--[[--
Story guide: in a book, the quick panel's **Story guide** shows who's who,
the places, the terms and what has happened, up to where you are, as
BookOrbit's story guide and an X-Ray do, built from the book's own text by
the AI service you set up (gzreader_ai.lua).

- BookOrbit builds a guide of its own on the server, but serves it only to
  its signed iPhone app: on a production server the route wants Apple's App
  Attest and refuses API keys (`RequireAppAttest`, `API_KEY_ROUTE_FORBIDDEN`,
  checked in BookOrbit's source, 2026-11-26). So GZreader makes its own.
- The book is read a part at a time (its contents' top-level chapters, up
  to where you are; the part you're in, up to your page). Each finished
  part is asked about once and kept with the book (its settings beside it);
  later only the new parts go. Before the first, it asks: the text you've
  read goes to the AI service.
- Sent: the book's title and author, and each part's text (cut at
  `MAX_WORDS` words). Nothing about you.
- Only with an AI key set up, and for books that reflow (EPUBs and the
  like: their text can be read part by part).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Guide = {
    SETTING = "gzreader_story_guide",
    VERSION = 1,
    MAX_WORDS = 9000, -- (a part's text sent at most: about 12,000 tokens)
    MAX_TOKENS = 1600,
    LIST_MAX = 12,
    SYSTEM = "You build a reader's guide to a book from its own text, as an X-Ray or a story guide does. "
        .. "Use only the text you are given: never what you know of the book from elsewhere, and nothing that happens after it. "
        .. "For a work of fiction, people are its characters; for non-fiction, the people it discusses, "
        .. "and terms are its ideas, methods and technical words. Reply with JSON only.",
}

local function words(text)
    local n = 0
    for _w in tostring(text or ""):gmatch("%S+") do n = n + 1 end
    return n
end
Guide.words = words

--- `text` cut to `max` words (whole words, the start kept). Pure.
function Guide.cut(text, max)
    text = tostring(text or "")
    local n, at = 0, nil
    for s in text:gmatch("()%S+") do
        n = n + 1
        if n > max then at = s; break end
    end
    if not at then return text, false end
    return text:sub(1, at - 1):gsub("%s+$", ""), true
end

--- The parts up to the page you're on: the contents' shallowest entries
--- (their title, page and xpointer), each to the next; the one you're in
--- ends where you are (`partial`). `toc`: ReaderToc's list; `page`: yours;
--- `here`: your xpointer. Pure.
function Guide.parts(toc, page, here)
    local top
    for _i, e in ipairs(type(toc) == "table" and toc or {}) do
        if type(e) == "table" and tonumber(e.depth) and (not top or e.depth < top) then top = e.depth end
    end
    local list = {}
    for _i, e in ipairs(type(toc) == "table" and toc or {}) do
        if e.depth == top and type(e.xpointer) == "string" and tonumber(e.page) then list[#list + 1] = e end
    end
    local out = {}
    for i, e in ipairs(list) do
        if e.page > page then break end
        local nxt = list[i + 1]
        if nxt and nxt.page <= page then
            out[#out + 1] = { title = e.title, from = e.xpointer, to = nxt.xpointer, page = e.page }
        else
            out[#out + 1] = { title = e.title, from = e.xpointer, to = here, page = e.page, partial = true }
        end
    end
    return out
end

--- A part's key in what's kept (its start and end).
function Guide.key(part) return tostring(part.from) .. "|" .. tostring(part.to) end

--- What to ask about one part: { system, text, max_tokens, what }. Pure.
function Guide.question(title, authors, part, text)
    local book = T("\"%1\"", tostring(title or ""))
    if type(authors) == "string" and authors:match("%S") then book = book .. " by " .. (authors:gsub("\n", ", ")) end
    local cut, was_cut = Guide.cut(text, Guide.MAX_WORDS)
    local q = "Book: " .. book .. ".\nPart: " .. tostring(part.title or "") .. (part.partial and " (read up to here so far)" or "")
        .. "\n\nThe part's text" .. (was_cut and " (its start)" or "") .. ":\n" .. cut .. "\n\n"
        .. "Reply with JSON only, in this shape: "
        .. "{\"summary\": \"2 to 4 sentences: what happens, or what is explained, in this part\", "
        .. "\"people\": [{\"name\": \"…\", \"about\": \"who they are, in a few words\"}], "
        .. "\"places\": [{\"name\": \"…\", \"about\": \"…\"}], "
        .. "\"terms\": [{\"name\": \"…\", \"about\": \"…\"}]}. "
        .. "At most " .. Guide.LIST_MAX .. " of each, the ones that matter most; an empty list where there are none."
    return { system = Guide.SYSTEM, text = q, max_tokens = Guide.MAX_TOKENS, what = "story guide" }
end

local function list(v)
    local out = {}
    for _i, e in ipairs(type(v) == "table" and v or {}) do
        if type(e) == "table" and type(e.name) == "string" and e.name:match("%S") then
            out[#out + 1] = { name = e.name:gsub("^%s+", ""):gsub("%s+$", ""), about = type(e.about) == "string" and e.about or "" }
        end
    end
    return out
end

--- A part's answer read from the AI's text, or nil. Pure.
function Guide.parse(text)
    local body = type(text) == "string" and text:match("%b{}") or nil
    local ok, data = pcall(function() return body and require("gzreader_json").decode(body) end)
    if not ok or type(data) ~= "table" then return nil end
    return { summary = type(data.summary) == "string" and data.summary or "",
        people = list(data.people), places = list(data.places), terms = list(data.terms) }
end

--- The parts' answers put together: { parts = { { title, summary } }, people,
--- places, terms } where each name is once, with what the latest part said
--- of it and in how many parts it came up, the most first. Pure.
function Guide.merge(answers)
    local out = { parts = {}, people = {}, places = {}, terms = {} }
    for _i, kind in ipairs({ "people", "places", "terms" }) do
        local by = {}
        for _j, a in ipairs(answers) do
            for _k, e in ipairs(a[kind] or {}) do
                local k = e.name:lower()
                local have = by[k]
                if have then
                    have.count = have.count + 1
                    if e.about ~= "" then have.about = e.about end
                else
                    have = { name = e.name, about = e.about, count = 1, first = #out[kind] + 1 }
                    by[k] = have
                    out[kind][#out[kind] + 1] = have
                end
            end
        end
        table.sort(out[kind], function(x, y)
            if x.count ~= y.count then return x.count > y.count end
            return x.first < y.first
        end)
    end
    for _i, a in ipairs(answers) do
        if a.summary and a.summary ~= "" then out.parts[#out.parts + 1] = { title = a.title, summary = a.summary } end
    end
    return out
end

--- The window's text: up to where, what has happened (the latest parts last),
--- then People, Places, Terms. Pure.
function Guide.render(merged, where, by)
    local out = {}
    if where then out[#out + 1] = where .. "\n" end
    local function section(title, entries)
        if #entries == 0 then return end
        out[#out + 1] = title
        for _i, e in ipairs(entries) do
            out[#out + 1] = "\u{2022} " .. e.name .. (e.about ~= "" and (" \u{2014} " .. e.about) or "")
                .. (e.count > 1 and ("  (" .. e.count .. ")") or "")
        end
        out[#out + 1] = ""
    end
    section(_("People"), merged.people)
    section(_("Places"), merged.places)
    section(_("Terms"), merged.terms)
    if #merged.parts > 0 then
        out[#out + 1] = _("So far")
        for _i, p in ipairs(merged.parts) do out[#out + 1] = (p.title and (p.title .. ": ") or "") .. p.summary .. "\n" end
    end
    out[#out + 1] = T(_("Made by %1 from the book's own text, up to your page. It can be wrong."), tostring(by or "AI"))
    return table.concat(out, "\n")
end

--- Can the tile be shown? (An AI key set up, a book that reflows.)
function Guide.available(plugin, ui)
    if type(ui) ~= "table" or not ui.document or (ui.document.info and ui.document.info.has_pages) then return false end
    local ok, AI = pcall(require, "gzreader_ai")
    return ok and AI.ready(plugin) == true
end

--- Where you are: page, xpointer, chapter.
local function here(ui)
    local pos = {}
    pcall(function()
        pos.page = ui.document:getCurrentPage()
        pos.total = ui.document:getPageCount()
        pos.xp = ui.document:getXPointer()
        pos.chapter = ui.toc and ui.toc:getTocTitleByPage(pos.page)
    end)
    return pos
end

--- The guide: what's kept shown, the parts not asked about yet asked first
--- (after a question the first time, as it sends the book's text).
function Guide.show(plugin, ui)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local AI = require("gzreader_ai")
    local pos = here(ui)
    pcall(function() ui.toc:fillToc() end)
    local parts = Guide.parts(ui.toc and ui.toc.toc, pos.page or 1, pos.xp)
    if #parts == 0 then
        -- (no contents: the book from its start to here, as one part)
        local okb, start = pcall(function() return ui.document:getPageXPointer(1) end)
        parts = { { title = ui.doc_props and ui.doc_props.display_title, from = okb and start or nil, to = pos.xp, partial = true } }
    end
    local ds = ui.doc_settings
    local kept = ds and ds:readSetting(Guide.SETTING)
    if type(kept) ~= "table" or kept.v ~= Guide.VERSION then kept = { v = Guide.VERSION, parts = {} } end
    local todo = {}
    for _i, p in ipairs(parts) do if not kept.parts[Guide.key(p)] then todo[#todo + 1] = p end end
    local name = AI.name(AI.provider(plugin))
    local function window()
        local answers = {}
        for _i, p in ipairs(parts) do
            local a = kept.parts[Guide.key(p)]
            if a then a.title = p.title; answers[#answers + 1] = a end
        end
        local where = {}
        if pos.page and pos.total and pos.total > 0 then where[#where + 1] = T(_("Up to %1%"), math.floor(pos.page * 100 / pos.total + 0.5)) end
        if type(pos.chapter) == "string" and pos.chapter ~= "" then where[#where + 1] = pos.chapter end
        local viewer
        viewer = require("ui/widget/textviewer"):new{
            title = _("Story guide"),
            text = Guide.render(Guide.merge(answers), #where > 0 and table.concat(where, " \u{00B7} ") or nil, name),
            buttons_table = { { { text = _("Close"), callback = function() UIManager:close(viewer) end } } },
            add_default_buttons = false,
        }
        UIManager:show(viewer)
        return viewer
    end
    if #todo == 0 then return window() end
    local texts, total_words = {}, 0
    for i, p in ipairs(todo) do
        local ok, t = pcall(function() return ui.document:getTextFromXPointers(p.from, p.to) end)
        texts[i] = ok and type(t) == "string" and t or ""
        total_words = total_words + math.min(words(texts[i]), Guide.MAX_WORDS)
    end
    local function run()
        local i = 0
        local waiting
        local function step()
            i = i + 1
            if waiting then UIManager:close(waiting) end
            if i > #todo then
                kept.by = name
                -- (a part you were in is kept until you read on: the next time it's asked again)
                for k, a in pairs(kept.parts) do if a.partial and k ~= Guide.key(todo[#todo]) then kept.parts[k] = nil end end
                if ds then ds:saveSetting(Guide.SETTING, kept) end
                Log.info("story guide:", #todo, "part(s) read,", total_words, "words sent")
                return window()
            end
            waiting = InfoMessage:new{ text = T(_("%1 is reading part %2 of %3…"), name, i, #todo) }
            UIManager:show(waiting)
            local props = ui.doc_props or {}
            AI.ask(plugin, Guide.question(props.display_title or props.title, props.authors, todo[i], texts[i]), function(text, why)
                local a = Guide.parse(text)
                if not a then
                    if waiting then UIManager:close(waiting); waiting = nil end
                    Log.warn("story guide: no answer for a part:", tostring(why or "unreadable"))
                    UIManager:show(InfoMessage:new{ text = T(_("%1 didn't answer: %2"), name, tostring(why or _("no answer"))) })
                    if ds then ds:saveSetting(Guide.SETTING, kept) end
                    return
                end
                a.partial = todo[i].partial or nil
                kept.parts[Guide.key(todo[i])] = a
                UIManager:nextTick(step)
            end)
        end
        step()
    end
    if next(kept.parts) == nil then
        -- the first time for this book: it sends the book's text
        return UIManager:show(require("ui/widget/confirmbox"):new{
            text = T(_("Story guide sends the text you've read so far (about %1 words) to %2, a part at a time, to make the guide. Later only what you've read since goes.\n\nGo ahead?"),
                total_words, name),
            ok_text = _("Make the guide"),
            ok_callback = run,
        })
    end
    return run()
end

--- The quick panel's tile in a book (nil without an AI key or for a page book).
function Guide.tile(plugin, ui)
    if not Guide.available(plugin, ui) then return nil end
    return { id = "storyguide", icon = "storyguide", label = _("Story guide"), run = function() Guide.show(plugin, ui) end }
end

return Guide
