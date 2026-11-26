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

Quick panel → Auto light, and Settings → Brightness (its adjustments) on Kindles
with a sensor. Pure part: autolight_test.lua.
]]

local AutoLight = {
    LOOK_EVERY = 15, -- seconds between looks at the sensor
    STILL = 0.06, -- a difference smaller than this (of the range) is left as it is
    STEP = 0.25, -- at most this much of the range changed at one look
    SETTING = "gzreader_auto_brightness",
    OFFSET = "gzreader_auto_brightness_offset",
    LOWEST = "gzreader_auto_brightness_lowest", -- never dimmer than (a level; none: the light's least)
    HIGHEST = "gzreader_auto_brightness_highest", -- never brighter than (a level; none: its most)
    SPEED = "gzreader_auto_brightness_speed", -- "slow", "normal" or "fast"
}

--- How quickly it follows the room: seconds between looks, and the most of the range changed at one.
AutoLight.SPEEDS = {
    slow = { every = 30, step = 0.12 },
    normal = { every = 15, step = 0.25 },
    fast = { every = 5, step = 0.5 },
}
AutoLight.SPEED_IDS = { "slow", "normal", "fast" }
--- "Brighter or dimmer than it would be" in Settings: these steps (of the light's range).
AutoLight.TASTES = { -0.4, -0.2, -0.1, 0, 0.1, 0.2, 0.4 }

-- ------------------------------------------------------------------ pure

--- How much of the light (0..1) the curve wants for `lux` (the room's light).
function AutoLight.curve(lux)
    lux = math.max(0, tonumber(lux) or 0)
    local f = 0.08 + 0.72 * math.min(1, math.log10(lux + 1) / 3)
    return math.max(0, math.min(1, f))
end

--- The light's level (min..max) for `lux`, moved by `offset` (your taste, -1..1 of the range),
--- and kept between `lowest` and `highest` (levels; nil: the light's own least and most).
function AutoLight.target(lux, min, max, offset, lowest, highest)
    local f = math.max(0, math.min(1, AutoLight.curve(lux) + (offset or 0)))
    local v = math.floor(min + f * (max - min) + 0.5)
    local lo = math.max(min, math.min(max, tonumber(lowest) or min))
    local hi = math.max(min, math.min(max, tonumber(highest) or max))
    if hi < lo then lo, hi = hi, lo end
    return math.max(lo, math.min(hi, v))
end

--- The level to set now, from `cur` towards `want` (nil: leave it): nothing for a
--- small difference, at most `step_f` of the range (STEP by default) at once.
function AutoLight.next(cur, want, min, max, step_f)
    local range = math.max(1, max - min)
    local d = want - cur
    if math.abs(d) < math.max(1, AutoLight.STILL * range) then return nil end
    local step = math.max(1, math.floor((step_f or AutoLight.STEP) * range + 0.5))
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

local function setting(key) return G_reader_settings and G_reader_settings:readSetting(key) end

--- How quickly it follows (AutoLight.SPEEDS's), as set.
function AutoLight.speed()
    local id = setting(AutoLight.SPEED)
    return AutoLight.SPEEDS[id] and id or "normal"
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

--- The light's level as the Kindle has it now (read from the light itself),
--- not only as KOReader last set it: something else (the Kindle's own
--- brightness, a button) may have moved it since. KOReader's own idea is put
--- right when they differ, so the next change starts from where it really is.
function AutoLight.realLevel(powerd, min, max)
    local kept = powerd:frontlightIntensity() or min
    -- (through powerd's lipc, as the Kindle's own software has it: in the same steps;
    -- the kernel's file uses other numbers, so without lipc there's nothing better)
    if powerd.lipc_handle == nil and not AutoLight.read_level then return kept end
    local ok, hw = pcall(function()
        if AutoLight.read_level then return AutoLight.read_level() end -- (tests, the emulator)
        return powerd:frontlightIntensityHW()
    end)
    hw = ok and tonumber(hw) or nil
    if not hw or hw < min or hw > max then return kept end
    hw = math.floor(hw + 0.5)
    if hw ~= kept then
        AutoLight.drift = (AutoLight.drift or 0) + 1
        log("auto brightness: the light was at", hw, "not", kept, "(moved by something else)")
        pcall(function() powerd.fl_intensity = hw end)
    end
    return hw
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
    local cur = AutoLight.realLevel(powerd, min, max)
    local want = AutoLight.target(lux, min, max, setting(AutoLight.OFFSET) or 0, setting(AutoLight.LOWEST), setting(AutoLight.HIGHEST))
    local v = AutoLight.next(cur, want, min, max, AutoLight.SPEEDS[AutoLight.speed()].step)
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

--- Seconds between looks: the speed's (LOOK_EVERY when set by hand, as tests do).
function AutoLight.every()
    if AutoLight.LOOK_EVERY ~= 15 then return AutoLight.LOOK_EVERY end
    return AutoLight.SPEEDS[AutoLight.speed()].every
end

--- Looks every few seconds (AutoLight.every) while it's on (and the Kindle awake).
function AutoLight.start()
    local UIManager = require("ui/uimanager")
    if AutoLight.loop then UIManager:unschedule(AutoLight.loop) end
    if not AutoLight.isOn() then AutoLight.loop = nil; return end
    AutoLight.loop = function()
        AutoLight.look()
        if AutoLight.isOn() and not AutoLight.asleep then UIManager:scheduleIn(AutoLight.every(), AutoLight.loop) end
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

--- "+10%", "−20%", "as it is" for a taste (an offset of the range).
function AutoLight.tasteText(o)
    local _ = require("gettext")
    local p = math.floor(math.abs(o or 0) * 100 + 0.5) * ((o or 0) < 0 and -1 or 1)
    if p == 0 then return _("as it is") end
    return (p > 0 and "+" or "\u{2212}") .. math.abs(p) .. "%"
end

--- The room's light and the light's level now, for Settings ("120 lux · light 14 of 24"), or nil.
function AutoLight.nowText()
    local lux = AutoLight.lux()
    if not lux then return nil end
    local powerd, min, max = range()
    local T = require("ffi/util").template
    local _ = require("gettext")
    return T(_("%1 lux · light %2 of %3"), math.floor(lux + 0.5), powerd:frontlightIntensity() or min, max)
end

--- Settings → Brightness's rows for it (Kindles with a sensor): on/off, brighter or
--- dimmer, never dimmer or brighter than, how quickly, forget what it learned, the
--- room now. `opts.on_enable()`: what turning it on turns off (the brightness schedule:
--- the two would fight over the light); `opts.picker(title, value, cb, min, max)`: a level picker.
function AutoLight.settingsItems(opts)
    if not AutoLight.available() then return {} end
    opts = opts or {}
    local _ = require("gettext")
    local T = require("ffi/util").template
    local function levels() return select(2, range()) end
    local items = {}
    items[#items + 1] = {
        text = _("Auto light"),
        help_text = _("The light follows the room, by the Kindle's light sensor: dim in the dark, brighter in a bright room. Turning it on turns the brightness schedule off."),
        checked_func = function() return AutoLight.isOn() end,
        callback = function()
            local now = not AutoLight.isOn()
            if now and opts.on_enable then pcall(opts.on_enable) end
            AutoLight.set(now)
        end,
    }
    local function on() return AutoLight.isOn() end
    local tastes = {}
    for _i, o in ipairs(AutoLight.TASTES) do
        tastes[#tastes + 1] = {
            text = o == 0 and _("As the room asks") or AutoLight.tasteText(o),
            radio = true,
            checked_func = function() return math.abs((setting(AutoLight.OFFSET) or 0) - o) < 0.005 end,
            callback = function()
                G_reader_settings:saveSetting(AutoLight.OFFSET, o)
                log("auto brightness: set brighter or dimmer", AutoLight.tasteText(o))
                AutoLight.look()
            end,
        }
    end
    items[#items + 1] = {
        text_func = function() return T(_("Brighter or dimmer: %1"), AutoLight.tasteText(setting(AutoLight.OFFSET) or 0)) end,
        help_text = _("How much brighter or dimmer than the room asks for. Moving the light's slider yourself while Auto light is on sets this too."),
        enabled_func = on,
        sub_item_table = tastes,
    }
    local function limit(key, title, default)
        return {
            text_func = function()
                local v = setting(key)
                return v and T(title .. ": %1", v) or T(title .. ": %1", default())
            end,
            enabled_func = on,
            keep_menu_open = true,
            callback = function(menu)
                local min, max = levels()
                local cur = setting(key) or (key == AutoLight.LOWEST and min or max)
                local function apply(v)
                    G_reader_settings:saveSetting(key, v)
                    log("auto brightness:", key == AutoLight.LOWEST and "never dimmer than" or "never brighter than", v)
                    AutoLight.look()
                    if menu and menu.updateItems then menu:updateItems() end
                end
                if opts.picker then opts.picker(title, cur, apply, min, max) end
            end,
        }
    end
    items[#items + 1] = limit(AutoLight.LOWEST, _("Never dimmer than"), function() return _("the least") end)
    items[#items + 1] = limit(AutoLight.HIGHEST, _("Never brighter than"), function() return _("the most") end)
    local names = { slow = _("Slowly (every 30 seconds)"), normal = _("Normally (every 15 seconds)"), fast = _("Quickly (every 5 seconds)") }
    local speeds = {}
    for _i, id in ipairs(AutoLight.SPEED_IDS) do
        speeds[#speeds + 1] = {
            text = names[id], radio = true,
            checked_func = function() return AutoLight.speed() == id end,
            callback = function()
                G_reader_settings:saveSetting(AutoLight.SPEED, id)
                log("auto brightness: follows the room", id)
                if AutoLight.isOn() then AutoLight.start() end
            end,
        }
    end
    items[#items + 1] = {
        text_func = function()
            local short = { slow = _("slowly"), normal = _("normally"), fast = _("quickly") }
            return T(_("Follows the room: %1"), short[AutoLight.speed()])
        end,
        help_text = _("How often it looks at the room's light, and how far it moves the light at once. Quicker uses a little more battery."),
        enabled_func = on,
        sub_item_table = speeds,
    }
    items[#items + 1] = {
        text = _("Forget my adjustments"),
        help_text = _("Back to how the room asks, the light's whole range, and normal speed."),
        enabled_func = on,
        keep_menu_open = true,
        callback = function(menu)
            for _i, k in ipairs({ AutoLight.OFFSET, AutoLight.LOWEST, AutoLight.HIGHEST, AutoLight.SPEED }) do G_reader_settings:delSetting(k) end
            log("auto brightness: adjustments forgotten")
            AutoLight.start()
            if menu and menu.updateItems then menu:updateItems() end
        end,
    }
    items[#items + 1] = {
        text_func = function()
            local t = AutoLight.isOn() and AutoLight.nowText()
            return t and T(_("Now: %1"), t) or _("Now: —")
        end,
        enabled_func = on,
        keep_menu_open = true,
        callback = function(menu) if menu and menu.updateItems then menu:updateItems() end end,
        separator = true,
    }
    -- (the Brightness page's own sun beside each, as its other rows have)
    local okI, icons = pcall(require, "common/inline_icon_map")
    local glyph = okI and type(icons) == "table" and icons.schedule_brightness
    if glyph then for _i, it in ipairs(items) do it.icon_glyph = glyph end end
    return items
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
