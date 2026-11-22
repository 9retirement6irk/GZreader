--[[--
Reading stats from the book server, for Home's reading stats widget (zenos:
home/widgets/grimmory_stats.lua) and the page a tap on it opens
(gzreader_statspage.lua). They count every device, because the server adds up
what each one sends. Which server: the one this Kindle is signed in to.

Grimmory (its user stats, /api/v1/user-stats/...):

  streak, longest_streak, reading_days   reading/streak
  week_time, week_books                  reading/timeline (this ISO week)
  month_sessions                         reading/heatmap/monthly
  year_finished                          reading/completion-timeline

BookOrbit (one call, GET koreader/plugin/catalog/dashboard, with the e-reader
sign-in; GS.fromDashboard turns it into the same kind of values):

  streak, longest_streak                 readingStreak
  today_time, week_time, month_time,
  year_time, year_days                   readingYear (minutes per day, a year back)
  year_finished, goal                    readingGoal
  badges                                 achievements (absent when switched off)
  library_books, reading_now             totalBooks, browseCounts

Beside the values, `detail` keeps what the page draws (GS.FIELDS says which
values each server has): BookOrbit's days, goal, badges, the book of a year ago,
finished books and the day's highlight; Grimmory's books of the week, days of
the month and finished books by month.

Fetched in the background when Home shows them and they're over 15 minutes
old (only while Wi-Fi is already on, never turning it on), and after this
Kindle's reading reaches the server. The last ones are kept for when it's
offline. Grimmory only answers users allowed to see their statistics (its
"access user stats" permission): without it, the widget shows dashes and the
log says why.
]]

local Log = require("gzreader_log")

local GS = { TTL = 15 * 60 }

--- Which values each server has (the widget offers these; the first three are its defaults).
GS.FIELDS = {
    grimmory = { "week_time", "streak", "year_finished", "longest_streak", "reading_days", "week_books", "month_sessions" },
    bookorbit = { "week_time", "streak", "year_finished", "longest_streak", "today_time", "month_time", "year_time", "year_days",
        "goal", "badges", "library_books", "reading_now" },
}

--- "grimmory" or "bookorbit": whose numbers this Kindle shows.
function GS.server(plugin)
    return type(plugin) == "table" and type(plugin.backend) == "function" and plugin:backend() == "bookorbit" and "bookorbit" or "grimmory"
end

--- ISO week of year as Grimmory's WeekFields.ISO.weekOfYear() counts it
--- (Monday first; week 1 has at least 4 days of the year; days before it: 0).
function GS.isoWeekOfYear(t)
    local d = os.date("*t", t)
    local jan1 = os.date("*t", os.time{ year = d.year, month = 1, day = 1, hour = 12 })
    local jan1_wday = (jan1.wday + 5) % 7 + 1 -- Monday 1 … Sunday 7
    local days = (d.yday - 1) + (jan1_wday - 1) -- since the Monday on or before 1 January
    return math.floor(days / 7) + (jan1_wday <= 4 and 1 or 0), d.year
end

local function sum(list, key)
    local n = 0
    for _i, r in ipairs(type(list) == "table" and list or {}) do n = n + (tonumber(type(r) == "table" and r[key]) or 0) end
    return n
end

--- Ask Grimmory (in the background process). { values } or { error }.
function GS.fetch(api, now)
    now = now or os.time()
    local d = os.date("*t", now)
    local function get(path)
        local code, data = api:call("GET", "/api/v1/user-stats/reading/" .. path, { timeouts = { 8, 15 } })
        if code == 200 then return data end
        return nil, code
    end
    local streak, code = get("streak")
    if not streak then return { error = code == 403 and "permission" or ("http_" .. tostring(code)) } end
    local values = {
        streak = tonumber(streak.currentStreak),
        longest_streak = tonumber(streak.longestStreak),
        reading_days = tonumber(streak.totalReadingDays),
    }
    local week, wyear = GS.isoWeekOfYear(now)
    local detail = { year = d.year, month = d.month }
    local timeline = get("timeline?year=" .. wyear .. "&week=" .. week)
    if type(timeline) == "table" then
        values.week_time = sum(timeline, "totalDurationSeconds")
        values.week_books = #timeline
        -- (the week's books, most read first, for the page)
        local books = {}
        for _i, r in ipairs(timeline) do
            if type(r) == "table" and (tonumber(r.totalDurationSeconds) or 0) > 0 then
                books[#books + 1] = { title = type(r.bookTitle) == "string" and r.bookTitle or "?", seconds = tonumber(r.totalDurationSeconds) }
            end
        end
        table.sort(books, function(a, b) return a.seconds > b.seconds end)
        for i = #books, 6, -1 do books[i] = nil end
        detail.week_books = books
    end
    local heat = get("heatmap/monthly?year=" .. d.year .. "&month=" .. d.month)
    if type(heat) == "table" then
        values.month_sessions = sum(heat, "count")
        local days = {}
        for _i, r in ipairs(heat) do
            local day = type(r) == "table" and type(r.date) == "string" and tonumber(r.date:match("^%d+%-%d+%-(%d+)"))
            if day and (tonumber(r.count) or 0) > 0 then days[#days + 1] = { day = day, count = tonumber(r.count) } end
        end
        detail.month_days = days
    end
    local done = get("completion-timeline?year=" .. d.year)
    if type(done) == "table" then
        values.year_finished = sum(done, "finishedBooks")
        local months = {}
        for _i, r in ipairs(done) do
            local m = type(r) == "table" and tonumber(r.month)
            if m and m >= 1 and m <= 12 then months[#months + 1] = { month = m, finished = tonumber(r.finishedBooks) or 0 } end
        end
        detail.finished_months = months
    end
    return { values = values, detail = detail }
end

local function text(v, max)
    if type(v) ~= "string" or v == "" then return nil end
    return max and #v > max and (v:sub(1, max):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…") or v
end

local function dayTime(key, add)
    local y, m, d = tostring(key):match("^(%d+)%-(%d+)%-(%d+)")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d) + (add or 0), hour = 12 }
end

local function bookLine(b)
    if type(b) ~= "table" then return nil end
    local who = type(b.authors) == "table" and type(b.authors[1]) == "string" and b.authors[1] or nil
    return { title = text(b.title, 80) or "?", author = text(who, 60) }
end

--- BookOrbit's dashboard reply as { values, detail } (no network: tested by itself).
function GS.fromDashboard(dash)
    if type(dash) ~= "table" then return { error = "bad_reply" } end
    local values, detail = {}, {}
    local streak = type(dash.readingStreak) == "table" and dash.readingStreak or {}
    values.streak = tonumber(streak.currentStreak)
    values.longest_streak = tonumber(streak.longestStreak)
    local goal = type(dash.readingGoal) == "table" and dash.readingGoal or {}
    values.year_finished = tonumber(goal.completedBooks)
    if tonumber(goal.goalBooks) and tonumber(goal.goalBooks) > 0 then
        values.goal = string.format("%d/%d", tonumber(goal.completedBooks) or 0, tonumber(goal.goalBooks))
        detail.goal = { done = tonumber(goal.completedBooks) or 0, books = tonumber(goal.goalBooks), year = tonumber(goal.year) }
    end
    values.library_books = tonumber(dash.totalBooks)
    values.reading_now = type(dash.browseCounts) == "table" and tonumber(dash.browseCounts.inProgress) or nil
    -- minutes read per day, oldest first, ending today (the reader's time zone, as the server has it)
    local ry = type(dash.readingYear) == "table" and dash.readingYear or nil
    local mins = ry and type(ry.minutes) == "table" and ry.minutes or nil
    local last = mins and dayTime(ry.startDate, #mins - 1)
    if last and #mins > 0 then
        local today = os.date("*t", last)
        local since_monday = (today.wday + 5) % 7 -- Monday 0 … Sunday 6
        local week, month, year, year_days = 0, 0, 0, 0
        local kept = {}
        for i, m in ipairs(mins) do
            m = math.max(0, math.floor(tonumber(m) or 0))
            kept[i] = m
            local back = #mins - i -- days before today
            if back <= since_monday then week = week + m end
            if back < today.day then month = month + m end
            if back < today.yday then
                year = year + m
                if m > 0 then year_days = year_days + 1 end
            end
        end
        values.today_time = kept[#kept] * 60
        values.week_time, values.month_time, values.year_time, values.year_days = week * 60, month * 60, year * 60, year_days
        detail.days = { start = ry.startDate, minutes = kept }
    end
    local ach = type(dash.achievements) == "table" and dash.achievements or nil
    if ach and tonumber(ach.total) then
        values.badges = string.format("%d/%d", tonumber(ach.earned) or 0, tonumber(ach.total))
        local function badge(b)
            if type(b) ~= "table" or not text(b.name) then return nil end
            return { name = text(b.name, 60), about = text(b.description, 160), progress = tonumber(b.currentProgress), threshold = tonumber(b.threshold) }
        end
        detail.badges = { earned = tonumber(ach.earned) or 0, total = tonumber(ach.total), next = badge(ach.next), latest = badge(ach.latest) }
    end
    local ago = type(dash.yearAgo) == "table" and dash.yearAgo or nil
    if ago and type(ago.book) == "table" then
        local b = bookLine(ago.book)
        detail.year_ago = { title = b.title, author = b.author, minutes = tonumber(ago.minutes) or 0, days = tonumber(ago.days) or 0 }
    end
    if type(dash.finishedThisYear) == "table" then
        local done = {}
        for i, b in ipairs(dash.finishedThisYear) do
            if i > 8 then break end
            done[#done + 1] = bookLine(b)
        end
        detail.finished = done
        detail.finished_count = #dash.finishedThisYear
    end
    local hl = type(dash.highlightOfTheDay) == "table" and dash.highlightOfTheDay or nil
    if hl and text(hl.text) then
        detail.highlight = { text = text(hl.text, 400), book = text(hl.bookTitle, 80), chapter = text(hl.chapterTitle, 80) }
    end
    return { values = values, detail = detail }
end

--- Ask the server this Kindle is signed in to (in the background process).
function GS.fetchFor(api, now)
    if type(api.readingDashboard) == "function" then
        local dash, err = api:readingDashboard()
        if not dash then return { error = tostring(err) } end
        return GS.fromDashboard(dash)
    end
    return GS.fetch(api, now)
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if b[k] ~= v then return false end end
    for k, v in pairs(b) do if a[k] ~= v then return false end end
    return true
end

--- Fetch them if they're old (and Wi-Fi is on): Home redraws when they change.
function GS.refresh(plugin, force)
    if GS.busy or not (plugin.api and plugin.api:isPaired()) then return end
    local server = GS.server(plugin)
    local name = server == "bookorbit" and "BookOrbit" or "Grimmory"
    local cached = GS.kept(plugin)
    if not force and cached and os.time() - (tonumber(cached.at) or 0) < GS.TTL then return end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end
    GS.busy = true
    require("gzreader_async").run(plugin.api, function(api) return GS.fetchFor(api) end, function(res)
        GS.busy = nil
        if type(res) ~= "table" then return end
        local old = cached and cached.values
        if res.error then
            Log.warn(name, "reading stats:", res.error == "permission"
                and "this user may not see reading statistics (Grimmory: user settings → permissions)" or res.error)
            plugin.store.grimmory_stats = { at = os.time(), values = old or {}, detail = cached and cached.detail, error = res.error, server = server }
        else
            plugin.store.grimmory_stats = { at = os.time(), values = res.values, detail = res.detail, server = server }
        end
        plugin:save()
        if not same(old, plugin.store.grimmory_stats.values) then
            local UIManager = require("ui/uimanager")
            UIManager:nextTick(function() pcall(function() require("common/gz_view").redrawHome() end) end)
        end
    end, "reading stats")
end

--- The numbers kept, when they're from the server this Kindle is signed in to now
--- (ones kept before the server was noted are Grimmory's).
function GS.kept(plugin)
    local cached = plugin.store.grimmory_stats
    if type(cached) ~= "table" or (cached.server or "grimmory") ~= GS.server(plugin) then return nil end
    return cached
end

--- What the widget shows now (and a refresh if they're old).
function GS.values(plugin)
    pcall(GS.refresh, plugin)
    local cached = GS.kept(plugin)
    return cached and cached.values or {}
end

--- Everything for the page: { server, name, values, detail, at, error }.
function GS.all(plugin)
    pcall(GS.refresh, plugin)
    local cached = GS.kept(plugin) or {}
    local server = GS.server(plugin)
    return { server = server, name = server == "bookorbit" and "BookOrbit" or "Grimmory", values = cached.values or {},
        detail = cached.detail or {}, at = tonumber(cached.at), error = cached.error, usb = cached.usb }
end

--- After reading sessions reached Grimmory: fetch again next time.
function GS.stale(plugin)
    if plugin.store.grimmory_stats then plugin.store.grimmory_stats.at = 0 end
end

return GS
