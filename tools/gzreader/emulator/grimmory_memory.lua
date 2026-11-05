-- The Grimmory tab with a big library (demo/big_grimmory.py on 127.0.0.1:18080),
-- best on GZ_EMU_MODEL=pw3: memory while paging through All books (Load more
-- a lot), the tiles, Authors and Series (the library index), a search.
-- Prints "[emu] mem <step>: lua <KB> rss <KB> covers <n>" lines and writes
-- <out>/memory.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local rows = {}

local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function browserMenu()
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do
        if w.widget._gz_navbar_tab_id == "ct_grimmory" then return w.widget end
    end
end
local function rss()
    local f = io.open("/proc/self/status")
    if not f then return 0 end
    local t = f:read("*a"); f:close()
    return tonumber(t:match("VmRSS:%s*(%d+)")) or 0
end
local function mem(name)
    return function(E)
        collectgarbage(); collectgarbage()
        local n = 0
        for _k in pairs(require("gzreader_covers").memory) do n = n + 1 end
        local m = browserMenu()
        local row = string.format("%-24s lua %7.0f KB  rss %7d KB  covers %3d  items %5s  page %s",
            name, collectgarbage("count"), rss(), n, m and tostring(#m.item_table) or "-",
            m and (tostring(m.page) .. "/" .. tostring(m.page_num)) or "-")
        rows[#rows + 1] = row
        E.say("mem " .. row)
    end
end

-- first start: past the setup guide, signed in to the big Grimmory
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    E.say("login", tostring(p.api:login("http://127.0.0.1:18080", "reader", "demo")))
    require("gzreader_homemenu").setDisplayMode("list_image_meta")
end, after = 2 })
add({ fn = mem("home"), after = 1 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 10 })
add({ fn = mem("grimmory tab"), after = 1 })
add({ shot = "1-tab" })
add({ fn = function(E) E.tap("All books") end, after = 15 })
add({ fn = mem("all books"), after = 1 })
add({ shot = "2-all" })
-- page to the end and Load more, many times (6 covers a page)
local LOADS = tonumber(os.getenv("GZ_MEM_LOADS") or "") or 16
for i = 1, LOADS do
    for _p = 1, 5 do
        add({ fn = function() local m = browserMenu(); if m and m.page < m.page_num then m:onNextPage() end end, after = 1.2 })
    end
    add({ fn = function(E)
        local m = browserMenu()
        if not m then return end
        m:onGotoPage(m.page_num)
        local last = m.item_table[#m.item_table]
        if last and last.text and last.text:find("Load more", 1, true) then
            m:onMenuSelect(last)
        elseif last and last.text and last.text:find("next", 1, true) then
            m:onMenuSelect(last)
        else
            E.say("no Load more / Next at the end:", tostring(last and last.text))
        end
    end, after = 6 })
    add({ fn = mem("load " .. i), after = 1 })
end
add({ shot = "3-loaded" })
-- the back arrow in the title (touch): back to the list of lists
local function chevron()
    local m, seen, found = browserMenu(), {}, nil
    local function walk(w, d)
        if found or type(w) ~= "table" or seen[w] or d > 40 then return end
        seen[w] = true
        if rawget(w, "icon") == "chevron.left" and w.dimen and w.dimen.w then found = w; return end
        for k, v in pairs(w) do
            if type(v) == "table" and k ~= "parent" and k ~= "show_parent" and k ~= "item_table" and k ~= "item_table_stack" then walk(v, d + 1) end
        end
    end
    walk(m and m.title_bar, 0)
    if found then return found.dimen.x + found.dimen.w / 2, found.dimen.y + found.dimen.h / 2 end
end
add({ fn = function(E)
    local x = chevron()
    E.say("back arrow", x and "found" or "not found")
end, after = 1 })
add({ tap = chevron, after = 5 })
add({ fn = function(E)
    local m = browserMenu()
    E.say("after the back arrow:", m and ("stack " .. #m.item_table_stack .. ", " .. tostring(m.title)) or "no browser")
end, after = 1 })
add({ fn = function(E) E.tap("All books") end, after = 12 })
-- tiles: 9 covers a page
add({ fn = function()
    require("gzreader_homemenu").setDisplayMode("mosaic_image")
    require("gzreader_covermenu").refresh()
end, after = 6 })
for i = 1, 12 do
    add({ fn = function() local m = browserMenu(); if m then m:onPrevPage() end end, after = 3 })
    if i % 4 == 0 then add({ fn = mem("tiles " .. i), after = 1 }) end
end
add({ shot = "4-tiles" })
add({ fn = function() require("gzreader_homemenu").setDisplayMode("list_image_meta") end, after = 1 })
-- back to the root, then Authors (builds the index of all the books)
add({ fn = function() local m = browserMenu(); while m and #m.item_table_stack > 0 do m:onClose() end end, after = 4 })
add({ fn = mem("root again"), after = 1 })
add({ fn = function(E) E.tap("Authors") end, after = 5 })
add({ wait_for = function()
    local Index = require("gzreader_index")
    return not Index.building and Index.data ~= nil
end, timeout = 900 })
add({ wait = 6 })
add({ fn = mem("authors"), after = 1 })
add({ shot = "5-authors" })
add({ fn = function() local m = browserMenu(); if m then m:onClose() end end, after = 4 })
add({ fn = function(E) E.tap("Series") end, after = 10 })
add({ fn = mem("series"), after = 1 })
add({ shot = "6-series" })
add({ fn = function() local m = browserMenu(); if m then m:onClose() end end, after = 4 })
-- search: the first line of the tab
add({ fn = function(E) E.tap("Search Grimmory…") end, after = 4 })
add({ fn = function(E)
    local d
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do
        if w.widget.getInputText and w.widget.title then d = w.widget end
    end
    E.say("search dialog:", tostring(d.title))
    d:setInputText("silver")
    d.buttons[1][2].callback()
end, after = 12 })
add({ fn = function(E)
    local m = browserMenu()
    local n = 0
    for _i, it in ipairs(m and m.item_table or {}) do if it.book then n = n + 1 end end
    E.say("search results:", m and m.title, n, "books", m and m.item_table[#m.item_table].text)
end, after = 1 })
add({ shot = "7-search" })
add({ fn = mem("search"), after = 1 })
add({ fn = mem("end"), after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/memory.txt", "w")
    f:write(table.concat(rows, "\n"), "\n")
    f:close()
end, after = 1 })
return s
