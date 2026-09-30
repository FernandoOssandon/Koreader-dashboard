-- Vista E-Ink del dashboard (design D11). Sólo pinta un ViewModel: no conoce la red ni el origen de los datos.
-- Blanco y negro puros, sin fondos grises; todo escalado por Screen:scaleBySize() o por porcentajes.
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local F = require("dashboard/format_es")

local Screen = Device.screen

local DashboardWidget = InputContainer:extend{
    name = "dashboard_widget",
    covers_fullscreen = true,
    view_model = nil,  -- ViewModel (ver view_model.lua)
    display = nil,     -- cfg.display
    icons_root = nil,  -- carpeta del plugin, con "/" final
    on_tap = nil,      -- si existe, un toque cierra la vista (Vista previa)
}

local function text(str, face, size, max_width)
    return TextWidget:new{
        text = str, face = Font:getFace(face, size), max_width = max_width, fgcolor = Blitbuffer.COLOR_BLACK,
    }
end

local function height(w) return w:getSize().h end

function DashboardWidget:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if self.on_tap then
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    self[1] = self:_build()
end

function DashboardWidget:onTap()
    if self.on_tap then self.on_tap() end
    return true
end

-- Un icono que falta no debe romper todo el dashboard: se deja el hueco en blanco
function DashboardWidget:_icon(rel_path, size)
    local ok, w = pcall(function()
        return ImageWidget:new{
            file = self.icons_root .. rel_path, width = size, height = size, scale_factor = 0, alpha = true,
        }
    end)
    return ok and w or HorizontalSpan:new{ width = size }
end

function DashboardWidget:_header(vm, inner_w)
    local g = VerticalGroup:new{ align = "left", text(vm.header.title, "tfont", 30, inner_w) }
    if vm.header.subtitle ~= "" then g[#g + 1] = text(vm.header.subtitle, "cfont", 18, inner_w) end
    return g
end

function DashboardWidget:_footer(vm, inner_w)
    local left = text(vm.footer.left, vm.footer.warn and "tfont" or "cfont", 18, math.floor(inner_w * 0.62))
    local right = text(vm.footer.right, "cfont", 18, inner_w - left:getSize().w - Screen:scaleBySize(10))
    local h = math.max(height(left), height(right))
    local dimen = Geom:new{ w = inner_w, h = h }
    return OverlapGroup:new{
        dimen = dimen,
        LeftContainer:new{ dimen = dimen, left },
        RightContainer:new{ dimen = dimen, right },
    }
end

function DashboardWidget:_weather(vm, inner_w)
    local w = vm.weather
    local gap = Screen:scaleBySize(12)
    local icon_sz = Screen:scaleBySize(80)
    local info_w = math.floor(inner_w * 0.40)

    local info = VerticalGroup:new{
        align = "left",
        text(w.temp, "tfont", 56, info_w),
        text(w.desc, "cfont", 20, info_w),
        text(w.range, "cfont", 18, info_w),
        text(w.extra, "cfont", 18, info_w),
    }
    local left = HorizontalGroup:new{
        align = "center", self:_icon(w.icon_path, icon_sz), HorizontalSpan:new{ width = gap }, info,
    }
    local left_w = left:getSize().w

    -- Franjas horarias: sólo en vertical y las que quepan en el ancho que queda
    local hourly
    local landscape = Screen:getWidth() > Screen:getHeight()
    if not landscape and #w.hourly > 0 then
        local avail = inner_w - left_w - gap
        local min_col = Screen:scaleBySize(56)
        local n = math.min(#w.hourly, math.floor(avail / min_col))
        if n > 0 then
            local col_w = math.min(math.floor(avail / n), Screen:scaleBySize(84))
            hourly = HorizontalGroup:new{ align = "top" }
            for i = 1, n do
                local h = w.hourly[i]
                local col = VerticalGroup:new{
                    align = "center",
                    text(h.time, "cfont", 16, col_w),
                    self:_icon(h.icon_path, Screen:scaleBySize(44)),
                    text(h.temp, "cfont", 18, col_w),
                }
                hourly[#hourly + 1] = CenterContainer:new{ dimen = Geom:new{ w = col_w, h = height(col) }, col }
            end
        end
    end

    local row_h = math.max(height(left), hourly and height(hourly) or 0)
    local dimen = Geom:new{ w = inner_w, h = row_h }
    local row = OverlapGroup:new{ dimen = dimen, LeftContainer:new{ dimen = dimen, left } }
    if hourly then row[#row + 1] = RightContainer:new{ dimen = dimen, hourly } end

    if not w.note then return row end
    return VerticalGroup:new{ align = "left", row, text("⚠ " .. w.note, "cfont", 16, inner_w) }
end

-- Añade filas mientras quepan; las que sobran se resumen como "+N más".
function DashboardWidget:_agenda(vm, inner_w, avail_h)
    local gap = Screen:scaleBySize(8)
    local g = VerticalGroup:new{ align = "left", text("Agenda de hoy", "tfont", 22, inner_w) }
    g[#g + 1] = VerticalSpan:new{ width = gap }
    local used = height(g[1]) + gap

    if vm.agenda_placeholder then
        g[#g + 1] = text(vm.agenda_placeholder, "cfont", 22, inner_w)
        return g
    end

    local time_w = math.floor(inner_w * 0.26)
    local text_w = inner_w - time_w - Screen:scaleBySize(10)
    local rows, heights = {}, {}
    for i, r in ipairs(vm.agenda.rows) do
        local right = VerticalGroup:new{ align = "left", text(r.title, "cfont", 20, text_w) }
        if r.sub and r.sub ~= "" then right[#right + 1] = text(r.sub, "cfont", 16, text_w) end
        local h = height(right)
        rows[i] = HorizontalGroup:new{
            align = "top",
            LeftContainer:new{ dimen = Geom:new{ w = time_w, h = h }, text(r.time, "tfont", 18, time_w) },
            HorizontalSpan:new{ width = Screen:scaleBySize(10) },
            right,
        }
        heights[i] = h
    end

    local total = vm.agenda.total
    local more_h = height(text(F.more(99), "cfont", 18, inner_w)) + gap
    local n, acc = 0, 0
    for i = 1, #rows do
        local need = acc + heights[i] + gap
        local reserve = (total - i > 0) and more_h or 0
        if used + need + reserve > avail_h then break end
        n, acc = i, need
    end
    for i = 1, n do
        g[#g + 1] = rows[i]
        g[#g + 1] = VerticalSpan:new{ width = gap }
    end
    if total - n > 0 then g[#g + 1] = text(F.more(total - n), "cfont", 18, inner_w) end
    return g
end

function DashboardWidget:_build()
    local vm = self.view_model
    local W, H = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(20)
    local inner_w, inner_h = W - 2 * pad, H - 2 * pad
    local gap = Screen:scaleBySize(10)
    local line_h = math.max(2, Screen:scaleBySize(2)) -- ≥ 2 px físicos
    local function line()
        return LineWidget:new{ dimen = Geom:new{ w = inner_w, h = line_h }, background = Blitbuffer.COLOR_BLACK }
    end

    local footer = self:_footer(vm, inner_w)
    local footer_h = height(footer)
    local top = VerticalGroup:new{ align = "left" }
    local used = 0
    local function add(w, h)
        top[#top + 1] = w
        used = used + (h or height(w))
    end
    local function space(h) add(VerticalSpan:new{ width = h }, h) end

    add(self:_header(vm, inner_w))
    space(gap)
    add(line(), line_h)
    space(gap)

    if vm.minimal then
        local avail = inner_h - used - footer_h - gap
        add(CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = math.max(avail, 0) },
            text(vm.message, "cfont", 24, inner_w),
        }, math.max(avail, 0))
    else
        if vm.weather then
            add(self:_weather(vm, inner_w))
        else
            local ph = text(vm.weather_placeholder, "cfont", 22, inner_w)
            add(CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = height(ph) + 2 * gap }, ph }, height(ph) + 2 * gap)
        end
        space(gap)
        add(line(), line_h)
        space(gap)
        add(self:_agenda(vm, inner_w, inner_h - used - footer_h - gap))
    end

    local inner = Geom:new{ w = inner_w, h = inner_h }
    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, margin = 0, padding = pad,
        width = W, height = H,
        OverlapGroup:new{ dimen = inner, top, BottomContainer:new{ dimen = inner, footer } },
    }
end

return DashboardWidget
