--[[--
The players' buttons, as in the mockups: hardware you could press.

- Key: a chunky piano key (the walkman's) or a pill (the CD player's), lit
  from the top and standing on a darker edge; a key that's down (playing)
  sits lower, its edge hidden. The letter key in a square inside it on
  Kindles with a keyboard. Tap or the letter presses it.
- Dial: a ridged knob with a pointer for a value (the volume): a tap on
  its left half turns it down, on the right half up.
- spine(): a CD case's spine, its text running down it.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local Skeuo = {}

local function tapEvents(self)
    local range = function() return self.dimen end
    self.ges_events = { TapSkeuo = { GestureRange:new{ ges = "tap", range = range } } }
end

---------------------------------------------------------------- a key

local Key = InputContainer:extend{ w = 100, h = 48, label = "", icon = nil, icon_after = false, letter = nil, down = false, shape = "key", callback = nil, font_size = 15,
    focused = false } -- (focused: the 5-way is on it, a black ring round it)
Skeuo.Key = Key

function Key:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    tapEvents(self)
end

function Key:getSize() return Geom:new{ w = self.w, h = self.h } end

function Key:onTapSkeuo()
    if self.callback then self.callback() end
    return true
end

--- A rounded shape filled row by row: shade(t) for t from 0 (top) to 1.
local function fillRounded(bb, x, y, w, h, r, shade)
    for row = 0, h - 1 do
        local inset = 0
        local dy = row < r and (r - row - 0.5) or (row > h - 1 - r and (row - (h - 1 - r) - 0.5) or nil)
        if dy then inset = math.floor(r - math.sqrt(math.max(0, r * r - dy * dy)) + 0.5) end
        if w - 2 * inset > 0 then
            bb:paintRect(x + inset, y + row, w - 2 * inset, 1, Blitbuffer.gray(shade(row / math.max(1, h - 1))))
        end
    end
end

--- The transport symbols, drawn (fonts don't all have them).
local function tri(bb, x, y, h, dir)
    for i = 0, h - 1 do
        local half = math.abs(i - (h - 1) / 2)
        local w = math.floor(((h - 1) / 2 - half) * 1.6) + 1
        bb:paintRect(dir > 0 and x or (x - w + 1), y + i, w, 1, Blitbuffer.COLOR_BLACK)
    end
end
local function symbol(bb, name, cx, cy, size)
    local h = size
    local y = cy - math.floor(h / 2)
    local tw = math.floor((h - 1) / 2 * 1.6) + 1
    local bar = math.max(2, math.floor(h / 5))
    if name == "play" then tri(bb, cx - math.floor(tw / 2), y, h, 1)
    elseif name == "pause" then
        bb:paintRect(cx - bar - math.max(1, math.floor(bar / 2)), y, bar, h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(cx + math.max(1, math.floor(bar / 2)), y, bar, h, Blitbuffer.COLOR_BLACK)
    elseif name == "next" then
        tri(bb, cx - tw + math.floor(tw / 4), y, h, 1)
        bb:paintRect(cx + math.floor(tw / 4) + 1, y, bar, h, Blitbuffer.COLOR_BLACK)
    elseif name == "prev" then
        tri(bb, cx + tw - math.floor(tw / 4), y, h, -1)
        bb:paintRect(cx - math.floor(tw / 4) - bar - 1, y, bar, h, Blitbuffer.COLOR_BLACK)
    elseif name == "ffwd" then
        tri(bb, cx - tw, y, h, 1); tri(bb, cx, y, h, 1)
    elseif name == "rew" then
        tri(bb, cx + tw, y, h, -1); tri(bb, cx, y, h, -1)
    elseif name == "stop" then
        bb:paintRect(cx - math.floor(h * 0.4), y + math.floor(h * 0.1), math.floor(h * 0.8), math.floor(h * 0.8), Blitbuffer.COLOR_BLACK)
    end
    return tw * ((name == "ffwd" or name == "rew") and 2 or 1)
end
Skeuo.symbol = symbol

function Key:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local depth = math.max(3, S(5))
    local w, h = self.w, self.h - depth
    local r = self.shape == "pill" and math.floor(h / 2) or math.max(3, S(6))
    local by = self.down and (y + depth - math.max(1, S(1))) or y
    -- the edge it stands on (hidden when it's down)
    if not self.down then
        fillRounded(bb, x, y + depth, w, h, r, function() return 0.62 end)
    end
    -- the top: light above, a little darker below (pressed: darker all over)
    if self.down then
        fillRounded(bb, x, by, w, h, r, function(t) return 0.30 + 0.08 * t end)
    else
        fillRounded(bb, x, by, w, h, r, function(t) return 0.03 + 0.30 * t * t end)
    end
    bb:paintBorder(x, by, w, h, math.max(1, S(2)), Blitbuffer.gray(0.85), r)
    if self.focused then
        local o = math.max(2, S(3))
        bb:paintBorder(x - o, by - o, w + 2 * o, h + 2 * o + (self.down and 0 or depth), math.max(2, S(3)), Blitbuffer.COLOR_BLACK, r + o)
    end
    -- the letter, then the label (a symbol and/or text)
    local lx, side = x, 0
    if self.letter then
        local Menu = require("ui/widget/menu")
        side = math.min(S(22), h - S(10))
        local ok, icon = pcall(Menu.getItemShortCutIcon, nil, Geom:new{ w = side, h = side }, self.letter, "square")
        if ok and icon then
            lx = x + (self.shape == "pill" and math.floor(r * 0.55) or S(6))
            bb:paintRect(lx, by + math.floor((h - side) / 2), side, side, Blitbuffer.COLOR_WHITE)
            icon:paintTo(bb, lx, by + math.floor((h - side) / 2))
            if icon.free then icon:free() end
            lx = lx + side
        else
            side = 0
        end
    end
    local pad = self.shape == "pill" and math.floor(r * 0.55) or S(6)
    local left = side > 0 and lx or x
    local room = x + w - pad - left
    local sym_h = math.floor(h * 0.34)
    local sym_w = 0
    if self.icon then sym_w = math.floor((sym_h - 1) / 2 * 1.6 + 1) * ((self.icon == "ffwd" or self.icon == "rew") and 2 or 1) end
    local t
    if self.label and self.label ~= "" then
        t = TextWidget:new{ text = self.label, face = Font:getFace("cfont", self.font_size), bold = true,
            max_width = room - (sym_w > 0 and sym_w + S(6) or 0) }
    end
    local tw = t and t:getSize().w or 0
    local total = sym_w + (sym_w > 0 and t and S(6) or 0) + tw
    local cx0 = left + math.floor((room - total) / 2)
    local cy = by + math.floor(h / 2)
    local before = self.icon_after ~= true
    if self.icon and before then symbol(bb, self.icon, cx0 + math.floor(sym_w / 2), cy, sym_h) end
    if t then
        local tx = cx0 + (before and sym_w > 0 and (sym_w + S(6)) or 0)
        t:paintTo(bb, tx, cy - math.floor(t:getSize().h / 2))
        t:free()
    end
    if self.icon and not before then symbol(bb, self.icon, cx0 + tw + S(6) + math.floor(sym_w / 2), cy, sym_h) end
end

---------------------------------------------------------------- a dial

local Dial = InputContainer:extend{ w = 160, h = 56, value = 0, max = 10, label = "", value_text = nil,
    minus = nil, plus = nil, letters = nil, focused = nil } -- (focused: "minus" or "plus", ringed)
Skeuo.Dial = Dial

function Dial:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    tapEvents(self)
end

function Dial:getSize() return Geom:new{ w = self.w, h = self.h } end

function Dial:onTapSkeuo(_arg, ges)
    local left = ges and ges.pos and self.dimen and ges.pos.x < self.dimen.x + math.floor(self.dimen.w / 2)
    if left and self.minus then self.minus() elseif not left and self.plus then self.plus() end
    return true
end

function Dial:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local w, h = self.w, self.h
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.gray(0.06), S(6))
    bb:paintBorder(x, y, w, h, math.max(1, S(2)), Blitbuffer.gray(0.8), S(6))
    -- the knob: ridges round its edge, a pointer
    local r = math.floor(h * 0.36)
    local cx, cy = x + S(10) + r, y + math.floor(h / 2)
    bb:paintCircle(cx, cy + S(2), r, Blitbuffer.gray(0.55))
    bb:paintCircle(cx, cy, r, Blitbuffer.gray(0.35))
    for k = 0, 23 do
        local a = k * math.pi / 12
        local px, py = cx + math.floor(math.cos(a) * (r - S(2))), cy + math.floor(math.sin(a) * (r - S(2)))
        bb:paintRect(px - 1, py - 1, math.max(2, S(2)), math.max(2, S(2)), Blitbuffer.gray(k % 2 == 0 and 0.75 or 0.1))
    end
    bb:paintCircle(cx, cy, math.floor(r * 0.62), Blitbuffer.gray(0.16))
    local f = self.max > 0 and math.max(0, math.min(1, self.value / self.max)) or 0
    local a = math.rad(-225 + 270 * f)
    for i = 0, math.floor(r * 0.85) do
        bb:paintRect(cx + math.floor(math.cos(a) * i) - 1, cy + math.floor(math.sin(a) * i) - 1, math.max(2, S(3)), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    end
    -- its value and what it is; − and + (or their letters) at the ends
    local tx = cx + r + S(10)
    local v = TextWidget:new{ text = self.value_text or tostring(self.value), face = Font:getFace("cfont", 16), bold = true }
    local l = TextWidget:new{ text = self.label or "", face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.gray(0.75) }
    local vh, lh = v:getSize().h, l:getSize().h
    local top = y + math.floor((h - vh - lh) / 2)
    v:paintTo(bb, tx, top)
    l:paintTo(bb, tx, top + vh)
    v:free(); l:free()
    -- − and + (with their letters), each in its own place so the 5-way's ring can sit round one
    local function mark(text, focused)
        return TextWidget:new{ text = text, face = Font:getFace("cfont", focused and 16 or 13), bold = true,
            fgcolor = focused and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.7) }
    end
    local mm = mark(self.letters and (self.letters[1] .. " \u{2212}") or "\u{2212}", self.focused == "minus")
    local mp = mark(self.letters and (self.letters[2] .. " +") or "+", self.focused == "plus")
    local pad = S(8)
    local px = x + w - mp:getSize().w - S(10)
    local mx = px - S(18) - mm:getSize().w
    for _i, it in ipairs({ { mm, mx, self.focused == "minus" }, { mp, px, self.focused == "plus" } }) do
        local tw, th = it[1]:getSize().w, it[1]:getSize().h
        local ty = y + math.floor((h - th) / 2)
        it[1]:paintTo(bb, it[2], ty)
        if it[3] then
            bb:paintBorder(it[2] - pad, ty - S(3), tw + 2 * pad, th + S(6), math.max(2, S(3)), Blitbuffer.COLOR_BLACK, S(4))
        end
        it[1]:free()
    end
end

---------------------------------------------------------------- a CD case's spine

local Spine = WidgetContainer:extend{ w = 24, h = 100, text = "" }
Skeuo.Spine = Spine
function Spine:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spine:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    bb:paintRect(x, y, self.w, self.h, Blitbuffer.gray(0.78))
    local lying = Blitbuffer.new(self.h, self.w, Blitbuffer.TYPE_BB8)
    lying:fill(Blitbuffer.gray(0.78))
    local t = TextWidget:new{ text = tostring(self.text):upper(), face = Font:getFace("cfont", 10), bold = true,
        fgcolor = Blitbuffer.COLOR_WHITE, max_width = self.h - S(12) }
    local ts = t:getSize()
    t:paintTo(lying, math.floor((self.h - ts.w) / 2), math.floor((self.w - ts.h) / 2))
    t:free()
    local stood = lying:rotatedCopy(self.down_up and 90 or 270)
    lying:free()
    bb:blitFrom(stood, x, y, 0, 0, self.w, self.h)
    stood:free()
end

return Skeuo
