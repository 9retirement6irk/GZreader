-- First start: setup guide, the phone page (phone simulated) connects Grimmory, go on.
local function pairPost(E)
    local UIManager = require("ui/uimanager")
    local url
    for _i, w in ipairs(UIManager._window_stack) do
        if w.widget.url then url = w.widget.url end
    end
    if not url then return E.say("no phone page!") end
    local base = url:match("^https?://[^/]+(/[^#]*)")
    local server
    for _i, z in ipairs(UIManager._zeromqs or {}) do if z.handler then server = z end end
    if not server then return E.say("no phone page server in ZMQs") end
    E.say("phone GET", (base:gsub("%x+$", "<token>")))
    local code = server.handler("GET", base, {}, "")
    E.say("-> ", code)
    local body = "action=password&server=" .. "http%3A%2F%2F127.0.0.1%3A18080" .. "&username=will&password=hunter22"
    E.say("phone POST login")
    local c2, _, location = server.handler("POST", base .. "/grimmory", {}, body)
    local html = select(3, server.handler("GET", tostring(location):gsub("#.*$", ""), {}, ""))
    E.say("-> ", c2, tostring(html):match('<div class="flash[^"]*">(.-)</div>') or "?")
end

local s = {
    start = 10,
    { shot = "01-boot" },
    { key = "RPgFwd", after = 4 },          -- Connect to Grimmory: QR (default) -> Next
    { shot = "02-pairscreen" },
    { fn = pairPost, after = 1 },
    { key = "Back", after = 2 },            -- done on the phone
    { fn = function(E) local UIManager = require("ui/uimanager"); local Event = require("ui/event")
        E.say("broadcast NetworkConnected"); UIManager:broadcastEvent(Event:new("NetworkConnected")) end, after = 2 },
    { shot = "03-after-login" },
    { key = "Press", after = 2 },           -- dismiss the summary
    { shot = "04-guide" },
}
for i = 1, 14 do
    s[#s + 1] = { key = "RPgFwd", after = 2 }
    s[#s + 1] = { shot = string.format("05-guide-%02d", i) }
end
for _i, x in ipairs({
    { wait = 6 },
    { shot = "06-after-guide" },
    { key = "Down" }, { shot = "07-down" },
    { key = "Press", after = 3 }, { shot = "08-press" },
    { key = "Back", after = 2 }, { shot = "09-back" },
    { key = "Menu", after = 3 }, { shot = "10-menu" },
    { key = "Back", after = 2 }, { shot = "11-back" },
    { wait = 30 },
    { shot = "12-end" },
}) do s[#s + 1] = x end
return s
