--[[--
GZreader remote-debugging watchdog: a small separate LuaJIT process.

Started by gzreader_remote.lua (run from the koreader folder):
  ./luajit plugins/gzreader.koplugin/gzreader_watchdog.lua <dir> <koreader pid>

<dir> holds:
  config        line 1: feed base URL (…/open/feed/<id>), line 2: device name
  heartbeat     "<epoch> <run|sleep|exit> <what GZreader is doing>", rewritten
                by GZreader every 15 s
  spool/        messages GZreader wants sent: <n>-send.json, <n>-state.json,
                <n>-resolve.json (the request body, ready to POST)
  watchdog.pid

Every few seconds it sends what's in spool/ (kept until sent, e.g. while
Wi-Fi is off), and watches GZreader:
- heartbeat older than STALL seconds while running: GZreader (or the whole
  Kindle) is unresponsive. It sends an alert with what's on the Kindle right
  then (memory, load, processes, the end of the log) and opens a "frozen"
  state, resolved when GZreader answers again.
- the GZreader process gone without a clean exit: a crash. It sends the end
  of crash.log and of GZreader's log, then exits.
Being its own process, it keeps working while GZreader's screen is stuck.
A frozen kernel or a dead battery stops it too; GZreader then reports the
previous run's end when it starts again.
]]

local dir, ppid = arg[1], tonumber(arg[2])
if not dir or not ppid then
    io.stderr:write("usage: gzreader_watchdog.lua <dir> <pid>\n")
    os.exit(1)
end
pcall(require, "setupkoenv")
local okh, http = pcall(require, "socket.http")
local ltn12 = require("ltn12")
local socket_ok, socket = pcall(require, "socket")

local W = { STALL = tonumber(os.getenv("GZ_WD_STALL")) or 120, TICK = tonumber(os.getenv("GZ_WD_TICK")) or 5,
    LOG = "gzreader.log", CRASH = "crash.log" }

local function now() return os.time() end
local function sleep(s)
    if socket_ok and socket.sleep then socket.sleep(s) else os.execute("sleep " .. tostring(s)) end
end
local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end
local function writeFile(p, s)
    local f = io.open(p .. ".tmp", "wb")
    if not f then return false end
    f:write(s)
    f:close()
    return os.rename(p .. ".tmp", p)
end
local function tail(p, n, max_chars)
    local s = readFile(p)
    if not s then return "" end
    local lines = {}
    for line in s:gmatch("[^\n]+") do
        lines[#lines + 1] = line
        if #lines > n then table.remove(lines, 1) end
    end
    local out = table.concat(lines, "\n")
    if max_chars and #out > max_chars then out = out:sub(-max_chars) end
    return out
end
local function sh(cmd, max_chars)
    local p = io.popen(cmd .. " 2>/dev/null")
    if not p then return "" end
    local s = p:read("*a") or ""
    p:close()
    if max_chars and #s > max_chars then s = s:sub(1, max_chars) end
    return s
end

local function jstr(s)
    s = tostring(s or "")
    s = s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\"
        elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" elseif c == "\r" then return "" end
        return string.format("\\u%04x", c:byte())
    end)
    return '"' .. s .. '"'
end
local function body(t)
    local parts = {}
    for _i, k in ipairs({ "eventId", "eventName", "eventContent", "source" }) do
        if t[k] then parts[#parts + 1] = jstr(k) .. ":" .. jstr(t[k]) end
    end
    local tags = {}
    for _i, tag in ipairs(t.tags or {}) do tags[#tags + 1] = jstr(tag) end
    parts[#parts + 1] = '"tags":[' .. table.concat(tags, ",") .. "]"
    parts[#parts + 1] = '"important":' .. (t.important and "true" or "false")
    return "{" .. table.concat(parts, ",") .. "}"
end

---------------------------------------------------------------- config & spool

local function config()
    local s = readFile(dir .. "/config") or ""
    local base, device = s:match("^([^\n]*)\n?([^\n]*)")
    return base ~= "" and base or nil, (device and device ~= "") and device or "Kindle"
end

local seq = 0
local function spool(kind, t)
    seq = seq + 1
    local name = string.format("%s/spool/%d%04d-w-%s.json", dir, now(), seq % 10000, kind)
    writeFile(name, body(t))
end

local ENDPOINT = { send = "/send", state = "/state/upsert", resolve = "/state/resolve" }

local function post(url, payload)
    if not okh then return false end
    http.TIMEOUT = 20
    local sink = {}
    local ok, code = pcall(function()
        local c = select(2, http.request{
            url = url, method = "POST",
            headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#payload) },
            source = ltn12.source.string(payload), sink = ltn12.sink.table(sink),
        })
        return c
    end)
    code = ok and tonumber(code) or nil
    return code ~= nil, code
end

local function flush()
    local base = config()
    if not base then return end
    local names = {}
    for line in io.popen('ls "' .. dir .. '/spool" 2>/dev/null'):lines() do
        if line:match("%.json$") then names[#names + 1] = line end
    end
    table.sort(names)
    -- don't let a long time offline fill the storage
    while #names > 300 do os.remove(dir .. "/spool/" .. table.remove(names, 1)) end
    for _i, name in ipairs(names) do
        local kind = name:match("%-(%a+)%.json$")
        local payload = readFile(dir .. "/spool/" .. name)
        if payload and ENDPOINT[kind] then
            local reached, code = post(base .. ENDPOINT[kind], payload)
            if not reached then return end -- offline: try again later
            if code and code >= 500 then return end
            os.remove(dir .. "/spool/" .. name) -- sent (or rejected for good: 4xx)
        else
            os.remove(dir .. "/spool/" .. name)
        end
    end
end

---------------------------------------------------------------- diagnostics

local function alive(pid) return io.open("/proc/" .. pid .. "/stat", "rb") ~= nil end

local function heartbeat()
    local s = readFile(dir .. "/heartbeat") or ""
    local t, status, what = s:match("^(%d+) (%a+) ?(.*)$")
    return tonumber(t), status, what
end

local function snapshot()
    local mem = sh("head -5 /proc/meminfo", 400)
    local load = sh("cat /proc/loadavg", 100)
    local top = sh("top -b -n 1 | head -15", 1500)
    if top == "" then top = sh("ps", 1500) end
    local kr = sh("grep -E 'VmRSS|VmSize' /proc/" .. ppid .. "/status", 200)
    local dmesg = sh("dmesg | tail -15", 1500)
    return table.concat({
        "Memory:\n" .. mem, "Load: " .. load, "GZreader process:\n" .. kr,
        "Top:\n" .. top, "Kernel messages:\n" .. dmesg,
        "End of gzreader.log:\n" .. tail(W.LOG, 25, 2500),
    }, "\n")
end

---------------------------------------------------------------- main loop

local own_pid = (readFile("/proc/self/stat") or ""):match("^(%d+)")
writeFile(dir .. "/watchdog.pid", tostring(own_pid or "") .. "\n")
local device = select(2, config())
local frozen_since, last_loop = nil, now()
local function tagged(extra) local t = { "gzreader", device } for _i, x in ipairs(extra) do t[#t + 1] = x end return t end
local state_id = "gzreader-frozen-" .. device:gsub("[^%w%-]", "-")

while true do
    local t = now()
    if t - last_loop > W.TICK * 6 then
        -- the Kindle was asleep (everything stops): not a freeze
        frozen_since = nil
    end
    last_loop = t
    if not alive(ppid) then
        local status, what = select(2, heartbeat())
        if status ~= "exit" then
            spool("send", { eventName = "GZreader crashed (" .. device .. ")", important = true, source = "gzreader",
                tags = tagged({ "crash" }),
                eventContent = "The GZreader process ended without closing normally. It was: " .. tostring(what) ..
                    "\n\nEnd of crash.log:\n" .. tail(W.CRASH, 30, 2500) .. "\n\nEnd of gzreader.log:\n" .. tail(W.LOG, 25, 2000) })
        end
        if frozen_since then spool("resolve", { eventId = state_id, source = "gzreader" }) end
        -- send it (Wi-Fi may still be up for a moment), then stop
        for _i = 1, 12 do
            flush()
            local left = io.popen('ls "' .. dir .. '/spool" 2>/dev/null'):read("*a")
            if not left or left == "" then break end
            sleep(5)
        end
        os.remove(dir .. "/watchdog.pid")
        os.exit(0)
    end
    local hb, status, what = heartbeat()
    if status == "run" and hb then
        local stale = t - hb
        if stale > W.STALL and not frozen_since then
            frozen_since = hb
            local content = string.format("GZreader hasn't responded for %d s. It was: %s\n\n%s", stale, tostring(what), snapshot())
            spool("send", { eventName = "Kindle unresponsive (" .. device .. ")", important = true, source = "gzreader",
                tags = tagged({ "freeze" }), eventContent = content })
            spool("state", { eventId = state_id, eventName = "GZreader unresponsive (" .. device .. ")", important = true,
                source = "gzreader", tags = tagged({ "freeze" }), eventContent = content })
        elseif stale <= W.STALL and frozen_since then
            local secs = t - frozen_since
            frozen_since = nil
            spool("send", { eventName = "Kindle responsive again (" .. device .. ")", source = "gzreader",
                tags = tagged({ "freeze" }), eventContent = string.format("GZreader answered again after about %d s. Now: %s", secs, tostring(what)) })
            spool("resolve", { eventId = state_id, source = "gzreader" })
        end
    end
    flush()
    sleep(W.TICK)
end
