--[[--
The Nook 1st Edition's e-ink controller, one command at a time: what
GZreader's direct refreshes do (frontend/device/nook/display_hw.lua), with
each step written to a log *before* it runs (synchronously, so it's on the
disk even if the Nook then freezes). The last "step" line without its "ok"
is the command that hung.

Started by the start script instead of GZreader:
    adb shell "GZ_NOOK_EINK_TEST=1 sh /data/gzreader/gzreader.sh"
Log: /data/gzreader/eink-test.log. A small square near the top left of the
e-ink page turns black, then the page is redrawn the Nook's way.

The first run hung at the first WAIT_DSPE_TRG: B&N's driver keeps the
controller asleep between updates (s1d13521_lock/unlock: RUN_SYS before,
SLP after) and the driver's ioctls don't wake it, so a display engine
command to a sleeping controller never answers (the kernel then spins on
the ready line with the big kernel lock held). So, as the driver itself
does: wake it, clear its interrupts, and wait by reading the display
engine status register (0x338) rather than with the WAIT_DSPE commands.
]]

local ffi = require("ffi")
local bit = require("bit")
-- (the tests pass their own C library and folders: nook_test.lua)
local C = rawget(_G, "GZ_EINK_C") or ffi.C

require("ffi/posix_h")
require("ffi/linux_fb_h")
pcall(ffi.cdef, [[
struct gzt_params { uint16_t param[5]; };
struct gzt_hwc { unsigned int addr; unsigned int value; void *buffer; };
]])

local LOG = rawget(_G, "GZ_EINK_LOG") or ((os.getenv("GZ") or "/data/gzreader") .. "/eink-test.log")
local logfd = C.open(LOG, bit.bor(C.O_WRONLY, C.O_CREAT, C.O_APPEND), ffi.cast("int", 420))

local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local line = os.date("%H:%M:%S ") .. table.concat(parts, " ") .. "\n"
    io.stdout:write(line)
    io.stdout:flush()
    if logfd >= 0 then C.write(logfd, line, #line); C.fsync(logfd) end
end

local function sysfs(path, value)
    if value == nil then
        local f = io.open(path, "r")
        local v = f and f:read("*l")
        if f then f:close() end
        return v
    end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(tostring(value))
    f:close()
    return true
end

local SYS_EINK = rawget(_G, "GZ_EINK_SYS") or "/sys/devices/platform/s1d13521fb.0"
local IOC = {
    REGREAD = 0x4540, REGWRITE = 0x4541, WR_REG = 0x4511, LD_IMG_AREA = 0x4522, LD_IMG_END = 0x4523,
    UPD_PART_AREA = 0x4536, MEMBURSTWRITE = 0x4547, RUN_SYS = 0x4502, SLP = 0x4505,
}
local sleep_ms = rawget(_G, "GZ_EINK_SLEEP") or function(ms) C.usleep(ms * 1000) end
local params = ffi.new("struct gzt_params")
local hwc = ffi.new("struct gzt_hwc")

local step = 0
local function run(what, fn)
    step = step + 1
    log("step", step, what)
    local ok, r = pcall(fn)
    log("  ok", step, ok and tostring(r) or ("error " .. tostring(r)))
    return r
end

log("---- e-ink test")
local fd = -1
for n = 0, 3 do
    local path = "/dev/graphics/fb" .. n
    local f = C.open(path, C.O_RDWR)
    if f >= 0 then
        local fix = ffi.new("struct fb_fix_screeninfo")
        C.ioctl(f, C.FBIOGET_FSCREENINFO, fix)
        local id = ffi.string(fix.id)
        log("framebuffer", path, id)
        if id:find("S1D13521") then fd = f else C.close(f) end
    end
end
if fd < 0 then
    log("no S1D13521 framebuffer")
    if logfd >= 0 then C.close(logfd) end
    return false
end

local function reg(addr)
    hwc.addr, hwc.value = addr, 0
    local r = C.ioctl(fd, IOC.REGREAD, hwc)
    return string.format("reg 0x%04x = 0x%04x (ioctl %d)", addr, tonumber(hwc.value), r)
end
local function cmd(ioc, ...)
    for i = 1, 5 do params.param[i - 1] = select(i, ...) or 0 end
    return C.ioctl(fd, ioc, params)
end

local function regValue(addr)
    hwc.addr, hwc.value = addr, 0
    C.ioctl(fd, IOC.REGREAD, hwc)
    return tonumber(hwc.value)
end
local function waitBit(bitpos, timeout_ms)
    -- (the driver: bs_cmd_wait_for_bit / s1d13521fb_wait_for_trigger)
    local waited = 0
    while bit.band(regValue(0x0338), bit.lshift(1, bitpos)) ~= 0 do
        if waited >= timeout_ms then return string.format("still set after %d ms", waited) end
        sleep_ms(5)
        waited = waited + 5
    end
    return string.format("clear after %d ms", waited)
end

log("kernel updates (enable):", sysfs(SYS_EINK .. "/enable"))
run("read the product code (0x0000)", function() return reg(0x0000) end)
run("read the system status (0x000A)", function() return reg(0x000A) end)
run("read the display engine status (0x0338)", function() return reg(0x0338) end)
run("kernel updates off (enable = 0)", function() return sysfs(SYS_EINK .. "/enable", 0) end)
run("RUN_SYS: wake the controller (the driver keeps it asleep)", function() return cmd(IOC.RUN_SYS) end)
run("clear its interrupts (0x033A = 0xFFFF)", function()
    hwc.addr, hwc.value = 0x033A, 0xFFFF
    return C.ioctl(fd, IOC.REGWRITE, hwc)
end)
run("read the system status again (0x000A)", function() return reg(0x000A) end)
run("wait for the trigger to be free (0x338 bit 0)", function() return waitBit(0, 1000) end)
run("wait for the frame end (0x338 bit 3)", function() return waitBit(3, 2000) end)
local lut = 0
run("free LUTs (0x0336)", function()
    local busy = regValue(0x0336)
    for i = 0, 14 do
        if bit.band(busy, bit.lshift(1, i)) == 0 then lut = i; break end
    end
    return string.format("busy 0x%04x, using LUT %d", busy, lut)
end)
run("LD_IMG_AREA 8 bpp, rows 32-47 (whole rows, as the driver does)", function() return cmd(IOC.LD_IMG_AREA, bit.lshift(3, 4), 0, 32, 600, 16) end)
run("WR_REG 0x154", function() return cmd(IOC.WR_REG, 0x154) end)
local black = ffi.new("uint8_t[?]", 600 * 16)
run("MEMBURSTWRITE 9600 bytes", function()
    hwc.addr, hwc.value, hwc.buffer = 0, 600 * 16, black
    return C.ioctl(fd, IOC.MEMBURSTWRITE, hwc)
end)
run("LD_IMG_END", function() return cmd(IOC.LD_IMG_END) end)
run("UPD_PART_AREA, DU waveform, 16 x 16 at 32, 32", function()
    return cmd(IOC.UPD_PART_AREA, bit.bor(bit.lshift(1, 8), bit.lshift(lut, 4)), 32, 32, 16, 16)
end)
run("wait for the trigger (0x338 bit 0)", function() return waitBit(0, 1000) end)
run("wait for the frame end (0x338 bit 3)", function() return waitBit(3, 2000) end)
run("read the display engine status (0x0338)", function() return reg(0x0338) end)
sleep_ms(1500) -- (time to see the square)
run("SLP: the controller back to sleep (as the driver leaves it)", function() return cmd(IOC.SLP) end)
run("kernel updates back on (enable = 1)", function() return sysfs(SYS_EINK .. "/enable", 1) end)
run("the Nook's own full redraw", function() return sysfs(SYS_EINK .. "/redraw", 1) end)
log("---- e-ink test done: every step answered")
C.close(fd)
if logfd >= 0 then C.close(logfd) end
return true
