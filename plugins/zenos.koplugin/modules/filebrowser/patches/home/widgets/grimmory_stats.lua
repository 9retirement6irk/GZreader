-- GZreader: reading stats from Grimmory, the same widget as the local
-- reading stats (stats_triplet.lua: notebook page, dividers, boxes…) with
-- numbers that count every device: Grimmory adds up the reading sessions
-- each GZreader (and its web reader) sends. GZreader fetches them
-- (gzreader_grimstats.lua) and keeps the last ones for when it's offline.

local _ = require("gettext")
local base = require("modules/filebrowser/patches/home/widgets/stats_triplet")
local fmt_time = base.fmt_time

local function num(v) return v ~= nil and tostring(v) or "—" end

local FIELDS = {
    streak = { id = "streak", label = _("Day streak"), tally = "streak", icon = "streak",
        get = function(s) return num(s.streak) end },
    longest_streak = { id = "longest_streak", label = _("Longest streak"), icon = "streak",
        get = function(s) return num(s.longest_streak) end },
    reading_days = { id = "reading_days", label = _("Days read"), icon = "book_days",
        get = function(s) return num(s.reading_days) end },
    week_time = { id = "week_time", label = _("Read this week"), icon = "book_duration",
        get = function(s) return s.week_time and fmt_time(s.week_time) or "—" end },
    week_books = { id = "week_books", label = _("Books this week"),
        get = function(s) return num(s.week_books) end },
    month_sessions = { id = "month_sessions", label = _("Sessions this month"), icon = "book_days",
        get = function(s) return num(s.month_sessions) end },
    year_finished = { id = "year_finished", label = _("Finished this year"),
        get = function(s) return num(s.year_finished) end },
}

local OPTIONS = { "week_time", "streak", "year_finished", "longest_streak", "reading_days", "week_books", "month_sessions" }

local widget = base.make{
    id = "grimmory_stats",
    label = _("Grimmory reading stats"),
    fields = FIELDS,
    config_key = "middle_grimmory_stats",
    defaults = { "week_time", "streak", "year_finished" },
    stats = function()
        local get = rawget(_G, "__GZ_GRIMMORY_STATS")
        local ok, values = pcall(function() return get and get() end)
        return ok and type(values) == "table" and values or {}
    end,
}
widget.FIELDS = FIELDS
widget.OPTIONS = OPTIONS
return widget
