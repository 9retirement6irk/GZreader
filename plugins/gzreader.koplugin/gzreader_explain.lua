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
}

--- `text` cut to at most `max` bytes, never inside a UTF-8 character.
function Explain.cut(text, max)
    max = max or Explain.MAX
    if #text <= max then return text end
    local n = max
    while n > 0 and text:byte(n + 1) and text:byte(n + 1) >= 0x80 and text:byte(n + 1) < 0xC0 do n = n - 1 end
    return text:sub(1, n)
end

--- The question for the AI service: { system, text, max_tokens, what }.
--- `title`, `authors`: the book's, when known. Pure.
function Explain.question(selected, title, authors)
    selected = Explain.cut((tostring(selected or ""):gsub("^%s+", ""):gsub("%s+$", "")))
    local from = ""
    if type(title) == "string" and title:match("%S") then
        from = (type(authors) == "string" and authors:match("%S")) and T("\"%1\" by %2", title, (authors:gsub("\n", ", "))) or T("\"%1\"", title)
    end
    local system = "You help someone who is reading a book on an e-reader. They selected some text and asked what it means. "
        .. "Explain it to them plainly. If it is a single word, a name or a short phrase, say what it means or who or what it is, as it is meant in this passage. "
        .. "If it is a sentence or a longer passage, say what it is saying and give any background needed to understand it. "
        .. "Do not reveal anything that happens later in the book. Keep it under 150 words, in plain text with no Markdown, no headings and no lists. "
        .. "Answer in the language of the selected text."
    local text = (from ~= "" and ("The book: " .. from .. "\n\n") or "") .. "The selected text:\n" .. selected
    return { system = system, text = text, max_tokens = Explain.MAX_TOKENS, what = "explain" }
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

--- Ask for the selection to be explained, and show the answer.
function Explain.run(plugin, highlight, index)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local AI = require("gzreader_ai")
    local selected = Explain.selection(highlight, index)
    if not selected or not selected:match("%S") then return false end
    local props = type(highlight.ui) == "table" and type(highlight.ui.doc_props) == "table" and highlight.ui.doc_props or {}
    local q = Explain.question(selected, props.display_title or props.title, props.authors)
    pcall(function() highlight:onClose() end) -- (the menu and the selection's marks go; the answer comes over the page)
    local name = AI.name(AI.provider(plugin))
    local waiting = InfoMessage:new{ text = T(_("Asking %1 to explain…"), name) }
    UIManager:show(waiting)
    AI.ask(plugin, q, function(answer, why)
        UIManager:close(waiting)
        if not answer or not answer:match("%S") then
            UIManager:show(InfoMessage:new{ text = T(_("%1 couldn't explain it: %2"), name, tostring(why or _("no answer"))) })
            return
        end
        local shown = Explain.cut(selected, 200)
        UIManager:show(require("ui/widget/textviewer"):new{
            title = T(_("Explained by %1"), name),
            text = "“" .. shown .. (#shown < #selected and "…" or "") .. "”\n\n" .. answer
                .. "\n\n" .. _("An AI wrote this. It can be wrong."),
        })
    end)
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
    return true
end

return Explain
