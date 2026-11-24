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
    E.say("pages:", table.concat(b:sections(), ","))
    b:openSection("requests")
end, after = 10 })
add({ fn = function(E)
    local out = {}
    for _i, it in ipairs(top().item_table or {}) do out[#out + 1] = tostring(it.text) .. (it.mandatory and (" = " .. it.mandatory) or "") end
    E.say("requests page:", table.concat(out, " | "))
end })
add({ shot = "requests-1-page" })
add({ fn = function(E)
    local b = require("gzreader_browser").current
    b._requests = { at = os.time(), list = {
        { id = 601, title = "The Salt Road", authors = { "Ines Ward" }, kind = "ebook", status = "pending" },
        { id = 602, title = "Lanterns over Marrow Bay", authors = { "T. K. Odeh" }, kind = "ebook", status = "searching" },
        { id = 603, title = "Small Hours", authors = { "Jun Hadley" }, kind = "audiobook", status = "downloading" },
        { id = 604, title = "A Winter Almanac", authors = { "Per Lindqvist" }, kind = "ebook", status = "approved" },
        { id = 605, title = "The Clockmaker's Orchard", authors = { "Ines Varga" }, kind = "ebook", status = "available" },
        { id = 606, title = "A Field Guide to Fog", authors = { "Per Lindqvist" }, kind = "audiobook", status = "available" },
        { id = 607, title = "Nine Bridges", authors = { "Amara Cole" }, kind = "ebook", status = "rejected", note = "No ebook edition found." },
    } }
    b:openSection("requests")
    local shop = top()._gz_shop
    E.say("order desk:", tostring(shop ~= nil), "rows of the 5-way:", tostring(#(top().layout or {})))
end, after = 8 })
add({ shot = "requests-3-desk-full" })
add({ fn = function(E)
    local m = top()
    for _i, row in ipairs(m.layout or {}) do
        for _k, h in ipairs(row) do
            if type(h.entry) == "table" and h.entry.text == "Didn't arrive" then h.entry.callback() end
        end
    end
    local out = {}
    for _i, it in ipairs(top().item_table or {}) do out[#out + 1] = tostring(it.text) .. (it.mandatory and (" = " .. it.mandatory) or "") end
    E.say("didn't arrive:", table.concat(out, " | "))
end, after = 6 })
add({ shot = "requests-4-didnt-arrive" })
add({ fn = function() require("gzreader_browser").current:openSection("requests") end, after = 8 })
add({ fn = function() top().item_table[1].callback() end, after = 6 })
add({ shot = "requests-5-form" })
return s
