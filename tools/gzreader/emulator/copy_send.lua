-- Copying connections, the sending side (run with copy_receive.lua on a
-- second emulator at the same time; any two GZ_EMU_MODELs). Connects
-- Grimmory (mock_grimmory.py on 18080), Notes (demo/mock_memos.py on 18082)
-- and the CalDAV account (demo/demo_caldav.py on 18083), hides one
-- calendar, then Send connections: writes the PIN to $GZ_COPY_PIN for the
-- other emulator, waits until it has copied (or 4 minutes).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    E.say("grimmory", tostring(p:connect("http://127.0.0.1:18080", "will", "hunter22")))
    E.say("memos", tostring(require("gzreader_notes").connect(p, "http://127.0.0.1:18082", "memos-test-token")))
    E.say("caldav", tostring(require("gzreader_calendar").connect(p, "http://127.0.0.1:18083", "reader", "demo-app-password")))
    p.store.caldav.calendars[1].enabled = false
    p:save()
end, after = 3 })
add({ fn = function(E)
    local Copy = require("gzreader_copy")
    Copy.send(plugin(), { on_done = function(sent) E.say("send screen closed", sent and sent.what or "-") end })
end, after = 4 })
add({ fn = function(E)
    local S = require("gzreader_copy").session
    E.say("sending as", require("gzreader_copy").deviceName(plugin()), S and "PIN ready" or "NOT SENDING")
    local f = io.open(os.getenv("GZ_COPY_PIN"), "w"); f:write(S and S.pin or "none"); f:close()
end, after = 1 })
add({ shot = "1-send" })
add({ wait_for = function() local S = require("gzreader_copy").session; return S and S.sent ~= nil end, timeout = 240 })
add({ wait = 2 })
add({ shot = "2-sent" })
add({ fn = function(E)
    local S = require("gzreader_copy").session
    E.say("sent:", S and S.sent and (S.sent.to .. ": " .. S.sent.what) or "nothing", "tries", S and S.tries)
end, after = 1 })
return s
