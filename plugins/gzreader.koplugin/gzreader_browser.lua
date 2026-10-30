--[[--
Keyboard-friendly Grimmory library browser built on KOReader's Menu widget.
Text-only (no cover thumbnails) to stay light on the Kindle Keyboard's RAM.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local PAGE_SIZE = 25
local Index = require("gzreader_index")

local Browser = {}
Browser.__index = Browser

function Browser:new(plugin)
    return setmetatable({ plugin = plugin, api = plugin.api }, self)
end

local function busy(text)
    local msg = InfoMessage:new{ text = text, timeout = 0 }
    UIManager:show(msg)
    UIManager:forceRePaint()
    return msg
end

local function isReadable(book)
    local t = type(book.primaryFileType) == "string" and book.primaryFileType:upper() or ""
    return book.isPhysical ~= true and t ~= "" and t ~= "AUDIOBOOK"
end

function Browser:errorText(err)
    return self.plugin:describeError(err)
end

local function seriesNumber(n)
    n = tonumber(n)
    if not n then return nil end
    return n == math.floor(n) and tostring(math.floor(n)) or tostring(n)
end

function Browser:bookItem(book, with_series_number)
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    local title = require("gzreader_titles").forBook(self.plugin, book) or _("Untitled")
    local num = with_series_number and seriesNumber(book.seriesNumber)
    if num then title = "#" .. num .. "  " .. title end
    local local_path = self.plugin:localPathFor(book.id)
    local fmt = type(book.primaryFileType) == "string" and book.primaryFileType or ""
    local progress = tonumber(book.readProgress)
    local tag = fmt
    if progress and progress > 0 then
        tag = T("%1 · %2%", tag, math.floor(progress + 0.5))
    end
    if local_path then
        tag = tag .. " · " .. _("on Kindle")
    elseif require("gzreader_download").isQueued(book.id) then
        tag = tag .. " · " .. _("queued")
    end
    return {
        text = authors ~= "" and (title .. " — " .. authors) or title,
        gz_title = title, -- the cover views show title and authors on their own lines
        mandatory = tag,
        book = book,
        callback = function() self:onBook(book) end,
    }
end

function Browser:show()
    -- the Notes tab, if it's open underneath (ZenOS opens action tabs on top)
    local Notes = package.loaded["gzreader_notes"] -- (never opened: nothing to close)
    if type(Notes) == "table" and Notes.closeOtherTabs then pcall(Notes.closeOtherTabs, Browser.TAB_ID) end
    self.menu = Menu:new{
        title = _("Grimmory"),
        item_table = self:rootItems(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        -- ZenOS: show its tab bar with the Grimmory tab underlined
        _gz_navbar_tab_id = Browser.TAB_ID,
    }
    -- ZenOS's status bar (clock, battery, Wi-Fi) in the title, like other tabs
    pcall(self.decorate, self, _("Grimmory"))
    -- book lists with covers (Menu → Display, as in Downloads)
    pcall(function() require("gzreader_covermenu").apply(self.menu, self.plugin) end)
    local orig_switch = self.menu.switchItemTable
    self.menu.switchItemTable = function(m, title, ...)
        local r = orig_switch(m, title, ...)
        if title then pcall(self.decorate, self, title) end
        return r
    end
    -- Wi-Fi only when needed: keep it up while the browser is open
    local Net = require("gzreader_net")
    local net_key = "browser-" .. tostring(self)
    Net.hold(net_key)
    local orig_close = self.menu.onCloseWidget
    self.menu.onCloseWidget = function(m, ...)
        self.closed = true
        Net.release(net_key)
        pcall(function() require("common/clock_timer").unbind(m) end)
        if orig_close then return orig_close(m, ...) end
    end
    -- GZreader: Alt + Q, W, E, R, T… (the Kindle Keyboard's 1-9) switch the
    -- bottom tabs, also from here. Plain letters stay the menu's item
    -- shortcuts (Q, W, E, R, T, Y, U, I, …).
    local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
    local row = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O" }
    self.menu.key_events = self.menu.key_events or {}
    self.menu.key_events.GzTabKey = { { digits }, { "Alt", digits }, { "Alt", row } }

    self.menu.onGzTabKey = function(menu, _args, key)
        UIManager:close(menu)
        UIManager:nextTick(function()
            local FileManager = require("apps/filemanager/filemanager")
            local fc = FileManager.instance and FileManager.instance.file_chooser
            if fc and fc.onKeyPress then fc:onKeyPress(key) end
        end)
        return true
    end
    UIManager:show(self.menu)
end

Browser.TAB_ID = "ct_grimmory"

--- Put ZenOS's status row (clock, battery, Wi-Fi, downloads) in the title
--- bar with `title` as its label, and a back arrow inside a sub-list.
function Browser:decorate(title)
    local menu = self.menu
    -- ZenOS: __ZEN_UI_PLUGIN is only set while ZenOS sets itself up, so
    -- after that the file manager's reference is the one to use (1.5.2: the
    -- status row never showed and the title kept KOReader's close button).
    local FileManager = require("apps/filemanager/filemanager")
    local zen = (FileManager.instance and FileManager.instance.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    if not (menu and menu.title_bar and zen) then return end
    local SharedState = require("common/shared_state")
    local createStatusRow = SharedState.get(zen, "createStatusRow")
    if type(createStatusRow) ~= "function" then return end -- status bar off
    local StandalonePage = require("modules/filebrowser/patches/standalone_page")
    local nested = #(menu.item_table_stack or {}) > 0
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = SharedState.get(zen, "createStatusRowCustomBack"),
        repaintTitleBar = SharedState.get(zen, "repaintTitleBar"),
        label = title,
        back_callback = nested and function() menu:onReturn() end or nil,
    })
    menu._gz_status_title = title
end

function Browser:rootItems()
    return {
        { text = _("Continue reading"), callback = function() self:openSimple("continue-reading", _("Continue reading")) end },
        { text = _("Recently added"), callback = function() self:openSimple("recently-added", _("Recently added")) end },
        { text = _("All books (A–Z)"), callback = function() self:openPaged(_("All books"), { sort = "title", dir = "asc" }) end },
        { text = _("Libraries"), callback = function() self:openLibraries() end },
        { text = _("Shelves"), callback = function() self:openShelves() end },
        { text = _("Authors"), callback = function() self:openAuthors() end },
        { text = _("Series"), callback = function() self:openSeries() end },
        { text = _("Search…"), callback = function() self:promptSearch() end },
        { text = _("Downloaded books"), callback = function() self:openDownloaded() end },
        { text = _("Audiobooks"), callback = function() self:openAudiobooks() end },
    }
end

--- Grimmory's audiobooks (M4B / MP3), to download and listen to.
function Browser:openAudiobooks()
    local Audiobook = require("gzreader_audiobook")
    self:openList{
        title = _("Audiobooks"),
        key = "audiobooks",
        fetch = function(page)
            return self.api:listBooks{ page = page, size = PAGE_SIZE, sort = "title", dir = "asc", fileType = { "AUDIOBOOK" } }
        end,
        to_item = function(book)
            local t = type(book.primaryFileType) == "string" and book.primaryFileType:upper() or ""
            if t ~= "AUDIOBOOK" then return nil end
            local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
            local here = Audiobook.load(self.plugin, book.id) ~= nil
            return {
                text = authors ~= "" and ((book.title or "?") .. " — " .. authors) or (book.title or "?"),
                book = book, cover_kind = "audiobook", -- the square audiobook cover in the cover views
                mandatory = here and _("on Kindle") or nil,
                callback = function() Audiobook.choose(self.plugin, book) end,
            }
        end,
    }
end

function Browser:push(title, items)
    if #items == 0 then
        items = { { text = _("Nothing here yet."), select_enabled = false } }
    end
    self.menu.item_table.title = self.menu.title
    table.insert(self.menu.item_table_stack, self.menu.item_table)
    self.menu:switchItemTable(title, items)
end

function Browser:replace(title, items)
    self.menu:switchItemTable(title, items)
end

function Browser:openSimple(endpoint, title)
    self:openCached{
        key = "simple:" .. endpoint,
        title = title,
        fetch = function() return self.api:simpleList(endpoint, 30) end,
        build = function(list)
            local items = {}
            for _, book in ipairs(type(list) == "table" and list or {}) do
                if type(book) == "table" and isReadable(book) then items[#items + 1] = self:bookItem(book) end
            end
            return items
        end,
    }
end

--- Show a list from the saved copy at once (if there is one), and fetch a
--- fresh one from Grimmory in the background to swap in.
--- opts = { key, title, fetch = function() -> data, err end, build = function(data) -> items }
--- Without a key nothing is saved (searches).
function Browser:openCached(opts)
    local Cache = require("gzreader_listcache")
    local Net = require("gzreader_net")
    local Async = require("gzreader_async")
    if opts.key then -- per server and account
        local store = self.plugin.store or {}
        opts.key = tostring(store.server) .. "|" .. tostring(store.username) .. "|" .. opts.key
    end
    local cached = opts.key and Cache.get(opts.key)
    local shown -- the item table on screen for this list
    if cached ~= nil then
        local ok, items = pcall(opts.build, cached)
        if ok and items then
            if #items == 0 then items = { { text = _("Nothing here yet."), select_enabled = false } } end
            items.gz_key = opts.key
            self:push(opts.title .. " · " .. _("saved"), items)
            shown = items
        end
    end
    local function apply(data, err)
        if data == nil then
            if not shown then return self.plugin:showError(err) end
            return -- keep the saved list
        end
        if opts.key then Cache.put(opts.key, data) end
        local items = opts.build(data)
        if not shown then return self:push(opts.title, items) end
        -- still looking at the saved copy? swap in the fresh one, same page
        local menu = self.menu
        if self.closed or not menu or menu.item_table ~= shown then return end
        if #items == 0 then items = { { text = _("Nothing here yet."), select_enabled = false } } end
        local per_page = menu.perpage or PAGE_SIZE
        local first = ((menu.page or 1) - 1) * per_page + 1
        menu:switchItemTable(opts.title, items, math.min(first, #items))
    end
    local function fetch()
        local msg = not shown and busy(_("Loading…")) or nil
        Async.run(self.api, function() return opts.fetch() end, function(data, err)
            if msg then UIManager:close(msg) end
            apply(data, err)
        end, opts.key or "list")
    end
    if Net.connected() then return fetch() end
    -- Wi-Fi off or still connecting: the saved copy now, fresh one once online
    Net.run(fetch, { quiet = shown ~= nil, reason = "Grimmory library" })
end

---------------------------------------------------------------- paged lists

--- Build menu items for one page of an AppPageResponse, appending to `prior`.
--- to_item(entry) returns a menu item or nil (skip). `header` items go first.
function Browser:listItems(spec, page, data, prior)
    local items = {}
    for i = 1, #prior do items[i] = prior[i] end
    if page == 0 then
        for _, h in ipairs(spec.header or {}) do items[#items + 1] = h end
    end
    for _, entry in ipairs(type(data.content) == "table" and data.content or {}) do
        local item = type(entry) == "table" and spec.to_item(entry) or nil
        if item then items[#items + 1] = item end
    end
    if data.hasNext == true then
        items[#items + 1] = {
            text = T(_("Load more (page %1 of %2)…"), page + 2, tonumber(data.totalPages) or "?"),
            callback = function() self:loadMore(spec, page + 1, items) end,
        }
    end
    return items
end

--- spec = { title, fetch = function(page) -> data, err end, to_item, header, key }
--- With a key, the first page is saved and shown at once next time.
function Browser:openList(spec)
    self:openCached{
        key = spec.key,
        title = spec.title,
        fetch = function() return spec.fetch(0) end,
        build = function(data) return self:listItems(spec, 0, data, {}) end,
    }
end

function Browser:loadMore(spec, page, existing)
    local msg = busy(_("Loading…"))
    local data, err = spec.fetch(page)
    UIManager:close(msg)
    if not data then return self.plugin:showError(err) end
    local prior = {}
    for i = 1, #existing - 1 do prior[i] = existing[i] end -- drop old "Load more"
    local first_new = #existing
    self:replace(spec.title, self:listItems(spec, page, data, prior))
    -- jump to the page that holds the first newly loaded entry
    local per_page = self.menu.perpage or PAGE_SIZE
    self.menu:onGotoPage(math.floor((first_new - 1) / per_page) + 1)
end

--- Books matching app-list filters (readable formats only).
function Browser:openPaged(title, params, with_series_number)
    self:openList{
        title = title,
        key = require("gzreader_listcache").key("paged", params),
        fetch = function(page)
            local p = { page = page, size = PAGE_SIZE, fileType = self.api.READABLE_TYPES }
            for k, v in pairs(params) do p[k] = v end
            return self.api:listBooks(p)
        end,
        to_item = function(book)
            if isReadable(book) then return self:bookItem(book, with_series_number) end
        end,
    }
end

local function countText(n)
    n = tonumber(n)
    if not n then return nil end
    return n == 1 and _("1 book") or T(_("%1 books"), n)
end

local function sortedByName(list)
    table.sort(list, function(x, y) return x.sort_key < y.sort_key end)
    return list
end

local function refreshItem(self, reopen)
    return {
        text = _("Refresh list from Grimmory"),
        callback = function()
            Index.build(self.plugin, true, function(data, err)
                if data then
                    table.remove(self.menu.item_table_stack) -- replace, don't stack
                    reopen()
                else
                    self.plugin:showError(err)
                end
            end)
        end,
    }
end

function Browser:openLibraries()
    self:openCached{
        key = "libraries",
        title = _("Libraries"),
        fetch = function() return self.api:listLibraries() end,
        build = function(libs)
            -- book counts from the saved library index (no network here)
            local index = Index.load(self.plugin.store)
            local counts = index and index.libraries or {}
            local items = {}
            for _, lib in ipairs(type(libs) == "table" and libs or {}) do
                if type(lib) == "table" and lib.id then
                    local n = counts[tostring(lib.id)]
                    if not index or (n and n > 0) then -- hide audiobook-only libraries
                        local name = type(lib.name) == "string" and lib.name or T(_("Library %1"), lib.id)
                        items[#items + 1] = {
                            text = name,
                            sort_key = name:lower(),
                            mandatory = countText(n),
                            callback = function()
                                self:openPaged(name, { libraryId = lib.id, sort = "title", dir = "asc" })
                            end,
                        }
                    end
                end
            end
            return sortedByName(items)
        end,
    }
end

--- Shelves and magic shelves from Grimmory.
function Browser:openShelves()
    self:openCached{
        key = "shelves",
        title = _("Shelves"),
        fetch = function() return self.api:listShelves() end,
        build = function(shelves)
            local items = {}
            for _i, sh in ipairs(type(shelves) == "table" and shelves or {}) do
                if type(sh) == "table" and sh.id then
                    local name = type(sh.name) == "string" and sh.name or T(_("Shelf %1"), sh.id)
                    items[#items + 1] = {
                        text = name,
                        sort_key = (sh.magic and "1" or "0") .. name:lower(),
                        mandatory = sh.magic and _("smart shelf") or countText(sh.bookCount),
                        callback = function()
                            local params = { sort = "title", dir = "asc" }
                            if sh.magic then params.magicShelfId = sh.id else params.shelfId = sh.id end
                            self:openPaged(name, params)
                        end,
                    }
                end
            end
            return sortedByName(items)
        end,
    }
end

function Browser:openAuthors(search, replace)
    Index.get(self.plugin, function(index)
        local items = {}
        local needle = search and search:lower()
        for name, n in pairs(index.authors or {}) do
            if not needle or name:lower():find(needle, 1, true) then
                items[#items + 1] = {
                    text = name,
                    sort_key = name:lower(),
                    mandatory = countText(n),
                    callback = function()
                        self:openPaged(name, { authors = name, sort = "title", dir = "asc" })
                    end,
                }
            end
        end
        sortedByName(items)
        if not search then
            table.insert(items, 1, { text = _("Search authors…"), callback = function() self:promptAuthorSearch() end })
            table.insert(items, 2, refreshItem(self, function() self:openAuthors() end))
        end
        local title = search and T(_("Authors: %1"), search) or _("Authors")
        if replace then self:replace(title, items) else self:push(title, items) end
    end)
end

function Browser:promptAuthorSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search authors"),
        input_hint = _("Author name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = dialog:getInputText()
                UIManager:close(dialog)
                if q and q:match("%S") then self:openAuthors(q) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:openSeries()
    Index.get(self.plugin, function(index)
        local items = {}
        for name, s in pairs(index.series or {}) do
            local authors = type(s.authors) == "table" and table.concat(s.authors, ", ") or ""
            items[#items + 1] = {
                text = authors ~= "" and (name .. " — " .. authors) or name,
                sort_key = name:lower(),
                mandatory = countText(s.count),
                callback = function()
                    -- filter rather than /series/{name}/books: names can contain "/"
                    self:openPaged(name, { series = name, sort = "seriesNumber", dir = "asc" }, true)
                end,
            }
        end
        sortedByName(items)
        table.insert(items, 1, refreshItem(self, function() self:openSeries() end))
        self:push(_("Series"), items)
    end)
end

function Browser:promptSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search Grimmory"),
        input_hint = _("Title, author, series…"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = dialog:getInputText()
                UIManager:close(dialog)
                if q and q:match("%S") then self:search(q) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Browser:search(q, data, err)
    if data == nil and err == nil then
        local msg = busy(_("Searching…"))
        return require("gzreader_async").call(self.api, "searchBooks", { q, 0, 40 }, function(d, e)
            UIManager:close(msg)
            self:search(q, d or false, e or "unreachable")
        end)
    end
    if not data then return self.plugin:showError(err) end
    local items = {}
    local list = type(data.content) == "table" and data.content or data
    for _, book in ipairs(type(list) == "table" and list or {}) do
        if type(book) == "table" and isReadable(book) then items[#items + 1] = self:bookItem(book) end
    end
    self:push(T(_("Search: %1"), q), items)
end

function Browser:openDownloaded()
    local items = {}
    for id, entry in pairs(self.plugin.store.downloads or {}) do
        if type(entry) == "table" and entry.path and lfs.attributes(entry.path, "mode") == "file" then
            items[#items + 1] = {
                text = (entry.title and require("gzreader_titles").full(entry.title, require("gzreader_titles").subtitle(self.plugin, id)))
                    or entry.path:match("[^/]+$"),
                mandatory = entry.format,
                callback = function() self.plugin:openBook(entry.path, self.menu) end,
                id = id,
            }
        end
    end
    table.sort(items, function(a, b) return a.text:lower() < b.text:lower() end)
    self:push(_("Downloaded books"), items)
end

function Browser:onBook(book)
    local path = self.plugin:localPathFor(book.id)
    if path then
        return self.plugin:openBook(path, self.menu)
    end
    local size_kb = tonumber(book.fileSizeKb)
    local size = size_kb and (size_kb >= 1024 and T("%1 MB", string.format("%.1f", size_kb / 1024)) or T("%1 KB", size_kb)) or ""
    local Download = require("gzreader_download")
    local name = require("gzreader_titles").forBook(self.plugin, book) or ""
    if Download.isQueued(book.id) then
        UIManager:show(InfoMessage:new{ text = T(_("“%1” is already downloading or in the queue."), name), timeout = 3 })
        return
    end
    local dl_busy = Download.active ~= nil
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    local box = ConfirmBox:new{
        text = T(_("Download “%1” to this Kindle?"), name) .. (authors ~= "" and ("\n" .. authors) or "")
            .. (size ~= "" and ("\n" .. size) or "")
            .. (dl_busy and ("\n\n" .. T(_("Another download is running; this one is queued (%1 waiting)."), #Download.queue)) or ""),
        ok_text = dl_busy and _("Add to queue") or _("Download & open"),
        ok_callback = function()
            self.plugin:downloadAndOpen(book, self.menu)
            if dl_busy then self:markQueued(book) end
        end,
    }
    self:showWithCover(box, book)
end

--- Grimmory's cover, cached on the Kindle (cache/gzreader-thumbs).
function Browser.thumbPath(book)
    local DataStorage = require("datastorage")
    local dir = DataStorage:getDataDir() .. "/cache/gzreader-thumbs"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(dir)
    end
    local stamp = tostring(book.coverUpdatedOn or ""):gsub("[^%w]", "")
    return string.format("%s/%s-%s.jpg", dir, tostring(book.id), stamp ~= "" and stamp or "0")
end

--- Show the box now; add the book's cover to it as soon as it's here
--- (from the cache at once, otherwise fetched in the background).
function Browser:showWithCover(box, book)
    local path = Browser.thumbPath(book)
    local closed = false
    local orig_close = box.onCloseWidget
    box.onCloseWidget = function(b, ...)
        closed = true
        if orig_close then return orig_close(b, ...) end
    end
    local function addCover()
        return pcall(function()
            local ImageWidget = require("ui/widget/imagewidget")
            local Screen = require("device").screen
            local want = Screen:scaleBySize(180)
            if type(want) ~= "number" then want = 180 end
            local w = math.min(box:getAddedWidgetAvailableWidth(), want)
            box:addWidget(ImageWidget:new{
                file = path, width = w, height = math.floor(w * 1.4), scale_factor = 0, file_do_cache = false,
            })
        end)
    end
    if lfs.attributes(path, "size") and addCover() then
        return UIManager:show(box)
    end
    UIManager:show(box)
    if not book.id then return end
    require("gzreader_async").call(self.api, "downloadThumbnail", { book.id, path }, function(ok)
        if not ok or closed then return end
        if addCover() then UIManager:setDirty("all", "ui") end
    end)
end

--- Show "queued" next to a book in the open list.
function Browser:markQueued(book)
    local menu = self.menu
    if not menu or type(menu.item_table) ~= "table" then return end
    for _i, item in ipairs(menu.item_table) do
        if item.book and tostring(item.book.id) == tostring(book.id) and not tostring(item.mandatory or ""):find(_("queued"), 1, true) then
            item.mandatory = (item.mandatory and item.mandatory ~= "" and (item.mandatory .. " · ") or "") .. _("queued")
            if menu.updateItems then menu:updateItems() end
        end
    end
end

Browser.isReadable = isReadable
Browser.util = util
return Browser
