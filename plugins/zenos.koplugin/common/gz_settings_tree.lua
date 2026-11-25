-- GZreader: Settings' first page and its sections, arranged as iOS and macOS
-- arrange theirs (claude/settings-reorg-proposal.md, owner 2026-11-17):
--
--   Wi-Fi                                              ─ what's switched most
--   General (About first, as on iOS) · Display and light · Sleep and wallpaper
--   Audio (Bluetooth first: a Kindle's Bluetooth is for sound)
--   Home and tabs · Reader
--   Accounts and services (the Grimmory account first, in Books)
--   Privacy and diagnostics
--
-- At most nine rows, so the first page fits on one screen on every Kindle
-- (a Settings page shows nine rows).
--
-- ZenOS's section modules still build their rows (zen_settings.lua); this
-- moves them, by their text, to where they go. A row that isn't named here
-- stays with the rest of its old section's rows, so nothing an upstream
-- ZenOS adds gets lost: General's go to General, Interface's to Display and
-- light, About's to General → About. Saved values never change: only where
-- a row is.
local M = {}

local function gettext() return require("gettext") end

--- An item's label: its text, or what its text_func says (nil if neither).
function M.textOf(item)
    if type(item) ~= "table" then return nil end
    local t = rawget(item, "text")
    if t == nil and type(rawget(item, "text_func")) == "function" then
        local ok, v = pcall(item.text_func)
        t = ok and v or nil
    end
    return type(t) == "string" and t or nil
end

--- Removes and returns the first row of `list` whose text is `text` (or for
--- which `text` (a function) is true).
function M.take(list, text)
    if type(list) ~= "table" then return nil end
    for i, item in ipairs(list) do
        local hit
        if type(text) == "function" then hit = text(item)
        else hit = type(item) == "table" and rawget(item, "text") == text end
        if hit then return table.remove(list, i) end
    end
end

--- The first row of `list` whose text is `text` (left in place).
function M.find(list, text)
    for _i, item in ipairs(type(list) == "table" and list or {}) do
        if type(item) == "table" and rawget(item, "text") == text then return item end
    end
end

--- A list of the non-nil values among `n` places.
local function compact(t, n)
    local out = {}
    for i = 1, n do if t[i] ~= nil then out[#out + 1] = t[i] end end
    return out
end
M.compact = compact

local function icon(item, glyph_name)
    local okI, IconItem = pcall(require, "common/ui/icon_menu_item")
    local okc, icons = pcall(require, "common/inline_icon_map")
    if okI and okc and type(icons) == "table" and icons[glyph_name] then return IconItem.decorate(item, icons[glyph_name]) end
    return item
end
M.icon = icon

local function iconFile(item, name, plugin_root)
    local ok, utils = pcall(require, "common/utils")
    if ok and type(utils.resolveLocalIcon) == "function" then
        item.icon_file = utils.resolveLocalIcon((plugin_root or "") .. "/icons/", name)
    end
    return item
end

-- a line under the last row of `list`
local function endGroup(list)
    if type(list) == "table" and list[#list] then list[#list].separator = true end
end

-- no line under the last row of a page (it only splits it from nothing)
local function noTrailingLine(list)
    if type(list) == "table" and list[#list] then list[#list].separator = nil end
    return list
end

--- A row opening one of GZreader's pages (`method` of its Grimmory plugin),
--- or saying it isn't loaded.
function M.gzPage(gzreader, method)
    return function()
        local g = gzreader and gzreader()
        if g and type(g[method]) == "function" then return g[method](g) end
        return { { text = gettext()("GZreader's Grimmory plugin isn't loaded."), enabled = false } }
    end
end

--- Settings → Accounts and services: one row per service, named for what it
--- does with the service it uses on the right (as iOS 18 puts every app's
--- settings behind one Apps row). `opts`: gzreader, plugin_root, audio (the
--- Kindle plays sound: Music and Audiobooks), wifi (House needs Wi-Fi).
function M.accountsItems(opts)
    local _ = gettext()
    local page = function(method) return M.gzPage(opts.gzreader, method) end
    local function row(text, service, method, glyph)
        return icon({ text = text, mandatory = service, sub_item_table_func = page(method) }, glyph)
    end
    local audiobooks
    if opts.audio then
        audiobooks = iconFile({
            text = _("Audiobooks"),
            help_text = _("Where the Catalog's audiobooks come from: Grimmory, or a library of your Plex server (Plex keeps audiobooks in a music library: an album per book, the author as its artist). Listening positions go to the same place. Choosing Plex needs a Plex sign-in: Accounts and services → Music."),
            -- (only with a Plex sign-in: otherwise they come from Grimmory)
            enabled_func = function()
                local g = opts.gzreader and opts.gzreader()
                return g ~= nil and type(g.store) == "table" and type(g.store.plex) == "table" and g.store.plex.token ~= nil
            end,
            mandatory_func = function()
                local ok, Tab = pcall(require, "gzreader_musictab")
                local g = opts.gzreader and opts.gzreader()
                if ok and g and type(Tab.audiobooksValue) == "function" then
                    local okv, v = pcall(Tab.audiobooksValue, g)
                    if okv and type(v) == "string" then return v end
                end
                return "Grimmory"
            end,
            keep_menu_open = true,
            callback = function(touchmenu)
                local ok, Tab = pcall(require, "gzreader_musictab")
                local g = opts.gzreader and opts.gzreader()
                if not (ok and g and type(Tab.chooseAudiobooks) == "function") then return end
                Tab.chooseAudiobooks(g, function()
                    if touchmenu and touchmenu.updateItems then pcall(touchmenu.updateItems, touchmenu) end
                end)
            end,
        }, "tab_audiobooks", opts.plugin_root)
    end
    return compact({
        row(_("Books"), "Grimmory", "menuItems", "sync"),
        audiobooks,
        opts.audio and iconFile({ text = _("Music"), mandatory = "Plex", sub_item_table_func = page("plexSettingsItems") },
            "tab_music", opts.plugin_root) or nil,
        row(_("Notes"), "Memos", "notesSettingsItems", "edit"),
        row(_("Calendar"), "CalDAV", "calendarSettingsItems", "calendar"),
        row(_("Photos"), "Immich", "immichSettingsItems", "wallpaper"),
        opts.wifi and iconFile({ text = _("House"), mandatory = "Home Assistant", sub_item_table_func = page("houseSettingsItems") },
            "tab_house", opts.plugin_root) or nil,
        -- GZreader: the daily paper (its feeds, fetched once a day; read on Home: the owner, 2026-11-18)
        row(_("Daily paper"), _("Feeds"), "dailySettingsItems", "history"),
    }, 8)
end

--- Software update's value: the version waiting, if one is known.
function M.updateValue(updater)
    if type(updater) ~= "table" then return nil end
    local ok, has = pcall(updater.has_update)
    if not (ok and has) then return nil end
    local okv, v = pcall(updater.latest_version)
    if okv and type(v) == "string" and v ~= "" then
        return require("ffi/util").template(gettext()("%1 available"), v)
    end
    return gettext()("Available")
end

--- The whole first page. `p`: the rows ZenOS's sections built —
---   general, interface (Interface's rows), about, reader (lists),
---   home (Home's item), library (the Downloads tab's rows),
---   gz = { general = { wifi, diagnostics }, reader, interface, performance, home },
---   gzreader (a function: GZreader's plugin or nil), updater, plugin_root,
---   koreader_item (About → Advanced → KOReader settings), reset_item (last in
---   Advanced), audio, wifi.
function M.build(p)
    local _ = gettext()
    local GzS = require("common/gz_settings")
    local general = p.general or {}
    local interface = p.interface or {}
    local about = p.about or {}
    local reader = p.reader or {}
    local gz = p.gz or {}
    local gz_general = gz.general or {}

    ---------------------------------------------------------------- out of General
    local zen_wifi = M.take(general, _("Wi-Fi"))
    local wifi = gz_general.wifi and GzS.wifiItem(gz_general.wifi, zen_wifi) or zen_wifi
    local bluetooth = M.take(general, _("Bluetooth"))
    local updates = M.take(general, _("Updates"))
    local schedules = M.take(general, _("Schedules"))
    local sleep = M.take(general, _("Sleep"))
    local screen = M.take(general, _("Screen"))
    local storage = M.take(general, _("Storage"))
    local battery = M.take(general, _("Battery"))
    local advanced = M.take(general, _("Advanced"))

    -- (About keeps only what it says: Setup Guide goes to General, Report a bug
    -- to Privacy and diagnostics)
    local setup = M.take(about, _("Setup Guide"))
    local report = M.take(about, _("Report a bug"))

    ---------------------------------------------------------------- Dark mode
    -- (it was in four places: General → Schedules, Reader → Appearance →
    -- Reader themes, Interface → Accent color, and the Invert with dark mode
    -- ticks of Interface → Wallpaper and Custom icons)
    local night_schedule = schedules and M.take(schedules.sub_item_table, _("Night mode schedule"))
    local reader_appearance = M.find(reader, _("Appearance"))
    local themes = reader_appearance and M.take(reader_appearance.sub_item_table, _("Reader themes"))
    local accent = M.find(interface, _("Accent color"))
    local night_accent = accent and M.take(accent.sub_item_table, function(item)
        local t = M.textOf(item)
        return t ~= nil and t:find(_("Night mode accent"), 1, true) == 1
    end)
    -- (shown where Accent color is: not on a Kindle that can't show colour)
    if night_accent and accent.show_func then night_accent.show_func = accent.show_func end
    local wallpaper = M.take(interface, _("Wallpaper"))
    local wallpaper_invert = wallpaper and M.take(wallpaper.sub_item_table, _("Invert with dark mode"))
    if wallpaper_invert then wallpaper_invert.text = _("Invert the Home background") end
    local custom_icons = M.find(interface, _("Custom icons"))
    local icons_invert = custom_icons and M.take(custom_icons.sub_item_table, _("Invert with dark mode"))
    if icons_invert then icons_invert.text = _("Invert custom icons") end
    local dark = compact({ night_schedule, themes, night_accent, wallpaper_invert, icons_invert }, 5)
    local dark_item = #dark > 0 and icon({
        text = _("Dark mode"),
        help_text = _("Everything about dark mode in one place: when it turns on by itself, how books look in it, and what else follows it."),
        sub_item_table = noTrailingLine(dark),
    }, "schedule_night") or nil

    ---------------------------------------------------------------- Home and tabs
    local home = p.home
    local home_rows = type(home) == "table" and home.sub_item_table or nil
    -- (GZreader's rows for Home, the daily paper: after Home's own)
    if home_rows then for _i, item in ipairs(gz.home or {}) do home_rows[#home_rows + 1] = item end end
    local home_status = M.take(home_rows, _("Show top status bar"))
    noTrailingLine(home_rows)
    local status = M.take(interface, _("Status bar"))
    if home_status then
        home_status.text = _("Show on Home")
        if status and type(status.sub_item_table) == "table" then
            home_status.separator = true
            table.insert(status.sub_item_table, 1, home_status)
        elseif home_rows then
            home_rows[#home_rows + 1] = home_status
        end
    end
    local navbar = M.take(interface, _("Navbar"))
    if navbar then navbar.text = _("Tab bar") end
    local quick = M.take(interface, _("Quick panel"))
    local library = type(p.library) == "table" and #p.library > 0 and icon({
        text = _("Downloads tab"),
        help_text = _("How the Downloads tab (and the other lists of books on this device) shows books and folders."),
        sub_item_table = p.library,
    }, "settings_library") or nil
    if type(home) == "table" then home.text = _("Home") end
    local home_tabs = compact({ home, status, navbar, quick, library }, 5)

    ---------------------------------------------------------------- Performance
    local performance = {}
    for _i, item in ipairs(gz.performance or {}) do performance[#performance + 1] = item end

    ---------------------------------------------------------------- General
    if updates then
        updates.text = _("Software update")
        updates.mandatory_func = function() return M.updateValue(p.updater) end
    end
    -- (About first, as iOS has it: General → About; only what it says)
    local about_item = #about > 0 and icon({ text = _("About"), _zen_settings_root = "about", sub_item_table = about }, "settings_about") or nil
    local general_out = compact({ about_item, updates, storage, battery }, 4)
    for _i, item in ipairs(general) do general_out[#general_out + 1] = item end -- Time and date, Language, …
    endGroup(general_out)
    local transfer = icon({
        text = _("Transfer"),
        help_text = _("Copy your connections to or from another GZreader, or sync through a computer instead of Wi-Fi."),
        sub_item_table = {
            icon({ text = _("Copy to or from another GZreader"), sub_item_table_func = M.gzPage(p.gzreader, "copyItems") }, "connect"),
            icon({ text = _("Sync through a computer"), sub_item_table_func = M.gzPage(p.gzreader, "usbSyncItems") }, "sync"),
        },
    }, "connect")
    general_out[#general_out + 1] = transfer
    if setup then general_out[#general_out + 1] = setup end
    if #performance > 0 then
        general_out[#general_out + 1] = icon({
            text = _("Performance"),
            help_text = _("Work GZreader does ahead of time or keeps ready, so books, covers and servers come up faster."),
            sub_item_table = performance,
        }, "settings_advanced")
    end

    ---------------------------------------------------------------- Display and light
    if schedules then schedules.text = _("Brightness and warmth") end
    local display = compact({ screen, schedules, dark_item }, 3)
    endGroup(display)
    local font = M.take(interface, _("Font"))
    if font then display[#display + 1] = font end
    for _i, item in ipairs(interface) do display[#display + 1] = item end -- size of menus, Accent color, Custom icons, Blur…
    for _i, item in ipairs(gz.interface or {}) do display[#display + 1] = item end -- (Nook) Colour screen, Touch orientation

    ---------------------------------------------------------------- Sleep and wallpaper
    if wallpaper then wallpaper.text = _("Home background") end
    local photos = p.wifi and icon({
        text = _("Pictures from Immich"),
        help_text = _("The Immich album the sleep screen and the Home background can show pictures from (the same as Accounts and services → Photos)."),
        sub_item_table_func = M.gzPage(p.gzreader, "immichSettingsItems"),
    }, "wallpaper") or nil
    local sleep_wallpaper = compact({ sleep, wallpaper, photos }, 3)

    ---------------------------------------------------------------- Audio
    local audio_rows, reader_rest = GzS.splitAudio(gz.reader or {})

    ---------------------------------------------------------------- Reader
    for _i, item in ipairs(reader_rest or {}) do reader[#reader + 1] = item end

    ---------------------------------------------------------------- Privacy and diagnostics
    local privacy = {}
    local diagnostics = gz_general.diagnostics
    if type(diagnostics) == "table" and #diagnostics > 0 then
        -- (GZreader's own Report a problem sends what About's Report a bug did)
        for _i, item in ipairs(diagnostics) do privacy[#privacy + 1] = item end
    elseif report then
        report.text = _("Report a problem")
        privacy[#privacy + 1] = report
    end
    if advanced then
        if type(advanced.sub_item_table) == "table" and p.koreader_item then
            table.insert(advanced.sub_item_table, p.koreader_item)
        end
        -- (and last, Reset GZreader: gzreader_reset.lua)
        if type(advanced.sub_item_table) == "table" and p.reset_item then
            local list = advanced.sub_item_table
            if list[#list] then list[#list].separator = true end
            list[#list + 1] = p.reset_item
        end
        endGroup(privacy)
        privacy[#privacy + 1] = advanced
    end

    ---------------------------------------------------------------- the first page
    local function section(key, text, rows, glyph, extra)
        if type(rows) ~= "table" or #rows == 0 then return nil end
        local item = { text = text, _zen_settings_root = key, sub_item_table = noTrailingLine(rows) }
        for k, v in pairs(extra or {}) do item[k] = v end
        return icon(item, glyph)
    end
    if wifi then wifi._zen_settings_root = "wifi" end
    if bluetooth then bluetooth._zen_settings_root = "bluetooth" end
    -- Bluetooth: first in Audio (a Kindle's Bluetooth is for headphones and
    -- speakers), on the first page only on a Kindle with nothing else for Audio
    local audio_list = type(audio_rows) == "table" and audio_rows or {}
    if bluetooth and #audio_list > 0 then
        bluetooth.separator = true
        table.insert(audio_list, 1, bluetooth)
        bluetooth = nil
    end
    local function audioSection()
        if #audio_list == 0 then return nil end
        return iconFile({ text = _("Audio"), _zen_settings_root = "audio", sub_item_table = audio_list }, "tab_music", p.plugin_root)
    end

    local groups = {
        { wifi, bluetooth },
        { section("general", _("General"), general_out, "settings"),
          section("display", _("Display and light"), display, "display"),
          section("sleep", _("Sleep and wallpaper"), sleep_wallpaper, "settings_sleep"),
          audioSection() },
        { section("home", _("Home and tabs"), home_tabs, "settings_home"),
          section("reader", _("Reader"), reader, "settings_reader") },
        { section("accounts", _("Accounts and services"), M.accountsItems(p), "connect") },
        { section("privacy", _("Privacy and diagnostics"), privacy, "settings_bug") },
    }
    local root = {}
    for _gi, g in ipairs(groups) do
        local added = false
        for i = 1, 4 do
            if g[i] then root[#root + 1] = g[i]; added = true end
        end
        if added then root[#root].separator = true end
    end
    noTrailingLine(root)
    return root
end

-- GZreader: the AI connection's row in Accounts and services, after Notes (one
-- key for handwriting to text, the daily paper's AI edition and what comes
-- next: the owner, 2026-11-24). Not on the Kindles without Wi-Fi. Added here,
-- not in the list above, so that list's own lines stay as they are.
local accountsBeforeAI = M.accountsItems
function M.accountsItems(opts)
    local items = accountsBeforeAI(opts)
    if not opts.wifi then return items end
    local _ = gettext()
    local row = icon({ text = _("AI"), mandatory_func = function()
        local ok, AI = pcall(require, "gzreader_ai")
        local g = opts.gzreader and opts.gzreader()
        return ok and g and AI.name(AI.provider(g)) or ""
    end, sub_item_table_func = M.gzPage(opts.gzreader, "aiSettingsItems") }, "connect")
    local at = #items + 1
    for i, it in ipairs(items) do
        if it.text == _("Notes") then at = i + 1 end
    end
    table.insert(items, at, row)
    return items
end

return M
