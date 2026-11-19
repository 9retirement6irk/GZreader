--[[--
Settings' easter egg, as Android's: tap GZreader's version in Settings →
About seven times and a little game opens: the 15 puzzle (fifteen numbered
tiles and a gap on a 4 x 4 board; slide them back into order).

- A tap on a tile in the gap's row or column slides it (and any between)
  into the gap. Keyboard Kindles and the Kindle 4: the 5-way moves the
  tile beside the gap into it (▲ moves the one below the gap up, and so on).
- Moves are counted; solved, it says in how many, and the best is kept.
- Back (or the ✕) closes it. It never touches anything else.

Pure part (easteregg_test.lua): Egg.taps (the version's taps), Egg.new,
Egg.shuffle, Egg.slide, Egg.slideDir, Egg.solved.
]]

local Egg = {}

Egg.TAPS = 7 -- taps on the version that open it
Egg.WINDOW = 4 -- seconds: a pause longer than this starts the count again
Egg.HINT_FROM = 4 -- from this tap on, "N more" is said (as Android does)
Egg.SIDE = 4
Egg.SHUFFLE_MOVES = 200
Egg.BEST = "gzreader_egg_best"

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

-- ------------------------------------------------------------ the board

--- A solved board: tiles 1..15 in order, 0 the gap (last).
function Egg.new(side)
    side = side or Egg.SIDE
    local b = { side = side, moves = 0 }
    for i = 1, side * side - 1 do b[i] = i end
    b[side * side] = 0
    b.gap = side * side
    return b
end

local function rc(b, i) return math.floor((i - 1) / b.side), (i - 1) % b.side end
local function at(b, r, c) return r * b.side + c + 1 end

function Egg.solved(b)
    for i = 1, b.side * b.side - 1 do if b[i] ~= i then return false end end
    return true
end

--- Slides the tile at `i` (and any between it and the gap) into the gap, when
--- it's in the gap's row or column. Returns the cells that changed, or nil.
function Egg.slide(b, i)
    if i == b.gap or b[i] == nil then return nil end
    local r, c = rc(b, i)
    local gr, gc = rc(b, b.gap)
    if r ~= gr and c ~= gc then return nil end
    local changed = { b.gap }
    local dr = r == gr and 0 or (r > gr and 1 or -1)
    local dc = c == gc and 0 or (c > gc and 1 or -1)
    -- (step by step from the gap towards the tile: each one in turn moves into the gap)
    while b.gap ~= i do
        local cr, cc = rc(b, b.gap)
        local nxt = at(b, cr + dr, cc + dc)
        b[b.gap], b[nxt] = b[nxt], 0
        b.gap = nxt
        changed[#changed + 1] = nxt
    end
    b.moves = b.moves + 1
    return changed
end

--- The 5-way: the tile on that side of the gap's other side moves into it
--- ("up": the tile below the gap moves up). Returns the cells changed, or nil.
function Egg.slideDir(b, dir)
    local gr, gc = rc(b, b.gap)
    local r, c = gr, gc
    if dir == "up" then r = gr + 1 elseif dir == "down" then r = gr - 1
    elseif dir == "left" then c = gc + 1 elseif dir == "right" then c = gc - 1 end
    if r < 0 or c < 0 or r >= b.side or c >= b.side then return nil end
    return Egg.slide(b, at(b, r, c))
end

--- Shuffled by `n` random slides from solved (so always solvable), not solved at the end.
--- `rand(k)`: 1..k (math.random by default).
function Egg.shuffle(b, n, rand)
    rand = rand or math.random
    local dirs = { "up", "down", "left", "right" }
    local back = { up = "down", down = "up", left = "right", right = "left" }
    local last
    local k = 0
    while k < (n or Egg.SHUFFLE_MOVES) or Egg.solved(b) do
        local d = dirs[rand(4)]
        if d ~= (last and back[last]) and Egg.slideDir(b, d) then last = d; k = k + 1 end
    end
    b.moves = 0
    return b
end

-- --------------------------------------------------------------- screen

--- Shows the game (full screen). Returns the widget.
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
    local T = require("ffi/util").template
    local Screen = Device.screen
    local function S(n) return Screen:scaleBySize(n) end

    local Game = InputContainer:extend{ name = "gz_egg", covers_fullscreen = true }
    function Game:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        self.board = Egg.shuffle(Egg.new())
        local side = self.board.side
        local size = math.floor(math.min(sw - 2 * S(24), sh - S(200)) / side) * side
        self.cell = size / side
        self.grid = Geom:new{ x = math.floor((sw - size) / 2), y = math.floor((sh - size) / 2) + S(20), w = size, h = size }
        self.best = G_reader_settings and G_reader_settings:readSetting(Egg.BEST)
        self.close_rect = Geom:new{ x = 0, y = 0, w = S(64), h = S(64) }
        self.ges_events = { TapGame = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
        local back = Device.input and Device.input.group and Device.input.group.Back or "Back"
        self.key_events = {
            Close = { { back } },
            Up = { { "Up" } }, Down = { { "Down" } }, Left = { { "Left" } }, Right = { { "Right" } },
            Again = { { "Press" } },
        }
        require("gzreader_log").info("easter egg: the 15 puzzle opened")
    end
    function Game:cellRect(i)
        local r, c = math.floor((i - 1) / self.board.side), (i - 1) % self.board.side
        return Geom:new{ x = self.grid.x + c * self.cell, y = self.grid.y + r * self.cell, w = self.cell, h = self.cell }
    end
    function Game:paintTo(bb, x, y)
        local sw, sh = self.dimen.w, self.dimen.h
        bb:paintRect(x, y, sw, sh, Blitbuffer.COLOR_WHITE)
        local title = Font:getFace("smalltfont", 26)
        local small = Font:getFace("cfont", 18)
        local function centre(face, text, ty, bold)
            local w = RenderText:sizeUtf8Text(0, sw, face, text, true, bold).x
            RenderText:renderUtf8Text(bb, x + math.floor((sw - w) / 2), y + ty, face, text, true, bold, Blitbuffer.COLOR_BLACK)
        end
        centre(title, "GZreader 15", S(50), true)
        -- ✕ at the top left (touch Kindles have no Back key)
        local cr = self.close_rect
        local xf = Font:getFace("cfont", 26)
        RenderText:renderUtf8Text(bb, x + cr.x + S(10), y + cr.y + S(36), xf, "\u{2715}", true, false, Blitbuffer.COLOR_BLACK)
        local status
        if self.won then
            status = T(_("Solved in %1 moves!"), self.board.moves) .. "   " .. _("Tap for another")
        else
            status = T(_("Moves: %1"), self.board.moves) .. (self.best and ("   " .. T(_("Best: %1"), self.best)) or "")
        end
        centre(small, status, S(90))
        local face = Font:getFace("smalltfont", math.max(18, math.floor(self.cell / Screen:scaleBySize(1) * 0.32)))
        for i = 1, self.board.side * self.board.side do
            local r = self:cellRect(i)
            local v = self.board[i]
            local pad = S(4)
            if v ~= 0 then
                bb:paintRect(x + r.x + pad, y + r.y + pad, r.w - 2 * pad, r.h - 2 * pad, Blitbuffer.COLOR_BLACK)
                bb:paintRect(x + r.x + pad + S(3), y + r.y + pad + S(3), r.w - 2 * pad - S(6), r.h - 2 * pad - S(6),
                    (v == i) and Blitbuffer.COLOR_LIGHT_GRAY or Blitbuffer.COLOR_WHITE)
                local text = tostring(v)
                local m = RenderText:sizeUtf8Text(0, r.w, face, text, true, true)
                local fh, asc = face.ftsize:getHeightAndAscender()
                RenderText:renderUtf8Text(bb, x + r.x + math.floor((r.w - m.x) / 2), y + r.y + math.floor((r.h - fh) / 2 + asc), face,
                    text, true, true, Blitbuffer.COLOR_BLACK)
            end
        end
        local hint = Device:isTouchDevice() and _("Tap a tile in the gap's row or column · ✕ closes")
            or _("◀ ▶ ▲ ▼ slide a tile into the gap · Back closes")
        centre(small, hint, sh - S(40))
    end
    function Game:changedCells(cells)
        if not cells then return end
        if Egg.solved(self.board) then
            self.won = true
            if not self.best or self.board.moves < self.best then
                self.best = self.board.moves
                if G_reader_settings then G_reader_settings:saveSetting(Egg.BEST, self.best) end
            end
            require("gzreader_log").info("easter egg: solved in", self.board.moves, "moves")
            UIManager:setDirty(self, "flashui")
            return
        end
        -- (only the tiles that moved, and the moves line, refreshed: quick on e-ink)
        local box
        for _i, c in ipairs(cells) do
            local r = self:cellRect(c)
            box = box and box:combine(r) or r
        end
        UIManager:setDirty(self, function() return "ui", box end)
        UIManager:setDirty(self, function() return "ui", Geom:new{ x = 0, y = S(70), w = self.dimen.w, h = S(30) } end)
    end
    function Game:onTapGame(_arg, ges)
        local p = ges.pos
        if self.close_rect:contains(p) then return self:onClose() end
        if self.won then return self:onAgain() end
        if not self.grid:contains(p) then return true end
        local c = math.floor((p.x - self.grid.x) / self.cell)
        local r = math.floor((p.y - self.grid.y) / self.cell)
        self:changedCells(Egg.slide(self.board, r * self.board.side + c + 1))
        return true
    end
    function Game:onUp() if not self.won then self:changedCells(Egg.slideDir(self.board, "up")) end; return true end
    function Game:onDown() if not self.won then self:changedCells(Egg.slideDir(self.board, "down")) end; return true end
    function Game:onLeft() if not self.won then self:changedCells(Egg.slideDir(self.board, "left")) end; return true end
    function Game:onRight() if not self.won then self:changedCells(Egg.slideDir(self.board, "right")) end; return true end
    function Game:onAgain()
        if not self.won then return true end
        self.won = nil
        self.board = Egg.shuffle(Egg.new())
        UIManager:setDirty(self, "ui")
        return true
    end
    function Game:onClose() UIManager:close(self, "full"); return true end
    local g = Game:new{}
    UIManager:show(g, "full")
    return g
end

--- The version row's tap (Settings → About): counts, says "N more" near the end, opens the game.
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
