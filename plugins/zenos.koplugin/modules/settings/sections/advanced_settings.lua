-- settings/sections/advanced.lua
-- Advanced / developer settings items for ZenOS.
-- Receives ctx: { plugin, config, save_and_apply, settings_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("modules/settings/zen_settings_utils")
local paths = require("common/paths")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local settings_apply = ctx.settings_apply

    local items = {}

    table.insert(items, {
        text = _("Extract metadata"),
        help_text = _("Extract and cache book metadata and cover images for books in the current directory. Requires CoverBrowser plugin."),
        callback = function()
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if not ok_bim or not BookInfoManager then return end
            local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
            local fc = ok_fm and FileManager and FileManager.instance
                and FileManager.instance.file_chooser
            if not fc then return end
            local Trapper = require("ui/trapper")
            Trapper:wrap(function()
                BookInfoManager:extractBooksInDirectory(fc.path, fc.cover_specs)
            end)
        end,
        keep_menu_open = true,
    })

    table.insert(items, {
        text = _("Partial pages refresh"),
        help_text = _("Flash the screen in the library when a page is not full of books to prevent ghosting."),
        checked_func = function()
            return config.features.partial_page_repaint == true
        end,
        callback = function()
            config.features.partial_page_repaint = config.features.partial_page_repaint ~= true
            plugin:saveConfig()
        end,
    })

    -- GZreader: Kindles without REAGL (Kindle 3 …): flash on screen changes
    local ok_eink, Eink = pcall(require, "gzreader_eink")
    if ok_eink and Eink.applies() then
        table.insert(items, {
            text = _("Flash when the screen changes"),
            help_text = _("Less ghosting: switching tabs and opening or closing a menu or a book flash the screen clean. Off: quicker, but a grey trace of the last screen stays until the next flash. Page turns: Settings → Reader → Appearance → Flash on every page turn."),
            checked_func = function() return Eink.enabled() end,
            callback = function() Eink.setEnabled(not Eink.enabled()) end,
        })
    end

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

    table.insert(items, {
        text = _("Show hidden files"),
        checked_func = function()
            return type(config.developer) == "table"
                and config.developer.show_hidden_outside_home == true
        end,
        callback = function()
            if type(config.developer) ~= "table" then
                config.developer = {}
            end
            local enabling = config.developer.show_hidden_outside_home ~= true
            config.developer.show_hidden_outside_home = enabling
            plugin:saveConfig()

            if enabling then
                local current_dir = utils.get_current_dir()
                local is_outside_home = not paths.isInHomeDir(current_dir)
                G_reader_settings:saveSetting("show_hidden", is_outside_home)
                G_reader_settings:saveSetting("show_unsupported", is_outside_home)
            else
                G_reader_settings:saveSetting("show_hidden", false)
                G_reader_settings:saveSetting("show_unsupported", false)
                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                local fm = ok and FileManager and FileManager.instance
                if fm and fm.file_chooser then
                    fm.file_chooser.show_hidden = false
                    fm.file_chooser.show_unsupported = false
                    fm.file_chooser:refreshPath()
                end
            end

            UIManager:nextTick(function()
                settings_apply.prompt_restart()
            end)
        end,
        keep_menu_open = true,
    })

    -- GZreader: no Debug logging (KOReader's verbose log; GZreader's own
    -- diagnostic log is at the top of this menu), no Clear all gestures (the
    -- gestures plugin isn't in GZreader, nothing reads gestures.lua), no
    -- Plugin management or Patch management (turning off gzreader, zenos or
    -- coverbrowser breaks GZreader; patches are untested code).

    return items
end

return M
