--[[--
BookOrbit as the book server, in place of Grimmory.

The same methods as the Grimmory client (gzreader_api.lua), answering in the
shapes the rest of GZreader already reads (a list page's `content`, a book's
`primaryFileType`…), so the Catalog, the library index, covers and downloads
work unchanged. Main swaps `plugin.api`'s class to this one when the sign-in
is a BookOrbit one (`store.backend == "bookorbit"`, Grimmory:useBackend).

BookOrbit's KOReader API (/api/v1/koreader/…) is what it offers e-readers:
  * sign-in: the KOReader sync user name and password from BookOrbit's
    Settings → Devices → KOReader, sent on every request as x-auth-user and x-auth-key
    (the password's MD5, as KOReader's own sync does). Only that MD5 is kept
    (store.bookorbit.key; off the USB drive, gzreader_secrets.lua): the
    password itself is never stored.
  * the catalog: /koreader/plugin/catalog/… (sections, books, a book, its
    cover, its file).

What is synced with BookOrbit so far is in `supports` (main's serverCan): reading
progress. Highlights, bookmarks, statistics, collections and audiobooks are not
yet, so every method for those answers nil, "unsupported"; `books_only` keeps
the Grimmory-only parts (its statistics, shelf editing, copying the sign-in) off.

Books are told apart by their file's fingerprint (KOReader's partial MD5, kept
as the download's `hash`): progress is sent by it, and the files already on the
Kindle are matched to BookOrbit's books by it (matchCheck).
  * progress out: POST /koreader/plugin/progress, the percentage as KOReader counts
    it (0-1) and the page's XPointer (or the page number): BookOrbit turns that
    into its web reader's place itself, so nothing is converted here.
  * progress in: the book's catalog record (its `progress`), given to
    gzreader_sync.lua in the shape it reads Grimmory's in.

Written from BookOrbit's routes and field names; none of its code is here.
]]

local Api = require("gzreader_api")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local BookOrbit = {
    books_only = true,
    supports = { progress = true, annotations = true, bookmarks = true, audiobooks = true, stats = true, ratings = true },
    koreader_positions = true, -- (the percentage and place are KOReader's own, not a web reader's)
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

BookOrbit.PAGED = { pdf = true, cbz = true, cbr = true, djvu = true }

local READABLE_RANK = {}
for i, f in ipairs(BookOrbit.READABLE) do READABLE_RANK[f] = i end
BookOrbit.READABLE_EXT = READABLE_RANK

-- (JSON null is a function here: only real values are taken)
local function s(v) return type(v) == "string" and v ~= "" and v or nil end
local function n(v) return type(v) == "number" and v or nil end
local function list(v) return type(v) == "table" and v or {} end

--- What is and isn't synced with BookOrbit, in a sentence or two, for every place
--- that tells the user (the sign-in message, the setup page, the Catalog's About,
--- the setup guide): it follows `supports`, so it's right after each new part.
BookOrbit.FEATURES = {
    { "progress", _("your place in each book") },
    { "annotations", _("highlights and their notes") },
    { "bookmarks", _("bookmarks") },
    { "stats", _("reading time") },
    { "ratings", _("ratings") },
    { "audiobooks", _("audiobooks and changing collections (with a BookOrbit API key)") },
}
function BookOrbit.note()
    local yes, no = {}, {}
    for _i, f in ipairs(BookOrbit.FEATURES) do
        local into = BookOrbit.supports[f[1]] and yes or no
        into[#into + 1] = f[2]
    end
    local out = _("You can browse and download your books.")
    if #yes > 0 then out = out .. " " .. T(_("Synced with BookOrbit: %1."), table.concat(yes, ", ")) end
    if #no > 0 then out = out .. " " .. T(_("Not yet: %1."), table.concat(no, ", ")) end
    return out
end

-- (an audiobook's id here is "a<BookOrbit's id>": see "audiobooks" below)
function BookOrbit.isAudioId(id) return type(id) == "string" and id:match("^a%d+$") ~= nil end
local function audioId(id) return tonumber((tostring(id):gsub("^a", ""))) end

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
    if type(self.store.bookorbit) == "table" then self.store.bookorbit.key, self.store.bookorbit.api_key = nil, nil end
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
        local ok, err, final = self:signInWith(base, username, key)
        if ok then return true end
        last_err = err
        if final then
            if err ~= "bookorbit_not_found" and not err:match("^http_") then return false, err end
            break
        end
    end
    if last_err == "unreachable" and typed_bare and not candidates[2] then last_err = "no_https" end
    return false, last_err
end

--- Check a KOReader sync user name and key (the password's MD5) with the server at `base`
--- and, when it accepts them, keep them. Returns true; or false, err, final (true: the
--- server answered, so another address needn't be tried).
function BookOrbit:signInWith(base, username, key, api_key)
    local code, data = Api.rawRequest("GET", base .. BookOrbit.BASE .. "/users/auth", {
        headers = { ["x-auth-user"] = username, ["x-auth-key"] = key },
        timeouts = { 10, 20 },
    })
    if code == 200 and type(data) == "table" and data.authorized == "OK" then
        -- (the API key stays when this is the same server and user again)
        local old = self.store.bookorbit
        local same = type(old) == "table" and self.store.server == base and self.store.username == username
        self.store.server = base
        self.store.username = username
        self.store.bookorbit = { key = key, api_key = api_key or (same and old.api_key) or nil, delivery = same and old.delivery or nil }
        self:deviceId()
        self.store.access_token, self.store.refresh_token, self.store.access_expires_at = nil, nil, nil
        self:readVersion()
        self.on_change()
        return true
    elseif code == 401 then
        return false, "bookorbit_credentials", true
    elseif code == 403 then
        return false, "bookorbit_sync_off", true
    elseif code == 429 then
        return false, "rate_limited", true
    elseif code then
        -- (a 404 here: an address that answers but isn't BookOrbit, or one too old for this)
        return false, code == 404 and "bookorbit_not_found" or ("http_" .. code), true
    end
    return false, "unreachable"
end

--- A password nobody has to remember (48 hex digits), for a sign-in GZreader makes itself.
local function newPassword()
    local f = io.open("/dev/urandom", "rb")
    local bytes = f and f:read(24)
    if f then f:close() end
    if type(bytes) == "string" and #bytes == 24 then
        return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
    end
    local md5 = require("ffi/sha2").md5
    local seed = tostring(os.time()) .. tostring(os.clock()) .. tostring({}) .. tostring(math.random())
    return md5(seed) .. md5(seed .. tostring({})):sub(1, 16)
end

--- Sign in with only an API key: BookOrbit is asked, with the key, for the account's
--- KOReader sync sign-in, and the Kindle then signs in with that as usual.
---   * There is one already: its user name (GET koreader/credentials) and its key, which
---     BookOrbit only hands out inside its "preconfigured plugin" download (GET
---     koreader/plugin-package: a zip whose bookorbit_provision.lua has it). Only that one
---     value is read from the zip; nothing in it is kept or run.
---   * There is none: one is made (POST koreader/credentials) under the account's name with
---     a random password that only its MD5 is kept of. It can be changed in BookOrbit.
--- The key needs the "KOReader sync" permission (and write access to make a sign-in).
--- Returns true, or false, err.
function BookOrbit:loginWithApiKey(server, api_key)
    api_key = type(api_key) == "string" and api_key:gsub("%s+", "") or ""
    if api_key == "" then return false, "bookorbit_no_api_key" end
    local auth = { ["Authorization"] = "Bearer " .. api_key }
    local candidates = { server }
    local typed_bare = server:match("^https://") and not self.explicit_https
    if typed_bare and require("gzreader_lan").isPrivate(server) then
        candidates[2] = "http://" .. server:sub(9)
    end
    local base, code, creds
    for _i, b in ipairs(candidates) do
        code, creds = Api.rawRequest("GET", b .. "/api/v1/koreader/credentials", { headers = auth, timeouts = { 10, 20 } })
        if code then base = b break end
    end
    if not base then return false, (typed_bare and not candidates[2]) and "no_https" or "unreachable" end
    if code == 401 then return false, "bookorbit_api_key_refused" end
    if code == 403 then return false, "bookorbit_key_no_kosync" end
    if code == 404 then return false, "bookorbit_not_found" end
    if code ~= 200 then return false, "http_" .. tostring(code) end
    local username, key
    if type(creds) == "table" and s(creds.username) then
        username = creds.username
        if creds.syncEnabled == false then return false, "bookorbit_sync_off" end
        local chunks, size = {}, 0
        local zcode = Api.rawRequest("GET", base .. "/api/v1/koreader/plugin-package?origin="
                .. base:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end), {
            headers = auth, timeouts = { 15, 60 }, log_url = base .. "/api/v1/koreader/plugin-package",
            sink = function(chunk)
                if chunk then
                    size = size + #chunk
                    if size > 16 * 1024 * 1024 then return nil, "too big" end
                    chunks[#chunks + 1] = chunk
                end
                return 1
            end,
        })
        if zcode == 400 then return false, "bookorbit_key_old_signin" end
        if zcode ~= 200 then return false, zcode and ("http_" .. tostring(zcode)) or "unreachable" end
        local text = require("gzreader_zipread").read(table.concat(chunks), "bookorbit_provision.lua")
        chunks = nil -- luacheck: ignore
        key = type(text) == "string" and text:match('\n%s*userkey%s*=%s*"(%x+)"') or nil
        if not key or #key ~= 32 then
            Log.warn("BookOrbit: the plugin download had no sync key in it")
            return false, "bookorbit_key_no_signin"
        end
        key = key:lower()
    else
        -- none yet: make one, named after the account
        local mcode, me = Api.rawRequest("GET", base .. "/api/v1/auth/me", { headers = auth, timeouts = { 8, 15 } })
        local name = mcode == 200 and type(me) == "table" and (s(me.username) or s(me.name)) or nil
        name = name and name:gsub("%s+", "-") or "gzreader"
        if #name < 3 then name = name .. "-reader" end
        local password = newPassword()
        local made
        for try = 1, 2 do
            -- (only a name and a password: BookOrbit's own defaults for the rest are the ones a Kindle
            -- wants: progress sync on, audiobook-only books hidden, read-aloud EPUBs text-only when it can)
            local pcode, pdata = Api.rawRequest("POST", base .. "/api/v1/koreader/credentials", {
                headers = auth, body = { username = name:sub(1, 100), password = password }, timeouts = { 10, 30 } })
            if pcode == 200 or pcode == 201 then made = true break end
            if pcode == 403 then
                return false, (type(pdata) == "table" and pdata.errorCode == "API_KEY_READ_ONLY") and "bookorbit_key_cannot_create" or "bookorbit_key_no_kosync"
            end
            local taken = pcode == 409 and type(pdata) == "table" and tostring(pdata.message):lower():find("taken", 1, true)
            if not taken or try == 2 then return false, pcode and ("http_" .. tostring(pcode)) or "unreachable" end
            name = name:sub(1, 90) .. "-" .. newPassword():sub(1, 4) -- (someone has that name: with four digits)
        end
        if not made then return false, "unreachable" end
        Log.info("BookOrbit: no e-reader sign-in existed for this account, so one was made")
        username, key = name:sub(1, 100), require("ffi/sha2").md5(password)
    end
    local ok, err = self:signInWith(base, username, key, api_key)
    if not ok then return false, err end
    self:readSyncSettings(base, api_key)
    self.on_change()
    return true
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

--- This Kindle's name to BookOrbit (its KOReader devices list): made once and kept.
function BookOrbit:deviceId()
    if type(self.store.bookorbit_device) ~= "string" or not self.store.bookorbit_device:match("^[%w_-]+$") then
        local md5 = require("ffi/sha2").md5
        self.store.bookorbit_device = "gz-" .. md5(tostring(os.time()) .. tostring(math.random()) .. tostring({})):sub(1, 16)
        self.on_change()
    end
    return self.store.bookorbit_device
end

--- What every plugin request carries: which device, and which GZreader.
function BookOrbit:deviceFields(body)
    body = body or {}
    body.deviceId = self:deviceId()
    local ok, model = pcall(function() return require("device").model end)
    body.deviceModel = ("GZreader " .. tostring(ok and model or "e-reader")):sub(1, 100)
    local okv, v = pcall(function() return require("gzreader_update").currentVersion() end)
    body.pluginVersion = ("gz" .. tostring(okv and v or "")):sub(1, 20)
    return body
end

--- KOReader's fingerprint of a file (its partial MD5), or nil.
--- (As KOReader's util.partialMD5, which its own sync and BookOrbit use: 1 KB at
--- offsets 0, 1 KB, 4 KB, 16 KB… up to 1 GB, as far as the file goes.)
function BookOrbit.hashFile(path)
    local ok, h = pcall(function()
        local f = io.open(path, "rb")
        if not f then return nil end
        local update = require("ffi/sha2").md5()
        for i = -1, 10 do
            f:seek("set", i < 0 and 0 or 1024 * 4 ^ i)
            local sample = f:read(1024)
            if not sample then break end
            update(sample)
        end
        f:close()
        return update()
    end)
    return ok and type(h) == "string" and #h == 32 and h:lower() or nil
end

--- Which of these fingerprints BookOrbit has a book for:
--- { [hash] = { book_id =, file_id = } }, or nil, err.
function BookOrbit:matchCheck(hashes)
    local out = {}
    for from = 1, #hashes, 500 do
        local part = {}
        for i = from, math.min(from + 499, #hashes) do part[#part + 1] = hashes[i] end
        local code, data, err = self:call("POST", BookOrbit.BASE .. "/plugin/match-check",
            { body = self:deviceFields({ hashes = require("gzreader_json").list(part) }), timeouts = { 10, 30 } })
        if not ((code == 200 or code == 201) and type(data) == "table") then return nil, err or ("http_" .. tostring(code)) end
        for _i, m in ipairs(list(data.matches)) do
            if type(m) == "table" and s(m.hash) and n(m.bookId) then
                out[m.hash:lower()] = { book_id = m.bookId, file_id = n(m.bookFileId) }
            end
        end
    end
    return out
end

--- Send a book's place (body as gzreader_sync.lua makes it for Grimmory, with the
--- page's XPointer in gz_xp). The book is named by its file's fingerprint
--- (the download's `hash`). Returns true, or false, err, code (404: BookOrbit has
--- no book with that file, so it isn't asked again).
function BookOrbit:putProgress(book_id, body)
    if BookOrbit.isAudioId(tostring(book_id)) then return self:putAudioProgress(tostring(book_id), body) end
    local entry = type(self.store.downloads) == "table" and self.store.downloads[tostring(book_id)]
    local hash = type(entry) == "table" and s(entry.hash)
    if not hash then return false, "bookorbit_unmatched", 404 end
    local fp = type(body) == "table" and type(body.fileProgress) == "table" and body.fileProgress or {}
    local pct = n(fp.progressPercent)
    if not pct then return false, "bookorbit_unmatched", 400 end
    local item = { hash = hash, percentage = math.max(0, math.min(1, pct / 100)), timestamp = os.time(),
        progress = s(body.gz_xp) or s(fp.positionData) }
    local code, data, err = self:call("POST", BookOrbit.BASE .. "/plugin/progress",
        { body = self:deviceFields({ items = require("gzreader_json").list({ item }) }), timeouts = { 8, 15 } })
    if (code == 200 or code == 201) and type(data) == "table" then
        for _i, r in ipairs(list(data.results)) do
            if type(r) == "table" and r.accepted == true then return true end
        end
        return false, "bookorbit_unmatched", 404
    end
    return false, err or ("http_" .. tostring(code)), code
end

--- A book's rating (value as gzreader_ratings.lua has Grimmory's: 1-10, nil for none):
--- BookOrbit's is 0-5 stars. Returns true, or false, err, code.
function BookOrbit:putRating(book_id, value)
    local stars = tonumber(value) and math.max(0, math.min(5, tonumber(value) / 2)) or 0
    local code, _, err = self:call("PUT", BookOrbit.CATALOG .. "/books/" .. tostring(book_id) .. "/rating",
        { body = { rating = stars }, timeouts = { 8, 15 } })
    if code == 200 then return true end
    return false, err or ("http_" .. tostring(code)), code
end

--- The reader's numbers as BookOrbit keeps them, over every device (gzreader_grimstats.lua):
--- GET catalog/dashboard has the streak, the year's goal, minutes read per day for the past
--- year, badges, the book read most a year ago, this year's finished books and a highlight.
--- Returns the reply, or nil, err.
function BookOrbit:readingDashboard()
    local code, data, err = self:call("GET", BookOrbit.CATALOG .. "/dashboard", { timeouts = { 10, 30 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code)), code
end

--- Reading time: pages read, by book (gzreader_bo_stats.lua). books = { { hash, bookFileId,
--- events = { { page, startTime, durationSeconds, totalPages }… } }… }.
--- Returns { unmatched = { hash… } }, or nil, err.
function BookOrbit:putPageStats(books)
    local code, data, err = self:call("POST", BookOrbit.BASE .. "/plugin/page-stats",
        { body = self:deviceFields({ books = require("gzreader_json").list(books) }), timeouts = { 10, 60 } })
    if (code == 200 or code == 201) and type(data) == "table" then
        local unmatched = {}
        for _i, h in ipairs(list(data.unmatched)) do if type(h) == "string" then unmatched[#unmatched + 1] = h:lower() end end
        return { unmatched = unmatched }
    end
    return nil, err or ("http_" .. tostring(code))
end

--- One book's highlight exchange (gzreader_bo_annotations.lua). book: { hash, keys,
--- keysComplete, sidecarState, changes }. Returns its result ({ toApply, more… }), or
--- nil, err ("bookorbit_unmatched": no book with this file; "bookorbit_incompatible":
--- BookOrbit's copy differs, so its positions can't be placed).
function BookOrbit:exchangeAnnotations(book) return self:exchange("annotations", book) end

--- The same for `kind` "annotations" (highlights) or "bookmarks" (gzreader_bo_bookmarks.lua).
function BookOrbit:exchange(kind, book)
    local body = self:deviceFields({ books = require("gzreader_json").list({ book }) })
    body.deviceTime = os.date("%Y-%m-%d %H:%M:%S") -- (BookOrbit dates what it makes in this Kindle's clock)
    local code, data, err = self:call("POST", BookOrbit.BASE .. "/plugin/" .. kind .. "/exchange", { body = body, timeouts = { 10, 45 } })
    if not ((code == 200 or code == 201) and type(data) == "table") then return nil, err or ("http_" .. tostring(code)) end
    local res = list(data.results)[1]
    if type(res) == "table" then return res end
    if #list(data.positionIncompatible) > 0 then return nil, "bookorbit_incompatible" end
    return nil, "bookorbit_unmatched"
end

--- Tell BookOrbit which of its changes were put into the book. Returns true, or false, err.
function BookOrbit:ackAnnotations(hash, applied, deleted) return self:ackExchange("annotations", hash, applied, deleted) end

function BookOrbit:ackExchange(kind, hash, applied, deleted)
    local Json = require("gzreader_json")
    local code, data, err = self:call("POST", BookOrbit.BASE .. "/plugin/" .. kind .. "/exchange-ack", {
        body = self:deviceFields({ books = Json.list({ { hash = hash, applied = Json.list(applied or {}), deleted = Json.list(deleted or {}) } }) }),
        timeouts = { 10, 30 } })
    if (code == 200 or code == 201) and type(data) == "table" then return true end
    return false, err or ("http_" .. tostring(code))
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
    if wantsOnlyAudio(params.fileType) then return self:listAudiobooks(params) end -- (the main API, with an API key)
    if s(params.category) then return self:listGenreBooks(params) end -- (genres: the main API too)
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
    if BookOrbit.isAudioId(book_id) then return self:audiobookRecord(book_id) end
    local d, err = detail(self, book_id)
    if not d then return nil, err end
    local f = BookOrbit.pickFile(d)
    local book = BookOrbit.toBook(d) or { id = d.id }
    book.primaryFile = f and { id = f.id, bookType = f.format:upper(), fileSizeKb = n(f.sizeBytes) and math.ceil(f.sizeBytes / 1024) or nil,
        fileHash = s(f.fileHash) } or nil
    book.primaryFileId = f and f.id or nil
    book.fileSizeKb = book.primaryFile and book.primaryFile.fileSizeKb or nil
    book.libraryId = n(d.libraryId)
    -- (BookOrbit's stars, 0-5, as Grimmory's 1-10: gzreader_ratings.lua reads that)
    book.personalRating = n(d.rating) and d.rating > 0 and math.floor(d.rating * 2 + 0.5) or nil
    -- where the book was left, on any device: as gzreader_sync.lua reads Grimmory's
    local p = type(d.progress) == "table" and d.progress
    if p and n(p.percentage) and p.percentage > 0 then
        local place = s(p.koreaderProgress)
        if f and BookOrbit.PAGED[f.format:lower()] then
            book.pdfProgress = { percentage = p.percentage, page = tonumber(place) }
        else
            book.epubProgress = { percentage = p.percentage }
            if place and place:sub(1, 1) == "/" then book.gz_xp = place end
        end
    end
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
    local audio = BookOrbit.isAudioId(tostring(book_id))
    if kind == "audiobook" and not audio then return false, "http_404", 404 end
    if audio and not self:hasApiKey() then return false, "bookorbit_no_api_key", 404 end
    local part = path .. ".part"
    local fh, ferr = io.open(part, "wb")
    if not fh then return false, ferr end
    local headers = audio and { ["Authorization"] = "Bearer " .. self.store.bookorbit.api_key } or self:authHeaders()
    headers["Accept"] = "image/*"
    local where = audio and ("/api/v1/books/" .. tostring(audioId(book_id)) .. "/thumbnail")
        or (BookOrbit.CATALOG .. "/books/" .. tostring(book_id) .. "/thumbnail")
    local code, _, resp = Api.rawRequest("GET", self.store.server .. where, {
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

---------------------------------------------------------------- audiobooks (the main API, with an API key)

-- BookOrbit's e-reader sign-in doesn't reach its audiobook routes (the manifest, the
-- audio files with resume, the listening position): those take an API key the user
-- makes in BookOrbit (Settings → You → API keys), kept as store.bookorbit.api_key with the
-- other secrets. Without one there are no BookOrbit audiobooks here.
--
-- A BookOrbit book can be an ebook and an audiobook at once, under one id. GZreader
-- keeps the two apart everywhere (downloads, the progress queue), so an audiobook's
-- id here is "a<id>": added in the lists below, taken off again in each call.

BookOrbit.AUDIO_PREFIX = "a"
local AUDIO_FORMATS = { "m4b", "mp3", "m4a", "flac", "ogg", "opus", "aac", "wav" }


function BookOrbit:hasApiKey()
    local b = self.store.bookorbit
    return self.store.server ~= nil and type(b) == "table" and type(b.api_key) == "string" and b.api_key ~= ""
end

--- A request with the API key. Returns code, data, err, headers.
function BookOrbit:keyCall(method, path, opts)
    if not self:hasApiKey() then return nil, nil, "bookorbit_no_api_key" end
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.headers = { ["Authorization"] = "Bearer " .. self.store.bookorbit.api_key }
    for k, v in pairs((opts or {}).headers or {}) do o.headers[k] = v end
    local code, data, headers = Api.rawRequest(method, self.store.server .. path, o)
    if not code then return nil, nil, "unreachable" end
    if code == 401 then
        Log.warn("BookOrbit refused the API key (HTTP 401): expired, deleted, or API keys switched off")
        return code, data, "bookorbit_api_key_refused", headers
    end
    if code == 403 and type(data) == "table" and data.errorCode == "API_KEY_READ_ONLY" then
        return code, data, "bookorbit_api_key_read_only", headers
    end
    return code, data, nil, headers
end

--- Check an API key against the signed-in server and keep it. Returns true, or false, err.
--- What the key has to be allowed, as BookOrbit's "Create API key" page names things
--- (checked against its source, v3.9.0; the wiki's BookOrbit page has the table):
---   Access "Read and write"   the listening position, collections, requests, making a sync sign-in
---                             ("Read only" is enough to list and download audiobooks)
---   Libraries                 the ones with your books and audiobooks
---   "KOReader sync"           signing in with only the key
---   "Request books"           requesting books
--- Nothing else: not "Download books" (audiobook files need no extra permission) and not
--- "Administrator access".
BookOrbit.KEY_NEEDS = "Access: Read and write. Libraries: all (or the ones with your books). Extra permissions: “KOReader sync” to sign in with the key, “Request books” to request books. Nothing else, and not Administrator access."

--- How BookOrbit is set to deliver this sync sign-in's read-aloud EPUBs (nil: Automatic,
--- text-only when it can; "audioless_epub"; "original": with the narration, which a
--- Kindle can't play and which makes the files much bigger). Read with the API key when
--- it may see the sync sign-in (its "KOReader sync" permission); kept as
--- store.bookorbit.delivery, false when it couldn't be read. A sign-in GZreader makes
--- itself is left on BookOrbit's defaults: progress sync on, audiobook-only books hidden
--- from the e-reader lists, delivery Automatic.
function BookOrbit:readSyncSettings(base, api_key)
    if type(self.store.bookorbit) ~= "table" then return nil end
    local code, creds = Api.rawRequest("GET", (base or self.store.server) .. "/api/v1/koreader/credentials",
        { headers = { ["Authorization"] = "Bearer " .. (api_key or self.store.bookorbit.api_key or "") }, timeouts = { 8, 15 } })
    if code == 200 and type(creds) == "table" then
        self.store.bookorbit.delivery = s(creds.readAloudDelivery) or "automatic"
        Log.info("BookOrbit: this sync sign-in's read-aloud EPUBs are delivered:", self.store.bookorbit.delivery,
            "| audiobook-only books hidden from the e-reader lists:", tostring(creds.hideAudioOnlyBooks))
    else
        self.store.bookorbit.delivery = false
    end
    return self.store.bookorbit.delivery
end

--- What the saved key turns out to be allowed, asked of the server (two small requests):
--- { signin = it may see the sync sign-in ("KOReader sync"), requests = it may request
--- books ("Request books") }; nil for a part that couldn't be asked.
function BookOrbit:keyAbilities()
    if not self:hasApiKey() then return {} end
    local out = {}
    local code = self:keyCall("GET", "/api/v1/koreader/credentials", { timeouts = { 8, 15 } })
    if code == 200 then out.signin = true elseif code == 403 then out.signin = false end
    code = self:keyCall("GET", "/api/v1/book-requests?page=1&limit=1", { timeouts = { 8, 15 } })
    if code == 200 then out.requests = true elseif code == 403 then out.requests = false end
    return out
end

--- A line for the user when a BookOrbit setting works against the Kindle, or nil.
function BookOrbit:settingsAdvice()
    local b = self.store.bookorbit
    if type(b) == "table" and b.delivery == "original" then return "delivery_original" end
    return nil
end

function BookOrbit:setApiKey(key)
    if not self:isPaired() then return false, "not_paired" end
    key = type(key) == "string" and key:gsub("%s+", "") or ""
    if key == "" then
        self.store.bookorbit.api_key = nil
        self.on_change()
        return true
    end
    local code = Api.rawRequest("GET", self.store.server .. "/api/v1/auth/me",
        { headers = { ["Authorization"] = "Bearer " .. key }, timeouts = { 10, 20 } })
    if code == 200 then
        self.store.bookorbit.api_key = key
        self:readSyncSettings()
        self.on_change()
        return true
    end
    return false, code == 401 and "bookorbit_api_key_refused" or (code and ("http_" .. code) or "unreachable")
end

--- One of the main API's book cards as an audiobook in the Catalog's lists, or nil.
local function audioCard(card)
    if type(card) ~= "table" or not n(card.id) then return nil end
    return {
        id = BookOrbit.AUDIO_PREFIX .. tostring(card.id), title = s(card.title) or ("Audiobook " .. tostring(card.id)),
        authors = names(card.authors), narrators = names(card.narrators), primaryFileType = "AUDIOBOOK",
        seriesName = s(card.seriesName), seriesNumber = n(card.seriesIndex), readProgress = n(card.readingProgress),
        hasCover = card.hasCover == true, categories = names(card.genres),
    }
end

--- One of the main API's book cards as a book in the Catalog's lists (its
--- files' formats say what GZreader opens), or nil.
local function bookCard(card)
    if type(card) ~= "table" or not n(card.id) then return nil end
    local formats = {}
    for _i, f in ipairs(list(card.files)) do
        if type(f) == "table" and s(f.format) then formats[#formats + 1] = f.format end
    end
    local book = BookOrbit.toBook({ id = card.id, title = card.title, authors = card.authors, seriesName = card.seriesName,
        seriesIndex = card.seriesIndex, formats = formats, progressPercentage = card.readingProgress, addedAt = card.addedAt,
        hasCover = card.hasCover })
    if book then book.categories = names(card.genres) end
    return book
end

-- The main API's filter: these formats (and, given, this genre).
local function formatFilter(formats, genre)
    local Json = require("gzreader_json")
    local any = {}
    for _i, f in ipairs(formats) do any[#any + 1] = f; any[#any + 1] = f:upper() end
    local rules = { { type = "rule", field = "format", operator = "includesAny", value = Json.list(any) } }
    if genre then rules[2] = { type = "rule", field = "genre", operator = "includesAny", value = Json.list({ genre }) } end
    return { type = "group", join = "AND", rules = Json.list(rules) }
end

local function query(self, body)
    local code, data, err = self:keyCall("POST", "/api/v1/books/query", { body = body, timeouts = { 15, 45 } })
    if not ((code == 200 or code == 201) and type(data) == "table") then return nil, err or ("http_" .. tostring(code)) end
    return data
end

--- A page of books in a genre (the main API, with the API key: BookOrbit's
--- e-reader catalog has no genres). Without a key: none.
function BookOrbit:listGenreBooks(params)
    local page, size = tonumber(params.page) or 0, math.min(tonumber(params.size) or 20, BookOrbit.PAGE_MAX)
    if not self:hasApiKey() then return emptyPage(page, size) end
    local Json = require("gzreader_json")
    local field = ({ title = "title", addedOn = "addedAt", lastReadTime = "lastReadAt" })[params.sort] or "title"
    local data, err = query(self, {
        sort = Json.list({ { field = field, dir = (params.dir == "desc") and "desc" or "asc" } }),
        pagination = { page = page, size = size }, -- (from 0)
        filter = formatFilter(BookOrbit.READABLE, s(params.category)),
        q = s(params.search),
    })
    if not data then return nil, err end
    local content = {}
    for _i, card in ipairs(list(data.items)) do
        local book = bookCard(card)
        if book and book.primaryFileType and book.primaryFileType ~= "AUDIOBOOK" then content[#content + 1] = book end
    end
    local total = n(data.total) or #content
    return { content = content, page = page, size = size, totalElements = total, totalPages = math.ceil(total / size),
        hasNext = (page + 1) * size < total, hasPrevious = page > 0 }
end

--- Every genre of the books KOReader opens, with how many books: { [name] = count }
--- (the library index's Genres). nil without the API key.
function BookOrbit:genreCounts()
    if not self:hasApiKey() then return nil end
    local counts, page, pages = {}, 0, 1
    while page < pages and page < 200 do
        local data = self:listGenreBooks({ page = page, size = BookOrbit.PAGE_MAX })
        if not data then return nil end
        pages = tonumber(data.totalPages) or 1
        for _i, b in ipairs(data.content) do
            for _j, g in ipairs(b.categories or {}) do counts[g] = (counts[g] or 0) + 1 end
        end
        page = page + 1
    end
    return counts
end

--- A page of audiobooks (the main API's book query), as the Catalog reads one.
function BookOrbit:listAudiobooks(params)
    local page, size = tonumber(params.page) or 0, math.min(tonumber(params.size) or 20, BookOrbit.PAGE_MAX)
    if not self:hasApiKey() then return emptyPage(page, size) end
    local Json = require("gzreader_json")
    local field = ({ title = "title", addedOn = "addedAt", lastReadTime = "lastReadAt" })[params.sort] or "title"
    local body = {
        sort = Json.list({ { field = field, dir = (params.dir == "desc") and "desc" or "asc" } }),
        pagination = { page = page, size = size }, -- (BookOrbit counts pages from 0, as GZreader does)
        filter = formatFilter(AUDIO_FORMATS, s(params.category)), -- (a genre: Genres on the Audiobooks page)
        q = s(params.search),
    }
    local data, err = query(self, body)
    if not data then return nil, err end
    local content = {}
    for _i, card in ipairs(list(data.items)) do content[#content + 1] = audioCard(card) end
    local total = n(data.total) or #content
    return { content = content, page = page, size = size, totalElements = total, totalPages = math.ceil(total / size),
        hasNext = (page + 1) * size < total, hasPrevious = page > 0 }
end

local function manifest(self, book_id)
    local code, data, err = self:keyCall("GET", "/api/v1/audiobooks/" .. tostring(audioId(book_id)) .. "/manifest", { timeouts = { 10, 30 } })
    if code == 200 and type(data) == "table" and type(data.assets) == "table" and #data.assets > 0 then
        table.sort(data.assets, function(a, b) return (n(a.sequence) or 0) < (n(b.sequence) or 0) end)
        return data
    end
    return nil, err or ("http_" .. tostring(code)), code
end

--- An audiobook's files and chapters, as Grimmory's audiobook info (what
--- gzreader_audiobook.lua's describe reads): one file with chapters, or one per track.
function BookOrbit:audiobookInfo(book_id)
    local m, err = manifest(self, book_id)
    if not m then return nil, err end
    local book = type(m.book) == "table" and m.book or {}
    local first = m.assets[1]
    local info = {
        title = s(book.title), author = table.concat(names(book.authors), ", "), narrator = table.concat(names(book.narrators), ", "),
        bookFileId = n(first.fileId), durationMs = n(m.totalDurationMs) or 0, folderBased = #m.assets > 1,
        codec = (s(first.format) or ""):lower() == "mp3" and "mp3" or "aac", totalSizeBytes = 0, tracks = {}, chapters = {},
        gz_manifest = s(m.revision),
    }
    if info.author == "" then info.author = nil end
    if info.narrator == "" then info.narrator = nil end
    local at = 0
    for i, a in ipairs(m.assets) do
        info.totalSizeBytes = info.totalSizeBytes + (n(a.sizeBytes) or 0)
        info.tracks[i] = { index = n(a.sequence) or (i - 1), fileName = string.format("%03d.%s", i, (s(a.format) or "mp3"):lower()),
            title = nil, durationMs = n(a.durationMs) or 0, fileSizeBytes = n(a.sizeBytes), cumulativeStartMs = at }
        at = at + (n(a.durationMs) or 0)
    end
    for i, c in ipairs(list(m.chapters)) do
        if type(c) == "table" then
            local start, stop = n(c.startMs) or 0, n(c.endMs)
            info.chapters[#info.chapters + 1] = { index = i - 1, title = s(c.title) or ("Chapter " .. i), startTimeMs = start,
                endTimeMs = stop, durationMs = stop and (stop - start) or nil }
            -- (one file per track: a track is named after the chapter that starts it)
            for _j, t in ipairs(info.tracks) do
                if t.title == nil and t.cumulativeStartMs == start then t.title = s(c.title) end
            end
        end
    end
    if not info.folderBased then info.tracks = nil end
    return info
end

--- One audio file of an audiobook to `path`, continuing what's there (BookOrbit's
--- audio files take a Range). track: its sequence (nil: the only file).
--- Returns true | false, err, retryable.
function BookOrbit:downloadAudio(book_id, track, path)
    local m, err, mcode = manifest(self, book_id)
    if not m then return false, err, mcode == nil end
    local asset = m.assets[1]
    for _i, a in ipairs(m.assets) do if track ~= nil and n(a.sequence) == tonumber(track) then asset = a end end
    local have = lfs.attributes(path, "size") or 0
    local fh, ferr = io.open(path, have > 0 and "ab" or "wb")
    if not fh then return false, ferr end
    local headers = { ["Authorization"] = "Bearer " .. self.store.bookorbit.api_key, ["Accept"] = "*/*" }
    if have > 0 then headers["Range"] = "bytes=" .. have .. "-" end
    local code = Api.rawRequest("GET", self.store.server .. "/api/v1/audiobooks/" .. tostring(audioId(book_id)) .. "/assets/"
        .. tostring(asset.assetId) .. "/content", { headers = headers, sink = ltn12.sink.file(fh), timeouts = { 60, -1 } })
    if code == 206 or (code == 200 and have == 0) or code == 416 then return true end
    if code == 200 and have > 0 then
        os.remove(path) -- (the whole file came after the part: start it again)
        return false, "restart", true
    end
    if code == 401 or code == 403 or code == 404 then return false, "http_" .. code, false end
    return false, code and ("http_" .. code) or "unreachable", true
end

local function uuid4()
    local md5 = require("ffi/sha2").md5
    local h = md5(tostring(os.time()) .. tostring(math.random()) .. tostring({}) .. tostring(os.clock()))
    local variant = ({ "8", "9", "a", "b" })[(tonumber(h:sub(17, 17), 16) % 4) + 1]
    return h:sub(1, 8) .. "-" .. h:sub(9, 12) .. "-4" .. h:sub(14, 16) .. "-" .. variant .. h:sub(18, 20) .. "-" .. h:sub(21, 32)
end
BookOrbit.uuid4 = uuid4

local function playbackState(self, book_id)
    local code, data, err = self:keyCall("GET", "/api/v1/audiobooks/" .. tostring(audioId(book_id)) .. "/playback-state", { timeouts = { 8, 15 } })
    if code == 200 then return type(data) == "table" and n(data.positionMs) and data or false end -- (false: none stored)
    return nil, err or ("http_" .. tostring(code)), code
end

--- Audiobooks in progress, most recently listened to first (Home's recently read
--- from the server). BookOrbit's "Continue listening" shelf gives the order but no
--- times, so each one's saved position is asked for when it was last captured: a
--- few books only (`limit`). Without an API key: none.
function BookOrbit:continueListening(limit)
    if not self:hasApiKey() then return {} end
    limit = math.max(1, math.min(tonumber(limit) or 6, 12))
    local code, data, err = self:keyCall("GET", "/api/v1/dashboard/scrollers/continue-listening?limit=" .. limit, { timeouts = { 10, 30 } })
    if not (code == 200 and type(data) == "table") then return nil, err or ("http_" .. tostring(code)) end
    local out = {}
    for _i, card in ipairs(list(data.books)) do
        local book = audioCard(card)
        if book and #out < limit then
            local state = playbackState(self, book.id)
            if state then
                book.lastReadTime = s(state.capturedAt)
                book.readProgress = n(state.percentage) or book.readProgress
            end
            out[#out + 1] = book
        end
    end
    return out
end

--- Where an audiobook was left, as Grimmory's record gives it (audiobookProgress:
--- positionMs within the track, trackIndex), for gzreader_audiobook.lua's pull.
function BookOrbit:audiobookRecord(book_id)
    local state, err = playbackState(self, book_id)
    if state == nil then return nil, err end
    local book = { id = book_id, metadata = {} }
    if state then
        local m = manifest(self, book_id)
        local index = 0
        for _i, a in ipairs(m and m.assets or {}) do if a.assetId == state.assetId then index = n(a.sequence) or 0 end end
        book.audiobookProgress = { positionMs = state.positionMs, trackIndex = index, percentage = n(state.percentage) }
    end
    return book
end

--- Save where an audiobook is (body as gzreader_audiobook.lua makes it for Grimmory:
--- positionData = ms in the track, positionHref = the track's index when it has
--- several files). BookOrbit wants the file, its place, and the revisions this is
--- based on; a place moved elsewhere meanwhile (409) is read again and sent once more.
function BookOrbit:putAudioProgress(book_id, body)
    local fp = type(body) == "table" and type(body.fileProgress) == "table" and body.fileProgress or {}
    local ms = tonumber(fp.positionData)
    if not ms then return false, "bookorbit_unmatched", 400 end
    local m, merr, mcode = manifest(self, book_id)
    if not m then return false, merr, mcode end
    local asset = m.assets[1]
    for _i, a in ipairs(m.assets) do if fp.positionHref ~= nil and n(a.sequence) == tonumber(fp.positionHref) then asset = a end end
    ms = math.max(0, math.min(math.floor(ms), n(asset.durationMs) or math.floor(ms)))
    local last_err, last_code
    for _try = 1, 2 do
        local state, serr, scode = playbackState(self, book_id)
        if state == nil then return false, serr, scode end
        local code, _, err = self:keyCall("PUT", "/api/v1/audiobooks/" .. tostring(audioId(book_id)) .. "/playback-state", {
            body = { assetId = asset.assetId, positionMs = ms, capturedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"), operationId = uuid4(),
                baseRevision = state and n(state.revision) or 0, manifestRevision = m.revision },
            timeouts = { 8, 15 } })
        if code == 200 then return true end
        last_err, last_code = err or ("http_" .. tostring(code)), code
        if code ~= 409 then break end -- (409: moved elsewhere since we read it: once more from its new revision)
    end
    -- (a read-only key, or the audiobook gone or changed: not something to keep retrying)
    if last_code == 403 or last_code == 404 or last_code == 400 or last_code == 412 then return false, last_err, 404 end
    return false, last_err, last_code
end

---------------------------------------------------------------- collections (GZreader's shelves), changed from here

-- Reading collections is the e-reader catalog's (listShelves, listBooks{ shelfId }). Putting a
-- book on one or taking it off is only on the main API, so it needs the API key too.

function BookOrbit:canEditShelves() return self:hasApiKey() end

--- Your own collections, as gzreader_shelves.lua reads Grimmory's shelves ({ id, name, bookCount, own }).
function BookOrbit:listMyShelves()
    local code, data, err = self:keyCall("GET", "/api/v1/collections", { timeouts = { 10, 20 } })
    if code ~= 200 or type(data) ~= "table" then return nil, err or ("http_" .. tostring(code)) end
    local mine
    if type(data[1]) == "table" and data[1].userId ~= nil then
        -- (others' shared collections are listed too: only your own can be changed)
        local mcode, me = self:keyCall("GET", "/api/v1/auth/me", { timeouts = { 8, 15 } })
        mine = mcode == 200 and type(me) == "table" and n(me.id) or nil
    end
    local out = {}
    for _i, c in ipairs(data) do
        if type(c) == "table" and n(c.id) and (mine == nil or n(c.userId) == nil or c.userId == mine) then
            out[#out + 1] = { id = c.id, name = s(c.name) or ("#" .. tostring(c.id)), bookCount = n(c.bookCount), own = true }
        end
    end
    return out
end

--- Put a book on collections `add` and take it off `remove` (lists of ids). Returns {}
--- (nothing more is known of the book), or nil, err, code.
function BookOrbit:setBookShelves(book_id, add, remove)
    local Json = require("gzreader_json")
    local id = tonumber(book_id)
    if not id then return nil, "bookorbit_unmatched", 400 end
    for _i, step in ipairs({ { "POST", add }, { "DELETE", remove } }) do
        for _j, cid in ipairs(type(step[2]) == "table" and step[2] or {}) do
            local code, _, err = self:keyCall(step[1], "/api/v1/collections/" .. tostring(cid) .. "/books",
                { body = { bookIds = Json.list({ id }) }, timeouts = { 10, 20 } })
            if not (code == 200 or code == 201 or code == 204) then return nil, err or ("http_" .. tostring(code)), code end
        end
    end
    return {}
end

---------------------------------------------------------------- book requests (API key)

-- Asking BookOrbit for a book it doesn't have (its Requests page). On the main API, so
-- with the API key, which needs the "Request books" permission (gzreader_bo_requests.lua).

function BookOrbit:canRequestBooks() return self:hasApiKey() end

local function requestRecord(r)
    if type(r) ~= "table" or not n(r.id) then return nil end
    local authors = {}
    for _i, a in ipairs(type(r.authors) == "table" and r.authors or {}) do
        if s(a) then authors[#authors + 1] = a end
    end
    return { id = r.id, title = s(r.title), authors = authors, kind = r.mediaKind == "audiobook" and "audiobook" or "ebook",
        status = s(r.status), reason = s(r.statusReason), note = s(r.decisionNote), book_id = n(r.matchedBookId) }
end

local function requestError(code, err)
    if err then return err end
    if code == 403 then return "bookorbit_requests_refused" end
    return "http_" .. tostring(code)
end

--- Ask for a book. `kind`: "ebook" or "audiobook"; `authors`: a list or nil. Returns the
--- request ({ id, title, status, …, joined = someone had asked already }), or nil, err, code.
function BookOrbit:requestBook(title, authors, kind)
    local Json = require("gzreader_json")
    local body = { title = title, mediaKind = kind == "audiobook" and "audiobook" or "ebook" }
    if type(authors) == "table" and #authors > 0 then body.authors = Json.list(authors) end
    local code, data, err = self:keyCall("POST", "/api/v1/book-requests", { body = body, timeouts = { 10, 30 } })
    if not (code == 200 or code == 201) or type(data) ~= "table" then return nil, requestError(code, err), code end
    local r = requestRecord(data.request) or { title = title, kind = body.mediaKind }
    r.joined = data.subscribed == true or nil
    return r
end

--- What you asked for, newest first (up to 100), or nil, err.
function BookOrbit:listRequests()
    local code, data, err = self:keyCall("GET", "/api/v1/book-requests?page=1&limit=100", { timeouts = { 10, 30 } })
    if code ~= 200 or type(data) ~= "table" then return nil, requestError(code, err), code end
    local out = {}
    for _i, r in ipairs(type(data.items) == "table" and data.items or {}) do
        out[#out + 1] = requestRecord(r)
    end
    return out
end

--- Cancel one of your requests. Returns true, or false, err, code.
function BookOrbit:cancelRequest(id)
    if not tonumber(id) then return false, "http_400", 400 end
    local code, _, err = self:keyCall("POST", "/api/v1/book-requests/" .. tostring(id) .. "/cancel", { body = {}, timeouts = { 10, 30 } })
    if code == 200 or code == 201 or code == 204 then return true end
    return false, requestError(code, err), code
end

---------------------------------------------------------------- not yet

-- Grimmory-only (its single sign-on, its web list) or not sent to BookOrbit yet: each
-- answers nil, "unsupported". Main and the sync modules don't call them while
-- `books_only` is set; this is so a call that slips through fails quietly.
for _i, name in ipairs{ "listWebBooks", "listAuthors", "listSeries",
    "listBookmarks", "createBookmark", "deleteBookmark", "listAnnotations",
    "createAnnotation", "updateAnnotation", "deleteAnnotation", "listBookNotes", "createBookNote", "updateBookNote",
    "deleteBookNote", "postSession", "hasSession", "publicSettings", "oidcExchange" } do
    BookOrbit[name] = function() return nil, "unsupported" end
end

return BookOrbit
