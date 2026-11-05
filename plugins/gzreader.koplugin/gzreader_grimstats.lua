--[[--
Reading stats from Grimmory for Home's "Grimmory reading stats" widget
(zenos: home/widgets/grimmory_stats.lua). They count every device: each
GZreader (and Grimmory's web reader) sends its reading sessions, and
Grimmory adds them up (its user stats, /api/v1/user-stats/...):

  streak, longest_streak, reading_days   reading/streak
  week_time, week_books                  reading/timeline (this ISO week)
  month_sessions                         reading/heatmap/monthly
  year_finished                          reading/completion-timeline

Fetched in the background when Home shows them and they're over 15 minutes
old (only while Wi-Fi is already on, never turning it on), and after this
Kindle's reading sessions reach Grimmory. The last ones are kept for when
it's offline. Grimmory only answers users allowed to see their statistics
(its "access user stats" permission): without it, the widget shows dashes
and the log says why.
]]

local Log = require("gzreader_log")

local GS = { TTL = 15 * 60 }

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
    local timeline = get("timeline?year=" .. wyear .. "&week=" .. week)
    if type(timeline) == "table" then
        values.week_time = sum(timeline, "totalDurationSeconds")
        values.week_books = #timeline
    end
    local heat = get("heatmap/monthly?year=" .. d.year .. "&month=" .. d.month)
    if type(heat) == "table" then values.month_sessions = sum(heat, "count") end
    local done = get("completion-timeline?year=" .. d.year)
    if type(done) == "table" then values.year_finished = sum(done, "finishedBooks") end
    return { values = values }
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
    local cached = plugin.store.grimmory_stats
    if not force and cached and os.time() - (tonumber(cached.at) or 0) < GS.TTL then return end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end
    GS.busy = true
    require("gzreader_async").run(plugin.api, function(api) return GS.fetch(api) end, function(res)
        GS.busy = nil
        if type(res) ~= "table" then return end
        local old = cached and cached.values
        if res.error then
            Log.warn("Grimmory reading stats:", res.error == "permission"
                and "this user may not see reading statistics (Grimmory: user settings → permissions)" or res.error)
            plugin.store.grimmory_stats = { at = os.time(), values = old or {}, error = res.error }
        else
            plugin.store.grimmory_stats = { at = os.time(), values = res.values }
        end
        plugin:save()
        if not same(old, plugin.store.grimmory_stats.values) then
            local UIManager = require("ui/uimanager")
            UIManager:nextTick(function() pcall(function() require("common/gz_view").redrawHome() end) end)
        end
    end, "grimmory stats")
end

--- What the widget shows now (and a refresh if they're old).
function GS.values(plugin)
    pcall(GS.refresh, plugin)
    local cached = plugin.store.grimmory_stats
    return cached and cached.values or {}
end

--- After reading sessions reached Grimmory: fetch again next time.
function GS.stale(plugin)
    if plugin.store.grimmory_stats then plugin.store.grimmory_stats.at = 0 end
end

return GS
