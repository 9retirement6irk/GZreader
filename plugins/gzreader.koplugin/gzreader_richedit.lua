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
- Code, quotes, tables show as their Markdown in grey and edit as text.
- A picture on a line of its own shows as the picture (when the editor
  gives `pictures`, and it's on the Kindle), at the size and place Memos'
  web editor gave it (`![alt|center|320](…)`, Sticky.altSize). A tap picks
  it: a frame and a pull tab on each side; drag a tab to make it wider or
  narrower, written back as the web editor writes it. Above it, the web
  editor's picture toolbar: Left, Center, Right, then ↑ ↓ (move it up or
  down a paragraph), Alt (its description), 1:1 (its own size) and ✕
  (delete). Dragging the picture itself moves it to another place in the
  note (a line shows where it goes). Typing with a picture picked starts
  a line after it.

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
local _ = require("gettext")
local Blocks = require("gzreader_blocks")
local Sticky = require("gzreader_sticky")

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
    -- a keyboard Kindle: no on-screen keyboard (the page is all of max_height), the
    -- Kindle's keys type here and the 5-way moves the cursor (RichEdit:onKeyPress)
    keys = false,
    gz_multiline = true, -- (the on-screen keyboard keeps Enter and ← →)
    gz_hash_key = true, -- (and a # key for tags: gzreader_hashkey.lua)
    focused = true,
    -- the note's pictures: { size = function(src) → w, h (the file's) or nil
    -- (not here: fetched, then `relayoutPictures()`), bb = function(src, w, h) → its picture at that size }
    pictures = nil,
}

RichEdit.TAB_W = 14 -- a pull tab, scaled (wide, and its touch area 3 times that)
RichEdit.TAB_H = 48
RichEdit.MIN_PICTURE = 40 -- the narrowest a picture is dragged to

RichEdit.TEXT_SIZE = 20
RichEdit.HEADING_SIZE = { 28, 24, 22, 21, 20, 20 }
RichEdit.MONO_SIZE = 16
RichEdit.SECTION_INDENT = 24 -- what's inside an open <details> section, this much to the right (scaled)
RichEdit.CHEVRON = 22 -- a section's chevron (scaled); a tap this far into its row opens or folds it

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

--- A picture block's picture: { src, alt, width, height, align } (the web
--- editor's size, Sticky.altSize), or nil when it isn't one.
function RichEdit.pictureOf(b)
    if b.kind ~= "image" then return nil end
    local alt, src = table.concat(b.chars):match("^%s*!%[([^%]]*)%]%(([^%)%s]+)[^%)]*%)%s*$")
    if not src then return nil end
    local size = Sticky.altSize(alt)
    size.src = src
    return size
end

--- How big a picture `nw` x `nh` (its file) shows on a page `width` wide:
--- a size set in Memos takes its share of Memos' column (Sticky.pictureWidth),
--- enlarged if need be; none set, its own width as Memos shows it (the file's
--- pixels as CSS pixels: the same share of the column, so a small picture
--- isn't a thumbnail beside sized ones), no taller than `max_h`.
function RichEdit.pictureSize(pic, nw, nh, width, max_h)
    local want = Sticky.pictureWidth(pic.width, width)
    if want then return want, math.max(1, math.floor(nh * want / nw + 0.5)) end
    local own = Sticky.pictureWidth(nw, width) or width
    local h = math.max(1, math.floor(nh * own / nw + 0.5))
    if max_h and h > max_h then return Sticky.fitSize(nw, nh, width, max_h, 50) end
    return own, h
end

--- Lays the note out `width` wide: the screen lines, each
--- { b, a, z, y, h, base, x0, xs (x of positions a … z+1), first, last, st }
--- (a picture's line also `picture` = { w, h, src, align, …, x }).
--- `pictured(b)`: the size a picture block shows at (w, h), or nil (its Markdown).
function RichEdit.layout(doc, width, pictured)
    local lines = {}
    local y = 0
    local prev, prev_num
    local depth, folded = 0, 0 -- (open <details> sections around the block; inside a folded one: how deep)
    for _k, b in ipairs(doc.blocks) do
        if folded > 0 then
            -- (inside a folded section: not shown, its end included)
            if b.section == "start" then folded = folded + 1 elseif b.section == "end" then folded = folded - 1 end
            goto next_block
        end
        if b.section == "start" or (b.section == "end" and depth > 0) then
            -- a <details> section's start: a row with a chevron and its title, a
            -- tap on the chevron opens or folds it (RichEdit.SECTION); its end: a thin line
            if prev then y = y + S(8) end
            if b.section == "end" then depth = depth - 1 end
            local face = RichEdit.face(RichEdit.TEXT_SIZE)
            local lh, base = lineMetrics(face)
            local x0 = S(RichEdit.SECTION_INDENT) * depth
            local h = b.section == "start" and lh or S(10)
            local xs = {}
            for _i = 1, #b.chars + 1 do xs[#xs + 1] = x0 end
            local info = b.section == "start" and Blocks.sectionStart(table.concat(b.chars)) or nil
            lines[#lines + 1] = { b = b, a = 1, z = #b.chars, y = y, h = h, base = base, x0 = x0, xs = xs, w = {},
                st = { size = RichEdit.TEXT_SIZE }, first = true, last = true,
                section = { start = b.section == "start", folded = b.folded, title = info and info.title or "" } }
            y = y + h
            if b.section == "start" then
                if b.folded then folded = 1 else depth = depth + 1 end
            end
            prev, prev_num = b, nil
            goto next_block
        end
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
        local pw, ph, pic
        if pictured then pw, ph, pic = pictured(b) end
        if pw then
            -- a picture: one line as tall as it, placed as in Memos
            local sx = S(RichEdit.SECTION_INDENT) * depth
            if sx > 0 and pw > width - sx then ph, pw = math.max(1, math.floor(ph * (width - sx) / pw)), width - sx end
            local room = math.max(0, width - sx - pw)
            local px = sx + (pic.align == "center" and math.floor(room / 2) or pic.align == "right" and room or 0)
            local xs = {}
            for _i = 1, #b.chars do xs[#xs + 1] = px end
            xs[#xs + 1] = px + pw
            pic.x, pic.w, pic.h = px, pw, ph
            lines[#lines + 1] = { b = b, a = 1, z = #b.chars, y = y, h = ph, base = 0, x0 = px, xs = xs, st = st, w = {},
                first = true, last = true, picture = pic }
            y = y + ph
            prev, prev_num = b, num
            goto next_block
        end
        local base_face = RichEdit.face(st.size, st.bold, false, st.mono)
        local lh, base = lineMetrics(base_face)
        local indent = S(28) * math.floor(#(b.indent or "") / 2) + S(RichEdit.SECTION_INDENT) * depth
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
        ::next_block::
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
    if self.keys then
        self.height = math.max(S(80), self.max_height or Screen:getHeight())
        self.focused = true
        self.parent = self.editor -- (Back: InputText's key handler closes its parent)
    else
        local VirtualKeyboard = require("ui/widget/virtualkeyboard")
        self.keyboard = VirtualKeyboard:new{ keyboard_layer = 2, inputbox = self }
        local kb_h = self.keyboard.dimen and self.keyboard.dimen.h or math.floor(Screen:getHeight() * 0.4)
        self.height = math.max(S(80), (self.max_height or Screen:getHeight()) - kb_h)
    end
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
        -- (a picture moved or sized follows the finger anywhere on the screen)
        PanEdit = { GestureRange:new{ ges = "pan", range = function() return self:panRange() end } },
        PanReleaseEdit = { GestureRange:new{ ges = "pan_release", range = function() return self:panRange() end } },
    }
    self:relayout()
    self:keepCursorInView()
end

function RichEdit:getSize() return self.dimen end

--- The size picture block `b` shows at here (w, h, its picture), or nil
--- (no `pictures`, not a picture, or its file not here yet).
function RichEdit:pictured(b)
    if not self.pictures then return nil end
    local pic = RichEdit.pictureOf(b)
    if not pic then return nil end
    local nw, nh = self.pictures.size(pic.src)
    if not nw or nw < 1 or nh < 1 then return nil end
    pic.nw, pic.nh = nw, nh
    local w, h = RichEdit.pictureSize(pic, nw, nh, self.width, math.floor(self.height * 0.6))
    return w, h, pic
end

--- A picture arrived (fetched): lay out again and redraw.
function RichEdit:relayoutPictures()
    self:update()
end

--- Lays out again after a change (and the flat text for the keyboard).
function RichEdit:relayout()
    self.lines, self.total_h = RichEdit.layout(self.doc, self.width, function(b) return self:pictured(b) end)
    if not RichEdit.lineOf(self.lines, self.cur) and self:unfoldAround(self.cur.b) then
        -- (the cursor went into a folded section, by an arrow key or a search: it opens)
        self.lines, self.total_h = RichEdit.layout(self.doc, self.width, function(b) return self:pictured(b) end)
    end
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
    if l.picture and l.h > self.height - S(60) then
        -- (a picture taller than the page: its top in view, a little above it showing)
        if l.y < self.top or l.y > self.top + self.height - S(60) then self.top = math.max(0, l.y - S(60)) end
    elseif l.y < self.top then self.top = l.y
    elseif l.y + l.h > self.top + self.height then self.top = l.y + l.h - self.height end
    self.top = math.max(0, math.min(self.top, math.max(0, self.total_h - self.height)))
end

--- After an edit or a move: lay out, keep the cursor in view, redraw.
--- (The formatting bar goes away with any of them but a hold and its own buttons: keep_bar.)
function RichEdit:update(edited, keep_bar)
    if not keep_bar then self.bar_open = nil end
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
    if self:onPicture() then
        -- (a picture takes no typing: the words go on a new line after it)
        self.picked = nil
        self.cur = { b = Blocks.split(self.doc, self.cur.b, #self.cur.b.chars + 1), i = 1 }
        self.doc.changed = true
        if chars == "\n" then return self:update("structure") end
    end
    if self:sectionLine(self.cur.b) then
        -- (a section's row or end takes no typing: the words go on a new line after it, inside an open section)
        local sb = self.cur.b
        if sb.section == "start" and sb.folded then sb.folded = false end
        self.anchor = nil
        self.cur = { b = Blocks.split(self.doc, sb, #sb.chars + 1), i = 1 }
        self.doc.changed = true
        if chars == "\n" then return self:update("structure") end
    end
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

--- Opens the folded <details> sections block `b` is in. True when any was.
function RichEdit:unfoldAround(b)
    local opened, stack = false, {}
    for _k, x in ipairs(self.doc.blocks) do
        if x == b then break end
        if x.section == "start" then stack[#stack + 1] = x
        elseif x.section == "end" and #stack > 0 then stack[#stack] = nil end
    end
    for _i, s in ipairs(stack) do
        if s.folded then s.folded = false; opened = true end
    end
    return opened
end

--- The section row or end line block `b` shows as (RichEdit.layout), if any.
function RichEdit:sectionLine(b)
    for _i, l in ipairs(self.lines or {}) do
        if l.section and l.b == b then return l end
    end
end

--- A <details> section's start: open it or fold it (how the editor shows
--- it; the note keeps how it was written). The cursor, if it was inside, goes to its row.
function RichEdit:toggleSection(b)
    b.folded = not b.folded
    if b.folded then
        local inside, depth = false, 0
        for _k, x in ipairs(self.doc.blocks) do
            if x == b then inside = true
            elseif inside then
                if x == self.cur.b or (self.anchor and x == self.anchor.b) then
                    self.anchor = nil
                    self.cur = { b = b, i = #b.chars + 1 }
                    break
                end
                if x.section == "start" then depth = depth + 1
                elseif x.section == "end" then
                    if depth == 0 then break end
                    depth = depth - 1
                end
            end
        end
    end
    self:update(nil, true)
end

--- The section's title, from a dialog; or the section taken away (its words
--- kept) or deleted with them.
function RichEdit:sectionMenu(b)
    local _ = require("gettext")
    local ButtonDialog = require("ui/widget/buttondialog")
    local info = Blocks.sectionStart(table.concat(b.chars)) or { title = "", open = false }
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    dialog = ButtonDialog:new{
        title = info.title ~= "" and info.title or _("Section"),
        buttons = {
            { { text = b.folded and _("Open") or _("Fold"), callback = run(function() self:toggleSection(b) end) } },
            { { text = _("Rename…"), callback = run(function() self:renameSection(b) end) } },
            { { text = _("Remove the section (keep what's in it)"), callback = run(function() self:removeSection(b, false) end) } },
            { { text = _("Delete the section and what's in it"), callback = run(function() self:removeSection(b, true) end) } },
        },
    }
    UIManager:show(dialog)
end

function RichEdit:renameSection(b)
    local _ = require("gettext")
    local InputDialog = require("ui/widget/inputdialog")
    local info = Blocks.sectionStart(table.concat(b.chars)) or { title = "", open = false }
    local dialog
    dialog = InputDialog:new{
        title = _("Section title"), input = info.title,
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local t = dialog:getInputText():gsub("\n", " ")
                UIManager:close(dialog)
                Blocks.setText(b, Blocks.sectionMarkdown(t, info.open))
                self:update("structure")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Takes section `b` away: its start and its end; with `everything`, what's in it too.
function RichEdit:removeSection(b, everything)
    local blocks = self.doc.blocks
    local from, to
    local depth = 0
    for k, x in ipairs(blocks) do
        if x == b then from = k
        elseif from then
            if x.section == "start" then depth = depth + 1
            elseif x.section == "end" then
                if depth == 0 then to = k; break end
                depth = depth - 1
            end
        end
    end
    if not from then return end
    to = to or (everything and #blocks or nil)
    if everything then
        for k = to, from, -1 do table.remove(blocks, k) end
    else
        if to then table.remove(blocks, to) end
        table.remove(blocks, from)
    end
    if blocks[from] then blocks[from].moved = true end
    if #blocks == 0 then blocks[1] = Blocks.new("paragraph") end
    self.doc.changed = true
    local at = blocks[math.min(from, #blocks)]
    self.anchor = nil
    self.cur = { b = at, i = 1 }
    self:update("structure")
end

--- The cursor is on a picture shown as one.
function RichEdit:onPicture()
    for _i, l in ipairs(self.lines or {}) do
        if l.picture and l.b == self.cur.b then return true end
    end
    return false
end

--- The picture line of block `b` (shown as a picture), if any.
function RichEdit:pictureLine(b)
    for _i, l in ipairs(self.lines or {}) do
        if l.picture and l.b == b then return l end
    end
end

--- The pull tabs of the picked picture, on the widget: { left = rect, right = rect }
--- (rects as drawn; a touch counts in a wider area, tabAt).
function RichEdit:tabs()
    local l = self.picked and self:pictureLine(self.picked)
    if not l then return nil end
    local tw, th = S(RichEdit.TAB_W), math.min(S(RichEdit.TAB_H), l.h)
    local ty = RichEdit.tabY(l.y - self.top, l.h, th, self.height)
    local x1, x2 = l.picture.x, l.picture.x + l.picture.w
    return {
        left = { x = math.max(0, x1 - math.floor(tw / 2)), y = ty, w = tw, h = th },
        right = { x = math.min(self.width - tw, x2 - math.floor(tw / 2)), y = ty, w = tw, h = th },
        line = l,
    }
end

--- Where the tabs go on a picture at `top`, `h` tall, on a page `page_h`
--- tall: the middle of the part on the page (all of it when it fits).
function RichEdit.tabY(top, h, th, page_h)
    local a, z = math.max(0, top), math.min(page_h, top + h)
    if z - a < th then a, z = top, top + h end
    return a + math.floor((z - a - th) / 2)
end

--- The tab at (x, y) on the widget ("left" or "right"), or nil.
function RichEdit:tabAt(x, y)
    local t = self:tabs()
    if not t then return nil end
    for _i, side in ipairs({ "right", "left" }) do
        local r = t[side]
        local pad = r.w
        if x >= r.x - pad and x < r.x + r.w + pad and y >= r.y - pad and y < r.y + r.h + pad then return side end
    end
end

-- the picked picture's toolbar, as the web editor's (mbe-image-toolbar), plus moving it
RichEdit.PICTURE_BAR = {
    { id = "left", align = "left", label = "Align left" },
    { id = "center", align = "center", label = "Align center" },
    { id = "right", align = "right", label = "Align right" },
    { id = "up", text = "\u{2191}", label = "Move up" },
    { id = "down", text = "\u{2193}", label = "Move down" },
    { id = "alt", text = "Alt", label = "Alt text" },
    { id = "reset", text = "1:1", label = "Reset size" },
    { id = "delete", text = "\u{2715}", label = "Delete" },
}

--- The picked picture's toolbar (relative to the widget): above the picture,
--- under it when there's no room, on the page. nil when no picture is picked.
function RichEdit:pictureBarRect()
    local l = self.picked and self:pictureLine(self.picked)
    if not l then return nil end
    local n = #RichEdit.PICTURE_BAR
    local cell = math.min(S(50), math.floor(self.width / n))
    local w, h, gap = cell * n, S(44), S(6)
    local top = l.y - self.top
    local y = top - h - gap
    if y < 0 then y = top + l.h + gap end
    if y + h > self.height then y = math.max(0, math.min(self.height - h, top + gap)) end
    local x = math.max(0, math.min(self.width - w, l.picture.x + math.floor((l.picture.w - w) / 2)))
    return { x = x, y = y, w = w, h = h, cell = cell }
end

--- The toolbar's button at (x, y), or nil.
function RichEdit:pictureBarAt(x, y)
    local r = self:pictureBarRect()
    if not r or x < r.x or x >= r.x + r.w or y < r.y or y >= r.y + r.h then return nil end
    return RichEdit.PICTURE_BAR[math.min(#RichEdit.PICTURE_BAR, math.floor((x - r.x) / r.cell) + 1)]
end

--- Moves block `b` to position `to` among the blocks (1 … #blocks): the
--- blocks around where it was and where it goes are joined again as Memos'
--- editor writes them.
function RichEdit:moveBlock(b, to)
    local blocks = self.doc.blocks
    local from
    for k, x in ipairs(blocks) do if x == b then from = k end end
    if not from then return false end
    to = math.max(1, math.min(#blocks, to))
    if to == from then return false end
    local function mark(k) if blocks[k] then blocks[k].moved = true end end
    mark(from + 1)
    table.remove(blocks, from)
    table.insert(blocks, to, b)
    mark(to); mark(to + 1)
    b.dirty = true
    self.doc.changed = true
    return true
end

--- A toolbar button on picture block `b`.
function RichEdit:pictureTool(t, b)
    local pic = RichEdit.pictureOf(b)
    if not pic then return end
    local line = table.concat(b.chars)
    if t.align then
        Blocks.setText(b, Sticky.setImageSize(line, 1, { width = pic.width, align = t.align ~= "left" and t.align or nil }))
    elseif t.id == "reset" then
        Blocks.setText(b, Sticky.setImageSize(line, 1, { align = pic.align }))
    elseif t.id == "up" or t.id == "down" then
        local k
        for i, x in ipairs(self.doc.blocks) do if x == b then k = i end end
        if not (k and self:moveBlock(b, k + (t.id == "up" and -1 or 1))) then return end
    elseif t.id == "delete" then
        local blocks = self.doc.blocks
        local k
        for i, x in ipairs(blocks) do if x == b then k = i end end
        if not k then return end
        if blocks[k + 1] then blocks[k + 1].moved = true end
        table.remove(blocks, k)
        if #blocks == 0 then blocks[1] = Blocks.new("paragraph") end
        local near = blocks[math.max(1, k - 1)]
        self.picked = nil
        self.cur = { b = near, i = #near.chars + 1 }
        self.doc.changed = true
    elseif t.id == "alt" then
        return self:askAlt(b)
    end
    self:update("structure", true)
end

--- Alt: the picture's description, typed (its size and place kept).
function RichEdit.withAlt(line, alt)
    local open, old, rest = line:match("^(%s*!%[)([^%]]*)(%].*)$")
    if not open then return nil end
    local size = Sticky.altSize(old)
    alt = tostring(alt or ""):gsub("[%[%]\n|]", " ")
    return open .. alt .. Sticky.imageSuffix{ width = size.width, height = size.height, align = size.align } .. rest
end

function RichEdit:askAlt(b)
    local InputDialog = require("ui/widget/inputdialog")
    local pic = RichEdit.pictureOf(b)
    local dialog
    dialog = InputDialog:new{
        title = "Alt text", input = pic.alt or "", input_hint = "Describe the image\u{2026}",
        buttons = { {
            { text = "Cancel", id = "close", callback = function() UIManager:close(dialog) end },
            { text = "Save", is_enter_default = true, callback = function()
                local line = RichEdit.withAlt(table.concat(b.chars), dialog:getInputText())
                UIManager:close(dialog)
                if line then
                    Blocks.setText(b, line)
                    self:update("structure", true)
                end
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Where pans are taken: the page; the whole screen while a picture is being moved or sized.
function RichEdit:panRange()
    if self.moving or self.drag then
        return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    end
    return self.dimen
end

RichEdit.EDGE = 48 -- a picture dragged this near the page's top or bottom scrolls the note

--- Where a picture dragged to `y` (on the widget) goes: the block position
--- (1 … #blocks + 1) and the line's y on the widget, to show it.
function RichEdit:dropAt(y)
    local yy = y + self.top
    local blocks = self.doc.blocks
    local at, line_y = #blocks + 1, self.total_h
    for k, b in ipairs(blocks) do
        local top, bottom
        for _i, l in ipairs(self.lines) do
            if l.b == b then top = top or l.y; bottom = math.max(bottom or 0, l.y + l.h) end
        end
        if top and yy < (top + bottom) / 2 then at, line_y = k, top; break end
    end
    return at, line_y - self.top
end

--- A picture dragged to `w` pixels wide here: its size in Memos (CSS
--- pixels, its share of Memos' column), written into the note.
function RichEdit:resizePicture(b, w)
    local pic = RichEdit.pictureOf(b)
    if not pic then return end
    local css = math.max(1, math.min(Sticky.WEB_COLUMN, math.floor(w * Sticky.WEB_COLUMN / self.width + 0.5)))
    local line = Sticky.setImageSize(table.concat(b.chars), 1, { width = css, align = pic.align })
    Blocks.setText(b, line)
    self:update("structure", true)
    return css
end

function RichEdit:delChar()
    if self:deleteSelection() then return self:update("structure") end
    if self:sectionLine(self.cur.b) then
        -- (not into a section's Markdown: to the line before; the section goes by its menu)
        local prev = self.doc.blocks[(Blocks.indexOf(self.doc, self.cur.b) or 1) - 1]
        if prev then self:setCursor({ b = prev, i = #prev.chars + 1 }) end
        return self:update()
    end
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

--- The whole note replaced by Markdown `text` (as InputText:setText), the cursor at its end.
function RichEdit:setText(text)
    local doc = Blocks.parse(text or "")
    if #doc.blocks == 0 then doc.blocks[1] = Blocks.new("paragraph") end
    self.doc.blocks = doc.blocks
    self.doc.changed = true
    local last = self.doc.blocks[#self.doc.blocks]
    self:setCursor({ b = last, i = #last.chars + 1 })
    self:update(true)
end
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

-- ------------------------------------------------------------ a keyboard Kindle's keys

-- (Alt + the top row types 1–0, as in the Markdown text box: gzreader_noteeditor.lua)
local ALT_DIGITS = { Q = "1", W = "2", E = "3", R = "4", T = "5", Y = "6", U = "7", I = "8", O = "9", P = "0" }

--- Where the cursor is, to tell whether a key moved it.
local function at(self) return self.cur.b, self.cur.i, self.top end

--- Ticks or unticks the checklist item the cursor is on (Alt+X). True when it is one.
function RichEdit:tickHere()
    local b = self.cur.b
    if b.kind ~= "task" then return false end
    Blocks.toggleDone(b)
    self:update(true)
    return true
end

-- (what InputText's key handler asks of a text box that this page has under other names, or not at all)
function RichEdit:goToHome() return self:goToStartOfLine() end
function RichEdit:goToEnd() return self:goToEndOfLine() end
function RichEdit:delNextChar()
    local b, i = at(self)
    self:rightChar()
    local b2, i2 = at(self)
    if b2 ~= b or i2 ~= i then self:delChar() end
end
function RichEdit:toggleKeyboard() end
function RichEdit:holdTextBox() end

--- A key of a keyboard Kindle (`keys`): the letters type (the Kindle's own
--- handling, InputText's: Shift, Sym + a letter, Del, Shift + Del a word);
--- Alt + a letter is the editor's shortcut (Alt+B bold, Alt+L list, …) and
--- Alt + the top row a digit; ◀ ▶ ▲ ▼ move the cursor (▼ on the last line
--- and ▲ on the first go on to the editor: its toolbar), with Shift they
--- select; Press is a new line, or opens / folds the section whose row the
--- cursor is on; Sym opens the symbols.
function RichEdit:onKeyPress(key)
    if not self.keys or not self.focused then return false end
    local mod = key.modifiers or {}
    if mod.Alt and not mod.Shift then
        if self.editor and self.editor.onShortcut and self.editor:onShortcut(key.key) then return true end
        local d = ALT_DIGITS[key.key] or (tostring(key.key):match("^%d$") and key.key)
        if d then self:addChars(d); return true end
    end
    if key.key and tostring(key.key):match("^%d$") and not mod.Alt then
        self:addChars(key.key)
        return true
    end
    if key["SymPress"] then
        local ok, GzSymbols = pcall(require, "gzsymbols")
        if ok and GzSymbols.wanted(require("device")) then GzSymbols.show(self) end
        return true
    end
    local arrow = key["Left"] and "leftChar" or key["Right"] and "rightChar" or key["Up"] and "upLine" or key["Down"] and "downLine"
    if arrow and mod.Shift and not mod.Alt then
        -- Shift + the 5-way: selects from where the cursor was
        local anchor = self.anchor or { b = self.cur.b, i = self.cur.i }
        local want = self.want_x
        self[arrow](self)
        if arrow == "upLine" or arrow == "downLine" then self.want_x = self.want_x or want end
        self.anchor = anchor
        self:update(nil, true)
        return true
    end
    if not (mod.Shift or mod.Alt or mod.Ctrl or mod.Sym) then
        if key["Up"] or key["Down"] then
            local b, i, top = at(self)
            self[arrow](self)
            local b2, i2, top2 = at(self)
            -- (didn't move: the first or last line; on to the editor, whose toolbar is under the page)
            return not (b2 == b and i2 == i and top2 == top)
        elseif key["Press"] then
            local sl = self:sectionLine(self.cur.b)
            if sl and sl.section.start then
                self:toggleSection(self.cur.b)
                return true
            end
        end
    end
    return require("ui/widget/inputtext").onKeyPress(self, key)
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

--- A colour screen (and its colour rendering on): text and highlight colours.
function RichEdit.colour() return require("gzreader_colour").enabled() end

--- "#rrggbb" as a colour to paint with.
function RichEdit.rgb32(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    return Blitbuffer.ColorRGB32(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), 0xFF)
end

--- Colours the selection, else the word at the cursor, else what's typed next
--- (`kind`: "fg" text colour, "hl" highlight; nil `id`: none).
function RichEdit:setColor(kind, id)
    local p, q = self:selection()
    if p then
        Blocks.setColorRange(self.doc, p, q, kind, id)
        return self:update(true)
    end
    local b, i = self.cur.b, self.cur.i
    if b.kind == "raw" or b.kind == "image" then return end
    local function word(ch) return ch and not ch:match("^[%s%p]$") end
    if word(b.chars[i]) or word(b.chars[i - 1]) then
        local a, z = Blocks.wordAt(b, i)
        Blocks.setColor(b, kind, id, a, z)
        return self:update(true)
    end
    local m = self.pending
    if m == nil then m = Blocks.typedMarks(b, i) end
    m = m or {}
    local fg, hl = m.fg, m.hl
    if kind == "fg" then fg = id else hl = id end
    self.pending = Blocks.markset(m.b, m.i, m.s, nil, nil, fg, hl)
    self:update()
end

--- The colours to choose from (the bar's A): the text's, then a highlight's.
function RichEdit:pickColor()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local NAMES = { gray = _("Grey"), red = _("Red"), orange = _("Orange"), yellow = _("Yellow"), green = _("Green"),
        aqua = _("Aqua"), blue = _("Blue"), purple = _("Purple"), pink = _("Pink") }
    local function row(list, kind, from, to)
        local r = {}
        for k = from, math.min(to, #list) do
            local c = list[k]
            r[#r + 1] = { text = NAMES[c.id] or c.id, callback = function()
                UIManager:close(dialog)
                self:setColor(kind, c.id)
            end }
        end
        return r
    end
    local buttons = {
        { { text = _("Text colour"), enabled = false } },
        row(Blocks.TEXT_COLORS, "fg", 1, 5), row(Blocks.TEXT_COLORS, "fg", 6, 9),
        { { text = _("Black (no colour)"), callback = function() UIManager:close(dialog); self:setColor("fg", nil) end } },
        { { text = _("Highlight"), enabled = false } },
        row(Blocks.MARK_COLORS, "hl", 1, 5),
        { { text = _("No highlight"), callback = function() UIManager:close(dialog); self:setColor("hl", nil) end } },
    }
    dialog = ButtonDialog:new{ title = _("Colour"), title_align = "center", buttons = buttons }
    UIManager:show(dialog)
end

--- A toolbar button (`id`: heading, bullet, task, ordered, bold, italic, colour, tag).
function RichEdit:useTool(id)
    if id == "bold" then return self:toggleMark("b")
    elseif id == "italic" then return self:toggleMark("i")
    elseif id == "color" then return self:pickColor()
    elseif id == "tag" then
        if self.editor and self.editor.pickTag then return self.editor:pickTag() end
        return
    end
    return self:setKind(id)
end

-- ------------------------------------------------------------ the formatting bar

--- The bar that comes up at a selection (hold a word, drag for more; hold an
--- empty line for the line itself): Bold, Italic, Heading, List, Checklist,
--- Numbered, Tag, as in Memos' web editor. A tap on the text or typing puts it away.
RichEdit.BAR = {
    { id = "bold", label = "B" },
    { id = "italic", label = "I" },
    { id = "heading", label = "H" },
    { id = "bullet", label = "\u{2022}" },
    { id = "task", label = "\u{2610}" },
    { id = "ordered", label = "1." },
    { id = "tag", label = "#" },
}
--- The bar's buttons here: a colour screen's has A (colours) after Italic.
function RichEdit:barTools()
    if not RichEdit.colour() then return RichEdit.BAR end
    if not RichEdit._colour_bar then
        local t = {}
        for _i, b in ipairs(RichEdit.BAR) do
            t[#t + 1] = b
            if b.id == "italic" then t[#t + 1] = { id = "color", label = "A" } end
        end
        RichEdit._colour_bar = t
    end
    return RichEdit._colour_bar
end

--- Where the bar goes (relative to the widget): above the selection's first
--- line, under its last one when there's no room above. nil when it's closed.
function RichEdit:barRect()
    if not self.bar_open then return nil end
    local p, q = self:selection()
    p, q = p or self.cur, q or self.cur
    local li, x1 = RichEdit.lineOf(self.lines, p)
    local lj = RichEdit.lineOf(self.lines, q)
    local first, last = li and self.lines[li], lj and self.lines[lj]
    if not first then return nil end
    last = last or first
    local n = #self:barTools()
    local cell = math.min(S(54), math.floor(self.width / n))
    local w, h, gap = cell * n, S(44), S(6)
    local y = first.y - self.top - h - gap
    if y < 0 then y = last.y + last.h - self.top + gap end
    if y + h > self.height then y = math.max(0, self.height - h) end
    local x = math.max(0, math.min(self.width - w, math.floor((x1 or 0) - w / 4)))
    return { x = x, y = y, w = w, h = h, cell = cell }
end

--- The bar's button at (x, y), if the bar is open and the point is on it.
function RichEdit:barToolAt(x, y)
    local r = self:barRect()
    if not r or x < r.x or x >= r.x + r.w or y < r.y or y >= r.y + r.h then return nil end
    local tools = self:barTools()
    return tools[math.min(#tools, math.floor((x - r.x) / r.cell) + 1)]
end

--- Is this tool on for the selection (or the cursor's line / word)? (drawn inverted)
function RichEdit:toolOn(id)
    local p = self:selection()
    local b = (p or self.cur).b
    if id == "heading" or id == "bullet" or id == "task" or id == "ordered" then return b.kind == id end
    local i = (p or self.cur).i
    local m = b.marks and b.marks[math.min(i, #b.chars)]
    if id == "bold" then return m and m.b == true or false end
    if id == "italic" then return m and m.i == true or false end
    return false
end

function RichEdit:paintBar(bb, x, y)
    local r = self:barRect()
    if not r then return end
    local bx, by = x + r.x, y + r.y
    local border = math.max(2, S(2))
    bb:paintRoundedRect(bx, by, r.w, r.h, Blitbuffer.COLOR_WHITE, S(8))
    bb:paintBorder(bx, by, r.w, r.h, border, Blitbuffer.COLOR_BLACK, S(8))
    for i, t in ipairs(self:barTools()) do
        local cx = bx + (i - 1) * r.cell
        local on = self:toolOn(t.id)
        if on then bb:paintRect(cx + border + 1, by + border + 1, r.cell - 2 * border - 2, r.h - 2 * border - 2, Blitbuffer.COLOR_BLACK) end
        if i > 1 then bb:paintRect(cx, by + S(8), 1, r.h - S(16), Blitbuffer.COLOR_DARK_GRAY) end
        local face = RichEdit.face(t.id == "task" and 22 or 20, t.id == "bold", t.id == "italic")
        local tw = RenderText:sizeUtf8Text(0, r.cell, face, t.label, true, false).x
        local _h, base = lineMetrics(face)
        RenderText:renderUtf8Text(bb, cx + math.floor((r.cell - tw) / 2), by + math.floor((r.h - _h) / 2) + base, face, t.label,
            true, false, on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
        if t.id == "color" then
            -- (A over a bar in the colour of the words there: red A for red words)
            local p0 = self:selection() or self.cur
            local m = p0.b.marks and p0.b.marks[math.min(p0.i, #p0.b.chars)]
            local hex = m and m.fg and Blocks.colorHex("fg", m.fg)
            local bw, bh = math.floor(r.cell * 0.5), math.max(3, S(4))
            local barx, bary = cx + math.floor((r.cell - bw) / 2), by + r.h - bh - S(6)
            if hex then bb:paintRectRGB32(barx, bary, bw, bh, RichEdit.rgb32(hex)) else bb:paintRect(barx, bary, bw, bh, Blitbuffer.COLOR_BLACK) end
        end
    end
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
    -- the formatting bar: its button, on the selection (the bar stays for another)
    local tool = self:barToolAt(x, y)
    if tool then
        self:useTool(tool.id)
        if tool.id ~= "tag" then
            self.bar_open = true
            UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
        end
        return true
    end
    -- the picked picture's toolbar
    local ptool = self.picked and self:pictureBarAt(x, y)
    if ptool then
        self:pictureTool(ptool, self.picked)
        return true
    end
    local p, l = self:posAt(x, y)
    if not p then return true end
    -- a picture: picked (its pull tabs), the cursor after it; a tap elsewhere lets it go
    if l and l.picture and x >= l.picture.x and x < l.picture.x + l.picture.w then
        self.picked = l.b
        self.anchor = nil
        self.cur = { b = l.b, i = #l.b.chars + 1 }
        -- (the keyboard away: room for the picture, its toolbar and moving it)
        if self.keyboard and self.keyboard:isVisible() then self:onCloseKeyboard() end
        self:update(nil, true)
        return true
    end
    if self.picked and self:tabAt(x, y) then return true end
    self.picked = nil
    -- a section's row: the chevron opens or folds it, its title has the section's menu
    if l and l.section and l.section.start then
        if x < l.x0 + S(RichEdit.CHEVRON) + S(16) then self:toggleSection(l.b) else self:sectionMenu(l.b) end
        return true
    end
    if l and l.section then -- (its end: the cursor on the line after it)
        local nxt = self.doc.blocks[(Blocks.indexOf(self.doc, l.b) or 0) + 1]
        if nxt then self:setCursor({ b = nxt, i = 1 }) end
        self:update()
        return true
    end
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
    if self:barToolAt(rel(self, ges)) then return true end
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
    self.dragged = false
    self.pending = nil
    self.bar_open = true -- the formatting bar, at what's chosen
    self:update(nil, true)
    return true
end

function RichEdit:onHoldPanEdit(_arg, ges)
    if not self.selecting then return false end
    local p = self:posAt(rel(self, ges))
    if p then
        self.cur = p
        self.dragged = true
        self:update(nil, true)
    end
    return true
end

function RichEdit:onHoldReleaseEdit(_arg, ges)
    if not self.selecting then return false end
    self.selecting = false
    -- (a hold without a drag keeps the word it chose: the finger lifts inside it)
    if self.dragged and ges and ges.pos then
        local p = self:posAt(rel(self, ges))
        if p and self.anchor and not (p.b == self.anchor.b and p.i == self.anchor.i) then self.cur = p end
    end
    self:update(nil, true)
    return true
end

--- A pull tab dragged: the picture's new width as an outline while the
--- finger moves (drawn at that size once it lifts: PanReleaseEdit).
function RichEdit:onPanEdit(_arg, ges)
    if not self.picked then return false end
    if not self.drag and not self.moving then
        -- (the picture itself, not a tab: moved to another place in the note)
        local sp = ges.start_pos or ges.pos
        local sx, sy = sp.x - (self.dimen.x or 0), sp.y - (self.dimen.y or 0)
        local pl = self:pictureLine(self.picked)
        local top = pl and (pl.y - self.top)
        if not self:tabAt(sx, sy) and pl and sx >= pl.picture.x and sx < pl.picture.x + pl.picture.w and sy >= top and sy < top + pl.h then
            self.moving = { b = self.picked, start_y = sy }
        end
    end
    if self.moving then
        local m = self.moving
        local dy = (ges.relative and ges.relative.y) or 0
        local fy = m.start_y + dy
        -- (near the top or the bottom: the note scrolls under the finger)
        local edge = S(RichEdit.EDGE)
        local max_top = math.max(0, self.total_h - self.height)
        local step = S(RichEdit.EDGE)
        if fy < edge and self.top > 0 then
            local was = self.top
            self.top = math.max(0, self.top - step)
            m.start_y = m.start_y + (was - self.top)
        elseif fy > self.height - edge and self.top < max_top then
            local was = self.top
            self.top = math.min(max_top, self.top + step)
            m.start_y = m.start_y - (self.top - was)
        end
        m.at, m.line_y = self:dropAt(math.max(0, math.min(self.height, m.start_y + dy)))
        UIManager:setDirty(self.editor or self, function() return "fast", self.dimen end)
        return true
    end
    if not self.drag then
        local sp = ges.start_pos or ges.pos
        local side = self:tabAt(sp.x - (self.dimen.x or 0), sp.y - (self.dimen.y or 0))
        if not side then return false end
        local l = self:pictureLine(self.picked)
        self.drag = { side = side, b = self.picked, w = l.picture.w, h = l.picture.h, x = l.picture.x,
            align = l.picture.align, start = l.picture.w }
    end
    local d = self.drag
    local dx = (ges.relative and ges.relative.x) or 0
    -- (a centred picture grows on both sides: twice as fast)
    local f = (d.side == "right" and 1 or -1) * (d.align == "center" and 2 or 1)
    d.w = math.max(S(RichEdit.MIN_PICTURE), math.min(self.width, d.start + dx * f))
    UIManager:setDirty(self.editor or self, function() return "fast", self.dimen end) -- (an outline: quick)
    return true
end

function RichEdit:onPanReleaseEdit(_arg, _ges)
    local m = self.moving
    if m then
        self.moving = nil
        local from
        for k, x in ipairs(self.doc.blocks) do if x == m.b then from = k end end
        -- (dropped below where it was: the places after it move up one)
        local to = m.at and from and (m.at > from and m.at - 1 or m.at)
        if to and self:moveBlock(m.b, to) then
            self:update("structure", true)
        else
            UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
        end
        return true
    end
    local d = self.drag
    if not d then return false end
    self.drag = nil
    if math.abs(d.w - d.start) >= 2 then
        self:resizePicture(d.b, d.w)
    else
        UIManager:setDirty(self.editor or self, function() return "ui", self.dimen end)
    end
    return true
end

function RichEdit:onSwipeEdit(_arg, ges)
    -- (a quick drag of a pull tab comes as a swipe)
    if self.picked and ges.pos then
        local x, y = rel(self, ges)
        local side = self:tabAt(x, y)
        if side and (ges.direction == "east" or ges.direction == "west") then
            local l = self:pictureLine(self.picked)
            local dist = ges.distance or 0
            local sign = (ges.direction == "east") == (side == "right") and 1 or -1
            local f = l.picture.align == "center" and 2 or 1
            self:resizePicture(self.picked, math.max(S(RichEdit.MIN_PICTURE), math.min(self.width, l.picture.w + sign * dist * f)))
            return true
        end
    end
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
        if l.picture and ly + l.h > 0 and ly < h then
            self:paintPicture(bb, x, y, l, ly)
        elseif l.section and ly >= 0 and ly + l.h <= h then
            self:paintSection(bb, x, y, l, ly)
        elseif ly + l.h > 0 and ly < h then
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
                        -- colours (Blocks: data-gz-color / data-gz-mark): a highlight is a marker's band
                        -- over the lower part of the line, under the words; a text colour, on a colour screen
                        if m and m.hl then
                            local band = math.floor(l.h * 0.55)
                            local hex = Blocks.colorHex("hl", m.hl)
                            if RichEdit.colour() and hex then
                                bb:paintRectRGB32(x + x1, y + ly + l.h - band - S(2), x2 - x1, band, RichEdit.rgb32(hex))
                            else
                                bb:paintRect(x + x1, y + ly + l.h - band - S(2), x2 - x1, band, Blitbuffer.COLOR_GRAY_D)
                            end
                        end
                        if m and m.fg and RichEdit.colour() and Blocks.colorHex("fg", m.fg) then
                            color = RichEdit.rgb32(Blocks.colorHex("fg", m.fg))
                        end
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
    -- the cursor (not on a picture: it's picked instead; a section's row: framed)
    local on_section = self:sectionLine(self.cur.b)
    if not p and on_section and on_section.section.start then
        local ly = on_section.y - top
        if ly >= 0 and ly + on_section.h <= h then
            bb:paintBorder(x + on_section.x0, y + ly, self.width - on_section.x0, on_section.h, cursorWidth(), Blitbuffer.COLOR_BLACK)
        end
    elseif not p and not on_section and not self:onPicture() then
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
    self:paintBar(bb, x, y)
end

--- A <details> section's row: its chevron (› folded, ⌄ open) and its title,
--- as Memos' web editor shows it; its end: a short light line.
function RichEdit:paintSection(bb, x, y, l, ly)
    local _ = require("gettext")
    if not l.section.start then
        bb:paintRect(x + l.x0, y + ly + math.floor(l.h / 2), S(40), 1, Blitbuffer.COLOR_LIGHT_GRAY)
        return
    end
    local cs = S(RichEdit.CHEVRON)
    require("gzreader_chevron").paint(bb, x + l.x0, y + ly + math.floor((l.h - cs) / 2), cs, not l.section.folded)
    local face = RichEdit.face(RichEdit.TEXT_SIZE)
    local title = l.section.title ~= "" and l.section.title or _("Details")
    local room = self.width - l.x0 - cs - S(8)
    if RenderText:sizeUtf8Text(0, room, face, title, true).x > room then title = RenderText:truncateTextByWidth(title, face, room, true) end
    RenderText:renderUtf8Text(bb, x + l.x0 + cs + S(8), y + ly + l.base, face, title, true, false, Blitbuffer.COLOR_BLACK)
end

--- A picture's line: the picture (the part on the page), its frame and pull
--- tabs when it's picked, and the outline of the new size while a tab is dragged.
function RichEdit:paintPicture(bb, x, y, l, ly)
    local pic = l.picture
    local h = self.height
    local img = self.pictures and self.pictures.bb(pic.src, pic.w, pic.h)
    local from, to = math.max(0, -ly), math.min(pic.h, h - ly)
    if img and to > from then
        bb:blitFrom(img, x + pic.x, y + ly + from, 0, from, math.min(pic.w, img:getWidth()), math.min(to, img:getHeight()) - from)
    elseif to > from then
        bb:paintBorder(x + pic.x, y + math.max(0, ly), pic.w, to - from, 1, Blitbuffer.COLOR_DARK_GRAY)
    end
    if self.picked ~= l.b then return end
    self:paintPictureBar(bb, x, y)
    if self.moving and self.moving.line_y then
        -- (where the picture goes: a thick line between the paragraphs)
        local ly2 = math.max(0, math.min(h - S(4), self.moving.line_y - S(2)))
        bb:paintRect(x, y + ly2, self.width, S(4), Blitbuffer.COLOR_BLACK)
    end
    local t = self:tabs()
    local d = self.drag
    local fx, fw = pic.x, pic.w
    if d and d.b == l.b then
        fw = math.floor(d.w)
        fx = d.align == "center" and math.floor((self.width - fw) / 2) or d.align == "right" and (self.width - fw)
            or (d.side == "left" and (pic.x + pic.w - fw) or pic.x)
        fx = math.max(0, math.min(self.width - fw, fx))
    end
    local fh = d and d.b == l.b and math.max(1, math.floor(pic.h * fw / math.max(1, pic.w))) or pic.h
    local fy = ly
    local b2 = math.max(2, S(3))
    -- (the frame, clipped to the page)
    local top, bottom = math.max(0, fy), math.min(h, fy + fh)
    if bottom > top then
        if fy >= 0 then bb:paintRect(x + fx, y + fy, fw, b2, Blitbuffer.COLOR_BLACK) end
        if fy + fh <= h then bb:paintRect(x + fx, y + fy + fh - b2, fw, b2, Blitbuffer.COLOR_BLACK) end
        bb:paintRect(x + fx, y + top, b2, bottom - top, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + fx + fw - b2, y + top, b2, bottom - top, Blitbuffer.COLOR_BLACK)
    end
    -- the pull tabs, on the frame's sides
    if t then
        local tw, th = t.right.w, t.right.h
        local ty = RichEdit.tabY(fy, fh, th, h)
        for _i, tx in ipairs({ fx - math.floor(tw / 2), fx + fw - math.floor(tw / 2) }) do
            tx = math.max(0, math.min(self.width - tw, tx))
            if ty >= 0 and ty + th <= h then
                bb:paintRect(x + tx, y + ty, tw, th, Blitbuffer.COLOR_BLACK)
                bb:paintRect(x + tx + math.floor(tw / 2) - 1, y + ty + S(8), 2, th - S(16), Blitbuffer.COLOR_WHITE)
            end
        end
    end
end

--- The picked picture's toolbar: the align buttons drawn as the web's icons
--- (a picture at the left, the middle or the right under a line), the chosen one inverted.
function RichEdit:paintPictureBar(bb, x, y)
    local r = self:pictureBarRect()
    if not r then return end
    local pic = RichEdit.pictureOf(self.picked) or {}
    local align = pic.align or "left"
    local bx, by = x + r.x, y + r.y
    local border = math.max(2, S(2))
    bb:paintRoundedRect(bx, by, r.w, r.h, Blitbuffer.COLOR_WHITE, S(8))
    bb:paintBorder(bx, by, r.w, r.h, border, Blitbuffer.COLOR_BLACK, S(8))
    for i, t in ipairs(RichEdit.PICTURE_BAR) do
        local cx = bx + (i - 1) * r.cell
        local on = t.align ~= nil and t.align == align
        local ink = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        if on then bb:paintRect(cx + border + 1, by + border + 1, r.cell - 2 * border - 2, r.h - 2 * border - 2, Blitbuffer.COLOR_BLACK) end
        if i > 1 then bb:paintRect(cx, by + S(8), 1, r.h - S(16), Blitbuffer.COLOR_DARK_GRAY) end
        if t.align then
            local iw, ih = math.floor(r.cell * 0.56), math.floor(r.h * 0.5)
            local ix, iy = cx + math.floor((r.cell - iw) / 2), by + math.floor((r.h - ih) / 2)
            bb:paintRect(ix, iy, iw, math.max(1, S(2)), ink)
            local pw2 = math.floor(iw * 0.5)
            local px = t.align == "left" and ix or t.align == "center" and ix + math.floor((iw - pw2) / 2) or ix + iw - pw2
            bb:paintRect(px, iy + S(6), pw2, ih - S(6), ink)
        else
            local face = RichEdit.face(t.id == "alt" and 15 or 18, t.id == "alt" or t.id == "reset", false)
            local tw = RenderText:sizeUtf8Text(0, r.cell, face, t.text, true, false).x
            local fh, base = lineMetrics(face)
            RenderText:renderUtf8Text(bb, cx + math.floor((r.cell - tw) / 2), by + math.floor((r.h - fh) / 2) + base, face, t.text, true, false, ink)
        end
    end
end

return RichEdit
