local _ = require("gettext")
local UIManager = require("ui/uimanager")

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

-- GZreader: a list from `n` entries some of which may be nil (left out).
local function compact(t, n)
    local out = {}
    for i = 1, n do if t[i] ~= nil then out[#out + 1] = t[i] end end
    return out
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

    -- GZreader: Wi-Fi is a menu (On, Off, Auto, then ZenOS's network list:
    -- gz_settings.wifiItem) in place of ZenOS's switch; usage statistics before
    -- Advanced, and the diagnostic log's items (logging, sending, saving) at
    -- the top of Advanced (gz_settings.splitDiagnostics);
    -- read aloud and the audiobook test at the end of Reader.
    local gz_general = gz_section("general")
    if gz_general.wifi then
        local at = index_of(general_items, _("Wi-Fi"))
        local item = require("common/gz_settings").wifiItem(gz_general.wifi, at and general_items[at])
        if at then general_items[at] = item else table.insert(general_items, 1, item) end
    end
    if type(gz_general.diagnostics) == "table" and #gz_general.diagnostics > 0 then
        local stay, advanced = require("common/gz_settings").splitDiagnostics(gz_general.diagnostics)
        local at = index_of(general_items, _("Advanced"))
        local adv = at and general_items[at].sub_item_table
        if type(adv) ~= "table" then stay, advanced = gz_general.diagnostics, {} end
        at = at or (#general_items + 1)
        if #stay > 0 then
            general_items[at - 1].separator = true
            for i, item in ipairs(stay) do table.insert(general_items, at + i - 1, item) end
            stay[#stay].separator = true
        end
        if #advanced > 0 then
            for i, item in ipairs(advanced) do table.insert(adv, i, item) end
            advanced[#advanced].separator = true
        end
    end
    local gz_reader = gz_section("reader")
    -- GZreader: read aloud, the audiobook test and the headphone jack are for
    -- music and audiobooks too: General → Audio, before Time and date
    -- (gz_settings.splitAudio); anything else of GZreader's stays in Reader.
    local gz_audio, gz_rest = require("common/gz_settings").splitAudio(gz_reader)
    if type(gz_audio) == "table" and type(gz_rest) == "table" then gz_reader = gz_rest else gz_audio = {} end
    if #gz_audio > 0 then
        local at = index_of(general_items, _("Time and date")) or index_of(general_items, _("Advanced"))
        table.insert(general_items, at or (#general_items + 1), {
            text = _("Audio"),
            icon_file = require("common/utils").resolveLocalIcon(plugin_root .. "/icons/", "tab_music"),
            sub_item_table = gz_audio,
        })
    end
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

    -- GZreader: the section is named Downloads, like the tab it sets up
    local library_item = IconItem.decorate({
        text = _("Downloads"),
        sub_item_table = filebrowser_items,
        _zen_settings_root = "library",
    }, icons.settings_library)
    library_item.icon_name = "tab_downloaded" -- GZreader: the Downloads tab's own icon

    local root_items = {
        home_item,
        library_item,
        IconItem.decorate({ text = _("Reader"), sub_item_table = reader_items }, icons.settings_reader),
        interface_item,
        -- GZreader: no Extras section. General takes its Schedules and Sleep
        -- and Interface its Custom icons (above); the rest (Stats tab widgets,
        -- ZenPM, Rakuyomi, Zen Search, Lockdown mode, Zen Keyboard) stays at
        -- its saved value or default, with nothing to set.
        IconItem.decorate({ text = _("General"), sub_item_table = general_items }, icons.settings),
        -- GZreader: Storage (what's on the Kindle) is in General → Storage
        -- GZreader: Connections: the Grimmory plugin's settings (connection,
        -- sync, audiobooks; KOReader → Tools → Grimmory is left out) and
        -- Memos (the Notes tab: connection, synced tags, storage, limits).
        IconItem.decorate({
            text = _("Connections"),
            _zen_settings_root = "gzreader",
            sub_item_table = compact({
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
                IconItem.decorate({
                    text = _("Calendar (CalDAV)"),
                    sub_item_table_func = function()
                        local g = gzreader()
                        if g and type(g.calendarSettingsItems) == "function" then return g:calendarSettingsItems() end
                        return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                    end,
                }, icons.calendar),
                -- GZreader: Plex (the Music tab), on the Kindles with a speaker or jack
                (function()
                    local okt, Touch = pcall(require, "gzreader_touch")
                    if not (okt and Touch.audio and Touch.audio()) then return nil end
                    return {
                        text = _("Plex (Music)"),
                        icon_file = require("common/utils").resolveLocalIcon(plugin_root .. "/icons/", "tab_music"),
                        sub_item_table_func = function()
                            local g = gzreader()
                            if g and type(g.plexSettingsItems) == "function" then return g:plexSettingsItems() end
                            return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                        end,
                    }
                end)(),
                -- GZreader: copy connections between two GZreader devices
                IconItem.decorate({
                    text = _("Copy to or from another GZreader"),
                    sub_item_table_func = function()
                        local g = gzreader()
                        if g and type(g.copyItems) == "function" then return g:copyItems() end
                        return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                    end,
                }, icons.connect),
                -- GZreader: syncing through a computer (the Kindles without Wi-Fi; any Kindle can choose it)
                IconItem.decorate({
                    text = _("Sync through a computer"),
                    sub_item_table_func = function()
                        local g = gzreader()
                        if g and type(g.usbSyncItems) == "function" then return g:usbSyncItems() end
                        return { { text = _("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
                    end,
                }, icons.sync),
            }, 6),
        }, icons.connect),
        {
            text = _("KOReader"),
            icon_file = plugin_root .. "/icons/koreader.png",
            _zen_settings_root = "koreader",
            sub_item_table_func = function()
                local items = require("modules/menu/app_launcher/native_menu").settingsItems("active")
                table.insert(items, IconItem.decorate({
                    text = _("Quit KOReader"),
                    icon_name = "close",
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
