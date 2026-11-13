-- Settings → Downloads → Books → Double-tap to open a book: only on a touch
-- screen (the Kindle 2, 3, DX and 4 have nothing to tap). ZenOS's Downloads
-- section (library_settings) is real; the rest are stubs.
--   luajit settings_doubletap_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local function magic()
    local m
    m = setmetatable({}, { __index = function() return m end, __call = function() return m end,
        __concat = function() return "" end, __tostring = function() return "" end })
    return m
end
local real = {
    ["modules/settings/sections/library_settings"] = true,
    ["modules/settings/sections/library_settings/metadata_settings"] = true,
    ["modules/settings/zen_settings_utils"] = true,
}
local touch = true
local stubs = {
    gettext = function(s) return s end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item) return item end },
    ["common/plugin_root"] = "",
    ["common/gz_view"] = { isBookshelf = function() return true end },
    device = { isTouchDevice = function() return touch end },
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
        t[#t + 1] = type(s) == "string" and s or "?"
    end
    return "|" .. table.concat(t, "|") .. "|"
end
local function sub(list, name)
    for _i, it in ipairs(list or {}) do
        if rawget(it, "text") == name then return rawget(it, "sub_item_table") end
    end
end

local config = { features = {}, lockdown = {}, custom_icons = { active_pack = "" }, navbar = { show_tabs = {} }, _meta = {},
    developer = {} }
local plugin = { config = config, saveConfig = function() end }
local ctx = { plugin = plugin, config = config, save_and_apply = function() end, apply_feature = function() end,
    settings_apply = magic() }
local Lib = require("modules/settings/sections/library_settings")

local function books()
    local okb, items = pcall(Lib.build, ctx)
    check(okb and type(items) == "table", "Downloads builds " .. tostring(not okb and items or ""))
    return okb and sub(items, "Books") or {}
end

touch = true
local b = books()
print("    Books (touch): " .. texts(b))
-- (ZenOS 4.3.2: "Double-tap to open a book" became "Double tap", with what a single and a double tap do under it)
check(texts(b):find("|Double tap|", 1, true) ~= nil, "a touch Kindle: Double tap is there")
local dt
for _i, it in ipairs(b) do if it.text == "Double tap" then dt = it end end
if dt then
    dt.callback()
    check(config.developer.double_tap == true and dt.checked_func(), "…and still turns ZenOS's setting on")
    dt.callback()
    check(config.developer.double_tap == false, "…and off")
    check(texts(dt.sub_item_table) == "|Single tap|Double tap|", "…with Single tap and Double tap under it: " .. texts(dt.sub_item_table))
end

touch = false
b = books()
print("    Books (keys): " .. texts(b))
check(not texts(b):find("|Double tap|", 1, true), "a Kindle with keys or a 5-way: no Double tap")
for _i, kept in ipairs({ "Book details", "Include new books in TBR", "Treat file updates as New", "Show all files from subfolders" }) do
    check(texts(b):find("|" .. kept .. "|", 1, true) ~= nil, "…the rest of Books stays: " .. kept)
end

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
