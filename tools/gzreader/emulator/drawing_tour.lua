-- A note with a drawing, on a touch Kindle: the note editor's Draw, the
-- drawing screen, Done, Save, sent to Memos (demo/mock_memos.py on 18090).
--   pw3 (or kt): drawn with a finger.
--   scribe (#144's model): only the pen draws; a finger on the page does
--   nothing; a hand resting on the page while the pen writes is ignored;
--   the pen's eraser end rubs out; the pen taps the toolbar.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh drawing_tour.lua <out>
-- Checks go to <out>/drawing-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function editor() for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then return w.widget end end end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local function screen() return find("gz_drawscreen") end
local function strokes() local d = screen(); return d and #d.sketch:live() or -1 end
-- the page's middle, by the screen's size
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function wave(fx0, fy, fx1)
    local out = {}
    for i = 0, 12 do out[#out + 1] = pt(fx0 + (fx1 - fx0) * i / 12, fy + 0.03 * math.sin(i / 2)) end
    return out
end
local function button(id)
    local d = screen()
    local function centreOf()
        for _i, b in ipairs(d and d.buttons or {}) do
            if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
        end
    end
    -- (a thickness, "w4": in the pen's choices, which the pen's button opens when it's tapped again)
    if d and id:match("^w") and not centreOf() then d:setFlyout("pen") end
    return centreOf()
end
local function tapButton(E, id) if PEN then E.penTap(button(id)) else E.tap(button(id)) end end

add({ fn = function(E)
    local Device = require("device")
    W, H = Device.screen:getWidth(), Device.screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local Notes = require("gzreader_notes")
    E.say("model", MODEL, "pen device:", tostring(require("gzreader_sketch").penDevice(Device)))
    check(Notes.canDraw(p), "Draw is offered (a touch Kindle, Memos over Wi-Fi)")
    Notes.edit(p, nil)
end, after = 2 })
add({ shot = "1-editor", after = 1 })
add({ fn = function(E)
    local e = editor()
    check(e and e:canDraw(), "the new note's editor has Draw")
    E.tap("\u{270E} " .. "Draw")
end, after = 2 })
add({ shot = "2-drawing-empty", after = 1 })
add({ fn = function(E)
    check(screen() ~= nil and top() == screen(), "Draw opens the drawing screen")
    if PEN then
        E.finger(wave(0.15, 0.3, 0.8))
    else
        E.finger(wave(0.15, 0.3, 0.8), 0.4)
    end
end, after = 1.5 })
add({ fn = function(E)
    if PEN then
        check(strokes() == 0, "scribe: a finger on the page draws nothing")
        E.pen(wave(0.15, 0.3, 0.8), 0.4)
    else
        check(strokes() == 1, "pw3: a finger draws a stroke (" .. strokes() .. ")")
    end
end, after = 1.5 })
add({ fn = function(E)
    if PEN then
        check(strokes() == 1, "scribe: the pen draws a stroke (" .. strokes() .. ")")
        -- a hand resting on the page, then the pen writes beside it
        local palm = pt(0.6, 0.62)
        E.fingerDown(palm[1], palm[2])
        E.pen(wave(0.15, 0.5, 0.5), 0.4)
        E.fingerUp(0.6)
    else
        tapButton(E, "w4")
    end
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    if PEN then
        check(strokes() == 2 and d.sketch.stats.palm + d.sketch.stats.ignored >= 1,
            "scribe: a hand resting on the page while the pen writes: ignored, the stroke drawn (ignored "
                .. (d.sketch.stats.palm + d.sketch.stats.ignored) .. ")")
        tapButton(E, "w4")
    else
        check(d.sketch.width == 4, "pw3: Thick chosen by a tap")
        E.finger(wave(0.2, 0.5, 0.6), 0.4)
    end
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    if PEN then
        check(d.sketch.width == 4, "scribe: the pen taps Thick")
        E.pen(wave(0.2, 0.7, 0.6), 0.4)
    else
        check(strokes() == 2 and d.sketch:live()[2].width == 4, "pw3: a thick stroke")
    end
end, after = 2 })
-- scribe: palm rejection on the toolbar (a finger tap there works when the pen is away)
add({ fn = function(E)
    if not PEN then return end
    local thin = button("w1")
    -- the pen hovers over the page; a palm lands on Thin and lifts; the pen goes
    E.penHover(pt(0.5, 0.5)[1], pt(0.5, 0.5)[2], 0)
    E.fingerDown(thin[1], thin[2], 0.05)
    E.fingerUp(0.12)
    E.penAway(0.2)
    -- just after the pen left: a palm on Thin again
    E.fingerDown(thin[1], thin[2], 0.4)
    E.fingerUp(0.45)
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    local d = screen()
    check(d.sketch.width == 4 and d.sketch.stats.palm == 2,
        "scribe: a palm on the toolbar while the pen hovers, and just after it left: ignored (palm " .. d.sketch.stats.palm .. ")")
    E.tap(button("w1"))
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    check(screen().sketch.width == 1, "scribe: with the pen away, a finger taps Thin")
end, after = 0.5 })
-- scribe: a whole hand (6 contacts) resting while the pen writes, the two
-- devices' frames interleaved: one stroke, every point on the pen's line
-- (before: a palm contact drew from the pen's slot and the pen's moves went
-- into a palm's slot, rectangles with a diagonal; the owner's Scribe)
add({ fn = function(E)
    if not PEN then return end
    E.penWithPalm({ pt(0.2, 0.85), pt(0.3, 0.85), pt(0.4, 0.85), pt(0.5, 0.85), pt(0.6, 0.85), pt(0.7, 0.85) }, 0.4,
        pt(0.55, 0.55), 6)
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    local d = screen()
    local live = d.sketch:live()
    local st = live[#live]
    local off, c = 0, d.sketch.canvas
    local line_y = pt(0, 0.85)[2] - c.y
    for _i, p in ipairs(st and st.points or {}) do if math.abs(p[2] - line_y) > 2 then off = off + 1 end end
    check(#live == 4 and st and #st.points >= 5 and off == 0,
        "scribe: a hand of 6 contacts resting while the pen writes: one stroke, all on the pen's line ("
            .. #live .. " strokes, " .. off .. " point(s) off it)")
    tapButton(E, "undo")
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    check(strokes() == 3, "scribe: …taken back with Undo")
end, after = 0.5 })
add({ shot = "3-drawn", after = 0.5 })
add({ fn = function(E)
    if PEN then
        check(strokes() == 3, "scribe: a thick pen stroke")
        -- the pen's eraser end across the first stroke
        E.pen({ pt(0.45, 0.22), pt(0.45, 0.38) }, 0.3, true)
    else
        tapButton(E, "undo")
    end
end, after = 2 })
add({ fn = function(E)
    if PEN then check(strokes() == 2, "scribe: the eraser end rubbed out a stroke (" .. strokes() .. ")")
    else check(strokes() == 1, "pw3: Undo took back the last stroke") end
end, after = 0.5 })
-- scribe: the pen's side button held, the tip across a stroke: rubbed out; Undo puts it back
add({ fn = function(E)
    if not PEN then return end
    E.penSideButton(true)
    E.pen({ pt(0.3, 0.45), pt(0.3, 0.56) }, 0.3)
    E.penSideButton(false, 0.5)
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    local d = screen()
    check(strokes() == 1 and d.sketch.tool == "pen" and d.sketch.side_button == false,
        "scribe: the side button held, the pen tip rubs out a stroke (" .. strokes() .. " left; the Pen tool still chosen)")
    tapButton(E, "undo")
end, after = 2 })
add({ fn = function(E)
    if not PEN then return end
    check(strokes() == 2, "scribe: …Undo brings it back")
end, after = 0.5 })
add({ shot = "4-after-erase-or-undo", after = 0.5 })
-- Done, and a second tap on the same spot 0.3 s later (a slow Done: the
-- owner's finger landed on Private ▾ in the editor that came back)
add({ fn = function(E)
    local done = button("done")
    E.vis_before = editor() and editor().visibility
    tapButton(E, "done")
    E.fingerDown(done[1], done[2], 0.3)
    E.fingerUp(0.35)
end, after = 3 })
add({ shot = "5-editor-with-drawing", after = 1 })
add({ fn = function(E)
    local e = editor()
    local menu = false
    for _i, w in ipairs(UIM()._window_stack) do if w.widget ~= e and w.widget.buttons then menu = true end end
    check(e and e.save_top and (e.taps_ignored or 0) >= 1 and e.visibility == E.vis_before and not menu,
        "a second tap where Done was: ignored by the editor's top row (" .. tostring(e and e.taps_ignored) .. "), still "
            .. tostring(e and e.visibility) .. ", no menu opened")
end, after = 0.5 })
add({ fn = function(E)
    local e = editor()
    local Drawing = require("gzreader_drawing")
    local page = e and e.pages and e.pages[1]
    local path = page and page.path
    local scene = path and Drawing.readFile(path)
    check(screen() == nil and e and page and path and path:match("drawing%-%d+%-%d+%.canvas%.png$") ~= nil,
        "Done: back in the editor, the drawing kept (" .. tostring(path) .. ")")
    check(scene and #scene.elements == (PEN and 2 or 1) and scene.elements[1].type == "freedraw",
        "the file is a memos drawing with the strokes (" .. tostring(scene and #scene.elements) .. ")")
    local f = path and io.open(path, "rb")
    local size = f and f:seek("end") or 0
    if f then f:close() end
    E.say("drawing file", size, "bytes")
    if path then os.execute("cp '" .. path .. "' '" .. E.out .. "/drawing-sent.canvas.png'") end
    e.input:setText("Sketch from the " .. MODEL, true)
    -- Save: at the top right now (touch)
    if PEN then E.penTap("Save") else E.tap("Save") end
end, after = 1 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ fn = function(E)
    local q = plugin().store.memos.queue or {}
    check(#q == 0, "sent to Memos (queue empty: " .. #q .. ")")
    local Memos = require("gzreader_memos")
    local client = Memos:new(plugin().store.memos)
    local list = client:list(nil, nil, 20)
    local found
    for _i, m in ipairs(list and list.memos or {}) do
        if m.content == "Sketch from the " .. MODEL then found = m end
    end
    check(found and found.attachments[1] and found.attachments[1].filename:match("%.canvas%.png$") ~= nil,
        "in Memos: the note with its drawing attached")
    local f = io.open(E.out .. "/drawing-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
