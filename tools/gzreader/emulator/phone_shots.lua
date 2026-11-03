-- The phone page, driven by a real browser (phone_drive.js): first start,
-- "Connect your phone", the QR code; the browser connects Grimmory, Notes
-- (Memos), a CalDAV account and two calendar links, and sends two books;
-- Back closes the page (the summary), the rest of the setup guide, Home,
-- Downloads, Calendar and Notes with what the phone set up.
--
-- Servers: demo/demo_grimmory.py on 18080, demo/mock_memos.py 18097 --sample
-- --prefix /api --memos26, demo/demo_caldav.py 18095, and demo/ served on
-- 18096 (python3 -m http.server 18096 --bind 127.0.0.1). Then, together:
--   run.sh tools/gzreader/emulator/phone_shots.lua <out>
--   node tools/gzreader/emulator/phone_drive.js <out> <book.epub>...
-- This script writes <out>/phone-url.txt; the driver writes phone-step-N
-- files as it goes and its own screenshots (phone-*.png) into <out>.
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "setup-2-qr" then break end
end
local OUT
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end
local function stepDone(n) return function() return exists(OUT .. "/phone-step-" .. n) end end
local function phoneUrl()
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do
        if w.widget.url then return w.widget.url end
    end
end

add({ fn = function(E)
    OUT = E.out
    local url = phoneUrl()
    E.say("phone page:", url and url:gsub("/phone/%x+", "/phone/<token>") or "none")
    local f = io.open(OUT .. "/phone-url.txt", "w")
    f:write(url or "", "\n")
    f:close()
end, after = 1 })
add({ wait_for = stepDone(1), label = "Grimmory", after = 1 })
shot("phone-k-1-grimmory")            -- the toast on the Kindle
add({ wait_for = stepDone(2), label = "Notes and Calendar", after = 1 })
shot("phone-k-2-calendar")
add({ wait_for = stepDone(3), label = "books", after = 1 })
shot("phone-k-3-books")
add({ wait_for = stepDone(4), label = "driver done", timeout = 60, after = 1 })
key("Back", 3)                        -- done on the phone: the summary (6 s)
shot("phone-k-4-summary")
key("Press", 4)                       -- closes it
shot("setup-3-welcome")
key("Press", 3)
for i = 1, 6 do shot(string.format("setup-4-guide-%d", i)); key("RPgFwd", 3) end
for _i = 1, 8 do key("RPgFwd", 2.5) end
add({ wait = 10 })
shot("home-books")
add({ fn = function(E)
    local p = require("apps/filemanager/filemanager").instance.gzreader
    local lfs = require("libs/libkoreader-lfs")
    local names = {}
    for name in lfs.dir(p:libraryDir()) do if name:match("%.epub$") then names[#names + 1] = name end end
    table.sort(names)
    E.say("books folder:", table.concat(names, ", "))
    E.say("memos:", tostring((p.store.memos or {}).user), "caldav:", tostring((p.store.caldav or {}).username),
        "links:", #(p.store.calendar_feeds or {}))
end, after = 1 })
key("X", 6)                           -- the Downloads tab
shot("downloads-books")
key("B", 25)                          -- Calendar: syncs
shot("calendar-agenda")
key("M", 4); key("E", 8)              -- Week
shot("calendar-week")
key("M", 4); key("Q", 6)              -- Agenda
key("V", 20)                          -- Notes
shot("notes-board")
add({ fn = function(E)
    local f = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local t = f and f:read("*a") or ""
    if f then f:close() end
    for _i, secret in ipairs({ "memos-test-token", "demo-app-password", "demo-pass", "s3cr3t" }) do
        E.say("log has", secret .. ":", tostring(t:find(secret, 1, true) ~= nil))
    end
end, after = 1 })
return s
