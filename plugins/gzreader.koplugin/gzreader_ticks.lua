--[[--
GZreader's periodic timers, lined up on the clock.

While you read, the Kindle sleeps between events; every timer that fires on
its own wakes it. GZreader's own (usage statistics every 30 s, the remote
debugging heartbeat every 15 s, the Wi-Fi idle check while its Wi-Fi is on)
used to fire at their own offsets, each a wake-up. Lined up on the wall
clock's quarter minutes (:00, :15, :30, :45), they fire together, also with
ZenOS's clock, which ticks on the minute.
]]

local Ticks = { now = nil } -- (injectable: wall-clock seconds, fractional)

local function wall()
    if Ticks.now then return Ticks.now() end
    local ok, socket = pcall(require, "socket")
    if ok and socket and socket.gettime then return socket.gettime() end
    return os.time()
end

--- Seconds until the next multiple of `period` seconds on the wall clock
--- (a moment after it, so the timers due then are all due together).
function Ticks.untilNext(period)
    local t = wall()
    local left = period - (t % period)
    if left < 0.5 then left = left + period end
    return left + 0.05
end

return Ticks
