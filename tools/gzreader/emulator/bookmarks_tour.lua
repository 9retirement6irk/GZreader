-- Bookmarks with Grimmory on a real reader (the test suite's mock on
-- 127.0.0.1:18080): two bookmarks made on the Kindle, the book closed, one
-- added in the web reader, the book opened again. Prints what the book has
-- and what Grimmory has after each step ("[emu] bm …" lines).
-- GZ_BM_BOOK: any EPUB with a few chapters (copied in as bm-book.epub).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local BOOK = "/mnt/us/GZreader/bm-book.epub"
local CTL = "http://127.0.0.1:18081"

local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function reader() return require("apps/reader/readerui").instance end
local function ctl(path)
    local http = require("socket.http")
    local body = http.request(CTL .. path)
    return body
end
local function server()
    local ok, st = pcall(function() return require("json").decode(ctl("/state")) end)
    return ok and st.bookmarks or {}
end
local function report(E, what)
    local ui = reader()
    local here = {}
    for _i, a in ipairs(ui and ui.annotation and ui.annotation.annotations or {}) do
        if not a.drawer then here[#here + 1] = tostring(a.page) .. (a.note and (" note=" .. a.note) or "") end
    end
    local there = {}
    for _i, b in ipairs(server()) do there[#there + 1] = tostring(b.id) .. ":" .. tostring(b.cfi) .. (type(b.notes) == "string" and (" notes=" .. b.notes) or "") end
    E.say("bm " .. what .. ": here " .. #here .. " [" .. table.concat(here, " | ") .. "]")
    E.say("bm " .. what .. ": Grimmory " .. #there .. " [" .. table.concat(there, " | ") .. "]")
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    E.say("login", tostring(p.api:login("http://127.0.0.1:18080", "will", "hunter22")))
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_BM_BOOK") or "/tmp/bmtest/book.epub") .. " " .. BOOK)
    p.store.downloads["3"] = { path = BOOK, format = "EPUB", title = "Book 03", file_id = 1003 }
    p:save()
    require("apps/reader/readerui"):showReader(BOOK)
end, after = 20 })
add({ fn = function(E) report(E, "opened") end, after = 1 })
-- two bookmarks: page 2 and page 5
add({ fn = function() reader():handleEvent(require("ui/event"):new("GotoPage", 2)) end, after = 3 })
add({ fn = function() reader().bookmark:toggleBookmark() end, after = 4 })
add({ fn = function() reader():handleEvent(require("ui/event"):new("GotoPage", 5)) end, after = 3 })
add({ fn = function() reader().bookmark:toggleBookmark() end, after = 8 })
add({ fn = function(E) report(E, "two made") end, after = 1 })
add({ shot = "1-bookmarked" })
add({ fn = function() reader():onHome() end, after = 8 })
-- the web reader (foliate-js): a range CFI of what's on screen
add({ fn = function(E)
    ctl("/addbm?book=3&title=web&cfi=" .. ("epubcfi(/6/4!/4/4,/20/1:0,/24/1:40)"):gsub("[^%w]", function(c)
        return string.format("%%%02X", c:byte()) end))
    E.say("bm web bookmark added")
end, after = 1 })
add({ fn = function() require("apps/reader/readerui"):showReader(BOOK) end, after = 25 })
add({ fn = function(E) report(E, "reopened") end, after = 1 })
add({ fn = function() reader():onHome() end, after = 8 })
add({ fn = function() require("apps/reader/readerui"):showReader(BOOK) end, after = 25 })
add({ fn = function(E) report(E, "reopened again") end, after = 1 })
add({ shot = "2-reopened" })
-- a highlight with a note (as KOReader's own Add note makes it)
add({ fn = function(E)
    local ui = reader()
    local p0 = "/body/DocFragment[1]/body/div/p[3]/text().0"
    local p1 = "/body/DocFragment[1]/body/div/p[3]/text().20"
    local item = { page = p0, pos0 = p0, pos1 = p1, drawer = "lighten", color = "yellow",
        text = ui.document:getTextFromXPointers(p0, p1), note = "Kindle note", chapter = "Chapter 1" }
    local index = ui.annotation:addItem(item)
    ui:handleEvent(require("ui/event"):new("AnnotationsModified", { item, nb_highlights_added = 1, index_modified = index }))
end, after = 20 })
add({ fn = function(E)
    local st = require("json").decode(ctl("/state"))
    for _i, n in ipairs(st.notes or {}) do E.say("bm note in Grimmory's Notes:", n.cfi, n.noteContent, tostring(n.selectedText)) end
    for _i, a in ipairs(st.annotations or {}) do E.say("bm highlight in Grimmory:", a.cfi, tostring(a.note)) end
    -- edited in the web reader
    if st.notes and st.notes[1] then ctl("/editnote?id=" .. st.notes[1].id .. "&note=edited%20on%20the%20web") end
end, after = 1 })
add({ fn = function() reader():onHome() end, after = 8 })
add({ fn = function() require("apps/reader/readerui"):showReader(BOOK) end, after = 30 })
add({ fn = function(E)
    for _i, a in ipairs(reader().annotation.annotations) do
        if a.drawer then E.say("bm highlight here, note:", tostring(a.note)) end
    end
    report(E, "last")
end, after = 1 })
return s
