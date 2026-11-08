--[[--
Grimmory shelves from the book menu.

For a book that came from Grimmory, ZenOS's book menu (hold a book, or its
… button) has "Add to shelf" where it had "Add to collection", and "Remove
from shelf" (or "Remove from shelves") when the book is on one or more of
your shelves. Books not from Grimmory, a Kindle that isn't signed in and
the Kindles without Wi-Fi (they reach Grimmory through the sync page) keep
Add to collection.

Only your own regular shelves: Grimmory lets you put books on the shelves
you made, not on someone else's public shelf, and smart (magic) shelves
fill themselves from their rules.

Which of your shelves a book is on is kept with its download
(entry.shelves = { { id, name } }, sorted by name), from Grimmory's record
of the book: when the book opens (the reading position comes in the same
record), whenever the shelves are listed here, and after each change. The
menu goes by that to offer "Remove from shelf"; adding and removing ask
Grimmory first, so what you pick from is up to date.
]]

local Shelves = {}

-- A list, as a list in JSON even when it's empty ([] and not {}: Grimmory
-- reads shelvesToUnassign as a set; KOReader's luajson and dkjson each have their mark).
local ARRAY = { __is_luajson_array = true, __jsontype = "array" }
function Shelves.list(t)
    local out = {}
    for i, v in ipairs(type(t) == "table" and t or {}) do out[i] = v end
    return setmetatable(out, ARRAY)
end

local function userKey(store) return tostring(store.server or "") .. "|" .. tostring(store.username or "") end

--- Your Grimmory user id, when known for the account signed in now.
function Shelves.myId(store)
    local u = type(store) == "table" and store.grimmory_user
    if type(u) == "table" and u.key == userKey(store) then return u.id end
end

function Shelves.setMyId(store, id)
    if id ~= nil then store.grimmory_user = { key = userKey(store), id = id } end
end

--- Is shelf `sh` (Grimmory's Shelf: id, name, userId, publicShelf) yours?
--- me: your user id (nil, or a shelf without a userId: the ones that
--- aren't public, which only their owner sees).
function Shelves.own(sh, me)
    if type(sh) ~= "table" or (type(sh.id) ~= "number" and type(sh.id) ~= "string") then return false end
    if me ~= nil and (type(sh.userId) == "number" or type(sh.userId) == "string") then
        return tostring(sh.userId) == tostring(me)
    end
    return sh.publicShelf ~= true
end

local function byName(list)
    table.sort(list, function(a, b)
        local x, y = tostring(a.name or ""):lower(), tostring(b.name or ""):lower()
        if x ~= y then return x < y end
        return tostring(a.id) < tostring(b.id)
    end)
    return list
end
Shelves.byName = byName

--- Your shelves among a book record's `shelves` ({ { id, name } } by name),
--- or nil when the record has no shelves at all (an older Grimmory).
function Shelves.ownOf(book, me)
    if type(book) ~= "table" or type(book.shelves) ~= "table" then return nil end
    local out = {}
    for _i, sh in ipairs(book.shelves) do
        if Shelves.own(sh, me) then
            out[#out + 1] = { id = sh.id, name = type(sh.name) == "string" and sh.name or ("#" .. tostring(sh.id)) }
        end
    end
    return byName(out)
end

local function sameShelves(a, b)
    a, b = type(a) == "table" and a or {}, type(b) == "table" and b or {}
    if #a ~= #b then return false end
    for i = 1, #a do
        if tostring(a[i].id) ~= tostring(b[i].id) or a[i].name ~= b[i].name then return false end
    end
    return true
end

--- Keep the shelves (a list from ownOf) book `book_id` is on with its download.
function Shelves.keep(plugin, book_id, list)
    local entry = plugin.store.downloads[tostring(book_id)]
    if type(entry) ~= "table" or type(list) ~= "table" then return end
    if not sameShelves(entry.shelves, list) then
        entry.shelves = #list > 0 and list or nil
        plugin:save()
    end
end

--- From Grimmory's record of a book (GET /api/v1/books/{id}, e.g. when it
--- opens): keep which of your shelves it's on. Returns that list (or nil).
function Shelves.remember(plugin, book_id, book)
    local list = Shelves.ownOf(book, Shelves.myId(plugin.store))
    if list then Shelves.keep(plugin, book_id, list) end
    return list
end

--- Shelves for the book menu? The Grimmory book id for `path`, its
--- download entry and the plugin's api; nil for the menu's own Add to collection.
function Shelves.bookFor(plugin, path)
    local api = plugin and plugin.api
    if not path or type(api) ~= "table" or api.offline or not api:isPaired() then return nil end
    local id, entry = plugin:entryForPath(path)
    if id == nil or type(entry) ~= "table" then return nil end
    return id, entry
end

--- The book menu's shelf buttons for `path`, or nil (keep Add to collection):
--- { { kind = "add" | "remove", text = …, submenu = a list follows, callback = fn } }. on_change():
--- after the book went on or off a shelf.
function Shelves.buttons(plugin, path, on_change)
    local id, entry = Shelves.bookFor(plugin, path)
    if id == nil then return nil end
    local _ = require("gettext")
    local out = { { kind = "add", text = _("Add to shelf"), submenu = true,
        callback = function() Shelves.showAdd(plugin, id, on_change) end } }
    local n = type(entry.shelves) == "table" and #entry.shelves or 0
    if n > 0 then
        out[2] = { kind = "remove", text = n == 1 and _("Remove from shelf") or _("Remove from shelves"), submenu = n > 1,
            callback = function() Shelves.showRemove(plugin, id, on_change) end }
    end
    return out
end

--- Ask Grimmory (Wi-Fi turned on if it's needed) for the shelves book `id`
--- is on and, unless opts.only_book, your shelves. done({ shelves, on })
--- when it answered: shelves = your shelves by name, on = the book's.
function Shelves.fetch(plugin, id, done, opts)
    opts = opts or {}
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Log = require("gzreader_log")
    local _ = require("gettext")
    require("gzreader_net").run(function()
        local wait = InfoMessage:new{ text = _("Asking Grimmory about your shelves…") }
        UIManager:show(wait)
        require("gzreader_async").run(plugin.api, function(a)
            local me = Shelves.myId(a.store)
            if me == nil then
                local u = a:me()
                me = type(u) == "table" and (type(u.id) == "number" or type(u.id) == "string") and u.id or nil
            end
            local mine, err
            if not opts.only_book then
                mine, err = a:listMyShelves(me)
                if not mine then return nil, err end
            end
            local book, err2 = a:getBook(id)
            if type(book) ~= "table" then return nil, err2 end
            return { me = me, shelves = mine, on = Shelves.ownOf(book, me) }
        end, function(res, err)
            UIManager:close(wait)
            if type(res) ~= "table" then
                Log.warn("shelves: Grimmory didn't answer for book", id, tostring(err))
                return plugin:showError(err)
            end
            Shelves.setMyId(plugin.store, res.me)
            if res.on then Shelves.keep(plugin, id, res.on) end
            res.shelves = byName(type(res.shelves) == "table" and res.shelves or {})
            res.on = type(res.on) == "table" and res.on or {}
            done(res)
        end, "shelves")
    end, { reason = "shelves" })
end

--- Put book `id` on shelves `add` / take it off shelves `remove` (ids);
--- `what`: the shelf's name for the message, or how many.
function Shelves.change(plugin, id, add, remove, what, on_change)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Log = require("gzreader_log")
    local _ = require("gettext")
    local T = require("ffi/util").template
    require("gzreader_net").run(function()
        require("gzreader_async").run(plugin.api, function(a)
            return a:setBookShelves(id, add, remove)
        end, function(book, err)
            if type(book) ~= "table" then
                Log.warn("shelves: change refused for book", id, tostring(err))
                return plugin:showError(err)
            end
            Log.info("shelves: book", id, #add > 0 and "added to" or "taken off", #add + #remove, "shelf/shelves")
            if not Shelves.remember(plugin, id, book) then
                -- (no shelves in the reply: what we asked for)
                local entry = plugin.store.downloads[tostring(id)]
                local list, gone = {}, {}
                for _i, sid in ipairs(remove) do gone[tostring(sid)] = true end
                for _i, sh in ipairs(type(entry) == "table" and entry.shelves or {}) do
                    if not gone[tostring(sh.id)] then list[#list + 1] = sh end
                end
                for _i, sid in ipairs(add) do list[#list + 1] = { id = sid, name = type(what) == "string" and what or nil } end
                Shelves.keep(plugin, id, byName(list))
            end
            local text
            if #add > 0 then text = T(_("Added to “%1”."), what)
            elseif type(what) == "number" then text = T(_("Removed from %1 shelves."), what)
            else text = T(_("Removed from “%1”."), what) end
            UIManager:show(InfoMessage:new{ text = text, timeout = 2 })
            if on_change then pcall(on_change) end
        end, "shelf change")
    end, { reason = "shelves" })
end

local function picker(title, items, on_pick)
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local menu
    menu = Menu:new{
        title = title,
        item_table = items,
        is_borderless = true,
        is_popout = false,
        onMenuSelect = function(_m, item)
            if item.dim then return true end
            UIManager:close(menu)
            on_pick(item)
            return true
        end,
        close_callback = function() UIManager:close(menu) end,
    }
    UIManager:show(menu)
    return menu
end

--- Add to shelf: your shelves; the ones the book is already on are ticked and greyed out.
function Shelves.showAdd(plugin, id, on_change)
    local _ = require("gettext")
    Shelves.fetch(plugin, id, function(res)
        if #res.shelves == 0 then
            local UIManager = require("ui/uimanager")
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("You have no shelves in Grimmory yet. Make one in Grimmory's web app (the + next to Shelves), then try again."),
                timeout = 6 })
            return
        end
        local on = {}
        for _i, sh in ipairs(res.on) do on[tostring(sh.id)] = true end
        local items = {}
        for _i, sh in ipairs(res.shelves) do
            local here = on[tostring(sh.id)]
            items[#items + 1] = { text = sh.name .. (here and "  ✓" or ""), dim = here or nil,
                mandatory = here and _("on it") or nil, gz_shelf = sh }
        end
        Shelves.menu = picker(_("Add to shelf"), items, function(item)
            Shelves.change(plugin, id, { item.gz_shelf.id }, {}, item.gz_shelf.name, on_change)
        end)
    end)
end

--- Remove from shelf: straight off when it's on one of your shelves; a
--- choice (one of them, or all) when it's on several.
function Shelves.showRemove(plugin, id, on_change)
    local _ = require("gettext")
    local T = require("ffi/util").template
    Shelves.fetch(plugin, id, function(res)
        local on = res.on
        if #on == 0 then
            local UIManager = require("ui/uimanager")
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("This book isn't on any of your shelves in Grimmory now."), timeout = 3 })
            if on_change then pcall(on_change) end
            return
        end
        if #on == 1 then
            return Shelves.change(plugin, id, {}, { on[1].id }, on[1].name, on_change)
        end
        local items = {}
        for _i, sh in ipairs(on) do items[#items + 1] = { text = sh.name, gz_shelf = sh } end
        items[#items + 1] = { text = T(_("All %1 shelves"), #on), gz_all = true }
        Shelves.menu = picker(_("Remove from shelf"), items, function(item)
            if item.gz_all then
                local ids = {}
                for _i, sh in ipairs(on) do ids[#ids + 1] = sh.id end
                Shelves.change(plugin, id, {}, ids, #ids, on_change)
            else
                Shelves.change(plugin, id, {}, { item.gz_shelf.id }, item.gz_shelf.name, on_change)
            end
        end)
    end, { only_book = true })
end

return Shelves
