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
- Results travel back as JSON (plain values only).
- `Async.sync = true` runs everything inline (tests; and where a result is
  needed right away, e.g. while going to sleep).
]]

local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local JSON = require("gzreader_json")
local Log = require("gzreader_log")

local Async = {
    sync = false,
    POLL = 0.2,
    TIMEOUT = 120,
    queue = {},
    busy = false,
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

local function finish(job, res)
    Async.busy = false
    pcall(function()
        require("gzreader_usage").request(job.name, res[1] ~= nil and res[1] ~= false,
            job.t0 and math.floor((require("socket").gettime() - job.t0) * 1000) or nil)
    end)
    netHold(false)
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
    UIManager:nextTick(pump)
end

pump = function()
    if Async.busy then return end
    local job = table.remove(Async.queue, 1)
    if not job then return end
    Async.busy = true
    job.t0 = require("socket").gettime()
    netHold(true) -- Wi-Fi only when needed: not turned off mid-request
    local api = job.api or {} -- (nil: a request that needs no Grimmory login, e.g. Plex)
    job.refresh_before = api.store and api.store.refresh_token
    local nice = job.nice
    local pid, fd = ffiutil.runInSubProcess(function(_pid, wfd)
        if nice then Async.lowerPriority(10) end -- long CPU work: let the screen go first
        local store = api.store or {}
        local before = {}
        for _i, k in ipairs(TOKEN_FIELDS) do before[k] = store[k] end
        api.no_refresh = false
        api.on_change = function() end -- saved by the main process instead
        if api.ensureToken then
            local okt, err = api:ensureToken()
            if not okt then
                local tokens = (store.refresh_token == nil and before.refresh_token ~= nil) and { cleared = true } or nil
                ffiutil.writeToFD(wfd, encode(pack(nil, err), tokens), true)
                return
            end
            -- a new login: on disk at once (see gzreader_api.lua, writePending)
            if store.refresh_token ~= before.refresh_token and api.writePending then
                pcall(api.writePending, store, before.refresh_token)
            end
        end
        local res = protected(job.fn, api)
        if api.writePending and store.refresh_token and store.refresh_token ~= before.refresh_token then
            pcall(api.writePending, store, before.refresh_token)
        end
        local tokens
        for _i, k in ipairs(TOKEN_FIELDS) do
            if store[k] ~= before[k] then tokens = tokens or {}; tokens[k] = store[k] end
        end
        if tokens and store.refresh_token == nil then tokens = { cleared = true } end
        ffiutil.writeToFD(wfd, encode(res, tokens), true)
    end, true)
    if not pid then
        -- couldn't fork (low memory?): give up rather than freeze the screen
        Log.warn("async: couldn't start a background process for", job.name or "?")
        return finish(job, pack(nil, "busy"))
    end
    local started = os.time()
    local out = Async.reader(fd)
    local function poll()
        out:drain()
        if not ffiutil.isSubProcessDone(pid) then
            if os.time() - started > (job.timeout or Async.TIMEOUT) then
                Log.warn("async request took too long, stopped:", job.name or "?")
                ffiutil.terminateSubProcess(pid)
                local function reap()
                    if ffiutil.isSubProcessDone(pid) then out:finish() else out:drain(); UIManager:scheduleIn(1, reap) end
                end
                UIManager:scheduleIn(1, reap)
                return finish(job, pack(nil, "timeout"))
            end
            return UIManager:scheduleIn(Async.POLL, poll)
        end
        local res = decode(out:finish()) or pack(nil, "background request failed")
        finish(job, res)
    end
    UIManager:scheduleIn(Async.POLL, poll)
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
    local started = os.time()
    local function done(...)
        Async.local_jobs = Async.local_jobs - 1
        local ok, err = pcall(on_done, ...)
        if not ok then Log.warn("async callback failed:", tostring(err)) end
    end
    local out = Async.reader(fd)
    local function poll()
        out:drain()
        if not ffiutil.isSubProcessDone(pid) then
            if os.time() - started > (opts.timeout or 600) then
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
