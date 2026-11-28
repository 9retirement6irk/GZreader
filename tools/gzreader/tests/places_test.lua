-- Where GZreader keeps things (gzreader_places.lua): the one GZreader folder
-- beside KOReader, the Nook's folder on its card, and a Kobo's own library
-- kept out of GZreader's folders. (The move from KOReader's place in 1.35 is
-- gone: no start checks for the old layout any more.)
--   luajit places_test.lua <repo> <koreader base> <work dir>
local REPO, KO, WORK = arg[1], arg[2], arg[3]
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. KO .. "/frontend/?.lua;" .. KO .. "/?.lua;" .. package.path
package.cpath = KO .. "/?.so;" .. KO .. "/libs/?.so;" .. package.cpath
local ok_lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then
    -- (no KOReader libraries for this machine: LuaFileSystem as it)
    package.preload["libs/libkoreader-lfs"] = function() return require("lfs") end
end

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function write(p, s)
    os.execute("mkdir -p '" .. p:match("^(.*)/[^/]*$") .. "'")
    local f = assert(io.open(p, "wb")); f:write(s); f:close()
end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local lfs = require("libs/libkoreader-lfs")
local function isDir(p) return lfs.attributes(p, "mode") == "directory" end

print("== where GZreader looks (gzreader_places)")
local P = dofile(REPO .. "/plugins/gzreader.koplugin/gzreader_places.lua")
do
    os.execute("mkdir -p '" .. WORK .. "/us/GZreader/app'")
    P.app_dir = WORK .. "/us/GZreader/app"
    check(P.isNew() and P.root() == WORK .. "/us/GZreader" and P.books("x") == WORK .. "/us/GZreader/books"
        and P.music("x") == WORK .. "/us/GZreader/music" and P.audiobooks("x") == WORK .. "/us/GZreader/audiobooks"
        and P.notes("notes.json", "x") == WORK .. "/us/GZreader/notes/notes.json", "in GZreader/app: books, music, audiobooks, notes beside it")
    P.app_dir = "/mnt/us/koreader"
    check(not P.isNew() and P.root() == nil and P.books("old") == "old" and P.notes("notes.json", "old") == "old",
        "anywhere else (the emulator's tree, the tests): the places the caller gives")
    P.app_dir = "/mnt/us/gzreader/app"
    check(P.isNew(), "…the drive's capitals don't matter (gzreader/app is GZreader/app)")
    P.app_dir = "/mnt/us/Other/app"
    check(not P.isNew(), "an app folder elsewhere: not GZreader's")
end

print("== the Nook: GZreader's folder on its card")
do
    -- (os.getenv can't be set from Lua: Places asks it, so it's stood in for the block)
    local real_getenv = os.getenv
    local card = WORK .. "/card"
    os.execute("rm -rf '" .. card .. "' && mkdir -p '" .. card .. "'")
    os.getenv = function(k) if k == "GZ_NOOK_HOME" then return card .. "/" end return real_getenv(k) end -- luacheck: ignore
    P.app_dir = WORK .. "/data/gzreader"
    check(P.root() == card .. "/GZreader" and isDir(card .. "/GZreader") and P.books("old") == card .. "/GZreader/books"
        and isDir(card .. "/GZreader/books"),
        "the program on /data, everything else in GZreader/ on the card, made when it isn't there (a new Nook needs no marker)")
    os.getenv = function(k) if k == "GZ_NOOK_HOME" then return WORK .. "/no-card" end return real_getenv(k) end -- luacheck: ignore
    check(P.root() == nil and P.books("old") == "old", "no card there (it's a USB drive on a computer): the caller's places, nothing made")
    os.getenv = function(k) if k == "GZ_NOOK_HOME" then return "" end return real_getenv(k) end -- luacheck: ignore
    check(P.nookRoot() == nil, "not a Nook: no such folder")
    os.getenv = real_getenv -- luacheck: ignore
end

print("== a Kobo: its library leaves GZreader's own folders alone")
do
    local conf = WORK .. "/Kobo eReader.conf"
    write(conf, "[ApplicationPreferences]\nfoo=1\n\n[FeatureSettings]\nExcludeSyncFolders=(\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+)\n")
    check(P.koboExclude(conf) and read(conf):find("ExcludeSyncFolders=((\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+))|GZreader/(app|notes|music|audiobooks)(/.*)?", 1, true),
        "the Kobo's own line kept, GZreader's folders added")
    local once = read(conf)
    check(not P.koboExclude(conf) and read(conf) == once, "…once")
    write(conf, "[ApplicationPreferences]\nfoo=1\n")
    check(P.koboExclude(conf) and read(conf):find("[FeatureSettings]\nExcludeSyncFolders=(", 1, true)
        and read(conf):find("|GZreader/(app|notes|music|audiobooks)(/.*)?", 1, true), "no such line: hidden folders and GZreader's (a section of its own)")
    check(P.koboExclude(WORK .. "/none.conf") == false, "no settings file: nothing written")
end

print("== no move at start any more")
do
    local reader = read(REPO .. "/reader.lua")
    check(not reader:find("gzreader_migrate", 1, true) and not reader:find("os.exit(85)", 1, true)
        and read(REPO .. "/plugins/gzreader.koplugin/gzreader_migrate.lua") == nil,
        "reader.lua starts straight away: no move module run before anything else")
    local main = read(REPO .. "/plugins/gzreader.koplugin/main.lua")
    check(main:find('require("gzreader_places").keepKoboOut()', 1, true) and not main:find("announce()", 1, true),
        "a Kobo's exclusion is still checked at start; nothing is announced")
    for _i, f in ipairs({ "/plugins/zenos.koplugin/kindle-launcher/GZreader.sh", "/plugins/gzreader.koplugin/launchers/kindle/extensions/gzreader/bin/start.sh" }) do
        local t = read(REPO .. f)
        check(t:find("APP=/mnt/us/GZreader/app", 1, true) and not t:find("APP=/mnt/us/koreader", 1, true),
            "the launcher starts GZreader/app, with no fallback to KOReader's folder (" .. f:match("[^/]+$") .. ")")
    end
end

print(("places: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
