-- A journal entry on a touch Kindle: the words typed right under the prompt
-- in a plain text box on lined paper (no "Write about it" button), the
-- keyboard making room for them (Done puts it away); ✎ in the box's corner
-- turns the box into a drawing, drawn right there under the prompt (lined),
-- moved around by a finger on a pen Kindle or the hand tool; Aa goes back to
-- typing; Save sends words and drawing.
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
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function stroke(E, win, fy)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { win.x + math.floor(win.w * (0.15 + 0.06 * i)), win.y + math.floor(win.h * fy + 15 * math.sin(i)) } end
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
    local win = d and d.window
    check(d and win and not d.covers_fullscreen and d.sketch:paper() == "ruled-medium", "✎: a drawing in the box, on lined paper (not a screen of its own)")
    check(win and win.y > 40 and win.y < require("device").screen:getHeight() / 3, "…right under the prompt (at y " .. tostring(win and win.y) .. ")")
    check(button("pen") and button("eraser") and button("hand") and button("undo") and button("typing"), "…its tools: pen, eraser, hand, undo, redo, Aa")
    strokes_before = d and #d.sketch:live() or 0
    if win then stroke(E, win, 0.5) end
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 1, "drawn in the box")
    pan_before = d and d.pan_y or 0
    if PEN then drag(E, d.window) else tapAt(E, button("hand")) end -- (a pen Kindle: a finger moves the page)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    if not PEN then
        check(d and d.tool == "hand", "the hand tool: in hand")
        drag(E, d.window)
    end
end, after = 3 })
add({ shot = "4-moved", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d and d.pan_y > pan_before and #d.sketch:live() == strokes_before + 1,
        (PEN and "a finger" or "the hand") .. " dragged up: the page moved under the box (" .. tostring(d and d.pan_y) .. " px), nothing drawn")
    if not PEN then tapAt(E, button("pen")) end
end, after = 2 })
add({ fn = function(E) stroke(E, screen().window, 0.4) end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 2, "…drawn further down the page")
    -- a tap outside the box: the journal's (the title row's Done)
    local j = journal()
    E.tap(centre(j.buttons["done-writing"].dimen))
end, after = 4 })
add({ shot = "5-back", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(j and screen() == nil and not j.drawing and j:sheetCount() == 1 and #j:drawings() == 1 and j.input and j.state.body == "Walked to the lake.",
        "a tap outside the box (Done) goes to the journal: the drawing kept, back to the words, ✎ shows one sheet")
    E.tap(centre(j.draw_chip.dimen))
end, after = 5 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 2, "✎ again: the same drawing, to go on with")
    tapAt(E, button("typing"))
end, after = 4 })
add({ fn = function(E)
    local j = journal()
    check(j and screen() == nil and not j.drawing and j:sheetCount() == 1, "Aa: back to typing")
    E.tap(centre(j.buttons.save.dimen))
end, after = 4 })
add({ fn = function(E)
    local q = plugin().store.memos.queue or {}
    local last = q[#q]
    local queued = last and last.op == "create" and last.content:find("Walked to the lake.", 1, true) and last.drawings and #last.drawings == 1
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local sent = false
    for _i, m in ipairs(st.memos or {}) do
        if tostring(m.content):find("Walked to the lake.", 1, true) and #(m.attachments or {}) == 1 then sent = true end
    end
    check(journal() == nil and (queued or sent), "Save: the entry's words and its drawing together (" .. (sent and "in Memos" or "queued") .. ")")
    local f = io.open(E.out .. "/journal-writing-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
