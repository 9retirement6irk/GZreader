--[[--
BookOrbit as the book server, in place of Grimmory.

The same methods as the Grimmory client (gzreader_api.lua), answering in the
shapes the rest of GZreader already reads (a list page's `content`, a book's
`primaryFileType`…), so the Catalog, the library index, covers and downloads
work unchanged. Main swaps `plugin.api`'s class to this one when the sign-in
is a BookOrbit one (`store.backend == "bookorbit"`, Grimmory:useBackend).

BookOrbit's KOReader API (/api/v1/koreader/…) is what it offers e-readers:
  * sign-in: the KOReader sync user name and password from BookOrbit's
    Settings → KOReader, sent on every request as x-auth-user and x-auth-key
    (the password's MD5, as KOReader's own sync does). Only that MD5 is kept
    (store.bookorbit.key; off the USB drive, gzreader_secrets.lua): the
    password itself is never stored.
  * the catalog: /koreader/plugin/catalog/… (sections, books, a book, its
    cover, its file).

This is the first part: sign in, browse, covers, download. Reading progress,
highlights, bookmarks, statistics, collections and audiobooks are not sent to
BookOrbit yet (`books_only`: main and the sync modules leave them alone), so
every method for those answers nil, "unsupported".

Written from BookOrbit's routes and field names; none of its code is here.
]]

local Api = require("gzreader_api")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local Log = require("gzreader_log")

local BookOrbit = {
    books_only = true,
    NAME = "BookOrbit",
    BASE = "/api/v1/koreader",
    CATALOG = "/api/v1/koreader/plugin/catalog",
    PAGE_MAX = 100, -- (the server's limit for one page)
    -- what KOReader opens, in the order a book with several files is offered
    READABLE = { "epub", "kepub", "azw3", "mobi", "fb2", "pdf", "cbz", "cbr", "djvu", "txt" },
    AUDIO = { m4b = true, mp3 = true, m4a = true, flac = true, ogg = true, opus = true, aac = true, wav = true },
    READABLE_TYPES = Api.READABLE_TYPES,
    IN_PROGRESS = Api.IN_PROGRESS,
}
BookOrbit.__index = BookOrbit

local READABLE_RANK = {}
for i, f in ipairs(BookOrbit.READABLE) do READABLE_RANK[f] = i end

-- (JSON null is a function here: only real values are taken)
local function s(v) return type(v) == "string" and v ~= "" and v or nil end
local function n(v) return type(v) == "number" and v or nil end
local function list(v) return type(v) == "table" and v or {} end

function BookOrbit:new(store, on_change)
    return setmetatable({ store = store, on_change = on_change or function() end }, self)
end

function BookOrbit:isPaired()
    local b = self.store.bookorbit
    return self.store.server ~= nil and type(b) == "table" and type(b.key) == "string" and b.key ~= ""
end

function BookOrbit:ensureToken()
    if self:isPaired() then return true end
    return false, "not_paired"
end

function BookOrbit:clearTokens()
    if type(self.store.bookorbit) == "table" then self.store.bookorbit.key = nil end
    self.on_change()
end

--- (nothing to tell the server: the sign-in is only kept here)
function BookOrbit:logout() self:clearTokens() end

function BookOrbit:authHeaders()
    return { ["x-auth-user"] = tostring(self.store.username or ""), ["x-auth-key"] = tostring((self.store.bookorbit or {}).key or "") }
end

--- A signed-in request. `path` is relative to the server. Returns code, data, err, headers
--- (as the Grimmory client's call does).
function BookOrbit:call(method, path, opts)
    if not self:isPaired() then return nil, nil, "not_paired" end
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.headers = self:authHeaders()
    for k, v in pairs((opts or {}).headers or {}) do o.headers[k] = v end
    local code, data, headers = Api.rawRequest(method, self.store.server .. path, o)
    if not code then return nil, nil, "unreachable" end
    if code == 401 or code == 403 then
        -- (the password was changed, or sync was switched off for it, in BookOrbit: the
        -- sign-in is kept, so switching it back on there is enough)
        Log.warn("BookOrbit refused this Kindle's sign-in (HTTP " .. tostring(code) .. ")")
        return code, data, code == 403 and "bookorbit_sync_off" or "bookorbit_refused", headers
    end
    return code, data, nil, headers
end

local function get(self, path, timeouts)
    local code, data, err = self:call("GET", path, { timeouts = timeouts or { 10, 30 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code)), code
end

--- Sign in with the KOReader sync user name and password. Returns true, or false, err.
function BookOrbit:login(server, username, password)
    local md5 = require("ffi/sha2").md5
    local key = md5(password)
    -- no scheme typed and no HTTPS: plain HTTP only on the home network (gzreader_lan.lua)
    local candidates = { server }
    local typed_bare = server:match("^https://") and not self.explicit_https
    if typed_bare and require("gzreader_lan").isPrivate(server) then
        candidates[2] = "http://" .. server:sub(9)
    end
    local last_err
    for _i, base in ipairs(candidates) do
        local code, data = Api.rawRequest("GET", base .. BookOrbit.BASE .. "/users/auth", {
            headers = { ["x-auth-user"] = username, ["x-auth-key"] = key },
            timeouts = { 10, 20 },
        })
        if code == 200 and type(data) == "table" and data.authorized == "OK" then
            self.store.server = base
            self.store.username = username
            self.store.bookorbit = { key = key }
            self.store.access_token, self.store.refresh_token, self.store.access_expires_at = nil, nil, nil
            self:readVersion()
            self.on_change()
            return true
        elseif code == 401 then
            return false, "bookorbit_credentials"
        elseif code == 403 then
            return false, "bookorbit_sync_off"
        elseif code == 429 then
            return false, "rate_limited"
        elseif code then
            -- (a 404 here: an address that answers but isn't BookOrbit, or one too old for this)
            last_err = code == 404 and "bookorbit_not_found" or ("http_" .. code)
            break
        else
            last_err = "unreachable"
        end
    end
    if last_err == "unreachable" and typed_bare and not candidates[2] then last_err = "no_https" end
    return false, last_err
end

--- What this server can do (its version and capabilities), kept for the parts that depend on it.
function BookOrbit:readVersion()
    local data = get(self, BookOrbit.BASE .. "/plugin/version", { 8, 15 })
    local b = self.store.bookorbit
    if type(data) ~= "table" or type(b) ~= "table" then return nil end
    b.server_version = s(data.serverVersion)
    b.capabilities = {}
    for _i, c in ipairs(list(data.capabilities)) do
        if type(c) == "string" then b.capabilities[c] = true end
    end
    return b.capabilities
end

function BookOrbit:can(capability)
    local b = self.store.bookorbit
    return type(b) == "table" and type(b.capabilities) == "table" and b.capabilities[capability] == true
end

function BookOrbit:me()
    if not self:isPaired() then return nil, "not_paired" end
    return { username = self.store.username, name = self.store.username }
end

---------------------------------------------------------------- books

--- The file GZreader would open: the first format KOReader reads, by READABLE's order.
function BookOrbit.pickFormat(formats)
    local best, rank
    for _i, f in ipairs(list(formats)) do
        local r = type(f) == "string" and READABLE_RANK[f:lower()]
        if r and (not rank or r < rank) then best, rank = f:lower(), r end
    end
    return best
end

local STATUS = { reading = "READING", finished = "READ", unread = "UNREAD" }

local function fileName(title, format)
    local name = tostring(title or "book"):gsub("[%c/\\:%*%?\"<>|]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("[%s%.]+$", "")
    if name == "" then name = "book" end
    if #name > 120 then name = name:sub(1, 120):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") end
    return name .. "." .. format
end
BookOrbit.fileName = fileName

--- A catalog list item as the app's book lists give one.
function BookOrbit.toBook(item)
    if type(item) ~= "table" or n(item.id) == nil then return nil end
    local format = BookOrbit.pickFormat(item.formats)
    local audio = false
    for _i, f in ipairs(list(item.formats)) do
        if type(f) == "string" and BookOrbit.AUDIO[f:lower()] then audio = true end
    end
    local authors = {}
    for _i, a in ipairs(list(item.authors)) do if s(a) then authors[#authors + 1] = a end end
    local title = s(item.title) or ("Book " .. tostring(item.id))
    return {
        id = item.id,
        title = title,
        authors = authors,
        seriesName = s(item.seriesName),
        seriesNumber = n(item.seriesIndex),
        primaryFileType = format and format:upper() or (audio and "AUDIOBOOK" or nil),
        primaryFileName = format and fileName(title, format) or nil,
        readProgress = n(item.progressPercentage), -- (0–100, as Grimmory's)
        lastReadTime = s(item.lastReadAt),
        readStatus = STATUS[item.readStatus],
        addedOn = s(item.addedAt),
        hasCover = item.hasCover == true,
    }
end

local SORT = { title = "title", addedOn = "recently_added", lastReadTime = "recently_read", seriesNumber = "series",
    author = "author", publishedDate = "published", updatedOn = "recently_updated" }

local function wantsOnlyAudio(types)
    if type(types) ~= "table" or #types == 0 then return false end
    for _i, t in ipairs(types) do
        if tostring(t):upper() ~= "AUDIOBOOK" then return false end
    end
    return true
end

local function emptyPage(page, size)
    return { content = {}, page = page, size = size, totalElements = 0, totalPages = 0, hasNext = false, hasPrevious = page > 0 }
end

--- A page of books. params as the Grimmory client's: page (from 0), size, sort, dir, search,
--- libraryId, shelfId (a collection), magicShelfId (a SmartScope), authors, series, status, fileType.
function BookOrbit:listBooks(params)
    params = params or {}
    local page, size = tonumber(params.page) or 0, math.min(tonumber(params.size) or 20, BookOrbit.PAGE_MAX)
    if wantsOnlyAudio(params.fileType) then return emptyPage(page, size) end -- (audiobooks: not yet)
    local q = { page = page + 1, size = size, sort = SORT[params.sort] or "title",
        order = (params.dir == "asc" or params.dir == "desc") and params.dir or nil,
        q = s(params.search), libraryId = params.libraryId, collectionId = params.shelfId, smartScopeId = params.magicShelfId,
        author = s(params.authors), series = s(params.series) }
    if type(params.status) == "table" or params.status == "READING" then q.readStatus = "reading" end
    local data, err = get(self, BookOrbit.CATALOG .. "/books" .. Api.query(q), { 15, 45 })
    if not data then return nil, err end
    local content = {}
    for _i, item in ipairs(list(data.items)) do
        local book = BookOrbit.toBook(item)
        -- (a book with nothing KOReader opens, an audiobook say, isn't listed among the books)
        if book and book.primaryFileType and book.primaryFileType ~= "AUDIOBOOK" then content[#content + 1] = book end
    end
    local total = n(data.total) or #content
    return { content = content, page = page, size = size, totalElements = total,
        totalPages = math.ceil(total / size), hasNext = data.hasNext == true, hasPrevious = data.hasPrevious == true }
end

function BookOrbit:searchBooks(q, page, size)
    return self:listBooks{ search = q, page = page or 0, size = size or 25, sort = "title", dir = "asc" }
end

--- The Grimmory lists the home page asks for by name.
function BookOrbit:simpleList(endpoint, limit)
    local params = { page = 0, size = limit or 20, sort = "addedOn", dir = "desc" }
    if endpoint == "continue-reading" then params.sort, params.status = "lastReadTime", BookOrbit.IN_PROGRESS end
    local data, err = self:listBooks(params)
    if not data then return nil, err end
    return data.content
end

function BookOrbit:continueReading(limit) return self:simpleList("continue-reading", limit) end

local function section(self, name)
    local data, err = get(self, BookOrbit.CATALOG .. "/sections/" .. name)
    if not data then return nil, err end
    local out = {}
    for _i, e in ipairs(list(data.items)) do
        local id = type(e) == "table" and (tonumber(e.id) or s(e.id))
        if id then out[#out + 1] = { id = id, name = s(e.title) or tostring(id), bookCount = n(e.count) } end
    end
    return out
end

function BookOrbit:listLibraries() return section(self, "libraries") end

--- How many books each library has ({ [id as text] = count }), for the library index:
--- BookOrbit's book lists don't say which library a book is in.
function BookOrbit:libraryCounts()
    local libs = section(self, "libraries")
    if not libs then return nil end
    local out = {}
    for _i, lib in ipairs(libs) do out[tostring(lib.id)] = lib.bookCount or 0 end
    return out
end

--- Collections, and SmartScopes as the "magic" ones.
function BookOrbit:listShelves()
    local out, err = section(self, "collections")
    if not out then return nil, err end
    for _i, e in ipairs(section(self, "smart-scopes") or {}) do
        e.magic = true
        out[#out + 1] = e
    end
    return out
end

local function detail(self, book_id)
    return get(self, BookOrbit.CATALOG .. "/books/" .. tostring(book_id), { 10, 20 })
end

--- The file of a book's detail that GZreader downloads: one of the book's own files
--- (role "primary", its main file, or "content", another one; both download) in the
--- first format KOReader reads; the main file when two share that format.
function BookOrbit.pickFile(d)
    local best, rank
    for _i, f in ipairs(list(type(d) == "table" and d.files)) do
        local r = type(f) == "table" and type(f.format) == "string" and READABLE_RANK[f.format:lower()]
        if r and (f.role == "primary" or f.role == "content") and s(f.downloadUrl) then
            r = r * 2 - (f.role == "primary" and 1 or 0)
            if not rank or r < rank then best, rank = f, r end
        end
    end
    return best
end

local function names(v)
    local out = {}
    for _i, x in ipairs(list(v)) do
        local name = s(x) or (type(x) == "table" and s(x.name))
        if name then out[#out + 1] = name end
    end
    return out
end

--- A book's record, as Grimmory's /books/{id}: its file and metadata.
function BookOrbit:getBook(book_id)
    local d, err = detail(self, book_id)
    if not d then return nil, err end
    local f = BookOrbit.pickFile(d)
    local book = BookOrbit.toBook(d) or { id = d.id }
    book.primaryFile = f and { id = f.id, bookType = f.format:upper(), fileSizeKb = n(f.sizeBytes) and math.ceil(f.sizeBytes / 1024) or nil,
        fileHash = s(f.fileHash) } or nil
    book.primaryFileId = f and f.id or nil
    book.fileSizeKb = book.primaryFile and book.primaryFile.fileSizeKb or nil
    book.libraryId = n(d.libraryId)
    book.metadata = { title = book.title, subtitle = s(d.subtitle), description = s(d.description), publisher = s(d.publisher),
        publishedDate = s(d.publishedDate), pageCount = n(d.pageCount), seriesName = book.seriesName, seriesNumber = book.seriesNumber,
        categories = names(d.genres), authors = book.authors }
    return book
end

--- A book's page (description, publisher…), as Grimmory's app detail.
function BookOrbit:getBookDetail(book_id)
    local book, err = self:getBook(book_id)
    if not book then return nil, err end
    local m = book.metadata
    return { id = book.id, title = book.title, subtitle = m.subtitle, description = m.description, categories = m.categories,
        pageCount = m.pageCount, publisher = m.publisher, publishedDate = m.publishedDate,
        seriesName = m.seriesName, seriesNumber = m.seriesNumber }
end

---------------------------------------------------------------- covers and files

function BookOrbit:downloadThumbnail(book_id, path, kind)
    if not self:isPaired() then return false, "not_paired" end
    if kind == "audiobook" then return false, "http_404", 404 end -- (audiobooks: not yet)
    local part = path .. ".part"
    local fh, ferr = io.open(part, "wb")
    if not fh then return false, ferr end
    local headers = self:authHeaders()
    headers["Accept"] = "image/*"
    local code, _, resp = Api.rawRequest("GET", self.store.server .. BookOrbit.CATALOG .. "/books/" .. tostring(book_id) .. "/thumbnail", {
        headers = headers, sink = ltn12.sink.file(fh), timeouts = { 10, 30 },
    })
    local ctype = type(resp) == "table" and (resp["content-type"] or resp["Content-Type"]) or ""
    if code == 200 and (lfs.attributes(part, "size") or 0) > 0 and tostring(ctype):find("image", 1, true) then
        os.rename(part, path)
        return true
    end
    os.remove(part)
    return false, code and ("http_" .. code) or "unreachable", code
end

function BookOrbit:downloadThumbnails(items)
    local got, none = 0, {}
    for _i, it in ipairs(items or {}) do
        local ok, err, code = self:downloadThumbnail(it.id, it.path, it.kind)
        if ok then
            got = got + 1
        elseif code == 404 then
            none[#none + 1] = it.id
        elseif err == "unreachable" or err == "not_paired" or code == 401 or code == 403 then
            break
        end
    end
    return { got = got, none = none }
end

--- A book's file straight into `path`. BookOrbit's download doesn't continue a part
--- (no Range), so a part left by an interrupted download is started again.
function BookOrbit:downloadToFile(book_id, path, _resume)
    local d, err = detail(self, book_id)
    if not d then return false, err end
    local f = BookOrbit.pickFile(d)
    if not f then return false, "bookorbit_no_file" end
    local fh, ferr = io.open(path, "wb")
    if not fh then return false, ferr end
    local headers = self:authHeaders()
    headers["Accept"] = "*/*"
    -- (the address the server gave for this file; only ever on the signed-in server)
    local where = f.downloadUrl:sub(1, 1) == "/" and f.downloadUrl or (BookOrbit.CATALOG .. "/files/" .. tostring(f.id) .. "/download")
    local code, _, resp, status = Api.rawRequest("GET", self.store.server .. where, {
        headers = headers,
        sink = require("gzreader_xferlog").sink(ltn12.sink.file(fh), "book " .. tostring(book_id)),
        timeouts = { 30, -1 },
    })
    if code == 200 then
        local want = type(resp) == "table" and tonumber(resp["content-length"])
        local have = lfs.attributes(path, "size") or 0
        if have > 0 and (not want or want == have) then return true end
        os.remove(path)
        return false, "stalled: " .. tostring(have) .. " of " .. tostring(want) .. " bytes"
    end
    os.remove(path)
    return false, code and ("http_" .. code) or tostring(status or "unreachable")
end

---------------------------------------------------------------- not yet

-- Grimmory-only (its single sign-on, its web list) or not sent to BookOrbit yet: each
-- answers nil, "unsupported". Main and the sync modules don't call them while
-- `books_only` is set; this is so a call that slips through fails quietly.
for _i, name in ipairs{ "listWebBooks", "listMyShelves", "setBookShelves", "listAuthors", "listSeries", "putProgress",
    "audiobookInfo", "downloadAudio", "listBookmarks", "createBookmark", "deleteBookmark", "listAnnotations",
    "createAnnotation", "updateAnnotation", "deleteAnnotation", "listBookNotes", "createBookNote", "updateBookNote",
    "deleteBookNote", "putRating", "postSession", "hasSession", "publicSettings", "oidcExchange" } do
    BookOrbit[name] = function() return nil, "unsupported" end
end

return BookOrbit
