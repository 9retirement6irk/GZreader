--[[--
Wi-Fi power saving off while a book or an update downloads.

With power saving on, the Wi-Fi chip naps between the access point's beacons
and takes in a few packets per wake: the owner's Paperwhite 3 downloaded at
~30 KB/s and his Kindle Scribe installed an update at ~5 KB/s (2026-11-15/16),
where the same Kindles reach ~1 MB/s. The Nook's start script turns it off
for good (1.26.7); on a Kindle it's turned off only while `Net.hold` has a
transfer key (download, update) and put back as it was when the last one ends,
so reading with Wi-Fi on still saves the battery. The same for audiobook and
music downloads, notes with drawings going to Memos, and while the phone page
is open (uploads from the phone).

Through the wireless extensions ioctl (`device/nook/wifi_power.lua`,
SIOCGIWPOWER/SIOCSIWPOWER): it reads and writes only power saving's state,
never the network's name. Where that ioctl isn't there (no Wi-Fi, a driver
without it), nothing happens and the reason is logged once per transfer.

Not on the Kindle 3: its driver accepted "off" but still read "on", and the
update it was downloading crawled at 1–8 KB/s with waits of up to 29 s and
broke off (2026-11-17; it downloaded at ~250 KB/s before). Anywhere else a
driver that accepts "off" but doesn't take it gets power saving put back at
once, and isn't asked again until GZreader restarts.
]]

local Log = require("gzreader_log")

local PS = {
    -- big transfers: Net.hold's keys for books, updates, audiobooks
    -- ("audiobook-download-<id>") and music ("music-<folder>"), and the keys
    -- Memos uploads and the phone page pass to PS.hold themselves
    KEYS = { download = true, update = true, ["memos-upload"] = true, phone = true },
    PREFIXES = { "audiobook-download-", "music-" },
    holding = {},     -- keys of PS.KEYS now held
    restore = false,  -- we turned it off: put it back on at the end
    io = nil,         -- tests: { get = fn(ifname), set = fn(ifname, on) }
    -- models it's never touched on (see above)
    SKIP_MODELS = { Kindle3 = true },
    ignored = false,  -- "off" didn't take on this Kindle: not asked again
    model = nil,      -- tests: the device's model
}

local function model()
    if PS.model then return PS.model end
    local ok, Device = pcall(require, "device")
    return ok and type(Device) == "table" and Device.model or nil
end

--- The Wi-Fi interface's name (wlan0 on every Kindle; eth0 on the Nook).
function PS.ifname()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if ok and type(NetworkMgr) == "table" and NetworkMgr.getNetworkInterfaceName then
        local okn, name = pcall(NetworkMgr.getNetworkInterfaceName, NetworkMgr)
        if okn and type(name) == "string" and name ~= "" then return name end
    end
    return "wlan0"
end

local function io()
    if PS.io then return PS.io end
    local ok, WP = pcall(require, "device/nook/wifi_power")
    if not ok then return { get = function() return nil, tostring(WP) end, set = function() return nil, tostring(WP) end } end
    return WP
end

--- "on", "off", or nil, why.
function PS.get()
    local ok, state, err = pcall(io().get, PS.ifname())
    if not ok then return nil, tostring(state) end
    return state, err
end

local function set(on)
    local ok, res, err = pcall(io().set, PS.ifname(), on)
    if not ok then return nil, tostring(res) end
    return res, err
end

--- Whether `key` is a big transfer.
function PS.transfer(key)
    if type(key) ~= "string" then return false end
    if PS.KEYS[key] then return true end
    for _i, p in ipairs(PS.PREFIXES) do
        if key:sub(1, #p) == p then return true end
    end
    return false
end

--- Net.hold(key): the first transfer turns power saving off (if it was on).
function PS.hold(key)
    if not PS.transfer(key) or PS.holding[key] then return end
    local first = next(PS.holding) == nil
    PS.holding[key] = true
    if not first then return end
    if PS.SKIP_MODELS[model() or ""] or PS.ignored then return end
    local state, why = PS.get()
    if state ~= "on" then
        if not state then Log.info("wifi: power saving unknown, left as it is (" .. tostring(why) .. ")") end
        return
    end
    local ok, err = set(false)
    if ok and PS.get() ~= "off" then
        -- accepted but not taken: back as it was, and left alone from now on
        set(true)
        PS.ignored = true
        Log.info("wifi: power saving didn't turn off (driver); left on")
    elseif ok then
        PS.restore = true
        Log.info("wifi: power saving off while transferring (" .. key .. ")")
    else
        Log.warn("wifi: couldn't turn power saving off:", tostring(err))
    end
end

--- Net.release(key): after the last transfer, power saving back on if we turned it off.
function PS.release(key)
    if not PS.holding[key] then return end
    PS.holding[key] = nil
    if next(PS.holding) ~= nil or not PS.restore then return end
    PS.restore = false
    local ok, err = set(true)
    if ok then
        Log.info("wifi: power saving back on")
    else
        Log.info("wifi: couldn't turn power saving back on:", tostring(err))
    end
end

return PS
