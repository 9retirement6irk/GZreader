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
    -- (only when the folder is there at all: without it GZreader doesn't start, and that's another matter)
    if exists(dir .. "/zenos.koplugin/main.lua") and not exists(dir .. "/zenos.koplugin/" .. Addons.MARKER) then
        out[#out + 1] = "ZenOS"
    end
    return out
end

--- Is ZenPM's plugin loaded?
function Addons.zenpm()
    local ok, inst = pcall(function() return require("pluginloader"):getPluginInstance("zenpm") end)
    return ok and inst or nil
end

--- At start: GZreader's parts still its own (else: say so, offer to put them
--- back), and ZenPM's tile on the quick panel the first time ZenPM is there.
function Addons.check(plugin, dir)
    local Log = require("gzreader_log")
    local gone = Addons.replaced(dir)
    if #gone > 0 then
        Log.warn("add-ons: replaced by another installer:", table.concat(gone, ", "))
        local UIManager = require("ui/uimanager")
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = T(_("GZreader's own %1 was replaced, probably by an update from ZenPM. Home, the tabs and Settings won't work as GZreader's until it's put back.\n\nPut GZreader's parts back now? It downloads this version again; your settings, books and add-ons are kept."),
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
• Don't install or update “Zen UI” (ZenOS) from ZenPM. GZreader has its own copy with its own changes; ZenPM's would replace it. If that happens, GZreader says so at its next start and offers to put its own back.
• KOReader patches change KOReader's own code and can break GZreader's screens. If something stops working after adding one, remove it in ZenPM.
• Progress sync, OPDS and similar plugins do what GZreader already does with your book server; two of them syncing the same book can disagree.
• Icon packs change ZenOS's icons; GZreader's own screens keep theirs.]])

--- Settings → General → Add-ons.
function Addons.items(plugin)
    local UIManager = require("ui/uimanager")
    local rows = {}
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
