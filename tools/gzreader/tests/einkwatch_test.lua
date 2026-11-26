-- When the e-ink display stops finishing its updates (gzreader_einkwatch.lua):
-- slow updates logged with what they were; two in a row: pen mode off and a
-- full refresh, at most once a minute.
--   luajit einkwatch_test.lua <plugins/gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local warned = {}
package.loaded["gzreader_log"] = { info = function() end, warn = function(...) warned[#warned + 1] = table.concat({ ... }, " ") end }
local dirty, ticks = {}, 0
package.loaded["ui/uimanager"] = { nextTick = function(_s, f) ticks = ticks + 1; f() end,
    setDirty = function(_s, w, mode) dirty[#dirty + 1] = { w = w, mode = mode } end }
local sent = {}
package.loaded["gzreader_penmode"] = { capable = function() return true end, send = function(_s, mode) sent[#sent + 1] = mode; return 0 end }
package.loaded["device"] = {}
local W = require("gzreader_einkwatch")
local clock = 100
W.now = function() return clock end

print("== slow updates")
check(W.line("refreshUIImp", 10, 544, 1236, 880, 5.02, 0.01) == "display: an update took 5.0 s (UI, 1236x880 at 10,544; 0.0 s CPU): the display didn't say it was done"
    and W.line("refreshFullImp", nil, nil, nil, nil, 6, 0):find("the whole screen", 1, true), "the log line: how long, which kind, where, the CPU")
local took = 0
local calls = 0
local screen = { refreshUIImp = function(_fb, _x, _y, _w, _h) calls = calls + 1; clock = clock + took; return "done" end,
    refreshFullImp = function() clock = clock + took end }
check(W.install(screen) and not W.install(screen), "installed once")
took = 0.2
check(screen:refreshUIImp(0, 0, 10, 10) == "done" and calls == 1 and #warned == 0 and W.streak == 0, "a quick update: passed through, nothing logged")
took = 5
screen:refreshUIImp(0, 0, 10, 10)
check(#warned == 1 and warned[1]:find("an update took 5.0 s (UI, 10x10 at 0,0", 1, true) and #sent == 0 and #dirty == 0, "one slow update: logged with what it was")
took = 0.1
screen:refreshUIImp(0, 0, 10, 10)
took = 5
screen:refreshUIImp(0, 0, 10, 10)
check(#sent == 0 and W.streak == 1, "…a quick one between: the count starts again")
screen:refreshUIImp(0, 0, 10, 10)
check(#sent == 1 and sent[1] == 0 and #dirty == 1 and dirty[1].w == "all" and dirty[1].mode == "full" and W.resets == 1
    and warned[#warned]:find("pen mode off; the whole screen refreshed", 1, true), "two in a row: pen mode off, the whole screen refreshed")
screen:refreshUIImp(0, 0, 10, 10)
screen:refreshUIImp(0, 0, 10, 10)
check(W.resets == 1, "…not again within a minute")
clock = clock + 61
screen:refreshUIImp(0, 0, 10, 10)
check(W.resets == 2, "…again after a minute")
package.loaded["gzreader_penmode"].capable = function() return false end
clock = clock + 61
screen:refreshFullImp(); screen:refreshFullImp()
check(W.resets == 3 and #sent == 2 and warned[#warned]:find("not a pen Kindle", 1, true), "not a pen Kindle: only the full refresh")
local main = io.open(PLUGIN .. "/main.lua"):read("*a")
check(main:find('pcall(function() require("gzreader_einkwatch").install() end)', 1, true), "installed when GZreader starts")

print(string.format("display updates: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
