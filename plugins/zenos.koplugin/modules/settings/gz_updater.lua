--[[--
GZreader: what ZenOS asks of its updater, without ZenOS's updater.

ZenOS's own updater (zen_updater.lua, ~1,900 lines) downloads upstream ZenOS
releases; GZreader replaces every entry point with gzreader_update (the
end of zen_updater.lua), so the rest was loaded at every start for nothing.
ZenOS's main.lua, zen_settings.lua, zen_bugreporter.lua and
updates_settings.lua require this file instead; zen_updater.lua stays as it
is upstream (and its GZreader end stays too) so upstream merges are simple.

gzreader_update itself is loaded when it's first needed (the background
check 20 s after start or a wake, the Updates menu), not at start.
]]

local M = { _has_update = false }

-- While KOReader loads a plugin, only that plugin's folder is on
-- package.path, so add GZreader's (gzreader.koplugin, next to this one).
local function gz()
    local ok_root, root = pcall(require, "common/plugin_root")
    if ok_root and type(root) == "string" then
        local plugins_dir = root:gsub("/+$", ""):match("^(.*)/[^/]+$")
        local gz_dir = plugins_dir and (plugins_dir .. "/gzreader.koplugin")
        if gz_dir and not package.path:find(gz_dir, 1, true) then
            package.path = gz_dir .. "/?.lua;" .. package.path
        end
    end
    local ok, Update = pcall(require, "gzreader_update")
    if ok and type(Update) == "table" then return Update end
    require("logger").warn("GZreader updater not loaded:", tostring(Update))
    return nil
end
M._gz = gz

local function sync_state()
    local Update = package.loaded["gzreader_update"]
    if type(Update) ~= "table" or type(Update.state) ~= "table" then return end
    M._has_update = Update.state.has_update == true
    M._latest_ver = Update.state.latest
end

function M.init_banner() M._banner_loaded = true; sync_state() end

function M.has_update() sync_state(); return M._has_update == true end
function M.latest_version() sync_state(); return M._latest_ver end

function M.check_for_update()
    local Update = gz()
    local info = Update and Update.check()
    sync_state()
    return info and "ok" or "error"
end

function M.cancel_wakeup_check()
    M._check_cancelled = true
    if M._wakeup_timer then require("ui/uimanager"):unschedule(M._wakeup_timer) end
    M._wakeup_timer = nil
end

function M.schedule_wakeup_check()
    local UIManager = require("ui/uimanager")
    M.cancel_wakeup_check()
    M._check_cancelled = false
    M._wakeup_timer = function()
        M._wakeup_timer = nil
        if M._check_cancelled then return end
        local Update = gz()
        if not Update then return end
        Update.backgroundCheck(function()
            sync_state()
            if type(M._on_update_found) == "function" then M._on_update_found() end
        end)
        sync_state()
    end
    UIManager:scheduleIn(20, M._wakeup_timer)
end

--- Wi-Fi connected: a check unless one is already waiting.
function M.on_network_connected()
    if M._wakeup_timer then return end
    M.schedule_wakeup_check()
end

--- A version change noticed outside the updater: no "update available" left in ZenOS's config.
function M.clear_update_state(cfg)
    M._has_update = false
    if type(cfg) == "table" and type(cfg.updater) == "table" then cfg.updater.update_available = false end
end

function M.run_update() local Update = gz(); if Update then Update.run() end end

--- The settings page's header button, while an update is known.
function M.build_update_available_action(plugin)
    if not M.has_update() then return nil end
    local ok_i, icons = pcall(require, "common/inline_icon_map")
    local _ = require("gettext")
    return {
        text = (ok_i and type(icons) == "table" and icons.upgrade and (icons.upgrade .. "  ") or "") .. _("Update available"),
        zen_button = true,
        callback = function() M.run_update(plugin) end,
    }
end

local function item(n) local Update = gz(); return Update and Update.menuItems()[n] or nil end
function M.build_update_now_item() return item(1) end
function M.build_auto_check_item() return item(2) end
function M.build_changelog_item() return item(3) end
function M.build_channel_item() return item(4) end
function M.get_channel() return "stable" end

return M
