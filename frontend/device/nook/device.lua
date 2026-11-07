--[[--
The Barnes & Noble Nook 1st Edition (2009, "bravo"): a 6" e-ink page
(600 × 800, no touch) with a 3.5" colour touchscreen (480 × 144) under it,
four page buttons (two each side), the "n" button under the touchscreen and
a power button. Android 1.5 on Linux 2.6.27, Samsung S3C6410 (ARMv6, like
the Kindle 3), 128 MB.

GZreader runs on it with the Kindle 2/3/DX build's binaries and its own C
library (platform/nook/gzreader.sh starts it, pausing Android's interface).
The colour touchscreen carries what the Kindles' keys do: arrows, OK, Back,
Menu and Home (so GZreader works as on a Kindle 4), a keyboard for typing,
and reading info or the book's cover (device/nook/lcd.lua; the panels are
GZreader's, gzreader_nook.lua).
]]

local Generic = require("device/generic/device")
local UIManager -- (later: needs the device)
local ffi = require("ffi")
local bit = require("bit")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local function yes() return true end
local function no() return false end

-- linux/input.h: the Nook's own key codes (B&N's kernel)
local KEY_LEFT_NEXTPAGE, KEY_LEFT_PREVPAGE = 0x20c, 0x20d
local KEY_RIGHT_NEXTPAGE, KEY_RIGHT_PREVPAGE = 0x20e, 0x20f
local KEY_LEFT_SWIPE, KEY_RIGHT_SWIPE = 0x210, 0x211

-- What the colour screen's buttons press (codes the Nook itself never sends)
local VIRTUAL = { Up = 103, Down = 108, Left = 105, Right = 106, Press = 28, Back = 158, Menu = 139,
    Backspace = 14, Home = 102, RPgFwd = KEY_RIGHT_NEXTPAGE, RPgBack = KEY_RIGHT_PREVPAGE }

local function readLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*l")
    f:close()
    return s
end

--- Battery: the first power supply with a capacity (Nook 1st Edition: the
--- bq27200 gauge; Simple Touch: its own), and its status.
local function battery()
    for _i, d in ipairs({ "bq27200-0", "battery", "max17042_battery", "bq27510-0", "bq27520-0", "wm8350-battery" }) do
        local dir = "/sys/class/power_supply/" .. d
        if lfs.attributes(dir .. "/capacity", "mode") then return dir end
    end
    local ok, iter, obj = pcall(lfs.dir, "/sys/class/power_supply")
    if not ok then return nil end
    for d in iter, obj do
        local dir = "/sys/class/power_supply/" .. d
        if d:sub(1, 1) ~= "." and lfs.attributes(dir .. "/capacity", "mode") then return dir end
    end
end
local function batteryStatus()
    local dir = battery()
    local s = dir and readLine(dir .. "/status")
    return s or readLine("/sys/class/power_supply/battery/status") or readLine("/sys/class/power_supply/wm8350-battery/status")
end

local NookPowerD = require("device/generic/powerd"):new{}
function NookPowerD:init() end
function NookPowerD:getCapacityHW()
    local dir = battery()
    return dir and tonumber(readLine(dir .. "/capacity") or "") or 0
end
function NookPowerD:isChargingHW() return batteryStatus() == "Charging" end
function NookPowerD:isChargedHW() return batteryStatus() == "Full" end

local Nook = Generic:extend{
    model = "Nook1",
    isNook = yes,
    hasKeys = yes,
    hasDPad = yes, -- (the colour screen's arrows)
    useDPadAsActionKeys = yes,
    hasFewKeys = no,
    isTouchDevice = no, -- (the e-ink page isn't; the colour screen is ours)
    hasFrontlight = no,
    hasWifiToggle = no, -- (Android keeps Wi-Fi up underneath)
    hasWifiManager = no,
    canSuspend = yes,
    canReboot = no,
    canPowerOff = no,
    supportsScreensaver = yes,
    hasExitOptions = no,
    home_dir = "/system/media/sdcard", -- (the Nook's own storage: "my documents" etc.)
    -- set by GZreader's colour screen: typing happens there, not on an e-ink keyboard
    lcd_keyboard = true,
}

--- Typing on the colour screen: KOReader doesn't put a keyboard on the page.
function Nook:hasScreenKB() return self.lcd_keyboard == true end

--- GZreader's and ZenOS's words are a Kindle's: "Kindle" reads "Nook", and
--- the 5-way's instructions point at the colour screen.
local EXACT = {
    ["Use the 5-way to choose and press it to continue."] = "Use the arrows on the colour screen to choose and OK to continue.",
    ["Your 5-way and buttons"] = "The colour screen's buttons",
    ["The 5-way moves; press its centre to pick. Down from the bottom of Home reaches the tabs (Home, Downloads, Grimmory, Notes, Calendar): Left and Right choose one."] =
        "The arrows on the colour screen move; OK picks. Down from the bottom of Home reaches the tabs (Home, Downloads, Grimmory, Notes, Calendar): Left and Right choose one. Touch the colour screen when it shows something else to get the arrows back.",
}
function Nook.nookStrings(exact)
    exact = exact or EXACT
    local gettext = require("gettext")
    local mt = getmetatable(gettext)
    if not (mt and mt.__call) or mt._gz_nook then return end
    local orig = mt.__call
    mt.__call = function(self, msgid)
        local r = orig(self, msgid)
        if type(r) ~= "string" then return r end
        if exact[msgid] then return exact[msgid] end
        if r:find("Kindle", 1, true) then r = r:gsub("Kindle", "Nook") end
        return r
    end
    mt._gz_nook = true
end

function Nook:init()
    Nook.nookStrings()
    -- (books and GZreader's folder: the Nook's own storage, else the SD card)
    self.home_dir = os.getenv("GZ_NOOK_HOME") or self.home_dir
    if lfs.attributes(self.home_dir, "mode") ~= "directory" then
        self.home_dir = lfs.attributes("/sdcard", "mode") == "directory" and "/sdcard" or nil
    end
    self.screen = require("device/nook/framebuffer"):new{ device = self, debug = logger.dbg }
    self.powerd = NookPowerD
    NookPowerD.device = self
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [KEY_LEFT_NEXTPAGE] = "LPgFwd", [KEY_LEFT_PREVPAGE] = "LPgBack",
            [KEY_RIGHT_NEXTPAGE] = "RPgFwd", [KEY_RIGHT_PREVPAGE] = "RPgBack",
            [116] = "Power",
            [103] = "Up", [108] = "Down", [105] = "Left", [106] = "Right", [28] = "Press",
            [158] = "Back", [139] = "Menu", [14] = "Backspace", [102] = "Home",
        },
    }
    self.input.nook_virtual_codes = VIRTUAL
    self.lcd = require("device/nook/lcd"):new{ hw = self.screen.hw }
    self:hookInput()
    self:openInputDevices()
    Generic.init(self)
end

--- The touch panel's events go to the colour screen (not KOReader's gesture
--- detector: the e-ink page isn't touch); its swipe "keys" (sent by the touch
--- controller itself) turn pages unless the colour screen saw that swipe.
function Nook:hookInput()
    local input, lcd = self.input, self.lcd
    input.handleTouchEv = function(this, ev)
        local evs = lcd:onInputEvent(this, ev)
        if evs and #evs > 0 then lcd.last_gesture_events = os.time() end
        return evs
    end
    local orig = input.handleKeyBoardEv
    input.handleKeyBoardEv = function(this, ev)
        if ev.code == 330 then -- BTN_TOUCH
            local evs = lcd:onInputEvent(this, ev)
            return evs and evs[1] or nil
        end
        if ev.code == KEY_LEFT_SWIPE or ev.code == KEY_RIGHT_SWIPE then
            if ev.value ~= 1 or not lcd.chip_swipes then return nil end
            local events = lcd:gesture({ kind = "swipe", dir = ev.code == KEY_LEFT_SWIPE and "west" or "east",
                x = lcd.w / 2, y = lcd.h / 2, chip = true }, this, ev.time)
            return events and events[1] or nil
        end
        return orig(this, ev)
    end
end

pcall(ffi.cdef, [[
struct gz_absinfo { int value; int minimum; int maximum; int fuzz; int flat; };
]])

--- Every input device: the page and power buttons, the touch panel (and the
--- "n" button on it).
function Nook:openInputDevices()
    local C = ffi.C
    require("ffi/posix_h")
    for n = 0, 9 do
        local path = "/dev/input/event" .. n
        if lfs.attributes(path, "mode") == "char device" then
            local ok, err = pcall(self.input.open, self.input, path)
            if not ok then logger.warn("nook: can't open", path, err) end
            -- the touch panel's coordinate range (EVIOCGABS)
            local fd = C.open(path, C.O_RDONLY)
            if fd >= 0 then
                local abs = ffi.new("struct gz_absinfo")
                local function range(code)
                    if C.ioctl(fd, bit.bor(0x80144540, code), abs) == 0 and abs.maximum > abs.minimum then
                        return { abs.minimum, abs.maximum }
                    end
                end
                local rx, ry = range(0), range(1)
                if rx and ry then
                    logger.info("nook: touch panel", path, "x", rx[1], rx[2], "y", ry[1], ry[2])
                    -- B&N's Synaptics driver (synaptics_i2c_rmi.c) reports y in the whole
                    -- virtual screen's height (0-13518: the e-ink page above, the colour
                    -- screen in its last 2082, from 11436), and x scaled by 0.8 after
                    -- announcing the panel's own range: the colour screen's touches are
                    -- x 0-5662, y 11436-13518. (With the announced ranges every touch
                    -- landed in the picture's bottom strip: "the left side is the down
                    -- arrow".)
                    if rx[2] == 7078 and ry[2] == 13518 then
                        rx, ry = { 0, math.floor(7078 * 800 / 1000) }, { 11436, 13518 }
                    end
                    self.lcd.range = { x = rx, y = ry }
                end
                C.close(fd)
            end
        end
    end
end

function Nook:setEventHandlers(uimgr)
    UIManager = uimgr
    UIManager.event_handlers.PowerPress = function() end
    UIManager.event_handlers.PowerRelease = function()
        self:onPowerEvent("Power")
    end
    UIManager.event_handlers.Suspend = function()
        self:_beforeSuspend()
        self:onPowerEvent("Suspend")
    end
    UIManager.event_handlers.Resume = function()
        self:onPowerEvent("Resume")
        self:_afterResume()
    end
end

--- Sleep: the colour screen goes dark and the kernel suspends (Android's
--- interface is paused, so nothing else asks for it). The power button wakes it.
function Nook:suspend()
    if self.lcd then self.lcd:setBacklight(false) end
    local f = io.open("/sys/power/state", "w")
    if f then f:write("mem"); f:close() end
end

function Nook:resume()
    local f = io.open("/sys/power/state", "w")
    if f then f:write("on"); f:close() end
    if self.lcd then self.lcd:setBacklight(true) end
end

function Nook:exit()
    if self.lcd and self.lcd.hw then
        -- (the screens go back to Android in screen:close)
        self.lcd.hw = nil
    end
    Generic.exit(self)
end

function Nook:initNetworkManager(NetworkMgr)
    -- Android keeps the Wi-Fi connection; GZreader only looks at it.
    function NetworkMgr:turnOnWifi(complete_callback)
        if complete_callback then complete_callback() end
        return true
    end
    function NetworkMgr:turnOffWifi(complete_callback)
        if complete_callback then complete_callback() end
    end
    -- (the Nook's Wi-Fi is an Atheros AR6002: eth0 on B&N's kernel)
    local function iface()
        for _i, ifname in ipairs({ "eth0", "wlan0", "tiwlan0" }) do
            if lfs.attributes("/sys/class/net/" .. ifname, "mode") then return ifname end
        end
    end
    NetworkMgr.getNetworkInterfaceName = function() return iface() or "eth0" end
    NetworkMgr.isWifiOn = function()
        local ifname = iface()
        if not ifname then return false end
        local state = readLine("/sys/class/net/" .. ifname .. "/operstate")
        return state == "up" or state == "unknown"
    end
    NetworkMgr.isConnected = function(this) return this:isWifiOn() end
end

function Nook:supportsScreensaver() return true end

Nook.PowerD = NookPowerD
Nook.readLine = readLine

return Nook
