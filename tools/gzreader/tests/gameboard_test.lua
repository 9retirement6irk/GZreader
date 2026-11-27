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
-- the paper's puzzles: all four on one day
for i, k in ipairs({ "sudoku", "words", "maze" }) do B.record(plugin, { kind = k, done_n = i, of = 4 }, t1 + 60 * i) end
local full = B.record(plugin, { kind = "cross", done_n = 4, of = 4 }, t1 + 600)
local fid = {}
for _i, a in ipairs(full) do fid[a.id] = true end
check(fid.paper and plugin.store.games.history[1].src == "paper" and plugin.store.games.history[1].s == nil, "the paper's four done in a day: The whole paper")
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
check(#plugin.store.games.history == B.HISTORY_MAX and plugin.store.games.stats.total == 222 and plugin.store.games.unlocked.hundred, "the history keeps the last 200; the count goes on")
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
B.solved(plugin, "sudoku", now + 20)
check(plugin.store.games.history[1].src == "paper" and Pz.state(plugin).recorded.sudoku, "the paper's puzzle finished from the board or the paper: in the history as the paper's")

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
