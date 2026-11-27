--[[--
The game board: a box of puzzles on Home's shelf, beside the daily paper
(off unless chosen: Settings → Home and tabs → Home → Game board, or the
setup guide). Its screen is gzreader_gameboardscreen.lua; the puzzles
themselves are gzreader_puzzles.lua's, on gzreader_puzzlescreen.lua's page.

On it:
- today's paper puzzles: the paper's own (store.daily.puzzles), so what's
  done on the board is done in the paper and the other way round;
- a themed set: a crossword, a word search, a word scramble and a maze,
  their words from the book you're reading, from several of your books,
  the season, a category (gzreader_gamewords.lua), or a theme the AI
  finds in your books;
- achievements, and the history of the puzzles finished.

Words from a book are read when you close it (Board.harvest): from the
pages you've read (the last HARVEST_PAGES of them), never further, so a
puzzle gives nothing away. Names that come up again and again (characters,
places) first, then the book's longer words; a clue is a sentence of the
book the word is in, left out. Kept for the last BOOKS_MAX books.

Kept in store.games = { enabled, set (the themed set: gzreader_puzzles.lua's
set table), books = { { key, title, authors, page, at, words = { { word,
clue } } } }, history = { { t, k (kind), s (set's title; nil: the paper), src,
d (seconds from first move), h (help taken) } }, stats = { total, counts,
days, paper, books, seasons, categories, ai, unaided, quick }, unlocked =
{ [id] = time } }.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Board = {
    HISTORY_MAX = 200,   -- puzzles kept in the history
    BOOKS_MAX = 6,       -- books whose words are kept
    BOOK_WORDS = 30,     -- words kept from a book
    HARVEST_PAGES = 120, -- pages read back from where you are
    HARVEST_EVERY = 15,  -- pages read before a book's words are read again
    TEXT_MAX = 300000,   -- bytes of a book's text looked at, at most
    QUICK = 180,         -- seconds: a quick finish
}

local function Pz() return require("gzreader_puzzles") end
local function Words() return require("gzreader_gamewords") end

-- (a change is kept soon, not at once)
local function keep(plugin)
    if type(plugin.saveSoon) == "function" then plugin:saveSoon() elseif type(plugin.save) == "function" then plugin:save() end
end

function Board.store(plugin)
    plugin.store.games = type(plugin.store.games) == "table" and plugin.store.games or {}
    local st = plugin.store.games
    st.books = type(st.books) == "table" and st.books or {}
    st.history = type(st.history) == "table" and st.history or {}
    st.stats = type(st.stats) == "table" and st.stats or {}
    st.unlocked = type(st.unlocked) == "table" and st.unlocked or {}
    return st
end

function Board.enabled(plugin)
    return type(plugin.store) == "table" and type(plugin.store.games) == "table" and plugin.store.games.enabled == true
end

function Board.setEnabled(plugin, on)
    local st = Board.store(plugin)
    st.enabled = on and true or nil
    plugin:save()
    require("gzreader_log").info("game board:", on and "on" or "off")
end

---------------------------------------------------------------- words from a book

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Longer words in every book (the puzzles' STOP has the shorter ones): not a book's own.
local COMMON = {}
for w in ([[
across almost another anyone anything around asked because before behind better beside between called cannot
change could didn't either enough every everyone everything father finally around himself herself inside itself
little looked looking minute moment mother myself nobody nothing others outside people perhaps rather really
reached replied second seemed should simply someone something somewhere started suddenly themselves though
thought through toward towards turned twenty usually waited walked wanted whatever whether without wondered
yourself already always answer answered believe course decided different during finished getting having knew
matter morning nearly number opened passed person places pulled really return right saying smiled sometimes
standing stopped straight talking things trying understand voice watched within working
]]):gmatch("%a+") do COMMON[w:upper()] = true end

--- The words of a book's text worth a puzzle: { { word, clue } }, `max` at
--- most. Names first (capitalised, three times or more, once at least in
--- the middle of a sentence, never in lower case), the ones seen most
--- first; then longer words (6 letters and up, not ending -ed, -ing or -ly,
--- not in every book) seen 3 times or more. Plain A–Z, 4 to 9 letters, no
--- everyday or grim words, one of a plural and its single. A word's clue
--- is the first sentence it's in that says enough without it (or none).
function Board.bookWords(text, max)
    max = max or Board.BOOK_WORDS
    if type(text) ~= "string" then return {} end
    local P = Pz()
    local STOP, GRIM = P.STOP, P.GRIM
    local caps, mid, lows, clue, order = {}, {}, {}, {}, {}
    for sentence in (text .. " "):gmatch("[^%.%?!\n]+[%.%?!\n]?") do
        local first = true
        for token in sentence:gmatch("[%a'\128-\255]+") do
            if #token >= 4 and #token <= 9 and not token:find("[^%a]") then
                local up = token:upper()
                if not STOP[up] and not GRIM[up] and not COMMON[up] then
                    local counted = false
                    if token:match("^%u%l+$") then
                        caps[up] = (caps[up] or 0) + 1
                        if not first then mid[up] = true end
                        counted = true
                    elseif token:match("^%l+$") then
                        lows[up] = (lows[up] or 0) + 1; counted = true
                    end
                    if counted then
                        if caps[up] == 1 and not lows[up] or lows[up] == 1 and not caps[up] then order[#order + 1] = up end
                        if clue[up] == nil and #sentence <= 400 then
                            clue[up] = P.clueFrom(up, trim(sentence)) or nil
                        end
                    end
                end
            end
            first = false
        end
    end
    local names, words = {}, {}
    for _i, w in ipairs(order) do
        local c, l = caps[w] or 0, lows[w] or 0
        if c >= 3 and l == 0 and mid[w] then names[#names + 1] = { word = w, n = c }
        elseif l >= 3 and #w >= 6 and not w:find("ED$") and not w:find("ING$") and not w:find("LY$") then
            words[#words + 1] = { word = w, n = l }
        end
    end
    local function most(a, b) if a.n ~= b.n then return a.n > b.n end return a.word < b.word end
    table.sort(names, most)
    table.sort(words, most)
    local out, has = {}, {}
    local function take(list, limit)
        for _i, e in ipairs(list) do
            if #out >= limit then return end
            local w = e.word
            local single = w:match("^(.+)S$")
            if not has[w] and not has[w .. "S"] and not (single and has[single]) then
                has[w] = true
                out[#out + 1] = { word = w, clue = clue[w] }
            end
        end
    end
    take(names, math.ceil(max * 0.6))
    take(words, max)
    take(names, max)
    return out
end

--- Read the words of the book open in `ui` (as it closes): from the pages
--- read, at most HARVEST_PAGES back; again only after HARVEST_EVERY more
--- pages. EPUBs and the like (not PDFs). Returns how many words it kept.
function Board.harvest(plugin, ui, now)
    if not Board.enabled(plugin) then return 0 end
    local ok, n = pcall(function()
        if not (ui and ui.rolling and ui.document) then return 0 end
        local doc = ui.document
        local key = doc.file
        if type(key) ~= "string" then return 0 end
        local st = Board.store(plugin)
        local page, total = doc:getCurrentPage(), doc:getPageCount()
        local at
        for i, b in ipairs(st.books) do if b.key == key then at = i end end
        local was = at and st.books[at]
        if was and tonumber(was.page) and math.abs(page - was.page) < Board.HARVEST_EVERY then return 0 end
        local t0 = os.clock()
        local from = math.max(1, page - Board.HARVEST_PAGES)
        local xp0 = doc:getPageXPointer(from)
        local xp1 = page < total and doc:getPageXPointer(page + 1) or doc:getPageXPointer(total)
        local text = doc:getTextFromXPointers(xp0, xp1)
        if type(text) ~= "string" then return 0 end
        if #text > Board.TEXT_MAX then text = text:sub(-Board.TEXT_MAX) end
        local words = Board.bookWords(text)
        -- (the words found before stay, after the new ones)
        local has = {}
        for _i, e in ipairs(words) do has[e.word] = true end
        for _i, e in ipairs(was and was.words or {}) do
            if #words >= Board.BOOK_WORDS then break end
            if type(e) == "table" and type(e.word) == "string" and not has[e.word] then has[e.word] = true; words[#words + 1] = e end
        end
        if #words < 4 then return 0 end
        local props = ui.doc_props or {}
        local entry = { key = key, title = props.display_title or props.title or key:match("([^/]+)$"),
            authors = type(props.authors) == "string" and props.authors:gsub("\n", ", ") or nil,
            page = page, at = now or os.time(), words = words }
        if at then table.remove(st.books, at) end
        table.insert(st.books, 1, entry)
        while #st.books > Board.BOOKS_MAX do table.remove(st.books) end
        keep(plugin)
        require("gzreader_log").info(string.format("game board: %d words from the book's pages %d–%d (%d KB) in %.1f s",
            #words, from, page, math.floor(#text / 1024), os.clock() - t0))
        return #words
    end)
    if not ok then require("gzreader_log").warn("game board: the book's words couldn't be read:", tostring(n)) return 0 end
    return n
end

--- The book of `key` among the kept ones.
function Board.book(plugin, key)
    for _i, b in ipairs(Board.store(plugin).books) do if b.key == key then return b end end
end

---------------------------------------------------------------- themed sets

--- A new set of puzzles: `src` = { kind = "book" | "books" | "season" |
--- "category" | "ai", id (a theme's or book's) }, its title, its words.
--- The words are shuffled by the set's seed (so "New puzzles" gives others).
function Board.makeSet(src, title, entries, now)
    now = now or os.time()
    local seed = tostring(src.kind) .. ":" .. tostring(src.id or "") .. ":" .. tostring(now)
    local list = {}
    for _i, e in ipairs(entries or {}) do list[#list + 1] = { word = e.word, clue = e.clue } end
    Pz().rng("set:" .. seed).shuffle(list)
    -- (words with a clue first: the crossword wants them)
    local clued, bare = {}, {}
    for _i, e in ipairs(list) do if e.clue then clued[#clued + 1] = e else bare[#bare + 1] = e end end
    for _i, e in ipairs(bare) do clued[#clued + 1] = e end
    return { fixed = true, day = seed, kinds = Pz().SET_KINDS, title = title, src = { kind = src.kind, id = src.id, ids = src.ids }, made = now, entries = clued }
end

function Board.seasonSet(now)
    now = now or os.time()
    local theme = Words().season(tonumber(os.date("%m", now)))
    return Board.makeSet({ kind = "season", id = theme.id }, theme.title, Words().entries(theme), now)
end

function Board.categorySet(id, now)
    local theme = Words().byId(id)
    if not theme then return nil end
    return Board.makeSet({ kind = theme.season and "season" or "category", id = theme.id }, theme.title, Words().entries(theme), now)
end

--- A set from one kept book's words (nil: none kept, or too few).
function Board.bookSet(plugin, key, now)
    local b
    if key then b = Board.book(plugin, key) else b = Board.store(plugin).books[1] end
    if not (b and type(b.words) == "table" and #b.words >= 4) then return nil end
    return Board.makeSet({ kind = "book", id = b.key }, T(_("From %1"), b.title or "?"), b.words, now)
end

--- A set from all the kept books' words, a share of each (nil: fewer than two books).
function Board.booksSet(plugin, now)
    local books = Board.store(plugin).books
    if #books < 2 then return nil end
    local entries, has, keys = {}, {}, {}
    local each = math.max(4, math.floor(24 / #books))
    for _i, b in ipairs(books) do
        keys[#keys + 1] = b.key
        local n = 0
        for _j, e in ipairs(b.words or {}) do
            if n >= each then break end
            if type(e) == "table" and e.word and not has[e.word] then has[e.word] = true; entries[#entries + 1] = e; n = n + 1 end
        end
    end
    local set = Board.makeSet({ kind = "books" }, _("From your books"), entries, now)
    set.src.ids = keys
    return set
end

--- The themed set on the board: the one chosen, or the season's. A season's
--- set not started yet follows the season.
function Board.current(plugin, now)
    local st = Board.store(plugin)
    local set = st.set
    local fresh = not (type(set) == "table" and set.fixed and type(set.entries) == "table")
    if not fresh and type(set.src) == "table" and set.src.kind == "season" and set.src.auto and not set.began then
        local theme = Words().season(tonumber(os.date("%m", now or os.time())))
        if theme and theme.id ~= set.src.id then fresh = true end
    end
    if fresh then
        set = Board.seasonSet(now)
        set.src.auto = true
        st.set = set
        keep(plugin)
    end
    return set
end

--- Put a set on the board.
function Board.choose(plugin, set)
    if not set then return false end
    Board.store(plugin).set = set
    plugin:save()
    require("gzreader_log").info("game board: a new set,", tostring(set.src and set.src.kind), #(set.entries or {}), "words")
    return true
end

--- The same theme again, its puzzles new.
function Board.again(plugin, now)
    local set = Board.current(plugin, now)
    local src = set.src or {}
    local new
    if src.kind == "book" then new = Board.bookSet(plugin, src.id, now)
    elseif src.kind == "books" then new = Board.booksSet(plugin, now) end
    if not new then
        new = Board.makeSet(src, set.title, set.entries, now)
        new.src.auto = src.auto
    end
    return Board.choose(plugin, new)
end

---------------------------------------------------------------- a theme from the AI

Board.AI_SYSTEM = "You make word puzzles for an e-reader. Reply with JSON only: no Markdown, no other text."

--- The books named for the AI: { { title, authors } }, the kept ones first,
--- then the history's, ten at most.
function Board.aiBooks(plugin)
    local out, has = {}, {}
    local function add(title, authors)
        if type(title) ~= "string" or title == "" or has[title:lower()] or #out >= 10 then return end
        has[title:lower()] = true
        out[#out + 1] = { title = title, authors = authors }
    end
    for _i, b in ipairs(Board.store(plugin).books) do add(b.title, b.authors) end
    pcall(function()
        for _i, h in ipairs(require("readhistory").hist or {}) do
            local name = type(h.file) == "string" and h.file:match("([^/]+)$")
            if name then add((name:gsub("%.[%w]+$", ""):gsub("[_%.]+", " "))) end
        end
    end)
    return out
end

--- The question: { system, text, max_tokens, what }. Pure.
function Board.aiQuestion(books)
    local lines = {}
    for _i, b in ipairs(books) do
        lines[#lines + 1] = "- " .. b.title .. (b.authors and b.authors ~= "" and (" by " .. b.authors) or "")
    end
    local text = "Books I have been reading:\n" .. table.concat(lines, "\n") .. "\n\n"
        .. "Find one theme these books share (a subject, a setting, a time, a mood or a kind of story). "
        .. "Name it in two to four words. Give 14 English words that fit the theme: each a single word of 4 to 9 letters, "
        .. "A to Z only, no names of real people, and a short crossword clue for each (under 60 characters) that doesn't use the word. "
        .. "Reply only with JSON: {\"theme\": \"…\", \"words\": [{\"word\": \"…\", \"clue\": \"…\"}]}"
    return { system = Board.AI_SYSTEM, text = text, max_tokens = 1200, what = "game board theme", timeout = 60 }
end

--- The AI's answer as a theme: title, entries; or nil.
function Board.parseAI(answer)
    if type(answer) ~= "string" then return nil end
    local json = answer:match("%b{}")
    if not json then return nil end
    local ok, data = pcall(function() return require("gzreader_json").decode(json) end)
    if not ok or type(data) ~= "table" or type(data.words) ~= "table" then return nil end
    local entries, has = {}, {}
    for _i, e in ipairs(data.words) do
        local w = type(e) == "table" and type(e.word) == "string" and e.word:upper():gsub("[%s%-']", "") or nil
        local c = type(e) == "table" and type(e.clue) == "string" and trim(e.clue) or nil
        if w and w:match("^%u+$") and #w >= 3 and #w <= 10 and not has[w] then
            -- (a clue that gives the word away is left out)
            if c and (c == "" or c:upper():find(w, 1, true)) then c = nil end
            has[w] = true
            entries[#entries + 1] = { word = w, clue = c and c:sub(1, 120) or nil }
        end
    end
    if #entries < 6 then return nil end
    local title = type(data.theme) == "string" and trim(data.theme):sub(1, 60) or ""
    if title == "" then title = _("A theme from your books") end
    return title, entries
end

--- Ask the AI for a theme; done(set) or done(nil, why).
function Board.askAI(plugin, done, now)
    local AI = require("gzreader_ai")
    if not AI.ready(plugin) then return done(nil, "no AI key") end
    local books = Board.aiBooks(plugin)
    if #books == 0 then return done(nil, "no books") end
    AI.ask(plugin, Board.aiQuestion(books), function(answer, why)
        local title, entries = Board.parseAI(answer)
        if not title then return done(nil, answer and "no theme in the answer" or why) end
        done(Board.makeSet({ kind = "ai" }, title, entries, now))
    end)
end

---------------------------------------------------------------- history and achievements

local function dayOf(t) return os.date("%Y-%m-%d", t) end

--- Days on end with a puzzle finished, to `today` (or to the day before, when
--- none is finished yet today).
function Board.streak(days, today)
    days = days or {}
    local y, m, d = today:match("^(%d+)%-(%d+)%-(%d+)$")
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    if not days[today] then t = t - 86400 end
    local n = 0
    while days[dayOf(t)] do n = n + 1; t = t - 86400 end
    return n
end

local function count(t) local n = 0 for _k in pairs(t or {}) do n = n + 1 end return n end

Board.ACHIEVEMENTS = {
    { id = "first", title = _("First puzzle"), text = _("Finish a puzzle."), test = function(s) return (s.total or 0) >= 1 end },
    { id = "ten", title = _("Ten down"), text = _("Finish ten puzzles."), test = function(s) return (s.total or 0) >= 10 end },
    { id = "fifty", title = _("Fifty down"), text = _("Finish fifty puzzles."), test = function(s) return (s.total or 0) >= 50 end },
    { id = "hundred", title = _("A hundred down"), text = _("Finish a hundred puzzles."), test = function(s) return (s.total or 0) >= 100 end },
    { id = "sudoku", title = _("Number cruncher"), text = _("Solve a sudoku."), test = function(s) return (s.counts.sudoku or 0) >= 1 end },
    { id = "words", title = _("Word hunter"), text = _("Find every word in a word search."), test = function(s) return (s.counts.words or 0) >= 1 end },
    { id = "cross", title = _("Crossworder"), text = _("Fill in a crossword."), test = function(s) return (s.counts.cross or 0) >= 1 end },
    { id = "maze", title = _("Way out"), text = _("Find your way through a maze."), test = function(s) return (s.counts.maze or 0) >= 1 end },
    { id = "scramble", title = _("Unscrambled"), text = _("Put every word of a scramble right."), test = function(s) return (s.counts.scramble or 0) >= 1 end },
    { id = "paper", title = _("The whole paper"), text = _("Finish all four of a day's paper puzzles."), test = function(s) return (s.paper or 0) >= 1 end },
    { id = "unaided", title = _("No help needed"), text = _("Fill in a crossword without Check."), test = function(s) return (s.unaided or 0) >= 1 end },
    { id = "quick", title = _("Quick thinker"), text = _("Finish a puzzle within three minutes of starting it."), test = function(s) return (s.quick or 0) >= 1 end },
    { id = "book", title = _("Bookworm"), text = _("Finish a puzzle made from one of your books."), test = function(s) return count(s.books) >= 1 end },
    { id = "library", title = _("Library card"), text = _("Finish puzzles from five different books."), test = function(s) return count(s.books) >= 5 end },
    { id = "seasons", title = _("All seasons"), text = _("Finish puzzles of four different seasons."), test = function(s) return count(s.seasons) >= 4 end },
    { id = "explorer", title = _("Explorer"), text = _("Finish puzzles of five different categories."), test = function(s) return count(s.categories) >= 5 end },
    { id = "ai", title = _("Theme spotter"), text = _("Finish a puzzle of a theme the AI found in your books."), test = function(s) return (s.ai or 0) >= 1 end },
    { id = "streak3", title = _("Three days running"), text = _("Finish a puzzle three days in a row."), test = function(s, today) return Board.streak(s.days, today) >= 3 end },
    { id = "streak7", title = _("A week running"), text = _("Finish a puzzle seven days in a row."), test = function(s, today) return Board.streak(s.days, today) >= 7 end },
    { id = "streak30", title = _("A month running"), text = _("Finish a puzzle thirty days in a row."), test = function(s, today) return Board.streak(s.days, today) >= 30 end },
    { id = "night", title = _("Night owl"), text = _("Finish a puzzle between midnight and 5 in the morning."), test = function(s) return (s.night or 0) >= 1 end },
    { id = "early", title = _("Early bird"), text = _("Finish a puzzle between 5 and 7 in the morning."), test = function(s) return (s.early or 0) >= 1 end },
}

--- A puzzle finished: into the history and the counts. `e` = { kind, set
--- (the themed set; nil: the paper's), began, helped, done_n (puzzles of
--- its set or paper now done), of }. Returns the achievements it unlocked
--- (a list of Board.ACHIEVEMENTS' entries).
function Board.record(plugin, e, now)
    now = now or os.time()
    local st = Board.store(plugin)
    local s = st.stats
    s.counts = type(s.counts) == "table" and s.counts or {}
    s.days = type(s.days) == "table" and s.days or {}
    for _i, k in ipairs({ "books", "seasons", "categories" }) do s[k] = type(s[k]) == "table" and s[k] or {} end
    local today = dayOf(now)
    s.total = (s.total or 0) + 1
    s.counts[e.kind] = (s.counts[e.kind] or 0) + 1
    s.days[today] = (s.days[today] or 0) + 1
    -- (only the last 400 days of them)
    if count(s.days) > 400 then
        local list = {}
        for d in pairs(s.days) do list[#list + 1] = d end
        table.sort(list)
        for i = 1, #list - 400 do s.days[list[i]] = nil end
    end
    local set = e.set
    local src = set and set.src or nil
    if not set and e.done_n and e.of and e.done_n >= e.of then s.paper = (s.paper or 0) + 1 end
    if src and src.kind == "book" and src.id then s.books[src.id] = true end
    if src and src.kind == "books" then
        for _i, k in ipairs(type(src.ids) == "table" and src.ids or {}) do s.books[k] = true end
    end
    if src and src.kind == "season" and src.id then s.seasons[src.id] = true end
    if src and src.kind == "category" and src.id then s.categories[src.id] = true end
    if src and src.kind == "ai" then s.ai = (s.ai or 0) + 1 end
    if e.kind == "cross" and not e.helped then s.unaided = (s.unaided or 0) + 1 end
    local took = e.began and (now - e.began) or nil
    if took and took >= 0 and took <= Board.QUICK then s.quick = (s.quick or 0) + 1 end
    local hour = tonumber(os.date("%H", now))
    if hour < 5 then s.night = (s.night or 0) + 1 elseif hour < 7 then s.early = (s.early or 0) + 1 end
    table.insert(st.history, 1, { t = now, k = e.kind, s = set and set.title or nil, src = src and src.kind or "paper", d = took, h = e.helped or nil })
    while #st.history > Board.HISTORY_MAX do table.remove(st.history) end
    if set then set.began = set.began or e.began or now end
    local new = {}
    for _i, a in ipairs(Board.ACHIEVEMENTS) do
        if not st.unlocked[a.id] then
            local ok, yes = pcall(a.test, s, today)
            if ok and yes then st.unlocked[a.id] = now; new[#new + 1] = a end
        end
    end
    plugin:save()
    require("gzreader_log").info("game board: finished", e.kind, set and ("(" .. tostring(src and src.kind) .. ")") or "(the paper)",
        #new > 0 and (#new .. " achievement(s)") or "")
    return new
end

--- A puzzle just finished on the puzzles' page (`pz`: the plugin, or a set's
--- stand-in): noted once. Returns the achievements it unlocked.
function Board.solved(pz, kind, now)
    local P = Pz()
    local first, info = P.markDone(pz, kind)
    if not first then return {} end
    local set = rawget(pz, "gz_set")
    local n = select(2, P.finished(pz))
    return Board.record(P.owner(pz), { kind = kind, set = set, began = info.began, helped = info.helped,
        done_n = n, of = #P.kindsOf(pz) }, now)
end

--- The achievements, with when each was unlocked: { { a, at } }, and how many are.
function Board.achievements(plugin)
    local st = Board.store(plugin)
    local out, n = {}, 0
    for _i, a in ipairs(Board.ACHIEVEMENTS) do
        local at = st.unlocked[a.id]
        if at then n = n + 1 end
        out[#out + 1] = { a = a, at = at }
    end
    return out, n
end

--- A puzzle's name, for the history.
function Board.kindName(kind)
    if kind == "scramble" then return _("Word scramble") end
    return require("gzreader_puzzlescreen").tabLabel(kind)
end

--- How long, in words: "4 min", "1 h 5 min", "2 days".
function Board.tookText(secs)
    if not secs or secs < 0 then return nil end
    if secs < 60 then return T(_("%1 s"), secs) end
    if secs < 3600 then return T(_("%1 min"), math.floor(secs / 60)) end
    if secs < 86400 then return T(_("%1 h %2 min"), math.floor(secs / 3600), math.floor(secs % 3600 / 60)) end
    return T(_("%1 days"), math.floor(secs / 86400 + 0.5))
end

--- The history as text, newest first, a day's heading before its puzzles.
function Board.historyText(plugin)
    local st = Board.store(plugin)
    if #st.history == 0 then return _("No puzzles finished yet. Finished puzzles are listed here, newest first.") end
    local lines, day = {}, nil
    for _i, h in ipairs(st.history) do
        local d = os.date("%a %d %b %Y", h.t):gsub(" 0(%d) ", " %1 ")
        if d ~= day then
            if day then lines[#lines + 1] = "" end
            lines[#lines + 1] = d
            day = d
        end
        local took = Board.tookText(h.d)
        lines[#lines + 1] = "  " .. os.date("%H:%M", h.t) .. "  " .. Board.kindName(h.k) .. " · " .. (h.s or _("the daily paper"))
            .. (took and (" · " .. took) or "") .. (h.h and (" · " .. _("with help")) or "")
    end
    local s = st.stats
    local today = dayOf(os.time())
    local run = Board.streak(s.days, today)
    return T(_("%1 puzzles finished"), s.total or 0) .. " · " .. (run == 1 and _("1 day running") or T(_("%1 days running"), run))
        .. "\n\n" .. table.concat(lines, "\n")
end

--- The achievements as text: unlocked ones with their dates, then the rest.
function Board.achievementsText(plugin)
    local list, n = Board.achievements(plugin)
    local got, left = {}, {}
    for _i, x in ipairs(list) do
        if x.at then got[#got + 1] = "\u{2713} " .. x.a.title .. " · " .. (os.date("%d %b %Y", x.at):gsub("^0", "")) .. "\n    " .. x.a.text
        else left[#left + 1] = "\u{25CB} " .. x.a.title .. "\n    " .. x.a.text end
    end
    local out = T(_("%1 of %2 unlocked"), n, #list)
    if #got > 0 then out = out .. "\n\n" .. table.concat(got, "\n") end
    if #left > 0 then out = out .. "\n\n" .. _("Still to do") .. "\n" .. table.concat(left, "\n") end
    return out
end

---------------------------------------------------------------- the setup guide

--- The setup guide's page about Home's shelf: its choices (ticked as they are now).
function Board.setupChoices(plugin)
    local D = require("gzreader_daily")
    return {
        { id = "gz_paper", text = _("The daily paper (news from feeds you choose, puzzles)"), checked = D.enabled(plugin) },
        { id = "gz_games", text = _("The game board (crosswords, word searches and more)"), checked = Board.enabled(plugin) },
    }
end

--- … and what's ticked, done.
function Board.applySetup(plugin, sel)
    local D = require("gzreader_daily")
    local st = D.store(plugin)
    local paper = sel.gz_paper == true
    if paper ~= D.enabled(plugin) then
        st.enabled = paper or nil
        if paper then st.shelf = nil end
        require("gzreader_log").info("setup guide: daily paper", paper and "on" or "off")
    end
    if (sel.gz_games == true) ~= Board.enabled(plugin) then Board.setEnabled(plugin, sel.gz_games == true) end
    plugin:save()
end

return Board
