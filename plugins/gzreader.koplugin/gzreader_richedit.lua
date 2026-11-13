--[[--
The note editor's page on touch Kindles: the note formatted, as Memos' web
editor shows it, typed into directly (no Markdown to see).

- Tap: the cursor goes there (tap a checklist item's ☐ to tick it).
- Hold a word: it's selected; drag to stretch the selection over words,
  lines and paragraphs. Typing replaces it; ⌫ deletes it.
- The toolbar acts on the selection, or on the cursor's line or word:
  Head (heading 1 → 2 → 3 → text), List / Check / Num (again: text),
  B / I (bold, italic: the selection, the word at the cursor, or what's
  typed next).
- Enter starts a new line (the next item in a list; Enter on an empty item
  ends the list); ⌫ at a line's start joins it to the line before.
- Swipe up or down: scroll a long note.
- Code, quotes, tables and pictures show as their Markdown in grey and edit
  as text.

The note is kept as `gzreader_blocks.lua`'s blocks (one per line on the
screen) and written back as Memos' rich editor writes it. For the on-screen
keyboard the widget is an input box: addChars, delChar, leftChar, … and a
flat `charlist` / `charpos` (blocks joined by line breaks), so ZenOS's
space-bar cursor works too.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local Blocks = require("gzreader_blocks")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local RichEdit = InputContainer:extend{
    width = nil,
    max_height = nil, -- the page's room; the keyboard's height is taken off it
    doc = nil,
    editor = nil, -- the note editor (# Tag asks it)
    at_start = false, -- the cursor at the start (a new note), else at the end
    hint = nil,
    on_change = nil,
    gz_multiline = true, -- (the on-screen keyboard keeps Enter and ← →)
    focused = true,
}

RichEdit.TEXT_SIZE = 20
RichEdit.HEADING_SIZE = { 28, 24, 22, 21, 20, 20 }
RichEdit.MONO_SIZE = 16

-- ------------------------------------------------------------ faces, widths

local FACES = {}
--- The face for `size` and bold / italic / mono.
function RichEdit.face(size, bold, italic, mono)
    local key = size .. (bold and "b" or "") .. (italic and "i" or "") .. (mono and "m" or "")
    local f = FACES[key]
    if f then return f end
    local name
    if mono then name = "infont"
    elseif bold and italic then name = "NotoSans-BoldItalic.ttf"
    elseif bold then name = "NotoSans-Bold.ttf"
    elseif italic then name = "NotoSans-Italic.ttf"
    else name = "cfont" end
    f = Font:getFace(name, size) or Font:getFace("cfont", size)
    FACES[key] = f
    return f
end

local WIDTHS = setmetatable({}, { __mode = "k" })
local function advance(face, ch)
    local t = WIDTHS[face]
    if not t then t = {}; WIDTHS[face] = t end
    local w = t[ch]
    if not w then
        if ch == "\n" then w = 0
        else w = RenderText:sizeUtf8Text(0, 100000, face, ch, false, false).x end
        t[ch] = w
    end
    return w
end

local function lineMetrics(face)
    local lh = math.floor((1.3 * face.size) + 0.5)
    local fh, asc = face.ftsize:getHeightAndAscender()
    local diff = math.floor(lh - fh)
    return lh, math.floor(asc + math.max(0, diff) / 2)
end

-- ------------------------------------------------------------ layout

--- How a block looks: its text size, bold, its marker and the gutter for it.
function RichEdit.style(b, num)
    if b.kind == "heading" then
        return { size = RichEdit.HEADING_SIZE[b.level or 1] or 20, bold = true }
    elseif b.kind == "raw" or b.kind == "image" then
        return { size = RichEdit.MONO_SIZE, mono = true, color = Blitbuffer.COLOR_DARK_GRAY }
    end
    local st = { size = RichEdit.TEXT_SIZE }
    if b.kind == "bullet" then st.prefix = "\u{2022}"
    elseif b.kind == "task" then st.prefix = b.done and "\u{2611}" or "\u{2610}"
    elseif b.kind == "ordered" then st.prefix = tostring(num or b.num or 1) .. "." end
    if b.kind == "task" and b.done then st.color = Blitbuffer.COLOR_DARK_GRAY end
    return st
end

--- The face for character `k` of `b` in style `st`.
local function charFace(b, k, st)
    local m = b.marks[k]
    if st.mono then return RichEdit.face(st.size, false, false, true) end
    if m and m.c then return RichEdit.face(RichEdit.MONO_SIZE, false, false, true) end
    return RichEdit.face(st.size, st.bold or (m and m.b), m and m.i)
end

--- Lays the note out `width` wide: the screen lines, each
--- { b, a, z, y, h, base, x0, xs (x of positions a … z+1), first, last, st }.
function RichEdit.layout(doc, width)
    local lines = {}
    local y = 0
    local prev, prev_num
    for _k, b in ipairs(doc.blocks) do
        local num
        if b.kind == "ordered" then
            num = (prev and prev.kind == "ordered" and (prev.indent or "") == (b.indent or "")) and ((prev_num or 1) + 1) or (b.num or 1)
        end
        local st = RichEdit.style(b, num)
        -- space between blocks: less inside a list
        if prev then
            local same_list = prev.kind == b.kind and (b.kind == "bullet" or b.kind == "task" or b.kind == "ordered")
            y = y + (same_list and S(2) or S(8))
        end
        local base_face = RichEdit.face(st.size, st.bold, false, st.mono)
        local lh, base = lineMetrics(base_face)
        local indent = S(28) * math.floor(#(b.indent or "") / 2)
        local gutter = (b.kind == "bullet" or b.kind == "task" or b.kind == "ordered") and S(40) or 0
        local x0 = indent + gutter
        local maxw = math.max(S(40), width - x0)
        local chars = b.chars
        local n = #chars
        local w = {}
        for k = 1, n do w[k] = advance(charFace(b, k, st), chars[k]) end
        local function push(a, z)
            local xs, x = {}, x0
            for k = a, z do xs[#xs + 1] = x; x = x + w[k] end
            xs[#xs + 1] = x
            lines[#lines + 1] = { b = b, a = a, z = z, y = y, h = lh, base = base, x0 = x0, xs = xs, st = st, w = w,
                first = a == 1, num = num }
            y = y + lh
        end
        local ls = 1
        while ls <= n do
            local x, k, brk = 0, ls, nil
            while k <= n do
                if chars[k] == "\n" then break end
                -- (a space may hang past the edge: the line breaks after it)
                if x + w[k] > maxw and k > ls and chars[k] ~= " " then break end
                x = x + w[k]
                if chars[k] == " " then brk = k end
                k = k + 1
            end
            local le
            if k > n then le = n
            elseif chars[k] == "\n" then le = k
            elseif brk then le = brk
            else le = k - 1 end
            push(ls, le)
            ls = le + 1
        end
        if n == 0 or chars[n] == "\n" then push(n + 1, n) end
        lines[#lines].last = true
        prev, prev_num = b, num
    end
    return lines, y
end

--- The screen line holding position `p` ({ b, i }) and its x.
function RichEdit.lineOf(lines, p)
    local found
    for li, l in ipairs(lines) do
        if l.b == p.b then
            local hi = l.z
            -- a line's own end: after its last character, unless that's a
            -- break (a wrapped space or a line break: the next line starts there)
            if l.last then hi = l.z + 1
            elseif l.b.chars[l.z] == "\n" then hi = l.z end
            if p.i >= l.a and p.i <= hi then return li, l.xs[p.i - l.a + 1] or l.xs[#l.xs] end
            found = found or li
        end
    end
    if found then return found, lines[found].x0 end
end

--- The position nearest to x on screen line `l`.
function RichEdit.posIn(l, x)
    local hi = l.z
    if l.last then hi = l.z + 1 elseif l.b.chars[l.z] == "\n" then hi = l.z end
    local best, bd = l.a, math.huge
    for i = l.a, math.max(l.a, hi) do
        local xi = l.xs[i - l.a + 1]
        if xi then
            local d = math.abs(xi - x)
            if d < bd then best, bd = i, d end
        end
    end
    return { b = l.b, i = best }
end

-- ------------------------------------------------------------ the widget

function RichEdit:init()
    self.lines = {}
    local VirtualKeyboard = require("ui/widget/virtualkeyboard")
    self.keyboard = VirtualKeyboard:new{ keyboard_layer = 2, inputbox = self }
    local kb_h = self.keyboard.dimen and self.keyboard.dimen.h or math.floor(Screen:getHeight() * 0.4)
    self.height = math.max(S(80), (self.max_height or Screen:getHeight()) - kb_h)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.top = 0
    if #self.doc.blocks == 0 then self.doc.blocks[1] = Blocks.new("paragraph") end
    local b
    if self.at_start then b = self.doc.blocks[1]
    else
        -- the end of the note's last words
        for k = #self.doc.blocks, 1, -1 do
            local x = self.doc.blocks[k]
            if x.kind ~= "raw" and x.kind ~= "image" and #x.chars > 0 then b = x; break end
        end
        b = b or self.doc.blocks[#self.doc.blocks]
    end
    self.cur = { b = b, i = #b.chars + 1 }
    self.anchor = nil
    self.ges_events = {
        TapEdit = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        HoldEdit = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
        HoldPanEdit = { GestureRange:new{ ges = "hold_pan", range = function() return self.dimen end } },
        HoldReleaseEdit = { GestureRange:new{ ges = "hold_release", range = function() return self.dimen end } },
        SwipeEdit = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    self:relayout()
    self:keepCursorInView()
end

function RichEdit:getSize() return self.dimen end

--- Lays out again after a change (and the flat text for the keyboard).
function RichEdit:relayout()
    self.lines, self.total_h = RichEdit.layout(self.doc, self.width)
    local list, pos = {}, nil
    for k, b in ipairs(self.doc.blocks) do
        if k > 1 then list[#list + 1] = "\n" end
        if b == self.cur.b then pos = #list + self.cur.i end
        for _i, ch in ipairs(b.chars) do list[#list + 1] = ch end
    end
    self.charlist, self.charpos = list, pos or (#list + 1)
end

--- Keeps the cursor's line on screen (scrolling as little as needed).
function RichEdit:keepCursorInView()
    local li = RichEdit.lineOf(self.lines, self.cur)
    local l = li and self.lines[li]
    if not l then return end
    if l.y < self.top then self.top = l.y
    elseif l.y + l.h > self.top + self.height then self.top = l.y + l.h - self.height end
    self.top = math.max(0, math.min(self.top, math.max(0, self.total_h - self.height)))
end

--- After an edit or a move: lay out, keep the cursor in view, redraw.
function RichEdit:update(edited)
    self:relayout()
    self:keepCursorInView()
    if edited then
        self.doc.changed = self.doc.changed or edited == "structure"
        if self.on_change then self.on_change() end
    end
    UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
end

--- The selection, in order (nil when there's none).
function RichEdit:selection()
    if not self.anchor then return nil end
    if self.anchor.b == self.cur.b and self.anchor.i == self.cur.i then return nil end
    return Blocks.order(self.doc, self.anchor, self.cur)
end

function RichEdit:setCursor(p, keep_selection)
    self.cur = { b = p.b, i = math.max(1, math.min(p.i, #p.b.chars + 1)) }
    if not keep_selection then self.anchor = nil end
    self.pending = nil
end

--- Deletes the selection, if any. True when it did.
function RichEdit:deleteSelection()
    local p, q = self:selection()
    self.anchor = nil
    if not p then return false end
    self.cur = Blocks.deleteRange(self.doc, p, q)
    return true
end

-- ------------------------------------------------------------ the keyboard's input box

function RichEdit:addChars(chars)
    if type(chars) == "table" then chars = table.concat(chars) end
    if chars == "" then return end
    local structure = self:deleteSelection()
    local b = self.cur.b
    local raw = b.kind == "raw" or b.kind == "image"
    local start = 1
    while start <= #chars do
        local nl = chars:find("\n", start, true)
        local piece = chars:sub(start, (nl or (#chars + 1)) - 1)
        if piece ~= "" then
            self.cur.i = Blocks.insert(self.cur.b, self.cur.i, piece, self.pending)
        end
        if nl then
            if raw then
                self.cur.i = Blocks.insert(self.cur.b, self.cur.i, "\n")
            else
                local nb = Blocks.split(self.doc, self.cur.b, self.cur.i)
                self.cur = { b = nb, i = 1 }
                self.doc.changed = true
                structure = true
            end
            start = nl + 1
        else
            break
        end
    end
    self:update(structure and "structure" or true)
end

function RichEdit:delChar()
    if self:deleteSelection() then return self:update("structure") end
    local b, i = self.cur.b, self.cur.i
    if i > 1 then
        Blocks.delete(b, i - 1, i - 1)
        self.cur.i = i - 1
        return self:update(true)
    end
    local to, at = Blocks.joinPrevious(self.doc, b)
    if to then
        self.cur = { b = to, i = at }
        self.doc.changed = true
        return self:update("structure")
    end
end

function RichEdit:delWord()
    if self:deleteSelection() then return self:update("structure") end
    local b, i = self.cur.b, self.cur.i
    if i == 1 then return self:delChar() end
    local a = i - 1
    while a > 1 and b.chars[a] == " " do a = a - 1 end
    while a > 1 and b.chars[a - 1] ~= " " and b.chars[a - 1] ~= "\n" do a = a - 1 end
    Blocks.delete(b, a, i - 1)
    self.cur.i = a
    self:update(true)
end

function RichEdit:delToStartOfLine()
    if self:deleteSelection() then return self:update("structure") end
    local li = RichEdit.lineOf(self.lines, self.cur)
    local l = li and self.lines[li]
    if not l or self.cur.i <= l.a then return self:delChar() end
    Blocks.delete(self.cur.b, l.a, self.cur.i - 1)
    self.cur.i = l.a
    self:update(true)
end

local function blockAt(self, k) return self.doc.blocks[k] end

function RichEdit:leftChar()
    local b, i = self.cur.b, self.cur.i
    if i > 1 then self:setCursor({ b = b, i = i - 1 })
    else
        local prev = blockAt(self, (Blocks.indexOf(self.doc, b) or 1) - 1)
        if prev then self:setCursor({ b = prev, i = #prev.chars + 1 }) else self.anchor = nil end
    end
    self:update()
end

function RichEdit:rightChar()
    local b, i = self.cur.b, self.cur.i
    if i <= #b.chars then self:setCursor({ b = b, i = i + 1 })
    else
        local nxt = blockAt(self, (Blocks.indexOf(self.doc, b) or 0) + 1)
        if nxt then self:setCursor({ b = nxt, i = 1 }) else self.anchor = nil end
    end
    self:update()
end

local function moveLine(self, delta)
    local li, x = RichEdit.lineOf(self.lines, self.cur)
    if not li then return end
    self.want_x = self.want_x or x
    local l = self.lines[li + delta]
    if l then
        local want = self.want_x
        self:setCursor(RichEdit.posIn(l, want))
        self.want_x = want
    end
    self:update()
end
function RichEdit:upLine() moveLine(self, -1) end
function RichEdit:downLine() moveLine(self, 1) end

function RichEdit:goToStartOfLine()
    local li = RichEdit.lineOf(self.lines, self.cur)
    if li then self:setCursor({ b = self.cur.b, i = self.lines[li].a }) end
    self:update()
end

function RichEdit:goToEndOfLine()
    local li = RichEdit.lineOf(self.lines, self.cur)
    local l = li and self.lines[li]
    if l then
        local e = l.z + 1
        if not l.last then e = l.z end
        self:setCursor({ b = self.cur.b, i = e })
    end
    self:update()
end

function RichEdit:scrollDown()
    self.top = math.max(0, math.min(self.top + math.floor(self.height * 0.7), math.max(0, self.total_h - self.height)))
    UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
end

function RichEdit:scrollUp()
    self.top = math.max(0, self.top - math.floor(self.height * 0.7))
    UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
end

--- The character `offset` from the cursor (ZenOS's double space asks for -1).
function RichEdit:getChar(offset)
    return self.cur.b.chars[self.cur.i + (offset or 0)]
end

--- A flat position (blocks joined by line breaks): the space-bar cursor.
function RichEdit:moveCursorToCharPos(n)
    local k = 0
    for _j, b in ipairs(self.doc.blocks) do
        if n <= k + #b.chars + 1 then
            self:setCursor({ b = b, i = n - k })
            return self:update()
        end
        k = k + #b.chars + 1
    end
    local last = self.doc.blocks[#self.doc.blocks]
    self:setCursor({ b = last, i = #last.chars + 1 })
    self:update()
end

function RichEdit:getText() return Blocks.write(self.doc) end
function RichEdit:isTextEdited() return Blocks.write(self.doc) ~= self.doc.original end

function RichEdit:onShowKeyboard()
    if self.keyboard then self.keyboard:showKeyboard() end
    return true
end
function RichEdit:onCloseKeyboard()
    if self.keyboard then self.keyboard:hideKeyboard() end
end
function RichEdit:isKeyboardVisible() return self.keyboard ~= nil and self.keyboard:isVisible() == true end
function RichEdit:getKeyboardDimen() return self.keyboard and self.keyboard.dimen end
function RichEdit:onCloseWidget()
    if self.keyboard then
        self.keyboard:hideKeyboard()
        if self.keyboard.free then self.keyboard:free() end
    end
end

-- ------------------------------------------------------------ the toolbar

--- Head / List / Check / Num: the lines selected, or the cursor's line.
function RichEdit:setKind(kind)
    local p, q = self:selection()
    local list = p and Blocks.span(self.doc, p, q) or { self.cur.b }
    local blocks = {}
    for _i, b in ipairs(list) do if b.kind ~= "raw" and b.kind ~= "image" then blocks[#blocks + 1] = b end end
    if #blocks == 0 then return false end
    if kind == "heading" then
        local first = blocks[1]
        local next_level = (first.kind == "heading" and (first.level or 1) or 0) + 1
        for _i, b in ipairs(blocks) do
            if next_level > 3 then Blocks.setKind(b, "paragraph")
            else b.kind = "paragraph"; Blocks.setKind(b, "heading", next_level) end
        end
    else
        local all = true
        for _i, b in ipairs(blocks) do if b.kind ~= kind then all = false end end
        for _i, b in ipairs(blocks) do
            if all then Blocks.setKind(b, "paragraph")
            elseif b.kind ~= kind then Blocks.setKind(b, kind) end
        end
    end
    self.doc.changed = true
    self:update("structure")
    return true
end

--- B / I: the selection; else the word at the cursor; else what's typed next.
function RichEdit:toggleMark(key)
    local p, q = self:selection()
    if p then
        Blocks.toggleMarkRange(self.doc, p, q, key)
        return self:update(true)
    end
    local b, i = self.cur.b, self.cur.i
    if b.kind == "raw" or b.kind == "image" then return end
    local function word(ch) return ch and not ch:match("^[%s%p]$") end
    if word(b.chars[i]) or word(b.chars[i - 1]) then
        local a, z = Blocks.wordAt(b, i)
        Blocks.toggleMark(b, key, a, z)
        return self:update(true)
    end
    -- nothing to mark: the next characters typed
    local m = self.pending
    if m == nil then m = Blocks.typedMarks(b, i) end
    local f = { b = m and m.b, i = m and m.i, s = m and m.s }
    f[key] = not f[key] or nil
    self.pending = Blocks.markset(f.b, f.i, f.s)
    self:update()
end

--- "#tag" at the cursor (a space before it when needed; after it only when words follow).
function RichEdit:insertTag(tag)
    self:deleteSelection()
    local b, i = self.cur.b, self.cur.i
    local before, after = b.chars[i - 1], b.chars[i]
    local ins = ((before and not before:match("%s")) and " " or "") .. "#" .. tag
        .. ((after and not after:match("%s")) and " " or "")
    self.cur.i = Blocks.insert(b, i, ins, false)
    self:update(true)
end

--- A toolbar button (`id`: heading, bullet, task, ordered, bold, italic, tag).
function RichEdit:useTool(id)
    if id == "bold" then return self:toggleMark("b")
    elseif id == "italic" then return self:toggleMark("i")
    elseif id == "tag" then
        if self.editor and self.editor.pickTag then return self.editor:pickTag() end
        return
    end
    return self:setKind(id)
end

-- ------------------------------------------------------------ touch

--- The position at screen point (x, y) (relative to the widget), and the line.
function RichEdit:posAt(x, y)
    local yy = y + self.top
    local pick
    for _i, l in ipairs(self.lines) do
        if yy < l.y + l.h then pick = l; break end
    end
    pick = pick or self.lines[#self.lines]
    if not pick then return nil end
    return RichEdit.posIn(pick, x), pick
end

local function rel(self, ges)
    return ges.pos.x - (self.dimen.x or 0), ges.pos.y - (self.dimen.y or 0)
end

function RichEdit:onTapEdit(_arg, ges)
    local x, y = rel(self, ges)
    local p, l = self:posAt(x, y)
    if not p then return true end
    -- a checklist item's box: ticks it
    if l and l.first and l.b.kind == "task" and x < l.x0 and y + self.top >= l.y then
        Blocks.toggleDone(l.b)
        self:update("structure")
        return true
    end
    self.want_x = nil
    self:setCursor(p)
    self:update()
    if self.keyboard and not self.keyboard:isVisible() then self:onShowKeyboard() end
    return true
end

function RichEdit:onHoldEdit(_arg, ges)
    local p = self:posAt(rel(self, ges))
    if not p then return true end
    local a, z = Blocks.wordAt(p.b, p.i)
    if a and p.b.kind ~= "raw" and p.b.kind ~= "image" and #p.b.chars > 0 then
        self.anchor = { b = p.b, i = a }
        self.cur = { b = p.b, i = z + 1 }
    else
        self.anchor = { b = p.b, i = p.i }
        self.cur = { b = p.b, i = p.i }
    end
    self.selecting = true
    self.pending = nil
    self:update()
    return true
end

function RichEdit:onHoldPanEdit(_arg, ges)
    if not self.selecting then return false end
    local p = self:posAt(rel(self, ges))
    if p then
        self.cur = p
        self:update()
    end
    return true
end

function RichEdit:onHoldReleaseEdit(_arg, ges)
    if not self.selecting then return false end
    self.selecting = false
    if ges and ges.pos then
        local p = self:posAt(rel(self, ges))
        if p and self.anchor and not (p.b == self.anchor.b and p.i == self.anchor.i) then self.cur = p end
    end
    self:update()
    return true
end

function RichEdit:onSwipeEdit(_arg, ges)
    if ges.direction == "north" then self:scrollDown(); return true end
    if ges.direction == "south" then self:scrollUp(); return true end
    return false
end

-- ------------------------------------------------------------ painting

local function cursorWidth() return math.max(2, S(2)) end

function RichEdit:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local top, h = self.top, self.height
    local p, q = self:selection()
    local doc_empty = #self.doc.blocks == 1 and #self.doc.blocks[1].chars == 0 and self.doc.blocks[1].kind == "paragraph"
    if doc_empty and self.hint then
        local face = RichEdit.face(RichEdit.TEXT_SIZE)
        local base = select(2, lineMetrics(face))
        RenderText:renderUtf8Text(bb, x + S(2), y + base, face, self.hint, false, false, Blitbuffer.COLOR_DARK_GRAY)
    end
    local sel_from, sel_to
    if p then
        sel_from = { k = Blocks.indexOf(self.doc, p.b), i = p.i }
        sel_to = { k = Blocks.indexOf(self.doc, q.b), i = q.i }
    end
    local index = {}
    for k, b in ipairs(self.doc.blocks) do index[b] = k end
    for _li, l in ipairs(self.lines) do
        local ly = l.y - top
        if ly + l.h > 0 and ly < h then
            if ly >= 0 and ly + l.h <= h then
                local st, b = l.st, l.b
                -- the selection's part of this line
                local k = index[b]
                if sel_from and k >= sel_from.k and k <= sel_to.k then
                    local a, z = l.a, l.z + 1
                    local s1 = k == sel_from.k and math.max(a, sel_from.i) or a
                    local s2 = k == sel_to.k and math.min(z, sel_to.i) or z
                    if s2 > s1 then
                        local x1 = l.xs[s1 - a + 1] or l.xs[#l.xs]
                        local x2 = l.xs[s2 - a + 1] or l.xs[#l.xs]
                        bb:paintRect(x + x1, y + ly, math.max(2, x2 - x1), l.h, Blitbuffer.COLOR_LIGHT_GRAY)
                    elseif k > sel_from.k and #b.chars == 0 then -- (an empty line in it)
                        bb:paintRect(x + l.x0, y + ly, S(8), l.h, Blitbuffer.COLOR_LIGHT_GRAY)
                    end
                end
                -- the marker of a list item
                if l.first and st.prefix then
                    local pf = RichEdit.face(b.kind == "task" and (st.size + 2) or st.size)
                    RenderText:renderUtf8Text(bb, x + l.x0 - S(36), y + ly + l.base, pf, st.prefix, false, false,
                        Blitbuffer.COLOR_BLACK)
                end
                -- the words, in runs of the same face
                local c = l.a
                while c <= l.z do
                    local face = charFace(b, c, st)
                    local m = b.marks[c] or false
                    local j = c
                    local parts = {}
                    while j <= l.z and b.chars[j] ~= "\n" and charFace(b, j, st) == face and (b.marks[j] or false) == m do
                        parts[#parts + 1] = b.chars[j]
                        j = j + 1
                    end
                    if #parts > 0 then
                        local x1 = l.xs[c - l.a + 1]
                        local x2 = l.xs[j - l.a + 1]
                        local color = st.color or Blitbuffer.COLOR_BLACK
                        RenderText:renderUtf8Text(bb, x + x1, y + ly + l.base, face, table.concat(parts), false, false, color)
                        if m and m.s then bb:paintRect(x + x1, y + ly + l.base - math.floor(face.size * 0.3), x2 - x1, 1, color) end
                        if m and m.link then bb:paintRect(x + x1, y + ly + l.base + 2, x2 - x1, 1, color) end
                    else
                        j = j + 1
                    end
                    c = j
                end
            end
        end
    end
    -- the cursor
    if not p then
        local li, cx = RichEdit.lineOf(self.lines, self.cur)
        local l = li and self.lines[li]
        if l then
            local ly = l.y - top
            if ly >= 0 and ly + l.h <= h then
                bb:paintRect(x + math.max(0, math.min(self.width - 2, cx)), y + ly + S(2), cursorWidth(), l.h - S(4), Blitbuffer.COLOR_BLACK)
            end
        end
    end
    -- more above / below
    if top > 0 then bb:paintRect(x, y, self.width, 1, Blitbuffer.COLOR_DARK_GRAY) end
    if top + h < self.total_h then bb:paintRect(x, y + h - 1, self.width, 1, Blitbuffer.COLOR_DARK_GRAY) end
end

return RichEdit
