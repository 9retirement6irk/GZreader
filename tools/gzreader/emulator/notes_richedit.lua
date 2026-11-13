-- The note editor on a touch Kindle, as Memos' web editor: a note written
-- there (a heading, bold and italic, an &nbsp; line, a checklist, a numbered
-- list, code, a tag) opens formatted on one page, with no Markdown to see.
-- Tap into a word, tick a box, the keyboard's Enter (⮠) for a new item, type
-- on the keys, hold and drag to select, Head on the selection, B, Save:
-- Memos gets the Markdown its own editor would write.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_richedit.lua <out>
-- Checks go to <out>/notes-richedit-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then return w.widget end end
end
local function Blocks() return require("gzreader_blocks") end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
-- the screen point of character position i of the line showing `text`
local function point(e, text, i)
    local r = e.input
    for _i, l in ipairs(r.lines) do
        if Blocks().plain(l.b) == text then
            local x = l.xs[(i or 1) - l.a + 1] or l.xs[#l.xs]
            return { r.dimen.x + x + 3, r.dimen.y + l.y - r.top + math.floor(l.h / 2) }, l
        end
    end
end
-- the on-screen keyboard's key with `label`
local function key(e, label)
    local kb = e.input.keyboard
    for _i, row in ipairs(kb.layout or {}) do
        for _j, k in ipairs(row) do
            if k.label == label and k.dimen then return k end
        end
    end
end
-- toolbar button `i` (1–7; 8: Save), from where it was drawn
local function tool(e, i)
    local k = 0
    for _j, w in ipairs(e.bar_slot[1]) do
        if w.ges_events and w.dimen then
            k = k + 1
            if k == i then return centre(w.dimen) end
        end
    end
end
local CONTENT = "## Weekend\n\nPack the **tent** and *maps*.\n\n&nbsp;\n\n- [ ] stove\n- [x] water\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
local EXPECT = "# Weekend away\n\n**Pack** the **tent** and *maps*.\n\n&nbsp;\n\n- [x] stove\n- [ ] lamp\n- [x] water\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
local note

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    note = require("gzreader_memos"):new(p.store.memos):create(CONTENT, "PRIVATE")
    check(note ~= nil, "a note written in Memos' rich editor")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then Notes.edit(plugin(), n) end end
end, after = 4 })
add({ shot = "1-opened", after = 1 })
add({ fn = function(E)
    local e = editor()
    check(e and e.rich and e.input.lines, "a touch Kindle edits the note formatted")
    local plain = {}
    for _i, b in ipairs(e.doc.blocks) do plain[#plain + 1] = Blocks().plain(b) end
    local all = table.concat(plain, "|")
    check(not all:find("&nbsp;", 1, true) and not all:find("**", 1, true) and not all:find("- [", 1, true),
        "nothing to see of the Markdown: " .. all)
    check(key(e, "⮠") and key(e, "←") and key(e, "→"), "the keyboard has Enter and ← → on its letters page")
    check(e:text() == CONTENT and not e:changed(), "nothing changed yet: it would be saved exactly as it was")
    E.tap((point(e, "stove", 6)))
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(Blocks().plain(e.input.cur.b) == "stove" and e.input.cur.i == 6, "tap after 'stove': the cursor there")
    local l = select(2, point(e, "stove", 1))
    E.tap({ e.input.dimen.x + l.x0 - 20, e.input.dimen.y + l.y - e.input.top + math.floor(l.h / 2) })
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(e.input.cur.b.done == true, "tap its ☐: ticked")
    E.tap(centre(key(e, "⮠").dimen))
end, after = 1.5 })
add({ fn = function(E)
    local e = editor()
    check(e.input.cur.b.kind == "task" and #e.input.cur.b.chars == 0, "the keyboard's Enter: a new item")
    E.tap(centre(key(e, "l").dimen))
end, after = 0.6 })
add({ fn = function(E) E.tap(centre(key(editor(), "a").dimen)) end, after = 0.6 })
add({ fn = function(E) E.tap(centre(key(editor(), "m").dimen)) end, after = 0.6 })
add({ fn = function(E) E.tap(centre(key(editor(), "p").dimen)) end, after = 1 })
add({ shot = "2-new-item", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(Blocks().plain(e.input.cur.b) == "lamp", "typed on the keys: 'lamp'")
    -- the heading: tap at its end, type " away"
    E.tap((point(e, "Weekend", 8)))
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    e.input:addChars(" away")
    -- hold "Weekend" and drag to the end of the line: selected
    local p1 = point(e, "Weekend away", 2)
    local p2 = point(e, "Weekend away", 13)
    E.holdDrag(p1[1], p1[2], p2[1], p2[2])
end, after = 4 })
add({ shot = "3-selected", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    local a, b = e.input:selection()
    check(a and b and a.i == 1 and b.i == 13, "hold and drag: 'Weekend away' selected")
    E.tap(tool(e, 1)) -- Head: from heading 2 to 3
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(e.input.cur.b.kind == "heading" and e.input.cur.b.level == 3, "Head on a heading 2: heading 3")
    E.tap(tool(e, 1)) -- → text
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    E.tap(tool(e, 1)) -- → heading 1
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(e.input.cur.b.kind == "heading" and e.input.cur.b.level == 1, "…then text, then heading 1")
    E.tap((point(e, "Pack the tent and maps.", 3)))
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    E.tap(tool(e, 5)) -- B on "Pack"
end, after = 2 })
add({ shot = "4-formatted", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(e:text() == EXPECT, "the Markdown to send:\n" .. e:text())
    E.tap(tool(e, 8)) -- Save
end, after = 2 })
add({ wait_for = function() local q = plugin().store.memos.queue; return q and #q == 0 end, timeout = 25 })
add({ fn = function(E)
    local c = require("gzreader_memos"):new(plugin().store.memos)
    local list = c:list(nil, nil, 50)
    local now
    for _i, m in ipairs(list and list.memos or {}) do if m.name == note.name then now = m end end
    check(now and now.content == EXPECT, "Memos has it as its rich editor writes it (unchanged blocks as they were)")
end, after = 0.5 })
-- a one-line box (the tag dialog's New tag): ZenOS' short bottom row
add({ fn = function(E)
    local InputDialog = require("ui/widget/inputdialog")
    local d = InputDialog:new{ title = "One line", input = "" }
    UIM():show(d)
    d:onShowKeyboard()
    E.one_line = d
end, after = 2 })
add({ fn = function(E)
    local d = E.one_line
    local kb = d._input_widget and d._input_widget.keyboard
    local enter = false
    for _i, row in ipairs(kb and kb.layout or {}) do
        for _j, k in ipairs(row) do if k.label == "⮠" then enter = true end end
    end
    check(kb and not enter, "a one-line box keeps ZenOS' short bottom row (no Enter on the letters page)")
    UIM():close(d)
end, after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-richedit-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
