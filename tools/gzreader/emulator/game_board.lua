-- The game board (gzreader_gameboard.lua, gzreader_gameboardscreen.lua): on
-- Home's shelf beside the daily paper, picked (its lid), opened; the paper's
-- puzzles from it (the same ones: a word found there is found in the paper);
-- a themed set's word scramble solved (history, an achievement); a book's
-- words read as it closes; the setup guide's page about Home's shelf.
--   GZ_EMU_MODEL=pw3|k3 GZ_EMU_BOOK=<an epub> GZ_EMU_TREE=<tree>/koreader ./run.sh game_board.lua <out>
-- Checks in <out>/game-board-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local TOUCH = os.getenv("GZ_EMU_MODEL") ~= "k3" and os.getenv("GZ_EMU_MODEL") ~= nil
local checks = {}
local function check(E, ok, msg)
    checks[#checks + 1] = (ok and "ok   " or "FAIL ") .. msg
    E.say(checks[#checks])
end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end

add({ fn = function(E)
    -- the setup guide's page about Home's shelf, before it's closed
    local guide
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "setup guide" then guide = w.widget end end
    E.guide = guide
    local at
    for i, page in ipairs(guide and guide.pages or {}) do if page.gz_home_shelf then at = i end end
    check(E, at ~= nil, "the setup guide has a page about Home's shelf")
    if at then
        local page = guide.pages[at]
        check(E, #page.choices == 2 and page.choices[1].id == "gz_paper" and page.choices[2].id == "gz_games" and page.choice_type == "checkbox",
            "… two ticks: the daily paper and the game board")
        guide._page_idx = at
        UIM():setDirty(guide, "full")
    end
end, after = 6 })
add({ shot = "games-0-setup" })
add({ fn = function(E)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    local p = plugin()
    -- both, as the guide would leave them
    require("gzreader_gameboard").applySetup(p, { gz_paper = true, gz_games = true })
    local D = require("gzreader_daily")
    D.fetch = function() return nil, "offline" end
    os.execute("mkdir -p /mnt/us/GZreader")
    local book = os.getenv("GZ_EMU_BOOK")
    if book then
        for _i, name in ipairs({ "one", "two", "three" }) do os.execute("cp " .. book .. " /mnt/us/GZreader/" .. name .. ".epub") end
        for _i, name in ipairs({ "one", "two", "three" }) do require("readhistory"):addItem("/mnt/us/GZreader/" .. name .. ".epub", os.time()) end
    end
    local fm = require("apps/filemanager/filemanager").instance
    local Home = require("common/shared_state").get(fm and fm.zenos, "home")
    Home.invalidateLibraryCache()
    Home.rebuildActive()
end, after = 14 })
add({ shot = "games-1-shelf" })
add({ fn = function(E)
    local G = require("gzreader_gameboardscreen")
    local menu = G.home and G.home.menu
    local paper_t, games_t
    for _i, t in ipairs(menu and menu._zen_home_focus_targets or {}) do
        if t.key == "gz:daily-paper" then paper_t = t end
        if t.key == "gz:game-board" then games_t = t end
    end
    check(E, paper_t ~= nil and games_t ~= nil and games_t.col == paper_t.col + 1, "on Home's shelf: the paper, then the game board beside it")
    E.games_t = games_t
    local at = G.home and G.home.spine_at
    check(E, at ~= nil and at.w < at.h / 2.5, "the game box stands on its side, as the books do")
    if at and TOUCH then
        E.tap({ at.x + math.floor(at.w / 2), at.y + math.floor(at.h / 2) })
    elseif games_t then
        menu._zen_home_focus_id, menu._zen_home_focus_key = games_t.id, games_t.key
        for i, t in ipairs(menu._zen_home_focus_targets) do if t == games_t then menu._zen_home_focus_index = i end end
        UIM():setDirty(require("apps/filemanager/filemanager").instance, "ui")
    end
end, after = 8 })
add({ shot = "games-2-picked" })
add({ fn = function(E)
    local G = require("gzreader_gameboardscreen")
    local menu = G.home and G.home.menu
    check(E, G.instance == nil and menu and E.games_t and menu._zen_home_focus_id == E.games_t.id, "picked: its lid shows, not opened yet")
    -- (a second tap, or Press: what the shelf does then)
    if E.games_t then E.games_t.activate() end
end, after = 6 })
add({ shot = "games-3-board" })
add({ fn = function(E)
    local G = require("gzreader_gameboardscreen")
    local b = G.instance
    E.board = b
    check(E, b ~= nil and #b.items == 12 and #b.cards == 8 and b.lid and b.die and b.cab and b.score,
        "opened: a game table: 4 paper cards, the theme's lid and die, 4 theme cards, the trophy cabinet and the score card: " .. (b and #b.items or 0))
    local inside, apart = true, true
    for i, t in ipairs(b.items) do
        if t.x < b.frame or t.y < b.frame or t.x + t.w > b.dimen.w - b.frame or t.y + t.h > b.dimen.h - b.frame then inside = false end
        for j = i + 1, #b.items do
            local u = b.items[j]
            if t.x < u.x + u.w and u.x < t.x + t.w and t.y < u.y + u.h and u.y < t.y + t.h then apart = false end
        end
    end
    check(E, inside and apart, "every part inside the board's frame, none over another")
    local spare = b.dimen.h - b.frame - (b.score.y + b.score.h)
    check(E, spare < b.dimen.h * 0.08, "the board fills the screen (" .. spare .. " px spare at the bottom)")
    check(E, b.cards[1].h >= b.dimen.h * 0.12, "the cards are big (" .. b.cards[1].w .. " × " .. b.cards[1].h .. " px)")
    -- the paper's word search, from the board
    if TOUCH then
        local t = b.items[2]
        b:onGbTap(nil, { pos = { x = t.x + 5, y = t.y + 5 } })
    else
        b.focus = 1
    end
end, after = 4 })
if not TOUCH then
    add({ key = "Right", after = 2 })
    add({ key = "Press", after = 5 })
end
add({ shot = "games-4-paper-words" })
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    local pg = Scr.instance
    check(E, pg ~= nil and pg.kind == "words" and pg.set == nil and pg.pz == plugin(), "the paper's word search, the paper's own")
    -- a word found here
    if pg then
        local w = pg.ws.words[1]
        pg:letter(w.x, w.y)
        pg:letter(w.x + w.dx * (#w.word - 1), w.y + w.dy * (#w.word - 1))
        E.word = w.word
        UIM():close(pg)
    end
end, after = 4 })
add({ fn = function(E)
    local Pz = require("gzreader_puzzles")
    local found = select(2, Pz.dayWords(plugin()))
    check(E, found[1] == true, "… found on the board: found in the paper too (" .. tostring(E.word) .. ")")
    local Paper = require("gzreader_dailyscreen")
    Paper.puzzles(plugin(), "words")
end, after = 5 })
add({ shot = "games-5-in-paper" })
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    local pg = Scr.instance
    check(E, pg and pg.found[1] == true, "the paper's own puzzles page shows it found")
    if pg then UIM():close(pg) end
end, after = 4 })
-- a theme: the scramble
add({ fn = function(E)
    local B = require("gzreader_gameboard")
    B.choose(plugin(), B.categorySet("animals"))
    E.board:rebuild()
    local t
    for _i, it in ipairs(E.board.cards) do if it.kind == "scramble" then t = it end end
    check(E, t ~= nil, "Animals on the board, its scramble a tile")
    t.run()
end, after = 5 })
add({ shot = "games-6-scramble" })
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    local pg = Scr.instance
    check(E, pg and pg.kind == "scramble" and pg.set ~= nil and #pg.kinds == 4 and pg.head.title.text == "GAME BOARD", "the themed set's page: the game board's, its four puzzles")
    local b = pg.board
    check(E, b.x >= 0 and b.x + b.w <= pg.dimen.w and pg.slist.y + #pg.slist.rows * pg.slist.row_h <= pg.status.y + 4, "the letters, the clue and the words fit above the status line")
    -- the first swap by a tap (or keys), then the rest straight
    local e = pg.sc.words[1]
    local i = 1
    while e.cur:sub(i, i) == e.w:sub(i, i) do i = i + 1 end
    local j = e.cur:find(e.w:sub(i, i), i + 1, true)
    E.swap = { i, j }
    if TOUCH then
        local function tapTile(k) pg:onPzTap(nil, { pos = { x = b.x + (k - 1) * b.cell + math.floor(b.cell / 2), y = b.y + math.floor(b.cell / 2) } }) end
        tapTile(i)
        tapTile(j)
    else
        pg.tcur = i
        pg:onPzPress()
        pg.tcur = j
        pg:onPzPress()
    end
end, after = 4 })
add({ shot = "games-7-swapped" })
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    local pg = Scr.instance
    local e = pg.sc.words[1]
    check(E, e.cur:sub(E.swap[1], E.swap[1]) == e.w:sub(E.swap[1], E.swap[1]), "two letters picked: swapped")
    -- the rest of the words, swap by swap
    local Pz = require("gzreader_puzzles")
    for n = 1, #pg.sc.words do
        Pz.scrambleGo(pg.pz, n)
        local w = pg.sc.words[n]
        for k = 1, #w.w do
            if w.cur:sub(k, k) ~= w.w:sub(k, k) then
                local m = w.cur:find(w.w:sub(k, k), k + 1, true)
                Pz.scrambleSwap(pg.pz, k, m)
            end
        end
    end
    pg:changed(true)
end, after = 5 })
add({ shot = "games-8-solved" })
add({ fn = function(E)
    local Scr = require("gzreader_puzzlescreen")
    local pg = Scr.instance
    local B = require("gzreader_gameboard")
    local st = B.store(plugin())
    check(E, pg.info.done and st.history[1] and st.history[1].k == "scramble" and st.history[1].s == "Animals", "solved: in the history, with its theme")
    check(E, st.unlocked.first and st.unlocked.scramble, "… and its achievements unlocked (shown for a moment)")
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w ~= E.board and w.name ~= "filemanager" and w ~= require("apps/filemanager/filemanager").instance then UIM():close(w) end
    end
end, after = 5 })
add({ shot = "games-9-board-after" })
add({ fn = function(E)
    local item = E.board.score
    local card
    for _i, c in ipairs(E.board.cards) do if c.kind == "scramble" then card = c end end
    check(E, card and card.done and E.board.cab.trophies[1].at ~= nil and #item.lines == 1 and item.sum.text:find("1 finished", 1, true),
        "on the board: the scramble's card stamped done, a trophy won, the score card's first line")
    item.run()
end, after = 4 })
add({ shot = "games-10-history" })
add({ fn = function(E)
    local v = top()
    UIM():close(v)
    local item
    item = E.board.cab
    item.run()
end, after = 4 })
add({ shot = "games-11-achievements" })
add({ fn = function(E)
    UIM():close(top())
    -- Choose a theme
    E.board.lid.run()
end, after = 4 })
add({ shot = "games-12-themes" })
add({ fn = function(E)
    UIM():close(top())
    UIM():close(E.board)
    -- a book read: its words
    local book = os.getenv("GZ_EMU_BOOK")
    if book then require("apps/reader/readerui"):showReader("/mnt/us/GZreader/one.epub") end
end, after = 20 })
add({ fn = function(E)
    local RUI = require("apps/reader/readerui")
    local ui = RUI.instance
    if ui then
        ui:handleEvent(require("ui/event"):new("GotoPage", 30))
    end
end, after = 6 })
add({ fn = function(E)
    UIM():sendEvent(require("ui/event"):new("Home"))
end, after = 14 })
add({ fn = function(E)
    local B = require("gzreader_gameboard")
    local books = B.store(plugin()).books
    check(E, os.getenv("GZ_EMU_BOOK") == nil or (books[1] and #books[1].words >= 4),
        "a book closed: its words kept for the board (" .. (books[1] and #books[1].words or 0) .. ": "
        .. (books[1] and (function() local t = {} for i = 1, math.min(8, #books[1].words) do t[#t + 1] = books[1].words[i].word end return table.concat(t, " ") end)() or "") .. ")")
    if books[1] then
        B.choose(plugin(), B.bookSet(plugin(), books[1].key))
        require("gzreader_puzzlescreen").show(plugin(), "cross", { set = B.current(plugin()) })
    end
end, after = 8 })
add({ shot = "games-13-book-cross" })
add({ fn = function(E)
    local f = io.open(E.out .. "/game-board-checks.txt", "w")
    f:write(table.concat(checks, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
