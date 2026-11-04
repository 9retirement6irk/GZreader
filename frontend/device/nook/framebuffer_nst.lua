--[[--
The Nook Simple Touch's e-ink screen (TI OMAP3621, B&N's omap3epfb driver;
kernel source: github.com/felixhaedicke/nst-kernel,
drivers/video/omap3ep/omap3epfb-user.h).

An ordinary Linux framebuffer (/dev/graphics/fb0, 600 × 800) that GZreader
draws on; each refresh is an area update ioctl with a waveform:

    OMAP3EPFB_IO_REQ_AREA_UPDATE = _IOWR('O', 0x83, struct omap3epfb_update_area)
    struct omap3epfb_update_area { x0, y0, x1, y1 (last pixel), wvfid, threshold }
    waveforms: GC 0 (flash, cleans), GU 1 (grey, no flash), DU 2 (fast), A2 3

The driver ignores these while its "page flip" mode is on (Android's
redraws refresh by themselves): GZreader turns it off for as long as it
runs (sysfs pgflip_refresh = 0) and puts it back afterwards.
]]

local ffi = require("ffi")
local logger = require("logger")
local C = ffi.C

pcall(ffi.cdef, [[
struct gz_omap3epfb_update_area { unsigned int x0, y0, x1, y1, wvfid, threshold; };
]])

local REQ_AREA_UPDATE = 0xC0184F83 -- _IOWR('O', 0x83, 24 bytes)
local WVF = { gc = 0, gu = 1, du = 2, a2 = 3 }
local SYSFS = "/sys/class/graphics/fb0"

local framebuffer = {
    device_node = "/dev/graphics/fb0",
    ioctl = function(...) return C.ioctl(...) end, -- (a test replaces it)
}

local function sysWrite(name, value)
    local f = io.open(SYSFS .. "/" .. name, "w")
    if not f then return false end
    f:write(tostring(value))
    f:close()
    return true
end
local function sysRead(name)
    local f = io.open(SYSFS .. "/" .. name, "r")
    if not f then return nil end
    local s = f:read("*l")
    f:close()
    return s
end
framebuffer.sysWrite, framebuffer.sysRead = sysWrite, sysRead

function framebuffer:init()
    local f = io.open(self.device_node, "r")
    if f then f:close() else self.device_node = "/dev/fb0" end
    -- our refreshes, not the page flips'
    self.pgflip_was = sysRead("pgflip_refresh")
    sysWrite("pgflip_refresh", 0)
    framebuffer.parent.init(self)
    -- (Android may have been showing its second buffer: show the one we draw on)
    local vinfo = self._vinfo
    if vinfo and vinfo.yoffset ~= 0 then
        vinfo.yoffset = 0
        C.ioctl(self.fd, 0x4606, vinfo) -- FBIOPAN_DISPLAY
    end
    self.area = ffi.new("struct gz_omap3epfb_update_area")
    logger.info("nook touch: e-ink", self.device_node, "pgflip was", tostring(self.pgflip_was))
end

local function update(self, waveform, x, y, w, h)
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)
    x, y, w, h = self.bb:getPhysicalRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    local a = self.area
    a.x0, a.y0, a.x1, a.y1 = x, y, x + w - 1, y + h - 1
    a.wvfid = WVF[waveform] or WVF.gu
    a.threshold = 0 -- (grey, not black and white)
    if self.ioctl(self.fd, REQ_AREA_UPDATE, a) < 0 then
        logger.dbg("nook touch: area update refused", x, y, w, h, waveform)
    end
end

function framebuffer:refreshFullImp(x, y, w, h) update(self, "gc", x, y, w, h) end
function framebuffer:refreshFlashPartialImp(x, y, w, h) update(self, "gc", x, y, w, h) end
function framebuffer:refreshFlashUIImp(x, y, w, h) update(self, "gc", x, y, w, h) end
function framebuffer:refreshPartialImp(x, y, w, h) update(self, "gu", x, y, w, h) end
function framebuffer:refreshUIImp(x, y, w, h) update(self, "gu", x, y, w, h) end
function framebuffer:refreshFastImp(x, y, w, h) update(self, "du", x, y, w, h) end
function framebuffer:refreshA2Imp(x, y, w, h) update(self, "du", x, y, w, h) end

function framebuffer:close(reinit)
    -- (reinit: the base class closes and reopens; only a real close gives the page flips back)
    if not reinit then sysWrite("pgflip_refresh", self.pgflip_was or 1) end
    return framebuffer.parent.close(self, reinit)
end

framebuffer.REQ_AREA_UPDATE = REQ_AREA_UPDATE
framebuffer.WVF = WVF

return require("ffi/framebuffer_linux"):extend(framebuffer)
