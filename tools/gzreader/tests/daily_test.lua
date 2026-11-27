-- The daily paper: feeds read into headlines and text (gzreader_feeds.lua),
-- an edition put together from them once a day (gzreader_daily.lua), and
-- what the screen shows of it (gzreader_dailyscreen.lua). No network: the
-- feeds' texts are given, and the HTTP layer is stood in for.
--   luajit daily_test.lua <repo> <tests lib> <work dir>
local REPO, LIB, WORK = arg[1], arg[2], arg[3]
local PLUGIN = REPO .. "/plugins/gzreader.koplugin"
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. package.path
os.execute("mkdir -p '" .. WORK .. "'")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function show(s) return (tostring(s):gsub("\n", "\\n")) end
local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

---------------------------------------------------------------- stand-ins
local dkjson = require("dkjson")
local logged = {}
package.preload["gettext"] = function() return function(t) return t end end
package.preload["gzreader_log"] = function()
    local function line(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logged[#logged + 1] = table.concat(parts, " ")
    end
    return { info = line, warn = line, err = line, enabled = true }
end
package.preload["gzreader_json"] = function()
    return { encode = dkjson.encode, decode = function(s) return (dkjson.decode(s)) end, list = function(t) return t end }
end
package.preload["datastorage"] = function() return { getSettingsDir = function() return WORK end, getDataDir = function() return WORK end } end
os.execute("mkdir -p '" .. WORK .. "/cache/gzreader-daily' && rm -f '" .. WORK .. "'/cache/gzreader-daily/*")
package.preload["ffi/util"] = function()
    return { template = function(s, ...)
        local args = { ... }
        return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
    end }
end
local shown, scheduled = {}, {}
package.preload["ui/uimanager"] = function()
    return {
        show = function(_s, w) shown[#shown + 1] = w end,
        close = function() end,
        nextTick = function(_s, fn) scheduled[#scheduled + 1] = fn end,
        setDirty = function() end,
    }
end
package.preload["ui/widget/infomessage"] = function() return { new = function(_s, o) o.kind = "info"; return o end } end
package.preload["ffi/blitbuffer"] = function() return { COLOR_BLACK = 0, COLOR_DARK_GRAY = 1 } end
package.preload["device"] = function() return { screen = { scaleBySize = function(_s, n) return n end, getWidth = function() return 600 end, getHeight = function() return 800 end }, isTouchDevice = function() return true end } end
package.preload["ui/font"] = function() return { getFace = function() return {} end } end
package.preload["ui/geometry"] = function() return { new = function(_s, o) return o end } end
local net = { usb = false, mode = "auto", runs = 0 }
package.preload["gzreader_net"] = function()
    return setmetatable({ run = function(fn, opts)
        net.runs = net.runs + 1
        net.last_opts = opts
        if net.mode == "off" and opts and opts.quiet then return end
        fn()
    end }, { __index = function(_t, k) if k == "usb" then return net.usb end end })
end
package.preload["gzreader_async"] = function()
    return { run = function(_api, fn, on_done, name, opts)
        net.async = { name = name, opts = opts }
        local ok, a, b = pcall(fn)
        if ok then on_done(a, b) else on_done(nil, a) end
    end }
end
package.preload["gzreader_gzip"] = function()
    return { available = function() return true end, inflate = function(s) return s:match("^GZ:(.*)$") end }
end
local http = { calls = {} }
package.preload["gzreader_api"] = function()
    return { rawRequest = function(method, url, opts)
        http.calls[#http.calls + 1] = { method = method, url = url, opts = opts }
        local answer = http.answers and http.answers[url]
        if not answer then return nil, nil, nil, "connection refused" end
        if answer.code and answer.code >= 400 then return answer.code, nil, {} end
        if not opts.sink then return answer.code or 200, answer.data, answer.headers or {} end
        local body = answer.body or ""
        for i = 1, #body, 1000 do
            if not opts.sink(body:sub(i, i + 999)) then return nil, nil, nil, "sink" end
        end
        opts.sink(nil)
        return answer.code or 200, nil, answer.headers or {}
    end }
end

local Feeds = require("gzreader_feeds")
local Daily = require("gzreader_daily")

---------------------------------------------------------------- feeds
print("== feeds read into headlines and text")
local RSS = [==[<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
<title>Example &amp; News</title><link>https://news.example.com/</link>
<atom:link href="https://news.example.com/rss" rel="self" type="application/rss+xml"/>
<image><title>logo</title><link>https://news.example.com/</link></image>
<item><title><![CDATA[First <b>story</b> &amp; more]]></title><link>https://news.example.com/1?a=1&amp;b=2</link>
<description>Short &lt;p&gt;summary&lt;/p&gt; here.</description>
<content:encoded><![CDATA[<p>Para one&nbsp;is here.</p><script>track("x")</script><ul><li>a</li><li class="x">b</li></ul>
<p>Para&#8217;s two &mdash; done.</p>]]></content:encoded>
<pubDate>Tue, 17 Nov 2026 07:05:00 -0500</pubDate></item>
<item><title>Second</title><guid>https://news.example.com/2</guid><description>Only this</description><dc:date>2026-11-16T23:00:00Z</dc:date></item>
<item><title>Third</title><guid isPermaLink="false">tag:3</guid><link>javascript:alert(1)</link><description></description></item>
<item><title></title><description>No title here. But a body.</description></item>
</channel></rss>]==]
local feed = Feeds.parse(RSS)
check(feed and feed.title == "Example & News" and #feed.items == 4, "RSS: the feed's name and its 4 stories … " .. tostring(feed and #feed.items))
local it = feed.items[1]
check(it.title == "First story & more", "a title: CDATA, tags out, entities read … " .. show(it.title))
check(it.link == "https://news.example.com/1?a=1&b=2", "its link, the & read … " .. tostring(it.link))
check(it.text == "Para one is here.\n\n\u{2022} a\n\u{2022} b\n\nPara\u{2019}s two \u{2014} done.",
    "the whole story (content:encoded) rather than the summary: paragraphs, a list, no script … " .. show(it.text))
check(it.at == 1794917100, "pubDate with -0500 as UTC seconds … " .. tostring(it.at))
check(feed.items[2].link == "https://news.example.com/2" and feed.items[2].at == 1794870000 and feed.items[2].text == "Only this",
    "no <link>: the guid when it's a permalink; dc:date read")
check(feed.items[3].link == nil, "a link that isn't http(s), a guid that isn't a permalink: no link")
check(feed.items[4].title == "No title here. But a body.", "a story without a title: named by the start of its text")

local ATOM = [==[<?xml version="1.0" encoding="utf-8"?><feed xmlns="http://www.w3.org/2005/Atom"><title type="text">Atom Example</title>
<link href="https://a.example.com/feed" rel="self"/><link href="https://a.example.com/"/>
<entry><title type="html">Hello &amp;amp; goodbye</title><link rel="replies" href="https://a.example.com/c"/><link rel="alternate" href="https://a.example.com/p1"/>
<published>2026-11-17T12:00:00.123+01:00</published><updated>2026-11-17T13:00:00Z</updated><summary type="text">1 &lt; 2 &amp; so on</summary></entry>
<entry><title>X</title><link href="https://a.example.com/p2"/><content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml"><p>In <em>XHTML</em>.</p></div></content></entry>
</feed>]==]
feed = Feeds.parse(ATOM)
check(feed and feed.title == "Atom Example" and #feed.items == 2, "Atom: 2 entries")
check(feed.items[1].title == "Hello & goodbye" and feed.items[1].link == "https://a.example.com/p1", "an entry's title and its alternate link (not replies, not self)")
check(feed.items[1].at == 1794913200, "published (+01:00, fractions) as UTC … " .. tostring(feed.items[1].at))
check(feed.items[1].text == "1 < 2 & so on", "a text summary keeps its < and & … " .. show(feed.items[1].text))
check(feed.items[2].text == "In XHTML.", "xhtml content as text … " .. show(feed.items[2].text))

local RDF = [==[<?xml version="1.0" encoding="ISO-8859-1"?><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/">
<channel><title>RDF caf]==] .. "\233" .. [==[</title><items><rdf:Seq/></items></channel>
<item rdf:about="https://r.example.com/1"><title>Caf]==] .. "\233 \147quoted\148" .. [==[</title><link>https://r.example.com/1</link><description>d</description></item></rdf:RDF>]==]
feed = Feeds.parse(RDF)
check(feed and #feed.items == 1 and feed.items[1].title == "Café \u{201C}quoted\u{201D}" and feed.title == "RDF café",
    "RSS 1.0 in Latin-1 / Windows-1252: read as UTF-8 … " .. show(feed and feed.items[1] and feed.items[1].title))
check(Feeds.parse("<html><body>Sign in</body></html>") == nil, "a web page isn't a feed")
check(Feeds.parse(nil) == nil and Feeds.parse("") == nil, "nothing isn't a feed")
feed = Feeds.parse("<rss><channel><title>Empty</title></channel></rss>")
check(feed and #feed.items == 0, "a feed with no stories is a feed")
local many = { "<rss><channel>" }
for i = 1, 30 do many[#many + 1] = "<item><title>T" .. i .. "</title><description>" .. string.rep("word ", 2000) .. "</description></item>" end
many[#many + 1] = "</channel></rss>"
feed = Feeds.parse(table.concat(many), { max_items = 7, max_text = 500 })
check(#feed.items == 7 and feed.items[7].title == "T7", "only the first max_items stories are read")
check(#feed.items[1].text <= 503 and feed.items[1].text:sub(-3) == "\u{2026}" and not feed.items[1].text:find("wor\u{2026}", 1, true),
    "a long text is cut at a word, with … (" .. #feed.items[1].text .. " bytes)")
check(Feeds.cut("aé" .. string.rep("é", 10), 4) == "aé\u{2026}", "a cut never splits a character … " .. Feeds.cut("aé" .. string.rep("é", 10), 4))
check(Feeds.utf8("ok \255\254 caf\195\169 \195") == "ok  café ", "bytes that aren't UTF-8 are dropped")
check(Feeds.entities("&lt;&#65;&#x42;&unknown;&nbsp;&hellip;") == "<AB&unknown; \u{2026}", "entities: named, decimal, hex; unknown ones stay")
check(Feeds.text("a<br>b<br/>c") == "a\nb\nc" and Feeds.text("plain\ntext") == "plain\ntext", "<br> is a new line; plain text keeps its lines")
check(Feeds.text("<p>one</p>\n<p>two</p><style>p{}</style><!-- c --><div>three</div>") == "one\n\ntwo\n\nthree", "paragraphs apart; style and comments out")
check(Feeds.date("Mon, 16 Nov 2026 23:00:00 GMT") == 1794870000 and Feeds.date("16 Nov 2026 18:00 EST") == 1794870000
    and Feeds.date("2026-11-16T23:00:00Z") == 1794870000 and Feeds.date("2026-11-16 23:00:00+00:00") == 1794870000,
    "dates: RFC 822 (GMT, EST, no weekday, no seconds) and ISO 8601")
check(Feeds.date("yesterday") == nil and Feeds.date("") == nil and Feeds.date("2026-13-40T00:00:00Z") == nil, "not a date: nil")
check(Feeds.timegm(1970, 1, 1) == 0 and Feeds.timegm(2000, 3, 1) == 951868800 and Feeds.timegm(2024, 2, 29, 12) == 1709208000, "days counted right (leap years)")

print("== a story's picture")
local function pic(inner) local f = Feeds.parse("<rss><channel><item><title>T</title>" .. inner .. "</item></channel></rss>"); return f.items[1].image end
check(pic('<media:content url="https://img.example.com/a.jpg?w=1&amp;h=2" medium="image"/>') == "https://img.example.com/a.jpg?w=1&h=2", "media:content (the & read)")
check(pic('<media:content url="https://v.example.com/a.mp4" type="video/mp4"/><media:thumbnail url="https://img.example.com/t.jpg"/>') == "https://img.example.com/t.jpg",
    "a video's media:content is passed over; media:thumbnail")
check(pic('<enclosure url="https://img.example.com/e.png" type="image/png" length="1"/>') == "https://img.example.com/e.png"
    and pic('<enclosure url="https://a.example.com/e.mp3" type="audio/mpeg"/>') == nil, "an image enclosure, not a podcast's")
check(pic('<description>&lt;p&gt;x&lt;/p&gt;&lt;img width="1" height="1" src="https://t.example.com/pixel.gif"&gt;&lt;img class="c" src="//img.example.com/d.jpg" alt=""&gt;</description>') == "https://img.example.com/d.jpg",
    "else the first picture in the text (not a 1 x 1 counter; //… gets https:)")
check(pic('<description><![CDATA[<img src="data:image/png;base64,AAAA"><img src=\'javascript:x\'>]]></description>') == nil and pic("<description>none</description>") == nil,
    "no picture, or one that isn't at an http(s) address: none")
check(Feeds.parse(ATOM).items[1].image == nil, "an Atom entry without one: none")

---------------------------------------------------------------- the edition
print("== an edition from the feeds")
local NOW = 1794920400 -- 2026-11-17 13:00 UTC
local function rss(name, stories)
    local out = { "<rss><channel><title>" .. name .. "</title>" }
    for _i, s in ipairs(stories) do
        out[#out + 1] = "<item><title>" .. s[1] .. "</title><link>https://" .. name .. ".example.com/" .. (s[3] or s[1]):gsub("%s", "-") .. "</link>"
            .. "<description>About " .. s[1] .. "</description>"
            .. (s[2] and ("<pubDate>" .. os.date("!%a, %d %b %Y %H:%M:%S GMT", NOW - s[2] * 3600) .. "</pubDate>") or "") .. "</item>"
    end
    out[#out + 1] = "</channel></rss>"
    return table.concat(out)
end
local bodies = {
    ["https://one.example.com/rss"] = rss("one", { { "A1", 1 }, { "A2", 2 }, { "A3", 3 }, { "A4", 4 }, { "A5", 5 }, { "A6", 6 }, { "A7", 7 } }),
    ["https://two.example.com/rss"] = rss("two", { { "B1", 1 }, { "A1", 2, "same-title" }, { "B old", 80 }, { "B2", 3 } }),
    ["https://slow.example.com/rss"] = rss("slow", { { "S last week", 200 }, { "S last month", 700 } }),
    ["https://undated.example.com/rss"] = rss("undated", { { "U1" }, { "U2" } }),
    ["https://page.example.com/rss"] = "<html>not a feed</html>",
}
local function fetch(url)
    if bodies[url] then return bodies[url] end
    return nil, "unreachable"
end
local feeds = {
    { url = "https://one.example.com/rss", name = "One", topic = "World" },
    { url = "https://two.example.com/rss", topic = "World" },
    { url = "https://slow.example.com/rss", name = "Slow", topic = "Science" },
    { url = "https://undated.example.com/rss", name = "Undated", topic = "Knitting" },
    { url = "https://page.example.com/rss", name = "Page", topic = "World" },
    { url = "https://down.example.com/rss", topic = "Books" },
}
local ed = Daily.build(feeds, NOW, fetch)
local function titles(section)
    local t = {}
    for _i, item in ipairs(section.items) do t[#t + 1] = item.title end
    return table.concat(t, ",")
end
check(ed and ed.day == "2026-11-17" and ed.at == NOW, "an edition for the day")
check(#ed.sections == 3 and ed.sections[1].topic == "World" and ed.sections[2].topic == "Science" and ed.sections[3].topic == "Knitting",
    "sections: GZreader's topics in their order, then your own; a topic with nothing isn't there")
check(titles(ed.sections[1]) == "A1,B1,A2,A3,B2,A4,A5", "the feeds of a topic take turns; a headline twice is shown once; " .. Daily.PER_FEED .. " a feed at most … " .. titles(ed.sections[1]))
check(not titles(ed.sections[1]):find("B old", 1, true), "a story older than a day and a half stays out")
check(titles(ed.sections[2]) == "S last week", "a feed that posts seldom: its newest story rather than nothing")
check(titles(ed.sections[3]) == "U1,U2", "stories without a date are taken as they come")
check(ed.sections[1].items[1].source == "One" and ed.sections[1].items[2].source == "two", "a story's source: the feed's name as you gave it, else its own")
check(#ed.failed == 2 and ed.failed[1] == "Page" and ed.failed[2] == "down.example.com", "feeds that failed are named (by name, else by site) … " .. table.concat(ed.failed, ","))
local e2, err2 = Daily.build({ feeds[5], feeds[6] }, NOW, fetch)
check(e2 == nil and err2 == "unreachable", "no feed answered: no edition (the old one stays)")
e2, err2 = Daily.build({}, NOW, fetch)
check(e2 == nil and err2 == "no feeds", "no feeds: no edition")
e2 = Daily.build({ feeds[2] }, 86400 * 3, fetch)
check(e2 and titles(e2.sections[1]):find("B old", 1, true), "a clock that ran down (1970): stories aren't judged by age")
local big = {}
for i = 1, 4 do big[#big + 1] = { url = "https://one.example.com/rss", name = "F" .. i, topic = "World" } end
bodies["https://one.example.com/rss"] = rss("one", { { "A1", 1 }, { "A2", 2 }, { "A3", 3 } })
local function fetchn(url)
    fetchn_count = (fetchn_count or 0) + 1 -- luacheck: ignore
    return (bodies[url]:gsub("<title>A", "<title>F" .. fetchn_count .. " A"):gsub("example%.com/", "example.com/F" .. fetchn_count .. "-"))
end
e2 = Daily.build(big, NOW, fetchn)
check(#e2.sections[1].items == Daily.PER_SECTION, "a section holds " .. Daily.PER_SECTION .. " stories at most … " .. #e2.sections[1].items)
local front
do
    local ed_mix = ed.order
    ed.order = nil
    front = Daily.front(ed, 4)
    ed.order = ed_mix
end
check(#front == 4 and front[1].title == "A1" and front[2].title == "S last week" and front[3].title == "U1" and front[4].title == "B1",
    "the front page of an edition without a mix (an older one): each section's first story, then their seconds")
;(function()
-- the stories mixed through the paper: every one once, a topic's own in their order, the same all day
local function mixTitles(e)
    local t = {}
    for _i, st in ipairs(Daily.ordered(e)) do t[#t + 1] = st.item.title end
    return table.concat(t, ",")
end
check(type(ed.order) == "table" and #ed.order == Daily.count(ed), "the edition is mixed when it's made: every story in it")
local seen_t, keeps_order, last_world = {}, true, 0
for _i, st in ipairs(Daily.ordered(ed)) do
    seen_t[st.item.title] = true
    if st.topic == "World" then
        if st.i < last_world then keeps_order = false end
        last_world = st.i
    end
end
local n_seen = 0
for _k in pairs(seen_t) do n_seen = n_seen + 1 end
check(n_seen == Daily.count(ed) and keeps_order, "…each story once, a topic's stories in their own order")
local again = { sections = ed.sections, order = Daily.mix(ed, ed.day) }
check(mixTitles(again) == mixTitles(ed) and Daily.front(ed, 4)[1].title == Daily.ordered(ed)[1].item.title,
    "…the same mix all day; the front page is the paper's first stories (" .. mixTitles(ed) .. ")")
local function runs(e)
    local n, last = 0, nil
    for _i, st in ipairs(Daily.ordered(e)) do if st.topic == last then n = n + 1 end; last = st.topic end
    return n
end
-- a paper with good news: it leads, and there's more of it in the first half
local function section(topic, n, tag)
    local items = {}
    for i = 1, n do items[i] = { title = tag .. i } end
    return { topic = topic, items = items }
end
local gp = { sections = { section("World", 8, "W"), section("Technology", 8, "T"), section("Science", 8, "S"), section("Good news", 8, "G") } }
local first_half, second_half, leads = 0, 0, 0
for d = 1, 40 do
    gp.order = Daily.mix(gp, "2026-12-" .. d)
    local list = Daily.ordered(gp)
    if list[1].topic == "Good news" then leads = leads + 1 end
    for k, st in ipairs(list) do
        if st.topic == "Good news" then if k <= 16 then first_half = first_half + 1 else second_half = second_half + 1 end end
    end
end
check(leads == 40 and first_half > second_half * 2, "good news leads the paper, and more of it comes in the first half ("
    .. first_half .. " to " .. second_half .. " over 40 days)")
gp.order = Daily.mix(gp, "2026-12-01")
check(runs(gp) == 0, "…never the same topic twice running while another has stories left")
local lone = { sections = { section("World", 3, "W") } }
lone.order = Daily.mix(lone, "x")
check(mixTitles(lone) == "W1,W2,W3", "one topic: its stories as they were")
-- an order that leaves stories out (an older one, or the AI's): those after, nothing twice
local part = { sections = gp.sections, order = { { s = 4, i = 2 }, { s = 4, i = 2 }, { s = 9, i = 1 }, { s = 1, i = 1 } } }
local pl = Daily.ordered(part)
check(#pl == 32 and pl[1].item.title == "G2" and pl[2].item.title == "W1" and pl[3].item.title == "W2",
    "an order with stories left out (or twice, or none such): the rest after it, each once")
end)()
check(#Daily.front(nil, 3) == 0 and #Daily.front(ed, 0) == 0 and #Daily.front(ed, 99) == Daily.count(ed), "the front page of nothing; never more than there is")
check(Daily.count(ed) == 10, "stories counted … " .. Daily.count(ed))

print("== the edition's pictures")
local PNG, JPG = "\137PNG\r\n\26\n" .. string.rep("x", 40), "\255\216\255\224" .. string.rep("y", 40)
check(Daily.pictureKind(PNG) == "png" and Daily.pictureKind(JPG) == "jpg" and Daily.pictureKind("GIF89a" .. string.rep("z", 20)) == "gif"
    and Daily.pictureKind("RIFF\1\2\3\4WEBPVP8 " .. string.rep("z", 20)) == "webp", "a picture is told by how it starts: PNG, JPEG, GIF, WebP")
check(Daily.pictureKind("<html>Not found</html>") == nil and Daily.pictureKind("<svg xmlns='x'></svg>") == nil and Daily.pictureKind(nil) == nil and Daily.pictureKind("\255\216\255") == nil,
    "an error page, an SVG, nothing: not a picture")
local ped = { day = "2026-11-17", sections = {
    { topic = "World", items = { { title = "W1", image = "https://img.example.com/w1.jpg?sig=SECRET" }, { title = "W2", image = "https://img.example.com/w2.jpg" }, { title = "W3" } } },
    { topic = "Science", items = { { title = "S1", image = "https://img.example.com/s1.png" }, { title = "S2", image = "https://img.example.com/page.html" } } } } }
local wanted = Daily.pictureWanted(ped)
check(#wanted == 4 and wanted[1].title == "W1" and wanted[2].title == "S1" and wanted[3].title == "W2", "pictures wanted in the front page's order, stories with one only")
local written, asked = {}, {}
local got = Daily.addPictures(ped, "/dir", function(url)
    asked[#asked + 1] = url
    if url:find("page.html", 1, true) then return "<html>no</html>" end
    if url:find("w2", 1, true) then return nil end
    return url:find("png", 1, true) and PNG or JPG
end, function(path, data) written[path] = data; return true end)
check(got == 2 and ped.sections[1].items[1].img == "2026-11-17-1.jpg" and ped.sections[2].items[1].img == "2026-11-17-2.png"
    and written["/dir/2026-11-17-1.jpg"] == JPG and written["/dir/2026-11-17-2.png"] == PNG, "each picture fetched is kept under the day and its place, by its kind")
check(ped.sections[1].items[2].img == nil and ped.sections[2].items[2].img == nil, "one that didn't come, or wasn't a picture: the story goes without")
check(not dkjson.encode(ped):find("SECRET", 1, true) and not dkjson.encode(ped):find("https:", 1, true), "the edition keeps no picture address")
local many_p = { day = "d", sections = { { topic = "World", items = {} } } }
for i = 1, 40 do many_p.sections[1].items[i] = { title = "T" .. i, image = "https://img.example.com/" .. i .. ".jpg" } end
check(Daily.addPictures(many_p, "/dir", function() return JPG end, function() return true end) == Daily.MAX_PICTURES, Daily.MAX_PICTURES .. " pictures an edition at most")
check(Daily.picturePath({ img = "../../etc/passwd" }) == nil and Daily.picturePath({ img = "none.jpg" }) == nil and Daily.picturePath({}) == nil,
    "a picture's file: only a plain name in the pictures' folder, only when it's there")

print("== pictures in an opened story")
check(Daily.MAX_PICTURES >= 20 and Daily.PAGE_PICTURES < Daily.MAX_PICTURES, "more stories get their picture than show one on the pages (" .. Daily.MAX_PICTURES .. " / " .. Daily.PAGE_PICTURES .. ")")
check(Daily.pagePicture({ img = "2026-11-18-1.jpg" }) and Daily.pagePicture({ img = "2026-11-18-" .. Daily.PAGE_PICTURES .. ".png" })
    and not Daily.pagePicture({ img = "2026-11-18-" .. (Daily.PAGE_PICTURES + 1) .. ".jpg" }) and not Daily.pagePicture({}) and not Daily.pagePicture({ img = "odd.jpg" }),
    "the first " .. Daily.PAGE_PICTURES .. " also show on the paper's pages; the rest in their opened story only")
local slow_p = { day = "d", sections = { { topic = "World", items = {} } } }
for i = 1, 10 do slow_p.sections[1].items[i] = { title = "T" .. i, image = "https://img.example.com/" .. i .. ".jpg" } end
local pic_tick = 0
check(Daily.addPictures(slow_p, "/dir", function() pic_tick = pic_tick + 70; return JPG end, function() return true end, 180, function() return pic_tick end) == 3
    and slow_p.sections[1].items[4].img == nil and slow_p.sections[1].items[4].image == nil, "fetching pictures stops when its time is up (180 s); the rest go without, and no address stays")
local Art = require("gzreader_article")
check(Art.leadImage('<html><head><meta charset="utf-8"><meta property="og:image" content="https://img.example.com/lead.jpg?w=1200&amp;h=630"></head><body></body></html>')
    == "https://img.example.com/lead.jpg?w=1200&h=630", "a page's own picture: og:image")
check(Art.leadImage("<head><META NAME='twitter:image' CONTENT='//img.example.com/t.png'></head>") == "https://img.example.com/t.png"
    and Art.leadImage('<head><meta content="https://img.example.com/first.jpg" property="og:image"/></head>') == "https://img.example.com/first.jpg",
    "… twitter:image, single quotes, either order, //… gets https:")
check(Art.leadImage('<head><meta property="og:image:width" content="1200"><meta property="og:title" content="https://x.example.com/a.jpg"></head>') == nil
    and Art.leadImage('<head><meta property="og:image" content="data:image/png;base64,AAAA"></head>') == nil and Art.leadImage("<html></html>") == nil and Art.leadImage(nil) == nil,
    "no picture named, or not at an http(s) address: none")
local og = { day = "d", sections = { { topic = "World", items = {
    { title = "No picture in the feed", text = "s", link = "https://w.example.com/a" },
    { title = "The feed's own", text = "s", link = "https://w.example.com/b", image = "https://img.example.com/feed.jpg" },
    { title = "Whole already", text = string.rep("long ", 800), link = "https://w.example.com/c" } } } } }
Daily.addFullText(og, function() return '<html><head><meta property="og:image" content="https://img.example.com/page.jpg"></head><body><p>x</p></body></html>', "text/html" end)
check(og.sections[1].items[1].image == "https://img.example.com/page.jpg" and og.sections[1].items[2].image == "https://img.example.com/feed.jpg" and og.sections[1].items[3].image == nil,
    "a story whose feed names no picture takes its page's; the feed's own is kept; a page that isn't fetched gives none")

print("== the paper's day")
local function at(h, m) return os.time{ year = 2026, month = 11, day = 17, hour = h, min = m or 0 } end
check(Daily.day(at(4, 59)) == "2026-11-16" and Daily.day(at(5, 0)) == "2026-11-17" and Daily.day(at(23, 59)) == "2026-11-17",
    "a new day's paper from 5 in the morning (reading past midnight keeps yesterday's)")

---------------------------------------------------------------- settings
print("== feeds chosen")
local saves = 0
local plugin = { store = {}, save = function() saves = saves + 1 end }
check(Daily.enabled(plugin) == false, "off until turned on")
local list = Daily.feeds(plugin)
local n_default = 0
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do if not f.off then n_default = n_default + 1 end end
check(#list == n_default and #list >= 6, "GZreader's own feeds: " .. #list .. " on to start with, " .. (#Daily.DEFAULT_FEEDS - n_default) .. " to tick")
local topics_ok, ids, https = true, {}, true
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do
    local known = false
    for _j, t in ipairs(Daily.TOPICS) do if t == f.topic then known = true end end
    if not known or ids[f.id] then topics_ok = false end
    ids[f.id] = true
    if not f.url:match("^https://") then https = false end
end
check(topics_ok and https, "each has an id of its own, a known topic and an https address")
do
    local good, on = {}, 0
    for _i, f in ipairs(Daily.DEFAULT_FEEDS) do
        if f.topic == "Good news" then good[#good + 1] = f.name; if not f.off then on = on + 1 end end
    end
    check(table.concat(good, ", ") == "Good News Network, Positive News, Reasons to be Cheerful" and on == 2
        and Daily.TOPICS[#Daily.TOPICS] == "Good news" and Daily.topicLabel("Good news") == "Good news",
        "a Good news section, last: Good News Network and Positive News on to start with, Reasons to be Cheerful to tick")
    local Fd = require("gzreader_feeds")
    check(Fd.withoutPostLine("A dog found its way home. The post A Dog Found Its Way Home appeared first on Good News Network.") == "A dog found its way home."
        and Fd.withoutPostLine("The post office reopened. The post was late.") == "The post office reopened. The post was late."
        and Fd.withoutPostLine("") == "" and Fd.withoutPostLine("The post X appeared first on Y.") == "",
        "the line WordPress feeds end each story with is left out; other sentences about a post stay")
    local parsed = Fd.parse('<rss version="2.0"><channel><title>G</title><item><title>Seeds</title><link>https://example.com/seeds</link>'
        .. '<description>&lt;p&gt;A million seeds are kept in the cold.&lt;/p&gt; &lt;p&gt;The post &lt;a href="https://example.com/seeds"&gt;Seeds&lt;/a&gt; appeared first on &lt;a href="https://example.com"&gt;Example&lt;/a&gt;.&lt;/p&gt;</description></item></channel></rss>')
    check(parsed and parsed.items and parsed.items[1] and parsed.items[1].text == "A million seeds are kept in the cold.", "…in a parsed feed too … " .. tostring(parsed and parsed.items and parsed.items[1] and parsed.items[1].text))
end
Daily.setDefaultOn(plugin, Daily.DEFAULT_FEEDS[1], false)
local optional
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do if f.off then optional = f end end
Daily.setDefaultOn(plugin, optional, true)
list = Daily.feeds(plugin)
local has_first, has_opt = false, false
for _i, f in ipairs(list) do
    if f.url == Daily.DEFAULT_FEEDS[1].url then has_first = true end
    if f.url == optional.url then has_opt = true end
end
check(not has_first and has_opt and #list == n_default, "one ticked off, an optional one ticked on")
check(Daily.normalizeUrl(" blog.example.com/feed ") == "https://blog.example.com/feed" and Daily.normalizeUrl("feed://x.example.com/a") == "https://x.example.com/a"
    and Daily.normalizeUrl("feed:https://x.example.com/a") == "https://x.example.com/a" and Daily.normalizeUrl("http://x.example.com/rss") == "http://x.example.com/rss",
    "an address as typed: no scheme, feed://, feed:https://, http://")
check(Daily.normalizeUrl("not an address") == nil and Daily.normalizeUrl("") == nil and Daily.normalizeUrl("ftp://x.example.com/a") == nil
    and Daily.normalizeUrl("https://localhost") == nil, "not an address: refused")
local e, why = Daily.addFeed(plugin, "blog.example.com/feed", " My blog ", "")
check(e and e.url == "https://blog.example.com/feed" and e.name == "My blog" and e.topic == nil, "a feed of your own added")
e, why = Daily.addFeed(plugin, "https://blog.example.com/feed")
check(e == nil and why == "have", "the same feed twice: refused")
e, why = Daily.addFeed(plugin, Daily.DEFAULT_FEEDS[2].url)
check(e == nil and why == "have", "one GZreader already has: refused")
e, why = Daily.addFeed(plugin, "nope")
check(e == nil and why == "bad", "not an address: refused")
list = Daily.feeds(plugin)
check(list[#list].url == "https://blog.example.com/feed" and list[#list].topic == Daily.OWN_TOPIC, "your feed is in the paper, under Your feeds")
plugin.store.daily.feeds[1].enabled = false
check(#Daily.feeds(plugin) == n_default, "a feed of yours unticked stays out")
plugin.store.daily.feeds[1].enabled = nil
local lines = Daily.parseFeedLines("\239\187\191# my feeds\r\nhttps://a.example.com/rss\r\n\r\nKnitting weekly | b.example.com/feed\nCrafts | Knit | https://c.example.com/atom.xml\nnot a link\n  # x\n")
check(#lines == 3 and lines[1].url == "https://a.example.com/rss" and lines[1].name == nil and lines[2].name == "Knitting weekly"
    and lines[3].topic == "Crafts" and lines[3].name == "Knit", "feeds.txt: an address, Name | address, Topic | Name | address; comments and junk skipped")
for i = 1, Daily.MAX_FEEDS + 2 do Daily.addFeed(plugin, "https://n" .. i .. ".example.com/feed") end
e, why = Daily.addFeed(plugin, "https://onemore.example.com/feed")
check(e == nil and why == "full" and #plugin.store.daily.feeds == Daily.MAX_FEEDS, "at most " .. Daily.MAX_FEEDS .. " feeds of your own")
check(Daily.site("https://www.example.com/a/b?key=secret") == "example.com" and Daily.site("https://feeds.example.org:8443/x") == "example.org", "a feed's site, for lists and the log")

---------------------------------------------------------------- fetching
print("== fetching a feed")
http.answers = {
    ["https://ok.example.com/rss?key=SECRET"] = { body = RSS },
    ["https://gz.example.com/rss"] = { body = "GZ:" .. RSS, headers = { ["content-encoding"] = "gzip" } },
    ["https://gone.example.com/rss"] = { code = 404 },
    ["https://huge.example.com/rss"] = { body = string.rep("x", Daily.MAX_BYTES + 5000) },
    ["https://blank.example.com/rss"] = { body = "" },
}
local body, ferr = Daily.fetch("https://ok.example.com/rss?key=SECRET")
check(body == RSS, "a feed's body, whole")
local call = http.calls[#http.calls]
check(call.method == "GET" and call.opts.log_url and not call.opts.log_url:find("SECRET", 1, true) and not call.opts.log_url:find("rss", 1, true)
    and call.opts.log_url:find("ok.example.com", 1, true), "the log gets the feed's site, never its address … " .. tostring(call.opts.log_url))
check(call.opts.headers["Accept-Encoding"] == "gzip" and call.opts.headers["User-Agent"]:find("GZreader", 1, true) and call.opts.timeouts[2] <= 60,
    "asked for compressed, as GZreader, with a time limit")
local sends_more = false
for k in pairs(call.opts.headers) do
    local name = k:lower()
    if name == "cookie" or name == "authorization" or name == "referer" then sends_more = true end
end
check(not sends_more and call.opts.body == nil and call.opts.raw_body == nil, "nothing about you is sent: no cookie, sign-in or body")
body = Daily.fetch("https://gz.example.com/rss")
check(body == RSS, "a compressed answer is unpacked")
body, ferr = Daily.fetch("https://gone.example.com/rss")
check(body == nil and ferr == "http_404", "a feed that's gone: http_404")
body, ferr = Daily.fetch("https://huge.example.com/rss")
check(body == nil and ferr == "too big", "a feed over " .. math.floor(Daily.MAX_BYTES / 1024) .. " KB isn't read to the end")
body, ferr = Daily.fetch("https://blank.example.com/rss")
check(body == nil and ferr == "empty", "an empty answer: no feed")
body, ferr = Daily.fetch("https://nowhere.example.com/rss")
check(body == nil and ferr == "unreachable", "a site that doesn't answer: unreachable")

---------------------------------------------------------------- once a day
print("== once a day")
-- (the feed's stories dated a few hours ago: with its fixed dates, "Second"
-- turned older than FRESH a day and a half after they were written)
local RECENT = RSS:gsub("2026%-11%-16T23:00:00Z", os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 3 * 3600))
    :gsub("Tue, 17 Nov 2026 07:05:00 %-0500", os.date("!%a, %d %b %Y %H:%M:%S GMT", os.time() - 2 * 3600))
http.answers["https://ok.example.com/rss?key=SECRET"] = { body = RECENT }
plugin = { store = { daily = { enabled = true, off = {}, feeds = { { url = "https://ok.example.com/rss?key=SECRET", name = "Mine" } } } }, save = function() saves = saves + 1 end }
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do Daily.setDefaultOn(plugin, f, false) end
os.remove(Daily.cachePath())
Daily.edition, Daily.loaded, Daily.tried_at, Daily.last_error = nil, nil, nil, nil
local changes = 0
Daily.listen("test", function() changes = changes + 1 end)
check(Daily.due(plugin) == true, "no edition yet: due")
logged = {}
local started = Daily.maybeRefresh(plugin)
check(started == true and net.last_opts.quiet == true, "asked for quietly (Wi-Fi off stays off)")
check(net.async and net.async.name == "daily paper" and net.async.opts.timeout >= 120, "fetched in the background, with a time limit")
check(Daily.edition and Daily.count(Daily.edition) == 4 and Daily.edition.sections[1].topic == Daily.OWN_TOPIC, "today's edition is there … " .. tostring(Daily.edition and Daily.count(Daily.edition)))
check(Daily.due(plugin) == false and Daily.maybeRefresh(plugin) == false, "today's is there: not due, not fetched again")
check(Daily.edition.pictures == 0 and Daily.edition.sections[1].items[1].img == nil, "no story had a picture: none fetched")
check(changes >= 2, "what shows the paper was told (a try began, an edition came)")
local kept = dkjson.decode(read(Daily.cachePath()))
check(kept and kept.day == Daily.edition.day and kept.sections[1].items[1].title == "First story & more", "kept on the Kindle (settings/gzreader-daily.json)")
local leaked = false
for _i, line in ipairs(logged) do if line:find("SECRET", 1, true) or line:find("/rss", 1, true) then leaked = true end end
check(not leaked and #logged >= 1, "the log names no feed address … " .. show(logged[#logged]))
Daily.edition, Daily.loaded = nil, nil
check(Daily.load() and Daily.load().day == kept.day, "read again after a restart")
-- tomorrow
local tomorrow = os.time() + 86400
check(Daily.due(plugin, tomorrow) == true, "the next day: due again")
http.answers["https://ok.example.com/rss?key=SECRET"] = nil
Daily.tried_at = nil
local before = Daily.edition
net.runs = 0
check(Daily.maybeRefresh(plugin, tomorrow) == true and Daily.edition == before and Daily.last_error == "unreachable", "a failed try keeps the edition there is")
check(Daily.maybeRefresh(plugin, tomorrow + 60) == false and Daily.maybeRefresh(plugin, tomorrow + Daily.RETRY - 1) == false, "after a failed try: not again for " .. (Daily.RETRY / 60) .. " minutes")
check(Daily.maybeRefresh(plugin, tomorrow + Daily.RETRY + 1) == true, "then again")
net.mode = "off"
Daily.tried_at = nil
local calls_before = #http.calls
Daily.maybeRefresh(plugin, tomorrow)
check(#http.calls == calls_before, "Wi-Fi turned off by you: nothing is fetched")
net.mode = "auto"
plugin.store.daily.enabled = nil
Daily.tried_at = nil
check(Daily.due(plugin, tomorrow) == false and Daily.maybeRefresh(plugin, tomorrow) == false, "the paper off: nothing is fetched")
plugin.store.daily.enabled = true
net.usb = true
calls_before = #http.calls
Daily.tried_at = nil
check(Daily.enabled(plugin) == true and Daily.maybeRefresh(plugin, tomorrow) == false and #http.calls == calls_before,
    "a Kindle without Wi-Fi: the paper can be on, but it doesn't fetch (the sync page brings it)")
local okr, errr
Daily.refresh(plugin, function(ok, err) okr, errr = ok, err end)
check(okr == false and errr == "usb" and Daily.why("usb"):find("sync", 1, true), "… and asking says it comes with a sync")
do
    -- what the sync page is told (outbox.json's daily)
    local ob = Daily.outbox(plugin)
    local ok_feeds = ob and #ob.feeds == #Daily.feeds(plugin) and ob.feeds[1].url and ob.feeds[1].name and ob.feeds[1].topic
    check(ok_feeds and ob.full == Daily.fullStories(plugin) and ob.per_feed == Daily.PER_FEED and ob.pages == Daily.USB_PAGES,
        "the sync page is told the feeds to fetch (address, name, topic), whole stories or not, how many")
    plugin.store.daily.enabled = nil
    check(Daily.outbox(plugin) == nil, "… nothing when the paper is off")
    plugin.store.daily.enabled = true
end
net.usb = false
plugin.store.daily.feeds = {}
Daily.refresh(plugin, function(ok, err) okr, errr = ok, err end)
check(okr == false and errr == "no feeds", "no feed ticked: said so")
for _i, code in ipairs({ "usb", "no feeds", "busy", "empty", "timeout", "unreachable", "whatever" }) do
    if type(Daily.why(code)) ~= "string" or Daily.why(code) == "" then check(false, "why: " .. code) end
end
check(true, "every way it can fail has its words")

---------------------------------------------------------------- the screen
print("== what the screen shows")
local Paper = require("gzreader_dailyscreen")
http.answers["https://ok.example.com/rss?key=SECRET"] = { body = RECENT }
plugin.store.daily.feeds = { { url = "https://ok.example.com/rss?key=SECRET", name = "Mine" } }
Daily.tried_at = nil
Daily.edition.day = ""
Daily.maybeRefresh(plugin)
check(Paper.dateText(os.time{ year = 2026, month = 11, day = 7, hour = 12 }) == "Saturday, November 7", "the date: Saturday, November 7")
check(Paper.timeText(os.time{ year = 2026, month = 11, day = 7, hour = 7, min = 5 }) == "7:05", "the time: 7:05")
check(Paper.statusText(plugin):match("^4 stories · %d+:%d%d$"), "today's paper: its stories and when it came … " .. Paper.statusText(plugin))
check(Paper.statusText(plugin, os.time() + 2 * 86400):match("^from %a+, %a+ %d+$"), "an older paper says which day it's from … " .. Paper.statusText(plugin, os.time() + 2 * 86400))
local stories = Paper.stories(Daily.edition)
check(#stories == 4 and stories[1].kicker == true and stories[2].kicker == false and stories[1].topic == Daily.OWN_TOPIC
    and stories[1].item.title == "First story & more", "the paper's stories in reading order, a section's first one marked for its heading")
do
local ks = Paper.stories({ sections = { { topic = "World", items = { { title = "w1" }, { title = "w2" } } }, { topic = "Science", items = { { title = "s1" } } } },
    order = { { s = 1, i = 1 }, { s = 2, i = 1 }, { s = 1, i = 2 } } })
check(#ks == 3 and ks[2].item.title == "s1" and ks[1].kicker and ks[2].kicker and ks[3].kicker,
    "mixed: the paper's order, each story with its topic over it when the topic changes")
end
check(#Paper.stories(nil) == 0, "no edition: no stories")
do
    -- colour: each section's heading, the nameplate's rule
    local ok_hex = true
    for _i, t in ipairs(Daily.TOPICS) do ok_hex = ok_hex and Paper.topicColor(t):match("^#%x%x%x%x%x%x$") ~= nil end
    check(ok_hex and Paper.topicColor("World") ~= Paper.topicColor("Science"), "each built-in section has its own colour")
    check(Paper.topicColor("Local news") == Paper.topicColor("Local news") and Paper.topicColor(Daily.OWN_TOPIC):match("^#%x+$")
        and Paper.topicColor(nil):match("^#%x+$"), "… your own sections one of a few, always the same one for a name")
    local Colour = require("gzreader_colour")
    local was = Colour.enabled
    Colour.enabled = function() return false end
    check(Paper.ink(Paper.MAST_COLOR) == nil, "a grey screen: no colour (black as before)")
    local BB = require("ffi/blitbuffer")
    BB.ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
    Colour.enabled = function() return true end
    local c = Paper.ink("#c92a2a")
    check(c and c.r == 0xc9 and c.g == 0x2a and c.b == 0x2a and c.a == 0xFF and Paper.ink("red") == nil, "a colour screen: the colour to paint with")
    BB.ColorRGB32 = nil
    Colour.enabled = was
    local src = read(PLUGIN .. "/gzreader_dailyscreen.lua")
    check(src:find("fgcolor = Paper.ink(Paper.topicColor(story.topic))", 1, true) and src:find("color = Paper.ink(Paper.MAST_COLOR)", 1, true)
        and select(2, src:gsub("paintRectRGB32", "")) >= 4, "the section headings and the nameplate's rule (page and Home) use them")
end
check(Paper.excerpt("One.\n\nTwo\nthree.", 100) == "One. Two three." and #Paper.excerpt(string.rep("word ", 300), 420) <= 423
    and Paper.excerpt(nil) == "", "how a story begins on the page: one paragraph, cut at a word")
check(Paper.columnCount(600, 167) == 2 and Paper.columnCount(1072, 300) == 2 and Paper.columnCount(824, 150) == 3 and Paper.columnCount(1860, 300) == 3,
    "columns: 2 on a 6-inch Kindle, 3 on a DX or a Scribe")
-- stories into columns
local function heights(list) return function(i) return list[i] end end
local function placedText(placed)
    local t = {}
    for _i, p in ipairs(placed) do t[#t + 1] = p.i .. "@" .. p.col .. ":" .. p.y end
    return table.concat(t, " ")
end
local placed, nxt = Paper.fill(1, 5, 2, 100, 10, heights({ 40, 40, 40, 40, 40 }))
check(placedText(placed) == "1@1:0 2@1:50 3@2:0 4@2:50" and nxt == 5, "columns fill top to bottom, left to right; what doesn't fit starts the next page … " .. placedText(placed))
placed, nxt = Paper.fill(5, 5, 2, 100, 10, heights({ 40, 40, 40, 40, 40 }))
check(placedText(placed) == "5@1:0" and nxt == 6, "the next page carries on from there, to the last story")
placed, nxt = Paper.fill(1, 3, 2, 100, 10, heights({ 300, 20, 20 }))
check(placedText(placed) == "1@1:0 2@2:0 3@2:30" and nxt == 4, "a story taller than a column gets one to itself (never an endless page)")
placed, nxt = Paper.fill(1, 2, 3, 100, 10, heights({ 100, 100 }))
check(placedText(placed) == "1@1:0 2@2:0" and nxt == 3, "a story that fills a column exactly")
placed, nxt = Paper.fill(4, 3, 2, 100, 10, heights({}))
check(#placed == 0 and nxt == 4, "nothing left: an empty page, nothing asked")
local every, seen_all, start, pages = {}, true, 1, 0
local hs = {}
for i = 1, 40 do hs[i] = 30 + (i * 37) % 90 end
while start <= 40 and pages < 50 do
    placed, nxt = Paper.fill(start, 40, 2, 400, 9, heights(hs))
    for _i, p in ipairs(placed) do
        every[#every + 1] = p.i
        if p.y > 0 and p.y + hs[p.i] > 400 then seen_all = false end
    end
    if nxt <= start then seen_all = false; break end
    start, pages = nxt, pages + 1
end
local in_order = #every == 40
table.sort(every)
for i, v in ipairs(every) do if v ~= i then in_order = false end end
check(in_order and seen_all, "40 stories over " .. pages .. " pages: each once, none past a column's foot")
placed, nxt = Paper.fill(1, 4, 2, 100, 10, heights({ 40, 80, 30, 50 }))
check(placedText(placed) == "1@1:0 3@1:50 2@2:0" and nxt == 4, "a story that doesn't fit waits for the next column's top; a shorter one after it fills the hole … " .. placedText(placed))
placed, nxt = Paper.fill(1, 3, 2, 100, 10, heights({ 70, 80, 30 }))
check(placedText(placed) == "1@1:0 2@2:0" and nxt == 3, "little room left under a story: nothing is moved up")
placed, nxt = Paper.fill(1, 2, 2, 100, 10, heights({ 40, 80 }))
check(placedText(placed) == "1@1:0 2@2:0" and nxt == 3, "the last story waiting is still placed")
placed, nxt = Paper.fill(1, 3, 1, 100, 10, heights({ 40, 80, 30 }))
check(placedText(placed) == "1@1:0" and nxt == 2, "in the last column nothing is passed over (the next page starts with it)")
-- the AI edition: a column filled exactly (Paper.fit)
do
    local function fitText(f)
        local t = {}
        for _i, v in ipairs(f) do t[#t + 1] = v.y .. "+" .. v.add end
        return table.concat(t, " ")
    end
    local f = Paper.fit(400, 10, { { h = 100, grow = 60 }, { h = 100, grow = 20 }, { h = 100, grow = 0 } })
    check(fitText(f) == "0+60 170+20 300+0", "a column's spare height goes to its pictures first, by how much each can grow … " .. fitText(f))
    f = Paper.fit(400, 10, { { h = 100, grow = 30 }, { h = 100, grow = 0 }, { h = 100, grow = 0 } })
    check(fitText(f) == "0+30 165+0 300+0" and f[3].y + 100 == 400, "what the pictures can't take is shared between the stories; the last ends at the foot … " .. fitText(f))
    f = Paper.fit(400, 10, { { h = 100 }, { h = 100 }, { h = 77 } })
    check(f[3].y + 77 == 400 and f[1].y == 0 and f[1].add == 0, "no pictures: the stories spread evenly, to the pixel")
    f = Paper.fit(400, 10, { { h = 150, grow = 500 } })
    check(fitText(f) == "0+250", "one story: its picture takes the rest")
    f = Paper.fit(400, 10, { { h = 150, grow = 0 } })
    check(fitText(f) == "0+0", "one story with no picture stays at the top")
    f = Paper.fit(100, 10, { { h = 80, grow = 40 }, { h = 80, grow = 40 } })
    check(fitText(f) == "0+0 90+0", "a column that's full already is left alone")
    local ends = true
    for seed = 1, 60 do
        local list, used = {}, 0
        for k = 1, 2 + seed % 4 do list[k] = { h = 40 + (seed * 13 + k * 29) % 70, grow = (seed + k) % 3 == 0 and (seed * 7) % 50 or 0 }; used = used + list[k].h end
        local col = used + 10 * (#list - 1) + (seed * 11) % 180
        local r = Paper.fit(col, 10, list)
        local last = r[#r].y + list[#list].h + r[#r].add
        if last ~= col then ends = false end
        for k = 2, #r do if r[k].y < r[k - 1].y + list[k - 1].h + r[k - 1].add + 10 then ends = false end end
    end
    check(ends, "60 columns: every one ends exactly at the foot, no story closer than the gap to the one above")
    local low, high = Paper.aiPicture(900, 2480)
    check(low == 306 and high == 720 and select(1, Paper.aiPicture(1000, 800)) == 176, "an article's picture: a third of the column wide to start, up to four fifths to fill (less on a short page)")
    local src = io.open(PLUGIN .. "/gzreader_dailyscreen.lua"):read("*a")
    check(src:find("Paper.fit(col_h, gap, hs)", 1, true) and src:find("if col < last_col or nxt <= self.n then", 1, true)
        and src:find("self:growPicture(built[list[k].i], f.add)", 1, true), "the AI edition fits every column that has stories after it")
end
-- Home's folded newspaper
local sizes = { shadow = 3, pad = 6, margin = 2, top = 2, gutter = 14, mast_h = 24, rules_h = 7, lead_h = 20, line_h = 16 }
local L = Paper.homeLayout(576, 130, sizes)
check(L.lead and L.rows == 3 and L.w == 576 - 3 - 4 and L.h == 130 - 3 - 2 and L.col_w * 2 + sizes.gutter <= L.inner_w,
    "Home's newspaper: the sheet with room for its shadow, the lead headline and 3 rows of two")
L = Paper.homeLayout(576, 90, sizes)
check(L.lead and L.rows == 1, "a lower row: the lead and one row")
L = Paper.homeLayout(576, 50, sizes)
check(not L.lead and L.rows == 0, "a very low row: the name alone")
-- a story opens as text that scrolls (the widget: emulator/daily_article.lua); what it shows and its buttons
local text1 = Paper.articleText(stories[1].item)
check(text1:find("Para one is here.", 1, true) and text1:find("^Mine · " .. os.date("%A, %B ", os.time() - 2 * 3600)),
    "a story opens as text, its source and day first")
check(table.concat(Paper.articleButtons(stories[1].item), ",") == "type,qr,close", "with Aa for its type, its link as a QR code, and ✕")
check(table.concat(Paper.articleButtons({ title = "T", text = "x" }), ",") == "type,close" and Paper.articleText({ title = "T", text = "x" }) == "x",
    "a story without a link: no QR code")
check(Paper.pulledDown({ direction = "south", pos = { x = 10, y = 5 } }) and not Paper.pulledDown({ direction = "south", pos = { x = 10, y = 5000 } })
    and not Paper.pulledDown({ direction = "west", pos = { x = 10, y = 5 } }) and not Paper.pulledDown(nil),
    "a swipe down from the top (on the paper or a story): the quick panel; lower down, or another way: not")
check(Paper.articleText({ title = "T", text = "short", link = "https://x.example.com/1", source = "S" }):find("only a summary", 1, true),
    "a short text says it's the feed's summary")
Daily.edition, Daily.loaded = nil, true
check(Paper.statusText(plugin) == "comes when Wi-Fi is on", "… and Home says when it comes")

print("== Settings → Accounts and services → Daily paper")
local home = { rows = { order = { "datetime", "featured" }, enabled = { datetime = true, featured = true } }, modules = {} }
local units = { datetime = 1, featured = 4, daily_paper = 3 }
local saved_home, redrawn = 0, 0
package.loaded["config/preset_store"] = {
    getSettings = function() return home end,
    saveSettings = function(_kind, cfg) home = cfg; saved_home = saved_home + 1 end,
}
local registered = {}
package.loaded["modules/filebrowser/patches/home/components/registry"] = {
    CAPACITY_UNITS = 10,
    get = function(id) return registered[id] end,
    sizeUnits = function(comp) return units[comp.id] end,
    totalUnits = function(enabled) local t = 0; for id, on in pairs(enabled) do if on then t = t + (units[id] or 0) end end return t end,
}
package.loaded["common/gz_view"] = { redrawHome = function() redrawn = redrawn + 1 end }
-- (main.lua registers Home's widget at start, without loading this module: Grimmory:installDailyPaper, run_tests.lua)
registered[Daily.ROW_ID] = { id = Daily.ROW_ID, label = "Daily paper", size = "m" }
plugin.store.daily.enabled = nil
local rows = Paper.settingsItems(plugin)
local function row(text) for _i, r in ipairs(rows) do if (r.text or (r.text_func and r.text_func())):find(text, 1, true) then return r end end end
check(row("Daily paper").checked_func() == false and row("Feeds").enabled_func() == false and row("Read the paper").enabled_func() == false,
    "off: the rest is greyed")
check(row("Daily paper").help_text:find("internet address", 1, true), "the switch says what a feed's site learns")
shown = {}
Paper.show(plugin)
check(shown[#shown] and shown[#shown].kind == "info" and shown[#shown].text:find("Settings → Accounts and services → Daily paper", 1, true), "opening the paper while it's off says where to turn it on")
saves = 0
check(Paper.onShelf(plugin) == false and Paper.shelfItem(plugin, {}, 300, 150) == nil, "off: no newspaper on the shelf")
row("Daily paper").callback()
check(Daily.enabled(plugin) and saves == 1 and home.rows.enabled.daily_paper ~= true and redrawn == 1,
    "turned on: kept, no row of its own on Home, Home drawn again")
check(Paper.onShelf(plugin) and row("On Home's bookshelf").checked_func() == true, "… the newspaper goes on Home's bookshelf")
row("On Home's bookshelf").callback()
check(not Paper.onShelf(plugin) and Daily.enabled(plugin) and plugin.store.daily.shelf == false and redrawn == 2, "unticked: off the shelf, the paper stays on")
row("On Home's bookshelf").callback()
check(Paper.onShelf(plugin) and plugin.store.daily.shelf == nil, "ticked again")
local pw, ph = Paper.shelfSize(300, 150)
check(ph == 240 and pw == 168, "on the shelf: a little lower than the books, a front page's shape … " .. pw .. "x" .. ph)
check(Paper.spineWidth(300) == 60 and Paper.spineWidth(100) == 24 and Paper.spineWidth(300) * 2 < pw and Paper.spineHeight(300) == 279 and Paper.spineHeight(300) > ph,
    "on its side: a fat folded paper (a fifth as thick as the books are tall), taller than its front page, nearly as tall as the books' room")
pw, ph = Paper.shelfSize(300, 400)
check(pw == 192, "never much wider than it is tall … " .. pw)
row("Headlines as a row on Home").callback()
check(home.rows.enabled.daily_paper == true and home.rows.order[#home.rows.order] == "daily_paper", "Headlines as a row on Home: the widget ticked (last)")
check(row("Headlines as a row on Home").checked_func() == true, "… and shown ticked")
home.rows.order = { "datetime", "featured", "strip", "quotes", "daily_paper" }
home.rows.enabled.daily_paper = false
row("Headlines as a row on Home").callback()
check(table.concat(home.rows.order, ",") == "datetime,featured,daily_paper,strip,quotes", "with books on Home, the paper goes above them (the bookshelf stays last) … " .. table.concat(home.rows.order, ","))
home.rows.order = { "daily_paper", "datetime", "featured", "strip" }
row("Headlines as a row on Home").callback()
row("Headlines as a row on Home").callback()
check(home.rows.order[3] == "daily_paper" and #home.rows.order == 4, "listed once, however often it's switched")
row("Headlines as a row on Home").callback()
check(home.rows.enabled.daily_paper == false and row("Headlines as a row on Home").checked_func() == false and Daily.enabled(plugin), "the row unticked: the paper stays on")
units.featured = 8
shown = {}
row("Headlines as a row on Home").callback()
check(home.rows.enabled.daily_paper == false and shown[#shown] and shown[#shown].text:find("no room", 1, true), "Home full: said so, nothing changed")
units.featured = 4
row("Headlines as a row on Home").callback()
check(home.rows.enabled.daily_paper == true, "the row on again")
row("Daily paper").callback()
check(not Daily.enabled(plugin) and home.rows.enabled.daily_paper == false and not Paper.onShelf(plugin), "the paper turned off: its row and the shelf's newspaper go too")
row("Daily paper").callback()
local feed_rows = Paper.feedItems(plugin)
local n_rows = #Daily.DEFAULT_FEEDS + #plugin.store.daily.feeds + 4
check(#feed_rows == n_rows and feed_rows[1].text == "World: " .. Daily.DEFAULT_FEEDS[1].name, "Feeds: GZreader's by topic, yours, Add a feed, Add from a browser, Add from feeds.txt, About feeds")
local was = feed_rows[1].checked_func()
feed_rows[1].callback()
check(feed_rows[1].checked_func() == (not was) and Daily.tried_at == nil, "a tick changes the feed; the paper is made again at the next look")
local mine = feed_rows[#Daily.DEFAULT_FEEDS + 1]
mine.callback()
local unticked = mine.checked_func()
mine.callback()
check(unticked == false and mine.checked_func() == true, "a feed of yours unticked, and ticked again")
check(mine.text == "Mine · ok.example.com" and not mine.text:find("SECRET", 1, true), "your feed is listed by name and site, not its address")
local fh = io.open(WORK .. "/feeds.txt", "wb")
fh:write("Tea | tea.example.com/feed\nhttps://ok.example.com/rss?key=SECRET\n")
fh:close()
plugin.feeds_file = WORK .. "/feeds.txt"
local added, where = Paper.importFile(plugin)
check(added == 1 and where == WORK .. "/feeds.txt" and plugin.store.daily.feeds[2].name == "Tea", "feeds.txt: the new one added, the one there already left")
plugin.feeds_file = WORK .. "/none.txt"
rawset(_G, "G_reader_settings", { readSetting = function() return WORK .. "/nohome/GZreader" end })
added, where = Paper.importFile(plugin)
check(added == nil and where:find("feeds.txt", 1, true), "no feeds.txt: says where to put one")
net.usb = true
rows = Paper.settingsItems(plugin)
local names = {}
for _i, r in ipairs(rows) do names[#names + 1] = r.text or (r.text_func and r.text_func()) or "?" end
local joined = table.concat(names, " | ")
check(rows[1].text == "Daily paper" and rows[1].help_text:find("sync page", 1, true) and joined:find("Feeds", 1, true)
    and joined:find("Whole stories", 1, true) and not joined:find("Pictures", 1, true) and not joined:find("Weather", 1, true)
    and not joined:find("QR code", 1, true) and not joined:find("Fetch now", 1, true) and rows[#rows].enabled == false
    and names[#names]:find("Comes with each sync", 1, true),
    "a Kindle without Wi-Fi: the paper's settings, without pictures, weather or the phone page; it comes with each sync (" .. joined .. ")")
net.usb = false

print("== a story's text from its own page")
local Article = require("gzreader_article")
local P1 = "The lighthouse keeper counted the ships again on Tuesday morning, and again there were seven where the harbour log had six. He wrote it down, as he had the day before, and went to put the kettle on while he thought about it."
local P2 = "Nobody on the island could say where the seventh had come from, though several people had a theory by lunchtime. The baker held that it was a trick of the light; the schoolmistress, that it was a visitor too shy to land."
local P3 = "By evening the council had sent a boat out, which came back with the news that the seventh ship was a rock. It had been there for some thousands of years, the boatman said, and nobody had counted it before."
local PAGE = [==[<!DOCTYPE html><HTML><head><title>Seven ships</title><style>p { color: red }</style>
<script>var x = "<p>not this, it is inside a script and quite long enough to count as a paragraph of text otherwise.</p>";</script></head>
<body><header><p>Example World: the news from the island, every day of the week, since 1904 and still going.</p></header>
<NAV><ul><li><a href="/">Home</a></li><li><a href="/world">World news from everywhere.</a></li></ul></NAV>
<main><article class="story"><header><h1>Seven ships seen</h1><p>By A. Reporter</p></header>
<p class="lead">]==] .. P1 .. [==[</p>
<p>Advertisement</p>
<figure><img src="https://img.example.com/a.jpg"><figcaption>The lighthouse, seen from the north on a clear day last week.</figcaption></figure>
<P>]==] .. P2 .. [==[ It&rsquo;s &ldquo;odd&rdquo;.</P>
<h2>What the council did</h2>
<p>]==] .. P3 .. [==[
<p>Unclosed paragraphs are read too, up to the next one, as browsers do with them.</p>
<ul><li>Short item</li><li>The harbour master said the log would be corrected by Friday at the latest.</li></ul>
<aside><p>Related: six other stories about ships that you might like to read after this one, with pictures.</p></aside>
<p>Share this</p><p>Sign up for our newsletter</p>
<form><p>Type your email address here to get the news from the island every single morning.</p></form>
<h3>More on this story</h3>
</article></main>
<footer><p>Copyright Example World. All rights reserved. Registered at the island post office as a newspaper.</p></footer></body></HTML>]==]
local story = Article.extract(PAGE, "text/html; charset=utf-8")
check(story and story:find(P1, 1, true) and story:find(P2 .. " It\u{2019}s \u{201C}odd\u{201D}.", 1, true) and story:find(P3, 1, true),
    "the article's paragraphs, in order, entities read")
check(story:find("\n\nWhat the council did\n\n", 1, true) and story:find("Unclosed paragraphs are read too", 1, true)
    and story:find("\u{2022} The harbour master said", 1, true), "its sub-headings, unclosed paragraphs, and list items that are sentences")
local clean = true
for _i, not_story in ipairs({ "not this", "since 1904", "World news from everywhere", "Advertisement", "seen from the north", "Related:", "Share this", "Sign up",
        "Type your email", "More on this story", "All rights reserved", "Short item", "By A. Reporter", "color: red" }) do
    if story:find(not_story, 1, true) then clean = false; print("    still there: " .. not_story) end
end
check(clean, "none of the page's furniture: script, style, header, menu, ad line, caption, sidebar, share and sign-up lines, form, footer")
check(not story:find("\n\n\n", 1, true) and not story:find("<", 1, true) and story:sub(1, #P1) == P1, "plain paragraphs, an empty line between")
local teaser, why_not = Article.extract("<html><body><article><p>" .. P1 .. "</p><p>Subscribe to read the rest.</p></article></body></html>")
check(teaser == nil and why_not == "no article", "a paywall's teaser isn't an article: nothing (the feed's summary stays)")
check(Article.extract('<html><body><div id="root"></div><script src="/app.js"></script></body></html>') == nil, "a page built by scripts: nothing")
check(Article.extract("") == nil and Article.extract(nil) == nil and Article.extract("%PDF-1.4 binary") == nil and select(2, Article.extract("{\"json\":true}")) == "not html",
    "not a web page: nothing")
local plain = Article.extract("<html><body><div><p>" .. P1 .. "</p><div><p>" .. P2 .. "</p></div><p>" .. P3 .. "</p><p>Read more: other things</p></div></body></html>")
check(plain == P1 .. "\n\n" .. P2 .. "\n\n" .. P3, "a page without <article>: the body's paragraphs")
local two = Article.extract("<html><body><article><p>A short card about something else on the page.</p></article><article><p>" .. P1 .. "</p><p>" .. P2 .. "</p><p>" .. P3 .. "</p></article></body></html>")
check(two == P1 .. "\n\n" .. P2 .. "\n\n" .. P3, "several <article>s: the one with the most text")
local latin = Article.extract("<html><head><meta charset=\"iso-8859-1\"></head><body><p>" .. P1 .. " Caf\233.</p><p>" .. P2 .. "</p><p>" .. P3 .. "</p></body></html>")
check(latin and latin:find("Café.", 1, true), "a Latin-1 page read as UTF-8 (from its meta tag; or from the answer's content type)")
check(Article.extract("<html><body><p>" .. P1 .. " Caf\233.</p><p>" .. P2 .. "</p><p>" .. P3 .. "</p></body></html>", "text/html; charset=ISO-8859-1"):find("Café.", 1, true), "… the content type")
-- a page with an "Embed" box, folded captions and a byline over the story (the owner's NPR story, 2026-11-25)
do
    local embed = '&lt;iframe src="https://www.example.com/player/embed/1/2" width="100%" height="290" frameborder="0" scrolling="no" title="embedded audio player"&gt;'
    local page = "<html><body><article><p>News</p><p>By</p><p>Ana Writer</p><p>The bakery where everything is free</p>"
        .. "<ul><li><b>Embed</b> <code>" .. embed .. "</code></li></ul>"
        .. "<p>A baker walks up to the table during the monthly gathering in the park. Sam Photo/Example News hide caption</p>"
        .. "<p>" .. P1 .. "</p><p>Short but a sentence.</p><p>" .. P2 .. "</p><p>The menu included scones. Sam Photo/Example News toggle caption</p><p>" .. P3 .. "</p></article></body></html>"
    local got = Article.extract(page)
    check(got and not got:find("iframe", 1, true) and not got:find("Embed", 1, true), "an Embed box's code isn't part of the story")
    check(got and not got:find("hide caption", 1, true) and not got:find("toggle caption", 1, true), "folded picture captions are left out")
    check(got and got:sub(1, #P1) == P1 and got:find("Short but a sentence.", 1, true) and got:find(P3, 1, true),
        "the section, By and the writer's name over the story are left out; short sentences inside it stay")
    check(Article.isMarkup('<iframe src="x">') and Article.isMarkup("see </div> here") and Article.isMarkup('<a href="https://example.com">')
        and not Article.isMarkup("Prices rose 3 < 4 percent, and x > y.") and not Article.isMarkup("He said <no> twice."), "markup is told from prose with a < in it")
    local kept = "News\n\nBy\n\nThe bakery where everything is free\n\n\u{2022} Embed " .. '<iframe src="https://www.example.com/e" width="100%">' .. "\n\n" .. P1 .. "\n\n" .. P2
    check(Article.tidyText(kept, "The bakery where everything is free") == P1 .. "\n\n" .. P2, "a story kept by an earlier build is tidied when it's shown, its headline said again too")
    check(Article.tidyText("Only a title line", nil) == "Only a title line" and Article.tidyText("", nil) == "" and Article.tidyText(nil) == nil, "never everything: a one-line text stays")
    local Paper2 = require("gzreader_dailyscreen")
    local shown = Paper2.articleText({ title = "T", text = kept, full = true })
    local feed_only = Paper2.articleText({ title = "T", text = "News\n\n" .. P1 })
    check(not shown:find("iframe", 1, true) and shown:find(P1, 1, true) and feed_only:find("News", 1, true), "an opened story shows it tidied; a feed's own text is left as the feed wrote it")
end
check(select(2, Article.extract("<html>" .. string.rep("x", Article.MAX_HTML) .. "</html>")) == "too big", "a page over " .. (Article.MAX_HTML / 1024 / 1024) .. " MB isn't read")
check(Article.extract("<html><body><p>" .. P1 .. "</p><p>" .. P1 .. "</p><p>" .. P2 .. "</p><p>" .. P3 .. "</p></body></html>") == P1 .. "\n\n" .. P2 .. "\n\n" .. P3, "a paragraph the page has twice is kept once")

print("== whole stories with the paper")
local long_text = string.rep("This feed carries the whole story already. ", 80)
local fed = { day = "d", sections = {
    { topic = "World", items = { { title = "Short", text = "One line.", link = "https://w.example.com/short?utm=SECRET" },
        { title = "Whole", text = long_text, link = "https://w.example.com/whole" }, { title = "No link", text = "x" } } },
    { topic = "Science", items = { { title = "Paywall", text = "A teaser of fair length from the feed itself.", link = "https://s.example.com/paywall" },
        { title = "Gone", text = "y", link = "https://s.example.com/gone" }, { title = "Shorter page", text = string.rep("Feed text. ", 200), link = "https://s.example.com/shorter" } } } } }
local page_asks = {}
local function page(url)
    page_asks[#page_asks + 1] = url
    if url:find("/short", 1, true) and not url:find("shorter", 1, true) then return PAGE, "text/html" end
    if url:find("paywall", 1, true) then return "<html><body><article><p>" .. P1 .. "</p><p>Subscribe to read the rest.</p></article></body></html>", "text/html" end
    if url:find("shorter", 1, true) then return "<html><body><p>" .. P1 .. "</p><p>" .. P2 .. "</p><p>" .. P3 .. "</p><p>" .. P1 .. " Again, differently.</p><p>" .. P2 .. " Again.</p><p>" .. P3 .. " Again.</p><p>" .. P1 .. " Thrice.</p><p>" .. P2 .. " Thrice.</p><p>" .. P3 .. " Thrice.</p></body></html>", "text/html" end
    if url:find("gone", 1, true) then error("socket closed") end
    return nil, "unreachable"
end
local filled, asked_n = Daily.addFullText(fed, page)
check(filled == 1 and fed.sections[1].items[1].full == true and fed.sections[1].items[1].text:find(P3, 1, true), "a story with a line from its feed gets its page's article")
check(fed.sections[1].items[2].text == long_text and fed.sections[1].items[2].full == nil and not table.concat(page_asks, " "):find("/whole", 1, true),
    "a story the feed carries whole: its page isn't fetched")
check(fed.sections[2].items[1].text:find("^A teaser") and fed.sections[2].items[1].full == nil and fed.sections[2].items[2].text == "y",
    "a paywall, a page that fails: the feed's text stays")
check(fed.sections[2].items[3].full == nil and fed.sections[2].items[3].text:find("^Feed text"), "a page's text that isn't clearly longer than the feed's: the feed's stays")
check(asked_n == 4 and #page_asks == 4 and page_asks[1]:find("/short", 1, true) and page_asks[2]:find("paywall", 1, true), "pages asked for in the front page's order; none for a story without a link … " .. asked_n)
local tick_now = 0
local slow = { day = "d", sections = { { topic = "World", items = {} } } }
for i = 1, 60 do slow.sections[1].items[i] = { title = "T" .. i, text = "s", link = "https://w.example.com/short" .. i } end
filled, asked_n = Daily.addFullText(slow, function() tick_now = tick_now + 100; return PAGE, "text/html" end, 300, function() return tick_now end)
check(asked_n == 3 and filled == 3 and slow.sections[1].items[4].full == nil, "it stops when its time is up (300 s): the rest keep their summaries")
filled, asked_n = Daily.addFullText(slow, function() return PAGE, "text/html" end, 300, function() return 0 end)
check(asked_n == Daily.MAX_FULL - 0 and filled == Daily.MAX_FULL - 3 + 0 or asked_n == Daily.MAX_FULL, Daily.MAX_FULL .. " pages an edition at most … " .. asked_n)
local huge = { day = "d", sections = { { topic = "World", items = { { title = "Long", text = "s", link = "https://w.example.com/long" } } } } }
Daily.addFullText(huge, function()
    local t = { "<html><body>" }
    for i = 1, 400 do t[#t + 1] = "<p>" .. P1 .. " Paragraph number " .. i .. " of this very long story.</p>" end
    return table.concat(t) .. "</body></html>", "text/html"
end)
check(huge.sections[1].items[1].full and #huge.sections[1].items[1].text <= Daily.MAX_TEXT + 3 and huge.sections[1].items[1].text:sub(-3) == "\u{2026}",
    "a very long story is cut at " .. Daily.MAX_TEXT .. " bytes, at a word")
-- through the paper's own fetch
plugin = { store = { daily = { enabled = true, pictures = false, feeds = { { url = "https://ok.example.com/rss?key=SECRET", name = "Mine" } } } }, save = function() end }
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do Daily.setDefaultOn(plugin, f, false) end
http.answers["https://ok.example.com/rss?key=SECRET"] = { body = '<rss><channel><item><title>Seven ships</title><link>https://news.example.com/seven?ref=SECRET</link><description>One line.</description></item></channel></rss>' }
http.answers["https://news.example.com/seven?ref=SECRET"] = { body = "GZ:" .. PAGE, headers = { ["content-encoding"] = "gzip", ["content-type"] = "text/html; charset=utf-8" } }
Daily.edition, Daily.loaded, Daily.tried_at = nil, true, nil
logged = {}
Daily.refresh(plugin)
local whole = Daily.edition and Daily.edition.sections[1].items[1]
check(whole and whole.full and whole.text:find(P2, 1, true) and Daily.edition.full == 1 and Daily.edition.pages == 1, "fetched with the day's paper (a compressed page unpacked), and counted")
local scall
for _i, c in ipairs(http.calls) do if c.url:find("news.example.com/seven", 1, true) then scall = c end end
check(scall and scall.opts.log_url:find("news.example.com", 1, true) and scall.opts.log_url:find("(story)", 1, true) and not scall.opts.log_url:find("SECRET", 1, true)
    and not scall.opts.log_url:find("seven", 1, true) and scall.opts.timeouts[2] <= 30, "the log gets the story's site, never its address; with a time limit")
leaked = false
for _i, line in ipairs(logged) do if line:find("SECRET", 1, true) or line:find("/seven", 1, true) then leaked = true end end
check(not leaked and logged[#logged]:find("1 whole stories from 1 pages", 1, true), "… and the day's line counts them … " .. show(logged[#logged]))
http.answers["https://news.example.com/seven?ref=SECRET"] = { body = "%PDF-1.4", headers = { ["content-type"] = "application/pdf" } }
Daily.edition.day = ""
Daily.refresh(plugin)
check(Daily.edition.sections[1].items[1].text == "One line." and not Daily.edition.sections[1].items[1].full, "a link that isn't a web page: the summary stays")
plugin.store.daily.full = false
local before_calls = #http.calls
Daily.edition.day = ""
Daily.refresh(plugin)
local story_calls = 0
for i = before_calls + 1, #http.calls do if http.calls[i].url:find("news.example.com", 1, true) then story_calls = story_calls + 1 end end
check(story_calls == 0 and not Daily.fullStories(plugin), "Whole stories off: no page is asked for")
plugin.store.daily.full = nil
rows = Paper.settingsItems(plugin)
check(row("Whole stories").checked_func() == true and row("Whole stories").help_text:find("paywall", 1, true) and row("Whole stories").help_text:find("internet address", 1, true),
    "Settings → Accounts and services → Daily paper → Whole stories: on, and says what it does, what it can't, and who sees the Kindle")
row("Whole stories").callback()
check(plugin.store.daily.full == false and row("Whole stories").checked_func() == false, "unticked")
row("Whole stories").callback()
check(plugin.store.daily.full == nil, "ticked again")
check(Paper.articleText({ title = "T", text = "x", link = "https://x.example.com/1", full = true }):find("From the story's own page", 1, true), "a whole story says where its text is from")
check(Daily.MAX_TEXT >= 12000, "a feed that carries whole stories is no longer cut at 4,000 bytes")

print("== a story's picture, whole")
local fw, fh = Paper.fitSize(1200, 800, 600, 500)
check(fw == 600 and fh == 400, "a big picture: as wide as the column, its shape kept")
fw, fh = Paper.fitSize(800, 1600, 600, 500)
check(fw == 250 and fh == 500, "a tall one: never taller than its room")
fw, fh = Paper.fitSize(100, 50, 600, 500)
check(fw == 200 and fh == 100, "a small one: at most twice its size (not blown up to the column)")
local dsp = read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(dsp:find("Paper.pictureWhole(pic_path, inner", 1, true) and dsp:find("Daily().pictures(self.plugin) and Daily().picturePath(it)", 1, true),
    "an opened story shows its picture under the headline (when Pictures is on and it has one)")
check(dsp:find("(feature or D.pagePicture(story.item)) and D.picturePath(story.item)", 1, true), "the pages show only the first few (the AI edition: every story's)")

print("== a story's type")
plugin = { store = { daily = { enabled = true } }, save = function() saves = saves + 1 end }
local sf = Paper.storyFont(plugin)
check(sf.face.id == "serif" and sf.size == 12 and sf.spacing.id == "normal" and sf.face.regular == "NotoSerif-Regular.ttf", "as it comes: Serif, 12, Normal spacing")
saves = 0
local rebuilt = 0
Paper.story = { rebuild = function() rebuilt = rebuilt + 1 end }
check(Paper.setStoryFont(plugin, "size", 16) == true and Paper.storyFont(plugin).size == 16 and saves == 1 and rebuilt == 1, "a size chosen: kept, and the open story set again")
check(Paper.setStoryFont(plugin, "size", 16) == false and saves == 1 and rebuilt == 1, "the same again: nothing to do")
Paper.setStoryFont(plugin, "size", 999)
check(Paper.storyFont(plugin).size == Paper.SIZE_MAX, "never bigger than " .. Paper.SIZE_MAX)
Paper.setStoryFont(plugin, "size", -4)
check(Paper.storyFont(plugin).size == Paper.SIZE_MIN, "never smaller than " .. Paper.SIZE_MIN)
check(Paper.setStoryFont(plugin, "face", "sans") and Paper.storyFont(plugin).face.bold == "NotoSans-Bold.ttf" and Paper.setStoryFont(plugin, "spacing", "wide")
    and Paper.storyFont(plugin).spacing.em > 0.3, "a typeface and a line spacing chosen")
check(Paper.setStoryFont(plugin, "face", "comic") == false and Paper.setStoryFont(plugin, "spacing", "huge") == false and Paper.setStoryFont(plugin, "colour", "red") == false
    and Paper.storyFont(plugin).face.id == "sans", "one that isn't offered changes nothing")
plugin.store.daily.font = { face = "gone", size = "x", spacing = 7 }
check(Paper.storyFont(plugin).face.id == "serif" and Paper.storyFont(plugin).size == 12 and Paper.storyFont(plugin).spacing.id == "normal", "kept values that make no sense: as it comes")
Paper.story = { closed = true, rebuild = function() rebuilt = rebuilt + 100 end }
Paper.setStoryFont(plugin, "size", 14)
check(rebuilt < 100, "no story open: none is set again")
Paper.story = nil
local ids = {}
for _i, c in ipairs(Paper.FACES) do ids[#ids + 1] = Paper.faceLabel(c.id) end
check(table.concat(ids, ",") == "Serif,Sans,Classic,Typewriter", "four typefaces: " .. table.concat(ids, ", "))
local fonts_ok = true
for _i, c in ipairs(Paper.FACES) do
    for _j, file in ipairs({ c.regular, c.bold }) do
        local found = false
        for _k, dir in ipairs({ "noto", "freefont", "droid" }) do
            local f = io.open(REPO .. "/fonts/" .. dir .. "/" .. file, "rb") or io.open((arg[4] or "") .. "/fonts/" .. dir .. "/" .. file, "rb")
            if f then f:close(); found = true end
        end
        if not found and arg[4] then fonts_ok = false; print("    missing font: " .. file) end
    end
end
check(fonts_ok, "each is a font GZreader ships" .. (arg[4] and "" or " (not checked: no KOReader tree given)"))
local trows = Paper.typeRows(plugin)
check(#trows == 3 and trows[1][1].text == "A\u{2212}" and trows[1][2].text == "Size 14" and trows[1][2].enabled == false and trows[1][3].text == "A+"
    and #trows[2] == 4 and trows[2][1].on == true and #trows[3] == 3 and trows[3][2].on == true, "the Aa box: A−, the size, A+; the typefaces; the spacings; the chosen ones marked")
check(trows[1][3].run() == true and Paper.storyFont(plugin).size == 15 and trows[2][2].run() == true and Paper.storyFont(plugin).face.id == "sans", "A+ makes it one bigger; a typeface's button chooses it")
Paper.setStoryFont(plugin, "size", Paper.SIZE_MAX)
check(Paper.typeRows(plugin)[1][3].enabled == false and Paper.typeRows(plugin)[1][1].enabled == true, "at the biggest, A+ is greyed")
rows = Paper.settingsItems(plugin)
local frows = Paper.fontItems(plugin)
check(row("Story text") and #frows == 3 and frows[1].text_func() == "Typeface: Sans" and frows[2].text_func() == "Size: " .. Paper.SIZE_MAX and frows[3].text_func() == "Line spacing: Normal",
    "Settings → Daily paper → Story text: typeface, size, line spacing")
frows[2].sub_item_table[4].callback()
check(Paper.storyFont(plugin).size == 12 and frows[2].sub_item_table[4].checked_func() == true and frows[2].sub_item_table[5].checked_func() == false, "a size picked there")
frows[1].sub_item_table[3].callback()
frows[3].sub_item_table[1].callback()
check(Paper.storyFont(plugin).face.id == "classic" and Paper.storyFont(plugin).spacing.id == "tight", "a typeface and a spacing picked there")
local dsrc = read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(dsrc:find("line_height = font.spacing.em", 1, true) and dsrc:find("face(font.face.regular, font.size", 1, true) and dsrc:find("self.key_events.ShowType = { { k.type } }", 1, true),
    "the story is set in the type chosen; a key opens the box on a Kindle with keys")
;(function()
    local kb, k4 = Paper.typeKeys(true), Paper.typeKeys(false)
    check(kb.type == "AA" and kb.panel == "Menu", "a Kindle with a keyboard: the Aa key is the type box, Menu the quick panel")
    check(k4.type == "Menu" and k4.panel == nil, "keys but no keyboard (no Aa key): Menu stays the type box")
    check(dsrc:find("if k.panel then self.key_events.KeyPanel = { { k.panel } } end", 1, true) and dsrc:find("if k.panel then self.key_events.GzPanel = { { k.panel } } end", 1, true)
        and dsrc:find('function PaperPage:onGzPanel() return Paper.openPanel(self.plugin, "Menu") end', 1, true)
        and dsrc:find('function ArticleView:onKeyPanel() return Paper.openPanel(self.plugin, "Menu") end', 1, true)
        and dsrc:find("Paper.typeKeys(Device:hasKeyboard())", 1, true), "the paper's pages and a story both take their keys from it")
    local shown = 0
    local was = package.loaded["gzreader_panel"]
    package.loaded["gzreader_panel"] = { show = function() shown = shown + 1 end }
    check(Paper.openPanel({}, "Menu") == true and shown == 1, "Menu's handler shows the quick panel")
    package.loaded["gzreader_panel"] = was
end)()

print("== the type of the paper's own pages")
plugin = { store = { daily = { enabled = true } }, save = function() saves = saves + 1 end }
local pf = Paper.frontFont(plugin)
check(pf.face.id == "serif" and pf.size.id == "normal" and pf.scale == 1, "as it comes: Serif, Normal")
saves = 0
local reloaded = 0
Paper.instance = { reload = function() reloaded = reloaded + 1 end }
check(Paper.setFrontFont(plugin, "size", "large") == true and Paper.frontFont(plugin).scale == 1.2 and saves == 1 and reloaded == 1, "Large chosen: kept, and the open paper laid out again")
check(Paper.setFrontFont(plugin, "size", "large") == false and reloaded == 1, "the same again: nothing to do")
check(Paper.setFrontFont(plugin, "face", "sans") == true and Paper.frontFont(plugin).face.regular == "NotoSans-Regular.ttf" and reloaded == 2, "a typeface chosen")
check(Paper.setFrontFont(plugin, "size", "huge") == false and Paper.setFrontFont(plugin, "face", "comic") == false and Paper.setFrontFont(plugin, "spacing", "wide") == false
    and Paper.frontFont(plugin).size.id == "large", "one that isn't offered changes nothing")
check(Paper.storyFont(plugin).face.id == "serif" and Paper.storyFont(plugin).size == 12, "the pages' type and a story's are separate choices")
plugin.store.daily.front = { face = 3, size = "gone" }
check(Paper.frontFont(plugin).face.id == "serif" and Paper.frontFont(plugin).scale == 1, "kept values that make no sense: as it comes")
Paper.instance = { closed = true, reload = function() reloaded = reloaded + 100 end }
Paper.setFrontFont(plugin, "size", "small")
check(reloaded < 100 and Paper.frontFont(plugin).scale < 1, "no paper open: none is laid out again")
Paper.instance = nil
local prows = Paper.frontRows(plugin)
local sizes_t = {}
for _i, b in ipairs(prows[1]) do sizes_t[#sizes_t + 1] = (b.on and "*" or "") .. b.text end
check(table.concat(sizes_t, ",") == "*Small,Normal,Large,Larger" and #prows[2] == 4 and prows[2][1].on == true, "the pages' Aa box: four sizes, the typefaces, the chosen ones marked")
check(prows[1][4].run() == true and Paper.frontFont(plugin).size.id == "larger", "a size's button chooses it")
rows = Paper.settingsItems(plugin)
local prs = Paper.frontItems(plugin)
check(row("The paper's pages") and #prs == 2 and prs[1].text_func() == "Typeface: Serif" and prs[2].text_func() == "Size: Larger", "Settings → Daily paper → The paper's pages: typeface, size")
prs[2].sub_item_table[2].callback()
prs[1].sub_item_table[4].callback()
check(Paper.frontFont(plugin).size.id == "normal" and Paper.frontFont(plugin).face.id == "typewriter" and prs[2].sub_item_table[2].checked_func() == true, "picked there")
check(Paper.weatherDays(0.85) == 4 and Paper.weatherDays(1) == 4 and Paper.weatherDays(1.2) == 3 and Paper.weatherDays(1.45) == 2, "bigger type: fewer days in the weather box, so each still fits")
check(row("The paper's pages").help_text:find("fewer stories on a page", 1, true), "the setting says bigger type means more pages")
local fsrc = read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(fsrc:find("local head_face = face(ff.face.bold, fz(lead and 17 or feature and 15 or 12)", 1, true) and fsrc:find("local body_face = face(ff.face.regular, fz(feature and 11 or 10)", 1, true)
    and fsrc:find("self.key_events.GzType = { { k.type } }", 1, true) and fsrc:find('return "type"', 1, true), "headlines and stories' beginnings are set in it; Aa at the foot and a key open the box")

print("== a story rests where the finger leaves it")
local LS = require("gzreader_livescroll")
local fdx, fdy = LS.freeEnd({ rel_x = 0, rel_y = -340, moved_x = 0, moved_y = 300 }, { direction = "north", distance = 900 })
check(fdx == 0 and fdy == 40, "a drag ending as a swipe: the page goes the 40 px the finger went since its last step, not a screenful")
fdx, fdy = LS.freeEnd({ rel_x = 0, rel_y = 200, moved_x = 0, moved_y = -200 }, { direction = "south", distance = 500 })
check(fdx == 0 and fdy == 0, "already where the finger left it: it stays")
fdx, fdy = LS.freeEnd({}, { direction = "north", distance = 120 })
check(fdx == 0 and fdy == 120 and select(2, LS.freeEnd({}, { direction = "south", distance = 80 })) == -80 and select(2, LS.freeEnd({}, { direction = "northeast", distance = 100 })) == 70,
    "a flick too quick to be seen as a drag: its own length, never a screenful")
local moved_by = {}
local function scroller()
    return { _is_scrollable = true, _scrolling = false, _scroll_offset_x = 0, _scroll_offset_y = 1000, _max_scroll_offset_x = 0, _max_scroll_offset_y = 5000,
        dimen = { x = 0, y = 0, w = 600, h = 800 }, show_parent = {},
        _scrollBy = function(self, _dx, dy) moved_by[#moved_by + 1] = dy; self._scroll_offset_y = math.max(0, math.min(self._max_scroll_offset_y, self._scroll_offset_y + dy)) end,
        onScrollablePan = function(self) self._scrolling = true; return true end,
        onScrollablePanRelease = function(self) self._scrolling = false; return true end,
        onScrollableSwipe = function(self, _a, ges) self:_scrollBy(0, ges.direction == "north" and 800 or -800); return true end }
end
local fake = scroller()
package.loaded["ui/uimanager"].setDirty = function() end
local clock = 0
LS.now = function() clock = clock + 1; return clock end
LS.on(fake, { free = true })
local pos = { intersectWith = function() return true end }
fake:onScrollablePan(nil, { relative = { x = 0, y = -100 } })
fake:onScrollablePan(nil, { relative = { x = 0, y = -230 } })
fake:onScrollablePan(nil, { relative = { x = 0, y = -235 } })
check(fake._scroll_offset_y == 1230, "the page follows the finger in steps (230 px so far; the last 5 px wait)")
fake:onScrollableSwipe(nil, { direction = "north", distance = 240, pos = pos })
check(fake._scroll_offset_y == 1235 and fake._scrolling == false, "the finger lifts still moving: the page rests 235 px on, where the finger was (was: a screenful further) … " .. fake._scroll_offset_y)
fake:onScrollablePan(nil, { relative = { x = 0, y = 60 } })
fake:onScrollablePanRelease(nil, {})
check(fake._gz_live.rel_y == nil or fake._scrolling == false, "the next drag starts afresh")
local snapper = scroller()
LS.on(snapper)
snapper:onScrollablePan(nil, { relative = { x = 0, y = -100 } })
snapper:onScrollableSwipe(nil, { direction = "north", distance = 120, pos = pos })
check(snapper._scroll_offset_y == 1800, "where it isn't asked for (the notes), a swipe still moves a screenful … " .. snapper._scroll_offset_y)
check(dsrc:find('require("gzreader_livescroll").on(self.scroller, { free = true, coarse = true })', 1, true),
    "the story asks for it (and for coarse steps: run_tests.lua checks those)")

print("== today's calendar events on the front page")
local function tm(day, h, m) return os.time{ year = 2026, month = 11, day = day, hour = h, min = m or 0 } end
local evs = {
    { title = "Dentist", start = tm(17, 9, 5), finish = tm(17, 10) },
    { title = "Yesterday", start = tm(16, 9), finish = tm(16, 10) },
    { title = "Birthday", all_day = true, start = tm(17, 0), finish = tm(18, 0) },
    { title = "Night shift", start = tm(16, 22), finish = tm(17, 6, 30) },
    { title = "", start = tm(17, 18), finish = tm(17, 19) },
    { title = "Tomorrow", start = tm(18, 0), finish = tm(18, 1) },
    { title = "Ended at midnight", all_day = true, start = tm(16, 0), finish = tm(17, 0) },
    { title = "No end", start = tm(17, 23, 59) },
}
rawset(_G, "G_reader_settings", { isTrue = function() return false end, readSetting = function() return WORK .. "/nohome/GZreader" end })
local today_list = Paper.todayEvents(tm(17, 12), evs)
local names = {}
for _i, ev in ipairs(today_list) do names[#names + 1] = ev.when .. " " .. ev.title end
check(table.concat(names, " | ") == "All day Birthday | Until 6:30 Night shift | 9:05 Dentist | 18:00 (no title) | 23:59 No end",
    "today's events: all-day first, then by time; one running since yesterday says until when; not yesterday's or tomorrow's … " .. table.concat(names, " | "))
rawset(_G, "G_reader_settings", { isTrue = function(_s, k) return k == "twelve_hour_clock" end, readSetting = function() return WORK .. "/nohome/GZreader" end })
check(Paper.todayEvents(tm(17, 12), evs)[3].when == "9:05 AM" and Paper.clockText(tm(17, 18), true) == "6:00 PM", "with the 12-hour clock: 9:05 AM")
rawset(_G, "G_reader_settings", { isTrue = function() return false end, readSetting = function() return WORK .. "/nohome/GZreader" end })
check(#Paper.todayEvents(tm(19, 12), evs) == 0 and #Paper.todayEvents(tm(17, 12), {}) == 0, "a day without events: nothing")
check(Paper.diaryText(today_list, 2) == "All day Birthday   \u{00B7}   Until 6:30 Night shift   \u{00B7}   and 3 more", "the diary line, and how many more")
package.loaded["gzreader_caldav"] = { loadCache = function() return { events = { { title = "Kept", start = os.time(), finish = os.time() + 60 } } } end }
check(Paper.todayEvents()[1].title == "Kept", "read from what the Calendar tab keeps on the Kindle (nothing fetched)")
package.loaded["gzreader_caldav"] = { loadCache = function() error("no cache") end }
check(#Paper.todayEvents() == 0, "no calendar: nothing, no error")
plugin = { store = { daily = { enabled = true } }, save = function() saves = saves + 1 end }
check(Paper.calendarOn(plugin) == true, "on unless unticked")
rows = Paper.settingsItems(plugin)
row("Today's calendar events").callback()
check(Paper.calendarOn(plugin) == false and plugin.store.daily.calendar == false and row("Today's calendar events").checked_func() == false, "Settings → Accounts and services → Daily paper → Today's calendar events: unticked")
row("Today's calendar events").callback()
check(Paper.calendarOn(plugin) == true and plugin.store.daily.calendar == nil, "… and ticked again")
check(row("Today's calendar events").help_text:find("nothing about them leaves the Kindle", 1, true), "the setting says the events stay on the Kindle")
local ds = read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(ds:find("if first and Paper.calendarOn(self.plugin) then", 1, true) and ds:find('return "diary"', 1, true), "the front page draws the box when it's on, and a tap on it is the Calendar tab's")

print("== the weather")
local W = require("gzreader_weather")
check(W.kindOfCode(0) == "clear" and W.kindOfCode(2) == "partly" and W.kindOfCode(3) == "cloudy" and W.kindOfCode(48) == "fog" and W.kindOfCode(61) == "rain"
    and W.kindOfCode(82) == "rain" and W.kindOfCode(75) == "snow" and W.kindOfCode(86) == "snow" and W.kindOfCode(96) == "storm" and W.kindOfCode(nil) == nil,
    "Open-Meteo's weather codes as kinds of sky")
check(W.kindOfCondition("sunny") == "clear" and W.kindOfCondition("partlycloudy") == "partly" and W.kindOfCondition("pouring") == "rain"
    and W.kindOfCondition("snowy-rainy") == "snow" and W.kindOfCondition("lightning-rainy") == "storm" and W.kindOfCondition("windy") == "cloudy"
    and W.kindOfCondition("unavailable") == nil, "Home Assistant's conditions as kinds of sky")
check(W.degrees(53.6) == "54\u{00B0}" and W.degrees(-0.2) == "0\u{00B0}" and W.degrees(-3.5) == "-3\u{00B0}" and W.degrees(nil) == "\u{2013}", "degrees rounded; no -0")
local asked_url
local function geo(results) return function(url) asked_url = url; return { results = results } end end
local found = W.geocode("  Saint-Rémy de Provence ", geo({ { name = "Example Town", latitude = 51.47812, longitude = -0.00149, admin1 = "Example Shire", country_code = "GB" } }))
check(found and found.lat == 51.48 and found.lon == 0 and found.place == "Example Town, Example Shire" and found.unit == "C",
    "a town found: where it is, rounded to two decimals; Celsius outside the Fahrenheit countries")
check(asked_url:find("name=Saint%-R%%C3%%A9my%%20de%%20Provence") and asked_url:find("^https://geocoding%-api%.open%-meteo%.com/"), "the town's name goes to Open-Meteo's geocoder, encoded")
check(W.geocode("x", geo({ { name = "Springfield", latitude = 39.8, longitude = -89.64, country_code = "US", admin1 = "Illinois" } })).unit == "F", "a town in the United States: Fahrenheit to start with")
local nf, nf_err = W.geocode("Nowhere", geo(nil))
check(nf == nil and nf_err == "not found" and select(2, W.geocode("", geo({}))) == "not found", "no such town: said so")
check(select(2, W.geocode("x", function() return nil, "unreachable" end)) == "unreachable", "the geocoder not reached: said so")
local furl = W.forecastUrl(51.48, -0.1234567, "F")
check(furl:find("latitude=51.48&longitude=-0.12&", 1, true) and furl:find("temperature_unit=fahrenheit", 1, true) and furl:find("forecast_days=3", 1, true)
    and W.forecastUrl(1, 2, "C"):find("temperature_unit=celsius", 1, true), "the day's request: coordinates to two decimals, the unit, three days")
local wnow = os.time{ year = 2026, month = 11, day = 17, hour = 12 }
local meteo = { current = { temperature_2m = 51.6, weather_code = 61 }, daily = { time = { "2026-11-17", "2026-11-18", "2026-11-19" }, weather_code = { 63, 2, 71 },
    temperature_2m_max = { 54.2, 49.1, 30 }, temperature_2m_min = { 41, 36.4, 22 }, precipitation_probability_max = { 80, 20, 60 } } }
local wx = W.fromMeteo(meteo, "F", wnow)
check(wx and wx.unit == "F" and wx.now.kind == "rain" and wx.now.temp == 51.6 and #wx.days == 3 and wx.days[2].kind == "partly" and wx.days[3].kind == "snow" and wx.days[1].wet == 80,
    "Open-Meteo's answer: now and three days")
check(W.fromMeteo({}, "C") == nil and W.fromMeteo(nil) == nil, "an answer with nothing in it: no weather")
check(not dkjson.encode(wx):find("51.48", 1, true) and not dkjson.encode(wx):find("lat", 1, true), "the weather kept with the paper has no place in it")
local cells = W.cells(wx, wnow)
local ct = {}
for _i, c in ipairs(cells) do ct[#ct + 1] = c.head .. "=" .. c.line .. "(" .. c.kind .. ")" end
check(table.concat(ct, " ") == "Now=52\u{00B0} Rain(rain) Today=54\u{00B0} / 41\u{00B0}  80%(rain) Wed=49\u{00B0} / 36\u{00B0}(partly) Thu=30\u{00B0} / 22\u{00B0}  60%(snow)",
    "the box: Now, Today, then the days by name; the chance of rain on a wet day; four cells at most … " .. table.concat(ct, " "))
check(W.cells(wx, wnow + 86400)[2].head == "Today" and W.cells(wx, wnow + 86400)[2].line:find("49", 1, true) and #W.cells(wx, wnow + 3 * 86400) == 1,
    "read the next day (yesterday's paper): the days gone by are left out")
check(#W.cells(nil) == 0, "no weather: no box")
local ha_state = { entity_id = "weather.home", state = "partlycloudy", attributes = { temperature = 12.4, temperature_unit = "\u{00B0}C" } }
local hw = W.fromHA(ha_state, { { datetime = "2026-11-17T12:00:00+00:00", condition = "rainy", temperature = 14, templow = 8, precipitation_probability = 70 },
    { datetime = "2026-11-18T12:00:00+00:00", condition = "sunny", temperature = 15, templow = 6 } }, wnow)
check(hw and hw.unit == "C" and hw.now.kind == "partly" and hw.now.temp == 12.4 and #hw.days == 2 and hw.days[1].kind == "rain" and hw.days[1].lo == 8 and hw.days[2].kind == "clear",
    "Home Assistant's weather entity and its daily forecast")
check(W.fromHA(ha_state, nil, wnow).now.temp == 12.4 and #W.fromHA(ha_state, nil, wnow).days == 0, "… without a forecast: now alone")
check(W.fromHA({ state = "unknown", attributes = {} }) == nil, "an entity that says nothing: no weather")
check(W.pickEntity({ { entity_id = "light.a", state = "on" }, { entity_id = "weather.broken", state = "unavailable" }, ha_state }) == ha_state, "the first weather entity that's alive")
plugin = { store = { daily = { enabled = true } }, save = function() saves = saves + 1 end }
check(W.source(plugin) == nil and not W.on(plugin) and W.plan(plugin) == nil, "no town and no Home Assistant: no weather is asked for")
W.store(plugin).lat, W.store(plugin).lon, W.store(plugin).unit = 51.48, 0, "F"
check(W.source(plugin) == "meteo" and W.on(plugin) and W.plan(plugin).source == "meteo" and W.plan(plugin).ha == nil, "a town set: Open-Meteo")
plugin.store.homeassistant = { server = "http://ha.example.com:8123", token = "TOKEN" }
check(W.source(plugin) == "ha" and W.plan(plugin).ha.server == "http://ha.example.com:8123", "Home Assistant connected: it comes first")
plugin.store.homeassistant = nil
W.store(plugin).off = true
check(not W.on(plugin) and W.plan(plugin) == nil, "the weather turned off: none asked for")
W.store(plugin).off = nil
for _i, kind in ipairs({ "clear", "partly", "cloudy", "fog", "rain", "snow", "storm", "?" }) do
    local painted, outside = 0, false
    local function mark(x, y, w2, h2)
        painted = painted + 1
        if x < 100 - 2 or y < 200 - 2 or x + (w2 or 0) > 100 + 44 + 4 or y + (h2 or 0) > 200 + 44 + 4 then outside = true end
    end
    local bbs = { paintRect = function(_s, x, y, w2, h2) mark(x, y, w2, h2) end,
        paintCircle = function(_s, cx, cy, r) mark(cx - r, cy - r, r * 2, r * 2) end }
    W.icon(bbs, kind, 100, 200, 44)
    if painted < 4 or outside then check(false, "the sky's drawing for " .. kind .. " (" .. painted .. " strokes, outside: " .. tostring(outside) .. ")") end
end
check(true, "every kind of sky has its drawing, inside its square")
-- fetched with the paper
plugin.store.daily.feeds = { { url = "https://ok.example.com/rss?key=SECRET", name = "Mine" } }
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do Daily.setDefaultOn(plugin, f, false) end
http.answers["https://ok.example.com/rss?key=SECRET"] = { body = RSS }
http.answers[W.forecastUrl(51.48, 0, "F")] = { data = meteo }
Daily.edition, Daily.loaded, Daily.tried_at = nil, true, nil
logged = {}
Daily.refresh(plugin)
check(Daily.edition and Daily.edition.weather and Daily.edition.weather.now.kind == "rain" and #Daily.edition.weather.days == 3, "the weather comes with the day's paper")
local wcall
for _i, c in ipairs(http.calls) do if c.url:find("api.open-meteo.com", 1, true) then wcall = c end end
check(wcall and wcall.opts.log_url and not wcall.opts.log_url:find("51", 1, true) and not wcall.opts.log_url:find("latitude", 1, true), "the log gets no coordinates … " .. tostring(wcall and wcall.opts.log_url))
leaked = false
for _i, line in ipairs(logged) do if line:find("51.48", 1, true) or line:find("latitude", 1, true) then leaked = true end end
check(not leaked, "… in no line")
http.answers[W.forecastUrl(51.48, 0, "F")] = nil
Daily.edition.day = ""
Daily.refresh(plugin)
check(Daily.edition and Daily.edition.day ~= "" and Daily.edition.weather == nil, "Open-Meteo not reached: the paper comes without the box")
rows = Paper.settingsItems(plugin)
local wrows = Paper.weatherItems(plugin)
check(row("Weather") and #wrows == 3 and wrows[1].checked_func() == true and wrows[3].text_func() == "Degrees: Fahrenheit" and wrows[2].text_func():find("Town", 1, true),
    "Settings → Accounts and services → Daily paper → Weather: the switch, the town, the degrees")
wrows[3].callback()
check(W.store(plugin).unit == "C" and wrows[3].text_func() == "Degrees: Celsius", "degrees switched")
wrows[1].callback()
check(W.store(plugin).off == true and not W.on(plugin), "weather switched off")
wrows[1].callback()
check(wrows[1].help_text:find("rounded to about a kilometre", 1, true) and wrows[1].help_text:find("Home Assistant", 1, true), "the switch says where the weather comes from and what is sent")
plugin.store.homeassistant = { server = "http://ha.example.com:8123", token = "TOKEN" }
check(wrows[2].text_func() == "From your Home Assistant" and wrows[2].enabled_func() == false, "with Home Assistant connected there's no town to set")
plugin.store.homeassistant = nil

print("== pictures fetched with the paper")
plugin = { store = { daily = { enabled = true, off = {}, feeds = { { url = "https://pics.example.com/rss", name = "Pics" } } } }, save = function() end }
for _i, f in ipairs(Daily.DEFAULT_FEEDS) do Daily.setDefaultOn(plugin, f, false) end
http.answers["https://pics.example.com/rss"] = { body = '<rss><channel><item><title>Lead</title><description>d</description><enclosure url="https://img.example.com/lead.png?k=SECRET" type="image/png"/></item>'
    .. '<item><title>Big</title><media:thumbnail url="https://img.example.com/big.jpg"/></item><item><title>Gone</title><media:thumbnail url="https://img.example.com/gone.jpg"/></item></channel></rss>' }
http.answers["https://img.example.com/lead.png?k=SECRET"] = { body = PNG }
http.answers["https://img.example.com/big.jpg"] = { body = JPG .. string.rep("b", Daily.MAX_PICTURE_BYTES) }
http.answers["https://img.example.com/gone.jpg"] = { code = 404 }
Daily.edition, Daily.loaded, Daily.tried_at = nil, true, nil
os.remove(Daily.cachePath())
logged = {}
Daily.refresh(plugin)
local lead_item = Daily.edition and Daily.edition.sections[1].items[1]
check(lead_item and lead_item.img and Daily.edition.pictures == 1 and read(Daily.pictureDir() .. "/" .. lead_item.img) == PNG and Daily.picturePath(lead_item),
    "the lead story's picture is fetched with the paper and kept in cache/gzreader-daily")
check(Daily.edition.sections[1].items[2].img == nil and Daily.edition.sections[1].items[3].img == nil, "a picture over " .. math.floor(Daily.MAX_PICTURE_BYTES / 1024) .. " KB, or one that's gone: the story goes without")
local pcall_ = http.calls[#http.calls]
check(pcall_.opts.log_url:find("img.example.com", 1, true) and pcall_.opts.log_url:find("(picture)", 1, true) and not pcall_.opts.log_url:find("jpg", 1, true),
    "the log gets a picture's site, never its address")
leaked = false
for _i, line in ipairs(logged) do if line:find("SECRET", 1, true) or line:find("lead.png", 1, true) then leaked = true end end
check(not leaked and logged[#logged]:find("1 pictures", 1, true), "… and the day's line counts them … " .. show(logged[#logged]))
check(not read(Daily.cachePath()):find("SECRET", 1, true), "no picture address is kept with the edition")
plugin.store.daily.pictures = false
local n_calls = #http.calls
Daily.refresh(plugin)
local pic_calls = 0
for i = n_calls + 1, #http.calls do if http.calls[i].url:find("img.example.com", 1, true) then pic_calls = pic_calls + 1 end end
check(pic_calls == 0 and Daily.edition.sections[1].items[1].img == nil and not Daily.pictures(plugin), "Pictures off: none is asked for")
plugin.store.daily.pictures = nil

print("== the setup page (a browser on your Wi-Fi)")
plugin = { store = { daily = { enabled = true, feeds = { { url = "https://ok.example.com/rss?key=SECRET", name = "Mine" }, { url = "https://two.example.com/feed" } } } }, save = function() end }
Daily.edition, Daily.loaded, Daily.tried_at = { day = "x", sections = { { topic = "World", items = { {}, {} } } } }, true, 5
local ps = Daily.pageState(plugin)
check(ps.enabled and ps.shelf and #ps.defaults == #Daily.DEFAULT_FEEDS and #ps.own == 2 and ps.own[1].name == "Mine" and ps.own[1].site == "ok.example.com"
    and ps.stories == 2, "the page's state: the switches, GZreader's feeds, yours by name and site")
check(not dkjson.encode(ps):find("SECRET", 1, true) and not dkjson.encode(ps):find("key=", 1, true) and not dkjson.encode(ps):find("https:", 1, true), "… never a feed's address")
local PairPage = dofile(PLUGIN .. "/gzreader_pairpage.lua")
local html = PairPage.hub({ base = "/t", paper = ps, start = "paper" })
check(html:find('<section id="paper"', 1, true) and html:find('data-tab="paper"', 1, true) and html:find('name="d_' .. Daily.DEFAULT_FEEDS[1].id .. '" value="1" checked', 1, true)
    and html:find('name="f_1" value="1" checked', 1, true) and html:find('name="feeds"', 1, true) and html:find("Remove Mine (ok.example.com)", 1, true),
    "the page has a Daily paper tab: switches, every feed with its tick, a box to paste feeds, Remove")
check(not html:find("SECRET", 1, true), "the page shows no feed address")
check(not PairPage.hub({ base = "/t" }):find('id="paper"', 1, true), "a Kindle without Wi-Fi: no such tab")
local form = { enabled = "1", count = "2", f_2 = "1" }
form["d_" .. Daily.DEFAULT_FEEDS[2].id] = "1"
Daily.pageSave(plugin, form)
local st2 = plugin.store.daily
check(ps.weather and ps.weather.on == true and ps.weather.source == nil and html:find('name="weather" value="1" checked', 1, true) and html:find('name="town"', 1, true)
    and html:find('name="unit"', 1, true) and W.store(plugin).off == true, "Weather: its tick, the town and the degrees on the page; unticked when Save comes without it")
check(st2.full == false and ps.full == true and html:find('name="full" value="1" checked', 1, true), "Whole stories: ticked on the page; unticked when Save comes without it")
check(st2.calendar == false and ps.calendar == true and html:find('name="calendar" value="1" checked', 1, true), "Today's calendar events: ticked on the page; unticked when Save comes without it")
check(st2.pictures == false and ps.pictures == true and html:find('name="pictures" value="1" checked', 1, true), "With pictures: ticked on the page; unticked when Save comes without it")
check(st2.enabled == true and st2.shelf == false and st2.feeds[1].enabled == false and st2.feeds[2].enabled == nil, "Save: the switches and your feeds' ticks as sent (an unticked box isn't sent)")
check(Daily.defaultOn(plugin, Daily.DEFAULT_FEEDS[2]) and not Daily.defaultOn(plugin, Daily.DEFAULT_FEEDS[1]) and Daily.tried_at == nil and Daily.edition.day == "",
    "… GZreader's feeds too; the paper is made again at the next look")
Daily.pageSave(plugin, { enabled = "1", shelf = "1", pictures = "1", weather = "1", unit = "F", count = "1", f_1 = "1" })
check(W.store(plugin).off == nil and W.store(plugin).unit == "F", "Weather ticked and Fahrenheit chosen on the page")
check(st2.feeds[1].enabled == false and st2.shelf == nil and st2.pictures == nil, "a page that's out of date (another count of feeds) doesn't change your feeds' ticks")
Daily.pageSave(plugin, { shelf = "1", count = "2" })
check(st2.enabled == nil and not Daily.enabled(plugin), "Save with Daily paper unticked: off")
local added_n, skipped_n = Daily.pageAdd(plugin, "Tea | tea.example.com/feed\r\n# note\n\nnot a feed\nhttps://two.example.com/feed\nCrafts | Knit | https://knit.example.com/atom.xml\n")
check(added_n == 2 and skipped_n == 2 and #st2.feeds == 4 and st2.feeds[3].name == "Tea" and st2.feeds[4].topic == "Crafts",
    "feeds pasted: 2 added, 2 lines not (not an address, there already); comments and empty lines don't count")
check(Daily.pageRemove(plugin, "3", "4") == true and #st2.feeds == 3 and st2.feeds[3].name == "Knit", "Remove: the one you chose")
check(Daily.pageRemove(plugin, "3", "4") == false and Daily.pageRemove(plugin, "9", "3") == false and Daily.pageRemove(plugin, "x", "3") == false and #st2.feeds == 3,
    "Remove from a page that's out of date, or of a feed that isn't there: nothing")
net.usb = true
check(Daily.pageState(plugin) == nil, "a Kindle without Wi-Fi: nothing for the page")
net.usb = false
local phone = read(PLUGIN .. "/gzreader_phone.lua")
check(phone:find('routes["/paper"]', 1, true) and phone:find('routes["/paper/add"]', 1, true) and phone:find('routes["/paper/remove"]', 1, true)
    and phone:find('require("gzreader_daily").pageState(plugin)', 1, true), "the setup page's server has the section's state and its three forms")
check(phone:find("W.geocode(town)", 1, true) and not phone:match("Log%.[a-z]+%([^\n]*town"), "a town typed on the page is looked up, and not logged")
check(not phone:match('routes%["/paper/add"%].-Log%.[a-z]+%([^\n]*form%.feeds'), "… and logs no pasted address")
rows = Paper.settingsItems(plugin)
plugin.store.daily.enabled = true
local opened
package.loaded["gzreader_phone"] = { open = function(_p, opts) opened = opts end }
row("Set up from a browser").callback()
check(opened and opened.section == "paper", "Settings → Accounts and services → Daily paper → Set up from a browser opens the page at Daily paper")

print("== wired in")
local main = read(PLUGIN .. "/main.lua")
check(main:find("function Grimmory:dailySettingsItems()", 1, true) and main:find('return require("gzreader_dailyscreen").settingsItems(self)', 1, true), "the plugin gives Settings → Accounts and services its Daily paper page")
check(main:find("pcall(self.installDailyPaper, self)", 1, true) and main:find('require("gzreader_dailyscreen").shelfItem(plugin, ctx, area_h, cover_w)', 1, true)
    and main:find('require("gzreader_dailyscreen").homeWidget(plugin, ctx)', 1, true), "the plugin registers Home's widget and the shelf's newspaper at start")
local zs = read(REPO .. "/plugins/zenos.koplugin/modules/settings/zen_settings.lua")
local tree = read(REPO .. "/plugins/zenos.koplugin/common/gz_settings_tree.lua")
check(tree:find('row(_("Daily paper"), _("Feeds"), "dailySettingsItems", "history")', 1, true) ~= nil,
    "Settings → Accounts and services has the daily paper (with the other things fetched from the web)")
local sh = read(REPO .. "/plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua")
check(sh:find('rawget(_G, "__GZ_SHELF_PAPER")', 1, true) and sh:find("opts.gz_home", 1, true) and sh:find("gz_paper = true", 1, true),
    "ZenOS's shelf asks for the newspaper, on Home's first shelf only")
check(sh:find("i == picked and slot.gz_paper", 1, true) and sh:find("slot.face:paintTo", 1, true) and sh:find("ctx.focusHomeTarget(slot.target)", 1, true),
    "… stands it on its side, and turns it to its front page when it's picked, as a book shows its cover")
check(read(REPO .. "/plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/strip_common.lua"):find("gz_home = true", 1, true), "Home's shelf says it's Home's")
local src = read(PLUGIN .. "/gzreader_daily.lua") .. read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(not src:find("Log%.[a-z]+%([^\n]*%f[%w]url%f[%W][^\n]*%)") or not src:find("Log%.[a-z]+%([^\n]*[^%.]url[,%)]"), "no log line takes a feed's address")
;(function()
print("== the day's puzzles")
local Pz = require("gzreader_puzzles")
local Dz = require("gzreader_daily")
local real_edition = Pz.edition
Pz.edition = function() return nil end -- (no paper yet: the puzzles' own words; the news' words are tested below)
local pz_saves, soon = 0, 0
local pl = { store = { daily = { enabled = true } }, save = function() pz_saves = pz_saves + 1 end, saveSoon = function() soon = soon + 1 end }
-- chance: the same day, the same run
local r1, r2, r3 = Pz.rng("2030-01-02"), Pz.rng("2030-01-02"), Pz.rng("2030-01-03")
local same, differs = true, false
for _i = 1, 50 do
    local a, b, c = r1.pick(1000), r2.pick(1000), r3.pick(1000)
    if a ~= b then same = false end
    if a ~= c then differs = true end
    if a < 1 or a > 1000 then same = false end
end
check(same and differs, "the day's chance: the same date gives the same numbers, another date others")

-- sudoku
local s = Pz.sudoku("2030-01-02")
local s_again, s_other = Pz.sudoku("2030-01-02"), Pz.sudoku("2030-01-03")
check(s.given == s_again.given and s.answer == s_again.answer and s.given ~= s_other.given, "sudoku: the same on every Kindle that day, another the next day")
local function valid(answer)
    for i = 0, 8 do
        local rw, col, box = {}, {}, {}
        for j = 0, 8 do
            rw[answer:sub(i * 9 + j + 1, i * 9 + j + 1)] = true
            col[answer:sub(j * 9 + i + 1, j * 9 + i + 1)] = true
            local r, c = math.floor(i / 3) * 3 + math.floor(j / 3), (i % 3) * 3 + j % 3
            box[answer:sub(r * 9 + c + 1, r * 9 + c + 1)] = true
        end
        for d = 1, 9 do if not (rw[tostring(d)] and col[tostring(d)] and box[tostring(d)]) then return false end end
    end
    return true
end
local ok_all, fewest, most = true, 81, 0
for d = 1, 12 do
    local g = Pz.sudoku("2031-03-" .. d)
    local grid_n, n = {}, 0
    for i = 1, 81 do
        grid_n[i] = tonumber(g.given:sub(i, i))
        if grid_n[i] ~= 0 then
            n = n + 1
            if g.given:sub(i, i) ~= g.answer:sub(i, i) then ok_all = false end
        end
    end
    fewest, most = math.min(fewest, n), math.max(most, n)
    if not valid(g.answer) or Pz.sudokuCount(grid_n, 2) ~= 1 then ok_all = false end
end
check(ok_all, "sudoku: every answer is a proper grid, the printed numbers are from it, and there is exactly one answer (12 days)")
check(fewest >= 28 and most <= 40, "sudoku: about 34 numbers printed (" .. fewest .. "–" .. most .. ")")
local empty_g = {}
for i = 1, 81 do empty_g[i] = 0 end
check(Pz.sudokuCount(empty_g, 2) == 2, "the counter stops at the limit on an empty grid")
empty_g[1], empty_g[2] = 5, 5
check(Pz.sudokuCount(empty_g, 2) == 0, "…and says none for a grid that breaks the rules")

-- the day's sudoku, written in
local day = Dz.day()
local dsu = Pz.daySudoku(pl)
check(dsu.given == Pz.sudoku(day).given and dsu.fill == dsu.given and pl.store.daily.puzzles.day == day and soon == 1 and pz_saves == 0, "the day's sudoku: made once and kept, saved soon (not at once)")
local first = dsu.fill:find("0", 1, true)
local printed = dsu.given:find("[1-9]")
local right = tonumber(dsu.answer:sub(first, first))
check(Pz.sudokuSet(pl, first, right % 9 + 1) == true and Pz.daySudoku(pl).fill:sub(first, first) == tostring(right % 9 + 1), "a number written in an empty square")
check(Pz.sudokuSet(pl, printed, 1) == false and Pz.sudokuSet(pl, first, right % 9 + 1) == false and Pz.sudokuSet(pl, 0, 1) == false and Pz.sudokuSet(pl, first, 10) == false,
    "a printed number can't be changed; the same number again, a square or a number that doesn't exist: nothing")
local wrong = Pz.sudokuWrong(Pz.daySudoku(pl))
check(wrong[first] == true and next(wrong, first) == nil and next(wrong) == first, "Check: only the wrong square is marked")
check(Pz.sudokuSet(pl, first, 0) == true and Pz.daySudoku(pl).fill == dsu.given, "0 rubs it out")
check(select(2, Pz.finished(pl)) == 0 and not Pz.sudokuDone(Pz.daySudoku(pl)), "not solved yet")
for i = 1, 81 do Pz.sudokuSet(pl, i, tonumber(dsu.answer:sub(i, i))) end
local fin, fin_n = Pz.finished(pl)
check(Pz.sudokuDone(Pz.daySudoku(pl)) and fin.sudoku == true and fin_n == 1, "every square right: solved, and counted")
Pz.sudokuClear(pl)
check(Pz.daySudoku(pl).fill == dsu.given and select(2, Pz.finished(pl)) == 0, "Start again: the printed numbers only")
pl.store.daily.puzzles.sudoku.fill = "12"
check(Pz.daySudoku(pl).fill == dsu.given, "a kept grid that makes no sense: the printed numbers")

-- word search
local ws = Pz.wordSearch("2030-01-02")
local ws2 = Pz.wordSearch("2030-01-02")
check(ws.grid == ws2.grid and #ws.grid == 100 and ws.size == 10 and #ws.words == 8 and not ws.grid:find("[^A-Z]"), "word search: 10 × 10 letters, eight words, the same that day")
local in_grid, in_line, sorted, seen_w = true, true, true, {}
for i, w in ipairs(ws.words) do
    for k = 1, #w.word do
        local x, y = w.x + w.dx * (k - 1), w.y + w.dy * (k - 1)
        if x < 1 or x > 10 or y < 1 or y > 10 or ws.grid:sub((y - 1) * 10 + x, (y - 1) * 10 + x) ~= w.word:sub(k, k) then in_grid = false end
    end
    local ex, ey = w.x + w.dx * (#w.word - 1), w.y + w.dy * (#w.word - 1)
    local line = Pz.line(w.x, w.y, ex, ey)
    if not line or #line ~= #w.word or Pz.wordAt(ws, w.x, w.y, ex, ey) ~= i or Pz.wordAt(ws, ex, ey, w.x, w.y) ~= i then in_line = false end
    if i > 1 and ws.words[i - 1].word >= w.word then sorted = false end
    if seen_w[w.word] then sorted = false end
    seen_w[w.word] = true
end
check(in_grid, "every word is in the letters where it says")
check(in_line and sorted, "a word is found from its first letter to its last or the other way round; the list is in order, no word twice")
check(Pz.line(1, 1, 3, 2) == nil and #Pz.line(2, 2, 2, 2) == 1 and #Pz.line(5, 1, 1, 5) == 5 and Pz.wordAt(ws, 1, 1, 1, 2) == nil, "letters not in a line, or not a word: nothing")
local all_caps = true
for _i, w in ipairs(Pz.WORD_LIST) do if not w:match("^[A-Z]+$") then all_caps = false end end
check(all_caps and #Pz.WORD_LIST >= 150, "the words are plain capitals (" .. #Pz.WORD_LIST .. ")")
local dw, fnd = Pz.dayWords(pl)
check(dw.grid == Pz.wordSearch(day).grid and next(fnd) == nil, "the day's word search, nothing found yet")
check(Pz.wordFound(pl, 3) == true and Pz.wordFound(pl, 3) == false and Pz.wordFound(pl, 99) == false, "a word marked found once; one that isn't there: nothing")
fnd = select(2, Pz.dayWords(pl))
check(fnd[3] == true and not fnd[1] and pl.store.daily.puzzles.words.found == "3" and not Pz.wordsDone(dw, fnd), "kept as its number")
for n = 1, 8 do Pz.wordFound(pl, n) end
fnd = select(2, Pz.dayWords(pl))
check(Pz.wordsDone(dw, fnd) and Pz.finished(pl).words == true, "all eight: solved")

-- maze
local mz = Pz.maze("2030-01-02", 12, 14)
local mz2 = Pz.maze("2030-01-02", 12, 14)
local same_m = #mz.cells == 168
for i = 1, #mz.cells do if mz.cells[i] ~= mz2.cells[i] then same_m = false end end
check(same_m, "maze: the same that day at the same size")
local opens, matched, reached = 0, true, { [1] = true }
local queue, head = { 1 }, 1
local step = { n = -12, s = 12, e = 1, w = -1 }
local back = { n = "s", s = "n", e = "w", w = "e" }
while queue[head] do
    local here = queue[head]; head = head + 1
    for side, d in pairs(step) do
        if Pz.mazeOpen(mz, here, side) then
            opens = opens + 1
            local to = here + d
            if to < 1 or to > 168 or not Pz.mazeOpen(mz, to, back[side]) then matched = false
            elseif (side == "e" and here % 12 == 0) or (side == "w" and here % 12 == 1) then matched = false
            elseif not reached[to] then reached[to] = true; queue[#queue + 1] = to end
        end
    end
end
check(matched and #queue == 168 and opens == 2 * 167, "every square can be reached, each opening has its other side, and there is one way between any two (no loops)")
local side = Pz.mazeOpen(mz, 1, "e") and "e" or "s"
local path = Pz.mazeWalk(mz, 1, side)
local blocked = Pz.mazeOpen(mz, 1, "e") and "s" or "e"
check(#path >= 1 and path[1] == 1 + step[side], "a walk goes on to a wall, a turning or a crossing (" .. #path .. " squares)")
check(Pz.mazeOpen(mz, 1, blocked) or #Pz.mazeWalk(mz, 1, blocked) == 0, "into a wall: nowhere")
check(#Pz.mazeWalk(mz, 1, "n") == 0 and #Pz.mazeWalk(mz, 1, "w") == 0, "the outer wall holds")
local dm, here, seen_m = Pz.dayMaze(pl, 12, 14)
check(here == 1 and seen_m[1] and #dm.cells == 168, "the day's maze: at the start")
local dside = Pz.mazeOpen(dm, 1, "e") and "e" or "s"
local moved = Pz.mazeMove(pl, 12, 14, dside)
local at2, seen2 = select(2, Pz.dayMaze(pl, 12, 14))
check(#moved >= 1 and at2 == moved[#moved] and seen2[1] and seen2[at2], "a move is kept, with where you've been")
check(select(2, Pz.dayMaze(pl, 10, 10)) == 1, "another size of screen: from the start")
pl.store.daily.puzzles.maze = { cols = 12, rows = 14, at = 168, seen = "1,168" }
check(Pz.finished(pl).maze == true and #Pz.mazeMove(pl, 12, 14, "n") == 0 and select(2, Pz.finished(pl)) == 2, "at the way out: solved, and it stays there")
Pz.mazeClear(pl)
check(select(2, Pz.dayMaze(pl, 12, 14)) == 1, "Start again: back at the start")

-- the next day: new puzzles, nothing carried over; the switch
local st_p = Pz.state(pl, "2031-05-05")
check(st_p.day == "2031-05-05" and st_p.sudoku == nil and st_p.words == nil and st_p.maze == nil and select(2, Pz.finished(pl, "2031-05-05")) == 0, "the next day's paper: new puzzles, nothing carried over")
check(Pz.on(pl) == true and Pz.on({ store = {} }) == true, "puzzles are on as it comes")
pz_saves = 0
Pz.setOn(pl, false)
check(Pz.on(pl) == false and pz_saves == 1, "switched off: kept")
check(Paper.puzzlesLabel(pl) == nil, "…and the paper's foot has no Puzzles")
Pz.setOn(pl, true)
check(Paper.puzzlesLabel(pl) == "Puzzles", "on: Puzzles at the paper's foot")
pl.store.daily.puzzles.maze = { cols = 12, rows = 14, at = 168, seen = "1,168" }
check(Paper.puzzlesLabel(pl) == "Puzzles 1/4", "…with how many are done")
local prow
for _i, r in ipairs(Paper.settingsItems(pl)) do if r.text == "Puzzles" then prow = r end end
check(prow and prow.checked_func() == true, "Settings → Daily paper → Puzzles, ticked")
prow.callback()
check(Pz.on(pl) == false and prow.checked_func() == false, "unticked there")
prow.callback()

-- the screen's words and sizes
local Scr = require("gzreader_puzzlescreen")
local c1, r1_ = Scr.mazeSize(576, 560, 30)
local c2, r2_ = Scr.mazeSize(1048, 1000, 80)
local c3, r3_ = Scr.mazeSize(100, 3000, 40)
check(c1 == 19 and r1_ == 18 and c2 == 13 and r2_ == 12 and c3 == 6 and r3_ == 26, "the maze's size follows the screen, within limits")
check(Scr.statusText("sudoku", { left = 47 }) == "47 squares to go." and Scr.statusText("sudoku", { left = 40, wrong = 1 }) == "1 square isn't right (marked)."
    and Scr.statusText("sudoku", { left = 40, wrong = 3 }) == "3 squares aren't right (marked)." and Scr.statusText("sudoku", { left = 40, wrong = 0, checked = true }) == "Right so far."
    and Scr.statusText("words", { found = 2, of = 8 }) == "2 of 8 found." and Scr.statusText("maze", { done = true }):find("Solved", 1, true), "the line under each puzzle")
check(Scr.helpText("sudoku", true):find("Tap a square", 1, true) and Scr.helpText("sudoku", false, true):find("Q–O", 1, true) and Scr.helpText("sudoku", false, false):find("Press: the next number", 1, true)
    and Scr.helpText("words", false, true):find("Press on a word's first letter", 1, true) and Scr.helpText("maze", true):find("swipe", 1, true), "how to play, for touch, a keyboard and the 5-way alone")
check(Scr.tabLabel("sudoku") == "Sudoku" and Scr.tabLabel("words") == "Word search" and Scr.tabLabel("cross") == "Crossword" and Scr.tabLabel("maze") == "Maze"
    and table.concat(Pz.KINDS, " ") == "sudoku words cross maze", "the four tabs")
-- words from the paper's stories
local paper = { day = "2031-06-01", sections = {
    { topic = "World", items = {
        { title = "Council votes to keep the old bridge open through the winter",
          text = "The council voted nine to four. Engineers said the bridge was sound, and the bridge stays. Café owners cheered. Elsewhere three people were killed in a crash. Traffic lights will let one lane cross at a time." },
        { title = "Harvest festival moved indoors", text = "Rain is forecast for the valley all weekend, the organisers said. Don't forget an umbrella." } } },
    { topic = "Technology", items = { { title = "A pocket radio that tunes itself", text = "The radio listens for the strongest signal. Its maker calls it a toy; the signal says otherwise." } } },
} }
local nw = Pz.newsWords(paper)
local by, order_ok, plain_ok = {}, true, true
for i, e in ipairs(nw) do
    by[e.word] = e
    if i > 1 then
        local a = nw[i - 1]
        if (not a.head and e.head) or (a.head == e.head and a.n < e.n) or (a.head == e.head and a.n == e.n and a.word >= e.word) then order_ok = false end
    end
    if not e.word:match("^[A-Z]+$") or #e.word < 4 or #e.word > 8 then plain_ok = false end
end
check(by.BRIDGE and by.BRIDGE.head == true and by.BRIDGE.n == 3 and by.COUNCIL and by.HARVEST and by.RADIO and by.RADIO.n == 2 and by.SIGNAL and by.SIGNAL.head == false,
    "the paper's words: from its headlines and its stories, counted")
check(order_ok and nw[1].head == true and plain_ok, "headline words first, then the ones seen most, then by the alphabet; plain A–Z words of 4 to 8 letters")
check(not by.THROUGH and not by.THREE and not by.PEOPLE and not by.SAID and not by.WERE, "everyday words say nothing about a story: left out")
check(not by.KILLED and not by.CRASH, "grim words aren't put in a puzzle")
check(by.CAF == nil and by.DON == nil and by.ENGINEERS == nil and by.ORGANISERS == nil, "a word with an accent or an apostrophe isn't cut in two; ones too long are left out")
check((by.VOTES ~= nil) ~= (by.VOTED ~= nil), "one of a family (VOTES or VOTED), not both")
check(by.FORECAST.from == "Rain is forecast for the valley all weekend, the organisers said." and by.COUNCIL.from == "Council votes to keep the old bridge open through the winter",
    "each word remembers the headline or sentence it was read in")
check(#Pz.newsWords(nil) == 0 and #Pz.newsWords({ sections = { { items = { { title = 5, text = false } } } } }) == 0 and Pz.source(nil) == "list" and Pz.source(paper) == "2031-06-01"
    and Pz.source({ day = "2031-06-02", sections = { { items = { { title = "Rain" } } } } }) == "list", "no paper, or one with hardly a word: the puzzles' own list")
local nws = Pz.wordSearch("2031-06-01", nil, nil, { "BRIDGE", "COUNCIL", "HARVEST", "FESTIVAL", "RADIO", "bad", "TOOLONGAWORD", "BRIDGE", "WINTER" })
local hidden = {}
for _i, w in ipairs(nws.words) do hidden[w.word] = true end
check(#nws.words == 8 and hidden.BRIDGE and hidden.COUNCIL and hidden.HARVEST and hidden.FESTIVAL and hidden.RADIO and hidden.WINTER and not hidden.bad,
    "a word search hides the words it's given first, and fills up from its own list")
-- the day's word search with a paper
local pn = { store = { daily = { enabled = true } }, save = function() end, saveSoon = function() end }
Pz.edition = function() return paper end
local wsn = Pz.dayWords(pn)
local from_news = 0
for _i, w in ipairs(wsn.words) do if by[w.word] then from_news = from_news + 1 end end
check(wsn.src == "2031-06-01" and #wsn.words == 8 and from_news >= 6 and pn.store.daily.puzzles.words.grid == wsn.grid, "with a paper: its words are hidden (" .. from_news .. " of 8), and the puzzle is kept")
Pz.edition = function() error("not asked again") end
local again_ws = Pz.dayWords(pn)
local same_w = again_ws.grid == wsn.grid and #again_ws.words == #wsn.words
for i, w in ipairs(wsn.words) do
    local o = again_ws.words[i]
    if not o or o.word ~= w.word or o.x ~= w.x or o.y ~= w.y or o.dx ~= w.dx or o.dy ~= w.dy then same_w = false end
end
check(same_w, "asked again: the kept puzzle, letter for letter, without reading the paper")
local paper2 = { day = "2031-06-01", sections = { { topic = "World", items = { { title = "Lighthouse keeper counts seven ships in the northern harbour", text = "The keeper kept a tally. Ships passed all morning." } } } } }
Pz.edition = function() return paper2 end
check(Pz.freshen(pn) == false and Pz.dayWords(pn).grid == wsn.grid, "the same day's paper fetched again: the puzzle stays (its paper is the same day's)")
paper2.day = "2031-06-02"
check(Pz.freshen(pn) == true and Pz.dayWords(pn).grid ~= wsn.grid and Pz.dayWords(pn).src == "2031-06-02", "a newer paper, the puzzle not started: made again from it")
Pz.wordFound(pn, 1)
paper2.day = "2031-06-03"
local started = Pz.dayWords(pn).grid
check(Pz.freshen(pn) == false and Pz.dayWords(pn).grid == started and select(2, Pz.dayWords(pn))[1] == true, "once a word is found the puzzle isn't changed under you")
pn.store.daily.puzzles.words.grid = "abc"
Pz.edition = function() return nil end
check(Pz.dayWords(pn).src == "list" and #Pz.dayWords(pn).grid == 100, "a kept puzzle that makes no sense: a new one")
check(Scr.statusText("words", { found = 2, of = 8, news = true }) == "2 of 8 found. The words are from the paper's stories." and Scr.statusText("words", { found = 2, of = 8 }) == "2 of 8 found.",
    "the page says when the words are the paper's")

-- the crossword
check(Pz.clueFrom("BRIDGE", "Council votes to keep the old bridge open through the winter") == "Council votes to keep the old _____ open through the winter",
    "a clue from the paper: the headline with the word left out")
check(Pz.clueFrom("BRIDGE", "The Bridge stays, and the bridge is sound.") == "The _____ stays, and the _____ is sound.", "…wherever it's written, capitals or not")
check(Pz.clueFrom("RAIN", "Rain is forecast.") == nil and Pz.clueFrom("RAIN", "Trains run late again today") == nil and Pz.clueFrom("RAIN", nil) == nil,
    "too little left to go on, or the word only inside another: no clue")
local long_clue = Pz.clueFrom("SIGNAL", string.rep("Many words come before it in this very long sentence and ", 3) .. "the radio finds the strongest signal at last, " .. string.rep("and many more words follow after it ", 4))
check(long_clue and #long_clue <= Pz.CLUE_LENGTH + 12 and long_clue:find("_____", 1, true) and long_clue:sub(1, 3) == "\u{2026}" and long_clue:sub(-3) == "\u{2026}",
    "a long sentence is cut round the gap (" .. #(long_clue or "") .. " bytes)")
local bank_ok, bank_n = true, 0
for word, clue in pairs(Pz.CLUES) do
    bank_n = bank_n + 1
    if not word:match("^%u+$") or clue:upper():find(word, 1, true) then bank_ok = false end
end
check(bank_ok and bank_n >= 150, "the puzzles' own clues: one a word, none giving its word away (" .. bank_n .. ")")
local function crossOK(cw)
    local cells = Pz.crossCells(cw)
    local grid = {}
    for idx, c in pairs(cells) do grid[idx] = c.letter end
    -- every run of two or more letters, across or down, must be one of the words, and only those
    local runs, want = {}, {}
    for _i, w in ipairs(cw.words) do want[w.d .. ":" .. w.x .. ":" .. w.y .. ":" .. w.word] = true end
    for y = 1, cw.rows do
        local x = 1
        while x <= cw.cols do
            if grid[(y - 1) * cw.cols + x] and not (x > 1 and grid[(y - 1) * cw.cols + x - 1]) then
                local wd, k = "", x
                while k <= cw.cols and grid[(y - 1) * cw.cols + k] do wd = wd .. grid[(y - 1) * cw.cols + k]; k = k + 1 end
                if #wd > 1 then runs["a:" .. x .. ":" .. y .. ":" .. wd] = true end
            end
            x = x + 1
        end
    end
    for x = 1, cw.cols do
        for y = 1, cw.rows do
            if grid[(y - 1) * cw.cols + x] and not (y > 1 and grid[(y - 2) * cw.cols + x]) then
                local wd, k = "", y
                while k <= cw.rows and grid[(k - 1) * cw.cols + x] do wd = wd .. grid[(k - 1) * cw.cols + x]; k = k + 1 end
                if #wd > 1 then runs["d:" .. x .. ":" .. y .. ":" .. wd] = true end
            end
        end
    end
    for k in pairs(runs) do if not want[k] then return false, "a run that's no word: " .. k end end
    for k in pairs(want) do if not runs[k] then return false, "a word that isn't there: " .. k end end
    -- every word crosses another; numbers go up left to right, top to bottom; across before down
    local last_n, last_d
    for _i, w in ipairs(cw.words) do
        local crosses = false
        for k = 0, #w.word - 1 do
            local c = cells[(w.y + (w.d == "d" and k or 0) - 1) * cw.cols + w.x + (w.d == "a" and k or 0)]
            if c.a and c.d then crosses = true end
        end
        if not crosses then return false, w.word .. " crosses nothing" end
        if w.d == last_d and w.n <= last_n then return false, "numbers out of order" end
        last_n, last_d = w.n, w.d
        if cells[(w.y - 1) * cw.cols + w.x].n ~= w.n then return false, "a word's number isn't in its first square" end
    end
    return true
end
local all_ok, why_not, fewest_w, widest = true, nil, 99, 0
for d = 1, 25 do
    local Rd = Pz.rng("t" .. d)
    local es = {}
    for _i, w in ipairs(Pz.WORD_LIST) do if Pz.CLUES[w] then es[#es + 1] = { word = w, clue = Pz.CLUES[w] } end end
    Rd.shuffle(es)
    local cw = Pz.crossword("t" .. d, es)
    local okc, whyc = crossOK(cw)
    if not okc then all_ok, why_not = false, whyc end
    fewest_w, widest = math.min(fewest_w, #cw.words), math.max(widest, cw.cols, cw.rows)
end
check(all_ok, "25 crosswords: every run of letters is one of the words, every word crosses another, numbered as crosswords are" .. (why_not and (" — " .. why_not) or ""))
check(fewest_w >= 7 and widest <= Pz.CROSS_SIZE, "…seven words or more each (" .. fewest_w .. "), none wider than " .. Pz.CROSS_SIZE .. " squares")
local few = Pz.crossword("x", { { word = "BRIDGE", clue = "c1" }, { word = "bad", clue = "no" }, { word = "RADIO", clue = "" }, { word = "GARDEN", clue = "c2" }, { word = "BRIDGE", clue = "again" } })
check(#few.words == 2 and crossOK(few) and #Pz.crossword("x", {}).words == 0, "odd entries are passed over; nothing to work with gives an empty one, not an error")
-- the day's crossword, from the paper
local pc = { store = { daily = { enabled = true } }, save = function() end, saveSoon = function() end }
Pz.edition = function() return paper end
local dcw, dfill = Pz.dayCross(pc)
local news_clues, own_clues = 0, 0
for _i, w in ipairs(dcw.words) do
    if w.clue:find("_____", 1, true) then news_clues = news_clues + 1 else own_clues = own_clues + 1 end
    if w.clue:upper():find(w.word, 1, true) then news_clues = -99 end
end
check(dcw.src == "2031-06-01" and crossOK(dcw) and news_clues >= 3 and #dfill == dcw.cols * dcw.rows and not dfill:find("[^%.]"),
    "with a paper: a crossword with clues from its stories (" .. news_clues .. " of them, " .. own_clues .. " of the puzzles' own to fill it), nothing written yet")
Pz.edition = function() error("not asked again") end
local dcw2 = Pz.dayCross(pc)
local same_c = #dcw2.words == #dcw.words
for i, w in ipairs(dcw.words) do
    local o = dcw2.words[i]
    if not o or o.word ~= w.word or o.clue ~= w.clue or o.x ~= w.x or o.y ~= w.y or o.d ~= w.d or o.n ~= w.n then same_c = false end
end
check(same_c, "asked again: the kept crossword, word for word, without reading the paper")
local ccells = Pz.crossCells(dcw)
local a_cell, a_letter
for idx, c in pairs(ccells) do if not a_cell or idx < a_cell then a_cell, a_letter = idx, c.letter end end
local hole
for i = 1, dcw.cols * dcw.rows do if not ccells[i] and not hole then hole = i end end
check(Pz.crossSet(pc, a_cell, a_letter:lower()) == true and select(2, Pz.dayCross(pc)):sub(a_cell, a_cell) == a_letter and Pz.crossSet(pc, a_cell, a_letter) == false,
    "a letter written in a square (small or capital); the same again: nothing")
check((hole == nil or Pz.crossSet(pc, hole, "A") == false) and Pz.crossSet(pc, a_cell, "AB") == false and Pz.crossSet(pc, a_cell, "5") == false and Pz.crossSet(pc, 0, "A") == false,
    "where there's no square, or what isn't a letter: nothing")
local wrong_c, left_c, done_c = Pz.crossCheck(dcw, select(2, Pz.dayCross(pc)))
local squares = 0
for _k in pairs(ccells) do squares = squares + 1 end
check(next(wrong_c) == nil and left_c == squares - 1 and done_c == false and Pz.finished(pc).cross == false, "one right letter: none wrong, the rest to go")
local other = a_letter == "Z" and "Y" or "Z"
Pz.crossSet(pc, a_cell, other)
wrong_c = Pz.crossCheck(dcw, select(2, Pz.dayCross(pc)))
check(wrong_c[a_cell] == true, "a wrong letter is found by the check")
Pz.edition = function() return { day = "2031-06-09", sections = paper.sections } end
check(Pz.freshen(pc) == false, "a crossword with a letter in it isn't made again for a newer paper")
check(Pz.crossSet(pc, a_cell, "") == true and Pz.freshen(pc) == true and Pz.dayCross(pc).src == "2031-06-09", "rubbed out, it's untouched: made again from the newer paper")
dcw = Pz.dayCross(pc)
for idx, c in pairs(Pz.crossCells(dcw)) do Pz.crossSet(pc, idx, c.letter) end
local fin_c, fin_cn = Pz.finished(pc)
check(select(3, Pz.crossCheck(dcw, select(2, Pz.dayCross(pc)))) == true and fin_c.cross == true and fin_cn == 1, "every square right: solved, and counted")
Pz.crossClear(pc)
check(not select(2, Pz.dayCross(pc)):find("%u") and Pz.finished(pc).cross == false, "Start again: every square empty")
pc.store.daily.puzzles.cross.words[1].w = "lower"
Pz.edition = function() return nil end
local own_cw = Pz.dayCross(pc)
local own_only = true
for _i, w in ipairs(own_cw.words) do if Pz.CLUES[w.word] ~= w.clue then own_only = false end end
check(own_cw.src == "list" and crossOK(own_cw) and own_only and #own_cw.words >= 7, "a kept crossword that makes no sense is made again; without a paper: the puzzles' own words and clues")
-- the page's part
local cc = Pz.crossCells({ cols = 5, rows = 3, words = { { word = "ABCDE", x = 1, y = 1, d = "a", n = 1 }, { word = "CXY", x = 3, y = 1, d = "d", n = 2 }, { word = "YZ", x = 3, y = 3, d = "a", n = 3 } } })
check(Scr.crossStep(cc, 5, 3, 1, "e") == 2 and Scr.crossStep(cc, 5, 3, 5, "e") == nil and Scr.crossStep(cc, 5, 3, 3, "s") == 8 and Scr.crossStep(cc, 5, 3, 13, "n") == 8,
    "the 5-way in a crossword: the next square that way")
check(Scr.crossStep(cc, 5, 3, 1, "s") == 8 and Scr.crossStep(cc, 5, 3, 5, "s") == 14 and Scr.crossStep(cc, 5, 3, 14, "n") == 4 and Scr.crossStep(cc, 5, 3, 1, "w") == nil,
    "…with none in its row or column, the nearest lying that way; none at all: stay")
-- (A B C D E / . . X . . / . . Y Z .: the gaps either side of X have a square above and one beside them)
check(table.concat(Scr.crossBlacks(cc, 5, 3), ",") == "7,9", "gaps with squares on two sides or more are blacked out, so they don't pass for squares: " .. table.concat(Scr.crossBlacks(cc, 5, 3), ","))
check(Scr.clueHead({ d = "a", n = 4 }) == "4 Across" and Scr.clueHead({ d = "d", n = 12 }) == "12 Down", "a clue's heading")
local listed = Scr.clueList({ words = { { d = "a", n = 1, clue = "First", word = "ABCDE" }, { d = "d", n = 2, clue = "Second", word = "CXY" } } })
check(listed == "ACROSS\n1. First (5)\n\nDOWN\n2. Second (3)", "all the clues as a list, each with its word's length")
check(Scr.statusText("cross", { left = 31 }) == "31 squares to go." and Scr.statusText("cross", { left = 0, wrong = 2 }) == "2 letters aren't right (marked)."
    and Scr.statusText("cross", { left = 4, wrong = 0, checked = true, news = true }) == "Right so far. The clues are from the paper's stories."
    and Scr.statusText("cross", { done = true }):find("Solved", 1, true), "the line under the crossword")
check(Scr.helpText("cross", true):find("Tap a square", 1, true) and Scr.helpText("cross", false, true):find("letters: write", 1, true) and Scr.helpText("cross", false, false):find("Press: the next letter", 1, true),
    "how to do the crossword, for touch, a keyboard and the 5-way alone")

-- circling a word: where a stroke ends, straightened; the ring drawn round a found word
check(table.concat({ Scr.snap(2, 3, 7, 3, 10) }, ",") == "7,3" and table.concat({ Scr.snap(2, 3, 7, 4, 10) }, ",") == "7,3", "a stroke across, a square off at its end: still across")
check(table.concat({ Scr.snap(4, 8, 5, 2, 10) }, ",") == "4,2", "a stroke up, a little crooked: straight up")
check(table.concat({ Scr.snap(2, 2, 6, 5, 10) }, ",") == "6,6" and table.concat({ Scr.snap(6, 6, 2, 3, 10) }, ",") == "2,2", "a stroke nearer a diagonal: the diagonal, as long as the stroke was")
check(table.concat({ Scr.snap(8, 8, 10, 11, 10) }, ",") == "10,10" and table.concat({ Scr.snap(3, 2, 0, -1, 10) }, ",") == "2,1", "a diagonal that would leave the letters stops at the edge")
check(table.concat({ Scr.snap(5, 5, 5, 5, 10) }, ",") == "5,5", "no stroke at all: the same square")
local ring = Scr.ringPoints(100, 100, 300, 100, 20)
local rx1, rx2, ry1, ry2, on_ring = 1e9, -1e9, 1e9, -1e9, true
for _i, pt in ipairs(ring) do
    rx1, rx2, ry1, ry2 = math.min(rx1, pt[1]), math.max(rx2, pt[1]), math.min(ry1, pt[2]), math.max(ry2, pt[2])
    -- (every point is 20 from the line between the two middles)
    local nearest = math.max(100, math.min(300, pt[1]))
    local d = math.sqrt((pt[1] - nearest) ^ 2 + (pt[2] - 100) ^ 2)
    if math.abs(d - 20) > 0.01 then on_ring = false end
end
check(on_ring and math.abs(rx1 - 80) < 0.5 and math.abs(rx2 - 320) < 0.5 and math.abs(ry1 - 80) < 0.5 and math.abs(ry2 - 120) < 0.5 and #ring > 400,
    "the ring round a found word: two sides and two round ends, all the same way off its letters (" .. #ring .. " points)")
local diag = Scr.ringPoints(0, 0, 100, 100, 10)
local off_diag = true
for _i, pt in ipairs(diag) do
    local tpar = math.max(0, math.min(100, (pt[1] + pt[2]) / 2))
    if math.abs(math.sqrt((pt[1] - tpar) ^ 2 + (pt[2] - tpar) ^ 2) - 10) > 0.01 then off_diag = false end
end
check(off_diag and #Scr.ringPoints(50, 50, 50, 50, 10) > 16, "…round a diagonal word too, and round a single square without dividing by nothing")
local psrc, ssrc = read(PLUGIN .. "/gzreader_puzzles.lua"), read(PLUGIN .. "/gzreader_puzzlescreen.lua")
check(not psrc:find("math.random", 1, true) and not psrc:find("socket", 1, true) and not psrc:find("Api", 1, true), "made on the Kindle from the date: no network, not the Kindle's own random numbers")
check(ssrc:find('PzPan = { GestureRange:new{ ges = "pan", range = range } }', 1, true) and ssrc:find('PzHoldPan = { GestureRange:new{ ges = "hold_pan", range = range } }', 1, true)
    and ssrc:find('PzPanRelease = { GestureRange:new{ ges = "pan_release", range = range } }', 1, true) and ssrc:find('PzHoldRelease = { GestureRange:new{ ges = "hold_release", range = range } }', 1, true)
    and ssrc:find("self:circle(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y, ges.end_pos.x - self.dimen.x, ges.end_pos.y - self.dimen.y)", 1, true),
    "a word can be drawn along quickly (a swipe), slowly (a pan) or after a pause (a hold and pan)")
check(Scr.helpText("words", true):find("Draw along a word to circle it", 1, true) and Scr.helpText("words", true):find("tap its first letter", 1, true), "the word search says so, and the two taps still work")
check(ssrc:find('self.key_events["PzKey" .. letter] = { { letter }, event = "PzKey", args = letter }', 1, true) and ssrc:find('local n = ("QWERTYUIO"):find(letter, 1, true)', 1, true)
    and ssrc:find('if self.kind == "cross" then return self:letterIn(letter) end', 1, true), "a letter key writes in the crossword, and is 1–9, rub out, check and start again elsewhere")
check(ssrc:find('PzPanel = { { "Menu" } }', 1, true) and ssrc:find("Paper.pulledDown(ges)", 1, true), "Menu and a swipe from the top are the quick panel there too")
local dsrc2 = read(PLUGIN .. "/gzreader_dailyscreen.lua")
Pz.edition = real_edition
check(dsrc2:find('if what == "puzzles" then', 1, true) and dsrc2:find("if self.foot.puzzles then Paper.puzzles(self.plugin) end", 1, true) and dsrc2:find('foot("puzzles", f.puzzles, S(6))', 1, true),
    "the paper opens them: a tap on Puzzles, or the 5-way to it and Press")

print("== the paper with keys: the 5-way goes every way, letters open things")
-- a page as it's laid out: TODAY's box, the lead across, two columns, the foot
local stops = {
    { id = "diary", x = 12, y = 100, w = 576, h = 30 },
    { id = 1, x = 8, y = 140, w = 584, h = 200 },
    { id = 2, x = 8, y = 346, w = 288, h = 120 }, { id = 3, x = 8, y = 472, w = 288, h = 150 }, { id = 4, x = 8, y = 628, w = 288, h = 100 },
    { id = 5, x = 304, y = 346, w = 288, h = 220 }, { id = 6, x = 304, y = 572, w = 288, h = 130 },
    { id = "fetch", x = 8, y = 775, w = 100, h = 20 }, { id = "type", x = 128, y = 775, w = 30, h = 20 }, { id = "puzzles", x = 170, y = 775, w = 60, h = 20 },
}
local function walk(from, sides)
    local out = {}
    for side in sides:gmatch(".") do
        from = Paper.neighbour(stops, from, side)
        out[#out + 1] = tostring(from)
        if from == nil then break end
    end
    return table.concat(out, " ")
end
check(walk("diary", "sssss") == "1 2 3 4 fetch", "down: TODAY, the lead, down the left column, to the foot (" .. walk("diary", "sssss") .. ")")
check(walk("fetch", "nnnnn") == "4 3 2 1 diary", "up: the same way back")
check(walk(2, "e") == "5" and walk(3, "e") == "5" and walk(4, "e") == "6", "right: to the story beside it in the next column")
check(walk(5, "w") == "2" and walk(6, "w") == "4", "left: back to the one beside it (" .. walk(5, "w") .. ", " .. walk(6, "w") .. ")")
check(walk(5, "ss") == "6 puzzles" and walk(5, "n") == "1", "the right column: down it to the foot's nearest, up to the lead")
check(walk("fetch", "ee") == "type puzzles" and walk("puzzles", "ww") == "type fetch", "along the foot both ways: Fetch, Aa, Puzzles")
check(walk("type", "n") == "4" and walk("puzzles", "n") == "4", "up from Aa or Puzzles: the story above")
check(walk(5, "e") == "nil" and walk(2, "w") == "nil" and walk("diary", "n") == "nil" and walk("fetch", "s") == "nil" and walk("puzzles", "e") == "nil" and walk(1, "e") == "nil",
    "nothing that way: no move (the page turns then)")
check(Paper.neighbour(stops, "gone", "s") == "diary" and Paper.neighbour({}, 1, "s") == nil, "a focus that isn't there: the first stop; an empty page: nothing")
local three = { { id = 1, x = 0, y = 0, w = 100, h = 50 }, { id = 2, x = 110, y = 0, w = 100, h = 90 }, { id = 3, x = 220, y = 0, w = 100, h = 40 }, { id = 4, x = 220, y = 46, w = 100, h = 40 } }
check(Paper.neighbour(three, 1, "e") == 2 and Paper.neighbour(three, 2, "e") == 3 and Paper.neighbour(three, 4, "w") == 2 and Paper.neighbour(three, 1, "s") == nil, "three columns: one column at a time")
check(Paper.neighbour(stops, 5, "w") == 2 and Paper.neighbour(stops, 6, "w") == 4 and Paper.step(stops, 6, "w", { from = 3, to = 6, side = "e" }) == 3
    and Paper.step(stops, 5, "w", { from = 4, to = 5, side = "e" }) == 4, "straight back the way you came returns to where you were (Right then Left ends where it began)")
check(Paper.step(stops, 6, "w", { from = 3, to = 5, side = "e" }) == 4 and Paper.step(stops, 6, "n", { from = 3, to = 6, side = "e" }) == 5
    and Paper.step(stops, 6, "w", { from = 99, to = 6, side = "e" }) == 4 and Paper.step(stops, 6, "w", nil) == 4, "…only straight back, from where the last move ended, to something still there")
check(dsrc2:find("local to = Paper.step(self:stops(), self.focus, side, self.came)", 1, true) and dsrc2:find("self.came = { from = self.focus, to = to, side = side }", 1, true), "the page remembers its last move")
check(table.concat(Paper.STORY_KEYS) == "QWERTYUIO" and Paper.PAGE_KEYS.P == "puzzles" and Paper.PAGE_KEYS.F == "fetch" and Paper.PAGE_KEYS.D == "diary", "letters: Q–O for the stories, P Puzzles, F Fetch, D TODAY")
local taken = {}
for _i, k in ipairs(Paper.STORY_KEYS) do taken[k] = true end
local clash = false
for k in pairs(Paper.PAGE_KEYS) do if taken[k] then clash = true end end
check(not clash, "no letter means two things")
check(dsrc2:find('GzLeft = { { "Left" }, event = "GzGo", args = "w" }', 1, true) and dsrc2:find('GzRight = { { "Right" }, event = "GzGo", args = "e" }', 1, true)
    and dsrc2:find('GzUp = { { "Up" }, event = "GzGo", args = "n" }', 1, true) and dsrc2:find('GzDown = { { "Down" }, event = "GzGo", args = "s" }', 1, true)
    and not dsrc2:find('{ "Down", "Right" }', 1, true), "the four arrows are four ways (Right isn't Down any more)")
check(dsrc2:find('self.key_events["GzStory" .. n] = { { letter }, { tostring(n) }, event = "GzStory", args = n }', 1, true)
    and dsrc2:find("self.keyboard = self.keys and Device:hasKeyboard() and true or false", 1, true), "a story's letter or number opens it, only on a Kindle with a keyboard")
check(dsrc2:find('foot("fetch", f.fetch, S(4))', 1, true) and dsrc2:find('foot("type", f.type, S(6))', 1, true) and dsrc2:find('out[#out + 1] = { id = "diary"', 1, true),
    "the 5-way reaches everything: TODAY, every story, Fetch, Aa, Puzzles")
end)()

;(function()
print("== the AI edition: a summary a story, pages of articles")
local Dz = require("gzreader_daily")
local AI = require("gzreader_ai")
local long = string.rep("The council met on Monday and agreed to keep the old bridge open through the winter. ", 12)
local function edition()
    return { day = Dz.day(), at = os.time(), sections = {
        { topic = "World", items = { { title = "Bridge stays open", text = long, source = "Example World", link = "https://example.com/world/bridge" },
            { title = "Short one", text = "Rain is forecast.", source = "Example World" } } },
        { topic = "Technology", items = { { title = "A radio that tunes itself", text = long .. long, source = "Example Tech" } } },
    } }
end
local pl = { store = { daily = { enabled = true } }, save = function() end }
check(Dz.aiWanted(pl) == false and Dz.aiOn(pl) == false, "the AI edition is off as it comes")
pl.store.daily.ai = true
check(Dz.aiWanted(pl) == true and Dz.aiOn(pl) == false, "ticked without an AI key: not on, nothing will be asked")
AI.settings(pl).claude.key = "sk-ant-example"
check(Dz.aiOn(pl) == true and table.concat(AI.uses(pl), "|"):find("The daily paper's AI edition", 1, true), "with the AI connection set up: on, and the AI page lists it")
-- what's asked
local q = Dz.summaryQuestion({ title = "Bridge stays open", text = string.rep("x", 20000), link = "https://example.com/world/bridge", source = "Example World" })
check(q.system == Dz.SUMMARY_SYSTEM and q.text:find("Headline: Bridge stays open", 1, true) and #q.text < Dz.AI_TEXT + 200 and q.max_tokens == 300,
    "a story's headline and the start of its text are asked about (" .. #q.text .. " bytes)")
check(not q.text:find("example.com", 1, true) and not q.system:find("example.com", 1, true), "its address isn't sent")
;(function()
    -- the AI's order: asked with the headlines, sections and how each begins; each story once
    local oe = { day = Dz.day(), at = os.time(), sections = {
        { topic = "World", items = { { title = "Storm hits coast", text = "Winds of 100 mph" }, { title = "Talks stall", text = "Leaders met" } } },
        { topic = "Good news", items = { { title = "Puppies rescued", text = "Twelve puppies" } } },
        { topic = "Science", items = { { title = "New comet", text = "Astronomers saw" } } } } }
    oe.order = Dz.mix(oe, oe.day)
    local asked_q
    local okq = Dz.aiOrder(oe, function(question)
        asked_q = question
        local list = Dz.ordered(oe)
        local good
        for k, st in ipairs(list) do if st.topic == "Good news" then good = k end end
        local other = good == 1 and 2 or 1
        return 'Here: {"order":[' .. good .. ', 99, ' .. good .. ', ' .. other .. ']}'
    end)
    local first = Dz.ordered(oe)[1]
    check(okq and oe.ordered_by_ai and first.item.title == "Puppies rescued" and #Dz.ordered(oe) == 4,
        "the AI edition: the AI puts the paper in order (its first story first; the ones it left out after, none twice)")
    check(asked_q and asked_q.system == Dz.ORDER_SYSTEM and asked_q.text:find("[Good news] Puppies rescued: Twelve puppies", 1, true)
        and Dz.ORDER_SYSTEM:find("good, hopeful or uplifting", 1, true),
        "…asked with each story's section, headline and how it begins, to open with good news")
    -- an answer with no usable order: the mix stays
    local mixed = Dz.mix(oe, oe.day)
    oe.order, oe.ordered_by_ai = mixed, nil
    local okn, whyn = Dz.aiOrder(oe, function() return "I can't do that." end)
    check(okn == false and whyn and oe.order == mixed and not oe.ordered_by_ai, "…no order in its answer: the paper keeps its mix")
    check(Dz.orderFrom('{"order":[1]}', Dz.ordered(oe)) == nil, "…an order naming too few stories isn't trusted")
    local dsrc2 = io.open(PLUGIN .. "/gzreader_daily.lua"):read("*a")
    check(dsrc2:find('local ordered, owhy = Daily.aiOrder(edition, function(q) return AI.complete(ai, q) end, how.style == "mixed_good")', 1, true)
        and dsrc2:find("edition.summaries, edition.summaries_asked, why = Daily.addSummaries", 1, true)
        and dsrc2:find("Daily.aiOrder(edition", 1, true) < dsrc2:find("edition.summaries, edition.summaries_asked", 1, true),
        "…asked before the summaries (they go to the paper's first stories)")
end)()
;(function()
    print("== the story order's settings")
    local old_ed = Dz.load()
    local function mk() return { day = "2026-12-03", at = os.time(), sections = {
        { topic = "World", items = { { title = "w1" }, { title = "w2" }, { title = "w3" } } },
        { topic = "Science", items = { { title = "s1" }, { title = "s2" } } },
        { topic = "Good news", items = { { title = "g1" }, { title = "g2" } } } } } end
    local function titles(e) local t = {} for _i, st in ipairs(Dz.ordered(e)) do t[#t + 1] = st.item.title end return table.concat(t, " ") end
    local pl = { store = { daily = { enabled = true } }, save = function() end }
    check(Dz.orderStyle(pl) == "mixed_good" and Dz.aiOrders(pl) == true and Dz.how(pl).ai == false,
        "as it comes: mixed, good news first; the AI's order on (used once the AI edition is ticked)")
    pl.store.daily.order = "whatever"
    check(Dz.orderStyle(pl) == "mixed_good", "an unknown order: the usual one")
    local e = Dz.arrange(mk(), { style = "sections" })
    check(e.order == nil and titles(e) == "w1 w2 w3 s1 s2 g1 g2", "By section: each section's stories together, in the feeds' order")
    check(Dz.front(e, 3)[1].title == "w1" and Dz.front(e, 3)[2].title == "s1", "…the front page takes each section's first")
    e = Dz.arrange(mk(), { style = "mixed_good" })
    check(Dz.ordered(e)[1].topic == "Good news", "Mixed, good news first: good news leads")
    local leads, early = 0, 0
    for d = 1, 28 do
        local m = mk(); m.day = "2026-12-" .. string.format("%02d", d)
        Dz.arrange(m, { style = "mixed" })
        local list = Dz.ordered(m)
        if list[1].topic == "Good news" then leads = leads + 1 end
        for k = 1, 3 do if list[k].topic == "Good news" then early = early + 1 end end
        local last
        for _i, st in ipairs(list) do assert(st.topic ~= last or _i == #list); last = st.topic end
    end
    check(leads < 28 and leads > 0, "Mixed: good news isn't put first (it led " .. leads .. " of 28 days)")
    local m1, m2 = Dz.arrange(mk(), { style = "mixed" }), Dz.arrange(mk(), { style = "mixed" })
    check(titles(m1) == titles(m2) and #Dz.ordered(m1) == 7, "…the same order all day, every story once")
    -- the AI's order, kept beside the others
    local a = mk()
    Dz.arrange(a, { style = "sections", ai = true })
    local oka = Dz.aiOrder(a, function() return '{"order":[7,6,5,4,3,2,1]}' end, false)
    check(oka and titles(a) == "g2 g1 s2 s1 w3 w2 w1" and a.ai_order and a.ordered_by_ai, "the AI's order used, and kept")
    Dz.arrange(a, { style = "sections", ai = false })
    check(titles(a) == "w1 w2 w3 s1 s2 g1 g2" and not a.ordered_by_ai, "…the AI's order turned off: the chosen order, at once")
    Dz.arrange(a, { style = "sections", ai = true })
    check(titles(a) == "g2 g1 s2 s1 w3 w2 w1", "…and on again: the AI's, without asking again")
    local q_good = Dz.orderQuestion(Dz.ordered(mk()))
    local q_plain = Dz.orderQuestion(Dz.ordered(mk()), false)
    check(q_good.system:find("good news", 1, true) and not q_plain.system:find("good", 1, true),
        "the AI is asked to put good news first only with Mixed, good news first")
    -- Settings → Daily paper → Story order
    local saved = 0
    local sp = { store = { daily = { enabled = true } }, save = function() saved = saved + 1 end }
    local kept = mk(); Dz.arrange(kept, Dz.how(sp)); Dz.keep(kept)
    local rows = Paper.settingsItems(sp)
    local orow
    for _i, r in ipairs(rows) do if r.text == "Story order" then orow = r end end
    check(orow and orow.text_func() == "Story order: Mixed, good news first" and orow.sub_item_table_func, "Settings → Daily paper → Story order, showing the choice")
    local sub = orow.sub_item_table_func()
    check(#sub == 4 and sub[1].text == "Mixed, good news first" and sub[2].text == "Mixed" and sub[3].text == "By section"
        and sub[1].radio and sub[1].checked_func() and not sub[3].checked_func() and sub[4].text == "The AI chooses the order"
        and sub[4].enabled_func() == false, "…three orders to choose from, and the AI's (greyed without the AI edition)")
    sub[3].callback()
    check(sp.store.daily.order == "sections" and saved == 1 and sub[3].checked_func() and orow.text_func() == "Story order: By section",
        "By section chosen: kept")
    Dz.loaded, Dz.edition = false, nil
    check(titles(Dz.load()) == "w1 w2 w3 s1 s2 g1 g2", "…today's kept paper is in the new order at once")
    sub[1].callback()
    check(sp.store.daily.order == nil and Dz.ordered(Dz.load())[1].topic == "Good news", "back to Mixed, good news first: not stored (the usual)")
    local aiOk = Dz.aiOn
    Dz.aiOn = function() return true end
    sp.store.daily.ai = true
    check(sub[4].enabled_func() and sub[4].checked_func() and orow.text_func() == "Story order: the AI's", "the AI edition: the AI chooses, as it comes")
    sub[4].callback()
    check(sp.store.daily.ai_order == false and not sub[4].checked_func() and Dz.how(sp).ai == false, "…unticked: the order above")
    sub[4].callback()
    check(sp.store.daily.ai_order == nil and Dz.how(sp).ai == true, "…ticked again")
    Dz.aiOn = aiOk
    net.usb = true
    local urows = Paper.settingsItems(sp)
    local has
    for _i, r in ipairs(urows) do if r.text == "Story order" then has = true end end
    check(has, "a Kindle without Wi-Fi has Story order too (the paper from the sync is put in it)")
    net.usb = false
    local dsrc3 = io.open(PLUGIN .. "/gzreader_daily.lua"):read("*a")
    check(dsrc3:find("Daily.arrange(edition, Daily.how(plugin))\n        Daily.keep(edition)", 1, true)
        and dsrc3:find("if not edition then return nil, err end\n        Daily.arrange(edition, how)", 1, true),
        "a paper fetched, or brought by the sync page, is put in the chosen order")
    if old_ed then Dz.keep(old_ed) else Dz.loaded, Dz.edition = false, nil; os.remove(Dz.cachePath()) end
end)()
-- the summaries
local e = edition()
local asked = {}
local done, n, why = Dz.addSummaries(e, function(question) asked[#asked + 1] = question; return "  The council voted to keep the bridge open.\nIt will be reviewed in spring, the mayor said afterwards.  " end)
check(done == 2 and n == 2 and why == nil and #asked == 2, "each long story is asked for once (" .. done .. " of " .. n .. ")")
check(e.sections[1].items[1].summary == "The council voted to keep the bridge open. It will be reviewed in spring, the mayor said afterwards."
    and e.sections[2].items[1].summary ~= nil, "the answer is kept as the story's summary, on one line")
check(e.sections[1].items[2].summary == nil, "a story of a line or two is its own summary: not sent")
e = edition()
local calls = 0
done, n, why = Dz.addSummaries(e, function() calls = calls + 1; return nil, "the key was refused (401)" end)
check(done == 0 and why == "the key was refused (401)" and calls == 2 and e.sections[1].items[1].summary == nil, "a refused key: no summaries, and why")
local many = { day = Dz.day(), at = os.time(), sections = { { topic = "World", items = {} } } }
for i = 1, 8 do many.sections[1].items[i] = { title = "Story " .. i, text = long } end
calls = 0
done, n = Dz.addSummaries(many, function() calls = calls + 1; return nil, "no answer" end)
check(calls == Dz.AI_GIVE_UP and done == 0, "after " .. Dz.AI_GIVE_UP .. " failures in a row the rest aren't asked for")
calls = 0
local t = 0
done, n = Dz.addSummaries(many, function() calls = calls + 1; t = t + 100; return string.rep("A summary. ", 6) end, 250, function() return t end)
check(calls == 3 and done == 3, "it stops when its time is up (" .. calls .. " asked in 250 s)")
calls = 0
done = Dz.addSummaries(many, function() calls = calls + 1; return calls == 1 and "short" or string.rep("word ", 400) end)
check(many.sections[1].items[1].summary == nil or many.sections[1].items[1].summary ~= "short", "an answer of a word isn't a summary")
local longest = 0
for _i, it in ipairs(many.sections[1].items) do longest = math.max(longest, #(it.summary or "")) end
check(longest > 0 and longest <= Dz.AI_SUMMARY + 8, "a summary that runs on is cut (" .. longest .. " bytes)")
check(pcall(Dz.addSummaries, edition(), function() error("boom") end), "an error while asking doesn't end the paper")
-- the page
e = edition()
check(Paper.aiEdition(pl, e) == false, "an edition without summaries is the ordinary paper, even when ticked")
e.summaries, e.ai = 2, "claude"
check(Paper.aiEdition(pl, e) == true, "ticked, with summaries: the AI edition")
pl.store.daily.ai = nil
check(Paper.aiEdition(pl, e) == false, "unticked: the ordinary paper again, the same edition")
pl.store.daily.ai = true
check(Paper.aiColumns(600, 167) == 1 and Paper.aiColumns(1072, 300) == 1 and Paper.aiColumns(1860, 300) >= 2, "one article across a 6-inch page, two on a big one")
local art = Paper.articleText({ title = "Bridge stays open", source = "Example World", text = "The whole story.", summary = "The council voted." })
check(art:find("In brief (AI summary): The council voted.", 1, true) and art:find("The whole story.", 1, true)
    and art:find("In brief", 1, true) < art:find("The whole story.", 1, true), "an opened story: the summary first, said to be the AI's, then the whole of it")
check(not Paper.articleText({ title = "x", text = "The whole story." }):find("In brief", 1, true), "no summary: nothing added")
-- settings and the setup page
local arow
for _i, r in ipairs(Paper.settingsItems(pl)) do if r.text == "AI edition" then arow = r end end
check(arow and arow.enabled_func() == true and arow.checked_func() == true and arow.help_text:find("headline and text are sent", 1, true), "Settings → Daily paper → AI edition, saying what's sent")
arow.callback()
check(Dz.aiWanted(pl) == false and arow.checked_func() == false, "unticked there")
AI.clear(pl)
check(arow.enabled_func() == false, "without an AI key it can't be ticked")
local ps = Dz.pageState(pl)
check(ps.ai == false and ps.ai_ready == false, "the setup page knows: off, no key")
Dz.pageSave(pl, { enabled = "1", ai = "1" })
check(pl.store.daily.ai == true and Dz.aiOn(pl) == false, "ticked on the page before there's a key: kept, but nothing is asked until there is one")
Dz.pageSave(pl, { enabled = "1" })
check(pl.store.daily.ai == nil, "unticked on the page")
local dsrc3, ksrc = read(PLUGIN .. "/gzreader_dailyscreen.lua"), read(PLUGIN .. "/gzreader_daily.lua")
check(ksrc:find("local ai = Daily.aiOn(plugin) and require(\"gzreader_ai\").snapshot(plugin) or nil", 1, true)
    and ksrc:find("Daily.addSummaries(edition, function(q) return AI.complete(ai, q) end)", 1, true), "the paper's fetch asks through the AI connection, only when it's on")
check(not ksrc:find("Log%.%a+%([^\n]*item%.summary") and not ksrc:find("Log%.%a+%([^\n]*%.text") and not ksrc:find("Log%.%a+%([^\n]*item%.title"), "no story, headline or summary in the log")
check(dsrc3:find("built[i] = built[i] or self:block(stories[i], col_w, false, ai)", 1, true) and dsrc3:find("if first and not ai then", 1, true), "the pages lay every story out as an article")
end)()

local cl = read(PLUGIN .. "/gzreader_changelog.lua")
check(cl:find("Daily paper", 1, true) or cl:find("daily paper", 1, true), "the changelog tells about it")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
