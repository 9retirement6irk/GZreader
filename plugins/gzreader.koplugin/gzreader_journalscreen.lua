--[[--
A journal entry (the Notes tab's Journal button; J): the Memos fork's
journaling mode on a Kindle (words and writing: gzreader_journal.lua).

  How have you felt?   [Overall today] [Right now]
  ○ ○ ○ ○ ● ○ ○        seven steps, very unpleasant to very pleasant
  What best describes this feeling?   the ten words nearest the step, More…
  What's behind it…                   causes (work, family, health…)
  What did you do?                    your activities
  Goals                               your goals, ticked when done
  A prompt, Another prompt, Write about it…
  Save

The entry is saved as an ordinary note (its mood and activities as tags), so
it reads the same in Memos and in the fork's Insights.

Every control is a button: a tap on touch Kindles; the 5-way moves and Press
picks on Kindles with keys; a keyboard Kindle has a key for each too
(1–7 the step, T today / right now, F feelings, I what's behind it,
A activities, G goals, P another prompt, W write, S save).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Journal = require("gzreader_journal")
local Touch = require("gzreader_touch")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local JournalScreen = FocusManager:extend{
    name = "gz_journal",
    covers_fullscreen = true,
    settings = nil, -- Journal.settings(…)
    on_save = nil,  -- on_save(content): the entry, as a note's text
    state = nil,
}

JournalScreen.MOOD_KEYS = { "1", "2", "3", "4", "5", "6", "7" }
JournalScreen.MOOD_ROW = { "Q", "W", "E", "R", "T", "Y", "U" } -- (Alt + these: the Kindle Keyboard's digits)

function JournalScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.settings = self.settings or Journal.settings()
    self.state = self.state or {
        kind = "today", feelings = {}, impacts = {}, activities = {}, goals = {}, body = "",
        prompt_i = (self.prompt_i or (os.time() % #Journal.PROMPTS)) % #Journal.PROMPTS + 1,
    }
    self.state.prompt = Journal.PROMPTS[self.state.prompt_i]
    self.key_events.Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } }
    -- touch: a swipe down from the top opens the quick panel, as at Home and in a book
    if Touch.on() and self.plugin then
        self.ges_events = self.ges_events or {}
        self.ges_events.PullPanel = { require("ui/gesturerange"):new{ ges = "swipe",
            range = function() return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = S(64) } end } }
    end
    if Touch.keys() then
        self.key_events.GzMood = { { JournalScreen.MOOD_KEYS }, { "Alt", JournalScreen.MOOD_KEYS }, { "Alt", JournalScreen.MOOD_ROW } }
        self.key_events.GzKey = { { { "T", "F", "I", "A", "G", "P", "W", "S" } } }
    end
    self:build()
end

-- ------------------------------------------------------------ what's chosen

function JournalScreen:setValence(v)
    local st = self.state
    if st.valence == v then
        -- the chosen step again: no mood (and nothing that describes one)
        st.valence, st.feelings, st.impacts = nil, {}, {}
    else
        st.valence = v
    end
    for i, x in ipairs(Journal.VALENCES) do
        if x == v then return self:rebuild("mood-" .. i) end
    end
end

--- The feeling words offered in the page (the nearest to the step, and any chosen).
function JournalScreen:feelingChips()
    local near = Journal.feelingsNear(self.state.valence)
    local out, seen = {}, {}
    for i = 1, Journal.SUGGESTED_FEELINGS do out[i] = near[i]; seen[near[i]] = true end
    for _i, id in ipairs(self.state.feelings) do
        if not seen[id] then out[#out + 1] = id end
    end
    return out
end

function JournalScreen:summary(list, labels, none)
    if #list == 0 then return none end
    local names = {}
    for i, id in ipairs(list) do names[i] = labels and labels[id] or Journal.words(id) end
    return table.concat(names, ", ")
end

function JournalScreen:goalsDone()
    local n = 0
    for i = 1, #self.settings.goals do if self.state.goals[i] then n = n + 1 end end
    return n
end

--- The entry as it would be saved.
function JournalScreen:content() return Journal.entry(self.state, self.settings, os.time()) end

-- ------------------------------------------------------------ dialogs

--- Pick any of `items` ({ id, label }): a ✓ on the chosen; Done closes.
function JournalScreen:pickMany(title, items, has, toggle, focus_id)
    local dialog
    local per = Touch.on() and 3 or 2
    local function show()
        local rows, row = {}, {}
        for _i, it in ipairs(items) do
            row[#row + 1] = { text = (has(it.id) and "\u{2713} " or "") .. it.label, callback = function()
                toggle(it.id)
                UIManager:close(dialog)
                show()
            end }
            if #row == per then rows[#rows + 1] = row; row = {} end
        end
        if #row > 0 then rows[#rows + 1] = row end
        rows[#rows + 1] = { { text = _("Done"), font_bold = true, callback = function()
            UIManager:close(dialog)
            self.picker = nil
            self:rebuild(focus_id)
        end } }
        dialog = ButtonDialog:new{ title = title, buttons = rows, tap_close_callback = function()
            self.picker = nil
            self:rebuild(focus_id)
        end }
        self.picker = dialog
        UIManager:show(dialog)
    end
    show()
    return dialog
end

function JournalScreen:pickFeelings()
    local items = {}
    for _i, id in ipairs(Journal.feelingsNear(self.state.valence)) do items[#items + 1] = { id = id, label = Journal.words(id) } end
    return self:pickMany(_("What best describes this feeling?"), items,
        function(id) return Journal.has(self.state.feelings, id) end,
        function(id) Journal.toggle(self.state.feelings, id) end, "more")
end

function JournalScreen:pickImpacts()
    local items = {}
    for _i, id in ipairs(Journal.impacts(self.settings)) do items[#items + 1] = { id = id, label = Journal.words(id) } end
    return self:pickMany(_("What's having the biggest impact?"), items,
        function(id) return Journal.has(self.state.impacts, id) end,
        function(id) Journal.toggle(self.state.impacts, id) end, "impact")
end

function JournalScreen:pickActivities()
    local items = {}
    for _i, a in ipairs(self.settings.activities) do items[#items + 1] = { id = a.id, label = a.label } end
    return self:pickMany(_("What did you do?"), items,
        function(id) return Journal.has(self.state.activities, id) end,
        function(id) Journal.toggle(self.state.activities, id) end, "did")
end

function JournalScreen:pickGoals()
    if #self.settings.goals == 0 then return end
    local items = {}
    for i, label in ipairs(self.settings.goals) do items[#items + 1] = { id = i, label = label } end
    return self:pickMany(_("Goals done today"), items,
        function(i) return self.state.goals[i] == true end,
        function(i) self.state.goals[i] = not self.state.goals[i] or nil end, "goals")
end

--- Write about it: the words of the entry.
function JournalScreen:write()
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{
        title = (self.settings.showPrompt and self.state.prompt) or _("Write about it"),
        input = self.state.body, input_hint = _("Write about it…"),
        allow_newline = true, use_available_height = true, gz_multiline = true,
        buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Done"), callback = function()
                self.state.body = d:getInputText() or ""
                UIManager:close(d)
                self:rebuild("write")
            end } } },
    }
    self.writer = d
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

function JournalScreen:nextPrompt()
    self.state.prompt_i = self.state.prompt_i % #Journal.PROMPTS + 1
    self.state.prompt = Journal.PROMPTS[self.state.prompt_i]
    self:rebuild("prompt")
end

function JournalScreen:save()
    if Journal.isEmpty(self.state) then
        return UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3,
            text = _("Nothing to save yet. Choose how you felt, or write something.") })
    end
    local content = self:content()
    self.saved = true
    UIManager:close(self, "full")
    if self.on_save then self.on_save(content) end
end

function JournalScreen:onClose()
    if Journal.isEmpty(self.state) then UIManager:close(self, "full"); return true end
    local dialog
    dialog = ButtonDialog:new{ title = _("Save this journal entry?"), buttons = {
        { { text = _("Save"), align = "left", callback = function() UIManager:close(dialog); self:save() end } },
        { { text = _("Discard"), align = "left", callback = function() UIManager:close(dialog); UIManager:close(self, "full") end } },
        { { text = _("Keep going"), align = "left", callback = function() UIManager:close(dialog) end } },
    } }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return true
end

-- ------------------------------------------------------------ keys

--- A swipe down from the top: the quick panel over the entry (kept as it is under it).
function JournalScreen:onPullPanel(_arg, ges)
    if not (ges and ges.direction == "south") then return false end
    require("gzreader_panel").show(self.plugin)
    return true
end

function JournalScreen:onGzMood(_args, key)
    local k = type(key) == "table" and key.key or key
    for i = 1, 7 do
        if k == JournalScreen.MOOD_KEYS[i] or k == JournalScreen.MOOD_ROW[i] then
            self:setValence(Journal.VALENCES[i])
            return true
        end
    end
    return false
end

function JournalScreen:onGzKey(_args, key)
    local k = type(key) == "table" and key.key or key
    if k == "T" then
        self.state.kind = self.state.kind == "today" and "now" or "today"
        self:rebuild("kind-" .. self.state.kind)
    elseif k == "F" then if self.state.valence then self:pickFeelings() end
    elseif k == "I" then if self.state.valence then self:pickImpacts() end
    elseif k == "A" then self:pickActivities()
    elseif k == "G" then self:pickGoals()
    elseif k == "P" then self:nextPrompt()
    elseif k == "W" then self:write()
    elseif k == "S" then self:save()
    else return false end
    return true
end

-- ------------------------------------------------------------ the page

function JournalScreen:button(id, text, width, callback, on, size)
    local b = Button:new{
        text = text, width = width, callback = callback, show_parent = self,
        bordersize = on and Size.border.thick or Size.border.thin, radius = Size.radius.button, margin = 0,
        padding = Size.padding.small, text_font_size = size or 16, text_font_bold = on and true or false,
    }
    b.gz_id, b.gz_on = id, on and true or false
    self.buttons[id] = b
    return b
end

--- Buttons in rows of `per` across `width` (also added to the 5-way's layout).
function JournalScreen:rows(list, per, width)
    local gap = S(6)
    local w = math.floor((width - gap * (per - 1)) / per)
    local group = VerticalGroup:new{ align = "left" }
    local row, line
    for i, spec in ipairs(list) do
        if (i - 1) % per == 0 then
            if row then group[#group + 1] = VerticalSpan:new{ width = gap } end
            row = HorizontalGroup:new{ align = "center" }
            line = {}
            group[#group + 1] = row
            self.layout[#self.layout + 1] = line
        end
        if #row > 0 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        local b = self:button(spec.id, spec.text, spec.wide and (w * spec.wide + gap * (spec.wide - 1)) or w, spec.callback, spec.on, spec.size)
        row[#row + 1] = b
        line[#line + 1] = b
    end
    return group
end

function JournalScreen:build()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local margin = S(14)
    local inner = sw - 2 * margin
    local st, set = self.state, self.settings
    self.layout, self.buttons = {}, {}
    local col = VerticalGroup:new{ align = "left" }
    local function gap(h) col[#col + 1] = VerticalSpan:new{ width = S(h or 8) } end
    local function label(text, gray)
        col[#col + 1] = TextWidget:new{ text = text, face = Font:getFace("cfont", gray and 14 or 16), bold = not gray,
            fgcolor = gray and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK, max_width = inner }
        gap(4)
    end
    -- title: ✕ Journal · the date … Save
    local date = Journal.heading(os.time()):gsub(", %d%d%d%d$", "")
    local close = self:button("close", "\u{2715}", S(44), function() self:onClose() end, false, 18)
    local save = self:button("save", _("Save"), S(84), function() self:save() end, true, 18)
    local title = TextWidget:new{ text = _("Journal") .. "  \u{00B7}  " .. date, face = Font:getFace("smalltfont", 20), bold = true,
        max_width = inner - S(44) - S(84) - S(20) }
    col[#col + 1] = HorizontalGroup:new{ align = "center", close, HorizontalSpan:new{ width = S(10) },
        LeftContainer:new{ dimen = Geom:new{ w = inner - S(44) - S(84) - S(20), h = S(44) }, title },
        HorizontalSpan:new{ width = S(10) }, save }
    self.layout[#self.layout + 1] = { close, save }
    gap(10)
    -- how you felt
    label(_("How have you felt?"))
    col[#col + 1] = self:rows({
        { id = "kind-today", text = Journal.KIND_LABELS.today, on = st.kind == "today", callback = function() st.kind = "today"; self:rebuild("kind-today") end },
        { id = "kind-now", text = Journal.KIND_LABELS.now, on = st.kind == "now", callback = function() st.kind = "now"; self:rebuild("kind-now") end },
    }, 2, inner)
    gap(6)
    local steps = {}
    for i, v in ipairs(Journal.VALENCES) do
        steps[i] = { id = "mood-" .. i, text = st.valence == v and "\u{25CF}" or "\u{25CB}", on = st.valence == v, size = 22,
            callback = function() self:setValence(v) end }
    end
    col[#col + 1] = self:rows(steps, 7, inner)
    gap(2)
    local scale = HorizontalGroup:new{ align = "center" }
    local third = math.floor(inner / 3)
    local function word(text, bold, align)
        local w = TextWidget:new{ text = text, face = Font:getFace("cfont", 13), bold = bold,
            fgcolor = bold and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, max_width = third }
        local C = align == "left" and LeftContainer or (align == "right" and require("ui/widget/container/rightcontainer") or CenterContainer)
        return C:new{ dimen = Geom:new{ w = third, h = S(20) }, w }
    end
    scale[1] = word(Journal.VALENCE_LABELS["very-unpleasant"], false, "left")
    scale[2] = word(st.valence and Journal.VALENCE_LABELS[st.valence] or _("Not chosen"), st.valence ~= nil, "center")
    scale[3] = word(Journal.VALENCE_LABELS["very-pleasant"], false, "right")
    col[#col + 1] = scale
    gap(8)
    if st.valence then
        label(_("What best describes this feeling?"))
        local chips = {}
        for _i, id in ipairs(self:feelingChips()) do
            chips[#chips + 1] = { id = "felt-" .. id, text = Journal.words(id), on = Journal.has(st.feelings, id), size = 14,
                callback = function() Journal.toggle(st.feelings, id); self:rebuild("felt-" .. id) end }
        end
        col[#col + 1] = self:rows(chips, 5, inner)
        gap(6)
        col[#col + 1] = self:rows({
            { id = "more", text = _("More feelings…"), size = 15, callback = function() self:pickFeelings() end },
            { id = "impact", size = 15, on = #st.impacts > 0,
              text = #st.impacts > 0 and T(_("Behind it: %1"), self:summary(st.impacts)) or _("What's behind it…"),
              callback = function() self:pickImpacts() end },
        }, 2, inner)
        gap(8)
    end
    -- what you did
    if #set.activities > 0 then
        label(_("What did you do?"))
        local acts = {}
        for i, a in ipairs(set.activities) do
            if i > 10 then break end
            acts[#acts + 1] = { id = "did-" .. a.id, text = a.label, on = Journal.has(st.activities, a.id), size = 14,
                callback = function() Journal.toggle(st.activities, a.id); self:rebuild("did-" .. a.id) end }
        end
        if #set.activities > 10 then
            acts[#acts] = { id = "did", text = _("More…"), size = 14, callback = function() self:pickActivities() end }
        end
        col[#col + 1] = self:rows(acts, 5, inner)
        gap(8)
    end
    if #set.goals > 0 then
        col[#col + 1] = self:rows({ { id = "goals", size = 15, on = self:goalsDone() > 0,
            text = T(_("Goals: %1 of %2 done"), self:goalsDone(), #set.goals), callback = function() self:pickGoals() end } }, 1, inner)
        gap(8)
    end
    -- the prompt and the words
    if set.showPrompt then
        col[#col + 1] = TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner, bold = true }
        gap(6)
    end
    local written = st.body:gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    if set.showPrompt then rows[#rows + 1] = { id = "prompt", text = _("Another prompt"), size = 15, callback = function() self:nextPrompt() end } end
    rows[#rows + 1] = { id = "write", text = written ~= "" and _("Edit what you wrote…") or _("Write about it…"), size = 15, on = written ~= "",
        callback = function() self:write() end }
    col[#col + 1] = self:rows(rows, #rows, inner)
    if written ~= "" then
        gap(6)
        local first = written:gsub("%s+", " ")
        col[#col + 1] = TextBoxWidget:new{ text = first, face = Font:getFace("cfont", 15), width = inner,
            height_adjust = true, height = S(44), height_overflow_show_ellipsis = true, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    end
    if Touch.keys() then
        gap(8)
        col[#col + 1] = TextBoxWidget:new{ width = inner, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            text = _("Alt+Q\u{2013}U (1\u{2013}7) how you felt  \u{00B7}  T today / right now  \u{00B7}  F feelings  \u{00B7}  I what's behind it  \u{00B7}  A what you did  \u{00B7}  G goals  \u{00B7}  P another prompt  \u{00B7}  W write  \u{00B7}  S save") }
    elseif not Touch.on() then
        gap(8)
        label(_("The 5-way moves, Press picks. Back closes."), true)
    end
    self.column = col
    self[1] = FrameContainer:new{ width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", VerticalSpan:new{ width = S(10) },
            HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, col } } }
end

--- Build the page again after a choice; the 5-way stays on the button `focus_id`.
function JournalScreen:rebuild(focus_id)
    if self[1] and self[1].free then pcall(self[1].free, self[1]) end
    self:build()
    self.selected = { x = 1, y = 1 }
    local b = focus_id and self.buttons[focus_id]
    if b then
        local x, y = self:getFocusableWidgetXY(b)
        if x then self.selected = { x = x, y = y } end
    end
    if not Touch.on() then self:moveFocusTo(self.selected.x, self.selected.y, FocusManager.FORCED_FOCUS) end
    UIManager:setDirty(self, "ui")
end

function JournalScreen:onShow()
    if not Touch.on() then
        local x, y = self:getFocusableWidgetXY(self.buttons["mood-4"])
        if x then self:moveFocusTo(x, y, FocusManager.FORCED_FOCUS) end
    end
    UIManager:setDirty(self, "full")
    return true
end

--- The screen turned (auto-rotate, gzreader_rotation.lua): the entry laid out again at the new size, as filled in.
require("gzreader_rotation").follow(JournalScreen, function(w)
    w.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    w:rebuild()
end)

--- opts: settings (Journal.settings(…)), on_save(content), plugin (the quick panel)
function JournalScreen.show(opts)
    local w = JournalScreen:new{ settings = opts.settings, on_save = opts.on_save, prompt_i = opts.prompt_i, plugin = opts.plugin }
    UIManager:show(w, "full")
    return w
end

return JournalScreen
