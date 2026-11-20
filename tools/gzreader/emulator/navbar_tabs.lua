-- Favorites stays in Settings → Home and tabs → Tab bar → Tabs (off by default,
-- Notes took its place in the bar), and the setup guide's Navbar Tabs page
-- offers Notes and Favorites. With demo/demo_grimmory.py on 127.0.0.1:18080.
-- GZ_FAV_IN_SETUP=1: turn Favorites on in the setup guide; otherwise leave
-- the page as it is and turn Favorites on in Settings → Navbar → Tabs.
local FAV_IN_SETUP = os.getenv("GZ_FAV_IN_SETUP") == "1"
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function tabs(E, label)
    local cfg = require("config/manager").load()
    local on = {}
    for _i, id in ipairs(cfg.navbar.tab_order) do
        on[#on + 1] = id .. (cfg.navbar.show_tabs[id] == true and "+" or "-")
    end
    E.say(label, table.concat(on, " "))
end
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "setup-4-guide-3" then
        -- the Navbar Tabs page: as it starts, then with Favorites turned on
        add({ fn = function(E) tabs(E, "tabs before the setup page:") end, after = 1 })
        shot("tabs-1-setup-page")
        if FAV_IN_SETUP then
            for _j = 1, 6 do key("Down", 1.5) end -- Home, Continue, Notes, Calendar, History, Favorites
            key("Press", 2)
            shot("tabs-2-setup-favorites-on")
        end
    end
    if step.shot == "home-empty" then break end
end
add({ fn = function(E) tabs(E, "tabs after the setup guide:") end, after = 1 })
shot("tabs-3-home-bar")
-- Settings → Home and tabs → Tab bar → Tabs (Interface: Quick panel Q, Navbar W)
key("Menu", 4)
key("U", 6)
key("R", 4)
key("W", 4)
shot("tabs-4-navbar-settings")
key("Q", 5)
shot("tabs-5-tabs-list")
if not FAV_IN_SETUP then
    -- Favorites is the 7th row (Home, Downloads, Grimmory, Notes, Calendar,
    -- Continue, Favorites): ▶ moves to its switch, Press turns it on
    for _j = 1, 6 do key("Down", 1.5) end
    key("Right", 1.5)
    key("Press", 3)
    shot("tabs-6-favorites-turned-on")
    add({ fn = function(E) tabs(E, "tabs after turning Favorites on:") end, after = 1 })
end
key("Back", 3); key("Back", 3); key("Back", 3); key("Back", 3)
add({ wait = 4 })
shot("tabs-7-home-bar-after")
return s
