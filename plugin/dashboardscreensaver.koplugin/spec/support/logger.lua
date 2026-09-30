-- Emula `logger` de KOReader y guarda las líneas para poder inspeccionarlas.
local M = { lines = {} }
local function add(level)
    return function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        M.lines[#M.lines + 1] = level .. " " .. table.concat(parts, " ")
    end
end
M.info, M.warn, M.err, M.dbg = add("INFO"), add("WARN"), add("ERR"), add("DBG")
function M.reset() M.lines = {} end
function M.text() return table.concat(M.lines, "\n") end
return M
