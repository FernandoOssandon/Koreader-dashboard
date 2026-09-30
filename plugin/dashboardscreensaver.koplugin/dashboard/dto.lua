-- Contrato de datos v1: validación estricta y normalización que nunca falla (design D10/D13).
local json = require("json")

local DTO = {}

DTO.ICONS = {
    "clear_day", "clear_night", "partly_cloudy_day", "partly_cloudy_night", "cloudy", "fog",
    "drizzle", "rain", "heavy_rain", "snow", "showers", "thunderstorm", "unknown",
}
local VALID_ICON = {}
for _, name in ipairs(DTO.ICONS) do VALID_ICON[name] = true end

local ELLIPSIS = "…"

-- json.null (según la versión de KOReader) se trata como ausente
local function val(x)
    if x == json.null then return nil end
    return x
end

local function is_num(x) return type(x) == "number" and x == x end

local function num(x, lo, hi, default)
    x = val(x)
    if not is_num(x) then return default end
    return math.floor(math.max(lo, math.min(hi, x)) + 0.5)
end

local function hhmm(s)
    s = val(s)
    if type(s) ~= "string" then return nil end
    local h, m = s:match("^(%d%d):(%d%d)$")
    if h and tonumber(h) <= 24 and tonumber(m) <= 59 then return s end
    return nil
end

--- Recorta a max_chars caracteres (no bytes) sin cortar secuencias UTF-8; termina en "…" si recorta.
function DTO.truncateUtf8(s, max_chars)
    if type(s) ~= "string" then return "" end
    s = s:gsub("%s+", " "):match("^%s*(.-)%s*$")
    local starts, i, len = {}, 1, #s
    while i <= len do
        local b = s:byte(i)
        local n = b < 0x80 and 1 or b >= 0xF0 and 4 or b >= 0xE0 and 3 or b >= 0xC0 and 2 or 1
        starts[#starts + 1] = i
        i = i + n
    end
    if #starts <= max_chars then return s end
    return s:sub(1, starts[max_chars] - 1) .. ELLIPSIS -- max_chars - 1 caracteres + "…"
end

local function text(x, max_chars)
    x = val(x)
    if type(x) ~= "string" then return nil end
    x = DTO.truncateUtf8(x, max_chars)
    if x == "" then return nil end
    return x
end

--- Devuelve true, o false y la ruta del primer campo inválido.
function DTO.validate(t)
    if type(t) ~= "table" then return false, "(root)" end
    if t.v ~= 1 then return false, "v" end
    local date = val(t.date)
    if type(date) ~= "string" or not date:match("^%d%d%d%d%-%d%d%-%d%d$") then return false, "date" end
    local wd = val(t.weekday)
    if not is_num(wd) or wd < 1 or wd > 7 or wd ~= math.floor(wd) then return false, "weekday" end
    if not is_num(val(t.generated_ts)) then return false, "generated_ts" end

    local w = val(t.weather)
    if w ~= nil then
        if type(w) ~= "table" then return false, "weather" end
        for _, k in ipairs({ "temp", "feels_like", "t_min", "t_max" }) do
            if not is_num(val(w[k])) then return false, "weather." .. k end
        end
        if type(val(w.icon)) ~= "string" then return false, "weather.icon" end
        if type(val(w.desc)) ~= "string" then return false, "weather.desc" end
    end

    local events = val(t.events)
    if events ~= nil then
        if type(events) ~= "table" then return false, "events" end
        for i, ev in ipairs(events) do
            if type(ev) ~= "table" then return false, "events[" .. i .. "]" end
            if type(val(ev.title)) ~= "string" then return false, "events[" .. i .. "].title" end
            if type(val(ev.all_day)) ~= "boolean" then return false, "events[" .. i .. "].all_day" end
        end
    end
    return true
end

local function sanitize_weather(w)
    local hourly = {}
    local src = type(val(w.hourly)) == "table" and w.hourly or {}
    for _, h in ipairs(src) do
        local time = type(h) == "table" and hhmm(h.time)
        if time and #hourly < 4 then
            local icon = val(h.icon)
            hourly[#hourly + 1] = {
                time = time,
                temp = num(h.temp, -60, 60, 0),
                icon = VALID_ICON[icon] and icon or "unknown",
                pop = num(h.pop, 0, 100, nil),
            }
        end
    end
    local icon = val(w.icon)
    return {
        location = text(w.location, 40) or "",
        temp = num(w.temp, -60, 60, 0),
        feels_like = num(w.feels_like, -60, 60, 0),
        t_min = num(w.t_min, -60, 60, 0),
        t_max = num(w.t_max, -60, 60, 0),
        code = num(w.code, 0, 99, 0),
        icon = VALID_ICON[icon] and icon or "unknown",
        desc = text(w.desc, 32) or "",
        pop = num(w.pop, 0, 100, 0),
        humidity = num(w.humidity, 0, 100, nil),
        wind_kmh = num(w.wind_kmh, 0, 300, nil),
        sunrise = hhmm(w.sunrise),
        sunset = hhmm(w.sunset),
        hourly = hourly,
    }
end

local function sanitize_events(events, max_events)
    local out = {}
    for _, ev in ipairs(events) do
        if #out >= max_events then break end
        local all_day = val(ev.all_day) == true
        out[#out + 1] = {
            title = text(ev.title, 60) or "(Sin título)",
            all_day = all_day,
            start = (not all_day) and hhmm(ev.start) or nil,
            ["end"] = (not all_day) and hhmm(ev["end"]) or nil,
            start_ts = num(ev.start_ts, 0, 4e9, 0),
            end_ts = num(ev.end_ts, 0, 4e9, 0),
            location = text(ev.location, 40),
            cal = text(ev.cal, 20),
        }
    end
    return out
end

--- Normaliza un DTO ya validado. Nunca falla: trunca, ajusta rangos y descarta lo desconocido.
function DTO.sanitize(t, display)
    local max_events = math.min(8, (display and display.max_events) or 8)
    local out = {
        v = 1,
        source = val(t.source) == "direct" and "direct" or "backend",
        generated_at = type(val(t.generated_at)) == "string" and t.generated_at or "",
        generated_ts = num(t.generated_ts, 0, 4e9, 0),
        ttl_s = num(t.ttl_s, 60, 86400 * 7, 900),
        tz = text(t.tz, 40) or "",
        date = t.date,
        weekday = num(t.weekday, 1, 7, 1),
        warnings = {},
    }
    if type(val(t.warnings)) == "table" then
        for _, w in ipairs(t.warnings) do
            if #out.warnings < 5 and type(w) == "string" then
                out.warnings[#out.warnings + 1] = DTO.truncateUtf8(w, 32)
            end
        end
    end
    if type(val(t.weather)) == "table" then out.weather = sanitize_weather(t.weather) end
    if type(val(t.events)) == "table" then
        out.events = sanitize_events(t.events, max_events)
        out.events_total = math.max(#out.events, num(t.events_total, 0, 1e6, #out.events))
    else
        out.events_total = 0
    end
    return out
end

return DTO
