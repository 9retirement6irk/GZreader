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
--- offered in Settings → Interface → Navbar and not shown in the bar even
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

--- KOReader menu items the Settings → KOReader section leaves out (by
--- KOReader's menu id), because they work against GZreader or ZenOS:
M.KOREADER_HIDDEN = {
    -- turning off gzreader, zenos or coverbrowser breaks GZreader; patches are untested code
    plugin_management = true,
    patch_management = true,
    developer_options = true,
    -- Help → Disable external plugins: gzreader and zenos are "external" to KOReader
    plugins_disable_external = true,
    -- Help → Report a bug points at KOReader's issues (About → Report a bug is GZreader's)
    report_bug = true,
    -- CoverBrowser's classic/mosaic/list fights ZenOS's library views and the Bookshelf view
    filemanager_display_mode = true,
    -- GZreader starts at Home (Settings → Interface → Navbar → Default tab)
    start_with = true,
    -- Wi-Fi on Auto turns Wi-Fi on and off by itself (Settings → General → Wi-Fi)
    network_restore = true,
    network_before_wifi_action = true,
    network_after_wifi_action = true,
    -- "Disable Wi-Fi connection when inactive": turned Wi-Fi off after 5 quiet
    -- minutes even on On (gzreader_net.lua clears a saved tick)
    network_powersave = true,
    -- the same menu as Settings → Connections → Grimmory
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
    -- a second one (gzreader_touch.lua forgetKOReaderDoubleTap clears it)
    screen_disable_double_tap = true,
    -- Document → Book metadata location and Move book metadata: GZreader's
    -- Storage and its clean-ups look for a book's .sdr folder next to it
    document_metadata_location = true,
    document_metadata_location_move = true,
}

--- Whether the KOReader section shows `item` (a KOReader menu item).
function M.keepKOReaderItem(item)
    return not (type(item) == "table" and type(item.id) == "string" and M.KOREADER_HIDDEN[item.id])
end

--- KOReader menu items the Settings → KOReader section leaves out because
--- GZreader has them elsewhere. Unlike KOREADER_HIDDEN they still work where
--- GZreader takes one by its id (Reader → End of book's End of document
--- action), so only the section drops them (native_menu.settingsItems).
M.KOREADER_DUPLICATES = {
    -- Settings → General: Language, Time and date, Sleep (and its Automatic
    -- suspend), Wi-Fi (and, in Wi-Fi, HTTP proxy and Network info)
    language = true, time = true, screensaver = true, autosuspend = true, network_wifi = true,
    network_proxy = true, network_info = true,
    -- the History, Favorites and Collections tabs
    history = true, favorites = true, collections = true,
    -- Settings → General → Screen: KOReader's whole Screen menu (M.screenItem)
    screen = true,
    -- Settings → Reader → End of book
    document_end_action = true,
    -- the quick panel's Night mode, Rotate, Restart, Sleep and Exit tiles
    -- (exit_menu: Restart, Sleep, Exit)
    night_mode = true, screen_rotation = true, exit_menu = true,
    -- Settings → About (GZreader's version), About → Setup Guide
    version = true, about = true, quickstart_guide = true,
    -- not used by GZreader
    cloud_storage = true,
    -- Settings → Interface → Quick panel: Open with a tap / a swipe
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

--- Settings → General → Screen: KOReader's Screen menu (DPI, E-ink settings,
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

--- The rows of Settings → General → Screen (see screenItem).
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

--- Of GZreader's diagnostics items (Settings → General), the ones that move
--- into General → Advanced: everything but Send debug reports automatically,
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

--- Settings → General → Wi-Fi as GZreader has it: GZreader's item (On, Off,
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
