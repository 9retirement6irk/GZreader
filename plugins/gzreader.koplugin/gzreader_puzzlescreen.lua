--[[--
The daily paper's puzzles page (the puzzles themselves: gzreader_puzzles.lua).

One screen, three puzzles, a tab each: Sudoku, Word search, Maze.

- Touch (a finger or the pen): tap a tab; in the sudoku tap a square, then a
  number under the grid; in the word search draw along a word from its first
  letter to its last (as you'd circle it), or tap those two letters; in the
  maze tap or swipe the way to go.
- Keys: the page keys change puzzle; the 5-way moves; Press writes the next
  number / marks a letter; on a keyboard, Q W E R T Y U I O (the keys under
  1–9) or the number keys write a number, Del rubs out, C checks, N starts
  again; Menu is the quick panel.

What you've done is kept for the day (store.daily.puzzles).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local function P() return require("gzreader_puzzles") end

local Screen_ = {}

function Screen_.tabLabel(kind)
    if kind == "sudoku" then return _("Sudoku") end
    if kind == "words" then return _("Word search") end
    return _("Maze")
end

--- The maze's size for a board of w × h pixels with squares about `cell` wide.
function Screen_.mazeSize(w, h, cell)
    local cols = math.max(6, math.min(22, math.floor(w / cell)))
    local rows = math.max(6, math.min(26, math.floor(h / math.floor(w / cols))))
    return cols, rows
end

--- The line under the board: what's left, or that it's done.
function Screen_.statusText(kind, info)
    if info.done then return _("Solved. A new one comes with tomorrow's paper.") end
    if kind == "sudoku" then
        if info.wrong and info.wrong > 0 then
            return info.wrong == 1 and _("1 square isn't right (marked).") or T(_("%1 squares aren't right (marked)."), info.wrong)
        end
        if info.checked then return _("Right so far.") end
        return T(_("%1 squares to go."), info.left)
    end
    if kind == "words" then return T(_("%1 of %2 found."), info.found, info.of) end
    return _("In at the top left, out at the bottom right.")
end

--- How to play, for this Kindle.
function Screen_.helpText(kind, touch, keyboard)
    if kind == "sudoku" then
        if touch then return _("Tap a square, then a number.") end
        if keyboard then return _("5-way: move · Q–O (or 1–9): write · Del: rub out · C: check · N: start again") end
        return _("5-way: move · Press: the next number")
    end
    if kind == "words" then
        if touch then return _("Draw along a word to circle it, or tap its first letter, then its last.") end
        return _("5-way: move · Press on a word's first letter, then on its last")
    end
    if touch then return _("Tap or swipe the way to go.") end
    return keyboard and _("5-way: go that way · N: start again") or _("5-way: go that way")
end

--- Where a stroke over the letters ends, straightened: from cell (x1, y1) to
--- (x2, y2), the end moved onto the line (across, down or a diagonal) the
--- stroke was nearest to, the same number of letters long, kept inside a
--- grid of `size`. A finger doesn't end exactly on a square.
function Screen_.snap(x1, y1, x2, y2, size)
    local dx, dy = x2 - x1, y2 - y1
    local ax, ay = math.abs(dx), math.abs(dy)
    local sx, sy = dx < 0 and -1 or 1, dy < 0 and -1 or 1
    local ex, ey
    if ax >= ay * 2 then ex, ey = x2, y1
    elseif ay >= ax * 2 then ex, ey = x1, y2
    else
        local n = math.floor((ax + ay) / 2 + 0.5)
        ex, ey = x1 + sx * n, y1 + sy * n
        -- (a diagonal that would leave the grid: as far as it goes)
        local over = math.max(0, 1 - ex, ex - size, 1 - ey, ey - size)
        ex, ey = ex - sx * over, ey - sy * over
    end
    return math.max(1, math.min(size, ex)), math.max(1, math.min(size, ey))
end

--- The points of a ring drawn round a row of squares, from the middle of the
--- first (ax, ay) to the middle of the last (bx, by), `r` from the line:
--- { { x, y }, … }, about a pixel apart. (Two sides and two round ends.)
function Screen_.ringPoints(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    local ux, uy = 1, 0
    if len > 0 then ux, uy = dx / len, dy / len end
    local nx, ny = -uy, ux
    local out = {}
    for d = 0, math.floor(len) do
        out[#out + 1] = { ax + ux * d + nx * r, ay + uy * d + ny * r }
        out[#out + 1] = { ax + ux * d - nx * r, ay + uy * d - ny * r }
    end
    local steps = math.max(8, math.floor(math.pi * r))
    for i = 0, steps do
        local a = math.pi * i / steps
        local c, sn = math.cos(a) * r, math.sin(a) * r
        out[#out + 1] = { bx + nx * c + ux * sn, by + ny * c + uy * sn }
        out[#out + 1] = { ax + nx * c - ux * sn, ay + ny * c - uy * sn }
    end
    return out
end

-- (a found word's tint on a colour screen, one after another)
Screen_.TINTS = { "#ffe066", "#a5d8ff", "#b2f2bb", "#ffc9c9", "#d0bfff", "#ffd8a8", "#96f2d7", "#fcc2d7" }

local Page

local function pageClass()
    if Page then return Page end
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end

    local function face(file, size, fallback)
        local ok, f = pcall(Font.getFace, Font, file, size)
        if ok and f then return f end
        return Font:getFace(fallback or "smallinfofont", size)
    end

    Page = InputContainer:extend{ covers_fullscreen = true, kind = "sudoku" }

    function Page:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        self.touch = Device:isTouchDevice()
        self.keys = Device:hasKeys() and Device:hasDPad() and not self.touch
        self.keyboard = Device:hasKeyboard() and true or false
        self.glyphs = {}
        if Device:hasKeys() then
            local g = Device.input.group
            self.key_events = {
                PzClose = { { g.Back } },
                PzNextTab = { { g.PgFwd } },
                PzPrevTab = { { g.PgBack } },
                PzUp = { { "Up" }, event = "PzMove", args = "n" },
                PzDown = { { "Down" }, event = "PzMove", args = "s" },
                PzLeft = { { "Left" }, event = "PzMove", args = "w" },
                PzRight = { { "Right" }, event = "PzMove", args = "e" },
                PzPress = { { "Press" } },
            }
            if self.keyboard then
                local row = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O" }
                for n = 1, 9 do
                    self.key_events["PzNum" .. n] = { { tostring(n) }, { row[n] }, event = "PzNumber", args = n }
                end
                self.key_events.PzRub = { { "Del" }, { "Backspace" }, { "P" }, event = "PzNumber", args = 0 }
                self.key_events.PzCheck = { { "C" } }
                self.key_events.PzAgain = { { "N" } }
                self.key_events.PzPanel = { { "Menu" } }
            end
        end
        if self.touch then
            local range = function() return self.dimen end
            self.ges_events = {
                PzTap = { GestureRange:new{ ges = "tap", range = range } },
                PzSwipe = { GestureRange:new{ ges = "swipe", range = range } },
                -- (a word drawn along slowly, or after a pause, isn't a swipe)
                PzPan = { GestureRange:new{ ges = "pan", range = range } },
                PzHoldPan = { GestureRange:new{ ges = "hold_pan", range = range } },
                PzPanRelease = { GestureRange:new{ ges = "pan_release", range = range } },
                PzHoldRelease = { GestureRange:new{ ges = "hold_release", range = range } },
            }
        end
        self:build()
    end

    function Page:glyph(text, size, bold)
        local key = text .. ":" .. size .. (bold and "b" or "")
        local g = self.glyphs[key]
        if not g then
            g = TextWidget:new{ text = text, face = bold and face("NotoSans-Bold.ttf", size, "smallinfofontbold") or face("NotoSans-Regular.ttf", size, "smallinfofont") }
            self.glyphs[key] = g
        end
        return g
    end

    function Page:freeWidgets()
        for _k, g in pairs(self.glyphs) do if g.free then g:free() end end
        self.glyphs = {}
        for _i, w in ipairs(self.widgets or {}) do if w.free then w:free() end end
        self.widgets = {}
    end

    --- Lay the page out for the puzzle showing.
    function Page:build()
        self:freeWidgets()
        local Pz = P()
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        local function text(str, f, max_w)
            local w = TextWidget:new{ text = str, face = f, max_width = max_w }
            self.widgets[#self.widgets + 1] = w
            return w
        end
        self.close_w = self.touch and S(44) or 0
        -- the heading, as the paper's own
        local title = text(_("PUZZLES"), face("NotoSerif-Bold.ttf", 18, "smallinfofontbold"))
        local date = text(require("gzreader_dailyscreen").dateText(os.time()), face("NotoSerif-Italic.ttf", 9, "smallinfofont"), W - margin * 3 - title:getSize().w - self.close_w)
        self.head = { title = title, date = date, y = S(8), h = title:getSize().h }
        local y = self.head.y + self.head.h + S(6)
        self.rule_y = y
        y = y + S(3) + S(8)
        -- the tabs
        local done = Pz.finished(self.plugin)
        self.tabs = {}
        local tab_w = math.floor((W - margin * 2) / #Pz.KINDS)
        local tab_face = Font:getFace("smallinfofontbold", 11)
        local tab_h = 0
        for i, kind in ipairs(Pz.KINDS) do
            local label = text(Screen_.tabLabel(kind) .. (done[kind] and " \u{2713}" or ""), tab_face, tab_w - S(8))
            tab_h = math.max(tab_h, label:getSize().h + S(12))
            self.tabs[i] = { kind = kind, label = label, x = margin + (i - 1) * tab_w, w = tab_w }
        end
        for _i, t in ipairs(self.tabs) do t.y, t.h = y, tab_h end
        y = y + tab_h + S(10)
        -- the foot: how to play, and the status
        local small = Font:getFace("smallinfofont", 10)
        local help = text(Screen_.helpText(self.kind, self.touch, self.keyboard), small, W - margin * 2)
        local foot_h = help:getSize().h + S(10)
        self.foot = { help = help, y = H - foot_h }
        local status_h = help:getSize().h + S(8)
        -- under the board: the sudoku's numbers (touch), the word search's words
        local extra_h = 0
        local ws, found
        if self.kind == "sudoku" then
            if self.touch then extra_h = math.floor((W - margin * 2) / 11) + S(8) end
        elseif self.kind == "words" then
            ws, found = Pz.dayWords(self.plugin)
            extra_h = (self:glyph("A", 11, true):getSize().h + S(6)) * math.ceil(#ws.words / 4) + S(6)
        elseif self.touch then
            extra_h = self:glyph("A", 11, true):getSize().h + S(16)
        end
        local room_h = self.foot.y - y - status_h - extra_h - S(8)
        local room_w = W - margin * 2
        self.board, self.pad, self.list, self.again = nil, nil, nil, nil
        local info
        if self.kind == "sudoku" then
            local s = Pz.daySudoku(self.plugin)
            local cell = math.floor(math.min(room_w, room_h) / 9)
            local side = cell * 9
            self.board = { x = math.floor((W - side) / 2), y = y, w = side, h = side, cell = cell, n = 9 }
            self.sudoku = s
            if not self.cur or self.cur < 1 or self.cur > 81 then self.cur = (s.fill:find("0", 1, true)) or 1 end
            local left = 0
            for _ in s.fill:gmatch("0") do left = left + 1 end
            local wrong_n = 0
            for _k in pairs(self.wrong or {}) do wrong_n = wrong_n + 1 end
            info = { done = Pz.sudokuDone(s), left = left, wrong = wrong_n, checked = self.checked }
            if self.touch then
                -- 1–9, rub out, Check
                local bw = math.floor(room_w / 11)
                self.pad = { y = y + side + S(8), h = bw, w = bw, x = margin, keys = {} }
                for n = 1, 9 do self.pad.keys[n] = { text = tostring(n), value = n } end
                self.pad.keys[10] = { text = "\u{232B}", value = 0 }
                self.pad.keys[11] = { text = "\u{2713}?", check = true }
            end
        elseif self.kind == "words" then
            local cell = math.floor(math.min(room_w, room_h) / ws.size)
            local side = cell * ws.size
            self.board = { x = math.floor((W - side) / 2), y = y, w = side, h = side, cell = cell, n = ws.size }
            self.ws, self.found = ws, found
            self.wcur = self.wcur or { 1, 1 }
            local n = 0
            for _k in pairs(found) do n = n + 1 end
            info = { done = Pz.wordsDone(ws, found), found = n, of = #ws.words }
            local line_h = self:glyph("A", 11, true):getSize().h + S(6)
            self.list = { y = y + side + S(8), col_w = math.floor(room_w / 4), line_h = line_h, x = margin }
        else
            local cols, rows = Screen_.mazeSize(room_w, room_h, S(self.touch and 40 or 30))
            local cell = math.floor(math.min(room_w / cols, room_h / rows))
            self.board = { x = math.floor((W - cell * cols) / 2), y = y, w = cell * cols, h = cell * rows, cell = cell, n = cols, rows = rows }
            self.mz, self.at, self.seen = Pz.dayMaze(self.plugin, cols, rows)
            info = { done = self.at == cols * rows }
            if self.touch then
                local again = text(_("Start again"), Font:getFace("smallinfofontbold", 11))
                self.again = { widget = again, x = margin, y = y + self.board.h + S(10), w = again:getSize().w + S(20), h = again:getSize().h + S(8) }
            end
        end
        if self.kind == "sudoku" and self.touch then
            local again = text(_("Start again"), small)
            self.again = { widget = again, x = W - margin - again:getSize().w, y = self.foot.y + S(5), w = again:getSize().w + S(20), h = foot_h, in_foot = true }
            help.max_width = W - margin * 3 - again:getSize().w
        end
        self.info = info
        local status = text((not info.done and self.note) or Screen_.statusText(self.kind, info), info.done and Font:getFace("smallinfofontbold", 11) or small, room_w)
        self.status = { widget = status, x = margin, y = self.foot.y - status_h + S(2) }
    end

    local function hline(bb, x, y, w, t, c) bb:paintRect(x, y, w, t, c or Blitbuffer.COLOR_BLACK) end
    local function vline(bb, x, y, h, t, c) bb:paintRect(x, y, t, h, c or Blitbuffer.COLOR_BLACK) end
    local function centred(bb, g, x, y, cell)
        local sz = g:getSize()
        g:paintTo(bb, x + math.floor((cell - sz.w) / 2), y + math.floor((cell - sz.h) / 2))
    end
    local function tint(bb, x, y, w, h, hex)
        local ink = require("gzreader_dailyscreen").ink(hex)
        if ink and bb.paintRectRGB32 then bb:paintRectRGB32(x, y, w, h, ink) else bb:paintRect(x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY) end
    end

    function Page:paintSudoku(bb, x, y)
        local b, s = self.board, self.sudoku
        local size = math.max(8, math.floor(b.cell * 0.5 * 160 / Screen:getDPI() + 0.5))
        for i = 1, 81 do
            local r, c = math.floor((i - 1) / 9), (i - 1) % 9
            local cx, cy = x + b.x + c * b.cell, y + b.y + r * b.cell
            local given = s.given:sub(i, i) ~= "0"
            local v = s.fill:sub(i, i)
            if given then bb:paintRect(cx, cy, b.cell, b.cell, Blitbuffer.COLOR_GRAY_E) end
            if v ~= "0" then centred(bb, self:glyph(v, size, given), cx, cy, b.cell) end
            if self.wrong and self.wrong[i] then
                -- (not right: a corner cut off)
                local k = math.floor(b.cell / 4)
                for d = 0, k do bb:paintRect(cx + b.cell - k + d, cy + 1, 1, d, Blitbuffer.COLOR_BLACK) end
            end
        end
        for k = 0, 9 do
            local t = (k % 3 == 0) and S(3) or 1
            hline(bb, x + b.x, y + b.y + k * b.cell - math.floor(t / 2), b.w, t)
            vline(bb, x + b.x + k * b.cell - math.floor(t / 2), y + b.y, b.h, t)
        end
        if self.cur and not self.info.done then
            local r, c = math.floor((self.cur - 1) / 9), (self.cur - 1) % 9
            bb:paintBorder(x + b.x + c * b.cell + 2, y + b.y + r * b.cell + 2, b.cell - 3, b.cell - 3, S(3), Blitbuffer.COLOR_BLACK)
        end
        if self.pad then
            local p = self.pad
            local psize = math.max(8, math.floor(p.w * 0.42 * 160 / Screen:getDPI() + 0.5))
            for n, k in ipairs(p.keys) do
                local kx = x + p.x + (n - 1) * p.w
                bb:paintBorder(kx + 2, y + p.y, p.w - 4, p.h, 1, Blitbuffer.COLOR_BLACK, S(4))
                centred(bb, self:glyph(k.text, k.check and math.floor(psize * 0.8) or psize, true), kx, y + p.y, p.w)
            end
        end
    end

    function Page:paintWords(bb, x, y)
        local b, ws = self.board, self.ws
        local size = math.max(8, math.floor(b.cell * 0.48 * 160 / Screen:getDPI() + 0.5))
        -- found words on a colour screen: their squares tinted, each word its own colour
        local colour = require("gzreader_dailyscreen").ink("#000000") ~= nil
        for n, w in ipairs(ws.words) do
            if self.found[n] and colour then
                for i = 0, #w.word - 1 do
                    tint(bb, x + b.x + (w.x + w.dx * i - 1) * b.cell + 1, y + b.y + (w.y + w.dy * i - 1) * b.cell + 1, b.cell - 2, b.cell - 2,
                        Screen_.TINTS[(n - 1) % #Screen_.TINTS + 1])
                end
            end
        end
        for i = 1, ws.size * ws.size do
            local r, c = math.floor((i - 1) / ws.size), (i - 1) % ws.size
            centred(bb, self:glyph(ws.grid:sub(i, i), size, true), x + b.x + c * b.cell, y + b.y + r * b.cell, b.cell)
        end
        bb:paintBorder(x + b.x - 1, y + b.y - 1, b.w + 2, b.h + 2, 1, Blitbuffer.COLOR_BLACK)
        -- found words: circled
        local th = math.max(2, S(2))
        local half = math.floor(b.cell / 2)
        for n, w in ipairs(ws.words) do
            if self.found[n] then
                local last = #w.word - 1
                for _i, pt in ipairs(Screen_.ringPoints(b.x + (w.x - 1) * b.cell + half, b.y + (w.y - 1) * b.cell + half,
                    b.x + (w.x + w.dx * last - 1) * b.cell + half, b.y + (w.y + w.dy * last - 1) * b.cell + half, math.floor(b.cell * 0.42))) do
                    bb:paintRect(x + math.floor(pt[1] + 0.5) - math.floor(th / 2), y + math.floor(pt[2] + 0.5) - math.floor(th / 2), th, th, Blitbuffer.COLOR_BLACK)
                end
            end
        end
        if self.wsel then
            -- (the first letter chosen: white on black)
            bb:invertRect(x + b.x + (self.wsel[1] - 1) * b.cell + 2, y + b.y + (self.wsel[2] - 1) * b.cell + 2, b.cell - 4, b.cell - 4)
        end
        if self.keys and not self.info.done then
            bb:paintBorder(x + b.x + (self.wcur[1] - 1) * b.cell + 1, y + b.y + (self.wcur[2] - 1) * b.cell + 1, b.cell - 2, b.cell - 2, S(2), Blitbuffer.COLOR_BLACK)
        end
        local l = self.list
        for n, w in ipairs(ws.words) do
            local g = self:glyph(w.word, 11, not self.found[n])
            local gx = x + l.x + ((n - 1) % 4) * l.col_w
            local gy = y + l.y + math.floor((n - 1) / 4) * l.line_h
            g:paintTo(bb, gx, gy)
            if self.found[n] then hline(bb, gx - S(2), gy + math.floor(g:getSize().h / 2), g:getSize().w + S(4), S(2)) end
        end
    end

    function Page:cellXY(at)
        local b = self.board
        return b.x + ((at - 1) % b.n) * b.cell, b.y + math.floor((at - 1) / b.n) * b.cell
    end

    function Page:paintMaze(bb, x, y)
        local Pz = P()
        local b, mz = self.board, self.mz
        local t = math.max(2, S(2))
        -- where you've been: a dot a square
        local dot = math.max(2, math.floor(b.cell / 8))
        for at in pairs(self.seen) do
            local cx, cy = self:cellXY(at)
            bb:paintRect(x + cx + math.floor((b.cell - dot) / 2), y + cy + math.floor((b.cell - dot) / 2), dot, dot, Blitbuffer.COLOR_DARK_GRAY)
        end
        for at = 1, mz.cols * mz.rows do
            local cx, cy = self:cellXY(at)
            if not Pz.mazeOpen(mz, at, "e") then vline(bb, x + cx + b.cell - math.floor(t / 2), y + cy - math.floor(t / 2), b.cell + t, t) end
            if not Pz.mazeOpen(mz, at, "s") and at ~= mz.cols * mz.rows then hline(bb, x + cx - math.floor(t / 2), y + cy + b.cell - math.floor(t / 2), b.cell + t, t) end
        end
        -- the outer wall, open above the first square (the last one's floor is open)
        hline(bb, x + b.x + b.cell, y + b.y - math.floor(t / 2), b.w - b.cell, t)
        vline(bb, x + b.x - math.floor(t / 2), y + b.y, b.h, t)
        -- the way out: an arrow under the last square
        local gx, gy = self:cellXY(mz.cols * mz.rows)
        local a = math.floor(b.cell / 4)
        for d = 0, a do hline(bb, x + gx + math.floor(b.cell / 2) - (a - d), y + gy + b.cell + S(2) + d, (a - d) * 2 + 1, 1) end
        -- you
        local px, py = self:cellXY(self.at)
        local r = math.floor(b.cell * 0.3)
        local ink = require("gzreader_dailyscreen").ink("#c92a2a")
        bb:paintCircle(x + px + math.floor(b.cell / 2), y + py + math.floor(b.cell / 2), r, ink or Blitbuffer.COLOR_BLACK)
        if self.again then
            local g = self.again
            bb:paintBorder(x + g.x, y + g.y, g.w, g.h, 1, Blitbuffer.COLOR_BLACK, S(4))
            g.widget:paintTo(bb, x + g.x + S(10), y + g.y + S(4))
        end
    end

    function Page:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        bb:paintRect(x, y, W, H, Blitbuffer.COLOR_WHITE)
        local h = self.head
        h.title:paintTo(bb, x + margin, y + h.y)
        h.date:paintTo(bb, x + margin + h.title:getSize().w + margin, y + h.y + h.h - h.date:getSize().h - S(3))
        local red = require("gzreader_dailyscreen").ink(require("gzreader_dailyscreen").MAST_COLOR)
        if red and bb.paintRectRGB32 then bb:paintRectRGB32(x + margin, y + self.rule_y, W - margin * 2, S(3), red)
        else bb:paintRect(x + margin, y + self.rule_y, W - margin * 2, S(3), Blitbuffer.COLOR_BLACK) end
        if self.close_w > 0 then
            local cx, cy, arm = x + W - math.floor(self.close_w / 2), y + math.floor(self.close_w / 2), S(7)
            for d = -arm, arm do
                bb:paintRect(cx + d, cy + d, 2, 2, Blitbuffer.COLOR_BLACK)
                bb:paintRect(cx + d, cy - d, 2, 2, Blitbuffer.COLOR_BLACK)
            end
        end
        for _i, t in ipairs(self.tabs) do
            local sz = t.label:getSize()
            t.label:paintTo(bb, x + t.x + math.floor((t.w - sz.w) / 2), y + t.y + math.floor((t.h - sz.h) / 2))
            if t.kind == self.kind then
                bb:invertRect(x + t.x + 1, y + t.y, t.w - 2, t.h)
            else
                bb:paintBorder(x + t.x + 1, y + t.y, t.w - 2, t.h, 1, Blitbuffer.COLOR_DARK_GRAY)
            end
        end
        if self.kind == "sudoku" then self:paintSudoku(bb, x, y)
        elseif self.kind == "words" then self:paintWords(bb, x, y)
        else self:paintMaze(bb, x, y) end
        self.status.widget:paintTo(bb, x + self.status.x, y + self.status.y)
        bb:paintRect(x + margin, y + self.foot.y, W - margin * 2, 1, Blitbuffer.COLOR_BLACK)
        self.foot.help:paintTo(bb, x + margin, y + self.foot.y + S(5))
        if self.again and self.again.in_foot then self.again.widget:paintTo(bb, x + self.again.x, y + self.again.y) end
    end

    function Page:redraw(full)
        UIManager:setDirty(self, function() return full and "partial" or "ui", self.dimen end)
    end

    --- Lay out again after a move (and tell the paper behind, whose foot counts the finished ones).
    function Page:changed(full)
        local was = self.info and self.info.done
        self:build()
        self:redraw(full or (self.info.done and not was))
        if self.info.done and not was then
            require("gzreader_log").info("daily puzzles: " .. self.kind .. " solved")
            local Paper = require("gzreader_dailyscreen")
            if Paper.instance and not Paper.instance.closed then pcall(function() Paper.instance:build() end) end
        end
    end

    function Page:show(kind)
        if kind == self.kind then return true end
        self.kind = kind
        self.wsel, self.wrong, self.checked, self.note, self.drag = nil, nil, nil, nil, nil
        self:build()
        self:redraw(true)
        return true
    end

    function Page:step(by)
        local kinds = P().KINDS
        for i, k in ipairs(kinds) do
            if k == self.kind then return self:show(kinds[(i - 1 + by) % #kinds + 1]) end
        end
    end

    ---------------------------------------------------------------- moves

    function Page:write(v)
        if self.kind ~= "sudoku" or self.info.done or not self.cur then return true end
        if P().sudokuSet(self.plugin, self.cur, v) then
            if self.wrong then self.wrong[self.cur] = nil end
            self.checked = nil
            self:changed()
        end
        return true
    end

    function Page:check()
        if self.kind ~= "sudoku" or self.info.done then return true end
        self.wrong = P().sudokuWrong(self.sudoku)
        self.checked = true
        self:changed()
        return true
    end

    function Page:startAgain()
        if self.kind == "sudoku" then
            P().sudokuClear(self.plugin)
            self.wrong, self.checked, self.cur = nil, nil, nil
        elseif self.kind == "maze" then
            P().mazeClear(self.plugin)
        else
            return true
        end
        self:changed(true)
        return true
    end

    --- A letter of the word search chosen: the first of a word, then the last.
    function Page:letter(cx, cy)
        if self.info.done then return true end
        self.note = nil
        local Pz = P()
        if not self.wsel then
            self.wsel = { cx, cy }
        elseif self.wsel[1] == cx and self.wsel[2] == cy then
            self.wsel = nil
        else
            local n = Pz.wordAt(self.ws, self.wsel[1], self.wsel[2], cx, cy)
            if n and Pz.wordFound(self.plugin, n) then
                self.wsel = nil
            else
                self.wsel = { cx, cy } -- (not a word: start from here)
            end
        end
        self:changed()
        return true
    end

    function Page:go(side)
        if self.info.done then return true end
        local path = P().mazeMove(self.plugin, self.board.n, self.board.rows, side)
        if #path > 0 then self:changed() end
        return true
    end

    ---------------------------------------------------------------- keys

    function Page:onPzClose() UIManager:close(self, "full"); return true end
    function Page:onPzNextTab() return self:step(1) end
    function Page:onPzPrevTab() return self:step(-1) end
    function Page:onPzCheck() return self:check() end
    function Page:onPzAgain() return self:startAgain() end
    function Page:onPzNumber(n) return self:write(n) end
    function Page:onPzPanel() return require("gzreader_dailyscreen").openPanel(self.plugin, "Menu") end

    function Page:onPzMove(side)
        local d = P().SIDES[side]
        if self.kind == "maze" then return self:go(side) end
        if self.kind == "sudoku" then
            local r, c = math.floor((self.cur - 1) / 9), (self.cur - 1) % 9
            r, c = (r + d[3]) % 9, (c + d[2]) % 9
            self.cur = r * 9 + c + 1
        else
            local n = self.ws.size
            self.wcur = { (self.wcur[1] - 1 + d[2]) % n + 1, (self.wcur[2] - 1 + d[3]) % n + 1 }
        end
        self:redraw()
        return true
    end

    function Page:onPzPress()
        if self.kind == "sudoku" then
            if self.info.done or self.sudoku.given:sub(self.cur, self.cur) ~= "0" then return true end
            return self:write((tonumber(self.sudoku.fill:sub(self.cur, self.cur)) + 1) % 10)
        elseif self.kind == "words" then
            return self:letter(self.wcur[1], self.wcur[2])
        end
        return true
    end

    ---------------------------------------------------------------- touch

    --- What's at a point: { "close" }, { "tab", kind }, { "cell", col, row }
    --- (from 1), { "pad", key }, { "again" }, or nil.
    function Page:at_(px, py)
        local W = self.dimen.w
        if self.close_w > 0 and px >= W - self.close_w and py <= self.close_w then return { "close" } end
        for _i, t in ipairs(self.tabs) do
            if px >= t.x and px < t.x + t.w and py >= t.y - S(6) and py < t.y + t.h + S(6) then return { "tab", t.kind } end
        end
        local b = self.board
        if px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h then
            return { "cell", math.floor((px - b.x) / b.cell) + 1, math.floor((py - b.y) / b.cell) + 1 }
        end
        local p = self.pad
        if p and py >= p.y - S(4) and py < p.y + p.h + S(4) and px >= p.x then
            local k = p.keys[math.floor((px - p.x) / p.w) + 1]
            if k then return { "pad", k } end
        end
        local g = self.again
        if g and px >= g.x - S(10) and px < g.x + g.w and py >= g.y - S(6) and py < g.y + g.h + S(6) then return { "again" } end
    end

    function Page:onPzTap(_arg, ges)
        local px, py = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
        local what = self:at_(px, py)
        if not what then
            if self.kind == "maze" then return self:toward(px, py) end
            return true
        end
        if what[1] == "close" then return self:onPzClose() end
        if what[1] == "tab" then return self:show(what[2]) end
        if what[1] == "again" then return self:startAgain() end
        if what[1] == "pad" then
            if what[2].check then return self:check() end
            return self:write(what[2].value)
        end
        if self.kind == "sudoku" then
            self.cur = (what[3] - 1) * 9 + what[2]
            self:redraw()
        elseif self.kind == "words" then
            return self:letter(what[2], what[3])
        else
            return self:toward(px, py)
        end
        return true
    end

    --- The maze: go the way a point lies from where you are.
    function Page:toward(px, py)
        local cx, cy = self:cellXY(self.at)
        local dx, dy = px - (cx + self.board.cell / 2), py - (cy + self.board.cell / 2)
        if math.abs(dx) < self.board.cell / 2 and math.abs(dy) < self.board.cell / 2 then return true end
        if math.abs(dx) >= math.abs(dy) then return self:go(dx > 0 and "e" or "w") end
        return self:go(dy > 0 and "s" or "n")
    end

    --- The word search's square at a point of the page: col, row (from 1), or nil off the letters.
    function Page:letterAt(px, py)
        local b = self.board
        if self.kind ~= "words" or not b then return nil end
        if px < b.x or px >= b.x + b.w or py < b.y or py >= b.y + b.h then return nil end
        return math.floor((px - b.x) / b.cell) + 1, math.floor((py - b.y) / b.cell) + 1
    end

    --- A stroke drawn over the letters, from one point of the page to another:
    --- when it runs along one of the words (either way), the word is found.
    --- Returns true when the stroke began on the letters (it's then nothing else).
    function Page:circle(x1, y1, x2, y2)
        local c1, r1 = self:letterAt(x1, y1)
        if not c1 then return false end
        if self.info.done then return true end
        local b = self.board
        -- (the end may run a little past the last letter, or off the edge)
        local c2 = math.floor((math.max(b.x, math.min(b.x + b.w - 1, x2)) - b.x) / b.cell) + 1
        local r2 = math.floor((math.max(b.y, math.min(b.y + b.h - 1, y2)) - b.y) / b.cell) + 1
        if c1 == c2 and r1 == r2 then return self:letter(c1, r1) end
        local Pz = P()
        local n = Pz.wordAt(self.ws, c1, r1, c2, r2)
        if not n then
            local sc, sr = Screen_.snap(c1, r1, c2, r2, self.ws.size)
            n = Pz.wordAt(self.ws, c1, r1, sc, sr)
        end
        self.wsel = nil
        if n and Pz.wordFound(self.plugin, n) then
            self.note = nil
        else
            self.note = n and _("You've found that one already.") or _("That isn't one of the words. Draw from a word's first letter to its last.")
        end
        self:changed()
        return true
    end

    function Page:onPzPan(_arg, ges)
        if self.kind ~= "words" or not ges.start_pos then return false end
        self.drag = { x1 = ges.start_pos.x - self.dimen.x, y1 = ges.start_pos.y - self.dimen.y, x2 = ges.pos.x - self.dimen.x, y2 = ges.pos.y - self.dimen.y }
        return self:letterAt(self.drag.x1, self.drag.y1) ~= nil
    end
    function Page:onPzHoldPan(arg, ges) return self:onPzPan(arg, ges) end

    function Page:onPzPanRelease(_arg, ges)
        local d = self.drag
        self.drag = nil
        if self.kind ~= "words" or not d then return false end
        return self:circle(d.x1, d.y1, ges.pos and (ges.pos.x - self.dimen.x) or d.x2, ges.pos and (ges.pos.y - self.dimen.y) or d.y2)
    end
    function Page:onPzHoldRelease(arg, ges) return self:onPzPanRelease(arg, ges) end

    function Page:onPzSwipe(_arg, ges)
        local Paper = require("gzreader_dailyscreen")
        if Paper.pulledDown(ges) then return Paper.openPanel(self.plugin) end
        self.drag = nil
        if self.kind == "words" and ges.end_pos
            and self:circle(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y, ges.end_pos.x - self.dimen.x, ges.end_pos.y - self.dimen.y) then
            return true
        end
        local side = ({ north = "n", south = "s", east = "e", west = "w" })[ges.direction]
        if self.kind == "maze" and side then return self:go(side) end
        if ges.direction == "west" then return self:step(1) end
        if ges.direction == "east" then return self:step(-1) end
        return false
    end

    function Page:onCloseWidget()
        self.closed = true
        self:freeWidgets()
        if Screen_.instance == self then Screen_.instance = nil end
        -- (what's written is kept now, not at the next quiet moment)
        pcall(function() self.plugin:save() end)
    end

    return Page
end

--- Open the day's puzzles (at one of them: "sudoku", "words", "maze").
function Screen_.show(plugin, kind)
    if Screen_.instance and not Screen_.instance.closed then return Screen_.instance end
    local self = pageClass():new{ plugin = plugin, kind = kind or "sudoku" }
    Screen_.instance = self
    UIManager:show(self)
    return self
end

return Screen_
