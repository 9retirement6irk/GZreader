--[[--
Headphones: are they plugged in? Pauses music, audiobooks and read aloud
when they're unplugged while playing (so the speaker doesn't suddenly play
out loud), if the Kindle says so.

How a Kindle says so isn't the same everywhere (and isn't documented), so
GZreader looks in the places Linux uses for it:
- an input device with a headphone switch (EV_SW, SW_HEADPHONE_INSERT: the
  state comes from the EVIOCGSW ioctl, without taking its events);
- a switch in sysfs (/sys/class/switch/*/state, as Android kernels have);
- what "Find the headphone jack" (Settings → Reader) found on this Kindle:
  it asks you to plug in and unplug headphones and keeps the one place that
  changed (a sysfs file, an input switch or an lipc property of
  com.lab126.audio). Until something is found, nothing is paused.
]]

local ffi = require("ffi")
local Log = require("gzreader_log")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

pcall(ffi.cdef, "int open(const char *pathname, int flags, ...);")
pcall(ffi.cdef, "int close(int fd);")
pcall(ffi.cdef, "int ioctl(int fd, unsigned long request, ...);")

local Jack = {
    INTERVAL = 1,
    SW_HEADPHONE_INSERT = 2,
    SETTING = "gzreader_jack",
    watchers = {},
    -- injectable (tests)
    read = nil,
    devices_file = "/proc/bus/input/devices",
}

local function readFile(p)
    if Jack.read then return Jack.read(p) end
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

--- Input devices with a headphone switch: { { event = "/dev/input/eventN", name } }.
function Jack.switchDevices()
    local text = readFile(Jack.devices_file) or ""
    local out = {}
    for block in (text .. "\n\n"):gmatch("(.-)\n\n") do
        local name = block:match('N: Name="([^"]*)"')
        local ev = block:match("H: Handlers=[^\n]-(event%d+)")
        local sw = block:match("B: SW=(%x+)")
        if ev and sw then
            local bits = tonumber(sw:sub(-8), 16) or 0
            if bit.band(bits, bit.lshift(1, Jack.SW_HEADPHONE_INSERT)) ~= 0 then
                out[#out + 1] = { event = "/dev/input/" .. ev, name = name }
            end
        end
    end
    return out
end

--- EVIOCGSW: the switch bits of an input device, or nil.
function Jack.switchBits(path)
    if Jack.read then
        local s = Jack.read(path .. "#sw")
        return s and tonumber(s)
    end
    local fd = ffi.C.open(path, 0x800) -- O_RDONLY | O_NONBLOCK
    if fd < 0 then return nil end
    local buf = ffi.new("uint8_t[8]")
    local req = bit.bor(bit.lshift(2, 30), bit.lshift(8, 16), bit.lshift(0x45, 8), 0x1b) -- _IOC(READ, 'E', 0x1b, 8)
    local r = ffi.C.ioctl(fd, ffi.cast("unsigned long", bit.tobit(req)), buf)
    ffi.C.close(fd)
    if r < 0 then return nil end
    return buf[0] + buf[1] * 256
end

local function sysfsSwitches()
    local out = {}
    local base = "/sys/class/switch"
    if not Jack.read and lfs.attributes(base, "mode") ~= "directory" then return out end
    local names = {}
    if Jack.read then
        for n in (Jack.read(base .. "#list") or ""):gmatch("%S+") do names[#names + 1] = n end
    else
        for n in lfs.dir(base) do if n ~= "." and n ~= ".." then names[#names + 1] = n end end
    end
    for _i, n in ipairs(names) do
        local l = n:lower()
        if l:find("h2w") or l:find("head") or l:find("jack") or l:find("phone") then out[#out + 1] = base .. "/" .. n .. "/state" end
    end
    return out
end

--- How to tell, on this Kindle: { kind = "switch", path } | { kind = "file",
--- path, on } | { kind = "lipc", prop, on }, or nil.
function Jack.detector()
    local saved = G_reader_settings:readSetting(Jack.SETTING)
    if type(saved) == "table" and saved.kind then return saved end
    local devs = Jack.switchDevices()
    if devs[1] then return { kind = "switch", path = devs[1].event } end
    local sw = sysfsSwitches()
    if sw[1] then return { kind = "file", path = sw[1], on = "nonzero" } end
    return nil
end

local function lipcGet(prop)
    if Jack.read then return Jack.read("lipc:" .. prop) end
    local p = io.popen("lipc-get-prop com.lab126.audio " .. prop .. " 2>/dev/null")
    if not p then return nil end
    local s = p:read("*a")
    p:close()
    return trim(s)
end

--- true: headphones in; false: out; nil: can't tell on this Kindle.
function Jack.plugged(det)
    det = det or Jack.detector()
    if not det then return nil end
    if det.kind == "switch" then
        local bits = Jack.switchBits(det.path)
        if not bits then return nil end
        return bit.band(bits, bit.lshift(1, Jack.SW_HEADPHONE_INSERT)) ~= 0
    end
    local v
    if det.kind == "file" then v = readFile(det.path) elseif det.kind == "lipc" then v = lipcGet(det.prop) end
    if v == nil then return nil end
    v = trim(v)
    if det.on == "nonzero" then return v ~= "" and v ~= "0" end
    return v == det.on
end

---------------------------------------------------------------- watching

--- While something plays: call on_unplug() when the headphones come out.
--- key: "music", "audiobook", "tts".
function Jack.watch(key, on_unplug)
    if G_reader_settings:readSetting("gzreader_jack_pause") == false then return end
    local det = Jack.detector()
    if not det then return end
    Jack.watchers[key] = on_unplug
    if Jack.ticker then return end
    Jack.last = Jack.plugged(det)
    Jack.ticker = function()
        Jack.ticker = nil
        if not next(Jack.watchers) then return end
        local now = Jack.plugged(det)
        if Jack.last == true and now == false then
            Log.info("headphones unplugged: pausing")
            local list = Jack.watchers
            Jack.watchers = {}
            for _k, fn in pairs(list) do pcall(fn) end
        end
        Jack.last = now
        if next(Jack.watchers) then
            Jack.ticker = Jack.tick_fn
            UIManager:scheduleIn(Jack.INTERVAL, Jack.ticker)
        end
    end
    Jack.tick_fn = Jack.ticker
    UIManager:scheduleIn(Jack.INTERVAL, Jack.ticker)
end

function Jack.unwatch(key)
    Jack.watchers[key] = nil
    if not next(Jack.watchers) and Jack.ticker then
        UIManager:unschedule(Jack.ticker)
        Jack.ticker = nil
    end
end

---------------------------------------------------------------- finding it

--- Everything that could say "headphones": name -> value.
function Jack.snapshot()
    local snap = {}
    for _i, d in ipairs(Jack.switchDevices()) do snap["switch:" .. d.event] = tostring(Jack.switchBits(d.event)) end
    -- every input device's switches, even without the headphone bit
    local text = readFile(Jack.devices_file) or ""
    for ev in text:gmatch("H: Handlers=[^\n]-(event%d+)") do
        local p = "/dev/input/" .. ev
        if not snap["switch:" .. p] then snap["anyswitch:" .. p] = tostring(Jack.switchBits(p)) end
    end
    for _i, p in ipairs(sysfsSwitches()) do snap["file:" .. p] = trim(readFile(p)) end
    if not Jack.read then
        -- sysfs files named like a jack (a shallow look: the sound and platform devices)
        local h = io.popen("find /sys/devices/platform /sys/class/sound /sys/devices/virtual -maxdepth 4 \\( -iname '*headphone*' -o -iname '*hp_det*' -o -iname '*hpdet*' -o -iname '*jack*' -o -iname '*headset*' \\) -type f 2>/dev/null | head -40")
        if h then
            for p in h:lines() do snap["file:" .. p] = trim(readFile(p)) end
            h:close()
        end
        -- com.lab126.audio's properties (Amazon's audio service)
        local lp = io.popen("lipc-probe -v com.lab126.audio 2>/dev/null")
        if lp then
            for line in lp:lines() do
                local prop = line:match("^%s+%a+%s+%a+%s+([%w_]+)%s*$") or line:match("^%s*([%w_]+)%s*$")
                if prop and #prop > 2 then snap["lipc:" .. prop] = lipcGet(prop) end
            end
            lp:close()
        end
    else
        for p in (Jack.read("#files") or ""):gmatch("%S+") do snap["file:" .. p] = trim(readFile(p)) end
        for prop in (Jack.read("#lipc") or ""):gmatch("%S+") do snap["lipc:" .. prop] = lipcGet(prop) end
    end
    return snap
end

--- Compare plugged-in and unplugged: the detector, or nil, and what changed.
function Jack.compare(with, without)
    local changed = {}
    for k, v in pairs(with) do
        if without[k] ~= nil and without[k] ~= v then changed[#changed + 1] = k end
    end
    table.sort(changed, function(a, b)
        local rank = function(k) return k:match("^switch:") and 0 or k:match("^file:") and 1 or k:match("^lipc:") and 2 or 3 end
        return rank(a) < rank(b) or (rank(a) == rank(b) and a < b)
    end)
    local k = changed[1]
    if not k then return nil, changed end
    local kind, where = k:match("^(%w+):(.*)$")
    if kind == "switch" then return { kind = "switch", path = where }, changed end
    if kind == "anyswitch" then return { kind = "bits", path = where, on_bits = tonumber(with[k]) }, changed end
    if kind == "file" then return { kind = "file", path = where, on = with[k] }, changed end
    if kind == "lipc" then return { kind = "lipc", prop = where, on = with[k] }, changed end
    return nil, changed
end

--- The guided test: plug in, unplug; keeps what changed.
function Jack.test(on_done)
    local ConfirmBox = require("ui/widget/confirmbox")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    local T = require("ffi/util").template
    -- (the Kindle's messages, heard while you plug in and unplug: see below)
    Jack.listen()
    local mark = Jack.syslogSize()
    UIManager:show(ConfirmBox:new{
        text = _("Plug headphones into the Kindle, then press Next."),
        ok_text = _("Next"),
        cancel_callback = function() Jack.stopListening() end,
        ok_callback = function()
            local with = Jack.snapshot()
            local heard_in = Jack.heard(mark)
            mark = Jack.syslogSize()
            UIManager:show(ConfirmBox:new{
                text = _("Now unplug them, then press Next."),
                ok_text = _("Next"),
                cancel_callback = function() Jack.stopListening() end,
                ok_callback = function()
                    local without = Jack.snapshot()
                    local heard_out = Jack.heard(mark)
                    Jack.stopListening()
                    local det, changed = Jack.compare(with, without)
                    det = det or Jack.fromEvents(heard_in, heard_out)
                    local n = 0
                    for _k in pairs(with) do n = n + 1 end
                    Log.info("headphone test: looked at", n, "places; changed:", table.concat(changed, ", "),
                        "| messages plugging in:", Jack.describeEvents(heard_in), "| unplugging:", Jack.describeEvents(heard_out))
                    if det then
                        G_reader_settings:saveSetting(Jack.SETTING, det)
                        UIManager:show(InfoMessage:new{ text = T(_("Found it (%1). Music, audiobooks and read aloud now pause when headphones are unplugged."),
                            det.path or det.prop or (det.name and (Jack.EVENT_SOURCE .. " " .. det.name))) })
                    else
                        UIManager:show(InfoMessage:new{ text = _("Nothing on this Kindle changed when the headphones were plugged in or out, so GZreader can't tell. Saving the diagnostic log (Settings → General) and sending it helps find another way.") })
                    end
                    if on_done then on_done(det) end
                end,
            })
        end,
    })
end

-- (a found input switch without the headphone bit: compare the whole bits)
local plugged = Jack.plugged
function Jack.plugged(det)
    det = det or Jack.detector()
    if det and det.kind == "bits" then
        local b = Jack.switchBits(det.path)
        if not b then return nil end
        return b == det.on_bits
    end
    if det and det.kind == "event" then return nil end -- (a message, not a state: see below)
    return plugged(det)
end

---------------------------------------------------------------- the Kindle's messages

--[[ The Kindle 3 shows headphones in none of the places above: its test
found no input switch, no sysfs file and no com.lab126.audio property that
changed. Its hardware service, com.lab126.hal, sends a message instead,
"audioHS" with 1 or 0 (seen in a Kindle 3's system log). A message can't be
looked at afterwards, so:
- "Find the headphone jack" listens while you plug in and unplug (an
  lipc-wait-event process writing what it hears to a file, and the system
  log, where lipc-send-event notes each message it sends), and keeps
  { kind = "event", name, on, off } when the message changed between the two;
- while something plays, one lipc-wait-event process listens and GZreader
  reads its file every second (no shell each time), pausing on the "off"
  message. ]]
Jack.EVENT_SOURCE = "com.lab126.hal"
Jack.EVENT_NAMES = "audioHS"
Jack.EVENTS_FILE = "/tmp/gzreader-jack-events"
Jack.SYSLOG = "/var/log/messages"

local function sh(cmd)
    if Jack.exec then return Jack.exec(cmd) end
    return os.execute(cmd)
end

local function kill(pid)
    if Jack.kill then return Jack.kill(pid) end
    pcall(function()
        pcall(require, "ffi/posix_h")
        pcall(ffi.cdef, "int kill(int pid, int sig);")
        ffi.C.kill(pid, 15)
    end)
end

--- Start listening for the Kindle's headphone messages (one listener).
function Jack.listen()
    Jack.stopListening()
    local file = Jack.EVENTS_FILE
    os.remove(file)
    Jack.listening = { file = file, seen = 0 }
    sh(string.format("(lipc-wait-event -m %s %s > %s 2>/dev/null & echo $! > %s.pid) >/dev/null 2>&1",
        Jack.EVENT_SOURCE, Jack.EVENT_NAMES, file, file))
end

function Jack.stopListening()
    local l = Jack.listening
    if not l then return end
    Jack.listening = nil
    local pid = tonumber(trim(readFile(l.file .. ".pid")))
    if pid then kill(pid) end
    os.remove(l.file .. ".pid")
    os.remove(l.file)
end

--- What the listener heard since the last call: { { name, value } }.
function Jack.readEvents()
    local l = Jack.listening
    if not l then return {} end
    local out, n = {}, 0
    for line in (readFile(l.file) or ""):gmatch("([^\n]*)\n") do -- (whole lines only)
        n = n + 1
        if n > l.seen then
            local name, value = line:match("^%s*([%w_]+)%s*(.-)%s*$")
            if name then out[#out + 1] = { name = name, value = value } end
        end
    end
    l.seen = math.max(l.seen, n)
    return out
end

--- The system log's size: where to read on from.
function Jack.syslogSize()
    if Jack.read then return #(Jack.read(Jack.SYSLOG) or "") end
    return lfs.attributes(Jack.SYSLOG, "size") or 0
end

--- Messages from the Kindle's hardware service noted in the system log since `mark`.
function Jack.syslogEvents(mark)
    local text
    if Jack.read then
        text = (Jack.read(Jack.SYSLOG) or ""):sub((mark or 0) + 1)
    else
        local f = io.open(Jack.SYSLOG, "rb")
        if not f then return {} end
        local size = f:seek("end")
        f:seek("set", (mark and mark <= size) and mark or 0) -- (a new log: from its start)
        text = f:read("*a") or ""
        f:close()
    end
    local out = {}
    local src = Jack.EVENT_SOURCE:gsub("%.", "%%.")
    for name, value in text:gmatch("name=([%w_]+), origin=" .. src .. ", fparam=([%-%w]+)") do
        out[#out + 1] = { name = name, value = value }
    end
    return out
end

--- Everything heard since `mark` (the listener's, else the system log's).
function Jack.heard(mark)
    local ev = Jack.readEvents()
    if #ev == 0 then ev = Jack.syslogEvents(mark) end
    return ev
end

function Jack.describeEvents(list)
    local out = {}
    for _i, e in ipairs(list or {}) do out[#out + 1] = e.name .. " " .. e.value end
    return #out > 0 and table.concat(out, ", ") or "none"
end

--- From the messages heard plugging in and unplugging: the detector, or nil.
function Jack.fromEvents(heard_in, heard_out)
    local function last(list)
        local t, order = {}, {}
        for _i, e in ipairs(list or {}) do
            if t[e.name] == nil then order[#order + 1] = e.name end
            t[e.name] = e.value
        end
        return t, order
    end
    local on, order_in = last(heard_in)
    local off, order_out = last(heard_out)
    local names = {}
    for _i, n in ipairs(order_out) do names[#names + 1] = n end
    for _i, n in ipairs(order_in) do if off[n] == nil then names[#names + 1] = n end end
    table.sort(names, function(a, b)
        local pa, pb = Jack.EVENT_NAMES:find(a, 1, true) and 0 or 1, Jack.EVENT_NAMES:find(b, 1, true) and 0 or 1
        return pa < pb or (pa == pb and a < b)
    end)
    for _i, n in ipairs(names) do
        if off[n] ~= nil and on[n] ~= off[n] then
            return { kind = "event", source = Jack.EVENT_SOURCE, name = n, on = on[n], off = off[n] }
        end
    end
    return nil
end

local watch, unwatch = Jack.watch, Jack.unwatch

function Jack.watch(key, on_unplug)
    local det = Jack.detector()
    if not (det and det.kind == "event") then return watch(key, on_unplug) end
    if G_reader_settings:readSetting("gzreader_jack_pause") == false then return end
    Jack.watchers[key] = on_unplug
    if Jack.event_ticker then return end
    Jack.listen()
    local function tick()
        Jack.event_ticker = nil
        if not next(Jack.watchers) then return Jack.stopListening() end
        for _i, e in ipairs(Jack.readEvents()) do
            if e.name == det.name and ((det.off ~= nil and e.value == det.off) or (det.off == nil and e.value ~= det.on)) then
                Log.info("headphones unplugged (" .. e.name .. " " .. e.value .. "): pausing")
                local list = Jack.watchers
                Jack.watchers = {}
                for _k, fn in pairs(list) do pcall(fn) end
                break
            end
        end
        if next(Jack.watchers) then
            Jack.event_ticker = tick
            UIManager:scheduleIn(Jack.INTERVAL, tick)
        else
            Jack.stopListening()
        end
    end
    Jack.event_ticker = tick
    UIManager:scheduleIn(Jack.INTERVAL, tick)
end

function Jack.unwatch(key)
    unwatch(key)
    if Jack.event_ticker and not next(Jack.watchers) then
        UIManager:unschedule(Jack.event_ticker)
        Jack.event_ticker = nil
        Jack.stopListening()
    end
end

return Jack
