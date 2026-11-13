-- The drawing screen's input (gzreader_sketch.lua): finger drawing on touch
-- Kindles; pen-only drawing with palm rejection on pen Kindles (the Scribe);
-- the eraser, undo, clear; the PNG's crop and the memos scene.
--   luajit sketch_test.lua <gzreader.koplugin> <tests lib> [<koreader base>]
local PLUGIN, LIB, KOROOT = arg[1], arg[2], arg[3]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. (KOROOT and (KOROOT .. "/?.lua;") or "") .. package.path
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local dkjson = require("dkjson")
package.preload["json"] = function()
    return { decode = function(s) local v, _, err = dkjson.decode(s); if err then error(err) end; return v end,
        encode = function(v) return dkjson.encode(v) end }
end

package.preload["gettext"] = package.preload["gettext"] or function() return function(t) return t end end
local Sketch = require("gzreader_sketch")
local Drawing = require("gzreader_drawing")

local FINGER, PEN, ERASER = 0, 1, 2
local PEN_SLOT = 4
local CANVAS = { x = 0, y = 100, w = 1000, h = 1300 }

-- input frames, as KOReader's MTSlots
local function finger(slot, x, y) return { slot = slot, id = slot + 10, x = x, y = y, tool = FINGER } end
local function lift(slot, tool) return { slot = slot, id = -1, x = 0, y = 0, tool = tool or FINGER } end
local function pen(x, y, tool) return { slot = PEN_SLOT, id = PEN_SLOT, x = x, y = y, tool = tool or PEN } end
local function hover(x, y, tool) return { slot = PEN_SLOT, id = -1, x = x, y = y, tool = tool or PEN } end
local function penGone() return { slot = PEN_SLOT, id = -1, x = 0, y = 0, tool = FINGER } end

local function run(sk, frames, t0, dt)
    local t, all = t0 or 0, { segments = 0, taps = {}, redraw = false }
    for _i, f in ipairs(frames) do
        local out = sk:frame(f, t)
        all.segments = all.segments + #out.segments
        for _j, tap in ipairs(out.taps) do all.taps[#all.taps + 1] = tap end
        all.redraw = all.redraw or out.redraw
        t = t + (dt or 0.01)
    end
    return all, t
end

print("== which Kindles draw with a pen")
;(function()
    check(Sketch.penDevice({ input = { wacom_protocol = true }, model = "KindleScribe" }), "the Scribe (wacom protocol): a pen Kindle")
    check(Sketch.penDevice({ input = {}, model = "KindleScribe2" }), "…by its model too")
    check(not Sketch.penDevice({ input = {}, model = "KindlePaperWhite3" }), "a Paperwhite 3: a finger Kindle")
    check(not Sketch.penDevice(nil), "no device: no pen")
    check(Sketch.perUnitFor(300) == 2 and Sketch.perUnitFor(167) > 1 and Sketch.perUnitFor(100) == 1,
        "2 screen pixels per scene unit at 300 dpi (memos' 2x), never under 1")
    check(Sketch.radiusFor(1, 2) == 2 and Sketch.radiusFor(2, 2) == 3 and Sketch.radiusFor(4, 2) == 6,
        "radius 2 / 3 / 6 px for memos widths 1 / 2 / 4 at 300 dpi (as memos draws them: 0.42 of full width)")
end)()

print("== a finger Kindle (Paperwhite 3)")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    local out = run(sk, { { finger(0, 100, 200) }, { finger(0, 150, 220) }, { finger(0, 150, 220) }, { finger(0, 220, 300) }, { lift(0) } })
    check(#sk.strokes == 1 and #sk.strokes[1].points == 3, "a finger draws one stroke (a repeated point left out)")
    check(out.segments == 3, "each new point gives a segment to paint")
    check(sk.strokes[1].points[1][1] == 100 and sk.strokes[1].points[1][2] == 100, "points relative to the canvas")
    -- a second finger while drawing: ignored
    run(sk, { { finger(0, 300, 300) }, { finger(1, 600, 600), finger(0, 320, 310) }, { finger(1, 650, 650) }, { lift(1) }, { lift(0) } })
    check(#sk.strokes == 2 and #sk.strokes[2].points == 2, "a second finger while drawing doesn't draw")
    -- a tap outside the canvas: for the toolbar
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 505, 45) }, { lift(0) } })
    check(#out.taps == 1 and out.taps[1].x == 500 and out.taps[1].y == 40 and #sk.strokes == 2, "a tap above the canvas goes to the toolbar")
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 600, 45) }, { lift(0) } })
    check(#out.taps == 0, "a swipe up there isn't a tap")
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 500, 400) }, { lift(0) } })
    check(#out.taps == 0 and #sk.strokes == 2, "a contact that starts on the toolbar never draws")
end)()

print("== a pen Kindle (Scribe): only the pen draws")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    local out = run(sk, { { finger(0, 100, 200) }, { finger(0, 300, 400) }, { lift(0) } })
    check(#sk.strokes == 0 and out.segments == 0, "a finger on the canvas draws nothing")
    out = run(sk, { { hover(100, 200) }, { pen(100, 200) }, { pen(140, 260) }, { pen(180, 300) }, { hover(180, 300) }, { penGone() } })
    check(#sk.strokes == 1 and #sk.strokes[1].points == 3 and out.segments == 3, "the pen draws a stroke")
    check(sk.strokes[1].width == 2, "with the chosen width")
    out = run(sk, { { finger(0, 500, 40) }, { lift(0) } }, 10)
    check(#out.taps == 1 and not out.taps[1].pen, "with the pen away, a finger taps the toolbar")
    out = run(sk, { { hover(500, 40) }, { pen(500, 40) }, { hover(500, 40) }, { penGone() } }, 20)
    check(#out.taps == 1 and out.taps[1].pen, "the pen taps the toolbar")
end)()

print("== palm rejection")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    -- the pen hovers, the palm lands on the toolbar: ignored
    local out = run(sk, { { hover(300, 300) }, { finger(0, 500, 40) }, { lift(0) } }, 0)
    check(#out.taps == 0 and sk.stats.palm == 1, "pen hovering: a palm on the toolbar taps nothing")
    -- the palm down first (on the toolbar), then the pen comes: the palm's contact is dropped
    sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    out = run(sk, { { finger(0, 500, 40) }, { hover(300, 300) }, { pen(300, 300) }, { pen(350, 320) }, { finger(0, 501, 41) }, { lift(0) },
        { hover(350, 320) }, { penGone() } }, 0)
    check(#out.taps == 0 and #sk.strokes == 1, "a palm already down when the pen comes: its tap is dropped, the stroke drawn")
    -- writing with the hand resting on the canvas and moving
    sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    run(sk, { { hover(300, 300) }, { pen(300, 300), finger(0, 600, 700) }, { pen(320, 330), finger(0, 620, 720) },
        { pen(360, 350), finger(1, 640, 760) }, { hover(360, 350) }, { lift(0), lift(1) }, { penGone() } }, 0)
    check(#sk.strokes == 1 and #sk.strokes[1].points == 3, "a hand resting and sliding while writing: only the pen's stroke")
    -- just after the pen leaves: still ignored; later: a tap works again
    sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    run(sk, { { hover(300, 300) }, { penGone() } }, 0)
    sk:frame({ finger(0, 500, 40) }, 0.3); sk:frame({ lift(0) }, 0.35)
    local after = sk.stats.palm
    out = run(sk, { { finger(0, 500, 40) }, { lift(0) } }, 2)
    check(after == 1 and #out.taps == 1, "a finger 0.3 s after the pen left: ignored; 2 s after: taps")
    -- the pen's leaving missed: after PEN_TIMEOUT without a word from it, fingers work again
    sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    run(sk, { { hover(300, 300) } }, 0)
    out = run(sk, { { finger(0, 500, 40) }, { lift(0) } }, Sketch.PEN_TIMEOUT + Sketch.PEN_GRACE + 1)
    check(#out.taps == 1, "no word from the pen for a while: it counts as gone")
    -- a finger Kindle has no palm guard
    local f = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    check(f:palmGuard(0) == false, "a finger Kindle never ignores fingers")
end)()

print("== the eraser, undo, clear")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    run(sk, { { hover(100, 200) }, { pen(100, 200) }, { pen(300, 200) }, { hover(300, 200) },
        { pen(100, 600) }, { pen(300, 600) }, { hover(300, 600) }, { penGone() } }, 0)
    check(#sk:live() == 2, "two strokes")
    -- the pen's other end crosses the first stroke
    local out = run(sk, { { hover(200, 150, ERASER) }, { pen(200, 150, ERASER) }, { pen(200, 260, ERASER) }, { hover(200, 260, ERASER) }, { penGone() } }, 10)
    check(#sk:live() == 1 and out.redraw and sk:live()[1].points[1][2] == 500, "the pen's eraser end rubs out the stroke it crosses")
    check(sk:undo() and #sk:live() == 2, "undo brings it back")
    sk:setTool("eraser")
    run(sk, { { hover(200, 600) }, { pen(200, 600) }, { hover(200, 600) }, { penGone() } }, 20)
    check(#sk:live() == 1, "the Eraser tool: the pen tip rubs out too")
    sk:setWidth(4)
    check(sk.tool == "pen" and sk.width == 4, "choosing a width goes back to the pen")
    run(sk, { { hover(500, 900) }, { pen(500, 900) }, { pen(520, 940) }, { hover(520, 940) }, { penGone() } }, 30)
    check(#sk:live() == 2 and sk:live()[2].width == 4, "a thick stroke")
    check(sk:clear() and sk:isEmpty(), "clear empties the page")
    check(sk:undo() and #sk:live() == 2, "undo brings the page back")
    check(sk:undo() and #sk:live() == 1, "undo takes back the last stroke")
    check(sk:undo() and #sk:live() == 2, "undo takes back the Eraser tool's rubbing out")
    while sk:undo() do end
    check(sk:isEmpty() and not sk:canUndo(), "undo back to the empty page")
    check(not sk:clear(), "clearing an empty page changes nothing")
end)()

print("== the PNG's crop and the memos scene")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    check(sk:cropRect() == nil and sk:bounds() == nil, "nothing drawn: no crop")
    run(sk, { { finger(0, 200, 300) }, { finger(0, 400, 500) }, { lift(0) } })
    local b, c = sk:bounds(), sk:cropRect()
    check(b.x == 197 and b.y == 197 and b.w == 206, "bounds: the points, plus the ink's radius")
    check(c.x == 197 - 48 and c.y == 197 - 48 and c.w == 206 + 96, "crop: plus memos' padding (24 units = 48 px)")
    run(sk, { { finger(0, 5, 105) }, { finger(0, 10, 110) }, { lift(0) } })
    c = sk:cropRect()
    check(c.x == 0 and c.y == 0, "…never outside the canvas")
    local scene = sk:scene()
    check(#scene.elements == 2 and scene.elements[1].type == "freedraw", "the scene: one freedraw per stroke")
    local el = scene.elements[1]
    check(el.x == 100 and el.y == 100 and el.width == 100 and el.height == 100, "in scene units (canvas pixels / 2)")
    check(el.simulatePressure == true and el.strokeWidth == 2 and el.strokeColor == Drawing.INK, "width from speed, memos' ink")
    check(scene.appState.viewBackgroundColor == Drawing.PAPER, "on memos' paper")
    local text = Drawing.encode(scene)
    local back = Drawing.decode(text)
    check(back and #back.elements == 2, "it encodes as a scene memos reads")
end)()

print("== painting")
;(function()
    local st = Sketch.stamps(0, 0, 10, 0, 4)
    check(#st == 6 and st[1][1] == 0 and st[#st][1] == 10, "a segment is stamped every r/2 pixels, both ends included")
    st = Sketch.stamps(5, 5, 5, 5, 3)
    check(#st == 2 and st[1][1] == 5, "a dot: stamped where it is")
    local d = Sketch.disc(3)
    check(d[0] == 3 and d[3] == 0 and d[-3] == 0 and d[2] == 2, "a disc's rows")
    check(Sketch.distToSegment(5, 5, 0, 0, 10, 0) == 5 and Sketch.distToSegment(-3, 4, 0, 0, 10, 0) == 5, "distance to a segment")
end)()

print("== opening a drawing to go on with it (one made in memos' web app)")
;(function()
    local scene = Drawing.readFile(HERE .. "/media/memos-drawing.canvas.png")
    check(scene ~= nil, "memos' drawing reads")
    if not scene then return end
    local original = Drawing.encode(scene)
    local PW3 = { x = 0, y = 100, w = 1072, h = 1300 }
    local sk = Sketch.fromScene(scene, { canvas = PW3, per_unit = 2 })
    check(#sk.strokes == 6 and #sk.locked == 2, "its 6 pen strokes can be changed; the ellipse and the text are kept as they are")
    local b = sk:bounds()
    check(sk.per_unit < 2 and b.x >= 0 and b.y >= 0 and b.x + b.w <= PW3.w + 1 and b.y + b.h <= PW3.h + 1,
        "bigger than the page: scaled down to fit (" .. string.format("%.2f", sk.per_unit) .. " px a unit), all on the page")
    check(Drawing.encode(sk:scene()) == original, "nothing changed: the same scene goes back, exactly")
    check(not sk:isEmpty(), "not empty")
    -- a stroke from memos maps back to the same scene point
    local el = sk.strokes[1].el
    local sx, sy = sk:toScene(sk.strokes[1].points[1][1], sk.strokes[1].points[1][2])
    check(math.abs(sx - (el.x + el.points[1][1])) < 1e-6 and math.abs(sy - (el.y + el.points[1][2])) < 1e-6,
        "canvas pixels and scene units: there and back")
    -- rub out one of memos' strokes, draw a new one
    local p = sk.strokes[2].points[math.floor(#sk.strokes[2].points / 2)]
    local cx, cy = p[1] + PW3.x, p[2] + PW3.y
    sk:setTool("eraser")
    sk:frame({ finger(0, cx, cy) }, 0); sk:frame({ lift(0) }, 0.1)
    local erased = 6 - #sk:live()
    sk:setWidth(2)
    sk:frame({ finger(0, 50, 1300) }, 1); sk:frame({ finger(0, 200, 1350) }, 1.1); sk:frame({ lift(0) }, 1.2)
    local out = sk:scene()
    local kinds = {}
    for _i, e in ipairs(out.elements) do kinds[#kinds + 1] = e.type end
    check(erased >= 1 and #out.elements == 8 - erased + 1 and out.elements[#out.elements].type == "freedraw" and not out.elements[#out.elements].el,
        "rubbed out " .. erased .. ", drew one: the rest kept in order, the new stroke last (" .. table.concat(kinds, " ") .. ")")
    local kept_same = true
    for _i, e in ipairs(out.elements) do
        if e.type ~= "freedraw" or e ~= out.elements[#out.elements] then
            local found = false
            for _j, o in ipairs(scene.elements) do if o == e then found = true end end
            if not found then kept_same = false end
        end
    end
    check(kept_same, "the strokes, ellipse and text left alone are memos' own elements, unchanged")
    local new = out.elements[#out.elements]
    local nx, ny = sk:toScene(50 - PW3.x, 1300 - PW3.y)
    check(math.abs(new.x - Drawing.round2(nx)) < 0.02 and math.abs(new.y - Drawing.round2(ny)) < 0.02,
        "the new stroke is placed in the drawing's own units (where it was drawn on it)")
    check(out.appState.viewBackgroundColor == scene.appState.viewBackgroundColor and out.files == scene.files,
        "its paper and files kept")
    check(sk:clear() and not sk:isEmpty() and #sk:live() == 0, "Clear rubs out the strokes; memos' shapes and text stay")
    -- a small drawing isn't enlarged
    local small = Drawing.newScene()
    Drawing.addStroke(small, { { 10, 10 }, { 60, 40 } })
    local ss = Sketch.fromScene(small, { canvas = PW3, per_unit = 2 })
    check(ss.per_unit == 2 and #ss.strokes == 1, "a drawing that fits: opened at its size (never enlarged)")
    local empty = Sketch.fromScene(Drawing.newScene(), { canvas = PW3, per_unit = 2 })
    check(empty:isEmpty() and empty.per_unit == 2, "an empty drawing: an empty page")
end)()

print("== notepaper: a page's background, as memos keeps one")
;(function()
    local PW3 = { x = 0, y = 100, w = 1072, h = 1300 }
    local Notepaper = require("gzreader_notepaper")
    local sk = Sketch.new{ canvas = PW3, per_unit = 2 }
    run(sk, { { finger(0, 100, 300) }, { finger(0, 300, 400) }, { lift(0) } })
    local before = { sk:toScene(sk.strokes[1].points[2][1], sk.strokes[1].points[2][2]) }
    check(sk:paper() == "blank", "a new page: blank")
    sk:setPaper("college")
    local bg = sk.base.elements[1]
    check(bg and bg.type == "image" and bg.locked == true and bg.x == 0 and bg.y == 0 and bg.width == Notepaper.W
        and bg.height == Notepaper.H and sk.base.files[bg.fileId].mimeType == "image/png"
        and sk.base.files[bg.fileId].dataURL:match("^data:image/png;base64,iVBOR") ~= nil,
        "College ruled: a locked picture at (0, 0) at its stored size, under everything, its PNG in the scene's files")
    check(sk:paper() == "college", "…and it's known again as College ruled")
    local after = { sk:toScene(sk.strokes[1].points[2][1], sk.strokes[1].points[2][2]) }
    check(sk.per_unit < 2 and Notepaper.W * sk.per_unit <= PW3.w and Notepaper.H * sk.per_unit <= PW3.h
        and math.abs(before[1] - after[1]) < 0.01 and math.abs(before[2] - after[2]) < 0.01,
        "the page fitted to the screen (" .. string.format("%.2f", sk.per_unit) .. " px a unit); the stroke stays where it was on it")
    sk:setPaper("graph")
    local n_bg, n_files = 0, 0
    for _i, el in ipairs(sk.base.elements) do if el.type == "image" then n_bg = n_bg + 1 end end
    for _k in pairs(sk.base.files) do n_files = n_files + 1 end
    check(sk:paper() == "graph" and n_bg == 1 and n_files == 1 and sk.base.elements[1].type == "image",
        "another paper: in place of the first (one picture, one file)")
    local out = sk:scene()
    check(out.elements[1].type == "image" and out.elements[2].type == "freedraw" and out.files[out.elements[1].fileId] ~= nil,
        "the scene: the paper first, then the strokes")
    local text = Drawing.encode(out)
    local back = Drawing.decode(text)
    check(back and back.elements[1].locked == true and back.files[back.elements[1].fileId].dataURL == Notepaper.dataURL("graph"),
        "written and read back as memos reads it")
    sk:clear()
    check(sk:isEmpty(), "only the paper left: an empty page")
    sk:setPaper("blank")
    n_files = 0
    for _k in pairs(sk.base.files) do n_files = n_files + 1 end
    check(sk:paper() == "blank" and n_files == 0 and #sk.locked == 0, "Blank: the paper taken off")
    local only = Sketch.new{ canvas = PW3, per_unit = 2 }
    only:setPaper("dots")
    check(only:isEmpty() and only:cropRect() and only:cropRect().w > 500, "a page with only its paper: empty, its PNG the whole page")
    -- memos' own drawing on paper (a picture added in memos, not locked): kept as it is
    local mine = Drawing.readFile(HERE .. "/media/memos-paper.canvas.png")
    local ms = Sketch.fromScene(mine, { canvas = PW3, per_unit = 2 })
    local pic
    for _i, el in ipairs(ms.locked) do if el.type == "image" then pic = el end end
    check(pic and not pic.locked and ms:paper() == "blank" and not ms:isEmpty(),
        "a drawing made in memos over a picture of College ruled paper (the owner's): the picture is part of the drawing, kept")
    check(ms:scene().files[pic.fileId] == mine.files[pic.fileId], "…its picture's file kept as it was")
    -- on paper, strokes stay on it
    local ps = Sketch.new{ canvas = PW3, per_unit = 2 }
    ps:setPaper("college")
    local page = ps:pageRect()
    check(page and page.w > 800 and page.w < PW3.w and page.x > 0, "the paper's place on the canvas")
    local r = ps:radius(ps.width)
    local midy = PW3.y + page.y + page.h / 2
    -- across the paper's right edge and back
    local all = run(ps, { { finger(0, page.x + page.w - 100, midy) }, { finger(0, PW3.w - 5, midy) },
        { finger(0, PW3.w - 3, midy + 40) }, { finger(0, page.x + page.w - 100, midy + 40) }, { lift(0) } })
    local live = ps:live()
    local maxx = 0
    for _i, st in ipairs(live) do for _j, p in ipairs(st.points) do maxx = math.max(maxx, p[1]) end end
    check(#live == 2 and math.abs(maxx - (page.x + page.w - r)) < 0.01,
        "a stroke over the paper's edge: two pieces, both ending at the edge (ink inside it): " .. #live .. ", " .. string.format("%.1f", maxx))
    check(all.segments > 0, "…and ink only on the paper")
    check(ps:undo() and #ps:live() == 0, "one Undo takes back the whole stroke")
    -- begun off the paper
    run(ps, { { finger(0, PW3.w - 4, midy) }, { finger(0, page.x + page.w / 2, midy) }, { lift(0) } })
    live = ps:live()
    check(#live == 1 and math.abs(live[1].points[1][1] - (page.x + page.w - r)) < 0.01,
        "begun off the paper: the stroke starts at its edge")
    run(ps, { { finger(0, PW3.w - 4, midy) }, { finger(0, PW3.w - 2, midy + 30) }, { lift(0) } })
    check(#ps:live() == 1 and #ps.history == 1, "all off the paper: nothing drawn")
    local blank = Sketch.new{ canvas = PW3, per_unit = 2 }
    check(blank:pageRect() == nil, "a blank page: the whole canvas")
    -- a drawing made here, opened again: where it was, at its size
    local here = Drawing.newScene()
    Drawing.addStroke(here, { { 200, 300 }, { 260, 340 } })
    local hs = Sketch.fromScene(here, { canvas = PW3, per_unit = 2 })
    check(hs.ox == 0 and hs.oy == 0 and hs.per_unit == 2, "a drawing made here comes back where it was drawn")
end)()

print(string.format("sketch: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
