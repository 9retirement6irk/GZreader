--[[--
Explain: in a book, the menu that comes up when text is selected has a
question mark. It sends the selected text to the AI service set up in
Settings → Accounts and services → AI (gzreader_ai.lua) and asks for it to
be explained to the reader; the answer shows in a window over the book.

- The button is there only when an AI key is set up.
- Sent: the selected text (its first Explain.MAX bytes) and the book's
  title and author, so that a name or a phrase is explained as it's meant
  in this book. Nothing else of the book, nothing about the reader.
- Nothing asked or answered is kept or logged (the log says that something
  was asked, how big, and how long the answer took: AI.ask).

The answer's window has Ask…, Simpler, Summarize and Translate… under it:
each asks about the same selection again, with the conversation so far sent
along, and the window then shows the new answer first. With a key set up the
selection menu's Translate opens a list of languages and the translation
comes from the AI service (Google Translate, as before, is the list's last
row). The conversation is gone when its window closes.

The button is registered with KOReader's own selection menu
(ReaderHighlight:addToHighlightDialog, key "gz_explain"); ZenOS's icon row
(modules/reader/patches/highlight_menu.lua) shows it as the question mark.
]]

local _ = require("gettext")
local T = require("ffi/util").template

local Explain = {
    KEY = "12_gz_explain",
    MAX = 3000,       -- bytes of the selection sent
    MAX_TOKENS = 500, -- (an answer of about 150 words, with room)
    MAX_LONG_TOKENS = 1500, -- (a translation or a simpler version of a long selection)
    KEEP = 4,         -- exchanges sent back with a follow-up, beside the first
    TRANSLATE_KEY = "13_gz_translate",
    -- languages offered for a translation (their names in English: sent as they are)
    LANGUAGES = { "English", "Spanish", "French", "German", "Italian", "Portuguese", "Dutch", "Polish", "Turkish", "Russian",
        "Arabic", "Hindi", "Chinese", "Japanese", "Korean" },
}

--- `text` cut to at most `max` bytes, never inside a UTF-8 character.
function Explain.cut(text, max)
    max = max or Explain.MAX
    if #text <= max then return text end
    local n = max
    while n > 0 and text:byte(n + 1) and text:byte(n + 1) >= 0x80 and text:byte(n + 1) < 0xC0 do n = n - 1 end
    return text:sub(1, n)
end

--[[ What the service is told for every question here: who it's helping,
how to write for an e-reader's text window, and never to give away what
comes later in the book. What to do with the selection goes with each
question (Explain.INSTRUCTIONS), so one conversation can explain, then put
it more simply, then translate. ]]
Explain.SYSTEM = "You help someone who is reading a book on an e-reader. They selected some text in it and ask you about it. "
    .. "Do not reveal anything that happens later in the book. "
    .. "Write plain text with no Markdown, no headings and no lists. Be brief: the answer is read on a small screen."

--- What each action asks for (the words sent). `translate` takes the language's name.
Explain.INSTRUCTIONS = {
    explain = "Explain it to me plainly. If it is a single word, a name or a short phrase, say what it means or who or what it is, as it is meant in this passage. "
        .. "If it is a sentence or a longer passage, say what it is saying and give any background needed to understand it. "
        .. "Keep it under 150 words. Answer in the language of the selected text.",
    simplify = "Say the selected text again in simpler words, keeping everything it says, in the language of the selected text. Give only the simpler version.",
    summarize = "Summarize the selected text in a few sentences, in the language of the selected text.",
    translate = "Translate the selected text into %s. Give only the translation.",
}

--- What an action is called on its button and over its answer.
function Explain.label(action, arg)
    if action == "explain" then return _("Explain") end
    if action == "simplify" then return _("Simpler") end
    if action == "summarize" then return _("Summarize") end
    if action == "translate" then return T(_("Into %1"), tostring(arg or "")) end
    return (tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")) -- (a question typed: itself)
end

--- The words sent for `action` ("explain", "simplify", "summarize",
--- "translate" with `arg` the language, "ask" with `arg` the question typed).
function Explain.instruction(action, arg)
    if action == "translate" then return string.format(Explain.INSTRUCTIONS.translate, tostring(arg or "English")) end
    if action == "ask" then return (tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
    return Explain.INSTRUCTIONS[action] or Explain.INSTRUCTIONS.explain
end

--- How long an answer may be: a translation or a simpler version is as long
--- as the selection, the rest about 150 words.
function Explain.maxTokens(action, selected)
    if action == "translate" or action == "simplify" then
        return math.max(Explain.MAX_TOKENS, math.min(Explain.MAX_LONG_TOKENS, math.floor(#tostring(selected or "") / 2)))
    end
    return Explain.MAX_TOKENS
end

--- The first question of a conversation: { system, text, max_tokens, what }.
--- `title`, `authors`: the book's, when known. Pure.
function Explain.question(selected, title, authors, action, arg)
    action = action or "explain"
    selected = Explain.cut((tostring(selected or ""):gsub("^%s+", ""):gsub("%s+$", "")))
    local from = ""
    if type(title) == "string" and title:match("%S") then
        from = (type(authors) == "string" and authors:match("%S")) and T("\"%1\" by %2", title, (authors:gsub("\n", ", "))) or T("\"%1\"", title)
    end
    local text = (from ~= "" and ("The book: " .. from .. "\n\n") or "") .. "The selected text:\n" .. selected
        .. "\n\n" .. Explain.instruction(action, arg)
    return { system = Explain.SYSTEM, text = text, max_tokens = Explain.maxTokens(action, selected), what = action == "explain" and "explain" or ("explain " .. action) }
end

--[[ A conversation about one selection, kept only while its window is open:
{ selected, first = the first question's text, turns = { { action, arg,
label, sent = the words sent (nil for the first), answer } } }. ]]
function Explain.newChat(selected, title, authors)
    return { selected = selected, title = title, authors = authors, turns = {} }
end

--- The question to send for the conversation's next turn (`action`, `arg`):
--- the turns so far go along as `history` ({ role, text } each), so "put
--- that more simply" means the answer just given. Pure.
function Explain.next(chat, action, arg)
    local q = Explain.question(chat.selected, chat.title, chat.authors, action, arg)
    if #chat.turns == 0 then return q end
    local first = chat.turns[1]
    local history = { { role = "user", text = Explain.question(chat.selected, chat.title, chat.authors, first.action, first.arg).text },
        { role = "assistant", text = first.answer } }
    for k = 2, #chat.turns do
        history[#history + 1] = { role = "user", text = chat.turns[k].sent }
        history[#history + 1] = { role = "assistant", text = chat.turns[k].answer }
    end
    -- (only the newest Explain.KEEP exchanges, and always the first: the selection is in it)
    while #history > 2 + 2 * Explain.KEEP do table.remove(history, 3); table.remove(history, 3) end
    local sent = Explain.instruction(action, arg)
    return { system = Explain.SYSTEM, history = history, text = sent, max_tokens = Explain.maxTokens(action, chat.selected), what = "explain follow-up" }, sent
end

--- The conversation as the window shows it: the selection, the newest
--- answer under what was asked, then the earlier ones. Pure.
function Explain.render(chat)
    local shown = Explain.cut(chat.selected, 200)
    local out = { "\u{201C}" .. shown .. (#shown < #chat.selected and "\u{2026}" or "") .. "\u{201D}" }
    for k = #chat.turns, 1, -1 do
        local t = chat.turns[k]
        if k == #chat.turns - 1 then out[#out + 1] = "\u{2014} " .. _("Earlier") .. " \u{2014}" end
        out[#out + 1] = "\u{25B8} " .. t.label .. "\n" .. t.answer
    end
    out[#out + 1] = _("An AI wrote this. It can be wrong.")
    return table.concat(out, "\n\n")
end

--- The button shows when an AI key is set up.
function Explain.available(plugin)
    local ok, AI = pcall(require, "gzreader_ai")
    return ok and AI.ready(plugin) == true
end

--- The text to explain: the new selection's, or an existing highlight's (`index`).
function Explain.selection(highlight, index)
    if type(highlight.selected_text) == "table" and type(highlight.selected_text.text) == "string" then
        return highlight.selected_text.text
    end
    local ok, text = pcall(function() return highlight.ui.annotation.annotations[index].text end)
    return ok and type(text) == "string" and text or nil
end

--- Ask the conversation's next question and show it with the answer.
function Explain.ask(plugin, chat, action, arg)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local AI = require("gzreader_ai")
    local q, sent = Explain.next(chat, action, arg)
    local name = AI.name(AI.provider(plugin))
    local waiting = InfoMessage:new{ text = action == "explain" and T(_("Asking %1 to explain…"), name) or T(_("Asking %1…"), name) }
    UIManager:show(waiting)
    AI.ask(plugin, q, function(answer, why)
        UIManager:close(waiting)
        if not answer or not answer:match("%S") then
            UIManager:show(InfoMessage:new{ text = action == "explain" and #chat.turns == 0
                and T(_("%1 couldn't explain it: %2"), name, tostring(why or _("no answer")))
                or T(_("%1 didn't answer: %2"), name, tostring(why or _("no answer"))) })
            if #chat.turns > 0 then Explain.show(plugin, chat) end -- (the conversation so far is still there)
            return
        end
        chat.turns[#chat.turns + 1] = { action = action, arg = arg, label = Explain.label(action, arg), sent = sent, answer = answer }
        Explain.show(plugin, chat)
    end)
    return true
end

--- The conversation's window: what was asked and answered, and under it
--- Ask…, Simpler, Summarize, Translate… for the next question.
function Explain.show(plugin, chat)
    local UIManager = require("ui/uimanager")
    local AI = require("gzreader_ai")
    local viewer
    local function again(action, arg)
        UIManager:close(viewer)
        Explain.ask(plugin, chat, action, arg)
    end
    local rows = { {
        { text = _("Ask…"), callback = function()
            Explain.typeQuestion(function(typed) again("ask", typed) end)
        end },
        { text = _("Simpler"), callback = function() again("simplify") end },
        { text = _("Summarize"), callback = function() again("summarize") end },
        { text = _("Translate…"), callback = function()
            Explain.languageMenu(plugin, function(lang) again("translate", lang) end)
        end },
    } }
    for _i, row in ipairs(Explain.extraRows(plugin, chat, function() return viewer end)) do rows[#rows + 1] = row end
    rows[#rows + 1] = { { text = _("Close"), callback = function() UIManager:close(viewer) end } }
    local first = chat.turns[1]
    viewer = require("ui/widget/textviewer"):new{
        title = (first and first.action == "explain" and #chat.turns == 1) and T(_("Explained by %1"), AI.name(AI.provider(plugin)))
            or T(_("Answered by %1"), AI.name(AI.provider(plugin))),
        text = Explain.render(chat),
        buttons_table = rows,
        add_default_buttons = false,
    }
    UIManager:show(viewer)
    return viewer
end

--- More rows of buttons for the conversation's window (none here; a place
--- for what's done with an answer). get_viewer(): the window, to close it.
function Explain.extraRows(_plugin, _chat, _get_viewer)
    return {}
end

--- A box to type a question in; on_done(text) when there's one.
function Explain.typeQuestion(on_done)
    local UIManager = require("ui/uimanager")
    local InputDialog = require("ui/widget/inputdialog")
    local box
    box = InputDialog:new{
        title = _("Ask about the selected text"),
        input_hint = _("Your question"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(box) end },
            { text = _("Ask"), is_enter_default = true, callback = function()
                local typed = box:getInputText()
                if type(typed) ~= "string" or not typed:match("%S") then return end
                UIManager:close(box)
                on_done(typed)
            end },
        } },
    }
    UIManager:show(box)
    if box.onShowKeyboard then box:onShowKeyboard() end
    return box
end

--- The language translations go into unless another is picked: the one
--- picked last, else GZreader's own language, else English.
function Explain.language()
    local saved = G_reader_settings:readSetting("gzreader_ai_translate_to")
    if type(saved) == "string" and saved ~= "" then return saved end
    local code = tostring(G_reader_settings:readSetting("language") or ""):lower():sub(1, 2)
    return Explain.BY_CODE[code] or "English"
end
Explain.BY_CODE = { en = "English", es = "Spanish", fr = "French", de = "German", it = "Italian", pt = "Portuguese", nl = "Dutch", pl = "Polish",
    tr = "Turkish", ru = "Russian", ar = "Arabic", hi = "Hindi", zh = "Chinese", ja = "Japanese", ko = "Korean" }

--- The languages in the order offered: the usual one first.
function Explain.languages()
    local usual = Explain.language()
    local out = { usual }
    for _i, l in ipairs(Explain.LANGUAGES) do if l ~= usual then out[#out + 1] = l end end
    return out
end

--- The menu of languages: on_pick(language). The one picked is the usual
--- one from then on. `other`: { text, callback } for one more row under them
--- (the reader's own translator, from the selection menu).
function Explain.languageMenu(_plugin, on_pick, other)
    local UIManager = require("ui/uimanager")
    local dialog
    local rows, row = {}, {}
    for i, lang in ipairs(Explain.languages()) do
        local label = i == 1 and T(_("Into %1"), lang) or lang
        local one = { text = label, callback = function()
            UIManager:close(dialog)
            G_reader_settings:saveSetting("gzreader_ai_translate_to", lang)
            on_pick(lang)
        end }
        if i == 1 then rows[#rows + 1] = { one }
        else
            row[#row + 1] = one
            if #row == 2 then rows[#rows + 1] = row; row = {} end
        end
    end
    if #row > 0 then rows[#rows + 1] = row end
    if other then
        rows[#rows + 1] = { { text = other.text, callback = function() UIManager:close(dialog); other.callback() end } }
    end
    dialog = require("ui/widget/buttondialog"):new{ title = _("Translate with AI"), title_align = "center", buttons = rows }
    UIManager:show(dialog)
    return dialog
end

--- Start a conversation about the selection with `action` (and `arg`).
function Explain.run(plugin, highlight, index, action, arg)
    local selected = Explain.selection(highlight, index)
    if not selected or not selected:match("%S") then return false end
    local props = type(highlight.ui) == "table" and type(highlight.ui.doc_props) == "table" and highlight.ui.doc_props or {}
    local chat = Explain.newChat(selected, props.display_title or props.title, props.authors)
    Explain.began(chat, highlight, index)
    pcall(function() highlight:onClose() end) -- (the menu and the selection's marks go; the answer comes over the page)
    return Explain.ask(plugin, chat, action or "explain", arg)
end

--- A conversation begins on `highlight`'s selection (or its highlight
--- `index`), before the menu closes: nothing to keep here.
function Explain.began(_chat, _highlight, _index) end

--- The selection menu's Translate, with an AI key set up: the languages,
--- and the reader's own translator (Google Translate) under them.
function Explain.translate(plugin, highlight, index)
    local selected = Explain.selection(highlight, index)
    if not selected or not selected:match("%S") then return false end
    Explain.languageMenu(plugin, function(lang) Explain.run(plugin, highlight, index, "translate", lang) end,
        { text = _("Without AI (Google Translate)"), callback = function() highlight:translate(index) end })
    return true
end

--- Add the button to this book's selection menu (once per reader).
function Explain.register(plugin, ui)
    local highlight = type(ui) == "table" and ui.highlight
    if type(highlight) ~= "table" or type(highlight.addToHighlightDialog) ~= "function" then return false end
    highlight:addToHighlightDialog(Explain.KEY, function(this, index)
        return {
            text = _("Explain (AI)"),
            show_in_highlight_dialog_func = function() return Explain.available(plugin) end,
            callback = function() Explain.run(plugin, this, index) end,
        }
    end)
    highlight:addToHighlightDialog(Explain.TRANSLATE_KEY, function(this, index)
        return {
            text = _("Translate (AI)"),
            show_in_highlight_dialog_func = function() return Explain.available(plugin) end,
            callback = function() Explain.translate(plugin, this, index) end,
        }
    end)
    return true
end

return Explain
