-- Kindles with Bluetooth: turning Wi‑Fi off (Amazon's airplane mode) turns
-- Bluetooth on again and reconnects the device that was connected
-- (frontend/device/kindle/gzbluetooth.lua, called from device.lua's
-- kindleEnableWifi).
--   luajit kindle_bt_test.lua <repo>
local REPO = arg[1]
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local BT = dofile(REPO .. "/frontend/device/kindle/gzbluetooth.lua")

-- Amazon's services, stood in for: a lipc handle that answers BTstate /
-- BTconnectedDevName and records every property set, in order.
local function handle(props, log)
    local h = { closed = false }
    function h:get_int_property(svc, name)
        if not props[svc] then error("no such service " .. svc) end
        return props[svc][name]
    end
    function h:get_string_property(svc, name)
        if not props[svc] then error("no such service " .. svc) end
        return props[svc][name]
    end
    function h:set_string_property(svc, name, v) log[#log + 1] = svc .. " " .. name .. " " .. tostring(v) end
    function h:set_int_property(svc, name, v) log[#log + 1] = svc .. " " .. name .. " " .. tostring(v) end
    function h:close() self.closed = true end
    return h
end

-- A config as Bluedroid writes it (made-up addresses; keys are never read)
local CONFIG = table.concat({
    "[Info]", "FileSource = Empty", "",
    "[Adapter]", "Address = 00:11:22:33:44:55", "Name = Kindle", "",
    "[aa:bb:cc:00:00:01]", "Timestamp = 1", "Name = Desk Speaker", "LinkKey = 0123", "",
    "[AA:BB:CC:00:00:02]", "Name = Car Radio", "DevClass = 2360344", "",
}, "\n")

print("== the paired devices in Amazon's Bluetooth config")
;(function()
    local list = BT.devices(CONFIG)
    check(#list == 2, "two devices; [Info] and [Adapter] aren't devices")
    check(list[1].address == "aa:bb:cc:00:00:01" and list[1].name == "Desk Speaker", "the first device and its name")
    check(list[2].address == "AA:BB:CC:00:00:02" and list[2].name == "Car Radio", "upper-case addresses kept as written")
    check(BT.addressFor(CONFIG, "Car Radio") == "AA:BB:CC:00:00:02", "the device that was connected, by its name")
    check(BT.addressFor(CONFIG, nil) == nil, "two paired, no name: nothing to reconnect")
    check(BT.addressFor(CONFIG, "Headphones") == nil, "a name that isn't paired: nothing")
    local one = "[Info]\n[aa:bb:cc:00:00:09]\nName = Only One\n"
    check(BT.addressFor(one, nil) == "aa:bb:cc:00:00:09", "only one paired: that one, even without a name")
    check(BT.addressFor(one, "Other") == "aa:bb:cc:00:00:09", "only one paired: that one when the name doesn't match")
    check(BT.addressFor("[Info]\r\n[aa:bb:cc:00:00:03]\r\nName = Crlf\r\n", "Crlf") == "aa:bb:cc:00:00:03", "Windows line ends")
    check(#BT.devices(nil) == 0 and BT.addressFor(nil, "x") == nil, "no config file: no devices")
    check(#BT.devices("[aa:bb]\nName = x\n") == 0, "a section that isn't an address isn't a device")
end)()

print("== before airplane mode: is Bluetooth on?")
;(function()
    local log = {}
    check(BT.before(handle({ ["com.lab126.btfd"] = { BTstate = 2, BTconnectedDevName = "Car Radio" } }, log)).name == "Car Radio",
        "on and connected: remembered with the device's name")
    local b = BT.before(handle({ ["com.lab126.btfd"] = { BTstate = 1, BTconnectedDevName = "" } }, log))
    check(b ~= nil and b.name == nil, "on, nothing connected: remembered without a name")
    check(BT.before(handle({ ["com.lab126.btfd"] = { BTstate = 0 } }, log)) == nil, "off: nothing to bring back")
    check(BT.before(handle({}, log)) == nil, "a Kindle without Bluetooth (no btfd service): nothing, no error")
    check(BT.before(nil) == nil, "no lipc: nothing")
    check(#log == 0, "asking sets nothing")
end)()

print("== after airplane mode: Bluetooth on again, the device reconnected")
;(function()
    BT.readConfig = function() return CONFIG end
    local log, later, opened = {}, {}, {}
    local h = handle({ ["com.lab126.btfd"] = { BTstate = 0 } }, log)
    local function open() local o = handle({}, log); opened[#opened + 1] = o; return o end
    local function schedule(s, fn) later[#later + 1] = { s = s, fn = fn } end
    check(BT.after(h, { name = "Car Radio" }, open, schedule) == true, "says Bluetooth was turned on again")
    check(log[1] == "com.lab126.btfd BTenable 1:1", "BTenable 1:1 at once")
    check(#log == 1, "not asked to connect yet (Bluetooth needs a moment)")
    check(#later == 1 and later[1].s == BT.CONNECT_DELAY and BT.CONNECT_DELAY >= 3, "the connect waits a few seconds")
    later[1].fn()
    check(log[2] == "com.lab126.btfd Connect AA:BB:CC:00:00:02", "then Connect to the device that was connected")
    check(#opened == 1 and opened[1].closed, "on a new lipc handle, closed after")

    log, later, opened = {}, {}, {}
    check(BT.after(h, nil, open, schedule) == false and #log == 0 and #later == 0, "Bluetooth was off: nothing turned on")
    check(BT.after(nil, { name = "x" }, open, schedule) == false, "no lipc: nothing")

    log, later = {}, {}
    h = handle({ ["com.lab126.btfd"] = { BTstate = 0 } }, log)
    BT.after(h, { name = "Headphones" }, open, schedule)
    later[1].fn()
    check(#log == 1 and log[1]:find("BTenable"), "two paired, the name not among them: Bluetooth on, no Connect")

    log, later = {}, {}
    h = handle({ ["com.lab126.btfd"] = { BTstate = 0 } }, log)
    BT.after(h, { name = "Car Radio" }, function() error("lipc gone") end, schedule)
    local ok = pcall(later[1].fn)
    check(ok and #log == 1, "a handle that can't be opened later: no error")

    log, later = {}, {}
    local cranky = handle({}, log)
    function cranky:set_string_property() error("service down") end
    check(pcall(BT.after, cranky, { name = "Car Radio" }, open, schedule), "a lipc error while turning it on: no error")
end)()

print("== device.lua: Wi‑Fi off goes through it")
;(function()
    local f = assert(io.open(REPO .. "/frontend/device/kindle/device.lua"))
    local src = f:read("*a"); f:close()
    local body = src:match("local function kindleEnableWifi%(toggle%)(.-)\nend\n")
    check(body ~= nil, "kindleEnableWifi found")
    body = body or ""
    local before = body:find("GzBT.before(lipc_handle)", 1, true)
    local airplane = body:find('"wirelessEnable", 0)', 1, true)
    local after = body:find("GzBT.after(lipc_handle", 1, true)
    check(before and airplane and before < airplane, "Bluetooth's state read before airplane mode")
    check(after and airplane and airplane < after, "turned on again after it")
    local on = body:find('"wirelessEnable", 1)', 1, true)
    check(on and on < (before or 0), "Wi‑Fi on unchanged (no Bluetooth step)")
    check(not body:find("BTconnectedDevName", 1, true) and not src:find("logger[^\n]*gz_bt"),
        "the device's name isn't logged")
end)()

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
