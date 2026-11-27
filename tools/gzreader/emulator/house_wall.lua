-- The House tab in the Bookshelf view (gzreader_houseview.lua): the rooms as a
-- wall with a fitting for each device, with demo/mock_homeassistant.py on
-- 127.0.0.1:18095. Its pages, a switch flipped (a tap, or its letter on a
-- keyboard Kindle), a speaker's buttons and a playlist of Music Assistant's
-- played on it, and the list again in another view.
--   python3 -I demo/mock_homeassistant.py 18095 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh house_wall.lua <out>
local s = { start = 12 }
-- (the setup guide, if it is up: closed)
s[#s + 1] = { fn = function()
    local UIManager = require("ui/uimanager")
    for _i, w in ipairs(UIManager._window_stack or {}) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIManager:close(w.widget) end
    end
end, after = 4 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function House() return require("gzreader_house") end
local function wall() local t = House().instance; return t and t.menu and t.menu._gz_wall end
add({ fn = function(E)
    local ok, err = require("gzreader_homeassistant").connect(plugin(), "127.0.0.1:18095", "ha-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    House().setTabShown(true)
    require("common/gz_view").set("bookshelf")
end, after = 8 })
add({ fn = function() House().show(plugin()) end, after = 12 })
add({ shot = "wall-1-first-page" })
add({ fn = function(E)
    local m = House().instance.menu
    local p = wall()
    local t = {}
    for _i, pl in ipairs(p and p.places or {}) do t[#t + 1] = pl.kind .. (pl.letter and (":" .. pl.letter) or "") end
    E.say("wall:", p and "yes" or "NO", "pages", tostring(m.page_num), "places", table.concat(t, " "))
    -- a switch, by what a tap on it does
    for _i, pl in ipairs(p and p.places or {}) do
        if pl.entry and pl.entry.gz_house_id == "light.floor_lamp" then pl.hot:onTapShop() end
    end
end, after = 8 })
add({ shot = "wall-2-lamp-on" })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18095/__state")
    local st = h:read("*a"); h:close()
    E.say("floor lamp on in Home Assistant:", tostring(st:find('"entity_id": "light.floor_lamp", "state": "on"', 1, true) ~= nil))
    House().instance.menu:onNextPage()
end, after = 8 })
add({ shot = "wall-3-next-page" })
add({ fn = function(E)
    local m = House().instance.menu
    E.say("page", tostring(m.page), "of", tostring(m.page_num))
    -- a letter on this page: what has it on the wall
    local p = wall()
    local first
    for _i, pl in ipairs(p and p.places or {}) do if pl.letter and pl.kind == "key" and not first then first = pl end end
    if first then
        E.say("letter", first.letter, "is", tostring(first.entry.text))
        m:onSelectByShortCut(nil, { key = first.letter })
    end
end, after = 8 })
add({ shot = "wall-4-scene-run" })
-- a speaker's buttons, then Music Assistant's playlists
add({ fn = function()
    House().instance.menu:onGotoPage(1)
    House().instance:tap("media_player.living_room_speaker")
end, after = 6 })
add({ shot = "wall-5-speaker" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    UIManager:close(stack[#stack].widget)
    local t = House().instance
    t:musicList(require("gzreader_homeassistant").find(t.house, "media_player.living_room_speaker"), "playlist", "Playlists", 0)
end, after = 8 })
add({ shot = "wall-6-playlists" })
add({ fn = function(E)
    local t = House().instance
    local m = t.music_menu
    E.say("playlists:", m and tostring(#m.item_table) or "NO LIST", m and tostring(m.item_table[1].text))
    if m then m:onMenuSelect(m.item_table[1]) end
end, after = 8 })
add({ shot = "wall-7-playing" })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18095/__state")
    local st = h:read("*a"); h:close()
    E.say("the speaker plays the playlist:", tostring(st:find('"media_content_id": "library://playlist/1"', 1, true) ~= nil))
end, after = 2 })
add({ fn = function(E)
    require("common/gz_view").set("mosaic_image")
    local UIManager = require("ui/uimanager")
    UIManager:close(House().instance.menu)
    House().show(plugin())
    E.say("another view: the list:", tostring(wall() == nil))
end, after = 10 })
add({ shot = "wall-8-list-in-another-view" })
add({ fn = function() require("common/gz_view").set("bookshelf") end, after = 2 })
return s
