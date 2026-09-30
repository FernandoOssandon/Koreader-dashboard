-- settings.json: valores por defecto, merge profundo, clamp con advertencia y protección del archivo.
local logger = require("logger")
-- Los require de módulos del plugin van SIEMPRE arriba: KOReader sólo añade la carpeta del plugin
-- a package.path mientras carga main.lua, así que un require diferido fallaría en el dispositivo.
local default_fs = require("dashboard/fs")

local Config = {}
Config.__index = Config

local function defaults()
    return {
        schema_version = 1,
        enabled = true,
        provider = "backend", -- provider, fallback y direct.* se conservan pero aún no tienen efecto
        fallback = "cache",
        backend = { url = "", token = "", connect_timeout_s = 1.0, total_timeout_s = 2.2 },
        direct = {
            latitude = -33.45, longitude = -70.66, location_name = "Santiago", ics_urls = {},
            total_timeout_s = 2.2, max_ics_bytes = 524288,
        },
        cache = { min_refresh_interval_s = 600, stale_after_s = 10800, max_age_s = 86400 },
        display = { max_events = 8, show_hourly = true, show_location = true, anti_ghosting = "full" },
        debug = { log_timings = false },
    }
end

local RANGES = {
    ["backend.connect_timeout_s"] = { 0.3, 1.5 },
    ["backend.total_timeout_s"] = { 0.5, 2.5 },
    ["cache.min_refresh_interval_s"] = { 0, 86400 },
    ["display.max_events"] = { 1, 8 },
}
local ENUMS = { ["display.anti_ghosting"] = { full = true, double = true } }

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end

-- Un default `{}` es una lista libre (p. ej. direct.ics_urls); un default con claves es un objeto.
-- Sólo se recorren las claves conocidas, así que las desconocidas se ignoran.
local function merge(def, user, prefix, warnings, null)
    local out = {}
    for k, dv in pairs(def) do
        local path = prefix .. k
        local uv
        if type(user) == "table" then uv = user[k] end -- (no usar `and/or`: rompería los `false`)
        if uv == null then uv = nil end
        if uv == nil then
            out[k] = copy(dv)
        elseif type(uv) ~= type(dv) then
            warnings[#warnings + 1] = ("%s: tipo inválido, usando el valor por defecto"):format(path)
            out[k] = copy(dv)
        elseif type(dv) == "table" and next(dv) ~= nil then
            out[k] = merge(dv, uv, path .. ".", warnings, null)
        elseif type(dv) == "number" and RANGES[path] then
            local lo, hi = RANGES[path][1], RANGES[path][2]
            local v = math.max(lo, math.min(hi, uv))
            if v ~= uv then
                warnings[#warnings + 1] = ("%s=%s fuera de rango [%s, %s], usando %s"):format(path, uv, lo, hi, v)
            end
            out[k] = v
        elseif ENUMS[path] and not ENUMS[path][uv] then
            warnings[#warnings + 1] = ("%s=%s no permitido, usando %s"):format(path, tostring(uv), tostring(dv))
            out[k] = dv
        else
            out[k] = uv
        end
    end
    return out
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- JSON con sangría y claves ordenadas: el archivo lo edita el usuario a mano.
local function pretty(json, v, indent)
    indent = indent or ""
    if type(v) ~= "table" then return json.encode(v) end
    local inner = indent .. "  "
    local parts = {}
    if #v > 0 or next(v) == nil then
        for _, x in ipairs(v) do parts[#parts + 1] = inner .. pretty(json, x, inner) end
        if #parts == 0 then return "[]" end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    for _, k in ipairs(sorted_keys(v)) do
        parts[#parts + 1] = inner .. json.encode(k) .. ": " .. pretty(json, v[k], inner)
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

--- deps opcionales: { json =, fs = } (los tests inyectan versiones en memoria).
function Config.new(path, deps)
    deps = deps or {}
    return setmetatable({
        path = path,
        json = deps.json or require("json"),
        fs = deps.fs or default_fs,
        warnings = {},
        valid_file = true,
        cfg = defaults(),
    }, Config)
end

function Config:_write()
    local dir = self.path:match("^(.*)/[^/]*$")
    if dir then self.fs:mkdirs(dir) end
    return self.fs:write(self.path, pretty(self.json, self.cfg) .. "\n")
end

function Config:load()
    self.warnings, self.valid_file = {}, true
    local raw = self.fs:read(self.path)
    if raw == nil then
        self.cfg = defaults()
        local ok, err = self:_write()
        if not ok then logger.warn("[dashboard] no se pudo crear settings.json:", tostring(err)) end
    else
        local ok, t = pcall(self.json.decode, raw)
        if not ok or type(t) ~= "table" then
            -- JSON roto: se trabaja con los defaults en memoria y NO se toca el archivo del usuario
            logger.err("[dashboard] settings.json inválido, usando valores por defecto")
            self.cfg, self.valid_file = defaults(), false
        else
            self.cfg = merge(defaults(), t, "", self.warnings, self.json.null)
        end
    end
    for _, w in ipairs(self.warnings) do logger.warn("[dashboard] config:", w) end
    return self.cfg
end

--- Cambia un valor (clave con puntos) y lo guarda, salvo que el archivo del usuario sea inválido.
function Config:set(dotted_key, value)
    if not self.valid_file then return false, "settings.json inválido" end
    local t = self.cfg
    local parts = {}
    for p in dotted_key:gmatch("[^.]+") do parts[#parts + 1] = p end
    for i = 1, #parts - 1 do
        t = t[parts[i]]
        if type(t) ~= "table" then return false, "clave desconocida" end
    end
    t[parts[#parts]] = value
    return self:_write()
end

function Config:get(dotted_key)
    local t = self.cfg
    for p in dotted_key:gmatch("[^.]+") do
        if type(t) ~= "table" then return nil end
        t = t[p]
    end
    return t
end

return Config
