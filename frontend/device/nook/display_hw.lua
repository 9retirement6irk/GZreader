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
  GZ_NOOK_EPD=kernel uses Android's way instead (each refresh a full GC
  flash): the fallback if the direct way misbehaves on a real Nook.

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

local HW = {}

--- The system calls (a test replaces them).
HW.sys = {
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
    local mode = os.getenv("GZ_NOOK_EPD")
    self.direct = self.epd_fd ~= nil and mode ~= "kernel"
    if self.direct then
        self.kernel_enable = HW.sys.read(SYS_EINK .. "/enable")
        if not HW.sys.write(SYS_EINK .. "/enable", 0) then
            logger.warn("nook: can't switch the kernel's e-ink updates off; using its refreshes")
            self.direct = false
        end
    end
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

--- Copy the colour screen's picture (480 × 144, RGB565 BlitBuffer) to the LCD.
function HW:lcd(bb)
    local line = self.line
    for row = 0, LCD_H - 1 do
        ffi.copy(self.map + (EINK_H + row) * line, ffi.cast("uint8_t *", bb.data) + row * bb.stride, LCD_W * 2)
    end
    HW.sys.ioctl(self.vfb_fd, BRAVO_VFB_UPDATE, nil)
end

--- LCD backlight: on/off and level (0–255; the Nook's default is 64).
function HW:backlight(on, level)
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
    self:backlight(true)
    if self.map then HW.sys.munmap(self.map, self.size); self.map = nil end
    if self.vfb_fd then HW.sys.close(self.vfb_fd); self.vfb_fd = nil end
    if self.epd_fd then HW.sys.close(self.epd_fd); self.epd_fd = nil end
end

HW.EINK_W, HW.EINK_H, HW.LCD_W, HW.LCD_H, HW.VFB_H = VFB_W, EINK_H, LCD_W, LCD_H, VFB_H

return HW
