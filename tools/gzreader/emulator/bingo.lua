-- Bingo on the game board (gzreader_bingo.lua, gzreader_bingoscreen.lua): its
-- card on the board beside the paper's three, the hall (the caller's ball,
-- your card, Call and New game), a square refused before its number is
-- called, balls called and daubed to a line: BINGO, the achievement, the
-- board's history; New game.
--   GZ_EMU_MODEL=pw3|k3 GZ_EMU_TREE=<tree>/koreader ./run.sh bingo.lua <out>
-- Checks in <out>/bingo-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local checks = {}
local function check(E, ok, msg)
    checks[#checks + 1] = (ok and "ok   " or "FAIL ") .. msg
    E.say(checks[#checks])
end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end

add({ fn = function(E)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    local p = plugin()
    require("gzreader_gameboard").applySetup(p, { gz_paper = true, gz_games = true })
    require("gzreader_daily").fetch = function() return nil, "offline" end
    E.board = require("gzreader_gameboardscreen").show(p)
end, after = 5 })
add({ shot = "bingo-1-board" })
add({ fn = function(E)
    local b = E.board
    local card
    for _i, c in ipairs(b and b.cards or {}) do if c.kind == "bingo" then card = c end end
    local paper_last = b and b.cards[3]
    check(E, card ~= nil and #b.cards == 8 and paper_last and card.y == paper_last.y and card.x > paper_last.x and card.w == paper_last.w,
        "the board: a Bingo card, the fourth of the paper's row")
    if card then card.run() end
end, after = 4 })
add({ shot = "bingo-2-hall" })
add({ fn = function(E)
    local Hall = require("gzreader_bingoscreen")
    local Bingo = require("gzreader_bingo")
    local h = Hall.instance
    E.hall = h
    local b = Bingo.state(plugin())
    check(E, h ~= nil and b.called == 0 and h.L.fits, "the hall opens: a new game, the card fits the screen")
    h:daub(1)
    check(E, (h.note or ""):find("hasn't been called", 1, true) ~= nil and b.marks:sub(1, 1) == "0",
        "a square before its number is called: refused, and said (" .. tostring(h.note) .. ")")
    for _i = 1, 3 do h:call() end
    check(E, b.called == 3, "Call, three times: three balls out")
end, after = 3 })
add({ shot = "bingo-3-called" })
add({ fn = function(E)
    local Bingo = require("gzreader_bingo")
    local h = E.hall
    local b = Bingo.state(plugin())
    -- play on: daub whatever is called, until a line
    local guard = 0
    while not b.won and guard < 80 do
        guard = guard + 1
        for _i, sq in ipairs(Bingo.waiting(b)) do
            if not b.won then h:daub(sq) end
        end
        if not b.won then h:call() end
    end
    E.calls = b.won
    check(E, b.won ~= nil and b.won <= 75 and Bingo.line(b.marks) ~= nil, "played on: BINGO in " .. tostring(b.won) .. " calls")
end, after = 6 })
add({ shot = "bingo-4-won" })
add({ fn = function(E)
    local p = plugin()
    local Bingo = require("gzreader_bingo")
    local hist = p.store.games.history[1]
    check(E, hist and hist.k == "bingo" and hist.s == Bingo.calls(E.calls) and p.store.games.unlocked.bingo ~= nil,
        "in the board's history (Bingo · " .. tostring(hist and hist.s) .. "), the Bingo! achievement unlocked")
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.text and tostring(w.text):find("Achievement", 1, true) then UIM():close(w) end
    end
    E.hall:newGame()
    local b = Bingo.state(p)
    check(E, b.played == 2 and b.called == 0 and b.won == nil and b.best == E.calls, "New game: another card, your best kept")
    E.hall:onBgClose()
end, after = 4 })
add({ shot = "bingo-5-board-after" })
add({ fn = function(E)
    local b = E.board
    local card
    for _i, c in ipairs(b and b.cards or {}) do if c.kind == "bingo" then card = c end end
    check(E, require("gzreader_bingoscreen").instance == nil and card ~= nil and not card.done,
        "closed: back on the board, drawn again")
    local f = io.open(E.out .. "/bingo-checks.txt", "w")
    f:write(table.concat(checks, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
