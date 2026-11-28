-- GZreader in a folder of its own (gzreader_places.lua): installed as
-- GZreader/app, its books, music, audiobooks and notes beside it in the
-- GZreader folder; on a Kobo, Nickel's library told to leave those alone.
--   APP=$(places-drive.sh <tree> <drive> [kindle|kobo])
--   GZ_EMU_KEEP=1 GZ_EMU_TREE=$APP run.sh places_tour.lua <out>
-- Checks go to <out>/places-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end

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
    local okd, Device = pcall(require, "device")
    if okd and Device.isKobo and Device:isKobo() then
        local f = io.open(root:match("^(.*)/[^/]+$") .. "/.kobo/Kobo/Kobo eReader.conf")
        local conf = f and f:read("*a") or ""
        if f then f:close() end
        check(conf:find("GZreader/(app|notes|music|audiobooks)", 1, true) ~= nil and conf:find("Foo=1", 1, true) ~= nil,
            "a Kobo: its own library leaves GZreader's folders alone (ExcludeSyncFolders), its other settings kept")
    end
end, after = 4 })
add({ shot = "2-after", after = 0.3 })
add({ fn = function(E)
    local f = io.open(E.out .. "/places-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
