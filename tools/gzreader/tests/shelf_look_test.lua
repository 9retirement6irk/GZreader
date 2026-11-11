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
    local names = { SHELF, "ffi/blitbuffer", "ui/font", "ui/geometry", "ui/gesturerange", "ui/widget/container/inputcontainer",
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

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
