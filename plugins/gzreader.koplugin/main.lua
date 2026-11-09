--[[--
Grimmory for KOReader.

* Pair with a Grimmory server by scanning a QR code shown on the Kindle (the
  phone does the typing), or by typing on the Kindle's own keyboard.
* Browse the library and download books (text-only lists, no thumbnails).
* Native progress sync through Grimmory's own reading-progress API (the one
  its web reader uses), plus reading sessions for Grimmory's statistics.
  No KOReader sync account, permission or file-hash matching involved.

@module koplugin.gzreader
]]

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local Net = require("gzreader_net")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Api = require("gzreader_api")
local Sync = require("gzreader_sync")
-- Loaded on first use (pairing, browsing, downloading, read aloud), not at start.
local LAZY = { Browser = "gzreader_browser", PairPage = "gzreader_pairpage", PairScreen = "gzreader_pairscreen",
    PairServer = "gzreader_pairserver", Download = "gzreader_download", TTS = "gzreader_tts", Touch = "gzreader_touch",
    Annotations = "gzreader_annotations" }
local Mod = setmetatable({}, { __index = function(t, k)
    local v = require(LAZY[k])
    rawset(t, k, v)
    return v
end })
local Log = require("gzreader_log")
local Index = require("gzreader_index")
local JSON = require("gzreader_json")
local Bookmarks = require("gzreader_bookmarks")

local PAIR_TIMEOUT_S = 10 * 60
local MAX_QUEUED_SESSIONS = 200

-- Night mode makes legacy Kindles unusably slow (software inversion): keep it off.
pcall(function() require("gzreader_nightguard").install() end)
-- Kindles without REAGL: flash when most of the screen changes (less ghosting).
pcall(function() require("gzreader_eink").install() end)

local Grimmory = WidgetContainer:extend{
    name = "gzreader",
    is_doc_only = false,
}

function Grimmory:init()
    -- One settings object for the whole run, shared by every instance: KOReader
    -- creates a new plugin instance for each FileManager/ReaderUI, and a
    -- background download or queued sync data must not be written to a stale copy.
    if not Grimmory.shared_settings then
        -- how long this start takes (a log line once Home is on screen: gzreader_opentiming.lua)
        pcall(function() require("gzreader_opentiming").bootBegin() end)
        Grimmory.shared_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/gzreader.lua")
        Log.init(DataStorage:getDataDir())
        pcall(function() require("gzreader_remote").keepPreviousLog() end)
        Log.info("---- plugin loaded", "koreader", tostring(require("version"):getCurrentRevision()),
            "device", tostring(Device.model))
        pcall(function() require("gzreader_timezone").apply() end)
    end
    pcall(Net.start)
    if not Grimmory.usage_scheduled then
        Grimmory.usage_scheduled = true
        UIManager:scheduleIn(15, function() pcall(function() require("gzreader_usage").start() end) end)
    end
    self.settings = Grimmory.shared_settings
    require("gzreader_audioengine").root = self.path
    if Device.gz_menu_perpage and not Grimmory.dx_lists then
        -- (the DX: more to a list's page, the text as big as 14 to a page on a 6" Kindle)
        Grimmory.dx_lists = true
        local Menu = require("ui/widget/menu")
        Menu.items_per_page_default = Device.gz_menu_perpage
        local item_font = Menu.getItemFontSize
        Menu.getItemFontSize = function(perpage)
            return item_font(math.max(6, math.floor(perpage * 14 / Device.gz_menu_perpage + 0.5)))
        end
        local mandatory = Menu.getItemMandatoryFontSize
        Menu.getItemMandatoryFontSize = function(perpage)
            return mandatory(math.max(6, math.floor(perpage * 14 / Device.gz_menu_perpage + 0.5)))
        end
    end
    if Device.lcd and not Grimmory.nook_screen then
        -- Nook 1st Edition: GZreader's panels on the colour touchscreen
        Grimmory.nook_screen = true
        UIManager:nextTick(function() pcall(function() require("gzreader_nook").install() end) end)
    end
    if not Grimmory.audio_checked then
        Grimmory.audio_checked = true
        pcall(function() require("gzreader_audioengine").stopStrayAtStart() end)
        -- the Kindle's screensaver block an earlier run left on (closed or
        -- crashed mid-download): lifted, nothing of ours holds it yet
        pcall(function() require("gzreader_awake").reset() end)
        -- the volume rocker, and stopping the audio when GZreader closes
        pcall(function() require("gzreader_audioctl").install() end)
        -- a log line per book opened: where the time went
        pcall(function() require("gzreader_opentiming").install() end)
        -- background processes wait while a book opens (released in onReaderReady)
        pcall(function()
            local ReaderUI = require("apps/reader/readerui")
            local orig_show = ReaderUI.showReader
            ReaderUI.showReader = function(rui, ...)
                pcall(require("gzreader_async").pause, "a book opens")
                return orig_show(rui, ...)
            end
        end)
    end
    -- a book: highlights too light to see on a greyscale screen (yellow, from
    -- Grimmory's web reader) are drawn like the grey one (gzreader_hlcolor.lua)
    if self.ui and self.ui.view then pcall(function() require("gzreader_hlcolor").install() end) end
    self.store = self.settings:readSetting("state", {})
    if not Grimmory.recent_applied then
        Grimmory.recent_applied = true
        local ok_r, applied = pcall(Grimmory.applyRecent, self.store)
        -- (written to gzreader.lua at the first save, so a stale recent part can't come back)
        if ok_r and applied then Grimmory.full_due, Grimmory.recent_written = true, true end
    end
    Grimmory.last_instance = self -- (every instance shares the store: the exit's last save)
    self.store.downloads = self.store.downloads or {}
    self.store.pending = self.store.pending or { progress = {}, sessions = {} }
    self.store.pending.ratings = self.store.pending.ratings or {}
    Log.enabled = self.store.logging_disabled ~= true
    self.api = Api:new(self.store, function() self:save() end)
    -- no Wi-Fi (Kindle 2, DX): Grimmory through a computer, the library
    -- from the copy the sync page left (gzreader_usbsync.lua)
    local Usb = require("gzreader_usbsync")
    if Usb.active() then
        local okd, dir = pcall(Usb.dir, self)
        if okd and dir then self.api = require("gzreader_offlineapi"):new(self.store, function() self:save() end, dir) end
    end
    pcall(Usb.start, self)
    -- a login a background process got but GZreader never saved (it was
    -- closed or restarted meanwhile): take it (gzreader_api.lua)
    if Api.recoverPending(self.store) then
        Log.info("Grimmory login: kept the one a background request got before GZreader closed")
        self:save()
    end
    -- the Access key / Cloudflare token on requests to your own servers
    pcall(function() require("gzreader_access").install(self) end)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    -- remote debugging (off until a feed address is set)
    pcall(function() require("gzreader_remote").start(self) end)
    if not self.ui.document and not self.store.home_is_library then
        -- Grimmory build: the home folder is the GZreader folder (no setup question)
        pcall(self.useLibraryAsHome, self)
    elseif not self.ui.document then
        -- and it stays so (an older build's "Set home folder" may have changed it)
        pcall(function()
            local dir = self:libraryDir()
            if G_reader_settings:readSetting("home_dir") ~= dir then
                G_reader_settings:saveSetting("home_dir", dir)
                Log.info("home folder set back to", dir)
            end
        end)
    end
    if not self.ui.document then
        -- download status in ZenOS's title bar (after every plugin has loaded)
        UIManager:nextTick(function() pcall(function() require("gzreader_tasks").installStatusBar() end) end)
        -- touch Kindles: GZreader's menu, the phone page and Send books in ZenOS's launcher
        UIManager:nextTick(function() pcall(self.addLauncherEntries, self) end)
        -- Pre-size downloaded books' covers in the background (fast Home/library)
        pcall(function()
            local Warm = require("gzreader_coverwarm")
            Warm.schedule(self, Warm.START_DELAY)
            require("common/cover_disk_cache").on_new_size = function() Warm.schedule(self, 30) end
        end)
        -- (once a run: KOReader starts the plugin again each time a book closes)
        if not Grimmory.manifest_checked then
            Grimmory.manifest_checked = true
            pcall(self.restoreFromManifest, self)
        end
        -- audiobooks: stored in a hidden folder; Downloads → Audiobooks lists them
        if Mod.Touch.audio() then
            pcall(function() require("gzreader_abfolder").start(self) end)
            -- downloaded music: Downloads → Music (on the bookshelf, a CD player)
            pcall(function() require("gzreader_musicfolder").start(self) end)
        end
        -- Home's "Grimmory reading stats" (every device's reading, from Grimmory)
        local plugin_ref = self
        rawset(_G, "__GZ_GRIMMORY_STATS", function() return require("gzreader_grimstats").values(plugin_ref) end)
        -- Downloads and the other book folders as bookshelves (the View)
        -- (after every plugin has patched the file browser)
        UIManager:nextTick(function() pcall(function()
            local SV = require("gzreader_shelfview")
            SV.plugin = plugin_ref -- (the authors Grimmory has, for spines whose files have none)
            rawset(_G, "__GZ_GRIMMORY_AUTHORS", SV.grimmoryAuthors) -- (Home's shelf too: shelf.lua)
            SV.install()
            -- square covers in the Bookshelf view (also when it was chosen earlier)
            local GV = require("common/gz_view")
            if GV.applyCorners() then
                local FM = require("apps/filemanager/filemanager").instance
                if FM and FM.file_chooser then FM.file_chooser:updateItems() end
                GV.redrawHome()
            end
        end) end)
        -- downloads from before 1.22.4 don't know their Grimmory authors yet
        UIManager:scheduleIn(15, function() pcall(self.backfillAuthors, self) end)
        -- books on bookshelves (Home and Downloads), once (1.19.0); the quick
        -- panel's View changes it
        if G_reader_settings:readSetting("gzreader_view") == nil then
            G_reader_settings:makeTrue("gzreader_downloads_list_v1")
            UIManager:nextTick(function()
                pcall(function() require("common/gz_view").set("bookshelf") end)
            end)
        end
        -- downloads / audiobook preparing cut short last time: ask what to do
        pcall(function() require("gzreader_recovery").schedule(self) end)
        if self.api:isPaired() then
            UIManager:scheduleIn(8, function()
                if not NetworkMgr:isConnected() then return end
                pcall(require("gzreader_shelfsync").run, self)
                local idx = Index.load(self.store)
                if idx then self:libraryUpkeep(idx) end
                if Index.isStale(idx) then
                    Index.build(self, false, function(built)
                        if built then self:libraryUpkeep(built, true) end
                    end)
                end
            end)
        end
    end
    if not self.ui.document and self.ui.menu then
        -- Every Kindle (and the Nook): the Menu key, a tap at the top or a
        -- swipe down (anything that opens "the menu") opens GZreader's quick
        -- panel (gzreader_panel.lua: square tiles, letter keys or the 5-way
        -- or a tap) instead of ZenOS's / KOReader's menu.
        -- ZenOS's Home page, its lists and OPDS call onShowMenu() directly,
        -- so that is the one replaced (HomeMenu.fullMenu() sets _gz_full to
        -- reach the original).
        local fm_menu = self.ui.menu
        local orig_show = fm_menu.onShowMenu
        local orig_key = fm_menu.onKeyPressShowMenu
        local plugin = self
        fm_menu.onShowMenu = function(m, ...)
            if not m._gz_full then return require("gzreader_panel").show(plugin) end
            return orig_show and orig_show(m, ...)
        end
        fm_menu.onKeyPressShowMenu = function(m, a, k)
            if not m._gz_full then return require("gzreader_panel").show(plugin) end
            return orig_key and orig_key(m, a, k) or (orig_show and orig_show(m))
        end
        -- a long press on a book on Home: Manage it (Open and Delete, then
        -- ZenOS's own book menu), as the panel's Manage tile does
        rawset(_G, "__GZ_MANAGE_BOOK", function(path, context)
            require("gzreader_homemenu").manageBook(plugin, { path = path, context = context })
            return true
        end)
        -- …and in the Downloads tab (the file list is laid out after this)
        require("gzreader_homemenu").hookHold()
    end
    if not self.ui.document and type(self.ui.active_widgets) == "table" then
        -- Dispatcher actions (e.g. ZenOS's Grimmory tab) are sent to the top
        -- window only; ZenOS's Home page sits above the file manager. Being an
        -- active widget lets our events still reach us. File manager only, so
        -- reader events are never delivered twice.
        table.insert(self.ui.active_widgets, self)
    end
    if not Grimmory.boot_timed then
        Grimmory.boot_timed = true
        pcall(function() require("gzreader_opentiming").bootReady() end)
    end
end

--[[ Saving GZreader's state.
settings/gzreader.lua holds all of it (`state`). Most saves only change small
things (a queued position, what was sent), but writing that file dumps the
whole state, sorted and indented, the download list and audiobooks included:
about 0.15–0.3 s of a Kindle 3's CPU per save with 500 books, plus a 250 KB
synced write. So:
- a save whose big parts (BIG_KEYS) and sign-in (FULL_KEYS) are as last
  written writes only the rest to settings/gzreader_recent.lua (`state`,
  `seq`), a few KB;
- otherwise, and on sleep, on exit and at least every FULL_EVERY seconds, the
  whole of gzreader.lua is written, and gzreader_recent.lua is removed.
At start, gzreader_recent.lua is laid over gzreader.lua when its `seq` is newer.
"As last written" is a fingerprint of those parts in rapidjson (fast); where
rapidjson isn't there, every save writes gzreader.lua, as before. gzreader.lua
stays complete, so an older GZreader (after switching test builds off) reads
it as it always did: at most what changed since the last sleep is older there.
]]
Grimmory.BIG_KEYS = { "downloads", "audiobooks", "music_stubs", "shelves_cache", "shelf_cache", "usb_idmap" }
Grimmory.FULL_KEYS = { "server", "username", "refresh_token", "client_id", "device_id" }
Grimmory.FULL_EVERY = 3600
local BIG = {}
for _i, k in ipairs(Grimmory.BIG_KEYS) do BIG[k] = true end

function Grimmory.recentPath() return DataStorage:getSettingsDir() .. "/gzreader_recent.lua" end

--- A fingerprint of the parts that make a save a full one, or nil (no fast
--- JSON: every save is full).
function Grimmory.fingerprint(store)
    local Json = require("gzreader_json")
    if not Json.rapidjson then return nil end
    local part = {}
    for _i, k in ipairs(Grimmory.BIG_KEYS) do part[k] = store[k] end
    for _i, k in ipairs(Grimmory.FULL_KEYS) do part[k] = store[k] end
    local ok, s = pcall(Json.rapidjson.encode, part)
    return ok and type(s) == "string" and s or nil
end

--- At start: what gzreader_recent.lua has, if it was written after gzreader.lua.
function Grimmory.applyRecent(store)
    local ok, rs = pcall(LuaSettings.open, LuaSettings, Grimmory.recentPath())
    if not ok or not rs then return false end
    local seq, small = rs:readSetting("seq"), rs:readSetting("state")
    if type(seq) ~= "number" or type(small) ~= "table" or seq <= (tonumber(store.save_seq) or 0) then return false end
    for k in pairs(store) do
        if not BIG[k] and small[k] == nil then store[k] = nil end
    end
    for k, v in pairs(small) do
        if not BIG[k] then store[k] = v end
    end
    store.save_seq = seq
    Log.info("state: the recent part laid over gzreader.lua (save", seq, ")")
    return true
end

function Grimmory:save()
    if Grimmory.save_soon then UIManager:unschedule(Grimmory.save_soon); Grimmory.save_soon = nil end
    local usb = Net.usb and require("gzreader_usbsync") or nil
    if usb then pcall(usb.number, self) end -- (queued positions numbered before they're saved)
    local store = self.store
    store.save_seq = (tonumber(store.save_seq) or 0) + 1
    local fp = Grimmory.fingerprint(store)
    local now = os.time()
    if Grimmory.full_due or not fp or fp ~= Grimmory.full_fp or now - (Grimmory.full_at or 0) >= Grimmory.FULL_EVERY then
        self.settings:saveSetting("state", store)
        self.settings:flush()
        Grimmory.full_fp, Grimmory.full_at, Grimmory.full_due = fp, now, false
        if Grimmory.recent_written then
            Grimmory.recent_written = false
            os.remove(Grimmory.recentPath())
            os.remove(Grimmory.recentPath() .. ".old")
        end
        Grimmory.saves_full = (Grimmory.saves_full or 0) + 1
    else
        local small = {}
        for k, v in pairs(store) do
            if not BIG[k] then small[k] = v end
        end
        Grimmory.recent = Grimmory.recent or LuaSettings:open(Grimmory.recentPath())
        Grimmory.recent:saveSetting("seq", store.save_seq)
        Grimmory.recent:saveSetting("state", small)
        Grimmory.recent:flush()
        Grimmory.recent_written = true
        Grimmory.saves_small = (Grimmory.saves_small or 0) + 1
    end
    -- syncing through a computer: what it should send and bring, next to the books
    if usb then usb.writeOutbox(self) end
end

--- Sleep and exit: the whole file, so that gzreader.lua alone is up to date.
function Grimmory:saveFull()
    Grimmory.full_due = true
    self:save()
end

--- Save within a few seconds (once, however many changes come meanwhile):
--- for what changes while you read (the position queued every 10 pages,
--- what was sent). Writing the whole settings file each time stalled page
--- turns on a Kindle 3 as it grew. Written at once on sleep, when a book or
--- GZreader closes (FlushSettings), and by any plain save().
Grimmory.SAVE_SOON_SECONDS = 15
function Grimmory:saveSoon()
    if Grimmory.save_soon then return end
    Grimmory.save_soon = function()
        Grimmory.save_soon = nil
        self:save()
    end
    UIManager:scheduleIn(Grimmory.SAVE_SOON_SECONDS, Grimmory.save_soon)
end

function Grimmory:onFlushSettings()
    if Grimmory.save_soon then self:save() end
end

-- leaving GZreader (exit, restart, update): a save still waiting is written first
do
    local orig_quit = UIManager.quit
    UIManager.quit = function(um, ...)
        local pending = Grimmory.save_soon
        local usb = Net.usb and package.loaded["gzreader_usbsync"]
        if usb and usb.plugin then
            -- syncing through a computer: the open book's exact place, and the outbox, now
            pcall(usb.finishCfis, usb.plugin)
            pcall(usb.handOverUsage, usb.plugin)
            pcall(usb.plugin.save, usb.plugin)
        elseif pending then pcall(pending) end
        return orig_quit(um, ...)
    end
end

function Grimmory:syncEnabled()
    return self.store.sync_disabled ~= true and self.api:isPaired()
end

-- exit: the next save is a whole one, and there is one if only the recent part
-- was written (wraps the "leaving GZreader" save above, which then saves whole)
do
    local orig_quit = UIManager.quit
    UIManager.quit = function(um, ...)
        if Grimmory.recent_written or Grimmory.save_soon then
            Grimmory.full_due = true
            if not Grimmory.save_soon and Grimmory.last_instance then pcall(Grimmory.last_instance.save, Grimmory.last_instance) end
        end
        return orig_quit(um, ...)
    end
end

function Grimmory:onDispatcherRegisterActions()
    -- NB: in KOReader's Dispatcher, `reader = true` means "reader only" (the
    -- action is disabled in the file manager). These work everywhere: general.
    Dispatcher:registerAction("grimmory_library", {
        category = "none", event = "ShowGrimmoryLibrary", title = _("Grimmory library"),
        general = true,
    })
    Dispatcher:registerAction("gzreader_notes", {
        category = "none", event = "ShowGzNotes", title = _("Notes (Memos)"),
        general = true,
    })
    Dispatcher:registerAction("gzreader_calendar", {
        category = "none", event = "ShowGzCalendar", title = _("Calendar (CalDAV)"),
        general = true,
    })
    Dispatcher:registerAction("gzreader_music", {
        category = "none", event = "ShowGzMusic", title = _("Music (Plex)"),
        general = true,
    })
    Dispatcher:registerAction("grimmory_pair", {
        category = "none", event = "GrimmoryPair", title = _("Grimmory: connect with QR code"),
        general = true,
    })
    Dispatcher:registerAction("grimmory_sync_now", {
        category = "none", event = "GrimmorySyncNow", title = _("Grimmory: sync progress now"),
        reader = true,
    })
end

---------------------------------------------------------------- menu

function Grimmory:addToMainMenu(menu_items)
    menu_items.gzreader = {
        text = _("Grimmory"),
        sub_item_table_func = function() return self:menuItems() end,
    }
end

local function closeTouchMenu(touchmenu)
    if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
end

function Grimmory:menuItems()
    local paired = self.api:isPaired()
    local items = {
        {
            text_func = function()
                if self.api:isPaired() then
                    return T(_("Connected as %1"), self.store.username or "?")
                end
                return _("Not connected")
            end,
            enabled = false,
            separator = true,
        },
    }
    if self.sync then
        table.insert(items, {
            text = _("Sync progress now"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                self:onGrimmorySyncNow()
            end,
        })
    end
    local more = {
        {
            text = _("Sync reading progress"),
            help_text = _("Send your position to Grimmory as you read, and pick up where you left off on other devices or in Grimmory's web reader."),
            checked_func = function() return self.store.sync_disabled ~= true end,
            callback = function()
                self.store.sync_disabled = (self.store.sync_disabled ~= true) or nil
                self:save()
            end,
            separator = true,
        },
        require("gzreader_shelfsync").menuItems(self),
        {
            text = _("Sync bookmarks"),
            help_text = _("Keep page bookmarks the same here and in Grimmory (its web reader and other devices)."),
            checked_func = function() return self.store.bookmark_sync_disabled ~= true end,
            callback = function()
                self.store.bookmark_sync_disabled = (self.store.bookmark_sync_disabled ~= true) or nil
                self:save()
            end,
        },
        {
            text = _("Sync highlights and notes"),
            help_text = _("Keep highlights and notes in EPUBs the same here and in Grimmory (its web reader and other devices). A highlight changed in both places since the last sync is left as it is in each."),
            checked_func = function() return self.store.annotation_sync_disabled ~= true end,
            callback = function()
                self.store.annotation_sync_disabled = (self.store.annotation_sync_disabled ~= true) or nil
                self:save()
                if self.annotations and not self.store.annotation_sync_disabled then self.annotations:run() end
            end,
        },
        not Net.usb and {
            text = _("Keep connections open (experimental)"),
            help_text = _("While Wi-Fi is on, a small helper keeps the connections to your servers open between requests, so browsing Grimmory and syncing skip setting up a secure connection each time (seconds on a Kindle 3). It uses a few MB of memory while Wi-Fi is on. Off by default."),
            checked_func = function() return require("gzreader_reqhelper").enabled() end,
            callback = function()
                local Helper = require("gzreader_reqhelper")
                local on = not Helper.setting()
                Helper.setSetting(on)
                if on and Net.connected() then Helper.start(self.path)
                elseif not Helper.enabled() and Helper.endpoint() then Helper.stop() end
            end,
        } or nil,
        {
            text = paired and _("Reconnect from your browser (QR code)") or _("Connect from your browser (QR code)"),
            help_text = _("Shows a QR code and this Kindle's address: the page they open in a browser (phone or computer) connects Grimmory, Notes and calendars, and sends books to this Kindle."),
            callback = function(touchmenu) self:onGrimmoryPair(touchmenu) end,
        },
        {
            text = _("Connect by typing"),
            callback = function() self:keyboardLogin() end,
        },
        {
            text = _("Copy from another GZreader"),
            help_text = _("The address and account from another GZreader on this Wi-Fi (it shows a PIN); then sign in here."),
            callback = function() require("gzreader_copy").receive(self, { only = "grimmory" }) end,
        },
        {
            text = _("Single sign-on (SSO)"),
            sub_item_table_func = function() return self:ssoMenu() end,
            separator = true,
        },
        {
            text = _("Disconnect"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function() self:confirmDisconnect() end,
        },
    }
    for i = 1, table.maxn(more) do if more[i] then table.insert(items, more[i]) end end
    return items
end

-- A list without the items left out (nil): t has n places.
local function packed(n, t)
    local out = {}
    for i = 1, n do if t[i] ~= nil then out[#out + 1] = t[i] end end
    return out
end

--- GZreader's settings that live in ZenOS's other Settings sections
--- (zenos modules/settings/zen_settings.lua puts them there):
---   "general"   { wifi = item, diagnostics = { items } }
---   "reader"    { items }
---   "interface" { items }
function Grimmory:sectionItems(section)
    local okI, IconItem = pcall(require, "common/ui/icon_menu_item")
    local okc, icons = pcall(require, "common/inline_icon_map")
    local function icon(name, item)
        if okI and okc and icons[name] then return IconItem.decorate(item, icons[name]) end
        return item
    end
    if section == "general" then
        return {
            wifi = not Net.usb and icon("wifi_off", {
                text = _("Wi-Fi only when needed"),
                help_text = _("Saves battery: GZreader turns Wi-Fi on by itself for browsing Grimmory, downloads, updates and syncing when a book opens or closes (and on wake after 15 minutes or more), then turns it off after a minute of not being used. Reading-position and bookmark changes made in between wait and go with the next sync. Wi-Fi you turn on yourself stays on."),
                checked_func = function() return G_reader_settings:nilOrTrue("gzreader_wifi_on_demand") end,
                callback = function() G_reader_settings:flipNilOrTrue("gzreader_wifi_on_demand") end,
            }) or nil, -- (no Wi-Fi: nothing to turn on)
            diagnostics = packed(5, {
                icon("settings_bug", {
                    text = _("Diagnostic logging"),
                    help_text = _("Keep a log of Grimmory activity in koreader/gzreader.log (passwords and tokens are never written)."),
                    checked_func = function() return self.store.logging_disabled ~= true end,
                    callback = function()
                        self.store.logging_disabled = (self.store.logging_disabled ~= true) or nil
                        Log.enabled = self.store.logging_disabled ~= true
                        self:save()
                    end,
                }),
                icon("settings_stats", require("gzreader_usage").menuItems()),
                icon("send", {
                    text = Net.usb and _("Send diagnostic log to the developer (at the next sync)") or _("Send diagnostic log to the developer"),
                    callback = function(touchmenu)
                        closeTouchMenu(touchmenu)
                        self:sendLogToDeveloper()
                    end,
                }) or nil,
                not Net.usb and icon("send", {
                    text = _("Send diagnostic log to a browser (QR code)"),
                    callback = function(touchmenu)
                        closeTouchMenu(touchmenu)
                        self:shareLog()
                    end,
                }) or nil,
                icon("save", {
                    text = _("Save diagnostic log (USB)"),
                    callback = function() self:exportLog() end,
                }),
            }),
        }
    elseif section == "reader" then
        if not Mod.Touch.audio() then return {} end -- (no speaker: no read aloud, no audiobooks)
        local items = {}
        -- (read aloud: Shift + Sym, the Kindles with a keyboard)
        if Mod.Touch.tts() then
            items[#items + 1] = icon("vocabulary", {
                text = _("Read aloud"),
                help_text = Mod.Touch.text(_("Volume, speed and the Kindle voice for reading aloud (Shift + Sym while reading)."),
                    _("Volume, speed and the Kindle voice for reading aloud (in a book: Read aloud in the quick panel).")),
                keep_menu_open = true,
                callback = function() self:showTtsSettings() end,
            })
        end
        items[#items + 1] = icon("check", {
            text = _("Test audiobook playback"),
            help_text = _("Plays two short tunes (MP3, and AAC as in M4B audiobooks) with each way this Kindle can play audio and asks which you heard."),
            keep_menu_open = true, -- the test's messages show over Settings
            callback = function() require("gzreader_audioengine").test() end,
        })
        items[#items + 1] = icon("check", {
            text = _("Pause when headphones are unplugged"),
            help_text = _("Music, audiobooks and read aloud pause instead of carrying on out of the speaker. Needs to know where this Kindle says the headphones are plugged in: Find the headphone jack."),
            checked_func = function() return G_reader_settings:readSetting("gzreader_jack_pause") ~= false end,
            callback = function()
                G_reader_settings:saveSetting("gzreader_jack_pause", G_reader_settings:readSetting("gzreader_jack_pause") == false)
            end,
        })
        items[#items + 1] = icon("check", {
            text = _("Find the headphone jack"),
            help_text = _("Asks you to plug in and unplug headphones, and keeps where this Kindle shows it."),
            keep_menu_open = true,
            callback = function() require("gzreader_jack").test() end,
        })
        return items
    elseif section == "interface" then
        local items = {
            icon("settings_covers", {
                text = _("Pre-size covers"),
                help_text = _("In the background, makes each downloaded book's cover at the exact sizes Home and the library show it, and keeps them, so covers appear without the Kindle scaling them every time."),
                checked_func = function() return not G_reader_settings:isFalse("gzreader_presize_covers") end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("gzreader_presize_covers")
                    local Disk = require("common/cover_disk_cache")
                    Disk.enabled = not G_reader_settings:isFalse("gzreader_presize_covers")
                    if Disk.enabled then require("gzreader_coverwarm").schedule(self, 5) else Disk.clear() end
                end,
            }),
        }
        if Device.model == "NookTouch" then
            -- (Nook Simple Touch: in case its touch is the wrong way round)
            local function flip(key, label)
                return {
                    text = label,
                    help_text = _("For a Nook whose touch lands on the wrong side. Takes effect after Restart GZreader."),
                    checked_func = function() return G_reader_settings:isTrue(key) end,
                    callback = function() G_reader_settings:flipNilOrFalse(key) end,
                }
            end
            table.insert(items, 1, icon("settings_background", {
                text = _("Touch orientation"),
                sub_item_table = {
                    flip("gzreader_nst_flip_x", _("Mirror left and right")),
                    flip("gzreader_nst_flip_y", _("Mirror top and bottom")),
                },
            }))
        end
        if Device.lcd then
            -- (Nook 1st Edition)
            table.insert(items, 1, icon("settings_background", {
                text = _("Colour screen"),
                help_text = _("What the Nook's colour touchscreen shows while reading, elsewhere and when typing, how long it stays lit, and its brightness."),
                sub_item_table_func = function() return require("gzreader_nook").menuItems() end,
            }))
        end
        return items
    end
    return {}
end

---------------------------------------------------------------- errors

local ERRORS = {
    not_paired = _("This Kindle isn't connected to Grimmory yet."),
    expired = _("Your Grimmory login has expired. Connect again with the QR code."),
    unreachable = _("Couldn't reach the Grimmory server. Check Wi-Fi and the server address."),
    bad_credentials = _("Wrong username or password."),
    rate_limited = _("Too many attempts. Wait a minute and try again."),
    usb = _("This Kindle syncs with Grimmory through a computer: Menu → Sync with computer."),
}

function Grimmory:describeError(err)
    if type(err) == "string" and ERRORS[err] then return ERRORS[err] end
    if type(err) == "string" and err:match("^stalled") then
        return T(_("The download stalled (%1). Check the Kindle's Wi-Fi signal and try again."), err:gsub("^stalled:%s*", ""))
    end
    if type(err) == "string" and err:match("^http_") then
        return T(_("Grimmory returned an error (%1)."), err:sub(6))
    end
    return T(_("Something went wrong: %1"), tostring(err))
end

function Grimmory:exportLog()
    local lib = self:libraryDir()
    local dest_dir = lib:match("^(.+)/[^/]+$") or lib -- next to the library, not in it
    -- On a Kindle, include a read-only audio / text-to-speech survey.
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Saving diagnostic log…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local dest, err = Log.exportTo(dest_dir, DataStorage:getDataDir() .. "/crash.log")
    UIManager:close(busy)
    if dest then
        Log.info("log exported to", dest)
        -- (only the newest few stay: each is ~700 KB)
        local pruned = Log.pruneExports(dest_dir, nil, dest)
        if pruned > 0 then Log.info("older saved logs deleted:", pruned) end
        UIManager:show(InfoMessage:new{
            text = T(_("Diagnostic log saved:\n%1\n\nConnect the Kindle over USB to copy it."), dest),
        })
    else
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log: %1"), tostring(err)) })
    end
end

--- "Diagnostics" (the quick panel): send the log to the developer or a phone, or save
--- it on the Kindle for USB.
function Grimmory:showDiagnostics()
    local ButtonDialog = require("ui/widget/buttondialog")
    local okc, icons = pcall(require, "common/inline_icon_map")
    local function label(icon, text) return (okc and icons[icon]) and (icons[icon] .. "  " .. text) or text end
    local dialog
    local buttons = {}
    -- (no Wi-Fi, Kindle 2 and DX: no phone to send it to; saved for the USB drive)
    if not Net.usb then
        buttons[#buttons + 1] = { { text = label("send", _("Send to a browser (QR code)")), align = "left", callback = function()
            UIManager:close(dialog)
            UIManager:nextTick(function() self:shareLog() end)
        end } }
    end
    -- (no Wi-Fi: saved for the sync page, which sends it at the next sync: gzreader_usbreport.lua)
    buttons[#buttons + 1] = { { text = label("send", Net.usb and _("Send to the developer (at the next sync)") or _("Send to the developer")),
        align = "left", callback = function()
        UIManager:close(dialog)
        UIManager:nextTick(function() self:sendLogToDeveloper() end)
    end } }
    buttons[#buttons + 1] = { { text = label("save", _("Save to the Kindle (copy over USB)")), align = "left", callback = function()
        UIManager:close(dialog)
        UIManager:nextTick(function() self:exportLog() end)
    end } }
    buttons[#buttons + 1] = { { text = label("remove", _("Cancel")), align = "left", callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{
        title = _("Diagnostics\nThe log helps find problems. Passwords and tokens are never in it."),
        buttons = buttons,
    }
    -- ZenOS's look: icon column, and Q, W, E keys on a Kindle Keyboard
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

--- Diagnostics → Send to the developer: asks what happened (what you were
--- doing, what failed), then sends it with the diagnostic log to the
--- developer's report feed (gzreader_remote.lua R.sendLogs). `comment`: what
--- was typed (nil: ask first).
function Grimmory:sendLogToDeveloper(comment)
    if comment == nil then return self:askReportComment() end
    if Net.usb then return self:saveReportForSync(comment) end -- (no Wi-Fi: the sync page sends it)
    if not Net.connected() and Net.enabled() then
        return Net.run(function() self:sendLogToDeveloper(comment) end, { reason = "sending the log" })
    end
    local tmp = DataStorage:getDataDir() .. "/cache"
    require("libs/libkoreader-lfs").mkdir(tmp)
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Sending the diagnostic log to the developer…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local dest, err = Log.exportTo(tmp, DataStorage:getDataDir() .. "/crash.log")
    local parts
    if dest then
        Net.hold("debug log")
        parts, err = require("gzreader_remote").sendLogs(dest, comment)
        Net.release("debug log")
        os.remove(dest)
    end
    UIManager:close(busy)
    if parts then
        UIManager:show(InfoMessage:new{ text = _("Diagnostic log sent to the developer. Thank you!"), timeout = 4 })
    else
        Log.warn("debug log not sent:", err)
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't send the log (%1). Check Wi-Fi and try again, or save it to the Kindle."),
            tostring(err)) })
    end
end

--- Kindle 2/DX (no Wi-Fi): the report waits on the Kindle for the sync page
--- (gzreader_usbreport.lua), which sends it at the next sync.
function Grimmory:saveReportForSync(comment)
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Saving the diagnostic log for the developer…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local stamp, err = require("gzreader_usbreport").save(self, comment)
    UIManager:close(busy)
    if stamp then
        UIManager:show(InfoMessage:new{ text = _("Saved for the developer, with what you typed. It's sent from the computer at your next sync (the sync page)."), timeout = 6 })
    else
        Log.warn("debug report not saved:", err)
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log (%1)."), tostring(err)) })
    end
    return stamp
end

--- What happened, typed before Send to the developer (it goes with the log).
function Grimmory:askReportComment()
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Send to the developer"),
        description = Net.usb
            and _("What were you doing, and what went wrong? It's sent with the diagnostic log from the computer at your next sync (passwords and tokens are never in it).")
            or _("What were you doing, and what went wrong? It's sent with the diagnostic log (passwords and tokens are never in it)."),
        input_hint = _("e.g. the book froze when I turned the page"),
        allow_newline = true,
        text_height = Device.screen:scaleBySize(110), -- (about four lines)
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Send"), is_enter_default = true, callback = function()
                local text = dialog:getInputText() or ""
                UIManager:close(dialog)
                UIManager:nextTick(function() self:sendLogToDeveloper(text) end)
            end },
        }},
    }
    self.report_dialog = dialog
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

--- Send the diagnostic log to a phone over Wi-Fi: the Kindle serves it on a
--- one-off address shown as a QR code (same mini web server as QR sign-in).
--- The phone saves the file, which can then be attached anywhere.
function Grimmory:shareLog()
    if self.pairing then return end
    if Net.usb then return self:exportLog() end -- (no Wi-Fi: saved for the USB drive)
    if not Net.connected() and Net.enabled() then
        return Net.run(function() self:shareLog() end, { reason = "sending the log" })
    end
    local lib = self:libraryDir()
    local dest_dir = lib:match("^(.+)/[^/]+$") or lib
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Preparing the diagnostic log…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    -- built in the cache and deleted there: the browser gets the copy in memory
    local tmp = DataStorage:getDataDir() .. "/cache"
    require("libs/libkoreader-lfs").mkdir(tmp)
    local content, filename = Log.exportText(tmp, DataStorage:getDataDir() .. "/crash.log")
    UIManager:close(busy)
    if not content then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log: %1"), tostring(filename)) })
    end
    -- (logs earlier versions left next to the GZreader folder: only the newest few stay)
    Log.pruneExports(dest_dir)
    local token = Mod.PairServer.randomToken(16)
    local base = "/log/" .. token
    -- typed into a browser: just the IP (port 80 where it can be used) and
    -- the PIN on the screen, like setup's page (gzreader_phone.lua)
    local pin, pin_tries = require("gzreader_spake").pin(), 0
    local PairPage = require("gzreader_pairpage")
    local Phone = require("gzreader_phone")
    local server, server80, screen, timeout_task, done
    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if server80 then UIManager:removeZMQ(server80); server80:stop() end
        if screen then UIManager:close(screen) end
        self.pairing = nil
    end
    local function pinPage(method, body)
        local st = { log = true, tries_left = Phone.PIN_TRIES - pin_tries, off = pin_tries >= Phone.PIN_TRIES }
        if method == "GET" or st.off then return 200, "text/html", PairPage.pin(st) end
        if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
        local typed = tostring(Mod.PairServer.parseForm(body).pin or ""):gsub("%D", "")
        if Phone.samePin(typed, pin) then
            Log.info("log page: PIN accepted")
            return 303, "text/plain", base
        end
        pin_tries = pin_tries + 1
        Log.info("log page: wrong PIN", pin_tries, "of", Phone.PIN_TRIES)
        st.tries_left, st.off, st.wrong = Phone.PIN_TRIES - pin_tries, pin_tries >= Phone.PIN_TRIES, true
        if st.off and screen and screen.setPin then screen:setPin(nil, _("PIN off: 5 wrong tries")) end
        return 200, "text/html", PairPage.pin(st)
    end
    local page = string.format([[<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GZreader diagnostic log</title><style>body{font-family:system-ui,sans-serif;max-width:32em;margin:2em auto;padding:0 1em;line-height:1.5}
a.b{display:inline-block;padding:.8em 1.4em;background:#000;color:#fff;border-radius:.5em;text-decoration:none;font-weight:600}</style></head>
<body><h1>GZreader diagnostic log</h1><p>%s (%d KB). Passwords and tokens are never in it.</p>
<p><a class="b" href="%s/%s" download="%s">Download the log</a></p>
<p>Then attach the downloaded file wherever you need it, for example in your chat with Claude.</p></body></html>]],
        filename, math.ceil(#content / 1024), base, filename, filename)
    server = Mod.PairServer:new{
        handler = function(method, path, _headers, body)
            if path == "/" or path == "/pin" then return pinPage(method, body) end
            if method ~= "GET" then return 405, "text/plain", "Method not allowed" end
            if path == base then return 200, "text/html", page end
            if path == base .. "/" .. filename then
                Log.info("log sent to phone", filename, #content, "bytes")
                return 200, "text/plain", content,
                    { ["Content-Disposition"] = 'attachment; filename="' .. filename .. '"' }
            end
            return 404, "text/plain", "Not found"
        end,
    }
    local ok, serr = server:start()
    if not ok then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start sharing: %1"), tostring(serr)) })
    end
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = Mod.PairServer.localIp(hint_host, iface)
    if not ip then
        server:stop()
        return UIManager:show(InfoMessage:new{
            text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why) })
    end
    self.pairing = true
    UIManager:insertZMQ(server)
    local url = T("http://%1:%2%3", ip, server.port, base)
    Log.info("sharing log on", T("http://%1:%2", ip, server.port))
    local origin = T("http://%1:%2", ip, server.port)
    local address = T("%1:%2", ip, server.port)
    if Phone.PORT80 then
        server80 = Mod.PairServer:new{ port = Phone.PORT80, exact_port = true, keep_wifi = false, handler = function()
            return 302, "text/plain", origin .. "/"
        end }
        if server80:start() then
            UIManager:insertZMQ(server80)
            address = Phone.PORT80 == 80 and ip or T("%1:%2", ip, Phone.PORT80)
        else
            server80 = nil
        end
    end
    screen = Mod.PairScreen:new{
        url = url,
        address = address,
        pin = pin,
        title = _("Send the diagnostic log"),
        instructions = _("Scan this code with your phone and tap \"Download the log\". (It isn't kept on the Kindle: use Save to the Kindle for a copy here.)"),
        footer = _("Press Back when you're done."),
        button_text = _("Done"),
        on_cancel = function() screen = nil; finish() end,
    }
    UIManager:show(screen)
    timeout_task = function() finish() end
    UIManager:scheduleIn(PAIR_TIMEOUT_S, timeout_task)
end

function Grimmory:showError(err)
    Log.warn("shown to user:", tostring(err), "|", self:describeError(err))
    UIManager:show(InfoMessage:new{ text = self:describeError(err), icon = "notice-warning" })
end

---------------------------------------------------------------- pairing

--- Log in. Returns ok, err.
function Grimmory:connect(server_input, username, password)
    local server = Api.normalizeServer(server_input)
    if not server then return false, _("That server address doesn't look right.") end
    username = (username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if username == "" or not password or password == "" then
        return false, _("Enter your username and password.")
    end
    local previous = { self.store.server, self.store.username }
    self.api.explicit_https = server_input:match("^%s*https://") ~= nil
    local ok, err = self.api:login(server, username, password)
    Log.info("password login to", ok and self.store.server or server, ok and "ok" or ("failed: " .. tostring(err)))
    if not ok then return false, self:describeError(err) end
    self:afterLogin(previous)
    return true
end

--- Bookkeeping after any successful login. `previous` = { server, username }
--- from before the login.
function Grimmory:afterLogin(previous)
    if type(previous) ~= "table" or previous[1] ~= self.store.server or previous[2] ~= self.store.username then
        -- Different server/account: queued data belongs to the old one.
        self.store.pending = { progress = {}, sessions = {}, ratings = {} }
        self:save()
    end
    self:flushPending()
end

function Grimmory:onGrimmoryPair(touchmenu)
    closeTouchMenu(touchmenu)
    if Net.usb then require("gzreader_usbsync").show(self); return true end
    Net.run(function() self:startQrPairing() end, { reason = "connecting to Grimmory" })
    return true
end

function Grimmory:onGrimmoryKeyboardLogin()
    self:keyboardLogin()
    return true
end

--- Copy connections from / send them to another GZreader (setup guide, Settings).
function Grimmory:onGzCopyReceive()
    require("gzreader_copy").receive(self)
    return true
end

function Grimmory:onGzCopySend()
    require("gzreader_copy").send(self)
    return true
end

--- Settings → Connections → Plex (Music), on the Kindles with audio.
function Grimmory:plexSettingsItems()
    return require("gzreader_musictab").settingsItems(self)
end

--- Settings → Connections → Copy to or from another GZreader.
function Grimmory:copyItems()
    return {
        {
            text = _("Copy from another GZreader"),
            help_text = _("Connections (Grimmory, Notes, calendars) from another GZreader on this Wi-Fi. On that one choose Send connections: it shows a PIN to enter here."),
            callback = function(touchmenu) closeTouchMenu(touchmenu); self:onGzCopyReceive() end,
        },
        {
            text = _("Send connections to another GZreader"),
            help_text = _("Shows a PIN for the other GZreader, which finds this one on the Wi-Fi and copies what you pick there."),
            callback = function(touchmenu) closeTouchMenu(touchmenu); self:onGzCopySend() end,
        },
    }
end

--- Connect with QR code: the phone page (gzreader_phone.lua), at Grimmory.
function Grimmory:startQrPairing()
    if self.pairing then return end
    require("gzreader_phone").open(self, { section = "grimmory" })
end

--- The phone page at "books" (Home menu → Send books from your phone).
--- Touch Kindles have no Menu key for GZreader's menu (Kindle Keyboard): it,
--- the phone page and Send books go in ZenOS's launcher (swipe down from the
--- top, the launcher icon), once; they can be moved or removed there.
--- Touch Kindles: GZreader's entries in ZenOS's launcher (swipe down, the
--- launcher tab). "GZreader" opens the GZreader menu at Home and the Reading
--- menu in a book; the others show only where they make sense: at Home /
--- in the library, or in a book (ZenOS's app_launcher: gz_context).
local LAUNCHER = {
    { _("GZreader"), "app_menu", "onGzLauncherMenu" },
    { _("Continue"), "tab_continue", "onGzLauncherContinue", "library" },
    { _("Grimmory"), "library", "onGzLauncherGrimmory", "library" },
    { _("Search"), "quick_search", "onGzLauncherSearch", "library" },
    { _("History"), "tab_history", "onGzLauncherHistory", "library" },
    { _("Phone"), "quick_connections", "onGzLauncherPhone", "library" },
    { _("Send books"), "quick_localsend", "onGzLauncherBooks", "library" },
    { _("Updates"), "zen_ui_update", "onGzLauncherUpdates", "library" },
    { _("Contents"), "toc", "onGzLauncherToc", "reader" },
    { _("Bookmark"), "bookmark", "onGzLauncherBookmark", "reader" },
    { _("Bookmarks"), "book_open", "onGzLauncherBookmarks", "reader" },
    { _("Go to page"), "skip_right", "onGzLauncherGoto", "reader" },
    { _("Search book"), "lookup_search", "onGzLauncherSearchBook", "reader" },
    { _("Sync"), "quick_sync", "onGzLauncherSync", "reader" },
    { _("Fit pictures"), "coverflow", "onGzLauncherPictures", "reader" },
    -- (Kindles with audio: the Kindle Touch)
    { _("Music"), "tab_music", "onGzLauncherMusic", nil, "audio" },
    { _("Play / pause"), "quick_read_aloud", "onGzLauncherMusicToggle", nil, "audio" },
}
Grimmory.LAUNCHER = LAUNCHER

function Grimmory:addLauncherEntries()
    -- (v3, 1.14.0: Music and Play / pause, on the Kindles with audio)
    if not Mod.Touch.on() or G_reader_settings:isTrue("gzreader_launcher_v3") then return end
    local ok, Model = pcall(require, "modules/menu/app_launcher/model")
    if not ok then return end
    local cfg = Model.ensure()
    local function find(entries, method)
        for _i, e in ipairs(entries or {}) do
            if e.type == "plugin" and type(e.plugin) == "table" and e.plugin.key == "gzreader" and e.plugin.method == method then return e end
            if e.type == "folder" then
                local f = find(e.children, method)
                if f then return f end
            end
        end
    end
    for _i, def in ipairs(LAUNCHER) do
        local e = find(cfg.entries, def[3])
        local skip = def[5] == "audio" and not Mod.Touch.audio() -- (no speaker: not added)
        if e then
            e.gz_context = def[4] -- (1.12.2: Phone and Send books are Home's)
        elseif not skip then
            cfg.entries[#cfg.entries + 1] = { id = Model.next_id(cfg), type = "plugin", label = def[1], icon = def[2],
                plugin = { key = "gzreader", method = def[3] }, gz_context = def[4] }
        end
    end
    Model.save(cfg)
    G_reader_settings:makeTrue("gzreader_launcher_v2")
    G_reader_settings:makeTrue("gzreader_launcher_v3")
    Log.info("launcher: GZreader entries added or updated")
end

--- The GZreader instance of the screen that's open (the launcher may call
--- these on the plugin's class): the book's while one is open.
local function liveInstance(self)
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local r = ok and ReaderUI.instance
    if r and r.document and r.gzreader then return r.gzreader end
    if self.ui then return self end
    local FileManager = require("apps/filemanager/filemanager")
    return FileManager.instance and FileManager.instance.gzreader or nil
end

--- The open book's ReaderUI, if any.
local function reader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local r = ok and ReaderUI.instance
    if r and r.document then return r end
end

local function dispatch(action)
    if Dispatcher.execute then Dispatcher:execute({ [action] = true }) end
end

--- In a book: an event to the reader.
local function readerEvent(name)
    local r = reader()
    if r then r:handleEvent(Event:new(name)) end
end

function Grimmory:onGzLauncherMenu()
    local p = liveInstance(self)
    if not p then return end
    require("gzreader_panel").show(p)
end

function Grimmory:onGzLauncherPhone()
    local p = liveInstance(self)
    if p then p:openPhonePage(nil) end
end

function Grimmory:onGzLauncherBooks()
    local p = liveInstance(self)
    if p then p:openPhonePage("books") end
end

function Grimmory:onGzLauncherMusic()
    local p = liveInstance(self)
    if p then require("gzreader_musictab").open(p) end
end
function Grimmory:onGzLauncherMusicToggle()
    local p = liveInstance(self)
    local Music = require("gzreader_music")
    if Music.current then Music.current:toggle()
    elseif p then require("gzreader_musictab").open(p) end
end

--- The Music tab (ZenOS's tab bar: Settings → Navbar → Tabs → Music).
function Grimmory:onShowGzMusic()
    if self.ui and self.ui.document then return end -- (file manager's instance)
    require("gzreader_musictab").show(self)
    return true
end

function Grimmory:onGzLauncherContinue() dispatch("open_previous_document") end
function Grimmory:onGzLauncherSearch() dispatch("file_search") end
function Grimmory:onGzLauncherHistory() dispatch("history") end
function Grimmory:onGzLauncherUpdates() require("gzreader_update").run() end
function Grimmory:onGzLauncherGrimmory()
    local p = liveInstance(self)
    if p then p:onShowGrimmoryLibrary() end
end

function Grimmory:onGzLauncherToc()
    local r = reader()
    if r and not r:handleEvent(Event:new("ShowZenUIToc")) then r:handleEvent(Event:new("ShowToc")) end
end
function Grimmory:onGzLauncherBookmark() readerEvent("ToggleBookmark") end
function Grimmory:onGzLauncherBookmarks() readerEvent("ShowBookmark") end
function Grimmory:onGzLauncherGoto() readerEvent("ShowGotoDialog") end
function Grimmory:onGzLauncherSearchBook() readerEvent("ShowFulltextSearchInput") end
function Grimmory:onGzLauncherSync()
    local p = liveInstance(self)
    if p then p:onGrimmorySyncNow() end
end
function Grimmory:onGzLauncherPictures()
    local r = reader()
    if not r then return end
    local PB = require("gzreader_picturebook")
    PB.set(r, not PB.isOn(r))
end

function Grimmory:openPhonePage(section)
    if self.pairing then return end
    if Net.usb then return require("gzreader_usbsync").show(self) end
    Net.run(function() require("gzreader_phone").open(self, { section = section }) end, { reason = "the setup page" })
end

--- Settings → Connections → Grimmory → Single sign-on (SSO): where the
--- identity provider sends the phone back (see gzreader_phone.ssoRedirect).
function Grimmory:ssoMenu()
    local Phone = require("gzreader_phone")
    local function current()
        local _, relay = Phone.ssoRedirect(self, "http://kindle")
        local v = G_reader_settings:readSetting("gzreader_sso_redirect")
        if not relay then return "kindle" end
        if type(v) == "string" and v ~= "relay" and v ~= "kindle" and v:match("^https://") then return "own" end
        return "relay"
    end
    local function set(v)
        G_reader_settings:saveSetting("gzreader_sso_redirect", v)
        if v ~= "kindle" then self.store.sso_direct_ok = nil end
    end
    return {
        {
            text = _("How to set it up"),
            keep_menu_open = true,
            callback = function() self:showSsoSetup() end,
            separator = true,
        },
        {
            text = _("Redirect: GZreader's sign-in page"),
            help_text = _("One redirect address for every Kindle, on any network. Recommended."),
            radio = true,
            checked_func = function() return current() == "relay" end,
            callback = function() set("relay") end,
        },
        {
            text = _("Redirect: your own copy of the page"),
            help_text = _("The same page (oauth2-callback.html from GZreader's docs folder), hosted on your own HTTPS address, e.g. next to Grimmory behind Cloudflare."),
            radio = true,
            checked_func = function() return current() == "own" end,
            callback = function(touchmenu) self:askSsoRedirect(touchmenu) end,
        },
        {
            text = _("Redirect: this Kindle's own address"),
            help_text = _("The Kindle's address on your Wi-Fi (http://<its IP>:8642/oauth2-callback): each Kindle needs its own entry at the identity provider, and its IP must not change."),
            radio = true,
            checked_func = function() return current() == "kindle" end,
            callback = function() set("kindle") end,
        },
    }
end

function Grimmory:askSsoRedirect(touchmenu)
    local InputDialog = require("ui/widget/inputdialog")
    local v = G_reader_settings:readSetting("gzreader_sso_redirect")
    local dialog
    dialog = InputDialog:new{
        title = _("Your sign-in page"),
        input = (type(v) == "string" and v:match("^https://")) and v or "https://",
        input_hint = "https://books.example.com/gzreader/oauth2-callback",
        description = _("The HTTPS address of your copy of GZreader's oauth2-callback page. It must end in /oauth2-callback."),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                local u = (dialog:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if not u:match("^https://[^/]+/.*oauth2%-callback$") then
                    UIManager:show(InfoMessage:new{ text = _("The address must start with https:// and end in /oauth2-callback.") })
                    return
                end
                UIManager:close(dialog)
                G_reader_settings:saveSetting("gzreader_sso_redirect", u)
                self.store.sso_direct_ok = nil
                if touchmenu then touchmenu:updateItems() end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Grimmory:showSsoSetup()
    local Phone = require("gzreader_phone")
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local ip = Mod.PairServer.localIp(hint_host, iface)
    local origin = ip and T("http://%1:%2", ip, Mod.PairServer.port)
    local uri, relay = Phone.ssoRedirect(self, origin or ("http://<" .. _("this Kindle's IP") .. ">:8642"))
    local text
    if relay then
        text = _("To sign in with SSO from the QR code page, add this redirect URI to Grimmory's client in your identity provider (Authentik, Pocket ID, Authelia, Keycloak…), next to the existing …/oauth2-callback one:")
            .. "\n\n" .. uri .. "\n\n"
            .. _("It's the same for every Kindle, wherever it is. If your Grimmory admin restricted ALLOWED_ORIGINS, add the start of it there too:")
            .. "\n" .. Phone.originOf(uri) .. "\n\n"
            .. _("The Kindle must reach Grimmory and the identity provider (e.g. through Cloudflare), and the phone must be on the Kindle's Wi-Fi (or the Kindle on the phone's hotspot) while signing in.")
    else
        text = _("To sign in with SSO from the QR code page, add this redirect URI to Grimmory's client in your identity provider (Authentik, Pocket ID, Authelia, Keycloak…), next to the existing …/oauth2-callback one:")
            .. "\n\n" .. (origin and uri or _("(connect to Wi-Fi to see it)")) .. "\n\n"
            .. _("Reserve this Kindle's IP address in your router so the address doesn't change. If your Grimmory admin restricted ALLOWED_ORIGINS, add the same address without /oauth2-callback there too.")
    end
    UIManager:show(InfoMessage:new{ text = text })
end

function Grimmory:announceConnected()
    UIManager:show(InfoMessage:new{
        text = T(_("Connected to Grimmory as %1."), self.store.username or "") .. "\n\n"
            .. _("Reading progress syncs automatically for books you download from Grimmory."),
    })
end

--- prefill = { server, username } (copied from another GZreader), or the saved ones.
function Grimmory:keyboardLogin(prefill)
    prefill = type(prefill) == "table" and prefill or {}
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Connect to Grimmory"),
        fields = {
            { text = prefill.server or self.store.server or "", hint = _("Server, e.g. https://books.example.com") },
            { text = prefill.username or self.store.username or "", hint = _("Username") },
            { text = "", hint = _("Password"), text_type = "password" },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = dialog:getFields()
                UIManager:close(dialog)
                Net.run(function()
                    local msg = InfoMessage:new{ text = _("Connecting…"), timeout = 0 }
                    UIManager:show(msg)
                    UIManager:forceRePaint()
                    local ok, err = self:connect(f[1], f[2], f[3])
                    UIManager:close(msg)
                    if ok then
                        self:announceConnected()
                    else
                        UIManager:show(InfoMessage:new{ text = err, icon = "notice-warning" })
                    end
                end)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Grimmory:confirmDisconnect()
    UIManager:show(ConfirmBox:new{
        text = _("Disconnect this Kindle from Grimmory? Downloaded books stay on the Kindle. Progress sync will stop until you connect again."),
        ok_text = _("Disconnect"),
        ok_callback = function()
            if self.sync then self.sync:onLeave() end
            NetworkMgr:runWhenConnected(function() self.api:logout() end)
            self.api:clearTokens()
            UIManager:show(InfoMessage:new{ text = _("Disconnected from Grimmory."), timeout = 3 })
        end,
    })
end

---------------------------------------------------------------- offline queue

--- Remember a progress update (latest per book) or a reading session to send later.
Grimmory.gone_books = {} -- book ids Grimmory answered "not found" for (this run)

function Grimmory:queue(kind, book_id, body)
    local pending = self.store.pending
    if kind == "progress" and Grimmory.gone_books[tostring(book_id)] then return end
    if kind == "progress" then
        pending.progress[tostring(book_id)] = body
        if Net.usb then pcall(require("gzreader_usbsync").cfiSoon, self, book_id, body) end
    else
        table.insert(pending.sessions, body)
        while #pending.sessions > MAX_QUEUED_SESSIONS do table.remove(pending.sessions, 1) end
    end
    self:saveSoon()
end

function Grimmory:clearQueued(kind, book_id)
    if kind == "progress" then self.store.pending.progress[tostring(book_id)] = nil end
end

--- Send progress and reading sessions queued while offline. In the
--- background (gzreader_async): sending a backlog can take many seconds.
function Grimmory:flushPending()
    if self.flushing or not self.api:isPaired() or not NetworkMgr:isConnected() then return end
    local pending = self.store.pending
    pending.ratings = pending.ratings or {}
    if next(pending.progress) == nil and #pending.sessions == 0 and next(pending.ratings) == nil then return end
    self.flushing = true
    local progress, sessions, ratings = {}, {}, {}
    for book_id, body in pairs(pending.progress) do progress[book_id] = body end
    for book_id, stars in pairs(pending.ratings) do ratings[book_id] = stars end
    for i, body in ipairs(pending.sessions) do
        sessions[i] = body
        -- remembered before sending: if this attempt's reply is lost, the
        -- next one first looks in Grimmory's history instead of re-posting
        body.gz_tries = (body.gz_tries or 0) + 1
    end
    if #sessions > 0 then self:save() end
    require("gzreader_async").run(self.api, function(api)
        local sent, dropped, n_sessions, cfis = {}, {}, 0, {}
        for book_id, body in pairs(progress) do
            -- the exact place (CFI) for the web reader, made here, off the screen's thread
            local fp = body.fileProgress
            if body.gz_xp and body.gz_file and type(fp) == "table" and not fp.positionData then
                local cfi = require("gzreader_sync").cfiInFile(body.gz_file, body.gz_xp)
                if cfi then fp.positionData = cfi; cfis[book_id] = cfi end
            end
            local ok, _, code = api:putProgress(book_id, body)
            if ok then sent[#sent + 1] = book_id
            elseif code == 404 or code == 400 or code == 403 then dropped[#dropped + 1] = book_id -- the book is gone
            else break end -- still offline; try again later
        end
        for _i, body in ipairs(sessions) do
            local ok, code
            if (body.gz_tries or 0) > 1 and api:hasSession(body) then
                ok = true -- already saved by an earlier attempt whose reply was lost
                require("gzreader_log").info("reading session already in Grimmory, not sent again", body.bookId, body.startTime)
            else
                local res = { api:postSession(body) }
                ok, code = res[1], res[3]
            end
            if ok or code == 400 or code == 404 then n_sessions = n_sessions + 1 else break end
        end
        local rated = {}
        local Ratings = require("gzreader_ratings")
        for book_id, stars in pairs(ratings) do
            local ok, _, code = api:putRating(book_id, Ratings.toGrimmory(stars))
            if ok or code == 400 or code == 403 or code == 404 then rated[book_id] = ok and "ok" or "dropped" else break end
        end
        return { sent = sent, dropped = dropped, sessions = n_sessions, cfis = cfis, rated = rated }
    end, function(res)
        self.flushing = nil
        if type(res) ~= "table" then return end
        for _i, book_id in ipairs(res.sent or {}) do
            local body = progress[book_id]
            -- only clear it if nothing newer was queued meanwhile
            if pending.progress[book_id] == body then pending.progress[book_id] = nil end
            local entry = self.store.downloads[book_id]
            local fp = body and body.fileProgress
            if entry and fp then
                entry.last_pushed_pct = fp.progressPercent
                entry.last_pushed_cfi = (res.cfis or {})[book_id] or fp.positionData
            end
            Log.info("sync push book", book_id, fp and (tostring(fp.progressPercent) .. "%") or "",
                fp and fp.positionHref or "", "ok")
        end
        for _i, book_id in ipairs(res.dropped or {}) do
            if pending.progress[book_id] == progress[book_id] then pending.progress[book_id] = nil end
            -- not in Grimmory (any more): not sent again this run (an audiobook
            -- playing kept sending it, every minute)
            if not Grimmory.gone_books[book_id] then
                Log.info("sync: book", book_id, "isn't in Grimmory; its position stays on the Kindle")
            end
            Grimmory.gone_books[book_id] = true
        end
        for _i = 1, tonumber(res.sessions) or 0 do
            if pending.sessions[1] == sessions[_i] then table.remove(pending.sessions, 1) end
        end
        if (tonumber(res.sessions) or 0) > 0 then require("gzreader_grimstats").stale(self) end
        for book_id, how in pairs(res.rated or {}) do
            -- only cleared if not changed again meanwhile
            if pending.ratings[book_id] == ratings[book_id] then pending.ratings[book_id] = nil end
            local entry = self.store.downloads[book_id]
            if entry and how == "ok" then entry.rating_synced = ratings[book_id] end
            Log.info("rating sent to Grimmory", book_id, ratings[book_id], "stars", how)
        end
        self:saveSoon()
        -- queued while this was being sent: send that too
        local more = false
        for book_id, body in pairs(pending.progress) do if progress[book_id] ~= body then more = true end end
        if #pending.sessions > (#sessions - (tonumber(res.sessions) or 0)) then more = true end
        for book_id, stars in pairs(pending.ratings) do if ratings[book_id] ~= stars then more = true end end
        if more and #(res.sent or {}) > 0 then UIManager:nextTick(function() self:flushPending() end) end
    end, "flush")
end

function Grimmory:onNetworkConnected()
    -- the request helper (opt-in: a file named gz-request-helper; gzreader_reqhelper.lua)
    pcall(function() require("gzreader_reqhelper").start(self.path) end)
    UIManager:scheduleIn(2, function()
        -- books rated in the file browser (not opened) since GZreader started
        if self.api:isPaired() and self:syncEnabled() and not self._ratings_swept then
            local ok, _, done = pcall(require("gzreader_ratings").sweep, self, 60)
            if ok and done then self._ratings_swept = true end
        end
        self:flushPending()
    end)
    -- auto-download shelf (at most every 30 min)
    UIManager:scheduleIn(6, function() pcall(require("gzreader_shelfsync").run, self) end)
    -- your shelves: changes made here sent, the shelves kept again (at most every 30 min)
    UIManager:scheduleIn(8, function() pcall(require("gzreader_shelves").sync, self) end)
end

---------------------------------------------------------------- reader integration

--- Grimmory book id + download entry for an open file, if it came from Grimmory.
function Grimmory:entryForPath(path)
    if not path then return end
    for id, entry in pairs(self.store.downloads) do
        if type(entry) == "table" and entry.path == path then return id, entry end
    end
end

--- The book menu's Add to shelf / Remove from shelf (ZenOS's
--- context_menu_file_dialog.lua, in place of Add to collection; gzreader_shelves.lua).
function Grimmory:shelfButtons(path, on_change)
    local ok, buttons = pcall(function() return require("gzreader_shelves").buttons(self, path, on_change) end)
    if not ok then Log.warn("shelves: book menu:", tostring(buttons)) end
    return ok and buttons or nil
end

--- Add to shelf for several selected books (ZenOS's context_menu.lua).
function Grimmory:shelfAddMany(paths, on_change)
    require("gzreader_shelves").showAdd(self, paths, on_change)
end

function Grimmory:setupReader()
    -- Read aloud (any reflowable book) and the keyboard Reading menu.
    if Mod.Touch.tts() then self.tts = Mod.TTS.Reader:new(self.ui) end
    local menu = self.ui.menu
    -- every Kindle: the quick panel (gzreader_panel.lua; More there is the
    -- old Reading menu list)
    if menu then
        local plugin = self
        local orig_show = menu.onShowMenu
        menu.onKeyPressShowMenu = function()
            require("gzreader_panel").show(plugin)
            return true
        end
        menu.onShowMenu = function(m, ...)
            if m._gz_full then return orig_show and orig_show(m, ...) end
            require("gzreader_panel").show(plugin)
            return true
        end
    end
end

function Grimmory:onKeyPress(key)
    if not (self.ui.document and self.tts and type(key) == "table") then return end
    if key.key == "ShiftSym" then
        self.tts:toggle()
        return true
    end
    -- (the volume rocker: gzreader_audioctl, everywhere)
end

function Grimmory:onAnnotationsModified(items)
    if self.bookmarks then self.bookmarks:onAnnotationsModified(items) end
    if self.annotations then self.annotations:onAnnotationsModified(items) end
end

function Grimmory:showTtsSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    -- Changes update the label in place: reopening the dialog would put the
    -- 5-way focus back on the first button (Quieter / Slower) every time.
    local function relabel(id, text)
        local btn = dialog and dialog.buttontable and dialog.buttontable:getButtonById(id)
        if not btn then return end
        btn:setText(text, btn.width)
        UIManager:setDirty(dialog, "ui", btn.dimen)
    end
    local function speedText() return T(_("Speed %1"), Mod.TTS.speed()) end
    local function volumeText() return T(_("Volume %1 / %2"), Mod.TTS.volume(), Mod.TTS.VOLUME_MAX) end
    local function setSpeed(v)
        Mod.TTS.setSpeed(math.max(50, math.min(200, v)))
        relabel("speed", speedText())
    end
    local function setVolume(v)
        Mod.TTS.setVolume(v)
        relabel("volume", volumeText())
        Mod.TTS.say("Volume " .. Mod.TTS.volume() .. ".")
    end
    dialog = ButtonDialog:new{
        title = _("Read aloud\nShift + Sym starts and stops reading. The sentence being read is highlighted and pages turn by themselves."),
        buttons = {
            {
                { text = _("Quieter"), callback = function() setVolume(Mod.TTS.volume() - 1) end },
                { id = "volume", text = volumeText(), enabled = false },
                { text = _("Louder"), callback = function() setVolume(Mod.TTS.volume() + 1) end },
            },
            {
                { text = _("Slower"), callback = function() setSpeed(Mod.TTS.speed() - 10) end },
                { id = "speed", text = speedText(), enabled = false },
                { text = _("Faster"), callback = function() setSpeed(Mod.TTS.speed() + 10) end },
            },
            { { text = _("Find the Kindle voice (test)"), callback = function()
                UIManager:close(dialog); Mod.TTS.findVoice()
            end } },
            { { text = _("Close"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

local function nookChange()
    if Device.lcd then pcall(function() require("gzreader_nook").onReaderChange() end) end
end

function Grimmory:onReaderReady()
    -- the first page is drawn next: then the paused background work carries on
    UIManager:scheduleIn(1, function() require("gzreader_async").resume("the book is open") end)
    if not self.ui.document then return end
    nookChange()
    pcall(self.setupReader, self)
    pcall(function() require("gzreader_picturebook").onOpen(self.ui) end)
    pcall(function() require("gzreader_usage").readStart(self.ui) end)
    local book_id, entry = self:entryForPath(self.ui.document.file)
    if not book_id then return end
    if not entry.file_id and self.api:isPaired() and NetworkMgr:isConnected() then
        -- the file id wasn't in the list the book was downloaded from: look it up once
        require("gzreader_async").call(self.api, "getBook", { book_id }, function(book)
            local pf = type(book) == "table" and type(book.primaryFile) == "table" and tonumber(book.primaryFile.id)
            if pf then entry.file_id = pf; self:save(); self:writeManifest() end
        end)
    end
    Log.info("opened Grimmory book", book_id, "file_id", tostring(entry.file_id), "format", tostring(entry.format))
    self.sync = Sync:new(self, self.ui, entry, book_id)
    self.sync:onReady() -- (then openSync, below: a moment after the first page)
    self.bookmarks = Bookmarks:new(self.sync)
    self.annotations = Mod.Annotations:new(self.sync)
    if self:syncEnabled() and self.api:isPaired() and not Net.connected() then
        -- Wi-Fi only when needed: bring it up quietly to sync this book
        Net.run(function() self:syncOpenBook() end, { quiet = true, reason = "sync on open" })
    end
end

--- A book's sync when it opens (Sync:onReady, a moment after the first
--- page): its place, then queued updates, bookmarks and highlights, all in
--- one background process (Async.together) instead of four at 1, 2, 4 and
--- 6 s, each a fork of GZreader and a secure connection (seconds of a
--- Kindle 3's CPU each, while you turn the first pages).
function Grimmory:openSync(sync, saved)
    if self.sync ~= sync or not self.ui.document then return end
    require("gzreader_async").together(function()
        if self:syncEnabled() then sync:pull(false, saved) end
        self:flushPending()
        if self.bookmarks then pcall(self.bookmarks.reconcile, self.bookmarks) end
        if self.annotations then pcall(self.annotations.run, self.annotations) end
    end)
end

--- Pull position, send queued updates and bookmarks for the open book.
function Grimmory:syncOpenBook()
    if not (self.sync and self.ui.document) then return end
    require("gzreader_async").together(function()
        self:flushPending()
        self.sync:pull(false)
        if self.bookmarks then pcall(self.bookmarks.reconcile, self.bookmarks) end
        if self.annotations then pcall(self.annotations.run, self.annotations) end
    end)
end

function Grimmory:hasPending()
    local p = self.store.pending
    return p and (next(p.progress or {}) ~= nil or #(p.sessions or {}) > 0)
end

function Grimmory:onPageUpdate()
    nookChange()
    if self.sync then self.sync:onPageTurned() end
    pcall(function() require("gzreader_usage").pageTurned() end)
    if self.tts then self.tts:onManualPageTurn() end
end

function Grimmory:onPosUpdate()
    nookChange()
    if self.sync and self.ui.view and self.ui.view.view_mode ~= "page" then
        -- scroll mode fires this continuously; count roughly a screen per call
        self.sync:onPageTurned()
    end
end

function Grimmory:onGrimmorySyncNow()
    if Net.usb then require("gzreader_usbsync").show(self); return true end
    if not self.sync then
        UIManager:show(InfoMessage:new{ text = _("This book wasn't downloaded from Grimmory, so it can't be synced."), timeout = 3 })
        return true
    end
    Net.run(function()
        if not self.sync then return end
        require("gzreader_async").together(function()
            self.sync:push(true)
            self.sync:pull(true)
            if self.bookmarks then pcall(self.bookmarks.reconcile, self.bookmarks) end
            if self.annotations then pcall(self.annotations.run, self.annotations) end
        end)
    end, { reason = "sync now" })
    return true
end

function Grimmory:onNetworkDisconnected()
    pcall(function()
        local Helper = package.loaded["gzreader_reqhelper"]
        if Helper and Helper.endpoint() then Helper.stop() end
    end)
end

function Grimmory:onSuspend()
    if Grimmory.save_soon or Grimmory.recent_written then pcall(self.saveFull, self) end
    local Music = package.loaded["gzreader_music"]
    if Music then pcall(Music.pauseAll) end
    local ok_ab, Audiobook = pcall(require, "gzreader_audiobook")
    if ok_ab and Audiobook.current then
        -- (also one about to start, still asking Grimmory where it was)
        Audiobook.current.pull_gen = (Audiobook.current.pull_gen or 0) + 1
        if Audiobook.current.playing then Audiobook.current:pause() end
    end
    if self.tts then self.tts:stop() end
    if self.sync then self.sync:onLeave() end
    self.suspended_at = os.time()
    pcall(function() require("gzreader_remote").onSuspend() end)
    Net.onSuspend()
    pcall(function() require("gzreader_usage").onSuspend() end)
end

Grimmory.WAKE_SYNC_AFTER = 15 * 60 -- Wi-Fi only when needed: sync on wake after a long sleep

function Grimmory:onResume()
    pcall(function() require("gzreader_remote").onResume() end)
    pcall(function() require("gzreader_usage").onResume() end)
    Net.onResume()
    UIManager:scheduleIn(5, function() self:flushPending() end)
    if self.sync then
        self.sync:startSession()
        if self:syncEnabled() then
            UIManager:scheduleIn(3, function() if self.sync then self.sync:pull(false) end end)
            local slept = self.suspended_at and os.time() - self.suspended_at or 0
            if slept >= Grimmory.WAKE_SYNC_AFTER and self.api:isPaired() and not Net.connected() then
                -- maybe read elsewhere meanwhile
                UIManager:scheduleIn(4, function()
                    Net.run(function() self:syncOpenBook() end, { quiet = true, reason = "sync on wake" })
                end)
            end
        end
    end
end

function Grimmory:onEndOfBook()
    if self.sync and self:syncEnabled() then self.sync:push(true) end
end

function Grimmory:onCloseDocument()
    nookChange()
    if self.tts then self.tts:stop(); self.tts = nil end
    pcall(function() require("gzreader_usage").readEnd("closed book") end)
    self.bookmarks = nil
    if self.annotations then
        pcall(self.annotations.onClose, self.annotations)
        self.annotations = nil
    end
    if self.sync then
        self.sync:onLeave()
        pcall(self.sync.releaseCfi, self.sync)
        self.sync = nil
    end
    if self.api:isPaired() and self:hasPending() and not Net.connected() then
        -- Wi-Fi only when needed: send where you stopped reading
        UIManager:scheduleIn(1, function()
            Net.run(function() self:flushPending() end, { quiet = true, reason = "sync on close" })
        end)
    end
end

---------------------------------------------------------------- library

function Grimmory:onShowGrimmoryLibrary(touchmenu)
    closeTouchMenu(touchmenu)
    if not self.api:isPaired() and Net.usb then
        -- no copy of the library yet: the first sync brings it
        require("gzreader_usbsync").show(self)
        return true
    end
    if not self.api:isPaired() then
        UIManager:show(ConfirmBox:new{
            -- (connected before: Grimmory stopped taking its login)
            text = self.store.server and self.store.username
                and T(_("Grimmory signed this Kindle out (%1 at %2). Your books and progress are still here. Connect again?"),
                    self.store.username, (self.store.server:gsub("^https?://", "")))
                or _("This Kindle isn't connected to Grimmory yet. Connect now with a QR code?"),
            ok_text = _("Connect"),
            ok_callback = function() self:onGrimmoryPair() end,
        })
        return true
    end
    -- open at once: lists come from their saved copies while Wi-Fi connects
    Mod.Browser:new(self):show()
    if not Net.connected() then Net.run(function() end, { quiet = true, reason = "Grimmory library" }) end
    return true
end

--- Settings → Connections → Sync through a computer.
function Grimmory:usbSyncItems()
    local Usb = require("gzreader_usbsync")
    return {
        {
            text = _("Sync with computer…"),
            enabled_func = function() return Usb.active() end,
            keep_menu_open = true,
            callback = function() Usb.show(self) end,
        },
        {
            text = _("Sync through a computer"),
            help_text = _("For Kindles without Wi-Fi (Kindle 2, DX), on by itself there: books, audiobooks, music, notes and calendars come from a web page on a computer the Kindle is plugged into, and your reading goes back to Grimmory the same way. GZreader restarts to switch."),
            checked_func = function() return Usb.active() end,
            callback = function()
                Usb.setActive(not Usb.active())
                UIManager:show(ConfirmBox:new{
                    text = _("GZreader needs to restart for this. Restart now?"),
                    ok_text = _("Restart"),
                    ok_callback = function() dispatch("restart") end,
                })
            end,
        },
        {
            text = _("Sync queue"),
            enabled_func = function() return #(self.store.usb_queue or {}) > 0 end,
            keep_menu_open = true,
            callback = function() Usb.showQueue(self) end,
        },
    }
end

--- The Calendar tab (ZenOS's tab bar): CalDAV calendars.
function Grimmory:onShowGzCalendar(touchmenu)
    closeTouchMenu(touchmenu)
    require("gzreader_calendar").show(self)
    return true
end

--- Settings → Connections → Calendar (CalDAV).
function Grimmory:calendarSettingsItems()
    return require("gzreader_calendar").settingsItems(self)
end

--- Settings → Notes (ZenOS settings): connection, storage, synced tags, limits.
function Grimmory:notesSettingsItems()
    return require("gzreader_notesettings").items(self)
end

--- The Notes tab (ZenOS's tab bar): Memos notes as sticky notes.
function Grimmory:onShowGzNotes(touchmenu)
    closeTouchMenu(touchmenu)
    require("gzreader_notes").show(self)
    return true
end

--- The GZreader folder: downloads go straight in, and it's KOReader's home
--- folder (the "Downloaded" tab). Created on first use and remembered.
Grimmory.FOLDER = "GZreader"

function Grimmory:libraryDir()
    local dir = self.store.library_dir
    if not dir then
        local home = G_reader_settings:readSetting("home_dir") or Device.home_dir or DataStorage:getDataDir()
        local previous = home .. "/" .. Grimmory.FOLDER -- kept after an update wiped the settings
        if lfs.attributes(previous, "mode") == "directory" then
            dir = previous
        else
            dir = (Device.home_dir or home) .. "/" .. Grimmory.FOLDER
        end
        self.store.library_dir = dir
        self:save()
        Log.info("library folder:", dir)
    end
    if lfs.attributes(dir, "mode") ~= "directory" then util.makePath(dir) end
    return dir
end
Grimmory.downloadDir = Grimmory.libraryDir


--- Make the GZreader folder KOReader's home folder (no prompt).
function Grimmory:useLibraryAsHome()
    local dir = self:libraryDir()
    if G_reader_settings:readSetting("home_dir") ~= dir then
        G_reader_settings:saveSetting("home_dir", dir)
        Log.info("home folder set to", dir)
    end
    if G_reader_settings:readSetting("collate") == nil then
        -- same sort default ZenOS's folder page applied: most recently opened first
        G_reader_settings:saveSetting("collate", "access")
        G_reader_settings:saveSetting("collate_mixed", true)
    end
    self.store.home_is_library = true
    self:save()
    -- show it now; looked up later because during startup the file manager
    -- isn't registered yet
    UIManager:nextTick(function()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager.instance
        if fm and fm.file_chooser and fm.file_chooser.goHome then
            pcall(fm.file_chooser.goHome, fm.file_chooser)
        end
    end)
    return dir
end

---------------------------------------------------------------- downloads list backup

-- The list of downloaded Grimmory books also lives in the books folder
-- (hidden file), so replacing the koreader folder (and its settings) on an
-- update doesn't forget which local files are Grimmory books.
local MANIFEST = ".gzreader-library.json"

function Grimmory:writeManifest()
    local dir = self.store.library_dir
    if not dir then return end
    local list = {}
    for id, e in pairs(self.store.downloads) do
        if type(e) == "table" and e.path then
            list[#list + 1] = { id = id, file = e.path:match("[^/]+$"), title = e.title,
                format = e.format, file_id = e.file_id, last_pushed_pct = e.last_pushed_pct }
        end
    end
    local f = io.open(dir .. "/" .. MANIFEST, "wb")
    if f then f:write(JSON.encode({ version = 1, books = list })); f:close() end
end

--- Merge the backup list into the settings (after an update wiped them).
function Grimmory:restoreFromManifest()
    local dir = self.store.library_dir
    local f = dir and io.open(dir .. "/" .. MANIFEST, "rb")
    if not f then return 0 end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    local restored = 0
    if ok and type(data) == "table" and type(data.books) == "table" then
        for _, b in ipairs(data.books) do
            local id = b.id and tostring(b.id)
            local path = type(b.file) == "string" and (dir .. "/" .. b.file)
            if id and path and not self.store.downloads[id] and lfs.attributes(path, "mode") == "file" then
                self.store.downloads[id] = { path = path, title = b.title, format = b.format,
                    file_id = tonumber(b.file_id), last_pushed_pct = tonumber(b.last_pushed_pct) }
                restored = restored + 1
            end
        end
    end
    if restored > 0 then
        Log.info("restored", restored, "downloaded books from", MANIFEST)
        self:save()
    end
    return restored
end

--- Link books in the GZreader folder to Grimmory's and give them their
--- subtitles: when the index or the folder changed since it was last done
--- (it ran 8 s after every book closed: KOReader starts the plugin again
--- then; on a big library that was seconds of work each time).
function Grimmory:libraryUpkeep(index, force)
    local dir = self.store.library_dir
    local sig = tostring(index and index.built_at) .. "|" .. tostring(dir and lfs.attributes(dir, "modification"))
    if not force and Grimmory.upkeep_sig == sig then return end
    Grimmory.upkeep_sig = sig
    pcall(self.relinkLibrary, self, index)
    pcall(require("gzreader_titles").backfill, self)
end

--- Match books in the folder that aren't linked yet to Grimmory books by
--- file name, using the library index. Returns the number linked.
function Grimmory:relinkLibrary(index)
    local dir = self.store.library_dir
    if not dir or not index or type(index.files) ~= "table" then return 0 end
    local linked_paths = {}
    for _, e in pairs(self.store.downloads) do if type(e) == "table" and e.path then linked_paths[e.path] = true end end
    local by_safe_name = {}
    -- (the folder's file system, read once: getSafeFilename read /proc/mounts
    -- again for every book in the library)
    local orig_fstype = util.getFilesystemType
    if orig_fstype then
        local fstype = orig_fstype(dir)
        util.getFilesystemType = function(p) if p == dir then return fstype end return orig_fstype(p) end
    end
    local ok_names, err_names = pcall(function()
        for name, info in pairs(index.files) do
            by_safe_name[util.getSafeFilename(name, dir)] = info
            by_safe_name[name] = info
        end
    end)
    util.getFilesystemType = orig_fstype
    if not ok_names then Log.warn("relink: file names:", tostring(err_names)) end
    local linked = 0
    for name in lfs.dir(dir) do
        local path = dir .. "/" .. name
        local info = by_safe_name[name]
        if info and not linked_paths[path] and lfs.attributes(path, "mode") == "file" then
            local id = tostring(info[1])
            if not self.store.downloads[id] then
                self.store.downloads[id] = { path = path, title = info[4], format = info[3], file_id = tonumber(info[2]) }
                linked = linked + 1
            end
        end
    end
    if linked > 0 then
        Log.info("relinked", linked, "books already on the Kindle")
        self:save()
        self:writeManifest()
    end
    return linked
end

function Grimmory:localPathFor(book_id)
    local entry = book_id and self.store.downloads[tostring(book_id)]
    if type(entry) == "table" and entry.path and lfs.attributes(entry.path, "mode") == "file" then
        return entry.path
    end
end

--- opts.no_open: download only (the book page's Download): in the
--- background, a note when it's done.
function Grimmory:downloadAndOpen(book, menu, opts)
    opts = opts or {}
    if Net.usb then
        -- no Wi-Fi: into the sync queue; the next sync with the computer brings it
        return require("gzreader_usbsync").queuedMessage(self, book)
    end
    if opts.no_open then
        local quiet = {}
        for k, v in pairs(book) do quiet[k] = v end
        quiet.gz_quiet = true
        book = quiet
    end
    local dir = self:downloadDir()
    local name = type(book.primaryFileName) == "string" and book.primaryFileName:match("[^/\\]+$") or nil
    if not name or name == "" then
        local ext = (type(book.primaryFileType) == "string" and book.primaryFileType:lower() or "epub")
        if ext == "cbx" then ext = "cbz" end
        name = (book.title or ("book-" .. tostring(book.id))) .. "." .. ext
    end
    name = util.getSafeFilename(name, dir)
    local path = dir .. "/" .. name
    local title = type(book.title) == "string" and book.title or name
    if book.gz_quiet and not Mod.Download.active then
        UIManager:show(InfoMessage:new{ text = T(_("Downloading “%1”…"), title), timeout = 2 })
    end
    Mod.Download.start(self, book, path, function(ok, err, watching, info)
        info = info or {}
        if not ok then
            if err ~= "cancelled" then
                if info.queued then
                    UIManager:show(InfoMessage:new{ text = T(_("“%1” couldn't be downloaded: %2"), title, tostring(err)), timeout = 5 })
                else
                    self:showError(err)
                end
            end
            return
        end
        local entry = {
            path = path,
            title = title,
            -- (the spine shows them when the file has none: gzreader_shelfview.lua)
            authors = type(book.authors) == "table" and #book.authors > 0 and table.concat(book.authors, "\n") or nil,
            subtitle = info.subtitle,
            format = type(book.primaryFileType) == "string" and book.primaryFileType or nil,
            file_id = tonumber(book.primaryFileId),
        }
        -- Grimmory's progress, for the book's first opening without Wi-Fi
        -- (gzreader_sync.lua: Sync:onReady)
        entry.grimmory_progress = Sync.progressOf(book)
        self.store.downloads[tostring(book.id)] = entry
        self:save()
        self:writeManifest()
        -- the Downloads tab, if it's what's on screen: the new book in it
        pcall(self.refreshDownloadsTab, self)
        if book.gz_quiet then
            -- (downloaded for later: a picture book is fitted before it's first opened)
            pcall(function() require("gzreader_picturebook").prepare(path) end)
        end
        if book.gz_quiet and Net.connected() then
            -- (downloaded for later: Grimmory's latest, while Wi-Fi is on)
            local key = tostring(book.id)
            require("gzreader_async").run(self.api, function(api) return api:getBook(book.id) end, function(full)
                local p = Sync.progressOf(full)
                if p and self.store.downloads[key] == entry and not (self.sync and self.sync.book_id == key) then
                    entry.grimmory_progress = p
                    self:save()
                end
                -- (and which of your shelves it's on: gzreader_shelves.lua)
                if self.store.downloads[key] == entry then
                    pcall(function() require("gzreader_shelves").remember(self, key, full) end)
                end
            end, "download progress", { nice = true })
        end
        pcall(function() require("gzreader_coverwarm").schedule(self, 15) end)
        local Titles = require("gzreader_titles")
        local sub = info.subtitle or Titles.subtitle(self, book.id)
        if sub then
            entry.subtitle = sub
            local okA, did = pcall(Titles.apply, path, title, sub, type(book.authors) == "table" and table.concat(book.authors, "\n") or nil)
            if okA and did then
                UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
            end
        end
        local shown = Titles.full(title, sub)
        if book.gz_quiet and not watching then
            UIManager:show(InfoMessage:new{ text = (info.left or 0) > 0
                and T(_("Downloaded “%1”. %2 more in the queue."), shown, info.left)
                or T(_("Downloaded “%1”."), shown), timeout = 3 })
        elseif watching then
            self:openBook(path, menu)
        elseif info.queued or (info.left or 0) > 0 then
            UIManager:show(InfoMessage:new{
                text = (info.left or 0) > 0 and T(_("Downloaded “%1”. %2 more in the queue."), shown, info.left)
                    or T(_("Downloaded “%1”. The download queue is done."), shown),
                timeout = 4 })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("“%1” has finished downloading. Open it now?"), shown),
                ok_text = _("Open"),
                cancel_text = _("Later"),
                ok_callback = function() self:openBook(path, menu) end,
            })
        end
    end)
end

--- Is the Downloads tab (the file manager in the GZreader folder) what's on
--- screen? Not under Home, the Grimmory tab, a book or another full-screen
--- page; a message box over it doesn't count.
function Grimmory:downloadsTabShowing()
    local FM = require("apps/filemanager/filemanager")
    local fm = FM.instance
    local fc = fm and fm.file_chooser
    if not (fc and fc.path and not fm.invisible and not fm.tearing_down) then return false end
    local dir = self.store.library_dir
    if not dir or fc.path:gsub("/+$", "") ~= dir:gsub("/+$", "") then return false end
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w == fm then return true end
        if w and (w.covers_fullscreen or w._gz_navbar_tab_id) then return false end
    end
    return false
end

--- A book was downloaded: if the Downloads tab is on screen, show it again
--- with the book in it (before, it showed up only after leaving the tab).
function Grimmory:refreshDownloadsTab()
    if not self:downloadsTabShowing() then return false end
    local fc = require("apps/filemanager/filemanager").instance.file_chooser
    fc:refreshPath()
    Log.info("Downloads tab refreshed: a new book")
    return true
end

--- Downloads from before 1.22.4: ask Grimmory for their authors (in the
--- background, while Wi-Fi is on anyway; 40 at a time; each book once).
function Grimmory:backfillAuthors()
    if self.backfilling or not self.api:isPaired() or not Net.connected() then return end
    local ids = {}
    for id, e in pairs(self.store.downloads or {}) do
        if type(e) == "table" and e.authors == nil and not e.authors_asked and tonumber(id) then
            ids[#ids + 1] = id
            if #ids >= 40 then break end
        end
    end
    if #ids == 0 then return end
    self.backfilling = true
    local api = self.api
    require("gzreader_async").run(api, function()
        local got = {}
        for _i, id in ipairs(ids) do
            local d = api:getBookDetail(id)
            if type(d) == "table" and type(d.authors) == "table" then got[id] = table.concat(d.authors, "\n") end
        end
        return got
    end, function(got)
        self.backfilling = nil
        if type(got) ~= "table" then return end
        for _i, id in ipairs(ids) do
            local e = self.store.downloads[id]
            if type(e) == "table" then
                e.authors_asked = true
                if got[id] and got[id] ~= "" then e.authors = got[id] end
            end
        end
        self:save()
        Log.info("authors for", #ids, "downloaded books asked from Grimmory")
        pcall(function()
            local FM = require("apps/filemanager/filemanager")
            local fc = FM.instance and FM.instance.file_chooser
            if fc then fc:refreshPath() end
        end)
    end, "authors")
end

function Grimmory:openBook(path, menu)
    if menu then UIManager:close(menu) end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:switchDocument(path)
    else
        ReaderUI:showReader(path)
    end
end

return Grimmory
