-- ZenOS's Settings page as GZreader builds it: its top-level sections, and
-- what General and Interface take from the (hidden) Extras items.
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
    check(top == "|General|Home|Reader|Interface|Connections|About|",
        "Settings: General first, then Home, Reader, Interface, Connections, About; no Extras, no KOReader (About → Advanced has it), no Downloads (in Home) " .. top)
    -- Home: its own rows, then the Downloads tab's (ZenOS's Library section: Appearance, Folders, Books, Context menu)
    local dl = sub(items, "Home")
    print("    Home: " .. texts(dl))
    local hrows = texts(dl)
    check(hrows:find("|Appearance|Folders|Books|Context menu|$") ~= nil and not hrows:find("^|Appearance|"),
        "Home: Home's own rows first, then the Downloads tab's Appearance, Folders, Books, Context menu " .. hrows)
    for i, it in ipairs(dl or {}) do
        if rawget(it, "text") == "Appearance" then
            check(dl[i - 1] and dl[i - 1].separator == true, "a line between Home's rows and the Downloads tab's")
        end
    end
    local books = texts(sub(dl, "Books"))
    check(books:find("|", 2, true) and not books:find("|Metadata|", 1, true),
        "Home → Books: no Metadata menu (details come from Grimmory) " .. books)
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
    local gen = texts(sub(items, "General"))
    check(gen:find("|Schedules|", 1, true) and gen:find("|Sleep|", 1, true),
        "General still has Schedules and Sleep (built with the Extras items) " .. gen)
    local interface = sub(items, "Interface")
    local ui = texts(interface)
    check(ui:find("|Custom icons|", 1, true), "Interface still has Custom icons " .. ui)
    local all = top .. gen .. ui
    for _i, gone in ipairs({ "Extras", "Stats", "Zen Search", "Lockdown mode", "Zen Keyboard" }) do
        check(not all:find("|" .. gone .. "|", 1, true), "not in Settings: " .. gone)
    end
end

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
