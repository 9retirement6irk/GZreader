--[[--
Bingo on the game board: the 75-ball game, played alone against the caller.

A card of five columns, B I N G O, five numbers each from the column's
fifteen (B 1-15, I 16-30, N 31-45, G 46-60, O 61-75), its middle square
free. The caller draws the 75 balls in an order of its own, one each time
you ask. You daub the squares yourself: a square can only be daubed once
its number has been called. Five in a line (a row, a column or a diagonal)
is Bingo; the game is how few calls you need (about 41 on average).

Card and calls come from the game's seed alone (the day and how many games
have been played), so a game half played is the same game after a restart.

Kept in store.games.bingo = { seed, card = { 25 numbers, 0 the free one },
called (how many balls), marks ("0"/"1" × 25), began, won (the calls it
took), best (fewest calls ever), played (games started), wins }.
]]

local Bingo = {
    LETTERS = { "B", "I", "N", "G", "O" },
    BALLS = 75,
    QUICK = 30, -- (a win within this many calls: the Quick caller achievement)
}

local function Board() return require("gzreader_gameboard") end

--- Numbers from a seed, the same on every device: next() gives 1..n.
function Bingo.rng(seed)
    local state = 0
    for i = 1, #seed do state = (state * 31 + seed:byte(i)) % 2147483647 end
    if state == 0 then state = 1 end
    for _i = 1, 4 do state = (state * 16807) % 2147483647 end
    return function(n)
        state = (state * 16807) % 2147483647
        return (state % n) + 1
    end
end

--- A card: 25 numbers, row by row (index (row - 1) * 5 + column), 0 in the middle.
function Bingo.card(seed)
    local R = Bingo.rng("card:" .. seed)
    local card = {}
    for col = 1, 5 do
        local pool = {}
        for n = 1, 15 do pool[n] = (col - 1) * 15 + n end
        for row = 1, 5 do
            local k = R(#pool)
            card[(row - 1) * 5 + col] = table.remove(pool, k)
        end
    end
    card[13] = 0
    return card
end

--- The caller's order: the 75 balls, shuffled.
function Bingo.order(seed)
    local R = Bingo.rng("calls:" .. seed)
    local balls = {}
    for n = 1, Bingo.BALLS do balls[n] = n end
    for i = Bingo.BALLS, 2, -1 do
        local k = R(i)
        balls[i], balls[k] = balls[k], balls[i]
    end
    return balls
end

--- A ball as it's called: "B 7", "O 61".
function Bingo.name(n)
    if type(n) ~= "number" or n < 1 or n > Bingo.BALLS then return "" end
    return Bingo.LETTERS[math.floor((n - 1) / 15) + 1] .. " " .. n
end

Bingo.LINES = {}
for r = 0, 4 do Bingo.LINES[#Bingo.LINES + 1] = { r * 5 + 1, r * 5 + 2, r * 5 + 3, r * 5 + 4, r * 5 + 5 } end
for c = 1, 5 do Bingo.LINES[#Bingo.LINES + 1] = { c, c + 5, c + 10, c + 15, c + 20 } end
Bingo.LINES[#Bingo.LINES + 1] = { 1, 7, 13, 19, 25 }
Bingo.LINES[#Bingo.LINES + 1] = { 5, 9, 13, 17, 21 }

--- The first line of five daubed in `marks` ("0"/"1" × 25), or nil.
function Bingo.line(marks)
    for _i, l in ipairs(Bingo.LINES) do
        local all = true
        for _j, sq in ipairs(l) do
            if marks:sub(sq, sq) ~= "1" then all = false; break end
        end
        if all then return l end
    end
end

local FRESH_MARKS = "000000000000100000000000" .. "0" -- (the free square daubed)

--- The game being played (a new one when there's none).
function Bingo.state(plugin, now)
    local games = Board().store(plugin)
    local b = games.bingo
    if type(b) ~= "table" or type(b.card) ~= "table" or #b.card ~= 25 or type(b.marks) ~= "string" or #b.marks ~= 25 then
        b = { played = type(b) == "table" and tonumber(b.played) or 0, wins = type(b) == "table" and tonumber(b.wins) or 0,
            best = type(b) == "table" and tonumber(b.best) or nil }
        games.bingo = b
        Bingo.deal(plugin, now)
    end
    return games.bingo
end

--- A new game: a new card, the balls back in the cage.
function Bingo.deal(plugin, now)
    now = now or os.time()
    local games = Board().store(plugin)
    local b = type(games.bingo) == "table" and games.bingo or {}
    games.bingo = b
    b.played = (tonumber(b.played) or 0) + 1
    b.seed = os.date("%Y-%m-%d", now) .. ":" .. b.played
    b.card = Bingo.card(b.seed)
    b.called, b.marks, b.began, b.won = 0, FRESH_MARKS, nil, nil
    plugin:save()
    return b
end

--- The balls called so far, the newest last.
function Bingo.calledBalls(b)
    local order, out = Bingo.order(b.seed), {}
    for i = 1, math.min(b.called or 0, Bingo.BALLS) do out[i] = order[i] end
    return out
end

--- Has `n` been called?
function Bingo.isCalled(b, n)
    if n == 0 then return true end
    local order = Bingo.order(b.seed)
    for i = 1, math.min(b.called or 0, Bingo.BALLS) do if order[i] == n then return true end end
    return false
end

--- Call the next ball. Returns it, or nil (the game is won, or the cage is empty).
function Bingo.call(plugin, now)
    local b = Bingo.state(plugin, now)
    if b.won or b.called >= Bingo.BALLS then return nil end
    b.called = b.called + 1
    b.began = b.began or now or os.time()
    if plugin.saveSoon then plugin:saveSoon() else plugin:save() end
    return Bingo.order(b.seed)[b.called]
end

--- Daub square `sq` (1..25). Returns "daubed", "bingo" (with the achievements
--- it unlocked), "already", "not called" (its number hasn't been called) or
--- "over" (the game is won).
function Bingo.daub(plugin, sq, now)
    local b = Bingo.state(plugin, now)
    if b.won then return "over" end
    if type(sq) ~= "number" or sq < 1 or sq > 25 then return "not called" end
    if b.marks:sub(sq, sq) == "1" then return "already" end
    if not Bingo.isCalled(b, b.card[sq]) then return "not called" end
    b.marks = b.marks:sub(1, sq - 1) .. "1" .. b.marks:sub(sq + 1)
    if not Bingo.line(b.marks) then
        if plugin.saveSoon then plugin:saveSoon() else plugin:save() end
        return "daubed"
    end
    now = now or os.time()
    b.won = b.called
    b.wins = (tonumber(b.wins) or 0) + 1
    if not b.best or b.called < b.best then b.best = b.called end
    local stats = Board().store(plugin).stats
    if b.called <= Bingo.QUICK then stats.bingo_quick = (stats.bingo_quick or 0) + 1 end
    -- (into the board's history as "Bingo · 23 calls"; no time taken: a game is counted in calls)
    local new = Board().record(plugin, { kind = "bingo", set = { title = Bingo.calls(b.called) } }, now)
    return "bingo", new
end

--- "23 calls" (the history's line for a game won).
function Bingo.calls(n)
    local _ = require("gettext")
    local T = require("ffi/util").template
    if n == 1 then return _("1 call") end
    return T(_("%1 calls"), n)
end

--- Squares whose number has been called but aren't daubed yet (a list of 1..25).
function Bingo.waiting(b)
    local out, called = {}, {}
    for _i, n in ipairs(Bingo.calledBalls(b)) do called[n] = true end
    for sq = 1, 25 do
        if b.marks:sub(sq, sq) ~= "1" and called[b.card[sq]] then out[#out + 1] = sq end
    end
    return out
end

return Bingo
