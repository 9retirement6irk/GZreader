--[[--
Grimmory without a network: the API the Grimmory tab uses, answered from a
copy of your library the USB sync page leaves on the Kindle
(GZreader/.gzsync/library.json, small covers in .gzsync/covers). For the
Kindles without Wi-Fi (Kindle 2, DX: gzreader_usbsync.lua).

Reads (book lists, search, libraries, shelves, a book's record with its
reading positions, its page, an audiobook's details, covers) come from the
copy. Writes (positions, reading time, ratings, bookmarks) fail as
"usb": the code that sends them keeps them queued, as when Wi-Fi is off, and
the outbox carries them to the sync page.

The copy, as the page writes it:
  { format = 1, written_at, server, user,
    books = { app book summaries: books and audiobooks },
    libraries = {…}, shelves = {… magic = true for magic shelves},
    lists = { shelf = { [id] = { book ids } }, magic = { [id] = {…} },
              continue = { ids }, recent = { ids } },
    full = { [id] = GET /api/v1/books/{id} (books on the Kindle: positions) },
    audio = { [id] = GET /api/v1/audiobooks/{id}/info },
    subtitles = { [id] = "…" } }
  details/<id>.json = GET /api/v1/app/books/{id} (a book's page)
]]

local Api = require("gzreader_api")
local JSON = require("gzreader_json")
local lfs = require("libs/libkoreader-lfs")

local OfflineApi = setmetatable({}, { __index = Api })
OfflineApi.__index = OfflineApi

local NOT = "usb" -- what a write answers: not sent, kept queued

function OfflineApi:new(store, on_change, dir)
    return setmetatable({ store = store, on_change = on_change or function() end, dir = dir, offline = true }, self)
end

local cache = { path = nil, mtime = nil, data = nil }

--- The library copy (read again when the page wrote a new one), or nil.
function OfflineApi:snapshot()
    local path = self.dir .. "/library.json"
    local mtime = lfs.attributes(path, "modification")
    if not mtime then return nil end
    if cache.path == path and cache.mtime == mtime and cache.data then return cache.data end
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    if not ok or type(data) ~= "table" or type(data.books) ~= "table" then return nil end
    -- by id, for lists of ids
    data.by_id = {}
    for _i, b in ipairs(data.books) do
        if type(b) == "table" and b.id ~= nil then data.by_id[tostring(b.id)] = b end
    end
    cache.path, cache.mtime, cache.data = path, mtime, data
    return data
end

function OfflineApi.forget() cache.path, cache.mtime, cache.data = nil, nil, nil end

-- Connected: a copy of the library is here (asked often: not read for it).
function OfflineApi:isPaired() return lfs.attributes(self.dir .. "/library.json", "mode") == "file" end
function OfflineApi:ensureToken() return true end
function OfflineApi:call() return nil, nil, NOT end
function OfflineApi:login() return false, NOT end
function OfflineApi:logout() end
function OfflineApi:clearTokens() end

-- (writes: kept queued, sent from the computer)
function OfflineApi:putProgress() return false, NOT end
function OfflineApi:postSession() return false, NOT end
function OfflineApi:hasSession() return nil end
function OfflineApi:putRating() return false, NOT end
-- (bookmarks and highlights: written to the journal, below)
function OfflineApi:downloadToFile() return false, NOT end
function OfflineApi:downloadAudio() return false, NOT, false end

---------------------------------------------------------------- lists

local function set(list)
    if type(list) ~= "table" then return nil end
    local s = {}
    for _i, v in ipairs(list) do s[tostring(v):upper()] = true end
    return next(s) and s or nil
end

local function lower(s) return type(s) == "string" and s:lower() or "" end

local function hasAuthor(b, name)
    for _i, a in ipairs(type(b.authors) == "table" and b.authors or {}) do
        if a == name then return true end
    end
    return false
end

-- sort keys: what's missing goes last (whichever the direction)
local function sorter(field, dir)
    local desc = dir == "desc"
    local function key(b)
        local v = b[field]
        if field == "title" then return lower(b.title) end
        if field == "seriesName" then return lower(b.seriesName) end
        if type(v) == "string" then return v:lower() end
        return v
    end
    return function(a, b)
        local ka, kb = key(a), key(b)
        if ka == nil or kb == nil or type(ka) ~= type(kb) then
            if (ka == nil) ~= (kb == nil) then return kb == nil end
            return lower(a.title) < lower(b.title)
        end
        if ka == kb then
            if field == "seriesName" and a.seriesNumber and b.seriesNumber and a.seriesNumber ~= b.seriesNumber then
                return a.seriesNumber < b.seriesNumber
            end
            return lower(a.title) < lower(b.title)
        end
        if desc then return ka > kb end
        return ka < kb
    end
end

local function page(items, p, size)
    p, size = tonumber(p) or 0, tonumber(size) or 25
    local out = {}
    for i = p * size + 1, math.min(#items, (p + 1) * size) do out[#out + 1] = items[i] end
    local pages = math.max(1, math.ceil(#items / size))
    return { content = out, page = p, size = size, totalElements = #items, totalPages = pages,
        hasNext = p + 1 < pages, hasPrevious = p > 0 }
end
OfflineApi.page = page

local function byIds(snap, ids)
    local out = {}
    for _i, id in ipairs(type(ids) == "table" and ids or {}) do
        local b = snap.by_id[tostring(id)]
        if b then out[#out + 1] = b end
    end
    return out
end

--- The book list (GET /api/v1/app/books): fileType, libraryId, shelfId,
--- magicShelfId, authors, series, status, search; sorted; a page.
function OfflineApi:listBooks(params)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    params = params or {}
    local pool = snap.books
    local lists = type(snap.lists) == "table" and snap.lists or {}
    if params.shelfId then pool = byIds(snap, (lists.shelf or {})[tostring(params.shelfId)])
    elseif params.magicShelfId then pool = byIds(snap, (lists.magic or {})[tostring(params.magicShelfId)]) end
    local types, status = set(params.fileType), set(params.status)
    local lib = params.libraryId and tostring(params.libraryId)
    local q = params.search and lower(params.search) or nil
    local out = {}
    for _i, b in ipairs(pool) do
        local t = type(b.primaryFileType) == "string" and b.primaryFileType:upper() or ""
        local ok = (not types or types[t])
            and (not lib or tostring(b.libraryId) == lib)
            and (not params.authors or hasAuthor(b, params.authors))
            and (not params.series or b.seriesName == params.series)
            and (not status or status[tostring(b.readStatus or ""):upper()])
            and (not q or OfflineApi.matches(b, q))
        if ok then out[#out + 1] = b end
    end
    if params.sort then table.sort(out, sorter(params.sort, params.dir)) end
    return page(out, params.page, params.size)
end

--- Does a book match a search (title, subtitle, authors, series)?
function OfflineApi.matches(b, q)
    if lower(b.title):find(q, 1, true) or lower(b.seriesName):find(q, 1, true) then return true end
    for _i, a in ipairs(type(b.authors) == "table" and b.authors or {}) do
        if lower(a):find(q, 1, true) then return true end
    end
    return false
end

function OfflineApi:searchBooks(q, p, size)
    return self:listBooks{ search = q, page = p, size = size, sort = "title", dir = "asc" }
end

--- recently-added, continue-reading (and anything else: nothing)
function OfflineApi:simpleList(endpoint, limit)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    local lists = type(snap.lists) == "table" and snap.lists or {}
    local out
    if endpoint == "continue-reading" then out = byIds(snap, lists.continue)
    elseif endpoint == "recently-added" then
        if lists.recent then out = byIds(snap, lists.recent)
        else
            out = {}
            for _i, b in ipairs(snap.books) do out[#out + 1] = b end
            table.sort(out, sorter("addedOn", "desc"))
        end
    else out = {} end
    limit = tonumber(limit) or 20
    while #out > limit do out[#out] = nil end
    return out
end

function OfflineApi:continueReading(limit) return self:simpleList("continue-reading", limit) end

function OfflineApi:listLibraries()
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    return type(snap.libraries) == "table" and snap.libraries or {}
end

function OfflineApi:listShelves()
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    return type(snap.shelves) == "table" and snap.shelves or {}
end

--- The web book list: only for subtitles (gzreader_index.lua).
function OfflineApi:listWebBooks(p)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    local out = {}
    if (tonumber(p) or 0) == 0 then
        for id, sub in pairs(type(snap.subtitles) == "table" and snap.subtitles or {}) do
            out[#out + 1] = { id = tonumber(id) or id, metadata = { subtitle = sub } }
        end
    end
    return { content = out, totalPages = 1 }
end

---------------------------------------------------------------- one book

function OfflineApi:getBook(book_id)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    local full = type(snap.full) == "table" and snap.full[tostring(book_id)]
    if type(full) == "table" then return full end
    return nil, NOT
end

function OfflineApi:getBookDetail(book_id)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    -- (a book's page: one file each, details/<id>.json, so the copy stays small)
    local f = io.open(self.dir .. "/details/" .. tostring(book_id):gsub("[^%w]", "") .. ".json", "rb")
    if f then
        local ok, d = pcall(JSON.decode, f:read("*a"))
        f:close()
        if ok and type(d) == "table" then return d end
    end
    local b = snap.by_id[tostring(book_id)]
    if not b then return nil, NOT end
    -- what the summary has, with the subtitle
    return { id = b.id, title = b.title, subtitle = type(snap.subtitles) == "table" and snap.subtitles[tostring(book_id)] or nil,
        seriesName = b.seriesName, seriesNumber = b.seriesNumber }
end

function OfflineApi:audiobookInfo(book_id)
    local snap = self:snapshot()
    if not snap then return nil, "not_paired" end
    local a = type(snap.audio) == "table" and snap.audio[tostring(book_id)]
    if type(a) == "table" then return a end
    return nil, NOT
end

---------------------------------------------------------------- bookmarks and highlights

--[[ Bookmarks and highlights go through the journal (.gzsync/journal.jsonl):
each create, change or delete made on the Kindle is a line, as the request
the sync page sends to Grimmory, in order. Something made here gets a
temporary id ("usb-…"): the page swaps it for Grimmory's own when it sends
the request, and tells the Kindle (inbox.created), which then uses Grimmory's
id. Grimmory's lists, as GZreader sees them here, are the page's copy
(library.json: marks, for the books on the Kindle) with what the journal
still has to send applied on top: the code that syncs bookmarks and
highlights (gzreader_bookmarks.lua, gzreader_annotations.lua) runs as it
does with Wi-Fi. Appending a line is safe from the background process
those run in. ]]

function OfflineApi:journalPath() return self.dir .. "/journal.jsonl" end

--- The journal's lines still to send (each { id, op, method, path, body, temp, ref, book }).
function OfflineApi:journal()
    local out = {}
    local f = io.open(self:journalPath(), "rb")
    if not f then return out end
    for line in f:lines() do
        local ok, j = pcall(JSON.decode, line)
        if ok and type(j) == "table" and j.id then out[#out + 1] = j end
    end
    f:close()
    return out
end

local function uid()
    local ok, PS = pcall(require, "gzreader_pairserver")
    local r = ok and PS.randomToken(4) or tostring(math.random(1e9))
    return tostring(os.time()) .. "-" .. r
end

function OfflineApi:record(j)
    j.id = "m:" .. uid()
    j.at = os.time()
    local f = io.open(self:journalPath(), "ab")
    if not f then return false end
    f:write(JSON.encode(j), "\n")
    f:close()
    return true
end

function OfflineApi:createBookmark(body)
    local temp = "usb-" .. uid()
    if not self:record{ op = "bookmark+", method = "POST", path = "/api/v1/bookmarks", body = body, temp = temp, book = body.bookId } then
        return nil, NOT
    end
    local made = {}
    for k, v in pairs(body) do made[k] = v end
    made.id = temp
    return made
end

function OfflineApi:deleteBookmark(id)
    if not self:record{ op = "bookmark-", method = "DELETE", path = "/api/v1/bookmarks/{id}", ref = tostring(id) } then return false, NOT end
    return true
end

function OfflineApi:createAnnotation(body)
    local temp = "usb-" .. uid()
    if not self:record{ op = "highlight+", method = "POST", path = "/api/v1/annotations", body = body, temp = temp, book = body.bookId } then
        return nil, NOT
    end
    local made = {}
    for k, v in pairs(body) do made[k] = v end
    made.id = temp
    return made, nil, 201
end

function OfflineApi:updateAnnotation(id, body)
    if not self:record{ op = "highlight~", method = "PUT", path = "/api/v1/annotations/{id}", ref = tostring(id), body = body } then
        return nil, NOT
    end
    return true, nil, 200
end

function OfflineApi:deleteAnnotation(id)
    if not self:record{ op = "highlight-", method = "DELETE", path = "/api/v1/annotations/{id}", ref = tostring(id) } then
        return false, NOT
    end
    return true, nil, 204
end

--- Grimmory's list (the page's copy) with the journal applied.
function OfflineApi:marks(book_id, kind)
    local snap = self:snapshot()
    local m = snap and type(snap.marks) == "table" and snap.marks[tostring(book_id)]
    if type(m) ~= "table" or type(m[kind]) ~= "table" then return nil end -- (not in the copy yet: nothing to compare)
    local list, at = {}, {}
    for _i, x in ipairs(m[kind]) do
        if type(x) == "table" then
            local c = {}
            for k, v in pairs(x) do c[k] = v end
            list[#list + 1] = c
            at[tostring(c.id)] = c
        end
    end
    local plus, change, minus = kind == "bookmarks" and "bookmark+" or "highlight+", "highlight~",
        kind == "bookmarks" and "bookmark-" or "highlight-"
    for _i, j in ipairs(self:journal()) do
        if j.op == plus and type(j.body) == "table" and tostring(j.book or j.body.bookId) == tostring(book_id) then
            local c = {}
            for k, v in pairs(j.body) do c[k] = v end
            c.id = j.temp
            list[#list + 1] = c
            at[tostring(c.id)] = c
        elseif j.op == change and at[tostring(j.ref)] and type(j.body) == "table" then
            for k, v in pairs(j.body) do at[tostring(j.ref)][k] = v end
        elseif j.op == minus and at[tostring(j.ref)] then
            local gone = at[tostring(j.ref)]
            at[tostring(j.ref)] = nil
            for i = #list, 1, -1 do if list[i] == gone then table.remove(list, i) end end
        end
    end
    return list
end

function OfflineApi:listBookmarks(book_id)
    local l = self:marks(book_id, "bookmarks")
    if l then return l end
    return nil, NOT
end

function OfflineApi:listAnnotations(book_id)
    local l = self:marks(book_id, "annotations")
    if l then return l end
    return nil, NOT
end

---------------------------------------------------------------- covers

--- A cover from the copy (covers/<id>.jpg, an audiobook's <id>-a.jpg).
function OfflineApi:downloadThumbnail(book_id, path, kind)
    local src = self.dir .. "/covers/" .. tostring(book_id) .. (kind == "audiobook" and "-a" or "") .. ".jpg"
    local inp = io.open(src, "rb")
    if not inp then return false, "http_404", 404 end
    local data = inp:read("*a")
    inp:close()
    local out = io.open(path, "wb")
    if not out then return false, "can't write" end
    out:write(data)
    out:close()
    return true
end

function OfflineApi:downloadThumbnails(items)
    local got, none = 0, {}
    for _i, it in ipairs(items or {}) do
        if self:downloadThumbnail(it.id, it.path, it.kind) then got = got + 1 else none[#none + 1] = it.id end
    end
    return { got = got, none = none }
end

return OfflineApi
