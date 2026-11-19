-- A journal entry's place and weather, as the Memos fork's web journal adds
-- them (gzreader_journalplace.lua): where Dawarich had you (through the fork),
-- the weather there (Open-Meteo), a place searched for by name (OpenStreetMap)
-- with the weather again for it; saved as the note's location and a weather
-- line; and the prompt kept with the entry. The services are the mock's
-- stand-ins (/__meteo, /__osm).
--   python3 -I demo/mock_memos.py 18090 --sample --journal --dawarich &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh journal_place.lua <out>
-- Checks go to <out>/journal-place-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function journal() for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_journal" then return w.widget end end end
local function titled(t) for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == t then return w.widget end end end
-- (a dialog's button by its exact text: "Search" is in its title too)
local function dialogButton(E, title, text)
    local d = titled(title)
    local seen = {}
    local function walk(t, depth)
        if type(t) ~= "table" or seen[t] or depth > 40 then return end
        seen[t] = true
        if t.text == text and t.callback and type(t.dimen) == "table" and t.dimen.w then return t end
        for k, v in pairs(t) do
            if k ~= "show_parent" and k ~= "parent" then local r = walk(v, depth + 1); if r then return r end end
        end
    end
    local b = d and walk(d, 0)
    if b then return E.tap({ b.dimen.x + math.floor(b.dimen.w / 2), b.dimen.y + math.floor(b.dimen.h / 2) }) end
    E.say("no button", text)
end
local function mid(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function jb(id) local b = journal() and journal().buttons[id]; return b and b.dimen and mid(b.dimen) end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local function tap(E, p) if MODEL == "scribe" then E.penTap(p) else E.tap(p) end end
local M = "http://127.0.0.1:18090"
local function state() return require("json").decode((require("socket.http").request(M .. "/__state"))) end

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local Place = require("gzreader_journalplace")
    Place.FORECAST, Place.ARCHIVE = M .. "/__meteo/forecast", M .. "/__meteo/archive"
    Place.GEOCODING, Place.NOMINATIM = M .. "/__meteo/geo", M .. "/__osm"
    local p = plugin()
    p.store.memos = { server = M, token = "memos-test-token", prefix = "/api/v1", user = "Will",
        journal = { addLocation = true, addWeather = true, defaultCity = "Exampleton, MA", temperatureUnit = "fahrenheit", showPrompt = true } }
    -- (the emulator is online as far as GZreader can tell)
    local Net = require("gzreader_net")
    Net.connected = function() return true end
    require("gzreader_notes").journal(p)
end, after = 10 })
add({ shot = "1-place-and-weather", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    local st = j and j.state or {}
    check(j and j.dawarich and st.place and st.place.name == "Example Park" and st.place.lat == 42.31,
        "Dawarich (through the fork): where it had you now, as the entry's place (" .. tostring(st.place and st.place.name) .. ")")
    check(st.weather and st.weather.unit == "fahrenheit" and st.weather.kind == "clear" and E.findText("\u{00B0}F, clear") ~= nil,
        "…the weather there (Open-Meteo), shown beside it: " .. tostring(st.weather and require("gzreader_journalplace").weatherLine(st.weather)))
    local asked = state().meteo or {}
    local last = asked[#asked] or {}
    check(last.latitude == "42.3100" and last.longitude == "-71.1100" and last.timezone == "GMT",
        "…asked for that place only (its point and the day): " .. tostring(last.latitude) .. "," .. tostring(last.longitude))
    check(E.findText("Example Park") ~= nil and j.buttons.place ~= nil, "the location above the prompt: Example Park ▾")
    tap(E, jb("place"))
end, after = 3 })
add({ shot = "2-location-menu", after = 0.5 })
add({ fn = function(E)
    check(titled("Location") ~= nil and E.findText("Where Dawarich had you") ~= nil and E.findText("Search for a place") ~= nil
        and E.findText("No location") ~= nil, "the location's menu (the web's): where Dawarich had you, search, no location")
    E.tap("Search for a place")
end, after = 3 })
add({ fn = function(E)
    local d = titled("Search for a place")
    check(d ~= nil, "Search for a place: a box to type in")
    if d then
        d:setInputText("deli")
        dialogButton(E, "Search for a place", "Search")
    end
end, after = 8 })
add({ shot = "3-searched", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    local st = j and j.state or {}
    check(st.place and st.place.name == "Example Deli" and st.place.lat == 42.36 and st.place_source == "search",
        "…a place by name (OpenStreetMap): Example Deli")
    local asked = state().meteo or {}
    check((asked[#asked] or {}).latitude == "42.3600" and st.weather ~= nil, "…and the weather again, for it")
    -- (a step and some words, then Save)
    j:setValence("pleasant")
    if j.input then j.input:setText("Dinner with friends.") else j.state.body = "Dinner with friends." end
    j:rebuild()
end, after = 3 })
add({ fn = function(E) tap(E, jb("save")) end, after = 4 })
add({ fn = function(E)
    -- (online: it's sent at once; the queue's copy, or Memos' own)
    local q = plugin().store.memos.queue or {}
    local last = q[#q] or {}
    local loc, content = last.location, last.content
    if not (content and content:find("Dinner with friends.", 1, true)) then
        for _i, m in ipairs(state().memos or {}) do
            if (m.content or ""):find("Dinner with friends.", 1, true) then loc, content = m.location, m.content end
        end
    end
    content = content or ""
    check(journal() == nil and loc and loc.placeholder == "Example Deli" and loc.latitude == 42.36,
        "Save: the entry with its place as the note's location (in Memos)")
    check(content:find("> ", 1, true) ~= nil and content:find("Dinner with friends.", 1, true) ~= nil
        and content:find("\u{00B0}F, clear\n\n#mood/pleasant", 1, true) ~= nil,
        "…its prompt, its words, the weather line before the tags (as the web writes it): " .. content:gsub("\n", "\\n"))
    local f = io.open(E.out .. "/journal-place-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
