-- Copying connections, the receiving side (with copy_send.lua running on
-- another emulator): Copy from another GZreader, the device found by mDNS,
-- the PIN from $GZ_COPY_PIN, what to copy, the result, then Grimmory's
-- sign-in with the address and account filled in. Writes <out>/copy.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function stack() return require("ui/uimanager")._window_stack end
local function top() local st = stack(); return st[#st] and st[#st].widget end
local function menuTitled(pat)
    for i = #stack(), 1, -1 do
        local w = stack()[i].widget
        if w.item_table and tostring(w.title):match(pat) then return w end
    end
end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function() require("gzreader_copy").receive(plugin()) end, after = 1 })
add({ shot = "1-looking" })
add({ wait_for = function()
    local m = menuTitled("^Copy from another GZreader")
    return m and m.item_table[1] and m.item_table[1].mandatory ~= nil
end, timeout = 30 })
add({ shot = "2-found" })
add({ fn = function(E)
    local m = menuTitled("^Copy from another GZreader")
    local dev = m and m.item_table[1]
    check(dev and dev.text:match("·"), "mDNS: the sending emulator is listed: " .. tostring(dev and dev.text) .. " " .. tostring(dev and dev.mandatory))
    if dev then dev.callback() end
end, after = 3 })
add({ shot = "3-pin" })
add({ fn = function(E)
    local f = io.open(os.getenv("GZ_COPY_PIN")); local pin = f and f:read("*a") or ""; if f then f:close() end
    local d = top()
    check(d and d.title and d.title:match("^PIN shown on"), "PIN asked for: " .. tostring(d and d.title))
    d:setInputText(pin)
    d.buttons[1][2].callback()
end, after = 6 })
add({ shot = "4-choose" })
add({ fn = function(E)
    local m = menuTitled("^Copy from ")
    local t = {}
    for _i, it in ipairs(m and m.item_table or {}) do t[#t + 1] = it.text .. " [" .. tostring(it.mandatory) .. "]" end
    check(m and #t >= 4, "what the other has, ticked: " .. table.concat(t, " | "))
    m.item_table[#m.item_table].callback()
end, after = 10 })
add({ shot = "5-copied" })
add({ fn = function(E)
    local p = plugin()
    check((p.store.memos or {}).token ~= nil, "Notes connected")
    local cals = (p.store.caldav or {}).calendars or {}
    check(#cals == 2 and cals[1].enabled == false, "CalDAV connected, the hidden calendar hidden")
    local d = top()
    local t = tostring(d and d.title)
    check(t:match("Notes: connected") and t:match("Calendar: connected") and t:match("own sign%-in"),
        "the result, then Grimmory's sign-in here: " .. t:gsub("\n", " / "))
    d.buttons[1][1].callback()
end, after = 3 })
add({ shot = "6-login" })
add({ fn = function(E)
    local d = top()
    local f = d and d.getFields and d:getFields() or {}
    check(f[1] == "http://127.0.0.1:18080" and f[2] == "will" and f[3] == "", "Grimmory login filled in (address and account): " .. tostring(f[1]) .. " " .. tostring(f[2]))
    local out = io.open(E.out .. "/copy.txt", "w"); out:write(table.concat(lines, "\n"), "\n"); out:close()
end, after = 1 })
return s
