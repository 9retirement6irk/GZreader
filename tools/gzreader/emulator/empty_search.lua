-- A Grimmory search that finds nothing, in the Bookshelf view: the display
-- ledges a search's books stand on, empty, cobwebs on them, and a card saying
-- "No books found containing “…”"; then a search in a library that finds
-- nothing, and one that finds books (the same ledges, with them). Against the test suite's mock
-- Grimmory (tools/gzreader/tests/mock_grimmory.py on 127.0.0.1:18080).
-- Works on every model (no keys pressed).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function view(E, what)
    local b = require("gzreader_browser").current
    local m = b and b.menu
    local v = m and m._gz_view
    E.say(what, "title:", tostring(m and m.title), "view:", tostring(v and v.L and v.L.kind),
        "last:", tostring(m and m.item_table[#m.item_table] and m.item_table[#m.item_table].text))
end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E) E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "will", "hunter22"))) end, after = 2 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 8 })
add({ fn = function() require("gzreader_browser").current:search("nothing like this") end, after = 8 })
add({ fn = function(E) view(E, "search, nothing found") end })
add({ shot = "empty-search-1-nothing" })
add({ fn = function()
    require("gzreader_browser").current:search("zzz", { title = "fiction", params = { libraryId = 2, sort = "title", dir = "asc" } })
end, after = 8 })
add({ fn = function(E) view(E, "library search, nothing found") end })
add({ shot = "empty-search-2-library" })
add({ fn = function() require("gzreader_browser").current:search("book 1") end, after = 10 })
add({ fn = function(E) view(E, "search with results") end })
add({ shot = "empty-search-3-results" })
return s
