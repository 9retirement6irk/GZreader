--[[--
Where a download's time goes, in gzreader.log.

The owner's Paperwhite 3 (2026-11-15): updates came in at ~34 KB/s from start
to end; books at ~30 KB/s for a few minutes, then ~1 MB/s. A Paperwhite 3
can take in well over 1 MB/s over TLS (the download's own work is a few
percent of its processor at that speed), so the slow stretches are waiting:
for the network (Wi-Fi power saving, the TCP receive buffer), for the
processor (other work at a higher priority), or the process being stopped
(gzreader_download.lua's Download.yield while other requests run). These
lines tell which.

Used inside the download's own process (books: Api:downloadToFile; updates:
Update.get), around its LuaSocket sink:

  transfer book 12: start · Wi-Fi power saving on · TCP receive buffer 4096 87380 1048576 · CPU ondemand 996 MHz (ignore nice 1) · load 1.20 0.90 0.50
  transfer book 12: 0.5 MB in 15 s (34 KB/s), 0.5 MB so far · own CPU 2%, all 97% · longest wait 0.4 s · Wi-Fi power saving on
  transfer book 12: done · 8.0 MB in 240 s (34 KB/s) · slowest 30 KB/s, fastest 41 KB/s (of the lines above) · longest wait 3.1 s

"longest wait": the longest time between two pieces of data (a stopped
process shows up there as a long one with no CPU used). "all": how busy the
whole processor was. Nothing is measured while diagnostic logging is off
(#41). No Wi-Fi network name is read or written: only power saving's state.
]]

local Log = require("gzreader_log")

local XferLog = {
    EVERY = 15,          -- s between speed lines
    MIN_BYTES = 262144,  -- a transfer smaller than this, with no line on the way, logs nothing (redirect bodies)
    -- (tests replace these)
    read = nil,          -- function(path) -> first line or nil
    clock = nil,         -- function() -> seconds, monotonic
    cpu = os.clock,      -- this process's processor time, s
    wifi = nil,          -- function() -> "on" / "off" / nil, why
}

local function readLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

local function monotonic()
    local ok, t = pcall(function()
        local ffi = require("ffi")
        pcall(ffi.cdef, "struct gz_xfer_ts { long tv_sec; long tv_nsec; }; int clock_gettime(int clk, struct gz_xfer_ts *tp);")
        local ts = ffi.new("struct gz_xfer_ts")
        if ffi.C.clock_gettime(1, ts) ~= 0 then error("clock_gettime") end -- CLOCK_MONOTONIC
        return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) / 1e9
    end)
    if ok then return t end
    return require("socket").gettime()
end

local function now() return (XferLog.clock or monotonic)() end
local function rd(path) return (XferLog.read or readLine)(path) end

--- The Wi-Fi interface's power saving: "on", "off", or nil, why.
function XferLog.wifiPower()
    if XferLog.wifi then return XferLog.wifi() end
    local ok, state, err = pcall(function()
        local ifname = "wlan0" -- (every Kindle; the Nook's is eth0)
        local okn, NetworkMgr = pcall(require, "ui/network/manager")
        if okn and NetworkMgr and NetworkMgr.getNetworkInterfaceName then
            local okf, name = pcall(NetworkMgr.getNetworkInterfaceName, NetworkMgr)
            if okf and type(name) == "string" and name ~= "" then ifname = name end
        end
        return require("device/nook/wifi_power").get(ifname)
    end)
    if not ok then return nil, tostring(state) end
    return state, err
end

--- Busy and total jiffies from /proc/stat's first line (all processors).
local function cpuTimes()
    local line = rd("/proc/stat")
    if not line or not line:match("^cpu ") then return nil end
    local total, idle, i = 0, 0, 0
    for n in line:gmatch("%d+") do
        i = i + 1
        n = tonumber(n)
        total = total + n
        if i == 4 or i == 5 then idle = idle + n end -- idle, iowait
    end
    return total - idle, total
end

local function kb(bytes, secs)
    if not secs or secs <= 0 then return "?" end
    return string.format("%d KB/s", math.floor(bytes / 1024 / secs + 0.5))
end
local function mb(bytes) return string.format("%.1f MB", bytes / 1048576) end

--- The start line: what could hold a transfer back on this device.
function XferLog.probe()
    local parts = {}
    local ps, why = XferLog.wifiPower()
    parts[#parts + 1] = "Wi-Fi power saving " .. (ps or ("unknown (" .. tostring(why) .. ")"))
    local rmem = rd("/proc/sys/net/ipv4/tcp_rmem")
    if rmem then parts[#parts + 1] = "TCP receive buffer " .. rmem:gsub("%s+", " ") end
    local gov = rd("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
    if gov then
        local cur = tonumber(rd("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq") or "")
        local nice = rd("/sys/devices/system/cpu/cpufreq/" .. gov .. "/ignore_nice_load")
            or rd("/sys/devices/system/cpu/cpu0/cpufreq/" .. gov .. "/ignore_nice_load")
        parts[#parts + 1] = "CPU " .. gov .. (cur and (" " .. math.floor(cur / 1000) .. " MHz") or "")
            .. (nice and (" (ignore nice " .. nice .. ")") or "")
    end
    local load = rd("/proc/loadavg")
    if load then
        local a, b, c = load:match("^(%S+)%s+(%S+)%s+(%S+)")
        if a then parts[#parts + 1] = "load " .. a .. " " .. b .. " " .. c end
    end
    return table.concat(parts, " · ")
end

--- `sink` (an ltn12 sink) measured for `what` ("book 12", "update").
--- While diagnostic logging is off, `sink` itself.
function XferLog.sink(sink, what)
    if not Log.enabled or type(sink) ~= "function" then return sink end
    local tag = "transfer " .. tostring(what) .. ":"
    local t0 = now()
    local st = {
        total = 0, last_at = t0, mark_at = t0, mark_bytes = 0, mark_cpu = XferLog.cpu(),
        longest = 0, longest_all = 0, lines = 0, slowest = nil, fastest = nil, started = false,
    }
    st.mark_busy, st.mark_jiffies = cpuTimes()
    local function start()
        if st.started then return end
        st.started = true
        Log.info(tag, "start ·", XferLog.probe())
    end
    local function line(t)
        local secs = t - st.mark_at
        local got = st.total - st.mark_bytes
        local rate = got / secs
        if not st.slowest or rate < st.slowest then st.slowest = rate end
        if not st.fastest or rate > st.fastest then st.fastest = rate end
        local own = (XferLog.cpu() - st.mark_cpu) / secs
        local busy, jiffies = cpuTimes()
        local all = (busy and st.mark_busy and jiffies > st.mark_jiffies)
            and (busy - st.mark_busy) / (jiffies - st.mark_jiffies) or nil
        local ps = XferLog.wifiPower()
        start()
        Log.info(tag, string.format("%s in %d s (%s), %s so far · own CPU %d%%%s · longest wait %.1f s%s",
            mb(got), math.floor(secs + 0.5), kb(got, secs), mb(st.total), math.floor(own * 100 + 0.5),
            all and string.format(", all %d%%", math.floor(all * 100 + 0.5)) or "",
            st.longest, ps and (" · Wi-Fi power saving " .. ps) or ""))
        st.lines = st.lines + 1
        st.mark_at, st.mark_bytes, st.mark_cpu = t, st.total, XferLog.cpu()
        st.mark_busy, st.mark_jiffies = busy, jiffies
        st.longest = 0
    end
    return function(chunk, err)
        local t = now()
        if chunk then
            local gap = t - st.last_at
            if gap > st.longest then st.longest = gap end
            if gap > st.longest_all then st.longest_all = gap end
            st.last_at = t
            st.total = st.total + #chunk
            if t - st.mark_at >= XferLog.EVERY then pcall(line, t) end
        else
            pcall(function()
                if st.lines == 0 and st.total < XferLog.MIN_BYTES then return end
                start()
                local secs = t - t0
                Log.info(tag, string.format("%s · %s in %d s (%s)%s · longest wait %.1f s", err and ("ended: " .. tostring(err)) or "done",
                    mb(st.total), math.floor(secs + 0.5), kb(st.total, secs),
                    st.slowest and string.format(" · slowest %s, fastest %s (of the lines above)",
                        kb(st.slowest, 1), kb(st.fastest, 1)) or "",
                    st.longest_all))
            end)
        end
        return sink(chunk, err)
    end
end

return XferLog
