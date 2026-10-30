--[[--
The Calendar tab: your CalDAV calendars (Nextcloud, iCloud, Fastmail,
Radicale, Baïkal, Google…), read-only, in four layouts.

- Agenda: the coming days' events in a list. Day: a timeline of one day.
  Week: seven columns. Month: a grid.
- Keys: letters (shown in squares) open an event, or a day in Week; Press
  opens what the 5-way is on (a day in Week and Month opens it in Day). The
  page keys (or ‹ ›) go to the next / previous day, week or month (Agenda:
  the next days). N today. M more: layouts, refresh, settings. Z, X, C, V,
  B switch the bottom tabs, as everywhere.
- Offline: the synced range of events is kept on the Kindle
  (gzreader-calendar.json); Wi-Fi is only used to sync: when the tab opens
  (at most every 15 minutes) and with M → Refresh.
- Settings → Connections → Calendar (CalDAV): connection, which calendars,
  default layout, week start, sync range, storage.

The tab is a KOReader Menu (so ZenOS puts its tab bar under it) whose page
is drawn here; ZenOS's status row is its title.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CalDAV = require("gzreader_caldav")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Calendar = {
    TAB_ID = "ct_calendar",
    SYNC_EVERY = 900, -- s: opening the tab syncs at most this often
    LAYOUTS = { "agenda", "day", "week", "month" },
    events = nil,      -- the synced events (cache, then fresh)
    cursor = nil,      -- the day (or week / month) shown
    history = {},      -- Agenda: where previous pages started
}

local LAYOUT_NAMES = { agenda = _("Agenda"), day = _("Day"), week = _("Week"), month = _("Month") }
Calendar.LAYOUT_NAMES = LAYOUT_NAMES
local KEYS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L" }
local MONTHS = { _("January"), _("February"), _("March"), _("April"), _("May"), _("June"), _("July"),
    _("August"), _("September"), _("October"), _("November"), _("December") }
local MON = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local WDAY = { _("Sun"), _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat") }
local WEEKDAY = { _("Sunday"), _("Monday"), _("Tuesday"), _("Wednesday"), _("Thursday"), _("Friday"), _("Saturday") }

local function info(text, timeout) UIManager:show(InfoMessage:new{ text = text, timeout = timeout }) end

---------------------------------------------------------------- settings and data

function Calendar.client(plugin)
    plugin.store.caldav = plugin.store.caldav or {}
    return CalDAV:new(plugin.store.caldav)
end

--- Settings → Connections → Calendar (kept when you disconnect).
function Calendar.prefs(plugin)
    plugin.store.calendar_prefs = plugin.store.calendar_prefs or {}
    local p = plugin.store.calendar_prefs
    p.layout = LAYOUT_NAMES[p.layout] and p.layout or "agenda"
    p.week_start = (p.week_start == 2) and 2 or 1 -- 1 Sunday, 2 Monday
    p.days_ahead = tonumber(p.days_ahead) or 90
    p.days_back = tonumber(p.days_back) or 14
    return p
end

---------------------------------------------------------------- dates

local function dayStart(t)
    local d = os.date("*t", t or os.time())
    return os.time{ year = d.year, month = d.month, day = d.day, hour = 0 }
end
Calendar.dayStart = dayStart

local function addDays(t, n)
    local d = os.date("*t", t)
    return os.time{ year = d.year, month = d.month, day = d.day + n, hour = 0 }
end
Calendar.addDays = addDays

local function addMonths(t, n)
    local d = os.date("*t", t)
    return os.time{ year = d.year, month = d.month + n, day = 1, hour = 0 }
end

local function weekStart(t, first)
    local wd = os.date("*t", t).wday
    return addDays(dayStart(t), -((wd - first) % 7))
end
Calendar.weekStart = weekStart

local function clock(t)
    local d = os.date("*t", t)
    local h = d.hour % 12 == 0 and 12 or d.hour % 12
    return string.format("%d:%02d %s", h, d.min, d.hour < 12 and "AM" or "PM")
end

local function shortClock(t) -- "9a", "2:30p"
    local d = os.date("*t", t)
    local h = d.hour % 12 == 0 and 12 or d.hour % 12
    return (d.min == 0 and tostring(h) or string.format("%d:%02d", h, d.min)) .. (d.hour < 12 and "a" or "p")
end

local function dayLabel(t, today)
    local d = os.date("*t", t)
    local base = WDAY[d.wday] .. " " .. MON[d.month] .. " " .. d.day
    if t == today then return _("Today") .. " \u{00B7} " .. base end
    if t == addDays(today, 1) then return _("Tomorrow") .. " \u{00B7} " .. base end
    return base
end

--- Events on a day (an event spanning days shows on each).
function Calendar.eventsOn(day)
    local nextday = addDays(day, 1)
    local out = {}
    for _i, ev in ipairs(Calendar.events or {}) do
        local finish = math.max(ev.finish or ev.start, ev.start + 1)
        if ev.start < nextday and finish > day then out[#out + 1] = ev end
    end
    return out
end

--- When an event happens, said simply.
function Calendar.when(ev)
    local d0 = dayStart(ev.start)
    if ev.all_day then
        local last = addDays(dayStart(math.max(ev.finish - 1, ev.start)), 0)
        if last <= d0 then return dayLabel(d0, dayStart()) .. " \u{00B7} " .. _("all day") end
        return dayLabel(d0, dayStart()) .. " \u{2013} " .. dayLabel(last, dayStart())
    end
    local same = dayStart(ev.finish) == d0
    return dayLabel(d0, dayStart()) .. " \u{00B7} " .. clock(ev.start) .. " \u{2013} "
        .. (same and clock(ev.finish) or (dayLabel(dayStart(ev.finish), dayStart()) .. " " .. clock(ev.finish)))
end

--- Calendar links (webcal / ICS): { {url, name, own_name, enabled} }.
function Calendar.feeds(plugin)
    plugin.store.calendar_feeds = plugin.store.calendar_feeds or {}
    return plugin.store.calendar_feeds
end

function Calendar.feedName(feed)
    if feed.name and feed.name ~= "" then return feed.name end
    if feed.own_name and feed.own_name ~= "" then return feed.own_name end
    return (feed.url or ""):match("^https?://([^/?#]+)") or _("Calendar link")
end

--- Anything to show: a CalDAV account or calendar links.
function Calendar.hasSources(plugin)
    return Calendar.client(plugin):isConnected() or #Calendar.feeds(plugin) > 0
end

--- All calendars, as events number them: the CalDAV account's, then the links.
--- { {name, enabled, kind = "caldav" | "link", ref = the stored entry} }
function Calendar.calendars(plugin)
    local out = {}
    for _i, c in ipairs((plugin.store.caldav or {}).calendars or {}) do
        out[#out + 1] = { name = c.name, kind = "caldav", ref = c }
    end
    for _i, f in ipairs(Calendar.feeds(plugin)) do
        out[#out + 1] = { name = Calendar.feedName(f), kind = "link", ref = f }
    end
    return out
end

function Calendar.calName(plugin, ev)
    local cal = Calendar.calendars(plugin)[ev.cal or 0]
    return cal and cal.name or ""
end

-- Calendars told apart by shade (e-ink): black, dark gray, gray, light.
local SHADES = { 1.0, 0.7, 0.45, 0.25 }
local function shade(ev)
    return Blitbuffer.gray(SHADES[((ev.cal or 1) - 1) % #SHADES + 1])
end

---------------------------------------------------------------- sync

function Calendar.loadCache()
    local cache = CalDAV.loadCache()
    Calendar.events = cache and cache.events or {}
    Calendar.range = cache and { from = cache.from, to = cache.to } or nil
    Calendar.cached_at = cache and cache.at
end

--- Fetch the chosen calendars' events for the sync range. on_done(ok, err).
function Calendar.refresh(plugin, on_done)
    if not Calendar.hasSources(plugin) then return on_done and on_done(false, "not_connected") end
    if Calendar.refreshing then return end
    Calendar.refreshing = true
    local prefs = Calendar.prefs(plugin)
    local today = dayStart()
    local from, to = addDays(today, -prefs.days_back), addDays(today, prefs.days_ahead + 1)
    local caldav_store = plugin.store.caldav or {}
    local feeds = Calendar.feeds(plugin)
    require("gzreader_async").run({}, function()
        return CalDAV.syncAll(caldav_store, feeds, from, to)
    end, function(res, err)
        Calendar.refreshing = false
        if type(res) ~= "table" then
            Log.warn("calendar: sync failed:", tostring(err))
            Calendar.last_error = err
            return on_done and on_done(false, err)
        end
        Calendar.last_error = nil
        local renamed = false
        for _i, n in ipairs(res.names or {}) do
            local f = feeds[tonumber(n.index) or 0]
            if f and f.own_name ~= n.name then f.own_name = n.name; renamed = true end
        end
        if renamed then plugin:save() end
        Calendar.events = res.events or {}
        Calendar.range = { from = from, to = to }
        Calendar.cached_at = os.time()
        Calendar.failed = res.failed
        CalDAV.saveCache({ at = Calendar.cached_at, from = from, to = to, events = Calendar.events })
        Log.info("calendar: synced", #Calendar.events, "events")
        if on_done then on_done(true) end
    end, "calendar: sync", { timeout = 180 })
end

local function describe(err)
    if err == "unauthorized" then return _("The calendar server didn't accept the user name or password. Connect again (M → Settings).") end
    if err == "unreachable" then return _("Couldn't reach the calendar server. Check Wi-Fi and the address.") end
    if err == "timeout" then return _("The calendar server took too long to answer.") end
    if err == "not_connected" then return _("Not connected to a calendar.") end
    if err == "gone" then return _("A calendar link no longer works (the calendar was unshared or the link changed).") end
    if err == "not a calendar" then return _("That link doesn't lead to a calendar (.ics).") end
    return T(_("The calendar server answered: %1"), tostring(err))
end
Calendar.describe = describe

--- Sync when the tab opens (quietly; Wi-Fi only when needed turns it on and
--- off again), unless it synced in the last 15 minutes.
function Calendar.syncOnOpen(plugin)
    if Calendar.cached_at and os.time() - Calendar.cached_at < Calendar.SYNC_EVERY then return end
    require("gzreader_net").run(function()
        Calendar.refresh(plugin, function(_ok, err)
            Calendar.redraw()
            if err == "unauthorized" then info(describe(err)) end
        end)
    end, { quiet = true, reason = "calendar" })
end

---------------------------------------------------------------- drawing helpers

--- Widgets at fixed places (for the Day timeline and the grids).
local Canvas = WidgetContainer:extend{ width = 0, height = 0 }

function Canvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.pos = {}
end

function Canvas:place(widget, x, y)
    self[#self + 1] = widget
    self.pos[#self] = { x = x, y = y }
    return widget
end

function Canvas:getSize() return self.dimen end

function Canvas:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    for i, w in ipairs(self) do
        local p = self.pos[i]
        w:paintTo(bb, x + p.x, y + p.y)
    end
end

--- A line (horizontal or vertical) of a shade.
local Line = WidgetContainer:extend{ w = 1, h = 1, color = nil }
function Line:getSize() return Geom:new{ w = self.w, h = self.h } end
function Line:paintTo(bb, x, y) bb:paintRect(x, y, self.w, self.h, self.color or Blitbuffer.COLOR_DARK_GRAY) end

--- Something the 5-way can stop on and Press / a letter opens.
local CalItem = InputContainer:extend{ w = 0, h = 0, build = nil, callback = nil, shortcut = nil, focused = false }

function CalItem:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
    self.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    self[1] = self.build(false)
end

function CalItem:getSize() return Geom:new{ w = self.w, h = self.h } end

function CalItem:redraw(focused)
    if self.focused == focused then return true end
    self.focused = focused
    if self[1] and self[1].free then self[1]:free() end
    self[1] = self.build(focused)
    return true
end

function CalItem:onFocus() return self:redraw(true) end
function CalItem:onUnfocus() return self:redraw(false) end

function CalItem:onTapSelect()
    if self.callback then self.callback() end
    return true
end

local function badge(letter, side)
    if not letter then return nil end
    return Menu.getItemShortCutIcon(nil, Geom:new{ w = side, h = side }, letter, "square")
end

--- Event details (title, when, calendar, place, notes).
function Calendar.showEvent(plugin, ev)
    local lines = { Calendar.when(ev) }
    local cal = Calendar.calName(plugin, ev)
    if cal ~= "" then lines[#lines + 1] = T(_("Calendar: %1"), cal) end
    if ev.location and ev.location ~= "" then lines[#lines + 1] = T(_("Where: %1"), ev.location) end
    if ev.repeats then lines[#lines + 1] = _("Repeats") end
    if ev.notes and ev.notes ~= "" then lines[#lines + 1] = "\n" .. ev.notes end
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{
        title = ev.title or _("(no title)"),
        text = table.concat(lines, "\n"),
        justified = false,
    })
end

---------------------------------------------------------------- layouts

--- One line of an event in a list: [letter] time · marker · title / place.
local function eventRow(plugin, ev, day, w, h, key)
    local time_w = S(92)
    local build = function(focused)
        local timeText, endText
        if ev.all_day or (ev.start < day and ev.finish > addDays(day, 1)) then timeText = _("All day")
        else
            timeText = ev.start < day and ("\u{2192} " .. clock(ev.finish)) or clock(ev.start)
            endText = (ev.start >= day and dayStart(ev.finish) == day and ev.finish > ev.start) and clock(ev.finish) or nil
        end
        local bsize = S(24)
        local b = badge(key, bsize)
        local inner = w - 2 * Size.border.thick
        local text_w = inner - bsize - S(8) - time_w - S(18)
        local title = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = ev.title or _("(no title)"), face = Font:getFace("cfont", 18), bold = true, max_width = text_w } }
        if ev.location and ev.location ~= "" then
            title[#title + 1] = TextWidget:new{ text = ev.location, face = Font:getFace("cfont", 13),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = text_w }
        end
        local times = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = timeText, face = Font:getFace("cfont", 15), max_width = time_w } }
        if endText then
            times[#times + 1] = TextWidget:new{ text = endText, face = Font:getFace("cfont", 12),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = time_w }
        end
        return FrameContainer:new{
            width = w, height = h, padding = 0, margin = 0,
            bordersize = focused and Size.border.thick or 0,
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = h - 2 * (focused and Size.border.thick or 0) },
                HorizontalGroup:new{ align = "center",
                    HorizontalSpan:new{ width = S(4) },
                    b or HorizontalSpan:new{ width = bsize },
                    HorizontalSpan:new{ width = S(8) },
                    LeftContainer:new{ dimen = Geom:new{ w = time_w, h = h - S(6) }, times },
                    FrameContainer:new{ padding = 0, bordersize = 0, background = shade(ev), width = S(6), height = h - S(16),
                        VerticalSpan:new{ width = 1 } },
                    HorizontalSpan:new{ width = S(12) },
                    title,
                } },
        }
    end
    return CalItem:new{ w = w, h = h, build = build, shortcut = key,
        callback = function() Calendar.showEvent(plugin, ev) end }
end

local function message(canvas, w, text)
    canvas:place(CenterContainer:new{ dimen = Geom:new{ w = w, h = S(160) },
        TextBoxWidget:new{ text = text, face = Font:getFace("cfont", 18), width = w - S(60), alignment = "center" } }, 0, S(40))
end

local function inRange(day)
    local r = Calendar.range
    return r and day >= dayStart(r.from) and day < r.to
end

local function outOfRangeText()
    return _("Not synced this far.\n\nSettings → Connections → Calendar → Sync range sets how far ahead and back events are kept.")
end

--- Agenda: days with events from the cursor on, as many as fit.
local function renderAgenda(plugin, w, h)
    local canvas = Canvas:new{ width = w, height = h }
    local layout, items = {}, {}
    local today = dayStart()
    local y, k = S(4), 0
    local head_h, row_h = S(30), S(52)
    local day = Calendar.cursor
    local last = day
    local stop = Calendar.range and Calendar.range.to or addDays(day, 60)
    local shown = 0
    while day < stop and y + head_h + row_h <= h do
        local evs = Calendar.eventsOn(day)
        if #evs > 0 then
            local head = dayLabel(day, today)
            canvas:place(FrameContainer:new{ width = w, height = head_h, padding = 0, bordersize = 0,
                background = day == today and Blitbuffer.COLOR_LIGHT_GRAY or nil,
                LeftContainer:new{ dimen = Geom:new{ w = w, h = head_h },
                    HorizontalGroup:new{ HorizontalSpan:new{ width = S(8) },
                        TextWidget:new{ text = head, face = Font:getFace("smalltfont", 17), bold = true } } } }, 0, y)
            y = y + head_h
            for _i, ev in ipairs(evs) do
                if y + row_h > h then break end
                k = k + 1
                local item = eventRow(plugin, ev, day, w, row_h, KEYS[k])
                canvas:place(item, 0, y)
                layout[#layout + 1] = { item }
                items[#items + 1] = item
                y = y + row_h
                shown = shown + 1
            end
            canvas:place(Line:new{ w = w - S(16), h = 1, color = Blitbuffer.COLOR_LIGHT_GRAY }, S(8), y + S(3))
            y = y + S(8)
        end
        last = day
        day = addDays(day, 1)
    end
    Calendar.agenda_next = addDays(last, 1)
    if shown == 0 then
        message(canvas, w, inRange(Calendar.cursor) and _("No events in the days ahead.\n\nM → Refresh to sync again.") or outOfRangeText())
    end
    return canvas, layout, items
end

--- Columns for overlapping events (greedy).
local function columns(evs)
    local cols, ends = {}, {}
    local groups, gmax, gend = {}, 0, -1
    local group = {}
    for _i, ev in ipairs(evs) do
        if ev.start >= gend and #group > 0 then
            for _j, e in ipairs(group) do groups[e] = gmax end
            group, gmax, ends = {}, 0, {}
        end
        local c = 1
        while ends[c] and ends[c] > ev.start do c = c + 1 end
        ends[c] = ev.finish
        cols[ev] = c
        gmax = math.max(gmax, c)
        gend = math.max(gend, ev.finish)
        group[#group + 1] = ev
    end
    for _j, e in ipairs(group) do groups[e] = gmax end
    return cols, groups
end

--- Day: all-day events on top, then a timeline.
local function renderDay(plugin, w, h)
    local canvas = Canvas:new{ width = w, height = h }
    local layout, items = {}, {}
    local day = Calendar.cursor
    if not inRange(day) then message(canvas, w, outOfRangeText()); return canvas, layout, items end
    local evs = Calendar.eventsOn(day)
    local allday, timed = {}, {}
    for _i, ev in ipairs(evs) do
        if ev.all_day or (ev.start <= day and ev.finish >= addDays(day, 1)) then allday[#allday + 1] = ev else timed[#timed + 1] = ev end
    end
    local k, y = 0, S(4)
    for _i, ev in ipairs(allday) do
        k = k + 1
        local item = eventRow(plugin, ev, day, w, S(40), KEYS[k])
        canvas:place(item, 0, y)
        layout[#layout + 1] = { item }
        items[#items + 1] = item
        y = y + S(42)
    end
    -- the hours shown: 7 AM to 9 PM, wider if events need it
    local h0, h1 = 7, 21
    for _i, ev in ipairs(timed) do
        local s = os.date("*t", math.max(ev.start, day))
        local e = os.date("*t", math.min(ev.finish, addDays(day, 1) - 1))
        h0 = math.min(h0, s.hour)
        h1 = math.max(h1, e.hour + (e.min > 0 and 1 or 0))
    end
    local top = y + S(6)
    local label_w = S(54)
    local px = (h - top - S(6)) / math.max(1, h1 - h0)
    for hr = h0, h1 do
        local ly = top + math.floor((hr - h0) * px)
        canvas:place(Line:new{ w = w - label_w, h = 1, color = Blitbuffer.COLOR_LIGHT_GRAY }, label_w, ly)
        if hr < h1 then
            local lab = (hr % 12 == 0 and 12 or hr % 12) .. (hr < 12 and " AM" or " PM")
            canvas:place(TextWidget:new{ text = lab, face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.COLOR_DARK_GRAY },
                S(4), ly + S(2))
        end
    end
    -- now
    local now = os.time()
    if day == dayStart(now) then
        local nd = os.date("*t", now)
        local hours = nd.hour + nd.min / 60
        if hours >= h0 and hours <= h1 then
            canvas:place(Line:new{ w = w - label_w, h = S(2), color = Blitbuffer.COLOR_BLACK }, label_w, top + math.floor((hours - h0) * px))
        end
    end
    table.sort(timed, function(a, b) return a.start < b.start end)
    local cols, groups = columns(timed)
    local area_w = w - label_w - S(4)
    for _i, ev in ipairs(timed) do
        local s = math.max(ev.start, day)
        local e = math.min(ev.finish, addDays(day, 1))
        local sd, ed = os.date("*t", s), os.date("*t", e)
        local sh = (s >= addDays(day, 1)) and h1 or (sd.hour + sd.min / 60)
        local eh = (e >= addDays(day, 1)) and 24 or (ed.hour + ed.min / 60)
        local by = top + math.floor((sh - h0) * px) + 1
        local bh = math.max(S(30), math.floor((math.min(eh, h1) - sh) * px) - 2)
        local n = groups[ev] or 1
        local bw = math.floor(area_w / n) - S(3)
        local bx = label_w + S(2) + (cols[ev] - 1) * (bw + S(3))
        k = k + 1
        local key = KEYS[k]
        local build = function(focused)
            local bsize = math.min(S(22), bh - S(6))
            local b = bsize >= S(14) and badge(key, bsize) or nil
            local inner_w = bw - S(12) - (b and (bsize + S(4)) or 0)
            local label = clock(ev.start) .. "  " .. (ev.title or "")
            return FrameContainer:new{
                width = bw, height = bh, padding = S(3), margin = 0,
                bordersize = focused and Size.border.thick or Size.border.thin,
                background = Blitbuffer.COLOR_WHITE,
                HorizontalGroup:new{ align = "top",
                    FrameContainer:new{ padding = 0, bordersize = 0, background = shade(ev), width = S(5),
                        height = bh - S(8) - 2 * Size.border.thick, VerticalSpan:new{ width = 1 } },
                    HorizontalSpan:new{ width = S(4) },
                    b or HorizontalSpan:new{ width = 0 },
                    HorizontalSpan:new{ width = b and S(4) or 0 },
                    TextBoxWidget:new{ text = label, face = Font:getFace("cfont", 14), width = math.max(S(20), inner_w),
                        height = math.max(S(16), bh - S(10)), height_adjust = false, height_overflow_show_ellipsis = true,
                        bold = false },
                },
            }
        end
        local item = CalItem:new{ w = bw, h = bh, build = build, shortcut = key,
            callback = function() Calendar.showEvent(plugin, ev) end }
        canvas:place(item, bx, by)
        layout[#layout + 1] = { item }
        items[#items + 1] = item
    end
    if #evs == 0 then
        canvas:place(CenterContainer:new{ dimen = Geom:new{ w = w - label_w, h = S(40) },
            TextWidget:new{ text = _("Nothing planned"), face = Font:getFace("cfont", 16), fgcolor = Blitbuffer.COLOR_DARK_GRAY } },
            label_w, top + math.floor((12 - h0) * px) - S(20))
    end
    return canvas, layout, items
end

--- A cell with a day's events as short lines (Week, Month).
local function dayCell(plugin, day, w, h, opts)
    local today = dayStart()
    local key = opts.key
    local build = function(focused)
        local evs = Calendar.eventsOn(day)
        local d = os.date("*t", day)
        local g = VerticalGroup:new{ align = "left" }
        local num = opts.week and (WDAY[d.wday] .. " " .. d.day) or tostring(d.day)
        local is_today = day == today
        local head = HorizontalGroup:new{ align = "center" }
        if key then
            head[#head + 1] = badge(key, S(20))
            head[#head + 1] = HorizontalSpan:new{ width = S(4) }
        end
        head[#head + 1] = FrameContainer:new{ padding = S(1), padding_left = S(3), padding_right = S(3), bordersize = 0,
            background = is_today and Blitbuffer.COLOR_BLACK or nil,
            TextWidget:new{ text = num, face = Font:getFace("cfont", opts.week and 14 or 15), bold = true,
                fgcolor = is_today and Blitbuffer.COLOR_WHITE or (opts.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK) } }
        g[1] = head
        g[2] = VerticalSpan:new{ width = S(2) }
        local line_h = S(opts.week and 34 or 16)
        local room = math.max(0, math.floor((h - S(28)) / line_h))
        local fsize = opts.week and 12 or 11
        for i, ev in ipairs(evs) do
            if i > room or (i == room and #evs > room) then
                g[#g + 1] = TextWidget:new{ text = T(_("+%1 more"), #evs - i + 1), face = Font:getFace("cfont", fsize),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w - S(6) }
                break
            end
            local t = (ev.all_day or ev.start < day) and "" or (shortClock(ev.start) .. " ")
            if opts.week then
                g[#g + 1] = HorizontalGroup:new{ align = "top",
                    FrameContainer:new{ padding = 0, bordersize = 0, background = shade(ev), width = S(3), height = line_h - S(4),
                        VerticalSpan:new{ width = 1 } },
                    HorizontalSpan:new{ width = S(2) },
                    TextBoxWidget:new{ text = t .. (ev.title or ""), face = Font:getFace("cfont", fsize), width = w - S(12),
                        height = line_h - S(2), height_adjust = false, height_overflow_show_ellipsis = true } }
            else
                g[#g + 1] = HorizontalGroup:new{ align = "center",
                    FrameContainer:new{ padding = 0, bordersize = 0, background = shade(ev), width = S(3), height = line_h - S(4),
                        VerticalSpan:new{ width = 1 } },
                    HorizontalSpan:new{ width = S(2) },
                    TextWidget:new{ text = t .. (ev.title or ""), face = Font:getFace("cfont", fsize), max_width = w - S(10) } }
            end
        end
        return FrameContainer:new{
            width = w, height = h, padding = S(2), margin = 0,
            bordersize = focused and Size.border.thick or Size.border.thin,
            color = focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            g,
        }
    end
    return CalItem:new{ w = w, h = h, build = build, shortcut = key, callback = function()
        Calendar.cursor = day
        Calendar.setLayout(plugin, "day", true)
    end }
end

--- Week: seven columns.
local function renderWeek(plugin, w, h)
    local canvas = Canvas:new{ width = w, height = h }
    local layout, items = { {} }, {}
    local first = weekStart(Calendar.cursor, Calendar.prefs(plugin).week_start)
    if not inRange(first) and not inRange(addDays(first, 6)) then message(canvas, w, outOfRangeText()); return canvas, {}, items end
    local cw = math.floor(w / 7)
    for i = 0, 6 do
        local day = addDays(first, i)
        local cell = dayCell(plugin, day, cw, h - S(4), { week = true, key = KEYS[i + 1] })
        canvas:place(cell, i * cw, S(2))
        table.insert(layout[1], cell)
        items[#items + 1] = cell
    end
    return canvas, layout, items
end

--- Month: a grid of the weeks in the month.
local function renderMonth(plugin, w, h)
    local canvas = Canvas:new{ width = w, height = h }
    local layout, items = {}, {}
    local first_day = addMonths(Calendar.cursor, 0)
    local start = weekStart(first_day, Calendar.prefs(plugin).week_start)
    local month = os.date("*t", first_day).month
    local weeks = math.ceil((((os.date("*t", first_day).wday - Calendar.prefs(plugin).week_start) % 7)
        + os.date("*t", addDays(addMonths(first_day, 1), -1)).day) / 7)
    local cw = math.floor(w / 7)
    local head_h = S(22)
    for i = 0, 6 do
        local wd = (Calendar.prefs(plugin).week_start - 1 + i) % 7 + 1
        canvas:place(CenterContainer:new{ dimen = Geom:new{ w = cw, h = head_h },
            TextWidget:new{ text = WDAY[wd], face = Font:getFace("cfont", 13), bold = true } }, i * cw, 0)
    end
    local ch = math.floor((h - head_h - S(2)) / weeks)
    for r = 0, weeks - 1 do
        local row = {}
        for c = 0, 6 do
            local day = addDays(start, r * 7 + c)
            local cell = dayCell(plugin, day, cw, ch, { dim = os.date("*t", day).month ~= month })
            canvas:place(cell, c * cw, head_h + r * ch)
            row[#row + 1] = cell
            items[#items + 1] = cell
        end
        layout[#layout + 1] = row
    end
    if not inRange(first_day) and not inRange(addDays(addMonths(first_day, 1), -1)) then
        canvas:place(FrameContainer:new{ padding = S(10), bordersize = Size.border.thin, background = Blitbuffer.COLOR_WHITE,
            TextBoxWidget:new{ text = outOfRangeText(), face = Font:getFace("cfont", 15), width = w - S(100) } }, S(40), S(120))
    end
    return canvas, layout, items
end

local RENDER = { agenda = renderAgenda, day = renderDay, week = renderWeek, month = renderMonth }

--- What the page shows, for the bar at the bottom.
function Calendar.periodLabel(plugin)
    local layout = Calendar.layout or Calendar.prefs(plugin).layout
    local c = Calendar.cursor
    local d = os.date("*t", c)
    if layout == "day" then return WEEKDAY[d.wday] .. ", " .. MONTHS[d.month] .. " " .. d.day end
    if layout == "month" then return MONTHS[d.month] .. " " .. d.year end
    if layout == "week" then
        local first = weekStart(c, Calendar.prefs(plugin).week_start)
        local last = addDays(first, 6)
        local a, b = os.date("*t", first), os.date("*t", last)
        if a.month == b.month then return MON[a.month] .. " " .. a.day .. " \u{2013} " .. b.day end
        return MON[a.month] .. " " .. a.day .. " \u{2013} " .. MON[b.month] .. " " .. b.day
    end
    return T(_("Agenda from %1"), dayLabel(c, dayStart()))
end

---------------------------------------------------------------- the tab

local function drawBoard(m)
    local old_dimen = m.dimen and m.dimen:copy()
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    m.items_per_page = 1
    m:_recalculateDimen(false)
    local w, h = m.item_dimen.w, m.available_height
    local layout = Calendar.layout or Calendar.prefs(m.plugin).layout
    -- what's shown (ZenOS hides KOReader's page bar on single-page tab views)
    local head_h = S(34)
    local head = FrameContainer:new{ width = w, height = head_h, padding = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = w, h = head_h },
            HorizontalGroup:new{ align = "center",
                TextWidget:new{ text = "\u{25C0}", face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY },
                HorizontalSpan:new{ width = S(16) },
                TextWidget:new{ text = Calendar.periodLabel(m.plugin), face = Font:getFace("smalltfont", 19), bold = true,
                    max_width = w - S(90) },
                HorizontalSpan:new{ width = S(16) },
                TextWidget:new{ text = "\u{25B6}", face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY },
            } } }
    local canvas, focus, items = RENDER[layout](m.plugin, w, h - head_h)
    m.item_group[1] = VerticalGroup:new{ align = "left", head, canvas }
    m.layout = focus
    m.cal_items = items
    m.page, m.page_num = 1, 1
    if #focus > 0 then
        pcall(m.updatePageInfo, m, 1)
    end
    -- the bar at the bottom: what's shown, ‹ › go back and forth
    pcall(function()
        m.page_info_text:setText(Calendar.periodLabel(m.plugin))
        m.page_info_text:enable()
        m.page_info_left_chev:show(); m.page_info_left_chev:enable()
        m.page_info_right_chev:show(); m.page_info_right_chev:enable()
        if m.page_info_first_chev then m.page_info_first_chev:hide() end
        if m.page_info_last_chev then m.page_info_last_chev:hide() end
        m.page_info:resetLayout()
    end)
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
end

Calendar.Board = Menu:extend{}

function Calendar.Board:updateItems() return drawBoard(self) end

function Calendar.Board:onNextPage() Calendar.move(self.plugin, 1); return true end
function Calendar.Board:onPrevPage() Calendar.move(self.plugin, -1); return true end
function Calendar.Board:onGotoPage() return true end
function Calendar.Board:onFirstPage() return true end
function Calendar.Board:onLastPage() return true end

function Calendar.Board:onSelectByShortCut(_arg, keyevent)
    local k = keyevent and keyevent.key
    if k == "N" then Calendar.today(self.plugin); return true end
    if k == "M" then Calendar.showOptions(self.plugin); return true end
    for _i, item in ipairs(self.cal_items or {}) do
        if item.shortcut == k then item:onTapSelect(); return true end
    end
    return true
end

function Calendar.Board:onMenuSelect() return true end

function Calendar.redraw()
    local b = Calendar.board
    if b and not b._gz_closed then b:updateItems() end
end

--- ◀ ▶: the next / previous day, week or month (Agenda: the next days).
function Calendar.move(plugin, dir)
    local layout = Calendar.layout or Calendar.prefs(plugin).layout
    local c = Calendar.cursor
    if layout == "day" then Calendar.cursor = addDays(c, dir)
    elseif layout == "week" then Calendar.cursor = addDays(c, 7 * dir)
    elseif layout == "month" then Calendar.cursor = addMonths(c, dir)
    else
        if dir > 0 then
            table.insert(Calendar.history, c)
            Calendar.cursor = Calendar.agenda_next or addDays(c, 7)
        else
            Calendar.cursor = table.remove(Calendar.history) or addDays(c, -7)
        end
    end
    Calendar.redraw()
end

function Calendar.today(plugin)
    local layout = Calendar.layout or Calendar.prefs(plugin).layout
    Calendar.cursor = layout == "month" and addMonths(dayStart(), 0) or dayStart()
    Calendar.history = {}
    Calendar.redraw()
end

--- Switch layouts (keep the day you're on; a month shows its first day's month).
function Calendar.setLayout(plugin, layout, keep_day)
    Calendar.layout = layout
    Calendar.history = {}
    if layout == "month" then Calendar.cursor = addMonths(Calendar.cursor or dayStart(), 0)
    elseif not keep_day and (Calendar.cursor or 0) < dayStart() and layout ~= "day" then Calendar.cursor = dayStart() end
    Calendar.redraw()
end

function Calendar.keyedDialog(title, rows)
    local dialog = ButtonDialog:new{ title = title, buttons = rows }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

function Calendar.showOptions(plugin)
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    local cur = Calendar.layout or Calendar.prefs(plugin).layout
    local rows = {}
    for _i, id in ipairs(Calendar.LAYOUTS) do
        rows[#rows + 1] = { { text = LAYOUT_NAMES[id] .. (cur == id and "  \u{2713}" or ""), align = "left",
            callback = run(function() Calendar.setLayout(plugin, id) end) } }
    end
    rows[#rows + 1] = { { text = _("Today"), align = "left", callback = run(function() Calendar.today(plugin) end) } }
    rows[#rows + 1] = { { text = _("Refresh"), align = "left", callback = run(function()
        require("gzreader_net").run(function()
            Calendar.refresh(plugin, function(ok, err)
                Calendar.redraw()
                if not ok then info(describe(err)) end
            end)
        end, { reason = "calendar" })
    end) } }
    rows[#rows + 1] = { { text = _("Calendar settings"), align = "left", callback = run(function() Calendar.showSettings(plugin) end) } }
    local synced = Calendar.cached_at and T(_("Synced %1"), os.date("%b %d, ", Calendar.cached_at) .. clock(Calendar.cached_at)) or _("Not synced yet")
    dialog = Calendar.keyedDialog(_("Calendar") .. "\n" .. synced, rows)
end

--- Settings → Connections → Calendar, from the tab (M → Calendar settings).
--- Built like KOReader's file manager menu: one tab (it needs an icon) in a
--- centered container.
function Calendar.showSettings(plugin)
    local TouchMenu = require("ui/widget/touchmenu")
    local container = CenterContainer:new{ ignore = "height", dimen = Screen:getSize() }
    local items = Calendar.settingsItems(plugin)
    items.icon = "appbar.settings"
    local menu = TouchMenu:new{
        width = Screen:getWidth(),
        last_index = 1,
        tab_item_table = { items },
        show_parent = container,
    }
    container[1] = menu
    menu.close_callback = function()
        UIManager:close(container)
        Calendar.redraw()
    end
    UIManager:show(container)
end

--- The Calendar tab (the tab bar's Calendar button).
function Calendar.show(plugin)
    require("gzreader_tabs").closeOthers(Calendar.TAB_ID)
    if Calendar.board and not Calendar.board._gz_closed then
        Calendar.redraw()
        return Calendar.board
    end
    if not Calendar.hasSources(plugin) then return Calendar.showConnect(plugin) end
    if not Calendar.events then Calendar.loadCache() end
    Calendar.layout = Calendar.layout or Calendar.prefs(plugin).layout
    if not Calendar.cursor then
        Calendar.cursor = Calendar.layout == "month" and addMonths(dayStart(), 0) or dayStart()
    end
    local menu = Calendar.Board:new{
        title = _("Calendar"),
        subtitle = _("N today  \u{00B7}  M more  \u{00B7}  \u{25C0} \u{25B6} page keys"),
        item_table = { { text = "" } },
        covers_fullscreen = true, is_borderless = true, is_popout = false, title_bar_fm_style = true,
        _gz_navbar_tab_id = Calendar.TAB_ID,
        plugin = plugin,
    }
    menu.key_events.LeftButtonTap = nil
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        m._gz_closed = true
        if Calendar.board == m then Calendar.board = nil end
        if orig_close then return orig_close(m, ...) end
    end
    Calendar.board = menu
    menu:updateItems()
    pcall(require("gzreader_tabs").decorate, menu, _("Calendar"))
    UIManager:show(menu)
    Calendar.syncOnOpen(plugin)
    return menu
end

---------------------------------------------------------------- connecting

--- Check an address, user name and password, find the calendars, keep them.
--- Returns ok, err (to show).
function Calendar.connect(plugin, server_input, username, password)
    local server = CalDAV.normalizeServer(server_input)
    username = (username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not server then return false, _("That address doesn't look right.") end
    if username == "" or not password or password == "" then return false, _("Enter your user name and password (an app password if your server has them).") end
    local found, err = CalDAV:new{ server = server, username = username, password = password }:discover()
    if not found and err == "unreachable" and not server_input:match("^%s*https?://") then
        local plain = server:gsub("^https://", "http://")
        local t2 = CalDAV:new{ server = plain, username = username, password = password }
        local f2, e2 = t2:discover()
        if f2 or e2 ~= "unreachable" then found, err, server = f2, e2, plain end
    end
    Log.info("calendar: connecting to", server, found and (#found.calendars .. " calendars") or ("failed: " .. tostring(err)))
    if not found then
        if err == "unauthorized" then return false, _("The server didn't accept that user name and password.") end
        if err == "unreachable" then return false, _("Couldn't reach a server at that address.") end
        return false, T(_("No calendars found there (%1)."), tostring(err))
    end
    if #found.calendars == 0 then return false, _("Signed in, but there are no calendars with events in this account.") end
    local old = plugin.store.caldav or {}
    local enabled = {}
    for _i, c in ipairs(old.calendars or {}) do enabled[c.href] = c.enabled end
    for _i, c in ipairs(found.calendars) do
        if old.server == server and enabled[c.href] ~= nil then c.enabled = enabled[c.href] else c.enabled = true end
    end
    plugin.store.caldav = { server = server, username = username, password = password, home = found.home,
        calendars = found.calendars }
    plugin:save()
    if old.server ~= server or old.username ~= username then
        os.remove(CalDAV.cachePath())
        Calendar.events, Calendar.cached_at, Calendar.range = nil, nil, nil
    end
    return true
end

local function connected(plugin)
    if Calendar.connect_menu then UIManager:close(Calendar.connect_menu); Calendar.connect_menu = nil end
    if Calendar.board then UIManager:close(Calendar.board) end
    local n = #((plugin.store.caldav or {}).calendars or {})
    info(T(_("Connected: %1 calendars."), n), 3)
    Calendar.cached_at = nil
    Calendar.show(plugin)
end

---------------------------------------------------------------- calendar links

--- "Name | link" or "link" lines (blank lines and # comments skipped): { {url, name} }.
function Calendar.parseLinkLines(text)
    local out = {}
    for line in ((text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            local name, url = line:match("^(.-)%s*|%s*(%S+)$")
            if not url then url = line end
            out[#out + 1] = { url = url, name = (name and name ~= "") and name or nil }
        end
    end
    return out
end

--- Add calendar links, checking each by fetching it (on the screen's
--- thread: from the phone page, typing or calendars.txt).
--- Returns results { {label, ok, name, count, err} }.
function Calendar.addFeeds(plugin, entries)
    local feeds = Calendar.feeds(plugin)
    local results = {}
    local today = dayStart()
    for _i, e in ipairs(entries) do
        local url = CalDAV.normalizeFeed(e.url)
        if not url then
            results[#results + 1] = { label = e.name or _("(not a link)"), ok = false, err = _("not a link") }
        else
            local dup
            for _j, f in ipairs(feeds) do if f.url == url then dup = f end end
            if dup then
                results[#results + 1] = { label = Calendar.feedName(dup), ok = true, note = _("already added") }
            else
                local res, err = CalDAV.fetchFeed(url, today, addDays(today, 31))
                if not res and err == "unreachable" and tostring(e.url):match("^%s*[Ww][Ee][Bb][Cc][Aa][Ll]://") then
                    -- webcal:// is plain HTTP on some (older) servers
                    local plain = url:gsub("^https://", "http://")
                    local r2, e2 = CalDAV.fetchFeed(plain, today, addDays(today, 31))
                    if r2 or e2 ~= "unreachable" then res, err, url = r2, e2, plain end
                end
                if res then
                    local f = { url = url, name = e.name, own_name = res.name, enabled = true }
                    feeds[#feeds + 1] = f
                    results[#results + 1] = { label = Calendar.feedName(f), ok = true, count = res.count }
                    Log.info("calendar: added", CalDAV.feedLabel(url), res.count, "events")
                else
                    results[#results + 1] = { label = e.name or (url:match("^https?://([^/?#]+)") or "?"), ok = false,
                        err = describe(err) }
                    Log.warn("calendar: link not added:", CalDAV.feedLabel(url), tostring(err))
                end
            end
        end
    end
    plugin:save()
    Calendar.cached_at = nil
    return results
end

function Calendar.resultsText(results)
    local lines = {}
    for _i, r in ipairs(results) do
        if r.ok then
            lines[#lines + 1] = "\u{2713} " .. r.label .. (r.note and (" (" .. r.note .. ")")
                or (r.count and (" (" .. T(_("%1 events"), r.count) .. ")") or ""))
        else
            lines[#lines + 1] = "\u{2717} " .. r.label .. ": " .. tostring(r.err)
        end
    end
    return table.concat(lines, "\n")
end

local function added(plugin, results)
    local any = false
    for _i, r in ipairs(results) do if r.ok then any = true end end
    UIManager:show(InfoMessage:new{ text = Calendar.resultsText(results), timeout = any and 5 or nil })
    if not any then return end
    if Calendar.connect_menu then UIManager:close(Calendar.connect_menu); Calendar.connect_menu = nil end
    if Calendar.board then UIManager:close(Calendar.board) end
    Calendar.events, Calendar.cached_at = nil, nil
    os.remove(CalDAV.cachePath())
    Calendar.show(plugin)
end
Calendar.afterAdd = added

--- Where calendars.txt is looked for: the GZreader folder, then the USB drive's top.
function Calendar.linkFiles(plugin)
    local out = {}
    local ok, dir = pcall(plugin.libraryDir, plugin)
    if ok and dir then
        out[#out + 1] = dir .. "/calendars.txt"
        out[#out + 1] = (dir:gsub("/[^/]+/?$", "")) .. "/calendars.txt"
    end
    out[#out + 1] = "/mnt/us/calendars.txt"
    return out
end

--- Add the links in calendars.txt (one per line, "Name | link" for a name).
function Calendar.importFile(plugin)
    for _i, path in ipairs(Calendar.linkFiles(plugin)) do
        local f = io.open(path, "rb")
        if f then
            local text = f:read("*a")
            f:close()
            local entries = Calendar.parseLinkLines(text)
            if #entries == 0 then return nil, T(_("%1 has no links in it."), path) end
            return Calendar.addFeeds(plugin, entries), path
        end
    end
    return nil, _("No calendars.txt found. Put one in the GZreader folder or at the top of the Kindle's USB drive: one calendar link per line (\"Name | link\" to give it a name).")
end

local function checking(n)
    local m = InfoMessage:new{ text = n > 1 and T(_("Checking %1 calendar links…"), n) or _("Checking the calendar link…") }
    UIManager:show(m)
    UIManager:forceRePaint()
    return m
end

function Calendar.importFileUI(plugin)
    require("gzreader_net").run(function()
        local m = checking(1)
        local results, where = Calendar.importFile(plugin)
        UIManager:close(m)
        if not results then return info(where) end
        added(plugin, results)
    end, { reason = "calendar links" })
end

function Calendar.typeAddLink(plugin)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    d = MultiInputDialog:new{
        title = _("Add a calendar link"),
        fields = {
            { description = _("Link (webcal:// or https://…ics)"), text = "", hint = "webcal://calendar.example.com/…" },
            { description = _("Name (optional)"), text = "" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Add"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                require("gzreader_net").run(function()
                    local m = checking(1)
                    local results = Calendar.addFeeds(plugin, { { url = f[1], name = f[2] ~= "" and f[2] or nil } })
                    UIManager:close(m)
                    added(plugin, results)
                end, { reason = "calendar links" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- The phone pastes one or more links (one per line) on a one-off page.
function Calendar.qrAddLinks(plugin)
    local PairServer = require("gzreader_pairserver")
    local PairPage = require("gzreader_pairpage")
    local NetworkMgr = require("ui/network/manager")
    local token = PairServer.randomToken(16)
    local base = "/calendar-links/" .. token
    local server, screen, timeout_task, done
    local results_all = {}
    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if screen then UIManager:close(screen) end
    end
    server = PairServer:new{
        handler = function(method, path, _headers, body)
            if path ~= base then return 404, "text/plain", "Not found" end
            if method == "GET" then return 200, "text/html", PairPage.feedsForm{ count = #Calendar.feeds(plugin) } end
            if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
            local form = PairServer.parseForm(body)
            local entries = Calendar.parseLinkLines(form.links)
            if #entries == 0 then
                return 200, "text/html", PairPage.feedsForm{ count = #Calendar.feeds(plugin), error = "Paste at least one calendar link." }
            end
            local results = Calendar.addFeeds(plugin, entries)
            for _i, r in ipairs(results) do results_all[#results_all + 1] = r end
            return 200, "text/html", PairPage.feedsResult(results, #Calendar.feeds(plugin))
        end,
    }
    local ok, serr = server:start()
    if not ok then return info(T(_("Couldn't start: %1"), tostring(serr))) end
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = PairServer.localIp(nil, iface)
    if not ip then
        server:stop()
        return info(_("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why))
    end
    UIManager:insertZMQ(server)
    screen = require("gzreader_pairscreen"):new{
        url = T("http://%1:%2%3", ip, server.port, base),
        title = _("Add calendar links"),
        instructions = _("Scan this code with your phone's camera and paste your calendar links (webcal:// or https://…ics, e.g. Proton Calendar's share links), one per line. You can add more than once. Your phone must be on the same Wi-Fi as this Kindle."),
        footer = _("Press Back when you're done."),
        on_cancel = function()
            screen = nil
            finish()
            if #results_all > 0 then added(plugin, results_all) end
        end,
    }
    UIManager:show(screen)
    timeout_task = function() finish(); if #results_all > 0 then added(plugin, results_all) end end
    UIManager:scheduleIn(600, timeout_task)
end

--- Remove a calendar link (its events go at the next sync).
function Calendar.removeFeed(plugin, index)
    local feeds = Calendar.feeds(plugin)
    local f = table.remove(feeds, index)
    plugin:save()
    if f then Log.info("calendar: removed", CalDAV.feedLabel(f.url)) end
    -- events are numbered by calendar: the kept ones are fetched again
    os.remove(CalDAV.cachePath())
    Calendar.events, Calendar.cached_at, Calendar.range = {}, nil, nil
end

function Calendar.showConnect(plugin)
    local items = {
        { text = _("Add calendar links with QR code (webcal / ICS, e.g. Proton)"), callback = function()
            require("gzreader_net").run(function() Calendar.qrAddLinks(plugin) end, { reason = "calendar links" })
        end },
        { text = _("Add a calendar link by typing"), callback = function() Calendar.typeAddLink(plugin) end },
        { text = _("Add links from calendars.txt (USB drive)"), callback = function() Calendar.importFileUI(plugin) end },
        { text = _("Connect a CalDAV account with QR code"), callback = function()
            require("gzreader_net").run(function() Calendar.qrConnect(plugin) end, { reason = "connecting a calendar" })
        end },
        { text = _("Connect a CalDAV account by typing"), callback = function() Calendar.typeConnect(plugin) end },
        { text = _("Calendar links are the subscription links calendars share (Proton Calendar: Settings → Calendars → Share → Share with anyone). A CalDAV account (Nextcloud, iCloud, Fastmail…) needs its address, user name and an app password."),
          select_enabled = false },
    }
    local menu
    menu = Menu:new{
        title = _("Calendar: add calendars"), item_table = items, covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = Calendar.TAB_ID,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    menu.key_events.LeftButtonTap = nil
    pcall(require("gzreader_tabs").decorate, menu, _("Calendar"))
    Calendar.connect_menu = menu
    UIManager:show(menu)
    return menu
end

function Calendar.typeConnect(plugin)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local s = plugin.store.caldav or {}
    local d
    d = MultiInputDialog:new{
        title = _("Connect a calendar (CalDAV)"),
        fields = {
            { description = _("Server address"), text = s.server or "", hint = "https://cloud.example.com/remote.php/dav" },
            { description = _("User name"), text = s.username or "" },
            { description = _("Password (an app password)"), text = "", text_type = "password" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                require("gzreader_net").run(function()
                    local ok, err = Calendar.connect(plugin, f[1], f[2], f[3])
                    if ok then connected(plugin) else info(err) end
                end, { reason = "connecting a calendar" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- The phone enters the address, user name and password (a one-off page
--- served by the Kindle, as for Grimmory and Memos).
function Calendar.qrConnect(plugin)
    local PairServer = require("gzreader_pairserver")
    local PairPage = require("gzreader_pairpage")
    local NetworkMgr = require("ui/network/manager")
    local token = PairServer.randomToken(16)
    local base = "/calendar/" .. token
    local server, screen, timeout_task, done
    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if screen then UIManager:close(screen) end
    end
    server = PairServer:new{
        handler = function(method, path, _headers, body)
            if path ~= base then return 404, "text/plain", "Not found" end
            local s = plugin.store.caldav or {}
            if method == "GET" then
                return 200, "text/html", PairPage.caldavForm{ server = s.server, username = s.username }
            end
            if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
            local form = PairServer.parseForm(body)
            local ok, err = Calendar.connect(plugin, form.server, form.username, form.password)
            if not ok then
                return 200, "text/html", PairPage.caldavForm{ server = form.server, username = form.username, error = err }
            end
            UIManager:nextTick(function() finish(); connected(plugin) end)
            return 200, "text/html", PairPage.caldavSuccess(#((plugin.store.caldav or {}).calendars or {}))
        end,
    }
    local ok, serr = server:start()
    if not ok then return info(T(_("Couldn't start: %1"), tostring(serr))) end
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = PairServer.localIp(nil, iface)
    if not ip then
        server:stop()
        return info(_("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why))
    end
    UIManager:insertZMQ(server)
    screen = require("gzreader_pairscreen"):new{
        url = T("http://%1:%2%3", ip, server.port, base),
        title = _("Connect a calendar"),
        instructions = _("Scan this code with your phone's camera, then enter your calendar server's address, your user name and a password (an app password where your server has them). Your phone must be on the same Wi-Fi as this Kindle."),
        footer = _("Press Back to cancel."),
        on_cancel = function() screen = nil; finish() end,
    }
    UIManager:show(screen)
    timeout_task = function() finish() end
    UIManager:scheduleIn(600, timeout_task)
end

function Calendar.disconnect(plugin)
    plugin.store.caldav = {}
    plugin:save()
    os.remove(CalDAV.cachePath())
    Calendar.events, Calendar.cached_at, Calendar.range = nil, nil, nil
    if Calendar.board then UIManager:close(Calendar.board) end
    Log.info("calendar: disconnected")
end

---------------------------------------------------------------- settings

local function size(bytes)
    bytes = bytes or 0
    if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
    return string.format("%d KB", math.floor(bytes / 1024 + 0.5))
end

--- Settings → Connections → Calendar (CalDAV).
function Calendar.settingsItems(plugin)
    local okI, IconItem = pcall(require, "common/ui/icon_menu_item")
    local okc, icons = pcall(require, "common/inline_icon_map")
    local function icon(name, item)
        if okI and okc and icons[name] then return IconItem.decorate(item, icons[name]) end
        return item
    end
    local prefs = Calendar.prefs(plugin)
    local function store() return plugin.store.caldav or {} end
    local function connected_() return Calendar.client(plugin):isConnected() end
    local function confirm(text, ok_text, fn)
        UIManager:show(require("ui/widget/confirmbox"):new{ text = text, ok_text = ok_text, ok_callback = fn })
    end
    local function choice(list, get, set, label)
        local items = {}
        for _i, c in ipairs(list) do
            items[#items + 1] = { text = label(c), radio = true,
                checked_func = function() return get() == c end,
                callback = function() set(c); plugin:save(); Calendar.redraw() end }
        end
        return items
    end
    local function resync()
        Calendar.cached_at = nil
        if Calendar.board and not Calendar.board._gz_closed then Calendar.syncOnOpen(plugin) end
    end
    return {
        icon("download", {
            text_func = function() return T(_("Calendar links: %1"), #Calendar.feeds(plugin)) end,
            help_text = _("Subscription links calendars share (webcal:// or https://…ics), e.g. Proton Calendar: Settings → Calendars → Share → Share with anyone. Several can be added; each is fetched when the Calendar tab syncs. Links are secret: they're kept in GZreader's settings and never written to the log."),
            sub_item_table_func = function()
                local items = {}
                for i, f in ipairs(Calendar.feeds(plugin)) do
                    items[#items + 1] = {
                        text_func = function() return Calendar.feedName(f) .. (f.enabled == false and ("  " .. _("(hidden)")) or "") end,
                        sub_item_table_func = function()
                            return {
                                { text = ((f.url or ""):match("^https?://([^/?#]+)") or "?") .. "/\u{2026}", enabled = false, separator = true },
                                { text = _("Show its events"), checked_func = function() return f.enabled ~= false end,
                                    callback = function() f.enabled = f.enabled == false; plugin:save(); resync() end },
                                { text = _("Rename"), keep_menu_open = true, callback = function()
                                    local InputDialog = require("ui/widget/inputdialog")
                                    local d
                                    d = InputDialog:new{ title = _("Calendar name"), input = Calendar.feedName(f),
                                        buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                                            { text = _("Save"), is_enter_default = true, callback = function()
                                                local v = d:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                                                UIManager:close(d)
                                                f.name = v ~= "" and v or nil
                                                plugin:save()
                                                Calendar.redraw()
                                            end } } } }
                                    UIManager:show(d)
                                    d:onShowKeyboard()
                                end },
                                { text = _("Remove"), callback = function(tm)
                                    confirm(T(_("Remove the calendar link “%1”?\n\nIts events are removed from the Kindle. The calendar itself stays as it is."),
                                        Calendar.feedName(f)), _("Remove"), function()
                                            for j, x in ipairs(Calendar.feeds(plugin)) do if x == f then Calendar.removeFeed(plugin, j) end end
                                            if tm and tm.backToUpperMenu then pcall(tm.backToUpperMenu, tm) end
                                            Calendar.redraw()
                                        end)
                                end },
                            }
                        end,
                    }
                    if i == #Calendar.feeds(plugin) then items[#items].separator = true end
                end
                items[#items + 1] = { text = _("Add links with QR code"), callback = function(tm)
                    if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end
                    require("gzreader_net").run(function() Calendar.qrAddLinks(plugin) end, { reason = "calendar links" })
                end }
                items[#items + 1] = { text = _("Add a link by typing"), callback = function(tm)
                    if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end
                    Calendar.typeAddLink(plugin)
                end }
                items[#items + 1] = { text = _("Add links from calendars.txt (USB drive)"), callback = function(tm)
                    if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end
                    Calendar.importFileUI(plugin)
                end }
                return items
            end,
        }),
        icon("connect", {
            text_func = function()
                if not connected_() then return _("CalDAV account: none") end
                local s = store()
                return T(_("CalDAV account: %1 · %2"), s.username or "?", ((s.server or ""):gsub("^https?://", ""):gsub("/.*$", "")))
            end,
            sub_item_table_func = function()
                local s = store()
                local items = {}
                if connected_() then
                    items[#items + 1] = { text = T(_("Signed in as %1"), s.username or "?"), enabled = false }
                    items[#items + 1] = { text = s.server or "", enabled = false, separator = true }
                end
                items[#items + 1] = { text = connected_() and _("Connect again with QR code") or _("Connect with QR code"),
                    callback = function(tm)
                        if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end
                        require("gzreader_net").run(function() Calendar.qrConnect(plugin) end, { reason = "connecting a calendar" })
                    end }
                items[#items + 1] = { text = connected_() and _("Connect again by typing") or _("Connect by typing"),
                    callback = function(tm)
                        if tm and tm.closeMenu then pcall(tm.closeMenu, tm) end
                        Calendar.typeConnect(plugin)
                    end }
                if connected_() then
                    items[#items].separator = true
                    items[#items + 1] = { text = _("Disconnect"), callback = function(tm)
                        confirm(_("Disconnect the CalDAV account?\n\nIts saved password and the events kept on this Kindle are removed (calendar links stay). Your calendars on the server stay as they are."),
                            _("Disconnect"), function()
                                Calendar.disconnect(plugin)
                                if tm and tm.backToUpperMenu then pcall(tm.backToUpperMenu, tm) end
                            end)
                    end }
                end
                return items
            end,
        }),
        icon("calendar", {
            text_func = function()
                local on, all = 0, 0
                for _i, c in ipairs(Calendar.calendars(plugin)) do all = all + 1; if c.ref.enabled ~= false then on = on + 1 end end
                return T(_("Calendars shown: %1 of %2"), on, all)
            end,
            enabled_func = function() return Calendar.hasSources(plugin) end,
            sub_item_table_func = function()
                local items = {}
                for _i, c in ipairs(Calendar.calendars(plugin)) do
                    items[#items + 1] = { text = c.name .. (c.kind == "link" and ("  \u{00B7} " .. _("link")) or ""),
                        checked_func = function() return c.ref.enabled ~= false end,
                        callback = function()
                            c.ref.enabled = c.ref.enabled == false
                            plugin:save()
                            resync()
                        end }
                end
                if connected_() then
                    if #items > 0 then items[#items].separator = true end
                    items[#items + 1] = { text = _("Look for CalDAV calendars again"), keep_menu_open = true, callback = function()
                        local s = store()
                        require("gzreader_net").run(function()
                            local ok, err = Calendar.connect(plugin, s.server, s.username, s.password)
                            info(ok and T(_("%1 calendars."), #(store().calendars or {})) or err, 3)
                        end, { reason = "calendar" })
                    end }
                end
                return items
            end,
        }),
        icon("view_list", {
            text_func = function() return T(_("Opens in: %1"), LAYOUT_NAMES[prefs.layout]) end,
            sub_item_table = choice(Calendar.LAYOUTS, function() return prefs.layout end,
                function(v) prefs.layout = v; Calendar.layout = v end, function(v) return LAYOUT_NAMES[v] end),
        }),
        icon("calendar", {
            text_func = function() return T(_("Week starts on: %1"), WEEKDAY[prefs.week_start]) end,
            sub_item_table = choice({ 1, 2 }, function() return prefs.week_start end,
                function(v) prefs.week_start = v end, function(v) return WEEKDAY[v] end),
        }),
        icon("sync", {
            text_func = function() return T(_("Sync range: %1 days back, %2 ahead"), prefs.days_back, prefs.days_ahead) end,
            help_text = _("Events in this range are fetched and kept on the Kindle for offline use. A longer range takes longer to sync."),
            sub_item_table = {
                { text = _("Days ahead"), sub_item_table = choice({ 30, 90, 180, 365 }, function() return prefs.days_ahead end,
                    function(v) prefs.days_ahead = v; resync() end, function(v) return T(_("%1 days"), v) end) },
                { text = _("Days back"), sub_item_table = choice({ 7, 14, 30, 90 }, function() return prefs.days_back end,
                    function(v) prefs.days_back = v; resync() end, function(v) return T(_("%1 days"), v) end) },
            },
        }),
        icon("disk", {
            text_func = function()
                local lfs = require("libs/libkoreader-lfs")
                return T(_("Storage used: %1"), size(lfs.attributes(CalDAV.cachePath(), "size") or 0))
            end,
            sub_item_table_func = function()
                local lfs = require("libs/libkoreader-lfs")
                local bytes = lfs.attributes(CalDAV.cachePath(), "size") or 0
                if not Calendar.events then Calendar.loadCache() end
                return {
                    { text = T(_("Events kept: %1 (%2)"), #(Calendar.events or {}), size(bytes)), enabled = false },
                    { text = Calendar.cached_at and T(_("Last synced: %1"), os.date("%b %d, ", Calendar.cached_at) .. clock(Calendar.cached_at))
                        or _("Not synced yet"), enabled = false, separator = true },
                    { text = _("Free up space: remove kept events"), enabled = bytes > 0, callback = function(tm)
                        confirm(_("Remove the events kept on this Kindle?\n\nThey stay on the server and are fetched again the next time you open the Calendar tab with Wi-Fi."),
                            _("Remove"), function()
                                os.remove(CalDAV.cachePath())
                                Calendar.events, Calendar.cached_at, Calendar.range = {}, nil, nil
                                if tm and tm.backToUpperMenu then pcall(tm.backToUpperMenu, tm) end
                            end)
                    end },
                }
            end,
        }),
    }
end

return Calendar
