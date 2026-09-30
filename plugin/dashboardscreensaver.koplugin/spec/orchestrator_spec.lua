local Orchestrator = require("dashboard/orchestrator")
local CacheManager = require("dashboard/cache_manager")
local MemFS = require("memfs")
local logger = require("logger")
local json = require("json")

local TOKEN = "s3cr3t-token-XYZ"
local PATH = "/cache/dashboard_cache.json"
local NOW = 1790181600 -- epoch fijo
local TODAY = os.date("%Y-%m-%d", NOW)

local function make_dto(over)
    local d = {
        v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = NOW, ttl_s = 900,
        tz = "America/Santiago", date = TODAY, weekday = 3, warnings = {}, events_total = 1,
        weather = { location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
                    icon = "cloudy", desc = "Nublado", pop = 10, hourly = {} },
        events = { { title = "Dentista", all_day = false, start = "18:30", ["end"] = "19:30" } },
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

-- Arma un orquestador con todo falso salvo el CacheManager (real, sobre memfs).
local function setup(opts)
    opts = opts or {}
    local s = { events = {}, ms = 0, now = NOW, fetches = {} }
    local function ev(name) s.events[#s.events + 1] = name end

    local cfg = {
        enabled = true,
        backend = { url = "http://192.168.1.10:8080/api/dashboard", token = TOKEN, connect_timeout_s = 1.0, total_timeout_s = 2.2 },
        cache = { min_refresh_interval_s = 600, stale_after_s = 10800, max_age_s = 86400 },
        display = { max_events = 8, show_hourly = true, show_location = true, anti_ghosting = "full" },
        debug = { log_timings = false },
    }
    for section, vals in pairs(opts.cfg or {}) do
        if type(vals) == "table" then for k, v in pairs(vals) do cfg[section][k] = v end else cfg[section] = vals end
    end

    local fs = MemFS.new()
    local cache = CacheManager.new({ path = PATH, fs = fs, json = json, now = function() return s.now end })
    local real_load, real_save, real_touch = cache.load, cache.save, cache.touch
    cache.load = function(self) ev("load"); s.ms = s.ms + (opts.load_ms or 0); return real_load(self) end
    cache.save = function(self, ...) ev("save"); return real_save(self, ...) end
    cache.touch = function(self) ev("touch"); return real_touch(self) end
    if opts.entry then
        s.now = NOW + (opts.entry_age or 0)
        cache.now = function() return NOW end -- se guardó "en el pasado"
        cache:save(opts.entry, opts.etag or 'W/"old"', "backend")
        cache.now = function() return s.now end
        s.events = {}
    end

    local client = { fetchData = function(_, onSuccess, onError, o)
        s.fetches[#s.fetches + 1] = o
        ev("fetch")
        s.ms = s.ms + (opts.fetch_ms or 0)
        if opts.client_throws then error("boom " .. TOKEN) end
        local r = opts.result or {}
        if r.err then return onError(r.err) end
        return onSuccess(r.dto, r.meta or {})
    end }

    s.vms = {}
    local o = Orchestrator.new({
        config = { cfg = cfg }, client = client, cache = cache,
        network = { isOnline = function() return opts.online ~= false end },
        ui = {
            show = function() ev("show") end, close = function() ev("close") end,
            setDirty = function(_, w, mode) ev("setDirty:" .. tostring(type(w) == "string" and w or "widget") .. ":" .. mode) end,
            forceRePaint = function() ev("forceRePaint") end,
            paintBlack = function() ev("paintBlack") end,
        },
        makeWidget = function(vm)
            if opts.widget_fails == true or (opts.widget_fails == "once" and #s.vms == 0) then
                s.vms[#s.vms + 1] = vm
                error("no cabe el árbol de widgets")
            end
            s.vms[#s.vms + 1] = vm
            return { vm = vm }
        end,
        readDevice = function() return { battery = 78, charging = false, date = TODAY, weekday = 3 } end,
        now_ms = function() return s.ms end,
        now = function() return s.now end,
        today = function() return TODAY end,
    })
    s.cfg, s.cache, s.fs = cfg, cache, fs
    function s.last_vm() return s.vms[#s.vms] end
    function s.index(name)
        for i, e in ipairs(s.events) do if e == name then return i end end
    end
    return o, s
end

local FRESH_RESULT = function() return { dto = make_dto({ events_total = 1 }), meta = { etag = 'W/"new"' } } end

describe("shouldFetch", function()
    local CFG = { min_refresh_interval_s = 600 }
    local URL = "http://x/"
    local function entry(validated_at, date) return { validated_at = validated_at, dto = { date = date or TODAY } } end

    it("sin URL no hace nada y avisa", function()
        assert.same({ false, "E_NOT_CONFIGURED" }, { Orchestrator.shouldFetch(nil, NOW, CFG, true, "") })
        assert.same({ false, "E_NOT_CONFIGURED" }, { Orchestrator.shouldFetch(entry(NOW), NOW, CFG, true, nil) })
    end)

    it("caché confirmado hace menos de min_refresh_interval_s: sin red y sin error", function()
        assert.same({ false, nil }, { Orchestrator.shouldFetch(entry(NOW - 599), NOW, CFG, true, URL) })
        assert.same({ false, nil }, { Orchestrator.shouldFetch(entry(NOW - 3), NOW, CFG, false, URL) })
    end)

    it("caché viejo con red → pide; sin red → E_NO_NETWORK", function()
        assert.same({ true, nil }, { Orchestrator.shouldFetch(entry(NOW - 600), NOW, CFG, true, URL) })
        assert.same({ false, "E_NO_NETWORK" }, { Orchestrator.shouldFetch(entry(NOW - 3600), NOW, CFG, false, URL) })
    end)

    it("sin caché: pide si hay red", function()
        assert.same({ true, nil }, { Orchestrator.shouldFetch(nil, NOW, CFG, true, URL) })
        assert.same({ false, "E_NO_NETWORK" }, { Orchestrator.shouldFetch(nil, NOW, CFG, false, URL) })
    end)

    it("un caché de otro día o con reloj en el futuro no cuenta como reciente", function()
        assert.same({ true, nil }, { Orchestrator.shouldFetch(entry(NOW - 10, "2020-01-01"), NOW, CFG, true, URL) })
        assert.same({ true, nil }, { Orchestrator.shouldFetch(entry(NOW + 500), NOW, CFG, true, URL) })
    end)

    it("min_refresh_interval_s = 0 fuerza la red siempre", function()
        assert.same({ true, nil }, { Orchestrator.shouldFetch(entry(NOW), NOW, { min_refresh_interval_s = 0 }, true, URL) })
    end)
end)

describe("runSuspend", function()
    before_each(function() logger.reset() end)

    it("camino feliz: pinta en vivo y guarda el caché DESPUÉS de pintar", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, result = FRESH_RESULT() })
        local info = o:runSuspend()
        assert.equals("live", info.origin)
        assert.equals("En vivo", s.last_vm().footer.left)
        assert.equals('W/"old"', s.fetches[1].etag) -- petición condicional
        local i = s.index
        assert.is_true(i("show") < i("setDirty:widget:full") and i("setDirty:widget:full") < i("forceRePaint"))
        assert.is_true(i("forceRePaint") < i("save"))
        assert.equals('W/"new"', s.cache:load().etag)
    end)

    it("caché reciente: no hay petición de red y aparece desde el caché", function()
        local o, s = setup({ entry = make_dto(), entry_age = 180 })
        local info = o:runSuspend()
        assert.equals(0, #s.fetches)
        assert.equals("cache", info.origin)
        assert.equals("Datos de hace 3 min", s.last_vm().footer.left)
        assert.is_nil(s.index("save"))
    end)

    it("modo avión: sin petición, caché de 2 h en el pie", function()
        local o, s = setup({ entry = make_dto(), entry_age = 2 * 3600, online = false })
        o:runSuspend()
        assert.equals(0, #s.fetches)
        assert.equals("Sin conexión · datos de hace 2 h", s.last_vm().footer.left)
    end)

    it("el timeout es el menor entre total_timeout_s y lo que queda menos 0.7 s", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, result = FRESH_RESULT() })
        o:runSuspend()
        assert.equals(2.2, s.fetches[1].timeout_s)

        o, s = setup({ entry = make_dto(), entry_age = 3600, result = FRESH_RESULT(), cfg = { backend = { total_timeout_s = 2.5 } } })
        o:runSuspend()
        assert.is_true(math.abs(s.fetches[1].timeout_s - 2.3) < 1e-9) -- 3.0 − 0.7

        o, s = setup({ entry = make_dto(), entry_age = 3600, result = FRESH_RESULT(), load_ms = 500 })
        o:runSuspend()
        assert.is_true(math.abs(s.fetches[1].timeout_s - 1.8) < 1e-9) -- (3.0 − 0.5) − 0.7
    end)

    it("un cliente lento recibe como máximo restante − 0.7 y el total no pasa de 3 s", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, load_ms = 100, fetch_ms = 2400,
                             result = { err = { code = "E_TIMEOUT", message = "timeout" } } })
        local t0 = s.ms
        o:runSuspend()
        local granted = s.fetches[1].timeout_s
        assert.is_true(granted <= (3000 - 100) / 1000 - 0.7 + 1e-9)
        assert.is_true(s.ms - t0 <= 3000)
        assert.equals("Servidor lento · datos de hace 1 h", s.last_vm().footer.left)
    end)

    it("sin presupuesto (< 0.5 s para la red) no se intenta la red", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, load_ms = 1900, result = FRESH_RESULT() })
        o:runSuspend() -- quedan 1.1 s − 0.7 = 0.4 s
        assert.equals(0, #s.fetches)
        assert.equals("Sin conexión · datos de hace 1 h", s.last_vm().footer.left)
    end)

    it("una excepción del cliente termina mostrando el caché", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, client_throws = true })
        local info = o:runSuspend()
        assert.equals("cache", info.origin)
        assert.equals("E_INTERNAL", info.err.code)
        assert.equals(1, #s.vms)
        assert.equals("Datos de hace 1 h", s.last_vm().footer.left)
        assert.is_nil(s.index("save"))
        assert.is_nil(logger.text():find(TOKEN, 1, true)) -- el mensaje de la excepción llevaba el token
    end)

    it("304: confirma el caché (touch), no lo regraba y se ve 'En vivo'", function()
        local o, s = setup({ entry = make_dto(), entry_age = 1200, result = { meta = { not_modified = true } } })
        local info = o:runSuspend()
        assert.equals("live", info.origin)
        assert.equals("En vivo", s.last_vm().footer.left)
        assert.is_not_nil(s.index("touch"))
        assert.is_nil(s.index("save"))
        assert.equals(NOW + 1200, s.cache:load().validated_at)
    end)

    it("una respuesta inválida no reemplaza ni borra el caché", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, result = { err = { code = "E_JSON_PARSE", message = "x" } } })
        o:runSuspend()
        assert.equals("Datos de hace 1 h", s.last_vm().footer.left ~= "" and "Datos de hace 1 h" or "")
        assert.equals("Respuesta inválida", s.last_vm().footer.left)
        assert.is_nil(s.index("save"))
        assert.equals('W/"old"', s.cache:load().etag)
    end)

    it("401 → 'Token inválido' con el caché", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, result = { err = { code = "E_AUTH", http_status = 401, message = "x" } } })
        o:runSuspend()
        assert.equals("Token inválido", s.last_vm().footer.left)
    end)

    it("HTTP 503 → 'Servidor HTTP 503'", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, result = { err = { code = "E_HTTP_STATUS", http_status = 503, message = "x" } } })
        o:runSuspend()
        assert.equals("Servidor HTTP 503", s.last_vm().footer.left)
    end)

    it("primera ejecución sin caché ni red: pantalla mínima", function()
        local o, s = setup({ online = false })
        o:runSuspend()
        assert.is_true(s.last_vm().minimal)
        assert.equals("Sin datos: conéctate a Wi-Fi para actualizar", s.last_vm().message)
        assert.equals(0, #s.fetches)
    end)

    it("backend sin configurar: sin petición y pie 'Configura el backend'", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, cfg = { backend = { url = "" } } })
        o:runSuspend()
        assert.equals(0, #s.fetches)
        assert.equals("Configura el backend", s.last_vm().footer.left)
    end)

    it("plugin desactivado: no interviene", function()
        local o, s = setup({ entry = make_dto(), entry_age = 3600, cfg = { enabled = false } })
        assert.is_nil(o:runSuspend())
        assert.same({}, s.events)
    end)

    it("si falla el árbol de widgets, cae a la pantalla mínima", function()
        local o, s = setup({ entry = make_dto(), entry_age = 180, widget_fails = "once" })
        o:runSuspend()
        assert.equals(2, #s.vms)
        assert.is_true(s.last_vm().minimal)
        assert.is_not_nil(s.index("show"))
    end)

    it("si falla también la pantalla mínima, el error sube y no se pinta nada", function()
        local o, s = setup({ entry = make_dto(), entry_age = 180, widget_fails = true })
        assert.has_error(function() o:runSuspend() end)
        assert.is_nil(s.index("show"))
    end)

    it("anti_ghosting = double pinta negro antes del dashboard", function()
        local o, s = setup({ entry = make_dto(), entry_age = 180, cfg = { display = { anti_ghosting = "double" } } })
        o:runSuspend()
        assert.is_true(s.index("paintBlack") < s.index("show"))
        o, s = setup({ entry = make_dto(), entry_age = 180 })
        o:runSuspend()
        assert.is_nil(s.index("paintBlack"))
    end)

    it("log_timings: registra código de error y tiempos, nunca el token", function()
        local o = setup({ entry = make_dto(), entry_age = 3600, cfg = { debug = { log_timings = true } },
                          result = { err = { code = "E_AUTH", http_status = 401, message = "token " .. TOKEN } } })
        o:runSuspend()
        local text = logger.text()
        assert.truthy(text:find("E_AUTH", 1, true))
        assert.truthy(text:find("total=", 1, true))
        assert.is_nil(text:find(TOKEN, 1, true))
    end)

    it("sin log_timings no escribe la línea de tiempos", function()
        local o = setup({ entry = make_dto(), entry_age = 180 })
        o:runSuspend()
        assert.is_nil(logger.text():find("total=", 1, true))
    end)
end)

describe("dismiss", function()
    it("cierra el widget y repinta todo con refresco completo; el segundo dismiss no hace nada", function()
        local o, s = setup({ entry = make_dto(), entry_age = 180 })
        o:runSuspend()
        s.events = {}
        o:dismiss()
        assert.same({ "close", "setDirty:all:full" }, s.events)
        s.events = {}
        o:dismiss()
        assert.same({}, s.events)
    end)

    it("sin dashboard visible no toca la pantalla", function()
        local o, s = setup()
        o:dismiss()
        assert.same({}, s.events)
    end)
end)

describe("runInteractive", function()
    it("refrescar fuerza la red aunque el caché sea reciente y no pinta", function()
        local o, s = setup({ entry = make_dto(), entry_age = 30, result = FRESH_RESULT() })
        local r = o:runInteractive({ force_fetch = true, show = false })
        assert.equals(1, #s.fetches)
        assert.equals(2.2, s.fetches[1].timeout_s) -- sin presupuesto de 3 s
        assert.equals("live", r.origin)
        assert.is_nil(s.index("show"))
        assert.is_not_nil(s.index("save"))
    end)

    it("refrescar con el backend caído devuelve el error y no cambia el caché", function()
        local o, s = setup({ entry = make_dto(), entry_age = 30, result = { err = { code = "E_HTTP_STATUS", http_status = 503, message = "HTTP 503" } } })
        local r = o:runInteractive({ force_fetch = true, show = false })
        assert.equals("E_HTTP_STATUS", r.err.code)
        assert.equals(503, r.err.http_status)
        assert.equals('W/"old"', s.cache:load().etag)
        assert.is_nil(s.index("save"))
    end)

    it("refrescar sin red devuelve E_NO_NETWORK sin intentar la petición", function()
        local o, s = setup({ entry = make_dto(), entry_age = 30, online = false })
        local r = o:runInteractive({ force_fetch = true, show = false })
        assert.equals("E_NO_NETWORK", r.err.code)
        assert.equals(0, #s.fetches)
    end)

    it("vista previa: pinta el dashboard y pasa on_tap a la vista", function()
        local got
        local o, s = setup({ entry = make_dto(), entry_age = 30 })
        local orig = o.d.makeWidget
        o.d.makeWidget = function(vm, display, opts) got = opts; return orig(vm, display, opts) end
        o:runInteractive({ show = true, on_tap = "cb" })
        assert.is_not_nil(s.index("show"))
        assert.equals("cb", got.on_tap)
    end)
end)

describe("vista previa y estado", function()
    it("no_network: pinta el caché sin pedir datos aunque esté viejo", function()
        local o, s = setup({ entry = make_dto(), entry_age = 5 * 3600, result = FRESH_RESULT() })
        o:runInteractive({ no_network = true, show = true })
        assert.equals(0, #s.fetches)
        assert.is_not_nil(s.index("show"))
    end)

    it("status devuelve el caché, su frescura y el último resultado", function()
        local o = setup({ entry = make_dto(), entry_age = 3600, result = { err = { code = "E_TIMEOUT" } } })
        assert.is_nil(o:status().last)
        o:runSuspend()
        local st = o:status()
        assert.equals("backend", st.entry.provider)
        assert.equals("E_TIMEOUT", st.last.err.code)
        assert.is_number(st.last.timings.net)
        assert.equals("cache", st.freshness.origin)
    end)
end)
