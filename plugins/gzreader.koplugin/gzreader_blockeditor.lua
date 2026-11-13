--[[--
The note editor's block mode (touch Kindles): the note shown as Memos' rich
editor shows it, a block at a time, instead of its Markdown.

  ┌ title: ✕ Edit note        ✎ Drawing   Private ▾ ┐
  [H Head] [• List] [☐ Check] [1. Num] [B] [I] [# Tag] [⌫ Block]  [Save]
  ┌ the blocks, formatted (headings, lists, ticks, bold, italic) ┐
  │ the one being edited has a thick frame; tap another to edit   │
  └──────────────────────────────────────────────────────────────┘
  [ its words, no markers: the text box the keyboard types in ]
  [ keyboard ]

- Tap a block to edit it; its words go in the text box under the blocks
  (no #, -, [ ] or ** to see), and the block shows what you type.
- Enter starts the next block: the next item in a list, a paragraph
  otherwise; Enter on an empty item ends the list. Backspace at the start
  joins the block to the one before (a list item or heading turns into a
  paragraph first). ☐ in a task ticks it.
- The toolbar acts on the block being edited: Head (heading 1 → 2 → 3 →
  text), List / Check / Num (again: back to text), B / I (the word at the
  cursor, or the whole block), # Tag, ⌫ Block (deletes it).
- Blocks it can't take apart (code, quotes, tables, pictures) show as they
  are and edit as their Markdown. The note is written back the way Memos'
  rich editor writes it, unchanged blocks exactly as they were
  (`gzreader_blocks.lua`).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Blocks = require("gzreader_blocks")
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local BE = {}

BE.TOOLS = {
    { id = "heading", label = "H " .. _("Head") },
    { id = "bullet", label = "\u{2022} " .. _("List") },
    { id = "task", label = "\u{2610} " .. _("Check") },
    { id = "ordered", label = "1. " .. _("Num") },
    { id = "bold", label = "B" },
    { id = "italic", label = "I" },
    { id = "tag", label = "# " .. _("Tag") },
    { id = "delete", label = "\u{232B} " .. _("Block") },
}

BE.HEADING_SIZE = { 27, 24, 22, 21, 20, 20 }
BE.TEXT_SIZE = 20

--- The note's blocks for `content` (at least one, to type in).
function BE.document(content)
    local doc = Blocks.parse(content)
    if #doc.blocks == 0 then doc.blocks[1] = Blocks.new("paragraph") end
    return doc
end

--- Where the cursor starts: a new note at its first block, an edit at its
--- last block with words (the end of the note).
function BE.startBlock(doc, is_new)
    if is_new then return doc.blocks[1] end
    for k = #doc.blocks, 1, -1 do
        local b = doc.blocks[k]
        if b.kind ~= "raw" and b.kind ~= "image" and #b.chars > 0 then return b end
    end
    return doc.blocks[#doc.blocks]
end

local function indexOf(doc, b)
    for k, x in ipairs(doc.blocks) do if x == b then return k end end
end
BE.indexOf = indexOf

-- ------------------------------------------------------------- showing

--- The marker a block shows before its words.
function BE.prefix(b, num)
    if b.kind == "bullet" then return "\u{2022}" end
    if b.kind == "task" then return b.done and "\u{2611}" or "\u{2610}" end
    if b.kind == "ordered" then return tostring(num or b.num or 1) .. "." end
end

local function htmlWidget(b, width, size, bold)
    local ok, HtmlBoxWidget = pcall(require, "ui/widget/htmlboxwidget")
    if not ok then return nil end
    local w = HtmlBoxWidget:new{ dimen = Geom:new{ w = width, h = Screen:getHeight() } }
    -- (MuPDF's page has a margin and a serif font of its own: none, and the UI's font)
    local css = "@page { margin: 0; font-family: 'Noto Sans'; } body { margin: 0; padding: 0; line-height: 1.3; } p { margin: 0; }"
        .. (bold and " p { font-weight: bold; }" or "") .. " code { font-family: monospace; }"
    local ok2 = pcall(w.setContent, w, "<p>" .. Blocks.html(b) .. "</p>", css, S(size))
    if not ok2 then return nil end
    local h = w.getSinglePageHeight and w:getSinglePageHeight()
    if h then w.dimen.h = math.ceil(h) end
    return w
end

--- A block, formatted, `width` wide.
function BE.blockWidget(b, width, num)
    if b.kind == "raw" or b.kind == "image" then
        local text = Blocks.textOf(b)
        if b.kind == "image" then text = "\u{1F5BC} " .. (text:match("%((.-)%)") or _("picture")):match("[^/]*$") end
        local box = TextBoxWidget:new{ text = text, face = Font:getFace("infont", 15), width = width - S(12),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        -- (a grey bar beside it: kept as it is, edited as Markdown)
        return HorizontalGroup:new{ align = "top",
            LineWidget:new{ dimen = Geom:new{ w = S(4), h = box:getSize().h }, background = Blitbuffer.COLOR_GRAY },
            HorizontalSpan:new{ width = S(8) },
            box,
        }
    end
    if Blocks.isEmptyParagraph(b) then return VerticalSpan:new{ width = S(18) } end
    local size = b.kind == "heading" and (BE.HEADING_SIZE[b.level or 1] or 20) or BE.TEXT_SIZE
    local bold = b.kind == "heading"
    local prefix = BE.prefix(b, num)
    local pre_w = prefix and S(40) or 0
    local text_w = width - pre_w
    local body
    if Blocks.hasMarks(b) then body = htmlWidget(b, text_w, size, bold) end
    if not body then
        local text = Blocks.textOf(b)
        if text == "" then text = " " end
        body = TextBoxWidget:new{ text = text:gsub("\194\160", " "), face = Font:getFace("cfont", size), bold = bold, width = text_w,
            fgcolor = (b.kind == "task" and b.done) and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK }
    end
    if not prefix then return body end
    -- (the marker in the same face as the words: on the same line)
    return HorizontalGroup:new{ align = "top",
        TextBoxWidget:new{ text = prefix, face = Font:getFace("cfont", size), width = pre_w },
        body,
    }
end

-- ------------------------------------------------------------- the list

local BlockItem = InputContainer:extend{ block = nil, editor = nil, num = nil, current = false, width = nil }

function BlockItem:init()
    local inner = self.width - 2 * S(6) - 2 * Size.border.thick
    self[1] = FrameContainer:new{
        width = self.width, padding = S(6), padding_top = S(3), padding_bottom = S(3), margin = 0, radius = S(4),
        bordersize = self.current and Size.border.thick or 0,
        BE.blockWidget(self.block, inner, self.num),
    }
    self.dimen = Geom:new{ w = self.width, h = self[1]:getSize().h }
    self.ges_events = { TapBlock = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end

function BlockItem:onTapBlock(_arg, ges)
    local e = self.editor
    -- a task's box: ticks it
    if self.block.kind == "task" and ges and ges.pos and ges.pos.x < self.dimen.x + S(6) + S(40) then
        Blocks.toggleDone(self.block)
        BE.render(e)
        return true
    end
    if self.block ~= e.cur then BE.select(e, self.block) end
    return true
end

--- Draws the list of blocks again (the one being edited kept on screen).
function BE.render(e)
    local slot = e.block_slot
    if not slot then return end
    slot:clear()
    local doc, width, area_h = e.doc, e.inner, e.blocks_h
    local cur = indexOf(doc, e.cur) or 1
    -- numbers of numbered items
    local nums, prev = {}, nil
    for k, b in ipairs(doc.blocks) do
        if b.kind == "ordered" then
            nums[k] = (prev and prev.kind == "ordered" and (prev.indent or "") == (b.indent or "")) and (nums[k - 1] + 1) or (b.num or 1)
        end
        prev = b
    end
    local items = {}
    local function item(k)
        if not items[k] then
            items[k] = BlockItem:new{ block = doc.blocks[k], editor = e, num = nums[k], current = k == cur, width = width }
        end
        return items[k]
    end
    -- the first block shown: as before, moved so the current one fits
    local top = math.max(1, math.min(e.block_top or 1, cur))
    local function heightFrom(a, z)
        local h = 0
        for k = a, z do h = h + item(k):getSize().h + S(2) end
        return h
    end
    while top < cur and heightFrom(top, cur) > area_h - S(30) do top = top + 1 end
    e.block_top = top
    local group = VerticalGroup:new{ align = "left" }
    local used = 0
    if top > 1 then
        local more = InputContainer:new{ dimen = Geom:new{ w = width, h = S(24) },
            TextWidget:new{ text = "\u{25B2} " .. _("more above"), face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY } }
        more.ges_events = { TapMore = { GestureRange:new{ ges = "tap", range = function() return more.dimen end } } }
        function more:onTapMore() e.block_top = math.max(1, top - 3); BE.select(e, doc.blocks[math.max(1, top - 1)]); return true end
        group[#group + 1] = more
        used = used + S(24)
    end
    local last = top - 1
    for k = top, #doc.blocks do
        local it = item(k)
        local h = it:getSize().h + S(2)
        if used + h > area_h - S(24) and k > cur then break end
        group[#group + 1] = it
        group[#group + 1] = VerticalSpan:new{ width = S(2) }
        used = used + h
        last = k
    end
    if last < #doc.blocks then
        local more = InputContainer:new{ dimen = Geom:new{ w = width, h = S(24) },
            TextWidget:new{ text = "\u{25BC} " .. _("more below"), face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY } }
        more.ges_events = { TapMore = { GestureRange:new{ ges = "tap", range = function() return more.dimen end } } }
        function more:onTapMore() BE.select(e, doc.blocks[math.min(#doc.blocks, last + 1)]); return true end
        group[#group + 1] = more
    end
    for k, it in pairs(items) do
        local shown = false
        for _i, w in ipairs(group) do if w == it then shown = true end end
        if not shown and it.free then it:free() end
        items[k] = nil
    end
    slot[1] = group
    UIManager:setDirty(e, "ui")
end

-- ------------------------------------------------------------- editing

--- The words of the block being edited, from the text box.
local function syncFromInput(e)
    if not (e.cur and e.input) then return false end
    return Blocks.setText(e.cur, e.input:getText() or "")
end

--- Edits block `b`, the cursor at `pos` (its end when nil). (`synced`: the
--- text box's words are already in the block being edited, or it's gone.)
function BE.select(e, b, pos, synced)
    if not synced then syncFromInput(e) end
    e.cur = b
    local text = Blocks.plain(b)
    e.input:setText(text)
    e.input:moveCursorToCharPos(pos or (#b.chars + 1))
    BE.render(e)
end

--- After a key: the block shows what was typed (a moment later: one redraw for a burst of keys).
function BE.onEdit(e, edited)
    if not edited then return end
    if syncFromInput(e) then
        e.doc.changed = true
        if not e._be_pending then
            e._be_pending = true
            UIManager:scheduleIn(0.4, function()
                e._be_pending = false
                if not e.closed_be then BE.render(e) end
            end)
        end
    end
end

--- Enter: the next block (an item for a list item, a paragraph otherwise).
--- In a block kept as Markdown (code, a table): a new line in it.
function BE.onEnter(e)
    syncFromInput(e)
    local b = e.cur
    if b.kind == "raw" or b.kind == "image" then
        local cb = e.input.enter_callback
        e.input.enter_callback = nil
        e.input:addChars("\n")
        e.input.enter_callback = cb
        return
    end
    local pos = e.input.charpos or (#b.chars + 1)
    local nb = Blocks.split(e.doc, b, pos)
    e.doc.changed = true
    BE.select(e, nb, 1, true)
end

--- Backspace at the start of the block: joins it to the one before. True
--- when it did something (else the key does nothing, as before).
function BE.onBackspaceAtStart(e)
    syncFromInput(e)
    local to, at = Blocks.joinPrevious(e.doc, e.cur)
    if not to then return false end
    e.doc.changed = true
    BE.select(e, to, at, true)
    return true
end

--- A toolbar button, on the block being edited.
function BE.useTool(e, id)
    syncFromInput(e)
    local b = e.cur
    if id == "heading" then
        local level = b.kind == "heading" and (b.level or 1) or 0
        if level >= 3 then Blocks.setKind(b, "heading", level) -- (heading 3 → text)
        else Blocks.setKind(b, "heading", level + 1) end
    elseif id == "bullet" or id == "task" or id == "ordered" then
        Blocks.setKind(b, id)
    elseif id == "bold" or id == "italic" then
        local a, z = Blocks.wordAt(b, e.input.charpos)
        Blocks.toggleMark(b, id == "bold" and "b" or "i", a, z)
    elseif id == "delete" then
        local nb = Blocks.remove(e.doc, b)
        BE.select(e, nb, nil, true)
        return
    elseif id == "tag" then
        return e:pickTag(e.input.charpos)
    end
    e.doc.changed = true
    BE.render(e)
end

--- A tag typed at the cursor of the block being edited.
function BE.insertTag(e, tag)
    local pos = e.input.charpos or 1
    local text = e.input:getText() or ""
    local chars = Blocks.chars(text)
    local before, after = chars[pos - 1], chars[pos]
    -- (a space after only when words follow: Memos writes a space ending a line as &#32;)
    local ins = ((before and not before:match("%s")) and " " or "") .. "#" .. tag
        .. ((after and not after:match("%s")) and " " or "")
    e.input:addChars(ins)
    BE.onEdit(e, true)
    BE.render(e)
end

--- The note as Markdown (what Save sends).
function BE.text(e)
    syncFromInput(e)
    return Blocks.write(e.doc)
end

return BE
