--[[--
The daily paper: once a day, the news feeds you chose (RSS / Atom) fetched
over Wi-Fi and put together as one edition, kept on the Kindle to read all
day with Wi-Fi off. Home shows its front page (the "Daily paper" widget,
gzreader_dailyscreen.lua); a tap opens the whole paper.

  The Daily Paper                         Tuesday, November 17
  World
    Headline …                                        BBC News
    Headline …                                             NPR
  Technology
    …

- Off until it's turned on (Settings → Home and tabs → Daily paper): the feeds are
  other people's sites, and each fetch tells them this Kindle's address.
  Nothing else is sent: no account, no cookies, nothing about you.
- An edition is made when the day's first look at Home (or the paper) finds
  yesterday's, with Wi-Fi on or allowed to come on (Wi-Fi: Auto / On). A
  failed try waits RETRY seconds. The paper's day starts at 5 in the morning.
- Feeds: GZreader's own list by topic (each can be ticked off) and your
  own, typed in or brought in a feeds.txt. A feed's address is never
  written to the log (only its site), as some carry a key.
- The Kindles without Wi-Fi (2, DX, DX Graphite, or Sync through a computer
  chosen): the sync page fetches the feeds that let a web page read them (and
  the stories' pages that do) and leaves them on the drive; GZreader makes the
  edition from them when it takes in what the computer brought
  (Daily.outbox, Daily.fromComputer). No pictures or weather that way.

The edition (settings/gzreader-daily.json):
  { day = "2026-11-17", at = seconds, sections = { { topic = "World",
    items = { { title, text, link, at, source, img } } } }, failed = { names } }
`full`: the story's text is its own page's (Daily.addFullText), not the
feed's. `img`: a story's picture, a file in cache/gzreader-daily/ (MAX_PICTURES of
them for the opened stories, the first PAGE_PICTURES also on the pages, each MAX_PICTURE_BYTES at most; Settings can turn
pictures off). Pictures often come from another site than the feed's.
]]

local Feeds = require("gzreader_feeds")
local Log = require("gzreader_log")
local _ = require("gettext")

local Daily = {
    ROW_ID = "daily_paper",
    PER_FEED = 5,        -- stories taken from one feed
    PER_SECTION = 8,     -- stories in one section
    MAX_TEXT = 16000,    -- bytes of a story's text kept (about 2,500 words)
    FULL_ENOUGH = 2500,  -- a feed's text this long is taken as the whole story: its page isn't fetched
    MAX_PAGE_BYTES = 2 * 1024 * 1024, -- a story's page bigger than this isn't read
    MAX_FULL = 40,       -- stories whose page is fetched in one edition
    FULL_SECONDS = 300,  -- … and how long that may take altogether
    MAX_BYTES = 1536 * 1024, -- a feed bigger than this isn't read
    MAX_FEEDS = 24,
    FRESH = 36 * 3600,   -- stories older than this stay out (when the feed dates them)
    RETRY = 30 * 60,
    MAX_PICTURES = 24,   -- stories that get their picture (the lead, then each section's first, …), for the opened story
    PAGE_PICTURES = 8,   -- … of which the first few also show on the paper's pages
    PICTURE_SECONDS = 180, -- how long fetching the pictures may take altogether
    MAX_PICTURE_BYTES = 700 * 1024,
    AI_MAX = 20,         -- stories summarised in one edition (the AI edition)
    AI_SECONDS = 240,    -- … and how long that may take altogether
    AI_TEXT = 6000,      -- bytes of a story sent for its summary
    AI_MIN = 600,        -- a story shorter than this is its own summary: not sent
    AI_SUMMARY = 700,    -- bytes of a summary kept
    AI_GIVE_UP = 3,      -- failures in a row after which the rest aren't asked for
    EDITION_HOUR = 5,    -- a day's paper is made from this hour on (the Kindle's clock)
    TOPICS = { "World", "Technology", "Science", "Books", "Curiosities", "Good news" },
    OWN_TOPIC = "Your feeds",
    GOOD_TOPIC = "Good news", -- (put forward: more of it near the front; its feeds come with their own PR)
    GOOD_WEIGHT = 3,          -- … this many times as likely to come next, in the first half of the paper
}

-- GZreader's own feeds (each can be turned off; `off = true`: there to tick on)
Daily.DEFAULT_FEEDS = {
    { id = "bbc-world", topic = "World", name = "BBC News", url = "https://feeds.bbci.co.uk/news/world/rss.xml" },
    { id = "npr-news", topic = "World", name = "NPR", url = "https://feeds.npr.org/1001/rss.xml" },
    { id = "ars", topic = "Technology", name = "Ars Technica", url = "https://feeds.arstechnica.com/arstechnica/index" },
    { id = "bbc-tech", topic = "Technology", name = "BBC News", url = "https://feeds.bbci.co.uk/news/technology/rss.xml" },
    { id = "hn", topic = "Technology", name = "Hacker News", url = "https://hnrss.org/frontpage", off = true },
    { id = "nasa", topic = "Science", name = "NASA", url = "https://www.nasa.gov/news-release/feed/" },
    { id = "bbc-science", topic = "Science", name = "BBC News", url = "https://feeds.bbci.co.uk/news/science_and_environment/rss.xml" },
    { id = "npr-science", topic = "Science", name = "NPR", url = "https://feeds.npr.org/1007/rss.xml", off = true },
    { id = "lithub", topic = "Books", name = "Literary Hub", url = "https://lithub.com/feed/" },
    { id = "atlas", topic = "Curiosities", name = "Atlas Obscura", url = "https://www.atlasobscura.com/feeds/latest" },
    { id = "npr-strange", topic = "Curiosities", name = "NPR Strange News", url = "https://feeds.npr.org/1146/rss.xml" },
    -- (happy news: the owner asked for Good News Network and others like it, 2026-11-25)
    { id = "gnn", topic = "Good news", name = "Good News Network", url = "https://www.goodnewsnetwork.org/feed/" },
    { id = "positive-news", topic = "Good news", name = "Positive News", url = "https://www.positive.news/feed/" },
    { id = "reasons-cheerful", topic = "Good news", name = "Reasons to be Cheerful", url = "https://reasonstobecheerful.world/feed/", off = true },
}

--- A topic's name as shown (the built-in ones are translated).
function Daily.topicLabel(topic)
    if topic == "World" then return _("World") end
    if topic == "Technology" then return _("Technology") end
    if topic == "Science" then return _("Science") end
    if topic == "Books" then return _("Books") end
    if topic == "Curiosities" then return _("Curiosities") end
    if topic == "Good news" then return _("Good news") end
    if topic == Daily.OWN_TOPIC then return _("Your feeds") end
    return topic
end

---------------------------------------------------------------- settings

function Daily.store(plugin)
    plugin.store.daily = type(plugin.store.daily) == "table" and plugin.store.daily or {}
    local st = plugin.store.daily
    st.off = type(st.off) == "table" and st.off or {}
    st.on = type(st.on) == "table" and st.on or {}
    st.feeds = type(st.feeds) == "table" and st.feeds or {}
    return st
end

--- No Wi-Fi here (a Kindle 2 / DX, or Sync through a computer chosen).
function Daily.noWifi()
    local ok, Net = pcall(require, "gzreader_net")
    return ok and Net.usb == true
end

function Daily.enabled(plugin)
    return Daily.store(plugin).enabled == true
end

--- Is one of GZreader's own feeds on?
function Daily.defaultOn(plugin, feed)
    local st = Daily.store(plugin)
    if feed.off then return st.on[feed.id] == true end
    return st.off[feed.id] ~= true
end

function Daily.setDefaultOn(plugin, feed, on)
    local st = Daily.store(plugin)
    if feed.off then st.on[feed.id] = on and true or nil else st.off[feed.id] = (not on) and true or nil end
end

--- A feed's address as typed or pasted (feed:// and no scheme allowed), or nil.
function Daily.normalizeUrl(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    s = s:gsub("^[Ff][Ee][Ee][Dd]:https?://", function(m) return m:sub(6) end)
    s = s:gsub("^[Ff][Ee][Ee][Dd]://", "https://")
    if not s:match("^%a[%w+.-]*://") then s = "https://" .. s end
    if not s:match("^https?://[^/%s?#]+%.[^/%s?#]+") or s:find("%s") then return nil end
    return s
end

--- How a feed shows in the log and in lists: its site only.
function Daily.site(url)
    return ((url or ""):match("^https?://([^/?#:]+)") or "?"):gsub("^www%.", ""):gsub("^feeds?%.", "")
end

--- Add one of your own feeds. Returns the entry, or nil and "bad" (not an
--- address), "have" (already there), "full".
function Daily.addFeed(plugin, url, name, topic)
    local st = Daily.store(plugin)
    url = Daily.normalizeUrl(url)
    if not url then return nil, "bad" end
    for _i, f in ipairs(st.feeds) do
        if f.url == url then return nil, "have" end
    end
    for _i, f in ipairs(Daily.DEFAULT_FEEDS) do
        if f.url == url then return nil, "have" end
    end
    if #st.feeds >= Daily.MAX_FEEDS then return nil, "full" end
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    topic = type(topic) == "string" and topic:gsub("^%s+", ""):gsub("%s+$", "") or ""
    local entry = { url = url, name = name ~= "" and name or nil, topic = topic ~= "" and topic or nil }
    st.feeds[#st.feeds + 1] = entry
    return entry
end

--- The lines of a feeds.txt: one feed a line, "Name | address" or
--- "Topic | Name | address" or the address alone; "#" starts a comment.
function Daily.parseFeedLines(text)
    local out = {}
    for line in tostring(text or ""):gsub("\r", ""):gmatch("[^\n]+") do
        line = line:gsub("^\239\187\191", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local parts = {}
            for part in (line .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = (part:gsub("^%s+", ""):gsub("%s+$", "")) end
            local url = parts[#parts]
            local name = #parts >= 2 and parts[#parts - 1] or nil
            local topic = #parts >= 3 and parts[#parts - 2] or nil
            if Daily.normalizeUrl(url) then
                out[#out + 1] = { url = url, name = name ~= "" and name or nil, topic = topic ~= "" and topic or nil }
            end
        end
    end
    return out
end

--- The feeds an edition is made from: { { url, name, topic } }.
function Daily.feeds(plugin)
    local st = Daily.store(plugin)
    local out = {}
    for _i, f in ipairs(Daily.DEFAULT_FEEDS) do
        if Daily.defaultOn(plugin, f) then out[#out + 1] = { url = f.url, name = f.name, topic = f.topic } end
    end
    for _i, f in ipairs(st.feeds) do
        if f.enabled ~= false and type(f.url) == "string" then
            out[#out + 1] = { url = f.url, name = f.name, topic = f.topic or Daily.OWN_TOPIC }
        end
    end
    return out
end

---------------------------------------------------------------- the setup page (gzreader_phone.lua)

--- What the setup page's Daily paper section shows: nil on a Kindle
--- without Wi-Fi. Your own feeds by name and site, never their addresses
--- (some carry a key).
function Daily.pageState(plugin)
    if Daily.noWifi() then return nil end
    local st = Daily.store(plugin)
    local defaults, own = {}, {}
    for _i, f in ipairs(Daily.DEFAULT_FEEDS) do
        defaults[#defaults + 1] = { id = f.id, topic = Daily.topicLabel(f.topic), name = f.name, site = Daily.site(f.url),
            on = Daily.defaultOn(plugin, f) }
    end
    for i, f in ipairs(st.feeds) do
        own[#own + 1] = { n = i, name = f.name, site = Daily.site(f.url), topic = f.topic, on = f.enabled ~= false }
    end
    local edition = Daily.load()
    local ai_ready = (function()
        local ok, AI = pcall(require, "gzreader_ai")
        return ok and AI.ready(plugin) or false
    end)()
    return { ai = st.ai == true, ai_ready = ai_ready, enabled = st.enabled == true, shelf = st.shelf ~= false, pictures = st.pictures ~= false, calendar = st.calendar ~= false, full = st.full ~= false,
        weather = (function()
            local W = require("gzreader_weather")
            local w = W.store(plugin)
            return { on = w.off ~= true, source = W.source(plugin), place = w.place, unit = w.unit }
        end)(),
        defaults = defaults, own = own, max = Daily.MAX_FEEDS,
        stories = edition and Daily.count(edition) or nil, day = edition and edition.day or nil }
end

--- The section's Save: the switches and which feeds are ticked (a box that
--- isn't ticked isn't sent: `form.d_<id>`, `form.f_<n>` = "1" when ticked;
--- `form.count` = how many of your feeds the page showed, so a page that's
--- out of date doesn't untick the wrong ones).
function Daily.pageSave(plugin, form)
    local st = Daily.store(plugin)
    st.enabled = form.enabled == "1" or nil
    if form.shelf == "1" then st.shelf = nil else st.shelf = false end
    if form.pictures == "1" then st.pictures = nil else st.pictures = false end
    if form.full == "1" then st.full = nil else st.full = false end
    if form.calendar == "1" then st.calendar = nil else st.calendar = false end
    st.ai = form.ai == "1" or nil
    local w = require("gzreader_weather").store(plugin)
    w.off = (form.weather ~= "1") or nil
    if form.unit == "F" or form.unit == "C" then w.unit = form.unit end
    for _i, f in ipairs(Daily.DEFAULT_FEEDS) do Daily.setDefaultOn(plugin, f, form["d_" .. f.id] == "1") end
    if tonumber(form.count) == #st.feeds then
        for i, f in ipairs(st.feeds) do
            if form["f_" .. i] == "1" then f.enabled = nil else f.enabled = false end
        end
    end
    Daily.feedsChanged()
    return true
end

--- Feeds pasted into the section (feeds.txt's lines). Returns how many
--- were added and how many lines weren't (not an address, there already,
--- or past the most the paper takes).
function Daily.pageAdd(plugin, text)
    local added, wanted = 0, 0
    for line in tostring(text or ""):gsub("\r", ""):gmatch("[^\n]+") do
        if line:match("%S") and not line:match("^%s*#") then wanted = wanted + 1 end
    end
    for _i, e in ipairs(Daily.parseFeedLines(text)) do
        if Daily.addFeed(plugin, e.url, e.name, e.topic) then added = added + 1 end
    end
    if added > 0 then Daily.feedsChanged() end
    return added, wanted - added
end

--- Remove your feed number `n` (of `count`, as the page showed them).
function Daily.pageRemove(plugin, n, count)
    local st = Daily.store(plugin)
    n = tonumber(n)
    if not n or tonumber(count) ~= #st.feeds or not st.feeds[n] then return false end
    table.remove(st.feeds, n)
    Daily.feedsChanged()
    return true
end

--- The feeds or the switches changed: today's paper is made again at the next look.
function Daily.feedsChanged()
    Daily.tried_at = nil
    if Daily.edition then Daily.edition.day = "" end
end

---------------------------------------------------------------- an edition

--- The paper's day: a new one starts at EDITION_HOUR (reading past midnight
--- doesn't fetch "tomorrow's" paper with the evening's stories).
function Daily.day(t) return os.date("%Y-%m-%d", (t or os.time()) - Daily.EDITION_HOUR * 3600) end

--- What every request says it is: GZreader/<version> (socketutil.USER_AGENT; "GZreader" where that can't be loaded).
local function userAgent()
    local ok, su = pcall(require, "socketutil")
    return ok and type(su) == "table" and su.USER_AGENT or "GZreader"
end

local function key(item)
    return (item.title or ""):lower():gsub("[%s%p]+", " ")
end

--- An edition from the feeds' texts. `fetch(url)` → the feed's body, or nil
--- and why. Topics in GZreader's order, then others as they come; inside a
--- topic the feeds take turns, so one busy feed doesn't fill it.
function Daily.build(feeds, now, fetch)
    now = now or os.time()
    local dated = now > 1704067200 -- (a clock that ran down to 1970/2000 can't judge a story's age)
    local by_topic, order, failed, seen = {}, {}, {}, {}
    for _i, topic in ipairs(Daily.TOPICS) do by_topic[topic] = {}; order[#order + 1] = topic end
    local got_any = false
    for _i, feed in ipairs(feeds or {}) do
        local body, err = fetch(feed.url)
        local parsed
        if body then parsed, err = Feeds.parse(body, { max_items = Daily.PER_FEED * 4, max_text = Daily.MAX_TEXT }) end
        if not parsed then
            Log.warn("daily paper:", Daily.site(feed.url), "failed:", tostring(err))
            failed[#failed + 1] = feed.name or Daily.site(feed.url)
        else
            got_any = true
            local source = feed.name or parsed.title or Daily.site(feed.url)
            local fresh, older = {}, {}
            for _j, item in ipairs(parsed.items) do
                item.source = source
                if dated and item.at and (item.at < now - Daily.FRESH or item.at > now + 86400) then
                    older[#older + 1] = item
                else
                    fresh[#fresh + 1] = item
                end
            end
            -- (a feed that posts seldom: its newest story rather than nothing)
            if #fresh == 0 and older[1] then fresh[1] = older[1] end
            local topic = feed.topic or Daily.OWN_TOPIC
            if not by_topic[topic] then by_topic[topic] = {}; order[#order + 1] = topic end
            local list = {}
            for j = 1, math.min(#fresh, Daily.PER_FEED) do list[#list + 1] = fresh[j] end
            table.insert(by_topic[topic], list)
        end
    end
    if not got_any then return nil, #failed > 0 and "unreachable" or "no feeds" end
    local sections = {}
    for _i, topic in ipairs(order) do
        local lists, items = by_topic[topic], {}
        local round = 1
        while #items < Daily.PER_SECTION do
            local any = false
            for _j, list in ipairs(lists) do
                local item = list[round]
                if item then
                    any = true
                    local k = key(item)
                    if not seen[k] and not (item.link and seen[item.link]) and #items < Daily.PER_SECTION then
                        seen[k] = true
                        if item.link then seen[item.link] = true end
                        items[#items + 1] = item
                    end
                end
            end
            if not any then break end
            round = round + 1
        end
        if #items > 0 then sections[#sections + 1] = { topic = topic, items = items } end
    end
    if #sections == 0 then return nil, "empty" end
    local edition = { day = Daily.day(now), at = now, sections = sections, failed = failed }
    -- (the topics mixed through the paper, good news near the front; the same all day)
    edition.order = Daily.mix(edition, edition.day)
    return edition
end

--- A number from `seed` (a string), and a generator of numbers 0 ≤ x < 1 from it. Pure.
local function rng(seed)
    local h = 5381
    for i = 1, #tostring(seed or "") do h = (h * 33 + tostring(seed):byte(i)) % 2147483647 end
    local state = h % 2147483646 + 1
    local function step()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
    -- (seeds a day apart start close together: a few draws first spread them out)
    for _i = 1, 4 do step() end
    return step
end

--- The edition's stories mixed: { { s, i } } (section, story in it), every story once.
--- Inside a topic they keep their order; which topic comes next is drawn (`seed`: the
--- same mix all day), in proportion to how many it has left, Good news GOOD_WEIGHT
--- times as likely in the first half and leading the paper; never the same topic
--- twice running while another has stories left. Pure.
function Daily.mix(edition, seed, good)
    local good_first = good ~= false
    local secs = type(edition) == "table" and edition.sections or {}
    local next_i, total = {}, 0
    for s, sec in ipairs(secs) do next_i[s] = 1; total = total + #sec.items end
    local rand = rng(seed)
    local out, last = {}, nil
    while #out < total do
        local cands, sum = {}, 0
        for s, sec in ipairs(secs) do
            local left = #sec.items - next_i[s] + 1
            if left > 0 then
                local w = left
                if good_first and sec.topic == Daily.GOOD_TOPIC and #out < total / 2 then w = w * Daily.GOOD_WEIGHT end
                cands[#cands + 1] = { s = s, w = w }
            end
        end
        -- (not the topic just used, when there's another)
        if #cands > 1 and last then
            for k = #cands, 1, -1 do if cands[k].s == last then table.remove(cands, k) end end
        end
        local pick
        if #out == 0 and good_first then
            for _k, c in ipairs(cands) do if secs[c.s].topic == Daily.GOOD_TOPIC then pick = c end end
        end
        if not pick then
            for _k, c in ipairs(cands) do sum = sum + c.w end
            local r = rand() * sum
            for _k, c in ipairs(cands) do
                r = r - c.w
                if r < 0 then pick = c; break end
            end
            pick = pick or cands[#cands]
        end
        out[#out + 1] = { s = pick.s, i = next_i[pick.s] }
        next_i[pick.s] = next_i[pick.s] + 1
        last = pick.s
    end
    return out
end

---------------------------------------------------------------- the paper's order

--- How the stories are ordered (Settings → Daily paper → Story order): "mixed_good"
--- (mixed, good news first: the usual), "mixed", "sections" (each section's stories
--- together, in the feeds list's order).
Daily.ORDER_STYLES = { "mixed_good", "mixed", "sections" }

function Daily.orderStyle(plugin)
    local v = Daily.store(plugin).order
    for _i, k in ipairs(Daily.ORDER_STYLES) do if v == k then return v end end
    return "mixed_good"
end

--- Does the AI edition's AI choose the order? (On unless turned off.)
function Daily.aiOrders(plugin)
    return Daily.store(plugin).ai_order ~= false
end

--- What Daily.arrange takes: { style, ai }.
function Daily.how(plugin)
    -- (the AI's order only while the AI edition is ticked)
    return { style = Daily.orderStyle(plugin), ai = Daily.aiWanted(plugin) and Daily.aiOrders(plugin) }
end

--- Put `edition` in the order `how` asks for ({ style, ai }): the AI's order when
--- `how.ai` and the AI gave one (edition.ai_order), else the style's: a mix with
--- or without good news first, or none (the sections one after another). The same
--- mix all day. Returns the edition. Pure.
function Daily.arrange(edition, how)
    if type(edition) ~= "table" or type(edition.sections) ~= "table" then return edition end
    how = type(how) == "table" and how or {}
    if how.ai ~= false and type(edition.ai_order) == "table" and #edition.ai_order > 0 then
        edition.order, edition.ordered_by_ai = edition.ai_order, true
        return edition
    end
    edition.ordered_by_ai = nil
    if how.style == "sections" then
        edition.order = nil
    else
        edition.order = Daily.mix(edition, edition.day, how.style ~= "mixed")
    end
    return edition
end

--- After a change to the order's settings: today's kept paper put in the new order.
function Daily.rearrange(plugin)
    local edition = Daily.load()
    if not edition then return end
    Daily.arrange(edition, Daily.how(plugin))
    Daily.keep(edition)
    Log.info("daily paper: order", Daily.orderStyle(plugin), Daily.aiOrders(plugin) and "(the AI's when it chose)" or "(not the AI's)")
    Daily.changed()
end

--- The edition's stories in reading order: { item, topic, s, i } (its mix when it has one,
--- else the sections one after another). Pure.
function Daily.ordered(edition)
    local out = {}
    if type(edition) ~= "table" then return out end
    local secs = edition.sections or {}
    local seen = {}
    for _k, o in ipairs(type(edition.order) == "table" and edition.order or {}) do
        local sec = type(o) == "table" and secs[tonumber(o.s) or 0]
        local item = sec and sec.items[tonumber(o.i) or 0]
        local at = tostring(o.s) .. ":" .. tostring(o.i)
        if item and not seen[at] then
            seen[at] = true
            out[#out + 1] = { item = item, topic = sec.topic, s = tonumber(o.s), i = tonumber(o.i) }
        end
    end
    -- (any the order left out, after: an order from an older edition, or the AI's)
    for s, sec in ipairs(secs) do
        for i, item in ipairs(sec.items) do
            if not seen[s .. ":" .. i] then out[#out + 1] = { item = item, topic = sec.topic, s = s, i = i } end
        end
    end
    return out
end

--- The front page: up to `n` headlines, the paper's first (its mix), or with no mix
--- the sections' first stories first.
function Daily.front(edition, n)
    local out = {}
    if type(edition) ~= "table" then return out end
    if type(edition.order) == "table" and #edition.order > 0 then
        for _i, st in ipairs(Daily.ordered(edition)) do
            if #out >= n then break end
            out[#out + 1] = { title = st.item.title, source = st.item.source, topic = st.topic, item = st.item }
        end
        return out
    end
    local round = 1
    while #out < n do
        local any = false
        for _i, s in ipairs(edition.sections or {}) do
            local item = s.items[round]
            if item and #out < n then
                any = true
                out[#out + 1] = { title = item.title, source = item.source, topic = s.topic, item = item }
            end
        end
        if not any then break end
        round = round + 1
    end
    return out
end

function Daily.count(edition)
    local n = 0
    for _i, s in ipairs(type(edition) == "table" and edition.sections or {}) do n = n + #s.items end
    return n
end

---------------------------------------------------------------- the network

--- One feed's body, or nil and why ("unreachable", "http_404", "too big").
function Daily.fetch(url)
    local Api = require("gzreader_api")
    local Gzip = require("gzreader_gzip")
    local chunks, size, too_big = {}, 0, false
    local function sink(chunk)
        if chunk then
            size = size + #chunk
            if size > Daily.MAX_BYTES then too_big = true; return nil, "too big" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    local answer = { Api.rawRequest("GET", url, {
        headers = {
            ["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
            ["Accept-Encoding"] = Gzip.available() and "gzip" or "identity",
            ["User-Agent"] = userAgent(),
        },
        sink = sink, timeouts = { 15, 45 }, log_url = "https://" .. Daily.site(url) .. "/\u{2026} (feed)",
    }) }
    local code, headers = answer[1], answer[3]
    if too_big then return nil, "too big" end
    if type(code) ~= "number" then return nil, "unreachable" end
    if code >= 400 then return nil, "http_" .. code end
    local raw = table.concat(chunks)
    local enc = type(headers) == "table" and (headers["content-encoding"] or headers["Content-Encoding"])
    if type(enc) == "string" and enc:lower():find("gzip", 1, true) and raw ~= "" then
        local plain = Gzip.inflate(raw)
        if not plain then return nil, "gzip" end
        if #plain > Daily.MAX_BYTES * 4 then return nil, "too big" end
        raw = plain
    end
    if raw == "" then return nil, "empty" end
    return raw
end

---------------------------------------------------------------- full stories

--- Whole stories wanted? (On unless turned off.) Many feeds carry only a
--- sentence or two; with this on, such a story's own page is fetched with
--- the paper and its article taken out of it (gzreader_article.lua).
function Daily.fullStories(plugin)
    return Daily.store(plugin).full ~= false
end

--- A story's page: its HTML and content type, or nil and why. Its address
--- isn't logged (its site only).
function Daily.fetchPage(url)
    local Api = require("gzreader_api")
    local Gzip = require("gzreader_gzip")
    local chunks, size, too_big = {}, 0, false
    local function sink(chunk)
        if chunk then
            size = size + #chunk
            if size > Daily.MAX_PAGE_BYTES then too_big = true; return nil, "too big" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    local answer = { Api.rawRequest("GET", url, {
        headers = { ["Accept"] = "text/html, application/xhtml+xml", ["Accept-Encoding"] = Gzip.available() and "gzip" or "identity",
            ["User-Agent"] = userAgent() },
        sink = sink, timeouts = { 10, 25 }, log_url = "https://" .. Daily.site(url) .. "/\u{2026} (story)",
    }) }
    if too_big then return nil, "too big" end
    local code, headers = answer[1], type(answer[3]) == "table" and answer[3] or {}
    if type(code) ~= "number" then return nil, "unreachable" end
    if code >= 400 then return nil, "http_" .. code end
    local raw = table.concat(chunks)
    local enc = headers["content-encoding"] or headers["Content-Encoding"]
    if type(enc) == "string" and enc:lower():find("gzip", 1, true) and raw ~= "" then
        raw = Gzip.inflate(raw)
        if not raw then return nil, "gzip" end
        if #raw > Daily.MAX_PAGE_BYTES * 3 then return nil, "too big" end
    end
    local kind = headers["content-type"] or headers["Content-Type"]
    if type(kind) == "string" and not kind:lower():find("html", 1, true) then return nil, "not html" end
    return raw, kind
end

--- Give the edition's short stories their whole text, from their own
--- pages: in the front page's order, MAX_FULL at most, until `seconds` have
--- gone. A story keeps the feed's text unless the page's is clearly longer.
--- `fetch(url)` → html, content type (or nil); `clock()` → seconds (for tests).
--- Returns how many stories were filled, and how many pages were asked for.
function Daily.addFullText(edition, fetch, seconds, clock)
    local Article = require("gzreader_article")
    clock = clock or os.time
    local started, filled, asked = clock(), 0, 0
    for _i, f in ipairs(Daily.front(edition, Daily.count(edition))) do
        local item = f.item
        if asked >= Daily.MAX_FULL or clock() - started >= (seconds or Daily.FULL_SECONDS) then break end
        if item.link and #(item.text or "") < Daily.FULL_ENOUGH then
            asked = asked + 1
            local ok, html, kind = pcall(fetch, item.link)
            -- (a story whose feed names no picture: the one its page names as its own)
            if ok and html and not item.image then item.image = Article.leadImage(html) end
            local text = ok and html and Article.extract(html, kind) or nil
            if text and #text >= Article.MIN_BYTES and #text > #(item.text or "") * 1.3 then
                item.text = Feeds.cut(text, Daily.MAX_TEXT)
                item.full = true
                filled = filled + 1
            end
        end
    end
    return filled, asked
end

---------------------------------------------------------------- the AI edition

--- The AI edition ticked? (Settings → Daily paper → AI edition.)
function Daily.aiWanted(plugin)
    return Daily.store(plugin).ai == true
end

--- The AI edition on: ticked, and the AI connection (gzreader_ai.lua) set up.
function Daily.aiOn(plugin)
    if not Daily.aiWanted(plugin) then return false end
    local ok, AI = pcall(require, "gzreader_ai")
    return ok and AI.ready(plugin) or false
end

Daily.SUMMARY_SYSTEM = "You write the short summaries a newspaper prints under its headlines. "
    .. "Given a news story, reply with a summary of it in 2 to 4 plain sentences, about 60 to 90 words. "
    .. "Say what happened, to whom, where and why it matters, using only what the story says. "
    .. "Neutral tone, no opinion, no preamble, no headline, no lists, no formatting: only the summary."

--- What to ask for a story's summary: { system, text, max_tokens, timeout }.
--- The story's headline and text only: never its address, nor anything of yours.
function Daily.summaryQuestion(item)
    return { system = Daily.SUMMARY_SYSTEM, max_tokens = 300, timeout = 40,
        text = "Headline: " .. tostring(item.title or "") .. "\n\nStory:\n" .. Feeds.cut(item.text or "", Daily.AI_TEXT) }
end

Daily.ORDER_SYSTEM = "You are the editor of a small daily newspaper read on an e-reader. "
    .. "You are given the day's stories, numbered, each with its section and how it begins. "
    .. "Put them in the order the paper should print them: open with good, hopeful or uplifting news, "
    .. "keep plenty of good news near the front, mix the sections so the same one doesn't run on, "
    .. "and put what matters or interests most early. Every story once. "
    .. "Reply with JSON only: {\"order\":[numbers]}."
-- (Story order without good news first: the same, without putting good news forward)
Daily.ORDER_SYSTEM_PLAIN = "You are the editor of a small daily newspaper read on an e-reader. "
    .. "You are given the day's stories, numbered, each with its section and how it begins. "
    .. "Put them in the order the paper should print them: mix the sections so the same one doesn't run on, "
    .. "and put what matters or interests most early. Every story once. "
    .. "Reply with JSON only: {\"order\":[numbers]}."

--- What to ask for the paper's order (`list`: Daily.ordered's, numbered from 1): the
--- headlines, sections and how each begins; nothing of yours. Pure.
function Daily.orderQuestion(list, good)
    local lines = {}
    for n, st in ipairs(list) do
        local start = Feeds.cut(tostring(st.item.text or ""):gsub("%s+", " "), 160)
        lines[#lines + 1] = string.format("%d. [%s] %s: %s", n, tostring(st.topic or ""), tostring(st.item.title or ""), start)
    end
    return { system = good == false and Daily.ORDER_SYSTEM_PLAIN or Daily.ORDER_SYSTEM, max_tokens = 400, timeout = 60,
        text = "The stories:\n" .. table.concat(lines, "\n") }
end

--- The order the AI chose, read from its answer `text` for `list`: { { s, i } } with each
--- story once (any it left out after, in the mix's order), or nil when there's no usable
--- list in it. Pure.
function Daily.orderFrom(text, list)
    local body = type(text) == "string" and text:match("%b{}") or nil
    local ok, data = pcall(function() return body and require("gzreader_json").decode(body) end)
    local nums = ok and type(data) == "table" and type(data.order) == "table" and data.order or nil
    if not nums then return nil end
    local out, used = {}, {}
    for _k, v in ipairs(nums) do
        local n = tonumber(v)
        local st = n and list[n]
        if st and not used[n] then used[n] = true; out[#out + 1] = { s = st.s, i = st.i } end
    end
    if #out < math.max(1, math.floor(#list / 2)) then return nil end -- (most of it: else not trusted)
    for n, st in ipairs(list) do if not used[n] then out[#out + 1] = { s = st.s, i = st.i } end end
    return out
end

--- The AI edition: the AI puts the paper in order (the mix stays when it can't).
--- `ask(question)` → text, or nil and why; `good` false: without good news first.
--- Kept as edition.ai_order too (Daily.arrange). Returns true, or false and why.
function Daily.aiOrder(edition, ask, good)
    local list = Daily.ordered(edition)
    if #list < 3 then return false, "too few stories" end
    local okc, text, err = pcall(ask, Daily.orderQuestion(list, good))
    local order = okc and Daily.orderFrom(text, list) or nil
    if not order then return false, okc and (err or "no order in the answer") or "an error" end
    edition.order, edition.ai_order, edition.ordered_by_ai = order, order, true
    return true
end

--- Give the edition's stories their summaries, in the front page's order:
--- AI_MAX at most, until `seconds` have gone, giving up after AI_GIVE_UP
--- failures in a row (a refused key fails every time). A story too short to
--- need one is left as it is. `ask(question)` → text, or nil and why.
--- Returns how many got one, how many were asked for, and the last reason
--- one wasn't given.
function Daily.addSummaries(edition, ask, seconds, clock)
    clock = clock or os.time
    local started, done, asked, misses, why = clock(), 0, 0, 0, nil
    for _i, f in ipairs(Daily.front(edition, Daily.count(edition))) do
        local item = f.item
        if asked >= Daily.AI_MAX or misses >= Daily.AI_GIVE_UP or clock() - started >= (seconds or Daily.AI_SECONDS) then break end
        if #(item.text or "") >= Daily.AI_MIN then
            asked = asked + 1
            local ok, text, err = pcall(ask, Daily.summaryQuestion(item))
            if ok and type(text) == "string" and #text >= 40 then
                item.summary = Feeds.cut((text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")), Daily.AI_SUMMARY)
                done, misses = done + 1, 0
            else
                misses = misses + 1
                why = ok and (err or "an empty answer") or "an error"
            end
        end
    end
    return done, asked, why
end

---------------------------------------------------------------- pictures

--- Pictures wanted? (On unless turned off; never on a Kindle with 128 MB.)
function Daily.pictures(plugin)
    return Daily.store(plugin).pictures ~= false
end

function Daily.pictureDir() return require("datastorage"):getDataDir() .. "/cache/gzreader-daily" end

--- What kind of picture `data` is, by how it starts: "jpg", "png", "gif",
--- "webp", or nil (an error page, an SVG, something else).
function Daily.pictureKind(data)
    if type(data) ~= "string" or #data < 16 then return nil end
    if data:sub(1, 3) == "\255\216\255" then return "jpg" end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "png" end
    if data:sub(1, 4) == "GIF8" then return "gif" end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "webp" end
    return nil
end

--- A picture's bytes, or nil and why. No address in the log (its site only).
function Daily.fetchPicture(url)
    local Api = require("gzreader_api")
    local chunks, size, too_big = {}, 0, false
    local function sink(chunk)
        if chunk then
            size = size + #chunk
            if size > Daily.MAX_PICTURE_BYTES then too_big = true; return nil, "too big" end
            chunks[#chunks + 1] = chunk
        end
        return 1
    end
    local answer = { Api.rawRequest("GET", url, {
        headers = { ["Accept"] = "image/jpeg, image/png, image/webp, image/gif", ["Accept-Encoding"] = "identity",
            ["User-Agent"] = userAgent() },
        sink = sink, timeouts = { 10, 30 }, log_url = "https://" .. Daily.site(url) .. "/\u{2026} (picture)",
    }) }
    if too_big then return nil, "too big" end
    if type(answer[1]) ~= "number" then return nil, "unreachable" end
    if answer[1] >= 400 then return nil, "http_" .. answer[1] end
    return table.concat(chunks)
end

--- The stories of an edition that get their picture, most wanted first: the
--- front page's order (each section's first, then their seconds…), those
--- with a picture only, MAX_PICTURES at most.
function Daily.pictureWanted(edition)
    local out = {}
    for _i, f in ipairs(Daily.front(edition, Daily.count(edition))) do
        if f.item.image and #out < Daily.MAX_PICTURES then out[#out + 1] = f.item end
    end
    return out
end

--- Fetch the edition's pictures into `dir` (emptied first): a story that got
--- one has `img`, its file's name. Every story's `image` address is dropped
--- from the edition (not kept, not logged). `fetch(url)` → bytes or nil.
--- `write(path, data)` → true (for tests; a plain file otherwise).
function Daily.addPictures(edition, dir, fetch, write, seconds, clock)
    clock = clock or os.time
    local started = clock()
    write = write or function(path, data)
        local f = io.open(path, "wb")
        if not f then return false end
        f:write(data)
        f:close()
        return true
    end
    local got = 0
    for n, item in ipairs(Daily.pictureWanted(edition)) do
        if clock() - started >= (seconds or Daily.PICTURE_SECONDS) then break end
        local data = fetch(item.image)
        local kind = Daily.pictureKind(data)
        if kind then
            local name = string.format("%s-%d.%s", edition.day, n, kind)
            if write(dir .. "/" .. name, data) then
                item.img = name
                got = got + 1
            end
        end
    end
    for _i, s in ipairs(edition.sections) do
        for _j, item in ipairs(s.items) do item.image = nil end
    end
    return got
end

--- Empty the pictures' folder (but `keep`, a set of names), making it if needed.
function Daily.clearPictures(keep)
    local dir = Daily.pictureDir()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then return end
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(require("datastorage"):getDataDir() .. "/cache")
        lfs.mkdir(dir)
        return
    end
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." and not (keep and keep[name]) then os.remove(dir .. "/" .. name) end
    end
end

--- Does a story's picture also show on the paper's pages? (The first
--- PAGE_PICTURES fetched: its file is named <day>-<n>.<kind>.)
function Daily.pagePicture(item)
    local n = type(item) == "table" and type(item.img) == "string" and tonumber(item.img:match("%-(%d+)%.%a+$"))
    return n ~= nil and n ~= false and n <= Daily.PAGE_PICTURES
end

--- A story's picture file, when it has one that's there.
function Daily.picturePath(item)
    if type(item) ~= "table" or type(item.img) ~= "string" or item.img:find("[/\\]") then return nil end
    local path = Daily.pictureDir() .. "/" .. item.img
    local f = io.open(path, "rb")
    if not f then return nil end
    f:close()
    return path
end

---------------------------------------------------------------- kept on the Kindle

function Daily.cachePath() return require("datastorage"):getSettingsDir() .. "/gzreader-daily.json" end

function Daily.load()
    if Daily.loaded then return Daily.edition end
    Daily.loaded = true
    local f = io.open(Daily.cachePath(), "rb")
    if not f then return nil end
    local ok, data = pcall(require("gzreader_json").decode, f:read("*a"))
    f:close()
    Daily.edition = ok and type(data) == "table" and type(data.sections) == "table" and data or nil
    return Daily.edition
end

function Daily.keep(edition)
    Daily.edition, Daily.loaded = edition, true
    local Json = require("gzreader_json")
    for _i, s in ipairs(edition.sections) do Json.list(s.items) end
    Json.list(edition.sections)
    Json.list(edition.failed)
    local ok, text = pcall(Json.encode, edition)
    if not ok then return Log.warn("daily paper: couldn't keep the edition:", tostring(text)) end
    local path = Daily.cachePath()
    local f = io.open(path .. ".tmp", "wb")
    if not f then return end
    f:write(text)
    f:close()
    os.rename(path .. ".tmp", path)
end

function Daily.forget()
    Daily.edition, Daily.loaded = nil, true
    os.remove(Daily.cachePath())
    pcall(Daily.clearPictures)
end

---------------------------------------------------------------- once a day

--- Is today's edition missing (and the paper on, with feeds)?
function Daily.due(plugin, now)
    if not Daily.enabled(plugin) then return false end
    local edition = Daily.load()
    return not edition or edition.day ~= Daily.day(now)
end

--- Fetch the feeds in the background and keep the new edition.
--- on_done(ok, err): err "busy", "off", "no feeds", "unreachable", "empty", "timeout".
function Daily.refresh(plugin, on_done)
    on_done = on_done or function() end
    if Daily.noWifi() then return on_done(false, "usb") end
    if Daily.refreshing then return on_done(false, "busy") end
    local feeds = Daily.feeds(plugin)
    if #feeds == 0 then return on_done(false, "no feeds") end
    Daily.refreshing = true
    local now = os.time()
    Daily.tried_at = math.max(Daily.tried_at or 0, now)
    Daily.changed()
    local pictures = Daily.pictures(plugin)
    local weather_plan = require("gzreader_weather").plan(plugin)
    local full = Daily.fullStories(plugin)
    -- (the AI edition: what a job needs to ask, copied now; nil when it's off)
    local ai = Daily.aiOn(plugin) and require("gzreader_ai").snapshot(plugin) or nil
    -- (the order asked for: Settings → Daily paper → Story order)
    local how = Daily.how(plugin)
    require("gzreader_async").run({}, function()
        local edition, err = Daily.build(feeds, now, Daily.fetch)
        if not edition then return nil, err end
        Daily.arrange(edition, how)
        -- (the day's weather, for the front page's box: gzreader_weather.lua)
        if weather_plan then
            local okw, weather = pcall(require("gzreader_weather").fetch, weather_plan, now)
            edition.weather = okw and weather or nil
            if not edition.weather then Log.warn("daily paper: no weather") end
        end
        -- (whole stories: the short ones' own pages, after the weather and before the pictures)
        if full then
            edition.full, edition.pages = Daily.addFullText(edition, Daily.fetchPage)
        end
        -- (pictures: after the stories, into the cache folder; a new edition's replace the old one's)
        if pictures then
            Daily.clearPictures()
            edition.pictures = Daily.addPictures(edition, Daily.pictureDir(), Daily.fetchPicture)
        else
            Daily.addPictures(edition, Daily.pictureDir(), function() return nil end)
            Daily.clearPictures()
        end
        -- (the AI edition: each story's summary, last, so a slow service delays nothing else)
        if ai then
            local AI = require("gzreader_ai")
            local why
            -- (first the order the AI chooses: the summaries then go to the paper's first stories)
            if how.ai then
                local ordered, owhy = Daily.aiOrder(edition, function(q) return AI.complete(ai, q) end, how.style == "mixed_good")
                if not ordered then Log.warn("daily paper: the AI's order wasn't used:", tostring(owhy)) end
            end
            edition.summaries, edition.summaries_asked, why = Daily.addSummaries(edition, function(q) return AI.complete(ai, q) end)
            edition.ai = ai.provider
            if why then Log.warn("daily paper: a summary wasn't given:", tostring(why)) end
        end
        return edition
    end, function(edition, err)
        Daily.refreshing = false
        if type(edition) ~= "table" then
            Daily.last_error = err or "unreachable"
            Log.warn("daily paper: no edition:", tostring(err))
            Daily.changed()
            return on_done(false, Daily.last_error)
        end
        Daily.last_error = nil
        Daily.keep(edition)
        Log.info("daily paper:", Daily.count(edition), "stories in", #edition.sections, "sections;", #(edition.failed or {}), "feeds failed;",
            tonumber(edition.pictures) or 0, "pictures;", tonumber(edition.full) or 0, "whole stories from", tonumber(edition.pages) or 0, "pages;",
            tonumber(edition.summaries) or 0, "summaries" .. (edition.ai and (" by " .. tostring(edition.ai) .. " of " .. tostring(edition.summaries_asked or 0) .. " asked") or ""))
        Daily.changed()
        on_done(true)
    end, "daily paper", { timeout = 300 + Daily.FULL_SECONDS + 120 + (ai and Daily.AI_SECONDS + 120 or 0) })
end

--- Today's edition, if it's due and wasn't tried a moment ago: with Wi-Fi
--- on, or brought on (not when you turned Wi-Fi off). Quiet: nothing shown.
function Daily.maybeRefresh(plugin, now)
    now = now or os.time()
    if Daily.noWifi() then return false end -- (the sync page brings it)
    if Daily.refreshing or not Daily.due(plugin, now) then return false end
    if Daily.tried_at and now - Daily.tried_at < Daily.RETRY and now >= Daily.tried_at then return false end
    Daily.tried_at = now
    require("gzreader_net").run(function() Daily.refresh(plugin) end, { quiet = true, reason = "the daily paper" })
    return true
end

--- Something to show changed (an edition came, a try began or failed):
--- Home's row and the open paper are drawn again.
function Daily.changed()
    for _i, fn in pairs(Daily.listeners or {}) do pcall(fn) end
end

function Daily.listen(name, fn)
    Daily.listeners = Daily.listeners or {}
    Daily.listeners[name] = fn
end

--- Why there's no paper, in words.
function Daily.why(err)
    if err == "usb" then return _("This Kindle gets the daily paper when it syncs with the computer: plug it in and open the sync page. Feeds whose sites don't let a web page read them can't come that way.") end
    if err == "no feeds" then return _("No feeds are ticked: Settings → Home and tabs → Daily paper → Feeds.") end
    if err == "busy" then return _("Already fetching today's paper…") end
    if err == "empty" then return _("The feeds answered, but had no stories.") end
    if err == "timeout" then return _("The feeds took too long to answer.") end
    return _("Couldn't reach the feeds. Check the Wi-Fi and try again.")
end

---------------------------------------------------------------- without Wi-Fi

Daily.USB_PAGES = 40 -- stories' pages the sync page tries (whole stories)

--- What the sync page needs to fetch the paper (outbox.json's daily), or nil
--- when the paper is off. Feeds' addresses only go to the drive (the page
--- reads them there), never to the log.
function Daily.outbox(plugin)
    if not Daily.enabled(plugin) then return nil end
    local feeds = {}
    for _i, f in ipairs(Daily.feeds(plugin)) do
        feeds[#feeds + 1] = { url = f.url, name = f.name or Daily.site(f.url), topic = f.topic }
    end
    if #feeds == 0 then return nil end
    local edition = Daily.load()
    return { feeds = feeds, full = Daily.fullStories(plugin), per_feed = Daily.PER_FEED, pages = Daily.USB_PAGES,
        max_bytes = Daily.MAX_BYTES, have = edition and edition.day or nil }
end

--- An edition from the files the sync page brought (in `dir`): `d` is
--- inbox.json's daily, { at = the computer's time (s), feeds = { { url, file, name, topic } },
--- failed = { names }, pages = { { url, file } } } (files relative to dir).
--- Made as over Wi-Fi (Daily.build, Daily.addFullText). → edition, or nil and why.
function Daily.fromFiles(feeds, dir, d, full)
    local function reader(list)
        local files = {}
        for _i, e in ipairs(type(list) == "table" and list or {}) do
            if type(e) == "table" and type(e.url) == "string" and type(e.file) == "string"
                and not e.file:find("..", 1, true) and not e.file:match("^/") then
                files[e.url] = dir .. "/" .. e.file
            end
        end
        return function(url)
            local path = files[url]
            local f = path and io.open(path, "rb")
            if not f then return nil, "unreachable" end
            local body = f:read(Daily.MAX_BYTES * 4 + 1)
            f:close()
            if not body or body == "" then return nil, "empty" end
            if #body > Daily.MAX_BYTES * 4 then return nil, "too big" end
            return body
        end
    end
    local now = tonumber(d.at)
    if not now or now < 1704067200 then now = os.time() end
    local edition, err = Daily.build(feeds, now, reader(d.feeds))
    if not edition then return nil, err end
    -- (feeds the page couldn't read: their sites don't let a web page in)
    local named = {}
    for _i, f in ipairs(edition.failed) do named[f] = true end
    for _i, name in ipairs(type(d.failed) == "table" and d.failed or {}) do
        if type(name) == "string" and not named[name] then named[name] = true; edition.failed[#edition.failed + 1] = name end
    end
    if full and type(d.pages) == "table" and #d.pages > 0 then
        local page = reader(d.pages)
        edition.full, edition.pages = Daily.addFullText(edition, function(url) return page(url) end)
    end
    edition.usb = true
    return edition
end

--- Where what the sync page brought for the paper waits (out of the sync
--- folder, which is emptied once taken in) while the edition is made.
function Daily.inDir() return require("datastorage"):getDataDir() .. "/cache/gzreader-daily-in" end

local function rmrf(path)
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then rmrf(path .. "/" .. name) end
        end
        lfs.rmdir(path)
    else
        os.remove(path)
    end
end

--- The paper from what the sync page brought: the files in `from` (the
--- sync folder's in/daily) moved aside, the edition made in the background
--- (a Kindle DX takes a while over 40 stories' pages) and kept.
--- on_done(stories or nil, why). → true when it's under way.
function Daily.fromComputer(plugin, from, d, on_done)
    on_done = on_done or function() end
    if type(d) ~= "table" or type(d.feeds) ~= "table" or not Daily.enabled(plugin) then return false end
    -- (the feeds as the page fetched them: those the outbox named then)
    local feeds = {}
    for _i, f in ipairs(d.feeds) do
        if type(f) == "table" and type(f.url) == "string" then
            feeds[#feeds + 1] = { url = f.url, name = type(f.name) == "string" and f.name or nil,
                topic = type(f.topic) == "string" and f.topic ~= "" and f.topic or Daily.OWN_TOPIC }
        end
    end
    if #feeds == 0 then return false end
    local dir = Daily.inDir()
    rmrf(dir)
    require("util").makePath(dir:match("^(.*)/[^/]+$"))
    if not os.rename(from, dir) then
        Log.warn("daily paper: couldn't keep what the computer brought")
        return false
    end
    local full = Daily.fullStories(plugin)
    local function finish(edition, err)
        rmrf(dir)
        if type(edition) ~= "table" then
            Daily.last_error = err or "empty"
            Log.warn("daily paper: nothing from the computer:", tostring(err))
            Daily.changed()
            return on_done(nil, Daily.last_error)
        end
        -- (no pictures this way: a web page can't read other sites' pictures)
        Daily.addPictures(edition, Daily.pictureDir(), function() return nil end)
        Daily.clearPictures()
        Daily.last_error = nil
        Daily.arrange(edition, Daily.how(plugin))
        Daily.keep(edition)
        Log.info("daily paper (from the computer):", Daily.count(edition), "stories in", #edition.sections, "sections;",
            #(edition.failed or {}), "feeds not readable;", tonumber(edition.full) or 0, "whole stories")
        Daily.changed()
        on_done(Daily.count(edition))
    end
    local function go()
        require("gzreader_async").background(function() return Daily.fromFiles(feeds, dir, d, full) end, function(edition, err)
            if edition == nil and err == "busy" then
                return require("ui/uimanager"):scheduleIn(20, go)
            end
            finish(edition, err)
        end, "daily paper from the computer", { timeout = 600 })
    end
    go()
    return true
end

return Daily
