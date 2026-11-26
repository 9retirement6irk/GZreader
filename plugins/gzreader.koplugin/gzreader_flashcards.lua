--[[--
Flashcards: question-and-answer cards made from what you read by your AI
service (gzreader_ai.lua), kept as notes in Memos, and a quiz on the Kindle.

Making cards (with an AI key set up):
- **From this chapter**: the quick panel's **Flashcards** in a book. The
  chapter you're in is sent (its first Flashcards.MAX_TEXT bytes), with the
  book's title and author; asked first, with how much will go.
- **From selected text**: **Flashcards (AI)** in the selection menu (under
  More, in ZenOS's row). The selection is sent.
The cards come back to check: **Save** keeps them, **Cancel** drops them.

A deck is a Memos note, so it's in Memos' web app to read and edit:

    #flashcards
    **Flashcards: Moby-Dick** · Chapter 16

    Q: What is a lay?
    A: A sailor's share of the voyage's profit.

(the lines are `Q:` and `A:`; Flashcards.parse reads them back). The Kindle
keeps its own copy of the decks it made, so the quiz works with Wi-Fi off.

The quiz (the same tile, **Quiz me**): a card at a time, large; tap **Show
answer**, then **Again** or **Got it**. Cards move up a box each time you
get them (seen again after 1, 3, 7, then 14 days) and back to the first
box when missed (seen again in the same quiz). Where each card is is kept
on the Kindle (gzreader_flashcards.lua in GZreader's settings).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Cards = {
    MAX_TEXT = 12000, -- bytes of a chapter sent
    MAX_SELECTION = 4000,
    COUNT = 10, -- cards asked for from a chapter
    COUNT_SELECTION = 5,
    MAX_TOKENS = 1800,
    DAYS = { 1, 3, 7, 14 }, -- a card in box n is due this many days after it was last seen
    QUIZ_MAX = 20, -- cards in one quiz
    TAG = "flashcards",
    KEY = "15_gz_flashcards",
}

---------------------------------------------------------------- the deck as text

--- `text` cut to at most `max` bytes, never inside a UTF-8 character.
local function cut(text, max)
    if #text <= max then return text end
    local n = max
    while n > 0 and text:byte(n + 1) and text:byte(n + 1) >= 0x80 and text:byte(n + 1) < 0xC0 do n = n - 1 end
    return text:sub(1, n)
end
Cards.cut = cut

--- The cards in `text`: { { q, a } } from lines "Q: …" and "A: …" (an
--- answer may run on over the next lines, until a blank line or the next Q). Pure.
function Cards.parse(text)
    local out, cur, in_answer = {}, nil, false
    for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local q = line:match("^%s*[Qq]%s*[:.]%s*(.-)%s*$")
        local a = line:match("^%s*[Aa]%s*[:.]%s*(.-)%s*$")
        if q and q ~= "" then
            cur = { q = q }
            in_answer = false
        elseif a and cur and not cur.a then
            cur.a = a
            in_answer = true
            out[#out + 1] = cur
        elseif in_answer and cur and line:match("%S") then
            cur.a = cur.a .. "\n" .. (line:gsub("^%s+", ""))
        else
            in_answer = false
            -- (a blank line after a question with no answer yet: that question had none)
            if cur and not cur.a and not line:match("%S") then cur = nil end
        end
    end
    local good = {}
    for _i, c in ipairs(out) do if c.a and c.a:match("%S") then good[#good + 1] = c end end
    return good
end

--- A deck as a Memos note's text. Pure.
function Cards.noteText(deck)
    local head = T("**%1**", T(_("Flashcards: %1"), tostring(deck.title or _("a book"))))
    if deck.part and deck.part ~= "" then head = head .. " \u{00B7} " .. deck.part end
    local out = { "#" .. Cards.TAG, head, "" }
    for _i, c in ipairs(deck.cards) do
        out[#out + 1] = "Q: " .. c.q
        out[#out + 1] = "A: " .. c.a
        out[#out + 1] = ""
    end
    return (table.concat(out, "\n"):gsub("\n+$", ""))
end

--- A card's own key (its question and answer), for where it is in the boxes. Pure.
function Cards.cardKey(c)
    local s = (c.q or "") .. "\0" .. (c.a or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

---------------------------------------------------------------- asking

Cards.SYSTEM = "You make flashcards for someone reading a book on an e-reader, to help them remember it. "
    .. "Each card is a short question and a short answer, about the text you are given and nothing else. "
    .. "Ask about what matters: people, events, ideas, terms and why things happen, not trivia like page numbers. "
    .. "Reply with only the cards, each as a line starting \"Q: \" and the next line starting \"A: \", with a blank line between cards. "
    .. "No numbering, no Markdown, no other text."

--- The question for the service: { system, text, max_tokens, what }. Pure.
function Cards.question(title, authors, part, text, count)
    local book = T("\"%1\"", tostring(title or ""))
    if type(authors) == "string" and authors:match("%S") then book = book .. " by " .. (authors:gsub("\n", ", ")) end
    local q = "The book: " .. book .. (part and part ~= "" and ("\nThe part: " .. part) or "") .. "\n\n"
        .. "The text:\n" .. text .. "\n\n"
        .. "Write " .. tostring(count or Cards.COUNT) .. " flashcards about this text, in the language of the text."
    return { system = Cards.SYSTEM, text = q, max_tokens = Cards.MAX_TOKENS, what = "flashcards", timeout = 90 }
end

--- The chapter you're in, as text: { text, part (its title), cut (true when
--- only its start is sent) }, or nil (a PDF: no chapters to take text from).
function Cards.chapter(ui)
    local ok, res = pcall(function()
        if not ui.rolling then return nil end
        local doc, toc = ui.document, ui.toc
        local page = doc:getCurrentPage()
        local total = doc:getPageCount()
        local first = toc:isChapterStart(page) and page or (toc:getPreviousChapter(page) or 1)
        local nxt = toc:getNextChapter(page) or (total + 1)
        local xp0 = doc:getPageXPointer(first)
        local xp1 = nxt <= total and doc:getPageXPointer(nxt) or nil
        -- (the contents' own places when it has them: a chapter starting halfway down a page
        -- doesn't take the end of the one before)
        local e0, e1 = Cards.tocBounds(toc, page)
        if e0 then xp0 = e0; xp1 = e1 end
        local text
        if xp1 then text = doc:getTextFromXPointers(xp0, xp1)
        else
            -- (the last chapter: to the end of the book)
            local last = doc:getPageXPointer(total)
            text = doc:getTextFromXPointers(xp0, last)
        end
        if type(text) ~= "string" or not text:match("%S") then return nil end
        text = text:gsub("[ \t]+", " "):gsub("\n%s*\n+", "\n\n")
        local title = toc:getTocTitleByPage(page)
        local was = #text
        text = cut(text, Cards.MAX_TEXT)
        return { text = text, part = (type(title) == "string" and title ~= "") and title or nil, cut = #text < was, pages = nxt - first }
    end)
    if ok then return res end
    Log.warn("flashcards: the chapter's text couldn't be read:", tostring(res))
    return nil
end

--- The contents' entry the page is in, and the next one at its level or
--- above: their places (xpointers), or nil (no contents with places).
function Cards.tocBounds(toc, page)
    local ok, a, b = pcall(function()
        if toc.fillToc then toc:fillToc() end
        local list = toc.toc
        if type(list) ~= "table" or #list == 0 then return nil end
        local at
        for i, e in ipairs(list) do
            if type(e.page) == "number" and e.page <= page and type(e.xpointer) == "string" then at = i end
        end
        if not at then return nil end
        local depth = list[at].depth or 1
        for j = at + 1, #list do
            local e = list[j]
            if (e.depth or 1) <= depth and type(e.xpointer) == "string" then return list[at].xpointer, e.xpointer end
        end
        return list[at].xpointer, nil
    end)
    if ok then return a, b end
    return nil
end

---------------------------------------------------------------- kept on the Kindle

function Cards.statePath()
    return require("datastorage"):getSettingsDir() .. "/gzreader_flashcards.lua"
end

function Cards.state()
    if Cards._state then return Cards._state end
    local LuaSettings = require("luasettings")
    local s = LuaSettings:open(Cards.statePath())
    Cards._settings = s
    Cards._state = { decks = s:readSetting("decks") or {}, boxes = s:readSetting("boxes") or {} }
    return Cards._state
end

function Cards.saveState()
    local st = Cards.state()
    if Cards._settings then
        Cards._settings:saveSetting("decks", st.decks)
        Cards._settings:saveSetting("boxes", st.boxes)
        Cards._settings:flush()
    end
end

--- Keep a deck: { title, part, book (its file), cards }.
function Cards.addDeck(deck)
    local st = Cards.state()
    deck.made = deck.made or os.time()
    table.insert(st.decks, deck)
    Cards.saveState()
end

--- Every card of the decks (of book `file` only, when given): { q, a, key, deck }.
function Cards.allCards(file)
    local out = {}
    for _i, d in ipairs(Cards.state().decks) do
        if not file or d.book == file then
            for _j, c in ipairs(d.cards or {}) do out[#out + 1] = { q = c.q, a = c.a, key = Cards.cardKey(c), deck = d } end
        end
    end
    return out
end

--- Is a card due at `now`? (Never seen: yes.) Pure, given `boxes`.
function Cards.due(boxes, key, now)
    local b = boxes[key]
    if type(b) ~= "table" then return true end
    local days = Cards.DAYS[b.box or 1] or Cards.DAYS[#Cards.DAYS]
    return now - (b.seen or 0) >= days * 86400 - 3600 -- (an hour's slack: a quiz at the same time of day)
end

--- The cards to quiz now: the due ones, lowest box first, at most QUIZ_MAX. Pure, given `boxes`.
function Cards.dueCards(cards, boxes, now)
    local out = {}
    for _i, c in ipairs(cards) do if Cards.due(boxes, c.key, now) then out[#out + 1] = c end end
    table.sort(out, function(x, y)
        local bx, by = (boxes[x.key] or {}).box or 0, (boxes[y.key] or {}).box or 0
        if bx ~= by then return bx < by end
        return x.key < y.key
    end)
    while #out > Cards.QUIZ_MAX do table.remove(out) end
    return out
end

--- A card answered: up a box (Got it) or back to the first (Again). Pure, on `boxes`.
function Cards.answer(boxes, key, got, now)
    local b = type(boxes[key]) == "table" and boxes[key] or { box = 0 }
    b.box = got and math.min(#Cards.DAYS, (b.box or 0) + 1) or 1
    b.seen = now
    boxes[key] = b
    return b.box
end

---------------------------------------------------------------- making cards

--- Ask for cards from `text`; show them to check; Save keeps them on the
--- Kindle and as a note in Memos.
function Cards.make(plugin, ui, text, part, count)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local AI = require("gzreader_ai")
    local props = ui.doc_props or {}
    local title = props.display_title or props.title
    local name = AI.name(AI.provider(plugin))
    local waiting = InfoMessage:new{ text = T(_("Asking %1 for flashcards…"), name) }
    UIManager:show(waiting)
    AI.ask(plugin, Cards.question(title, props.authors, part, text, count), function(answer, why)
        UIManager:close(waiting)
        local cards = answer and Cards.parse(answer) or {}
        if #cards == 0 then
            UIManager:show(InfoMessage:new{ text = answer and T(_("%1 didn't send any cards."), name)
                or T(_("%1 didn't answer: %2"), name, tostring(why or _("no answer"))) })
            return
        end
        Log.info("flashcards:", #cards, "cards made")
        local deck = { title = title, part = part, book = ui.document and ui.document.file, cards = cards }
        Cards.preview(plugin, deck)
    end)
end

--- The cards made, to check: Save or Cancel.
function Cards.preview(plugin, deck)
    local UIManager = require("ui/uimanager")
    local lines = {}
    for i, c in ipairs(deck.cards) do lines[#lines + 1] = T("%1. %2\n%3", i, c.q, c.a) end
    local viewer
    viewer = require("ui/widget/textviewer"):new{
        title = T(_("%1 flashcards"), #deck.cards),
        text = table.concat(lines, "\n\n") .. "\n\n" .. _("An AI wrote these. They can be wrong."),
        buttons_table = { {
            { text = _("Cancel"), callback = function() UIManager:close(viewer) end },
            { text = _("Save"), callback = function()
                UIManager:close(viewer)
                Cards.save(plugin, deck)
            end },
        } },
        add_default_buttons = false,
    }
    UIManager:show(viewer)
    return viewer
end

--- Keep a deck on the Kindle, and as a note in Memos when it's connected.
--- Returns "memos" or "kindle".
function Cards.save(plugin, deck)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    Cards.addDeck(deck)
    local memos = false
    local store = plugin.store and plugin.store.memos
    if type(store) == "table" and require("gzreader_memos"):new(store):isConnected() then
        local ok = pcall(function() require("gzreader_notes").addNote(plugin, Cards.noteText(deck), "PRIVATE") end)
        memos = ok
    end
    Log.info("flashcards: a deck of", #deck.cards, "kept", memos and "(and sent to Memos)" or "(on the Kindle only)")
    UIManager:show(InfoMessage:new{ timeout = 3,
        text = memos and T(_("%1 cards saved, and as a note in Memos (tagged #flashcards)."), #deck.cards)
            or T(_("%1 cards saved on this Kindle. (Connect Memos to keep them as notes too.)"), #deck.cards) })
    return memos and "memos" or "kindle"
end

--- Cards from the chapter you're in: asked first, with how much goes.
function Cards.fromChapter(plugin, ui)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local ch = Cards.chapter(ui)
    if not ch then
        UIManager:show(InfoMessage:new{ text = _("This book's chapters can't be read as text here (a PDF or a comic). Select some text and use Flashcards (AI) in the selection menu instead."), timeout = 5 })
        return false
    end
    local AI = require("gzreader_ai")
    local words = select(2, ch.text:gsub("%S+", ""))
    UIManager:show(require("ui/widget/confirmbox"):new{
        text = T(_("Make %1 flashcards from %2?\n\nSent to %3: about %4 words of it%5, and the book's title and author."),
            Cards.COUNT, ch.part and ("“" .. ch.part .. "”") or _("this chapter"), AI.name(AI.provider(plugin)), words,
            ch.cut and _(" (its start: the chapter is longer)") or ""),
        ok_text = _("Make cards"),
        ok_callback = function() Cards.make(plugin, ui, ch.text, ch.part, Cards.COUNT) end,
    })
    return true
end

--- Cards from selected text (the selection menu).
function Cards.fromSelection(plugin, highlight, index)
    local text
    if type(highlight.selected_text) == "table" then text = highlight.selected_text.text end
    if not text and index then pcall(function() text = highlight.ui.annotation.annotations[index].text end) end
    if type(text) ~= "string" or not text:match("%S") then return false end
    local ui = highlight.ui
    pcall(function() highlight:onClose() end)
    local part
    pcall(function() part = ui.toc:getTocTitleByPage(ui.document:getCurrentPage()) end)
    Cards.make(plugin, ui, cut(text, Cards.MAX_SELECTION), part, Cards.COUNT_SELECTION)
    return true
end

---------------------------------------------------------------- the quiz

--- Quiz `cards` one at a time (a list from dueCards).
function Cards.quiz(cards)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Font = require("ui/font")
    local st = Cards.state()
    local queue = {}
    for _i, c in ipairs(cards) do queue[#queue + 1] = c end
    local total, right, seen = #queue, 0, 0
    local face = Font:getFace("cfont", 26)
    local function finish()
        Cards.saveState()
        Log.info("flashcards: a quiz of", total, "cards,", right, "right first time")
        UIManager:show(InfoMessage:new{ text = T(_("Done: %1 of %2 right the first time."), right, total), timeout = 4 })
    end
    local missed = {}
    local function nextCard()
        local c = table.remove(queue, 1)
        if not c then return finish() end
        seen = seen + 1
        local front
        front = require("ui/widget/textviewer"):new{
            title = T(_("Card %1 of %2"), math.min(seen, total), total),
            text = c.q, text_face = face, justified = false,
            buttons_table = { {
                { text = _("Stop"), callback = function() UIManager:close(front); Cards.saveState() end },
                { text = _("Show answer"), callback = function()
                    UIManager:close(front)
                    local back
                    back = require("ui/widget/textviewer"):new{
                        title = T(_("Card %1 of %2"), math.min(seen, total), total),
                        text = c.q .. "\n\n\u{2014}\n\n" .. c.a, text_face = face, justified = false,
                        buttons_table = { {
                            { text = _("Again"), callback = function()
                                UIManager:close(back)
                                Cards.answer(st.boxes, c.key, false, os.time())
                                missed[c.key] = true
                                queue[#queue + 1] = c -- (seen again before the quiz ends)
                                nextCard()
                            end },
                            { text = _("Got it"), callback = function()
                                UIManager:close(back)
                                if not missed[c.key] then right = right + 1 end
                                Cards.answer(st.boxes, c.key, true, os.time())
                                nextCard()
                            end },
                        } },
                        add_default_buttons = false,
                    }
                    UIManager:show(back)
                end },
            } },
            add_default_buttons = false,
        }
        UIManager:show(front)
    end
    if #queue == 0 then
        UIManager:show(InfoMessage:new{ text = _("No cards are due. Come back tomorrow, or make some from a chapter."), timeout = 4 })
        return false
    end
    nextCard()
    return true
end

---------------------------------------------------------------- where it's offered

function Cards.available(plugin)
    local ok, AI = pcall(require, "gzreader_ai")
    return ok and AI.ready(plugin) == true
end

--- The quick panel's Flashcards in a book: make cards, quiz this book's, quiz all.
function Cards.menu(plugin, ui)
    local UIManager = require("ui/uimanager")
    local now = os.time()
    local st = Cards.state()
    local file = ui.document and ui.document.file
    local here = Cards.dueCards(Cards.allCards(file), st.boxes, now)
    local all = Cards.dueCards(Cards.allCards(nil), st.boxes, now)
    local dialog
    local rows = {}
    if Cards.available(plugin) then
        rows[#rows + 1] = { { text = _("Make cards from this chapter"), align = "left", callback = function()
            UIManager:close(dialog); Cards.fromChapter(plugin, ui)
        end } }
    end
    rows[#rows + 1] = { { text = T(_("Quiz me on this book (%1 due)"), #here), align = "left", enabled = #here > 0, callback = function()
        UIManager:close(dialog); Cards.quiz(here)
    end } }
    rows[#rows + 1] = { { text = T(_("Quiz me on all my cards (%1 due)"), #all), align = "left", enabled = #all > 0, callback = function()
        UIManager:close(dialog); Cards.quiz(all)
    end } }
    dialog = require("ui/widget/buttondialog"):new{ title = _("Flashcards"), title_align = "center", buttons = rows }
    UIManager:show(dialog)
    return dialog
end

--- The quick panel's tile in a book: with an AI key, or with cards to quiz.
function Cards.tile(plugin, ui)
    if type(ui) ~= "table" or not ui.document then return nil end
    if not Cards.available(plugin) and #Cards.allCards(nil) == 0 then return nil end
    return { id = "flashcards", icon = "flashcards", label = _("Flashcards"), run = function() Cards.menu(plugin, ui) end }
end

--- Flashcards (AI) in the selection menu (under More in ZenOS's row).
function Cards.register(plugin, ui)
    local highlight = type(ui) == "table" and ui.highlight
    if type(highlight) ~= "table" or type(highlight.addToHighlightDialog) ~= "function" then return false end
    highlight:addToHighlightDialog(Cards.KEY, function(this, index)
        return {
            text = _("Flashcards (AI)"),
            show_in_highlight_dialog_func = function() return Cards.available(plugin) end,
            callback = function() Cards.fromSelection(plugin, this, index) end,
        }
    end)
    return true
end

return Cards
