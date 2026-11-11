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
        Theme.changed = function() Theme.planks, Theme.images, Theme.found = {}, {}, nil end
        check(Theme.get() == "oak" and Theme.ornaments() == "room", "to begin with: the Oak plank, ornaments where there's room")
        check(Theme.set("walnut") and Theme.get() == "walnut" and not Theme.set("marble") and Theme.get() == "walnut", "a theme is one of Plain, Oak, Walnut")
        settings[Theme.SETTING] = "nonsense"
        check(Theme.get() == "oak", "a theme this version doesn't know: Oak")
        check(Theme.setOrnaments("always") and Theme.ornaments() == "always" and not Theme.setOrnaments("lots"), "ornaments: off, where there's room, or on every page")
        Theme.set("plain")
        check(Theme.plank(600, 8, 9) == nil, "Plain: no picture for the plank (the board is drawn in greys)")
        -- the two that come with it, measured from their files
        local list = Theme.list()
        check(#list == 2 and list[1].name == "ornament-plant.svg" and math.abs(list[1].aspect - 60 / 106) < 0.001 and list[2].name == "ornament-cactus.svg",
            "Bookshelf's potted plant and cactus, their shape from their viewBox")
        for _i, e in ipairs(list) do
            local f = io.open(e.path, "r")
            local text = f:read("*a")
            f:close()
            check(text:find("From Bookshelf by AndyHazz", 1, true) and text:find("AGPL-3.0", 1, true), e.name .. " says where it's from and its licence")
        end
        -- the reader's own: PNG and SVG files, by name, others left out
        local function write(name, data) local f = io.open(udir .. "/gzreader/ornaments/" .. name, "wb"); f:write(data); f:close() end
        write("globe.png", "\137PNG\r\n\26\n\0\0\0\13IHDR\0\0\0\200\0\0\0\100" .. string.rep("\0", 16))
        write("Vase.SVG", '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 80"></svg>')
        write("notes.txt", "x")
        write("broken.svg", "<svg></svg>")
        dir_files = { ".", "..", "notes.txt", "globe.png", "broken.svg", "Vase.SVG", ".hidden.png" }
        Theme.found = nil
        list = Theme.list()
        check(#list == 4 and list[3].name == "Vase.SVG" and list[3].aspect == 0.5 and list[4].name == "globe.png" and list[4].aspect == 2,
            "your own PNG and SVG files join them (their shape from the file); other files and broken ones don't (" .. #list .. ")")
        check(Theme.userDir(false) == udir .. "/gzreader/ornaments", "…from koreader/settings/gzreader/ornaments")
        -- which one stands where: the same every time
        local a, b = Theme.pick("downloads:1:3"), Theme.pick("downloads:1:3")
        local seen = {}
        for i = 1, 40 do seen[Theme.pick("downloads:" .. i .. ":1").name] = true end
        local kinds = 0
        for _k in pairs(seen) do kinds = kinds + 1 end
        check(a == b and kinds == 4, "the same place has the same ornament every time; different places, different ones (" .. kinds .. " of 4)")
        -- sizes: 80% of the books' room, narrower when the room is, never under 2/3
        local plant = list[1]
        local w, h = Theme.size(plant, 150, 400)
        check(h == 120 and w == math.floor(120 * 60 / 106), "an ornament stands 80% as tall as the books' room (" .. tostring(w) .. " x " .. tostring(h) .. ")")
        local w2, h2 = Theme.size(plant, 150, 70)
        check(w2 == 50 and h2 and h2 < 120 and h2 >= 80, "less room: smaller, its shape kept (" .. tostring(w2) .. " x " .. tostring(h2) .. ")")
        check(Theme.size(plant, 150, 50) == nil and Theme.size(plant, 20, 400) == nil, "too little room, or a tiny shelf: none")
        check(Theme.reserve(150) == 120 + 20, "an ornament on every page: the bottom shelf keeps room for the widest (a square at most)")
        Theme.setOrnaments("room")
        check(Theme.reserve(150) == 0, "where there's room: nothing is kept for them")
        Theme.setOrnaments("off")
        local BB = require("ffi/blitbuffer")
        local wall = BB.new(300, 200, BB.TYPE_BB8)
        wall:fill(BB.COLOR_WHITE)
        check(Theme.paintOrnament(wall, "x", 0, 300, 180, 150) == nil and wall:getPixel(250, 181):getColor8().a == 255, "no ornaments: nothing is drawn")
        -- Settings: the themes, the ornaments, your own
        local item = Theme.settingsItem()
        local texts = {}
        for i, it in ipairs(item.sub_item_table) do texts[i] = it.text end
        check(item.text == "Bookshelf theme" and table.concat(texts, " | ") == "Plain | Oak | Walnut | No ornaments | Ornaments where there's room | An ornament on every page | Your own ornaments…",
            "Settings: " .. table.concat(texts, " | "))
        item.sub_item_table[2].callback()
        item.sub_item_table[6].callback()
        check(Theme.get() == "oak" and item.sub_item_table[2].checked_func() and not item.sub_item_table[1].checked_func()
            and Theme.ornaments() == "always" and item.sub_item_table[6].checked_func(), "choosing one sets it, and ticks it")
    end
    os.execute("rm -rf '" .. udir .. "'")
    -- where it's asked for
    local function slurp(path) local fh = io.open(REPO .. "/" .. path, "r"); local t = fh and fh:read("*a"); if fh then fh:close() end; return t or "" end
    check(slurp("plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua"):find('Theme.plank(w, top_h, front_h)', 1, true)
        and slurp("plugins/gzreader.koplugin/gzreader_bookshop.lua"):find('Theme.plank(r.w, top_h, r.h - top_h)', 1, true),
        "the boards (Home, Downloads) and the Catalog's ledges ask for the theme's plank")
    check(select(2, slurp("plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua"):gsub('paintOrnament%(', "")) == 1
        and select(2, slurp("plugins/gzreader.koplugin/gzreader_shelfview.lua"):gsub('paintOrnament%(', "")) == 1
        and select(2, slurp("plugins/gzreader.koplugin/gzreader_bookshop.lua"):gsub('paintOrnament%(', "")) == 1,
        "Home's shelf, Downloads' shelves and the Catalog's ledges stand an ornament on their free end")
    check(slurp("plugins/zenos.koplugin/modules/settings/sections/library_settings.lua"):find('ShelfTheme.settingsItem()', 1, true),
        "Settings → Downloads → Appearance has Bookshelf theme")
    local png = io.open(REPO .. "/plugins/gzreader.koplugin/icons/shelf/plank-oak.png", "rb")
    local head = png and png:read(24) or ""
    if png then png:close() end
    check(head:sub(1, 4) == "\137PNG" and head:byte(20) == 480 % 256 and head:byte(24) == 32, "the oak plank's picture: 480 x 32 (24 rows of its top, 8 of its front)")
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
