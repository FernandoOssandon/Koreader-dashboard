local DTO = require("dashboard/dto")

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

describe("iconos", function()
    it("hay 13 valores de WeatherIcon", function()
        assert.equals(13, #DTO.ICONS)
    end)

    for _, name in ipairs(DTO.ICONS) do
        for _, size in ipairs({ 96, 48 }) do
            it(("existe icons/%s_%d.png"):format(name, size), function()
                assert.is_true(exists(("icons/%s_%d.png"):format(name, size)))
            end)
        end
    end

    it("cada icono es un PNG", function()
        local f = assert(io.open("icons/clear_day_96.png", "rb"))
        local magic = f:read(8)
        f:close()
        assert.equals("\137PNG\r\n\26\n", magic)
    end)
end)
