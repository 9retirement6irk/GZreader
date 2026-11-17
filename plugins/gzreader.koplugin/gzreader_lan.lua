--[[--
Is a server on the home network? Decides whether GZreader may try plain HTTP
by itself when an address was typed without http:// or https:// and HTTPS
didn't answer.

A server on the internet that "has no HTTPS" is just as often one whose
HTTPS someone on the same Wi-Fi is blocking, to get the password (or token,
or calendar link) sent again in the clear. So the plain-HTTP retry is only
for addresses that can't be on the internet: private and link-local IPv4
(10/8, 172.16/12, 192.168/16, 169.254/16, 100.64/10 — Tailscale and carrier
NAT), loopback, private IPv6 (fc00::/7, fe80::/10, ::1), names with no dot
("nas"), and local names (.local, .lan, .home, .internal, .home.arpa,
localhost). Anything else needs http:// typed to be reached without HTTPS.
]]

local Lan = {}

local LOCAL_SUFFIXES = { "local", "lan", "home", "internal", "home.arpa", "localhost", "localdomain" }

--- The host of an address (lower case; an IPv6 address without its brackets).
function Lan.host(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    s = s:gsub("^%a[%w+.-]*://", "")
    s = s:gsub("^[^/@]*@", "") -- (user:password@)
    local v6 = s:match("^%[([^%]]+)%]")
    if v6 then return v6:lower() end
    return (s:match("^([^/:?#]+)") or ""):lower()
end

local function ipv4(h)
    local a, b, c, d = h:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return a, b
end

--- Can this address only be on the home network (or this device)?
function Lan.isPrivate(s)
    local h = Lan.host(s)
    if h == "" then return false end
    local a, b = ipv4(h)
    if a then
        return a == 10 or a == 127 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)
            or (a == 169 and b == 254) or (a == 100 and b >= 64 and b <= 127)
    end
    if h:find(":", 1, true) then -- IPv6
        return h == "::1" or h:match("^f[cd]%x%x:") ~= nil or h:match("^fe[89ab]%x:") ~= nil
    end
    h = h:gsub("%.$", "")
    if not h:find(".", 1, true) then return true end -- ("nas", "localhost")
    for _i, suffix in ipairs(LOCAL_SUFFIXES) do
        if h == suffix or h:sub(-(#suffix + 1)) == "." .. suffix then return true end
    end
    return false
end

--- May an address typed as `typed` be tried over plain HTTP when HTTPS
--- doesn't answer? Only with no scheme typed, and only on the home network.
function Lan.plainRetry(typed)
    if tostring(typed or ""):match("^%s*%a[%w+.-]*://") then return false end
    return Lan.isPrivate(typed)
end

--- What to tell someone whose server on the internet didn't answer over HTTPS.
function Lan.noHttpsText()
    local _ = require("gettext")
    return _("Couldn't reach it over HTTPS. If this server really has no HTTPS, type the address with http:// in front (what you send it then travels unencrypted).")
end

return Lan
