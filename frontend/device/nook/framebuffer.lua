--[[--
The Nook 1st Edition's e-ink screen for KOReader: an 8-bit grey page
(600 × 800) that GZreader draws on, sent to the e-ink controller area by
area with a waveform per refresh (display_hw.lua). The colour touchscreen
under it is the LCD module's (device/nook/lcd.lua), through the same
display_hw.
]]

local BB = require("ffi/blitbuffer")
local logger = require("logger")

local framebuffer = {}

function framebuffer:init()
    local HW = require("device/nook/display_hw")
    local ok, err = HW:open()
    if not ok then error("Nook screen: " .. tostring(err)) end
    self.hw = HW
    self.bb = BB.new(HW.EINK_W, HW.EINK_H, BB.TYPE_BB8)
    self.bb:fill(BB.COLOR_WHITE)
    framebuffer.parent.init(self)
end

local function update(self, waveform, flash, x, y, w, h)
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)
    x, y, w, h = self.bb:getPhysicalRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    local ok, err = pcall(self.hw.eink, self.hw, self.bb, x, y, w, h, waveform, flash)
    if not ok then logger.warn("nook: e-ink refresh failed:", err) end
end

function framebuffer:refreshFullImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshFlashPartialImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshFlashUIImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshPartialImp(x, y, w, h) update(self, "gu", false, x, y, w, h) end
function framebuffer:refreshUIImp(x, y, w, h) update(self, "gu", false, x, y, w, h) end
function framebuffer:refreshFastImp(x, y, w, h) update(self, "du", false, x, y, w, h) end
function framebuffer:refreshA2Imp(x, y, w, h) update(self, "du", false, x, y, w, h) end

function framebuffer:close()
    if self.hw then pcall(self.hw.close, self.hw) end
    if self.bb then self.bb:free(); self.bb = nil end
end

return require("ffi/framebuffer"):extend(framebuffer)
