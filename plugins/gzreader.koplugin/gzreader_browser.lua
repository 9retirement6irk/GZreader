--[[--
Keyboard-friendly Grimmory library browser built on KOReader's Menu widget
(covers in book lists: gzreader_covermenu.lua).

Big libraries: a book list keeps at most MAX_PAGES pages of Grimmory's
results in memory ("Load more" drops the earliest, "Earlier books" brings
them back), and keeps only the fields GZreader uses of each book.
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

local Browser = {
    MAX_PAGES = 8, -- pages of a book list kept (8 x 25 = 200 books)
}
Browser.__index = Browser

-- what GZreader uses of a book (Grimmory sends ~40 fields: ratings, tags…)
local BOOK_FIELDS = { "id", "title", "authors", "primaryFileType", "primaryFileName", "primaryFileId",
    "fileSizeKb", "readProgress", "seriesName", "seriesNumber", "coverUpdatedOn", "libraryId", "isPhysical", "personalRating" }
local function slim(book)
    local out = {}
    for _i, k in ipairs(BOOK_FIELDS) do out[k] = book[k] end
    return out
end

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
    book = slim(book)
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

--- The Catalog tab (gzreader_catalog.lua): its pages are Books, Audiobooks
--- and Music; `opts.section` opens on another than Books.
function Browser:show(opts)
    -- the Notes or Calendar tab, if it's open underneath (ZenOS opens action tabs on top)
    pcall(function() require("gzreader_tabs").closeOthers(Browser.TAB_ID) end)
    Browser.current = self
    local Catalog = require("gzreader_catalog")
    local section = opts and opts.section
    self.section = (section and Catalog.step(Catalog.sections(), section, 0)) or "books"
    self.menu = Menu:new{
        title = Catalog.title(self.section),
        item_table = self:rootItems(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        -- ZenOS: show its tab bar with the Grimmory tab underlined
        _gz_navbar_tab_id = Browser.TAB_ID,
    }
    -- ZenOS's status bar (clock, battery, Wi-Fi) in the title, like other tabs
    pcall(self.decorate, self, Catalog.title(self.section))
    -- the pages: the strip under the title, turning at a page's ends
    pcall(Catalog.apply, self)
    -- book lists with covers (Menu → Display, as in Downloads)
    pcall(function() require("gzreader_covermenu").apply(self.menu, self.plugin) end)
    -- the first page as a bookshop in the Bookshelf view (gzreader_bookshop.lua)
    pcall(function() require("gzreader_bookshop").apply(self) end)
    -- the selection stays where it is when the page is drawn again (keys)
    pcall(function() require("gzreader_focus").apply(self.menu, require("device"):hasDPad()) end)
    local orig_switch = self.menu.switchItemTable
    self.menu.switchItemTable = function(m, title, ...)
        local r = orig_switch(m, title, ...)
        if title then pcall(self.decorate, self, title) end
        return r
    end
    -- the Music page: a download's progress line kept current (as in the Music tab)
    self.menu.onGzMusicDownload = function(m, st)
        if self.section ~= "music" then return end
        local ok, Tab = pcall(require, "gzreader_musictab")
        if ok and Tab.updateProgress(m.item_table, st) then m:updateItems(m.selected and m.selected.y or nil, true) end
    end
    -- Wi-Fi only when needed: keep it up while the browser is open
    local Net = require("gzreader_net")
    local net_key = "browser-" .. tostring(self)
    Net.hold(net_key)
    local orig_close = self.menu.onCloseWidget
    self.menu.onCloseWidget = function(m, ...)
        self.closed = true
        Net.release(net_key)
        if self.music_tab then self.music_tab.closed = true end
        if self.music_key then
            local Music = package.loaded["gzreader_music"]
            if Music and Music.listeners then Music.listeners[self.music_key] = nil end
        end
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
        -- (Menu:onClose goes back one list; KOReader's Menu has no onReturn:
        -- 1.12.2 and older crashed here on touch Kindles)
        back_callback = nested and function() menu:onClose() end or nil,
    })
    menu._gz_status_title = title
end

--- The page showing (Books, Audiobooks or Music): its first list.
function Browser:rootItems()
    local section = self.section or "books"
    local items
    -- (Browser.x(self): tests call this on a plain table)
    if section == "audiobooks" then items = Browser.audiobookItems(self)
    elseif section == "music" then items = Browser.musicItems(self)
    else items = Browser.bookItems(self) end
    items.gz_catalog = section
    return items
end

--- Turn to the page `dir` (+1, -1) from this one: false at an end.
function Browser:turnSection(dir)
    local Catalog = require("gzreader_catalog")
    local to = Catalog.step(Catalog.sections(), self.section or "books", dir)
    if not to or not self.menu then return false end
    self:openSection(to)
    return true
end

--- Show page `id`'s first list (the title says which).
function Browser:openSection(id)
    self.section = id
    local m = self.menu
    m._gz_shop_last = nil
    m.item_table_stack = {}
    m:switchItemTable(require("gzreader_catalog").title(id), self:rootItems())
end

--- The Books page. gz_id: what the bookshop (gzreader_bookshop.lua) draws
--- for each; gz_root marks the page.
function Browser:bookItems()
    return {
        gz_root = true,
        { gz_id = "search", gz_action = "search", text = _("Search Grimmory…"), callback = function() self:promptSearch() end },
        { gz_id = "continue", text = _("Continue reading"), callback = function() self:openSimple("continue-reading", _("Continue reading")) end },
        { gz_id = "recent", text = _("Recently added"), callback = function() self:openSimple("recently-added", _("Recently added")) end },
        { gz_id = "all", text = _("All books"), callback = function() self:openPaged(_("All books"), { sort = "title", dir = "asc" }) end },
        { gz_id = "libraries", text = _("Libraries"), callback = function() self:openLibraries() end },
        { gz_id = "shelves", text = _("Shelves"), callback = function() self:openShelves() end },
        { gz_id = "authors", text = _("Authors"), callback = function() self:openAuthors() end },
        { gz_id = "series", text = _("Series"), callback = function() self:openSeries() end },
        { gz_id = "downloaded", text = Browser.hereText(), callback = function() self:openDownloaded() end },
        -- (the next page, from the list: its letter on keyboard Kindles; the
        -- bookshop doesn't draw it. Only on Kindles with a speaker.)
        require("gzreader_touch").audio() and { gz_id = "audiobooks", text = _("Audiobooks"), callback = function() self:openSection("audiobooks") end } or nil,
    }
end

--- The Audiobooks page (Kindles with a speaker or headphone jack).
function Browser:audiobookItems()
    return {
        { gz_id = "ab_all", text = _("All audiobooks"), callback = function() self:openAudiobooks() end },
    }
end

--- The Music page: Plex (gzreader_musictab.lua's lists, here in the tab).
function Browser:musicItems()
    local MusicTab = require("gzreader_musictab")
    local tab = self.music_tab
    if not tab then
        tab = MusicTab.new(self.plugin)
        self.music_tab = tab
        -- (its lists go on this tab's Menu; Now playing / downloads change
        -- the Music page while it shows)
        tab.refreshRoot = function()
            if self.closed or self.section ~= "music" or not self.menu then return end
            if require("gzreader_catalog").atRoot(self.menu) then self:openSection("music") end
        end
        self.music_key = "catalog-" .. tostring(self)
        local okm, Music = pcall(require, "gzreader_music")
        if okm and Music.listeners then Music.listeners[self.music_key] = function() tab:refreshRoot() end end
    end
    tab.menu = self.menu
    tab.closed = false
    return tab:rootItems(function() self:openSection("music") end)
end

--- Grimmory's audiobooks (M4B / MP3), to download and listen to.
function Browser:openAudiobooks()
    local Audiobook = require("gzreader_audiobook")
    self:openList{
        title = _("Audiobooks"),
        key = "audiobooks",
        fetch = function(page)
            local sort, dir = Browser.sortParams()
            return self.api:listBooks{ page = page, size = PAGE_SIZE, sort = sort, dir = dir, fileType = { "AUDIOBOOK" } }
        end,
        reopen = function() self:openAudiobooks() end,
        to_item = function(book)
            local t = type(book.primaryFileType) == "string" and book.primaryFileType:upper() or ""
            if t ~= "AUDIOBOOK" then return nil end
            local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
            local here = Audiobook.load(self.plugin, book.id) ~= nil
            return {
                text = authors ~= "" and ((book.title or "?") .. " — " .. authors) or (book.title or "?"),
                book = book, cover_kind = "audiobook", -- the square audiobook cover in the cover views
                mandatory = here and _("on Kindle")
                    or (require("gzreader_usbsync").isQueued(self.plugin, book.id) and _("queued")) or nil,
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
        fetch = function()
            if endpoint == "continue-reading" then return self.api:continueReading(30) end
            return self.api:simpleList(endpoint, 30)
        end,
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
        -- (what's selected stays selected, if it's still in the list: gzreader_focus.lua)
        local okf, at = pcall(function() return require("gzreader_focus").carry(menu, items) end)
        menu:switchItemTable(opts.title, items, math.min(okf and at or first, #items))
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
    Net.run(fetch, { quiet = shown ~= nil, reason = "Grimmory library", usb = true })
end

---------------------------------------------------------------- paged lists

--- One page of Grimmory's results as menu items (to_item(entry) -> item or nil).
local function pageItems(spec, data)
    local list = {}
    for _, entry in ipairs(type(data.content) == "table" and data.content or {}) do
        local item = type(entry) == "table" and spec.to_item(entry) or nil
        if item then list[#list + 1] = item end
    end
    return list
end

--- A paged list as it's shown: its header, "Earlier books" when its first
--- pages were let go, the loaded pages' books, "Load more" while Grimmory has
--- more. st = { spec, pages = { [n] = items }, first, last, next_of, total }
function Browser:pagedItems(st)
    local spec, items = st.spec, {}
    for _, h in ipairs(spec.header or {}) do items[#items + 1] = h end
    local n_header = #items
    if st.first > 0 then
        items[#items + 1] = {
            text = T(_("Earlier books (page %1 of %2)…"), st.first, st.total or "?"), gz_action = "earlier",
            callback = function() self:loadPage(st, st.first - 1) end,
        }
    end
    for p = st.first, st.last do
        for _, it in ipairs(st.pages[p] or {}) do items[#items + 1] = it end
    end
    if st.next_of[st.last] then
        items[#items + 1] = {
            text = T(_("Load more (page %1 of %2)…"), st.last + 2, st.total or "?"), gz_action = "more",
            callback = function() self:loadPage(st, st.last + 1) end,
        }
    end
    if #items == n_header and n_header > 0 then
        -- (a search that found nothing: gz_kind "nothing_found", empty
        -- ledges with cobwebs in the Bookshelf view: gzreader_shopviews.lua)
        items[#items + 1] = { text = spec.empty_text or _("Nothing here yet."), select_enabled = false, gz_kind = spec.empty_kind }
    end
    items.gz_reopen = spec.reopen -- (a new sort order: opened again with it)
    return items
end

--- A new list state from Grimmory's first page.
function Browser:pagedState(spec, data)
    return { spec = spec, pages = { [0] = pageItems(spec, data) }, first = 0, last = 0,
        next_of = { [0] = data.hasNext == true }, total = tonumber(data.totalPages) }
end

--- spec = { title, fetch = function(page) -> data, err end, to_item, header, key, empty_text, empty_kind }
--- With a key, the first page is saved and shown at once next time.
function Browser:openList(spec)
    self:openCached{
        key = spec.key,
        title = spec.title,
        fetch = function() return spec.fetch(0) end,
        build = function(data) return self:pagedItems(self:pagedState(spec, data)) end,
    }
end

--- Load page `page` of a paged list (the one after the last, or before the
--- first) in the background, and show it. At most MAX_PAGES are kept: the
--- farthest one is let go (a Kindle's memory; 1.12.2 kept every page).
function Browser:loadPage(st, page)
    local msg = busy(_("Loading…"))
    require("gzreader_async").run(self.api, function() return st.spec.fetch(page) end, function(data, err)
        UIManager:close(msg)
        if self.closed or not self.menu then return end
        if not data then return self.plugin:showError(err) end
        local list = pageItems(st.spec, data)
        st.pages[page] = list
        st.next_of[page] = data.hasNext == true
        st.total = tonumber(data.totalPages) or st.total
        if page > st.last then
            st.last = page
            if st.last - st.first + 1 > Browser.MAX_PAGES then
                st.pages[st.first] = nil
                st.first = st.first + 1
            end
        else
            st.first = page
            if st.last - st.first + 1 > Browser.MAX_PAGES then
                st.pages[st.last] = nil
                st.last = st.last - 1
            end
        end
        local items = self:pagedItems(st)
        local at = #items
        for i, it in ipairs(items) do
            if it == list[1] then at = i; break end
        end
        self:replace(st.spec.title, items)
        -- go to the menu page holding the first book of the page just loaded
        local per_page = self.menu.perpage or PAGE_SIZE
        self.menu:onGotoPage(math.floor((at - 1) / per_page) + 1)
    end, "list")
end

--- Does Grimmory's answer look like a search for q: do most of the books
--- have it in their title, series or an author? (Not all: Grimmory also
--- lowercases letters like É, which Lua doesn't.)
local function matchesSearch(data, q)
    local list = type(data) == "table" and type(data.content) == "table" and data.content or {}
    if #list == 0 then return true end
    q = q:lower()
    local n = 0
    for _i, b in ipairs(list) do
        local hit = false
        if type(b) == "table" then
            hit = tostring(b.title or ""):lower():find(q, 1, true) or tostring(b.seriesName or ""):lower():find(q, 1, true)
            for _j, a in ipairs(type(b.authors) == "table" and b.authors or {}) do
                hit = hit or tostring(a):lower():find(q, 1, true)
            end
        end
        if hit then n = n + 1 end
    end
    return n * 2 >= #list
end
Browser.matchesSearch = matchesSearch

--- Books matching app-list filters (readable formats only).
--- opts = { search = q, header = items, empty_text }: a search's results.
---------------------------------------------------------------- sorting

--- How the Grimmory tab's book lists are sorted (Sort, in its menu): what
--- Grimmory itself can sort by (its app API). A series stays in its order.
Browser.SORTS = {
    { "title", _("Title"), "title", "asc" },
    { "added", _("Date added"), "addedOn", "desc" },
    { "lastread", _("Last read"), "lastReadTime", "desc" },
    { "series", _("Series"), "seriesName", "asc" },
    { "rating", _("Your rating"), "personalRating", "desc" },
    { "goodreads", _("Goodreads rating"), "goodreadsRating", "desc" },
    { "published", _("Publication date"), "publishedDate", "desc" },
    { "pages", _("Page count"), "pageCount", "asc" },
}

--- The chosen sort: Grimmory's sort field and direction.
function Browser.sortParams()
    local id = G_reader_settings:readSetting("gzreader_grimmory_sort") or "title"
    local def = Browser.SORTS[1]
    for _i, d in ipairs(Browser.SORTS) do if d[1] == id then def = d end end
    local dir = def[4]
    if G_reader_settings:isTrue("gzreader_grimmory_sort_reverse") then dir = dir == "asc" and "desc" or "asc" end
    return def[3], dir, def[1]
end

--- The open Grimmory tab, if it's on top (the Sort menu sorts it).
function Browser.onTop()
    local b = Browser.current
    if not (b and not b.closed and b.menu) then return nil end
    -- (under a dialog or the quick panel too: the full-screen one on top)
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w == b.menu then return b end
        if w and w.covers_fullscreen then return nil end
    end
    return nil
end

function Browser:showSort()
    local ButtonDialog = require("ui/widget/buttondialog")
    local cur = select(3, Browser.sortParams())
    local reverse = G_reader_settings:isTrue("gzreader_grimmory_sort_reverse")
    local dialog
    local function apply(id, rev)
        UIManager:close(dialog)
        G_reader_settings:saveSetting("gzreader_grimmory_sort", id)
        if rev ~= nil then G_reader_settings:saveSetting("gzreader_grimmory_sort_reverse", rev or nil) end
        self:resort()
    end
    local buttons = {}
    for _i, d in ipairs(Browser.SORTS) do
        buttons[#buttons + 1] = {{ text = (d[1] == cur and "✓ " or "") .. d[2], callback = function() apply(d[1]) end }}
    end
    buttons[#buttons + 1] = {{ text = (reverse and "✓ " or "") .. _("Reverse order"), callback = function() apply(cur, not reverse) end }}
    dialog = ButtonDialog:new{ title = _("Sort Grimmory's books by"), buttons = buttons }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
end

--- The list on screen again, in the new order (book lists; others as they are).
function Browser:resort()
    local m = self.menu
    local reopen = m and type(m.item_table) == "table" and m.item_table.gz_reopen
    if not reopen or #m.item_table_stack == 0 then return end
    -- back to the list it came from (not drawn), then the list opened again
    local prev = table.remove(m.item_table_stack)
    m.item_table = prev
    m.title = prev.title or m.title
    reopen()
end

function Browser:openPaged(title, params, with_series_number, opts)
    opts = opts or {}
    -- in the chosen order (a series in its own)
    local base_params = params
    if not with_series_number and not opts.keep_order then
        params = {}
        for k, v in pairs(base_params) do params[k] = v end
        params.sort, params.dir = Browser.sortParams()
    end
    local header = opts.header
    if not header and not with_series_number then
        -- search this list (a library, a shelf, an author's books…) or everything
        local scoped = params.libraryId or params.shelfId or params.magicShelfId or params.authors
        local scope = scoped and { title = title, params = params } or nil
        header = { {
            gz_action = "search",
            text = scope and T(_("Search in %1…"), title) or _("Search Grimmory…"),
            callback = function() self:promptSearch(scope) end,
        } }
    end
    self:openList{
        title = title,
        key = not opts.search and require("gzreader_listcache").key("paged", params) or nil,
        header = header,
        empty_text = opts.empty_text,
        empty_kind = opts.search and "nothing_found" or nil,
        reopen = function() self:openPaged(title, base_params, with_series_number, opts) end,
        fetch = function(page)
            local p = { page = page, size = PAGE_SIZE, fileType = self.api.READABLE_TYPES }
            for k, v in pairs(params) do p[k] = v end
            local data, err = self.api:listBooks(p)
            if data and opts.search and not matchesSearch(data, opts.search) then
                -- an older Grimmory that ignores search= in its book list:
                -- its own search instead (the whole library, newest first)
                return self.api:searchBooks(opts.search, page, PAGE_SIZE)
            end
            return data, err
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
        gz_action = "refresh",
        text = _("Refresh list from Grimmory"),
        callback = function()
            -- (a list opened from the saved index needs no Wi-Fi, so it may be
            -- off by now: "Wi-Fi only when needed" turns it off when idle)
            require("gzreader_net").run(function()
                Index.build(self.plugin, true, function(data, err)
                    if data then
                        table.remove(self.menu.item_table_stack) -- replace, don't stack
                        reopen()
                    else
                        self.plugin:showError(err)
                    end
                end)
            end, { reason = "refreshing the Grimmory list", usb = true })
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
                            gz_kind = "library", gz_count = n, -- (the bookshelf view: gzreader_shopviews.lua)
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
                        gz_kind = "shelf", gz_magic = sh.magic and true or nil, gz_count = tonumber(sh.bookCount),
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
                    gz_kind = "author", gz_count = n,
                    mandatory = countText(n),
                    callback = function()
                        self:openPaged(name, { authors = name, sort = "title", dir = "asc" })
                    end,
                }
            end
        end
        sortedByName(items)
        if not search then
            table.insert(items, 1, { gz_action = "search", text = _("Search authors…"), callback = function() self:promptAuthorSearch() end })
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

function Browser:openSeries(search)
    Index.get(self.plugin, function(index)
        local items = {}
        local needle = search and search:lower()
        for name, s in pairs(index.series or {}) do
            local authors = type(s.authors) == "table" and table.concat(s.authors, ", ") or ""
            -- (a series of one book isn't shown: it's just that book; 1.22.2)
            if (tonumber(s.count) or 0) >= 2
                    and (not needle or name:lower():find(needle, 1, true) or authors:lower():find(needle, 1, true)) then
                items[#items + 1] = {
                    text = authors ~= "" and (name .. " — " .. authors) or name,
                    sort_key = name:lower(),
                    gz_kind = "series", gz_name = name, gz_authors = authors, gz_count = s.count,
                    mandatory = countText(s.count),
                    callback = function()
                        -- filter rather than /series/{name}/books: names can contain "/"
                        self:openPaged(name, { series = name, sort = "seriesNumber", dir = "asc" }, true)
                    end,
                }
            end
        end
        sortedByName(items)
        if search then
            self:push(T(_("Series: %1"), search), items)
        else
            table.insert(items, 1, { gz_action = "search", text = _("Search series…"), callback = function() self:promptSeriesSearch() end })
            table.insert(items, 2, refreshItem(self, function() self:openSeries() end))
            self:push(_("Series"), items)
        end
    end)
end

function Browser:promptSeriesSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search series"),
        input_hint = _("Series or author name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = dialog:getInputText()
                UIManager:close(dialog)
                if q and q:match("%S") then self:openSeries(util.trim(q)) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Ask what to search for: in the whole library, or in `scope` = { title,
--- params } (a library, shelf or author's books). `text`: start with it.
function Browser:promptSearch(scope, text)
    local dialog
    dialog = InputDialog:new{
        title = scope and T(_("Search in %1"), scope.title) or _("Search Grimmory"),
        input = text,
        input_hint = _("Title, author or series"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = dialog:getInputText()
                UIManager:close(dialog)
                if q and q:match("%S") then self:search(util.trim(q), scope) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Grimmory's books whose title, series or an author contains q (readable
--- formats, A–Z, paged like All books), in the whole library or in `scope`.
function Browser:search(q, scope)
    local params = { search = q, sort = "title", dir = "asc" }
    for k, v in pairs(scope and scope.params or {}) do
        if k ~= "sort" and k ~= "dir" then params[k] = v end
    end
    local title = scope and T(_("%1: “%2”"), scope.title, q) or T(_("Search: %1"), q)
    self:openPaged(title, params, false, {
        search = q,
        header = { { gz_action = "search", text = _("Search again…"), callback = function() self:promptSearch(scope, q) end } },
        empty_text = T(_("No books found containing “%1”"), q),
    })
end

--- What's downloaded here is "On this Kindle" (on a Nook, "On this Nook"),
--- as on the Audiobooks and Music pages.
function Browser.hereText()
    local ok, Device = pcall(require, "device")
    if ok and type(Device) == "table" and Device.isNook and Device:isNook() then return _("On this Nook") end
    return _("On this Kindle")
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
    self:push(Browser.hereText(), items)
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
    local Usb = require("gzreader_usbsync")
    if Usb.isQueued(self.plugin, book.id) then
        -- (syncing through a computer)
        UIManager:show(ConfirmBox:new{
            text = T(_("“%1” is in the sync queue: it comes with the next sync with your computer."), name),
            ok_text = _("Take it off"), cancel_text = _("Keep"),
            ok_callback = function()
                Usb.dequeue(self.plugin, book.id)
                local menu = self.menu
                for _i, item in ipairs(menu and menu.item_table or {}) do
                    if item.book and tostring(item.book.id) == tostring(book.id) then item.mandatory = self:bookItem(item.book).mandatory end
                end
                if menu and menu.updateItems then menu:updateItems() end
            end,
        })
        return
    end
    if Download.isQueued(book.id) then
        UIManager:show(InfoMessage:new{ text = T(_("“%1” is already downloading or in the queue."), name), timeout = 3 })
        return
    end
    -- its page: cover, what it is, its description; Download, Download & open
    -- (gzreader_bookpage.lua); the old box if that fails
    local okp, page = pcall(function() return require("gzreader_bookpage").show(self, book) end)
    if okp and page then return end
    require("gzreader_log").warn("book page:", tostring(page))
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
