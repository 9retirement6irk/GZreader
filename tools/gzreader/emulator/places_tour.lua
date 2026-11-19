-- GZreader in a folder of its own (gzreader_places.lua, gzreader_migrate.lua):
--   GZ_PLACES=new:   installed as GZreader/app: books, music, audiobooks and
--                    notes beside it in the GZreader folder;
--   GZ_PLACES=moved: installed as before 1.35, in KOReader's place (koreader/),
--                    moved at this start (reader.lua, before anything opened a
--                    file): the books, their saved positions and reading
--                    history, music, notes, and the program itself, which went on
--                    running from its new folder.
--   APP=$(places-drive.sh <tree> <drive> [kindle|kobo])
--   GZ_EMU_KEEP=1 GZ_MOVE_HOME=<drive> GZ_MOVE_DEVICE=kindle|kobo GZ_PLACES=moved GZ_EMU_TREE=$APP run.sh places_tour.lua <out>
--   GZ_PLACES=new GZ_EMU_TREE=<drive>/GZreader/app run.sh places_tour.lua <out>
-- Checks go to <out>/places-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local KIND = os.getenv("GZ_PLACES") or "new"
local lfs = require("libs/libkoreader-lfs")
local function exists(p) return lfs.attributes(p, "mode") ~= nil end

add({ fn = function(_E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
end, after = 4 })
add({ shot = "1-home", after = 0.5 })
add({ fn = function(E)
    local P = require("gzreader_places")
    local app = P.app()
    local root = P.root()
    check(P.isNew() and root and app == root .. "/app", "GZreader runs from GZreader/app (" .. tostring(app) .. ")")
    local p = plugin()
    local books = root and (root .. "/books")
    check(p:libraryDir() == books and G_reader_settings:readSetting("home_dir") == books,
        "the books: GZreader/books, KOReader's home folder (" .. tostring(p:libraryDir()) .. ")")
    check(require("gzreader_music").root(p) == root .. "/music" and require("gzreader_audiobook").dir(p, 12) == root .. "/audiobooks/12",
        "music and audiobooks: GZreader/music, GZreader/audiobooks")
    check(require("gzreader_memos").cachePath() == root .. "/notes/notes.json" and require("gzreader_drawscreen").dir() == root .. "/notes/drawings"
        and require("gzreader_memos").filesDir() == root .. "/notes/files", "Notes: GZreader/notes (notes, drawings, attachments)")
    check(require("gzreader_usbsync").dir(p) == root .. "/.gzsync", "the sync page's folder: at the top of the GZreader folder")
    if KIND == "moved" then
        local home = root:match("^(.*)/[^/]+$")
        check(not exists(home .. "/koreader") and exists(root .. "/books/Moved Book.epub") and exists(root .. "/books/Moved Book.sdr")
            and exists(root .. "/music/album-1/01.mp3") and exists(root .. "/notes/drawings/waiting.png"),
            "moved at this start: koreader/ gone; the book, its .sdr, music, a drawing waiting")
        local hf = io.open(app .. "/settings/history.lua")
        local hist = hf and hf:read("*a") or ""
        if hf then hf:close() end
        check(hist:find('"' .. root .. '/books/Moved Book.epub"', 1, true) ~= nil and not hist:find(root .. '/Moved Book.epub', 1, true),
            "reading history: the book's new place")
        local DocSettings = require("docsettings")
        local ds = DocSettings:open(root .. "/books/Moved Book.epub")
        check(ds:readSetting("last_xpointer") == "/body/DocFragment[3]" and ds:readSetting("doc_path") == root .. "/books/Moved Book.epub",
            "its saved reading position came with it")
        E.say("waiting for the moved note")
    end
end, after = 4 })
add({ shot = "2-after", after = 0.3 })
add({ fn = function(E)
    if KIND == "moved" then
        local said
        for _i, w in ipairs(UIM()._window_stack) do
            if type(w.widget.text) == "string" and w.widget.text:find("folder of its own", 1, true) then said = w.widget.text end
        end
        check(said ~= nil and said:find("beside KOReader", 1, true) and said:find("koreader folder is free for KOReader", 1, true),
            "said once on the screen: GZreader has a folder of its own, beside KOReader")
    end
    local f = io.open(E.out .. "/places-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
