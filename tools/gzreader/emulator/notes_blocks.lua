-- The note editor in blocks (touch Kindles), as Memos' rich editor: a note
-- written there (a heading, bold and italic, an &nbsp; line, a checklist, a
-- numbered list, code, a tag) opens formatted with no Markdown to see; tap a
-- block, tick a box, Enter for the next item, B on a word, Save; Memos gets
-- the Markdown its own editor would write.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_blocks.lua <out>
-- Checks go to <out>/notes-blocks-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.blocks_mode ~= nil and w.widget.on_save then return w.widget end end
end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
-- the block items drawn, in order
local function items(e)
    local out = {}
    local function walk(w)
        for _i, c in ipairs(w) do
            if type(c) == "table" then
                if c.block then out[#out + 1] = c else walk(c) end
            end
        end
    end
    walk(e.block_slot)
    return out
end
local function itemOf(e, text)
    for _i, it in ipairs(items(e)) do
        if require("gzreader_blocks").plain(it.block) == text then return it end
    end
end
-- "▲ more above" / "▼ more below" (when the note is longer than the room)
local function more(e, up)
    for _i, c in ipairs(e.block_slot[1] or {}) do
        if c.ges_events and c.ges_events.TapMore and c[1] and c[1].text and c[1].text:match(up and "above" or "below") then return c end
    end
end
-- taps "more above" until the block with `text` shows (one tap a step)
local function reveal(text)
    return { fn = function(E)
        local e = editor()
        if itemOf(e, text) then return end
        local m = more(e, true)
        if m then E.tap(centre(m.dimen)) end
    end, after = 1.5 }
end
-- toolbar button `i` (1–8; 9: Save), from where it was drawn
local function tool(e, i)
    local bar = e.bar_slot[1]
    local k = 0
    for _j, w in ipairs(bar) do
        if w.ges_events and w.dimen then
            k = k + 1
            if k == i then return centre(w.dimen) end
        end
    end
end
local CONTENT = "## Weekend\n\nPack the **tent** and *maps*.\n\n&nbsp;\n\n- [ ] stove\n- [x] water\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
local EXPECT = "## Weekend\n\n**Pack** the **tent** and *maps*.\n\n&nbsp;\n\n- [x] stove\n- [ ] lamp\n- [x] water\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
local note

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local c = require("gzreader_memos"):new(p.store.memos)
    note = c:create(CONTENT, "PRIVATE")
    check(note ~= nil, "a note written in Memos' rich editor")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local m
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then m = n end end
    local ok, err = xpcall(function() Notes.edit(plugin(), m) end, debug.traceback)
    if not ok then E.say("edit failed", err) end
end, after = 4 })
add({ shot = "1-opened", after = 1 })
add({ fn = function(E)
    local e = editor()
    check(e and e.blocks_mode, "a touch Kindle edits in blocks")
    local kinds = {}
    for _i, b in ipairs(e.doc.blocks) do kinds[#kinds + 1] = b.kind end
    check(table.concat(kinds, ",") == "heading,paragraph,paragraph,task,task,ordered,ordered,raw,paragraph",
        "the note's blocks: " .. table.concat(kinds, ","))
    check(e.input:getText() == "#trip", "the cursor in its last words (#trip), no markers")
    local any_nbsp = false
    for _i, b in ipairs(e.doc.blocks) do
        if require("gzreader_blocks").plain(b):match("&nbsp;") then any_nbsp = true end
    end
    local shown = items(e)
    check(#shown >= 3 and shown[#shown].block == e.cur and not any_nbsp,
        "the blocks shown end with the one edited (" .. #shown .. " shown); no &nbsp; anywhere")
    check(more(e, true) ~= nil, "a note longer than the room: \"more above\"")
    check(e:text() == CONTENT and not e:changed(), "nothing changed yet: it would be saved exactly as it was")
end, after = 0.5 })
add(reveal("stove"))
add(reveal("stove"))
add(reveal("stove"))
add({ fn = function(E)
    local e = editor()
    check(itemOf(e, "stove") ~= nil, "\"more above\" brings the checklist into sight")
    E.tap(centre(itemOf(e, "stove").dimen))
end, after = 2 })
add({ shot = "2-stove-tapped", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(require("gzreader_blocks").plain(e.cur) == "stove" and e.input:getText() == "stove", "tapping 'stove': it's the block edited")
    local it = itemOf(e, "stove")
    E.tap({ it.dimen.x + 20, it.dimen.y + math.floor(it.dimen.h / 2) })
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(itemOf(e, "stove").block.done == true, "tapping its box ticks it")
    e.input:moveCursorToCharPos(6)
    e.input:addChars("\n") -- (the keyboard's Enter)
end, after = 1.5 })
add({ fn = function(E)
    local e = editor()
    check(e.cur.kind == "task" and e.input:getText() == "", "Enter at the end of an item: a new item, its words empty")
    for _i, ch in ipairs({ "l", "a", "m", "p" }) do e.input:addChars(ch) end
end, after = 1.5 })
add({ shot = "3-new-item", after = 0.5 })
add(reveal("Pack the tent and maps."))
add(reveal("Pack the tent and maps."))
add(reveal("Pack the tent and maps."))
add({ fn = function(E)
    local e = editor()
    E.tap(centre(itemOf(e, "Pack the tent and maps.").dimen))
end, after = 2 })
add({ fn = function(E)
    local e = editor()
    check(e.input:getText() == "Pack the tent and maps.", "the paragraph: its words without ** and *")
    e.input:moveCursorToCharPos(2)
    E.tap(tool(e, 5)) -- B
end, after = 2 })
add({ shot = "4-bold", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(e:text() == EXPECT, "the Markdown to send:\n" .. e:text())
    E.tap(tool(e, 9)) -- Save
end, after = 2 })
add({ wait_for = function() local q = plugin().store.memos.queue; return q and #q == 0 end, timeout = 25 })
add({ fn = function(E)
    local c = require("gzreader_memos"):new(plugin().store.memos)
    local list = c:list(nil, nil, 50)
    local now
    for _i, m in ipairs(list and list.memos or {}) do if m.name == note.name then now = m end end
    check(now and now.content == EXPECT, "Memos has it as its rich editor writes it (unchanged blocks as they were)")
end, after = 0.5 })
add({ shot = "5-saved", after = 0.5 })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-blocks-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
