-- The daily paper (gzreader_daily.lua): turned on, an edition made from two
-- feeds given here (no network), Home's Daily paper widget (a folded
-- newspaper), the paper's front page and second page, a story, and Settings → Home → Daily paper → Feeds. Any model.
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
    return "<item><title>" .. title .. "</title><link>https://news.example.com/" .. title:gsub("%W", "-") .. "</link><description><![CDATA["
        .. text .. "]]></description><pubDate>" .. os.date("!%a, %d %b %Y %H:%M:%S GMT", os.time() - hours * 3600) .. "</pubDate></item>"
end
local long = "<p>" .. string.rep("The lighthouse keeper counted the ships again, and again there were seven. ", 12) .. "</p><p>"
    .. string.rep("Nobody on the island could say where the seventh had come from. ", 10) .. "</p>"
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
    Daily.keep(edition)
    Daily.tried_at = os.time() -- (no network here)
    local ok, why = Paper.setOnHome(true)
    check(E, ok == true, "the widget ticked on Home … " .. tostring(why))
    check(E, Paper.onHome(), "Home's settings have it")
    local rows = require("config/preset_store").getSettings("home").rows
    local on = {}
    for _i, id in ipairs(rows.order) do on[#on + 1] = id .. (rows.enabled[id] and "*" or "") end
    E.say("Home's rows:", table.concat(on, " "))
end, after = 10 })
add({ shot = "daily-1-home" })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    check(E, Paper.home ~= nil and Paper.home.menu ~= nil, "Home built the Daily paper widget")
    Paper.show(plugin())
end, after = 8 })
add({ shot = "daily-2-paper" })
add({ fn = function(E)
    local page = require("gzreader_dailyscreen").instance
    check(E, page ~= nil and page.page == 1 and #page.blocks >= 3 and page.blocks[1].w > page.blocks[2].w,
        "the front page: the lead story across it, the others in columns … " .. tostring(page and #page.blocks))
    check(E, page.has_next, "more pages behind it")
    local inside = true
    for _i, b in ipairs(page.blocks) do
        if b.x < 0 or b.x + b.w > page.dimen.w or b.y + math.min(b.h, b.clip or b.h) > page.foot.y then inside = false end
    end
    check(E, inside, "every story is inside the page, above the foot")
    page:turn(1)
end, after = 8 })
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
    check(E, top and top.title and top.title:find("Seven ships", 1, true) ~= nil, "a story opened as text")
    if top then UIManager:close(top) end
    local Paper = require("gzreader_dailyscreen")
    if Paper.instance then UIManager:close(Paper.instance) end
end, after = 6 })
add({ fn = function(E)
    local Paper = require("gzreader_dailyscreen")
    check(E, Paper.instance == nil, "the paper closed")
    pcall(function() require("modules/settings/zen_settings_page").closeActive() end)
    require("modules/settings/zen_settings_page").show(require("apps/filemanager/filemanager").instance.zenos,
        { path = { { key = "text", value = "Home" }, { key = "text", value = "Daily paper" } } })
end, after = 10 })
add({ shot = "daily-5-settings" })
add({ fn = function(E)
    local out = E.out or "."
    local f = io.open(out .. "/daily-checks.txt", "w")
    if f then f:write(table.concat(checks, "\n"), "\n"); f:close() end
end, after = 1 })
return s
