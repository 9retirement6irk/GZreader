--[[--
Grimmory shelves on the Kindle: the book menu's Add to shelf and Remove
from shelf, on every Kindle, with or without Wi-Fi.

The book menu (ZenOS's: quick panel → Manage “book”, or holding a book) and
the menu for several selected books have "Add to shelf" where ZenOS had
"Add to collection"; a book on one or more of your shelves also has "Remove
from shelf" ("Remove from shelves" when on several: one of them, or all).
Not signed in to Grimmory: the buttons are there and say to sign in. Only
your own regular shelves: Grimmory doesn't let you put books on someone
else's public shelf, and smart (magic) shelves fill themselves from rules.

The shelves are kept on the Kindle (store.shelf_cache): each of your
shelves with the ids of every book on it, as Grimmory has them —
  { key = server|user, at = when, full = true, shelves = { { id, name, books = { ids } } } }
  (full: every shelf and book; without it, only what opened books' records said)
- Kindles with Wi-Fi: from Grimmory (your shelves, then each shelf's
  books) when Wi-Fi connects (at most every 30 minutes) and after sending a
  change; a book's own record (GET /api/v1/books/{id}, when it opens)
  updates that book's shelves.
- Kindles syncing through a computer (Kindle 2, DX): from the library copy
  the sync page leaves (its shelves marked own = true, lists.shelf).

A change made here is queued (store.pending.shelves[book] = { seq, set =
{ [shelf] = true | false } }) and shown at once; the menus show the queue
on top of the kept shelves. With Wi-Fi it's sent straight away (or when
Wi-Fi next connects); without, the outbox carries it to the sync page as a
job (POST /api/v1/books/shelves), which the page sends before it copies the
library again. Only the shelves changed are sent, so a change made in
Grimmory's web app meanwhile to another shelf stays.
]]

local Shelves = { EVERY = 30 * 60, PAGE = 100, MAX_PAGES = 50 }

-- A list, as a list in JSON even when it's empty ([] and not {}: Grimmory
-- reads the shelf lists as sets; KOReader's luajson and dkjson each have their mark).
local ARRAY = { __is_luajson_array = true, __jsontype = "array" }
function Shelves.list(t)
    local out = {}
    for i, v in ipairs(type(t) == "table" and t or {}) do out[i] = v end
    return setmetatable(out, ARRAY)
end

local function idOk(v) return type(v) == "number" or type(v) == "string" end
local function num(v) return tonumber(v) or v end

local function userKey(store) return tostring(store.server or "") .. "|" .. tostring(store.username or "") end

--- Your Grimmory user id, when known for the account signed in now.
function Shelves.myId(store)
    local u = type(store) == "table" and store.grimmory_user
    if type(u) == "table" and u.key == userKey(store) then return u.id end
end

function Shelves.setMyId(store, id)
    if idOk(id) then store.grimmory_user = { key = userKey(store), id = id } end
end

--- Is shelf `sh` (Grimmory's Shelf: id, name, userId, publicShelf; the sync
--- page's copy: own) yours? me: your user id (nil, or a shelf without a
--- userId: the ones that aren't public, which only their owner sees).
function Shelves.own(sh, me)
    if type(sh) ~= "table" or not idOk(sh.id) or sh.magic == true then return false end
    if sh.own ~= nil then return sh.own == true end
    if me ~= nil and idOk(sh.userId) then return tostring(sh.userId) == tostring(me) end
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

local function shelfName(sh) return type(sh.name) == "string" and sh.name ~= "" and sh.name or ("#" .. tostring(sh.id)) end

--- Your shelves among a book record's `shelves` ({ { id, name } } by name),
--- or nil when the record has no shelves at all (an older Grimmory).
function Shelves.ownOf(book, me)
    if type(book) ~= "table" or type(book.shelves) ~= "table" then return nil end
    local out = {}
    for _i, sh in ipairs(book.shelves) do
        if Shelves.own(sh, me) then out[#out + 1] = { id = sh.id, name = shelfName(sh) } end
    end
    return byName(out)
end

---------------------------------------------------------------- what's kept

--- The kept shelves for the account signed in now, or nil (none kept yet).
function Shelves.cache(plugin)
    local c = plugin.store.shelf_cache
    if type(c) == "table" and c.key == userKey(plugin.store) and type(c.shelves) == "table" then return c end
    -- (a Kindle without Wi-Fi with a library copy from before shelves were kept: from it, once)
    local api = plugin.api
    if type(api) == "table" and api.offline and not api.gz_shelves_tried and api.snapshot then
        api.gz_shelves_tried = true
        local ok, snap = pcall(api.snapshot, api)
        if ok and snap and Shelves.takeCopy(plugin, snap) then return Shelves.cache(plugin) end
    end
end

--- full: every shelf with every book (from Grimmory or the sync page's
--- copy); not: only what books' own records said (refreshed before a list).
local function setCache(plugin, shelves, at, partial)
    for _i, sh in ipairs(shelves) do
        local seen, books = {}, {}
        for _j, b in ipairs(type(sh.books) == "table" and sh.books or {}) do
            if idOk(b) and not seen[tostring(b)] then seen[tostring(b)] = true; books[#books + 1] = num(b) end
        end
        sh.books = books
        sh.name = shelfName(sh)
    end
    plugin.store.shelf_cache = { key = userKey(plugin.store), at = at or os.time(), shelves = byName(shelves),
        full = not partial or nil }
    plugin:save()
end
Shelves.setCache = setCache

local function inList(list, id)
    for i, v in ipairs(list) do if tostring(v) == tostring(id) then return i end end
end

--- The queued changes of book `book_id` ({ [shelf id] = true | false }), or nil.
local function queued(plugin, book_id)
    local p = plugin.store.pending and plugin.store.pending.shelves
    local q = type(p) == "table" and p[tostring(book_id)]
    return type(q) == "table" and type(q.set) == "table" and q.set or nil
end

--- Your shelves ({ { id, name } } by name), or nil when none are kept yet.
function Shelves.mine(plugin)
    local c = Shelves.cache(plugin)
    if not c then return nil end
    local out = {}
    for _i, sh in ipairs(c.shelves) do out[#out + 1] = { id = sh.id, name = sh.name } end
    return out
end

--- Is book `book_id` on shelf `shelf_id` (the queue first, then what's kept)?
function Shelves.isOn(plugin, book_id, shelf_id)
    local q = queued(plugin, book_id)
    if q and q[tostring(shelf_id)] ~= nil then return q[tostring(shelf_id)] == true end
    local c = Shelves.cache(plugin)
    for _i, sh in ipairs(c and c.shelves or {}) do
        if tostring(sh.id) == tostring(shelf_id) then return inList(sh.books, book_id) ~= nil end
    end
    return false
end

--- The shelves book `book_id` is on ({ { id, name } } by name).
function Shelves.on(plugin, book_id)
    local out = {}
    for _i, sh in ipairs(Shelves.mine(plugin) or {}) do
        if Shelves.isOn(plugin, book_id, sh.id) then out[#out + 1] = sh end
    end
    return out
end

--- Grimmory's record of a book (GET /api/v1/books/{id}: when it opens): its
--- shelves into what's kept. Returns the list or nil.
function Shelves.remember(plugin, book_id, book)
    local list = Shelves.ownOf(book, Shelves.myId(plugin.store))
    if not list then return nil end
    local c = Shelves.cache(plugin)
    local shelves = {}
    for _i, sh in ipairs(c and c.shelves or {}) do
        local books = {}
        for _j, b in ipairs(sh.books) do books[#books + 1] = b end
        shelves[#shelves + 1] = { id = sh.id, name = sh.name, books = books }
    end
    local on, changed = {}, false
    for _i, sh in ipairs(list) do on[tostring(sh.id)] = sh end
    for _i, sh in ipairs(shelves) do
        local i = inList(sh.books, book_id)
        local want = on[tostring(sh.id)]
        if want then
            on[tostring(sh.id)] = nil
            if not i then sh.books[#sh.books + 1] = num(book_id); changed = true end
            if want.name ~= sh.name then sh.name = want.name; changed = true end
        elseif i then
            table.remove(sh.books, i); changed = true
        end
    end
    for _id, sh in pairs(on) do -- (a shelf not kept yet: kept with this book; the rest comes with the next refresh)
        shelves[#shelves + 1] = { id = sh.id, name = sh.name, books = { num(book_id) } }
        changed = true
    end
    if changed then setCache(plugin, shelves, c and c.at or 0, not (c and c.full)) end
    return list
end

--- The sync page's library copy (Kindles without Wi-Fi): your shelves and
--- their books. A copy from before the page marked them (own): the shelves
--- that aren't public.
function Shelves.takeCopy(plugin, snap)
    if type(snap) ~= "table" or type(snap.shelves) ~= "table" then return false end
    local lists = type(snap.lists) == "table" and type(snap.lists.shelf) == "table" and snap.lists.shelf or {}
    local shelves = {}
    for _i, sh in ipairs(snap.shelves) do
        if Shelves.own(sh, nil) then
            local books = lists[tostring(sh.id)]
            shelves[#shelves + 1] = { id = sh.id, name = sh.name, books = type(books) == "table" and books or {} }
        end
    end
    setCache(plugin, shelves, tonumber(snap.written_at) or os.time())
    return true
end

---------------------------------------------------------------- changes

--- Put books `book_ids` on shelf `shelf_id` (on = true) or take them off
--- (false): queued and shown at once; sent now when there's Wi-Fi.
function Shelves.set(plugin, book_ids, shelf_id, on)
    local store = plugin.store
    store.pending.shelves = type(store.pending.shelves) == "table" and store.pending.shelves or {}
    local c = Shelves.cache(plugin)
    local kept_on = {}
    for _i, sh in ipairs(c and c.shelves or {}) do
        if tostring(sh.id) == tostring(shelf_id) then
            for _j, b in ipairs(sh.books) do kept_on[tostring(b)] = true end
        end
    end
    for _i, book in ipairs(book_ids) do
        local key = tostring(book)
        local q = store.pending.shelves[key] or { set = {} }
        if (kept_on[key] == true) == (on == true) then
            q.set[tostring(shelf_id)] = nil -- (back to how Grimmory has it: nothing to send for it)
        else
            q.set[tostring(shelf_id)] = on == true
        end
        store.shelf_seq = (store.shelf_seq or 0) + 1
        q.seq = store.shelf_seq
        store.pending.shelves[key] = next(q.set) ~= nil and q or nil
    end
    plugin:save()
    require("gzreader_log").info("shelves:", #book_ids, "book(s)", on and "put on" or "taken off", "shelf", shelf_id,
        "(queued)")
    Shelves.sendSoon(plugin)
end

--- Has anything waiting to go to Grimmory?
function Shelves.hasPending(plugin)
    local p = plugin.store.pending and plugin.store.pending.shelves
    return type(p) == "table" and next(p) ~= nil
end

--- The queue as requests for the sync page (the outbox's jobs).
function Shelves.jobs(plugin)
    local p = plugin.store.pending and plugin.store.pending.shelves
    local books = {}
    for book in pairs(type(p) == "table" and p or {}) do books[#books + 1] = book end
    table.sort(books)
    local out = {}
    for _i, book in ipairs(books) do
        local q = p[book]
        local add, remove = {}, {}
        local shelves = {}
        for sid in pairs(type(q) == "table" and type(q.set) == "table" and q.set or {}) do shelves[#shelves + 1] = sid end
        table.sort(shelves)
        for _j, sid in ipairs(shelves) do
            if q.set[sid] then add[#add + 1] = num(sid) else remove[#remove + 1] = num(sid) end
        end
        if #shelves > 0 then
            out[#out + 1] = { id = "sh:" .. book .. ":" .. tostring(q.seq or 0), kind = "shelf", book = num(book),
                method = "POST", path = "/api/v1/books/shelves",
                body = { bookIds = Shelves.list{ num(book) }, shelvesToAssign = Shelves.list(add),
                    shelvesToUnassign = Shelves.list(remove) } }
        end
    end
    return out
end

--- A book's queued change went through (`q`: what was queued): into what's
--- kept, off the queue (unless changed again meanwhile).
local function applied(plugin, book, q)
    if type(q) ~= "table" or type(q.set) ~= "table" then return end
    local c = Shelves.cache(plugin)
    for _i, sh in ipairs(c and c.shelves or {}) do
        local want = q.set[tostring(sh.id)]
        if want ~= nil then
            local i = inList(sh.books, book)
            if want and not i then sh.books[#sh.books + 1] = num(book) end
            if not want and i then table.remove(sh.books, i) end
        end
    end
    local p = plugin.store.pending.shelves
    if p and p[tostring(book)] and p[tostring(book)].seq == q.seq then p[tostring(book)] = nil end
end

--- The sync page sent these jobs (done = { [job id] = true }): off the queue.
--- Returns how many.
function Shelves.applyDone(plugin, done)
    local n = 0
    for _i, j in ipairs(Shelves.jobs(plugin)) do
        if done[j.id] then
            applied(plugin, j.book, plugin.store.pending.shelves[tostring(j.book)])
            n = n + 1
        end
    end
    return n
end

local function online(plugin)
    local api = plugin.api
    if type(api) ~= "table" or api.offline or not api:isPaired() then return false end
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    return ok and NetworkMgr:isConnected() and true or false
end

--- Send the queue now (Wi-Fi Kindles), then refresh what's kept.
function Shelves.sendSoon(plugin)
    if type(plugin.api) ~= "table" or plugin.api.offline then return end
    require("gzreader_net").run(function() Shelves.sync(plugin, true) end, { quiet = true, reason = "shelves" })
end

--- With Wi-Fi: send what's queued, then (after a change, or every 30
--- minutes) your shelves and their books again from Grimmory.
function Shelves.sync(plugin, force, on_done)
    if not online(plugin) or Shelves.running then return on_done and on_done(false) end
    local c = Shelves.cache(plugin)
    local stale = not (c and c.full) or os.time() - (tonumber(c.at) or 0) >= Shelves.EVERY
    if not Shelves.hasPending(plugin) and not stale and not force then return on_done and on_done(true) end
    Shelves.running = true
    -- (copies: what's queued meanwhile isn't taken for sent)
    local sending = {}
    for book, q in pairs(plugin.store.pending.shelves or {}) do
        local set = {}
        for sid, v in pairs(q.set or {}) do set[sid] = v end
        sending[book] = { seq = q.seq, set = set }
    end
    local jobs = Shelves.jobs(plugin)
    local key = userKey(plugin.store)
    require("gzreader_async").run(plugin.api, function(a)
        local me = Shelves.myId(a.store)
        if me == nil then
            local u = a:me()
            me = type(u) == "table" and idOk(u.id) and u.id or nil
        end
        local sent = {}
        for _i, j in ipairs(jobs) do
            local book, err, code = a:setBookShelves(j.book, j.body.shelvesToAssign, j.body.shelvesToUnassign)
            if book then sent[tostring(j.book)] = "ok"
            elseif code and code >= 400 and code < 500 and code ~= 401 and code ~= 408 and code ~= 429 then
                sent[tostring(j.book)] = "refused " .. tostring(code) -- (for good: not sent again)
            else
                return { me = me, sent = sent, err = err } -- still offline: the rest later
            end
        end
        local mine, err = a:listMyShelves(me)
        if not mine then return { me = me, sent = sent, err = err } end
        for _i, sh in ipairs(mine) do
            sh.books = {}
            local page, pages = 0, 1
            while page < pages and page < Shelves.MAX_PAGES do
                local data, perr = a:listBooks{ shelfId = sh.id, page = page, size = Shelves.PAGE, sort = "title", dir = "asc" }
                if type(data) ~= "table" then return { me = me, sent = sent, err = perr } end
                pages = tonumber(data.totalPages) or 1
                for _j, b in ipairs(type(data.content) == "table" and data.content or {}) do
                    if type(b) == "table" and idOk(b.id) then sh.books[#sh.books + 1] = b.id end
                end
                page = page + 1
            end
        end
        return { me = me, sent = sent, shelves = mine }
    end, function(res, err)
        Shelves.running = nil
        local Log = require("gzreader_log")
        if type(res) ~= "table" then
            Log.warn("shelves: Grimmory didn't answer:", tostring(err))
            return on_done and on_done(false, err)
        end
        if userKey(plugin.store) ~= key then return on_done and on_done(false) end -- (signed in as someone else meanwhile)
        Shelves.setMyId(plugin.store, res.me)
        for book, how in pairs(res.sent or {}) do
            if sending[book] then applied(plugin, book, sending[book]) end
            Log.info("shelves: book", book, "change sent:", how)
        end
        if type(res.shelves) == "table" then
            setCache(plugin, res.shelves)
            local n = 0
            for _i, sh in ipairs(res.shelves) do n = n + #sh.books end
            Log.info("shelves: kept", #res.shelves, "shelves,", n, "books on them")
        else
            plugin:save()
            if res.err then Log.warn("shelves: Grimmory didn't answer:", tostring(res.err)) end
        end
        if on_done then on_done(type(res.shelves) == "table", res.err) end
        -- changed again while this was being sent: send that too
        if next(res.sent or {}) ~= nil and Shelves.hasPending(plugin) then
            require("ui/uimanager"):nextTick(function() Shelves.sync(plugin, true) end)
        end
    end, "shelves")
end

---------------------------------------------------------------- the menus

local function info(text, timeout)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

--- Signed in to Grimmory (a Kindle without Wi-Fi: the sync page left a copy)?
--- If not, says how and returns false.
function Shelves.ready(plugin)
    local _ = require("gettext")
    local api = plugin.api
    if type(api) == "table" and api:isPaired() then return true end
    if type(api) == "table" and api.offline then
        info(_("Sign in to Grimmory to continue: plug this Kindle into a computer and sync with the sync page (Settings → Connections → Sync through a computer)."), 6)
    else
        info(_("Sign in to Grimmory to continue: Settings → Connections → Grimmory."), 5)
    end
    return false
end

local function shelvesThen(plugin, fn)
    local _ = require("gettext")
    local mine = Shelves.mine(plugin)
    local c = Shelves.cache(plugin)
    if mine and (c.full or plugin.api.offline) then return fn(mine) end
    if plugin.api.offline then
        return info(_("Your shelves come to this Kindle with the next sync through a computer."), 5)
    end
    require("gzreader_net").run(function()
        local UIManager = require("ui/uimanager")
        local InfoMessage = require("ui/widget/infomessage")
        local wait = InfoMessage:new{ text = _("Asking Grimmory about your shelves…") }
        UIManager:show(wait)
        Shelves.sync(plugin, true, function(ok, err)
            UIManager:close(wait)
            local got = Shelves.mine(plugin) -- (no answer: what's kept, if anything)
            if got and (ok or #got > 0) then return fn(got) end
            if not ok then plugin:showError(err or "unreachable") end
        end)
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
    Shelves.menu = menu
    return menu
end

local function after(plugin, text)
    local _ = require("gettext")
    if type(plugin.api) == "table" and plugin.api.offline then
        text = text .. "\n" .. _("Grimmory gets it at the next sync through a computer.")
    elseif Shelves.hasPending(plugin) and not online(plugin) then
        text = text .. "\n" .. _("Grimmory gets it when Wi-Fi is on.")
    end
    info(text, 3)
end

--- The Grimmory book ids of files `paths` (a list), and how many aren't from Grimmory.
local function bookIds(plugin, paths)
    local ids, others = {}, 0
    for _i, p in ipairs(paths) do
        local id = plugin:entryForPath(p)
        if id ~= nil then ids[#ids + 1] = id else others = others + 1 end
    end
    return ids, others
end

local function notFromGrimmory()
    local _ = require("gettext")
    info(_("This book isn't from your Grimmory library, so it can't go on a Grimmory shelf."), 4)
end

--- Add to shelf for files `paths` (one book, or several selected).
function Shelves.showAdd(plugin, paths, on_change)
    local _ = require("gettext")
    local T = require("ffi/util").template
    if not Shelves.ready(plugin) then return end
    local ids, others = bookIds(plugin, paths)
    if #ids == 0 then
        if #paths > 1 then return info(_("None of these books are from your Grimmory library, so they can't go on a Grimmory shelf."), 4) end
        return notFromGrimmory()
    end
    shelvesThen(plugin, function(mine)
        if #mine == 0 then
            return info(_("You have no shelves in Grimmory yet. Make one in Grimmory's web app (the + next to Shelves); it comes to this Kindle with the next sync."), 6)
        end
        local items = {}
        for _i, sh in ipairs(mine) do
            local all = true
            for _j, id in ipairs(ids) do if not Shelves.isOn(plugin, id, sh.id) then all = false break end end
            items[#items + 1] = { text = sh.name .. (all and "  ✓" or ""), dim = all or nil,
                mandatory = all and _("on it") or nil, gz_shelf = sh }
        end
        picker(#ids > 1 and T(_("Add %1 books to shelf"), #ids) or _("Add to shelf"), items, function(item)
            Shelves.set(plugin, ids, item.gz_shelf.id, true)
            local text = #ids > 1 and T(_("Added %1 books to “%2”."), #ids, item.gz_shelf.name)
                or T(_("Added to “%1”."), item.gz_shelf.name)
            if others > 0 then text = text .. "\n" .. T(_("%1 not from Grimmory left out."), others) end
            after(plugin, text)
            if on_change then pcall(on_change) end
        end)
    end)
end

--- Remove from shelf: straight off when it's on one of your shelves; a
--- choice (one of them, or all) when it's on several.
function Shelves.showRemove(plugin, path, on_change)
    local _ = require("gettext")
    local T = require("ffi/util").template
    if not Shelves.ready(plugin) then return end
    local id = plugin:entryForPath(path)
    if id == nil then return notFromGrimmory() end
    local on = Shelves.on(plugin, id)
    local function off(list, what)
        for _i, sh in ipairs(list) do Shelves.set(plugin, { id }, sh.id, false) end
        after(plugin, what)
        if on_change then pcall(on_change) end
    end
    if #on == 0 then return info(_("This book isn't on any of your shelves."), 3) end
    if #on == 1 then return off(on, T(_("Removed from “%1”."), on[1].name)) end
    local items = {}
    for _i, sh in ipairs(on) do items[#items + 1] = { text = sh.name, gz_shelf = sh } end
    items[#items + 1] = { text = T(_("All %1 shelves"), #on), gz_all = true }
    picker(_("Remove from shelf"), items, function(item)
        if item.gz_all then off(on, T(_("Removed from %1 shelves."), #on))
        else off({ item.gz_shelf }, T(_("Removed from “%1”."), item.gz_shelf.name)) end
    end)
end

--- The book menu's shelf buttons for file `path` (always: Add to shelf;
--- Remove from shelf/shelves when it's on any of yours):
--- { { kind = "add" | "remove", text = …, submenu = a list follows, callback = fn } }.
--- on_change(): after it went on or off a shelf.
function Shelves.buttons(plugin, path, on_change)
    local _ = require("gettext")
    local out = { { kind = "add", text = _("Add to shelf"), submenu = true,
        callback = function() Shelves.showAdd(plugin, { path }, on_change) end } }
    local id = path and plugin:entryForPath(path)
    local n = id ~= nil and #Shelves.on(plugin, id) or 0
    if n > 0 then
        out[2] = { kind = "remove", text = n == 1 and _("Remove from shelf") or _("Remove from shelves"), submenu = n > 1,
            callback = function() Shelves.showRemove(plugin, path, on_change) end }
    end
    return out
end

return Shelves
