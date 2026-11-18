-- The pencil draws with a grain (graphite on the paper's tooth): only some
-- of a line's pixels are marked, more of them the harder the pen presses.
-- A light stroke, a medium one and a hard one with the pencil, then one
-- with the pen for comparison; the page's ink is counted under each.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh pencil_texture.lua <out>
-- Checks go to <out>/pencil-texture-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function stroke(E, y, pressure)
    local pts = {}
    for i = 0, 20 do pts[#pts + 1] = { W * 0.25 + i * W * 0.025, y + math.sin(i / 3) * 12, pressure } end
    E.pen(pts, 0.5)
end
--- Of the page's pixels in a band around y: how many are marked, and their mean tone.
local function band(d, y)
    local bb, c = d.canvas_bb, d.canvas
    local marked, sum, total = 0, 0, 0
    for yy = math.floor(y - c.y - 40), math.floor(y - c.y + 40) do
        for xx = math.floor(W * 0.3), math.floor(W * 0.7) do
            local v = bb:getPixel(xx, yy):getColor8().a
            total = total + 1
            if v < 0xF0 then marked = marked + 1; sum = sum + v end
        end
    end
    return marked, marked > 0 and math.floor(sum / marked) or 255, total
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:saveSetting("gzreader_drawing_paper", "blank")
    require("gzreader_drawscreen").show{ on_done = function() end, on_cancel = function() end }
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    d:setWriting("pencil"); d:setTool("pen", 7); d:setFlyout(nil)
    stroke(E, H * 0.3, 500)
end, after = 3 })
add({ fn = function(E) stroke(E, H * 0.4, 2000) end, after = 3 })
add({ fn = function(E) stroke(E, H * 0.5, 4000) end, after = 3 })
add({ fn = function(E)
    local d = screen()
    d:setWriting("pen")
    stroke(E, H * 0.6, 2000)
end, after = 3 })
add({ shot = "1-pencil-light-medium-hard-then-pen", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local l, lt = band(d, H * 0.3)
    local m, mt = band(d, H * 0.4)
    local h, ht = band(d, H * 0.5)
    local _, pt = band(d, H * 0.6)
    check(l > 0 and m > l * 1.3 and h > m * 1.2, "the pencil marks more of the paper the harder it's pressed (" .. l .. ", " .. m .. ", " .. h .. " pixels)")
    check(lt > 0x20 and lt < 0x50 and pt == 0, "its marks are dark grey specks (tone " .. lt .. "), the pen's solid black (" .. pt .. ")")
    -- a grain: marked and unmarked pixels side by side inside the line (the pen's line has none unmarked)
    local c = d.canvas
    local y = math.floor(H * 0.4 - c.y + math.sin(10 / 3) * 12)
    local x0 = math.floor(W * 0.5)
    local on, off = 0, 0
    for yy = y - 2, y + 2 do
        for xx = x0 - 10, x0 + 10 do
            if d.canvas_bb:getPixel(xx, yy):getColor8().a < 0xF0 then on = on + 1 else off = off + 1 end
        end
    end
    check(on > 20 and off > 20, "…with paper showing between them in the middle of the line (" .. on .. " marked, " .. off .. " not)")
    local st = d.sketch:live()
    check(#st == 4 and st[1].kind == "pencil" and mt > 0 and ht > 0, "four strokes kept (three pencil, one pen)")
    -- drawn again from the strokes (undo, redo: the page repainted): the same specks
    local before = {}
    for xx = x0 - 30, x0 + 30 do before[#before + 1] = d.canvas_bb:getPixel(xx, y):getColor8().a end
    d.sketch:undo(); d.sketch:redo(); d:redrawAll()
    local same = true
    for i = 1, #before do if d.canvas_bb:getPixel(x0 - 31 + i, y):getColor8().a ~= before[i] then same = false end end
    check(same, "the page drawn again from its strokes: the same grain, pixel for pixel")
    -- saved: the pencil's strokes are see-through strokes in the drawing (Memos' editor can
    -- move and erase them), no picture of them; the picture of the page has the grain
    local res = d:save()
    local Drawing = require("gzreader_drawing")
    local scene = res and Drawing.readFile(res.path)
    local layer, pencil_shown, pen_shown = nil, 0, 0
    for _i, e in ipairs(scene and scene.elements or {}) do
        if e.type == "image" and type(e.customData) == "table" and e.customData.gzLayer then layer = e end
        if e.type == "freedraw" and e.opacity == 70 and e.customData and e.customData.gzTool == "pencil" then pencil_shown = pencil_shown + 1 end
        if e.type == "freedraw" and e.opacity == 100 then pen_shown = pen_shown + 1 end
    end
    check(scene and not layer and pencil_shown == 3 and pen_shown == 1,
        "saved: the pencil's 3 strokes are strokes in the drawing (shown, see-through: editable in Memos), the pen's as ever, no picture of them")
    -- opened again: three pencil strokes and one pen
    local Sketch = require("gzreader_sketch")
    local back = scene and Sketch.fromScene(scene, { canvas = d.canvas, per_unit = d.sketch.per_unit, tap_slop = 8 })
    check(back and #back:live() == 4 and back:live()[1].kind == "pencil" and #back.locked == 0, "opened again: the same four strokes, no extra picture")
    if res then os.remove(res.path) end
    local f = io.open(E.out .. "/pencil-texture-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l2 in ipairs(lines) do E.say("check", l2) end
end, after = 1 })
return s
