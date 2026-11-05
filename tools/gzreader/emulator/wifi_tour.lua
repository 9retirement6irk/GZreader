-- The Wi-Fi networks page (GZ_EMU_WIFID=1): list, then join a saved network.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
add({ fn = function(E)
    local UI = require("ui/uimanager")
    for i = #UI._window_stack, 1, -1 do
        local w = UI._window_stack[i].widget
        if w.name ~= "filemanager" and not w._zen_home_focus_targets and i > 1 then UI:close(w) end
    end
    local NM = require("ui/network/manager")
    NM.getCurrentNetwork = function() return E.wifid.current and { ssid = E.wifid.current } or nil end
    NM.isConnected = function() return E.wifid.current ~= nil end
    NM.obtainIP = function() end
    NM.releaseIP = function() end
    NM.hasDefaultRoute = function() return E.wifid.current ~= nil end
    require("modules/settings/zen_settings_utils").get_device_ip_address = function() return E.wifid.current and "192.0.2.5" or nil end
    local zen = require("apps/filemanager/filemanager").instance.zenos
    require("modules/menu/network_switcher").open(nil, true, zen)
end, after = 8 })
add({ fn = function(E) E.say("calls:", table.concat(E.wifid.calls, " | ")) end, after = 1 })
add({ shot = "w1-list" })
add({ fn = function(E)
    local UI = require("ui/uimanager")
    for _i, w in ipairs(UI._window_stack) do
        if w.widget.name == "network_switcher" then
            for _j, it in ipairs(w.widget.item_table) do
                if it.text == "Home" then E.say("selecting Home"); w.widget:onMenuSelect(it) end
            end
        end
    end
end, after = 20 })
add({ fn = function(E) E.say("calls:", table.concat(E.wifid.calls, " | "), "current:", tostring(E.wifid.current), "windows:", E.top()) end, after = 1 })
add({ shot = "w2-joined" })
return s
