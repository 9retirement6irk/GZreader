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
    -- a second finger while drawing (after the pinch window): ignored
    run(sk, { { finger(0, 300, 300) }, { finger(1, 600, 600), finger(0, 320, 310) }, { finger(1, 650, 650) }, { lift(1) }, { lift(0) } }, 0, Sketch.PINCH_WINDOW + 0.05)
    check(#sk.strokes == 2 and #sk.strokes[2].points == 2, "a second finger while drawing doesn't draw")
    -- a tap outside the canvas: for the toolbar
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 505, 45) }, { lift(0) } })
    check(#out.taps == 1 and out.taps[1].x == 500 and out.taps[1].y == 40 and #sk.strokes == 2, "a tap above the canvas goes to the toolbar")
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 600, 45) }, { lift(0) } })
    check(#out.taps == 0, "a swipe up there isn't a tap")
    out = run(sk, { { finger(0, 500, 40) }, { finger(0, 500, 400) }, { lift(0) } })
    check(#out.taps == 0 and #sk.strokes == 2, "a contact that starts on the toolbar never draws")
end)()

print("== pictures (photos from Immich), as memos' drawing sheet places them")
;(function()
    -- placing: in the middle of what's shown, at most 60 % of it, never enlarged; several fanned out
    local view = { cx = 500, cy = 400, w = 1000, h = 800 }
    local one = Sketch.placePictures({ { w = 1440, h = 1080 } }, view)
    check(math.abs(one[1].w - 600) < 0.01 and math.abs(one[1].h - 450) < 0.01 and one[1].cx == 500 and one[1].cy == 400,
        "a big photo: 60 % of the page shown (here across: 600 of 1000), its shape kept, in its middle")
    local small = Sketch.placePictures({ { w = 200, h = 100 } }, view)
    check(small[1].w == 200 and small[1].h == 100, "a small one: its own size")
    local three = Sketch.placePictures({ { w = 100, h = 100 }, { w = 100, h = 100 }, { w = 100, h = 100 } }, view)
    check(three[1].cx == 500 - Sketch.PICTURE_STEP and three[2].cx == 500 and three[3].cy == 400 + Sketch.PICTURE_STEP,
        "three: fanned out from the middle, a step down and to the right each")
    -- on the page: an image element and its file in the scene; undo takes it off, redo puts it back
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    run(sk, { { finger(0, 100, 200) }, { finger(0, 300, 200) }, { lift(0) } })
    local url = "data:image/jpeg;base64,/9j/AAAA"
    local el = sk:addPicture(url, "image/jpeg", 320, 240, 250, 300, 1700000000000)
    check(el.type == "image" and el.x == 90 and el.y == 180 and el.width == 320 and el.height == 240 and el.locked == false
        and sk.base.files[el.fileId].dataURL == url and sk.base.files[el.fileId].mimeType == "image/jpeg",
        "a picture: an image element centred where asked, its pixels a file of the scene (movable in memos)")
    local scene = sk:scene()
    local kinds = {}
    for _i, e in ipairs(scene.elements) do kinds[#kinds + 1] = e.type end
    local live = Drawing.liveScene and Drawing.liveScene(scene) or scene
    check(table.concat(kinds, ",") == "image,freedraw" and live.files[el.fileId] ~= nil,
        "the drawing as memos keeps it: the picture, the ink drawn before it, the file kept (" .. table.concat(kinds, ",") .. ")")
    local b = sk:bounds()
    check(b and b.w >= 320 * 2 and b.h >= 240 * 2, "the drawing's picture (its crop) takes the picture in")
    check(sk:undo() and #sk:scene().elements == 1 and sk:scene().elements[1].type == "freedraw", "undo: the picture off, the ink left")
    check(sk:redo() and sk:scene().elements[1] == el and #sk:scene().elements == 2, "redo: back")
    -- on a new page with nothing drawn
    local sk2 = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    local el2 = sk2:addPicture(url, "image/jpeg", 100, 50, 0, 0)
    check(sk2.base and #sk2:scene().elements == 1 and sk2:scene().elements[1] == el2, "a blank page: the picture alone")
    -- a page that was in memos: its own pictures stay, the new one goes after
    local old = Drawing.newScene()
    old.elements[1] = { id = "x", type = "image", x = 0, y = 0, width = 10, height = 10, fileId = "f1", locked = true }
    old.files = { f1 = { mimeType = "image/png", dataURL = "data:image/png;base64,AA" } }
    local sk3 = Sketch.fromScene(old, { canvas = CANVAS, per_unit = 2 })
    local el3 = sk3:addPicture(url, "image/jpeg", 10, 10, 50, 50)
    local s3 = sk3:scene()
    check(#s3.elements == 2 and s3.elements[1].id == "x" and s3.elements[2] == el3 and s3.files.f1 and s3.files[el3.fileId],
        "an opened drawing: its own picture first, the new one after, both files kept")
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

print("== a pull down from the top: the quick panel")
;(function()
    local function pulled(sk, frames)
        local any, taps, t = false, 0, 0
        for _i, f in ipairs(frames) do
            local out = sk:frame(f, t)
            any = any or out.pull == true
            taps = taps + #out.taps
            t = t + 0.01
        end
        return any, taps
    end
    -- a finger Kindle, the top bar shown (it's a hole, 52 px high)
    local sk = Sketch.new{ canvas = { x = 0, y = 0, w = 1000, h = 1400 }, per_unit = 2 }
    sk.holes, sk.pull_zone, sk.pull_distance = { { x = 0, y = 0, w = 1000, h = 52 } }, 52, 60
    local p, taps = pulled(sk, { { finger(0, 500, 20) }, { finger(0, 505, 90) }, { finger(0, 510, 200) }, { lift(0) } })
    check(p and taps == 0 and #sk.strokes == 0, "a finger pulled down from the top bar: the quick panel, no ink, no tap")
    p, taps = pulled(sk, { { finger(0, 500, 20) }, { finger(0, 502, 22) }, { lift(0) } })
    check(not p and taps == 1, "a tap on the top bar is still a tap (its buttons)")
    p = pulled(sk, { { finger(0, 500, 20) }, { finger(0, 700, 60) }, { lift(0) } })
    check(not p, "a drag along the bar isn't a pull")
    p = pulled(sk, { { finger(0, 500, 400) }, { finger(0, 500, 700) }, { lift(0) } })
    check(not p and #sk.strokes == 1, "a stroke down the page draws, as before")
    -- the top bar folded away: only a strip at the very top
    sk.holes, sk.pull_zone = {}, 24
    p = pulled(sk, { { finger(0, 300, 5) }, { finger(0, 300, 150) }, { lift(0) } })
    check(p and #sk.strokes == 1, "folded away: a pull from the top edge still opens it")
    p = pulled(sk, { { finger(0, 300, 40) }, { finger(0, 300, 200) }, { lift(0) } })
    check(not p and #sk.strokes == 2, "…a stroke starting under that strip draws")
    -- a pen Kindle: a finger pulls; the pen on the page still draws, even at the top
    local pk = Sketch.new{ canvas = { x = 0, y = 0, w = 1000, h = 1400 }, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    pk.holes, pk.pull_zone, pk.pull_distance = {}, 24, 60
    p = pulled(pk, { { finger(0, 400, 4) }, { finger(0, 400, 160) }, { lift(0) } })
    check(p and #pk.strokes == 0, "a pen Kindle: a finger pulled down from the top edge opens it")
    p = pulled(pk, { { pen(400, 10) }, { pen(400, 200) }, { hover(400, 200) } })
    check(not p and #pk.strokes == 1, "…the pen there draws")
    check(Sketch.pulledDown(0, 0, 10, 80, 60) and not Sketch.pulledDown(0, 0, 10, 40, 60) and not Sketch.pulledDown(0, 0, 90, 80, 60),
        "far enough down, and more down than across")
end)()

print("== inline (a journal entry): the page moves under the box")
;(function()
    local moved = {}
    local function on_pan(dx, dy) moved[#moved + 1] = { dx, dy }; return true end
    local function run_frames(sk, list)
        local any = false
        for i, f in ipairs(list) do any = sk:frame(f, i * 0.4).panned or any end
        return any
    end
    -- a finger Kindle: the finger draws; the hand tool moves the page
    local sk = Sketch.new{ canvas = { x = 0, y = 0, w = 1000, h = 1400 }, per_unit = 2 }
    sk.inline_pan, sk.on_pan = true, on_pan
    run_frames(sk, { { finger(0, 200, 600) }, { finger(0, 260, 620) }, { lift(0) } })
    check(#sk.strokes == 1 and #moved == 0, "a finger Kindle, inline: the finger draws")
    sk.tool = "hand"
    local panned = run_frames(sk, { { finger(0, 500, 900) }, { finger(0, 500, 700) }, { finger(0, 500, 500) }, { lift(0) } })
    check(panned and #moved > 0 and #sk.strokes == 1, "the hand tool: the page moves (on_pan), nothing drawn")
    local dy = 0
    for _i, m in ipairs(moved) do dy = dy + m[2] end
    check(dy == -400, "…by as far as the finger went (" .. dy .. ")")
    -- a pen Kindle: a finger moves the page, the pen draws
    moved = {}
    local pk = Sketch.new{ canvas = { x = 0, y = 0, w = 1000, h = 1400 }, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    pk.inline_pan, pk.on_pan = true, on_pan
    panned = run_frames(pk, { { finger(0, 500, 900) }, { finger(0, 500, 800) }, { finger(0, 500, 600) }, { lift(0) } })
    check(panned and #pk.strokes == 0, "a pen Kindle, inline: a finger moves the page")
    run_frames(pk, { { pen(300, 300) }, { pen(380, 330) }, { hover(380, 330) } })
    check(#pk.strokes == 1, "…the pen draws")
    pk.tool = "hand"
    moved = {}
    panned = run_frames(pk, { { pen(500, 900) }, { pen(500, 800) }, { pen(500, 600) }, { hover(500, 600) } })
    check(panned and #pk.strokes == 1 and #moved > 0, "…the hand tool: the pen moves the page too")
    -- not inline: a pen Kindle's finger still does nothing until zoomed in
    local nk = Sketch.new{ canvas = { x = 0, y = 0, w = 1000, h = 1400 }, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    panned = run_frames(nk, { { finger(0, 500, 900) }, { finger(0, 500, 600) }, { lift(0) } })
    check(not panned and #nk.strokes == 0, "the full drawing screen, not zoomed: a finger still does nothing")
end)()

print("== pinch to zoom")
;(function()
    local W, H = CANVAS.w, CANVAS.h
    local function pinch(sk, a0, b0, a1, b1, t0, ta)
        return run(sk, { { finger(0, a0[1], a0[2]) }, { finger(0, a0[1], a0[2]), finger(1, b0[1], b0[2]) },
            { finger(0, a1[1], a1[2]), finger(1, b1[1], b1[2]) }, { lift(1) }, { lift(0) } }, t0 or 0, ta or 0.05)
    end
    -- a finger Kindle: a stroke, then two fingers apart from the middle
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    run(sk, { { finger(0, 200, 300) }, { finger(0, 300, 300) }, { lift(0) } })
    local before = { sk.strokes[1].points[1][1], sk.strokes[1].points[1][2] }
    local sx, sy = sk:toScene(before[1], before[2])
    local out = pinch(sk, { 400, 500 }, { 500, 500 }, { 350, 500 }, { 550, 500 }, 10)
    check(out.redraw and math.abs(sk:zoom() - 2) < 0.01 and sk.zoomed and #sk.strokes == 1,
        "two fingers spread twice as far: the page twice as big (the stroke kept, no stroke from the fingers)")
    local ax, ay = sk:toScene(sk.strokes[1].points[1][1], sk.strokes[1].points[1][2])
    check(math.abs(ax - sx) < 0.01 and math.abs(ay - sy) < 0.01 and sk.strokes[1].points[1][1] ~= before[1],
        "…the stroke is in the same place on the page, bigger on the screen")
    check(math.abs(sk:radius(2) - Sketch.radiusFor(2, 4)) < 0.01, "…and drawn thicker (the pen's width is the page's)")
    -- a point's own weight (a pen's pressure) goes with it through a zoom
    sk.strokes[1].points[1][3] = 0.7
    sk:zoomBy(1.5, 100, 100, 100, 100)
    local kept = sk.strokes[1].points[1][3] == 0.7
    sk:unzoom()
    check(kept and sk.strokes[1].points[1][3] == 0.7, "…a point's pressure weight kept through zooming in and out")
    sk:zoomBy(2, 0, 0, 0, 0)
    -- a stroke drawn while zoomed: the right size on the page
    run(sk, { { finger(0, 100, 100) }, { finger(0, 300, 100) }, { lift(0) } }, 20)
    local p1x = sk:toScene(100, 100)
    local p2x = sk:toScene(300, 100)
    check(#sk.strokes == 2 and math.abs((p2x - p1x) - 50) < 0.01, "a stroke of 200 px at 2x is 50 units long on the page (100 at 1x)")
    -- pinched in again: back to the fitted page
    pinch(sk, { 300, 500 }, { 700, 500 }, { 450, 500 }, { 550, 500 }, 30)
    check(not sk.zoomed and sk:zoom() == 1 and math.abs(sk:toScene(before[1], before[2]) - sx) < 0.01
        and sk.strokes[1].points[1][1] == before[1], "pinched in: back to the page as it fits (never smaller)")
    -- at most MAX_ZOOM
    pinch(sk, { 480, 500 }, { 520, 500 }, { 100, 500 }, { 900, 500 }, 40)
    check(math.abs(sk:zoom() - Sketch.MAX_ZOOM) < 0.01, "at most " .. Sketch.MAX_ZOOM .. "x")
    -- two fingers dragged while zoomed: moved, not zoomed; never past the page's edge
    local z, ox = sk:zoom(), sk.ox
    pinch(sk, { 400, 500 }, { 500, 500 }, { 300, 500 }, { 400, 500 }, 50)
    check(sk:zoom() == z and sk.ox > ox, "two fingers dragged left while zoomed: the page moves, same size")
    pinch(sk, { 400, 500 }, { 500, 500 }, { 400 + 3000, 500 }, { 500 + 3000, 500 }, 60)
    local f = sk:fitView()
    check(math.abs(sk.ox - f.ox) < 0.01, "…dragged far: stops at the page's edge")
    -- unzoom (before saving)
    check(sk:unzoom() and not sk.zoomed and sk.per_unit == f.per_unit and not sk:unzoom(), "unzoom: the fitted page again (once)")
    -- two fingers resting (not moving): nothing
    out = pinch(sk, { 400, 500 }, { 500, 500 }, { 402, 500 }, { 501, 500 }, 70)
    check(not out.zoom and not sk.zoomed, "two fingers resting, not moving: nothing")
    -- a second finger after the pinch window: no pinch, the stroke is drawn
    local n = #sk.strokes
    pinch(sk, { 400, 500 }, { 500, 500 }, { 350, 600 }, { 550, 500 }, 80, Sketch.PINCH_WINDOW + 0.1)
    check(not sk.zoomed and #sk.strokes == n + 1, "a second finger later than " .. Sketch.PINCH_WINDOW .. " s: no zoom, the first finger's stroke kept")
    -- a pen Kindle: two fingers zoom when the pen is away; a hand (3 contacts) or the pen near: no
    local pk = Sketch.new{ canvas = CANVAS, pen_only = true, pen_slot = PEN_SLOT, per_unit = 2 }
    pinch(pk, { 400, 500 }, { 500, 500 }, { 350, 500 }, { 550, 500 }, 100)
    check(math.abs(pk:zoom() - 2) < 0.01 and #pk.strokes == 0, "a pen Kindle: two fingers spread: zoomed (fingers still never draw)")
    pk:unzoom()
    run(pk, { { finger(0, 400, 500) }, { finger(0, 400, 500), finger(1, 500, 500) }, { finger(0, 400, 500), finger(1, 500, 500), finger(2, 600, 700) },
        { finger(0, 300, 500), finger(1, 700, 500), finger(2, 600, 700) }, { lift(0), lift(1), lift(2) } }, 110)
    check(not pk.zoomed, "…a hand (a third contact): no zoom")
    run(pk, { { hover(100, 100) } }, 120)
    pinch(pk, { 400, 500 }, { 500, 500 }, { 350, 500 }, { 550, 500 }, 120.1)
    check(not pk.zoomed, "…the pen near the screen: fingers are a palm, no zoom")
    run(pk, { { penGone() } }, 121)
    pinch(pk, { 400, 500 }, { 500, 500 }, { 350, 500 }, { 550, 500 }, 125, Sketch.PINCH_PAIR + 0.1)
    check(not pk.zoomed, "…two fingers landing " .. Sketch.PINCH_PAIR .. " s apart: no zoom")
    -- zoomed, the page kept for the PNG: the scene doesn't change with the view
    local zk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    run(zk, { { finger(0, 200, 300) }, { finger(0, 300, 300) }, { lift(0) } })
    local s1 = zk:scene().elements[1]
    pinch(zk, { 400, 500 }, { 500, 500 }, { 300, 500 }, { 600, 500 }, 10)
    local s2 = zk:scene().elements[1]
    check(math.abs(s1.x - s2.x) < 0.01 and math.abs(s1.y - s2.y) < 0.01 and #s1.points == #s2.points,
        "the drawing saved is the same zoomed or not")
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
    -- the pen's side button held (the Premium Pen): the tip rubs out; let go, it draws again
    sk.side_button = true
    run(sk, { { hover(200, 150) }, { pen(200, 150) }, { pen(200, 260) }, { hover(200, 260) }, { penGone() } }, 12)
    local rubbed = #sk:live() == 1 and sk.tool == "pen"
    sk.side_button = false
    check(rubbed and sk:undo() and #sk:live() == 2, "the side button held: the pen tip rubs out (the Pen tool stays chosen)")
    run(sk, { { hover(700, 150) }, { pen(700, 150) }, { pen(700, 260) }, { hover(700, 260) }, { penGone() } }, 14)
    check(#sk:live() == 3, "…let go: the tip draws again")
    sk:undo()
    sk.side_button = true
    run(sk, { { finger(0, 200, 150) }, { finger(0, 200, 260) }, { lift(0) } }, 40)
    sk.side_button = false
    check(#sk:live() == 2, "…a finger with the button held doesn't rub out (fingers don't draw or erase on a pen Kindle)")
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

print("== redo, the controls over the page, pen thicknesses")
;(function()
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    run(sk, { { finger(0, 100, 200) }, { finger(0, 200, 260) }, { lift(0) } })
    run(sk, { { finger(0, 300, 400) }, { finger(0, 400, 460) }, { lift(0) } })
    check(not sk:canRedo() and not sk:redo(), "nothing to redo before an undo")
    check(sk:undo() and #sk:live() == 1 and sk:canRedo(), "undo: the last stroke gone, redo possible")
    check(sk:redo() and #sk:live() == 2 and not sk:canRedo() and sk:canUndo(), "redo brings it back (and can be undone again)")
    check(sk:undo() and sk:undo() and sk:isEmpty() and sk:redo() and sk:redo() and #sk:live() == 2, "two undos, two redos: both strokes back")
    sk:undo()
    run(sk, { { finger(0, 500, 600) }, { finger(0, 600, 660) }, { lift(0) } })
    check(not sk:canRedo() and #sk:live() == 2, "a new stroke after an undo: nothing left to redo")
    sk:clear()
    check(sk:isEmpty() and sk:undo() and #sk:live() == 2 and sk:redo() and sk:isEmpty(), "Clear can be undone and redone")
    sk:undo()
    -- the toolbar and the page pill lie over the page: a contact there is a tap for them, never ink
    sk.holes = { { x = 10, y = 120, w = 60, h = 400 } }
    local before = #sk.strokes
    local out = run(sk, { { finger(0, 30, 200) }, { finger(0, 32, 202) }, { lift(0) } })
    check(#out.taps == 1 and out.taps[1].x == 30 and #sk.strokes == before, "a tap on the toolbar (over the page) goes to it and draws nothing")
    out = run(sk, { { finger(0, 30, 200) }, { finger(0, 300, 500) }, { lift(0) } })
    check(#sk.strokes == before and #out.taps == 0, "a contact that starts on the toolbar never draws, wherever it goes")
    out = run(sk, { { finger(0, 300, 300) }, { finger(0, 320, 330) }, { lift(0) } })
    check(#sk.strokes == before + 1, "beside it, the page draws as before")
    check(not sk:inCanvas(30, 200) and sk:inCanvas(300, 300) and not sk:inCanvas(500, 40), "inCanvas: on the page and not under a control")
    -- thicknesses: five, from very fine to very thick; a stroke keeps the one it was drawn with
    check(#Sketch.WIDTHS == 5 and Sketch.WIDTHS[1] == 0.5 and Sketch.WIDTHS[3] == 2 and Sketch.WIDTHS[5] == 7, "five pen thicknesses (0.5 to 7; memos' own 1, 2 and 4 among them)")
    sk.holes = nil
    sk:setWidth(7)
    run(sk, { { finger(0, 600, 300) }, { finger(0, 700, 330) }, { lift(0) } })
    sk:setWidth(0.5)
    run(sk, { { finger(0, 600, 500) }, { finger(0, 700, 530) }, { lift(0) } })
    local scene = Drawing.decode(Drawing.encode(sk:scene()))
    local widths = {}
    for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "freedraw" then widths[#widths + 1] = el.strokeWidth end end
    check(widths[#widths] == 0.5 and widths[#widths - 1] == 7, "…written into the drawing as memos' stroke widths (7 and 0.5)")
    local again = Sketch.fromScene(scene, { canvas = CANVAS, per_unit = 2 })
    local live = again:live()
    check(live[#live].width == 0.5 and live[#live - 1].width == 7, "…and read back as drawn")
end)()

print("== pen colours (colour screens): memos' own palette")
;(function()
    local ids, vals = {}, {}
    for i, c in ipairs(Sketch.COLORS) do ids[i], vals[i] = c.id, c.value end
    check(table.concat(ids, ",") == "ink,gray,red,orange,green,teal,blue,violet"
        and table.concat(vals, ",") == "#1a1a1a,#868e96,#e03131,#f08c00,#2f9e44,#0c8599,#1971c2,#7048e8",
        "the colours are memos' ink and its drawing editor's seven hues")
    check(Sketch.inkColor("#E03131") == "#e03131" and Sketch.inkColor("#1a1a1a") == nil and Sketch.inkColor("#1A1A1A") == nil
        and Sketch.inkColor("red") == nil and Sketch.inkColor(nil) == nil and Sketch.inkColor("#12345") == nil and Sketch.inkColor(5) == nil,
        "a colour is kept as #rrggbb in lower case; memos' ink (and anything that isn't a colour) is no colour")
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    local segs = {}
    local function draw(frames)
        segs = {}
        for i, f in ipairs(frames) do
            for _j, seg in ipairs(sk:frame(f, i * 0.01).segments) do segs[#segs + 1] = seg end
        end
    end
    draw({ { finger(0, 100, 200) }, { finger(0, 200, 260) }, { lift(0) } })
    check(sk.color == nil and sk:live()[1].color == nil and #segs > 0 and segs[1][6] == nil, "a new drawing draws in memos' ink")
    sk:setTool("eraser")
    sk:setColor("#1971C2")
    check(sk.color == "#1971c2" and sk.tool == "pen", "choosing a colour takes the pen")
    draw({ { finger(0, 300, 400) }, { finger(0, 400, 460) }, { finger(0, 450, 500) }, { lift(0) } })
    local live = sk:live()
    check(#live == 2 and live[2].color == "#1971c2" and live[1].color == nil, "the next stroke is blue; the one before stays as it was")
    local all_blue = #segs > 0
    for _i, seg in ipairs(segs) do if seg[6] ~= "#1971c2" then all_blue = false end end
    check(all_blue, "…and each piece drawn says so (the screen and the PNG paint it in that colour)")
    sk:setColor("#1a1a1a")
    run(sk, { { finger(0, 500, 600) }, { finger(0, 600, 660) }, { lift(0) } })
    check(sk.color == nil and sk:live()[3].color == nil, "back to the ink")
    local scene = Drawing.decode(Drawing.encode(sk:scene()))
    local cols = {}
    for _i, el in ipairs(scene.elements) do if el.type == "freedraw" then cols[#cols + 1] = el.strokeColor end end
    check(table.concat(cols, ",") == "#1a1a1a,#1971c2,#1a1a1a", "written into the drawing as memos' stroke colours: " .. table.concat(cols, ","))
    local again = Sketch.fromScene(scene, { canvas = CANVAS, per_unit = 2 })
    local l2 = again:live()
    check(l2[1].color == nil and l2[2].color == "#1971c2" and l2[3].color == nil, "…and read back (a stroke coloured in Memos keeps its colour here too)")
    again:undo()
    check(again:scene().elements and true, "an opened drawing still saves")
    -- a coloured stroke undone and redone keeps its colour
    sk:undo(); sk:undo()
    sk:redo()
    check(sk:live()[2].color == "#1971c2", "undo and redo keep a stroke's colour")
end)()

print("== pen pressure and tilt (a Kindle with a pen)")
;(function()
    local kept_range = Sketch.range
    local R = { p_seen = 0, t_seen = 0, n = 0 }
    check(Sketch.pressureTop(R) == 4095 and Sketch.tiltTop(R) == 60, "before the pen has shown its range: 4095 levels of pressure, 60 degrees of tilt")
    check(Sketch.weight(R, nil) == nil and Sketch.weight(R, 0) == nil, "no pressure (a finger, a hovering pen): no weight")
    local half = Sketch.weight(R, 2048)
    check(math.abs(half - 0.5) < 0.01 and Sketch.weight(R, 4095) == 1 and Sketch.weight(R, 100) == 0.05,
        "pressure alone: half pressure is the chosen thickness, full is the heaviest, the lightest touch still leaves a line")
    check(Sketch.weight(R, 2048, 60, 0) > 0.94 and Sketch.weight(R, 2048, 30, 0) > half and Sketch.weight(R, 2048, 0, -60) > 0.94
        and Sketch.weight(R, 4095, 60, 60) == 1,
        "tilt: the pen laid over makes the line heavier, whichever way it leans (as shading with the side of a pencil)")
    check(Sketch.weightRadius(10, nil) == 10 and Sketch.weightRadius(10, 0.5) == 10 and Sketch.weightRadius(10, 1) == 16
        and Sketch.weightRadius(10, 0.05) == 5 and Sketch.weightRadius(1, 0.05) == 1,
        "the line's width: the chosen thickness at half weight, 0.4 to 1.6 of it across the range")
    -- the range is learned from the pen
    Sketch.noteRange(R, 8000, 0, 0)
    check(Sketch.pressureTop(R) == 8000 and R.n == 1, "a pen that reports more than 4095: its own top")
    R = { p_seen = 0, t_seen = 0, n = 0 }
    for _i = 1, 299 do Sketch.noteRange(R, 1000, 5, -8) end
    local early = Sketch.pressureTop(R)
    Sketch.noteRange(R, 1023, 0, 0)
    check(early == 4095 and Sketch.pressureTop(R) == 1023 and R.t_seen == 8, "a pen that never comes near it (1024 levels): after 300 samples, its own top")
    Sketch.noteRange(R, 500, -4200, 100)
    check(Sketch.tiltTop(R) == 6000 and math.abs(Sketch.weight(R, 512, 3000, 0) - 0.5 * 1.45) < 0.02,
        "a pen that reports tilt in hundredths of a degree is read that way")
    -- strokes
    Sketch.range = { p_seen = 0, t_seen = 0, n = 0 }
    local sk = Sketch.new{ canvas = CANVAS, per_unit = 2, pen_only = true }
    local function pen(x, y, pr, tx) return { slot = 4, id = 4, x = x, y = y, tool = Sketch.TOOL_PEN, pressure = pr, tilt_x = tx } end
    local function up() return { slot = 4, id = -1, tool = Sketch.TOOL_PEN, pressure = 0 } end
    local segs = {}
    local function draw(frames)
        segs = {}
        for i, f in ipairs(frames) do
            for _j, seg in ipairs(sk:frame(f, 100 + i * 0.01).segments) do segs[#segs + 1] = seg end
        end
    end
    draw({ { pen(100, 300, 600) }, { pen(200, 300, 600) }, { pen(300, 300, 600) }, { pen(400, 300, 4095) }, { pen(500, 300, 4095) },
        { pen(600, 300, 4095) }, { pen(700, 300, 4095) }, { up() } })
    local st = sk:live()[1]
    local base = sk:radius(st.width)
    check(st and #st.points == 7 and st.points[1][3] ~= nil and st.points[1][3] < 0.2 and st.points[7][3] > 0.9,
        "a pen stroke: every point has its weight (light, then pressed hard)")
    check(segs[1][5] < base and segs[#segs][5] > base and segs[#segs][5] > segs[1][5],
        "…drawn thin where it was light and wide where it was pressed (" .. segs[1][5] .. " to " .. segs[#segs][5] .. " px around " .. base .. ")")
    check(Sketch.range.p_seen == 4095 and Sketch.range.n == 7, "…and the pen's range is noted as it draws")
    local scene = Drawing.decode(Drawing.encode(sk:scene()))
    local el
    for _i, e in ipairs(scene.elements) do if e.type == "freedraw" then el = e end end
    check(el and el.simulatePressure == false and el.points[1][3] < 0.2 and el.points[#el.points][3] > 0.9,
        "written into the drawing as memos' pressures (it draws the stroke by them, not by speed)")
    local again = Sketch.fromScene(scene, { canvas = CANVAS, per_unit = 2 })
    local st2 = again:live()[1]
    check(st2.points[1][3] ~= nil and math.abs(st2.points[1][3] - el.points[1][3]) < 0.01 and st2.points[#st2.points][3] > 0.9,
        "…and read back: an opened drawing shows the stroke as wide as it was pressed")
    -- tilt on a stroke
    draw({ { pen(100, 500, 2048, 0) }, { pen(200, 500, 2048, 0) }, { pen(300, 500, 2048, 55) }, { pen(400, 500, 2048, 55) },
        { pen(500, 500, 2048, 55) }, { pen(600, 500, 2048, 55) }, { up() } })
    local tilted = sk:live()[2]
    check(tilted.points[#tilted.points][3] > tilted.points[1][3] + 0.25, "laying the pen over part way through a stroke widens it from there")
    -- turned off: uniform, as a pen without pressure
    sk.pressure_on = false
    draw({ { pen(100, 700, 600) }, { pen(300, 700, 4095) }, { pen(500, 700, 4095) }, { up() } })
    local flat = sk:live()[3]
    local off_scene = sk:scene()
    local off_el = off_scene.elements[#off_scene.elements]
    check(flat.points[1][3] == nil and segs[1][5] == base and segs[#segs][5] == base and off_el.simulatePressure == true,
        "Pressure and tilt off: an even line of the chosen thickness, saved as before")
    sk.pressure_on = true
    -- the writing tools (as on the Kindle Scribe): pen, pencil, fountain pen, highlighter
    local function stroke(tool, y)
        sk.writing = tool
        draw({ { pen(100, y, 400) }, { pen(250, y, 400) }, { pen(400, y, 4095) }, { pen(550, y, 4095) }, { up() } })
        local l = sk:live()
        return l[#l], { light = segs[2][5], hard = segs[#segs][5], gray = segs[#segs][7] }
    end
    local stp, pn = stroke("pen", 900)
    local stf, fo = stroke("fountain", 1000)
    local stc, pc = stroke("pencil", 1100)
    local sth, hl = stroke("highlighter", 1200)
    check(stp.kind == nil and stf.kind == "fountain" and stc.kind == "pencil" and sth.kind == "highlighter",
        "each stroke keeps its tool (the pen's has none, as before)")
    check(fo.light < pn.light and fo.hard > pn.hard,
        "fountain pen: thinner than the pen when light, wider when pressed (" .. fo.light .. "–" .. fo.hard .. " px; pen "
            .. pn.light .. "–" .. pn.hard .. ")")
    check(pc.gray and pc.gray > 0 and pc.gray < 0xC0 and pc.hard < pn.hard and pc.hard - pc.light < pn.hard - pn.light,
        "pencil: grey, thinner, and pressure changes it less")
    check(hl.gray and hl.gray > pc.gray and hl.light == hl.hard and hl.hard > 3 * pn.light and sth.points[1][3] == nil,
        "highlighter: light grey, broad, even (no pressure)")
    local tsc = Drawing.decode(Drawing.encode(sk:scene()))
    local byTool = {}
    for _i, e in ipairs(tsc.elements) do
        if e.type == "freedraw" then byTool[(e.customData and e.customData.gzTool) or "pen"] = e end
    end
    check(byTool.fountain and byTool.pencil.opacity == 70 and byTool.highlighter.opacity == 35 and byTool.highlighter.simulatePressure == true
        and byTool.highlighter.strokeWidth > byTool.pen.strokeWidth and byTool.pen.opacity == 100,
        "saved for Memos: the tool kept (customData), the pencil and highlighter see-through, the highlighter broad")
    local back = Sketch.fromScene(tsc, { canvas = CANVAS, per_unit = 2 })
    local kinds = {}
    for _i, bst in ipairs(back:live()) do kinds[#kinds + 1] = bst.kind or "pen" end
    local hb
    for _i, bst in ipairs(back:live()) do if bst.kind == "highlighter" then hb = bst end end
    check(table.concat(kinds, ","):find("pen,fountain,pencil,highlighter", 1, true) and hb.width == sth.width,
        "…read back with their tools, the highlighter at the thickness it was drawn with")
    check(Sketch.toolOf({ opacity = 30 }) == "highlighter" and Sketch.toolOf({ opacity = 80 }) == "pencil"
        and Sketch.toolOf({ opacity = 100 }) == nil and Sketch.toolOf({ opacity = 30, customData = { gzTool = "fountain" } }) == "fountain",
        "a see-through stroke drawn in Memos opens as a highlighter or a pencil")
    -- the pen's shortcut button: held, its tool (Settings → Notes); the eraser by default
    sk.writing = "pen"
    sk.side_button, sk.shortcut = true, "highlighter"
    draw({ { pen(100, 1250, 2000) }, { pen(300, 1250, 2000) }, { up() } })
    local viaButton = sk:live()[#sk:live()]
    sk.shortcut = "fountain"
    draw({ { pen(100, 1280, 2000) }, { pen(300, 1280, 2000) }, { up() } })
    local viaFountain = sk:live()[#sk:live()]
    sk.side_button = false
    draw({ { pen(100, 1310, 2000) }, { pen(300, 1310, 2000) }, { up() } })
    local after = sk:live()[#sk:live()]
    check(viaButton.kind == "highlighter" and viaFountain.kind == "fountain" and after.kind == nil and sk.writing == "pen",
        "the shortcut button held: its tool (highlighter, fountain pen); let go: the tool in hand again")
    check(Sketch.shortcutTool({}) == "eraser" and Sketch.shortcutTool({ shortcut = "nonsense" }) == "eraser"
        and Sketch.shortcutTool({ shortcut = "pencil" }) == "pencil", "the shortcut button's tool: the eraser unless chosen")
    -- a finger (no pressure reported) and a pen that reports none: as before
    local fsk = Sketch.new{ canvas = CANVAS, per_unit = 2 }
    run(fsk, { { finger(0, 100, 200) }, { finger(0, 200, 260) }, { lift(0) } })
    local fscene = fsk:scene()
    check(fsk:live()[1].points[1][3] == nil and fscene.elements[#fscene.elements].simulatePressure == true,
        "a finger: no weights, memos draws the stroke by its speed as before")
    local psk = Sketch.new{ canvas = CANVAS, per_unit = 2, pen_only = true }
    psk:frame({ { slot = 4, id = 4, x = 100, y = 300, tool = Sketch.TOOL_PEN } }, 1)
    psk:frame({ { slot = 4, id = 4, x = 300, y = 300, tool = Sketch.TOOL_PEN } }, 1.01)
    psk:frame({ { slot = 4, id = -1, tool = Sketch.TOOL_PEN } }, 1.02)
    check(psk:live()[1] and psk:live()[1].points[1][3] == nil, "a pen that reports no pressure draws as before too")
    -- undo / redo keep the weights; the eraser ignores pressure
    sk:undo(); sk:undo(); sk:redo()
    check(sk:live()[2].points[3][3] ~= nil, "undo and redo keep a stroke's weights")
    Sketch.range = kept_range
end)()

-- shapes, the marker and the eraser's sizes (the Kindle Scribe's tools)
;(function()
    local function sketch()
        return Sketch.new{ canvas = { x = 0, y = 0, w = 600, h = 800 }, per_unit = 1, tap_slop = 8 }
    end
    local function drag(sk, x0, y0, x1, y1, t)
        local outs = {}
        outs[1] = sk:frame({ { slot = 0, id = 1, x = x0, y = y0 } }, t)
        outs[2] = sk:frame({ { slot = 0, id = 1, x = (x0 + x1) / 2, y = (y0 + y1) / 2 } }, t + 0.01)
        outs[3] = sk:frame({ { slot = 0, id = 1, x = x1, y = y1 } }, t + 0.02)
        outs[4] = sk:frame({ { slot = 0, id = -1 } }, t + 0.03)
        return outs
    end
    local sq = Sketch.outline("square", 10, 20, 110, 220)
    check(#sq == 5 and sq[1][1] == 10 and sq[3][1] == 110 and sq[3][2] == 220 and sq[5][1] == sq[1][1] and sq[5][2] == sq[1][2],
        "a square's outline: its four corners, closed")
    local ci = Sketch.outline("circle", 0, 0, 200, 100)
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for _i, p in ipairs(ci) do minx, maxx, miny, maxy = math.min(minx, p[1]), math.max(maxx, p[1]), math.min(miny, p[2]), math.max(maxy, p[2]) end
    check(#ci >= 25 and math.abs(maxx - 200) < 1 and math.abs(minx) < 1 and math.abs(maxy - 100) < 1 and math.abs(miny) < 1
        and math.abs(ci[1][1] - ci[#ci][1]) < 0.001, "a circle's outline: an oval in the box dragged, closed")
    local tr = Sketch.outline("triangle", 0, 100, 100, 0)
    check(#tr == 4 and tr[1][1] == 50 and tr[1][2] == 0 and tr[2][2] == 100 and tr[3][2] == 100, "a triangle: its point up, whichever way it's dragged")
    local ar = Sketch.outline("arrow", 0, 0, 100, 0)
    check(#Sketch.outline("line", 0, 0, 5, 5) == 2 and #ar == 5 and ar[2][1] == 100 and ar[4][1] == 100 and ar[3][1] < 100 and ar[3][2] == -ar[5][2],
        "a line: two points; an arrow: the line and two barbs back from its tip")
    local sk = sketch()
    sk.tool, sk.shape, sk.width = "shape", "square", 2
    local outs = drag(sk, 100, 100, 300, 250, 1)
    local st = sk:live()[1]
    check(st and #st.points == 5 and st.points[3][1] == 300 and st.points[3][2] == 250 and st.kind == nil and st.width == 2
        and #outs[2].segments == 0 and outs[4].redraw and outs[4].stroke_done,
        "the shape tool: nothing drawn on the way, a square from where the pen landed to where it lifted (a stroke in the pen's ink)")
    check(sk:canUndo() and sk:undo() and #sk:live() == 0 and sk:redo() and #sk:live() == 1, "…undone and redone like any stroke")
    local scene = sk:scene()
    local el
    for _i, e in ipairs(scene.elements) do if e.type == "freedraw" then el = e end end
    check(el and #el.points == 5, "…sent to Memos as a stroke along its outline")
    local sk2 = sketch()
    sk2.tool, sk2.shape = "shape", "line"
    drag(sk2, 100, 100, 102, 101, 1)
    check(#sk2:live() == 0, "a tap with a shape in hand draws nothing")
    -- the marker: as wide all along, black
    check(Sketch.TOOL_STYLE.marker.flat and not Sketch.TOOL_STYLE.marker.gray and Sketch.toolRadius("marker", 4, 0.1) == Sketch.toolRadius("marker", 4, 0.9)
        and Sketch.toolRadius("marker", 4) > Sketch.toolRadius("pen", 4)
        and table.concat(Sketch.PEN_IDS, ",") == "pen,fountain,marker,pencil",
        "the marker: black, wider than the pen, the same however hard it's pressed; the pen's tools in the Scribe's order")
    -- the eraser's sizes: how near a stroke it takes it
    local sk3 = sketch()
    sk3.width = 1
    drag(sk3, 100, 300, 300, 300, 1)
    sk3.tool, sk3.eraser_width = "eraser", 1
    drag(sk3, 200, 305, 201, 306, 2)
    local near = #sk3:live()
    sk3.eraser_width = 12
    drag(sk3, 200, 305, 201, 306, 3)
    check(near == 1 and #sk3:live() == 0 and Sketch.ERASER_WIDTHS[1] == 1 and Sketch.ERASER_WIDTHS[5] == 12,
        "the eraser: Fine passes a stroke 5 px away, Heavy takes it")
end)()

-- zoomed in: the page follows a pinch as it goes, and (a pen Kindle) one finger moves it
;(function()
    local function sketch()
        local sk = Sketch.new{ canvas = { x = 0, y = 0, w = 600, h = 800 }, per_unit = 1, tap_slop = 8, pen_only = true, pen_slot = 4 }
        sk:zoomBy(2, 300, 400, 300, 400)
        return sk
    end
    local sk = sketch()
    local ox0, oy0 = sk.ox, sk.oy
    check(sk.zoomed and math.abs(sk:zoom() - 2) < 0.01, "zoomed to 2x")
    local o1 = sk:frame({ { slot = 0, id = 1, x = 300, y = 400 } }, 10)
    local o2 = sk:frame({ { slot = 0, id = 1, x = 300, y = 340 } }, 10.1)
    local o3 = sk:frame({ { slot = 0, id = 1, x = 300, y = 300 } }, 10.4)
    local mid_oy = sk.oy
    local o4 = sk:frame({ { slot = 0, id = 1, x = 300, y = 280 } }, 10.45)
    local o5 = sk:frame({ { slot = 0, id = -1 } }, 10.5)
    check(not o1.redraw and not o2.redraw and o3.redraw and o3.view and math.abs((mid_oy - oy0) - 50) < 0.5 and sk.ox == ox0,
        "a pen Kindle, zoomed: one finger moves the page while it's still down (100 px up the screen at 2x: 50 of the page), a step at a time")
    check(not o4.redraw and o5.redraw and o5.view and math.abs((sk.oy - oy0) - 60) < 0.5 and #sk:live() == 0 and not sk:canUndo(),
        "…and it settles where the finger lifts; nothing is drawn, nothing to undo")
    local un = Sketch.new{ canvas = { x = 0, y = 0, w = 600, h = 800 }, per_unit = 1, tap_slop = 8, pen_only = true, pen_slot = 4 }
    un:frame({ { slot = 0, id = 1, x = 300, y = 400 } }, 1)
    local u2 = un:frame({ { slot = 0, id = 1, x = 300, y = 200 } }, 2)
    check(not u2.redraw and un.contacts[0].kind == "ignore", "not zoomed: a finger does nothing, as before")
    -- the pen near: a hand on the screen doesn't move the page
    local pk = sketch()
    pk:frame({ { slot = 4, id = 4, x = 100, y = 100, tool = Sketch.TOOL_PEN } }, 20)
    pk:frame({ { slot = 0, id = 1, x = 300, y = 500 } }, 20.1)
    local p3 = pk:frame({ { slot = 0, id = 1, x = 300, y = 300 } }, 20.6)
    check(not p3.view and pk.contacts[0].kind == "ignore", "the pen writing: a hand resting on the zoomed page doesn't move it")
    -- a pinch follows the fingers too
    local pz = sketch()
    pz:frame({ { slot = 0, id = 1, x = 250, y = 400 } }, 30)
    pz:frame({ { slot = 0, id = 1, x = 250, y = 400 }, { slot = 1, id = 2, x = 350, y = 400 } }, 30.05)
    local z1 = pz:frame({ { slot = 0, id = 1, x = 220, y = 400 }, { slot = 1, id = 2, x = 380, y = 400 } }, 30.5)
    local zmid = pz:zoom()
    local z2 = pz:frame({ { slot = 0, id = 1, x = 200, y = 400 }, { slot = 1, id = 2, x = 400, y = 400 } }, 30.9)
    local z3 = pz:frame({ { slot = 0, id = -1 }, { slot = 1, id = 2, x = 400, y = 400 } }, 31)
    check(z1.redraw and z1.view and z1.zoom == nil and zmid > 2.4 and zmid < 3.3 and z2.redraw and math.abs(pz:zoom() - 4) < 0.05
        and z3.zoom and math.abs(z3.zoom.from - 2) < 0.01 and math.abs(z3.zoom.to - 4) < 0.05,
        "a pinch: the page zooms while the fingers are still down (2x, part of the way, 4x), told once when they lift")
end)()

print(string.format("sketch: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
