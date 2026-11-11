-- The Grimmory tab while browsing (demo/demo_grimmory.py on 127.0.0.1:18080),
-- a Kindle with keys (k3, k4): the first page and All books with the
-- selection moved, then drawn again (the bookshop's lists, a fresh copy of
-- the list): it stays; a book's page with the list's cover; Download (the
-- selection stays on the book); the Downloads tab showing a book downloaded
-- while it's on screen. Prints "selected: x y <item>" after each step.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function focused(E, what)
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.item_table and w.layout then
            local row = w.layout[w.selected and w.selected.y or 1] or {}
            local it = row[w.selected and w.selected.x or 1]
            E.say(what, "selected:", tostring(w.selected and w.selected.x), tostring(w.selected and w.selected.y),
                tostring(it and (it.text or (it.entry and it.entry.text)) or "?"))
            return
        end
    end
    E.say(what, "no menu")
end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
-- first start: past the setup guide, signed in to the demo Grimmory
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E) E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo"))) end, after = 2 })
add({ shot = "browse-0-home" })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 1 })
add({ key = "Down", after = 0.3 })   -- moved before the fresh first page arrives
add({ key = "Right", after = 0.3 })
add({ fn = function(E) focused(E, "first page moved") end, after = 10 })
add({ fn = function()
    -- what the bookshop does when its lists arrive (the first page drawn again)
    local m = require("gzreader_browser").current.menu
    m:updateItems()
end, after = 2 })
add({ fn = function(E) focused(E, "first page redrawn") end })
add({ fn = function(E) focused(E, "first page after refresh") end })
add({ shot = "browse-1-root" })
add({ key = "Back", after = 3 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 6 })
add({ key = "R", after = 8 })         -- All books
add({ fn = function(E) focused(E, "all books opened") end })
add({ key = "Down", after = 0.3 })    -- the third row, second book, while covers and the fresh copy arrive
add({ key = "Down", after = 0.3 })
add({ key = "Right", after = 0.3 })
add({ fn = function(E) focused(E, "all books moved") end, after = 8 })
add({ fn = function()
    -- what openCached does when Grimmory's fresh copy arrives: a new table, same books
    local m = require("gzreader_browser").current.menu
    local items = {}
    for i, it in ipairs(m.item_table) do
        local c = {}
        for k, v in pairs(it) do c[k] = v end
        items[i] = c
    end
    local at = require("gzreader_focus").carry(m, items)
    m:switchItemTable(m.title, items, at or 1)
end, after = 3 })
add({ fn = function(E) focused(E, "all books fresh copy") end })
add({ fn = function(E) focused(E, "all books after refresh") end })
add({ shot = "browse-2-all" })
add({ key = "Press", after = 10 })    -- the book's page
add({ shot = "browse-3-bookpage" })
add({ key = "Press", after = 15 })    -- Download (focused first)
add({ fn = function(E) focused(E, "after download") end })
add({ shot = "browse-4-after-download" })
add({ fn = function()
    local b = require("gzreader_browser").current
    if b and b.menu then require("ui/uimanager"):close(b.menu) end
end, after = 3 })
add({ key = "X", after = 8 })         -- the Downloads tab
add({ shot = "browse-5-downloaded" })
add({ fn = function(E)
    -- a download finishing while the Downloads tab is open
    E.say("downloads tab showing:", tostring(plugin():downloadsTabShowing()))
    plugin():downloadAndOpen({ id = 5, title = "Sense and Sensibility", primaryFileType = "EPUB",
        primaryFileName = "5.epub", authors = { "Jane Austen" } }, nil, { no_open = true })
end, after = 20 })
add({ shot = "browse-6-downloaded-after" })
add({ fn = function(E)
    local n = 0
    for _i, it in ipairs(require("apps/filemanager/filemanager").instance.file_chooser.item_table or {}) do
        if it.path and it.path:match("%.epub$") then n = n + 1 end
    end
    E.say("books in the Downloads tab:", n)
end })
return s
