--[[--
Keep the Kindle awake while something long runs (a download, an audiobook).

Holders are counted, so a finished download doesn't let the Kindle sleep
while an audiobook still plays. While held:
- the Kindle framework's screensaver is blocked (powerd preventScreenSaver);
- KOReader's autosuspend is told every 50 s that there was activity.

Each holder can say how to tell it's still needed (`still`): every 50 s a
holder that isn't (a player that stopped on an error path, a download that
ended without saying so) is let go, and the log says which. Until 1.23.8 one
such holder kept a Kindle 3 from ever sleeping. The Kindle's own block is
also lifted when GZreader starts (`Awake.reset`): a block left by GZreader
closing or crashing mid-download outlived it (it's powerd's, not ours).
]]

local UIManager = require("ui/uimanager")
local Event = require("ui/event")

local Awake = {
    holders = {}, count = 0, exec = os.execute,
    TICK = 50,
    REPORT_EVERY = 600, -- (the log says who keeps it awake, every 10 minutes)
}

local function log(...)
    local ok, Log = pcall(require, "gzreader_log")
    if ok and Log and Log.info then pcall(Log.info, ...) end
end

local function powerd(on)
    Awake.exec(string.format("lipc-set-prop -i com.lab126.powerd preventScreenSaver %d >/dev/null 2>&1 &", on and 1 or 0))
end

local function isKindle()
    local ok, Device = pcall(require, "device")
    return ok and Device.isKindle and Device:isKindle() or false
end

--- Who holds it, for the log (kinds only: no paths, names or titles).
function Awake.who()
    local names = {}
    for _key, h in pairs(Awake.holders) do names[#names + 1] = h.what end
    table.sort(names)
    return table.concat(names, ", ")
end

local function whatOf(key, opts)
    if opts and opts.what then return opts.what end
    if type(key) == "string" then return key:match("^[%a]+") or "?" end
    return "?"
end

--- Let go of holders that say they aren't needed any more.
function Awake.prune()
    local stale = {}
    for key, h in pairs(Awake.holders) do
        if h.still then
            local ok, needed = pcall(h.still)
            if ok and not needed then stale[#stale + 1] = key end
        end
    end
    for _i, key in ipairs(stale) do
        log("awake: let go of", Awake.holders[key].what, "(it had ended without saying so)")
        Awake.release(key)
    end
end

local function tick()
    Awake.prune()
    if Awake.count == 0 then Awake.ticking = false; return end
    UIManager:broadcastEvent(Event:new("InputEvent"))
    local now = os.time()
    if now - (Awake.reported or 0) >= Awake.REPORT_EVERY then
        Awake.reported = now
        log("awake: kept awake by", Awake.who())
    end
    UIManager:scheduleIn(Awake.TICK, tick)
end
Awake.tick = tick

--- Keep awake for `key` (any value). `opts.still`: a function, true while
--- it's still needed; `opts.what`: its kind, for the log.
function Awake.hold(key, opts)
    if Awake.holders[key] then return end
    Awake.holders[key] = { what = whatOf(key, opts), still = opts and opts.still, since = os.time() }
    Awake.count = Awake.count + 1
    if Awake.count == 1 then
        powerd(true)
        Awake.reported = os.time()
    end
    log("awake: kept awake for", Awake.holders[key].what)
    if not Awake.ticking then
        Awake.ticking = true
        UIManager:scheduleIn(Awake.TICK, tick)
    end
end

function Awake.release(key)
    local h = Awake.holders[key]
    if not h then return end
    Awake.holders[key] = nil
    Awake.count = Awake.count - 1
    log("awake: done with", h.what, "after", (os.time() - h.since) .. "s")
    if Awake.count == 0 then
        powerd(false)
        UIManager:unschedule(tick)
        Awake.ticking = false
    end
end

function Awake.held(key) return Awake.holders[key] ~= nil end

--- GZreader starting: nothing of ours holds the Kindle awake yet, so lift a
--- block an earlier run left (closed or crashed mid-download).
function Awake.reset()
    if Awake.count > 0 or Awake.was_reset or not isKindle() then return end
    Awake.was_reset = true
    powerd(false)
end

return Awake
