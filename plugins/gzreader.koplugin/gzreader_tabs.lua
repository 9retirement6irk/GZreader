--[[--
What GZreader's own tabs in ZenOS's tab bar (Grimmory, Notes, Calendar)
share: closing each other when one opens, and ZenOS's status row (clock,
Wi-Fi, battery) as their title.
]]

local UIManager = require("ui/uimanager")

local Tabs = {
    IDS = { ct_grimmory = true, ct_notes = true, ct_calendar = true },
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
end

return Tabs
