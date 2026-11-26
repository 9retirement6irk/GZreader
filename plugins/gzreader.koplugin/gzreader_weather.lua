--[[--
Weather for the daily paper (gzreader_daily.lua): now and the next days,
fetched with the edition and drawn on the front page as a newspaper's
weather box, each day with a little engraving of its sky.

Where it comes from:
- Home Assistant, when the House tab's is connected: its first weather
  entity (its state and temperature, and its daily forecast when it gives
  one). Nothing leaves your network.
- else Open-Meteo (open-meteo.com: free, no account, no key) for the town
  set in Settings → Home and tabs → Daily paper → Weather. The town's name is sent
  once, to find where it is; after that only its coordinates rounded to two
  decimals (about a kilometre) go with each day's request. Neither the
  town nor the coordinates are written to the log.

What's kept with the edition: { at, unit = "F"|"C", now = { temp, kind },
days = { { day = "2026-11-18", hi, lo, kind, wet = % } } }, no place.
Kinds: clear, partly, cloudy, fog, rain, snow, storm.
]]

local _ = require("gettext")

local Weather = {
    DAYS = 3,
    GEOCODE = "https://geocoding-api.open-meteo.com/v1/search",
    FORECAST = "https://api.open-meteo.com/v1/forecast",
    -- countries that use Fahrenheit (the unit to start with)
    FAHRENHEIT = { US = true, BS = true, KY = true, LR = true, PW = true, FM = true, MH = true },
}

---------------------------------------------------------------- kinds

--- A WMO weather code (Open-Meteo's weather_code) as a kind of sky.
function Weather.kindOfCode(code)
    code = tonumber(code)
    if not code then return nil end
    if code == 0 then return "clear" end
    if code <= 2 then return "partly" end
    if code == 3 then return "cloudy" end
    if code == 45 or code == 48 then return "fog" end
    if (code >= 71 and code <= 77) or code == 85 or code == 86 then return "snow" end
    if code >= 95 then return "storm" end
    if code >= 51 then return "rain" end
    return "cloudy"
end

--- Home Assistant's condition ("partlycloudy", "pouring"…) as a kind of sky.
function Weather.kindOfCondition(s)
    s = tostring(s or ""):lower()
    if s == "sunny" or s == "clear-night" or s == "clear" then return "clear" end
    if s == "partlycloudy" then return "partly" end
    if s == "fog" then return "fog" end
    if s:find("snow", 1, true) or s == "hail" then return "snow" end
    if s:find("lightning", 1, true) then return "storm" end
    if s == "rainy" or s == "pouring" then return "rain" end
    if s == "cloudy" or s == "windy" or s == "windy-variant" or s == "exceptional" then return "cloudy" end
    return nil
end

function Weather.kindLabel(kind)
    if kind == "clear" then return _("Clear") end
    if kind == "partly" then return _("Some cloud") end
    if kind == "cloudy" then return _("Cloudy") end
    if kind == "fog" then return _("Fog") end
    if kind == "rain" then return _("Rain") end
    if kind == "snow" then return _("Snow") end
    if kind == "storm" then return _("Storms") end
    return ""
end

--- "54°".
function Weather.degrees(t)
    t = tonumber(t)
    if not t then return "\u{2013}" end
    local r = math.floor(t + 0.5)
    if r == 0 then r = 0 end -- (no "-0")
    return tostring(r) .. "\u{00B0}"
end

---------------------------------------------------------------- settings

function Weather.store(plugin)
    local daily = require("gzreader_daily").store(plugin)
    daily.weather = type(daily.weather) == "table" and daily.weather or {}
    return daily.weather
end

--- "ha" (the House tab's Home Assistant is connected), "meteo" (a town is
--- set), or nil (nowhere to ask).
function Weather.source(plugin)
    local hs = plugin.store.homeassistant
    if type(hs) == "table" and hs.server and hs.token then return "ha" end
    local w = Weather.store(plugin)
    if tonumber(w.lat) and tonumber(w.lon) then return "meteo" end
    return nil
end

function Weather.on(plugin)
    return Weather.store(plugin).off ~= true and Weather.source(plugin) ~= nil
end

--- What the background fetch needs (plain values): nil when off.
function Weather.plan(plugin)
    if not Weather.on(plugin) then return nil end
    local w = Weather.store(plugin)
    local hs = plugin.store.homeassistant or {}
    return { source = Weather.source(plugin), lat = w.lat, lon = w.lon, unit = w.unit,
        ha = Weather.source(plugin) == "ha" and { server = hs.server, token = hs.token } or nil }
end

---------------------------------------------------------------- Open-Meteo

local function enc(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

--- A JSON answer from Open-Meteo, or nil and why. The address (the town,
--- the coordinates) isn't logged.
function Weather.get(url, what)
    local code, data = require("gzreader_api").rawRequest("GET", url, {
        timeouts = { 10, 30 }, log_url = "https://open-meteo.com/\u{2026} (" .. what .. ")",
    })
    if type(code) ~= "number" then return nil, "unreachable" end
    if code >= 400 or type(data) ~= "table" then return nil, "http_" .. tostring(code) end
    return data
end

--- Where a town is: { lat, lon (rounded to 2 decimals), place = "Albany,
--- New York", unit = "F"|"C" } or nil, "unreachable" / "not found".
function Weather.geocode(town, get)
    town = tostring(town or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if town == "" then return nil, "not found" end
    local data, err = (get or Weather.get)(Weather.GEOCODE .. "?count=1&language=en&format=json&name=" .. enc(town), "weather: town")
    if not data then return nil, err end
    local r = type(data.results) == "table" and data.results[1]
    if type(r) ~= "table" or not tonumber(r.latitude) or not tonumber(r.longitude) then return nil, "not found" end
    local place = tostring(r.name or town)
    local region = r.admin1 or r.country
    if region and region ~= place then place = place .. ", " .. tostring(region) end
    return { lat = math.floor(r.latitude * 100 + 0.5) / 100, lon = math.floor(r.longitude * 100 + 0.5) / 100, place = place,
        unit = Weather.FAHRENHEIT[tostring(r.country_code or ""):upper()] and "F" or "C" }
end

function Weather.forecastUrl(lat, lon, unit)
    return string.format("%s?latitude=%.2f&longitude=%.2f&current=temperature_2m,weather_code"
        .. "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
        .. "&timezone=auto&forecast_days=%d&temperature_unit=%s", Weather.FORECAST, lat, lon, Weather.DAYS,
        unit == "F" and "fahrenheit" or "celsius")
end

--- Open-Meteo's forecast as the paper's weather, or nil.
function Weather.fromMeteo(data, unit, now)
    if type(data) ~= "table" then return nil end
    local out = { at = now or os.time(), unit = unit == "F" and "F" or "C", days = {} }
    local cur = data.current
    if type(cur) == "table" and tonumber(cur.temperature_2m) then
        out.now = { temp = tonumber(cur.temperature_2m), kind = Weather.kindOfCode(cur.weather_code) or "cloudy" }
    end
    local d = data.daily
    if type(d) == "table" and type(d.time) == "table" then
        for i = 1, math.min(#d.time, Weather.DAYS) do
            out.days[#out.days + 1] = { day = tostring(d.time[i]):sub(1, 10),
                hi = tonumber((d.temperature_2m_max or {})[i]), lo = tonumber((d.temperature_2m_min or {})[i]),
                kind = Weather.kindOfCode((d.weather_code or {})[i]) or "cloudy",
                wet = tonumber((d.precipitation_probability_max or {})[i]) }
        end
    end
    if not out.now and #out.days == 0 then return nil end
    return out
end

---------------------------------------------------------------- Home Assistant

--- Home Assistant's weather entity (its state) and daily forecast (a list,
--- or nil) as the paper's weather, or nil.
function Weather.fromHA(state, forecast, now)
    if type(state) ~= "table" then return nil end
    local a = type(state.attributes) == "table" and state.attributes or {}
    local out = { at = now or os.time(), unit = tostring(a.temperature_unit or ""):find("F", 1, true) and "F" or "C", days = {} }
    local kind = Weather.kindOfCondition(state.state)
    if tonumber(a.temperature) and kind then out.now = { temp = tonumber(a.temperature), kind = kind } end
    for _i, f in ipairs(type(forecast) == "table" and forecast or {}) do
        if #out.days >= Weather.DAYS then break end
        if type(f) == "table" and f.datetime then
            out.days[#out.days + 1] = { day = tostring(f.datetime):sub(1, 10), hi = tonumber(f.temperature), lo = tonumber(f.templow),
                kind = Weather.kindOfCondition(f.condition) or "cloudy", wet = tonumber(f.precipitation_probability) }
        end
    end
    if not out.now and #out.days == 0 then return nil end
    return out
end

--- The first weather entity among Home Assistant's states.
function Weather.pickEntity(states)
    for _i, st in ipairs(type(states) == "table" and states or {}) do
        if type(st) == "table" and tostring(st.entity_id or ""):match("^weather%.") and st.state ~= "unavailable" and st.state ~= "unknown" then
            return st
        end
    end
end

---------------------------------------------------------------- fetching (in the background, with the edition)

--- The day's weather for a plan (Weather.plan), or nil and why.
function Weather.fetch(plan, now)
    if type(plan) ~= "table" then return nil, "off" end
    if plan.source == "ha" and plan.ha then
        local HA = require("gzreader_homeassistant")
        local client = HA:new({ server = plan.ha.server, token = plan.ha.token })
        local res = { client:request("GET", "/api/states") }
        local entity = Weather.pickEntity(res[2])
        if not entity then return nil, res[3] or "no weather entity" end
        local forecast
        local answer = ({ client:request("POST", "/api/services/weather/get_forecasts?return_response",
            { entity_id = entity.entity_id, type = "daily" }) })[2]
        if type(answer) == "table" and type(answer.service_response) == "table" then
            local r = answer.service_response[entity.entity_id]
            forecast = type(r) == "table" and r.forecast or nil
        end
        return Weather.fromHA(entity, forecast, now)
    end
    if plan.source == "meteo" and tonumber(plan.lat) and tonumber(plan.lon) then
        local data, err = Weather.get(Weather.forecastUrl(plan.lat, plan.lon, plan.unit), "weather")
        if not data then return nil, err end
        return Weather.fromMeteo(data, plan.unit, now)
    end
    return nil, "off"
end

---------------------------------------------------------------- the box's words

--- The cells of the front page's weather box: { { head, line, kind } }:
--- now, then the days ("Today", "Wed"…).
function Weather.cells(weather, now, max)
    local out = {}
    if type(weather) ~= "table" then return out end
    now = now or os.time()
    local today = os.date("%Y-%m-%d", now)
    if type(weather.now) == "table" then
        out[#out + 1] = { head = _("Now"), line = Weather.degrees(weather.now.temp) .. " " .. Weather.kindLabel(weather.now.kind), kind = weather.now.kind }
    end
    for _i, d in ipairs(type(weather.days) == "table" and weather.days or {}) do
        if #out >= (max or 4) then break end
        if tostring(d.day) >= today then
            local y, m, dd = tostring(d.day):match("^(%d+)%-(%d+)%-(%d+)")
            local head = d.day == today and _("Today")
                or (y and os.date("%a", os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })) or tostring(d.day)
            local line = Weather.degrees(d.hi) .. " / " .. Weather.degrees(d.lo)
            if tonumber(d.wet) and d.wet >= 30 and (d.kind == "rain" or d.kind == "snow" or d.kind == "storm") then
                line = line .. "  " .. math.floor(d.wet + 0.5) .. "%"
            end
            out[#out + 1] = { head = head, line = line, kind = d.kind }
        end
    end
    return out
end

---------------------------------------------------------------- the engravings

local function line(bb, x0, y0, x1, y1, t, c)
    local dx, dy = x1 - x0, y1 - y0
    local n = math.max(math.abs(dx), math.abs(dy), 1)
    for i = 0, n do
        bb:paintRect(math.floor(x0 + dx * i / n + 0.5), math.floor(y0 + dy * i / n + 0.5), t, t, c)
    end
end

--- The shapes of a sky `s` px square, as { { "disc"|"ring"|"line"|"rect",
--- … in tenths of a per cent of s } }: what Weather.icon paints.
function Weather.shapes(kind)
    local sun = {
        { "ring", 500, 500, 190 },
        { "line", 500, 130, 500, 230 }, { "line", 500, 770, 500, 870 }, { "line", 130, 500, 230, 500 }, { "line", 770, 500, 870, 500 },
        { "line", 240, 240, 310, 310 }, { "line", 690, 690, 760, 760 }, { "line", 240, 760, 310, 690 }, { "line", 690, 310, 760, 240 },
    }
    local function cloud(dy)
        return {
            { "cloud", 330, 560 + dy, 150 }, { "cloud", 520, 460 + dy, 210 }, { "cloud", 700, 570 + dy, 140 },
            { "cloudbase", 250, 560 + dy, 540, 150 },
            { "hatch", 330, 640 + dy, 380 }, { "hatch", 400, 590 + dy, 300 },
        }
    end
    local function with(a, b)
        local out = {}
        for _i, s in ipairs(a) do out[#out + 1] = s end
        for _i, s in ipairs(b) do out[#out + 1] = s end
        return out
    end
    if kind == "clear" then return sun end
    if kind == "cloudy" then return cloud(0) end
    if kind == "partly" then
        return with({ { "ring", 330, 330, 150 }, { "line", 330, 60, 330, 130 }, { "line", 60, 330, 130, 330 },
            { "line", 130, 130, 190, 190 }, { "line", 530, 130, 470, 190 }, { "line", 130, 530, 190, 470 } }, cloud(60))
    end
    if kind == "rain" then
        return with(cloud(-140), { { "line", 360, 660, 300, 800 }, { "line", 500, 660, 440, 800 }, { "line", 640, 660, 580, 800 },
            { "line", 430, 830, 390, 920 }, { "line", 570, 830, 530, 920 } })
    end
    if kind == "snow" then
        return with(cloud(-140), { { "flake", 330, 730 }, { "flake", 500, 780 }, { "flake", 670, 730 }, { "flake", 410, 890 }, { "flake", 590, 890 } })
    end
    if kind == "storm" then
        return with(cloud(-140), { { "bold", 540, 630, 430, 780 }, { "bold", 430, 780, 560, 780 }, { "bold", 560, 780, 450, 940 } })
    end
    if kind == "fog" then
        return { { "line", 180, 300, 820, 300 }, { "line", 100, 430, 700, 430 }, { "line", 260, 560, 900, 560 }, { "line", 140, 690, 760, 690 } }
    end
    return cloud(0)
end

--- Paint a sky's engraving, `s` px square, at x, y: black line on white.
function Weather.icon(bb, kind, x, y, s)
    local Blitbuffer = require("ffi/blitbuffer")
    local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    local t = math.max(1, math.floor(s / 22 + 0.5)) -- the line's weight
    local function px(v) return math.floor(v * s / 1000 + 0.5) end
    local shapes = Weather.shapes(kind)
    -- a cloud is its discs and base in black, then the same a line's weight smaller in white
    for pass = 1, 2 do
        for _i, sh in ipairs(shapes) do
            if sh[1] == "cloud" then
                local r = px(sh[4]) - (pass == 2 and t or 0)
                if r > 0 then bb:paintCircle(x + px(sh[2]), y + px(sh[3]), r, pass == 1 and black or white) end
            elseif sh[1] == "cloudbase" then
                local inset = pass == 2 and t or 0
                bb:paintRect(x + px(sh[2]) + inset, y + px(sh[3]), px(sh[4]) - inset * 2, px(sh[5]) - inset, pass == 1 and black or white)
            end
        end
    end
    for _i, sh in ipairs(shapes) do
        if sh[1] == "ring" then
            bb:paintCircle(x + px(sh[2]), y + px(sh[3]), px(sh[4]), black, t)
        elseif sh[1] == "line" then
            line(bb, x + px(sh[2]), y + px(sh[3]), x + px(sh[4]), y + px(sh[5]), t, black)
        elseif sh[1] == "bold" then
            line(bb, x + px(sh[2]), y + px(sh[3]), x + px(sh[4]), y + px(sh[5]), t * 2, black)
        elseif sh[1] == "hatch" then
            bb:paintRect(x + px(sh[2]), y + px(sh[3]), px(sh[4]), 1, Blitbuffer.COLOR_DARK_GRAY)
        elseif sh[1] == "flake" then
            local cx, cy, r = x + px(sh[2]), y + px(sh[3]), math.max(2, px(45))
            line(bb, cx - r, cy, cx + r, cy, 1, black)
            line(bb, cx, cy - r, cx, cy + r, 1, black)
            line(bb, cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1, 1, black)
            line(bb, cx - r + 1, cy + r - 1, cx + r - 1, cy - r + 1, 1, black)
        end
    end
end

return Weather
