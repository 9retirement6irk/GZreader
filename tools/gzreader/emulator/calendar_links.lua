-- The Calendar tab with calendar links (webcal / ICS, as Proton Calendar
-- shares them), no CalDAV account. Serve demo/ (proton_sample.ics,
-- holidays_sample.ics) on 127.0.0.1:18096, e.g.
--   cd tools/gzreader/emulator/demo && python3 -m http.server 18096 --bind 127.0.0.1
-- and demo/demo_grimmory.py on 18080 for the setup guide. Adds two links
-- from the phone page (one with secret keys in it), shows Agenda and Week,
-- the links in Settings, and checks the log never has the secret.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local SECRET = "CacheKey=s3cr3tCacheKey&PassphraseKey=s3cr3tPassphrase"
local function phonePost(E, form)
    local UIManager = require("ui/uimanager")
    local url
    for _i, w in ipairs(UIManager._window_stack) do if w.widget.url then url = w.widget.url end end
    local path = url and url:match("^https?://[^/]+(/.*)$")
    local server
    for _i, z in ipairs(UIManager._zeromqs or {}) do if z.handler then server = z end end
    if not (path and server) then return E.say("no QR page") end
    local code, _, page = server.handler("GET", path, {}, "")
    E.say("phone opens the page ->", code, tostring(page):find("Paste one or more calendar links", 1, true) and "form" or "?")
    local enc = form:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end)
    code, _, page = server.handler("POST", path, {}, "links=" .. enc)
    local ok = select(2, tostring(page):gsub("✓", ""))
    E.say("phone adds links ->", code, ok .. " added")
end

key("B", 6)
shot("links-1-add-screen")
key("Q", 8) -- Add calendar links with QR code
shot("links-2-qr")
add({ fn = function(E)
    phonePost(E, "http://127.0.0.1:18096/proton_sample.ics?" .. SECRET .. "\nHolidays | webcal://127.0.0.1:18096/holidays_sample.ics")
end, after = 20 })
key("Back", 25) -- done: the Calendar tab opens and syncs
shot("links-3-agenda")
add({ fn = function(E)
    local Cal = require("gzreader_calendar")
    local p = require("apps/filemanager/filemanager").instance.gzreader
    local names = {}
    for _i, f in ipairs(Cal.feeds(p)) do names[#names + 1] = Cal.feedName(f) .. " (" .. f.url:match("^(%a+)://") .. ")" end
    E.say("links:", table.concat(names, ", "), "| events:", #(Cal.events or {}))
end, after = 1 })
key("M", 4); key("E", 8) -- Week
key("RPgFwd", 6) -- next week: Election Day, the moved piano lesson
shot("links-4-week")
key("M", 4); key("W", 6) -- Day
shot("links-5-day")
key("M", 4); key("Q", 6) -- Agenda
key("M", 4); key("U", 6) -- Calendar settings
shot("links-6-settings")
key("Q", 5) -- Calendar links
shot("links-7-links")
key("Q", 5) -- the first link
shot("links-8-link")
key("Back", 3); key("Back", 3); key("Back", 3)
add({ fn = function(E)
    local f = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local t = f and f:read("*a") or ""
    if f then f:close() end
    E.say("log has the secret:", tostring(t:find("s3cr3t", 1, true) ~= nil), "| log mentions calendar links:",
        tostring(t:find("(calendar link)", 1, true) ~= nil))
end, after = 1 })
return s
