-- Regla de dependencias (design D1): la vista, el view model y el caché no pueden conocer la red
-- ni los proveedores de datos. Analiza los `require(...)` del código fuente.
local FILES = {
    "dashboard/dashboard_widget.lua",
    "dashboard/view_model.lua",
    "dashboard/cache_manager.lua",
}

-- Módulos que esas tres piezas no pueden requerir (coincidencia por fragmento del nombre)
local FORBIDDEN = { "backend_client", "provider_", "socket", "ical_parser", "ui/network" }

local function read(path)
    local f = assert(io.open(path, "rb"), "no se pudo abrir " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function requires_of(source)
    local found = {}
    for name in source:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do found[#found + 1] = name end
    return found
end

--- Devuelve los require prohibidos de un texto fuente (para poder probar el propio detector).
local function violations(source)
    local bad = {}
    for _, name in ipairs(requires_of(source)) do
        for _, frag in ipairs(FORBIDDEN) do
            if name:find(frag, 1, true) then bad[#bad + 1] = name end
        end
    end
    return bad
end

describe("arquitectura: dependencias de la vista, el view model y el caché", function()
    for _, path in ipairs(FILES) do
        it(path .. " no requiere red ni proveedores", function()
            local source = read(path)
            assert.is_true(#requires_of(source) > 0, "el análisis no encontró ningún require en " .. path)
            assert.same({}, violations(source))
        end)
    end

    it("el detector falla si se introduce un require prohibido", function()
        assert.same({ "dashboard/backend_client" }, violations('local C = require("dashboard/backend_client")'))
        assert.same({ "socket.http" }, violations("local http = require('socket.http')"))
        assert.same({ "ui/network/manager" }, violations('local N = require "ui/network/manager"'))
        assert.same({ "dashboard/provider_direct" }, violations('require("dashboard/provider_direct")'))
        assert.same({ "dashboard/ical_parser" }, violations('require( "dashboard/ical_parser" )'))
        assert.same({}, violations('local F = require("dashboard/format_es")'))
    end)
end)
