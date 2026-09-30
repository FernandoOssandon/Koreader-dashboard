local CacheManager = require("dashboard/cache_manager")
local MemFS = require("memfs")
local logger = require("logger")
local json = require("json")

local PATH = "/cache/dashboardscreensaver/dashboard_cache.json"
local CFG = { stale_after_s = 10800, max_age_s = 86400 }

local function dto(date)
    return {
        v = 1, source = "backend", generated_at = "x", generated_ts = 100, ttl_s = 900, tz = "America/Santiago",
        date = date or "2026-09-23", weekday = 3, warnings = {}, events_total = 0,
        weather = { location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
                    icon = "cloudy", desc = "Nublado", pop = 10, hourly = {} },
        events = {},
    }
end

local clock
local function new(files)
    local fs = MemFS.new(files)
    clock = 1000
    return CacheManager.new({ path = PATH, fs = fs, json = json, now = function() return clock end }), fs
end

describe("cache_manager", function()
    before_each(function() logger.reset() end)

    it("no hay caché → load devuelve nil", function()
        local c = new()
        assert.is_nil(c:load())
    end)

    it("round-trip: save y load", function()
        local c, fs = new()
        assert.is_true(c:save(dto(), 'W/"abc"', "backend"))
        local e = c:load()
        assert.equals(1000, e.saved_at)
        assert.equals(1000, e.validated_at)
        assert.equals('W/"abc"', e.etag)
        assert.equals("backend", e.provider)
        assert.equals("2026-09-23", e.dto.date)
        assert.equals(18, e.dto.weather.temp)
        assert.is_false(fs:exists(PATH .. ".tmp")) -- el .tmp se renombró
        assert.is_true(fs.dirs["/cache/dashboardscreensaver"])
    end)

    it("archivo truncado → nil y se borra", function()
        local c, fs = new()
        c:save(dto(), nil, "backend")
        fs.files[PATH] = fs.files[PATH]:sub(1, math.floor(#fs.files[PATH] / 2))
        assert.is_nil(c:load())
        assert.is_false(fs:exists(PATH))
        assert.truthy(logger.text():find("corrupto", 1, true))
    end)

    it("otra versión de formato o dto inválido → se borra", function()
        local c, fs = new({ [PATH] = json.encode({ cache_version = 2, saved_at = 1, validated_at = 1, dto = dto() }) })
        assert.is_nil(c:load())
        assert.is_false(fs:exists(PATH))
        local bad = dto(); bad.v = 2
        fs.files[PATH] = json.encode({ cache_version = 1, saved_at = 1, validated_at = 1, dto = bad })
        assert.is_nil(c:load())
        assert.is_false(fs:exists(PATH))
    end)

    it("una escritura fallida deja intacto el caché anterior", function()
        local c, fs = new()
        c:save(dto("2026-09-23"), "e1", "backend")
        fs.fail_write = true
        assert.is_false(c:save(dto("2026-09-24"), "e2", "backend"))
        fs.fail_write = false
        local e = c:load()
        assert.equals("2026-09-23", e.dto.date)
        assert.equals("e1", e.etag)
        assert.is_false(fs:exists(PATH .. ".tmp"))
    end)

    it("touch sólo cambia validated_at", function()
        local c = new()
        c:save(dto(), "e1", "backend")
        clock = 2500
        assert.is_true(c:touch())
        local e = c:load()
        assert.equals(1000, e.saved_at)
        assert.equals(2500, e.validated_at)
        assert.equals("e1", e.etag)
    end)

    it("touch sin caché no falla", function()
        local c = new()
        assert.is_false(c:touch())
    end)

    it("clear borra el archivo", function()
        local c, fs = new()
        c:save(dto(), nil, "backend")
        c:clear()
        assert.is_false(fs:exists(PATH))
    end)

    describe("freshness", function()
        local function entry(validated_at, date) return { validated_at = validated_at, dto = dto(date) } end
        local TODAY = "2026-09-23"

        it("sin entrada → none/expired", function()
            local f = CacheManager.freshness(nil, 5000, CFG, TODAY)
            assert.equals("none", f.origin)
            assert.equals("expired", f.level)
        end)

        it("fresh por debajo de stale_after_s", function()
            local f = CacheManager.freshness(entry(1000), 1000 + 10799, CFG, TODAY)
            assert.equals("fresh", f.level)
            assert.equals(10799, f.age_s)
            assert.equals("cache", f.origin)
        end)

        it("stale desde stale_after_s hasta max_age_s", function()
            assert.equals("stale", CacheManager.freshness(entry(1000), 1000 + 10800, CFG, TODAY).level)
            assert.equals("stale", CacheManager.freshness(entry(1000), 1000 + 5 * 3600, CFG, TODAY).level)
            assert.equals("stale", CacheManager.freshness(entry(1000), 1000 + 86399, CFG, TODAY).level)
        end)

        it("expired desde max_age_s", function()
            local f = CacheManager.freshness(entry(1000), 1000 + 86400, CFG, TODAY)
            assert.equals("expired", f.level)
            assert.equals("age", f.reason)
        end)

        it("expired si cambió el día", function()
            local f = CacheManager.freshness(entry(1000, "2026-09-22"), 1010, CFG, TODAY)
            assert.equals("expired", f.level)
            assert.equals("date", f.reason)
        end)

        it("expired si validated_at está en el futuro", function()
            local f = CacheManager.freshness(entry(5000), 1000, CFG, TODAY)
            assert.equals("expired", f.level)
            assert.equals("clock", f.reason)
            assert.equals(0, f.age_s)
        end)
    end)
end)
