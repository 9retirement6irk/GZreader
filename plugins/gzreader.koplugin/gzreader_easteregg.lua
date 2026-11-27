--[[--
Settings' easter egg, as Android's: tap GZreader's version in Settings →
About seven times and a little animation plays: an open book whose pages
turn by themselves, each turn writing the next letter of "GZreader", until
the whole name is on the page.

- It plays through three times, then rests on its last page.
- A tap anywhere, Back, or the 5-way's Press closes it. It never touches
  anything else, and keeps nothing.

Pure part (easteregg_test.lua): Egg.tap (the version's taps), Egg.frame
(what a frame shows), Egg.wait (how long it stays), Egg.FRAMES.
]]

local Egg = {}

Egg.TAPS = 7 -- taps on the version that open it
Egg.WINDOW = 4 -- seconds: a pause longer than this starts the count again
Egg.HINT_FROM = 4 -- from this tap on, "N more" is said (as Android does)
Egg.WORD = { "G", "Z", "r", "e", "a", "d", "e", "r" }
Egg.LEAF = 3 -- a turning page's frames: over the right page, upright at the spine, over the left page
Egg.FRAMES = #Egg.WORD * (Egg.LEAF + 1) + 1 -- each letter: the page turns, then the letter; and the last page
Egg.LOOPS = 3 -- times it plays before resting on the last page

-- ------------------------------------------------------------- the taps

--- A tap on the version at time `now`: { count, open (true on the 7th),
--- left (taps still to go, from HINT_FROM on; else nil) }. `state` is kept between taps.
function Egg.tap(state, now)
    if state.at and now - state.at > Egg.WINDOW then state.count = 0 end
    state.at = now
    state.count = (state.count or 0) + 1
    if state.count >= Egg.TAPS then
        state.count = 0
        return { count = Egg.TAPS, open = true }
    end
    local left = Egg.TAPS - state.count
    return { count = state.count, left = state.count >= Egg.HINT_FROM and left or nil }
end

-- ------------------------------------------------------------ the frames

--- What frame `n` (1 to Egg.FRAMES) shows:
--- { leaf (0: no page in the air; 1, 2, 3: where the turning page is),
---   letter (the letter on the right page, nil while a page turns or at the end),
---   written (the letters already on the left page),
---   finale (true: the whole name across the book) }. Pure.
function Egg.frame(n)
    n = math.max(1, math.min(Egg.FRAMES, n))
    if n == Egg.FRAMES then
        return { leaf = 0, finale = true, written = table.concat(Egg.WORD) }
    end
    local per = Egg.LEAF + 1
    local i = math.floor((n - 1) / per) + 1 -- which letter
    local step = (n - 1) % per + 1          -- 1..LEAF: the page turns; LEAF + 1: the letter
    local written = table.concat(Egg.WORD, "", 1, i - 1)
    if step <= Egg.LEAF then return { leaf = step, written = written, index = i } end
    return { leaf = 0, letter = Egg.WORD[i], written = written, index = i }
end

--- How long frame `n` stays, in seconds: a turning page moves on quickly,
--- a letter is left to be read, the last page longest.
function Egg.wait(n)
    local f = Egg.frame(n)
    if f.finale then return 5 end
    if f.leaf > 0 then return 0.3 end
    return 0.9
end

-- --------------------------------------------------------------- screen

--- Shows the animation (full screen). Returns the widget.
function Egg.show()
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local RenderText = require("ui/rendertext")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = Device.screen
    local function S(n) return Screen:scaleBySize(n) end

    local Show = InputContainer:extend{ name = "gz_egg", covers_fullscreen = true }
    function Show:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        -- the open book, in the middle: two pages and the spine between
        local bw = math.min(sw - 2 * S(36), math.floor((sh - S(220)) / 0.62))
        bw = bw - bw % 2
        local bh = math.floor(bw * 0.62)
        self.book = Geom:new{ x = math.floor((sw - bw) / 2), y = math.floor((sh - bh) / 2), w = bw, h = bh }
        -- (what a frame can change: the book and the page lifted a little above it)
        self.area = Geom:new{ x = self.book.x - S(14), y = self.book.y - S(22), w = bw + 2 * S(14), h = bh + S(44) }
        self.n, self.loop = 1, 1
        self.ges_events = { TapShow = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
        local back = Device.input and Device.input.group and Device.input.group.Back or "Back"
        self.key_events = { Close = { { back } }, ClosePress = { { "Press" } } }
        self.tick = function() self:advance() end
        UIManager:scheduleIn(Egg.wait(1), self.tick)
        require("gzreader_log").info("easter egg: the animation opened")
    end
    function Show:advance()
        if self.closed then return end
        if self.n >= Egg.FRAMES then
            if self.loop >= Egg.LOOPS then return end -- (rests on the last page)
            self.loop, self.n = self.loop + 1, 1
        else
            self.n = self.n + 1
        end
        local f = Egg.frame(self.n)
        -- a page in the air: the quickest refresh; a letter landed, or the last page: a clean one
        local mode = f.leaf > 0 and "fast" or "ui"
        UIManager:setDirty(self, function() return mode, self.area end)
        UIManager:scheduleIn(Egg.wait(self.n), self.tick)
    end
    local function centred(bb, face, text, cx, cy, bold, color)
        local m = RenderText:sizeUtf8Text(0, Screen:getWidth(), face, text, true, bold)
        local fh, asc = face.ftsize:getHeightAndAscender()
        RenderText:renderUtf8Text(bb, cx - math.floor(m.x / 2), cy - math.floor(fh / 2) + math.floor(asc), face, text, true, bold,
            color or Blitbuffer.COLOR_BLACK)
    end
    function Show:paintTo(bb, x, y)
        local sw, sh = self.dimen.w, self.dimen.h
        local B = self.book
        local f = Egg.frame(self.n)
        bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)
        local small = Font:getFace("cfont", 18)
        centred(bb, small, Device:isTouchDevice() and _("Tap to close") or _("Back closes"), x + math.floor(sw / 2), y + sh - S(40), false,
            Blitbuffer.COLOR_DARK_GRAY)
        local bx, by, half = x + B.x, y + B.y, B.w / 2
        local line = math.max(2, S(2))
        -- the cover behind, the block of pages (their edges below), the two open pages, the spine
        bb:paintRect(bx - S(8), by - S(4), B.w + 2 * S(8), B.h + S(16), Blitbuffer.COLOR_BLACK)
        for k = 2, 0, -1 do
            bb:paintRect(bx - S(2) * k, by + B.h + S(3) * k - S(1), B.w + 2 * S(2) * k, S(3), Blitbuffer.COLOR_WHITE)
            bb:paintRect(bx - S(2) * k, by + B.h + S(3) * k + S(2), B.w + 2 * S(2) * k, 1, Blitbuffer.COLOR_DARK_GRAY)
        end
        bb:paintRect(bx, by, B.w, B.h, Blitbuffer.COLOR_WHITE)
        bb:paintRect(bx + half - math.floor(line / 2), by, line, B.h, Blitbuffer.COLOR_BLACK)
        bb:paintRect(bx + half - S(6), by, S(5), B.h, Blitbuffer.COLOR_LIGHT_GRAY)
        bb:paintRect(bx + half + line, by, S(4), B.h, Blitbuffer.COLOR_LIGHT_GRAY)
        local lcx, rcx, cy = bx + math.floor(half / 2), bx + math.floor(half * 1.5), by + math.floor(B.h / 2)
        local px = function(v) return math.max(12, math.floor(v / Screen:scaleBySize(1))) end
        if f.finale then
            -- the whole name across the book, and a line under it
            local big = Font:getFace("smalltfont", px(B.h * 0.2))
            centred(bb, big, "GZ", lcx, cy - S(6), true)
            centred(bb, big, "reader", rcx, cy - S(6), true)
            centred(bb, small, _("Thanks for reading."), rcx, by + B.h - S(34), false, Blitbuffer.COLOR_DARK_GRAY)
            return
        end
        -- the left page: what's written so far; the right page: this turn's letter
        if f.written ~= "" then
            centred(bb, Font:getFace("smalltfont", px(B.h * 0.13)), f.written, lcx, cy, true, Blitbuffer.COLOR_DARK_GRAY)
        end
        if f.letter then
            centred(bb, Font:getFace("smalltfont", px(B.h * 0.42)), f.letter, rcx, cy, true)
        end
        -- the page in the air: over the right page, upright at the spine, over the left page
        if f.leaf > 0 then
            local lift = S(12)
            local lx, lw
            if f.leaf == 1 then lx, lw = bx + half, math.floor(half * 0.72)
            elseif f.leaf == 2 then lx, lw = bx + half - S(5), S(10)
            else lw = math.floor(half * 0.72); lx = bx + half - lw end
            local ly, lh = by - (f.leaf == 2 and lift + S(6) or lift), B.h + (f.leaf == 2 and S(6) or 0)
            bb:paintRect(lx, ly, lw, lh, f.leaf == 2 and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_LIGHT_GRAY)
            bb:paintBorder(lx, ly, lw, lh, line, Blitbuffer.COLOR_BLACK)
        end
    end
    function Show:onTapShow() return self:onClose() end
    function Show:onClosePress() return self:onClose() end
    function Show:onCloseWidget()
        self.closed = true
        UIManager:unschedule(self.tick)
    end
    function Show:onClose() UIManager:close(self, "full"); return true end
    local g = Show:new{}
    UIManager:show(g, "full")
    return g
end

--- The version row's tap (Settings → About): counts, says "N more" near the end, opens the animation.
Egg.state = {}
function Egg.versionTapped(now)
    local r = Egg.tap(Egg.state, now or os.time())
    if r.open then return Egg.show() end
    if r.left then
        local UIManager = require("ui/uimanager")
        local _ = require("gettext")
        local T = require("ffi/util").template
        UIManager:show(require("ui/widget/notification"):new{
            text = r.left == 1 and _("One more tap…") or T(_("%1 more taps…"), r.left) })
    end
    return r
end

return Egg
