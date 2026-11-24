--[[--
What GZreader's own tabs in ZenOS's tab bar (Catalog, Notes, Calendar, House, Recipes…)
share: closing each other when one opens, and ZenOS's status row (clock,
Wi-Fi, battery) as their title.
]]

local UIManager = require("ui/uimanager")

local Tabs = {
    IDS = { ct_grimmory = true, ct_notes = true, ct_calendar = true, ct_music = true, ct_audiobooks = true, ct_house = true, ct_recipes = true },
}

--- Close GZreader's other tab views. ZenOS opens an action tab on top of the
--- one that's open, so switching between them stacked full-screen views.
function Tabs.closeOthers(keep_id)
    local close = {}
    for _i, w in ipairs(UIManager._window_stack or {}) do
        local id = w.widget and w.widget._gz_navbar_tab_id
        if id and id ~= keep_id and Tabs.IDS[id] then close[#close + 1] = w.widget end
    end
    for _i, widget in ipairs(close) do UIManager:close(widget) end
end

--- ZenOS (its plugin object), or nil. __ZEN_UI_PLUGIN is only set while ZenOS
--- sets itself up; after that the file manager has it.
function Tabs.zen()
    local FileManager = require("apps/filemanager/filemanager")
    return (FileManager.instance and FileManager.instance.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
end

---------------------------------------------------------------- on or off

Tabs.MAX_SHOWN = 7 -- (ZenOS's tab bar)

local function navbar()
    local zen = Tabs.zen()
    local nb = zen and type(zen.config) == "table" and zen.config.navbar
    if type(nb) ~= "table" then return nil end
    return nb, zen
end

--- Whether tab `id` is in the tab bar.
function Tabs.shown(id)
    local nb = navbar()
    return nb ~= nil and type(nb.show_tabs) == "table" and nb.show_tabs[id] == true
end

--- Put tab `id` in the tab bar, or take it out (as Settings → Home and tabs →
--- Tab bar → Tabs does). `entry`: its definition, added to ZenOS's tab list
--- when it isn't there. False when it can't: no ZenOS, or 7 tabs already
--- (then `full(message)` is called with what to do).
function Tabs.setShown(id, on, entry, full)
    local nb, zen = navbar()
    if not nb then return false end
    nb.show_tabs = type(nb.show_tabs) == "table" and nb.show_tabs or {}
    nb.tab_order = type(nb.tab_order) == "table" and nb.tab_order or {}
    nb.custom_tabs = type(nb.custom_tabs) == "table" and nb.custom_tabs or {}
    local has_tab, listed = false, false
    for _i, t in ipairs(nb.custom_tabs) do if type(t) == "table" and t.id == id then has_tab = true end end
    if not has_tab and entry then table.insert(nb.custom_tabs, entry) end
    for _i, t in ipairs(nb.tab_order) do if t == id then listed = true end end
    if not listed then table.insert(nb.tab_order, id) end
    if on and nb.show_tabs[id] ~= true then
        local count = 0
        for _i, t in ipairs(nb.tab_order) do if nb.show_tabs[t] == true then count = count + 1 end end
        if count >= Tabs.MAX_SHOWN then
            local _ = require("gettext")
            if full then full(_("The tab bar has 7 tabs already: turn one off first (Settings → Home and tabs → Tab bar → Tabs).")) end
            return false
        end
    end
    nb.show_tabs[id] = on and true or false
    if type(zen.saveConfig) == "function" then pcall(zen.saveConfig, zen) end
    local reinject = rawget(_G, "__ZEN_UI_REINJECT_NAVBARS") or rawget(_G, "__ZEN_UI_REINJECT_FM_NAVBAR")
    if type(reinject) == "function" then UIManager:scheduleIn(0, reinject) end
    require("gzreader_log").info("tabs:", id, on and "shown" or "hidden")
    return true
end

--- ZenOS's status row in a tab view's title, with `label`; no close button.
function Tabs.decorate(menu, label)
    local zen = Tabs.zen()
    if not (menu and menu.title_bar and zen) then return end
    local SharedState = require("common/shared_state")
    local createStatusRow = SharedState.get(zen, "createStatusRow")
    if type(createStatusRow) ~= "function" then return end
    require("modules/filebrowser/patches/standalone_page").apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = SharedState.get(zen, "createStatusRowCustomBack"),
        repaintTitleBar = SharedState.get(zen, "repaintTitleBar"),
        label = label,
    })
    -- touch Kindles: the buttons in place of the key hints (a new title bar loses them)
    if menu._gz_actions then pcall(require("gzreader_touch").actionRow, menu) end
end

--- The Home key from a full-screen view of ours (the audiobook player,
--- Settings): close everything above the file manager and open the default
--- tab (Home), like the Home key does in the file manager. `widget` is closed
--- first (its own close handling runs). In a book (no file manager), the
--- reader's Home.
function Tabs.goHome(widget)
    if widget then UIManager:close(widget) end
    -- at once (not on the next tick): closing and Home make one screen refresh
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if fm and fm.onHome then
        fm:onHome()
        return true
    end
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader = ok and ReaderUI.instance
    if reader and reader.onHome then reader:onHome() end
    return true
end

return Tabs
