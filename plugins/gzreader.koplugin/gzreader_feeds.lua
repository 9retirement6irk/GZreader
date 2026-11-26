--[[--
News feeds (RSS 2.0, RSS 1.0 / RDF, Atom) read into plain headlines and
text, for the daily paper (gzreader_daily.lua).

Read with patterns rather than an XML tree: feeds in the wild are often not
quite XML (HTML entities, a stray "&", a byte-order mark), a whole tree of a
300 KB feed is a lot of memory on a Kindle 3, and only a handful of fields
are wanted from each item.

    local feed = Feeds.parse(body, { max_items = 5, max_text = 4000 })
    feed.title, feed.items[1] = { title, link, text, at, image }

`text` is plain text (paragraphs separated by an empty line), `at` the
item's time (UTC seconds) or nil, `image` its picture's address or nil. Nothing here touches the network or the
screen.
]]

local Feeds = {}

Feeds.MAX_ITEMS = 10
Feeds.MAX_TEXT = 4000

---------------------------------------------------------------- text

local function utf8char(cp)
    if not cp or cp < 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return "" end
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end
Feeds.utf8char = utf8char

local ENTITIES = {
    amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
    mdash = "\u{2014}", ndash = "\u{2013}", hellip = "\u{2026}", bull = "\u{2022}", middot = "\u{00B7}",
    lsquo = "\u{2018}", rsquo = "\u{2019}", ldquo = "\u{201C}", rdquo = "\u{201D}", sbquo = "\u{201A}", bdquo = "\u{201E}",
    laquo = "\u{00AB}", raquo = "\u{00BB}", copy = "\u{00A9}", reg = "\u{00AE}", trade = "\u{2122}", deg = "\u{00B0}",
    pound = "\u{00A3}", euro = "\u{20AC}", yen = "\u{00A5}", cent = "\u{00A2}", sect = "\u{00A7}", para = "\u{00B6}",
    times = "\u{00D7}", divide = "\u{00F7}", plusmn = "\u{00B1}", frac12 = "\u{00BD}", frac14 = "\u{00BC}", frac34 = "\u{00BE}",
    prime = "\u{2032}", Prime = "\u{2033}", minus = "\u{2212}", larr = "\u{2190}", rarr = "\u{2192}", uarr = "\u{2191}", darr = "\u{2193}",
    aacute = "á", eacute = "é", iacute = "í", oacute = "ó", uacute = "ú", yacute = "ý",
    Aacute = "Á", Eacute = "É", Iacute = "Í", Oacute = "Ó", Uacute = "Ú",
    agrave = "à", egrave = "è", igrave = "ì", ograve = "ò", ugrave = "ù", Agrave = "À", Egrave = "È",
    acirc = "â", ecirc = "ê", icirc = "î", ocirc = "ô", ucirc = "û",
    auml = "ä", euml = "ë", iuml = "ï", ouml = "ö", uuml = "ü", Auml = "Ä", Ouml = "Ö", Uuml = "Ü", szlig = "ß",
    atilde = "ã", ntilde = "ñ", otilde = "õ", Ntilde = "Ñ", ccedil = "ç", Ccedil = "Ç",
    aring = "å", Aring = "Å", aelig = "æ", AElig = "Æ", oslash = "ø", Oslash = "Ø",
    zwnj = "", zwj = "", shy = "", ensp = " ", emsp = " ", thinsp = " ",
}

--- &amp; &#8217; &#x2019; &eacute; … as the characters they stand for; an
--- entity that isn't known stays as it is.
function Feeds.entities(s)
    if not s:find("&", 1, true) then return s end
    return (s:gsub("&(#?)([%w]+);", function(hash, name)
        if hash == "#" then
            local cp = name:match("^[xX](%x+)$")
            cp = cp and tonumber(cp, 16) or tonumber(name)
            if not cp then return nil end
            if cp == 160 then return " " end
            return utf8char(cp)
        end
        return ENTITIES[name]
    end))
end

--- `s` as valid UTF-8: bytes that aren't are dropped (a feed cut in the
--- middle of a character, or one that says UTF-8 and isn't).
function Feeds.utf8(s)
    if not s:find("[\128-\255]") then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c < 0xE0) and 2 or (c >= 0xE0 and c < 0xF0) and 3
            or (c >= 0xF0 and c < 0xF5) and 4 or 0
        local ok = len > 0 and i + len - 1 <= n
        if ok then
            for j = i + 1, i + len - 1 do
                local b = s:byte(j)
                if b < 0x80 or b > 0xBF then ok = false; break end
            end
        end
        if ok then
            out[#out + 1] = s:sub(i, i + len - 1)
            i = i + len
        else
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Windows-1252's 0x80–0x9F (curly quotes, dashes, the euro), which Latin-1 feeds use
local CP1252 = {
    [0x80] = 0x20AC, [0x82] = 0x201A, [0x83] = 0x0192, [0x84] = 0x201E, [0x85] = 0x2026, [0x86] = 0x2020, [0x87] = 0x2021,
    [0x88] = 0x02C6, [0x89] = 0x2030, [0x8A] = 0x0160, [0x8B] = 0x2039, [0x8C] = 0x0152, [0x8E] = 0x017D,
    [0x91] = 0x2018, [0x92] = 0x2019, [0x93] = 0x201C, [0x94] = 0x201D, [0x95] = 0x2022, [0x96] = 0x2013, [0x97] = 0x2014,
    [0x98] = 0x02DC, [0x99] = 0x2122, [0x9A] = 0x0161, [0x9B] = 0x203A, [0x9C] = 0x0153, [0x9E] = 0x017E, [0x9F] = 0x0178,
}

--- Latin-1 / Windows-1252 bytes as UTF-8.
function Feeds.fromLatin1(s)
    return (s:gsub("[\128-\255]", function(ch)
        local b = ch:byte()
        return utf8char(CP1252[b] or b)
    end))
end

--- `s` cut to at most `max` bytes, at a word when there's one near, never in
--- the middle of a character, with "…" when something was cut.
function Feeds.cut(s, max)
    if #s <= max then return s end
    local to = max
    while to > 0 do
        local b = s:byte(to + 1)
        if not b or b < 0x80 or b > 0xBF then break end
        to = to - 1
    end
    local part = s:sub(1, to)
    local at = part:match("^.*()%s")
    if at and at > to * 0.8 then part = part:sub(1, at - 1) end
    return (part:gsub("[%s%p]+$", "")) .. "\u{2026}"
end

--- HTML as plain text: paragraphs separated by an empty line, list items
--- as "• …", no tags, no scripts, entities as their characters.
function Feeds.text(html)
    local s = tostring(html or "")
    if s == "" then return "" end
    s = s:gsub("\r\n?", "\n")
    s = s:gsub("<!%-%-.-%-%->", "")
    for _i, name in ipairs({ "script", "style", "figcaption", "iframe", "noscript", "svg" }) do
        local upper = name:upper()
        s = s:gsub("<" .. name .. "[%s>].-</" .. name .. "%s*>", " ")
        s = s:gsub("<" .. upper .. "[%s>].-</" .. upper .. "%s*>", " ")
    end
    if s:find("<", 1, true) then
        -- (in HTML a line break in the source is a space)
        s = s:gsub("%s*\n%s*", " ")
        s = s:gsub("<[bB][rR]%s*/?>", "\n")
        s = s:gsub("<[lL][iI]%s[^>]*>", "\n\u{2022} "):gsub("<[lL][iI]>", "\n\u{2022} ")
        s = s:gsub("</?[pP]%s*>", "\n\n"):gsub("<[pP]%s[^>]*>", "\n\n")
        s = s:gsub("</?[dD][iI][vV][^>]*>", "\n\n")
        s = s:gsub("</?[hH]%d[^>]*>", "\n\n")
        s = s:gsub("</?[bB][lL][oO][cC][kK][qQ][uU][oO][tT][eE][^>]*>", "\n\n")
        s = s:gsub("</?[uUoO][lL][^>]*>", "\n\n")
        s = s:gsub("</[tT][rR]%s*>", "\n")
        s = s:gsub("<[^>]*>", "")
    end
    s = Feeds.entities(s)
    s = s:gsub("\u{00A0}", " ")
    s = s:gsub("[ \t\f\v]+", " ")
    s = s:gsub(" ?\n ?", "\n")
    s = s:gsub("\n\n\n+", "\n\n")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

---------------------------------------------------------------- dates

--- Seconds since 1970 (UTC) of a calendar date and time given in UTC.
function Feeds.timegm(y, m, d, hh, mm, ss)
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not (y and m and d) or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    -- (days from the civil date: Howard Hinnant's algorithm)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    local days = era * 146097 + doe - 719468
    return days * 86400 + (tonumber(hh) or 0) * 3600 + (tonumber(mm) or 0) * 60 + (tonumber(ss) or 0)
end

local MONTHS = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }
local ZONES = { gmt = 0, ut = 0, utc = 0, z = 0, est = -5, edt = -4, cst = -6, cdt = -5, mst = -7, mdt = -6, pst = -8, pdt = -7 }

local function offset(zone)
    zone = tostring(zone or ""):lower()
    if zone == "" then return 0 end
    if ZONES[zone] then return ZONES[zone] * 3600 end
    local sign, hh, mm = zone:match("^([+-])(%d%d):?(%d%d)$")
    if not sign then return 0 end
    return (sign == "-" and -1 or 1) * (tonumber(hh) * 3600 + tonumber(mm) * 60)
end

--- A feed's date as UTC seconds: RSS's "Tue, 17 Nov 2026 07:05:00 GMT" (or
--- "+0100", "EST"), Atom's "2026-11-17T07:05:00Z" (or "+01:00"). nil when it
--- is neither.
function Feeds.date(s)
    s = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    local y, m, d, hh, mm, ss, rest = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[Tt ](%d%d):(%d%d):?(%d*)(.*)$")
    if y then
        local zone = rest:gsub("^[%.,]%d+", ""):gsub("%s", "")
        local t = Feeds.timegm(y, m, d, hh, mm, ss ~= "" and ss or 0)
        return t and t - offset(zone)
    end
    y, m, d = s:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y then return Feeds.timegm(y, m, d, 12, 0, 0) end
    local day, mon, year, h2, m2, s2, zone = s:match("(%d%d?)%s+(%a%a%a)%a*%s+(%d%d%d?%d?)%s+(%d%d?):(%d%d):?(%d*)%s*([%a%d:+-]*)")
    if not day then return nil end
    local month = MONTHS[mon:lower()]
    if not month then return nil end
    year = tonumber(year)
    if year < 100 then year = year + (year < 70 and 2000 or 1900) end
    local t = Feeds.timegm(year, month, day, h2, m2, s2 ~= "" and s2 or 0)
    return t and t - offset(zone)
end

---------------------------------------------------------------- XML, loosely

local function magic(name) return (name:gsub("[%-%.%+%*%?%^%$%(%)%[%]%%]", "%%%0")) end

--- What's between <name …> and </name> (the first one in `block`), and the
--- opening tag's attributes; nil when there's none. An empty <name …/> gives "".
local function element(block, name, from)
    local pat = "<" .. magic(name) .. "([%s/>])"
    local s, e, after = block:find(pat, from or 1)
    if not s then return nil end
    local attrs, close
    if after == ">" then
        attrs, close = "", e
    else
        close = block:find(">", e, true)
        if not close then return nil end
        attrs = block:sub(e, close - 1)
    end
    if attrs:sub(-1) == "/" or after == "/" then return "", attrs, close + 1 end
    local cs, ce = block:find("</" .. magic(name) .. "%s*>", close + 1)
    if not cs then return nil end
    return block:sub(close + 1, cs - 1), attrs, ce + 1
end
Feeds._element = element

--- An element's content as text: CDATA sections as they are, the rest with
--- XML's entities read.
local function unxml(raw)
    if not raw or raw == "" then return "" end
    if not raw:find("<![CDATA[", 1, true) then return Feeds.entities(raw) end
    local out, pos = {}, 1
    while true do
        local s, e = raw:find("<![CDATA[", pos, true)
        if not s then
            out[#out + 1] = Feeds.entities(raw:sub(pos))
            break
        end
        out[#out + 1] = Feeds.entities(raw:sub(pos, s - 1))
        local cs, ce = raw:find("]]>", e + 1, true)
        if not cs then
            out[#out + 1] = raw:sub(e + 1)
            break
        end
        out[#out + 1] = raw:sub(e + 1, cs - 1)
        pos = ce + 1
    end
    return table.concat(out)
end
Feeds._unxml = unxml

local function attr(attrs, name)
    if not attrs then return nil end
    local v = attrs:match("[%s\"']" .. magic(name) .. "%s*=%s*\"([^\"]*)\"") or attrs:match("^" .. magic(name) .. "%s*=%s*\"([^\"]*)\"")
        or attrs:match("[%s\"']" .. magic(name) .. "%s*=%s*'([^']*)'") or attrs:match("^" .. magic(name) .. "%s*=%s*'([^']*)'")
    return v and Feeds.entities(v) or nil
end

local function oneLine(s)
    return (Feeds.text(s):gsub("%s+", " "))
end

--- An item's link: RSS's <link>https://…</link>, Atom's <link href="…"/>
--- (the one that isn't the feed itself, a reply thread or an enclosure). Only
--- http(s) links are kept.
local function link(block)
    local best
    local from = 1
    while true do
        local content, attrs, nxt = element(block, "link", from)
        if not content then break end
        local href = attr(attrs, "href")
        if href then
            local rel = (attr(attrs, "rel") or "alternate"):lower()
            if rel == "alternate" then best = href; break end
            best = best or (rel ~= "self" and rel ~= "enclosure" and rel ~= "replies" and href) or nil
        else
            local text = unxml(content):gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then best = text; break end
        end
        from = nxt
    end
    if not best then
        local guid, gattrs = element(block, "guid")
        if guid and (attr(gattrs, "isPermaLink") or "true"):lower() ~= "false" then best = unxml(guid):gsub("^%s+", ""):gsub("%s+$", "") end
    end
    if best and best:match("^https?://[^%s]+$") then return best end
    return nil
end

--- `text` without the line WordPress feeds end every item with ("The post
--- <headline> appeared first on <site>."): it isn't the story's.
function Feeds.withoutPostLine(text)
    local s = tostring(text or "")
    local at
    local from = 1
    while true do
        local i = s:find("The post ", from, true)
        if not i then break end
        at, from = i, i + 1
    end
    if at and s:sub(at):find("^The post .- appeared first on [^\n]-%.?%s*$") then
        s = s:sub(1, at - 1):gsub("%s+$", "")
    end
    return s
end

--- The longest of an item's texts (the whole article when the feed carries
--- it, else its summary), as plain text.
local function body(block, max_text)
    local best = ""
    for _i, name in ipairs({ "content:encoded", "content", "description", "summary" }) do
        local raw, attrs = element(block, name)
        if raw and raw ~= "" then
            local kind = (attr(attrs, "type") or "html"):lower()
            local text
            if kind == "xhtml" then
                text = Feeds.text(raw)
            elseif kind == "text" then
                text = Feeds.text((unxml(raw):gsub("&", "&amp;"):gsub("<", "&lt;")))
            else
                text = Feeds.text(unxml(raw))
            end
            text = Feeds.withoutPostLine(text)
            if #text > #best then best = text end
        end
    end
    return Feeds.cut(best, max_text)
end

--- A story's picture: what the feed names for it (media:content,
--- media:thumbnail, an image enclosure), else the first picture in its
--- text. Only http(s) addresses; nil when there's none.
local function picture(block)
    local function ok(u)
        if type(u) ~= "string" then return nil end
        u = u:gsub("^%s+", ""):gsub("%s+$", "")
        if u:match("^//") then u = "https:" .. u end
        return u:match("^https?://[^%s\"'<>]+$") and u or nil
    end
    local from = 1
    while true do
        local content, attrs, nxt = element(block, "media:content", from)
        if not content then break end
        local kind = (attr(attrs, "type") or attr(attrs, "medium") or "image"):lower()
        local u = ok(attr(attrs, "url"))
        if u and kind:find("image", 1, true) then return u end
        from = nxt
    end
    local thumb = { element(block, "media:thumbnail") }
    if thumb[2] and ok(attr(thumb[2], "url")) then return ok(attr(thumb[2], "url")) end
    from = 1
    while true do
        local content, attrs, nxt = element(block, "enclosure", from)
        if not content then break end
        if (attr(attrs, "type") or ""):lower():find("^image/") and ok(attr(attrs, "url")) then return ok(attr(attrs, "url")) end
        from = nxt
    end
    from = 1
    while true do
        local content, attrs, nxt = element(block, "link", from)
        if not content then break end
        if (attr(attrs, "rel") or ""):lower() == "enclosure" and (attr(attrs, "type") or ""):lower():find("^image/") and ok(attr(attrs, "href")) then
            return ok(attr(attrs, "href"))
        end
        from = nxt
    end
    for _i, name in ipairs({ "content:encoded", "content", "description", "summary" }) do
        local raw = element(block, name)
        if raw and raw ~= "" then
            local html = unxml(raw)
            for tag in html:gmatch("<[iI][mM][gG]%s[^>]*>") do
                local u = ok(Feeds.entities(tag:match("[%s\"']src%s*=%s*\"([^\"]*)\"") or tag:match("[%s\"']src%s*=%s*'([^']*)'") or ""))
                -- (not the 1 x 1 counters feeds end with)
                local tiny = tag:match("width%s*=%s*[\"']?1[\"'%s>/]") or tag:match("height%s*=%s*[\"']?1[\"'%s>/]")
                if u and not tiny then return u end
            end
        end
    end
    return nil
end

--- A feed's text → { title = the feed's own name or nil, items = { { title,
--- link, text, at } … } } (the feed's order, at most opts.max_items, each
--- text at most opts.max_text bytes), or nil, "not a feed".
function Feeds.parse(xml, opts)
    opts = opts or {}
    local max_items = opts.max_items or Feeds.MAX_ITEMS
    local max_text = opts.max_text or Feeds.MAX_TEXT
    if type(xml) ~= "string" then return nil, "not a feed" end
    xml = xml:gsub("^\239\187\191", "")
    local enc = xml:sub(1, 200):match("<%?xml[^>]-encoding%s*=%s*[\"']([^\"']+)[\"']")
    enc = enc and enc:lower() or "utf-8"
    if enc == "iso-8859-1" or enc == "windows-1252" or enc == "latin1" or enc == "iso-8859-15" or enc == "us-ascii" then
        xml = Feeds.fromLatin1(xml)
    else
        xml = Feeds.utf8(xml)
    end
    local atom = false
    local first = xml:find("<item[%s>]")
    if not first then
        first = xml:find("<entry[%s>]")
        atom = first ~= nil
    end
    local head = first and xml:sub(1, first - 1) or xml
    if not first and not (head:find("<rss[%s>]") or head:find("<feed[%s>]") or head:find("<rdf:RDF[%s>]") or head:find("<channel[%s>]")) then
        return nil, "not a feed"
    end
    local feed = { items = {} }
    local title = element(head, "title")
    if title then
        title = oneLine(unxml(title))
        if title ~= "" then feed.title = Feeds.cut(title, 80) end
    end
    local name = atom and "entry" or "item"
    local pos = first
    while pos and #feed.items < max_items do
        local block, _, nxt = element(xml, name, pos)
        if not block then break end
        local item = {}
        local t = element(block, "title")
        item.title = t and Feeds.cut(oneLine(unxml(t)), 300) or ""
        item.link = link(block)
        item.image = picture(block)
        item.text = body(block, max_text)
        for _i, dn in ipairs(atom and { "published", "updated" } or { "pubDate", "dc:date", "date", "published", "updated" }) do
            local raw = element(block, dn)
            local at = raw and Feeds.date(unxml(raw))
            if at then item.at = at; break end
        end
        if item.title == "" and item.text ~= "" then
            -- (a feed of posts without titles: the start of the text)
            item.title = Feeds.cut((item.text:match("^[^\n]+") or ""), 100)
        end
        if item.title ~= "" then feed.items[#feed.items + 1] = item end
        pos = xml:find("<" .. name .. "[%s>]", nxt)
    end
    return feed
end

return Feeds
