--[[--
Usage statistics, sent to GZreader's Tianji server (application tracking,
tianji.dev/docs/application/tracking: POST /api/application/batch).

Settings → General → Usage statistics:
- Basic (default) and Full send the same events (below).
- Full also turns on remote debugging (gzreader_remote.lua): starts,
  how the previous run ended, warnings, errors, freezes and crashes go to
  the developer's feed.
- Off: nothing is recorded or sent.

The events. Every one carries the version, the device, its firmware and
`minutes` (how long it covers), and this Kindle's random ID:
- a visit to a part of GZreader, sent when you leave it (shorter than
  MIN_VISIT seconds: not sent; sleep ends a visit, waking starts one):
  "reader" (a book open: format, picture book or not, pages, pages per
  minute, battery use per hour), "catalog books", "catalog audiobooks", "catalog music" (the
  Catalog tab's pages), "audiobooks tab", "music tab", "notes",
  "calendar". What's open on top (the quick panel, a book's page, the
  player, a note being written) counts as the part underneath;
- "read aloud", "audiobook playing", "music playing": how long it spoke or
  played (pauses and track changes within AUDIO_GAP seconds are one);
- diagnostics: "download" (done or failed, size, speed, resumed), "slow
  operations", "keys not answered", "sync" (Grimmory's answers, Wi-Fi
  on-time), every SUMMARY_EVERY.
Each event's `screen` is the part it's about (Tianji counts screens per
session); `version` is also at the payload's top level, where Tianji reads
it for its Version chart.

Never sent: book titles, authors, file names, your Grimmory address or
account, anything you type. Each Kindle has a random ID (not tied to you
or the device's serial number) so its events can be told apart; its first
8 characters are also in the User-Agent, because Tianji tells sessions
apart by address + User-Agent.

Cost on a Kindle 3: recording an event appends one line to a small file;
events are sent in one batch from a background process, at most every 15
minutes and only while Wi-Fi is already on (GZreader never turns Wi-Fi on
for this). The file is capped, so a long time offline can't fill storage.
Kindles without Wi-Fi hand the waiting files to the sync page (in the
.gzsync folder's usage/ folder, when GZreader steps aside for the USB
drive), which sends them from the computer.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local UIManager = require("ui/uimanager")
local JSON = require("gzreader_json")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local U = {
    SERVER = "https://in.wxcyber.com",
    APP = "cmvu6mxme1ke55zr7g6i6kw24",
    SEND_EVERY = 15 * 60,
    SUMMARY_EVERY = 30 * 60,
    TICK = 30,
    MIN_VISIT = 5,
    AUDIO_GAP = 60,
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
    -- Full also sends the debug reports (gzreader_remote.lua)
    pcall(function() require("gzreader_remote").apply() end)
end

--- Recording at all (Basic and Full record the same events; Full also
--- sends the debug reports: gzreader_remote.lua).
local function on()
    return U.level() ~= "off"
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

--- The firmware (read once: it only changes with a Kindle update, and every
--- event carries it).
local function firmware()
    if U.fw then return U.fw end
    local s = readFile("/etc/prettyversion.txt") or readFile("/etc/version.txt") or ""
    local v = s:match("Kindle ([%d%.]+)") or s:match("^([^\n]*)") or ""
    U.fw = v ~= "" and v:sub(1, 30) or "?"
    return U.fw
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

--- Minutes to one decimal.
local function mins(seconds) return math.floor((seconds or 0) / 60 * 10 + 0.5) / 10 end
U.mins = mins

--- Record an event: every one carries the version, device, firmware and
--- `minutes` (how long it covers; 0 when nothing). `screen`: the part of
--- GZreader it's about (default: where the user is now).
function U.event(name, data, screen)
    if not on() then return end
    data = data or {}
    data.install = U.id()
    data.version = data.version or version()
    data.device = osName()
    data.firmware = firmware()
    data.minutes = tonumber(data.minutes) or 0
    data.level = U.level()
    append({ type = "event", payload = {
        application = U.APP, name = tostring(name):sub(1, 50), data = data,
        screen = screen or U.portion() or U.whereNow(), os = osName(), language = "en",
        -- (Tianji's Version chart reads these here, not from data)
        version = data.version, sdkVersion = "gzreader",
    } })
    if countLines() >= 50 then UIManager:scheduleIn(5, U.maybeSend) end
end

function U.identify()
    if not on() then return end
    append({ type = "identify", payload = { application = U.APP, os = osName(), language = "en",
        version = version(), sdkVersion = "gzreader", data = {
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

--- The User-Agent: Tianji tells sessions apart by address + User-Agent, so
--- it carries the start of the random ID (two Kindles on one Wi-Fi).
function U.agent()
    return "GZreader/" .. version() .. " (" .. osName() .. "; " .. U.id():sub(1, 8) .. ")"
end

--- Syncing through a computer (no Wi-Fi): the sync page sends them.
function U.noWifi()
    local okn, Net = pcall(require, "gzreader_net")
    return okn and Net.usb == true
end

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
    local agent = U.agent()
    local pid = ffiutil.runInSubProcess(function()
        require("gzreader_async").lowerPriority(require("gzreader_async").NICE) -- (page turns first)
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

--- Kindles without Wi-Fi: hand what's waiting to the sync page (it sends
--- it from the computer: Usb.handOverUsage). Moves the waiting files into
--- dest_dir; returns how many were moved.
function U.handOver(dest_dir)
    if not on() or U.sending then return 0 end
    local dir = U.dir()
    if countLines() > 0 then
        os.rename(queuePath(), string.format("%s/sending-%d.jsonl", dir, os.time()))
        U.lines = 0
    end
    local names = {}
    for name in lfs.dir(dir) do
        if name:match("^sending%-.*%.jsonl$") then names[#names + 1] = name end
    end
    if #names == 0 then return 0 end
    if lfs.attributes(dest_dir, "mode") ~= "directory" then lfs.mkdir(dest_dir) end
    local moved = 0
    for _i, name in ipairs(names) do
        local to = dest_dir .. "/" .. name
        local k = 2
        while lfs.attributes(to, "mode") do
            to = dest_dir .. "/" .. name:gsub("%.jsonl$", "") .. "-" .. k .. ".jsonl"
            k = k + 1
        end
        local from = dir .. "/" .. name
        local ok = os.rename(from, to)
        if not ok then
            local text = readFile(from)
            if text then writeFile(to, text); ok = lfs.attributes(to, "mode") == "file" end
            if ok then os.remove(from) end
        end
        if ok then moved = moved + 1 end
    end
    return moved
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

---------------------------------------------------------------- the clock

--- Seconds on a monotonic clock (the Nook's wall clock jumps when it's set).
function U.clock()
    local T = require("ui/time")
    return T.to_s(T.monotonic())
end

---------------------------------------------------------------- aggregates

local agg
local function resetAgg()
    agg = { since = os.time(), slow = 0, slow_max = 0, slow_kinds = {}, wifi = 0, sync = {} }
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
    if not on() then return end
    local kind = SYNC_KIND[name] or "library"
    local s = agg.sync[kind] or { ok = 0, failed = 0, ms = 0 }
    if ok then s.ok = s.ok + 1 else s.failed = s.failed + 1 end
    s.ms = s.ms + (ms or 0)
    agg.sync[kind] = s
end

--- Send the aggregates gathered since the last summary: slow operations;
--- "sync" with Grimmory's answers and Wi-Fi on-time.
function U.summary(reason)
    if not on() then resetAgg(); return end
    local minutes = mins(os.time() - agg.since)
    if agg.slow > 0 then
        U.event("slow operations", { count = agg.slow, longest_s = agg.slow_max, kinds = agg.slow_kinds, minutes = minutes })
    end
    local ev = { minutes = minutes, wifi_minutes = mins(agg.wifi), reason = reason }
    for k, st in pairs(agg.sync) do
        local n = st.ok + st.failed
        ev[k] = { ok = st.ok, failed = st.failed, avg_ms = n > 0 and math.floor(st.ms / n) or 0 }
    end
    if next(agg.sync) or agg.wifi > 0 then U.event("sync", ev) end
    resetAgg()
end

---------------------------------------------------------------- screens

--- Where the user is now: Home, Downloads, Grimmory, reader, menu, other
--- (the top window; "keys not answered" uses it).
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

-- GZreader's tabs (their _gz_navbar_tab_id) and the visit each is
local TAB_PART = { ct_notes = "notes", ct_calendar = "calendar", ct_music = "music tab", ct_audiobooks = "audiobooks tab" }
-- full screens that aren't a counted part: Home, the Downloads tab, Settings
local NOT_A_PART = { home = true, filemanager = true, KOReader = true, zen_settings = true }

--- The part of GZreader on screen: "reader", "catalog books", "catalog
--- audiobooks", "catalog music", "audiobooks tab", "music tab", "notes",
--- "calendar", or nil (Home, Downloads, Settings…). Looks down the window
--- stack past what's open on top of a part (the quick panel, dialogs, a
--- book's page, the players, the note editor).
function U.portion()
    local stack = UIManager._window_stack or {}
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if type(w) == "table" then
            if w.name == "ReaderUI" then return "reader" end
            local id = w._gz_navbar_tab_id
            if id == "ct_grimmory" then
                local B = package.loaded["gzreader_browser"]
                local b = B and B.current
                local section = (b and b.menu == w and b.section) or "books"
                return "catalog " .. section
            end
            if id and TAB_PART[id] then return TAB_PART[id] end
            if NOT_A_PART[w.name] then return nil end
        end
    end
    return nil
end

---------------------------------------------------------------- visits

--- A visit ended: sent if it lasted MIN_VISIT seconds (the reader sends its
--- own, richer event: readEnd).
local function endVisit(reason)
    local v = U.visit
    U.visit = nil
    if not v or not on() then return end
    local secs = U.clock() - v.t
    if secs < U.MIN_VISIT then return end
    U.event(v.part, { minutes = mins(secs), reason = reason }, v.part)
end

--- See whether the part on screen changed: ends the visit to the last one,
--- starts one to the new one. Cheap (a walk down the window stack): every
--- tick, and soon after GZreader's tabs open or close and Catalog pages turn.
function U.checkPortion()
    if not on() then U.visit = nil; return end
    local part = U.portion()
    if part == "reader" then part = nil end -- (readStart/readEnd)
    if U.visit and U.visit.part == part then return end
    endVisit("left")
    if part then U.visit = { part = part, t = U.clock() } end
end

--- Check again in a moment (after a window opened or closed).
function U.nudge()
    if U.nudged then return end
    U.nudged = true
    UIManager:scheduleIn(0.5, function()
        U.nudged = false
        pcall(U.checkPortion)
    end)
end

local function isPartWindow(w)
    return type(w) == "table" and (w.name == "ReaderUI" or (w._gz_navbar_tab_id ~= nil))
end

--- Notice GZreader's tabs and books opening and closing (UIManager.show and
--- close: one table lookup per window shown).
function U.watchWindows()
    if U.windows_watched then return end
    U.windows_watched = true
    local orig_show, orig_close = UIManager.show, UIManager.close
    UIManager.show = function(um, w, ...)
        if isPartWindow(w) then U.nudge() end
        return orig_show(um, w, ...)
    end
    UIManager.close = function(um, w, ...)
        if isPartWindow(w) then U.nudge() end
        return orig_close(um, w, ...)
    end
end

---------------------------------------------------------------- audio

--- Playing time of audiobooks and music (gzreader_audioengine: kind
--- "audiobook" or "music"). A pause or a track change shorter than
--- AUDIO_GAP seconds is the same session.
local function endAudio(reason)
    local a = U.audio
    U.audio = nil
    if not a or not on() then return end
    if a.since then a.played = a.played + (U.clock() - a.since) end
    if a.played < U.MIN_VISIT then return end
    U.event(a.kind .. " playing", { minutes = mins(a.played), plays = a.plays, reason = reason }, U.portion())
end
U.endAudio = endAudio

function U.audioPlay(kind)
    if not on() or (kind ~= "audiobook" and kind ~= "music") then return end
    local a = U.audio
    if a and a.kind ~= kind then endAudio("switched"); a = nil end
    if not a then a = { kind = kind, played = 0, plays = 0 }; U.audio = a end
    a.plays = a.plays + 1
    a.stopped = nil
    if not a.since then a.since = U.clock() end
end

function U.audioStop()
    local a = U.audio
    if not a or not a.since then return end
    a.played = a.played + (U.clock() - a.since)
    a.since = nil
    a.stopped = U.clock()
end

--- (every tick) a session stopped for AUDIO_GAP seconds has ended.
function U.checkAudio()
    local a = U.audio
    if a and not a.since and a.stopped and U.clock() - a.stopped >= U.AUDIO_GAP then endAudio("stopped") end
end

local function tick()
    -- (the time since the last tick: lined up on the clock, the first one is shorter)
    local now = os.time()
    local elapsed = math.max(0, math.min(now - (U.last_tick or (now - U.TICK)), 2 * U.TICK))
    U.last_tick = now
    if on() then
        pcall(U.checkPortion)
        pcall(U.checkAudio)
        local okn, NetworkMgr = pcall(require, "ui/network/manager")
        if okn and NetworkMgr:isWifiOn() then agg.wifi = agg.wifi + elapsed end
        -- keys the screen didn't answer (also without remote debugging)
        local okt, Trace = pcall(require, "gzreader_slowtrace")
        local okr, R = pcall(require, "gzreader_remote")
        if okt and Trace.installed and not (okr and R.on) then pcall(Trace.checkStuck, function() end) end
        if os.time() - agg.since >= U.SUMMARY_EVERY then U.summary("periodic") end
        U.maybeSend() -- only does something when Wi-Fi is on and it's time
    end
    UIManager:scheduleIn(require("gzreader_ticks").untilNext(U.TICK), tick) -- (with the other timers: gzreader_ticks.lua)
end

---------------------------------------------------------------- reading

function U.readStart(ui)
    if not on() or not (ui and ui.document) then return end
    local file = ui.document.file or ""
    U.reading = {
        t = U.clock(), pages = 0, battery = battery(),
        format = (file:match("%.(%w+)$") or "?"):lower(),
        picture_book = ui.doc_settings and ui.doc_settings:readSetting("gzreader_picture_book") == true or false,
    }
    U.nudge() -- (a Catalog or tab visit underneath ends)
end

function U.pageTurned()
    if U.reading then U.reading.pages = U.reading.pages + 1 end
end

--- The "reader" visit: a book was open (closed, Home, sleep).
function U.readEnd(reason)
    local r = U.reading
    U.reading = nil
    if not (r and on()) then return end
    local secs = U.clock() - r.t
    if secs < U.MIN_VISIT then return end
    local b = battery()
    local drop = (r.battery and b) and (r.battery - b) or nil
    local ev = {
        format = r.format, picture_book = r.picture_book, minutes = mins(secs),
        pages = r.pages, pages_per_minute = math.floor(r.pages / (secs / 60) * 10 + 0.5) / 10,
        battery_start = r.battery, battery_end = b,
        battery_per_hour = (drop and secs >= 600) and math.floor(drop / secs * 3600 * 10 + 0.5) / 10 or nil,
        reason = reason,
    }
    U.event("reader", ev, "reader")
end

--- Read aloud (gzreader_tts): how long it spoke.
function U.ttsStart() U.tts_at = U.clock() end
function U.ttsStop()
    local t = U.tts_at
    U.tts_at = nil
    if not t then return end
    local secs = U.clock() - t
    if secs >= U.MIN_VISIT then U.event("read aloud", { minutes = mins(secs) }, U.portion()) end
end

--- A book download finished (gzreader_download).
function U.download(info)
    if not on() then return end
    local data = { ok = info.ok == true, error = (not info.ok) and tostring(info.error or "?"):sub(1, 40) or nil,
        kind = info.kind or "book" }
    data.kb = info.bytes and math.floor(info.bytes / 1024) or nil
    data.seconds = info.seconds
    data.minutes = info.seconds and mins(info.seconds) or 0
    data.kb_per_s = (info.bytes and info.seconds and info.seconds > 0) and math.floor(info.bytes / 1024 / info.seconds) or nil
    data.resumed = info.resumed == true
    U.event("download", data)
end

--- Keys arrived but the screen didn't change (gzreader_slowtrace).
function U.stuck(seconds, windows)
    U.event("keys not answered", { seconds = seconds, minutes = mins(seconds), screen = U.whereNow(),
        windows = tostring(windows):sub(1, 120) })
end

---------------------------------------------------------------- start / sleep

--- Everything under way ends (exit, sleep): visits, the book, read aloud,
--- audio, the summaries.
local function endAll(reason)
    U.readEnd(reason)
    endVisit(reason)
    U.ttsStop()
    endAudio(reason)
    U.summary(reason)
end

function U.start()
    if U.started then return end
    U.started = true
    -- (how the previous run ended: the debug reports, gzreader_remote.lua)
    os.remove(U.dir() .. "/state") -- (written until 1.28)
    if not on() then
        U.dropQueue()
    else
        U.identify()
    end
    if not U.quit_patched then
        U.quit_patched = true
        local orig_quit = UIManager.quit
        UIManager.quit = function(...)
            pcall(endAll, "closed")
            return orig_quit(...)
        end
    end
    pcall(U.watchWindows)
    U.nudge()
    UIManager:scheduleIn(U.TICK, tick)
    -- the slow-operation timer (cheap; without the profiler)
    if on() then
        local okt, Trace = pcall(require, "gzreader_slowtrace")
        if okt and not Trace.installed then
            pcall(Trace.install, DataStorage:getDataDir() .. "/gzreader-remote", {})
        end
    end
end

--- Sleep ends what's under way (a new visit starts on waking).
function U.onSuspend()
    pcall(function()
        if U.reading then
            local ui_reading = U.reading
            U.readEnd("sleep")
            U.resume_reading = ui_reading
        end
        endAll("sleep")
    end)
end

function U.onResume()
    pcall(function()
        local r = U.resume_reading
        U.resume_reading = nil
        if r and on() then
            U.reading = { t = U.clock(), pages = 0, battery = battery(), format = r.format, picture_book = r.picture_book }
        end
        U.nudge()
    end)
end

--- What Basic and Full send (Settings → General → Usage statistics).
U.WHAT_IS_SENT = require("gettext")("Sends, with GZreader's version, the Kindle model and firmware: how long you spend in books, the Catalog's Books, Audiobooks and Music pages, the Audiobooks and Music tabs, Notes and Calendar; reading (format, picture book or not, pages, pages per minute, battery use per hour); how long read aloud, audiobooks and music play; downloads (worked or failed, size, speed); how syncs with Grimmory go; how long Wi-Fi is on; slow operations and keys the screen didn't answer. No book titles, file names, account or anything you type.")

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
            item(_("Basic (how GZreader is used)"), "basic",
                U.WHAT_IS_SENT),
            item(_("Full (also debug reports)"), "full",
                _("The same as Basic.") .. (U.noWifi() and "" or ("\n\n" .. _("Full also sends debug reports to the developer: GZreader's starts and how the previous run ended, warnings and errors from its log, freezes and crashes. Log lines can name the book or file GZreader was working on; they never have passwords or tokens.")))),
            item(_("Off (send nothing)"), "off", _("Nothing is recorded or sent. What was waiting is deleted.")),
        },
        help_text = U.noWifi() and _("This Kindle has no Wi-Fi: the statistics wait on the Kindle and the sync page sends them from the computer when you sync.") or nil,
        separator = true,
    }
end

return U
