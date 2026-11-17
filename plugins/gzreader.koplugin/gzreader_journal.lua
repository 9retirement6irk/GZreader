--[[--
Journal entries, as the Memos fork's journaling mode writes them
(github.com/9retirement6irk/memos, web/src/lib/journal).

A journal entry is an ordinary note. How you felt and what you did are tags
(#mood/pleasant #mood/today #felt/grateful #impact/work #did/reading), goals
are a checklist, so any Memos shows and searches it whole. This module is the
words and the writing (no screen: gzreader_journalscreen.lua); it must write
an entry exactly as the web editor does, so the fork's Insights read entries
from a Kindle like its own.

The fork keeps each user's journal settings at /api/journal/settings (which
space entries go to, tag prefixes, activities, goals). A Memos without it
(stock Memos) gets the defaults.
]]

local _ = require("gettext")

local Journal = {}

--- From very unpleasant to very pleasant (the fork's VALENCES, Apple's seven steps).
Journal.VALENCES = {
    "very-unpleasant", "unpleasant", "slightly-unpleasant", "neutral", "slightly-pleasant", "pleasant", "very-pleasant",
}
Journal.VALENCE_LABELS = {
    ["very-unpleasant"] = _("Very unpleasant"), ["unpleasant"] = _("Unpleasant"),
    ["slightly-unpleasant"] = _("Slightly unpleasant"), ["neutral"] = _("Neutral"),
    ["slightly-pleasant"] = _("Slightly pleasant"), ["pleasant"] = _("Pleasant"), ["very-pleasant"] = _("Very pleasant"),
}
--- (short, for seven buttons in a row)
Journal.VALENCE_SHORT = { "\u{2212}3", "\u{2212}2", "\u{2212}1", "0", "+1", "+2", "+3" }

Journal.KINDS = { "today", "now" }
Journal.KIND_LABELS = { today = _("Overall today"), now = _("Right now") }

--- The fork's feeling words, with where each usually sits from -1 to 1.
Journal.FEELINGS = {
    amazed = 0.9, amused = 0.6, angry = -0.9, annoyed = -0.4, anxious = -0.7, ashamed = -0.8, brave = 0.6, calm = 0.3,
    confident = 0.7, content = 0.4, disappointed = -0.5, discouraged = -0.6, disgusted = -0.8, drained = -0.4,
    embarrassed = -0.5, excited = 0.9, frustrated = -0.6, grateful = 0.7, guilty = -0.6, happy = 0.8, hopeful = 0.5,
    hopeless = -1, indifferent = 0, irritated = -0.4, jealous = -0.5, joyful = 1, lonely = -0.6, overwhelmed = -0.7,
    passionate = 0.8, peaceful = 0.5, proud = 0.8, relieved = 0.4, sad = -0.7, satisfied = 0.5, scared = -0.8,
    stressed = -0.6, surprised = 0.1, worried = -0.5,
}

--- What's behind a feeling.
Journal.IMPACTS = {
    "community", "current-events", "dating", "education", "family", "fitness", "friends", "health", "hobbies", "identity",
    "money", "partner", "self-care", "spirituality", "tasks", "travel", "weather", "work",
}

Journal.SUGGESTED_FEELINGS = 10

--- The fork's prompts (journal.prompt.p1 to p8).
Journal.PROMPTS = {
    _("What's one small thing you want to remember about today?"),
    _("What made you smile?"),
    _("What did you learn?"),
    _("What are you grateful for right now?"),
    _("What took most of your energy?"),
    _("Who did you spend time with?"),
    _("What would you do differently?"),
    _("What are you looking forward to?"),
}

Journal.DEFAULT_ACTIVITIES = { "work", "exercise", "family", "reading", "music", "friends", "travel", "gaming", "drawing" }
-- each one's icon, as the fork's defaults (lib/journal/settings.ts), and the icons an activity can have
Journal.DEFAULT_ICONS = { work = "briefcase", exercise = "dumbbell", family = "users", reading = "book-open", music = "music",
    friends = "coffee", travel = "plane", gaming = "gamepad", drawing = "palette" }
Journal.ACTIVITY_ICONS = { "briefcase", "dumbbell", "users", "book-open", "music", "coffee", "plane", "gamepad", "palette",
    "utensils", "tree", "heart", "star" }

local function words(id) -- "current-events" → "Current events"
    local s = tostring(id):gsub("%-", " ")
    return (s:gsub("^%l", string.upper))
end
Journal.words = words

--- A tag segment from a label: lowercase, words joined by "-", only what tags allow.
function Journal.tagSegment(label)
    local s = tostring(label or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    s = s:gsub("[%s/]+", "-")
    -- letters and digits (any script: bytes of UTF-8 kept), _ - + &
    s = s:gsub("[^%w_%-+&\128-\255]", "")
    s = s:gsub("%-+", "-"):gsub("^%-", ""):gsub("%-$", "")
    return s
end

--- A tag prefix as typed, ending in one "/" when it isn't empty.
function Journal.normalizePrefix(prefix)
    local parts = {}
    for seg in (tostring(prefix or "") .. "/"):gmatch("([^/]*)/") do
        local s = Journal.tagSegment(seg)
        if s ~= "" then parts[#parts + 1] = s end
    end
    return #parts > 0 and (table.concat(parts, "/") .. "/") or ""
end

local function indexOf(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

--- A step as a number from -1 to 1.
function Journal.valenceScore(valence)
    return ((indexOf(Journal.VALENCES, valence) or 4) - 4) / 3
end

--- Feeling words, the nearest to a step first (all of them, nearest neutral first, without one).
function Journal.feelingsNear(valence)
    local score = valence and Journal.valenceScore(valence) or 0
    local ids = {}
    for id in pairs(Journal.FEELINGS) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local da, db = math.abs(Journal.FEELINGS[a] - score), math.abs(Journal.FEELINGS[b] - score)
        if math.abs(da - db) > 1e-9 then return da < db end
        return a < b
    end)
    return ids
end

--- The settings a user starts with (the fork's defaultJournalSettings; only what a Kindle uses).
function Journal.defaults()
    local acts = {}
    for i, id in ipairs(Journal.DEFAULT_ACTIVITIES) do acts[i] = { id = id, label = words(id), icon = Journal.DEFAULT_ICONS[id] } end
    return {
        space = "", moodTagPrefix = "mood/", feelingTagPrefix = "felt/", impactTagPrefix = "impact/", hiddenImpacts = {},
        activityTagPrefix = "did/", activities = acts, goals = {}, showPrompt = true, dateHeading = false,
    }
end

local function strings(list)
    local out = {}
    for _i, v in ipairs(type(list) == "table" and list or {}) do
        if type(v) == "string" and v ~= "" then out[#out + 1] = v end
    end
    return out
end

--- Settings from the server's document (or nil: the defaults), keeping only
--- what's of the right kind. Nothing but these fields is kept on the Kindle.
function Journal.settings(stored)
    local s = Journal.defaults()
    if type(stored) ~= "table" then return s end
    for _i, k in ipairs({ "space", "moodTagPrefix", "feelingTagPrefix", "impactTagPrefix", "activityTagPrefix" }) do
        if type(stored[k]) == "string" then s[k] = stored[k] end
    end
    for _i, k in ipairs({ "showPrompt", "dateHeading" }) do
        if type(stored[k]) == "boolean" then s[k] = stored[k] end
    end
    if not s.space:match("^spaces/[A-Za-z0-9_-]+$") then s.space = "" end
    if type(stored.hiddenImpacts) == "table" then s.hiddenImpacts = strings(stored.hiddenImpacts) end
    if type(stored.goals) == "table" then s.goals = strings(stored.goals) end
    if type(stored.activities) == "table" then
        local acts = {}
        for _i, a in ipairs(stored.activities) do
            if type(a) == "table" and type(a.id) == "string" and a.id ~= "" then
                local icon = type(a.icon) == "string" and indexOf(Journal.ACTIVITY_ICONS, a.icon) and a.icon or "star"
                acts[#acts + 1] = { id = a.id, label = (type(a.label) == "string" and a.label ~= "") and a.label or words(a.id), icon = icon }
            end
        end
        s.activities = acts
    end
    return s
end

--- The causes offered (the user's hidden ones left out).
function Journal.impacts(settings)
    local hidden = {}
    for _i, id in ipairs(settings and settings.hiddenImpacts or {}) do hidden[id] = true end
    local out = {}
    for _i, id in ipairs(Journal.IMPACTS) do if not hidden[id] then out[#out + 1] = id end end
    return out
end

--- The tags that record a state of mind, in the order they're written. Nothing without a step.
-- the five faces the fork's mood scale replaced, read as the nearest step
Journal.LEGACY_MOODS = { awful = "very-unpleasant", bad = "unpleasant", okay = "neutral", good = "pleasant", great = "very-pleasant" }

--- The step a note's tags record (`tags` without "#"), as the web reads it
--- (moodFromTags: the mood prefix, then a step or one of the old faces), or nil.
function Journal.valenceFromTags(tags, prefix)
    local p = Journal.normalizePrefix(prefix or "mood/"):lower()
    if p == "" then return nil end
    for _i, t in ipairs(tags or {}) do
        t = tostring(t):lower()
        if t:sub(1, #p) == p then
            local v = t:sub(#p + 1)
            if indexOf(Journal.VALENCES, v) then return v end
            if Journal.LEGACY_MOODS[v] then return Journal.LEGACY_MOODS[v] end
        end
    end
    return nil
end

--- mind: { valence, kind, feelings = {…}, impacts = {…} }
function Journal.mindTags(mind, kind, prefixes)
    if not (mind and mind.valence and indexOf(Journal.VALENCES, mind.valence)) then return {} end
    local mood = Journal.normalizePrefix(prefixes.moodTagPrefix)
    local out = { "#" .. mood .. mind.valence, "#" .. mood .. (mind.kind or kind or "today") }
    for _i, id in ipairs(mind.feelings or {}) do
        if Journal.FEELINGS[id] then out[#out + 1] = "#" .. Journal.normalizePrefix(prefixes.feelingTagPrefix) .. id end
    end
    for _i, id in ipairs(mind.impacts or {}) do
        if indexOf(Journal.IMPACTS, id) then out[#out + 1] = "#" .. Journal.normalizePrefix(prefixes.impactTagPrefix) .. id end
    end
    return out
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

--- The entry as Markdown (the fork's composeEntry).
--- parts: heading, prompt, body, goals = { { label, done } }, weather, mind,
--- mindKind, activities = { ids }, and the settings' tag prefixes.
function Journal.compose(parts)
    local blocks = {}
    local body = trim(parts.body)
    if parts.heading and parts.heading ~= "" then blocks[#blocks + 1] = "## " .. parts.heading end
    if parts.prompt and parts.prompt ~= "" and body ~= "" then blocks[#blocks + 1] = "> " .. parts.prompt end
    if body ~= "" then blocks[#blocks + 1] = body end
    if parts.goals and #parts.goals > 0 then
        local lines = {}
        for i, g in ipairs(parts.goals) do lines[i] = "- [" .. (g.done and "x" or " ") .. "] " .. g.label end
        blocks[#blocks + 1] = table.concat(lines, "\n")
    end
    if parts.weather and parts.weather ~= "" then blocks[#blocks + 1] = parts.weather end
    local tags = parts.mind and Journal.mindTags(parts.mind, parts.mindKind, parts) or {}
    for _i, id in ipairs(parts.activities or {}) do
        tags[#tags + 1] = "#" .. Journal.normalizePrefix(parts.activityTagPrefix) .. id
    end
    if #tags > 0 then blocks[#blocks + 1] = table.concat(tags, " ") end
    return table.concat(blocks, "\n\n") .. "\n"
end

--- The date heading ("Sunday, November 15, 2026", as the web editor writes it in English).
function Journal.heading(time)
    local t = os.date("*t", time)
    return os.date("%A, %B ", time) .. t.day .. ", " .. t.year
end

--- Adds `id` to a list of choices, or takes it out (in the order chosen, as the web editor keeps them).
function Journal.toggle(list, id)
    for i, v in ipairs(list) do
        if v == id then table.remove(list, i); return false end
    end
    list[#list + 1] = id
    return true
end

function Journal.has(list, id) return indexOf(list or {}, id) ~= nil end

--- An entry from the journal screen's state and the settings.
--- state: valence, kind, feelings, impacts, activities (lists of ids, in the
--- order chosen), goals = { [i] = true }, prompt, body
function Journal.entry(state, settings, time)
    local goals = {}
    for i, label in ipairs(settings.goals or {}) do goals[i] = { label = label, done = state.goals and state.goals[i] == true } end
    return Journal.compose{
        heading = settings.dateHeading and Journal.heading(time) or nil,
        prompt = settings.showPrompt and state.prompt or nil,
        body = state.body or "",
        goals = goals,
        mind = { valence = state.valence, kind = state.kind, feelings = state.feelings or {}, impacts = state.impacts or {} },
        mindKind = "today",
        activities = state.activities or {},
        moodTagPrefix = settings.moodTagPrefix, feelingTagPrefix = settings.feelingTagPrefix,
        impactTagPrefix = settings.impactTagPrefix, activityTagPrefix = settings.activityTagPrefix,
    }
end

--- Is there anything to save?
function Journal.isEmpty(state)
    if state.valence or trim(state.body) ~= "" then return false end
    if #(state.activities or {}) > 0 then return false end
    for _k, v in pairs(state.goals or {}) do if v then return false end end
    return true
end

return Journal
