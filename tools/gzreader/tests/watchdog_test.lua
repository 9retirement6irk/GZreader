-- The watchdog (gzreader_watchdog.lua, its own process), run for real with
-- short times: no freeze report when the Kindle wakes up (its last beat is
-- from before it slept), a real freeze still reported. The Kindle's sleep is
-- the watchdog stopped (SIGSTOP) and continued: on a Kindle everything stops.
--   luajit watchdog_test.lua <gzreader.koplugin> <work dir>
local PLUGIN, WORK = arg[1], arg[2]
local ffi = require("ffi")
ffi.cdef("int getpid(void);")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function sh(cmd) local p = io.popen(cmd); local s = p:read("*a"); p:close(); return s end
local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function wait(s) os.execute("sleep " .. s) end

local dir = WORK .. "/watchdog"
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "/spool'")
-- (no report address: what it would send stays in the spool, to be looked at)
write(dir .. "/config", "\nKindle\n")
local function beat(status, what) write(dir .. "/heartbeat", os.time() .. " " .. status .. " " .. what) end
local function reports()
    local names = {}
    for name in sh("ls '" .. dir .. "/spool'"):gmatch("[^\n]+") do
        local s = io.open(dir .. "/spool/" .. name, "rb"):read("*a")
        names[#names + 1] = (s:match('"eventName":"([^"(]+)') or name):gsub("%s+$", "")
    end
    return table.concat(names, ", ")
end
local function clear() os.execute("rm -f '" .. dir .. "/spool/'*") end

beat("run", "on Home")
local pid = tonumber(sh(string.format(
    "cd '%s' && GZ_WD_TICK=1 GZ_WD_STALL=4 GZ_WD_SLOW=100 luajit '%s/gzreader_watchdog.lua' '%s' %d >/dev/null 2>&1 & echo $!",
    dir, PLUGIN, dir, ffi.C.getpid())))
check(pid ~= nil, "the watchdog started")

print("== waking up")
;(function()
    -- the screensaver went up while GZreader still said "run", then the Kindle slept
    wait(2)
    beat("run", "on Home (ScreenSaver)")
    os.execute("kill -STOP " .. pid)
    wait(9) -- (more than 6 ticks: the watchdog sees it slept)
    os.execute("kill -CONT " .. pid)
    wait(1.5)
    beat("run", "on Home") -- GZreader's first beat after waking
    wait(3)
    check(reports() == "", "woken after a sleep: no \"unresponsive\" (GZreader's last beat was from before it slept): " .. reports())
end)()

print("== a real freeze")
;(function()
    clear()
    beat("run", "opening a book")
    wait(9) -- no beats: more than STALL
    local r = reports()
    check(r:find("Kindle unresponsive", 1, true) ~= nil, "no beats for longer than it allows: reported as unresponsive: " .. r)
    beat("run", "reading")
    wait(3)
    check(reports():find("Kindle responsive again", 1, true) ~= nil, "…and responsive again when it beats")
end)()

print("== a freeze right after waking")
;(function()
    clear()
    beat("run", "on Home (ScreenSaver)")
    os.execute("kill -STOP " .. pid)
    wait(9)
    os.execute("kill -CONT " .. pid)
    wait(9) -- woken, but no beat since
    check(reports():find("Kindle unresponsive", 1, true) ~= nil,
        "no beat for longer than it allows after waking: still reported (counted from waking): " .. reports())
end)()

beat("off", "")
wait(2)
os.execute("kill " .. pid .. " 2>/dev/null")
print(string.format("watchdog: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
