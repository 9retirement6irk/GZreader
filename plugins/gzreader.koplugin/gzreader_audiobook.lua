--[[--
Grimmory audiobooks on the Kindle: download, listen, chapters, sleep timer,
progress synced with Grimmory's own audiobook progress (the web player's).
Or Plex's (Settings → Connections → Plex → Audiobooks): an album of a Plex
library is a book (id "plex-<album key>", book.plex = { key, thumb }), its
tracks the book's files (gzreader_plex.lua Plex:audiobookInfo), and the
listening position goes to the track's place in Plex (Plex:setProgress),
read back from the track listened to last (Plex:audiobookPosition).

Storage: <GZreader folder>/.audiobooks/<book id>/ with the audio file(s) and
audiobook.json (Grimmory's info: duration, chapters, tracks). Hidden: a long
book is thousands of 15-second chunk files, which file lists, folder covers
and file search would otherwise walk through. The visible
<GZreader folder>/Audiobooks folder holds a small stand-in book file per
audiobook, shown as a tile and in Recent (gzreader_abfolder.lua).

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
local JSON = require("gzreader_json")
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
local Touch = require("gzreader_touch")
local _ = require("gettext")
local T = ffiutil.template

local Audiobook = {
    SAVE_EVERY = 60,       -- seconds between saving the position on the Kindle while playing
    PUSH_EVERY = 300,      -- …and sending it to Grimmory (each send is an HTTPS request in
                           -- a helper process: seconds of a Kindle 3's CPU; pause, stop and
                           -- closing the player send it too)
    SKIP_MS = 30000,
    TICK_SECONDS = 2,      -- player housekeeping (track end, sleep timer); each wake-up costs battery
    current = nil,         -- the Player that is playing or paused
}

---------------------------------------------------------------- helpers

--- "10 h 28 min" (a running time)
function Audiobook.runtime(ms)
    local mins = math.floor((ms or 0) / 60000 + 0.5)
    local h, m = math.floor(mins / 60), mins % 60
    if h > 0 then return T(_("%1 h %2 min"), h, m) end
    return T(_("%1 min"), m)
end

--- A time typed in: "1:23:45", "23:45", "90" (minutes) or "50%" (of `total`).
--- Milliseconds, or nil (pure: run_tests.lua).
function Audiobook.parseTime(text, total)
    text = tostring(text or ""):gsub("%s", "")
    local pct = text:match("^(%d+%.?%d*)%%$")
    if pct then
        return total and total > 0 and math.floor(math.min(100, tonumber(pct)) * total / 100) or nil
    end
    local a, b, c = text:match("^(%d+):(%d%d?):(%d%d?)$")
    if a then return ((tonumber(a) * 60 + tonumber(b)) * 60 + tonumber(c)) * 1000 end
    a, b = text:match("^(%d+):(%d%d?)$")
    if a then return (tonumber(a) * 60 + tonumber(b)) * 1000 end
    -- digits alone, read like a clock from the right (no colons needed):
    -- 5000 is 50:00, 13000 1:30:00, 45 0:45. (Until 1.23.8 they were minutes.)
    local digits = text:match("^(%d+)$")
    if digits and #digits <= 7 then
        local secs = tonumber(digits:sub(-2))
        local mins = #digits > 2 and tonumber(digits:sub(-4, -3)) or 0
        local hours = #digits > 4 and tonumber(digits:sub(1, -5)) or 0
        return ((hours * 60 + mins) * 60 + secs) * 1000
    end
    return nil
end

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

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", mdash = "\u{2014}",
    ndash = "\u{2013}", hellip = "\u{2026}", rsquo = "\u{2019}", lsquo = "\u{2018}", rdquo = "\u{201D}", ldquo = "\u{201C}" }

local function utf8char(n)
    n = tonumber(n)
    if not n or n < 32 or n > 0x10FFFF then return "" end
    if n < 0x80 then return string.char(n) end
    if n < 0x800 then return string.char(0xC0 + math.floor(n / 64), 0x80 + n % 64) end
    if n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 4096), 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
    end
    return string.char(0xF0 + math.floor(n / 262144), 0x80 + math.floor(n / 4096) % 64, 0x80 + math.floor(n / 64) % 64, 0x80 + n % 64)
end

--- Grimmory's description (HTML) as plain text, or nil when there is none.
function Audiobook.plainText(html)
    if type(html) ~= "string" or html:match("^%s*$") then return nil end
    local text = html:gsub("\r", "")
    if text:find("<%a") or text:find("</%a") then
        text = text:gsub("%s*\n%s*", " ")
            :gsub("<[Bb][Rr]%s*/?>", "\n")
            :gsub("</[Pp]>", "\n\n"):gsub("</[Dd][Ii][Vv]>", "\n")
            :gsub("<[Ll][Ii][^>]*>", "\n\u{2022} ")
            :gsub("<[^>]*>", "")
    end
    text = text:gsub("&#[xX](%x+);", function(h) return utf8char(tonumber(h, 16)) end)
        :gsub("&#(%d+);", utf8char)
        :gsub("&(%a+);", function(name) return ENTITIES[name] end)
    text = text:gsub("[ \t]+\n", "\n"):gsub("\n[ \t]+", "\n"):gsub("\n\n\n+", "\n\n"):gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

--- Turn Grimmory's info into our local book description.
function Audiobook.describe(book_id, info, primary_name)
    local tracks, files = {}, {}
    if info.folderBased and type(info.tracks) == "table" and #info.tracks > 0 then
        for i, t in ipairs(info.tracks) do
            local name = string.format("track-%03d.%s", i, extOf(t.fileName, "mp3"))
            files[i] = name
            tracks[i] = { file = name, index = t.index or (i - 1), durationMs = tonumber(t.durationMs) or 0,
                start = tonumber(t.cumulativeStartMs) or 0, size = tonumber(t.fileSizeBytes), title = t.title,
                plex_key = t.plexKey and tostring(t.plexKey) or nil }
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
        plex = info.plexKey and { key = tostring(info.plexKey), thumb = info.plexThumb } or nil,
        description = Audiobook.plainText(info.gz_description),
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
    local dialog
    local state = { kind = "prepare", title = title, total = total, done = 0 }
    Awake.hold(awake_key, { what = "audiobook preparing", still = function() return Audiobook.active_prepare == state end })
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
    local plex = type(summary.plex) == "table" and summary.plex.key and require("gzreader_music").plex(plugin) or nil
    if not info and plex then
        -- a Plex audiobook: its tracks and details from Plex, in the background
        return require("gzreader_async").run(nil, function() return plex:audiobookInfo(summary.plex.key) end, function(got, err)
            if not got then return on_done(nil, err) end
            Audiobook.download(plugin, summary, on_done, attempt, got)
        end, "plex audiobook")
    end
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
    local bitrate = plex and require("gzreader_plex").quality(plugin.store).bitrate
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        api.no_refresh = true
        for i, t in ipairs(book.tracks) do
            local final = dir .. "/" .. t.file
            if plex and lfs.attributes(final, "mode") ~= "file" and not readChunks(dir, t) then
                local err = Audiobook.fetchPlexTrack(plex, info.tracks[i].plexTrack, final, bitrate)
                if err then
                    ffiutil.writeToFD(wfd, "err " .. err, true)
                    return
                end
            elseif lfs.attributes(final, "mode") ~= "file" and not readChunks(dir, t) then
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
        if plex and book.plex and book.plex.thumb and lfs.attributes(dir .. "/cover.jpg", "mode") ~= "file" then
            pcall(plex.downloadThumb, plex, book.plex.thumb, dir .. "/cover.jpg", 600)
        end
        ffiutil.writeToFD(wfd, "ok", true)
    end, true)
    if not pid then return on_done(nil, "could not start the download") end
    local awake_key = "audiobook-download-" .. tostring(summary.id)
    local dialog
    local state = { kind = "audiobook", title = book.title or summary.title, total = total, done = 0 }
    Awake.hold(awake_key, { what = "audiobook download", still = function() return Audiobook.active_download == state end })
    require("gzreader_net").hold(awake_key)
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
        if plex then Audiobook.plexFiles(dir, book) end
        pcall(require("gzreader_recovery").audioStarted, plugin, summary, "prepare")
        Audiobook.prepare(dir, book.tracks, book.title, function(pok, perr)
            if not pok then return on_done(nil, T(_("Couldn't prepare the audio for the Kindle: %1"), tostring(perr))) end
            Audiobook.finishLayout(dir, book)
            local f = io.open(dir .. "/audiobook.json", "wb")
            if f then f:write(JSON.encode(book)); f:close() end
            plugin.store.audiobooks = plugin.store.audiobooks or {}
            plugin.store.audiobooks[book.id] = { title = book.title, author = book.author, plex_thumb = book.plex and book.plex.thumb or nil }
            plugin:save()
            -- its tile in Downloads → Audiobooks, then Grimmory's cover for it
            pcall(Folder.writeStub, plugin, book.id)
            pcall(Folder.fetchCover, plugin, book.id)
            pcall(require("gzreader_recovery").audioDone, plugin, summary.id)
            on_done(Audiobook.load(plugin, summary.id))
        end)
    end
    UIManager:scheduleIn(1, poll)
end

--- A Plex track into `final` (its name says the format Plex.how chose):
--- nil when it's there, or the error (" (resumable)" when trying again
--- later can help). Runs in the download's process.
function Audiobook.fetchPlexTrack(plex, track, final, bitrate)
    if type(track) ~= "table" then return "no track" end
    local base = final:gsub("%.[^./]*$", "")
    local tries, err = 0, nil
    while tries < 3 do
        local got, e = plex:downloadTrack(track, base, bitrate)
        if got then return nil end
        err = tostring(e)
        if err == "unauthorized" or err:find("transcode", 1, true) then return err end
        tries = tries + 1
        ffiutil.sleep(3 * tries)
    end
    return err .. " (resumable)"
end

--- After a Plex download: a track Plex's transcoder sent as AAC (its own
--- profile) has a .aac name instead of the .mp3 asked for.
function Audiobook.plexFiles(dir, book)
    for i, t in ipairs(book.tracks) do
        if lfs.attributes(dir .. "/" .. t.file, "mode") ~= "file" and not readChunks(dir, t) then
            local base = t.file:gsub("%.[^./]*$", "")
            for _j, ext in ipairs({ "aac", "mp3", "m4a" }) do
                if lfs.attributes(dir .. "/" .. base .. "." .. ext, "mode") == "file" then
                    t.file = base .. "." .. ext
                    book.files[i] = t.file
                    break
                end
            end
        end
    end
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
    if self.playing then
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
    pcall(Folder.saveProgress, self.plugin, self.book.id, entry.pos_ms, Audiobook.total(self.book))
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
    if self.book.plex then return self:pushPlex() end
    if not self.book.file_id or self.plugin.store.sync_disabled or not self.plugin.api:isPaired() then return end
    local body = self:progressBody()
    self.last_push = os.time()
    -- sent in the background (never on the screen's thread)
    self.plugin:queue("progress", self.book.id, body)
    -- (GZreader closing: sent at the next start)
    if NetworkMgr:isConnected() and not Audiobook.quitting then self.plugin:flushPending() end
end

--- A Plex audiobook: where it is goes to the track's place in Plex (in the
--- background; without Wi-Fi, the next push sends it).
function Player:pushPlex()
    if not NetworkMgr:isConnected() or Audiobook.quitting then return end
    local plex = require("gzreader_music").plex(self.plugin)
    if not plex:isConnected() then return end
    local track, in_track = Audiobook.locate(self.book, self:globalPos())
    local t = self.book.tracks[track]
    if not (t and t.plex_key) then return end
    self.last_push = os.time()
    require("gzreader_async").run(nil, function() return plex:setProgress(t.plex_key, in_track) end, function(ok, err)
        if not ok then Log.warn("audiobook: Plex position not sent:", tostring(err)) end
    end, "plex audiobook position")
end

--- Plex's place for book (Plex:audiobookPosition's answer) as ms from the
--- book's start, or nil. Pure.
function Audiobook.plexMs(book, pos)
    if type(pos) ~= "table" or not pos.track then return nil end
    for _i, t in ipairs(book.tracks or {}) do
        if t.plex_key == tostring(pos.track) then
            if pos.finished then return t.start + (t.durationMs or 0) end
            return t.start + (tonumber(pos.offset) or 0)
        end
    end
    return nil
end

--- A Plex audiobook: offer Plex's place (any Plex player's).
function Player:pullPlex(on_done)
    local plex = require("gzreader_music").plex(self.plugin)
    if not (NetworkMgr:isConnected() and plex:isConnected()) then return on_done() end
    require("gzreader_async").run(nil, function() return plex:audiobookPosition(self.book.plex.key) end, function(pos)
        local ms = Audiobook.plexMs(self.book, pos)
        if not ms then return on_done() end
        self:offerRemote(math.min(ms, math.max(0, Audiobook.total(self.book) - 1000)), true, on_done)
    end, "plex audiobook position")
end

--- Offer Grimmory's position when it differs from ours by more than a minute.
function Player:pull(on_done)
    if self.book.plex then return self:pullPlex(on_done) end
    -- Grimmory's progress kept when it was downloaded (syncing through a
    -- computer, no Wi-Fi now): the first opening only
    local kept = self.plugin.store.audiobooks and self.plugin.store.audiobooks[self.book.id]
    if self._pulled == nil and type(kept) == "table" and kept.grimmory_progress then
        local saved = kept.grimmory_progress
        kept.grimmory_progress = nil
        self.plugin:save()
        if not (self.plugin.api:isPaired() and NetworkMgr:isConnected()) then self._pulled = saved end
    end
    -- (asked once: 1.21.0 and older asked again and again when Grimmory
    -- didn't have the book any more, about once a second)
    if self._pulled == nil and not (self.plugin.api:isPaired() and NetworkMgr:isConnected()) then return on_done() end
    if self._pulled == nil then
        return require("gzreader_async").call(self.plugin.api, "getBook", { self.book.id }, function(remote)
            self._pulled = remote or false
            self:pull(on_done)
        end)
    end
    local remote = self._pulled or nil
    self._pulled = nil
    if remote then self:noteDetails(remote) end
    local ap = remote and remote.audiobookProgress
    local ms = ap and tonumber(ap.positionMs)
    if not ms then return on_done() end
    if self.book.folder then
        local ti = tonumber(ap.trackIndex) or 0
        for _i, t in ipairs(self.book.tracks) do
            if (t.index or 0) == ti then ms = t.start + ms; break end
        end
    end
    self:offerRemote(ms, false, on_done)
end

--- The place Grimmory (or Plex) has, ms: taken when nothing was listened to
--- here yet, offered when it's more than a minute away from ours.
function Player:offerRemote(ms, plex, on_done)
    if math.abs(ms - self.pos) < 60000 then return on_done() end
    if self.pos < 1000 then
        -- nothing listened to here yet (just downloaded): Grimmory's place, no question
        Log.info("audiobook", self.book.id, plex and "starts at Plex's place" or "starts at Grimmory's place", ms)
        self.pos = ms
        UIManager:show(InfoMessage:new{ text = plex and T(_("Continuing from %1 (Plex)."), Audiobook.fmt(ms))
            or T(_("Continuing from %1 (Grimmory)."), Audiobook.fmt(ms)), timeout = 2 })
        return on_done()
    end
    UIManager:show(ConfirmBox:new{
        text = plex and T(_("Plex has this audiobook at %1 (here: %2). Continue from there?"), Audiobook.fmt(ms), Audiobook.fmt(self.pos))
            or T(_("Grimmory has this audiobook at %1 (here: %2). Continue from there?"), Audiobook.fmt(ms), Audiobook.fmt(self.pos)),
        ok_text = plex and _("Use Plex's") or _("Use Grimmory's"), cancel_text = _("Keep this"),
        ok_callback = function() self.pos = ms; on_done() end,
        cancel_callback = function() on_done() end,
    })
end


--- Keep Grimmory's description of the book (audiobooks downloaded before
--- GZreader 1.6.2 don't have it; it can also change on the server).
function Player:noteDetails(remote)
    local m = type(remote) == "table" and remote.metadata
    local desc = type(m) == "table" and Audiobook.plainText(m.description)
    if not desc or desc == self.book.description then return end
    self.book.description = desc
    pcall(self.saveLayout, self)
    pcall(Folder.writeStub, self.plugin, self.book.id) -- Home shows it
    if self.screen then self.screen:refresh() end
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
    -- (one thing at a time: music pauses)
    local Music = package.loaded["gzreader_music"]
    if Music then pcall(Music.pauseAll) end
    local started = select(2, Engine.play(p, src))
    self.pos = t.start + (started or 0)
    self.track = track
    self.playing = true
    self.paused = nil
    Audiobook.current = self
    -- headphones unplugged: pause rather than play out loud
    pcall(function() require("gzreader_jack").watch("audiobook", function()
        self:pause()
        UIManager:show(InfoMessage:new{ text = _("Headphones unplugged: audiobook paused."), timeout = 3 })
        if self.screen then self.screen:refresh() end
    end) end)
    self:keepAwake(true)
    self:schedule()
    return true
end

--- Pause: the player is stopped (its place kept) rather than suspended. The
--- Kindle 3's sound pipeline doesn't come back from a suspended player, and a
--- stopped one frees the sound device (read aloud can speak).
function Player:pause()
    self.pull_gen = (self.pull_gen or 0) + 1 -- (a start still on its way: not any more)
    if not self.playing then return end
    pcall(function() require("gzreader_jack").unwatch("audiobook") end)
    self.pos = self:globalPos()
    Engine.stop()
    self.playing = false
    self.paused = true
    if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
    self:keepAwake(false)
    Log.info("audiobook: paused at", Audiobook.fmt(self.pos))
    self:save()
    self:push()
end

--- Play again from where it was paused.
function Player:resume()
    if self.playing then return end
    self:play()
end

function Player:toggle()
    if self.playing then self:pause() else self:resume() end
end

function Player:stop()
    pcall(function() require("gzreader_jack").unwatch("audiobook") end)
    -- (only its own player: a paused audiobook mustn't stop music playing)
    if self.playing then
        self.pos = self:globalPos()
        Engine.stop()
    end
    self.playing = false
    self.paused = nil
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
    if was_playing and not self:play() then self:keepAwake(false) end
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
    -- (still: playing. Until 1.23.8 a skip whose playing didn't start again
    -- kept the Kindle awake for good)
    if on then Awake.hold(self, { what = "audiobook", still = function() return self.playing == true end })
    else Awake.release(self) end
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
    local stopped = not Engine.running()
    local ended = stopped
        or (t.durationMs and t.durationMs > 0 and in_track >= t.durationMs + 5000)
    -- The player quit on its own: straight away (it couldn't play), or well
    -- before the end of the track. Not the end of the book: keep the position.
    local played = Engine.played()
    local early = stopped and (played < 4000
        or (t.durationMs and t.durationMs > 0 and in_track < t.durationMs - 30000))
    if early then
        local out = Engine.log()
        Log.warn("audiobook: the player stopped after", math.floor(played), "ms at", math.floor(in_track),
            "of", tostring(t.durationMs), "ms:", out:sub(1, 400):gsub("\n", " / "))
        self.pos = t.start + in_track
        Engine.stop()
        self.playing = false
        self:keepAwake(false)
        if self.ticker then UIManager:unschedule(self.ticker); self.ticker = nil end
        self:save()
        UIManager:show(InfoMessage:new{ text = played < 4000
            and _("The audio didn't play. Run Test audiobook playback (Settings → Reader), then send the log (Menu → Diagnostics) if it still fails.")
            or _("The audio stopped unexpectedly. Your place is kept. If it keeps happening, send the log (Menu → Diagnostics).") })
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
    if os.time() - (self.last_save or 0) >= Audiobook.SAVE_EVERY then
        self.last_save = os.time()
        self:save()
    end
    if os.time() - self.last_push >= Audiobook.PUSH_EVERY then self:push() end
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

-- widgets only the screen needs: loaded when it is drawn
local HorizontalGroup, HorizontalSpan, Size, TextWidget
local function screenWidgets()
    HorizontalGroup = HorizontalGroup or require("ui/widget/horizontalgroup")
    HorizontalSpan = HorizontalSpan or require("ui/widget/horizontalspan")
    Size = Size or require("ui/size")
    TextWidget = TextWidget or require("ui/widget/textwidget")
end

local Screen = InputContainer:extend{ player = nil, covers_fullscreen = true,
    gz_player = true } -- (no flashes inside it on a Kindle 3, gzreader_eink)
Audiobook.Screen = Screen

--[[ The player screen (Kindle Keyboard first):

    cover
    title / author
    Chapter n of N · chapter title
    ───────────── book progress
    0:12:30 of 0:25:00 in this chapter        1:23:45 / 9:52:00 · 14%
    ▶ Playing · Sleep in 25:00

    [Q Chapters] [W Sleep: off]  [E Stop]
    [A Quieter]  Volume 10 / 15  [S Louder]

    5-way: from key to key (it starts on play / pause) · Press: that key
    · D: about this book · Back: close (keeps playing)
    (Kindles with a 5-way and no touch screen; on the others ◀ ▶ skip 30 s
    and ▲ ▼ change chapter)
]]

--- The 5-way moves between the keys (Kindle 2, 3, 4, DX: no touch screen).
local function fiveWay() return Device:hasDPad() and not Device:isTouchDevice() end
Screen.ROWS = { 5, 4, 2 }   -- transport · chapters / sleep / stop / go to · volume − +

--- The focus after an arrow (pure: run_tests.lua): rows of different
--- lengths keep it where it was across the screen.
function Screen.move(focus, dir, rows)
    rows = rows or Screen.ROWS
    local r, c = focus[1], focus[2]
    if dir == "Left" then c = math.max(1, c - 1)
    elseif dir == "Right" then c = math.min(rows[r], c + 1)
    elseif dir == "Up" or dir == "Down" then
        local nr = math.max(1, math.min(#rows, r + (dir == "Up" and -1 or 1)))
        if nr ~= r then
            c = math.min(rows[nr], math.floor((c - 0.5) * rows[nr] / rows[r]) + 1)
            r = nr
        end
    end
    return { r, c }
end

function Screen:init()
    screenWidgets()
    local sw, sh = Device.screen:getWidth(), Device.screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.key_events = {
        Toggle = { { { "Press", " " } } },
        Back30 = { { "Left" } },
        Fwd30 = { { "Right" } },
        PrevChapter = { { "Up" } },
        NextChapter = { { "Down" } },
        Chapters = { { "Q" } },
        PrevChapterKey = { { "Z" } },
        Back30Key = { { "X" } },
        ToggleKey = { { "C" } },
        Fwd30Key = { { "V" } },
        NextChapterKey = { { "B" } },
        GoTo = { { "R" } },
        Sleep = { { "W" } },
        StopClose = { { "E" } },
        VolDown = { { "A" } },
        VolUp = { { "S" } },
        Options = { { "Menu" } },
        Home = { { "Home" } },
        Description = { { "D" } },
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
    }
    if fiveWay() then
        -- the 5-way goes from key to key; Press uses the one it's on (play / pause to start)
        self.key_events.Back30, self.key_events.Fwd30, self.key_events.PrevChapter, self.key_events.NextChapter = nil, nil, nil, nil
        self.key_events.Toggle = { { " " } }
        self.key_events.FocusMove = { { { "Left", "Right", "Up", "Down" } } }
        self.key_events.FocusPress = { { "Press" } }
        self.focus = self.focus or { 1, 3 }
    end
    self.player.screen = self
    self:loadCover()
    self:build()
end

--- The audiobook's cover (Grimmory's), shrunk to fit the top of the screen.
function Screen:loadCover()
    local book = self.player.book
    local path = book.dir and (book.dir .. "/cover.jpg")
    local f = path and io.open(path, "rb")
    if not f then
        -- not here yet: fetch it (when Wi-Fi is up) and redraw
        pcall(Folder.fetchCover, self.player.plugin, book.id, function()
            if self.player.screen == self then self:loadCover(); self:refresh() end
        end)
        return
    end
    local data = f:read("*a")
    f:close()
    local RenderImage = require("ui/renderimage")
    local ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    if not ok or not bb then return end
    local sw, sh = self.dimen.w, self.dimen.h
    local max_w, max_h = math.floor(sw * 0.66), math.floor(sh * 0.40)
    local scale = math.min(max_w / bb:getWidth(), max_h / bb:getHeight())
    if self.cover_bb then self.cover_bb:free() end
    self.cover_bb = RenderImage:scaleBlitBuffer(bb, math.floor(bb:getWidth() * scale), math.floor(bb:getHeight() * scale), true)
end

local function face(size, bold) return Font:getFace(bold and "smalltfont" or "cfont", size) end

--- A control: its letter key in a square, and the label in a box (tap works too).
function Screen:control(key, label, callback, width)
    local Button = require("ui/widget/button")
    -- (the letter only where there's a keyboard; on the Kindle Touch: just the button)
    local side = Touch.keys() and Device.screen:scaleBySize(26) or 0
    local btn = Button:new{
        text = label, callback = callback, width = width - side - (side > 0 and Size.padding.default or 0),
        bordersize = Size.border.thin, radius = Size.radius.button, text_font_size = 16,
        text_font_bold = false, show_parent = self,
    }
    if side == 0 then return btn end
    local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = side, h = side }, key, "square")
    return HorizontalGroup:new{ align = "center", sc, HorizontalSpan:new{ width = Size.padding.default }, btn }
end

function Screen:build()
    local p, book = self.player, self.player.book
    local sw, sh = self.dimen.w, self.dimen.h
    local inner = math.floor(sw * 0.88)
    local g = self.skip_target or p:globalPos()   -- (skips still being gathered: where they'll land)
    local total = Audiobook.total(book)
    local ch_idx, ch = Audiobook.chapterAt(book, g)
    local chapters = book.chapters or {}
    local group = VerticalGroup:new{ align = "center" }
    local function add(w) group[#group + 1] = w end
    local function gap(px) add(VerticalSpan:new{ width = Device.screen:scaleBySize(px) }) end

    -- the audiobook as a cassette tape: its title, author and running time
    -- on the label, the tape going from reel to reel through the book
    -- (gzreader_deck.lua; 1.23.6: was the walkman, which stays on the shelf)
    local Deck = require("gzreader_deck")
    local tape_w = math.min(inner, math.floor(sh * 0.36 / Deck.Cassette.RATIO))
    add(Deck.Cassette:new{ w = tape_w, state = {
        title = book.title,
        author = book.author,
        runtime = total > 0 and Audiobook.runtime(total) or nil,
        progress = total > 0 and g / total or 0,
        cover_bb = self.cover_bb,
    } })
    gap(10)
    if ch then
        -- "Chapter 4: On the Trail · 4 of 12" (titles often say "Chapter" already)
        local count = #chapters > 1 and T(_("%1 of %2"), ch_idx, #chapters) or nil
        local title = ch.title and ch.title ~= "" and ch.title or (count and T(_("Chapter %1"), ch_idx))
        add(TextWidget:new{ text = (count and title) and (title .. "  ·  " .. count) or (title or ""),
            face = face(17, true), max_width = inner })
    end
    gap(8)
    local ch_start = ch and (ch.startTimeMs or 0) or 0
    local nxt = chapters[ch_idx + 1]
    local ch_end = nxt and nxt.startTimeMs or total
    local ch_len = math.max(1, ch_end - ch_start)
    -- the whole book: its page edges, a ribbon where you are (as on Home)
    local okp, BookProgress = pcall(require, "common/ui/book_progress")
    if okp and BookProgress.edges then
        add(BookProgress.edges(total > 0 and g / total or 0, inner, Device.screen:scaleBySize(14)))
    else
        add(require("ui/widget/progresswidget"):new{ width = inner, height = Device.screen:scaleBySize(10),
            percentage = total > 0 and math.min(1, g / total) or 0, ticks = nil })
    end
    gap(4)
    local left = TextWidget:new{ text = T(_("%1 of %2"), Audiobook.fmt(g - ch_start), Audiobook.fmt(ch_len)), face = face(14) }
    local right = TextWidget:new{ text = T("%1 / %2 · %3%", Audiobook.fmt(g), Audiobook.fmt(total),
        total > 0 and math.floor(g / total * 100) or 0), face = face(14) }
    add(HorizontalGroup:new{ left, HorizontalSpan:new{ width = math.max(0, inner - left:getSize().w - right:getSize().w) }, right })
    -- (playing or paused: the walkman's ▶ / ❚❚ and its play key, down while playing)
    gap(14)
    -- the walkman's keys (gzreader_skeuo.lua): transport, then the rest
    local Skeuo = require("gzreader_skeuo")
    local function keys(defs, h)
        local n = #defs
        local gapw = Device.screen:scaleBySize(6)
        local kw = math.floor((inner - (n - 1) * gapw) / n)
        local rowg = HorizontalGroup:new{ align = "center" }
        for k, d in ipairs(defs) do
            if k > 1 then rowg[#rowg + 1] = HorizontalSpan:new{ width = gapw } end
            rowg[#rowg + 1] = Skeuo.Key:new{ w = kw, h = h, label = d[1], letter = d[2] and Touch.keys() and d[2] or nil,
                down = d[4] and true or false, callback = d[3], font_size = d[5] or 15, icon = d.icon, icon_after = d.after,
                focused = self.focus ~= nil and self.focus[1] == d.row and self.focus[2] == k }
            if d.row then self.actions[d.row] = self.actions[d.row] or {}; self.actions[d.row][k] = d[3] end
        end
        return rowg
    end
    local kh = Device.screen:scaleBySize(50)
    self.actions = {}
    -- (letters: the keyboard's bottom row, Z to B, as the keys are laid out)
    add(keys({
        { "", "Z", function() self:onPrevChapter() end, icon = "prev", row = 1 },
        { "30 s", "X", function() self:onBack30() end, false, 14, icon = "rew", row = 1 },
        { "", "C", function() self:onToggle() end, p.playing, icon = p.playing and "pause" or "play", row = 1 },
        { "30 s", "V", function() self:onFwd30() end, false, 14, icon = "ffwd", after = true, row = 1 },
        { "", "B", function() self:onNextChapter() end, icon = "next", row = 1 },
    }, kh))
    gap(10)
    local sleep_label = p.sleep_end_of_chapter and _("Sleep: chapter")
        or (p.sleep_at and T(_("Sleep: %1 min"), math.max(1, math.ceil((p.sleep_at - os.time()) / 60))))
        or _("Sleep: off")
    add(keys({
        { _("Chapters"), "Q", function() self:onChapters() end, row = 2 },
        { sleep_label, "W", function() self:onSleep() end, p.sleep_at ~= nil or p.sleep_end_of_chapter, row = 2 },
        { _("Stop"), "E", function() self:onStopClose() end, icon = "stop", row = 2 },
        { _("Go to"), "R", function() self:onGoTo() end, row = 2 },
    }, kh))
    self.actions[3] = { function() self:onVolDown() end, function() self:onVolUp() end }
    gap(10)
    add(Skeuo.Dial:new{ w = inner, h = Device.screen:scaleBySize(56), value = Engine.volume(), max = 15,
        value_text = T("%1 / %2", Engine.volume(), 15), label = _("volume"),
        letters = Touch.keys() and { "A", "S" } or nil,
        focused = self.focus and self.focus[1] == 3 and (self.focus[2] == 1 and "minus" or "plus") or nil,
        minus = function() self:onVolDown() end, plus = function() self:onVolUp() end })
    gap(12)
    if Touch.on() then
        add(Touch.chips(inner, {
            { _("About this book"), function() self:onDescription() end },
            { _("Close (keeps playing)"), function() self:onClose() end },
        }, self))
    else
        add(TextBoxWidget:new{ text = fiveWay() and _("5-way: choose a key   Press: use it   (or its letter)\nD: about this book   Back: close (keeps playing)")
            or _("◀ ▶ 30 s   ▲ ▼ chapter   Press: play / pause\nD: about this book   Back: close (keeps playing)"),
            face = face(14), width = inner, alignment = "center", fgcolor = Blitbuffer.COLOR_DARK_GRAY })
    end
    self.content = group
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group },
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

--- The 5-way: to the next key that way (a quick redraw).
function Screen:onFocusMove(_arg, key)
    local dir = type(key) == "table" and key.key or nil
    if not (dir and self.focus) then return true end
    local nf = Screen.move(self.focus, dir)
    if nf[1] ~= self.focus[1] or nf[2] ~= self.focus[2] then
        self.focus = nf
        self:build()
        UIManager:setDirty(self, "fast")
    end
    return true
end

--- Press: the key the 5-way is on.
function Screen:onFocusPress()
    local row = self.focus and self.actions and self.actions[self.focus[1]]
    local act = row and row[self.focus[2]]
    if act then act() else self:onToggle() end
    return true
end
--- 30 s back or on: presses close together are added up and the player is
--- started once, where they end (each start of the player costs the Kindle 3
--- a second or two; several presses started it several times).
Screen.SKIP_GATHER = 0.8
function Screen:queueSkip(delta)
    local p = self.player
    self.skip_target = math.max(0, (self.skip_target or p:globalPos()) + delta)
    if self.skip_apply then UIManager:unschedule(self.skip_apply) end
    self.skip_apply = function()
        self.skip_apply = nil
        local target = self.skip_target
        self.skip_target = nil
        if target then p:seekTo(target) end
        if not self.closed then self:refresh() end
    end
    UIManager:scheduleIn(Screen.SKIP_GATHER, self.skip_apply)
    -- (the time shown moves at once)
    self:build()
    UIManager:setDirty(self, "fast")
    return true
end
function Screen:onBack30() return self:queueSkip(-Audiobook.SKIP_MS) end
function Screen:onFwd30() return self:queueSkip(Audiobook.SKIP_MS) end
function Screen:onPrevChapterKey() return self:onPrevChapter() end
function Screen:onNextChapterKey() return self:onNextChapter() end
function Screen:onBack30Key() return self:onBack30() end
function Screen:onFwd30Key() return self:onFwd30() end
function Screen:onToggleKey() return self:onToggle() end

--- Go to a time: "1:23:45", "23:45", the same digits without colons
--- ("12345", "2345"), or a percentage.
function Screen:onGoTo()
    local InputDialog = require("ui/widget/inputdialog")
    local p = self.player
    local total = Audiobook.total(p.book)
    local dialog
    local function go()
        local ms = Audiobook.parseTime(dialog:getInputText(), total)
        if not ms then
            UIManager:show(InfoMessage:new{ text = _("Type a time with or without colons (5000 or 50:00, 13000 or 1:30:00), or a percentage (50%)."), timeout = 4 })
            return
        end
        UIManager:close(dialog)
        p:seekTo(ms)
        self:refresh()
    end
    dialog = InputDialog:new{
        title = _("Go to"),
        description = T(_("Now at %1 of %2. Type a time, colons optional (5000 = 50:00, 13000 = 1:30:00), or a percentage (50%)."),
            Audiobook.fmt(p:globalPos()), Audiobook.fmt(total)),
        input = "", input_hint = Audiobook.fmt(p:globalPos()),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Go"), is_enter_default = true, callback = go },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return true
end
function Screen:onPrevChapter() self.player:chapterStep(-1); self:refresh(); return true end
function Screen:onNextChapter() self.player:chapterStep(1); self:refresh(); return true end
-- (the volume rocker: gzreader_audioctl, everywhere)
function Screen:onVolUp() Engine.setVolume(Engine.volume() + 1); self:refreshVolume(); return true end
function Screen:onVolDown() Engine.setVolume(Engine.volume() - 1); self:refreshVolume(); return true end

--- After a volume change: a quick redraw (no flash).
function Screen:refreshVolume()
    self:build()
    UIManager:setDirty(self, "fast")
end

--- Close: back to where the player was opened from (Home…), fully redrawn.
local function closeScreen(self)
    UIManager:close(self, "full")
    pcall(Folder.refreshHome, Folder.stubPath(self.player.plugin, self.player.book.id))
    return true
end

function Screen:onClose()
    pcall(self.player.save, self.player) -- Home shows where you are
    pcall(self.player.push, self.player) -- and so does Grimmory
    return closeScreen(self)
end

--- The Home key: Home (the audio keeps playing).
function Screen:onHome()
    pcall(self.player.save, self.player)
    pcall(self.player.push, self.player)
    return require("gzreader_tabs").goHome(self)
end

function Screen:onStopClose()
    self.player:stop() -- saves and sends the position
    return closeScreen(self)
end

function Screen:onCloseWidget()
    -- skips still being gathered: done now
    if self.skip_apply then
        local f = self.skip_apply
        UIManager:unschedule(f)
        self.closed = true
        pcall(f)
    end
    self.closed = true
    if self.player.screen == self then self.player.screen = nil end
    if self.cover_bb then self.cover_bb:free(); self.cover_bb = nil end
end

--- A dialog with Q, W, E… keys, as in the book menus.
local function keyedDialog(title, rows)
    local dialog = ButtonDialog:new{ title = title, buttons = rows }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

function Screen:onSleep()
    local p = self.player
    local dialog
    local function pick(v)
        return function()
            UIManager:close(dialog)
            if v == "off" then p:cancelSleep() else p:setSleep(v) end
            self:refresh()
        end
    end
    dialog = keyedDialog(_("Sleep timer"), {
        { { text = _("15 minutes"), align = "left", callback = pick(15) } },
        { { text = _("30 minutes"), align = "left", callback = pick(30) } },
        { { text = _("45 minutes"), align = "left", callback = pick(45) } },
        { { text = _("60 minutes"), align = "left", callback = pick(60) } },
        { { text = _("At the end of this chapter"), align = "left", callback = pick("chapter") } },
        { { text = _("Off"), align = "left", callback = pick("off") } },
    })
    return true
end

--- What the book is about (Grimmory's description), its narrator and length.
function Screen:onDescription()
    local book = self.player.book
    local facts = {}
    if book.author then facts[#facts + 1] = book.author end
    if book.narrator and book.narrator ~= "" then facts[#facts + 1] = T(_("Read by %1"), book.narrator) end
    local total = Audiobook.total(book)
    if total > 0 then facts[#facts + 1] = T(_("Length %1"), Audiobook.fmt(total)) end
    local n = #(book.chapters or {})
    if n > 1 then facts[#facts + 1] = T(_("%1 chapters"), n) end
    local text = table.concat(facts, "\n")
    text = text .. (text ~= "" and "\n\n" or "") .. (book.description
        or _("Grimmory has no description of this book (or it hasn't been fetched yet: it is, the next time the player opens with Wi-Fi on)."))
    UIManager:show(require("ui/widget/textviewer"):new{ title = book.title or _("Audiobook"), text = text })
    return true
end

function Screen:onOptions()
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    dialog = keyedDialog(self.player.book.title, {
        { { text = _("About this book"), align = "left", callback = run(function() self:onDescription() end) } },
        { { text = _("Chapters"), align = "left", callback = run(function() self:onChapters() end) } },
        { { text = _("Sleep timer"), align = "left", callback = run(function() self:onSleep() end) } },
        { { text = _("Stop and close"), align = "left", callback = run(function() self:onStopClose() end) } },
        { { text = _("Close (keeps playing)"), align = "left", callback = run(function() self:onClose() end) } },
    })
    return true
end

--- Chapter list: the current one marked, its start time and length.
function Screen:onChapters()
    local p = self.player
    local chapters = p.book.chapters or {}
    local items = {}
    local cur = Audiobook.chapterAt(p.book, p:globalPos())
    local total = Audiobook.total(p.book)
    for i, c in ipairs(chapters) do
        local nxt = chapters[i + 1]
        local len = (nxt and nxt.startTimeMs or total) - (c.startTimeMs or 0)
        items[#items + 1] = {
            text = (i == cur and "▶ " or "") .. (c.title or T(_("Chapter %1"), i)),
            bold = i == cur,
            mandatory = Audiobook.fmt(c.startTimeMs) .. " · " .. Audiobook.fmt(len),
            callback = function() p:seekTo(c.startTimeMs or 0); self:refresh() end,
        }
    end
    if #items == 0 then items[1] = { text = _("This audiobook has no chapters."), select_enabled = false } end
    local menu
    menu = Menu:new{
        title = T(_("Chapters · %1"), p.book.title or ""), item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = true, title_bar_fm_style = true,
        onMenuChoice = function(_m, item)
            UIManager:close(menu, "ui")
            if item.callback then item.callback() end
            return true
        end,
    }
    menu.key_events.LeftButtonTap = nil -- the Menu key closes it
    menu.key_events.GzClose = { { "Menu" } }
    menu.onGzClose = function() UIManager:close(menu, "ui"); return true end
    menu:onGotoPage(menu:getPageNumber(cur))
    UIManager:show(menu)
    return true
end

--- Open (or bring back) the player for a downloaded audiobook.
function Audiobook.open(plugin, book)
    local p = Audiobook.current
    if not (p and p.book.id == book.id) then
        if p then p:stop() end
        p = Player:new(plugin, book)
    end
    -- into Recent / history like a book, with its progress on the tile
    pcall(Folder.recordPlay, plugin, book.id, p.pos, Audiobook.total(book))
    local screen = Screen:new{ player = p }
    UIManager:show(screen)
    if not p.playing and not p.paused then
        -- (only if nothing happened meanwhile: the Kindle went to sleep, the
        -- player was closed, Play was pressed; 1.21.0 started an audiobook
        -- on a Kindle 3 while it slept)
        local gen = (p.pull_gen or 0) + 1
        p.pull_gen = gen
        p:pull(function()
            if p.pull_gen ~= gen or p.playing or Audiobook.current ~= p then return end
            if UIManager.isWidgetShown and not UIManager:isWidgetShown(screen) then return end
            p:play(); screen:refresh()
        end)
    end
    return screen
end

--- From the Grimmory browser: open if downloaded, else offer to download.
function Audiobook.choose(plugin, summary)
    local book = Audiobook.load(plugin, summary.id)
    if book then return Audiobook.open(plugin, book) end
    local size_kb = tonumber(summary.fileSizeKb)
    if summary.plex and require("gzreader_net").usb then
        return UIManager:show(InfoMessage:new{ text = _("This Kindle syncs through your computer: choose Plex audiobooks on the sync page (Content → Audiobooks), and they come with the next sync.") })
    end
    if require("gzreader_net").usb then
        -- no Wi-Fi: the next sync with the computer brings it (gzreader_usbsync.lua)
        local Usb = require("gzreader_usbsync")
        if Usb.isQueued(plugin, summary.id) then
            return UIManager:show(ConfirmBox:new{
                text = T(_("“%1” is in the sync queue: it comes with the next sync with your computer."), summary.title or ""),
                ok_text = _("Take it off"), cancel_text = _("Keep"),
                ok_callback = function() Usb.dequeue(plugin, summary.id) end,
            })
        end
        return UIManager:show(ConfirmBox:new{
            text = T(_("Add the audiobook “%1” to the sync queue?"), summary.title or "")
                .. (size_kb and ("\n" .. string.format("%.0f MB", size_kb / 1024)) or ""),
            ok_text = _("Add to sync queue"),
            ok_callback = function() Usb.queuedMessage(plugin, summary) end,
        })
    end
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
    pcall(Folder.removeStub, plugin, book_id)
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

return Audiobook
