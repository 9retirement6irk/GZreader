-- The Catalog's Magazines page (demo/demo_grimmory.py on 127.0.0.1:18080 with
-- GZ_DEMO_MAGAZINES=1: a Magazines library of made-up monthly magazines; a touch
-- model, e.g. GZ_EMU_MODEL=pw3): signed in, the Magazines library chosen
-- (Settings → Accounts and services → Books → Magazines), the library index
-- built again; then the Books page (no magazines on it), the Magazines page as a
-- magazine stand, Magazines A–Z and one magazine's issues. Prints each list.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function browser() return require("gzreader_browser").current end
local function listTop(E, what)
    local w = top()
    local out = {}
    for i, it in ipairs(w and w.item_table or {}) do
        if i > 16 then break end
        out[#out + 1] = tostring(it.text or (it.text_func and it.text_func()) or "?")
    end
    E.say(what, tostring(w and (w.name or w.title)), table.concat(out, " | "))
end
local function closeGuides()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end

add({ fn = closeGuides, after = 6 })
add({ fn = function(E) E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo"))) end, after = 4 })
add({ fn = function(E)
    local Mag = require("gzreader_magazines")
    Mag.set(plugin(), { id = 8, name = "Magazines" })
    require("gzreader_index").build(plugin(), false, function(d, err)
        E.say("index:", tostring(d and d.total), "books;", tostring(d and d.magazines and #d.magazines.ids), "magazines", tostring(err))
    end)
end, after = 20 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 16 })
add({ fn = function(E)
    E.say("pages:", table.concat(browser():sections(), ","))
    listTop(E, "books page")
    local st = browser()._shop or {}
    local ids = {}
    for _i, b in ipairs(st.recent or {}) do ids[#ids + 1] = tostring(b.id) end
    E.say("recently added (fetched):", table.concat(ids, ","))
end })
add({ shot = "mag-1-books-page" })
add({ fn = function() browser():openSection("magazines") end, after = 16 })
add({ fn = function(E)
    listTop(E, "magazines page")
    local st = browser()._stand or {}
    E.say("stand issues:", tostring(st.issues and #st.issues), "total", tostring(st.total))
end })
add({ shot = "mag-2-stand" })
add({ fn = function() browser():openMagazineTitles() end, after = 10 })
add({ fn = function(E) listTop(E, "titles") end })
add({ shot = "mag-3-titles" })
add({ fn = function(E)
    for _i, it in ipairs(top().item_table or {}) do
        if tostring(it.text):match("^Harbor") and it.callback then it.callback(); return end
    end
    E.say("no Harbor")
end, after = 8 })
add({ fn = function(E) listTop(E, "harbor") end })
add({ shot = "mag-4-harbor" })
add({ fn = function() browser():openSection("books"); browser():openPaged("All books", { sort = "title", dir = "asc" }) end, after = 12 })
add({ fn = function(E) listTop(E, "all books") end })
return s
