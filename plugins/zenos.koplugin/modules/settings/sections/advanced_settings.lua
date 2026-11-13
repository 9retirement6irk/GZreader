-- settings/sections/advanced.lua
-- Advanced / developer settings items for ZenOS.
-- Receives ctx: { plugin, config, save_and_apply, settings_apply }

local _ = require("gettext")

local M = {}

function M.build(_ctx)
    local items = {}

    -- GZreader: no Extract metadata (CoverBrowser reads a book's details and
    -- cover by itself when it shows the book; GZreader's Catalog has its own)
    -- and no Show hidden files (config/manager.lua turns a saved tick off once):
    -- the owner's call, 2026-11-11.

    -- GZreader: Partial pages refresh and GZreader's Flash when the screen
    -- changes (gzreader_eink, the Kindles without REAGL) are in General →
    -- Screen → E-ink settings (sections/gz_screen_refresh.lua).

    -- GZreader: no Allow dragging reader modals (ZenOS keeps KOReader's pop-up
    -- windows where they open; config/manager.lua turns a saved tick off once).
    -- At the end of this menu GZreader adds KOReader settings (zen_settings.lua,
    -- gz_settings.koreaderMenuItem); this menu itself is About → Advanced.

    -- GZreader: no Debug logging (KOReader's verbose log; GZreader's own
    -- diagnostic log is at the top of this menu), no Clear all gestures (the
    -- gestures plugin isn't in GZreader, nothing reads gestures.lua), no
    -- Plugin management or Patch management (turning off gzreader, zenos or
    -- coverbrowser breaks GZreader; patches are untested code).

    return items
end

return M
