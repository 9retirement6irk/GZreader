--[[--
GZreader "Home menu": what the Menu key opens on the Home screen and the
library on a Kindle Keyboard (instead of ZenOS's touch quick-settings panel).
A plain list like the Reading menu: every entry has its letter key.
]]

local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local HomeMenu = {}

local function dispatch(action)
    local ok, Dispatcher = pcall(require, "dispatcher")
    if ok and Dispatcher.execute then Dispatcher:execute({ [action] = true }) end
end

local function fm()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    return ok and FileManager.instance or nil
end

---------------------------------------------------------------- the highlighted book

--- The book highlighted on Home or in a file list (Downloaded tab) when the
--- Menu key was pressed: { path, context = ZenOS's own book menu } or nil.
function HomeMenu.highlighted()
    local top = UIManager:getTopmostVisibleWidget()
    -- ZenOS Home: its focus targets (GZreader adds the book's path to them)
    local targets = top and top._zen_home_focus_targets
    local idx = top and top._zen_home_focus_index
    if type(targets) == "table" and type(idx) == "number" and not top._zen_home_focus_suspended then
        local t = targets[idx]
        if t and type(t.path) == "string" and lfs.attributes(t.path, "mode") == "file" then
            return { path = t.path, context = t.context }
        end
        return nil
    end
    -- file lists: the focused entry
    local f = fm()
    local fc = f and f.file_chooser
    if fc and (top == f or top == f.show_parent or top == fc) and type(fc.getFocusItem) == "function" then
        local ok, item = pcall(fc.getFocusItem, fc)
        local entry = ok and type(item) == "table" and (item.entry or item.item)
        local path = type(entry) == "table" and (entry.path or entry.file)
        if type(path) == "string" and entry.is_file ~= false and lfs.attributes(path, "mode") == "file" then
            return { path = path, context = function() fc:showFileDialog(entry) end }
        end
    end
end

local function bookTitle(path)
    local ok, BIM = pcall(require, "bookinfomanager")
    local info = ok and BIM:getBookInfo(path, false)
    local title = info and type(info.title) == "string" and info.title ~= "" and info.title
    return title or path:match("([^/]+)%.[^.]+$") or path
end

local function refreshViews(path)
    local f = fm()
    pcall(function() require("common/cover_disk_cache").drop(path) end)
    if f and f.file_chooser then pcall(f.file_chooser.refreshPath, f.file_chooser) end
    local zen = f and f.zenos
    pcall(function()
        local Home = require("common/shared_state").get(zen, "home")
        if Home then
            if Home.invalidateBookCache then Home.invalidateBookCache(path) end
            if Home.invalidateLibraryCache then Home.invalidateLibraryCache() end
            Home.rebuildActive()
        end
    end)
end

--- Delete a downloaded book from the Kindle (file, its .sdr, history and
--- collections entries; Grimmory's copy and reading progress stay).
function HomeMenu.deleteBook(plugin, path)
    local ConfirmBox = require("ui/widget/confirmbox")
    local InfoMessage = require("ui/widget/infomessage")
    local title = bookTitle(path)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete “%1” from this Kindle?\n\nIts reading position and bookmarks on this Kindle go too. Grimmory keeps the book and your progress, so you can download it again any time."), title),
        ok_text = _("Delete"),
        ok_callback = function()
            local f = fm()
            local ok = f and f.deleteFile and f:deleteFile(path, true)
            if not ok then
                local okfm, FileManager = pcall(require, "apps/filemanager/filemanager")
                if okfm and FileManager.deleteFile then
                    ok = FileManager.deleteFile(FileManager, path, true)
                else -- (no file manager loaded) the file and its .sdr folder
                    ok = os.remove(path) and true or false
                    if ok then pcall(function() require("docsettings").updateLocation(path) end) end
                end
            end
            if not ok then
                return UIManager:show(InfoMessage:new{ text = T(_("Couldn't delete “%1”."), title) })
            end
            local changed = false
            for id, e in pairs(plugin.store.downloads or {}) do
                if type(e) == "table" and e.path == path then plugin.store.downloads[id] = nil; changed = true end
            end
            if changed then plugin:save(); pcall(plugin.writeManifest, plugin) end
            require("grimmory_log").info("deleted from the Kindle:", path)
            refreshViews(path)
            UIManager:show(InfoMessage:new{ text = T(_("Deleted “%1”."), title), timeout = 2 })
        end,
    })
end

HomeMenu.SORTS = {
    { "access", _("Last read") },
    { "title", _("Title") },
    { "authors", _("Author") },
    { "series", _("Series") },
    { "date", _("Date downloaded") },
    { "percent_unopened_last", _("Reading progress") },
    { "size", _("File size") },
    { "natural", _("File name") },
}

--- Sort the book lists (the Downloaded tab and folders).
function HomeMenu.showSort()
    local ButtonDialog = require("ui/widget/buttondialog")
    local cur = G_reader_settings:readSetting("collate") or "strcoll"
    local reverse = G_reader_settings:isTrue("reverse_collate")
    local dialog
    local function apply(mode, rev)
        UIManager:close(dialog)
        G_reader_settings:saveSetting("collate", mode)
        if rev ~= nil then
            if rev then G_reader_settings:saveSetting("reverse_collate", true) else G_reader_settings:delSetting("reverse_collate") end
        end
        -- like ZenOS's own "Sort library": drop its cached lists, then re-list
        local f = fm()
        local fc = f and f.file_chooser
        if fc then
            if fc._zen_clear_item_table_cache then pcall(fc._zen_clear_item_table_cache, fc) end
            if fc.clearSortingCache then pcall(fc.clearSortingCache, fc) end
            pcall(fc.refreshPath, fc)
        end
    end
    local buttons = {}
    for _i, sdef in ipairs(HomeMenu.SORTS) do
        buttons[#buttons + 1] = {{ text = (sdef[1] == cur and "✓ " or "") .. sdef[2], callback = function() apply(sdef[1]) end }}
    end
    buttons[#buttons + 1] = {{ text = (reverse and "✓ " or "") .. _("Reverse order"), callback = function() apply(cur, not reverse) end }}
    dialog = ButtonDialog:new{ title = _("Sort books by"), buttons = buttons }
    UIManager:show(dialog)
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
        { text = _("Sort books…"), callback = function() HomeMenu.showSort() end },
        { text_func = function()
            return NetworkMgr:isWifiOn() and _("Turn Wi-Fi off") or _("Turn Wi-Fi on")
        end, callback = function() dispatch("toggle_wifi") end },
        not require("grimmory_nightguard").applies() and { text_func = function()
            return G_reader_settings:isTrue("night_mode") and _("Night mode off") or _("Night mode on")
        end, callback = function() dispatch("night_mode") end } or nil,
        { text = _("Settings"), callback = function() HomeMenu.settings() end },
        { text = _("KOReader settings"), callback = function()
            HomeMenu.settings({ path = { { key = "_zen_settings_root", value = "koreader" } } })
        end },
        { text = _("Check for GZreader updates"), callback = function() require("grimmory_update").run() end },
        { text = _("Send diagnostic log to my phone"), callback = function() plugin:shareLog() end },
        { text = _("Sleep"), callback = function() dispatch("suspend") end },
        { text = _("Restart GZreader"), callback = function() dispatch("restart") end },
        { text = _("Quick panel"), callback = function() HomeMenu.fullMenu() end },
        { text = _("Exit to the Kindle"), callback = function() dispatch("exit") end },
    }
    local list = {}
    local book = HomeMenu.context
    if book then
        local title = bookTitle(book.path)
        list[#list + 1] = { text = T(_("Open “%1”"), title), callback = function()
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(book.path)
        end }
        list[#list + 1] = { text = T(_("Delete “%1” from this Kindle"), title), callback = function()
            HomeMenu.deleteBook(plugin, book.path)
        end }
        if book.context then
            list[#list + 1] = { text = _("More options for this book"), callback = book.context, separator = true }
        end
    end
    local Tasks = require("grimmory_tasks")
    if Tasks.count() > 0 then list[#list + 1] = Tasks.menuItem() end -- near the top while something downloads
    for i = 1, table.maxn(items) do if items[i] then list[#list + 1] = items[i] end end -- drop hidden entries
    return list
end

--- ZenOS's Settings page (Home, Library, Reader, Interface, Extras, General,
--- KOReader). opts.path opens a section.
function HomeMenu.settings(opts)
    local f = fm()
    local zen = (f and f.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen then
        local okp, PluginLoader = pcall(require, "pluginloader")
        zen = okp and PluginLoader:getPluginInstance("zenos") or nil
    end
    local ok, Page = pcall(require, "modules/settings/zen_settings_page")
    if ok and zen then return Page.show(zen, opts) end
    HomeMenu.fullMenu()
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
    local okh, book = pcall(HomeMenu.highlighted)
    HomeMenu.context = okh and book or nil
    local menu
    menu = Menu:new{
        title = _("Menu"),
        item_table = HomeMenu.items(plugin),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        title_bar_fm_style = true,
        onMenuChoice = function(_m, item)
            UIManager:close(menu, "full")
            if item.callback then UIManager:nextTick(item.callback) end
            return true
        end,
        close_callback = function() HomeMenu.open = nil end,
    }
    menu.key_events = menu.key_events or {}
    menu.key_events.GzCloseHomeMenu = { { "Menu" } }
    menu.onGzCloseHomeMenu = function() UIManager:close(menu, "full"); return true end
    -- Back key too: full e-ink refresh, no ghost of the menu on the page
    menu.onCloseAllMenus = function(m)
        UIManager:close(m, "full")
        if m.close_callback then m.close_callback() end
        return true
    end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        HomeMenu.open = nil
        if orig_close then return orig_close(m, ...) end
    end
    HomeMenu.open = menu
    UIManager:show(menu, "full") -- full e-ink refresh: no ghosting from the page behind
    return true
end

return HomeMenu
