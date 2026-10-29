--[[--
Plain-text diagnostic log for the Grimmory plugin.

Written to <koreader dir>/grimmory.log (on a Kindle: /mnt/us/koreader/grimmory.log,
visible over USB). Rotates to grimmory.log.1 at ~512 KB. Secrets are redacted
before anything is written: passwords, access/refresh tokens, OIDC codes,
PKCE verifiers, states and the pairing URL token never reach the file.
]]

local MAX_BYTES = 512 * 1024

local Log = {
    enabled = true,
    path = nil,
}

function Log.init(dir)
    Log.path = dir .. "/grimmory.log"
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
    for _, k in ipairs(SECRET_KEYS) do
        -- key=value in query strings / form bodies
        s = s:gsub("([?&]" .. k .. "=)[^&%s\"]*", "%1<redacted>")
        s = s:gsub("^(" .. k .. "=)[^&%s\"]*", "%1<redacted>")
        -- "key": "value" in JSON
        s = s:gsub("(\"" .. k .. "\"%s*:%s*\")[^\"]*", "%1<redacted>")
    end
    return s
end

local function rotateIfNeeded()
    local f = io.open(Log.path, "rb")
    if not f then return end
    local size = f:seek("end")
    f:close()
    if size and size > MAX_BYTES then
        os.remove(Log.path .. ".1")
        os.rename(Log.path, Log.path .. ".1")
    end
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
    pcall(function()
        rotateIfNeeded()
        local f = io.open(Log.path, "ab")
        if f then
            f:write(line)
            f:close()
        end
    end)
end

function Log.info(...) write("INFO", ...) end
function Log.warn(...) write("WARN", ...) end
function Log.err(...) write("ERROR", ...) end

--- Copy the log (and the current KOReader crash.log tail) somewhere visible
--- over USB. Returns the destination path or nil, err.
function Log.exportTo(dir, crash_log_path)
    local stamp = os.date("%Y%m%d-%H%M%S")
    local dest = string.format("%s/grimmory-log-%s.txt", dir, stamp)
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
    if Log.probe_device then
        out:write("\n\n===== device probe (text-to-speech / audio) =====\n", Log.deviceProbe())
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
    "awk 'tolower($0) ~ /tts|snippet/' /var/log/messages 2>/dev/null | tail -40",
}

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
