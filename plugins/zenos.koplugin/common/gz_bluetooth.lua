--[[--
GZreader: does this device have Bluetooth that ZenOS's Bluetooth menu can
manage? A Kindle whose firmware has liblipclua (5.x) and Amazon's Bluetooth
service (`com.lab126.btfd` answers `BTstate`): the Kindle 8th gen and later,
Oasis, Paperwhite 4 and newer, Scribe, Colorsoft. Not the Kindle 2/3/DX/4/
Touch (no liblipclua), the Paperwhites 2–3 (no btfd), the Nooks.

One question, in this process (no lipc-get-prop process); the caller keeps
the answer (modules/menu/bluetooth/bluetooth.lua).
]]

local M = {
    SERVICE = "com.lab126.btfd",
    -- (tests) stand-ins for require("device") and require("liblipclua")
    device = nil,
    lipc = nil,
}

function M.present()
    local Device = M.device
    if not Device then
        local ok, d = pcall(require, "device")
        if not ok then return false end
        Device = d
    end
    if not (Device.isKindle and Device:isKindle()) then return false end
    local lipc = M.lipc
    if not lipc then
        local ok, l = pcall(require, "liblipclua")
        if not ok or type(l) ~= "table" then return false end
        lipc = l
    end
    local ok, handle = pcall(lipc.init, "com.github.koreader.gzreader.bluetooth")
    if not ok or not handle then return false end
    local got, state = pcall(handle.get_int_property, handle, M.SERVICE, "BTstate")
    pcall(handle.close, handle)
    return got and type(state) == "number" or false
end

return M
