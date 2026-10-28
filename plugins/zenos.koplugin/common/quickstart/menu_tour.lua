local _ = require("gettext")

local M = {}
local active = false

local RETRY_DELAY = 0.1
local MAX_RETRIES = 20

local ZEN_MODE_TEXT = table.concat({
    _("Zen Mode is enabled. KOReader menus are hidden."),
    _("Disable Zen Mode with this icon to adjust KOReader settings that aren’t available in Zen Settings."),
    _("This does not disable ZenOS—it only shows or hides KOReader’s menus."),
}, "\n\n")
local ZEN_SETTINGS_TEXT = _("This is Zen Settings. ZenOS settings/updates and common KOReader settings live here.")
local KOREADER_SETTINGS_TEXT = _("Adjust KOReader settings here. These tabs were previously located in the top menu")

local function valid_dimen(dimen)
    return type(dimen) == "table"
        and type(dimen.x) == "number" and type(dimen.y) == "number"
        and type(dimen.w) == "number" and dimen.w > 0
        and type(dimen.h) == "number" and dimen.h > 0
end

local function tab_index(tabs, id)
    for i, tab in ipairs(tabs or {}) do
        if tab.id == id then return i end
    end
end

local function zen_button_dimen(touch_menu)
    local refs = touch_menu and touch_menu._zen_panel_refs
    for _i, ref in ipairs(refs and refs.buttons or {}) do
        if ref.id == "zen" then
            local dimen = ref.widget and ref.widget.dimen
            return valid_dimen(dimen) and dimen or nil, true
        end
    end
end

local function zen_settings_dimen(touch_menu)
    local index = tab_index(touch_menu and touch_menu.tab_item_table, "zen_ui")
    local icon = index and touch_menu.bar and touch_menu.bar.icon_widgets
        and touch_menu.bar.icon_widgets[index]
    local image_dimen = icon and icon.image and icon.image.dimen
    if valid_dimen(image_dimen) then return image_dimen end
    local dimen = icon and icon.dimen
    return valid_dimen(dimen) and dimen or nil
end

local function switch_to_quicksettings(touch_menu, index)
    local icon = touch_menu and touch_menu.bar and touch_menu.bar.icon_widgets
        and touch_menu.bar.icon_widgets[index]
    if icon and type(icon.callback) == "function" then
        icon.callback()
        return true
    end
    if touch_menu and type(touch_menu.switchMenuTab) == "function" then
        touch_menu:switchMenuTab(index)
        return true
    end
    return false
end

local function wait_until_ready(get_steps, on_ready)
    local UIManager = require("ui/uimanager")
    local retries = 0
    local function check()
        local steps = get_steps()
        if steps then
            on_ready(steps)
            return
        end
        retries = retries + 1
        if retries < MAX_RETRIES then
            UIManager:scheduleIn(RETRY_DELAY, check)
        else
            active = false
        end
    end
    UIManager:scheduleIn(RETRY_DELAY, check)
end

function M.start(plugin)
    local meta = plugin and plugin.config and plugin.config._meta
    if type(meta) ~= "table" or meta.quickstart_menu_tour_pending ~= true or active then
        return false
    end

    local menu = plugin.ui and plugin.ui.menu
    if not (menu and type(menu.onShowMenu) == "function") then return false end
    if type(menu.tab_item_table) ~= "table" and type(menu.setUpdateItemTable) == "function" then
        menu:setUpdateItemTable()
    end
    local quicksettings_index = tab_index(menu.tab_item_table, "quicksettings")
    if not quicksettings_index then return false end

    local UIManager = require("ui/uimanager")
    local menu_container = menu.menu_container
    local menu_is_open = menu_container and type(UIManager.isWidgetShown) == "function"
        and UIManager:isWidgetShown(menu_container)
    if menu_is_open then
        if not switch_to_quicksettings(menu_container[1], quicksettings_index) then return false end
    else
        menu:onShowMenu(quicksettings_index)
        local touch_menu = menu.menu_container and menu.menu_container[1]
        if touch_menu and touch_menu.cur_tab ~= quicksettings_index
                and not switch_to_quicksettings(touch_menu, quicksettings_index) then
            return false
        end
    end

    active = true
    local Coachmark = require("common/quickstart/menu_coachmark")
    local touch_menu
    local settings_page
    local has_zen_button
    local function cancel()
        if settings_page then settings_page:closeMenu() end
        active = false
        UIManager:scheduleIn(0.5, function() M.start(plugin) end)
    end
    local function complete()
        meta.quickstart_menu_tour_pending = false
        plugin:saveConfig()
        active = false
        if settings_page then
            settings_page:closeMenu()
        elseif type(touch_menu.updateItems) == "function" then
            touch_menu:updateItems(1)
        end
        if meta.quickstart_reader_tour_pending == true
                and type(menu._zen_start_reader_tour) == "function" then
            menu:_zen_start_reader_tour()
        end
    end

    local function show_koreader_step()
        touch_menu:closeMenu()
        settings_page = require("modules/settings/zen_settings_page").show(plugin, { path = {} })
        settings_page:backToRootMenu()
        for index, item in ipairs(settings_page.item_table) do
            if item._zen_settings_root == "koreader" then
                settings_page.page = settings_page:getPageNumber(index)
                settings_page:updateItems(1)
                break
            end
        end
        UIManager:forceRePaint()
        wait_until_ready(function()
            if settings_page._closed then return nil end
            for _i, row in ipairs(settings_page.item_group or {}) do
                if row.entry._zen_settings_root == "koreader" then
                    local container = row._underline_container or row[1]
                    local target = container and container.dimen
                    if valid_dimen(target) then
                        return {{ text = KOREADER_SETTINGS_TEXT, target = target }}
                    end
                end
            end
        end, function(steps)
            UIManager:show(Coachmark:new{
                steps = steps,
                on_complete = complete,
                on_cancel = cancel,
            })
        end)
    end

    UIManager:forceRePaint()
    wait_until_ready(function()
        touch_menu = menu.menu_container and menu.menu_container[1]
        local zen_target
        zen_target, has_zen_button = zen_button_dimen(touch_menu)
        local settings_target = zen_settings_dimen(touch_menu)
        if not (settings_target and touch_menu._zen_panel_refs)
                or (has_zen_button and not zen_target) then return nil end
        local steps = {{ text = ZEN_SETTINGS_TEXT, target = settings_target }}
        if zen_target then
            table.insert(steps, 1, { text = ZEN_MODE_TEXT, target = zen_target })
        end
        return steps
    end, function(steps)
        UIManager:show(Coachmark:new{
            steps = steps,
            on_complete = has_zen_button and complete or show_koreader_step,
            on_cancel = cancel,
        })
    end)
    return true
end

return M
