--[[--
The Barnes & Noble Nook Simple Touch (2011, "gossamer"; also the Simple
Touch with GlowLight, 2012): a 6" e-ink touchscreen (600 × 800, infrared
zForce: one finger), four page buttons (two each side), the "n" button under
the screen and a power button; the GlowLight model has a frontlight.
Android 2.1 on Linux 2.6.29, TI OMAP3621 (ARM Cortex-A8), 256 MB.

Like the Nook 1st Edition, GZreader runs as a Linux program with the Kindle
2/3/DX build's binaries (ARMv6 code runs on the Cortex-A8) and its own C
library; platform/nook/gzreader.sh starts it. Used by touch, like the
Kindle Touch.
]]

local Generic = require("device/generic/device")
local Nook1 = require("device/nook/device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local UIManager

local function yes() return true end
local function no() return false end
local readLine = Nook1.readLine

-- linux/input.h: what the Simple Touch's buttons send (B&N's board file:
-- the page buttons are a TWL4030 keypad, "n" and power GPIO keys)
local KEY_NEXT, KEY_PREVIOUS = 407, 412

--- The GlowLight's frontlight: an LED driver channel, 0–255 (shown as 0–100).
local FL = "/sys/class/leds/lcd-backlight/brightness"

local NSTPowerD = Nook1.PowerD
NSTPowerD.fl_min, NSTPowerD.fl_max = 0, 100
function NSTPowerD:frontlightIntensityHW()
    local v = tonumber(readLine(FL) or "") or 0
    return math.floor(v * 100 / 255 + 0.5)
end
function NSTPowerD:setIntensityHW(intensity)
    local f = io.open(FL, "w")
    if not f then return end
    f:write(tostring(math.floor(intensity * 255 / 100 + 0.5)))
    f:close()
    self:_decideFrontlightState()
end
function NSTPowerD:isFrontlightOnHW() return (tonumber(readLine(FL) or "") or 0) > 0 end

local NookTouch = Generic:extend{
    model = "NookTouch",
    isNook = yes,
    isTouchDevice = yes,
    hasMultitouch = no, -- (the zForce panel's single-touch protocol)
    hasKeys = yes,
    hasDPad = no,
    hasFewKeys = yes,
    hasFrontlight = function() return lfs.attributes(FL, "mode") == "file" end,
    hasWifiToggle = no, -- (Android keeps Wi-Fi up underneath)
    hasWifiManager = no,
    canSuspend = yes,
    canReboot = no,
    canPowerOff = no,
    supportsScreensaver = yes,
    hasExitOptions = no,
    home_dir = "/media", -- (the Simple Touch's own storage, "NOOK" over USB)
}

function NookTouch:init()
    Nook1.nookStrings({})
    self.home_dir = os.getenv("GZ_NOOK_HOME") or self.home_dir
    if lfs.attributes(self.home_dir, "mode") ~= "directory" then
        self.home_dir = lfs.attributes("/sdcard", "mode") == "directory" and "/sdcard" or nil
    end
    self.screen = require("device/nook/framebuffer_nst"):new{ device = self, debug = logger.dbg }
    NSTPowerD.device = self
    self.powerd = NSTPowerD
    if self:hasFrontlight() then
        NSTPowerD.fl_intensity = NSTPowerD:frontlightIntensityHW()
        NSTPowerD:_decideFrontlightState()
    end
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [KEY_NEXT] = "RPgFwd", [KEY_PREVIOUS] = "RPgBack",
            -- (the left pair; Settings → Navigation can swap them)
            [158] = "LPgFwd", [139] = "LPgBack",
            [102] = "Home", [116] = "Power",
        },
    }
    -- single touch: ABS_X / ABS_Y, then BTN_TOUCH down or up
    local input = self.input
    input.handleTouchEv = input.handleTouchEvLegacy
    local orig = input.handleKeyBoardEv
    input.handleKeyBoardEv = function(this, ev)
        if ev.code == 330 then -- BTN_TOUCH
            this:setCurrentMtSlotChecked("id", ev.value ~= 0 and 1 or -1)
            return nil
        end
        return orig(this, ev)
    end
    -- the touch's orientation, if it's off on a Nook (Settings → Interface)
    if G_reader_settings:isTrue("gzreader_nst_flip_x") then
        input:registerEventAdjustHook(input.adjustABS_MirrorX, self.screen:getWidth() - 1)
    end
    if G_reader_settings:isTrue("gzreader_nst_flip_y") then
        input:registerEventAdjustHook(input.adjustABS_MirrorY, self.screen:getHeight() - 1)
    end
    for n = 0, 9 do
        local path = "/dev/input/event" .. n
        if lfs.attributes(path, "mode") == "char device" then
            local ok, err = pcall(input.open, input, path)
            if not ok then logger.warn("nook touch: can't open", path, err) end
        end
    end
    Generic.init(self)
end

function NookTouch:setEventHandlers(uimgr)
    UIManager = uimgr
    UIManager.event_handlers.PowerPress = function() end
    UIManager.event_handlers.PowerRelease = function() self:onPowerEvent("Power") end
    UIManager.event_handlers.Suspend = function()
        self:_beforeSuspend()
        self:onPowerEvent("Suspend")
    end
    UIManager.event_handlers.Resume = function()
        self:onPowerEvent("Resume")
        self:_afterResume()
    end
end

function NookTouch:suspend()
    local f = io.open("/sys/power/state", "w")
    if f then f:write("mem"); f:close() end
end

function NookTouch:resume()
    local f = io.open("/sys/power/state", "w")
    if f then f:write("on"); f:close() end
end

NookTouch.initNetworkManager = Nook1.initNetworkManager

function NookTouch:supportsScreensaver() return true end

return NookTouch
