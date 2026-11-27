-- The daily paper's puzzles (gzreader_puzzles.lua, gzreader_puzzlescreen.lua):
-- the paper's foot, the puzzles page, a sudoku square written, a word found,
-- the maze walked, each kept. Touch models: taps; k3: real key presses.
--   GZ_EMU_MODEL=pw3|k3 GZ_EMU_TREE=<tree>/koreader ./run.sh daily_puzzles.lua <out>
-- Checks in <out>/puzzles-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local KEYS = os.getenv("GZ_EMU_MODEL") == "k3" or not os.getenv("GZ_EMU_MODEL")
add({ fn = function()
    local UIM = require("ui/uimanager")
    for i = #UIM._window_stack, 1, -1 do
        local w = UIM._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM:close(w) end
    end
end, after = 6 })
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local checks = {}
local function check(E, ok, msg)
    checks[#checks + 1] = (ok and "ok   " or "FAIL ") .. msg
    E.say(checks[#checks])
end
local function tap(page, x, y) page:onPzTap(nil, { pos = { x = x, y = y } }) end

add({ fn = function(E)
    local p = plugin()
    local D = require("gzreader_daily")
    local st = D.store(p)
    st.enabled = true
    st.puzzles = nil
    -- (no fetch: an edition given here)
    D.fetch = function() return nil, "offline" end
    local Paper = require("gzreader_dailyscreen")
    local page = Paper.show(p)
    E.paper = page
    check(E, page.foot.puzzles ~= nil and Paper.puzzlesLabel(p) == "Puzzles", "Puzzles at the foot of the paper")
    local f = page.foot
    check(E, f.puzzles.x + f.puzzles.w <= page.dimen.w * 0.5 and f.puzzles.x >= f.type.x + f.type.widget:getSize().w,
        "…beside Aa, clear of the page arrows (" .. f.puzzles.x .. "+" .. f.puzzles.w .. " of " .. page.dimen.w .. ")")
    check(E, page:at(f.puzzles.x + 6, f.y + 6) == "puzzles" and page:at(f.type.x + 2, f.y + 6) == "type", "a tap there is Puzzles; Aa is still Aa")
end, after = 5 })
add({ shot = "puzzles-0-paper" })
if KEYS then
    -- the 5-way to the foot's Puzzles, Press
    add({ fn = function(E)
        E.paper.focus = #E.paper.blocks + 1
        E.paper:redraw()
    end, after = 3 })
    add({ key = "Down", after = 3 })
    add({ shot = "puzzles-0b-focus" })
    add({ key = "Press", after = 6 })
else
    add({ fn = function(E)
        local f = E.paper.foot
        E.paper:onGzTap(nil, { pos = { x = f.puzzles.x + 6, y = f.y + 6 } })
    end, after = 6 })
end
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    E.pz = Scr.instance
    check(E, E.pz ~= nil and E.pz.kind == "sudoku", "it opens the puzzles page at the sudoku")
    local b = E.pz.board
    check(E, b.x >= 0 and b.x + b.w <= E.pz.dimen.w and b.y + b.h < E.pz.status.y and E.pz.status.y < E.pz.foot.y, "the grid, the status line and the foot don't overlap")
    if E.pz.pad then check(E, E.pz.pad.y >= b.y + b.h and E.pz.pad.y + E.pz.pad.h <= E.pz.status.y, "the numbers sit between the grid and the status line") end
end, after = 3 })
add({ shot = "puzzles-1-sudoku" })
-- write the right number in the first empty square, a wrong one in the next, check
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local pz = E.pz
    local s0 = Pz.daySudoku(plugin())
    local first = s0.fill:find("0", 1, true)
    local second = s0.fill:find("0", first + 1, true)
    E.first, E.second = first, second
    E.right = tonumber(s0.answer:sub(first, first))
    E.bad = tonumber(s0.answer:sub(second, second)) % 9 + 1
    if not KEYS then
        local b, p = pz.board, pz.pad
        tap(pz, b.x + ((first - 1) % 9) * b.cell + 5, b.y + math.floor((first - 1) / 9) * b.cell + 5)
        tap(pz, p.x + (E.right - 1) * p.w + 5, p.y + 5)
        tap(pz, b.x + ((second - 1) % 9) * b.cell + 5, b.y + math.floor((second - 1) / 9) * b.cell + 5)
        tap(pz, p.x + (E.bad - 1) * p.w + 5, p.y + 5)
        tap(pz, p.x + 10 * p.w + 5, p.y + 5)
    else
        pz.cur = first
    end
end, after = 3 })
if KEYS then
    -- (the cursor is on the first empty square: its number's letter key; then to the next, a wrong one; C checks)
    add({ fn = function(E) E.send = ({ "Q", "W", "E", "R", "T", "Y", "U", "I", "O" }) end, after = 1 })
    add({ fn = function(E) E.key(E.send[E.right]) end, after = 3 })
    add({ fn = function(E) E.pz.cur = E.second; E.pz:redraw() end, after = 2 })
    add({ fn = function(E) E.key(E.send[E.bad]) end, after = 3 })
    add({ key = "C", after = 4 })
end
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local s1 = Pz.daySudoku(plugin())
    check(E, s1.fill:sub(E.first, E.first) == tostring(E.right) and s1.fill:sub(E.second, E.second) == tostring(E.bad), "two squares written (" .. (KEYS and "letter keys" or "taps") .. ")")
    check(E, E.pz.wrong and E.pz.wrong[E.second] and not E.pz.wrong[E.first] and E.pz.info.wrong == 1, "Check marks the wrong one only")
end, after = 2 })
add({ shot = "puzzles-2-sudoku-checked" })
-- the word search
if KEYS then add({ key = "RPgFwd", after = 5 }) else add({ fn = function(E) tap(E.pz, E.pz.tabs[2].x + 10, E.pz.tabs[2].y + 5) end, after = 5 }) end
add({ fn = function(E)
    local pz = E.pz
    check(E, pz.kind == "words" and pz.ws and #pz.ws.words == 8, "the next puzzle: the word search, eight words")
    local w = pz.ws.words[1]
    local b = pz.board
    local ex, ey = w.x + w.dx * (#w.word - 1), w.y + w.dy * (#w.word - 1)
    if KEYS then
        pz.wcur = { w.x, w.y }; pz:onPzPress()
        pz.wcur = { ex, ey }; pz:onPzPress()
    else
        tap(pz, b.x + (w.x - 1) * b.cell + 5, b.y + (w.y - 1) * b.cell + 5)
        tap(pz, b.x + (ex - 1) * b.cell + 5, b.y + (ey - 1) * b.cell + 5)
    end
    check(E, pz.found[1] == true and pz.info.found == 1, "a word's first and last letter: found (" .. w.word .. ")")
    local l = pz.list
    check(E, l.y + l.line_h * 2 <= pz.status.y and l.y >= b.y + b.h, "the words fit under the letters")
    -- a first letter chosen, for the picture
    local w2 = pz.ws.words[2]
    if KEYS then pz.wcur = { w2.x, w2.y }; pz:onPzPress() else tap(pz, b.x + (w2.x - 1) * b.cell + 5, b.y + (w2.y - 1) * b.cell + 5) end
end, after = 4 })
add({ shot = "puzzles-3-words" })
-- the maze
if KEYS then add({ key = "RPgFwd", after = 5 }) else add({ fn = function(E) tap(E.pz, E.pz.tabs[3].x + 10, E.pz.tabs[3].y + 5) end, after = 5 }) end
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local pz = E.pz
    check(E, pz.kind == "maze" and pz.at == 1, "the maze, at its start")
    E.side = Pz.mazeOpen(pz.mz, 1, "e") and "e" or "s"
    if not KEYS then
        local cx, cy = pz:cellXY(1)
        if E.side == "e" then tap(pz, cx + pz.board.cell * 3, cy + 4) else tap(pz, cx + 4, cy + pz.board.cell * 3) end
    end
end, after = 3 })
if KEYS then add({ fn = function(E) E.key(E.side == "e" and "Right" or "Down") end, after = 4 }) end
add({ fn = function(E)
    local pz = E.pz
    check(E, pz.at ~= 1 and pz.seen[1] and pz.seen[pz.at], "a step that way: the dot moved, its trail kept (now at " .. tostring(pz.at) .. ")")
    local b = pz.board
    check(E, b.x >= 0 and b.x + b.w <= pz.dimen.w and b.y + b.h + b.cell / 2 <= pz.status.y, "the maze fits (" .. b.n .. " × " .. b.rows .. ")")
end, after = 2 })
add({ shot = "puzzles-4-maze" })
-- walk it to the end (the way found here), for the solved look
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local pz = E.pz
    local mz = pz.mz
    local goal = mz.cols * mz.rows
    local prev, queue, head = { [pz.at] = 0 }, { pz.at }, 1
    local step = { n = -mz.cols, s = mz.cols, e = 1, w = -1 }
    while queue[head] do
        local at = queue[head]; head = head + 1
        for side, d in pairs(step) do
            if Pz.mazeOpen(mz, at, side) and not prev[at + d] then prev[at + d] = at; queue[#queue + 1] = at + d end
        end
    end
    local route, at = {}, goal
    while at ~= pz.at do table.insert(route, 1, at); at = prev[at] end
    local guard = 0
    while pz.at ~= goal and guard < 2000 do
        guard = guard + 1
        -- (the next square of the route from here)
        local nxt = route[1]
        for i, c in ipairs(route) do if c == pz.at then nxt = route[i + 1] end end
        local d = nxt - pz.at
        pz:go(d == 1 and "e" or d == -1 and "w" or d > 0 and "s" or "n")
    end
    check(E, pz.at == goal and pz.info.done, "walked to the way out: solved")
    local n = select(2, Pz.finished(plugin()))
    check(E, n == 1 and require("gzreader_dailyscreen").puzzlesLabel(plugin()) == "Puzzles 1/3", "the paper's foot counts it: Puzzles 1/3")
end, after = 5 })
add({ shot = "puzzles-5-maze-solved" })
-- closed and opened again: everything as left
add({ fn = function(E)
    require("ui/uimanager"):close(E.pz)
end, after = 4 })
add({ shot = "puzzles-6-paper-after" })
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local p = plugin()
    local Scr = require("gzreader_puzzlescreen")
    check(E, Scr.instance == nil, "closed")
    local s1 = Pz.daySudoku(p)
    local found = select(2, Pz.dayWords(p))
    check(E, s1.fill:sub(E.first, E.first) == tostring(E.right) and found[1] == true, "what was done is kept")
    local pz = Scr.show(p, "sudoku")
    check(E, pz.kind == "sudoku" and pz.tabs[3].label.text:find("\u{2713}", 1, true) ~= nil, "opened again: the maze's tab is ticked")
end, after = 4 })
add({ shot = "puzzles-7-again" })
add({ fn = function(E)
    local f = io.open((E.out or ".") .. "/puzzles-checks.txt", "w")
    if f then f:write(table.concat(checks, "\n"), "\n"); f:close() end
end, after = 1 })
return s
