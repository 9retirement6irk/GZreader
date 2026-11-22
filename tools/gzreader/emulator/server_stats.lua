-- The reading stats page (gzreader_statspage.lua): BookOrbit's numbers fetched from
-- tests/mock_bookorbit.py on 127.0.0.1:18096 and shown on Home's widget and on the page a
-- tap opens; then the page as it is with Grimmory's numbers (made up here, no server).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    if top and top.text then UIManager:close(top) end
    require("gzreader_grimstats").refresh(p, true)
    E.say("sign-in:", tostring(ok), tostring(err))
end, after = 8 })
add({ fn = function(E)
    local p = plugin()
    local all = require("gzreader_grimstats").all(p)
    E.say("stats from:", all.name, "| streak", tostring(all.values.streak), "| today", tostring(all.values.today_time), "| goal", tostring(all.values.goal),
        "| days kept", tostring(all.detail.days and #all.detail.days.minutes))
    pcall(function() require("common/gz_view").redrawHome() end)
end, after = 4 })
add({ shot = "stats-1-home" })
add({ fn = function(E)
    local page = rawget(_G, "__GZ_SERVER_STATS_PAGE")()
    E.say("BookOrbit page: sections shown", tostring(page and page.sections_shown))
end, after = 4 })
add({ shot = "stats-2-bookorbit" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    local Page = require("gzreader_statspage")
    if Page.current then UIManager:close(Page.current) end
    local d = os.date("*t")
    local page = Page.show(plugin(), { server = "grimmory", name = "Grimmory", at = os.time() - 1500,
        values = { streak = 6, longest_streak = 19, reading_days = 212, week_time = 5 * 3600 + 1200, week_books = 3, month_sessions = 31, year_finished = 14 },
        detail = { year = d.year, month = d.month,
            week_books = { { title = "The Salt Road", seconds = 9800 }, { title = "Low Tide: Notes from a Northern Shore", seconds = 6100 }, { title = "A Field Guide to Getting Lost", seconds = 3300 } },
            month_days = { { day = 1, count = 2 }, { day = 2, count = 1 }, { day = 4, count = 3 }, { day = 5, count = 1 }, { day = 8, count = 4 }, { day = 9, count = 2 },
                { day = 12, count = 1 }, { day = 13, count = 2 }, { day = 15, count = 5 }, { day = 16, count = 1 }, { day = 19, count = 2 }, { day = 20, count = 3 }, { day = 21, count = 1 } },
            finished_months = { { month = 1, finished = 1 }, { month = 2, finished = 2 }, { month = 4, finished = 1 }, { month = 5, finished = 3 }, { month = 7, finished = 2 },
                { month = 8, finished = 1 }, { month = 9, finished = 2 }, { month = 10, finished = 1 }, { month = 11, finished = 1 } } } })
    E.say("Grimmory page: sections shown", tostring(page and page.sections_shown))
end, after = 4 })
add({ shot = "stats-3-grimmory" })
return s
