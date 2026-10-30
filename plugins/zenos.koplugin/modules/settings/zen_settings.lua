local _ = require("gettext")
local UIManager = require("ui/uimanager")

local settings_apply = require("modules/settings/zen_settings_apply")
local updater        = require("modules/settings/zen_updater")
local icons          = require("common/inline_icon_map")
local plugin_root    = require("common/plugin_root")
local IconItem       = require("common/ui/icon_menu_item")
local utils          = require("modules/settings/zen_settings_utils")

local lib_section      = require("modules/settings/sections/library_settings")
local home_section = require("modules/settings/sections/library_settings/home_settings")
local interface_section = require("modules/settings/sections/interface_settings")
local reader_section   = require("modules/settings/sections/reader_settings")
local extras_section   = require("modules/settings/sections/extras_settings")
local general_section  = require("modules/settings/sections/general_settings")
local about_section    = require("modules/settings/sections/about_settings")
local shutdown         = require("common/shutdown")

local M = {}

IconItem.installMenuPatch()

-- GZreader: its Grimmory plugin instance (reader or file manager), or nil.
local function gzreader()
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local ok, cls = pcall(require, mod)
        local inst = ok and type(cls) == "table" and cls.instance
        if type(inst) == "table" and type(inst.gzreader) == "table" then return inst.gzreader end
    end
end

-- GZreader: its settings for a section ("general", "reader", "interface").
local function gz_section(name)
    local g = gzreader()
    if not (g and type(g.sectionItems) == "function") then return {} end
    local ok, items = pcall(g.sectionItems, g, name)
    return ok and type(items) == "table" and items or {}
end

local function index_of(items, text)
    for i, item in ipairs(items) do
        if item.text == text then return i end
    end
end

function M.build(plugin)
    -- Initialize updater banner state; release metadata stays live-only.
    updater.init_banner()
    if settings_apply.set_plugin then
        settings_apply.set_plugin(plugin)
    end

    local config = plugin.config

    local function apply_feature(feature)
        local enabled = config.features[feature] == true
        settings_apply.apply_feature_toggle(plugin, feature, enabled)
    end

    local function save_and_apply(feature)
        plugin:saveConfig()
        apply_feature(feature)
    end

    local ctx = {
        plugin         = plugin,
        config         = config,
        save_and_apply = save_and_apply,
        apply_feature  = apply_feature,
        settings_apply = settings_apply,
    }

    local filebrowser_items    = lib_section.build(ctx)
    local home_item       = home_section.build(ctx)
    local reader_items         = reader_section.build(ctx)
    local extras_items      = extras_section.build(ctx)
    local about_items     = about_section.build(ctx)
    local general_items   = general_section.build(ctx, extras_items)

    -- GZreader: Wi-Fi only when needed under Wi-Fi; diagnostics (logging,
    -- remote debugging, usage statistics, sending the log) before Advanced;
    -- read aloud and the audiobook test at the end of Reader.
    local gz_general = gz_section("general")
    if gz_general.wifi then
        table.insert(general_items, (index_of(general_items, _("Wi-Fi")) or 0) + 1, gz_general.wifi)
    end
    if type(gz_general.diagnostics) == "table" and #gz_general.diagnostics > 0 then
        local at = index_of(general_items, _("Advanced")) or (#general_items + 1)
        general_items[at - 1].separator = true
        for i, item in ipairs(gz_general.diagnostics) do
            table.insert(general_items, at + i - 1, item)
        end
        gz_general.diagnostics[#gz_general.diagnostics].separator = true
    end
    local gz_reader = gz_section("reader")
    if #gz_reader > 0 then
        reader_items[#reader_items].separator = true
        for _i, item in ipairs(gz_reader) do reader_items[#reader_items + 1] = item end
    end

    extras_items = utils.order_items_by_text(extras_items, {
        _("Install ZenPM"),
        _("Open ZenPM"),
        _("Zen OPDS"),
        _("Zen Search"),
        _("Zen Keyboard"),
        _("Stats"),
        _("Rakuyomi"),
    })

    home_item.text = _("Home")
    IconItem.decorate(home_item, icons.settings_home)
    local interface_item = interface_section.build(ctx, extras_items)
    local gz_interface = gz_section("interface")
    if #gz_interface > 0 and type(interface_item.sub_item_table) == "table" then
        local list = interface_item.sub_item_table
        list[#list].separator = true
        for _i, item in ipairs(gz_interface) do list[#list + 1] = item end
    end

    local library_item = IconItem.decorate({
        text = _("Library"),
        sub_item_table = filebrowser_items,
        _zen_settings_root = "library",
    }, icons.settings_library)

    local root_items = {
        home_item,
        library_item,
        IconItem.decorate({ text = _("Reader"), sub_item_table = reader_items }, icons.settings_reader),
        interface_item,
        IconItem.decorate({ text = _("Extras"), sub_item_table = extras_items }, icons.fav_add),
        IconItem.decorate({ text = _("General"), sub_item_table = general_items }, icons.settings),
        -- GZreader: Connections: the Grimmory plugin's settings (connection,
        -- sync, audiobooks; also under KOReader → Tools → Grimmory) and
        -- Memos (the Notes tab: connection, synced tags, storage, limits).
        IconItem.decorate({
            text = _("Connections"),
            _zen_settings_root = "gzreader",
            sub_item_table = {
                IconItem.decorate({
                    text = _("Grimmory"),
                    sub_item_table_func = function()
                        local g = gzreader()
                        if g and type(g.menuItems) == "function" then return g:menuItems() end
                        return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                    end,
                }, icons.sync),
                IconItem.decorate({
                    text = _("Memos (Notes)"),
                    sub_item_table_func = function()
                        local g = gzreader()
                        if g and type(g.notesSettingsItems) == "function" then return g:notesSettingsItems() end
                        return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                    end,
                }, icons.edit),
            },
        }, icons.connect),
        {
            text = _("KOReader"),
            icon_file = plugin_root .. "/icons/koreader.png",
            _zen_settings_root = "koreader",
            sub_item_table_func = function()
                local items = require("modules/menu/app_launcher/native_menu").settingsItems("active")
                table.insert(items, IconItem.decorate({
                    text = _("Quit KOReader"),
                    keep_menu_open = true,
                    callback = function()
                        UIManager:show(require("ui/widget/confirmbox"):new{
                            text = _("Are you sure you want to quit KOReader?"),
                            ok_text = _("Quit"),
                            ok_callback = function()
                                shutdown.broadcastExit(plugin)
                            end,
                        })
                    end,
                }, icons.delete))
                return items
            end,
        },
        IconItem.decorate({ text = _("About"), sub_item_table = about_items }, icons.settings_about),
    }

    root_items._zen_header_action_func = function()
        return updater.build_update_available_action(plugin)
    end

    -- fires when navigating back from a submenu (e.g. About after manual check).
    root_items.needs_refresh = true
    root_items.refresh_func  = function()
        return M.build(plugin).sub_item_table
    end

    return {
        text = _("ZenOS"),
        sub_item_table = root_items,
    }
end

return M
