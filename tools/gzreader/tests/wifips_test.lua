-- Wi-Fi power saving off while a book or update downloads (gzreader_wifips.lua),
-- back as it was after the last one.
--   luajit wifips_test.lua <repo>
local REPO = arg[1] or "../../.."
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. REPO .. "/frontend/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local lines = {}
local function rec(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
    lines[#lines + 1] = table.concat(t, " ")
end
package.loaded["gzreader_log"] = { enabled = true, info = rec, warn = rec }
package.loaded["ui/network/manager"] = { getNetworkInterfaceName = function() return "wlan0" end }
local PS = require("gzreader_wifips")

local state, sets, fail_get, fail_set = "on", {}, nil, nil
PS.io = {
    get = function(ifname)
        if fail_get then return nil, fail_get end
        check(ifname == "wlan0", "the Kindle's interface")
        return state
    end,
    set = function(_ifname, on)
        if fail_set then return nil, fail_set end
        sets[#sets + 1] = on
        state = on and "on" or "off"
        return true
    end,
}
local function reset(s) state, sets, lines, fail_get, fail_set = s, {}, {}, nil, nil; PS.holding, PS.restore = {}, false end

print("== Wi-Fi power saving while downloading")

reset("on")
PS.hold("download")
check(sets[1] == false and state == "off", "a download turns power saving off")
check((lines[1] or ""):find("power saving off while transferring (download)", 1, true) ~= nil, "and says so in the log")
PS.release("download")
check(sets[2] == true and state == "on", "after it, power saving is back on")

reset("on")
PS.hold("download"); PS.hold("update")
check(#sets == 1, "a second transfer doesn't switch it again")
PS.release("download")
check(#sets == 1 and state == "off", "still off while the update runs")
PS.release("update")
check(#sets == 2 and state == "on", "back on after the last one")

reset("off")
PS.hold("update"); PS.release("update")
check(#sets == 0, "already off (the Nook, or the user's choice): left alone, not turned on after")

reset("on")
PS.hold("async"); PS.hold("pairserver"); PS.release("async"); PS.release("pairserver")
check(#sets == 0, "other Wi-Fi holders (requests, the QR page) don't change it")

reset("on")
PS.release("download")
check(#sets == 0, "a release without a hold changes nothing")

reset("on")
fail_get = "no such device"
PS.hold("download"); PS.release("download")
check(#sets == 0 and (lines[1] or ""):find("power saving unknown", 1, true) ~= nil, "can't read it (no Wi-Fi, old driver): left alone, reason logged")

reset("on")
fail_set = "Operation not supported"
PS.hold("download")
check((lines[1] or ""):find("couldn't turn power saving off", 1, true) ~= nil and not PS.restore, "can't set it: logged, nothing to put back")
fail_set = nil
PS.release("download")
check(#sets == 0, "and not turned on afterwards")

;(function()
    PS.io = { get = function() error("boom") end, set = function() error("boom") end }
    reset("on")
    PS.io = { get = function() error("boom") end, set = function() error("boom") end }
    local ok = pcall(function() PS.hold("download"); PS.release("download") end)
    check(ok, "an error in the ioctl never reaches the download")
    PS.io = nil
    local okr, st, why = pcall(PS.get)
    check(okr and (st ~= nil or why ~= nil), "the real ioctl answers or says why (" .. tostring(st or why) .. ")")
end)()

;(function()
    local function src(p) local f = assert(io.open(REPO .. "/" .. p)); local s = f:read("*a"); f:close(); return s end
    local net = src("plugins/gzreader.koplugin/gzreader_net.lua")
    check(net:find('require("gzreader_wifips").hold(key)', 1, true) ~= nil, "Net.hold asks it")
    check(net:find('require("gzreader_wifips").release(key)', 1, true) ~= nil, "Net.release asks it")
    local mod = src("plugins/gzreader.koplugin/gzreader_wifips.lua")
    check(not mod:find("ESSID", 1, true) and not mod:find("popen", 1, true) and not mod:find("wpa", 1, true),
        "no network name read, no shell commands")
end)()

print(string.format("Wi-Fi power saving: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
