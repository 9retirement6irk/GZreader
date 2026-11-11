-- Settings as GZreader trims it: General → Advanced (GZreader's diagnostic
-- log items, no Debug logging / Clear all gestures / Plugin management),
-- About (GZreader's version first, Report a bug → Send to the developer),
-- the KOReader section without the items that clash, no Manga / News /
-- Calibre Search tabs. ZenOS's settings modules are real; the rest are stubs.
--   luajit gz_settings_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local function magic()
    local m
    m = setmetatable({}, { __index = function() return m end, __call = function() return m end,
        __concat = function() return "" end, __tostring = function() return "" end })
    return m
end
local real = {
    ["modules/settings/zen_settings"] = true,
    ["modules/settings/sections/extras_settings"] = true,
    ["modules/settings/sections/global_settings"] = true,
    ["modules/settings/sections/general_settings"] = true,
    ["modules/settings/sections/advanced_settings"] = true,
    ["modules/settings/sections/about_settings"] = true,
    ["modules/settings/sections/interface_settings"] = true,
    ["modules/settings/zen_settings_utils"] = true,
    ["modules/settings/koreader_settings"] = true,
    ["common/gz_settings"] = true,
    ["common/gz_settings_icons"] = true,
    ["common/inline_icon_map"] = true,
    ["common/gz_wifi_icon"] = true,
    gzreader_sleeppreview = true,
}
local PLUGIN = arg[2] -- plugins/gzreader.koplugin (the Wallpaper tiles)
if PLUGIN then package.path = PLUGIN .. "/?.lua;" .. package.path end
-- GZreader's plugin as Settings sees it
local sent = 0
local storage_shown
local gz = {
    sendLogToDeveloper = function() sent = sent + 1 end,
    sectionItems = function(_self, section)
        if section ~= "general" then return {} end
        return {
            -- (gzreader_net.lua Net.menuItem)
            wifi = { text = "Wi-Fi", mandatory_func = function() return "Auto" end, sub_item_table = {
                { text = "On", radio = true }, { text = "Off", radio = true },
                { text = "Auto (only when needed)", radio = true, separator = true } } },
            diagnostics = {
                { text = "Diagnostic logging" },
                { text = "Usage statistics" },
                { text = "Send diagnostic log to the developer" },
                { text = "Send diagnostic log to a browser (QR code)" },
                { text = "Save diagnostic log (USB)" },
            },
        }
    end,
}
local stubs = {
    -- branded as frontend/gettext.lua does: "KOReader"/"ZenOS" inside a UI string → "GZreader"
    gettext = function(s)
        if s == "KOReader" or s == "KOReader menu" or s == "KOReader settings" then return s end
        return (s:gsub("KOReader", "GZreader"):gsub("ZenOS", "GZreader"))
    end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item) return item end },
    ["common/plugin_root"] = "",
    ["modules/settings/zenpm_installer"] = { build_item = function() return nil end },
    ["modules/filebrowser/patches/rakuyomi"] = { is_available = function() return false end },
    ["apps/reader/readerui"] = {},
    ["apps/filemanager/filemanager"] = { instance = { gzreader = gz } },
    ["gzreader_update"] = { currentVersion = function() return "1.26.10" end },
    version = "v2026.07.1",
    ["gzreader_timezone"] = { label = function() return "UTC−5" end, menuItems = function() return {} end },
    ["gzreader_storage"] = { settingsItems = function(g, page)
        storage_shown = { g = g, page = page }
        return { { text = "Free on this Kindle" }, { text = "Books", sub_item_table = {} } }
    end },
    ["ui/language"] = { getLangMenuTable = function() return { text = "Language", sub_item_table = { { text = "English" } } } end },
    ["ui/elements/common_settings_menu_table"] = { time = { text = "Time and date",
        sub_item_table = { { text = "12-hour clock" }, { text = "Set time" } } } },
}
table.insert(package.loaders, 2, function(name)
    if stubs[name] ~= nil then local v = stubs[name]; return function() return v end end
    if real[name] then return nil end
    return function() return magic() end
end)
G_reader_settings = setmetatable({}, { __index = function() return function() end end })

local ok_count, fail = 0, 0
local function check(c, n) if c then ok_count = ok_count + 1 print("  ok   " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

local function text(it)
    local s = rawget(it, "text")
    if s == nil and type(rawget(it, "text_func")) == "function" then
        local okf, v = pcall(it.text_func); s = okf and v or nil
    end
    return type(s) == "string" and s or "?"
end
local function texts(list)
    local t = {}
    for _i, it in ipairs(type(list) == "table" and list or {}) do t[#t + 1] = text(it) end
    return "|" .. table.concat(t, "|") .. "|"
end
local function find(list, name)
    for _i, it in ipairs(list or {}) do if text(it) == name then return it end end
end
local function read(path)
    local f = assert(io.open(ZEN .. "/" .. path, "rb")); local s = f:read("*a"); f:close(); return s
end

local config = { features = {}, lockdown = {}, custom_icons = { active_pack = "" }, navbar = { show_tabs = {} }, _meta = {} }
local plugin = { config = config, saveConfig = function() end, version = "4.3.0" }
local okb, root = pcall(require("modules/settings/zen_settings").build, plugin)
check(okb and type(root) == "table", "Settings build " .. tostring(not okb and root or ""))
if okb then
    local items = root.sub_item_table
    local general = find(items, "General").sub_item_table
    local gen = texts(general)
    local advanced = find(general, "Advanced")
    local adv = texts(advanced and advanced.sub_item_table)
    print("    General: " .. gen)
    print("    Advanced: " .. adv)
    check(adv:find("^|Diagnostic logging|Send diagnostic log to the developer|Send diagnostic log to a browser %(QR code%)|Save diagnostic log %(USB%)|") ~= nil,
        "General → Advanced starts with the diagnostic log's items")
    check(advanced.sub_item_table[4].separator == true, "a line under them")
    check(gen:find("|Usage statistics|Advanced|", 1, true) ~= nil, "Usage statistics stays in General, just above Advanced")
    for _i, gone in ipairs({ "Diagnostic logging", "Send diagnostic log to the developer", "Save diagnostic log (USB)" }) do
        check(not gen:find("|" .. gone .. "|", 1, true), "not in General itself: " .. gone)
    end
    for _i, gone in ipairs({ "Debug logging", "Clear all gestures", "Plugin management", "Patch management" }) do
        check(not adv:find("|" .. gone .. "|", 1, true), "not in General → Advanced: " .. gone)
    end
    for _i, kept in ipairs({ "Partial pages refresh", "Show hidden files", "Extract metadata" }) do
        check(adv:find("|" .. kept .. "|", 1, true) ~= nil, "Advanced still has " .. kept)
    end

    local about = find(items, "About").sub_item_table
    print("    About: " .. texts(about))
    check(text(about[1]) == "GZreader 1.26.10", "About: GZreader's version first (" .. text(about[1]) .. ")")
    check(text(about[2]) == "Built on ZenOS 4.3.0 and KOReader v2026.07.1", "then what it's built on (" .. text(about[2]) .. ")")
    check(not texts(about):find("|ZenOS: ", 1, true), "no \"ZenOS: …\" line")
    local device = find(about, "Device")
    check(device and not texts(device.sub_item_table):find("|KOReader: ", 1, true), "Device: no KOReader line (it's on the second line)")
    check(find(about, "Report a Bug") == nil, "no ZenOS bug reporter")
    -- Wi-Fi: GZreader's On / Off / Auto menu in place of ZenOS's switch, its network list after them
    local wifi = find(general, "Wi-Fi")
    local wifi_rows = texts(wifi and wifi.sub_item_table)
    check(gen:find("|Updates|Wi-Fi|Bluetooth|", 1, true) and select(2, gen:gsub("|Wi%-Fi", "")) == 1,
        "General: one Wi-Fi row, where ZenOS's was (no separate \"Wi-Fi only when needed\") " .. gen)
    check(wifi_rows == "|On|Off|Auto (only when needed)|Networks|" and wifi.mandatory_func() == "Auto",
        "General → Wi-Fi: On, Off, Auto, then Networks; the row shows the mode " .. wifi_rows)
    local nets = wifi and wifi.sub_item_table[4]
    check(nets and type(nets.callback) == "function" and nets._zen_settings_submenu,
        "Networks opens ZenOS's network list (what its Wi-Fi row opened)")
    local GzS = require("common/gz_settings")
    check(GzS.wifiItem(nil, { text = "Wi-Fi" }).text == "Wi-Fi", "no GZreader item (a Kindle without Wi-Fi): ZenOS's Wi-Fi row stays")
    check(texts(GzS.wifiItem({ text = "Wi-Fi", sub_item_table = { { text = "On" } } }, nil).sub_item_table) == "|On|",
        "no ZenOS row to take the network list from: the modes alone")
    check(gen:find("|Sleep|Time and date|Language|Storage|Battery|", 1, true) ~= nil,
        "General: Time and date, Language and Storage after Sleep " .. gen)
    check(find(items, "Storage") == nil, "no Storage section at the top")
    local dev = texts(device and device.sub_item_table)
    check(not dev:find("|Storage|", 1, true) and not dev:find("|Language|", 1, true) and not dev:find("|Time and date|", 1, true),
        "About → Device: no Storage, Language or Time and date " .. dev)
    local storage = find(general, "Storage")
    check(storage and type(storage.sub_item_table_func) == "function" and storage.callback == nil,
        "General → Storage is a submenu (rows and arrows), not a screen of its own")
    if storage and storage.sub_item_table_func then
        local page = { item_table = nil }
        local rows = storage.sub_item_table_func(page)
        check(storage_shown and storage_shown.g == gz and storage_shown.page == page and texts(rows) == "|Free on this Kindle|Books|",
            "its rows come from gzreader_storage.settingsItems, for this Settings page")
    end
    check(read("modules/settings/sections/general_settings.lua"):find("GzSettings.storageItem(), icons.settings_storage", 1, true) ~= nil,
        "Storage has its icon")
    local td = find(general, "Time and date")
    check(td and texts(td.sub_item_table) == "|Time zone: UTC−5|12-hour clock|Set time|",
        "General → Time and date: Time zone first " .. texts(td and td.sub_item_table))
    local downloads = find(items, "Downloads")
    check(downloads and downloads.icon_name == "tab_downloaded", "Downloads has the Downloads tab's icon")
    local shared = require("ui/elements/common_settings_menu_table").time
    check(#shared.sub_item_table == 2, "KOReader's own Time and date menu left as it was")
    local bug = find(about, "Report a bug")
    check(bug and type(bug.callback) == "function", "Report a bug is there")
    if bug then
        local closed = false
        bug.callback({ closeMenu = function() closed = true end })
        check(sent == 1 and closed, "Report a bug → GZreader's Send to the developer (menu closed)")
    end
end
check(not read("modules/settings/sections/about_settings.lua"):find("require(\"modules/settings/zen_bugreporter\")", 1, true),
    "About doesn't load ZenOS's bug reporter")

-- the KOReader section
local KS = require("modules/settings/koreader_settings")
local src = {
    { id = "network_wifi", text = "Wi-Fi connection" },
    { id = "plugin_management", text = "Plugin management" },
    { id = "more_tools", text = "More tools", sub_item_table = {
        { id = "patch_management", text = "Patches" },
        { id = "advanced_settings", text = "Advanced settings" },
        { id = "developer_options", text = "Developer options" },
    } },
    { id = "start_with", text = "Start with" },
    { id = "filemanager_display_mode", text = "Display mode" },
    { id = "network_restore", text = "Restore Wi-Fi" },
    { id = "network_before_wifi_action", text = "Action when Wi-Fi is off" },
    { id = "network_after_wifi_action", text = "Action when done with Wi-Fi" },
    { id = "network_proxy", text = "HTTP proxy" },
    { id = "gzreader", text = "Grimmory" },
    { id = "statistics", text = "Reading statistics" },
    { id = "filemanager_settings", text = "File browser" },
    { id = "help", text = "Help", sub_item_table = {
        { id = "quickstart_guide", text = "Quickstart guide" },
        { id = "report_bug", text = "Report a bug" },
        { id = "plugins_disable_external", text = "Disable external plugins and user-patches" },
        { id = "version", text = "Version" },
    } },
    { text = "no id" },
}
local copied = KS.copyItems(src, {}, true)
check(texts(copied[4] and copied[4].sub_item_table) == "|Quickstart guide|Version|",
    "Help: no KOReader bug report, no Disable external plugins " .. texts(copied[4] and copied[4].sub_item_table))
check(texts(copied) == "|Wi-Fi connection|More tools|HTTP proxy|Help|no id|",
    "KOReader section: clashing items left out " .. texts(copied))
check(texts(copied[2].sub_item_table) == "|Advanced settings|", "and inside submenus " .. texts(copied[2].sub_item_table))
local n_keep = select(2, read("modules/menu/app_launcher/native_menu.lua"):gsub("keepKOReaderItem", ""))
check(n_keep == 2, "the KOReader section's top menus (File browser) are filtered too")
check(read("modules/menu/app_launcher/native_menu.lua"):find("keepKOReaderItem", 1, true) ~= nil,
    "the KOReader menu picker (bottom swipe → KOReader menu) leaves them out too")

-- the KOReader section without what GZreader has elsewhere (KOREADER_DUPLICATES)
;(function()
    local GzS = require("common/gz_settings")
    for _i, id in ipairs({ "language", "time", "screensaver", "autosuspend", "network_wifi", "history", "favorites",
            "collections", "document_end_action", "night_mode", "screen_rotation", "exit_menu", "version", "about",
            "quickstart_guide", "cloud_storage" }) do
        check(GzS.KOREADER_DUPLICATES[id] == true and not GzS.KOREADER_HIDDEN[id], "KOReader section: " .. id .. " left out there only")
    end
    local refreshed = 0
    local section = {
        { id = "night_mode", text = "Night mode" },
        { id = "network", text = "Network", sub_item_table = {
            { id = "network_wifi", text = "Wi-Fi connection" }, { id = "network_info", text = "Network info" } } },
        { id = "device", text = "Device", sub_item_table_func = function() return {
            { id = "time", text = "Time and date" }, { id = "keyboard_layout", text = "Keyboard" },
            { id = "autosuspend", text = "Autosuspend timeout" } } end },
        { id = "main", text = "Main menu", sub_item_table = {
            { id = "history", text = "History" }, { id = "bookmark_browser", text = "Bookmark browser" },
            { id = "help", text = "Help", sub_item_table = { { id = "quickstart_guide", text = "Quickstart guide" },
                { id = "search_menu", text = "Menu search" }, { id = "version", text = "Version" }, { id = "about", text = "About" } } },
            { id = "exit_menu", text = "Exit", sub_item_table = { { id = "restart_koreader", text = "Restart" } } } } },
        { text = "no id" },
    }
    section._zen_refresh = function() refreshed = refreshed + 1; return { { id = "language", text = "Language" }, { id = "units", text = "Units" } } end
    local out = GzS.dropKOReaderDuplicates(section)
    check(texts(out) == "|Network|Device|Main menu|no id|", "KOReader section: Night mode left out " .. texts(out))
    check(texts(out[1].sub_item_table) == "|Network info|", "…and Wi-Fi connection inside Network")
    check(texts(out[2].sub_item_table_func()) == "|Keyboard|", "…and Time and date, Autosuspend inside a built-later submenu")
    check(texts(out[3].sub_item_table) == "|Bookmark browser|Help|", "…History and Exit (Restart, Sleep, Exit) from Main menu")
    check(texts(out[3].sub_item_table[2].sub_item_table) == "|Menu search|", "…Quickstart guide, Version, About from Help")
    check(texts(out._zen_refresh()) == "|Units|" and refreshed == 1, "…and again after the page refreshes")
    check(GzS.dropKOReaderDuplicates(nil) == nil, "nil: nil")
    local nm = read("modules/menu/app_launcher/native_menu.lua")
    check(nm:find('dropKOReaderDuplicates(\n                        Settings.copyItems(children, menu, setting))', 1, true) ~= nil
        and select(2, nm:gsub("dropKOReaderDuplicates", "")) == 1,
        "only the KOReader section drops them (not settingsItems(scope, id): End of book's End of document action)")
    check(read("modules/settings/sections/end_book_settings.lua"):find('settingsItems("active", "document_end_action")', 1, true) ~= nil,
        "End of book still takes End of document action by its id")
end)()

-- navbar tabs
local GS = require("common/gz_settings")
local kept = GS.dropHiddenTabs({ { id = "books" }, { id = "manga" }, "news", { id = "calibre_search" }, "home", { id = "folder" } })
check(#kept == 3 and kept[1].id == "books" and kept[2] == "home" and kept[3].id == "folder", "Manga, News, Calibre Search tabs dropped")
local nav_settings = read("modules/settings/sections/library_settings/navbar_settings.lua")
local n_drop = select(2, nav_settings:gsub("dropHiddenTabs", ""))
check(n_drop == 2, "Settings → Navbar: not in Tabs nor Default tab")
check(read("modules/filebrowser/patches/navbar.lua"):find("gz_settings\").HIDDEN_TABS[tab_id]", 1, true) ~= nil,
    "the bar leaves them out even when saved as on")
do
    local nav = read("modules/filebrowser/patches/navbar.lua")
    local fn = nav:match("local function showCurrentDirMenu%(fc%)(.-)\n        end\n")
    check(fn and fn:find("_is_current_dir = true", 1, true) ~= nil,
        "keyboard Kindles: holding Press on the tab bar opens the menu with Filter (KOReader's File browser is hidden)")
end
check(read("config/manager.lua"):find("gz_debug_logging_off", 1, true) ~= nil,
    "KOReader's verbose log turned off once (no switch for it any more)")

-- every Settings row has an icon (its own, or gz_settings_icons')
local Icons = require("common/gz_settings_icons")
local map = require("common/inline_icon_map")
local missing = {}
for _i, r in ipairs(Icons.RULES) do if not map[r[2]] then missing[#missing + 1] = r[2] end end
for _k, v in pairs(Icons.KIND) do if not map[v] then missing[#missing + 1] = v end end
check(#missing == 0, "every icon the rules name exists " .. table.concat(missing, ","))
check(Icons.keyFor({ text = "RAM usage" }) == "settings_ram" and Icons.keyFor({ text = "Program", callback = print }) == "go",
    "words match at their start (RAM, not pRogRAM)")
check(Icons.keyFor({ text = "Wi-Fi only when needed" }) == "wifi_on" and Icons.keyFor({ text = "Keyword" }) == "keywords",
    "Wi-Fi, keywords")
check(Icons.keyFor({ text = "Zzz", sub_item_table = {} }) == "settings" and Icons.keyFor({ text = "Zzz", radio = true }) == "select"
    and Icons.keyFor({ text = "Zzz", checked_func = print }) == "check" and Icons.keyFor({ text = "Zzz" }) == "details",
    "otherwise by kind: submenu, choice, switch, information")
check(Icons.glyphFor({ text = "Font", icon_glyph = "x" }) == nil, "a row's own icon is kept")
if okb then
    local rows, without = 0, {}
    local function walk(list, depth, seen)
        if depth > 4 or type(list) ~= "table" or seen[list] then return end
        seen[list] = true
        for _i, it in ipairs(list) do
            if type(it) == "table" and getmetatable(it) == nil then
                rows = rows + 1
                if not (rawget(it, "icon_glyph") or rawget(it, "icon_file") or rawget(it, "icon_name") or Icons.glyphFor(it)) then
                    without[#without + 1] = text(it)
                end
                -- (built submenus only: some _func ones loop on the stubs; the
                -- emulator's settings_cleanup.lua checks the rest on a device)
                walk(rawget(it, "sub_item_table"), depth + 1, seen)
            end
        end
    end
    walk(root.sub_item_table, 0, {})
    check(rows > 50 and #without == 0, "all " .. rows .. " Settings rows built here have an icon " .. table.concat(without, ","))
end
check(read("common/ui/icon_menu_item.lua"):find("gz_settings_icons\").glyphFor(item)", 1, true) ~= nil,
    "Settings rows draw it")

-- Sleep: no Presets; Wallpaper is tiles; no Custom images
check(read("modules/settings/sections/global_settings.lua"):find("sub_item_table_func = _build_preset_items", 1, true) == nil,
    "General → Sleep: no Presets")
local ss = io.open(ZEN .. "/../../frontend/ui/elements/screensaver_menu.lua"):read("*a")
check(not ss:find('_("Custom images")', 1, true), "Wallpaper options: no Custom images")
check(ss:find('require, "gzreader_sleeppreview"', 1, true) and ss:find('_("Wallpaper options")', 1, true),
    "Wallpaper opens the tiles; the rest is in Wallpaper options")
check(not ss:find('"document_cover", nil, nil', 1, true), "no custom image choice")

if PLUGIN then
    local store = {}
    G_reader_settings = {
        readSetting = function(_s, k) return store[k] end,
        saveSetting = function(_s, k, v) store[k] = v end,
        nilOrTrue = function(_s, k) return store[k] == nil or store[k] == true end,
        makeTrue = function(_s, k) store[k] = true end,
        makeFalse = function(_s, k) store[k] = false end,
    }
    stubs["libs/libkoreader-lfs"] = { attributes = function() return nil end, dir = function() return function() end end }
    stubs.device = { screen = { scaleBySize = function(_s, n) return n end, getWidth = function() return 600 end,
        getHeight = function() return 800 end }, hasKeyboard = function() return true end,
        isKindle = function() return true end, hasDPad = function() return true end }
    package.loaded.device = nil
    local okp, P = pcall(require, "gzreader_sleeppreview")
    check(okp and type(P) == "table", "the Wallpaper tiles load " .. tostring(not okp and P or ""))
    if okp then
        local ids = {}
        for _i, c in ipairs(P.choices()) do ids[#ids + 1] = c.id end
        check(table.concat(ids, ",") == "auto,cover,random_image,readingprogress,bookstatus,disable",
            "six tiles: GZreader's, cover, picture, progress, status, as it is " .. table.concat(ids, ","))
        check(P.current() == "auto", "GZreader's own is in use at first")
        P.choose("cover")
        check(P.current() == "cover" and store.screensaver_type == "cover" and store.gzreader_sleep_auto == false,
            "choosing Book cover saves it and turns GZreader's own off")
        P.choose("auto")
        check(P.current() == "auto" and store.gzreader_sleep_auto == true, "choosing GZreader's own again")
        for _i, size in ipairs({ { 600, 800 }, { 824, 1200 }, { 1072, 1448 }, { 758, 1024 } }) do
            local L = P.layoutFor(size[1], size[2], 6)
            local bottom = L.top + L.rows * L.th + (L.rows - 1) * L.gap
            check(L.tw > 0 and L.ph > L.tw and bottom <= size[2] - 30 and L.cols * L.tw + (L.cols - 1) * L.gap <= size[1],
                ("tiles fit a %d × %d screen (%d × %d pictures)"):format(size[1], size[2], L.tw, L.ph))
        end
    end
end

print("Wi-Fi in the status bars: the auto mark")
do
    local WI = require("common/gz_wifi_icon")
    local net = { mode = function() return "auto" end }
    package.loaded["gzreader_net"] = net
    check(WI.mark() == "A", "Auto: \"A\" after the Wi-Fi icon")
    net.mode = function() return "on" end
    check(WI.mark() == nil, "On: the icon alone")
    net.mode = function() return "off" end
    check(WI.mark() == nil, "Off: the icon alone")
    net.mode, net.usb = function() return "auto" end, true
    check(WI.mark() == nil, "a Kindle without Wi-Fi: no mark")
    net.usb, net.mode = nil, function() error("broken") end
    check(WI.mark() == nil, "GZreader's mode can't be read: no mark, no error")
    package.loaded["gzreader_net"] = nil
    for _i, f in ipairs({ "modules/filebrowser/patches/status_bar.lua", "modules/reader/patches/reader_top_status_bar.lua" }) do
        local src = read(f)
        local body = src:match("local function getWifi%a+%(%)(.-)\n    end\n")
        local _n, marks = (body or ""):gsub("inline_icons%.wifi_o[nf]f?, gz_mark,", "")
        check(body and body:find('local gz_mark = require("common/gz_wifi_icon").mark()', 1, true) and marks == 3,
            f .. ": the Wi-Fi item carries the auto mark (searching, on, off)")
    end
end

-- Wallpaper options → Scale cover to fill screen (frontend/gzsleepfit.lua)
do
    local FRONT = ZEN .. "/../../frontend"
    package.path = FRONT .. "/?.lua;" .. package.path
    real.gzsleepfit = true
    package.loaded.gzsleepfit, package.loaded.device = nil, nil
    stubs.device = setmetatable({ isTouchDevice = function() return true end }, { __index = function() return function() end end })
    local Fit = require("gzsleepfit")
    local function covers(iw, ih, w, h, angle)
        local f = Fit.factor(iw, ih, w, h, angle)
        if angle and angle % 180 ~= 0 then iw, ih = ih, iw end
        local sw, sh = math.floor(iw * f), math.floor(ih * f)
        -- covers the screen, and overflows on one side only (no stretching)
        return sw >= w and sh >= h and (sw <= w + 1 or sh <= h + 1), f
    end
    local okc, f = covers(600, 900, 600, 800)
    check(okc and math.abs(f - 1) < 1e-3, "fill: a tall cover keeps its width, top and bottom cut off")
    okc, f = covers(1200, 600, 600, 800)
    check(okc and math.abs(f - 800 / 600) < 1e-3, "fill: a wide picture is scaled to the height, sides cut off")
    okc, f = covers(300, 400, 824, 1200)
    check(okc and f > 2.9, "fill: a small cover is scaled up")
    check((covers(1200, 600, 600, 800, 90)) and math.abs(Fit.factor(1200, 600, 600, 800, 90) - 1) < 1e-3
        and math.abs(Fit.factor(1200, 600, 600, 800, -90) - 1) < 1e-3, "fill: a turned picture uses its turned size")
    check(Fit.factor(nil, 600, 600, 800) == 0 and Fit.factor(0, 600, 600, 800) == 0,
        "fill: an unknown size falls back to best fit")
    local all = true
    for iw = 97, 1500, 37 do for ih = 113, 1600, 41 do
        for _i, s in ipairs({ { 600, 800 }, { 824, 1200 }, { 1072, 1448 }, { 758, 1024 }, { 1200, 824 } }) do
            if not covers(iw, ih, s[1], s[2]) then all = false end
        end
    end end
    check(all, "fill: never a bar left at the edge, at any cover size on any Kindle screen")

    local store = { screensaver_stretch_images = true }
    G_reader_settings = {
        readSetting = function(_s, k) return store[k] end,
        isTrue = function(_s, k) return store[k] == true end,
        nilOrTrue = function(_s, k) return store[k] == nil or store[k] == true end,
        makeFalse = function(_s, k) store[k] = false end,
        makeTrue = function(_s, k) store[k] = true end,
        flipNilOrFalse = function(_s, k) if store[k] then store[k] = nil else store[k] = true end end,
        saveSetting = function(_s, k, v) store[k] = v end,
    }
    local okm, menu = pcall(dofile, FRONT .. "/ui/elements/screensaver_menu.lua")
    check(okm and type(menu) == "table", "the Sleep menu loads " .. tostring(not okm and menu or ""))
    local opts = okm and find(menu, "Wallpaper options")
    local border = opts and find(opts.sub_item_table, "Border fill, rotation, and fit")
    local fill = border and find(border.sub_item_table, "Scale cover to fill screen")
    check(fill and true or false, "Border fill, rotation, and fit has Scale cover to fill screen "
        .. texts(border and border.sub_item_table))
    check(opts and not find(opts.sub_item_table, "Scale cover to fill screen"),
        "Scale cover to fill screen isn't also in Wallpaper options itself")
    if fill then
        local stretch, at = nil, {}
        for i, it in ipairs(border.sub_item_table) do
            if rawget(it, "text_func") and text(it):find("Stretch") then stretch, at.stretch = it, i end
            if it == fill then at.fill = i end
            if rawget(it, "text") == "Rotate cover for best fit" then at.rotate = i end
        end
        check(at.stretch and at.fill and at.rotate and at.stretch < at.fill and at.fill < at.rotate,
            "between Stretch cover to fit screen and Rotate cover for best fit")
        check(border.enabled_func() and not fill.checked_func() and stretch and stretch.enabled_func(),
            "off at first; offered with GZreader's sleep screen; Stretch still offered")
        fill.callback()
        check(store[Fit.SETTING] == true and fill.checked_func() and store.screensaver_stretch_images == false
            and not stretch.enabled_func(), "ticking it turns Stretch off and greys it out")
        fill.callback()
        check(store[Fit.SETTING] == nil and not fill.checked_func() and stretch.enabled_func(), "unticking it")
        store.gzreader_sleep_auto, store.screensaver_type = false, "bookstatus"
        check(not border.enabled_func(), "greyed out (with its submenu) when the sleep screen shows no picture")
    end
    local ss_src = io.open(FRONT .. "/ui/screensaver.lua"):read("*a")
    check(ss_src:find('isTrue("screensaver_rotate_auto_for_best_fit") or gz_fill then', 1, true)
        and ss_src:find('require("gzsleepfit").factor(widget_settings.image:getWidth()', 1, true)
        and ss_src:find("screen_w, screen_h, widget_settings.rotation_angle)", 1, true),
        "the sleep screen loads the picture to know its size and scales it to fill")
end

-- Wallpaper → "Book cover while reading, a picture elsewhere" whatever was
-- chosen before it (frontend/gzsleepmode.lua). A saved screensaver_type used
-- to override it: a picture while reading, or the cover at Home after
-- Book cover was chosen once and GZreader's own again.
do
    local FRONT = ZEN .. "/../../frontend"
    real.gzsleepmode = true
    package.loaded.gzsleepmode = nil
    local Mode = require("gzsleepmode")
    local store = {}
    G_reader_settings = {
        readSetting = function(_s, k) return store[k] end,
        saveSetting = function(_s, k, v) store[k] = v end,
        has = function(_s, k) return store[k] ~= nil end,
        nilOrTrue = function(_s, k) return store[k] == nil or store[k] == true end,
        makeTrue = function(_s, k) store[k] = true end,
        makeFalse = function(_s, k) store[k] = false end,
    }
    local S = G_reader_settings
    store.screensaver_type = "disable" -- (screensaver.lua's first-start default)
    check(Mode.type(S, "", true) == "cover" and Mode.type(S, "", false) == "random_image",
        "GZreader's own at first: the cover while reading, a picture at Home")
    store.screensaver_type = "random_image"
    check(Mode.type(S, "", true) == "cover", "a saved picture choice doesn't show while reading")
    store.screensaver_type = "cover"
    check(Mode.type(S, "", false) == "random_image", "a saved Book cover choice doesn't show at Home")
    store.gzreader_sleep_auto = false
    check(Mode.type(S, "", false) == "cover" and Mode.type(S, "", true) == "cover", "Book cover chosen: the cover everywhere")
    store.screensaver_type = "random_image"
    check(Mode.type(S, "", true) == "random_image", "a picture chosen: a picture while reading too")
    store.gzreader_sleep_auto, store.poweroff_screensaver_type = nil, "message"
    check(Mode.type(S, "poweroff_", false) == "message" and Mode.type(S, "reboot_", false) == "random_image",
        "KOReader's own power-off type still comes first; reboot without one: GZreader's")
    store.poweroff_screensaver_type = nil
    if PLUGIN then
        local okp, P = pcall(require, "gzreader_sleeppreview")
        if okp then
            store.gzreader_sleep_auto, store.screensaver_type = nil, "random_image"
            P.choose("cover"); P.choose("auto")
            check(P.current() == "auto" and Mode.type(S, "", false) == "random_image" and Mode.type(S, "", true) == "cover",
                "tiles: Book cover, then GZreader's own again: a picture at Home, the cover while reading")
            P.choose("random_image"); P.choose("auto")
            check(Mode.type(S, "", true) == "cover" and Mode.type(S, "", false) == "random_image",
                "tiles: a picture, then GZreader's own again: the cover while reading")
        end
    end
    local src = io.open(FRONT .. "/ui/screensaver.lua"):read("*a")
    local setup = src:match("function Screensaver:setup%(.-\nend\n") or ""
    local at = setup:find('require("gzsleepmode").type(G_reader_settings, self.prefix, self.ui.document ~= nil)', 1, true)
    local prefix_at = setup:find('self.prefix = event and event .. "_" or ""', 1, true)
    check(at and prefix_at and prefix_at < at and not setup:find("self.screensaver_type = G_reader_settings:readSetting", 1, true),
        "the sleep screen asks gzsleepmode once the prefix is known, and nothing reads the saved type over it")
end

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
