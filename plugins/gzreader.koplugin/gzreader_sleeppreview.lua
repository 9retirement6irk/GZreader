--[[--
Settings → General → Sleep → Wallpaper: each sleep screen as a tile with a
small preview of what it shows, instead of a list of radio buttons.

  * GZreader's own (the default): the book's cover while reading, a picture
    from the screensavers folder elsewhere: half of each;
  * Book cover: the last book's cover;
  * A picture from the screensavers folder (a different one each time);
  * With an Immich album chosen (gzreader_immich.lua): the book's cover while
    reading and an Immich picture elsewhere, or an Immich picture always;
  * Reading progress (needs reading statistics), Book status;
  * Leave the screen as it is: what the screen showed when Wallpaper opened.

Tap a tile, or on a Kindle with keys press its letter or move to it with the
5-way and press. Back, Menu, the × or a tap outside the tiles close it.
The choice is saved as the menu saved it (screensaver_type,
gzreader_sleep_auto, gzreader_sleep_source: frontend/gzsleepmode.lua); the other sleep-screen settings are under
Wallpaper options (frontend/ui/elements/screensaver_menu.lua).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FocusManager = require("ui/widget/focusmanager")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Screen = Device.screen
local function S(n) return Screen:scaleBySize(n) end

local P = {
    KEYS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    COLUMNS = 3,
    -- where a random picture comes from (screensaver.lua's order)
    PICTURE_DIRS = { "/mnt/us/screensavers", "/opt/amazon/screen_saver/600x800" },
}

local function ui()
    local okr, ReaderUI = pcall(require, "apps/reader/readerui")
    local okf, FileManager = pcall(require, "apps/filemanager/filemanager")
    return (okr and ReaderUI.instance) or (okf and FileManager.instance) or nil
end

local function lastFile()
    local f = G_reader_settings:readSetting("lastfile")
    if type(f) == "string" and lfs.attributes(f, "mode") == "file" then return f end
end

--- The choices, in order: { id, label, enabled }.
function P.choices()
    local u = ui()
    local immich = G_reader_settings:readSetting("gzreader_immich_album") ~= nil
        or require("gzsleepmode").source(G_reader_settings) == "immich"
    local list = {
        { id = "auto", label = _("Book cover while reading, a picture elsewhere"), enabled = true },
        { id = "cover", label = _("Book cover"), enabled = lastFile() ~= nil },
        { id = "random_image", label = _("A picture from the screensavers folder"), enabled = true },
        -- (with an Immich album: Settings → Connections → Immich)
        immich and { id = "immich_auto", label = _("Book cover while reading, an Immich picture elsewhere"), enabled = true } or false,
        immich and { id = "immich", label = _("A picture from your Immich album"), enabled = true } or false,
        { id = "readingprogress", label = _("Reading progress"), enabled = u ~= nil and u.statistics ~= nil },
        { id = "bookstatus", label = _("Book status (while reading)"), enabled = true },
        { id = "disable", label = _("Leave the screen as it is"), enabled = true },
    }
    local out = {}
    for _i, c in ipairs(list) do if c then out[#out + 1] = c end end
    return out
end

--- The choice in use.
function P.current()
    return require("gzsleepmode").current(G_reader_settings)
end

--- Use the choice `id` (as the old radio buttons did).
function P.choose(id)
    require("gzsleepmode").use(G_reader_settings, id)
end

--- The first of the Immich album's pictures on the Kindle, or nil.
function P.immichPicture()
    local dir = require("gzsleepmode").immichDir()
    if lfs.attributes(dir, "mode") ~= "directory" then return nil end
    local DocumentRegistry = require("document/documentregistry")
    local names = {}
    for name in lfs.dir(dir) do
        if name:sub(1, 1) ~= "." and DocumentRegistry:isImageFile(name) then names[#names + 1] = name end
    end
    table.sort(names)
    return names[1] and (dir .. "/" .. names[1]) or nil
end

--- The first picture a random sleep screen could show (its folder, then the
--- screensavers folder, then the Kindle's own), or nil.
function P.firstPicture()
    local DocumentRegistry = require("document/documentregistry")
    local dirs = {}
    local set = G_reader_settings:readSetting("screensaver_dir")
    if type(set) == "string" then dirs[#dirs + 1] = set end
    for _i, d in ipairs(Device:isKindle() and P.PICTURE_DIRS or {}) do dirs[#dirs + 1] = d end
    for _i, dir in ipairs(dirs) do
        if lfs.attributes(dir, "mode") == "directory" then
            local names = {}
            for name in lfs.dir(dir) do
                if name:sub(1, 1) ~= "." and DocumentRegistry:isImageFile(name) then names[#names + 1] = name end
            end
            table.sort(names)
            if names[1] then return dir .. "/" .. names[1] end
        end
    end
end

-- the last book's cover as a blitbuffer (CoverBrowser's cache first: no
-- opening the book), or nil
local function coverBB(file)
    if not file then return nil end
    local okb, BIM = pcall(require, "bookinfomanager")
    if okb and BIM and BIM.getBookInfo then
        local okg, info = pcall(BIM.getBookInfo, BIM, file, true)
        if okg and type(info) == "table" and info.cover_bb then return info.cover_bb end
    end
    local u = ui()
    if u and u.bookinfo and u.bookinfo.getCoverImage then
        local okc, bb = pcall(u.bookinfo.getCoverImage, u.bookinfo, u.document, file)
        if okc and bb then return bb end
    end
end

-- a widget showing `src` ({ image = bb } or { file = path } or { icon = path })
-- fitted into w × h
local function picture(src, w, h)
    if not src then return nil end
    if src.icon then
        local s = math.floor(math.min(w, h) * 0.5)
        return IconWidget:new{ file = src.icon, width = s, height = s, alpha = true }
    end
    return ImageWidget:new{ image = src.image, file = src.file, width = w, height = h,
        scale_factor = 0, image_disposable = src.image ~= nil and src.own ~= false }
end

local zen_icons = (function()
    local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
    return here:gsub("gzreader%.koplugin$", "zenos.koplugin") .. "/icons/"
end)()

--- The preview widgets for choice `id` at w × h: a list of
--- { widget, x, y } relative to the tile's picture area.
function P.preview(id, w, h, snapshot)
    local book = lastFile()
    if id == "cover" or id == "bookstatus" then
        local bb = coverBB(book)
        if not bb then return { { widget = picture({ icon = zen_icons .. "book_closed.svg" }, w, h) } } end
        if id == "bookstatus" then
            -- the status page: the cover smaller, over its details
            return { { widget = picture({ image = bb }, math.floor(w * 0.55), math.floor(h * 0.45)), top = true },
                { widget = picture({ icon = zen_icons .. "info.svg" }, math.floor(w * 0.5), math.floor(h * 0.4)), bottom = true } }
        end
        return { { widget = picture({ image = bb }, w, h) } }
    elseif id == "random_image" then
        local f = P.firstPicture()
        return { { widget = picture(f and { file = f } or { icon = zen_icons .. "grid.svg" }, w, h) } }
    elseif id == "immich" then
        local f = P.immichPicture()
        return { { widget = picture(f and { file = f } or { icon = zen_icons .. "grid.svg" }, w, h) } }
    elseif id == "auto" or id == "immich_auto" then
        local half = math.floor(w / 2)
        local bb = coverBB(book)
        local f
        if id == "immich_auto" then f = P.immichPicture() else f = P.firstPicture() end
        return {
            { widget = picture(bb and { image = bb } or { icon = zen_icons .. "book_closed.svg" }, half, h), left = true },
            { widget = picture(f and { file = f } or { icon = zen_icons .. "grid.svg" }, w - half, h), right = true },
        }
    elseif id == "readingprogress" then
        return { { widget = picture({ icon = zen_icons .. "pie_chart.svg" }, w, h) } }
    elseif id == "disable" then
        if snapshot then return { { widget = picture({ image = snapshot, own = false }, w, h) } } end
        return { { widget = picture({ icon = zen_icons .. "page.svg" }, w, h) } }
    end
    return {}
end

---------------------------------------------------------------- a tile

local Tile = InputContainer:extend{ w = 0, h = 0, pic_h = 0, label = "", key = nil, on = false, enabled = true,
    parts = nil, callback = nil }

function Tile:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = { TapTile = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function Tile:getSize() return Geom:new{ w = self.w, h = self.h } end

function Tile:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, ph = self.w, self.pic_h
    bb:paintRect(x, y, w, ph, Blitbuffer.COLOR_WHITE)
    for _i, p in ipairs(self.parts or {}) do
        local wd = p.widget
        if wd then
            local s = wd:getSize()
            local px = x + math.floor((w - s.w) / 2)
            local py = y + math.floor((ph - s.h) / 2)
            if p.left then px = x + math.floor((w / 2 - s.w) / 2) end
            if p.right then px = x + math.floor(w / 2) + math.floor((w / 2 - s.w) / 2) end
            if p.top then py = y + S(6) end
            if p.bottom then py = y + ph - s.h - S(6) end
            wd:paintTo(bb, px, py)
        end
    end
    if self.parts and #self.parts == 2 and self.parts[1].left then
        bb:paintRect(x + math.floor(w / 2), y, 1, ph, Blitbuffer.COLOR_DARK_GRAY)
    end
    if not self.enabled then bb:lightenRect(x, y, w, ph, 0.6) end
    -- the frame: thick for the choice in use
    bb:paintBorder(x, y, w, ph, self.on and math.max(4, S(4)) or math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    -- the label; white on black for the choice in use
    local fg = self.on and Blitbuffer.COLOR_WHITE or (self.enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY)
    local bg = self.on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
    local label = TextBoxWidget:new{ text = self.label, face = Font:getFace("cfont", 14), width = w - S(4),
        alignment = "center", height = self.h - ph - S(6), height_adjust = true, height_overflow_show_ellipsis = true,
        fgcolor = fg, bgcolor = bg }
    if self.on then bb:paintRect(x, y + ph, w, label:getSize().h + S(6), bg) end
    label:paintTo(bb, x + S(2), y + ph + S(3))
    label:free()
    if self.key then
        local Menu = require("ui/widget/menu")
        local side = S(22)
        local badge = Menu.getItemShortCutIcon(nil, Geom:new{ w = side, h = side }, self.key, "square")
        if badge then badge:paintTo(bb, x + S(4), y + S(4)); if badge.free then badge:free() end end
    end
    if self.focused then
        bb:paintBorder(x - S(5), y - S(5), w + 2 * S(5), self.h + 2 * S(5), math.max(3, S(3)), Blitbuffer.COLOR_BLACK)
    end
end

function Tile:onFocus() self.focused = true; return true end
function Tile:onUnfocus() self.focused = false; return true end

function Tile:onTapTile()
    if self.enabled and self.callback then self.callback() end
    return true
end

function Tile:free()
    for _i, p in ipairs(self.parts or {}) do
        if p.widget and p.widget.free then p.widget:free() end
    end
    self.parts = nil
end

---------------------------------------------------------------- the screen

local PreviewWidget = FocusManager:extend{ name = "gzreader sleep screen previews", modal = true,
    covers_fullscreen = true }

--- Tile sizes for the screen w × h: tile width, picture height, label height.
function P.layoutFor(sw, sh, n)
    local cols = P.COLUMNS
    local rows = math.ceil(n / cols)
    local pad, gap, top, bottom, label_h = S(16), S(14), S(64), S(36), S(44)
    local tw = math.floor((sw - 2 * pad - (cols - 1) * gap) / cols)
    local ph = math.floor(tw * sh / sw) -- the screen's shape
    local room = sh - top - bottom - (rows - 1) * gap
    if rows * (ph + label_h) > room then
        ph = math.floor(room / rows) - label_h
        tw = math.min(tw, math.floor(ph * sw / sh))
    end
    return { cols = cols, rows = rows, pad = pad, gap = gap, top = top, tw = tw, ph = ph, th = ph + label_h }
end

function PreviewWidget:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local choices = P.choices()
    local L = P.layoutFor(sw, sh, #choices)
    local left = math.floor((sw - (L.cols * L.tw + (L.cols - 1) * L.gap)) / 2)
    local keys = Device:hasKeyboard()
    local current = P.current()
    self.layout, self.placed = {}, {}
    local row
    for i, c in ipairs(choices) do
        local col = (i - 1) % L.cols
        if col == 0 then row = {}; self.layout[#self.layout + 1] = row end
        local r = math.floor((i - 1) / L.cols)
        local tile = Tile:new{ w = L.tw, h = L.th, pic_h = L.ph, label = c.label, on = c.id == current,
            enabled = c.enabled, key = keys and P.KEYS[i] or nil,
            parts = P.preview(c.id, L.tw - S(4), L.ph - S(4), self.snapshot),
            callback = function() self:pick(c.id) end }
        tile.choice = c.id
        row[#row + 1] = tile
        self[#self + 1] = tile
        self.placed[#self.placed + 1] = { tile = tile, x = left + col * (L.tw + L.gap), y = L.top + r * (L.th + L.gap) }
        if keys then
            self.key_events = self.key_events or {}
            self.key_events["Pick" .. P.KEYS[i]] = { { P.KEYS[i] } }
            self["onPick" .. P.KEYS[i]] = function() tile:onTapTile(); return true end
        end
    end
    self.key_events = self.key_events or {}
    self.key_events.Close = { { "Menu" } }
    self.key_events.CloseBack = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } }
    self.close_box = Geom:new{ x = sw - S(64), y = 0, w = S(64), h = S(56) }
    self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } } }
end

function PreviewWidget:paintTo(bb, x, y)
    local sw = self.dimen.w
    bb:paintRect(x, y, sw, self.dimen.h, Blitbuffer.COLOR_WHITE)
    local title = TextWidget:new{ text = _("Wallpaper"), face = Font:getFace("tfont", 22), bold = true }
    title:paintTo(bb, x + S(20), y + S(16)); title:free()
    local close = TextWidget:new{ text = "×", face = Font:getFace("cfont", 28) }
    close:paintTo(bb, x + sw - S(44), y + S(14)); close:free()
    bb:paintRect(x, y + S(56), sw, math.max(1, S(1)), Blitbuffer.COLOR_DARK_GRAY)
    for _i, p in ipairs(self.placed) do p.tile:paintTo(bb, x + p.x, y + p.y) end
    local hint = TextWidget:new{ text = Device:hasKeyboard() and _("Press a letter to use that sleep screen.")
        or _("Tap a sleep screen to use it."), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    hint:paintTo(bb, x + math.floor((sw - hint:getSize().w) / 2), y + self.dimen.h - S(30)); hint:free()
end

function PreviewWidget:pick(id)
    P.choose(id)
    UIManager:close(self)
    if self.on_done then self.on_done(id) end
end

function PreviewWidget:onTapOutside(_arg, ges)
    if ges and ges.pos and ges.pos:intersectWith(self.close_box) then UIManager:close(self); return true end
    for _i, p in ipairs(self.placed) do
        if ges and ges.pos and ges.pos:intersectWith(p.tile.dimen) then return true end
    end
    UIManager:close(self)
    return true
end

function PreviewWidget:onClose() UIManager:close(self); return true end
function PreviewWidget:onCloseBack() UIManager:close(self); return true end

function PreviewWidget:onFocusMove(args)
    local r = FocusManager.onFocusMove(self, args)
    UIManager:setDirty(self, "ui")
    return r
end

function PreviewWidget:onShow()
    if Device:hasDPad() then
        -- start on the choice in use
        for y, r in ipairs(self.layout) do
            for x, t in ipairs(r) do if t.on then self:moveFocusTo(x, y) end end
        end
    end
    UIManager:setDirty(self, "full")
    return true
end

function PreviewWidget:onCloseWidget()
    for _i, p in ipairs(self.placed or {}) do p.tile:free() end
    if self.snapshot then self.snapshot:free(); self.snapshot = nil end
    P.open = nil
    UIManager:setDirty(nil, "full")
end

--- Show the tiles; `on_done(id)` after a choice.
function P.show(on_done)
    if P.open then UIManager:close(P.open) end
    -- what the screen shows now (the Settings page), for "Leave the screen as it is"
    local okc, snapshot = pcall(function() return Screen.bb:copy() end)
    local w = PreviewWidget:new{ on_done = on_done, snapshot = okc and snapshot or nil }
    P.open = w
    UIManager:show(w)
    return w
end

P._Tile, P._Widget = Tile, PreviewWidget
return P
