-- An opened note on a touch Kindle has the drawing screen's top bar, as the
-- note editor does: ← the note's name (when, its space, pinned under it),
-- then the pin, ⋮ and Edit; no buttons along the bottom.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh note_view_bar.lua <out>
-- Checks go to <out>/note-view-bar-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function N() return require("gzreader_notes") end
local function view()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.memo and w.widget.scroller then return w.widget end end
end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then return w.widget end end
end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local memo

add({ fn = function(_E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will", queue = {} }
    memo = { name = "memos/m001", content = "# Weekend\n\nBike to the lake, then lunch.\n\n- [ ] sandwiches\n- [x] water\n\n#plans",
        tags = { "plans" }, visibility = "PRIVATE", created = "2026-11-16T10:00:00Z", attachments = {} }
    N().showNote(p, memo)
end, after = 3 })
add({ shot = "1-note", after = 0.5 })
add({ fn = function(E)
    local v = view()
    local bb = v and v.bar_buttons or {}
    check(v and bb.back and bb.pin and bb.options and bb.edit and v.bar_title == "Weekend",
        "an opened note: the top bar, ← and its name (" .. tostring(v and v.bar_title) .. ")")
    check(bb.back and bb.back.dimen.x < bb.pin.dimen.x and bb.pin.dimen.x < bb.options.dimen.x and bb.options.dimen.x < bb.edit.dimen.x,
        "…then the pin, ⋮ and Edit, in that order")
    local ed = editor() -- (none yet)
    check(ed == nil and E.findText("More") == nil and E.findText("Close") == nil, "…and no buttons along the bottom")
    check(bb.edit and bb.edit.dimen.y < require("gzreader_notebar").height(), "…at the top of the screen")
    E.tap(centre(bb.pin.dimen))
end, after = 3 })
add({ fn = function(E)
    local v = view()
    check(memo.pinned == true and (view().bar_hint or ""):find("pinned", 1, true) ~= nil, "the pin: pinned (it says so under the name)")
    E.tap(centre(v.bar_buttons.options.dimen))
end, after = 3 })
add({ fn = function(E)
    check(E.findText("Back to the board") ~= nil, "⋮: the note's More")
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.title == "Note" and w.widget.buttons then UIM():close(w.widget) end
    end
end, after = 2 })
add({ fn = function(E) E.tap(centre(view().bar_buttons.edit.dimen)) end, after = 4 })
add({ shot = "2-edit", after = 0.5 })
add({ fn = function(_E)
    local e = editor()
    check(e and e.bar_buttons and e.bar_buttons.done and e.bar_title == "Weekend", "Edit: the editor, with the same bar")
    if e then UIM():close(e) end
end, after = 3 })
add({ fn = function(E) local v = view(); if v then E.tap(centre(v.bar_buttons.back.dimen)) end end, after = 3 })
add({ fn = function(E)
    check(view() == nil, "←: back to the board")
    local f = io.open(E.out .. "/note-view-bar-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })

return s
