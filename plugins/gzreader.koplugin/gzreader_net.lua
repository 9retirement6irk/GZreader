--[[--
Wi-Fi only when needed (Settings → GZreader → Wi-Fi only when needed).

The Kindle 3's Wi-Fi is one of its biggest battery drains. With this on,
GZreader turns Wi-Fi on by itself when it needs the network:
- browsing Grimmory, downloads, connecting, sending the log, checking for
  updates (shows "Connecting to Wi-Fi…");
- syncing when a book opens and closes, and on wake after a long sleep
  (quietly in the background);
and turns it off again once nothing has used it for IDLE_SECONDS and
nothing needs it (an open Grimmory browser, a download or its queue, the
library index, a QR screen). Page-turn syncs and bookmarks made while Wi-Fi
is off wait and go with the next sync. Wi-Fi you turned on yourself is
never turned off.
]]

local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Log = require("gzreader_log")

local Net = {
    IDLE_SECONDS = 60,
    holders = {},
    ours = false,      -- we turned Wi-Fi on (so we may turn it off)
    last_use = 0,
    clock = os.time,
}

function Net.enabled()
    return G_reader_settings:nilOrTrue("gzreader_wifi_on_demand")
end

function Net.connected()
    return NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
end

local function busy()
    return next(Net.holders) ~= nil
end

local check
local function schedule()
    UIManager:unschedule(check)
    UIManager:scheduleIn(Net.IDLE_SECONDS / 3, check)
end

check = function()
    if not Net.ours then return end
    if not NetworkMgr:isWifiOn() then Net.ours = false; return end -- turned off elsewhere
    if busy() or Net.clock() - Net.last_use < Net.IDLE_SECONDS then return schedule() end
    Net.ours = false
    Log.info("wifi: idle, turning it off (Wi-Fi only when needed)")
    NetworkMgr:disableWifi()
end

Net._check = function() return check() end -- tests

--- Something just used the network.
function Net.touch()
    Net.last_use = Net.clock()
    if Net.ours then schedule() end
end

function Net.hold(key)
    Net.holders[key] = true
    Net.touch()
end

function Net.release(key)
    if Net.holders[key] then
        Net.holders[key] = nil
        Net.touch()
    end
end

--- Run fn once online. opts.quiet: no "Connecting…" message and no prompt
--- (background syncs); without "Wi-Fi only when needed", quiet calls only run
--- when already connected.
function Net.run(fn, opts)
    opts = opts or {}
    local function go() Net.touch(); fn() end
    if Net.connected() then return go() end
    if not Net.enabled() then
        if opts.quiet then return end
        return NetworkMgr:runWhenOnline(go)
    end
    if Net.connecting then
        table.insert(Net.connecting, go)
        return
    end
    Net.connecting = { go }
    Log.info("wifi: turning on for", opts.reason or "?")
    Net.ours = not NetworkMgr:isWifiOn()
    local function done()
        local list = Net.connecting or {}
        Net.connecting = nil
        Log.info("wifi: connected")
        for _i, f in ipairs(list) do pcall(f) end
        if Net.ours then schedule() end
    end
    local r
    if opts.quiet then
        r = NetworkMgr:enableWifi(done)
    else
        r = NetworkMgr:turnOnWifiAndWaitForConnection(done)
    end
    if r == false then
        Net.connecting = nil
        Log.warn("wifi: couldn't connect for", opts.reason or "?")
    end
    -- give up waiting after 90 s (no network in range): drop the callbacks
    UIManager:scheduleIn(90, function()
        if Net.connecting then
            Log.warn("wifi: no connection after 90 s for", opts.reason or "?")
            Net.connecting = nil
            if Net.ours and not busy() then Net.ours = false; NetworkMgr:disableWifi() end
        end
    end)
end

--- Before sleep: turn off Wi-Fi we turned on (the queued syncs wait).
function Net.onSuspend()
    if Net.ours and NetworkMgr:isWifiOn() and not busy() then
        Net.ours = false
        UIManager:unschedule(check)
        NetworkMgr:disableWifi()
    end
end

return Net
