--[[--
Your calendar as the sleep screen: Settings → Sleep and wallpaper → Sleep →
Wallpaper has two more tiles when a calendar is set up (Settings → Accounts and
services → Calendar):

  * Today's calendar: today in big with its events, then the next days that
    have events (the Calendar tab's Agenda);
  * This week's calendar: the week, a day a row (the tab's Week).

It's drawn from the events kept on the Kindle, so going to sleep never waits
for Wi-Fi. They're kept fresh when Wi-Fi connects (if the last sync is more
than an hour old) and whenever the Calendar tab opens; the page says when they
were last synced.

frontend/ui/screensaver.lua draws a sleep screen named here (screensaver_type
"gz_calendar" or "gz_calendar_week") with the function this registers; without
it (the plugin off) that sleep screen falls back to a picture.
]]

local Log = require("gzreader_log")

local M = {
    IDS = { gz_calendar = "agenda", gz_calendar_week = "week" },
    CARD = "gzreader_sleep_calendar_card", -- nil: no card; "top" or "bottom": where it goes
    CARD_PLACES = { top = 0.04, bottom = 0.96 },
    FRESH = 3600, -- s: Wi-Fi connecting syncs the calendar when its events are older than this
}

--- The calendar layout chosen for the sleep screen ("agenda", "week"), or nil.
function M.chosen(settings)
    if settings:nilOrTrue("gzreader_sleep_auto") then return nil end
    return M.IDS[settings:readSetting("screensaver_type")]
end

--- Whether there's a calendar to show (a CalDAV account, calendar links, or the holidays).
function M.available(plugin)
    local ok, yes = pcall(function() return require("gzreader_calendar").hasSources(plugin) end)
    return ok and yes or false
end

--- The sleep screen for `id`, w x h: a widget, or nil.
function M.page(plugin, id, w, h)
    local layout = M.IDS[id]
    if not layout or not plugin then return nil end
    return require("gzreader_calendar").sleepPage(plugin, layout, w, h)
end

--- Tell the sleep screen how to draw ours. `owner` is the plugin's class:
--- its last instance (the screen in use) is the one asked.
function M.install(owner)
    local ok, Screensaver = pcall(require, "ui/screensaver")
    if not ok or type(Screensaver) ~= "table" then return false end
    Screensaver.gz_screens = Screensaver.gz_screens or {}
    for id in pairs(M.IDS) do
        Screensaver.gz_screens[id] = function(w, h) return M.page(owner.last_instance, id, w, h) end
    end
    -- the card over any other wallpaper
    Screensaver.gz_cards = Screensaver.gz_cards or {}
    Screensaver.gz_cards.calendar = function(w, h) return M.card(owner.last_instance, w, h) end
    return true
end

--- Where the calendar card goes over the wallpaper: "top", "bottom", or nil (none).
function M.cardPlace(settings)
    local v = (settings or G_reader_settings):readSetting(M.CARD)
    return M.CARD_PLACES[v] and v or nil
end

--- The card for a sleep screen w x h: { widget, vertical (0 top … 1 bottom) }, or nil.
function M.card(plugin, w, _h)
    local place = M.cardPlace()
    if not place or not plugin then return nil end
    local widget = require("gzreader_calendar").sleepCard(plugin, w)
    if not widget then return nil end
    return { widget = widget, vertical = M.CARD_PLACES[place] }
end

--- Settings → Sleep and wallpaper → Sleep: its row (the card over the wallpaper).
function M.cardItem()
    local _ = require("gettext")
    local names = { top = _("at the top"), bottom = _("at the bottom") }
    local function row(text, value)
        return { text = text, radio = true,
            checked_func = function() return M.cardPlace() == value end,
            callback = function()
                if value then G_reader_settings:saveSetting(M.CARD, value) else G_reader_settings:delSetting(M.CARD) end
                Log.info("calendar: the sleep screen's card", tostring(value or "off"))
            end }
    end
    return {
        text_func = function()
            local p = M.cardPlace()
            return p and require("ffi/util").template(_("Calendar on the wallpaper: %1"), names[p]) or _("Calendar on the wallpaper: off")
        end,
        help_text = _("A small card with today's date and your next events, laid over whatever wallpaper you choose (and the sleep screen message, if you have one). From the events kept on the Kindle."),
        enabled_func = function()
            local ok, plugin = pcall(function()
                local u = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
                return u and u.gzreader
            end)
            return ok and plugin ~= nil and M.available(plugin)
        end,
        sub_item_table = { row(_("Off"), nil), row(_("At the top"), "top"), row(_("At the bottom"), "bottom") },
    }
end

--- Wi-Fi connected: sync the calendar if it's the sleep screen and its events
--- are over an hour old. Returns what it did ("sync", "fresh", or nil).
function M.onNetworkConnected(plugin, now)
    if not M.chosen(G_reader_settings) and not M.cardPlace() then return nil end
    local Calendar = require("gzreader_calendar")
    if not Calendar.hasNetSources(plugin) then return nil end
    if Calendar.events == nil then pcall(Calendar.loadCache) end
    now = now or os.time()
    if Calendar.cached_at and now - Calendar.cached_at < M.FRESH then return "fresh" end
    Calendar.plugin = plugin
    Log.info("calendar: synced for the sleep screen")
    Calendar.refresh(plugin)
    return "sync"
end

return M
