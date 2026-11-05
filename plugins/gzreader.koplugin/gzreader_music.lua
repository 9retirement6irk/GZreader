--[[--
Music from Plex: what's downloaded, downloading, and the player that keeps
playing while you read (gzreader_musictab.lua is the Music tab).

Kindles with a speaker or headphone jack (gzreader_touch.lua audio(): the
Kindle 2, 3, DX and Touch). The audio goes through the same player as
audiobooks (gzreader_audioengine.lua): MP3, and AAC as ADTS chunks.

Storage: <GZreader folder>/.music/<album-or-playlist>/ with the tracks
(01.mp3…, or 01.m4a.chunks/ for AAC), cover.jpg and music.json:
  { kind = "album" | "playlist", key, title, artist, year, added,
    tracks = { { key, title, artist, album, duration, file, chunks } } }
A track is there when its file (or chunks index) is.

Downloads run in a background process, a track at a time, in order, so
"Play" can start with the first track while the rest come (and the Kindle
can be read meanwhile). Wi-Fi is only on while downloading. Progress (track
n of m, and how far into it) shows in the album's list, the Downloads screen
and the status bar, where a download can be stopped. Tracks that came stay
when one fails or a download is stopped (or GZreader restarts mid-way: a
track whose file is complete is taken up again); downloading again fetches
only the missing ones; half-written files are cleared.

Only one thing plays at a time: music, an audiobook or read aloud. Starting
one pauses the others; sleep (the power switch) and unplugging headphones
(gzreader_jack.lua) pause it too.
]]

local Awake = require("gzreader_awake")
local Engine = require("gzreader_audioengine")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local Log = require("gzreader_log")
local UIManager = require("ui/uimanager")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = ffiutil.template

local Music = {
    STORE = ".music",
    TICK = 2,
    current = nil,   -- the player
    downloads = {},  -- dir -> state, while downloading
    BITRATES = { 128, 192, 320 },
}

local function mkdirp(path)
    local acc = path:sub(1, 1) == "/" and "" or "."
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if lfs.attributes(acc, "mode") == nil then lfs.mkdir(acc) end
    end
end

function Music.plex(plugin)
    plugin.store.plex = plugin.store.plex or {}
    local p = require("gzreader_plex"):new(plugin.store.plex)
    p.plugin = plugin
    return p
end

function Music.root(plugin) return plugin:libraryDir() .. "/" .. Music.STORE end

local function safe(s) return (tostring(s or ""):gsub("[^%w%-]", "_")) end

function Music.dirFor(plugin, kind, key) return Music.root(plugin) .. "/" .. safe(kind) .. "-" .. safe(key) end

---------------------------------------------------------------- what's downloaded

local function readJson(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and data or nil
end

local function writeJson(p, t)
    local f = io.open(p .. ".tmp", "wb")
    if not f then return false end
    f:write(JSON.encode(t))
    f:close()
    return os.rename(p .. ".tmp", p)
end

--- Is track t of collection c on the Kindle? (path / chunks set when it is)
function Music.trackReady(c, t)
    if t.chunks then return true end
    if not t.file and t.base and c.dir then
        -- downloaded, but not written down (GZreader stopped mid-download)
        for _i, ext in ipairs({ "mp3", "aac" }) do
            if lfs.attributes(c.dir .. "/" .. t.base .. "." .. ext, "mode") == "file" then t.file = t.base .. "." .. ext end
        end
        if not t.file and lfs.attributes(c.dir .. "/" .. t.base .. ".m4a.chunks/index.json", "mode") == "file" then
            t.file = t.base .. ".m4a"
        end
    end
    if not t.file then return false end
    local path = c.dir .. "/" .. t.file
    if t.file:match("%.m4a$") then
        local idx = readJson(path .. ".chunks/index.json")
        if idx and idx.starts then
            t.chunks = { dir = t.file .. ".chunks", starts = idx.starts }
            t.duration = t.duration or idx.durationMs
            return true
        end
        return false
    end
    return lfs.attributes(path, "mode") == "file"
end

function Music.load(dir)
    local c = readJson(dir .. "/music.json")
    if not c or type(c.tracks) ~= "table" then return nil end
    c.dir = dir
    local have = 0
    for _i, t in ipairs(c.tracks) do if Music.trackReady(c, t) then have = have + 1 end end
    c.have = have
    return c
end

function Music.save(c)
    local copy = {}
    for k, v in pairs(c) do if k ~= "dir" and k ~= "have" then copy[k] = v end end
    return writeJson(c.dir .. "/music.json", copy)
end

--- Everything downloaded (or partly): newest first.
function Music.downloaded(plugin)
    local root, out = Music.root(plugin), {}
    if lfs.attributes(root, "mode") ~= "directory" then return out end
    for name in lfs.dir(root) do
        if name ~= "." and name ~= ".." then
            local c = Music.load(root .. "/" .. name)
            if c and c.have > 0 then out[#out + 1] = c end
        end
    end
    table.sort(out, function(a, b) return (a.added or 0) > (b.added or 0) end)
    return out
end

function Music.find(plugin, kind, key)
    return Music.load(Music.dirFor(plugin, kind, key))
end

local function dirSize(dir)
    local n = 0
    if lfs.attributes(dir, "mode") ~= "directory" then return 0 end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local p = dir .. "/" .. name
            local m = lfs.attributes(p, "mode")
            if m == "directory" then n = n + dirSize(p) elseif m == "file" then n = n + (lfs.attributes(p, "size") or 0) end
        end
    end
    return n
end
Music.dirSize = dirSize

local function rmrf(dir)
    if lfs.attributes(dir, "mode") ~= "directory" then os.remove(dir); return end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then rmrf(dir .. "/" .. name) end
    end
    lfs.rmdir(dir)
end

function Music.delete(plugin, c)
    if Music.current and Music.current.collection_dir == c.dir then Music.current:stop() end
    if not tostring(c.dir):find("/" .. Music.STORE .. "/", 1, true) then return end -- (only ever inside .music)
    rmrf(c.dir)
    Log.info("music: deleted", c.kind, c.key)
    pcall(function() require("gzreader_musicfolder").sync(plugin) end)
end

---------------------------------------------------------------- downloading

--- About how big track t will be (bytes), for its progress: its file's
--- size, or (made into MP3 by the server) its length at the bitrate.
function Music.trackSize(t, bitrate)
    local how = require("gzreader_plex").how(t)
    if how ~= "transcode" and t.part and tonumber(t.part.size) then return tonumber(t.part.size) end
    local ms = tonumber(t.duration)
    if ms and ms > 0 then return math.floor(ms / 1000 * (bitrate or 192) * 1000 / 8) end
end

--- How far a download is: 0..1 (tracks done, and the one coming).
function Music.fraction(st)
    if not st or (st.total or 0) == 0 then return 0 end
    local n = (st.done or 0) + (st.failed or 0) + math.min(0.99, st.current_frac or 0)
    return math.min(1, n / st.total)
end

--- "track 3 of 12 · 41%" (pure: run_tests.lua)
function Music.progressShort(st)
    local at = math.min(st.total, (st.done or 0) + (st.failed or 0) + 1)
    local text = T(_("track %1 of %2 · %3%"), at, st.total, math.floor(Music.fraction(st) * 100))
    if (st.failed or 0) > 0 then text = text .. " · " .. T(_("%1 failed"), st.failed) end
    return text
end

--- "Downloading… track 3 of 12 · 41%"
function Music.progressText(st)
    return T(_("Downloading… %1"), Music.progressShort(st))
end

--- What to say when a download ends (pure: run_tests.lua).
function Music.resultText(st, err)
    local title = st.title or ""
    if st.cancelled then
        return T(_("Download stopped: %1 of %2 tracks of “%3” are on the Kindle. Download it again for the rest."),
            st.done or 0, st.total, title)
    end
    if (st.failed or 0) > 0 then
        return T(_("%1 of %2 tracks of “%3” couldn't be downloaded (%4). The others are on the Kindle; download it again to retry the missing ones."),
            st.failed, st.total, title, tostring(err or "?"))
    end
    return T(_("“%1” is on the Kindle."), title)
end

--- Tell the lists showing a download how far it is.
local function notify(st)
    UIManager:broadcastEvent(require("ui/event"):new("GzMusicDownload", st))
end

--- Stop downloading into `dir` (the tracks that came stay).
function Music.stop(dir)
    local st = Music.downloads[dir]
    if not (st and st.pid) then return false end
    st.cancelled = true
    pcall(ffiutil.terminateSubProcess, st.pid)
    Log.info("music: download stopped", st.done, "of", st.total)
    return true
end

local function clearParts(dir)
    if lfs.attributes(dir, "mode") ~= "directory" then return end
    for name in lfs.dir(dir) do
        if name:match("%.part$") then os.remove(dir .. "/" .. name) end
    end
end

--- Download collection `c` ({ kind, key, title, artist, year, thumb,
--- tracks }) into its folder, in the background, in order. opts.on_track(i)
--- as each track arrives, opts.on_done(ok, err). Returns the state.
function Music.download(plugin, c, opts)
    opts = opts or {}
    local dir = Music.dirFor(plugin, c.kind, c.key)
    if Music.downloads[dir] then
        local st = Music.downloads[dir]
        if opts.on_track then st.listeners[#st.listeners + 1] = opts.on_track end
        return st
    end
    mkdirp(dir)
    local old = Music.load(dir)
    local col = { kind = c.kind, key = c.key, title = c.title, artist = c.artist, year = c.year, added = old and old.added or os.time(),
        tracks = {}, dir = dir }
    clearParts(dir)
    for i, t in ipairs(c.tracks) do
        local prev = old and old.tracks[i]
        local base = string.format("%02d", i)
        if prev and prev.key ~= t.key then
            -- (a playlist changed: another track was here; not to be taken for this one)
            for _j, ext in ipairs({ "mp3", "aac", "m4a" }) do os.remove(dir .. "/" .. base .. "." .. ext) end
            local idx = dir .. "/" .. base .. ".m4a.chunks/index.json"
            if lfs.attributes(idx, "mode") == "file" then os.remove(idx) end
        end
        col.tracks[i] = { key = t.key, title = t.title, artist = t.artist, album = t.album, duration = t.duration,
            file = prev and prev.key == t.key and prev.file or nil, base = base, part = t.part }
    end
    Music.save(col)
    local plex = Music.plex(plugin)
    local bitrate = plugin.store.plex.bitrate or 192
    local luajit = require("gzreader_audiobook").luajit()
    local script = (Engine.root or "plugins/gzreader.koplugin") .. "/gzreader_mp4.lua"
    local todo = {}
    for i, t in ipairs(col.tracks) do if not Music.trackReady(col, t) then todo[#todo + 1] = i end end
    local state = { dir = dir, total = #todo, done = 0, failed = 0, listeners = { opts.on_track }, title = c.title, kind = "music",
        todo = todo, current_frac = 0 }
    if #todo == 0 then
        if opts.on_done then opts.on_done(true) end
        return state
    end
    Music.downloads[dir] = state
    Log.info("music: downloading", #todo, "tracks of", c.kind, c.key)
    -- (the child writes one line per track to a file: "<i> <file>" or "<i> error <why>")
    local report = dir .. "/.progress"
    os.remove(report)
    local pid = ffiutil.runInSubProcess(function()
        local out = io.open(report, "ab")
        for _n, i in ipairs(todo) do
            local t = col.tracks[i]
            local path, kind = plex:downloadTrack(t, dir .. "/" .. t.base, bitrate)
            if path and kind == "m4a" then
                -- AAC in MP4: ADTS chunks the Kindle can play (as for audiobooks)
                local q = function(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
                lfs.mkdir(path .. ".chunks")
                os.execute(string.format("nice -n 19 %s %s %s %s %s >/dev/null 2>&1", luajit, q(script), q(path), q(path .. ".chunks"),
                    q(path .. ".chunks/progress")))
                if lfs.attributes(path .. ".chunks/index.json", "mode") ~= "file" then path, kind = nil, "couldn't convert" end
            end
            if path then
                out:write(i, " ", path:match("[^/]+$"), "\n")
            else
                out:write(i, " error ", tostring(kind or "?"):gsub("\n", " "), "\n")
            end
            out:flush()
        end
        out:close()
    end)
    if not pid then
        Music.downloads[dir] = nil
        if opts.on_done then opts.on_done(false, "could not start the download", state) end
        return state
    end
    state.pid = pid
    local key = "music-" .. dir
    Awake.hold(key)
    require("gzreader_net").hold(key)
    pcall(function() require("gzreader_tasks").changed() end)
    local seen, errors = 0, {}
    local function poll()
        local f = io.open(report, "rb")
        local lines = {}
        if f then for l in f:lines() do lines[#lines + 1] = l end f:close() end
        for n = seen + 1, #lines do
            local i, rest = lines[n]:match("^(%d+) (.*)$")
            i = tonumber(i)
            if i and col.tracks[i] then
                local why = rest:match("^error (.*)$")
                if why then
                    errors[#errors + 1] = why
                    state.failed = state.failed + 1
                    Log.warn("music: track", i, "of", c.key, "failed:", why)
                else
                    col.tracks[i].file = rest
                    Music.trackReady(col, col.tracks[i])
                    state.done = state.done + 1
                    Music.save(col)
                    for _j, l in ipairs(state.listeners) do pcall(l, i, col) end
                end
            end
        end
        local moved = #lines > seen
        seen = #lines
        if not ffiutil.isSubProcessDone(pid) then
            -- how far into the track coming: its half-written file
            local i = todo[seen + 1]
            local t = i and col.tracks[i]
            if t then
                local ext = select(2, require("gzreader_plex").how(t))
                local size = lfs.attributes(dir .. "/" .. t.base .. "." .. ext .. ".part", "size")
                local want = Music.trackSize(t, bitrate)
                state.current_frac = size and want and want > 0 and math.min(0.99, size / want)
                    or (lfs.attributes(dir .. "/" .. t.base .. "." .. ext, "mode") and 0.99) or 0
            end
            local now = os.time()
            if moved or now - (state.notified or 0) >= 5 then
                state.notified = now
                notify(state)
                if moved then pcall(function() require("gzreader_tasks").changed() end) end
            end
            return UIManager:scheduleIn(1, poll)
        end
        Music.downloads[dir] = nil
        os.remove(report)
        clearParts(dir)
        state.current_frac = 0
        -- (a track finished as it was stopped: written, not yet reported)
        for _i, t in ipairs(col.tracks) do Music.trackReady(col, t) end
        Awake.release(key)
        require("gzreader_net").release(key)
        pcall(function() require("gzreader_tasks").changed() end)
        Music.save(col)
        Log.info("music: download finished", c.key, state.done, "of", state.total, #errors > 0 and ("errors: " .. errors[1]) or "",
            state.cancelled and "(stopped)" or "")
        state.finished = true
        notify(state)
        pcall(function() require("gzreader_musicfolder").sync(plugin) end)
        if opts.on_done then opts.on_done(#errors == 0 and not state.cancelled, state.cancelled and "stopped" or errors[1], state) end
    end
    UIManager:scheduleIn(1, poll)
    -- the cover, in the background too (small)
    if c.thumb and lfs.attributes(dir .. "/cover.jpg", "mode") ~= "file" then
        require("gzreader_async").run(nil, function() return plex:downloadThumb(c.thumb, dir .. "/cover.jpg", 300) end, function() end, "music cover")
    end
    return state
end

---------------------------------------------------------------- the player

local Player = {}
Player.__index = Player
Music.Player = Player

--- A player for collection `c` from track `start` (shuffled: in random order).
function Player:new(plugin, c, start, shuffle)
    local o = setmetatable({ plugin = plugin, c = c, collection_dir = c.dir, pos = 0, shuffle = shuffle or false,
        ["repeat"] = plugin.store.plex and plugin.store.plex["repeat"] or "off" }, self)
    o.order = {}
    for i = 1, #c.tracks do o.order[i] = i end
    if shuffle then o:reshuffle(start) end
    o.at = 1
    for n, i in ipairs(o.order) do if i == (start or 1) then o.at = n end end
    return o
end

function Player:reshuffle(first)
    local rest = {}
    for i = 1, #self.c.tracks do if i ~= first then rest[#rest + 1] = i end end
    for i = #rest, 2, -1 do
        local j = math.random(1, i)
        rest[i], rest[j] = rest[j], rest[i]
    end
    self.order = { first or table.remove(rest, 1) }
    for _i, v in ipairs(rest) do self.order[#self.order + 1] = v end
end

function Player:track() return self.c.tracks[self.order[self.at]] end

--- Tracks that arrived since the player started (a download in progress
--- writes music.json as each one comes).
function Player:refreshTracks()
    if self.c.kind == "all" then return end
    local fresh = Music.load(self.c.dir)
    if not fresh then return end
    for i, t in ipairs(fresh.tracks) do
        local mine = self.c.tracks[i]
        if mine and mine.key == t.key then
            mine.file, mine.chunks, mine.duration = t.file, t.chunks, mine.duration or t.duration
        end
    end
end

function Player:source(t, offset)
    if t.chunks then
        return { kind = "chunks", dir = self.c.dir .. "/" .. t.chunks.dir, starts = t.chunks.starts, offset_ms = offset }, "aac"
    end
    local path = self.c.dir .. "/" .. t.file
    return { kind = "file", path = path, offset_ms = offset, size = lfs.attributes(path, "size"), duration_ms = t.duration },
        Engine.format(path)
end

--- Pause whatever else plays (an audiobook, read aloud).
local function quietOthers(plugin)
    local AB = package.loaded["gzreader_audiobook"]
    if AB and AB.current and AB.current.playing then pcall(AB.current.pause, AB.current) end
    pcall(function()
        local ui = require("apps/reader/readerui").instance
        local g = ui and ui.gzreader
        if g and g.tts and g.tts.active then g.tts:stop() end
    end)
end

--- The next track in the play order that's on the Kindle (after the
--- current one; round to the start with repeat all), or nil.
function Player:nextReady()
    local n = #self.order
    for k = 1, n do
        local at = self.at + k
        if at > n then
            if self["repeat"] ~= "all" then return nil end
            at = at - n
        end
        local t = self.c.tracks[self.order[at]]
        if t and Music.trackReady(self.c, t) then return at end
    end
end

function Player:play()
    local t = self:track()
    if not t then return self:stop() end
    if not Music.trackReady(self.c, t) then self:refreshTracks() end
    if not Music.trackReady(self.c, t) and not Music.downloads[self.c.dir] then
        -- not on the Kindle, and nothing's bringing it: on to the next that is
        -- (at once; it waited 2 s for each missing track before)
        local nxt = self:nextReady()
        if nxt then
            Log.info("music: skipping to the next track on the Kindle")
            self.at, self.pos = nxt, 0
            return self:play()
        end
        Log.warn("music: none of the tracks are on the Kindle")
        self:stop()
        UIManager:show(InfoMessage:new{ text = _("None of these tracks are on the Kindle. Download them again."), timeout = 5 })
        return false
    end
    if not Music.trackReady(self.c, t) then
        -- still downloading: start when it's there
        self.waiting = true
        self.playing = true
        Music.current = self
        self:schedule()
        return true
    end
    self.waiting = nil
    self.skipped = 0
    local src, fmt = self:source(t, self.pos)
    local p = Engine.chosen(fmt)
    if not p then
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = T(_("No player has been found yet for %1 audio on this Kindle. Run the audio test now?"), (fmt or "?"):upper()),
            ok_text = _("Test audio"),
            ok_callback = function() Engine.test(function() if Engine.chosen(fmt) then self:play() end end) end,
        })
        return false
    end
    quietOthers(self.plugin)
    if Music.current and Music.current ~= self then Music.current:stop() end
    local started = select(2, Engine.play(p, src))
    self.pos = started or 0
    self.playing, self.paused = true, nil
    Music.current = self
    self:keepAwake(true)
    pcall(function() require("gzreader_jack").watch("music", function() self:pause(_("Headphones unplugged: music paused.")) end) end)
    self:schedule()
    self:changed()
    Log.info("music: playing", self.order[self.at], "of", self.c.key)
    return true
end

function Player:position()
    if self.playing and not self.waiting then return Engine.position() end
    return self.pos
end

function Player:pause(why)
    if not self.playing then return end
    if not self.waiting then self.pos = Engine.position() end
    Engine.stop()
    self.playing, self.paused, self.waiting = false, true, nil
    if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
    self:keepAwake(false)
    pcall(function() require("gzreader_jack").unwatch("music") end)
    if why then UIManager:show(InfoMessage:new{ text = why, timeout = 3 }) end
    self:changed()
end

function Player:resume() if not self.playing then self:play() end end
function Player:toggle() if self.playing then self:pause() else self:resume() end end

function Player:stop()
    Engine.stop()
    self.playing, self.paused, self.waiting = false, nil, nil
    if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
    self:keepAwake(false)
    pcall(function() require("gzreader_jack").unwatch("music") end)
    if Music.current == self then Music.current = nil end
    self:changed()
end

--- Next (+1) or previous (-1) track. Previous restarts the track after 3 s.
function Player:step(dir)
    if dir < 0 and self:position() > 3000 then
        self.pos = 0
    else
        local n = self.at + dir
        if n > #self.order then
            if self["repeat"] == "all" then n = 1 else return self:finish() end
        elseif n < 1 then n = 1 end
        self.at, self.pos = n, 0
    end
    local was = self.playing or self.paused
    Engine.stop()
    self.playing = false
    if was then self:play() else self:changed() end
end

function Player:jump(n)
    self.at, self.pos = math.max(1, math.min(#self.order, n)), 0
    Engine.stop()
    self.playing = false
    self:play()
end

function Player:setShuffle(on)
    local cur = self.order[self.at]
    self.shuffle = on
    if on then self:reshuffle(cur) else
        self.order = {}
        for i = 1, #self.c.tracks do self.order[i] = i end
    end
    for n, i in ipairs(self.order) do if i == cur then self.at = n end end
    self:changed()
end

function Player:cycleRepeat()
    local nxt = { off = "all", all = "one", one = "off" }
    self["repeat"] = nxt[self["repeat"]] or "off"
    self.plugin.store.plex = self.plugin.store.plex or {}
    self.plugin.store.plex["repeat"] = self["repeat"]
    self.plugin:save()
    self:changed()
end

function Player:finish()
    self.at, self.pos = 1, 0
    self:stop()
    UIManager:show(InfoMessage:new{ text = T(_("The end of “%1”."), self.c.title or ""), timeout = 3 })
end

function Player:keepAwake(on)
    if on == self.awake then return end
    self.awake = on
    if on then Awake.hold(self) else Awake.release(self) end
end

function Player:schedule()
    if self.ticker then return end
    self.ticker = function() self.ticker = nil; self:tick() end
    UIManager:scheduleIn(Music.TICK, self.ticker)
end

function Player:tick()
    if not self.playing then return end
    if self.waiting then
        self:refreshTracks()
        if Music.trackReady(self.c, self:track()) then return self:play() end
        if not Music.downloads[self.c.dir] then
            -- the download stopped without it: skip it (once round the
            -- list at most: 1.21.0 went round and round, every 2 s)
            self.skipped = (self.skipped or 0) + 1
            if self.skipped >= #(self.c.tracks or {}) then
                Log.warn("music: none of the tracks are on the Kindle, stopping")
                self.skipped = 0
                self.waiting = nil
                self:stop()
                UIManager:show(InfoMessage:new{ text = _("None of these tracks are on the Kindle. Download the album again."), timeout = 5 })
                return
            end
            Log.warn("music: track never arrived, skipping")
            return self:step(1)
        end
        return self:schedule()
    end
    local t = self:track()
    local pos = Engine.position()
    local stopped = not Engine.running()
    local ended = stopped or (t.duration and t.duration > 0 and pos >= t.duration + 4000)
    if stopped and Engine.played() < 3000 then
        Log.warn("music: the player stopped at once:", Engine.log():sub(1, 300):gsub("\n", " / "))
        self:stop()
        UIManager:show(InfoMessage:new{ text = _("The track didn't play. Run Test audiobook playback (Settings → Reader); if it still fails, send the log (Settings → General).") })
        return
    end
    if ended then
        if self["repeat"] == "one" then
            self.pos = 0
            Engine.stop(); self.playing = false
            return self:play()
        end
        return self:step(1)
    end
    -- KOReader's autosuspend counts input; playing music counts as activity
    if os.time() - (self.last_activity or 0) >= 50 then
        self.last_activity = os.time()
        UIManager:broadcastEvent(require("ui/event"):new("InputEvent"))
    end
    self:schedule()
end

--- Tell the Music tab, Now playing and the reading menus.
function Player:changed()
    for _k, fn in pairs(Music.listeners) do pcall(fn, self) end
end
Music.listeners = {}

--- "Title — Artist" of what's playing, or nil.
function Music.nowText()
    local p = Music.current
    if not p then return nil end
    local t = p:track()
    if not t then return nil end
    return (t.title or "?") .. (t.artist and (" — " .. t.artist) or "")
end

--- Play collection c (downloaded, or downloading it now: from the first track).
function Music.play(plugin, c, start, shuffle)
    local p = Player:new(plugin, c, start, shuffle)
    return p:play() and p
end

--- Every downloaded track at random.
function Music.shuffleAll(plugin)
    local all = { kind = "all", key = "all", title = _("All downloaded music"), tracks = {}, dir = "" }
    local list = Music.downloaded(plugin)
    for _i, c in ipairs(list) do
        for _j, t in ipairs(c.tracks) do
            if Music.trackReady(c, t) then
                local copy = {}
                for k, v in pairs(t) do copy[k] = v end
                -- (paths relative to the collection: make them relative to the music folder)
                local sub = c.dir:match("[^/]+$")
                if copy.chunks then copy.chunks = { dir = sub .. "/" .. copy.chunks.dir, starts = copy.chunks.starts } end
                if copy.file then copy.file = sub .. "/" .. copy.file end
                all.tracks[#all.tracks + 1] = copy
            end
        end
    end
    if #all.tracks == 0 then
        return UIManager:show(InfoMessage:new{ text = _("No music downloaded yet."), timeout = 3 })
    end
    all.dir = Music.root(plugin)
    return Music.play(plugin, all, math.random(1, #all.tracks), true)
end

--- Pause (from sleep, read aloud, an audiobook).
function Music.pauseAll(why)
    if Music.current and Music.current.playing then Music.current:pause(why) end
end

return Music
