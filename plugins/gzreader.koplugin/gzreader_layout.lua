--[[--
New books laid out in the background while the Kindle charges.

The first open of a big EPUB is slow: the book engine (crengine) lays the
whole book out and keeps the result (koreader/cache/cr3cache); later opens
use it (10–30 s for a big book on a Kindle 3, the first time). While the
Kindle charges and Home is on screen, GZreader opens a downloaded book that
was never opened in a background process at the lowest priority, the way the
reader would open it (KOReader's own ReaderUI, so the same settings: the
layout is only reused when they match), lets the engine lay it out, and
closes it, which writes the layout cache. The book itself isn't touched: no
reading history, no settings next to the book, no statistics (the process
ends as soon as the layout is done, before the reader is ready).

Not on Kindles with 128 MB or less (Kindle 2, DX): a second book engine
doesn't fit there. Not while books download or other background work runs
(Layout.busy: on a Kindle 3 with many books downloading, the layouts made
Home and reading slow, memory down to 2-3 MB), and not before a new book's
picture-book check: a picture book is laid out with the margins and style
the check gives it (laid out before, its first open fitted it and laid it
out again; and the check, run beside a layout, failed for lack of memory). It stops at once when the
charger is unplugged, a book is opened or a download starts; a book that
fails twice isn't tried again. The background process
is the one the kernel ends first if memory runs out (oom_score_adj).
Settings → Reader → Lay out new books while charging.
]]

local Log = require("gzreader_log")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local Layout = {
    SETTING = "gzreader_layout_charging",
    EVERY = 300,       -- s between looks while on Home
    POLL = 2,          -- s between checks on a running layout
    TIMEOUT = 15 * 60, -- s: given up (the next look tries another book)
    MAX_TRIES = 2,
    LOW_MEMORY_KB = 160 * 1024,
    EXTS = { epub = true, fb2 = true, mobi = true, azw = true, azw3 = true, htm = true, html = true, txt = true, rtf = true, doc = true, chm = true },
    running = nil,
    -- injectable (tests)
    fork = nil, isCharging = nil, readerOpen = nil, sidecar = nil, memTotalKB = nil,
}

function Layout.enabled() return G_reader_settings:readSetting(Layout.SETTING) ~= false end

local function memTotalKB()
    if Layout.memTotalKB then return Layout.memTotalKB() end
    local f = io.open("/proc/meminfo", "r")
    if not f then return nil end
    local s = f:read("*a") or ""
    f:close()
    return tonumber(s:match("MemTotal:%s*(%d+)"))
end

--- Can this Kindle do it at all (memory)?
function Layout.possible()
    local kb = memTotalKB()
    return kb ~= nil and kb > Layout.LOW_MEMORY_KB
end

local function charging()
    if Layout.isCharging then return Layout.isCharging() end
    local ok, v = pcall(function() return require("device"):getPowerDevice():isCharging() end)
    return ok and v == true
end

local function readerOpen()
    if Layout.readerOpen then return Layout.readerOpen() end
    local RU = package.loaded["apps/reader/readerui"]
    return RU ~= nil and RU.instance ~= nil
end

--- Something else is working: a book downloading or waiting to, or another
--- background job (a picture-book check, covers): a reason, or nil.
function Layout.busy()
    if Layout.isBusy then return Layout.isBusy() end
    local D = package.loaded["gzreader_download"]
    if type(D) == "table" and (D.active or (type(D.queue) == "table" and #D.queue > 0)) then return "a download" end
    local A = package.loaded["gzreader_async"]
    if type(A) == "table" and (A.local_jobs or 0) > 0 then return "other background work" end
    -- (a book waiting for its picture-book check: laid out after it, with the
    -- settings it writes; laid out before, the fitting threw the layout away)
    local PB = package.loaded["gzreader_picturebook"]
    if type(PB) == "table" and type(PB.queue) == "table" and #PB.queue > 0 then return "a picture-book check" end
    return nil
end

--- What the settings next to the book say (nil: no settings file): a table
--- with the keys that matter here.
local function sidecar(path)
    if Layout.sidecar then return Layout.sidecar(path) end
    local ok, v = pcall(function()
        local DocSettings = require("docsettings")
        if not DocSettings:hasSidecarFile(path) then return nil end
        local ds = DocSettings:open(path)
        local t = {}
        for _i, k in ipairs({ "last_xpointer", "last_page", "percent_finished", "gzreader_picture_book", "gzreader_pb_fit" }) do
            t[k] = ds:readSetting(k)
        end
        return t
    end)
    return ok and v or nil
end

--- Why this book isn't laid out now, or nil. Opened already (a reading
--- position next to it). A picture book recognized but not fitted yet: the
--- first open fits it (margins, a style tweak) and lays it out again, so a
--- layout now would be thrown away. (The settings the picture-book check
--- writes before the first open are no reason: the background process
--- opens the book with them, so its layout is the one the reader wants.)
function Layout.notYet(path)
    local sc = sidecar(path)
    if not sc then return nil end
    if sc.last_xpointer ~= nil or sc.last_page ~= nil or sc.percent_finished ~= nil then return "opened" end
    if sc.gzreader_picture_book == true and sc.gzreader_pb_fit == nil then return "a picture book fitted when it opens" end
    return nil
end

--- The downloaded book to lay out next: never opened, not laid out yet, not
--- failed twice (Layout.notYet); the newest first. Or nil.
function Layout.candidate(plugin)
    local best, best_t
    for id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" and type(e.path) == "string" and not e.laid_out and (e.layout_tries or 0) < Layout.MAX_TRIES then
            local ext = (e.path:match("%.([%w]+)$") or ""):lower()
            local t = Layout.EXTS[ext] and lfs.attributes(e.path, "modification")
            if t and (not best_t or t > best_t) and not Layout.notYet(e.path) then best, best_t = { id = tostring(id), entry = e }, t end
        end
    end
    return best
end

--- In the background process: open the book as the reader would, and as soon
--- as it's laid out, close it (the layout cache is written) and end.
function Layout.child(path, report)
    pcall(function() require("gzreader_async").lowerPriority(19) end)
    for _i, p in ipairs({ "/proc/self/oom_score_adj", "/proc/self/oom_adj" }) do
        local f = io.open(p, "w")
        if f then f:write(p:find("score") and "1000" or "15"); f:close() end
    end
    local t0 = os.time()
    local DocumentRegistry = require("document/documentregistry")
    local doc = DocumentRegistry:openDocument(path)
    if not doc or not doc._document or not doc.render then return report("err not a book the engine lays out") end
    -- (nothing written but the layout: no history, no settings next to the book)
    pcall(function() require("readhistory").addItem = function() end end)
    pcall(function() require("docsettings").flush = function() end end)
    pcall(function() G_reader_settings.flush = function() end end)
    local orig_render = doc.render
    doc.render = function(d, ...)
        local r = { orig_render(d, ...) }
        local pages = 0
        pcall(function() pages = d:getPageCount() end)
        pcall(function() d._document:close() end) -- (writes the layout cache)
        report(string.format("ok %d %d", pages, os.time() - t0))
        os.exit(0)
        return unpack(r)
    end
    local Screen = require("device").screen
    require("apps/reader/readerui"):new{ dimen = Screen:getSize(), document = doc }
    report("err no layout")
end

local function fork(path)
    if Layout.fork then return Layout.fork(path) end
    local ffiutil = require("ffi/util")
    local pid, fd = ffiutil.runInSubProcess(function(_pid, wfd)
        local ok, err = pcall(Layout.child, path, function(s) ffiutil.writeToFD(wfd, s .. "\n", true) end)
        if not ok then ffiutil.writeToFD(wfd, "err " .. tostring(err):gsub("\n", " "):sub(1, 200) .. "\n", true) end
    end, true)
    if not pid then return nil end
    local out = require("gzreader_async").reader(fd)
    return {
        poll = function() -- nil (still going), or the line it sent ("" if it died)
            out:drain()
            if not ffiutil.isSubProcessDone(pid) then return nil end
            return (out:finish() or ""):match("^[^\n]*") or ""
        end,
        stop = function() pcall(ffiutil.terminateSubProcess, pid) end,
    }
end

--- After a background layout: the reader's book engine reads its layout
--- cache index again (cache/cr3cache/cr3cache.inx). The index is read once,
--- when the first book opens, and kept in memory; the background process
--- adds its book to the index on disk, which this process didn't see, so a
--- book laid out after another one had been opened was laid out again when
--- it opened (in the emulator: 1.0 s, against 0.04 s when no book had been
--- opened first; on a Kindle 3, Steve Jobs: 13.9 s). Not while a book is
--- open. Nothing to do before the first book opens (crengine not started:
--- cacheInit errors, and the index is read fresh at that first open).
function Layout.reloadCacheIndex()
    if Layout.reloadIndex then return Layout.reloadIndex() end
    if readerOpen() then return false end
    local CD = package.loaded["document/credocument"]
    if type(CD) ~= "table" or type(CD.cacheInit) ~= "function" then return false end
    local ok = pcall(CD.cacheInit)
    return ok
end

local function finish(plugin, job, line)
    Layout.running = nil
    local e = job.entry
    local pages, secs = (line or ""):match("^ok (%d+) (%d+)")
    if pages then
        e.laid_out = os.time()
        e.layout_secs = tonumber(secs)
        e.layout_hash = nil -- (kept by 2026-11-09's beta; it told nothing, see Layout.opened)
        local reread = Layout.reloadCacheIndex()
        Log.info("layout: book", job.id, "laid out while charging:", pages, "pages in", secs, "s",
            reread and "(layout cache index read again)" or "")
    else
        e.layout_tries = (e.layout_tries or 0) + 1
        Log.warn("layout: book", job.id, "not laid out:", line ~= "" and line or "the background process ended (memory?)")
    end
    pcall(plugin.saveSoon, plugin)
    if job.on_done then pcall(job.on_done, pages ~= nil, line) end
end

--- Lay this book out now (on_done(ok, line)); false if one is already going.
--- forced: whether or not it's charging (the emulator's check).
function Layout.start(plugin, id, entry, on_done, forced)
    if Layout.running then return false end
    local p = fork(entry.path)
    if not p then return false end
    local job = { id = tostring(id), entry = entry, proc = p, started = os.time(), on_done = on_done, forced = forced }
    Layout.running = job
    Log.info("layout: book", job.id, "laid out in the background (charging, on Home)")
    local function poll()
        if Layout.running ~= job then return end
        local line = p.poll()
        if line then return finish(plugin, job, line) end
        local busy = Layout.busy()
        local why = (not charging() and not job.forced and "the charger unplugged") or (readerOpen() and "a book opened")
            or (busy == "a download" and "a download started")
            or (os.time() - job.started > Layout.TIMEOUT and "too long")
        if why then
            p.stop()
            Layout.running = nil
            if why == "too long" then entry.layout_tries = (entry.layout_tries or 0) + 1 end
            Log.info("layout: book", job.id, "stopped:", why)
            if on_done then pcall(on_done, false, "stopped: " .. why) end
            return
        end
        UIManager:scheduleIn(Layout.POLL, poll)
    end
    UIManager:scheduleIn(Layout.POLL, poll)
    return job
end

--- A look: charging, on Home, a book waiting? Then lay it out.
function Layout.tick(plugin)
    if Layout.running or not Layout.enabled() or not Layout.possible() or not charging() or readerOpen() or Layout.busy() then return nil end
    local c = Layout.candidate(plugin)
    if not c then return nil end
    return Layout.start(plugin, c.id, c.entry)
end

--- A book laid out in the background is opened: did the reader use that
--- layout? crengine can't say: its rendering hash differs between the
--- background process and the reader even when the reader uses the layout,
--- and hasCacheFile/isCacheFileStale are true for a book never laid out too
--- (all seen in the emulator). What tells is the time the reader's layout
--- took (gzreader_opentiming's "laid out"): a fraction of a second with the
--- layout cache, seconds without (a 630-page book in the emulator: 0.1 s and
--- 1.0 s; on a Kindle 3, 0.1-0.4 s and 9-14 s). Written in the log line.
Layout.REUSED_S = 1
function Layout.opened(_doc, entry, id, laid_s)
    if type(entry) ~= "table" or not entry.laid_out or entry.layout_checked then return end
    entry.layout_checked = true
    if laid_s == nil then
        local OT = package.loaded["gzreader_opentiming"]
        local cur = type(OT) == "table" and OT.cur
        laid_s = cur and cur.phases and cur.phases["laid out"] and require("ui/time").to_s(cur.phases["laid out"])
    end
    local bg = entry.layout_secs and string.format(" (in the background: %d s)", entry.layout_secs) or ""
    local verdict
    if type(laid_s) ~= "number" then
        verdict = "the reader's layout time not known" .. bg
    elseif laid_s < Layout.REUSED_S then
        verdict = string.format("its layout used: laid out in %.1f s%s", laid_s, bg)
    else
        verdict = string.format("laid out again, %.1f s%s: its layout wasn't used (other settings: margins, font, style?)", laid_s, bg)
    end
    Log.info("layout: book", tostring(id), "opened after its background layout:", verdict)
end

--- Look every EVERY seconds (and `soon` seconds from now: after a download).
function Layout.schedule(plugin, soon)
    if not Layout.possible() then return end
    if Layout.loop then UIManager:unschedule(Layout.loop) end
    Layout.loop = function()
        Layout.loop = nil
        pcall(Layout.tick, plugin)
        Layout.schedule(plugin)
    end
    UIManager:scheduleIn(soon or Layout.EVERY, Layout.loop)
end

return Layout
