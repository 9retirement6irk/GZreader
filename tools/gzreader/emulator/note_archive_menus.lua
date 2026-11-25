-- Archive and delete from the note editor's ⋮ and the drawing screen's bar and ⋮:
-- a note's editor → Draw → a page drawn → ⋮ → Archive note (the drawing is
-- saved, then the note archived; both screens close); another note's
-- editor → ⋮ → Delete note… (asks; then deleted in Memos).
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh note_archive_menus.lua <out>
-- Checks go to <out>/note-archive-menus-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function N() return require("gzreader_notes") end
local W, H
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then return w.widget end end
end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function memosState()
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local by = {}
    for _i, m in ipairs(st.memos or {}) do by[m.name] = m end
    return by
end

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will", queue = {} }
    N().edit(p, { name = "memos/m003", content = "\"The woods were full of ghosts.\" #quotes", tags = { "quotes" },
        visibility = "PRIVATE", attachments = {} })
end, after = 3 })
add({ fn = function(_E) editor():openDrawing() end, after = 3 })
add({ fn = function(E) if find("gz_paperlist") then E.tap("Create") end end, after = 4 })
add({ fn = function(E)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { math.floor(W * (0.3 + 0.04 * i)), math.floor(H * (0.5 + 0.02 * math.sin(i))) } end
    E.finger(pts, 0.4)
end, after = 3 })
add({ shot = "0-drawing-bar", after = 0.5 })
add({ fn = function(E)
    -- (not in the top bar: in ⋮ only)
    local bar = {}
    for _i, b in ipairs(screen().buttons) do
        if b.group == "top" then bar[b.tool.id] = b.rect end
    end
    check(bar.options and not bar["archive-note"] and not bar["delete-note"],
        "the drawing screen's top bar (a note that's there): no Archive or Delete (they're in ⋮)")
    E.tap(button("options"))
end, after = 2 })
add({ shot = "1-drawing-options", after = 0.5 })
add({ fn = function(E)
    check(button("archive-note") ~= nil and button("delete-note") ~= nil, "the drawing screen's ⋮ (a note that's there): Archive note, Delete note…")
    E.tap(button("archive-note"))
end, after = 4 })
add({ wait_for = function() return #(plugin().store.memos.queue or {}) == 0 end, timeout = 30 })
add({ fn = function(_E)
    local m = memosState()["memos/m003"]
    local drawn = false
    for _i, a in ipairs(m and m.attachments or {}) do if tostring(a.filename):match("canvas%.png$") then drawn = true end end
    check(screen() == nil and editor() == nil, "Archive note: the drawing screen and the editor closed")
    check(m and m.state == "ARCHIVED" and drawn, "…the drawing saved with the note, then the note archived in Memos")
    N().edit(plugin(), { name = "memos/m004", content = "Notes tab for the Kindle. #ideas", tags = { "ideas" },
        visibility = "PRIVATE", attachments = {} })
end, after = 3 })
add({ fn = function(E) E.tap(centre(editor().bar_buttons.options.dimen)) end, after = 2 })
add({ fn = function(E)
    check(E.findText("Archive note") ~= nil and E.findText("Delete note…") ~= nil, "the editor's ⋮: Archive note, Delete note…")
    E.tap("Delete note…")
end, after = 2 })
add({ shot = "2-delete-asks", after = 0.5 })
add({ fn = function(_E)
    local box
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.ok_text == "Delete" then box = w.widget end end
    check(box ~= nil and editor() ~= nil, "Delete note…: asks first")
    if box then box.ok_callback(); UIM():close(box) end
end, after = 2 })
add({ wait_for = function() return #(plugin().store.memos.queue or {}) == 0 end, timeout = 30 })
add({ fn = function(E)
    check(editor() == nil and memosState()["memos/m004"] == nil, "Delete: the editor closed, the note gone from Memos")
    local f = io.open(E.out .. "/note-archive-menus-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
