-- GZreader: the flash settings of GZreader and ZenOS, shown in Settings →
-- General → Screen → E-ink settings after KOReader's Full refresh rate
-- (common/gz_settings.lua screenItem; until 1.28.3 they were General →
-- Screen refresh):
--   Flash on every page turn       (the Kindles' page turns; gzreader_eink)
--   Flash when the screen changes  (Kindles without REAGL only; gzreader_eink)
--   Partial pages refresh          (ZenOS: a library page that isn't full)
-- ZenOS's "Flash on every CBZ page turn" isn't offered: KOReader's "Always
-- flash on pages with images" covers comics too (reader_flash_cbz.lua).
-- Receives ctx: { plugin, config, ... } as the other sections do.

local _ = require("gettext")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local items = {}
    local ok_eink, Eink = pcall(require, "gzreader_eink")
    if not ok_eink or type(Eink) ~= "table" then Eink = nil end

    -- every page turn flashes the screen clean (on by default on the Kindles
    -- without REAGL: Kindle 2, DX, 3, 4)
    if Eink and Eink.flashPageTurns then
        items[#items + 1] = IconItem.decorate({
            text = _("Flash on every page turn"),
            help_text = _("Every page turn flashes the screen clean, as the Kindle's own reader does: no grey trace of the last pages. Off: a flash every 6 pages, quicker turns. On by default on the Kindle 2, DX, 3 and 4. Replaces a Full refresh rate chosen above (or in a book's menu)."),
            checked_func = function() return Eink.pageTurnsTicked() end,
            callback = function() Eink.setFlashPageTurns(not Eink.pageTurnsTicked()) end,
        }, icons.reader_flash_cbz)
    end

    -- Kindles without REAGL (Kindle 3 …): flash on screen changes
    if Eink and Eink.applies and Eink.applies() then
        items[#items + 1] = IconItem.decorate({
            text = _("Flash when the screen changes"),
            help_text = _("Less ghosting: switching tabs and opening or closing a menu or a book flash the screen clean. Off: quicker, but a grey trace of the last screen stays until the next flash. Page turns: Flash on every page turn, above."),
            checked_func = function() return Eink.enabled() end,
            callback = function() Eink.setEnabled(not Eink.enabled()) end,
        }, icons.refresh)
    end

    items[#items + 1] = IconItem.decorate({
        text = _("Partial pages refresh"),
        help_text = _("Flash the screen in the library when a page is not full of books to prevent ghosting."),
        checked_func = function()
            return config.features.partial_page_repaint == true
        end,
        callback = function()
            config.features.partial_page_repaint = config.features.partial_page_repaint ~= true
            plugin:saveConfig()
        end,
    }, icons.refresh)

    return items
end

return M
