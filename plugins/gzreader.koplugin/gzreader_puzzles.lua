--[[--
The daily paper's puzzles: a sudoku, a word search and a maze, made on the
Kindle (no network), and how far you've got with each (kept until the next
day's paper). The screen is gzreader_puzzlescreen.lua.

The sudoku and the maze come from the day's date alone. The word search and
the crossword take their words from the paper's stories when there is a
paper (the kept edition's headlines first), and from a list of their own
otherwise; they are made once and kept for the day, so fetching the paper
again doesn't change a puzzle you've started. A crossword clue from the
paper is the headline or sentence the word was read in, with the word left
out.

Kept in store.daily.puzzles = { off, day, sudoku = { given, answer, fill },
words = { found = "1,4", of, src, grid, placed },
cross = { src, cols, rows, words = { { w, c, x, y, d } }, fill },
maze = { cols, rows, at, seen } }.
]]

local Puzzles = {
    KINDS = { "sudoku", "words", "cross", "maze" },
    CROSS_SIZE = 11,   -- the crossword is laid out in a square this big, then trimmed to what it uses
    CROSS_WORDS = 9,   -- words wanted in it
    CLUE_LENGTH = 110, -- bytes of a clue, about
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

---------------------------------------------------------------- words from the news

-- Words that say nothing about a story (they'd be in every paper), 4 letters and up.
local STOP = {}
for w in ([[
about above after again against almost along already also although always among another around because become
becomes been before behind being below between both came cannot come comes could does doing done down during each
early either else enough even ever every first five following found four from further gave gets give given gives
going gone good great half have having here hers herself himself however into itself just keep kept know known
last late later least less like likely long made make makes many might more most much must near nearly need never
next none nothing often once only onto other others ours over part past people perhaps said same says seen seven
several shall should show since some soon still such take taken tell than that their theirs them then there these
they thing things think this those though three through thus time times told took toward towards under until upon
used very want wants week weeks well went were what when where whether which while whom whose will with within
without would year years your yours yesterday today tomorrow monday tuesday wednesday thursday friday saturday sunday
january february march april june july august september october november december according reported report reports
news story stories read more click here share email photo photos image images video caption getty reuters editor
]]):gmatch("%a+") do STOP[w:upper()] = true end

-- News has grim words; a puzzle needn't. (Not hidden in the letters, not asked for in a clue.)
local GRIM = {}
for w in ([[
abuse abused assault attack attacked attacks blast bomb bombs bombing bombed cancer corpse crash crashed dead deadly
death deaths died dies dying execution fatal fatally funeral grave gunman hostage hostages injured kidnap kill killed
killer killing kills massacre murder murdered murders rape raped shooting shot slain stabbed stabbing suicide terror
terrorist torture victim victims wounded
]]):gmatch("%a+") do GRIM[w:upper()] = true end

local function stem(w)
    return (w:gsub("ING$", ""):gsub("ED$", ""):gsub("ES$", ""):gsub("S$", ""))
end

--- The words of an edition worth hiding in a puzzle, most telling first:
--- { { word = "BRIDGE", head = true (in a headline), n = times seen,
--- from = where it was read: a headline or the sentence it's in }, … }.
--- Plain A–Z words of `min` to `max` letters; no everyday words, no grim
--- ones, one of each family (VOTE, not also VOTES and VOTED). Headline words
--- first, then the ones seen most, then by the alphabet (so the same paper
--- always gives the same list).
function Puzzles.newsWords(edition, min, max)
    min, max = min or 4, max or 8
    local seen, order = {}, {}
    local function take(text, head)
        if type(text) ~= "string" then return end
        -- (sentence by sentence, so each word knows the sentence it came in)
        for sentence in (text .. " "):gmatch("[^%.%?!\n]+[%.%?!\n]?") do
            for token in sentence:gmatch("[%a'\128-\255]+") do
                if #token >= min and #token <= max and not token:find("[^%a]") then
                    local w = token:upper()
                    if not STOP[w] and not GRIM[w] then
                        local key = stem(w)
                        local e = seen[key]
                        if not e then
                            e = { word = w, n = 0, head = false, from = (sentence:gsub("^%s+", ""):gsub("%s+$", "")) }
                            seen[key] = e
                            order[#order + 1] = e
                        end
                        e.n = e.n + 1
                        if head then e.head = true end
                    end
                end
            end
        end
    end
    for _i, section in ipairs(type(edition) == "table" and type(edition.sections) == "table" and edition.sections or {}) do
        for _j, item in ipairs(type(section.items) == "table" and section.items or {}) do take(item.title, true) end
    end
    for _i, section in ipairs(type(edition) == "table" and type(edition.sections) == "table" and edition.sections or {}) do
        for _j, item in ipairs(type(section.items) == "table" and section.items or {}) do take(item.text, false) end
    end
    table.sort(order, function(a, b)
        if a.head ~= b.head then return a.head end
        if a.n ~= b.n then return a.n > b.n end
        return a.word < b.word
    end)
    return order
end

--- The kept edition, for the puzzles (tests put their own here).
function Puzzles.edition()
    local ok, D = pcall(require, "gzreader_daily")
    if not ok then return nil end
    local ok2, edition = pcall(D.load)
    return ok2 and edition or nil
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
--- `first`: words to hide before the list's own (the news'), in any order;
--- the list fills up what they leave.
function Puzzles.wordSearch(seed, size, count, first)
    size, count = size or Puzzles.WORDS_SIZE, count or Puzzles.WORDS_COUNT
    local R = Puzzles.rng("words:" .. seed)
    local pool, own, has = {}, {}, {}
    for _i, w in ipairs(first or {}) do
        if type(w) == "string" and w:match("^[A-Z]+$") and #w >= 4 and #w <= size - 2 and not has[w] then
            has[w] = true
            pool[#pool + 1] = w
        end
    end
    R.shuffle(pool)
    for _i, w in ipairs(Puzzles.WORD_LIST) do if #w >= 4 and #w <= size - 2 and not has[w] then own[#own + 1] = w end end
    R.shuffle(own)
    for _i, w in ipairs(own) do pool[#pool + 1] = w end
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

---------------------------------------------------------------- crossword

-- Clues for the puzzles' own words (when there's no paper, or its words don't fit).
Puzzles.CLUES = {
    ANCHOR = "It holds a ship where it is", APPLE = "Fruit that keeps the doctor away", ATLAS = "Book of maps",
    AUTUMN = "Season of falling leaves", BAKERY = "Where bread is made and sold", BALLOON = "It rises when filled with hot air",
    BASKET = "Woven carrier for a picnic", BEACON = "Light that warns or guides", BICYCLE = "Two wheels and pedals",
    BLANKET = "Warm cover for a bed", BOTTLE = "Glass container with a neck", BRANCH = "Arm of a tree",
    BRIDGE = "It carries a road over a river", BUTTON = "It fastens a shirt", CABIN = "Small house of logs",
    CACTUS = "Prickly desert plant", CAMERA = "It takes photographs", CANDLE = "Wax light with a wick",
    CANOE = "Narrow boat moved with a paddle", CANYON = "Deep valley with steep sides", CARPET = "Floor covering",
    CASTLE = "Fortress with towers and a moat", CELLAR = "Room under a house", CHERRY = "Small red fruit with a stone",
    CHIMNEY = "Smoke leaves a house by it", CIRCLE = "Round shape", CLOUD = "It drifts across the sky and may bring rain",
    CLOVER = "Lucky with four leaves", COFFEE = "Morning drink made from roasted beans", COMET = "Icy visitor with a tail",
    COMPASS = "Its needle points north", COPPER = "Reddish metal of old coins", CORNER = "Where two walls meet",
    COTTON = "Soft fibre for shirts", CRAYON = "Coloured wax stick for drawing", CUSHION = "Soft pad on a sofa",
    DAISY = "White flower with a yellow middle", DESERT = "Dry land of sand", DINNER = "Evening meal",
    DOLPHIN = "Clever sea mammal that leaps", DRAGON = "Fire-breathing beast of stories", DRAWER = "It slides out of a desk",
    EAGLE = "Large bird of prey", ECHO = "A sound that comes back", ELBOW = "Joint in the middle of an arm",
    ENGINE = "It makes a car go", FABLE = "Short tale with a moral", FALCON = "Fast hunting bird",
    FEATHER = "A bird is covered in them", FERRY = "Boat that carries cars across", FIDDLE = "Another name for a violin",
    FLOWER = "Bloom", FOREST = "Many trees together", FOSSIL = "Ancient remains in stone",
    GARDEN = "Where flowers and vegetables grow", GINGER = "Spicy root", GLACIER = "Slow river of ice",
    GOBLET = "Drinking cup with a stem", GRAVEL = "Small stones on a path", GUITAR = "Six strings and a neck",
    HAMMER = "Tool for nails", HARBOR = "Shelter for ships", HARVEST = "Gathering in of crops",
    HAZEL = "Tree with small round nuts", HELMET = "It protects the head", HERON = "Long-legged wading bird",
    HONEY = "Sweet food made by bees", HORIZON = "Where the sky meets the land", ISLAND = "Land with water all round",
    IVORY = "What a tusk is made of", JACKET = "Short coat", JIGSAW = "Puzzle of many pieces",
    JUNGLE = "Thick tropical forest", KETTLE = "It boils water for tea", KITCHEN = "Room for cooking",
    LADDER = "You climb it rung by rung", LAGOON = "Shallow water behind a reef", LANTERN = "Lamp you can carry",
    LEMON = "Sour yellow fruit", LETTER = "It comes in an envelope", LIBRARY = "Place that lends books",
    LIZARD = "Small reptile that basks in the sun", MAGNET = "It attracts iron", MAPLE = "Tree that gives syrup",
    MARBLE = "Small glass ball, or a stone for statues", MARKET = "Place of stalls", MEADOW = "Field of grass and wild flowers",
    MIRROR = "It shows your reflection", MITTEN = "Glove without fingers", MONSOON = "Season of heavy rain",
    MORNING = "Start of the day", MUSEUM = "Building of exhibits", NEEDLE = "It pulls the thread",
    NOVEL = "Long story in a book", OCEAN = "Vast body of salt water", OLIVE = "Small fruit pressed for oil",
    ORANGE = "Fruit and colour", ORCHARD = "Field of fruit trees", OTTER = "Playful river mammal",
    OYSTER = "Shellfish that may hold a pearl", PADDLE = "It moves a canoe", PARROT = "Bird that can copy speech",
    PEBBLE = "Small smooth stone", PENCIL = "It writes in graphite", PEPPER = "Salt's partner",
    PIANO = "Instrument with black and white keys", PICNIC = "Meal eaten outdoors", PIGEON = "Bird of city squares",
    PILLOW = "Rest for a sleeping head", PLANET = "Mars or Venus", POCKET = "Pouch sewn into trousers",
    POTTERY = "Things made of fired clay", PUDDLE = "Small pool after rain", PUMPKIN = "Large orange squash",
    PUZZLE = "What you are doing now", QUARTZ = "Crystal in many watches", QUILT = "Padded bed cover of patches",
    RABBIT = "Long-eared burrower", RAVEN = "Large black bird", RIBBON = "Strip of cloth for tying a gift",
    RIVER = "It flows to the sea", ROCKET = "It carries astronauts up", SADDLE = "Seat on a horse",
    SAILOR = "One who works on a ship", SALMON = "Fish that swims upstream", SANDAL = "Open summer shoe",
    SCARF = "Worn round the neck in winter", SHADOW = "It follows you on a sunny day", SIGNAL = "Sign to stop or go",
    SILVER = "Metal of second place", SKETCH = "Quick drawing", SPARROW = "Small brown garden bird",
    SPIDER = "Eight-legged spinner of webs", SPONGE = "It soaks up water", SQUARE = "Shape with four equal sides",
    STABLE = "Where horses are kept", STREAM = "Small river", SUMMER = "Warmest season",
    SUNSET = "End of the day in the west", TEAPOT = "It pours a brew", THIMBLE = "Cap that protects a sewing finger",
    THUNDER = "Sound that follows lightning", TICKET = "It lets you board the train", TIMBER = "Wood for building",
    TRACTOR = "Farm vehicle", TULIP = "Spring flower from a bulb", TUNNEL = "Passage under a hill",
    TURTLE = "Reptile with a shell", UMBRELLA = "Shelter from the rain you carry", VALLEY = "Low land between hills",
    VELVET = "Soft cloth with a pile", VIOLIN = "Instrument played with a bow", VOYAGE = "Long journey by sea",
    WAGON = "Four-wheeled cart", WALNUT = "Nut with a wrinkled kernel", WHISTLE = "A referee blows it",
    WILLOW = "Tree that weeps by the water", WINDOW = "Glass you look out through", WINTER = "Coldest season",
}

--- A crossword clue from where a word was read: the headline or sentence
--- with the word left out ("Council votes to keep the old _____ open"), cut
--- to about CLUE_LENGTH round the gap. nil when too little is left to go on.
function Puzzles.clueFrom(word, sentence)
    if type(sentence) ~= "string" or type(word) ~= "string" or word == "" then return nil end
    local text = sentence:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local low, w = text:lower(), word:lower()
    local parts, at, first = {}, 1, nil
    while true do
        local a, b = low:find("%f[%a\128-\255]" .. w .. "%f[^%a\128-\255]", at)
        if not a then break end
        first = first or (#table.concat(parts) + (a - at) + 1)
        parts[#parts + 1] = text:sub(at, a - 1)
        parts[#parts + 1] = "_____"
        at = b + 1
    end
    if not first then return nil end
    parts[#parts + 1] = text:sub(at)
    local clue = table.concat(parts)
    -- (what's left must say something: three other words at least)
    local others = 0
    for token in clue:gmatch("[%a\128-\255]+") do if #token > 1 then others = others + 1 end end
    if others < 3 then return nil end
    if #clue > Puzzles.CLUE_LENGTH then
        -- (cut at spaces, keeping the gap in view)
        local half = math.floor(Puzzles.CLUE_LENGTH / 2)
        local from, to = math.max(1, first - half), math.min(#clue, first + 5 + half)
        if from > 1 then from = (clue:find(" ", from, true) or from) + 1 end
        if to < #clue then
            local cut = clue:sub(1, to):match("^.*() ")
            to = cut and cut - 1 or to
        end
        clue = (from > 1 and "\u{2026}" or "") .. clue:sub(from, to) .. (to < #clue and "\u{2026}" or "")
    end
    return clue
end

--- A crossword from words and their clues. `entries` = { { word = "BRIDGE",
--- clue = "…" }, … }, the ones wanted most first. Returns { cols, rows,
--- words = { { word, clue, x, y, d = "a" (across) | "d" (down), n = its
--- number } } } with x, y from 1 inside cols × rows, numbered as crosswords
--- are (left to right, top to bottom). Every word crosses another; no two
--- words touch except where they cross.
function Puzzles.crossword(seed, entries, size, count)
    size, count = size or Puzzles.CROSS_SIZE, count or Puzzles.CROSS_WORDS
    local pool, has = {}, {}
    for _i, e in ipairs(entries or {}) do
        if type(e) == "table" and type(e.word) == "string" and e.word:match("^[A-Z]+$") and #e.word >= 3 and #e.word <= size
            and type(e.clue) == "string" and e.clue ~= "" and not has[e.word] then
            has[e.word] = true
            pool[#pool + 1] = e
        end
    end
    local function attempt(order)
        local letters, dirs, placed = {}, {}, {}
        local function at(x, y) return letters[(y - 1) * size + x] end
        local function inside(x, y) return x >= 1 and x <= size and y >= 1 and y <= size end
        --- How many letters a word would share there, or nil when it can't go there.
        local function fits(w, x, y, d)
            local dx, dy = d == "a" and 1 or 0, d == "a" and 0 or 1
            local ex, ey = x + dx * (#w - 1), y + dy * (#w - 1)
            if not inside(x, y) or not inside(ex, ey) then return nil end
            if (inside(x - dx, y - dy) and at(x - dx, y - dy)) or (inside(ex + dx, ey + dy) and at(ex + dx, ey + dy)) then return nil end
            local shared = 0
            for i = 0, #w - 1 do
                local cx, cy = x + dx * i, y + dy * i
                local have = at(cx, cy)
                if have then
                    if have ~= w:sub(i + 1, i + 1) or dirs[(cy - 1) * size + cx][d] then return nil end
                    shared = shared + 1
                else
                    -- (an empty square's side neighbours must be empty, or two words would touch)
                    if (inside(cx + dy, cy + dx) and at(cx + dy, cy + dx)) or (inside(cx - dy, cy - dx) and at(cx - dy, cy - dx)) then return nil end
                end
            end
            return shared
        end
        local function put(e, x, y, d)
            local dx, dy = d == "a" and 1 or 0, d == "a" and 0 or 1
            for i = 0, #e.word - 1 do
                local idx = (y + dy * i - 1) * size + x + dx * i
                letters[idx] = e.word:sub(i + 1, i + 1)
                dirs[idx] = dirs[idx] or {}
                dirs[idx][d] = true
            end
            placed[#placed + 1] = { word = e.word, clue = e.clue, x = x, y = y, d = d }
        end
        local used = {}
        -- the first: across the middle
        local e1 = order[1]
        if not e1 then return placed end
        put(e1, math.floor((size - #e1.word) / 2) + 1, math.floor(size / 2) + 1, "a")
        used[1] = true
        for _pass = 1, 2 do
            for k = 2, #order do
                if #placed >= count then break end
                if not used[k] then
                    local w = order[k].word
                    local best, best_score
                    for i = 1, #w do
                        local ch = w:sub(i, i)
                        for idx, have in pairs(letters) do
                            if have == ch then
                                local cx, cy = (idx - 1) % size + 1, math.floor((idx - 1) / size) + 1
                                for _j, d in ipairs({ "a", "d" }) do
                                    local x, y = cx - (d == "a" and i - 1 or 0), cy - (d == "d" and i - 1 or 0)
                                    local shared = fits(w, x, y, d)
                                    if shared and shared >= 1 then
                                        -- (more crossings first; then nearer the middle; then one fixed order)
                                        local mid = (size + 1) / 2
                                        local mx, my = x + (d == "a" and (#w - 1) / 2 or 0), y + (d == "d" and (#w - 1) / 2 or 0)
                                        local score = shared * 100 - (math.abs(mx - mid) + math.abs(my - mid)) - (y * size + x) / 10000 - (d == "d" and 0.00001 or 0)
                                        if not best_score or score > best_score then best, best_score = { x, y, d }, score end
                                    end
                                end
                            end
                        end
                    end
                    if best then
                        put(order[k], best[1], best[2], best[3])
                        used[k] = true
                    end
                end
            end
        end
        return placed
    end
    -- a few tries, each starting from another of the first words; the fullest wins
    -- (`seed` is in the order the caller shuffled `entries` into; the tries themselves are fixed)
    local _ = seed
    local best = {}
    for try = 1, math.min(6, #pool) do
        local order = {}
        for i, e in ipairs(pool) do order[i] = e end
        order[1], order[try] = order[try], order[1]
        local placed = attempt(order)
        if #placed > #best then best = placed end
        if #best >= count then break end
    end
    -- trimmed to what it uses, and numbered
    local x1, y1, x2, y2 = size, size, 1, 1
    for _i, w in ipairs(best) do
        local ex, ey = w.x + (w.d == "a" and #w.word - 1 or 0), w.y + (w.d == "d" and #w.word - 1 or 0)
        x1, y1, x2, y2 = math.min(x1, w.x), math.min(y1, w.y), math.max(x2, ex), math.max(y2, ey)
    end
    if #best == 0 then return { cols = 0, rows = 0, words = {} } end
    for _i, w in ipairs(best) do w.x, w.y = w.x - x1 + 1, w.y - y1 + 1 end
    local out = { cols = x2 - x1 + 1, rows = y2 - y1 + 1, words = best }
    Puzzles.crossNumber(out)
    return out
end

--- Number a crossword's words as crosswords are: the squares where a word
--- starts, left to right and top to bottom (an across and a down from the
--- same square share a number); the words sorted by number, across first.
function Puzzles.crossNumber(cw)
    local starts = {}
    for _i, w in ipairs(cw.words) do starts[(w.y - 1) * cw.cols + w.x] = true end
    local keys = {}
    for k in pairs(starts) do keys[#keys + 1] = k end
    table.sort(keys)
    local number = {}
    for n, k in ipairs(keys) do number[k] = n end
    for _i, w in ipairs(cw.words) do w.n = number[(w.y - 1) * cw.cols + w.x] end
    table.sort(cw.words, function(a, b)
        if a.d ~= b.d then return a.d == "a" end
        return a.n < b.n
    end)
    return cw
end

--- A crossword's squares: { [cell] = { letter, n = number shown (or nil),
--- a = its across word's place in cw.words, d = its down word's } }
--- (cell = (row - 1) × cols + col).
function Puzzles.crossCells(cw)
    local cells = {}
    for i, w in ipairs(cw.words) do
        for k = 0, #w.word - 1 do
            local idx = (w.y + (w.d == "d" and k or 0) - 1) * cw.cols + w.x + (w.d == "a" and k or 0)
            local c = cells[idx] or { letter = w.word:sub(k + 1, k + 1) }
            cells[idx] = c
            c[w.d] = i
            if k == 0 then c.n = w.n end
        end
    end
    return cells
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
        p.day, p.sudoku, p.words, p.cross, p.maze = day, nil, nil, nil, nil
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

-- How many of the news' words a word search is offered (more than it hides: not every word fits).
Puzzles.NEWS_POOL = 24

local function packWords(ws)
    local out = {}
    for _i, w in ipairs(ws.words) do out[#out + 1] = table.concat({ w.word, w.x, w.y, w.dx, w.dy }, ":") end
    return table.concat(out, ",")
end

local function unpackWords(p)
    if type(p) ~= "table" or type(p.grid) ~= "string" or type(p.placed) ~= "string" then return nil end
    local size = math.floor(math.sqrt(#p.grid) + 0.5)
    if size < 4 or size * size ~= #p.grid or p.grid:find("[^A-Z]") then return nil end
    local words = {}
    for word, x, y, dx, dy in p.placed:gmatch("(%u+):(%d+):(%d+):(%-?%d):(%-?%d)") do
        words[#words + 1] = { word = word, x = tonumber(x), y = tonumber(y), dx = tonumber(dx), dy = tonumber(dy) }
    end
    if #words == 0 then return nil end
    return { size = size, grid = p.grid, words = words, src = p.src }
end

--- Where the day's word puzzles take their words from now: the kept
--- edition's day ("2026-11-26") when it has words enough, else "list".
function Puzzles.source(edition)
    if type(edition) == "table" and edition.day and #Puzzles.newsWords(edition) >= 4 then return tostring(edition.day) end
    return "list"
end

--- The day's word search and which words are found: ws, { [n] = true }.
--- Made the first time it's asked for, from the paper's words when there is
--- a paper, and kept for the day (ws.src says which paper, or "list").
function Puzzles.dayWords(plugin, day)
    local p = Puzzles.state(plugin, day)
    local ws = unpackWords(p.words)
    if not ws then
        local edition = Puzzles.edition()
        local src = Puzzles.source(edition)
        local first = {}
        if src ~= "list" then
            for i, e in ipairs(Puzzles.newsWords(edition, 4, Puzzles.WORDS_SIZE - 2)) do
                if i > Puzzles.NEWS_POOL then break end
                first[#first + 1] = e.word
            end
        end
        ws = Puzzles.wordSearch(p.day .. (src ~= "list" and (":" .. src) or ""), nil, nil, first)
        ws.src = src
        p.words = { grid = ws.grid, placed = packWords(ws), src = src, of = #ws.words }
        keep(plugin)
    end
    local found = {}
    if type(p.words.found) == "string" then
        for n in p.words.found:gmatch("%d+") do
            if ws.words[tonumber(n)] then found[tonumber(n)] = true end
        end
    end
    return ws, found
end

--- A word puzzle not started yet is made again when the paper it would take
--- its words from has changed (the paper fetched since, or a new day's):
--- call when the puzzles are opened. Returns true when one will be remade.
function Puzzles.freshen(plugin, day)
    local p = Puzzles.state(plugin, day)
    local src = Puzzles.source(Puzzles.edition())
    local changed = false
    if type(p.words) == "table" and p.words.src ~= src and (p.words.found or "") == "" then
        p.words = nil
        changed = true
    end
    if type(p.cross) == "table" and p.cross.src ~= src and not tostring(p.cross.fill or ""):find("%u") then
        p.cross = nil
        changed = true
    end
    if changed then keep(plugin) end
    return changed
end

--- Mark a word found. Returns true when it's new.
function Puzzles.wordFound(plugin, n)
    local ws, found = Puzzles.dayWords(plugin)
    if not ws.words[n] or found[n] then return false end
    found[n] = true
    local list = {}
    for i = 1, #ws.words do if found[i] then list[#list + 1] = i end end
    local w = Puzzles.state(plugin).words
    w.found, w.of = table.concat(list, ","), #ws.words
    keep(plugin)
    return true
end

--- The day's crossword and what you've written: cw (as Puzzles.crossword
--- gives it, with cw.src), fill (cols × rows characters: a letter, or "."
--- where nothing is written or there is no square). Made the first time
--- it's asked for, from the paper's words and the sentences they came in
--- when there is a paper, filled up from the puzzles' own; kept for the day.
function Puzzles.dayCross(plugin, day)
    local p = Puzzles.state(plugin, day)
    local c = p.cross
    local cw
    if type(c) == "table" and type(c.words) == "table" and tonumber(c.cols) and tonumber(c.rows) then
        cw = { cols = c.cols, rows = c.rows, src = c.src, words = {} }
        for _i, w in ipairs(c.words) do
            if type(w) == "table" and type(w.w) == "string" and w.w:match("^%u+$") and tonumber(w.x) and tonumber(w.y) and (w.d == "a" or w.d == "d") then
                cw.words[#cw.words + 1] = { word = w.w, clue = tostring(w.c or ""), x = w.x, y = w.y, d = w.d }
            end
        end
        if #cw.words < 2 or #cw.words ~= #c.words then cw = nil else Puzzles.crossNumber(cw) end
    end
    if not cw then
        local edition = Puzzles.edition()
        local src = Puzzles.source(edition)
        local seed = p.day .. (src ~= "list" and (":" .. src) or "")
        local R = Puzzles.rng("cross:" .. seed)
        local entries, has = {}, {}
        if src ~= "list" then
            local news = {}
            for _i, e in ipairs(Puzzles.newsWords(edition, 4, 9)) do
                if #news >= 30 then break end
                local clue = Puzzles.clueFrom(e.word, e.from)
                if clue then news[#news + 1] = { word = e.word, clue = clue } end
            end
            -- (in their order: headline words first)
            for _i, e in ipairs(news) do entries[#entries + 1] = e; has[e.word] = true end
        end
        local own = {}
        for _i, w in ipairs(Puzzles.WORD_LIST) do
            if Puzzles.CLUES[w] and not has[w] then own[#own + 1] = { word = w, clue = Puzzles.CLUES[w] } end
        end
        R.shuffle(own)
        for i = 1, math.min(#own, 40) do entries[#entries + 1] = own[i] end
        cw = Puzzles.crossword(seed, entries)
        cw.src = src
        local kept = {}
        for i, w in ipairs(cw.words) do kept[i] = { w = w.word, c = w.clue, x = w.x, y = w.y, d = w.d } end
        p.cross = { src = src, cols = cw.cols, rows = cw.rows, words = kept, fill = string.rep(".", cw.cols * cw.rows) }
        keep(plugin)
    end
    local fill = p.cross.fill
    if type(fill) ~= "string" or #fill ~= cw.cols * cw.rows or fill:find("[^%u%.]") then
        fill = string.rep(".", cw.cols * cw.rows)
        p.cross.fill = fill
    end
    return cw, fill
end

--- Write a letter ("" or nil rubs out) in a square of the day's crossword.
--- Returns true when it changed.
function Puzzles.crossSet(plugin, cell, letter)
    local cw, fill = Puzzles.dayCross(plugin)
    letter = type(letter) == "string" and letter:upper() or ""
    if letter ~= "" and not letter:match("^%u$") then return false end
    if not Puzzles.crossCells(cw)[cell] then return false end
    local ch = letter == "" and "." or letter
    if fill:sub(cell, cell) == ch then return false end
    Puzzles.state(plugin).cross.fill = fill:sub(1, cell - 1) .. ch .. fill:sub(cell + 1)
    keep(plugin)
    return true
end

--- The squares written that aren't right { [cell] = true }, how many squares
--- are still empty, and whether it's solved.
function Puzzles.crossCheck(cw, fill)
    local wrong, left = {}, 0
    for cell, c in pairs(Puzzles.crossCells(cw)) do
        local ch = fill:sub(cell, cell)
        if ch == "." or ch == "" then left = left + 1
        elseif ch ~= c.letter then wrong[cell] = true end
    end
    return wrong, left, left == 0 and next(wrong) == nil
end

--- Start the day's crossword again.
function Puzzles.crossClear(plugin)
    local cw = Puzzles.dayCross(plugin)
    Puzzles.state(plugin).cross.fill = string.rep(".", cw.cols * cw.rows)
    keep(plugin)
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
    local out = { sudoku = false, words = false, cross = false, maze = false }
    if type(p.sudoku) == "table" and p.sudoku.fill and p.sudoku.fill == p.sudoku.answer then out.sudoku = true end
    if type(p.words) == "table" and type(p.words.found) == "string" then
        local n = 0
        for _ in p.words.found:gmatch("%d+") do n = n + 1 end
        out.words = n >= (tonumber(p.words.of) or Puzzles.WORDS_COUNT)
    end
    if type(p.maze) == "table" and p.maze.cols and p.maze.at == p.maze.cols * p.maze.rows then out.maze = true end
    if type(p.cross) == "table" and type(p.cross.fill) == "string" and p.cross.fill:find("%u") then
        -- (only looked at once something is written: making it is left to the page)
        local ok, cw, fill = pcall(Puzzles.dayCross, plugin, day)
        if ok then out.cross = select(3, Puzzles.crossCheck(cw, fill)) end
    end
    local n = 0
    for _i, k in ipairs(Puzzles.KINDS) do if out[k] then n = n + 1 end end
    return out, n
end

return Puzzles
