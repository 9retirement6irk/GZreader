--[[--
Covers in the Grimmory tab: book lists drawn like Downloads, following the
same Display choice (Menu → Display): List with details (cover, title,
author, format and progress), Tiles (a 3 x 3 grid of covers) or Simple list
(KOReader's text list, no covers).

Applied to the browser's Menu by replacing its updateItems for book lists
(lists whose entries carry .book). Other lists (the root, libraries,
authors…) stay KOReader's text list. Covers come from gzreader_covers.lua:
what's missing on the page is fetched in the background and the page is
redrawn when it arrives.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Covers = require("gzreader_covers")

local Screen = Device.screen

local CoverMenu = {
    LIST_PER_PAGE = 6,
    COLS = 3,
    ROWS = 3,
}

function CoverMenu.mode()
    local ok, HM = pcall(require, "gzreader_homemenu")
    return ok and HM.displayMode() or "list_image_meta"
end

local function coverOf(entry)
    local book = entry and entry.book
    if type(book) ~= "table" or not book.id then return nil end
    return book.id, entry.cover_kind
end

function CoverMenu.hasBooks(items)
    for _i, e in ipairs(items or {}) do
        if coverOf(e) then return true end
    end
    return false
end

---------------------------------------------------------------- one item

local Item = InputContainer:extend{
    entry = nil,
    menu = nil,
    dimen = nil,
    shortcut = nil,
    shortcut_style = "square",
    mosaic = false,
}

local function placeholder(w, h, text)
    return FrameContainer:new{
        width = w, height = h, padding = 0, margin = 0,
        bordersize = Size.border.thin, color = Blitbuffer.COLOR_DARK_GRAY,
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * Size.border.thin, h = h - 2 * Size.border.thin },
            text and TextBoxWidget:new{
                text = text, face = Font:getFace("cfont", 11), width = w - Screen:scaleBySize(8),
                alignment = "center", height = h - Screen:scaleBySize(8), height_adjust = true,
                height_overflow_show_ellipsis = true,
            } or VerticalSpan:new{ width = 0 },
        },
    }
end

local function coverWidget(entry, w, h)
    local id, kind = coverOf(entry)
    local bb = id and Covers.image(id, kind, w, h)
    if bb then
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            FrameContainer:new{
                padding = 0, margin = 0, bordersize = Size.border.thin,
                ImageWidget:new{ image = bb, image_disposable = false },
            },
        }
    end
    local title = entry.book and entry.book.title or entry.text
    return placeholder(w, h, title)
end

function Item:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    local w, h = self.dimen.w, self.dimen.h
    local pad = Screen:scaleBySize(6)
    local sc_side = Screen:scaleBySize(26)
    local shortcut = self.shortcut and self.menu:getItemShortCutIcon(
        Geom:new{ w = sc_side, h = sc_side }, self.shortcut, self.shortcut_style)
    local entry = self.entry
    local content
    if self.mosaic then
        local title_h = Screen:scaleBySize(20)
        local cw, ch = w - 2 * pad, h - title_h - 3 * pad
        local cover = coverOf(entry) and coverWidget(entry, cw, ch) or placeholder(cw, ch, entry.text)
        local title = entry.book and (entry.book.title or entry.text) or entry.text or ""
        local stack = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = pad },
            cover,
            VerticalSpan:new{ width = pad },
            TextWidget:new{ text = title, face = Font:getFace("cfont", 13), max_width = w - 2 * pad },
        }
        content = OverlapGroup:new{
            dimen = Geom:new{ w = w, h = h - Size.line.thick },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = h - Size.line.thick }, stack },
        }
        if shortcut then
            table.insert(content, LeftContainer:new{
                dimen = Geom:new{ w = sc_side + pad, h = sc_side + pad },
                HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, shortcut },
            })
        end
    else
        local cover_h = h - 2 * pad
        local cover_w = math.floor(cover_h * 0.71)
        local row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = Size.padding.fullscreen } }
        if shortcut then
            table.insert(row, shortcut)
            table.insert(row, HorizontalSpan:new{ width = Size.span.horizontal_default })
        end
        local has_cover = coverOf(entry) ~= nil
        if has_cover then
            table.insert(row, coverWidget(entry, cover_w, cover_h))
            table.insert(row, HorizontalSpan:new{ width = Screen:scaleBySize(10) })
        end
        local used = Size.padding.fullscreen * 2 + (shortcut and (sc_side + Size.span.horizontal_default) or 0)
            + (has_cover and (cover_w + Screen:scaleBySize(10)) or 0)
        local text_w = w - used
        local texts = VerticalGroup:new{ align = "left" }
        local book = entry.book
        if book then
            local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
            table.insert(texts, TextBoxWidget:new{
                text = entry.gz_title or book.title or entry.text, face = Font:getFace("cfont", 19), bold = true,
                width = text_w, height = Screen:scaleBySize(50), height_adjust = true,
                height_overflow_show_ellipsis = true,
            })
            if authors ~= "" then
                table.insert(texts, TextWidget:new{ text = authors, face = Font:getFace("cfont", 16), max_width = text_w })
            end
            if entry.mandatory and entry.mandatory ~= "" then
                table.insert(texts, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                table.insert(texts, TextWidget:new{ text = entry.mandatory, face = Font:getFace("cfont", 14),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w })
            end
        else
            table.insert(texts, TextWidget:new{ text = entry.text or "", face = Font:getFace("cfont", 19), max_width = text_w })
        end
        table.insert(row, texts)
        content = LeftContainer:new{ dimen = Geom:new{ w = w, h = h - Size.line.thick }, row }
    end
    self._underline_container = UnderlineContainer:new{
        vertical_align = "center",
        dimen = Geom:new{ w = w, h = h },
        linesize = Size.line.thick,
        color = self.mosaic and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_LIGHT_GRAY,
        content,
    }
    self[1] = FrameContainer:new{ bordersize = 0, padding = 0, self._underline_container }
end

function Item:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function Item:onUnfocus()
    self._underline_container.color = self.mosaic and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_LIGHT_GRAY
    return true
end

function Item:onTapSelect()
    if not self[1].dimen then return end
    self.menu:onMenuSelect(self.entry)
    return true
end

function Item:onHoldSelect()
    if not self[1].dimen then return end
    self.menu:onMenuHold(self.entry)
    return true
end

---------------------------------------------------------------- the page

--- Draw the current page of `m` (a book list) as cover rows or tiles.
function CoverMenu.build(m, plugin, mode, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    m:_recalculateDimen(no_recalculate_dimen)
    local per = m.perpage
    local offset = (m.page - 1) * per
    local entries = {}
    for i = 1, per do
        local e = m.item_table[offset + i]
        if not e then break end
        e.idx = offset + i
        if offset + i == m.itemnumber then select_number = i end
        entries[#entries + 1] = e
    end
    local function shortcutFor(i)
        if not m.is_enable_shortcut then return nil end
        return m.item_shortcuts[i], (i < 11 or i > 20) and "square" or "grey_square"
    end
    local wanted = {}
    if mode == "mosaic_image" then
        local cols = CoverMenu.COLS
        local cell_w = math.floor(m.item_dimen.w / cols)
        local cell_h = math.floor(m.available_height / CoverMenu.ROWS)
        local row, layout_row
        for i, e in ipairs(entries) do
            if (i - 1) % cols == 0 then
                row = HorizontalGroup:new{ align = "top" }
                layout_row = {}
                table.insert(m.item_group, row)
                table.insert(m.layout, layout_row)
            end
            local sc, style = shortcutFor(i)
            local item = Item:new{ entry = e, menu = m, mosaic = true, shortcut = sc, shortcut_style = style,
                dimen = Geom:new{ w = cell_w, h = cell_h }, show_parent = m.show_parent }
            table.insert(row, item)
            table.insert(layout_row, item)
            local id, kind = coverOf(e)
            if id then wanted[#wanted + 1] = { id = id, kind = kind } end
        end
    else
        for i, e in ipairs(entries) do
            local sc, style = shortcutFor(i)
            local item = Item:new{ entry = e, menu = m, shortcut = sc, shortcut_style = style,
                dimen = m.item_dimen:copy(), show_parent = m.show_parent }
            table.insert(m.item_group, item)
            table.insert(m.layout, { item })
            local id, kind = coverOf(e)
            if id then wanted[#wanted + 1] = { id = id, kind = kind } end
        end
    end
    m:updatePageInfo(select_number)
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    -- covers not on the Kindle yet: fetch this page's, then redraw it
    local page, items = m.page, m.item_table
    Covers.fetch(plugin, wanted, function(got)
        if got > 0 and m.page == page and m.item_table == items and not m._gz_closed then
            local sel = m.selected and m.layout[m.selected.y]
                and ((m.selected.y - 1) * #m.layout[1] + m.selected.x) or nil
            m.itemnumber = sel and (offset + sel) or nil
            m:updateItems()
        end
    end)
end

CoverMenu.open_menus = setmetatable({}, { __mode = "k" })

--- Redraw open Grimmory tab lists (after Menu → Display changed the view).
function CoverMenu.refresh()
    for m in pairs(CoverMenu.open_menus) do
        if not m._gz_closed then pcall(m.updateItems, m) end
    end
end

--- Take over `menu`'s drawing for book lists.
function CoverMenu.apply(menu, plugin)
    if menu._gz_covermenu then return end
    menu._gz_covermenu = true
    CoverMenu.open_menus[menu] = true
    local orig_update = menu.updateItems
    menu.updateItems = function(m, select_number, no_recalculate_dimen)
        local mode = CoverMenu.mode()
        if (mode == "list_image_meta" or mode == "mosaic_image") and CoverMenu.hasBooks(m.item_table) then
            local per = mode == "mosaic_image" and CoverMenu.COLS * CoverMenu.ROWS or CoverMenu.LIST_PER_PAGE
            if m.items_per_page ~= per then
                m.items_per_page = per
                no_recalculate_dimen = false
            end
            return CoverMenu.build(m, plugin, mode, select_number, no_recalculate_dimen)
        end
        if m.items_per_page then
            m.items_per_page = nil
            no_recalculate_dimen = false
        end
        return orig_update(m, select_number, no_recalculate_dimen)
    end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        m._gz_closed = true
        CoverMenu.open_menus[m] = nil
        Covers.release()
        if orig_close then return orig_close(m, ...) end
    end
end

return CoverMenu
