-- The game board (gzreader_gameboard.lua): themed sets of puzzles kept apart
-- from the paper's (gzreader_puzzles.lua with Puzzles.forSet), the word
-- scramble, words read from a book, the AI's theme, the history and the
-- achievements, and the setup guide's page. No widgets: the screens are
-- driven in the emulator (tools/gzreader/emulator/game_board.lua).
--   luajit gameboard_test.lua <plugin dir> <tests lib>
local PLUGIN, LIB = arg[1], arg[2]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

---------------------------------------------------------------- stand-ins
local dkjson = require("dkjson")
local logged = {}
package.preload["gettext"] = function() return function(t) return t end end
package.preload["gzreader_log"] = function()
    local function line(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logged[#logged + 1] = table.concat(parts, " ")
    end
    return { info = line, warn = line, err = line }
end
package.preload["gzreader_json"] = function() return { decode = function(s) return (dkjson.decode(s)) end, encode = dkjson.encode } end
package.preload["ffi/util"] = function()
    return { template = function(s, ...)
        local args = { ... }
        return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
    end }
end
package.preload["ffi/blitbuffer"] = function() return {} end
package.preload["device"] = function() return { screen = {} } end
package.preload["ui/font"] = function() return {} end
package.preload["ui/geometry"] = function() return {} end
package.preload["ui/uimanager"] = function() return {} end
local today = "2030-03-14"
local daily = { enabled = false }
package.preload["gzreader_daily"] = function()
    return {
        day = function() return today end,
        store = function(p) p.store.daily = p.store.daily or {}; return p.store.daily end,
        enabled = function(p) return p.store.daily and p.store.daily.enabled == true end,
        load = function() return nil end,
    }
end
local ai = { ready = false, asked = nil, answer = nil }
package.preload["gzreader_ai"] = function()
    return {
        ready = function() return ai.ready end,
        ask = function(_p, q, done) ai.asked = q; done(ai.answer, ai.answer and nil or "no answer") end,
    }
end
package.preload["readhistory"] = function() return { hist = { { file = "/mnt/us/books/The_Wind_in_the_Willows.epub" } } } end

local saves, soon = 0, 0
local plugin = { store = { daily = daily } }
function plugin.save() saves = saves + 1 end
function plugin.saveSoon() soon = soon + 1 end

local Pz = require("gzreader_puzzles")
local B = require("gzreader_gameboard")
local W = require("gzreader_gamewords")

print("== the themes' words")
local bad, words_n = {}, 0
for _i, t in ipairs(W.THEMES) do
    local seen = {}
    for _j, pair in ipairs(t.words) do
        words_n = words_n + 1
        if not pair[1]:match("^%u+$") or #pair[1] < 3 or #pair[1] > 10 or type(pair[2]) ~= "string" or pair[2] == ""
            or pair[2]:upper():find(pair[1], 1, true) or seen[pair[1]] then bad[#bad + 1] = t.id .. ":" .. pair[1] end
        seen[pair[1]] = true
    end
    if #W.entries(t) < 12 then bad[#bad + 1] = t.id .. " has too few" end
end
check(#bad == 0, "every theme's words are A–Z, 3–10 letters, each once, with a clue that doesn't give it away (" .. words_n .. " words): " .. table.concat(bad, ", "))
local months_ok = true
for m = 1, 12 do if not (W.season(m) and W.season(m).season) then months_ok = false end end
check(months_ok and W.season(11).id == "harvest" and W.season(12).id == "holidays" and W.season(7).id == "summer", "every month has its season's theme (November: harvest, December: the winter holidays)")
check(#W.categories() >= 8 and not W.categories()[1].season, "eight categories or more, apart from the seasons")

print("== a themed set, apart from the paper's puzzles")
local now = os.time({ year = 2030, month = 3, day = 14, hour = 10 })
local set = B.categorySet("ocean", now)
check(set.fixed and set.title == "The ocean" and set.src.kind == "category" and #set.entries == 14 and set.kinds[3] == "scramble", "a category's set: its title, its fourteen words, a crossword, a word search, a scramble and a maze")
local set2 = B.categorySet("ocean", now + 60)
check(set2.day ~= set.day, "the same theme again: another seed (other puzzles)")
local pz = Pz.forSet(plugin, set)
check(Pz.state(pz) == set and Pz.owner(pz) == plugin and #Pz.kindsOf(pz) == 4 and #Pz.kindsOf(plugin) == 4 and Pz.kindsOf(plugin)[1] == "sudoku",
    "a set's stand-in keeps its state in the set; the plugin's kinds are the paper's")
local ws, found = Pz.dayWords(pz)
local theirs = {}
for _i, e in ipairs(set.entries) do theirs[e.word] = true end
local all_theirs = #ws.words >= 6
for _i, w in ipairs(ws.words) do if not theirs[w.word] then all_theirs = false end end
check(all_theirs and ws.src == "set" and next(found) == nil, "its word search hides its own words, none of the list's (" .. #ws.words .. ")")
check(daily.puzzles == nil, "… and the paper's puzzles aren't touched")
local cw = Pz.dayCross(pz)
local cross_theirs = #cw.words >= 3
for _i, w in ipairs(cw.words) do if not theirs[w.word] then cross_theirs = false end end
check(cross_theirs and cw.src == "set", "its crossword: its own words and clues (" .. #cw.words .. " words)")
check(Pz.freshen(pz) == false, "a set's word puzzles aren't remade when the paper changes")
-- the paper's puzzles on the board are the paper's own
local paper_ws = Pz.dayWords(plugin)
check(daily.puzzles and daily.puzzles.day == today and paper_ws.src == "list", "the paper's puzzles from the board: the paper's own, kept where the paper keeps them")
Pz.wordFound(plugin, 1)
local n_done = select(2, Pz.finished(plugin))
check(n_done == 0 and select(2, Pz.dayWords(plugin))[1] == true, "a word found on the board's paper puzzles is found in the paper")
today = "2030-03-15"
check(Pz.state(pz).words ~= nil, "a new day: a set keeps its puzzles")
check(Pz.state(plugin).words == nil, "… the paper's start again")

print("== the word scramble")
check(Pz.jumble("OCEAN", "x") ~= "OCEAN" and Pz.jumble("OCEAN", "x") == Pz.jumble("OCEAN", "x"), "a word's letters jumbled, never as it is, the same each time for a seed")
local sc = Pz.dayScramble(pz)
check(#sc.words == 6 and sc.at == 1 and not Pz.scrambleDone(sc), "six words to unscramble, from the set's")
local jumbled = true
for _i, e in ipairs(sc.words) do
    if e.cur == e.w or #e.cur ~= #e.w then jumbled = false end
    local a, b = {}, {}
    for i = 1, #e.w do a[#a + 1] = e.w:sub(i, i); b[#b + 1] = e.cur:sub(i, i) end
    table.sort(a); table.sort(b)
    if table.concat(a) ~= table.concat(b) then jumbled = false end
end
check(jumbled, "each is its own letters in another order")
-- solve the first by swaps
local function solve(n)
    local e = sc.words[n]
    for i = 1, #e.w do
        if e.cur:sub(i, i) ~= e.w:sub(i, i) then
            local j = e.cur:find(e.w:sub(i, i), i + 1, true)
            local spelled = select(2, Pz.scrambleSwap(pz, i, j))
            if spelled then return true end
        end
    end
end
check(Pz.scrambleSwap(pz, 1, 1) == false, "a letter swapped with itself: nothing")
check(solve(1) and sc.words[1].cur == sc.words[1].w and sc.at == 2, "letters swapped until the word is spelled: on to the next word")
check(Pz.scrambleSwap(pz, 1, 2) and Pz.scrambleGo(pz, 1) and Pz.scrambleSwap(pz, 1, 2) == false, "a word put right stays right")
Pz.scrambleGo(pz, 2)
local hinted = Pz.scrambleHint(pz)
check(hinted and sc.words[2].cur:sub(1, 1) == sc.words[2].w:sub(1, 1) and set.helped.scramble == true, "a hint puts the word's first wrong letter right, and counts as help")
for n = 2, 6 do Pz.scrambleGo(pz, n); solve(n) end
check(Pz.scrambleDone(Pz.dayScramble(pz)) and select(1, Pz.finished(pz)).scramble == true, "every word spelled: the scramble is done")
Pz.scrambleClear(pz)
check(not Pz.scrambleDone(Pz.dayScramble(pz)) and Pz.dayScramble(pz).at == 1, "Start again: jumbled again, at the first word")
local few = B.makeSet({ kind = "ai" }, "Few", { { word = "OWLS", clue = "Birds" } }, now)
check(#Pz.dayScramble(Pz.forSet(plugin, few)).words == 6, "a set with too few words: the list's fill the scramble")

print("== words from a book")
local text = [[
Mole had been working very hard all the morning. Ratty watched the river from the bank.
"Hello, Mole," said Ratty, and the river glittered. Badger lived in the Wild Wood, far from the river, and Ratty visited Badger.
Mole and Ratty rowed along the river until dusk. Toad shouted from the bank about his motorcar.
Ratty laughed; Toad was always buying a new motorcar. Badger frowned at Toad and his motorcar.
The meadow was golden and the hedgerows full of blossom. Mole loved the meadow by the river bank.
Toad sang in the meadow. Badger and Mole walked the meadow at night, and the hedgerows rustled.
They had a picnic by the hedgerows. The picnic basket was heavy. Ratty packed the picnic himself.
Killed it, said nobody, and the dead leaves blew. They were killed by nothing at all.
]]
local bw = B.bookWords(text, 10)
local got = {}
for i, e in ipairs(bw) do got[e.word] = i end
check(got.RATTY and got.TOAD and got.BADGER and got.MOLE, "names that come up again and again are kept (" .. #bw .. " words)")
check(got.RATTY < (got.MEADOW or 99) and got.TOAD < (got.MEADOW or 99), "names first, then the book's other words")
check(got.MOTORCAR and got.PICNIC and got.HEDGEROWS and got.MEADOW, "longer words seen three times or more are kept too")
check(not got.RIVER or got.RIVER > 4, "a short everyday word isn't among the first")
check(not got.KILLED and not got.DEAD and not got.HELLO and not got.WORKING, "no grim words, none seen only once or twice")
local clue
for _i, e in ipairs(bw) do if e.word == "MOTORCAR" then clue = e.clue end end
check(clue and clue:find("_____", 1, true) and not clue:upper():find("MOTORCAR", 1, true), "a word's clue is a sentence of the book with it left out: " .. tostring(clue))

-- read as a book closes
local pages_text = text
local doc_asked
local doc = {
    file = "/mnt/us/books/willows.epub",
    page = 40,
    getCurrentPage = function(self) return self.page end,
    getPageCount = function() return 300 end,
    getPageXPointer = function(_s, p) return "p" .. p end,
    getTextFromXPointers = function(_s, a, b) doc_asked = { a, b }; return pages_text end,
}
local ui = { rolling = true, document = doc, doc_props = { display_title = "The Wind in the Willows", authors = "Kenneth Grahame" } }
plugin.store.games = nil
check(B.harvest(plugin, ui, now) == 0 and plugin.store.games == nil, "the game board off: nothing is read from the book")
B.setEnabled(plugin, true)
check(B.enabled(plugin), "the board on")
local n_words = B.harvest(plugin, ui, now)
local kept = plugin.store.games.books[1]
check(n_words >= 6 and kept.title == "The Wind in the Willows" and kept.authors == "Kenneth Grahame" and kept.page == 40,
    "a book closed: its words kept, with its title and where you were (" .. n_words .. ")")
check(doc_asked[1] == "p1" and doc_asked[2] == "p41", "only the pages read are looked at, from the start up to the page you're on")
doc.page = 500
local far = { rolling = true, document = doc, doc_props = ui.doc_props }
doc.page = 45
check(B.harvest(plugin, far, now) == 0, "read again only after fifteen more pages")
doc.page = 200
B.harvest(plugin, far, now)
check(doc_asked[1] == "p80" and #plugin.store.games.books == 1, "a long way in: the last 120 pages; the same book kept once")
check(B.harvest(plugin, { rolling = false, document = doc }, now) == 0, "a PDF: nothing read")
for i = 1, 7 do
    B.harvest(plugin, { rolling = true, document = setmetatable({ file = "/b" .. i .. ".epub" }, { __index = doc }), doc_props = { title = "Book " .. i } }, now + i)
end
check(#plugin.store.games.books == B.BOOKS_MAX and plugin.store.games.books[1].title == "Book 7", "the last six books are kept, the newest first")

local bset = B.bookSet(plugin, "/mnt/us/books/willows.epub", now)
check(bset == nil, "a book no longer kept: no set")
bset = B.bookSet(plugin, nil, now)
check(bset and bset.title == "From Book 7" and bset.src.kind == "book" and bset.entries[1].clue ~= nil, "the latest book's set: its words, the ones with clues first")
local mix = B.booksSet(plugin, now)
check(mix and mix.src.kind == "books" and #mix.src.ids == 6 and #mix.entries >= 4, "your books' set: some words of each")

print("== the set on the board")
plugin.store.games.set = nil
local march = B.current(plugin, now)
check(march.src.kind == "season" and march.src.id == "spring" and march.src.auto, "none chosen: the season's")
local may = os.time({ year = 2030, month = 6, day = 2, hour = 10 })
check(B.current(plugin, may).src.id == "summer", "… a new season, and none of its puzzles begun: the new season's")
local s_now = B.current(plugin, may)
s_now.began = may
check(B.current(plugin, os.time({ year = 2030, month = 9, day = 2 })) == s_now, "… begun: it stays")
check(B.choose(plugin, B.categorySet("space", now)) and B.current(plugin, now).title == "Space", "a theme chosen stays on the board")
local before = B.current(plugin, now).day
B.again(plugin, now + 5)
check(B.current(plugin, now).title == "Space" and B.current(plugin, now).day ~= before, "New puzzles: the same theme, a new seed")

print("== the AI's theme")
local q = B.aiQuestion(B.aiBooks(plugin))
check(q.text:find("Book 7", 1, true) and q.text:find("The Wind in the Willows", 1, true) and q.what == "game board theme" and q.system:find("JSON", 1, true),
    "the question names your books (the kept ones, then the history's), and asks for JSON")
check(not q.text:find("mnt", 1, true) and not q.text:find("epub", 1, true), "… by their names, not their files")
local title, entries = B.parseAI('Here you go: {"theme": "Rivers and boats", "words": [{"word": "Canoe", "clue": "A light boat"}, {"word": "paddle", "clue": "Push the water with it"},'
    .. '{"word": "Ferry", "clue": "It carries you across"}, {"word": "WEIR", "clue": "A low dam"}, {"word": "BOATHOUSE", "clue": "Where the boats are kept"},'
    .. '{"word": "bank", "clue": "The bank of the river"}, {"word": "sail boat", "clue": "Blown along"}, {"word": "Ébène", "clue": "x"}, {"word": "OAR", "clue": "Row with it"}]}')
local by = {}
for _i, e in ipairs(entries or {}) do by[e.word] = e end
check(title == "Rivers and boats" and by.CANOE and by.PADDLE and by.SAILBOAT and by.OAR and not by["ÉBÈNE"], "the answer read: the theme, its words in capitals, A–Z only")
check(by.BANK and by.BANK.clue == nil, "a clue that gives its word away is dropped")
check(B.parseAI("Sorry, I can't.") == nil and B.parseAI('{"theme": "x", "words": [{"word": "ONE", "clue": "1"}]}') == nil, "no JSON, or too few words: no theme")
local asked_set, why
B.askAI(plugin, function(s, w) asked_set, why = s, w end, now)
check(asked_set == nil and why == "no AI key" and ai.asked == nil, "no AI set up: nothing asked")
why = nil
ai.ready = true
ai.answer = '{"theme": "Old England", "words": [{"word":"MANOR","clue":"A grand country house"},{"word":"SQUIRE","clue":"A country gentleman"},{"word":"HEDGE","clue":"A wall of bushes"},'
    .. '{"word":"COTTAGE","clue":"A small country house"},{"word":"VILLAGE","clue":"Smaller than a town"},{"word":"MEADOW","clue":"A field of grass"}]}'
B.askAI(plugin, function(s, w) asked_set, why = s, w end, now)
check(asked_set and why == nil and asked_set.title == "Old England" and asked_set.src.kind == "ai" and #asked_set.entries == 6, "asked: a set of the AI's theme")

print("== history and achievements")
plugin.store.games.history, plugin.store.games.stats, plugin.store.games.unlocked = {}, {}, {}
local t1 = os.time({ year = 2030, month = 3, day = 14, hour = 3 })
local new = B.record(plugin, { kind = "cross", set = bset, began = t1 - 100, helped = false }, t1)
local ids = {}
for _i, a in ipairs(new) do ids[a.id] = true end
check(ids.first and ids.cross and ids.book and ids.unaided and ids.quick and ids.night, "a crossword from your book, alone, in under three minutes, at 3 a.m.: those achievements")
local h = plugin.store.games.history[1]
check(h.k == "cross" and h.s == "From Book 7" and h.src == "book" and h.d == 100 and not h.h, "… and in the history: what, which set, how long")
local again = B.record(plugin, { kind = "cross", set = bset, began = t1 - 100, helped = true }, t1 + 10)
check(#again == 0, "an achievement comes once")
check(plugin.store.games.stats.unaided == 1, "help taken: not unaided")
-- the paper's puzzles on the board (no sudoku): all three on one day
for i, k in ipairs({ "words", "maze" }) do B.record(plugin, { kind = k, done_n = i, of = 3 }, t1 + 60 * i) end
local full = B.record(plugin, { kind = "cross", done_n = 3, of = 3 }, t1 + 600)
local fid = {}
for _i, a in ipairs(full) do fid[a.id] = true end
check(fid.paper and plugin.store.games.history[1].src == "paper" and plugin.store.games.history[1].s == nil, "the paper's three on the board done in a day: The whole paper")
-- streaks
local days = { ["2030-03-12"] = 1, ["2030-03-13"] = 2, ["2030-03-14"] = 1 }
check(B.streak(days, "2030-03-14") == 3 and B.streak(days, "2030-03-15") == 3 and B.streak(days, "2030-03-16") == 0, "a streak: days running, to today or yesterday")
check(B.streak({ ["2030-02-28"] = 1, ["2030-03-01"] = 1 }, "2030-03-01") == 2, "… across the month's end")
for d = 15, 20 do B.record(plugin, { kind = "maze", set = set }, os.time({ year = 2030, month = 3, day = d, hour = 12 })) end
local unlocked = select(2, B.achievements(plugin))
check(plugin.store.games.unlocked.streak7 and plugin.store.games.unlocked.streak3 and not plugin.store.games.unlocked.streak30, "seven days running: three and seven days running, not thirty")
check(unlocked >= 10 and B.achievementsText(plugin):find("unlocked", 1, true) and B.achievementsText(plugin):find("Still to do", 1, true),
    "the achievements listed: those unlocked, then the rest (" .. unlocked .. " of " .. #B.ACHIEVEMENTS .. ")")
for i = 1, 210 do B.record(plugin, { kind = "words" }, t1 + i) end
check(#plugin.store.games.history == B.HISTORY_MAX and plugin.store.games.stats.total == 221 and plugin.store.games.unlocked.hundred, "the history keeps the last 200; the count goes on")
check(B.tookText(45) == "45 s" and B.tookText(300) == "5 min" and B.tookText(3900) == "1 h 5 min" and B.tookText(200000) == "2 days" and B.tookText(nil) == nil,
    "how long, in words")

-- a puzzle finished on the puzzles' page: noted once
plugin.store.games.history = {}
local s3 = B.categorySet("music", now)
local pz3 = Pz.forSet(plugin, s3)
Pz.began(pz3, "maze")
local first_new = B.solved(pz3, "maze", now + 5)
check(#plugin.store.games.history == 1 and plugin.store.games.history[1].s == "Music" and plugin.store.games.history[1].d ~= nil and type(first_new) == "table",
    "a set's puzzle finished on its page: in the history, with its theme")
B.solved(pz3, "maze", now + 9)
check(#plugin.store.games.history == 1, "… once, however often the page says it's done")
B.solved(plugin, "words", now + 20)
check(plugin.store.games.history[1].src == "paper" and Pz.state(plugin).recorded.words, "the paper's puzzle finished from the board or the paper: in the history as the paper's")
-- no sudoku on the board: not among its paper cards, not an achievement, and one finished in the paper isn't the board's
local kinds_text = table.concat(Pz.BOARD_KINDS, " ")
local has_sudoku_award = false
for _i, a in ipairs(B.ACHIEVEMENTS) do if a.id == "sudoku" or a.text:lower():find("sudoku", 1, true) then has_sudoku_award = true end end
local hist_before = #plugin.store.games.history
local none = B.solved(plugin, "sudoku", now + 30)
check(kinds_text == "words cross maze" and not has_sudoku_award and #B.ACHIEVEMENTS == 23
    and #none == 0 and #plugin.store.games.history == hist_before and Pz.state(plugin).recorded.sudoku,
    "no sudoku on the board: three paper puzzles, 23 achievements (two of them bingo's), a sudoku done in the paper stays the paper's")
local GS = require("gzreader_gameboardscreen")
local pdone, pn, pof = GS.paperDone(plugin)
check(pof == 3 and pn <= 3 and type(pdone) == "table", "the board counts the paper's three (" .. pn .. "/" .. pof .. ")")

print("== bingo")
do
    local Bingo = require("gzreader_bingo")
    local card = Bingo.card("2026-11-28:1")
    local cols_ok, seen = true, {}
    for sq = 1, 25 do
        local n, col = card[sq], (sq - 1) % 5
        if sq == 13 then
            if n ~= 0 then cols_ok = false end
        else
            if n < col * 15 + 1 or n > col * 15 + 15 or seen[n] then cols_ok = false end
            seen[n] = true
        end
    end
    check(#card == 25 and cols_ok, "a card: five numbers of each column's fifteen (B 1-15 … O 61-75), none twice, the middle free")
    local same, other = Bingo.card("2026-11-28:1"), Bingo.card("2026-11-28:2")
    check(table.concat(same, ",") == table.concat(card, ",") and table.concat(other, ",") ~= table.concat(card, ","),
        "the same game is the same card (after a restart); another game, another card")
    local order, all = Bingo.order("2026-11-28:1"), {}
    for _i, n in ipairs(order) do all[n] = true end
    local every = #order == 75
    for n = 1, 75 do if not all[n] then every = false end end
    check(every and table.concat(order, ",") ~= table.concat(Bingo.order("2026-11-28:2"), ","), "the caller: all 75 balls, each once, in the game's own order")
    check(Bingo.name(7) == "B 7" and Bingo.name(61) == "O 61" and Bingo.name(45) == "N 45" and Bingo.name(0) == "", "a ball as it's called: B 7, N 45, O 61")
    check(#Bingo.LINES == 12 and Bingo.line("1111100000000000000000000") ~= nil and Bingo.line("1000001000001000001000001") ~= nil
        and Bingo.line("0000100010001000100010000") ~= nil and Bingo.line("0100001000010000100001000") ~= nil
        and Bingo.line("1111000000001000000000000") == nil, "bingo: a row, a column or a diagonal of five (twelve lines); four isn't")

    -- a game
    plugin.store.games.bingo = nil
    local save_n = 0
    local real_save, real_soon = plugin.save, plugin.saveSoon
    plugin.save = function() save_n = save_n + 1 end
    plugin.saveSoon = function() save_n = save_n + 1 end
    local b = Bingo.state(plugin, now)
    check(b.played == 1 and b.called == 0 and b.marks:sub(13, 13) == "1" and select(2, b.marks:gsub("1", "")) == 1 and b.won == nil,
        "a won_new game: nothing called, only the free square daubed")
    local first_sq = 1
    check(Bingo.daub(plugin, first_sq, now) == "not called" and b.marks:sub(first_sq, first_sq) == "0",
        "a square can't be daubed before its number is called")
    local n1 = Bingo.call(plugin, now)
    check(n1 == Bingo.order(b.seed)[1] and b.called == 1 and b.began == now and #Bingo.calledBalls(b) == 1, "Call: the caller's first ball")
    -- call until the middle row's four numbers are out (the row with the free square), daubing them
    local row = { 11, 12, 14, 15 }
    local need = {}
    for _i, sq in ipairs(row) do need[b.card[sq]] = sq end
    local left, guard, last_sq = 4, 0, nil
    local waited_ok = true
    while left > 0 and guard < 80 do
        guard = guard + 1
        local n = n1
        n1 = nil
        n = n or Bingo.call(plugin, now + guard)
        if need[n] then
            if left > 1 then
                local w = Bingo.waiting(b)
                local hit = false
                for _i, sq in ipairs(w) do if sq == need[n] then hit = true end end
                if not hit then waited_ok = false end
                check(Bingo.daub(plugin, need[n], now + guard) == "daubed" or false, "…a called square daubed (" .. Bingo.name(n) .. ")")
                check(Bingo.daub(plugin, need[n], now + guard) == "already", "…once")
            end
            left = left - 1
            if left == 0 then last_sq = need[n] end
        end
    end
    local calls = b.called
    local history_before = #plugin.store.games.history
    local what, won_new = Bingo.daub(plugin, last_sq, now + 200)
    check(waited_ok, "the squares called and not yet daubed are known (for a test; the page doesn't show them)")
    local won_ids = {}
    for _i, a in ipairs(type(won_new) == "table" and won_new or {}) do won_ids[a.id] = true end
    check(what == "bingo" and b.won == calls and b.best == calls and b.wins == 1 and won_ids.bingo == true,
        "five in a line: BINGO, in the calls it took (" .. calls .. "); the Bingo! achievement")
    local entry = plugin.store.games.history[1]
    check(#plugin.store.games.history == history_before + 1 and entry.k == "bingo" and entry.s == Bingo.calls(calls) and entry.d == nil
        and B.kindName("bingo") == "Bingo" and plugin.store.games.stats.counts.bingo == 1,
        "in the board's history: Bingo · " .. Bingo.calls(calls))
    check((won_ids.bingo_quick == true) == (calls <= Bingo.QUICK), "Quick caller only for a win within 30 calls")
    check(Bingo.call(plugin, now + 300) == nil and Bingo.daub(plugin, 1, now + 300) == "over", "won: no more calls or daubs in this game")
    local nb = Bingo.deal(plugin, now + 400)
    check(nb.played == 2 and nb.called == 0 and nb.won == nil and nb.best == calls and nb.wins == 1
        and table.concat(nb.card, ",") ~= table.concat(card, ",") and save_n > 0,
        "New game: another card, the best and the wins kept, saved")
    -- the hall's lines
    local BS = require("gzreader_bingoscreen")
    local l0 = BS.lines(nb)
    check(l0.count == "Call the first ball to begin." and l0.earlier == "", "the hall before the first ball")
    for _i = 1, 7 do Bingo.call(plugin, now + 500) end
    local l7 = BS.lines(nb, "x")
    local _, dots = l7.earlier:gsub(" · ", "")
    check(l7.count == "Ball 7 of 75" and dots == 4 and l7.note == "x", "after seven: Ball 7 of 75, the five before it")
    local L = BS.layout(1072, 1448, function(v) return v * 2 end)
    local L2 = BS.layout(600, 800, function(v) return v end)
    local function inside(Lx, w, hh)
        local bt = Lx.buttons
        return Lx.fits and Lx.grid.x >= 0 and Lx.grid.x + Lx.cell * 5 <= w and bt.call.y + bt.call.h <= hh and bt.new.x + bt.new.w <= w
            and Lx.grid.y >= Lx.ball.y + Lx.ball.d and bt.call.y >= Lx.grid.y + Lx.cell * 5 and bt.call.x + bt.call.w <= bt.new.x
    end
    check(inside(L, 1072, 1448) and inside(L2, 600, 800), "the hall's layout on a Paperwhite and a Kindle 3: ball, card and buttons, nothing over anything or off the screen")
    plugin.save, plugin.saveSoon = real_save, real_soon
end

print("== the setup guide's page")
plugin.store.games.enabled = nil
daily.enabled = nil
local choices = B.setupChoices(plugin)
check(#choices == 2 and choices[1].id == "gz_paper" and choices[2].id == "gz_games" and not choices[1].checked and not choices[2].checked,
    "two choices, the daily paper and the game board, ticked as they are (both off)")
B.applySetup(plugin, { gz_paper = true, gz_games = true })
check(daily.enabled == true and B.enabled(plugin), "both ticked: both on")
check(B.setupChoices(plugin)[1].checked and B.setupChoices(plugin)[2].checked, "the guide again: ticked")
B.applySetup(plugin, { gz_paper = true })
check(daily.enabled == true and not B.enabled(plugin), "the board unticked: off; the paper stays")
B.applySetup(plugin, {})
check(not daily.enabled and not B.enabled(plugin), "neither: both off")

print("== what it may not do")
local function src(name) local f = assert(io.open(PLUGIN .. "/" .. name)); local t = f:read("*a"); f:close(); return t end
local bsrc, wsrc = src("gzreader_gameboard.lua"), src("gzreader_gamewords.lua")
check(not bsrc:find("math.random", 1, true) and not wsrc:find("math.random", 1, true), "no Kindle's own random numbers: the same seed, the same puzzles")
check(not bsrc:find("socket", 1, true) and select(2, bsrc:gsub("AI%.ask%(", "")) == 1, "nothing sent anywhere but the one question to the AI, when asked for")
check(not bsrc:find("Log%.[a-z]+%([^)]*title") and not bsrc:find('info%([^)]*%.word'), "the log names no book and no word")

print(string.format("game board: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
