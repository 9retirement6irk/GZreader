--[[--
Find what makes GZreader slow (on with remote debugging).

- A sampling profiler (LuaJIT's jit.profile): while GZreader uses the CPU,
  every 50 ms of CPU time it notes which Lua code is running (3 frames) and
  whether it's running Lua, C code (e.g. crengine drawing a page), garbage
  collection or the JIT compiler. It costs very little and only runs while
  GZreader is actually busy (the timer counts CPU time, not clock time).
- The tally is written to <remote dir>/profile every ~5 s of CPU, also while
  GZreader is stuck in one long piece of work, so the watchdog's
  "unresponsive" report can say where it's stuck.
- Every keypress, round of scheduled work and screen repaint is timed; one
  that takes more than SLOW seconds is logged as a warning with the code that
  used the time.
- GZreader's own CPU use is measured every heartbeat; at 60% or more for a
  minute it sends a "busy" report with the profile (at most every 10 min).
]]

local Log = require("gzreader_log")

local S = { SLOW = 3, INTERVAL = 50, WRITE_EVERY = 100, BUSY_PCT = 60, BUSY_WINDOWS = 4, REPORT_EVERY = 600 }

local ok_prof, prof = pcall(require, "jit.profile")
S.available = ok_prof and type(prof) == "table" and prof.start ~= nil

local VM = { N = "JIT code", I = "Lua", C = "C code", G = "garbage collection", J = "JIT compiler" }

local total, window, event = {}, {}, nil
local samples_since_write, all_samples = 0, 0

local function add(t, key, n) t[key] = (t[key] or 0) + n end

local function top(t, n)
    local list, sum = {}, 0
    for k, v in pairs(t) do list[#list + 1] = { k, v }; sum = sum + v end
    table.sort(list, function(a, b) return a[2] > b[2] end)
    local out = {}
    for i = 1, math.min(n, #list) do
        out[#out + 1] = string.format("%3d%%  %s", math.floor(list[i][2] * 100 / math.max(sum, 1) + 0.5), list[i][1])
    end
    return table.concat(out, "\n"), sum
end
S.top = top

local function clean(stack)
    return (stack:gsub("[^;]*/plugins/", "plugins/"):gsub("[^;]*/frontend/", "frontend/"):gsub(";$", ""):gsub(";", " <- "))
end

local function writeProfile()
    if not S.file then return end
    local f = io.open(S.file .. ".tmp", "wb")
    if not f then return end
    local w = top(window, 12)
    local t = top(total, 12)
    f:write(os.date("%H:%M:%S"), " profile (share of CPU samples)\nLast few minutes:\n", w, "\n\nSince start:\n", t, "\n")
    f:close()
    os.rename(S.file .. ".tmp", S.file)
end

local function onSample(thread, samples, vmstate)
    if not S.profiling then return end
    local stack = clean(prof.dumpstack(thread, "pl;", 6))
    local key = (VM[vmstate] or vmstate) .. ": " .. stack
    add(total, key, samples)
    add(window, key, samples)
    if event then add(event, key, samples) end
    all_samples = all_samples + samples
    samples_since_write = samples_since_write + samples
    if samples_since_write >= S.WRITE_EVERY then
        samples_since_write = 0
        pcall(writeProfile)
    end
end

---------------------------------------------------------------- CPU use

local function cpuTicks()
    local f = io.open("/proc/self/stat", "rb")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    -- fields after the ")" of the command name: state is field 3; utime 14, stime 15
    local rest = s:match("%)%s+(.*)$") or ""
    local fields = {}
    for x in rest:gmatch("%S+") do fields[#fields + 1] = x end
    return (tonumber(fields[12]) or 0) + (tonumber(fields[13]) or 0)
end

local last_ticks, last_time, busy_windows, last_report = nil, nil, 0, 0

--- Called every heartbeat: CPU % since the last one; a "busy" report if needed.
function S.tick(report)
    local t, ticks = os.time(), cpuTicks()
    local pct
    if last_ticks and t > last_time then
        pct = math.floor((ticks - last_ticks) / (t - last_time) + 0.5) -- 100 ticks per second
    end
    last_ticks, last_time = ticks, t
    S.cpu = pct
    if not pct then return end
    if pct >= S.BUSY_PCT then busy_windows = busy_windows + 1 else busy_windows = 0 end
    if busy_windows >= S.BUSY_WINDOWS and t - last_report >= S.REPORT_EVERY and report then
        last_report = t
        local w = top(window, 12)
        report(string.format("GZreader has used %d%% of the CPU or more for %d s.\nWhere (share of samples):\n%s",
            S.BUSY_PCT, busy_windows * 15, w))
    end
    -- keep the window to the last few minutes
    if all_samples > 4000 then window = {}; all_samples = 0 end
end

---------------------------------------------------------------- slow operations

local depth = 0

local function memory()
    local f = io.open("/proc/self/status", "rb")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    local rss = tonumber(s:match("VmRSS:%s+(%d+)"))
    return rss and string.format("%d MB", math.floor(rss / 1024)) or "?"
end

-- No pcall here: an error keeps its full traceback for crash.log (1.2.1–1.2.4
-- caught and re-raised it, which cut the traceback off).
local t0, w0
local function done(what, ...)
    depth = 0
    local wall = os.time() - w0
    if wall >= S.SLOW then
        pcall(function() require("gzreader_usage").slow(what, wall) end)
        local cpu = os.clock() - t0
        local where = top(event or {}, 4)
        Log.warn(string.format("slow: %s took %d s (%.1f s CPU, memory %s)%s", what, wall, cpu, memory(),
            where ~= "" and (": " .. where:gsub("\n", " | ")) or ""))
    end
    event = nil
    return ...
end

local function timed(what, fn, ...)
    if depth > 0 then return fn(...) end
    depth = 1
    t0, w0 = os.clock(), os.time()
    event = S.profiling and {} or nil
    return done(what, fn(...))
end
S.timed = timed

---------------------------------------------------------------- re-layouts

--- Book layout changes (margins, styles, fonts…) make crengine lay the whole
--- book out again, which takes many seconds on a Kindle 3. Log who asks, and
--- warn when it happens often (that would make every page turn slow).
local relayouts = {}
local function watchRelayouts()
    local ok, CreDocument = pcall(require, "document/credocument")
    if not ok then return end
    for _i, name in ipairs({ "render", "setStyleSheet", "setPageMargins", "setFontSize", "setViewDimen",
            "setRenderDPI", "setEmbeddedStyleSheet", "setBlockRenderingFlags" }) do
        local orig = CreDocument[name]
        if type(orig) == "function" then
            CreDocument[name] = function(doc, ...)
                if type(doc) ~= "table" or not doc.been_rendered then return orig(doc, ...) end -- opening: expected
                local t = os.time()
                local who = debug.traceback("", 2):gsub("^%s*stack traceback:%s*", "")
                local lines = {}
                for line in who:gmatch("[^\n]+") do
                    line = line:gsub("^%s+", ""):gsub("^.-/plugins/", "plugins/"):gsub("^.-/frontend/", "frontend/")
                    if not line:match("gzreader_slowtrace") then lines[#lines + 1] = line end
                    if #lines >= 6 then break end
                end
                relayouts[#relayouts + 1] = { t = t, what = name, who = table.concat(lines, " <- ") }
                while relayouts[1] and t - relayouts[1].t > 60 do table.remove(relayouts, 1) end
                if #relayouts == 6 then -- many in a minute: say who
                    local out = {}
                    for _j, r in ipairs(relayouts) do out[#out + 1] = r.what .. " from " .. r.who end
                    Log.warn("book layout redone " .. #relayouts .. " times in a minute: " .. table.concat(out, " || "))
                end
                return orig(doc, ...)
            end
        end
    end
end

---------------------------------------------------------------- keys vs. screen

--- Keys that reach GZreader and screen updates, so a "frozen" screen can be
--- told apart: keys not arriving, keys arriving but the screen not changing,
--- or GZreader busy.
S.keys, S.last_key, S.last_paint = 0, nil, nil

function S.windows()
    local UIManager = require("ui/uimanager")
    local out = {}
    for i, w in ipairs(UIManager._window_stack or {}) do
        local wd = w.widget or {}
        local name = wd.name or wd.title or (type(wd.text) == "string" and wd.text:sub(1, 50)) or wd.id
        out[#out + 1] = tostring(name or "?"):gsub("[\n\r]", " ") .. (wd.modal and " (modal)" or "")
        if i > 8 then break end
    end
    return table.concat(out, " > ")
end

function S.uiState()
    local t = os.time()
    return string.format("%d keys, last key %s, screen last changed %s", S.keys,
        S.last_key and ((t - S.last_key) .. " s ago") or "never",
        S.last_paint and ((t - S.last_paint) .. " s ago") or "never")
end

local stuck_reported = 0
--- Keys pressed for 45 s with no screen change at all: report what's on screen.
function S.checkStuck(report)
    local t = os.time()
    if not (S.last_key and report) then return end
    local unanswered = S.last_key_first_unanswered
    if not unanswered or (S.last_paint and S.last_paint >= unanswered) then return end
    if t - unanswered < 45 or t - stuck_reported < 600 then return end
    stuck_reported = t
    pcall(function() require("gzreader_usage").stuck(t - unanswered, S.windows()) end)
    report(string.format("Keys were pressed for %d s but the screen didn't change (%s).\nOn screen: %s",
        t - unanswered, S.uiState(), S.windows()))
end

function S.install(dir, opts)
    if S.installed then return end
    S.installed = true
    opts = opts or {}
    S.file = dir and (dir .. "/profile")
    -- The sampling profiler (SIGPROF timer signals) only when asked for:
    -- Settings → General → Remote debugging → Detailed timing.
    if opts.profile and S.available then
        local okp, err = pcall(prof.start, "fi" .. S.INTERVAL, onSample)
        if okp then S.profiling = true else Log.warn("profiler unavailable:", tostring(err)) end
    end
    local UIManager = require("ui/uimanager")
    local orig_input = UIManager.handleInputEvent
    UIManager.handleInputEvent = function(self, ev)
        local t = os.time()
        if type(ev) == "table" and ev.handler == "onKeyPress" then
            S.keys = S.keys + 1
            S.last_key = t
            if not S.last_key_first_unanswered or (S.last_paint and S.last_paint >= S.last_key_first_unanswered) then
                S.last_key_first_unanswered = t
            end
        end
        return timed("a keypress", orig_input, self, ev)
    end
    local orig_tasks = UIManager._checkTasks
    UIManager._checkTasks = function(self) return timed("scheduled work", orig_tasks, self) end
    local orig_repaint = UIManager._repaint
    UIManager._repaint = function(self) return timed("a screen repaint", orig_repaint, self) end
    local okd, Device = pcall(require, "device")
    local Screen = okd and Device.screen
    if Screen and Screen.afterPaint then
        local orig_after = Screen.afterPaint
        Screen.afterPaint = function(...)
            S.last_paint = os.time()
            return orig_after(...)
        end
    end
    pcall(watchRelayouts)
    Log.info("slow-operation tracing on", S.profiling and "(with profiler)" or "(no profiler)")
end

return S
