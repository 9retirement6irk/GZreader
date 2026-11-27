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
    -- the 5-way along the foot to Puzzles (Fetch → Aa → Puzzles), and back out; then its letter, P
    add({ fn = function(E)
        E.paper.focus = "fetch"
        E.paper:redraw()
    end, after = 3 })
    add({ key = "Right", after = 3 })
    add({ key = "Right", after = 3 })
    add({ shot = "puzzles-0b-focus" })
    add({ fn = function(E) check(E, E.paper.focus == "puzzles", "Right twice from Fetch: the frame is on Puzzles") end, after = 1 })
    add({ key = "Press", after = 6 })
    add({ fn = function(E)
        local Scr = require("gzreader_puzzlescreen")
        check(E, Scr.instance ~= nil, "Press there opens the puzzles")
        if Scr.instance then require("ui/uimanager"):close(Scr.instance) end
    end, after = 4 })
    add({ key = "P", after = 6 })
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
    if not KEYS then
        -- drawn along: the third word slowly (pan, then release a little past its last letter), the
        -- fourth quickly (a swipe), then a stroke that is no word
        local function mid(cx, cy) return pz.dimen.x + b.x + (cx - 1) * b.cell + math.floor(b.cell / 2), pz.dimen.y + b.y + (cy - 1) * b.cell + math.floor(b.cell / 2) end
        local w3, w4 = pz.ws.words[3], pz.ws.words[4]
        local x1, y1 = mid(w3.x, w3.y)
        local x2, y2 = mid(w3.x + w3.dx * (#w3.word - 1), w3.y + w3.dy * (#w3.word - 1))
        pz:onPzPan(nil, { start_pos = { x = x1, y = y1 }, pos = { x = math.floor((x1 + x2) / 2), y = math.floor((y1 + y2) / 2) } })
        pz:onPzPanRelease(nil, { pos = { x = x2 + math.floor(b.cell * 0.3) * w3.dx, y = y2 + math.floor(b.cell * 0.3) * w3.dy } })
        check(E, pz.found[3] == true, "a word drawn along slowly, ending a little past its last letter: found (" .. w3.word .. ")")
        x1, y1 = mid(w4.x + w4.dx * (#w4.word - 1), w4.y + w4.dy * (#w4.word - 1))
        x2, y2 = mid(w4.x, w4.y)
        pz:onPzSwipe(nil, { direction = "west", pos = { x = x1, y = y1 }, end_pos = { x = x2, y = y2 } })
        check(E, pz.found[4] == true and pz.kind == "words", "a word swiped along backwards: found, and the page didn't change puzzle (" .. w4.word .. ")")
        local before = pz.info.found
        pz:onPzSwipe(nil, { direction = "east", pos = { x = pz.dimen.x + b.x + 3, y = pz.dimen.y + b.y + 3 }, end_pos = { x = pz.dimen.x + b.x + b.cell * 2, y = pz.dimen.y + b.y + 3 } })
        check(E, pz.info.found == before and pz.kind == "words" and pz.note ~= nil and pz.status.widget.text:find("isn't one of the words", 1, true) ~= nil,
            "a stroke that isn't a word: nothing found, and the page says so")
        pz:onPzSwipe(nil, { direction = "west", pos = { x = pz.dimen.x + 5, y = pz.foot.y - 4 }, end_pos = { x = pz.dimen.x + 200, y = pz.foot.y - 4 } })
        check(E, pz.kind == "cross", "a swipe off the letters still changes puzzle")
        pz:show("words")
        b = pz.board
    end
    -- a first letter chosen, for the picture
    local w2 = pz.ws.words[2]
    if KEYS then pz.wcur = { w2.x, w2.y }; pz:onPzPress() else tap(pz, b.x + (w2.x - 1) * b.cell + 5, b.y + (w2.y - 1) * b.cell + 5) end
end, after = 4 })
add({ shot = "puzzles-3-words" })
-- the crossword
if KEYS then add({ key = "RPgFwd", after = 5 }) else add({ fn = function(E) tap(E.pz, E.pz.tabs[3].x + 10, E.pz.tabs[3].y + 5) end, after = 5 }) end
add({ fn = function(E)
    local pz = E.pz
    local b = pz.board
    check(E, pz.kind == "cross" and #pz.cw.words >= 7, "the next puzzle: the crossword (" .. #pz.cw.words .. " words, " .. pz.cw.cols .. " × " .. pz.cw.rows .. ")")
    check(E, b.x >= 0 and b.x + b.w <= pz.dimen.w and b.y + b.h <= pz.clue.y and pz.clue.y + pz.clue.h <= pz.status.y, "the grid, the clue and the status line don't overlap")
    if pz.cpad then
        local p = pz.cpad
        check(E, p.y >= pz.clue.y + pz.clue.h and p.y + (p.h + 4) * 2 <= pz.status.y + 4 and p.x + p.w * 14 <= pz.dimen.w and #p.keys == 28,
            "the letters sit between the clue and the status line, two rows of fourteen")
    else
        check(E, pz.clues ~= nil and #pz.clues.rows >= 4, "the clues are listed under the grid, Across beside Down")
    end
    -- the first across word, written
    local w = pz.cw.words[1]
    E.cross_word = w
    check(E, w.d == "a" and pz.ccur == (w.y - 1) * pz.cw.cols + w.x and pz.clue.head.text == "1 Across" or pz.clue.head.text:find("Across", 1, true) ~= nil,
        "it starts in the first across word, with its clue showing (" .. pz.clue.head.text .. ")")
    if not KEYS then
        local p = pz.cpad
        local function key(letter)
            for i, k in ipairs(p.keys) do
                if k.letter == letter then tap(pz, p.x + ((i - 1) % 14) * p.w + 5, p.y + math.floor((i - 1) / 14) * (p.h + 4) + 5) end
            end
        end
        tap(pz, b.x + (w.x - 1) * b.cell + 5, b.y + (w.y - 1) * b.cell + 5)
        for i = 1, #w.word do key(w.word:sub(i, i)) end
    end
end, after = 3 })
if KEYS then
    for i = 1, 9 do
        add({ fn = function(E) local w = E.cross_word; if i <= #w.word then E.key(w.word:sub(i, i)) end end, after = 2 })
    end
end
add({ shot = "puzzles-3b-crossword" })
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local pz = E.pz
    local w = E.cross_word
    local fill = select(2, Pz.dayCross(plugin()))
    local written = ""
    for i = 0, #w.word - 1 do written = written .. fill:sub((w.y - 1) * pz.cw.cols + w.x + i, (w.y - 1) * pz.cw.cols + w.x + i) end
    check(E, written == w.word, "its letters written one after another (" .. (KEYS and "letter keys" or "taps") .. "): " .. written)
    check(E, pz.ccur == (w.y - 1) * pz.cw.cols + w.x + #w.word - 1 and pz.info.wrong == 0, "the cursor went along the word and stopped at its end; nothing marked wrong")
    -- a wrong letter, checked; then put right
    local last = w.word:sub(-1)
    local bad = last == "Z" and "Y" or "Z"
    pz:letterIn(bad)
    pz:check()
    check(E, pz.cwrong[pz.ccur] == true and pz.info.wrong == 1, "a wrong letter, checked: marked")
    pz:letterIn(last)
    -- turn to the word going down through one of its squares
    local cells = Pz.crossCells(pz.cw)
    local cross
    for i = 0, #w.word - 1 do
        local idx = (w.y - 1) * pz.cw.cols + w.x + i
        if cells[idx].d and not cross then cross = idx end
    end
    if pz.ccur ~= cross then pz:square(cross) end
    pz:square(cross)
    check(E, pz.cdir == "d" and pz.clue.head.text:find("Down", 1, true) ~= nil, "the same square chosen again: the word going down, and its clue (" .. pz.clue.head.text .. ")")
end, after = 3 })
add({ shot = "puzzles-3c-crossword-down" })
-- the maze
if KEYS then add({ key = "RPgFwd", after = 5 }) else add({ fn = function(E) tap(E.pz, E.pz.tabs[4].x + 10, E.pz.tabs[4].y + 5) end, after = 5 }) end
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
    check(E, n == 1 and require("gzreader_dailyscreen").puzzlesLabel(plugin()) == "Puzzles 1/4", "the paper's foot counts it: Puzzles 1/4")
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
    check(E, pz.kind == "sudoku" and pz.tabs[4].label.text:find("\u{2713}", 1, true) ~= nil and #pz.tabs == 4, "opened again: the maze's tab is ticked")
end, after = 4 })
add({ shot = "puzzles-7-again" })
-- with a paper: the word search hides the stories' words (an example edition; nothing is fetched)
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local Scr = require("gzreader_puzzlescreen")
    local p = plugin()
    if Scr.instance then require("ui/uimanager"):close(Scr.instance) end
    Pz.edition = function()
        return { day = Pz.state(p).day, sections = { { topic = "World", items = {
            { title = "Council votes to keep the old bridge open through the winter", text = "Engineers said the bridge was sound. Traffic lights will let one lane cross at a time." },
            { title = "Harvest festival moved indoors", text = "Rain is forecast for the valley all weekend." },
            { title = "Lighthouse keeper counts seven ships in the northern harbour", text = "The keeper kept a tally in a ledger." },
            { title = "A pocket radio that tunes itself", text = "The radio listens for the strongest signal." } } } } }
    end
    Pz.state(p).words = nil
    E.pz = Scr.show(p, "words")
end, after = 6 })
add({ shot = "puzzles-8-news-words" })
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local pz = E.pz
    local known, n = {}, 0
    for _i, e in ipairs(Pz.newsWords(Pz.edition())) do known[e.word] = true end
    local list = {}
    for _i, w in ipairs(pz.ws.words) do list[#list + 1] = w.word; if known[w.word] then n = n + 1 end end
    check(E, pz.ws.src ~= "list" and n == #pz.ws.words, "with a paper, every word the word search hides is from its stories: " .. table.concat(list, " "))
    check(E, pz.status.widget.text:find("from the paper's stories", 1, true) ~= nil, "…and says so")
    Pz.edition = nil
end, after = 2 })
add({ fn = function(E)
    local f = io.open((E.out or ".") .. "/puzzles-checks.txt", "w")
    if f then f:write(table.concat(checks, "\n"), "\n"); f:close() end
end, after = 1 })
return s
