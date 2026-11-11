-- GZreader: Settings → General → Screen refresh. Every setting about when the
-- e-ink screen flashes clean, in one place (they were in Reader → Appearance
-- and General → Advanced):
--   Flash on every page turn       (the Kindles' page turns; gzreader_eink)
--   Flash on every CBZ page turn   (ZenOS: comics)
--   Flash when the screen changes  (Kindles without REAGL only; gzreader_eink)
--   Partial pages refresh          (ZenOS: a library page that isn't full)
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
            help_text = _("Every page turn flashes the screen clean, as the Kindle's own reader does: no grey trace of the last pages. Off: a flash every 6 pages, quicker turns. On by default on the Kindle 2, DX, 3 and 4. Replaces a full refresh rate chosen in a book's menu (Screen → E-ink settings)."),
            checked_func = function() return Eink.pageTurnsTicked() end,
            callback = function() Eink.setFlashPageTurns(not Eink.pageTurnsTicked()) end,
        }, icons.reader_flash_cbz)
    end

    items[#items + 1] = IconItem.decorate({
        text = _("Flash on every CBZ page turn"),
        checked_func = function()
            return config.features.reader_flash_cbz == true
        end,
        callback = function()
            config.features.reader_flash_cbz = config.features.reader_flash_cbz ~= true
            plugin:saveConfig()
        end,
    }, icons.reader_flash_cbz)

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
