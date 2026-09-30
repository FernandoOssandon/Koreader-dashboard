-- Acceso a archivos del dispositivo. Los módulos lo reciben por inyección (se usa con `:`)
-- para poder probarlos con un sistema de archivos en memoria.
local M = {}

function M:read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

function M:write(path, s)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    local ok, werr = f:write(s)
    local cok, cerr = f:close() -- close vacía los buffers: un fallo aquí también es un fallo de escritura
    if not ok then return false, werr end
    if not cok then return false, cerr end
    return true
end

function M:exists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

function M:remove(path) return os.remove(path) end
function M:rename(from, to) return os.rename(from, to) end

function M:mkdirs(dir)
    local lfs = require("libs/libkoreader-lfs")
    local path = dir:sub(1, 1) == "/" and "/" or ""
    for part in dir:gmatch("[^/]+") do
        path = path .. part
        if lfs.attributes(path, "mode") == nil then
            local ok, err = lfs.mkdir(path)
            if not ok then return false, err end
        end
        path = path .. "/"
    end
    return true
end

return M
