local _ = require("gettext")

local settings_apply = require("modules/settings/zen_settings_apply")
local updater        = require("modules/settings/gz_updater") -- GZreader: not ZenOS's updater (gz_updater.lua)
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

    extras_items = utils.order_items_by_text(extras_items, {
        _("Install ZenPM"),
        _("Open ZenPM"),
        _("Zen OPDS"),
        _("Zen Search"),
        _("Zen Keyboard"),
        _("Stats"),
        _("Rakuyomi"),
    })
    IconItem.decorate(home_item, icons.settings_home)
    local interface_item = interface_section.build(ctx, extras_items)

    -- GZreader: the first page arranged as iOS and macOS arrange theirs
    -- (common/gz_settings_tree.lua; owner, 2026-11-17): the Grimmory account,
    -- Wi-Fi and Bluetooth, then General, Display and light, Sleep and
    -- wallpaper, Audio, Home and tabs, Reader, Accounts and services, Privacy
    -- and diagnostics, About. ZenOS's sections still build their rows; the
    -- tree moves them. No Extras section: General takes its Schedules and
    -- Sleep (general_settings.lua) and Interface its Custom icons; the rest
    -- (Stats tab widgets, ZenPM, Rakuyomi, Zen Search, Lockdown mode, Zen
    -- Keyboard) stays at its saved value or default, with nothing to set. No
    -- KOReader section: KOReader's whole menu is Privacy and diagnostics →
    -- Advanced → KOReader settings (gz_settings.koreaderMenuItem).
    local okt, Touch = pcall(require, "gzreader_touch")
    local okn, no_wifi = pcall(function() return require("gzreader_usbsync").noWifi() end)
    local root_items = require("common/gz_settings_tree").build({
        general = general_items,
        interface = type(interface_item.sub_item_table) == "table" and interface_item.sub_item_table or {},
        about = about_items,
        reader = reader_items,
        home = home_item,
        library = filebrowser_items,
        gz = {
            general = gz_section("general"),
            reader = gz_section("reader"),
            interface = gz_section("interface"),
            performance = gz_section("performance"),
        },
        gzreader = gzreader,
        updater = updater,
        plugin_root = plugin_root,
        koreader_item = require("common/gz_settings").koreaderMenuItem(plugin_root),
        -- (Music and Audiobooks: the Kindles with a speaker or jack; House:
        -- not on the Kindles without Wi-Fi, 2 and DX)
        audio = okt and type(Touch) == "table" and type(Touch.audio) == "function" and Touch.audio() and true or false,
        wifi = not (okn and no_wifi),
    })

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
