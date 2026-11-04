-- luacheck: globals arg io
--[[
Run GZreader (the real KOReader + ZenOS + GZreader Lua) as a Kindle 3 under
qemu-arm, headless: fake framebuffer, scripted keys, real everything else.
GZ_EMU_MODEL: k3 (default), k2 (Kindle 2), dx (DX: KOReader's Kindle 2
class at 824 × 1200), dxg (DX Graphite), k4 (Kindle 4: 5-way, no keyboard,
8-bit inverted framebuffer), kt (Kindle Touch: touch, Home button) or pw3
(Paperwhite 3: touch, 1072 × 1448 at 300 dpi), with that model's serial,
framebuffer and key codes; scripted taps and swipes on the touch models.

  tools/gzreader/emulator/run.sh <script.lua> <outdir> [cpu %]   (see README.md)

The script returns a list of steps: { wait = s } | { key = "Press" } |
{ shot = "name" } | { fn = function(E) ... end } |
{ wait_for = function(E) return done end, timeout = s } |
{ tap = { x, y } } | { tap = "text on screen" } | { tap = function() return x, y end } | { hold = { x, y } | "text" } |
{ swipe = { x1, y1, x2, y2 } } (touch models).
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
    k4 = "B00E12345678ABCD", kt = "B00F12345678ABCD", pw3 = "G090G1000000000A" }
-- framebuffer: einkfb (Kindle 2, DX, 3, 4) or mxcfb (touch), size, bits, inverted grey levels
local SCREENS = { k3 = { 600, 800, 4 }, k2 = { 600, 800, 4 }, dx = { 824, 1200, 4 }, dxg = { 824, 1200, 4 },
    k4 = { 600, 800, 8 }, kt = { 600, 800, 8, mxcfb = true }, pw3 = { 1072, 1448, 8, mxcfb = true } }
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
local function down(x, y, dt)
    x, y = x * TOUCH_SCALE[1], y * TOUCH_SCALE[2]
    touch_id = touch_id + 1
    frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_TRACKING_ID, touch_id }, { ABS_MT_X, math.floor(x) }, { ABS_MT_Y, math.floor(y) } }, dt)
end
local function move(x, y, dt) x, y = x * TOUCH_SCALE[1], y * TOUCH_SCALE[2]; frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_X, math.floor(x) }, { ABS_MT_Y, math.floor(y) } }, dt) end
local function up(dt) frame({ { ABS_MT_SLOT, 0 }, { ABS_MT_TRACKING_ID, -1 } }, dt) end
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
    return PW
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
        dev.isKindle = function() return true end
        E.installDisplay(dev.screen)
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
    end
end

function E.shot(name)
    local p = OUT .. "/" .. name .. ".png"
    local ok, err = pcall(function() E.display:writePNG(p) end)
    say("shot", name, ok and "" or tostring(err), "refreshes", E.refreshes, "windows:", E.top())
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

table.insert(package.loaders, 2, function(name)
    if name ~= "gzreader_usage" then return nil end
    return function()
        local m = dofile(package.searchpath(name, package.path))
        if os.getenv("GZ_EMU_TIANJI") then m.SERVER = os.getenv("GZ_EMU_TIANJI") end
        m.SEND_EVERY = tonumber(os.getenv("GZ_EMU_USAGE_EVERY") or "") or m.SEND_EVERY
        if os.getenv("GZ_EMU_USAGE_LEVEL") then G_reader_settings:saveSetting("gzreader_usage", os.getenv("GZ_EMU_USAGE_LEVEL")) end
        m.TICK = tonumber(os.getenv("GZ_EMU_USAGE_TICK") or "") or m.TICK
        m.SUMMARY_EVERY = tonumber(os.getenv("GZ_EMU_USAGE_SUMMARY") or "") or m.SUMMARY_EVERY
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
