--[[--
Grimmory audiobooks on the Kindle: download, listen, chapters, sleep timer,
progress synced with Grimmory's own audiobook progress (the web player's).

Storage: <GZreader folder>/.audiobooks/<book id>/ with the audio file(s) and
audiobook.json (Grimmory's info: duration, chapters, tracks). Hidden: a long
book is thousands of 15-second chunk files, which file lists, folder covers
and file search would otherwise walk through. The visible
<GZreader folder>/Audiobooks folder stays empty; opening it in a file list
shows the downloaded audiobooks instead (gzreader_abfolder.lua).

Grimmory progress for audiobooks (PUT /api/v1/app/books/{id}/progress):
  fileProgress = { bookFileId, positionData = "<ms>", positionHref = "<track>",
                   progressPercent }
  positionData is the position inside the current track for folder-based
  books (one file per track), else inside the single file; positionHref is
  the track index (folder-based books only). The same as Grimmory's web player.

Keys on the player screen (Kindle Keyboard):
  5-way press or Space   play / pause
  Left / Right           back / forward 30 seconds
  Up / Down              previous / next chapter
  Menu                   chapters, sleep timer, volume, stop
  Back                   close the screen (playback continues)
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local JSON = require("json")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Awake = require("gzreader_awake")
local ProgressbarDialog = require("gzreader_progress")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Engine = require("gzreader_audioengine")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = ffiutil.template

local Audiobook = {
    PUSH_EVERY = 60,       -- seconds between progress pushes while playing
    SKIP_MS = 30000,
    TICK_SECONDS = 2,      -- player housekeeping (track end, sleep timer); each wake-up costs battery
    current = nil,         -- the Player that is playing or paused
}

---------------------------------------------------------------- helpers

function Audiobook.fmt(ms)
    local s = math.max(0, math.floor((ms or 0) / 1000))
    local h, m = math.floor(s / 3600), math.floor(s / 60) % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s % 60) end
    return string.format("%d:%02d", m, s % 60)
end

local function mkdirp(path)
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if lfs.attributes(acc, "mode") == nil then lfs.mkdir(acc) end
    end
end

local Folder = require("gzreader_abfolder")
Audiobook.STORE = Folder.STORE -- hidden; see the note at the top

function Audiobook.dir(plugin, book_id)
    return plugin:libraryDir() .. "/" .. Audiobook.STORE .. "/" .. tostring(book_id)
end

local function extOf(name, fallback)
    local e = type(name) == "string" and name:match("%.([%w]+)$")
    return (e and e:lower()) or fallback
end

--- The local layout: { info = Grimmory info, files = { path... }, starts = { ms... } }
function Audiobook.load(plugin, book_id)
    local dir = Audiobook.dir(plugin, book_id)
    local f = io.open(dir .. "/audiobook.json", "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    if not ok or type(data) ~= "table" or type(data.files) ~= "table" then return nil end
    for _i, p in ipairs(data.files) do
        if lfs.attributes(dir .. "/" .. p, "mode") ~= "file" then return nil end
    end
    data.dir = dir
    return data
end

--- Global position (ms from the start of the book) -> track index (1-based), ms in track.
function Audiobook.locate(book, global_ms)
    local tracks = book.tracks
    for i = #tracks, 1, -1 do
        if global_ms >= tracks[i].start then return i, global_ms - tracks[i].start end
    end
    return 1, global_ms
end

function Audiobook.total(book)
    local last = book.tracks[#book.tracks]
    return book.durationMs or (last and (last.start + (last.durationMs or 0))) or 0
end

function Audiobook.chapterAt(book, global_ms)
    local idx = 1
    for i, c in ipairs(book.chapters or {}) do
        if (c.startTimeMs or 0) <= global_ms then idx = i end
    end
    return idx, book.chapters and book.chapters[idx]
end

---------------------------------------------------------------- download

--- Turn Grimmory's info into our local book description.
function Audiobook.describe(book_id, info, primary_name)
    local tracks, files = {}, {}
    if info.folderBased and type(info.tracks) == "table" and #info.tracks > 0 then
        for i, t in ipairs(info.tracks) do
            local name = string.format("track-%03d.%s", i, extOf(t.fileName, "mp3"))
            files[i] = name
            tracks[i] = { file = name, index = t.index or (i - 1), durationMs = tonumber(t.durationMs) or 0,
                start = tonumber(t.cumulativeStartMs) or 0, size = tonumber(t.fileSizeBytes), title = t.title }
        end
    else
        local name = "audiobook." .. extOf(primary_name, (info.codec or ""):lower():find("mp3") and "mp3" or "m4b")
        files[1] = name
        tracks[1] = { file = name, index = nil, durationMs = tonumber(info.durationMs) or 0, start = 0,
            size = tonumber(info.totalSizeBytes) }
    end
    local chapters = {}
    for _i, c in ipairs(type(info.chapters) == "table" and info.chapters or {}) do
        chapters[#chapters + 1] = { title = c.title, startTimeMs = tonumber(c.startTimeMs) or 0, durationMs = tonumber(c.durationMs) }
    end
    if #chapters == 0 and #tracks > 1 then
        for i, t in ipairs(tracks) do chapters[i] = { title = t.title or T(_("Track %1"), i), startTimeMs = t.start } end
    end
    return { id = tostring(book_id), title = info.title, author = info.author, narrator = info.narrator,
        file_id = tonumber(info.bookFileId), folder = info.folderBased == true, durationMs = tonumber(info.durationMs),
        tracks = tracks, chapters = chapters, files = files }
end

local function needsConversion(t) return Engine.format(t.file) == "m4a" end

--- M4B/M4A tracks are converted once into ADTS AAC chunks (the Kindle 3
--- can decode AAC but can't open MP4 files): <file>.chunks/c0.aac, c1.aac…
--- plus index.json with each chunk's start time.
---
--- The conversion runs as its own small LuaJIT process at the lowest
--- priority (gzreader_mp4.lua as a script), not in a fork of KOReader: a
--- fork's copy of KOReader's memory gets duplicated page by page as its
--- garbage collector runs, and on a Kindle 3 that ran out of memory and
--- restarted the Kindle's software (1.0.21).
local function readChunks(dir, t)
    local f = io.open(dir .. "/" .. t.file .. ".chunks/index.json", "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    if not (ok and type(data) == "table" and data.starts) then return nil end
    data.dir = data.dir or (t.file .. ".chunks")
    return data
end
Audiobook.readChunks = readChunks

local function shellQuote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

function Audiobook.luajit()
    if Audiobook.LUAJIT then return Audiobook.LUAJIT end
    return lfs.attributes("./luajit", "mode") == "file" and "./luajit" or "luajit"
end

local nice_prefix
local function nice()
    if nice_prefix == nil then
        nice_prefix = os.execute("nice -n 19 true >/dev/null 2>&1") == 0 and "nice -n 19 " or ""
    end
    return nice_prefix
end

--- Start converting one track in the background. Returns the progress file.
function Audiobook.startConversion(dir, t)
    local src = dir .. "/" .. t.file
    local cdir = src .. ".chunks"
    mkdirp(cdir)
    os.remove(cdir .. "/index.json")
    local prog = cdir .. "/progress"
    os.remove(prog)
    local root = Engine.root or "plugins/gzreader.koplugin"
    local script = root .. "/gzreader_mp4.lua"
    local cmd = string.format("%s%s %s %s %s %s", nice(), Audiobook.luajit(), shellQuote(script),
        shellQuote(src), shellQuote(cdir), shellQuote(prog))
    os.execute(string.format("(%s >/dev/null 2>&1; echo $? > %s) >/dev/null 2>&1 &", cmd, shellQuote(prog .. ".exit")))
    return prog
end

--- Convert the tracks that need it, one after another, with a progress bar.
--- on_done(true) or on_done(false, err).
function Audiobook.prepare(dir, tracks, title, on_done)
    local todo, total = {}, 0
    for _i, t in ipairs(tracks) do
        if needsConversion(t) and not readChunks(dir, t) and lfs.attributes(dir .. "/" .. t.file, "mode") == "file" then
            todo[#todo + 1] = t
            total = total + (lfs.attributes(dir .. "/" .. t.file, "size") or 0)
        end
    end
    if #todo == 0 then return on_done(true) end
    local awake_key = "audiobook-prepare-" .. dir
    Awake.hold(awake_key)
    local dialog
    local state = { kind = "prepare", title = title, total = total, done = 0 }
    state.open_dialog = function()
        if dialog then return end
        dialog = ProgressbarDialog:new{
            title = T(_("Preparing “%1” for the Kindle…"), title or ""),
            subtitle = _("Done once per audiobook. Press any key to hide; it carries on."),
            progress_max = total > 0 and total or nil, refresh_time_seconds = 2,
        }
        dialog.dismiss_callback = function() dialog = nil end
        dialog:show()
        dialog:reportProgress(state.done)
    end
    Audiobook.active_prepare = state
    pcall(function() require("gzreader_tasks").changed() end)
    state.open_dialog()
    Log.info("audiobook: preparing", #todo, "file(s) for the Kindle,", total, "bytes")
    local started = os.time()
    local i, before, prog, last_change, last_text = 0, 0, nil, os.time(), nil
    local function finish(ok, err)
        Awake.release(awake_key)
        Audiobook.active_prepare = nil
        pcall(function() require("gzreader_tasks").changed() end)
        if dialog then dialog.dismiss_callback = nil; UIManager:close(dialog); dialog = nil end
        if ok then Log.info("audiobook: prepared in", (os.time() - started) .. "s")
        else Log.warn("audiobook: preparing failed:", tostring(err)) end
        on_done(ok, err)
    end
    local poll
    local function nextTrack()
        i = i + 1
        local t = todo[i]
        if not t then return finish(true) end
        prog = Audiobook.startConversion(dir, t)
        last_change = os.time()
        UIManager:scheduleIn(1, poll)
    end
    poll = function()
        local t = todo[i]
        local f = io.open(prog, "rb")
        local text = f and f:read("*l")
        if f then f:close() end
        if text and text ~= last_text then last_text, last_change = text, os.time() end
        local d = text and tonumber(text:match("^(%d+) %d+$"))
        if d then state.done = math.min(total, before + d) end
        if d and dialog then dialog:reportProgress(state.done) end
        local err = text and text:match("^error (.*)$")
        if err then return finish(false, err) end
        if text and text:match("^done") then
            local c = readChunks(dir, t)
            if not c then return finish(false, "no index") end
            before = before + (t.size or lfs.attributes(dir .. "/" .. t.file, "size") or 0)
            os.remove(dir .. "/" .. t.file) -- the M4B itself isn't needed any more
            os.remove(prog); os.remove(prog .. ".exit")
            return nextTrack()
        end
        local ef = io.open(prog .. ".exit", "rb")
        if ef then
            local code = ef:read("*l"); ef:close()
            return finish(false, "the conversion stopped (exit " .. tostring(code) .. ")")
        end
        if os.time() - last_change > 300 then return finish(false, "no progress for 5 minutes") end
        UIManager:scheduleIn(1, poll)
    end
    nextTrack()
end

--- Download an audiobook (all tracks) in a background process, resuming
--- interrupted transfers, then prepare M4B audio for the Kindle.
--- on_done(book|nil, err).
function Audiobook.download(plugin, summary, on_done, attempt, info)
    attempt = attempt or 1
    local api = plugin.api
    if not info then
        -- the audiobook's details (and a fresh login) in the background
        return require("gzreader_async").call(api, "audiobookInfo", { summary.id }, function(got, err)
            if not got then return on_done(nil, err) end
            Audiobook.download(plugin, summary, on_done, attempt, got)
        end)
    end
    local book = Audiobook.describe(summary.id, info, summary.primaryFileName)
    book.title = book.title or summary.title
    local dir = Audiobook.dir(plugin, summary.id)
    mkdirp(dir)
    local total = 0
    for _i, t in ipairs(book.tracks) do total = total + (t.size or 0) end
    Log.info("audiobook download start", summary.id, #book.tracks, "files", total, "bytes", "attempt", attempt)
    pcall(require("gzreader_recovery").audioStarted, plugin, summary, "download") -- picked up after a restart
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        api.no_refresh = true
        for _i, t in ipairs(book.tracks) do
            local final = dir .. "/" .. t.file
            if lfs.attributes(final, "mode") ~= "file" and not readChunks(dir, t) then
                local part = final .. ".part"
                local tries, last_size = 0, -1
                while true do
                    local dok, derr, retry = api:downloadAudio(summary.id, book.folder and t.index or nil, part)
                    if dok then break end
                    local size = lfs.attributes(part, "size") or 0
                    if size > last_size then tries = 0 else tries = tries + 1 end -- count only tries with no progress
                    last_size = size
                    if not retry or derr == "http_401" or tries >= 5 then
                        ffiutil.writeToFD(wfd, "err " .. tostring(derr) .. (retry and " (resumable)" or ""), true)
                        return
                    end
                    ffiutil.sleep(math.min(30, 3 * (tries + 1)))
                end
                os.rename(part, final)
            end
        end
        ffiutil.writeToFD(wfd, "ok", true)
    end, true)
    if not pid then return on_done(nil, "could not start the download") end
    local awake_key = "audiobook-download-" .. tostring(summary.id)
    Awake.hold(awake_key)
    require("gzreader_net").hold(awake_key)
    local dialog
    local state = { kind = "audiobook", title = book.title or summary.title, total = total, done = 0 }
    state.open_dialog = function()
        if dialog then return end
        dialog = ProgressbarDialog:new{
            title = T(_("Downloading “%1”…"), book.title or ""),
            subtitle = _("Press any key to hide; the download continues and the Kindle stays awake."),
            progress_max = total > 0 and total or nil, refresh_time_seconds = 2,
        }
        dialog.dismiss_callback = function() dialog = nil end
        dialog:show()
        dialog:reportProgress(state.done)
    end
    Audiobook.active_download = state
    pcall(function() require("gzreader_tasks").changed() end)
    state.open_dialog()
    local function poll()
        local have = 0
        for _i, t in ipairs(book.tracks) do
            local p = dir .. "/" .. t.file
            have = have + (lfs.attributes(p, "size") or lfs.attributes(p .. ".part", "size")
                or (readChunks(dir, t) and (t.size or 0)) or 0)
        end
        state.done = total > 0 and math.min(have, total) or have
        if dialog then dialog:reportProgress(state.done) end
        if not ffiutil.isSubProcessDone(pid) then return UIManager:scheduleIn(1, poll) end
        Awake.release(awake_key)
        require("gzreader_net").release(awake_key)
        Audiobook.active_download = nil
        pcall(function() require("gzreader_tasks").changed() end)
        if dialog then dialog.dismiss_callback = nil; UIManager:close(dialog); dialog = nil end
        local res = ffiutil.readAllFromFD(fd)
        if res ~= "ok" then
            Log.warn("audiobook download failed", summary.id, res)
            if res:find("(resumable)", 1, true) and attempt < 4 then
                -- e.g. the login expired during a long download: refresh it and carry on
                return UIManager:scheduleIn(2, function() Audiobook.download(plugin, summary, on_done, attempt + 1) end) -- info again: refreshes the login
            end
            return on_done(nil, (res:match("^err (.*)$") or res):gsub(" %(resumable%)", ""))
        end
        Log.info("audiobook downloaded", summary.id)
        pcall(require("gzreader_recovery").audioStarted, plugin, summary, "prepare")
        Audiobook.prepare(dir, book.tracks, book.title, function(pok, perr)
            if not pok then return on_done(nil, T(_("Couldn't prepare the audio for the Kindle: %1"), tostring(perr))) end
            Audiobook.finishLayout(dir, book)
            local f = io.open(dir .. "/audiobook.json", "wb")
            if f then f:write(JSON.encode(book)); f:close() end
            plugin.store.audiobooks = plugin.store.audiobooks or {}
            plugin.store.audiobooks[book.id] = { title = book.title, author = book.author }
            plugin:save()
            pcall(Folder.ensureEntry, plugin)
            pcall(require("gzreader_recovery").audioDone, plugin, summary.id)
            on_done(Audiobook.load(plugin, summary.id))
        end)
    end
    UIManager:scheduleIn(1, poll)
end

--- Record converted tracks in the book description (files list -> chunk files).
function Audiobook.finishLayout(dir, book)
    for i, t in ipairs(book.tracks) do
        local c = readChunks(dir, t)
        if c then
            t.chunks = { dir = c.dir, starts = c.starts }
            if (t.durationMs or 0) == 0 then t.durationMs = c.durationMs end
            book.files[i] = c.dir .. "/c0.aac"
        end
    end
end

---------------------------------------------------------------- player

local Player = {}
Player.__index = Player
Audiobook.Player = Player

function Player:new(plugin, book)
    plugin.store.audiobooks = plugin.store.audiobooks or {}
    local saved = plugin.store.audiobooks[book.id] or {}
    return setmetatable({ plugin = plugin, book = book, pos = tonumber(saved.pos_ms) or 0,
        playing = false, last_push = 0 }, self)
end

function Player:globalPos()
    if self.playing or Engine.isPaused() then
        local t = self.book.tracks[self.track or 1]
        return (t and t.start or 0) + Engine.position()
    end
    return self.pos
end

function Player:save()
    local entry = self.plugin.store.audiobooks[self.book.id] or {}
    entry.pos_ms = math.floor(self:globalPos())
    entry.updated = os.time()
    self.plugin.store.audiobooks[self.book.id] = entry
    self.plugin:save()
end

--- Grimmory progress body (same fields as Grimmory's web player).
function Player:progressBody()
    local g = self:globalPos()
    local track, in_track = Audiobook.locate(self.book, g)
    local total = Audiobook.total(self.book)
    local fp = {
        bookFileId = self.book.file_id,
        positionData = tostring(math.floor(self.book.folder and in_track or g)),
        progressPercent = total > 0 and math.floor(g / total * 1000 + 0.5) / 10 or 0,
    }
    if self.book.folder then fp.positionHref = tostring(self.book.tracks[track].index or (track - 1)) end
    return { fileProgress = fp }
end

function Player:push()
    if not self.book.file_id or self.plugin.store.sync_disabled or not self.plugin.api:isPaired() then return end
    local body = self:progressBody()
    self.last_push = os.time()
    -- sent in the background (never on the screen's thread)
    self.plugin:queue("progress", self.book.id, body)
    if NetworkMgr:isConnected() then self.plugin:flushPending() end
end

--- Offer Grimmory's position when it differs from ours by more than a minute.
function Player:pull(on_done)
    if not (self.plugin.api:isPaired() and NetworkMgr:isConnected()) then return on_done() end
    if not self._pulled then
        return require("gzreader_async").call(self.plugin.api, "getBook", { self.book.id }, function(remote)
            self._pulled = remote or false
            self:pull(on_done)
        end)
    end
    local remote = self._pulled or nil
    self._pulled = nil
    local ap = remote and remote.audiobookProgress
    local ms = ap and tonumber(ap.positionMs)
    if not ms then return on_done() end
    if self.book.folder then
        local ti = tonumber(ap.trackIndex) or 0
        for _i, t in ipairs(self.book.tracks) do
            if (t.index or 0) == ti then ms = t.start + ms; break end
        end
    end
    if math.abs(ms - self.pos) < 60000 then return on_done() end
    UIManager:show(ConfirmBox:new{
        text = T(_("Grimmory has this audiobook at %1 (here: %2). Continue from there?"), Audiobook.fmt(ms), Audiobook.fmt(self.pos)),
        ok_text = _("Use Grimmory's"), cancel_text = _("Keep this"),
        ok_callback = function() self.pos = ms; on_done() end,
        cancel_callback = function() on_done() end,
    })
end


--- Record converted tracks in audiobook.json.
function Player:saveLayout()
    local dir = self.book.dir
    Audiobook.finishLayout(dir, self.book)
    local f = io.open(dir .. "/audiobook.json", "wb")
    if f then
        local copy = {}
        for k, v in pairs(self.book) do if k ~= "dir" then copy[k] = v end end
        f:write(JSON.encode(copy)); f:close()
    end
end

--- What the engine plays for track `t`, and its format family (nil while
--- the track is still being prepared).
function Player:source(t, in_track)
    local dir = self.book.dir
    if not t.chunks and needsConversion(t) then
        -- downloaded before GZreader 1.0.13 (or preparing was interrupted)
        if not readChunks(dir, t) then
            if self.preparing then return nil end
            self.preparing = true
            Audiobook.prepare(dir, self.book.tracks, self.book.title, function(ok, err)
                self.preparing = nil
                if not ok then
                    UIManager:show(InfoMessage:new{ text = T(_("Couldn't prepare the audio for the Kindle: %1"), tostring(err)) })
                    return
                end
                self:saveLayout()
                self:play()
                if self.screen then self.screen:refresh() end
            end)
            return nil
        end
        self:saveLayout()
    end
    if t.chunks then
        return { kind = "chunks", dir = dir .. "/" .. t.chunks.dir, starts = t.chunks.starts, offset_ms = in_track }, "aac"
    end
    local path = dir .. "/" .. t.file
    return { kind = "file", path = path, offset_ms = in_track, size = t.size or lfs.attributes(path, "size"),
        duration_ms = t.durationMs }, Engine.format(path)
end

function Player:play()
    local g = self.pos
    local track, in_track = Audiobook.locate(self.book, g)
    local t = self.book.tracks[track]
    local src, fmt = self:source(t, in_track)
    if not src then return false end
    local p = Engine.chosen(fmt)
    if not p then
        UIManager:show(ConfirmBox:new{
            text = T(_("No player has been found yet for %1 audio on this Kindle. Run the audio test now?"), (fmt or "?"):upper()),
            ok_text = _("Test audio"),
            ok_callback = function() Engine.test(function() if Engine.chosen(fmt) then self:play() end end) end,
        })
        return false
    end
    local started = select(2, Engine.play(p, src))
    self.pos = t.start + (started or 0)
    self.track = track
    self.playing = true
    Audiobook.current = self
    self:keepAwake(true)
    self:schedule()
    return true
end

function Player:pause()
    if not self.playing then return end
    Engine.pause()
    self.pos = self:globalPos()
    self.playing = false
    self:keepAwake(false)
    self:save()
    self:push()
end

function Player:resume()
    if self.playing then return end
    if Engine.isPaused() then
        Engine.resume()
        self.playing = true
        self:keepAwake(true)
        self:schedule()
    else
        self:play()
    end
end

function Player:toggle()
    if self.playing then self:pause() else self:resume() end
end

function Player:stop()
    if self.playing or Engine.isPaused() then self.pos = self:globalPos() end
    Engine.stop()
    self.playing = false
    self:keepAwake(false)
    self:cancelSleep()
    if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
    self:save()
    self:push()
    if Audiobook.current == self then Audiobook.current = nil end
end

function Player:seekTo(g)
    local total = Audiobook.total(self.book)
    g = math.max(0, math.min(total > 0 and total - 1000 or g, g))
    local was_playing = self.playing
    Engine.stop()
    self.playing = false
    self.pos = g
    if was_playing then self:play() end
    self:save()
end

function Player:skip(delta_ms) self:seekTo(self:globalPos() + delta_ms) end

function Player:chapterStep(dir)
    local chapters = self.book.chapters or {}
    if #chapters == 0 then return self:skip(dir * 5 * 60000) end
    local g = self:globalPos()
    local idx = Audiobook.chapterAt(self.book, g)
    if dir < 0 and g - (chapters[idx].startTimeMs or 0) > 3000 then
        return self:seekTo(chapters[idx].startTimeMs or 0) -- restart this chapter
    end
    local target = chapters[math.max(1, math.min(#chapters, idx + dir))]
    self:seekTo(target.startTimeMs or 0)
end

--- Stop the Kindle from sleeping while audio plays (KOReader's autosuspend
--- and the Kindle's own screensaver).
function Player:keepAwake(on)
    if on == self.awake then return end
    self.awake = on
    if on then Awake.hold(self) else Awake.release(self) end
end

function Player:schedule()
    if self.ticker then return end
    self.ticker = function()
        self.ticker = nil
        self:tick()
    end
    UIManager:scheduleIn(Audiobook.TICK_SECONDS, self.ticker)
end

function Player:tick()
    if not self.playing then return end
    local t = self.book.tracks[self.track]
    local in_track = Engine.position()
    local ended = not Engine.running()
        or (t.durationMs and t.durationMs > 0 and in_track >= t.durationMs + 5000)
    if ended and in_track < 4000 and not Engine.isPaused() then
        -- the player quit straight away: don't skip ahead or lose the position
        local out = Engine.log()
        Log.warn("audiobook: the player stopped at once:", out:sub(1, 400):gsub("\n", " / "))
        self.pos = t.start + in_track
        Engine.stop()
        self.playing = false
        self:keepAwake(false)
        if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
        UIManager:show(InfoMessage:new{ text = _("The audio didn't play. Run Test audiobook playback (Settings → Reader), then send the diagnostic log if it still fails.") })
        if self.screen then self.screen:refresh() end
        return
    end
    if ended then
        if self.track < #self.book.tracks then
            self.pos = self.book.tracks[self.track + 1].start
            Engine.stop()
            self.playing = false
            self:play()
        else
            self.pos = 0
            self:stop()
            Log.info("audiobook finished", self.book.id)
            UIManager:show(InfoMessage:new{ text = _("The end of the audiobook."), timeout = 4 })
            if self.screen then self.screen:refresh() end
            return
        end
    end
    if self.sleep_at and os.time() >= self.sleep_at then
        self.sleep_at = nil
        self:pause()
        UIManager:show(InfoMessage:new{ text = _("Sleep timer: paused."), timeout = 4 })
    elseif self.sleep_end_of_chapter then
        local idx = Audiobook.chapterAt(self.book, self:globalPos())
        if idx ~= self.sleep_end_of_chapter then
            self.sleep_end_of_chapter = nil
            self:pause()
            UIManager:show(InfoMessage:new{ text = _("Sleep timer: paused at the end of the chapter."), timeout = 4 })
        end
    end
    if os.time() - self.last_push >= Audiobook.PUSH_EVERY then self:save(); self:push() end
    -- KOReader's autosuspend counts input; playing audio counts as activity
    if os.time() - (self.last_activity or 0) >= 50 then
        self.last_activity = os.time()
        UIManager:broadcastEvent(Event:new("InputEvent"))
    end
    if self.screen then self.screen:refreshTime() end
    if self.playing then self:schedule() end
end

function Player:setSleep(minutes)
    self.sleep_at, self.sleep_end_of_chapter = nil, nil
    if minutes == "chapter" then
        self.sleep_end_of_chapter = Audiobook.chapterAt(self.book, self:globalPos())
    elseif minutes and minutes > 0 then
        self.sleep_at = os.time() + minutes * 60
    end
end

function Player:cancelSleep() self.sleep_at, self.sleep_end_of_chapter = nil, nil end

function Player:sleepText()
    if self.sleep_end_of_chapter then return _("Sleep: end of chapter") end
    if self.sleep_at then return T(_("Sleep in %1"), Audiobook.fmt((self.sleep_at - os.time()) * 1000)) end
    return nil
end

---------------------------------------------------------------- screen

local Screen = InputContainer:extend{ player = nil }
Audiobook.Screen = Screen

function Screen:init()
    local sw, sh = Device.screen:getWidth(), Device.screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.key_events = {
        Toggle = { { { "Press", " " } } },
        Back30 = { { "Left" } },
        Fwd30 = { { "Right" } },
        PrevChapter = { { "Up" } },
        NextChapter = { { "Down" } },
        Options = { { "Menu" } },
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        VolUp = { { "VPlus" } },
        VolDown = { { "VMinus" } },
    }
    self.player.screen = self
    self:build()
end

function Screen:text()
    local p, book = self.player, self.player.book
    local g = p:globalPos()
    local total = Audiobook.total(book)
    local ch = select(2, Audiobook.chapterAt(book, g))
    local lines = {
        book.author and (book.title .. "\n" .. book.author) or book.title,
        "",
        ch and ch.title or "",
        T("%1 / %2  (%3%)", Audiobook.fmt(g), Audiobook.fmt(total), total > 0 and math.floor(g / total * 100) or 0),
        p.playing and _("▶ Playing") or _("❚❚ Paused"),
        p:sleepText() or "",
        "",
        _("Press: play / pause   ◀ ▶: 30 s   ▲ ▼: chapter"),
        _("Menu: chapters, sleep timer, volume   Back: close (keeps playing)"),
    }
    return table.concat(lines, "\n")
end

function Screen:build()
    local sw, sh = self.dimen.w, self.dimen.h
    self.textbox = TextBoxWidget:new{
        text = self:text(),
        face = Font:getFace("cfont", 22),
        width = math.floor(sw * 0.88),
        alignment = "center",
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh },
            VerticalGroup:new{ align = "center", self.textbox, VerticalSpan:new{ width = 1 } } },
    }
end

function Screen:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function Screen:refreshTime()
    -- e-ink: redraw the time every 30 s only (each redraw costs battery)
    local now = os.time()
    if now - (self.last_time_redraw or 0) >= 30 then
        self.last_time_redraw = now
        self:build(); UIManager:setDirty(self, "fast")
    end
end

function Screen:onToggle() self.player:toggle(); self:refresh(); return true end
function Screen:onBack30() self.player:skip(-Audiobook.SKIP_MS); self:refresh(); return true end
function Screen:onFwd30() self.player:skip(Audiobook.SKIP_MS); self:refresh(); return true end
function Screen:onPrevChapter() self.player:chapterStep(-1); self:refresh(); return true end
function Screen:onNextChapter() self.player:chapterStep(1); self:refresh(); return true end
function Screen:onVolUp() Engine.setVolume(Engine.volume() + 1); return true end
function Screen:onVolDown() Engine.setVolume(Engine.volume() - 1); return true end
function Screen:onClose() UIManager:close(self); return true end
function Screen:onCloseWidget() if self.player.screen == self then self.player.screen = nil end end

function Screen:onOptions()
    local p = self.player
    local dialog
    local function close() UIManager:close(dialog) end
    dialog = ButtonDialog:new{
        title = p.book.title,
        buttons = {
            { { text = _("Chapters"), callback = function() close(); self:showChapters() end } },
            { { text = _("Sleep 15 min"), callback = function() close(); p:setSleep(15); self:refresh() end },
              { text = _("30 min"), callback = function() close(); p:setSleep(30); self:refresh() end },
              { text = _("60 min"), callback = function() close(); p:setSleep(60); self:refresh() end } },
            { { text = _("Sleep at end of chapter"), callback = function() close(); p:setSleep("chapter"); self:refresh() end },
              { text = _("Sleep off"), callback = function() close(); p:cancelSleep(); self:refresh() end } },
            { { text = _("Quieter"), callback = function() Engine.setVolume(Engine.volume() - 1) end },
              { text = _("Louder"), callback = function() Engine.setVolume(Engine.volume() + 1) end } },
            { { text = _("Stop and close"), callback = function() close(); p:stop(); UIManager:close(self) end } },
        },
    }
    UIManager:show(dialog)
    return true
end

function Screen:showChapters()
    local p = self.player
    local items = {}
    local cur = Audiobook.chapterAt(p.book, p:globalPos())
    for i, c in ipairs(p.book.chapters or {}) do
        items[#items + 1] = {
            text = (i == cur and "▶ " or "") .. (c.title or T(_("Chapter %1"), i)),
            mandatory = Audiobook.fmt(c.startTimeMs),
            callback = function() p:seekTo(c.startTimeMs or 0); self:refresh() end,
        }
    end
    if #items == 0 then items[1] = { text = _("This audiobook has no chapters."), select_enabled = false } end
    local menu
    menu = Menu:new{
        title = _("Chapters"), item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = true, title_bar_fm_style = true,
        onMenuChoice = function(_m, item) UIManager:close(menu); if item.callback then item.callback() end return true end,
    }
    menu:onGotoPage(menu:getPageNumber(cur))
    UIManager:show(menu)
end

--- Open (or bring back) the player for a downloaded audiobook.
function Audiobook.open(plugin, book)
    local p = Audiobook.current
    if not (p and p.book.id == book.id) then
        if p then p:stop() end
        p = Player:new(plugin, book)
    end
    local screen = Screen:new{ player = p }
    UIManager:show(screen)
    if not p.playing and not Engine.isPaused() then
        p:pull(function() p:play(); screen:refresh() end)
    end
    return screen
end

--- From the Grimmory browser: open if downloaded, else offer to download.
function Audiobook.choose(plugin, summary)
    local book = Audiobook.load(plugin, summary.id)
    if book then return Audiobook.open(plugin, book) end
    local size_kb = tonumber(summary.fileSizeKb)
    UIManager:show(ConfirmBox:new{
        text = T(_("Download the audiobook “%1” to this Kindle?"), summary.title or "")
            .. (size_kb and ("\n" .. string.format("%.0f MB", size_kb / 1024)) or ""),
        ok_text = _("Download & listen"),
        ok_callback = function()
            NetworkMgr:runWhenOnline(function()
                Audiobook.download(plugin, summary, function(b, err)
                    if b then Audiobook.open(plugin, b) else plugin:showError(err) end
                end)
            end)
        end,
    })
end

--- Downloaded audiobooks, for the Grimmory menu.
function Audiobook.downloaded(plugin)
    local list = {}
    for id, e in pairs(plugin.store.audiobooks or {}) do
        local b = Audiobook.load(plugin, id)
        if b then list[#list + 1] = { book = b, pos = e.pos_ms, updated = e.updated or 0 } end
    end
    table.sort(list, function(a, b) return a.updated > b.updated end)
    return list
end

--- Delete a downloaded audiobook from the Kindle (Grimmory keeps it and
--- the listening position).
function Audiobook.delete(plugin, book_id)
    local cur = Audiobook.current
    if cur and tostring(cur.book.id) == tostring(book_id) then cur:stop() end
    local dir = Audiobook.dir(plugin, book_id)
    pcall(function() require("gzreader_recovery").stopConversions(dir) end)
    if lfs.attributes(dir, "mode") == "directory" then
        ffiutil.purgeDir(dir)
    end
    if plugin.store.audiobooks then
        plugin.store.audiobooks[book_id] = nil
        plugin.store.audiobooks[tonumber(book_id) or book_id] = nil
        plugin.store.audiobooks[tostring(book_id)] = nil
    end
    plugin:save()
    Log.info("audiobook deleted", book_id)
end

--- The downloaded audiobooks: pick one to listen to (Downloads → Audiobooks).
function Audiobook.showDownloaded(plugin)
    local menu
    local function build()
        local items = {}
        local list = Audiobook.downloaded(plugin)
        for _i, e in ipairs(list) do
            local playing = Audiobook.current and Audiobook.current.book.id == e.book.id
            items[#items + 1] = {
                text = (playing and "▶ " or "") .. (e.book.title or "?"),
                mandatory = (e.pos and e.pos > 0) and (Audiobook.fmt(e.pos) .. " / " .. Audiobook.fmt(Audiobook.total(e.book)))
                    or Audiobook.fmt(Audiobook.total(e.book)),
                callback = function()
                    UIManager:close(menu)
                    Audiobook.open(plugin, e.book)
                end,
            }
        end
        if #items == 0 then
            items[1] = { text = _("No audiobooks on this Kindle yet. Download them from the Grimmory tab → Audiobooks."),
                select_enabled = false }
        else
            items[#items].separator = true
            items[#items + 1] = { text = _("Delete an audiobook from this Kindle…"), callback = function()
                local buttons = {}
                local dialog
                for _i, e in ipairs(list) do
                    buttons[#buttons + 1] = { { text = e.book.title or "?", align = "left", callback = function()
                        UIManager:close(dialog)
                        UIManager:show(ConfirmBox:new{
                            text = T(_("Delete the audiobook “%1” from this Kindle?\n\nGrimmory keeps it and your listening position."),
                                e.book.title or "?"),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                Audiobook.delete(plugin, e.book.id)
                                menu:switchItemTable(nil, build())
                            end,
                        })
                    end } }
                end
                buttons[#buttons + 1] = { { text = _("Cancel"), callback = function() UIManager:close(dialog) end } }
                dialog = ButtonDialog:new{ title = _("Delete which audiobook?"), buttons = buttons }
                UIManager:show(dialog)
            end }
        end
        return items
    end
    menu = Menu:new{
        title = _("Audiobooks"),
        item_table = build(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
    }
    UIManager:show(menu)
    return menu
end

return Audiobook
