-- Dashboard de suspensión para KOReader.
--
-- Punto de enganche (design D2): estrategia A, `onSuspend`. Requiere que la pantalla de suspensión
-- nativa de KOReader esté en "Desactivada". Si el spike (tarea 1.1) muestra que el screensaver
-- nativo pisa el dashboard, la estrategia B envuelve `Screensaver.show` en lugar de `onSuspend`;
-- sólo cambia este archivo, el orquestador es el mismo.
--
-- Todos los require de módulos del plugin van arriba: KOReader sólo añade la carpeta del plugin
-- a package.path mientras carga este archivo.
local DataStorage = require("datastorage")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local BackendClient = require("dashboard/backend_client")
local CacheManager = require("dashboard/cache_manager")
local Config = require("dashboard/config")
local DashboardWidget = require("dashboard/dashboard_widget")
local Orchestrator = require("dashboard/orchestrator")
local ViewModel = require("dashboard/view_model")
local redact = require("dashboard/redact")

local Screen = Device.screen

-- Adaptador de UIManager para el orquestador (que lo recibe por inyección y usa `:`).
local ui = {}
function ui:show(widget) UIManager:show(widget) end
function ui:close(widget) UIManager:close(widget) end
function ui:setDirty(widget, mode) UIManager:setDirty(widget, mode) end
function ui:forceRePaint() UIManager:forceRePaint() end
function ui:paintBlack() -- anti_ghosting = "double": flash negro completo antes del dashboard
    local black = FrameContainer:new{
        background = Blitbuffer.COLOR_BLACK, bordersize = 0, margin = 0, padding = 0,
        width = Screen:getWidth(), height = Screen:getHeight(),
        HorizontalSpan:new{ width = 1 },
    }
    UIManager:show(black)
    UIManager:setDirty(black, "full")
    UIManager:forceRePaint()
    UIManager:close(black)
end

local DashboardScreensaver = WidgetContainer:extend{
    name = "dashboardscreensaver",
    is_doc_only = false,
}

function DashboardScreensaver:init()
    local settings_path = DataStorage:getSettingsDir() .. "/dashboardscreensaver/settings.json"
    local cache_path = DataStorage:getDataDir() .. "/cache/dashboardscreensaver/dashboard_cache.json"
    local icons_root = self.path .. "/"

    self.config = Config.new(settings_path)
    self.config:load()
    self.orchestrator = Orchestrator.new({
        config = self.config,
        client = BackendClient.new(self.config),
        cache = CacheManager.new({ path = cache_path }),
        network = NetworkMgr,
        ui = ui,
        makeWidget = function(vm, display, opts)
            return DashboardWidget:new{
                view_model = vm, display = display, icons_root = icons_root, on_tap = opts and opts.on_tap,
            }
        end,
    })
    self.ui.menu:registerToMainMenu(self)
end

-- Registra un fallo sin exponer nunca el token
function DashboardScreensaver:_logFailure(what, err)
    logger.err("[dashboard] " .. what, redact(err, self.config.cfg.backend.token))
end

function DashboardScreensaver:onSuspend()
    local ok, err = pcall(self.orchestrator.runSuspend, self.orchestrator)
    if not ok then self:_logFailure("suspend failed", err) end
    -- No devolver true: consumiría el evento que necesitan otros plugins (p. ej. AutoSuspend)
end

function DashboardScreensaver:onResume()
    local ok, err = pcall(self.orchestrator.dismiss, self.orchestrator)
    if not ok then self:_logFailure("resume failed", err) end
end

-- La estrategia A sólo funciona con la pantalla de suspensión nativa desactivada
function DashboardScreensaver:_warnNativeScreensaver()
    if G_reader_settings:readSetting("screensaver_type") ~= "disable" then
        UIManager:show(InfoMessage:new{
            text = _("Para ver el dashboard, ve a Pantalla → Pantalla de suspensión y elige «Desactivada»."),
        })
    end
end

function DashboardScreensaver:_preview()
    local ok, err = pcall(self.orchestrator.runInteractive, self.orchestrator, {
        show = true, no_network = true, on_tap = function() self.orchestrator:dismiss() end,
    })
    if not ok then
        self:_logFailure("preview failed", err)
        UIManager:show(InfoMessage:new{ text = _("No se pudo mostrar la vista previa (ver crash.log).") })
    end
end

function DashboardScreensaver:_refresh()
    UIManager:show(InfoMessage:new{ text = _("Actualizando…"), timeout = 1 })
    UIManager:forceRePaint() -- que el mensaje se vea antes de que la red bloquee el hilo
    local ok, res = pcall(self.orchestrator.runInteractive, self.orchestrator, { force_fetch = true, show = false })
    local msg
    if not ok then
        self:_logFailure("refresh failed", res)
        msg = _("Error interno al actualizar (ver crash.log).")
    elseif res.err then
        msg = _("No se pudo actualizar: ") .. ViewModel.errorText(res.err)
    else
        msg = _("Datos actualizados") .. (" (%d ms)"):format(res.elapsed_ms)
    end
    UIManager:show(InfoMessage:new{ text = msg })
end

function DashboardScreensaver:_showStatus()
    local ok, res = pcall(self.orchestrator.status, self.orchestrator)
    UIManager:show(InfoMessage:new{ text = ok and ViewModel.statusText(res) or _("No se pudo leer el estado del caché.") })
end

function DashboardScreensaver:addToMainMenu(menu_items)
    menu_items.dashboard_screensaver = {
        text = _("Dashboard de suspensión"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Activar dashboard"),
                checked_func = function() return self.config.cfg.enabled end,
                keep_menu_open = true,
                callback = function()
                    local enable = not self.config.cfg.enabled
                    local ok, err = self.config:set("enabled", enable)
                    if not ok then
                        UIManager:show(InfoMessage:new{ text = _("No se pudo guardar el ajuste: ") .. tostring(err) })
                    elseif enable then
                        self:_warnNativeScreensaver()
                    end
                end,
            },
            { text = _("Vista previa ahora"), callback = function() self:_preview() end },
            { text = _("Refrescar datos ahora"), callback = function() self:_refresh() end },
            { text = _("Ver estado del caché"), callback = function() self:_showStatus() end },
        },
    }
end

return DashboardScreensaver
