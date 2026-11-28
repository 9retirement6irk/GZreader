--[[--
The state of mind panel at the foot of a journal entry, as the owner's Memos
fork draws it (web components/Journal/JournalStatePanel.tsx): the mood on its
seven-step scale, the feelings, what they were because of, and what the day
held. It stands for the entry's journal tags (#mood/…, #felt/…, #impact/…,
#did/…), which stay in the note as written; the note page leaves out the
tags it shows (`shown`), and a tap on an item shows the notes with its tag.

On a grey screen the scale's steps carry −3 … +3 and the chosen one is
black: the fork's colours as greys aren't in order (pleasant is about as
light as slightly unpleasant). On a colour screen the scale has the fork's
colours with a ring round the chosen step.

    local st = State.of(memo.tags, journal_settings) -- or nil
    State.widget(st, width, { item = function(tag, w) return w end, colour = false })
]]

local Journal = require("gzreader_journal")

local State = {}

--- An icon for each thing a feeling can be because of (icons/journal/<name>.svg,
--- as the fork's IMPACT_ICONS).
State.IMPACT_ICONS = {
    community = "landmark", ["current-events"] = "newspaper", dating = "heart-handshake", education = "graduation-cap",
    family = "house", fitness = "dumbbell", friends = "users", health = "heart-pulse", hobbies = "palette",
    identity = "fingerprint", money = "wallet", partner = "heart", ["self-care"] = "bath", spirituality = "sparkles",
    tasks = "list-checks", travel = "plane", weather = "cloud-sun", work = "briefcase",
}

local _ = require("gettext")
State.TITLES = {
    feelings = _("Feelings"),
    impacts = _("Because of"),
    activities = _("Did"),
}

-- the tag's value after `prefix` (lowercased), when it's one segment; else nil
local function after(tag, prefix)
    local p = Journal.normalizePrefix(prefix or ""):lower()
    tag = tostring(tag or "")
    if p == "" or tag:lower():sub(1, #p) ~= p then return nil end
    local rest = tag:sub(#p + 1):lower()
    if rest == "" or rest:find("/", 1, true) then return nil end
    return rest
end

local function isImpact(id)
    for _i, v in ipairs(Journal.IMPACTS) do if v == id then return true end end
    return false
end

--- What a note's tags (without "#") say, as the panel shows it, or nil when
--- there's nothing it can draw:
--- { valence, kind = "today"|"now", mood_tag, feelings = { { id, tag, label } },
---   impacts = { { id, tag, label, icon } }, activities = { { id, tag, label, icon } },
---   shown = { [lowercased tag] = true } }
function State.of(tags, settings)
    settings = settings or Journal.defaults()
    tags = tags or {}
    local shown = {}
    local st = { feelings = {}, impacts = {}, activities = {}, shown = shown }
    st.valence = Journal.valenceFromTags(tags, settings.moodTagPrefix)
    if st.valence then
        st.kind = "today"
        for _i, t in ipairs(tags) do
            local v = after(t, settings.moodTagPrefix)
            if v then
                if Journal.valenceFromTags({ t }, settings.moodTagPrefix) then
                    st.mood_tag = st.mood_tag or t
                    shown[t:lower()] = true
                elseif v == "today" or v == "now" then
                    if v == "now" then st.kind = "now" end
                    shown[t:lower()] = true
                end
            end
        end
    end
    local function gather(list, prefix, accept, make)
        local seen = {}
        for _i, t in ipairs(tags) do
            local id = after(t, prefix)
            if id and not seen[id] and accept(id) then
                seen[id] = true
                local item = { id = id, tag = t }
                make(item)
                list[#list + 1] = item
                shown[t:lower()] = true
            end
        end
    end
    gather(st.feelings, settings.feelingTagPrefix, function(id) return Journal.FEELINGS[id] ~= nil end,
        function(it) it.label = Journal.words(it.id) end)
    gather(st.impacts, settings.impactTagPrefix, isImpact,
        function(it) it.label = Journal.words(it.id); it.icon = State.IMPACT_ICONS[it.id] or "sparkles" end)
    gather(st.activities, settings.activityTagPrefix, function() return true end, function(it)
        for _i, a in ipairs(settings.activities or {}) do
            if tostring(a.id):lower() == it.id then it.label, it.icon = a.label, a.icon end
        end
        it.label = it.label or Journal.words(it.id)
        it.icon = it.icon or "star"
    end)
    if not st.valence and #st.feelings == 0 and #st.impacts == 0 and #st.activities == 0 then return nil end
    return st
end

--- Is `tag` one the panel draws for this note?
function State.isShown(st, tag)
    return st ~= nil and st.shown[tostring(tag or ""):lower()] == true
end

--- The scale's steps: { label, chosen, fill } for each of the seven. `fill`
--- is a colour ("#rrggbb") on a colour screen: the fork's, made lighter
--- (as its 45% opacity on the panel's grey) for the steps not chosen.
function State.steps(valence, colour)
    local out = {}
    local MoodFace = colour and require("gzreader_moodface")
    for i, v in ipairs(Journal.VALENCES) do
        local step = { label = Journal.VALENCE_SHORT[i], chosen = v == valence, valence = v }
        if colour then
            local hex = MoodFace.COLORS[v][1]
            if not step.chosen then
                local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
                local function mix(c) return math.floor(c * 0.45 + 0xEE * 0.55 + 0.5) end
                hex = string.format("#%02x%02x%02x", mix(r), mix(g), mix(b))
            end
            step.fill = hex
        end
        out[i] = step
    end
    return out
end

---------------------------------------------------------------- drawing

State.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/journal/"

function State.iconPath(name)
    local lfs = require("libs/libkoreader-lfs")
    local p = State.ICON_DIR .. tostring(name) .. ".svg"
    if lfs.attributes(p, "mode") == "file" then return p end
    return State.ICON_DIR .. "star.svg"
end

--- The panel `width` wide. opts.item(tag, widget, label) makes an item
--- tappable (and returns what to show); opts.colour: the colour screen's look.
function State.widget(st, width, opts)
    opts = opts or {}
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local Screen = require("device").screen
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    local function S(px) return Screen:scaleBySize(px) end
    local function rgb(hex)
        return Blitbuffer.ColorRGB32(tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16), 0xFF)
    end
    local item = opts.item or function(_tag, w) return w end
    local pad = S(12)
    local inner = width - 2 * pad - 2 * Size.border.thin
    local GREY = Blitbuffer.Color8(0x55)
    local face = function(size, bold) return Font:getFace(bold and "NotoSans-Bold.ttf" or "cfont", size) or Font:getFace("cfont", size) end
    local italic = Font:getFace("NotoSans-Italic.ttf", 16) or face(16)
    local col = VerticalGroup:new{ align = "left" }
    local function add(w) col[#col + 1] = w end
    local function gap(px) add(VerticalSpan:new{ width = S(px) }) end

    -- items in rows, as many as fit
    local function flow(list, between)
        local g = VerticalGroup:new{ align = "left" }
        local row, used
        for _i, w in ipairs(list) do
            local ww = w:getSize().w
            if not row or used + between + ww > inner then
                if row then g[#g + 1] = VerticalSpan:new{ width = between } end
                row, used = HorizontalGroup:new{ align = "top" }, 0
                g[#g + 1] = row
            else
                row[#row + 1] = HorizontalSpan:new{ width = between }
                used = used + between
            end
            row[#row + 1] = w
            used = used + ww
        end
        return g
    end
    local function title(text)
        add(TextWidget:new{ text = text, face = face(13, true), fgcolor = GREY })
        gap(6)
    end
    local function chip(content)
        return FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, color = Blitbuffer.Color8(0x88),
            bordersize = Size.border.thin, radius = S(6), margin = 0, padding = 0,
            padding_left = S(12), padding_right = S(12), padding_top = S(6), padding_bottom = S(6), content }
    end

    if st.valence then
        local MoodFace = require("gzreader_moodface")
        local fsize = S(30)
        local kind = TextWidget:new{ text = Journal.KIND_LABELS[st.kind or "today"], face = face(14, true), fgcolor = GREY }
        local label = Journal.VALENCE_LABELS[st.valence] or st.valence
        local name = TextWidget:new{ text = label, face = face(17, true) }
        name = st.mood_tag and item(st.mood_tag, FrameContainer:new{ bordersize = 0, padding = S(4), margin = 0, name }, label) or name
        local room = inner - fsize - S(10) - kind:getSize().w - name:getSize().w
        add(HorizontalGroup:new{ align = "center", MoodFace.widget{ valence = st.valence, size = fsize },
            HorizontalSpan:new{ width = S(10) }, kind, HorizontalSpan:new{ width = math.max(S(8), room) }, name })
        gap(8)
        -- the seven steps
        local between = S(3)
        local cell = math.floor((inner - 6 * between) / 7)
        local h = opts.colour and S(14) or S(26)
        local steps = HorizontalGroup:new{ align = "center" }
        for i, step in ipairs(State.steps(st.valence, opts.colour)) do
            if i > 1 then steps[#steps + 1] = HorizontalSpan:new{ width = between } end
            local content
            if not opts.colour then
                content = TextWidget:new{ text = step.label, face = face(step.chosen and 14 or 13, step.chosen),
                    fgcolor = step.chosen and Blitbuffer.COLOR_WHITE or GREY }
            end
            -- (every step the same size outside, whatever its border)
            local border = step.chosen and Size.border.thick or (opts.colour and 0 or Size.border.thin)
            local frame = FrameContainer:new{
                background = opts.colour and rgb(step.fill) or (step.chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE),
                color = step.chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.Color8(0x99),
                bordersize = border,
                radius = (i == 1 or i == 7) and math.floor(h / 2) or 0, margin = 0, padding = 0,
                CenterContainer:new{ dimen = Geom:new{ w = cell - 2 * border, h = h - 2 * border }, content or VerticalSpan:new{ width = 0 } },
            }
            steps[#steps + 1] = frame
        end
        add(steps)
    end

    local function section(key, list, make, between)
        if #list == 0 then return end
        if #col > 0 then gap(14) end
        title(State.TITLES[key])
        local ws = {}
        for _i, it in ipairs(list) do ws[#ws + 1] = item(it.tag, make(it), it.label) end
        add(flow(ws, between))
    end
    section("feelings", st.feelings, function(it)
        return chip(TextWidget:new{ text = it.label, face = italic, max_width = inner - S(26) })
    end, S(8))
    section("impacts", st.impacts, function(it)
        return chip(HorizontalGroup:new{ align = "center",
            IconWidget:new{ file = State.iconPath(it.icon), width = S(18), height = S(18), alpha = true },
            HorizontalSpan:new{ width = S(6) },
            TextWidget:new{ text = it.label, face = face(16), max_width = inner - S(50) } })
    end, S(8))
    section("activities", st.activities, function(it)
        local tw = S(72)
        return VerticalGroup:new{ align = "center",
            FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, color = Blitbuffer.Color8(0x88),
                bordersize = Size.border.thin, radius = S(10), margin = 0, padding = 0,
                CenterContainer:new{ dimen = Geom:new{ w = S(50), h = S(50) },
                    IconWidget:new{ file = State.iconPath(it.icon), width = S(28), height = S(28), alpha = true } } },
            VerticalSpan:new{ width = S(4) },
            CenterContainer:new{ dimen = Geom:new{ w = tw, h = S(18) },
                TextWidget:new{ text = it.label, face = face(13), max_width = tw } },
        }
    end, S(10))

    return FrameContainer:new{ background = Blitbuffer.Color8(0xEE), color = Blitbuffer.Color8(0xCC),
        bordersize = Size.border.thin, radius = S(10), margin = 0, padding = pad, width = width,
        col, gz_label = _("State of mind") }
end

return State
