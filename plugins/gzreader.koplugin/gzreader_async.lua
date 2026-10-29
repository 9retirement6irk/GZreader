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
local JSON = require("json")
local Log = require("gzreader_log")

local Async = {
    sync = false,
    POLL = 0.2,
    TIMEOUT = 120,
    queue = {},
    busy = false,
}

local function pack(...) return { n = select("#", ...), ... } end

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
    netHold(false)
    if res.tokens and job.api and job.api.store then
        -- the login was refreshed in the background process: keep the new tokens
        local store = job.api.store
        if res.tokens.cleared then
            pcall(job.api.clearTokens, job.api)
        else
            for _i, k in ipairs(TOKEN_FIELDS) do if res.tokens[k] ~= nil then store[k] = res.tokens[k] end end
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
    netHold(true) -- Wi-Fi only when needed: not turned off mid-request
    local api = job.api
    local pid, fd = ffiutil.runInSubProcess(function(_pid, wfd)
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
        end
        local res = protected(job.fn, api)
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
    if job.nice then -- long CPU work: let the screen go first
        os.execute(string.format("renice -n 10 -p %d >/dev/null 2>&1 || renice 10 %d >/dev/null 2>&1", pid, pid))
    end
    local started = os.time()
    local function poll()
        if not ffiutil.isSubProcessDone(pid) then
            if os.time() - started > (job.timeout or Async.TIMEOUT) then
                Log.warn("async request took too long, stopped:", job.name or "?")
                ffiutil.terminateSubProcess(pid)
                local function reap()
                    if ffiutil.isSubProcessDone(pid) then ffiutil.readAllFromFD(fd) else UIManager:scheduleIn(1, reap) end
                end
                UIManager:scheduleIn(1, reap)
                return finish(job, pack(nil, "timeout"))
            end
            return UIManager:scheduleIn(Async.POLL, poll)
        end
        local res = decode(ffiutil.readAllFromFD(fd)) or pack(nil, "background request failed")
        finish(job, res)
    end
    UIManager:scheduleIn(Async.POLL, poll)
end

--- Run fn(api) in the background; on_done(...) gets what it returned.
--- opts.nice: lower the process's priority (long conversions); opts.timeout (s).
function Async.run(api, fn, on_done, name, opts)
    on_done = on_done or function() end
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
