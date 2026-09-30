-- Stubs mínimos de los módulos de KOReader (widgets, device, uimanager…) para ejecutar la capa de UI
-- en busted. Los tamaños son una aproximación (ancho de texto ≈ 0.55 × cuerpo), suficiente para
-- comprobar el layout: que nada se salga de los márgenes y que el ajuste de filas funcione.
local M = {}

local Base = {}
function Base:extend(t)
    t = t or {}
    t.__index = t
    return setmetatable(t, { __index = self })
end
function Base:new(o)
    o = setmetatable(o or {}, self)
    if o.init then o:init() end
    return o
end
function Base:getSize() return { w = 0, h = 0 } end

local function class(getSize)
    local c = Base:extend()
    c.getSize = getSize
    return c
end

local function dimen_size(self) return { w = self.dimen.w, h = self.dimen.h } end
local function sum_h(self)
    local w, h = 0, 0
    for _, c in ipairs(self) do local s = c:getSize(); w = math.max(w, s.w); h = h + s.h end
    return { w = w, h = h }
end
local function sum_w(self)
    local w, h = 0, 0
    for _, c in ipairs(self) do local s = c:getSize(); w = w + s.w; h = math.max(h, s.h) end
    return { w = w, h = h }
end

local function utf8_len(s)
    local n = 0
    for _ in tostring(s):gmatch("[^\128-\191]") do n = n + 1 end
    return n
end

--- screen = { w =, h = } ; se puede cambiar entre pruebas con M.set_screen
M.screen = { w = 600, h = 800 }
function M.set_screen(w, h) M.screen.w, M.screen.h = w, h end

function M.install()
    local p = package.preload
    p["ffi/blitbuffer"] = function() return { COLOR_WHITE = "white", COLOR_BLACK = "black" } end
    p["device"] = function()
        return { screen = {
            getWidth = function() return M.screen.w end,
            getHeight = function() return M.screen.h end,
            scaleBySize = function(_, n) return n end,
        }, getPowerDevice = function() return { getCapacity = function() return 78 end, isCharging = function() return false end } end }
    end
    p["ui/font"] = function() return { getFace = function(_, name, size) return { name = name, size = size } end } end
    p["ui/geometry"] = function() return { new = function(_, t) return t end } end
    p["ui/gesturerange"] = function() return { new = function(_, t) return t end } end
    p["ui/widget/textwidget"] = function()
        return class(function(self)
            local w = math.ceil(utf8_len(self.text) * self.face.size * 0.55)
            if self.max_width then w = math.min(w, self.max_width) end
            return { w = w, h = math.ceil(self.face.size * 1.35) }
        end)
    end
    p["ui/widget/imagewidget"] = function()
        return class(function(self) return { w = self.width, h = self.height } end)
    end
    p["ui/widget/horizontalspan"] = function() return class(function(self) return { w = self.width, h = 0 } end) end
    p["ui/widget/verticalspan"] = function() return class(function(self) return { w = 0, h = self.width } end) end
    p["ui/widget/linewidget"] = function() return class(dimen_size) end
    p["ui/widget/verticalgroup"] = function() return class(sum_h) end
    p["ui/widget/horizontalgroup"] = function() return class(sum_w) end
    p["ui/widget/overlapgroup"] = function() return class(dimen_size) end
    for _, name in ipairs({ "left", "right", "center", "bottom" }) do
        p["ui/widget/container/" .. name .. "container"] = function() return class(dimen_size) end
    end
    p["ui/widget/container/framecontainer"] = function()
        return class(function(self) return { w = self.width, h = self.height } end)
    end
    p["ui/widget/container/inputcontainer"] = function() return class(dimen_size) end
    p["ui/widget/container/widgetcontainer"] = function() return class(dimen_size) end
end

M.Base = Base
return M
