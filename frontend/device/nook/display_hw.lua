--[[--
The Nook 1st Edition's two screens, as its kernel (B&N's GPL release,
github.com/JesusFreke/nook-linux-kernel) drives them:

- "bravo-vfb", a 600 × 944 RGB565 framebuffer (double buffered: 1888 rows):
  rows 0–799 are the e-ink page, rows 800–943 (the first 480 columns) the
  colour touchscreen. Panning it (or its ioctl 0x4642) copies the bottom
  part to the LCD, turned 90° by the 2D engine (bravo_virtualfb.c).
- "S1D13521", the Epson Broadsheet e-ink controller. Android's way is to
  draw the page into bravo-vfb and let the kernel convert it to grey and
  refresh the changed rows, always with the flashing GC waveform. GZreader
  instead sends its 8-bit grey page straight to the controller and picks the
  waveform for each refresh, like on the Kindles (s1d13521ioctl.h: load an
  area, write the pixels in bursts, update the area with a waveform), after
  switching the kernel's own updates off (sysfs enable = 0).
  On a real Nook (firmware 1.0.0 with nookDevs' Softroot 2.5.1) the direct
  way froze the whole Nook at the first refresh, so Android's way is the
  default; GZ_NOOK_EPD=direct tries the direct way (each refresh otherwise
  a full GC flash).

The emulator replaces this module (package.preload["device/nook/display_hw"]).
]]

local ffi = require("ffi")
local bit = require("bit")
local logger = require("logger")
local C = ffi.C

require("ffi/posix_h")
require("ffi/linux_fb_h")

pcall(ffi.cdef, [[
struct gz_s1d_params { uint16_t param[5]; };
struct gz_s1d_hwc { unsigned int addr; unsigned int value; void *buffer; };
]])

local VFB_W, EINK_H, LCD_W, LCD_H = 600, 800, 480, 144
local VFB_H = EINK_H + LCD_H

-- s1d13521ioctl.h (plain numbers, 'E' << 8 | command)
local IOC = {
    LD_IMG_AREA = 0x4522, LD_IMG_END = 0x4523, WR_REG = 0x4511,
    WAIT_DSPE_TRG = 0x4528, WAIT_DSPE_FREND = 0x4529, WAIT_DSPE_LUTFREE = 0x452A,
    UPD_FULL_AREA = 0x4534, UPD_PART_AREA = 0x4536, MEMBURSTWRITE = 0x4547,
}
local BRAVO_VFB_UPDATE = 0x4642
local DFMT_8BPP = 3
--- Broadsheet waveforms (s1d13521.h): DU fast black & white, GU grey without
--- a flash, GC grey with a flash (cleans ghosting).
local WF = { du = 1, gu = 2, gc = 3 }

local SYS_EINK = "/sys/devices/platform/s1d13521fb.0"
local SYS_LCD = "/sys/devices/platform/s3c-lcd"

local function writeFile(path, value)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(tostring(value))
    f:close()
    return true
end

local function readFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*l")
    f:close()
    return s
end

--- One write(2), whatever it answers: B&N's lcd_power and gesture_mask
--- attributes report 0 bytes written when they took the value, and C's
--- buffered output (io.write) then writes again forever.
local function writeOnce(path, value)
    local fd = C.open(path, C.O_WRONLY)
    if fd < 0 then return false end
    local s = tostring(value)
    C.write(fd, s, #s)
    C.close(fd)
    return true
end

local HW = {}

--- How e-ink refreshes are sent: "kernel" (Android's way, the default) or
--- "direct" (to the controller: froze a real Nook; GZ_NOOK_EPD=direct).
--- How the colour screen's picture gets there: "vfb" (the kernel's 2D
--- engine copy) or "direct" (into its framebuffer): direct when the kernel
--- has no 2D engine device.
function HW.lcdMode()
    local m = os.getenv("GZ_NOOK_LCD")
    if m == "vfb" or m == "direct" then return m end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs.attributes("/dev/s3c-g2d", "mode") then return "vfb" end
    return "direct"
end

function HW.epdMode()
    return os.getenv("GZ_NOOK_EPD") == "direct" and "direct" or "kernel"
end

--- The colour screen and its touch panel as Android leaves them asleep
--- (B&N's kernel): the "picture tube" LCD powered down (lcd_power 0, an SPI
--- device), the backlight off, and the Synaptics panel reporting only taps
--- (gesture_mask 1: a tap sends Home, which wakes Android) instead of
--- finger motion (16). GZreader started with the colour screen black and
--- deaf to touches: Android had put it to sleep before it was paused. (The
--- LCD controller itself is stopped by the kernel's early suspend, which
--- platform/nook/gzreader.sh undoes: "on" in /sys/power/state.)
local SYS_SPI, SYS_I2C = "/sys/bus/spi/devices", "/sys/bus/i2c/devices"
-- linux/fb.h: FBIOBLANK takes the blank level itself as its argument
local FBIOBLANK, BLANK_UNBLANK, BLANK_POWERDOWN = 0x4611, 0, 4
local GESTURE_MOTION = 16

--- The first <dir>/*/<name> that exists, or nil.
local function findAttr(dir, name)
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then return nil end
    local okd, iter, state = pcall(lfs.dir, dir)
    if not okd then return nil end
    for entry in iter, state do
        if entry ~= "." and entry ~= ".." then
            local path = dir .. "/" .. entry .. "/" .. name
            if lfs.attributes(path, "mode") == "file" then return path end
        end
    end
end

--- The system calls (a test replaces them).
HW.sys = {
    find = findAttr,
    writeOnce = writeOnce,
    open = function(...) return C.open(...) end,
    close = function(...) return C.close(...) end,
    ioctl = function(...) return C.ioctl(...) end,
    mmap = function(...) return C.mmap(...) end,
    munmap = function(...) return C.munmap(...) end,
    write = writeFile,
    read = readFile,
}

--- Open both devices. Returns HW (ok) or nil, error.
function HW:open()
    local finfo = ffi.new("struct fb_fix_screeninfo")
    local vinfo = ffi.new("struct fb_var_screeninfo")
    for _i, pattern in ipairs({ "/dev/graphics/fb%d", "/dev/fb%d" }) do
        for n = 0, 3 do
            local path = pattern:format(n)
            local fd = HW.sys.open(path, bit.bor(C.O_RDWR, C.O_CLOEXEC))
            if fd >= 0 then
                local id = HW.sys.ioctl(fd, C.FBIOGET_FSCREENINFO, finfo) == 0 and ffi.string(finfo.id) or ""
                if id:find("bravo%-vfb") and not self.vfb_fd then
                    self.vfb_fd, self.vfb_path = fd, path
                elseif id:find("S1D13521") and not self.epd_fd then
                    self.epd_fd, self.epd_path = fd, path
                elseif id:find("s3cfb") and not self.lcdfb_fd then
                    self.lcdfb_fd = fd -- (the colour screen's LCD controller: its power is FBIOBLANK)
                else
                    HW.sys.close(fd)
                end
            end
        end
        if self.vfb_fd then break end
    end
    if not self.vfb_fd then return nil, "no bravo-vfb framebuffer (not a Nook 1st Edition?)" end
    HW.sys.ioctl(self.vfb_fd, C.FBIOGET_FSCREENINFO, finfo)
    HW.sys.ioctl(self.vfb_fd, C.FBIOGET_VSCREENINFO, vinfo)
    self.line = finfo.line_length
    self.size = finfo.smem_len
    self.yoffset = vinfo.yoffset
    self.vinfo = vinfo
    local map = HW.sys.mmap(nil, self.size, bit.bor(C.PROT_READ, C.PROT_WRITE), C.MAP_SHARED, self.vfb_fd, 0)
    if tonumber(ffi.cast("intptr_t", map)) == C.MAP_FAILED then return nil, "can't map bravo-vfb" end
    self.map = ffi.cast("uint8_t *", map)
    -- what Android showed on the LCD, for when GZreader quits
    self.saved_lcd = ffi.new("uint8_t[?]", LCD_H * self.line)
    ffi.copy(self.saved_lcd, self.map + (self.yoffset + EINK_H) * self.line, LCD_H * self.line)
    -- always show buffer 0 from now on
    if self.yoffset ~= 0 then
        self.vinfo.yoffset = 0
        HW.sys.ioctl(self.vfb_fd, 0x4606, self.vinfo) -- (FBIOPAN_DISPLAY)
        self.yoffset = 0
    end
    self.direct = self.epd_fd ~= nil and HW.epdMode() == "direct"
    if self.direct then
        self.kernel_enable = HW.sys.read(SYS_EINK .. "/enable")
        if not HW.sys.write(SYS_EINK .. "/enable", 0) then
            logger.warn("nook: can't switch the kernel's e-ink updates off; using its refreshes")
            self.direct = false
        end
    end
    self:wakeLcd()
    self.params = ffi.new("struct gz_s1d_params")
    self.hwc = ffi.new("struct gz_s1d_hwc")
    logger.info("nook: vfb", self.vfb_path, "e-ink", self.epd_path or "-", self.direct and "direct" or "through the kernel")
    return self
end

local function cmd(self, ioc, ...)
    local n = select("#", ...)
    for i = 1, n do self.params.param[i - 1] = select(i, ...) end
    return HW.sys.ioctl(self.epd_fd, ioc, self.params)
end

--- Show rows y .. y+h-1 of `bb` (BB8, 600 wide, contiguous) with a waveform
--- on the area x, y, w, h: "du", "gu" or "gc"; flash: a full (flashing) update.
function HW:eink(bb, x, y, w, h, waveform, flash)
    if self.direct then
        -- (whole rows go over: one contiguous burst from the page buffer)
        cmd(self, IOC.WAIT_DSPE_TRG)
        cmd(self, IOC.WAIT_DSPE_FREND) -- (one update at a time: no LUT clashes)
        cmd(self, IOC.LD_IMG_AREA, bit.lshift(DFMT_8BPP, 4), 0, y, VFB_W, h)
        cmd(self, IOC.WR_REG, 0x154)
        self.hwc.value = VFB_W * h
        self.hwc.buffer = ffi.cast("uint8_t *", bb.data) + y * bb.stride
        HW.sys.ioctl(self.epd_fd, IOC.MEMBURSTWRITE, self.hwc)
        cmd(self, IOC.LD_IMG_END)
        -- the controller wants an even x and width
        local x2 = x + w
        x = x - x % 2
        x2 = math.min(VFB_W, x2 + x2 % 2)
        local arg = bit.lshift(WF[waveform] or WF.gu, 8) -- (LUT 0, no border update)
        cmd(self, flash and IOC.UPD_FULL_AREA or IOC.UPD_PART_AREA, arg, x, y, x2 - x, h)
        cmd(self, IOC.WAIT_DSPE_TRG)
        return
    end
    -- Android's way: RGB565 into bravo-vfb, then the kernel converts and refreshes everything
    local line = self.line
    for row = y, y + h - 1 do
        local src = ffi.cast("uint8_t *", bb.data) + row * bb.stride
        local dst = ffi.cast("uint16_t *", self.map + row * line)
        for col = 0, VFB_W - 1 do
            local g = src[col]
            dst[col] = bit.bor(bit.lshift(bit.rshift(g, 3), 11), bit.lshift(bit.rshift(g, 2), 5), bit.rshift(g, 3))
        end
    end
    HW.sys.write(SYS_EINK .. "/redraw", 1)
end

--- The colour screen's own framebuffer (s3cfb: 240 × 480 portrait, RGB565,
--- the 480 × 144 picture turned 90° in columns 96–239). The kernel copies
--- the vfb's rows 800–943 there with the 2D engine; on a Nook whose kernel
--- has no 2D engine device (/dev/s3c-g2d) that copy never happens and the
--- colour screen kept Android's last picture, so GZreader writes it there
--- itself. GZ_NOOK_LCD=vfb / direct forces one way; GZ_NOOK_LCD_ROT=ccw
--- turns it the other way.
local LCD_FB_W, LCD_FB_H, LCD_FB_X = 240, 480, 96
function HW:openLcdFb()
    if not self.lcdfb_fd then return false end
    local finfo = ffi.new("struct fb_fix_screeninfo")
    if HW.sys.ioctl(self.lcdfb_fd, C.FBIOGET_FSCREENINFO, finfo) ~= 0 then return false end
    self.lcd_line = finfo.line_length
    self.lcd_size = finfo.smem_len
    local map = HW.sys.mmap(nil, self.lcd_size, bit.bor(C.PROT_READ, C.PROT_WRITE), C.MAP_SHARED, self.lcdfb_fd, 0)
    if tonumber(ffi.cast("intptr_t", map)) == C.MAP_FAILED then return false end
    self.lcd_map = ffi.cast("uint8_t *", map)
    self.lcd_var = ffi.new("struct fb_var_screeninfo")
    HW.sys.ioctl(self.lcdfb_fd, C.FBIOGET_VSCREENINFO, self.lcd_var)
    return true
end

function HW:lcdDirect(bb)
    local line2 = self.lcd_line / 2
    local dst = ffi.cast("uint16_t *", self.lcd_map)
    local ccw = self.lcd_ccw
    for y = 0, LCD_H - 1 do
        local src = ffi.cast("uint16_t *", ffi.cast("uint8_t *", bb.data) + y * bb.stride)
        if ccw then
            local col = LCD_FB_X + y
            for x = 0, LCD_W - 1 do dst[(LCD_FB_H - 1 - x) * line2 + col] = src[x] end
        else
            local col = LCD_FB_X + (LCD_H - 1 - y)
            for x = 0, LCD_W - 1 do dst[x * line2 + col] = src[x] end
        end
    end
    -- (show its first buffer)
    if self.lcd_var.yoffset ~= 0 then
        self.lcd_var.yoffset = 0
        HW.sys.ioctl(self.lcdfb_fd, 0x4606, self.lcd_var) -- (FBIOPAN_DISPLAY)
    end
end

--- Copy the colour screen's picture (480 × 144, RGB565 BlitBuffer) to the LCD.
function HW:lcd(bb)
    if self.lcd_direct == nil then
        local mode = HW.lcdMode()
        self.lcd_direct = mode == "direct" and self:openLcdFb() or false
        self.lcd_ccw = os.getenv("GZ_NOOK_LCD_ROT") == "ccw"
        logger.info("nook: colour screen", self.lcd_direct and ("written directly (" .. (self.lcd_ccw and "ccw" or "cw") .. ")")
            or "through the vfb (2D engine)")
    end
    if self.lcd_direct then return self:lcdDirect(bb) end
    local line = self.line
    for row = 0, LCD_H - 1 do
        ffi.copy(self.map + (EINK_H + row) * line, ffi.cast("uint8_t *", bb.data) + row * bb.stride, LCD_W * 2)
    end
    HW.sys.ioctl(self.vfb_fd, BRAVO_VFB_UPDATE, nil)
end

--- Wake the colour screen and its touch panel, keeping how Android left
--- them (put back by close).
function HW:wakeLcd()
    self.tube = self.tube or HW.sys.find(SYS_SPI, "lcd_power")
    self.gesture = self.gesture or HW.sys.find(SYS_I2C, "gesture_mask")
    self.saved_power = {
        lcd = HW.sys.read(SYS_LCD .. "/lcd_power"),
        tube = self.tube and HW.sys.read(self.tube),
        backlight = HW.sys.read(SYS_LCD .. "/backlight_power"),
        level = HW.sys.read(SYS_LCD .. "/backlight_level"),
        gesture = self.gesture and HW.sys.read(self.gesture),
    }
    -- The LCD controller: Android blanks it (FBIOBLANK powerdown) when the
    -- screen goes off; its sysfs lcd_power only reads. The backlight doesn't
    -- light while it's off (the kernel waits for it).
    if self.lcdfb_fd then
        HW.sys.ioctl(self.lcdfb_fd, FBIOBLANK, ffi.cast("unsigned long", BLANK_UNBLANK))
    end
    if self.gesture then HW.sys.writeOnce(self.gesture, GESTURE_MOTION) end
    -- (Android dims to 8 before turning it off: its normal level is 64)
    local level = tonumber(self.saved_power.level or "")
    self:backlight(true, (not level or level < 32) and 64 or nil)
    logger.info("nook: colour screen woken (LCD was", tostring(self.saved_power.lcd), "now", tostring(HW.sys.read(SYS_LCD .. "/lcd_power")),
        "; tube", tostring(self.tube), "was", tostring(self.saved_power.tube),
        "; backlight was", tostring(self.saved_power.backlight), "level", tostring(self.saved_power.level),
        "; touch", tostring(self.gesture), "was", tostring(self.saved_power.gesture), ")")
end

--- LCD backlight: on/off and level (0–255; the Nook's default is 64).
--- On also powers the LCD itself up (the kernel doesn't light the
--- backlight while the "picture tube" is powered down).
function HW:backlight(on, level)
    if on and self.tube then HW.sys.writeOnce(self.tube, 1) end
    if level then HW.sys.write(SYS_LCD .. "/backlight_level", math.floor(level)) end
    HW.sys.write(SYS_LCD .. "/backlight_power", on and 1 or 0)
end

function HW:backlightLevel()
    return tonumber(HW.sys.read(SYS_LCD .. "/backlight_level") or "")
end

--- Give the screens back to Android (on exit): its LCD picture, the
--- kernel's e-ink updates, and a full redraw of Android's page.
function HW:close()
    if self.map then
        ffi.copy(self.map + EINK_H * self.line, self.saved_lcd, LCD_H * self.line)
        HW.sys.ioctl(self.vfb_fd, BRAVO_VFB_UPDATE, nil)
    end
    if self.direct then HW.sys.write(SYS_EINK .. "/enable", self.kernel_enable or 1) end
    HW.sys.write(SYS_EINK .. "/redraw", 1)
    -- the colour screen and touch panel as Android left them (it wakes them itself)
    local saved = self.saved_power
    if saved then
        if self.gesture and saved.gesture then HW.sys.writeOnce(self.gesture, saved.gesture) end
        if saved.level then HW.sys.write(SYS_LCD .. "/backlight_level", saved.level) end
        if saved.backlight then HW.sys.write(SYS_LCD .. "/backlight_power", saved.backlight) end
        if self.tube and saved.tube then HW.sys.writeOnce(self.tube, saved.tube) end
        if self.lcdfb_fd and saved.lcd == "0" then
            HW.sys.ioctl(self.lcdfb_fd, FBIOBLANK, ffi.cast("unsigned long", BLANK_POWERDOWN))
        end
        self.saved_power = nil
    else
        self:backlight(true)
    end
    if self.map then HW.sys.munmap(self.map, self.size); self.map = nil end
    if self.lcd_map then HW.sys.munmap(self.lcd_map, self.lcd_size); self.lcd_map = nil end
    if self.vfb_fd then HW.sys.close(self.vfb_fd); self.vfb_fd = nil end
    if self.epd_fd then HW.sys.close(self.epd_fd); self.epd_fd = nil end
    if self.lcdfb_fd then HW.sys.close(self.lcdfb_fd); self.lcdfb_fd = nil end
end

HW.EINK_W, HW.EINK_H, HW.LCD_W, HW.LCD_H, HW.VFB_H = VFB_W, EINK_H, LCD_W, LCD_H, VFB_H

return HW
