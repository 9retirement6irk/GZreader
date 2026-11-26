-- Settings → Audio: GZreader's read aloud, audiobook test and headphone
-- settings (they come with its Reader items) in their own section on the
-- first page, after Sleep and wallpaper; anything else of GZreader's for
-- Reader stays at the end of Reader. ZenOS's settings modules are real; the rest
-- are stubs.
--   luajit settings_audio_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
-- (the tree as gz_settings_tree.lua builds it: what Settings makes of it afterwards is gz_settings_tidy_test.lua's)
package.loaded["common/gz_settings_tidy"] = { apply = function(root) return root end }
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
    ["common/gz_settings"] = true,
    ["common/gz_settings_tree"] = true,
}
-- what GZreader's plugin gives Settings (main.lua Grimmory:sectionItems)
local reader_items
local gz = {
    sectionItems = function(_self, section)
        if section == "reader" then return reader_items end
        return {}
    end,
}
local stubs = {
    gettext = function(s) return s end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item) return item end },
    ["common/plugin_root"] = "",
    ["common/utils"] = { resolveLocalIcon = function(dir, name) return dir .. name .. ".svg" end },
    ["modules/settings/zenpm_installer"] = { build_item = function() return nil end },
    ["modules/filebrowser/patches/rakuyomi"] = { is_available = function() return false end },
    ["apps/reader/readerui"] = {},
    ["apps/filemanager/filemanager"] = { instance = { gzreader = gz } },
    ["ui/language"] = { getLangMenuTable = function() return { text = "Language", sub_item_table = {} } end },
    ["ui/elements/common_settings_menu_table"] = { time = { text = "Time and date", sub_item_table = {} } },
    ["gzreader_timezone"] = { label = function() return "UTC" end, menuItems = function() return {} end },
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

local GzS = require("common/gz_settings")
local function items(...)
    local t = {}
    for _i, name in ipairs({ ... }) do t[#t + 1] = { text = name, callback = function() end } end
    return t
end

-- the splitter
local audio, rest = GzS.splitAudio(items("Read aloud", "Lay out new books while charging", "Test audiobook playback",
    "Pause when headphones are unplugged", "Find the headphone jack"))
check(texts(audio) == "|Read aloud|Test audiobook playback|Pause when headphones are unplugged|Find the headphone jack|",
    "splitAudio: the four audio items, in their order " .. texts(audio))
check(texts(rest) == "|Lay out new books while charging|", "…and the rest " .. texts(rest))
audio, rest = GzS.splitAudio(nil)
check(#audio == 0 and #rest == 0, "splitAudio(nil): nothing")

local config = { features = {}, lockdown = {}, custom_icons = { active_pack = "" }, navbar = { show_tabs = {} }, _meta = {} }
local plugin = { config = config, saveConfig = function() end }
local function build(list)
    reader_items = list
    local okb, root = pcall(require("modules/settings/zen_settings").build, plugin)
    check(okb and type(root) == "table", "Settings build " .. tostring(not okb and root or ""))
    return okb and root.sub_item_table or {}
end

-- a Kindle 3 / Touch (a speaker): the four audio items, plus one more of GZreader's Reader items
local root = build(items("Read aloud", "Test audiobook playback", "Pause when headphones are unplugged",
    "Find the headphone jack", "Something else"))
print("    Settings: " .. texts(root))
check(texts(root):find("|Sleep and wallpaper|Audio|", 1, true) ~= nil and find(root, "Audio").separator == true
        and find(root, "Bluetooth") == nil and #root <= 9,
    "Settings: Audio after Sleep and wallpaper, then a line; Bluetooth in Audio, not on the first page (nine rows at most) " .. texts(root))
check(not texts(find(root, "General").sub_item_table):find("|Audio|", 1, true), "not in General any more")
local a = find(root, "Audio")
check(a and a._zen_settings_root == "audio" and texts(a.sub_item_table) == "|Bluetooth|Read aloud|Test audiobook playback|Pause when headphones are unplugged|Find the headphone jack|"
        and a.sub_item_table[1].separator == true,
    "Audio: Bluetooth (a line under it), Read aloud, Test audiobook playback, Pause when headphones are unplugged, Find the headphone jack " .. texts(a and a.sub_item_table))
check(a and type(a.icon_file) == "string" and a.icon_file:find("tab_music", 1, true) ~= nil, "Audio has the Music tab's icon")
check(a and type(a.sub_item_table[1].callback) == "function", "its rows are GZreader's own (they still run)")
local reader = texts(find(root, "Reader").sub_item_table)
print("    Reader: " .. reader)
for _i, gone in ipairs(GzS.AUDIO_ITEMS) do
    check(not reader:find("|" .. gone .. "|", 1, true), "not in Reader any more: " .. gone)
end
check(reader:find("|Something else|$") ~= nil, "GZreader's other Reader items stay at the end of Reader")

-- a Kindle without a speaker (GZreader gives no Reader items): no Audio
root = build({})
check(find(root, "Audio") == nil and find(root, "Bluetooth") ~= nil, "no speaker: no Audio, Bluetooth on the first page")

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
