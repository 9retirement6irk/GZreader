--[[--
Usage statistics, sent to GZreader's Tianji server (application tracking,
tianji.dev/docs/application/tracking: POST /api/application/batch).

Settings → GZreader → Usage statistics:
- Basic (default): GZreader starts (version, device, firmware), whether the
  previous run ended without closing normally, downloads (done or failed),
  slow operations and keys the screen didn't answer.
- Full: also time spent on Home, Downloads, Grimmory, in books and menus,
  which menu entries are used, reading sessions (format, picture book or
  not, minutes, pages, pages per minute, battery use per hour), read aloud,
  download size, speed and resumes, how syncs with Grimmory go (count,
  failures, time), and how long Wi-Fi is on.
- Off: nothing is recorded or sent.

Never sent: book titles, authors, file names, your Grimmory address or
account, anything you type. Each Kindle has a random ID (not tied to you
or the device's serial number) so its starts can be counted.

Cost on a Kindle 3: recording an event appends one line to a small file;
events are sent in one batch from a background process, at most every 15
minutes and only while Wi-Fi is already on (GZreader never turns Wi-Fi on
for this). The file is capped, so a long time offline can't fill storage.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local U = {
    SERVER = "https://in.wxcyber.com",
    APP = "cmvu6mxme1ke55zr7g6i6kw24",
    SEND_EVERY = 15 * 60,
    SUMMARY_EVERY = 30 * 60,
    TICK = 30,
    MAX_LINES = 400,
    lines = nil,
}

---------------------------------------------------------------- settings

function U.level()
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_usage")
    if v == "off" or v == "full" then return v end
    return "basic"
end

function U.setLevel(v)
    G_reader_settings:saveSetting("gzreader_usage", v)
    if v == "off" then U.dropQueue() end
    Log.info("usage statistics:", v)
end

local function on(full)
    local l = U.level()
    if l == "off" then return false end
    return not full or l == "full"
end
U.on = on

function U.dir()
    local d = DataStorage:getDataDir() .. "/gzreader-usage"
    lfs.mkdir(d)
    return d
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
    if not f then return end
    f:write(s)
    f:close()
    os.rename(p .. ".tmp", p)
end

--- A random ID for this Kindle (not its serial number).
function U.id()
    local id = G_reader_settings:readSetting("gzreader_usage_id")
    if type(id) == "string" and #id == 32 then return id end
    local f = io.open("/dev/urandom", "rb")
    local bytes = f and f:read(16) or tostring(os.time()) .. tostring(math.random())
    if f then f:close() end
    id = (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end)):sub(1, 32)
    G_reader_settings:saveSetting("gzreader_usage_id", id)
    return id
end

local function version()
    return ((readFile("gzreader-version") or "?"):gsub("%s", ""))
end

local function firmware()
    local s = readFile("/etc/prettyversion.txt") or readFile("/etc/version.txt") or ""
    local v = s:match("Kindle ([%d%.]+)") or s:match("^([^\n]*)") or ""
    return v ~= "" and v:sub(1, 30) or "?"
end

local function battery()
    local ok, pct = pcall(function() return Device:getPowerDevice():getCapacity() end)
    return ok and tonumber(pct) or nil
end

local function osName()
    return tostring(Device.model or "Kindle"):gsub("%s", ""):sub(1, 20)
end

---------------------------------------------------------------- the queue

local function queuePath() return U.dir() .. "/queue.jsonl" end

local function countLines()
    if U.lines then return U.lines end
    local n = 0
    local f = io.open(queuePath(), "rb")
    if f then
        for _l in f:lines() do n = n + 1 end
        f:close()
    end
    U.lines = n
    return n
end

local function append(item)
    if U.testing_sink then return U.testing_sink(item) end
    if countLines() >= U.MAX_LINES then return end
    local ok, line = pcall(JSON.encode, item)
    if not ok then return end
    local f = io.open(queuePath(), "ab")
    if not f then return end
    f:write(line, "\n")
    f:close()
    U.lines = U.lines + 1
end

--- Record an event. full = true: only at the Full level.
function U.event(name, data, full)
    if not on(full) then return end
    data = data or {}
    data.install = U.id()
    data.version = data.version or version()
    data.level = U.level()
    append({ type = "event", payload = {
        application = U.APP, name = tostring(name):sub(1, 50), data = data,
        screen = U.screen, os = osName(), language = "en",
    } })
    if countLines() >= 50 then UIManager:scheduleIn(5, U.maybeSend) end
end

function U.identify()
    if not on() then return end
    append({ type = "identify", payload = { application = U.APP, os = osName(), language = "en", data = {
        id = U.id(), version = version(), device = osName(), firmware = firmware(),
        level = U.level(), sdkVersion = "gzreader",
    } } })
end

function U.dropQueue()
    os.remove(queuePath())
    U.lines = 0
    for name in lfs.dir(U.dir()) do
        if name:match("^sending%-") then os.remove(U.dir() .. "/" .. name) end
    end
end

---------------------------------------------------------------- sending

--- Send what's queued: in a background process, only while Wi-Fi is on.
function U.maybeSend(force)
    if U.sending or not on() then return end
    local okn, Net = pcall(require, "gzreader_net")
    if not okn or not Net.connected() then return end
    if not force and os.time() - (U.last_send or 0) < U.SEND_EVERY and countLines() < 50 then return end
    local dir = U.dir()
    if countLines() > 0 then
        os.rename(queuePath(), string.format("%s/sending-%d.jsonl", dir, os.time()))
        U.lines = 0
    end
    local files = {}
    for name in lfs.dir(dir) do
        if name:match("^sending%-.*%.jsonl$") then files[#files + 1] = dir .. "/" .. name end
    end
    if #files == 0 then return end
    table.sort(files)
    U.sending = true
    U.last_send = os.time()
    Net.hold("usage")
    local ffiutil = require("ffi/util")
    local server = U.SERVER
    local agent = "GZreader/" .. version() .. " (" .. osName() .. ")"
    local pid = ffiutil.runInSubProcess(function()
        local http = require("socket.http")
        local ltn12 = require("ltn12")
        local socketutil = require("socketutil")
        socketutil:set_timeout(20, 60)
        for _i, path in ipairs(files) do
            local items = {}
            local f = io.open(path, "rb")
            if f then
                for line in f:lines() do
                    local okd, item = pcall(JSON.decode, line)
                    if okd and type(item) == "table" then items[#items + 1] = item end
                end
                f:close()
            end
            local sent = true
            for start = 1, #items, 100 do
                local chunk = {}
                for k = start, math.min(#items, start + 99) do chunk[#chunk + 1] = items[k] end
                local body = JSON.encode({ events = chunk })
                local okr, code = pcall(function()
                    return select(2, http.request{
                        url = server .. "/api/application/batch", method = "POST",
                        headers = { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body),
                            ["User-Agent"] = agent },
                        source = ltn12.source.string(body), sink = ltn12.sink.null(),
                    })
                end)
                code = okr and tonumber(code) or nil
                if not code or code >= 500 then sent = false; break end -- offline or server trouble: later
            end
            if not sent then break end
            os.remove(path) -- sent (or refused for good: 4xx)
        end
    end)
    local started = os.time()
    local function poll()
        if pid and not ffiutil.isSubProcessDone(pid) and os.time() - started < 180 then
            return UIManager:scheduleIn(2, poll)
        end
        if pid and not ffiutil.isSubProcessDone(pid) then ffiutil.terminateSubProcess(pid) end
        U.sending = false
        pcall(Net.release, "usage")
    end
    if not pid then
        U.sending = false
        Net.release("usage")
        return
    end
    UIManager:scheduleIn(2, poll)
end

--- Called whenever GZreader used the network (Wi-Fi is on): send soon.
function U.networkUsed()
    if not on() or U.send_scheduled then return end
    U.send_scheduled = true
    UIManager:scheduleIn(10, function()
        U.send_scheduled = false
        U.maybeSend()
    end)
end

---------------------------------------------------------------- run state

local function stateWrite(status)
    writeFile(U.dir() .. "/state", string.format("%d %s %s", os.time(), status, U.activity or "on Home"))
end

---------------------------------------------------------------- aggregates

local agg
local function resetAgg()
    agg = { since = os.time(), slow = 0, slow_max = 0, slow_kinds = {}, screens = {}, wifi = 0, sync = {} }
end
resetAgg()

function U.slow(what, wall)
    if not on() then return end
    agg.slow = agg.slow + 1
    agg.slow_max = math.max(agg.slow_max, wall or 0)
    local k = tostring(what):gsub("^a ", ""):gsub("^scheduled ", "")
    agg.slow_kinds[k] = (agg.slow_kinds[k] or 0) + 1
end

local SYNC_KIND = { flush = "position", pull = "position", bookmarks = "bookmarks", deleteBookmark = "bookmarks",
    annotations = "highlights", ["shelf sync"] = "shelves", ["refresh login"] = "login" }

--- A background request finished (gzreader_async).
function U.request(name, ok, ms)
    if not on(true) then return end
    local kind = SYNC_KIND[name] or "library"
    local s = agg.sync[kind] or { ok = 0, failed = 0, ms = 0 }
    if ok then s.ok = s.ok + 1 else s.failed = s.failed + 1 end
    s.ms = s.ms + (ms or 0)
    agg.sync[kind] = s
end

--- Send the aggregates gathered since the last summary.
function U.summary(reason)
    if not on() then resetAgg(); return end
    local mins = math.floor((os.time() - agg.since) / 60 + 0.5)
    if agg.slow > 0 then
        U.event("slow operations", { count = agg.slow, longest_s = agg.slow_max, kinds = agg.slow_kinds, minutes = mins })
    end
    if on(true) then
        local screens = {}
        local any = false
        for k, v in pairs(agg.screens) do screens[k] = math.floor(v / 60 * 10 + 0.5) / 10; any = true end
        if any then U.event("time on screens", { minutes = screens, wifi_minutes = math.floor(agg.wifi / 60 + 0.5), reason = reason }, true) end
        if next(agg.sync) then
            local sync = {}
            for k, s in pairs(agg.sync) do
                local n = s.ok + s.failed
                sync[k] = { ok = s.ok, failed = s.failed, avg_ms = n > 0 and math.floor(s.ms / n) or 0 }
            end
            U.event("sync", sync, true)
        end
    end
    resetAgg()
end

---------------------------------------------------------------- screens

--- Where the user is now: Home, Downloads, Grimmory, reader, menu, other.
function U.whereNow()
    local stack = UIManager._window_stack or {}
    local top = stack[#stack] and stack[#stack].widget
    local name = top and (top.name or (type(top.title) == "string" and top.title)) or ""
    if top and top._gz_navbar_tab_id then return "grimmory" end
    if name == "ReaderUI" then return "reader" end
    if name == "Menu" or name == "Reading menu" or name == "zen_settings" or name == "Quick panel" then return "menus" end
    if name == "home" then return "home" end
    if name == "filemanager" or name == "KOReader" then return "downloads" end
    return "other"
end

local function tick()
    if on() then
        if on(true) then
            local where = U.whereNow()
            U.screen = where
            agg.screens[where] = (agg.screens[where] or 0) + U.TICK
            local okn, NetworkMgr = pcall(require, "ui/network/manager")
            if okn and NetworkMgr:isWifiOn() then agg.wifi = agg.wifi + U.TICK end
        end
        -- keys the screen didn't answer (also without remote debugging)
        local okt, Trace = pcall(require, "gzreader_slowtrace")
        local okr, R = pcall(require, "gzreader_remote")
        if okt and Trace.installed and not (okr and R.on) then pcall(Trace.checkStuck, function() end) end
        if os.time() - agg.since >= U.SUMMARY_EVERY then U.summary("periodic") end
        U.maybeSend() -- only does something when Wi-Fi is on and it's time
    end
    UIManager:scheduleIn(U.TICK, tick)
end

---------------------------------------------------------------- reading

function U.readStart(ui)
    if not on(true) or not (ui and ui.document) then return end
    local file = ui.document.file or ""
    U.reading = {
        t = os.time(), pages = 0, battery = battery(),
        format = (file:match("%.(%w+)$") or "?"):lower(),
        picture_book = ui.doc_settings and ui.doc_settings:readSetting("gzreader_picture_book") == true or false,
    }
    U.activity = "reading"
    stateWrite("run")
end

function U.pageTurned()
    if U.reading then U.reading.pages = U.reading.pages + 1 end
end

function U.readEnd(reason)
    local r = U.reading
    U.reading = nil
    U.activity = "on Home"
    if not (r and on(true)) then return end
    local secs = os.time() - r.t
    if secs < 30 then return end
    local b = battery()
    local mins = secs / 60
    local drop = (r.battery and b) and (r.battery - b) or nil
    U.event("reading", {
        format = r.format, picture_book = r.picture_book, minutes = math.floor(mins * 10 + 0.5) / 10,
        pages = r.pages, pages_per_minute = math.floor(r.pages / mins * 10 + 0.5) / 10,
        battery_start = r.battery, battery_end = b,
        battery_per_hour = (drop and secs >= 600) and math.floor(drop / secs * 3600 * 10 + 0.5) / 10 or nil,
        reason = reason,
    }, true)
end

function U.ttsStart() U.tts_at = os.time() end
function U.ttsStop()
    if U.tts_at then
        U.event("read aloud", { seconds = os.time() - U.tts_at }, true)
        U.tts_at = nil
    end
end

--- A menu entry was chosen (no book titles: quoted text is dropped).
function U.menu(menu, text)
    if not on(true) or type(text) ~= "string" then return end
    text = text:gsub("“.-”", "…"):gsub("\".-\"", "…"):gsub("%s+%(.-%)$", ""):gsub("%s+", " ")
    U.event("menu", { menu = menu, item = text:sub(1, 60) }, true)
end

--- A book download finished (gzreader_download).
function U.download(info)
    if not on() then return end
    local data = { ok = info.ok == true, error = (not info.ok) and tostring(info.error or "?"):sub(1, 40) or nil,
        kind = info.kind or "book" }
    if on(true) then
        data.kb = info.bytes and math.floor(info.bytes / 1024) or nil
        data.seconds = info.seconds
        data.kb_per_s = (info.bytes and info.seconds and info.seconds > 0) and math.floor(info.bytes / 1024 / info.seconds) or nil
        data.resumed = info.resumed == true
    end
    U.event("download", data)
end

--- Keys arrived but the screen didn't change (gzreader_slowtrace).
function U.stuck(seconds, windows)
    U.event("keys not answered", { seconds = seconds, screen = U.whereNow(), windows = tostring(windows):sub(1, 120) })
end

---------------------------------------------------------------- start / sleep

function U.start()
    if U.started then return end
    U.started = true
    local prev = readFile(U.dir() .. "/state")
    local t, status, what = (prev or ""):match("^(%d+) (%a+) ?(.*)$")
    if not on() then
        U.dropQueue()
    else
        U.identify()
        local previous = status == nil and "first start" or status == "exit" and "closed normally"
            or status == "sleep" and "was asleep" or "ended without closing normally"
        U.event("start", { device = osName(), firmware = firmware(), previous = previous })
        if status == "run" then
            U.event("restart without closing", { last_seen = tonumber(t), was = what ~= "" and what or nil })
        end
    end
    stateWrite("run")
    if not U.quit_patched then
        U.quit_patched = true
        local orig_quit = UIManager.quit
        UIManager.quit = function(...)
            pcall(function()
                U.readEnd("closed")
                U.summary("closed")
                stateWrite("exit")
            end)
            return orig_quit(...)
        end
    end
    UIManager:scheduleIn(U.TICK, tick)
    -- the slow-operation timer (cheap; without the profiler) feeds Basic
    if on() then
        local okt, Trace = pcall(require, "gzreader_slowtrace")
        if okt and not Trace.installed then
            pcall(Trace.install, DataStorage:getDataDir() .. "/gzreader-remote", {})
        end
    end
end

function U.onSuspend()
    pcall(function()
        if U.reading then
            local ui_reading = U.reading
            U.readEnd("sleep")
            U.resume_reading = ui_reading
        end
        U.summary("sleep")
        stateWrite("sleep")
    end)
end

function U.onResume()
    pcall(function()
        stateWrite("run")
        local r = U.resume_reading
        U.resume_reading = nil
        if r and on(true) then
            U.reading = { t = os.time(), pages = 0, battery = battery(), format = r.format, picture_book = r.picture_book }
        end
    end)
end

function U.menuItems()
    local _ = require("gettext")
    local function item(text, value, help)
        return {
            text = text, help_text = help, radio = true,
            checked_func = function() return U.level() == value end,
            callback = function() U.setLevel(value) end,
        }
    end
    return {
        text = _("Usage statistics"),
        sub_item_table = {
            item(_("Basic (starts, downloads, problems)"), "basic",
                _("Sends GZreader's version, the Kindle model and firmware when GZreader starts, whether the last run ended without closing normally, downloads that worked or failed, slow operations, and keys the screen didn't answer. No book titles, file names, account or anything you type.")),
            item(_("Full (also how GZreader is used)"), "full",
                _("Basic, plus: time on Home, Downloads, Grimmory, in books and menus; which menu entries you use; reading sessions (format, picture book or not, minutes, pages, pages per minute, battery use per hour); read aloud; download size and speed; how syncs with Grimmory go; how long Wi-Fi is on. Still no titles, file names or account.")),
            item(_("Off (send nothing)"), "off", _("Nothing is recorded or sent. What was waiting is deleted.")),
        },
        separator = true,
    }
end

return U
