-- Nook Simple Touch (GZ_EMU_MODEL=nst): GZreader by touch on its 600 × 800
-- e-ink screen, as on a Kindle Touch: the setup guide, Home and its tabs,
-- the launcher, a book, its menus, the page buttons.
--   GZ_NOOK_HOME=<dir> GZ_EMU_MODEL=nst run.sh tools/gzreader/emulator/nst_tour.lua <out>
local s = { start = 16 }
local function at(x, y) return function() return x * 600 / 1072, y * 800 / 1448 end end
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function tap(what, after) add({ tap = what, after = after or 3 }) end

shot("01-guide")
tap(at(950, 1390), 4)                  -- Next
shot("02-guide-next")
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
shot("03-home")
tap(at(325, 1380), 6); shot("04-downloads")
tap(at(740, 1380), 10); shot("05-notes")
tap(at(918, 1380), 12); shot("06-calendar")
tap(at(128, 1380), 6); shot("07-home")
add({ swipe = { 300, 3, 300, 400 }, after = 4 }); shot("08-swipe-down")
tap(at(200, 48), 4); shot("09-launcher")
tap("GZreader", 5); shot("10-gz-menu")
tap(at(1040, 40), 4)
add({ fn = function()
    local home = os.getenv("GZ_NOOK_HOME")
    os.execute("mkdir -p '" .. home .. "/GZreader' && cp '/root/work/opt/books/Persuasion.epub' '" .. home .. "/GZreader/'")
    require("apps/reader/readerui"):showReader(home .. "/GZreader/Persuasion.epub")
end, after = 20 })
shot("11-book")
tap({ 540, 400 }, 4); shot("12-tap-next")
add({ key = "RPgFwd", after = 4 }); shot("13-page-button")
tap({ 300, 60 }, 4); shot("14-top-menu")
tap({ 300, 400 }, 4)
add({ key = "Home", after = 8 }); shot("15-home-again")
return s
