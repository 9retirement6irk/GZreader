--[[--
GZreader "Reading menu": what the Menu key opens while reading on a Kindle
Keyboard. A plain list, so every entry has a letter key (Q, W, E, …) shown
next to it and the 5-way works too. Holding Menu still opens ZenOS's page
browser; "All settings" opens the full reader menu.
]]

local Event = require("ui/event")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ReadMenu = {}

function ReadMenu.items(plugin)
    local ui = plugin.ui
    local function send(name, ...)
        local args = { ... }
        return function() ui:handleEvent(Event:new(name, table.unpack and table.unpack(args) or unpack(args))) end
    end
    local tts = plugin.tts
    local items = {
        { text = _("Table of contents"), callback = function()
            if not ui:handleEvent(Event:new("ShowZenUIToc")) then ui:handleEvent(Event:new("ShowToc")) end
        end },
        { text = _("Bookmarks"), callback = send("ShowBookmark") },
        { text_func = function()
            local bm = ui.view and ui.view.dogear_visible
            return bm and _("Remove bookmark on this page") or _("Bookmark this page")
        end, callback = send("ToggleBookmark") },
        { text = _("Go to page or %"), callback = send("ShowGotoDialog") },
        { text = _("Search in book"), callback = send("ShowFulltextSearchInput") },
    }
    if tts and tts:supported() then
        items[#items + 1] = {
            text_func = function() return tts.active and _("Stop reading aloud  (Shift + Sym)") or _("Read aloud  (Shift + Sym)") end,
            callback = function() tts:toggle() end,
        }
    end
    items[#items + 1] = { text = _("Font, size and layout"), callback = send("ShowConfigMenu") }
    if ui.document and not ui.document.info.has_pages and ui.styletweak then
        items[#items + 1] = require("grimmory_picturebook").menuItem(ui)
    end
    if plugin.sync then
        items[#items + 1] = { text = _("Sync with Grimmory now"), callback = function() plugin:onGrimmorySyncNow() end }
    end
    local Tasks = require("grimmory_tasks")
    if Tasks.count() > 0 then items[#items + 1] = Tasks.menuItem() end
    items[#items + 1] = { text = _("Look up a word"), callback = send("ShowDictionaryLookup") }
    items[#items + 1] = { text = _("Page browser"), callback = send("ShowPageBrowser") }
    items[#items + 1] = { text = _("Book information"), callback = send("ShowBookInfo") }
    items[#items + 1] = { text = _("Read-aloud settings"), callback = function() plugin:showTtsSettings() end }
    items[#items + 1] = { text = _("All settings (full menu)"), callback = function()
        if ui.menu then ui.menu:onShowMenu() end
    end }
    items[#items + 1] = { text = _("Close book (Home)"), callback = send("Home") }
    return items
end

function ReadMenu.show(plugin)
    local menu
    menu = Menu:new{
        title = _("Reading menu"),
        item_table = ReadMenu.items(plugin),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_fm_style = true,
        onMenuChoice = function(_menu, item)
            UIManager:close(menu, "full")
            -- run after the menu is gone so dialogs open on the book page
            if item.callback then UIManager:nextTick(item.callback) end
            return true
        end,
    }
    -- The Menu key closes it again.
    menu.key_events = menu.key_events or {}
    menu.key_events.GzCloseReadMenu = { { "Menu" } }
    menu.onGzCloseReadMenu = function() UIManager:close(menu, "full"); return true end
    -- Back key too: full e-ink refresh, no ghost of the menu on the page
    menu.onCloseAllMenus = function(m)
        UIManager:close(m, "full")
        if m.close_callback then m.close_callback() end
        return true
    end
    UIManager:show(menu, "full") -- full e-ink refresh: no ghosting from the page behind
    return menu
end

return ReadMenu
