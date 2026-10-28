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
    out:close()
    return dest
end

return Log
