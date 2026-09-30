-- Textos en español para la pantalla. Funciones puras: no dependen de KOReader.
local F = {}

local WEEKDAYS = { "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo" } -- 1 = lunes (ISO)
local MONTHS = {
    "enero", "febrero", "marzo", "abril", "mayo", "junio",
    "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
}

function F.weekdayName(n) return WEEKDAYS[n] or "" end
function F.monthName(m) return MONTHS[m] or "" end

--- "22 de septiembre" a partir de "2026-09-22".
function F.dayMonth(date)
    local _, m, d = tostring(date):match("^(%d+)-(%d+)-(%d+)$")
    if not m then return "" end
    return ("%d de %s"):format(tonumber(d), F.monthName(tonumber(m)))
end

--- "Miércoles 23 de septiembre".
function F.dateTitle(date, weekday)
    local dm = F.dayMonth(date)
    local name = F.weekdayName(weekday)
    if dm == "" then return name end
    return name .. " " .. dm
end

--- "hace 5 min" / "hace 2 h" / "hace 1 día".
function F.ageLabel(seconds)
    seconds = math.max(seconds or 0, 0)
    if seconds < 60 then return "hace unos segundos" end
    if seconds < 3600 then return ("hace %d min"):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return ("hace %d h"):format(math.floor(seconds / 3600)) end
    local days = math.floor(seconds / 86400)
    return days == 1 and "hace 1 día" or ("hace %d días"):format(days)
end

--- "Todo el día", "14:00–14:15" o "15:00" cuando el evento no tiene fin.
function F.timeRange(ev)
    if ev.all_day then return "Todo el día" end
    local s, e = ev.start or "", ev["end"]
    if not e or e == s then return s end
    return s .. "–" .. e
end

function F.more(n) return ("+%d más"):format(n) end

--- Hora "HH:MM" de un ISO-8601 con offset (la del servidor, no la del Kindle).
function F.updatedAt(generated_at)
    return tostring(generated_at or ""):match("T(%d%d:%d%d)")
end

return F
