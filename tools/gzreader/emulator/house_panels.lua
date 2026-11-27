-- The House tab's control panels in the Bookshelf view (gzreader_housepanel.lua),
-- with demo/mock_homeassistant.py on 127.0.0.1:18095: the dimmer (a level by
-- a real tap on a touch model, by the 5-way and a letter on the k3), the
-- thermostat (+, a mode), a speaker (play, a volume light, shuffle), a TV
-- that only switches, a bulb with colours, closing (a tap outside, Back), and
-- choosing music: the shelves' keys and Music Assistant's lists as shelves.
--   GZ_HA_DEMO_MUSIC=1 python3 -I demo/mock_homeassistant.py 18095 &   (a fresh one each run: it keeps its state)
--   GZ_EMU_TREE=<tree>/koreader ./run.sh house_panels.lua <out>
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local touch = (os.getenv("GZ_EMU_MODEL") or "k3") ~= "k3"
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function House() return require("gzreader_house") end
local function panel() local t = House().instance; return t and t.panel and not t.panel.closed and t.panel or nil end
local function control(id) local p = panel(); for i, c in ipairs(p and p.P.controls or {}) do if c.id == id then return c, p.rects and p.rects[i] end end end
local function attr(id, name)
    local h = io.popen("curl -s http://127.0.0.1:18095/__state")
    local st = h:read("*a"); h:close()
    local data = require("gzreader_json").decode(st) or {}
    for _i, e in ipairs(data.states or {}) do
        if e.entity_id == id then return name == "state" and e.state or (e.attributes or {})[name] end
    end
end
local function press(id) return function(E)
    local c, r = control(id)
    if not c then return E.say("NO CONTROL", id) end
    -- a real tap where the control is drawn, on a touch model
    if touch and r then E.tap({ r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) }) else panel():press(c) end
end end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for _i, w in ipairs(UIManager._window_stack or {}) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIManager:close(w.widget) end
    end
end, after = 4 })
add({ fn = function(E)
    E.say("connect ->", tostring(require("gzreader_homeassistant").connect(plugin(), "127.0.0.1:18095", "ha-test-token")))
    House().setTabShown(true)
    require("common/gz_view").set("bookshelf")
end, after = 8 })
add({ fn = function() House().show(plugin()) end, after = 12 })
-- the dimmer
add({ fn = function() House().instance:tap("light.living_room_ceiling") end, after = 6 })
add({ shot = "panel-1-dimmer" })
add({ fn = function(E) E.say("dimmer open:", tostring(panel() and panel().P.kind), panel() and panel().P.state or ""); press("level60")(E) end, after = 8 })
add({ shot = "panel-2-dimmer-60" })
add({ fn = function(E) E.say("60% pressed: brightness", tostring(attr("light.living_room_ceiling", "brightness")), "panel says", panel() and panel().P.state or "CLOSED") end, after = 1 })
-- a Kindle with keys: the frame down a light and Press, then the letter of −
if not touch then
    add({ key = "Down", after = 3 })
    add({ key = "Press", after = 8 })
    add({ fn = function(E) E.say("5-way down + Press: panel says", panel() and panel().P.state or "CLOSED") end, after = 1 })
    add({ key = "E", after = 8 })
    add({ shot = "panel-2b-dimmer-keys" })
    add({ fn = function(E) E.say("letter E (−): panel says", panel() and panel().P.state or "CLOSED") end, after = 1 })
    add({ key = "Back", after = 5 })
    add({ fn = function(E) E.say("Back closes the panel, not the tab:", tostring(panel() == nil and House().instance ~= nil and not House().instance.closed)) end, after = 1 })
else
    -- a tap outside the panel closes it
    add({ tap = { 20, 60 }, after = 5 })
    add({ fn = function(E) E.say("a tap outside closes the panel:", tostring(panel() == nil)) end, after = 1 })
end
-- the thermostat
add({ fn = function() House().instance:tap("climate.thermostat") end, after = 6 })
add({ shot = "panel-3-thermostat" })
add({ fn = press("warmer"), after = 8 })
add({ fn = function(E) E.say("+ pressed: target", tostring(attr("climate.thermostat", "temperature")), "dial", tostring(control("dial") and control("dial").text)); press("mode_off")(E) end, after = 8 })
add({ shot = "panel-4-thermostat-off" })
add({ fn = function(E)
    E.say("Off pressed: mode", tostring(attr("climate.thermostat", "state")))
    panel():press(control("mode_heat"))
end, after = 6 })
-- a speaker
add({ fn = function() require("ui/uimanager"):close(panel()); House().instance:tap("media_player.living_room_speaker") end, after = 6 })
add({ shot = "panel-5-speaker" })
add({ fn = press("play_pause"), after = 8 })
add({ fn = press("volume60"), after = 8 })
add({ fn = press("shuffle"), after = 8 })
add({ shot = "panel-6-speaker-playing" })
add({ fn = function(E)
    E.say("speaker:", tostring(attr("media_player.living_room_speaker", "state")), "volume", tostring(attr("media_player.living_room_speaker", "volume_level")),
        "shuffle", tostring(attr("media_player.living_room_speaker", "shuffle")), "panel", control("display") and control("display").foot or "")
    press("music")(E)
end, after = 6 })
-- choosing music: the shelves' keys, then a shelf (the mock started with GZ_HA_DEMO_MUSIC=1 has more on them)
add({ shot = "panel-6b-choose-music" })
add({ fn = function(E) E.say("choose music:", tostring(panel() and panel().P.kind), tostring(panel() and panel().P.title)); press("radio")(E) end, after = 10 })
add({ shot = "panel-6c-radio-shelves" })
add({ fn = function(E)
    local m = House().instance.music_menu
    local pg = m and m._gz_music
    E.say("radio:", m and tostring(#m.item_table) or "NO LIST", "shelves:", pg and "yes" or "NO", "a page holds", tostring(m and m.perpage), "pages", tostring(m and m.page_num))
    require("ui/uimanager"):close(m)
    House().instance:musicList(require("gzreader_homeassistant").find(House().instance.house, "media_player.living_room_speaker"), "album", "Albums", 0)
end, after = 10 })
add({ shot = "panel-6d-album-shelves" })
add({ fn = function(E)
    local m = House().instance.music_menu
    local pl = m._gz_music and m._gz_music.places[1]
    E.say("albums:", tostring(#m.item_table), "first is a", tostring(pl and pl.kind), tostring(pl and pl.entry.text))
    -- a real tap on the first thing on a touch model; its letter's row otherwise
    if touch and pl and pl.hot and pl.hot.dimen then local d = pl.hot.dimen; E.tap({ d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) })
    else m:onMenuSelect(m.item_table[1]) end
end, after = 8 })
add({ fn = function(E)
    E.say("picked from the shelf: now playing", tostring(attr("media_player.living_room_speaker", "media_title")))
    if panel() then require("ui/uimanager"):close(panel()) end
    House().instance:tap("media_player.living_room_tv")
end, after = 6 })
add({ shot = "panel-7-tv" })
add({ fn = function(E)
    E.say("tv panel:", tostring(panel() and #panel().P.controls))
    require("ui/uimanager"):close(panel())
    House().instance:tap("light.under_cabinet")
end, after = 6 })
add({ shot = "panel-8-colour-bulb" })
add({ fn = function(E)
    require("ui/uimanager"):close(panel())
    -- another view: the windows of buttons
    require("common/gz_view").set("mosaic_image")
    House().instance:tap("light.living_room_ceiling")
    E.say("another view: no panel:", tostring(panel() == nil))
end, after = 6 })
add({ shot = "panel-9-buttons-in-another-view" })
add({ fn = function() require("common/gz_view").set("bookshelf") end, after = 2 })
return s
