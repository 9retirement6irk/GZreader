-- Pen Kindles (gzreader_peninput.lua): the pen and the touch screen kept
-- apart. KOReader's own input.lua (the real one) is fed what a Kindle Scribe
-- sends while the pen writes and a hand rests on the screen; the contacts it
-- hands on are checked without the fix (the owner's rectangles) and with it.
--   luajit peninput_test.lua <repo> <koreader base>
local REPO, KO = arg[1], arg[2]
package.path = REPO .. "/frontend/?.lua;" .. REPO .. "/plugins/gzreader.koplugin/?.lua;" .. KO .. "/?.lua;" .. package.path
G_reader_settings = setmetatable({}, { __index = function() return function() return nil end end })

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

package.preload["ffi/framebuffer"] = function()
    return { DEVICE_ROTATED_UPRIGHT = 0, DEVICE_ROTATED_CLOCKWISE = 1, DEVICE_ROTATED_UPSIDE_DOWN = 2, DEVICE_ROTATED_COUNTER_CLOCKWISE = 3 }
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp" end, getSettingsDir = function() return "/tmp/gz-peninput-none" end }
end
package.preload["dbg"] = function() return { guard = function() end, dassert = function() end, is_on = false } end
package.preload["logger"] = function()
    local l = {}
    for _i, k in ipairs({ "dbg", "info", "warn", "err" }) do l[k] = function() end end
    return l
end
package.preload["gettext"] = function() return function(s) return s end end
-- the gesture detector: keeps each frame's contacts as KOReader hands them on
package.preload["device/gesturedetector"] = function()
    return { new = function(_s, o)
        o.frames = {}
        o.feedEvent = function(self, slots)
            local f = {}
            for _i, s in ipairs(slots) do f[#f + 1] = { slot = s.slot, id = s.id, x = s.x, y = s.y, tool = s.tool, gz_pressure = s.gz_pressure } end
            self.frames[#self.frames + 1] = f
            return {}
        end
        o.adjustGesCoordinate = function(_self, g) return g end
        return o
    end }
end

local Input = require("device/input")
local PenInput = require("gzreader_peninput")

local function newInput()
    local dev = setmetatable({ screen = { getWidth = function() return 1860 end, getHeight = function() return 2480 end } },
        { __index = function() return function() return false end end })
    local inp = Input:new{ device = dev, input = {}, event_map = {} }
    inp.wacom_protocol = true -- (KindleScribe:init)
    return inp
end

local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
local ABS_X, ABS_Y, ABS_PRESSURE = 0, 1, 24
local ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
local BTN_TOOL_PEN, BTN_TOUCH, BTN_TOOL_FINGER = 320, 330, 325
local clock = 0
local function feed(inp, evs)
    clock = clock + 0.01
    local tv = { sec = math.floor(clock), usec = math.floor((clock % 1) * 1e6) }
    for _i, e in ipairs(evs) do
        local ev = { type = e[1], code = e[2], value = e[3], time = tv }
        if ev.type == EV_KEY then inp:handleKeyBoardEv(ev) else inp:handleTouchEv(ev) end
    end
    inp:handleTouchEv({ type = EV_SYN, code = 0, value = 0, time = tv })
end

-- the touch screen: a palm of `n` contacts in slots 0..n-1 near (px, py),
-- then its single-touch copy of the first (the kernel's pointer emulation)
local function palmDown(inp, n, px, py)
    local evs = {}
    for s = 0, n - 1 do
        evs[#evs + 1] = { EV_ABS, ABS_MT_SLOT, s }
        evs[#evs + 1] = { EV_ABS, ABS_MT_TRACKING_ID, 100 + s }
        evs[#evs + 1] = { EV_ABS, ABS_MT_X, px + 40 * s }
        evs[#evs + 1] = { EV_ABS, ABS_MT_Y, py + 25 * s }
    end
    evs[#evs + 1] = { EV_KEY, BTN_TOUCH, 1 }
    evs[#evs + 1] = { EV_KEY, BTN_TOOL_FINGER, 1 }
    evs[#evs + 1] = { EV_ABS, ABS_X, px }
    evs[#evs + 1] = { EV_ABS, ABS_Y, py }
    feed(inp, evs)
end
-- the palm shifting: only its last slot moves (no ABS_MT_SLOT: the kernel leaves it out)
local function palmShift(inp, n, px, py, d)
    feed(inp, { { EV_ABS, ABS_MT_X, px + 40 * (n - 1) + d }, { EV_ABS, ABS_MT_Y, py + 25 * (n - 1) + d } })
end
local function palmUp(inp, n)
    local evs = {}
    for s = 0, n - 1 do
        evs[#evs + 1] = { EV_ABS, ABS_MT_SLOT, s }
        evs[#evs + 1] = { EV_ABS, ABS_MT_TRACKING_ID, -1 }
    end
    evs[#evs + 1] = { EV_KEY, BTN_TOUCH, 0 }
    evs[#evs + 1] = { EV_KEY, BTN_TOOL_FINGER, 0 }
    feed(inp, evs)
end

-- the pen writes along y = 500 from x = 300 to 700 while a palm (6 contacts)
-- rests around (1200, 1800) and moves a little between the pen's frames
local function scenario(inp)
    feed(inp, { { EV_KEY, BTN_TOOL_PEN, 1 }, { EV_ABS, ABS_X, 300 }, { EV_ABS, ABS_Y, 500 }, { EV_ABS, ABS_PRESSURE, 0 } })
    palmDown(inp, 6, 1200, 1800)
    feed(inp, { { EV_ABS, ABS_PRESSURE, 1200 }, { EV_KEY, BTN_TOUCH, 1 } })
    for i = 1, 8 do
        feed(inp, { { EV_ABS, ABS_X, 300 + 50 * i }, { EV_ABS, ABS_Y, 500 }, { EV_ABS, ABS_PRESSURE, 1500 } })
        palmShift(inp, 6, 1200, 1800, i)
    end
    feed(inp, { { EV_ABS, ABS_PRESSURE, 0 }, { EV_KEY, BTN_TOUCH, 0 } })
    palmUp(inp, 6)
    feed(inp, { { EV_KEY, BTN_TOOL_PEN, 0 } })
end

-- what the drawing screen sees: the pen's contacts (tool pen, down) and every
-- other contact that was down in the pen's slot
local function seen(inp)
    local pen_points, strays, others = {}, 0, {}
    for _i, f in ipairs(inp.gesture_detector.frames) do
        for _j, s in ipairs(f) do
            local down = s.id ~= nil and s.id ~= -1 and s.x ~= nil and s.y ~= nil
            if down and s.slot == inp.pen_slot then
                if s.tool == 1 then pen_points[#pen_points + 1] = { s.x, s.y } else strays = strays + 1 end
            elseif down then
                others[s.slot] = true
            end
        end
    end
    return pen_points, strays, others
end
local function offPath(points)
    local n = 0
    for _i, p in ipairs(points) do if p[2] ~= 500 or p[1] < 300 or p[1] > 700 then n = n + 1 end end
    return n
end

print("== without the fix: what a hand did to a pen stroke (the owner's rectangles)")
;(function()
    local inp = newInput()
    scenario(inp)
    local pts = seen(inp)
    check(offPath(pts) > 0, "KOReader alone: the palm's 5th contact lands in the pen's slot as the pen ("
        .. offPath(pts) .. " pen point(s) where the hand is)")
    -- one palm contact that jumps between the pen's line and the hand, frame after frame
    local jumps, last = 0, nil
    for _i, f in ipairs(inp.gesture_detector.frames) do
        for _j, s in ipairs(f) do
            if s.slot == 5 and s.id ~= -1 and s.y then
                local on_line = s.y == 500
                if last ~= nil and on_line ~= last then jumps = jumps + 1 end
                last = on_line
            end
        end
    end
    check(jumps >= 8, "…and the pen's moves go into a palm's slot: it jumps between the pen and the hand "
        .. jumps .. " times (the rectangles with a diagonal)")
end)()

print("== with the fix: the pen's stroke is the pen's")
;(function()
    local inp = newInput()
    check(PenInput.install(inp) and not PenInput.install(inp), "installed once on a pen Kindle")
    scenario(inp)
    local pts, strays, others = seen(inp)
    check(#pts >= 9 and offPath(pts) == 0, "every pen point on the pen's line (" .. #pts .. " points)")
    check(strays == 0, "no palm contact in the pen's slot")
    local n = 0
    for slot in pairs(others) do
        n = n + 1
        check(slot ~= inp.pen_slot, "palm slot " .. slot .. " isn't the pen's")
    end
    check(n == 6, "the palm's 6 contacts kept, each in its own slot (" .. n .. ")")
    local st = inp.gz_pen_input.stats
    check(st.dropped >= 4 and st.pen > 0 and st.panel > 0, "the touch screen's single-touch copy dropped (" .. st.dropped .. ")")
end)()

print("== with the fix: a finger alone and the pen alone still work")
;(function()
    local inp = newInput()
    PenInput.install(inp)
    feed(inp, { { EV_ABS, ABS_MT_SLOT, 0 }, { EV_ABS, ABS_MT_TRACKING_ID, 7 }, { EV_ABS, ABS_MT_X, 100 }, { EV_ABS, ABS_MT_Y, 200 },
        { EV_KEY, BTN_TOUCH, 1 }, { EV_ABS, ABS_X, 100 }, { EV_ABS, ABS_Y, 200 } })
    feed(inp, { { EV_ABS, ABS_MT_X, 110 } })
    feed(inp, { { EV_ABS, ABS_MT_TRACKING_ID, -1 }, { EV_KEY, BTN_TOUCH, 0 } })
    local f = inp.gesture_detector.frames
    check(f[1][1].slot == 0 and f[1][1].x == 100 and f[1][1].id == 7 and f[2][1].x == 110 and f[3][1].id == -1,
        "a finger tap: slot 0, its moves and its lift (toolbar taps, menus)")
    local inp2 = newInput()
    PenInput.install(inp2)
    feed(inp2, { { EV_KEY, BTN_TOOL_PEN, 1 }, { EV_ABS, ABS_X, 10 }, { EV_ABS, ABS_Y, 20 } })
    feed(inp2, { { EV_ABS, ABS_PRESSURE, 900 }, { EV_KEY, BTN_TOUCH, 1 } })
    feed(inp2, { { EV_ABS, ABS_X, 30 } })
    feed(inp2, { { EV_KEY, BTN_TOUCH, 0 } })
    feed(inp2, { { EV_KEY, BTN_TOOL_PEN, 0 } })
    local pts = {}
    for _i, fr in ipairs(inp2.gesture_detector.frames) do
        for _j, s in ipairs(fr) do if s.slot == inp2.pen_slot and s.id == inp2.pen_slot then pts[#pts + 1] = s.x end end
    end
    check(table.concat(pts, ",") == "10,30", "the pen alone: down at 10, moved to 30, lifted (" .. table.concat(pts, ",") .. ")")
end)()

print("== the decision on its own")
;(function()
    local st = PenInput.newState(4, 0)
    local r, slot = PenInput.route(st, { type = EV_ABS, code = ABS_X, value = 1 })
    check(r == "pen" and slot == 4, "a position with no multitouch in the frame: the pen's")
    r, slot = PenInput.route(st, { type = EV_ABS, code = ABS_MT_SLOT, value = 5 })
    check(r == "panel" and slot == 5 + PenInput.PANEL_SHIFT, "the touch screen's slot 5: moved past the pen's")
    r = PenInput.route(st, { type = EV_KEY, code = BTN_TOUCH, value = 1 })
    check(r == "drop", "BTN_TOUCH after a multitouch event in the same frame: the touch screen's copy, dropped")
    PenInput.route(st, { type = EV_SYN, code = 0, value = 0 })
    r, slot = PenInput.route(st, { type = EV_ABS, code = ABS_MT_X, value = 3 })
    check(r == "panel" and slot == 5 + PenInput.PANEL_SHIFT, "the next frame without ABS_MT_SLOT: still the touch screen's slot 5")
    r = PenInput.route(st, { type = EV_KEY, code = 116, value = 1 })
    check(r == "pass", "the power button: as it is")
    check(PenInput.panelSlot(st, 0) == 0 and PenInput.panelSlot(st, 3) == 3 and PenInput.panelSlot(st, 4) == 20,
        "slots below the pen's kept (two-finger gestures use 0 and 1)")
    check(not PenInput.install({ wacom_protocol = false }) and not PenInput.install(nil), "Kindles without a pen: nothing changes")
end)()

-- a Kobo's pen (the Elipsa, Sage, Elipsa 2E, Libra Colour): on the touch panel itself, a
-- contact whose tool is a pen (ABS_MT_TOOL_TYPE 1), its pressure in ABS_MT_PRESSURE
do
    local ABS_MT_TOOL_TYPE, ABS_MT_PRESSURE = 0x37, 0x3a
    local dev = setmetatable({ screen = { getWidth = function() return 1404 end, getHeight = function() return 1872 end } },
        { __index = function() return function() return false end end })
    local inp = Input:new{ device = dev, input = {}, event_map = {} }
    inp.pressure_event = ABS_MT_PRESSURE -- (KoboCondor)
    feed(inp, { { EV_ABS, ABS_MT_SLOT, 0 }, { EV_ABS, ABS_MT_TRACKING_ID, 7 }, { EV_ABS, ABS_MT_TOOL_TYPE, 0 },
        { EV_ABS, ABS_MT_X, 900 }, { EV_ABS, ABS_MT_Y, 900 }, { EV_ABS, ABS_MT_PRESSURE, 40 } })
    feed(inp, { { EV_ABS, ABS_MT_SLOT, 1 }, { EV_ABS, ABS_MT_TRACKING_ID, 8 }, { EV_ABS, ABS_MT_TOOL_TYPE, 1 },
        { EV_ABS, ABS_MT_X, 300 }, { EV_ABS, ABS_MT_Y, 500 }, { EV_ABS, ABS_MT_PRESSURE, 2200 } })
    feed(inp, { { EV_ABS, ABS_MT_SLOT, 1 }, { EV_ABS, ABS_MT_X, 320 }, { EV_ABS, ABS_MT_PRESSURE, 2600 } })
    local pen, finger
    for _i, f in ipairs(inp.gesture_detector.frames) do
        for _j, c in ipairs(f) do
            if c.tool == 1 and c.gz_pressure then pen = c.gz_pressure end
            if c.tool == 0 and c.slot == 0 then finger = c end
        end
    end
    check(pen == 2600, "a Kobo's pen: its pressure (ABS_MT_PRESSURE) goes with its contact as the Scribe's does (" .. tostring(pen) .. ")")
    check(finger and finger.gz_pressure == nil, "…a finger's pressure doesn't (fingers draw without)")
end

print(string.format("pen input: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
