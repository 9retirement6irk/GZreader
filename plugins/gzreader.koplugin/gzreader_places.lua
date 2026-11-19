--[[--
Where GZreader keeps things: one GZreader folder on the Kindle's (or Kobo's)
drive, beside KOReader rather than in its place.

  GZreader/app/         the program, its settings, logs and cache
  GZreader/books/       the books (and their .sdr folders): KOReader's home folder
  GZreader/music/       downloaded music
  GZreader/audiobooks/  downloaded audiobooks
  GZreader/notes/       Notes kept on the device: notes.json, memos-lacks.json,
                        files/ (attachments), drawings/ (waiting to go to Memos)

(The drive doesn't tell capitals from small letters, so a gzreader/ folder
for the program beside GZreader/ for the books would have been one folder.)

Until 1.35 GZreader was installed in KOReader's place (koreader/, or
.adds/koreader on a Kobo), its books straight in GZreader/, music and
audiobooks in the hidden GZreader/.music and .audiobooks, and the notes in
koreader/settings and koreader/cache. Running from there ("legacy"), these
answer the old places; gzreader_migrate.lua moves everything once.

Sign-ins stay on the device's own disk (gzreader_secrets.lua).

The Nook: its program and settings stay on its own disk (/data/gzreader:
programs can't run from the card, which is FAT); everything else is in
GZreader/ on the card (GZ_NOOK_HOME): app (the parts of the program that are
only read, mounted into it by gzreader.sh, checked against fingerprints on
/data), books, music, audiobooks, notes. Once moved (gzreader_migrate.lua's
NOOK_DONE), these answer the new places.
]]

local lfs = require("libs/libkoreader-lfs")

local Places = {
    FOLDER = "GZreader",
    APP = "app",
    BOOKS = "books",
    MUSIC = "music",
    AUDIOBOOKS = "audiobooks",
    NOTES = "notes",
    app_dir = nil, -- (tests: the app's folder)
}

local function absolute(p)
    if p:sub(1, 1) == "/" then return p end
    local cwd = lfs.currentdir() or "."
    if p == "." then return cwd end
    return cwd .. "/" .. p:gsub("^%./", "")
end

--- The program's folder, absolute (KOReader's data dir: "." on a Kindle or Kobo).
function Places.app()
    if Places.app_dir then return Places.app_dir end
    local ok, DataStorage = pcall(require, "datastorage")
    local d = ok and DataStorage:getDataDir() or "."
    return (absolute(d):gsub("/+$", ""))
end

--- Is `app` (default: this one) GZreader/app, the one-folder layout?
function Places.isNew(app)
    app = app or Places.app()
    local parent, name = app:match("^(.*)/([^/]+)$")
    if not parent or name ~= Places.APP then return false end
    return (parent:match("([^/]+)$") or ""):lower() == Places.FOLDER:lower()
end

--- The Nook's GZreader folder on its card, once moved there (nil: not a Nook, or not yet).
function Places.nookRoot(app)
    local home = os.getenv("GZ_NOOK_HOME")
    if not home or home == "" then return nil end
    app = app or Places.app()
    if lfs.attributes(app .. "/settings/gzreader-folder.done", "mode") ~= "file" then return nil end
    return (home:gsub("/+$", "")) .. "/" .. Places.FOLDER
end

--- The GZreader folder (one-folder layout), or nil (legacy).
function Places.root(app)
    app = app or Places.app()
    if not Places.isNew(app) then return Places.nookRoot(app) end
    return (app:match("^(.*)/[^/]+$"))
end

local function sub(name, legacy)
    local root = Places.root()
    if not root then return legacy end
    local dir = root .. "/" .. name
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    return dir
end

--- The books (KOReader's home folder). `legacy`: the old GZreader folder.
function Places.books(legacy) return sub(Places.BOOKS, legacy) end
--- Downloaded music. `legacy`: the old place (GZreader/.music).
function Places.music(legacy) return sub(Places.MUSIC, legacy) end
--- Downloaded audiobooks. `legacy`: the old place (GZreader/.audiobooks).
function Places.audiobooks(legacy) return sub(Places.AUDIOBOOKS, legacy) end

--- A file or folder of the Notes kept on the device: `name` in GZreader/notes,
--- or `legacy` (its old place in the app's settings or cache).
function Places.notes(name, legacy)
    local dir = sub(Places.NOTES, nil)
    if not dir then return legacy end
    return name and (dir .. "/" .. name) or dir
end

--- After the move into GZreader/ (gzreader_migrate.lua, at this start): logged,
--- and said once on the screen. A Kobo: its library keeps out of GZreader's own folders.
function Places.announce()
    local root = Places.root()
    if not root then return end
    local Log = require("gzreader_log")
    local okd, Device = pcall(require, "device")
    if okd and Device.isKobo and Device:isKobo() then
        local home = root:match("^(.*)/[^/]+$")
        local ok, changed = pcall(function()
            return dofile(Places.app() .. "/plugins/gzreader.koplugin/gzreader_migrate.lua").koboExclude(home .. "/.kobo/Kobo/Kobo eReader.conf")
        end)
        if ok and changed then Log.info("places: the Kobo's library leaves GZreader/app, notes, music and audiobooks alone (ExcludeSyncFolders)") end
    end
    local note = Places.app() .. "/settings/gzreader-moved.json"
    if lfs.attributes(note, "mode") ~= "file" then return end
    local f = io.open(note, "rb")
    local text = f and f:read("*a") or ""
    if f then f:close() end
    os.remove(note)
    local ok, moved = pcall(require("gzreader_json").decode, text)
    if not ok or type(moved) ~= "table" then return end
    Log.info(string.format("places: moved from %s into %s: %d books, %d saved paths in %d files", tostring(moved.from), root,
        tonumber(moved.books) or 0, tonumber(moved.paths) or 0, tonumber(moved.files) or 0))
    local _ = require("gettext")
    local T = require("ffi/util").template
    require("ui/uimanager"):scheduleIn(3, function()
        local said
        if moved.device == "nook" then
            said = T(_("GZreader's things on the card are in one folder now: %1\n\napp: the parts of GZreader kept on the card\nbooks: your books\nmusic, audiobooks: what you downloaded\nnotes: your notes kept here\n\nEverything was moved there, your reading positions with it."), root)
        else
            said = T(_("GZreader now has a folder of its own, beside %2: %1\n\napp: GZreader itself\nbooks: your books\nmusic, audiobooks: what you downloaded\nnotes: your notes kept here\n\nEverything was moved there, your reading positions with it, and the %3 folder is free for %2."), root, "KOReader", "koreader")
        end
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{ text = said })
    end)
end

return Places
