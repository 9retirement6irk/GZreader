-- luacheck: globals arg io
--[[
Run GZreader (the real KOReader + ZenOS + GZreader Lua) as a Kindle 3 under
qemu-arm, headless: fake framebuffer, scripted keys, real everything else.

  tools/gzreader/emulator/run.sh <script.lua> <outdir> [cpu %]   (see README.md)

The script returns a list of steps: { wait = s } | { key = "Press" } |
{ shot = "name" } | { fn = function(E) ... end }.
]]
local SCRIPT, OUT = arg[1], arg[2]
arg = { [0] = "reader.lua" }
os.execute("mkdir -p " .. OUT)

local ffi = require("ffi")
pcall(ffi.cdef, "int usleep(unsigned int usec);")
pcall(ffi.cdef, "struct emu_timeval { long tv_sec; long tv_usec; }; int gettimeofday(struct emu_timeval *tv, void *tz);")

-- /proc/usid: a Kindle 3 (Wi-Fi) serial
local real_open = io.open
local usid = OUT .. "/usid"
do local f = real_open(usid, "w"); f:write("B00812345678ABCD\n"); f:close() end
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

local E = { queue = {}, log = {}, t0 = os.time(), out = OUT }
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
    Enter = 28, Shift = 42, Alt = 56, Period = 52 }

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

function E.key(name)
    local code = KEYS[name] or error("no key " .. name)
    local t = now_tv()
    table.insert(E.queue, { { type = 1, code = code, value = 1, time = t }, { type = 0, code = 0, value = 0, time = t } })
    local t2 = now_tv()
    table.insert(E.queue, { { type = 1, code = code, value = 0, time = t2 }, { type = 0, code = 0, value = 0, time = t2 } })
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
    return FB
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
    Screen.refreshFullImp = function(self, x, y, w, h)
        x, y = x or 0, y or 0
        w, h = w or self.bb:getWidth(), h or self.bb:getHeight()
        E.display:blitFrom(self.bb, x, y, x, y, w, h)
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
            E.done = true
            return UIManager:quit()
        end
        if s.wait then
            return UIManager:scheduleIn(s.wait, step)
        end
        if s.key then
            say("key", s.key)
            E.key(s.key)
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

local ok, err = xpcall(function() dofile("reader.lua") end, debug.traceback)
say("reader.lua returned", ok, err and tostring(err):sub(1, 2000) or "")
local f = real_open(OUT .. "/emu.log", "w")
f:write(table.concat(E.log, "\n"), "\n")
f:close()
os.exit(0)
