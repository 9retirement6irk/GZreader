-- luacheck: globals arg io
--[[
Run GZreader (the real KOReader + ZenOS + GZreader Lua) as a Kindle 3 under
qemu-arm, headless: fake framebuffer, scripted keys, real everything else.
GZ_EMU_MODEL: k3 (default), k2 (Kindle 2), dx (DX: KOReader's Kindle 2
class at 824 × 1200), dxg (DX Graphite), k4 (Kindle 4: 5-way, no keyboard,
8-bit inverted framebuffer), kt (Kindle Touch: touch, Home button), pw3
(Paperwhite 3: touch, 1072 × 1448 at 300 dpi) or scribe (Kindle Scribe:
touch and a pen, 1860 × 2480 at 300 dpi, KOReader's KindleScribe with its
MTK display), with that model's serial, framebuffer and key codes; scripted
taps and swipes on the touch models, pen strokes on the Scribe.

  tools/gzreader/emulator/run.sh <script.lua> <outdir> [cpu %]   (see README.md)

The script returns a list of steps: { wait = s } | { key = "Press" } |
{ shot = "name" } | { fn = function(E) ... end } |
{ wait_for = function(E) return done end, timeout = s } |
{ tap = { x, y } } | { tap = "text on screen" } | { tap = function() return x, y end } | { hold = { x, y } | "text" } |
{ swipe = { x1, y1, x2, y2 } } (touch models) |
{ pen = { { x, y }, … }, eraser = true } (the Scribe: one stroke, E.pen).
]]
local SCRIPT, OUT = arg[1], arg[2]
arg = { [0] = "reader.lua" }
os.execute("mkdir -p " .. OUT)

local ffi = require("ffi")
pcall(ffi.cdef, "int usleep(unsigned int usec);")
pcall(ffi.cdef, "struct emu_timeval { long tv_sec; long tv_usec; }; int gettimeofday(struct emu_timeval *tv, void *tz);")

-- /proc/usid: a Kindle 3 (Wi-Fi) serial, or a Paperwhite 3's
local MODEL = os.getenv("GZ_EMU_MODEL") or "k3"
local SERIALS = { k3 = "B00812345678ABCD", k2 = "B00212345678ABCD", dx = "B00412345678ABCD", dxg = "B00912345678ABCD",
    k4 = "B00E12345678ABCD", kt = "B00F12345678ABCD", pw3 = "G090G1000000000A",
    -- (a Kindle Scribe: device code 27J at the 4th–6th characters, KOReader's ks_set)
    scribe = "G0927J000000000A" }
-- framebuffer: einkfb (Kindle 2, DX, 3, 4) or mxcfb (touch), size, bits, inverted grey levels
local SCREENS = { k3 = { 600, 800, 4 }, k2 = { 600, 800, 4 }, dx = { 824, 1200, 4 }, dxg = { 824, 1200, 4 },
    k4 = { 600, 800, 8 }, kt = { 600, 800, 8, mxcfb = true }, pw3 = { 1072, 1448, 8, mxcfb = true },
    scribe = { 1860, 2480, 8, mxcfb = true } }
local SCREEN = SCREENS[MODEL] or SCREENS.k3
local real_open = io.open
local usid = OUT .. "/usid"
do local f = real_open(usid, "w"); f:write((os.getenv("GZ_EMU_SERIAL") or SERIALS[MODEL] or SERIALS.k3) .. "\n"); f:close() end
io.open = function(p, m)
    if p == "/proc/usid" then return real_open(usid, m) end
    return real_open(p, m)
end

package.cpath = "./libs/?.so;" .. package.cpath
do
    local lfs = require("libs/libkoreader-lfs")
    local orig = lfs.attributes
    lfs.attributes = function(p, ...)
        if MODEL == "nook" then
            -- the Nook 1st Edition: no Kindle serial; its screen's platform device
            if p == "/proc/usid" then return nil end
            if p == "/sys/devices/platform/bravo-vfb" then return orig(OUT, ...) end
        elseif MODEL == "nst" then
            -- the Nook Simple Touch: its e-ink driver's sysfs setting
            if p == "/proc/usid" then return nil end
            if p == "/sys/class/graphics/fb0/pgflip_refresh" then return orig(usid, ...) end
        end
        if p == "/proc/usid" then return orig(usid, ...) end
        return orig(p, ...)
    end
end

local E = { queue = {}, log = {}, t0 = os.time(), out = OUT, model = MODEL }
E.clock0 = os.clock() -- (CPU time at start)
_G.EMU = E
local function say(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local line = string.format("[emu %4ds] %s", os.time() - E.t0, table.concat(parts, " "))
    io.stderr:write(line, "\n")
    E.log[#E.log + 1] = line
end
E.say = say

-- input: scripted
local KEYS = { Press = 28, Up = 103, Down = 108, Left = 105, Right = 106, Menu = 139, Back = 158, Home = 102,
    RPgFwd = 191, RPgBack = 109, LPgFwd = 104, LPgBack = 193, Del = 14, AA = 190, Sym = 126, Space = 57,
    Enter = 28, Shift = 42, Alt = 56, Period = 52, VPlus = 115, VMinus = 114 }

local letters = { Q = 16, W = 17, E = 18, R = 19, T = 20, Y = 21, U = 22, I = 23, O = 24, P = 25, A = 30, S = 31,
    D = 32, F = 33, G = 34, H = 35, J = 36, K = 37, L = 38, Z = 44, X = 45, C = 46, V = 47, B = 48, N = 49, M = 50 }
for k, v in pairs(letters) do KEYS[k] = v end
E.KEYS = KEYS

local function now_tv()
    local tv = ffi.new("struct emu_timeval")
    ffi.C.gettimeofday(tv, nil)
    return { sec = tonumber(tv.tv_sec), usec = tonumber(tv.tv_usec) }
end

function E.now()
    local tv = now_tv()
    return tv.sec + tv.usec / 1e6
end
E.start = E.now() -- (wall time at start: for startup timings)

-- the key codes of this model: its event map, the other way round (Kindle 3: KEYS)
local model_codes
local function code(name)
    if MODEL ~= "k3" and not model_codes then
        local ok, Device = pcall(require, "device")
        local map = ok and Device.input and Device.input.event_map
        if type(map) == "table" then
            model_codes = {}
            for c, n in pairs(map) do
                if type(n) == "string" and (not model_codes[n] or c < model_codes[n]) then model_codes[n] = c end
            end
        end
    end
    return (model_codes and model_codes[name]) or (MODEL == "k3" and KEYS[name]) or error("no key " .. name .. " on " .. MODEL)
end
E.code = code

--- A key pressed while another is held (Alt + R, Shift + Sym).
function E.combo(mod, name)
    local mc, kc = code(mod), code(name)
    local function ev(c, v)
        local t = now_tv()
        table.insert(E.queue, { { type = 1, code = c, value = v, time = t }, { type = 0, code = 0, value = 0, time = t } })
    end
    ev(mc, 1); ev(kc, 1); ev(kc, 0); ev(mc, 0)
end

function E.key(name)
    local c = code(name)
    local t = now_tv()
    table.insert(E.queue, { { type = 1, code = c, value = 1, time = t }, { type = 0, code = 0, value = 0, time = t } })
    local t2 = now_tv()
    table.insert(E.queue, { { type = 1, code = c, value = 0, time = t2 }, { type = 0, code = 0, value = 0, time = t2 } })
end

-- touch (Paperwhite): multitouch protocol B frames, as the panel sends them
local EV_SYN, EV_ABS = 0, 3
local ABS_MT_SLOT, ABS_MT_X, ABS_MT_Y, ABS_MT_TRACKING_ID = 0x2f, 0x35, 0x36, 0x39
local touch_id = 0
-- a frame at `dt` seconds after now (queued at once: the gesture detector goes by the event times)
local function frame(evs, dt)
    local t = now_tv()
    if dt and dt > 0 then
        local us = t.usec + math.floor(dt * 1e6)
        t = { sec = t.sec + math.floor(us / 1e6), usec = us % 1000000 }
    end
    local out = {}
    for _i, e in ipairs(evs) do out[#out + 1] = { type = EV_ABS, code = e[1], value = e[2], time = t } end
    out[#out + 1] = { type = EV_SYN, code = 0, value = 0, time = t }
    table.insert(E.queue, out)
end
-- the Kindle Touch's panel counts 0–4095 each way (KOReader scales it back)
local TOUCH_SCALE = MODEL == "kt" and { 4095 / 600, 4095 / 800 } or { 1, 1 }
-- the Nook Simple Touch's zForce panel: single touch, ABS_X / ABS_Y + BTN_TOUCH
local function stFrame(evs, dt)
    local t = now_tv()
    if dt and dt > 0 then
        local us = t.usec + math.floor(dt * 1e6)
        t = { sec = t.sec + math.floor(us / 1e6), usec = us % 1000000 }
    end
    local out = {}
    for _i, e in ipairs(evs) do out[#out + 1] = { type = e[1], code = e[2], value = e[3], time = t } end
    out[#out + 1] = { type = 0, code = 0, value = 0, time = t }
    table.insert(E.queue, out)
end
local st_last = { 0, 0 }
local function down(x, y, dt)
    if MODEL == "nst" then
        st_last = { math.floor(x), math.floor(y) }
        return stFrame({ { 3, 0, st_last[1] }, { 3, 1, st_last[2] }, { 1, 330, 1 } }, dt)
    end
    x, y = x * TOUCH_SCALE[1], y * TOUCH_SCALE[2]
    touch_id = touch_id + 1
    frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_TRACKING_ID, touch_id }, { ABS_MT_X, math.floor(x) }, { ABS_MT_Y, math.floor(y) } }, dt)
end
local function move(x, y, dt)
    if MODEL == "nst" then
        st_last = { math.floor(x), math.floor(y) }
        return stFrame({ { 3, 0, st_last[1] }, { 3, 1, st_last[2] } }, dt)
    end
    x, y = x * TOUCH_SCALE[1], y * TOUCH_SCALE[2]; frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_X, math.floor(x) }, { ABS_MT_Y, math.floor(y) } }, dt) end
local function up(dt)
    if MODEL == "nst" then return stFrame({ { 3, 0, st_last[1] }, { 3, 1, st_last[2] }, { 1, 330, 0 } }, dt) end
    frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_TRACKING_ID, -1 } }, dt) end
local function later(sec, fn)
    require("ui/uimanager"):scheduleIn(sec, fn)
end

--- Where `what` is: { x, y }, or the centre of the topmost widget showing that text.
function E.where(what)
    if type(what) == "function" then return what() end
    if type(what) == "table" then return what[1], what[2] end
    local hit = E.findText(what)
    if hit then return hit.x + hit.w / 2, hit.y + hit.h / 2 end
end

--- The topmost shown widget whose text contains `text` (plain): the dimen of
--- the innermost widget around it that takes taps (a button, a menu item).
local function validDimen(d) return type(d) == "table" and d.w and d.w > 0 and d.h and d.h > 0 and d.x and d.y end
function E.findText(text)
    local UIManager = require("ui/uimanager")
    local seen = {}
    local SKIP = { parent = true, show_parent = true, ui = true, dialog = true, _parent = true, menu = true,
        document = true, plugin = true, view = true, key_events = true, ges_events = true }
    local function search(w, depth, ctx)
        if type(w) ~= "table" or seen[w] or depth > 60 then return nil end
        seen[w] = true
        -- (only what takes taps: containers' own dimen often keeps x = y = 0)
        local d = rawget(w, "dimen")
        if validDimen(d) and type(w.onGesture) == "function" then ctx = d end
        local t = rawget(w, "text")
        -- (a widget, not the table describing one: ButtonTable's button specs have text too)
        if type(t) == "string" and t:find(text, 1, true) and ctx and type(w.paintTo) == "function" then return ctx end
        for k, v in pairs(w) do
            if type(v) == "table" and not SKIP[k] then
                local r = search(v, depth + 1, ctx)
                if r then return r end
            end
        end
    end
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local r = search(stack[i].widget, 0, nil)
        if r then return r end
    end
end

-- the Scribe's pen (KOReader's wacom protocol, input.wacom_protocol): its own
-- tool keys, single-touch ABS_X / ABS_Y, BTN_TOUCH for contact; KOReader puts
-- it in its own slot (pen_slot), tagged pen or eraser
local BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_TOUCH = 320, 321, 330
local ABS_X, ABS_Y, ABS_PRESSURE = 0, 1, 24
local function penFrame(evs, dt) stFrame(evs, dt) end
--- One pen stroke through `points` ({ { x, y }, … }, screen pixels; one point:
--- a tap), `sec` long; `eraser`: the pen's other end.
function E.pen(points, sec, eraser)
    if type(points) ~= "table" or #points == 0 then return say("pen: no points") end
    sec = sec or 0.3
    local tool = eraser and BTN_TOOL_RUBBER or BTN_TOOL_PEN
    local p1 = points[1]
    say(eraser and "eraser" or "pen", #points, "points from", math.floor(p1[1]), math.floor(p1[2]))
    -- hovering in, then down
    penFrame({ { 1, tool, 1 }, { 3, ABS_X, math.floor(p1[1]) }, { 3, ABS_Y, math.floor(p1[2]) }, { 3, ABS_PRESSURE, 0 } }, 0)
    penFrame({ { 3, ABS_PRESSURE, 1200 }, { 1, BTN_TOUCH, 1 } }, 0.01)
    local n = #points
    for i = 2, n do
        local p = points[i]
        penFrame({ { 3, ABS_X, math.floor(p[1]) }, { 3, ABS_Y, math.floor(p[2]) }, { 3, ABS_PRESSURE, 1500 } }, 0.01 + sec * (i - 1) / n)
    end
    -- lifted, then out of range
    penFrame({ { 3, ABS_PRESSURE, 0 }, { 1, BTN_TOUCH, 0 } }, sec + 0.02)
    penFrame({ { 1, tool, 0 } }, sec + 0.04)
end
--- The pen hovering over (x, y), not touching; and taken away. `dt`: seconds from now.
function E.penHover(x, y, dt)
    say("pen hovering", math.floor(x), math.floor(y))
    penFrame({ { 1, BTN_TOOL_PEN, 1 }, { 3, ABS_X, math.floor(x) }, { 3, ABS_Y, math.floor(y) }, { 3, ABS_PRESSURE, 0 } }, dt or 0)
end
function E.penAway(dt) say("pen away"); penFrame({ { 1, BTN_TOOL_PEN, 0 } }, dt or 0) end
--- A tap with the pen on `what` ({ x, y } or text on screen).
function E.penTap(what)
    local x, y = E.where(what)
    if not x then return say("pen tap: not on screen:", tostring(what)) end
    E.pen({ { x, y } }, 0.05)
end

function E.tap(what)
    local x, y = E.where(what)
    if not x then return say("tap: not on screen:", tostring(what)) end
    say("tap", type(what) == "string" and ("\"" .. what .. "\"") or "", math.floor(x), math.floor(y))
    down(x, y)
    up(0.05)
end

function E.hold(what, sec)
    local x, y = E.where(what)
    if not x then return say("hold: not on screen:", tostring(what)) end
    say("hold", math.floor(x), math.floor(y))
    down(x, y)
    later(sec or 1.2, up)
end

-- the Nook's colour touchscreen: single-touch ABS_X / ABS_Y / pressure +
-- BTN_TOUCH, in the panel's raw range (0–4095 here)
local function lcdFrame(evs, dt)
    local t = now_tv()
    if dt and dt > 0 then
        local us = t.usec + math.floor(dt * 1e6)
        t = { sec = t.sec + math.floor(us / 1e6), usec = us % 1000000 }
    end
    local out = {}
    for _i, e in ipairs(evs) do out[#out + 1] = { type = e[1], code = e[2], value = e[3], time = t } end
    out[#out + 1] = { type = 0, code = 0, value = 0, time = t }
    table.insert(E.queue, out)
end
local function lcdRaw(x, y)
    return math.floor(x * 4095 / 479 + 0.5), math.floor(y * 4095 / 143 + 0.5)
end
--- `what`: { x, y } on the colour screen, or a button's label there.
function E.lcdWhere(what)
    if type(what) == "table" then return what[1], what[2] end
    local ok, NS = pcall(require, "gzreader_nook")
    for _i, b in ipairs(ok and NS.buttons or {}) do
        if b.label == what then return b.x + b.w / 2, b.y + b.h / 2 end
    end
end
function E.lcdTap(what, hold_s)
    local x, y = E.lcdWhere(what)
    if not x then return say("lcd: no button", tostring(what)) end
    say(hold_s and "lcd hold" or "lcd tap", type(what) == "string" and ("\"" .. what .. "\"") or "", math.floor(x), math.floor(y))
    local rx, ry = lcdRaw(x, y)
    lcdFrame({ { 3, 0, rx }, { 3, 1, ry }, { 3, 24, 100 }, { 1, 330, 1 } }, 0)
    lcdFrame({ { 3, 24, 0 }, { 1, 330, 0 } }, hold_s or 0.08)
end
function E.lcdSwipe(x1, y1, x2, y2)
    say("lcd swipe", x1, y1, "->", x2, y2)
    local rx, ry = lcdRaw(x1, y1)
    lcdFrame({ { 3, 0, rx }, { 3, 1, ry }, { 3, 24, 100 }, { 1, 330, 1 } }, 0)
    for i = 1, 4 do
        local mx, my = lcdRaw(x1 + (x2 - x1) * i / 4, y1 + (y2 - y1) * i / 4)
        lcdFrame({ { 3, 0, mx }, { 3, 1, my } }, 0.04 * i)
    end
    lcdFrame({ { 3, 24, 0 }, { 1, 330, 0 } }, 0.2)
end

--- A finger stroke through `points` ({ { x, y }, … }, screen pixels), `sec` long.
function E.finger(points, sec)
    if type(points) ~= "table" or #points == 0 then return say("finger: no points") end
    sec = sec or 0.3
    say("finger", #points, "points from", math.floor(points[1][1]), math.floor(points[1][2]))
    down(points[1][1], points[1][2])
    local n = #points
    for i = 2, n do move(points[i][1], points[i][2], sec * (i - 1) / n) end
    up(sec + 0.02)
end
--- A finger put down and left there (a hand resting on the screen), and lifted.
function E.fingerDown(x, y, dt) say("finger down", math.floor(x), math.floor(y)); down(x, y, dt) end
function E.fingerUp(dt) say("finger up"); up(dt) end

function E.swipe(x1, y1, x2, y2, sec)
    say("swipe", x1, y1, "->", x2, y2)
    sec = sec or 0.25
    down(x1, y1)
    local n = 5
    for i = 1, n do move(x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n, sec * i / (n + 1)) end
    up(sec)
end

package.preload["libs/libkoreader-input"] = function()
    require("ffi/posix_h")
    local C = ffi.C
    local I = {}
    local n = 20
    function I.open() n = n + 1; return n end
    function I.fdopen() end
    function I.close() return true end
    function I.closeAll() end
    function I.fakeTapInput() end
    function I.waitForEvent(sec, usec)
        if #E.queue > 0 then
            E.key_sent_at = os.time()
            return true, table.remove(E.queue, 1)
        end
        local t = sec and (sec + (usec or 0) / 1e6) or 0.05
        if t > 0.05 then t = 0.05 end
        if t > 0 then C.usleep(math.floor(t * 1e6)) end
        return false, C.ETIME
    end
    return I
end
package.preload["ffi/framebuffer_einkfb"] = function()
    local FB = require("ffi/framebuffer_dummy")
    if os.getenv("GZ_EMU_FB8") == "1" then return FB end
    -- like the Kindle 2/3/4's and DX's: 4-bit (8-bit on the Kindle 4) with inverted grey levels (0xF = black)
    local BB = require("ffi/blitbuffer")
    local K3 = FB:extend{}
    function K3:init()
        self.bb = BB.new(SCREEN[1], SCREEN[2], SCREEN[3] == 8 and BB.TYPE_BB8 or BB.TYPE_BB4)
        self.bb:invert()
        self.bb:fill(BB.COLOR_WHITE)
        require("ffi/framebuffer").init(self)
    end
    return K3
end

-- the touch Kindles' framebuffer: 8-bit (Paperwhite 3: 1072 × 1448, Touch: 600 × 800)
package.preload["ffi/framebuffer_mxcfb"] = function()
    local FB = require("ffi/framebuffer_dummy")
    local BB = require("ffi/blitbuffer")
    local PW = FB:extend{}
    function PW:init()
        self.bb = BB.new(SCREEN[1], SCREEN[2], BB.TYPE_BB8)
        self.bb:fill(BB.COLOR_WHITE)
        require("ffi/framebuffer").init(self)
    end
    -- (the Scribe's MTK display: KindleScribe:init turns its "fast" mode on)
    function PW:_MTK_ToggleFastMode(on) E.mtk_fast = on end
    return PW
end

-- the Nook 1st Edition's two screens: the e-ink page on top, the colour
-- touchscreen under it (in a dark bezel), as one picture
local NOOK = { lcd_x = 60, lcd_y = 800 + 24, w = 600, h = 800 + 24 + 144 + 24 }
E.NOOK = NOOK
package.preload["device/nook/display_hw"] = function()
    local BB = require("ffi/blitbuffer")
    local HW = { EINK_W = 600, EINK_H = 800, LCD_W = 480, LCD_H = 144, VFB_H = 944, direct = true }
    function HW:open()
        E.display = BB.new(NOOK.w, NOOK.h, BB.TYPE_BBRGB32)
        E.display:paintRectRGB32(0, 0, NOOK.w, NOOK.h, BB.ColorRGB32(0x3b, 0x3d, 0x40, 0xFF))
        E.display:paintRect(0, 0, 600, 800, BB.COLOR_WHITE)
        E.display:paintRectRGB32(NOOK.lcd_x, NOOK.lcd_y, 480, 144, BB.ColorRGB32(0, 0, 0, 0xFF))
        E.refreshes, E.lcd_presents, E.waveforms = 0, 0, {}
        return self
    end
    function HW:eink(bb, x, y, w, h, waveform)
        if not E.no_display then E.display:blitFrom(bb, x, y, x, y, w, h) end
        E.refreshes = E.refreshes + 1
        E.waveforms[waveform] = (E.waveforms[waveform] or 0) + 1
        E.last_refresh, E.last_refresh_t = os.time(), E.now()
    end
    function HW:lcd(bb)
        E.display:blitFrom(bb, NOOK.lcd_x, NOOK.lcd_y, 0, 0, 480, 144)
        E.lcd_presents = (E.lcd_presents or 0) + 1
    end
    function HW:backlight(on)
        E.lcd_lit = on
        if not on then
            E.display:paintRectRGB32(NOOK.lcd_x, NOOK.lcd_y, 480, 144, BB.ColorRGB32(0, 0, 0, 0xFF))
        end
    end
    function HW:backlightLevel() return 64 end
    function HW:close() end
    return HW
end

-- the Nook Simple Touch's screen: an 8-bit page here (the real driver's
-- refresh ioctls are tested in nook_test.lua)
package.preload["device/nook/framebuffer_nst"] = function()
    local FB = require("ffi/framebuffer_dummy")
    local BB = require("ffi/blitbuffer")
    local NST = FB:extend{}
    function NST:init()
        self.bb = BB.new(600, 800, BB.TYPE_BB8)
        self.bb:fill(BB.COLOR_WHITE)
        require("ffi/framebuffer").init(self)
    end
    return NST
end

-- GZ_EMU_WIFID=1: a stand-in for the Kindle's Wi-Fi services over lipc (what
-- libopenlipclua reaches on a Kindle): two networks in range, "Home" saved;
-- joining one makes it the current network. E.wifid holds the state and the
-- calls made.
if os.getenv("GZ_EMU_WIFID") == "1" then
    local W = { calls = {}, current = nil, scanning = 0,
        profiles = { { essid = "Home", netid = 3 } },
        scan = { { essid = "Home", signal = 4, signal_max = 5, key_mgmt = "WPA-PSK", known = "yes", netid = 3 },
            { essid = "Cafe", signal = 2, signal_max = 5, key_mgmt = "WPA-PSK", known = "no" } } }
    E.wifid = W
    local function handle()
        local h = {}
        function h:set_string_property(svc, prop, val)
            W.calls[#W.calls + 1] = svc .. " " .. prop .. " " .. tostring(val)
            -- (the switcher connects in a subprocess: its calls go to the run's output too)
            print("[emu] wifid: " .. svc .. " " .. prop .. " " .. tostring(val))
            if prop == "scan" then W.scanning = 3 end
            local essid = prop == "ensureConnection" and tostring(val):match("^wifi:(.*)$") or prop == "cmConnect" and val
            if essid then
                for _i, p in ipairs(W.profiles) do
                    if p.essid == essid or tostring(p.netid) == essid then W.current = p.essid end
                end
            end
            if prop == "deleteProfile" then
                for i = #W.profiles, 1, -1 do if W.profiles[i].essid == val then table.remove(W.profiles, i) end end
            end
        end
        function h:set_int_property(svc, prop, val)
            W.calls[#W.calls + 1] = svc .. " " .. prop .. " " .. tostring(val)
            if prop == "deleteProfile" then
                for i = #W.profiles, 1, -1 do if W.profiles[i].netid == val then table.remove(W.profiles, i) end end
            end
        end
        function h:get_string_property(_svc, prop)
            if prop == "scanState" then
                if W.scanning > 0 then W.scanning = W.scanning - 1; return "scanning" end
                return "idle"
            end
            if prop == "cmState" then return W.current and "CONNECTED" or "READY" end
            return ""
        end
        function h:new_hasharray()
            local ha = { rows = {} }
            function ha:add_hash() self.rows[#self.rows + 1] = {} end
            function ha:put_string(i, k, v) self.rows[i + 1][k] = v end
            function ha:put_int(i, k, v) self.rows[i + 1][k] = v end
            function ha:destroy() end
            return ha
        end
        function h:access_hash_property(_svc, prop, input)
            local rows = {}
            if prop == "profileData" then rows = W.profiles
            elseif prop == "scanList" then rows = W.scan
            elseif prop == "currentEssid" then rows = { { essid = W.current or "" } }
            elseif prop == "createProfile" then
                local p = input.rows[1]
                W.profiles[#W.profiles + 1] = { essid = p.essid, netid = #W.profiles + 10 }
                W.calls[#W.calls + 1] = "com.lab126.wifid createProfile " .. tostring(p.essid)
            end
            return { to_table = function() return rows end, destroy = function() end }
        end
        function h:close() end
        return h
    end
    package.preload["libopenlipclua"] = function() return { open_no_name = handle, open = handle } end
end

-- the device: patch networking once it exists
table.insert(package.loaders, 2, function(name)
    if name ~= "device" then return nil end
    return function()
        local dev = dofile("frontend/device.lua")
        dev.initNetworkManager = function(_self, NM)
            NM.isWifiOn = function() return true end
            NM.isConnected = function() return true end
            NM.isOnline = function() return true end
            NM.turnOnWifi = function(_s, cb) if cb then cb() end return true end
            NM.turnOffWifi = function(_s, cb) if cb then cb() end end
            NM.getNetworkInterfaceName = function() return "eth0" end
            NM.restoreWifiAsync = function() end
        end
        if MODEL ~= "nook" then
            if MODEL ~= "nst" then dev.isKindle = function() return true end end
            E.installDisplay(dev.screen)
        end
        return dev
    end
end)

-- watch the main loop: how long each keypress takes to be handled
local function hookUI()
    local UIManager = require("ui/uimanager")
    local orig = UIManager.handleInputEvent
    UIManager.handleInputEvent = function(self, ev)
        local t = os.clock()
        local w0 = os.time()
        local r = { orig(self, ev) }
        local dt = os.time() - w0
        if dt >= 2 then say("SLOW input event:", dt, "s wall", string.format("%.1f s cpu", os.clock() - t)) end
        return unpack(r)
    end
end

function E.top()
    local UIManager = require("ui/uimanager")
    local out = {}
    for i, w in ipairs(UIManager._window_stack or {}) do
        local wd = w.widget
        local text = type(wd.text) == "string" and wd.text:sub(1, 40) or nil
        local title = type(wd.title) == "string" and wd.title or nil
        out[#out + 1] = i .. ":" .. tostring(wd.name or title or text or wd.id or "?"):gsub("%s+", " ")
            .. (wd.modal and "(modal)" or "")
    end
    return table.concat(out, " | ")
end

-- what the e-ink panel shows: only what was refreshed
function E.installDisplay(Screen)
    local BB = require("ffi/blitbuffer")
    E.display = BB.new(Screen.bb:getWidth(), Screen.bb:getHeight(), BB.TYPE_BBRGB32)
    E.display:fill(BB.COLOR_WHITE)
    E.refreshes = 0
    local prev = Screen.refreshFullImp
    Screen.refreshFullImp = function(self, x, y, w, h, ...)
        if prev then prev(self, x, y, w, h, ...) end -- (the shadow screen packs into the framebuffer here)
        if E.no_display then -- (timings: the copy to the emulator's display isn't the Kindle's cost)
            E.refreshes = E.refreshes + 1
            E.last_refresh, E.last_refresh_t = os.time(), E.now()
            return
        end
        x, y = x or 0, y or 0
        w, h = w or self.bb:getWidth(), h or self.bb:getHeight()
        -- what the panel shows: the framebuffer itself (not the shadow screen),
        -- physical pixels (a rotated screen looks sideways, as on the Kindle)
        local real = self._gz_fb_bb
        if real then
            local px, py, pw, ph = self.bb:getPhysicalRect(self.bb:getBoundedRect(x, y, w, h))
            real:setRotation(0)
            E.display:blitFrom(real, px, py, px, py, pw, ph)
        else
            E.display:blitFrom(self.bb, x, y, x, y, w, h)
        end
        E.refreshes = E.refreshes + 1
        E.last_refresh = os.time()
        E.last_refresh_t = E.now()
        if E.ghost then E.ghost.update(x, y, w, h) end
    end
    if os.getenv("GZ_EMU_GHOST") == "1" then E.installGhosts(Screen) end
end

--[[ GZ_EMU_GHOST=1: e-ink ghosting, roughly. Each refresh's kind (the
outermost refresh…Imp called) picks a waveform: a flashing one (full,
flashui, flashpartial) clears the panel; the others leave a trace of what the
pixel showed before (the Kindle 3's partial update a lot; the Paperwhite's
REAGL little, its GL16 more, A2/DU most), and traces add up over refreshes
until a flash. The panel as seen is written beside each shot as
<name>-ghost.png, and every refresh's kind, area and the screen's ghosting
afterwards go to <out>/ghosts.tsv (time, kind, x, y, w, h, % of the screen
with a visible ghost, worst ghost in grey levels). ]]
local GHOST = {
    einkfb = { flash = 0, partial = 0.16 },                      -- Kindle 2/3/4, DX: two update modes
    mxcfb = { flash = 0, reagl = 0.03, gl16 = 0.08, a2 = 0.22 },  -- touch Kindles
    KEEP = 0.85,     -- how much of an earlier trace a non-flashing update keeps
    VISIBLE = 16,    -- grey levels (of 255) a trace must reach to be seen
}
function E.installGhosts(Screen)
    local BB = require("ffi/blitbuffer")
    local W, H = E.display:getWidth(), E.display:getHeight()
    local touch = SCREEN.mxcfb == true
    local K = touch and GHOST.mxcfb or GHOST.einkfb
    local KIND = touch and { Full = "flash", FlashPartial = "flash", FlashUI = "flash", Partial = "reagl",
            NoMergePartial = "reagl", UI = "gl16", NoMergeUI = "gl16", Fast = "a2", A2 = "a2" }
        or { Full = "flash", FlashPartial = "flash", FlashUI = "flash" } -- (the rest: partial)
    local shown = ffi.new("uint8_t[?]", W * H)   -- the grey each pixel was last driven to
    local trace = ffi.new("float[?]", W * H)     -- its ghost (+: darker than it should be, -: lighter)
    ffi.fill(shown, W * H, 255)
    local seen = BB.new(W, H, BB.TYPE_BB8)        -- what the eye sees
    seen:fill(BB.COLOR_WHITE)
    local tsv = real_open(OUT .. "/ghosts.tsv", "w")
    tsv:write("t\tkind\tx\ty\tw\th\tghosted_pct\tworst\n")
    local depth, kind = 0, nil
    for name in pairs({ Full = 1, Partial = 1, NoMergePartial = 1, FlashPartial = 1, UI = 1, NoMergeUI = 1,
            FlashUI = 1, Fast = 1, A2 = 1 }) do
        local key = "refresh" .. name .. "Imp"
        local orig = Screen[key]
        if orig then
            Screen[key] = function(self, ...)
                if depth == 0 then kind = KIND[name] or "partial" end
                depth = depth + 1
                local r = { pcall(orig, self, ...) }
                depth = depth - 1
                if not r[1] then error(r[2]) end
                return unpack(r, 2)
            end
        end
    end
    local G = {}
    E.ghost = G
    function G.update(x, y, w, h)
        local kname = kind or "partial"
        local k = K[kname] or K.partial or 0
        kind = nil
        x, y = math.max(0, math.floor(x)), math.max(0, math.floor(y))
        w, h = math.min(W - x, math.floor(w)), math.min(H - y, math.floor(h))
        if w <= 0 or h <= 0 then return end
        local src = ffi.cast("uint8_t*", E.display.data)
        local sstride = E.display.stride
        local dst = ffi.cast("uint8_t*", seen.data)
        local dstride = seen.stride
        local flash = k == 0
        for yy = y, y + h - 1 do
            local srow, drow, base = src + yy * sstride, dst + yy * dstride, yy * W
            for xx = x, x + w - 1 do
                local i = base + xx
                local target = srow[xx * 4]   -- (RGB32: r)
                if flash then
                    trace[i] = 0
                else
                    trace[i] = trace[i] * GHOST.KEEP + (target - shown[i]) * k
                end
                shown[i] = target
                local v = target - trace[i]
                drow[xx] = v < 0 and 0 or v > 255 and 255 or v
            end
        end
        -- the whole screen's ghosting now
        local n, worst = 0, 0
        for i = 0, W * H - 1, 4 do   -- (every 4th pixel: enough for a percentage)
            local t = trace[i]
            if t < 0 then t = -t end
            if t >= GHOST.VISIBLE then n = n + 1 end
            if t > worst then worst = t end
        end
        G.pct = n * 400 / (W * H)
        G.worst = worst
        tsv:write(string.format("%.1f\t%s\t%d\t%d\t%d\t%d\t%.2f\t%d\n", E.now(), kname,
            x, y, w, h, G.pct, worst))
        tsv:flush()
    end
    function G.write(name)
        seen:writePNG(OUT .. "/" .. name .. "-ghost.png")
    end
end

function E.shot(name)
    local p = OUT .. "/" .. name .. ".png"
    local ok, err = pcall(function() E.display:writePNG(p) end)
    if E.ghost then pcall(E.ghost.write, name) end
    say("shot", name, ok and "" or tostring(err), "refreshes", E.refreshes, "windows:", E.top(),
        E.ghost and string.format("ghosted %.1f%% worst %d", E.ghost.pct or 0, E.ghost.worst or 0) or "")
end

local function runScript()
    local UIManager = require("ui/uimanager")
    local steps = dofile(SCRIPT)
    local i = 0
    local function step()
        i = i + 1
        local s = steps[i]
        if not s then
            say("script done; windows:", E.top())
            if E.requires then
                local rf = real_open(os.getenv("GZ_EMU_REQUIRES"), "w")
                rf:write(table.concat(E.requires, "\n"), "\n")
                rf:close()
            end
            E.done = true
            return UIManager:quit()
        end
        if s.wait then
            return UIManager:scheduleIn(s.wait, step)
        end
        -- wait (the UI keeps running) until wait_for(E) is true, e.g. a phone driven from outside
        if s.wait_for then
            local deadline = os.time() + (s.timeout or 180)
            local function poll()
                local ok, done = pcall(s.wait_for, E)
                if (ok and done) or os.time() > deadline then
                    say("wait_for", (ok and done) and "done" or "timed out", s.label or "")
                    return UIManager:scheduleIn(s.after or 1, step)
                end
                UIManager:scheduleIn(1, poll)
            end
            return poll()
        end
        if s.key then
            say("key", s.key)
            local ok, err = pcall(E.key, s.key)
            if not ok then say("step error:", tostring(err)) end
        elseif s.combo then
            say("keys", s.combo[1] .. "+" .. s.combo[2])
            local ok, err = pcall(E.combo, s.combo[1], s.combo[2])
            if not ok then say("step error:", tostring(err)) end
        elseif s.tap then
            E.tap(s.tap)
        elseif s.hold then
            E.hold(s.hold, s.sec)
        elseif s.swipe then
            E.swipe(unpack(s.swipe))
        elseif s.pen then
            E.pen(s.pen, s.sec, s.eraser)
        elseif s.lcd then
            E.lcdTap(s.lcd, s.sec)
        elseif s.lcd_swipe then
            E.lcdSwipe(unpack(s.lcd_swipe))
        elseif s.lcd_type then
            -- type on the colour screen's keyboard, a key at a time
            local k = 0
            local str = s.lcd_type
            local function nextKey()
                k = k + 1
                local ch = str:sub(k, k)
                if ch == "" then return end
                E.lcdTap(ch == " " and "space" or ch)
                require("ui/uimanager"):scheduleIn(0.4, nextKey)
            end
            nextKey()
        elseif s.shot then
            E.shot(s.shot)
        elseif s.fn then
            local ok, err = pcall(s.fn, E)
            if not ok then say("step error:", tostring(err)) end
        end
        UIManager:scheduleIn(s.after or 1.5, step)
    end
    UIManager:scheduleIn(steps.start or 8, step)
end

-- GZreader's helper processes (watchdog, audio) run the ARM luajit: via qemu here
table.insert(package.loaders, 2, function(name)
    if name ~= "gzreader_audiobook" then return nil end
    return function()
        local path = package.searchpath("gzreader_audiobook", package.path)
        local m = dofile(path)
        m.LUAJIT = "qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit"
        return m
    end
end)

table.insert(package.loaders, 2, function(name)
    if name ~= "gzreader_homemenu" then return nil end
    return function()
        local m = dofile(package.searchpath(name, package.path))
        local orig = m.show
        m.show = function(...)
            local c = os.clock()
            local r = { orig(...) }
            say(string.format("HomeMenu.show took %.2f s CPU", os.clock() - c))
            return unpack(r)
        end
        return m
    end
end)

table.insert(package.loaders, 2, function(name)
    if name ~= "gzreader_tts" then return nil end
    return function()
        local m = dofile(package.searchpath(name, package.path))
        local function handle()
            local h = {}
            function h:new_hasharray()
                local ha = {}
                function ha:add_hash() end
                function ha:put_string() end
                function ha:put_int() end
                function ha:destroy() end
                return ha
            end
            function h:access_hash_property() return { destroy = function() end } end
            function h:set_int_property() end
            function h:get_string_property() return "" end
            function h:close() end
            return h
        end
        m.lipc = { open_no_name = handle }
        m.exec = function() return 0 end
        return m
    end
end)

-- GZ_EMU_DEBUG_REPORTS=1: debug reports on (with GZ_REMOTE_FEED, feed.py's)
table.insert(package.loaders, 2, function(name)
    if name ~= "gzreader_remote" then return nil end
    return function()
        local m = dofile(package.searchpath(name, package.path))
        if os.getenv("GZ_EMU_DEBUG_REPORTS") then G_reader_settings:saveSetting(m.SETTING, os.getenv("GZ_EMU_DEBUG_REPORTS") == "1") end
        return m
    end
end)

-- start the script once UIManager exists
table.insert(package.loaders, 2, function(name)
    if name ~= "ui/uimanager" then return nil end
    return function()
        package.loaders[2] = package.loaders[2] -- noop
        local path = package.searchpath("ui/uimanager", package.path)
        local m = dofile(path)
        package.loaded["ui/uimanager"] = m
        hookUI()
        m:nextTick(runScript)
        return m
    end
end)

-- GZ_EMU_REQUIRES=<file>: every module loaded, with the time it took (self, not children)
if os.getenv("GZ_EMU_REQUIRES") then
    local orig_require = require
    local loaded_log, depth_t = {}, {}
    local clock = os.clock
    E.requires = loaded_log
    require = function(name) -- luacheck: ignore
        if package.loaded[name] ~= nil then return package.loaded[name] end
        local t0 = clock()
        depth_t[#depth_t + 1] = 0
        local r = orig_require(name)
        local child = table.remove(depth_t)
        local total = clock() - t0
        if #depth_t > 0 then depth_t[#depth_t] = depth_t[#depth_t] + total end
        loaded_log[#loaded_log + 1] = string.format("%.4f %.4f %s", total - child, total, name)
        return r
    end
end

local ok, err = xpcall(function() dofile("reader.lua") end, debug.traceback)
say("reader.lua returned", ok, err and tostring(err):sub(1, 2000) or "")
if E.requires then
    local rf = real_open(os.getenv("GZ_EMU_REQUIRES"), "w")
    rf:write(table.concat(E.requires, "\n"), "\n")
    rf:close()
end
local f = real_open(OUT .. "/emu.log", "w")
f:write(table.concat(E.log, "\n"), "\n")
f:close()
os.exit(0)
