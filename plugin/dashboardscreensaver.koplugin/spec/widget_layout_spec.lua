-- Prueba de humo del árbol de widgets con stubs de KOReader: no sustituye a las capturas en el
-- emulador, pero detecta errores de ejecución y desbordes de layout en varias resoluciones.
local kostubs = require("kostubs")
kostubs.install()

local VM = require("dashboard/view_model")
local DashboardWidget = require("dashboard/dashboard_widget")

local DEVICE = { battery = 78, charging = false, date = "2026-09-23", weekday = 3 }
local DISPLAY = { max_events = 8, show_hourly = true, show_location = true }
local LIVE = { origin = "live", age_s = 0, level = "fresh" }

local function dto(over)
    local d = {
        v = 1, source = "backend", generated_at = "2026-09-23T13:40:00-03:00", generated_ts = 1, date = "2026-09-23",
        weekday = 3, warnings = {}, events_total = 0,
        weather = { location = "Santiago", temp = 18, feels_like = 17, t_min = 9, t_max = 22, code = 2,
                    icon = "partly_cloudy_day", desc = "Parcialmente nublado", pop = 10,
                    hourly = { { time = "16:00", temp = 21, icon = "clear_day" }, { time = "19:00", temp = 17, icon = "cloudy" },
                               { time = "22:00", temp = 13, icon = "clear_night" }, { time = "01:00", temp = 11, icon = "rain" } } },
        events = {},
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end

local function events(n, title)
    local out = {}
    for i = 1, n do
        out[i] = { title = title or ("Evento número " .. i), all_day = i == 1, start = "1" .. (i % 10) .. ":00",
                   ["end"] = "1" .. (i % 10) .. ":45", location = "Av. Providencia 1234, Santiago" }
    end
    return out
end

local FIXTURES = {
    { "completo", dto({ events = events(3), events_total = 3 }), LIVE },
    { "sin clima", dto({ weather = nil, events = events(2), events_total = 2 }), LIVE },
    { "sin eventos", dto({ events = {} }), LIVE },
    { "agenda no disponible", dto({ events = nil }), LIVE },
    { "8 eventos largos", dto({ events = events(8, string.rep("Reunión de planificación trimestral ", 3)), events_total = 12 }), LIVE },
    { "stale", dto({ events = events(3), events_total = 3 }), { origin = "cache", age_s = 5 * 3600, level = "stale", err = "E_NO_NETWORK" } },
    { "expirado", dto({ events = events(3), events_total = 3 }), { origin = "cache", age_s = 3600, level = "expired", reason = "date" } },
    { "sin caché", nil, { origin = "none", level = "expired", err = "E_NO_NETWORK" } },
}

local SCREENS = { { 600, 800 }, { 1072, 1448 }, { 1264, 1680 }, { 800, 600 } } -- las últimas: Oasis/Scribe y horizontal

-- Recorre el árbol y junta los widgets con `text`
local function collect(node, acc)
    acc = acc or {}
    if type(node) ~= "table" then return acc end
    if node.text then acc[#acc + 1] = node end
    for _, child in ipairs(node) do collect(child, acc) end
    return acc
end

local function build(dto_, freshness, screen)
    kostubs.set_screen(screen[1], screen[2])
    local vm = VM.build(dto_, DEVICE, freshness, DISPLAY)
    return DashboardWidget:new{ view_model = vm, display = DISPLAY, icons_root = "/plugin/" }, vm
end

describe("dashboard_widget (layout con stubs)", function()
    for _, screen in ipairs(SCREENS) do
        for _, fx in ipairs(FIXTURES) do
            it(("%s en %dx%d: cabe en pantalla y ningún texto se sale de los márgenes"):format(fx[1], screen[1], screen[2]), function()
                local widget = build(fx[2], fx[3], screen)
                local W, H = screen[1], screen[2]
                local pad = 20
                local inner_w, inner_h = W - 2 * pad, H - 2 * pad

                local overlap = widget[1][1]
                local top, bottom = overlap[1], overlap[2]
                local footer_h = bottom[1]:getSize().h
                assert.is_true(top:getSize().h + footer_h <= inner_h,
                    ("el contenido (%d) + pie (%d) supera el alto útil (%d)"):format(top:getSize().h, footer_h, inner_h))
                for _, t in ipairs(collect(widget)) do
                    assert.is_true(t:getSize().w <= inner_w, "texto fuera de los márgenes: " .. t.text)
                end
                assert.equals(W, widget.dimen.w)
                assert.equals(H, widget.dimen.h)
            end)
        end
    end

    it("8 eventos en 600x800: las filas que no caben se resumen como '+N más'", function()
        local widget = build(FIXTURES[5][2], FIXTURES[5][3], { 600, 800 })
        local texts = {}
        for _, t in ipairs(collect(widget)) do texts[#texts + 1] = t.text end
        local more
        for _, s in ipairs(texts) do if s:match("^%+%d+ más$") then more = s end end
        assert.is_not_nil(more, "debería haber una línea '+N más'")
        local shown = 0
        for _, s in ipairs(texts) do if s:match("^Reunión de planificación") then shown = shown + 1 end end
        assert.equals(12, shown + tonumber(more:match("%d+")))
    end)

    it("una agenda corta muestra todas las filas sin '+N más'", function()
        local widget = build(FIXTURES[1][2], FIXTURES[1][3], { 1264, 1680 })
        for _, t in ipairs(collect(widget)) do assert.is_nil(t.text:match("más$")) end
    end)

    it("las franjas horarias desaparecen en horizontal", function()
        local function count_times(screen)
            local widget = build(FIXTURES[1][2], FIXTURES[1][3], screen)
            local n = 0
            for _, t in ipairs(collect(widget)) do
                if t.text:match("^%d%d:%d%d$") and t.face.size == 16 then n = n + 1 end
            end
            return n
        end
        assert.is_true(count_times({ 600, 800 }) > 0)
        assert.equals(0, count_times({ 800, 600 }))
    end)

    it("sólo pinta en blanco y negro: el fondo es blanco y las líneas miden ≥ 2 px", function()
        local widget = build(FIXTURES[1][2], FIXTURES[1][3], { 600, 800 })
        assert.equals("white", widget[1].background)
        local function lines(node, acc)
            acc = acc or {}
            if type(node) ~= "table" then return acc end
            if node.background == "black" and node.dimen then acc[#acc + 1] = node end
            for _, c in ipairs(node) do lines(c, acc) end
            return acc
        end
        local found = lines(widget)
        assert.is_true(#found >= 2)
        for _, l in ipairs(found) do assert.is_true(l.dimen.h >= 2) end
    end)

    it("con on_tap, un toque llama al callback y consume el evento", function()
        kostubs.set_screen(600, 800)
        local called = false
        local vm = VM.build(FIXTURES[1][2], DEVICE, LIVE, DISPLAY)
        local w = DashboardWidget:new{ view_model = vm, display = DISPLAY, icons_root = "/", on_tap = function() called = true end }
        assert.is_true(w:onTap())
        assert.is_true(called)
        assert.is_not_nil(w.ges_events.Tap)
    end)

    it("sin on_tap no registra gestos", function()
        local w = build(FIXTURES[1][2], FIXTURES[1][3], { 600, 800 })
        assert.is_nil(w.ges_events)
    end)
end)
