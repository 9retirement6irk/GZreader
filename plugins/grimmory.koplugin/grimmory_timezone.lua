--[[--
Time zone for GZreader. The Kindle 3 has no time zone setting: its clock is
kept in UTC (from Amazon's network time), so KOReader showed UTC times. This
sets the TZ environment variable of GZreader's own process (POSIX rules, so
no zoneinfo files are needed) and leaves the Kindle's clock alone.
]]

local Log = require("grimmory_log")
local _ = require("gettext")

local TZ = {}

TZ.ZONES = {
    { "UTC", "UTC0" },
    { "US Eastern (New York)", "EST5EDT,M3.2.0,M11.1.0" },
    { "US Central (Chicago)", "CST6CDT,M3.2.0,M11.1.0" },
    { "US Mountain (Denver)", "MST7MDT,M3.2.0,M11.1.0" },
    { "US Arizona (Phoenix)", "MST7" },
    { "US Pacific (Los Angeles)", "PST8PDT,M3.2.0,M11.1.0" },
    { "US Alaska (Anchorage)", "AKST9AKDT,M3.2.0,M11.1.0" },
    { "US Hawaii (Honolulu)", "HST10" },
    { "Canada Atlantic (Halifax)", "AST4ADT,M3.2.0,M11.1.0" },
    { "Canada Newfoundland", "NST3:30NDT,M3.2.0,M11.1.0" },
    { "Mexico City", "CST6" },
    { "Brazil (São Paulo)", "<-03>3" },
    { "UK, Ireland, Portugal", "GMT0BST,M3.5.0/1,M10.5.0" },
    { "Central Europe (Paris, Berlin)", "CET-1CEST,M3.5.0,M10.5.0/3" },
    { "Eastern Europe (Athens, Kyiv)", "EET-2EEST,M3.5.0/3,M10.5.0/4" },
    { "Moscow, Istanbul", "<+03>-3" },
    { "Gulf (Dubai)", "<+04>-4" },
    { "India", "IST-5:30" },
    { "China, Singapore, Perth", "CST-8" },
    { "Japan, Korea", "JST-9" },
    { "Australia East (Sydney)", "AEST-10AEDT,M10.1.0,M4.1.0/3" },
    { "Australia Brisbane", "AEST-10" },
    { "New Zealand", "NZST-12NZDT,M9.5.0,M4.1.0/3" },
}

local function setenv(value)
    local ok, ffi = pcall(require, "ffi")
    if not ok then return false end
    pcall(ffi.cdef, "int setenv(const char *name, const char *value, int overwrite); void tzset(void);")
    local ok2 = pcall(function()
        ffi.C.setenv("TZ", value, 1)
        ffi.C.tzset()
    end)
    return ok2
end

function TZ.current() return G_reader_settings:readSetting("gzreader_timezone") end

--- Apply the saved time zone (at start-up).
function TZ.apply()
    local tz = TZ.current()
    if tz and tz ~= "" then
        local ok = setenv(tz)
        Log.info("time zone", tz, ok and "applied" or "could not be applied")
        return ok
    end
end

function TZ.set(tz)
    G_reader_settings:saveSetting("gzreader_timezone", tz)
    setenv(tz)
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("TimeFormatChanged")) -- clocks redraw
end

function TZ.label()
    local tz = TZ.current()
    for _i, z in ipairs(TZ.ZONES) do if z[2] == tz then return z[1] end end
    return tz or _("not set (UTC)")
end

function TZ.menuItems()
    local items = {}
    for _i, z in ipairs(TZ.ZONES) do
        items[#items + 1] = {
            text = z[1],
            checked_func = function() return TZ.current() == z[2] end,
            radio = true,
            callback = function(touchmenu)
                TZ.set(z[2])
                if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
            end,
        }
    end
    return items
end

return TZ
