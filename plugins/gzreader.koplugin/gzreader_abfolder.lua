--[[--
Audiobooks on the Kindle's shelves: where they're stored, and the small
stand-in book file each one gets so ZenOS shows it like a book.

Storage: <GZreader folder>/.audiobooks/<book id>/ (hidden: a long book is
thousands of 15-second chunk files that file lists, folder covers and file
search would otherwise walk through).

Stand-ins: <GZreader folder>/Audiobooks/<title>.epub, one per downloaded
audiobook: a tiny EPUB with the title, author and Grimmory's cover. ZenOS
shows them as tiles (Downloads → Audiobooks) and, once played, in Recent and
on Home, with the listening progress. Opening one starts the audiobook
player instead of the reader (the ReaderUI.showReader hook below).

Kept small: starting GZreader loads this, not the player.
]]

local lfs = require("libs/libkoreader-lfs")
local ffiutil = require("ffi/util")
local Log = require("gzreader_log")

local Folder = {
    STORE = ".audiobooks",
    ENTRY = "Audiobooks",
    STUB_VERSION = 2, -- bump to rewrite every stand-in at the next start
}

local function mkdirp(path)
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if lfs.attributes(acc, "mode") == nil then lfs.mkdir(acc) end
    end
end

local function storeDir(plugin, id)
    return plugin:libraryDir() .. "/" .. Folder.STORE .. "/" .. tostring(id)
end

function Folder.entryDir(plugin)
    return plugin:libraryDir() .. "/" .. Folder.ENTRY
end

--- Before 1.3.6 audiobooks were stored in the visible Audiobooks folder:
--- move them into the hidden one (same file system: one rename each).
function Folder.migrate(plugin)
    local lib = plugin:libraryDir()
    local old, new = lib .. "/" .. Folder.ENTRY, lib .. "/" .. Folder.STORE
    if lfs.attributes(old, "mode") ~= "directory" then return 0 end
    local moved = 0
    for name in lfs.dir(old) do
        local from = old .. "/" .. name
        if name ~= "." and name ~= ".." and not name:match("%.sdr$")
                and lfs.attributes(from, "mode") == "directory"
                and lfs.attributes(from .. "/audiobook.json", "mode") == "file" then
            if moved == 0 then
                mkdirp(new)
                -- a conversion left running by a restart would write to the old place
                pcall(function() require("gzreader_recovery").stopConversions(old) end)
            end
            local to = new .. "/" .. name
            if lfs.attributes(to, "mode") == nil then
                local ok, err = os.rename(from, to)
                if ok then moved = moved + 1 else Log.warn("audiobook move failed", name, tostring(err)) end
            end
        end
    end
    if moved > 0 then Log.info("audiobooks moved to the hidden folder:", moved) end
    return moved
end

---------------------------------------------------------------- stand-ins

--- ZenOS's Home module (Recent, the featured book), or nil.
local function zenHome()
    local zen = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen then
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        zen = ok_fm and FileManager.instance and FileManager.instance.zenos
    end
    if not zen then
        local ok_pl, PluginLoader = pcall(require, "pluginloader")
        zen = ok_pl and PluginLoader:getPluginInstance("zenos") or nil
    end
    if not zen then return nil end
    local ok, home = pcall(function() return require("common/shared_state").get(zen, "home") end)
    return ok and home or nil
end


local function xmlEsc(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

--- A file name from the title (unique among the stand-ins and other files).
local function stubName(plugin, id, title)
    local base = tostring(title or ("Audiobook " .. id)):gsub("[/\\:%*%?\"<>|%c]", "_"):gsub("^%.+", "")
    base = base:sub(1, 80):gsub("%s+$", "")
    if base == "" then base = "Audiobook " .. id end
    for other_id, e in pairs(plugin.store.audiobooks or {}) do
        if tostring(other_id) ~= tostring(id) and type(e) == "table" and e.stub == base .. ".epub" then
            return base .. " (" .. id .. ").epub"
        end
    end
    if lfs.attributes(Folder.entryDir(plugin) .. "/" .. base .. ".epub", "mode") then
        return base .. " (" .. id .. ").epub" -- something else of that name is there
    end
    return base .. ".epub"
end

--- Write the stand-in EPUB for audiobook `id` (title, author, cover if
--- downloaded). Returns its path.
function Folder.writeStub(plugin, id)
    local e = plugin.store.audiobooks and plugin.store.audiobooks[id]
    if type(e) ~= "table" then return nil end
    local title = e.title or ("Audiobook " .. id)
    local author = e.author
    local dir = Folder.entryDir(plugin)
    mkdirp(dir)
    e.stub = e.stub or stubName(plugin, id, title)
    local path = dir .. "/" .. e.stub
    local cf = io.open(storeDir(plugin, id) .. "/cover.jpg", "rb")
    local cover = cf and cf:read("*a")
    if cf then cf:close() end
    if cover == "" then cover = nil end
    -- length and narrator for the description (Home shows it)
    local info = {}
    pcall(function()
        local jf = io.open(storeDir(plugin, id) .. "/audiobook.json", "rb")
        if jf then
            info = require("json").decode(jf:read("*a")) or {}
            jf:close()
        end
    end)
    local desc = { "Audiobook" }
    local ms = tonumber(info.durationMs)
    if ms and ms > 0 then
        local m = math.floor(ms / 60000 + 0.5)
        desc[#desc + 1] = m >= 60 and string.format("%d h %d min", math.floor(m / 60), m % 60) or string.format("%d min", m)
    end
    if type(info.narrator) == "string" and info.narrator ~= "" then desc[#desc + 1] = "read by " .. info.narrator end
    local description = table.concat(desc, " · ")

    local Archiver = require("ffi/archiver")
    local epub = Archiver.Writer:new{}
    local tmp = path .. ".tmp"
    if not epub:open(tmp, "epub") then
        Log.warn("audiobook stand-in: can't write", tmp)
        return nil
    end
    local mtime = os.time()
    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", "application/epub+zip", mtime)
    epub:setZipCompression("deflate")
    epub:addFileFromMemory("META-INF/container.xml", [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>]], mtime)
    local manifest = '<item id="page" href="page.xhtml" media-type="application/xhtml+xml"/>'
        .. '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
    local cover_meta = ""
    if cover then
        manifest = manifest .. '<item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>'
        cover_meta = '<meta name="cover" content="cover-image"/>'
        epub:addFileFromMemory("OEBPS/cover.jpg", cover, mtime)
    end
    epub:addFileFromMemory("OEBPS/content.opf", string.format([[<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
<dc:title>%s</dc:title>%s<dc:language>en</dc:language><dc:identifier id="id">gzreader-audiobook-%s</dc:identifier>
<dc:subject>Audiobook</dc:subject><dc:description>%s</dc:description>%s
</metadata>
<manifest>%s</manifest>
<spine toc="ncx"><itemref idref="page"/></spine>
</package>]], xmlEsc(title), author and ("<dc:creator>" .. xmlEsc(author) .. "</dc:creator>") or "",
        xmlEsc(id), xmlEsc(description), cover_meta, manifest), mtime)
    epub:addFileFromMemory("OEBPS/toc.ncx", string.format([[<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="gzreader-audiobook-%s"/></head>
<docTitle><text>%s</text></docTitle><navMap><navPoint id="p" playOrder="1"><navLabel><text>%s</text></navLabel><content src="page.xhtml"/></navPoint></navMap></ncx>]],
        xmlEsc(id), xmlEsc(title), xmlEsc(title)), mtime)
    epub:addFileFromMemory("OEBPS/page.xhtml", string.format([[<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>%s</title></head><body>
<h1>%s</h1>%s<p>This is an audiobook. Open it from Home or Downloads → Audiobooks to listen.</p></body></html>]],
        xmlEsc(title), xmlEsc(title), author and ("<p>" .. xmlEsc(author) .. "</p>") or ""), mtime)
    epub:close()
    os.rename(tmp, path)
    e.stub_version = Folder.STUB_VERSION
    e.stub_cover = cover ~= nil
    plugin:save()
    -- covers and titles are cached by path: forget the old ones
    pcall(function()
        local BIM = require("bookinfomanager")
        if BIM.deleteBookInfo then BIM:deleteBookInfo(path) end
    end)
    pcall(function()
        local home = zenHome()
        if home and home.invalidateBookCache then home.invalidateBookCache(path, true) end
    end)
    Log.info("audiobook stand-in written", id, e.stub, cover and "with cover" or "no cover yet")
    return path
end

--- The audiobook id of a stand-in path, or nil.
function Folder.idForPath(plugin, path)
    if type(path) ~= "string" or not path:match("%.epub$") then return nil end
    local dir = Folder.entryDir(plugin)
    if path:sub(1, #dir + 1) ~= dir .. "/" then
        local real = ffiutil.realpath(path)
        local rdir = ffiutil.realpath(dir) or dir
        if not real or real:sub(1, #rdir + 1) ~= rdir .. "/" then return nil end
        path, dir = real, rdir
    end
    local name = path:sub(#dir + 2)
    for id, e in pairs(plugin.store.audiobooks or {}) do
        if type(e) == "table" and e.stub == name then return id end
    end
end

function Folder.stubPath(plugin, id)
    local e = plugin.store.audiobooks and plugin.store.audiobooks[id]
    return type(e) == "table" and e.stub and (Folder.entryDir(plugin) .. "/" .. e.stub) or nil
end

--- Get Grimmory's cover for audiobook `id` (its square audiobook cover, else
--- the book's), keep it with the audio, rewrite the stand-in with it, then
--- on_done(). Uses a cover the Grimmory tab already downloaded; otherwise
--- fetches in the background, only when Wi-Fi is already up.
function Folder.fetchCover(plugin, id, on_done)
    local e = plugin.store.audiobooks and plugin.store.audiobooks[id]
    if type(e) ~= "table" then return end
    local path = storeDir(plugin, id) .. "/cover.jpg"
    if lfs.attributes(path, "mode") == "file" then
        if not e.stub_cover then Folder.writeStub(plugin, id) end
        if on_done then pcall(on_done) end
        return
    end
    local function done()
        Folder.fetching = nil
        Folder.writeStub(plugin, id)
        if on_done then pcall(on_done) end
    end
    -- the Grimmory tab's cover cache
    local ok_c, Covers = pcall(require, "gzreader_covers")
    if ok_c then
        for _i, kind in ipairs({ "audiobook", "book" }) do
            local src = io.open(Covers.path(id, kind ~= "book" and kind or nil), "rb")
            if src then
                local data = src:read("*a"); src:close()
                local dst = io.open(path, "wb")
                if dst and data and #data > 0 then dst:write(data); dst:close(); return done() end
                if dst then dst:close() end
            end
        end
    end
    if Folder.fetching then return end
    if not (plugin.api and plugin.api:isPaired()) then return end
    local ok_net, Net = pcall(require, "gzreader_net")
    if not (ok_net and Net.connected()) then return end
    Folder.fetching = true
    local Async = require("gzreader_async")
    Async.call(plugin.api, "downloadThumbnail", { id, path, "audiobook" }, function(got)
        if got then return done() end
        Async.call(plugin.api, "downloadThumbnail", { id, path }, function(got2)
            if got2 then return done() end
            Folder.fetching = nil
        end)
    end)
end

--- Stand-ins for every downloaded audiobook (missing ones written).
function Folder.syncStubs(plugin)
    local wrote = 0
    for id, e in pairs(plugin.store.audiobooks or {}) do
        if type(e) == "table" and lfs.attributes(storeDir(plugin, id) .. "/audiobook.json", "mode") == "file" then
            local path = Folder.stubPath(plugin, id)
            if not path or lfs.attributes(path, "mode") ~= "file" or e.stub_version ~= Folder.STUB_VERSION then
                if Folder.writeStub(plugin, id) then wrote = wrote + 1 end
            end
        end
    end
    return wrote
end

--- Listening progress on the tile (percent, like a book's).
function Folder.saveProgress(plugin, id, pos_ms, total_ms)
    local path = Folder.stubPath(plugin, id)
    if not path or not total_ms or total_ms <= 0 or lfs.attributes(path, "mode") ~= "file" then return end
    pcall(function()
        local ds = require("docsettings"):open(path)
        ds:saveSetting("percent_finished", math.max(0, math.min(1, (pos_ms or 0) / total_ms)))
        ds:flush()
    end)
end

--- When played: into Recent / history (like opening a book), with progress.
function Folder.recordPlay(plugin, id, pos_ms, total_ms)
    local path = Folder.stubPath(plugin, id)
    if not path or lfs.attributes(path, "mode") ~= "file" then
        path = Folder.writeStub(plugin, id)
        if not path then return end
    end
    pcall(function() require("readhistory"):addItem(path, os.time()) end)
    Folder.saveProgress(plugin, id, pos_ms, total_ms)
    Folder.refreshHome(path)
end

--- ZenOS's Home rebuilds Recent when a book closes in the reader, which an
--- audiobook never does: ask it to.
function Folder.refreshHome(path)
    pcall(function()
        local home = zenHome()
        if not home then return end
        if home.invalidateBookCache then home.invalidateBookCache(path, true) end
        if home.rebuildActive then
            require("ui/uimanager"):nextTick(function() pcall(home.rebuildActive) end)
        end
    end)
end

--- Remove an audiobook's stand-in (and its history entry and settings).
function Folder.removeStub(plugin, id)
    local path = Folder.stubPath(plugin, id)
    if not path then return end
    pcall(function() require("readhistory"):removeItemByPath(path) end)
    os.remove(path)
    local sdr = path:gsub("%.epub$", ".sdr")
    if lfs.attributes(sdr, "mode") == "directory" then pcall(ffiutil.purgeDir, sdr) end
    pcall(function()
        local BIM = require("bookinfomanager")
        if BIM.deleteBookInfo then BIM:deleteBookInfo(path) end
    end)
    Folder.refreshHome(path)
end

---------------------------------------------------------------- opening

--- Opening a stand-in (from a tile, Recent, Continue, History or search)
--- opens the audiobook player instead of the reader.
function Folder.install(plugin)
    Folder.plugin = plugin
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._gz_audiobook_hook then return end
    ReaderUI._gz_audiobook_hook = true
    local orig = ReaderUI.showReader
    function ReaderUI:showReader(file, ...)
        local p = Folder.plugin
        local id = p and Folder.idForPath(p, file)
        if id then
            Folder.open(p, id)
            return
        end
        return orig(self, file, ...)
    end
end

function Folder.open(plugin, id)
    -- ZenOS may have set up an opening banner for the tapped cover
    local set_cover = rawget(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER")
    if type(set_cover) == "function" then pcall(set_cover, nil) end
    local Audiobook = require("gzreader_audiobook")
    local book = Audiobook.load(plugin, id)
    if book then return Audiobook.open(plugin, book) end
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{ text = _("This audiobook's audio isn't on the Kindle any more. Download it again from the Grimmory tab → Audiobooks.") })
end

--- At start: move old storage, hook opening, make missing stand-ins.
function Folder.start(plugin)
    Folder.migrate(plugin)
    Folder.install(plugin)
    if next(plugin.store.audiobooks or {}) then
        Folder.syncStubs(plugin)
        -- covers for stand-ins without one, once Wi-Fi is up anyway
        require("ui/uimanager"):scheduleIn(30, function()
            for id, e in pairs(plugin.store.audiobooks or {}) do
                if type(e) == "table" and e.stub and not e.stub_cover then
                    return Folder.fetchCover(plugin, id)
                end
            end
        end)
    end
end

return Folder
