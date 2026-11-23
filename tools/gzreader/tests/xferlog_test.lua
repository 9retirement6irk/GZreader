-- A download's speed in gzreader.log (gzreader_xferlog.lua): a start line
-- with what could hold it back, a line every 15 s, a summary; nothing while
-- diagnostic logging is off or for a tiny transfer; data passes untouched.
--   luajit xferlog_test.lua <repo>
local REPO = arg[1] or "../../.."
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. REPO .. "/frontend/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local lines = {}
local Log = { enabled = true }
function Log.info(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(t, " ")
end
package.loaded["gzreader_log"] = Log
local X = require("gzreader_xferlog")

-- a fake device: its files, clock, processor time and Wi-Fi
local files = {
    ["/proc/sys/net/ipv4/tcp_rmem"] = "4096\t87380\t1048576",
    ["/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"] = "ondemand",
    ["/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"] = "996000",
    ["/sys/devices/system/cpu/cpufreq/ondemand/ignore_nice_load"] = "1",
    ["/proc/loadavg"] = "1.20 0.90 0.50 2/80 1234",
}
local jiffies = { busy = 0, total = 0 }
local function stat() return string.format("cpu  %d 0 0 %d 0 0 0 0 0 0", jiffies.busy, jiffies.total - jiffies.busy) end
X.read = function(path)
    if path == "/proc/stat" then return stat() end
    return files[path]
end
local t, cpu = 1000, 0
X.clock = function() return t end
X.cpu = function() return cpu end
local ps = "on"
X.wifi = function() return ps end

local got = {}
local function inner(chunk, err)
    got[#got + 1] = chunk or ("<end " .. tostring(err) .. ">")
    return 1
end

print("== signal strength")
;(function()
    package.loaded["gzreader_wifips"] = package.loaded["gzreader_wifips"] or { ifname = function() return "wlan0" end, get = function() return ps end }
    local head = "Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n"
    X.readFile = function() return head .. " wlan0: 0000   54.  -56.  -256        0      0      0      0      0        0\n" end
    check(X.signal() == -56, "the signal in dBm from the driver's numbers")
    X.readFile = function() return head .. "  eth0: 0000   54.  -40.  -256  0 0 0 0 0 0\n wlan0: 0000   30   200   0  0 0 0 0 0 0\n" end
    check(X.signal() == -56, "a driver that gives it as a byte; another interface's line isn't taken")
    X.readFile = function() return head end
    check(X.signal() == nil, "Wi-Fi off: no signal, nothing said")
    X.readFile = function() return nil end
    check(X.signal() == nil and X.probe():find("signal", 1, true) == nil, "no such file: nothing said")
    X.readFile = function() return head .. " wlan0: 0000   54.  -71.  -256  0 0 0 0 0 0\n" end
    check(X.probe():find("Wi-Fi power saving on · signal -71 dBm · TCP receive buffer", 1, true) ~= nil, "the start line has the signal " .. X.probe())
    X.readFile = function() return nil end
end)()

print("== download speed log")

;(function()
    Log.enabled = false
    local s = X.sink(inner, "book 1")
    check(s == inner, "logging off: the sink as it was (nothing measured)")
    Log.enabled = true
    check(X.sink(nil, "book 1") == nil, "no sink: nothing to wrap")
end)()

;(function()
    lines, got = {}, {}
    local s = X.sink(inner, "book 12")
    check(s ~= inner, "logging on: the sink is measured")
    local block = string.rep("x", 2048)
    local check_ret
    -- 30 s at ~34 KB/s: 17 blocks a second; the processor 97% busy, ours 2%
    for _sec = 1, 31 do
        for _i = 1, 17 do
            t = t + 1 / 17
            check_ret = s(block)
        end
        cpu = cpu + 0.02
        jiffies.busy, jiffies.total = jiffies.busy + 97, jiffies.total + 100
        if _sec == 20 then ps = "off" end
    end
    check(check_ret == 1, "the sink's answer passes through")
    check(#got == 527 and got[1] == block, "every piece of data reaches the file's sink, unchanged")
    check(#lines == 3, "a start line and a line every 15 s (" .. #lines .. ")")
    local first = lines[1] or ""
    check(first:find("transfer book 12: start", 1, true) ~= nil, "start line names the transfer")
    check(first:find("Wi-Fi power saving on", 1, true) ~= nil, "start: Wi-Fi power saving")
    check(first:find("TCP receive buffer 4096 87380 1048576", 1, true) ~= nil, "start: TCP receive buffer")
    check(first:find("CPU ondemand 996 MHz (ignore nice 1)", 1, true) ~= nil, "start: CPU governor, speed, ignore nice")
    check(first:find("load 1.20 0.90 0.50", 1, true) ~= nil, "start: load")
    local l2 = lines[2] or ""
    check(l2:find("in 15 s (34 KB/s)", 1, true) ~= nil, "15 s line: speed (" .. l2 .. ")")
    check(l2:find("own CPU 2%, all 97%", 1, true) ~= nil, "15 s line: own and whole processor use")
    check(l2:find("longest wait 0.1 s", 1, true) ~= nil, "15 s line: longest wait between pieces")
    check(l2:find("Wi-Fi power saving on", 1, true) ~= nil, "15 s line: Wi-Fi power saving now")
    check((lines[3] or ""):find("Wi-Fi power saving off", 1, true) ~= nil, "a change of power saving shows")
    -- stopped for 20 s (SIGSTOP), then faster
    t = t + 20
    s(block)
    for _i = 1, 600 do t = t + 0.002; s(block) end
    s(nil)
    check(got[#got] == "<end nil>", "the end reaches the file's sink (it closes the file)")
    local last = lines[#lines] or ""
    check(last:find("transfer book 12: done", 1, true) ~= nil, "summary at the end (" .. last .. ")")
    check(last:find("longest wait 20.0 s", 1, true) ~= nil, "summary: the stop shows as the longest wait")
    local stopped = lines[#lines - 1] or ""
    check(stopped:find("(2 KB/s)", 1, true) ~= nil and stopped:find("longest wait 20.0 s", 1, true) ~= nil,
        "a stopped stretch: hardly anything and the long wait in its line (" .. stopped .. ")")
    check(last:find("slowest 2 KB/s, fastest 34 KB/s", 1, true) ~= nil, "summary: slowest and fastest line")
    for _i, l in ipairs(lines) do
        if l:find("transfer book 12: start", 1, true) and _i > 1 then check(false, "only one start line") end
    end
    ps = "on"
end)()

;(function()
    lines, got = {}, {}
    local s = X.sink(inner, "update")
    s(string.rep("x", 300)) -- a redirect's body
    s(nil)
    check(#lines == 0, "a small transfer with no 15 s line logs nothing (redirects)")
    s = X.sink(inner, "update")
    t = t + 1
    s(string.rep("x", 300000))
    s(nil, "timeout")
    check(#lines == 2 and (lines[2] or ""):find("ended: timeout", 1, true) ~= nil, "a short but real transfer: start and why it ended")
end)()

;(function()
    -- the real Wi-Fi reading (no wlan0 here): an answer or a reason, never an error
    X.wifi = nil
    package.loaded["ui/network/manager"] = { getNetworkInterfaceName = function() return "gz-test-none0" end }
    local okc, st, why = pcall(X.wifiPower)
    check(okc and (st == "on" or st == "off" or (st == nil and why ~= nil)), "Wi-Fi power saving read through the ioctl, or why not (" .. tostring(st or why) .. ")")
    local okp, line = pcall(X.probe)
    check(okp and line:find("Wi-Fi power saving", 1, true) ~= nil, "probe works on a machine without the Kindle's files")
end)()

;(function()
    local function src(p) local f = assert(io.open(REPO .. "/" .. p)); local s = f:read("*a"); f:close(); return s end
    local mod = src("plugins/gzreader.koplugin/gzreader_xferlog.lua")
    check(not mod:find("popen", 1, true) and not mod:find("os.execute", 1, true), "no shell commands (no fork of GZreader per line)")
    -- (/proc/net/wireless holds the interface's name and signal numbers, no network name;
    -- XferLog.signal gives back one number from it and nothing else, checked above)
    check(not mod:find("ESSID", 1, true) and not mod:find("wpa", 1, true) and not mod:find("iwgetid", 1, true) and not mod:find("iwconfig", 1, true)
        and select(2, mod:gsub("/proc/net/wireless", "")) <= 3 and type(X.signal) == "function",
        "no Wi-Fi network name is read (only the signal's number)")
    check(src("plugins/gzreader.koplugin/gzreader_api.lua"):find('require("gzreader_xferlog").sink(ltn12.sink.file(fh), "book "', 1, true) ~= nil,
        "book downloads are measured")
    check(src("plugins/gzreader.koplugin/gzreader_update.lua"):find('require("gzreader_xferlog").sink(ltn12.sink.file(fh), "update")', 1, true) ~= nil,
        "update downloads are measured")
end)()

print(string.format("download speed log: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
