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
check(s.reminderToken == nil and s.view == nil and s.defaultCity == nil and s.activities[1].icon == nil,
    "…and nothing else kept (no tokens, no place)")
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

print(("journal: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
