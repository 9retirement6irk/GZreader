--[[--
Passwords, tokens, keys and calendar links kept off the Kindle's USB drive.

On a Kindle, KOReader's settings live on the USB drive (/mnt/us/koreader/
settings): any computer the Kindle is plugged into can read them. GZreader's
state (settings/gzreader.lua, and gzreader_recent.lua between full saves)
held the sign-ins in it: the CalDAV password, the Home Assistant, Memos and
Plex tokens, the Immich key, the Access key and Cloudflare token, the handwriting
services' keys (Claude, OpenAI-style), Grimmory's
sign-in tokens and the calendar links (their keys are in the address).

Those (PATHS, and each calendar link's url) are kept in SECRET_FILE on the
Kindle's own disk instead (/var/local: not shared over USB), and every save
takes them out of what is written to the drive: Grimmory:save() calls
strip() just before writing and restore() right after; init calls load().
A GZreader before this one, given the same settings, finds no sign-ins (it
asks to connect again).

Only where it matters and works: the settings are on a USB drive and the
device's own disk can be written (`active()`): a Kindle (/mnt/us, kept in
/var/local/gzreader) or a Kobo (/mnt/onboard, kept in /usr/local/gzreader:
a Kobo firmware update can clear it, and GZreader then asks to connect
again). Elsewhere (the Nook keeps its settings on its own disk, the
emulator, the tests) nothing changes.
]]

local Secrets = {
    DIR = "/var/local/gzreader", -- (the place in use: set by active())
    FILE = "secrets.lua",
    -- settings on this USB drive: sign-ins kept in this folder on the device's own disk
    PLACES = {
        { drive = "/mnt/us/", dir = "/var/local/gzreader" },      -- a Kindle
        { drive = "/mnt/onboard/", dir = "/usr/local/gzreader" }, -- a Kobo
    },
    -- { key, key, … } inside the state
    PATHS = {
        { "refresh_token" }, { "access_token" },
        { "caldav", "password" },
        { "memos", "token" },
        { "plex", "token" }, { "plex", "server", "token" },
        { "homeassistant", "token" },
        { "immich", "key" },
        { "access", "key" }, { "access", "cf_id" }, { "access", "cf_secret" },
        { "handwriting", "claude", "key" }, { "handwriting", "openai", "key" },
    },
    written = nil, -- (what the file holds, as last written or read)
    on = nil,      -- (active(), worked out once)
}

local function settingsDir()
    local ok, DataStorage = pcall(require, "datastorage")
    return ok and DataStorage:getSettingsDir() or nil
end

function Secrets.path() return Secrets.DIR .. "/" .. Secrets.FILE end

--- Are sign-ins kept apart here? (settings on the USB drive, the Kindle's own disk writable)
function Secrets.active()
    if Secrets.on ~= nil then return Secrets.on end
    local dir = settingsDir()
    local on = false
    for _i, place in ipairs(Secrets.PLACES) do
        if dir and dir:sub(1, #place.drive) == place.drive then
            os.execute("mkdir -p '" .. place.dir .. "' 2>/dev/null")
            local probe = place.dir .. "/.write-test"
            local f = io.open(probe, "w")
            if f then f:close(); os.remove(probe); on = true; Secrets.DIR = place.dir end
            break
        end
    end
    Secrets.on = on
    return on
end

local function get(t, path)
    for i = 1, #path - 1 do
        t = type(t) == "table" and t[path[i]] or nil
    end
    return type(t) == "table" and t[path[#path]] or nil, t
end

local function feedKey(f, i) return "calendar_feeds#" .. tostring(f.id or i) end

--- The values to keep apart, as { ["a.b"] = value }; with clear, also taken out of `store`.
local function collect(store, clear)
    local out = {}
    for _i, path in ipairs(Secrets.PATHS) do
        local v, parent = get(store, path)
        if v ~= nil then
            out[table.concat(path, ".")] = v
            if clear then parent[path[#path]] = nil end
        end
    end
    for i, f in ipairs(type(store.calendar_feeds) == "table" and store.calendar_feeds or {}) do
        if type(f) == "table" and f.url ~= nil then
            if not f.id then f.id = require("gzreader_pairserver").randomToken(4) end
            out[feedKey(f, i) .. ".url"] = f.url
            if clear then f.url = nil end
        end
    end
    return out
end

local function serialize(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines = { "return {" }
    for _i, k in ipairs(keys) do
        local v = t[k]
        if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then
            lines[#lines + 1] = string.format("    [%q] = %s,", k, type(v) == "string" and string.format("%q", v) or tostring(v))
        end
    end
    lines[#lines + 1] = "}\n"
    return table.concat(lines, "\n")
end

--- Write the file if what it holds changed (a new file, then renamed over: never half written).
local function write(values)
    local text = serialize(values)
    local have = io.open(Secrets.path(), "r")
    if have then have:close() end
    if text == Secrets.written and have then return true end
    local tmp = Secrets.path() .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(text)
    f:close()
    if not os.rename(tmp, Secrets.path()) then os.remove(tmp); return false end
    Secrets.written = text
    return true
end

--- Before a save: take the sign-ins out of `store` (they're written to their
--- own file). Returns what restore() puts back, or nil (nothing taken out).
function Secrets.strip(store)
    if type(store) ~= "table" or not Secrets.active() then return nil end
    local values = collect(store, false)
    if not write(values) then
        -- (the Kindle's disk can't be written right now: keep them where they were rather than lose them)
        require("gzreader_log").warn("secrets: couldn't write", Secrets.path(), "- sign-ins stay in the settings this time")
        return nil
    end
    collect(store, true)
    return values
end

--- After a save: the sign-ins back in `store`.
function Secrets.restore(store, values)
    if type(store) ~= "table" or type(values) ~= "table" then return end
    for _i, path in ipairs(Secrets.PATHS) do
        local v = values[table.concat(path, ".")]
        if v ~= nil then
            local parent = select(2, get(store, path))
            if type(parent) == "table" then parent[path[#path]] = v end
        end
    end
    for i, f in ipairs(type(store.calendar_feeds) == "table" and store.calendar_feeds or {}) do
        local v = type(f) == "table" and values[feedKey(f, i) .. ".url"]
        if v ~= nil then f.url = v end
    end
end

--- At start: the sign-ins from their file into `store` (a value the settings
--- still hold wins: written by a GZreader before this one, it's the newer).
--- Returns true when the settings still held some (they're moved at the next save).
function Secrets.load(store)
    if type(store) ~= "table" or not Secrets.active() then return false end
    local in_settings = next(collect(store, false)) ~= nil
    local f = io.open(Secrets.path(), "r")
    if f then
        local text = f:read("*a")
        f:close()
        local chunk = loadstring(text, "=secrets")
        if chunk and text:sub(1, 1) ~= "\27" then
            setfenv(chunk, {})
            local ok, values = pcall(chunk)
            if ok and type(values) == "table" then
                Secrets.written = text
                local have = collect(store, false)
                local missing = {}
                for k, v in pairs(values) do if have[k] == nil then missing[k] = v end end
                Secrets.restore(store, missing)
            end
        end
    end
    return in_settings
end

--- After the first save that moved them: the settings' backup copy (.old)
--- held them too. Overwritten with the file just written, and the recent
--- part's files (written before the move) removed.
function Secrets.cleanBackups(settings_file, recent_file)
    if not Secrets.active() then return end
    local f = settings_file and io.open(settings_file, "rb")
    if f then
        local text = f:read("*a")
        f:close()
        local o = io.open(settings_file .. ".old", "rb")
        if o then
            o:close()
            local w = io.open(settings_file .. ".old", "wb")
            if w then w:write(text); w:close() end
        end
    end
    if recent_file then
        os.remove(recent_file)
        os.remove(recent_file .. ".old")
    end
end

--- Where a background process keeps fresh Grimmory tokens until saved (gzreader_api.lua).
function Secrets.pendingDir()
    if Secrets.active() then return Secrets.DIR end
    return settingsDir()
end

return Secrets
