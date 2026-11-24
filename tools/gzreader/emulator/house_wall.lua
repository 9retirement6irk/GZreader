-- The House tab in the Bookshelf view (gzreader_houseview.lua), with
-- demo/mock_homeassistant.py on 127.0.0.1:18095: the hallway (the home's own
-- things, a plate a room, the scenes), a room opened from its plate, a switch
-- flipped and All lights, Back to the hallway, a speaker's buttons and a
-- playlist of Music Assistant's played on it, and the list again in another
-- view.
--   python3 -I demo/mock_homeassistant.py 18095 &      (a fresh one each run: it keeps its state)
--   GZ_EMU_TREE=<tree>/koreader ./run.sh house_wall.lua <out>
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function House() return require("gzreader_house") end
local function wall() local t = House().instance; return t and t.menu and t.menu._gz_wall end
local function place(text)
    local p = wall()
    for _i, pl in ipairs(p and p.places or {}) do if pl.entry and pl.entry.text == text then return pl end end
end
local function kinds()
    local p, t = wall(), {}
    for _i, pl in ipairs(p and p.places or {}) do t[#t + 1] = pl.kind .. (pl.letter and (":" .. pl.letter) or "") end
    return table.concat(t, " ")
end
local function state(id)
    local h = io.popen("curl -s http://127.0.0.1:18095/__state")
    local st = h:read("*a"); h:close()
    return st:match('"entity_id": "' .. id:gsub("%.", "%%.") .. '", "state": "([^"]*)"')
end
-- (the setup guide, if it is up: closed)
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for _i, w in ipairs(UIManager._window_stack or {}) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIManager:close(w.widget) end
    end
end, after = 4 })
add({ fn = function(E)
    local ok, err = require("gzreader_homeassistant").connect(plugin(), "127.0.0.1:18095", "ha-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    House().setTabShown(true)
    require("common/gz_view").set("bookshelf")
end, after = 8 })
add({ fn = function() House().show(plugin()) end, after = 12 })
add({ shot = "wall-1-hallway" })
add({ fn = function(E)
    E.say("hallway:", wall() and "yes" or "NO WALL", "pages", tostring(House().instance.menu.page_num), "places", kinds())
    place("Living room").hot:onTapShop()
end, after = 8 })
add({ shot = "wall-2-room" })
add({ fn = function(E)
    E.say("room:", tostring(House().instance.wall_room), "places", kinds())
    place("Floor lamp").hot:onTapShop()
end, after = 8 })
add({ shot = "wall-3-lamp-on" })
add({ fn = function(E)
    E.say("floor lamp:", tostring(state("light.floor_lamp")))
    place("All lights").hot:onTapShop()
end, after = 8 })
add({ shot = "wall-4-all-lights-off" })
add({ fn = function(E)
    E.say("after All lights: ceiling", tostring(state("light.living_room_ceiling")), "floor lamp", tostring(state("light.floor_lamp")))
    place("Speaker").hot:onTapShop()
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
    local m = House().instance.music_menu
    E.say("playlists:", m and tostring(#m.item_table) or "NO LIST", m and tostring(m.item_table[1].text))
    if m then m:onMenuSelect(m.item_table[1]) end
end, after = 8 })
add({ shot = "wall-7-playing" })
-- Back: the hallway (the key on a Kindle with one)
add({ fn = function(E)
    E.say("the speaker:", tostring(state("media_player.living_room_speaker")))
    -- (touch models have no Back key: the next step fails there, harmlessly)
    if (os.getenv("GZ_EMU_MODEL") or "k3") ~= "k3" then House().instance.menu:onClose() end
end, after = 2 })
add({ key = "Back", after = 6 })
add({ shot = "wall-8-back-in-the-hallway" })
add({ fn = function(E)
    local t = House().instance
    E.say("back in the hallway:", tostring(t ~= nil and not t.closed and t.wall_room == nil and wall() ~= nil), "places", kinds())
    -- a scene, by its letter where there are letters
    local m = t.menu
    for pg = 1, m.page_num do
        m:onGotoPage(pg)
        local pl = place("Goodnight")
        if pl then
            if pl.letter then m:onSelectByShortCut(nil, { key = pl.letter }) else pl.hot:onTapShop() end
            break
        end
    end
end, after = 8 })
add({ shot = "wall-9-scene-run" })
add({ fn = function(E)
    E.say("Goodnight ran: porch", tostring(state("light.porch")))
    require("common/gz_view").set("mosaic_image")
    local UIManager = require("ui/uimanager")
    UIManager:close(House().instance.menu)
    House().show(plugin())
    E.say("another view: the list:", tostring(wall() == nil))
end, after = 10 })
add({ shot = "wall-10-list-in-another-view" })
add({ fn = function() require("common/gz_view").set("bookshelf") end, after = 2 })
return s
