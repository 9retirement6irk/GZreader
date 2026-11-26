--[[--
Auto-download a Grimmory shelf ("Send to Kindle").

Pick one of your Grimmory shelves (or smart shelves) in Settings → Accounts and services → Books.
Books added to it there download to this Kindle by themselves: when Wi-Fi
connects (at most every 30 minutes) and with "Download new books from the
shelf now". They go through the download queue in the background. Books
taken off the shelf are left on the Kindle, unless:

- Mirror the shelf (off by default): a book the shelf brought (or that was
  on the Kindle while on the shelf) and is then taken off it moves into the
  books folder's "Taken off the shelf" folder, with its reading position;
  put back on the shelf, it moves back. Nothing is deleted. Only when the
  whole shelf was read (not cut short), and never the book that's open.
- Keep books up to date (off by default): a book on the shelf whose title
  or authors changed on the server gets them on the Kindle too (as Book
  information's edit does; a title you changed yourself is left alone), and
  one whose file changed there (another file, or a different size: its
  metadata written into it, say) is downloaded again over the old one,
  keeping its reading position.

Idea from Shelf Sync (krisboho/connecto-library), written for GZreader.
]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local ShelfSync = { EVERY = 30 * 60, PAGE = 50, MAX_PAGES = 40 }

function ShelfSync.shelf(plugin) return plugin.store.auto_shelf end

function ShelfSync.set(plugin, shelf)
    plugin.store.auto_shelf = shelf and { id = shelf.id, magic = shelf.magic == true, name = shelf.name } or nil
    plugin.store.auto_shelf_last = nil
    plugin:save()
end

local function fields(b)
    return { id = b.id, title = b.title, authors = b.authors, primaryFileName = b.primaryFileName,
        primaryFileType = b.primaryFileType, primaryFileId = b.primaryFileId, fileSizeKb = b.fileSizeKb,
        isPhysical = b.isPhysical }
end
ShelfSync.fields = fields

ShelfSync.TRASH = "Taken off the shelf"

function ShelfSync.mirrorOn(plugin) return plugin.store.auto_shelf_mirror == true end
function ShelfSync.refreshOn(plugin) return plugin.store.auto_shelf_refresh == true end

--- The folder books taken off the shelf go to.
function ShelfSync.trashDir(plugin) return plugin:downloadDir() .. "/" .. ShelfSync.TRASH end

local function openPath()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok and ReaderUI.instance
    return ui and ui.document and ui.document.file or nil
end

--- Move a book's file (and its reading position, history) from `from` to `to`.
function ShelfSync.move(from, to)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(to, "mode") then return false, "exists" end
    local ok, err = os.rename(from, to)
    if not ok then return false, err end
    pcall(function() require("docsettings").updateLocation(from, to) end)
    pcall(function() require("readhistory"):updateItem(from, to) end)
    return true
end

--- Mirror the shelf: books it brought that are no longer on it moved to
--- the trash folder, and back when they're on it again. `ids`: { [id] = true }
--- on the shelf now. Returns moved off, moved back.
function ShelfSync.mirror(plugin, ids)
    local lfs = require("libs/libkoreader-lfs")
    local got = plugin.store.auto_shelf_got or {}
    plugin.store.auto_shelf_got = got
    local trash = ShelfSync.trashDir(plugin)
    local open = openPath()
    local off, back = 0, 0
    for id, e in pairs(plugin.store.downloads or {}) do
        local path = type(e) == "table" and e.path
        if path and lfs.attributes(path, "mode") == "file" and path ~= open then
            local name = path:match("[^/]+$")
            local in_trash = path:sub(1, #trash + 1) == trash .. "/"
            if ids[id] and in_trash then
                -- on the shelf again: back where downloads go
                local to = plugin:downloadDir() .. "/" .. name
                if ShelfSync.move(path, to) then e.path = to; back = back + 1 end
            elseif not ids[id] and got[id] and not in_trash then
                if lfs.attributes(trash, "mode") ~= "directory" then lfs.mkdir(trash) end
                local to = trash .. "/" .. name
                if ShelfSync.move(path, to) then e.path = to; off = off + 1 end
            end
        end
    end
    return off, back
end

--- Keep the shelf's books on the Kindle up to date: titles and authors
--- changed on the server written as the book's metadata; a changed file
--- downloaded again. `books`: the shelf's. Returns titles changed, files queued.
function ShelfSync.refresh(plugin, books)
    local open = openPath()
    local titled, queued = 0, 0
    for _i, b in ipairs(books) do
        local id = tostring(b.id)
        local e = plugin.store.downloads and plugin.store.downloads[id]
        local path = plugin:localPathFor(b.id)
        if type(e) == "table" and path and path ~= open then
            -- the title and authors
            local authors = type(b.authors) == "table" and #b.authors > 0 and table.concat(b.authors, "\n") or nil
            local title = type(b.title) == "string" and b.title ~= "" and b.title or nil
            if (title and title ~= e.title) or (authors and e.authors and authors ~= e.authors) then
                if ShelfSync.applyMetadata(path, title or e.title, authors) then titled = titled + 1 end
                e.title, e.authors = title or e.title, authors or e.authors
            end
            -- the file: another one, or a different size, since it was last seen
            local fid, kb = tonumber(b.primaryFileId), tonumber(b.fileSizeKb)
            local changed = (fid and e.file_id and fid ~= e.file_id) or (kb and e.size_kb and kb ~= e.size_kb)
            if changed and not require("gzreader_download").isQueued(b.id) then
                queued = queued + 1
                local book = {}
                for k, v in pairs(b) do book[k] = v end
                book.gz_quiet = true
                require("gzreader_download").start(plugin, book, path, function(ok)
                    if not ok then return end
                    e.file_id, e.size_kb = fid or e.file_id, kb or e.size_kb
                    plugin:save()
                    pcall(function()
                        local Event = require("ui/event")
                        UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", path))
                        UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
                    end)
                    Log.info("shelf sync: a book changed on the server downloaded again")
                end)
            else
                -- (first seen: what it is now, to notice a change later)
                e.file_id, e.size_kb = e.file_id or fid, e.size_kb or kb
            end
        end
    end
    return titled, queued
end

--- A downloaded book's title and authors (KOReader's custom metadata, as
--- Book information's edit writes it), unless you changed them yourself.
function ShelfSync.applyMetadata(path, title, authors)
    local DocSettings = require("docsettings")
    local cm = DocSettings.openSettingsFile(DocSettings:findCustomMetadataFile(path))
    local custom = cm:readSetting("custom_props") or {}
    -- (a title or authors you set yourself, not GZreader: left alone)
    if custom.title and custom.title ~= cm:readSetting("gzreader_title") then return false end
    if custom.authors and custom.authors ~= cm:readSetting("gzreader_authors") then return false end
    if not cm:readSetting("doc_props") then cm:saveSetting("doc_props", { title = title, authors = authors }) end
    custom.title = title
    cm:saveSetting("gzreader_title", title)
    if authors then custom.authors = authors; cm:saveSetting("gzreader_authors", authors) end
    cm:saveSetting("custom_props", custom)
    if not cm:flushCustomMetadata(path) then return false end
    pcall(function() UIManager:broadcastEvent(require("ui/event"):new("InvalidateMetadataCache", path)) end)
    return true
end

--- Check the shelf and queue what isn't on the Kindle. manual: say so when nothing is new.
function ShelfSync.run(plugin, manual)
    local shelf = ShelfSync.shelf(plugin)
    if not shelf or not plugin.api:isPaired() or ShelfSync.running then return end
    if not manual and os.time() - (plugin.store.auto_shelf_last or 0) < ShelfSync.EVERY then return end
    ShelfSync.running = true
    plugin.store.auto_shelf_last = os.time()
    local readable = plugin.api.READABLE_TYPES
    require("gzreader_async").run(plugin.api, function(api)
        local books, page, complete = {}, 0, false
        while page < ShelfSync.MAX_PAGES do
            local p = { page = page, size = ShelfSync.PAGE, sort = "addedOn", dir = "desc", fileType = readable }
            if shelf.magic then p.magicShelfId = shelf.id else p.shelfId = shelf.id end
            local data, err = api:listBooks(p)
            if not data then return nil, err end
            for _i, b in ipairs(type(data.content) == "table" and data.content or {}) do
                if type(b) == "table" and b.id then books[#books + 1] = fields(b) end
            end
            page = page + 1
            if not data.hasNext or page >= (tonumber(data.totalPages) or 1) then complete = true; break end
        end
        -- (JSON back from the request process: the list, and whether it's the whole shelf)
        return { books = books, complete = complete }
    end, function(res, err)
        local books = type(res) == "table" and res.books or nil
        ShelfSync.running = nil
        if not books then
            Log.warn("shelf sync failed:", tostring(err))
            if manual then plugin:showError(err) end
            return
        end
        local Download = require("gzreader_download")
        local Browser = require("gzreader_browser")
        local new = {}
        for _i, b in ipairs(books) do
            local ftype = type(b.primaryFileType) == "string" and b.primaryFileType:upper() or ""
            if b.isPhysical ~= true and ftype ~= "AUDIOBOOK" and (not Browser.isReadable or Browser.isReadable(b))
                    and not plugin:localPathFor(b.id) and not Download.isQueued(b.id) then
                new[#new + 1] = b
            end
        end
        Log.info("shelf sync", shelf.name or shelf.id, #books, "on shelf,", #new, "new")
        -- (the shelf's books: what mirroring keeps in step)
        local ids = {}
        plugin.store.auto_shelf_got = plugin.store.auto_shelf_got or {}
        for _i, b in ipairs(books) do
            local id = tostring(b.id)
            ids[id] = true
            if plugin:localPathFor(b.id) then plugin.store.auto_shelf_got[id] = true end
        end
        for _i, b in ipairs(new) do plugin.store.auto_shelf_got[tostring(b.id)] = true end
        local said = false
        if ShelfSync.mirrorOn(plugin) and res.complete == true then
            local okm, off, back = pcall(ShelfSync.mirror, plugin, ids)
            if okm and (off > 0 or back > 0) then
                Log.info("shelf sync: mirrored,", off, "taken off the shelf moved aside,", back, "back on it")
                pcall(plugin.writeManifest, plugin)
                pcall(plugin.refreshDownloadsTab, plugin)
                said = true
                UIManager:show(InfoMessage:new{ timeout = 4, text = off > 0
                    and T(_("%1 book(s) taken off “%2” moved to the “%3” folder."), off, shelf.name or "", ShelfSync.TRASH)
                    or T(_("%1 book(s) back on “%2”, moved back."), back, shelf.name or "") })
            end
        end
        if ShelfSync.refreshOn(plugin) then
            local okr, titled, queued = pcall(ShelfSync.refresh, plugin, books)
            if okr and (titled > 0 or queued > 0) then
                Log.info("shelf sync: kept up to date,", titled, "titles or authors changed,", queued, "changed files downloaded again")
            end
        end
        plugin:save()
        if #new == 0 then
            if manual and not said then UIManager:show(InfoMessage:new{ text = T(_("Everything on “%1” is already on this Kindle."), shelf.name or ""), timeout = 3 }) end
            return
        end
        Download.background = true -- quietly, one after another
        for _i, b in ipairs(new) do plugin:downloadAndOpen(b, nil) end
        UIManager:show(InfoMessage:new{
            text = T(_("Downloading %1 new book(s) from “%2” in the background."), #new, shelf.name or ""), timeout = 4 })
    end, "shelf sync")
end

--- Settings menu entries.
function ShelfSync.menuItems(plugin)
    return {
        text_func = function()
            local s = ShelfSync.shelf(plugin)
            return s and T(_("Auto-download shelf: %1"), s.name or "?") or _("Auto-download a shelf: off")
        end,
        help_text = _("Books you put on this Grimmory shelf (for example one called “Kindle”) download to this Kindle by themselves when Wi-Fi is on, in the background. Books taken off the shelf stay on the Kindle, unless Mirror the shelf is on."),
        enabled_func = function() return plugin.api:isPaired() end,
        keep_menu_open = true,
        sub_item_table_func = function()
            local items = {
                { text = _("Download new books from the shelf now"),
                  enabled_func = function() return ShelfSync.shelf(plugin) ~= nil end,
                  callback = function()
                      require("gzreader_net").run(function() ShelfSync.run(plugin, true) end, { reason = "shelf" })
                  end, separator = true },
                { text = _("Mirror the shelf"),
                  help_text = T(_("Books the shelf brought that you take off it move to the “%1” folder in the books folder (with their reading positions); put back on the shelf, they move back. Nothing is deleted, and other books are never touched."), ShelfSync.TRASH),
                  enabled_func = function() return ShelfSync.shelf(plugin) ~= nil end,
                  checked_func = function() return ShelfSync.mirrorOn(plugin) end,
                  callback = function()
                      plugin.store.auto_shelf_mirror = not ShelfSync.mirrorOn(plugin) or nil
                      plugin:save()
                      Log.info("shelf sync: mirror", tostring(ShelfSync.mirrorOn(plugin)))
                  end },
                { text = _("Keep books up to date"),
                  help_text = _("A shelf book whose title or authors change on the server gets them here too (unless you changed them yourself), and one whose file changes there is downloaded again over the old one, keeping your place."),
                  enabled_func = function() return ShelfSync.shelf(plugin) ~= nil end,
                  checked_func = function() return ShelfSync.refreshOn(plugin) end,
                  callback = function()
                      plugin.store.auto_shelf_refresh = not ShelfSync.refreshOn(plugin) or nil
                      plugin:save()
                      Log.info("shelf sync: keep up to date", tostring(ShelfSync.refreshOn(plugin)))
                  end, separator = true },
                { text = _("Off"),
                  checked_func = function() return ShelfSync.shelf(plugin) == nil end,
                  callback = function() ShelfSync.set(plugin, nil) end },
            }
            if not plugin.store.shelves_cache and require("gzreader_net").connected() then
                local list = plugin.api:listShelves()
                if list then
                    local keep = {}
                    for _i, sh in ipairs(list) do keep[#keep + 1] = { id = sh.id, name = sh.name, magic = sh.magic == true } end
                    plugin.store.shelves_cache = keep
                    plugin:save()
                end
            end
            local shelves = plugin.store.shelves_cache or {}
            for _i, sh in ipairs(shelves) do
                items[#items + 1] = {
                    text = (sh.name or "?") .. (sh.magic and ("  (" .. _("smart shelf") .. ")") or ""),
                    checked_func = function()
                        local cur = ShelfSync.shelf(plugin)
                        return cur ~= nil and cur.id == sh.id and cur.magic == (sh.magic == true)
                    end,
                    callback = function()
                        ShelfSync.set(plugin, sh)
                        require("gzreader_net").run(function() ShelfSync.run(plugin, true) end, { reason = "shelf" })
                    end,
                }
            end
            items[#items + 1] = {
                text = _("Refresh the list of shelves"),
                separator = true,
                callback = function()
                    require("gzreader_net").run(function()
                        local list, err = plugin.api:listShelves()
                        if not list then return plugin:showError(err) end
                        local keep = {}
                        for _i, sh in ipairs(list) do keep[#keep + 1] = { id = sh.id, name = sh.name, magic = sh.magic == true } end
                        plugin.store.shelves_cache = keep
                        plugin:save()
                        UIManager:show(InfoMessage:new{ text = T(_("%1 shelves. Open this menu again to pick one."), #keep), timeout = 3 })
                    end, { reason = "shelves" })
                end,
            }
            return items
        end,
    }
end

return ShelfSync
