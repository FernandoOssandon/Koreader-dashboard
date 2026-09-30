-- Cliente HTTP del backend (design D10). Expone la firma de la futura interfaz DataProvider:
--   fetchData(onSuccess, onError, opts)  -- invoca EXACTAMENTE un callback, una sola vez; síncrono.
local DTO = require("dashboard/dto")
local logger = require("logger")
local redact = require("dashboard/redact") -- el token no puede llegar nunca a un mensaje ni al log

local MAX_BYTES = 8192

local BackendClient = {}
BackendClient.__index = BackendClient

local function default_deps()
    local time = require("ui/time")
    return {
        http = require("socket.http"),
        https = nil, -- se carga sólo si la URL es https (ssl.https)
        socket = require("socket"),
        socketutil = require("socketutil"),
        json = require("json"),
        now_ms = function() return time.to_ms(time.now()) end,
    }
end

--- config: objeto con `.cfg` (settings ya cargados; se lee en cada petición para ver los cambios).
function BackendClient.new(config, deps)
    return setmetatable({ config = config, d = deps or default_deps() }, BackendClient)
end

local function make_err(code, message, http_status)
    return {
        code = code, message = message, http_status = http_status,
        retryable = code == "E_TIMEOUT" or code == "E_NO_NETWORK" or (http_status ~= nil and http_status >= 500),
    }
end


function BackendClient:_perform(opts)
    local d, cfg = self.d, self.config.cfg
    local b = cfg.backend
    local body, overflow = {}, false
    local counted = 0
    local table_sink = d.socketutil.table_sink(body)
    local sink = function(chunk, err)
        if chunk then
            counted = counted + #chunk
            if counted > MAX_BYTES then
                overflow = true
                return nil, "payload too large"
            end
        end
        return table_sink(chunk, err)
    end

    local headers = { ["Accept"] = "application/json", ["Connection"] = "close" }
    if b.token ~= "" then headers["Authorization"] = "Bearer " .. b.token end
    if opts.etag then headers["If-None-Match"] = opts.etag end

    local url = b.url .. (b.url:find("?", 1, true) and "&" or "?") .. "max_events=" .. cfg.display.max_events
    local req = { url = url, method = "GET", headers = headers, sink = sink }
    local http = d.http
    if url:match("^https") then
        http = d.https or require("ssl.https") -- http.request hablaría texto plano al puerto 443
    else
        req.create = d.socketutil.tcp
    end

    d.socketutil:set_timeout(b.connect_timeout_s, opts.timeout_s)
    local ok, code, resp_headers = pcall(function() return d.socket.skip(1, http.request(req)) end)
    d.socketutil:reset_timeout() -- SIEMPRE, aunque falle

    if not ok then return { err = make_err("E_INTERNAL", redact(code, b.token)) } end
    if overflow then return { err = make_err("E_PAYLOAD_TOO_LARGE", "respuesta de más de 8 KB") } end
    if type(code) ~= "number" then -- error de transporte: LuaSocket devuelve la descripción como string
        local su = d.socketutil
        if code == su.TIMEOUT_CODE or code == su.SINK_TIMEOUT_CODE then
            return { err = make_err("E_TIMEOUT", "timeout") }
        elseif su.SSL_HANDSHAKE_CODE and code == su.SSL_HANDSHAKE_CODE then
            return { err = make_err("E_TLS", "error TLS") }
        end
        return { err = make_err("E_NO_NETWORK", redact(code, b.token)) }
    end

    resp_headers = resp_headers or {}
    if code == 304 then return { meta = { not_modified = true } } end
    if code == 401 or code == 403 then return { err = make_err("E_AUTH", "token rechazado", code) } end
    if code ~= 200 then return { err = make_err("E_HTTP_STATUS", "HTTP " .. code, code) } end

    if not tostring(resp_headers["content-type"] or ""):lower():match("^application/json") then
        return { err = make_err("E_JSON_PARSE", "no es JSON (¿portal cautivo?)") }
    end
    local dok, t = pcall(d.json.decode, table.concat(body))
    if not dok or type(t) ~= "table" then return { err = make_err("E_JSON_PARSE", "JSON inválido") } end
    local vok, path = DTO.validate(t)
    if not vok then return { err = make_err("E_SCHEMA", "contrato inválido en " .. tostring(path)) } end
    return { dto = DTO.sanitize(t, cfg.display), meta = { etag = resp_headers["etag"] } }
end

--- opts: { timeout_s = number, etag = string|nil }
function BackendClient:fetchData(onSuccess, onError, opts)
    local t0 = self.d.now_ms()
    local ok, res = pcall(self._perform, self, opts)
    if not ok then
        res = { err = make_err("E_INTERNAL", redact(res, self.config.cfg.backend.token)) }
    end
    local elapsed = self.d.now_ms() - t0
    -- Los callbacks se llaman fuera de todo pcall y una sola vez
    if res.err then
        res.err.elapsed_ms = elapsed
        logger.info("[dashboard] fetch error", res.err.code, res.err.http_status or "", elapsed .. "ms")
        return onError(res.err)
    end
    res.meta.elapsed_ms = elapsed
    return onSuccess(res.dto, res.meta)
end

return BackendClient
