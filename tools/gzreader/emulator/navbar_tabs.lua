-- Favorites stays in Settings → Interface → Navbar → Tabs (off by default,
-- Notes took its place in the bar), and the setup guide's Navbar Tabs page
-- offers Notes and Favorites. With demo/demo_grimmory.py on 127.0.0.1:18080.
-- Also checks the config migrations from 1.4.x and from 1.5.0.
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
-- Settings → Interface → Navbar → Tabs
key("Menu", 4)
key("U", 6)
key("R", 4)
key("E", 4)
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
-- migrations: a 1.4.x config (Favorites in the bar, no Notes) and a 1.5.0
-- config (Favorites taken out of the list)
add({ fn = function(E)
    local M = require("config/manager")
    local utils = require("common/utils")
    local base = M.load()
    local function try(label, setup)
        local old = utils.deepcopy(base)
        old._meta.gz_calendar_tab_migrated = nil -- (configs from before 1.6.0)
        old.navbar.show_tabs.ct_calendar = nil
        local keep = {}
        for _i, ct in ipairs(old.navbar.custom_tabs or {}) do if ct.id ~= "ct_calendar" then keep[#keep + 1] = ct end end
        old.navbar.custom_tabs = keep
        setup(old)
        M.save(old)
        local new = M.load()
        local on = {}
        for _i, id in ipairs(new.navbar.tab_order) do
            on[#on + 1] = id .. (new.navbar.show_tabs[id] == true and "+" or "-")
        end
        local n, c = 0, 0
        for _i, ct in ipairs(new.navbar.custom_tabs) do
            if ct.id == "ct_notes" then n = n + 1 end
            if ct.id == "ct_calendar" then c = c + 1 end
        end
        E.say(label, table.concat(on, " "), "| notes / calendar tabs defined:", n, c)
        local again = M.load()
        E.say(label .. " (loaded again)", #again.navbar.tab_order == #new.navbar.tab_order and "same" or "changed")
    end
    try("from 1.4.x:", function(c)
        c._meta.gz_notes_tab_migrated = nil
        c._meta.gz_favorites_listed_migrated = nil
        c.navbar.custom_tabs = { { id = "ct_grimmory", type = "action", action = { grimmory_library = true }, label = "Grimmory", icon = "library" } }
        c.navbar.tab_order = { "home", "books", "continue", "ct_grimmory", "favorites" }
        c.navbar.show_tabs.favorites = true
        c.navbar.show_tabs.ct_notes = nil
    end)
    try("from 1.5.0:", function(c)
        c._meta.gz_notes_tab_migrated = true
        c._meta.gz_favorites_listed_migrated = nil
        c.navbar.tab_order = { "home", "books", "continue", "ct_grimmory", "ct_notes" }
        c.navbar.show_tabs.continue = true
        c.navbar.show_tabs.favorites = false
        c.navbar.show_tabs.ct_notes = true
    end)
    try("1.5.0, Favorites turned back on by hand:", function(c)
        c._meta.gz_notes_tab_migrated = true
        c._meta.gz_favorites_listed_migrated = nil
        c.navbar.tab_order = { "home", "books", "favorites", "continue", "ct_grimmory", "ct_notes" }
        c.navbar.show_tabs.favorites = true
    end)
end, after = 2 })
return s
