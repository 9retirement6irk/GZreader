--[[--
The Notes tab's editor (new notes and edits): a full page, or for the quick
panel's Quick note a window over whatever is on the screen (`showFloating`;
a tap outside it closes it, as Back does). Memos notes are Markdown; a
toolbar adds it for you:

  • List   ☐ Check   1. Num   H Head   I   B   # Tag   |  Save

- Menu jumps to the toolbar from anywhere in the text, the cursor staying
  where it is (on the tool used last); Menu again (or ▲) goes back to the
  text. ▼ from the last line also reaches it. ◀ ▶ choose; Press applies to
  the line the cursor is on (lists, checklists, headings) or adds the markers
  at the cursor (italic, bold).
- Shortcuts from anywhere: Alt+L list, Alt+C checklist, Alt+N numbered,
  Alt+H heading, Alt+K italic, Alt+B bold, Alt+G tag, Alt+S save,
  Alt+V who can see it. (Alt + the top row types 1–0 on the Kindle Keyboard,
  so those letters aren't shortcuts here.)
- # Tag: your tags, or a new one (the keyboard has no # key; Sym+G also types #).
- New notes are private unless you choose otherwise.
- Draw (touch Kindles): drawings to go with the note
  (`gzreader_drawscreen.lua`: pages, each on its paper), sent to Memos as
  drawings you can edit there. A note that has drawings opens them for
  editing right away (Edit edits the drawings; Done goes back to the text);
  Done over the old ones replaces them.
- Touch Kindles edit the note formatted, as in Memos' web editor
  (`gzreader_richedit.lua`): no Markdown markers or `&nbsp;` to see; hold
  and drag to select, and the toolbar formats the selection.
- Back: asks whether to save when something changed.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local lfs = require("libs/libkoreader-lfs")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local util = require("util")
local Touch = require("gzreader_touch")
local Log = require("gzreader_log")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local NoteEditor = {}

NoteEditor.TOOLS = {
    { id = "list", label = "\u{2022} " .. _("List"), key = "L", prefix = "- ", help = _("bulleted list") },
    { id = "check", label = "\u{2610} " .. _("Check"), key = "C", prefix = "- [ ] ", help = _("checklist") },
    { id = "numbered", label = "1. " .. _("Num"), key = "N", prefix = "1. ", help = _("numbered list") },
    { id = "heading", label = "H " .. _("Head"), key = "H", prefix = "## ", help = _("heading") },
    { id = "italic", label = "I", key = "K", wrap = "*", help = _("italic") },
    { id = "bold", label = "B", key = "B", wrap = "**", help = _("bold") },
    { id = "tag", label = "# " .. _("Tag"), key = "G", help = _("add a tag") },
}

-- Touch Kindles edit the note formatted (Memos' web editor); false: Markdown, as on keyboard Kindles.
NoteEditor.RICH = true

-- The toolbar on touch Kindles (the formatted page): on the selection, or the cursor's line or word.
NoteEditor.RICH_TOOLS = {
    { id = "heading", label = "H " .. _("Head") },
    { id = "bullet", label = "\u{2022} " .. _("List") },
    { id = "task", label = "\u{2610} " .. _("Check") },
    { id = "ordered", label = "1. " .. _("Num") },
    { id = "bold", label = "B" },
    { id = "italic", label = "I" },
    { id = "tag", label = "# " .. _("Tag") },
}

NoteEditor.VISIBILITY = { "PRIVATE", "PROTECTED", "PUBLIC" }
-- In a space (Memos v0.31), also "only its members", second as in Memos' own menu.
NoteEditor.VISIBILITY_IN_SPACE = { "PRIVATE", "SPACE", "PROTECTED", "PUBLIC" }
--- Seconds the top row ignores taps after the drawing screen closes (Done is
--- in the same corner as Private ▾ and Save: a second tap on a slow Done
--- landed on them).
NoteEditor.TAP_GUARD_S = 0.8

--- True while taps on the top row are ignored: within TAP_GUARD_S of `since`
--- (seconds; nil: never).
function NoteEditor.guarded(since, now)
    return since ~= nil and now ~= nil and now >= since and now - since < NoteEditor.TAP_GUARD_S
end

NoteEditor.VIS_LABEL = { PRIVATE = _("Private"), PROTECTED = _("Signed-in users"), PUBLIC = _("Public"),
    SPACE = _("Space members") }

--- Who can see a note in `space` (nil: none): the choices Alt+V goes through.
--- (Space members only in a space, or for a note that already has it.)
function NoteEditor.visibilities(space, current)
    if space or current == "SPACE" then return NoteEditor.VISIBILITY_IN_SPACE end
    return NoteEditor.VISIBILITY
end

--- The next visibility after `current` (Alt+V, a tap).
function NoteEditor.nextVisibility(current, space)
    local list = NoteEditor.visibilities(space, current)
    local i = 1
    for j, v in ipairs(list) do if v == current then i = j end end
    return list[i % #list + 1]
end

--- Moving a note out of its space: "Space members" can't stay (Memos
--- refuses it without a space), so it becomes Private, as in Memos' own
--- Move dialog. Otherwise who can see it stays as it was.
function NoteEditor.visibilityAfterMove(visibility, space)
    if not space and visibility == "SPACE" then return "PRIVATE" end
    return visibility
end

---------------------------------------------------------------- Markdown edits (plain text, tested)

-- Line prefixes the list tools replace one another with.
local PREFIXES = { "^%- %[[ xX]%] ", "^[%-%*%+] ", "^%d+[%.%)] ", "^#+ " }

local function lineBounds(chars, pos)
    local s = pos
    while s > 1 and chars[s - 1] ~= "\n" do s = s - 1 end
    local e = pos
    while e <= #chars and chars[e] ~= "\n" do e = e + 1 end
    return s, e - 1
end

--- Apply a line tool to the line holding the cursor. `text`, `pos` (the
--- cursor, 1-based character position): returns the new text and cursor.
function NoteEditor.applyPrefix(text, pos, tool)
    local chars = util.splitToChars(text)
    pos = math.max(1, math.min(pos, #chars + 1))
    local s, e = lineBounds(chars, pos)
    local line = table.concat(chars, "", s, e)
    local indent, body = line:match("^(%s*)(.*)$")
    local old = ""
    for _i, pat in ipairs(PREFIXES) do
        local m = body:match(pat)
        if m then old = m; break end
    end
    local prefix = tool.prefix
    if tool.id == "numbered" then
        -- continue the list above
        local ps = s - 1
        if ps >= 1 then
            local pls = lineBounds(chars, ps)
            local prev = table.concat(chars, "", pls, ps - 1)
            local n = prev:match("^%s*(%d+)[%.%)] ")
            if n then prefix = (tonumber(n) + 1) .. ". " end
        end
    end
    local same = old ~= "" and (old == tool.prefix or (tool.id == "numbered" and old:match("^%d+[%.%)] ")))
    local new_body = body:sub(#old + 1)
    if not same then new_body = prefix .. new_body end
    local new_line = indent .. new_body
    local before = table.concat(chars, "", 1, s - 1)
    local after = table.concat(chars, "", e + 1)
    local shift = util.splitToChars(new_line)
    local delta = #shift - (e - s + 1)
    local cursor = math.max(s, pos + delta)
    if pos <= s + #util.splitToChars(indent .. old) then cursor = s + #shift end -- at the start: go after the marker
    if cursor > s + #shift then cursor = s + #shift end
    return before .. new_line .. after, cursor
end

--- Italic / bold markers at the cursor (the cursor goes between them). On a
--- word, the word is wrapped instead.
function NoteEditor.applyWrap(text, pos, mark)
    local chars = util.splitToChars(text)
    pos = math.max(1, math.min(pos, #chars + 1))
    local function word(c) return c and not c:match("^[%s%p]$") end
    local ws, we = pos, pos - 1
    while ws > 1 and word(chars[ws - 1]) do ws = ws - 1 end
    while we < #chars and word(chars[we + 1]) do we = we + 1 end
    local n = #util.splitToChars(mark)
    if we >= ws then -- inside or at the edge of a word: wrap it
        local before = table.concat(chars, "", 1, ws - 1)
        local w = table.concat(chars, "", ws, we)
        local after = table.concat(chars, "", we + 1)
        return before .. mark .. w .. mark .. after, we + 1 + 2 * n
    end
    local before = table.concat(chars, "", 1, pos - 1)
    local after = table.concat(chars, "", pos)
    return before .. mark .. mark .. after, pos + n
end

--- "#tag " at the cursor, with a space before it when needed.
function NoteEditor.insertTag(text, pos, tag)
    local chars = util.splitToChars(text)
    pos = math.max(1, math.min(pos, #chars + 1))
    local prev = chars[pos - 1]
    local ins = ((prev and not prev:match("%s")) and " " or "") .. "#" .. tag .. " "
    local before = table.concat(chars, "", 1, pos - 1)
    local after = table.concat(chars, "", pos)
    return before .. ins .. after, pos + #util.splitToChars(ins)
end

--- A tag as Memos reads it (letters, digits, - _ /).
function NoteEditor.cleanTag(s)
    s = (s or ""):gsub("^%s*#*", ""):gsub("%s+$", ""):gsub("%s+", "-")
    s = s:gsub("[^%w%-_/\128-\255]", ""):gsub("%-+$", "")
    return s
end

---------------------------------------------------------------- the window (a quick note)

--- The quick note's window: as wide as fits (a margin each side, no wider
--- than a Kindle 3's page), its text box about a quarter of the screen,
--- centred in what the on-screen keyboard leaves (`kb_h`, 0 without one).
--- `chrome_h`: the window's height without the text; `s`: Screen:scaleBySize.
--- Returns { x, y, w, h, text_h } (pure: run_tests.lua).
function NoteEditor.floatingBox(sw, sh, kb_h, chrome_h, s)
    local gap = s(16)
    local w = math.min(sw - 2 * gap, s(560))
    local free = sh - (kb_h or 0)
    local text_h = math.min(math.floor(sh * 0.28), free - chrome_h - 2 * gap)
    text_h = math.max(text_h, s(60))
    local h = chrome_h + text_h
    local y = math.max(math.min(gap, math.floor(free / 2)), math.floor((free - h) / 2))
    return { x = math.floor((sw - w) / 2), y = y, w = w, h = h, text_h = text_h }
end

---------------------------------------------------------------- the page

local Editor = InputContainer:extend{ covers_fullscreen = true,
    gz_no_flash = true } -- (typing: no flash at every key on a Kindle 3, gzreader_eink)

-- The text box: Alt shortcuts reach the editor before the box types them,
-- and Alt + the top row types 1–0 (the Kindle Keyboard's numbers).
local ALT_DIGITS = { Q = "1", W = "2", E = "3", R = "4", T = "5", Y = "6", U = "7", I = "8", O = "9", P = "0" }

local function makeInput(editor, opts)
    local InputText = require("ui/widget/inputtext")
    local Box = InputText:extend{}
    function Box:onKeyPress(key)
        if not self.focused then return false end
        if key.modifiers and key.modifiers.Alt and not key.modifiers.Shift then
            if editor:onShortcut(key.key) then return true end
            local d = ALT_DIGITS[key.key] or (tostring(key.key):match("^%d$") and key.key)
            if d then self:addChars(d); return true end
        end
        if key.key and tostring(key.key):match("^%d$") and not (key.modifiers and key.modifiers.Alt) then
            self:addChars(key.key)
            return true
        end
        return InputText.onKeyPress(self, key)
    end
    return Box:new(opts)
end

function Editor:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.visibility = (self.memo and self.memo.visibility) or "PRIVATE"
    self.original = self.memo and self.memo.content or ""
    self.original_vis = self.visibility
    -- its space (Memos v0.31): a chip beside who can see it, when you have spaces
    if self.memo then self.space = self.memo.space end -- (a new note: the space it was given, if any)
    self.original_space = self.space
    self.has_spaces = (self.spaces and #self.spaces > 0) or self.space ~= nil
    -- the note's drawings once the drawing screen has been opened: every page,
    -- { att (in Memos), path, filename, changed, removed } (nil: as in Memos)
    self.pages = nil
    self.focus_tool = nil
    self.key_events = {
        ToolLeft = { { "Left" } },
        ToolRight = { { "Right" } },
        ToolUp = { { "Up" } },
        ToolDown = { { "Down" } },
        ToolPress = { { "Press" } },
        ToolbarToggle = { { "Menu" } },
        CloseDialog = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
    }
    local margin = self.floating and S(10) or S(12)
    self.margin = margin
    -- a quick note: a window (the screen less a margin each side); otherwise the page
    self.win_w = self.floating and NoteEditor.floatingBox(sw, sh, 0, 0, S).w - 2 * Size.border.window or sw
    self.inner = self.win_w - 2 * margin
    self.title_h, self.tool_h, self.footer_h = S(44), S(40), S(30)
    local text_h = sh - self.title_h - self.tool_h - self.footer_h - S(28)
    self.touch = Touch.on() and not Touch.keys()
    -- Kindle 4: the on-screen keyboard too (the 5-way types on it); Menu goes
    -- to the toolbar (the keyboard hides) and back
    self.dpad = Touch.dpad()
    self.vk = self.touch or self.dpad
    -- (taps and keys reach the editor under the on-screen keyboard, as in KOReader's input dialogs)
    if self.vk then self.is_always_active = true end
    -- touch: the note formatted, typed into as in Memos' web editor
    -- (`gzreader_richedit.lua`; Markdown when it can't be read that way).
    -- (Not in a window over the screen: a quick note keeps its text box.)
    if self.touch and NoteEditor.RICH and not self.floating then
        -- (laid out again after a rotation: the page as it is now, gzRelayout)
        local ok, doc = true, self._gz_doc
        if not doc then ok, doc = pcall(require("gzreader_blocks").parse, self.original) end
        if ok then
            self.rich = true
            self.doc = doc
        else
            Log.warn("notes: not read as blocks, editing Markdown:", tostring(doc))
        end
    end
    -- touch, the full page: Save at the top right (beside Space and Private, where the drawing screen's Done is)
    self.save_top = self.touch and not self.floating or nil
    if self.rich then self.tool_h = S(50) end -- (the row under the title: the note's sheets, and Save off touch)
    local function box(h)
        -- (the formatted page: made once, its own height above its keyboard)
        if self.rich then
            self.rich_input = self.rich_input or require("gzreader_richedit"):new{
                width = self.inner, max_height = sh - self.title_h - self.tool_h - S(16),
                doc = self.doc, editor = self, at_start = self.memo == nil,
                hint = _("Write a note. #words become tags."),
            }
            return self.rich_input
        end
        return makeInput(self, {
            text = self.original, width = self.inner - 2 * (S(8) + Size.border.thin), height = h, scroll = true,
            face = Font:getFace("cfont", 20), parent = self, focused = true,
            padding = S(8), margin = 0, bordersize = Size.border.thin,
            hint = _("Write a note. #words become tags."),
            gz_multiline = true, -- (the on-screen keyboard keeps Enter and ← →)
        })
    end
    if self.floating and not self.vk then
        self.box = NoteEditor.floatingBox(sw, sh, 0, self:floatingChrome(), S)
        text_h = self.box.text_h
    end
    self.input = box(text_h)
    if self.vk then
        -- touch: the toolbar under the title, the text box above the on-screen keyboard
        self.footer_h = self.dpad and S(26) or 0
        local kb = self.input.keyboard
        local kb_h = kb and kb.dimen and kb.dimen.h or math.floor(sh * 0.4)
        if self.input.free then pcall(self.input.free, self.input) end
        text_h = sh - self.title_h - self.tool_h - kb_h - S(24) - (self.dpad and S(26) or 0)
        if self.floating then
            self.box = NoteEditor.floatingBox(sw, sh, kb_h, self:floatingChrome(), S)
            text_h = self.box.text_h
        end
        self.input = box(text_h)
    end
    self.title_slot = VerticalGroup:new{}
    self.bar_slot = VerticalGroup:new{}
    self.hint_slot = VerticalGroup:new{}
    local column
    if self.vk then
        column = VerticalGroup:new{ align = "center",
            self.title_slot,
            self.bar_slot,
            self.hint_slot, -- (Kindle 4: what the keys do)
            VerticalSpan:new{ width = S(8) },
            self.input,
            self.floating and VerticalSpan:new{ width = S(8) } or nil,
        }
    else
        column = VerticalGroup:new{ align = "center",
            self.title_slot,
            self.input,
            VerticalSpan:new{ width = S(10) },
            self.bar_slot, -- at the bottom: ▼ from the last line reaches it, ▲ goes back
            VerticalSpan:new{ width = S(8) },
            self.hint_slot,
            self.floating and VerticalSpan:new{ width = S(6) } or nil,
        }
    end
    if self.floating then
        -- a window: what's under it (the book, Home) stays on the screen around it
        self.frame = FrameContainer:new{ padding = 0, bordersize = Size.border.window, radius = Size.radius.window,
            background = Blitbuffer.COLOR_WHITE, column }
        self[1] = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = self.box.y },
            HorizontalGroup:new{ HorizontalSpan:new{ width = self.box.x }, self.frame } }
        if Touch.on() then
            self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
        end
    else
        self[1] = FrameContainer:new{
            width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
            column,
        }
    end
    self:drawChrome()
end

--- A quick note's window without its text box: title, toolbar, key hints,
--- the spaces between, the text box's own frame and the window's border.
function Editor:floatingChrome()
    local around_text = 2 * (S(8) + Size.border.thin) + 2 * Size.border.window
    if self.vk then return self.title_h + self.tool_h + self.footer_h + S(8) + S(8) + around_text end
    return self.title_h + S(10) + self.tool_h + S(8) + self.footer_h + S(6) + around_text
end

--- A tap outside the quick note's window: as Back (asks to save when
--- something was written).
function Editor:onTapOutside(_arg, ges)
    local d = self.frame and self.frame.dimen
    if not (d and ges and ges.pos) or ges.pos:intersectWith(d) then return false end
    return self:onCloseDialog()
end

--- What a redraw refreshes: the window, or the page.
function Editor:area()
    if self.frame and self.frame.dimen then return self.frame.dimen end
    return self.dimen
end

--- Touch and the Kindle 4: KOReader keeps the on-screen keyboard above every
--- other window, so it hid the lower half of `dialog` (Save this note?, Add a
--- tag, New tag). It steps aside while the dialog is open and comes back
--- once it's closed, if the note is still the window in front.
function Editor:keyboardAside(dialog)
    if not (self.vk and self.input and self.input.onCloseKeyboard) then return end
    self.input:onCloseKeyboard()
    local closed = dialog.onCloseWidget
    dialog.onCloseWidget = function(d, ...)
        local r
        if closed then r = closed(d, ...) end
        UIManager:nextTick(function() self:keyboardBack() end)
        return r
    end
end

--- The keyboard again, when the editor is in front (only the keyboard or a
--- message above it) and not on the Kindle 4's toolbar.
function Editor:keyboardBack()
    if not (self.vk and self.input and self.input.onShowKeyboard) or (self.dpad and self.focus_tool) then return end
    local st = UIManager._window_stack or {}
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w == self then self.input:onShowKeyboard(); return true end
        if w.name ~= "VirtualKeyboard" and not w.toast then return end
    end
end

--- Touch: `widget`, tapped, runs `fn`.
local function tapTarget(widget, fn)
    if not Touch.on() then return widget end
    local size = widget:getSize()
    local box = InputContainer:new{ dimen = Geom:new{ w = size.w, h = size.h }, widget }
    box.ges_events = { TapIt = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    function box:onTapIt() fn(); return true end
    return box
end

--- Seconds now (monotonic).
function Editor.now()
    local time = require("ui/time")
    return time.to_s(time.now())
end

--- A tap target in the top row: ignored just after the drawing screen closed
--- (NoteEditor.TAP_GUARD_S), so a second tap on its Done does nothing here.
function Editor:topTap(widget, fn)
    return tapTarget(widget, function()
        if NoteEditor.guarded(self.drawing_closed_at, Editor.now()) then
            Log.info("notes: a tap on the editor's top row right after the drawing closed: ignored")
            self.taps_ignored = (self.taps_ignored or 0) + 1
            return
        end
        fn()
    end)
end

function Editor:onCloseWidget()
    self.closed = true
    if self.input and self.input.onCloseKeyboard then pcall(self.input.onCloseKeyboard, self.input) end
end

--- The on-screen keyboard back a moment later, if the note is still open
--- then: closed meanwhile (a tap outside the quick note while the Kindle
--- was still redrawing after the drawing screen), the keyboard stayed over
--- the book with nothing under it (the owner, 2026-11-16).
function Editor:keyboardSoon()
    if not self.vk then return end
    UIManager:nextTick(function()
        if self.closed or not self.input or not self.input.onShowKeyboard then return end
        for _i, w in ipairs(UIManager._window_stack or {}) do
            if w.widget == self then return self.input:onShowKeyboard() end
        end
    end)
end

function Editor:onShow()
    -- touch: the on-screen keyboard, at once (not when the drawing screen opens over it first)
    if not self.drawing_first then self:keyboardSoon() end
end

function Editor:drawChrome()
    local sw = self.win_w
    local margin = self.margin
    self.title_slot:clear()
    self.title_slot[1] = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = self.title_h },
        LeftContainer:new{ dimen = Geom:new{ w = sw, h = self.title_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = margin },
                self.touch and tapTarget(FrameContainer:new{ padding = S(6), bordersize = 0,
                    TextWidget:new{ text = "\u{2715}", face = Font:getFace("cfont", 22) } }, function() self:onCloseDialog() end)
                    or HorizontalSpan:new{ width = 0 },
                self.touch and HorizontalSpan:new{ width = S(8) } or HorizontalSpan:new{ width = 0 },
                TextWidget:new{ text = self.memo and _("Edit note") or _("New note"), face = Font:getFace("smalltfont", 21), bold = true } } },
        RightContainer:new{ dimen = Geom:new{ w = sw, h = self.title_h },
            HorizontalGroup:new{
                (self:canDraw() and not self.rich) and self:topTap(FrameContainer:new{ padding = S(6), radius = S(6), bordersize = Size.border.thick,
                    background = self:hasDrawing() and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                    TextWidget:new{ text = self:drawingLabel(),
                        face = Font:getFace("cfont", 15), bold = true,
                        fgcolor = self:hasDrawing() and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } },
                    function() self:openDrawing() end)
                    or HorizontalSpan:new{ width = 0 },
                HorizontalSpan:new{ width = (self:canDraw() and not self.rich) and S(8) or 0 },
                self.has_spaces and self:topTap(FrameContainer:new{ padding = S(6), radius = S(6),
                    bordersize = (self.touch or (self.dpad and self.focus_tool == #NoteEditor.TOOLS + 3)) and Size.border.thick
                        or (self.dpad and Size.border.thin) or 0,
                    TextWidget:new{ text = self:spaceLabel() .. ((self.touch or self.dpad) and "  \u{25BE}" or "  (Alt+A)"),
                        face = Font:getFace("cfont", 15), max_width = math.floor(sw * (self.save_top and 0.22 or 0.3)) } },
                        function() self:onShortcut("A") end)
                    or HorizontalSpan:new{ width = 0 },
                HorizontalSpan:new{ width = self.has_spaces and S(8) or 0 },
                self:topTap(FrameContainer:new{ padding = S(6), radius = S(6),
                    bordersize = (self.touch or (self.dpad and self.focus_tool == #NoteEditor.TOOLS + 2)) and Size.border.thick
                        or (self.dpad and Size.border.thin) or 0,
                    TextWidget:new{ text = NoteEditor.VIS_LABEL[self.visibility] .. ((self.touch or self.dpad) and "  \u{25BE}" or "  (Alt+V)"),
                        face = Font:getFace("cfont", 15) } }, function() self:onShortcut("V") end),
                -- touch: Save at the top right, where the drawing screen's Done is
                self.save_top and HorizontalSpan:new{ width = S(10) } or HorizontalSpan:new{ width = 0 },
                self.save_top and self:topTap(FrameContainer:new{ padding = S(6), padding_left = S(14), padding_right = S(14),
                    radius = S(6), bordersize = Size.border.thick, background = Blitbuffer.COLOR_BLACK,
                    TextWidget:new{ text = _("Save"), face = Font:getFace("cfont", 16), bold = true, fgcolor = Blitbuffer.COLOR_WHITE } },
                    function() self:save() end)
                    or HorizontalSpan:new{ width = 0 },
                HorizontalSpan:new{ width = margin } } },
    }
    local bar = HorizontalGroup:new{ align = "center" }
    -- (Save at the top on touch: this row is all the tools', or the sheets')
    local save_w = self.save_top and 0 or S(70)
    local save_gap = self.save_top and 0 or S(10)
    local tools = self:tools()
    local tool_w = math.floor((self.inner - save_w - save_gap) / math.max(1, #tools))
    if self.rich then
        -- the formatted page: formatting comes up at the selection (gzreader_richedit.lua's bar);
        -- this row is the note's sheets (its drawings), and Save (at the top on touch)
        local strip = self:sheetStrip(self.inner - save_w - save_gap)
        bar[#bar + 1] = LeftContainer:new{ dimen = Geom:new{ w = self.inner - save_w - save_gap, h = self.tool_h }, strip }
    end
    for i, t in ipairs(tools) do
        local focused = self.focus_tool == i
        local fg = focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local txt
        if t.id == "italic" then
            local ok, face = pcall(Font.getFace, Font, "./fonts/noto/NotoSerif-Italic.ttf", 19)
            txt = TextWidget:new{ text = "I", face = ok and face or Font:getFace("infofont", 17), fgcolor = fg }
        else
            txt = TextWidget:new{ text = t.label, face = Font:getFace("cfont", 15), bold = t.id == "bold" or focused, fgcolor = fg,
                max_width = tool_w - S(4) }
        end
        bar[#bar + 1] = tapTarget(FrameContainer:new{
            width = tool_w, height = self.tool_h, padding = 0, margin = 0, bordersize = Size.border.thin,
            background = focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = tool_w - 2, h = self.tool_h - 2 }, txt },
        }, function() self:useTool(i) end)
    end
    local save_focused = self.focus_tool == #tools + 1
    if not self.save_top then
        bar[#bar + 1] = HorizontalSpan:new{ width = S(10) }
        bar[#bar + 1] = tapTarget(FrameContainer:new{
            width = save_w, height = self.tool_h, padding = 0, bordersize = Size.border.thick, radius = S(6),
            background = save_focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = save_w - 4, h = self.tool_h - 4 },
                TextWidget:new{ text = _("Save"), face = Font:getFace("cfont", 18), bold = true,
                    fgcolor = save_focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } },
        }, function() self:save() end)
    end
    self.bar_slot:clear()
    self.bar_slot[1] = bar
    if self.touch then return end -- (no key hints)
    local t = self.focus_tool and tools[self.focus_tool]
    local hint
    if self.dpad then
        hint = self.focus_tool and (_("\u{25C0} \u{25B6} choose   Press apply   Menu: back to the text"))
            or (self.has_spaces and _("Menu: toolbar, visibility, space, save     Back: close")
                or _("Menu: toolbar, visibility, save     Back: close"))
    elseif t then
        hint = t.help .. "  (Alt+" .. t.key .. ")   \u{00B7}   \u{25C0} \u{25B6} " .. _("choose") .. "   " .. _("Press apply")
            .. "   Menu " .. _("text")
    elseif self.focus_tool then
        hint = _("Save to Memos") .. "  (Alt+S)   \u{00B7}   Menu " .. _("back to the text")
    else
        hint = "Menu " .. _("toolbar") .. "   \u{00B7}   Alt+G " .. _("tag") .. "   Alt+C " .. _("check") .. "   Alt+B "
            .. _("bold") .. "   Alt+S " .. _("save")
    end
    self.hint_slot:clear()
    self.hint_slot[1] = CenterContainer:new{ dimen = Geom:new{ w = sw, h = self.footer_h },
        TextWidget:new{ text = hint, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = self.inner } }
end

function Editor:redraw()
    self:drawChrome()
    UIManager:setDirty(self, function() return "ui", self:area() end)
end

--- The toolbar's tools: the Markdown ones (keyboard Kindles, a quick note's window). The
--- formatted page has none in a row: its bar comes up at the selection.
function Editor:tools() return self.rich and {} or NoteEditor.TOOLS end

--- The note's sheets shown in the editor: { page (its number), path (its picture, if it's here) }.
function Editor:sheets()
    local Memos = require("gzreader_memos")
    local out = {}
    if self.pages then
        for _i, p in ipairs(self.pages) do
            if not p.removed then out[#out + 1] = { page = #out + 1, path = p.path or (p.att and Memos.filePath(p.att)) } end
        end
    else
        for i, att in ipairs(self.drawing_atts or {}) do out[i] = { page = i, path = Memos.filePath(att) } end
    end
    return out
end

NoteEditor.STRIP_THUMBS = 3 -- sheets pictured in the editor's strip (the rest: "… of n")
NoteEditor.STRIP_PHOTOS = 3 -- photos pictured there (the rest: "+n", a list)

--- The formatted page's row under the title: the note's sheets as small pictures (a tap
--- opens that page to draw on), their count, and "New sheet" for a note without any.
--- Without drawing (not connected, a pen-less Kindle): how formatting works.
function Editor:sheetStrip(width)
    local row = HorizontalGroup:new{ align = "center" }
    local sheets = self:sheets()
    self.strip = { thumbs = 0, label = nil }
    local function label(text, bold, gray)
        return TextWidget:new{ text = text, face = Font:getFace("cfont", 15), bold = bold,
            fgcolor = gray and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK, max_width = math.floor(width * 0.6) }
    end
    if #sheets == 0 and not self:canDraw() then
        row[1] = label(_("Hold a word to format it. Drag to choose more."), false, true)
        return row
    end
    local th = self.tool_h - S(8)
    local tw = math.floor(th * 0.77)
    if self:canDraw() or #sheets > 0 then
        local Sticky = require("gzreader_sticky")
        local ImageWidget = require("ui/widget/imagewidget")
        for i, sh in ipairs(sheets) do
            if i > NoteEditor.STRIP_THUMBS then break end
            local bb = sh.path and Sticky.picture(sh.path, tw - 2, th - 2, 1)
            local inside = bb and ImageWidget:new{ image = bb, image_disposable = true }
                or TextWidget:new{ text = tostring(sh.page), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            local cell = FrameContainer:new{ width = tw, height = th, padding = 0, margin = 0, bordersize = Size.border.thin,
                background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = Geom:new{ w = tw - 2, h = th - 2 }, inside } }
            row[#row + 1] = self:canDraw() and tapTarget(cell, function() self:openDrawing(sh.page) end) or cell
            row[#row + 1] = HorizontalSpan:new{ width = S(6) }
            self.strip.thumbs = self.strip.thumbs + 1
        end
    end
    local text
    if #sheets == 0 then text = "\u{270E} " .. _("Draw")
    elseif #sheets == 1 then text = "\u{270E} " .. _("1 sheet")
    else text = "\u{270E} " .. T(_("%1 sheets"), #sheets) end
    self.strip.label = text
    local chip = FrameContainer:new{ padding = S(6), radius = S(6), bordersize = self:canDraw() and Size.border.thick or 0,
        label(text, true) }
    row[#row + 1] = self:canDraw() and tapTarget(chip, function() self:openDrawing() end) or chip
    -- the note's photos (attached, put in the text here, or to be attached): small pictures,
    -- a tap for what to do with one; then + Photos (Immich)
    local photos = self:photoList()
    self.strip.photo_thumbs = 0
    if #photos > 0 then
        local Sticky = require("gzreader_sticky")
        local ImageWidget = require("ui/widget/imagewidget")
        row[#row + 1] = HorizontalSpan:new{ width = S(8) }
        for i, ph in ipairs(photos) do
            if i > NoteEditor.STRIP_PHOTOS then break end
            local here = ph.path and lfs.attributes(ph.path, "mode") == "file"
            if not here and ph.att and self.immich then
                -- (not on the Kindle yet: fetched, then drawn)
                require("gzreader_notes").fetchFile(self.immich, ph.att, function() if not self.closed then self:redraw() end end)
            end
            local bb = here and Sticky.picture(ph.path, th - 2, th - 2)
            local inside = bb and ImageWidget:new{ image = bb, image_disposable = true }
                or TextWidget:new{ text = "\u{2026}", face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            local cell = FrameContainer:new{ width = th, height = th, padding = 0, margin = 0,
                bordersize = ph.in_text and Size.border.thick or Size.border.thin,
                background = Blitbuffer.COLOR_WHITE, CenterContainer:new{ dimen = Geom:new{ w = th - 2, h = th - 2 }, inside } }
            row[#row + 1] = tapTarget(cell, function() self:photoActions(ph) end)
            row[#row + 1] = HorizontalSpan:new{ width = S(6) }
            self.strip.photo_thumbs = self.strip.photo_thumbs + 1
        end
        if #photos > NoteEditor.STRIP_PHOTOS then
            row[#row + 1] = tapTarget(label("+" .. (#photos - NoteEditor.STRIP_PHOTOS), true, true), function() self:photosMenu() end)
        end
    end
    if self.immich then
        -- photos from Immich (as the Memos fork's Insert image → From Immich): in the text or attached, asked each time
        local ptext = "+ " .. _("Photos")
        self.strip.photos = ptext
        row[#row + 1] = HorizontalSpan:new{ width = S(8) }
        row[#row + 1] = tapTarget(FrameContainer:new{ padding = S(6), radius = S(6), bordersize = Size.border.thick, label(ptext, true) },
            function() self:addPhotos() end)
    end
    if #sheets == 0 and not self.immich and #photos == 0 then
        row[#row + 1] = HorizontalSpan:new{ width = S(10) }
        row[#row + 1] = TextWidget:new{ text = _("Hold a word to format it"), face = Font:getFace("cfont", 13),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = math.max(S(40), width - chip:getSize().w - S(14)) }
    end
    return row
end

--- The note as Markdown (formatted: written back as Memos' rich editor writes it).
function Editor:text()
    if self.rich then return require("gzreader_blocks").write(self.doc) end
    return self.input:getText() or ""
end

function Editor:apply(new_text, cursor)
    self.input:setText(new_text, true)
    self.input.is_text_edited = true
    self.input:moveCursorToCharPos(cursor)
    UIManager:setDirty(self, function() return "ui", self:area() end)
end

function Editor:useTool(i)
    if self.rich then
        return self:save() -- (its row has only Save: formatting is the bar at the selection)
    end
    local t = NoteEditor.TOOLS[i]
    if not t then return self:save() end
    local pos = self.input.charpos or (#self.input.charlist + 1)
    self.last_tool = i
    if t.prefix then
        self:apply(NoteEditor.applyPrefix(self:text(), pos, t))
    elseif t.wrap then
        self:apply(NoteEditor.applyWrap(self:text(), pos, t.wrap))
    elseif t.id == "tag" then
        return self:pickTag(pos)
    end
    self:backToText()
end

--- The text box loses / gets back the keys without being rebuilt (InputText's
--- unfocus / focus redo the text box: its cursor would vanish and a long
--- note would scroll), so the cursor stays where it is, visible.
function Editor:textKeys(on)
    self.input.focused = on
    if self.input._frame_textwidget then
        self.input._frame_textwidget.color = on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    end
end

function Editor:backToText()
    self.focus_tool = nil
    self:textKeys(true)
    self:redraw()
    if self.dpad and self.input then self.input:onShowKeyboard() end
end

function Editor:pickTag(pos)
    local dialog
    local rows = {}
    local function insert(tag)
        tag = NoteEditor.cleanTag(tag)
        if tag ~= "" and self.rich then self.input:insertTag(tag)
        elseif tag ~= "" then self:apply(NoteEditor.insertTag(self:text(), pos, tag)) end
        self:backToText()
    end
    for i, t in ipairs(self.tags or {}) do
        if i > 9 then break end
        rows[#rows + 1] = { { text = "#" .. t.tag, align = "left", callback = function() UIManager:close(dialog); insert(t.tag) end } }
    end
    rows[#rows + 1] = { { text = _("New tag…"), align = "left", callback = function()
        UIManager:close(dialog)
        local InputDialog = require("ui/widget/inputdialog")
        local d
        d = InputDialog:new{ title = _("New tag"), input = "", input_hint = _("e.g. travel or books/to-read"),
            buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d); self:backToText() end },
                { text = _("Add"), is_enter_default = true, callback = function()
                    local v = d:getInputText()
                    UIManager:close(d)
                    insert(v)
                end } } } }
        self:keyboardAside(d)
        UIManager:show(d)
        d:onShowKeyboard()
    end } }
    dialog = ButtonDialog:new{ title = _("Add a tag"), buttons = rows }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    self:keyboardAside(dialog)
    UIManager:show(dialog)
end

--- Alt + key (from the text box or the toolbar). True when it was ours.
function Editor:onShortcut(k)
    if k == "S" then self:save(); return true end
    if k == "V" then
        self.visibility = NoteEditor.nextVisibility(self.visibility, self.space)
        self:redraw()
        return true
    end
    if k == "A" and self.has_spaces then self:pickSpace(); return true end
    for i, t in ipairs(NoteEditor.TOOLS) do
        if t.key == k then self:useTool(i); return true end
    end
    return false
end

function Editor:onToolDown()
    -- the text box passes ▼ on from its last line
    if not self.focus_tool then
        self.focus_tool = self.last_tool or 1
        self:textKeys(false)
        self:redraw()
    end
    return true
end

--- Menu: to the toolbar and back; the cursor stays where it is in the text.
function Editor:onToolbarToggle()
    if self.focus_tool then
        self:backToText()
    else
        -- (Kindle 4: the keyboard steps aside while on the toolbar)
        if self.dpad and self.input then self.input:onCloseKeyboard() end
        self:onToolDown()
    end
    return true
end

--- The toolbar's last cell: Save, then (Kindle 4) who can see the note and
--- its space.
function Editor:lastTool()
    if not self.dpad then return #NoteEditor.TOOLS + 1 end
    return #NoteEditor.TOOLS + (self.has_spaces and 3 or 2)
end

function Editor:onToolUp()
    if self.focus_tool then self:backToText() end
    return true
end

function Editor:onToolLeft()
    if not self.focus_tool then return false end
    self.focus_tool = self.focus_tool > 1 and self.focus_tool - 1 or self:lastTool()
    self:redraw()
    return true
end

function Editor:onToolRight()
    if not self.focus_tool then return false end
    self.focus_tool = self.focus_tool < self:lastTool() and self.focus_tool + 1 or 1
    self:redraw()
    return true
end

function Editor:onToolPress()
    if not self.focus_tool then return false end
    if self.focus_tool == #NoteEditor.TOOLS + 2 then self:onShortcut("V"); return true end
    if self.focus_tool == #NoteEditor.TOOLS + 3 then self:onShortcut("A"); return true end
    self:useTool(self.focus_tool)
    return true
end

function Editor:onKeyPress(key)
    -- on the toolbar, Alt shortcuts still work; typing goes back to the text
    if self.focus_tool and key.modifiers and key.modifiers.Alt and self:onShortcut(key.key) then return true end
    local r = InputContainer.onKeyPress(self, key)
    if r then return r end
    if self.focus_tool and type(key.key) == "string" and #key.key == 1 then
        self:backToText()
        return self.input:onKeyPress(key)
    end
    return r
end

function Editor:changed()
    return self:text() ~= self.original or self.visibility ~= self.original_vis or self.space ~= self.original_space
        or #self:drawingChanges() > 0 or self.pages_reordered == true or #(self.photos or {}) > 0
        or #(self.sent or {}) > 0 or #(self.dropped or {}) > 0 or #(self.unsent or {}) > 0
end

-- ------------------------------------------------------------------ photos

--- The note's photos as the editor shows them: { kind = "att" (the note's, in Memos),
--- "sent" (put in the text here: sent already) or "new" (to be attached at Save),
--- att, path (its file here), filename, in_text }.
function Editor:photoList()
    local Memos = require("gzreader_memos")
    local text = self:text()
    local out = {}
    local dropped = {}
    for _i, n in ipairs(self.dropped or {}) do dropped[n] = true end
    local function inText(att)
        local uid = tostring(att.name):match("attachments/(.+)$")
        return uid ~= nil and text:find("/file/attachments/" .. uid, 1, true) ~= nil
    end
    for _i, a in ipairs(self.photo_atts or {}) do
        if not dropped[a.name] then
            out[#out + 1] = { kind = "att", att = a, path = Memos.filePath(a), filename = a.filename, in_text = inText(a) }
        end
    end
    for _i, a in ipairs(self.sent or {}) do
        out[#out + 1] = { kind = "sent", att = a, path = Memos.filePath(a), filename = a.filename, in_text = inText(a) }
    end
    for _i, f in ipairs(self.photos or {}) do
        out[#out + 1] = { kind = "new", file = f, path = f.path, filename = f.filename, in_text = false }
    end
    return out
end

--- Photos from Immich (gzreader_immichpick.lua): asked each time whether they
--- go in the text, at the cursor (as Insert image does in Memos), or with
--- the note as attachments (as Insert image → From Immich does).
function Editor:addPhotos()
    if self.vk and self.input and self.input.onCloseKeyboard then self.input:onCloseKeyboard() end
    require("gzreader_immichpick").show(self.immich, { on_pick = function(files)
        if self.closed then for _i, f in ipairs(files) do os.remove(f.path) end; return end
        local dialog
        local function attach()
            UIManager:close(dialog)
            self.photos = self.photos or {}
            for _i, f in ipairs(files) do self.photos[#self.photos + 1] = f end
            Log.info("notes: editor:", #files, "photo(s) from Immich to go with the note")
            self:redraw()
        end
        dialog = ButtonDialog:new{
            title = #files == 1 and _("Where does the photo go?") or T(_("Where do the %1 photos go?"), #files),
            buttons = {
                { { text = _("In the text, at the cursor"), align = "left", callback = function()
                    UIManager:close(dialog)
                    self:putInText(files)
                end } },
                { { text = _("With the note, as attachments"), align = "left", callback = attach } },
            },
            tap_close_callback = attach, -- (closed without a choice: kept, as attachments)
        }
        UIManager:show(dialog)
    end })
end

--- Photos (picked files) put in the text at the cursor: each is sent to
--- Memos now (Memos wants a picture in a note's text to be one of its
--- attachments: a note in Memos gets them at once, a new one is made with
--- them), then its line goes in. One that can't be sent stays to be attached.
function Editor:putInText(files)
    local Memos = require("gzreader_memos")
    local Notes = require("gzreader_notes")
    local InfoMessage = require("ui/widget/infomessage")
    local c = Notes.client(self.immich)
    local busy = InfoMessage:new{ text = T(_("Sending %1 photo(s)…"), #files), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local lines, failed = {}, {}
    for _i, f in ipairs(files) do
        local att, err = c:uploadAttachment(f.path, f.filename, self.memo and self.memo.name or nil, f.type)
        if att then
            att.type = att.type or f.type
            -- (shown here at once, and on the note's page without fetching it again)
            local src = io.open(f.path, "rb")
            local data = src and src:read("*a")
            if src then src:close() end
            local dst = data and io.open(Memos.filePath(att), "wb")
            if dst then dst:write(data); dst:close() end
            os.remove(f.path)
            self.sent = self.sent or {}
            self.sent[#self.sent + 1] = att
            lines[#lines + 1] = require("gzreader_sticky").pictureLine(att)
        else
            Log.warn("notes: a photo for the text not sent:", tostring(err))
            failed[#failed + 1] = f
        end
    end
    UIManager:close(busy)
    if #lines > 0 then self:insertLines(lines) end
    if #failed > 0 then
        self.photos = self.photos or {}
        for _i, f in ipairs(failed) do self.photos[#self.photos + 1] = f end
        UIManager:show(InfoMessage:new{ text = _("Couldn't send the photo to Memos now: it goes with the note as an attachment instead."), timeout = 4 })
    end
    Log.info("notes: editor:", #lines, "photo(s) put in the text")
    self:redraw()
end

--- Lines put in the text at the cursor: after the paragraph the cursor is
--- in (the formatted page: each a picture of its own), or where the cursor is.
function Editor:insertLines(lines)
    if self.rich and self.rich_input and self.doc then
        local Blocks = require("gzreader_blocks")
        local ri = self.rich_input
        local cur = ri.cur and ri.cur.b
        local idx = #self.doc.blocks
        for k, b in ipairs(self.doc.blocks) do if b == cur then idx = k end end
        local last
        for k, line in ipairs(lines) do
            last = { kind = "image", chars = Blocks.chars(line), marks = {}, dirty = true }
            table.insert(self.doc.blocks, idx + k, last)
        end
        ri.cur = { b = last, i = #last.chars + 1 }
        ri.anchor = nil
        ri:update("structure")
    elseif self.input then
        self.input:addChars("\n" .. table.concat(lines, "\n") .. "\n")
    end
end

--- Takes the lines showing attachment `att` out of the text.
function Editor:removeFromText(att)
    local uid = tostring(att.name):match("attachments/(.+)$")
    if not uid then return end
    local needle = "/file/attachments/" .. uid
    if self.rich and self.rich_input and self.doc then
        local kept = {}
        for _i, b in ipairs(self.doc.blocks) do
            if not (b.kind == "image" and table.concat(b.chars):find(needle, 1, true)) then kept[#kept + 1] = b end
        end
        if #kept == 0 then kept[1] = require("gzreader_blocks").new("paragraph") end
        self.doc.blocks = kept
        local still = false
        for _i, b in ipairs(kept) do if b == (self.rich_input.cur and self.rich_input.cur.b) then still = true end end
        if not still then self.rich_input.cur = { b = kept[#kept], i = #kept[#kept].chars + 1 } end
        self.rich_input.anchor = nil
        self.rich_input:update("structure")
    elseif self.input then
        local out = {}
        for line in ((self:text() or "") .. "\n"):gmatch("(.-)\n") do
            if not line:find(needle, 1, true) then out[#out + 1] = line end
        end
        if out[#out] == "" then table.remove(out) end
        self.input:setText(table.concat(out, "\n"), true)
        self.input.is_text_edited = true
    end
end

--- A tap on one of the note's photos: what to do with it.
function Editor:photoActions(ph)
    local dialog
    local rows = {}
    local function close() UIManager:close(dialog) end
    if ph.kind == "new" then
        rows[#rows + 1] = { { text = _("Put it in the text, at the cursor"), align = "left", callback = function()
            close()
            for i, f in ipairs(self.photos or {}) do if f == ph.file then table.remove(self.photos, i); break end end
            self:putInText({ ph.file })
        end } }
        rows[#rows + 1] = { { text = _("Take it off (not attached)"), align = "left", callback = function()
            close()
            for i, f in ipairs(self.photos or {}) do if f == ph.file then table.remove(self.photos, i); break end end
            os.remove(ph.file.path)
            self:redraw()
        end } }
    else
        if ph.in_text then
            rows[#rows + 1] = { { text = _("Take it out of the text (keep it attached)"), align = "left", callback = function()
                close(); self:removeFromText(ph.att); self:redraw()
            end } }
        else
            rows[#rows + 1] = { { text = _("Put it in the text, at the cursor"), align = "left", callback = function()
                close(); self:insertLines({ require("gzreader_sticky").pictureLine(ph.att) }); self:redraw()
            end } }
        end
        rows[#rows + 1] = { { text = _("Remove it from the note…"), align = "left", callback = function()
            close()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = T(_("Take %1 off the note? It's deleted in Memos when you save."), ph.filename or _("this photo")),
                ok_text = _("Remove"),
                ok_callback = function() self:removePhoto(ph) end,
            })
        end } }
    end
    rows[#rows + 1] = { { text = _("Show it"), align = "left", callback = function()
        close()
        local RenderImage = require("ui/renderimage")
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, ph.path, false)
        if ok and bb then
            UIManager:show(require("ui/widget/imageviewer"):new{ image = bb, image_disposable = true, with_title_bar = false, fullscreen = true })
        end
    end } }
    dialog = ButtonDialog:new{ title = ph.filename or _("Photo"), buttons = rows }
    self:keyboardAside(dialog)
    UIManager:show(dialog)
end

--- Removes a photo of the note (its line in the text too); deleted in Memos at Save.
function Editor:removePhoto(ph)
    self:removeFromText(ph.att)
    if ph.kind == "att" then
        self.dropped = self.dropped or {}
        self.dropped[#self.dropped + 1] = ph.att.name
    else
        for i, a in ipairs(self.sent or {}) do if a == ph.att then table.remove(self.sent, i); break end end
        self.unsent = self.unsent or {} -- (sent when picked: deleted at Save, or when the edit is left)
        self.unsent[#self.unsent + 1] = ph.att.name
    end
    Log.info("notes: editor: a photo removed from the note")
    self:redraw()
end

--- "+n": all of the note's photos, a tap for what to do with one.
function Editor:photosMenu()
    local dialog
    local rows = {}
    for _i, ph in ipairs(self:photoList()) do
        rows[#rows + 1] = { { text = (ph.in_text and "\u{25A3}  " or "\u{25A1}  ") .. tostring(ph.filename), align = "left", callback = function()
            UIManager:close(dialog); self:photoActions(ph)
        end } }
    end
    dialog = ButtonDialog:new{ title = _("The note's photos (\u{25A3} in the text)"), buttons = rows }
    self:keyboardAside(dialog)
    UIManager:show(dialog)
end

--- What Save does with the photos: { added = { att } (sent here, kept with the note),
--- drop = { names } (to delete in Memos: removed here, or sent here and taken out) }.
function Editor:photoChanges()
    local out = { added = {}, drop = {} }
    for _i, a in ipairs(self.sent or {}) do out.added[#out.added + 1] = a end
    for _i, n in ipairs(self.dropped or {}) do out.drop[#out.drop + 1] = n end
    for _i, n in ipairs(self.unsent or {}) do out.drop[#out.drop + 1] = n end
    return out
end

--- The screen turned (a Kindle with auto-rotate, gzreader_rotation.lua): the
--- page (or a quick note's window) laid out again at the new size, keeping
--- what was written, who can see it, its space and its drawings.
function Editor:gzRelayout()
    local keep = {}
    for _i, k in ipairs({ "visibility", "space", "original", "original_vis", "original_space", "pages", "pages_reordered", "saved", "photos", "sent", "dropped", "unsent" }) do
        keep[k] = self[k]
    end
    local text = not self.rich and self:text() or nil
    local edited = self.input and self.input.is_text_edited
    if self.input and self.input.onCloseKeyboard then pcall(self.input.onCloseKeyboard, self.input) end
    if self.input and self.input.free then pcall(self.input.free, self.input) end
    self._gz_doc = self.rich and self.doc or nil
    self.rich_input, self.input = nil, nil
    self:init()
    self._gz_doc = nil
    for k, v in pairs(keep) do self[k] = v end
    if text and self.input and self.input.setText then
        self.input:setText(text, true)
        self.input.is_text_edited = edited
    end
    self:drawChrome()
    if self.vk then UIManager:nextTick(function() if self.input then self:keyboardBack() end end) end
end
require("gzreader_rotation").follow(Editor, Editor.gzRelayout)

--- Draw: on touch Kindles, when the caller allows it (a new note, or one
--- already in Memos: its drawing, or a first one).
function Editor:canDraw()
    return self.touch and self.can_draw == true
end

--- The Draw chip: Draw, Drawing, or Drawings (n).
function Editor:drawingLabel()
    local n = self:drawingCount()
    if n == 0 then return "\u{270E} " .. _("Draw") end
    if n == 1 then return "\u{270E} " .. _("Drawing") end
    return "\u{270E} " .. T(_("Drawings (%1)"), n)
end

--- The note has drawings (drawn here, or its own from Memos, not taken off): how many.
function Editor:drawingCount()
    if not self.pages then return #(self.drawing_atts or {}) end
    local n = 0
    for _i, p in ipairs(self.pages) do if not p.removed then n = n + 1 end end
    return n
end
function Editor:hasDrawing() return self:drawingCount() > 0 end

--- What Save sends about the drawings: { att, path, filename } for each
--- drawn or edited, { att, removed = true } for each taken off.
function Editor:drawingChanges()
    local out = {}
    for _i, p in ipairs(self.pages or {}) do
        if p.removed and p.att then out[#out + 1] = { att = p.att, removed = true }
        elseif p.changed and p.path then out[#out + 1] = { att = p.att, path = p.path, filename = p.filename } end
    end
    -- the pages' order (Memos lists a note's attachments newest first: put back in this order;
    -- pages only moved: their order alone)
    if #out > 0 or self.pages_reordered then
        out.order = {}
        for _i, p in ipairs(self.pages or {}) do
            local f = p.filename or (p.att and p.att.filename)
            if not p.removed and f then out.order[#out.order + 1] = f end
        end
    end
    return out
end

--- The note's name: its first line of words, without Markdown's marks (nil when it has none yet).
function Editor:heading()
    for line in (self:text() or ""):gmatch("[^\n]+") do
        local t = line:gsub("^%s*#+%s*", ""):gsub("^%s*[-*]%s+%[.%]%s*", ""):gsub("^%s*[-*>]%s+", ""):gsub("[*_`]", "")
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= "" and t ~= "&nbsp;" then return #t > 48 and (t:sub(1, 48):gsub("[\128-\191]*$", "") .. "…") or t end
    end
end

--- Opens the drawing screen (the note's drawings, or a new page); the
--- keyboard goes away meanwhile and comes back after. `page`: the page to show first.
function Editor:openDrawing(page)
    if self.input and self.input.onCloseKeyboard then pcall(self.input.onCloseKeyboard, self.input) end
    local function back()
        self.drawing_closed_at = Editor.now()
        self:redraw()
        self:keyboardSoon()
    end
    local DrawScreen = require("gzreader_drawscreen")
    if not self.pages then
        -- the note's own drawings, from the copies the Notes tab keeps
        local Memos = require("gzreader_memos")
        local pages = {}
        for _i, att in ipairs(self.drawing_atts or {}) do
            local scene, err = require("gzreader_drawing").readFile(Memos.filePath(att))
            if not scene then
                Log.warn("notes: drawing not opened:", tostring(err))
                back()
                return UIManager:show(require("ui/widget/infomessage"):new{ timeout = 4,
                    text = err == "no-chunk" and _("This picture isn't a drawing that can be edited.")
                        or _("The drawing isn't on the Kindle yet. Open the note on Wi‑Fi first.") })
            end
            pages[#pages + 1] = { att = att, filename = att.filename }
        end
        self.pages = pages
    end
    -- (a PDF's pages to mark up: after the note's own drawings, shown first; once)
    local list, extra = self.pages, self.extra_pages
    self.extra_pages = nil
    if extra and #extra > 0 then
        list = {}
        for _i, p in ipairs(self.pages) do list[#list + 1] = p end
        page = page or (#list + 1)
        for _i, p in ipairs(extra) do list[#list + 1] = p end
    end
    DrawScreen.show{
        pages = list,
        choose_paper = true, -- (a new drawing: which paper first)
        start = page,
        title = self:heading(),
        -- (a new drawing: named and tagged from the drawing screen's top bar, as the Kindle Scribe's notebooks)
        meta = self.popup_only and { title = self.draw_title or "", tags = self.draw_tags or {}, offered = self.tags } or nil,
        immich = self.immich,
        on_done = function(res)
            if res.reordered then self.pages_reordered = true end
            res.reordered = nil
            local title, tags = res.title, res.tags
            res.title, res.tags = nil, nil
            self.draw_title, self.draw_tags = title, tags
            self.pages = res
            if self.popup_only then return self:newDrawingDone(title, tags) end
            back()
        end,
        on_cancel = function()
            if #self.pages == 0 and #(self.drawing_atts or {}) == 0 then self.pages = nil end
            -- (a new drawing left at once: nothing to save, the Notes tab again)
            if self.popup_only and not self:hasDrawing() then return UIManager:close(self, "full") end
            -- (a drawing note left without keeping anything: the Notes tab again, the note as it was)
            if self.drawing_note then self:dropDrawing(); return UIManager:close(self, "full") end
            if self.popup_only then return self:newDrawingDone() end
            -- (Mark up left at once: the note as it was, not its editor)
            if extra and not self:changed() then return UIManager:close(self, "full") end
            back()
        end,
    }
end

--- The drawings' new files, gone (a note discarded).
function Editor:dropDrawing()
    for _i, p in ipairs(self.pages or {}) do
        if p.path and p.changed then os.remove(p.path) end
    end
    self.pages = nil
    for _i, f in ipairs(self.photos or {}) do os.remove(f.path) end
    self.photos = nil
    -- photos sent when they were put in the text, and the edit left: deleted in Memos again
    local gone = {}
    for _i, a in ipairs(self.sent or {}) do gone[#gone + 1] = a.name end
    for _i, n in ipairs(self.unsent or {}) do gone[#gone + 1] = n end
    if #gone > 0 and self.immich then require("gzreader_notes").dropAttachments(self.immich, nil, gone) end
    self.sent, self.unsent, self.dropped = nil, nil, nil
end

--- The space chip's text: the note's space, or "No space".
function Editor:spaceLabel()
    if not self.space then return _("No space") end
    return (self.space_title and self.space_title(self.space)) or self.space:match("^spaces/(.+)$") or self.space
end

--- Choose the note's space (Alt+A, a tap): No space, or one of yours.
--- (Touch: the on-screen keyboard steps aside while the list is open, or it
--- would hide the list's last rows; it comes back after.)
function Editor:pickSpace()
    local dialog
    local kb = self.touch and self.input
    if kb then kb:onCloseKeyboard() end
    local function back() if kb then kb:onShowKeyboard() end end
    local function row(name, text)
        return { { text = text .. (self.space == name and "  \u{2713}" or ""), align = "left", callback = function()
            UIManager:close(dialog)
            self.space = name
            self.visibility = NoteEditor.visibilityAfterMove(self.visibility, name)
            self:redraw()
            back()
        end } }
    end
    local rows = { row(nil, _("No space")) }
    local listed = false
    for _i, sp in ipairs(self.spaces or {}) do
        rows[#rows + 1] = row(sp.name, sp.title)
        if sp.name == self.space then listed = true end
    end
    if self.space and not listed then rows[#rows + 1] = row(self.space, self:spaceLabel()) end
    dialog = ButtonDialog:new{ title = _("Space"), buttons = rows, tap_close_callback = back }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

function Editor:save()
    local text = self:text():gsub("%s+$", "")
    local has_photos = #(self.photos or {}) > 0 or #(self.sent or {}) > 0 -- (a note can be just photos from Immich, too)
    if text == "" and not self:hasDrawing() then
        if not has_photos then
            UIManager:show(require("ui/widget/infomessage"):new{ text = _("The note is empty."), timeout = 2 })
            return
        end
    end
    return self:saveText(text)
end

--- A new drawing (the Notes tab's Draw) after Done: the New drawing window
--- (a title and tags, then Save), not the note's page; nothing drawn: closed.
function Editor:newDrawingDone(title, tags)
    local NewDrawing = require("gzreader_newdrawing")
    if not self:hasDrawing() and not self.drawing_note then return UIManager:close(self, "full") end
    if title and self.drawing_note then
        -- a drawing note opened on its drawing: saved when something changed (a page, its name, its tags)
        local text = NewDrawing.content(title, tags)
        local changes = self:drawingChanges()
        UIManager:setDirty("all", "full")
        if text == (self.memo and self.memo.content or "") and #changes == 0 and not changes.order then
            return UIManager:close(self, "full")
        end
        Log.info("notes: a drawing note saved from the drawing screen")
        return self:saveText(text)
    end
    if title then
        -- Done on the drawing screen, its name and tags given there: saved at once (no window after)
        Log.info("notes: a new drawing saved from the drawing screen,", self:drawingCount(), "page(s),", #(tags or {}), "tag(s)")
        UIManager:setDirty("all", "full")
        return self:saveText(NewDrawing.content(title, tags))
    end
    -- (what's under: the Notes tab, painted again where the drawing screen was)
    UIManager:setDirty("all", "full")
    return NewDrawing.show{
        tags = self.tags,
        on_save = function(text)
            Log.info("notes: a new drawing saved from its window,", self:drawingCount(), "page(s)")
            self:saveText(text)
        end,
        on_back = function()
            local n = 0
            for _i, p in ipairs(self.pages or {}) do if not p.removed then n = n + 1 end end
            self:openDrawing(math.max(1, n))
        end,
    }
end

--- The editor out of sight: a new drawing's (only its drawing screen and
--- the New drawing window show; the Notes tab stays under them).
function Editor:paintTo(bb, x, y)
    if self.popup_only then return end
    return InputContainer.paintTo(self, bb, x, y)
end

function Editor:handleEvent(ev)
    -- (out of sight: nothing reaches it, nor what's under it)
    if self.popup_only then return ev.handler == "onGesture" or nil end
    return InputContainer.handleEvent(self, ev)
end

--- Saves the note as `text` with its drawings (Save, and the New drawing window's Save).
function Editor:saveText(text)
    self.saved = true
    UIManager:close(self, "full")
    if self.on_save then
        local drawings = self:drawingChanges()
        self.on_save(text, self.visibility, self.visibility ~= self.original_vis, self.space, self.space ~= self.original_space,
            (#drawings > 0 or drawings.order) and drawings or nil, #(self.photos or {}) > 0 and self.photos or nil, self:photoChanges())
    end
end

--- Back (from the text box or the toolbar).
function Editor:onCloseDialog()
    if not self:changed() then UIManager:close(self, "full"); return true end
    local dialog
    dialog = ButtonDialog:new{ title = _("Save this note?"), buttons = {
        { { text = _("Save"), align = "left", callback = function() UIManager:close(dialog); self:save() end } },
        { { text = _("Discard"), align = "left", callback = function()
            UIManager:close(dialog); self:dropDrawing(); UIManager:close(self, "full")
        end } },
        { { text = _("Keep writing"), align = "left", callback = function() UIManager:close(dialog) end } },
    } }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    self:keyboardAside(dialog)
    UIManager:show(dialog)
    return true
end

--- opts: memo (nil for a new note), tags ({ {tag=, count=} }), spaces
--- ({ { name, title } }: your Memos spaces, or nil), space (a new note's:
--- the one the board shows), space_title(name),
--- can_draw (drawings: touch Kindles), drawing_atts (the note's drawings
--- in Memos), extra_pages (new pages ready to draw on, after them: a PDF's
--- pages to mark up), open_drawing (open them, or a new page, at once),
--- immich (the plugin, when a way to Immich is set up: the Photos chip),
--- on_save(text, visibility, vis_changed, space, space_changed, drawings, photos):
--- photos = { { path, filename, type } } picked from Immich (to go with the note), or nil;
--- drawings = { { att, path, filename } (drawn or edited: waiting to be
--- sent), { att, removed = true } } or nil when they're as they were.
function NoteEditor.show(opts)
    local atts = opts.drawing_atts or (opts.drawing_att and { opts.drawing_att }) or {}
    local e = Editor:new{ memo = opts.memo, tags = opts.tags, on_save = opts.on_save,
        spaces = opts.spaces, space = opts.space, space_title = opts.space_title, can_draw = opts.can_draw,
        immich = opts.immich, photo_atts = opts.photo_atts, -- (the Photos chip; the note's photos)
        drawing_atts = atts, extra_pages = opts.extra_pages }
    -- (Draw, Edit on drawings: the drawing screen goes up with the editor, so
    -- only it is drawn; the text page shows when Done or Cancel goes back to it)
    e.drawing_first = opts.open_drawing and e:canDraw() or nil
    -- a new drawing: Done opens the New drawing window, the note's page never shows
    if opts.new_drawing and e.drawing_first then e.popup_only, e.covers_fullscreen = true, false end
    if opts.drawing_note and opts.memo and e.drawing_first then
        e.popup_only, e.covers_fullscreen, e.drawing_note = true, false, true
        e.draw_title, e.draw_tags = require("gzreader_newdrawing").parse(opts.memo.content)
    end
    UIManager:show(e, "full")
    if e.drawing_first then e:openDrawing() end
    return e
end

NoteEditor.Editor = Editor

--- The same editor as a window over the screen (the quick panel's Quick
--- note): the book or Home stays visible around it. Same opts as show.
function NoteEditor.showFloating(opts)
    local o = { floating = true, covers_fullscreen = false }
    for k, v in pairs(opts) do o[k] = v end
    local e = Editor:new(o)
    UIManager:show(e, function() return "ui", e:area() end)
    return e
end

return NoteEditor
