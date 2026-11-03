-- Screenshots for the README (with demo/demo_grimmory.py on 127.0.0.1:18080).
-- The phone (simulated): opens the phone page and connects Grimmory; Back on the Kindle closes it.
local function pairPost(E)
    local UIManager = require("ui/uimanager")
    local url
    for _i, w in ipairs(UIManager._window_stack) do if w.widget.url then url = w.widget.url end end
    local base = url and url:match("^https?://[^/]+(/[^#]*)")
    local server
    for _i, z in ipairs(UIManager._zeromqs or {}) do if z.handler then server = z end end
    if not (base and server) then return E.say("no phone page") end
    server.handler("GET", base, {}, "")
    local code = server.handler("POST", base .. "/grimmory", {}, "action=password&server=http%3A%2F%2F127.0.0.1%3A18080&username=reader&password=demo")
    E.say("phone sign-in ->", code)
end
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 2.5 }) end
local function combo(a, b, after) add({ combo = { a, b }, after = after or 3 }) end
-- setup
shot("setup-1-connect")
key("RPgFwd", 6)
shot("setup-2-qr")
add({ fn = pairPost, after = 4 })
key("Back", 3)            -- done on the phone: what changed
shot("setup-3-connected")
key("Press", 3)
for i = 1, 6 do shot(string.format("setup-4-guide-%d", i)); key("RPgFwd", 3) end
for _i = 1, 8 do key("RPgFwd", 2.5) end
add({ wait = 8 })
shot("home-empty")
-- Grimmory tab
key("C", 8)               -- the Grimmory tab
shot("grimmory-1")
key("Down", 3)
shot("grimmory-2")
key("Press", 4)
shot("grimmory-3")
key("Back", 3)
key("E", 5)
shot("grimmory-4-all")
key("Q", 4)
shot("grimmory-5-book")
key("Right", 1.5)
key("Press", 2)
shot("download-1")
add({ wait = 1 })
shot("download-2")
add({ wait = 2 })
shot("download-3")
add({ wait = 15 })
shot("reading-1")
key("RPgFwd", 3)
shot("reading-2")
key("Menu", 4)
shot("readmenu-1")
key("Back", 3)
combo("Shift", "Sym", 4)
shot("tts-0-voice")
key("Right", 1.5)
key("Press", 3)           -- "Yes, I heard it": the voice is set up
combo("Shift", "Sym", 3)
shot("tts-1")
add({ wait = 4 })
shot("tts-2")
add({ wait = 4 })
shot("tts-3")
combo("Shift", "Sym", 3)
key("Back", 8)
shot("home-1")
key("Menu", 4)
shot("homemenu-1")
key("Back", 3)
key("X", 6)               -- the Downloads tab
shot("downloaded-1")
return s
