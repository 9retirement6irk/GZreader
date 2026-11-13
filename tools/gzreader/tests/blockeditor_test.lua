-- The note editor's block mode (gzreader_blockeditor.lua), on touch Kindles:
-- typing, Enter, Backspace at a block's start, the toolbar, ticking, tags,
-- what Save writes, and the list of blocks drawn (KOReader's widgets stubbed).
--   luajit blockeditor_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

-- ------------------------------------------------------------ stubs
local scheduled = {}
local dirty = 0
local function class(base)
    local c = base and setmetatable({}, { __index = base }) or {}
    c.__index = c
    function c:extend(o) o = o or {}; setmetatable(o, { __index = self }); o.__index = o; return o end
    function c:new(o)
        o = o or {}
        setmetatable(o, self)
        if o.init then o:init() end
        return o
    end
    function c:getSize() return { w = self.width or 100, h = self.height or 20 } end
    function c:free() self.freed = true end
    function c:clear() for k = #self, 1, -1 do self[k] = nil end end
    return c
end
local Widget = class()
local function textHeight(self)
    local n = #(self.text or "")
    local per = math.max(1, math.floor((self.width or 400) / 10))
    return 30 * math.max(1, math.ceil(n / per))
end
local TextBox = class(Widget)
function TextBox:getSize() return { w = self.width, h = textHeight(self) } end
local Frame = class(Widget)
function Frame:getSize()
    assert(self[1], "a FrameContainer needs something in it") -- (as KOReader's)
    local inner = self[1]:getSize()
    return { w = self.width or inner.w, h = self.height or (inner.h + 2 * (self.padding or 0)) }
end
local Group = class(Widget)
function Group:getSize()
    local h, w = 0, 0
    for _i, c in ipairs(self) do local s = c:getSize(); h = h + s.h; w = math.max(w, s.w) end
    return { w = w, h = h }
end
local HGroup = class(Widget)
function HGroup:getSize()
    local h, w = 0, 0
    for _i, c in ipairs(self) do local s = c:getSize(); w = w + s.w; h = math.max(h, s.h) end
    return { w = w, h = h }
end
local Span = class(Widget)
function Span:getSize() return { w = self.width or 0, h = self.width or 0 } end
local Input = class(Widget)
function Input:getSize() return self.dimen or { w = 0, h = 0 } end
local Geom = { new = function(_s, o) return o end }

local function stub(name, v) package.preload[name] = function() return v end end
stub("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1, COLOR_GRAY = 2, COLOR_DARK_GRAY = 3 })
stub("device", { screen = { scaleBySize = function(_s, n) return n end, getHeight = function() return 1448 end,
    getWidth = function() return 1072 end } })
stub("ui/font", { getFace = function(_s, name, size) return { name = name, size = size } end })
stub("ui/widget/container/framecontainer", Frame)
stub("ui/geometry", Geom)
stub("ui/gesturerange", { new = function(_s, o) return o end })
stub("ui/widget/horizontalgroup", HGroup)
stub("ui/widget/horizontalspan", Span)
stub("ui/widget/container/inputcontainer", Input)
local Line = class(Widget)
function Line:getSize() return self.dimen end
stub("ui/widget/linewidget", Line)
stub("ui/size", { border = { thick = 2, thin = 1 } })
stub("ui/widget/textboxwidget", TextBox)
stub("ui/widget/textwidget", TextBox)
stub("ui/uimanager", { setDirty = function() dirty = dirty + 1 end,
    scheduleIn = function(_s, _t, fn) scheduled[#scheduled + 1] = fn end })
stub("ui/widget/verticalgroup", Group)
stub("ui/widget/verticalspan", Span)
stub("gettext", function(s) return s end)
-- (no MuPDF here: blocks with bold or italic fall back to plain text)
package.preload["ui/widget/htmlboxwidget"] = function() error("no mupdf") end

local Blocks = require("gzreader_blocks")
local BE = require("gzreader_blockeditor")

local function chars(s) return Blocks.chars(s) end

-- the text box under the blocks, as InputText behaves
local function fakeInput()
    local inp = { text = "", charpos = 1 }
    function inp:getText() return self.text end
    function inp:setText(t) self.text = t; self.charpos = math.min(self.charpos, #chars(t) + 1) end
    function inp:moveCursorToCharPos(p) self.charpos = p end
    function inp:addChars(s)
        if self.enter_callback and s == "\n" then return self.enter_callback() end
        local c = chars(self.text)
        local add = chars(s)
        for k = #add, 1, -1 do table.insert(c, self.charpos, add[k]) end
        self.text = table.concat(c)
        self.charpos = self.charpos + #add
        if self.edit_callback then self.edit_callback(true) end
    end
    function inp:delChar() -- (the editor's Box: at the start of a block, join)
        if self.charpos == 1 then return BE.onBackspaceAtStart(self.editor) end
        local c = chars(self.text)
        table.remove(c, self.charpos - 1)
        self.text = table.concat(c)
        self.charpos = self.charpos - 1
        if self.edit_callback then self.edit_callback(true) end
    end
    return inp
end

local function editor(content, is_new)
    local e = { inner = 1000, blocks_h = 600, block_slot = Group:new{} }
    e.doc = BE.document(content)
    e.cur = BE.startBlock(e.doc, is_new)
    e.input = fakeInput()
    e.input.editor = e
    e.input.enter_callback = function() BE.onEnter(e) end
    e.input.edit_callback = function(ed) BE.onEdit(e, ed) end
    e.input.text = Blocks.plain(e.cur)
    e.input.charpos = #e.cur.chars + 1
    function e:pickTag(pos) self.tag_asked = pos end
    return e
end
local function typeText(e, s) for _i, ch in ipairs(chars(s)) do e.input:addChars(ch) end end
local function flush() local f = scheduled; scheduled = {}; for _i, fn in ipairs(f) do fn() end end
local function kinds(e)
    local out = {}
    for _i, b in ipairs(e.doc.blocks) do out[#out + 1] = b.kind end
    return table.concat(out, ",")
end

-- ------------------------------------------------------------ a new note
do
    local e = editor("", true)
    check(#e.doc.blocks == 1 and e.cur.kind == "paragraph" and BE.text(e) == "", "a new note: one empty paragraph; nothing to save yet")
    BE.useTool(e, "heading")
    check(e.cur.kind == "heading" and e.cur.level == 1, "Head: heading 1")
    typeText(e, "Shopping")
    check(BE.text(e) == "# Shopping", "typed into the heading: '# Shopping' (no markers typed) … " .. BE.text(e))
    e.input:addChars("\n")
    check(kinds(e) == "heading,paragraph" and e.input.text == "" and e.input.charpos == 1, "Enter after a heading: a paragraph")
    BE.useTool(e, "task")
    typeText(e, "milk")
    e.input:addChars("\n")
    typeText(e, "eggs & *ham*")
    check(kinds(e) == "heading,task,task", "Enter in a checklist: the next item")
    check(BE.text(e) == "# Shopping\n\n- [ ] milk\n- [ ] eggs & \\*ham\\*",
        "Markdown as Memos writes it: tight list, stars escaped, & kept … " .. BE.text(e):gsub("\n", "\\n"))
    e.input:addChars("\n")
    e.input:addChars("\n") -- (Enter on an empty item: the list ends)
    check(kinds(e) == "heading,task,task,paragraph" and e.cur.kind == "paragraph", "Enter on an empty item ends the list")
    typeText(e, "Thanks")
    check(BE.text(e) == "# Shopping\n\n- [ ] milk\n- [ ] eggs & \\*ham\\*\n\nThanks", "then a paragraph after the list")
    -- tick the first item by tapping its box
    BE.render(e)
    local items = {}
    local function collect(w)
        for _i, c in ipairs(w) do
            if c.block then items[#items + 1] = c elseif type(c) == "table" then collect(c) end
        end
    end
    collect(e.block_slot)
    check(#items == 4, "all four blocks drawn")
    local milk = items[2]
    milk.dimen.x, milk.dimen.y = 12, 100
    milk:onTapBlock(nil, { pos = { x = 20, y = 110 } })
    check(e.doc.blocks[2].done == true and e.cur.kind == "paragraph", "tapping a task's box ticks it (the block edited stays the same)")
    check(BE.text(e):match("%- %[x%] milk"), "ticked: '- [x] milk'")
    items = {}
    collect(e.block_slot)
    local eggs = items[3]
    eggs.dimen.x, eggs.dimen.y = 12, 140
    eggs:onTapBlock(nil, { pos = { x = 400, y = 150 } })
    check(e.cur == e.doc.blocks[3] and e.input.text == "eggs & *ham*" and e.input.charpos == 13,
        "tapping a block's words: it's edited, its words (no markers) in the box, the cursor at the end")
    check(e.doc.blocks[4].chars[1] == "T" and Blocks.plain(e.doc.blocks[4]) == "Thanks", "…the block left keeps what was typed in it")
end

-- ------------------------------------------------------------ an edit of a Memos note
do
    local note = "## Plan\n\nFirst **bold** paragraph.\n\n&nbsp;\n\n1. one\n2. two\n\n```\ncode\n```\n\n#travel"
    local e = editor(note, false)
    check(BE.text(e) == note, "opened and saved untouched: exactly as it was")
    check(kinds(e) == "heading,paragraph,paragraph,ordered,ordered,raw,paragraph",
        "the blocks: heading, paragraph, the &nbsp; line (an empty paragraph), the numbered list, code kept as it is, the tags … " .. kinds(e))
    check(e.cur == e.doc.blocks[7] and e.input.text == "#travel", "edit: the cursor at the end of the note's last words")
    check(Blocks.plain(e.doc.blocks[3]) == "" and Blocks.isEmptyParagraph(e.doc.blocks[3]), "no '&nbsp;' to see: an empty line")
    -- edit the bold paragraph: its words, marks kept
    BE.select(e, e.doc.blocks[2])
    check(e.input.text == "First bold paragraph.", "a bold word: shown without ** in the box")
    e.input.charpos = 9
    typeText(e, "XX")
    check(BE.text(e):match("First %*%*boXXld%*%* paragraph%.") ~= nil,
        "typed inside the bold word: bold too … " .. BE.text(e):match("[^\n]*paragraph[^\n]*"))
    e.input.charpos = 7
    typeText(e, "very ")
    check(BE.text(e):match("First very %*%*boXXld%*%*") ~= nil, "typed just before it: not bold (as in Memos)")
    check(BE.text(e):match("^## Plan\n\nFirst") and BE.text(e):match("1%. one\n2%. two\n\n```\ncode\n```\n\n#travel$"),
        "the rest written back as it was")
    -- Backspace at the start of the second item: it becomes a paragraph, then joins
    BE.select(e, e.doc.blocks[5], 1)
    e.input:delChar()
    check(e.doc.blocks[5].kind == "paragraph" and e.input.text == "two", "Backspace at an item's start: a paragraph first")
    e.input:delChar()
    check(kinds(e) == "heading,paragraph,paragraph,ordered,raw,paragraph" and e.cur == e.doc.blocks[4]
        and e.input.text == "onetwo" and e.input.charpos == 4, "Backspace again: joined to the item before, the cursor between")
    -- numbered list: Num again turns it into text; delete a block
    BE.useTool(e, "ordered")
    check(e.cur.kind == "paragraph", "Num on a numbered item: back to text")
    local before = #e.doc.blocks
    BE.useTool(e, "delete")
    check(#e.doc.blocks == before - 1 and e.cur == e.doc.blocks[4] and e.cur.kind == "raw" and e.input.text == "```\ncode\n```",
        "⌫ Block: deleted; the next block edited (code: as Markdown)")
    -- Enter in a code block: a new line in it
    e.input.charpos = 9
    e.input:addChars("\n")
    check(#e.doc.blocks == before - 1 and e.input.text == "```\ncode\n\n```", "Enter in code: a new line, not a new block")
    flush()
    check(BE.text(e):match("```\ncode\n\n```"), "…written as typed")
end

-- ------------------------------------------------------------ the toolbar
do
    local e = editor("make it bold", false)
    e.input.charpos = 10
    BE.useTool(e, "bold")
    check(BE.text(e) == "make it **bold**", "B: the word at the cursor … " .. BE.text(e))
    BE.useTool(e, "bold")
    check(BE.text(e) == "make it bold", "B again: off")
    e.input.charpos = 3
    BE.useTool(e, "italic")
    check(BE.text(e) == "*make* it bold", "I: the word at the cursor")
    BE.useTool(e, "heading"); BE.useTool(e, "heading"); BE.useTool(e, "heading")
    check(e.cur.kind == "heading" and e.cur.level == 3 and BE.text(e) == "### *make* it bold", "Head three times: heading 3")
    BE.useTool(e, "heading")
    check(e.cur.kind == "paragraph", "…a fourth: text again")
    BE.useTool(e, "bullet")
    check(BE.text(e) == "- *make* it bold", "List: a bullet")
    BE.useTool(e, "tag")
    check(e.tag_asked ~= nil, "# Tag: asks which tag")
    e.input.charpos = #chars(e.input.text) + 1
    BE.insertTag(e, "ideas")
    check(BE.text(e) == "- *make* it bold #ideas", "the tag at the cursor, a space before it … " .. BE.text(e))
end

-- ------------------------------------------------------------ typing and redraws
do
    local e = editor("abc", false)
    flush()
    dirty = 0
    typeText(e, "def")
    check(#scheduled == 1, "a burst of keys: one redraw waiting, not one per key")
    flush()
    check(dirty >= 1 and BE.text(e) == "abcdef", "…then the block shows what was typed")
    e.closed_be = true
    typeText(e, "g")
    dirty = 0
    flush()
    check(dirty == 0, "closed: no redraw after")
end

-- ------------------------------------------------------------ a long note: the edited block stays in sight
do
    local lines = {}
    for k = 1, 40 do lines[#lines + 1] = "Paragraph number " .. k .. " " .. string.rep("words ", 10) end
    local e = editor(table.concat(lines, "\n\n"), false)
    e.blocks_h = 300
    BE.render(e)
    local shown = {}
    local function collect(w)
        for _i, c in ipairs(w) do
            if c.block then shown[#shown + 1] = c.block elseif type(c) == "table" then collect(c) end
        end
    end
    collect(e.block_slot)
    check(shown[#shown] == e.doc.blocks[40] and #shown < 40 and e.block_top > 1,
        "the last block edited: the list starts further down so it shows (" .. #shown .. " shown from " .. e.block_top .. ")")
    BE.select(e, e.doc.blocks[1])
    shown = {}
    collect(e.block_slot)
    check(shown[1] == e.doc.blocks[1] and e.block_top == 1, "the first edited: the list from the top")
end

-- ------------------------------------------------------------ shown as Memos shows it
do
    check(BE.prefix({ kind = "task", done = true }) == "\u{2611}" and BE.prefix({ kind = "task" }) == "\u{2610}"
        and BE.prefix({ kind = "bullet" }) == "\u{2022}" and BE.prefix({ kind = "ordered" }, 3) == "3."
        and BE.prefix({ kind = "paragraph" }) == nil, "markers shown: ☐ ☑ • 3.")
    local doc = BE.document("# Big\n\n## Smaller\n\ntext")
    local w1 = BE.blockWidget(doc.blocks[1], 500)
    local w3 = BE.blockWidget(doc.blocks[3], 500)
    check(w1.face.size > w3.face.size and w1.bold and not w3.bold, "headings bigger and bold")
    local hidden = BE.blockWidget(BE.document("&nbsp;").blocks[1], 500)
    check(hidden.text == nil, "an &nbsp; line: a gap, no text")
end

print(("blockeditor: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
