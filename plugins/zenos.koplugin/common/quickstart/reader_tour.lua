local _ = require("gettext")

local M = {}
local active = false

function M.start(plugin, ui, open_page_browser)
    local meta = plugin and plugin.config and plugin.config._meta
    -- GZreader: the tour is coachmarks for touch gestures ("swipe up…") on
    -- the touch menus. A Kindle Keyboard has neither (GZreader's Menu key
    -- opens its own list), so the tour only opened the wrong menu or the page
    -- browser over the book, and stayed "pending" for ever. Mark it done.
    if type(meta) == "table" and meta.quickstart_reader_tour_pending == true
            and not require("device"):isTouchDevice() then
        meta.quickstart_reader_tour_pending = false
        if type(plugin.saveConfig) == "function" then pcall(plugin.saveConfig, plugin) end
        return false
    end
    if type(meta) ~= "table" or meta.quickstart_reader_tour_pending ~= true
            or active or type(open_page_browser) ~= "function" then
        return false
    end

    -- GZreader: after the quick panel's tour (it starts this one when it
    -- ends), and never under the quick panel
    local ok_gz, GzTour = pcall(require, "gzreader_tour")
    if ok_gz then
        if meta.quickstart_menu_tour_pending == true or GzTour.active then return false end
        GzTour.closePanel()
    end

    local UIManager = require("ui/uimanager")
    local Coachmark = require("common/quickstart/menu_coachmark")
    active = true
    -- One-shot: clear as soon as shown
    meta.quickstart_reader_tour_pending = false
    plugin:saveConfig()

    UIManager:show(Coachmark:new{
        steps = {{
            text = _("Swipe up to open the Page Browser"),
            position = "bottom",
            swipe_up = true,
        }},
        on_complete = function()
            active = false
            open_page_browser()
        end,
        on_cancel = function() active = false end,
    })
    return true
end

return M
