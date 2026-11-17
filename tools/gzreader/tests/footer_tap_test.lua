-- The setup guide's reader defaults (ZenOS common/reader_defaults.lua, run by
-- its last page): a tap on the bottom status bar hides it ("Hide on tap:
-- Bottom"). ZenOS's presets lock the bar, and a tap there turned the page
-- instead (owner's Kindle Scribe, 2026-11-16). reader_defaults,
-- reader_footer_presets and reader_status_bar are real; the rest are stubs.
--   luajit footer_tap_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
local function magic()
    local m
    m = setmetatable({}, { __index = function() return m end, __call = function() return m end })
    return m
end
local real = {
    ["common/reader_defaults"] = true,
    ["common/reader_status_bar"] = true,
    ["modules/reader/patches/reader_footer_presets"] = true,
}
local saved_preset
local stubs = {
    ["common/plugin_root"] = "",
    ["common/font_language"] = { supportsBundledFonts = function() return false end },
    ["common/library_font_path"] = { resolve = function(p) return p end },
    ["config/preset_store"] = {
        saveSettings = function(_kind, s) saved_preset = s end,
        setActivePreset = function() end,
    },
    ["apps/reader/readerui"] = { instance = nil },
    device = { hasColorScreen = function() return false end, screen = { scaleBySize = function(_s, v) return v end } },
}
table.insert(package.loaders, 2, function(name)
    if stubs[name] ~= nil then local v = stubs[name]; return function() return v end end
    if real[name] then return nil end
    return function() return magic() end
end)

local function store()
    local t = {}
    return {
        t = t,
        saveSetting = function(_s, k, v) t[k] = v end,
        readSetting = function(_s, k) return t[k] end,
        delSetting = function(_s, k) t[k] = nil end,
        isTrue = function(_s, k) return t[k] == true end,
        flipNilOrFalse = function(_s, k) t[k] = not t[k] end,
    }
end
G_reader_settings = store()

local ok_count, fail = 0, 0
local function check(c, n) if c then ok_count = ok_count + 1 print("  ok   " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

local Defaults = require("common/reader_defaults")
local StatusBar = require("common/reader_status_bar")
local presets = require("modules/reader/patches/reader_footer_presets")

local settings = store()
local config = {}
local ok, err = pcall(Defaults.apply, settings, config)
check(ok, "the setup guide's reader defaults apply " .. tostring(not ok and err or ""))
local footer = settings.t.footer
check(type(footer) == "table" and footer.lock_tap == false, "the bottom status bar isn't locked after setup")
check(type(config.reader_footer) == "table" and config.reader_footer.tap_hide == "bottom",
    "Hide on tap: Bottom after setup")
local plugin = { config = config }
check(StatusBar.getTapHide(plugin, { settings = footer }) == "bottom",
    "a tap on the bottom status bar hides the bottom bar (not the top one, not the next page)")
check(type(saved_preset) == "table" and saved_preset.footer.lock_tap == false,
    "the reader preset kept as active says the same")
check(presets[1].footer.lock_tap == true, "ZenOS's own presets are unchanged (picking one later still locks the bar)")
-- a later change in Settings (Hide on tap: Off) still wins
footer.lock_tap = true
check(StatusBar.getTapHide(plugin, { settings = footer }) == false, "Hide on tap: Off still turns it off")

print(string.format("%d passed, %d failed", ok_count, fail))
os.exit(fail == 0 and 0 or 1)
