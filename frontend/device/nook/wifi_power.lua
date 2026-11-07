--[[--
The Nook 1st Edition's Wi-Fi power saving, through the wireless extensions'
ioctls (SIOCGIWPOWER / SIOCSIWPOWER: what `iwconfig eth0 power off` does;
Android 1.5 has no iwconfig). With power saving on, the Marvell chip naps
between packets: a strong signal still lost 2 pings in 5 and took 50-75 ms
to the router, and GZreader's HTTPS requests timed out. Android manages it
itself; while GZreader runs, its start script brings Wi-Fi up and turns
power saving off (gzreader.sh).

As a module: WifiPower.get(ifname) -> "on" / "off" or nil, err;
WifiPower.set(ifname, on) -> true or nil, err.
As a script (from koreader/): ./luajit frontend/device/nook/wifi_power.lua get|off|on [eth0]
]]

local ffi = require("ffi")

pcall(ffi.cdef, [[
int socket(int domain, int type, int protocol);
int ioctl(int fd, unsigned long request, ...);
int close(int fd);
char *strerror(int errnum);
struct gz_iw_param { int32_t value; uint8_t fixed; uint8_t disabled; uint16_t flags; };
struct gz_iwreq { char name[16]; union { struct gz_iw_param power; char pad[16]; } u; };
]])

local WifiPower = {
    SIOCGIWPOWER = 0x8B2D,
    SIOCSIWPOWER = 0x8B2C,
    AF_INET = 2, SOCK_DGRAM = 2,
    C = ffi.C, -- (a test replaces it)
}

local function request(ifname, ioc, disabled)
    local C = WifiPower.C
    local fd = C.socket(WifiPower.AF_INET, WifiPower.SOCK_DGRAM, 0)
    if fd < 0 then return nil, "no socket: " .. ffi.string(C.strerror(ffi.errno())) end
    local req = ffi.new("struct gz_iwreq")
    ffi.copy(req.name, ifname, math.min(#ifname, 15))
    if disabled ~= nil then req.u.power.disabled = disabled and 1 or 0 end
    local r = C.ioctl(fd, ioc, req)
    local err = r < 0 and ffi.string(C.strerror(ffi.errno())) or nil
    C.close(fd)
    if err then return nil, err end
    return req
end

--- "on" or "off", or nil, why.
function WifiPower.get(ifname)
    local req, err = request(ifname or "eth0", WifiPower.SIOCGIWPOWER)
    if not req then return nil, err end
    return req.u.power.disabled ~= 0 and "off" or "on"
end

--- Power saving on or off. True, or nil, why.
function WifiPower.set(ifname, on)
    local req, err = request(ifname or "eth0", WifiPower.SIOCSIWPOWER, not on)
    if not req then return nil, err end
    return true
end

-- run as a script: print what it did (the start script logs it)
if arg and arg[0] and arg[0]:match("wifi_power%.lua$") then
    local what, ifname = arg[1] or "get", arg[2] or "eth0"
    if what == "off" or what == "on" then
        local before = WifiPower.get(ifname)
        local ok, err = WifiPower.set(ifname, what == "on")
        local after = WifiPower.get(ifname)
        print(ok and ("power saving " .. tostring(before) .. " -> " .. tostring(after))
            or ("power saving not changed (" .. tostring(before) .. "): " .. tostring(err)))
        os.exit(ok and 0 or 1)
    end
    local state, err = WifiPower.get(ifname)
    print(state and ("power saving " .. state) or ("power saving unknown: " .. tostring(err)))
    os.exit(state and 0 or 1)
end

return WifiPower
