-- A keyboard Kindle's note editor is the formatted page the touch Kindles
-- have (gzreader_richedit.lua, `keys`): the letters type, Alt + a letter
-- formats (B bold, L list, C checklist, X ticks it), Press is a new line,
-- ▼ from the last line reaches the toolbar, Alt+S saves what Memos' own
-- editor would write.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_TREE=<tree>/koreader run.sh notes_keyboard_rich.lua <out>     (k3)
-- Checks go to <out>/notes-keyboard-rich-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.barOptions then return w.widget end end
end
local function text() return editor():text() end
local function keys(str, after)
    for ch in str:gmatch(".") do add({ key = ch == " " and " " or ch:upper(), after = 0.5 }) end
    add({ fn = function() end, after = after or 1 })
end
local function alt(k) add({ combo = { "Alt", k }, after = 1.5 }) end
local function state()
    return require("json").decode((require("socket.http").request("http://127.0.0.1:18090/__state")))
end
local NOTE = "# Packing list\n\nSome **bold** and *italic* words.\n\n- [ ] tent\n- [x] stove\n\n| Item | Weight |\n| --- | --- |\n| Tent | 1.2 kg |"
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().show(p)
end, after = 9 })
-- a new note, typed
add({ fn = function() N().edit(plugin(), nil) end, after = 6 })
add({ fn = function()
    local ed = editor()
    local sh = require("device").screen:getHeight()
    check(ed and ed.rich and ed.keys_bar and ed.input.keys and ed.input.keyboard == nil,
        "a new note on a keyboard Kindle: the formatted page, no on-screen keyboard")
    check(#ed:tools() == 7 and ed[1][1]:getSize().h <= sh, "…its toolbar under it (List … Tag, Save), all within the screen")
end, after = 1 })
keys("hello")
add({ fn = function() check(text() == "hello", "the letters type: " .. text()) end, after = 0.5 })
alt("B")
add({ fn = function() check(text() == "**hello**", "Alt+B: the word at the cursor bold (" .. text() .. ")") end, after = 0.5 })
add({ key = "Press", after = 1 })
keys("milk")
alt("C")
add({ fn = function() check(text() == "**hello**\n\n- [ ] milk", "Press: a new line; Alt+C: it's a checklist item (" .. text():gsub("\n", "\\n") .. ")") end, after = 0.5 })
alt("X")
add({ fn = function() check(text() == "**hello**\n\n- [x] milk", "Alt+X: ticked (" .. text():gsub("\n", "\\n") .. ")") end, after = 0.5 })
add({ key = "Del", after = 1 })
add({ fn = function() check(text() == "**hello**\n\n- [x] mil", "Del: the character before the cursor gone") end, after = 0.5 })
add({ combo = { "Alt", "Q" }, after = 1 })
add({ fn = function() check(text() == "**hello**\n\n- [x] mil1", "Alt+Q: 1 (the top row's digits)") end, after = 0.5 })
add({ shot = "1-typed", after = 0.5 })
-- ▼ on the last line: the toolbar; ▶ and Press: a tool; ▲: back to the text
add({ key = "Down", after = 1.5 })
add({ fn = function() check(editor().focus_tool ~= nil and editor().input.focused == false, "▼ from the last line: on the toolbar") end, after = 0.5 })
add({ shot = "2-toolbar", after = 0.5 })
add({ key = "Up", after = 1.5 })
add({ fn = function() check(editor().focus_tool == nil and editor().input.focused == true, "▲: back in the text") end, after = 0.5 })
add({ key = "Up", after = 1 })
add({ fn = function()
    local ri = editor().input
    check(ri.cur.b == ri.doc.blocks[1], "▲: the cursor up a line (on the first)")
end, after = 0.5 })
add({ combo = { "Shift", "Left" }, after = 1 })
add({ combo = { "Shift", "Left" }, after = 1 })
add({ fn = function()
    local ri = editor().input
    local p, q = ri:selection()
    check(p and q and math.abs(q.i - p.i) == 2, "Shift + ◀ twice: two characters selected")
end, after = 0.5 })
alt("K")
add({ fn = function() check(text():find("%*", 1) ~= nil and text() ~= "**hello**\n\n- [x] mil1", "Alt+K: the selection italic (" .. text():gsub("\n", "\\n") .. ")") end, after = 0.5 })
alt("S")
add({ fn = function() end, after = 6 })
add({ fn = function(E)
    local found
    for _i, m in ipairs(state().memos) do if m.content:find("mil1", 1, true) then found = m.content end end
    check(editor() == nil and found ~= nil and found:find("- [x] mil1", 1, true) ~= nil, "Alt+S: saved to Memos (" .. tostring(found):gsub("\n", "\\n") .. ")")
end, after = 1 })
-- an existing note with a table: formatted, the table kept as it was written
add({ fn = function()
    N().edit(plugin(), { name = "memos/m900", content = NOTE, tags = {}, visibility = "PRIVATE", attachments = {} })
end, after = 6 })
add({ shot = "3-existing", after = 0.5 })
add({ fn = function()
    local ed = editor()
    check(ed.rich and text() == NOTE, "an existing note opened and not touched: its Markdown exactly as it was")
    check(ed.bar_title == "Packing list", "the bar has its name")
end, after = 0.5 })
alt("M")
add({ fn = function(E)
    local d = editor().options_dialog
    check(d ~= nil, "Alt+M: the menu")
    if d then UIM():close(d) end
    local f = io.open(E.out .. "/notes-keyboard-rich-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 1 })
return s
