--[[--
The bingo hall: the game board's bingo (gzreader_bingo.lua), drawn.

The caller's ball at the top (the number just called, how many have been,
the five before it), your card under it (B I N G O over five rows; a daubed
square is a black counter with its number in white; the middle is free),
and two buttons: Call the next ball, New game.

- Touch: tap Call, tap a square to daub it, the X to close.
- Keys: the 5-way moves over the card and the buttons, Press daubs or
  presses; with a keyboard N calls the next ball; Back closes.

A square whose number hasn't been called can't be daubed (a line says so).
Five in a line: BINGO, with how many calls it took and your best.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen_ = { instance = nil }
local function B() return require("gzreader_bingo") end

--- What the hall says under the ball: { count, earlier, note }.
function Screen_.lines(b, note)
    local Bingo = B()
    local called = Bingo.calledBalls(b)
    local earlier = {}
    for i = #called - 1, math.max(1, #called - 5), -1 do earlier[#earlier + 1] = Bingo.name(called[i]) end
    local count
    if b.won then
        count = T(_("BINGO! In %1."), Bingo.calls(b.won))
        if b.best then count = count .. " " .. T(_("Your best: %1."), Bingo.calls(b.best)) end
    elseif #called == 0 then
        count = _("Call the first ball to begin.")
    else
        count = T(_("Ball %1 of %2"), #called, Bingo.BALLS)
    end
    return {
        count = count,
        earlier = #earlier > 0 and (_("Before it: ") .. table.concat(earlier, " · ")) or "",
        note = note or "",
    }
end

--- Where everything is on a screen of w × h (px: 160-dpi pixels to the screen's):
--- { ball = { x, y, d }, text = { x, y, w }, head = { x, y, w, h }, cell, grid = { x, y }, buttons = { call, new } }.
function Screen_.layout(w, h, px)
    local margin = px(14)
    local top = px(52)
    local buttons_h = px(56)
    local ball_d = math.min(math.floor(h * 0.17), math.floor(w * 0.3))
    local head_h = px(34)
    local grid_top = top + ball_d + px(18)
    local room_h = h - grid_top - head_h - buttons_h - px(30)
    local cell = math.floor(math.min((w - margin * 2) / 5, room_h / 5))
    local grid_w = cell * 5
    local gx = math.floor((w - grid_w) / 2)
    local by = grid_top + head_h + cell * 5 + px(14)
    local call_w = math.floor(grid_w * 0.62)
    return {
        margin = margin, top = top, cell = cell,
        ball = { x = gx, y = top, d = ball_d },
        text = { x = gx + ball_d + px(14), y = top, w = grid_w - ball_d - px(14) },
        head = { x = gx, y = grid_top, w = grid_w, h = head_h },
        grid = { x = gx, y = grid_top + head_h },
        buttons = {
            call = { x = gx, y = by, w = call_w, h = buttons_h },
            new = { x = gx + call_w + px(10), y = by, w = grid_w - call_w - px(10), h = buttons_h },
        },
        fits = cell >= px(40),
    }
end

local Page

local function pageClass()
    if Page then return Page end
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end
    local function shade(v) return Blitbuffer.gray(v) end
    local function sizeFor(px) return math.max(5, math.floor(px * 160 / Screen:getDPI() + 0.5)) end

    Page = InputContainer:extend{ covers_fullscreen = true, name = "bingo" }

    function Page:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        self.touch = Device:isTouchDevice()
        self.focus = 26 -- (the Call button)
        if Device:hasKeys() then
            local g = Device.input.group
            self.key_events = {
                BgClose = { { g.Back } },
                BgUp = { { "Up" }, event = "BgMove", args = "n" },
                BgDown = { { "Down" }, event = "BgMove", args = "s" },
                BgLeft = { { "Left" }, event = "BgMove", args = "w" },
                BgRight = { { "Right" }, event = "BgMove", args = "e" },
                BgPress = { { "Press" } },
            }
            if Device:hasKeyboard() then self.key_events.BgCall = { { "N" } } end
        end
        if self.touch then
            self.ges_events = { BgTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
        end
        self.widgets = {}
        self.L = Screen_.layout(self.dimen.w, self.dimen.h, S)
    end

    function Page:freeWidgets()
        for _i, w in ipairs(self.widgets) do if w.free then w:free() end end
        self.widgets = {}
    end

    function Page:text(str, f, max_w, colour)
        local w = TextWidget:new{ text = str, face = f, max_width = max_w, fgcolor = colour }
        self.widgets[#self.widgets + 1] = w
        return w
    end

    --- Square `sq`'s place on the screen.
    function Page:squareAt(sq)
        local L = self.L
        return L.grid.x + ((sq - 1) % 5) * L.cell, L.grid.y + math.floor((sq - 1) / 5) * L.cell
    end

    function Page:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        self:freeWidgets()
        local Bingo = B()
        local b = Bingo.state(self.plugin)
        local L = self.L
        local W, H = self.dimen.w, self.dimen.h
        local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
        bb:paintRect(x, y, W, H, white)
        -- the banner and the X
        local banner_h = S(40)
        bb:paintRect(x, y, W, banner_h, black)
        local title = self:text(_("BINGO"), Font:getFace("smallinfofontbold", 16), W - S(80), white)
        title:paintTo(bb, x + L.margin, y + math.floor((banner_h - title:getSize().h) / 2))
        local games = self:text(T(_("Game %1 · won %2"), b.played or 1, b.wins or 0), Font:getFace("smallinfofont", 10), W - S(160), white)
        games:paintTo(bb, x + L.margin + title:getSize().w + S(14), y + math.floor((banner_h - games:getSize().h) / 2))
        if self.touch then
            local d = S(30)
            self.close = { x = W - L.margin - d, y = math.floor((banner_h - d) / 2), d = d }
            local cx, cy, r = x + self.close.x + math.floor(d / 2), y + self.close.y + math.floor(d / 2), math.floor(d / 2)
            bb:paintCircle(cx, cy, r, white)
            local arm = math.floor(r * 0.45)
            for k = -arm, arm do
                bb:paintRect(cx + k - 1, cy + k - 1, 3, 3, black)
                bb:paintRect(cx + k - 1, cy - k - 1, 3, 3, black)
            end
        end
        -- the caller's ball
        local called = Bingo.calledBalls(b)
        local last = called[#called]
        local ball = L.ball
        local r = math.floor(ball.d / 2)
        local bx, by = x + ball.x + r, y + ball.y + r
        bb:paintCircle(bx + S(3), by + S(3), r, shade(0.5))
        bb:paintCircle(bx, by, r, last and black or shade(0.2))
        bb:paintCircle(bx, by, math.floor(r * 0.72), white)
        bb:paintCircle(bx, by, math.floor(r * 0.72), black, math.max(1, S(1)))
        if last then
            local letter = self:text(Bingo.LETTERS[math.floor((last - 1) / 15) + 1], Font:getFace("smallinfofontbold", sizeFor(r * 0.34)))
            local number = self:text(tostring(last), Font:getFace("smallinfofontbold", sizeFor(r * 0.6)))
            local total = letter:getSize().h + number:getSize().h - S(4)
            letter:paintTo(bb, bx - math.floor(letter:getSize().w / 2), by - math.floor(total / 2))
            number:paintTo(bb, bx - math.floor(number:getSize().w / 2), by - math.floor(total / 2) + letter:getSize().h - S(4))
        else
            local q = self:text("?", Font:getFace("smallinfofontbold", sizeFor(r * 0.7)), nil, shade(0.5))
            q:paintTo(bb, bx - math.floor(q:getSize().w / 2), by - math.floor(q:getSize().h / 2))
        end
        -- what the caller says
        local lines = Screen_.lines(b, self.note)
        local tx, ty = x + L.text.x, y + L.text.y + S(6)
        local count = self:text(lines.count, Font:getFace("smallinfofontbold", b.won and 13 or 14), L.text.w)
        count:paintTo(bb, tx, ty)
        ty = ty + count:getSize().h + S(8)
        local earlier = self:text(lines.earlier, Font:getFace("smallinfofont", 11), L.text.w)
        earlier:paintTo(bb, tx, ty)
        ty = ty + earlier:getSize().h + S(8)
        local note = self:text(lines.note, Font:getFace("smallinfofont", 11), L.text.w)
        note:paintTo(bb, tx, ty)
        -- the card: B I N G O
        local c = L.cell
        bb:paintRect(x + L.head.x, y + L.head.y, L.head.w, L.head.h, black)
        for col = 1, 5 do
            local l = self:text(Bingo.LETTERS[col], Font:getFace("smallinfofontbold", sizeFor(L.head.h * 0.62)), nil, white)
            l:paintTo(bb, x + L.head.x + (col - 1) * c + math.floor((c - l:getSize().w) / 2), y + L.head.y + math.floor((L.head.h - l:getSize().h) / 2))
        end
        local won_line = {}
        for _i, sq in ipairs(b.won and Bingo.line(b.marks) or {}) do won_line[sq] = true end
        local num_face = Font:getFace("smallinfofontbold", sizeFor(c * 0.36))
        local free_face = Font:getFace("smallinfofontbold", sizeFor(c * 0.2))
        for sq = 1, 25 do
            local sx, sy = self:squareAt(sq)
            sx, sy = x + sx, y + sy
            bb:paintRect(sx, sy, c, c, won_line[sq] and shade(0.25) or white)
            bb:paintBorder(sx, sy, c + 1, c + 1, math.max(1, S(1)), black)
            local daubed = b.marks:sub(sq, sq) == "1"
            local n = b.card[sq]
            if daubed then
                bb:paintCircle(sx + math.floor(c / 2), sy + math.floor(c / 2), math.floor(c * 0.4), black)
            end
            local label = n == 0 and self:text(_("FREE"), free_face, c - S(6), white)
                or self:text(tostring(n), num_face, c - S(6), daubed and white or black)
            label:paintTo(bb, sx + math.floor((c - label:getSize().w) / 2), sy + math.floor((c - label:getSize().h) / 2))
            if self.focus == sq and not self.touch then
                bb:paintBorder(sx + S(2), sy + S(2), c - S(3), c - S(3), math.max(3, S(3)), daubed and shade(0.5) or black)
            end
        end
        -- the buttons
        local function button(t, label, enabled, focused)
            bb:paintRoundedRect(x + t.x + S(2), y + t.y + S(2), t.w, t.h, shade(0.5), S(8))
            bb:paintRoundedRect(x + t.x, y + t.y, t.w, t.h, enabled and black or shade(0.35), S(8))
            if focused then bb:paintBorder(x + t.x + S(4), y + t.y + S(4), t.w - S(8), t.h - S(8), math.max(2, S(2)), white, S(6)) end
            local l = self:text(label, Font:getFace("smallinfofontbold", 13), t.w - S(16), white)
            l:paintTo(bb, x + t.x + math.floor((t.w - l:getSize().w) / 2), y + t.y + math.floor((t.h - l:getSize().h) / 2))
        end
        local can_call = not b.won and b.called < Bingo.BALLS
        local call_label = Device:hasKeyboard() and _("Call the next ball (N)") or _("Call the next ball")
        button(L.buttons.call, call_label, can_call, self.focus == 26 and not self.touch)
        button(L.buttons.new, _("New game"), true, self.focus == 27 and not self.touch)
    end

    function Page:redraw()
        UIManager:setDirty(self, "ui")
        return true
    end

    function Page:call()
        local Bingo = B()
        local n = Bingo.call(self.plugin)
        local b = Bingo.state(self.plugin)
        if n then
            self.note = ""
        elseif b.won then
            self.note = _("New game deals another card.")
        else
            self.note = _("Every ball has been called.")
        end
        return self:redraw()
    end

    function Page:daub(sq)
        local Bingo = B()
        local b = Bingo.state(self.plugin)
        local what, new = Bingo.daub(self.plugin, sq)
        if what == "not called" then
            self.note = T(_("%1 hasn't been called."), Bingo.name(b.card[sq]))
        elseif what == "over" then
            self.note = _("New game deals another card.")
        else
            self.note = ""
        end
        self:redraw()
        if what == "bingo" then
            UIManager:setDirty(self, "flashui")
            if type(new) == "table" and #new > 0 then pcall(function() require("gzreader_puzzlescreen").unlocked(new) end) end
        end
        return true
    end

    function Page:newGame()
        B().deal(self.plugin)
        self.note = ""
        self.focus = 26
        UIManager:setDirty(self, "flashui")
        return true
    end

    --- What's at a point: "close", a square (1..25), 26 (Call) or 27 (New game).
    function Page:at_(px, py)
        local L = self.L
        local c = self.close
        if c and px >= c.x - S(8) and px < c.x + c.d + S(8) and py >= c.y - S(8) and py < c.y + c.d + S(8) then return "close" end
        local gx, gy = px - L.grid.x, py - L.grid.y
        if gx >= 0 and gy >= 0 and gx < L.cell * 5 and gy < L.cell * 5 then
            return math.floor(gy / L.cell) * 5 + math.floor(gx / L.cell) + 1
        end
        for i, t in ipairs({ L.buttons.call, L.buttons.new }) do
            if px >= t.x and px < t.x + t.w and py >= t.y and py < t.y + t.h then return 25 + i end
        end
    end

    function Page:run(what)
        if what == 26 then return self:call() end
        if what == 27 then return self:newGame() end
        if type(what) == "number" then return self:daub(what) end
        return true
    end

    function Page:onBgTap(_arg, ges)
        local what = self:at_(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
        if what == "close" then return self:onBgClose() end
        return self:run(what)
    end

    function Page:onBgMove(side)
        local f = self.focus
        if f <= 25 then
            local row, col = math.floor((f - 1) / 5), (f - 1) % 5
            if side == "e" and col < 4 then f = f + 1
            elseif side == "w" and col > 0 then f = f - 1
            elseif side == "n" and row > 0 then f = f - 5
            elseif side == "s" then f = row < 4 and f + 5 or (col >= 3 and 27 or 26) end
        elseif side == "n" then f = f == 26 and 22 or 25
        elseif side == "e" and f == 26 then f = 27
        elseif side == "w" and f == 27 then f = 26 end
        if f ~= self.focus then
            self.focus = f
            self:redraw()
        end
        return true
    end

    function Page:onBgPress() return self:run(self.focus) end
    function Page:onBgCall() return self:call() end

    function Page:onBgClose()
        UIManager:close(self, "full")
        return true
    end

    function Page:onCloseWidget()
        self.closed = true
        self:freeWidgets()
        if Screen_.instance == self then Screen_.instance = nil end
        pcall(function() self.plugin:save() end)
        if self.on_close then pcall(self.on_close) end
    end

    return Page
end

--- Open the bingo hall. opts.on_close: called when it closes (the board draws itself again).
function Screen_.show(plugin, opts)
    if Screen_.instance and not Screen_.instance.closed then return Screen_.instance end
    local self = pageClass():new{ plugin = plugin, on_close = opts and opts.on_close }
    Screen_.instance = self
    UIManager:show(self)
    require("gzreader_log").info("game board: bingo opened")
    return self
end

return Screen_
