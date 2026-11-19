--[[--
A journal entry's place and weather, as the Memos fork's journaling mode
adds them (web/src/lib/journal/weather.ts, components/MemoEditor/edit/
journal/JournalHeader.tsx):

- The place is the note's own location in Memos ({ placeholder, latitude,
  longitude }), not text. It comes from Dawarich (where it had you at the
  entry's moment: the visit then, or the nearest point within half an hour),
  through the fork's /api/dawarich (your Memos sign-in; the Dawarich key
  stays on the server), or from a search by name (OpenStreetMap's
  Nominatim). A Kindle has no GPS, so there's no "current location".
- The weather is a line of text ("56°F, clear"), for the entry's place, or
  the journal settings' default city when it has none, at the entry's hour,
  from Open-Meteo (no key). Only the coordinates and the date are sent.

Settings (the fork's /api/journal/settings, kept by gzreader_journal.lua):
addLocation, addWeather, defaultCity, temperatureUnit.

Privacy: places, coordinates and city names are never written to the log
(the addresses asked are logged without their query).

The parsing is pure (run_tests.lua); fetching runs in a background process.
]]

local Log = require("gzreader_log")

local Place = {
    -- (the services; a tour points them at a stand-in)
    FORECAST = "https://api.open-meteo.com/v1/forecast",
    ARCHIVE = "https://archive-api.open-meteo.com/v1/archive",
    GEOCODING = "https://geocoding-api.open-meteo.com/v1/search",
    NOMINATIM = "https://nominatim.openstreetmap.org",
}

--- What a WMO weather code describes (the fork's weatherKind).
function Place.weatherKind(code)
    code = tonumber(code)
    if not code then return "cloudy" end
    if code == 0 then return "clear" end
    if code == 1 then return "mostly-clear" end
    if code == 2 then return "partly-cloudy" end
    if code == 3 then return "cloudy" end
    if code == 45 or code == 48 then return "fog" end
    if code >= 51 and code <= 57 then return "drizzle" end
    if (code >= 61 and code <= 67) or (code >= 80 and code <= 82) then return "rain" end
    if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
    if code >= 95 then return "thunderstorm" end
    return "cloudy"
end

--- The fork's English words for each kind (locales/en.json journal.weather).
Place.WEATHER_WORDS = {
    clear = "clear", ["mostly-clear"] = "mostly clear", ["partly-cloudy"] = "partly cloudy", cloudy = "cloudy",
    fog = "foggy", drizzle = "drizzle", rain = "rain", snow = "snow", thunderstorm = "thunderstorms",
}

--- The weather line written into an entry: "56°F, clear" (the fork's weatherLine).
function Place.weatherLine(w)
    if type(w) ~= "table" or not w.temperature then return nil end
    return string.format("%d\u{00B0}%s, %s", w.temperature, w.unit == "celsius" and "C" or "F",
        Place.WEATHER_WORDS[w.kind] or w.kind or "")
end

local function enc(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function query(t)
    local keys, out = {}, {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    for _i, k in ipairs(keys) do out[#out + 1] = enc(k) .. "=" .. enc(t[k]) end
    return table.concat(out, "&")
end
Place.query = query

--- The forecast service covers about three months back; the archive covers everything older.
Place.ARCHIVE_AFTER_DAYS = 80

--- Open-Meteo's address for the weather at (lat, lon) on `at`'s day (UTC), in `unit`.
function Place.weatherUrl(lat, lon, at, unit, now)
    now = now or os.time()
    local old = now - at > Place.ARCHIVE_AFTER_DAYS * 86400
    local base = old and Place.ARCHIVE or Place.FORECAST
    local day = os.date("!%Y-%m-%d", at)
    return base .. "?" .. query{
        latitude = string.format("%.4f", lat), longitude = string.format("%.4f", lon),
        hourly = "temperature_2m,weather_code", temperature_unit = unit == "celsius" and "celsius" or "fahrenheit",
        timezone = "GMT", start_date = day, end_date = day,
    }
end

--- Open-Meteo's answer: the weather in `at`'s hour, or nil.
function Place.parseWeather(data, at, unit)
    local hourly = type(data) == "table" and data.hourly
    if type(hourly) ~= "table" or type(hourly.time) ~= "table" or #hourly.time == 0 then return nil end
    local hour = math.min(math.max(tonumber(os.date("!%H", at)) or 0, 0), #hourly.time - 1)
    local temp = type(hourly.temperature_2m) == "table" and hourly.temperature_2m[hour + 1]
    local code = type(hourly.weather_code) == "table" and hourly.weather_code[hour + 1]
    if type(temp) ~= "number" or type(code) ~= "number" then return nil end
    local rounded = temp >= 0 and math.floor(temp + 0.5) or -math.floor(-temp + 0.5)
    return { temperature = rounded, unit = unit == "celsius" and "celsius" or "fahrenheit", kind = Place.weatherKind(code) }
end

--- A city name ("Boston, MA") → Open-Meteo's geocoding address.
function Place.cityUrl(name, lang)
    local city = (tostring(name or ""):match("^([^,]*)") or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if city == "" then return nil end
    return Place.GEOCODING .. "?" .. query{ name = city, count = "10", language = lang or "en", format = "json" }
end

--- The city a name means: the result whose state or country the name's qualifier mentions, else the first.
function Place.parseCity(data, name)
    local results = type(data) == "table" and type(data.results) == "table" and data.results or {}
    local rest = tostring(name or ""):match("^[^,]*,(.*)$")
    local qualifier = rest and rest:lower() or ""
    local function mentions(r)
        if qualifier == "" then return false end
        for _i, k in ipairs({ "admin1", "admin1_code", "country", "country_code" }) do
            local v = r[k]
            if type(v) == "string" and v ~= "" and qualifier:find(v:lower(), 1, true) then return true end
        end
        return false
    end
    local pick
    for _i, r in ipairs(results) do if type(r) == "table" and mentions(r) then pick = r; break end end
    pick = pick or results[1]
    if type(pick) ~= "table" or type(pick.latitude) ~= "number" or type(pick.longitude) ~= "number" then return nil end
    return { lat = pick.latitude, lon = pick.longitude, name = pick.name }
end

--- A place by name or address: OpenStreetMap's first answer.
function Place.searchUrl(q, lang)
    return Place.NOMINATIM .. "/search?" .. query{ q = q, format = "jsonv2", limit = "1", ["accept-language"] = lang or "en" }
end
function Place.parseSearch(list, q)
    local first = type(list) == "table" and list[1]
    if type(first) ~= "table" then return nil end
    local lat, lon = tonumber(first.lat), tonumber(first.lon)
    if not lat or not lon then return nil end
    local name = (type(first.name) == "string" and first.name ~= "" and first.name)
        or (type(first.display_name) == "string" and first.display_name:match("^([^,]+)")) or q
    return { lat = lat, lon = lon, name = name }
end

--- A short name for where a point is ("Jamaica Plain", "Boston"), from OpenStreetMap.
function Place.reverseUrl(lat, lon, lang)
    return Place.NOMINATIM .. "/reverse?" .. query{ lat = tostring(lat), lon = tostring(lon), format = "jsonv2",
        zoom = "16", ["accept-language"] = lang or "en" }
end
function Place.parseReverse(data)
    if type(data) ~= "table" then return nil end
    if type(data.name) == "string" and data.name ~= "" then return data.name end
    local a = type(data.address) == "table" and data.address or {}
    for _i, k in ipairs({ "park", "neighbourhood", "suburb", "city", "town", "village" }) do
        if type(a[k]) == "string" and a[k] ~= "" then return a[k] end
    end
    return nil
end

--- The half hour either side of `at`, as the fork asks Dawarich (start, end: ISO UTC).
function Place.range(at)
    return query{ start = os.date("!%Y-%m-%dT%H:%M:%SZ", at - 1800), ["end"] = os.date("!%Y-%m-%dT%H:%M:%SZ", at + 1800) }
end

-- (days since 1970-01-01 for a date: H. Hinnant's days_from_civil)
local function days(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

--- An ISO time ("2026-11-17T23:05:00Z", "…+01:00", "….123Z") as seconds since 1970 (UTC), or nil.
local function isoTime(s)
    if type(s) ~= "string" then return nil end
    local y, mo, d, h, mi, se = s:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    if not y then return nil end
    local t = days(tonumber(y), tonumber(mo), tonumber(d)) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
    local sign, oh, om = s:match("([%+%-])(%d%d):?(%d%d)$")
    if sign then
        local secs = tonumber(oh) * 3600 + tonumber(om) * 60
        t = sign == "+" and t - secs or t + secs
    end
    return t
end
Place.isoTime = isoTime

--- Where Dawarich had you at `at` (the fork's placeAt): the visit covering it, else
--- the nearest point. visits = { { name, start, end, lat, lon } }, points = { { lat, lon, time } }.
function Place.placeAt(visits, points, at)
    for _i, v in ipairs(type(visits) == "table" and visits or {}) do
        local s, e = isoTime(v.start), isoTime(v["end"])
        if s and e and s <= at and at <= e and type(v.lat) == "number" and type(v.lon) == "number" then
            return { lat = v.lat, lon = v.lon, name = (type(v.name) == "string" and v.name ~= "") and v.name or nil }
        end
    end
    local best, best_d
    for _i, p in ipairs(type(points) == "table" and points or {}) do
        local t = isoTime(p.time)
        if t and type(p.lat) == "number" and type(p.lon) == "number" then
            local d = math.abs(t - at)
            if not best_d or d < best_d then best, best_d = p, d end
        end
    end
    return best and { lat = best.lat, lon = best.lon } or nil
end

---------------------------------------------------------------- fetching (a background process)

local function get(url, headers, shown)
    local Api = require("gzreader_api")
    local code, data = Api.rawRequest("GET", url, { headers = headers, timeouts = { 10, 20 },
        log_url = shown, expected = { [404] = true } })
    if code ~= 200 then return nil, code end
    return data
end
local function base(url) return (url:match("^(https?://[^?]+)")) or "?" end

--- In the background: Dawarich's place for `at` (through the fork), named.
--- memos = { server, token }. → place or nil, why ("no-dawarich", "none", an error).
function Place.fromDawarich(memos, at, lang)
    if not (memos and memos.server and memos.token) then return nil, "no-dawarich" end
    local headers = { ["Authorization"] = "Bearer " .. memos.token }
    local root = memos.server .. "/api/dawarich"
    local conn = get(root .. "/connection", headers, root .. "/connection")
    if type(conn) ~= "table" or conn.configured ~= true then return nil, "no-dawarich" end
    local r = Place.range(at)
    local visits = get(root .. "/visits?" .. r, headers, root .. "/visits")
    local points = get(root .. "/points?" .. r, headers, root .. "/points")
    local place = Place.placeAt(type(visits) == "table" and visits.visits or nil, type(points) == "table" and points.points or nil, at)
    if not place then return nil, "none" end
    if not place.name then
        local url = Place.reverseUrl(place.lat, place.lon, lang)
        place.name = Place.parseReverse(get(url, nil, base(url)))
    end
    place.source = "dawarich"
    return place
end

--- Is Dawarich connected to this Memos (the fork's /api/dawarich/connection)? In the background.
function Place.dawarichConnected(memos)
    if not (memos and memos.server and memos.token) then return false end
    local root = memos.server .. "/api/dawarich"
    local conn = get(root .. "/connection", { ["Authorization"] = "Bearer " .. memos.token }, root .. "/connection")
    return type(conn) == "table" and conn.configured == true
end

--- In the background: a place by name.
function Place.search(q, lang)
    local url = Place.searchUrl(q, lang)
    local place = Place.parseSearch(get(url, nil, base(url)), q)
    if place then place.source = "search" end
    return place
end

--- In the background: the weather at `place` (or the default city's) at `at`.
function Place.weather(place, settings, at, lang)
    local p = place
    if not (p and p.lat and p.lon and (p.lat ~= 0 or p.lon ~= 0)) then
        local url = settings and Place.cityUrl(settings.defaultCity, lang)
        p = url and Place.parseCity(get(url, nil, base(url)), settings.defaultCity) or nil
    end
    if not p then return nil end
    local unit = settings and settings.temperatureUnit or "fahrenheit"
    local url = Place.weatherUrl(p.lat, p.lon, at, unit)
    return Place.parseWeather(get(url, nil, base(url)), at, unit)
end

--- Runs `fn` (returning plain values) in a background process when the Kindle is online;
--- on_done(...) gets what it returned (or nothing when offline or it failed).
function Place.run(name, fn, on_done)
    local ok_net, Net = pcall(require, "gzreader_net")
    if ok_net and (Net.usb or not Net.connected()) then
        Log.info("journal:", name, "skipped (offline)")
        return on_done()
    end
    require("gzreader_async").background(fn, function(...) on_done(...) end, "journal: " .. name, { timeout = 60 })
end

return Place
