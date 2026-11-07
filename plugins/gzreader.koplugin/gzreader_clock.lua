--[[--
The device's clock from a server's, when it's plainly wrong.

A Nook 1st Edition whose battery ran down starts in the year 2000 (and a
Kindle in 1970); with Wi-Fi nothing sets it again while GZreader runs:
Grimmory's reading statistics were then asked for the year 2000 (only the
streak, which doesn't need a date, showed), and reading sessions went out
with 2000 dates. Every HTTPS answer carries the server's time (the Date
header): when the clock is before 2024 and a server says otherwise, the
clock is set from it (once per start), as the sync page does over USB for
the Kindles without Wi-Fi (gzreader_usbsync.lua).
]]

local Log = require("gzreader_log")

local Clock = {
    WRONG_BEFORE = 1704067200, -- 2024-01-01 UTC: a clock before this is wrong
    done = false,
}

local MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }

--- Days since 1970-01-01 of a date (proleptic Gregorian).
local function daysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

--- "Sat, 07 Nov 2026 06:57:01 GMT" -> seconds since 1970 (UTC), or nil.
function Clock.parseHttpDate(s)
    if type(s) ~= "string" then return nil end
    local d, mon, y, hh, mm, ss = s:match("(%d%d?) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT")
    local m = MONTHS[mon or ""]
    if not m then return nil end
    return daysFromCivil(tonumber(y), m, tonumber(d)) * 86400 + tonumber(hh) * 3600 + tonumber(mm) * 60 + tonumber(ss)
end

--- Set the clock (UTC seconds); only on the e-readers GZreader runs on as
--- root. True when the command ran.
function Clock.set(t)
    local Device = require("device")
    local ok_kindle = Device.isKindle and Device:isKindle()
    local ok_nook = Device.isNook and Device:isNook()
    if not ok_kindle and not ok_nook then return false end
    os.execute(string.format("date -u %s >/dev/null 2>&1 && (hwclock -u -w >/dev/null 2>&1 || true)", os.date("!%m%d%H%M%Y.%S", t)))
    return true
end

--- A server answered (its headers): set a plainly wrong clock from its Date.
--- Returns true when the clock was set.
function Clock.fromServer(headers, now)
    if Clock.done or type(headers) ~= "table" then return false end
    now = now or os.time()
    if now >= Clock.WRONG_BEFORE then
        Clock.done = true -- (right already: nothing more to look at)
        return false
    end
    local t = Clock.parseHttpDate(headers.date or headers.Date)
    if not t or t < Clock.WRONG_BEFORE then return false end
    Clock.done = true
    Log.info("clock: said", os.date("!%Y-%m-%d %H:%M", now), "UTC; set from the server's", os.date("!%Y-%m-%d %H:%M", t))
    return Clock.set(t) == true
end

return Clock
