-- The shelves' look (ZenOS's home/widgets/shelf.lua, GZreader's bookshelf):
-- page-block tops, the cloth's light, the board, the books' shadow on the
-- wall, drawn after AndyHazz's Bookshelf plugin. Painted into real
-- Blitbuffers and read back.
--   luajit shelf_look_test.lua <repo> <koreader dir>
local REPO, KOROOT = arg[1], arg[2]
package.path = REPO .. "/frontend/?.lua;" .. KOROOT .. "/?.lua;" .. KOROOT .. "/frontend/?.lua;" .. package.path
local function preload(name, val) package.preload[name] = function() return val end end
preload("libs/libkoreader-lfs", { attributes = function() end, currentdir = function() return "." end })
preload("logger", { dbg = function() end, info = function() end, warn = function() end, err = print })
preload("device", { screen = {} })
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    print((ok and "  ok   " or "  FAIL ") .. what)
end

print("The shelves' look: page-block tops, the wall's shadow, the board (after Bookshelf's)")
do
    local Device = require("device")
    local was_screen = Device.screen
    Device.screen = { getWidth = function() return 600 end, getHeight = function() return 800 end, scaleBySize = function(_s, v) return v end }
    local SHELF = "modules/filebrowser/patches/home/widgets/shelf"
    local names = { SHELF, "ui/font", "ui/geometry", "ui/gesturerange", "ui/widget/container/inputcontainer",
        "ui/widget/textwidget", "ui/widget/container/widgetcontainer", "modules/filebrowser/patches/home/widgets/cover_common", "common/cover_utils" }
    local saved = {}
    for _i, m in ipairs(names) do saved[m] = package.loaded[m] end
    local function class() return { extend = function(_s, o) return o or {} end, new = function(_s, o) return o or {} end } end
    local okb, BB = pcall(require, "ffi/blitbuffer")
    for _i, m in ipairs({ "ui/font", "ui/geometry", "ui/gesturerange", "ui/widget/container/inputcontainer", "ui/widget/textwidget",
        "ui/widget/container/widgetcontainer", "modules/filebrowser/patches/home/widgets/cover_common", "common/cover_utils" }) do
        package.loaded[m] = class()
    end
    package.loaded[SHELF] = nil
    local oks, Sh = pcall(dofile, REPO .. "/plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua")
    check(okb and oks, "shelf.lua loads with the real Blitbuffer " .. tostring(not oks and Sh or ""))
    if okb and oks then
        check(Sh.topEdge(50) == 0 and Sh.topEdge(60) == 8 and Sh.topEdge(90) == 12 and Sh.topEdge(150) == 13 and Sh.topEdge(400) == 13,
            "a book's top: its cover's width seen from 12 degrees above, none on a short book, 13 px at most (" .. Sh.topEdge(60) .. ", " .. Sh.topEdge(90) .. ", " .. Sh.topEdge(150) .. ")")
        check(Sh.boardShade(0.2) > 0.2 and Sh.boardShade(0.2) < 1 and Sh.boardShade(0.9) <= 1 and Sh.boardShade(0.9) > 0.9, "the boards: darker than the cloth, never past black")
        -- lettering: 1 px a letter per type size (bold or not), a line as tall as its size
        local m = { width = function(str, size) return #str * size / 2 end, lineH = function(size) return size end,
            tuck = function() return 0 end, gap = 10, max = 20 }
        local function show(f) return f.size .. ":" .. table.concat(f.lines, "/") .. ":" .. tostring(f.author) end
        local f = Sh.fitSpine("Emma", "Jane Austen", 200, 50, m)
        check(f.size == 20 and #f.lines == 1 and f.author == "after" and f.a_size == 17, "a short title: big, its author after it on the same line (" .. show(f) .. ")")
        f = Sh.fitSpine("Frankenstein", "Mary Shelley", 130, 50, m)
        check(f.size == 20 and #f.lines == 1 and f.author == "line", "no room after it: the author on a line of its own (" .. show(f) .. ")")
        f = Sh.fitSpine("Alice's Adventures in Wonderland", "Lewis Carroll", 130, 50, m)
        check(not f.cut and #f.lines == 2 and f.lines[1] == "Alice's Adventures" and f.lines[2] == "in Wonderland" and f.size <= 14,
            "a long title: whole, in two lines of about the same length, in smaller type (" .. show(f) .. ")")
        f = Sh.fitSpine("Kidnapped", "R. L. Stevenson", 110, 40, m)
        check(f.lines[1] == "Kidnapped" and f.author == "line" and f.size == 17, "a long name: the title a little smaller so the author has its line (" .. show(f) .. ")")
        f = Sh.fitSpine("Hamlet", "", 100, 40, m)
        check(f.size == 20 and f.author == nil, "no author: the title alone")
        f = Sh.fitSpine("The Innocence of Father Brown and Other Stories of Detection", "G. K. Chesterton", 90, 30, m)
        check(f.cut and f.size == Sh.TITLE_MIN and #f.lines == 2 and f.author == nil, "too long for the spine even in the smallest type: as many lines as fit, the last cut (" .. show(f) .. ")")
        check(Sh.wrapTitle("Supercalifragilistic", 50, function(str) return #str * 6 end, 3) == nil
            and #Sh.wrapTitle("a b c d e f", 12, function(str) return #str * 6 end, 6) == 6
            and Sh.wrapTitle("a b c d e f", 12, function(str) return #str * 6 end, 5) == nil, "a word too long for the run, or more lines than fit: not wrapped")
        local function lum(bb, x, y) return bb:getPixel(x, y):getColor8().a end
        -- the page block between its boards
        local bb = BB.new(60, 40, BB.TYPE_BB8)
        bb:fill(BB.COLOR_WHITE)
        Sh.paintTop(bb, 10, 5, 40, 12, 0.5)
        local board, paper = lum(bb, 10, 10), lum(bb, 30, 16)
        local lines = 0
        for x = 14, 45 do if lum(bb, x, 10) < 200 and lum(bb, x, 10) > board then lines = lines + 1 end end
        check(board < 100 and lum(bb, 49, 10) == board and lum(bb, 12, 10) == board, "the top: a board up each side, darker than the cloth (" .. board .. ")")
        check(lines >= 5 and lines <= 26, "…page lines on paper between them (" .. lines .. " of 32 columns)")
        check(lum(bb, 30, 5) < 200 and lum(bb, 30, 5) > board and lum(bb, 30, 4) == 255 and lum(bb, 30, 17) == 255,
            "…the row above the paper is the wall's shadow; nothing outside its box")
        check(paper ~= nil and lum(bb, 13, 16) == board and lum(bb, 46, 16) == board, "…the boards turn in where they meet the spine")
        -- the cloth's light
        local cl = BB.new(40, 10, BB.TYPE_BB8)
        cl:fill(BB.gray(0.5))
        Sh.shadeRamp(cl, 0, 0, 40, 10)
        check(lum(cl, 0, 5) < lum(cl, 20, 5) and lum(cl, 20, 5) < lum(cl, 39, 5) and math.abs(lum(cl, 20, 5) - 128) <= 3,
            "a spine is a touch darker at its left edge than its right (" .. lum(cl, 0, 5) .. ", " .. lum(cl, 20, 5) .. ", " .. lum(cl, 39, 5) .. ")")
        -- the board: its top darkest at the back, a bright edge, the front, a shadow under it
        local wall = BB.new(200, 60, BB.TYPE_BB8)
        wall:fill(BB.COLOR_WHITE)
        Sh.paintBoard(wall, 0, 20, 200)
        local back, near = lum(wall, 100, 17), lum(wall, 100, 24)
        local front = lum(wall, 100, 28)
        check(back < near and near <= 255 and lum(wall, 100, 16) == 255, "the board's top starts " .. Sh.STAND .. " px behind the books' feet, darkest at the back (" .. back .. " to " .. near .. ")")
        check(lum(wall, 2, 17) == 255 and lum(wall, 2, 28) == front, "…narrower at the back than its front")
        check(lum(wall, 100, 25) > front and lum(wall, 100, 20 + Sh.BOARD_H - 1) < front, "…a bright line along its edge, a dark one under its front")
        check(lum(wall, 100, 20 + Sh.BOARD_H) < 255 and lum(wall, 100, 20 + Sh.BOARD_H + Sh.UNDER_H + 1) == 255, "…and its shadow on the wall below")
        -- the books' shadow on the wall
        local spans = { { x = 40, w = 20, h = 60 }, { x = 60, w = 20, h = 40 } }
        check(Sh.recessHorizon(spans, 45, 14) == 60 and Sh.recessHorizon(spans, 65, 14) == 54 and Sh.recessHorizon(spans, 85, 14) == 34
            and Sh.recessHorizon(spans, 30, 14) == 50 and Sh.recessHorizon(spans, 10, 14) == 0,
            "the shadow leans over what's beside a book and falls away at 45 degrees, " .. Sh.RECESS_SIDE .. " px at most")
        local room = BB.new(140, 100, BB.TYPE_BB8)
        room:fill(BB.COLOR_WHITE)
        Sh.paintDepth(room, 90, spans)
        check(lum(room, 50, 90 - Sh.STAND - 61) < 255 and lum(room, 50, 90 - Sh.STAND - 60 - Sh.RECESS_HALO - 2) == 255, "a little of it shows above a book's top, and no further")
        check(lum(room, 84, 80) < 255 and lum(room, 84, 80) < lum(room, 92, 80) + 1 and lum(room, 110, 80) == 255 and lum(room, 36, 80) < 255,
            "…and past both ends of the row, fading out")
        check(lum(room, 50, 90) < 255, "…and the books darken the board where they stand")
        local empty = BB.new(20, 20, BB.TYPE_BB8)
        empty:fill(BB.COLOR_WHITE)
        check(pcall(Sh.paintDepth, empty, 10, {}) and lum(empty, 5, 5) == 255, "an empty shelf has no shadow")
    end
    for _i, m in ipairs(names) do package.loaded[m] = saved[m] end
    Device.screen = was_screen
end

print("The shelves' theme and ornaments (gzreader_shelftheme.lua)")
do
    local settings = {}
    G_reader_settings = { -- luacheck: ignore
        readSetting = function(_s, k) return settings[k] end,
        saveSetting = function(_s, k, v) settings[k] = v end,
    }
    local Device = require("device")
    Device.screen = { scaleBySize = function(_s, v) return v end }
    local dir_files
    package.loaded["libs/libkoreader-lfs"] = {
        attributes = function(path) return dir_files and path:match("/ornaments$") and "directory" or nil end,
        dir = function() local i = 0; return function() i = i + 1; return dir_files[i] end end,
        mkdir = function() end,
    }
    package.preload["gettext"] = function() return function(str) return str end end
    local WORK = os.getenv("TMPDIR") or "/tmp"
    local udir = WORK .. "/gz-orn-test"
    os.execute("rm -rf '" .. udir .. "' && mkdir -p '" .. udir .. "/gzreader/ornaments'")
    package.loaded["datastorage"] = { getSettingsDir = function() return udir end }
    local ok, Theme = pcall(dofile, REPO .. "/plugins/gzreader.koplugin/gzreader_shelftheme.lua")
    check(ok, "gzreader_shelftheme loads " .. tostring(not ok and Theme or ""))
    if ok then
        local real_changed = Theme.changed
        Theme.changed = function() Theme.planks, Theme.images, Theme.found = {}, {}, nil end
        check(Theme.get() == "oak" and Theme.ornaments() == "room", "to begin with: the Oak plank, ornaments where there's room")
        check(Theme.set("walnut") and Theme.get() == "walnut" and not Theme.set("marble") and Theme.get() == "walnut", "a theme is one of Plain, Oak, Walnut")
        settings[Theme.SETTING] = "nonsense"
        check(Theme.get() == "oak", "a theme this version doesn't know: Oak")
        check(Theme.setOrnaments("always") and Theme.ornaments() == "always" and not Theme.setOrnaments("lots"), "ornaments: off, where there's room, or on every page")
        Theme.set("plain")
        check(Theme.plank(600, 8, 9) == nil, "Plain: no picture for the plank (the board is drawn in greys)")
        -- the two that come with it, measured from their files
        Theme.today = { 6, 10 }
        local list = Theme.list()
        check(#list == 19 and list[1].name == "ornament-photo-potted-plant-01.png" and list[1].aspect > 0.3 and list[1].aspect < 0.6 and list[19].name == "ornament-photo-christmas-tree.png",
            "19 ornaments come with GZreader (their shape from the picture's header)")
        local photos = 0
        for _i, e in ipairs(list) do
            if e.photo then
                photos = photos + 1
                local head = io.open(e.path, "rb")
                local magic = head and head:read(4) or ""
                if head then head:close() end
                if magic ~= "\137PNG" then photos = -100 end
            end
        end
        local credits = io.open(REPO .. "/plugins/gzreader.koplugin/icons/shelf/CREDITS.md", "r"):read("*a")
        local shipped = 0
        local ls = io.popen("ls '" .. REPO .. "/plugins/gzreader.koplugin/icons/shelf'")
        for name in ls:lines() do if name:match("^ornament%-") then shipped = shipped + (name:match("^ornament%-photo%-.*%.png$") and 1 or -100) end end
        ls:close()
        check(photos == 19 and shipped == 19 and list[17].label == "Tabby cat" and not list[17].season and list[18].label == "Pumpkin" and list[18].season,
            "all are photorealistic pictures (no drawn ones, none left in the folder): 17 standing all year, and the pumpkin and the Christmas tree")
        check(credits:find("ornament-photo-christmas-tree", 1, true) and credits:find("supplied by the owner", 1, true),
            "…the three the owner supplied are listed as his, their source not recorded")
        check(credits:find("Poly Haven", 1, true) and credits:find("CC0", 1, true) and credits:find("concrete_cat_statue", 1, true) and credits:find("dutch_ship_medium", 1, true),
            "…credited: Poly Haven's objects, CC0, by name")
        -- seasons
        local tree
        for _i, e in ipairs(list) do if e.name == "ornament-photo-christmas-tree.png" then tree = e end end
        check(Theme.inSeason({ 11, 20, 1, 6 }, 12, 25) and Theme.inSeason({ 11, 20, 1, 6 }, 1, 6) and Theme.inSeason({ 11, 20, 1, 6 }, 11, 20)
            and not Theme.inSeason({ 11, 20, 1, 6 }, 1, 7) and not Theme.inSeason({ 11, 20, 1, 6 }, 11, 19)
            and Theme.inSeason({ 3, 1, 5, 31 }, 4, 15) and not Theme.inSeason({ 3, 1, 5, 31 }, 6, 1) and Theme.inSeason(nil, 6, 1),
            "a season runs from a day to a day, over New Year too")
        local function names(t) local o = {}; for i, e in ipairs(t) do o[i] = e.label end; return table.concat(o, ", ") end
        check(#(Theme.standing()) == 17 and (Theme.standing())[1].photo and (Theme.standing())[17].label == "Tabby cat",
            "in June: the 17 that stand all year")
        Theme.today = { 12, 10 }
        local on, seasonal = Theme.standing()
        check(#on == 18 and names(seasonal) == "Christmas tree", "in December: the Christmas tree joins them")
        local festive = 0
        for i = 1, 300 do if Theme.pick("downloads:" .. i .. ":2").season then festive = festive + 1 end end
        check(festive > 180 and festive < 270, "…and takes about two places of three (" .. festive .. " of 300)")
        Theme.today = { 10, 31 }
        check(names(select(2, Theme.standing())) == "Pumpkin", "in October: the pumpkin")
        Theme.today = { 4, 2 }
        check(#select(2, Theme.standing()) == 0 and #(Theme.standing()) == 17, "in April: no seasonal one")
        Theme.today = { 6, 10 }
        Theme.setOn(tree, true)
        check(Theme.isOn(tree) and #select(2, Theme.standing()) == 0 and #(Theme.standing()) == 18, "ticked by hand: the Christmas tree stands in June too, as one among the others")
        Theme.today = { 12, 10 }
        Theme.setOn(tree, false)
        check(not Theme.isOn(tree) and #select(2, Theme.standing()) == 0 and #(Theme.standing()) == 17, "unticked by hand: not even at Christmas")
        Theme.resetChosen()
        check(Theme.isOn(tree), "\"Seasonal ones in their season again\": back to its season")
        Theme.today = { 6, 10 }
        -- the reader's own: PNG and SVG files, by name, others left out
        local function write(name, data) local f = io.open(udir .. "/gzreader/ornaments/" .. name, "wb"); f:write(data); f:close() end
        write("globe.png", "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\200\0\0\0\100" .. string.rep("\0", 16))
        write("Vase.SVG", '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 80"></svg>')
        write("notes.txt", "x")
        write("broken.svg", "<svg></svg>")
        dir_files = { ".", "..", "notes.txt", "globe.png", "broken.svg", "Vase.SVG", ".hidden.png" }
        Theme.found = nil
        list = Theme.list()
        check(#list == 21 and list[20].name == "Vase.SVG" and list[20].aspect == 0.5 and list[20].label == "Vase" and list[21].name == "globe.png" and list[21].aspect == 2,
            "your own PNG and SVG files join them (their shape from the file); other files and broken ones don't (" .. #list .. ")")
        check(Theme.userDir(false) == udir .. "/gzreader/ornaments", "…from koreader/settings/gzreader/ornaments")
        -- which one stands where: the same every time
        local a, b = Theme.pick("downloads:1:3"), Theme.pick("downloads:1:3")
        local seen = {}
        for i = 1, 40 do seen[Theme.pick("downloads:" .. i .. ":1").name] = true end
        local kinds = 0
        for _k in pairs(seen) do kinds = kinds + 1 end
        check(a == b and kinds >= 12, "the same place has the same ornament every time; different places, different ones (" .. kinds .. " of 19)")
        -- sizes: 80% of the books' room, narrower when the room is, never under 2/3
        local plant = list[1]
        local w, h = Theme.size(plant, 150, 400)
        check(h == 120 and math.abs(w - 120 * plant.aspect) <= 1, "an ornament stands 80% as tall as the books' room (" .. tostring(w) .. " x " .. tostring(h) .. ")")
        local w2, h2 = Theme.size(plant, 150, 60)
        check(w2 == 40 and h2 and h2 < 120 and h2 >= 80, "less room: smaller, its shape kept (" .. tostring(w2) .. " x " .. tostring(h2) .. ")")
        check(Theme.size(plant, 150, 50) == nil and Theme.size(plant, 20, 400) == nil, "too little room, or a tiny shelf: none")
        check(Theme.reserve(150) == 120 + 20, "an ornament on every page: the bottom shelf keeps room for the widest (as wide as the usual height at most)")
        local vase
        for _i, e in ipairs(list) do if e.label == "Blue and white vase" then vase = e end end
        check(select(2, Theme.size(vase, 150, 400)) == 108 and select(2, Theme.size(tree, 150, 400)) == 142, "some stand shorter or taller than the rest: a vase 72% of the books' room, the tree 95%")
        -- an ornament stands on its lowest drawn row
        local pic = { getWidth = function() return 20 end, getHeight = function() return 30 end,
            getPixel = function(_s, x, y) return { alpha = (y <= 24 and x >= 8 and x <= 12) and 255 or 0 } end }
        check(Theme.emptyFoot(pic) == 5, "the empty rows under a picture are measured (Bookshelf's two leave a margin there): it stands on what's drawn")
        -- shading on 16 greys: dithered, not banded
        do
            local BBm = require("ffi/blitbuffer")
            local g = BBm.new(64, 16, BBm.TYPE_BB8A)
            for gx = 0, 63 do for gy = 0, 15 do g:setPixel(gx, gy, BBm.Color8A(104 + math.floor(gx / 4), gy < 12 and 255 or 0)) end end
            local before = g:getPixel(10, 14):getColor8A().a
            check(Theme.dither(g), "a shaded picture's greys are dithered")
            local levels, sum, off = {}, 0, 0
            for gx = 0, 63 do for gy = 0, 11 do
                local v = g:getPixel(gx, gy):getColor8A().a
                levels[v] = true
                sum = sum + v
                if v % 17 ~= 0 then off = off + 1 end
            end end
            local n = 0
            for _v in pairs(levels) do n = n + 1 end
            local mean = sum / (64 * 12)
            check(off == 0 and n == 2 and levels[102] and levels[119], "…to the screen's 16 greys: a slope from 104 to 119 becomes a mix of 102 and 119, no in-between")
            check(math.abs(mean - 111.5) < 2, "…its tone kept (" .. string.format("%.1f", mean) .. " for 111.5)")
            local row_a, row_b = 0, 0
            for gy = 0, 11 do if g:getPixel(2, gy):getColor8A().a == 119 then row_a = row_a + 1 end; if g:getPixel(60, gy):getColor8A().a == 119 then row_b = row_b + 1 end end
            check(row_b > row_a, "…the lighter end has more of the lighter grey (" .. row_a .. " then " .. row_b .. " of 12)")
            check(g:getPixel(10, 14):getColor8A().a == before and g:getPixel(10, 14):getColor8A().alpha == 0, "…what's transparent is left alone")
            g:free()
        end
        check(Theme.emptyFoot({ getWidth = function() return 20 end, getHeight = function() return 30 end, getPixel = function() return {} end }) == 0,
            "a picture without transparency stands on its edge")
        -- where, how many, which end
        local function sides(t) local o = {}; for r = 1, 4 do o[r] = t[r] and t[r]:sub(1, 1) or "-" end; return table.concat(o) end
        check(Theme.count() == 1 and Theme.side() == "right" and Theme.placeOn("home") and Theme.placeOn("downloads") and Theme.placeOn("catalog"),
            "to begin with: one on a page, at the right end, on Home, in Downloads and in the Catalog")
        check(sides(Theme.rowsFor("downloads", { 1, 2, 3 })) == "--r-", "one on a page: the lowest shelf with books")
        check(sides(Theme.rowsFor("downloads", { 1 })) == "r---" and sides(Theme.rowsFor("downloads", {})) == "----", "…a page with one shelf of books: that one; no books: none")
        Theme.setCount(2)
        check(sides(Theme.rowsFor("downloads", { 1, 2, 3 })) == "-rr-" and sides(Theme.rowsFor("downloads", { 1 })) == "r---", "up to two: the two lowest")
        Theme.setCount("all")
        check(Theme.count() == math.huge and sides(Theme.rowsFor("downloads", { 1, 2, 3, 4 })) == "rrrr", "one on every shelf")
        Theme.setSide("left")
        check(sides(Theme.rowsFor("home", { 1, 2 })) == "ll--", "at the left end")
        Theme.setSide("scattered")
        check(sides(Theme.rowsFor("downloads", { 1, 2, 3 })) == "rlr-" and sides(Theme.rowsFor("downloads", { 2, 3 })) == "-rl-",
            "scattered: the first on the right, the next on the left, then the right again")
        check(not Theme.setSide("middle") and not Theme.setCount(7) and not Theme.setCount(0) and Theme.side() == "scattered", "only the choices there are")
        Theme.setPlace("home", false)
        check(not Theme.placeOn("home") and Theme.placeOn("downloads") and sides(Theme.rowsFor("home", { 1 })) == "----" and sides(Theme.rowsFor("downloads", { 1 })) == "r---",
            "Home switched off: none there, Downloads keeps its own")
        Theme.setCount(2)
        check(Theme.keeps("downloads", 3, 3) and Theme.keeps("downloads", 2, 3) and not Theme.keeps("downloads", 1, 3) and not Theme.keeps("home", 1, 1),
            "an ornament on every page: the shelves that get one keep room for it (the two lowest of three; none on Home, switched off)")
        Theme.setPlace("home", true)
        Theme.setCount(1)
        Theme.setSide("right")
        Theme.setOrnaments("room")
        check(not Theme.keeps("downloads", 3, 3), "where there's room: nothing is kept for them")
        check(Theme.plan("x", 30, 150) == nil, "no room beside the books: no ornament planned")
        -- a page's ornaments differ from each other; in season about two of three are seasonal
        Theme.today = { 10, 31 } -- (one seasonal ornament: the pumpkin)
        local repeats, pumpkins, pages = 0, 0, 60
        for pg = 1, pages do
            local p1, p2, p3 = Theme.pick("downloads:" .. pg, 1), Theme.pick("downloads:" .. pg, 2), Theme.pick("downloads:" .. pg, 3)
            if p1 == p2 or p2 == p3 or p1 == p3 then repeats = repeats + 1 end
            for _i, e in ipairs({ p1, p2, p3 }) do if e.label == "Pumpkin" then pumpkins = pumpkins + 1 end end
            if Theme.pick("downloads:" .. pg, 2) ~= p2 then repeats = repeats + 100 end
        end
        check(repeats == 0, "three ornaments on a page are three different ones, the same each time (60 pages)")
        check(pumpkins == pages, "…in October one of the three is the pumpkin (" .. pumpkins .. " on " .. pages .. " pages)")
        Theme.today = { 12, 10 }
        local festive3 = 0
        for pg = 1, pages do for k = 1, 3 do if Theme.pick("downloads:" .. pg, k).season then festive3 = festive3 + 1 end end end
        check(festive3 == pages, "…in December one of the three is the Christmas tree (" .. festive3 .. " on " .. pages .. " pages)")
        Theme.today = { 6, 10 }
        Theme.setOrnaments("off")
        local BB = require("ffi/blitbuffer")
        local wall = BB.new(300, 200, BB.TYPE_BB8)
        wall:fill(BB.COLOR_WHITE)
        check(Theme.paintOrnament(wall, "x", 0, 300, 180, 150) == nil and wall:getPixel(250, 181):getColor8().a == 255
            and Theme.plan("x", 300, 150) == nil and sides(Theme.rowsFor("downloads", { 1, 2 })) == "----", "no ornaments: nothing is planned or drawn")
        -- Settings → … → Bookshelf theme: the theme screen (gzreader_shelfpreview.lua)
        local item = Theme.settingsItem()
        local shown_with
        package.loaded["gzreader_shelfpreview"] = { show = function(cb) shown_with = cb or true; return true end }
        local refreshed
        item.callback({ updateItems = function() refreshed = true end })
        check(item.text == "Bookshelf theme" and item.sub_item_table == nil and item.keep_menu_open and type(shown_with) == "function",
            "Settings: Bookshelf theme opens the theme screen (no list of rows)")
        shown_with()
        check(refreshed, "…and Settings' row is drawn again when it closes")
        package.loaded["gzreader_shelfpreview"] = nil
        package.loaded["gzreader_shelftheme"] = Theme
        local okp, P = pcall(dofile, REPO .. "/plugins/gzreader.koplugin/gzreader_shelfpreview.lua")
        check(okp, "gzreader_shelfpreview loads " .. tostring(not okp and P or ""))
        if okp then
            -- the theme screen's choices
            local secs = P.sections()
            local sec_names = {}
            for i, sec in ipairs(secs) do
                local labels = {}
                for j, c in ipairs(sec.items) do labels[j] = c.label end
                sec_names[i] = sec.title .. ": " .. table.concat(labels, ", ")
            end
            check(table.concat(sec_names, " | ") == "Plank: Oak, Walnut, Plain | Ornaments: None, Where there's room, On every page | Where on the shelf: Right end, Left end, Scattered | How many on a page: One, Up to two, Up to three, Every shelf",
                "the theme screen: " .. table.concat(sec_names, " | "))
            secs[1].items[2].pick(); secs[2].items[3].pick(); secs[3].items[3].pick(); secs[4].items[4].pick()
            check(Theme.get() == "walnut" and Theme.ornaments() == "always" and Theme.side() == "scattered" and Theme.count() == math.huge
                and secs[1].items[2].on() and not secs[1].items[1].on() and secs[2].items[3].on() and secs[3].items[3].on() and secs[4].items[4].on(),
                "a tile sets what it says, and is the one marked")
            secs[1].items[1].pick(); secs[2].items[2].pick(); secs[3].items[1].pick(); secs[4].items[1].pick()
            check(Theme.get() == "oak" and Theme.ornaments() == "room" and Theme.side() == "right" and Theme.count() == 1 and secs[4].items[1].on(),
                "…and back")
            local places = P.places()
            check(#places == 3 and places[1].label == "Home" and places[3].label == "Catalog" and places[1].on(), "chips: Home, Downloads, Catalog")
            places[1].pick()
            check(not Theme.placeOn("home") and not places[1].on(), "…a chip turns its screen's ornaments off")
            places[1].pick()
            check(Theme.placeOn("home"), "…and on")
            -- Which ornaments
            Theme.today = { 6, 10 }
            local all = Theme.list()
            local function find(label) for _i, e in ipairs(all) do if e.label == label then return e end end end
            local xmas, pumpkin = find("Christmas tree"), find("Pumpkin")
            local on_n, total = P.counts()
            local want = 0
            for _i, e in ipairs(all) do if Theme.isOn(e) then want = want + 1 end end
            check(total == #all and on_n == want and on_n == total - 2, "Which ornaments: " .. on_n .. " of " .. total .. " stand (in June, not the seasonal two)")
            check(P.seasonTag(xmas) == "Not in season" and P.seasonTag(find("Potted plant")) == nil, "a seasonal one out of its season says so; the others have no tag")
            Theme.today = { 10, 31 }
            check(P.seasonTag(pumpkin) == "In season" and P.firstShown() == pumpkin, "…in its season it says so, and the preview starts with it")
            Theme.today = { 6, 10 }
            check(not P.seasonalByHand(), "nothing ticked by hand yet")
            Theme.setOn(xmas, true)
            check(Theme.isOn(xmas) and P.seasonTag(xmas) == nil and P.seasonalByHand(), "ticking the Christmas tree in June: it stands all year, no season tag")
            Theme.resetChosen()
            check(not Theme.isOn(xmas) and not P.seasonalByHand(), "Seasonal ones in their season again")
            local n_pages, pg, first, last = P.pageOf(21, 20, 2)
            local pages1, pg1, first1, last1 = P.pageOf(19, 20, 1)
            check(n_pages == 2 and pg == 2 and first == 21 and last == 22 and pages1 == 1 and pg1 == 1 and first1 == 1 and last1 == 20,
                "ornaments on pages: Your own… the last place")
            -- what fits on a screen
            for _i, size in ipairs({ { 600, 800 }, { 1072, 1448 }, { 758, 1024 }, { 824, 1200 } }) do
                local L = P.themeLayout(size[1], size[2])
                local W2 = P.whichLayout(size[1], size[2])
                local grid_end = W2.grid_y + W2.rows * (W2.ph + W2.cap_h) + (W2.rows - 1) * W2.gap
                check(L.rows_y + 2 * L.row_h <= size[2] and L.ph >= 36 and L.sections[4].y + L.sections[4].ph + L.cap_h < L.rows_y
                    and grid_end <= W2.footer_y and W2.per >= 12,
                    "the theme screen and Which ornaments fit " .. size[1] .. " x " .. size[2] .. " (" .. W2.cols .. " x " .. W2.rows .. ")")
            end
        end
        -- while the theme screen is open, a change is only noted; the shelves are drawn again once, when it closes
        local stub_changed = Theme.changed
        Theme.changed = real_changed
        Theme.defer(true)
        local planks_before = Theme.planks
        Theme.found = Theme.list()
        Theme.setOrnaments("always")
        check(Theme.deferred == "pending" and Theme.planks == planks_before and Theme.found == nil and Theme.ornaments() == "always",
            "a change while the theme screen is open: kept, the shelves not drawn yet")
        Theme.defer(false)
        check(Theme.deferred == nil and Theme.planks ~= planks_before, "…drawn again when it closes")
        Theme.defer(true); Theme.defer(false)
        check(Theme.deferred == nil, "…and nothing to do when nothing changed")
        Theme.changed = stub_changed
        -- the little pictures take narrow ornaments the shelves would leave out
        local narrow = { aspect = 0.3, tall = 0.6 }
        check(Theme.size(narrow, 60, 400) == nil and Theme.size(narrow, 60, 400, true) ~= nil, "narrow ornaments: only in the theme screen's pictures")
        -- a hold on an ornament: the theme screen
        local shelf_w, other = {}, {}
        local wall2 = BB.new(300, 200, BB.TYPE_BB8)
        wall2:fill(BB.COLOR_WHITE)
        -- (a picture of its own: pictures aren't decoded here)
        local spot = Theme.paintPlanned(wall2, { img = BB.new(40, 60, BB.TYPE_BB8), w = 40, h = 60 }, 200, 180, shelf_w)
        check(spot ~= nil and Theme.at(shelf_w, { x = spot.x + 2, y = spot.y + 2 }) == spot
            and Theme.at(shelf_w, { x = spot.x - 5, y = spot.y + 2 }) == nil and Theme.at(other, { x = spot.x + 2, y = spot.y + 2 }) == nil,
            "a drawn ornament's place is kept by the shelf that drew it")
        local opened = nil
        package.loaded["gzreader_shelfpreview"] = { show = function() opened = true; return true end }
        local off_it = Theme.hold(shelf_w, { x = spot.x - 5, y = spot.y + 2 })
        check(off_it == false and opened == nil, "a hold beside the ornament: nothing (the shelf's own hold, if any)")
        local on_it = Theme.hold(shelf_w, { x = spot.x + math.floor(spot.w / 2), y = spot.y + math.floor(spot.h / 2) })
        check(on_it == true and opened, "a hold on the ornament: the theme screen")
        package.loaded["gzreader_shelfpreview"] = nil
        Theme.forget(shelf_w)
        check(Theme.at(shelf_w, { x = spot.x + 2, y = spot.y + 2 }) == nil, "drawn again: the old place is forgotten")
    end
    os.execute("rm -rf '" .. udir .. "'")
    -- where it's asked for
    local function slurp(path) local fh = io.open(REPO .. "/" .. path, "r"); local t = fh and fh:read("*a"); if fh then fh:close() end; return t or "" end
    check(slurp("plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua"):find('Theme.plank(w, top_h, front_h)', 1, true)
        and slurp("plugins/gzreader.koplugin/gzreader_bookshop.lua"):find('Theme.plank(r.w, top_h, r.h - top_h)', 1, true),
        "the boards (Home, Downloads) and the Catalog's ledges ask for the theme's plank")
    check(slurp("plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua"):find('rowsFor("home", occupied)', 1, true)
        and slurp("plugins/gzreader.koplugin/gzreader_shelfview.lua"):find('rowsFor("downloads", occupied)', 1, true)
        and slurp("plugins/gzreader.koplugin/gzreader_bookshop.lua"):find('Theme.placeOn("catalog")', 1, true),
        "Home's shelf, Downloads' shelves and the Catalog's ledges ask where their ornaments go")
    for _i, w in ipairs({ { "plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua", "Shelf" },
            { "plugins/gzreader.koplugin/gzreader_shelfview.lua", "Row" }, { "plugins/gzreader.koplugin/gzreader_bookshop.lua", "Page" } }) do
        local src = slurp(w[1])
        local gesture = src:match("function " .. w[2] .. ":onGesture%(ev%)(.-)\nend\n") or ""
        local paint = src:match("function " .. w[2] .. ":paintTo%(bb, x, y%)\n(.-)\n") or ""
        local paint2 = src:match("function " .. w[2] .. ":paintTo%(bb, x, y%)\n.-\n(.-)\n") or ""
        check(gesture:find('ev.ges == "hold"', 1, true) and gesture:find("Theme.hold(self, ev.pos)", 1, true)
            and (paint .. paint2):find('.forget(self)', 1, true)
            and (src:find("board_y, self)", 1, true) or src:find("led.box_h, i, self)", 1, true)),
            w[1]:match("[^/]+$") .. ": a hold on its ornament opens the settings; it says where it drew one, and forgets it when drawn again")
    end
    check(slurp("plugins/zenos.koplugin/modules/settings/sections/library_settings.lua"):find('ShelfTheme.settingsItem()', 1, true),
        "Settings → Downloads → Appearance has Bookshelf theme")
    local png = io.open(REPO .. "/plugins/gzreader.koplugin/icons/shelf/plank-oak.png", "rb")
    local head = png and png:read(24) or ""
    if png then png:close() end
    check(head:sub(1, 4) == "\137PNG" and head:byte(20) == 480 % 256 and head:byte(24) == 32, "the oak plank's picture: 480 x 32 (24 rows of its top, 8 of its front)")
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
