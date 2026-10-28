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

function Browser:bookItem(book)
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    local title = type(book.title) == "string" and book.title or _("Untitled")
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

function Browser:pagedItems(title, params, page, data)
    local items = {}
    for _, book in ipairs(type(data.content) == "table" and data.content or {}) do
        if type(book) == "table" and isReadable(book) then items[#items + 1] = self:bookItem(book) end
    end
    if data.hasNext == true then
        items[#items + 1] = {
            text = T(_("Load more (page %1 of %2)…"), page + 2, tonumber(data.totalPages) or "?"),
            callback = function() self:loadPage(title, params, page + 1, items) end,
        }
    end
    return items
end

function Browser:fetchPage(params, page)
    local p = { page = page, size = PAGE_SIZE, fileType = self.api.READABLE_TYPES }
    for k, v in pairs(params) do p[k] = v end
    return self.api:listBooks(p)
end

function Browser:openPaged(title, params)
    local msg = busy(_("Loading…"))
    local data, err = self:fetchPage(params, 0)
    UIManager:close(msg)
    if not data then return self.plugin:showError(err) end
    self:push(title, self:pagedItems(title, params, 0, data))
end

function Browser:loadPage(title, params, page, existing)
    local msg = busy(_("Loading…"))
    local data, err = self:fetchPage(params, page)
    UIManager:close(msg)
    if not data then return self.plugin:showError(err) end
    local items = {}
    for i = 1, #existing - 1 do items[i] = existing[i] end -- drop old "Load more"
    for _, item in ipairs(self:pagedItems(title, params, page, data)) do items[#items + 1] = item end
    local first_new = #existing
    self:replace(title, items)
    -- jump to the page that holds the first newly loaded book
    local per_page = self.menu.perpage or PAGE_SIZE
    self.menu:onGotoPage(math.floor((first_new - 1) / per_page) + 1)
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
