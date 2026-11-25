-- ZenOS's Settings page as GZreader builds it (common/gz_settings_tree.lua):
-- its first page, Home and tabs (Home's rows, the Downloads tab's), Dark
-- mode, what General and Display and light take from the (hidden) Extras
-- items, and Accounts and services.
-- ZenOS's settings modules are real; KOReader and the rest of ZenOS are stubs.
--   luajit zen_settings_test.lua <plugins/zenos.koplugin>
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
    ["common/gz_settings_tree"] = true,
    ["common/gz_settings"] = true,
    ["modules/settings/sections/extras_settings"] = true,
    ["modules/settings/sections/global_settings"] = true,
    ["modules/settings/sections/general_settings"] = true,
    ["modules/settings/sections/interface_settings"] = true,
    ["modules/settings/zen_settings_utils"] = true,
    ["modules/settings/sections/library_settings"] = true,
    ["modules/settings/sections/library_settings/metadata_settings"] = true,
}
local view = { bookshelf = true }
local stubs = {
    gettext = function(s) return s end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item) return item end },
    ["common/plugin_root"] = "",
    -- ZenOS's Home section (its rows; the Downloads tab's come after them in Settings)
    ["modules/settings/sections/library_settings/home_settings"] = { build = function()
        return { text = "Home", sub_item_table = { { text = "Widgets ▸" }, { text = "Edit mode" }, { text = "Presets" }, { text = "Show top status bar" } } }
    end },
    -- no ZenPM, no Rakuyomi on a Kindle with GZreader
    ["modules/settings/zenpm_installer"] = { build_item = function() return nil end },
    ["modules/filebrowser/patches/rakuyomi"] = { is_available = function() return false end },
    ["common/gz_view"] = { isBookshelf = function() return view.bookshelf end },
    -- the Kindles without Wi-Fi (2, DX): no Home Assistant in Connections
    ["gzreader_usbsync"] = { noWifi = function() return view.no_wifi == true end },
}
table.insert(package.loaders, 2, function(name)
    if stubs[name] ~= nil then local v = stubs[name]; return function() return v end end
    if real[name] then return nil end
    return function() return magic() end
end)
G_reader_settings = setmetatable({}, { __index = function() return function() end end })

local ok_count, fail = 0, 0
local function check(c, n) if c then ok_count = ok_count + 1 print("  ok   " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

local function texts(list)
    local t = {}
    for _i, it in ipairs(type(list) == "table" and list or {}) do
        local s = rawget(it, "text")
        if s == nil and type(rawget(it, "text_func")) == "function" then
            local okf, v = pcall(it.text_func); s = okf and v or nil
        end
        t[#t + 1] = type(s) == "string" and s or "?"
    end
    return "|" .. table.concat(t, "|") .. "|"
end
local function sub(list, name)
    for _i, it in ipairs(list or {}) do
        if rawget(it, "text") == name then return rawget(it, "sub_item_table") end
    end
end

local config = { features = {}, lockdown = {}, custom_icons = { active_pack = "" }, navbar = { show_tabs = {} }, _meta = {} }
local plugin = { config = config, saveConfig = function() end }
local okb, root = pcall(require("modules/settings/zen_settings").build, plugin)
check(okb and type(root) == "table", "ZenOS's settings build " .. tostring(not okb and root or ""))
if okb then
    local items = root.sub_item_table
    local top = texts(items)
    -- (stubs here: Reader, About and Status bar's modules)
    check(top:find("^|Wi%-Fi|Bluetooth|General|Display and light|Sleep and wallpaper|Home and tabs|") ~= nil
            and top:find("|Accounts and services|Privacy and diagnostics|$") ~= nil and #items <= 9,
        "Settings: Wi-Fi and Bluetooth first, then General, Display and light, Sleep and wallpaper, Home and tabs, …, Accounts and services, Privacy and diagnostics (nine rows at most); no Extras, no KOReader, no Downloads, no Interface " .. top)
    for _i, gone in ipairs({ "Interface", "Connections", "Downloads", "Home", "About" }) do
        check(not top:find("|" .. gone .. "|", 1, true), "not on the first page: " .. gone)
    end
    -- Home and tabs: Home (its own rows), Status bar, Tab bar, Quick panel, Downloads tab
    local ht = sub(items, "Home and tabs")
    local htt = texts(ht)
    check(htt == "|Home|Tab bar|Downloads tab|", "Home and tabs: Home, (Status bar, Quick panel: stubs here,) Tab bar, Downloads tab " .. htt)
    local home_rows = texts(sub(ht, "Home"))
    check(home_rows == "|Widgets ▸|Edit mode|Presets|Show on Home|",
        "Home: its own rows; with no Status bar section, Show top status bar stays in Home as Show on Home " .. home_rows)
    -- with a Status bar section: Show on Home is its first row
    local Tree = require("common/gz_settings_tree")
    local t = Tree.build({
        home = { text = "Home", sub_item_table = { { text = "Widgets" }, { text = "Show top status bar", separator = true } } },
        interface = { { text = "Status bar", sub_item_table = { { text = "Bold text" } } }, { text = "Navbar", sub_item_table = {} },
            { text = "Quick panel", sub_item_table = {} }, { text = "Font" }, { text = "Blur menu background" } },
        general = { { text = "Updates", sub_item_table = {} } }, about = {}, reader = {}, library = { { text = "Appearance" } },
    })
    local tht = sub(t, "Home and tabs")
    check(texts(tht) == "|Home|Status bar|Tab bar|Quick panel|Downloads tab|", "Home and tabs: Home, Status bar, Tab bar, Quick panel, Downloads tab " .. texts(tht))
    local srows = sub(tht, "Status bar")
    check(texts(srows) == "|Show on Home|Bold text|" and srows[1].separator == true and texts(sub(tht, "Home")) == "|Widgets|"
            and not sub(tht, "Home")[1].separator,
        "Status bar: Show on Home (Home's Show top status bar) first, then a line; Home keeps its own rows " .. texts(srows))
    check(texts(sub(t, "Display and light")) == "|Font|Blur menu background|", "Display and light: Interface's other rows, Font first " .. texts(sub(t, "Display and light")))
    check(texts(t):find("|Wi-Fi|", 1, true) == nil and texts(sub(t, "General")) == "|Software update|Transfer|",
        "nothing to move: no empty rows, sections or Wi-Fi " .. texts(t) .. texts(sub(t, "General")))
    local dl = sub(ht, "Downloads tab")
    print("    Downloads tab: " .. texts(dl))
    check(texts(dl) == "|Appearance|Folders|Books|Context menu|", "Downloads tab: Appearance, Folders, Books, Context menu " .. texts(dl))
    local books = texts(sub(dl, "Books"))
    check(books:find("|", 2, true) and not books:find("|Metadata|", 1, true),
        "Downloads tab → Books: no Metadata menu (details come from Grimmory) " .. books)
    -- Appearance → Covers → Rounded cover corners: off in the Bookshelf view
    local covers = sub(sub(dl, "Appearance"), "Covers")
    local rounded
    for _i, it in ipairs(covers or {}) do
        if rawget(it, "text") == "Rounded cover corners" then rounded = it end
    end
    check(rounded and type(rounded.enabled_func) == "function", "Covers: Rounded cover corners has an enabled_func")
    if rounded and rounded.enabled_func then
        view.bookshelf = true
        check(rounded.enabled_func() == false, "Rounded cover corners: greyed out in the Bookshelf view")
        view.bookshelf = false
        check(rounded.enabled_func() == true, "Rounded cover corners: can be changed in the other views")
    end
    local display = sub(items, "Display and light")
    local disp = texts(display)
    print("    Display and light: " .. disp)
    local bw = texts(sub(display, "Brightness and warmth"))
    check(bw == "|Brightness|Warmth|", "Brightness and warmth: Extras' Schedules without Night mode schedule " .. bw)
    local dark = texts(sub(display, "Dark mode"))
    check(dark == "|Night mode schedule|Reader themes|?|Invert the Home background|Invert custom icons|"
            or dark == "|Night mode schedule|Night mode accent: |Invert the Home background|Invert custom icons|"
            or dark:find("^|Night mode schedule|") ~= nil and dark:find("|Invert the Home background|Invert custom icons|$") ~= nil,
        "Dark mode: Night mode schedule, (Reader themes,) Night mode accent, the two Invert with dark mode ticks " .. dark)
    local accent_rows = texts(sub(display, "Accent color"))
    check(not accent_rows:find("Night mode accent", 1, true), "Accent color: no Night mode accent (in Dark mode) " .. accent_rows)
    local custom = sub(display, "Custom icons")
    check(custom ~= nil and not texts(custom):find("Invert", 1, true), "Custom icons: no Invert with dark mode (in Dark mode)")
    local sw = sub(items, "Sleep and wallpaper")
    check(texts(sw):find("^|Sleep|Home background|") ~= nil, "Sleep and wallpaper: Sleep, Home background (Interface's Wallpaper) " .. texts(sw))
    check(not texts(sub(sw, "Home background")):find("Invert", 1, true), "Home background: no Invert with dark mode (in Dark mode)")
    local gen = texts(sub(items, "General"))
    check(not gen:find("|Schedules|", 1, true) and not gen:find("|Sleep|", 1, true),
        "General: no Schedules or Sleep (Display and light, Sleep and wallpaper) " .. gen)
    local ui = disp
    check(ui:find("|Custom icons|", 1, true), "Display and light has Custom icons " .. ui)
    local all = top .. gen .. ui
    for _i, gone in ipairs({ "Extras", "Stats", "Zen Search", "Lockdown mode", "Zen Keyboard" }) do
        check(not all:find("|" .. gone .. "|", 1, true), "not in Settings: " .. gone)
    end
end

-- Connections: Home Assistant (the House tab), before Copy; not without Wi-Fi
do
    local function accounts()
        local okc, r = pcall(require("modules/settings/zen_settings").build, plugin)
        for _i, it in ipairs(okc and r.sub_item_table or {}) do
            if rawget(it, "_zen_settings_root") == "accounts" then return texts(it.sub_item_table) end
        end
        return ""
    end
    view.no_wifi = false
    local con = accounts()
    check(con:find("|Photos|House|Daily paper|AI|$") ~= nil, "Accounts and services: House (Home Assistant), the daily paper, then AI, last " .. con)
    check(not con:find("Copy to or from another GZreader", 1, true) and not con:find("Sync through a computer", 1, true),
        "Accounts and services: no Copy or Sync through a computer (General → Transfer) " .. con)
    view.no_wifi = true
    con = accounts()
    check(con ~= "" and not con:find("House", 1, true) and not con:find("|AI|", 1, true), "Accounts and services: no House and no AI on a Kindle without Wi-Fi " .. con)
    view.no_wifi = false
end

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
