--[[--
A story's text from its own web page, for the daily paper's full stories
(gzreader_daily.lua): what a browser's reader view does, with patterns.

    local text = Article.extract(html)   -- paragraphs, or nil

How:
1. What is never the story goes first: scripts, styles, the page's header,
   navigation, footer, sidebars, forms, comments.
2. The part that holds the story: the <article> (or <main>) with the most
   paragraph text, else the whole page.
3. Its paragraphs (and sub-headings, quotes, list items), each as plain
   text; the short lines sites put between them ("Advertisement", "Share
   this", "Sign up for…") are dropped.
4. Kept only when it reads like an article: MIN_PARAGRAPHS paragraphs and
   MIN_BYTES of text. A paywall's teaser, a page built by scripts or a
   cookie wall gives nil, and the paper keeps what the feed carried.

Nothing here touches the network or the screen.
]]

local Feeds = require("gzreader_feeds")

local Article = {
    MIN_BYTES = 600,
    MIN_PARAGRAPHS = 3,
    MAX_HTML = 3 * 1024 * 1024,
}

-- blocks that are never the story (lower-case names; the page is matched in both cases)
local DROP = { "script", "style", "noscript", "svg", "nav", "header", "footer", "aside", "form", "iframe", "figure", "button", "select", "template" }

-- a short line that isn't the story's
local JUNK = {
    "^advertisement$", "^advertising$", "^share this", "^share$", "^read more", "^related", "^sign up", "^subscribe", "^follow us",
    "^copyright", "all rights reserved", "^image source", "^image caption", "^photo:", "^credit:", "^watch:", "^listen:", "^loading",
    "cookies?%s+policy", "^we use cookies", "^skip to", "^click here", "^more on this story", "^media caption", "^getty images$",
}

local function lowerTags(html, name)
    -- (tag names are matched case-blind by lowering the few that are looked for)
    local upper = name:upper()
    if not html:find("<" .. upper, 1, true) and not html:find("</" .. upper, 1, true) then return html end
    return (html:gsub("<(/?)" .. upper .. "([%s>/])", function(slash, after) return "<" .. slash .. name .. after end))
end

--- Remove every <name …>…</name> block (not nested ones' outer part: the
--- first closing tag ends it, which is right for these).
local function dropBlocks(html, name)
    html = lowerTags(html, name)
    if not html:find("<" .. name, 1, true) then return html end
    local out, pos = {}, 1
    while true do
        local s, e = html:find("<" .. name .. "[%s>]", pos)
        if not s then break end
        local cs, ce = html:find("</" .. name .. "%s*>", e, false)
        out[#out + 1] = html:sub(pos, s - 1)
        if not cs then pos = #html + 1; break end -- (never closed: the rest goes)
        pos = ce + 1
    end
    out[#out + 1] = html:sub(pos)
    return table.concat(out, " ")
end
Article._dropBlocks = dropBlocks

--- The paragraphs of a piece of HTML, as plain text, junk lines out.
function Article.paragraphs(html)
    local out = {}
    for _i, name in ipairs({ "p", "h2", "h3", "h4", "blockquote", "li" }) do html = lowerTags(html, name) end
    -- (in page order: every opening of one of these, to its own closing tag)
    local pos = 1
    while true do
        local s, e, name = html:find("<(%a%w*)[^>]*>", pos)
        if not s then break end
        if name == "p" or name == "h2" or name == "h3" or name == "h4" or name == "li" then
            local cs, ce = html:find("</" .. name .. "%s*>", e + 1)
            -- (a <p> never closed ends at the next <p>)
            local ns = name == "p" and html:find("<p[%s>]", e + 1) or nil
            if not cs or (ns and ns < cs) then cs, ce = (ns or #html + 1), (ns or #html + 1) - 1 end
            local text = Feeds.text(html:sub(e + 1, cs - 1)):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then
                local low = text:lower()
                local junk = false
                if #text < 90 then
                    for _j, pat in ipairs(JUNK) do
                        if low:find(pat) then junk = true; break end
                    end
                end
                -- (a list item only when it's a sentence: menus are lists too)
                if name == "li" and (#text < 40 or not text:find("[%.!%?:]")) then junk = true end
                if not junk then
                    out[#out + 1] = { text = (name == "li" and "\u{2022} " or "") .. text, heading = name:sub(1, 1) == "h", para = name == "p" }
                end
            end
            pos = math.max(ce + 1, e + 1)
        else
            pos = e + 1
        end
    end
    return out
end

local function weight(paras)
    local bytes, n = 0, 0
    for _i, p in ipairs(paras) do
        if p.para and #p.text >= 60 then
            bytes = bytes + #p.text
            n = n + 1
        end
    end
    return bytes, n
end

--- Every <name …>…</name> part of the page (to its first closing tag).
local function parts(html, name)
    html = lowerTags(html, name)
    local out, pos = {}, 1
    while true do
        local s, e = html:find("<" .. name .. "[%s>]", pos)
        if not s then break end
        local cs, ce = html:find("</" .. name .. "%s*>", e)
        if not cs then
            out[#out + 1] = html:sub(e + 1)
            break
        end
        out[#out + 1] = html:sub(e + 1, cs - 1)
        pos = ce + 1
    end
    return out
end

--- A page's bytes as UTF-8 (pages that say Latin-1 / Windows-1252).
function Article.decode(html, content_type)
    local charset = tostring(content_type or ""):lower():match("charset%s*=%s*[\"']?([%w%-_]+)")
        or html:sub(1, 4096):lower():match("<meta[^>]-charset%s*=%s*[\"']?([%w%-_]+)")
    if charset == "iso-8859-1" or charset == "windows-1252" or charset == "latin1" or charset == "iso-8859-15" then
        return Feeds.fromLatin1(html)
    end
    return Feeds.utf8(html)
end

--- The picture a page names as its own (og:image, twitter:image): an
--- http(s) address, or nil. Looked for in the page's head only.
function Article.leadImage(html)
    if type(html) ~= "string" then return nil end
    local head = html:sub(1, 60000)
    for tag in head:gmatch("<[mM][eE][tT][aA]%s[^>]*>") do
        local low = tag:lower()
        if low:find("og:image", 1, true) or low:find("twitter:image", 1, true) then
            local name = low:match("property%s*=%s*[\"']([^\"']+)") or low:match("name%s*=%s*[\"']([^\"']+)")
            if name == "og:image" or name == "og:image:url" or name == "og:image:secure_url" or name == "twitter:image" or name == "twitter:image:src" then
                local u = tag:match("[cC][oO][nN][tT][eE][nN][tT]%s*=%s*\"([^\"]*)\"") or tag:match("[cC][oO][nN][tT][eE][nN][tT]%s*=%s*'([^']*)'")
                u = u and Feeds.entities(u):gsub("^%s+", ""):gsub("%s+$", "") or nil
                if u and u:match("^//") then u = "https:" .. u end
                if u and u:match("^https?://[^%s\"'<>]+$") then return u end
            end
        end
    end
    return nil
end

--- Is `text` markup shown as text (a page's "Embed" box holds the code to
--- paste, e.g. <iframe src="…">), not prose?
function Article.isMarkup(text)
    text = tostring(text or "")
    return text:find("<%s*%a[%w%-]*%s+[%w%-:]+%s*=") ~= nil or text:find("<%s*/%s*%a[%w%-]*%s*>") ~= nil
        or text:lower():find("<%s*iframe") ~= nil
end

-- how a picture's caption ends on pages that fold them ("… KUT News hide caption")
local CAPTION_ENDS = { "hide caption$", "toggle caption$", "enlarge this image$" }

--[[ What isn't the story, out of its paragraphs (`list`: strings, in order;
`title`: the headline, when known). Returns a new list.
- Markup shown as text (Article.isMarkup).
- Picture captions that end with the page's "hide caption" button.
- The headline said again.
- The short lines over the story, before its first real paragraph: the
  section ("News"), "By", the writer's name.
Never everything: when nothing would be left, `list` comes back as it was. ]]
function Article.tidy(list, title)
    local function norm(t) return (tostring(t or ""):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")) end
    local head = norm(title)
    local out, started = {}, false
    for _i, text in ipairs(list or {}) do
        local low = norm(text)
        local drop = Article.isMarkup(text) or (head ~= "" and low == head)
        if not drop then
            for _j, pat in ipairs(CAPTION_ENDS) do
                if low:find(pat) then drop = true; break end
            end
        end
        if not drop and not started then
            -- (a line over the story: short, and not a sentence)
            if #text < 60 and not text:find("[%.!%?\"\u{201D}]%s*$") then drop = true else started = true end
        end
        if not drop then out[#out + 1] = text end
    end
    if #out == 0 then return list or {} end
    return out
end

--- Article.tidy for a story's text as it's kept (paragraphs with an empty
--- line between them).
function Article.tidyText(text, title)
    if type(text) ~= "string" or text == "" then return text end
    local list = {}
    for para in (text .. "\n\n"):gmatch("(.-)\n\n+") do
        if para:find("%S") then list[#list + 1] = para end
    end
    return table.concat(Article.tidy(list, title), "\n\n")
end

--- The story's text from its page: paragraphs separated by an empty line,
--- or nil (and why: "not html", "too big", "no article").
function Article.extract(html, content_type)
    if type(html) ~= "string" or html == "" then return nil, "not html" end
    if #html > Article.MAX_HTML then return nil, "too big" end
    if not html:find("<[pP][%s>]") and not html:find("<[hH][tT][mM][lL]") then return nil, "not html" end
    html = Article.decode(html, content_type)
    html = html:gsub("\r\n?", "\n"):gsub("<!%-%-.-%-%->", " ")
    for _i, name in ipairs(DROP) do html = dropBlocks(html, name) end
    local best, best_bytes, best_n = nil, 0, 0
    for _i, name in ipairs({ "article", "main" }) do
        for _j, part in ipairs(parts(html, name)) do
            local paras = Article.paragraphs(part)
            local bytes, n = weight(paras)
            if bytes > best_bytes then best, best_bytes, best_n = paras, bytes, n end
        end
        if best and best_n >= Article.MIN_PARAGRAPHS and best_bytes >= Article.MIN_BYTES then break end
    end
    if not best or best_n < Article.MIN_PARAGRAPHS or best_bytes < Article.MIN_BYTES then
        local body = html:match("<[bB][oO][dD][yY][^>]*>(.*)") or html
        best = Article.paragraphs(body)
        best_bytes, best_n = weight(best)
    end
    if best_n < Article.MIN_PARAGRAPHS or best_bytes < Article.MIN_BYTES then return nil, "no article" end
    -- (a heading with nothing under it, at the end, isn't the story's)
    while #best > 0 and best[#best].heading do best[#best] = nil end
    local out, seen = {}, {}
    for _i, p in ipairs(best) do
        if not seen[p.text] then
            seen[p.text] = true
            out[#out + 1] = p.text
        end
    end
    return table.concat(Article.tidy(out), "\n\n")
end

return Article
