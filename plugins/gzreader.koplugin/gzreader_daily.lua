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

- Off until it's turned on (Settings → Home → Daily paper): the feeds are
  other people's sites, and each fetch tells them this Kindle's address.
  Nothing else is sent: no account, no cookies, nothing about you.
- An edition is made when the day's first look at Home (or the paper) finds
  yesterday's, with Wi-Fi on or allowed to come on (Wi-Fi: Auto / On). A
  failed try waits RETRY seconds. The paper's day starts at 5 in the morning.
- Feeds: GZreader's own list by topic (each can be ticked off) and your
  own, typed in or brought in a feeds.txt. A feed's address is never
  written to the log (only its site), as some carry a key.
- The Kindles without Wi-Fi (2, DX) have no paper yet.

The edition (settings/gzreader-daily.json):
  { day = "2026-11-17", at = seconds, sections = { { topic = "World",
    items = { { title, text, link, at, source, img } } } }, failed = { names } }
`img`: a story's picture, a file in cache/gzreader-daily/ (the lead's and a
few more: MAX_PICTURES, each MAX_PICTURE_BYTES at most; Settings can turn
pictures off). Pictures often come from another site than the feed's.
]]

local Feeds = require("gzreader_feeds")
local Log = require("gzreader_log")
local _ = require("gettext")

local Daily = {
    ROW_ID = "daily_paper",
    PER_FEED = 5,        -- stories taken from one feed
    PER_SECTION = 8,     -- stories in one section
    MAX_TEXT = 4000,     -- bytes of a story's text kept
    MAX_BYTES = 1536 * 1024, -- a feed bigger than this isn't read
    MAX_FEEDS = 24,
    FRESH = 36 * 3600,   -- stories older than this stay out (when the feed dates them)
    RETRY = 30 * 60,
    MAX_PICTURES = 8,    -- stories that get their picture (the lead, then each section's first, …)
    MAX_PICTURE_BYTES = 700 * 1024,
    EDITION_HOUR = 5,    -- a day's paper is made from this hour on (the Kindle's clock)
    TOPICS = { "World", "Technology", "Science", "Books", "Curiosities" },
    OWN_TOPIC = "Your feeds",
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
}

--- A topic's name as shown (the built-in ones are translated).
function Daily.topicLabel(topic)
    if topic == "World" then return _("World") end
    if topic == "Technology" then return _("Technology") end
    if topic == "Science" then return _("Science") end
    if topic == "Books" then return _("Books") end
    if topic == "Curiosities" then return _("Curiosities") end
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
    return Daily.store(plugin).enabled == true and not Daily.noWifi()
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
    return { enabled = st.enabled == true, shelf = st.shelf ~= false, pictures = st.pictures ~= false,
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
    return { day = Daily.day(now), at = now, sections = sections, failed = failed }
end

--- The front page: up to `n` headlines, the sections' first stories first.
function Daily.front(edition, n)
    local out = {}
    if type(edition) ~= "table" then return out end
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
            ["User-Agent"] = "GZreader (daily paper; +https://github.com/9retirement6irk/GZreader)",
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
            ["User-Agent"] = "GZreader (daily paper; +https://github.com/9retirement6irk/GZreader)" },
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
function Daily.addPictures(edition, dir, fetch, write)
    write = write or function(path, data)
        local f = io.open(path, "wb")
        if not f then return false end
        f:write(data)
        f:close()
        return true
    end
    local got = 0
    for n, item in ipairs(Daily.pictureWanted(edition)) do
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
    require("gzreader_async").run({}, function()
        local edition, err = Daily.build(feeds, now, Daily.fetch)
        if not edition then return nil, err end
        -- (pictures: after the stories, into the cache folder; a new edition's replace the old one's)
        if pictures then
            Daily.clearPictures()
            edition.pictures = Daily.addPictures(edition, Daily.pictureDir(), Daily.fetchPicture)
        else
            Daily.addPictures(edition, Daily.pictureDir(), function() return nil end)
            Daily.clearPictures()
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
            tonumber(edition.pictures) or 0, "pictures")
        Daily.changed()
        on_done(true)
    end, "daily paper", { timeout = 300 })
end

--- Today's edition, if it's due and wasn't tried a moment ago: with Wi-Fi
--- on, or brought on (not when you turned Wi-Fi off). Quiet: nothing shown.
function Daily.maybeRefresh(plugin, now)
    now = now or os.time()
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
    if err == "usb" then return _("The daily paper needs Wi-Fi, and this Kindle syncs through a computer.") end
    if err == "no feeds" then return _("No feeds are ticked: Settings → Home → Daily paper → Feeds.") end
    if err == "busy" then return _("Already fetching today's paper…") end
    if err == "empty" then return _("The feeds answered, but had no stories.") end
    if err == "timeout" then return _("The feeds took too long to answer.") end
    return _("Couldn't reach the feeds. Check the Wi-Fi and try again.")
end

return Daily
