-- Settings → Reader in fewer rows: Notes and footnotes (Annotation viewer,
-- Footnotes and pinned pages) and Gestures and controls (Bottom swipe
-- gesture, Reader controls, Page Browser) as submenus; the Settings buttons
-- in the page browser, the annotation viewer and the reference drawer still
-- open their page. ZenOS's Reader section is real; the rest are stubs.
--   luajit settings_reader_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local function magic()
    local m
    m = setmetatable({}, { __index = function() return m end, __call = function() return m end,
        __concat = function() return "" end, __tostring = function() return "" end })
    return m
end
local stubs = {
    gettext = function(s) return s end,
    ["ffi/util"] = { template = function(f, ...) local a = { ... }
        return (f:gsub("%%(%d)", function(i) return tostring(a[tonumber(i)]) end)) end },
    ["common/ui/icon_menu_item"] = { installMenuPatch = function() end, decorate = function(item, glyph)
        item.icon_glyph = item.icon_glyph or glyph; return item end },
    ["common/plugin_root"] = "",
}
table.insert(package.loaders, 2, function(name)
    if stubs[name] ~= nil then local v = stubs[name]; return function() return v end end
    if name:match("^modules/settings/") or name == "common/inline_icon_map" then return nil end
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

local G = require("modules/settings/sections/gz_reader_groups")

-- the helper on its own
local function rows(...)
    local t = {}
    for _i, name in ipairs({ ... }) do t[#t + 1] = { text = name, separator = true } end
    return t
end
local list = rows("Appearance", "Page Browser", "Annotation viewer", "Bottom swipe gesture", "Mine", "Reader controls")
list.needs_refresh = true
local out = G.group(list)
check(texts(out) == "|Appearance|Gestures and controls|Notes and footnotes|Mine|",
    "a group takes the place of its first entry; the rest stay in their order " .. texts(out))
check(texts(find(out, "Gestures and controls").sub_item_table) == "|Bottom swipe gesture|Reader controls|Page Browser|",
    "Gestures and controls: Bottom swipe gesture, Reader controls, Page Browser (in that order)")
check(texts(find(out, "Notes and footnotes").sub_item_table) == "|Annotation viewer|",
    "a group has what's there (Footnotes and pinned pages missing here)")
check(find(out, "Gestures and controls").sub_item_table[1].separator == nil, "no lines inside a group")
check(find(out, "Appearance").separator == true, "rows outside a group keep their line")
check(out.needs_refresh == true, "the list's own fields are kept")
check(find(out, "Gestures and controls").icon_glyph ~= nil and find(out, "Notes and footnotes").icon_glyph ~= nil, "each group has an icon")
check(texts(G.group(rows("Appearance", "End of book"))) == "|Appearance|End of book|", "no members: no empty group")
check(G.group(nil) == nil, "nil: nil")

-- the paths the Settings buttons open
local function ptexts(path)
    local t = {}
    for _i, p in ipairs(path) do t[#t + 1] = p.value end
    return table.concat(t, " → ")
end
check(ptexts(G.path("Page Browser")) == "Reader → Gestures and controls → Page Browser", "path: " .. ptexts(G.path("Page Browser")))
check(ptexts(G.path("Footnotes and pinned pages", "Pinned page options"))
    == "Reader → Notes and footnotes → Footnotes and pinned pages → Pinned page options", "path with more steps")
check(ptexts(G.path("Highlight / Lookup", "Highlight")) == "Reader → Highlight / Lookup → Highlight", "path to an entry outside a group")
for file, entry in pairs({
    ["modules/reader/page_browser_widget.lua"] = 'gz_reader_groups").path(_("Page Browser"))',
    ["modules/reader/annotation_viewer.lua"] = 'gz_reader_groups").path(_("Annotation viewer"))',
    ["modules/reader/reference_drawer.lua"] = 'gz_reader_groups").path(_("Footnotes and pinned pages")',
}) do
    check(read(file):find(entry, 1, true) ~= nil, file .. ": its Settings button goes through the group")
end

-- ZenOS's real Reader section
local config = { features = {}, lockdown = {}, custom_icons = { active_pack = "" }, navbar = { show_tabs = {} }, _meta = {} }
local plugin = { config = config, saveConfig = function() end }
local ctx = { plugin = plugin, config = config, save_and_apply = function() end, apply_feature = function() end,
    settings_apply = magic() }
local okb, reader = pcall(require("modules/settings/sections/reader_settings").build, ctx)
check(okb and type(reader) == "table", "Reader builds " .. tostring(not okb and reader or ""))
if okb then
    print("    Reader: " .. texts(reader))
    check(texts(reader) == "|Appearance|Highlight / Lookup|Gestures and controls|Notes and footnotes|Restore library location on exit|End of book|",
        "Reader: Appearance, Highlight / Lookup, Gestures and controls, Notes and footnotes, Restore library location on exit, End of book")
    check(texts(find(reader, "Gestures and controls").sub_item_table) == "|Bottom swipe gesture|Reader controls|Page Browser|",
        "Gestures and controls holds ZenOS's three")
    check(texts(find(reader, "Notes and footnotes").sub_item_table) == "|Annotation viewer|Footnotes and pinned pages|",
        "Notes and footnotes holds ZenOS's two")
    -- each deep link's path finds its page in what was built
    local function resolve(path)
        local it, items = nil, { { text = "Reader", sub_item_table = reader } }
        for _i, step in ipairs(path) do
            it = find(items, step.value)
            if not it then return nil end
            items = rawget(it, "sub_item_table")
            if not items and type(rawget(it, "sub_item_table_func")) == "function" then
                local okf, v = pcall(it.sub_item_table_func); items = okf and v or nil
            end
        end
        return it
    end
    check(resolve(G.path("Page Browser")) ~= nil, "the page browser's Settings button finds Page Browser")
    check(resolve(G.path("Annotation viewer")) ~= nil, "the annotation viewer's Settings button finds Annotation viewer")
    check(resolve(G.path("Footnotes and pinned pages")) ~= nil, "the reference drawer's Settings button finds Footnotes and pinned pages")
end

print(ok_count .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
