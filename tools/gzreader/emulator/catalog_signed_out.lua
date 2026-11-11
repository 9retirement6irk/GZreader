-- The Catalog without Grimmory: the Books page with empty shelves saying to
-- sign in, the Audiobooks page the same, the Grimmory card's list; then
-- signed in (against the test suite's mock Grimmory on 127.0.0.1:18080),
-- the Books page filled in with the Grimmory card last. Any model with a
-- speaker (k3 by default); no keys pressed.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function say(E, what)
    local b = require("gzreader_browser").current
    local m = b and b.menu
    local ids = {}
    for _i, it in ipairs(m and m.item_table or {}) do ids[#ids + 1] = tostring(it.gz_id or it.text) end
    E.say(what, "title:", tostring(m and m.title), "signed out:", tostring(m and m.item_table.gz_signed_out),
        "shop:", tostring(m and m._gz_shop ~= nil), "items:", table.concat(ids, ","))
end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E) E.say("paired before:", tostring(plugin().api:isPaired())); plugin():onShowGrimmoryLibrary() end, after = 6 })
add({ fn = function(E) say(E, "books, signed out") end })
add({ shot = "catalog-out-1-books" })
add({ fn = function() require("gzreader_browser").current:turnSection(1) end, after = 4 })
add({ fn = function(E) say(E, "audiobooks, signed out") end })
add({ shot = "catalog-out-2-audiobooks" })
add({ fn = function() require("gzreader_browser").current:turnSection(-1) end, after = 3 })
add({ fn = function() require("gzreader_browser").current:openGrimmory() end, after = 3 })
add({ fn = function(E) say(E, "the Grimmory card, signed out") end })
add({ shot = "catalog-out-3-grimmory-card" })
add({ fn = function(E)
    local p = plugin()
    local previous = { p.store.server, p.store.username }
    E.say("login", tostring(p.api:login("http://127.0.0.1:18080", "will", "hunter22")))
    p:afterLogin(previous)
end, after = 10 })
add({ fn = function(E) say(E, "books, signed in") end })
add({ shot = "catalog-out-4-signed-in" })
add({ fn = function() require("gzreader_browser").current:turnSection(1) end, after = 6 })
add({ fn = function(E) say(E, "audiobooks, signed in") end })
add({ shot = "catalog-out-5-audiobooks-signed-in" })
return s
