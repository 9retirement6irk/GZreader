--[[--
The daily paper's puzzles page (the puzzles themselves: gzreader_puzzles.lua).

One screen, four puzzles, a tab each: Sudoku, Word search, Crossword, Maze.

- Touch (a finger or the pen): tap a tab; in the sudoku tap a square, then a
  number under the grid; in the word search draw along a word from its first
  letter to its last (as you'd circle it), or tap those two letters; in the
  crossword tap a square (again to turn from across to down), then a letter
  under the grid; in the maze tap or swipe the way to go.
- Keys: the page keys change puzzle; the 5-way moves; Press writes the next
  number / marks a letter; on a keyboard, Q W E R T Y U I O (the keys under
  1–9) or the number keys write a number, Del rubs out, C checks, N starts
  again; in the crossword the letter keys write and Press turns from across
  to down; Menu is the quick panel.

What you've done is kept for the day (store.daily.puzzles).

The game board (gzreader_gameboardscreen.lua) opens the same page for the
paper's puzzles (the same ones, kept in the same place), and for a themed
set of its own: Screen_.show(plugin, kind, { set = … }), with a word
scramble among its puzzles (tap a letter, then another to swap them; 5-way:
left and right choose, Press picks and swaps, up and down change word).
A puzzle finished is noted in the board's history (gzreader_gameboard.lua
Board.solved), whichever page it was done on.
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
    if kind == "cross" then return _("Crossword") end
    if kind == "scramble" then return _("Scramble") end
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
    if info.done then
        if info.set then return _("Solved. For new puzzles of this theme: New puzzles on the game board.") end
        return _("Solved. A new one comes with tomorrow's paper.")
    end
    if kind == "scramble" then
        return T(_("Word %1 of %2 · %3 put right."), info.at, info.of, info.right)
    end
    if kind == "sudoku" then
        if info.wrong and info.wrong > 0 then
            return info.wrong == 1 and _("1 square isn't right (marked).") or T(_("%1 squares aren't right (marked)."), info.wrong)
        end
        if info.checked then return _("Right so far.") end
        return T(_("%1 squares to go."), info.left)
    end
    if kind == "cross" then
        local line
        if info.wrong and info.wrong > 0 then
            line = info.wrong == 1 and _("1 letter isn't right (marked).") or T(_("%1 letters aren't right (marked)."), info.wrong)
        elseif info.checked then line = _("Right so far.")
        else line = T(_("%1 squares to go."), info.left) end
        if info.news then line = line .. " " .. _("The clues are from the paper's stories.") end
        return line
    end
    if kind == "words" then
        local line = T(_("%1 of %2 found."), info.found, info.of)
        if info.news then line = line .. " " .. _("The words are from the paper's stories.") end
        return line
    end
    return _("In at the top left, out at the bottom right.")
end

--- How to play, for this Kindle.
function Screen_.helpText(kind, touch, keyboard)
    if kind == "sudoku" then
        if touch then return _("Tap a square, then a number.") end
        if keyboard then return _("5-way: move · Q–O (or 1–9): write · Del: rub out · C: check · N: start again") end
        return _("5-way: move · Press: the next number")
    end
    if kind == "cross" then
        if touch then return _("Tap a square (again to turn), then a letter. Tap the clue for all the clues.") end
        if keyboard then return _("5-way: move · letters: write · Del: rub out · Press: across or down") end
        return _("5-way: move · Press: the next letter")
    end
    if kind == "scramble" then
        if touch then return _("Tap a letter, then another to swap them. Tap a word below to go to it.") end
        if keyboard then return _("5-way: choose · Press: pick, then swap · Up, Down: another word · H: a hint") end
        return _("Left, Right: choose · Press: pick, then swap · Up, Down: another word")
    end
    if kind == "words" then
        if touch then return _("Draw along a word to circle it, or tap its first letter, then its last.") end
        return _("5-way: move · Press on a word's first letter, then on its last")
    end
    if touch then return _("Tap or swipe the way to go.") end
    return keyboard and _("5-way: go that way · N: start again") or _("5-way: go that way")
end

--- A crossword clue's heading and text: "4 Across", "Council votes to keep the old _____ open".
function Screen_.clueHead(w)
    return T(w.d == "a" and _("%1 Across") or _("%1 Down"), w.n)
end

--- Every clue of a crossword as text, Across then Down (the touch page's list).
function Screen_.clueList(cw)
    local out, last = {}, nil
    for _i, w in ipairs(cw.words) do
        if w.d ~= last then
            out[#out + 1] = (last and "\n" or "") .. (w.d == "a" and _("ACROSS") or _("DOWN"))
            last = w.d
        end
        out[#out + 1] = w.n .. ". " .. w.clue .. " (" .. #w.word .. ")"
    end
    return table.concat(out, "\n")
end

--- The gaps of a crossword to black out: the places without a square that
--- have squares on two sides or more (left blank they'd pass for squares).
function Screen_.crossBlacks(cells, cols, rows)
    local out = {}
    for y = 1, rows do
        for x = 1, cols do
            local idx = (y - 1) * cols + x
            if not cells[idx] then
                local n = 0
                if x > 1 and cells[idx - 1] then n = n + 1 end
                if x < cols and cells[idx + 1] then n = n + 1 end
                if y > 1 and cells[idx - cols] then n = n + 1 end
                if y < rows and cells[idx + cols] then n = n + 1 end
                if n >= 2 then out[#out + 1] = idx end
            end
        end
    end
    return out
end

--- Where the 5-way goes in a crossword from a square towards a side: the
--- next square that way in its row or column (over a gap too); with none,
--- the nearest square lying that way at all; nil when there is none.
--- `cells` = Puzzles.crossCells(cw).
function Screen_.crossStep(cells, cols, rows, cell, side)
    local x, y = (cell - 1) % cols + 1, math.floor((cell - 1) / cols) + 1
    local dx = side == "e" and 1 or side == "w" and -1 or 0
    local dy = side == "s" and 1 or side == "n" and -1 or 0
    local cx, cy = x + dx, y + dy
    while cx >= 1 and cx <= cols and cy >= 1 and cy <= rows do
        if cells[(cy - 1) * cols + cx] then return (cy - 1) * cols + cx end
        cx, cy = cx + dx, cy + dy
    end
    local best, best_d
    for idx in pairs(cells) do
        local ox, oy = (idx - 1) % cols + 1 - x, math.floor((idx - 1) / cols) + 1 - y
        local along, off = ox * dx + oy * dy, math.abs(ox * dy) + math.abs(oy * dx)
        if along > 0 then
            local d = along + off * 2 + idx / 100000
            if not best_d or d < best_d then best, best_d = idx, d end
        end
    end
    return best
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
        self.pz = self.pz or self.plugin
        self.kinds = self.kinds or P().kindsOf(self.pz) -- (the game board gives the paper's without the sudoku)
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
                -- (a letter key means what the puzzle showing makes of it: Page:onPzKey)
                for b = 65, 90 do
                    local letter = string.char(b)
                    self.key_events["PzKey" .. letter] = { { letter }, event = "PzKey", args = letter }
                end
                for n = 1, 9 do
                    self.key_events["PzNum" .. n] = { { tostring(n) }, event = "PzNumber", args = n }
                end
                self.key_events.PzRub = { { "Del" }, { "Backspace" }, event = "PzNumber", args = 0 }
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
        local title = text(self.set and _("GAME BOARD") or _("PUZZLES"), face("NotoSerif-Bold.ttf", 18, "smallinfofontbold"))
        local date = text(self.set and tostring(self.set.title or "") or require("gzreader_dailyscreen").dateText(os.time()),
            face("NotoSerif-Italic.ttf", 9, "smallinfofont"), W - margin * 3 - title:getSize().w - self.close_w)
        self.head = { title = title, date = date, y = S(8), h = title:getSize().h }
        local y = self.head.y + self.head.h + S(6)
        self.rule_y = y
        y = y + S(3) + S(8)
        -- the tabs
        local done = Pz.finished(self.pz)
        self.tabs = {}
        local tab_w = math.floor((W - margin * 2) / #self.kinds)
        local tab_face = Font:getFace("smallinfofontbold", 11)
        local tab_h = 0
        for i, kind in ipairs(self.kinds) do
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
            ws, found = Pz.dayWords(self.pz)
            extra_h = (self:glyph("A", 11, true):getSize().h + S(6)) * math.ceil(#ws.words / 4) + S(6)
        elseif self.kind == "cross" or self.kind == "scramble" then
            extra_h = 0 -- (worked out below, with the puzzle in hand)
        elseif self.touch then
            extra_h = self:glyph("A", 11, true):getSize().h + S(16)
        end
        local room_h = self.foot.y - y - status_h - extra_h - S(8)
        local room_w = W - margin * 2
        self.board, self.pad, self.list, self.again, self.clue, self.cpad, self.clues = nil, nil, nil, nil, nil, nil, nil
        self.sclue, self.slist, self.hint = nil, nil, nil
        local info
        if self.kind == "sudoku" then
            local s = Pz.daySudoku(self.pz)
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
            info = { done = Pz.wordsDone(ws, found), found = n, of = #ws.words, news = ws.src ~= nil and ws.src ~= "list" and ws.src ~= "set" }
            local line_h = self:glyph("A", 11, true):getSize().h + S(6)
            self.list = { y = y + side + S(8), col_w = math.floor(room_w / 4), line_h = line_h, x = margin }
        elseif self.kind == "cross" then
            local cw, fill = Pz.dayCross(self.pz)
            local cells = Pz.crossCells(cw)
            self.cw, self.cfill, self.ccells = cw, fill, cells
            if not self.ccur or not cells[self.ccur] then
                local w1 = cw.words[1]
                self.ccur, self.cdir = (w1.y - 1) * cw.cols + w1.x, w1.d
            end
            if not cells[self.ccur][self.cdir] then self.cdir = self.cdir == "a" and "d" or "a" end
            local word = cw.words[cells[self.ccur][self.cdir]]
            -- under the grid: the clue of the word you're in (three lines), then the letters
            -- (touch) or as many of the clues as fit (keys)
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local line_h = self:glyph("A", 11, true):getSize().h
            local clue_h = line_h * 3 + S(6)
            local under = clue_h + S(8)
            local key_w = math.floor(room_w / 14)
            local list_lines = 0
            if self.touch then
                under = under + key_w * 2 + S(10)
            else
                local across, down = 0, 0
                for _i, w in ipairs(cw.words) do if w.d == "a" then across = across + 1 else down = down + 1 end end
                list_lines = math.min(math.max(across, down) + 1, math.max(0, math.floor((room_h * 0.4 - clue_h) / (line_h + S(2)))))
                under = under + list_lines * (line_h + S(2)) + S(6)
            end
            local grid_h = room_h - under
            local cell = math.min(S(64), math.floor(math.min(room_w / cw.cols, grid_h / cw.rows)))
            self.board = { x = math.floor((W - cell * cw.cols) / 2), y = y, w = cell * cw.cols, h = cell * cw.rows, cell = cell, n = cw.cols, rows = cw.rows }
            local below = y + self.board.h + S(8)
            local head = text(Screen_.clueHead(word), Font:getFace("smallinfofontbold", 11))
            local body = TextBoxWidget:new{ text = word.clue .. " (" .. #word.word .. ")", face = Font:getFace("smallinfofont", 11),
                width = room_w - head:getSize().w - S(10), height = clue_h, height_adjust = true, height_overflow_show_ellipsis = true, alignment = "left" }
            self.widgets[#self.widgets + 1] = body
            self.clue = { head = head, body = body, x = margin, y = below, w = room_w, h = clue_h }
            below = below + clue_h + S(8)
            if self.touch then
                self.cpad = { x = margin, y = below, w = key_w, h = key_w, keys = {} }
                for i = 1, 26 do self.cpad.keys[#self.cpad.keys + 1] = { text = string.char(64 + i), letter = string.char(64 + i) } end
                -- (13 letters a row; rub out ends the first row, check the second)
                table.insert(self.cpad.keys, 14, { text = "\u{232B}", rub = true })
                self.cpad.keys[#self.cpad.keys + 1] = { text = "\u{2713}?", check = true }
                local again = text(_("Start again"), small)
                self.again = { widget = again, x = W - margin - again:getSize().w, y = self.foot.y + S(5), w = again:getSize().w + S(20), h = foot_h, in_foot = true }
                help.max_width = W - margin * 3 - again:getSize().w
            elseif list_lines > 1 then
                -- the clues, Across beside Down, the one you're in in bold
                self.clues = { x = margin, y = below, col_w = math.floor(room_w / 2), line_h = line_h + S(2), rows = {} }
                local col = { a = {}, d = {} }
                for i, w in ipairs(cw.words) do col[w.d][#col[w.d] + 1] = i end
                for c, d in ipairs({ "a", "d" }) do
                    local list = col[d]
                    -- (when they don't all fit, the ones round the word you're in)
                    local first = 1
                    for k, i in ipairs(list) do if cw.words[i] == word and k > list_lines - 1 then first = k - (list_lines - 1) + 1 end end
                    self.clues.rows[#self.clues.rows + 1] = { widget = text(d == "a" and _("ACROSS") or _("DOWN"), Font:getFace("smallinfofontbold", 9)), col = c, line = 0 }
                    for k = first, math.min(#list, first + list_lines - 2) do
                        local w = cw.words[list[k]]
                        self.clues.rows[#self.clues.rows + 1] = { col = c, line = k - first + 1,
                            widget = text(w.n .. ". " .. w.clue, Font:getFace(w == word and "smallinfofontbold" or "smallinfofont", 10), self.clues.col_w - S(10)) }
                    end
                end
            end
            local wrong, left, solved = Pz.crossCheck(cw, fill)
            local wrong_n = 0
            for _k in pairs(wrong) do wrong_n = wrong_n + 1 end
            -- (wrong letters are only shown once asked for, or when every square is written)
            self.cwrong = (self.checked or left == 0) and wrong or {}
            info = { done = solved, left = left, wrong = (self.checked or left == 0) and wrong_n or 0, checked = self.checked, news = cw.src ~= nil and cw.src ~= "list" and cw.src ~= "set" }
        elseif self.kind == "scramble" then
            local sc = Pz.dayScramble(self.pz)
            self.sc = sc
            local e = sc.words[sc.at]
            -- the word you're on as tiles, as big as fit; its clue; the words, a line each
            local n = #e.w
            local tile = math.min(S(70), math.floor(room_w / math.max(n, 6)))
            self.board = { x = math.floor((W - tile * n) / 2), y = y + S(6), w = tile * n, h = tile, cell = tile, n = n, rows = 1 }
            if not self.tcur or self.tcur > n then self.tcur = 1 end
            if self.tsel and self.tsel > n then self.tsel = nil end
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local line_h = self:glyph("A", 11, true):getSize().h
            local clue = TextBoxWidget:new{ text = e.c and (e.c .. " (" .. n .. ")") or T(_("No clue for this one (%1 letters)."), n),
                face = Font:getFace("smallinfofont", 12), width = room_w, height = line_h * 3 + S(6), height_adjust = true,
                height_overflow_show_ellipsis = true, alignment = "center" }
            self.widgets[#self.widgets + 1] = clue
            local below = self.board.y + tile + S(14)
            self.sclue = { widget = clue, x = margin, y = below }
            below = below + clue:getSize().h + S(14)
            local row_h = line_h + S(14)
            self.slist = { x = margin, y = below, w = room_w, row_h = row_h, rows = {} }
            local right = 0
            for i, w in ipairs(sc.words) do
                local ok = w.cur == w.w
                if ok then right = right + 1 end
                local label = i .. ".  " .. (ok and w.w or (w.cur:gsub(".", "%0 "):gsub(" $", ""))) .. (ok and "  \u{2713}" or "")
                self.slist.rows[i] = { widget = text(label, Font:getFace(i == sc.at and "smallinfofontbold" or "smallinfofont", 11), room_w) }
            end
            if self.touch and not Pz.scrambleDone(sc) then
                local hint = text(_("Hint"), Font:getFace("smallinfofontbold", 11))
                self.hint = { widget = hint, x = margin, y = below + #sc.words * row_h + S(8), w = hint:getSize().w + S(20), h = hint:getSize().h + S(8) }
            end
            if self.touch and not self.again then
                local again = text(_("Start again"), small)
                self.again = { widget = again, x = W - margin - again:getSize().w, y = self.foot.y + S(5), w = again:getSize().w + S(20), h = foot_h, in_foot = true }
                help.max_width = W - margin * 3 - again:getSize().w
            end
            info = { done = Pz.scrambleDone(sc), at = sc.at, of = #sc.words, right = right }
        else
            local cols, rows = Screen_.mazeSize(room_w, room_h, S(self.touch and 40 or 30))
            local cell = math.floor(math.min(room_w / cols, room_h / rows))
            self.board = { x = math.floor((W - cell * cols) / 2), y = y, w = cell * cols, h = cell * rows, cell = cell, n = cols, rows = rows }
            self.mz, self.at, self.seen = Pz.dayMaze(self.pz, cols, rows)
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
        if self.set then info.set = true end
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

    function Page:paintCross(bb, x, y)
        local b, cw, cells = self.board, self.cw, self.ccells
        local size = math.max(8, math.floor(b.cell * 0.5 * 160 / Screen:getDPI() + 0.5))
        local num = math.max(5, math.floor(b.cell * 0.2 * 160 / Screen:getDPI() + 0.5))
        local word = cells[self.ccur] and cells[self.ccur][self.cdir]
        -- (a gap with squares on two sides or more would look like a square itself: blacked out)
        for _i, idx in ipairs(Screen_.crossBlacks(cells, cw.cols, cw.rows)) do
            bb:paintRect(x + b.x + ((idx - 1) % cw.cols) * b.cell + 1, y + b.y + math.floor((idx - 1) / cw.cols) * b.cell + 1, b.cell - 1, b.cell - 1, Blitbuffer.COLOR_BLACK)
        end
        for idx, c in pairs(cells) do
            local cx, cy = x + b.x + ((idx - 1) % cw.cols) * b.cell, y + b.y + math.floor((idx - 1) / cw.cols) * b.cell
            -- (the word you're in: on grey)
            if not self.info.done and word and c[self.cdir] == word then bb:paintRect(cx, cy, b.cell, b.cell, Blitbuffer.COLOR_GRAY_E) end
            bb:paintBorder(cx, cy, b.cell + 1, b.cell + 1, 1, Blitbuffer.COLOR_BLACK)
            if c.n then self:glyph(tostring(c.n), num, false):paintTo(bb, cx + S(2), cy + 1) end
            local ch = self.cfill:sub(idx, idx)
            if ch ~= "." and ch ~= "" then
                local g = self:glyph(ch, size, true)
                local sz = g:getSize()
                g:paintTo(bb, cx + math.floor((b.cell - sz.w) / 2), cy + b.cell - sz.h - math.max(0, math.floor((b.cell - sz.h) / 6)))
            end
            if self.cwrong[idx] then
                local k = math.floor(b.cell / 4)
                for d = 0, k do bb:paintRect(cx + b.cell - k + d, cy + 1, 1, d, Blitbuffer.COLOR_BLACK) end
            end
        end
        if not self.info.done and cells[self.ccur] then
            local cx, cy = x + b.x + ((self.ccur - 1) % cw.cols) * b.cell, y + b.y + math.floor((self.ccur - 1) / cw.cols) * b.cell
            bb:paintBorder(cx + 1, cy + 1, b.cell - 1, b.cell - 1, S(3), Blitbuffer.COLOR_BLACK)
        end
        local cl = self.clue
        cl.head:paintTo(bb, x + cl.x, y + cl.y)
        cl.body:paintTo(bb, x + cl.x + cl.head:getSize().w + S(10), y + cl.y)
        if self.cpad then
            local p = self.cpad
            local psize = math.max(8, math.floor(p.w * 0.42 * 160 / Screen:getDPI() + 0.5))
            for i, k in ipairs(p.keys) do
                local kx, ky = x + p.x + ((i - 1) % 14) * p.w, y + p.y + math.floor((i - 1) / 14) * (p.h + S(4))
                bb:paintBorder(kx + 1, ky, p.w - 2, p.h, 1, Blitbuffer.COLOR_BLACK, S(4))
                centred(bb, self:glyph(k.text, k.check and math.floor(psize * 0.8) or psize, true), kx, ky, p.w)
            end
        end
        if self.clues then
            for _i, r in ipairs(self.clues.rows) do
                r.widget:paintTo(bb, x + self.clues.x + (r.col - 1) * self.clues.col_w, y + self.clues.y + r.line * self.clues.line_h)
            end
        end
    end

    function Page:paintScramble(bb, x, y)
        local b, e = self.board, self.sc.words[self.sc.at]
        local size = math.max(10, math.floor(b.cell * 0.5 * 160 / Screen:getDPI() + 0.5))
        local done = e.cur == e.w
        for i = 1, b.n do
            local tx, ty = x + b.x + (i - 1) * b.cell, y + b.y
            local pad = math.max(2, math.floor(b.cell / 14))
            if done then bb:paintRect(tx + pad, ty + pad, b.cell - pad * 2, b.cell - pad * 2, Blitbuffer.COLOR_GRAY_E) end
            bb:paintBorder(tx + pad, ty + pad, b.cell - pad * 2, b.cell - pad * 2, math.max(1, S(1)), Blitbuffer.COLOR_BLACK, S(6))
            centred(bb, self:glyph(e.cur:sub(i, i), size, true), tx, ty, b.cell)
            if self.tsel == i then bb:invertRect(tx + pad + 2, ty + pad + 2, b.cell - pad * 2 - 4, b.cell - pad * 2 - 4) end
            if self.keys and self.tcur == i and not done then
                hline(bb, tx + pad, ty + b.cell + S(3), b.cell - pad * 2, S(3))
            end
        end
        self.sclue.widget:paintTo(bb, x + self.sclue.x, y + self.sclue.y)
        local l = self.slist
        for i, r in ipairs(l.rows) do
            local ry = y + l.y + (i - 1) * l.row_h
            if i == self.sc.at then bb:paintRect(x + l.x, ry, l.w, l.row_h - S(4), Blitbuffer.COLOR_GRAY_E) end
            r.widget:paintTo(bb, x + l.x + S(8), ry + S(5))
        end
        if self.hint then
            local g = self.hint
            bb:paintBorder(x + g.x, y + g.y, g.w, g.h, 1, Blitbuffer.COLOR_BLACK, S(4))
            g.widget:paintTo(bb, x + g.x + S(10), y + g.y + S(4))
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
        elseif self.kind == "cross" then self:paintCross(bb, x, y)
        elseif self.kind == "scramble" then self:paintScramble(bb, x, y)
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
        if not was then pcall(P().began, self.pz, self.kind) end
        self:build()
        self:redraw(full or (self.info.done and not was))
        if self.info.done and not was then
            require("gzreader_log").info((self.set and "game board: " or "daily puzzles: ") .. self.kind .. " solved")
            local Paper = require("gzreader_dailyscreen")
            if Paper.instance and not Paper.instance.closed then pcall(function() Paper.instance:build() end) end
            -- (into the game board's history; an achievement unlocked is shown)
            local ok, new = pcall(function() return require("gzreader_gameboard").solved(self.pz, self.kind) end)
            if ok and type(new) == "table" and #new > 0 then Screen_.unlocked(new) end
            local Board = package.loaded["gzreader_gameboardscreen"]
            if Board and Board.instance and not Board.instance.closed then pcall(function() Board.instance:rebuild() end) end
        end
    end

    function Page:show(kind)
        if kind == self.kind then return true end
        self.kind = kind
        self.wsel, self.wrong, self.checked, self.note, self.drag, self.tsel = nil, nil, nil, nil, nil, nil
        self:build()
        self:redraw(true)
        return true
    end

    function Page:step(by)
        local kinds = self.kinds
        for i, k in ipairs(kinds) do
            if k == self.kind then return self:show(kinds[(i - 1 + by) % #kinds + 1]) end
        end
    end

    ---------------------------------------------------------------- moves

    function Page:write(v)
        if self.kind ~= "sudoku" or self.info.done or not self.cur then return true end
        if P().sudokuSet(self.pz, self.cur, v) then
            if self.wrong then self.wrong[self.cur] = nil end
            self.checked = nil
            self:changed()
        end
        return true
    end

    --- The crossword: a square chosen (the one you're on again: turn from across to down).
    function Page:square(cell)
        local c = self.ccells[cell]
        if not c or self.info.done then return true end
        if cell == self.ccur and c.a and c.d then
            self.cdir = self.cdir == "a" and "d" or "a"
        else
            self.ccur = cell
            if not c[self.cdir] then self.cdir = c.a and "a" or "d" end
        end
        self:changed()
        return true
    end

    --- The crossword: a letter written where you are (then on to the word's next square), or rubbed out.
    function Page:letterIn(letter)
        if self.kind ~= "cross" or self.info.done then return true end
        local Pz = P()
        local step = self.cdir == "a" and 1 or self.cw.cols
        if letter then
            Pz.crossSet(self.pz, self.ccur, letter)
            local nxt = self.ccur + step
            if self.ccells[nxt] and self.ccells[nxt][self.cdir] == self.ccells[self.ccur][self.cdir] then self.ccur = nxt end
        elseif not Pz.crossSet(self.pz, self.ccur, "") then
            -- (already empty: back a square, and that one rubbed out)
            local prev = self.ccur - step
            if self.ccells[prev] and self.ccells[prev][self.cdir] == self.ccells[self.ccur][self.cdir] then
                self.ccur = prev
                Pz.crossSet(self.pz, prev, "")
            end
        end
        self.checked = nil
        self:changed()
        return true
    end

    --- Every clue, in a window (the touch page shows only the one you're in).
    function Page:allClues()
        local TextViewer = require("ui/widget/textviewer")
        UIManager:show(TextViewer:new{ title = _("Crossword clues"), text = Screen_.clueList(self.cw), justified = false })
        return true
    end

    function Page:check()
        if (self.kind == "cross" or self.kind == "sudoku") and not self.info.done then pcall(P().helped, self.pz, self.kind) end
        if self.kind == "cross" and not self.info.done then
            self.checked = true
            self:changed()
            return true
        end
        if self.kind ~= "sudoku" or self.info.done then return true end
        self.wrong = P().sudokuWrong(self.sudoku)
        self.checked = true
        self:changed()
        return true
    end

    function Page:startAgain()
        if self.kind == "sudoku" then
            P().sudokuClear(self.pz)
            self.wrong, self.checked, self.cur = nil, nil, nil
        elseif self.kind == "maze" then
            P().mazeClear(self.pz)
        elseif self.kind == "cross" then
            P().crossClear(self.pz)
            self.checked, self.ccur = nil, nil
        elseif self.kind == "scramble" then
            P().scrambleClear(self.pz)
            self.tsel, self.tcur = nil, nil
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
            if n and Pz.wordFound(self.pz, n) then
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
        local path = P().mazeMove(self.pz, self.board.n, self.board.rows, side)
        if #path > 0 then self:changed() end
        return true
    end

    --- The scramble: a letter chosen; a second swaps the two.
    function Page:tile(i)
        if self.info.done then return true end
        local e = self.sc.words[self.sc.at]
        if e.cur == e.w then return true end
        if not self.tsel then
            self.tsel = i
            self:redraw()
            return true
        end
        if self.tsel == i then self.tsel = nil; self:redraw(); return true end
        local a = self.tsel
        self.tsel = nil
        local spelled = select(2, P().scrambleSwap(self.pz, a, i))
        if spelled then self.tcur = 1 end
        self:changed(spelled)
        return true
    end

    function Page:toWord(n)
        if P().scrambleGo(self.pz, n) then
            self.tsel, self.tcur = nil, 1
            self:changed(true)
        end
        return true
    end

    function Page:hintNow()
        if self.kind ~= "scramble" or self.info.done then return true end
        self.tsel = nil
        P().scrambleHint(self.pz)
        self:changed()
        return true
    end

    ---------------------------------------------------------------- keys

    function Page:onPzClose() UIManager:close(self, "full"); return true end
    function Page:onPzNextTab() return self:step(1) end
    function Page:onPzPrevTab() return self:step(-1) end
    function Page:onPzNumber(n)
        if self.kind == "cross" then return n == 0 and self:letterIn(nil) or true end
        return self:write(n)
    end
    --- A letter key: in the crossword, that letter. Elsewhere Q–O are 1–9 (the
    --- keys under the numbers), P rubs out, C checks, N starts again.
    function Page:onPzKey(letter)
        if self.kind == "cross" then return self:letterIn(letter) end
        if self.kind == "scramble" then
            if letter == "H" then return self:hintNow() end
            if letter == "N" then return self:startAgain() end
            return true
        end
        local n = ("QWERTYUIO"):find(letter, 1, true)
        if n then return self:write(n) end
        if letter == "P" then return self:write(0) end
        if letter == "C" then return self:check() end
        if letter == "N" then return self:startAgain() end
        return true
    end
    function Page:onPzPanel() return require("gzreader_dailyscreen").openPanel(self.plugin, "Menu") end

    function Page:onPzMove(side)
        local d = P().SIDES[side]
        if self.kind == "maze" then return self:go(side) end
        if self.kind == "scramble" then
            if side == "n" or side == "s" then
                local n = #self.sc.words
                return self:toWord((self.sc.at - 1 + (side == "s" and 1 or -1)) % n + 1)
            end
            self.tcur = (self.tcur - 1 + (side == "e" and 1 or -1)) % self.board.n + 1
            self:redraw()
            return true
        end
        if self.kind == "cross" then
            if self.info.done then return true end
            local to = Screen_.crossStep(self.ccells, self.cw.cols, self.cw.rows, self.ccur, side)
            if to then
                self.ccur = to
                -- (moving along a word is reading it that way)
                local want = (side == "e" or side == "w") and "a" or "d"
                if self.ccells[to][want] then self.cdir = want elseif not self.ccells[to][self.cdir] then self.cdir = want == "a" and "d" or "a" end
                self:changed()
            end
            return true
        end
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
        if self.kind == "scramble" then return self:tile(self.tcur) end
        if self.kind == "sudoku" then
            if self.info.done or self.sudoku.given:sub(self.cur, self.cur) ~= "0" then return true end
            return self:write((tonumber(self.sudoku.fill:sub(self.cur, self.cur)) + 1) % 10)
        elseif self.kind == "words" then
            return self:letter(self.wcur[1], self.wcur[2])
        elseif self.kind == "cross" then
            if self.info.done then return true end
            -- a keyboard writes with its letters, so Press turns; without one, Press is the next letter
            if self.keyboard then return self:square(self.ccur) end
            local ch = self.cfill:sub(self.ccur, self.ccur)
            local nxt = ch == "." and "A" or ch == "Z" and "" or string.char(ch:byte() + 1)
            P().crossSet(self.pz, self.ccur, nxt)
            self.checked = nil
            self:changed()
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
        local cp = self.cpad
        if cp and px >= cp.x and py >= cp.y - S(2) and py < cp.y + (cp.h + S(4)) * 2 then
            local k = cp.keys[math.floor((py - cp.y + S(2)) / (cp.h + S(4))) * 14 + math.floor((px - cp.x) / cp.w) + 1]
            if k and px < cp.x + cp.w * 14 then return { "pad", k } end
        end
        local sl = self.slist
        if sl and px >= sl.x and px < sl.x + sl.w and py >= sl.y and py < sl.y + #sl.rows * sl.row_h then
            return { "word", math.floor((py - sl.y) / sl.row_h) + 1 }
        end
        local hn = self.hint
        if hn and px >= hn.x - S(6) and px < hn.x + hn.w + S(6) and py >= hn.y - S(6) and py < hn.y + hn.h + S(6) then return { "hint" } end
        local cl = self.clue
        if cl and px >= cl.x and px < cl.x + cl.w and py >= cl.y - S(4) and py < cl.y + cl.h + S(4) then return { "clue" } end
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
        if what[1] == "clue" then return self:allClues() end
        if what[1] == "word" then return self:toWord(what[2]) end
        if what[1] == "hint" then return self:hintNow() end
        if what[1] == "pad" then
            if what[2].check then return self:check() end
            if what[2].letter then return self:letterIn(what[2].letter) end
            if what[2].rub then return self:letterIn(nil) end
            return self:write(what[2].value)
        end
        if self.kind == "cross" then return self:square((what[3] - 1) * self.cw.cols + what[2]) end
        if self.kind == "scramble" then return self:tile(what[2]) end
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
        if n and Pz.wordFound(self.pz, n) then
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

--- Achievements just unlocked, said for a moment.
function Screen_.unlocked(list)
    local names = {}
    for _i, a in ipairs(list) do names[#names + 1] = "\u{2605} " .. a.title .. "\n" .. a.text end
    UIManager:show(require("ui/widget/infomessage"):new{
        text = (#list == 1 and _("Achievement unlocked") or _("Achievements unlocked")) .. "\n\n" .. table.concat(names, "\n\n"),
        timeout = 4 })
end

--- Open the day's puzzles (at one of them: "sudoku", "words", "maze"), or
--- with opts.set a game board's themed set (gzreader_gameboard.lua);
--- opts.kinds: only these of the paper's puzzles, as tabs (the game board's).
function Screen_.show(plugin, kind, opts)
    if Screen_.instance and not Screen_.instance.closed then return Screen_.instance end
    local set = opts and opts.set
    -- (a word puzzle not started is made again if the paper has been fetched since)
    if not set then pcall(function() P().freshen(plugin) end) end
    local pz = set and P().forSet(plugin, set) or plugin
    local kinds = (not set and opts and type(opts.kinds) == "table" and opts.kinds) or P().kindsOf(pz)
    local want = kind
    local offered = false
    for _i, k in ipairs(kinds) do if k == want then offered = true end end
    if not offered then want = kinds[1] end
    local self = pageClass():new{ plugin = plugin, pz = pz, set = set, kind = want, kinds = kinds }
    Screen_.instance = self
    UIManager:show(self)
    return self
end

return Screen_
