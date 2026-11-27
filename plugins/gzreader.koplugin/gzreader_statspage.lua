--[[--
The reading stats page: what a tap on Home's reading stats widget opens. It shows the numbers the
book server keeps for every device (gzreader_grimstats.lua) with charts:

  BookOrbit   the last seven days as bars, the past year as a grid of days
              (darker = more reading), the year's goal and the next badge as
              progress bars, the book of a year ago, this year's finished
              books and the day's highlight.
  Grimmory    the week's books as bars, the month as a calendar of days read,
              and books finished by month.

The charts are GZreader's own drawings from the numbers (Page.sections decides
what is shown; the painters below draw it): grey on grey screens, in colour on
colour ones. Nothing here is taken from BookOrbit's or Grimmory's programs.

A tap or any key closes it.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Page = {}

--- A length of time in words: "2 h 5 min", "45 min".
function Page.time(seconds)
    local mins = math.floor((tonumber(seconds) or 0) / 60 + 0.5)
    if mins < 60 then return T(_("%1 min"), mins) end
    local h, m = math.floor(mins / 60), mins % 60
    return m == 0 and T(_("%1 h"), h) or T(_("%1 h %2 min"), h, m)
end

--- How dark a day is drawn: 0 (nothing read) to 4 (an hour or more).
function Page.level(minutes)
    minutes = tonumber(minutes) or 0
    if minutes <= 0 then return 0 end
    if minutes < 15 then return 1 end
    if minutes < 30 then return 2 end
    if minutes < 60 then return 3 end
    return 4
end

local function dayTime(key, add)
    local y, m, d = tostring(key):match("^(%d+)%-(%d+)%-(%d+)")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d) + (add or 0), hour = 12 }
end

local WEEKDAYS = { _("Mon"), _("Tue"), _("Wed"), _("Thu"), _("Fri"), _("Sat"), _("Sun") }
local MONTHS = { _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"), _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec") }

--- The last seven days of BookOrbit's days, oldest first: { { label, minutes, today }… }.
function Page.lastWeek(days)
    local mins = type(days) == "table" and type(days.minutes) == "table" and days.minutes or {}
    local out = {}
    for back = 6, 0, -1 do
        local i = #mins - back
        local t = dayTime(days and days.start, i - 1)
        if i >= 1 and t then
            local wday = (os.date("*t", t).wday + 5) % 7 + 1 -- Monday 1 … Sunday 7
            out[#out + 1] = { label = WEEKDAYS[wday], minutes = mins[i], today = back == 0 or nil }
        end
    end
    return out
end

--- BookOrbit's days as a grid: columns are weeks (oldest first), rows Monday to Sunday.
--- { cols = { { level or false ×7 }… }, months = { [col] = label } } (false: no such day).
function Page.yearGrid(days, max_cols)
    local mins = type(days) == "table" and type(days.minutes) == "table" and days.minutes or {}
    local first = dayTime(days and days.start, 0)
    if not first or #mins == 0 then return { cols = {}, months = {} } end
    local lead = (os.date("*t", first).wday + 5) % 7 -- days of the first week before the first day
    local n_cols = math.ceil((lead + #mins) / 7)
    local skip = math.max(0, n_cols - (max_cols or n_cols)) -- (a narrow screen: the newest weeks)
    local cols, months = {}, {}
    local last_month
    for c = skip + 1, n_cols do
        local col = {}
        for r = 1, 7 do
            local i = (c - 1) * 7 + r - lead
            col[r] = i >= 1 and i <= #mins and Page.level(mins[i])
        end
        cols[#cols + 1] = col
        -- (a month's name over the week its first Monday-row day falls in)
        local i = math.max(1, (c - 1) * 7 + 1 - lead)
        local m = os.date("*t", dayTime(days.start, i - 1)).month
        if m ~= last_month then
            if last_month then months[#cols] = MONTHS[m] end
            last_month = m
        end
    end
    return { cols = cols, months = months }
end

--- Grimmory's month as a calendar: rows are weeks, Monday first.
--- { rows = { { { day, count } or false ×7 }… }, max = most sessions in a day }.
function Page.monthGrid(year, month, month_days)
    local first = os.time{ year = year, month = month, day = 1, hour = 12 }
    local n_days = os.date("*t", os.time{ year = year, month = month + 1, day = 0, hour = 12 }).day
    local lead = (os.date("*t", first).wday + 5) % 7
    local count, max = {}, 0
    for _i, r in ipairs(type(month_days) == "table" and month_days or {}) do
        count[r.day] = r.count
        max = math.max(max, tonumber(r.count) or 0)
    end
    local rows = {}
    for cell = 1, math.ceil((lead + n_days) / 7) * 7 do
        local row = math.ceil(cell / 7)
        rows[row] = rows[row] or {}
        local day = cell - lead
        rows[row][(cell - 1) % 7 + 1] = day >= 1 and day <= n_days and { day = day, count = count[day] or 0 } or false
    end
    return { rows = rows, max = max }
end

local function bookText(b)
    if type(b) ~= "table" then return nil end
    return b.author and T(_("%1, by %2"), b.title, b.author) or b.title
end

--- What the page shows, top to bottom, from GS.all(plugin): a list of sections
--- { kind, title, … }. Kinds: "numbers", "bars", "year", "month", "progress", "text".
function Page.sections(stats)
    stats = type(stats) == "table" and stats or {}
    local v, d = stats.values or {}, stats.detail or {}
    local out = {}
    local function num(x) return x ~= nil and tostring(x) or "—" end
    out[#out + 1] = { kind = "numbers", items = {
        { value = num(v.streak), label = _("Day streak") },
        { value = v.week_time and Page.time(v.week_time) or "—", label = _("Read this week") },
        { value = num(v.year_finished), label = _("Finished this year") },
    } }
    if stats.server == "bookorbit" then
        local week = Page.lastWeek(d.days)
        if #week > 0 then
            local bars = {}
            for i, w in ipairs(week) do bars[i] = { label = w.label, value = w.minutes, mark = w.today, text = w.minutes > 0 and tostring(w.minutes) or "" } end
            out[#out + 1] = { kind = "bars", title = _("The last seven days (minutes)"), bars = bars }
        end
        if d.days and #(d.days.minutes or {}) > 7 then
            local mins, read, total = d.days.minutes, 0, 0
            for _i, m in ipairs(mins) do
                if m > 0 then read = read + 1 end
                total = total + m
            end
            out[#out + 1] = { kind = "year", title = T(_("The past year: %1 on %2 days"), Page.time(total * 60), read), days = d.days }
        end
        if d.goal then
            out[#out + 1] = { kind = "progress", title = d.goal.year and T(_("Reading goal for %1"), d.goal.year) or _("Reading goal"),
                done = d.goal.done, of = d.goal.books, text = T(_("%1 of %2 books"), d.goal.done, d.goal.books) }
        end
        if d.badges then
            local line = T(_("Badges: %1 of %2"), d.badges.earned, d.badges.total)
            local nb = d.badges.next
            if nb and nb.threshold and nb.threshold > 0 then
                out[#out + 1] = { kind = "progress", title = T(_("%1. Next: %2"), line, nb.name), done = math.min(nb.progress or 0, nb.threshold), of = nb.threshold,
                    text = T(_("%1 of %2"), nb.progress or 0, nb.threshold), note = nb.about }
            else
                out[#out + 1] = { kind = "text", title = line, text = d.badges.latest and T(_("Latest: %1"), d.badges.latest.name) or nil }
            end
        end
        if d.year_ago then
            out[#out + 1] = { kind = "text", title = _("A year ago you were reading"),
                text = T(_("%1 (%2 over %3 days)"), bookText(d.year_ago), Page.time(d.year_ago.minutes * 60), d.year_ago.days) }
        end
        if d.finished and #d.finished > 0 then
            local lines = {}
            for i, b in ipairs(d.finished) do lines[i] = "• " .. bookText(b) end
            local more = (tonumber(d.finished_count) or #lines) - #lines
            if more > 0 then lines[#lines + 1] = T(_("… and %1 more"), more) end
            out[#out + 1] = { kind = "text", title = _("Finished this year"), text = table.concat(lines, "\n"), shrink = true }
        end
        if d.highlight then
            local from = d.highlight.book and (d.highlight.chapter and T(_("%1, %2"), d.highlight.book, d.highlight.chapter) or d.highlight.book) or nil
            out[#out + 1] = { kind = "text", title = _("Highlight of the day"), text = "“" .. d.highlight.text .. "”" .. (from and ("\n— " .. from) or ""), shrink = true }
        end
        local extra = {}
        if v.longest_streak then extra[#extra + 1] = T(_("Longest streak: %1 days"), v.longest_streak) end
        if v.library_books then extra[#extra + 1] = T(_("Books in the library: %1"), v.library_books) end
        if v.reading_now then extra[#extra + 1] = T(_("Reading now: %1"), v.reading_now) end
        if #extra > 0 then out[#out + 1] = { kind = "text", text = table.concat(extra, "  ·  ") } end
    else
        if d.week_books and #d.week_books > 0 then
            local bars = {}
            for i, b in ipairs(d.week_books) do bars[i] = { label = b.title, value = b.seconds, text = Page.time(b.seconds) } end
            out[#out + 1] = { kind = "bars", title = _("This week's books"), bars = bars, sideways = true }
        end
        if d.month_days and d.year and d.month then
            out[#out + 1] = { kind = "month", title = T(_("%1: reading sessions by day"), MONTHS[d.month] .. " " .. d.year),
                grid = Page.monthGrid(d.year, d.month, d.month_days) }
        end
        if d.finished_months and #d.finished_months > 0 then
            local by = {}
            for _i, m in ipairs(d.finished_months) do by[m.month] = m.finished end
            local bars = {}
            for m = 1, 12 do bars[m] = { label = MONTHS[m]:sub(1, 1), value = by[m] or 0, text = (by[m] or 0) > 0 and tostring(by[m]) or "", mark = m == d.month or nil } end
            out[#out + 1] = { kind = "bars", title = d.year and T(_("Books finished in %1, by month"), d.year) or _("Books finished by month"), bars = bars }
        end
        local extra = {}
        if v.longest_streak then extra[#extra + 1] = T(_("Longest streak: %1 days"), v.longest_streak) end
        if v.reading_days then extra[#extra + 1] = T(_("Days read: %1"), v.reading_days) end
        if v.month_sessions then extra[#extra + 1] = T(_("Sessions this month: %1"), v.month_sessions) end
        if #extra > 0 then out[#out + 1] = { kind = "text", text = table.concat(extra, "  ·  ") } end
    end
    return out
end

--- The line under the page: where the numbers are from and how old.
function Page.footer(stats, now)
    stats = type(stats) == "table" and stats or {}
    local name = stats.name or "Grimmory"
    local how = require("device"):isTouchDevice() and _("Tap to close.") or _("Press any key to close.")
    if not stats.at or stats.at <= 0 then
        return T(_("Nothing from %1 yet: the numbers come when Wi-Fi is on."), name) .. " " .. how
    end
    local age = math.max(0, (now or os.time()) - stats.at)
    local when = age < 120 and _("just now") or age < 5400 and T(_("%1 minutes ago"), math.floor(age / 60))
        or age < 172800 and T(_("%1 hours ago"), math.floor(age / 3600)) or T(_("%1 days ago"), math.floor(age / 86400))
    return T(_("Every device's reading, from %1, as of %2."), name, when) .. " " .. how
end

---------------------------------------------------------------- drawing

-- The five shades of a day (nothing … an hour or more): grey levels, and greens on a colour screen.
local GREY = { 0.08, 0.3, 0.5, 0.72, 1 }
local GREEN = { { 0xE6, 0xEC, 0xE6 }, { 0xB7, 0xE0, 0xA8 }, { 0x74, 0xC4, 0x76 }, { 0x31, 0x9B, 0x54 }, { 0x0B, 0x6B, 0x35 } }
local ACCENT = { 0x1F, 0x6F, 0xB5 } -- (bars and progress on a colour screen)

local function painter()
    local Blitbuffer = require("ffi/blitbuffer")
    local ok, colour = pcall(function() return require("gzreader_colour").enabled() end)
    colour = ok and colour == true
    local P = { colour = colour }
    function P.rect(bb, x, y, w, h, rgb, grey)
        if w <= 0 or h <= 0 then return end
        if colour and rgb and bb.paintRectRGB32 then
            bb:paintRectRGB32(x, y, w, h, Blitbuffer.ColorRGB32(rgb[1], rgb[2], rgb[3], 0xFF))
        else
            bb:paintRect(x, y, w, h, Blitbuffer.gray(grey))
        end
    end
    function P.shade(bb, x, y, w, h, level) P.rect(bb, x, y, w, h, GREEN[level + 1], GREY[level + 1]) end
    function P.accent(bb, x, y, w, h, strong) P.rect(bb, x, y, w, h, ACCENT, strong and 1 or 0.6) end
    function P.frame(bb, x, y, w, h)
        bb:paintRect(x, y, w, 1, Blitbuffer.COLOR_DARK_GRAY); bb:paintRect(x, y + h - 1, w, 1, Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(x, y, 1, h, Blitbuffer.COLOR_DARK_GRAY); bb:paintRect(x + w - 1, y, 1, h, Blitbuffer.COLOR_DARK_GRAY)
    end
    return P
end

--- The page itself. `plugin`: GZreader's; `stats`: GS.all's (read fresh when nil).
function Page.show(plugin, stats)
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Widget = require("ui/widget/widget")
    local Screen = Device.screen

    stats = stats or require("gzreader_grimstats").all(plugin)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(18)
    local W = sw - pad * 2
    local P = painter()
    local small = Font:getFace("smallinfofont", 14)
    local body = Font:getFace("smallinfofont", 16)
    local head = Font:getFace("smallinfofont", 17)

    local Canvas = Widget:extend{ w = 0, h = 0, draw = nil }
    function Canvas:getSize() return Geom:new{ w = self.w, h = self.h } end
    function Canvas:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
        self.draw(bb, x, y, self.w, self.h)
    end
    local function label(bb, text, face, x, y, max_w, centre, bold, white)
        if not text or text == "" then return 0 end
        local tw = TextWidget:new{ text = text, face = face, bold = bold, max_width = max_w, fgcolor = white and Blitbuffer.COLOR_WHITE or nil }
        local size = tw:getSize()
        tw:paintTo(bb, centre and (x + math.floor((max_w - size.w) / 2)) or x, y)
        tw:free()
        return size.w
    end
    local line_h = TextWidget:new{ text = "Ag", face = small }:getSize().h

    local function numbers(sec)
        local big = Font:getFace("tfont", 30)
        local big_h = TextWidget:new{ text = "8", face = big }:getSize().h
        return Canvas:new{ w = W, h = big_h + line_h + Screen:scaleBySize(6), draw = function(bb, x, y, w)
            local cell = math.floor(w / #sec.items)
            for i, it in ipairs(sec.items) do
                local cx = x + (i - 1) * cell
                label(bb, it.value, big, cx, y, cell, true, true)
                label(bb, it.label, small, cx, y + big_h + Screen:scaleBySize(2), cell, true)
                if i > 1 then bb:paintRect(cx, y + Screen:scaleBySize(6), 1, big_h + line_h - Screen:scaleBySize(8), Blitbuffer.COLOR_GRAY) end
            end
        end }
    end

    local function bars(sec)
        local max = 0
        for _i, b in ipairs(sec.bars) do max = math.max(max, tonumber(b.value) or 0) end
        if sec.sideways then -- one row per bar: name, bar, amount
            local row_h = line_h + Screen:scaleBySize(6)
            local name_w, amount_w = math.floor(W * 0.42), math.floor(W * 0.2)
            return Canvas:new{ w = W, h = row_h * #sec.bars, draw = function(bb, x, y, w)
                local room = w - name_w - amount_w - Screen:scaleBySize(12)
                for i, b in ipairs(sec.bars) do
                    local ry = y + (i - 1) * row_h
                    label(bb, b.label, small, x, ry, name_w - Screen:scaleBySize(6))
                    local bw = max > 0 and math.max(2, math.floor(room * b.value / max)) or 0
                    P.accent(bb, x + name_w, ry + Screen:scaleBySize(3), bw, row_h - Screen:scaleBySize(8), i == 1)
                    label(bb, b.text, small, x + name_w + bw + Screen:scaleBySize(6), ry, amount_w + room - bw)
                end
            end }
        end
        local chart_h = Screen:scaleBySize(70)
        return Canvas:new{ w = W, h = chart_h + line_h * 2 + Screen:scaleBySize(4), draw = function(bb, x, y, w)
            local n = #sec.bars
            local cell = math.floor(w / n)
            local bar_w = math.max(4, math.floor(cell * 0.56))
            local base = y + line_h + chart_h
            bb:paintRect(x, base, cell * n, 1, Blitbuffer.COLOR_DARK_GRAY)
            for i, b in ipairs(sec.bars) do
                local cx = x + (i - 1) * cell
                local bh = max > 0 and b.value > 0 and math.max(3, math.floor(chart_h * b.value / max)) or 0
                P.accent(bb, cx + math.floor((cell - bar_w) / 2), base - bh, bar_w, bh, b.mark)
                label(bb, b.text, small, cx, base - bh - line_h, cell, true)
                label(bb, b.label, small, cx, base + Screen:scaleBySize(3), cell, true, b.mark)
            end
        end }
    end

    local function year(sec)
        local gap = math.max(1, Screen:scaleBySize(1))
        local side = math.max(4, math.min(Screen:scaleBySize(14), math.floor((W + gap) / 53) - gap))
        local grid = Page.yearGrid(sec.days, math.floor((W + gap) / (side + gap)))
        local gw = #grid.cols * (side + gap) - gap
        return Canvas:new{ w = W, h = line_h + 7 * (side + gap) + Screen:scaleBySize(4) + line_h, draw = function(bb, x, y, w)
            local gx = x + math.floor((w - gw) / 2)
            local next_free = 0 -- (month names never run into each other)
            for c, col in ipairs(grid.cols) do
                local cx = gx + (c - 1) * (side + gap)
                if grid.months[c] and cx >= next_free then
                    next_free = cx + label(bb, grid.months[c], small, cx, y, w) + Screen:scaleBySize(6)
                end
                for r = 1, 7 do
                    if col[r] then P.shade(bb, cx, y + line_h + (r - 1) * (side + gap), side, side, col[r]) end
                end
            end
            -- what the shades mean
            local ky = y + line_h + 7 * (side + gap) + Screen:scaleBySize(4)
            local kx = gx + label(bb, _("Less"), small, gx, ky, w) + Screen:scaleBySize(6)
            local ks = math.min(side, line_h - 4)
            for level = 0, 4 do
                P.shade(bb, kx, ky + math.floor((line_h - ks) / 2), ks, ks, level)
                kx = kx + ks + gap + 1
            end
            label(bb, _("More"), small, kx + Screen:scaleBySize(5), ky, w)
        end }
    end

    local function month(sec)
        local rows = sec.grid.rows
        local cell_w, cell_h = math.floor(W / 7), line_h + Screen:scaleBySize(8)
        return Canvas:new{ w = W, h = line_h + #rows * cell_h, draw = function(bb, x, y)
            for c = 1, 7 do label(bb, WEEKDAYS[c], small, x + (c - 1) * cell_w, y, cell_w, true) end
            for r, row in ipairs(rows) do
                for c = 1, 7 do
                    local cell = row[c]
                    if cell then
                        local cx, cy = x + (c - 1) * cell_w + 1, y + line_h + (r - 1) * cell_h + 1
                        -- (one session light, more darker, the month's busiest day darkest; day numbers stay readable)
                        local level = cell.count <= 0 and 0 or math.min(3, math.max(1, math.ceil(3 * cell.count / math.max(1, sec.grid.max))))
                        P.shade(bb, cx, cy, cell_w - 2, cell_h - 2, level)
                        label(bb, tostring(cell.day), small, cx, cy + Screen:scaleBySize(3), cell_w - 2, true, cell.count > 0, level >= 3)
                    end
                end
            end
        end }
    end

    local function progress(sec)
        local bar_h = Screen:scaleBySize(14)
        return Canvas:new{ w = W, h = bar_h + Screen:scaleBySize(2), draw = function(bb, x, y, w)
            local text_w = math.floor(w * 0.3)
            local bw = w - text_w
            P.frame(bb, x, y, bw, bar_h)
            local fill = sec.of > 0 and math.floor((bw - 4) * math.min(1, sec.done / sec.of)) or 0
            P.accent(bb, x + 2, y + 2, fill, bar_h - 4, true)
            label(bb, sec.text, small, x + bw + Screen:scaleBySize(8), y + math.floor((bar_h - line_h) / 2), text_w - Screen:scaleBySize(8))
        end }
    end

    -- Sections go on while they fit: the footer always shows.
    local footer = TextBoxWidget:new{ text = Page.footer(stats), face = small, width = W, alignment = "center" }
    local title = TextWidget:new{ text = T(_("Reading stats · %1"), stats.name or "Grimmory"), face = Font:getFace("tfont", 22), bold = true, max_width = W }
    local span = Screen:scaleBySize(10)
    local group = VerticalGroup:new{ align = "left", title, VerticalSpan:new{ width = span } }
    local room = sh - pad * 2 - title:getSize().h - span - footer:getSize().h - span
    local shown = 0
    for _i, sec in ipairs(Page.sections(stats)) do
        local parts = {}
        if sec.title then parts[#parts + 1] = TextWidget:new{ text = sec.title, face = head, bold = true, max_width = W } end
        local chart = sec.kind == "numbers" and numbers(sec) or sec.kind == "bars" and bars(sec) or sec.kind == "year" and year(sec)
            or sec.kind == "month" and month(sec) or sec.kind == "progress" and progress(sec) or nil
        if chart then parts[#parts + 1] = chart end
        local words = sec.kind == "text" and sec.text or sec.note
        local used = span
        for _j, p in ipairs(parts) do used = used + p:getSize().h end
        if words then
            local box = TextBoxWidget:new{ text = words, face = sec.kind == "text" and body or small, width = W }
            if sec.shrink and used + box:getSize().h > room and room - used >= line_h * 2 then
                -- (a long list or highlight: as many lines as there is room for)
                box:free()
                box = TextBoxWidget:new{ text = words, face = body, width = W, height = room - used, height_adjust = true, height_overflow_show_ellipsis = true }
            end
            parts[#parts + 1] = box
            used = used + box:getSize().h
        end
        if used <= room then
            for _j, p in ipairs(parts) do group[#group + 1] = p end
            group[#group + 1] = VerticalSpan:new{ width = span }
            room = room - used
            shown = shown + 1
        else
            for _j, p in ipairs(parts) do if p.free then p:free() end end
        end
    end
    if room > 0 then group[#group + 1] = VerticalSpan:new{ width = room } end
    group[#group + 1] = footer

    local StatsPage = InputContainer:extend{ name = "reading stats page", modal = true }
    local page = StatsPage:new{ dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh } }
    if Device:hasKeys() then page.key_events = { AnyKeyPressed = { { Device.input.group.Any } } } end
    if Device:isTouchDevice() then
        page.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = page.dimen } } }
    end
    local function close()
        UIManager:close(page)
        return true
    end
    page.onAnyKeyPressed, page.onTapClose, page.onClose = close, close, close
    function page:onShow() UIManager:setDirty(self, function() return "full", self.dimen end) end
    function page:onCloseWidget() UIManager:setDirty(nil, "full") end
    page[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group } }
    page.sections_shown = shown
    Page.current = page
    UIManager:show(page)
    require("gzreader_log").info("reading stats page:", stats.name or "?", shown, "sections shown")
    return page
end

return Page
