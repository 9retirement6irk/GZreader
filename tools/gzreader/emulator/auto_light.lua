-- Auto brightness on a Kindle with a light sensor (the Scribe model; the
-- sensor's reading given here: AutoLight.read): the quick panel's Auto light
-- tile turns it on; the light follows the room (gently); moving the slider
-- yourself is remembered; off, it stays put. A Paperwhite 3 (no sensor) has no tile.
--   GZ_EMU_MODEL=scribe|pw3 GZ_EMU_TREE=<tree>/koreader run.sh auto_light.lua <out>
-- Checks go to <out>/auto-light-checks.txt.
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function A() return require("gzreader_autolight") end
-- (the emulator has no front light to set: a stand-in for powerd, as KOReader's behaves)
local PD = { fl_min = 0, fl_max = 24, fl_intensity = 12, on = false }
function PD:isFrontlightOff() return not self.on end
function PD:frontlightIntensity() return self.on and self.fl_intensity or 0 end
function PD:setIntensity(v) self.fl_intensity = v; self.on = v > self.fl_min end
function PD:turnOnFrontlight() self.on = true end
function PD:turnOffFrontlight() self.on = false end
local function powerd() return PD end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function tile()
    for _i, t in ipairs(require("gzreader_panel").controls(plugin())) do if t.id == "autolight" then return t end end
end
local ROOM = 0
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting(A().SETTING); G_reader_settings:delSetting(A().OFFSET)
    A().read = function() return ROOM end
    local D = require("device")
    E.real_pd = D.getPowerDevice
    D.getPowerDevice = function() return PD end
    A().LOOK_EVERY = 1
end, after = 2 })
if MODEL ~= "scribe" then
    add({ fn = function(E) check(tile() == nil and not A().available(), "no light sensor (" .. MODEL .. "): no Auto light tile") end, after = 1 })
else
    add({ fn = function(E)
        local t = tile()
        check(t and t.label == "Auto light off" and not t.on, "the quick panel has Auto light (off)")
        powerd():turnOnFrontlight()
        powerd():setIntensity(20)
        check(not powerd():isFrontlightOff() and powerd():frontlightIntensity() == 20, "the light on, at 20")
        ROOM = 2 -- (a dark room)
        t.run()
    end, after = 6 })
    add({ fn = function(E)
        local p = powerd()
        local cur = p:frontlightIntensity()
        local min, max = p.fl_min or 0, p.fl_max or 24
        local want = A().target(2, min, max, 0)
        check(A().isOn() and tile().on, "on")
        check(cur <= want + 2 and cur < 20, "a dark room: the light comes down, a step at a look (" .. cur .. ", wanting " .. want .. ")")
        E.dark = cur
        ROOM = 800 -- (the lamp on)
    end, after = 6 })
    add({ fn = function(E)
        local cur = powerd():frontlightIntensity()
        check(cur > E.dark, "a bright room: it goes up (" .. E.dark .. " → " .. cur .. ")")
        -- moved yourself (as the slider's release does): remembered
        powerd():setIntensity(math.max(0, cur - 6))
        A().userSet(math.max(0, cur - 6))
        E.mine = math.max(0, cur - 6)
    end, after = 4 })
    add({ fn = function(E)
        local cur = powerd():frontlightIntensity()
        local o = G_reader_settings:readSetting(A().OFFSET)
        check(o and o < 0 and math.abs(cur - E.mine) <= 1, "set dimmer by hand: remembered (" .. string.format("%+.2f", o or 0) .. "), and kept (" .. cur .. ")")
        tile().run()
        ROOM = 1
    end, after = 4 })
    add({ fn = function(E)
        local cur = powerd():frontlightIntensity()
        check(not A().isOn() and math.abs(cur - E.mine) <= 1, "off: the light stays where it was though the room went dark (" .. cur .. ")")
        -- asleep: no looks
        A().set(true); A().onSuspend()
        E.before_sleep = A().changes or 0
        ROOM = 0 -- (the room goes dark while it sleeps)
    end, after = 4 })
    add({ fn = function(E)
        check((A().changes or 0) == E.before_sleep, "asleep: the sensor isn't looked at")
        A().onResume()
    end, after = 3 })
    add({ fn = function(E)
        check((A().changes or 0) > E.before_sleep, "awake again: the light set for the room at once")
        -- turned off by you: left off
        powerd():turnOffFrontlight()
        E.before_off = A().changes or 0
        ROOM = 3
    end, after = 4 })
    add({ fn = function(E)
        check((A().changes or 0) == E.before_off and powerd():isFrontlightOff(), "the light turned off: auto brightness leaves it off")
        A().set(false)
    end, after = 1 })
end
add({ fn = function(E)
    A().read = nil
    if E.real_pd then require("device").getPowerDevice = E.real_pd end
    G_reader_settings:delSetting(A().SETTING); G_reader_settings:delSetting(A().OFFSET)
    local f = io.open(E.out .. "/auto-light-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
