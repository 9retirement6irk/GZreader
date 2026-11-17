--[[--
Read aloud for GZreader on the Kindle Keyboard, using the Kindle's own
text-to-speech voice (the one behind Amazon's "Experimental → Text-to-Speech").

What the diagnostic logs showed on a Kindle 3 (firmware 3.4.3):
- Amazon's speech daemon /usr/sbin/ttsd is running and reachable over lipc:
  com.lab126.ttsd  playSnippetNow / enqueueSnippet (hash properties),
                   cancelSnippetPlayback, pause2, unpause2
  com.lab126.tts   playFile (hash), stop, pause, unpause, TtsISpeed [100],
                   TtsSVoice [Tom]
- KOReader's lipc library doesn't load there, so requests go through the
  Kindle's lipc-hash-prop tool: {key = "string", key2 = (int)} on stdin.
- Amazon never documented the fields. ttsd says in /var/log/messages which
  one it is missing ("enqueueSnippet unable to read id", "… unable to read
  text"), so "Find the Kindle voice" learns the request shape from those
  messages: it adds the missing field, retries, and stops when ttsd accepts
  it; then it asks whether you heard the test sentence. The shape is saved.

What the diagnostic log showed on a Kindle DX (firmware 2.5.8): no
com.lab126.ttsd and no lipc-hash-prop; ttsd answers as com.lab126.tts:
playFile (a string: a text file's path; ttsd reads the file and says it),
stop, pause, unpause, TtsISpeed, TtsSVoice [Tom], TextToProcess. So the
discovery also tries writing the sentence to a file and handing ttsd its
path (lipc-set-prop -s com.lab126.tts playFile <file>). ttsd has no queue
and sends no events there: one sentence at a time, paced by estimates.

A later DX log: ttsd refused a plain text file ("playFile: wrong file", before
it even opened it). Kindle 2/3 firmware feeds ttsd through a named pipe,
/var/tmp/ttsUSFifo (the stock reader writes the text into it): so the
discovery first hands ttsd that pipe's path and writes the sentence into it
(`fifo` targets), then falls back to plain text files.

Reading: one sentence at a time (crengine sentence boundaries). The sentence
being spoken is highlighted, pages turn by themselves, Shift + Sym plays and
stops (like the stock Kindle). The next sentence starts after a time worked
out from the sentence length and the speed setting.

Kindles with Bluetooth on firmware 5.x (a Scribe on 5.20.2, the owner's,
over SSH): no ttsd. Amazon's Ivona voice (the one behind Assistive Reader)
is einkttsdaemon, upstart job eink_ttsd (not running until something starts
it), on lipc as com.lab126.ivonatts:
  playSnippet  (string) the text itself, spoken as given (JSON is read out
               too); requests queue: a second one waits for the first
  stopReading  (string) stops at once
  speechRate   (string) "1" normal, "1.5" faster
  ivonaStarted (int) 1 once it's up
It sends no lipc events (none with lipc-wait-event, nor from playermgr or
audiomgrd), but it writes its audio to Amazon's mixer in 2400-byte buffers
and says so in the system log ("einkttsd[pid]: … ReleaseBufPlay
numBytes=2400 …", every 40 ms); each sentence's last buffer is shorter
(1438, 2398 on the Scribe), logged when that sentence's sound ends. Reading
follows those lines (TTS.ivonaEnds), a sentence sent ahead so the voice
doesn't stop between them; the estimate is only a backstop. It speaks
through Bluetooth (audiomgrd's audioOutputConnected): no voice set-up, no
discovery (TTS.IVONA). (The daemon itself logs each sentence's text there.)

Reflowable books only (EPUB, FB2, MOBI, AZW3, TXT, HTML); not PDF or comics.
]]

local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local OUT_PREFIX = "/tmp/gzreader-tts."

local TTS = {
    -- Where to send speech requests, tried in this order by the discovery.
    TARGETS = {
        { pub = "com.lab126.ttsd", prop = "playSnippetNow" },
        { pub = "com.lab126.ttsd", prop = "enqueueSnippet" },
        -- Kindle 2 / DX (firmware 2.x): the Kindle's speech pipe (fifo), the
        -- sentence written into it; then a text file ttsd reads (file = its folder)
        { pub = "com.lab126.tts", prop = "playFile", file = "/var/tmp", fifo = "/var/tmp/ttsUSFifo" },
        { pub = "com.lab126.tts", prop = "playFile", file = "/tmp", fifo = "/tmp/ttsUSFifo" },
        { pub = "com.lab126.tts", prop = "playFile", file = "/tmp" },
        { pub = "com.lab126.tts", prop = "playFile", file = "/var/tmp" },
    },
    -- First guesses for fields ttsd asks for (by name); anything else is
    -- tried as a number, then as a string.
    GUESSES = {
        id = { int = 1 }, priority = { int = 0 }, speed = { int = 100 },
        voice = { str = "Tom" }, lang = { str = "en-US" }, language = { str = "en-US" },
        locale = { str = "en_US" }, model = { str = "full_155mrf22" },
    },
    MAX_ROUNDS = 10,
    TEST_TEXT = "This is the Kindle voice test. ",
    BASE_WPM = 165,   -- words per minute at speed 100 (generous, so sentences aren't cut off)
    -- injectable for tests
    lipc = nil,       -- KOReader's libopenlipclua (doesn't load on the Kindle 3)
    exec = nil,       -- function(cmd) running a shell command (default os.execute)
    syslog = "/var/log/messages",
    now = nil,        -- function() -> "yymmdd:HHMMSS" (syslog timestamp format)
    seq = 0,
    testing = false,
}

local function settings() return G_reader_settings end

local function openLipc()
    local lipc = TTS.lipc
    if not lipc then
        local ok, mod = pcall(require, "libopenlipclua")
        if not ok then return nil, "libopenlipclua: " .. tostring(mod) end
        lipc = mod
    end
    local ok, handle = pcall(lipc.open_no_name)
    if not ok or not handle then return nil, "lipc open failed: " .. tostring(handle) end
    return handle
end

local function run(cmd)
    if TTS.exec then return TTS.exec(cmd) end
    return os.execute(cmd)
end

---------------------------------------------------------------- Ivona (Bluetooth Kindles)

TTS.IVONA = { pub = "com.lab126.ivonatts", prop = "playSnippet", ivona = true }
TTS.IVONA_JOB = "eink_ttsd"
TTS.IVONA_WAIT = 10 -- seconds for the voice to start

--- This Kindle has Amazon's Ivona voice (gzreader_touch: the daemon's file).
function TTS.hasIvona()
    if TTS.ivona_present ~= nil then return TTS.ivona_present end -- (tests)
    local ok, Touch = pcall(require, "gzreader_touch")
    return ok and Touch.ivona and Touch.ivona() or false
end

function TTS.isIvona(template)
    return type(template) == "table" and type(template.target) == "table" and template.target.ivona == true
end

--- Shell-quote for lipc-set-prop (single quotes).
local function shq(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

--- A string property of the Ivona voice; `wait`: before returning (else in
--- the background, the UI never waits).
local function ivonaSet(prop, value, wait)
    local h = openLipc()
    if h then
        local ok, err = pcall(h.set_string_property, h, TTS.IVONA.pub, prop, tostring(value))
        pcall(h.close, h)
        if ok then return true end
        return nil, tostring(err)
    end
    run(string.format("lipc-set-prop %s %s %s >/dev/null 2>&1%s", TTS.IVONA.pub, prop, shq(value), wait and "" or " &"))
    return true
end

local function intGet(pub, prop)
    local h = openLipc()
    if not h then return nil end
    local ok, v = pcall(h.get_int_property, h, pub, prop)
    pcall(h.close, h)
    return ok and tonumber(v) or nil
end

--- Is the Ivona voice up (com.lab126.ivonatts answers ivonaStarted = 1)?
function TTS.ivonaUp() return intGet(TTS.IVONA.pub, "ivonaStarted") == 1 end

--- A Bluetooth audio device is connected (audiomgrd: where sound goes).
--- nil when it can't be asked.
function TTS.bluetoothAudio()
    local v = intGet("com.lab126.audiomgrd", "audioOutputConnected")
    if v == nil then return nil end
    return v == 1
end

--- Start the Ivona voice if it isn't running, then on_ready(true) once it
--- answers, or on_ready(false) after IVONA_WAIT seconds. upstart's `start`
--- waits until the job is up, so it runs in the background.
function TTS.ensureIvona(on_ready)
    if TTS.ivonaUp() then return on_ready(true) end
    Log.info("tts: starting Amazon's voice (" .. TTS.IVONA_JOB .. ")")
    run("start " .. TTS.IVONA_JOB .. " >/dev/null 2>&1 &")
    local tries = 0
    local function check()
        tries = tries + 1
        if TTS.ivonaUp() then return on_ready(true) end
        if tries >= TTS.IVONA_WAIT * 2 then
            Log.warn("tts: Amazon's voice didn't start")
            return on_ready(false)
        end
        UIManager:scheduleIn(0.5, check)
    end
    UIManager:scheduleIn(0.5, check)
end

-- Following the voice in the system log: where we've read up to.
TTS.IVONA_BUF = 2400        -- bytes of every audio buffer but a sentence's last
TTS.IVONA_LOG_MAX = 1048576 -- bytes read per look at most (more: skipped)
TTS.ivona_log_offset = nil

--- Start following the system log from its end. False if it can't be read.
function TTS.ivonaLogStart()
    local f = io.open(TTS.syslog, "rb")
    if not f then TTS.ivona_log_offset = nil; return false end
    TTS.ivona_log_offset = f:seek("end")
    f:close()
    return TTS.ivona_log_offset ~= nil
end

--- Sentences the voice finished since the last look: its audio buffers'
--- lines whose size isn't IVONA_BUF (each sentence's last). Only whole lines;
--- a log that got shorter (rotated) is followed from its new end.
function TTS.ivonaEnds()
    local off = TTS.ivona_log_offset
    if not off then return 0 end
    local f = io.open(TTS.syslog, "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    if size < off then off = size end
    if size - off > TTS.IVONA_LOG_MAX then
        TTS.ivona_log_offset = size; f:close(); return 0
    end
    f:seek("set", off)
    local chunk = f:read(size - off) or ""
    f:close()
    local last_nl = chunk:match(".*()\n")
    if not last_nl then TTS.ivona_log_offset = off; return 0 end
    chunk = chunk:sub(1, last_nl)
    TTS.ivona_log_offset = off + #chunk
    local n = 0
    for line in chunk:gmatch("[^\n]+") do
        if line:find("einkttsd[", 1, true) then
            local bytes = tonumber(line:match("ReleaseBufPlay numBytes=(%d+)"))
            if bytes and bytes ~= TTS.IVONA_BUF then n = n + 1 end
        end
    end
    return n
end

--- speechRate for GZreader's speed (100 = normal): "1", "1.5", "0.8".
function TTS.ivonaRate(speed)
    local r = math.floor((speed or 100) / 10 + 0.5) / 10
    if r == math.floor(r) then return tostring(math.floor(r)) end
    return tostring(r)
end

function TTS.backend()
    local h = openLipc()
    if h then pcall(h.close, h); return "lib" end
    return "shell"
end

--- Make text safe inside lipc-hash-prop's quotes.
local function clean(value)
    return (tostring(value):gsub("[\r\n\t]+", " "):gsub('"', "'"):gsub("\\", "/"))
end

--- fields: ordered list of { name, int = n } / { name, str = "s" }.
--- Returns the lipc-hash-prop input, e.g. {text = "Hi", id = (1)}.
function TTS.hashText(fields)
    local parts = {}
    for _i, f in ipairs(fields) do
        if f.int ~= nil then
            parts[#parts + 1] = string.format("%s = (%d)", f[1], f.int)
        else
            parts[#parts + 1] = string.format('%s = "%s"', f[1], clean(f.str))
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

--- Run a lipc-hash-prop in the background (the UI never waits on it).
--- Returns the path of its output file: "rc=<n>" is appended when it ends.
local function hashPropAsync(pub, prop, hash)
    TTS.seq = TTS.seq + 1
    -- one input file per call: an earlier call may not have read its own yet
    local hash_file = OUT_PREFIX .. TTS.seq .. ".hash"
    local out = OUT_PREFIX .. TTS.seq .. ".out"
    local f = io.open(hash_file, "wb")
    if not f then return nil, "cannot write " .. hash_file end
    f:write(hash, "\n"); f:close()
    os.remove(out)
    -- pub/prop are constants from TARGETS; the text only goes in the file.
    run(string.format("(lipc-hash-prop %s %s < %s > %s 2>&1; echo \"rc=$?\" >> %s; rm -f %s) &",
        pub, prop, hash_file, out, out, hash_file))
    return out
end

--- Result of a background call: true (ok), false, details (failed), nil (still running).
function TTS.result(out)
    if out == true then return true, "" end
    local f = out and io.open(out, "rb")
    if not f then return nil end
    local text = f:read("*a") or ""
    f:close()
    local rc = tonumber(text:match("rc=(%d+)"))
    if not rc then return nil end
    os.remove(out)
    local body = text:gsub("rc=%d+%s*$", "")
    if rc ~= 0 or body:lower():find("fail") or body:lower():find("error") or body:lower():find("usage") then
        return false, (body ~= "" and body or ("exit code " .. rc))
    end
    return true, body
end

--- The text of a request (its "text" field).
local function textOf(fields)
    for _i, f in ipairs(fields) do if f[1] == "text" then return tostring(f.str or "") end end
    return ""
end

--- Firmware 2.x's voice reads plain text: typographic punctuation as ASCII.
function TTS.plainText(text)
    return (tostring(text):gsub("\u{2018}", "'"):gsub("\u{2019}", "'"):gsub("\u{201C}", '"'):gsub("\u{201D}", '"')
        :gsub("\u{2014}", ", "):gsub("\u{2013}", ", "):gsub("\u{2026}", "..."):gsub("\u{00A0}", " "):gsub("[\r\n\t]+", " "))
end

--- The text file a playFile request hands ttsd (a few kept: ttsd may still
--- be reading the previous one).
TTS.FIFO_WRITER_PID = OUT_PREFIX .. "writer.pid"
TTS.FIFO_WRITER_TIMEOUT = 30 -- seconds a sentence waits for ttsd to read the pipe

--- playFile through the Kindle's speech pipe: make the pipe if it isn't
--- there, write the sentence into it in the background (the write waits
--- until ttsd opens the pipe; given up after FIFO_WRITER_TIMEOUT), and hand
--- ttsd the pipe's path. A writer still waiting from the previous sentence
--- is stopped first.
local function fifoRequest(target, text)
    local txt = string.format("%sfifo.%d.txt", OUT_PREFIX, TTS.seq)
    local f = io.open(txt, "wb")
    if not f then return nil, "cannot write " .. txt end
    f:write(text, "\n")
    f:close()
    os.remove(string.format("%sfifo.%d.txt", OUT_PREFIX, TTS.seq - 4))
    TTS.last_file = target.fifo
    local out = OUT_PREFIX .. TTS.seq .. ".out"
    os.remove(out)
    -- (pub/prop/fifo are constants from TARGETS; the text only goes in the file)
    local pidf, fifo = TTS.FIFO_WRITER_PID, target.fifo
    run(string.format("(kill $(cat %s 2>/dev/null) >/dev/null 2>&1; "
        .. "[ -p %s ] || { rm -f %s; mkfifo %s 2>/dev/null || mknod %s p; }; "
        .. "(cat %s > %s) >/dev/null 2>&1 & w=$!; echo $w > %s; "
        .. "lipc-set-prop -s %s %s %s > %s 2>&1; echo \"rc=$?\" >> %s; "
        .. "sleep %d; kill $w >/dev/null 2>&1) >/dev/null 2>&1 &",
        pidf, fifo, fifo, fifo, fifo, txt, fifo, pidf,
        target.pub, target.prop, fifo, out, out, TTS.FIFO_WRITER_TIMEOUT))
    return out
end

local function playFileRequest(target, fields)
    TTS.seq = TTS.seq + 1
    if target.fifo then return fifoRequest(target, TTS.plainText(textOf(fields))) end
    local path = string.format("%s/gzreader-tts.%d.txt", target.file, TTS.seq)
    local f = io.open(path, "wb")
    if not f then return nil, "cannot write " .. path end
    f:write(TTS.plainText(textOf(fields)), "\n")
    f:close()
    TTS.last_file = path
    os.remove(string.format("%s/gzreader-tts.%d.txt", target.file, TTS.seq - 4))
    local h = openLipc()
    if h then
        local ok, err = pcall(h.set_string_property, h, target.pub, target.prop, path)
        pcall(h.close, h)
        if not ok then return nil, tostring(err) end
        return true
    end
    local out = OUT_PREFIX .. TTS.seq .. ".out"
    os.remove(out)
    -- (pub/prop are constants from TARGETS; the path is ours)
    run(string.format("(lipc-set-prop -s %s %s %s > %s 2>&1; echo \"rc=$?\" >> %s) &", target.pub, target.prop, path, out, out))
    return out
end

--- Is this voice one ttsd queues (enqueueSnippet, with events), or one
--- sentence at a time (firmware 2.x's playFile)?
function TTS.oneAtATime(template)
    template = template or TTS.template()
    return type(template) == "table" and type(template.target) == "table" and template.target.file ~= nil
end

--- Send one request. Returns a result handle for TTS.result, or nil, err.
function TTS.send(target, fields)
    if target.file then return playFileRequest(target, fields) end
    if target.ivona then return ivonaSet(target.prop, TTS.plainText(textOf(fields))) end
    local h = openLipc()
    if not h then
        return hashPropAsync(target.pub, target.prop, TTS.hashText(fields))
    end
    local ok, res = pcall(function()
        local ha = h:new_hasharray()
        ha:add_hash()
        for _i, f in ipairs(fields) do
            if f.int ~= nil then ha:put_int(0, f[1], f.int) else ha:put_string(0, f[1], tostring(f.str)) end
        end
        local out = h:access_hash_property(target.pub, target.prop, ha)
        if out then out:destroy() end
        ha:destroy()
    end)
    pcall(h.close, h)
    if not ok then return nil, tostring(res) end
    return true
end

--- The saved request shape, filled in for `text`.
local function fieldsFor(template, text, id)
    local fields = {}
    for _i, f in ipairs(template.fields) do
        if f[1] == "text" then
            -- ttsd holds back the last word until more text arrives; a
            -- trailing space lets it see that the word is complete
            fields[#fields + 1] = { "text", str = text .. " " }
        elseif f[1] == "id" and f.int ~= nil then
            fields[#fields + 1] = { "id", int = id or (TTS.seq + 1) } -- a fresh id per snippet
        else
            fields[#fields + 1] = { f[1], int = f.int, str = f.str }
        end
    end
    return fields
end

--- How to reach this Kindle's voice: Amazon's Ivona voice where there is
--- one (nothing to find), else what "Find the Kindle voice" saved.
function TTS.template()
    if TTS.hasIvona() then return { target = TTS.IVONA, fields = { { "text", str = "" } } } end
    return settings():readSetting("gzreader_tts_template")
end

TTS.next_id = 100

--- Speak `text` with the saved request shape. opts.enqueue: queue it after
--- what is playing (ttsd's enqueueSnippet) instead of replacing it.
--- Returns a result handle (see TTS.result) and the snippet id, or nil, err.
--- Never waits for the speech.
function TTS.say(text, template, opts)
    template = template or TTS.template()
    if not template then return nil, "no voice set up" end
    opts = opts or {}
    TTS.next_id = TTS.next_id + 1
    local id = TTS.next_id
    local target = template.target
    if opts.enqueue and target.pub == "com.lab126.ttsd" and not target.file then
        target = { pub = target.pub, prop = "enqueueSnippet" }
    end
    local handle, err = TTS.send(target, fieldsFor(template, text, id))
    if not handle then return nil, err end
    return handle, id
end

---------------------------------------------------------------- ttsd events

-- ttsd announces snippetStarted / snippetFinished (with the snippet id) over
-- lipc; lipc-wait-event writes them to a file we read. That paces reading by
-- the real speech instead of an estimate (estimates are the fallback).
TTS.EVENTS_FILE = OUT_PREFIX .. "events"
local events_offset = 0

function TTS.startEvents()
    TTS.stopEvents()
    os.remove(TTS.EVENTS_FILE)
    events_offset = 0
    run(string.format("(lipc-wait-event -m com.lab126.ttsd snippetStarted,snippetFinished > %s 2>&1 & echo $! > %s.pid) >/dev/null 2>&1",
        TTS.EVENTS_FILE, TTS.EVENTS_FILE))
end

function TTS.stopEvents()
    local f = io.open(TTS.EVENTS_FILE .. ".pid", "rb")
    local pid = f and tonumber(f:read("*a"))
    if f then f:close() end
    if pid then run("kill " .. pid .. " >/dev/null 2>&1") end
    os.remove(TTS.EVENTS_FILE .. ".pid")
end

--- New events since the last call: list of { name = "started"|"finished", id = n }.
function TTS.readEvents()
    local f = io.open(TTS.EVENTS_FILE, "rb")
    if not f then return {} end
    f:seek("set", events_offset)
    local chunk = f:read("*a") or ""
    f:close()
    -- only whole lines
    local last_nl = chunk:match(".*()\n")
    if not last_nl then return {} end
    chunk = chunk:sub(1, last_nl)
    events_offset = events_offset + #chunk
    local out = {}
    for line in chunk:gmatch("[^\n]+") do
        local kind = line:match("snippet(%a+)")
        local id = tonumber(line:match("(%d+)%s*$"))
        if kind and id then
            out[#out + 1] = { name = kind:lower(), id = id }
        end
    end
    return out
end

local function intProp(pub, prop, value)
    local h = openLipc()
    if not h then
        run(string.format("lipc-set-prop -i %s %s %d >/dev/null 2>&1 &", pub, prop, value))
        return
    end
    pcall(h.set_int_property, h, pub, prop, value)
    pcall(h.close, h)
end

--- Stop a sentence still waiting to be written into the speech pipe.
local function stopFifoWriter()
    local f = io.open(TTS.FIFO_WRITER_PID, "rb")
    local pid = f and tonumber(f:read("*a"))
    if f then f:close() end
    if pid then run("kill " .. pid .. " >/dev/null 2>&1") end
    os.remove(TTS.FIFO_WRITER_PID)
end

--- Stop what the Kindle's voice is saying. Only the properties this Kindle's
--- voice has: a Kindle 2/DX (playFile, one sentence at a time) has no
--- com.lab126.ttsd, and setting its cancelSnippetPlayback failed there, a
--- line in the system log each time a book closed. No voice set up: nothing
--- can be speaking, nothing sent.
function TTS.cancel(template)
    template = template or TTS.template()
    if TTS.isIvona(template) then ivonaSet("stopReading", ""); return end
    if template then
        if not TTS.oneAtATime(template) then intProp("com.lab126.ttsd", "cancelSnippetPlayback", 1) end
        intProp("com.lab126.tts", "stop", 1)
    end
    stopFifoWriter()
end

--- Like TTS.cancel, but waits until ttsd has it (so a request sent right
--- after can't be cancelled by it).
function TTS.cancelNow()
    if TTS.isIvona(TTS.template()) then ivonaSet("stopReading", "", true); return end
    local pub, prop = "com.lab126.ttsd", "cancelSnippetPlayback"
    if TTS.oneAtATime() then pub, prop = "com.lab126.tts", "stop" end
    local h = openLipc()
    if h then
        pcall(h.set_int_property, h, pub, prop, 1)
        pcall(h.close, h)
        return
    end
    run(string.format("lipc-set-prop -i %s %s 1 >/dev/null 2>&1", pub, prop))
end

--- Remove leftover result files of background calls (and playFile's texts).
function TTS.cleanup()
    local dirs = {}
    for _i, t in ipairs(TTS.TARGETS) do if t.file then dirs[#dirs + 1] = t.file .. "/gzreader-tts.*.txt" end end
    stopFifoWriter()
    run("rm -f " .. OUT_PREFIX .. "*.out " .. OUT_PREFIX .. "*.hash " .. OUT_PREFIX .. "fifo.*.txt " .. table.concat(dirs, " ") .. " >/dev/null 2>&1")
end

function TTS.speed() return settings():readSetting("gzreader_tts_speed") or 100 end

--- Speaker volume, 0-15 (com.lab126.audio CmdIVolume; the Kindle's own range).
TTS.VOLUME_MAX = 15
function TTS.volume() return settings():readSetting("gzreader_tts_volume") or 10 end

function TTS.setVolume(v)
    v = math.max(0, math.min(TTS.VOLUME_MAX, v))
    settings():saveSetting("gzreader_tts_volume", v)
    if TTS.hasIvona() then return end -- (the volume is the Bluetooth device's)
    intProp("com.lab126.audio", "CmdIVolume", v)
end

function TTS.applySettings()
    if TTS.hasIvona() then ivonaSet("speechRate", TTS.ivonaRate(TTS.speed())); return end
    intProp("com.lab126.tts", "TtsISpeed", TTS.speed())
    if settings():readSetting("gzreader_tts_volume") then
        intProp("com.lab126.audio", "CmdIVolume", TTS.volume())
    end
end

function TTS.setSpeed(v)
    settings():saveSetting("gzreader_tts_speed", v)
    if TTS.hasIvona() then ivonaSet("speechRate", TTS.ivonaRate(v)); return end
    intProp("com.lab126.tts", "TtsISpeed", v)
end

--- Seconds the Kindle needs to say `text` at the current speed.
function TTS.duration(text)
    local words = 0
    for _w in tostring(text):gmatch("%S+") do words = words + 1 end
    local pauses = select(2, tostring(text):gsub("[,;:%.!%?]", ""))
    local wpm = TTS.BASE_WPM * TTS.speed() / 100
    return 0.4 + words * 60 / wpm + pauses * 0.2
end

---------------------------------------------------------------- discovery

local function stamp()
    if TTS.now then return TTS.now() end
    -- the Kindle writes its system log in its own (UTC) clock, whatever time
    -- zone GZreader shows
    return os.date("!%y%m%d:%H%M%S", os.time() - 2) -- a little slack
end

--- The newest ttsd complaint in the system log written at or after `since`.
function TTS.ttsdComplaint(since)
    local f = io.open(TTS.syslog, "rb")
    if not f then return nil end
    local size = f:seek("end") or 0
    f:seek("set", math.max(0, size - 16384))
    local tail = f:read("*a") or ""
    f:close()
    local found
    for line in tail:gmatch("[^\n]+") do
        local ts = line:match("^(%d%d%d%d%d%d:%d%d%d%d%d%d)")
        if ts and ts >= since and line:find("ttsd%[") and line:find("lipc_handling") then found = line end
    end
    return found
end

--- What ttsd wants, from a complaint line: "unable to read id" -> "id".
function TTS.missingField(line)
    if not line then return nil end
    return line:match("unable to read ([%w_]+)") or line:match("bad_([%w_]+):")
end

--- Learn the request shape ttsd accepts. on_done(template_or_nil, why).
function TTS.discover(on_done)
    local ti, rounds = 1, 0
    local fields = { { "text", str = TTS.TEST_TEXT } }
    local tried = {}
    local last_err
    local function attempt()
        rounds = rounds + 1
        local target = TTS.TARGETS[ti]
        if not target or rounds > TTS.MAX_ROUNDS * #TTS.TARGETS then
            return on_done(nil, last_err or "no answer from ttsd")
        end
        local since = stamp()
        local handle, err = TTS.send(target, fields)
        local function wait(n)
            local ok, detail = TTS.result(handle)
            if handle and ok == nil and n < 8 then return UIManager:scheduleIn(0.5, function() wait(n + 1) end) end
            if not handle then ok, detail = false, err end
            local desc = target.prop .. (target.fifo and (" (the speech pipe " .. target.fifo .. ")")
                or target.file and (" (a text file in " .. target.file .. ")") or (" " .. TTS.hashText(fields)))
            local complaint = TTS.ttsdComplaint(since)
            if ok and target.file and complaint and TTS.last_file and complaint:find(TTS.last_file, 1, true) then
                ok, detail = false, complaint -- (ttsd couldn't use the file)
            end
            if ok then
                Log.info("tts discover: accepted", desc)
                return on_done({ target = target, fields = fields })
            end
            -- (every different answer, for the message: the first ones say most)
            local this_err = tostring(complaint or detail or "?")
            if not last_err then last_err = this_err
            elseif not last_err:find(this_err, 1, true) then last_err = last_err .. "\n" .. this_err end
            Log.info("tts discover: rejected", desc, "|", tostring(detail), "|", tostring(complaint))
            local name = not target.file and TTS.missingField(complaint) or nil
            local next_fields
            if name then
                local key = name
                local existing
                for _i, f in ipairs(fields) do if f[1] == name then existing = f end end
                local guess = TTS.GUESSES[name] or {}
                if not existing and not tried[key .. ":int"] and not (guess.str and not guess.int) then
                    tried[key .. ":int"] = true
                    next_fields = {}
                    for _i, f in ipairs(fields) do next_fields[#next_fields + 1] = f end
                    next_fields[#next_fields + 1] = { name, int = guess.int or 1 }
                elseif not tried[key .. ":str"] then
                    -- added as a number already (or a string is the better guess)
                    tried[key .. ":str"] = true
                    next_fields = {}
                    for _i, f in ipairs(fields) do if f[1] ~= name then next_fields[#next_fields + 1] = f end end
                    next_fields[#next_fields + 1] = { name, str = guess.str or "1" }
                end
            end
            if next_fields then
                fields = next_fields
            else
                -- nothing new to try here: next target, starting over
                ti = ti + 1
                fields = { { "text", str = TTS.TEST_TEXT } }
                tried = {}
            end
            UIManager:scheduleIn(0.5, attempt)
        end
        -- (a text file: ttsd reads it a moment later, and complains then if it can't)
        UIManager:scheduleIn(target.file and 2.5 or 1, function() wait(0) end)
    end
    attempt()
end

--- Menu action: find the request shape, then check it was heard.
function TTS.findVoice(on_done)
    if TTS.testing then return end
    if TTS.hasIvona() then return TTS.testIvona(on_done) end
    TTS.testing = true
    Log.info("tts backend", TTS.backend())
    local busy = InfoMessage:new{ text = _("Finding the Kindle's voice… Listen for \"This is the Kindle voice test\"."), timeout = 0 }
    UIManager:show(busy)
    TTS.discover(function(template, why)
        UIManager:close(busy)
        TTS.testing = false
        if not template then
            Log.warn("tts: discovery failed:", tostring(why))
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle's speech service didn't accept any request:\n%1\n\nSave the diagnostic log (Settings → General) and send it so this can be fixed."),
                tostring(why):sub(1, 300)) })
            return
        end
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("The Kindle's speech service accepted the request. Did you hear \"This is the Kindle voice test\"?"),
            ok_text = _("Yes"),
            cancel_text = _("No"),
            ok_callback = function()
                settings():saveSetting("gzreader_tts_template", template)
                Log.info("tts template saved", template.target.prop, TTS.hashText(template.fields))
                UIManager:show(InfoMessage:new{ text = require("gzreader_touch").text(_("Kindle voice set. Press Shift + Sym while reading to start or stop."),
                    _("Kindle voice set. In a book, Read aloud in the quick panel (swipe down from the top) starts and stops it.")), timeout = 4 })
                if on_done then on_done(template) end
            end,
            cancel_callback = function()
                Log.warn("tts: accepted but not heard", template.target.prop, TTS.hashText(template.fields))
                UIManager:show(InfoMessage:new{ text = _("Check the volume (the Kindle's speaker or headphones), then try again. If it stays silent, save the diagnostic log (Settings → General) and send it.") })
            end,
        })
        -- say it once more while the question is up
        TTS.say(TTS.TEST_TEXT, template)
    end)
end

--- Why the Ivona voice can't be heard now (no Bluetooth audio device), or nil.
function TTS.ivonaBlocked()
    if TTS.bluetoothAudio() == false then
        return _("Connect Bluetooth headphones or a speaker first (Settings → General → Bluetooth): this Kindle reads aloud through Bluetooth.")
    end
end

--- Kindles with Amazon's Ivona voice: start it if needed and say the test
--- sentence, asking whether it was heard.
function TTS.testIvona(on_done)
    local blocked = TTS.ivonaBlocked()
    if blocked then UIManager:show(InfoMessage:new{ text = blocked }); return end
    TTS.testing = true
    local busy = InfoMessage:new{ text = _("Starting the Kindle's voice… Listen for \"This is the Kindle voice test\"."), timeout = 0 }
    UIManager:show(busy)
    TTS.ensureIvona(function(up)
        UIManager:close(busy)
        TTS.testing = false
        if not up then
            UIManager:show(InfoMessage:new{ text = _("The Kindle's voice didn't start. Try again in a moment; if it stays silent, save the diagnostic log (Settings → General) and send it.") })
            return
        end
        TTS.applySettings()
        TTS.say(TTS.TEST_TEXT)
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("Did you hear \"This is the Kindle voice test\"?"),
            ok_text = _("Yes"),
            cancel_text = _("No"),
            ok_callback = function()
                Log.info("tts: Amazon's voice heard")
                if on_done then on_done(TTS.template()) end
            end,
            cancel_callback = function()
                Log.warn("tts: Amazon's voice not heard")
                UIManager:show(InfoMessage:new{ text = _("Check that the Bluetooth device is connected and its volume is up, then try again. If it stays silent, save the diagnostic log (Settings → General) and send it.") })
            end,
        })
    end)
end

---------------------------------------------------------------- reader

local Reader = {}
Reader.__index = Reader
TTS.Reader = Reader

function Reader:new(ui)
    return setmetatable({ ui = ui, active = false, paused = false }, self)
end

function Reader:supported()
    local doc = self.ui and self.ui.document
    return doc and not doc.info.has_pages and doc.extendXPointersToSentenceSegment ~= nil
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A sentence is spoken as one piece. Very long ones are split at a comma,
-- semicolon, colon or dash once they reach CLAUSE_WORDS (never mid-clause
-- before MAX_WORDS); paragraph ends always end a piece.
Reader.CLAUSE_WORDS = 30
Reader.MAX_WORDS = 80

local SENTENCE_END = "[%.!%?…]['\"”’%)%]]*$"
local CLAUSE_END = "[,;:—–]['\"”’%)%]]*$"

--- What the voice says for a piece of text: web addresses are left out.
function TTS.speakable(text)
    text = tostring(text or "")
    text = text:gsub("[Hh][Tt][Tt][Pp][Ss]?://%S+", " ")
    text = text:gsub("[Ww][Ww][Ww]%.%S+%.%S+", " ")
    text = text:gsub("%s+", " ")
    return trim(text)
end

local function pageOf(doc, xp)
    if not xp or type(doc.getPageFromXPointer) ~= "function" then return nil end
    local ok, p = pcall(doc.getPageFromXPointer, doc, xp)
    return ok and p or nil
end

--- Sentence starting at (or after) xp: returns text, xp0, xp1, extra or nil
--- at the end. extra.turn_xp / extra.turn_frac: where the sentence crosses
--- onto the next page and how far into it (by characters), so the page can
--- turn while it's being said.
function Reader:sentenceAt(xp)
    local doc = self.ui.document
    if not xp then return nil end
    local first_end = doc:getNextVisibleWordEnd(xp)
    if not first_end then return nil end
    local start = xp
    local last_end = first_end
    local cur_end = first_end
    local start_page = pageOf(doc, start)
    local turn_xp
    for n = 1, Reader.MAX_WORDS do
        last_end = cur_end
        local word = trim(doc:getTextFromXPointers(doc:getPrevVisibleWordStart(cur_end) or start, cur_end, false))
        if word:find(SENTENCE_END) then break end
        if n >= Reader.CLAUSE_WORDS and word:find(CLAUSE_END) then break end
        local next_start = doc:getNextVisibleWordStart(cur_end)
        if not next_start then break end
        -- a paragraph (or heading, list item) ends here
        local gap = doc:getTextFromXPointers(cur_end, next_start, false) or ""
        if gap:find("\n") then break end
        local next_end = doc:getNextVisibleWordEnd(next_start)
        if not next_end or next_end == cur_end then break end
        if not turn_xp and start_page then
            local p = pageOf(doc, next_start)
            if p and p > start_page then turn_xp = next_start end
        end
        cur_end = next_end
    end
    local text = trim(doc:getTextFromXPointers(start, last_end, false))
    if text == "" then
        local nxt = doc:getNextVisibleWordStart(last_end)
        if not nxt or nxt == xp then return nil end
        return self:sentenceAt(nxt)
    end
    local extra
    if turn_xp then
        local before = #trim(doc:getTextFromXPointers(start, turn_xp, false))
        extra = { turn_xp = turn_xp, turn_frac = math.max(0, math.min(1, before / math.max(1, #text))) }
    end
    return text, start, last_end, extra
end

function Reader:highlight(xp0, xp1)
    local doc = self.ui.document
    pcall(doc.getTextFromXPointers, doc, xp0, xp1, true) -- crengine draws the selection
    UIManager:setDirty(self.ui.dialog, "ui")
end

function Reader:clearHighlight()
    pcall(self.ui.document.clearSelection, self.ui.document)
    UIManager:setDirty(self.ui.dialog, "ui")
end

--- Make sure xp is on screen, turning pages forward as needed.
function Reader:follow(xp)
    local doc = self.ui.document
    for _i = 1, 4 do
        if doc:isXPointerInCurrentPage(xp) then return true end
        self.turning = true
        self.ui:handleEvent(Event:new("GotoViewRel", 1))
        self.turning = false
    end
    if not doc:isXPointerInCurrentPage(xp) then
        self.turning = true
        self.ui:handleEvent(Event:new("GotoXPointer", xp, xp))
        self.turning = false
    end
    return true
end

Reader.AHEAD = 2       -- sentences handed to ttsd ahead of what is being spoken
Reader.POLL = 0.4
Reader.EVENTS_GRACE = 4 -- seconds to wait for a first ttsd event before using estimates

function Reader:start()
    if self.active then return end
    if not self:supported() then
        UIManager:show(InfoMessage:new{ text = _("Read aloud works with EPUB, FB2, MOBI, AZW3 and text books, not PDFs or comics.") })
        return
    end
    if not TTS.template() then
        return TTS.findVoice(function() self:start() end)
    end
    self.ivona = TTS.isIvona(TTS.template())
    if self.ivona and not self.ivona_ready then
        -- Amazon's voice (Bluetooth Kindles): a Bluetooth device, and the voice started
        local blocked = TTS.ivonaBlocked()
        if blocked then UIManager:show(InfoMessage:new{ text = blocked }); return end
        if self.starting then return end
        self.starting = true
        return TTS.ensureIvona(function(up)
            self.starting = false
            if not up then
                UIManager:show(InfoMessage:new{ text = _("The Kindle's voice didn't start. Try again in a moment.") })
                return
            end
            self.ivona_ready = true
            self:start()
            self.ivona_ready = nil
        end)
    end
    -- the Kindle voice needs the sound device: no audiobook player holding it
    pcall(function() require("gzreader_abfolder").releaseAudio("read aloud", true) end)
    self.active, self.paused = true, false
    TTS.applySettings()
    self.one = TTS.oneAtATime()
    if not self.one and not self.ivona then TTS.startEvents() end
    self.events_ok = nil
    -- (firmware 2.x and Amazon's Ivona voice: no events, paced by estimates;
    -- the Ivona voice by its sentence ends in the system log where it can be read)
    if self.one or self.ivona then self.events_ok = false end
    self.ivona_log = self.ivona and TTS.ivonaLogStart() or false
    self.ivona_marks, self.ivona_backstops = 0, 0
    if self.ivona then Log.info("tts: Amazon's voice,", self.ivona_log and "following its sentence ends in the system log" or "paced by estimates (system log unreadable)") end
    self.started_at = os.time()
    self.next_xp = self.ui.document:getXPointer()
    Log.info("tts start")
    UIManager:show(Notification:new{ text = require("gzreader_touch").text(_("Reading aloud. Shift + Sym to stop."),
        _("Reading aloud. Quick panel → Read aloud to stop.")) })
    self:restartQueue()
    self.poller = function() self.poller_scheduled = false; self:poll() end
    self:schedulePoll()
    -- headphones unplugged: stop rather than read out loud (Bluetooth: no jack)
    if not self.ivona then pcall(function() require("gzreader_jack").watch("tts", function()
        self:stop()
        UIManager:show(InfoMessage:new{ text = _("Headphones unplugged: read aloud stopped."), timeout = 3 })
    end) end) end
end

Reader.IVONA_POLL = 0.25 -- (the system log: the highlight within a quarter second of the voice)

function Reader:schedulePoll()
    if self.active and not self.poller_scheduled then
        self.poller_scheduled = true
        UIManager:scheduleIn(self.ivona_log and Reader.IVONA_POLL or Reader.POLL, self.poller)
    end
end

--- Throw away what is queued and start from self.next_xp.
function Reader:restartQueue()
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    self.queue = {}
    self.outbox = {}
    self.no_more = false
    self.generation = (self.generation or 0) + 1
    -- Everything goes through ttsd's queue (enqueueSnippet). playSnippetNow
    -- flushes that queue, and requests sent close together could reach ttsd
    -- out of order, which dropped whole sentences (seen on a Kindle 3).
    TTS.cancelNow()
    if self.ivona_log then
        -- the sentence cut off may still log a short buffer: start from here,
        -- and leave out what the next look finds
        TTS.ivonaLogStart()
        self.ivona_skip = true
    end
    self:fill()
    self:playHead()
end

--- Keep Reader.AHEAD sentences handed to ttsd.
function Reader:fill()
    while self.active and not self.no_more and #self.queue < Reader.AHEAD do
        local text, xp0, xp1, extra = self:sentenceAt(self.next_xp)
        if not text then self.no_more = true; break end
        self.next_xp = self.ui.document:getNextVisibleWordStart(xp1)
        local spoken = TTS.speakable(text)
        if spoken:find("%w") then -- a piece that was only a web link is skipped
            local item = { text = spoken, xp0 = xp0, xp1 = xp1,
                turn_xp = extra and extra.turn_xp, turn_frac = extra and extra.turn_frac }
            self.queue[#self.queue + 1] = item
            if not self.one then self.outbox[#self.outbox + 1] = item end -- (one at a time: sent when shown)
        end
        if not self.next_xp then self.no_more = true; break end
    end
    self:sendNext()
    if self.active and #self.queue == 0 and self.no_more then
        self:stop()
        UIManager:show(Notification:new{ text = _("End of book.") })
    end
end

--- Send queued sentences to ttsd one at a time, each only after ttsd has
--- answered the previous request, so they arrive in order.
function Reader:sendNext()
    if not self.active or self.sending or #self.outbox == 0 then return end
    local item = table.remove(self.outbox, 1)
    local handle, id = TTS.say(item.text, nil, { enqueue = true })
    if not handle then
        Log.warn("tts say failed:", id)
        self:stop()
        UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), id) })
        return
    end
    item.id = id
    if type(handle) ~= "string" then return self:sendNext() end -- answered already (lipc library)
    self.sending = handle
    local gen, tries = self.generation, 0
    local function check()
        if not self.active or gen ~= self.generation then self.sending = nil; return end
        tries = tries + 1
        local r, detail = TTS.result(handle)
        if r == nil and tries < 40 then return UIManager:scheduleIn(0.25, check) end
        self.sending = nil
        if r == false then
            Log.warn("tts rejected:", detail)
            self:stop()
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), detail) })
            return
        end
        self:sendNext()
    end
    UIManager:scheduleIn(0.25, check)
end

--- Show the sentence at the head of the queue (the one being spoken).
function Reader:playHead()
    local head = self.queue and self.queue[1]
    if not self.active or not head or head.shown then return end
    head.shown = true
    head.shown_at = os.time()
    if self.one then
        -- firmware 2.x: no queue in ttsd; this sentence now
        local since = (self.said or 0) < 3 and os.date("!%y%m%d:%H%M%S", os.time() - 2) or nil
        local handle, id = TTS.say(head.text)
        if not handle then
            Log.warn("tts say failed:", id)
            self:stop()
            UIManager:show(InfoMessage:new{ text = T(_("The Kindle voice didn't respond: %1"), id) })
            return
        end
        head.id = id
        self.said = (self.said or 0) + 1
        if since then
            -- (the first few: what ttsd thought of them, for the log)
            UIManager:scheduleIn(2, function()
                local c = TTS.ttsdComplaint(since)
                if c then Log.warn("tts: ttsd:", c) end
            end)
        end
    end
    self.cur = { head.xp0, head.xp1 }
    self:follow(head.xp0)
    self:highlight(head.xp0, head.xp1)
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    if head.turn_xp then
        -- the sentence goes on overleaf: turn when the voice gets there
        self.turn_timer = function()
            self.turn_timer = nil
            if self.active and self.queue[1] == head then
                self:follow(head.turn_xp)
                self:highlight(head.xp0, head.xp1)
            end
        end
        UIManager:scheduleIn(math.max(0.5, TTS.duration(head.text) * head.turn_frac), self.turn_timer)
    end
    if self.events_ok == false then self:armTimer(head) end
end

--- Estimate mode: move on when the head should be done.
function Reader:armTimer(head)
    if self.timer then UIManager:unschedule(self.timer) end
    self.timer = function()
        self.timer = nil
        if self.queue[1] == head then
            if self.ivona_log then self.ivona_backstops = (self.ivona_backstops or 0) + 1 end
            self:advance(head.id)
        end
    end
    local wait = TTS.duration(head.text)
    -- following the voice in the log: the estimate only in case a sentence's end isn't seen
    if self.ivona_log then wait = wait * 1.5 + 1.5 end
    UIManager:scheduleIn(wait, self.timer)
end

--- Snippet `id` is done: drop it (and anything before it), refill, show the next.
function Reader:advance(id)
    local idx
    for i, q in ipairs(self.queue) do if q.id == id then idx = i; break end end
    if not idx then return end
    for _i = 1, idx do table.remove(self.queue, 1) end
    self:fill()
    self:playHead()
end

function Reader:poll()
    if not self.active then return end
    if self.ivona_log then
        local ends = TTS.ivonaEnds()
        if self.ivona_skip then self.ivona_skip = false; ends = 0 end
        for _i = 1, ends do
            local head = self.queue[1]
            if not (self.active and head and head.shown) then break end
            self.ivona_marks = (self.ivona_marks or 0) + 1
            self:advance(head.id)
        end
        if not self.active then return end
    end
    for _i, ev in ipairs(TTS.readEvents()) do
        self.logged_events = (self.logged_events or 0) + 1
        if self.logged_events <= 12 then Log.info("tts event", ev.name, ev.id, "queue head", self.queue[1] and self.queue[1].id) end
        if self.events_ok ~= true then
            self.events_ok = true
            if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
        end
        if ev.name == "started" then
            -- ttsd moved on to this one: everything before it is done
            local idx
            for i, q in ipairs(self.queue) do if q.id == ev.id then idx = i; break end end
            if idx and idx > 1 then
                for _j = 1, idx - 1 do table.remove(self.queue, 1) end
                self:fill()
            end
            self:playHead()
        elseif ev.name == "finished" then
            -- If ttsd reports "finished" when it has *rendered* the snippet
            -- rather than said it, don't race ahead (and pile the book into
            -- its queue): move on no sooner than ~60% of the estimate.
            local head = self.queue[1]
            local early = head and head.id == ev.id and head.shown_at
                and (TTS.duration(head.text) * 0.6 - (os.time() - head.shown_at))
            if early and early > 0.5 then
                local id = ev.id
                UIManager:scheduleIn(early, function() if self.active then self:advance(id) end end)
            else
                self:advance(ev.id)
            end
        end
        if not self.active then return end
    end
    if self.events_ok == nil and os.time() - self.started_at >= Reader.EVENTS_GRACE then
        self.events_ok = false
        Log.info("tts: no ttsd events, pacing by estimate")
        local head = self.queue[1]
        if head then self:armTimer(head) end
    end
    self:schedulePoll()
end

function Reader:stop()
    pcall(function() require("gzreader_jack").unwatch("tts") end)
    if self.timer then UIManager:unschedule(self.timer); self.timer = nil end
    if self.turn_timer then UIManager:unschedule(self.turn_timer); self.turn_timer = nil end
    if self.poller then UIManager:unschedule(self.poller); self.poller_scheduled = false end
    if self.active then
        Log.info("tts stop", self.ivona_log and string.format("(sentence ends seen in the log: %d, by estimate: %d)",
            self.ivona_marks or 0, self.ivona_backstops or 0) or "")
    end
    local was_active = self.active
    self.active, self.paused = false, false
    self.queue = {}
    -- (only when it was reading: a book closing without read aloud used to
    -- start lipc-set-prop for nothing, where the lipc library doesn't load)
    if was_active then TTS.cancel(); TTS.stopEvents(); TTS.cleanup() end
    self.said = nil
    self:clearHighlight()
end

function Reader:toggle()
    if self.active then self:stop() else self:start() end
end

--- A page turned by the reader (not by us): continue from the new page.
function Reader:onManualPageTurn()
    if not self.active or self.turning then return end
    self.next_xp = self.ui.document:getXPointer()
    UIManager:scheduleIn(0.3, function()
        if self.active then self:restartQueue() end
    end)
end

return TTS
