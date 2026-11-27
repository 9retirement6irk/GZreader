-- Settings kept simple (common/gz_settings_tidy.lua): each thing in one place,
-- as few taps as it takes, on pages made up as the tree makes them.
--   luajit gz_settings_tidy_test.lua <plugins/zenos.koplugin>
local ZEN = arg[1]
package.path = ZEN .. "/?.lua;" .. package.path
package.loaded["gettext"] = function(s) return s end
package.loaded["ffi/util"] = { template = function(s, ...)
    local args = { ... }
    return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end }
local warned = {}
package.loaded["logger"] = { warn = function(...) warned[#warned + 1] = table.concat({ ... }, " ") end, info = function() end }
local opened
package.loaded["gzreader_tabs"] = { zen = function() return { zen = true } end }
package.loaded["modules/settings/zen_settings_page"] = { show = function(_zen, opts) opened = opts.path; return {} end }

local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end
end
local Tidy = require("common/gz_settings_tidy")
local function texts(list)
    local t = {}
    for _i, it in ipairs(list or {}) do t[#t + 1] = Tidy.label(it) or "?" end
    return table.concat(t, " | ")
end
local function sec(root, key) return Tidy.rowsOf((Tidy.section(root, key))) end

-- a first page as gz_settings_tree.build makes it (the rows that matter here)
local function root()
    local hw_sub = {
        { text = "On the Kindle", radio = true },
        { text = "With AI (needs a key)", radio = true, separator = true },
        { text_func = function() return "AI key and service: Claude" end, sub_item_table_func = function() return { { text = "Claude key: set" } } end },
    }
    return {
        { text = "Wi-Fi", _zen_settings_root = "wifi", sub_item_table = { { text = "On" } } },
        { text = "General", _zen_settings_root = "general", sub_item_table = { { text = "About" } } },
        { text = "Sleep and wallpaper", _zen_settings_root = "sleep", sub_item_table = {
            { text = "Sleep", sub_item_table_func = function() return { { text = "Wallpaper" } } end },
            { text = "Home background", sub_item_table = {} },
            { text = "Pictures from Immich", sub_item_table_func = function() return {} end },
        } },
        { text = "Accounts and services", _zen_settings_root = "accounts", sub_item_table = {
            { text = "Books", mandatory = "Grimmory" },
            { text = "Notes", mandatory = "Memos", sub_item_table_func = function()
                return { { text = "Layout" }, { text_func = function() return "Handwriting to text: Claude" end, sub_item_table = hw_sub } }
            end },
            { text = "AI", sub_item_table_func = function() return {} end },
            { text = "Photos", mandatory = "Immich" },
        } },
    }
end

print("== one place for each thing")
local r = Tidy.apply(root(), {})
check(texts(sec(r, "sleep")) == "Wallpaper | Home background", "Sleep and wallpaper: no Pictures from Immich (that's Accounts and services → Photos)")
local notes = Tidy.find(sec(r, "accounts"), "Notes")
local hw = Tidy.find(notes.sub_item_table_func(), function(it) return Tidy.startsWith(it, "Handwriting to text") end)
local link = hw.sub_item_table[3]
check(Tidy.label(link) == "AI service: Claude" and link.sub_item_table_func == nil and link.callback,
    "Notes → Handwriting to text: one row naming the AI service, not the whole AI page again")
link.callback()
check(opened and opened[1].value == "Accounts and services" and opened[2].value == "AI", "…a tap opens Accounts and services → AI")
check(texts(hw.sub_item_table):find("On the Kindle | With AI", 1, true) == 1, "…the other rows as they were")
-- a page without those rows: nothing changes, nothing fails
local bare = { { text = "Sleep and wallpaper", _zen_settings_root = "sleep", sub_item_table = { { text = "Sleep", enabled = false } } },
    { text = "Accounts and services", _zen_settings_root = "accounts", sub_item_table = { { text = "Notes", sub_item_table_func = function() return { { text = "Layout" } } end } } } }
Tidy.apply(bare, {})
check(texts(Tidy.rowsOf(bare[1])) == "" and texts(bare[2].sub_item_table[1].sub_item_table_func()) == "Layout" and #warned == 0,
    "rows that aren't there: left alone")
-- a step that fails doesn't take Settings with it
local bad = Tidy.apply({ { _zen_settings_root = "accounts", sub_item_table = setmetatable({}, { __index = function() error("boom") end }) } }, {})
check(type(bad) == "table", "a step that fails: Settings still opens")
-- a page built again (refresh_func) is changed again
local list = { { text = "x" } }
list.refresh_func = function() return { { text = "Pictures from Immich" }, { text = "y" } } end
local item = { sub_item_table = list }
Tidy.onPage(item, function(l) Tidy.take(l, "Pictures from Immich") end)
check(texts(list.refresh_func()) == "y", "a page built again on a refresh: changed the same way")

print("== fewer taps")
;(function()
    local sleep_on = true
    local function page()
        return {
            { text = "Display and light", _zen_settings_root = "display", sub_item_table = {
                { text = "Screen" },
                { text = "Font", text_func = function() return "Font: Hyperreadable, 18" end, icon_glyph = "F",
                  sub_item_table = { { text = "Font size: 18" }, { text = "Font: Hyperreadable" }, { text = "Reset font" } } },
                { text_func = function() return "Size of menus and text: Automatic" end, sub_item_table = { { text = "Smaller" } } },
                { text = "Blur menu background" },
            } },
            { text = "Sleep and wallpaper", _zen_settings_root = "sleep", sub_item_table = {
                { text = "Sleep", enabled_func = function() return sleep_on end, sub_item_table_func = function()
                    return { { text = "Wallpaper" }, { text = "Wallpaper options" }, { text = "Sleep screen message" }, { text = "Automatic suspend" } }
                end },
                { text = "Home background", sub_item_table = {} },
                { text = "Pictures from Immich" },
            } },
        }
    end
    local p = Tidy.apply(page(), {})
    local sleep = p[2]
    local rows = sleep.sub_item_table_func()
    check(texts(rows) == "Wallpaper | Wallpaper options | Sleep screen message | Automatic suspend | Home background"
        and rows[4].separator and not rows[5].separator, "Sleep and wallpaper: the sleep screen's rows on its own page (no Sleep row to open first), then Home background")
    sleep_on = false
    check(texts(sleep.sub_item_table_func()) == "Home background", "…a device without a sleep screen: Home background only")
    local display = select(2, Tidy.section(p, "display"))
    check(texts(display) == "Screen | Menu text | Blur menu background", "Display and light: Font and Size of menus and text are one row, Menu text")
    local mt = Tidy.find(display, "Menu text")
    check(mt.icon_glyph == "F" and mt.help_text and texts(mt.sub_item_table_func()) == "Size of menus and text: Automatic | Font size: 18 | Font: Hyperreadable | Reset font"
        and mt.sub_item_table_func()[1].separator, "…the size of everything first, then the font's rows")
    -- only one of them (a device without the size row): as it was
    local one = { { _zen_settings_root = "display", sub_item_table = { { text = "Font", sub_item_table = { { text = "Font size: 18" } } } } } }
    Tidy.apply(one, {})
    check(texts(one[1].sub_item_table) == "Font", "…without the size row (small screens): Font as it was")
end)()

print("== rows where they belong")
;(function()
    local built = 0
    local function page()
        return {
            { text = "General", _zen_settings_root = "general", sub_item_table = {
                { text = "About" }, { text = "Language", separator = true },
                { text = "Transfer", sub_item_table = { { text = "Copy to or from another GZreader" }, { text = "Sync through a computer" } } },
                { text = "Setup Guide" }, { text = "Performance", sub_item_table = { { text = "Pre-size covers" } } } } },
            { text = "Display and light", _zen_settings_root = "display", sub_item_table = {
                { text = "Screen", sub_item_table_func = function()
                    built = built + 1
                    return { { text = "Screen DPI" }, { text = "E-ink settings" }, { text = "Notifications", sub_item_table = { { text = "From gestures and profiles" } } } }
                end } } },
            { text = "Home and tabs", _zen_settings_root = "home", sub_item_table = { { text = "Home" }, { text = "Status bar" }, { text = "Downloads tab" } } },
            { text = "Reader", _zen_settings_root = "reader", sub_item_table = {
                { text = "Appearance" }, { text = "Highlight / Lookup", sub_item_table = { { text = "Zen quick lookup" }, { text = "Show Wikipedia" } } } } },
            { text = "Accounts and services", _zen_settings_root = "accounts", sub_item_table = {
                { text = "Books" },
                { text = "Notes", sub_item_table_func = function()
                    return { { text = "Layout" }, { text_func = function() return "Pen's shortcut button: Eraser" end, sub_item_table = {} },
                        { text = "Pen's eraser removes highlights" },
                        { text_func = function() return "Handwriting to text: On the Kindle" end, sub_item_table = { { text = "Handwriting on the keyboard (✍ key)" } } },
                        { text = "Storage used: 0 bytes" } }
                end },
                { text = "Photos" },
                { text = "Daily paper", mandatory = "Feeds", separator = true } } },
            { text = "Privacy and diagnostics", _zen_settings_root = "privacy", sub_item_table = {
                { text = "Diagnostic logging" },
                { text = "Advanced", sub_item_table = { { text = "KOReader settings", separator = true }, { text = "Reset GZreader" } } } } },
        }
    end
    local p = Tidy.apply(page(), { pen = true })
    local general = sec(p, "general")
    check(texts(general) == "About | Language | Pen | Transfer or reset | Setup Guide", "General: Pen before Transfer or reset; no Performance " .. texts(general))
    local pen = Tidy.find(general, "Pen")
    check(texts(pen.sub_item_table_func()) == "Pen's shortcut button: Eraser | Handwriting to text: On the Kindle",
        "General → Pen (a Kindle with a pen): the shortcut button and Handwriting to text, out of Notes")
    local notes = Tidy.find(sec(p, "accounts"), "Notes")
    check(texts(notes.sub_item_table_func()) == "Layout | Storage used: 0 bytes", "…Notes keeps its own rows")
    local hl = Tidy.find(sec(p, "reader"), "Highlight / Lookup")
    check(texts(hl.sub_item_table) == "Zen quick lookup | Show Wikipedia | Pen's eraser removes highlights",
        "Reader → Highlight / Lookup: Pen's eraser removes highlights (it acts in books)")
    local transfer = Tidy.find(general, "Transfer or reset")
    check(texts(transfer.sub_item_table) == "Copy to or from another GZreader | Sync through a computer | Reset GZreader"
        and transfer.sub_item_table[2].separator, "General → Transfer or reset: Reset GZreader last, after a line")
    local adv = Tidy.find(sec(p, "privacy"), "Advanced")
    check(texts(adv.sub_item_table) == "Performance | Notifications | KOReader settings" and adv.sub_item_table[2].separator
        and not adv.sub_item_table[3].separator, "Privacy and diagnostics → Advanced: Performance, Notifications, KOReader settings")
    local screen = Tidy.find(sec(p, "display"), "Screen")
    check(texts(screen.sub_item_table_func()) == "Screen DPI | E-ink settings", "Display and light → Screen: no Notifications")
    check(texts(Tidy.rowsOf(adv.sub_item_table[2])) == "From gestures and profiles", "…its switches are Advanced → Notifications")
    check(texts(sec(p, "home")) == "Home | Daily paper | Status bar | Downloads tab" and texts(sec(p, "accounts")) == "Books | Notes | Photos"
        and not sec(p, "accounts")[3].separator, "Daily paper: Home and tabs, after Home (no account; read on Home)")
    -- a Kindle without a pen: Handwriting to text stays in Notes, no Pen row
    local q = Tidy.apply(page(), { pen = false })
    check(not Tidy.find(sec(q, "general"), "Pen") and texts(Tidy.find(sec(q, "accounts"), "Notes").sub_item_table_func())
        == "Layout | Pen's shortcut button: Eraser | Handwriting to text: On the Kindle | Storage used: 0 bytes",
        "a Kindle without a pen: no Pen row; Handwriting to text stays in Notes")
end)()

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
