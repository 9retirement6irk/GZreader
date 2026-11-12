--[[--
The Notes tab's full-page editor (new notes and edits). Memos notes are
Markdown; a toolbar at the bottom of the page adds it for you:

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
- Back: asks whether to save when something changed.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
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

NoteEditor.VISIBILITY = { "PRIVATE", "PROTECTED", "PUBLIC" }
-- In a space (Memos v0.31), also "only its members", second as in Memos' own menu.
NoteEditor.VISIBILITY_IN_SPACE = { "PRIVATE", "SPACE", "PROTECTED", "PUBLIC" }
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
    local margin = S(12)
    self.margin = margin
    self.inner = sw - 2 * margin
    self.title_h, self.tool_h, self.footer_h = S(44), S(40), S(30)
    local text_h = sh - self.title_h - self.tool_h - self.footer_h - S(28)
    self.touch = Touch.on() and not Touch.keys()
    -- Kindle 4: the on-screen keyboard too (the 5-way types on it); Menu goes
    -- to the toolbar (the keyboard hides) and back
    self.dpad = Touch.dpad()
    self.vk = self.touch or self.dpad
    -- (taps and keys reach the editor under the on-screen keyboard, as in KOReader's input dialogs)
    if self.vk then self.is_always_active = true end
    local function box(h)
        return makeInput(self, {
            text = self.original, width = self.inner - 2 * (S(8) + Size.border.thin), height = h, scroll = true,
            face = Font:getFace("cfont", 20), parent = self, focused = true,
            padding = S(8), margin = 0, bordersize = Size.border.thin,
            hint = _("Write a note. #words become tags."),
        })
    end
    self.input = box(text_h)
    if self.vk then
        -- touch: the toolbar under the title, the text box above the on-screen keyboard
        self.footer_h = self.dpad and S(26) or 0
        local kb = self.input.keyboard
        local kb_h = kb and kb.dimen and kb.dimen.h or math.floor(sh * 0.4)
        if self.input.free then pcall(self.input.free, self.input) end
        self.input = box(sh - self.title_h - self.tool_h - kb_h - S(24) - (self.dpad and S(26) or 0))
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
        }
    else
        column = VerticalGroup:new{ align = "center",
            self.title_slot,
            self.input,
            VerticalSpan:new{ width = S(10) },
            self.bar_slot, -- at the bottom: ▼ from the last line reaches it, ▲ goes back
            VerticalSpan:new{ width = S(8) },
            self.hint_slot,
        }
    end
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        column,
    }
    self:drawChrome()
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

function Editor:onCloseWidget()
    if self.input and self.input.onCloseKeyboard then pcall(self.input.onCloseKeyboard, self.input) end
end

function Editor:onShow()
    -- touch: the on-screen keyboard, at once
    if self.vk then UIManager:nextTick(function() if self.input then self.input:onShowKeyboard() end end) end
end

function Editor:drawChrome()
    local sw = self.dimen.w
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
                self.has_spaces and tapTarget(FrameContainer:new{ padding = S(6), radius = S(6),
                    bordersize = (self.touch or (self.dpad and self.focus_tool == #NoteEditor.TOOLS + 3)) and Size.border.thick
                        or (self.dpad and Size.border.thin) or 0,
                    TextWidget:new{ text = self:spaceLabel() .. ((self.touch or self.dpad) and "  \u{25BE}" or "  (Alt+A)"),
                        face = Font:getFace("cfont", 15), max_width = math.floor(sw * 0.3) } }, function() self:onShortcut("A") end)
                    or HorizontalSpan:new{ width = 0 },
                HorizontalSpan:new{ width = self.has_spaces and S(8) or 0 },
                tapTarget(FrameContainer:new{ padding = S(6), radius = S(6),
                    bordersize = (self.touch or (self.dpad and self.focus_tool == #NoteEditor.TOOLS + 2)) and Size.border.thick
                        or (self.dpad and Size.border.thin) or 0,
                    TextWidget:new{ text = NoteEditor.VIS_LABEL[self.visibility] .. ((self.touch or self.dpad) and "  \u{25BE}" or "  (Alt+V)"),
                        face = Font:getFace("cfont", 15) } }, function() self:onShortcut("V") end),
                HorizontalSpan:new{ width = margin } } },
    }
    local bar = HorizontalGroup:new{ align = "center" }
    local save_w = S(70)
    local tools = NoteEditor.TOOLS
    local tool_w = math.floor((self.inner - save_w - S(10)) / #tools)
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
    bar[#bar + 1] = HorizontalSpan:new{ width = S(10) }
    local save_focused = self.focus_tool == #tools + 1
    bar[#bar + 1] = tapTarget(FrameContainer:new{
        width = save_w, height = self.tool_h, padding = 0, bordersize = Size.border.thick, radius = S(6),
        background = save_focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = save_w - 4, h = self.tool_h - 4 },
            TextWidget:new{ text = _("Save"), face = Font:getFace("cfont", 18), bold = true,
                fgcolor = save_focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } },
    }, function() self:save() end)
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
    UIManager:setDirty(self, "ui")
end

function Editor:text() return self.input:getText() or "" end

function Editor:apply(new_text, cursor)
    self.input:setText(new_text, true)
    self.input.is_text_edited = true
    self.input:moveCursorToCharPos(cursor)
    UIManager:setDirty(self, "ui")
end

function Editor:useTool(i)
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
        if tag ~= "" then self:apply(NoteEditor.insertTag(self:text(), pos, tag)) end
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
        UIManager:show(d)
        d:onShowKeyboard()
    end } }
    dialog = ButtonDialog:new{ title = _("Add a tag"), buttons = rows }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
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
    if text == "" then
        UIManager:show(require("ui/widget/infomessage"):new{ text = _("The note is empty."), timeout = 2 })
        return
    end
    self.saved = true
    UIManager:close(self, "full")
    if self.on_save then
        self.on_save(text, self.visibility, self.visibility ~= self.original_vis, self.space, self.space ~= self.original_space)
    end
end

--- Back (from the text box or the toolbar).
function Editor:onCloseDialog()
    if not self:changed() then UIManager:close(self, "full"); return true end
    local dialog
    dialog = ButtonDialog:new{ title = _("Save this note?"), buttons = {
        { { text = _("Save"), align = "left", callback = function() UIManager:close(dialog); self:save() end } },
        { { text = _("Discard"), align = "left", callback = function() UIManager:close(dialog); UIManager:close(self, "full") end } },
        { { text = _("Keep writing"), align = "left", callback = function() UIManager:close(dialog) end } },
    } }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return true
end

--- opts: memo (nil for a new note), tags ({ {tag=, count=} }), spaces
--- ({ { name, title } }: your Memos spaces, or nil), space (a new note's:
--- the one the board shows), space_title(name),
--- on_save(text, visibility, vis_changed, space, space_changed).
function NoteEditor.show(opts)
    local e = Editor:new{ memo = opts.memo, tags = opts.tags, on_save = opts.on_save,
        spaces = opts.spaces, space = opts.space, space_title = opts.space_title }
    UIManager:show(e, "full")
    return e
end

NoteEditor.Editor = Editor

return NoteEditor
