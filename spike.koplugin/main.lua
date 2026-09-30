-- Plugin temporal de mediciones (spike) para KOReader Dashboard Screensaver.
-- Todas las líneas de log empiezan con "[spike]" y quedan en koreader/crash.log.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local NetworkMgr = require("ui/network/manager")
local Screensaver = require("ui/screensaver")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local time = require("ui/time")
local Screen = Device.screen

local DEFAULT_HTTP = "http://example.com/"
local DEFAULT_HTTPS = "https://example.com/"

local function now_ms() return time.to_ms(time.now()) end
local function log(...) logger.info("[spike]", os.date("%H:%M:%S"), ...) end
local function setting(key, default)
    local v = G_reader_settings:readSetting(key)
    if v == nil then return default end
    return v
end

-- Q1: registrar cuándo pinta el screensaver nativo (se envuelve una sola vez)
if not Screensaver._spike_wrapped then
    local orig_show = Screensaver.show
    Screensaver.show = function(self, ...)
        log("Screensaver.show t=", now_ms())
        return orig_show(self, ...)
    end
    Screensaver._spike_wrapped = true
end

-- Petición GET acotada: devuelve (resultado, ms)
local function probe(url, total_timeout)
    local sink = {}
    local t = now_ms()
    socketutil:set_timeout(1, total_timeout or 2.5)
    local is_https = url:match("^https") ~= nil
    local ok, code = pcall(function()
        -- HTTPS necesita ssl.https (hace el handshake TLS); http.request habla texto plano al puerto 443
        local req = { url = url, method = "GET", sink = socketutil.table_sink(sink) }
        if is_https then
            return socket.skip(1, require("ssl.https").request(req))
        end
        req.create = socketutil.tcp
        return socket.skip(1, http.request(req))
    end)
    socketutil:reset_timeout()
    local result = ok and tostring(code) or ("EXC " .. tostring(code))
    return result, now_ms() - t
end

local Spike = WidgetContainer:extend{
    name = "spike",
    is_doc_only = false,
}

function Spike:init()
    self.ui.menu:registerToMainMenu(self)
end

function Spike:onSuspend()
    local t0 = now_ms()
    log("onSuspend t=", t0,
        "online=", tostring(NetworkMgr:isOnline()),
        "wifi_on=", tostring(NetworkMgr:isWifiOn()),
        "screensaver_type=", tostring(G_reader_settings:readSetting("screensaver_type")))

    -- Q2: ¿hay red útil durante la suspensión?
    if G_reader_settings:isTrue("spike_net") then
        local res, ms = probe(setting("spike_url_http", DEFAULT_HTTP), 2.5)
        log("Q2 probe result=", res, "ms=", ms)
    end

    -- Q4: espera artificial antes de pintar
    local block = setting("spike_block_s", 0)
    if block > 0 then
        log("Q4 bloqueando", block, "s")
        ffiutil.sleep(block)
    end

    -- Q3: medir el pintado a pantalla completa
    local label = string.format("SPIKE %s  espera=%ds", os.date("%H:%M:%S"), block)
    self.widget = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
            TextWidget:new{ text = label, face = Font:getFace("tfont", 40) },
        },
    }
    local tp = now_ms()
    UIManager:show(self.widget)
    UIManager:setDirty(self.widget, "full")
    UIManager:forceRePaint()
    log("Q3 paint_ms=", now_ms() - tp, "total_ms=", now_ms() - t0, "label=", label)
end

function Spike:onResume()
    log("onResume t=", now_ms())
    if self.widget then
        UIManager:close(self.widget)
        self.widget = nil
        UIManager:setDirty("all", "full")
    end
end

-- Q5: 10 GET por HTTP y 10 por HTTPS al mismo host, con el Kindle despierto
local function bench()
    local lines = {}
    for _, spec in ipairs{ { "HTTP", setting("spike_url_http", DEFAULT_HTTP) },
                           { "HTTPS", setting("spike_url_https", DEFAULT_HTTPS) } } do
        local times = {}
        for i = 1, 10 do
            local res, ms = probe(spec[2], 10)
            log("Q5", spec[1], i, "result=", res, "ms=", ms)
            table.insert(times, ms)
        end
        table.sort(times)
        table.insert(lines, string.format("%s  min=%d  mediana=%d  max=%d ms",
            spec[1], times[1], times[5], times[10]))
    end
    local text = table.concat(lines, "\n")
    log("Q5 resumen\n" .. text)
    UIManager:show(InfoMessage:new{ text = "Resultados Q5:\n\n" .. text })
end

local function editUrl(key, title, default)
    local dlg
    dlg = InputDialog:new{
        title = title,
        input = setting(key, default),
        buttons = {{
            { text = "Cancelar", id = "close", callback = function() UIManager:close(dlg) end },
            { text = "Guardar", is_enter_default = true, callback = function()
                G_reader_settings:saveSetting(key, dlg:getInputText())
                UIManager:close(dlg)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

function Spike:addToMainMenu(menu_items)
    menu_items.spike_dashboard = {
        text = "Spike dashboard",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Q2 · Probar red al suspender",
                checked_func = function() return G_reader_settings:isTrue("spike_net") end,
                callback = function() G_reader_settings:flipNilOrFalse("spike_net") end,
            },
            {
                text_func = function()
                    return "Q4 · Espera antes de pintar: " .. setting("spike_block_s", 0) .. " s (toca para cambiar)"
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("spike_block_s", (setting("spike_block_s", 0) + 1) % 5)
                    touchmenu_instance:updateItems()
                end,
            },
            {
                text = "Q5 · Medir HTTP vs HTTPS (10 + 10)",
                callback = function()
                    UIManager:show(InfoMessage:new{ text = "Midiendo… (puede tardar ~30 s)", timeout = 2 })
                    UIManager:scheduleIn(2.5, bench)
                end,
            },
            {
                text = "Configurar URL HTTP de prueba",
                keep_menu_open = true,
                callback = function() editUrl("spike_url_http", "URL HTTP", DEFAULT_HTTP) end,
            },
            {
                text = "Configurar URL HTTPS de prueba",
                keep_menu_open = true,
                callback = function() editUrl("spike_url_https", "URL HTTPS", DEFAULT_HTTPS) end,
            },
        },
    }
end

return Spike
