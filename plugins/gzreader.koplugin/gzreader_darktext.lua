--[[--
Darker text (experimental): Settings → Display and light → Screen → E-ink
settings → Darker text, on Kindles.

An e-ink screen picks how hard to drive its ink (its waveform) by the
panel's temperature: colder panels are driven longer. Telling the display
driver the panel is colder than it is makes text darker and leaves less of
the last page behind, at the cost of slower page turns with a longer flash.
KOReader sends the driver "use the panel's own temperature" with every
screen update (TEMP_USE_AMBIENT); this sends a fixed one instead (in °C):

  * A little darker: 16 °C   * Darker: 10 °C   * Darkest: 4 °C

Only while a book is open: closing it, or the Kindle going to sleep, puts
the panel's own temperature back (and opening a book, or waking, sets the
choice again). Off (the default): nothing is changed.

Experimental: on some Kindles a temperature the screen has no waveform for
may make updates slow or odd. If the screen misbehaves, choose Off (or
restart the Kindle: nothing is kept in the display driver).
]]

local DarkText = {
    SETTING = "gzreader_darker_text",
    LEVELS = {
        { id = "off" },
        { id = "little", temp = 16 },
        { id = "more", temp = 10 },
        { id = "most", temp = 4 },
    },
    own = nil,     -- the update's own temperature value, kept to put back (TEMP_USE_AMBIENT…)
    applied = nil, -- the temperature sent now (°C), or nil
    reading = false,
}

local function log(...) pcall(function(...) require("gzreader_log").info(...) end, ...) end

local function screen(device)
    device = device or require("device")
    return device.screen
end

--- The update request whose temperature is sent with every screen update,
--- or nil (not a Kindle, or a screen without one: the emulator).
function DarkText.request(device)
    device = device or require("device")
    local ok, req = pcall(function()
        if not (device.isKindle and device:isKindle()) then return nil end
        local s = screen(device)
        local r = s and s.update_data
        if r and type(tonumber(r.temp)) == "number" then return r end
        return nil
    end)
    return ok and req or nil
end

function DarkText.available(device) return DarkText.request(device) ~= nil end

--- The level chosen ("off", "little", "more", "most").
function DarkText.level(settings)
    settings = settings or G_reader_settings
    local v = settings and settings:readSetting(DarkText.SETTING)
    for _i, l in ipairs(DarkText.LEVELS) do if l.id == v then return v end end
    return "off"
end

--- The temperature (°C) for a level, or nil (off).
function DarkText.tempFor(id)
    for _i, l in ipairs(DarkText.LEVELS) do if l.id == id then return l.temp end end
    return nil
end

--- Send what's chosen now (a book open and a level other than off), or put
--- the panel's own temperature back.
function DarkText.update(device)
    local req = DarkText.request(device)
    if not req then return nil end
    if DarkText.own == nil then DarkText.own = tonumber(req.temp) end
    local t = DarkText.reading and DarkText.tempFor(DarkText.level()) or nil
    if t == DarkText.applied then return t end
    req.temp = t or DarkText.own
    DarkText.applied = t
    log("darker text:", t and (t .. " °C") or "the panel's own temperature again")
    return t
end

--- A book opened, closed; the Kindle going to sleep, waking.
function DarkText.onReading(device) DarkText.reading = true; return DarkText.update(device) end
function DarkText.onClosed(device) DarkText.reading = false; return DarkText.update(device) end
function DarkText.onSuspend(device)
    DarkText.was_reading = DarkText.reading
    DarkText.reading = false
    return DarkText.update(device)
end
function DarkText.onResume(device)
    DarkText.reading = DarkText.was_reading or false
    return DarkText.update(device)
end

--- Choose a level.
function DarkText.set(id, device)
    G_reader_settings:saveSetting(DarkText.SETTING, id)
    log("darker text: chosen", id)
    local t = DarkText.update(device)
    -- (the page drawn again at once, with the new temperature: a full flash)
    pcall(function() require("ui/uimanager"):setDirty("all", "full") end)
    return t
end

--- Settings → Display and light → Screen → E-ink settings: its row, or nil.
function DarkText.menuItem(device)
    if not DarkText.available(device) then return nil end
    local _ = require("gettext")
    local names = { off = _("Off"), little = _("A little darker"), more = _("Darker"), most = _("Darkest") }
    local sub = {}
    for _i, l in ipairs(DarkText.LEVELS) do
        sub[#sub + 1] = {
            text = names[l.id],
            radio = true,
            checked_func = function() return DarkText.level() == l.id end,
            callback = function() DarkText.set(l.id, device) end,
        }
    end
    return {
        text_func = function()
            local T = require("ffi/util").template
            return T(_("Darker text (experimental): %1"), names[DarkText.level()])
        end,
        help_text = _("Darker text and less of the last page left behind while reading, by telling the screen it's colder than it is. Page turns get slower, with a longer flash. Only while a book is open; sleep and Home use the screen's own setting. Experimental: if the screen misbehaves, choose Off or restart the Kindle."),
        sub_item_table = sub,
    }
end

return DarkText
