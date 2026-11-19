-- GZreader moving out of KOReader's folder into its own (gzreader_migrate.lua,
-- gzreader_places.lua): a Kindle's (and a Kobo's) drive laid out as before
-- 1.35, moved; books, music, audiobooks and notes in place, every saved path
-- rewritten, the launchers pointed at GZreader/app, a move cut short finished.
--   luajit migrate_test.lua <repo> <koreader base> <work dir>
local REPO, KO, WORK = arg[1], arg[2], arg[3]
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. KO .. "/frontend/?.lua;" .. KO .. "/?.lua;" .. package.path
package.cpath = KO .. "/?.so;" .. KO .. "/libs/?.so;" .. package.cpath
local ok_lfs = pcall(require, "libs/libkoreader-lfs")
if not ok_lfs then
    -- (no KOReader libraries for this machine: LuaFileSystem as it)
    package.preload["libs/libkoreader-lfs"] = function() return require("lfs") end
end
local lfs = require("libs/libkoreader-lfs")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function write(p, s)
    os.execute("mkdir -p '" .. p:match("^(.*)/[^/]*$") .. "'")
    local f = assert(io.open(p, "wb")); f:write(s); f:close()
end
local function read(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("*a"); f:close(); return s end
local function exists(p) return lfs.attributes(p, "mode") ~= nil end

local M = dofile(REPO .. "/plugins/gzreader.koplugin/gzreader_migrate.lua")
M.log = function() end

-- a Kindle's drive before 1.35
local function kindleDrive(home)
    os.execute("rm -rf '" .. home .. "' && mkdir -p '" .. home .. "'")
    local A, L = home .. "/koreader", home .. "/GZreader"
    write(A .. "/koreader.sh", "#!/bin/sh\n")
    os.execute("mkdir -p '" .. A .. "/plugins'")
    os.execute("cp -r '" .. REPO .. "/plugins/gzreader.koplugin' '" .. REPO .. "/plugins/zenos.koplugin' '" .. A .. "/plugins/'")
    write(A .. "/settings.reader.lua", '-- we can read Lua syntax here!\nreturn {\n    ["home_dir"] = "' .. L .. '",\n    ["lastfile"] = "' .. L .. '/Dog Days.epub",\n    ["screensaver_dir"] = "' .. A .. '/screensavers",\n}\n')
    write(A .. "/history.lua", 'return {\n    [1] = {\n        ["file"] = "' .. L .. '/Dog Days.epub",\n        ["time"] = 1795000000,\n    },\n    [2] = {\n        ["file"] = "/mnt/elsewhere/Other.epub",\n        ["time"] = 1794000000,\n    },\n}\n')
    write(A .. "/settings/collection.lua", 'return {\n    ["favorites"] = {\n        ["' .. L .. '/Dog Days.epub"] = {\n            ["file"] = "' .. L .. '/Dog Days.epub",\n            ["order"] = 1,\n        },\n    },\n}\n')
    write(A .. "/settings/gzreader.lua", 'return {\n    ["library_dir"] = "' .. L .. '",\n    ["downloads"] = {\n        ["42"] = "' .. L .. '/Dog Days.epub",\n    },\n    ["memos"] = {\n        ["queue"] = {\n            [1] = {\n                ["drawings"] = {\n                    [1] = {\n                        ["path"] = "./settings/gzreader-drawings/20261118-a.png",\n                    },\n                },\n            },\n        },\n    },\n}\n')
    write(A .. "/settings/zen_ui/config.lua", 'return { ["shelf_folder"] = "' .. L .. '/Comics" }\n')
    write(A .. "/settings/gzreader_index.json", '{"books":{"42":{"path":"' .. L:gsub("/", "\\/") .. '\\/Dog Days.epub"}}}\n')
    write(A .. "/settings/gzreader-notes.json", '{"memos":[]}')
    write(A .. "/settings/gzreader-memos-lacks.json", '{}')
    write(A .. "/settings/gzreader-drawings/20261118-a.png", "PNG")
    write(A .. "/cache/gzreader-notes/abc-photo.jpg", "JPG")
    write(A .. "/settings/docprops_cache.sqlite", "cache")
    write(L .. "/Dog Days.epub", "EPUB")
    write(L .. "/Dog Days.sdr/metadata.epub.lua", 'return {\n    ["doc_path"] = "' .. L .. '/Dog Days.epub",\n    ["last_xpointer"] = "/body/DocFragment[3]",\n}\n')
    write(L .. "/Comics/Batman.cbz", "CBZ")
    write(L .. "/Audiobooks/Dune.epub", "STUB")
    write(L .. "/.music/album-7/01.mp3", "MP3")
    write(L .. "/.audiobooks/12/audiobook.json", '{"id":12}')
    write(home .. "/extensions/koreader/menu.json", '{"items":[{"name":"GZreader","action":"/mnt/us/koreader/koreader.sh"}]}')
    write(home .. "/launchpad/koreader.ini", "G G = !/mnt/us/koreader/koreader.sh # GZreader\n")
    write(home .. "/documents/GZreader.sh", "# Name: GZreader\n# Version: 1.2.0\n/mnt/us/koreader/koreader.sh\n")
    return A, L
end

print("== a Kindle's drive before 1.35, moved")
do
    local home = WORK .. "/us"
    local A, L = kindleDrive(home)
    local R = home .. "/GZreader"
    local target = M.run({ home = home, app = A, device = "kindle" })
    check(target == R .. "/app" and exists(R .. "/app/koreader.sh") and not exists(A), "the program: koreader/ → GZreader/app")
    check(exists(R .. "/books/Dog Days.epub") and exists(R .. "/books/Dog Days.sdr/metadata.epub.lua") and exists(R .. "/books/Comics/Batman.cbz")
        and exists(R .. "/books/Audiobooks/Dune.epub") and not exists(R .. "/Dog Days.epub"),
        "the books, their .sdr folders and sub-folders → GZreader/books")
    check(exists(R .. "/music/album-7/01.mp3") and exists(R .. "/audiobooks/12/audiobook.json") and not exists(R .. "/.music") and not exists(R .. "/.audiobooks"),
        "music and audiobooks → GZreader/music, GZreader/audiobooks (no longer hidden)")
    check(exists(R .. "/notes/notes.json") and exists(R .. "/notes/memos-lacks.json") and exists(R .. "/notes/drawings/20261118-a.png")
        and exists(R .. "/notes/files/abc-photo.jpg"), "Notes kept on the Kindle → GZreader/notes (notes, attachments, drawings waiting)")
    local s = read(R .. "/app/settings.reader.lua")
    check(s:find('"home_dir"] = "' .. R .. '/books"', 1, true) and s:find('"lastfile"] = "' .. R .. '/books/Dog Days.epub"', 1, true)
        and s:find('"screensaver_dir"] = "' .. R .. '/app/screensavers"', 1, true), "KOReader's settings: home folder, last book, the program's own paths")
    local h = read(R .. "/app/history.lua") or ""
    check(h:find(R .. "/books/Dog Days.epub", 1, true) and h:find("/mnt/elsewhere/Other.epub", 1, true),
        "reading history (KOReader's history.lua, beside the settings): moved books' paths, others as they were")
    local c = read(R .. "/app/settings/collection.lua")
    local count, at = 0, 1
    while true do local i = c:find(R .. "/books/Dog Days.epub", at, true); if not i then break end; count, at = count + 1, i + 1 end
    check(count == 2, "collections: the key and the file (" .. count .. ")")
    local g = read(R .. "/app/settings/gzreader.lua")
    check(g:find('"library_dir"] = "' .. R .. '/books"', 1, true) and g:find('"42"] = "' .. R .. '/books/Dog Days.epub"', 1, true)
        and g:find('"path"] = "' .. R .. '/notes/drawings/20261118-a.png"', 1, true), "GZreader's state: the books' folder, downloads, a queued drawing's place")
    check(read(R .. "/app/settings/zen_ui/config.lua"):find(R .. "/books/Comics", 1, true) ~= nil, "ZenOS's settings too")
    check(read(R .. "/app/settings/gzreader_index.json"):find((R .. "/books/Dog Days.epub"):gsub("/", "\\/"), 1, true) ~= nil, "JSON (with \\/) too")
    check(read(R .. "/books/Dog Days.sdr/metadata.epub.lua"):find('"doc_path"] = "' .. R .. '/books/Dog Days.epub"', 1, true) ~= nil,
        "a book's own settings: where the book is")
    check(not exists(R .. "/app/settings/docprops_cache.sqlite"), "caches kept by path: dropped (made again)")
    local kual = read(home .. "/extensions/gzreader/menu.json") or ""
    check(not exists(home .. "/extensions/koreader") and kual:find('"/mnt/us/GZreader/app/koreader.sh"', 1, true)
        and not kual:find("start.sh", 1, true) and M.kualReady(home),
        "KUAL: GZreader's own entry (extensions/gzreader), starting GZreader/app/koreader.sh itself; its old one in KOReader's place gone")
    check(not exists(home .. "/launchpad/koreader.ini") and read(home .. "/launchpad/gzreader.ini"):find("/mnt/us/GZreader/app/koreader.sh", 1, true),
        "launchpad: gzreader.ini, to GZreader/app")
    check(read(home .. "/documents/GZreader.sh"):find("APP=/mnt/us/GZreader/app", 1, true) ~= nil, "the home-screen item: to GZreader/app")
    local note = read(R .. "/app/settings/gzreader-moved.json") or ""
    check(note:find('"books":4', 1, true) and note:find('"device":"kindle"', 1, true), "a note for GZreader to say it moved, once (" .. note:gsub("\n", "") .. ")")
    -- the rules again: nothing changes (a file rewritten twice stays right)
    local again, n = M.rewriteText(g, M.rules({ app = A, lib = L, root = R }), R)
    check(n == 0 and again == g, "a path already moved isn't moved again")
    check(M.run({ home = home, app = A, device = "kindle" }) == nil, "done once: GZreader/app is there, nothing moves again")
end

print("== a move cut short (the battery ran out), finished at the next start")
do
    local home = WORK .. "/us2"
    local A, L = kindleDrive(home)
    local R = home .. "/GZreader"
    -- (half done: some books moved, music moved, the program not)
    os.execute("mkdir -p '" .. R .. "/books' && mv '" .. L .. "/Comics' '" .. R .. "/books/' && mv '" .. L .. "/.music' '" .. R .. "/music'")
    os.execute("mkdir -p '" .. L .. "/.audiobooks/13' && touch '" .. L .. "/.audiobooks/13/a.mp3' && mkdir -p '" .. R .. "/audiobooks/12' && mv '" .. L .. "/.audiobooks/12/audiobook.json' '" .. R .. "/audiobooks/12/'")
    local target = M.run({ home = home, app = A, device = "kindle" })
    check(target and exists(R .. "/books/Comics/Batman.cbz") and exists(R .. "/books/Dog Days.epub") and exists(R .. "/music/album-7/01.mp3")
        and exists(R .. "/audiobooks/12/audiobook.json") and exists(R .. "/audiobooks/13/a.mp3") and not exists(L .. "/.audiobooks"),
        "what was moved stays, the rest follows (a folder half moved: its insides)")
end

print("== where GZreader looks (gzreader_places)")
do
    local P = dofile(REPO .. "/plugins/gzreader.koplugin/gzreader_places.lua")
    P.app_dir = WORK .. "/us/GZreader/app"
    check(P.isNew() and P.root() == WORK .. "/us/GZreader" and P.books("x") == WORK .. "/us/GZreader/books"
        and P.music("x") == WORK .. "/us/GZreader/music" and P.audiobooks("x") == WORK .. "/us/GZreader/audiobooks"
        and P.notes("notes.json", "x") == WORK .. "/us/GZreader/notes/notes.json", "in GZreader/app: books, music, audiobooks, notes beside it")
    P.app_dir = "/mnt/us/koreader"
    check(not P.isNew() and P.root() == nil and P.books("old") == "old" and P.notes("notes.json", "old") == "old", "in koreader/ (before the move): the old places")
    P.app_dir = "/mnt/us/gzreader/app"
    check(P.isNew(), "…the drive's capitals don't matter (gzreader/app is GZreader/app)")
    P.app_dir = "/mnt/us/Other/app"
    check(not P.isNew(), "an app folder elsewhere: not GZreader's")
end

print("== a Kobo: its library leaves GZreader's own folders alone")
do
    local conf = WORK .. "/Kobo eReader.conf"
    write(conf, "[ApplicationPreferences]\nfoo=1\n\n[FeatureSettings]\nExcludeSyncFolders=(\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+)\n")
    check(M.koboExclude(conf) and read(conf):find("ExcludeSyncFolders=((\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+))|GZreader/(app|notes|music|audiobooks)(/.*)?", 1, true),
        "the Kobo's own line kept, GZreader's folders added")
    local once = read(conf)
    check(not M.koboExclude(conf) and read(conf) == once, "…once")
    write(conf, "[ApplicationPreferences]\nfoo=1\n")
    check(M.koboExclude(conf) and read(conf):find("[FeatureSettings]\nExcludeSyncFolders=(", 1, true)
        and read(conf):find("|GZreader/(app|notes|music|audiobooks)(/.*)?", 1, true), "no such line: hidden folders and GZreader's (a section of its own)")
    local home = WORK .. "/onboard"
    os.execute("rm -rf '" .. home .. "'")
    local A, L = home .. "/.adds/koreader", home .. "/GZreader"
    write(A .. "/koreader.sh", "#!/bin/sh\n")
    os.execute("mkdir -p '" .. A .. "/plugins' && cp -r '" .. REPO .. "/plugins/gzreader.koplugin' '" .. A .. "/plugins/'")
    write(L .. "/Book.epub", "EPUB")
    write(home .. "/.adds/nm/gzreader", "menu_item:main:GZreader:cmd_spawn:quiet:exec /mnt/onboard/.adds/koreader/koreader.sh\n")
    write(home .. "/.kobo/Kobo/Kobo eReader.conf", "[FeatureSettings]\n")
    local target = M.run({ home = home, app = A, device = "kobo" })
    check(target == L .. "/app" and exists(L .. "/books/Book.epub") and read(home .. "/.adds/nm/gzreader"):find("/mnt/onboard/GZreader/app/koreader.sh", 1, true)
        and read(home .. "/.kobo/Kobo/Kobo eReader.conf"):find("GZreader/(app", 1, true),
        "a Kobo: .adds/koreader → GZreader/app, NickelMenu's item to it, the Kobo's library told")
end

do -- the books' folder GZreader remembered: taken only when it's a GZreader folder on this drive
    check(M.ownLibrary("/mnt/us/GZreader", "/mnt/us") and M.ownLibrary("/mnt/us/documents/gzreader", "/mnt/us")
        and not M.ownLibrary("/mnt/us/documents", "/mnt/us") and not M.ownLibrary("/mnt/base-us/GZreader", "/mnt/us")
        and not M.ownLibrary(nil, "/mnt/us") and not M.ownLibrary("/mnt/usx/GZreader", "/mnt/us"),
        "the remembered books' folder: a GZreader folder on this drive (documents/GZreader too), never documents itself or another drive")
    local home = WORK .. "/lib-elsewhere"
    os.execute("rm -rf '" .. home .. "'")
    local A, L = home .. "/koreader", home .. "/GZreader"
    write(A .. "/koreader.sh", "#!/bin/sh\n")
    os.execute("mkdir -p '" .. A .. "/plugins' && cp -r '" .. REPO .. "/plugins/gzreader.koplugin' '" .. A .. "/plugins/'")
    write(L .. "/Here.epub", "EPUB")
    local other = WORK .. "/lib-other-drive/documents"
    write(other .. "/Theirs.epub", "EPUB")
    local target = M.run({ home = home, app = A, lib = other, device = "kindle" })
    check(target == L .. "/app" and exists(L .. "/books/Here.epub") and exists(other .. "/Theirs.epub")
        and not exists(L .. "/books/Theirs.epub"),
        "a remembered folder that isn't GZreader's own (documents, another drive): left alone; GZreader/'s books moved")
    os.execute("rm -rf '" .. WORK .. "/lib-other-drive'")
end

do -- the Nook: its program stays on /data; the rest into GZreader/ on the card, once (no restart)
    local card, data = WORK .. "/nook-card", WORK .. "/nook-data"
    os.execute("rm -rf '" .. card .. "' '" .. data .. "'")
    local A, L = data .. "/gzreader/koreader", card .. "/GZreader"
    write(A .. "/luajit", "ELF")
    write(A .. "/settings/gzreader.lua", 'return {\n    ["library_dir"] = "' .. L .. '",\n}\n')
    write(A .. "/settings/history.lua", 'return {\n    [1] = {\n        ["file"] = "' .. L .. '/Nook Book.epub",\n    },\n}\n')
    write(A .. "/settings/gzreader-notes.json", '{"notes":[]}')
    write(A .. "/settings/gzreader-drawings/w.png", "PNG")
    write(L .. "/Nook Book.epub", "EPUB")
    write(L .. "/Nook Book.sdr/metadata.epub.lua", 'return {\n    ["doc_path"] = "' .. L .. '/Nook Book.epub",\n}\n')
    write(L .. "/.music/a/1.mp3", "MP3")
    write(L .. "/app/.gz-app", "") -- (the parts of the program on the card: gzreader.sh's)
    write(L .. "/app/frontend/ui.lua", "ui")
    local target, why = M.run({ home = card, app = A, lib = L, device = "nook", keep_app = true })
    check(target == A and exists(A .. "/luajit") and exists(L .. "/books/Nook Book.epub") and exists(L .. "/music/a/1.mp3")
        and read(L .. "/app/frontend/ui.lua") == "ui" and not exists(L .. "/books/app"),
        "the Nook: the program stays on /data; the books and music into GZreader/ on the card; GZreader/app (the card's part) left as it is ("
            .. tostring(target or why) .. ")")
    check(read(L .. "/notes/notes.json") == '{"notes":[]}' and not exists(A .. "/settings/gzreader-notes.json")
        and read(L .. "/notes/drawings/w.png") == "PNG",
        "…the notes off the Nook's small disk onto the card (copied across: another disk)")
    check((read(A .. "/settings/history.lua") or ""):find(L .. "/books/Nook Book.epub", 1, true) ~= nil
        and (read(L .. "/books/Nook Book.sdr/metadata.epub.lua") or ""):find(L .. "/books/Nook Book.epub", 1, true) ~= nil
        and exists(A .. "/" .. M.NOOK_DONE) and (read(A .. "/settings/gzreader-moved.json") or ""):find('"device":"nook"', 1, true) ~= nil,
        "…the saved paths follow (history, the book's own settings); done once (noted on /data)")
    local again, why2 = M.run({ home = card, app = A, lib = L, device = "nook", keep_app = true })
    check(again == nil and why2 == "moved already", "…and not again")
    -- (from reader.lua, as the Nook starts it: GZ_NOOK_HOME, in the program's folder)
    os.execute("rm -f '" .. A .. "/" .. M.NOOK_DONE .. "'")
    write(L .. "/Second.epub", "EPUB")
    local cmd = string.format("cd '%s' && GZ_NOOK_HOME='%s' luajit -e \"package.path='%s/?.lua;'..package.path; "
        .. "package.cpath='%s/?.so;%s/libs/?.so;'..package.cpath; "
        .. "if not pcall(require,'libs/libkoreader-lfs') then package.preload['libs/libkoreader-lfs']=function() return require('lfs') end end; "
        .. "io.write(tostring(dofile('%s/plugins/gzreader.koplugin/gzreader_migrate.lua').early()))\" 2>/dev/null",
        A, card, KO, KO, KO, REPO)
    local h = io.popen(cmd)
    local out = h and h:read("*a") or ""
    if h then h:close() end
    check(out == "nil" and exists(L .. "/books/Second.epub") and exists(A .. "/" .. M.NOOK_DONE),
        "…from reader.lua on a Nook (GZ_NOOK_HOME): moved, and no restart asked (" .. out .. ")")
    local cmd2 = string.format("GZ_NOOK_HOME='%s' luajit -e \"package.path='%s/plugins/gzreader.koplugin/?.lua;%s/?.lua;'..package.path; "
        .. "package.cpath='%s/?.so;%s/libs/?.so;'..package.cpath; "
        .. "if not pcall(require,'libs/libkoreader-lfs') then package.preload['libs/libkoreader-lfs']=function() return require('lfs') end end; "
        .. "local P=require('gzreader_places'); io.write(tostring(P.root('%s')), ' ', tostring(P.root('%s')))\" 2>/dev/null",
        card, REPO, KO, KO, KO, A, WORK .. "/not-moved")
    local h2 = io.popen(cmd2)
    local out2 = h2 and h2:read("*a") or ""
    if h2 then h2:close() end
    check(out2 == L .. " nil", "…then GZreader's places are GZreader/ on the card (not before the move): " .. out2)
    write(WORK .. "/copy-from.bin", string.rep("x", 200000))
    check(M.copyFile(WORK .. "/copy-from.bin", WORK .. "/copy-to.bin") and read(WORK .. "/copy-to.bin") == string.rep("x", 200000)
        and not exists(WORK .. "/copy-to.bin.gzmove"), "a file copied in pieces, whole (another disk)")
    package.loaded["gzreader_places"] = nil
end

do -- moved by a beta that left the reading history behind (1.34.0-beta.2bcfc79): put right once, at the next start
    local home = WORK .. "/history-fix"
    os.execute("rm -rf '" .. home .. "'")
    local R = home .. "/GZreader"
    local A = R .. "/app"
    write(A .. "/settings/settings.reader.lua", "return {}\n")
    write(R .. "/books/Old One.epub", "EPUB")
    write(R .. "/books/Read Again.epub", "EPUB")
    write(A .. "/history.lua", 'return {\n'
        .. '    [1] = { ["file"] = "' .. R .. '/books/Read Again.epub", ["time"] = 1795100000 },\n'
        .. '    [2] = { ["file"] = "' .. R .. '/Read Again.epub", ["time"] = 1795000000 },\n'
        .. '    [3] = { ["file"] = "' .. R .. '/Old One.epub", ["time"] = 1794000000 },\n'
        .. '    [4] = { ["file"] = "/mnt/elsewhere/Other.epub", ["time"] = 1793000000 },\n}\n')
    -- (and KUAL's entry as that beta wrote it: through bin/start.sh, which a Kindle 3 couldn't start GZreader from)
    write(home .. "/extensions/gzreader/menu.json", '{"items":[{"name":"GZreader","items":[{"action":"/mnt/us/extensions/gzreader/bin/start.sh"}]}]}')
    write(home .. "/extensions/gzreader/config.xml", "<extension/>")
    os.execute("mkdir -p '" .. A .. "/plugins/gzreader.koplugin' && cp -r '" .. REPO .. "/plugins/gzreader.koplugin/launchers' '"
        .. A .. "/plugins/gzreader.koplugin/'")
    local cmd = string.format("cd '%s' && GZ_MOVE_HOME='%s' luajit -e \"package.path='%s/frontend/?.lua;%s/?.lua;'..package.path; "
        .. "package.cpath='%s/?.so;%s/libs/?.so;'..package.cpath; "
        .. "if not pcall(require,'libs/libkoreader-lfs') then package.preload['libs/libkoreader-lfs']=function() return require('lfs') end end; "
        .. "io.write(tostring(dofile('%s/plugins/gzreader.koplugin/gzreader_migrate.lua').early()))\" 2>&1",
        A, home, KO, KO, KO, KO, REPO)
    local h = io.popen(cmd)
    local out = h and h:read("*a") or ""
    if h then h:close() end
    local hist = read(A .. "/history.lua") or ""
    local again = select(2, hist:gsub("Read Again%.epub", ""))
    check(out:find("nil", 1, true) ~= nil and hist:find('"' .. R .. '/books/Old One.epub"', 1, true) ~= nil
        and not hist:find('"' .. R .. '/Old One.epub"', 1, true) and again == 1 and hist:find("/mnt/elsewhere/Other.epub", 1, true) ~= nil
        and exists(A .. "/" .. M.HISTORY_FIXED),
        "moved by a beta that missed the reading history: its books' places put right at the next start, a book read again since kept once (" .. out:gsub("\n", " ") .. ")")
    check(M.kualReady(home) and not (read(home .. "/extensions/gzreader/menu.json") or ""):find("start.sh", 1, true),
        "…and KUAL's entry written again, starting GZreader/app/koreader.sh itself (not through bin/start.sh)")
    write(A .. "/history.lua", 'return {\n    [1] = { ["file"] = "' .. R .. '/Later.epub", ["time"] = 1 },\n}\n')
    h = io.popen(cmd); if h then h:read("*a"); h:close() end
    check((read(A .. "/history.lua") or ""):find(R .. "/Later.epub", 1, true) ~= nil, "…once only (a marker in its settings)")
end

print(string.format("move into the GZreader folder: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
