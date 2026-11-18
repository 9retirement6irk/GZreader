-- The quick panel pulled down while writing or drawing a note: a swipe down
-- from the top of the note editor (the keyboard steps aside and comes back),
-- of a drawing (from its top bar, and from the top edge with the bar folded
-- away; nothing is drawn) and of a journal entry. The note, the drawing and
-- the entry are still there after the panel closes.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh panel_over_notes.lua <out>
-- (GZ_EMU_MODEL=scribe too: the pen draws, a finger pulls.)
-- Checks go to <out>/panel-over-notes-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local function editor() for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then return w.widget end end end
local function panel() return require("gzreader_panel").open end
local function closePanel() local p = panel(); if p then UIM():close(p) end end
local function pull(E, y0) E.swipe(math.floor(W / 2), y0 or 6, math.floor(W / 2), math.floor(H * 0.35), 0.3) end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function draw(E, fy)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = pt(0.25 + 0.05 * i, fy + 0.02 * math.sin(i)) end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end
local strokes_before

-- the note editor
add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_notes").edit(p)
end, after = 3 })
add({ fn = function(_E)
    local e = editor()
    check(e ~= nil and e.input:isKeyboardVisible(), "a new note: the editor, its keyboard up")
    if e then e.input:addChars("Buy stamps") end
end, after = 1 })
add({ fn = function(E) pull(E, 10) end, after = 3 })
add({ shot = "1-panel-over-editor", after = 0.5 })
add({ fn = function(_E)
    local e = editor()
    check(panel() ~= nil, "a swipe down from the editor's top: the quick panel")
    check(e and not e.input:isKeyboardVisible(), "…the keyboard steps aside for it")
    closePanel()
end, after = 3 })
add({ fn = function(_E)
    local e = editor()
    check(panel() == nil and e and e:text():find("Buy stamps", 1, true) and e.input:isKeyboardVisible(),
        "panel closed: the note as written, the keyboard back")
    -- the drawing: from the editor's Draw
    e:openDrawing()
end, after = 4 })
add({ fn = function(E)
    local l = find("gz_paperlist")
    if l then tapAt(E, "Create") end
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d ~= nil and d.plugin ~= nil, "Draw: the drawing screen (it can open the quick panel)")
    draw(E, 0.5)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    strokes_before = d and #d.sketch:live() or 0
    -- a finger down from the top bar's title (not a button)
    pull(E, math.floor(d.top_h / 2))
end, after = 3 })
add({ shot = "2-panel-over-drawing", after = 0.5 })
add({ fn = function(_E)
    local d = screen()
    check(panel() ~= nil, "a pull down from the drawing's top bar: the quick panel")
    check(d and #d.sketch:live() == strokes_before, "…and nothing drawn by it (" .. tostring(d and #d.sketch:live()) .. ")")
    closePanel()
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(panel() == nil and d and #d.sketch:live() == strokes_before and UIM():getTopmostVisibleWidget() == d,
        "panel closed: the drawing as it was, on top again")
    tapAt(E, button("topfold"))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d and d.top_hidden and d.pull_zone and d.pull_zone < d.top_h, "the top bar folded away: a strip along the top edge")
    pull(E, 3)
end, after = 3 })
add({ fn = function(_E)
    local d = screen()
    check(panel() ~= nil and d and #d.sketch:live() == strokes_before, "…a pull from the top edge opens it too, nothing drawn")
    closePanel()
end, after = 3 })
add({ fn = function(E) draw(E, 0.7) end, after = 3 })
add({ fn = function(_E)
    local d = screen()
    check(d and #d.sketch:live() == strokes_before + 1, "after it, drawing goes on as before")
    if d then d:cancel() end
end, after = 3 })
add({ fn = function(_E)
    -- (Close asks whether to keep the drawing: leave it)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.title and tostring(w.widget.title):find("drawing") and w.widget.buttons then UIM():close(w.widget) end
    end
    local d = screen()
    if d then d:close() end
    local e = editor()
    if e then UIM():close(e) end
    require("gzreader_notes").journal(plugin())
end, after = 4 })
add({ fn = function(E)
    check(find("gz_journal") ~= nil, "a journal entry")
    pull(E, 8)
end, after = 3 })
add({ shot = "3-panel-over-journal", after = 0.5 })
add({ fn = function(_E)
    check(panel() ~= nil, "a swipe down from the journal's top: the quick panel")
    closePanel()
end, after = 3 })
add({ fn = function(E)
    check(panel() == nil and find("gz_journal") ~= nil, "panel closed: the journal entry still there")
    local f = io.open(E.out .. "/panel-over-notes-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
