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
    -- (anything else asked of it: the real one's)
    local real = E.real_pd(D)
    setmetatable(PD, { __index = function(_t, k)
        local v = real[k]
        if type(v) == "function" then return function(_self, ...) return v(real, ...) end end
        return v
    end })
    D.getPowerDevice = function() return PD end
    A().LOOK_EVERY = 1
end, after = 2 })
if MODEL ~= "scribe" then
    add({ fn = function(E)
        check(tile() == nil and not A().available(), "no light sensor (" .. MODEL .. "): no Auto light tile")
        local zen = require("apps/filemanager/filemanager").instance.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        local items = require("modules/settings/sections/global_settings").build({ config = zen.config, plugin = zen, settings_apply = function() end })
        local first
        for _i, it in ipairs(items) do if it.text == "Brightness" then first = it.sub_item_table[1] end end
        check(first and first.text == "Enable brightness schedule", "…and Settings → Brightness starts with the schedule, as before")
    end, after = 1 })
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
        powerd():turnOnFrontlight()
        ROOM = 100
    end, after = 2 })
    -- Settings → General → Schedules → Brightness: Auto light first, with its adjustments
    add({ fn = function(E)
        pcall(function() require("modules/settings/zen_settings_page").closeActive() end)
        local fm = require("apps/filemanager/filemanager").instance
        require("modules/settings/zen_settings_page").show(fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN"), { path = {
            { key = "text", value = "General" }, { key = "text", value = "Schedules" }, { key = "text", value = "Brightness" } } })
    end, after = 6 })
    add({ shot = "1-settings-brightness", after = 0.5 })
    add({ fn = function(E)
        -- the rows as Settings builds them
        local zen = require("apps/filemanager/filemanager").instance.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        local items = require("modules/settings/sections/global_settings").build({ config = zen.config, plugin = zen, settings_apply = function() end })
        local br
        for _i, it in ipairs(items) do if it.text == "Brightness" then br = it end end
        local rows = br and br.sub_item_table or {}
        local function txt(r) return r.text or (r.text_func and r.text_func()) or "" end
        local names = {}
        for i = 1, 7 do names[i] = rows[i] and txt(rows[i]) or "" end
        E.rows = rows
        check(names[1] == "Auto light" and names[2]:find("^Brighter or dimmer") and names[3]:find("^Never dimmer than") and names[4]:find("^Never brighter than")
            and names[5]:find("^Follows the room") and names[6] == "Forget my adjustments" and names[7]:find("^Now: ")
            and txt(rows[8]) == "Enable brightness schedule",
            "Settings → Brightness: Auto light and its adjustments first, then the schedule (" .. table.concat(names, " | ") .. ")")
        check(rows[1].checked_func() == true and names[7]:find("lux", 1, true) ~= nil, "…Auto light ticked (it's on); Now: the room's light and the light's level (" .. names[7] .. ")")
        -- brighter or dimmer: +20%
        for _i, sub in ipairs(rows[2].sub_item_table) do if sub.text == "+20%" then sub.callback() end end
        check(math.abs((G_reader_settings:readSetting(A().OFFSET) or 0) - 0.2) < 0.001 and txt(rows[2]) == "Brighter or dimmer: +20%", "Brighter or dimmer → +20%: kept, and the row says so")
        -- never brighter than 10 (the picker: answered as if 10 were chosen)
        rows[4].callback()
    end, after = 2 })
    add({ fn = function(E)
        local d = UIM():getTopmostVisibleWidget()
        check(d and d.value_max == 24 and d.callback ~= nil, "Never brighter than: a picker of the light's levels (0–" .. tostring(d and d.value_max) .. ")")
        if d and d.callback then d.callback(10); UIM():close(d) end
        ROOM = 5000
    end, after = 4 })
    add({ fn = function(E)
        local cur = powerd():frontlightIntensity()
        check(G_reader_settings:readSetting(A().HIGHEST) == 10 and cur <= 10, "…set to 10: in daylight the light stays at 10 at most (" .. cur .. ")")
        -- quickly
        for _i, sub in ipairs(E.rows[5].sub_item_table) do if sub.text:find("^Quickly") then sub.callback() end end
        check(A().speed() == "fast" and A().SPEEDS.fast.every == 5, "Follows the room → Quickly: kept")
        -- the schedule turned on: Auto light goes off (they'd fight)
        E.rows[8].callback()
        check(not A().isOn(), "Enable brightness schedule: Auto light turns off")
        E.rows[8].callback() -- (the schedule off again)
        -- Auto light on again: the schedule goes off
        E.rows[8].callback()
        E.rows[1].callback()
        local zen = require("apps/filemanager/filemanager").instance.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        check(A().isOn() and zen.config.features.brightness_schedule == false, "Auto light on: the brightness schedule turns off")
        -- forget my adjustments
        E.rows[6].callback()
        check(G_reader_settings:readSetting(A().OFFSET) == nil and G_reader_settings:readSetting(A().HIGHEST) == nil and A().speed() == "normal",
            "Forget my adjustments: back to as the room asks, the whole range, normal speed")
        pcall(function() require("modules/settings/zen_settings_page").closeActive() end)
        A().set(false)
    end, after = 3 })

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
