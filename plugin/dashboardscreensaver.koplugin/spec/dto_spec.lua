local DTO = require("dashboard/dto")
local json = require("json")

local function valid()
    return {
        v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = 1790181600,
        ttl_s = 900, tz = "America/Santiago", date = "2026-09-23", weekday = 3,
        weather = {
            location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
            icon = "partly_cloudy_day", desc = "Parcialmente nublado", pop = 10, humidity = 45, wind_kmh = 12,
            sunrise = "07:12", sunset = "19:31",
            hourly = {
                { time = "16:00", temp = 21, icon = "clear_day", pop = 0 },
                { time = "19:00", temp = 17, icon = "partly_cloudy_night", pop = 5 },
            },
        },
        events = {
            { title = "Feriado", all_day = true, start = json.null, ["end"] = json.null, start_ts = 1, end_ts = 2,
              location = json.null, cal = "Feriados" },
            { title = "Stand-up", all_day = false, start = "14:00", ["end"] = "14:15", start_ts = 3, end_ts = 4,
              location = "Meet", cal = "Trabajo" },
        },
        events_total = 2, warnings = {},
    }
end

describe("dto.validate", function()
    it("acepta el ejemplo válido", function()
        assert.is_true(DTO.validate(valid()))
    end)

    it("rechaza v = 2", function()
        local t = valid(); t.v = 2
        local ok, path = DTO.validate(t)
        assert.is_false(ok); assert.equals("v", path)
    end)

    it("rechaza lo que no es un objeto", function()
        assert.is_false(DTO.validate(nil))
        assert.is_false(DTO.validate("x"))
    end)

    it("rechaza fecha y weekday inválidos", function()
        local t = valid(); t.date = "23/09/2026"
        assert.is_false(DTO.validate(t))
        t = valid(); t.weekday = 8
        assert.is_false(DTO.validate(t))
        t = valid(); t.generated_ts = "ayer"
        assert.is_false(DTO.validate(t))
    end)

    it("rechaza un clima incompleto pero acepta weather = null", function()
        local t = valid(); t.weather.temp = nil
        assert.is_false(DTO.validate(t))
        t = valid(); t.weather.icon = nil
        assert.is_false(DTO.validate(t))
        t = valid(); t.weather = json.null
        assert.is_true(DTO.validate(t))
    end)

    it("rechaza toda la respuesta si un evento no tiene título", function()
        local t = valid(); t.events[2].title = nil
        local ok, path = DTO.validate(t)
        assert.is_false(ok); assert.equals("events[2].title", path)
        t = valid(); t.events[1].all_day = nil
        assert.is_false(DTO.validate(t))
    end)

    it("acepta events = null (agenda no disponible)", function()
        local t = valid(); t.events = json.null
        assert.is_true(DTO.validate(t))
    end)
end)

describe("dto.sanitize", function()
    it("json.null pasa a nil", function()
        local out = DTO.sanitize(valid())
        assert.is_nil(out.events[1].start)
        assert.is_nil(out.events[1]["end"])
        assert.is_nil(out.events[1].location)
        assert.equals("Meet", out.events[2].location)
    end)

    it("weather = null y events = null se tratan como ausentes", function()
        local t = valid(); t.weather = json.null; t.events = json.null
        local out = DTO.sanitize(t)
        assert.is_nil(out.weather)
        assert.is_nil(out.events)
        assert.equals(0, out.events_total)
    end)

    it("temp = 999 se muestra como 60", function()
        local t = valid(); t.weather.temp = 999; t.weather.t_min = -999
        local out = DTO.sanitize(t)
        assert.equals(60, out.weather.temp)
        assert.equals(-60, out.weather.t_min)
    end)

    it("icono desconocido pasa a unknown", function()
        local t = valid(); t.weather.icon = "tornado"; t.weather.hourly[1].icon = "meteor"
        local out = DTO.sanitize(t)
        assert.equals("unknown", out.weather.icon)
        assert.equals("unknown", out.weather.hourly[1].icon)
    end)

    it("título de 80 caracteres con emojis se trunca a 60 terminando en …", function()
        local t = valid()
        t.events[2].title = string.rep("ñ😀", 40) -- 80 caracteres
        local out = DTO.sanitize(t)
        local title = out.events[2].title
        assert.equals("…", title:sub(-3))
        -- 59 caracteres + "…" = 60; comprobamos que no hay bytes cortados
        local chars = 0
        for _ in title:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars = chars + 1 end
        assert.equals(60, chars)
        assert.equals(title, title:gsub("[\128-\191]+$", function(tail)
            return tail -- una cola de continuación sin inicio indicaría corte a mitad de carácter
        end))
        assert.is_nil(title:match("[\194-\244]$"))
    end)

    it("recorta arreglos a sus máximos y respeta display.max_events", function()
        local t = valid()
        t.events = {}
        for i = 1, 12 do t.events[i] = { title = "E" .. i, all_day = false, start = "10:00", ["end"] = "11:00" } end
        t.events_total = 12
        local out = DTO.sanitize(t, { max_events = 8 })
        assert.equals(8, #out.events)
        assert.equals(12, out.events_total)
        assert.equals(3, #DTO.sanitize(t, { max_events = 3 }).events)
        t.weather.hourly = {}
        for i = 1, 7 do t.weather.hourly[i] = { time = "1" .. i .. ":00", temp = 10, icon = "cloudy" } end
        assert.equals(4, #DTO.sanitize(t).weather.hourly)
    end)

    it("descarta horas mal formadas y usa (Sin título) para títulos vacíos", function()
        local t = valid()
        t.events[2].start = "25:99"; t.events[2].title = "   "
        local out = DTO.sanitize(t)
        assert.is_nil(out.events[2].start)
        assert.equals("(Sin título)", out.events[2].title)
    end)

    it("all_day fuerza start y end a nil; events_total nunca es menor que los eventos", function()
        local t = valid(); t.events[1].start = "10:00"; t.events_total = 0
        local out = DTO.sanitize(t)
        assert.is_nil(out.events[1].start)
        assert.equals(2, out.events_total)
    end)
end)

describe("dto.truncateUtf8", function()
    it("no toca lo corto y colapsa espacios", function()
        assert.equals("a b", DTO.truncateUtf8("  a \n  b ", 10))
    end)
    it("cuenta caracteres, no bytes", function()
        assert.equals("ééé", DTO.truncateUtf8("ééé", 3))
        assert.equals("éé…", DTO.truncateUtf8("éééé", 3))
    end)
    it("tolera entradas que no son texto", function()
        assert.equals("", DTO.truncateUtf8(nil, 5))
    end)
end)
