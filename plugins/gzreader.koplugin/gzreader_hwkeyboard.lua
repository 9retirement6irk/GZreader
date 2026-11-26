--[[--
Handwriting on the on-screen keyboard: the ✍ key (in the 🌐 key's place, or
in its hold menu when you use more than one keyboard layout) swaps the keys
for a writing pad. Write a word or a few with the pen (or a finger on a
Kindle without one); a moment after you lift it, the writing is read and
typed into the box, as if you'd typed it. The pad's own row has ⌨ (the keys
again), space, ⌫ (hold: the whole word) and Enter.

The writing is read the way Settings → Notes → Handwriting to text says: on
the Kindle (Ink Away's reader: printed English writing), or by Claude / an
OpenAI-style service with your key. Only the pad's writing is sent, as a
black-on-white picture.

Settings → Notes → Handwriting to text → "Handwriting on the keyboard" (on by
default, touch Kindles). On a Kindle with a pen, fingers don't write (a hand
resting on the screen leaves no marks); the pen's other end clears the pad.

How: GZreader wraps KOReader's VirtualKeyboard.addKeys (the 🌐 key becomes ✍,
or gets ✍ in its hold menu; with the pad on, the keys are replaced by the pad
at the same height), and while the pad shows, the touches that begin in its
writing area are taken from KOReader's gesture detector (as the drawing
screen does) and never reach the keys.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Log = require("gzreader_log")

local HwKb = {
    SETTING = "gzreader_hw_keyboard",
    KEY = "✍",
    PAUSE = 1.0,       -- (s) the pen lifted this long: what's written is read
    INK = 2,           -- (px, scaled) the ink's radius on the pad
    MIN_STEP = 1,      -- (px) points closer than this to the last aren't kept
    TOOL_PEN = 1,
    TOOL_ERASER = 2,
    active = nil,      -- the pad showing (one at a time)
}

local function S(px)
    local ok, v = pcall(function() return require("device").screen:scaleBySize(px) end)
    return ok and type(v) == "number" and v or px
end

--- On (the default) unless turned off; touch Kindles only.
function HwKb.enabled(settings, device)
    settings = settings or G_reader_settings
    device = device or require("device")
    if not (device.isTouchDevice and device:isTouchDevice()) then return false end
    return settings:nilOrTrue(HwKb.SETTING)
end

--- A Kindle with a pen: only the pen writes.
function HwKb.penOnly(device)
    local ok, yes = pcall(function() return require("gzreader_sketch").penDevice(device or require("device")) end)
    return ok and yes == true
end

--- GZreader's plugin (for the reading settings): the book's or Home's.
function HwKb.plugin()
    local ok, p = pcall(function()
        local RUI = require("apps/reader/readerui").instance
        if RUI and RUI.gzreader then return RUI.gzreader end
        local FM = require("apps/filemanager/filemanager").instance
        return FM and FM.gzreader
    end)
    return ok and p or nil
end

---------------------------------------------------------------- what's typed (pure)

--- The text to type for `read` (what the writing was read as), after the
--- character `before` (nil at the start of the box): lines joined with
--- spaces, a space put in front when it follows a word. nil: nothing to type.
function HwKb.typed(read, before)
    if type(read) ~= "string" then return nil end
    local text = read:gsub("[\r\n]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    if before and before ~= "" and not before:match("^%s$") then
        -- (no space before punctuation that ends a word)
        if not text:match("^[%.,;:!%?%)]") then text = " " .. text end
    end
    return text
end

--- The character before the cursor in an InputText, or nil.
function HwKb.before(inputbox)
    local list, pos = inputbox and inputbox.charlist, inputbox and inputbox.charpos
    if type(list) ~= "table" or type(pos) ~= "number" or pos <= 1 then return nil end
    return list[pos - 1]
end

---------------------------------------------------------------- strokes (pure)

--- A stroke recorder: contacts in, strokes out. `area` = { x, y, w, h }
--- (screen pixels) where writing counts; `pen_only`: fingers don't write.
--- feed(slots) takes one input frame ({ slot, id (-1 lifted), x, y, tool })
--- and returns { new = { {x1, y1, x2, y2}, … } (ink to show), clear = true
--- (the pen's other end), lifted = true (a stroke ended) }.
function HwKb.recorder(area, pen_only)
    local r = { area = area, pen_only = pen_only, strokes = {}, live = {} }
    local function inside(x, y)
        local a = r.area
        return x >= a.x and x < a.x + a.w and y >= a.y and y < a.y + a.h
    end
    function r:feed(slots)
        local out = { new = {} }
        for _i, s in ipairs(slots) do
            local down = s.id ~= nil and s.id ~= -1 and s.x and s.y
            local cur = self.live[s.slot]
            if down then
                if s.tool == HwKb.TOOL_ERASER then
                    out.clear = true
                elseif not cur then
                    local writes = (not pen_only) or s.tool == HwKb.TOOL_PEN
                    if writes and inside(s.x, s.y) then
                        local st = { { s.x - self.area.x, s.y - self.area.y } }
                        self.strokes[#self.strokes + 1] = st
                        self.live[s.slot] = st
                    end
                else
                    local last = cur[#cur]
                    local a = self.area
                    local x = math.max(0, math.min(a.w - 1, s.x - a.x))
                    local y = math.max(0, math.min(a.h - 1, s.y - a.y))
                    if math.abs(x - last[1]) >= HwKb.MIN_STEP or math.abs(y - last[2]) >= HwKb.MIN_STEP then
                        cur[#cur + 1] = { x, y }
                        out.new[#out.new + 1] = { last[1], last[2], x, y }
                    end
                end
            elseif cur then
                self.live[s.slot] = nil
                if #cur == 1 then
                    -- (a dot: shown, kept as a tiny stroke)
                    cur[2] = { cur[1][1] + 1, cur[1][2] }
                    out.new[#out.new + 1] = { cur[1][1], cur[1][2], cur[2][1], cur[2][2] }
                end
                out.lifted = true
            end
        end
        if out.clear then self.strokes, self.live = {}, {} end
        return out
    end
    function r:writing() return next(self.live) ~= nil end
    --- The finished strokes as the handwriting reader takes them (flat x, y lists), and forgets them.
    function r:take()
        local flat, keep = {}, {}
        for _i, st in ipairs(self.strokes) do
            local live = false
            for _s, l in pairs(self.live) do if l == st then live = true end end
            if live then keep[#keep + 1] = st
            else
                local f = {}
                for _j, p in ipairs(st) do f[#f + 1] = p[1]; f[#f + 1] = p[2] end
                flat[#flat + 1] = f
            end
        end
        self.strokes = keep
        return flat
    end
    return r
end

---------------------------------------------------------------- the pad

local Pad = {}
Pad.__index = Pad

--- The pad for keyboard `kb`, `w` x `h`.
function HwKb.newPad(kb, w, h)
    local self = setmetatable({ kb = kb, w = w, h = h }, Pad)
    self.row_h = math.max(S(44), math.floor(h * 0.22))
    self.area_h = h - self.row_h
    self.bb = Blitbuffer.new(w, self.area_h, Blitbuffer.TYPE_BB8)
    self.disc = require("gzreader_sketch").disc(S(HwKb.INK))
    self.reading = 0
    self:clearInk()
    return self
end

--- The writing area's place on the screen (set when painted).
function Pad:area()
    local d = self.at
    return d and { x = d.x, y = d.y, w = self.w, h = self.area_h } or nil
end

function Pad:clearInk()
    local bb = self.bb
    bb:fill(Blitbuffer.COLOR_WHITE)
    -- a writing line, a third from the bottom, and a hint while it's empty
    local y = math.floor(self.area_h * 0.72)
    bb:paintRect(S(24), y, self.w - 2 * S(24), math.max(1, S(1)), Blitbuffer.COLOR_LIGHT_GRAY)
end

function Pad:stamp(bb, ox, oy, x1, y1, x2, y2)
    local r = S(HwKb.INK)
    for _i, p in ipairs(require("gzreader_sketch").stamps(x1, y1, x2, y2, r)) do
        for dy = -r, r do
            local dx = self.disc[dy]
            bb:paintRect(ox + p[1] - dx, oy + p[2] + dy, 2 * dx + 1, 1, Blitbuffer.COLOR_BLACK)
        end
    end
end

--- Ink for new segments (pad coordinates): into the pad and on the screen at once.
function Pad:ink(segs)
    if #segs == 0 or not self.at then return end
    -- (the first ink: the hint goes)
    if self.hint_shown then self.hint_shown = false; self:repaintArea() end
    local Screen = require("device").screen
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local r = S(HwKb.INK) + 1
    for _i, s in ipairs(segs) do
        self:stamp(self.bb, 0, 0, s[1], s[2], s[3], s[4])
        self:stamp(Screen.bb, self.at.x, self.at.y, s[1], s[2], s[3], s[4])
        x0, y0 = math.min(x0, s[1] - r, s[3] - r), math.min(y0, s[2] - r, s[4] - r)
        x1, y1 = math.max(x1, s[1] + r, s[3] + r), math.max(y1, s[2] + r, s[4] + r)
    end
    x0, y0 = math.max(0, math.floor(x0)), math.max(0, math.floor(y0))
    x1, y1 = math.min(self.w, math.ceil(x1)), math.min(self.area_h, math.ceil(y1))
    if x1 > x0 and y1 > y0 then
        local Geom = require("ui/geometry")
        require("ui/uimanager"):setDirty(nil, "fast", Geom:new{ x = self.at.x + x0, y = self.at.y + y0, w = x1 - x0, h = y1 - y0 })
    end
end

function Pad:repaintArea()
    local a = self:area()
    if not a then return end
    require("device").screen.bb:blitFrom(self.bb, a.x, a.y, 0, 0, self.w, self.area_h)
    require("ui/uimanager"):setDirty(nil, "ui", require("ui/geometry"):new(a))
end

--- One input frame (from the gesture detector, already in screen pixels):
--- true when the pad took it.
function Pad:feed(slots)
    local a = self:area()
    if not a then return false end
    if not self.rec then self.rec = HwKb.recorder(a, HwKb.penOnly()) end
    self.rec.area = a
    local took = false
    for _i, s in ipairs(slots) do
        if self.rec.live[s.slot] then took = true end
        if s.id ~= nil and s.id ~= -1 and s.x and s.y and s.x >= a.x and s.x < a.x + a.w and s.y >= a.y and s.y < a.y + a.h then
            took = true
        end
    end
    if not took then return false end
    local out = self.rec:feed(slots)
    if out.clear then
        self:clearInk()
        self:repaintArea()
        return true
    end
    self:ink(out.new)
    if out.lifted or #out.new > 0 then self:soon() end
    return true
end

--- Read what's written a moment after the pen lifts (writing again puts it off).
function Pad:soon()
    local UIManager = require("ui/uimanager")
    if not self.task then
        self.task = function()
            if HwKb.active ~= self then return end
            if self.rec and self.rec:writing() then return UIManager:scheduleIn(HwKb.PAUSE, self.task) end
            self:readNow()
        end
    end
    UIManager:unschedule(self.task)
    UIManager:scheduleIn(HwKb.PAUSE, self.task)
end

function Pad:readNow()
    local flat = self.rec and self.rec:take() or {}
    if #flat == 0 then return end
    -- (the ink stays until it's read; then the pad is clean for the next words)
    self.reading = self.reading + 1
    local Hw = require("gzreader_handwriting")
    local t0 = os.clock()
    Hw.read(HwKb.plugin(), flat, function(text, why)
        self.reading = self.reading - 1
        if HwKb.active ~= self then return end
        if self.reading == 0 and not (self.rec and next(self.rec.strokes)) then
            self:clearInk()
            self:repaintArea()
        end
        local typed = HwKb.typed(text, HwKb.before(self.kb.inputbox))
        Log.info(string.format("keyboard: writing read (%d strokes, %.2f s): %s", #flat, os.clock() - t0,
            typed and (#typed .. " characters typed") or ("nothing (" .. tostring(why or "empty") .. ")")))
        if typed then
            self.kb.inputbox:addChars(typed)
        elseif why then
            require("ui/uimanager"):show(require("ui/widget/infomessage"):new{ timeout = 2,
                text = require("ffi/util").template(require("gettext")("Your writing couldn't be read (%1)."), why) })
        end
    end)
end

function Pad:close()
    local UIManager = require("ui/uimanager")
    if self.task then UIManager:unschedule(self.task) end
    if self.bb then self.bb:free(); self.bb = nil end
    if HwKb.active == self then HwKb.active = nil end
end

---------------------------------------------------------------- the pad as a widget

--- The pad's widget: the writing area (painted from the pad) over its row of keys.
function HwKb.padWidget(kb, pad)
    local _ = require("gettext")
    local Button = require("ui/widget/button")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Widget = require("ui/widget/widget")
    local Geom = require("ui/geometry")
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")

    local area = Widget:new{ dimen = Geom:new{ w = pad.w, h = pad.area_h } }
    local hint_face = Font:getFace("cfont", 16)
    function area:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        pad.at = { x = x, y = y }
        if pad.bb then bb:blitFrom(pad.bb, x, y, 0, 0, pad.w, pad.area_h) end
        if not (pad.rec and next(pad.rec.strokes)) and pad.reading == 0 then
            local hint = TextWidget:new{ text = HwKb.penOnly() and _("Write here with the pen") or _("Write here"),
                face = hint_face, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
            hint:paintTo(bb, x + S(24), y + S(12))
            hint:free()
            pad.hint_shown = true
        end
    end
    function area:getSize() return Geom:new{ w = pad.w, h = pad.area_h } end

    local gap = S(6)
    local n = 4
    local bw = math.floor((pad.w - (n + 1) * gap) / n)
    local bh = pad.row_h - 2 * gap
    local function key(text, cb, hold, w)
        return Button:new{ text = text, width = w or bw, height = bh, bordersize = S(1), radius = S(4),
            text_font_size = 20, callback = cb, hold_callback = hold, show_parent = kb }
    end
    local row = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = gap },
        key("⌨", function() HwKb.keys(kb) end), HorizontalSpan:new{ width = gap },
        key(_("space"), function() kb.inputbox:addChars(" ") end), HorizontalSpan:new{ width = gap },
        key("⌫", function() kb.inputbox:delChar() end, function() kb.inputbox:delWord(true) end), HorizontalSpan:new{ width = gap },
        key("⮠", function() kb.inputbox:addChars("\n") end),
    }
    return FrameContainer:new{
        margin = 0, padding = 0, bordersize = S(1), background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ area, FrameContainer:new{ margin = 0, bordersize = 0, padding = 0, padding_top = gap,
            padding_bottom = gap, background = Blitbuffer.COLOR_LIGHT_GRAY, row } },
    }
end

---------------------------------------------------------------- the keyboard

local function hook()
    local Device = require("device")
    local gd = Device.input and Device.input.gesture_detector
    if not gd or HwKb._gd then return end
    HwKb._gd, HwKb._own = gd, rawget(gd, "feedEvent")
    local orig = gd.feedEvent
    local wrapper
    wrapper = function(det, tevs)
        local pad = HwKb.active
        if not pad then return orig(det, tevs) end
        local slots = {}
        for _i, tev in ipairs(tevs) do
            local x, y = tev.x, tev.y
            if x and y then
                local Geom = require("ui/geometry")
                local ges = { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
                if det.adjustGesCoordinate then pcall(det.adjustGesCoordinate, det, ges) end
                x, y = ges.pos.x, ges.pos.y
            end
            slots[#slots + 1] = { slot = tev.slot, id = tev.id, x = x, y = y, tool = tev.tool }
        end
        local ok, took = pcall(pad.feed, pad, slots)
        if ok and took then return {} end
        if not ok then Log.warn("keyboard: handwriting:", tostring(took)) end
        return orig(det, tevs)
    end
    HwKb._wrapper = wrapper
    rawset(gd, "feedEvent", wrapper)
end

local function unhook()
    local gd = HwKb._gd
    if gd and rawget(gd, "feedEvent") == HwKb._wrapper then rawset(gd, "feedEvent", HwKb._own) end
    HwKb._gd, HwKb._own, HwKb._wrapper = nil, nil, nil
end

--- The pad in place of `kb`'s keys.
function HwKb.write(kb)
    kb.gz_hw = true
    G_reader_settings:saveSetting("gzreader_hw_keyboard_last", "pad")
    Log.info("keyboard: the handwriting pad")
    kb:addKeys()
    kb:_refresh(true)
end

--- The keys again.
function HwKb.keys(kb)
    kb.gz_hw = false
    G_reader_settings:delSetting("gzreader_hw_keyboard_last")
    if kb.gz_pad then kb.gz_pad:close(); kb.gz_pad = nil end
    unhook()
    kb:addKeys()
    kb:_refresh(true)
end

--- `kb`'s KEYS with the 🌐 key as ✍ (a copy), or nil when 🌐 isn't there or stays.
function HwKb.withKey(keys, layouts)
    if type(keys) ~= "table" or (tonumber(layouts) or 0) > 1 then return nil end
    for i, row in ipairs(keys) do
        for j, k in ipairs(row) do
            if type(k) == "table" and k.label == "🌐" then
                local copy = {}
                for r, rr in ipairs(keys) do copy[r] = rr end
                local nrow = {}
                for c, kk in pairs(row) do nrow[c] = kk end
                nrow[j] = { label = HwKb.KEY, width = k.width, gz_hw_key = true }
                copy[i] = nrow
                return copy
            end
        end
    end
    return nil
end

function HwKb.install()
    local ok, VirtualKeyboard = pcall(require, "ui/widget/virtualkeyboard")
    if not ok or VirtualKeyboard._gz_hw then return false end
    VirtualKeyboard._gz_hw = true
    local orig = VirtualKeyboard.addKeys
    function VirtualKeyboard:addKeys(...)
        if not HwKb.enabled() then return orig(self, ...) end
        -- (the pad was in use last time: it again)
        if self.gz_hw == nil and not self._gz_hw_seen then
            self._gz_hw_seen = true
            if G_reader_settings:readSetting("gzreader_hw_keyboard_last") == "pad" then self.gz_hw = true end
        end
        local layouts = #(G_reader_settings:readSetting("keyboard_layouts") or {})
        local keys = self.KEYS
        local swapped = HwKb.withKey(keys, layouts)
        if swapped then self.KEYS = swapped end
        local res = { pcall(orig, self, ...) }
        self.KEYS = keys
        if not res[1] then error(res[2]) end
        local kb = self
        for _r, row in ipairs(self.layout or {}) do
            for _c, key in ipairs(row) do
                if key.label == HwKb.KEY then
                    key.callback = function() HwKb.write(kb) end
                    key.hold_callback, key.swipe_callback, key.key_chars = nil, nil, nil
                elseif key.label == "🌐" and type(key.key_chars) == "table" then
                    -- (several layouts: ✍ in the 🌐 key's hold menu)
                    key.key_chars.south = HwKb.KEY
                    key.key_chars.south_func = function()
                        if key.popup then require("ui/uimanager"):close(key.popup) end
                        HwKb.write(kb)
                    end
                end
            end
        end
        if self.gz_hw then
            local frame = self[1] and self[1][1]
            local size = frame and frame.getSize and frame:getSize()
            if size then
                if self.gz_pad then self.gz_pad:close() end
                local pad = HwKb.newPad(self, size.w - 2 * S(1), size.h - 2 * S(1))
                self.gz_pad = pad
                HwKb.active = pad
                local widget = HwKb.padWidget(self, pad)
                self[1][1] = widget
                widget.dimen = widget:getSize()
                self.dimen = widget.dimen
                hook()
            end
        end
        return unpack(res, 2)
    end
    local close = VirtualKeyboard.onCloseWidget
    function VirtualKeyboard:onCloseWidget(...)
        if self.gz_pad then
            self.gz_pad:close()
            self.gz_pad = nil
            unhook()
        end
        return close(self, ...)
    end
    local show = VirtualKeyboard.onShow
    function VirtualKeyboard:onShow(...)
        -- (shown again: its pad made again, the one written on)
        if self.gz_hw and not self.gz_pad then pcall(self.addKeys, self) end
        if self.gz_pad then HwKb.active = self.gz_pad; hook() end
        return show(self, ...)
    end
    return true
end

--- Settings → Notes → Handwriting to text: its row.
function HwKb.menuItem()
    local _ = require("gettext")
    return {
        text = _("Handwriting on the keyboard (✍ key)"),
        help_text = _("The on-screen keyboard's 🌐 key becomes ✍ (with more than one keyboard layout: hold 🌐). It swaps the keys for a writing pad: write, and a moment after you lift the pen your writing is typed into the box, read the way chosen above."),
        checked_func = function() return HwKb.enabled() end,
        callback = function()
            G_reader_settings:saveSetting(HwKb.SETTING, not G_reader_settings:nilOrTrue(HwKb.SETTING))
            Log.info("keyboard: handwriting key", tostring(HwKb.enabled()))
        end,
    }
end

return HwKb
