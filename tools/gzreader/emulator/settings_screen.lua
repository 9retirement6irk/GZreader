-- Settings → General → Screen on the emulated Kindle, built by the real code
-- from KOReader's real menu: Settings starts with General; General → Screen
-- is KOReader's Screen menu without Sleep screen and Rotation; its E-ink
-- settings have Full refresh rate, then GZreader's flash rows; Settings →
-- KOReader has no Screen menu and no "Flash on every CBZ page turn" anywhere.
-- Prints "[emu] screen: …" lines; shots of General → Screen and its E-ink settings.
--   GZ_EMU_TREE=<tree>/koreader run.sh settings_screen.lua <out>
local function text(it)
    local s = it.text
    if s == nil and type(it.text_func) == "function" then
        local ok, v = pcall(it.text_func); s = ok and v or nil
    end
    return type(s) == "string" and s or "?"
end
local function texts(list)
    local t = {}
    for _i, it in ipairs(type(list) == "table" and list or {}) do t[#t + 1] = text(it) end
    return table.concat(t, " | ")
end
local function find(list, name)
    for _i, it in ipairs(list or {}) do if text(it) == name then return it end end
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
local function root()
    local fm = require("apps/filemanager/filemanager").instance
    local plugin = fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
    return require("modules/settings/zen_settings").build(plugin).sub_item_table
end
local function ids(list, out, depth, seen)
    if depth > 5 or type(list) ~= "table" or seen[list] then return out end
    seen[list] = true
    for _i, it in ipairs(list) do
        if type(it) == "table" then
            out[#out + 1] = (type(it.id) == "string" and it.id or "") .. "=" .. text(it)
            ids(sub(it), out, depth + 1, seen)
        end
    end
    return out
end

local function report(_E)
    local r = root()
    print("[emu] screen: root = " .. texts(r))
    local general = sub(find(r, "General"))
    print("[emu] screen: general = " .. texts(general))
    local screen = sub(find(general, "Screen"))
    print("[emu] screen: screen = " .. texts(screen))
    local eink = sub(find(screen, "E-ink settings"))
    print("[emu] screen: e-ink = " .. texts(eink))
    print("[emu] screen: full refresh rate = " .. texts(sub(find(eink, "Full refresh rate"))))
    local ko = table.concat(ids(sub(find(r, "KOReader")), {}, 0, {}), ",")
    print("[emu] screen: koreader has screen menu: " .. tostring(ko:find("screen_eink_opt", 1, true) ~= nil)
        .. ", CBZ row anywhere: " .. tostring((texts(screen) .. texts(eink) .. ko):find("CBZ", 1, true) ~= nil))
end

local function open(path_texts)
    return function(_E)
        local list = root()
        for _i, name in ipairs(path_texts) do list = sub(find(list, name)) end
        local Menu = require("ui/widget/menu")
        local UIManager = require("ui/uimanager")
        if _G.__gz_emu_menu then UIManager:close(_G.__gz_emu_menu) end
        local m = Menu:new{ title = table.concat(path_texts, " → "), item_table = {}, is_popout = false }
        local items = {}
        for _j, it in ipairs(list) do items[#items + 1] = { text = text(it) } end
        m:switchItemTable(nil, items)
        _G.__gz_emu_menu = m
        UIManager:show(m)
    end
end

return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = report, after = 2 },
    { fn = open({ "General", "Screen" }), after = 4 },
    { shot = "general-screen" },
    { fn = open({ "General", "Screen", "E-ink settings" }), after = 4 },
    { shot = "general-screen-eink" },
    -- the real Settings page (icons, ticks), opened straight to the path
    { fn = function(_E)
        local UIManager = require("ui/uimanager")
        if _G.__gz_emu_menu then UIManager:close(_G.__gz_emu_menu); _G.__gz_emu_menu = nil end
        local fm = require("apps/filemanager/filemanager").instance
        require("modules/settings/zen_settings_page").show(fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN"), { path = {
            { key = "text", value = "General" }, { key = "text", value = "Screen" }, { key = "text", value = "E-ink settings" } } })
    end, after = 6 },
    { shot = "settings-page-eink" },
    { fn = function(_E)
        local Page = require("modules/settings/zen_settings_page")
        if Page.closeActive then Page.closeActive() end
        local fm = require("apps/filemanager/filemanager").instance
        Page.show(fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN"), { path = {} })
    end, after = 6 },
    { shot = "settings-root" },
}
