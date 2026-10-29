--[[--
Night mode on the Kindle 2 / DX / Kindle Keyboard / Kindle 4.

These Kindles can't invert the screen in hardware, so KOReader inverts every
drawing in software; on the Kindle 3's 4-bit screen that is slow enough to
make the Kindle unusable (and night mode is saved, so it came back on every
start). GZreader turns it off at start and refuses to turn it on there,
wherever the request comes from (menus, gestures, ZenOS's night schedule).
]]

local Device = require("device")
local Screen = Device.screen

local Guard = { installed = false }

function Guard.applies()
    return Device:isKindle() and not Device:canHWInvert()
end

local function notify()
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok then return end
    UIManager:nextTick(function()
        local InfoMessage = require("ui/widget/infomessage")
        local _ = require("gettext")
        UIManager:show(InfoMessage:new{
            text = _("Night mode isn't available on this Kindle: it has no hardware screen inversion, and inverting in software makes it far too slow."),
            timeout = 5,
        })
    end)
end

function Guard.install()
    if Guard.installed or not Guard.applies() then return end
    Guard.installed = true
    local orig = Screen.toggleNightMode
    -- Turn it off if a saved setting switched it on at start.
    if Screen.night_mode then
        orig(Screen)
        pcall(function()
            local UIManager = require("ui/uimanager")
            UIManager:ToggleNightMode(false)
            UIManager:setDirty("all", "full")
        end)
    end
    G_reader_settings:saveSetting("night_mode", false)
    Screen.toggleNightMode = function(self, ...)
        if not self.night_mode then
            -- would switch it on
            G_reader_settings:saveSetting("night_mode", false)
            notify()
            return
        end
        return orig(self, ...)
    end
    -- DeviceListener flips the saved setting after toggling; keep it off.
    local okd, DeviceListener = pcall(require, "device/devicelistener")
    if okd and DeviceListener.onToggleNightMode then
        local orig_toggle = DeviceListener.onToggleNightMode
        DeviceListener.onToggleNightMode = function(listener, ...)
            if not Screen.night_mode then
                G_reader_settings:saveSetting("night_mode", false)
                notify()
                return true
            end
            return orig_toggle(listener, ...)
        end
    end
end

return Guard
