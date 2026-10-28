return function()
    local Device = require("device")
    if not (Device.isKindle and Device:isKindle()) then return end

    local powerd = Device:getPowerDevice()
    if not powerd.batt_capacity_file or powerd._zen_capacity_fallback then return end

    local orig_getCapacityHW = powerd.getCapacityHW
    powerd.getCapacityHW = function(self, ...)
        -- LIPC may return nil during suspend/resume; use the kernel's battery reading.
        return orig_getCapacityHW(self, ...) or self:unchecked_read_int_file(self.batt_capacity_file)
    end
    powerd._zen_capacity_fallback = true
end
