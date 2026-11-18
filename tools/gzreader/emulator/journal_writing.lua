-- A journal entry on a touch Kindle: the words typed right under the prompt
-- in a plain text box on lined paper (no "Write about it" button), the
-- keyboard making room for them (Done puts it away); ✎ in the box's corner
-- opens the drawing screen right under the prompt (lined): the same tools,
-- writing tools, pinch and pan as a note's drawing; ← back to the entry, Aa
-- back to typing, and its Save saves the entry, words and drawing.
--   python3 -I demo/mock_memos.py 18090 --sample --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh journal_writing.lua <out>
-- (GZ_EMU_MODEL=scribe too: the pen draws, a finger moves the page.)
-- Checks go to <out>/journal-writing-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function journal() return find("gz_journal") end
local function screen() return find("gz_drawscreen") end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function buttonWhere(pred)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if pred(b.tool) then return { b.rect.x + d.ox + math.floor(b.rect.w / 2), b.rect.y + d.oy + math.floor(b.rect.h / 2) } end
    end
end
local function button(id) return buttonWhere(function(t) return t.id == id end) end
-- (the page's part of the pane, on the screen: under its top bar, clear of the tools down the side)
local function area()
    local d = screen()
    local p = d.pane
    return { x = p.x + math.floor(p.w * 0.2), y = p.y + d.top_h + 40, w = math.floor(p.w * 0.6), h = p.h - d.top_h - 80 }
end
local function stroke(E, win, fy)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { win.x + math.floor(win.w * (0.1 + 0.08 * i)), win.y + math.floor(win.h * fy + 15 * math.sin(i)) } end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end
local function drag(E, w)
    local x = w.x + math.floor(w.w / 2)
    E.finger({ { x, w.y + math.floor(w.h * 0.8) }, { x, w.y + math.floor(w.h * 0.6) }, { x, w.y + math.floor(w.h * 0.3) } }, 1.2)
end
local strokes_before, pan_before

add({ fn = function(_E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will", queue = {} }
    require("gzreader_notes").journal(p)
end, after = 3 })
add({ shot = "1-journal", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    local inp = j and j.input
    check(inp and inp.getText and j.rich == nil, "a journal entry: a plain text box for the words (not the formatted page)")
    check(j and j.buttons.write == nil and E.findText("Write about it") == nil, "…no Write about it button")
    local pd, bd = j and j.buttons.prompt and j.buttons.prompt.dimen, inp and inp.dimen
    check(pd and bd and bd.y and bd.y > pd.y and bd.y - (pd.y + pd.h) < 80, "…right under the prompt")
    local tw = inp and inp.text_widget
    local tb = tw and (tw.text_widget or tw)
    check(tb and tb.line_height_px and j.draw_chip and bd and j.draw_chip.dimen.x > bd.x + bd.w / 2, "…lined, ✎ in its top right corner")
    if bd then E.tap({ bd.x + 40, bd.y + 60 }) end
end, after = 3 })
add({ shot = "2-writing", after = 0.5 })
add({ fn = function(_E)
    local j = journal()
    check(j and j.writing and j.input:isKeyboardVisible(), "a tap in it: the keyboard, the entry folded to the prompt and the words")
    local kb = j.input.keyboard.dimen
    check(j.input.dimen.y + j.input.dimen.h <= kb.y + 2, "…the words above the keyboard")
    j.input:addChars("Walked to the lake.")
end, after = 1 })
add({ fn = function(E) tapAt(E, centre(journal().buttons["done-writing"].dimen)) end, after = 3 })
add({ fn = function(E)
    local j = journal()
    check(j and not j.writing and not j.input:isKeyboardVisible() and j.state.body == "Walked to the lake.",
        "Done: the keyboard away, the whole entry again, the words kept (as typed: plain text)")
    E.tap(centre(j.draw_chip.dimen))
end, after = 5 })
add({ shot = "3-drawing", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local p = d and d.pane
    local sh = require("device").screen:getHeight()
    check(d and p and d.journal and not d.covers_fullscreen and d.sketch:paper() == "ruled-medium",
        "✎: the drawing screen, under the entry's prompt, on lined paper")
    check(p and p.y > 40 and p.y < sh / 3 and p.y + p.h == sh and p.x == 0, "…the prompt above it, the drawing the rest of the screen (from y " .. tostring(p and p.y) .. ")")
    local all = true
    for _i, id in ipairs({ "pen", "highlighter", "shape", "text", "eraser", "hand", "undo", "redo", "more", "paper", "pages", "options", "typing", "cancel" }) do
        if not button(id) then all = false end
    end
    check(all, "…the drawing screen's tools: pen, highlighter, shapes, text, eraser, hand, undo, redo, more; paper, pages, options; Aa; ←")
    local save
    for _i, b in ipairs(d.buttons) do if b.tool.id == "done" then save = b.tool.label end end
    check(save == "Save", "…its Save saves the entry (" .. tostring(save) .. ")")
    strokes_before = d and #d.sketch:live() or 0
    tapAt(E, button("pen")) -- (the pen in hand: a tap opens its panel)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local kinds = {}
    for _i, b in ipairs(d and d.buttons or {}) do if b.tool.writing then kinds[#kinds + 1] = b.tool.writing end end
    check(d and d.flyout == "pen" and table.concat(kinds, ",") == "pen,fountain,marker,pencil",
        "the pen's panel: Pen, Fountain pen, Marker, Pencil (" .. table.concat(kinds, ",") .. ")")
    tapAt(E, buttonWhere(function(t) return t.writing == "pencil" end))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    if d.flyout then tapAt(E, button("pen")) end -- (the panel away)
end, after = 2 })
add({ fn = function(E)
    stroke(E, area(), 0.3)
    if PEN then E.penAway(0.6) end -- (the pen out of range: fingers aren't a resting hand then)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local live = d and d.sketch:live() or {}
    check(#live == strokes_before + 1 and live[#live].kind == "pencil", "drawn with the pencil")
    local a = area()
    local cx, cy = a.x + math.floor(a.w / 2), a.y + math.floor(a.h / 2)
    E.zoom_was = d.sketch:zoom()
    E.pinch({ cx - 40, cy }, { cx + 40, cy }, { cx - 160, cy }, { cx + 160, cy }, 0.4)
end, after = 3 })
add({ shot = "4-zoomed", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d and d.sketch.zoomed and d.sketch:zoom() > E.zoom_was * 1.5 and #d.sketch:live() == strokes_before + 1,
        "two fingers spread: the page bigger (" .. string.format("%.2f", d.sketch:zoom()) .. "x), nothing drawn by them")
    pan_before = d.sketch.oy
    if PEN then drag(E, area()) else tapAt(E, button("hand")) end -- (a pen Kindle: a finger moves a zoomed page)
end, after = 3 })
add({ fn = function(E)
    if not PEN then
        local d = screen()
        check(d and d.tool == "hand", "the hand tool: in hand")
        drag(E, area())
    end
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d and d.sketch.oy > pan_before and #d.sketch:live() == strokes_before + 1,
        (PEN and "a finger" or "the hand") .. " dragged up: the page moved, nothing drawn")
    if not PEN then tapAt(E, button("pen")) end
end, after = 2 })
add({ fn = function(E) stroke(E, area(), 0.5) end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 2, "…drawn further down the page")
    tapAt(E, button("cancel"))
end, after = 4 })
add({ shot = "5-back", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(j and screen() == nil and not j.drawing and j:sheetCount() == 1 and #j:drawings() == 1 and j.input and j.state.body == "Walked to the lake.",
        "←: back to the whole entry, the drawing kept, the words kept, ✎ shows one sheet")
    E.tap(centre(j.draw_chip.dimen))
end, after = 5 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 2, "✎ again: the same drawing, to go on with")
    tapAt(E, button("typing"))
end, after = 4 })
add({ fn = function(E)
    local j = journal()
    check(j and screen() == nil and not j.drawing and j:sheetCount() == 1 and j.writing and j.input:isKeyboardVisible(),
        "Aa: back to typing, the keyboard up")
    j.input:addChars(" Then home.")
    E.tap(centre(j.draw_chip.dimen))
end, after = 5 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 2, "✎ from the keyboard: the drawing again")
    tapAt(E, button("done"))
end, after = 5 })
add({ fn = function(E)
    local q = plugin().store.memos.queue or {}
    local last = q[#q]
    local queued = last and last.op == "create" and last.content:find("Walked to the lake. Then home.", 1, true) and last.drawings and #last.drawings == 1
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local sent = false
    for _i, m in ipairs(st.memos or {}) do
        if tostring(m.content):find("Walked to the lake. Then home.", 1, true) and #(m.attachments or {}) == 1 then sent = true end
    end
    check(journal() == nil and (queued or sent), "the drawing screen's Save: the entry saved, its words and its drawing together (" .. (sent and "in Memos" or "queued") .. ")")
    local f = io.open(E.out .. "/journal-writing-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
