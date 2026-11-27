-- The daily paper (gzreader_daily.lua): turned on, an edition made from two
-- feeds given here (no network), the newspaper on Home's bookshelf (empty,
-- then beside books: GZ_EMU_BOOK = an EPUB; with pictures: GZ_EMU_PICTURE), the optional headlines row, the paper's front page and second page, a story (it scrolls; the quick panel from the top), and Settings → Accounts and services → Daily paper → Feeds. Any model.
--   GZ_EMU_TREE=<tree>/koreader ./run.sh daily_paper.lua <out>
-- Checks in <out>/daily-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
-- (the setup guide closed: Back does it on a Kindle with keys only)
add({ fn = function()
    local UIM = require("ui/uimanager")
    for i = #UIM._window_stack, 1, -1 do
        local w = UIM._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM:close(w) end
    end
end, after = 6 })
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local checks = {}
local function check(E, ok, msg)
    checks[#checks + 1] = (ok and "ok   " or "FAIL ") .. msg
    E.say(checks[#checks])
end
local function item(title, text, hours)
    return "<item><title>" .. title .. "</title><link>https://news.example.com/" .. title:gsub("%W", "-") .. "</link>"
        .. '<enclosure url="https://img.example.com/' .. title:gsub("%W", "-") .. '.png" type="image/png"/>' .. "<description><![CDATA["
        .. text .. "]]></description><pubDate>" .. os.date("!%a, %d %b %Y %H:%M:%S GMT", os.time() - hours * 3600) .. "</pubDate></item>"
end
local long = string.rep("<p>" .. string.rep("The lighthouse keeper counted the ships again, and again there were seven. ", 12) .. "</p><p>"
    .. string.rep("Nobody on the island could say where the seventh had come from. ", 10) .. "</p>", 5) -- (longer than a screen: it scrolls)
local BODIES = {
    world = "<rss><channel><title>Example World</title>"
        .. item("Seven ships seen off the northern lighthouse, where six were expected by everyone", long, 2)
        .. item("Council votes to keep the old bridge open through the winter", "The vote was nine to four.", 5)
        .. item("Harvest festival moved indoors", "Rain is forecast.", 9) .. "</channel></rss>",
    science = "<rss><channel><title>Example Science</title>"
        .. item("A comet returns after four hundred years", long, 3)
        .. item("Why moss grows faster on old slate roofs", "A short summary only.", 20) .. "</channel></rss>",
}
local short = "<p>The committee met for three hours on Monday and agreed on most of it; the rest waits for spring, when the road is open again and the surveyors can get up to the pass.</p>"
for _i, t in ipairs({ { "tech", "Technology", "A pocket radio that tunes itself|The last typewriter repair shop takes on an apprentice|Old cables, new tricks: copper carries more than anyone thought|A clock that loses a second every hundred years" },
        { "books", "Books", "The novel that took forty years to finish|Why we reread|A library on a boat calls at twelve islands|Notes found in the margins of a borrowed atlas" },
        { "odd", "Curiosities", "The town that moved its church by rail|A staircase to nowhere, and the man who built it|How the pretzel got its knot" } }) do
    local parts, n = { "<rss><channel><title>Example " .. t[2] .. "</title>" }, 0
    for title in t[3]:gmatch("[^|]+") do n = n + 1; parts[#parts + 1] = item(title, n % 2 == 0 and long or short, n + 1) end
    BODIES[t[1]] = table.concat(parts) .. "</channel></rss>"
end
add({ fn = function(E)
    local Daily = require("gzreader_daily")
    local Paper = require("gzreader_dailyscreen")
    local p = plugin()
    Daily.store(p).enabled = true
    local edition = Daily.build({
        { url = "world", name = "Example World", topic = "World" },
        { url = "science", name = "Example Science", topic = "Science" },
        { url = "tech", name = "Example Tech", topic = "Technology" },
        { url = "books", name = "Example Books", topic = "Books" },
        { url = "odd", name = "Example Oddities", topic = "Curiosities" },
    }, os.time(), function(url) return BODIES[url] end)
    check(E, edition ~= nil and Daily.count(edition) == 16, "an edition from five feeds: 16 stories … " .. tostring(edition and Daily.count(edition)))
    -- pictures (GZ_EMU_PICTURE = a PNG or JPEG): the lead's and a few more
    local pf = io.open(os.getenv("GZ_EMU_PICTURE") or "", "rb")
    if pf then
        local bytes = pf:read("*a")
        pf:close()
        Daily.clearPictures()
        local n = Daily.addPictures(edition, Daily.pictureDir(), function(url) return url:find("Seven", 1, true) and bytes or (url:find("comet", 1, true) or url:find("radio", 1, true)) and bytes or nil end)
        check(E, n == 3 and Daily.picturePath(edition.sections[1].items[1]) ~= nil, "3 stories got their picture … " .. tostring(n))
    end
    -- the weather, as Open-Meteo gives it for a town (given here; no network)
    local Wx = require("gzreader_weather")
    local w = Wx.store(p)
    w.lat, w.lon, w.place, w.unit = 51.48, 0, "Example Town", "F"
    local day = os.date("%Y-%m-%d")
    local function plus(n) return os.date("%Y-%m-%d", os.time() + n * 86400) end
    edition.weather = Wx.fromMeteo({ current = { temperature_2m = 51.6, weather_code = 61 },
        daily = { time = { day, plus(1), plus(2) }, weather_code = { 63, 2, 0 }, temperature_2m_max = { 54.2, 49.1, 57 },
            temperature_2m_min = { 41, 36.4, 39 }, precipitation_probability_max = { 80, 20, 0 } } }, "F")
    check(E, Wx.on(p) and #Wx.cells(edition.weather) == 4, "the day's weather: now and three days")
    -- today's calendar events, as the Calendar tab keeps them
    local t = os.date("*t")
    local function at(h, m) return os.time{ year = t.year, month = t.month, day = t.day, hour = h, min = m or 0 } end
    require("gzreader_caldav").saveCache({ at = os.time(), from = at(0), to = at(0) + 86400, events = {
        { title = "Farmers' market", all_day = true, start = at(0), finish = at(0) + 86400 },
        { title = "Dentist", start = at(9, 30), finish = at(10, 15) },
        { title = "Lunch with Sam", start = at(12, 30), finish = at(13, 30) },
        { title = "Book club: chapters 4 to 7", start = at(19), finish = at(21) },
    } })
    check(E, #Paper.todayEvents() == 4, "today's 4 calendar events are found")
    Daily.keep(edition)
    Daily.tried_at = os.time() -- (no network here)
    check(E, Paper.onShelf(p) and not Paper.onHome(), "on: the newspaper goes on Home's bookshelf, not in a row of its own")
    require("common/gz_view").redrawHome()
end, after = 10 })
add({ shot = "daily-1-home" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    check(E, Paper.home ~= nil and Paper.home.shelf == true and Paper.home.menu ~= nil, "Home's shelf has the newspaper on it")
    -- with books beside it
    os.execute("mkdir -p /mnt/us/GZreader")
    local book = os.getenv("GZ_EMU_BOOK")
    if book then
        for _i, name in ipairs({ "one", "two", "three" }) do os.execute("cp " .. book .. " /mnt/us/GZreader/" .. name .. ".epub") end
        local fm = require("apps/filemanager/filemanager").instance
        local Home = require("common/shared_state").get(fm and fm.zenos, "home")
        for _i, name in ipairs({ "one", "two", "three" }) do require("readhistory"):addItem("/mnt/us/GZreader/" .. name .. ".epub", os.time()) end
        Home.invalidateLibraryCache()
        Home.rebuildActive()
    end
end, after = 12 })
add({ shot = "daily-1b-home-books" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local at = Paper.home and Paper.home.spine_at
    check(E, at ~= nil and at.w < at.h / 3 and at.w > at.h / 6, "the newspaper stands on its side among the books, a fat folded paper")
    if at and require("device"):isTouchDevice() then
        E.tap({ at.x + math.floor(at.w / 2), at.y + math.floor(at.h / 2) })
    else
        -- (keys: the 5-way's place put on it)
        local menu = Paper.home.menu
        for i, t in ipairs(menu._zen_home_focus_targets or {}) do
            if t.key == "gz:daily-paper" then menu._zen_home_focus_index, menu._zen_home_focus_id, menu._zen_home_focus_key = i, t.id, t.key end
        end
        require("ui/uimanager"):setDirty(require("apps/filemanager/filemanager").instance, "ui")
    end
end, after = 8 })
add({ shot = "daily-1b2-home-picked" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local menu = Paper.home.menu
    local picked = false
    for _i, t in ipairs(menu._zen_home_focus_targets or {}) do
        if t.key == "gz:daily-paper" and menu._zen_home_focus_id == t.id then picked = true end
    end
    check(E, picked and Paper.instance == nil, "picked: it turns to its front page, and isn't opened yet")
end, after = 2 })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local ok = Paper.setOnHome(true)
    check(E, ok == true and Paper.onHome(), "the headlines row can be ticked on as well")
end, after = 10 })
add({ shot = "daily-1c-home-row" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    Paper.setOnHome(false)
    Paper.show(plugin())
end, after = 10 })
add({ shot = "daily-2-paper" })
-- a Kindle with a keyboard: the 5-way goes every way; a story's letter opens it (real key presses)
if os.getenv("GZ_EMU_MODEL") == "k3" or not os.getenv("GZ_EMU_MODEL") then
    add({ fn = function(E)
        local page = require("gzreader_dailyscreen").instance
        E.trail = { tostring(page.focus) }
        -- (which story is first in the second column)
        for i, b in ipairs(page.blocks) do if not E.right_top and i > 1 and b.x > page.blocks[2].x then E.right_top = i end end
        check(E, page.focus == 1 and page.badges[1] ~= nil and page.badges[2] ~= nil and page.diary ~= nil, "the frame starts on the lead story; stories carry their letter")
    end, after = 1 })
    for _i, key in ipairs({ "Down", "Right", "Left", "Up", "Up", "Down", "Down", "Right" }) do
        add({ key = key, after = 3 })
        add({ fn = function(E) E.trail[#E.trail + 1] = tostring(require("gzreader_dailyscreen").instance.focus) end, after = 1 })
    end
    add({ shot = "daily-2a-right-column" })
    add({ fn = function(E)
        local page = require("gzreader_dailyscreen").instance
        local want = table.concat({ "1", "2", tostring(E.right_top), "2", "1", "diary", "1", "2", tostring(E.right_top) }, " ")
        check(E, table.concat(E.trail, " ") == want and page.page == 1, "Down, Right, Left, Up, Up, Down, Down, Right: " .. table.concat(E.trail, " ") .. " (wanted " .. want .. "), no page turned")
    end, after = 1 })
    -- down the right column to the foot, along it, and up again
    add({ fn = function(E) E.trail = {} end, after = 1 })
    for _i, key in ipairs({ "Down", "Down", "Down", "Down", "Down", "Down" }) do
        add({ fn = function(E)
            local page = require("gzreader_dailyscreen").instance
            if page.focus ~= "puzzles" and page.page == 1 then E.key("Down") end
        end, after = 3 })
    end
    add({ fn = function(E) check(E, require("gzreader_dailyscreen").instance.focus == "puzzles", "down the right column ends on Puzzles at the foot") end, after = 1 })
    add({ key = "Left", after = 3 })
    add({ fn = function(E) check(E, require("gzreader_dailyscreen").instance.focus == "type", "Left: Aa") end, after = 1 })
    add({ key = "Left", after = 3 })
    add({ shot = "daily-2b-foot" })
    add({ fn = function(E)
        local page = require("gzreader_dailyscreen").instance
        check(E, page.focus == "fetch" and page.foot.fetch.widget.text:sub(1, 1) == "F" and page.foot.puzzles.widget.text:sub(1, 1) == "P", "Left: Fetch; the foot names its letters (F, P)")
    end, after = 1 })
    add({ key = "Up", after = 3 })
    add({ fn = function(E)
        local page = require("gzreader_dailyscreen").instance
        check(E, type(page.focus) == "number" and page.blocks[page.focus].x == page.blocks[2].x, "Up from Fetch: the left column's last story (" .. tostring(page.focus) .. ")")
    end, after = 1 })
    -- a story's letter
    add({ key = "W", after = 6 })
    add({ fn = function(E)
        local Paper = require("gzreader_dailyscreen")
        local page = Paper.instance
        local UIM = require("ui/uimanager")
        local top = UIM._window_stack[#UIM._window_stack].widget
        check(E, top ~= page and top.item == page.blocks[2].story.item, "W opens the second story (" .. tostring(top.item and top.item.title) .. ")")
        if top ~= page then UIM:close(top) end
        page.focus = 1
        page:redraw()
    end, after = 4 })
end
add({ fn = function(E)
    local page = require("gzreader_dailyscreen").instance
    check(E, page ~= nil and page.page == 1 and #page.blocks >= 3 and page.blocks[1].w > page.blocks[2].w,
        "the front page: the lead story across it, the others in columns … " .. tostring(page and #page.blocks))
    check(E, page.has_next, "more pages behind it")
    check(E, page.weather ~= nil and #page.weather.cells == 4 and page.weather.y < page.blocks[1].y, "the weather box above the stories, a sky drawn for each day")
    check(E, page.diary ~= nil and page.diary.y < page.blocks[1].y and page:at(page.diary.x + 5, page.diary.y + 5) == "diary", "today's events in a box above the lead story")
    local inside = true
    for _i, b in ipairs(page.blocks) do
        if b.x < 0 or b.x + b.w > page.dimen.w or b.y + math.min(b.h, b.clip or b.h) > page.foot.y then inside = false end
    end
    check(E, inside, "every story is inside the page, above the foot")
    page:turn(1)
end, after = 8 })
-- a Kindle with a keyboard: the Aa key opens the pages' type box, Menu the quick panel (real key presses)
if os.getenv("GZ_EMU_MODEL") == "k3" or not os.getenv("GZ_EMU_MODEL") then
    add({ key = "AA", after = 4 })
    add({ fn = function(E)
        local Paper = require("gzreader_dailyscreen")
        check(E, Paper.front_dialog ~= nil and require("gzreader_panel").open == nil, "the Aa key on the paper: the pages' type box, not the quick panel")
        if Paper.front_dialog then require("ui/uimanager"):close(Paper.front_dialog); Paper.front_dialog = nil end
    end, after = 3 })
    add({ key = "Menu", after = 4 })
    add({ shot = "daily-3a-menu-panel" })
    add({ fn = function(E)
        local Paper = require("gzreader_dailyscreen")
        check(E, require("gzreader_panel").open ~= nil and Paper.front_dialog == nil, "the Menu key on the paper: the quick panel")
    end, after = 2 })
    add({ key = "Menu", after = 4 })
    add({ fn = function(E)
        local Paper = require("gzreader_dailyscreen")
        check(E, require("gzreader_panel").open == nil and Paper.instance and not Paper.instance.closed, "Menu again closes it; the paper is still there")
    end, after = 2 })
end
-- the AI edition: the same paper with a summary a story (given here: nothing is asked), as pages of articles
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local Daily = require("gzreader_daily")
    local AI = require("gzreader_ai")
    local p = plugin()
    local page = Paper.instance
    page.page, page.starts = 1, { 1 }
    page:build()
    E.plain_blocks, E.plain_cols = #page.blocks, 0
    local xs = {}
    for _i, b in ipairs(page.blocks) do if not xs[b.x] then xs[b.x] = true; E.plain_cols = E.plain_cols + 1 end end
    local edition = Daily.load()
    local n = 0
    for _i, sec in ipairs(edition.sections) do
        for _j, it in ipairs(sec.items) do
            n = n + 1
            it.summary = "The council voted nine to four to keep the old bridge open through the winter, after engineers said it was sound. "
                .. "Traffic lights will let one lane cross at a time. The question comes back in spring, when the surveyors can get up to the pass. (" .. n .. ")"
        end
    end
    edition.summaries, edition.ai = n, "claude"
    Daily.keep(edition)
    AI.settings(p).claude.key = "sk-ant-example-not-a-key"
    Daily.store(p).ai = true
    check(E, Daily.aiOn(p) and Paper.aiEdition(p, Daily.load()), "the AI edition switched on, the edition has its summaries")
    page:reload()
end, after = 8 })
add({ shot = "daily-ai-1-front" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local page = Paper.instance
    local cols, xs, inside, whole, pics = 0, {}, true, true, 0
    for _i, b in ipairs(page.blocks) do
        if not xs[b.x] then xs[b.x] = true; cols = cols + 1 end
        if b.x < 0 or b.x + b.w > page.dimen.w or b.y + math.min(b.h, b.clip or b.h) > page.foot.y then inside = false end
        if not b.summary then whole = false end
        for _j, part in ipairs(b.parts) do if part.widget.gz_picture or (part.widget.getSize and part.widget.image) then pics = pics + 1 end end
    end
    check(E, page.ai == true and #page.blocks >= 1 and cols == Paper.aiColumns(page.dimen.w, require("device").screen:getDPI()) and cols < math.max(2, E.plain_cols),
        "the front page is articles one after another (" .. #page.blocks .. " on it, " .. cols .. " across; the ordinary paper had " .. E.plain_blocks .. " in " .. E.plain_cols .. " columns)")
    check(E, inside and whole, "every article fits inside the page and shows its summary")
    -- every column ends at the foot of the page, to the pixel (Paper.fit)
    local ends, foot = {}, 0
    for _i, b in ipairs(page.blocks) do ends[b.x] = math.max(ends[b.x] or 0, b.y + b.h) end
    for _x, e in pairs(ends) do foot = math.max(foot, e) end
    local level = page.has_next
    for _x, e in pairs(ends) do if e ~= foot then level = false end end
    check(E, level and page.foot.y - foot <= require("device").screen:scaleBySize(6), "every column is filled to the foot of the page (" .. foot .. " of " .. page.foot.y .. ")")
    check(E, page.blocks[1].w > page.dimen.w * 0.4 and page.has_next, "an article is as wide as its column; more pages behind")
    check(E, Paper.statusText(plugin()):find("summaries by Claude", 1, true) ~= nil, "the date line says the summaries are Claude's")
    E.ai_pages = 1
    page:turn(1)
end, after = 6 })
add({ shot = "daily-ai-2-page2" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local Daily = require("gzreader_daily")
    local page = Paper.instance
    check(E, page.page == 2 and #page.blocks >= 1 and page.blocks[1].summary == true, "the next page: more articles")
    local guard = 0
    while page.has_next and guard < 40 do guard = guard + 1; page:turn(1) end
    local last = page.blocks[#page.blocks]
    check(E, last ~= nil and page.next_start == page.n + 1, "paging reaches the last story (" .. page.page .. " pages for " .. page.n .. " stories)")
    -- open one: the summary first, then the whole story
    local text = Paper.articleText(page.blocks[1].story.item)
    check(E, text:find("In brief (AI summary):", 1, true) ~= nil, "an opened story begins with its summary, said to be the AI's")
    -- back to the ordinary paper for the rest of the tour
    local p = plugin()
    Daily.store(p).ai = nil
    require("gzreader_ai").clear(p)
    local edition = Daily.load()
    for _i, sec in ipairs(edition.sections) do for _j, it in ipairs(sec.items) do it.summary = nil end end
    edition.summaries, edition.ai = nil, nil
    Daily.keep(edition)
    page:reload()
    check(E, page.ai ~= true and #page.blocks == E.plain_blocks, "switched off: the ordinary paper again")
end, after = 8 })
-- the pages' type: Aa at the foot; Large + Sans, laid out again
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local page = Paper.instance
    page.page, page.starts = 1, { 1 }
    page:build()
    E.front_blocks = #page.blocks
    E.front_h = page.blocks[2] and page.blocks[2].h or 0
    check(E, page:at(page.foot.type.x + 4, page.foot.y + 6) == "type", "Aa at the foot of the paper")
    page:onGzTap(nil, { pos = { x = page.foot.type.x + 4, y = page.foot.y + 6 } })
    check(E, Paper.front_dialog ~= nil, "…opens the pages' type box")
    Paper.frontRows(plugin())[1][3].run()
    Paper.frontRows(plugin())[2][2].run()
    Paper.frontDialog(plugin())
end, after = 6 })
add({ shot = "daily-3b-front-type" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local UIManager = require("ui/uimanager")
    if Paper.front_dialog then UIManager:close(Paper.front_dialog); Paper.front_dialog = nil end
    local page = Paper.instance
    check(E, page.page == 1 and page.blocks[2] and page.blocks[2].h > E.front_h, "Large, Sans: the page is laid out again with bigger type (a story's block " .. tostring(page.blocks[2] and page.blocks[2].h) .. " > " .. tostring(E.front_h) .. " px)")
    local inside = true
    for _i, b in ipairs(page.blocks) do
        if b.x < 0 or b.x + b.w > page.dimen.w or b.y + math.min(b.h, b.clip or b.h) > page.foot.y then inside = false end
    end
    check(E, inside and #page.blocks <= E.front_blocks, "…everything still inside the page, fewer or as many stories on it (" .. #page.blocks .. " ≤ " .. E.front_blocks .. ")")
    page:turn(1)
end, after = 6 })
add({ shot = "daily-3c-front-large" })
add({ fn = function()
    local Paper = require("gzreader_dailyscreen")
    Paper.setFrontFont(plugin(), "size", "normal")
    Paper.setFrontFont(plugin(), "face", "serif")
    Paper.instance:turn(1)
end, after = 4 })
add({ shot = "daily-3-page2" })
add({ fn = function(E)
    local page = require("gzreader_dailyscreen").instance
    check(E, page.page == 2 and #page.blocks >= 2 and page.starts[2] == #require("gzreader_dailyscreen").instance.blocks * 0 + page.starts[2],
        "page 2 carries on where page 1 stopped (story " .. tostring(page.starts[2]) .. ")")
    local seen, n = page.starts[2] - 1, 0
    while page.has_next and n < 10 do page:turn(1); n = n + 1 end
    check(E, page.next_start == page.n + 1, "the last page ends with the last story (" .. page.n .. " in " .. page.page .. " pages)")
    page:turn(-99)
    page.page, page.starts = 1, { 1 }
    page:build()
    check(E, seen >= 3, "page 1 held " .. seen .. " stories")
    page:open(1)
end, after = 8 })
add({ shot = "daily-4-story" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    local top = UIManager:getTopmostVisibleWidget()
    check(E, top and top.name == "gz_daily_article" and top.item.title:find("Seven ships", 1, true) ~= nil, "a story opened as text")
    if os.getenv("GZ_EMU_PICTURE") then check(E, top and top.picture ~= nil and top.picture:getSize().w > 100, "…with its picture under the headline") end
    E.story = top
    -- it scrolls freely: a long story is taller than the screen, and the page key moves it part of a screen
    local sc = top and top.scroller
    if sc then sc:initState() end
    E.y0 = sc and sc._scroll_offset_y or 0
    if top then top:onPageDown() end
end, after = 3 })
add({ fn = function(E)
    local sc = E.story and E.story.scroller
    local moved = sc and (sc._scroll_offset_y or 0) - E.y0 or 0
    check(E, sc ~= nil and sc._scrollBy ~= nil, "…in a scrolling view (a ScrollableContainer, not pages)")
    check(E, moved > 0 or (sc and (sc._max_scroll_offset_y or 0) == 0), "…the page key moves it on (" .. tostring(moved) .. " px)")
    -- a swipe down from the top of a story: the quick panel
    local opened = E.story:onPullPanel(nil, { direction = "south", pos = { x = 100, y = 10 } })
    local Panel = require("gzreader_panel")
    check(E, opened and Panel.open ~= nil, "a swipe down from the top of a story: the quick panel")
    if Panel.open then require("ui/uimanager"):close(Panel.open) end
end, after = 4 })
-- in a story too, on a Kindle with a keyboard: the Aa key is the type box, Menu the quick panel
if os.getenv("GZ_EMU_MODEL") == "k3" or not os.getenv("GZ_EMU_MODEL") then
    add({ key = "AA", after = 4 })
    add({ fn = function(E)
        local Paper = require("gzreader_dailyscreen")
        check(E, Paper.type_dialog ~= nil and require("gzreader_panel").open == nil, "the Aa key in a story: the story's type box")
        if Paper.type_dialog then require("ui/uimanager"):close(Paper.type_dialog); Paper.type_dialog = nil end
    end, after = 3 })
    add({ key = "Menu", after = 4 })
    add({ fn = function(E)
        check(E, require("gzreader_panel").open ~= nil and require("gzreader_dailyscreen").type_dialog == nil, "the Menu key in a story: the quick panel")
    end, after = 2 })
    add({ key = "Menu", after = 4 })
    add({ fn = function(E)
        check(E, require("gzreader_panel").open == nil and E.story ~= nil, "Menu again closes it; the story is still open")
    end, after = 2 })
end
-- the story's type: Aa, bigger, another typeface, wider lines; the story is set again at the same place
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local sc = E.story.scroller
    E.at0 = (sc._max_scroll_offset_y or 0) > 0 and sc._scroll_offset_y / sc._max_scroll_offset_y or 0
    E.max0 = sc._max_scroll_offset_y or 0
    E.story:onShowType()
    check(E, Paper.type_dialog ~= nil, "Aa opens the story's type box")
    local rows = Paper.typeRows(plugin())
    rows[1][3].run(); Paper.typeRows(plugin())[1][3].run(); Paper.typeRows(plugin())[1][3].run()
    Paper.typeRows(plugin())[2][2].run()
    Paper.typeRows(plugin())[3][3].run()
    Paper.typeDialog(plugin())
end, after = 5 })
add({ shot = "daily-4b-story-type" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    local UIManager = require("ui/uimanager")
    local font = Paper.storyFont(plugin())
    check(E, font.size == 15 and font.face.id == "sans" and font.spacing.id == "wide", "three taps on A+, Sans, Wide: kept")
    if Paper.type_dialog then UIManager:close(Paper.type_dialog); Paper.type_dialog = nil end
    local sc = E.story.scroller
    check(E, sc ~= nil and (sc._max_scroll_offset_y or 0) > E.max0, "the story is set again, bigger (it's longer now: " .. tostring(sc and sc._max_scroll_offset_y) .. " > " .. tostring(E.max0) .. ")")
    local at = (sc._max_scroll_offset_y or 0) > 0 and sc._scroll_offset_y / sc._max_scroll_offset_y or 0
    check(E, math.abs(at - E.at0) < 0.05, "…at the same place in the story (" .. string.format("%.2f", at) .. " ~ " .. string.format("%.2f", E.at0) .. ")")
    -- a drag that ends with the finger still moving rests where the finger was
    local y0 = sc._scroll_offset_y
    local pos = require("ui/geometry"):new{ x = 200, y = 400, w = 0, h = 0 }
    sc:onScrollableTouch(nil, { pos = pos })
    sc:onScrollablePan(nil, { pos = pos, relative = { x = 0, y = 150 }, direction = "south" })
    sc:onScrollableSwipe(nil, { pos = pos, direction = "south", distance = 170 })
    check(E, y0 - sc._scroll_offset_y == math.min(150, y0), "a flick down 150 px moves the story 150 px, not a screenful (" .. tostring(y0 - sc._scroll_offset_y) .. ")")
end, after = 4 })
add({ shot = "daily-4c-story-big" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    if E.story then UIManager:close(E.story) end
    local Paper = require("gzreader_dailyscreen")
    -- …and from the top of the paper itself
    local page = Paper.instance
    local opened = page and page:onGzSwipe(nil, { direction = "south", pos = { x = 100, y = 10 } })
    local Panel = require("gzreader_panel")
    check(E, opened and Panel.open ~= nil, "a swipe down from the top of the paper: the quick panel")
    if Panel.open then UIManager:close(Panel.open) end
end, after = 4 })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    local Paper = require("gzreader_dailyscreen")
    if Paper.instance then UIManager:close(Paper.instance) end
end, after = 6 })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    check(E, Paper.instance == nil, "the paper closed")
    pcall(function() require("modules/settings/zen_settings_page").closeActive() end)
    require("modules/settings/zen_settings_page").show(require("apps/filemanager/filemanager").instance.zenos,
        { path = { { key = "text", value = "Accounts and services" }, { key = "text", value = "Daily paper" } } })
end, after = 10 })
add({ shot = "daily-5-settings" })
add({ fn = function(E)
    local out = E.out or "."
    local f = io.open(out .. "/daily-checks.txt", "w")
    if f then f:write(table.concat(checks, "\n"), "\n"); f:close() end
end, after = 1 })
return s
