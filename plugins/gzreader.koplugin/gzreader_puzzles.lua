--[[--
The daily paper's puzzles: a sudoku, a word search and a maze, made on the
Kindle from the day's date (no network; the same day gives the same
puzzles), and how far you've got with each (kept until the next day's
paper). The screen is gzreader_puzzlescreen.lua.

Kept in store.daily.puzzles = { off, day, sudoku = { given, answer, fill },
words = { found = "1,4" }, maze = { cols, rows, at, seen } }.
]]

local Puzzles = {
    KINDS = { "sudoku", "words", "maze" },
    WORDS_SIZE = 10,   -- the word search's letters a side
    WORDS_COUNT = 8,
    SUDOKU_GIVEN = 34, -- numbers printed (about; never fewer than it takes for one answer)
}

---------------------------------------------------------------- chance

--- A generator of the day's numbers: the same text always gives the same
--- run (Park–Miller; os's own random isn't the same on every Kindle).
function Puzzles.rng(text)
    local s = 7
    for i = 1, #text do s = (s * 31 + text:byte(i)) % 2147483647 end
    if s == 0 then s = 1 end
    for _i = 1, 5 do s = (s * 16807) % 2147483647 end
    local R = {}
    --- 1..n
    function R.pick(n)
        s = (s * 16807) % 2147483647
        return (s % n) + 1
    end
    function R.shuffle(list)
        for i = #list, 2, -1 do
            local j = R.pick(i)
            list[i], list[j] = list[j], list[i]
        end
        return list
    end
    return R
end

---------------------------------------------------------------- sudoku

local function boxOf(r, c) return math.floor(r / 3) * 3 + math.floor(c / 3) end

--- How many answers a grid (81 numbers, 0 = empty) has, counted up to `limit`.
function Puzzles.sudokuCount(cells, limit)
    local bit = require("bit")
    local rows, cols, boxes, g = {}, {}, {}, {}
    for i = 0, 8 do rows[i], cols[i], boxes[i] = 0, 0, 0 end
    for i = 1, 81 do
        local v = cells[i]
        g[i] = v
        if v ~= 0 then
            local r, c = math.floor((i - 1) / 9), (i - 1) % 9
            local m = bit.lshift(1, v)
            if bit.band(rows[r], m) ~= 0 or bit.band(cols[c], m) ~= 0 or bit.band(boxes[boxOf(r, c)], m) ~= 0 then return 0 end
            rows[r], cols[c], boxes[boxOf(r, c)] = bit.bor(rows[r], m), bit.bor(cols[c], m), bit.bor(boxes[boxOf(r, c)], m)
        end
    end
    local count = 0
    local function go()
        -- (the empty cell with the fewest numbers that fit)
        local best, best_n, best_used
        for i = 1, 81 do
            if g[i] == 0 then
                local r, c = math.floor((i - 1) / 9), (i - 1) % 9
                local used = bit.bor(rows[r], cols[c], boxes[boxOf(r, c)])
                local n = 0
                for v = 1, 9 do if bit.band(used, bit.lshift(1, v)) == 0 then n = n + 1 end end
                if n == 0 then return end
                if not best or n < best_n then best, best_n, best_used = i, n, used end
                if n == 1 then break end
            end
        end
        if not best then count = count + 1; return end
        local r, c = math.floor((best - 1) / 9), (best - 1) % 9
        local b = boxOf(r, c)
        for v = 1, 9 do
            local m = bit.lshift(1, v)
            if bit.band(best_used, m) == 0 then
                g[best] = v
                rows[r], cols[c], boxes[b] = bit.bor(rows[r], m), bit.bor(cols[c], m), bit.bor(boxes[b], m)
                go()
                rows[r], cols[c], boxes[b] = bit.band(rows[r], bit.bnot(m)), bit.band(cols[c], bit.bnot(m)), bit.band(boxes[b], bit.bnot(m))
                g[best] = 0
                if count >= limit then return end
            end
        end
    end
    go()
    return count
end

--- A day's sudoku: { given = "81 digits, 0 where you write", answer = "81 digits" }.
--- One answer only. Numbers are taken out two at a time, opposite each other.
function Puzzles.sudoku(seed)
    local R = Puzzles.rng("sudoku:" .. seed)
    -- a full grid: the plain pattern with its bands, rows, columns and numbers shuffled
    local function order()
        local out = {}
        for _i, band in ipairs(R.shuffle({ 0, 1, 2 })) do
            for _j, k in ipairs(R.shuffle({ 0, 1, 2 })) do out[#out + 1] = band * 3 + k end
        end
        return out
    end
    local rs, cs, nums = order(), order(), R.shuffle({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
    local answer = {}
    for r = 1, 9 do
        for c = 1, 9 do
            answer[(r - 1) * 9 + c] = nums[(3 * (rs[r] % 3) + math.floor(rs[r] / 3) + cs[c]) % 9 + 1]
        end
    end
    local given, left = {}, 81
    for i = 1, 81 do given[i] = answer[i] end
    local spots = {}
    for i = 1, 41 do spots[i] = i end
    R.shuffle(spots)
    for _i, a in ipairs(spots) do
        if left <= Puzzles.SUDOKU_GIVEN then break end
        local b = 82 - a
        local va, vb = given[a], given[b]
        given[a], given[b] = 0, 0
        if Puzzles.sudokuCount(given, 2) == 1 then
            left = left - (a == b and 1 or 2)
        else
            given[a], given[b] = va, vb
        end
    end
    return { given = table.concat(given), answer = table.concat(answer) }
end

---------------------------------------------------------------- word search

-- (plain, friendly words of 4 to 8 letters)
Puzzles.WORD_LIST = {
    "ANCHOR", "APPLE", "ATLAS", "AUTUMN", "BAKERY", "BALLOON", "BASKET", "BEACON", "BICYCLE", "BLANKET",
    "BOTTLE", "BRANCH", "BRIDGE", "BUTTON", "CABIN", "CACTUS", "CAMERA", "CANDLE", "CANOE", "CANYON",
    "CARPET", "CASTLE", "CELLAR", "CHERRY", "CHIMNEY", "CIRCLE", "CLOUD", "CLOVER", "COFFEE", "COMET",
    "COMPASS", "COPPER", "CORNER", "COTTON", "CRAYON", "CUSHION", "DAISY", "DESERT", "DINNER", "DOLPHIN",
    "DRAGON", "DRAWER", "EAGLE", "ECHO", "ELBOW", "ENGINE", "FABLE", "FALCON", "FEATHER", "FERRY",
    "FIDDLE", "FLOWER", "FOREST", "FOSSIL", "FOX", "GARDEN", "GINGER", "GLACIER", "GOBLET", "GRAVEL",
    "GUITAR", "HAMMER", "HARBOR", "HARVEST", "HAZEL", "HELMET", "HERON", "HONEY", "HORIZON", "ISLAND",
    "IVORY", "JACKET", "JIGSAW", "JUNGLE", "KETTLE", "KITCHEN", "LADDER", "LAGOON", "LANTERN", "LEMON",
    "LETTER", "LIBRARY", "LIZARD", "MAGNET", "MAPLE", "MARBLE", "MARKET", "MEADOW", "MIRROR", "MITTEN",
    "MONSOON", "MORNING", "MUSEUM", "NEEDLE", "NOVEL", "OCEAN", "OLIVE", "ORANGE", "ORCHARD", "OTTER",
    "OYSTER", "PADDLE", "PARROT", "PEBBLE", "PENCIL", "PEPPER", "PIANO", "PICNIC", "PIGEON", "PILLOW",
    "PLANET", "POCKET", "POTTERY", "PUDDLE", "PUMPKIN", "PUZZLE", "QUARTZ", "QUILT", "RABBIT", "RAVEN",
    "RIBBON", "RIVER", "ROCKET", "SADDLE", "SAILOR", "SALMON", "SANDAL", "SCARF", "SHADOW", "SIGNAL",
    "SILVER", "SKETCH", "SPARROW", "SPIDER", "SPONGE", "SQUARE", "STABLE", "STREAM", "SUMMER", "SUNSET",
    "TEAPOT", "THIMBLE", "THUNDER", "TICKET", "TIMBER", "TRACTOR", "TULIP", "TUNNEL", "TURTLE", "UMBRELLA",
    "VALLEY", "VELVET", "VIOLIN", "VOYAGE", "WAGON", "WALNUT", "WHISTLE", "WILLOW", "WINDOW", "WINTER",
}

-- (across, down, both diagonals; and backwards)
local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 }, { -1, 0 }, { 0, -1 } }

--- A day's word search: { size, grid = "size × size letters, row by row",
--- words = { { word, x, y, dx, dy } } } (x, y from 1: where its first letter is).
function Puzzles.wordSearch(seed, size, count)
    size, count = size or Puzzles.WORDS_SIZE, count or Puzzles.WORDS_COUNT
    local R = Puzzles.rng("words:" .. seed)
    local pool = {}
    for _i, w in ipairs(Puzzles.WORD_LIST) do if #w >= 4 and #w <= size - 2 then pool[#pool + 1] = w end end
    R.shuffle(pool)
    local cells, words = {}, {}
    local function fits(w, x, y, dx, dy)
        local ex, ey = x + dx * (#w - 1), y + dy * (#w - 1)
        if ex < 1 or ex > size or ey < 1 or ey > size then return false end
        for i = 1, #w do
            local at = cells[(y + dy * (i - 1) - 1) * size + x + dx * (i - 1)]
            if at and at ~= w:sub(i, i) then return false end
        end
        return true
    end
    for _i, w in ipairs(pool) do
        if #words >= count then break end
        for _try = 1, 60 do
            local d = DIRS[R.pick(#DIRS)]
            local x, y = R.pick(size), R.pick(size)
            if fits(w, x, y, d[1], d[2]) then
                for i = 1, #w do cells[(y + d[2] * (i - 1) - 1) * size + x + d[1] * (i - 1)] = w:sub(i, i) end
                words[#words + 1] = { word = w, x = x, y = y, dx = d[1], dy = d[2] }
                break
            end
        end
    end
    local out = {}
    for i = 1, size * size do out[i] = cells[i] or string.char(64 + R.pick(26)) end
    table.sort(words, function(a, b) return a.word < b.word end)
    return { size = size, grid = table.concat(out), words = words }
end

--- The cells from one to another when they're in a line (across, down or a
--- diagonal): { { x, y }, … }, or nil.
function Puzzles.line(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    if not (dx == 0 or dy == 0 or math.abs(dx) == math.abs(dy)) then return nil end
    local n = math.max(math.abs(dx), math.abs(dy))
    local sx, sy = dx == 0 and 0 or dx / math.abs(dx), dy == 0 and 0 or dy / math.abs(dy)
    local out = {}
    for i = 0, n do out[#out + 1] = { x1 + sx * i, y1 + sy * i } end
    return out
end

--- Which of the puzzle's words lies exactly from one cell to another (either
--- way round): its number, or nil.
function Puzzles.wordAt(ws, x1, y1, x2, y2)
    for i, w in ipairs(ws.words) do
        local ex, ey = w.x + w.dx * (#w.word - 1), w.y + w.dy * (#w.word - 1)
        if (w.x == x1 and w.y == y1 and ex == x2 and ey == y2) or (w.x == x2 and w.y == y2 and ex == x1 and ey == y1) then return i end
    end
end

---------------------------------------------------------------- maze

-- A cell's open sides, added up: north 1, east 2, south 4, west 8.
Puzzles.SIDES = { n = { 1, 0, -1, 4 }, e = { 2, 1, 0, 8 }, s = { 4, 0, 1, 1 }, w = { 8, -1, 0, 2 } }

--- A day's maze: { cols, rows, cells = { open sides of each cell, row by row } }.
--- Every cell can be reached; there is one way between any two. In at the
--- top left, out at the bottom right.
function Puzzles.maze(seed, cols, rows)
    local bit = require("bit")
    local R = Puzzles.rng("maze:" .. seed .. ":" .. cols .. "x" .. rows)
    local cells, seen = {}, {}
    for i = 1, cols * rows do cells[i] = 0 end
    local stack = { 1 }
    seen[1] = true
    local names = { "n", "e", "s", "w" }
    while #stack > 0 do
        local at = stack[#stack]
        local x, y = (at - 1) % cols, math.floor((at - 1) / cols)
        local ways = {}
        for _i, name in ipairs(names) do
            local d = Puzzles.SIDES[name]
            local nx, ny = x + d[2], y + d[3]
            if nx >= 0 and nx < cols and ny >= 0 and ny < rows and not seen[ny * cols + nx + 1] then ways[#ways + 1] = d end
        end
        if #ways == 0 then
            stack[#stack] = nil
        else
            local d = ways[R.pick(#ways)]
            local to = (y + d[3]) * cols + x + d[2] + 1
            cells[at] = bit.bor(cells[at], d[1])
            cells[to] = bit.bor(cells[to], d[4])
            seen[to] = true
            stack[#stack + 1] = to
        end
    end
    return { cols = cols, rows = rows, cells = cells }
end

--- Can you step from a cell (its number, from 1) to the side named ("n", "e", "s", "w")?
function Puzzles.mazeOpen(mz, at, side)
    return require("bit").band(mz.cells[at] or 0, Puzzles.SIDES[side][1]) ~= 0
end

--- Walk from a cell towards a side until a wall, a turning or a crossing:
--- the cells passed, in order (none when there's a wall at once).
function Puzzles.mazeWalk(mz, at, side)
    local d = Puzzles.SIDES[side]
    local path = {}
    while Puzzles.mazeOpen(mz, at, side) do
        at = at + d[3] * mz.cols + d[2]
        path[#path + 1] = at
        if at == mz.cols * mz.rows then break end
        -- (a way off to either hand: stop to choose)
        local ways = 0
        for _name, o in pairs(Puzzles.SIDES) do if require("bit").band(mz.cells[at], o[1]) ~= 0 then ways = ways + 1 end end
        if ways > 2 then break end
    end
    return path
end

---------------------------------------------------------------- the day's, and how far you are

local function daily() return require("gzreader_daily") end

-- (a move is kept soon, not at once: a save can take a while on an old Kindle)
local function keep(plugin)
    if type(plugin.saveSoon) == "function" then plugin:saveSoon() else plugin:save() end
end

--- The kept puzzles' table (made empty for a new day).
function Puzzles.state(plugin, day)
    local D = daily()
    local st = D.store(plugin)
    st.puzzles = type(st.puzzles) == "table" and st.puzzles or {}
    local p = st.puzzles
    day = day or D.day()
    if p.day ~= day then
        p.day, p.sudoku, p.words, p.maze = day, nil, nil, nil
    end
    return p
end

function Puzzles.on(plugin)
    local D = daily()
    local p = D.store(plugin).puzzles
    return not (type(p) == "table" and p.off == true)
end

function Puzzles.setOn(plugin, on)
    local p = Puzzles.state(plugin)
    if on then p.off = nil else p.off = true end
    plugin:save()
end

--- The day's sudoku with what you've written: { given, answer, fill } (each
--- 81 digits). Made the first time it's asked for (a few seconds on an old
--- Kindle), then kept for the day.
function Puzzles.daySudoku(plugin, day)
    local p = Puzzles.state(plugin, day)
    local s = p.sudoku
    if not (type(s) == "table" and type(s.given) == "string" and #s.given == 81 and type(s.answer) == "string" and #s.answer == 81) then
        s = Puzzles.sudoku(p.day)
        s.fill = s.given
        p.sudoku = s
        keep(plugin)
    end
    if type(s.fill) ~= "string" or #s.fill ~= 81 then s.fill = s.given end
    return s
end

--- Write a number (0 rubs out) in a cell of the day's sudoku. Printed
--- numbers stay. Returns true when it changed.
function Puzzles.sudokuSet(plugin, i, v)
    local s = Puzzles.daySudoku(plugin)
    if i < 1 or i > 81 or v < 0 or v > 9 or s.given:sub(i, i) ~= "0" or s.fill:sub(i, i) == tostring(v) then return false end
    s.fill = s.fill:sub(1, i - 1) .. tostring(v) .. s.fill:sub(i + 1)
    keep(plugin)
    return true
end

--- The cells written that aren't right: { [cell] = true }.
function Puzzles.sudokuWrong(s)
    local out = {}
    for i = 1, 81 do
        local v = s.fill:sub(i, i)
        if v ~= "0" and v ~= s.answer:sub(i, i) then out[i] = true end
    end
    return out
end

function Puzzles.sudokuDone(s) return s.fill == s.answer end

--- Start the day's sudoku again.
function Puzzles.sudokuClear(plugin)
    local s = Puzzles.daySudoku(plugin)
    s.fill = s.given
    keep(plugin)
end

--- The day's word search and which words are found: ws, { [n] = true }.
function Puzzles.dayWords(plugin, day)
    local p = Puzzles.state(plugin, day)
    local ws = Puzzles.wordSearch(p.day)
    local found = {}
    if type(p.words) == "table" and type(p.words.found) == "string" then
        for n in p.words.found:gmatch("%d+") do
            if ws.words[tonumber(n)] then found[tonumber(n)] = true end
        end
    end
    return ws, found
end

--- Mark a word found. Returns true when it's new.
function Puzzles.wordFound(plugin, n)
    local ws, found = Puzzles.dayWords(plugin)
    if not ws.words[n] or found[n] then return false end
    found[n] = true
    local list = {}
    for i = 1, #ws.words do if found[i] then list[#list + 1] = i end end
    Puzzles.state(plugin).words = { found = table.concat(list, ","), of = #ws.words }
    keep(plugin)
    return true
end

function Puzzles.wordsDone(ws, found)
    for i = 1, #ws.words do if not found[i] then return false end end
    return #ws.words > 0
end

--- The day's maze at a size, with where you are and where you've been:
--- mz, at, { [cell] = true }. (Another size: from the start again.)
function Puzzles.dayMaze(plugin, cols, rows, day)
    local p = Puzzles.state(plugin, day)
    local mz = Puzzles.maze(p.day, cols, rows)
    local m = p.maze
    if not (type(m) == "table" and m.cols == cols and m.rows == rows and type(m.at) == "number" and m.at >= 1 and m.at <= cols * rows) then
        m = { cols = cols, rows = rows, at = 1, seen = "1" }
        p.maze = m
    end
    local seen = {}
    for n in tostring(m.seen or ""):gmatch("%d+") do seen[tonumber(n)] = true end
    seen[m.at] = true
    return mz, m.at, seen
end

--- Walk the day's maze towards a side. Returns the cells passed (none: a wall).
function Puzzles.mazeMove(plugin, cols, rows, side)
    local mz, at, seen = Puzzles.dayMaze(plugin, cols, rows)
    if at == cols * rows then return {} end
    local path = Puzzles.mazeWalk(mz, at, side)
    if #path == 0 then return path end
    for _i, c in ipairs(path) do seen[c] = true end
    local list = {}
    for i = 1, cols * rows do if seen[i] then list[#list + 1] = i end end
    local m = Puzzles.state(plugin).maze
    m.at, m.seen = path[#path], table.concat(list, ",")
    keep(plugin)
    return path
end

function Puzzles.mazeClear(plugin)
    Puzzles.state(plugin).maze = nil
    keep(plugin)
end

--- Which of the day's puzzles are finished, without making any:
--- { sudoku = bool, words = bool, maze = bool }, and how many.
function Puzzles.finished(plugin, day)
    local p = Puzzles.state(plugin, day)
    local out = { sudoku = false, words = false, maze = false }
    if type(p.sudoku) == "table" and p.sudoku.fill and p.sudoku.fill == p.sudoku.answer then out.sudoku = true end
    if type(p.words) == "table" and type(p.words.found) == "string" then
        local n = 0
        for _ in p.words.found:gmatch("%d+") do n = n + 1 end
        out.words = n >= (tonumber(p.words.of) or Puzzles.WORDS_COUNT)
    end
    if type(p.maze) == "table" and p.maze.cols and p.maze.at == p.maze.cols * p.maze.rows then out.maze = true end
    local n = 0
    for _i, k in ipairs(Puzzles.KINDS) do if out[k] then n = n + 1 end end
    return out, n
end

return Puzzles
