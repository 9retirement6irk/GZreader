-- BookOrbit with only an API key (tests/mock_bookorbit.py on 127.0.0.1:18096): the key
-- fetches the e-reader sign-in (out of the server's plugin zip) and the Kindle signs in
-- with it; then the same with no sign-in on the server, where one is made. Prints what
-- each step found.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local KEY = "bok_" .. string.rep("a1B2c3D4e5", 4) .. "f6G7h8I9j"
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connectWithApiKey("http://127.0.0.1:18096", KEY)
    local list = p.api:listBooks{ page = 0, size = 20 }
    E.say("with a sign-in on the server:", tostring(ok), tostring(err), "| as", tostring(p.store.username), "| key kept:", tostring(p.api:hasApiKey()),
        "| books:", tostring(list and #list.content))
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local Api = require("gzreader_api")
    Api.rawRequest("POST", "http://127.0.0.1:18096/_mock/set", { body = { ko_credentials = false } })
    p.api:clearTokens()
    local ok, err = p:connectWithApiKey("http://127.0.0.1:18096", KEY)
    local list = p.api:listBooks{ page = 0, size = 20 }
    E.say("with none on the server:", tostring(ok), tostring(err), "| as", tostring(p.store.username), "| books:", tostring(list and #list.content))
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    E.say("log has the API key:", tostring(text:find(KEY, 1, true) ~= nil), "| the sync key:", tostring(text:find(tostring(p.store.bookorbit and p.store.bookorbit.key), 1, true) ~= nil))
end, after = 4 })
return s
