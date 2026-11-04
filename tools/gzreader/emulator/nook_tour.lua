-- Nook 1st Edition (GZ_EMU_MODEL=nook): the e-ink page and the colour
-- touchscreen under it, driven only by the colour screen and the page keys,
-- as on a real Nook: the setup guide, Home and its menu, a book with reading
-- info / cover / controls, the Reading menu, typing on the colour screen's
-- keyboard, the colour screen's settings.
--   GZ_NOOK_HOME=<dir> GZ_EMU_MODEL=nook run.sh tools/gzreader/emulator/nook_tour.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function lcd(what, after) add({ lcd = what, after = after or 2.5 }) end
local function closeNamed(names)
    return function()
        local UIManager = require("ui/uimanager")
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if names[w.name or ""] then UIManager:close(w) end
        end
    end
end

shot("01-guide")
lcd("▶", 3)
shot("02-guide-next")
add({ fn = closeNamed({ ["setup guide"] = true, ["QR code screen"] = true }), after = 6 })
shot("03-home")
lcd("Menu", 4)
shot("04-home-menu")
lcd("▼", 1.5); lcd("▼", 1.5)
shot("05-home-menu-down")
lcd("Back", 3)
-- the clock on the colour screen elsewhere
add({ fn = function()
    local NS = require("gzreader_nook")
    local st = NS.settings(); st.other = "info"; G_reader_settings:saveSetting("gzreader_nook_lcd", st); NS.refresh()
end, after = 2 })
shot("06-home-clock")
lcd({ 240, 70 }, 2)
shot("07-home-touched")
-- a book
add({ fn = function()
    local home = os.getenv("GZ_NOOK_HOME")
    os.execute("mkdir -p '" .. home .. "/GZreader' && cp '/root/work/opt/books/Persuasion.epub' '" .. home .. "/GZreader/'")
    require("apps/reader/readerui"):showReader(home .. "/GZreader/Persuasion.epub")
end, after = 20 })
shot("08-reading-info")
add({ key = "RPgFwd", after = 4 })
add({ key = "RPgFwd", after = 4 })
shot("09-page-3")
lcd({ 240, 70 }, 2)                       -- a touch: the controls
shot("10-controls")
lcd("▶▶", 4)
shot("11-page-4")
lcd("•••", 3)
shot("12-cover")
add({ lcd_swipe = { 400, 70, 80, 70 }, after = 4 })
shot("13-swiped")
add({ lcd_swipe = { 240, 120, 240, 10 }, after = 3 })
shot("14-swipe-up")
lcd("Menu", 4)
shot("15-reading-menu")
lcd("Back", 3)
-- typing on the colour screen
add({ fn = function() require("ui/uimanager"):sendEvent(require("ui/event"):new("ShowFulltextSearchInput")) end, after = 4 })
shot("16-search")
add({ lcd_type = "elliot", after = 5 })
shot("17-typed")
lcd("Done", 2)
shot("18-kb-done")
lcd("Back", 3)
-- the colour screen's settings
add({ fn = function()
    local NS = require("gzreader_nook")
    local UIManager = require("ui/uimanager")
    local Menu = require("ui/widget/menu")
    local items = {}
    for _i, it in ipairs(NS.menuItems()) do items[#items + 1] = { text = it.text } end
    _G.EMU.nook_menu = Menu:new{ title = "Colour screen", item_table = items, covers_fullscreen = true }
    UIManager:show(_G.EMU.nook_menu)
end, after = 3 })
shot("19-settings")
lcd("Back", 3)
lcd("Home", 8)
shot("20-home-again")
return s
