-- The Kindle Scribe's pen mode (gzreader_penmode.lua): which updates a run
-- of ink is sent as, and that pen mode is on for ink and off before any
-- ordinary update of the screen (the driver's rule: the two never together).
--   luajit penmode_test.lua <gzreader.koplugin>
local PLUGIN = arg[1]
package.path = PLUGIN .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local PenMode = require("gzreader_penmode")

print("== the updates a run of ink is sent as")
;(function()
    local function areas(list) local t = {}; for _i, r in ipairs(list) do t[#t + 1] = r.w .. "x" .. r.h .. "@" .. r.x .. "," .. r.y end; return table.concat(t, " ") end
    -- a slow line: small steps, all in one small update
    local slow = {}
    for i = 0, 5 do slow[#slow + 1] = { x = 100 + i * 4, y = 200, w = 12, h = 12 } end
    local s1 = PenMode.split(slow)
    check(#s1 == 1 and s1[1].x == 100 and s1[1].w == 32 and s1[1].h == 12, "a slow line's steps: one small update (" .. areas(s1) .. ")")
    -- a quick diagonal: its steps together would be a big square; kept as updates under the driver's limit
    local quick = {}
    for i = 0, 9 do quick[#quick + 1] = { x = 100 + i * 40, y = 100 + i * 40, w = 50, h = 50 } end
    local s2 = PenMode.split(quick)
    local worst, covered = 0, true
    for _i, r in ipairs(s2) do worst = math.max(worst, r.w * r.h) end
    for _i, q in ipairs(quick) do
        local inside = false
        for _j, r in ipairs(s2) do
            if q.x >= r.x and q.y >= r.y and q.x + q.w <= r.x + r.w and q.y + q.h <= r.y + r.h then inside = true end
        end
        covered = covered and inside
    end
    check(#s2 > 1 and #s2 <= #quick and worst < PenMode.MAX_AREA and covered,
        "a quick diagonal: several updates, each under " .. PenMode.MAX_AREA .. " pixels (the driver's quick path), every step in one (" .. #s2 .. ", at most " .. worst .. ")")
    -- one piece too big on its own (a broad marker's long step): cut into strips
    local s3 = PenMode.split({ { x = 10, y = 20, w = 400, h = 40 } })
    local total, big = 0, 0
    for _i, r in ipairs(s3) do total = total + r.w * r.h; big = math.max(big, r.w * r.h) end
    check(#s3 >= 3 and total == 400 * 40 and big < PenMode.MAX_AREA and s3[1].x == 10 and s3[#s3].x + s3[#s3].w == 410,
        "a piece over the limit on its own: cut into strips that cover it exactly (" .. areas(s3) .. ")")
    check(#PenMode.split({}) == 0 and #PenMode.split({ { x = 1, y = 1, w = 0, h = 5 } }) == 0, "nothing to show: no update")
end)()

print("== pen mode on for ink, off before anything else")
;(function()
    local log = {}
    local clock = 100
    PenMode.now = function() return clock end
    PenMode.sleep = function(s) log[#log + 1] = string.format("sleep %.2f", s); clock = clock + s end
    PenMode.wait = function() log[#log + 1] = "wait" end
    PenMode.send = function(_screen, mode) log[#log + 1] = mode == 1 and "on" or "off"; return 0 end
    local screen = { fd = 3, marker = 41, dont_wait_for_marker = 7 }
    for _i, name in ipairs({ "refreshUIImp", "refreshPartialImp", "refreshFullImp", "refreshA2Imp" }) do
        screen[name] = function() log[#log + 1] = name end
    end
    screen.refreshFastImp = function(_s, x, y, w, h) log[#log + 1] = "fast " .. w .. "x" .. h end
    screen.refreshFast = function(s, x, y, w, h) return s:refreshFastImp(x, y, w, h) end
    local own_ui = screen.refreshUIImp
    local ui = { setDirty = function() log[#log + 1] = "dirty" end, _repaint = function() log[#log + 1] = "repaint" end }
    local real_dirty, real_repaint = ui.setDirty, ui._repaint
    PenMode.hook(screen, ui)
    local function seq() local t = table.concat(log, ","); log = {}; return t end

    -- ink right after the screen opened (it was just drawn: an ordinary update): waited for, then on
    check(PenMode.ink(screen, { { x = 10, y = 10, w = 20, h = 20 } }) == true and seq() == "wait,on,fast 20x20" and PenMode.on,
        "the first ink: the screen's last ordinary update waited for, pen mode on, the ink sent at once")
    clock = clock + 0.01
    check(PenMode.ink(screen, { { x = 30, y = 10, w = 20, h = 20 } }) == true and seq() == "fast 20x20",
        "more ink: sent, nothing else")
    -- the toolbar is refreshed 50 ms after the last ink: pen mode off first, once the ink has had its time
    clock = clock + 0.05
    screen:refreshUIImp(0, 0, 100, 100)
    check(seq() == "sleep 0.25,off,refreshUIImp" and not PenMode.on,
        "an ordinary update 50 ms after ink: waits the rest of the ink's time, pen mode off, then the update")
    check(screen.dont_wait_for_marker == 41, "…and KOReader won't wait on the last ink update's marker before it (the driver may not track ink sent in pen mode)")
    screen:refreshUIImp(0, 0, 100, 100)
    check(seq() == "refreshUIImp", "another ordinary update: just sent")
    -- ink again: the ordinary update waited for
    check(PenMode.ink(screen, { { x = 10, y = 10, w = 20, h = 20 } }) and seq() == "wait,on,fast 20x20", "ink again: waited for the ordinary update, on again")
    -- a long pause, then an ordinary update: no wait
    clock = clock + 2
    screen:refreshPartialImp(0, 0, 10, 10)
    check(seq() == "off,refreshPartialImp", "an ordinary update long after the ink: pen mode off at once, no wait")
    -- ink long after that ordinary update: it has finished, the driver isn't asked
    clock = clock + 3
    check(PenMode.ink(screen, { { x = 10, y = 10, w = 20, h = 20 } }) and seq() == "on,fast 20x20", "ink long after the last ordinary update: on at once, nothing to wait for")
    clock = clock + 2
    screen:refreshUIImp(0, 0, 10, 10)
    seq()
    -- an update asked for but not sent yet (setDirty before the repaint): ink the ordinary way meanwhile
    ui:setDirty({}, "ui")
    check(PenMode.queued and PenMode.ink(screen, { { x = 1, y = 1, w = 5, h = 5 } }) == false and seq() == "dirty",
        "something waiting to be repainted: ink isn't sent in pen mode ahead of it (the caller shows it the ordinary way)")
    ui:_repaint()
    check(not PenMode.queued and seq() == "repaint" and PenMode.ink(screen, { { x = 1, y = 1, w = 5, h = 5 } }) == true, "…after the repaint: pen mode again")
    seq()
    -- closing: off, the screen's and the UI's own methods back
    clock = clock + 5
    local stats = PenMode.unhook()
    check(seq() == "off" and rawget(screen, "refreshUIImp") == own_ui and ui.setDirty == real_dirty and ui._repaint == real_repaint and not PenMode.hooked,
        "closed: pen mode off, the screen's and the UI's methods as they were")
    check(stats and stats.entered == 4 and stats.updates == 5 and stats.runs == 5 and math.abs((stats.waited_after or 0) - 0.25) < 1e-6,
        "its numbers for the log: on 4 times, 5 updates, 0.25 s waited after ink")
    -- the driver refuses (another Kindle, older firmware): never tried again, ink the ordinary way
    PenMode.send = function() log[#log + 1] = "try"; return nil, "ioctl -1 errno 22" end
    PenMode.hook(screen, ui)
    local r1 = PenMode.ink(screen, { { x = 1, y = 1, w = 5, h = 5 } })
    local r2 = PenMode.ink(screen, { { x = 1, y = 1, w = 5, h = 5 } })
    check(r1 == false and r2 == false and seq() == "wait,try" and PenMode.failed == "ioctl -1 errno 22" and not PenMode.on,
        "the driver refuses: said why, not tried again, nothing sent in pen mode")
    check(PenMode.supported({ isKindle = function() return true end, isMTK = function() return true end, input = { pen_slot = 4 } }) == false,
        "…and not used again this session")
    PenMode.unhook()
    PenMode.failed = nil
    local scribe = { isKindle = function() return true end, isMTK = function() return true end, input = { pen_slot = 4 } }
    local pw = { isKindle = function() return true end, isMTK = function() return true end, input = {} }
    local old = { isKindle = function() return true end, isMTK = function() return false end, input = { pen_slot = 4 } }
    check(PenMode.capable(scribe) and PenMode.supported(scribe) and not PenMode.capable(pw) and not PenMode.capable(old) and not PenMode.capable(nil),
        "a Kindle with the MTK display driver and a pen (the Scribe): yes; one without a pen, or another driver: no")
    G_reader_settings = { isFalse = function(_s, k) return k == PenMode.SETTING end }
    check(PenMode.capable(scribe) and not PenMode.supported(scribe), "turned off by hand: not used")
    G_reader_settings = nil
    check(PenMode.IOCTL == 0x4004464C and PenMode.ON == 1 and PenMode.OFF == 0, "the driver's call: _IOW('F', 0x4C, uint32_t), 1 on, 0 off (FBInk's MXCFB_SET_STYLUS_MODE)")
end)()

print(string.format("pen mode: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
