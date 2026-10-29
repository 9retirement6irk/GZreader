--[[--
GZreader "Home menu": what the Menu key opens on the Home screen and the
library on a Kindle Keyboard (instead of ZenOS's touch quick-settings panel).
A plain list like the Reading menu: every entry has its letter key.
]]

local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local HomeMenu = {}

local function dispatch(action)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher.execute then Dispatcher:execute({ [action] = true }) end
end

local function fm()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    return ok and FileManager.instance or nil
end

function HomeMenu.items(plugin)
    local items = {
        { text = _("Grimmory library"), callback = function() plugin:onShowGrimmoryLibrary() end },
        { text = _("Continue reading (last book)"), callback = function() dispatch("open_previous_document") end },
        { text_func = function()
            local ok, Audiobook = pcall(require, "grimmory_audiobook")
            local cur = ok and Audiobook.current
            return cur and (_("Audiobook: ") .. (cur.book.title or "?")) or _("Audiobooks")
        end, callback = function()
            local ok, Audiobook = pcall(require, "grimmory_audiobook")
            if ok and Audiobook.current then return Audiobook.open(plugin, Audiobook.current.book) end
            local list = ok and Audiobook.downloaded(plugin) or {}
            if #list == 1 then return Audiobook.open(plugin, list[1].book) end
            plugin:showAudiobookMenu()
        end },
        { text = _("Search books on this Kindle"), callback = function() dispatch("file_search") end },
        { text = _("History"), callback = function() dispatch("history") end },
        { text_func = function()
            return NetworkMgr:isWifiOn() and _("Turn Wi-Fi off") or _("Turn Wi-Fi on")
        end, callback = function() dispatch("toggle_wifi") end },
        { text_func = function()
            return G_reader_settings:isTrue("night_mode") and _("Night mode off") or _("Night mode on")
        end, callback = function() dispatch("night_mode") end },
        { text = _("Settings"), callback = function()
            local ok, Page = pcall(require, "modules/settings/zen_settings_page")
            local zen = rawget(_G, "__ZEN_UI_PLUGIN")
            if ok and zen then Page.show(zen) else HomeMenu.fullMenu() end
        end },
        { text = _("Check for GZreader updates"), callback = function() require("grimmory_update").run() end },
        { text = _("Send diagnostic log to my phone"), callback = function() plugin:shareLog() end },
        { text = _("Sleep"), callback = function() dispatch("suspend") end },
        { text = _("Restart GZreader"), callback = function() dispatch("restart") end },
        { text = _("All settings (full menu)"), callback = function() HomeMenu.fullMenu() end },
        { text = _("Exit to the Kindle"), callback = function() dispatch("exit") end },
    }
    return items
end

function HomeMenu.fullMenu()
    local f = fm()
    if f and f.menu then
        f.menu._gz_full = true
        f.menu:onShowMenu()
        f.menu._gz_full = nil
    end
end

function HomeMenu.show(plugin)
    if HomeMenu.open then return true end
    local menu
    menu = Menu:new{
        title = _("Menu"),
        item_table = HomeMenu.items(plugin),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_fm_style = true,
        onMenuChoice = function(_m, item)
            UIManager:close(menu)
            if item.callback then UIManager:nextTick(item.callback) end
            return true
        end,
        close_callback = function() HomeMenu.open = nil end,
    }
    menu.key_events = menu.key_events or {}
    menu.key_events.GzCloseHomeMenu = { { "Menu" } }
    menu.onGzCloseHomeMenu = function() UIManager:close(menu); return true end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        HomeMenu.open = nil
        if orig_close then return orig_close(m, ...) end
    end
    HomeMenu.open = menu
    UIManager:show(menu)
    return true
end

return HomeMenu
