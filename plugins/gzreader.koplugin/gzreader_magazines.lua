--[[--
Magazines: one library on the book server (Grimmory or BookOrbit) chosen as
the magazine library, in Settings → Accounts and services → Books. Then the
Catalog has a Magazines page (gzreader_catalog.lua) showing only that
library's books, drawn as a magazine stand (gzreader_magstand.lua), and the
Books page leaves them out: its lists, its counts (the library index), its
Libraries list and its searches.

The choice is kept per server and account (store.magazines = { server, user,
id, name }): signed in elsewhere, there's no Magazines page until one is
chosen there.

Which books are magazines: a book whose libraryId is the magazine library's
(Grimmory's lists say), or one of the library's books by id (BookOrbit's lists
don't say a book's library: the ids come from the library index, which lists
the magazine library's books, and from the stand's own list of issues).

An issue's title (the magazine it's an issue of): its series when it has one,
else its title up to " - ", " – ", " — " or ": " ("Wired - November 2026" is
Wired), else its whole title.
]]

local Mag = {
    PAGE = 50,       -- (Grimmory's most a page)
    STAND_PAGES = 4, -- the stand's issues: the newest 200
    ALL_PAGES = 100, -- the index's ids: up to 5,000 issues
}

local function current(store)
    local m = type(store) == "table" and store.magazines
    if type(m) ~= "table" or m.id == nil then return nil end
    if m.server ~= store.server or m.user ~= store.username then return nil end
    return m
end

--- The magazine library chosen for the server and account signed in now:
--- { id, name }, or nil.
function Mag.get(plugin)
    return current(type(plugin) == "table" and plugin.store)
end

--- The same, from the store alone (the library index's check).
function Mag.fromStore(store) return current(store) end

--- Its id as text ("" when there's none): what the library index was built for.
function Mag.key(store)
    local m = current(store)
    return m and tostring(m.id) or ""
end

--- Choose `lib` ({ id, name }) as the magazine library, or none (nil).
function Mag.set(plugin, lib)
    local store = plugin.store
    if lib and lib.id ~= nil then
        store.magazines = { server = store.server, user = store.username, id = lib.id,
            name = type(lib.name) == "string" and lib.name or tostring(lib.id) }
    else
        store.magazines = nil
    end
    Mag.forget()
    if type(plugin.save) == "function" then pcall(plugin.save, plugin) end
end

---------------------------------------------------------------- choosing it

--- Settings → Accounts and services → Books → Magazines: the server's
--- libraries to choose from (and Off). on_done() after a choice.
function Mag.choose(plugin, on_done)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    local msg = InfoMessage:new{ text = _("Loading…") }
    UIManager:show(msg)
    require("gzreader_net").run(function()
        require("gzreader_async").run(plugin.api, function() return plugin.api:listLibraries() end, function(libs, err)
            UIManager:close(msg)
            if type(libs) ~= "table" then return plugin:showError(err) end
            local ButtonDialog = require("ui/widget/buttondialog")
            local cur = Mag.get(plugin)
            local dialog
            local function pick(lib)
                UIManager:close(dialog)
                Mag.set(plugin, lib)
                Mag.changed(plugin)
                if on_done then on_done() end
            end
            local buttons = {}
            local sorted = {}
            for _i, lib in ipairs(libs) do
                if type(lib) == "table" and lib.id ~= nil then sorted[#sorted + 1] = lib end
            end
            table.sort(sorted, function(a, b) return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end)
            for _i, lib in ipairs(sorted) do
                local name = type(lib.name) == "string" and lib.name or tostring(lib.id)
                local on = cur and tostring(cur.id) == tostring(lib.id)
                buttons[#buttons + 1] = {{ text = (on and "✓ " or "") .. name, callback = function() pick({ id = lib.id, name = name }) end }}
            end
            buttons[#buttons + 1] = {{ text = (cur and "" or "✓ ") .. _("Off: no Magazines page"), callback = function() pick(nil) end }}
            dialog = ButtonDialog:new{ title = _("Which library holds your magazines?"), buttons = buttons }
            local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
            if add then pcall(add, dialog) end
            UIManager:show(dialog)
        end, "libraries")
    end, { reason = "magazine library", usb = true })
end

--- After a new choice: the library index again (its counts leave the
--- magazines out, or count them again), quietly, and an open Catalog shows
--- the pages it has now.
function Mag.changed(plugin)
    local Log = require("gzreader_log")
    local m = Mag.get(plugin)
    Log.info("magazines: library", m and tostring(m.id) or "off")
    pcall(function() require("gzreader_index").data = nil end)
    pcall(function()
        require("gzreader_net").run(function() require("gzreader_index").build(plugin, false, nil) end,
            { quiet = true, reason = "magazine library", usb = true })
    end)
    local B = package.loaded["gzreader_browser"]
    local b = B and B.current
    if b and not b.closed and b.menu then
        if b.section == "magazines" and not m then b.section = "books" end
        b._shop, b._stand = nil, nil
        pcall(b.openSection, b, b.section or "books")
    end
end

---------------------------------------------------------------- which books

Mag.stand_ids = nil -- { [id as text] = true } from the stand's issues (this run)

function Mag.forget() Mag.stand_ids = nil end

--- The magazine library's book ids known now ({ [id as text] = true }).
function Mag.ids(plugin)
    local out = {}
    local ok, idx = pcall(function() return require("gzreader_index").load(plugin.store) end)
    local m = ok and type(idx) == "table" and idx.magazines
    for _i, id in ipairs(type(m) == "table" and type(m.ids) == "table" and m.ids or {}) do out[tostring(id)] = true end
    for id in pairs(Mag.stand_ids or {}) do out[id] = true end
    return out
end

--- Is `book` one of the magazines (to leave out of the Books page)?
--- `ids`: Mag.ids(plugin), when asking for many books.
function Mag.isMagazine(plugin, book, ids)
    local m = Mag.get(plugin)
    if not m or type(book) ~= "table" then return false end
    if book.libraryId ~= nil and tostring(book.libraryId) == tostring(m.id) then return true end
    ids = ids or Mag.ids(plugin)
    return book.id ~= nil and ids[tostring(book.id)] == true
end

--- For a list on the Books page with these params: a function telling the
--- books to leave out, or nil (no magazine library, or the list is the
--- magazine library's own: its page, a search in it).
function Mag.hider(plugin, params)
    local m = Mag.get(plugin)
    if not m then return nil end
    if type(params) == "table" and params.libraryId ~= nil and tostring(params.libraryId) == tostring(m.id) then return nil end
    local ids = Mag.ids(plugin)
    return function(book) return Mag.isMagazine(plugin, book, ids) end
end

---------------------------------------------------------------- titles

local SEPARATORS = { " - ", " – ", " — ", ": " }

--- The magazine an issue is of.
function Mag.titleOf(book)
    if type(book) ~= "table" then return "?" end
    if type(book.seriesName) == "string" and book.seriesName:match("%S") then return book.seriesName end
    local title = type(book.title) == "string" and book.title or "?"
    local cut
    for _i, sep in ipairs(SEPARATORS) do
        local at = title:find(sep, 1, true)
        if at and at > 1 and (not cut or at < cut) then cut = at end
    end
    if cut then title = title:sub(1, cut - 1) end
    return (title:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- The issues grouped by magazine, in the issues' order (newest first when
--- they come that way): { { name, issues = { … } }, … }, the magazine with
--- the newest issue first.
function Mag.groups(issues)
    local out, by = {}, {}
    for _i, b in ipairs(type(issues) == "table" and issues or {}) do
        if type(b) == "table" and b.id ~= nil then
            local name = Mag.titleOf(b)
            local key = name:lower()
            local g = by[key]
            if not g then
                g = { name = name, issues = {} }
                by[key] = g
                out[#out + 1] = g
            end
            g.issues[#g.issues + 1] = b
        end
    end
    return out
end

---------------------------------------------------------------- from the server

--- The library's issues, newest first, up to `pages` pages (a background
--- process: api:listBooks). Returns the list, its total, or nil and the error.
function Mag.fetch(api, id, pages)
    local out, total = {}, nil
    local page, last = 0, 1
    pages = pages or Mag.STAND_PAGES
    while page < last and page < pages do
        local data, err = api:listBooks{ page = page, size = Mag.PAGE, sort = "addedOn", dir = "desc",
            libraryId = id, fileType = api.READABLE_TYPES }
        if not data then
            if page == 0 then return nil, err end
            break
        end
        last = tonumber(data.totalPages) or 1
        total = tonumber(data.totalElements) or total
        for _i, b in ipairs(type(data.content) == "table" and data.content or {}) do
            if type(b) == "table" and b.id ~= nil then out[#out + 1] = b end
        end
        page = page + 1
    end
    return out, total or #out
end

--- Recently added without the magazines (a background process): the server's
--- own list could be all new issues, so the books newest first, a page at a
--- time, the magazines left out, until there are `limit` (or 3 pages were read).
function Mag.recent(api, hide, limit)
    local out = {}
    for page = 0, 2 do
        local data, err = api:listBooks{ page = page, size = Mag.PAGE, sort = "addedOn", dir = "desc", fileType = api.READABLE_TYPES }
        if not data then
            if page == 0 then return nil, err end
            break
        end
        for _i, b in ipairs(type(data.content) == "table" and data.content or {}) do
            if #out >= limit then break end
            if type(b) == "table" and not hide(b) then out[#out + 1] = b end
        end
        if #out >= limit or not data.hasNext then break end
    end
    return out
end

--- Every id in the library (for the library index; a background process).
function Mag.allIds(api, id)
    local list = Mag.fetch(api, id, Mag.ALL_PAGES)
    if not list then return nil end
    local ids = {}
    for _i, b in ipairs(list) do ids[#ids + 1] = b.id end
    return ids
end

--- The stand's issues were fetched: their ids count as magazines from now on.
function Mag.noteIssues(issues)
    Mag.stand_ids = Mag.stand_ids or {}
    for _i, b in ipairs(type(issues) == "table" and issues or {}) do
        if type(b) == "table" and b.id ~= nil then Mag.stand_ids[tostring(b.id)] = true end
    end
end

return Mag
