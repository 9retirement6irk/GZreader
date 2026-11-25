-- Settings → About: GZreader's version tapped seven times plays an
-- animation (as Android's easter egg): a book whose pages turn, writing
-- "GZreader" a letter a turn. A tap or Back closes it.
--   GZ_EMU_MODEL=pw3|k3 GZ_EMU_TREE=<tree>/koreader run.sh easter_egg.lua <out>
-- Checks go to <out>/easter-egg-checks.txt; shots 1-first-letter, 2-page-turning, 3-last-page.
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
add({ fn = function()
    local g = game()
    check(g ~= nil and g.n >= 1 and g.n < Egg().FRAMES, "the seventh: the animation, playing")
end, after = 2.2 })
add({ shot = "1-first-letter", after = 0.1 })
add({ fn = function()
    local g = game()
    check(g ~= nil and g.n > 4, "it plays by itself (frame " .. tostring(g and g.n) .. ")")
    -- on to a page in the air mid-word, then the last page, to look at them
    UIM():unschedule(g.tick)
    g.n = 13
    UIM():setDirty(g, "ui")
end, after = 1.5 })
add({ shot = "2-page-turning", after = 0.5 })
add({ fn = function()
    local g = game()
    g.n, g.loop = Egg().FRAMES, Egg().LOOPS
    UIM():setDirty(g, "ui")
    g:advance()
    check(g.n == Egg().FRAMES, "after its last time through it rests on the last page")
end, after = 1.5 })
add({ shot = "3-last-page", after = 0.5 })
if TOUCH then
    add({ fn = function(E) E.tap({ 200, 300 }) end, after = 3 })
else
    add({ key = "Back", after = 3 })
end
add({ fn = function(E)
    check(game() == nil, TOUCH and "a tap closes it" or "Back closes it")
    local f = io.open(E.out .. "/easter-egg-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
