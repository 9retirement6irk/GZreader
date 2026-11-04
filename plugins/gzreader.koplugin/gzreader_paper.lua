--[[--
Paper for the Calendar tab (like the Notes tab's sticky notes): sheets with
a shadow on a grey desk, spiral bindings, a hook, a tear-off pad's binding
and torn edge, a paper clip. All drawn with rectangles and circles (e-ink:
greys only, no pictures to load).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Paper = {
    DESK = Blitbuffer.gray(0.09),
    SHADOW = Blitbuffer.gray(0.40),
    EDGE = Blitbuffer.gray(0.55),
    RULE = Blitbuffer.gray(0.20),
    UNDER = Blitbuffer.gray(0.04),
    HIGHLIGHT = Blitbuffer.gray(0.17),
}

local function sized(class)
    class.getSize = function(self) return Geom:new{ w = self.w, h = self.h } end
    return class
end

--- A white sheet with its shadow (`shadow` px down and right, outside w x h).
Paper.Sheet = sized(WidgetContainer:extend{ w = 0, h = 0, shadow = nil, bg = nil })
function Paper.Sheet:paintTo(bb, x, y)
    local sh = self.shadow or S(5)
    if sh > 0 then bb:paintRect(x + sh, y + sh, self.w, self.h, Paper.SHADOW) end
    bb:paintRect(x, y, self.w, self.h, self.bg or Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, self.w, self.h, 1, Paper.EDGE)
end

--- A spiral binding: rings over the top edge ("top", w long) or the left
--- edge ("left", h long). Place it so the holes sit just inside the sheet.
Paper.Coil = sized(WidgetContainer:extend{ w = 0, h = 0, side = "top", step = nil, gap = nil })
function Paper.Coil:init()
    if self.side == "top" then self.h = S(40) else self.w = S(44) end
end
function Paper.Coil:paintTo(bb, x, y)
    local step = self.step or S(26)
    local ring, len = S(8), S(30)
    local half = math.floor(ring / 2)
    local bw = math.max(2, S(3))
    local hole = math.max(2, S(4))
    local n = math.floor((self.side == "top" and self.w or self.h) / step)
    local off = math.floor(((self.side == "top" and self.w or self.h) - n * step) / 2)
    for i = 0, n - 1 do
        local c = off + i * step + math.floor(step / 2)
        local mid = math.floor((self.side == "top" and self.w or self.h) / 2)
        if self.gap and math.abs(c - mid) < self.gap / 2 then goto continue end
        if self.side == "top" then
            bb:paintCircle(x + c, y + S(31), hole, Blitbuffer.gray(0.75))
            bb:paintRect(x + c - half, y + S(3), ring, len, Blitbuffer.COLOR_WHITE)
            bb:paintBorder(x + c - half, y + S(3), ring, len, bw, Blitbuffer.COLOR_BLACK, half)
        else
            bb:paintCircle(x + S(32), y + c, hole, Blitbuffer.gray(0.75))
            bb:paintRect(x + S(3), y + c - half, len + S(2), ring, Blitbuffer.COLOR_WHITE)
            bb:paintBorder(x + S(3), y + c - half, len + S(2), ring, bw, Blitbuffer.COLOR_BLACK, half)
        end
        ::continue::
    end
end

--- The nail a wall calendar hangs on.
Paper.Hook = sized(WidgetContainer:extend{ w = 0, h = 0 })
function Paper.Hook:init() self.w, self.h = S(20), S(20) end
function Paper.Hook:paintTo(bb, x, y)
    local r = math.floor(self.w / 2)
    bb:paintCircle(x + r, y + r, r, Blitbuffer.gray(0.80), math.max(2, S(3)))
end

--- A tear-off pad's binding: a dark band with two staples.
Paper.Binding = sized(WidgetContainer:extend{ w = 0, h = 0 })
function Paper.Binding:paintTo(bb, x, y)
    bb:paintRoundedRect(x, y, self.w, self.h, Blitbuffer.gray(0.84), S(4))
    local sw, sh = S(46), math.max(2, S(6))
    for _i, f in ipairs({ 0.27, 0.73 }) do
        bb:paintRect(x + math.floor(self.w * f - sw / 2), y + math.floor((self.h - sh) / 2), sw, sh, Blitbuffer.gray(0.45))
    end
end

--- What's left of the pages torn off: a ragged strip.
Paper.Torn = sized(WidgetContainer:extend{ w = 0, h = 0 })
function Paper.Torn:paintTo(bb, x, y)
    local col = math.max(2, S(2))
    local teeth = S(18)
    for i = 0, math.floor(self.w / col) - 1 do
        local px = i * col
        local t = (px % teeth) / teeth
        local depth = math.floor(self.h * (0.35 + 0.65 * math.abs(t - 0.5) * 2) * (0.75 + 0.25 * ((i * 7) % 5) / 4))
        bb:paintRect(x + px, y, col, depth, Paper.UNDER)
    end
end

--- A paper clip (w x h, standing up).
Paper.Clip = sized(WidgetContainer:extend{ w = 0, h = 0 })
function Paper.Clip:init() self.w, self.h = S(30), S(72) end
function Paper.Clip:paintTo(bb, x, y)
    local bw = math.max(2, S(3))
    bb:paintBorder(x, y + S(14), self.w, self.h - S(14), bw, Blitbuffer.gray(0.85), math.floor(self.w / 2))
    bb:paintBorder(x + S(8), y, self.w - S(16), self.h - S(16), bw, Blitbuffer.gray(0.85), math.floor((self.w - S(16)) / 2))
end

--- Ruled lines every `pitch` px (a planner's page).
Paper.Ruled = sized(WidgetContainer:extend{ w = 0, h = 0, pitch = nil, first = nil })
function Paper.Ruled:paintTo(bb, x, y)
    local pitch = self.pitch or S(22)
    local ly = self.first or pitch
    while ly < self.h do
        bb:paintRect(x, y + ly, self.w, 1, Paper.RULE)
        ly = ly + pitch
    end
end

--- A dashed line (the tear-off page's perforation).
Paper.Dashed = sized(WidgetContainer:extend{ w = 0, h = 0 })
function Paper.Dashed:paintTo(bb, x, y)
    local dash, gap = S(8), S(5)
    local px = 0
    while px < self.w do
        bb:paintRect(x + px, y, math.min(dash, self.w - px), self.h, Paper.EDGE)
        px = px + dash + gap
    end
end

return Paper
