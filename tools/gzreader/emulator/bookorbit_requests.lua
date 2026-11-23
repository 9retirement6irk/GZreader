-- BookOrbit book requests (tests/mock_bookorbit.py on 127.0.0.1:18096): sign in, enter the
-- API key, open the Catalog's BookOrbit card, the request form, send two requests and
-- show the list and one request's details. Prints what each step found.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local KEY = "bok_" .. string.rep("a1B2c3D4e5", 4) .. "f6G7h8I9j"
local function closeTop(name)
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if not name or w.name == name then UIManager:close(w) return true end
    end
end
add({ fn = function()
    closeTop("setup guide"); closeTop("QR code screen")
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    local k_ok, k_err = p:setBookOrbitApiKey(KEY)
    E.say("sign-in:", tostring(ok), tostring(err), "| key:", tostring(k_ok), tostring(k_err))
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    if top and top.text then UIManager:close(top) end
    p:onShowGrimmoryLibrary()
end, after = 8 })
add({ fn = function(E)
    local B = require("gzreader_browser")
    local b = B.instance or B.current
    E.say("browser:", tostring(b ~= nil))
    if b then b:openGrimmory() end
end, after = 4 })
add({ shot = "requests-1-card" })
add({ fn = function() require("gzreader_bo_requests").ask(plugin()) end, after = 4 })
add({ shot = "requests-2-form" })
add({ fn = function(E)
    local Rq = require("gzreader_bo_requests")
    local UIManager = require("ui/uimanager")
    if Rq.dialog then UIManager:close(Rq.dialog) end
    local p = plugin()
    local a = p.api:requestBook("The Salt Road", { "Ines Ward" }, "ebook")
    local b = p.api:requestBook("Low Tide: Notes from a Northern Shore", { "Mara Quill" }, "audiobook")
    E.say("requested:", tostring(a and a.status), tostring(b and b.status))
    local B = require("gzreader_browser")
    local br = B.instance or B.current
    if br then Rq.open(br) end
end, after = 6 })
add({ shot = "requests-3-list" })
add({ fn = function(E)
    local B = require("gzreader_browser")
    local br = B.instance or B.current
    local it = br and br.menu and br.menu.item_table and br.menu.item_table[2]
    E.say("row:", tostring(it and it.text), tostring(it and it.mandatory))
    if it then it.callback() end
end, after = 4 })
add({ shot = "requests-4-detail" })
return s
