-- Prueba de humo de main.lua con stubs de KOReader: el cableado real (config, caché, orquestador,
-- vista, menú) sin dispositivo. No sustituye a la prueba en el emulador o en el Kindle.
local kostubs = require("kostubs")
kostubs.install()
local logger = require("logger")
local json = require("json")

local ROOT = "/tmp/kodash-main-spec"
local SETTINGS = ROOT .. "/settings/dashboardscreensaver/settings.json"
local CACHE = ROOT .. "/data/cache/dashboardscreensaver/dashboard_cache.json"

local uim = { calls = {}, shown = {} }
function uim:show(w) self.calls[#self.calls + 1] = "show"; self.shown[#self.shown + 1] = w; if self.fail then error(self.fail) end end
function uim:close() self.calls[#self.calls + 1] = "close" end
function uim:setDirty(_, mode) self.calls[#self.calls + 1] = "setDirty:" .. tostring(mode) end
function uim:forceRePaint() self.calls[#self.calls + 1] = "forceRePaint" end

local network = { online = false }
function network:isOnline() return self.online end

package.preload["datastorage"] = function()
    return { getSettingsDir = function() return ROOT .. "/settings" end, getDataDir = function() return ROOT .. "/data" end }
end
package.preload["ui/uimanager"] = function() return uim end
package.preload["ui/network/manager"] = function() return network end
package.preload["ui/widget/infomessage"] = function()
    return { new = function(_, o) o.is_info = true; return o end }
end
package.preload["gettext"] = function() return function(s) return s end end
-- Red y reloj: sólo hace falta que existan (con el Wi-Fi apagado nunca se llega a pedir nada)
package.preload["ui/time"] = function()
    return { now = function() return os.clock() * 1000 end, to_ms = function(t) return t end }
end
package.preload["socket.http"] = function() return { request = function() error("no debería haber red") end } end
package.preload["socket"] = function() return { skip = function(n, ...) return select(n + 1, ...) end } end
package.preload["socketutil"] = function()
    return { set_timeout = function() end, reset_timeout = function() end, table_sink = function() end, tcp = function() end }
end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() return nil end, mkdir = function(p) os.execute("mkdir -p '" .. p .. "'"); return true end }
end
_G.G_reader_settings = { readSetting = function() return _G.SCREENSAVER_TYPE end }

local Plugin = dofile("main.lua")

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a"); f:close()
    return s
end

local function write(path, s)
    os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
    local f = assert(io.open(path, "wb")); f:write(s); f:close()
end

local menu_owner
local function new_plugin()
    kostubs.set_screen(600, 800)
    return Plugin:new{ path = ".", ui = { menu = { registerToMainMenu = function(_, p) menu_owner = p end } } }
end

local function find_item(plugin, text)
    local items = {}
    plugin:addToMainMenu(items)
    for _, it in ipairs(items.dashboard_screensaver.sub_item_table) do
        if it.text == text then return it end
    end
end

local function last_info() for i = #uim.shown, 1, -1 do if uim.shown[i].is_info then return uim.shown[i] end end end

describe("main.lua (con stubs)", function()
    before_each(function()
        os.execute("rm -rf " .. ROOT)
        uim.calls, uim.shown, uim.fail = {}, {}, nil
        network.online = false
        _G.SCREENSAVER_TYPE = "disable"
        logger.reset()
    end)

    it("al iniciar crea settings.json con los defaults y se registra en el menú", function()
        local p = new_plugin()
        assert.equals(p, menu_owner)
        local cfg = json.decode(read(SETTINGS))
        assert.is_true(cfg.enabled)
        assert.equals("", cfg.backend.url)
    end)

    it("el menú tiene las cuatro acciones", function()
        local p = new_plugin()
        local items = {}
        p:addToMainMenu(items)
        local texts = {}
        for _, it in ipairs(items.dashboard_screensaver.sub_item_table) do texts[#texts + 1] = it.text end
        assert.same({ "Activar dashboard", "Vista previa ahora", "Refrescar datos ahora", "Ver estado del caché" }, texts)
    end)

    it("onSuspend con el backend sin configurar pinta la pantalla mínima y NO devuelve true", function()
        local p = new_plugin()
        local ret = p:onSuspend()
        assert.is_nil(ret)
        assert.same({ "show", "setDirty:full", "forceRePaint" }, uim.calls)
        assert.is_true(uim.shown[1].view_model.minimal)
        assert.equals("Configura el backend", uim.shown[1].view_model.footer.left)
    end)

    it("onResume cierra el dashboard y repinta todo con refresco completo", function()
        local p = new_plugin()
        p:onSuspend()
        uim.calls = {}
        assert.is_nil(p:onResume())
        assert.same({ "close", "setDirty:full" }, uim.calls)
    end)

    it("usa el caché existente cuando no hay red", function()
        local p = new_plugin()
        write(SETTINGS, json.encode({ backend = { url = "http://192.168.1.10:8080/api/dashboard", token = "x" } }))
        p = new_plugin()
        local today = os.date("%Y-%m-%d")
        write(CACHE, json.encode({
            cache_version = 1, saved_at = os.time() - 7200, validated_at = os.time() - 7200, provider = "backend",
            dto = { v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = 1, ttl_s = 900,
                    tz = "x", date = today, weekday = 3, warnings = {}, events_total = 0, events = {},
                    weather = { location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
                                icon = "cloudy", desc = "Nublado", pop = 10, hourly = {} } },
        }))
        p:onSuspend()
        local vm = uim.shown[1].view_model
        assert.is_false(vm.minimal)
        assert.equals("Sin conexión · datos de hace 2 h", vm.footer.left)
    end)

    it("una excepción al pintar se registra como 'suspend failed', sin el token, y no se propaga", function()
        write(SETTINGS, json.encode({ backend = { url = "http://x/", token = "TOKEN-SECRETO" } }))
        local p = new_plugin()
        uim.fail = "boom con TOKEN-SECRETO"
        assert.has_no.errors(function() p:onSuspend() end)
        local text = logger.text()
        assert.truthy(text:find("[dashboard] suspend failed", 1, true))
        assert.is_nil(text:find("TOKEN-SECRETO", 1, true))
    end)

    it("plugin desactivado: no interviene", function()
        write(SETTINGS, json.encode({ enabled = false }))
        local p = new_plugin()
        p:onSuspend()
        assert.same({}, uim.calls)
    end)

    it("'Activar dashboard' alterna y guarda enabled; al activar avisa si la pantalla nativa no está desactivada", function()
        local p = new_plugin()
        local item = find_item(p, "Activar dashboard")
        assert.is_true(item.checked_func())
        item.callback()
        assert.is_false(item.checked_func())
        assert.is_false(json.decode(read(SETTINGS)).enabled)
        assert.is_nil(last_info()) -- al desactivar no hay aviso

        _G.SCREENSAVER_TYPE = "cover"
        item.callback()
        assert.is_true(json.decode(read(SETTINGS)).enabled)
        assert.truthy(last_info().text:find("Desactivada", 1, true))

        uim.shown = {}
        _G.SCREENSAVER_TYPE = "disable"
        item.callback(); item.callback()
        assert.is_nil(last_info()) -- ya está desactivada: sin aviso
    end)

    it("'Vista previa ahora' muestra el dashboard y un toque lo cierra", function()
        local p = new_plugin()
        find_item(p, "Vista previa ahora").callback()
        local w = uim.shown[#uim.shown]
        assert.is_not_nil(w.view_model)
        uim.calls = {}
        w:onTap()
        assert.same({ "close", "setDirty:full" }, uim.calls)
    end)

    it("'Refrescar datos ahora' con el backend sin configurar muestra un error legible", function()
        local p = new_plugin()
        find_item(p, "Refrescar datos ahora").callback()
        assert.truthy(last_info().text:find("No se pudo actualizar: El backend no está configurado", 1, true))
    end)

    it("'Ver estado del caché' informa del caché vacío y de la falta de ejecuciones", function()
        local p = new_plugin()
        find_item(p, "Ver estado del caché").callback()
        assert.truthy(last_info().text:find("Caché: vacío", 1, true))
    end)
end)
