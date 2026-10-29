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
    local title = type(book.title) == "string" and book.title or _("Untitled")
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
    end
    return {
        text = authors ~= "" and (title .. " — " .. authors) or title,
        mandatory = tag,
        book = book,
        callback = function() self:onBook(book) end,
    }
end

function Browser:show()
    self.menu = Menu:new{
        title = _("Grimmory"),
        item_table = self:rootItems(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
    }
    UIManager:show(self.menu)
end

function Browser:rootItems()
    return {
        { text = _("Continue reading"), callback = function() self:openSimple("continue-reading", _("Continue reading")) end },
        { text = _("Recently added"), callback = function() self:openSimple("recently-added", _("Recently added")) end },
        { text = _("All books (A–Z)"), callback = function() self:openPaged(_("All books"), { sort = "title", dir = "asc" }) end },
        { text = _("Libraries"), callback = function() self:openLibraries() end },
        { text = _("Authors"), callback = function() self:openAuthors() end },
        { text = _("Series"), callback = function() self:openSeries() end },
        { text = _("Search…"), callback = function() self:promptSearch() end },
        { text = _("Downloaded books"), callback = function() self:openDownloaded() end },
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
    local msg = busy(_("Loading…"))
    local list, err = self.api:simpleList(endpoint, 30)
    UIManager:close(msg)
    if not list then return self.plugin:showError(err) end
    local items = {}
    for _, book in ipairs(list) do
        if type(book) == "table" and isReadable(book) then items[#items + 1] = self:bookItem(book) end
    end
    self:push(title, items)
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

--- spec = { title, fetch = function(page) -> data, err end, to_item, header }
function Browser:openList(spec)
    local msg = busy(_("Loading…"))
    local data, err = spec.fetch(0)
    UIManager:close(msg)
    if not data then return self.plugin:showError(err) end
    self:push(spec.title, self:listItems(spec, 0, data, {}))
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

function Browser:openLibraries()
    local msg = busy(_("Loading…"))
    local libs, err = self.api:listLibraries()
    UIManager:close(msg)
    if not libs then return self.plugin:showError(err) end
    local items = {}
    for _, lib in ipairs(libs) do
        if type(lib) == "table" and lib.id then
            local name = type(lib.name) == "string" and lib.name or T(_("Library %1"), lib.id)
            items[#items + 1] = {
                text = name,
                mandatory = countText(lib.bookCount),
                callback = function()
                    self:openPaged(name, { libraryId = lib.id, sort = "title", dir = "asc" })
                end,
            }
        end
    end
    table.sort(items, function(x, y) return x.text:lower() < y.text:lower() end)
    self:push(_("Libraries"), items)
end

function Browser:openAuthors(search)
    local title = search and T(_("Authors: %1"), search) or _("Authors")
    self:openList{
        title = title,
        header = not search and {
            { text = _("Search authors…"), callback = function() self:promptAuthorSearch() end },
        } or nil,
        fetch = function(page)
            return self.api:listAuthors{ page = page, size = 50, sort = "name", dir = "asc", search = search }
        end,
        to_item = function(author)
            local name = type(author.name) == "string" and author.name or nil
            if not name then return nil end
            return {
                text = name,
                mandatory = countText(author.bookCount),
                callback = function()
                    self:openPaged(name, { authors = name, sort = "title", dir = "asc" })
                end,
            }
        end,
    }
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
    self:openList{
        title = _("Series"),
        fetch = function(page)
            return self.api:listSeries{ page = page, size = 50, sort = "name", dir = "asc" }
        end,
        to_item = function(series)
            local name = type(series.seriesName) == "string" and series.seriesName or nil
            if not name then return nil end
            local count = tonumber(series.bookCount)
            local total = tonumber(series.seriesTotal)
            local info = count and (total and total > count and T(_("%1 of %2"), count, total) or countText(count)) or nil
            local authors = type(series.authors) == "table" and table.concat(series.authors, ", ") or ""
            return {
                text = authors ~= "" and (name .. " — " .. authors) or name,
                mandatory = info,
                callback = function()
                    -- filter rather than /series/{name}/books: names can contain "/"
                    self:openPaged(name, { series = name, sort = "seriesNumber", dir = "asc" }, true)
                end,
            }
        end,
    }
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

function Browser:search(q)
    local msg = busy(_("Searching…"))
    local data, err = self.api:searchBooks(q, 0, 40)
    UIManager:close(msg)
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
                text = entry.title or entry.path:match("[^/]+$"),
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
    UIManager:show(ConfirmBox:new{
        text = T(_("Download “%1” to this Kindle?"), book.title or "") .. (size ~= "" and ("\n" .. size) or ""),
        ok_text = _("Download & open"),
        ok_callback = function()
            self.plugin:downloadAndOpen(book, self.menu)
        end,
    })
end

Browser.isReadable = isReadable
Browser.util = util
return Browser
