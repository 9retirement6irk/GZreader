--[[--
The story so far: in a book, the quick panel's **Story so far** asks the AI
service (gzreader_ai.lua) who's who and what has happened up to where you
are, from what the service knows of the book, and shows it in a window.

- Sent: the book's title and author, how far through it you are (a
  percentage) and the chapter's title. Nothing of the book's text.
- Told not to give away anything after that point, and to say so when it
  doesn't know the book (a self-published or very new one).
- The answer is kept with the book (its settings, beside the book) for the
  chapter it was asked in, so opening it again in the same chapter shows it
  at once; **Ask again** asks for where you are now.
- Only with an AI key set up (the tile isn't there otherwise).

BookOrbit builds a story guide of its own on the server (its "story
guides"), but serves it only to its signed iPhone app: in production the
route wants Apple's App Attest and refuses API keys, so GZreader can't read
it (checked in BookOrbit's source, 2026-11-26).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Story = {
    MAX_TOKENS = 900,
    SETTING = "gzreader_story_so_far",
    SYSTEM = "You help someone reading a book on an e-reader catch up on it. Use what you know of the book. "
        .. "Never mention or hint at anything that happens after the point they have reached. "
        .. "Write plain text with no Markdown: no asterisks, no headings marked with #, no bullet characters.",
}

--- Where the reader is: { pct (0-100, whole), chapter (title or nil), page }.
function Story.position(ui)
    local pos = {}
    pcall(function()
        local page
        if ui.paging then page = ui.paging.current_page else page = ui.document:getCurrentPage() end
        local total = ui.document:getPageCount()
        pos.page = tonumber(page)
        if page and total and total > 0 then pos.pct = math.floor(page * 100 / total + 0.5) end
        local title = ui.toc and ui.toc:getTocTitleByPage(page)
        if type(title) == "string" and title:match("%S") then pos.chapter = title end
    end)
    return pos
end

--- The question: { system, text, max_tokens, what }. Pure.
function Story.question(title, authors, pos)
    pos = pos or {}
    local book = T("\"%1\"", tostring(title or ""))
    if type(authors) == "string" and authors:match("%S") then book = book .. " by " .. (authors:gsub("\n", ", ")) end
    local where = pos.pct and (tostring(pos.pct) .. "% of the way through") or "partway through"
    if pos.chapter then where = where .. ", in the part titled \"" .. pos.chapter .. "\"" end
    local text = "I am reading " .. book .. " and I am " .. where .. ".\n\n"
        .. "Help me catch up, without spoilers. Write two parts.\n"
        .. "First a line \"Who's who\", then the main people (and any important places or things) I have met so far, one per line, "
        .. "each as the name, a dash, and who or what they are so far in a few words.\n"
        .. "Then a line \"So far\", then what has happened up to this point in one or two short paragraphs.\n"
        .. "Stay before this point. If you don't know this book well enough, say so in one sentence and stop."
    return { system = Story.SYSTEM, text = text, max_tokens = Story.MAX_TOKENS, what = "story so far" }
end

--- The kept answer for this book when it was asked in the same chapter (or,
--- with no chapters, within 2% of here), else nil. Pure.
function Story.kept(saved, pos)
    if type(saved) ~= "table" or type(saved.text) ~= "string" or saved.text == "" then return nil end
    pos = pos or {}
    if pos.chapter and saved.chapter then return saved.chapter == pos.chapter and saved or nil end
    if pos.pct and saved.pct then return math.abs(pos.pct - saved.pct) <= 2 and saved or nil end
    return nil
end

--- The window's text: where it's up to, the answer, and who wrote it. Pure.
function Story.render(saved)
    local where = {}
    if saved.pct then where[#where + 1] = T(_("Up to %1%"), saved.pct) end
    if saved.chapter then where[#where + 1] = saved.chapter end
    local head = #where > 0 and (table.concat(where, " \u{00B7} ") .. "\n\n") or ""
    return head .. saved.text .. "\n\n" .. T(_("Written by %1 from what it knows of the book. It can be wrong."), tostring(saved.by or "AI"))
end

--- Can the tile be shown? (An AI key set up, a book open.)
function Story.available(plugin, ui)
    if type(ui) ~= "table" or not ui.document then return false end
    local ok, AI = pcall(require, "gzreader_ai")
    return ok and AI.ready(plugin) == true
end

--- Show the story so far: kept, or asked now (`fresh`: always asked).
function Story.show(plugin, ui, fresh)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local AI = require("gzreader_ai")
    local pos = Story.position(ui)
    local ds = ui.doc_settings
    local kept = not fresh and ds and Story.kept(ds:readSetting(Story.SETTING), pos)
    local function window(saved)
        local viewer
        viewer = require("ui/widget/textviewer"):new{
            title = _("The story so far"),
            text = Story.render(saved),
            buttons_table = { {
                { text = _("Ask again"), callback = function() UIManager:close(viewer); Story.show(plugin, ui, true) end },
                { text = _("Close"), callback = function() UIManager:close(viewer) end },
            } },
            add_default_buttons = false,
        }
        UIManager:show(viewer)
        return viewer
    end
    if kept then return window(kept) end
    local props = ui.doc_props or {}
    local name = AI.name(AI.provider(plugin))
    local waiting = InfoMessage:new{ text = T(_("Asking %1…"), name) }
    UIManager:show(waiting)
    AI.ask(plugin, Story.question(props.display_title or props.title, props.authors, pos), function(text, why)
        UIManager:close(waiting)
        if not text or not text:match("%S") then
            UIManager:show(InfoMessage:new{ text = T(_("%1 didn't answer: %2"), name, tostring(why or _("no answer"))) })
            return
        end
        local saved = { text = text, pct = pos.pct, chapter = pos.chapter, by = name, at = os.time() }
        if ds then ds:saveSetting(Story.SETTING, saved) end
        Log.info("story so far: answered at", tostring(pos.pct) .. "%")
        window(saved)
    end)
    return true
end

--- The quick panel's tile in a book (nil without an AI key).
function Story.tile(plugin, ui)
    if not Story.available(plugin, ui) then return nil end
    return { id = "storysofar", icon = "storysofar", label = _("Story so far"), run = function() Story.show(plugin, ui) end }
end

return Story
