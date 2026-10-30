--[[--
CalDAV client for the Calendar tab (read-only): finds your calendars and
fetches their events for a date range.

- Discovery (RFC 4791 / 6764): the address you give → current-user-principal
  → calendar-home-set → the calendars in it (VEVENT ones). An address that
  is a calendar itself works too, and /.well-known/caldav is tried when the
  address has no path.
- Events: one calendar-query REPORT per calendar with a time range, asking
  the server to expand repeating events (<C:expand>, times then come in
  UTC). Servers that don't expand send the RRULE: it's expanded here
  (DAILY / WEEKLY / MONTHLY / YEARLY with INTERVAL, COUNT, UNTIL, BYDAY,
  BYMONTHDAY; EXDATE; changed single occurrences via RECURRENCE-ID).
- Sign-in: HTTP Basic with your user name and password. Use an app password
  where the server has them (Nextcloud, iCloud, Fastmail, Google…): it's
  kept in GZreader's settings like the Memos token, and never logged (the
  log has addresses only, and passwords are redacted from it anyway).
- Times with a TZID that the server didn't expand are read as the Kindle's
  own time zone (GZreader's time zone setting); UTC and all-day times are
  exact.
]]

local ltn12 = require("ltn12")
local Log = require("gzreader_log")

local CalDAV = {}
CalDAV.__index = CalDAV

--- `store` is plugin.store.caldav (server, username, password, home, calendars).
function CalDAV:new(store)
    return setmetatable({ store = store }, self)
end

function CalDAV:isConnected()
    return self.store.server ~= nil and self.store.username ~= nil and self.store.password ~= nil
end

function CalDAV.normalizeServer(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    if not s:match("^https?://") then s = "https://" .. s end
    if not s:match("^https?://[^/]+") then return nil end
    return s
end

local function b64(s)
    local ok, mime = pcall(require, "mime")
    if ok and mime and mime.b64 then return (mime.b64(s)) end
    return require("ffi/sha2").bin_to_base64(s)
end

--- The scheme and host of a URL ("https://host:port").
local function origin(url) return url:match("^(https?://[^/]+)") end

--- `href` (as servers send it: a path, or a full URL) made absolute against `base`.
function CalDAV.absolute(base, href)
    if href:match("^https?://") then return href end
    if href:sub(1, 1) == "/" then return origin(base) .. href end
    return (base:gsub("[^/]*$", "")) .. href
end

---------------------------------------------------------------- XML

local function localName(name) return (tostring(name or ""):gsub("^.*:", "")) end

local function kids(el, name)
    local out = {}
    for _i, k in ipairs(el and el.kids or {}) do
        if k.type == "element" and (not name or localName(k.name) == name) then out[#out + 1] = k end
    end
    return out
end

local function child(el, name) return kids(el, name)[1] end

local function find(el, name, out)
    out = out or {}
    for _i, k in ipairs(el and el.kids or {}) do
        if k.type == "element" then
            if localName(k.name) == name then out[#out + 1] = k end
            find(k, name, out)
        end
    end
    return out
end

local function text(el)
    if not el then return nil end
    local t = {}
    for _i, k in ipairs(el.kids or {}) do
        if k.type == "text" then t[#t + 1] = k.value
        elseif k.type == "element" then t[#t + 1] = text(k) or "" end
    end
    return table.concat(t)
end

--- The <response> elements of a multistatus document: { href, props = { name = element } }.
function CalDAV.parseMultistatus(xml)
    local SLAXML = require("gzreader_slaxml")
    local ok, doc = pcall(SLAXML.dom, SLAXML, xml or "", { stripWhitespace = false })
    if not ok or not doc then return nil, "bad XML" end
    local out = {}
    for _i, r in ipairs(find(doc, "response")) do
        local item = { href = (text(child(r, "href")) or ""):gsub("^%s+", ""):gsub("%s+$", ""), props = {} }
        for _j, ps in ipairs(kids(r, "propstat")) do
            local status = text(child(ps, "status")) or ""
            if status:match(" 2%d%d") or status == "" then
                for _k, prop in ipairs(kids(ps, "prop")) do
                    for _l, p in ipairs(kids(prop)) do item.props[localName(p.name)] = p end
                end
            end
        end
        out[#out + 1] = item
    end
    return out
end
CalDAV._text, CalDAV._find, CalDAV._kids = text, find, kids

---------------------------------------------------------------- HTTP

--- One request. Returns code, body, headers, err ("unreachable", "unauthorized", "http_<code>").
function CalDAV:request(method, url, body, depth, opts)
    opts = opts or {}
    local Api = require("gzreader_api")
    local chunks = {}
    local headers = {
        ["Authorization"] = "Basic " .. b64((self.store.username or "") .. ":" .. (self.store.password or "")),
        ["Accept"] = "text/xml, application/xml, */*",
        ["Content-Type"] = body and "application/xml; charset=utf-8" or nil,
        ["Depth"] = depth,
    }
    local code, _, resp_headers = Api.rawRequest(method, url, {
        headers = headers, raw_body = body, sink = ltn12.sink.table(chunks), timeouts = opts.timeouts or { 15, 60 },
    })
    local out = table.concat(chunks)
    if not code then return nil, nil, nil, "unreachable" end
    if code == 401 or code == 403 then return code, out, resp_headers, "unauthorized" end
    if code >= 300 and code < 400 then return code, out, resp_headers end
    if code >= 400 then return code, out, resp_headers, "http_" .. code end
    return code, out, resp_headers
end

--- PROPFIND, following redirects. Returns responses, final url, err.
function CalDAV:propfind(url, depth, props)
    local body = '<?xml version="1.0" encoding="utf-8"?>'
        .. '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/" xmlns:ic="http://apple.com/ns/ical/">'
        .. "<d:prop>" .. props .. "</d:prop></d:propfind>"
    for _i = 1, 4 do
        local code, out, headers, err = self:request("PROPFIND", url, body, depth)
        if err then return nil, url, err end
        if code >= 300 and code < 400 then
            local loc = headers and (headers.location or headers.Location)
            if not loc then return nil, url, "http_" .. code end
            url = CalDAV.absolute(url, loc)
        else
            local list, perr = CalDAV.parseMultistatus(out)
            if not list then return nil, url, perr end
            return list, url
        end
    end
    return nil, url, "too many redirects"
end

local function hrefIn(prop)
    local h = prop and child(prop, "href")
    local t = text(h)
    return t and (t:gsub("^%s+", ""):gsub("%s+$", "")) or nil
end

local function isCalendar(props)
    local rt = props.resourcetype
    if not (rt and child(rt, "calendar")) then return false end
    local comps = props["supported-calendar-component-set"]
    if not comps then return true end
    for _i, c in ipairs(kids(comps, "comp")) do
        for _j, a in ipairs(c.attr or {}) do
            if localName(a.name) == "name" and a.value == "VEVENT" then return true end
        end
    end
    return false
end

local CAL_PROPS = "<d:resourcetype/><d:displayname/><c:supported-calendar-component-set/><ic:calendar-color/><cs:getctag/>"

--- Find the calendars. Returns { home, calendars = { {href, name, color} } } or nil, err.
function CalDAV:discover()
    local server = self.store.server
    local tries = { server }
    if not server:match("^https?://[^/]+/.") then tries[#tries + 1] = origin(server) .. "/.well-known/caldav" end
    local principal, home, start, last_err
    for _i, url in ipairs(tries) do
        local list, final, err = self:propfind(url, "0",
            "<d:current-user-principal/><c:calendar-home-set/>" .. CAL_PROPS)
        if err == "unauthorized" then return nil, err end
        if list and list[1] then
            local p = list[1].props
            if isCalendar(p) then -- the address is a calendar
                return { home = nil, calendars = { {
                    href = final, name = text(p.displayname) ~= "" and text(p.displayname) or "Calendar",
                    color = text(p["calendar-color"]),
                } } }
            end
            home = hrefIn(p["calendar-home-set"])
            principal = hrefIn(p["current-user-principal"])
            start = final
            if home or principal then break end
        end
        last_err = err or last_err
    end
    if not home and principal then
        local list, final, err = self:propfind(CalDAV.absolute(start, principal), "0", "<c:calendar-home-set/>")
        if err then return nil, err end
        home = list and list[1] and hrefIn(list[1].props["calendar-home-set"])
        start = final
    end
    if not home then return nil, last_err or "no calendars found at this address" end
    home = CalDAV.absolute(start, home)
    local list, final, err = self:propfind(home, "1", CAL_PROPS)
    if err then return nil, err end
    local cals = {}
    for _i, r in ipairs(list or {}) do
        if isCalendar(r.props) then
            local name = text(r.props.displayname)
            cals[#cals + 1] = {
                href = CalDAV.absolute(final, r.href),
                name = (name and name ~= "") and name or (r.href:match("([^/]+)/?$") or "Calendar"),
                color = text(r.props["calendar-color"]),
            }
        end
    end
    table.sort(cals, function(a, b) return a.name:lower() < b.name:lower() end)
    return { home = home, calendars = cals }
end

---------------------------------------------------------------- iCalendar

--- RFC 5545 lines: unfolded, as { name, params = {}, value }.
function CalDAV.icalLines(data)
    data = (data or ""):gsub("\r\n", "\n"):gsub("\n[ \t]", "")
    local out = {}
    for line in data:gmatch("[^\n]+") do
        local head, value = line:match("^([^:]+):(.*)$")
        if head then
            local name, rest = head:match("^([^;]+)(.*)$")
            local params = {}
            for k, v in rest:gmatch(';([^=;]+)=("?[^;]*"?)') do params[k:upper()] = v:gsub('^"(.*)"$', "%1") end
            out[#out + 1] = { name = name:upper(), params = params, value = value }
        end
    end
    return out
end

local function unescape(s)
    return (s or ""):gsub("\\[nN]", "\n"):gsub("\\([,;\\])", "%1")
end

--- os.time for UTC fields (summer time included).
local function timegm(f)
    local t = os.time(f)
    local lt, ut = os.date("*t", t), os.date("!*t", t)
    ut.isdst = lt.isdst
    return t + (os.time(lt) - os.time(ut))
end
CalDAV.timegm = timegm

--- An iCalendar date or date-time: epoch seconds, all_day.
function CalDAV.parseTime(value, params)
    params = params or {}
    if value:match("^%d%d%d%d%d%d%d%d$") or params.VALUE == "DATE" then
        local y, m, d = value:match("^(%d%d%d%d)(%d%d)(%d%d)")
        if not y then return nil end
        return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 }, true
    end
    local Y, M, D, h, mi, sec, z = value:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)(Z?)$")
    if not Y then return nil end
    local f = { year = tonumber(Y), month = tonumber(M), day = tonumber(D), hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec) }
    if z == "Z" then return timegm(f), false end
    f.isdst = nil
    return os.time(f), false -- floating or TZID: the Kindle's time zone
end

--- An iCalendar DURATION in seconds.
function CalDAV.parseDuration(s)
    local sign, rest = (s or ""):match("^([+-]?)P(.*)$")
    if not rest then return nil end
    local secs = 0
    local w = rest:match("^(%d+)W") ; if w then secs = secs + tonumber(w) * 604800 end
    local d = rest:match("(%d+)D") ; if d then secs = secs + tonumber(d) * 86400 end
    local t = rest:match("T(.*)$") or ""
    local h = t:match("(%d+)H") ; if h then secs = secs + tonumber(h) * 3600 end
    local mi = t:match("(%d+)M") ; if mi then secs = secs + tonumber(mi) * 60 end
    local sec = t:match("(%d+)S") ; if sec then secs = secs + tonumber(sec) end
    return sign == "-" and -secs or secs
end

--- The VEVENTs in iCalendar data: { uid, title, start, finish, all_day, location, notes, rrule, exdates, recurrence_id }.
function CalDAV.parseEvents(data)
    local events, ev = {}, nil
    local depth = 0
    for _i, l in ipairs(CalDAV.icalLines(data)) do
        if l.name == "BEGIN" then
            if l.value:upper() == "VEVENT" and depth == 0 then ev = { exdates = {} } end
            if ev and l.value:upper() ~= "VEVENT" then depth = depth + 1 end -- VALARM inside
        elseif l.name == "END" then
            if ev and l.value:upper() ~= "VEVENT" then depth = depth - 1
            elseif ev and l.value:upper() == "VEVENT" then
                if ev.start and ev.status ~= "CANCELLED" then
                    if not ev.finish then
                        ev.finish = ev.duration and (ev.start + ev.duration) or (ev.all_day and ev.start + 86400 or ev.start)
                    end
                    ev.duration, ev.status = nil, nil
                    events[#events + 1] = ev
                end
                ev = nil
            end
        elseif ev and depth == 0 then
            local n, v = l.name, l.value
            if n == "UID" then ev.uid = v
            elseif n == "SUMMARY" then ev.title = unescape(v)
            elseif n == "LOCATION" then ev.location = unescape(v)
            elseif n == "DESCRIPTION" then ev.notes = unescape(v):sub(1, 2000)
            elseif n == "STATUS" then ev.status = v:upper()
            elseif n == "DTSTART" then ev.start, ev.all_day = CalDAV.parseTime(v, l.params)
            elseif n == "DTEND" then ev.finish = CalDAV.parseTime(v, l.params)
            elseif n == "DURATION" then ev.duration = CalDAV.parseDuration(v)
            elseif n == "RRULE" then ev.rrule = v
            elseif n == "RECURRENCE-ID" then ev.recurrence_id = CalDAV.parseTime(v, l.params)
            elseif n == "EXDATE" then
                for part in v:gmatch("[^,]+") do
                    local t = CalDAV.parseTime(part, l.params)
                    if t then ev.exdates[t] = true end
                end
            end
        end
    end
    return events
end

---------------------------------------------------------------- repeating events

local WEEKDAYS = { SU = 1, MO = 2, TU = 3, WE = 4, TH = 5, FR = 6, SA = 7 }

local function addMonths(t, n)
    local d = os.date("*t", t)
    d.month = d.month + n
    d.isdst = nil
    return os.time(d)
end

local function daysInMonth(y, m) return os.date("*t", os.time{ year = y, month = m + 1, day = 0, hour = 12 }).day end

--- The starts of a repeating event between from and to (epoch), at most `max`.
function CalDAV.expandRule(ev, from, to, max)
    max = max or 500
    local rule = {}
    for k, v in (ev.rrule or ""):gmatch("([^=;]+)=([^;]+)") do rule[k:upper()] = v end
    local freq = (rule.FREQ or ""):upper()
    local interval = tonumber(rule.INTERVAL) or 1
    local count = tonumber(rule.COUNT)
    local untilt = rule.UNTIL and CalDAV.parseTime(rule.UNTIL)
    local s = os.date("*t", ev.start)
    local out, n = {}, 0
    local function emit(t)
        if t < ev.start then return true end
        if untilt and t > untilt then return false end
        n = n + 1
        if count and n > count then return false end
        if t + (ev.finish - ev.start) > from and t < to and not ev.exdates[t] then out[#out + 1] = t end
        return #out < max and t < to
    end
    local function at(y, mo, d)
        return os.time{ year = y, month = mo, day = d, hour = s.hour, min = s.min, sec = s.sec }
    end
    local guard = 0
    if freq == "DAILY" then
        local t = ev.start
        while guard < 20000 do
            guard = guard + 1
            if not emit(t) then break end
            local d = os.date("*t", t); d.day = d.day + interval; d.isdst = nil; t = os.time(d)
        end
    elseif freq == "WEEKLY" then
        local days = {}
        for code in (rule.BYDAY or ""):gmatch("(%a%a)") do days[#days + 1] = WEEKDAYS[code:upper()] end
        if #days == 0 then days = { s.wday } end
        table.sort(days)
        local week = os.time{ year = s.year, month = s.month, day = s.day - (s.wday - 1), hour = 12 }
        local done = false
        while not done and guard < 5000 do
            guard = guard + 1
            local w = os.date("*t", week)
            for _i, wd in ipairs(days) do
                if not emit(at(w.year, w.month, w.day + wd - 1)) then done = true; break end
            end
            w.day = w.day + 7 * interval; w.isdst = nil; week = os.time(w)
        end
    elseif freq == "MONTHLY" or freq == "YEARLY" then
        local step = freq == "MONTHLY" and interval or 12 * interval
        local base = os.time{ year = s.year, month = s.month, day = 1, hour = 12 }
        local done = false
        while not done and guard < 2000 do
            guard = guard + 1
            local m = os.date("*t", base)
            local cands = {}
            local dim = daysInMonth(m.year, m.month)
            if rule.BYDAY and (freq == "MONTHLY" or rule.BYMONTH) then
                for nth, code in rule.BYDAY:gmatch("([+-]?%d*)(%a%a)") do
                    local wd = WEEKDAYS[code:upper()]
                    local list = {}
                    for d = 1, dim do
                        if os.date("*t", os.time{ year = m.year, month = m.month, day = d, hour = 12 }).wday == wd then list[#list + 1] = d end
                    end
                    local k = tonumber(nth)
                    if not k then for _i, d in ipairs(list) do cands[#cands + 1] = d end
                    elseif k > 0 and list[k] then cands[#cands + 1] = list[k]
                    elseif k < 0 and list[#list + k + 1] then cands[#cands + 1] = list[#list + k + 1] end
                end
            elseif rule.BYMONTHDAY then
                for v in rule.BYMONTHDAY:gmatch("[+-]?%d+") do
                    local k = tonumber(v)
                    local d = k > 0 and k or dim + k + 1
                    if d >= 1 and d <= dim then cands[#cands + 1] = d end
                end
            else
                if freq == "YEARLY" and m.month ~= s.month then cands = {} elseif s.day <= dim then cands = { s.day } end
            end
            table.sort(cands)
            for _i, d in ipairs(cands) do
                if not emit(at(m.year, m.month, d)) then done = true; break end
            end
            base = addMonths(base, step)
        end
    else
        if ev.start + (ev.finish - ev.start) > from and ev.start < to then out[1] = ev.start end
    end
    return out
end

--- Events between from and to, one entry per occurrence: repeating events
--- expanded, changed occurrences in place of the ones they change.
function CalDAV.occurrences(events, from, to)
    local overrides, out = {}, {}
    for _i, ev in ipairs(events) do
        if ev.recurrence_id and ev.uid then overrides[ev.uid .. "@" .. ev.recurrence_id] = true end
    end
    for _i, ev in ipairs(events) do
        local len = (ev.finish or ev.start) - ev.start
        if ev.rrule and not ev.recurrence_id then
            for _j, t in ipairs(CalDAV.expandRule(ev, from, to)) do
                if not (ev.uid and overrides[ev.uid .. "@" .. t]) then
                    out[#out + 1] = { uid = ev.uid, title = ev.title, location = ev.location, notes = ev.notes,
                        all_day = ev.all_day, start = t, finish = t + len, repeats = true }
                end
            end
        elseif ev.start < to and ev.start + math.max(len, 1) > from then
            out[#out + 1] = { uid = ev.uid, title = ev.title, location = ev.location, notes = ev.notes,
                all_day = ev.all_day, start = ev.start, finish = ev.finish, repeats = ev.recurrence_id ~= nil or nil }
        end
    end
    return out
end

---------------------------------------------------------------- fetching

local function utc(t) return os.date("!%Y%m%dT%H%M%SZ", t) end

--- One calendar's events between from and to: { … } or nil, err.
function CalDAV:events(href, from, to)
    local body = '<?xml version="1.0" encoding="utf-8"?>'
        .. '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        .. '<d:prop><c:calendar-data><c:expand start="' .. utc(from) .. '" end="' .. utc(to) .. '"/></c:calendar-data></d:prop>'
        .. '<c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT">'
        .. '<c:time-range start="' .. utc(from) .. '" end="' .. utc(to) .. '"/>'
        .. "</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>"
    local _, out, _, err = self:request("REPORT", href, body, "1")
    if err then return nil, err end
    local list, perr = CalDAV.parseMultistatus(out)
    if not list then return nil, perr end
    local raw = {}
    for _i, r in ipairs(list) do
        local data = text(r.props["calendar-data"])
        if data and data ~= "" then
            for _j, ev in ipairs(CalDAV.parseEvents(data)) do raw[#raw + 1] = ev end
        end
    end
    return CalDAV.occurrences(raw, from, to)
end

--- Events of the chosen calendars between from and to:
--- { events = { …, cal = index }, failed = { names } } or nil, err.
function CalDAV:sync(calendars, from, to)
    local all, failed, ok_any, first_err = {}, {}, false, nil
    for i, cal in ipairs(calendars or {}) do
        if cal.enabled ~= false then
            local evs, err = self:events(cal.href, from, to)
            if evs then
                ok_any = true
                for _j, ev in ipairs(evs) do ev.cal = i; all[#all + 1] = ev end
            else
                failed[#failed + 1] = cal.name
                first_err = first_err or err
                Log.warn("calendar: couldn't read", cal.name, tostring(err))
                if err == "unauthorized" or err == "unreachable" then return nil, err end
            end
        end
    end
    if not ok_any and #failed > 0 then return nil, first_err end
    table.sort(all, function(a, b)
        if a.start ~= b.start then return a.start < b.start end
        if (a.all_day and 1 or 0) ~= (b.all_day and 1 or 0) then return a.all_day == true end
        return (a.title or "") < (b.title or "")
    end)
    return { events = all, failed = failed }
end

---------------------------------------------------------------- the cache

function CalDAV.cachePath() return require("datastorage"):getSettingsDir() .. "/gzreader-calendar.json" end

function CalDAV.loadCache()
    local f = io.open(CalDAV.cachePath(), "rb")
    if not f then return nil end
    local ok, data = pcall(require("json").decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and data or nil
end

function CalDAV.saveCache(data)
    local path = CalDAV.cachePath()
    local f = io.open(path .. ".tmp", "wb")
    if not f then return end
    f:write(require("json").encode(data))
    f:close()
    os.rename(path .. ".tmp", path)
end

return CalDAV
