--[[--
Auto brightness on Kindles with a light sensor (Voyage, Oasis 2 and 3,
Paperwhite 5 Signature, Scribe, Colorsoft): the front light follows the
room, as the Kindle's own "Auto brightness" does.

- The sensor (powerd's alsLux, in lux) is read every LOOK_EVERY seconds
  while the Kindle is awake and auto brightness is on, and once at waking.
- The light it wants (`AutoLight.target`): dim in a dark room, brighter as
  the room gets brighter, on a curve by the room's light's logarithm (the
  eye sees light that way): about a tenth at 1 lux, a third at 10, half
  at 100, most of it from 1,000 on.
- Your own taste: moving the light yourself (the quick panel's slider)
  while it's on is remembered as how much brighter or dimmer than the curve
  you like it (`offset`), and kept for the next time.
- Changes are gentle: nothing for a small difference (STILL), and at most
  STEP of the light's range at each look, so it doesn't jump when a hand
  passes over the sensor.

Quick panel → Auto light (Kindles with a sensor). Pure part: autolight_test.lua.
]]

local AutoLight = {
    LOOK_EVERY = 15, -- seconds between looks at the sensor
    STILL = 0.06, -- a difference smaller than this (of the range) is left as it is
    STEP = 0.25, -- at most this much of the range changed at one look
    SETTING = "gzreader_auto_brightness",
    OFFSET = "gzreader_auto_brightness_offset",
}

-- ------------------------------------------------------------------ pure

--- How much of the light (0..1) the curve wants for `lux` (the room's light).
function AutoLight.curve(lux)
    lux = math.max(0, tonumber(lux) or 0)
    local f = 0.08 + 0.72 * math.min(1, math.log10(lux + 1) / 3)
    return math.max(0, math.min(1, f))
end

--- The light's level (min..max) for `lux`, moved by `offset` (your taste, -1..1 of the range).
function AutoLight.target(lux, min, max, offset)
    local f = math.max(0, math.min(1, AutoLight.curve(lux) + (offset or 0)))
    return math.floor(min + f * (max - min) + 0.5)
end

--- The level to set now, from `cur` towards `want` (nil: leave it): nothing for a
--- small difference, at most STEP of the range at once.
function AutoLight.next(cur, want, min, max)
    local range = math.max(1, max - min)
    local d = want - cur
    if math.abs(d) < math.max(1, AutoLight.STILL * range) then return nil end
    local step = math.max(1, math.floor(AutoLight.STEP * range + 0.5))
    if d > step then d = step elseif d < -step then d = -step end
    return cur + d
end

--- Your taste after you set the light to `level` yourself while the room was at `lux`.
function AutoLight.offsetFor(level, lux, min, max)
    local range = math.max(1, max - min)
    local o = (level - min) / range - AutoLight.curve(lux)
    return math.max(-1, math.min(1, o))
end

-- ------------------------------------------------------------ the Kindle

local function Device() return require("device") end
local function log(...) pcall(function(...) require("gzreader_log").info(...) end, ...) end

--- A Kindle with a light sensor and a front light.
function AutoLight.available(device)
    device = device or Device()
    local ok, yes = pcall(function()
        return device:hasLightSensor() and device:hasFrontlight() and device:getPowerDevice() ~= nil
    end)
    return ok and yes and true or false
end

function AutoLight.isOn()
    return G_reader_settings ~= nil and G_reader_settings:isTrue(AutoLight.SETTING) and AutoLight.available()
end

--- The room's light in lux (powerd's alsLux), or nil when it can't be read.
function AutoLight.lux()
    if AutoLight.read then return AutoLight.read() end -- (tests, the emulator)
    local ok, lipc = pcall(require, "liblipclua")
    if not ok or not lipc then return nil end
    local h = lipc.init("com.github.gzreader.autolight")
    if not h then return nil end
    local okv, v = pcall(h.get_int_property, h, "com.lab126.powerd", "alsLux")
    h:close()
    return okv and type(v) == "number" and v >= 0 and v or nil
end

local function range()
    local powerd = Device():getPowerDevice()
    return powerd, powerd.fl_min or 0, powerd.fl_max or 24
end

--- One look: the light moved towards what the room wants. Returns the level set, or nil.
function AutoLight.look()
    if not AutoLight.isOn() then return nil end
    local lux = AutoLight.lux()
    if not lux then return nil end
    AutoLight.last_lux = lux
    local powerd, min, max = range()
    -- (the light turned off by you stays off: auto brightness moves it only while it's on)
    if powerd:isFrontlightOff() then return nil end
    local cur = powerd:frontlightIntensity() or min
    local want = AutoLight.target(lux, min, max, G_reader_settings:readSetting(AutoLight.OFFSET) or 0)
    local v = AutoLight.next(cur, want, min, max)
    if v then
        AutoLight.setting = true -- (our own change: not your taste)
        powerd:setIntensity(v)
        AutoLight.setting = nil
        AutoLight.changes = (AutoLight.changes or 0) + 1
    end
    return v
end

--- The light set by you (the quick panel) while auto brightness is on: remembered as your taste.
function AutoLight.userSet(level)
    if AutoLight.setting or not AutoLight.isOn() then return end
    local lux = AutoLight.last_lux or AutoLight.lux()
    if not lux then return end
    local min, max = select(2, range())
    local o = AutoLight.offsetFor(level, lux, min, max)
    G_reader_settings:saveSetting(AutoLight.OFFSET, o)
    log("auto brightness: your taste now", string.format("%+.2f", o), "at", lux, "lux")
end

--- Looks every LOOK_EVERY seconds while it's on (and the Kindle awake).
function AutoLight.start()
    local UIManager = require("ui/uimanager")
    if AutoLight.loop then UIManager:unschedule(AutoLight.loop) end
    if not AutoLight.isOn() then AutoLight.loop = nil; return end
    AutoLight.loop = function()
        AutoLight.look()
        if AutoLight.isOn() and not AutoLight.asleep then UIManager:scheduleIn(AutoLight.LOOK_EVERY, AutoLight.loop) end
    end
    UIManager:scheduleIn(0, AutoLight.loop)
end

function AutoLight.onSuspend()
    AutoLight.asleep = true
    if AutoLight.loop then require("ui/uimanager"):unschedule(AutoLight.loop) end
end

function AutoLight.onResume()
    AutoLight.asleep = nil
    AutoLight.start()
end

function AutoLight.set(on)
    G_reader_settings:saveSetting(AutoLight.SETTING, on and true or false)
    log("auto brightness", on and "on" or "off")
    if on then AutoLight.start() else AutoLight.onSuspend(); AutoLight.asleep = nil end
end

--- The quick panel's tile (Kindles with a sensor).
function AutoLight.tile()
    if not AutoLight.available() then return nil end
    local _ = require("gettext")
    local on = AutoLight.isOn()
    return { id = "autolight", icon = "sun", label = on and _("Auto light") or _("Auto light off"), on = on,
        run = function()
            local now = not AutoLight.isOn()
            AutoLight.set(now)
            pcall(function()
                require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                    text = now and _("Auto light on: the light follows the room. Move it yourself and it remembers how you like it.")
                        or _("Auto light off: the light stays where you put it."), timeout = 3 })
            end)
        end }
end

return AutoLight
