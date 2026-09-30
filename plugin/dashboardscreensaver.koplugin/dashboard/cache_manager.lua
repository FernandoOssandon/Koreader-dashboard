-- Caché en disco de la última respuesta válida. No depende de la red ni de proveedores (regla de D1).
local DTO = require("dashboard/dto")
local logger = require("logger")
local default_fs = require("dashboard/fs") -- arriba, no diferido: ver el comentario de config.lua

local CacheManager = {}
CacheManager.__index = CacheManager

local FORMAT_VERSION = 1

--- opts: { path =, fs = (opcional), json = (opcional), now = fn() -> epoch (opcional) }
function CacheManager.new(opts)
    return setmetatable({
        path = opts.path,
        fs = opts.fs or default_fs,
        json = opts.json or require("json"),
        now = opts.now or os.time,
    }, CacheManager)
end

--- Devuelve la entrada o nil. Un archivo ilegible, de otra versión o que no cumple el contrato se borra.
function CacheManager:load()
    local raw = self.fs:read(self.path)
    if raw == nil then return nil end
    local ok, e = pcall(self.json.decode, raw)
    if not ok or type(e) ~= "table" or e.cache_version ~= FORMAT_VERSION
        or type(e.saved_at) ~= "number" or type(e.validated_at) ~= "number"
        or not DTO.validate(e.dto) then
        logger.warn("[dashboard] caché corrupto, se elimina")
        self.fs:remove(self.path)
        return nil
    end
    return e
end

-- Escritura atómica: .tmp completo y luego rename. Un corte deja el caché anterior intacto.
function CacheManager:_write(entry)
    local dir = self.path:match("^(.*)/[^/]*$")
    if dir then self.fs:mkdirs(dir) end
    local tmp = self.path .. ".tmp"
    local ok, err = self.fs:write(tmp, self.json.encode(entry))
    if not ok then
        self.fs:remove(tmp)
        logger.warn("[dashboard] no se pudo guardar el caché:", tostring(err))
        return false
    end
    if not self.fs:rename(tmp, self.path) then
        self.fs:remove(tmp)
        logger.warn("[dashboard] no se pudo reemplazar el caché")
        return false
    end
    return true
end

function CacheManager:save(dto, etag, provider_id)
    local now = self.now()
    return self:_write({
        cache_version = FORMAT_VERSION, saved_at = now, validated_at = now,
        etag = etag, provider = provider_id or "backend", dto = dto,
    })
end

--- El servidor confirmó que no hubo cambios (304): sólo se actualiza validated_at.
function CacheManager:touch()
    local entry = self:load()
    if not entry then return false end
    entry.validated_at = self.now()
    return self:_write(entry)
end

function CacheManager:clear()
    self.fs:remove(self.path)
    self.fs:remove(self.path .. ".tmp")
end

--- Nivel de frescura (función pura). `today` es la fecha local del dispositivo, "YYYY-MM-DD".
--- @return table { origin = "cache"|"none", age_s, level = "fresh"|"stale"|"expired", reason }
function CacheManager.freshness(entry, now, cache_cfg, today)
    if not entry then return { origin = "none", level = "expired" } end
    local age = now - entry.validated_at
    local f = { origin = "cache", age_s = math.max(age, 0), level = "fresh" }
    if age < 0 then
        f.level, f.reason = "expired", "clock" -- reloj corregido hacia atrás
    elseif entry.dto.date ~= today then
        f.level, f.reason = "expired", "date"
    elseif age >= cache_cfg.max_age_s then
        f.level, f.reason = "expired", "age"
    elseif age >= cache_cfg.stale_after_s then
        f.level = "stale"
    end
    return f
end

return CacheManager
