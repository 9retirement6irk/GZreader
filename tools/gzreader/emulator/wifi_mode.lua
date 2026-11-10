-- Wi-Fi: On, Off, Auto (gzreader_net.lua). Home's status bar on Auto (the
-- "A" after the Wi-Fi icon), the quick panel's Wi-Fi tile in each mode, and
-- Settings → General → Wi-Fi (On, Off, Auto, Networks). The emulator has no
-- Wi-Fi to switch: the mode is set as Net.setMode saves it, and Net._switch
-- does nothing. Shots: home-auto, panel-auto, panel-on, panel-off,
-- general, general-wifi. Prints "[emu] wifi: …".
--   GZ_EMU_TREE=<tree>/koreader run.sh wifi_mode.lua <out>
local function UIM() return require("ui/uimanager") end
local TOUCH = { kt = true, pw3 = true, nst = true }
local function say(...) print("[emu] wifi:", ...) end
local function tiles()
    local st = UIM()._window_stack
    local w = st[#st] and st[#st].widget
    for _i, p in ipairs(w and w.placed or {}) do
        if p.tile.icon and tostring(p.tile.icon):match("^wifi") then
            return tostring(p.tile.label) .. " (" .. tostring(p.tile.icon) .. (p.tile.on and ", inverted" or "") .. ")"
        end
    end
    return "?"
end
local function mode(m)
    return function(_E)
        local Net = require("gzreader_net")
        Net._switch = function() end
        Net.setMode(m)
        say("mode", Net.mode(), "status-bar mark", tostring((require("common/gz_wifi_icon").mark())))
    end
end
local function panel()
    return function(E)
        if TOUCH[E.model] then
            local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
            E.swipe(W / 2, 3, W / 2, H / 2)
        else
            E.key("Menu")
        end
    end
end
local function closePanel()
    return function(_E)
        local st = UIM()._window_stack
        local w = st[#st] and st[#st].widget
        if w and w.placed then UIM():close(w) end
    end
end
local function settings(path)
    return function(_E)
        local fm = require("apps/filemanager/filemanager").instance
        local plugin = fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        local Page = require("modules/settings/zen_settings_page")
        Page.closeActive()
        local markers = {}
        for _i, t in ipairs(path) do markers[#markers + 1] = { key = "text", value = t } end
        Page.show(plugin, { path = markers })
    end
end
return {
    start = 16,
    { fn = function()
        for i = #UIM()._window_stack, 1, -1 do
            local w = UIM()._window_stack[i].widget
            if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
        end
    end, after = 8 },
    { fn = mode("auto"), after = 4 },
    { shot = "home-auto" },
    { fn = panel(), after = 5 },
    { fn = function() say("tile", tiles()) end, after = 1 },
    { shot = "panel-auto" },
    { fn = closePanel(), after = 3 },
    { fn = mode("on"), after = 3 },
    { fn = panel(), after = 5 },
    { fn = function() say("tile", tiles()) end, after = 1 },
    { shot = "panel-on" },
    { fn = closePanel(), after = 3 },
    { fn = mode("off"), after = 3 },
    { fn = panel(), after = 5 },
    { fn = function() say("tile", tiles()) end, after = 1 },
    { shot = "panel-off" },
    { fn = closePanel(), after = 3 },
    { fn = mode("auto"), after = 2 },
    { fn = settings({ "General" }), after = 6 },
    { shot = "general" },
    { fn = settings({ "General", "Wi-Fi" }), after = 6 },
    { shot = "general-wifi" },
}
