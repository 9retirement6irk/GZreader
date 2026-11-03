-- Kindle Paperwhite 3 (GZ_EMU_MODEL=pw3): first start by touch, the phone
-- page (phone_drive.js connects Grimmory, Notes, Calendar and sends books),
-- the rest of the setup guide, the touch tour, then every tab and the main
-- screens by tapping. Servers and the driver as for phone_shots.lua:
--   GZ_EMU_MODEL=pw3 run.sh tools/gzreader/emulator/pw3_tour.lua <out> &
--   node tools/gzreader/emulator/phone_drive.js <out> <book.epub>...
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function tap(what, after) add({ tap = what, after = after or 3 }) end
local function exists(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end

shot("01-connect")
tap({ 950, 1390 }, 6)                 -- Next: the QR code
add({ fn = function(E)
    local url
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do if w.widget.url then url = w.widget.url end end
    local f = io.open(E.out .. "/phone-url.txt", "w"); f:write(url or "", "\n"); f:close()
end })
shot("02-qr")
add({ wait_for = function(E) return exists(E.out .. "/phone-step-4") end, label = "phone", timeout = 240 })
shot("03-qr-done")
tap("Done", 3)
shot("04-summary")
tap({ 536, 300 }, 3)                  -- (closes the summary)
for _i = 2, 13 do tap({ 950, 1390 }, 2.5) end
shot("05-last-page")
tap({ 536, 1100 }, 10)                -- Get Started
shot("06-tour")
tap({ 536, 1000 }, 3)
shot("07-tour")
tap({ 536, 1000 }, 3)
shot("10-home")
tap({ 325, 1380 }, 6); shot("11-downloads")
tap({ 550, 1380 }, 10); shot("12-grimmory")
tap({ 740, 1380 }, 12); shot("13-notes")
tap({ 918, 1380 }, 15); shot("14-calendar")
tap({ 128, 1380 }, 6); shot("15-home")
-- the launcher (swipe down from the top): GZreader's menu, the phone page, Send books
add({ swipe = { 536, 5, 536, 700 }, after = 4 })
tap({ 200, 48 }, 4); shot("16-launcher")
tap("GZreader", 5); shot("17-gz-menu")
tap({ 1040, 40 }, 4)                  -- (close)
add({ swipe = { 536, 5, 536, 700 }, after = 4 })
tap({ 200, 48 }, 4)
tap("Send books", 8); shot("18-send-books")
tap("Done", 4); shot("19-home")
-- a note: tick a checklist item by tapping it, then the buttons
tap({ 740, 1380 }, 10)
tap("headlamp", 5); shot("20-note")
tap("headlamp", 4); shot("21-note-ticked")
tap("Close", 4)
tap("New note", 6); shot("22-editor")
tap({ 70, 40 }, 3)                    -- ✕ (nothing typed: closes)
-- the calendar: ▶, an event
tap({ 918, 1380 }, 12)
tap("\u{25B6}", 6); shot("23-calendar-next")
tap("Today", 6)
tap("Dentist", 4); shot("24-event")
tap("Close", 3)
-- a book from the Grimmory tab, read by tapping
tap({ 550, 1380 }, 8)
tap("All books", 8)
tap({ 180, 330 }, 5)
tap("Download & open", 25); shot("25-book")
tap({ 536, 724 }, 3)                  -- (ZenOS's first-time tip)
tap({ 950, 724 }, 4); shot("26-page-2")
tap({ 950, 724 }, 4); shot("27-page-3")
tap({ 536, 40 }, 4); shot("28-reader-menu")
return s
