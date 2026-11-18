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
local front = Daily.front(ed, 4)
check(#front == 4 and front[1].title == "A1" and front[2].title == "S last week" and front[3].title == "U1" and front[4].title == "B1",
    "the front page: each section's first story, then their seconds")
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
for i = 1, 20 do many_p.sections[1].items[i] = { title = "T" .. i, image = "https://img.example.com/" .. i .. ".jpg" } end
check(Daily.addPictures(many_p, "/dir", function() return JPG end, function() return true end) == Daily.MAX_PICTURES, Daily.MAX_PICTURES .. " pictures an edition at most")
check(Daily.picturePath({ img = "../../etc/passwd" }) == nil and Daily.picturePath({ img = "none.jpg" }) == nil and Daily.picturePath({}) == nil,
    "a picture's file: only a plain name in the pictures' folder, only when it's there")

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
check(Daily.enabled(plugin) == false and Daily.maybeRefresh(plugin, tomorrow) == false, "a Kindle without Wi-Fi: no paper")
local okr, errr
Daily.refresh(plugin, function(ok, err) okr, errr = ok, err end)
check(okr == false and errr == "usb", "… and asking says why")
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
check(#Paper.stories(nil) == 0, "no edition: no stories")
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
-- Home's folded newspaper
local sizes = { shadow = 3, pad = 6, margin = 2, top = 2, gutter = 14, mast_h = 24, rules_h = 7, lead_h = 20, line_h = 16 }
local L = Paper.homeLayout(576, 130, sizes)
check(L.lead and L.rows == 3 and L.w == 576 - 3 - 4 and L.h == 130 - 3 - 2 and L.col_w * 2 + sizes.gutter <= L.inner_w,
    "Home's newspaper: the sheet with room for its shadow, the lead headline and 3 rows of two")
L = Paper.homeLayout(576, 90, sizes)
check(L.lead and L.rows == 1, "a lower row: the lead and one row")
L = Paper.homeLayout(576, 50, sizes)
check(not L.lead and L.rows == 0, "a very low row: the name alone")
local items = { nil, nil, { callback = function() Paper.article(plugin, stories[1].item) end } }
shown = {}
package.loaded["ui/widget/textviewer"] = { new = function(_s, o) o.kind = "viewer"; return o end }
items[3].callback()
local viewer = shown[#shown]
check(viewer and viewer.kind == "viewer" and viewer.title == "First story & more" and viewer.text:find("Para one is here.", 1, true)
    and viewer.text:find("^Mine · " .. os.date("%A, %B ", os.time() - 2 * 3600)), "a story opens as text, its source and day first")
check(viewer.buttons_table[1][1].text == "QR code" and viewer.buttons_table[1][2].text == "Close", "with its link as a QR code, and Close")
package.loaded["ui/widget/qrmessage"] = { new = function(_s, o) o.kind = "qr"; return o end }
viewer.buttons_table[1][1].callback()
check(shown[#shown].kind == "qr" and shown[#shown].text == "https://news.example.com/1?a=1&b=2", "the QR code is the story's link")
local no_link = Paper.article(plugin, { title = "T", text = "x" })
check(#no_link.buttons_table[1] == 1 and no_link.buttons_table[1][1].text == "Close" and no_link.text == "x", "a story without a link: no QR code")
check(Paper.articleText({ title = "T", text = "short", link = "https://x.example.com/1", source = "S" }):find("only a summary", 1, true),
    "a short text says it's the feed's summary")
Daily.edition, Daily.loaded = nil, true
check(Paper.statusText(plugin) == "comes when Wi-Fi is on", "… and Home says when it comes")

print("== Settings → Home → Daily paper")
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
check(Paper.install(plugin) == false, "ZenOS not started yet: nothing registered")
rawset(_G, "__ZENOS_REGISTER_HOME_ITEM", function(id, build, opts)
    registered[id] = { id = id, build = build, label = opts.label, size = opts.size }
    return true
end)
check(Paper.install(plugin) == true and registered.daily_paper and registered.daily_paper.label == "Daily paper" and registered.daily_paper.size == "m",
    "Home gets a Daily paper widget (size M)")
plugin.store.daily.enabled = nil
local rows = Paper.settingsItems(plugin)
local function row(text) for _i, r in ipairs(rows) do if (r.text or (r.text_func and r.text_func())):find(text, 1, true) then return r end end end
check(row("Daily paper").checked_func() == false and row("Feeds").enabled_func() == false and row("Read the paper").enabled_func() == false,
    "off: the rest is greyed")
check(row("Daily paper").help_text:find("internet address", 1, true), "the switch says what a feed's site learns")
shown = {}
Paper.show(plugin)
check(shown[#shown] and shown[#shown].kind == "info" and shown[#shown].text:find("Settings → Home → Daily paper", 1, true), "opening the paper while it's off says where to turn it on")
saves = 0
check(Paper.onShelf(plugin) == false and Paper.shelfItem(plugin, {}, 300, 150) == nil, "off: no newspaper on the shelf")
row("Daily paper").callback()
check(Daily.enabled(plugin) and saves == 1 and home.rows.enabled.daily_paper ~= true and redrawn == 1,
    "turned on: kept, no row of its own on Home, Home drawn again")
check(Paper.onShelf(plugin) and row("On Home's bookshelf").checked_func() == true, "… the newspaper goes on Home's bookshelf")
check(type(rawget(_G, "__GZ_SHELF_PAPER")) == "function", "the shelf can ask for it")
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
check(#rows == 1 and rows[1].enabled == false and rows[1].text:find("Wi-Fi", 1, true), "a Kindle without Wi-Fi: Settings says the paper needs it")
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
    "Settings → Home → Daily paper → Whole stories: on, and says what it does, what it can't, and who sees the Kindle")
row("Whole stories").callback()
check(plugin.store.daily.full == false and row("Whole stories").checked_func() == false, "unticked")
row("Whole stories").callback()
check(plugin.store.daily.full == nil, "ticked again")
check(Paper.articleText({ title = "T", text = "x", link = "https://x.example.com/1", full = true }):find("From the story's own page", 1, true), "a whole story says where its text is from")
check(Daily.MAX_TEXT >= 12000, "a feed that carries whole stories is no longer cut at 4,000 bytes")

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
check(Paper.calendarOn(plugin) == false and plugin.store.daily.calendar == false and row("Today's calendar events").checked_func() == false, "Settings → Home → Daily paper → Today's calendar events: unticked")
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
    "Settings → Home → Daily paper → Weather: the switch, the town, the degrees")
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
check(opened and opened.section == "paper", "Settings → Home → Daily paper → Set up from a browser opens the page at Daily paper")

print("== wired in")
local main = read(PLUGIN .. "/main.lua")
check(main:find('section == "home"', 1, true) and main:find('require("gzreader_dailyscreen").settingsItems(self)', 1, true), "the plugin gives Settings → Home its Daily paper row")
check(main:find('require("gzreader_dailyscreen").install(self)', 1, true), "the plugin registers Home's widget at start")
local zs = read(REPO .. "/plugins/zenos.koplugin/modules/settings/zen_settings.lua")
check(zs:find('gz_section("home")', 1, true), "ZenOS's Settings asks GZreader for Home's rows")
local sh = read(REPO .. "/plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/shelf.lua")
check(sh:find('rawget(_G, "__GZ_SHELF_PAPER")', 1, true) and sh:find("opts.gz_home", 1, true) and sh:find("gz_paper = true", 1, true),
    "ZenOS's shelf asks for the newspaper, on Home's first shelf only")
check(sh:find("i == picked and slot.gz_paper", 1, true) and sh:find("slot.face:paintTo", 1, true) and sh:find("ctx.focusHomeTarget(slot.target)", 1, true),
    "… stands it on its side, and turns it to its front page when it's picked, as a book shows its cover")
check(read(REPO .. "/plugins/zenos.koplugin/modules/filebrowser/patches/home/widgets/strip_common.lua"):find("gz_home = true", 1, true), "Home's shelf says it's Home's")
local src = read(PLUGIN .. "/gzreader_daily.lua") .. read(PLUGIN .. "/gzreader_dailyscreen.lua")
check(not src:find("Log%.[a-z]+%([^\n]*%f[%w]url%f[%W][^\n]*%)") or not src:find("Log%.[a-z]+%([^\n]*[^%.]url[,%)]"), "no log line takes a feed's address")
local cl = read(PLUGIN .. "/gzreader_changelog.lua")
check(cl:find("Daily paper", 1, true) or cl:find("daily paper", 1, true), "the changelog tells about it")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
