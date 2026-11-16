-- Menus and text on big screens (frontend/gzuiscale.lua).
-- Usage: luajit uiscale_test.lua <repo>
local REPO = arg[1] or "../../.."
local passed, failed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end

-- stand-ins for what the module asks KOReader for
local logged = {}
package.loaded["logger"] = { info = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end }
package.loaded["gettext"] = setmetatable({}, { __call = function(_s, t)
    return (t:gsub("KOReader", "GZreader")) -- (as frontend/gettext.lua brands it)
end })
package.loaded["ffi/util"] = { template = function(t, a) return (t:gsub("%%1", a)) end }
local restarts = 0
package.loaded["ui/uimanager"] = { askForRestart = function() restarts = restarts + 1 end }
local store = {}
G_reader_settings = {
    readSetting = function(_s, k) return store[k] end,
    saveSetting = function(_s, k, v) store[k] = v end,
}

local S = dofile(REPO .. "/frontend/gzuiscale.lua")

local function near(a, b) return a ~= nil and math.abs(a - b) < 0.01 end

-- which screens change
check(S.scaleFor(600, 167) == nil, "Kindle 3 / 4 / Nook (600 px, 167 dpi): KOReader's scale")
check(S.scaleFor(1072, 300) == nil, "Paperwhite 3 (1072 px, 300 dpi): KOReader's scale")
check(S.scaleFor(1264, 300) == nil, "Oasis / Colorsoft (1264 px, 300 dpi): KOReader's scale")
check(S.scaleFor(1236, 300) == nil, "Paperwhite 5: KOReader's scale")
local scribe = S.scaleFor(1860, 300)
check(near(scribe, 2.31), "Scribe (1860 px, 300 dpi): 2.31 instead of 3.10 (" .. tostring(scribe) .. ")")
check(near(S.scaleFor(824, 150), 1.12), "DX (824 px, 150 dpi): 1.12 instead of 1.37 (" .. tostring(S.scaleFor(824, 150)) .. ")")
check(S.scaleFor(1860, nil) == nil and S.scaleFor(1860, 0) == nil, "no DPI known: KOReader's")
-- what it looks like to the eye, compared with a Kindle 3 (1/167 inch per unit)
local k3 = 1 / 167
check(scribe / 300 / k3 < 1.35 and S.koreaderScale(1860) / 300 / k3 > 1.7,
    "on a Scribe things are about 1.3 times a Kindle 3's size (KOReader: 1.7)")
-- the choices
check(near(S.scaleFor(1860, 300, "smaller"), 2.31 * 0.87), "Smaller: 13% smaller")
check(near(S.scaleFor(1860, 300, "larger"), 2.31 * 1.15), "Larger: 15% larger")
check(S.scaleFor(1860, 300, "koreader") == nil, "As large as KOReader makes them: KOReader's")
check(near(S.scaleFor(824, 150, "larger"), 1.12 * 1.15), "a DX on Larger: 1.29")
S.CHOICES.larger = 2
check(S.scaleFor(1860, 300, "larger") == nil, "never bigger than KOReader's (Larger past it: KOReader's)")
S.CHOICES.larger = 1.15
check(S.choice() == nil, "no setting: automatic")
store.gzreader_ui_size = "bogus"
check(S.choice() == nil, "an unknown value: automatic")
store.gzreader_ui_size = nil

-- applied to a device
local function device(w, h, dpi)
    local screen = { w = w, h = h }
    function screen:getWidth() return self.w end
    function screen:getHeight() return self.h end
    function screen:scaleBySize(px) -- KOReader's (ffi/framebuffer.lua)
        local size_scale = math.min(self:getWidth(), self:getHeight()) / 600
        local dpi_scale = self.dpi_override and self.dpi / 160 or size_scale
        return math.ceil(px * (size_scale + dpi_scale) / 2)
    end
    return { screen = screen, display_dpi = dpi }
end

local k3dev = device(600, 800, 167)
local before = k3dev.screen.scaleBySize
check(S.apply(k3dev) == nil and k3dev.screen.scaleBySize == before,
    "Kindle 3: nothing replaced")
check(#logged == 0, "…and nothing logged")

local dev = device(1860, 2480, 300)
check(near(S.apply(dev), 2.31), "Scribe: applied")
check(dev.screen:scaleBySize(100) == 232, "a menu's 100 becomes 232 (KOReader: 310): " .. dev.screen:scaleBySize(100))
dev.screen.w, dev.screen.h = 2480, 1860
check(dev.screen:scaleBySize(100) == 232, "the same turned sideways")
check(logged[1] and logged[1]:match("2%.31") and logged[1]:match("3%.10") and logged[1]:match("6%.2%-inch"),
    "logged: the scale, KOReader's and the screen's width (" .. tostring(logged[1]) .. ")")
-- a book's page keeps KOReader's sizes
local function callFrom(chunkname)
    local fn = load("local Screen = ...; local v = Screen:scaleBySize(20); return v", chunkname)
    return fn(dev.screen)
end
check(callFrom("@./frontend/apps/reader/modules/readerfont.lua") == 62, "the book's font size: KOReader's (20 → 62)")
check(callFrom("@frontend/apps/reader/modules/readertypeset.lua") == 62, "the book's margins: KOReader's")
check(callFrom("@plugins/zenos.koplugin/common/reader_defaults.lua") == 62, "ZenOS's reading defaults (the setup guide sets the font size): KOReader's")
check(callFrom("@frontend/document/pdfdocument.lua") == 62, "a document's own (a PDF's reflow font, through CanvasContext): KOReader's")
check(callFrom("@frontend/apps/reader/modules/readerfooter.lua") == 47, "the book's status bar: GZreader's (20 → 47)")
check(callFrom("@plugins/zenos.koplugin/modules/filebrowser/patches/home/home_page.lua") == 47, "Home: GZreader's")
check(S.isBookCaller("@C:\\x\\readerfont.lua") and not S.isBookCaller(nil) and not S.isBookCaller("=[C]"),
    "callers told apart by the file's name")
-- a DPI set in KOReader's Screen menu wins
dev.screen.dpi_override, dev.screen.dpi = true, 200
check(dev.screen:scaleBySize(100) == math.ceil(100 * (1860 / 600 + 200 / 160) / 2), "a DPI the user set: KOReader's sum")
dev.screen.dpi_override = nil

-- the choice applied
store.gzreader_ui_size = "koreader"
local kodev = device(1860, 2480, 300)
check(S.apply(kodev) == nil and kodev.screen:scaleBySize(100) == 310, "As large as KOReader makes them: KOReader's 310")
store.gzreader_ui_size = "smaller"
local sdev = device(1860, 2480, 300)
S.apply(sdev)
check(sdev.screen:scaleBySize(100) == 202, "Smaller: 202 (" .. sdev.screen:scaleBySize(100) .. ")")
store.gzreader_ui_size = nil

-- the setting (Settings → Interface)
check(S.menuItem(device(600, 800, 167)) == nil, "no setting on a Kindle 3")
check(S.menuItem(device(1072, 1448, 300)) == nil, "…nor on a Paperwhite 3")
local item = S.menuItem(device(1860, 2480, 300))
check(item and #item.sub_item_table == 4, "on a Scribe: Size of menus and text, four choices")
check(item.text_func() == "Size of menus and text: Automatic", "shows Automatic: " .. item.text_func())
check(item.sub_item_table[1].checked_func() and not item.sub_item_table[2].checked_func(), "Automatic ticked")
check(item.sub_item_table[4].text == "As large as KOReader makes them", "KOReader named as KOReader (not branded): " .. item.sub_item_table[4].text)
item.sub_item_table[2].callback()
check(store.gzreader_ui_size == "smaller" and restarts == 1, "Smaller: saved, asks to restart")
check(item.text_func() == "Size of menus and text: Smaller", "…and shown")
item.sub_item_table[2].callback()
check(restarts == 1, "the same choice again: no restart asked")
item.sub_item_table[1].callback()
check(store.gzreader_ui_size == nil and restarts == 2, "back to Automatic: cleared, asks to restart")

-- where it's called from
local function read(p) local f = assert(io.open(REPO .. "/" .. p)); local s = f:read("*a"); f:close(); return s end
local reader = read("reader.lua")
local at_device = reader:find('local Device = require("device")', 1, true)
local at_scale = reader:find('require("gzuiscale").apply(Device)', 1, true)
local at_ui = reader:find('require("ui/uimanager")', 1, true)
check(at_device and at_scale and at_ui and at_device < at_scale and at_scale < at_ui,
    "reader.lua: applied right after the device is set up, before any widget is loaded")
check(read("plugins/zenos.koplugin/modules/settings/sections/interface_settings.lua"):find('GzUiScale.menuItem()', 1, true) ~= nil,
    "Settings → Interface offers it")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
