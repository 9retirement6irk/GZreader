--[[--
GZreader: Bluetooth kept on when Wi‑Fi is turned off, on the Kindles with
Bluetooth (2016 and newer: Kindle 8th gen, Oasis, Paperwhite 4 and newer,
Scribe, Colorsoft).

KOReader turns a Kindle's Wi‑Fi off with Amazon's airplane mode
(`com.lab126.cmd wirelessEnable 0`): the Kindle ignores `com.lab126.wifid
enable 0` on its own (checked on a Scribe, firmware 5.20.2: it stayed
CONNECTED). Airplane mode switches Bluetooth off too, which cuts off
headphones and speakers. Bluetooth can be turned on again inside airplane
mode (`com.lab126.btfd BTenable 1:1`) and the device reconnected
(`Connect <address>`): sound reached the Scosche again with Wi‑Fi still off
(same Scribe).

    local BT = require("device/kindle/gzbluetooth")
    local before = BT.before(lipc_handle)   -- before wirelessEnable 0
    BT.after(lipc_handle, before, open, schedule)
    BT.sleep(open)                          -- going to sleep: Bluetooth off
    BT.wake(open, schedule)                 -- waking: on again if it was

The device's name and address are never logged.
]]

local BT = {
    CONFIG = "/var/local/zbluetooth/bt_config.conf",
    -- seconds between turning Bluetooth on and asking it to connect
    -- (it isn't ready to connect at once; 4 s worked on the Scribe)
    CONNECT_DELAY = 4,
    SERVICE = "com.lab126.btfd",
}

local function call(fn, ...)
    local ok, v = pcall(fn, ...)
    if ok then return v end
end

--- Bluetooth's state from Amazon's service: a number (0 = off, 2 = on with
--- a device connected, seen on the Scribe), or nil on a Kindle without
--- Bluetooth (no `com.lab126.btfd`).
function BT.state(lipc)
    if not lipc then return nil end
    local v = call(lipc.get_int_property, lipc, BT.SERVICE, "BTstate")
    return tonumber(v)
end

--- What to bring back after airplane mode: nil when Bluetooth is off or
--- missing; otherwise { name = the connected device's name, or nil }.
function BT.before(lipc)
    -- asleep: Bluetooth stays off (BT.sleep), Wi-Fi off doesn't bring it back
    if BT.asleep then return nil end
    local state = BT.state(lipc)
    if not state or state == 0 then return nil end
    local name = call(lipc.get_string_property, lipc, BT.SERVICE, "BTconnectedDevName")
    if type(name) ~= "string" or name == "" then name = nil end
    return { name = name }
end

--- The paired devices in Amazon's Bluetooth config (Bluedroid's format:
--- `[aa:bb:cc:dd:ee:ff]` then `Name = …` lines; `[Info]`, `[Adapter]` and
--- other sections aren't devices), in file order: { { address, name } }.
function BT.devices(text)
    local list, cur = {}, nil
    for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        local section = line:match("^%s*%[(.-)%]%s*$")
        if section then
            cur = nil
            if section:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") then
                cur = { address = section }
                list[#list + 1] = cur
            end
        elseif cur then
            local name = line:match("^%s*Name%s*=%s*(.-)%s*$")
            if name and name ~= "" then cur.name = name end
        end
    end
    return list
end

--- The address to reconnect: the device with that name; without a name
--- (or no match), the only paired device; otherwise nil.
function BT.addressFor(text, name)
    local list = BT.devices(text)
    if name then
        for _i, d in ipairs(list) do
            if d.name == name then return d.address end
        end
    end
    if #list == 1 then return list[1].address end
    return nil
end

local function readConfig()
    local f = io.open(BT.CONFIG, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
BT.readConfig = readConfig

--- After airplane mode: Bluetooth on again, and (CONNECT_DELAY seconds
--- later, through `schedule(seconds, fn)`) the device that was connected
--- asked to connect, on a handle from `open()` (closed after).
--- Returns true when Bluetooth was turned on again.
local function reconnectLater(name, open, schedule)
    if not schedule then return end
    schedule(BT.CONNECT_DELAY, function()
        if BT.asleep then return end -- went to sleep meanwhile
        local address = BT.addressFor(BT.readConfig(), name)
        if not address then return end
        local h = open and call(open)
        if not h then return end
        call(h.set_string_property, h, BT.SERVICE, "Connect", address)
        call(h.close, h)
    end)
end

function BT.after(lipc, before, open, schedule)
    if not before or not lipc then return false end
    call(lipc.set_string_property, lipc, BT.SERVICE, "BTenable", "1:1")
    reconnectLater(before.name, open, schedule)
    return true
end

--- Going to sleep (the Kindle's screensaver): Bluetooth off when it's on,
--- remembering the connected device for BT.wake. Returns true when it was
--- turned off. Kindles without Bluetooth (or lipc): nothing.
BT.asleep = false
BT.was_on = nil
function BT.sleep(open)
    if BT.asleep then return false end
    local h = open and call(open)
    local before = h and BT.before(h)
    BT.asleep = true
    BT.was_on = before
    if before then call(h.set_string_property, h, BT.SERVICE, "BTenable", "0:1") end
    if h then call(h.close, h) end
    return before ~= nil
end

--- Waking up: Bluetooth on again and the device reconnected (CONNECT_DELAY
--- seconds later), only if it was on when the Kindle went to sleep. Returns
--- true when it was turned on.
function BT.wake(open, schedule)
    if not BT.asleep then return false end
    BT.asleep = false
    local before = BT.was_on
    BT.was_on = nil
    if not before then return false end
    local h = open and call(open)
    if not h then return false end
    call(h.set_string_property, h, BT.SERVICE, "BTenable", "1:1")
    call(h.close, h)
    reconnectLater(before.name, open, schedule)
    return true
end

return BT
