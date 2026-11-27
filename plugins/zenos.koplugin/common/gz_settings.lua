-- GZreader: decisions about what Settings shows, kept out of ZenOS's big
-- settings files so they can be tested on their own (zen_settings_test.lua).
local M = {}

--- GZreader's Grimmory plugin instance (reader or file manager), or nil.
function M.gzreader()
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, cls = pcall(require, mod)
        local inst = ok and type(cls) == "table" and cls.instance
        if type(inst) == "table" and type(inst.gzreader) == "table" then return inst.gzreader end
    end
end

--- Navbar tabs whose apps aren't in GZreader's package: Manga (Rakuyomi),
--- News (QuickRSS, RSS Reader), Calibre Search (the calibre plugin). Not
--- offered in Settings → Home and tabs → Tab bar and not shown in the bar even
--- when an earlier version saved them as on.
M.HIDDEN_TABS = { manga = true, news = true, calibre_search = true }

--- `list` without the hidden tabs; entries are ids or { id = … } tables.
function M.dropHiddenTabs(list)
    local out = {}
    for _i, entry in ipairs(list or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if not M.HIDDEN_TABS[id] then out[#out + 1] = entry end
    end
    return out
end

--- KOReader menu items GZreader leaves out where it shows KOReader's rows (by
--- KOReader's menu id), because they work against GZreader or ZenOS:
M.KOREADER_HIDDEN = {
    -- turning off gzreader, zenos or coverbrowser breaks GZreader; patches are untested code
    plugin_management = true,
    patch_management = true,
    developer_options = true,
    -- Help → Disable external plugins: gzreader and zenos are "external" to KOReader
    plugins_disable_external = true,
    -- Help → Report a bug points at KOReader's issues (Privacy and diagnostics → Report a problem is GZreader's)
    report_bug = true,
    -- CoverBrowser's classic/mosaic/list fights ZenOS's library views and the Bookshelf view
    filemanager_display_mode = true,
    -- GZreader starts at Home (Settings → Home and tabs → Tab bar → Default tab)
    start_with = true,
    -- Wi-Fi on Auto turns Wi-Fi on and off by itself (Settings → Wi-Fi)
    network_restore = true,
    network_before_wifi_action = true,
    network_after_wifi_action = true,
    -- "Disable Wi-Fi connection when inactive": turned Wi-Fi off after 5 quiet
    -- minutes even on On (gzreader_net.lua clears a saved tick)
    network_powersave = true,
    -- the same menu as Settings → Accounts and services → Books
    gzreader = true,
    -- the whole File browser menu: Sort by, Book status, Reverse, mixed are
    -- what ZenOS's own Sort and Filter in Downloads set (the same settings),
    -- and its Settings repeat Downloads' (layout, items per page, hidden
    -- files, files from subfolders)
    filemanager_settings = true,
    -- Tools → Reading statistics: the plugin stays (time left, book details,
    -- the end-of-book page, Reading goals), its menu goes
    statistics = true,
    -- Taps and gestures → Disable double tap: GZreader has no double-tap
    -- actions (no gestures plugin); unticked, every tap in a book waited for
    -- a second one
    screen_disable_double_tap = true,
    -- Document → Book metadata location and Move book metadata: GZreader's
    -- Storage and its clean-ups look for a book's .sdr folder next to it
    document_metadata_location = true,
    document_metadata_location_move = true,
}

--- Whether `item` (a KOReader menu item) is shown (not in About → Advanced →
--- KOReader settings, which shows everything).
function M.keepKOReaderItem(item)
    return not (type(item) == "table" and type(item.id) == "string" and M.KOREADER_HIDDEN[item.id])
end

--- KOReader menu items KOReader's menu (native_menu.settingsItems, filtered) leaves out because
--- GZreader has them elsewhere. Unlike KOREADER_HIDDEN they still work where
--- GZreader takes one by its id (Reader → End of book's End of document
--- action), so only the section drops them (native_menu.settingsItems).
M.KOREADER_DUPLICATES = {
    -- Settings → General: Language, Time and date; Sleep and wallpaper: Sleep (and its Automatic
    -- suspend), Wi-Fi (and, in Wi-Fi, HTTP proxy and Network info)
    language = true, time = true, screensaver = true, autosuspend = true, network_wifi = true,
    network_proxy = true, network_info = true,
    -- the History, Favorites and Collections tabs
    history = true, favorites = true, collections = true,
    -- Settings → Display and light → Screen: KOReader's whole Screen menu (M.screenItem)
    screen = true,
    -- Settings → Reader → Closing a book → End of book
    document_end_action = true,
    -- the quick panel's Night mode, Rotate, Restart, Sleep and Exit tiles
    -- (exit_menu: Restart, Sleep, Exit)
    night_mode = true, screen_rotation = true, exit_menu = true,
    -- Settings → General → About (GZreader's version), General → Setup Guide
    version = true, about = true, quickstart_guide = true,
    -- not used by GZreader
    cloud_storage = true,
    -- Settings → Home and tabs → Quick panel: Open with a tap / a swipe
    -- (gzreader_panel.lua openRows; its Auto-show bottom menu does nothing here)
    menu_activate = true,
}

--- `list` (rows copied from KOReader's menu for the KOReader section) without
--- KOREADER_DUPLICATES, inside submenus too, and again after a refresh.
function M.dropKOReaderDuplicates(list)
    if type(list) ~= "table" then return list end
    local out = {}
    for key, value in pairs(list) do
        if type(key) ~= "number" then out[key] = value end
    end
    for _i, refresh in ipairs({ "_zen_refresh", "refresh_func" }) do
        if type(list[refresh]) == "function" then
            local f = list[refresh]
            out[refresh] = function(...) return M.dropKOReaderDuplicates(f(...)) end
        end
    end
    for _i, item in ipairs(list) do
        if not (type(item) == "table" and type(item.id) == "string" and M.KOREADER_DUPLICATES[item.id]) then
            if type(item) == "table" then
                if type(item.sub_item_table) == "table" then
                    item.sub_item_table = M.dropKOReaderDuplicates(item.sub_item_table)
                elseif type(item.sub_item_table_func) == "function" then
                    local f = item.sub_item_table_func
                    item.sub_item_table_func = function(...) return M.dropKOReaderDuplicates(f(...)) end
                end
            end
            out[#out + 1] = item
        end
    end
    return out
end

--- Settings → Display and light → Screen: KOReader's Screen menu (DPI, E-ink settings,
--- Fullscreen, …; out of Settings → KOReader, KOREADER_DUPLICATES.screen),
--- without what GZreader has elsewhere (Sleep screen, Rotation), and with
--- GZreader's flash rows (`gz_items`: Flash on every page turn, Flash when
--- the screen changes, Partial pages refresh) in its E-ink settings after
--- Full refresh rate. `native`: modules/menu/app_launcher/native_menu. Built
--- when opened, from the menu of whatever is open (Home or a book).
function M.screenItem(native, gz_items)
    local _ = require("gettext")
    return {
        text = _("Screen"),
        sub_item_table_func = function() return M.screenItems(native, gz_items) end,
    }
end

--- The rows of Settings → Display and light → Screen (see screenItem).
function M.screenItems(native, gz_items)
    gz_items = type(gz_items) == "table" and gz_items or {}
    local ok, got = pcall(function() return native.settingsItems("active", "screen") end)
    local screen = ok and type(got) == "table" and got[1]
    local list
    if type(screen) == "table" then
        list = screen.sub_item_table
        if type(list) ~= "table" and type(screen.sub_item_table_func) == "function" then
            local okf, l = pcall(screen.sub_item_table_func)
            list = okf and l or nil
        end
    end
    if type(list) ~= "table" then
        -- no KOReader menu to take it from: GZreader's own rows alone
        local out = {}
        for _i, item in ipairs(gz_items) do out[#out + 1] = item end
        return out
    end
    return M.withFlashRows(M.dropKOReaderDuplicates(list), gz_items)
end

--- `list` (KOReader's Screen rows) with `gz_items` in its E-ink settings, after
--- Full refresh rate (at the end of the list when there's no E-ink settings).
function M.withFlashRows(list, gz_items)
    if type(list) ~= "table" or #gz_items == 0 then return list end
    -- (the Settings page builds the list again from KOReader's on a refresh: again with them)
    for _i, refresh in ipairs({ "_zen_refresh", "refresh_func" }) do
        if type(list[refresh]) == "function" then
            local f = list[refresh]
            list[refresh] = function(...) return M.withFlashRows(f(...), gz_items) end
        end
    end
    local function into(children)
        if type(children) ~= "table" then return children end
        local out = {}
        for key, value in pairs(children) do
            if type(key) ~= "number" then out[key] = value end
        end
        for _i, refresh in ipairs({ "_zen_refresh", "refresh_func" }) do
            if type(children[refresh]) == "function" then
                local f = children[refresh]
                out[refresh] = function(...) return into(f(...)) end
            end
        end
        local at = 0
        local full = require("gettext")("Full refresh rate")
        for i, item in ipairs(children) do
            out[#out + 1] = item
            if type(item) == "table" and item.text == full then at = i end
        end
        for i, item in ipairs(gz_items) do table.insert(out, at + i, item) end
        if at > 0 then out[at].separator = nil end
        gz_items[#gz_items].separator = true
        return out
    end
    for _i, item in ipairs(list) do
        if type(item) == "table" and item.id == "screen_eink_opt" then
            if type(item.sub_item_table) == "table" then
                item.sub_item_table = into(item.sub_item_table)
            elseif type(item.sub_item_table_func) == "function" then
                local f = item.sub_item_table_func
                item.sub_item_table_func = function(...) return into(f(...)) end
            end
            return list
        end
    end
    if #list > 0 and type(list[#list]) == "table" then list[#list].separator = true end
    for _i, item in ipairs(gz_items) do list[#list + 1] = item end
    return list
end

--- A line in GZreader's log, written to the storage at once (still there
--- after a freeze and a restart).
function M.trace(...)
    local ok, Log = pcall(require, "gzreader_log")
    if ok and type(Log) == "table" and type(Log.infoNow) == "function" then pcall(Log.infoNow, true, "settings:", ...) end
end

--- KOReader's sections, each saying in the log that it's being opened
--- before its rows are gathered (each plugin's own menu code runs then), and
--- how long that took when it was slow. The items themselves are changed
--- in place and returned.
function M.traced(items)
    for _i, item in ipairs(items) do
        local gather = type(item) == "table" and item.sub_item_table_func
        if type(gather) == "function" and not item._gz_traced then
            item._gz_traced = true
            item.sub_item_table_func = function(...)
                M.trace("KOReader settings: opening", tostring(item.text))
                local t0 = os.time()
                local rows = gather(...)
                if os.time() - t0 >= 2 then M.trace("KOReader settings:", tostring(item.text), "took", os.time() - t0, "s") end
                return rows
            end
        end
    end
    return items
end

--- About → Advanced → KOReader settings: KOReader's whole menu, nothing left
--- out (native_menu.settingsItems unfiltered: also what KOREADER_HIDDEN and
--- KOREADER_DUPLICATES leave out elsewhere), from the menu of whatever is open
--- (Home or the book). It was the Settings → KOReader section until the owner
--- asked for it here (2026-11-11). `plugin_root`: ZenOS's folder (the icon).
function M.koreaderMenuItem(plugin_root, native)
    local _ = require("gettext")
    local T = require("ffi/util").template
    return {
        -- (gettext keeps "KOReader settings" as it is; any other string naming KOReader shows GZreader)
        text = _("KOReader settings"),
        help_text = T(_("All of %1's own settings, as %1 has them, including those GZreader leaves out elsewhere because they can work against it (plugin and patch management, developer options, Wi-Fi actions). Change them only if you know what they do."), "KOReader"),
        icon_file = plugin_root and (plugin_root .. "/icons/koreader.png") or nil,
        _zen_settings_root = "koreader",
        sub_item_table_func = function()
            native = native or require("modules/menu/app_launcher/native_menu")
            -- (a line in the log before each part is gathered, written to the storage at once: the
            -- owner's Scribe froze here and restarted with nothing in the log to say where)
            M.trace("KOReader settings: gathering KOReader's menu")
            local ok, items = pcall(native.settingsItems, "active", nil, { unfiltered = true })
            if not ok then M.trace("KOReader settings: could not be gathered", tostring(items)) end
            items = ok and type(items) == "table" and items or {}
            M.trace("KOReader settings:", #items, "sections")
            return M.traced(items)
        end,
    }
end

--- General → Transfer or reset → Reset GZreader: settings to their defaults, downloads
--- and accounts gone, a restart into the setup guide (gzreader_reset.lua
--- asks first).
function M.resetItem()
    local _ = require("gettext")
    return {
        icon_glyph = require("common/inline_icon_map").restart,
        text = _("Reset GZreader"),
        help_text = _("Every setting back to its default, every download removed from this device, every account forgotten on it; then GZreader restarts with the setup guide. Asks first."),
        callback = function(touchmenu)
            local g = M.gzreader()
            local ok, Reset = pcall(require, "gzreader_reset")
            if not (g and ok) then return end
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            Reset.confirm(g)
        end,
    }
end

--- About's first two lines: GZreader's version, then what it's built on.
function M.aboutLines(gz_version, zen_version, ko_version)
    local _ = require("gettext")
    local T = require("ffi/util").template
    -- (the names go in as arguments: gettext.lua turns "ZenOS" and "KOReader"
    -- inside a UI string into "GZreader")
    return T(_("%1 %2"), "GZreader", gz_version or "?"),
        T(_("Built on %1 %2 and %3 %4"), "ZenOS", zen_version or "?", "KOReader", ko_version or "?")
end

--- GZreader's time zone setting (the Kindle 3 has none of its own: its
--- clock is UTC; gzreader_timezone.lua).
function M.timeZoneItem()
    local _ = require("gettext")
    return {
        text_func = function()
            local ok, TZ = pcall(require, "gzreader_timezone")
            return _("Time zone") .. (ok and (": " .. TZ.label()) or "")
        end,
        sub_item_table_func = function()
            local ok, TZ = pcall(require, "gzreader_timezone")
            return ok and TZ.menuItems() or {}
        end,
    }
end

--- General → Time and date: KOReader's menu (`base`, shared with
--- KOReader's own Settings → Device, so copied, not changed) with Time zone
--- first.
function M.timeAndDate(base, tz_item)
    local item = {}
    for k, v in pairs(type(base) == "table" and base or {}) do item[k] = v end
    local list = { tz_item or M.timeZoneItem() }
    for _i, sub in ipairs(type(item.sub_item_table) == "table" and item.sub_item_table or {}) do
        list[#list + 1] = sub
    end
    item.sub_item_table = list
    return item
end

--- Settings → General → Storage: what GZreader keeps on the Kindle, as
--- rows with icons and arrows into the biggest of each (gzreader_storage.lua).
function M.storageItem()
    local _ = require("gettext")
    return {
        text = _("Storage"),
        sub_item_table_func = function(page)
            local g = M.gzreader()
            local ok, Storage = pcall(require, "gzreader_storage")
            if g and ok and type(Storage) == "table" and type(Storage.settingsItems) == "function" then
                return Storage.settingsItems(g, page)
            end
            return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
        end,
    }
end

--- GZreader's installed version ("0.0.0" when unknown).
function M.gzreaderVersion()
    local ok, Update = pcall(require, "gzreader_update")
    if ok and type(Update) == "table" and type(Update.currentVersion) == "function" then
        local okv, v = pcall(Update.currentVersion)
        if okv and type(v) == "string" then return v end
    end
    return "0.0.0"
end

--- (Unused since 1.32.x: Settings → Privacy and diagnostics has them all.)
--- Of GZreader's diagnostics items, the ones that moved
--- into About → Advanced: everything but Send debug reports automatically,
--- which stays in General where it's easy to find (as Usage statistics did
--- up to 1.28.1; GZreader no longer sends them).
function M.splitDiagnostics(items)
    local reports = require("gettext")("Send debug reports automatically")
    local stay, advanced = {}, {}
    for _i, item in ipairs(items or {}) do
        if type(item) == "table" and item.text == reports then
            stay[#stay + 1] = item
        else
            advanced[#advanced + 1] = item
        end
    end
    return stay, advanced
end

--- Settings → Wi-Fi as GZreader has it: GZreader's item (On, Off,
--- Auto; gzreader_net.lua Net.menuItem) with ZenOS's network list after
--- them, in place of ZenOS's Wi-Fi switch. `zen_item`: ZenOS's Wi-Fi row (its
--- callback opens the network list), or nil.
function M.wifiItem(gz_item, zen_item, net)
    if type(gz_item) ~= "table" then return zen_item end
    local items = {}
    for _i, item in ipairs(gz_item.sub_item_table or {}) do items[#items + 1] = item end
    if type(zen_item) == "table" and type(zen_item.callback) == "function" then
        items[#items + 1] = {
            text = require("gettext")("Networks"),
            _zen_settings_submenu = true,
            keep_menu_open = true,
            callback = zen_item.callback,
        }
    end
    -- KOReader's HTTP proxy (tap: on/off; hold: the address) and Network info,
    -- here instead of Settings → KOReader → Network (KOREADER_DUPLICATES)
    for _i, item in ipairs(M.networkItems(net)) do items[#items + 1] = item end
    gz_item.sub_item_table = items
    return gz_item
end

--- KOReader's HTTP proxy and Network info rows (NetworkMgr's own), or none.
function M.networkItems(net)
    local out = {}
    if not net then
        local ok, mgr = pcall(require, "ui/network/manager")
        if not ok then return out end
        net = mgr
    end
    for _i, name in ipairs({ "getProxyMenuTable", "getInfoMenuTable" }) do
        local ok, item = pcall(function() return net[name](net) end)
        if ok and type(item) == "table" then
            item.keep_menu_open = true
            out[#out + 1] = item
        end
    end
    return out
end

--- GZreader's audio settings, by text: they come with the Reader section's
--- items (gzreader main.lua sectionItems("reader")) but are for music and
--- audiobooks too, so Settings shows them in General → Audio.
M.AUDIO_ITEMS = { "Read aloud", "Test audiobook playback", "Pause when headphones are unplugged", "Find the headphone jack" }

--- `items` split into the audio ones (in their order) and the rest.
function M.splitAudio(items)
    local _ = require("gettext")
    local wanted = {}
    for _i, t in ipairs(M.AUDIO_ITEMS) do wanted[_(t)] = true end
    local audio, rest = {}, {}
    for _i, item in ipairs(items or {}) do
        if type(item) == "table" and wanted[item.text] then audio[#audio + 1] = item else rest[#rest + 1] = item end
    end
    return audio, rest
end

return M
