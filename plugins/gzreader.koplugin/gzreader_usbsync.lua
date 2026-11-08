--[[--
Syncing through a computer, for Kindles without Wi-Fi (Kindle 2, Kindle DX,
Kindle DX Graphite; any Kindle with Settings → Connections → Sync through a
computer).

The Kindle and a web page (https://9retirement6irk.github.io/GZreader/sync/,
Chrome or Edge on a computer the Kindle is plugged into) pass files in the
GZreader folder's hidden .gzsync folder:

- outbox.json (the Kindle writes it whenever its settings are saved):
  what to send to Grimmory (reading positions, reading time, ratings, as
  ready-made requests: jobs), the sync queue (books and audiobooks to bring),
  what's on the Kindle, the notes changed here (Memos), which calendar range.
  Never a password or token: the page keeps its own sign-ins.
- library.json and covers/ (the page): a copy of the Grimmory library, so the
  Grimmory tab can be browsed without a network (gzreader_offlineapi.lua);
  details/<id>.json: a book's page.
- in/… and inbox.json (the page, inbox.json last): books, audiobooks and
  music it brought, the notes, the calendars, and which jobs went through.
  The next time GZreader starts it takes them in (import) and deletes the
  inbox.

The Kindle's USB drive is only there while GZreader isn't running (KOReader
stops the Kindle's USB service while it runs): exit GZreader first.

Format 1:
  outbox = { format, written_at, gzreader, kindle = { model, name, id, audio },
    grimmory = { server, user },
    jobs = { { id, kind = "progress"|"session"|"rating", book, method, path, body } },
    queue = { { id, kind = "book"|"audiobook", title, authors, format, file_id, name, size_kb } },
    have = { books = { [id] = { file_id, format } }, audiobooks = { ids }, music = { "kind-key" } },
    notes = { queue = { Memos changes: id, op, content, visibility, name, pinned } },
    calendar = { from, to }, auto_shelf = { id, magic }, last_import,
    usage = { level, server, app } (absent when off),
    screensavers = { names, mode = "auto"|"always"|"other" }; kindle.screen = { w, h } }
- usage/*.jsonl (the Kindle, when it steps aside for the USB drive): usage
  statistics waiting to be sent (gzreader_usage.lua); the page sends them
  to usage.server and deletes each file it sent.
  inbox = { format, written_at, done = { job ids }, failed = { { id, error } },
    books = { { id, file, name, title, authors, format, file_id, subtitle, progress } },
    audiobooks = { { id, dir, info, primaryFileName, title, progress } },
    music = { { kind, key, dir } },
    notes = { file, done = { queue ids }, server, user },
    calendars = { { name, file } },
    grimmory = { server, user },
    screensavers = { add = { { file, name } }, remove = { names }, mode },
    grimmory_stats = { at, values = { streak, longest_streak, reading_days,
      week_time, week_books, month_sessions, year_finished } } or { at, error } }
]]

local DataStorage = require("datastorage")
local Device = require("device")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local Usb = {
    FORMAT = 1,
    MODELS = { Kindle2 = true, KindleDX = true, KindleDXG = true }, -- no Wi-Fi
    PAGE_URL = "https://9retirement6irk.github.io/GZreader/sync/",
    FOLDER = ".gzsync",
}

---------------------------------------------------------------- which Kindles

--- This model has no Wi-Fi.
function Usb.noWifi(model)
    return Usb.MODELS[tostring(model or Device.model)] == true
end

--- Sync through a computer: Kindles without Wi-Fi, or chosen in Settings.
function Usb.active()
    local s = G_reader_settings and G_reader_settings:readSetting("gzreader_usb_sync")
    if s == true or s == false then return s end
    return Usb.noWifi()
end

function Usb.setActive(on)
    if on == Usb.noWifi() then G_reader_settings:delSetting("gzreader_usb_sync")
    else G_reader_settings:saveSetting("gzreader_usb_sync", on) end
end

function Usb.dir(plugin)
    local dir = plugin:libraryDir() .. "/" .. Usb.FOLDER
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    return dir
end

---------------------------------------------------------------- files

local function readJson(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and data or nil
end
Usb.readJson = readJson

local function writeFile(path, text)
    local f = io.open(path .. ".tmp", "wb")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(path) -- (FAT: rename doesn't replace)
    return os.rename(path .. ".tmp", path)
end
Usb.writeFile = writeFile

local function isFile(p) return lfs.attributes(p, "mode") == "file" end
local function isDir(p) return lfs.attributes(p, "mode") == "directory" end

local function rmrf(path)
    if isDir(path) then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then rmrf(path .. "/" .. name) end
        end
        lfs.rmdir(path)
    elseif lfs.attributes(path, "mode") then
        os.remove(path)
    end
end
Usb.rmrf = rmrf

local function copyFile(src, dst)
    local i = io.open(src, "rb")
    if not i then return false end
    local o = io.open(dst, "wb")
    if not o then i:close(); return false end
    while true do
        local chunk = i:read(256 * 1024)
        if not chunk then break end
        o:write(chunk)
    end
    i:close(); o:close()
    return true
end

--- Move a file or folder (renamed when it can be, copied otherwise).
local function move(src, dst)
    if os.rename(src, dst) then return true end
    if isFile(src) then
        if copyFile(src, dst) then os.remove(src); return true end
        return false
    end
    if isDir(src) then
        lfs.mkdir(dst)
        for name in lfs.dir(src) do
            if name ~= "." and name ~= ".." then
                if not move(src .. "/" .. name, dst .. "/" .. name) then return false end
            end
        end
        lfs.rmdir(src)
        return true
    end
    return false
end
Usb.move = move

---------------------------------------------------------------- the sync queue

local function queue(plugin)
    plugin.store.usb_queue = plugin.store.usb_queue or {}
    return plugin.store.usb_queue
end
Usb.queue = queue

function Usb.isQueued(plugin, book_id)
    if not plugin then return false end
    for _i, q in ipairs(plugin.store.usb_queue or {}) do
        if tostring(q.id) == tostring(book_id) then return true end
    end
    return false
end

--- Add a book or audiobook (a Grimmory summary) to the sync queue.
function Usb.enqueue(plugin, book, kind)
    if Usb.isQueued(plugin, book.id) then return false end
    local ftype = type(book.primaryFileType) == "string" and book.primaryFileType:upper() or ""
    kind = kind or (ftype == "AUDIOBOOK" and "audiobook" or "book")
    local list = queue(plugin)
    list[#list + 1] = {
        id = tonumber(book.id) or book.id, kind = kind, title = book.title,
        authors = type(book.authors) == "table" and book.authors or nil,
        format = book.primaryFileType, file_id = tonumber(book.primaryFileId),
        name = type(book.primaryFileName) == "string" and book.primaryFileName:match("[^/\\]+$") or nil,
        size_kb = tonumber(book.fileSizeKb), at = os.time(),
    }
    Log.info("sync queue: added", kind, book.id)
    plugin:save()
    return true
end

function Usb.dequeue(plugin, book_id)
    local list, out, gone = queue(plugin), {}, false
    for _i, q in ipairs(list) do
        if tostring(q.id) == tostring(book_id) then gone = true else out[#out + 1] = q end
    end
    plugin.store.usb_queue = out
    if gone then plugin:save() end
    return gone
end

function Usb.queueSizeKb(plugin)
    local kb = 0
    for _i, q in ipairs(queue(plugin)) do kb = kb + (tonumber(q.size_kb) or 0) end
    return kb
end

---------------------------------------------------------------- the outbox

-- A list, as a list in JSON even when it's empty ([] and not {}: the page
-- reads the outbox; KOReader's JSON (luajson) and dkjson each have their mark).
local ARRAY = { __is_luajson_array = true, __jsontype = "array" }
local function jsonList(t)
    local out = {}
    for i, v in ipairs(type(t) == "table" and t or {}) do out[i] = v end
    return setmetatable(out, ARRAY)
end
Usb.list = jsonList

local function clean(body)
    local out = {}
    for k, v in pairs(body or {}) do if not tostring(k):match("^gz_") then out[k] = v end end
    return out
end

--- A job's id: what the page reports back as done.
function Usb.jobId(kind, book_id, body)
    if kind == "progress" then return "p:" .. tostring(book_id) .. ":" .. tostring(body.gz_seq or 0) end
    if kind == "session" then return "s:" .. tostring(body.bookId) .. ":" .. tostring(body.startTime) end
    return "r:" .. tostring(book_id) .. ":" .. tostring(body)
end

--- Every queued position (each numbered once: its id changes when a newer one replaces it).
local function number(plugin)
    local store = plugin.store
    local changed = false
    for _id, body in pairs(store.pending.progress or {}) do
        if type(body) == "table" and not body.gz_seq then
            store.usb_seq = (store.usb_seq or 0) + 1
            body.gz_seq = store.usb_seq
            changed = true
        end
    end
    return changed
end
Usb.number = number

function Usb.jobs(plugin)
    number(plugin)
    local pending = plugin.store.pending
    local jobs = {}
    local ids = {}
    for id in pairs(pending.progress or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _i, id in ipairs(ids) do
        local body = pending.progress[id]
        jobs[#jobs + 1] = { id = Usb.jobId("progress", id, body), kind = "progress", book = tonumber(id) or id,
            method = "PUT", path = "/api/v1/app/books/" .. id .. "/progress", body = clean(body) }
    end
    for _i, body in ipairs(pending.sessions or {}) do
        jobs[#jobs + 1] = { id = Usb.jobId("session", nil, body), kind = "session", book = body.bookId,
            method = "POST", path = "/api/v1/reading-sessions", body = clean(body) }
    end
    local Ratings = require("gzreader_ratings")
    for id, stars in pairs(pending.ratings or {}) do
        local value = Ratings.toGrimmory(stars)
        jobs[#jobs + 1] = value
            and { id = Usb.jobId("rating", id, stars), kind = "rating", book = tonumber(id) or id,
                method = "PUT", path = "/api/v1/books/personal-rating", body = { ids = { tonumber(id) }, rating = math.floor(value) } }
            or { id = Usb.jobId("rating", id, stars), kind = "rating", book = tonumber(id) or id,
                method = "POST", path = "/api/v1/books/reset-personal-rating", body = { tonumber(id) } }
    end
    -- bookmarks and highlights, in the order they were made (the journal:
    -- gzreader_offlineapi.lua); "{id}" in a path and temp/ref ids are for
    -- the page to fill in
    for _i, j in ipairs(Usb.journal(plugin)) do
        jobs[#jobs + 1] = { id = j.id, kind = "mark", op = j.op, book = j.book, method = j.method, path = j.path,
            body = j.body, temp = j.temp, ref = j.ref }
    end
    return jobs
end

function Usb.journalPath(plugin) return Usb.dir(plugin) .. "/journal.jsonl" end

function Usb.journal(plugin)
    local out = {}
    local f = io.open(Usb.journalPath(plugin), "rb")
    if not f then return out end
    for line in f:lines() do
        local ok, j = pcall(JSON.decode, line)
        if ok and type(j) == "table" and j.id then out[#out + 1] = j end
    end
    f:close()
    return out
end

--- The journal without what the page sent; Grimmory's ids for what was
--- made here (inbox.created = { temp = id }) everywhere GZreader keeps one.
function Usb.applyMarks(plugin, done, created)
    local left, sent = {}, 0
    for _i, j in ipairs(Usb.journal(plugin)) do
        if done[tostring(j.id)] then sent = sent + 1 else left[#left + 1] = j end
    end
    local map = {}
    for temp, id in pairs(type(created) == "table" and created or {}) do map[tostring(temp)] = id end
    if next(map) then
        local idmap = plugin.store.usb_idmap or {}
        for temp, id in pairs(map) do idmap[temp] = id end
        plugin.store.usb_idmap = idmap
        -- (ids still to be sent that refer to these: Grimmory's now)
        for _i, j in ipairs(left) do
            if j.ref and map[tostring(j.ref)] then j.ref = tostring(map[tostring(j.ref)]) end
        end
        for _id, e in pairs(plugin.store.downloads or {}) do
            if type(e) == "table" then
                for key, id in pairs(type(e.bookmarks) == "table" and e.bookmarks or {}) do
                    if map[tostring(id)] then e.bookmarks[key] = map[tostring(id)] end
                end
                if type(e.anno_shadow) == "table" then
                    for id, v in pairs(e.anno_shadow) do
                        if map[tostring(id)] then
                            e.anno_shadow[id] = nil
                            e.anno_shadow[tostring(map[tostring(id)])] = v
                        end
                    end
                end
            end
        end
    end
    if sent > 0 or next(map) then
        local lines = {}
        for _i, j in ipairs(left) do lines[#lines + 1] = JSON.encode(j) end
        if #lines > 0 then writeFile(Usb.journalPath(plugin), table.concat(lines, "\n") .. "\n")
        else os.remove(Usb.journalPath(plugin)) end
    end
    return sent
end

--- A highlight's Grimmory id as this Kindle had it (made here before a sync: a "usb-…" one).
function Usb.realId(plugin, id)
    local map = plugin and plugin.store.usb_idmap
    return map and id ~= nil and map[tostring(id)] or id
end

-- (the outbox is written at every save: what takes reading many files is
-- looked at again at most every two minutes, and after an import)
local slow = {}
local function cached(key, fn)
    local c = slow[key]
    if c and os.time() - c.at < 120 then return c.value end
    local value = fn()
    slow[key] = { at = os.time(), value = value }
    return value
end
function Usb.forgetCached() slow = {} end

function Usb.have(plugin)
    local books, audiobooks = {}, {}
    for id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" and e.path and isFile(e.path) then
            books[tostring(id)] = { file_id = e.file_id, format = e.format }
        end
    end
    for id in pairs(plugin.store.audiobooks or {}) do
        if isFile(plugin:libraryDir() .. "/" .. require("gzreader_abfolder").STORE .. "/" .. tostring(id) .. "/audiobook.json") then
            audiobooks[#audiobooks + 1] = tonumber(id) or id
        end
    end
    table.sort(audiobooks, function(a, b) return tostring(a) < tostring(b) end)
    local music = cached("music", function()
        local list = {}
        pcall(function()
            for _i, c in ipairs(require("gzreader_music").downloaded(plugin, { any = true })) do
                list[#list + 1] = tostring(c.kind) .. "-" .. tostring(c.key)
            end
        end)
        return list
    end)
    return { books = books, audiobooks = jsonList(audiobooks), music = jsonList(music) }
end

--- The screen, upright (for pictures made to fit it).
function Usb.screenSize()
    local ok, w, h = pcall(function() return Device.screen:getWidth(), Device.screen:getHeight() end)
    if not ok or not tonumber(w) or not tonumber(h) then return nil end
    if w > h then w, h = h, w end
    return { w = w, h = h }
end

function Usb.usageInfo()
    local ok, U = pcall(require, "gzreader_usage")
    if not ok or not U.on() then return nil end
    return { level = U.level(), server = U.SERVER, app = U.APP }
end

--- Usage statistics waiting on the Kindle: into .gzsync/usage/ for the page
--- (when GZreader steps aside for the USB drive).
function Usb.handOverUsage(plugin)
    local n = require("gzreader_usage").handOver(Usb.dir(plugin) .. "/usage")
    if n > 0 then Log.info("sync: usage statistics for the sync page:", n, "file(s)") end
    return n
end

--- Use a module for one answer and, if nothing else had loaded it, let it go
--- again (the outbox is written on every save on a Kindle without Wi-Fi: it
--- shouldn't keep big modules in memory to fill a field or two).
local function borrow(name, fn)
    local had = package.loaded[name] ~= nil
    local ok, v1, v2 = pcall(function() return fn(require(name)) end)
    if not had then package.loaded[name] = nil end
    if ok then return v1, v2 end
end

--- What the outbox needs from other modules, worked out once per run (none
--- of it changes while GZreader runs: the version, this Kindle's name).
Usb.fixed = nil
function Usb.fixedFields(plugin)
    if Usb.fixed and Usb.fixed.store == plugin.store then return Usb.fixed end
    local f = { store = plugin.store }
    f.version = borrow("gzreader_update", function(Update) return Update.currentVersion() end)
    f.name, f.id = borrow("gzreader_copy", function(Copy) return Copy.deviceName(plugin), Copy.deviceId(plugin) end)
    Usb.fixed = f
    return f
end

--- Read straight from the store, as gzreader_calendar.lua's prefs(),
--- gzreader_shelfsync.lua's shelf() and gzreader_plex.lua's quality() would
--- (the tests check they agree), without loading those modules.
function Usb.calendarDays(store)
    local p = store.calendar_prefs or {}
    return tonumber(p.days_back) or 14, tonumber(p.days_ahead) or 90
end
function Usb.musicQuality(store)
    local s = type(store.plex) == "table" and store.plex or {}
    return { bitrate = tonumber(s.bitrate) or 192, shrink = s.shrink == true }
end

function Usb.outbox(plugin)
    local store = plugin.store
    local fixed = Usb.fixedFields(plugin)
    local version = fixed.version
    local cal_from, cal_to = Usb.calendarDays(store)
    local s = store.auto_shelf
    local shelf = type(s) == "table" and { id = s.id, magic = s.magic == true, name = s.name } or nil
    local memos = store.memos or {}
    local notes_queue = {}
    for _i, q in ipairs(memos.queue or {}) do
        notes_queue[#notes_queue + 1] = { id = q.id, op = q.op, content = q.content, visibility = q.visibility,
            name = q.name, pinned = q.pinned, at = q.at }
    end
    -- the notes' pictures already here (not brought again)
    local note_files = cached("note_files", function()
        local list = {}
        pcall(function()
            local dir = require("gzreader_memos").filesDir()
            for f in lfs.dir(dir) do
                if f ~= "." and f ~= ".." and isFile(dir .. "/" .. f) then list[#list + 1] = f end
            end
            table.sort(list)
        end)
        return list
    end)
    local name, id = fixed.name, fixed.id
    return {
        format = Usb.FORMAT,
        gzreader = version,
        -- (Settings → Updates → Test builds: the page then brings those)
        test_builds = G_reader_settings:isTrue("gzreader_update_beta") or nil, -- (gzreader_update.betaEnabled)
        kindle = { model = tostring(Device.model), name = name, id = id, audio = require("gzreader_touch").audio() == true,
            screen = Usb.screenSize() },
        -- (Plex music's quality: the page converts at it, and shrinks bigger MP3/AAC if asked)
        music_quality = Usb.musicQuality(store),
        grimmory = store.server and { server = store.server, user = store.username } or nil,
        jobs = jsonList(Usb.jobs(plugin)),
        queue = jsonList(queue(plugin)),
        have = Usb.have(plugin),
        notes = { queue = jsonList(notes_queue), sync_tags = memos.sync_tags and jsonList(memos.sync_tags) or nil, keep = (store.notes_prefs or {}).keep,
            files_mb = (store.notes_prefs or {}).files_mb, files = jsonList(note_files) },
        calendar = { days_back = cal_from or 14, days_ahead = cal_to or 90 },
        auto_shelf = shelf,
        last_import = store.usb_last and store.usb_last.at or nil,
        -- the sleep screen's pictures (the page makes new ones for this screen)
        screensavers = { names = jsonList(cached("screensavers", Usb.screensavers)), mode = Usb.sleepMode() },
        -- usage statistics (gzreader_usage.lua): the page sends what's in usage/
        usage = Usb.usageInfo(),
        -- (how much room is left on the Kindle, for the page)
        disk = cached("disk", function()
            local ok, du = pcall(function() return require("util").diskUsage(plugin:libraryDir()) end)
            return ok and type(du) == "table" and du.total and { total = du.total, available = du.available } or nil
        end),
    }
end

--- Write outbox.json (skipped when nothing changed since the last time).
function Usb.writeOutbox(plugin)
    local ok, err = pcall(function()
        local out = Usb.outbox(plugin)
        local text = JSON.encode(out)
        if text == Usb.last_outbox and isFile(Usb.dir(plugin) .. "/outbox.json") then return end
        Usb.last_outbox = text
        out.written_at = os.time()
        writeFile(Usb.dir(plugin) .. "/outbox.json", JSON.encode(out))
    end)
    if not ok then Log.warn("sync: couldn't write the outbox:", tostring(err)) end
end

--- A queued position for an EPUB: its exact place (CFI) worked out in the
--- background, as when it's sent over Wi-Fi (gzreader_sync.lua).
function Usb.cfiSoon(plugin, book_id, body)
    local fp = type(body) == "table" and body.fileProgress
    if not (body.gz_xp and body.gz_file and type(fp) == "table" and not fp.positionData) then return end
    local Async = require("gzreader_async")
    local xp, file = body.gz_xp, body.gz_file
    Async.background(function() return require("gzreader_sync").cfiInFile(file, xp) end, function(cfi)
        if type(cfi) ~= "string" then return end
        if plugin.store.pending.progress[tostring(book_id)] == body then
            fp.positionData = cfi
            plugin:saveSoon()
        end
    end, "cfi for the outbox")
end

--- Before GZreader closes: the open book's place as a CFI now (it may be
--- the last chance before the Kindle is plugged in).
function Usb.finishCfis(plugin)
    local n = 0
    for _id, body in pairs(plugin.store.pending.progress or {}) do
        local fp = type(body) == "table" and body.fileProgress
        if body.gz_xp and body.gz_file and type(fp) == "table" and not fp.positionData and n < 3 then
            n = n + 1
            fp.positionData = require("gzreader_sync").cfiInFile(body.gz_file, body.gz_xp)
        end
    end
end

---------------------------------------------------------------- taking in what the page brought

local function set(list)
    local s = {}
    for _i, v in ipairs(type(list) == "table" and list or {}) do s[tostring(v)] = true end
    return s
end

--- Jobs the page sent: off the pending lists.
function Usb.applyDone(plugin, done)
    local pending = plugin.store.pending
    local n = 0
    for id, body in pairs(pending.progress or {}) do
        if done[Usb.jobId("progress", id, body)] then
            pending.progress[id] = nil
            n = n + 1
            local entry = plugin.store.downloads[id]
            local fp = body.fileProgress
            if entry and fp then entry.last_pushed_pct = fp.progressPercent; entry.last_pushed_cfi = fp.positionData end
        end
    end
    local left = {}
    for _i, body in ipairs(pending.sessions or {}) do
        if done[Usb.jobId("session", nil, body)] then n = n + 1 else left[#left + 1] = body end
    end
    pending.sessions = left
    for id, stars in pairs(pending.ratings or {}) do
        if done[Usb.jobId("rating", id, stars)] then
            pending.ratings[id] = nil
            n = n + 1
            local entry = plugin.store.downloads[id]
            if entry then entry.rating_synced = stars end
        end
    end
    return n
end

local function safeName(plugin, name, dir)
    local util = require("util")
    return util.getSafeFilename(name, dir)
end

--- A book the page brought: into the GZreader folder, as a download.
function Usb.takeBook(plugin, base, b)
    local src = base .. "/" .. tostring(b.file or "")
    if not b.id or not isFile(src) then return false end
    local dir = plugin:libraryDir()
    local id = tostring(b.id)
    local old = plugin.store.downloads[id]
    local name = type(b.name) == "string" and b.name:match("[^/\\]+$") or nil
    if not name or name == "" then
        local ext = (type(b.format) == "string" and b.format:lower() or "epub")
        if ext == "cbx" then ext = "cbz" end
        name = (b.title or ("book-" .. id)) .. "." .. ext
    end
    name = safeName(plugin, name, dir)
    local path = dir .. "/" .. name
    if type(old) == "table" and old.path and isFile(old.path) then
        path = old.path -- a newer file of a book already here: in its place
        os.remove(path)
    elseif isFile(path) then
        local stem, ext = name:match("^(.*)(%.[^.]+)$")
        local i = 2
        while isFile(path) do
            path = dir .. "/" .. (stem or name) .. " (" .. i .. ")" .. (ext or "")
            i = i + 1
        end
    end
    if not move(src, path) then return false end
    local authors = type(b.authors) == "table" and #b.authors > 0 and table.concat(b.authors, "\n") or nil
    local title = type(b.title) == "string" and b.title or name
    local entry = type(old) == "table" and old or {}
    entry.path, entry.title, entry.authors = path, title, authors or entry.authors
    entry.subtitle = type(b.subtitle) == "string" and b.subtitle ~= "" and b.subtitle or entry.subtitle
    entry.format = type(b.format) == "string" and b.format or entry.format
    entry.file_id = tonumber(b.file_id) or entry.file_id
    -- (Grimmory's progress: the book opens there the first time)
    entry.grimmory_progress = require("gzreader_sync").progressOf(b.progress) or entry.grimmory_progress
    plugin.store.downloads[id] = entry
    if entry.subtitle then
        pcall(require("gzreader_titles").apply, path, title, entry.subtitle, authors)
    end
    Usb.dequeue(plugin, b.id)
    Log.info("sync: book", id, "brought by the computer:", (path:match("[^/]+$")))
    -- (a picture book: fitted before it's first opened)
    pcall(function() require("gzreader_picturebook").prepare(path) end)
    return true
end

--- An audiobook the page brought: its folder in place; M4B audio is
--- prepared for the Kindle (in the background, one after another).
function Usb.takeAudiobook(plugin, base, a, prepare_list)
    local src = base .. "/" .. tostring(a.dir or "")
    if not a.id or type(a.info) ~= "table" or not isDir(src) then return false end
    local Audiobook = require("gzreader_audiobook")
    local id = tostring(a.id)
    local dest = Audiobook.dir(plugin, id)
    local parent = dest:match("^(.*)/[^/]+$")
    if parent and not isDir(parent) then lfs.mkdir(parent) end
    if isDir(dest) then
        local cur = Audiobook.current
        if cur and tostring(cur.book.id) == id then pcall(cur.stop, cur) end
        rmrf(dest)
    end
    if not move(src, dest) then return false end
    local book = Audiobook.describe(id, a.info, a.primaryFileName)
    book.title = book.title or a.title
    plugin.store.audiobooks = plugin.store.audiobooks or {}
    local e = plugin.store.audiobooks[id] or {}
    e.title, e.author = book.title, book.author
    e.grimmory_progress = require("gzreader_sync").progressOf(a.progress) or e.grimmory_progress
    plugin.store.audiobooks[id] = e
    prepare_list[#prepare_list + 1] = { dir = dest, book = book, id = id }
    Usb.dequeue(plugin, a.id)
    Log.info("sync: audiobook", id, "brought by the computer,", #book.tracks, "file(s)")
    return true
end

--- Prepare the audiobooks and music (M4B/M4A → AAC chunks), one by one.
function Usb.prepareAll(plugin, list, on_done)
    local Audiobook = require("gzreader_audiobook")
    local JSONenc = JSON.encode
    local i = 0
    local function nxt()
        i = i + 1
        local p = list[i]
        if not p then return on_done and on_done() end
        Audiobook.prepare(p.dir, p.tracks or p.book.tracks, p.book and p.book.title or p.title, function(ok, err)
            if p.book then
                if ok then
                    Audiobook.finishLayout(p.dir, p.book)
                    local f = io.open(p.dir .. "/audiobook.json", "wb")
                    if f then f:write(JSONenc(p.book)); f:close() end
                    local Folder = require("gzreader_abfolder")
                    pcall(Folder.writeStub, plugin, p.id)
                    pcall(Folder.fetchCover, plugin, p.id)
                else
                    Log.warn("sync: audiobook", p.id, "couldn't be prepared:", tostring(err))
                end
            elseif p.music then
                local Music = require("gzreader_music")
                local c = Music.load(p.dir)
                if c then
                    for _j, t in ipairs(c.tracks) do Music.trackReady(c, t) end
                    Music.save(c)
                end
                pcall(function() require("gzreader_musicfolder").sync(plugin) end)
            end
            plugin:save()
            nxt()
        end)
    end
    nxt()
end

--- Music (a Plex album or playlist) the page brought.
function Usb.takeMusic(plugin, base, m, prepare_list)
    local src = base .. "/" .. tostring(m.dir or "")
    if not (m.kind and m.key) or not isFile(src .. "/music.json") then return false end
    local Music = require("gzreader_music")
    local root = Music.root(plugin)
    if not isDir(root) then lfs.mkdir(root) end
    local dest = Music.dirFor(plugin, m.kind, m.key)
    if isDir(dest) then rmrf(dest) end
    if not move(src, dest) then return false end
    local c = Music.load(dest)
    if not c then return false end
    local todo = {}
    for _i, t in ipairs(c.tracks) do
        if t.file and t.file:match("%.m4a$") and not Music.trackReady(c, t) then
            todo[#todo + 1] = { file = t.file, size = lfs.attributes(dest .. "/" .. t.file, "size") }
        end
    end
    Music.save(c)
    prepare_list[#prepare_list + 1] = { dir = dest, tracks = todo, title = c.title, music = true }
    Log.info("sync: music", m.kind, m.key, "brought by the computer,", #c.tracks, "tracks")
    return true
end

--- The notes the page brought (Memos): the Notes tab's copy.
function Usb.takeNotes(plugin, base, n)
    local data = readJson(base .. "/" .. tostring(n.file or ""))
    if not data or type(data.notes) ~= "table" then return false end
    local Memos = require("gzreader_memos")
    local store = plugin.store
    store.memos = store.memos or {}
    local memos = store.memos
    memos.usb = true
    memos.server = memos.server or n.server
    memos.user = n.user or memos.user
    if type(data.tags) == "table" then memos.tag_counts = data.tags end
    local done = set(n.done)
    local left = {}
    for _i, q in ipairs(memos.queue or {}) do if not done[tostring(q.id)] then left[#left + 1] = q end end
    memos.queue = left
    Memos.saveCache({ notes = data.notes, at = tonumber(data.at) or os.time() })
    -- attachments (pictures…)
    local files = base .. "/" .. tostring(n.files or "in/notes-files")
    if isDir(files) then
        local dest = Memos.filesDir()
        for name in lfs.dir(files) do
            if name ~= "." and name ~= ".." and isFile(files .. "/" .. name) then
                os.remove(dest .. "/" .. name)
                move(files .. "/" .. name, dest .. "/" .. name)
            end
        end
    end
    local Notes = package.loaded["gzreader_notes"]
    if Notes then Notes.notes = nil end
    Log.info("sync: notes brought by the computer:", #data.notes)
    return #data.notes
end

--- The calendars the page brought (.ics texts): events for the Calendar tab.
function Usb.takeCalendars(plugin, base, cals)
    local CalDAV = require("gzreader_caldav")
    local Calendar = require("gzreader_calendar")
    local prefs = Calendar.prefs(plugin)
    local today = os.time()
    local t = os.date("*t", today)
    t.hour, t.min, t.sec = 0, 0, 0
    local day = os.time(t)
    local from, to = day - prefs.days_back * 86400, day + (prefs.days_ahead + 1) * 86400
    local feeds, events = {}, {}
    local n = #((plugin.store.caldav or {}).calendars or {})
    if not (plugin.store.caldav and plugin.store.caldav.server) then n = 0 end
    for i, c in ipairs(type(cals) == "table" and cals or {}) do
        local f = io.open(base .. "/" .. tostring(c.file or ""), "rb")
        local text = f and f:read("*a")
        if f then f:close() end
        local old
        for _j, o in ipairs(plugin.store.calendar_feeds or {}) do if o.usb and o.name == c.name then old = o end end
        feeds[#feeds + 1] = { name = c.name, usb = true, enabled = not (old and old.enabled == false) }
        if text and text:find("BEGIN:VCALENDAR", 1, true) and feeds[#feeds].enabled then
            local ok, occ = pcall(function() return CalDAV.occurrences(CalDAV.parseEvents(text), from, to) end)
            if ok then
                for _j, ev in ipairs(occ) do ev.cal = n + i; events[#events + 1] = ev end
            else
                Log.warn("sync: calendar", i, "couldn't be read:", tostring(occ))
            end
        end
    end
    table.sort(events, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        if (a.all_day and 1 or 0) ~= (b.all_day and 1 or 0) then return a.all_day == true end
        return (a.title or "") < (b.title or "")
    end)
    plugin.store.calendar_feeds = feeds
    CalDAV.saveCache({ at = os.time(), from = from, to = to, events = events })
    Calendar.events = nil
    Log.info("sync: calendars brought by the computer:", #feeds, "with", #events, "events")
    return #events
end

--- Take in what the page left (inbox.json). Returns a summary, or nil
--- when there's nothing. on_prepared: once audiobooks/music are ready.
--- The Kindle's clock, from the computer's: a Kindle without Wi-Fi never
--- sets its own, and a Kindle DX whose battery ran down starts at 1970
--- (reading times then went out with 1970 dates). The page wrote the inbox
--- (written_at, the computer's clock) before GZreader read it, so a clock
--- behind that is wrong: set to it plus a minute (unplugging and starting).
--- Returns true when the clock was set.
Usb.setClock = function(t)
    if not Device:isKindle() then return false end
    os.execute(string.format("date -u %s >/dev/null 2>&1 && (hwclock -u -w >/dev/null 2>&1 || true)", os.date("!%m%d%H%M%Y.%S", t)))
    return true
end
function Usb.fixClock(written_at)
    local t = tonumber(written_at)
    if not t or t < 1700000000 then return false end
    local now = os.time()
    if now >= t - 60 then return false end
    Log.info("sync: the Kindle's clock said", os.date("!%Y-%m-%d %H:%M", now), "UTC: set from the computer's",
        os.date("!%Y-%m-%d %H:%M", t + 60))
    return Usb.setClock(t + 60) == true
end

---------------------------------------------------------------- sleep screen pictures

--- Where the sleep screen's pictures are: the drive's "screensavers" folder
--- on a Kindle (frontend/ui/screensaver.lua looks there), elsewhere the
--- folder chosen in the sleep screen settings or GZreader's own.
function Usb.screensaverDir()
    if Usb.SCREENSAVER_DIR then return Usb.SCREENSAVER_DIR end -- (tests)
    if Device:isKindle() then return "/mnt/us/screensavers" end
    local dir = G_reader_settings:readSetting("screensaver_dir")
    if type(dir) == "string" and dir ~= "" then return dir end
    return DataStorage:getDataDir() .. "/screensavers"
end

local PICTURE = { png = true, jpg = true, jpeg = true, gif = true, bmp = true, svg = true }
local function isPicture(name)
    local ext = type(name) == "string" and name:match("%.(%w+)$")
    return ext ~= nil and PICTURE[ext:lower()] == true
end

--- The pictures there (names), for the page.
function Usb.screensavers()
    local list = {}
    pcall(function()
        local dir = Usb.screensaverDir()
        if not isDir(dir) then return end
        for f in lfs.dir(dir) do
            if f:sub(1, 1) ~= "." and isPicture(f) and isFile(dir .. "/" .. f) then list[#list + 1] = f end
        end
        table.sort(list)
    end)
    return list
end

--- inbox.screensavers = { add = { { file, name } }, remove = { names }, mode = "auto"|"always" }:
--- pictures the page made for this screen into the folder, the ones taken
--- off removed, and when they show (auto: the book's cover while reading,
--- a picture elsewhere; always: a picture). Returns how many came.
function Usb.takeScreensavers(base, st)
    local dir = Usb.screensaverDir()
    if not isDir(dir) then lfs.mkdir(dir) end
    local added = 0
    for _i, p in ipairs(type(st.add) == "table" and st.add or {}) do
        local src = type(p) == "table" and type(p.file) == "string" and base .. "/" .. p.file
        local name = type(p) == "table" and type(p.name) == "string" and p.name:match("[^/\\]+$")
        if src and name and isPicture(name) and not name:find("^%.") and isFile(src) then
            local dest = dir .. "/" .. name
            local stem, ext = name:match("^(.*)(%.[^.]+)$")
            local k = 2
            while isFile(dest) do
                dest = dir .. "/" .. (stem or name) .. " (" .. k .. ")" .. (ext or "")
                k = k + 1
            end
            if move(src, dest) then added = added + 1 end
        end
    end
    for _i, name in ipairs(type(st.remove) == "table" and st.remove or {}) do
        -- (only a picture's name in that folder)
        if type(name) == "string" and not name:find("[/\\]") and not name:find("^%.") and isPicture(name) then
            os.remove(dir .. "/" .. name)
        end
    end
    if st.mode == "auto" then
        G_reader_settings:saveSetting("gzreader_sleep_auto", true)
    elseif st.mode == "always" then
        G_reader_settings:saveSetting("gzreader_sleep_auto", false)
        G_reader_settings:saveSetting("screensaver_type", "random_image")
        G_reader_settings:saveSetting("screensaver_dir", dir)
    end
    if not Device:isKindle() and G_reader_settings:readSetting("screensaver_dir") == nil then
        G_reader_settings:saveSetting("screensaver_dir", dir) -- (only Kindles look in /mnt/us/screensavers by themselves)
    end
    slow.screensavers = nil -- (the outbox lists them afresh)
    Log.info("sync: sleep screen pictures:", added, "brought,", type(st.remove) == "table" and #st.remove or 0, "taken off, mode", tostring(st.mode))
    return added
end

--- Which sleep screen is on, for the page.
function Usb.sleepMode()
    if G_reader_settings:nilOrTrue("gzreader_sleep_auto") then return "auto" end
    if G_reader_settings:readSetting("screensaver_type") == "random_image" then return "always" end
    return "other"
end

--- Grimmory's reading stats the page fetched (Home's "Grimmory reading
--- stats" widget: gzreader_grimstats.lua), with this sync's sessions in.
function Usb.takeStats(plugin, st)
    if type(st) ~= "table" then return nil end
    local old = plugin.store.grimmory_stats
    local prev = type(old) == "table" and type(old.values) == "table" and old.values or {}
    local at = tonumber(st.at) or os.time()
    if type(st.values) == "table" then
        local values = {}
        for _i, k in ipairs({ "streak", "longest_streak", "reading_days", "week_time", "week_books", "month_sessions", "year_finished" }) do
            values[k] = tonumber(st.values[k])
        end
        plugin.store.grimmory_stats = { at = at, values = values, usb = true }
    elseif st.error then
        Log.warn("sync: Grimmory reading stats:", tostring(st.error) == "permission"
            and "this user may not see reading statistics (Grimmory: user settings → permissions)" or tostring(st.error))
        plugin.store.grimmory_stats = { at = at, values = prev, error = tostring(st.error), usb = true }
    else
        return nil
    end
    pcall(function() require("common/gz_view").redrawHome() end)
    return true
end

function Usb.import(plugin, on_prepared)
    local base = Usb.dir(plugin)
    local inbox = readJson(base .. "/inbox.json")
    if not inbox then return nil end
    local r = { sent = 0, failed = 0, books = 0, audiobooks = 0, music = 0 }
    r.clock = select(2, pcall(Usb.fixClock, inbox.written_at)) == true
    local ok, err = pcall(function()
        r.sent = Usb.applyDone(plugin, set(inbox.done))
        r.marks = Usb.applyMarks(plugin, set(inbox.done), inbox.created)
        for _i, f in ipairs(type(inbox.failed) == "table" and inbox.failed or {}) do
            Log.warn("sync: the computer couldn't send", tostring(f.id), tostring(f.error))
            if tostring(f.error or ""):match("^http_4") and tostring(f.id):match("^p:") then
                -- (refused for good: a book gone from Grimmory; not sent again)
                local book = tostring(f.id):match("^p:([^:]+):")
                local body = book and plugin.store.pending.progress[book]
                if body and Usb.jobId("progress", book, body) == f.id then plugin.store.pending.progress[book] = nil end
            else
                r.failed = r.failed + 1 -- (still waiting: the next sync tries again)
            end
        end
        if type(inbox.grimmory) == "table" and inbox.grimmory.server then
            plugin.store.server = inbox.grimmory.server
            plugin.store.username = inbox.grimmory.user
        end
        r.stats = Usb.takeStats(plugin, inbox.grimmory_stats)
        pcall(Usb.takeMusicQuality, plugin, inbox)
        for _i, b in ipairs(type(inbox.books) == "table" and inbox.books or {}) do
            local okb, got = pcall(Usb.takeBook, plugin, base, b)
            if okb and got then r.books = r.books + 1
            elseif not okb then Log.warn("sync: book", tostring(b.id), tostring(got)) end
        end
        local prepare = {}
        for _i, a in ipairs(type(inbox.audiobooks) == "table" and inbox.audiobooks or {}) do
            local oka, got = pcall(Usb.takeAudiobook, plugin, base, a, prepare)
            if oka and got then r.audiobooks = r.audiobooks + 1
            elseif not oka then Log.warn("sync: audiobook", tostring(a.id), tostring(got)) end
        end
        for _i, m in ipairs(type(inbox.music) == "table" and inbox.music or {}) do
            local okm, got = pcall(Usb.takeMusic, plugin, base, m, prepare)
            if okm and got then r.music = r.music + 1
            elseif not okm then Log.warn("sync: music", tostring(m.key), tostring(got)) end
        end
        if type(inbox.notes) == "table" then
            local okn, got = pcall(Usb.takeNotes, plugin, base, inbox.notes)
            if okn then r.notes = got or nil else Log.warn("sync: notes:", tostring(got)) end
        end
        if type(inbox.calendars) == "table" then
            local okc, got = pcall(Usb.takeCalendars, plugin, base, inbox.calendars)
            if okc then r.events = got else Log.warn("sync: calendars:", tostring(got)) end
        end
        if type(inbox.screensavers) == "table" then
            local oks, got = pcall(Usb.takeScreensavers, base, inbox.screensavers)
            if oks then r.pictures = got else Log.warn("sync: sleep screen pictures:", tostring(got)) end
        end
        r.prepare = prepare
    end)
    if not ok then Log.err("sync: taking in what the computer brought failed:", tostring(err)) end
    -- done with it (also when part of it failed: not taken in twice)
    os.remove(base .. "/inbox.json")
    rmrf(base .. "/in")
    plugin.store.usb_last = { at = tonumber(inbox.written_at) or os.time(), imported = os.time(),
        books = r.books, audiobooks = r.audiobooks, music = r.music, sent = r.sent }
    -- the library copy may be new: lists and the index from it
    pcall(function() require("gzreader_offlineapi").forget() end)
    pcall(function()
        local Index = require("gzreader_index")
        Index.data = nil
        os.remove(DataStorage:getSettingsDir() .. "/gzreader_index.json")
    end)
    Usb.last_outbox = nil
    Usb.forgetCached()
    plugin:save()
    pcall(plugin.writeManifest, plugin)
    pcall(function() require("gzreader_coverwarm").schedule(plugin, 15) end)
    Log.info("sync: took in what the computer brought:", r.sent, "sent,", r.books, "books,", r.audiobooks, "audiobooks,",
        r.music, "music")
    if r.prepare and #r.prepare > 0 then
        Usb.prepareAll(plugin, r.prepare, on_prepared)
    elseif on_prepared then
        on_prepared()
    end
    return r
end

--- What the summary says, e.g. "3 books, 1 audiobook; 12 updates sent".
function Usb.summaryText(r)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local parts = {}
    if r.books > 0 then parts[#parts + 1] = r.books == 1 and _("1 book") or T(_("%1 books"), r.books) end
    if r.audiobooks > 0 then parts[#parts + 1] = r.audiobooks == 1 and _("1 audiobook") or T(_("%1 audiobooks"), r.audiobooks) end
    if r.music > 0 then parts[#parts + 1] = r.music == 1 and _("1 album or playlist") or T(_("%1 albums or playlists"), r.music) end
    if r.notes then parts[#parts + 1] = r.notes == 1 and _("1 note") or T(_("%1 notes"), r.notes) end
    if r.events then parts[#parts + 1] = T(_("calendar: %1 events"), r.events) end
    if (r.pictures or 0) > 0 then parts[#parts + 1] = r.pictures == 1 and _("1 sleep screen picture") or T(_("%1 sleep screen pictures"), r.pictures) end
    local text = #parts > 0 and table.concat(parts, ", ") or _("No new books")
    if r.sent > 0 then text = text .. "\n" .. T(_("%1 reading updates sent to Grimmory."), r.sent) end
    if (r.marks or 0) > 0 then text = text .. "\n" .. T(_("%1 bookmark and highlight changes sent to Grimmory."), r.marks) end
    if r.failed > 0 then text = text .. "\n" .. T(_("%1 couldn't be sent; they'll go with the next sync."), r.failed) end
    return text
end

---------------------------------------------------------------- a GZreader update

--- Test builds switched on or off on the page (inbox.test_builds): the
--- Kindle's own setting follows (Settings → Updates → Test builds).
function Usb.takeTestBuilds(inbox)
    if type(inbox) ~= "table" or type(inbox.test_builds) ~= "boolean" then return false end
    local Update = require("gzreader_update")
    if inbox.test_builds == Update.betaEnabled() then return false end
    Update.setBeta(inbox.test_builds)
    return true
end

--- Music quality chosen on the page (inbox.music_quality = { bitrate, shrink }):
--- the Kindle's Plex settings follow (Music tab → Plex: you · server).
function Usb.takeMusicQuality(plugin, inbox)
    local q = type(inbox) == "table" and inbox.music_quality
    if type(q) ~= "table" then return false end
    local b = tonumber(q.bitrate)
    local ok = false
    for _i, v in ipairs(require("gzreader_music").BITRATES) do if v == b then ok = true end end
    if not ok then return false end
    plugin.store.plex = plugin.store.plex or {}
    local s = plugin.store.plex
    local shrink = q.shrink == true or nil
    if s.bitrate == b and s.shrink == shrink then return false end
    s.bitrate, s.shrink = b, shrink
    plugin:save()
    Log.info("sync: music quality from the computer:", b, "kbps, shrink", tostring(shrink == true))
    return true
end

--- The page brought a GZreader update (inbox.update = { version, file, size }):
--- installed before anything else is taken in (the new GZreader takes in
--- the rest after it restarts). Returns true when it was installed (restart
--- now), or nil, why it wasn't.
function Usb.installUpdate(plugin, base, inbox)
    local u = type(inbox) == "table" and inbox.update
    if type(u) ~= "table" or type(u.file) ~= "string" then return nil end
    local Update = require("gzreader_update")
    local src = base .. "/" .. u.file
    local function forget()
        -- (off the inbox: not tried again; the rest of it still comes in)
        inbox.update = nil
        writeFile(base .. "/inbox.json", JSON.encode(inbox))
        os.remove(src)
    end
    if not isFile(src) then forget(); return nil, "the update file isn't there" end
    -- (a test build: any other than this one; a release: a newer one)
    if not Update.isNewer({ version = tostring(u.version), beta = u.beta == true }) then
        Log.info("sync: update", tostring(u.version), "not newer than", Update.currentVersion())
        forget()
        return nil
    end
    local size = lfs.attributes(src, "size")
    if tonumber(u.size) and size ~= tonumber(u.size) then
        Log.warn("sync: update", u.version, "is", size, "bytes, expected", u.size)
        forget()
        return nil, "the update file is incomplete"
    end
    -- (out of in/ first: taking in the rest removes in/)
    local zip = DataStorage:getDataDir() .. "/cache/gzreader-update.zip"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    os.remove(zip)
    if not move(src, zip) then forget(); return nil, "couldn't move the update" end
    inbox.update = nil
    writeFile(base .. "/inbox.json", JSON.encode(inbox))
    Log.info("sync: installing GZreader", u.version, "brought by the computer")
    local ok, err = Update.apply(zip, {})
    os.remove(zip)
    if not ok then Log.err("sync: update failed:", tostring(err)); return nil, err end
    return true
end

---------------------------------------------------------------- at start

--- Set up (each start): note the mode, take in the inbox.
function Usb.start(plugin)
    local Net = require("gzreader_net")
    Net.usb = Usb.active()
    Usb.plugin = plugin
    if not Net.usb then return end
    if Usb.started then return end
    Usb.started = true
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(1, function()
        local base = Usb.dir(plugin)
        if not isFile(base .. "/inbox.json") then return Usb.writeOutbox(plugin) end
        local InfoMessage = require("ui/widget/infomessage")
        local _ = require("gettext")
        local T = require("ffi/util").template
        local inbox = readJson(base .. "/inbox.json")
        Usb.takeTestBuilds(inbox)
        if inbox and type(inbox.update) == "table" then
            local version = tostring(inbox.update.version)
            local busy = InfoMessage:new{ text = T(_("Installing GZreader %1 (from your computer)…"), version), timeout = 0 }
            UIManager:show(busy)
            UIManager:forceRePaint()
            local done, err = Usb.installUpdate(plugin, base, inbox)
            UIManager:close(busy)
            if done then
                -- the new GZreader takes in the rest when it starts
                UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 installed. Restarting…"), version), timeout = 2 })
                UIManager:scheduleIn(2, function() UIManager:restartKOReader() end)
                return
            elseif err then
                UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 couldn't be installed: %2"), version, tostring(err)), timeout = 6 })
            end
        end
        local msg = InfoMessage:new{ text = _("Taking in what your computer brought…"), timeout = 0 }
        UIManager:show(msg)
        UIManager:forceRePaint()
        local r = Usb.import(plugin, function()
            pcall(function() require("gzreader_tasks").changed() end)
        end)
        UIManager:close(msg)
        Usb.writeOutbox(plugin)
        if r then
            UIManager:show(InfoMessage:new{ text = _("Synced with your computer") .. "\n\n" .. Usb.summaryText(r), timeout = 6 })
            pcall(function()
                local FM = require("apps/filemanager/filemanager")
                local fc = FM.instance and FM.instance.file_chooser
                if fc then fc:refreshPath() end
            end)
        end
    end)
end

---------------------------------------------------------------- the screen

--- What's waiting to go (for the Sync screen).
function Usb.waiting(plugin)
    local p = plugin.store.pending
    local n = 0
    for _k in pairs(p.progress or {}) do n = n + 1 end
    n = n + #(p.sessions or {})
    for _k in pairs(p.ratings or {}) do n = n + 1 end
    local notes = #((plugin.store.memos or {}).queue or {})
    return n, notes
end

--- Menu → Sync with computer: how to, what's waiting, the queue.
function Usb.show(plugin)
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local _ = require("gettext")
    local T = require("ffi/util").template
    Usb.writeOutbox(plugin)
    local updates, notes = Usb.waiting(plugin)
    local q = queue(plugin)
    local kindle = Device:isKindle()
    local lines = {
        _("Sync with a computer"),
        "",
        kindle and _("1. Press Connect to computer: GZreader steps aside so the Kindle can share its USB drive (it can't while GZreader runs).")
            or _("1. Exit GZreader (the USB drive only works while it isn't running)."),
        _("2. Plug the Kindle into a computer and open this page in Chrome or Edge:"),
        "   " .. Usb.PAGE_URL:gsub("^https://", ""),
        _("3. Choose the Kindle's drive, enter its PIN and press Sync."),
        kindle and _("4. Eject the Kindle and unplug it: GZreader starts again by itself and takes in the new books.")
            or _("4. Eject the Kindle and start GZreader: it takes in the new books."),
        "",
    }
    local status = {}
    if updates > 0 then status[#status + 1] = T(_("%1 reading updates to send"), updates) end
    if notes > 0 then status[#status + 1] = T(_("%1 note changes to send"), notes) end
    if #q > 0 then
        local kb = Usb.queueSizeKb(plugin)
        status[#status + 1] = T(_("%1 in the sync queue"), #q)
            .. (kb > 0 and string.format(kb < 10240 and " (%.1f MB)" or " (%.0f MB)", kb / 1024) or "")
    end
    if #status == 0 then status[1] = _("Nothing waiting to be sent.") end
    lines[#lines + 1] = table.concat(status, "\n")
    local last = plugin.store.usb_last
    if last and last.imported then
        lines[#lines + 1] = T(_("Last sync: %1"), os.date("%b %d, %H:%M", last.imported))
    end
    local dialog
    local buttons = {}
    if kindle then
        buttons[#buttons + 1] = { { text = _("Connect to computer (USB drive)"), callback = function()
            UIManager:close(dialog)
            Usb.connect(plugin)
        end } }
    end
    if #q > 0 then
        buttons[#buttons + 1] = { { text = T(_("Sync queue (%1)"), #q), callback = function()
            UIManager:close(dialog)
            Usb.showQueue(plugin)
        end } }
    end
    buttons[#buttons + 1] = { { text = _("Exit GZreader now"), callback = function()
        UIManager:close(dialog)
        pcall(Usb.finishCfis, plugin)
        plugin:save()
        local ok, Dispatcher = pcall(require, "dispatcher")
        if ok and Dispatcher.execute then Dispatcher:execute({ exit = true }) end
    end } }
    buttons[#buttons + 1] = { { text = _("Close"), callback = function() UIManager:close(dialog) end } }
    dialog = ButtonDialog:new{ title = table.concat(lines, "\n"), title_align = "left", buttons = buttons }
    UIManager:show(dialog)
    return dialog
end

--- Step aside for the Kindle's USB drive mode: save everything (the outbox
--- included), then quit with exit code 86. koreader.sh (platform/kindle)
--- lets the Kindle's USB service run again, waits while the drive is shared
--- and starts GZreader again once it's back.
function Usb.connect(plugin)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Event = require("ui/event")
    local _ = require("gettext")
    pcall(Usb.finishCfis, plugin)
    plugin:save()
    Log.info("sync: stepping aside for the Kindle's USB drive mode")
    UIManager:show(InfoMessage:new{ text = _("Plug the Kindle into the computer.\n\nGZreader starts again after you eject it."), timeout = 0 })
    UIManager:forceRePaint()
    UIManager:flushSettings()
    UIManager:broadcastEvent(Event:new("Close"))
    UIManager:quit(86)
end

--- The sync queue: what the next sync brings; select one to take it off.
function Usb.showQueue(plugin)
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local ConfirmBox = require("ui/widget/confirmbox")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local menu
    local function items()
        local out = {}
        for _i, q in ipairs(queue(plugin)) do
            local authors = type(q.authors) == "table" and table.concat(q.authors, ", ") or ""
            out[#out + 1] = {
                text = (q.title or "?") .. (authors ~= "" and (" — " .. authors) or ""),
                mandatory = (q.kind == "audiobook" and _("audiobook") or (q.format or ""))
                    .. (q.size_kb and string.format(" · %.1f MB", q.size_kb / 1024) or ""),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Take “%1” off the sync queue?"), q.title or ""),
                        ok_text = _("Take off"),
                        ok_callback = function()
                            Usb.dequeue(plugin, q.id)
                            if menu then menu:switchItemTable(nil, items()) end
                        end,
                    })
                end,
            }
        end
        if #out == 0 then out[1] = { text = _("The sync queue is empty."), select_enabled = false } end
        return out
    end
    menu = Menu:new{ title = _("Sync queue"), item_table = items(), covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, name = "gz_usb_queue" }
    UIManager:show(menu)
    return menu
end

--- "Added to the sync queue" (and that a sync brings it).
function Usb.queuedMessage(plugin, book)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local name = book.title or ""
    if not Usb.enqueue(plugin, book) then
        return UIManager:show(InfoMessage:new{ text = T(_("“%1” is already in the sync queue."), name), timeout = 3 })
    end
    UIManager:show(InfoMessage:new{
        text = T(_("“%1” is in the sync queue. It comes to the Kindle with the next sync with your computer (Menu → Sync with computer)."), name),
        timeout = 4 })
end

return Usb
