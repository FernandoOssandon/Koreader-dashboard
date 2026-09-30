local VM = require("dashboard/view_model")

local DEVICE = { battery = 78, charging = false, date = "2026-09-23", weekday = 3 }
local DISPLAY = { max_events = 8, show_hourly = true, show_location = true }

local function weather()
    return {
        location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
        icon = "partly_cloudy_day", desc = "Parcialmente nublado", pop = 10,
        hourly = {
            { time = "16:00", temp = 21, icon = "clear_day" },
            { time = "19:00", temp = 17, icon = "partly_cloudy_night" },
        },
    }
end

local function events(n)
    local out = {}
    for i = 1, n do
        out[i] = { title = "Evento " .. i, all_day = false, start = "1" .. i .. ":00", ["end"] = "1" .. i .. ":30",
                   location = "Sala " .. i }
    end
    return out
end

local function dto(opts)
    opts = opts or {}
    local d = {
        v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = 1,
        date = "2026-09-23", weekday = 3, warnings = {}, events_total = 0,
    }
    if opts.weather ~= false then d.weather = weather() end
    if opts.events ~= nil then
        d.events = events(opts.events)
        d.events_total = opts.total or opts.events
    end
    return d
end

local LIVE = { origin = "live", age_s = 0, level = "fresh" }
local function cache(age, level, extra)
    local f = { origin = "cache", age_s = age, level = level }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

describe("view_model: contenido", function()
    it("pantalla completa con datos en vivo", function()
        local vm = VM.build(dto({ events = 3 }), DEVICE, LIVE, DISPLAY)
        assert.is_false(vm.minimal)
        assert.equals("Miércoles 23 de septiembre", vm.header.title)
        assert.equals("Santiago · Actualizado 13:40", vm.header.subtitle)
        assert.equals("18°", vm.weather.temp)
        assert.equals("icons/partly_cloudy_day_96.png", vm.weather.icon_path)
        assert.equals("Parcialmente nublado", vm.weather.desc)
        assert.equals("Mín 9° · Máx 22°", vm.weather.range)
        assert.equals("Lluvia 10%", vm.weather.extra)
        assert.equals(2, #vm.weather.hourly)
        assert.equals("icons/clear_day_48.png", vm.weather.hourly[1].icon_path)
        assert.equals(3, #vm.agenda.rows)
        assert.equals("11:00–11:30", vm.agenda.rows[1].time)
        assert.equals("Sala 1", vm.agenda.rows[1].sub)
        assert.is_nil(vm.agenda.more)
        assert.is_nil(vm.agenda_placeholder)
        assert.equals("En vivo", vm.footer.left)
        assert.is_false(vm.footer.warn)
        assert.equals("Batería 78%", vm.footer.right)
    end)

    it("todo el día va como 'Todo el día'", function()
        local d = dto({ events = 0 })
        d.events = { { title = "Feriado", all_day = true }, { title = "X", all_day = false, start = "10:00", ["end"] = "11:00" } }
        d.events_total = 2
        local vm = VM.build(d, DEVICE, LIVE, DISPLAY)
        assert.equals("Todo el día", vm.agenda.rows[1].time)
    end)

    it("show_location = false oculta el lugar y la ubicación de la cabecera", function()
        local vm = VM.build(dto({ events = 1 }), DEVICE, LIVE, { max_events = 8, show_location = false })
        assert.is_nil(vm.agenda.rows[1].sub)
        assert.equals("Actualizado 13:40", vm.header.subtitle)
    end)

    it("show_hourly = false quita las franjas", function()
        local vm = VM.build(dto({ events = 1 }), DEVICE, LIVE, { max_events = 8, show_hourly = false })
        assert.equals(0, #vm.weather.hourly)
    end)

    it("sin eventos", function()
        local vm = VM.build(dto({ events = 0 }), DEVICE, LIVE, DISPLAY)
        assert.equals("Sin eventos hoy", vm.agenda_placeholder)
        assert.equals(0, #vm.agenda.rows)
    end)

    it("agenda nula y clima nulo", function()
        local vm = VM.build(dto({ weather = false }), DEVICE, LIVE, DISPLAY)
        assert.equals("Agenda no disponible", vm.agenda_placeholder)
        assert.equals("Clima no disponible", vm.weather_placeholder)
        assert.is_nil(vm.weather)
    end)

    it("8 eventos de 10: '+2 más'", function()
        local vm = VM.build(dto({ events = 8, total = 10 }), DEVICE, LIVE, DISPLAY)
        assert.equals(8, #vm.agenda.rows)
        assert.equals("+2 más", vm.agenda.more)
        assert.equals(10, vm.agenda.total)
    end)

    it("max_events de la configuración limita las filas", function()
        local vm = VM.build(dto({ events = 5 }), DEVICE, LIVE, { max_events = 3 })
        assert.equals(3, #vm.agenda.rows)
        assert.equals("+2 más", vm.agenda.more)
    end)

    it("batería no disponible y en carga", function()
        assert.equals("Batería —", VM.build(dto({ events = 1 }), { date = "x", weekday = 1 }, LIVE, DISPLAY).footer.right)
        assert.equals("Batería 64% · cargando",
            VM.build(dto({ events = 1 }), { battery = 64, charging = true }, LIVE, DISPLAY).footer.right)
    end)
end)

describe("view_model: pie y frescura", function()
    local function footer(f) return VM.build(dto({ events = 1 }), DEVICE, f, DISPLAY).footer end

    it("caché fresco sin intento de red", function()
        local f = footer(cache(180, "fresh"))
        assert.equals("Datos de hace 3 min", f.left)
        assert.is_false(f.warn)
    end)

    it("modo avión con caché de 2 h", function()
        local f = footer(cache(2 * 3600, "fresh", { err = "E_NO_NETWORK" }))
        assert.equals("Sin conexión · datos de hace 2 h", f.left)
        assert.is_true(f.warn)
    end)

    it("datos de 5 h sin red: aviso de antigüedad y la agenda se muestra", function()
        local vm = VM.build(dto({ events = 2 }), DEVICE, cache(5 * 3600, "stale", { err = "E_NO_NETWORK" }), DISPLAY)
        assert.equals("⚠ Datos de hace 5 h", vm.footer.left)
        assert.is_true(vm.footer.warn)
        assert.equals(2, #vm.agenda.rows)
        assert.is_nil(vm.agenda_placeholder)
        assert.is_nil(vm.weather.note)
    end)

    it("datos de ayer: agenda desactualizada y clima con aviso", function()
        local vm = VM.build(dto({ events = 2 }), DEVICE, cache(3600, "expired", { reason = "date" }), DISPLAY)
        assert.equals("Agenda desactualizada", vm.agenda_placeholder)
        assert.equals(0, #vm.agenda.rows)
        assert.equals("Datos del 23 de septiembre", vm.weather.note)
        assert.is_true(vm.footer.warn)
    end)

    it("expirado por antigüedad y por reloj", function()
        local vm = VM.build(dto({ events = 1 }), DEVICE, cache(3 * 86400, "expired", { reason = "age" }), DISPLAY)
        assert.equals("Datos de hace 3 días", vm.weather.note)
        vm = VM.build(dto({ events = 1 }), DEVICE, cache(0, "expired", { reason = "clock" }), DISPLAY)
        assert.equals("Datos de antigüedad desconocida", vm.weather.note)
    end)

    local ERRORS = {
        { { err = "E_TIMEOUT" }, "Servidor lento · datos de hace 1 h" },
        { { err = "E_BUDGET_EXCEEDED" }, "Sin conexión · datos de hace 1 h" },
        { { err = "E_TLS" }, "Error TLS" },
        { { err = "E_AUTH" }, "Token inválido" },
        { { err = "E_HTTP_STATUS", err_status = 503 }, "Servidor HTTP 503" },
        { { err = "E_PAYLOAD_TOO_LARGE" }, "Respuesta inválida" },
        { { err = "E_JSON_PARSE" }, "Respuesta inválida" },
        { { err = "E_SCHEMA" }, "Versión incompatible" },
        { { err = "E_NOT_CONFIGURED" }, "Configura el backend" },
    }
    for _, case in ipairs(ERRORS) do
        it("error " .. case[1].err, function()
            assert.equals(case[2], footer(cache(3600, "fresh", case[1])).left)
        end)
    end

    it("los errores accionables se muestran aunque los datos sean viejos", function()
        assert.equals("Token inválido", footer(cache(6 * 3600, "stale", { err = "E_AUTH" })).left)
        assert.equals("Configura el backend", footer(cache(6 * 3600, "stale", { err = "E_NOT_CONFIGURED" })).left)
    end)

    it("un error interno no oculta la antigüedad", function()
        assert.equals("Datos de hace 1 h", footer(cache(3600, "fresh", { err = "E_INTERNAL" })).left)
    end)
end)

describe("view_model: sin datos", function()
    it("pantalla mínima con fecha del dispositivo, batería y mensaje", function()
        local vm = VM.build(nil, DEVICE, { origin = "none", level = "expired", err = "E_NO_NETWORK" }, DISPLAY)
        assert.is_true(vm.minimal)
        assert.equals("Miércoles 23 de septiembre", vm.header.title)
        assert.equals("Sin datos: conéctate a Wi-Fi para actualizar", vm.message)
        assert.equals("Batería 78%", vm.footer.right)
        assert.equals("Sin conexión", vm.footer.left)
    end)

    it("sin caché y backend sin configurar", function()
        local vm = VM.build(nil, DEVICE, { origin = "none", level = "expired", err = "E_NOT_CONFIGURED" }, DISPLAY)
        assert.equals("Configura el backend", vm.footer.left)
    end)
end)

describe("view_model: tabla de verdad", function()
    -- origen × clima × eventos × frescura: nunca falla y siempre da pie, cabecera y agenda coherentes
    local origins = {
        { LIVE }, { cache(60, "fresh") }, { cache(4 * 3600, "stale") },
        { cache(3600, "expired", { reason = "date" }) },
    }
    local event_cases = { { nil, "Agenda no disponible" }, { 0, "Sin eventos hoy" }, { 3, false } }
    for _, o in ipairs(origins) do
        for _, has_weather in ipairs({ true, false }) do
            for _, e in ipairs(event_cases) do
                local f = o[1]
                local name = ("%s/%s clima=%s eventos=%s"):format(f.origin, f.level, tostring(has_weather), tostring(e[1]))
                it(name, function()
                    local vm = VM.build(dto({ weather = has_weather, events = e[1] }), DEVICE, f, DISPLAY)
                    assert.equals(has_weather, vm.weather ~= nil)
                    assert.equals(not has_weather, vm.weather_placeholder ~= nil)
                    local expired = f.level == "expired"
                    if expired then
                        assert.equals("Agenda desactualizada", vm.agenda_placeholder)
                    elseif e[2] then
                        assert.equals(e[2], vm.agenda_placeholder)
                    else
                        assert.is_nil(vm.agenda_placeholder)
                        assert.equals(3, #vm.agenda.rows)
                    end
                    assert.is_string(vm.footer.left)
                    assert.equals(f.origin ~= "live" and f.level ~= "fresh", vm.footer.warn)
                end)
            end
        end
    end
end)

describe("view_model.readDevice", function()
    it("lee batería y carga", function()
        local d = VM.readDevice({ powerd = { getCapacity = function() return 64 end, isCharging = function() return true end } })
        assert.equals(64, d.battery)
        assert.is_true(d.charging)
        assert.truthy(d.date:match("^%d%d%d%d%-%d%d%-%d%d$"))
        assert.is_true(d.weekday >= 1 and d.weekday <= 7)
    end)

    it("si el dispositivo falla, no lanza y deja la batería en nil", function()
        local d = VM.readDevice({ powerd = {
            getCapacity = function() error("sin fuel gauge") end,
            isCharging = function() error("boom") end,
        } })
        assert.is_nil(d.battery)
        assert.is_nil(d.charging)
        assert.is_string(d.date)
    end)
end)

describe("view_model: textos del menú", function()
    it("errorText", function()
        assert.equals("Token inválido", VM.errorText({ code = "E_AUTH" }))
        assert.equals("El servidor respondió HTTP 503", VM.errorText({ code = "E_HTTP_STATUS", http_status = 503 }))
        assert.equals("E_RARO", VM.errorText({ code = "E_RARO" }))
    end)

    it("statusText con caché y último error", function()
        local text = VM.statusText({
            entry = { provider = "backend", dto = { date = "2026-09-23" } },
            freshness = { age_s = 2 * 3600, level = "fresh" },
            last = { err = { code = "E_TIMEOUT" }, timings = { cache = 12, net = 2200 } },
        })
        assert.truthy(text:find("Origen: backend", 1, true))
        assert.truthy(text:find("Antigüedad: hace 2 h (reciente)", 1, true))
        assert.truthy(text:find("Fecha de los datos: 2026-09-23", 1, true))
        assert.truthy(text:find("Último error: El servidor tardó demasiado en responder", 1, true))
        assert.truthy(text:find("Tiempos: caché 12 ms · red 2200 ms", 1, true))
    end)

    it("statusText sin caché ni ejecuciones", function()
        local text = VM.statusText({ freshness = { level = "expired" } })
        assert.truthy(text:find("Caché: vacío", 1, true))
        assert.truthy(text:find("Aún no hubo ninguna ejecución", 1, true))
    end)
end)
