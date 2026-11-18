-- KOReader's gesture detector (the real frontend/device/gesturedetector.lua):
-- a two-finger tap whose other contact has no first event recorded. On a
-- Kindle Scribe (2026-11-17, reading) that ended GZreader:
--   gesturedetector.lua:295: attempt to index field 'initial_tev' (a nil value)
-- With the fix it isn't a two-finger tap, and nothing breaks.
--   luajit twofinger_test.lua <repo> <koreader base>
local REPO, KO = arg[1], arg[2]
package.path = REPO .. "/frontend/?.lua;" .. KO .. "/?.lua;" .. package.path
G_reader_settings = setmetatable({}, { __index = function() return function() return nil end end })

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
package.preload["logger"] = function()
    local l = {}
    for _i, k in ipairs({ "dbg", "info", "warn", "err" }) do l[k] = function() end end
    return l
end
package.preload["util"] = function() return { tableDeepCopy = function(x) local o = {} for k, v in pairs(x) do o[k] = v end return o end } end
package.preload["dbg"] = function() return { guard = function() end, dassert = function() end, is_on = false } end

local GD = require("device/gesturedetector")
local timeouts = 0
local gd = GD:new{
    screen = { scaleByDPI = function(_s, v) return v end, getWidth = function() return 1860 end, getHeight = function() return 2480 end },
    input = { main_finger_slot = 0, setTimeout = function() timeouts = timeouts + 1 end, clearTimeout = function() end },
}
local t = 1000
local function tev(slot, id, x, y)
    t = t + 0.02
    local sec = math.floor(t)
    return { slot = slot, id = id, x = x, y = y, timev = require("ui/time").timeval({ sec = sec, usec = math.floor((t - sec) * 1e6) }) }
end
-- two fingers down
local a, b = tev(0, 1, 500, 800), tev(1, 2, 560, 820)
gd:feedEvent({ a })
gd:feedEvent({ b })
local ca, cb = gd:getContact(0), gd:getContact(1)
check(ca and cb and ca.buddy_contact == cb and cb.initial_tev, "two contacts, buddies")
-- the other contact without its first event (as the Scribe's pen and palm left one)
cb.initial_tev = nil
a.id = -1
local ok, err = pcall(gd.feedEvent, gd, { a })
check(ok, "a lift with a buddy that has no first event: no error " .. tostring(err))
-- an ordinary two-finger tap still works
gd:dropContacts()
local c, d = tev(0, 3, 500, 800), tev(1, 4, 540, 810)
gd:feedEvent({ c })
gd:feedEvent({ d })
c.id = -1
local g1 = gd:feedEvent({ c })
d.id = -1
local g2 = gd:feedEvent({ d })
local names = {}
for _i, g in ipairs(g1) do names[#names + 1] = g.ges end
for _i, g in ipairs(g2) do names[#names + 1] = g.ges end
check(table.concat(names, ","):find("two_finger_tap", 1, true), "an ordinary two-finger tap: still two_finger_tap (" .. table.concat(names, ",") .. ")")
print(string.format("two-finger tap: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
