-- Keyboard Kindles (k3; k4 for the opened note): an opened note and the
-- editor have the touch Kindles' top bar (the note's name, a grey line
-- under it) without buttons, and Alt+M in the editor has its menu: who can
-- see it, Archive note, Delete note…, Close.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_TREE=<tree>/koreader run.sh notes_keyboard_bars.lua <out>
-- Checks go to <out>/notes-keyboard-bars-checks.txt.
local MODEL = os.getenv("GZ_EMU_MODEL") or "k3"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function find(pat)
    for _i, m in ipairs(N().visible()) do if tostring(m.content):find(pat, 1, true) then return m end end
end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.barOptions then return w.widget end end
end
local function state()
    return require("json").decode((require("socket.http").request("http://127.0.0.1:18090/__state")))
end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().show(p)
end, after = 9 })
add({ wait_for = function() return find("Georgia section") ~= nil end, timeout = 60 }) -- (a slow model: the notes loaded)
add({ fn = function(E) E.v = N().showNote(plugin(), find("Georgia section")) end, after = 5 })
add({ shot = "1-opened", after = 0.5 })
add({ fn = function(E)
    local v = E.v
    check(v.bar_title == "Georgia section" and tostring(v.bar_hint):find("Today", 1, true) ~= nil and next(v.bar_buttons) == nil,
        "an opened note: its name at the top, its date under it (" .. tostring(v.bar_title) .. " / " .. tostring(v.bar_hint) .. "); no buttons")
    v:onClose()
end, after = 4 })
if MODEL ~= "k4" then -- (a keyboard: k3, dx, k2)
    add({ fn = function(E) N().edit(plugin(), find("Georgia section")) end, after = 6 })
    add({ shot = "2-editor", after = 0.5 })
    add({ fn = function(E)
        local ed = editor()
        check(ed and ed.keys_bar and ed.bar_title == "Georgia section", "the editor: the same bar, the note's name")
        local sh = require("device").screen:getHeight()
        local h = ed[1][1]:getSize().h
        check(h <= sh, "…and everything fits the screen, the keys listed at the foot too (" .. h .. " of " .. sh .. ")")
    end, after = 1 })
    add({ combo = { "Alt", "M" }, after = 3 })
    add({ shot = "3-menu", after = 0.5 })
    add({ fn = function(E)
        local d = top()
        local t = {}
        for _i, row in ipairs(d and d.buttons or {}) do t[#t + 1] = row[1].text end
        local texts = table.concat(t, "|")
        check(d == editor().options_dialog and texts:find("Who can see it: Private", 1, true) and texts:find("Archive note", 1, true)
            and texts:find("Delete note…", 1, true) and texts:find("Close", 1, true), "Alt+M: " .. texts)
        E.before = #state().memos
        for _i, row in ipairs(d.buttons) do if row[1].text == "Archive note" then row[1].callback() end end
    end, after = 6 })
    add({ fn = function(E)
        local archived
        for _i, m in ipairs(state().memos) do if m.content:find("Georgia section", 1, true) then archived = m.state end end
        check(editor() == nil and archived == "ARCHIVED" and find("Georgia section") == nil,
            "Archive note: the editor closed, the note archived in Memos (" .. tostring(archived) .. "), off the board")
    end, after = 1 })
end
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-keyboard-bars-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
