-- DTO + estado del dispositivo + frescura → ViewModel con todos los textos ya resueltos.
-- No depende de la red ni de proveedores (regla de D1); la vista sólo pinta lo que sale de aquí.
local F = require("dashboard/format_es")

local ViewModel = {}

local MSG_NO_DATA = "Sin datos: conéctate a Wi-Fi para actualizar"

local ERR_TEXT = {
    E_NOT_CONFIGURED = "Configura el backend",
    E_TLS = "Error TLS",
    E_AUTH = "Token inválido",
    E_PAYLOAD_TOO_LARGE = "Respuesta inválida",
    E_JSON_PARSE = "Respuesta inválida",
    E_SCHEMA = "Versión incompatible",
}
-- Errores que el usuario debe corregir: se muestran aunque los datos sean viejos
local ACTIONABLE = { E_NOT_CONFIGURED = true, E_AUTH = true, E_SCHEMA = true, E_TLS = true }

--- Texto y aviso del pie izquierdo según el origen, la frescura y el último error.
local function footerLeft(f)
    if f.origin == "live" then return "En vivo", false end
    local age = f.age_s and F.ageLabel(f.age_s) or nil
    local code = f.err

    if code == "E_HTTP_STATUS" then
        return "Servidor HTTP " .. tostring(f.err_status or "?"), true
    elseif code and ERR_TEXT[code] then
        if not ACTIONABLE[code] and f.origin == "cache" and f.level ~= "fresh" then
            return "⚠ Datos de " .. age, true
        end
        return ERR_TEXT[code], true
    elseif code == "E_NO_NETWORK" or code == "E_BUDGET_EXCEEDED" or code == "E_TIMEOUT" then
        if f.origin == "cache" and f.level ~= "fresh" then return "⚠ Datos de " .. age, true end
        local label = code == "E_TIMEOUT" and "Servidor lento" or "Sin conexión"
        return age and (label .. " · datos de " .. age) or label, true
    end

    if f.origin == "cache" then -- sin intento de red (caché reciente) o error interno
        if f.level == "fresh" then return "Datos de " .. age, false end
        return "⚠ Datos de " .. age, true
    end
    return "", false
end

local function footerRight(device)
    if type(device.battery) ~= "number" then return "Batería —" end
    return ("Batería %d%%%s"):format(device.battery, device.charging and " · cargando" or "")
end

local function buildWeather(w, f, dto)
    local hourly = {}
    for _, h in ipairs(w.hourly or {}) do
        hourly[#hourly + 1] = {
            time = h.time, temp = h.temp .. "°", icon_path = ("icons/%s_48.png"):format(h.icon),
        }
    end
    local vm = {
        temp = w.temp .. "°",
        icon_path = ("icons/%s_96.png"):format(w.icon),
        desc = w.desc,
        range = ("Mín %d° · Máx %d°"):format(w.t_min, w.t_max),
        extra = ("Lluvia %d%%"):format(w.pop or 0),
        hourly = hourly,
    }
    if f.origin == "cache" and f.level == "expired" then
        vm.note = f.reason == "date" and ("Datos del " .. F.dayMonth(dto.date))
            or f.reason == "clock" and "Datos de antigüedad desconocida"
            or ("Datos de " .. F.ageLabel(f.age_s))
    end
    return vm
end

local function buildAgenda(dto, f, display)
    local expired = f.origin == "cache" and f.level == "expired"
    if expired then return { rows = {}, total = 0 }, "Agenda desactualizada" end
    if dto.events == nil then return { rows = {}, total = 0 }, "Agenda no disponible" end
    if #dto.events == 0 then return { rows = {}, total = 0 }, "Sin eventos hoy" end
    local rows = {}
    local max = math.min(display.max_events or 8, #dto.events)
    for i = 1, max do
        local ev = dto.events[i]
        rows[i] = {
            time = F.timeRange(ev), title = ev.title,
            sub = display.show_location and ev.location or nil,
        }
    end
    local total = math.max(dto.events_total or 0, #rows)
    return { rows = rows, total = total, more = total > #rows and F.more(total - #rows) or nil }, nil
end

--- @param dto table|nil  DTO saneado (nil → pantalla mínima)
--- @param device table   { battery, charging, date, weekday } (ver readDevice)
--- @param freshness table { origin, age_s, level, reason, err, err_status }
--- @param display table  cfg.display
function ViewModel.build(dto, device, freshness, display)
    display = display or {}
    local left, warn = footerLeft(freshness)
    local footer = { left = left, right = footerRight(device), warn = warn }

    if dto == nil then
        return {
            minimal = true,
            header = { title = F.dateTitle(device.date, device.weekday), subtitle = "" },
            message = MSG_NO_DATA,
            footer = footer,
        }
    end

    local subtitle = F.updatedAt(dto.generated_at)
    subtitle = subtitle and ("Actualizado " .. subtitle) or ""
    local loc = dto.weather and dto.weather.location or ""
    if display.show_location and loc ~= "" then
        subtitle = subtitle ~= "" and (loc .. " · " .. subtitle) or loc
    end

    local vm = {
        minimal = false,
        header = { title = F.dateTitle(dto.date, dto.weekday), subtitle = subtitle },
        footer = footer,
    }
    if dto.weather then
        vm.weather = buildWeather(dto.weather, freshness, dto)
        if display.show_hourly == false then vm.weather.hourly = {} end
    else
        vm.weather_placeholder = "Clima no disponible"
    end
    vm.agenda, vm.agenda_placeholder = buildAgenda(dto, freshness, display)
    return vm
end

local ERR_LONG = {
    E_NOT_CONFIGURED = "El backend no está configurado (falta backend.url)",
    E_NO_NETWORK = "Sin conexión",
    E_BUDGET_EXCEEDED = "No quedó tiempo para la red",
    E_TIMEOUT = "El servidor tardó demasiado en responder",
    E_TLS = "Error TLS al conectar",
    E_AUTH = "Token inválido",
    E_PAYLOAD_TOO_LARGE = "La respuesta era demasiado grande",
    E_JSON_PARSE = "La respuesta no es válida (¿portal cautivo?)",
    E_SCHEMA = "Versión de datos incompatible",
    E_INTERNAL = "Error interno del plugin",
}

--- Mensaje legible de un ProviderError ({ code, http_status }) para las acciones del menú.
function ViewModel.errorText(err)
    if err.code == "E_HTTP_STATUS" then return "El servidor respondió HTTP " .. tostring(err.http_status or "?") end
    return ERR_LONG[err.code] or tostring(err.code)
end

local LEVEL_ES = { fresh = "reciente", stale = "antiguo", expired = "caducado" }

--- Texto de "Ver estado del caché". status = { entry, freshness, last } (ver Orchestrator:status).
function ViewModel.statusText(status)
    local lines = {}
    local e, f = status.entry, status.freshness
    if not e then
        lines[#lines + 1] = "Caché: vacío"
    else
        lines[#lines + 1] = "Origen: " .. tostring(e.provider)
        lines[#lines + 1] = ("Antigüedad: %s (%s)"):format(F.ageLabel(f.age_s), LEVEL_ES[f.level] or f.level)
        lines[#lines + 1] = "Fecha de los datos: " .. tostring(e.dto.date)
    end
    local last = status.last
    if not last then
        lines[#lines + 1] = "Aún no hubo ninguna ejecución desde que arrancó KOReader."
    else
        lines[#lines + 1] = "Último error: " .. (last.err and ViewModel.errorText(last.err) or "ninguno")
        lines[#lines + 1] = ("Tiempos: caché %d ms · red %d ms"):format(last.timings.cache or 0, last.timings.net or 0)
    end
    return table.concat(lines, "\n")
end

--- Batería, carga y fecha local. Nunca lanza: cualquier fallo del dispositivo deja el campo en nil.
--- deps.powerd permite inyectar un dispositivo falso en los tests.
function ViewModel.readDevice(deps)
    deps = deps or {}
    local wday = tonumber(os.date("%w")) -- 0 = domingo
    local out = { date = os.date("%Y-%m-%d"), weekday = wday == 0 and 7 or wday }
    local ok, powerd = pcall(function() return deps.powerd or require("device"):getPowerDevice() end)
    if ok and powerd then
        local ok1, cap = pcall(function() return powerd:getCapacity() end)
        if ok1 and type(cap) == "number" then out.battery = math.floor(cap) end
        local ok2, charging = pcall(function() return powerd:isCharging() end)
        if ok2 then out.charging = charging and true or false end
    end
    return out
end

return ViewModel
