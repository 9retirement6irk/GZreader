--[[--
ZenOS's first-run tour of the menu, for GZreader's quick panel (touch Kindles).

After the setup guide, ZenOS tours its touch menu: its Zen Mode button, its
Zen Settings tab, KOReader's settings. On GZreader that menu is replaced by
the quick panel (gzreader_panel.lua), so ZenOS's tour opened the panel and
pointed at places that aren't there, then left the panel open over the page
browser for the rest of the tour (its second part, "Swipe up to open the Page
Browser", runs on the first book). This tour shows the panel itself: how to
open and close it, Settings, and the Home or This book tiles. It closes the
panel when it ends, then (in a book) hands over to ZenOS's page browser tour.

ZenOS's common/quickstart/menu_tour.lua calls Tour.start on touch devices;
keyboard Kindles skip both tours (their Menu key opens the panel).
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Tour = { active = false }

--- The texts, by step (tests read them).
Tour.TEXT = {
    panel = _("This is the quick panel. Swipe down from the top of the screen to open it, at Home or in a book. Tap below it to close it."),
    settings = _("Settings: your Grimmory connection, Notes, Calendar, reading and Home."),
    book = _("This book: contents, bookmarks, search, font and layout for the book you're reading."),
    home = _("Home: continue reading, send books from your browser, search, view and sort your books."),
}

local function panelOpen()
    local ok, Panel = pcall(require, "gzreader_panel")
    return ok and Panel.open or nil
end

--- Close the quick panel if it's open.
function Tour.closePanel()
    local w = panelOpen()
    if w then UIManager:close(w) end
end

--- Where the panel's parts are (screen rectangles), from its layout:
--- `controls` (the Controls tiles), `settings` (the Settings tile),
--- `section` (the Home or This book tiles' heading and first row).
function Tour.targets(w)
    local out = {}
    local placed, controls = w and w.placed or {}, w and w.controls or {}
    local titles = w and w.titles or {}
    local sw = Device.screen:getWidth()
    local function rowOf(first, last, title)
        local p, q = placed[first], placed[last]
        if not (p and q) then return nil end
        local top = title and title.y or p.y
        return { x = p.x, y = top, w = sw - 2 * p.x, h = q.y + q.tile.h - top }
    end
    local n = #controls
    -- (the Controls tiles: all their rows)
    out.controls = rowOf(1, n, titles[1])
    for _i, p in ipairs(placed) do
        if p.tile.label == _("Settings") then
            out.settings = { x = p.x, y = p.y, w = p.tile.w, h = p.tile.h }
        end
    end
    -- (the section's first row: up to 5 tiles)
    local cols = 0
    for i = n + 1, #placed do
        if placed[i].y ~= placed[n + 1].y then break end
        cols = cols + 1
    end
    if cols > 0 then out.section = rowOf(n + 1, n + cols, titles[2]) end
    return out
end

--- The steps for the open panel (`in_book`: This book, else Home).
function Tour.steps(w, in_book)
    local t = Tour.targets(w)
    local steps = {}
    if t.controls then steps[#steps + 1] = { text = Tour.TEXT.panel, target = t.controls } end
    if t.settings then steps[#steps + 1] = { text = Tour.TEXT.settings, target = t.settings } end
    if t.section then steps[#steps + 1] = { text = in_book and Tour.TEXT.book or Tour.TEXT.home, target = t.section } end
    return steps
end

--- Start the tour (ZenOS's `plugin`, its ui: the file manager or a book).
--- Returns true when it started.
function Tour.start(plugin)
    local meta = plugin and plugin.config and plugin.config._meta
    if type(meta) ~= "table" or meta.quickstart_menu_tour_pending ~= true or Tour.active then return false end
    local ui = plugin.ui
    local menu = ui and ui.menu
    if not (menu and type(menu.onShowMenu) == "function") then return false end
    local in_book = ui.document ~= nil
    if not panelOpen() then menu:onShowMenu() end
    local w = panelOpen()
    if not w then return false end
    local steps = Tour.steps(w, in_book)
    if #steps == 0 then return false end
    Tour.active = true
    local function finish(done)
        Tour.active = false
        Tour.closePanel()
        if not done then return end
        meta.quickstart_menu_tour_pending = false
        if type(plugin.saveConfig) == "function" then pcall(plugin.saveConfig, plugin) end
        -- in a book: ZenOS's next tour (swipe up for the page browser)
        if in_book and meta.quickstart_reader_tour_pending == true
                and type(menu._zen_start_reader_tour) == "function" then
            menu:_zen_start_reader_tour()
        end
    end
    local Coachmark = require("common/quickstart/menu_coachmark")
    -- (after the panel has been drawn)
    UIManager:nextTick(function()
        if panelOpen() ~= w then Tour.active = false; return end
        UIManager:show(Coachmark:new{
            name = "gzreader tour",
            steps = steps,
            on_complete = function() finish(true) end,
            -- (cancelled by a rotation: closed, asked again at the next start)
            on_cancel = function() finish(false) end,
        })
    end)
    return true
end

return Tour
