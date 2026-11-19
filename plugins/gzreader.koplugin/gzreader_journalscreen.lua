--[[--
A journal entry (the Notes tab's Journal button; J): the Memos fork's
journaling mode on a Kindle (words and writing: gzreader_journal.lua).

  How have you felt?   [Overall today] [Right now]
  ○ ○ ○ ○ ● ○ ○        seven steps, very unpleasant to very pleasant
  What best describes this feeling?   the ten words nearest the step, More…
  What's behind it…                   causes (work, family, health…)
  What did you do?                    your activities
  Goals                               your goals, ticked when done
  A prompt, Another prompt
  ┌───────────────────────────── [✎] ┐   touch Kindles: the entry's words,
  │ typed here, plain text, on lined │   typed right under the prompt; ✎ in
  │ paper ─────────────────────────  │   the corner opens the drawing screen
  └──────────────────────────────────┘   under the prompt
  Save

Touch Kindles: a tap in the box brings the keyboard and makes room for it
(only the prompt and the words above it, Done puts it away). ✎ opens the
drawing screen under the prompt (gzreader_drawscreen.lua in a pane: every
tool, pinch and move, pages and paper, as a note's drawing); its ← goes back
to the entry, Aa to typing, Save saves the entry. The drawings go with the entry as the note's drawings. Kindles with keys: W writes in a
box of its own, as before.

The entry is saved as an ordinary note (its mood and activities as tags), so
it reads the same in Memos and in the fork's Insights.

Every control is a button: a tap on touch Kindles; the 5-way moves and Press
picks on Kindles with keys; a keyboard Kindle has a key for each too
(1–7 the step, T today / right now, F feelings, I what's behind it,
A activities, G goals, P another prompt, W write, S save).
]]

local GestureRange = require("ui/gesturerange")
local Log = require("gzreader_log")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")

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
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Journal = require("gzreader_journal")
local MoodFace = require("gzreader_moodface")
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
JournalScreen.PAPER = "ruled-medium" -- a journal entry's drawing: lined paper
JournalScreen.MIN_BOX = 140 -- the words' box at least this high (scaled), however much is above it

function JournalScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.settings = self.settings or Journal.settings()
    self.state = self.state or {
        kind = "today", feelings = {}, impacts = {}, activities = {}, goals = {}, body = "",
        prompt_i = (self.prompt_i or (os.time() % #Journal.PROMPTS)) % #Journal.PROMPTS + 1,
    }
    self.state.prompt = Journal.PROMPTS[self.state.prompt_i]
    -- touch Kindles: the words typed right under the prompt, formatted, on lined paper
    self.inline = Touch.on() and not Touch.keys()
    if self.inline then
        self.is_always_active = true -- (taps reach the page under the on-screen keyboard, and around an inline drawing)
    end
    self.pages = self.pages or nil -- the drawings, once drawn: { path, filename, changed } (DrawScreen's)
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
        title = (self.settings.showPrompt and self.state.prompt) or _("Journal"),
        input = self.state.body, input_hint = _("Write here…"),
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

--- The drawings to send with the entry: { path, filename } each.
function JournalScreen:drawings()
    local out = {}
    for _i, p in ipairs(self.pages or {}) do
        if p.path and not p.removed then out[#out + 1] = { path = p.path, filename = p.filename } end
    end
    return out
end

function JournalScreen:save()
    self:finishDrawing(true) -- (an inline drawing: kept first)
    self:keepWords()
    local drawings = self:drawings()
    if Journal.isEmpty(self.state) and #drawings == 0 then
        return UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3,
            text = _("Nothing to save yet. Choose how you felt, or write something.") })
    end
    local content = self:content()
    self.saved = true
    require("gzreader_drawdraft").clear(self.draft_id, "the journal entry saved")
    UIManager:close(self, "full")
    if self.on_save then self.on_save(content, #drawings > 0 and drawings or nil) end
end

-- ------------------------------------------------------------ writing, drawing (touch)

function JournalScreen:isShown()
    for _i, w in ipairs(UIManager._window_stack or {}) do if w.widget == self then return true end end
    return false
end

--- Done while drawing: the drawing kept, the whole entry again.
function JournalScreen:stopDrawing()
    self:finishDrawing(true)
    self:rebuild("draw")
end

--- The words typed so far, into the entry.
function JournalScreen:keepWords()
    if self.input then self.state.body = self.input:getText() or "" end
end

--- The keyboard came up for the words: room for it (the questions above fold away).
function JournalScreen:startWriting()
    if self.writing then return end
    self:keepWords()
    self.writing = true
    Log.info("journal: writing")
    self:rebuild("done-writing")
end

--- Done: the keyboard away, the whole entry again.
function JournalScreen:stopWriting(quiet)
    self:keepWords()
    if self.input and self.input.onCloseKeyboard then self.input:onCloseKeyboard() end
    if not self.writing then return end
    self.writing = false
    if not quiet then self:rebuild("write") end
end

--- ✎ in the box's corner: the entry's drawing, on lined paper, in the whole
--- drawing screen (every tool, pinch and move) under the prompt; its Save
--- saves the entry (its pages, once drawn).
function JournalScreen:startDrawing()
    if self.drawing then return end
    self:stopWriting(true)
    self.drawing = true
    Log.info("journal: drawing,", self.pages and #self.pages or 0, "page(s) so far")
    self:rebuild("draw")
end

--- The drawing screen in `rect` (screen pixels: under the prompt), as the
--- note's drawing screen is, but for this entry: ← goes back to the entry, Aa
--- to typing, Save saves the entry. (It was a small box with a few tools;
--- the owner, 2026-11-17: the same tools, pinch and pan as the regular one.)
function JournalScreen:openDrawing(rect)
    if self.drawing_open then return self.drawing_open end
    local pages = self.pages
    if not pages or #pages == 0 then
        local Drawing = require("gzreader_drawing")
        local scene = Drawing.newScene()
        local el, file_id, file = require("gzreader_notepaper").element(JournalScreen.PAPER)
        if el then
            scene.files[file_id] = file
            table.insert(scene.elements, 1, el)
        end
        pages = { { scene = scene } }
    end
    self.drawing_rect = rect
    self.drawing_open = require("gzreader_drawscreen").show{
        plugin = self.plugin,
        pages = pages,
        title = _("Journal"),
        pane = { x = rect.x, y = rect.y, w = rect.w, h = rect.h },
        journal = { under = self },
        on_done = function(res)
            local after = res.after
            res.reordered, res.title, res.tags, res.after = nil, nil, nil, nil
            local kept = {}
            for _i, p in ipairs(res) do if not p.removed then kept[#kept + 1] = p end end
            if #kept > 0 then self.pages = kept end
            self.drawing_open = nil
            if self.drawing then
                self.drawing = false
                if self.finishing then return end
                if after == "save" then
                    -- (the drawing's Save: the entry saved, drawing and all)
                    Log.info("journal: saved from the drawing screen")
                    self:save()
                    return
                end
                self:rebuild("draw")
                if after == "typing" then
                    -- (Aa: the keyboard up for the words)
                    UIManager:nextTick(function()
                        if self.input and self:isShown() then self.input:onShowKeyboard() end
                    end)
                end
            end
        end,
        on_cancel = function()
            self.drawing_open = nil
            self.drawing = false
            if not self.finishing then self:rebuild("draw") end
        end,
    }
    return self.drawing_open
end

--- An inline drawing still open: kept (its Done), before the entry is saved or left.
function JournalScreen:finishDrawing(quiet)
    local d = self.drawing_open
    if not d then return end
    self.finishing = quiet
    d:done()
    self.finishing = nil
    if self.drawing_open == d then
        -- (it couldn't be saved: closed anyway)
        self.drawing_open = nil
        d:close()
    end
    self.drawing = false
end

function JournalScreen:sheetCount()
    local n = 0
    for _i, p in ipairs(self.pages or {}) do if not p.removed then n = n + 1 end end
    return n
end

--- Lined paper under the words: a light rule under each line of `input`
--- (painted after it, at the bottom of each line, where no letters are).
function JournalScreen.paintRules(input, bb, x, y)
    local tw = input.text_widget
    local tb = tw and (tw.text_widget or tw)
    local pitch = tb and tb.line_height_px
    if not pitch or pitch < 4 or not tb.dimen or not tb.dimen.y then return 0 end
    local top, bottom = tb.dimen.y, y + (input.height or tb.height or 0)
    local w = input.width or tb.width
    local n = 0
    local ry = top + pitch - 1
    while ry < bottom do
        bb:paintRect(tb.dimen.x or x, ry, w, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        n = n + 1
        ry = ry + pitch
    end
    return n
end

JournalScreen.PREVIEW_H = 150 -- (scaled) how tall a page's picture is under the tags

--- The entry's drawing as small pictures, one a page (at most as many as fit
--- across `width`), a tap on one opens the drawing again. nil when no page has
--- a picture yet.
function JournalScreen:drawingStrip(width)
    local Sticky = require("gzreader_sticky")
    local ImageWidget = require("ui/widget/imagewidget")
    local screen = self
    local th = S(JournalScreen.PREVIEW_H)
    local row = HorizontalGroup:new{ align = "center" }
    local used, shown = 0, 0
    self.preview = { pages = 0 }
    for _i, p in ipairs(self.pages or {}) do
        if not p.removed and p.path then
            local bb = Sticky.picture(p.path, width, th - 2)
            if bb then
                local w = bb:getWidth() + 2
                if shown > 0 and used + S(8) + w > width then break end
                local cell = FrameContainer:new{ padding = 0, margin = 0, bordersize = Size.border.thin,
                    background = Blitbuffer.COLOR_WHITE, ImageWidget:new{ image = bb, image_disposable = true } }
                local tap = InputContainer:new{ dimen = Geom:new{ w = cell:getSize().w, h = cell:getSize().h }, cell }
                tap.ges_events = { TapPreview = { GestureRange:new{ ges = "tap", range = function() return tap.dimen end } } }
                function tap:onTapPreview() screen:startDrawing(); return true end
                if shown > 0 then row[#row + 1] = HorizontalSpan:new{ width = S(8) } end
                row[#row + 1] = tap
                self.preview.first = self.preview.first or tap
                used = used + (shown > 0 and S(8) or 0) + w
                shown = shown + 1
            end
        end
    end
    if shown == 0 then return nil end
    self.preview.pages = shown
    return row
end

--- The words' box: plain text (KOReader's InputText), lined, `h` high, with
--- ✎ in its top right corner (and how many sheets, once drawn).
function JournalScreen:writingBox(width, h)
    local screen = self
    if self.input then
        if self.input.onCloseKeyboard then pcall(self.input.onCloseKeyboard, self.input) end
        self.input = nil
    end
    local input = require("ui/widget/inputtext"):new{
        text = self.state.body or "", width = width, height = h, scroll = true, parent = self,
        face = Font:getFace("cfont", 18), bordersize = 0, padding = 0, margin = 0,
        hint = _("Start writing…"), focused = false,
        gz_multiline = true, gz_hash_key = true, -- (the keyboard's Enter, ← →, and # bar)
        edit_callback = function(edited) if edited and screen.input then screen.state.body = screen.input:getText() or "" end end,
    }
    -- (✎ lies over the box's top right corner: a tap there is for it, not the text)
    local tap_text = input.onTapTextBox
    input.onTapTextBox = function(i, arg, ges)
        local d = screen.draw_chip and screen.draw_chip.dimen
        if d and d.x and ges and ges.pos and ges.pos.x >= d.x and ges.pos.x < d.x + d.w and ges.pos.y >= d.y and ges.pos.y < d.y + d.h then
            screen:startDrawing()
            return true
        end
        return tap_text(i, arg, ges)
    end
    local show_kb = input.onShowKeyboard
    input.onShowKeyboard = function(i, ...)
        local r = show_kb(i, ...)
        screen:startWriting()
        return r
    end
    local paint = input.paintTo
    input.paintTo = function(i, bb, x, y)
        paint(i, bb, x, y)
        JournalScreen.paintRules(i, bb, x, y)
    end
    self.input = input
    if self.writing then
        -- (laid out again for the keyboard: the new box takes it)
        UIManager:nextTick(function() if screen.input == input and screen.writing then input:onShowKeyboard() end end)
    end
    local n = self:sheetCount()
    local icon = require("ui/widget/iconwidget"):new{ file = require("gzreader_drawscreen").ICON_DIR .. "pen.svg",
        width = S(26), height = S(26), alpha = true }
    local inside = HorizontalGroup:new{ align = "center", icon }
    if n > 0 then
        inside[#inside + 1] = HorizontalSpan:new{ width = S(4) }
        inside[#inside + 1] = TextWidget:new{ text = tostring(n), face = Font:getFace("cfont", 15), bold = true }
    end
    local chip = FrameContainer:new{ padding = S(6), radius = S(6), margin = 0, bordersize = Size.border.thick,
        background = Blitbuffer.COLOR_WHITE, inside }
    local tap = InputContainer:new{ dimen = Geom:new{ w = chip:getSize().w, h = chip:getSize().h }, chip }
    tap.ges_events = { TapDraw = { GestureRange:new{ ges = "tap", range = function() return tap.dimen end } } }
    function tap:onTapDraw() screen:startDrawing(); return true end
    self.draw_chip = tap
    return FrameContainer:new{ padding = S(4), margin = 0, bordersize = Size.border.thin, radius = S(4),
        OverlapGroup:new{ dimen = Geom:new{ w = width, h = h }, input,
            RightContainer:new{ dimen = Geom:new{ w = width, h = chip:getSize().h }, tap } } }
end


function JournalScreen:onClose()
    if self.writing then self:stopWriting(); return true end
    if self.drawing then self:stopDrawing(); return true end
    self:keepWords()
    if Journal.isEmpty(self.state) and #self:drawings() == 0 then UIManager:close(self, "full"); return true end
    local dialog
    dialog = ButtonDialog:new{ title = _("Save this journal entry?"), buttons = {
        { { text = _("Save"), align = "left", callback = function() UIManager:close(dialog); self:save() end } },
        { { text = _("Discard"), align = "left", callback = function()
            UIManager:close(dialog)
            require("gzreader_drawdraft").clear(self.draft_id, "the journal entry discarded")
            UIManager:close(self, "full")
        end } },
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
    self:stopWriting() -- (the keyboard would stay over the panel)
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
    elseif k == "W" then if self.inline and self.input then self.input:onShowKeyboard() else self:write() end
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

-- ------------------------------------------------------------ the web's look (touch)
-- (as the owner's Memos fork's journal: a face beside a slider of the seven
-- steps, chips that fill black when chosen, activities with their icons)

JournalScreen.CHIP_GREY = 0xE6 -- a chip not chosen: the web's "well" (light grey, no border)
JournalScreen.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/journal/"

--- A chip as the web draws its small buttons: chosen, black with white
--- words; else light grey (`ghost`: no fill, for the kind toggles). With
--- `icon` (an activity's), its picture before the words.
function JournalScreen:chip(spec, max_w)
    local size = spec.size or 15
    local text = spec.text
    local icon_w
    if spec.icon then
        -- (room for the picture: spaces before the words, the icon painted over them)
        local face = Font:getFace("cfont", size)
        local sp = require("ui/rendertext"):sizeUtf8Text(0, 1e6, face, " ").x
        icon_w = S(math.floor(size * 1.25))
        text = string.rep(" ", math.ceil((icon_w + S(4)) / math.max(1, sp))) .. text
    end
    local b = Button:new{
        text = text, max_width = max_w, callback = spec.callback, show_parent = self,
        background = spec.on and Blitbuffer.COLOR_BLACK or (not spec.ghost and Blitbuffer.Color8(JournalScreen.CHIP_GREY) or nil),
        bordersize = spec.ghost and not spec.on and 0 or Size.border.thin,
        radius = Size.radius.button, margin = 0, padding_h = S(10), padding_v = S(4),
        text_font_size = size, text_font_bold = spec.on and true or false,
    }
    if spec.ghost and not spec.on then b.frame.background = nil; b.frame.bordersize = 0 end
    if spec.on and b.label_widget then b.label_widget.fgcolor = Blitbuffer.COLOR_WHITE end
    if spec.icon then
        local path = self:iconPath(spec.icon)
        local paint = b.paintTo
        local screen = self
        b.paintTo = function(btn, bb, x, y)
            paint(btn, bb, x, y)
            local ib = path and screen:icon(path, icon_w, spec.on)
            if ib then
                local h = btn:getSize().h
                local ix = x + S(10) + Size.border.thin
                local iy = y + math.floor((h - icon_w) / 2)
                if spec.on then bb:blitFrom(ib, ix, iy, 0, 0, icon_w, icon_w) else bb:alphablitFrom(ib, ix, iy, 0, 0, icon_w, icon_w) end
            end
        end
    end
    b.gz_id, b.gz_on = spec.id, spec.on and true or false
    self.buttons[spec.id] = b
    return b
end

--- An activity icon's file (icons/journal/<name>.svg; star when it isn't one).
function JournalScreen:iconPath(name)
    local dir = JournalScreen.ICON_DIR
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir .. tostring(name) .. ".svg", "mode") == "file" then return dir .. name .. ".svg" end
    if lfs.attributes(dir .. "star.svg", "mode") == "file" then return dir .. "star.svg" end
end

--- An icon `w` square: black lines on clear (chosen: white lines on black). Kept.
function JournalScreen:icon(path, w, white)
    self.icons = self.icons or {}
    local key = path .. w .. (white and "w" or "b")
    if self.icons[key] == nil then
        local ok, ib = pcall(require("ui/renderimage").renderSVGImageFile, require("ui/renderimage"), path, w, w)
        if ok and ib and white then
            -- (white on black: drawn on white, then inverted)
            local tmp = Blitbuffer.new(w, w, Blitbuffer.TYPE_BB8)
            tmp:fill(Blitbuffer.COLOR_WHITE)
            tmp:alphablitFrom(ib, 0, 0, 0, 0, w, w)
            tmp:invertRect(0, 0, w, w)
            ib:free()
            ib = tmp
        end
        self.icons[key] = ok and ib or false
    end
    return self.icons[key] or nil
end

--- Chips across `width`, as many on a line as fit (as the web wraps them;
--- each line one row of the 5-way's layout).
function JournalScreen:flow(list, width)
    local gap = S(6)
    local group = VerticalGroup:new{ align = "left" }
    local row, line, used
    for _i, spec in ipairs(list) do
        local c = self:chip(spec, width)
        local w = c:getSize().w
        if not row or used + gap + w > width then
            if row then group[#group + 1] = VerticalSpan:new{ width = gap } end
            row, line, used = HorizontalGroup:new{ align = "center" }, {}, 0
            group[#group + 1] = row
            self.layout[#self.layout + 1] = line
        else
            row[#row + 1] = HorizontalSpan:new{ width = gap }
            used = used + gap
        end
        row[#row + 1] = c
        line[#line + 1] = c
        used = used + w
    end
    return group
end

--- The slider of the seven steps (the web's range input on its coloured
--- track, here in the faces' greys): a tap or a drag along it picks a step.
--- Each step is also `buttons["mood-<i>"]` (where a tap picks it).
function JournalScreen:moodSlider(width)
    local screen = self
    local h = S(40)
    local Slider = InputContainer:extend{}
    local slider = Slider:new{ dimen = Geom:new{ w = width, h = h } }
    self.mood_slider = slider
    local n = #Journal.VALENCES
    local pad = S(12) -- (the thumb's room at the ends)
    local function stepX(i) return pad + math.floor((width - 2 * pad) * (i - 1) / (n - 1)) end
    for i = 1, n do
        screen.buttons["mood-" .. i] = { gz_id = "mood-" .. i, gz_on = screen.state.valence == Journal.VALENCES[i],
            dimen = Geom:new{ x = 0, y = 0, w = S(24), h = h } }
    end
    local function pick(x)
        local best, bd = 1, math.huge
        for i = 1, n do
            local d = math.abs(slider.dimen.x + stepX(i) - x)
            if d < bd then best, bd = i, d end
        end
        return best
    end
    slider.ges_events = {
        TapStep = { GestureRange:new{ ges = "tap", range = function() return slider.dimen end } },
        PanStep = { GestureRange:new{ ges = "pan", range = function() return slider.dimen end } },
        PanReleaseStep = { GestureRange:new{ ges = "pan_release", range = function() return slider.dimen end } },
    }
    function slider:onTapStep(_a, ges)
        local v = Journal.VALENCES[pick(ges.pos.x)]
        if screen.state.valence == v then screen:rebuild("mood-" .. pick(ges.pos.x)) -- (the web: a tap on the chosen step keeps it)
        else screen:setValence(v) end
        return true
    end
    function slider:onPanStep(_a, ges)
        -- (the dot moved to the finger's step, shown once a step is reached: in grey, as
        -- "fast" (black and white only) lost the dot and the track's greys on a Kindle)
        local i = pick(ges.pos.x)
        if i == self.dragging then return true end
        self.dragging = i
        UIManager:setDirty(screen, function() return "ui", self.dimen end)
        return true
    end
    function slider:onPanReleaseStep(_a, ges)
        local i = ges and ges.pos and pick(ges.pos.x) or self.dragging
        self.dragging = nil
        if i then
            local v = Journal.VALENCES[i]
            if screen.state.valence ~= v then screen:setValence(v) else screen:rebuild("mood-" .. i) end
        end
        return true
    end
    function slider:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local th = S(10)
        local ty = y + math.floor((h - th) / 2)
        -- the track: each step's stretch in its face's grey
        local x1 = x + pad
        local seg = (width - 2 * pad) / (n - 1)
        for i = 1, n do
            local a = math.floor(x1 + seg * (i - 1.5))
            local b2 = math.floor(x1 + seg * (i - 0.5))
            a, b2 = math.max(x + pad - math.floor(th / 2), a), math.min(x + width - pad + math.floor(th / 2), b2)
            local c = Blitbuffer.Color8(MoodFace.greys(Journal.VALENCES[i]).fill)
            if i == 1 or i == n then
                bb:paintRoundedRect(a, ty, b2 - a, th, c, math.floor(th / 2))
                bb:paintRect(i == 1 and (a + math.floor(th / 2)) or a, ty, b2 - a - math.floor(th / 2), th, c)
            else
                bb:paintRect(a, ty, b2 - a, th, c)
            end
        end
        -- the steps' places (where a tap picks each)
        for i = 1, n do
            local sb = screen.buttons["mood-" .. i]
            sb.dimen = Geom:new{ x = x + stepX(i) - math.floor(seg / 2), y = y, w = math.max(1, math.floor(seg)), h = h }
        end
        -- the thumb: white with a dark ring before a step is chosen, else the step's grey ringed in white
        local cur = self.dragging
        if not cur then for i, v in ipairs(Journal.VALENCES) do if v == screen.state.valence then cur = i end end end
        local r = S(11)
        local cx, cy = x + stepX(cur or 4), y + math.floor(h / 2)
        self.thumb_at = cur
        if cur then
            bb:paintCircle(cx, cy, r + S(1), Blitbuffer.COLOR_DARK_GRAY, S(1))
            bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_WHITE, S(3))
            bb:paintCircle(cx, cy, r - S(3), Blitbuffer.Color8(MoodFace.greys(Journal.VALENCES[cur]).fill))
        else
            bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_WHITE)
            bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_DARK_GRAY, S(2))
        end
    end
    return slider
end

--- How you felt, as the web asks it: the question and Overall today /
--- Right now; a big face beside the step's name (Clear), the slider and its ends.
function JournalScreen:webMood(col, inner)
    local st = self.state
    local function add(w) col[#col + 1] = w end
    local question = st.kind == "now" and _("How do you feel right now?") or _("How have you felt today?")
    local kinds = self:flow({
        { id = "kind-today", text = Journal.KIND_LABELS.today, on = st.kind == "today", ghost = true, size = 14,
          callback = function() st.kind = "today"; self:rebuild("kind-today") end },
        { id = "kind-now", text = Journal.KIND_LABELS.now, on = st.kind == "now", ghost = true, size = 14,
          callback = function() st.kind = "now"; self:rebuild("kind-now") end },
    }, inner)
    local kw = kinds:getSize().w
    add(HorizontalGroup:new{ align = "center",
        LeftContainer:new{ dimen = Geom:new{ w = inner - kw, h = kinds:getSize().h },
            TextWidget:new{ text = question, face = Font:getFace("cfont", 16), bold = true, max_width = inner - kw - S(8) } },
        kinds })
    col[#col + 1] = VerticalSpan:new{ width = S(8) }
    local face_w = S(56)
    local right = inner - face_w - S(12)
    local name = TextWidget:new{ text = st.valence and Journal.VALENCE_LABELS[st.valence] or _("Not chosen"),
        face = Font:getFace("cfont", 16), bold = st.valence ~= nil,
        fgcolor = st.valence and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, max_width = right - S(90) }
    local top
    if st.valence then
        local clear = self:chip({ id = "mood-clear", text = _("Clear"), ghost = true, size = 14,
            callback = function() self:setValence(st.valence) end }, S(90))
        self.layout[#self.layout + 1] = { clear }
        top = HorizontalGroup:new{ align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = right - clear:getSize().w, h = clear:getSize().h }, name }, clear }
    else
        top = LeftContainer:new{ dimen = Geom:new{ w = right, h = S(30) }, name }
    end
    local ends = HorizontalGroup:new{ align = "center",
        LeftContainer:new{ dimen = Geom:new{ w = math.floor(right / 2), h = S(18) },
            TextWidget:new{ text = Journal.VALENCE_LABELS["very-unpleasant"], face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.COLOR_DARK_GRAY } },
        RightContainer:new{ dimen = Geom:new{ w = right - math.floor(right / 2), h = S(18) },
            TextWidget:new{ text = Journal.VALENCE_LABELS["very-pleasant"], face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.COLOR_DARK_GRAY } },
    }
    add(HorizontalGroup:new{ align = "center",
        MoodFace.widget{ valence = st.valence or "neutral", size = face_w, faded = st.valence == nil },
        HorizontalSpan:new{ width = S(12) },
        VerticalGroup:new{ align = "left", top, self:moodSlider(right), ends } })
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
    -- (writing: Done in place of ✕, the keyboard away and the whole entry back)
    if self.inline and self.drawing then return self:buildDrawing(sw, sh, margin, inner) end
    local busy = self.writing
    local close_w = busy and S(84) or S(44)
    local close = busy and self:button("done-writing", _("Done"), close_w, function()
            self:stopWriting()
        end, false, 17)
        or self:button("close", "\u{2715}", close_w, function() self:onClose() end, false, 18)
    local save = self:button("save", _("Save"), S(84), function() self:save() end, true, 18)
    local title = TextWidget:new{ text = _("Journal") .. "  \u{00B7}  " .. date, face = Font:getFace("smalltfont", 20), bold = true,
        max_width = inner - close_w - S(84) - S(20) }
    col[#col + 1] = HorizontalGroup:new{ align = "center", close, HorizontalSpan:new{ width = S(10) },
        LeftContainer:new{ dimen = Geom:new{ w = inner - close_w - S(84) - S(20), h = S(44) }, title },
        HorizontalSpan:new{ width = S(10) }, save }
    self.layout[#self.layout + 1] = { close, save }
    gap(10)
    if self.inline and self.writing then
        -- writing: the prompt, and the words over the keyboard
        if set.showPrompt then
            col[#col + 1] = TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner, bold = true }
            gap(6)
        end
        local kb = self.input and self.input.keyboard
        local kb_h = kb and kb.dimen and kb.dimen.h or math.floor(sh * 0.4)
        local used = col:getSize().h + S(10)
        col[#col + 1] = self:writingBox(inner - 2 * S(4), sh - used - kb_h - S(18))
        return self:finish(col, sw, sh, margin)
    end
    if self.inline then return self:buildWeb(col, inner, sw, sh, margin, gap, label) end
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
    if set.showPrompt and self.inline then
        -- (touch: the prompt, Another at its right, and the words right under it)
        local another_w = S(120)
        local another = self:button("prompt", "\u{21BB} " .. _("Another"), another_w, function() self:nextPrompt() end, false, 15)
        col[#col + 1] = HorizontalGroup:new{ align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = inner - another_w - S(10), h = math.max(S(40), another:getSize().h) },
                TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner - another_w - S(10), bold = true } },
            HorizontalSpan:new{ width = S(10) }, another }
        self.layout[#self.layout + 1] = { another }
    elseif set.showPrompt then
        col[#col + 1] = TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner, bold = true }
        gap(6)
    end
    local written = st.body:gsub("^%s+", ""):gsub("%s+$", "")
    local rows = {}
    if set.showPrompt and not self.inline then rows[#rows + 1] = { id = "prompt", text = _("Another prompt"), size = 15, callback = function() self:nextPrompt() end } end
    if not self.inline then
        rows[#rows + 1] = { id = "write", text = written ~= "" and _("Edit what you wrote…") or _("Write…"), size = 15, on = written ~= "",
            callback = function() self:write() end }
    end
    if #rows > 0 then col[#col + 1] = self:rows(rows, #rows, inner) end
    if self.inline then
        -- the words, right under the prompt: the rest of the page, lined
        gap(6)
        local used = col:getSize().h + S(10)
        col[#col + 1] = self:writingBox(inner - 2 * S(4), math.max(S(JournalScreen.MIN_BOX), sh - used - S(24)))
        return self:finish(col, sw, sh, margin)
    end
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
    return self:finish(col, sw, sh, margin)
end

--- Drawing: the prompt at the top, and under it the drawing screen (its own
--- top bar, tools and pages), opened once this is shown.
function JournalScreen:buildDrawing(sw, sh, margin, inner)
    local col = VerticalGroup:new{ align = "left" }
    self.layout, self.buttons = {}, {}
    local st, set = self.state, self.settings
    if set.showPrompt and st.prompt and st.prompt ~= "" then
        col[#col + 1] = TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner, bold = true }
    end
    local used = col:getSize().h > 0 and (S(10) + col:getSize().h + S(10)) or 0
    local rect = Geom:new{ x = 0, y = used, w = sw, h = sh - used }
    self.drawing_box = rect
    local screen = self
    UIManager:nextTick(function()
        if screen.drawing and not screen.drawing_open and screen:isShown() then screen:openDrawing(rect) end
    end)
    return self:finish(col, sw, sh, margin)
end

--- The page on touch Kindles, as the web shows it (webMood, chips, icons),
--- then the prompt and the words under it.
function JournalScreen:buildWeb(col, inner, sw, sh, margin, gap, label)
    local st, set = self.state, self.settings
    self:webMood(col, inner)
    gap(10)
    if st.valence then
        label(_("What best describes this feeling?"))
        local chips = {}
        for _i, id in ipairs(self:feelingChips()) do
            chips[#chips + 1] = { id = "felt-" .. id, text = Journal.words(id), on = Journal.has(st.feelings, id), size = 14,
                callback = function() Journal.toggle(st.feelings, id); self:rebuild("felt-" .. id) end }
        end
        chips[#chips + 1] = { id = "more", text = _("More feelings…"), ghost = true, size = 14, callback = function() self:pickFeelings() end }
        col[#col + 1] = self:flow(chips, inner)
        gap(8)
        label(_("What's behind it?"))
        local causes = {}
        for _i, id in ipairs(Journal.impacts(set)) do
            causes[#causes + 1] = { id = "impact-" .. id, text = Journal.words(id), on = Journal.has(st.impacts, id), size = 14,
                callback = function() Journal.toggle(st.impacts, id); self:rebuild("impact-" .. id) end }
        end
        if #causes > 8 then
            -- (more than fit nicely: the chosen and the first few, then the list)
            local short = {}
            for i, c in ipairs(causes) do if i <= 7 or c.on then short[#short + 1] = c end end
            short[#short + 1] = { id = "impact", text = _("More…"), ghost = true, size = 14, callback = function() self:pickImpacts() end }
            causes = short
        end
        col[#col + 1] = self:flow(causes, inner)
        gap(10)
    end
    if #set.activities > 0 then
        label(_("What did you do?"))
        local acts = {}
        for _i, a in ipairs(set.activities) do
            acts[#acts + 1] = { id = "did-" .. a.id, text = a.label, icon = a.icon or "star", on = Journal.has(st.activities, a.id), size = 15,
                callback = function() Journal.toggle(st.activities, a.id); self:rebuild("did-" .. a.id) end }
        end
        col[#col + 1] = self:flow(acts, inner)
        gap(10)
    end
    if #set.goals > 0 then
        col[#col + 1] = self:flow({ { id = "goals", size = 14, on = self:goalsDone() > 0,
            text = T(_("Goals: %1 of %2 done"), self:goalsDone(), #set.goals), callback = function() self:pickGoals() end } }, inner)
        gap(10)
    end
    -- the drawing, once drawn (← back from it keeps it): a picture of each page, under the
    -- tags as the words are under the prompt; a tap opens it again
    if self:sheetCount() > 0 then
        local strip = self:drawingStrip(inner)
        if strip then
            col[#col + 1] = strip
            gap(8)
        end
    end
    -- the prompt (Another at its right) and the words right under it, lined
    if set.showPrompt then
        local another = self:chip({ id = "prompt", text = "\u{21BB} " .. _("Another"), ghost = true, size = 14,
            callback = function() self:nextPrompt() end }, S(140))
        local aw = another:getSize().w
        col[#col + 1] = HorizontalGroup:new{ align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = inner - aw - S(10), h = math.max(S(36), another:getSize().h) },
                TextBoxWidget:new{ text = st.prompt, face = Font:getFace("cfont", 17), width = inner - aw - S(10), bold = true } },
            HorizontalSpan:new{ width = S(10) }, another }
        self.layout[#self.layout + 1] = { another }
    end
    gap(6)
    local used = col:getSize().h + S(10)
    col[#col + 1] = self:writingBox(inner - 2 * S(4), math.max(S(JournalScreen.MIN_BOX), sh - used - S(24)))
    return self:finish(col, sw, sh, margin)
end

function JournalScreen:finish(col, sw, sh, margin)
    -- (measured before the words' box went in: measured again)
    if col.resetLayout then col:resetLayout() end
    self.column = col
    self[1] = FrameContainer:new{ width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", VerticalSpan:new{ width = S(10) },
            HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, col } } }
end

--- Takes `w` out of the widget tree `node` (so freeing the tree leaves it alone).
function JournalScreen:unparent(node, w)
    if type(node) ~= "table" then return false end
    for i = #node, 1, -1 do
        if node[i] == w then table.remove(node, i); return true end
        if type(node[i]) == "table" and self:unparent(node[i], w) then return true end
    end
    return false
end

--- Build the page again after a choice; the 5-way stays on the button `focus_id`.
function JournalScreen:rebuild(focus_id)
    -- (the words' page is kept: taken out before the old layout is freed)
    if self.input then self:unparent(self[1], self.input) end
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
