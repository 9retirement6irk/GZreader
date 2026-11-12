-- settings/sections/advanced.lua
-- Advanced / developer settings items for ZenOS.
-- Receives ctx: { plugin, config, save_and_apply, settings_apply }

local _ = require("gettext")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local settings_apply = ctx.settings_apply

    local items = {}

    -- GZreader: no Extract metadata (CoverBrowser reads a book's details and
    -- cover by itself when it shows the book; GZreader's Catalog has its own)
    -- and no Show hidden files (config/manager.lua turns a saved tick off once):
    -- the owner's call, 2026-11-11.

    -- GZreader: Partial pages refresh and GZreader's Flash when the screen
    -- changes (gzreader_eink, the Kindles without REAGL) are in General →
    -- Screen → E-ink settings (sections/gz_screen_refresh.lua).

    table.insert(items, {
        text = _("Allow dragging reader modals"),
        help_text = _("Restore KOReader's default draggable modal behavior."),
        checked_func = function()
            return type(config.developer) == "table"
                and config.developer.allow_modal_drag == true
        end,
        callback = function()
            if type(config.developer) ~= "table" then config.developer = {} end
            config.developer.allow_modal_drag = config.developer.allow_modal_drag ~= true
            plugin:saveConfig()
            settings_apply.prompt_restart()
        end,
    })

    -- GZreader: no Debug logging (KOReader's verbose log; GZreader's own
    -- diagnostic log is at the top of this menu), no Clear all gestures (the
    -- gestures plugin isn't in GZreader, nothing reads gestures.lua), no
    -- Plugin management or Patch management (turning off gzreader, zenos or
    -- coverbrowser breaks GZreader; patches are untested code).

    return items
end

return M
