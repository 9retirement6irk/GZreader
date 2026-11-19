--[[--
A safety net under every timer: KOReader's round of scheduled work
(UIManager:_checkTasks), with three limits.

Everything on a timer goes through that round: GZreader's own (the drawing
screen's ink and keeping, the daily paper, audiobooks and music, Wi-Fi,
calendar sync, the watchdog's heartbeat, auto light…) and KOReader's (its
sleep timer, the reader's). KOReader runs every task that's due, and every
task those schedule for "now", before it looks at the screen again. On
2026-11-18 a Kindle Scribe ran one such round for almost a minute (the log:
"scheduled work took 4 s … 6 s … 14 s … 28 s … 55 s", the slowest task
KOReader's AutoSuspend timer): no pen stroke, tap or key was looked at, the
screen stopped answering and GZreader had to restart.

1. **A round has a budget** (`BUDGET` seconds). Once it's spent, the tasks
   still due wait for the next round, after KOReader has looked at the touch
   screen, the pen and the keys. A runaway timer makes the Kindle slow, not
   frozen, and a tap still gets through.
2. **A task that keeps coming back at once** (run `RUNAWAY` times in one
   round: it schedules itself with no delay, over and over) is put off by
   `PUT_OFF` seconds each time after that, and logged once with where it is.
3. **One of GZreader's own tasks that fails** is logged with its traceback
   (and a debug report, when they're on) and the round goes on, so a fault in
   one feature (say, the daily paper's) doesn't take all of GZreader down.
   KOReader's own tasks fail as they always did.

The steps are KOReader's own UIManager:_checkTasks (frontend/ui/uimanager.lua),
with the limits added. `Safe.slowest` is the round's slowest task, for the
slow-operation log (gzreader_slowtrace.lua).
]]

local Safe = {
    BUDGET = 0.5, -- (s) of scheduled work before the screen and the pen get a turn
    RUNAWAY = 200, -- runs of one task in one round: it keeps scheduling itself at once
    PUT_OFF = 1, -- (s) a runaway task is put off by, each time
    REPORT_EVERY = 600, -- (s) at most one debug report of a failing task this often
    installed = false,
    failures = 0,
    slowest = nil, -- { action, took (fts) } of the last round
}

local unpack = unpack or table.unpack

--- Where function `fn` is ("plugins/gzreader.koplugin/gzreader_paper.lua:120"), and
--- whether it's GZreader's (its own tasks fail on their own).
local where_cache = setmetatable({}, { __mode = "k" })
function Safe.where(fn)
    local w = where_cache[fn]
    if w then return w[1], w[2] end
    local info = type(fn) == "function" and debug.getinfo(fn, "S") or {}
    local src = tostring(info.short_src or info.source or "?"):gsub("^@", "")
    local text = src .. ":" .. tostring(info.linedefined or "?")
    local ours = (info.source or ""):find("gzreader", 1, true) ~= nil
    where_cache[fn] = { text, ours }
    return text, ours
end

local reported_at = 0
local warned = {}

--- One of GZreader's tasks raised `err`: logged, reported (at most every REPORT_EVERY s).
function Safe.failed(action, err, trace)
    Safe.failures = Safe.failures + 1
    local where = Safe.where(action)
    local ok, Log = pcall(require, "gzreader_log")
    if ok then Log.warn("a timer's task failed (the rest go on):", where, tostring(err), trace and ("\n" .. trace) or "") end
    local now = os.time()
    if now - reported_at >= Safe.REPORT_EVERY then
        reported_at = now
        pcall(function()
            local R = require("gzreader_remote")
            if R.on and R.event then
                R.event("A timer's task failed", string.format("%s\n%s\n\n%s", where, tostring(err), tostring(trace or "")), { "task" }, true)
            end
        end)
    end
end

--- A task that kept scheduling itself at once: logged once a run.
local function runaway(action)
    local where = Safe.where(action)
    if warned[where] then return end
    warned[where] = true
    local ok, Log = pcall(require, "gzreader_log")
    if ok then
        Log.warn(string.format("a timer's task keeps coming back at once (%d times in one round): put off by %d s each time:",
            Safe.RUNAWAY, Safe.PUT_OFF), where)
    end
end

--- KOReader's round of scheduled work, with the limits above. `UI` is UIManager;
--- `now_fn` and `clock` (time.now, its seconds) are passed in by the tests.
function Safe.checkTasks(UI, now_fn, to_s)
    local time = require("ui/time")
    now_fn, to_s = now_fn or time.now, to_s or time.to_s
    UI._now = now_fn()
    local started = UI._now
    local wait_until
    local runs = {}
    local slowest, slowest_took
    UI._task_queue_dirty = false
    while UI._task_queue[1] do
        local task_time = UI._task_queue[#UI._task_queue].time
        if task_time > UI._now then
            wait_until = task_time
            break
        end
        -- the budget spent: what's still due waits until the screen and the pen have had a turn
        local spent = now_fn() - started
        if to_s(spent) >= Safe.BUDGET then
            Safe.cut = (Safe.cut or 0) + 1
            wait_until = UI._now -- (due already: KOReader polls input without waiting, then runs them)
            UI._task_queue_dirty = false
            break
        end
        local task = table.remove(UI._task_queue)
        local action = task.action
        local n = (runs[action] or 0) + 1
        runs[action] = n
        if n > Safe.RUNAWAY then
            -- (it came back at once RUNAWAY times: later, not now)
            runaway(action)
            UI:schedule(UI._now + time.s(Safe.PUT_OFF), action, unpack(task.args, 1, task.args.n))
        else
            local w = now_fn()
            local ours = select(2, Safe.where(action))
            if ours then
                local trace
                local ok, err = xpcall(function() return action(unpack(task.args, 1, task.args.n)) end,
                    function(e) trace = debug.traceback("", 2); return e end)
                if not ok then Safe.failed(action, err, trace) end
            else
                action(unpack(task.args, 1, task.args.n))
            end
            local took = now_fn() - w
            if not slowest_took or took > slowest_took then slowest, slowest_took = action, took end
        end
    end
    Safe.slowest = slowest and { slowest, slowest_took } or nil
    return wait_until, UI._now
end

--- Puts the net under UIManager's rounds (once).
function Safe.install()
    if Safe.installed then return end
    local UIManager = require("ui/uimanager")
    if type(UIManager._checkTasks) ~= "function" or type(UIManager._task_queue) ~= "table" then return end
    Safe.installed = true
    Safe.orig = UIManager._checkTasks
    UIManager._checkTasks = function(self)
        if type(self._task_queue) ~= "table" then return Safe.orig(self) end
        return Safe.checkTasks(self)
    end
end

return Safe
