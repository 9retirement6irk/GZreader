-- Journal entries (gzreader_journal.lua) are written exactly as the Memos
-- fork's journaling mode writes them (github.com/9retirement6irk/memos,
-- web/src/lib/journal): its Insights read an entry from a Kindle like one of
-- its own. journal_reference.json is what the fork's own code gives for the
-- same input (composeEntry, feelingsNear, tagSegment, normalizePrefix,
-- mindTags at abb0857; made with Node from its entry.ts, mood.ts, tags.ts).
--   luajit journal_test.lua <gzreader.koplugin> <tests lib>
local PLUGIN, LIB = arg[1], arg[2]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. package.path
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function show(s) return (tostring(s):gsub("\n", "\\n")) end

package.preload["gettext"] = function() return function(t) return t end end
local dkjson = require("dkjson")
local Journal = require("gzreader_journal")
local f = assert(io.open(HERE .. "/journal_reference.json"))
local REF = dkjson.decode(f:read("*a"))
f:close()

local P = { moodTagPrefix = "mood/", feelingTagPrefix = "felt/", impactTagPrefix = "impact/", activityTagPrefix = "did/" }
local function with(t) for k, v in pairs(P) do if t[k] == nil then t[k] = v end end return t end
local function same(name, got) check(got == REF[name], name .. ": as the fork writes it … " .. show(got)) end

print("== an entry, as Memos' journaling mode writes it")
same("full", Journal.compose(with{ heading = "Sunday, November 15, 2026", prompt = "What made you smile?", body = "  A long walk.\n\nThen tea.  ",
    goals = { { label = "Read 20 pages", done = true }, { label = "Stretch", done = false } }, weather = "",
    mind = { valence = "pleasant", kind = "today", feelings = { "grateful", "calm" }, impacts = { "work", "family" } }, mindKind = "today",
    activities = { "reading", "walk" } }))
same("moodOnly", Journal.compose(with{ body = "", goals = {}, mind = { valence = "very-unpleasant", kind = "now", feelings = {}, impacts = {} },
    mindKind = "today", activities = {} }))
same("bodyOnly", Journal.compose(with{ prompt = "What did you learn?", body = "Lua patterns.", goals = {},
    mind = { feelings = { "happy" }, impacts = { "work" } }, mindKind = "today", activities = {} }))
same("promptNoBody", Journal.compose(with{ prompt = "What did you learn?", body = "   ", goals = {},
    mind = { valence = "neutral", feelings = { "nope", "indifferent" }, impacts = { "nope", "weather" } }, mindKind = "now", activities = { "music" } }))
same("prefixes", Journal.compose{ moodTagPrefix = " My Mood //x ", feelingTagPrefix = "", impactTagPrefix = "Why", activityTagPrefix = "Did It/Today/",
    body = "", goals = {}, mind = { valence = "slightly-pleasant", feelings = { "proud" }, impacts = { "self-care" } }, mindKind = "today",
    activities = { "a-walk" } })
same("empty", Journal.compose(with{ body = "", goals = {}, mindKind = "today", activities = {} }))
check(table.concat(Journal.mindTags({ valence = "pleasant", feelings = {}, impacts = {} }, "now", P), " ") == table.concat(REF.mind, " "),
    "a mood without its kind said: the kind given (" .. table.concat(REF.mind, " ") .. ")")
check(#Journal.mindTags({ feelings = { "happy" }, impacts = { "work" } }, "today", P) == 0, "no step chosen: no mood tags at all (feelings and causes describe a step)")

print("== tags and prefixes")
local segs = { "Self Care", " A/B  c ", "Rock & Roll!", "über-Cool__x", "--a--", "C++" }
for i, label in ipairs(segs) do
    check(Journal.tagSegment(label) == REF.seg[i], "tag from “" .. label .. "”: " .. REF.seg[i] .. " … " .. Journal.tagSegment(label))
end
local pres = { "mood/", "Mood", "/a//b/", "", " My Mood //x " }
for i, pre in ipairs(pres) do
    check(Journal.normalizePrefix(pre) == REF.pre[i], "prefix “" .. pre .. "”: “" .. REF.pre[i] .. "” … " .. Journal.normalizePrefix(pre))
end

print("== the feeling words offered: the nearest to the step first")
for _i, v in ipairs(Journal.VALENCES) do
    check(table.concat(Journal.feelingsNear(v), ",") == table.concat(REF.near[v], ","), v .. ": " .. table.concat(REF.near[v], ", ", 1, 5) .. "…")
end
check(table.concat(Journal.feelingsNear(nil), ",") == table.concat(REF.near_none, ","), "no step: all of them, the nearest to neutral first")
local n = 0
for _ in pairs(Journal.FEELINGS) do n = n + 1 end
check(n == 38 and #Journal.IMPACTS == 18 and #Journal.VALENCES == 7 and #Journal.PROMPTS == 8 and Journal.SUGGESTED_FEELINGS == 10,
    "38 feeling words, 18 causes, 7 steps, 8 prompts; 10 words offered")
check(Journal.valenceScore("very-unpleasant") == -1 and Journal.valenceScore("neutral") == 0 and Journal.valenceScore("very-pleasant") == 1,
    "the steps run from -1 to 1")

print("== settings: the fork's, or the defaults (stock Memos)")
local d = Journal.settings(nil)
local ids = {}
for i, a in ipairs(d.activities) do ids[i] = a.id .. "=" .. a.label end
check(d.space == "" and d.moodTagPrefix == "mood/" and d.feelingTagPrefix == "felt/" and d.impactTagPrefix == "impact/" and d.activityTagPrefix == "did/"
    and d.showPrompt == true and d.dateHeading == false and #d.goals == 0
    and table.concat(ids, ",") == "work=Work,exercise=Exercise,family=Family,reading=Reading,music=Music,friends=Friends,travel=Travel,gaming=Gaming,drawing=Drawing",
    "no settings (stock Memos): the fork's defaults: " .. table.concat(ids, ","))
local s = Journal.settings{ space = "spaces/journal", moodTagPrefix = "m/", activities = { { id = "walk", label = "A walk", icon = "tree" }, { id = "nap" }, "junk", { label = "no id" } },
    goals = { "Read", 5, "" }, hiddenImpacts = { "dating", "money" }, showPrompt = false, dateHeading = true, reminderToken = "secret", view = { own = true },
    defaultCity = "Boston, MA" }
check(s.space == "spaces/journal" and s.moodTagPrefix == "m/" and s.feelingTagPrefix == "felt/" and #s.activities == 2 and s.activities[1].label == "A walk"
    and s.activities[2].label == "Nap" and #s.goals == 1 and s.goals[1] == "Read" and s.showPrompt == false and s.dateHeading == true,
    "the server's settings: the space, prefixes, activities (a label from the id when it has none), goals, prompt and heading switches")
check(s.reminderToken == nil and s.view == nil and s.defaultCity == "Boston, MA" and s.activities[1].icon == "tree" and s.activities[2].icon == "star",
    "…and nothing else kept (no tokens; the default city, since 2026-11-19, for the weather); each activity its icon (a star for none)")
check(Journal.settings{ space = "spaces/a b\" || true" }.space == "" and Journal.settings{ space = 5 }.space == "", "a space name that isn't one: none")
local imp = Journal.impacts(s)
check(#imp == 16 and imp[1] == "community" and not table.concat(imp, ","):find("dating") and not table.concat(imp, ","):find("money"),
    "the causes offered: all but the ones you've hidden")

print("== an entry from the journal screen")
local st = { valence = "pleasant", kind = "now", feelings = {}, impacts = {}, activities = {}, goals = {}, body = "", prompt = Journal.PROMPTS[2] }
check(Journal.isEmpty{ feelings = {}, impacts = {}, activities = {}, goals = {}, body = "  \n" } and not Journal.isEmpty(st)
    and not Journal.isEmpty{ activities = { "work" }, goals = {}, body = "" } and not Journal.isEmpty{ activities = {}, goals = { [2] = true }, body = "" }
    and not Journal.isEmpty{ activities = {}, goals = {}, body = "x" },
    "empty until a step, an activity, a goal or words are there")
check(Journal.toggle(st.feelings, "grateful") == true and Journal.toggle(st.feelings, "calm") == true and Journal.toggle(st.feelings, "proud") == true
    and Journal.toggle(st.feelings, "calm") == false and table.concat(st.feelings, ",") == "grateful,proud" and Journal.has(st.feelings, "proud")
    and not Journal.has(st.feelings, "calm"), "choices are kept in the order chosen; a second tap takes one out")
Journal.toggle(st.impacts, "work")
Journal.toggle(st.activities, "walk")
st.goals[1] = true
st.body = "Sun on the porch."
local t = os.time{ year = 2026, month = 11, day = 5, hour = 9 }
check(Journal.entry(st, s, t) == "## Thursday, November 5, 2026\n\nSun on the porch.\n\n- [x] Read\n\n#m/pleasant #m/now #felt/grateful #felt/proud #impact/work #did/walk\n",
    "with your settings (a date heading, no prompt, your prefix and goals): " .. show(Journal.entry(st, s, t)))
check(Journal.entry(st, Journal.settings(nil), t) == "> What made you smile?\n\nSun on the porch.\n\n#mood/pleasant #mood/now #felt/grateful #felt/proud #impact/work #did/walk\n",
    "with the defaults: the prompt quoted above the words, no heading: " .. show(Journal.entry(st, Journal.settings(nil), t)))
check(Journal.heading(t) == "Thursday, November 5, 2026", "the date heading: " .. Journal.heading(t))
check(Journal.words("current-events") == "Current events" and Journal.words("self-care") == "Self care", "ids read as words")

-- the web's look: activities' icons, the mood read from a note's tags, the faces
local d = Journal.settings(nil)
check(d.activities[1].icon == "briefcase" and d.activities[4].icon == "book-open" and d.activities[9].icon == "palette",
    "the default activities with the fork's icons")
local mine = Journal.settings({ activities = { { id = "walk", label = "Walk", icon = "tree" }, { id = "x", icon = "rocket" }, { id = "y" } } })
check(mine.activities[1].icon == "tree" and mine.activities[2].icon == "star" and mine.activities[3].icon == "star",
    "your activities' icons; one GZreader doesn't have, or none: a star (as the web)")
check(Journal.valenceFromTags({ "journal", "mood/pleasant", "mood/today" }) == "pleasant"
    and Journal.valenceFromTags({ "Mood/Very-Unpleasant" }) == "very-unpleasant"
    and Journal.valenceFromTags({ "m/now", "m/great" }, "m") == "very-pleasant"
    and Journal.valenceFromTags({ "mood/okay" }) == "neutral"
    and Journal.valenceFromTags({ "moody/pleasant", "mood/today" }) == nil and Journal.valenceFromTags(nil) == nil,
    "the mood from a note's tags, as the web reads it (your prefix, any case, the five old faces)")
package.preload["ffi/blitbuffer"] = function() return { Color8 = function(v) return v end } end
package.preload["ui/geometry"] = function() return { new = function(_s, o) return o end } end
package.preload["ui/widget/widget"] = function() local c = {}; function c:extend(o) o = o or {}; o.__index = o; function o:new(x) return setmetatable(x or {}, o) end; return o end; return c end
local MF = require("gzreader_moodface")
check(MF.grey("#ffffff") == 255 and MF.grey("#000000") == 0 and MF.grey("#363a8a") == 66, "a web colour as a grey of its lightness")
local light = {}
for i, v in ipairs(MF.VALENCES) do light[i] = MF.greys(v).fill end
check(light[1] < light[2] and light[2] < light[3] and light[3] < light[4] and light[7] < light[6],
    "neighbouring steps differ in lightness (darkest at the ends, as the web's colours)")
local c1, m1 = MF.mouth("very-unpleasant")
local c7, m7 = MF.mouth("very-pleasant")
local c4, m4 = MF.mouth("neutral")
check(m1 < c1 and m7 > c7 and c4 == m4, "the mouth: a frown, a smile, straight in the middle")
check(MF.pixel(20, 20, "neutral") ~= nil and MF.pixel(1, 1, "neutral") == nil and MF.pixel(14, 18, "neutral") == MF.greys("neutral").ink,
    "a round face; its eyes in ink")
check(MF.pixel(20, 32, "neutral", nil, true) > MF.pixel(20, 32, "neutral"), "a face not chosen yet: faded")
local painted = 0
MF.paint({ setPixel = function() painted = painted + 1 end }, 0, 0, 20, "pleasant")
check(painted > 200 and painted < 400, "painted pixel by pixel, the round part only (" .. painted .. " of 400)")

print("== a prompt answered with a drawing; place and weather (the owner, 2026-11-19)")
do
    local base = with{ prompt = "What are you grateful for right now?", body = "", goals = {},
        mind = { valence = "neutral", feelings = {}, impacts = {} }, mindKind = "today", activities = {} }
    local plain = Journal.compose(base)
    base.drawn = true
    local drawn = Journal.compose(base)
    check(not plain:find("> What are you grateful", 1, true) and drawn:find("> What are you grateful for right now?\n\n#mood/neutral", 1, true) == 1,
        "no words: no prompt (as the web); a drawing for an answer: the prompt kept … " .. show(drawn))
    local s = Journal.settings({ addLocation = false, addWeather = true, defaultCity = "Boston, MA", temperatureUnit = "celsius",
        showPrompt = true })
    local d = Journal.settings(nil)
    check(s.addLocation == false and s.addWeather == true and s.defaultCity == "Boston, MA" and s.temperatureUnit == "celsius"
        and d.addLocation == true and d.addWeather == true and d.defaultCity == "" and d.temperatureUnit == "fahrenheit"
        and Journal.settings({ temperatureUnit = "kelvin", defaultCity = 5 }).temperatureUnit == "fahrenheit",
        "settings: add location, add weather, default city, temperature unit (the fork's), kept only when of the right kind")
    local st = { valence = "pleasant", feelings = {}, impacts = {}, activities = {}, goals = {}, body = "Dinner at the deli.",
        prompt = "What are you grateful for right now?", weather = { temperature = 56, unit = "fahrenheit", kind = "clear" } }
    local e = Journal.entry(st, Journal.settings({ showPrompt = true }), os.time())
    check(e:find("> What are you grateful for right now?\n\nDinner at the deli.\n\n56\u{00B0}F, clear\n\n#mood/", 1, true) ~= nil,
        "the weather line after the words, before the tags, as the web writes it … " .. show(e))
    local off = Journal.entry(st, Journal.settings({ addWeather = false }), os.time())
    check(not off:find("56", 1, true), "weather turned off in the journal settings: no line")
end

print("== place and weather (gzreader_journalplace.lua: the fork's weather.ts)")
package.preload["gzreader_log"] = function() return { info = function() end, warn = function() end } end
local Place = require("gzreader_journalplace")
local kinds = {}
for _i, c in ipairs({ 0, 1, 2, 3, 45, 53, 63, 81, 73, 86, 95, 99, 4 }) do kinds[#kinds + 1] = Place.weatherKind(c) end
check(table.concat(kinds, ",") == "clear,mostly-clear,partly-cloudy,cloudy,fog,drizzle,rain,rain,snow,snow,thunderstorm,thunderstorm,cloudy",
    "WMO codes as the fork reads them: " .. table.concat(kinds, ","))
check(Place.weatherLine({ temperature = 56, unit = "fahrenheit", kind = "clear" }) == "56\u{00B0}F, clear"
    and Place.weatherLine({ temperature = -3, unit = "celsius", kind = "partly-cloudy" }) == "-3\u{00B0}C, partly cloudy"
    and Place.weatherLine(nil) == nil, "the weather line: 56°F, clear; -3°C, partly cloudy")
local at = 1795014000 -- 2026-11-18 15:00 UTC
local u = Place.weatherUrl(42.36, -71.06, at, "fahrenheit", at + 3600)
local old = Place.weatherUrl(42.36, -71.06, at - 100 * 86400, "celsius", at)
check(u:find("^https://api%.open%-meteo%.com/v1/forecast%?") ~= nil and u:find("start_date=2026-11-18", 1, true) and u:find("latitude=42.3600", 1, true)
    and u:find("temperature_unit=fahrenheit", 1, true) and u:find("timezone=GMT", 1, true)
    and old:find("^https://archive%-api%.open%-meteo%.com/v1/archive%?") ~= nil and old:find("temperature_unit=celsius", 1, true),
    "Open-Meteo: the forecast for the last three months, the archive before; the day, the place, the unit")
local times, temps, codes = {}, {}, {}
for h = 0, 23 do times[h + 1] = "2026-11-18T" .. string.format("%02d", h) .. ":00"; temps[h + 1] = 40 + h; codes[h + 1] = h == 15 and 0 or 3 end
local w = Place.parseWeather({ hourly = { time = times, temperature_2m = temps, weather_code = codes } }, at, "fahrenheit")
check(w and w.temperature == 55 and w.kind == "clear" and w.unit == "fahrenheit", "the entry's hour picked out of the day (15:00 UTC: 55, clear)")
check(Place.parseWeather({ hourly = { time = times, temperature_2m = {}, weather_code = codes } }, at) == nil
    and Place.parseWeather({}, at) == nil and Place.parseWeather(nil, at) == nil, "no weather in the answer: none")
local cu = Place.cityUrl("Springfield, IL")
local city = Place.parseCity({ results = {
    { latitude = 42.1, longitude = -72.5, name = "Springfield", admin1 = "Massachusetts", admin1_code = "MA", country_code = "US" },
    { latitude = 39.8, longitude = -89.6, name = "Springfield", admin1 = "Illinois", admin1_code = "IL", country_code = "US" } } }, "Springfield, IL")
local first = Place.parseCity({ results = { { latitude = 1, longitude = 2, name = "A" } } }, "A")
check(cu:find("name=Springfield$") ~= nil and not cu:find("IL", 1, true) and city and city.lat == 39.8 and first and first.lat == 1
    and Place.cityUrl("  ") == nil, "the default city: its name asked, the state or country after the comma picks among the answers")
local found = Place.parseSearch({ { lat = "42.31", lon = "-71.11", name = "", display_name = "Jamaica Pond, Boston, MA" } }, "pond")
check(found and found.lat == 42.31 and found.name == "Jamaica Pond" and Place.parseSearch({}, "x") == nil
    and Place.searchUrl("Jason's Deli"):find("q=Jason%27s%20Deli", 1, true) ~= nil,
    "a place by name (OpenStreetMap): its point and a short name")
check(Place.parseReverse({ name = "", address = { suburb = "Jamaica Plain", city = "Boston" } }) == "Jamaica Plain"
    and Place.parseReverse({ name = "Fenway Park" }) == "Fenway Park" and Place.parseReverse({ address = {} }) == nil,
    "a point's short name: its own, else the park, neighbourhood, suburb, city")
check(Place.isoTime("2026-11-18T15:00:00Z") == at and Place.isoTime("2026-11-18T10:00:00-05:00") == at
    and Place.isoTime("2026-11-18T15:00:00.123Z") == at and Place.isoTime("x") == nil, "ISO times (UTC, with an offset) as seconds")
local visits = { { name = "Home", start = "2026-11-18T14:00:00Z", ["end"] = "2026-11-18T16:00:00Z", lat = 1.5, lon = 2.5 } }
local points = { { lat = 3, lon = 4, time = "2026-11-18T14:50:00Z" }, { lat = 5, lon = 6, time = "2026-11-18T15:04:00Z" } }
local pv, pp = Place.placeAt(visits, points, at), Place.placeAt({}, points, at)
check(pv and pv.name == "Home" and pv.lat == 1.5 and pp and pp.lat == 5 and pp.name == nil and Place.placeAt(nil, nil, at) == nil,
    "Dawarich: the visit covering the moment, else the nearest point (the fork's placeAt)")
check(Place.range(at) == "end=2026-11-18T15%3A30%3A00Z&start=2026-11-18T14%3A30%3A00Z", "Dawarich: half an hour either side")
local src = io.open(PLUGIN .. "/gzreader_journalplace.lua"):read("*a")
check(select(2, src:gsub("log_url = shown", "")) == 1 and src:find("local function base(url)", 1, true) ~= nil
    and not src:find("Log.info(.-place%.name") and not src:find("Log.info(.-lat"),
    "privacy: the addresses asked are logged without their query (no place, no coordinates in the log)")

print(("journal: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
