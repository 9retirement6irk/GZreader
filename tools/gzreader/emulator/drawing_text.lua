-- Text boxes on a drawing: the Text tool, a tap on the page asks for the
-- words, the box is drawn into the page and chosen (a frame, a corner
-- handle); dragged it moves, its corner resizes it (the words wrap at the
-- new width); tapped again its words change; Undo; Done saves it into the
-- note's drawing as memos' text element (in the PNG's scene).
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh drawing_text.lua <out>
-- (GZ_EMU_MODEL=scribe too: the pen taps and drags.) Checks go to <out>/drawing-text-checks.txt.
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
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function drag(E, a, b)
    local pts = {}
    for i = 0, 8 do pts[#pts + 1] = { math.floor(a[1] + (b[1] - a[1]) * i / 8), math.floor(a[2] + (b[2] - a[2]) * i / 8) } end
    if PEN then E.pen(pts, 1.2) else E.finger(pts, 1.2) end
end
local function dialog()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Text box" then return w.widget end end
end
local function boxRect()
    local d = screen()
    local el = d and d.sketch:liveTexts()[1]
    if not el then return nil end
    local x0, y0 = d.sketch:toCanvas(el.x, el.y)
    local x1, y1 = d.sketch:toCanvas(el.x + el.width, el.y + el.height)
    return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }, el
end
local first

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_notes").draw(p)
end, after = 3 })
add({ fn = function(E) if find("gz_paperlist") then tapAt(E, "Create") end end, after = 4 })
add({ fn = function(E)
    check(screen() ~= nil and button("text") ~= nil, "the drawing screen: a Text tool among the tools")
    tapAt(E, button("text"))
end, after = 2 })
add({ fn = function(E)
    check(screen().tool == "text", "Text: in hand")
    tapAt(E, { math.floor(W * 0.3), math.floor(H * 0.35) })
end, after = 3 })
add({ fn = function(_E)
    local d = dialog()
    check(d ~= nil, "a tap on the page: its words asked for")
    if d then
        d:addTextToInput("Pick up the bike on Saturday morning")
        for _i, row in ipairs(d.button_table and d.button_table.buttons_layout or {}) do
            for _j, b in ipairs(row) do if b.text == "Add" then b.callback() end end
        end
    end
end, after = 3 })
add({ shot = "1-box", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local r, el = boxRect()
    first = r and { x = el.x, y = el.y, width = el.width }
    check(el and el.text == "Pick up the bike on Saturday morning" and d.text_sel == el and el.type == "text",
        "Add: the box on the page, chosen")
    check(r and math.abs(r.x - W * 0.3) < 4 and math.abs(r.y - H * 0.35) < 4, "…where the tap was")
    -- drag it down and left
    drag(E, { math.floor(r.x + 30), math.floor(r.y + 10) }, { math.floor(r.x - 70), math.floor(r.y + 210) })
end, after = 3 })
add({ fn = function(E)
    local r, el = boxRect()
    check(el and el.x < first.x - 20 and el.y > first.y + 60 and el.width == first.width and #screen().sketch:live() == 0,
        "dragged: moved, the same size, no ink")
    -- its corner: narrower
    drag(E, { math.floor(r.x + r.w - 4), math.floor(r.y + r.h - 4) }, { math.floor(r.x + r.w * 0.5), math.floor(r.y + r.h + 40) })
end, after = 3 })
add({ shot = "2-moved-resized", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local r, el = boxRect()
    local need = d:textHeight(el)
    check(el and el.width < first.width - 20 and el.height >= need - 0.5, "its corner dragged: narrower, its words wrapping (" .. tostring(el and el.width) .. " units)")
    tapAt(E, { math.floor(r.x + 20), math.floor(r.y + 10) })
end, after = 3 })
add({ fn = function(_E)
    local d = dialog()
    check(d ~= nil and d:getInputText() == "Pick up the bike on Saturday morning", "a tap on the chosen box: its words to change")
    if d then
        d:setInputText("Pick up the bike Saturday 9am")
        for _i, row in ipairs(d.button_table and d.button_table.buttons_layout or {}) do
            for _j, b in ipairs(row) do if b.text == "Save" then b.callback() end end
        end
    end
end, after = 3 })
add({ fn = function(E)
    local el = select(2, boxRect())
    check(el and el.text == "Pick up the bike Saturday 9am", "Save: the new words")
    tapAt(E, button("undo"))
end, after = 2 })
add({ fn = function(E)
    local el = select(2, boxRect())
    check(el and el.text == "Pick up the bike on Saturday morning", "Undo: the words before")
    tapAt(E, button("redo"))
end, after = 2 })
add({ fn = function(E) tapAt(E, button("done")) end, after = 5 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 30 })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local made
    for _i, m in ipairs(st.memos or {}) do
        for _j, a in ipairs(m.attachments or {}) do if tostring(a.filename):match("canvas%.png$") then made = a end end
    end
    check(made ~= nil, "Done: the drawing in Memos")
    local Memos = require("gzreader_memos")
    local found
    if made then
        local path = E.out .. "/drawing-text.canvas.png"
        local c = Memos:new(plugin().store.memos)
        c:download(made, path)
        local scene = require("gzreader_drawing").readFile(path)
        for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "text" then found = el end end
    end
    check(found and found.text == "Pick up the bike Saturday 9am" and found.autoWidth == false, "…with the box as memos' text element")
    local f = io.open(E.out .. "/drawing-text-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
