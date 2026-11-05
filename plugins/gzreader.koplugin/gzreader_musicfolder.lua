--[[--
Downloaded music on the Kindle's shelves, like audiobooks
(gzreader_abfolder.lua): <GZreader folder>/Music/<album>.epub, one small
stand-in EPUB per downloaded album or playlist (title, artist, cover), so
Downloads shows a Music folder (on the bookshelf: a CD player with
headphones, gzreader_shelfview.lua). Opening one plays it and shows the
Music tab's player.

The music itself stays in the hidden .music folder (gzreader_music.lua).
Stand-ins are made at start, after a download finishes and after a delete;
plugin.store.music_stubs maps a stand-in's file name to its music folder.
]]

local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local Folder = {
    ENTRY = "Music",
    STUB_VERSION = 1,
}

local function xmlEsc(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

function Folder.entryDir(plugin) return plugin:libraryDir() .. "/" .. Folder.ENTRY end

local function stubs(plugin)
    plugin.store.music_stubs = plugin.store.music_stubs or {}
    return plugin.store.music_stubs
end

local function nameFor(plugin, c)
    local base = tostring(c.title or c.key or "Music"):gsub("[/\\:%*%?\"<>|%c]", "_"):gsub("^%.+", "")
    base = base:sub(1, 80):gsub("%s+$", "")
    if base == "" then base = "Music" end
    local name = base .. ".epub"
    local taken = stubs(plugin)[name]
    if (taken and taken ~= c.dir:match("[^/]+$")) or (not taken and lfs.attributes(Folder.entryDir(plugin) .. "/" .. name, "mode")) then
        name = base .. " (" .. tostring(c.key or os.time()) .. ").epub"
    end
    return name
end

--- Write the stand-in for collection c (Music.load). Returns its path.
function Folder.writeStub(plugin, c)
    local dir = Folder.entryDir(plugin)
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local folder = c.dir:match("[^/]+$")
    local name
    for n, f in pairs(stubs(plugin)) do if f == folder then name = n end end
    name = name or nameFor(plugin, c)
    local path = dir .. "/" .. name
    local cf = io.open(c.dir .. "/cover.jpg", "rb")
    local cover = cf and cf:read("*a")
    if cf then cf:close() end
    if cover == "" then cover = nil end
    local n = #(c.tracks or {})
    local description = (c.kind == "playlist" and "Playlist" or "Album") .. " · " .. n .. (n == 1 and " track" or " tracks")
        .. (c.year and (" · " .. tostring(c.year)) or "")
    local Archiver = require("ffi/archiver")
    local epub = Archiver.Writer:new{}
    local tmp = path .. ".tmp"
    if not epub:open(tmp, "epub") then
        Log.warn("music stand-in: can't write", tmp)
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
    local cover_meta = ""
    if cover then
        manifest = manifest .. '<item id="cover-image" href="cover.jpg" media-type="image/jpeg"/>'
        cover_meta = '<meta name="cover" content="cover-image"/>'
        epub:addFileFromMemory("OEBPS/cover.jpg", cover, mtime)
    end
    local artist = c.artist
    epub:addFileFromMemory("OEBPS/content.opf", string.format([[<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
<dc:title>%s</dc:title>%s<dc:language>en</dc:language><dc:identifier id="id">gzreader-music-%s</dc:identifier>
<dc:subject>Music</dc:subject><dc:description>%s</dc:description>%s
</metadata>
<manifest>%s</manifest>
<spine><itemref idref="page"/></spine>
</package>]], xmlEsc(c.title or folder), artist and ("<dc:creator>" .. xmlEsc(artist) .. "</dc:creator>") or "",
        xmlEsc(folder), xmlEsc(description), cover_meta, manifest), mtime)
    epub:addFileFromMemory("OEBPS/page.xhtml", string.format([[<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>%s</title></head><body>
<h1>%s</h1><p>%s</p><p>This is music. Open it from Downloads → Music to listen.</p></body></html>]],
        xmlEsc(c.title or folder), xmlEsc(c.title or folder), xmlEsc(description)), mtime)
    epub:close()
    os.rename(tmp, path)
    stubs(plugin)[name] = folder
    plugin:save()
    pcall(function()
        local BIM = require("bookinfomanager")
        if BIM.deleteBookInfo then BIM:deleteBookInfo(path) end
    end)
    Log.info("music stand-in written", folder, cover and "with cover" or "no cover")
    return path
end

--- Stand-ins for everything downloaded; none for what's gone.
function Folder.sync(plugin)
    local Music = require("gzreader_music")
    local have = {}
    for _i, c in ipairs(Music.downloaded(plugin)) do
        local folder = c.dir:match("[^/]+$")
        have[folder] = true
        local exists
        for n, f in pairs(stubs(plugin)) do
            if f == folder and lfs.attributes(Folder.entryDir(plugin) .. "/" .. n, "mode") == "file" then exists = true end
        end
        if not exists then pcall(Folder.writeStub, plugin, c) end
    end
    for n, f in pairs(stubs(plugin)) do
        if not have[f] then
            os.remove(Folder.entryDir(plugin) .. "/" .. n)
            stubs(plugin)[n] = nil
            Log.info("music stand-in removed", f)
        end
    end
    -- an empty Music folder isn't shown
    local dir = Folder.entryDir(plugin)
    if next(stubs(plugin)) == nil and lfs.attributes(dir, "mode") == "directory" then pcall(lfs.rmdir, dir) end
    plugin:save()
end

--- The music folder (in .music) of a stand-in's path, or nil.
function Folder.folderForPath(plugin, path)
    if type(path) ~= "string" then return nil end
    local dir, name = path:match("^(.*)/([^/]+%.epub)$")
    if not dir or dir ~= Folder.entryDir(plugin) then return nil end
    return stubs(plugin)[name]
end

--- Opening a stand-in plays it (and shows the player).
function Folder.install(plugin)
    Folder.plugin = plugin
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._gz_music_hook then return end
    ReaderUI._gz_music_hook = true
    local orig = ReaderUI.showReader
    function ReaderUI:showReader(file, ...)
        local p = Folder.plugin
        local folder = p and Folder.folderForPath(p, file)
        if folder then return Folder.open(p, folder) end
        return orig(self, file, ...)
    end
end

function Folder.open(plugin, folder)
    local set_cover = rawget(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER")
    if type(set_cover) == "function" then pcall(set_cover, nil) end
    local Music = require("gzreader_music")
    local c = Music.load(Music.root(plugin) .. "/" .. folder)
    if not c or (c.have or 0) == 0 then
        local _ = require("gettext")
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("This music isn't on the Kindle any more. Download it again from the Music tab.") })
        return
    end
    Music.play(plugin, c, 1)
    pcall(function() require("gzreader_musictab").open(plugin) end)
end

function Folder.start(plugin)
    Folder.install(plugin)
    pcall(Folder.sync, plugin)
end

return Folder
