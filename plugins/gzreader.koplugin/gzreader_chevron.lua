--[[--
A chevron drawn with the line's own pixels: › for a folded section, ⌄ for an
open one, as Memos' web app marks a `<details>` section. (The icon font
bundled with GZreader has a right chevron but no down one.)

    Chevron.widget{ size = S(20), open = true }
    Chevron.paint(bb, x, y, size, open, color)
]]

local Blitbuffer = require("ffi/blitbuffer")

local Chevron = {}

--- The chevron's two strokes inside a `size` square at x, y: lists of
--- { x, y } points from one end to the tip and on to the other end.
function Chevron.points(x, y, size, open)
    local a = math.floor(size * 0.3)
    local b = size - a
    local mid = math.floor(size / 2)
    if open then
        return { { x + a - math.floor(size * 0.08), y + a + math.floor(size * 0.06) }, { x + mid, y + b - math.floor(size * 0.06) },
            { x + b + math.floor(size * 0.08), y + a + math.floor(size * 0.06) } }
    end
    return { { x + a + math.floor(size * 0.06), y + a - math.floor(size * 0.08) }, { x + b - math.floor(size * 0.06), y + mid },
        { x + a + math.floor(size * 0.06), y + b + math.floor(size * 0.08) } }
end

function Chevron.paint(bb, x, y, size, open, color)
    color = color or Blitbuffer.COLOR_BLACK
    local pts = Chevron.points(x, y, size, open)
    local t = math.max(2, math.floor(size / 9)) -- (the stroke's thickness)
    for k = 1, #pts - 1 do
        local x0, y0, x1, y1 = pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2]
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
        for s = 0, steps do
            local px = math.floor(x0 + (x1 - x0) * s / steps + 0.5)
            local py = math.floor(y0 + (y1 - y0) * s / steps + 0.5)
            bb:paintRect(px - math.floor(t / 2), py - math.floor(t / 2), t, t, color)
        end
    end
end

local ChevronWidget -- (made the first time: the editor only paints)

--- A widget `size` square: { size, open, color }.
function Chevron.widget(o)
    if not ChevronWidget then
        local Geom = require("ui/geometry")
        ChevronWidget = require("ui/widget/widget"):extend{ size = 20, open = false, color = nil }
        function ChevronWidget:getSize() return Geom:new{ w = self.size, h = self.size } end
        function ChevronWidget:paintTo(bb, x, y)
            self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
            Chevron.paint(bb, x, y, self.size, self.open, self.color)
        end
    end
    return ChevronWidget:new(o)
end

return Chevron
