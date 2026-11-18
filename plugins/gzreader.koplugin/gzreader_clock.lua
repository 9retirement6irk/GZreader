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

And as soon as Wi-Fi connects (gzreader_net.lua), not only when a server of
yours answers: a Kindle Touch whose clock went back to 2013 after a reboot
had nothing to set it until Grimmory answered. Clock.online asks a time
server (NTP, pool.ntp.org) and, if that's blocked, the Date of an answer
from GitHub (where updates come from). Only while the clock is plainly
wrong: a right clock costs one comparison, no request.
]]

local Log = require("gzreader_log")

local Clock = {
    WRONG_BEFORE = 1704067200, -- 2024-01-01 UTC: a clock before this is wrong
    done = false,
    NTP_HOST = "pool.ntp.org",
    HTTP_URL = "https://github.com/",
    TIMEOUT = 3,
    -- (tests) stand-ins: udp() -> a LuaSocket UDP object; head(url) -> headers
    udp = nil,
    head = nil,
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

--- An NTP answer (48 bytes) -> seconds since 1970 (UTC), or nil: its
--- transmit time (bytes 41-44, seconds since 1900).
function Clock.parseNtp(packet)
    if type(packet) ~= "string" or #packet < 48 then return nil end
    local b1, b2, b3, b4 = packet:byte(41, 44)
    local secs = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
    if secs == 0 then return nil end
    return secs - 2208988800
end

local function ntp()
    local udp = Clock.udp and Clock.udp() or require("socket").udp()
    if not udp then return nil, "no UDP" end
    udp:settimeout(Clock.TIMEOUT)
    -- client request: leap 0, version 3, mode 3 (0x1B), the rest zero
    local ok, err = udp:sendto(string.char(0x1B) .. string.rep("\0", 47), Clock.NTP_HOST, 123)
    local answer
    if ok then answer, err = udp:receive() end
    udp:close()
    if not answer then return nil, tostring(err) end
    return Clock.parseNtp(answer), "a time server"
end

local function http()
    local headers
    if Clock.head then
        headers = Clock.head(Clock.HTTP_URL)
    else
        local https = require("ssl.https")
        local socketutil = require("socketutil")
        socketutil:set_timeout(Clock.TIMEOUT, Clock.TIMEOUT * 2)
        local ok, _, _, h = pcall(https.request, { url = Clock.HTTP_URL, method = "HEAD" })
        socketutil:reset_timeout()
        headers = ok and h or nil
    end
    if type(headers) ~= "table" then return nil, "no answer" end
    return Clock.parseHttpDate(headers.date or headers.Date), "GitHub's Date"
end

--- Wi-Fi just connected: a plainly wrong clock set from a time server (NTP),
--- or from GitHub's Date if NTP is blocked. Returns true when it was set.
function Clock.online(now)
    if Clock.done then return false end
    now = now or os.time()
    if now >= Clock.WRONG_BEFORE then
        Clock.done = true
        return false
    end
    local t, from = nil, nil
    for _i, ask in ipairs({ ntp, http }) do
        local ok, v, how = pcall(ask)
        if ok and v and v >= Clock.WRONG_BEFORE then t, from = v, how break end
    end
    if not t then
        Log.info("clock: says", os.date("!%Y-%m-%d", now), "UTC; no time server answered (set from the next server answer)")
        return false
    end
    Clock.done = true
    Log.info("clock: said", os.date("!%Y-%m-%d %H:%M", now), "UTC; set from " .. from, os.date("!%Y-%m-%d %H:%M", t))
    return Clock.set(t) == true
end

return Clock
