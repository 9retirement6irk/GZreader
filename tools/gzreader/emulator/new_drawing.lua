-- The New drawing window (gzreader_newdrawing.lua): the Notes tab's Draw, a
-- stroke, Done: a window "New drawing" with a title and # Tag, not the note's
-- page; Back to drawing and back; a title and a new tag; Save: the note in
-- Memos (demo/mock_memos.py on 18090) with "# title", the tag and the drawing.
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
local function ND() return require("gzreader_newdrawing") end
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
local function press(d, label)
    for _i, row in ipairs(d.buttons or {}) do
        for _j, b in ipairs(row) do if b.text == label then return b.callback() end end
    end
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
add({ fn = function(E)
    local e = editor()
    check(screen() ~= nil and e and e.popup_only and e.covers_fullscreen == false, "Draw: the drawing screen (the note's page out of sight)")
    draw(E, 0.4)
end, after = 2 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 3 })
add({ shot = "1-new-drawing-window", after = 0.5 })
add({ fn = function(E)
    local d = ND().current
    check(screen() == nil and d and d.title == "New drawing" and editor() and editor().popup_only,
        "Done: the New drawing window, not the note's page")
    press(d, "Back to drawing")
end, after = 2 })
add({ fn = function(E)
    check(screen() ~= nil and #screen().sketch:live() == 1, "Back to drawing: the drawing screen again, the stroke there")
    draw(E, 0.6)
end, after = 2 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 3 })
add({ fn = function(E)
    local d = ND().current
    check(d and d.title == "New drawing", "Done again: the window")
    d:setInputText("Garden plan")
    press(d, "# Tag")
end, after = 2 })
add({ shot = "2-tags", after = 0.5 })
add({ fn = function(E)
    local picker = ND().current
    check(picker and picker.title == "Add a tag", "# Tag: your tags and New tag…")
    for _i, row in ipairs(picker.buttons or {}) do
        for _j, b in ipairs(row) do if b.text == "New tag…" then b.callback() end end
    end
end, after = 2 })
add({ fn = function(E)
    local d = ND().current
    d:setInputText("garden")
    press(d, "Add")
end, after = 2 })
add({ shot = "3-titled-tagged", after = 0.5 })
add({ fn = function(E)
    local d = ND().current
    check(d and d.title == "New drawing" and d:getInputText() == "Garden plan" and tostring(d.description):find("#garden", 1, true),
        "back in the window: the title kept, the tag shown (" .. tostring(d and d.description) .. ")")
    press(d, "Save")
end, after = 1 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ fn = function(E)
    local open = false
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "New drawing" then open = true end end
    check(editor() == nil and not open, "Save: the window and the editor closed")
    local Memos = require("gzreader_memos")
    local list = Memos:new(plugin().store.memos):list(nil, nil, 20)
    local found
    for _i, m in ipairs(list and list.memos or {}) do if m.content == "# Garden plan\n\n#garden" then found = m end end
    local pic = found and found.attachments and found.attachments[1]
    check(found and pic and tostring(pic.filename):match("%.canvas%.png$"),
        "in Memos: \"# Garden plan\", #garden and the drawing (" .. tostring(found and #found.attachments) .. " attachment)")
    local f = io.open(E.out .. "/new-drawing-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
