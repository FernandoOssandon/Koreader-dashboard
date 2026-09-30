-- Sistema de archivos en memoria con la misma interfaz que dashboard/fs.lua (se usa con `:`).
local M = {}
M.__index = M

function M.new(files)
    return setmetatable({ files = files or {}, dirs = {}, fail_write = false }, M)
end
function M:read(path) return self.files[path] end
function M:write(path, s)
    if self.fail_write then return false, "disk full" end
    self.files[path] = s
    return true
end
function M:exists(path) return self.files[path] ~= nil end
function M:remove(path)
    local had = self.files[path] ~= nil
    self.files[path] = nil
    return had
end
function M:rename(from, to)
    if self.files[from] == nil then return nil, "no such file" end
    self.files[to], self.files[from] = self.files[from], nil
    return true
end
function M:mkdirs(dir) self.dirs[dir] = true; return true end
return M
