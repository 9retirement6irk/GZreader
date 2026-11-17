-- A new drawing (the Notes tab's Draw), as the Kindle Scribe's notebooks:
-- which paper first (Create), a stroke, then its name and a tag from the
-- drawing screen's top bar; Done saves the note at once (no window after):
-- in Memos (demo/mock_memos.py on 18090) "# title", the tag and the drawing.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh new_drawing.lua <out>
-- Checks go to <out>/new-drawing-checks.txt.
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

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_notes").draw(p)
end, after = 3 })
add({ shot = "1-which-paper", after = 0.5 })
add({ fn = function(E)
    local l = find("gz_paperlist")
    check(l and l.create and screen() == nil, "Draw: which paper first")
    tapAt(E, "Create")
end, after = 4 })
add({ fn = function(E)
    local e, d = editor(), screen()
    check(d ~= nil and d.meta ~= nil and e and e.popup_only and e.covers_fullscreen == false and d:heading() == "Untitled drawing",
        "Create: the drawing screen (the note's page out of sight), Untitled drawing in its top bar")
    draw(E, 0.4)
end, after = 3 })
add({ fn = function(E) tapAt(E, button("title")) end, after = 4 })
add({ fn = function(E)
    local dialog
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Name this drawing" then dialog = w.widget end end
    check(dialog ~= nil, "a tap on the name: Name this drawing")
    if dialog then dialog:addTextToInput("Garden plan"); E.tap("Save") end
end, after = 4 })
add({ fn = function(E) tapAt(E, button("tag")) end, after = 3 })
add({ fn = function(E) tapAt(E, button("newtag")) end, after = 4 })
add({ fn = function(E)
    local dialog
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "New tag" then dialog = w.widget end end
    check(dialog ~= nil, "Tags, New tag: its window")
    if dialog then dialog:addTextToInput("garden"); E.tap("Add") end
end, after = 4 })
add({ shot = "2-named-and-tagged", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d and d:heading() == "Garden plan" and d.meta.tags[1] == "garden" and d.flyout == "tags",
        "the name in the top bar, the tag on the drawing (" .. tostring(d and d.meta.tags[1]) .. ")")
    tapAt(E, button("tag"))
end, after = 3 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 3 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ fn = function(E)
    local open = false
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "New drawing" then open = true end end
    check(editor() == nil and not open and screen() == nil, "Done: saved at once, no New drawing window after")
    local Memos = require("gzreader_memos")
    local list = Memos:new(plugin().store.memos):list(nil, nil, 20)
    local found
    for _i, m in ipairs(list and list.memos or {}) do if m.content == "# Garden plan\n\n#garden" then found = m end end
    local pic = found and found.attachments and found.attachments[1]
    check(found and pic and tostring(pic.filename):match("%.canvas%.png$"),
        "in Memos: \"# Garden plan\", #garden and the drawing (" .. tostring(found and #found.attachments) .. " attachment)")
    -- the note is only a drawing: a tap on it (the Notes tab) opens the drawing, not the note's page
    E.memo = found
    require("gzreader_notes").refresh(plugin())
end, after = 8 })
add({ fn = function(E)
    local N = require("gzreader_notes")
    check(E.memo ~= nil and N.drawings(E.memo)[1] ~= nil, "the note has its drawing")
    if E.memo then N.showNote(plugin(), E.memo) end
end, after = 5 })
add({ shot = "3-drawing-note-opened", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local view
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.scroller and w.widget.memo then view = w.widget end end
    check(d and view == nil and d:heading() == "Garden plan" and d.meta and d.meta.tags[1] == "garden" and #d.sketch:live() == 1,
        "a tap on it: its drawing (the name and tag in the top bar, the stroke there), not the note's page")
    draw(E, 0.6)
end, after = 3 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 3 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ fn = function(E)
    local Memos = require("gzreader_memos")
    local list = Memos:new(plugin().store.memos):list(nil, nil, 20)
    local found, n = nil, 0
    for _i, m in ipairs(list and list.memos or {}) do if m.content == "# Garden plan\n\n#garden" then found = m; n = n + 1 end end
    check(screen() == nil and editor() == nil and n == 1 and found and #found.attachments == 1,
        "Done: back on the Notes tab, the same note saved with its drawing (" .. n .. " note, " .. tostring(found and #found.attachments) .. " drawing)")
    local f = io.open(E.out .. "/new-drawing-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
