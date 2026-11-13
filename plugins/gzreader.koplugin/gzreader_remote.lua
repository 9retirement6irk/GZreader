--[[--
Remote debugging: GZreader reports to the developer's feed (Tianji
/open/feed/<id>/send and /state/upsert) so problems are visible even when
the Kindle can't be reached afterwards.

On with "Send debug reports automatically" (Settings → About, or the
setup guide's Debug Reports page; off unless chosen), on Kindles with
Wi-Fi. (Until 1.28.1 it came with Full usage statistics; GZreader sends no
usage statistics since: R.setting carries a Full choice over.) Releases report to one feed,
test builds (a version like 1.26.7-beta.abc1234) to another. GZ_REMOTE_FEED
(environment) points it elsewhere, for the emulator's feed.py.

What is sent (log lines are already redacted: no passwords or tokens):
- "started": version, battery, free memory, how the previous run ended;
- after a run that ended without closing normally (hard reboot, battery
  ran out, crash, freeze): what GZreader was doing last, and the end of the
  previous run's log and of crash.log;
- warnings and errors from GZreader's log, gathered for a minute;
- from the watchdog (gzreader_watchdog.lua, its own process): "unresponsive"
  when GZreader's screen hasn't answered for 2 minutes (with memory, load,
  processes and the log at that moment), "responsive again", and "crashed".

Messages wait in a folder and are sent by the watchdog when Wi-Fi is on;
GZreader never turns Wi-Fi on for them.

Diagnostics → Send to the developer (R.sendLogs) sends the whole diagnostic
log at once, with what the user typed about what happened, to its own feed
(R.REPORT_FEED, for releases and test builds alike), whether automatic
reports are on or not.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local UIManager = require("ui/uimanager")
local JSON = require("gzreader_json")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local R = {
    HEARTBEAT = 15, BATCH = 60, seq = 0,
    -- The 15 s beat goes to LIVE_DIR (a RAM disk on Kindles: no flash write);
    -- <dir>/heartbeat, on the Kindle's own storage, only when the status
    -- changes (run, sleep, exit, off) and every KEEP seconds, so that after a
    -- hard reboot the next start can still say roughly when it was last seen.
    LIVE_DIR = "/tmp", KEEP = 600,
    FEED = "https://in.wxcyber.com/open/feed/cmvtvoj3j1dpb5zr7b1dj3zen", -- releases
    TEST_FEED = "https://in.wxcyber.com/open/feed/cmw79imiu09sx8o2f27uihqar", -- test builds
    -- Diagnostics → Send to the developer (releases and test builds alike)
    REPORT_FEED = "https://in.wxcyber.com/open/feed/cmw7f51fm0e318o2f94o54020",
    PART = 60 * 1024, -- a diagnostic log is sent in parts of this size…
    MAX_PARTS = 8, -- …at most this many (its newest part)
}

function R.dir()
    local d = DataStorage:getDataDir() .. "/gzreader-remote"
    lfs.mkdir(d)
    lfs.mkdir(d .. "/spool")
    return d
end

--- "https://…/open/feed/<id>" from what the user gave (with or without /send).
function R.normalize(url)
    if type(url) ~= "string" then return nil end
    url = url:gsub("^%s+", ""):gsub("%s+$", "")
    url = url:gsub("/state/upsert/?$", ""):gsub("/state/resolve/?$", ""):gsub("/send/?$", ""):gsub("/+$", "")
    if not url:match("^https?://[^/]+/.+") then return nil end
    return url
end

function R.version()
    local ok, v = pcall(function() return require("gzreader_update").currentVersion() end)
    return ok and v or "0.0.0"
end

--- A test build: a version with something after the number (1.26.7-beta.abc1234).
function R.testBuild(version)
    version = tostring(version or R.version()):gsub("^v", "")
    local rest = version:match("^%d[%d%.]*%d(.*)$")
    return rest ~= nil and rest ~= ""
end

--- The feed this build reports to.
function R.feedUrl(version)
    local env = os.getenv("GZ_REMOTE_FEED")
    if env and R.normalize(env) then return R.normalize(env) end
    return R.testBuild(version) and R.TEST_FEED or R.FEED
end

--- The feed Send to the developer posts to (GZ_REMOTE_FEED: the emulator's).
function R.reportUrl()
    local env = os.getenv("GZ_REMOTE_FEED")
    if env and R.normalize(env) then return R.normalize(env) end
    return R.REPORT_FEED
end

R.SETTING = "gzreader_debug_reports"

--- Send debug reports automatically? (the user's choice; off unless chosen.
--- Until 1.28.1 they came with Full usage statistics, "gzreader_usage" =
--- "full": that choice carries over.)
function R.setting()
    local gs = G_reader_settings
    if not gs then return false end
    local v = gs:readSetting(R.SETTING)
    if v == nil then return gs:readSetting("gzreader_usage") == "full" end
    return v == true
end

--- Kindles without Wi-Fi (Kindle 2, DX) can't: the watchdog could never send.
function R.possible()
    local okn, Net = pcall(require, "gzreader_net")
    return not (okn and Net.usb)
end

--- On: chosen, on a Kindle with Wi-Fi.
function R.enabled()
    return R.possible() and R.setting()
end

--- The user's choice (Settings, the setup guide): starts or stops at once.
function R.setSetting(on)
    G_reader_settings:saveSetting(R.SETTING, on == true)
    G_reader_settings:delSetting("gzreader_usage") -- (the old levels: usage statistics are gone)
    Log.info("debug reports:", on == true and "on" or "off")
    R.apply()
end

--- What it sends (the Settings item's help, the setup guide's page).
R.WHAT_IS_SENT = require("gettext")("When GZreader starts, how the previous run ended; warnings and errors from its log; freezes and crashes. Sent to the developer only while Wi-Fi is on. Log lines can name the book or file GZreader was working on; never passwords or tokens.")

--- Settings → About: "Send debug reports automatically" (nil on a Kindle
--- without Wi-Fi: Send diagnostic log to the developer still works there,
--- at the next sync).
function R.menuItem()
    if not R.possible() then return nil end
    local _ = require("gettext")
    return {
        text = _("Send debug reports automatically"),
        help_text = R.WHAT_IS_SENT,
        checked_func = function() return R.setting() end,
        callback = function() R.setSetting(not R.setting()) end,
        separator = true,
    }
end

--- GZreader's usage statistics (until 1.28.1): their queue and the old level
--- are deleted once. The random ID stays: it names this Kindle in reports.
function R.forgetUsage()
    local gs = G_reader_settings
    if gs and gs:readSetting(R.SETTING) == nil and gs:readSetting("gzreader_usage") ~= nil then
        gs:saveSetting(R.SETTING, gs:readSetting("gzreader_usage") == "full")
    end
    if gs then gs:delSetting("gzreader_usage") end
    local d = DataStorage:getDataDir() .. "/gzreader-usage"
    if lfs.attributes(d, "mode") == "directory" then
        for name in lfs.dir(d) do
            if name ~= "." and name ~= ".." then os.remove(d .. "/" .. name) end
        end
        os.remove(d)
    end
end

--- A random ID for this Kindle (not its serial number), made once.
function R.id()
    local gs = G_reader_settings
    local id = gs and gs:readSetting("gzreader_usage_id") -- (the key it had with usage statistics)
    if type(id) == "string" and #id == 32 then return id end
    local f = io.open("/dev/urandom", "rb")
    local bytes = f and f:read(16) or tostring(os.time()) .. tostring(math.random())
    if f then f:close() end
    id = (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end)):sub(1, 32)
    if gs then gs:saveSetting("gzreader_usage_id", id) end
    return id
end

local function writeFile(p, s)
    local f = io.open(p .. ".tmp", "wb")
    if not f then return false end
    f:write(s)
    f:close()
    return os.rename(p .. ".tmp", p)
end

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

---------------------------------------------------------------- messages

--- Queue a message. kind: "send" (event), "state" (upsert), "resolve".
function R.queue(kind, msg)
    if not R.on then return end
    R.seq = R.seq + 1
    msg.source = msg.source or "gzreader"
    msg.tags = msg.tags or {}
    table.insert(msg.tags, 1, "gzreader")
    table.insert(msg.tags, 2, R.device)
    local ok, body = pcall(JSON.encode, msg)
    if not ok then return end
    writeFile(string.format("%s/spool/%d%04d-m-%s.json", R.dir(), os.time(), R.seq % 10000, kind), body)
end

function R.event(name, content, tags, important)
    R.queue("send", { eventName = name .. " (" .. R.device .. ")", eventContent = content, tags = tags, important = important == true })
end

---------------------------------------------------------------- the device

local function battery()
    local ok, pct = pcall(function() return Device:getPowerDevice():getCapacity() end)
    return ok and pct or "?"
end

local function memFree()
    local s = readFile("/proc/meminfo") or ""
    local free = tonumber(s:match("MemFree:%s+(%d+)")) or 0
    local cached = tonumber(s:match("\nCached:%s+(%d+)")) or 0
    local rss = tonumber((readFile("/proc/self/status") or ""):match("VmRSS:%s+(%d+)"))
    return string.format("%d MB free (+%d MB cache), GZreader uses %s MB", math.floor(free / 1024),
        math.floor(cached / 1024), rss and tostring(math.floor(rss / 1024)) or "?")
end
R.memFree = memFree

local function tail(p, n)
    local s = readFile(p)
    if not s then return "" end
    local lines = {}
    for line in s:gmatch("[^\n]+") do
        lines[#lines + 1] = line
        if #lines > n then table.remove(lines, 1) end
    end
    return table.concat(lines, "\n")
end

--- What GZreader is doing, for the heartbeat.
function R.activity()
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok_r and ReaderUI.instance
    local what
    if ui and ui.document then
        local name = (ui.document.file or ""):match("([^/]+)$") or "?"
        local page = ui.view and ui.view.state and ui.view.state.page
        what = "reading " .. name .. (page and (" p." .. page) or "")
    else
        local top = UIManager._window_stack and UIManager._window_stack[#UIManager._window_stack]
        local w = top and top.widget
        what = "on Home" .. (w and w.name and (" (" .. tostring(w.name) .. ")") or "")
    end
    local ok_d, Download = pcall(require, "gzreader_download")
    if ok_d and Download.active then what = what .. ", downloading " .. tostring(Download.active.title) end
    local ok_a, Audiobook = pcall(require, "gzreader_audiobook")
    if ok_a and Audiobook.active_prepare then what = what .. ", preparing an audiobook" end
    return (what:gsub("[\n\r]", " "))
end

local function myPid()
    if not R.pid then R.pid = tonumber((readFile("/proc/self/stat") or ""):match("^(%d+)")) end
    return R.pid
end

--- The 15 s beat's file, for GZreader's process pid (also the watchdog's).
function R.livePath(pid) return string.format("%s/gzreader-heartbeat.%s", R.LIVE_DIR, tostring(pid or myPid())) end

function R.beat(status)
    if not R.on then return end
    status = status or "run"
    local cpu = R.trace and R.trace.cpu
    local ui = R.trace and R.trace.uiState and ("; " .. R.trace.uiState() .. "; on screen: " .. R.trace.windows()) or ""
    local now = os.time()
    local line = string.format("%d %s %s%s%s", now, status, R.activity(),
        cpu and string.format(" (CPU %d%%)", cpu) or "", (ui:gsub("[\n\r]", " ")))
    local live_ok = myPid() and writeFile(R.livePath(), line)
    if not live_ok or status ~= R.kept_status or now - (R.kept_at or 0) >= R.KEEP then
        writeFile(R.dir() .. "/heartbeat", line)
        R.kept_status, R.kept_at = status, now
    end
end

--- The newest beat a previous run left (the kept one or a live one, if this
--- Kindle didn't restart since); the live files are removed.
function R.previousBeat(dir)
    local best = readFile(dir .. "/heartbeat")
    local best_t = tonumber((best or ""):match("^(%d+)")) or -1
    local me = tostring(myPid())
    pcall(function()
        for name in lfs.dir(R.LIVE_DIR) do
            local pid = name:match("^gzreader%-heartbeat%.(%d+)$")
            if pid and pid ~= me then
                local p = R.LIVE_DIR .. "/" .. name
                local s = readFile(p)
                local t = tonumber((s or ""):match("^(%d+)"))
                if t and t > best_t then best, best_t = s, t end
                os.remove(p)
            end
        end
    end)
    return best
end

---------------------------------------------------------------- watchdog

local function watchdogRunning()
    local pid = tonumber((readFile(R.dir() .. "/watchdog.pid") or ""):match("(%d+)"))
    if not pid then return false end
    local cmd = readFile("/proc/" .. pid .. "/cmdline") or ""
    return cmd:find("gzreader_watchdog", 1, true) ~= nil
end

function R.startWatchdog(plugin_path)
    if watchdogRunning() then return end
    local pid = (readFile("/proc/self/stat") or ""):match("^(%d+)")
    if not pid then return end
    local Audiobook = require("gzreader_audiobook")
    local script = (plugin_path or "plugins/gzreader.koplugin") .. "/gzreader_watchdog.lua"
    local q = function(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
    os.execute(string.format("(nice -n 5 %s %s %s %s %s >/dev/null 2>&1 &) >/dev/null 2>&1",
        Audiobook.luajit(), q(script), q(R.dir()), pid, q(R.LIVE_DIR)))
    Log.info("remote debugging: watchdog started")
end

---------------------------------------------------------------- start

--- "Kindle3-1a2b3c": the model and the start of this Kindle's random ID
--- (not the serial number), so reports from two Kindles can be told apart.
function R.deviceName()
    local model = tostring(Device.model or "Kindle"):gsub("%s", "")
    local ok, id = pcall(R.id)
    id = ok and type(id) == "string" and id:gsub("[^%w]", ""):sub(1, 6) or ""
    return id ~= "" and (model .. "-" .. id) or model
end

--- Once per run (from the first GZreader instance).
function R.start(plugin)
    if R.started then return end
    R.started = true
    R.plugin = plugin
    local store = plugin.store
    -- (up to 1.26.7 the feed was set by hand: Settings → Remote debugging)
    if store.remote_url or store.remote_disabled or store.remote_profile or store.remote_device then
        store.remote_url, store.remote_disabled, store.remote_profile, store.remote_device = nil, nil, nil, nil
        pcall(plugin.save, plugin)
    end
    if not R.enabled() then return end
    R.on = true
    R.device = R.deviceName()
    local dir = R.dir()
    -- how did the previous run end?
    local prev = R.previousBeat(dir)
    local t, status, what = (prev or ""):match("^(%d+) (%a+) ?(.*)$")
    local version = R.version()
    writeFile(dir .. "/config", R.feedUrl(version) .. "\n" .. R.device .. "\n")
    local how = "first start with remote debugging"
    if status == "exit" then how = "closed normally"
    elseif status == "sleep" then how = "it was asleep (battery ran out or restarted while asleep)"
    elseif status == "run" then how = "it didn't close normally (hard reboot, battery, freeze or crash)" end
    R.event("GZreader " .. version .. " started",
        string.format("Battery %s%%, %s.\nPrevious run: %s%s.", battery(), memFree(), how,
            t and (", last seen " .. os.date("%Y-%m-%d %H:%M:%S", tonumber(t)) .. " " .. tostring(what)) or ""),
        { "start" }, false)
    if status == "run" then
        local crash = readFile("crash.log") and tail("crash.log", 30) or ""
        R.event("Previous run ended unexpectedly",
            string.format("Last seen %s, %s.\n\nEnd of the previous log:\n%s\n\nEnd of crash.log:\n%s",
                os.date("%Y-%m-%d %H:%M:%S", tonumber(t)), tostring(what),
                tail(DataStorage:getDataDir() .. "/gzreader.log.prev", 40), crash),
            { "unclean" }, true)
    end
    os.remove(DataStorage:getDataDir() .. "/gzreader.log.prev")
    R.beat("run")
    R.startWatchdog(plugin.path)
    -- heartbeat (the watchdog's "is it still answering?")
    -- where the time goes when GZreader is slow
    local okt, Trace = pcall(require, "gzreader_slowtrace")
    if okt then
        R.trace = Trace
        pcall(Trace.install, dir, {})
    end
    local function tick()
        if R.trace then
            pcall(R.trace.tick, function(text) R.event("GZreader busy", text, { "busy" }, true) end)
            pcall(R.trace.checkStuck, function(text) R.event("Screen not answering keys", text, { "freeze" }, false) end)
        end
        R.beat("run")
        UIManager:scheduleIn(require("gzreader_ticks").untilNext(R.HEARTBEAT), tick)
    end
    -- (on the quarter minutes, with GZreader's other timers: gzreader_ticks.lua)
    UIManager:scheduleIn(require("gzreader_ticks").untilNext(R.HEARTBEAT), tick)
    -- a normal close
    if not R.quit_patched then
        R.quit_patched = true
        local orig_quit = UIManager.quit
        UIManager.quit = function(...)
            pcall(R.beat, "exit")
            return orig_quit(...)
        end
    end
    -- warnings and errors from the log, a minute's worth at a time
    Log.on_line = function(level, line)
        R.pending = R.pending or {}
        if #R.pending < 40 then R.pending[#R.pending + 1] = line:gsub("\n$", "") end
        R.pending_err = R.pending_err or level == "ERROR"
        if not R.batch_scheduled then
            R.batch_scheduled = true
            UIManager:scheduleIn(R.BATCH, function()
                R.batch_scheduled = false
                local lines = R.pending or {}
                R.pending = nil
                local important = R.pending_err
                R.pending_err = nil
                if #lines > 0 then
                    R.event(#lines .. (important and " error(s) and warning(s)" or " warning(s)"),
                        table.concat(lines, "\n"), { important and "error" or "warning" }, important)
                end
            end)
        end
    end
end

--- Remote debugging turned off: nothing more is sent, the queued messages
--- are dropped and the watchdog stops (up to 1.2.8 it kept running, and
--- reported the next restart as a crash).
function R.stop()
    if not R.on then return end
    R.on = false
    Log.on_line = nil
    writeFile(R.dir() .. "/heartbeat", string.format("%d off", os.time()))
    R.kept_status = "off"
    os.remove(R.livePath())
    local spool = R.dir() .. "/spool"
    pcall(function()
        for name in lfs.dir(spool) do
            if name:match("%.json$") then os.remove(spool .. "/" .. name) end
        end
    end)
    Log.info("remote debugging: off")
end

--- Keep the previous run's log tail for the report above (called before the
--- log is written to in a new run).
function R.keepPreviousLog()
    local d = DataStorage:getDataDir()
    local s = readFile(d .. "/gzreader.log")
    if s then writeFile(d .. "/gzreader.log.prev", s:sub(-20000)) end
end

function R.onSuspend() if R.on then R.beat("sleep") end end
function R.onResume() if R.on then R.beat("run"); R.startWatchdog() end end

---------------------------------------------------------------- settings

--- The choice changed: start or stop.
function R.apply()
    if R.enabled() then
        if not R.on and R.plugin then R.started = false; R.start(R.plugin) end
    else
        R.stop()
    end
end

--- Diagnostics → Send to the developer: the diagnostic log (as saved for
--- USB: GZreader's log, crash.log's end, what keeps the Kindle awake) in
--- events of PART bytes, its newest MAX_PARTS, to R.REPORT_FEED. `note`: what
--- the user typed (what they were doing, what went wrong), at the top of the
--- first event and in its name. Returns the number of parts sent, or nil,
--- error. `post(url, body)` → HTTP code (tests); else LuaSocket.
function R.sendLogs(path, note, post)
    local s = readFile(path)
    if not s or s == "" then return nil, "no log" end
    local version = R.version()
    local url = R.reportUrl() .. "/send"
    local device = R.device or R.deviceName()
    local total = #s
    local function lead(i) -- (never in the middle of a UTF-8 character)
        while i <= total do
            local b = s:byte(i)
            if b < 0x80 or b >= 0xC0 then break end
            i = i + 1
        end
        return i
    end
    local first = lead(math.max(1, total - R.PART * R.MAX_PARTS + 1))
    local parts = {}
    local i = first
    while i <= total do
        local j = lead(i + R.PART)
        parts[#parts + 1] = s:sub(i, j - 1)
        i = j
    end
    post = post or function(u, body)
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        socketutil:set_timeout(20, 60)
        local ok, code = pcall(function()
            return select(2, http.request{
                url = u, method = "POST",
                headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body),
                    ["User-Agent"] = "GZreader/" .. version },
                source = ltn12.source.string(body), sink = ltn12.sink.null(),
            })
        end)
        socketutil:reset_timeout()
        return ok and tonumber(code) or nil
    end
    -- (what the user typed: passwords or tokens in it are redacted like the log's)
    note = type(note) == "string" and Log.redact(note):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local head = string.format("GZreader %s on %s, %s. %s\n\nWhat happened: %s", version, device, os.date("%Y-%m-%d %H:%M"),
        first > 1 and string.format("The last %d KB of %d KB of the log.", math.floor((total - first + 1) / 1024), math.floor(total / 1024)) or "",
        note ~= "" and note or "(nothing typed)")
    local summary = note:gsub("%s+", " ")
    if #summary > 80 then summary = (summary:sub(1, 79):match("^(.*) ") or summary:sub(1, 79)) .. "…" end
    for k, part in ipairs(parts) do
        local body = JSON.encode({
            eventName = string.format("Debug report from %s (%d/%d)%s", device, k, #parts,
                (k == 1 and summary ~= "") and (": " .. summary) or ""),
            eventContent = (k == 1 and (head .. "\n\n") or "") .. part,
            tags = { "gzreader", device, "debug-log", R.testBuild(version) and "test-build" or "release",
                note ~= "" and "with-comment" or nil },
            source = "gzreader",
            important = false,
        })
        local code = post(url, body)
        if not code then return nil, "unreachable" end
        if code >= 400 then return nil, "http_" .. code end
    end
    Log.info("debug log sent to the developer:", #parts, "part(s)")
    return #parts
end

return R
