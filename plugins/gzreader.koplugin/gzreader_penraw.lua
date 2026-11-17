--[[--
The pen's pressure and tilt, read from the digitizer itself (Kindle Scribe).

KOReader opens Amazon's `stylus-custom` device for the pen (its positions
are already scaled to the screen). On the owner's Scribe 27 strokes went by
without one pressure or tilt value reaching the drawing screen (the log of
2026-11-17: no "drawing: pen pressure" line), so that device doesn't pass
them on. The digitizer under it, `WacomDigitizer`, does report them. It
can't simply be opened by KOReader as well: its positions aren't scaled,
and the pen would be seen twice. So the drawing screen reads it on the
side, only while it's open, and takes nothing from it but ABS_PRESSURE,
ABS_TILT_X and ABS_TILT_Y. The device isn't grabbed and nothing is written.

`PenRaw.eventOf(text, name)` and `PenRaw.take(state, type, code, value)`
are the pure parts (tested); `open`, `read` and `close` do the reading.
]]

local PenRaw = {
    NAME = "WacomDigitizer",
    EV_ABS = 3, ABS_PRESSURE = 0x18, ABS_TILT_X = 0x1a, ABS_TILT_Y = 0x1b,
    BATCH = 64,
}

--- The eventN of the input device called `name`, from /proc/bus/input/devices' text.
function PenRaw.eventOf(text, name)
    for block in (tostring(text or "") .. "\n\n"):gmatch("(.-)\n%s*\n") do
        if block:match('N: Name="' .. name:gsub("%p", "%%%0") .. '"') then
            local ev = block:match("H: Handlers=[^\n]-(event%d+)")
            if ev then return ev end
        end
    end
end

--- One event from the digitizer: its pressure and tilt kept in `state`
--- ({ pressure, tilt_x, tilt_y, n }); anything else is passed over.
function PenRaw.take(state, etype, code, value)
    if etype ~= PenRaw.EV_ABS then return false end
    if code == PenRaw.ABS_PRESSURE then state.pressure = value
    elseif code == PenRaw.ABS_TILT_X then state.tilt_x = value
    elseif code == PenRaw.ABS_TILT_Y then state.tilt_y = value
    else return false end
    state.n = (state.n or 0) + 1
    return true
end

local function slurp(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- What a device says it reports (its EV_ABS bits, as the kernel prints
--- them: numbers only), for the log.
function PenRaw.absCaps(event)
    local s = slurp("/sys/class/input/" .. event .. "/device/capabilities/abs")
    return s and s:gsub("%s+$", "") or "?"
end

--- Opens the digitizer for reading (nil, why when it can't be).
function PenRaw.open(name)
    name = name or PenRaw.NAME
    local event = PenRaw.eventOf(slurp("/proc/bus/input/devices"), name)
    if not event then return nil, "no " .. name end
    local ok, res = pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        require("ffi/linux_input_h")
        local C = ffi.C
        local fd = C.open("/dev/input/" .. event, bit.bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
        if fd < 0 then return nil end
        local size = ffi.sizeof("struct input_event")
        return { fd = fd, event = event, name = name, size = size, buf = ffi.new("struct input_event[?]", PenRaw.BATCH),
            state = { n = 0 }, ffi = ffi, C = C }
    end)
    if not ok or not res then return nil, ok and "couldn't open /dev/input/" .. event or tostring(res) end
    return res
end

--- Takes in what the digitizer has reported since the last call (it never
--- waits); the latest pressure and tilt are in `raw.state`.
function PenRaw.read(raw)
    if not raw or not raw.fd then return nil end
    local C, total = raw.C, raw.size * PenRaw.BATCH
    for _round = 1, 16 do -- (at most 1024 events a call)
        local got = tonumber(C.read(raw.fd, raw.buf, total))
        if not got or got < raw.size then break end
        for i = 0, math.floor(got / raw.size) - 1 do
            local ev = raw.buf[i]
            PenRaw.take(raw.state, ev.type, ev.code, ev.value)
        end
        if got < total then break end
    end
    return raw.state
end

function PenRaw.close(raw)
    if raw and raw.fd then pcall(raw.C.close, raw.fd); raw.fd = nil end
end

return PenRaw
