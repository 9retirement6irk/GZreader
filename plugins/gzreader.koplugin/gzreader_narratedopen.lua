--[[--
A narrated EPUB (one with its own narration: EPUB 3 media overlays, such as
BookOrbit's read-along books) opened from anywhere asks how:

  * Read: the book, as any other;
  * Read with narration: the book, its narration playing from where you are,
    the sentence being read highlighted (gzreader_narration.lua);
  * Listen as audiobook: the audiobook player, with chapters and the sleep
    timer. When the server's audiobook of the same book is downloaded
    (BookOrbit's "a<id>"), that one; otherwise the narration of the EPUB
    itself, made into an audiobook once (its audio copied out of the book:
    no download, and the narration plays from that copy too).

Where you were carries over: the audiobook made from the book starts at the
sentence the narration was last at, and the book opens at the sentence the
audiobook was last at when you listened after reading.

Settings → Audio → Narrated books → "Ask how to open them" (on by default;
off: they open as books). A Kindle without sound never asks.

On the walkman: every narrated EPUB on the Kindle is an audiobook in
Downloads → Audiobooks too (Open.scan at start, Open.onWalkman after each
download): a cassette with the book's cover, title and author; a tap
listens to it (Open.listen: made into an audiobook the first time).

Also BookOrbit: a book's download asks Narrated book (its size) or Book only,
when the book has narration (Open.chooseDownload), and Home's recently read
list shows a BookOrbit book and its audiobook as one (gzreader_serverrecent).
]]

local Log = require("gzreader_log")

local Open = {
    PREFIX = "narr-", -- the audiobook made from a book: "narr-<md5 of its path>"
}

local function UIManager() return require("ui/uimanager") end
local function _(t) return require("gettext")(t) end
local function T(...) return require("ffi/util").template(...) end

--- A Kindle with sound.
function Open.sound()
    local ok, yes = pcall(function() return require("gzreader_touch").player() end)
    return ok and yes and true or false
end

--- Whether to ask for `path`.
function Open.wants(path, settings)
    settings = settings or G_reader_settings
    if settings:readSetting(require("gzreader_narration").OPEN) == "read" then return false end
    if not Open.sound() then return false end
    return require("gzreader_narration").quickCheck(path) == true
end

---------------------------------------------------------------- the audiobook from the book

--- The id of the audiobook made from the book at `path`.
function Open.idFor(path)
    return Open.PREFIX .. require("ffi/sha2").md5(path)
end

local function plugin()
    if Open.PLUGIN then return Open.PLUGIN end -- (tests)
    local ok, p = pcall(function()
        local RUI = require("apps/reader/readerui").instance
        if RUI and RUI.gzreader then return RUI.gzreader end
        local FM = require("apps/filemanager/filemanager").instance
        return FM and FM.gzreader
    end)
    return ok and p or nil
end
Open.plugin = plugin

--- The layout of the audiobook made from `book` (gzreader_narration's
--- parsed book): the audiobook player's (tracks, chapters, files) and
--- `epub_audio`, the copy of each audio file. Pure.
function Open.layout(book, title, author)
    local order, seen = {}, {}
    for _i, p in ipairs(book.pars) do
        if not seen[p.audio] then
            seen[p.audio] = true
            order[#order + 1] = p.audio
        end
    end
    local tracks, files, starts, map = {}, {}, {}, {}
    local at = 0
    for i, audio in ipairs(order) do
        local ext = (audio:match("%.(%w+)$") or "mp3"):lower()
        local name = string.format("track-%03d.%s", i, ext)
        local dur = book.duration[audio] or 0
        files[i] = name
        tracks[i] = { file = name, index = i - 1, start = at, durationMs = dur, title = nil }
        starts[audio] = at
        map[audio] = name
        at = at + dur
    end
    local chapters, done = {}, {}
    local titles = {}
    for _i, s in ipairs(book.spine or {}) do titles[s.index] = s.title end
    for _i, p in ipairs(book.pars) do
        if not done[p.index] then
            done[p.index] = true
            chapters[#chapters + 1] = { title = titles[p.index] or T(_("Part %1"), #chapters + 1), startTimeMs = starts[p.audio] + p.b }
        end
    end
    return { title = title, author = author, folder = true, durationMs = at, tracks = tracks, files = files,
        chapters = chapters, epub_audio = map, narrated_from = book.path }
end

--- Where sentence `i` is in the audiobook made from `book` (ms from its start).
function Open.msAt(layout, book, i)
    local p = book.pars[i]
    if not p then return 0 end
    for _k, t in ipairs(layout.tracks) do
        if layout.epub_audio[p.audio] == t.file then return t.start + p.b end
    end
    return 0
end

--- The sentence at `ms` of the audiobook made from `book`: its index.
function Open.sentenceAt(layout, book, ms)
    local best = 1
    for i, p in ipairs(book.pars) do
        if Open.msAt(layout, book, i) <= ms then best = i else
            -- (later sentences of another file can come before in the list only if the book jumps back)
            if p.audio == book.pars[best].audio then break end
        end
    end
    return best
end

local function readJson(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local ok, data = pcall(require("gzreader_json").decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and data or nil
end

--- The copy of `audio` (a path in the EPUB at `epub`) made for its audiobook, or nil.
function Open.copiedAudio(epub, audio)
    local p = plugin()
    if not p then return nil end
    local AB = require("gzreader_audiobook")
    local dir = AB.dir(p, Open.idFor(epub))
    local data = readJson(dir .. "/audiobook.json")
    local name = data and type(data.epub_audio) == "table" and data.epub_audio[audio]
    if not name then return nil end
    local file = dir .. "/" .. name
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(file, "mode") == "file" and file or nil
end

--- The audiobook made from the EPUB at `path`, made now if it isn't yet (its
--- audio copied out of the book). Returns the player's book, or nil, why.
function Open.make(p, path, title, author)
    local Narration = require("gzreader_narration")
    local AB = require("gzreader_audiobook")
    local id = Open.idFor(path)
    local have = AB.load(p, id)
    if have then return have end
    local book = Narration.load(path)
    if not book then return nil, "no narration" end
    local lfs = require("libs/libkoreader-lfs")
    local dir = AB.dir(p, id)
    require("util").makePath(dir)
    local layout = Open.layout(book, title, author)
    layout.id = id
    local r = require("ffi/archiver").Reader:new()
    if not r:open(path) then return nil, "the book couldn't be opened" end
    for _e in r:iterate() do end
    for audio, name in pairs(layout.epub_audio) do
        local out = dir .. "/" .. name
        if lfs.attributes(out, "mode") ~= "file" then
            local ok = r:extractToPath(audio, out)
            if not ok or lfs.attributes(out, "mode") ~= "file" then
                r:close()
                os.remove(out)
                return nil, "its audio couldn't be copied out of the book"
            end
        end
    end
    r:close()
    local f = io.open(dir .. "/audiobook.json", "wb")
    if not f then return nil, "couldn't write" end
    f:write(require("gzreader_json").encode(layout))
    f:close()
    Log.info("narration: the book made into an audiobook,", #layout.files, "audio files,", #layout.chapters, "chapters")
    -- (the narration plays from this copy now: its own copy goes)
    pcall(Narration.forgetCopy, path)
    return AB.load(p, id)
end

--- The server's audiobook of the book at `path`, downloaded: its player book, or nil.
function Open.serverAudiobook(p, path)
    local AB = require("gzreader_audiobook")
    for id, e in pairs(p.store.downloads or {}) do
        if type(e) == "table" and e.path == path and tostring(id):match("^%d+$") then
            local b = AB.load(p, "a" .. tostring(id))
            if b then return b end
        end
    end
    return nil
end

--- The book's title and author, from its file's metadata as KOReader keeps them.
local function about(path)
    local title, author
    pcall(function()
        local DocSettings = require("docsettings")
        local ds = DocSettings:open(path)
        local props = ds:readSetting("doc_props") or {}
        title, author = props.title, props.authors
    end)
    return title or path:match("([^/]+)%.%w+$"), author
end

--- Listen to the book at `path` as an audiobook.
function Open.listen(path)
    local p = plugin()
    if not p then return false end
    local AB = require("gzreader_audiobook")
    local server = Open.serverAudiobook(p, path)
    if server then
        Log.info("narration: listening to the server's audiobook of the book")
        AB.open(p, server)
        return true
    end
    local title, author = about(path)
    local InfoMessage = require("ui/widget/infomessage")
    local wait = InfoMessage:new{ text = _("Getting the narration ready…") }
    UIManager():show(wait)
    UIManager():forceRePaint()
    local book, why = Open.make(p, path, title, author)
    UIManager():close(wait)
    if not book then
        UIManager():show(InfoMessage:new{ text = T(_("The narration couldn't be made into an audiobook: %1."), tostring(why)) })
        return false
    end
    -- (where the narration was last: the audiobook starts there, if it's further on)
    local Narration = require("gzreader_narration")
    local nb = Narration.load(path)
    local kept = p.store.narration_at and p.store.narration_at[path]
    p.store.audiobooks = p.store.audiobooks or {}
    local e = p.store.audiobooks[book.id] or {}
    if nb and type(kept) == "table" and (kept.at or 0) > (e.updated or 0) then
        e.pos_ms = Open.msAt(book, nb, kept.i or 1)
        e.updated = kept.at
        p.store.audiobooks[book.id] = e
    end
    -- (after the message has gone and Home has been drawn again)
    UIManager():nextTick(function() AB.open(p, book) end)
    return true
end

---------------------------------------------------------------- on the walkman

local function unescape(s)
    return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

--- From an EPUB's OPF (at `opf_path` in it): { title, author, cover = the
--- cover picture's path in the EPUB }. Pure.
function Open.parseMeta(xml, opf_path)
    xml = xml or ""
    local function dc(name)
        local v = xml:match("<dc:" .. name .. "[^>]*>(.-)</dc:" .. name .. ">")
        v = v and unescape(v:gsub("<[^>]+>", "")):gsub("^%s+", ""):gsub("%s+$", "") or nil
        return v ~= "" and v or nil
    end
    local items, cover = {}, nil
    for tag in xml:gmatch("<[%w:]*item%s[^>]*>") do
        local id, href = tag:match('%sid="([^"]*)"'), tag:match('%shref="([^"]*)"')
        if id and href then
            items[id] = href
            if (tag:match('%sproperties="([^"]*)"') or ""):match("cover%-image") then cover = href end
        end
    end
    if not cover then
        for tag in xml:gmatch("<[%w:]*meta%s[^>]*>") do
            if tag:match('name="cover"') then
                local id = tag:match('content="([^"]*)"')
                cover = id and items[id] or cover
            end
        end
    end
    local N = require("gzreader_narration")
    return { title = dc("title"), author = dc("creator"), cover = cover and N.resolve(opf_path, unescape(cover)) or nil }
end

--- The EPUB at `path`: { title, author, cover = its picture's bytes } (any of them nil).
function Open.aboutFile(path)
    local out = {}
    pcall(function()
        local N = require("gzreader_narration")
        local r = require("ffi/archiver").Reader:new()
        if not r:open(path) then return end
        for _e in r:iterate() do end
        local function read(name) return name and r:extractToMemory(name) or nil end
        local opf = N.parseContainer(read("META-INF/container.xml"))
        local xml = opf and read(opf)
        if xml then
            local m = Open.parseMeta(xml, opf)
            out.title, out.author = m.title, m.author
            if m.cover then out.cover = read(m.cover) end
        end
        r:close()
    end)
    return out
end

--- The narrated EPUB at `path` as an audiobook in Downloads → Audiobooks (the
--- walkman): its cassette with the book's cover, title and author; a tap
--- listens to it (gzreader_abfolder.lua's open). Returns true when it's there.
function Open.onWalkman(p, path)
    if not (p and p.store) or require("gzreader_narration").quickCheck(path) ~= true then return false end
    local lfs = require("libs/libkoreader-lfs")
    local AB = require("gzreader_audiobook")
    local Folder = require("gzreader_abfolder")
    local id = Open.idFor(path)
    p.store.audiobooks = p.store.audiobooks or {}
    local e = p.store.audiobooks[id] or {}
    local fresh = e.narrated ~= path or not e.title
    if fresh then
        local a = Open.aboutFile(path)
        local title, author = about(path)
        e.title, e.author, e.narrated = a.title or title, a.author or author, path
        local dir = AB.dir(p, id)
        require("util").makePath(dir)
        if a.cover and a.cover ~= "" and lfs.attributes(dir .. "/cover.jpg", "mode") ~= "file" then
            local f = io.open(dir .. "/cover.jpg", "wb")
            if f then f:write(a.cover); f:close() end
        end
        p.store.audiobooks[id] = e
        Log.info("narration: a narrated book on the walkman")
    end
    local stub = Folder.stubPath(p, id)
    if fresh or not stub or lfs.attributes(stub, "mode") ~= "file" then Folder.writeStub(p, id) end
    return true
end

--- Every narrated EPUB on the Kindle as an audiobook on the walkman, and off
--- it again when its book has gone. `done(n)`: how many are on it.
--- A few books a tick, so the Kindle keeps answering; a book seen not to be
--- narrated (its size and time unchanged) isn't looked into again.
function Open.scan(p, done)
    if not (p and p.store and p.libraryDir) or not Open.sound() then return end
    local lfs = require("libs/libkoreader-lfs")
    local Folder = require("gzreader_abfolder")
    local root, skip = p:libraryDir(), Folder.entryDir(p)
    local found = {}
    local function walk(dir, depth)
        if depth > 6 or dir == skip then return end
        local ok, iter, st = pcall(lfs.dir, dir)
        if not ok then return end
        for name in iter, st do
            if name:sub(1, 1) ~= "." and not name:match("%.sdr$") then
                local path = dir .. "/" .. name
                local mode = lfs.attributes(path, "mode")
                if mode == "directory" then walk(path, depth + 1)
                elseif mode == "file" and name:lower():match("%.epub$") then found[#found + 1] = path end
            end
        end
    end
    walk(root, 0)
    p.store.narration_no = p.store.narration_no or {}
    local no, n, i = p.store.narration_no, 0, 1
    local function key(path)
        local a = lfs.attributes(path) or {}
        return tostring(a.size) .. "|" .. tostring(a.modification)
    end
    local function step()
        for _k = 1, 8 do
            local path = found[i]
            if not path then
                -- (a narrated book that's gone, not made into an audiobook: off the walkman)
                for id, e in pairs(p.store.audiobooks or {}) do
                    if type(e) == "table" and e.narrated and lfs.attributes(e.narrated, "mode") ~= "file"
                        and lfs.attributes(require("gzreader_audiobook").dir(p, id) .. "/audiobook.json", "mode") ~= "file" then
                        Folder.removeStub(p, id)
                        p.store.audiobooks[id] = nil
                    end
                end
                if p.save then p:save() end
                if done then done(n) end
                return
            end
            i = i + 1
            if no[path] ~= key(path) then
                if Open.onWalkman(p, path) then n = n + 1; no[path] = nil else no[path] = key(path) end
            end
        end
        UIManager():scheduleIn(0.2, step)
    end
    step()
end

--- Where the narration is now, kept for the audiobook (narration's place).
function Open.noteSentence(path, i)
    local p = plugin()
    if not (p and path and i) then return end
    p.store.narration_at = p.store.narration_at or {}
    p.store.narration_at[path] = { i = i, at = os.time() }
end

--- After the book opens: at the sentence the audiobook made from it was
--- last at, when that's newer than the book's own place.
function Open.catchUp(ui)
    local p = plugin()
    local path = ui and ui.document and ui.document.file
    if not (p and path) then return end
    local e = p.store.audiobooks and p.store.audiobooks[Open.idFor(path)]
    if type(e) ~= "table" or not e.pos_ms or not e.updated then return end
    local kept = p.store.narration_at and p.store.narration_at[path]
    if type(kept) == "table" and (kept.at or 0) >= e.updated then return end
    local lfs = require("libs/libkoreader-lfs")
    local DocSettings = require("docsettings")
    local sidecar = DocSettings:findSidecarFile(path)
    local read_at = sidecar and lfs.attributes(sidecar, "modification") or 0
    if read_at >= e.updated then return end
    local AB = require("gzreader_audiobook")
    local ab = AB.load(p, Open.idFor(path))
    local nb = require("gzreader_narration").load(path)
    if not (ab and nb) then return end
    local i = Open.sentenceAt(ab, nb, e.pos_ms)
    local par = nb.pars[i]
    local Narration = require("gzreader_narration")
    local link = Narration.linkFor(par.index, par.id)
    local ok = pcall(function()
        if ui.document:isXPointerInDocument(link) then
            local xp = ui.document:getNormalizedXPointer(link)
            ui:handleEvent(require("ui/event"):new("GotoXPointer", xp, xp))
        end
    end)
    Log.info("narration: the book opened where the audiobook was", ok and "" or "(not found)")
end

---------------------------------------------------------------- asking

--- The question for `path`: go("read" | "narration" | "listen").
function Open.ask(path, go)
    local ButtonDialog = require("ui/widget/buttondialog")
    local title = about(path)
    local d
    local function pick(how) return function() UIManager():close(d); go(how) end end
    d = ButtonDialog:new{
        title = T(_("“%1” has its own narration."), title),
        buttons = {
            { { text = _("Read"), callback = pick("read") } },
            { { text = _("Read with narration"), callback = pick("narration") } },
            { { text = _("Listen as audiobook"), callback = pick("listen") } },
        },
    }
    UIManager():show(d)
    return d
end

--- Opening books asks first, for narrated EPUBs (wraps ReaderUI.showReader).
function Open.install()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._gz_narrated_hook then return end
    ReaderUI._gz_narrated_hook = true
    local orig = ReaderUI.showReader
    function ReaderUI:showReader(file, provider, seamless, forced, after_open, ...)
        local reloading = rawget(self, "reloading")
        if reloading or seamless or Open.skip or not Open.wants(file) then
            Open.skip = nil
            if not reloading and not seamless and Open.sound() and require("gzreader_narration").quickCheck(file) then
                -- (opened without asking: still at the audiobook's place when that's newer)
                local cb = after_open
                after_open = function(ui, ...)
                    pcall(Open.catchUp, ui)
                    if cb then return cb(ui, ...) end
                end
            end
            return orig(self, file, provider, seamless, forced, after_open, ...)
        end
        local rest = { ... }
        local me = self
        Open.ask(file, function(how)
            Log.info("narration: a narrated book opened:", how)
            if how == "listen" then return Open.listen(file) end
            local cb = after_open
            local function opened(ui, ...)
                pcall(Open.catchUp, ui)
                if how == "narration" then
                    UIManager():scheduleIn(1, function()
                        local ok, why, fmt = require("gzreader_narration").play(ui)
                        if not ok then require("gzreader_narration").couldnt(why, fmt) end
                    end)
                end
                if cb then return cb(ui, ...) end
            end
            return orig(me, file, provider, seamless, forced, opened, unpack(rest))
        end)
    end
    return true
end

---------------------------------------------------------------- BookOrbit: downloading

--- A size in MB, for the question.
local function mb(bytes)
    if not tonumber(bytes) then return nil end
    return string.format("%.0f MB", math.max(1, bytes / 1048576))
end

--- The book-only copy's size for a label: "12 MB", "≈ 12 MB" (worked out from the
--- narrated copy less its audio, before BookOrbit has made it), or nil. Pure.
function Open.textSize(info)
    local m = mb(info and info.text)
    if m and info.text_about then return "\u{2248} " .. m end
    return m
end

--- The question for a narrated BookOrbit book being downloaded: `info` =
--- { narrated = bytes, text = bytes or nil }; go("original" | "audioless_epub").
function Open.askDownload(title, info, go)
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    local function pick(v) return function() UIManager():close(d); go(v) end end
    local narrated = mb(info.narrated)
    local text = Open.textSize(info)
    d = ButtonDialog:new{
        title = T(_("“%1” has its own narration. Download:"), title or ""),
        buttons = {
            { { text = narrated and T(_("Narrated book (%1)"), narrated) or _("Narrated book"), callback = pick("original") } },
            { { text = text and T(_("Book only (%1)"), text) or _("Book only (smaller)"), callback = pick("audioless_epub") } },
            { { text = _("Cancel"), callback = function() UIManager():close(d) end } },
        },
    }
    UIManager():show(d)
    return d
end

--- Before a BookOrbit book downloads (asked from a book's page or the
--- Catalog): if it has narration, ask which; then cont(book) with
--- book.gz_variant set ("original" or "audioless_epub"), or not at all
--- (Cancel). Books without narration: cont(book) at once.
function Open.chooseDownload(p, book, cont)
    if not (p and p.api and p.api.readAloudChoices) or book.gz_variant then return cont(book) end
    require("gzreader_async").run(p.api, function(api) return api:readAloudChoices(book.id) end, function(info)
        if type(info) ~= "table" or not info.has then return cont(book) end
        Open.askDownload(book.title, info, function(v)
            local b = {}
            for k, val in pairs(book) do b[k] = val end
            b.gz_variant = v
            if v == "original" and info.narrated then b.fileSizeKb = math.ceil(info.narrated / 1024) end
            if v == "audioless_epub" then b.fileSizeKb = info.text and math.ceil(info.text / 1024) or nil end
            Log.info("narration: downloading a narrated book as", v)
            cont(b)
        end)
    end, "read-aloud choices")
end

--- `book` to download as `variant`, with that copy's size (from `info`, readAloudChoices').
function Open.asVariant(book, info, variant)
    local b = {}
    for k, val in pairs(book) do b[k] = val end
    b.gz_variant = variant
    local bytes = info and (variant == "original" and info.narrated or info.text)
    b.fileSizeKb = bytes and math.ceil(bytes / 1024) or (variant == "original" and book.fileSizeKb or nil)
    return b
end

--- The book page's two choices for a narrated book (gzreader_bookpage.lua):
--- { { variant, label } ×2 }, with the sizes when known. Pure.
function Open.pageChoices(info)
    local narrated, text = mb(info and info.narrated), Open.textSize(info)
    return {
        { variant = "original", label = narrated and T(_("With narration · %1"), narrated) or _("With narration") },
        { variant = "audioless_epub", label = text and T(_("Book only · %1"), text) or _("Book only (smaller)") },
    }
end

---------------------------------------------------------------- a downloaded book: its narration after all

--- The BookOrbit id of the downloaded book at `path`, or nil.
function Open.downloadedId(p, path)
    for id, e in pairs(p and p.store and p.store.downloads or {}) do
        if type(e) == "table" and e.path == path then return id, e end
    end
end

--- Whether a book's hold menu offers Download with narration: a BookOrbit
--- EPUB on the Kindle whose copy has no narration (BookOrbit is asked when tapped).
function Open.canAddNarration(p, path)
    if not (p and type(path) == "string" and path:lower():match("%.epub$")) then return false end
    local okb, backend = pcall(function() return p:backend() end)
    if not okb or backend ~= "bookorbit" then return false end
    local id = Open.downloadedId(p, path)
    if not id or tostring(id):sub(1, #require("gzreader_bookorbit").AUDIO_PREFIX) == require("gzreader_bookorbit").AUDIO_PREFIX then return false end
    return require("gzreader_narration").quickCheck(path) ~= true
end

--- The hold menu's Download with narration: asks BookOrbit, then the narrated
--- copy replaces the one at `path` (same file: its place, highlights and
--- notes on the Kindle stay).
function Open.addNarration(p, path)
    local InfoMessage = require("ui/widget/infomessage")
    local id, e = Open.downloadedId(p, path)
    if not id then return end
    local RUI = require("apps/reader/readerui").instance
    if RUI and RUI.document and RUI.document.file == path then
        return UIManager():show(InfoMessage:new{ text = _("Close the book first: its copy can't be replaced while it's open.") })
    end
    local title = e.title or path:match("([^/]+)%.[^.]+$")
    local authors
    if type(e.authors) == "string" then
        authors = {}
        for a in e.authors:gmatch("[^\n]+") do authors[#authors + 1] = a end
    end
    local book = { id = tonumber(id) or id, title = title, authors = authors, primaryFileType = "epub",
        primaryFileId = e.file_id }
    require("gzreader_net").run(function()
        require("gzreader_async").run(p.api, function(api) return api:readAloudChoices(book.id) end, function(info)
            if type(info) ~= "table" or not info.has then
                return UIManager():show(InfoMessage:new{ text = T(_("BookOrbit has no narration for “%1”."), title) })
            end
            local size = mb(info.narrated)
            UIManager():show(require("ui/widget/confirmbox"):new{
                text = T(_("Download “%1” with its narration%2?\n\nIt replaces the copy on this Kindle. Your place, highlights and notes stay."),
                    title, size and (" (" .. size .. ")") or ""),
                ok_text = _("Download"),
                ok_callback = function()
                    Log.info("narration: downloading the narrated copy over the one on the Kindle")
                    p:downloadAndOpen(Open.asVariant(book, info, "original"), nil, { no_open = true, gz_asked = true, gz_path = path })
                end,
            })
        end, "read-aloud choices")
    end, { reason = "a book's narration" })
end

---------------------------------------------------------------- a book and its audiobook, neither on the Kindle

--- The choices for a BookOrbit book that has an audiobook too (Home's recently read, the
--- Catalog's Audiobooks page): { { how, label } … }: "narrated" (with its size) when the
--- EPUB has narration, "ebook" (book only), "audio" (the audiobook only). Pure.
function Open.bothChoices(info, audio_bytes)
    local out = {}
    local narrated = info and info.has
    if narrated then
        local m = mb(info.narrated)
        out[#out + 1] = { how = "narrated", label = m and T(_("Narrated book · %1"), m) or _("Narrated book") }
    end
    local t = narrated and Open.textSize(info) or nil
    out[#out + 1] = { how = "ebook", label = t and T(_("Ebook only · %1"), t) or _("Ebook only") }
    local a = mb(audio_bytes)
    out[#out + 1] = { how = "audio", label = a and T(_("Audiobook only · %1"), a) or _("Audiobook only") }
    return out
end

--- The book's id for an audiobook of BookOrbit's ("a104": 104), or nil.
function Open.bookIdOfAudio(id)
    local b = tostring(id or ""):match("^a(%d+)$")
    return b and tonumber(b) or nil
end

--- The audiobook downloaded and played (as its own Download & listen does).
function Open.downloadAudio(p, audio)
    local AB = require("gzreader_audiobook")
    local b = AB.load(p, audio.id)
    if b then return AB.open(p, b) end
    require("ui/network/manager"):runWhenOnline(function()
        AB.download(p, audio, function(got, err)
            if got then AB.open(p, got) else p:showError(err) end
        end)
    end)
end

--- The hold menu's row for `path` (gzreader_homemenu.lua), or nil.
function Open.manageRow(path)
    local p = plugin()
    if not Open.canAddNarration(p, path) then return nil end
    return { text = _("Download with narration"), callback = function() Open.addNarration(p, path) end }
end

return Open
