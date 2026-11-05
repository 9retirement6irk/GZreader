--[[--
Downloads (and the other book folders) as bookshelves: the View
"Bookshelf" (common/gz_view.lua).

Drawn over CoverBrowser's tiles mode: when the view is the bookshelf, the
file browser's tiles layout (MosaicMenu _recalculateDimen and
_updateItemsBuildUI) is replaced by this one; every other list keeps its own.

- Shelves fill the page, each with as many spines as fit (ZenOS's Home
  shelf draws them: shelf.lua). The book the 5-way is on, or that was
  tapped, turns to show its cover; tap it again, Press or its letter opens
  it. Hold: the book's menu.
- Folders are spines too (light grey, a tab at the top).
- Audiobooks and Music (GZreader's folders of what's downloaded) stand on
  the top shelf to the right of the books: a cassette walkman with
  headphones and a CD player (icons/shelf/*.svg). In lists and tiles
  they're always first (FileChooser item order, below).
- The sort (Menu → Sort) orders the books as in the other views.

Pages: a page holds rows x spines-per-row items (the widest spine, so they
always fit); on the first page the walkman and the CD player take the room
of the spines they push off.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local Order = require("gzreader_shelforder")
local View = {
    ROW_H = 190,     -- a shelf (px at 160 dpi), books and board
    SPECIAL = Order.SPECIAL,
    SPECIAL_ORDER = Order.SPECIAL_ORDER,
    specialOf = Order.specialOf,
    specialsFirst = Order.specialsFirst,
}

local function Shelf() return require("modules/filebrowser/patches/home/widgets/shelf") end

local root = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"

--- The file browser in the bookshelf view?
function View.applies(menu)
    if type(menu) ~= "table" or menu.name ~= "filemanager" then return false end
    local ok, on = pcall(function() return require("common/gz_view").isBookshelf() end)
    return ok and on == true
end

---------------------------------------------------------------- sizes

local function areaH(row_h)
    return row_h - S(Shelf().BOARD_H) - S(Shelf().UNDER_H) - S(10)
end

local function deviceSize(name, row_h)
    local h = math.floor(areaH(row_h) * 0.74)
    return math.floor(h * View.SPECIAL[name].ratio), h
end

--- Room kept on every shelf for the book turned to show its cover (so
--- turning one never pushes another off the shelf).
local function turnRoom(row_h)
    local face_w = math.floor(areaH(row_h) * 0.88 * 2 / 3) + 2 * S(6) + S(Shelf().PAGES) + S(5)
    return math.max(0, face_w - S(Shelf().MIN_SPINE))
end

--- How many spines' room a device takes.
local function deviceSlots(name, row_h)
    local w = deviceSize(name, row_h)
    return math.ceil((w + S(10)) / S(Shelf().MAX_SPINE))
end

function View.recalculateDimen(menu)
    menu.portrait_mode = Screen:getWidth() <= Screen:getHeight()
    menu.others_height = 0
    if menu.title_bar then
        if not menu.is_borderless then menu.others_height = menu.others_height + 2 end
        if not menu.no_title then menu.others_height = menu.others_height + menu.title_bar.dimen.h end
        if menu.page_info then menu.others_height = menu.others_height + menu.page_info:getSize().h end
    end
    local avail = math.max(S(120), menu.inner_dimen.h - menu.others_height)
    local rows = math.max(1, math.floor(avail / S(View.ROW_H)))
    local width = menu.inner_dimen.w
    local row_h = math.floor(avail / rows)
    local per_row = math.max(3, math.floor((width - S(16) - turnRoom(row_h)) / S(Shelf().MAX_SPINE)))
    -- the special folders at the start of the list: the room they take
    local extra = 0
    for i = 1, math.min(#View.SPECIAL_ORDER + 1, #menu.item_table) do
        local name = View.specialOf(menu.item_table[i])
        if name then extra = extra + deviceSlots(name, row_h) - 1 end
    end
    menu._gz_rows, menu._gz_per_row, menu._gz_row_h, menu._gz_width = rows, per_row, row_h, width
    menu.nb_cols, menu.nb_rows = per_row, rows
    menu.perpage = math.max(1, rows * per_row - extra)
    menu.page_num = math.max(1, math.ceil(#menu.item_table / menu.perpage))
    if menu.page > menu.page_num then menu.page = menu.page_num end
    menu.item_margin = 0
    menu.item_width, menu.item_height = S(Shelf().MAX_SPINE), row_h
    menu.item_dimen = Geom:new{ x = 0, y = 0, w = menu.item_width, h = menu.item_height }
end

---------------------------------------------------------------- books

local function stripExt(name) return (name:gsub("%.[^%.]+$", "")) end

--- What the spine shows: { path, title, authors, series_index, has_real_cover }.
local function bookOf(entry, missing)
    local book = { path = entry.path }
    local ok, BIM = pcall(require, "bookinfomanager")
    local info = ok and BIM:getBookInfo(entry.path, false)
    if info then
        if not info.ignore_meta then
            book.title = info.title
            book.authors = info.authors
            book.series_index = info.series_index
        end
        book.has_real_cover = info.has_cover and not info.ignore_cover and true or false
    elseif missing then
        missing[#missing + 1] = entry.path
    end
    if not book.title or book.title == "" then
        book.title = stripExt(entry.text or entry.path:match("([^/]+)$") or "")
    end
    return book
end

local function folderOf(entry)
    local name = (entry.text or entry.path or ""):gsub("/$", ""):match("([^/]+)$") or "?"
    return { path = entry.path, title = entry.is_go_up and "↑" or name, authors = entry.is_go_up and "" or _("Folder") }
end

---------------------------------------------------------------- an item on a shelf

local Item = InputContainer:extend{
    menu = nil, entry = nil, idx = 0, slot = 0, kind = "book", -- "book", "folder", "special"
    w = 0, h = 0,
}

function Item:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    -- (taps, and Press on the one the 5-way is on: FocusManager sends it a tap)
    local range = function() return self.dimen end
    self.ges_events = {
        TapShelfItem = { GestureRange:new{ ges = "tap", range = range } },
        HoldShelfItem = { GestureRange:new{ ges = "hold", range = range } },
    }
end

function Item:getSize() return Geom:new{ w = self.w, h = self.h } end

function Item:open()
    local menu = self.menu
    UIManager:nextTick(function() menu:onMenuSelect(self.entry) end)
    return true
end

function Item:onTapShelfItem()
    local menu = self.menu
    if self.kind == "book" and menu._gz_picked ~= self.idx then
        View.pick(menu, self.idx)
        return true
    end
    return self:open()
end
function Item:onHoldShelfItem()
    local menu = self.menu
    if menu.onMenuHold then menu:onMenuHold(self.entry) end
    return true
end

local function redraw(menu)
    UIManager:setDirty(menu.show_parent, function()
        return "ui", menu.item_group and menu.item_group.dimen or menu.dimen
    end)
end

function Item:onFocus()
    self.focused = true
    if self.kind == "book" then View.pick(self.menu, self.idx) else redraw(self.menu) end
    return true
end

function Item:onUnfocus()
    self.focused = false
    redraw(self.menu)
    return true
end

function Item:paintTo() end -- (the shelf paints its items)

--- The book picked (turned to show its cover): repaint the shelves.
function View.pick(menu, idx)
    if menu._gz_picked == idx then return end
    menu._gz_picked = idx
    redraw(menu)
end

---------------------------------------------------------------- a shelf row

local Row = WidgetContainer:extend{ w = 0, h = 0 }

function Row:getSize() return Geom:new{ w = self.w, h = self.h } end

local device_cache = {}

local function deviceImage(name, w, h)
    local key = name .. w .. "x" .. h
    if device_cache[key] then return device_cache[key] end
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        return RenderImage:renderSVGImageFile(root .. "/icons/shelf/" .. View.SPECIAL[name].icon .. ".svg", w, h)
    end)
    if not ok or not bb then return nil end
    device_cache[key] = bb
    return bb
end

local function badge(bb, menu, item, x, y, w, h)
    local letter = menu.is_enable_shortcut and menu.item_shortcuts and menu.item_shortcuts[item.slot]
    if not letter then return end
    local side = math.min(S(22), w - S(4))
    if side < S(12) then return end
    local Menu = require("ui/widget/menu")
    local ok, icon = pcall(Menu.getItemShortCutIcon, nil, Geom:new{ w = side, h = side }, letter, "square")
    if not (ok and icon) then return end
    local bx, by = x + math.floor((w - side) / 2), y + h - side - S(4)
    bb:paintRect(bx, by, side, side, Blitbuffer.COLOR_WHITE)
    icon:paintTo(bb, bx, by)
    if icon.free then icon:free() end
end

local function plate(bb, text, cx, y, max_w)
    local tw = TextWidget:new{ text = text, face = Font:getFace("cfont", 11), bold = true, max_width = max_w }
    local s = tw:getSize()
    local pw, ph = s.w + S(10), s.h + S(2)
    local px = cx - math.floor(pw / 2)
    bb:paintRect(px, y, pw, ph, Blitbuffer.gray(0.12))
    bb:paintBorder(px, y, pw, ph, 1, Blitbuffer.gray(0.8))
    tw:paintTo(bb, px + S(5), y + S(1))
    tw:free()
end

function Row:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local menu = self.menu
    local Sh = Shelf()
    local board_y = y + self.h - S(Sh.BOARD_H) - S(Sh.UNDER_H)
    Sh.paintBoard(bb, x, board_y, self.w)
    -- devices on the right (this shelf's room for books ends where they start)
    local right = x + self.w - S(8)
    for k = #self.devices, 1, -1 do
        local d = self.devices[k]
        local img = deviceImage(d.name, d.w, d.h)
        local dx = right - d.w
        local dy = board_y - d.h
        d.item.dimen = Geom:new{ x = dx, y = dy, w = d.w, h = d.h }
        if img then bb:alphablitFrom(img, dx, dy, 0, 0, d.w, d.h) end
        bb:darkenRect(dx + S(6), board_y, d.w - S(6), S(3), 0.35)
        plate(bb, d.label, dx + math.floor(d.w / 2), board_y + S(2), d.w + S(20))
        badge(bb, menu, d.item, dx, dy, d.w, d.h - S(16))
        if d.item.focused then
            bb:paintBorder(dx - S(4), dy - S(4), d.w + S(8), d.h + S(8), S(2), Blitbuffer.COLOR_BLACK)
        end
        right = dx - S(10)
    end
    -- the books (the picked one turned, the ones after it moved along)
    local room_end = right
    local picked
    for i, it in ipairs(self.items) do
        if it.kind == "book" and menu._gz_picked == it.idx then picked = i end
    end
    local face_w = self.cover_w + 2 * S(6) + S(Sh.PAGES) + S(5)
    local px = x + S(8)
    local spans = {}
    for i, it in ipairs(self.items) do
        local w = i == picked and face_w or it.w
        if px + w > room_end then
            it.hidden = true
            it.dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }
        else
            it.hidden = false
            if i == picked then
                if not it.cover then
                    it.cover = require("modules/filebrowser/patches/home/widgets/cover_common").make_cover_widget(it.book,
                        self.cover_w, self.cover_h, { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY })
                end
                local cs = it.cover:getSize()
                local cx, cy = px + S(6), board_y - cs.h - S(Sh.PAGES)
                Sh.paintBook(bb, it.cover, cx, cy, cs.w, cs.h)
                for k = 0, 1 do
                    bb:paintBorder(cx - S(3) - k, cy - S(3) - k, cs.w + 2 * (S(3) + k), cs.h + 2 * (S(3) + k), 1, Blitbuffer.COLOR_BLACK)
                end
                it.dimen = Geom:new{ x = cx, y = cy, w = cs.w, h = cs.h }
                badge(bb, menu, it, cx, cy, cs.w, cs.h)
            else
                local top = board_y - it.h
                it.spine:paintTo(bb, px, top)
                if it.kind == "folder" then
                    -- a folder: a tab on top
                    bb:paintRect(px + S(6), top - S(5), it.w - S(12), S(5), Blitbuffer.gray(0.25))
                    bb:paintBorder(px + S(6), top - S(5), it.w - S(12), S(6), 1, Blitbuffer.gray(0.8))
                end
                it.dimen = Geom:new{ x = px, y = top, w = it.w, h = it.h }
                spans[#spans + 1] = { x = px, w = it.w, h = it.h }
                badge(bb, menu, it, px, top, it.w, it.h)
                if it.focused then
                    bb:paintBorder(px - S(2), top - S(4), it.w + S(4), it.h + S(4), S(2), Blitbuffer.COLOR_BLACK)
                end
            end
            px = px + w
        end
        if i ~= picked and it.cover then it.cover:free(); it.cover = nil end
    end
    Sh.paintDepth(bb, board_y, spans)
end

function Row:free()
    for _i, it in ipairs(self.items or {}) do
        if it.cover then it.cover:free(); it.cover = nil end
    end
end

---------------------------------------------------------------- building a page

local extracting = {} -- path -> true (asked for once)

local function extractMissing(menu, paths)
    local todo = {}
    for _i, p in ipairs(paths) do
        if not extracting[p] then extracting[p] = true; todo[#todo + 1] = { filepath = p, cover_specs = { max_cover_w = S(300), max_cover_h = S(450) } } end
    end
    if #todo == 0 then return end
    local ok, BIM = pcall(require, "bookinfomanager")
    if not ok then return end
    UIManager:nextTick(function()
        if not BIM:extractInBackground(todo) then return end
        local function poll()
            if BIM:isExtractingInBackground() then return UIManager:scheduleIn(1.5, poll) end
            if View.applies(menu) and menu.item_group then pcall(menu.updateItems, menu, nil, true) end
        end
        UIManager:scheduleIn(1.5, poll)
    end)
end

function View.buildUI(menu)
    local Sh = Shelf()
    local VerticalGroup_ok = menu.item_group ~= nil
    if not VerticalGroup_ok then return end
    local rows, row_h, width = menu._gz_rows or 1, menu._gz_row_h or S(View.ROW_H), menu._gz_width or menu.inner_dimen.w
    local area_h = areaH(row_h)
    local ratio = 2 / 3
    pcall(function() ratio = tonumber(require("common/cover_utils").getRatio()) or ratio end)
    local cover_w, cover_h = require("modules/filebrowser/patches/home/widgets/cover_common").uniform_dims(
        math.floor(area_h * 0.88 * ratio), math.floor(area_h * 0.88))
    local first = (menu.page - 1) * menu.perpage
    local books, devices = {}, {}
    local missing = {}
    local select_number
    for slot = 1, menu.perpage do
        local idx = first + slot
        local entry = menu.item_table[idx]
        if not entry then break end
        entry.idx = idx
        if idx == menu.itemnumber then select_number = slot end
        local special = View.specialOf(entry)
        if special then
            local w, h = deviceSize(special, row_h)
            devices[#devices + 1] = { name = special, w = w, h = h, label = View.SPECIAL[special].label,
                item = Item:new{ menu = menu, entry = entry, idx = idx, slot = slot, kind = "special", w = w, h = h } }
        else
            local is_book = entry.is_file and true or false
            local book = is_book and bookOf(entry, missing) or folderOf(entry)
            local look = Sh.look(book, area_h)
            local shade = is_book and look.shade or 0.12
            local item = Item:new{ menu = menu, entry = entry, idx = idx, slot = slot, kind = is_book and "book" or "folder",
                w = look.w, h = is_book and look.h or math.floor(area_h * 0.8), book = book }
            item.spine = Sh.newSpine(book, item.w, item.h, shade)
            books[#books + 1] = item
        end
    end
    -- the rows: books in order, filling each shelf (the first one leaves
    -- room for the devices on its right)
    local device_room = 0
    for _i, d in ipairs(devices) do device_room = device_room + d.w + S(10) end
    local row_items = {}
    local r, x = 1, 0
    local limit = function(rr) return width - S(16) - turnRoom(row_h) - (rr == 1 and device_room or 0) end
    for _i, it in ipairs(books) do
        if x + it.w > limit(r) and x > 0 and r < rows then r, x = r + 1, 0 end
        row_items[r] = row_items[r] or {}
        table.insert(row_items[r], it)
        x = x + it.w
    end
    menu.layout = {}
    if menu._gz_picked and not (menu._gz_picked > first and menu._gz_picked <= first + menu.perpage) then
        menu._gz_picked = nil
    end
    for rr = 1, rows do
        local row = Row:new{ w = width, h = row_h, menu = menu, items = row_items[rr] or {},
            devices = rr == 1 and devices or {}, cover_w = cover_w, cover_h = cover_h }
        table.insert(menu.item_group, row)
        local line = {}
        for _i, it in ipairs(row.items) do line[#line + 1] = it end
        for _i, d in ipairs(row.devices) do line[#line + 1] = d.item end
        if #line > 0 then table.insert(menu.layout, line) end
        -- (taps reach the items through the row)
        for _i, w in ipairs(line) do row[#row + 1] = w end
    end
    if #missing > 0 then extractMissing(menu, missing) end
    return select_number
end

---------------------------------------------------------------- install

--- Put the bookshelf in front of the tiles layout (once; CoverBrowser copies
--- MosaicMenu's functions to the file browser whenever tiles are chosen).
function View.install()
    local ok, MosaicMenu = pcall(require, "mosaicmenu")
    if not ok or MosaicMenu._gz_bookshelf then return end
    local FileChooser = require("ui/widget/filechooser")
    local build, dim = MosaicMenu._updateItemsBuildUI, MosaicMenu._recalculateDimen
    MosaicMenu._gz_bookshelf = true
    MosaicMenu._updateItemsBuildUI = function(menu, ...)
        if View.applies(menu) then return View.buildUI(menu) end
        return build(menu, ...)
    end
    MosaicMenu._recalculateDimen = function(menu, ...)
        if View.applies(menu) then return View.recalculateDimen(menu) end
        return dim(menu, ...)
    end
    if FileChooser._updateItemsBuildUI == build then FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI end
    if FileChooser._recalculateDimen == dim then FileChooser._recalculateDimen = MosaicMenu._recalculateDimen end
    -- Audiobooks and Music first in every view, whatever the sort (the
    -- bookshelf puts them on the right); outermost, after ZenOS's sorting
    local switch = FileChooser.switchItemTable
    FileChooser.switchItemTable = function(fc, title, items, ...)
        if type(items) == "table" and fc.name == "filemanager" then pcall(View.specialsFirst, items) end
        return switch(fc, title, items, ...)
    end
    -- already showing tiles: show the shelves instead
    local okf, FM = pcall(require, "apps/filemanager/filemanager")
    local fc = okf and FM.instance and FM.instance.file_chooser
    if fc and fc.display_mode_type == "mosaic" and View.applies(fc) then pcall(function() fc:refreshPath() end) end
end

return View
