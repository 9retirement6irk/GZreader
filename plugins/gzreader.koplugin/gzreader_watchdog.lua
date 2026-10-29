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
local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")

--- Names in a folder (without starting a shell when lfs is there).
local function listDir(d)
    local out = {}
    if ok_lfs then
        local okd, iter, obj = pcall(lfs.dir, d)
        if okd then for name in iter, obj do if name ~= "." and name ~= ".." then out[#out + 1] = name end end end
        return out
    end
    local p = io.popen('ls "' .. d .. '" 2>/dev/null')
    if p then for line in p:lines() do out[#out + 1] = line end; p:close() end
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
    for _i, line in ipairs(listDir(dir .. "/spool")) do
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

--- /proc/<pid>/stat as { state, ppid, ticks (CPU), nice, name }
local function procStat(pid)
    local s = readFile("/proc/" .. pid .. "/stat")
    if not s then return nil end
    local name, rest = s:match("^%d+ %((.-)%) (.*)$")
    if not rest then return nil end
    local f = {}
    for x in rest:gmatch("%S+") do f[#f + 1] = x end
    return { state = f[1], ppid = tonumber(f[2]), ticks = (tonumber(f[12]) or 0) + (tonumber(f[13]) or 0),
        nice = tonumber(f[17]), name = name }
end

--- GZreader and its helper processes: state, CPU over 2 s, memory, what it waits on.
local function processes()
    local pids = {}
    for _i, line in ipairs(listDir("/proc")) do
        local pid = tonumber(line)
        if pid then
            local st = procStat(pid)
            local cmd = (readFile("/proc/" .. pid .. "/cmdline") or ""):gsub("%z", " ")
            if st and (pid == ppid or st.ppid == ppid or cmd:find("reader.lua", 1, true) or cmd:find("gzreader_", 1, true)) then
                pids[#pids + 1] = { pid = pid, st = st, cmd = cmd }
            end
        end
    end
    local before = {}
    for _i, p in ipairs(pids) do before[p.pid] = p.st.ticks end
    sleep(2)
    local out, zombies = {}, 0
    for _i, p in ipairs(pids) do
        local st = procStat(p.pid) or p.st
        if st.state == "Z" then
            zombies = zombies + 1
        else
            local rss = (readFile("/proc/" .. p.pid .. "/status") or ""):match("VmRSS:%s+(%d+)")
            local wchan = (readFile("/proc/" .. p.pid .. "/wchan") or ""):gsub("%s", "")
            out[#out + 1] = string.format("%d%s %s nice %s, CPU %d%%, %s MB, waits in %s: %s", p.pid,
                p.pid == ppid and " (GZreader)" or (st.ppid == ppid and " (child)" or ""),
                st.state, tostring(st.nice), math.floor((st.ticks - (before[p.pid] or st.ticks)) / 2 + 0.5),
                rss and tostring(math.floor(tonumber(rss) / 1024)) or "?", wchan ~= "" and wchan or "-",
                p.cmd:sub(1, 80))
        end
    end
    if zombies > 0 then out[#out + 1] = zombies .. " finished child process(es) not collected" end
    return table.concat(out, "\n")
end

local function snapshot()
    local mem = sh("head -5 /proc/meminfo", 400)
    local load = sh("cat /proc/loadavg", 100)
    local top = sh("top -b -n 1 | head -12", 1200)
    if top == "" then top = sh("ps", 1200) end
    local dmesg = sh("dmesg | tail -8", 800)
    return table.concat({
        "GZreader's processes (state R = running, S = waiting, D = waiting for storage):\n" .. processes(),
        "Where GZreader's CPU went:\n" .. (readFile(dir .. "/profile") or "(no profile)"),
        "Memory:\n" .. mem, "Load: " .. load, "Top:\n" .. top, "Kernel messages:\n" .. dmesg,
        "End of gzreader.log:\n" .. tail(W.LOG, 20, 2000),
    }, "\n")
end

---------------------------------------------------------------- main loop

local own_pid = (readFile("/proc/self/stat") or ""):match("^(%d+)")
writeFile(dir .. "/watchdog.pid", tostring(own_pid or "") .. "\n")
local device = select(2, config())
local frozen_since, last_loop, slow_reported = nil, now(), 0
W.SLOW = tonumber(os.getenv("GZ_WD_SLOW")) or 45
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
            if #listDir(dir .. "/spool") == 0 then break end
            sleep(5)
        end
        os.remove(dir .. "/watchdog.pid")
        os.exit(0)
    end
    local hb, status, what = heartbeat()
    if status == "run" and hb then
        local stale = t - hb
        if stale > W.SLOW and stale <= W.STALL and not frozen_since and t - slow_reported > 600 then
            slow_reported = t
            spool("send", { eventName = "GZreader slow (" .. device .. ")", important = false, source = "gzreader",
                tags = tagged({ "slow" }), eventContent = string.format(
                    "GZreader hasn't updated its heartbeat for %d s (it should every 15 s). It was: %s\n\n%s",
                    stale, tostring(what), snapshot()) })
        end
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
