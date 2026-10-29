--[[--
Keep the Kindle awake while something long runs (a download, an audiobook).

Holders are counted, so a finished download doesn't let the Kindle sleep
while an audiobook still plays. While held:
- the Kindle framework's screensaver is blocked (powerd preventScreenSaver);
- KOReader's autosuspend is told every 50 s that there was activity.
]]

local UIManager = require("ui/uimanager")
local Event = require("ui/event")

local Awake = { holders = {}, count = 0, exec = os.execute }

local function powerd(on)
    Awake.exec(string.format("lipc-set-prop -i com.lab126.powerd preventScreenSaver %d >/dev/null 2>&1 &", on and 1 or 0))
end

local function tick()
    if Awake.count == 0 then Awake.ticking = false; return end
    UIManager:broadcastEvent(Event:new("InputEvent"))
    UIManager:scheduleIn(50, tick)
end

function Awake.hold(key)
    if Awake.holders[key] then return end
    Awake.holders[key] = true
    Awake.count = Awake.count + 1
    if Awake.count == 1 then powerd(true) end
    if not Awake.ticking then
        Awake.ticking = true
        UIManager:scheduleIn(50, tick)
    end
end

function Awake.release(key)
    if not Awake.holders[key] then return end
    Awake.holders[key] = nil
    Awake.count = Awake.count - 1
    if Awake.count == 0 then
        powerd(false)
        UIManager:unschedule(tick)
        Awake.ticking = false
    end
end

function Awake.held(key) return Awake.holders[key] == true end

return Awake
