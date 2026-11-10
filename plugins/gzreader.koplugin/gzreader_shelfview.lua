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
- Folders are spines too (light grey, a tab at the top). A series
  (ZenOS's series grouping) is a spine that turns to show its first book's
  cover, the others behind it.
- In Audiobooks, each audiobook is a cassette: its case's spine, turned to
  show the tape with its label and reels; in Music, each album or playlist
  is a CD: its jewel case's spine, turned to show the cover with the disc
  peeking out.
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
    KEYS = 19,       -- letter keys on the shelves: Q to L (not Del; after L, none)
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

--- At most this many shelves on a page: the DX's tall screen fitted six,
--- each book small; four make them bigger. nil: as many as fit.
View.DX_ROWS = 4
function View.maxRows()
    local ok, dx = pcall(function() return require("gzreader_touch").dx() end)
    if ok and dx then return View.DX_ROWS end
    return nil
end

local function areaH(row_h)
    return row_h - S(Shelf().BOARD_H) - S(Shelf().UNDER_H) - S(10)
end

local function deviceSize(name, row_h)
    local h = math.floor(areaH(row_h) * 0.86 * (View.SPECIAL[name].height or 1))
    return math.floor(h * View.SPECIAL[name].ratio), h
end

--- Room kept on every shelf for the book turned to show its cover (so
--- turning one never pushes another off the shelf).
local function turnRoom(row_h)
    local face_w = math.floor(areaH(row_h) * 0.88 * 2 / 3) + 2 * S(6) + S(Shelf().PAGES) + S(5)
    return math.max(0, face_w - S(Shelf().MIN_SPINE))
end

--- An item's width on a shelf, as buildUI makes it (spines' widths come from
--- their path: no book needs reading).
function View.itemWidth(entry)
    local case = View.caseOf(entry)
    if case == "tape" then return S(20) elseif case == "cd" then return S(14) end
    local p = entry.path
    if not entry.is_file and type(entry.series_items) == "table" and type(entry.series_items[1]) == "table" then
        p = entry.series_items[1].path or p -- (a series: its first book's spine)
    end
    if p then return Shelf().look({ path = p }, S(100)).w end
    return Shelf().look({ title = (entry.text or ""):gsub("/$", "") }, S(100)).w
end

--- Do item_table[first + 1 .. first + n] fit on `rows` shelves (the devices
--- on the first one's right, the room for a turned book on each)?
function View.pageFits(items, first, n, rows, row_h, width)
    local device_room, widths = 0, {}
    for i = first + 1, math.min(#items, first + n) do
        local e = items[i]
        local special = View.specialOf(e)
        if special then
            device_room = device_room + deviceSize(special, row_h) + S(10)
        else
            widths[#widths + 1] = View.itemWidth(e)
        end
    end
    local function limit(rr) return width - S(16) - turnRoom(row_h) - (rr == 1 and device_room or 0) end
    local r, x = 1, 0
    for _i, w in ipairs(widths) do
        if x + w > limit(r) and x > 0 then
            if r >= rows then return false end
            r, x = r + 1, 0
        end
        x = x + w
    end
    return x <= limit(r) or #widths == 0
end

--- How many items a page takes: as many as fit on every page, by the books'
--- own widths (it was rows × the widest spine, so a shelf of narrow spines
--- ended with room for three more).
function View.perPage(items, rows, row_h, width)
    local key = table.concat({ tostring(items), #items, rows, row_h, width }, " ")
    if View._per_page and View._per_page.key == key then return View._per_page.n end -- (once per list and size)
    local n = View.countPerPage(items, rows, row_h, width)
    View._per_page = { key = key, n = n }
    return n
end

function View.countPerPage(items, rows, row_h, width)
    local Sh = Shelf()
    local least = math.max(1, rows * math.max(3, math.floor((width - S(16) - turnRoom(row_h)) / S(Sh.MAX_SPINE))) - 2)
    local most = rows * math.max(3, math.floor((width - S(16)) / S(Sh.MIN_SPINE)))
    if #items == 0 then return least end
    for n = most, least + 1, -1 do
        local ok = true
        for first = 0, #items - 1, n do
            if not View.pageFits(items, first, n, rows, row_h, width) then ok = false; break end
        end
        if ok then return n end
    end
    return least
end

function View.recalculateDimen(menu)
    menu.portrait_mode = Screen:getWidth() <= Screen:getHeight()
    menu.others_height = 0
    if menu.title_bar then
        if not menu.is_borderless then menu.others_height = menu.others_height + 2 end
        if not menu.no_title then menu.others_height = menu.others_height + menu.title_bar.dimen.h end
        if menu.page_info then menu.others_height = menu.others_height + menu.page_info:getSize().h end
    end
    local width = menu.inner_dimen.w
    local function plan(avail)
        avail = math.max(S(120), avail)
        local rows = math.max(1, math.floor(avail / S(View.ROW_H)))
        local cap = View.maxRows()
        if cap then rows = math.min(rows, cap) end
        local row_h = math.floor(avail / rows)
        local per_row = math.max(3, math.floor((width - S(16) - turnRoom(row_h)) / S(Shelf().MAX_SPINE)))
        return rows, row_h, per_row, View.perPage(menu.item_table or {}, rows, row_h, width)
    end
    local avail = menu.inner_dimen.h - menu.others_height
    local rows, row_h, per_row, perpage = plan(avail)
    -- one page: no page arrows, so the shelves take their room too and the
    -- bottom one stands on the tab bar (as on Home)
    local footer = menu.page_info and menu.page_info:getSize().h or 0
    if footer > 0 then
        local r2, h2, p2, pp2 = plan(avail + footer)
        if #menu.item_table <= pp2 then rows, row_h, per_row, perpage = r2, h2, p2, pp2 end
    end
    menu._gz_rows, menu._gz_per_row, menu._gz_row_h, menu._gz_width = rows, per_row, row_h, width
    menu.nb_cols, menu.nb_rows = per_row, rows
    menu.perpage = perpage
    menu.page_num = math.max(1, math.ceil(#menu.item_table / menu.perpage))
    if menu.page > menu.page_num then menu.page = menu.page_num end
    menu.item_margin = 0
    menu.item_width, menu.item_height = S(Shelf().MAX_SPINE), row_h
    menu.item_dimen = Geom:new{ x = 0, y = 0, w = menu.item_width, h = menu.item_height }
end

---------------------------------------------------------------- books

local function stripExt(name) return (name:gsub("%.[^%.]+$", "")) end

--- What the spine shows: { path, title, authors, series_index, has_real_cover }.
--- The authors Grimmory has for a downloaded book (its download entry), or nil.
function View.grimmoryAuthors(path)
    local store = View.plugin and View.plugin.store
    for _id, e in pairs(store and store.downloads or {}) do
        if type(e) == "table" and e.path == path then
            return type(e.authors) == "string" and e.authors ~= "" and e.authors or nil
        end
    end
    return nil
end

--- A book's KOReader custom metadata (custom_props), read once and kept
--- until its file changes: it was read from disk for every spine each time
--- a shelf page was built.
local lfs = require("libs/libkoreader-lfs")
local custom_cache = {}
function View.customProps(path)
    local DocSettings = require("docsettings")
    local file = DocSettings:findCustomMetadataFile(path)
    if not file then custom_cache[path] = nil; return nil end
    local mtime = lfs.attributes(file, "modification") or 0
    local c = custom_cache[path]
    if c and c.file == file and c.mtime == mtime then return c.props end
    local okr, props = pcall(function() return DocSettings.openSettingsFile(file):readSetting("custom_props") end)
    props = okr and type(props) == "table" and props or nil
    custom_cache[path] = { file = file, mtime = mtime, props = props }
    return props
end

local function bookOf(entry, missing)
    local book = { path = entry.path }
    local ok, BIM = pcall(require, "bookinfomanager")
    local info = ok and BIM:getBookInfo(entry.path, false)
    if info then
        if not info.ignore_meta then
            -- (with the book's KOReader custom metadata: GZreader writes
            -- Grimmory's title and authors there; 1.22.3 left them off the spine)
            local custom = View.customProps(entry.path) or {}
            local p = { title = custom.title or info.title, authors = custom.authors or info.authors,
                series_index = custom.series_index or info.series_index }
            book.title = p.title or info.title
            book.authors = p.authors or info.authors
            book.series_index = p.series_index or info.series_index
        end
        book.has_real_cover = info.has_cover and not info.ignore_cover and true or false
    elseif missing then
        missing[#missing + 1] = entry.path
    end
    if not book.title or book.title == "" then
        book.title = stripExt(entry.text or entry.path:match("([^/]+)$") or "")
    end
    if not book.authors or book.authors == "" then
        -- the file has none: the authors Grimmory has for it
        book.authors = View.grimmoryAuthors and View.grimmoryAuthors(entry.path) or nil
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

local TURNS = { book = true, series = true, tape = true, cd = true }

function Item:onTapShelfItem()
    local menu = self.menu
    if TURNS[self.kind] and menu._gz_picked ~= self.idx then
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

--- The shelf (row) an item stands on.
local function rowOf(menu, idx)
    if not idx then return nil end
    for _i, row in ipairs(menu.item_group or {}) do
        for _j, it in ipairs(row.items or {}) do if it.idx == idx then return row end end
        for _j, d in ipairs(row.devices or {}) do if d.item and d.item.idx == idx then return row end end
    end
end

--- Repaint, the screen updated only where the shelves changed (the rows
--- given; all of them when they aren't known yet). Every 5-way step
--- updated the whole page before 1.23.7: slow on a Kindle 3.
local function redraw(menu, ...)
    local rect
    for _i, row in ipairs({ ... }) do
        if row and row.dimen and row.dimen.w > 0 then
            rect = rect and rect:combine(row.dimen) or row.dimen:copy()
        end
    end
    UIManager:setDirty(menu.show_parent, function()
        return "ui", rect or (menu.item_group and menu.item_group.dimen) or menu.dimen
    end)
    if rect then View.rowsOnly(menu) end
end
View.rowOf = rowOf

--- The 5-way moved along the shelves: KOReader's focus manager then asks
--- for the whole screen to be updated as well ("fast", no region), which
--- took in the shelves' own update (KOReader joins overlapping updates).
--- That one request, right after, only repaints: the shelves' update is
--- enough. (Kept for the move under way: cleared on the next tick.)
function View.rowsOnly(menu)
    View.rows_only = menu
    UIManager:nextTick(function() if View.rows_only == menu then View.rows_only = nil end end)
end
if UIManager.setDirty then
    local orig = UIManager.setDirty
    UIManager.setDirty = function(um, widget, refreshtype, region, ...)
        local m = View.rows_only
        if m and refreshtype == "fast" and region == nil and widget ~= nil
                and (widget == m.show_parent or widget == m) then
            View.rows_only = nil
            return orig(um, widget, function() return nil end)
        end
        return orig(um, widget, refreshtype, region, ...)
    end
end

function Item:onFocus()
    self.focused = true
    if TURNS[self.kind] then View.pick(self.menu, self.idx) else redraw(self.menu, rowOf(self.menu, self.idx)) end
    return true
end

function Item:onUnfocus()
    self.focused = false
    redraw(self.menu, rowOf(self.menu, self.idx))
    return true
end

function Item:paintTo() end -- (the shelf paints its items)

--- The book picked (turned to show its cover): repaint the shelves.
function View.pick(menu, idx)
    if menu._gz_picked == idx then return end
    local was = menu._gz_picked
    menu._gz_picked = idx
    -- (the shelf it was turned on, and the one it is now)
    redraw(menu, rowOf(menu, was), rowOf(menu, idx))
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
    local letter = item.slot <= View.KEYS and menu.is_enable_shortcut and menu.item_shortcuts and menu.item_shortcuts[item.slot]
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

---------------------------------------------------------------- tapes and CDs

local function gray(v) return Blitbuffer.gray(math.max(0, math.min(1, v))) end

--- Text running up a strip w x h (a case's spine), on `bg`.
local function spineText(bb, x, y, w, h, text, bg, ink, size)
    local lying = Blitbuffer.new(h, w, Blitbuffer.TYPE_BB8)
    lying:fill(bg)
    local t = TextWidget:new{ text = text, face = Font:getFace("cfont", size or 9), bold = true, fgcolor = ink, max_width = h - S(8) }
    local ts = t:getSize()
    t:paintTo(lying, math.floor((h - ts.w) / 2), math.floor((w - ts.h) / 2))
    t:free()
    local stood = lying:rotatedCopy(270)
    lying:free()
    bb:blitFrom(stood, x, y, 0, 0, w, h)
    stood:free()
end

--- A cassette case standing, its spine out: the J-card's spine with the title.
local function tapeSpine(bb, x, y, w, h, title)
    bb:paintRect(x, y, w, h, gray(0.55))
    spineText(bb, x + S(3), y + S(3), w - S(6), h - S(6), title, Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK, 9)
    bb:paintRect(x + S(3), y + S(3), w - S(6), S(4), gray(0.85))
    bb:paintBorder(x, y, w, h, 1, gray(0.95))
    Shelf().shadeRound(bb, x, y, w, h, 0.5)
end

--- A CD's jewel case standing, its spine out.
local function cdSpine(bb, x, y, w, h, title, shade)
    local ink = shade >= 0.5 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, y, w, h, gray(shade))
    spineText(bb, x + 1, y + S(4), w - 2, h - S(8), title, gray(shade), ink, 8)
    bb:paintBorder(x, y, w, h, 1, gray(0.9))
    -- the clear case's edges catching the light
    bb:paintRect(x + 1, y + 1, 1, h - 2, gray(0.15))
    Shelf().shadeRound(bb, x, y, w, h, 0.4)
end

--- The tape itself, turned to face out (w x h, its foot on `bottom`).
local function tapeFront(bb, x, bottom, w, h, title, cover)
    local y = bottom - h
    bb:darkenRect(x + S(4), y + S(4), w, h, 0.3)
    bb:paintRoundedRect(x, y, w, h, gray(0.7), S(5))
    bb:paintBorder(x, y, w, h, 1, gray(0.95), S(5))
    -- screws in the corners
    for _i, c in ipairs({ { S(6), S(6) }, { w - S(7), S(6) }, { S(6), h - S(7) }, { w - S(7), h - S(7) } }) do
        bb:paintCircle(x + c[1], y + c[2], math.max(2, S(2)), gray(0.25))
    end
    -- the label: its cover, the title, the window with the reels
    local lx, ly, lw, lh = x + S(10), y + S(8), w - S(20), math.floor(h * 0.62)
    bb:paintRect(lx, ly, lw, lh, gray(0.03))
    bb:paintRect(lx, ly, lw, S(5), gray(0.6))
    local tx = lx + S(4)
    if cover then
        local cs = math.min(lh - S(12), S(40))
        local cw = cover:getSize()
        pcall(function() cover:paintTo(bb, lx + S(4), ly + S(8)) end)
        tx = lx + S(8) + math.min(cs, cw.w)
    end
    local t = TextWidget:new{ text = title, face = Font:getFace("cfont", 11), bold = true, max_width = lx + lw - tx - S(4) }
    t:paintTo(bb, tx, ly + S(8))
    t:free()
    local wy = ly + math.floor(lh * 0.55)
    local ww, wh = math.floor(lw * 0.55), math.floor(lh * 0.32)
    local wx = lx + math.floor((lw - ww) / 2)
    bb:paintRoundedRect(wx, wy, ww, wh, gray(0.35), math.floor(wh / 2))
    for _i, cx in ipairs({ wx + math.floor(wh / 2) + S(2), wx + ww - math.floor(wh / 2) - S(2) }) do
        local r = math.floor(wh / 2) - S(2)
        bb:paintCircle(cx, wy + math.floor(wh / 2), r, Blitbuffer.COLOR_WHITE)
        bb:paintCircle(cx, wy + math.floor(wh / 2), math.max(2, math.floor(r * 0.45)), gray(0.7))
    end
    -- the head opening at the foot
    local hw = math.floor(w * 0.5)
    for i = 0, S(9) - 1 do
        local inset = math.floor((S(9) - i) * S(5) / S(9))
        bb:paintRect(x + math.floor((w - hw) / 2) - S(5) + inset, bottom - S(9) + i, hw + 2 * S(5) - 2 * inset, 1, gray(0.85))
    end
end

--- The CD turned to face out: its case with the cover, the disc peeking out.
local function cdFront(bb, x, bottom, side, cover)
    local y = bottom - side
    -- the disc behind, out on the right
    local r = math.floor(side * 0.46)
    local cx, cy = x + side - math.floor(r * 0.35), y + math.floor(side / 2)
    bb:paintCircle(cx, cy, r, gray(0.25))
    bb:paintCircle(cx, cy, r - S(2), gray(0.12))
    for k = 1, 3 do bb:paintCircle(cx, cy, math.floor(r * (0.4 + 0.15 * k)), gray(0.2), 1) end
    bb:paintCircle(cx, cy, math.floor(r * 0.18), Blitbuffer.COLOR_WHITE)
    bb:paintCircle(cx, cy, math.floor(r * 0.08), gray(0.5))
    -- the case
    bb:darkenRect(x + S(4), y + S(4), side, side, 0.3)
    bb:paintRect(x, y, side, side, gray(0.2))
    if cover then pcall(function() cover:paintTo(bb, x + S(7), y + S(2)) end) end
    bb:paintRect(x, y, S(6), side, gray(0.55)) -- the hinge
    bb:paintRect(x + S(6), y, 1, side, gray(0.9))
    bb:paintBorder(x, y, side, side, 1, gray(0.95))
    -- a glare across the clear front
    for i = 0, S(10) do bb:lightenRect(x + side - S(30) + i, y + S(4) + i, S(3), 1, 0.4) end
end

function Row:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local menu = self.menu
    local Sh = Shelf()
    local board_y = y + self.h - S(Sh.BOARD_H) - S(Sh.UNDER_H)
    Sh.paintBoard(bb, x, board_y, self.w)
    if self.note then
        local title = TextWidget:new{ text = self.note[1], face = Font:getFace("cfont", 22), bold = true, max_width = self.w - S(32) }
        local line = require("ui/widget/textboxwidget"):new{ text = self.note[2], face = Font:getFace("cfont", 16),
            width = self.w - S(48), alignment = "center" }
        local th, lh = title:getSize().h, line:getSize().h
        local ty = y + math.floor((board_y - y - th - S(8) - lh) / 2)
        title:paintTo(bb, x + math.floor((self.w - title:getSize().w) / 2), ty)
        line:paintTo(bb, x + S(24), ty + th + S(8))
        title:free(); line:free()
    end
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
        if TURNS[it.kind] and menu._gz_picked == it.idx then picked = i end
    end
    local face_w = self.cover_w + 2 * S(6) + S(Sh.PAGES) + S(5)
    local px = x + S(8)
    local spans = {}
    for i, it in ipairs(self.items) do
        local w = i == picked and (it.face_w or face_w) or it.w
        if px + w > room_end then
            it.hidden = true
            it.dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }
        else
            it.hidden = false
            if i == picked and (it.kind == "tape" or it.kind == "cd") then
                local CC = require("modules/filebrowser/patches/home/widgets/cover_common")
                if it.kind == "tape" then
                    local th = it.face_h
                    if not it.cover then
                        local cs = math.min(math.floor(th * 0.62) - S(12), S(40))
                        it.cover = CC.make_cover_widget(it.book, cs, cs, { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY, uniform = false })
                    end
                    tapeFront(bb, px + S(4), board_y, it.face_w - S(10), th, it.book.title or "", it.cover)
                    it.dimen = Geom:new{ x = px + S(4), y = board_y - th, w = it.face_w - S(10), h = th }
                else
                    local side = it.face_h
                    if not it.cover then
                        it.cover = CC.make_cover_widget(it.book, side - S(9), side - S(4), { border = 0, background = Blitbuffer.COLOR_LIGHT_GRAY, uniform = false })
                    end
                    cdFront(bb, px + S(4), board_y, side, it.cover)
                    it.dimen = Geom:new{ x = px + S(4), y = board_y - side, w = side, h = side }
                end
                local d = it.dimen
                for k = 0, 1 do
                    bb:paintBorder(d.x - S(3) - k, d.y - S(3) - k, d.w + 2 * (S(3) + k), d.h + 2 * (S(3) + k), 1, Blitbuffer.COLOR_BLACK)
                end
                badge(bb, menu, it, d.x, d.y, d.w, d.h)
            elseif i == picked then
                if not it.cover then
                    it.cover = require("modules/filebrowser/patches/home/widgets/cover_common").make_cover_widget(it.book,
                        self.cover_w, self.cover_h, { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY })
                end
                if it.kind == "series" then
                    -- the series' other books behind its first
                    local cs0 = it.cover:getSize()
                    for k = 2, 1, -1 do
                        local ox, oy = px + S(6) + k * S(5), board_y - cs0.h - S(Sh.PAGES) - k * S(4)
                        bb:paintRect(ox, oy, cs0.w, cs0.h, Blitbuffer.gray(0.25 + 0.2 * k))
                        bb:paintBorder(ox, oy, cs0.w, cs0.h, 1, Blitbuffer.COLOR_BLACK)
                    end
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
                if it.kind == "tape" then tapeSpine(bb, px, top, it.w, it.h, it.book.title or "")
                elseif it.kind == "cd" then cdSpine(bb, px, top, it.w, it.h, it.book.title or "", it.shade or 0.3)
                else it.spine:paintTo(bb, px, top) end
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

--- "tape" for an audiobook in Audiobooks, "cd" for an album or playlist in
--- Music (GZreader's stand-ins in its own folders), else nil.
function View.caseOf(entry)
    local path = type(entry) == "table" and entry.is_file and entry.path
    if type(path) ~= "string" then return nil end
    local dir = path:match("^(.*)/[^/]+$")
    local name = dir and dir:match("([^/]+)$")
    local home = G_reader_settings:readSetting("home_dir")
    home = home and home:gsub("/+$", "")
    if not (name and home and dir == home .. "/" .. name) then return nil end
    if name == "Audiobooks" then return "tape" end
    if name == "Music" then return "cd" end
    return nil
end

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
            local series = not is_book and (entry.is_series_group or type(entry.series_items) == "table")
            local case = is_book and View.caseOf(entry) -- "tape" / "cd" in Audiobooks / Music
            local book
            if series then
                -- a series: its first book's cover when it turns, its name on the spine
                local first_book = type(entry.series_items) == "table" and entry.series_items[1]
                book = first_book and bookOf(first_book, missing) or folderOf(entry)
                book.title = (entry.text or ""):gsub("/$", "")
                book.series_index = nil
                book.group_label = entry.path
            else
                book = is_book and bookOf(entry, missing) or folderOf(entry)
            end
            local look = Sh.look(book, area_h)
            local shade = (is_book or series) and look.shade or 0.12
            local kind = case or (series and "series") or (is_book and "book") or "folder"
            local item = Item:new{ menu = menu, entry = entry, idx = idx, slot = slot, kind = kind,
                w = look.w, h = (is_book or series) and look.h or math.floor(area_h * 0.8), book = book }
            if case then book.cover_w, book.cover_h = 1, 1 end -- (square: an audiobook's or album's cover)
            if case == "tape" then
                item.w, item.h = S(20), math.floor(area_h * 0.52)
                item.face_h = math.floor(area_h * 0.5)
                item.face_w = math.floor(item.face_h * 1.55) + S(14)
            elseif case == "cd" then
                item.w, item.h, item.shade = S(14), math.floor(area_h * 0.58), shade
                item.face_h = math.floor(area_h * 0.6)
                item.face_w = item.face_h + math.floor(item.face_h * 0.3) + S(10)
            else
                item.spine = Sh.newSpine(book, item.w, item.h, shade)
            end
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
    -- nothing here yet (the GZreader folder with no books): say what fills it,
    -- on the top shelf (ZenOS's "No books found" + "Set home folder" went under
    -- the shelves, over the tab bar, until 1.23.11)
    menu._gz_shelves = true
    local note
    if #books == 0 and #devices == 0 and menu.page == 1 then
        note = { _("No books yet"), _("Books you download from the Catalog tab appear here.") }
    end
    for rr = 1, rows do
        local row = Row:new{ w = width, h = row_h, menu = menu, items = row_items[rr] or {},
            devices = rr == 1 and devices or {}, cover_w = cover_w, cover_h = cover_h, note = rr == 1 and note or nil }
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
    -- letter keys: Q to L only (KEYS); after L an item has none, and Del and
    -- the bottom row's letters (the tab bar's) aren't taken for the shelves
    local select_key = FileChooser.onSelectByShortCut
    FileChooser.onSelectByShortCut = function(fc, arg, keyevent)
        if View.applies(fc) and type(keyevent) == "table" then
            for k, v in ipairs(fc.item_shortcuts or {}) do
                if v == keyevent.key then
                    if k > View.KEYS then return false end
                    break
                end
            end
        end
        return select_key(fc, arg, keyevent)
    end
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
