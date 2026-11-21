--[[--
Wi-Fi: on, off or auto (the quick panel's Wi-Fi tile cycles through them;
Settings → Wi-Fi offers them too). The mode is kept in
G_reader_settings "gzreader_wifi_mode"; until 1.28 it was two settings
("Wi-Fi only when needed" and "you turned it off"), read by Net.mode() when
no mode has been saved yet.

- **Auto** (the default; it was "Wi-Fi only when needed"). The Kindle 3's
  Wi-Fi is one of its biggest battery drains. GZreader turns Wi-Fi on by
  itself when it needs the network:
  - browsing Grimmory, downloads, connecting, sending the log, checking for
    updates (shows "Connecting to Wi-Fi…");
  - syncing when a book opens and closes, and on wake after a long sleep
    (quietly in the background);
  and turns it off again once nothing has used it for IDLE_SECONDS and
  nothing needs it (an open Grimmory browser, a download or its queue, the
  library index, a QR screen). Page-turn syncs and bookmarks made while
  Wi-Fi is off wait and go with the next sync. Wi-Fi that was already on
  when GZreader started or woke up (the Kindle keeps it on by itself) counts
  as GZreader's too: up to 1.2.7 it didn't, so on a Kindle that connected at
  boot Wi-Fi was never turned off.
- **On**: Wi-Fi stays on; GZreader never turns it off, and turns it back on
  when something needs it and it has gone off (after waking, out of range).
- **Off**: background work (syncing when a book opens or closes, after
  waking, Notes, the auto-download shelf) waits until Wi-Fi is on again,
  also after a restart (1.6.0; before, the next sync turned it back on).
  Things you ask for (browsing Grimmory, a download, opening an attachment,
  checking for updates, connecting) still turn it on, then off after a
  minute.

Turning Wi-Fi on or off anywhere else (KOReader's Wi-Fi menu, a gesture, the
network list) chooses On or Off, so the mode always says what you last asked
for.
]]

local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Log = require("gzreader_log")

local Net = {
    IDLE_SECONDS = 60,
    CHECK_EVERY = 30, -- (until 1.26.9: IDLE_SECONDS / 3, at its own offset)
    holders = {},
    ours = false,      -- we turned Wi-Fi on (so we may turn it off)
    last_use = 0,
    clock = os.time,
}

--- Kindles without Wi-Fi: they sync through a computer (gzreader_usbsync.lua).
Net.NO_WIFI_MODELS = { Kindle2 = true, KindleDX = true, KindleDXG = true }

--- This model has no Wi-Fi (gzreader_usbsync.lua Usb.noWifi).
function Net.noWifi(model)
    return Net.NO_WIFI_MODELS[tostring(model or require("device").model)] == true
end

--- Sync through a computer: Kindles without Wi-Fi, or chosen in Settings
--- (gzreader_usbsync.lua Usb.active; here so that start-up doesn't load that
--- module on the Kindles that sync over Wi-Fi).
function Net.usbSyncChosen()
    local s = G_reader_settings and G_reader_settings:readSetting("gzreader_usb_sync")
    if s == true or s == false then return s end
    return Net.noWifi()
end

Net.MODES = { "on", "off", "auto" } -- (the tile's order)
local VALID = { on = true, off = true, auto = true }

--- "on", "off" or "auto".
function Net.mode()
    local m = G_reader_settings:readSetting("gzreader_wifi_mode")
    if VALID[m] then return m end
    -- (until 1.28: "Wi-Fi only when needed" (on by default) and "you turned it off")
    if G_reader_settings:isTrue("gzreader_wifi_kept_off") then return "off" end
    if G_reader_settings:readSetting("gzreader_wifi_on_demand") == false then return "on" end
    return "auto"
end

--- The next mode on the quick panel's tile: on → off → auto → on.
function Net.nextMode(m)
    m = m or Net.mode()
    for i, v in ipairs(Net.MODES) do
        if v == m then return Net.MODES[i % #Net.MODES + 1] end
    end
    return "auto"
end

--- You turned Wi-Fi off yourself (mode Off): background work leaves it off.
function Net.keptOff()
    return Net.mode() == "off"
end

local check
local function saveMode(m)
    if Net.mode() ~= m then Log.info("wifi: mode", m) end
    G_reader_settings:saveSetting("gzreader_wifi_mode", m)
    G_reader_settings:delSetting("gzreader_wifi_on_demand")
    G_reader_settings:delSetting("gzreader_wifi_kept_off")
    -- the status bars' Wi-Fi icon (the auto mark) and open settings pages
    pcall(function()
        UIManager:broadcastEvent(require("ui/event"):new("NetworkStateChanged"))
    end)
end

function Net.connected()
    return NetworkMgr:isWifiOn() and NetworkMgr:isConnected()
end

local function busy()
    return next(Net.holders) ~= nil
end

local function schedule()
    UIManager:unschedule(check)
    -- (every half minute, on the clock with GZreader's other timers: gzreader_ticks.lua)
    UIManager:scheduleIn(require("gzreader_ticks").untilNext(Net.CHECK_EVERY), check)
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
    -- (a download or an update: Wi-Fi power saving off until it's done; gzreader_wifips.lua)
    pcall(function() require("gzreader_wifips").hold(key) end)
end

function Net.release(key)
    if Net.holders[key] then
        Net.holders[key] = nil
        Net.touch()
    end
    pcall(function() require("gzreader_wifips").release(key) end)
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
    -- (a clock that ran down, e.g. a Touch back in 2013 after a reboot: set
    -- from a time server first; one comparison when it's right)
    local function go() Net.touch(); pcall(function() require("gzreader_clock").online() end); fn() end
    if Net.connected() then return go() end
    local mode = Net.mode()
    if opts.quiet and mode == "off" then return end -- you turned it off: background work waits
    if Net.connecting then
        table.insert(Net.connecting, go)
        return
    end
    local attempt = { go }
    Net.connecting = attempt
    Log.info("wifi: turning on for", opts.reason or "?")
    -- (On: it stays on afterwards)
    Net.ours = mode ~= "on" and not NetworkMgr:isWifiOn()
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
                Log.info("wifi (quiet):", (tostring(w.text):gsub("\n", " "))) -- (Log hides the network's name)
                return
            end
            return show(um, w, ...)
        end
        UIManager.forceRePaint = function() end
        local res = { pcall(orig, self, cb, interactive, ...) }
        UIManager.show, UIManager.forceRePaint = show, repaint
        if not res[1] then error(res[2]) end
        -- KOReader's scan found no network: the Kindle's own saved network
        if res[2] == false and Net.joinSaved() then
            if cb then cb() end -- (KOReader's connectivity check waits for it)
            return nil
        end
        return unpack(res, 2)
    end
    NetworkMgr.reconnectOrShowNetworkMenu = Net._scan
end
Net._wrapScan = wrapScan -- (for the tests)

--- KOReader's scan came back empty: a Paperwhite 3 and a Touch, right after
--- KOReader or the Kindle restarted, had "Initial Wi-Fi scan yielded no
--- results" twice within a second on every try (2026-11-08, 2026-11-17),
--- while ZenOS's Wi-Fi menu still connected them. As that menu does: ask the
--- Kindle's connection manager to join the network it has saved
--- (com.lab126.cmd ensureConnection). True when asked. The network's name is
--- never logged. Net._lipc: tests.
function Net.joinSaved()
    local okd, Device = pcall(require, "device")
    if not (okd and Device.isKindle and Device:isKindle()) then return false end
    local lipc = Net._lipc
    if not lipc then
        local ok, l = pcall(require, "libopenlipclua")
        if not ok or type(l) ~= "table" or type(l.open_no_name) ~= "function" then return false end
        lipc = l
    end
    local okh, h = pcall(lipc.open_no_name)
    if not okh or not h then return false end
    local input, result, profiles
    pcall(function()
        input = h:new_hasharray()
        result = h:access_hash_property("com.lab126.wifid", "profileData", input)
        profiles = result and result:to_table()
    end)
    if result then pcall(result.destroy, result) end
    if input then pcall(input.destroy, input) end
    local essid
    for _i, p in ipairs(type(profiles) == "table" and profiles or {}) do
        if type(p) == "table" and type(p.essid) == "string" and p.essid ~= "" then essid = p.essid break end
    end
    local asked = false
    if essid then
        asked = pcall(h.set_string_property, h, "com.lab126.cmd", "ensureConnection", "wifi:" .. essid)
    end
    pcall(h.close, h)
    if asked then
        Log.info("wifi: the scan found no network; asked the Kindle to join its saved one (" .. #profiles .. " saved)")
    elseif essid then
        Log.warn("wifi: the scan found no network, and the Kindle refused to join its saved one")
    else
        Log.info("wifi: the scan found no network, and the Kindle has none saved")
    end
    return asked
end

--- Wi-Fi switched on or off by you anywhere else (KOReader's Wi-Fi menu, a
--- gesture, the network list): On or Off. (Net.setMode's own switching goes
--- through here too, with the mode already saved.)
local function userSwitched(on)
    Net.ours = false
    UIManager:unschedule(check)
    local m = on and "on" or "off"
    if Net.mode() == m then return end
    if on then Log.info("wifi: turned on by you; left on (Wi-Fi: on)")
    else Log.info("wifi: turned off by you; background work waits until you turn it on (Wi-Fi: off)") end
    saveMode(m)
end

local function wrapToggles()
    if NetworkMgr.toggleWifiOn ~= Net._toggle_on then
        local orig = NetworkMgr.toggleWifiOn
        Net._toggle_on = function(...)
            userSwitched(true)
            return orig(...)
        end
        NetworkMgr.toggleWifiOn = Net._toggle_on
    end
    if NetworkMgr.toggleWifiOff ~= Net._toggle_off then
        local orig = NetworkMgr.toggleWifiOff
        Net._toggle_off = function(...)
            userSwitched(false)
            return orig(...)
        end
        NetworkMgr.toggleWifiOff = Net._toggle_off
    end
    -- the quick panel and Wi-Fi menu turn it off with disableWifi(cb, interactive = true);
    -- GZreader's own calls aren't interactive
    if NetworkMgr.disableWifi ~= Net._disable then
        local orig = NetworkMgr.disableWifi
        Net._disable = function(self, cb, interactive, ...)
            if interactive == true then userSwitched(false) end
            return orig(self, cb, interactive, ...)
        end
        NetworkMgr.disableWifi = Net._disable
    end
    -- and on again (the toggle_wifi action: enableWifi(cb, interactive = true))
    if NetworkMgr.enableWifi ~= Net._enable then
        local orig = NetworkMgr.enableWifi
        Net._enable = function(self, cb, interactive, ...)
            if interactive == true then userSwitched(true) end
            return orig(self, cb, interactive, ...)
        end
        NetworkMgr.enableWifi = Net._enable
    end
end

--- Switch Wi-Fi on or off the way the quick panel always has (KOReader's
--- toggle_wifi action: its messages, ZenOS's network list when there's no
--- saved network). Tests replace it.
function Net._switch()
    local Dispatcher = require("dispatcher")
    Dispatcher:execute({ toggle_wifi = true })
end

--- Choose On, Off or Auto (the quick panel's tile, Settings → Wi-Fi). Returns true when Wi-Fi itself is being switched (KOReader shows
--- "Turning on Wi-Fi…" then).
function Net.setMode(m)
    if not VALID[m] then return end
    pcall(wrapToggles)
    saveMode(m)
    Net.ours = false
    UIManager:unschedule(check)
    local on = NetworkMgr:isWifiOn()
    if m == "on" and not on or m == "off" and on then
        local ok, err = pcall(Net._switch)
        if not ok then Log.warn("wifi: switching failed:", tostring(err)) end
        return true
    end
    if m == "auto" and on and not Net.connecting then
        -- on now: off once nothing has used it for a minute
        Net.ours = true
        Net.last_use = Net.clock()
        schedule()
    end
    return false
end

--- What each mode is called and what it does (the tile, the menu).
function Net.describe(m)
    local _ = require("gettext")
    m = m or Net.mode()
    if m == "on" then
        return { name = _("On"), tile = _("Wi-Fi on"), icon = "wifi",
            help = _("Wi-Fi stays on. If it goes off (after sleep, out of range), GZreader turns it on again when something needs it.") }
    elseif m == "off" then
        return { name = _("Off"), tile = _("Wi-Fi off"), icon = "wifi_off",
            help = _("Wi-Fi stays off. Syncing waits until Wi-Fi is on again; things you ask for (browsing Grimmory, a download, checking for updates) turn it on, then off again after a minute.") }
    end
    local on = NetworkMgr:isWifiOn()
    return { name = _("Auto"), tile = _("Wi-Fi auto"), icon = on and "wifi_auto" or "wifi_auto_off",
        help = _("Saves battery: GZreader turns Wi-Fi on by itself for browsing Grimmory, downloads, updates and syncing when a book opens or closes (and on wake after 15 minutes or more), then turns it off after a minute of not being used. Reading-position and bookmark changes made in between wait and go with the next sync.") }
end

--- Settings → Wi-Fi: On, Off, Auto (zenos common/gz_settings.lua
--- wifiItem adds ZenOS's network list under them).
function Net.menuItem()
    local _ = require("gettext")
    local items = {}
    for _i, m in ipairs(Net.MODES) do
        local d = Net.describe(m)
        items[#items + 1] = {
            text = m == "auto" and _("Auto (only when needed)") or d.name,
            help_text = d.help,
            radio = true,
            gz_wifi_mode = m,
            checked_func = function() return Net.mode() == m end,
            callback = function() Net.setMode(m) end,
        }
    end
    items[#items].separator = true
    return {
        text = _("Wi-Fi"),
        help_text = _("On: Wi-Fi stays on. Off: it stays off. Auto: GZreader turns it on when it needs it and off again after a minute unused. The quick panel's Wi-Fi tile goes through the three."),
        mandatory_func = function() return Net.describe().name end,
        sub_item_table = items,
    }
end

--- At start and after waking: Wi-Fi that's on and not turned on by the user
--- is managed like Wi-Fi GZreader turned on (off after IDLE_SECONDS unused).
function Net.adopt()
    pcall(wrapToggles) -- (again: ZenOS replaces these functions after we load)
    if Net.mode() == "on" or Net.ours or Net.connecting then return end
    if not NetworkMgr:isWifiOn() then return end
    Net.ours = true
    Net.last_use = Net.clock()
    Log.info("wifi: on but not needed: off in", Net.IDLE_SECONDS, "s unless something uses it")
    schedule()
end

--- KOReader's "Disable Wi-Fi connection when inactive" (auto_disable_wifi)
--- turned Wi-Fi off after 5 quiet minutes whatever the mode, On too. Its row
--- is gone from Settings → KOReader (zenos common/gz_settings.lua
--- KOREADER_HIDDEN), so a saved tick is cleared: Auto does that job.
--- Once only (gzreader_wifi_powersave_cleared): since 1.28.4 KOReader's
--- whole menu is in About → Advanced → KOReader settings, where it can be
--- ticked again on purpose.
function Net.forgetKOReaderPowersave()
    if G_reader_settings:isTrue("gzreader_wifi_powersave_cleared") then return false end
    G_reader_settings:makeTrue("gzreader_wifi_powersave_cleared")
    if G_reader_settings:isTrue("auto_disable_wifi") then
        G_reader_settings:delSetting("auto_disable_wifi")
        Log.info("wifi: KOReader's \"Disable Wi-Fi connection when inactive\" off (Wi-Fi Auto does that)")
        return true
    end
    return false
end

function Net.start()
    if Net.started then return end
    Net.started = true
    pcall(Net.forgetKOReaderPowersave)
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
