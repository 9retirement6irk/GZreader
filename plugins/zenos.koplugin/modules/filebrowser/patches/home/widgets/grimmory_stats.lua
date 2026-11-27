-- GZreader: reading stats from the book server, the same widget as the local
-- reading stats (stats_triplet.lua: notebook page, dividers, boxes…) with
-- numbers that count every device: the server (Grimmory or BookOrbit,
-- whichever this Kindle is signed in to) adds up what each device sends.
-- GZreader fetches them (gzreader_grimstats.lua) and keeps the last ones for
-- when it's offline. A tap opens the page with more (gzreader_statspage.lua).

local _ = require("gettext")
local base = require("modules/filebrowser/patches/home/widgets/stats_triplet")
local fmt_time = base.fmt_time

local function num(v) return v ~= nil and tostring(v) or "—" end
local function time(key) return function(s) return s[key] and fmt_time(s[key]) or "—" end end

-- GZreader: which server's numbers (asked each time: the sign-in can change)
local function server()
    local get = rawget(_G, "__GZ_BOOK_SERVER")
    local ok, name = pcall(function() return get and get() end)
    return ok and name == "bookorbit" and "bookorbit" or "grimmory"
end

local ALL = {
    streak = { id = "streak", label = _("Day streak"), tally = "streak", icon = "streak",
        get = function(s) return num(s.streak) end },
    longest_streak = { id = "longest_streak", label = _("Longest streak"), icon = "streak",
        get = function(s) return num(s.longest_streak) end },
    reading_days = { id = "reading_days", label = _("Days read"), icon = "book_days",
        get = function(s) return num(s.reading_days) end },
    week_time = { id = "week_time", label = _("Read this week"), icon = "book_duration", get = time("week_time") },
    week_books = { id = "week_books", label = _("Books this week"),
        get = function(s) return num(s.week_books) end },
    month_sessions = { id = "month_sessions", label = _("Sessions this month"), icon = "book_days",
        get = function(s) return num(s.month_sessions) end },
    year_finished = { id = "year_finished", label = _("Finished this year"),
        get = function(s) return num(s.year_finished) end },
    -- GZreader: BookOrbit's
    today_time = { id = "today_time", label = _("Read today"), icon = "book_duration", get = time("today_time") },
    month_time = { id = "month_time", label = _("Read this month"), icon = "book_duration", get = time("month_time") },
    year_time = { id = "year_time", label = _("Read this year"), icon = "book_duration", get = time("year_time") },
    year_days = { id = "year_days", label = _("Days read this year"), icon = "book_days",
        get = function(s) return num(s.year_days) end },
    goal = { id = "goal", label = _("Reading goal"), get = function(s) return num(s.goal) end },
    badges = { id = "badges", label = _("Badges"), get = function(s) return num(s.badges) end },
    library_books = { id = "library_books", label = _("Books in the library"),
        get = function(s) return num(s.library_books) end },
    reading_now = { id = "reading_now", label = _("Reading now"), get = function(s) return num(s.reading_now) end },
}

-- GZreader: what each server has (the same lists as gzreader_grimstats.lua's FIELDS)
local BY_SERVER = {
    grimmory = { "week_time", "streak", "year_finished", "longest_streak", "reading_days", "week_books", "month_sessions" },
    bookorbit = { "week_time", "streak", "year_finished", "longest_streak", "today_time", "month_time", "year_time", "year_days",
        "goal", "badges", "library_books", "reading_now" },
}

local function has(list, id)
    for _i, v in ipairs(list) do if v == id then return true end end
    return false
end

-- The fields of the server signed in to: a slot set to one the other server has
-- falls back to the widget's first default (build_stats does that for a missing id).
local FIELDS = setmetatable({}, { __index = function(_t, id)
    local f = ALL[id]
    return f and has(BY_SERVER[server()], id) and f or nil
end })

local widget = base.make{
    id = "grimmory_stats",
    label = _("Reading stats (every device)"),
    fields = FIELDS,
    config_key = "middle_grimmory_stats",
    defaults = { "week_time", "streak", "year_finished" },
    stats = function()
        local get = rawget(_G, "__GZ_GRIMMORY_STATS")
        local ok, values = pcall(function() return get and get() end)
        return ok and type(values) == "table" and values or {}
    end,
}

-- GZreader: a tap opens the reading stats page; a hold in edit mode, the widget's settings
local build = widget.build
widget.build = function(ctx)
    local body = build(ctx)
    -- (the 5-way: the widget picked and Press opens the page too; Settings has no Reading stats row)
    if type(ctx.setWidgetActions) == "function" then
        ctx.setWidgetActions{ activate = function()
            local open = rawget(_G, "__GZ_SERVER_STATS_PAGE")
            if not open then return false end
            pcall(open)
            return true
        end }
    end
    local Device = require("device")
    if not Device:isTouchDevice() then return body end
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Screen = Device.screen
    local whole = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local tap = InputContainer:new{
        dimen = Geom:new{ w = ctx.width, h = ctx.height },
        ges_events = {
            TapServerStats = { GestureRange:new{ ges = "tap", range = whole } },
            HoldServerStats = { GestureRange:new{ ges = "hold", range = whole } },
        },
    }
    tap.onTapServerStats = function(tap_self, _arg, ges)
        if not (tap_self.dimen and ges and ges.pos and tap_self.dimen:contains(ges.pos)) then return false end
        if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
        -- (not ctx.editMode: that's ZenOS's standing "hold a widget to change it",
        -- on by default, so a tap stopped here and the page never opened)
        local open = rawget(_G, "__GZ_SERVER_STATS_PAGE")
        if not open then return false end
        pcall(open)
        return true
    end
    tap.onHoldServerStats = function(tap_self, _arg, ges)
        if not (tap_self.dimen and ges and ges.pos and tap_self.dimen:contains(ges.pos)) then return false end
        if ctx.editMode and ctx.openWidgetSettings then return ctx.openWidgetSettings() end
        return false
    end
    tap[1] = body
    return tap
end

widget.FIELDS = FIELDS
widget.ALL = ALL
widget.BY_SERVER = BY_SERVER
-- (label and OPTIONS follow the server signed in to)
return setmetatable(widget, { __index = function(_t, key)
    if key == "OPTIONS" then return BY_SERVER[server()] end
end })
