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
}
local stubs = {
    gettext = function(s) return s end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item) return item end },
    ["common/plugin_root"] = "",
    -- no ZenPM, no Rakuyomi on a Kindle with GZreader
    ["modules/settings/zenpm_installer"] = { build_item = function() return nil end },
    ["modules/filebrowser/patches/rakuyomi"] = { is_available = function() return false end },
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
    check(top == "|Home|Library|Reader|Interface|General|Storage|Connections|KOReader|About|",
        "Settings: Home, Library, Reader, Interface, General, Storage, Connections, KOReader, About; no Extras " .. top)
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
