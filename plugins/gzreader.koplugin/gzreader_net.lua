--[[--
Wi-Fi only when needed (Settings → General → Wi-Fi only when needed).

The Kindle 3's Wi-Fi is one of its biggest battery drains. With this on,
GZreader turns Wi-Fi on by itself when it needs the network:
- browsing Grimmory, downloads, connecting, sending the log, checking for
  updates (shows "Connecting to Wi-Fi…");
- syncing when a book opens and closes, and on wake after a long sleep
  (quietly in the background);
and turns it off again once nothing has used it for IDLE_SECONDS and
nothing needs it (an open Grimmory browser, a download or its queue, the
library index, a QR screen). Page-turn syncs and bookmarks made while Wi-Fi
is off wait and go with the next sync.

Wi-Fi you turn off yourself (Wi-Fi menu item or quick panel) stays off
for background work (syncing when a book opens or closes, after waking,
Notes, the auto-download shelf): that waits until you turn Wi-Fi on again,
also after a restart (1.6.0; before, the next sync turned it back on).
Things you ask for (browsing Grimmory, a download, opening an attachment,
checking for updates, connecting) still turn it on, then off after a minute.

Wi-Fi that was already on when GZreader started or woke up (the Kindle
keeps it on by itself) counts as GZreader's too: up to 1.2.7 it didn't, so
on a Kindle that connected at boot Wi-Fi was never turned off. Only Wi-Fi
you turn on yourself (the Wi-Fi menu item or quick panel button) is left
alone, until you turn it off again.
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

--- You turned Wi-Fi off yourself: background work leaves it off.
function Net.keptOff()
    return G_reader_settings:isTrue("gzreader_wifi_kept_off")
end

local function setKeptOff(on)
    if on then G_reader_settings:makeTrue("gzreader_wifi_kept_off")
    else G_reader_settings:delSetting("gzreader_wifi_kept_off") end
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
    pcall(function() require("gzreader_usage").networkUsed() end)
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

local wrapScan

Net.ROUTE_WAIT = 8

--- A default route (somewhere to send requests), from /proc/net/route; true
--- where that can't be read.
function Net.routeReady()
    local f = io.open("/proc/net/route", "r")
    if not f then return true end
    local ok = false
    for line in f:lines() do
        local dest = line:match("^%S+%s+(%x+)%s")
        if dest == "00000000" then ok = true break end
    end
    f:close()
    return ok
end

--- Run fn once online. opts.quiet: no "Connecting…" message and no prompt
--- (background syncs); without "Wi-Fi only when needed", quiet calls only run
--- when already connected.
function Net.run(fn, opts)
    opts = opts or {}
    if Net.usb then
        -- no Wi-Fi (syncing through a computer, gzreader_usbsync.lua): what
        -- the library copy can answer runs; anything else asked for opens the
        -- Sync with computer screen, background work waits for the computer
        if opts.usb then return fn() end
        if not opts.quiet then pcall(Net.onUsb, opts.reason) end
        return
    end
    local function go() Net.touch(); fn() end
    if Net.connected() then return go() end
    if opts.quiet and Net.keptOff() then return end -- you turned it off: background work waits
    if not Net.enabled() then
        if opts.quiet then return end
        return NetworkMgr:runWhenOnline(go)
    end
    if Net.connecting then
        table.insert(Net.connecting, go)
        return
    end
    local attempt = { go }
    Net.connecting = attempt
    Log.info("wifi: turning on for", opts.reason or "?")
    Net.ours = not NetworkMgr:isWifiOn()
    local function run_waiting()
        local list = Net.connecting or {}
        Net.connecting = nil
        for _i, f in ipairs(list) do pcall(f) end
        if Net.ours then schedule() end
    end
    local function done()
        Log.info("wifi: connected")
        -- The Paperwhite says it's connected a moment before it has a route
        -- out ("Network is unreachable" for the first requests): wait for one
        -- (up to ROUTE_WAIT seconds).
        local waited = 0
        local function routeCheck()
            if Net.routeReady() or waited >= Net.ROUTE_WAIT then
                if waited > 0 then Log.info("wifi: route out after", waited, "s") end
                return run_waiting()
            end
            waited = waited + 0.5
            UIManager:scheduleIn(0.5, routeCheck)
        end
        routeCheck()
    end
    local r
    pcall(wrapScan)
    Net.automatic = true -- (no scan popups: see wrapScan)
    local ok, res = pcall(function()
        if opts.quiet then return NetworkMgr:enableWifi(done) end
        return NetworkMgr:turnOnWifiAndWaitForConnection(done)
    end)
    Net.automatic = false
    r = ok and res
    if not ok then Log.warn("wifi: turning on failed:", tostring(res)) end
    if r == false then
        Net.connecting = nil
        Log.warn("wifi: couldn't connect for", opts.reason or "?")
    end
    -- give up waiting after 90 s (no network in range): drop the callbacks
    UIManager:scheduleIn(90, function()
        -- (this attempt's own: a later one, started after Wi-Fi went off
        -- again, isn't given up on by this timer; it was until 1.23.7)
        if Net.connecting == attempt then
            Log.warn("wifi: no connection after 90 s for", opts.reason or "?")
            Net.connecting = nil
            if Net.ours and not busy() then Net.ours = false; NetworkMgr:disableWifi() end
        end
    end)
end

--- Asked for something that needs the network on a Kindle syncing through
--- a computer: the Sync with computer screen.
function Net.onUsb(reason)
    local Usb = require("gzreader_usbsync")
    Log.info("wifi: none (syncing through a computer); asked for", tostring(reason))
    if Usb.plugin then Usb.show(Usb.plugin) end
end

--- Touch Kindles (Paperwhite, Touch) turn Wi-Fi on through KOReader's scan
--- ("Scanning for networks…", then "Connecting to network …"); the Kindle 3
--- doesn't. When GZreader turns Wi-Fi on by itself those stay in the
--- background, as on the Kindle 3 (errors are still logged).
wrapScan = function()
    if NetworkMgr.reconnectOrShowNetworkMenu == Net._scan then return end
    local orig = NetworkMgr.reconnectOrShowNetworkMenu
    if type(orig) ~= "function" then return end
    Net._scan = function(self, cb, interactive, ...)
        if not Net.automatic or interactive then return orig(self, cb, interactive, ...) end
        local show, repaint = UIManager.show, UIManager.forceRePaint
        UIManager.show = function(um, w, ...)
            -- (only messages are shown here when it isn't interactive)
            if type(w) == "table" and type(w.text) == "string" and not w.buttons then
                Log.info("wifi (quiet):", tostring(w.text):gsub("\n", " "))
                return
            end
            return show(um, w, ...)
        end
        UIManager.forceRePaint = function() end
        local res = { pcall(orig, self, cb, interactive, ...) }
        UIManager.show, UIManager.forceRePaint = show, repaint
        if not res[1] then error(res[2]) end
        return unpack(res, 2)
    end
    NetworkMgr.reconnectOrShowNetworkMenu = Net._scan
end

--- Wi-Fi switched on or off by the user (menu, quick panel, gesture).
local function wrapToggles()
    if NetworkMgr.toggleWifiOn ~= Net._toggle_on then
        local orig = NetworkMgr.toggleWifiOn
        Net._toggle_on = function(...)
            Net.user_on, Net.ours = true, false
            setKeptOff(false)
            UIManager:unschedule(check)
            Log.info("wifi: turned on by you; left on")
            return orig(...)
        end
        NetworkMgr.toggleWifiOn = Net._toggle_on
    end
    if NetworkMgr.toggleWifiOff ~= Net._toggle_off then
        local orig = NetworkMgr.toggleWifiOff
        Net._toggle_off = function(...)
            Net.user_on, Net.ours = nil, false
            UIManager:unschedule(check)
            if not Net.keptOff() then Log.info("wifi: turned off by you; background work waits until you turn it on") end
            setKeptOff(true)
            return orig(...)
        end
        NetworkMgr.toggleWifiOff = Net._toggle_off
    end
    -- the quick panel and Wi-Fi menu turn it off with disableWifi(cb, interactive = true);
    -- GZreader's own calls aren't interactive
    if NetworkMgr.disableWifi ~= Net._disable then
        local orig = NetworkMgr.disableWifi
        Net._disable = function(self, cb, interactive, ...)
            if interactive == true then
                Net.user_on, Net.ours = nil, false
                UIManager:unschedule(check)
                if not Net.keptOff() then Log.info("wifi: turned off by you; background work waits until you turn it on") end
                setKeptOff(true)
            end
            return orig(self, cb, interactive, ...)
        end
        NetworkMgr.disableWifi = Net._disable
    end
    -- and on again (the Home menu's "Turn Wi-Fi on": enableWifi(cb, interactive = true))
    if NetworkMgr.enableWifi ~= Net._enable then
        local orig = NetworkMgr.enableWifi
        Net._enable = function(self, cb, interactive, ...)
            if interactive == true then
                Net.user_on, Net.ours = true, false
                UIManager:unschedule(check)
                setKeptOff(false)
            end
            return orig(self, cb, interactive, ...)
        end
        NetworkMgr.enableWifi = Net._enable
    end
end

--- At start and after waking: Wi-Fi that's on and not turned on by the user
--- is managed like Wi-Fi GZreader turned on (off after IDLE_SECONDS unused).
function Net.adopt()
    pcall(wrapToggles) -- (again: ZenOS replaces these functions after we load)
    if not Net.enabled() or Net.user_on or Net.ours or Net.connecting then return end
    if not NetworkMgr:isWifiOn() then return end
    Net.ours = true
    Net.last_use = Net.clock()
    Log.info("wifi: on but not needed: off in", Net.IDLE_SECONDS, "s unless something uses it")
    schedule()
end

function Net.start()
    if Net.started then return end
    Net.started = true
    UIManager:scheduleIn(10, Net.adopt) -- after startup syncs, once ZenOS has loaded
end

function Net.onResume()
    UIManager:scheduleIn(20, Net.adopt)
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
