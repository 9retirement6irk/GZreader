--[[--
Where the time goes when a book opens: one line in the log per book opened,

  book open: 9.8 s to the first page (CPU 2.4 s) | file manager closed 0.6 s |
  document opened 0.1 s | reader set up 6.2 s (book loaded 1.0 s, laid out
  3.1 s) | ReaderReady 1.9 s: statistics 0.9, gzreader 0.6 | screen refreshes
  3 (1.4 s) | book 31.7 MB, free memory 23 MB (+ 40 MB cache), GZreader 56 MB

Times are wall-clock. Wall time well above the CPU time means waiting:
reading the book and its cache from storage, memory being short (files read
again), or the e-ink panel.
]]

local Log = require("gzreader_log")
local time = require("ui/time")

local OT = { installed = false, LIMIT = 90, BOOT_FALLBACK = 60 }

local function now() return time.now() end
local function secs(d) return time.to_s(d) end

local function meminfo()
    local f = io.open("/proc/meminfo", "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local free = tonumber(s:match("MemFree:%s+(%d+)"))
    local cached = tonumber(s:match("\nCached:%s+(%d+)"))
    return free and math.floor(free / 1024), cached and math.floor(cached / 1024)
end

local function rss()
    local f = io.open("/proc/self/status", "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local kb = tonumber(s:match("VmRSS:%s+(%d+)"))
    return kb and math.floor(kb / 1024)
end

--- A book starts opening. With diagnostic logging off nothing is measured:
--- the line would be thrown away, so no /proc reads and no timing (every
--- wrapper below does nothing while OT.cur is nil).
function OT.start(file)
    if not Log.enabled then
        OT.cur = nil
        return
    end
    local free, cached = meminfo()
    local lfs = require("libs/libkoreader-lfs")
    OT.cur = {
        file = file, t0 = now(), c0 = os.clock(), phases = {}, order = {}, modules = {},
        refreshes = 0, refresh_time = 0, free = free, cached = cached,
        size = lfs.attributes(file, "size"),
    }
end

local function addPhase(name, d)
    local cur = OT.cur
    if not cur then return end
    if not cur.phases[name] then cur.order[#cur.order + 1] = name end
    cur.phases[name] = (cur.phases[name] or 0) + d
end

--- Wrap `obj[method]` to add its wall time to phase `name` while a book opens.
local function wrap(obj, method, name)
    local orig = obj and obj[method]
    if type(orig) ~= "function" then return end
    obj[method] = function(...)
        if not OT.cur then return orig(...) end
        local t = now()
        local r = { orig(...) }
        addPhase(name, now() - t)
        return unpack(r)
    end
end

local function finish()
    local cur = OT.cur
    OT.cur = nil
    if not cur then return end
    local total = secs(now() - cur.t0)
    local parts = { string.format("book open: %.1f s to the first page (CPU %.1f s)", total, os.clock() - cur.c0) }
    local function ph(name) return cur.phases[name] and string.format("%s %.1f s", name, secs(cur.phases[name])) end
    parts[#parts + 1] = ph("file manager closed")
    parts[#parts + 1] = ph("document opened")
    local inner = {}
    for _i, name in ipairs({ "book loaded", "laid out" }) do inner[#inner + 1] = ph(name) end
    local ready = ph("ReaderReady")
    if ready then
        table.sort(cur.modules, function(a, b) return a[2] > b[2] end)
        local m = {}
        for i = 1, math.min(5, #cur.modules) do
            if cur.modules[i][2] >= 0.05 then m[#m + 1] = string.format("%s %.1f", cur.modules[i][1], cur.modules[i][2]) end
        end
        inner[#inner + 1] = ready .. (#m > 0 and (": " .. table.concat(m, ", ")) or "")
    end
    local setup = ph("reader set up")
    if setup then parts[#parts + 1] = setup .. (#inner > 0 and (" (" .. table.concat(inner, "; ") .. ")") or "") end
    parts[#parts + 1] = string.format("screen refreshes %d (%.1f s)", cur.refreshes, secs(cur.refresh_time))
    local free, cached = meminfo()
    parts[#parts + 1] = string.format("book %.1f MB, free memory %s MB (+ %s MB cache) before, %s MB (+ %s) after, GZreader %s MB",
        (cur.size or 0) / 1048576, tostring(cur.free), tostring(cur.cached), tostring(free), tostring(cached), tostring(rss()))
    Log.info(table.concat(parts, " | "))
    -- (Full usage statistics: how long books take to open)
    pcall(function() require("gzreader_usage").bookOpened(total) end)
end

---------------------------------------------------------------- the start
-- One line per start, like the book-open one:
--
--   start: Home on screen 14.2 s after the program started (CPU 9.1 s) |
--   GZreader started at 6.3 s, set up in 0.7 s | modules loaded 905,
--   Lua memory 15.3 MB | free memory 98 MB (+ 31 MB cache), GZreader 44 MB
--
-- "GZreader started at": KOReader and the plugins before GZreader's (ZenOS,
-- the file manager); "set up in": GZreader's own start; the rest, up to
-- the first refresh with Home (or a book) on screen: ZenOS's Home, covers,
-- the first drawing.

--- Seconds since this process started, from /proc/self/stat (its start, in
--- clock ticks since boot) and /proc/uptime; `stat`/`uptime` (text) for tests.
function OT.processAge(stat, uptime, hz)
    if not stat then
        local f = io.open("/proc/self/stat", "rb")
        stat = f and f:read("*a"); if f then f:close() end
    end
    if not uptime then
        local f = io.open("/proc/uptime", "rb")
        uptime = f and f:read("*a"); if f then f:close() end
    end
    if type(stat) ~= "string" or type(uptime) ~= "string" then return nil end
    -- (the command name, in brackets, may hold spaces: fields count from after it)
    local rest = stat:match("^.*%)%s+(.*)$")
    local up = tonumber(uptime:match("^%s*([%d.]+)"))
    if not rest or not up then return nil end
    local fields = {}
    for x in rest:gmatch("%S+") do fields[#fields + 1] = x end
    local start_ticks = tonumber(fields[20]) -- field 22 of the whole line: starttime
    if not start_ticks then return nil end
    local age = up - start_ticks / (hz or 100)
    return age >= 0 and age or nil
end

--- The log line for a start (pure: run_tests.lua).
function OT.startupLine(b)
    local function n(v, fmt) return v and string.format(fmt, v) or "?" end
    return table.concat({
        string.format("start: %s on screen %s s after the program started (CPU %s s)",
            b.what or "the first screen", n(b.shown, "%.1f"), n(b.cpu, "%.1f")),
        string.format("GZreader started at %s s, set up in %s s", n(b.plugin_at, "%.1f"), n(b.setup, "%.1f")),
        string.format("modules loaded %s, Lua memory %s MB", tostring(b.modules or "?"), n(b.lua_mb, "%.1f")),
        string.format("free memory %s MB (+ %s MB cache), GZreader %s MB",
            tostring(b.free or "?"), tostring(b.cached or "?"), tostring(b.rss or "?")),
    }, " | ")
end

--- GZreader's plugin starts (the first instance of a run).
function OT.bootBegin()
    if OT.boot ~= nil then return end
    OT.boot = { plugin_at = OT.processAge(), t0 = now() }
end

--- GZreader's plugin is set up: from here, the first refresh with Home (or a
--- book) on screen ends the start; a refresh with neither BOOT_FALLBACK s
--- later ends it too (you start on the file browser, say).
function OT.bootReady()
    local b = OT.boot
    if type(b) ~= "table" or b.ready then return end
    b.ready = true
    b.setup = secs(now() - b.t0)
end

local function windowIs(stack)
    for i = #(stack or {}), 1, -1 do
        local w = stack[i] and stack[i].widget
        if type(w) == "table" then
            if rawget(w, "_zen_home_focus_targets") ~= nil or w._zen_home_focus_targets ~= nil then return "Home" end
            if w.name == "ReaderUI" then return "a book" end
        end
    end
end
OT.windowIs = windowIs

--- A screen refresh while the start is being timed (`stack`: UIManager's windows).
function OT.bootRefresh(stack)
    local b = OT.boot
    if type(b) ~= "table" or not b.ready then return end
    b.last_refresh = OT.processAge() or b.last_refresh
    local what = windowIs(stack)
    if what then return OT.bootFinish(what) end
    if secs(now() - b.t0) > OT.BOOT_FALLBACK then return OT.bootFinish("the first screen") end
end

function OT.bootFinish(what)
    local b = OT.boot
    if type(b) ~= "table" then return end
    OT.boot = false -- (once a run)
    if not what then return end
    local free, cached = meminfo()
    local n = 0
    for _k in pairs(package.loaded) do n = n + 1 end
    b.what = what
    b.shown = what == "the first screen" and b.last_refresh or OT.processAge()
    b.cpu = os.clock()
    b.modules = n
    b.lua_mb = collectgarbage("count") / 1024
    b.free, b.cached, b.rss = free, cached, rss()
    Log.info(OT.startupLine(b))
    return b
end

function OT.install()
    if OT.installed then return end
    OT.installed = true
    local ReaderUI = require("apps/reader/readerui")
    local orig_show = ReaderUI.showReader
    ReaderUI.showReader = function(self, file, ...)
        pcall(OT.start, file)
        return orig_show(self, file, ...)
    end
    local okf, FileManager = pcall(require, "apps/filemanager/filemanager")
    if okf then wrap(FileManager, "onShowingReader", "file manager closed") end
    wrap(require("document/documentregistry"), "openDocument", "document opened")
    wrap(ReaderUI, "init", "reader set up")
    local okc, CreDocument = pcall(require, "document/credocument")
    if okc then
        wrap(CreDocument, "loadDocument", "book loaded")
        wrap(CreDocument, "render", "laid out")
    end
    -- ReaderReady: each module's share
    local orig_he = ReaderUI.handleEvent
    ReaderUI.handleEvent = function(self, ev)
        if not (OT.cur and type(ev) == "table" and ev.handler == "onReaderReady") then return orig_he(self, ev) end
        local wrapped = {}
        for i, child in ipairs(self) do
            local f = type(child) == "table" and child.handleEvent
            if f then
                local own = rawget(child, "handleEvent")
                local name = tostring(child.name or i)
                child.handleEvent = function(c, e)
                    local t = now()
                    local r = f(c, e)
                    if OT.cur then OT.cur.modules[#OT.cur.modules + 1] = { name, secs(now() - t) } end
                    return r
                end
                wrapped[#wrapped + 1] = { child, own }
            end
        end
        local t = now()
        local ok, r = pcall(orig_he, self, ev)
        for _i, w in ipairs(wrapped) do rawset(w[1], "handleEvent", w[2]) end
        addPhase("ReaderReady", now() - t)
        if OT.cur then OT.cur.ready = true end
        if not ok then error(r, 0) end
        return r
    end
    -- screen refreshes (on the Kindle 3: packing the shadow screen + the e-ink update);
    -- the first one after ReaderReady is the page
    local Screen = require("device").screen
    for _i, name in ipairs({ "refreshPartialImp", "refreshFullImp" }) do
        local orig = Screen[name]
        if type(orig) == "function" then
            Screen[name] = function(self, ...)
                local cur = OT.cur
                if not cur and not OT.boot then return orig(self, ...) end
                local t = now()
                local r = { orig(self, ...) }
                -- (the start being timed: this refresh may be the first with Home)
                if OT.boot then pcall(OT.bootRefresh, require("ui/uimanager")._window_stack) end
                if cur then
                    cur.refreshes = cur.refreshes + 1
                    cur.refresh_time = cur.refresh_time + (now() - t)
                    if cur.ready then pcall(finish) end
                    if OT.cur and secs(now() - OT.cur.t0) > OT.LIMIT then OT.cur = nil end
                end
                return unpack(r)
            end
        end
    end
end

return OT
