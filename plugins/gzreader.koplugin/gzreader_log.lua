--[[--
Plain-text diagnostic log for the Grimmory plugin.

Written to <koreader dir>/gzreader.log (on a Kindle: /mnt/us/koreader/gzreader.log,
visible over USB). Rotates to gzreader.log.1 at ~512 KB. Secrets are redacted
before anything is written: passwords, access/refresh tokens, OIDC codes,
PKCE verifiers, states and the pairing URL token never reach the file.

INFO lines are kept in memory and written together (one open, one write)
FLUSH_AFTER seconds after the first of them, as soon as a warning or an
error comes, when MAX_BUFFER bytes are waiting, and on Log.flush() (the
plugin calls it when the Kindle goes to sleep, on exit and before the log is
exported). A burst of sync logging is then one write to the Kindle's flash
instead of one per line. Background processes (forks) write each line at
once, and drop what the parent hadn't written yet (it's the parent's).
]]

local ffi = require("ffi")
pcall(ffi.cdef, "int getpid(void);")

local MAX_BYTES = 512 * 1024

local Log = {
    enabled = true,
    path = nil,
    buffered = true,
    FLUSH_AFTER = 5,
    MAX_BUFFER = 16 * 1024,
}

local buf, buf_bytes, flush_scheduled = {}, 0, false
local function pid() return ffi.C.getpid() end

-- Size tracked in memory (checked on disk once per run), so a log line is
-- one open + write, not two opens.
local size_known

function Log.init(dir)
    Log.path = dir .. "/gzreader.log"
    size_known = nil
    Log.main_pid = pid()
end

local SECRET_KEYS = {
    "password", "accessToken", "refreshToken", "access_token", "refresh_token",
    "code", "code_verifier", "state", "nonce", "token", "id_token", "passwordMD5",
}

--- Remove secrets from arbitrary text (URLs, JSON, form bodies, headers).
function Log.redact(s)
    s = tostring(s)
    s = s:gsub("([Bb]earer%s+)[%w%-%._~+/=]+", "%1<redacted>")
    s = s:gsub("(/pair/)%x+", "%1<token>")
    -- every pattern below needs "=" or a quoted key: most lines have neither
    if not s:find("=", 1, true) and not s:find('"', 1, true) then return s end
    for _, k in ipairs(SECRET_KEYS) do
        -- key=value in query strings / form bodies
        s = s:gsub("([?&]" .. k .. "=)[^&%s\"]*", "%1<redacted>")
        s = s:gsub("^(" .. k .. "=)[^&%s\"]*", "%1<redacted>")
        -- "key": "value" in JSON
        s = s:gsub("(\"" .. k .. "\"%s*:%s*\")[^\"]*", "%1<redacted>")
    end
    return s
end

local function rotateIfNeeded(adding)
    if not size_known then
        local f = io.open(Log.path, "rb")
        size_known = f and f:seek("end") or 0
        if f then f:close() end
    end
    size_known = size_known + adding
    if size_known > MAX_BYTES then
        os.remove(Log.path .. ".1")
        os.rename(Log.path, Log.path .. ".1")
        size_known = adding
    end
end

local function append(text)
    pcall(function()
        rotateIfNeeded(#text)
        local f = io.open(Log.path, "ab")
        if f then
            f:write(text)
            f:close()
        end
    end)
end

--- Write the lines waiting in memory (in a background process: drop them,
--- they're the parent's to write).
function Log.flush()
    if #buf == 0 then return end
    local lines = buf
    buf, buf_bytes = {}, 0
    if not Log.path or (Log.main_pid and pid() ~= Log.main_pid) then return end
    append(table.concat(lines))
end

local function scheduleFlush()
    if flush_scheduled then return end
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or not UIManager or not UIManager.scheduleIn then return Log.flush() end
    flush_scheduled = true
    UIManager:scheduleIn(Log.FLUSH_AFTER, function()
        flush_scheduled = false
        Log.flush()
    end)
end

local function write(level, ...)
    if not Log.enabled or not Log.path then return end
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[#parts + 1] = type(v) == "table" and "<table>" or tostring(v)
    end
    local line = string.format("%s [%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), level,
        Log.redact(table.concat(parts, " ")))
    if Log.on_line and level ~= "INFO" then pcall(Log.on_line, level, line) end -- remote debugging
    if not Log.buffered or (Log.main_pid and pid() ~= Log.main_pid) then
        if #buf > 0 then Log.flush() end -- (a fork: drops the parent's)
        return append(line)
    end
    buf[#buf + 1] = line
    buf_bytes = buf_bytes + #line
    if level ~= "INFO" or buf_bytes >= Log.MAX_BUFFER then
        Log.flush()
    else
        scheduleFlush()
    end
end

function Log.info(...) write("INFO", ...) end
function Log.warn(...) write("WARN", ...) end
function Log.err(...) write("ERROR", ...) end

--- Copy the log (and the current KOReader crash.log tail) somewhere visible
--- over USB. Returns the destination path or nil, err.
function Log.exportTo(dir, crash_log_path)
    Log.flush()
    local stamp = os.date("%Y%m%d-%H%M%S")
    local dest = string.format("%s/gzreader-log-%s.txt", dir, stamp)
    local out, err = io.open(dest, "wb")
    if not out then return nil, err end
    out:write("Grimmory plugin log, exported ", os.date("%Y-%m-%d %H:%M:%S"), "\n\n")
    for _, p in ipairs({ Log.path .. ".1", Log.path }) do
        local f = io.open(p, "rb")
        if f then
            out:write(f:read("*a"))
            f:close()
        end
    end
    local cf = crash_log_path and io.open(crash_log_path, "rb")
    if cf then
        local size = cf:seek("end")
        cf:seek("set", math.max(0, size - 64 * 1024))
        out:write("\n\n===== tail of KOReader crash.log =====\n", Log.redact(cf:read("*a")))
        cf:close()
    end
    out:write("\n\n===== staying awake =====\n", Log.awakeReport())
    if Log.probe_device then
        out:write("\n\n===== device probe (text-to-speech, audio, Wi-Fi) =====\n", Log.deviceProbe())
    end
    out:close()
    return dest
end

-- Read-only survey used to plan text-to-speech: where the Kindle's own speech
-- engine lives, whether it is reachable over lipc, and what audio playback
-- exists. Only lists/reads; never changes anything. Kept to quick commands
-- that exist in old busybox.
Log.PROBE_COMMANDS = {
    "uname -a",
    "cat /etc/prettyversion.txt /etc/version.txt 2>/dev/null",
    "head -12 /proc/cpuinfo",
    "free",
    "cat /proc/asound/cards 2>&1; cat /proc/asound/devices 2>&1",
    "ls -la /dev/snd /dev/dsp* /dev/audio* /dev/mixer* 2>&1",
    "for b in aplay amixer arecord gst-launch gst-launch-0.10 gst-inspect-0.10 mplayer madplay mpg123 espeak flite tts lipc-probe lipc-get-prop lipc-set-prop lipc-send-event; do p=$(which $b 2>/dev/null); echo \"$b: ${p:-missing}\"; done",
    "ls /usr/bin /usr/sbin /bin /sbin /usr/local/bin 2>/dev/null | awk 'tolower($0) ~ /tts|speak|speech|vocal|nuance|audio|gst|play|mp3|alsa|sound/'",
    "ls -la /usr/lib 2>/dev/null | awk 'tolower($0) ~ /tts|speak|speech|vocal|nuance|vauto|asound|gst|audio/'",
    "ls -la /opt/amazon/ebook/lib 2>/dev/null | awk 'tolower($0) ~ /tts|speak|speech|vocal|nuance|audio|sound/'",
    "for d in /usr/share/tts /opt/tts /opt/amazon/tts /usr/local/tts /mnt/us/tts /mnt/us/usertts /var/local/tts; do [ -e $d ] && { echo \"== $d\"; ls -la $d; }; done",
    "ls -R /usr/share 2>/dev/null | awk 'tolower($0) ~ /tts|vocal|nuance|vauto/' | head -40",
    "ls -R /opt 2>/dev/null | awk 'tolower($0) ~ /tts|vocal|nuance|vauto|speech/' | head -40",
    "lipc-probe -a 2>&1 | head -80",
    "lipc-probe -v com.lab126.tts 2>&1 | head -40",
    "lipc-probe -v com.lab126.audio 2>&1 | head -40",
    "lipc-probe -v com.lab126.audioMgr 2>&1 | head -40",
    "ps 2>/dev/null | awk 'tolower($0) ~ /tts|audio|cvm|speech|java/' | grep -v grep",
    -- GZreader read aloud: where the speech daemons live and what they log
    "ls -la /usr/bin/*tts* /usr/sbin/*tts* /usr/local/bin/*tts* 2>&1",
    "lipc-hash-prop 2>&1 | head -20",
    -- audiobooks: which GStreamer elements exist, and Amazon's audio player
    "ls /usr/lib/gstreamer-0.10 2>&1",
    "gst-inspect-0.10 2>&1 | awk 'tolower($0) ~ /mad|mp3|mpeg|aac|faad|qtdemux|mp4|decodebin|playbin|alsa|mixer|sink|audioconvert|resample|typefind|fdsrc|filesrc|audible/' | head -80",
    "strings /usr/bin/audioServer 2>/dev/null | awk 'tolower($0) ~ /player|uri|seek|play|mp3|aac|audible|gst|pipeline|sink|lipc/' | head -150",
    "ps 2>/dev/null | awk 'tolower($0) ~ /audioserver|gst|aplay/' | grep -v awk",
    "strings /usr/sbin/ttsd 2>/dev/null | awk 'tolower($0) ~ /snippet|unable|read|voice|text|lipc|enqueue|play|speak|id$/' | head -200",
    "awk 'tolower($0) ~ /tts|snippet/' /var/log/messages 2>/dev/null | tail -40",
    -- firmware 2.x: which file or pipe ttsd's playFile wants (its built-in paths)
    "strings /usr/sbin/ttsd 2>/dev/null | awk '/\\// || tolower($0) ~ /fifo|\\.txt|\\.text|wrong/' | head -40",
    "ls -la /var/tmp/*tts* /var/tmp/*Fifo* /tmp/*tts* /tmp/*Fifo* 2>&1 | head -20",
    -- Wi-Fi networks menu: the lipc libraries and the Wi-Fi services' property
    -- names and states (no network names or passwords)
    "ls -la /usr/lib/liblipc* common/*lipc* libs/*lipc* 2>&1",
    "lipc-probe com.lab126.wifid 2>&1 | head -60",
    "lipc-probe com.lab126.cmd 2>&1 | head -40",
    "for p in cmState scanState; do echo \"$p: $(lipc-get-prop com.lab126.wifid $p 2>&1)\"; done",
}

--- What keeps the Kindle from sleeping, as the log is sent: GZreader's
--- holders, what's playing, and the Kindle's own screensaver block.
function Log.awakeReport()
    local lines = {}
    local A = package.loaded["gzreader_awake"]
    lines[#lines + 1] = "GZreader keeps it awake for: " .. (A and A.count > 0 and A.who() or "nothing")
    local AB = package.loaded["gzreader_audiobook"]
    local cur = AB and AB.current
    lines[#lines + 1] = "audiobook: " .. (cur and (cur.playing and "playing" or (cur.paused and "paused" or "stopped")) or "none")
    local M = package.loaded["gzreader_music"]
    local mc = M and M.current
    lines[#lines + 1] = "music: " .. (mc and (mc.waiting and "waiting for a track" or (mc.playing and "playing" or "paused")) or "none")
    local ok, Device = pcall(require, "device")
    if ok and Device.isKindle and Device:isKindle() then
        for _i, prop in ipairs({ "preventScreenSaver", "status", "state" }) do
            local f = io.popen("lipc-get-prop com.lab126.powerd " .. prop .. " 2>&1")
            local v = f and f:read("*a") or ""
            if f then f:close() end
            lines[#lines + 1] = "powerd " .. prop .. ": " .. v:gsub("%s+$", ""):gsub("\n", " / ")
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

function Log.deviceProbe()
    local parts = {}
    for _, cmd in ipairs(Log.PROBE_COMMANDS) do
        parts[#parts + 1] = "$ " .. cmd
        local ok, result = pcall(function()
            local p = io.popen(cmd .. " 2>&1")
            if not p then return "(could not run)" end
            local outp = p:read("*a") or ""
            p:close()
            return #outp > 8000 and (outp:sub(1, 8000) .. "\n…truncated") or outp
        end)
        parts[#parts + 1] = ok and result or ("(error: " .. tostring(result) .. ")")
    end
    return table.concat(parts, "\n")
end

return Log
