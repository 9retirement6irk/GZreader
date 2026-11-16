-- GZreader: menus and text on big screens (the Kindle Scribe, the DX).
--
-- KOReader sizes everything it draws with Screen:scaleBySize, which grows
-- with the screen's width in pixels (its shorter side / 600). On a 6-7"
-- Kindle that keeps things the same size on paper whatever the resolution,
-- but on a big screen everything grows with the screen: on a Scribe (1860
-- pixels at 300 dpi, 6.2" wide) menus, buttons and text came out 3.1 times
-- their size, about 1.7 times as big to the eye as on a Kindle 3 or a
-- Paperwhite.
--
-- On a screen wider than BIG_IN inches GZreader sizes them for the screen's
-- density instead, as on the biggest 6-7" Kindles (REF_IN wide), and lets
-- them grow only with the fourth root of the extra width: a Scribe gets
-- 2.31 (25% smaller than KOReader's), a DX 1.12 (KOReader's 1.37). Smaller
-- and screens up to BIG_IN are left exactly as KOReader sizes them.
--
-- A book's pages are not changed: the font size, margins and what's worked
-- out from them (the calls from BOOK_CALLERS) keep KOReader's scale, so a
-- book looks as it did. A DPI the user set in KOReader's own Screen menu
-- wins too. Settings → Interface → Size of menus and text (big screens
-- only; `gzreader_ui_size`: nil/auto, smaller, larger, koreader) changes
-- it from the next start.
-- Called from reader.lua right after the device is set up.
local M = {
    BIG_IN = 5.0, -- inches across (the shorter side) from which this applies
    REF_IN = 4.2, -- the widest 6-7" Kindles (Oasis, Colorsoft, Paperwhite 5: 4.1-4.2")
    GROWTH = 0.25, -- how much of the extra width things grow with (a power)
    CHOICES = { smaller = 0.87, larger = 1.15 },
    SETTING = "gzreader_ui_size",
}

-- KOReader's modules whose scaleBySize sizes a book's page (its font size,
-- margins, and the line heights and link boxes worked out from them).
M.BOOK_CALLERS = {
    ["readerfont.lua"] = true, ["readertypeset.lua"] = true,
    ["readerrolling.lua"] = true, ["readerlink.lua"] = true,
    ["readerpagemap.lua"] = true, ["readerpaging.lua"] = true,
    ["reader_defaults.lua"] = true, -- (ZenOS's reading defaults set the font size too)
}

--- The screen's shorter side in inches (nil when the DPI isn't known).
function M.inches(short_px, dpi)
    if not (short_px and dpi and dpi > 0) then return nil end
    return short_px / dpi
end

--- KOReader's own scale for a screen this wide (no DPI override).
function M.koreaderScale(short_px) return short_px / 600 end

--- GZreader's scale for a screen (`choice`: the setting's value), or nil
--- where KOReader's stays: a screen up to BIG_IN inches across, an unknown
--- DPI, or the choice "koreader". Never bigger than KOReader's.
function M.scaleFor(short_px, dpi, choice)
    local inches = M.inches(short_px, dpi)
    if not inches or inches <= M.BIG_IN or choice == "koreader" then return nil end
    local s = dpi * M.REF_IN / 600 * (inches / M.REF_IN) ^ M.GROWTH
    s = s * (M.CHOICES[choice] or 1)
    local ko = M.koreaderScale(short_px)
    if s >= ko then return nil end
    return s
end

--- Whether `source` (debug.getinfo's) is one of BOOK_CALLERS or a
--- document's own code (frontend/document/: a PDF's reflow font size; its
--- calls through CanvasContext are tail calls, so they show as the caller).
function M.isBookCaller(source)
    if type(source) ~= "string" then return false end
    if source:find("[/\\]document[/\\]") then return true end
    local name = source:match("([^/\\]+)$")
    return name ~= nil and M.BOOK_CALLERS[name] == true
end

--- The device's screen: its shorter side in pixels and its real DPI.
local function screenOf(device)
    local screen = device and device.screen
    if not screen then return nil end
    local w, h = screen:getWidth(), screen:getHeight()
    local dpi = device.display_dpi or (device.getDeviceScreenDPI and device:getDeviceScreenDPI())
    return screen, math.min(w, h), dpi
end

--- Whether this device has a big screen (the setting is offered there).
function M.isBig(device)
    local short, dpi = select(2, screenOf(device))
    local inches = M.inches(short, dpi)
    return inches ~= nil and inches > M.BIG_IN
end

--- The setting's value (nil: automatic).
function M.choice(settings)
    settings = settings or G_reader_settings
    local v = settings and settings:readSetting(M.SETTING)
    if v == "smaller" or v == "larger" or v == "koreader" then return v end
    return nil
end

--- Size the device's menus and text for its screen (see the top). Returns
--- the scale used, or nil when KOReader's is kept.
function M.apply(device, settings)
    local screen, short, dpi = screenOf(device)
    if not screen then return nil end
    local s = M.scaleFor(short, dpi, M.choice(settings))
    M.scale, M.short, M.dpi = s, short, dpi
    if not s then return nil end
    local orig = screen.scaleBySize
    M.orig = orig
    screen.scaleBySize = function(self, px)
        -- (a DPI set in KOReader's Screen menu: KOReader's sum, as asked)
        if self.dpi_override then return orig(self, px) end
        local info = debug.getinfo(2, "S")
        if info and M.isBookCaller(info.source) then return orig(self, px) end
        return math.ceil(px * s)
    end
    local ok, logger = pcall(require, "logger")
    if ok and logger then
        logger.info(string.format("GZreader: menus and text at %.2f (KOReader's %.2f) on a %.1f-inch-wide screen",
            s, M.koreaderScale(short), short / dpi))
    end
    return s
end

--- Settings → Interface → Size of menus and text, on big screens (nil
--- elsewhere). `restart`: asks to restart (UIManager:askForRestart).
function M.menuItem(device, restart)
    if not device then
        local ok, d = pcall(require, "device")
        device = ok and d or nil
    end
    if not M.isBig(device) then return nil end
    local _ = require("gettext")
    restart = restart or function()
        require("ui/uimanager"):askForRestart(_("Restart GZreader to change the size of menus and text."))
    end
    local function item(text, value)
        return {
            text = text,
            radio = true,
            checked_func = function() return M.choice() == value end,
            callback = function()
                if M.choice() == value then return end
                G_reader_settings:saveSetting(M.SETTING, value)
                restart()
            end,
        }
    end
    local names = {
        smaller = _("Smaller"), larger = _("Larger"),
        -- (as an argument: gettext.lua shows "KOReader" in a text as "GZreader")
        koreader = require("ffi/util").template(_("As large as %1 makes them"), "KOReader"),
    }
    return {
        text_func = function()
            local c = M.choice()
            return _("Size of menus and text") .. ": " .. (c and names[c] or _("Automatic"))
        end,
        sub_item_table = {
            item(_("Automatic (for this screen)"), nil),
            item(names.smaller, "smaller"),
            item(names.larger, "larger"),
            item(names.koreader, "koreader"),
        },
    }
end

return M
