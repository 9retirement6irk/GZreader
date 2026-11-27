--[[--
GZreader's quick panel: the same panel on every Kindle (and the Nook), at
the top of the screen. Square tiles, in two groups:

  Controls   Wi-Fi (on, off, auto), Night mode, Rotate, Auto-rotate, Restart, Sleep, Home, Updates,
             Settings, Diagnostics (with diagnostic logging on), Exit
  Home       Manage “book” (the one highlighted), Continue, Connect,
             Search, History, View, Sort, Quick note, Music, Audiobook
  This book  Sync with Grimmory, Reader tools, Bookmark, Read aloud, Story
             guide, Flashcards, Mark up, Notes, Music, Audiobook, Quick note

Quick note is there while Memos is connected (the Notes tab): a new note in
the full-page editor over whatever is on screen; Save sends it in the
background and you're back in the book (or Home, or Settings).

Music and Audiobook are there only while one plays (or is paused): they
open its player. Browsing and downloading music and audiobooks is the
Catalog tab's (gzreader_catalog.lua); what's on the Kindle, Downloads.

With a keyboard each tile shows its letter (Controls: the top row of keys,
Q to P; the second group: A to L) and the 5-way and Press work too; the
Kindle 4 (no letter keys) has the 5-way; touch Kindles tap, and have the
light's slider at the top. Menu, Back, or a tap below the panel closes it.
A tile that's on (Wi-Fi, night mode, a bookmark, music or read aloud
playing; Updates when an update was found) is drawn inverted. Touch Kindles: tap or drag the light's slider.
Kindles with a warm light (Device:hasNaturalLight(): Paperwhite 5 and newer,
Oasis 3, Scribe, Colorsoft) get a warmth slider under it, cool to warm, in
the Kindle's own steps (powerd's native warmth, 0 to 24).
Touch Kindles with sound (the Kindle Touch; Bluetooth Kindles) get a volume
slider under those: TTS.volume, the speaker's 0 to 15 or the Kindle's
Bluetooth volume 1 to 8 (the Kindle 2, 3 and DX: their volume buttons).

Settings → Home and tabs → Quick panel also puts the tiles in your order and
adds tiles of your own, a third group (gzreader_panelcustom.lua).
Settings → Home and tabs → Quick panel shows or hides each tile (Panel.CATALOG;
the hidden ones in G_reader_settings "gzreader_panel_hidden", as
"<group>:<id>"). Home, Settings and Exit to Kindle are always there; a group
with every tile hidden isn't drawn. Letters follow the tiles shown.
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
    -- (big screens: a tile at most TILE_MAX_IN inches wide, a little more
    -- than on a Paperwhite (0.63") or an Oasis (0.74"), so more of them go
    -- across instead of each one growing with the screen)
    TILE_MAX_IN = 0.8, MAX_COLUMNS = 8, BIG_SCREEN_IN = 5.0,
}

--- Whether the screen's shorter side is more than BIG_SCREEN_IN inches
--- (the Kindle Scribe, the DX; by the device's own DPI).
function Panel.bigScreen(dev)
    dev = dev or Device
    local dpi = dev.display_dpi
    if not (dpi and dpi > 0 and dev.screen) then return false end
    return math.min(dev.screen:getWidth(), dev.screen:getHeight()) / dpi > Panel.BIG_SCREEN_IN
end

--- How many tiles go across. COLUMNS everywhere, but on a big touch screen
--- as many as keep each at most TILE_MAX_IN wide (at most MAX_COLUMNS): five across a
--- Scribe made each tile over an inch wide (1.13"). Kindles with keys keep
--- five (the letters follow the keyboard's rows: Q to T, then Y to P).
function Panel.columns(sw, pad, gap, keys, dev)
    dev = dev or Device
    local cols = Panel.COLUMNS
    if keys or not Panel.bigScreen(dev) then return cols end
    local max_w = math.floor(dev.display_dpi * Panel.TILE_MAX_IN)
    local fit = math.ceil((sw - 2 * pad + gap) / (max_w + gap)) -- (enough for none to be wider)
    return math.max(cols, math.min(fit, Panel.MAX_COLUMNS))
end

--- The letters for your own tiles: the second group's keys it doesn't use
--- (it has `used` tiles), so no key means two tiles.
function Panel.ownKeys(used)
    local out = {}
    for i = (used or 0) + 1, #Panel.SECOND_KEYS do out[#out + 1] = Panel.SECOND_KEYS[i] end
    return out
end

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

local Tile = InputContainer:extend{ w = 0, h = 0, icon = nil, label = "", sub = nil, side = nil, key = nil, on = false,
    callback = nil, side_callback = nil, hold = nil }

--- The height of a tile's side part (its bottom quarter: the Rotate tile's turn, while Manual).
local function sideHeight(h) return math.floor(h / 4) end

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
    self.gz_painted = true -- (its place on screen is known: the 5-way refreshes just it)
    local w, h = self.w, self.h
    local r = S(10)
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
    local isz = math.floor(math.min(w, h) * 0.34)
    -- (a side part along the bottom: the rest of the tile is its main part)
    local sh = self.side and sideHeight(h) or 0
    local mh = h - sh
    local label = TextBoxWidget:new{ text = self.label, face = Font:getFace("cfont", 15), width = w - S(6),
        alignment = "center", height = math.floor(h * 0.36), height_adjust = true, height_overflow_show_ellipsis = true }
    local lh = label:getSize().h
    local sub = self.sub and TextBoxWidget:new{ text = self.sub, face = Font:getFace("cfont", 12), width = w - S(6),
        alignment = "center", height = math.floor(h * 0.2), height_adjust = true, height_overflow_show_ellipsis = true }
    local subh = sub and sub:getSize().h or 0
    if sub then isz = math.floor(isz * 0.85) end
    -- (with a side part: no icon above the words, the side part has it)
    if self.side then isz = 0 end
    local gap = self.side and S(2) or S(6)
    local top = y + math.max(S(2), math.floor((mh - isz - gap - lh - subh) / 2)) + (self.key and S(6) or 0)
    if self.icon and isz > 0 then
        local icon = IconWidget:new{ file = iconFile(self.icon), width = isz, height = isz, alpha = true }
        icon:paintTo(bb, x + math.floor((w - isz) / 2), top)
        icon:free()
    end
    label:paintTo(bb, x + S(4), top + isz + gap)
    label:free()
    if sub then sub:paintTo(bb, x + S(4), top + isz + gap + lh); sub:free() end
    if self.side then
        -- a line across, then the side part's icon under it
        bb:paintRect(x + S(8), y + mh, w - 2 * S(8), math.max(1, S(1)), Blitbuffer.COLOR_GRAY_9)
        local ssz = math.floor(sh * 0.8)
        local sicon = IconWidget:new{ file = iconFile(self.side.icon), width = ssz, height = ssz, alpha = true }
        sicon:paintTo(bb, x + math.floor((w - ssz) / 2), y + mh + math.floor((sh - ssz) / 2))
        sicon:free()
    end
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

function Tile:onTapTile(_arg, ges)
    local pos = ges and ges.pos
    if self.side and self.side_callback and pos and pos.y >= self.dimen.y + self.h - sideHeight(self.h) then
        self.side_callback()
    elseif self.callback then self.callback() end
    return true
end

function Tile:onHoldTile()
    if self.hold then self.hold() elseif self.callback then self.callback() end
    return true
end

---------------------------------------------------------------- which tiles are shown

local HIDDEN_KEY = "gzreader_panel_hidden"

local function usbOnly() return require("gzreader_net").usb == true end
local function nightGuarded()
    local okn, Guard = pcall(require, "gzreader_nightguard")
    return okn and Guard.applies and Guard.applies() and true or false
end

--- Every tile the panel can have, by group, in panel order:
--- { id, label, note (when it's there), fixed (always shown), available (on this device) }.
function Panel.catalog()
    return {
        { id = "controls", title = _("Controls"), tiles = {
            { id = "home", label = _("Home"), fixed = true },
            { id = "wifi", label = usbOnly() and _("Sync") or _("Wi-Fi") },
            { id = "bluetooth", label = _("Bluetooth"), note = _("Kindles with Bluetooth"), available = function() return Panel.bluetooth() ~= nil end },
            { id = "night", label = _("Night mode"), available = function() return not nightGuarded() end },
            { id = "rotate", label = _("Rotate"), note = _("Auto or Manual on Kindles that turn the screen by themselves") },
            { id = "autolight", label = _("Auto light"), note = _("Kindles with a light sensor"), available = function() return require("gzreader_autolight").available() end },
            { id = "restart", label = _("Restart") },
            { id = "sleep", label = _("Sleep") },
            { id = "updates", label = _("Updates"), available = function() return not usbOnly() end },
            { id = "settings", label = _("Settings"), fixed = true },
            { id = "diagnostics", label = _("Diagnostics"), note = _("while logging is on") },
            { id = "exit", label = _("Exit to Kindle"), fixed = true },
        } },
        { id = "home", title = _("Home"), tiles = {
            { id = "manage", label = _("Manage book"), note = _("the book highlighted") },
            { id = "continue", label = _("Continue") },
            { id = "send", label = _("Connect"), note = _("your phone or computer: send books, set up"), available = function() return not usbOnly() end },
            { id = "search", label = _("Search") },
            { id = "history", label = _("History") },
            { id = "view", label = _("View") },
            { id = "sort", label = _("Sort") },
            { id = "note", label = _("Quick note"), note = _("while Memos is connected") },
            { id = "music", label = _("Music"), note = _("while it plays"), available = Touch.player },
            { id = "audiobook", label = _("Audiobook"), note = _("while one plays"), available = Touch.player },
            { id = "tasks", label = _("Background tasks"), note = _("while one is running") },
        } },
        { id = "book", title = _("This book"), tiles = {
            { id = "sync", label = _("Sync with Grimmory"), note = _("Grimmory's books") },
            { id = "controls", label = _("Reader tools"), note = _("what a swipe up from the bottom of the page opens: font, layout, search, bookmarks, highlights") },
            { id = "bookmark", label = _("Bookmark") },
            { id = "readaloud", label = _("Read aloud"), available = Touch.tts },
            { id = "storyguide", label = _("Story guide"), note = _("people, places, terms and what's happened, made from the book's text by your AI service; with an AI key") },
            { id = "note", label = _("Quick note"), note = _("while Memos is connected") },
            { id = "markup", label = _("Mark up"), note = _("draw on the page, kept in Memos with the book and chapter; touch Kindles, while Memos is connected") },
            { id = "split", label = _("Notes"), note = _("beside the book, on big screens, while Memos is connected"),
                available = function() return require("gzreader_splitview").available() end },
            { id = "music", label = _("Music"), note = _("while it plays"), available = Touch.player },
            { id = "audiobook", label = _("Audiobook"), note = _("while one plays"), available = Touch.player },
            { id = "flashcards", label = _("Flashcards"), note = _("make cards with your AI service, and quiz yourself") },
        } },
    }
end

local function catalogEntry(group, id)
    for _i, g in ipairs(Panel.catalog()) do
        if g.id == group then
            for _j, t in ipairs(g.tiles) do if t.id == id then return t end end
        end
    end
end

local function hiddenSet()
    local h = G_reader_settings:readSetting(HIDDEN_KEY)
    return type(h) == "table" and h or {}
end

--- Is this tile on the panel (when it applies)? Home, Settings and Exit always are.
function Panel.isShown(group, id)
    local e = catalogEntry(group, id)
    if e and e.fixed then return true end
    return hiddenSet()[group .. ":" .. id] ~= true
end

function Panel.setShown(group, id, shown)
    local e = catalogEntry(group, id)
    if not e or e.fixed then return end
    local h = {}
    for k, v in pairs(hiddenSet()) do h[k] = v end
    h[group .. ":" .. id] = (not shown) or nil
    if next(h) then G_reader_settings:saveSetting(HIDDEN_KEY, h) else G_reader_settings:delSetting(HIDDEN_KEY) end
end

function Panel.showAll() G_reader_settings:delSetting(HIDDEN_KEY) end

--- The tiles of a group the user hasn't hidden, in the order they chose
--- (Settings → Quick panel → Arrange tiles: gzreader_panelcustom.lua).
local function shown(group, list)
    if group == "book" then list = Panel.inBookOrder(list) end
    local out = {}
    for _i, t in ipairs(list) do
        if not t.id or Panel.isShown(group, t.id) then out[#out + 1] = t end
    end
    return require("gzreader_panelcustom").ordered(group, out)
end

--- Settings → Home and tabs → Quick panel: a tick per tile, by group.
--- How the quick panel opens on a touch Kindle: a tap at the top, a swipe
--- down from the top, or both. It's KOReader's "Activate menu" (G_reader_settings
--- activate_menu: "swipe_tap", the default, "tap" or "swipe"), which opens the
--- quick panel since GZreader puts it in place of KOReader's menu; its row in
--- Settings → KOReader is left out (zenos common/gz_settings.lua
--- KOREADER_DUPLICATES.menu_activate), with the "Auto-show bottom menu" under
--- it (ZenOS keeps KOReader's bottom menu shut on touch Kindles). As there,
--- unticking one ticks the other: the panel always opens somehow. None on a
--- Kindle without a touch screen (the Menu key opens it).
function Panel.openRows()
    if not require("gzreader_touch").on() then return {} end
    local function mode() return G_reader_settings:readSetting("activate_menu") or "swipe_tap" end
    local function set(value)
        G_reader_settings:saveSetting("activate_menu", value)
        -- (Home's and an open book's menus read it once, when they're made)
        for _i, name in ipairs({ "apps/filemanager/filemanager", "apps/reader/readerui" }) do
            local ok, App = pcall(require, name)
            local ui = ok and type(App) == "table" and App.instance
            if ui and ui.menu then ui.menu.activation_menu = value end
            if ui and ui.config then ui.config.activation_menu = value end
        end
    end
    return {
        {
            text = _("Open with a tap at the top"),
            help_text = _("A tap at the top of the screen opens the quick panel (in a book too). Untick it to open it only with a swipe down."),
            checked_func = function() return mode() ~= "swipe" end,
            callback = function() set(mode() ~= "swipe" and "swipe" or "swipe_tap") end,
        },
        {
            text = _("Open with a swipe down from the top"),
            help_text = _("A swipe down from the top of the screen opens the quick panel (in a book too). Untick it to open it only with a tap at the top."),
            checked_func = function() return mode() ~= "tap" end,
            callback = function() set(mode() ~= "tap" and "tap" or "swipe_tap") end,
            separator = true,
        },
    }
end

function Panel.settingsItem()
    local groups = {}
    for _i, row in ipairs(Panel.openRows()) do groups[#groups + 1] = row end
    for _i, g in ipairs(Panel.catalog()) do
        local items = {}
        for _j, t in ipairs(g.tiles) do
            if not t.available or t.available() then
                local gid, tid, fixed = g.id, t.id, t.fixed
                items[#items + 1] = {
                    text = t.note and T("%1 (%2)", t.label, t.note) or t.label,
                    help_text = fixed and _("Always on the quick panel.") or nil,
                    enabled_func = function() return not fixed end,
                    checked_func = function() return Panel.isShown(gid, tid) end,
                    callback = function() Panel.setShown(gid, tid, not Panel.isShown(gid, tid)) end,
                }
            end
        end
        groups[#groups + 1] = { text = g.title, sub_item_table = items }
    end
    groups[#groups].separator = true
    local Custom = require("gzreader_panelcustom")
    local arrange = {}
    for gi, g in ipairs(Panel.catalog()) do
        arrange[#arrange + 1] = { id = g.id, title = g.title, tiles = function()
            local out = {}
            for _j, t in ipairs(Panel.catalog()[gi].tiles) do
                if not t.available or t.available() then out[#out + 1] = { id = t.id, label = t.label } end
            end
            return out
        end }
    end
    groups[#groups + 1] = {
        text = _("Show every tile"),
        keep_menu_open = true,
        callback = function(touchmenu)
            Panel.showAll()
            if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
            pcall(function()
                UIManager:show(require("ui/widget/infomessage"):new{ text = _("Every tile is back on the quick panel."), timeout = 2 })
            end)
        end,
        separator = true,
    }
    groups[#groups + 1] = Custom.arrangeItem(arrange)
    groups[#groups + 1] = Custom.ownItem()
    return {
        text = _("Quick panel"),
        help_text = _("How the quick panel opens (touch Kindles: a tap at the top, a swipe down; the Menu key on the others) and its tiles: which show, their order, and tiles of your own (a plugin's screen, one of KOReader's menus). Home, Settings and Exit to Kindle are always there. Hidden tiles' letters go to the tiles after them."),
        sub_item_table = groups,
    }
end

---------------------------------------------------------------- what's on it

--- The Wi-Fi tile: On, Off or Auto (gzreader_net.lua); a tap goes to the
--- next one (on → off → auto → on). On is drawn inverted; Auto's icon has an
--- "A" and still shows whether Wi-Fi is on right now. It stays: the panel
--- stays open and the tile is drawn again (`stay`, `refresh`).
function Panel.wifiTile()
    local Net = require("gzreader_net")
    local mode = Net.mode()
    local d = Net.describe(mode)
    return { id = "wifi", icon = d.icon, label = d.tile, on = mode == "on", stay = true, refresh = Panel.wifiTile, run = function()
        local next_mode = Net.nextMode(Net.mode())
        local switching = Net.setMode(next_mode)
        -- (KOReader says "Turning on Wi-Fi…" / "Wi-Fi off." when it switches)
        if not switching or next_mode == "auto" then
            local nd = Net.describe(next_mode)
            pcall(function()
                UIManager:show(require("ui/widget/infomessage"):new{ text = T(_("Wi-Fi: %1"), nd.name), timeout = 2 })
            end)
        end
    end }
end

--- ZenOS's Bluetooth module where this Kindle has Bluetooth that it can
--- manage (modules/menu/bluetooth/bluetooth.lua, gated by
--- common/gz_bluetooth.lua); nil elsewhere.
function Panel.bluetooth()
    local ok, BT = pcall(require, "modules/menu/bluetooth/bluetooth")
    if ok and type(BT) == "table" and BT.isAvailable and BT.isAvailable() then return BT end
    return nil
end

--- The Bluetooth tile (Kindles with Bluetooth): a tap turns Bluetooth on or
--- off, the panel staying open like the Wi-Fi tile's (`stay`, `refresh`,
--- drawn again once the change is confirmed); a hold opens ZenOS's
--- Bluetooth devices list (search, pair, connect). On is drawn inverted.
function Panel.bluetoothTile()
    local BT = Panel.bluetooth()
    if not BT then return nil end
    local state = BT.getCachedState()
    if state == nil and not BT.isChanging() then state = BT.isEnabled() end
    return { id = "bluetooth", icon = state and "bluetooth" or "bluetooth_off",
        label = BT.isChanging() and _("Bluetooth…") or state and _("Bluetooth") or _("Bluetooth off"),
        on = state == true, stay = true, refresh = Panel.bluetoothTile,
        run = function()
            BT.toggle(function(ok, reason)
                if not ok then
                    pcall(function()
                        UIManager:show(require("ui/widget/infomessage"):new{
                            text = reason or _("Could not change Bluetooth power."), timeout = 2 })
                    end)
                end
                -- (the open panel draws the tile again on BluetoothStateChanged)
            end)
        end,
        hold = function()
            local fm = package.loaded["apps/filemanager/filemanager"]
            local f = fm and fm.instance
            local zen = (f and f.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
            require("modules/menu/bluetooth_switcher").open(nil, false, zen)
        end }
end

--- The Controls tiles: { id, icon, label, on, run, hold, stay }.
function Panel.controls(plugin)
    -- (no Wi-Fi: syncing through a computer, gzreader_usbsync.lua)
    local usb = usbOnly()
    local list = {
        { id = "home", icon = "home", label = _("Home"), run = function() require("gzreader_tabs").goHome() end },
        usb and { id = "wifi", icon = "usb", label = _("Sync"), run = function() require("gzreader_usbsync").show(plugin) end }
            or Panel.wifiTile(),
    }
    list[#list + 1] = Panel.bluetoothTile() -- (Kindles with Bluetooth)
    if not nightGuarded() then
        list[#list + 1] = { id = "night", icon = "night", label = _("Night mode"), on = G_reader_settings:isTrue("night_mode"),
            run = function() dispatch("night_mode") end }
    end
    -- (Kindles with an accelerometer, Oasis and Scribe: Auto or Manual, and the turn on the tile's side while Manual)
    list[#list + 1] = require("gzreader_rotation").tile(function() dispatch("iterate_rotation") end)
    list[#list + 1] = require("gzreader_autolight").tile() -- (Kindles with a light sensor: Voyage, Oasis, Scribe…)
    list[#list + 1] = { id = "restart", icon = "restart", label = _("Restart"), run = function() dispatch("restart") end }
    list[#list + 1] = { id = "sleep", icon = "sleep", label = _("Sleep"), run = function() dispatch("suspend") end }
    if not usb then list[#list + 1] = Panel.updatesTile() end
    -- (a full page over the panel: a full refresh after it, or touch Kindles keep a ghost of the panel)
    list[#list + 1] = { id = "settings", icon = "settings", label = _("Settings"), full = true, run = function() require("gzreader_homemenu").settings() end }
    if plugin and plugin.store and plugin.store.logging_disabled ~= true then
        list[#list + 1] = { id = "diagnostics", icon = "diagnostics", label = _("Diagnostics"), full = true, run = function() plugin:showDiagnostics() end }
    end
    list[#list + 1] = { id = "exit", icon = "exit", label = _("Exit to Kindle"), run = function() dispatch("exit") end }
    return shown("controls", list)
end

local function shortTitle(path)
    local ok, BIM = pcall(require, "bookinfomanager")
    local info = ok and BIM:getBookInfo(path, false)
    local t = info and type(info.title) == "string" and info.title ~= "" and info.title
        or path:match("([^/]+)%.[^.]+$") or path
    if #t > 18 then t = t:sub(1, 16):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…" end
    return t
end

--- The Updates tile: "Update available", drawn inverted, once a check (the
--- daily one, or one from Settings) found a newer version. Nothing is
--- fetched here; gzreader_update is only loaded when a check was saved.
function Panel.updatesTile()
    local latest
    if package.loaded["gzreader_update"] or G_reader_settings:readSetting("gzreader_update_latest") then
        local ok, Update = pcall(require, "gzreader_update")
        latest = ok and type(Update.known) == "function" and Update.known() or nil
    end
    return { id = "updates", icon = "updates", label = latest and _("Update available") or _("Updates"), on = latest ~= nil,
        run = function() require("gzreader_update").run() end }
end

--- The Music tile, while music plays or is paused (its player: the CD
--- player). Nothing else: music is browsed in the Catalog.
local function musicTile(plugin)
    if not Touch.player() then return nil end
    local okm, M = pcall(require, "gzreader_music")
    local cur = okm and M.current
    if not cur then return nil end
    local playing = cur.playing == true
    return { id = "music", icon = "music", label = playing and _("Music ▶") or _("Music"), on = playing,
        run = function() require("gzreader_musictab").nowPlaying(plugin) end }
end
Panel.musicTile = musicTile

--- The Audiobook tile, while one plays or is paused (its player).
local function audiobookTile(plugin)
    if not Touch.player() then return nil end
    local okA, Audiobook = pcall(require, "gzreader_audiobook")
    local cur = okA and Audiobook.current
    if not (cur and cur.book) then return nil end
    return { id = "audiobook", icon = "readaloud", label = cur.playing and _("Audiobook ▶") or _("Audiobook"), on = cur.playing == true,
        run = function() Audiobook.open(plugin, cur.book) end }
end
Panel.audiobookTile = audiobookTile

--- The Quick note tile, while Memos is connected: a new note over whatever
--- is on screen (gzreader_notes is only loaded when it's used).
local function quickNoteTile(plugin)
    local store = plugin and plugin.store and plugin.store.memos
    if not (type(store) == "table" and require("gzreader_memos"):new(store):isConnected()) then return nil end
    return { id = "note", icon = "quicknote", label = _("Quick note"), run = function() require("gzreader_notes").quickNote(plugin) end }
end
Panel.quickNoteTile = quickNoteTile

--- Home's tiles (the file manager).
function Panel.homeTiles(plugin, book)
    local HomeMenu = require("gzreader_homemenu")
    local list = {}
    if book then
        list[#list + 1] = { id = "manage", icon = "manage", label = T(_("Manage “%1”"), shortTitle(book.path)), run = function()
            HomeMenu.manageBook(plugin, book)
        end }
    end
    list[#list + 1] = { id = "continue", icon = "continue", label = _("Continue"), run = function() dispatch("open_previous_document") end }
    if not require("gzreader_net").usb then -- (no Wi-Fi: Sync, in Controls)
        -- (Connect: the page your phone or computer opens, at its first tab; Send books is one of them)
        list[#list + 1] = { id = "send", icon = "connect", label = _("Connect"), run = function() plugin:openPhonePage(nil) end }
    end
    list[#list + 1] = { id = "search", icon = "search", label = _("Search"), run = function() dispatch("file_search") end }
    list[#list + 1] = { id = "history", icon = "history", label = _("History"), full = true, run = function() dispatch("history") end }
    list[#list + 1] = { id = "view", icon = "view", label = _("View"), run = function() HomeMenu.showDisplay() end }
    list[#list + 1] = { id = "sort", icon = "sort", label = _("Sort"), run = function() HomeMenu.showSort() end }
    list[#list + 1] = quickNoteTile(plugin)
    list[#list + 1] = musicTile(plugin)
    list[#list + 1] = audiobookTile(plugin)
    local Tasks = require("gzreader_tasks")
    if Tasks.count() > 0 then
        local item = Tasks.menuItem()
        list[#list + 1] = { id = "tasks", icon = "updates", label = item.text_func(), run = function() item.callback() end }
    end
    return shown("home", list)
end

--- A book's tiles (the reader).
function Panel.bookTiles(plugin, ui)
    local function send(name) return function() ui:handleEvent(Event:new(name)) end end
    local list = {}
    if plugin.sync then
        list[#list + 1] = { id = "sync", icon = "sync", label = _("Sync with Grimmory"), run = function() plugin:onGrimmorySyncNow() end }
    end
    -- reader controls, as a swipe up from the bottom opens them: contents, bookmarks, go to page, the
    -- font, the layout (Fit pictures in it) — they were six tiles here (the owner, 2026-11-26)
    list[#list + 1] = { id = "controls", icon = "layout", label = _("Reader tools"), run = function() Panel.readerControls(ui) end }
    list[#list + 1] = { id = "bookmark", icon = "bookmark", label = _("Bookmark"), on = ui.view and ui.view.dogear_visible == true,
        run = send("ToggleBookmark") }
    local tts = plugin.tts
    -- (a narrated book: Read aloud plays its own narration, the sentence highlighted: gzreader_narration.lua)
    local okn, narrated = pcall(function() return require("gzreader_narration").forReadAloud(ui) end)
    if okn and narrated then
        local N = require("gzreader_narration")
        list[#list + 1] = { id = "readaloud", icon = "readaloud", label = _("Read aloud"), on = N.playingIn(ui),
            run = function() N.toggle(ui) end }
    elseif tts and tts:supported() then
        list[#list + 1] = { id = "readaloud", icon = "readaloud", label = _("Read aloud"), on = tts.active == true, run = function() tts:toggle() end }
    end
    -- (people, places, terms and what's happened so far, from the book's text: gzreader_storyguide.lua)
    local oks, Story = pcall(require, "gzreader_storyguide")
    if oks then list[#list + 1] = Story.tile(plugin, ui) end
    list[#list + 1] = quickNoteTile(plugin)
    -- (the page as a drawing's background, the markup kept in Memos: gzreader_bookmarkup.lua)
    local okm, BookMarkup = pcall(require, "gzreader_bookmarkup")
    if okm then list[#list + 1] = BookMarkup.tile(plugin, ui) end
    -- (a big screen: the book in one half, a page for notes in the other)
    list[#list + 1] = require("gzreader_splitview").tile(plugin)
    list[#list + 1] = musicTile(plugin)
    list[#list + 1] = audiobookTile(plugin)
    -- (cards made from what you read, and a quiz: gzreader_flashcards.lua)
    local okf, Cards = pcall(require, "gzreader_flashcards")
    if okf then list[#list + 1] = Cards.tile(plugin, ui) end
    return shown("book", list)
end

--- The layout panel (KOReader's bottom config menu: size, margins, spacing…).
--- Opened with force: ZenOS's Zen mode blocks a plain ShowConfigMenu on touch
--- Kindles (meant for the bottom swipe), as its own reader controls do.
--- The Reader tools tile: on a touch Kindle, whatever the swipe up from the bottom
--- of a book opens (Settings → Reader → Bottom swipe gesture: the page
--- browser, reader controls, …; ZenOS's page_browser.lua); otherwise, or when
--- that swipe is off, ZenOS's reader controls (KOReader's bottom menu where
--- ZenOS's aren't there).
function Panel.readerControls(ui)
    local menu = ui and ui.menu
    if Device.isTouchDevice and Device:isTouchDevice() then
        local okb, BottomSwipe = pcall(require, "common/reader_bottom_swipe")
        if okb and type(BottomSwipe) == "table" and type(BottomSwipe.gz_open) == "function" then
            local ok, done = pcall(BottomSwipe.gz_open, ui)
            if ok and done then return true end
        end
    end
    if menu and not menu.onShowReaderControls then
        local zen = rawget(_G, "__ZEN_UI_PLUGIN") or ui.zenos
        if zen then pcall(function() require("modules/menu/patches/reader_controls")(zen) end) end
    end
    if menu and menu.onShowReaderControls then return menu:onShowReaderControls() end
    return Panel.showLayout(ui)
end

function Panel.showLayout(ui)
    if ui.config and ui.config.onShowConfigMenu then return ui.config:onShowConfigMenu(true) end
    ui:handleEvent(Event:new("ShowConfigMenu"))
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
            -- (ZenOS rows: the font icon, the one in use ticked on the right)
            items[#items + 1] = { text = it.text_func and it.text_func() or it.text or it.menu_item_id,
                mandatory = on and "\u{2713}" or nil, gz_run = it.callback, gz_icon = "font" }
        end
    end
    require("gzreader_rows").mark(items)
    local menu
    menu = Menu:new{ title = _("Font"), item_table = items, covers_fullscreen = true, is_borderless = true,
        width = Screen:getWidth(), height = Screen:getHeight(),
        is_popout = false, title_bar_fm_style = true,
        onMenuSelect = function(_m, item)
            UIManager:close(menu)
            if item.gz_run then UIManager:nextTick(item.gz_run) end
            return true
        end }
    require("gzreader_rows").apply(menu)
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
    local keys = Touch.keys()
    self.keys = keys
    local cols = Panel.columns(sw, pad, gap, keys)
    self.cols = cols
    local tw = math.floor((sw - 2 * pad - (cols - 1) * gap) / cols)
    local th = tw
    -- (a group with every tile hidden in Settings isn't drawn)
    local groups = {}
    for _i, g in ipairs({ { title = _("Controls"), tiles = self.controls, letters = Panel.TOP_KEYS },
        { title = self.section_title, tiles = self.section, letters = Panel.SECOND_KEYS },
        -- (your own tiles: the keys the second group leaves, from the end of its row)
        { title = _("Your tiles"), tiles = self.own or {}, letters = Panel.ownKeys(#(self.section or {})) } }) do
        if #g.tiles > 0 then groups[#groups + 1] = g end
    end
    local light = Device:hasFrontlight() and Device:isTouchDevice()
    local warmth = light and Panel.hasWarmth()
    local volume = Panel.hasVolume()
    -- (fit the screen: smaller tiles on a short one)
    local rows = 0
    for _i, g in ipairs(groups) do rows = rows + math.ceil(#g.tiles / cols) end
    local fixed = S(40) + (light and S(52) or 0) + (warmth and S(52) or 0) + (volume and S(52) or 0) + #groups * S(30) + S(30)
    local max_th = math.floor((sh * 0.86 - fixed - (rows - 1) * gap) / math.max(1, rows))
    th = math.max(S(60), math.min(th, max_th))
    self.layout = {}
    self.placed = {}
    local y = S(40)
    if light then
        self.light_y = y
        y = y + S(52)
    end
    if warmth then
        self.warmth_y = y
        y = y + S(52)
    end
    if volume then
        self.volume_y = y
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
            local tile = Tile:new{ w = tw, h = th, icon = t.icon, label = t.label, sub = t.sub, side = t.side or nil, on = t.on,
                key = keys and g.letters[i] or nil,
                callback = nil }
            tile.callback = function() self:pick(t, tile) end
            -- (the side part, while there is one: the panel closes and it runs)
            tile.side_callback = function() if t.side then self:pick({ run = t.side.run }) end end
            if t.hold then tile.hold = function() self:pick({ run = t.hold, full = true }) end end
            tile.gz_tile = t
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
    if light or volume then
        -- drag the slider (pan while moving, then its release; a quick drag is a swipe;
        -- the strip covers every slider: the light, the warmth, the volume)
        local strip = function()
            local top = self.light_y or self.volume_y
            local bottom = self.volume_y or self.warmth_y or self.light_y
            return Geom:new{ x = 0, y = top - S(10), w = sw, h = bottom - top + S(64) }
        end
        -- (only a drag that starts with a finger put down on the slider: the
        -- swipe down that opens the panel in a book is still going when it
        -- appears, and its rest would set the light where the finger passed)
        self.ges_events.TouchPanel = { GestureRange:new{ ges = "touch", range = whole } }
        self.ges_events.PanLight = { GestureRange:new{ ges = "pan", range = strip } }
        self.ges_events.PanReleaseLight = { GestureRange:new{ ges = "pan_release", range = strip } }
        self.ges_events.SwipeLight = { GestureRange:new{ ges = "swipe", range = strip } }
    end
end

--- The sliders on screen, top to bottom: "light", then "warmth" (a warm light).
function PanelWidget:sliders()
    local list = {}
    if self.light_y then list[#list + 1] = { kind = "light", y = self.light_y } end
    if self.warmth_y then list[#list + 1] = { kind = "warmth", y = self.warmth_y } end
    if self.volume_y then list[#list + 1] = { kind = "volume", y = self.volume_y } end
    return list
end

--- The slider a finger at y is on (the one whose bar is nearest), or nil.
function PanelWidget:sliderAtY(y)
    local best, dist
    for _i, s in ipairs(self:sliders()) do
        if y >= s.y - S(10) and y <= s.y + S(54) then
            local d = math.abs(y - (s.y + S(20)))
            if not dist or d < dist then best, dist = s.kind, d end
        end
    end
    return best
end

function PanelWidget:sliderInfo(kind)
    if kind == "warmth" then return self:warmthInfo() end
    if kind == "volume" then return self:volumeInfo() end
    return self:lightInfo()
end

function PanelWidget:setSlider(kind, v, dragging)
    if kind == "warmth" then return self:setWarmth(v, dragging) end
    if kind == "volume" then return self:setVolume(v, dragging) end
    return self:setLight(v, dragging)
end

--- A slider's value at position x (the bar only; − and + are buttons).
function PanelWidget:sliderAt(kind, x, final)
    local min, max = select(2, self:sliderInfo(kind))
    local bar = self:lightBar(0)
    local f = math.max(0, math.min(1, (x - bar.x) / math.max(1, bar.w)))
    local v = math.floor(min + f * (max - min) + 0.5)
    if v == self._dragged and not final then return true end
    self._dragged = v
    self:setSlider(kind, v, not final)
    return true
end

--- The light at the slider's position x.
function PanelWidget:lightAt(x, final) return self:sliderAt("light", x, final) end

--- A finger put down: a slider follows a drag only if it went down on it
--- (_light_touched: which one, "light" or "warmth", or false).
function PanelWidget:onTouchPanel(_arg, ges)
    local y = ges and ges.pos and ges.pos.y
    self._light_touched = (y and self:sliderAtY(y)) or false
    return false
end

function PanelWidget:onPanLight(_arg, ges)
    if not (self._light_touched and ges and ges.pos) then return true end
    return self:sliderAt(self._light_touched, ges.pos.x)
end

function PanelWidget:onPanReleaseLight(_arg, ges)
    self._dragged = nil
    local touched = self._light_touched
    self._light_touched = false
    if not (touched and ges and ges.pos) then return true end
    return self:sliderAt(touched, ges.pos.x, true)
end

function PanelWidget:onSwipeLight(_arg, ges)
    local touched = self._light_touched
    self._light_touched = false
    if not touched then return true end
    if not (ges and ges.pos and (ges.direction == "east" or ges.direction == "west")) then return true end
    -- (pos is where it started: end where it went)
    local x = ges.pos.x + (ges.direction == "east" and 1 or -1) * (ges.distance or 0)
    self._dragged = nil
    return self:sliderAt(touched, x, true)
end

function PanelWidget:getSize() return self.dimen end

function PanelWidget:pick(t, tile)
    -- (a tile that stays, e.g. Wi-Fi: run it and draw it again, the panel open)
    if t.stay and tile then
        UIManager:nextTick(function()
            if t.run then t.run() end
            self:refreshTile(t, tile)
        end)
        return
    end
    UIManager:close(self)
    if t.run then UIManager:nextTick(function()
        t.run()
        if t.full then UIManager:scheduleIn(0.4, function() UIManager:setDirty(nil, "full") end) end
    end) end
end

--- A tile that stays, drawn again from its refresh (its icon, label, on,
--- what a tap does next), with the status row (Wi-Fi on/off).
function PanelWidget:refreshTile(t, tile)
    local fresh = t.refresh and t.refresh()
    if fresh then
        for k, v in pairs(fresh) do t[k] = v end
        t.on = fresh.on -- (nil when off)
        tile.icon, tile.label, tile.on = fresh.icon, fresh.label, fresh.on and true or false
        tile.sub, tile.side = fresh.sub, fresh.side or nil
    end
    UIManager:setDirty(self, "ui")
end

--- Wi-Fi went on or off (KOReader tells every window): the Wi-Fi tile and
--- the status row follow while the panel is open.
function PanelWidget:refreshStaying()
    for _i, p in ipairs(self.placed or {}) do
        local t = p.tile and p.tile.gz_tile
        if t and t.stay then self:refreshTile(t, p.tile) end
    end
end
function PanelWidget:onNetworkConnected() self:refreshStaying() end
function PanelWidget:onNetworkDisconnected() self:refreshStaying() end
function PanelWidget:onNetworkStateChanged() self:refreshStaying() end
-- (ZenOS's Bluetooth module says so while it switches and once it's done)
function PanelWidget:onBluetoothStateChanged() self:refreshStaying() end

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
    local wifi = NetworkMgr:isWifiOn() and _("Wi-Fi") or _("Wi-Fi off")
    if not usbOnly() and require("gzreader_net").mode() == "auto" then wifi = T(_("%1 (auto)"), wifi) end
    local right = wifi .. (cap and (" · " .. cap .. "%") or "")
    local rt = TextWidget:new{ text = right, face = face }
    rt:paintTo(bb, x + w - S(16) - rt:getSize().w, y + S(10))
    rt:free()
    if self.light_y then self:paintLight(bb, x, y + self.light_y) end
    if self.warmth_y then self:paintWarmth(bb, x, y + self.warmth_y) end
    if self.volume_y then self:paintVolume(bb, x, y + self.volume_y) end
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

--- Whether this Kindle has a warm light (its colour can be changed).
function Panel.hasWarmth()
    local ok, yes = pcall(function()
        return Device:hasNaturalLight() and Device:getPowerDevice() ~= nil
    end)
    return ok and yes and true or false
end

function PanelWidget:lightInfo()
    local powerd = Device:getPowerDevice()
    local min, max = powerd.fl_min or 0, powerd.fl_max or 24
    local cur = powerd:frontlightIntensity() or min
    return powerd, min, max, cur
end

--- The warmth in the Kindle's own steps (powerd's public warmth is 0 to 100).
function PanelWidget:warmthInfo()
    local powerd = Device:getPowerDevice()
    local min, max = powerd.fl_warmth_min or 0, powerd.fl_warmth_max or 100
    local cur = powerd:toNativeWarmth(powerd:frontlightWarmth() or 0) or min
    return powerd, min, max, cur
end

--- The room between a slider's − / + button and its bar.
function Panel.BAR_GAP() return S(20) end

function PanelWidget:lightBar(x)
    local w = self.w
    -- (S(20) from each button: half the knob (S(10)) plus room, so the knob
    -- at either end of the bar clears the − and + buttons)
    return { x = x + S(16) + S(44) + Panel.BAR_GAP(), w = w - 2 * S(16) - 2 * (S(44) + Panel.BAR_GAP()) }
end

--- Each slider's − and + icons (icons/panel/<name>.svg): lower and higher.
Panel.SLIDER_ICONS = {
    light = { "light_low", "light_high" },   -- a small dim sun, a big bright one
    warmth = { "warmth_low", "warmth_high" }, -- a snowflake (cool), a flame (warm)
    volume = { "volume_low", "volume_high" }, -- a quiet speaker, a loud one
}

--- One slider row at y: − and + buttons (each with its kind's icon), the bar
--- filled up to cur (fill: its colour).
function PanelWidget:paintSlider(bb, x, y, kind, min, max, cur, fill)
    local bar = self:lightBar(x)
    local cy = y + S(20)
    local icons = Panel.SLIDER_ICONS[kind]
    local isz = S(28)
    for i, label in ipairs({ "\u{2212}", "+" }) do
        local bx = i == 1 and (x + S(16)) or (x + self.w - S(16) - S(44))
        bb:paintBorder(bx, y, S(44), S(40), math.max(2, S(2)), Blitbuffer.COLOR_BLACK, S(8))
        if icons then
            local icon = IconWidget:new{ file = iconFile(icons[i]), width = isz, height = isz, alpha = true }
            icon:paintTo(bb, bx + math.floor((S(44) - isz) / 2), y + math.floor((S(40) - isz) / 2))
            icon:free()
        else
            local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 20), bold = true }
            local ts = t:getSize()
            t:paintTo(bb, bx + math.floor((S(44) - ts.w) / 2), y + math.floor((S(40) - ts.h) / 2))
            t:free()
        end
    end
    local bh = S(10)
    bb:paintBorder(bar.x, cy - math.floor(bh / 2), bar.w, bh, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, math.floor(bh / 2))
    local f = (max > min) and (cur - min) / (max - min) or 0
    local fw = math.floor(bar.w * f)
    if fw > 0 then bb:paintRoundedRect(bar.x, cy - math.floor(bh / 2), fw, bh, fill, math.floor(bh / 2)) end
    local knob = S(20)
    local kx = bar.x + fw - math.floor(knob / 2)
    bb:paintRoundedRect(kx, cy - math.floor(knob / 2), knob, knob, Blitbuffer.COLOR_WHITE, math.floor(knob / 2))
    bb:paintBorder(kx, cy - math.floor(knob / 2), knob, knob, math.max(2, S(2)), Blitbuffer.COLOR_BLACK, math.floor(knob / 2))
end

function PanelWidget:paintLight(bb, x, y)
    local min, max, cur = select(2, self:lightInfo())
    self:paintSlider(bb, x, y, "light", min, max, cur, Blitbuffer.COLOR_BLACK)
end

--- The warmth: filled in grey; a snowflake on −, a flame on +.
function PanelWidget:paintWarmth(bb, x, y)
    local min, max, cur = select(2, self:warmthInfo())
    self:paintSlider(bb, x, y, "warmth", min, max, cur, Blitbuffer.COLOR_DARK_GRAY)
end

--- The slider's row to refresh after a change (the bar and the knob).
function PanelWidget:sliderDirty(kind, dragging)
    local sy = (kind == "warmth" and self.warmth_y) or (kind == "volume" and self.volume_y) or self.light_y
    -- (while dragging: the quick black-and-white refresh)
    UIManager:setDirty(self, function()
        return dragging and "fast" or "ui", Geom:new{ x = 0, y = sy, w = self.w, h = S(44) }
    end)
end

function PanelWidget:setLight(v, dragging)
    local powerd, min, max = self:lightInfo()
    v = math.max(min, math.min(max, math.floor(v + 0.5)))
    powerd:setIntensity(v)
    -- (auto brightness on: where you leave it is remembered as how you like it)
    if not dragging then pcall(function() require("gzreader_autolight").userSet(v) end) end
    self:sliderDirty("light", dragging)
end

--- v in the Kindle's own warmth steps (warmthInfo's min to max).
function PanelWidget:setWarmth(v, dragging)
    local powerd, min, max = self:warmthInfo()
    v = math.max(min, math.min(max, math.floor(v + 0.5)))
    powerd:setWarmth(powerd:fromNativeWarmth(v))
    self:sliderDirty("warmth", dragging)
end

---------------------------------------------------------------- the volume

--- Whether the panel gets a volume slider: touch Kindles with sound (the
--- Kindle Touch's speaker and headphones; Bluetooth Kindles, the volume of
--- Bluetooth headphones or a speaker). The Kindle 2, 3 and DX have volume buttons.
function Panel.hasVolume()
    if Panel.volume_present ~= nil then return Panel.volume_present end
    local ok, yes = pcall(function()
        return Device:isTouchDevice() and (Touch.audio() or Touch.ivona()) and true or false
    end)
    return ok and yes or false
end

--- The volume: the Kindle's Bluetooth steps (1-8) or the speaker's (0-15),
--- the same one read aloud's and the audiobook player's settings show.
function PanelWidget:volumeInfo()
    local TTS = require("gzreader_tts")
    local min = TTS.hasIvona() and 1 or 0
    local max = TTS.volumeMax()
    local cur = math.max(min, math.min(max, TTS.volume() or min))
    return TTS, min, max, cur
end

--- The volume: filled in grey; a quiet speaker on −, a loud one on +.
function PanelWidget:paintVolume(bb, x, y)
    local min, max, cur = select(2, self:volumeInfo())
    self:paintSlider(bb, x, y, "volume", min, max, cur, Blitbuffer.COLOR_DARK_GRAY)
end

function PanelWidget:setVolume(v, dragging)
    local TTS, min, max, cur = self:volumeInfo()
    v = math.max(min, math.min(max, math.floor(v + 0.5)))
    if v ~= cur then TTS.setVolume(v) end -- (the audiobook player and music use it too)
    self:sliderDirty("volume", dragging)
end

function PanelWidget:onTapPanel(_arg, ges)
    local pos = ges and ges.pos
    if not pos then return true end
    if pos.y > self.h then UIManager:close(self); return true end
    for _i, s in ipairs(self:sliders()) do
        if pos.y >= s.y and pos.y <= s.y + S(44) then
            local min, max, cur = select(2, self:sliderInfo(s.kind))
            local bar = self:lightBar(0)
            if pos.x < S(16) + S(44) + S(4) then return self:setSlider(s.kind, cur - 1) or true end
            if pos.x > self.w - S(16) - S(44) - S(4) then return self:setSlider(s.kind, cur + 1) or true end
            local f = math.max(0, math.min(1, (pos.x - bar.x) / math.max(1, bar.w)))
            return self:setSlider(s.kind, min + f * (max - min)) or true
        end
    end
    return true
end

function PanelWidget:onClose() UIManager:close(self); return true end
function PanelWidget:onCloseBack() UIManager:close(self); return true end

--- Where a tile and its focus ring (just outside it) are on screen; nil
--- before the tile has been drawn.
function PanelWidget:focusRect(tile)
    local d = tile and tile.gz_painted and tile.dimen
    if not (d and d.w and d.w > 0 and d.h and d.h > 0) then return nil end
    local m = S(5) -- (the ring is S(4) outside the tile)
    return Geom:new{ x = d.x - m, y = d.y - m, w = d.w + 2 * m, h = d.h + 2 * m }
end

local function focusedTile(self)
    local row = self.layout and self.selected and self.layout[self.selected.y]
    return row and row[self.selected.x]
end

--- The 5-way moves the focus: only the tile it leaves and the one it reaches
--- are refreshed (FocusManager's own refresh, the whole screen, is held back);
--- the whole panel if either hasn't been drawn yet.
function PanelWidget:onFocusMove(args)
    local before = focusedTile(self)
    local moved = false
    local real = UIManager.setDirty
    UIManager.setDirty = function(um, widget, how, ...)
        if widget == self and how == "fast" then moved = true; return end
        return real(um, widget, how, ...)
    end
    local ok, r = pcall(FocusManager.onFocusMove, self, args)
    UIManager.setDirty = real
    if not ok then error(r, 0) end
    if not moved then return r end -- (nothing moved: nothing to redraw)
    local after = focusedTile(self)
    local a, b = self:focusRect(before), self:focusRect(after)
    local how = (a and b) and "tiles" or "panel"
    if how == "tiles" then
        UIManager:setDirty(self, function() return "ui", a end)
        if after ~= before then UIManager:setDirty(self, function() return "ui", b end) end
    else
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
    if self.gz_focus_logged ~= how then
        self.gz_focus_logged = how
        require("gzreader_log").info("quick panel: 5-way step refreshes the", how == "tiles" and "two tiles" or "whole panel")
    end
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
    local w = PanelWidget:new{ controls = Panel.controls(plugin), section = section, section_title = title, section_id = id,
        own = require("gzreader_panelcustom").tiles() }
    Panel.open = w
    UIManager:show(w)
    return true
end

Panel._Widget = PanelWidget -- (for the tests)

--- The order of a book's tiles, by id (the owner, 2026-11-26): the book's
--- own tools, then what's made from it (Story guide, Flashcards), notes, what
--- plays, and Quick note last. A tile not listed goes just before Quick note.
Panel.BOOK_ORDER = { "sync", "controls", "contents", "bookmark", "bookmarks", "gotopage", "font", "layout",
    "fitpictures", "readaloud", "storyguide", "storysofar", "flashcards", "markup", "split", "music", "audiobook", "note" }

--- `list` in Panel.BOOK_ORDER (a copy; tiles with the same place keep theirs). Pure.
function Panel.inBookOrder(list)
    local rank = {}
    for i, id in ipairs(Panel.BOOK_ORDER) do rank[id] = i end
    local unknown = (rank.note or #Panel.BOOK_ORDER + 1) - 0.5
    local keyed = {}
    for i, t in ipairs(list) do keyed[i] = { t = t, r = rank[t.id] or unknown, i = i } end
    table.sort(keyed, function(a, b) if a.r ~= b.r then return a.r < b.r end return a.i < b.i end)
    local out = {}
    for i, k in ipairs(keyed) do out[i] = k.t end
    return out
end

return Panel
