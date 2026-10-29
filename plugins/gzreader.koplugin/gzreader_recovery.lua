--[[--
Unfinished downloads and audiobook preparing, picked up after a restart.

Every book download (running or queued) and every audiobook download and
"preparing the audio" is written down in GZreader's settings when it starts
and crossed off when it finishes, or when you stop it or take it out of the
queue. If GZreader ends in between (the battery ran out, the Kindle slept or
restarted, GZreader crashed or was closed), the note is still there the next
time GZreader starts, and it asks, for each one:

- Continue: download again from where it stopped (the part already on the
  Kindle is kept; Grimmory sends only the rest), or carry on preparing;
- Delete: remove the part that was downloaded or converted;
- Ignore: stop asking; nothing is removed (downloading the book again later
  still picks up the part already here).

  store.unfinished = { ["book:<id>"] = { kind = "book", book = {…}, path, title, at },
                       ["audio:<id>"] = { kind = "audiobook", summary = {…}, stage, title, at } }
]]

local ButtonDialog = require("ui/widget/buttondialog")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local R = { DELAY = 6, checked = false }

local BOOK_FIELDS = { "id", "title", "authors", "primaryFileName", "primaryFileType", "primaryFileId", "fileSizeKb" }

local function slim(book)
    local out = {}
    for _i, k in ipairs(BOOK_FIELDS) do
        local v = book[k]
        if type(v) ~= "function" then out[k] = v end
    end
    return out
end

local function list(plugin)
    plugin.store.unfinished = type(plugin.store.unfinished) == "table" and plugin.store.unfinished or {}
    return plugin.store.unfinished
end

--- A book download started or was queued.
function R.bookStarted(plugin, book, path)
    if not plugin or not plugin.store then return end
    list(plugin)["book:" .. tostring(book.id)] = { kind = "book", book = slim(book), path = path,
        title = book.title, at = os.time() }
    plugin:save()
end

--- An audiobook download (stage "download") or its preparing ("prepare") started.
function R.audioStarted(plugin, summary, stage)
    if not plugin or not plugin.store then return end
    list(plugin)["audio:" .. tostring(summary.id)] = { kind = "audiobook", summary = slim(summary), stage = stage,
        title = summary.title, at = os.time() }
    plugin:save()
end

function R.done(plugin, key)
    if not plugin or not plugin.store or not plugin.store.unfinished then return end
    if plugin.store.unfinished[key] then
        plugin.store.unfinished[key] = nil
        plugin:save()
    end
end

function R.bookDone(plugin, book_id) R.done(plugin, "book:" .. tostring(book_id)) end
function R.audioDone(plugin, book_id) R.done(plugin, "audio:" .. tostring(book_id)) end

---------------------------------------------------------------- after a restart

--- Stop a conversion process left running by the previous GZreader.
function R.stopConversions(dir)
    if not dir then return end
    os.execute(string.format(
        "for p in $(ps w 2>/dev/null | grep '[g]rimmory_mp4.lua' | grep -F %q | awk '{print $1}'); do kill $p; done >/dev/null 2>&1",
        dir))
end

local function partBytes(rec, plugin)
    if rec.kind == "book" then
        return lfs.attributes((rec.path or "") .. ".part", "size") or 0
    end
    local dir = require("gzreader_audiobook").dir(plugin, rec.summary.id)
    local n = 0
    local function walk(d)
        for name in lfs.dir(d) do
            if name ~= "." and name ~= ".." then
                local p = d .. "/" .. name
                local a = lfs.attributes(p)
                if a and a.mode == "directory" then walk(p) elseif a then n = n + a.size end
            end
        end
    end
    if lfs.attributes(dir, "mode") == "directory" then pcall(walk, dir) end
    return n
end

--- Still unfinished? (the book may have been downloaded since)
local function stillUnfinished(plugin, rec)
    if rec.kind == "book" then
        return rec.book and rec.book.id and not plugin:localPathFor(rec.book.id)
    elseif rec.kind == "audiobook" then
        return rec.summary and rec.summary.id and require("gzreader_audiobook").load(plugin, rec.summary.id) == nil
    end
end

function R.continue(plugin, key, rec)
    R.done(plugin, key) -- noted again when it starts
    local Net = require("gzreader_net")
    if rec.kind == "book" then
        Log.info("recovery: continuing the download of book", rec.book.id)
        Net.run(function() plugin:downloadAndOpen(rec.book) end, { reason = "continue a download" })
    else
        Log.info("recovery: continuing audiobook", rec.summary.id, rec.stage)
        local Audiobook = require("gzreader_audiobook")
        R.stopConversions(Audiobook.dir(plugin, rec.summary.id))
        Net.run(function()
            Audiobook.download(plugin, rec.summary, function(b, err)
                if b then Audiobook.open(plugin, b) else plugin:showError(err) end
            end)
        end, { reason = "continue an audiobook" })
    end
end

function R.delete(plugin, key, rec)
    if rec.kind == "book" then
        os.remove((rec.path or "") .. ".part")
    else
        local Audiobook = require("gzreader_audiobook")
        local dir = Audiobook.dir(plugin, rec.summary.id)
        R.stopConversions(dir)
        if Audiobook.load(plugin, rec.summary.id) == nil and lfs.attributes(dir, "mode") == "directory" then
            require("ffi/util").purgeDir(dir)
        end
    end
    Log.info("recovery: deleted unfinished", key)
    R.done(plugin, key)
end

function R.ignore(plugin, key)
    Log.info("recovery: ignored", key)
    R.done(plugin, key)
end

local function describe(plugin, rec)
    local title = rec.title or (rec.book and rec.book.title) or (rec.summary and rec.summary.title) or "?"
    local mb = string.format("%.1f MB", partBytes(rec, plugin) / 1048576)
    if rec.kind == "book" then
        return T(_("The download of “%1” didn't finish (%2 downloaded), for example because the battery ran out, the Kindle went to sleep or GZreader closed."), title, mb)
    elseif rec.stage == "prepare" then
        return T(_("Preparing the audiobook “%1” for the Kindle didn't finish (%2 on the Kindle)."), title, mb)
    end
    return T(_("The download of the audiobook “%1” didn't finish (%2 downloaded)."), title, mb)
end

--- Ask about each unfinished job, one after another.
function R.ask(plugin, keys, i)
    i = i or 1
    local key = keys[i]
    if not key then return end
    local rec = list(plugin)[key]
    if not rec then return R.ask(plugin, keys, i + 1) end
    local dialog
    local function nextOne() UIManager:nextTick(function() R.ask(plugin, keys, i + 1) end) end
    local verb = rec.kind == "audiobook" and rec.stage == "prepare" and _("Continue preparing") or _("Continue downloading")
    dialog = ButtonDialog:new{
        title = describe(plugin, rec),
        buttons = {
            {{ text = verb, callback = function() UIManager:close(dialog); R.continue(plugin, key, rec); nextOne() end }},
            {{ text = _("Delete what was downloaded"), callback = function() UIManager:close(dialog); R.delete(plugin, key, rec); nextOne() end }},
            {{ text = _("Ignore"), callback = function() UIManager:close(dialog); R.ignore(plugin, key); nextOne() end }},
        },
    }
    UIManager:show(dialog)
end

--- Once per run, a few seconds after GZreader starts.
function R.check(plugin)
    if R.checked then return end
    R.checked = true
    local Download = require("gzreader_download")
    local keys = {}
    for key, rec in pairs(list(plugin)) do
        local busy = type(rec) == "table" and rec.kind == "book" and rec.book and Download.isQueued(rec.book.id)
        if type(rec) ~= "table" or not stillUnfinished(plugin, rec) then
            list(plugin)[key] = nil -- finished since, or unreadable
        elseif not busy then
            keys[#keys + 1] = key
        end
    end
    if #keys == 0 then return end
    plugin:save()
    table.sort(keys, function(a, b)
        local ta, tb = list(plugin)[a].at or 0, list(plugin)[b].at or 0
        if ta ~= tb then return ta < tb end
        return a < b -- same second: a stable order
    end)
    Log.info("recovery:", #keys, "unfinished download(s) or audiobook(s) from before")
    R.ask(plugin, keys)
end

function R.schedule(plugin)
    if R.checked or R.pending then return end
    if not next(list(plugin)) then R.checked = true; return end -- nothing was cut short
    R.pending = true
    UIManager:scheduleIn(R.DELAY, function()
        R.pending = nil
        pcall(R.check, plugin)
    end)
end

return R
