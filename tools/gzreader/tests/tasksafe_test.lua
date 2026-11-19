-- The safety net under every timer (gzreader_tasksafe.lua): a round of
-- scheduled work has a budget, a task that keeps scheduling itself at once is
-- put off, and one of GZreader's tasks that fails stops alone.
--   luajit tasksafe_test.lua <gzreader.koplugin> <tests lib> <koreader base>
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
table.unpack = table.unpack or unpack
local PLUGIN, LIB, KOROOT = arg[1], arg[2], arg[3]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. KOROOT .. "/frontend/?.lua;" .. KOROOT .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local warnings = {}
package.preload["gzreader_log"] = function()
    return { warn = function(...) warnings[#warnings + 1] = table.concat({ ... }, " ") end, info = function() end }
end
package.preload["gzreader_remote"] = function() return { on = false } end

local time = require("ui/time")
local Safe = require("gzreader_tasksafe")

-- a UIManager's task queue, as KOReader keeps it (latest first; schedule() as KOReader's)
local function newUI()
    local UI = { _task_queue = {} }
    function UI:schedule(t, action, ...)
        local lo, hi = 1, #self._task_queue
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if self._task_queue[mid].time <= t then hi = mid - 1 else lo = mid + 1 end
        end
        table.insert(self._task_queue, lo, { time = t, action = action, args = table.pack(...) })
        self._task_queue_dirty = true
    end
    return UI
end
-- the clock: moved on by the tasks themselves (`spend`)
local clock = time.s(1000)
local function now() return clock end
local function spend(s) clock = clock + time.s(s) end

print("== an ordinary round")
do
    local UI, ran = newUI(), {}
    UI:schedule(clock, function() ran[#ran + 1] = "a" end)
    UI:schedule(clock, function() ran[#ran + 1] = "b"; UI:schedule(clock, function() ran[#ran + 1] = "c" end) end)
    local later = clock + time.s(5)
    UI:schedule(later, function() ran[#ran + 1] = "later" end)
    local wait = Safe.checkTasks(UI, now)
    check(table.concat(ran, ",") == "a,b,c" and wait == later and #UI._task_queue == 1,
        "every task due runs, those they schedule for now too, in order; the next one's time is returned (" .. table.concat(ran, ",") .. ")")
end

print("== a round has a budget")
do
    local UI, ran = newUI(), 0
    for _i = 1, 10 do UI:schedule(clock, function() ran = ran + 1; spend(0.2) end) end
    local start = clock
    local wait, at = Safe.checkTasks(UI, now)
    check(ran == 3 and #UI._task_queue == 7 and wait == at and at == start and UI._task_queue_dirty == false,
        "10 tasks of 0.2 s: 3 run (" .. Safe.BUDGET .. " s spent), the 7 others wait for the next round, after the screen and the pen (" .. ran .. ")")
    Safe.checkTasks(UI, now); Safe.checkTasks(UI, now); Safe.checkTasks(UI, now)
    check(ran == 10 and #UI._task_queue == 0, "…and run in the rounds after")
end

print("== a task that keeps scheduling itself at once")
do
    local UI, ran = newUI(), 0
    warnings = {}
    -- (as KOReader's AutoSuspend Kindle timer would with a stale idle time: scheduleIn of a negative delay)
    local function loop() ran = ran + 1; UI:schedule(clock - time.s(1), loop) end
    UI:schedule(clock, loop)
    local wait = Safe.checkTasks(UI, now)
    check(ran == Safe.RUNAWAY and #UI._task_queue == 1 and UI._task_queue[1].time >= clock + time.s(Safe.PUT_OFF) and wait == UI._task_queue[1].time,
        "it runs " .. Safe.RUNAWAY .. " times, then is put off by " .. Safe.PUT_OFF .. " s: the round ends (before: for ever)")
    check(#warnings == 1 and warnings[1]:find("keeps coming back", 1, true) and warnings[1]:find("tasksafe_test.lua", 1, true),
        "…logged once, with where it is")
    clock = clock + time.s(Safe.PUT_OFF)
    Safe.checkTasks(UI, now)
    check(ran == 2 * Safe.RUNAWAY and #warnings == 1, "…a second later it runs again (still not for ever), not logged again")
end

print("== one of GZreader's tasks that fails")
do
    local UI, ran = newUI(), {}
    warnings = {}
    -- (a function from a GZreader file: its source names gzreader)
    local ours = assert(load("return function() error('the daily paper broke') end", "@plugins/gzreader.koplugin/gzreader_paper.lua"))()
    UI:schedule(clock, function() ran[#ran + 1] = "before" end)
    UI:schedule(clock, ours)
    UI:schedule(clock, function() ran[#ran + 1] = "after" end)
    local before = Safe.failures
    local ok = pcall(Safe.checkTasks, UI, now)
    check(ok and table.concat(ran, ",") == "before,after" and Safe.failures == before + 1,
        "it stops alone: the tasks before and after it run (" .. table.concat(ran, ",") .. ")")
    check(#warnings == 1 and warnings[1]:find("gzreader_paper.lua", 1, true) and warnings[1]:find("the daily paper broke", 1, true)
        and warnings[1]:find("traceback", 1, true),
        "…logged with where it is, the error and its traceback")
    local theirs = assert(load("return function() error('KOReader broke') end", "@frontend/ui/widget/somewidget.lua"))()
    UI:schedule(clock, theirs)
    local ok2, err = pcall(Safe.checkTasks, UI, now)
    check(not ok2 and tostring(err):find("KOReader broke", 1, true), "KOReader's own tasks fail as they always did")
end

print("== the slowest task, for the slow-operation log")
do
    local UI = newUI()
    local quick = function() spend(0.01) end
    local slow = function() spend(0.3) end
    UI:schedule(clock, quick); UI:schedule(clock, slow); UI:schedule(clock, quick)
    Safe.checkTasks(UI, now)
    check(Safe.slowest and Safe.slowest[1] == slow and time.to_s(Safe.slowest[2]) > 0.29, "the round's slowest task noted")
end

print("== installed at start, under KOReader's own loop")
do
    local main = io.open(PLUGIN .. "/main.lua"):read("*a")
    local tr = io.open(PLUGIN .. "/gzreader_slowtrace.lua"):read("*a")
    local ek = io.open(PLUGIN .. "/gzreader_eink.lua"):read("*a")
    check(main:find('require("gzreader_tasksafe").install()', 1, true) ~= nil
        and main:find('gzreader_tasksafe', 1, true) < main:find('gzreader_opentiming', 1, true),
        "installed first thing at start")
    check(tr:find('local Safe = package.loaded["gzreader_tasksafe"]', 1, true) ~= nil, "the slow-operation log times the safe round (no second loop of its own)")
    check(ek:find('local okf, flash = pcall(Eink.flashesFor', 1, true) ~= nil and ek:find('local ok, m = pcall(function()', 1, true) ~= nil,
        "the e-ink refresh hooks: GZreader's part in a pcall, KOReader's call always made")
end

print(string.format("tasksafe: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
