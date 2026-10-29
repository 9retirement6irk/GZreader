--[[--
Audio playback for GZreader audiobooks on a Kindle Keyboard.

The Kindle 3 has a speaker/headphone jack (ALSA, WM8960), GStreamer 0.10
(gst-launch-0.10) and Amazon's audio service (com.lab126.audio over lipc,
which plays MP3 and Audible books for the stock "Experimental → MP3 player"
and audiobooks). What decodes which format differs between firmware builds,
so "Test audio playback" plays two short test tunes (MP3, and AAC as used by
M4B audiobooks) through each candidate player, logs what the Kindle says,
asks which you heard, and remembers the player per format.

Players:
  gst  gst-launch-0.10 pipelines (process in the background; pause/resume by
       SIGSTOP/SIGCONT; starting mid-file for MP3 by skipping bytes, as MP3
       frames can be decoded from anywhere);
  lipc Amazon's com.lab126.audio player (URI + PlayerCreate/PlayerStart …).
Position is timed on the Kindle (wall clock while playing).
]]

local UIManager = require("ui/uimanager")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = require("ffi/util").template

local PID_FILE = "/tmp/gzreader-audio.pid"
local LOG_FILE = "/tmp/gzreader-audio.log"

local Engine = {
    exec = nil,        -- injectable: function(cmd)
    syslog = "/var/log/messages",
    root = nil,        -- plugin folder (set by main.lua)
    clock = os.time,
    testing = false,
}

Engine.PLAYERS = {
    { id = "gst-decodebin", kind = "gst", seek_mp3 = true,
      pipe = "decodebin ! audioconvert ! audioresample ! alsasink" },
    { id = "gst-playbin", kind = "gst", playbin = true },
    { id = "gst-mad", kind = "gst", formats = { mp3 = true }, seek_mp3 = true,
      pipe = "mad ! audioconvert ! audioresample ! alsasink" },
    { id = "gst-faad", kind = "gst", formats = { m4a = true },
      pipe = "qtdemux ! faad ! audioconvert ! audioresample ! alsasink" },
    { id = "gst-mixersink", kind = "gst", seek_mp3 = true,
      pipe = "decodebin ! audioconvert ! audioresample ! mixersink" },
    { id = "lipc-audio", kind = "lipc" },
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

--- Audio format family of a file: "mp3", "m4a" (AAC: m4a/m4b/mp4/aac) or nil.
function Engine.format(path)
    local ext = tostring(path):match("%.([%w]+)$")
    ext = ext and ext:lower()
    if ext == "mp3" then return "mp3" end
    if ext == "m4a" or ext == "m4b" or ext == "mp4" or ext == "aac" then return "m4a" end
    return ext
end

local function player(id)
    for _i, p in ipairs(Engine.PLAYERS) do if p.id == id then return p end end
end

function Engine.chosen(fmt)
    local saved = G_reader_settings:readSetting("gzreader_audio_players") or {}
    return saved[fmt] and player(saved[fmt]) or nil
end

local function quote(path) return "'" .. tostring(path):gsub("'", "'\\''") .. "'" end

local function lipcSet(prop, value, int)
    run(string.format("lipc-set-prop %s com.lab126.audio %s %s >> %s 2>&1",
        int and "-i" or "-s", prop, int and tostring(math.floor(value)) or quote(value), LOG_FILE))
end

--- Build the shell command that plays `path` from `offset_ms` with player `p`.
--- size/duration_ms are used to start an MP3 mid-file by skipping bytes.
function Engine.command(p, path, offset_ms, size, duration_ms)
    local fmt = Engine.format(path)
    if p.playbin then
        return string.format("gst-launch-0.10 -q playbin uri=%s", quote("file://" .. path))
    end
    local skip = 0
    if offset_ms and offset_ms > 0 and fmt == "mp3" and p.seek_mp3 and size and duration_ms and duration_ms > 0 then
        skip = math.floor(size * offset_ms / duration_ms / 4096)
    end
    if skip > 0 then
        return string.format("dd if=%s bs=4096 skip=%d 2>/dev/null | gst-launch-0.10 -q fdsrc ! %s", quote(path), skip, p.pipe)
    end
    return string.format("gst-launch-0.10 -q filesrc location=%s ! %s", quote(path), p.pipe)
end

--- Can player `p` start `path` at `offset_ms`? (else it starts at 0)
function Engine.canSeek(p, path)
    return p.kind == "lipc" or (Engine.format(path) == "mp3" and p.seek_mp3 == true)
end

---------------------------------------------------------------- playback

local current -- { p, pid, path, started_at, offset_ms, paused_at }

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

--- Start playing. Returns true or nil, err.
function Engine.play(p, path, offset_ms, size, duration_ms)
    Engine.stop()
    os.remove(LOG_FILE)
    local started_ms = offset_ms or 0
    if p.kind == "gst" then
        os.remove(PID_FILE)
        local cmd = Engine.command(p, path, offset_ms, size, duration_ms)
        if not Engine.canSeek(p, path) then started_ms = 0 end
        run(string.format("(%s > %s 2>&1 & echo $! > %s) >/dev/null 2>&1", cmd, LOG_FILE, PID_FILE))
    else
        local uri = "file://" .. path
        lipcSet("URI", uri)
        lipcSet("PlayerCreate", uri)
        lipcSet("PlayerStart", uri)
        if offset_ms and offset_ms > 0 then lipcSet("Seek", offset_ms, true) end
    end
    current = { p = p, path = path, offset_ms = started_ms, started_at = Engine.clock(), pid = nil }
    Log.info("audio play", p.id, path, "from", started_ms, "ms")
    return true, started_ms
end

function Engine.position()
    if not current then return 0 end
    if current.paused_at then return current.offset_ms end
    return current.offset_ms + (Engine.clock() - current.started_at) * 1000
end

--- Is the current track still playing? (false when it reached its end)
function Engine.running()
    if not current then return false end
    if current.p.kind == "gst" then
        current.pid = current.pid or Engine.pid()
        if not current.pid then return true end -- just started, pid not written yet
        return current.paused_at ~= nil or Engine.alive(current.pid)
    end
    return true -- the lipc player doesn't tell us; the duration does
end

function Engine.pause()
    if not current or current.paused_at then return end
    current.offset_ms = Engine.position()
    current.paused_at = Engine.clock()
    if current.p.kind == "gst" then
        local pid = current.pid or Engine.pid()
        if pid then run("kill -STOP " .. pid .. " >/dev/null 2>&1") end
    else
        lipcSet("PlayerPause", "file://" .. current.path)
    end
end

function Engine.resume()
    if not current or not current.paused_at then return end
    current.paused_at = nil
    current.started_at = Engine.clock()
    if current.p.kind == "gst" then
        local pid = current.pid or Engine.pid()
        if pid then run("kill -CONT " .. pid .. " >/dev/null 2>&1") end
    else
        lipcSet("PlayerResume", "file://" .. current.path)
    end
end

function Engine.stop()
    if not current then return end
    if current.p.kind == "gst" then
        local pid = current.pid or Engine.pid()
        if pid then run("kill -CONT " .. pid .. " >/dev/null 2>&1; kill " .. pid .. " >/dev/null 2>&1") end
        os.remove(PID_FILE)
    else
        lipcSet("PlayerStop", "file://" .. current.path)
        lipcSet("PlayerRelease", "file://" .. current.path)
    end
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

--- Recent lines from the system log about audio (for the diagnostic log).
local function audioSyslog()
    local s = readFile(Engine.syslog)
    if not s then return "" end
    local lines = {}
    for line in s:sub(-8192):gmatch("[^\n]+") do
        local l = line:lower()
        if l:find("audio") or l:find("gst") or l:find("player") or l:find("alsa") then lines[#lines + 1] = line end
    end
    return table.concat(lines, "\n", math.max(1, #lines - 8))
end

local function sample(fmt)
    return (Engine.root or ".") .. "/audio/test." .. fmt
end

--- Try every player for MP3 and for AAC (M4B); ask which test tune was heard.
function Engine.test(on_done)
    if Engine.testing then return end
    Engine.testing = true
    local InfoMessage = require("ui/widget/infomessage")
    local ConfirmBox = require("ui/widget/confirmbox")
    local chosen = G_reader_settings:readSetting("gzreader_audio_players") or {}
    local plan = {}
    for _i, fmt in ipairs({ "mp3", "m4a" }) do
        for _j, p in ipairs(Engine.PLAYERS) do
            if not p.formats or p.formats[fmt] then plan[#plan + 1] = { fmt = fmt, p = p } end
        end
    end
    local i = 0
    local found = {}
    local function finish()
        Engine.testing = false
        Engine.stop()
        G_reader_settings:saveSetting("gzreader_audio_players", chosen)
        local summary = T(_("MP3: %1\nM4B / AAC: %2"),
            chosen.mp3 or _("no working player found"), chosen.m4a or _("no working player found"))
        Log.info("audio test result", chosen.mp3 or "-", chosen.m4a or "-")
        UIManager:show(InfoMessage:new{ text = _("Audio test finished.") .. "\n\n" .. summary
            .. ((chosen.mp3 and chosen.m4a) and "" or ("\n\n" .. _("Save the diagnostic log (Grimmory menu) and send it so missing players can be added."))) })
        if on_done then on_done(chosen) end
    end
    local function step()
        i = i + 1
        local item = plan[i]
        if not item then return finish() end
        if found[item.fmt] then return step() end -- already have one for this format
        local path = sample(item.fmt)
        Engine.play(item.p, path, 0)
        UIManager:scheduleIn(3.5, function()
            local log = readFile(LOG_FILE) or ""
            local ok_process = item.p.kind ~= "gst" or not (log:lower():find("error") or log:lower():find("no such element")
                or log:lower():find("not found") or log:lower():find("could not"))
            Log.info("audio test", item.fmt, item.p.id, ok_process and "ran" or "failed", "|", log:sub(1, 300):gsub("\n", " / "),
                "| syslog:", audioSyslog():gsub("\n", " / "))
            Engine.stop()
            if not ok_process then return step() end
            UIManager:show(ConfirmBox:new{
                text = T(_("Did you just hear a short tune (%1 test)?"), item.fmt == "mp3" and "MP3" or "M4B / AAC"),
                ok_text = _("Yes"), cancel_text = _("No"),
                ok_callback = function()
                    found[item.fmt] = true
                    chosen[item.fmt] = item.p.id
                    UIManager:scheduleIn(0.5, step)
                end,
                cancel_callback = function() UIManager:scheduleIn(0.5, step) end,
            })
        end)
    end
    UIManager:show(InfoMessage:new{ text = _("Audio test: listen to the speaker or headphones. The Kindle plays a short tune with each player and asks whether you heard it."), timeout = 5 })
    chosen = {}
    UIManager:scheduleIn(5.5, step)
end

return Engine
