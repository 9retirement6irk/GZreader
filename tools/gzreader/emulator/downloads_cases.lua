-- Downloads → Audiobooks and Music in the Bookshelf view: every cassette and
-- CD faces out with its cover, its name on a plate on the shelf under it.
--   GZ_EMU_TREE=<tree>/koreader ./run.sh downloads_cases.lua <out>
-- GZ_EMU_COVERS: a folder of c1.jpg … c9.jpg (any pictures; without them the
-- stand-ins have no cover and ZenOS draws its own).
local COVERS = os.getenv("GZ_EMU_COVERS") or "/tmp/gzcovers"
local BOOKS = {
    { "A Walk in the Woods", "Sam Example" }, { "The Long Way Round", "Ann Sample" },
    { "Rivers", "J. Doe" }, { "An Unusually Long Audiobook Title That Will Not Fit", "R. Writer" },
    { "Night Train", "C. Author" }, { "Small Hours", "M. Teller" }, { "Gardens", "P. Green" },
}
local ALBUMS = { { "Blue Tones", "The Tones" }, { "Morning", "Example Band" }, { "Live at the Hall", "Quartet" },
    { "Greatest Hits of the Imaginary Decade", "Various" }, { "Quiet", "Duo" } }

local function copy(from, to)
    local fi = io.open(from, "rb")
    if not fi then return end
    local data = fi:read("*a"); fi:close()
    local fo = io.open(to, "wb"); fo:write(data); fo:close()
end

local s = { start = 12, { key = "Back", after = 4 } }
s[#s + 1] = { fn = function()
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local lib = plugin:libraryDir()
    local Json = require("gzreader_json")
    plugin.store.audiobooks = plugin.store.audiobooks or {}
    for i, b in ipairs(BOOKS) do
        local id = 100 + i
        local dir = lib .. "/.audiobooks/" .. id
        os.execute("mkdir -p '" .. dir .. "'")
        local f = io.open(dir .. "/audiobook.json", "wb")
        f:write(Json.encode({ id = id, title = b[1], durationMs = 3600000 * i })); f:close()
        copy(COVERS .. "/c" .. i .. ".jpg", dir .. "/cover.jpg")
        plugin.store.audiobooks[id] = { title = b[1], author = b[2] }
        require("gzreader_abfolder").writeStub(plugin, id)
    end
    for i, a in ipairs(ALBUMS) do
        local dir = lib .. "/.music/album-" .. i
        os.execute("mkdir -p '" .. dir .. "'")
        copy(COVERS .. "/c" .. (10 - i) .. ".jpg", dir .. "/cover.jpg")
        require("gzreader_musicfolder").writeStub(plugin, { dir = dir, title = a[1], artist = a[2], kind = "album",
            tracks = { {}, {}, {} } })
    end
    print("[emu] stand-ins written")
end, after = 2 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 8 } -- the Downloads tab
s[#s + 1] = { shot = "downloads" }
local function go(sub)
    return { fn = function()
        local fm = require("apps/filemanager/filemanager").instance
        fm.file_chooser:changeToPath(fm.gzreader:libraryDir() .. "/" .. sub)
    end, after = 12 }
end
s[#s + 1] = go("Audiobooks")
s[#s + 1] = { fn = function()
    local View = require("gzreader_shelfview")
    local fc = require("apps/filemanager/filemanager").instance.file_chooser
    local shown, hidden = 0, 0
    for _i, row in ipairs(fc.item_group or {}) do
        for _j, it in ipairs(row.items or {}) do
            if it.hidden then hidden = hidden + 1 else shown = shown + 1 end
        end
    end
    print(string.format("[emu] Audiobooks: bookshelf %s, no_turn %s, per page %s, shown %d, hidden %d",
        tostring(View.applies(fc)), tostring(View.no_turn), tostring(fc.perpage), shown, hidden))
end, after = 1 }
s[#s + 1] = { shot = "audiobooks" }
s[#s + 1] = { key = "Down", after = 3 } -- the 5-way onto a tape: a frame
s[#s + 1] = { shot = "audiobooks-focus" }
s[#s + 1] = go("Music")
s[#s + 1] = { shot = "music" }
return s
