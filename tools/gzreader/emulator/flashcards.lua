-- Flashcards (gzreader_flashcards.lua): a book (GZ_EMU_BOOK), this chapter's
-- text as it would be sent, cards made (the AI service's answer stood in
-- for) and saved, then the quiz: a card, its answer, Got it.
--   GZ_EMU_MODEL=scribe GZ_EMU_BOOK=<epub> GZ_EMU_TREE=<tree>/koreader run.sh flashcards.lua <out>
-- Checks go to <out>/flashcards-checks.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function press(w, text)
    for _i, row in ipairs(w and (w.buttons_table or w.buttons) or {}) do
        for _k, b in ipairs(row) do if b.text == text then b.callback(); return true end end
    end
    return false
end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 14 })
add({ fn = function() reader():handleEvent(require("ui/event"):new("GotoPage", 4)) end, after = 3 })
add({ fn = function(E)
    local Cards = require("gzreader_flashcards")
    Cards.statePath = function() return "/tmp/gz-emu-flashcards.lua" end
    os.remove("/tmp/gz-emu-flashcards.lua")
    require("gzreader_ai").settings(reader().gzreader).claude.key = "sk-example"
    local ch = Cards.chapter(reader())
    E.say("chapter:", tostring(ch and ch.part), tostring(ch and #ch.text), "bytes;", tostring(ch and (ch.text:sub(1, 80):gsub("\n", " / "))))
    check(ch ~= nil and #ch.text > 200, "this chapter's text, read from the book (" .. tostring(ch and #ch.text) .. " bytes, " .. tostring(ch and ch.part) .. ")")
    local tile
    for _i, t in ipairs(require("gzreader_panel").bookTiles(reader().gzreader, reader())) do if t.id == "flashcards" then tile = t end end
    check(tile ~= nil, "the quick panel has Flashcards")
    require("gzreader_ai").ask = function(_p, q, cb)
        cb("Q: In which month does the poem begin?\nA: April.\n\nQ: Who says she is no Russian?\nA: Marie.")
    end
    tile.run()
end, after = 3 })
add({ fn = function(E)
    press(top(), "Make cards from this chapter")
end, after = 3 })
add({ shot = "cards-1-confirm" })
add({ fn = function(E)
    local w = top()
    check(w and w.ok_callback ~= nil, "Make cards: asked first")
    if w then UIM():close(w); w.ok_callback() end
end, after = 3 })
add({ shot = "cards-2-preview" })
add({ fn = function(E)
    check(press(top(), "Save"), "the cards to check, then Save")
end, after = 4 })
add({ fn = function(E)
    local Cards = require("gzreader_flashcards")
    check(#Cards.allCards(reader().document.file) == 2, "the deck kept for this book")
    Cards.quiz(Cards.dueCards(Cards.allCards(nil), Cards.state().boxes, os.time()))
end, after = 3 })
add({ shot = "cards-3-question" })
add({ fn = function(E) press(top(), "Show answer") end, after = 3 })
add({ shot = "cards-4-answer" })
add({ fn = function(E)
    press(top(), "Got it")
    local Cards = require("gzreader_flashcards")
    local n = 0
    for _k, b in pairs(Cards.state().boxes) do if b.box == 1 then n = n + 1 end end
    check(n == 1, "Got it: the card up a box")
    local f = io.open(E.out .. "/flashcards-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
