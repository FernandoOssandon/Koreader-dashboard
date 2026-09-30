-- Emula el módulo `json` de KOReader: decode devuelve json.null para los null.
local dkjson = require("dkjson")
local M = { null = setmetatable({}, { __tostring = function() return "json.null" end }) }

function M.decode(s)
    local v, _, err = dkjson.decode(s, 1, M.null)
    if err then error(err) end
    return v
end

function M.encode(t)
    return dkjson.encode(t)
end

return M
