--[[--
Grimmory requests off the screen's thread.

On a Kindle 3 an HTTPS request to Grimmory takes 0.3–3.5 s (mostly the TLS
handshake), and the screen froze for that long whenever GZreader synced:
every 10 page turns, when a book opened, when queued updates were sent.
These now run in a short-lived background process; the screen keeps going
and the result comes back a moment later.

- One request process at a time, first come first served: Grimmory rotates
  refresh tokens, so two processes refreshing at once would lock each other
  out. The login is refreshed inside that process when it's due, and the new
  tokens come back with the result (1.2.3; before, the refresh ran on the
  screen's thread and could freeze it for the whole request, or much longer
  when the network was half down). Nothing here ever does network work on
  the screen's thread.
- Requests queued together for the same login run in one process, one
  after another (up to BATCH_MAX; long ones last), each result coming back
  on its own line as soon as it's ready: a fork of GZreader and a login
  check are seconds on a Kindle 3, and opening a book started four.
  Async.together(fn) holds the queue while fn() starts its requests.
- Results travel back as JSON (plain values only).
- `Async.sync = true` runs everything inline (tests; and where a result is
  needed right away, e.g. while going to sleep).
- While a book opens (Async.pause / Async.resume), the background
  processes running are paused and no new request starts: a Kindle 3 has
  one core and little memory, and a calendar sync running beside a book
  open made it take 23.5 s instead of 6 (2026-11-08). They carry on once
  the first page is up, their time limits moved on by the pause.
]]

local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local JSON = require("json")
local Log = require("gzreader_log")

local Async = {
    sync = false,
    POLL = 0.2,
    TIMEOUT = 120,
    -- A request process's priority (nice): it mostly waits on the network,
    -- but the TLS handshake is seconds of CPU on a Kindle 3, and it ran at
    -- the screen's own priority, so page turns waited for it (opening a book
    -- starts several). NICE_LONG: long CPU work (opts.nice).
    NICE = 5,
    NICE_LONG = 10,
    queue = {},
    busy = false,
    held = 0,       -- inside Async.together(): requests wait
    BATCH_MAX = 6,  -- requests in one background process at most
}

local function pack(...) return { n = select("#", ...), ... } end

--- (in a background process) Lower its own priority: was a renice command
--- run from the main process, which copied the whole of GZreader to start
--- a shell (slow on a Kindle 3) for every job.
function Async.lowerPriority(n)
    pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        ffi.C.setpriority(ffi.C.PRIO_PROCESS, 0, n)
    end)
end

--- What a background process writes to its pipe, read as it comes. A pipe
--- holds ~64 KB: a process writing more blocks until it's read, so waiting
--- for the process to end before reading would wait forever (1.5.1: a
--- Memos account with a lot of notes never loaded). Call :drain() on every
--- poll and :finish() once the process has ended.
function Async.reader(fd)
    local ffi = require("ffi")
    pcall(require, "ffi/posix_h")
    local chunks = {}
    local r = {}
    function r:drain()
        if not fd then return end
        for _i = 1, 64 do -- up to 64 chunks a poll; the rest next time
            local n = ffiutil.getNonBlockingReadSize(fd)
            if not n or n <= 0 then return end
            n = math.min(n, 65536)
            local buf = ffi.new("char[?]", n)
            local got = tonumber(ffi.C.read(fd, buf, n))
            if not got or got <= 0 then return end
            chunks[#chunks + 1] = ffi.string(buf, got)
        end
    end
    --- What has been read since the last take() (and isn't returned again).
    function r:take()
        local s = table.concat(chunks)
        chunks = {}
        return s
    end
    function r:finish()
        if not fd then return table.concat(chunks) end
        chunks[#chunks + 1] = ffiutil.readAllFromFD(fd) or ""
        fd = nil
        return table.concat(chunks)
    end
    return r
end

--- fn(api) under pcall, as packed results (an error becomes nil, message).
local function protected(fn, api)
    local res = pack(pcall(fn, api))
    if not res[1] then return pack(nil, tostring(res[2])) end
    local out = { n = res.n - 1 }
    for i = 2, res.n do out[i - 1] = res[i] end
    return out
end

local TOKEN_FIELDS = { "access_token", "refresh_token", "access_expires_at" }

local function encode(res, tokens)
    local out = { n = res.n, tokens = tokens }
    for i = 1, res.n do
        if res[i] ~= nil then out["r" .. i] = res[i] end
    end
    return JSON.encode(out)
end

local function decode(s)
    local ok, t = pcall(JSON.decode, s or "")
    if not ok or type(t) ~= "table" then return nil end
    local res = { n = tonumber(t.n) or 0, tokens = type(t.tokens) == "table" and t.tokens or nil }
    for i = 1, res.n do res[i] = t["r" .. i] end
    return res
end

local pump

local function netHold(on)
    pcall(function()
        local Net = require("gzreader_net")
        if on then Net.hold("async") else Net.release("async") end
    end)
end

--- One job's result, in the main process: usage statistics, the login it
--- may have renewed, then its on_done.
local function finishJob(job, res)
    pcall(function()
        require("gzreader_usage").request(job.name, res[1] ~= nil and res[1] ~= false,
            job.t0 and math.floor((require("socket").gettime() - job.t0) * 1000) or nil)
    end)
    if res.tokens and job.api and job.api.store then
        -- the login was refreshed in the background process: keep the new tokens
        local store = job.api.store
        if res.tokens.cleared then
            -- (only if they're still the ones it started with: the main
            -- process may have a newer login, it must not be thrown away)
            if store.refresh_token == job.refresh_before then pcall(job.api.clearTokens, job.api) end
        else
            for _i, k in ipairs(TOKEN_FIELDS) do if res.tokens[k] ~= nil then store[k] = res.tokens[k] end end
            if job.api.on_change then pcall(job.api.on_change) end
        end
    end
    if res.tokens then
        -- (saved above: the file the background process kept them in can go)
        if job.api and job.api.dropPending then pcall(job.api.dropPending) end
    elseif job.api and job.api.store and job.api.recoverPending then
        -- No tokens came back: the request was stopped (it took too long) or
        -- failed after the login was renewed. Grimmory has already cancelled
        -- the old login, so the new one, kept on disk by the background
        -- process, must be taken, not thrown away (it was until 1.23.7: a
        -- slow request after a renewal signed you out).
        local ok, took = pcall(job.api.recoverPending, job.api.store)
        if ok and took then
            Log.info("Grimmory login: kept the one a stopped background request got")
            if job.api.on_change then pcall(job.api.on_change) end
        end
    end
    local ok, err = pcall(job.on_done, unpack(res, 1, res.n))
    if not ok then Log.warn("async callback failed:", tostring(err)) end
end

--- A background process is done (all its jobs answered): the next one.
local function batchDone()
    Async.busy = false
    netHold(false)
    UIManager:nextTick(pump)
end

--- The jobs for the next background process: the first queued job and the
--- ones after it for the same login (up to BATCH_MAX), long ones (opts.nice)
--- last. One process instead of one each: one fork of GZreader, one login
--- check (and, later, one connection), on a Kindle 3 seconds each.
local function takeBatch()
    local first = table.remove(Async.queue, 1)
    if not first then return nil end
    local quick, long = { first }, {}
    if first.nice then quick, long = {}, { first } end
    local i = 1
    while Async.queue[i] and #quick + #long < Async.BATCH_MAX do
        local j = Async.queue[i]
        if j.api == first.api then
            table.remove(Async.queue, i)
            if j.nice then long[#long + 1] = j else quick[#quick + 1] = j end
        else
            i = i + 1
        end
    end
    for _i, j in ipairs(long) do quick[#quick + 1] = j end
    return quick
end

pump = function()
    if Async.busy or Async.held > 0 or Async.paused then return end
    local jobs = takeBatch()
    if not jobs then return end
    Async.busy = true
    local t0 = require("socket").gettime()
    netHold(true) -- Wi-Fi only when needed: not turned off mid-request
    local api = jobs[1].api or {} -- (nil: a request that needs no Grimmory login, e.g. Plex)
    local refresh_before = api.store and api.store.refresh_token
    local timeout = 0
    for _i, job in ipairs(jobs) do
        job.t0, job.refresh_before = t0, refresh_before
        timeout = timeout + (job.timeout or Async.TIMEOUT)
    end
    local pid, fd = ffiutil.runInSubProcess(function(_pid, wfd)
        Async.lowerPriority(Async.NICE) -- the screen goes first (see NICE)
        local store = api.store or {}
        local before = {}
        for _i, k in ipairs(TOKEN_FIELDS) do before[k] = store[k] end
        api.no_refresh = false
        api.on_change = function() end -- saved by the main process instead
        -- each job's result on its own line, as soon as it's ready
        local function send(res, last)
            local tokens
            for _i, k in ipairs(TOKEN_FIELDS) do
                if store[k] ~= before[k] then tokens = tokens or {}; tokens[k] = store[k] end
            end
            if tokens and store.refresh_token == nil then tokens = { cleared = true } end
            ffiutil.writeToFD(wfd, encode(res, tokens) .. "\n", last)
        end
        if api.ensureToken then
            local okt, err = api:ensureToken()
            if not okt then
                for i = 1, #jobs do send(pack(nil, err), i == #jobs) end
                return
            end
            -- a new login: on disk at once (see gzreader_api.lua, writePending)
            if store.refresh_token ~= before.refresh_token and api.writePending then
                pcall(api.writePending, store, before.refresh_token)
            end
        end
        local lowered = false
        for i, job in ipairs(jobs) do
            if job.nice and not lowered then
                lowered = true
                Async.lowerPriority(Async.NICE_LONG) -- long CPU work: lower still
            end
            local res = protected(job.fn, api)
            if api.writePending and store.refresh_token and store.refresh_token ~= before.refresh_token then
                pcall(api.writePending, store, before.refresh_token)
            end
            send(res, i == #jobs)
        end
    end, true)
    if not pid then
        -- couldn't fork (low memory?): give up rather than freeze the screen
        Log.warn("async: couldn't start a background process for", jobs[1].name or "?")
        for _i, job in ipairs(jobs) do finishJob(job, pack(nil, "busy")) end
        return batchDone()
    end
    if #jobs > 1 then
        local names = {}
        for i, job in ipairs(jobs) do names[i] = job.name or "?" end
        Log.info("async: one background process for", #jobs, "requests:", table.concat(names, ", "))
    end
    local run = { started = os.time() }
    Async.running[pid] = run
    local out = Async.reader(fd)
    local buf, next_job = "", 1
    -- the results that have arrived, each to its job
    local function dispatch(text)
        buf = buf .. text
        while true do
            local nl = buf:find("\n", 1, true)
            if not nl or next_job > #jobs then break end
            local line = buf:sub(1, nl - 1)
            buf = buf:sub(nl + 1)
            local job = jobs[next_job]
            next_job = next_job + 1
            finishJob(job, decode(line) or pack(nil, "background request failed"))
        end
    end
    local function rest(why)
        while next_job <= #jobs do
            local job = jobs[next_job]
            next_job = next_job + 1
            finishJob(job, pack(nil, why))
        end
    end
    local function poll()
        out:drain()
        dispatch(out:take())
        if not ffiutil.isSubProcessDone(pid) then
            if not Async.paused and os.time() - run.started > timeout then
                Async.running[pid] = nil
                Log.warn("async request took too long, stopped:", jobs[next_job] and jobs[next_job].name or "?")
                ffiutil.terminateSubProcess(pid)
                local function reap()
                    if ffiutil.isSubProcessDone(pid) then out:finish() else out:drain(); UIManager:scheduleIn(1, reap) end
                end
                UIManager:scheduleIn(1, reap)
                rest("timeout")
                return batchDone()
            end
            return UIManager:scheduleIn(Async.POLL, poll)
        end
        Async.running[pid] = nil
        dispatch(out:finish() .. "\n")
        rest("background request failed")
        batchDone()
    end
    UIManager:scheduleIn(Async.POLL, poll)
end

---------------------------------------------------------------- while a book opens

Async.running = {} -- pid -> { started = os.time() }: the background processes running now
Async.paused = nil -- { reason, at, count, timer }: while a book opens
Async.PAUSE_MAX = 30 -- s: carry on anyway (a book that never finished opening)

--- A signal to a background process and anything it started (its group;
--- the process itself too, in case it hasn't made its group yet).
local SIGSTOP, SIGCONT = 19, 18
local function signal(pid, sig)
    return pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        ffi.C.kill(pid, sig)
        ffi.C.kill(-pid, sig)
    end)
end

--- A book starts opening: pause the background processes running now, and
--- start no new request until Async.resume() (or PAUSE_MAX seconds).
function Async.pause(reason)
    if Async.sync or Async.paused then return end
    local p = { reason = reason or "?", at = os.time(), count = 0 }
    Async.paused = p
    for pid in pairs(Async.running) do
        signal(pid, SIGSTOP)
        p.count = p.count + 1
    end
    if p.count > 0 then Log.info("async: paused", p.count, "background process(es) while", p.reason) end
    p.timer = function() Async.resume("still not done after " .. Async.PAUSE_MAX .. " s") end
    UIManager:scheduleIn(Async.PAUSE_MAX, p.timer)
end

--- The book is open: the paused processes carry on (their time limits moved
--- on by the pause), and waiting requests start.
function Async.resume(why)
    local p = Async.paused
    if not p then return end
    Async.paused = nil
    UIManager:unschedule(p.timer)
    local paused_for = os.time() - p.at
    for pid, run in pairs(Async.running) do
        run.started = run.started + paused_for
        signal(pid, SIGCONT)
    end
    if p.count > 0 then Log.info("async: resumed after", paused_for, "s", why and ("(" .. why .. ")") or "") end
    UIManager:nextTick(pump)
end

--- Run fn(api) in the background; on_done(...) gets what it returned.
--- opts.nice: lower the process's priority (long conversions); opts.timeout (s).
function Async.run(api, fn, on_done, name, opts)
    on_done = on_done or function() end
    if api and api.offline and not Async.sync and not (opts and opts.nice) then
        -- the library copy (gzreader_offlineapi.lua): files, no network; here, a moment later
        return UIManager:nextTick(function()
            local res = protected(fn, api)
            on_done(unpack(res, 1, res.n))
        end)
    end
    if Async.sync then
        if api and api.ensureToken then
            local okt, err = api:ensureToken()
            if not okt then return on_done(nil, err) end
        end
        local res = protected(fn, api)
        return on_done(unpack(res, 1, res.n))
    end
    table.insert(Async.queue, { api = api, fn = fn, on_done = on_done, name = name, nice = opts and opts.nice,
        timeout = opts and opts.timeout })
    pump()
end

--- Run fn(); the requests it starts wait until it's done and then go in one
--- background process (when they're for the same login), e.g. a book's sync
--- when it opens: its place, queued updates, bookmarks and highlights.
function Async.together(fn)
    Async.held = Async.held + 1
    local ok, err = pcall(fn)
    Async.held = Async.held - 1
    pump()
    if not ok then error(err, 0) end
end

--- Local work (no network, no login) in its own background process, outside
--- the request queue so a long job doesn't hold up syncing. Lowest priority.
--- on_done(...) gets what fn() returned, or nil, "timeout"/"busy"/an error.
Async.local_jobs = 0
function Async.background(fn, on_done, name, opts)
    on_done = on_done or function() end
    opts = opts or {}
    if Async.sync then
        local res = protected(fn)
        return on_done(unpack(res, 1, res.n))
    end
    if Async.local_jobs >= 1 then return on_done(nil, "busy") end -- one at a time: memory on a Kindle 3
    local pid, fd = ffiutil.runInSubProcess(function(_pid, wfd)
        Async.lowerPriority(19)
        ffiutil.writeToFD(wfd, encode(protected(fn)), true)
    end, true)
    if not pid then
        Log.warn("async: couldn't start a background process for", name or "?")
        return on_done(nil, "busy")
    end
    Async.local_jobs = Async.local_jobs + 1
    local run = { started = os.time() }
    Async.running[pid] = run
    if Async.paused then signal(pid, SIGSTOP) end -- (it waits for the book too)
    local function done(...)
        Async.running[pid] = nil
        Async.local_jobs = Async.local_jobs - 1
        local ok, err = pcall(on_done, ...)
        if not ok then Log.warn("async callback failed:", tostring(err)) end
    end
    local out = Async.reader(fd)
    local function poll()
        out:drain()
        if not ffiutil.isSubProcessDone(pid) then
            if not Async.paused and os.time() - run.started > (opts.timeout or 600) then
                Log.warn("background job took too long, stopped:", name or "?")
                ffiutil.terminateSubProcess(pid)
                local function reap()
                    if ffiutil.isSubProcessDone(pid) then out:finish() else out:drain(); UIManager:scheduleIn(1, reap) end
                end
                UIManager:scheduleIn(1, reap)
                return done(nil, "timeout")
            end
            return UIManager:scheduleIn(1, poll)
        end
        local res = decode(out:finish()) or pack(nil, "background job failed")
        done(unpack(res, 1, res.n))
    end
    UIManager:scheduleIn(1, poll)
end

--- A valid login for a process forked outside this queue (downloads, the
--- library index): refreshed in the background if needed, then cb(ok, err).
function Async.ensureToken(api, cb)
    local store = api.store or {}
    if store.access_token and os.time() < (store.access_expires_at or 0) - 120 then return cb(true) end
    Async.run(api, function() return true end, function(ok, err) cb(ok == true, err) end, "refresh login")
end

--- Shortcut: api:method(...) in the background.
function Async.call(api, method, args, on_done)
    args = args or {}
    return Async.run(api, function(a) return a[method](a, unpack(args)) end, on_done, method)
end

return Async
