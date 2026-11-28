-- The Catalog's Requests page (tests/mock_bookorbit.py on 127.0.0.1:18096; any
-- model): signed in to BookOrbit with an API key, one request made, then the
-- Catalog turned to Requests (the order desk in the Bookshelf view); then the desk
-- with requests in every state (put in by hand: the mock only makes waiting ones),
-- and Request a book's form. Prints the page's rows.
local KEY = "bok_" .. string.rep("a1B2c3D4e5", 4) .. "f6G7h8I9j" -- (the mock's made-up key)
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
add({ fn = function()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    local k_ok = p:setBookOrbitApiKey(KEY)
    local r = p.api:requestBook("The Salt Road", { "Ines Ward" }, "ebook")
    E.say("sign-in:", tostring(ok), tostring(err), "key:", tostring(k_ok), "request:", tostring(r and r.status))
end, after = 6 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 14 })
add({ fn = function(E)
    local b = require("gzreader_browser").current
    local list = {}
    for i = 1, 3 do list[#list + 1] = { id = 700 + i, title = "On order " .. i, authors = { "A. Writer" }, kind = "ebook", status = "approved" } end
    for i = 1, 43 do list[#list + 1] = { id = 800 + i, title = "Arrived " .. i, authors = { "B. Writer" }, kind = "ebook", status = "available" } end
    for i = 1, 2 do list[#list + 1] = { id = 900 + i, title = "Missing " .. i, authors = { "C. Writer" }, kind = "ebook", status = "rejected" } end
    b._requests = { at = os.time(), list = list }
    b:openSection("requests")
end, after = 10 })
add({ shot = "desk" })
add({ fn = function(E)
    local m = top()
    E.say("desk:", tostring(m._gz_shop ~= nil), "items", #(m.item_table or {}), "perpage", tostring(m.perpage),
        "items_per_page", tostring(m.items_per_page), "page_num", tostring(m.page_num))
    local f = io.open(E.out .. "/order-desk-checks.txt", "w")
    f:write(((m._gz_shop ~= nil and m.page_num == 1) and "ok   " or "FAIL ")
        .. "the order desk is one page: no page arrows or number under it (page_num " .. tostring(m.page_num) .. ")\n")
    f:close()
end })
return s
