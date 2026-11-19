-- Settings → About: GZreader's version tapped seven times opens the 15
-- puzzle (as Android's easter egg). Taps on a touch Kindle, the 5-way on
-- the others; solved, it says in how many moves; Back closes it.
--   GZ_EMU_MODEL=pw3|k3 GZ_EMU_TREE=<tree>/koreader run.sh easter_egg.lua <out>
-- Checks go to <out>/easter-egg-checks.txt; shots 1-puzzle, 2-solved.
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local TOUCH = MODEL == "pw3" or MODEL == "kt" or MODEL == "scribe"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function Egg() return require("gzreader_easteregg") end
local function game() for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_egg" then return w.widget end end end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
end, after = 2 })
-- the version row as Settings → About builds it: its callback, seven times
add({ fn = function(E)
    local about = require("modules/settings/sections/about_settings")
    local items = about.build({ plugin = { path = "", version = "x" }, config = {} })
    E.row = items[1]
    check(type(E.row.callback) == "function" and E.row.keep_menu_open, "About's first row (GZreader's version) takes taps, the menu stays")
    for _i = 1, 6 do E.row.callback() end
    check(game() == nil, "six taps: not yet")
    E.row.callback()
end, after = 3 })
add({ shot = "1-puzzle", after = 0.5 })
add({ fn = function(E)
    local g = game()
    check(g ~= nil and not Egg().solved(g.board) and g.board.moves == 0, "the seventh: the 15 puzzle, shuffled")
    -- set two moves from solved, to check winning (the gap where the 15 was, the 15 left of it… the 11 above)
    local b = Egg().new()
    Egg().slideDir(b, "right"); Egg().slideDir(b, "down")
    b.moves = 0
    g.board = b
    UIM():setDirty(g, "ui")
end, after = 2 })
if TOUCH then
    add({ fn = function(E)
        local g = game()
        local r = g:cellRect(g.board.gap + 4) -- (the tile below the gap)
        E.tap({ r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) })
    end, after = 2 })
    add({ fn = function(E)
        local g = game()
        check(g.board.moves == 1, "a tap on the tile below the gap: it slides up (1 move)")
        local r = g:cellRect(g.board.gap + 1)
        E.tap({ r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) })
    end, after = 2 })
else
    add({ key = "Up", after = 2 })
    add({ fn = function() check(game().board.moves == 1, "▲: the tile below the gap slides up (1 move)") end, after = 0.5 })
    add({ key = "Left", after = 2 })
end
add({ shot = "2-solved", after = 0.5 })
add({ fn = function(E)
    local g = game()
    check(g.won and Egg().solved(g.board) and g.board.moves == 2, "…and the last one: solved in 2 moves")
    check(G_reader_settings:readSetting(Egg().BEST) == 2, "…the best kept")
    G_reader_settings:delSetting(Egg().BEST)
end, after = 1 })
if TOUCH then
    add({ fn = function(E) local r = game().close_rect; E.tap({ r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) }) end, after = 3 })
else
    add({ key = "Back", after = 3 })
end
add({ fn = function(E)
    check(game() == nil, TOUCH and "✕ closes it" or "Back closes it")
    local f = io.open(E.out .. "/easter-egg-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
