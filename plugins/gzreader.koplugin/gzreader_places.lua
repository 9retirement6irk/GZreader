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

Run from anywhere else (the emulator's tree, the tests), these answer the
places the caller gives ("legacy": the old layout, from before 1.35, when
GZreader was installed in KOReader's place; devices were moved over then).

Sign-ins stay on the device's own disk (gzreader_secrets.lua).

The Nook: its program and settings stay on its own disk (/data/gzreader:
programs can't run from the card, which is FAT); everything else is in
GZreader/ on the card (GZ_NOOK_HOME): app (the parts of the program that are
only read, mounted into it by gzreader.sh, checked against fingerprints on
/data), books, music, audiobooks, notes.
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

--- The Nook's GZreader folder on its card (nil: not a Nook, or its card isn't there).
function Places.nookRoot()
    local home = os.getenv("GZ_NOOK_HOME")
    if not home or home == "" then return nil end
    home = home:gsub("/+$", "")
    if lfs.attributes(home, "mode") ~= "directory" then return nil end
    local root = home .. "/" .. Places.FOLDER
    if lfs.attributes(root, "mode") ~= "directory" then lfs.mkdir(root) end
    return root
end

--- The GZreader folder (one-folder layout), or nil (legacy).
function Places.root(app)
    app = app or Places.app()
    if not Places.isNew(app) then return Places.nookRoot() end
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

--- A Kobo: Nickel's library leaves GZreader's own folders alone (the
--- program, its notes, music and audiobooks), as it leaves hidden folders:
--- its ExcludeSyncFolders setting, in [FeatureSettings] of `conf` (Nickel isn't
--- running while GZreader is; it reads it at its next start). True when changed.
Places.KOBO_EXCLUDE = "GZreader/(app|notes|music|audiobooks)(/.*)?"
Places.KOBO_DEFAULT = "(\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+)"
function Places.koboExclude(conf)
    local f = io.open(conf, "rb")
    if not f then return false end
    local text = f:read("*a")
    f:close()
    if text:find(Places.KOBO_EXCLUDE, 1, true) then return false end
    local lines, found, section, insert_at = {}, false, nil, nil
    for line in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
        local sec = line:match("^%[(.-)%]")
        if sec then section = sec end
        local value = section == "FeatureSettings" and line:match("^ExcludeSyncFolders=(.*)$")
        if value then
            value = value:gsub("\r$", "")
            line = "ExcludeSyncFolders=" .. (value == "" and Places.KOBO_EXCLUDE or ("(" .. value .. ")|" .. Places.KOBO_EXCLUDE))
            found = true
        end
        lines[#lines + 1] = line
        if sec == "FeatureSettings" then insert_at = #lines end
    end
    if not found then
        local entry = "ExcludeSyncFolders=(" .. Places.KOBO_DEFAULT .. ")|" .. Places.KOBO_EXCLUDE
        if insert_at then table.insert(lines, insert_at + 1, entry)
        else lines[#lines + 1] = ""; lines[#lines + 1] = "[FeatureSettings]"; lines[#lines + 1] = entry end
    end
    local tmp = conf .. ".gztmp"
    local out = io.open(tmp, "wb")
    if not out then return false end
    local ok = out:write(table.concat(lines, "\n") .. "\n")
    out:close()
    if not ok then os.remove(tmp); return false end
    return os.rename(tmp, conf) ~= nil
end

--- At each start on a Kobo: its library keeps out of GZreader's own folders
--- (written once; put back if the Kobo's settings were reset).
function Places.keepKoboOut()
    local root = Places.root()
    if not root then return end
    local okd, Device = pcall(require, "device")
    if not (okd and Device.isKobo and Device:isKobo()) then return end
    local home = root:match("^(.*)/[^/]+$")
    local ok, changed = pcall(Places.koboExclude, home .. "/.kobo/Kobo/Kobo eReader.conf")
    if ok and changed then
        require("gzreader_log").info("places: the Kobo's library leaves GZreader/app, notes, music and audiobooks alone (ExcludeSyncFolders)")
    end
end

return Places
