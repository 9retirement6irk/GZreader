--[[--
Pre-size the covers of downloaded books in the background.

ZenOS shows covers at a few exact sizes (Home, the cover strip, the library
grid and list). GZreader remembers those sizes (common/cover_disk_cache) and
this job makes every downloaded book's cover at each of them ahead of time,
in a low-priority background process, saving the results on disk. Home and
the library then just load them: no decompressing and no scaling while you
wait.

Runs a minute after start, after downloads, and when ZenOS shows covers at a
size it hasn't seen before. Books whose cover hasn't been read from the book
yet are handed to KOReader's cover extraction first (also in the background)
and pre-sized on the next run.
]]

local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local Warm = {
    running = false,
    tried = {}, -- books handed to cover extraction this session
    START_DELAY = 60,
    EXTS = { epub = true, pdf = true, cbz = true, cbr = true, cbt = true, fb2 = true, mobi = true,
        azw = true, azw3 = true, djvu = true, txt = true, html = true, docx = true },
}

local function renice(pid)
    if pid then os.execute(string.format("renice -n 19 -p %d >/dev/null 2>&1 || renice 19 %d >/dev/null 2>&1", pid, pid)) end
end

--- Downloaded books: Grimmory downloads plus any book file in the GZreader folder.
function Warm.books(plugin)
    local seen, list = {}, {}
    local function add(p)
        if p and not seen[p] and lfs.attributes(p, "mode") == "file" then seen[p] = true; list[#list + 1] = p end
    end
    for _id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" then add(e.path) end
    end
    local dir = plugin.store.library_dir
    if dir and lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            local ext = name:match("%.([%w]+)$")
            if ext and Warm.EXTS[ext:lower()] and not name:match("^%.") then add(dir .. "/" .. name) end
        end
    end
    return list
end

--- What still has to be made: { jobs = { {path, sizes} }, missing = { paths } }.
function Warm.plan(plugin)
    local ok_d, Disk = pcall(require, "common/cover_disk_cache")
    local ok_b, BIM = pcall(require, "bookinfomanager")
    if not ok_d or not ok_b then return nil end
    local jobs, missing, nsizes = {}, {}, 0
    for _i, path in ipairs(Warm.books(plugin)) do
        local info = BIM:getBookInfo(path, false)
        if not info or not info.cover_fetched then
            missing[#missing + 1] = path
        elseif info.has_cover and not info.ignore_cover then
            local todo = {}
            for _j, sz in ipairs(Disk.targetsFor(tonumber(info.cover_w), tonumber(info.cover_h))) do
                if not Disk.has(path, sz[1], sz[2]) then todo[#todo + 1] = sz end
            end
            if #todo > 0 then
                jobs[#jobs + 1] = { path = path, sizes = todo }
                nsizes = nsizes + #todo
            end
        end
    end
    return { jobs = jobs, missing = missing, count = nsizes }
end

--- Child process: make and save the covers. Returns how many were made.
local function work(jobs)
    local BIM = require("bookinfomanager")
    local Disk = require("common/cover_disk_cache")
    local RC = require("common/cover_render_cache")
    local made = 0
    for _i, job in ipairs(jobs) do
        local info = BIM:getBookInfo(job.path, true)
        local src = info and info.cover_bb
        if src then
            for _j, sz in ipairs(job.sizes) do
                local okc, copy = pcall(src.copy, src)
                local out = okc and copy and RC._resize(copy, sz[1], sz[2])
                if out then
                    if Disk.save(job.path, sz[1], sz[2], out) then made = made + 1 end
                    pcall(out.free, out)
                end
            end
            pcall(src.free, src)
        end
    end
    return made
end

local function extractMissing(missing)
    if #missing == 0 then return end
    local ok_b, BIM = pcall(require, "bookinfomanager")
    if not ok_b or BIM:isExtractingInBackground() then return end
    local ok_d, Disk = pcall(require, "common/cover_disk_cache")
    -- extract at the largest size in use, so no view needs a better one
    local w, h = 0, 0
    if ok_d then
        local s = Disk.knownSizes()
        for _i, list in ipairs({ s.boxes, s.exact }) do
            for _j, e in ipairs(list) do w, h = math.max(w, e[1]), math.max(h, e[2]) end
        end
    end
    if w == 0 then return end
    local files = {}
    for _i, p in ipairs(missing) do
        if #files >= 20 then break end -- a batch at a time
        if not Warm.tried[p] then
            Warm.tried[p] = true
            files[#files + 1] = { filepath = p, cover_specs = { max_cover_w = w, max_cover_h = h } }
        end
    end
    if #files == 0 then return end
    Log.info("covers: reading", #files, "cover(s) from the books first")
    BIM:extractInBackground(files)
    renice(BIM.subprocesses_pids and BIM.subprocesses_pids[#BIM.subprocesses_pids])
    return true
end

--- Run once now (if not already running). on_done(made) optional.
--- Everything that touches many files (finding what's missing, making the
--- covers, measuring the cache) happens in the low-priority child process,
--- so the screen never waits for it.
function Warm.run(plugin, on_done)
    if Warm.running then return end
    local ok_b, BIM = pcall(require, "bookinfomanager")
    if not ok_b or not pcall(require, "common/cover_disk_cache") then return end
    if BIM:isExtractingInBackground() then
        -- don't compete with KOReader's own extraction; try again later
        UIManager:scheduleIn(30, function() Warm.run(plugin, on_done) end)
        return
    end
    Warm.running = true
    local started = os.time()
    BIM:closeDbConnection() -- not shared with the child (like KOReader's extraction)
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        local plan = Warm.plan(plugin) or { jobs = {}, missing = {}, count = 0 }
        local made = 0
        if plan.count > 0 then
            made = work(plan.jobs) -- writes nothing itself
        end
        local files, bytes = require("common/cover_disk_cache").usage()
        local out = { string.format("%d %d %d %d", made, plan.count, files, bytes) }
        for _i, m in ipairs(plan.missing) do out[#out + 1] = m end
        ffiutil.writeToFD(wfd, table.concat(out, "\n"), true)
    end, true)
    if not pid then Warm.running = false; return end
    renice(pid)
    local out = require("gzreader_async").reader(fd) -- (the list of books can be over a pipe's 64 KB)
    local function poll()
        out:drain()
        if not ffiutil.isSubProcessDone(pid) then return UIManager:scheduleIn(2, poll) end
        local res = out:finish() or ""
        Warm.running = false
        local head, rest = res:match("^([^\n]*)\n?(.*)$")
        local made, wanted, files, bytes = (head or ""):match("^(%d+) (%d+) (%d+) (%d+)$")
        local missing = {}
        for line in (rest or ""):gmatch("[^\n]+") do missing[#missing + 1] = line end
        if tonumber(wanted) and tonumber(wanted) > 0 then
            Log.info("covers: pre-sized", made, "of", wanted, "in", (os.time() - started) .. "s;", files, "on disk,",
                string.format("%.1f MB", (tonumber(bytes) or 0) / 1048576))
        end
        if extractMissing(missing) then Warm.schedule(plugin, 120) end -- then pre-size those
        if on_done then on_done(tonumber(made) or 0) end
    end
    UIManager:scheduleIn(2, poll)
end

--- Run later (debounced): after start, downloads, new sizes.
function Warm.schedule(plugin, delay)
    if G_reader_settings:isFalse("gzreader_presize_covers") then return end
    if Warm.pending then UIManager:unschedule(Warm.pending) end
    Warm.pending = function()
        Warm.pending = nil
        pcall(Warm.run, plugin)
    end
    UIManager:scheduleIn(delay or 20, Warm.pending)
end

return Warm
