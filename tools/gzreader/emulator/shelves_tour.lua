-- The book menu's Add to shelf / Remove from shelf for a Grimmory book
-- (gzreader_shelves.lua), on a Kindle 3: mock_grimmory.py on 127.0.0.1:18080
-- (the test suite's), GZ_EMU_BOOK: an EPUB that stands in for book 3.
--   GZ_EMU_TREE=<tree>/koreader run.sh shelves_tour.lua <out>
-- Shots: manage (Add to shelf where Add to collection was), shelves (your
-- shelves), added, manage-remove (Remove from shelf), manage-two (Remove
-- from shelves), remove-which, removed, sideloaded (a book not from
-- Grimmory: Add to shelf, no Add to collection).
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local BOOK = "/mnt/us/GZreader/Book 03.epub"

local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
-- ZenOS's book menu for the book (what holding it, or Manage, opens)
local function bookMenu()
    return function()
        local fc = require("apps/filemanager/filemanager").instance.file_chooser
        fc:showFileDialog({ path = BOOK, is_file = true, text = "Book 03.epub" })
    end
end
local function ctl(path) os.execute("curl -s 'http://127.0.0.1:18081" .. path .. "' > /dev/null") end
local function menuLines(E, what)
    local UIManager = require("ui/uimanager")
    local w = UIManager._window_stack[#UIManager._window_stack]
    local texts = {}
    local function walk(t, depth)
        if type(t) ~= "table" or depth > 12 then return end
        if type(t.text) == "string" and t.text ~= "" then texts[#texts + 1] = t.text end
        for _k, v in pairs(t) do if type(v) == "table" and _k ~= "parent" and _k ~= "show_parent" then walk(v, depth + 1) end end
    end
    if w then walk(w.widget.buttons or w.widget.item_table or {}, 0) end
    E.say(what .. ": " .. table.concat(texts, " | "))
end

add({ key = "Back", after = 4 })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    local p = plugin()
    E.say("login", tostring(p.api:login("http://127.0.0.1:18080", "will", "hunter22")))
    os.execute("mkdir -p /mnt/us/GZreader && cp '" .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. "' '" .. BOOK .. "'")
    p.store.downloads["3"] = { path = BOOK, title = "Book 03", file_id = 1003 }
    p:save()
    ctl("/shelf?book=3&remove=4&remove=6")
end, after = 3 })
-- open it once (Grimmory's record of it comes with its shelves), then Home
add({ fn = function() require("apps/reader/readerui"):showReader(BOOK) end, after = 15 })
add({ key = "Back", after = 10 })
add({ fn = bookMenu(), after = 5 })
add({ shot = "manage" })
add({ fn = function(E) menuLines(E, "book menu") end, after = 1 })
add({ key = "W", after = 8 }) -- Add to shelf
add({ shot = "shelves" })
add({ fn = function(E) menuLines(E, "add to shelf") end, after = 1 })
add({ key = "W", after = 8 }) -- Kindle
add({ shot = "added" })
add({ fn = function(E) E.say("on shelves: " .. tostring(#require("gzreader_shelves").on(plugin(), "3"))) end, after = 4 })
add({ fn = bookMenu(), after = 5 })
add({ shot = "manage-remove" })
add({ fn = function(E) menuLines(E, "book menu") end, after = 1 })
add({ key = "Back", after = 3 })
-- put on Beach reads too in the web app; open the book again
add({ fn = function() ctl("/shelf?book=3&add=6"); require("apps/reader/readerui"):showReader(BOOK) end, after = 15 })
add({ key = "Back", after = 10 })
add({ fn = bookMenu(), after = 5 })
add({ shot = "manage-two" })
add({ fn = function(E) menuLines(E, "book menu") end, after = 1 })
add({ key = "E", after = 8 }) -- Remove from shelves
add({ shot = "remove-which" })
add({ fn = function(E) menuLines(E, "remove from shelf") end, after = 1 })
add({ key = "E", after = 8 }) -- All 2 shelves
add({ shot = "removed" })
add({ fn = function(E) E.say("on shelves: " .. tostring(#require("gzreader_shelves").on(plugin(), "3"))) end, after = 1 })
-- a book not from Grimmory: still Add to shelf (it says why it can't)
add({ fn = function()
    os.execute("cp '" .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. "' /mnt/us/documents/sideloaded.epub")
    local fc = require("apps/filemanager/filemanager").instance.file_chooser
    fc:showFileDialog({ path = "/mnt/us/documents/sideloaded.epub", is_file = true, text = "sideloaded.epub" })
end, after = 5 })
add({ shot = "sideloaded" })
add({ fn = function(E) menuLines(E, "sideloaded book menu") end, after = 1 })
add({ key = "W", after = 4 })
add({ shot = "sideloaded-add" })
return s
