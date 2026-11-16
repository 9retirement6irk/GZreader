-- Settings → General → Bluetooth on Kindles with Bluetooth: ZenOS's
-- Bluetooth module, its Kindle adapter and its device list, brought back
-- with GZreader's gate (common/gz_bluetooth.lua: only Kindles whose Amazon
-- Bluetooth service answers; one question, no lipc-get-prop process).
--   luajit settings_bluetooth_test.lua <zenos plugin dir>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

-- KOReader stand-ins
local scheduled = {}
package.loaded["ui/uimanager"] = {
    scheduleIn = function(_self, s, fn) scheduled[#scheduled + 1] = { s = s, fn = fn } end,
    unschedule = function() end,
    broadcastEvent = function() end,
    forceRePaint = function() end,
}
package.loaded["ui/event"] = { new = function(_self, name) return { name = name } end }
local logged = {}
package.loaded["common/zen_logger"] = { new = function()
    local function log(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    return { info = log, warn = log, dbg = log }
end }

local function reload(name)
    package.loaded[name] = nil
    return require(name)
end

print("== does this device have Bluetooth? (common/gz_bluetooth)")
;(function()
    local G = reload("common/gz_bluetooth")
    local kindle = { isKindle = function() return true end }
    local nook = { isKindle = function() return false end }
    local closed, asked = 0, 0
    local function lipcWith(get)
        return { init = function()
            return { get_int_property = function(_h, svc, prop) asked = asked + 1; return get(svc, prop) end,
                     close = function() closed = closed + 1 end }
        end }
    end
    G.device, G.lipc = nook, lipcWith(function() return 2 end)
    check(G.present() == false and asked == 0, "a Nook: no, nothing asked")
    G.device = kindle
    G.lipc = lipcWith(function(svc, prop) if svc == "com.lab126.btfd" and prop == "BTstate" then return 0 end end)
    check(G.present() == true and closed == 1, "a Kindle whose btfd answers (Bluetooth off): yes; the handle closed")
    G.lipc = lipcWith(function() return 2 end)
    check(G.present() == true, "…and with Bluetooth on")
    G.lipc = lipcWith(function() error("no such service com.lab126.btfd") end)
    check(G.present() == false, "a Paperwhite 3 (no btfd service): no, no error")
    G.lipc = { init = function() return nil end }
    check(G.present() == false, "lipc can't be opened: no")
    G.lipc = { init = function() error("boom") end }
    check(G.present() == false, "lipc init fails: no")
    G.lipc = nil
    package.loaded["liblipclua"] = nil
    package.preload["liblipclua"] = function() error("module 'liblipclua' not found") end
    check(G.present() == false, "a Kindle 3 (firmware 3.x, no liblipclua): no")
    package.preload["liblipclua"] = nil
    local src = assert(io.open(ZEN .. "/common/gz_bluetooth.lua")):read("*a")
    check(not src:find("io.popen", 1, true) and not src:find("os.execute", 1, true),
        "never starts a lipc-get-prop process")
end)()

print("== ZenOS's Bluetooth module behind the gate")
;(function()
    local present = false
    package.loaded["common/gz_bluetooth"] = { present = function() present = present; return present end }
    local adapter_loaded = 0
    package.preload["modules/menu/bluetooth_adapters/kindle"] = function()
        adapter_loaded = adapter_loaded + 1
        return {
            state = 2,
            readState = function() return package.loaded["modules/menu/bluetooth_adapters/kindle"].state, "LIPC" end,
            setPower = function(enabled, req)
                package.loaded["modules/menu/bluetooth_adapters/kindle"].state = enabled and 2 or 0
                req.verify({ 0 })
                return true
            end,
        }
    end
    local BT = reload("modules/menu/bluetooth/bluetooth")
    check(BT.isAvailable() == false and BT.getState() == nil and BT.isEnabled() == false,
        "no Bluetooth: not available, no state")
    check(BT.setEnabled(true) == false and BT.toggle() == false, "no Bluetooth: can't be turned on")
    check(adapter_loaded == 0, "no Bluetooth: the Kindle adapter isn't even loaded")
    -- the answer is kept: no second question
    local asked = 0
    package.loaded["common/gz_bluetooth"] = { present = function() asked = asked + 1; return true end }
    BT.isAvailable(); BT.getState()
    check(asked == 0, "the answer is kept for the session (no second question)")

    BT = reload("modules/menu/bluetooth/bluetooth")
    check(BT.isAvailable() == true and BT.getState() == true and asked == 1, "a Kindle with Bluetooth: available, on (asked once)")
    local result
    BT.toggle(function(ok) result = ok end)
    check(result == true and BT.getState() == false and BT.getCachedState() == false, "toggle turns it off")
    BT.toggle(function(ok) result = ok end)
    check(result == true and BT.isEnabled() == true, "…and on again")
    package.preload["modules/menu/bluetooth_adapters/kindle"] = nil
    package.loaded["modules/menu/bluetooth_adapters/kindle"] = nil
end)()

print("== the Kindle adapter: devices, pair, connect")
;(function()
    -- Amazon's lists as libopenlipclua hands them over
    local lists = {
        ListDiscovered = { { address = "aa:bb:cc:00:00:01", name = "Desk Speaker", rssi = -40 },
                           { address = "aa:bb:cc:00:00:02", name = "Car Radio" } },
        ListPaired = { { address = "aa:bb:cc:00:00:02", name = "Car Radio" } },
        ListConnected = {},
    }
    local set = {}
    package.loaded["libopenlipclua"] = { open_no_name = function()
        return {
            new_hasharray = function() return { destroy = function() end } end,
            access_hash_property = function(_h, _svc, prop)
                return { to_table = function() return lists[prop] end, destroy = function() end }
            end,
            set_string_property = function(_h, svc, prop, v)
                set[#set + 1] = svc .. " " .. prop .. " " .. v
                if prop == "Bond" then table.insert(lists.ListPaired, { address = v }) end
                if prop == "Connect" then table.insert(lists.ListConnected, { address = v }) end
            end,
            close = function() end,
        }
    end }
    local Kindle = reload("modules/menu/bluetooth_adapters/kindle")
    local a = Kindle.new()
    local devices = a.getDeviceList()
    check(devices and #devices == 2, "two devices found")
    check(devices[1].name == "Desk Speaker" and not devices[1].paired and devices[1].rssi == -40, "a new one: not paired")
    check(devices[2].name == "Car Radio" and devices[2].paired and not devices[2].connected, "a paired one, not connected")
    local ok
    a.pair(devices[1], function(r) ok = r end)
    check(ok == true and set[1] == "com.lab126.btfd Bond aa:bb:cc:00:00:01", "Pair: Bond with its address, then it's paired")
    a.connect(devices[2], function(r) ok = r end)
    check(ok == true and set[2] == "com.lab126.btfd Connect aa:bb:cc:00:00:02", "Connect: Connect with its address")
    a.connect({ address = "not an address" }, function(r) ok = r end)
    check(ok == false and #set == 2, "a bad address isn't sent")
    for _i, line in ipairs(logged) do
        if line:find("Desk Speaker", 1, true) or line:find("aa:bb:cc", 1, true) then
            check(false, "a device's name or address in the log: " .. line)
        end
    end
    check(true, "no device names or addresses in the log")
end)()

print("== the device list screen and the Settings row")
;(function()
    local sw = assert(io.open(ZEN .. "/modules/menu/bluetooth_switcher.lua")):read("*a")
    check(not sw:find("bluetooth_adapters/kobo", 1, true) and not sw:find("bluetooth_adapters/pocketbook", 1, true),
        "the switcher loads only the Kindle adapter (GZreader has no Kobo/PocketBook ones)")
    check(sw:find("Bluetooth.isAvailable() and Kindle", 1, true) ~= nil, "…and only on a Kindle with Bluetooth")
    local gen = assert(io.open(ZEN .. "/modules/settings/sections/general_settings.lua")):read("*a")
    check(gen:find("if Bluetooth.isAvailable() then", 1, true) and gen:find('require("modules/menu/bluetooth_switcher").open', 1, true),
        "Settings → General has the Bluetooth row (tick: on/off; tap: the devices) where Bluetooth is available")
    local f = io.open(ZEN .. "/modules/menu/bluetooth_adapters/kobo.lua")
    check(f == nil, "no Kobo adapter shipped")
    if f then f:close() end
end)()

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
