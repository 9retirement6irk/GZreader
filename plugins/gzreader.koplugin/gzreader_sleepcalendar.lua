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
    return true
end

--- Wi-Fi connected: sync the calendar if it's the sleep screen and its events
--- are over an hour old. Returns what it did ("sync", "fresh", or nil).
function M.onNetworkConnected(plugin, now)
    if not M.chosen(G_reader_settings) then return nil end
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
