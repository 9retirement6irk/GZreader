-- The Calendar tab (CalDAV) with demo/demo_caldav.py on 127.0.0.1:18095
-- (Radicale), after the setup guide (demo/demo_grimmory.py on 18080): the
-- tab bar (Home, Downloads, Grimmory, Notes, Calendar on Z X C V B), the
-- connect page, Agenda, an event, Day, Week, Month, paging, letter keys,
-- and Settings → Connections → Calendar. Also the Notes tab's M key.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function say(label, fn) add({ fn = function(E) E.say(label, fn()) end, after = 1 }) end
local function windows(label)
    say(label, function()
        local t = {}
        for _i, w in ipairs(require("ui/uimanager")._window_stack) do
            t[#t + 1] = tostring(w.widget._gz_navbar_tab_id or w.widget.name or w.widget.title or "?")
        end
        return table.concat(t, " | ")
    end)
end

shot("cal-0-tabbar")
say("tabs:", function()
    local cfg = require("config/manager").load()
    local on = {}
    for _i, id in ipairs(cfg.navbar.tab_order) do if cfg.navbar.show_tabs[id] then on[#on + 1] = id end end
    return table.concat(on, ",")
end)
key("B", 6) -- the 5th tab: Calendar
shot("cal-1-connect")
add({ fn = function(E)
    local Cal = require("gzreader_calendar")
    E.say("connect ->", tostring(Cal.connect(plugin(), "127.0.0.1:18095", "reader", "demo-app-password")))
    if Cal.connect_menu then require("ui/uimanager"):close(Cal.connect_menu, "full"); Cal.connect_menu = nil end
    Cal.cached_at = nil
    Cal.show(plugin())
end, after = 20 })
shot("cal-2-agenda")
say("events:", function() return tostring(#(require("gzreader_calendar").events or {})) end)
key("Q", 4)
shot("cal-3-event")
key("Back", 3)
key("RPgFwd", 5)
shot("cal-4-agenda-next")
key("N", 5)
key("M", 4)
shot("cal-5-more")
key("W", 6) -- Day
shot("cal-6-day")
key("RPgFwd", 6)
shot("cal-7-day-tomorrow")
key("M", 4); key("E", 6) -- Week
shot("cal-8-week")
key("E", 6) -- the week's third day, in Day
shot("cal-9-week-day")
key("M", 4); key("R", 8) -- Month
shot("cal-10-month")
key("Down", 3); key("Right", 3)
shot("cal-11-month-focus")
key("Press", 6) -- that day, in Day
shot("cal-12-month-day")
key("RPgBack", 5)
key("M", 4); key("E", 6); key("RPgFwd", 6) -- next week
shot("cal-13-next-week")
key("M", 4); key("Q", 6) -- back to Agenda
-- other tabs: Notes's M key opens its menu (not the Home menu)
key("X", 6)
shot("cal-14-X-downloads")
key("C", 8)
shot("cal-15-C-grimmory")
key("B", 8)
windows("after Grimmory → Calendar:")
key("V", 8)
shot("cal-16-V-notes")
windows("after Calendar → Notes:")
-- Settings → Connections → Calendar
key("Z", 6)
key("Menu", 4)
key("U", 6)
key("U", 5)
shot("cal-17-connections")
key("E", 5)
shot("cal-18-calendar-settings")
key("W", 4)
shot("cal-19-calendars")
key("Back", 3)
key("Back", 3); key("Back", 3); key("Back", 3)
return s
