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
    local f = io.open(E.out .. "/pencil-texture-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l2 in ipairs(lines) do E.say("check", l2) end
end, after = 1 })
return s
