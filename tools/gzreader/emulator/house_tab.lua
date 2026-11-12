-- The House tab (Home Assistant), with demo/mock_homeassistant.py on
-- 127.0.0.1:18095: connected, the tab turned on in the tab bar, the rooms,
-- a dimmable light's dimmer, the thermostat, and Settings → Connections →
-- Home Assistant (House).
--   python3 -I demo/mock_homeassistant.py 18095 &
--   GZ_EMU_TREE=<tree>/koreader ./run.sh house_tab.lua <out>
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
add({ fn = function(E)
    local ok, err = require("gzreader_homeassistant").connect(plugin(), "127.0.0.1:18095", "ha-test-token")
    E.say("connect ->", tostring(ok), tostring(err))
    E.say("tab on ->", tostring(require("gzreader_house").setTabShown(true)))
end, after = 8 })
add({ shot = "house-0-tabbar" })
add({ fn = function() require("gzreader_house").show(plugin()) end, after = 12 })
add({ shot = "house-1-rooms" })
add({ fn = function(E)
    local House = require("gzreader_house")
    local rows = House.instance and House.instance.menu.item_table or {}
    local t = {}
    for _i, r in ipairs(rows) do t[#t + 1] = tostring(r.text) .. (r.mandatory and (" = " .. r.mandatory) or "") end
    E.say("rows:", table.concat(t, " | "))
    House.instance:tap("light.living_room_ceiling")
end, after = 6 })
add({ shot = "house-2-dimmer" })
add({ key = "Back", after = 4 })
add({ fn = function() require("gzreader_house").instance:tap("climate.thermostat") end, after = 6 })
add({ shot = "house-3-thermostat" })
add({ key = "Back", after = 4 })
add({ fn = function() require("gzreader_house").instance:tap("light.floor_lamp") end, after = 8 })
add({ shot = "house-4-lamp-on" })
add({ fn = function(E)
    local h = io.popen("curl -s http://127.0.0.1:18095/__state")
    local st = h:read("*a"); h:close()
    E.say("floor lamp on in Home Assistant:", tostring(st:find('"entity_id": "light.floor_lamp", "state": "on"', 1, true) ~= nil))
    local UIManager = require("ui/uimanager")
    local House = require("gzreader_house")
    if House.instance then UIManager:close(House.instance.menu) end
    require("modules/settings/zen_settings_page").closeActive()
    require("modules/settings/zen_settings_page").show(require("gzreader_tabs").zen(), { path = {
        { key = "text", value = "Connections" }, { key = "text", value = "Home Assistant (House)" } } })
end, after = 10 })
add({ shot = "house-5-settings" })
return s
