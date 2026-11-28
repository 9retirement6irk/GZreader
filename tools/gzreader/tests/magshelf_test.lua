-- Magazine issues on the shelves (gzreader_magazines.lua's on-the-Kindle part,
-- and where the Downloads shelves and Home's shelf ask it): a download of the
-- magazine library stands on its side, a thin spine taller than the books.
--   luajit magshelf_test.lua <gzreader.koplugin> <zenos.koplugin>
local PLUGIN = arg[1] or "../../../plugins/gzreader.koplugin"
local ZENOS = arg[2] or "../../../plugins/zenos.koplugin"
package.path = PLUGIN .. "/?.lua;" .. package.path
package.preload["gettext"] = function() return function(t) return t end end
-- (no library index on disk: its ids are given here)
local index_ids = {}
package.preload["gzreader_index"] = function()
    return { load = function() return { magazines = { ids = index_ids } } end }
end
local Mag = require("gzreader_magazines")
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end

local store = { server = "https://books.example.com", username = "reader", downloads = {} }
local plugin = { store = store, save = function() end }
check(next(Mag.downloadedPaths(plugin, 1)) == nil, "no magazine library: no download is a magazine")
Mag.set(plugin, { id = 7, name = "Magazines" })
check(Mag.mark(plugin, { id = 1, libraryId = 7 }) == "7" and Mag.mark(plugin, { id = 2, libraryId = 3 }) == nil,
    "a download records the magazine library's id when the book is one of its issues (Grimmory's libraryId)")
Mag.stand_ids = { ["5"] = true }
check(Mag.mark(plugin, { id = 5 }) == "7", "…or its id is one of the library's (BookOrbit: the stand's issues, the index)")
Mag.forget()
index_ids = { 9 }
store.downloads = {
    ["1"] = { path = "/b/Wired - November 2026.epub", magazine = "7" },
    ["2"] = { path = "/b/Emma.epub" },
    ["9"] = { path = "/b/Old issue.pdf" },             -- (downloaded before issues were marked: the index says)
    ["4"] = { path = "/b/Other library.epub", magazine = "3" }, -- (marked for a library chosen before)
}
local paths = Mag.downloadedPaths(plugin, 100)
check(paths["/b/Wired - November 2026.epub"] and paths["/b/Old issue.pdf"] and not paths["/b/Emma.epub"]
    and not paths["/b/Other library.epub"],
    "the issues on the Kindle: marked for the library chosen now, or the library's by id; not the books")
store.downloads["3"] = { path = "/b/New.epub", magazine = "7" }
check(not Mag.downloadedPaths(plugin, 101)["/b/New.epub"] and Mag.downloadedPaths(plugin, 100 + Mag.PATHS_FOR)["/b/New.epub"],
    "kept for a moment (a shelf page asks for every spine), then looked at again")
store.downloads = { ["3"] = { path = "/b/New.epub", magazine = "7" } }
check(Mag.downloadedPaths(plugin, 102)["/b/New.epub"] and not Mag.downloadedPaths(plugin, 102)["/b/Emma.epub"],
    "…at once when the downloads list itself is replaced")
Mag.set(plugin, nil)
check(not Mag.isDownloaded(plugin, "/b/New.epub"), "no magazine library chosen any more: back to a book")
check(not Mag.isDownloaded(nil, "/b/New.epub") and not Mag.isDownloaded(plugin, nil), "no plugin, no path: not one")

local function words(t) local a, b = Mag.spineWords(t); return a .. "|" .. b end
check(words("Wired - November 2026") == "Wired|November 2026" and words("The Atlantic: December 2026") == "The Atlantic|December 2026"
    and words("Granta") == "Granta|" and words("") == "|",
    "a spine's words: the magazine in bold, then the issue")

-- where the shelves ask
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end
local sv = read(PLUGIN .. "/gzreader_shelfview.lua")
local sh = read(ZENOS .. "/modules/filebrowser/patches/home/widgets/shelf.lua")
local main = read(PLUGIN .. "/main.lua")
check(sv:find("if is_book and not case and View.isMagazine(entry.path) then", 1, true)
    and sv:find("look = Sh.magazineLook(book, area_h)", 1, true)
    and sv:find("if entry.is_file and p and View.isMagazine(p) then return S(Shelf().MAG_SPINE) end", 1, true),
    "Downloads: an issue's spine (and its room when a page is filled) is the magazine's")
check(sh:find("elseif M.isMagazine(book) then", 1, true) and sh:find('rawget(_G, "__GZ_IS_MAGAZINE")', 1, true)
    and main:find('rawset(_G, "__GZ_IS_MAGAZINE"', 1, true),
    "Home's shelf: the same, through GZreader's hook")
check(sh:find("h = math.max(S(60), area_h + S(M.MAG_OVER))", 1, true) and sh:find("M.MAG_SPINE = 26", 1, true)
    and sh:find("local tall = 0.84 + ((math.floor(h / 7) % 17) / 100)", 1, true),
    "taller than any book (a book is 84-100% of the room; an issue the room and a little more), thinner than any (44-58)")
check(sh:find("if book.gz_magazine == true then\n        bb = draw_magazine_side(book, w, h, shade)", 1, true)
    and sh:find('book.gz_magazine == true and "mag" or ""', 1, true),
    "drawn as an issue's spine, kept apart from a book's of the same size")
check(main:find('magazine = require("gzreader_magazines").mark(self, book),', 1, true), "a download is marked when it's made")

print(("magazines on the shelves: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
