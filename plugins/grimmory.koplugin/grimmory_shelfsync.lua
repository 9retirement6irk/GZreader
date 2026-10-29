--[[--
Auto-download a Grimmory shelf ("Send to Kindle").

Pick one of your Grimmory shelves (or smart shelves) in Settings → GZreader.
Books added to it there download to this Kindle by themselves: when Wi-Fi
connects (at most every 30 minutes) and with "Download new books from the
shelf now". They go through the download queue in the background. Books
taken off the shelf are left on the Kindle.

Idea from Shelf Sync (krisboho/connecto-library), written for GZreader.
]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Log = require("grimmory_log")
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

--- Check the shelf and queue what isn't on the Kindle. manual: say so when nothing is new.
function ShelfSync.run(plugin, manual)
    local shelf = ShelfSync.shelf(plugin)
    if not shelf or not plugin.api:isPaired() or ShelfSync.running then return end
    if not manual and os.time() - (plugin.store.auto_shelf_last or 0) < ShelfSync.EVERY then return end
    ShelfSync.running = true
    plugin.store.auto_shelf_last = os.time()
    local readable = plugin.api.READABLE_TYPES
    require("grimmory_async").run(plugin.api, function(api)
        local books, page = {}, 0
        while page < ShelfSync.MAX_PAGES do
            local p = { page = page, size = ShelfSync.PAGE, sort = "addedOn", dir = "desc", fileType = readable }
            if shelf.magic then p.magicShelfId = shelf.id else p.shelfId = shelf.id end
            local data, err = api:listBooks(p)
            if not data then return nil, err end
            for _i, b in ipairs(type(data.content) == "table" and data.content or {}) do
                if type(b) == "table" and b.id then books[#books + 1] = fields(b) end
            end
            page = page + 1
            if not data.hasNext or page >= (tonumber(data.totalPages) or 1) then break end
        end
        return books
    end, function(books, err)
        ShelfSync.running = nil
        if not books then
            Log.warn("shelf sync failed:", tostring(err))
            if manual then plugin:showError(err) end
            return
        end
        local Download = require("grimmory_download")
        local Browser = require("grimmory_browser")
        local new = {}
        for _i, b in ipairs(books) do
            local ftype = type(b.primaryFileType) == "string" and b.primaryFileType:upper() or ""
            if b.isPhysical ~= true and ftype ~= "AUDIOBOOK" and (not Browser.isReadable or Browser.isReadable(b))
                    and not plugin:localPathFor(b.id) and not Download.isQueued(b.id) then
                new[#new + 1] = b
            end
        end
        Log.info("shelf sync", shelf.name or shelf.id, #books, "on shelf,", #new, "new")
        plugin:save()
        if #new == 0 then
            if manual then UIManager:show(InfoMessage:new{ text = T(_("Everything on “%1” is already on this Kindle."), shelf.name or ""), timeout = 3 }) end
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
        help_text = _("Books you put on this Grimmory shelf (for example one called “Kindle”) download to this Kindle by themselves when Wi-Fi is on, in the background. Books taken off the shelf stay on the Kindle."),
        enabled_func = function() return plugin.api:isPaired() end,
        keep_menu_open = true,
        sub_item_table_func = function()
            local items = {
                { text = _("Download new books from the shelf now"),
                  enabled_func = function() return ShelfSync.shelf(plugin) ~= nil end,
                  callback = function()
                      require("grimmory_net").run(function() ShelfSync.run(plugin, true) end, { reason = "shelf" })
                  end, separator = true },
                { text = _("Off"),
                  checked_func = function() return ShelfSync.shelf(plugin) == nil end,
                  callback = function() ShelfSync.set(plugin, nil) end },
            }
            if not plugin.store.shelves_cache and require("grimmory_net").connected() then
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
                        require("grimmory_net").run(function() ShelfSync.run(plugin, true) end, { reason = "shelf" })
                    end,
                }
            end
            items[#items + 1] = {
                text = _("Refresh the list of shelves"),
                separator = true,
                callback = function()
                    require("grimmory_net").run(function()
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
