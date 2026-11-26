-- The calendar as the sleep screen (gzreader_sleepcalendar.lua): a calendar
-- link set up (never fetched here: its events are put in as if synced),
-- Wallpaper's tiles with Today's and This week's calendar, then each as the
-- sleep screen, the way the Kindle shows it going to sleep.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh calendar_sleep.lua <out>
-- Checks go to <out>/calendar-sleep-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function dark(E)
    -- the share of dark pixels in a grid over the screen
    local Screen = require("device").screen
    local w, h = Screen:getWidth(), Screen:getHeight()
    local n, d = 0, 0
    for y = 10, h - 10, 17 do
        for x = 10, w - 10, 17 do
            n = n + 1
            if E.display:getPixel(x, y):getColor8().a < 128 then d = d + 1 end
        end
    end
    return d / n
end
local function sleep(id)
    return function(E)
        local P = require("gzreader_sleeppreview")
        P.choose(id)
        local Screensaver = require("ui/screensaver")
        Screensaver:setup()
        E.say("sleep:", tostring(Screensaver.screensaver_type))
        check(Screensaver.screensaver_type == id, "going to sleep: " .. id .. " is the sleep screen")
        Screensaver:show()
    end
end
local function measure(what)
    return function(E)
        local share = dark(E)
        E.say("dark share", what, string.format("%.3f", share))
        check(share > 0.01 and share < 0.6, what .. ": a page drawn (" .. string.format("%.1f", share * 100) .. "% dark)")
        require("ui/screensaver"):close()
    end
end
add({ key = "Back", after = 3 })
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local plugin = fm().gzreader
    local Cal = require("gzreader_calendar")
    plugin.store.calendar_feeds = { { url = "https://calendar.example.com/family.ics", name = "Family", enabled = true } }
    local today = Cal.dayStart()
    local function at(days, hour, min) return Cal.addDays(today, days) + hour * 3600 + (min or 0) * 60 end
    Cal.plugin = plugin
    Cal.events = {
        { title = "Dentist", location = "Main St", start = at(0, 9, 30), finish = at(0, 10, 15), cal = 1 },
        { title = "Lunch with Sam", start = at(0, 12), finish = at(0, 13), cal = 1 },
        { title = "Piano lesson", start = at(0, 16), finish = at(0, 17), cal = 1 },
        { title = "Library books due", start = at(1, 0), finish = at(2, 0), all_day = true, cal = 1 },
        { title = "Book club", location = "Café", start = at(2, 19), finish = at(2, 21), cal = 1 },
        { title = "Soccer practice", start = at(4, 17, 30), finish = at(4, 19), cal = 1 },
    }
    Cal.range = { from = Cal.addDays(today, -14), to = Cal.addDays(today, 90) }
    Cal.cached_at = os.time() - 1800
    local P = require("gzreader_sleeppreview")
    local ids = {}
    for _i, c in ipairs(P.choices()) do ids[c.id] = true end
    check(ids.gz_calendar and ids.gz_calendar_week, "Wallpaper's tiles: Today's calendar and This week's calendar")
    P.show()
end, after = 6 })
add({ shot = "calsleep-1-tiles" })
add({ fn = function(E)
    local st = UIM()._window_stack
    UIM():close(st[#st].widget)
end, after = 3 })
add({ fn = sleep("gz_calendar"), after = 8 })
add({ shot = "calsleep-2-today" })
add({ fn = measure("Today's calendar"), after = 5 })
add({ fn = sleep("gz_calendar_week"), after = 8 })
add({ shot = "calsleep-3-week" })
add({ fn = measure("This week's calendar"), after = 5 })
add({ fn = function(E)
    -- without the plugin's drawing: a picture instead, never a blank screen
    local Screensaver = require("ui/screensaver")
    local keep = Screensaver.gz_screens
    Screensaver.gz_screens = nil
    Screensaver:setup()
    check(Screensaver.screensaver_type == "random_image", "nothing to draw it: a picture instead")
    Screensaver:cleanup()
    Screensaver.gz_screens = keep
    require("gzreader_sleeppreview").choose("auto")
    local f = io.open(E.out .. "/calendar-sleep-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
