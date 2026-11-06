--[[--
GZreader's quick panel: the same panel on every Kindle (and the Nook), at
the top of the screen. Square tiles, in two groups:

  Controls   Wi-Fi, Night mode, Rotate, Restart, Sleep, Home, Updates,
             Settings, Diagnostics (with diagnostic logging on), Exit
  Home       Manage “book” (the one highlighted), Continue, Send books,
             Search, History, View, Sort, Music
  This book  Sync with Grimmory, Contents, Bookmark, Bookmarks, Go to page,
             Search book, Font, Layout, Fit pictures, Read aloud, Music

With a keyboard each tile shows its letter (Controls: the top row of keys,
Q to P; the second group: A to L) and the 5-way and Press work too; the
Kindle 4 (no letter keys) has the 5-way; touch Kindles tap, and have the
light's slider at the top. Menu, Back, or a tap below the panel closes it.
A tile that's on (Wi-Fi, night mode, a bookmark, music or read aloud
playing) is drawn inverted. Touch Kindles: tap or drag the light's slider.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Touch = require("gzreader_touch")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Panel = {
    TOP_KEYS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
    SECOND_KEYS = { "A", "S", "D", "F", "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M" },
    COLUMNS = 5,
}

local root = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
local function iconFile(name) return root .. "/icons/panel/" .. name .. ".svg" end

local function dispatch(action)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher.execute then Dispatcher:execute({ [action] = true }) end
end

local function reader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI.instance or nil
end

---------------------------------------------------------------- a tile

local Tile = InputContainer:extend{ w = 0, h = 0, icon = nil, label = "", key = nil, on = false, callback = nil, hold = nil }

function Tile:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = {
        TapTile = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldTile = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
end

function Tile:getSize() return Geom:new{ w = self.w, h = self.h } end

function Tile:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local w, h = self.w, self.h
    local r = S(10)
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
    local isz = math.floor(math.min(w, h) * 0.34)
    local label = TextBoxWidget:new{ text = self.label, face = Font:getFace("cfont", 15), width = w - S(6),
        alignment = "center", height = math.floor(h * 0.36), height_adjust = true, height_overflow_show_ellipsis = true }
    local lh = label:getSize().h
    local top = y + math.floor((h - isz - S(6) - lh) / 2) + (self.key and S(6) or 0)
    if self.icon then
        local icon = IconWidget:new{ file = iconFile(self.icon), width = isz, height = isz, alpha = true }
        icon:paintTo(bb, x + math.floor((w - isz) / 2), top)
        icon:free()
    end
    label:paintTo(bb, x + S(4), top + isz + S(6))
    label:free()
    if self.key then
        local side = S(20)
        local badge = Menu.getItemShortCutIcon(nil, Geom:new{ w = side, h = side }, self.key, "square")
        if badge then badge:paintTo(bb, x + S(5), y + S(5)); if badge.free then badge:free() end end
    end
    if self.on then bb:invertRect(x + S(3), y + S(3), w - 2 * S(3), h - 2 * S(3)) end
    bb:paintBorder(x, y, w, h, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, r)
    if self.focused then
        -- the 5-way's place: a thick ring just outside
        bb:paintBorder(x - S(4), y - S(4), w + 2 * S(4), h + 2 * S(4), math.max(3, S(3)), Blitbuffer.COLOR_BLACK, r + S(4))
    end
end

function Tile:onFocus() self.focused = true; return true end
function Tile:onUnfocus() self.focused = false; return true end

function Tile:onTapTile()
    if self.callback then self.callback() end
    return true
end

function Tile:onHoldTile()
    if self.hold then self.hold() elseif self.callback then self.callback() end
    return true
end

---------------------------------------------------------------- what's on it

--- The Controls tiles: { icon, label, on, run }.
function Panel.controls(plugin)
    -- (no Wi-Fi: syncing through a computer, gzreader_usbsync.lua)
    local usb = require("gzreader_net").usb == true
    local list = {
        usb and { icon = "usb", label = _("Sync"), run = function() require("gzreader_usbsync").show(plugin) end }
            or { icon = "wifi", label = _("Wi-Fi"), on = NetworkMgr:isWifiOn(), run = function() dispatch("toggle_wifi") end },
    }
    local okn, Guard = pcall(require, "gzreader_nightguard")
    if not (okn and Guard.applies and Guard.applies()) then
        list[#list + 1] = { icon = "night", label = _("Night mode"), on = G_reader_settings:isTrue("night_mode"),
            run = function() dispatch("night_mode") end }
    end
    list[#list + 1] = { icon = "rotate", label = _("Rotate"), run = function() dispatch("iterate_rotation") end }
    list[#list + 1] = { icon = "restart", label = _("Restart"), run = function() dispatch("restart") end }
    list[#list + 1] = { icon = "sleep", label = _("Sleep"), run = function() dispatch("suspend") end }
    list[#list + 1] = { icon = "home", label = _("Home"), run = function() require("gzreader_tabs").goHome() end }
    if not usb then list[#list + 1] = { icon = "updates", label = _("Updates"), run = function() require("gzreader_update").run() end } end
    -- (a full page over the panel: a full refresh after it, or touch Kindles keep a ghost of the panel)
    list[#list + 1] = { icon = "settings", label = _("Settings"), full = true, run = function() require("gzreader_homemenu").settings() end }
    if plugin and plugin.store and plugin.store.logging_disabled ~= true then
        list[#list + 1] = { icon = "diagnostics", label = _("Diagnostics"), full = true, run = function() plugin:showDiagnostics() end }
    end
    list[#list + 1] = { icon = "exit", label = _("Exit to Kindle"), run = function() dispatch("exit") end }
    return list
end

local function shortTitle(path)
    local ok, BIM = pcall(require, "bookinfomanager")
    local info = ok and BIM:getBookInfo(path, false)
    local t = info and type(info.title) == "string" and info.title ~= "" and info.title
        or path:match("([^/]+)%.[^.]+$") or path
    if #t > 18 then t = t:sub(1, 16):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…" end
    return t
end

local function musicTile(plugin)
    if not Touch.audio() then return nil end
    local Tab = require("gzreader_musictab")
    local item = Tab.menuItem(plugin)
    local okm, M = pcall(require, "gzreader_music")
    local playing = okm and M.current and M.current.playing
    return { icon = "music", label = playing and _("Music ▶") or _("Music"), on = playing == true, run = item.callback }
end

--- Home's tiles (the file manager).
function Panel.homeTiles(plugin, book)
    local HomeMenu = require("gzreader_homemenu")
    local list = {}
    if book then
        list[#list + 1] = { icon = "manage", label = T(_("Manage “%1”"), shortTitle(book.path)), run = function()
            HomeMenu.manageBook(plugin, book)
        end }
    end
    list[#list + 1] = { icon = "continue", label = _("Continue"), run = function() dispatch("open_previous_document") end }
    if not require("gzreader_net").usb then -- (no Wi-Fi: Sync, in Controls)
        list[#list + 1] = { icon = "send", label = _("Send books"), run = function() plugin:openPhonePage("books") end }
    end
    list[#list + 1] = { icon = "search", label = _("Search"), run = function() dispatch("file_search") end }
    list[#list + 1] = { icon = "history", label = _("History"), full = true, run = function() dispatch("history") end }
    list[#list + 1] = { icon = "view", label = _("View"), run = function() HomeMenu.showDisplay() end }
    list[#list + 1] = { icon = "sort", label = _("Sort"), run = function() HomeMenu.showSort() end }
    local m = musicTile(plugin)
    if m then list[#list + 1] = m end
    local okA, Audiobook = pcall(require, "gzreader_audiobook")
    local cur = okA and Audiobook.current
    if cur and cur.book then
        list[#list + 1] = { icon = "readaloud", label = _("Audiobook"), on = cur.playing == true,
            run = function() Audiobook.open(plugin, cur.book) end }
    end
    local Tasks = require("gzreader_tasks")
    if Tasks.count() > 0 then
        local item = Tasks.menuItem()
        list[#list + 1] = { icon = "updates", label = item.text_func(), run = function() item.callback() end }
    end
    return list
end

--- A book's tiles (the reader).
function Panel.bookTiles(plugin, ui)
    local function send(name) return function() ui:handleEvent(Event:new(name)) end end
    local list = {}
    if plugin.sync then
        list[#list + 1] = { icon = "sync", label = _("Sync with Grimmory"), run = function() plugin:onGrimmorySyncNow() end }
    end
    list[#list + 1] = { icon = "contents", label = _("Contents"), run = function()
        if not ui:handleEvent(Event:new("ShowZenUIToc")) then ui:handleEvent(Event:new("ShowToc")) end
    end }
    list[#list + 1] = { icon = "bookmark", label = _("Bookmark"), on = ui.view and ui.view.dogear_visible == true,
        run = send("ToggleBookmark") }
    list[#list + 1] = { icon = "bookmarks", label = _("Bookmarks"), run = send("ShowBookmark") }
    list[#list + 1] = { icon = "gotopage", label = _("Go to page"), run = send("ShowGotoDialog") }
    list[#list + 1] = { icon = "searchbook", label = _("Search book"), run = send("ShowFulltextSearchInput") }
    -- the font (reflowing books), and the layout panel (size, margins, spacing…)
    if ui.font and ui.font.face_table and ui.document and not ui.document.info.has_pages then
        list[#list + 1] = { icon = "font", label = _("Font"), run = function() Panel.showFonts(ui) end }
    end
    list[#list + 1] = { icon = "layout", label = _("Layout"), run = send("ShowConfigMenu") }
    if ui.document and not ui.document.info.has_pages and ui.styletweak then
        local PB = require("gzreader_picturebook")
        local item = PB.menuItem(ui)
        list[#list + 1] = { icon = "fitpictures", label = _("Fit pictures"), on = PB.isOn(ui) == true, run = item.callback }
    end
    local tts = plugin.tts
    if tts and tts:supported() then
        list[#list + 1] = { icon = "readaloud", label = _("Read aloud"), on = tts.active == true, run = function() tts:toggle() end }
    end
    local m = musicTile(plugin)
    if m then list[#list + 1] = m end
    return list
end

--- The fonts, as a list (the one in use ticked): picking one sets it.
--- (KOReader's font menu, outside its top menu: letter keys, the 5-way, taps.)
function Panel.showFonts(ui)
    local face_table = ui.font.face_table
    if face_table.needs_refresh and face_table.refresh_func then face_table = face_table.refresh_func() end
    local items, current = {}, 1
    for _i, it in ipairs(face_table) do
        if it.menu_item_id and it.callback then
            local on = it.checked_func and it.checked_func()
            if on then current = #items + 1 end
            items[#items + 1] = { text = it.text_func and it.text_func() or it.text or it.menu_item_id,
                mandatory = on and "\u{2713}" or nil, gz_run = it.callback }
        end
    end
    local menu
    menu = Menu:new{ title = _("Font"), item_table = items, covers_fullscreen = true, is_borderless = true,
        width = Screen:getWidth(), height = Screen:getHeight(),
        is_popout = false, title_bar_fm_style = true,
        onMenuSelect = function(_m, item)
            UIManager:close(menu)
            if item.gz_run then UIManager:nextTick(item.gz_run) end
            return true
        end }
    -- open at the page with the font in use
    pcall(function() menu:onGotoPage(math.ceil(current / menu.perpage)) end)
    UIManager:show(menu)
    return menu
end

---------------------------------------------------------------- the panel

local PanelWidget = FocusManager:extend{ name = "gzreader quick panel", modal = true }

function PanelWidget:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad, gap = S(16), S(10)
    local cols = Panel.COLUMNS
    local tw = math.floor((sw - 2 * pad - (cols - 1) * gap) / cols)
    local th = tw
    local keys = Touch.keys()
    self.keys = keys
    local groups = { { title = _("Controls"), tiles = self.controls, letters = Panel.TOP_KEYS },
        { title = self.section_title, tiles = self.section, letters = Panel.SECOND_KEYS } }
    local light = Device:hasFrontlight() and Device:isTouchDevice()
    -- (fit the screen: smaller tiles on a short one)
    local rows = 0
    for _i, g in ipairs(groups) do rows = rows + math.ceil(#g.tiles / cols) end
    local fixed = S(40) + (light and S(52) or 0) + #groups * S(30) + S(30)
    local max_th = math.floor((sh * 0.86 - fixed - (rows - 1) * gap) / math.max(1, rows))
    th = math.max(S(60), math.min(th, max_th))
    self.layout = {}
    self.placed = {}
    local y = S(40)
    if light then
        self.light_y = y
        y = y + S(52)
    end
    self.titles = {}
    for _i, g in ipairs(groups) do
        self.titles[#self.titles + 1] = { text = g.title, y = y }
        y = y + S(28)
        local row
        for i, t in ipairs(g.tiles) do
            local c = (i - 1) % cols
            if c == 0 then
                row = {}
                self.layout[#self.layout + 1] = row
                if i > 1 then y = y + th + gap end
            end
            local tile = Tile:new{ w = tw, h = th, icon = t.icon, label = t.label, on = t.on,
                key = keys and g.letters[i] or nil,
                callback = function() self:pick(t) end }
            tile.key_letter = g.letters[i]
            row[#row + 1] = tile
            self[#self + 1] = tile
            self.placed[#self.placed + 1] = { tile = tile, x = pad + c * (tw + gap), y = y }
        end
        y = y + th + gap + S(4)
    end
    self.hint_y = y
    self.h = y + S(28)
    self.w = sw
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = self.h }
    -- keys: the letters; Menu and Back close
    self.key_events = self.key_events or {}
    self.key_events.Close = { { "Menu" } }
    self.key_events.CloseBack = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } }
    if keys then
        for _i, p in ipairs(self.placed) do
            local tile = p.tile
            if tile.key_letter then
                self.key_events["Pick" .. tile.key_letter] = { { tile.key_letter } }
                self["onPick" .. tile.key_letter] = function() tile:onTapTile(); return true end
            end
        end
    end
    -- a tap below the panel closes it (and the light's slider)
    local whole = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = { TapPanel = { GestureRange:new{ ges = "tap", range = whole } } }
    if light then
        -- drag the slider (pan while moving, then its release; a quick drag is a swipe)
        local strip = function() return Geom:new{ x = 0, y = self.light_y - S(10), w = sw, h = S(64) } end
        self.ges_events.PanLight = { GestureRange:new{ ges = "pan", range = strip } }
        self.ges_events.PanReleaseLight = { GestureRange:new{ ges = "pan_release", range = strip } }
        self.ges_events.SwipeLight = { GestureRange:new{ ges = "swipe", range = strip } }
    end
end

--- The light at the slider's position x (the bar only; − and + are buttons).
function PanelWidget:lightAt(x, final)
    local min, max = select(2, self:lightInfo())
    local bar = self:lightBar(0)
    local f = math.max(0, math.min(1, (x - bar.x) / math.max(1, bar.w)))
    local v = math.floor(min + f * (max - min) + 0.5)
    if v == self._dragged and not final then return true end
    self._dragged = v
    self:setLight(v, not final)
    return true
end

function PanelWidget:onPanLight(_arg, ges)
    if not (ges and ges.pos) then return true end
    return self:lightAt(ges.pos.x)
end

function PanelWidget:onPanReleaseLight(_arg, ges)
    self._dragged = nil
    if not (ges and ges.pos) then return true end
    return self:lightAt(ges.pos.x, true)
end

function PanelWidget:onSwipeLight(_arg, ges)
    if not (ges and ges.pos and (ges.direction == "east" or ges.direction == "west")) then return true end
    -- (pos is where it started: end where it went)
    local x = ges.pos.x + (ges.direction == "east" and 1 or -1) * (ges.distance or 0)
    self._dragged = nil
    return self:lightAt(x, true)
end

function PanelWidget:getSize() return self.dimen end

function PanelWidget:pick(t)
    UIManager:close(self)
    if t.run then UIManager:nextTick(function()
        pcall(function() require("gzreader_usage").menu(self.section_id, t.label) end)
        t.run()
        if t.full then UIManager:scheduleIn(0.4, function() UIManager:setDirty(nil, "full") end) end
    end) end
end

function PanelWidget:paintTo(bb, x, y)
    local w, h = self.w, self.h
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x, y + h - math.max(2, S(3)), w, math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    -- the status row: time, "Quick panel", battery and Wi-Fi
    local face = Font:getFace("cfont", 14)
    local time = TextWidget:new{ text = (os.date("%I:%M %p"):gsub("^0", "")), face = face }
    time:paintTo(bb, x + S(16), y + S(10))
    time:free()
    local title = TextWidget:new{ text = _("Quick panel"), face = face, bold = true }
    title:paintTo(bb, x + math.floor((w - title:getSize().w) / 2), y + S(10))
    title:free()
    local okp, powerd = pcall(function() return Device:getPowerDevice() end)
    local cap = okp and powerd and powerd.getCapacity and powerd:getCapacity()
    local right = (NetworkMgr:isWifiOn() and _("Wi-Fi") or _("Wi-Fi off")) .. (cap and (" · " .. cap .. "%") or "")
    local rt = TextWidget:new{ text = right, face = face }
    rt:paintTo(bb, x + w - S(16) - rt:getSize().w, y + S(10))
    rt:free()
    if self.light_y then self:paintLight(bb, x, y + self.light_y) end
    for _i, t in ipairs(self.titles) do
        local tw = TextWidget:new{ text = tostring(t.text):upper(), face = Font:getFace("cfont", 12), bold = true,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        tw:paintTo(bb, x + S(16), y + t.y + S(4))
        tw:free()
    end
    for _i, p in ipairs(self.placed) do p.tile:paintTo(bb, x + p.x, y + p.y) end
    local hint
    if self.keys then hint = _("Menu opens and closes it · a letter picks · or the 5-way and Press")
    elseif Device:hasDPad() then hint = _("The 5-way moves · Press picks · Menu closes")
    else hint = _("Tap below to close") end
    local ht = TextWidget:new{ text = hint, face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w - S(32) }
    ht:paintTo(bb, x + math.floor((w - ht:getSize().w) / 2), y + self.hint_y)
    ht:free()
end

---------------------------------------------------------------- the light (touch Kindles)

function PanelWidget:lightInfo()
    local powerd = Device:getPowerDevice()
    local min, max = powerd.fl_min or 0, powerd.fl_max or 24
    local cur = powerd:frontlightIntensity() or min
    return powerd, min, max, cur
end

function PanelWidget:lightBar(x)
    local w = self.w
    return { x = x + S(16) + S(44) + S(8), w = w - 2 * S(16) - 2 * (S(44) + S(8)) }
end

function PanelWidget:paintLight(bb, x, y)
    local min, max, cur = select(2, self:lightInfo())
    local bar = self:lightBar(x)
    local cy = y + S(20)
    -- − and +
    for i, label in ipairs({ "\u{2212}", "+" }) do
        local bx = i == 1 and (x + S(16)) or (x + self.w - S(16) - S(44))
        bb:paintBorder(bx, y, S(44), S(40), math.max(2, S(2)), Blitbuffer.COLOR_BLACK, S(8))
        local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 20), bold = true }
        local ts = t:getSize()
        t:paintTo(bb, bx + math.floor((S(44) - ts.w) / 2), y + math.floor((S(40) - ts.h) / 2))
        t:free()
    end
    local bh = S(10)
    bb:paintBorder(bar.x, cy - math.floor(bh / 2), bar.w, bh, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, math.floor(bh / 2))
    local f = (max > min) and (cur - min) / (max - min) or 0
    local fw = math.floor(bar.w * f)
    if fw > 0 then bb:paintRoundedRect(bar.x, cy - math.floor(bh / 2), fw, bh, Blitbuffer.COLOR_BLACK, math.floor(bh / 2)) end
    local knob = S(20)
    local kx = bar.x + fw - math.floor(knob / 2)
    bb:paintRoundedRect(kx, cy - math.floor(knob / 2), knob, knob, Blitbuffer.COLOR_WHITE, math.floor(knob / 2))
    bb:paintBorder(kx, cy - math.floor(knob / 2), knob, knob, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, math.floor(knob / 2))
end

function PanelWidget:setLight(v, dragging)
    local powerd, min, max = self:lightInfo()
    v = math.max(min, math.min(max, math.floor(v + 0.5)))
    powerd:setIntensity(v)
    -- (while dragging: the quick black-and-white refresh)
    UIManager:setDirty(self, function()
        return dragging and "fast" or "ui", Geom:new{ x = 0, y = self.light_y, w = self.w, h = S(44) }
    end)
end

function PanelWidget:onTapPanel(_arg, ges)
    local pos = ges and ges.pos
    if not pos then return true end
    if pos.y > self.h then UIManager:close(self); return true end
    if self.light_y and pos.y >= self.light_y and pos.y <= self.light_y + S(44) then
        local min, max, cur = select(2, self:lightInfo())
        local bar = self:lightBar(0)
        if pos.x < S(16) + S(44) + S(4) then return self:setLight(cur - 1) or true end
        if pos.x > self.w - S(16) - S(44) - S(4) then return self:setLight(cur + 1) or true end
        local f = math.max(0, math.min(1, (pos.x - bar.x) / math.max(1, bar.w)))
        return self:setLight(min + f * (max - min)) or true
    end
    return true
end

function PanelWidget:onClose() UIManager:close(self); return true end
function PanelWidget:onCloseBack() UIManager:close(self); return true end

function PanelWidget:onFocusMove(args)
    local r = FocusManager.onFocusMove(self, args)
    UIManager:setDirty(self, "ui")
    return r
end

function PanelWidget:onShow()
    if Device:hasDPad() then self:moveFocusTo(1, 1) end
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    return true
end

function PanelWidget:onCloseWidget()
    Panel.open = nil
    UIManager:setDirty(nil, function() return "ui", self.dimen end)
end

---------------------------------------------------------------- opening it

--- The panel, for Home (the file manager) or the book open.
function Panel.show(plugin)
    if Panel.open then UIManager:close(Panel.open); return true end
    local ui = reader()
    local section, title, id
    if ui and ui.document then
        section, title, id = Panel.bookTiles(plugin, ui), _("This book"), "reading"
    else
        local HomeMenu = require("gzreader_homemenu")
        local okh, book = pcall(HomeMenu.highlighted)
        section, title, id = Panel.homeTiles(plugin, okh and book or nil), _("Home"), "home"
    end
    local w = PanelWidget:new{ controls = Panel.controls(plugin), section = section, section_title = title, section_id = id }
    Panel.open = w
    UIManager:show(w)
    return true
end

return Panel
