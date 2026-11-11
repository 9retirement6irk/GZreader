-- Settings as GZreader trims it, built by the real code on the emulated
-- Kindle: About's first lines, General → Advanced, the KOReader section's
-- items (none of gz_settings.KOREADER_HIDDEN). Prints
-- "[emu] settings: …" lines and shots of About and General → Advanced.
--   GZ_EMU_TREE=<tree>/koreader run.sh settings_cleanup.lua <out>
local function texts(list)
    local t = {}
    for _i, it in ipairs(type(list) == "table" and list or {}) do
        local s = it.text
        if s == nil and type(it.text_func) == "function" then
            local ok, v = pcall(it.text_func); s = ok and v or nil
        end
        t[#t + 1] = type(s) == "string" and s or "?"
    end
    return table.concat(t, " | ")
end
local function find(list, name)
    for _i, it in ipairs(list or {}) do if it.text == name then return it end end
end
local function sub(it)
    if not it then return {} end
    if it.sub_item_table then return it.sub_item_table end
    if type(it.sub_item_table_func) == "function" then
        local ok, v = pcall(it.sub_item_table_func, { closeMenu = function() end, updateItems = function() end })
        return ok and v or {}
    end
    return {}
end
-- every KOReader menu id under the KOReader section, however deep
local function ids(list, out, depth, seen)
    if depth > 5 or type(list) ~= "table" or seen[list] then return out end
    seen[list] = true
    for _i, it in ipairs(list) do
        if type(it) == "table" then
            if type(it.id) == "string" then out[#out + 1] = it.id end
            ids(sub(it), out, depth + 1, seen)
        end
    end
    return out
end

local function report(_E)
    local fm = require("apps/filemanager/filemanager").instance
    local zen = fm and fm.zenos
    local plugin = zen or rawget(_G, "__ZEN_UI_PLUGIN")
    local root = require("modules/settings/zen_settings").build(plugin).sub_item_table
    print("[emu] settings: root = " .. texts(root))
    local about = sub(find(root, "About"))
    print("[emu] settings: about = " .. texts(about))
    local general = sub(find(root, "General"))
    print("[emu] settings: general = " .. texts(general))
    print("[emu] settings: advanced = " .. texts(sub(find(general, "Advanced"))))
    local ko = sub(find(root, "KOReader"))
    print("[emu] settings: koreader = " .. texts(ko))
    local all = ids(ko, {}, 0, {})
    local hidden = require("common/gz_settings").KOREADER_HIDDEN
    local bad = {}
    for _i, id in ipairs(all) do if hidden[id] then bad[#bad + 1] = id end end
    print("[emu] settings: koreader ids " .. #all .. ", hidden ones shown: " .. (#bad == 0 and "none" or table.concat(bad, ",")))
end

local function open(path_texts)
    return function(_E)
        local fm = require("apps/filemanager/filemanager").instance
        local plugin = fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        local list = require("modules/settings/zen_settings").build(plugin).sub_item_table
        for _i, name in ipairs(path_texts) do list = sub(find(list, name)) end
        local Menu = require("ui/widget/menu")
        local UIManager = require("ui/uimanager")
        if _G.__gz_emu_menu then UIManager:close(_G.__gz_emu_menu) end
        local m = Menu:new{ title = table.concat(path_texts, " → "), item_table = {} , is_popout = false }
        local items = {}
        for _j, it in ipairs(list) do
            local s = it.text or (type(it.text_func) == "function" and select(2, pcall(it.text_func))) or "?"
            items[#items + 1] = { text = tostring(s) }
        end
        m:switchItemTable(nil, items)
        _G.__gz_emu_menu = m
        UIManager:show(m)
    end
end

return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = report, after = 2 },
    { fn = open({ "About" }), after = 4 },
    { shot = "about" },
    { fn = open({ "General", "Advanced" }), after = 4 },
    { shot = "general-advanced" },
}
