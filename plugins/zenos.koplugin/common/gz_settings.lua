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
}

--- Whether the KOReader section shows `item` (a KOReader menu item).
function M.keepKOReaderItem(item)
    return not (type(item) == "table" and type(item.id) == "string" and M.KOREADER_HIDDEN[item.id])
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
--- into General → Advanced: everything but Usage statistics, which stays in
--- General where it's easy to find.
function M.splitDiagnostics(items)
    local usage = require("gettext")("Usage statistics")
    local stay, advanced = {}, {}
    for _i, item in ipairs(items or {}) do
        if type(item) == "table" and item.text == usage then
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
function M.wifiItem(gz_item, zen_item)
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
    gz_item.sub_item_table = items
    return gz_item
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
