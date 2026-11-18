-- Settings arranged as iOS and macOS arrange theirs (common/gz_settings_tree.lua):
-- the real Settings page at its first page and in each new section, with a
-- shot of each, and every page's rows in the log ("[emu] tree: …").
--   GZ_EMU_MODEL=pw3 run.sh settings_tree.lua <out>
local function UIM() return require("ui/uimanager") end

local function texts(list)
    local out = {}
    for _i, it in ipairs(list or {}) do
        local t = it.text
        if t == nil and type(it.text_func) == "function" then
            local ok, v = pcall(it.text_func); t = ok and v or nil
        end
        out[#out + 1] = tostring(t)
    end
    return table.concat(out, " | ")
end

local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
end

-- the Settings page, opened at `path` (texts; a table { key, value } as is)
local function open(path, name)
    return function(_E)
        local Page = require("modules/settings/zen_settings_page")
        Page.closeActive()
        local markers = {}
        for _i, t in ipairs(path) do
            markers[#markers + 1] = type(t) == "table" and t or { key = "text", value = t }
        end
        local page = Page.show(plugin(), { path = markers })
        UIM():scheduleIn(2, function()
            local p = rawget(_G, "__ZEN_UI_SETTINGS_PAGE") or page
            print("[emu] tree: " .. name .. " = " .. texts(p and p.item_table))
        end)
    end
end

return {
    start = 16,
    { fn = function()
        -- past the setup guide, to Home
        for i = #UIM()._window_stack, 1, -1 do
            local w = UIM()._window_stack[i].widget
            if w and (w.name == "setup guide" or w.name == "QR code screen") then UIM():close(w) end
        end
    end, after = 6 },
    { fn = open({}, "root"), after = 6 },
    { shot = "1-settings" },
    { fn = open({ "General" }, "general"), after = 6 },
    { shot = "2-general" },
    { fn = open({ "Display and light" }, "display"), after = 6 },
    { shot = "3-display" },
    { fn = open({ "Display and light", "Dark mode" }, "dark mode"), after = 6 },
    { shot = "4-dark-mode" },
    { fn = open({ "Sleep and wallpaper" }, "sleep and wallpaper"), after = 6 },
    { shot = "5-sleep-wallpaper" },
    { fn = open({ "Home and tabs" }, "home and tabs"), after = 6 },
    { shot = "6-home-tabs" },
    { fn = open({ "Reader" }, "reader"), after = 6 },
    { shot = "7-reader" },
    { fn = open({ "Accounts and services" }, "accounts"), after = 6 },
    { shot = "8-accounts" },
    { fn = open({ "Privacy and diagnostics" }, "privacy"), after = 6 },
    { shot = "9-privacy" },
    { fn = function() require("modules/settings/zen_settings_page").closeActive() end, after = 3 },
}
