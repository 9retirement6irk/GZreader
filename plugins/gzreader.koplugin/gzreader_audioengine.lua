--[[--
Audio playback for GZreader audiobooks on a Kindle Keyboard.

What the Kindle 3 has (from its diagnostic log, firmware 3.4.3):
- GStreamer 0.10 (gst-launch-0.10, which has no "-q" option) with Freescale
  hardware decoders: mfw_mp3decoder and mfw_aacdecoder, plus decodebin,
  playbin, typefind, filesrc/fdsrc and alsasink. No MP4 demuxer (qtdemux),
  so M4B/M4A files are converted to ADTS AAC chunks after download
  (gzreader_mp4.lua) and streamed to the AAC decoder.
- Amazon's audioServer (com.lab126.audio over lipc): playbin-based, needs
  absolute file paths.

"Test audiobook playback" (Settings → Reader) plays a short MP3 and an AAC tune (converted on the
Kindle from the bundled M4A, which also tests the converter) through each
candidate pipeline, logs what the Kindle says, asks which you heard and
remembers the pipeline per format.

Sources:
  file    an MP3 file; starting mid-file by skipping bytes (MP3 decoders
          resynchronise on the next frame);
  chunks  ADTS chunk files c<N>.aac; starting at the chunk that holds the
          position, then cat-ing the following chunks into the decoder.
Pause/resume: SIGSTOP/SIGCONT of the gst-launch process. Position: timed on
the Kindle while playing.
]]

local bit = require("bit")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local PID_FILE = "/tmp/gzreader-audio.pid"
local LOG_FILE = "/tmp/gzreader-audio.log"
local SINK = "audioconvert ! audioresample ! alsasink"

local Engine = {
    exec = nil,        -- injectable: function(cmd)
    syslog = "/var/log/messages",
    root = nil,        -- plugin folder (set by main.lua)
    clock = os.time,
    testing = false,
}

-- stream = true: the pipeline reads from stdin (fdsrc), so it can play from
-- any position (MP3 byte skip, AAC chunks).
Engine.PLAYERS = {
    { id = "mp3-mfw", formats = { mp3 = true }, stream = true, pipe = "mfw_mp3decoder ! " .. SINK },
    { id = "mp3-typefind-mfw", formats = { mp3 = true }, stream = true, pipe = "typefind ! mfw_mp3decoder ! " .. SINK },
    { id = "mp3-decodebin", formats = { mp3 = true }, stream = true, pipe = "decodebin ! " .. SINK },
    { id = "aac-mfw", formats = { aac = true }, stream = true, pipe = "mfw_aacdecoder ! " .. SINK },
    { id = "aac-typefind-mfw", formats = { aac = true }, stream = true, pipe = "typefind ! mfw_aacdecoder ! " .. SINK },
    { id = "aac-decodebin", formats = { aac = true }, stream = true, pipe = "decodebin ! " .. SINK },
    { id = "playbin", formats = { mp3 = true, aac = true }, playbin = true },
}

local function run(cmd)
    if Engine.exec then return Engine.exec(cmd) end
    return os.execute(cmd)
end

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function abs(path)
    if tostring(path):sub(1, 1) == "/" then return path end
    return (lfs.currentdir() or ".") .. "/" .. path
end

--- Audio format family of a file: "mp3", "m4a" (MP4 container) or "aac" (ADTS).
function Engine.format(path)
    local ext = tostring(path):match("%.([%w]+)$")
    ext = ext and ext:lower()
    if ext == "mp3" then return "mp3" end
    if ext == "m4a" or ext == "m4b" or ext == "mp4" then return "m4a" end
    if ext == "aac" then return "aac" end
    return ext
end

local function player(id)
    for _i, p in ipairs(Engine.PLAYERS) do if p.id == id then return p end end
end

--- The pipeline chosen by the audio test for "mp3" or "aac".
function Engine.chosen(fmt)
    local saved = G_reader_settings:readSetting("gzreader_audio_players") or {}
    return saved[fmt] and player(saved[fmt]) or nil
end

local function quote(path) return "'" .. tostring(path):gsub("'", "'\\''") .. "'" end

local ADTS_RATES = { [0] = 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350 }

--- Where `ms` falls in an ADTS file: the byte offset of the frame playing
--- then, and the time that frame starts at. (0, 0) if the file can't be read.
--- Lets a paused AAC audiobook carry on within its 15-second chunk.
function Engine.adtsSkip(path, ms)
    if not ms or ms <= 0 then return 0, 0 end
    local f = io.open(path, "rb")
    if not f then return 0, 0 end
    local data = f:read("*a")
    f:close()
    local pos, t, n = 1, 0, #data
    while pos + 6 <= n do
        local b1, b2, b3, b4, b5, b6, b7 = data:byte(pos, pos + 6)
        if b1 ~= 0xFF or bit.band(b2, 0xF6) ~= 0xF0 then return 0, 0 end -- not ADTS (or lost sync)
        local rate = ADTS_RATES[bit.band(bit.rshift(b3, 2), 0x0F)]
        local len = bit.bor(bit.lshift(bit.band(b4, 3), 11), bit.lshift(b5, 3), bit.rshift(b6, 5))
        if not rate or len < 7 then return 0, 0 end
        local dur = 1024 * (bit.band(b7, 3) + 1) * 1000 / rate
        if t + dur > ms then break end
        t = t + dur
        pos = pos + len
    end
    if pos > n then return 0, 0 end -- (past the end: from the start of the chunk)
    return pos - 1, t
end

--- The shell command playing `src` with player `p`.
--- src = { kind = "file", path, offset_ms, size, duration_ms }
---     | { kind = "chunks", dir, starts = { ms… }, offset_ms }
--- Returns command, position actually started at (ms).
function Engine.command(p, src)
    local offset = src.offset_ms or 0
    if src.kind == "chunks" then
        local k = 1
        for i, st in ipairs(src.starts or { 0 }) do if st <= offset then k = i end end
        local start = (src.starts or { 0 })[k] or 0
        -- into the chunk, from the ADTS frame playing at `offset`
        local skip, skipped = Engine.adtsSkip(src.dir .. "/c" .. (k - 1) .. ".aac", offset - start)
        local loop = string.format("while [ -f %s/c$i.aac ]; do cat %s/c$i.aac; i=$((i+1)); done",
            quote(src.dir), quote(src.dir))
        local feed
        if skip > 0 then
            feed = string.format("i=%d; { dd if=%s/c%d.aac bs=%d skip=1 2>/dev/null; %s; }",
                k, quote(src.dir), k - 1, skip, loop)
        else
            feed = string.format("i=%d; %s", k - 1, loop)
        end
        return feed .. " | gst-launch-0.10 fdsrc ! " .. p.pipe, start + math.floor(skipped)
    end
    local path = abs(src.path)
    if p.playbin then
        return string.format("gst-launch-0.10 playbin uri=%s", quote("file://" .. path)), 0
    end
    local skip = 0
    if offset > 0 and src.size and src.duration_ms and src.duration_ms > 0 then
        skip = math.floor(src.size * offset / src.duration_ms / 4096)
    end
    local started = skip > 0 and math.floor(skip * 4096 * src.duration_ms / src.size) or 0
    return string.format("dd if=%s bs=4096 skip=%d 2>/dev/null | gst-launch-0.10 fdsrc ! %s", quote(path), skip, p.pipe), started
end

---------------------------------------------------------------- playback

local current -- { p, src, pid, started_at, offset_ms, paused_at }

function Engine.pid()
    local s = readFile(PID_FILE)
    return s and tonumber(s:match("%d+"))
end

local function alive(pid)
    if not pid then return false end
    local f = io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local st = f:read("*l") or ""
    f:close()
    return not st:match("^%d+ %b() Z") -- not a zombie
end
Engine.alive = alive -- injectable for tests

--- Stop players left from an earlier run: GZreader restarted (an update, for
--- example) while one was playing or paused, so `current` forgot it. The
--- Kindle 3's sound device takes one player at a time, so a leftover one
--- makes every later play fail. Only GZreader runs gst-launch (Amazon's own
--- player is audioServer).
function Engine.stopStray()
    if current then return end
    local pid = Engine.pid()
    if pid and Engine.alive(pid) then
        Log.warn("audio: stopping a player left from before", pid)
        run(string.format("kill -CONT %d >/dev/null 2>&1; kill -TERM %d >/dev/null 2>&1", pid, pid))
    end
    os.remove(PID_FILE)
    run("for p in $(pidof gst-launch-0.10 2>/dev/null); do kill -CONT $p; kill -TERM $p; done >/dev/null 2>&1")
end

--- At GZreader's start: only the player it started itself (cheap, no shell
--- unless there is one).
function Engine.stopStrayAtStart()
    if current then return end
    local pid = Engine.pid()
    if pid and Engine.alive(pid) then
        Log.warn("audio: stopping a player left running before the restart", pid)
        run(string.format("kill -CONT %d >/dev/null 2>&1; kill -TERM %d >/dev/null 2>&1", pid, pid))
    end
    if pid then os.remove(PID_FILE) end
end

--- Start playing `src` with `p`. Returns true, position started at (ms).
function Engine.play(p, src)
    Engine.stop()
    Engine.stopStray()
    os.remove(LOG_FILE)
    os.remove(PID_FILE)
    local cmd, started_ms = Engine.command(p, src)
    run(string.format("(%s > %s 2>&1 & echo $! > %s) >/dev/null 2>&1", cmd, LOG_FILE, PID_FILE))
    current = { p = p, src = src, offset_ms = started_ms, first_offset_ms = started_ms, started_at = Engine.clock() }
    Log.info("audio play", p.id, src.path or src.dir, "from", started_ms, "ms")
    return true, started_ms
end

function Engine.position()
    if not current then return 0 end
    if current.paused_at then return current.offset_ms end
    return current.offset_ms + (Engine.clock() - current.started_at) * 1000
end

--- Milliseconds actually played since this play() (not the book position).
function Engine.played()
    if not current then return 0 end
    return Engine.position() - (current.first_offset_ms or current.offset_ms)
end

--- Is it still playing? (false once the stream ended or the player failed)
function Engine.running()
    if not current then return false end
    current.pid = current.pid or Engine.pid()
    if not current.pid then return Engine.clock() - current.started_at < 5 end -- pid not written yet
    return current.paused_at ~= nil or Engine.alive(current.pid)
end

function Engine.log() return readFile(LOG_FILE) or "" end

local function signal(sig)
    local pid = current and (current.pid or Engine.pid())
    if pid then run(string.format("kill -%s %d >/dev/null 2>&1", sig, pid)) end
end

function Engine.pause()
    if not current or current.paused_at then return end
    current.offset_ms = Engine.position()
    current.paused_at = Engine.clock()
    signal("STOP")
end

function Engine.resume()
    if not current or not current.paused_at then return end
    current.paused_at = nil
    current.started_at = Engine.clock()
    signal("CONT")
end

function Engine.stop()
    if not current then return end
    signal("CONT")
    signal("TERM")
    os.remove(PID_FILE)
    current = nil
end

function Engine.isPaused() return current ~= nil and current.paused_at ~= nil end
function Engine.active() return current ~= nil end

---------------------------------------------------------------- volume

function Engine.volume() return G_reader_settings:readSetting("gzreader_tts_volume") or 10 end
function Engine.setVolume(v)
    v = math.max(0, math.min(15, v))
    G_reader_settings:saveSetting("gzreader_tts_volume", v)
    run(string.format("lipc-set-prop -i com.lab126.audio CmdIVolume %d >/dev/null 2>&1 &", v))
end

---------------------------------------------------------------- test

local function audioSyslog()
    local s = readFile(Engine.syslog)
    if not s then return "" end
    local lines = {}
    for line in s:sub(-8192):gmatch("[^\n]+") do
        local l = line:lower()
        if l:find("audio") or l:find("gst") or l:find("mfw") or l:find("alsa") then lines[#lines + 1] = line end
    end
    return table.concat(lines, "\n", math.max(1, #lines - 6))
end

--- Test sources: the bundled MP3, and the bundled M4A converted to ADTS chunks.
function Engine.testSources()
    local root = abs(Engine.root or ".")
    local srcs = { mp3 = { kind = "file", path = root .. "/audio/test.mp3" } }
    local dir = "/tmp/gzreader-audiotest"
    lfs.mkdir(dir)
    local ok, conv = pcall(function()
        return require("gzreader_mp4").convert(root .. "/audio/test.m4a", dir)
    end)
    if ok and conv then
        srcs.aac = { kind = "chunks", dir = dir, starts = conv.starts }
        srcs.aac_file = { kind = "file", path = dir .. "/c0.aac" }
        Log.info("audio test: M4A converted to ADTS", conv.count, "chunk(s),", conv.durationMs, "ms")
    else
        Log.warn("audio test: M4A conversion failed:", tostring(conv))
    end
    return srcs
end

--- Try the pipelines for MP3 and for AAC (M4B); ask which test tune was heard.
function Engine.test(on_done)
    if Engine.testing then return end
    Engine.testing = true
    Engine.stop()
    Engine.stopStray()
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")
    local srcs = Engine.testSources()
    local plan = {}
    for _i, fmt in ipairs({ "mp3", "aac" }) do
        for _j, p in ipairs(Engine.PLAYERS) do
            if p.formats[fmt] then
                local src = srcs[fmt]
                if p.playbin and fmt == "aac" then src = srcs.aac_file end
                if src then plan[#plan + 1] = { fmt = fmt, p = p, src = src } end
            end
        end
    end
    local chosen, i = {}, 0
    local function finish()
        Engine.testing = false
        Engine.stop()
        -- Keep an earlier working choice for a format nothing worked for this
        -- time (a busy sound device shouldn't undo a setup that worked).
        local saved = {}
        for k, v in pairs(G_reader_settings:readSetting("gzreader_audio_players") or {}) do saved[k] = v end
        for k, v in pairs(chosen) do saved[k] = v end
        G_reader_settings:saveSetting("gzreader_audio_players", saved)
        Log.info("audio test result", "mp3=" .. tostring(chosen.mp3), "aac=" .. tostring(chosen.aac))
        UIManager:show(InfoMessage:new{ text = _("Audio test finished.") .. "\n\n"
            .. T(_("MP3: %1\nM4B / AAC: %2"), chosen.mp3 or _("no working player found"), chosen.aac or _("no working player found"))
            .. ((chosen.mp3 and chosen.aac) and "" or ("\n\n" .. _("Send the diagnostic log (Settings → General) so this can be fixed."))) })
        if on_done then on_done(chosen) end
    end
    local function step()
        i = i + 1
        local item = plan[i]
        if not item then return finish() end
        if chosen[item.fmt] then return step() end
        Engine.play(item.p, item.src)
        UIManager:scheduleIn(3.5, function()
            local out = Engine.log()
            local lower = out:lower()
            local failed = lower:find("error") or lower:find("no such element") or lower:find("could not")
                or lower:find("unknown option") or lower:find("not found") or lower:find("erroneous")
            Log.info("audio test", item.fmt, item.p.id, failed and "failed" or "ran", "|", out:sub(1, 300):gsub("\n", " / "),
                "| syslog:", (audioSyslog():gsub("\n", " / ")))
            Engine.stop()
            if failed then return step() end
            UIManager:show(ConfirmBox:new{
                text = T(_("Did you just hear a short tune (%1 test)?"), item.fmt == "mp3" and "MP3" or "M4B / AAC"),
                ok_text = _("Yes"), cancel_text = _("No"),
                ok_callback = function()
                    chosen[item.fmt] = item.p.id
                    UIManager:scheduleIn(0.5, step)
                end,
                cancel_callback = function() UIManager:scheduleIn(0.5, step) end,
            })
        end)
    end
    UIManager:show(InfoMessage:new{ text = _("Audio test: listen to the speaker or headphones. The Kindle plays a short tune with each player and asks whether you heard it."), timeout = 5 })
    UIManager:scheduleIn(5.5, step)
end

return Engine
