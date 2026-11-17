--[[--
Text boxes on a drawing: memos' `text` elements (@usememos/canvas
`TextElement`), typed on the Kindle and moved or resized on the page.

A box is kept in scene units, as memos keeps it: `x`, `y` its top left,
`width` where its lines wrap (`autoWidth = false`), `height` (at least its
lines'), `fontSize` (memos' default 20), `fontFamily` (memos' default),
`text` with its line breaks. The drawing screen draws it into the page (so
the PNG shows it) and the sketch (`gzreader_sketch.lua`) moves it and keeps
its undo. memos opens it as a text box it can edit too.
]]

local Drawing = require("gzreader_drawing")

local DrawText = {
    FONT = "system-ui, sans-serif", -- (memos' editor's own)
    SIZE = 20, -- scene units (memos' default)
    LINE_HEIGHT = 1.25, -- memos' (text/layout LINE_HEIGHT)
    MIN_WIDTH = 40, -- scene units: a box can't be made narrower
}

--- JSON null (memos checks a text's `containerId` is null or a string: left
--- out, it would refuse the scene). Drawing.encode writes a function as null.
DrawText.NULL = function() end

--- A new box at scene point (x, y), `width` wide, with `text`, in `color` ("#rrggbb"; nil: memos' ink).
function DrawText.element(x, y, width, text, color, font_size)
    local size = font_size or DrawText.SIZE
    local lines = select(2, tostring(text or ""):gsub("\n", "\n")) + 1
    return {
        id = Drawing.randomId(),
        type = "text",
        x = Drawing.round2(x),
        y = Drawing.round2(y),
        width = Drawing.round2(math.max(DrawText.MIN_WIDTH, width)),
        height = Drawing.round2(lines * size * DrawText.LINE_HEIGHT),
        angle = 0,
        strokeColor = color or Drawing.INK,
        backgroundColor = "transparent",
        strokeWidth = 2,
        opacity = 100,
        isDeleted = false,
        groupIds = Drawing.list(),
        boundElements = Drawing.list(),
        seed = Drawing.randomSeed(),
        locked = false,
        text = tostring(text or ""),
        fontSize = size,
        fontFamily = DrawText.FONT,
        textAlign = "left",
        autoWidth = false,
        containerId = DrawText.NULL,
    }
end

--- What a box's undo needs: where it is, how big, what it says, whether it's there.
function DrawText.snap(el, gone)
    return { x = el.x, y = el.y, width = el.width, height = el.height, text = el.text, gone = gone == true }
end

--- A box put back as `s` was (DrawText.snap). Returns whether it's there.
function DrawText.restore(el, s)
    el.x, el.y, el.width, el.height, el.text = s.x, s.y, s.width, s.height, s.text
    return not s.gone
end

--- Its box on the canvas (canvas pixels), through `toCanvas` (the sketch's).
function DrawText.rect(el, toCanvas)
    local x0, y0 = toCanvas(tonumber(el.x) or 0, tonumber(el.y) or 0)
    local x1, y1 = toCanvas((tonumber(el.x) or 0) + (tonumber(el.width) or 0), (tonumber(el.y) or 0) + (tonumber(el.height) or 0))
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

--- Which part of a box (canvas pixels `r`) a point is on: "resize" (the
--- handle at its bottom right corner, `handle` pixels, reaching a little
--- outside it), "move" (anywhere else in it), or nil.
function DrawText.partAt(r, x, y, handle)
    local hs = handle or 40
    if x >= r.x + r.w - hs and x <= r.x + r.w + hs / 2 and y >= r.y + r.h - hs and y <= r.y + r.h + hs / 2 then
        return "resize"
    end
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return "move" end
    return nil
end

return DrawText
