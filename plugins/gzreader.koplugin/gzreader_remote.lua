--[[--
Remote debugging: GZreader reports to a feed (Tianji-style
/open/feed/<id>/send and /state/upsert) so problems are visible even when
the Kindle can't be reached afterwards.

Off until a feed address is set: Settings → GZreader → Remote debugging, or
a file `gzreader-remote.txt` on the Kindle's USB drive with the address on
its first line (read when GZreader starts). The address isn't in GZreader's
code: the project is public and anyone with it could post to the feed.

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
]]

local DataStorage = require("datastorage")
local Device = require("device")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local R = { HEARTBEAT = 15, BATCH = 60, seq = 0 }

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

function R.enabled(store)
    return store and store.remote_url ~= nil and store.remote_disabled ~= true
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

function R.beat(status)
    if not R.on then return end
    local cpu = R.trace and R.trace.cpu
    local ui = R.trace and R.trace.uiState and ("; " .. R.trace.uiState() .. "; on screen: " .. R.trace.windows()) or ""
    writeFile(R.dir() .. "/heartbeat", string.format("%d %s %s%s%s", os.time(), status or "run", R.activity(),
        cpu and string.format(" (CPU %d%%)", cpu) or "", (ui:gsub("[\n\r]", " "))))
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
    os.execute(string.format("(nice -n 5 %s %s %s %s >/dev/null 2>&1 &) >/dev/null 2>&1",
        Audiobook.luajit(), q(script), q(R.dir()), pid))
    Log.info("remote debugging: watchdog started")
end

---------------------------------------------------------------- start

--- Read gzreader-remote.txt from the USB drive (first line: the feed address).
function R.importFile(store)
    for _i, p in ipairs({ "/mnt/us/gzreader-remote.txt", (Device.home_dir or "") .. "/../gzreader-remote.txt",
            DataStorage:getDataDir() .. "/gzreader-remote.txt" }) do
        local s = readFile(p)
        local url = s and R.normalize(s:match("^[^\n]*"))
        if url then
            if store.remote_url ~= url then
                store.remote_url = url
                store.remote_disabled = nil
                Log.info("remote debugging: address read from", p)
                return true
            end
            return false
        end
    end
    return false
end

--- Once per run (from the first GZreader instance).
function R.start(plugin)
    if R.started then return end
    R.started = true
    local store = plugin.store
    if R.importFile(store) then plugin:save() end
    if not R.enabled(store) then return end
    R.on = true
    R.device = store.remote_device or (tostring(Device.model or "Kindle"):gsub("%s", ""))
    local dir = R.dir()
    -- how did the previous run end?
    local prev = readFile(dir .. "/heartbeat")
    local t, status, what = (prev or ""):match("^(%d+) (%a+) ?(.*)$")
    writeFile(dir .. "/config", store.remote_url .. "\n" .. R.device .. "\n")
    local version = (readFile("gzreader-version") or "?"):gsub("%s", "")
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
        pcall(Trace.install, dir, { profile = store.remote_profile == true })
    end
    local function tick()
        if R.trace then
            pcall(R.trace.tick, function(text) R.event("GZreader busy", text, { "busy" }, true) end)
            pcall(R.trace.checkStuck, function(text) R.event("Screen not answering keys", text, { "freeze" }, false) end)
        end
        R.beat("run")
        UIManager:scheduleIn(R.HEARTBEAT, tick)
    end
    UIManager:scheduleIn(R.HEARTBEAT, tick)
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

function R.menuItems(plugin)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local store = plugin.store
    return {
        text = _("Remote debugging"),
        sub_item_table = {
            {
                text = _("Send reports to my feed"),
                help_text = _("Sends GZreader's start, crashes, freezes, warnings and errors (no passwords or tokens) to the feed address below, so you can see what happened even when the Kindle had to be hard rebooted."),
                enabled_func = function() return store.remote_url ~= nil end,
                checked_func = function() return R.enabled(store) end,
                callback = function()
                    store.remote_disabled = (store.remote_disabled ~= true) or nil
                    plugin:save()
                    if R.enabled(store) then R.started = false; R.start(plugin) else R.on = false end
                end,
            },
            {
                text_func = function()
                    return store.remote_url and T(_("Feed address: %1"), store.remote_url:match("^https?://([^/]+)") or "?")
                        or _("Set the feed address…")
                end,
                keep_menu_open = true,
                callback = function(touchmenu)
                    local InputDialog = require("ui/widget/inputdialog")
                    local dlg
                    dlg = InputDialog:new{
                        title = _("Feed address (…/open/feed/<id>)"),
                        input = store.remote_url or "https://",
                        buttons = {{
                            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
                            { text = _("Save"), is_enter_default = true, callback = function()
                                local url = R.normalize(dlg:getInputText())
                                UIManager:close(dlg)
                                if not url then return end
                                store.remote_url, store.remote_disabled = url, nil
                                plugin:save()
                                R.started = false
                                R.start(plugin)
                                if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                            end },
                        }},
                    }
                    UIManager:show(dlg)
                    dlg:onShowKeyboard()
                end,
            },
            {
                text = _("Detailed timing (slower)"),
                help_text = _("Also samples where GZreader spends its CPU time (LuaJIT's profiler) and adds it to slow and freeze reports. Off by default: it uses timer signals all the time. Takes effect after a restart."),
                enabled_func = function() return R.enabled(store) end,
                checked_func = function() return store.remote_profile == true end,
                callback = function()
                    store.remote_profile = (store.remote_profile ~= true) or nil
                    plugin:save()
                end,
            },
            {
                text = _("Send a test report"),
                enabled_func = function() return R.enabled(store) end,
                callback = function()
                    R.event("Test report", "Remote debugging works. " .. memFree() .. ", battery " .. battery() .. "%.", { "test" }, false)
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{ text = _("Test report queued: it's sent within a few seconds while Wi-Fi is on."), timeout = 3 })
                end,
            },
        },
    }
end

return R
