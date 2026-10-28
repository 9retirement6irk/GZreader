return function()
    local Device = require("device")
    if not (Device.isKindle and Device:isKindle() and Device:supportsScreensaver()) then return end

    local powerd = Device:getPowerDevice()
    if powerd._zen_wakeup_recovery or type(powerd.checkUnexpectedWakeup) ~= "function" then return end
    local ok, lipc = pcall(require, "liblipclua")
    if not ok or type(lipc.init) ~= "function" then return end

    local logger = require("common/zen_logger").new("kindle_wakeup_recovery")
    local orig_checkUnexpectedWakeup = powerd.checkUnexpectedWakeup
    powerd.checkUnexpectedWakeup = function(self, ...)
        if Device.screen_saver_mode then
            local state = self:getPowerdState()
            if state == nil then
                if self.lipc_handle then
                    pcall(self.lipc_handle.close, self.lipc_handle)
                    self.lipc_handle = nil
                end
                local opened, handle = pcall(lipc.init, "com.github.koreader.kindlepowerd")
                if opened then self.lipc_handle = handle end
                state = self:getPowerdState()
            end
            if state == nil then
                logger.warn("Could not read Kindle power state after reconnect")
                return
            end
            -- Background wakes also reach this check; resume only after a confirmed active state.
            if state == "active" then
                logger.warn("Recovering missed Kindle screensaver exit")
                return Device:outofScreenSaver()
            end
        end
        return orig_checkUnexpectedWakeup(self, ...)
    end
    powerd._zen_wakeup_recovery = true
end
