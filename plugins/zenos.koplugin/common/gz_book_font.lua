-- GZreader: a book's default font size on big screens (the Kindle Scribe, the DX).
--
-- KOReader's font size is in its own units, scaled by the screen's width in
-- pixels (Screen:scaleBySize): ZenOS's default, 23, is about 10 points on a
-- Paperwhite or a Kindle 3 but 17 on a Scribe (1860 pixels at 300 dpi), a
-- large-print book. On a screen more than BIG_IN inches across the default
-- is made smaller in step with the screen's width, so a book's text comes
-- out the size it is on a 6-7" Kindle: 23 × REF_IN / inches, to the half:
-- 14 on a Scribe (6.2"), 16 on a DX (5.5").
--
-- Applied where the default is used:
--  * ZenOS's reading defaults (common/reader_defaults.lua: the setup guide
--    and Reset to defaults) take `defaultSize()`;
--  * once, the saved global size (`copt_font_size`) when it's still one of
--    the old defaults (`migrateGlobal`, `gzreader_big_font_default_done`);
--  * once per book, a size the book kept from before that's one of the old
--    defaults (`checkBook`, from ReaderFont:onReadSettings, before the book is
--    laid out; `gz_big_font_checked` in the book's settings). A size you chose
--    yourself (anything else) is never changed.
-- Other Kindles: nothing changes.
local M = {
    BIG_IN = 5.0,
    REF_IN = 3.8, -- (a 6" Kindle's screen across: Kindle 3 3.6", Paperwhite 3.6", Oasis 4.2")
    ZEN_DEFAULT = 23,
    -- the old defaults: KOReader's 22, ZenOS's 23 and the 22.5 the owner's Scribe had
    OLD = { [22] = true, [22.5] = true, [23] = true },
    GLOBAL_DONE = "gzreader_big_font_default_done",
    BOOK_DONE = "gz_big_font_checked",
}

local function device(dev)
    if dev then return dev end
    local ok, d = pcall(require, "device")
    return ok and d or nil
end

--- The screen's shorter side in inches (nil when the DPI isn't known).
function M.inches(dev)
    dev = device(dev)
    local dpi = dev and dev.display_dpi
    if not (dpi and dpi > 0 and dev.screen) then return nil end
    return math.min(dev.screen:getWidth(), dev.screen:getHeight()) / dpi
end

function M.bigScreen(dev)
    local inches = M.inches(dev)
    return inches ~= nil and inches > M.BIG_IN
end

--- The default font size for a book on this screen.
function M.defaultSize(dev)
    local inches = M.inches(dev)
    if not inches or inches <= M.BIG_IN then return M.ZEN_DEFAULT end
    return math.floor(M.ZEN_DEFAULT * M.REF_IN / inches * 2 + 0.5) / 2
end

function M.isOldDefault(size) return type(size) == "number" and M.OLD[size] == true end

--- Once: the saved global size, when it's still an old default (or unset),
--- becomes this screen's default. Returns the new size or nil.
function M.migrateGlobal(settings, dev)
    settings = settings or G_reader_settings
    if not settings or settings:isTrue(M.GLOBAL_DONE) or not M.bigScreen(dev) then return nil end
    settings:saveSetting(M.GLOBAL_DONE, true)
    local size = settings:readSetting("copt_font_size")
    if size ~= nil and not M.isOldDefault(size) then return nil end
    local new = M.defaultSize(dev)
    settings:saveSetting("copt_font_size", new)
    return new
end

--- Once per book: `configurable.font_size` (what the book kept, or the global
--- default) set to this screen's default when it's an old default.
--- `config`: the book's settings. Returns the new size or nil.
function M.checkBook(configurable, config, dev)
    if not (configurable and config) or not M.bigScreen(dev) then return nil end
    if config:isTrue(M.BOOK_DONE) then return nil end
    config:saveSetting(M.BOOK_DONE, true)
    if not M.isOldDefault(configurable.font_size) then return nil end
    configurable.font_size = M.defaultSize(dev)
    return configurable.font_size
end

--- Wrap ReaderFont:onReadSettings (once): the book's size checked before
--- KOReader hands it to the document.
function M.install(ReaderFont)
    ReaderFont = ReaderFont or require("apps/reader/modules/readerfont")
    if ReaderFont._gz_book_font then return false end
    ReaderFont._gz_book_font = true
    local orig = ReaderFont.onReadSettings
    ReaderFont.onReadSettings = function(self, config, ...)
        pcall(M.checkBook, self.configurable, config) -- (ReaderFont is only in EPUB-like books)
        return orig(self, config, ...)
    end
    pcall(M.migrateGlobal)
    return true
end

return M
