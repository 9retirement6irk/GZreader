--[[--
An opened note's words as Memos shows them: **bold**, *italic*,
~~struck~~, `code` and [links](…) drawn that way (not as plain words), a
quote with a bar at its left, list items hung from their bullet or number,
a rule as a line, and a table as a table. The note editor on touch Kindles
has shown the first five since it was made (gzreader_richedit.lua); this is
the same for reading, on every Kindle.

Pure (inline_test.lua):
  Inline.classify(line)  → { kind = "blank" | "rule" | "quote" | "bullet" |
                             "ordered" | "para", text, depth, num }
  Inline.wrap(chars, w, max_w) → { { a, z }, … } (the lines' first and last characters)
  Inline.cells(line)     → a table row's cells, or nil
  Inline.tableAt(lines, i) → { head = { … }, align = { … }, rows = { { … } }, n = lines used }, or nil
  Inline.columns(natural, width, min) → the columns' widths

Widgets (KOReader's, loaded when first made):
  Inline.text{ text, width, size, bold, color }  → the words, wrapped
  Inline.line(line, width, size)                 → a line of a note (by its kind)
  Inline.table(t, width, size)                   → a table
  Inline.widgets(lines, width, size)             → a run of text lines, as widgets
]]

local Blocks = require("gzreader_blocks")

local Inline = {}

--- A colour screen: the words' colours show (gzreader_colour.lua).
function Inline.colour()
    local ok, Colour = pcall(require, "gzreader_colour")
    return ok and Colour.enabled() or false
end
--- "#rrggbb" as a colour to paint with.
function Inline.rgb32(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    return require("ffi/blitbuffer").ColorRGB32(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16), 0xFF)
end

Inline.MONO_SIZE = 16

-- ------------------------------------------------------------------ pure

--- What kind of line `line` (a note's Markdown) is, and its words.
function Inline.classify(line)
    line = tostring(line or "")
    -- (Memos writes an empty paragraph as &nbsp;)
    if line:match("^%s*$") or line:match("^%s*&nbsp;%s*$") then return { kind = "blank", text = "" } end
    if line:match("^%s*%-%-%-+%s*$") or line:match("^%s*%*%*%*+%s*$") or line:match("^%s*___+%s*$") then
        return { kind = "rule", text = "" }
    end
    local q = line:match("^%s*>%s?(.*)$")
    if q then return { kind = "quote", text = q } end
    local ind, rest = line:match("^(%s*)[%-%*%+]%s+(.*)$")
    if ind then return { kind = "bullet", text = rest, depth = math.floor(#ind:gsub("\t", "  ") / 2) } end
    local ind2, num, rest2 = line:match("^(%s*)(%d+)[%.%)]%s+(.*)$")
    if ind2 then return { kind = "ordered", text = rest2, num = tonumber(num), depth = math.floor(#ind2:gsub("\t", "  ") / 2) } end
    return { kind = "para", text = (line:gsub("^%s+", "")) }
end

--- Characters `chars` (widths `w`) wrapped into lines at most `max_w` wide:
--- at spaces (a space may hang past the edge), a long word cut; "\n" ends a line.
function Inline.wrap(chars, w, max_w)
    local lines = {}
    local n = #chars
    local ls = 1
    while ls <= n do
        local x, k, brk = 0, ls, nil
        while k <= n do
            if chars[k] == "\n" then break end
            if x + w[k] > max_w and k > ls and chars[k] ~= " " then break end
            x = x + w[k]
            if chars[k] == " " then brk = k end
            k = k + 1
        end
        local le
        if k > n then le = n
        elseif chars[k] == "\n" then le = k
        elseif brk then le = brk
        else le = k - 1 end
        lines[#lines + 1] = { a = ls, z = le }
        ls = le + 1
    end
    if n == 0 then lines[1] = { a = 1, z = 0 } end
    return lines
end

--- A table row's cells (`| a | b |`; `\|` is a bar in a cell), or nil.
function Inline.cells(line)
    line = tostring(line or "")
    if not line:match("^%s*|") then return nil end
    local s = line:gsub("^%s*|", ""):gsub("%s+$", "")
    s = s:gsub("\\|", "\1")
    if s:sub(-1) == "|" then s = s:sub(1, -2) end
    local cells = {}
    for c in (s .. "|"):gmatch("(.-)|") do
        cells[#cells + 1] = (c:gsub("^%s+", ""):gsub("%s+$", ""):gsub("\1", "|"))
    end
    return cells
end

--- The table that starts at `lines[i]` (a header row, a row of dashes, then
--- rows): { head, align = { "left" | "center" | "right" }, rows, n }, or nil.
function Inline.tableAt(lines, i)
    local head = Inline.cells(lines[i])
    local sep = Inline.cells(lines[i + 1])
    if not head or not sep or #sep == 0 or #head == 0 then return nil end
    local align = {}
    for k, c in ipairs(sep) do
        if not c:match("^:?%-+:?$") then return nil end
        align[k] = (c:sub(1, 1) == ":" and c:sub(-1) == ":") and "center" or c:sub(-1) == ":" and "right" or "left"
    end
    local rows = {}
    local j = i + 2
    while lines[j] do
        local r = Inline.cells(lines[j])
        if not r then break end
        rows[#rows + 1] = r
        j = j + 1
    end
    return { head = head, align = align, rows = rows, n = j - i }
end

--- The columns' widths: each as wide as its widest cell (`natural`) when all
--- fit `width`. Else the narrow ones keep theirs (a column no wider than an
--- even share of what's left) and the wide ones share the rest by how wide
--- they are, none under `min` (or an even share, when that's less).
function Inline.columns(natural, width, min)
    local n = #natural
    local total = 0
    for _i, w in ipairs(natural) do total = total + w end
    local cols = {}
    if total <= width then
        for k, w in ipairs(natural) do cols[k] = w end
        return cols
    end
    min = math.min(min, math.floor(width / n))
    local left, room = n, width
    local changed = true
    while changed and left > 0 do
        changed = false
        for k, w in ipairs(natural) do
            if not cols[k] and w <= room / left then
                cols[k] = w
                room, left, changed = room - cols[k], left - 1, true
            end
        end
    end
    local wide = 0
    for k, w in ipairs(natural) do if not cols[k] then wide = wide + w end end
    for k, w in ipairs(natural) do
        if not cols[k] then cols[k] = math.max(min, math.floor(room * w / wide)) end
    end
    return cols
end

-- --------------------------------------------------------------- widgets

local ui -- KOReader's, loaded at the first widget (the tests' stand-ins load this module without them)
local function UI()
    if ui then return ui end
    ui = {
        Blitbuffer = require("ffi/blitbuffer"),
        Font = require("ui/font"),
        Geom = require("ui/geometry"),
        RenderText = require("ui/rendertext"),
        Screen = require("device").screen,
        Widget = require("ui/widget/widget"),
    }
    return ui
end
local function S(n) return UI().Screen:scaleBySize(n) end

local FACES = {}
--- The face for `size` and bold / italic / mono (the note editor's: RichEdit.face).
function Inline.face(size, bold, italic, mono)
    local key = size .. (bold and "b" or "") .. (italic and "i" or "") .. (mono and "m" or "")
    local f = FACES[key]
    if f then return f end
    local Font = UI().Font
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
        w = ch == "\n" and 0 or UI().RenderText:sizeUtf8Text(0, 100000, face, ch, false, false).x
        t[ch] = w
    end
    return w
end

local function metrics(face)
    local lh = math.floor((1.3 * face.size) + 0.5)
    local fh, asc = face.ftsize:getHeightAndAscender()
    return lh, math.floor(asc + math.max(0, math.floor(lh - fh)) / 2)
end

local Text -- (the widget's class, made at the first one)
--- The words of `o.text` (Markdown inline), wrapped to `o.width`:
--- o.size, o.bold (all of it), o.color, o.align ("center" / "right": each line placed so).
function Inline.text(o)
    local u = UI()
    if not Text then
        Text = u.Widget:extend{}
        function Text:getSize() return self.dimen end
        function Text:paintTo(bb, x, y)
            self.dimen.x, self.dimen.y = x, y
            local color = self.color or u.Blitbuffer.COLOR_BLACK
            for li, l in ipairs(self.lines) do
                local ly = y + (li - 1) * self.lh
                local lx = x + (self.align == "center" and math.floor((self.width - l.w) / 2) or self.align == "right" and (self.width - l.w) or 0)
                local c = l.a
                while c <= l.z do
                    local face, m = self.faces[c], self.marks[c] or false
                    local j, parts, w = c, {}, 0
                    while j <= l.z and self.chars[j] ~= "\n" and self.faces[j] == face and (self.marks[j] or false) == m do
                        parts[#parts + 1] = self.chars[j]
                        w = w + self.w[j]
                        j = j + 1
                    end
                    if #parts > 0 then
                        if m and m.c then
                            -- (code: on light grey, as the web shows it)
                            bb:paintRect(lx - 1, ly + 1, w + 2, self.lh - 2, u.Blitbuffer.Color8(0xE6))
                        end
                        local ink = color
                        -- (colours: a highlight as a marker's band under the words; a text colour on a colour screen)
                        if m and m.hl then
                            local band = math.floor(self.lh * 0.55)
                            local hex = Blocks.colorHex("hl", m.hl)
                            if Inline.colour() and hex then
                                bb:paintRectRGB32(lx, ly + self.lh - band, w, band, Inline.rgb32(hex))
                            else
                                bb:paintRect(lx, ly + self.lh - band, w, band, u.Blitbuffer.COLOR_GRAY_D)
                            end
                        end
                        if m and m.fg and Inline.colour() and Blocks.colorHex("fg", m.fg) then ink = Inline.rgb32(Blocks.colorHex("fg", m.fg)) end
                        u.RenderText:renderUtf8Text(bb, lx, ly + self.base, face, table.concat(parts), false, false, ink)
                        if m and m.s then bb:paintRect(lx, ly + self.base - math.floor(face.size * 0.3), w, 1, color) end
                        if m and m.link then bb:paintRect(lx, ly + self.base + 2, w, 1, color) end
                    else
                        j = j + 1
                    end
                    lx = lx + w
                    c = j
                end
            end
        end
    end
    local size = o.size or 20
    local chars, marks = Blocks.readInline(o.text or "")
    local faces, w = {}, {}
    for k, ch in ipairs(chars) do
        local m = marks[k]
        local f = (m and m.c) and Inline.face(Inline.MONO_SIZE, false, false, true)
            or Inline.face(size, o.bold or (m and m.b), m and m.i)
        faces[k] = f
        w[k] = advance(f, ch)
    end
    local lh, base = metrics(Inline.face(size, o.bold))
    local lines = Inline.wrap(chars, w, o.width)
    local widest = 0
    for _i, l in ipairs(lines) do
        local lw, z = 0, l.z
        while z >= l.a and (chars[z] == " " or chars[z] == "\n") do z = z - 1 end -- (a space hung past the edge isn't counted)
        for k = l.a, z do lw = lw + w[k] end
        l.w = lw
        widest = math.max(widest, lw)
    end
    return Text:new{ chars = chars, marks = marks, faces = faces, w = w, lines = lines, lh = lh, base = base,
        width = o.width, align = o.align, color = o.color, natural = widest,
        dimen = u.Geom:new{ w = o.align and o.width or math.min(o.width, widest), h = #lines * lh } }
end

--- A line of a note's text (`line`: its Markdown) `width` wide, by its kind:
--- a paragraph's words; a quote, grey, a bar at its left; a list item hung
--- from its bullet or number; a rule; nil for a blank line.
function Inline.line(line, width, size)
    local u = UI()
    local c = Inline.classify(line)
    if c.kind == "blank" then return nil end
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    if c.kind == "rule" then
        return VerticalGroup:new{ VerticalSpan:new{ width = S(8) },
            LineWidget:new{ background = u.Blitbuffer.COLOR_GRAY, dimen = u.Geom:new{ w = width, h = math.max(1, S(1)) } },
            VerticalSpan:new{ width = S(8) } }
    end
    if c.kind == "quote" then
        local words = Inline.text{ text = c.text, width = width - S(16), size = size, color = u.Blitbuffer.COLOR_DARK_GRAY }
        return HorizontalGroup:new{ align = "top",
            LineWidget:new{ background = u.Blitbuffer.COLOR_GRAY, dimen = u.Geom:new{ w = S(4), h = words:getSize().h } },
            HorizontalSpan:new{ width = S(12) }, words }
    end
    if c.kind == "bullet" or c.kind == "ordered" then
        local indent = S(24) * (c.depth or 0)
        local gutter = S(30)
        local mark = c.kind == "bullet" and "\u{2022}" or (tostring(c.num) .. ".")
        local mw = TextWidget:new{ text = mark, face = Inline.face(size) }
        local used = mw:getSize().w
        gutter = math.max(gutter, used + S(8))
        return HorizontalGroup:new{ align = "top",
            HorizontalSpan:new{ width = indent + (c.kind == "bullet" and S(8) or 0) }, mw,
            HorizontalSpan:new{ width = gutter - used - (c.kind == "bullet" and S(8) or 0) },
            Inline.text{ text = c.text, width = width - indent - gutter, size = size } }
    end
    return Inline.text{ text = c.text, width = width, size = size }
end

local Grid -- (a table's widget class)
--- Table `t` (Inline.tableAt) at most `width` wide: its head in bold, a line
--- between rows and columns, each cell's words wrapped in its column.
function Inline.table(t, width, size)
    local u = UI()
    if not Grid then
        Grid = u.Widget:extend{}
        function Grid:getSize() return self.dimen end
        function Grid:paintTo(bb, x, y)
            self.dimen.x, self.dimen.y = x, y
            local line, grey = self.line, u.Blitbuffer.COLOR_GRAY
            local w, h = self.dimen.w, self.dimen.h
            local ry = y
            for r, row in ipairs(self.cells) do
                if r == 1 then bb:paintRect(x, ry, w, self.heights[r] + line, u.Blitbuffer.Color8(0xEE)) end
                bb:paintRect(x, ry, w, line, grey)
                local cx = x
                for k, cell in ipairs(row) do
                    local cw = self.cols[k] + 2 * self.pad + line
                    local sz = cell:getSize()
                    local a = self.align[k]
                    local ox = a == "center" and math.floor((self.cols[k] - sz.w) / 2) or a == "right" and (self.cols[k] - sz.w) or 0
                    cell:paintTo(bb, cx + line + self.pad + math.max(0, ox), ry + line + self.pad)
                    cx = cx + cw
                end
                ry = ry + self.heights[r] + line
            end
            bb:paintRect(x, y + h - line, w, line, grey)
            local cx = x
            for k = 1, #self.cols do
                bb:paintRect(cx, y, line, h, grey)
                cx = cx + self.cols[k] + 2 * self.pad + line
            end
            bb:paintRect(x + w - line, y, line, h, grey)
        end
    end
    local n = #t.head
    local pad, line = S(6), math.max(1, S(1))
    local room = width - n * (2 * pad + line) - line
    local all = { t.head }
    for _i, r in ipairs(t.rows) do all[#all + 1] = r end
    -- how wide each column would like to be: its widest cell on one line
    local natural = {}
    for k = 1, n do natural[k] = S(20) end
    for r, row in ipairs(all) do
        for k = 1, n do
            local cell = Inline.text{ text = row[k] or "", width = 100000, size = size, bold = r == 1 }
            natural[k] = math.max(natural[k], cell.natural)
        end
    end
    local cols = Inline.columns(natural, room, S(48))
    local cells, heights = {}, {}
    local total_h = line
    for r, row in ipairs(all) do
        cells[r] = {}
        local rh = 0
        for k = 1, n do
            local cell = Inline.text{ text = row[k] or "", width = cols[k], size = size, bold = r == 1 }
            cells[r][k] = cell
            rh = math.max(rh, cell:getSize().h)
        end
        heights[r] = rh + 2 * pad
        total_h = total_h + heights[r] + line
    end
    local total_w = line
    for k = 1, n do total_w = total_w + cols[k] + 2 * pad + line end
    return Grid:new{ cells = cells, cols = cols, heights = heights, align = t.align, pad = pad, line = line,
        dimen = u.Geom:new{ w = total_w, h = total_h } }
end

--- A run of a note's text lines (their Markdown) as widgets, top to bottom:
--- tables as tables, the rest by Inline.line; a blank line is a gap (one,
--- however many; none first or last).
function Inline.widgets(lines, width, size)
    local VerticalSpan = require("ui/widget/verticalspan")
    local out = {}
    local gap = false
    local i = 1
    while i <= #lines do
        local t = Inline.tableAt(lines, i)
        local w
        if t then
            w = Inline.table(t, width, size)
            i = i + t.n
        else
            w = Inline.line(lines[i], width, size)
            i = i + 1
        end
        if w then
            if gap and #out > 0 then out[#out + 1] = VerticalSpan:new{ width = S(10) } end
            if t and #out > 0 then out[#out + 1] = VerticalSpan:new{ width = S(4) } end
            out[#out + 1] = w
            if t then out[#out + 1] = VerticalSpan:new{ width = S(4) } end
            gap = false
        else
            gap = true
        end
    end
    return out
end

return Inline
