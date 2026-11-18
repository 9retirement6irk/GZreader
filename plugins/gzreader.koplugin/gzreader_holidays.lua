--[[
Holidays, as a calendar of their own in the Calendar tab: worked out on the
Kindle (no link, no account, no Wi-Fi: the Kindle 2 and DX have them too),
turned on in Settings → Calendar → Holidays, on the Calendar tab's first
screen, or on the phone page (gzreader_pairpage.lua). Off until turned on.

Each country is a list of rules: a fixed date, the nth (or last) weekday of
a month, a weekday on or before a date, or so many days from Easter.

  plugin.store.calendar_holidays = { enabled = true, country = "US" }
  Holidays.on(plugin, day) --> { "Thanksgiving" }  (day: any time that day)
]]

local _ = require("gettext")

local Holidays = {}

local SUN, MON, THU = 1, 2, 5

-- { title, rule… }: { m, d } a date; { m, wday = w, n = k } the kth weekday
-- (k = -1: the last); { m, wday = w, before = d } the w on or before day d;
-- { easter = days }.
Holidays.COUNTRIES = {
    { id = "US", name = _("United States"), days = {
        { _("New Year's Day"), 1, 1 },
        { _("Martin Luther King Jr. Day"), 1, wday = MON, n = 3 },
        { _("Valentine's Day"), 2, 14 },
        { _("Presidents' Day"), 2, wday = MON, n = 3 },
        { _("St. Patrick's Day"), 3, 17 },
        { _("Easter"), easter = 0 },
        { _("Mother's Day"), 5, wday = SUN, n = 2 },
        { _("Memorial Day"), 5, wday = MON, n = -1 },
        { _("Father's Day"), 6, wday = SUN, n = 3 },
        { _("Juneteenth"), 6, 19 },
        { _("Independence Day"), 7, 4 },
        { _("Labor Day"), 9, wday = MON, n = 1 },
        { _("Columbus Day / Indigenous Peoples' Day"), 10, wday = MON, n = 2 },
        { _("Halloween"), 10, 31 },
        { _("Veterans Day"), 11, 11 },
        { _("Thanksgiving"), 11, wday = THU, n = 4 },
        { _("Christmas Eve"), 12, 24 },
        { _("Christmas Day"), 12, 25 },
        { _("New Year's Eve"), 12, 31 },
    } },
    { id = "CA", name = _("Canada"), days = {
        { _("New Year's Day"), 1, 1 },
        { _("Family Day"), 2, wday = MON, n = 3 },
        { _("Valentine's Day"), 2, 14 },
        { _("Good Friday"), easter = -2 },
        { _("Easter"), easter = 0 },
        { _("Easter Monday"), easter = 1 },
        { _("Mother's Day"), 5, wday = SUN, n = 2 },
        { _("Victoria Day"), 5, wday = MON, before = 24 },
        { _("Father's Day"), 6, wday = SUN, n = 3 },
        { _("Canada Day"), 7, 1 },
        { _("Civic Holiday"), 8, wday = MON, n = 1 },
        { _("Labour Day"), 9, wday = MON, n = 1 },
        { _("National Day for Truth and Reconciliation"), 9, 30 },
        { _("Thanksgiving"), 10, wday = MON, n = 2 },
        { _("Halloween"), 10, 31 },
        { _("Remembrance Day"), 11, 11 },
        { _("Christmas Eve"), 12, 24 },
        { _("Christmas Day"), 12, 25 },
        { _("Boxing Day"), 12, 26 },
        { _("New Year's Eve"), 12, 31 },
    } },
    { id = "GB", name = _("United Kingdom"), days = {
        { _("New Year's Day"), 1, 1 },
        { _("Valentine's Day"), 2, 14 },
        { _("Mothering Sunday"), easter = -21 },
        { _("St. Patrick's Day"), 3, 17 },
        { _("Good Friday"), easter = -2 },
        { _("Easter Sunday"), easter = 0 },
        { _("Easter Monday"), easter = 1 },
        { _("Early May bank holiday"), 5, wday = MON, n = 1 },
        { _("Spring bank holiday"), 5, wday = MON, n = -1 },
        { _("Father's Day"), 6, wday = SUN, n = 3 },
        { _("Summer bank holiday"), 8, wday = MON, n = -1 },
        { _("Halloween"), 10, 31 },
        { _("Bonfire Night"), 11, 5 },
        { _("Remembrance Sunday"), 11, wday = SUN, n = 2 },
        { _("Christmas Eve"), 12, 24 },
        { _("Christmas Day"), 12, 25 },
        { _("Boxing Day"), 12, 26 },
        { _("New Year's Eve"), 12, 31 },
    } },
}

function Holidays.country(id)
    for _i, c in ipairs(Holidays.COUNTRIES) do if c.id == id then return c end end
    return Holidays.COUNTRIES[1]
end

--- The setting: { enabled, country } (off, the United States, until changed).
function Holidays.conf(plugin)
    plugin.store.calendar_holidays = plugin.store.calendar_holidays or {}
    local c = plugin.store.calendar_holidays
    if c.enabled == nil then c.enabled = false end
    c.country = Holidays.country(c.country).id
    return c
end

function Holidays.enabled(plugin)
    return Holidays.conf(plugin).enabled == true
end

--- "Holidays (United States)": the calendar's name.
function Holidays.name(plugin)
    return string.format("%s (%s)", _("Holidays"), Holidays.country(Holidays.conf(plugin).country).name)
end

local function wdayOf(y, m, d) return os.date("*t", os.time{ year = y, month = m, day = d, hour = 12 }).wday end
local function lastDay(y, m) return os.date("*t", os.time{ year = y, month = m + 1, day = 0, hour = 12 }).day end

--- Easter Sunday (Gregorian): month, day.
function Holidays.easter(y)
    local a, b, c = y % 19, math.floor(y / 100), y % 100
    local d, e = math.floor(b / 4), b % 4
    local f = math.floor((b + 8) / 25)
    local g = math.floor((b - f + 1) / 3)
    local h = (19 * a + b - d - g + 15) % 30
    local i, k = math.floor(c / 4), c % 4
    local l = (32 + 2 * e + 2 * i - h - k) % 7
    local m = math.floor((a + 11 * h + 22 * l) / 451)
    local month = math.floor((h + l - 7 * m + 114) / 31)
    return month, (h + l - 7 * m + 114) % 31 + 1
end

--- One rule in a year: month, day.
function Holidays.date(rule, y)
    if rule.easter then
        local m, d = Holidays.easter(y)
        local t = os.date("*t", os.time{ year = y, month = m, day = d + rule.easter, hour = 12 })
        return t.month, t.day
    end
    local m = rule[2]
    if not rule.wday then return m, rule[3] end
    if rule.before then
        local d = rule.before
        return m, d - (wdayOf(y, m, d) - rule.wday) % 7
    end
    if rule.n == -1 then
        local d = lastDay(y, m)
        return m, d - (wdayOf(y, m, d) - rule.wday) % 7
    end
    return m, 1 + (rule.wday - wdayOf(y, m, 1)) % 7 + 7 * (rule.n - 1)
end

local years = {} -- "US 2026" -> { ["11-26"] = { "Thanksgiving" } }

--- A country's holidays in a year: { ["m-d"] = { titles } }.
function Holidays.year(id, y)
    local key = id .. " " .. y
    if years[key] then return years[key] end
    local out = {}
    for _i, rule in ipairs(Holidays.country(id).days) do
        local m, d = Holidays.date(rule, y)
        local k = m .. "-" .. d
        out[k] = out[k] or {}
        table.insert(out[k], rule[1])
    end
    years[key] = out
    return out
end

--- The holidays on a day (any time that day): { titles }; {} when off.
function Holidays.on(plugin, day)
    local c = Holidays.conf(plugin)
    if not c.enabled then return {} end
    local t = os.date("*t", day)
    return Holidays.year(c.country, t.year)[t.month .. "-" .. t.day] or {}
end

--- The same as Calendar events: all day, in calendar number `cal`.
function Holidays.eventsOn(plugin, day, cal)
    local titles = Holidays.on(plugin, day)
    if #titles == 0 then return titles end
    local t = os.date("*t", day)
    local start = os.time{ year = t.year, month = t.month, day = t.day, hour = 0 }
    local finish = os.time{ year = t.year, month = t.month, day = t.day + 1, hour = 0 }
    local out = {}
    for _i, title in ipairs(titles) do
        out[#out + 1] = { title = title, start = start, finish = finish, all_day = true, cal = cal, holiday = true }
    end
    return out
end

--- Settings: { enabled = bool, country = id } (either may be nil).
function Holidays.set(plugin, v)
    local c = Holidays.conf(plugin)
    if v.enabled ~= nil then c.enabled = v.enabled == true end
    if v.country then c.country = Holidays.country(v.country).id end
    plugin:save()
    return c
end

return Holidays
