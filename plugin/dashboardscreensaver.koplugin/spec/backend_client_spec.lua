local BackendClient = require("dashboard/backend_client")
local logger = require("logger")
local json = require("json")

local TOKEN = "s3cr3t-token-XYZ"

local function valid_body(overrides)
    local t = {
        v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = 1790181600,
        ttl_s = 900, tz = "America/Santiago", date = "2026-09-23", weekday = 3, warnings = {},
        weather = { location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
                    icon = "cloudy", desc = "Nublado", pop = 10, hourly = {} },
        events = { { title = "Dentista", all_day = false, start = "18:30", ["end"] = "19:30",
                     start_ts = 1, end_ts = 2 } },
        events_total = 1,
    }
    for k, v in pairs(overrides or {}) do t[k] = v end
    return json.encode(t)
end

local JSON_H = { ["content-type"] = "application/json; charset=utf-8", etag = 'W/"abc123"' }

-- `behavior(req)` devuelve lo mismo que http.request en modo tabla: 1, code, headers  |  nil, err
local function setup(behavior, overrides)
    local state = { set = 0, reset = 0, now = 0, reqs = {} }
    local socketutil = {
        TIMEOUT_CODE = "timeout", SINK_TIMEOUT_CODE = "sink timeout", SSL_HANDSHAKE_CODE = "handshake failed",
        tcp = function() end,
        table_sink = function(t)
            return function(chunk) if chunk then t[#t + 1] = chunk end return 1 end
        end,
        set_timeout = function(_, connect, total) state.set = state.set + 1; state.timeouts = { connect, total } end,
        reset_timeout = function() state.reset = state.reset + 1 end,
    }
    local http = { request = function(req) state.reqs[#state.reqs + 1] = req; return behavior(req) end }
    local cfg = {
        backend = { url = "http://192.168.1.10:8080/api/dashboard", token = TOKEN, connect_timeout_s = 1.0, total_timeout_s = 2.2 },
        display = { max_events = 8 },
    }
    for k, v in pairs(overrides or {}) do cfg.backend[k] = v end
    local client = BackendClient.new({ cfg = cfg }, {
        http = http, socketutil = socketutil, json = json,
        socket = { skip = function(n, ...) return select(n + 1, ...) end },
        now_ms = function() state.now = state.now + 5; return state.now end,
    })
    return client, state
end

local function fetch(client, opts)
    local calls = { success = {}, error = {} }
    client:fetchData(
        function(dto, meta) calls.success[#calls.success + 1] = { dto = dto, meta = meta } end,
        function(err) calls.error[#calls.error + 1] = err end,
        opts or { timeout_s = 2.2 })
    return calls
end

local function assert_one_callback(calls, kind)
    assert.equals(kind == "success" and 1 or 0, #calls.success)
    assert.equals(kind == "error" and 1 or 0, #calls.error)
end

describe("backend_client", function()
    before_each(function() logger.reset() end)

    local function expect_error(behavior, code, http_status)
        local client, state = setup(behavior)
        local calls = fetch(client)
        assert_one_callback(calls, "error")
        assert.equals(code, calls.error[1].code)
        assert.equals(http_status, calls.error[1].http_status)
        assert.equals(1, state.set)
        assert.equals(1, state.reset) -- reset_timeout siempre
        assert.is_nil(logger.text():find(TOKEN, 1, true))
        assert.is_nil(calls.error[1].message:find(TOKEN, 1, true))
        return calls.error[1]
    end

    it("200 válido → onSuccess con el DTO saneado y el ETag", function()
        local client, state = setup(function(req)
            req.sink(valid_body()); req.sink(nil)
            return 1, 200, JSON_H
        end)
        local calls = fetch(client, { timeout_s = 1.8, etag = 'W/"viejo"' })
        assert_one_callback(calls, "success")
        assert.equals("Dentista", calls.success[1].dto.events[1].title)
        assert.equals('W/"abc123"', calls.success[1].meta.etag)
        assert.is_nil(calls.success[1].meta.not_modified)
        -- petición: cabeceras, timeouts y URL
        local req = state.reqs[1]
        assert.equals("Bearer " .. TOKEN, req.headers["Authorization"])
        assert.equals('W/"viejo"', req.headers["If-None-Match"])
        assert.equals("http://192.168.1.10:8080/api/dashboard?max_events=8", req.url)
        assert.same({ 1.0, 1.8 }, state.timeouts)
        assert.equals(1, state.reset)
    end)

    it("no envía Authorization sin token ni If-None-Match sin ETag", function()
        local client, state = setup(function(req) req.sink(valid_body()); req.sink(nil); return 1, 200, JSON_H end, { token = "" })
        fetch(client)
        assert.is_nil(state.reqs[1].headers["Authorization"])
        assert.is_nil(state.reqs[1].headers["If-None-Match"])
    end)

    it("304 → onSuccess(nil, not_modified)", function()
        local client = setup(function() return 1, 304, {} end)
        local calls = fetch(client)
        assert_one_callback(calls, "success")
        assert.is_nil(calls.success[1].dto)
        assert.is_true(calls.success[1].meta.not_modified)
    end)

    it("401 y 403 → E_AUTH", function()
        expect_error(function() return 1, 401, {} end, "E_AUTH", 401)
        expect_error(function() return 1, 403, {} end, "E_AUTH", 403)
    end)

    it("503 → E_HTTP_STATUS reintentable", function()
        local err = expect_error(function() return 1, 503, {} end, "E_HTTP_STATUS", 503)
        assert.is_true(err.retryable)
    end)

    it("timeout y sink timeout → E_TIMEOUT", function()
        local err = expect_error(function() return nil, "timeout" end, "E_TIMEOUT")
        assert.is_true(err.retryable)
        expect_error(function() return nil, "sink timeout" end, "E_TIMEOUT")
    end)

    it("fallo de handshake → E_TLS", function()
        expect_error(function() return nil, "handshake failed" end, "E_TLS")
    end)

    it("conexión rechazada → E_NO_NETWORK", function()
        expect_error(function() return nil, "connection refused" end, "E_NO_NETWORK")
    end)

    it("HTML de portal cautivo → E_JSON_PARSE", function()
        expect_error(function(req)
            req.sink("<html>Inicia sesión en el Wi-Fi</html>"); req.sink(nil)
            return 1, 200, { ["content-type"] = "text/html" }
        end, "E_JSON_PARSE")
    end)

    it("9 KB de basura → E_PAYLOAD_TOO_LARGE", function()
        expect_error(function(req)
            local ok = req.sink(string.rep("x", 9 * 1024))
            if not ok then return nil, "payload too large" end
            req.sink(nil)
            return 1, 200, JSON_H
        end, "E_PAYLOAD_TOO_LARGE")
    end)

    it("el límite se aplica aunque el cuerpo llegue en trozos", function()
        expect_error(function(req)
            for _ = 1, 10 do
                if not req.sink(string.rep("x", 1000)) then return nil, "payload too large" end
            end
            req.sink(nil)
            return 1, 200, JSON_H
        end, "E_PAYLOAD_TOO_LARGE")
    end)

    it("JSON malformado con content-type correcto → E_JSON_PARSE", function()
        expect_error(function(req) req.sink('{"v":1,'); req.sink(nil); return 1, 200, JSON_H end, "E_JSON_PARSE")
    end)

    it("JSON con otro schema (v = 2) → E_SCHEMA", function()
        expect_error(function(req) req.sink(valid_body({ v = 2 })); req.sink(nil); return 1, 200, JSON_H end, "E_SCHEMA")
    end)

    it("un evento sin título rechaza toda la respuesta → E_SCHEMA", function()
        local body = valid_body({ events = { { all_day = false } } })
        expect_error(function(req) req.sink(body); req.sink(nil); return 1, 200, JSON_H end, "E_SCHEMA")
    end)

    it("una excepción del transporte → E_INTERNAL, sin filtrar el token y con reset_timeout", function()
        local err = expect_error(function() error("boom con " .. TOKEN) end, "E_INTERNAL")
        assert.truthy(err.message:find("***", 1, true))
    end)

    it("usa ssl.https para URLs https y no fuerza create", function()
        local https_called
        local client, state = setup(function() return 1, 304, {} end, { url = "https://ejemplo.cl/api/dashboard" })
        client.d.https = { request = function(req) https_called = req; return 1, 304, {} end }
        fetch(client)
        assert.is_truthy(https_called)
        assert.is_nil(https_called.create)
        assert.equals(0, #state.reqs)
    end)

    it("añade max_events con & si la URL ya tiene query", function()
        local client, state = setup(function() return 1, 304, {} end, { url = "http://x/api?a=1" })
        fetch(client)
        assert.equals("http://x/api?a=1&max_events=8", state.reqs[1].url)
    end)
end)
