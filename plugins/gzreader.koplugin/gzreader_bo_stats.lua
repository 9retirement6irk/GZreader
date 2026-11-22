--[[--
Reading time and ratings for BookOrbit.

Reading time: KOReader's own statistics (statistics.sqlite3: one row per page
read, with when and for how long) are what BookOrbit's reading activity is made
from. For each book downloaded from BookOrbit (or matched to one of its books),
the rows since the last upload are sent to POST /koreader/plugin/page-stats, by
the book's fingerprint; BookOrbit turns them into reading sessions itself and
ignores a row it has had. Sent a few seconds after a book closes and at most
every ten minutes otherwise, in a background process (it reads the database
there, so the screen's thread never waits on it).

  store.bookorbit_stats = { [fingerprint] = start time of the last row sent }

(Ratings need nothing here: gzreader_ratings.lua sends them through the client's
putRating and reads them from its getBook, as for Grimmory.)

Written from BookOrbit's routes and field names; none of its plugin's code is here.
]]

local Log = require("gzreader_log")

local Stats = { EVERY = 600, AFTER_CLOSE = 6, MAX_EVENTS = 500, MAX_BOOKS = 50, MAX_DURATION = 86400 }

function Stats.dbPath()
    return require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
end

--- A book's page rows after `since` (oldest first, at most `limit`), from KOReader's
--- statistics database: { { page, startTime, durationSeconds, totalPages }… }.
function Stats.read(db_path, hash, since, limit)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(db_path, "mode") ~= "file" then return {} end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(db_path, "ro")
    local out = {}
    local ok, err = pcall(function()
        local stmt = conn:prepare([[SELECT page, start_time, duration, total_pages FROM page_stat_data
            JOIN book ON book.id = page_stat_data.id_book
            WHERE book.md5 = ? AND start_time > ? ORDER BY start_time LIMIT ?]])
        local res = stmt:reset():bind(hash, since or 0, limit or Stats.MAX_EVENTS):resultset("i")
        stmt:close()
        local n = res and res[1] and #res[1] or 0
        for i = 1, n do
            local page, start, dur, total = tonumber(res[1][i]), tonumber(res[2][i]), tonumber(res[3][i]), tonumber(res[4][i])
            if page and start and start >= 1 and total and total >= 1 then
                out[#out + 1] = { page = math.max(0, page), startTime = start,
                    durationSeconds = math.max(0, math.min(Stats.MAX_DURATION, dur or 0)), totalPages = total }
            end
        end
    end)
    conn:close()
    if not ok then return nil, tostring(err) end
    return out
end

--- In the background: read and send. books = { { hash, since, file_id }… }.
--- Returns { until_ = { [hash] = last start time sent }, sent = rows, unmatched = { hash… } }, or nil, err.
function Stats.work(api, db_path, books)
    local Json = require("gzreader_json")
    local out = { until_ = {}, sent = 0, unmatched = {} }
    local batch, last = {}, {}
    local function flush()
        if #batch == 0 then return true end
        local res, err = api:putPageStats(batch)
        if not res then return nil, err end
        local gone = {}
        for _i, h in ipairs(res.unmatched or {}) do gone[h] = true; out.unmatched[#out.unmatched + 1] = h end
        for _i, b in ipairs(batch) do
            if not gone[b.hash] then
                out.until_[b.hash] = last[b.hash]
                out.sent = out.sent + #b.events
            end
        end
        batch = {}
        return true
    end
    for _i, book in ipairs(books) do
        local events, err = Stats.read(db_path, book.hash, book.since, Stats.MAX_EVENTS)
        if not events then return nil, err end
        if #events > 0 then
            last[book.hash] = events[#events].startTime
            batch[#batch + 1] = { hash = book.hash, bookFileId = tonumber(book.file_id), events = Json.list(events) }
            if #batch >= Stats.MAX_BOOKS then
                local ok, ferr = flush()
                if not ok then return nil, ferr end
            end
        end
    end
    local ok, ferr = flush()
    if not ok then return nil, ferr end
    return out
end

function Stats.enabled(plugin)
    return plugin:syncEnabled() and plugin:serverCan("stats") and type(plugin.api.putPageStats) == "function"
end

--- Send what's new (in the background). force: now, whatever was sent when. on_done(ok) optional.
function Stats.send(plugin, force, on_done)
    if not Stats.enabled(plugin) or Stats.busy then return on_done and on_done(false) end
    if not require("gzreader_net").connected() then return on_done and on_done(false) end
    local now = os.time()
    if not force and Stats.last and now - Stats.last < Stats.EVERY then return on_done and on_done(false) end
    local sent_until = type(plugin.store.bookorbit_stats) == "table" and plugin.store.bookorbit_stats or {}
    local books, seen = {}, {}
    for _id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" and type(e.hash) == "string" and not seen[e.hash] then
            seen[e.hash] = true
            books[#books + 1] = { hash = e.hash, since = tonumber(sent_until[e.hash]) or 0, file_id = e.file_id }
        end
    end
    if #books == 0 then return on_done and on_done(false) end
    Stats.busy, Stats.last = true, now
    local db_path = Stats.dbPath()
    require("gzreader_async").run(plugin.api, function(api) return Stats.work(api, db_path, books) end, function(res, err)
        Stats.busy = nil
        if type(res) ~= "table" then
            Log.info("BookOrbit reading time: not sent:", tostring(err))
            return on_done and on_done(false)
        end
        plugin.store.bookorbit_stats = type(plugin.store.bookorbit_stats) == "table" and plugin.store.bookorbit_stats or {}
        local n_books = 0
        for hash, t in pairs(res.until_ or {}) do
            plugin.store.bookorbit_stats[hash] = t
            n_books = n_books + 1
        end
        if n_books > 0 then
            plugin:save()
            Log.info("BookOrbit reading time: sent", res.sent or 0, "page rows of", n_books, "books")
            -- (Home's reading stats are older than what BookOrbit now has)
            if (tonumber(res.sent) or 0) > 0 then require("gzreader_grimstats").stale(plugin) end
        end
        if on_done then on_done(true) end
    end, "reading time", { nice = true })
end

--- A book just closed: its pages are in the database a moment later.
function Stats.later(plugin)
    if not Stats.enabled(plugin) then return end
    require("ui/uimanager"):scheduleIn(Stats.AFTER_CLOSE, function() Stats.send(plugin, true) end)
end

return Stats
