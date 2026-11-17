-- The note editor's formatted page (gzreader_richedit.lua), on touch Kindles:
-- typing, Enter and Backspace, selections (hold and drag), the toolbar on a
-- selection or the cursor's line or word, ticking, tags, scrolling, the
-- keyboard's input box, and what Save writes. KOReader's widgets stubbed;
-- every character is 10 px wide.
--   luajit richedit_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function show(s) return (tostring(s):gsub("\n", "\\n")) end

-- ------------------------------------------------------------ stubs
local dirty = 0
local function class()
    local c = {}
    c.__index = c
    function c:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
    function c:new(o) o = o or {}; setmetatable(o, self); if o.init then o:init() end; return o end
    return c
end
local function stub(name, v) package.preload[name] = function() return v end end
stub("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_LIGHT_GRAY = 2, COLOR_DARK_GRAY = 3 })
stub("device", { screen = { scaleBySize = function(_s, n) return n end, getHeight = function() return 1000 end,
    getWidth = function() return 600 end } })
local faces = {}
stub("ui/font", { getFace = function(_s, name, size)
    local key = name .. size
    faces[key] = faces[key] or { name = name, size = size,
        ftsize = { getHeightAndAscender = function() return size * 1.2, size end } }
    return faces[key]
end })
stub("ui/geometry", { new = function(_s, o) return o end })
stub("ui/gesturerange", { new = function(_s, o) return o end })
stub("ui/widget/container/inputcontainer", class())
local drawn = {}
stub("ui/rendertext", {
    sizeUtf8Text = function(_s, _x, _w, _face, text) return { x = 10 * #require("gzreader_blocks").chars(text) } end,
    renderUtf8Text = function(_s, _bb, x, y, face, text) drawn[#drawn + 1] = { x = x, y = y, face = face, text = text } end,
})
stub("ui/uimanager", { setDirty = function() dirty = dirty + 1 end, scheduleIn = function() end })
local KB = class()
function KB:init() self.dimen = { h = 400 }; self.visible = false end
function KB:showKeyboard() self.visible = true end
function KB:hideKeyboard() self.visible = false end
function KB:isVisible() return self.visible end
stub("ui/widget/virtualkeyboard", KB)

local Blocks = require("gzreader_blocks")
local RE = require("gzreader_richedit")

local function editor(content, at_start)
    local e = { tag_asked = false }
    function e.pickTag() e.tag_asked = true end
    local doc = Blocks.parse(content)
    local r = RE:new{ width = 300, max_height = 900, doc = doc, editor = e, at_start = at_start, hint = "Write" }
    return r, doc
end
local function text(r) return Blocks.write(r.doc) end
local function kinds(r)
    local out = {}
    for _i, b in ipairs(r.doc.blocks) do out[#out + 1] = b.kind end
    return table.concat(out, ",")
end
local function block(r, k) return r.doc.blocks[k] end
local function at(r, k, i) return { b = block(r, k), i = i } end
local function select(r, p, q) r.anchor = p; r.cur = q; r:update() end
-- a gesture at a widget point
local function ges(x, y, kind) return { pos = { x = x, y = y }, ges = kind } end

-- ------------------------------------------------------------ a new note, typed
do
    local r = editor("", true)
    check(#r.doc.blocks == 1 and text(r) == "" and r.keyboard and r.height == 500, "a new note: one empty line; the room less the keyboard")
    check(r.gz_multiline == true, "the keyboard keeps Enter and ← → for it")
    r:useTool("heading")
    r:addChars("Shopping")
    check(text(r) == "# Shopping", "Head, then typing: '# Shopping' … " .. show(text(r)))
    r:addChars("\n")
    r:useTool("task")
    r:addChars("milk\neggs")
    check(kinds(r) == "heading,task,task" and text(r) == "# Shopping\n\n- [ ] milk\n- [ ] eggs",
        "Check, then Enter: the next item … " .. show(text(r)))
    r:addChars("\n")
    r:addChars("\n")
    check(kinds(r) == "heading,task,task,paragraph", "Enter on an empty item ends the list")
    r:addChars("Thanks")
    r:delChar(); r:delChar()
    check(Blocks.plain(r.cur.b) == "Than" and r.cur.i == 5, "⌫ deletes the character before the cursor")
    r:goToStartOfLine()
    r:delChar()
    check(kinds(r) == "heading,task,task" and Blocks.plain(r.cur.b) == "eggsThan" and r.cur.i == 5,
        "⌫ at a line's start joins it to the line before (the cursor between)")
    check(r.charlist and table.concat(r.charlist) == "Shopping\nmilk\neggsThan" and r.charpos == 19,
        "the keyboard's flat text and cursor (the space bar moves it)")
    r:moveCursorToCharPos(12)
    check(r.cur.b == block(r, 2) and r.cur.i == 3, "…and a flat position back to the line and character")
end

-- ------------------------------------------------------------ a selection and the toolbar
do
    local r = editor("one\n\ntwo\n\nthree", false)
    check(r.cur.b == block(r, 3) and r.cur.i == 6, "an edit: the cursor at the end of the note")
    select(r, at(r, 1, 1), at(r, 3, 3))
    r:useTool("bullet")
    check(text(r) == "- one\n- two\n- three", "List on a selection over three lines: three items … " .. show(text(r)))
    r:useTool("bullet")
    check(text(r) == "one\n\ntwo\n\nthree", "List again: text again")
    select(r, at(r, 1, 2), at(r, 3, 3))
    r:useTool("bold")
    check(text(r) == "o**ne**\n\n**two**\n\n**th**ree", "B on a selection across lines … " .. show(text(r)))
    r:useTool("bold")
    check(text(r) == "one\n\ntwo\n\nthree", "B again: off")
    select(r, at(r, 2, 1), at(r, 2, 4))
    r:addChars("2")
    check(text(r) == "one\n\n2\n\nthree" and r:selection() == nil, "typing replaces the selection")
    select(r, at(r, 1, 3), at(r, 3, 2))
    r:delChar()
    check(text(r) == "onhree" and kinds(r) == "paragraph", "⌫ on a selection over lines: deleted, the ends joined")
    r:useTool("heading"); r:useTool("heading")
    check(text(r) == "## onhree", "Head twice: heading 2")
    r:useTool("heading"); r:useTool("heading")
    check(text(r) == "onhree", "…four times: text again")
    r:useTool("tag")
    check(r.editor.tag_asked, "# Tag: asks which tag")
    r:setCursor({ b = block(r, 1), i = 3 })
    r:insertTag("ideas")
    check(text(r) == "on #ideas hree", "the tag at the cursor, spaces around it … " .. show(text(r)))
end

-- ------------------------------------------------------------ B / I without a selection
do
    local r = editor("make it bold", false)
    r:setCursor({ b = block(r, 1), i = 10 })
    r:useTool("bold")
    check(text(r) == "make it **bold**", "B: the word at the cursor")
    local r2 = editor("plain ", false)
    r2:useTool("italic")
    r2:addChars("slanted")
    check(text(r2) == "plain *slanted*", "I with no word at the cursor: what's typed next … " .. show(text(r2)))
    r2:leftChar()
    r2:addChars("x")
    check(text(r2):match("%*slantexd%*") ~= nil, "typed inside an italic word: italic too")
end

-- ------------------------------------------------------------ touch: tap, hold and drag, tick, swipe
do
    local r = editor("Plan\n\n- [ ] stove\n- [x] water\n\nPack the tent and the maps for the trip", false)
    local ls = r.lines
    check(#ls >= 5 and ls[1].b == block(r, 1), "laid out: a line per short paragraph … " .. #ls)
    local long = {}
    for _i, l in ipairs(ls) do if l.b == block(r, 4) then long[#long + 1] = l end end
    check(#long == 2 and long[1].z == 31 and long[2].a == 32, "a long paragraph wraps after a space (300 px: 30 characters) … "
        .. tostring(long[1] and long[1].z))
    -- tap in "stove": the cursor there
    local stove = ls[2]
    r:onTapEdit(nil, ges(stove.x0 + 27, stove.y + 5))
    check(r.cur.b == block(r, 2) and r.cur.i == 4 and r.keyboard:isVisible(), "tap: the cursor between characters, the keyboard up")
    -- tap the box
    r:onTapEdit(nil, ges(5, stove.y + 5))
    check(block(r, 2).done == true and text(r):match("%- %[x%] stove"), "tap a ☐: ticked")
    -- hold "tent", drag to "maps"
    local l1 = long[1]
    r:onHoldEdit(nil, ges(l1.x0 + 10 * 10 + 5, l1.y + 5))
    check(r:selection() and r.anchor.i == 10 and r.cur.i == 14, "hold: the word ('tent') selected")
    r:onHoldPanEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    r:onHoldReleaseEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    local p, q = r:selection()
    check(p and p.i == 10 and q.i == 27, "drag: the selection stretches ('tent and the maps')")
    r:useTool("bold")
    check(text(r):match("Pack the %*%*tent and the maps%*%* for") ~= nil, "…and B makes it bold")
    -- hold on "Plan", drag down into the list
    r:onHoldEdit(nil, ges(5, ls[1].y + 5))
    r:onHoldPanEdit(nil, ges(stove.x0 + 30, ls[3].y + 5))
    r:onHoldReleaseEdit(nil, ges(stove.x0 + 30, ls[3].y + 5))
    p, q = r:selection()
    check(p and p.b == block(r, 1) and q.b == block(r, 3), "drag over lines: the selection spans them")
    r:useTool("ordered")
    check(text(r):match("^1%. Plan\n2%. stove\n3%. water") ~= nil, "Num on it: a numbered list … " .. show(text(r)))
    -- up and down keep the column
    r:setCursor({ b = block(r, 4), i = 33 })
    r:upLine()
    check(r.cur.b == block(r, 4) and r.cur.i == 2, "↑ from the wrapped line: the same column on the line above")
    r:upLine()
    check(r.cur.b == block(r, 3), "↑ again: the item above")
    r:downLine(); r:downLine()
    check(r.cur.b == block(r, 4) and r.cur.i == 33, "↓ ↓: back where it was")
end

-- ------------------------------------------------------------ Memos' notes: kept as they were
do
    local note = "## Weekend\n\nPack the **tent**.\n\n&nbsp;\n\n1. drive\n2. hike\n\n```\nsite 42\n```\n\n#trip"
    local r = editor(note, false)
    check(text(r) == note and not r:isTextEdited(), "opened, nothing changed: written exactly as it was")
    check(#block(r, 3).chars == 0, "the &nbsp; line: an empty line, nothing to see")
    check(r.cur.b == block(r, 7) and r.cur.i == 6, "the cursor after #trip")
    -- typing in code: a line break in it
    r:setCursor({ b = block(r, 6), i = 12 })
    r:addChars("\n")
    check(#r.doc.blocks == 7 and text(r):match("```\nsite 42\n\n```"), "Enter in code: a line break in it, not a new line")
    r:onTapEdit(nil, ges(5, r.lines[1].y + 5))
    r:addChars("Long ")
    check(text(r):match("^## Long Weekend\n\nPack the %*%*tent%*%*%.\n\n&nbsp;") ~= nil, "typed in the heading: the rest unchanged")
    drawn = {}
    r:paintTo({ paintRect = function() end }, 0, 0)
    local saw_nbsp, saw_marker = false, false
    for _i, d in ipairs(drawn) do
        if d.text:match("&nbsp;") or d.text:match("%*%*") then saw_nbsp = true end
        if d.text == "1." then saw_marker = true end
    end
    check(not saw_nbsp and saw_marker, "drawn: no &nbsp; or ** anywhere; numbers before the items")
    local heading_face
    for _i, d in ipairs(drawn) do if d.text:match("Weekend") then heading_face = d.face end end
    check(heading_face and heading_face.size == RE.HEADING_SIZE[2] and heading_face.name == "NotoSans-Bold.ttf",
        "the heading drawn big and bold")
end

-- ------------------------------------------------------------ a long note scrolls
do
    local parts = {}
    for k = 1, 40 do parts[#parts + 1] = "Paragraph " .. k end
    local r = editor(table.concat(parts, "\n\n"), false)
    check(r.top > 0 and r.total_h > r.height, "a long note opens scrolled to its end (the cursor in view)")
    r:onSwipeEdit(nil, { direction = "south", pos = { x = 1, y = 1 } })
    local up = r.top
    r:onSwipeEdit(nil, { direction = "north", pos = { x = 1, y = 1 } })
    check(up < r.top or r.top == 0, "swipe down / up scrolls")
    r:moveCursorToCharPos(1)
    check(r.top == 0 and r.cur.b == block(r, 1), "the cursor at the top: scrolled to it")
end

-- ------------------------------------------------------------ the keyboard's other keys
do
    local r = editor("one two three", false)
    r:delWord()
    check(Blocks.plain(block(r, 1)) == "one two ", "delete word")
    r:delToStartOfLine()
    check(text(r) == "", "delete to the line's start")
    r:addChars("ab")
    r:leftChar(); r:leftChar(); r:leftChar()
    check(r.cur.i == 1, "← stops at the start")
    r:rightChar(); r:rightChar(); r:rightChar()
    check(r.cur.i == 3, "→ stops at the end")
    check(r:getChar(-1) == "b", "the character before the cursor (ZenOS' double space)")
    r:onCloseKeyboard()
    check(not r.keyboard:isVisible(), "the keyboard hides")
end

-- ------------------------------------------------------------ random editing reads back as edited
do
    math.randomseed(tonumber(os.getenv("GZ_SEED") or "") or 7)
    local words = { "milk", "the", "a", "*", "_", "#tag", "x_y", "1.", "-", "[ ]", "<b>", "&amp;", "`c`", "\\", "  ", "~" }
    local tools = { "heading", "bullet", "task", "ordered", "bold", "italic" }
    local bad, sessions = nil, 400
    for n = 1, sessions do
        local r = editor("", true)
        for _step = 1, 25 do
            local op = math.random(10)
            if op <= 4 then r:addChars(words[math.random(#words)] .. (math.random(2) == 1 and " " or ""))
            elseif op == 5 then r:addChars("\n")
            elseif op == 6 then r:delChar()
            elseif op == 7 then r:useTool(tools[math.random(#tools)])
            elseif op == 8 then r:moveCursorToCharPos(math.random(#r.charlist + 1))
            else
                -- a selection between two random places
                local a = math.random(#r.charlist + 1)
                r:moveCursorToCharPos(a)
                local p = { b = r.cur.b, i = r.cur.i }
                r:moveCursorToCharPos(math.random(#r.charlist + 1))
                r.anchor = p
                if math.random(2) == 1 then r:useTool(tools[math.random(#tools)]) else r:addChars("z") end
            end
        end
        -- what Save writes reads back as the same lines, kinds and marks
        local md = Blocks.write(r.doc)
        local back = Blocks.parse(md)
        local function sig(doc)
            -- (empty lines at the end aren't written, as in Memos)
            local last = #doc.blocks
            while last > 0 and doc.blocks[last].kind == "paragraph" and #doc.blocks[last].chars == 0 do last = last - 1 end
            local out = {}
            for k = 1, last do
                local b = doc.blocks[k]
                local ms = {}
                for c = 1, #b.chars do
                    -- (bold or italic on a space next to a marker isn't kept: Memos moves it outside)
                    local m = not b.chars[c]:match("^%s$") and b.marks[c]
                    ms[c] = m and ((m.b and "b" or "") .. (m.i and "i" or "")) or ""
                end
                out[#out + 1] = b.kind .. (b.level or "") .. (b.done and "x" or "") .. ":" .. table.concat(b.chars) .. "|" .. table.concat(ms, ",")
            end
            return table.concat(out, "\n")
        end
        local s1, s2 = sig(r.doc), sig(back)
        if s1 ~= s2 then bad = { n = n, md = md, s1 = s1, s2 = s2 }; break end
    end
    check(bad == nil, ("%d random editing sessions (typing, Enter, ⌫, the toolbar, selections) read back as edited"):format(sessions)
        .. (bad and ("\n#" .. bad.n .. " " .. show(bad.md) .. "\n  edited: " .. show(bad.s1) .. "\n  read:   " .. show(bad.s2)) or ""))
end

do
    local r = editor("old", false)
    r:setText("# New\n\n- [ ] item")
    check(text(r) == "# New\n\n- [ ] item" and r.cur.b == block(r, 2) and r.cur.i == 5, "setText: the whole note replaced, the cursor at its end")
end

-- ------------------------------------------------------------ the formatting bar at the selection
do
    print("== the formatting bar comes up at the selection (hold), as in Memos' web editor")
    local r = editor("Pack the tent and the maps.\n\nsecond line here\n\n&nbsp;")
    local function line(k) for _i, l in ipairs(r.lines) do if l.b == block(r, k) then return l end end end
    check(r:barRect() == nil and r:barToolAt(20, 20) == nil, "no bar while typing")
    local l1 = line(1)
    r:onHoldEdit(nil, ges(l1.x0 + 10 * 10 + 5, l1.y + 5))
    local rect = r:barRect()
    check(rect ~= nil and r.bar_open == true, "hold a word: it's selected and the bar comes up")
    check(rect.y >= l1.y + l1.h and rect.x >= 0 and rect.x + rect.w <= r.width and rect.w == rect.cell * #RE.BAR,
        "…under the line when there's no room above it, inside the page")
    local ids = {}
    for i, t in ipairs(RE.BAR) do ids[i] = t.id end
    check(table.concat(ids, ",") == "bold,italic,heading,bullet,task,ordered,tag", "its buttons: B, I, H, list, checklist, numbered, tag")
    r:onHoldPanEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    r:onHoldReleaseEdit(nil, ges(l1.x0 + 10 * 26, l1.y + 5))
    check(r.bar_open == true and r:selection() ~= nil, "drag for more: the bar stays")
    rect = r:barRect()
    local function barPoint(i) return ges(rect.x + (i - 1) * rect.cell + 5, rect.y + 5) end
    check(r:barToolAt(rect.x + 5, rect.y + 5).id == "bold" and r:barToolAt(rect.x + rect.w - 2, rect.y + 5).id == "tag"
        and r:barToolAt(rect.x + 5, rect.y + rect.h + 3) == nil, "a point on the bar is its button; beside it, none")
    r:onTapEdit(nil, barPoint(1))
    check(text(r):match("Pack the %*%*tent and the maps%*%*%.") ~= nil and r.bar_open == true and r:selection() ~= nil,
        "tap B on the bar: the selection bold, the bar and the selection still there … " .. show(text(r)))
    check(r:toolOn("bold") == true and r:toolOn("italic") == false and r:toolOn("heading") == false, "…B shown as on")
    r:onTapEdit(nil, barPoint(2))
    check(text(r):match("%*%*%*tent and the maps%*%*%*") ~= nil or text(r):match("_") ~= nil or text(r):match("%*%*%*") ~= nil,
        "…then I: bold and italic … " .. show(text(r)))
    r:onHoldEdit(nil, barPoint(3))
    check(r:selection() ~= nil and r.bar_open == true, "a hold on the bar itself changes nothing")
    r:onTapEdit(nil, barPoint(3))
    check(block(r, 1).kind == "heading" and r.bar_open == true, "H on the bar: the selection's line a heading")
    -- a tap on the text puts it away
    rect = r:barRect()
    r:onTapEdit(nil, ges(25, rect.y + rect.h + 60))
    check(r.bar_open == nil and r:barRect() == nil and r:selection() == nil, "a tap on the text: the bar goes away, the cursor there")
    local l2 = line(2)
    -- typing puts it away
    r:onHoldEdit(nil, ges(l2.x0 + 25, l2.y + 5))
    r:onHoldReleaseEdit(nil, ges(l2.x0 + 25, l2.y + 5))
    local hp, hq = r:selection()
    check(r.bar_open == true and hp and hp.i == 1 and hq.i == 7, "hold again (no drag): the bar again, the whole word still chosen when the finger lifts inside it")
    r:addChars("x")
    check(r.bar_open == nil, "typing puts it away")
    -- an empty line: the bar for the line itself
    local l3 = line(3)
    r:onHoldEdit(nil, ges(5, l3.y + 5))
    r:onHoldReleaseEdit(nil, ges(5, l3.y + 5))
    check(r.bar_open == true and r:selection() == nil, "hold an empty line: the bar, with nothing selected")
    rect = r:barRect()
    check(rect.y + rect.h <= line(3).y - r.top, "…above the line when there's room")
    r:onTapEdit(nil, barPoint(5))
    check(block(r, 3).kind == "task" and r.bar_open == true, "…its checklist button makes the line a checklist item")
    r:onTapEdit(nil, barPoint(7))
    check(r.editor.tag_asked == true, "# on the bar asks for a tag")
    -- arrows put it away
    r.bar_open = true
    r:leftChar()
    check(r.bar_open == nil, "moving the cursor puts it away")
    -- painted: its labels
    r:onHoldEdit(nil, ges(l2.x0 + 25, line(2).y + 5))
    drawn = {}
    local rects = 0
    r:paintTo({ paintRect = function() rects = rects + 1 end, paintRoundedRect = function() rects = rects + 1 end, paintBorder = function() rects = rects + 1 end }, 0, 0)
    local labels = {}
    for _i, d in ipairs(drawn) do labels[d.text] = true end
    check(labels["B"] and labels["I"] and labels["H"] and labels["1."] and labels["#"], "painted with the page: B I H … 1. #")
end

-- ------------------------------------------------------------ lined paper (a journal entry)
do
    local r = editor("", true)
    local told = 0
    r.on_show_keyboard = function() told = told + 1 end
    r:onShowKeyboard()
    check(told == 1 and r.keyboard.visible, "the keyboard coming up is told (a journal entry makes room for it)")
    r:setHeight(240)
    check(r.height == 240 and r.dimen.h == 240, "a new height when the page around it is laid out again")
    local rules = RE.rules(26, 0, 100)
    check(#rules == 3 and rules[1] == 25 and rules[3] == 77, "lined paper: a rule under each line, the text's line height apart")
    rules = RE.rules(26, 30, 100)
    check(rules[1] == 21 and #rules == 4, "…scrolled, the rules move with the words")
    r.ruled = true
    local lines_drawn = 0
    r:paintTo({ paintRect = function(_b, _x, _y, _w, h) if h == 1 then lines_drawn = lines_drawn + 1 end end,
        paintRoundedRect = function() end, paintBorder = function() end }, 0, 0)
    check(lines_drawn >= 8, "a ruled page paints its rules (" .. lines_drawn .. ")")
end

print(("richedit: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
