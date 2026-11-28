-- Magazine issues among the books: on the Downloads shelves and Home's shelf
-- an issue stands on its side, a thin spine a bit taller than the books, the
-- magazine's name and the issue along it; picked, it turns to show its cover
-- as a book does. A keyboard model (the tabs by Alt + Q / W).
--   GZ_EMU_MAGS=<a folder of EPUBs: books, and issues named "<magazine> - <issue>">
--   GZ_EMU_MODEL=k3 GZ_EMU_TREE=<tree>/koreader run.sh magazine_shelf.lua <out>
-- Checks go to <out>/magazine-shelf-checks.txt.
local s = { start = 14, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function FM() return require("apps/filemanager/filemanager").instance end
local ISSUES = { "Field and Fern - December 2026", "Circuit - November 2026", "Circuit - October 2026", "The Long Read Winter 2026" }
local st = {}

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    local p = FM().gzreader
    local dir = p:libraryDir()
    st.dir = dir
    os.execute(string.format("cp '%s'/*.epub '%s/'", os.getenv("GZ_EMU_MAGS") or "/root/work/magbooks", dir))
    -- signed in to a book server whose library 7 is the magazine library; the issues downloaded from it
    p.store.server, p.store.username = "https://books.example.com", "reader"
    require("gzreader_magazines").set(p, { id = 7, name = "Magazines" })
    p.store.downloads = p.store.downloads or {}
    for i, name in ipairs(ISSUES) do
        p.store.downloads["90" .. i] = { path = dir .. "/" .. name .. ".epub", title = name, magazine = "7" }
    end
    -- Home's shelf: the recent books, issues among them
    local RH = require("readhistory")
    local t = os.time()
    for i, name in ipairs({ "Emma", "Circuit - November 2026", "Persuasion", "Field and Fern - December 2026", "Treasure Island" }) do
        RH:addItem(dir .. "/" .. name .. ".epub", t - 100 * i)
    end
    pcall(function() require("common/gz_view").set("bookshelf") end)
end, after = 3 })
add({ combo = { "Alt", "W" }, after = 15 }) -- the Downloads tab
add({ shot = "1-downloads" })
add({ fn = function(E)
    local fc = FM().file_chooser
    local mags, books, mag_h, book_h, mag_w = 0, 0, 0, 0, 1e9
    for _i, row in ipairs(fc.item_group or {}) do
        for _j, it in ipairs(row.items or {}) do
            if it.book and it.book.gz_magazine then
                mags = mags + 1; mag_h = math.max(mag_h, it.h); mag_w = math.min(mag_w, it.w)
                if it.book.title:find("Fern", 1, true) then st.fern = it end
            elseif it.kind == "book" then
                books = books + 1; book_h = math.max(book_h, it.h)
            end
        end
    end
    E.say("downloads: magazines", mags, "books", books, "mag h", mag_h, "tallest book", book_h, "mag w", mag_w)
    check(mags == #ISSUES and books == 4, "Downloads: the four issues and four books on the shelves (" .. mags .. ", " .. books .. ")")
    check(mag_h > book_h, "the issues are taller than the tallest book (" .. mag_h .. " > " .. book_h .. ")")
    local Sh = require("modules/filebrowser/patches/home/widgets/shelf")
    check(mag_w == require("device").screen:scaleBySize(Sh.MAG_SPINE) and mag_w < require("device").screen:scaleBySize(Sh.MIN_SPINE),
        "…and thinner than any book")
    if st.fern then require("gzreader_shelfview").pick(fc, st.fern.idx) end
end, after = 4 })
add({ shot = "2-downloads-picked" })
add({ fn = function()
    local fc = FM().file_chooser
    check(st.fern and fc._gz_picked == st.fern.idx, "picked, an issue turns to show its cover (as a book does)")
end, after = 1 })
add({ combo = { "Alt", "Q" }, after = 12 }) -- Home
add({ shot = "3-home" })
add({ fn = function(E)
    local Sh = require("modules/filebrowser/patches/home/widgets/shelf")
    local found = 0
    for _i, name in ipairs(ISSUES) do
        if Sh.isMagazine({ path = st.dir .. "/" .. name .. ".epub" }) then found = found + 1 end
    end
    check(found == #ISSUES and not Sh.isMagazine({ path = st.dir .. "/Emma.epub" }),
        "Home's shelf asks GZreader: the issues are magazines, the books aren't")
    local f = io.open(E.out .. "/magazine-shelf-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    E.say(table.concat(lines, "\n"))
end, after = 1 })
return s
