--[[--
Add-ons: plugins and other extras from outside GZreader, and ZenPM (ZenLabs'
package manager, github.com/xZenLabs/zen-pm, GPL-3.0) to install them with.

Settings → General → Add-ons:
- Install ZenPM (ZenOS's own installer: the plugin from ZenPM's latest GitHub
  release, its SHA-256 checked), then Open ZenPM. Once ZenPM is there it gets
  a tile on the quick panel (Your tiles: gzreader_panelcustom.lua), once.
- What works and what to leave alone.

What to leave alone, and the guard for it: ZenPM lists every plugin folder it
finds and matches it to its catalogue by name, so it sees GZreader's ZenOS
(plugins/zenos.koplugin) as its "Zen UI" package and offers to update it. That
update would be ZenLabs' ZenOS, without GZreader's changes: Home, the tabs and
Settings would be theirs, and GZreader's screens that live in it gone.
GZreader's copy carries a file (zenos.koplugin/GZREADER); at each start
`Addons.check` looks for it, and when it's gone says so and offers to put
GZreader's parts back (the updater, installing this version again).
(KOReader's own bundled plugins, the cover browser and statistics among them,
ZenPM leaves alone.)
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Addons = {
    MARKER = "GZREADER",
    TILE_FLAG = "gzreader_zenpm_tile_added",
}

local function pluginsDir()
    local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
    return (here:match("^(.*)/[^/]+$")) or "plugins"
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

--- GZreader's own parts that aren't GZreader's any more ({ "ZenOS" }, or {}).
--- `dir`: the plugins folder (tests).
function Addons.replaced(dir)
    dir = dir or pluginsDir()
    local out = {}
    -- (replaced by another ZenOS, or taken away: ZenPM's Uninstall)
    if not exists(dir .. "/zenos.koplugin/main.lua") or not exists(dir .. "/zenos.koplugin/" .. Addons.MARKER) then
        out[#out + 1] = "ZenOS"
    end
    return out
end

--- GZreader's own plugins, by the folder names KOReader's "disabled plugins" setting uses.
Addons.OWN = { "zenos", "coverbrowser", "statistics", "autosuspend" }

--- Any of GZreader's own plugins switched off (ZenPM's Disable, KOReader's
--- plugin management): switched back on. Returns their names (a restart loads them).
function Addons.reenable()
    local s = rawget(_G, "G_reader_settings")
    local disabled = s and s:readSetting("plugins_disabled")
    if type(disabled) ~= "table" then return {} end
    local back = {}
    for _i, name in ipairs(Addons.OWN) do
        if disabled[name] then
            disabled[name] = nil
            back[#back + 1] = name
        end
    end
    if #back > 0 then
        s:saveSetting("plugins_disabled", disabled)
        pcall(function() s:flush() end)
    end
    return back
end

--- ZenPM's own list of what's installed (its SQLite file in KOReader's settings folder), or nil.
function Addons.zenpmDb()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok or not DataStorage then return nil end
    local path = DataStorage:getSettingsDir() .. "/ZenPM/state/zenpm.sqlite3"
    return exists(path) and path or nil
end

--- ZenPM's "Ignore updates" turned on for GZreader's ZenOS, in ZenPM's own
--- list: ZenPM then offers no update for it, and its Update all leaves it.
--- ZenPM keeps the flag when it scans the plugins again. (Nothing to set
--- until ZenPM has listed it, at its first opening: set at the start after.)
--- Returns how many rows it set, or nil and why. `path`: the list (tests).
function Addons.ignoreUpdates(path)
    path = path or Addons.zenpmDb()
    if not path or not exists(path) then return nil, "no ZenPM list" end -- (never made here)
    local WHICH = "(install_path LIKE '%/zenos.koplugin' OR id = 'zen-ui')"
    local ok, res = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path)
        local n = 0
        local okq, err = pcall(function()
            conn:exec("PRAGMA busy_timeout = 2000")
            n = tonumber(conn:rowexec("SELECT COUNT(*) FROM installed_packages WHERE " .. WHICH .. " AND update_ignored = 0")) or 0
            if n > 0 then
                conn:exec("UPDATE installed_packages SET update_ignored = 1, update_ignored_version = '' WHERE " .. WHICH)
            end
        end)
        conn:close()
        if not okq then error(err) end
        return n
    end)
    if ok then return res end
    return nil, tostring(res)
end

--- Is ZenPM's plugin loaded?
function Addons.zenpm()
    local ok, inst = pcall(function() return require("pluginloader"):getPluginInstance("zenpm") end)
    return ok and inst or nil
end

--- GZreader's own icon stays on question boxes. ZenPM's plugin wraps
--- IconWidget.init so that every "notice-question" icon (KOReader's ConfirmBox)
--- shows ZenPM's ZenOS logo, unless it sees the mark it leaves on IconWidget.
--- That mark is set here first (GZreader loads before ZenPM: it then wraps
--- nothing); if ZenPM got there first, its file is put back after it.
--- `dir`: the plugins folder (tests).
function Addons.keepIcon(dir)
    local IconWidget = require("ui/widget/iconwidget")
    if IconWidget.__gz_question_icon then return false end
    IconWidget.__gz_question_icon = true
    local theirs = IconWidget.__zenpm_confirmation_icon_patched
    IconWidget.__zenpm_confirmation_icon_patched = true
    if not theirs then return false end
    local own = (dir or pluginsDir() or "") .. "/zenos.koplugin/icons/zen_ui.svg"
    local init = IconWidget.init
    function IconWidget:init()
        init(self)
        if self.icon == "notice-question" then self.file = own end
    end
    return true
end

--- At start: GZreader's parts still its own (else: say so, offer to put them
--- back), and ZenPM's tile on the quick panel the first time ZenPM is there.
function Addons.check(plugin, dir)
    local Log = require("gzreader_log")
    -- (ZenPM's Disable on one of GZreader's own plugins: on again)
    local back = Addons.reenable()
    if #back > 0 then
        Log.warn("add-ons: GZreader's own plugins were switched off; on again:", table.concat(back, ", "))
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = T(_("A part of GZreader was switched off (%1), probably with Disable in ZenPM. GZreader needs it and has switched it back on.\n\nRestart now to load it?"), table.concat(back, ", ")),
            ok_text = _("Restart"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end
    -- (ZenPM offers no update for GZreader's ZenOS)
    local set, why = Addons.ignoreUpdates()
    if set and set > 0 then Log.info("add-ons: ZenPM's Ignore updates turned on for GZreader's ZenOS")
    elseif not set and why ~= "no ZenPM list" then Log.warn("add-ons: couldn't set ZenPM's Ignore updates:", tostring(why)) end
    local gone = Addons.replaced(dir)
    if #gone > 0 then
        Log.warn("add-ons: replaced by another installer:", table.concat(gone, ", "))
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = T(_("GZreader's own %1 was replaced or removed, probably from ZenPM (an update, a change of version or Uninstall). Home, the tabs and Settings won't work as GZreader's until it's put back.\n\nPut GZreader's parts back now? It downloads this version again; your settings, books and add-ons are kept."),
                table.concat(gone, ", ")),
            ok_text = _("Put back"),
            ok_callback = function() Addons.repair(plugin) end,
        })
        return gone
    end
    local s = rawget(_G, "G_reader_settings")
    if s and Addons.zenpm() and not s:isTrue(Addons.TILE_FLAG) then
        s:saveSetting(Addons.TILE_FLAG, true)
        local ok = require("gzreader_panelcustom").add({ kind = "plugin", key = "zenpm", method = "open", label = "ZenPM" })
        Log.info("add-ons: ZenPM is installed; its quick panel tile", ok and "added" or "not added")
    end
    return gone
end

--- This version's update, installed again (GZreader's plugin folders put back).
function Addons.repair(_plugin)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Update = require("gzreader_update")
    require("gzreader_net").run(function()
        local busy = InfoMessage:new{ text = _("Fetching GZreader…"), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local info, err = Update.check()
        UIManager:close(busy)
        if not info then
            UIManager:show(InfoMessage:new{ text = T(_("Couldn't fetch GZreader:\n%1"), tostring(err)) })
            return
        end
        require("gzreader_log").info("add-ons: putting GZreader's parts back with", tostring(info.version))
        Update.download(info)
    end, { reason = "putting GZreader's parts back" })
end

Addons.ABOUT = _([[ZenPM is ZenLabs' package manager for KOReader (not part of GZreader). With it you can add plugins, wallpapers and other extras.

What to know:
• Plugins you add are kept through GZreader's updates. Open one from the quick panel: Settings → Home and tabs → Quick panel → Your tiles → Add a plugin's screen.
• ZenPM lists GZreader's own ZenOS as one of its packages (it shows it as “GZreader”, by ZenLabs). Leave it alone: don't update it, change its version, disable or uninstall it. GZreader turns on ZenPM's “Ignore updates” for it by itself, switches it back on if it's disabled, and if it's replaced or removed says so at its next start and offers to put its own back.
• KOReader patches change KOReader's own code and can break GZreader's screens. If something stops working after adding one, remove it in ZenPM.
• Progress sync, OPDS and similar plugins do what GZreader already does with your book server; two of them syncing the same book can disagree.
• Icon packs change ZenOS's icons; GZreader's own screens keep theirs.]])

--- Settings → General → Add-ons.
function Addons.items(plugin)
    local UIManager = require("ui/uimanager")
    local rows = {}
    pcall(Addons.ignoreUpdates) -- (ZenPM may have listed GZreader's ZenOS since the start)
    local ok, Installer = pcall(require, "modules/settings/zenpm_installer")
    local zen = rawget(_G, "__ZEN_UI_PLUGIN")
    local item = ok and type(Installer) == "table" and Installer.build_item and Installer.build_item(zen) or nil
    if item and not Addons.zenpm() then
        -- (ZenOS's installer, after GZreader's own word on it)
        local install = item.callback
        item.help_text = _("Download and install ZenPM, ZenLabs' package manager, to add plugins and other extras. It isn't part of GZreader.")
        item.callback = function(touchmenu)
            UIManager:show(require("ui/widget/confirmbox"):new{
                text = Addons.ABOUT .. "\n\n" .. _("Install ZenPM?"),
                ok_text = _("Continue"),
                ok_callback = function() install(touchmenu) end,
            })
        end
    end
    if item then
        rows[#rows + 1] = item
    else
        rows[#rows + 1] = { text = _("ZenPM isn't available for this device."), enabled_func = function() return false end }
    end
    rows[#rows + 1] = {
        text = _("About add-ons"),
        keep_menu_open = true,
        callback = function() UIManager:show(require("ui/widget/infomessage"):new{ text = Addons.ABOUT }) end,
    }
    local gone = Addons.replaced()
    if #gone > 0 then
        rows[#rows + 1] = {
            text = T(_("Put GZreader's %1 back"), table.concat(gone, ", ")),
            keep_menu_open = true,
            callback = function() Addons.repair(plugin) end,
        }
    end
    return rows
end

return Addons
