-- A Kobo (GZ_EMU_MODEL=clara: Clara HD, or libra: Libra 2): GZreader as
-- KOReader's Kobo build starts it, from the setup guide to Home, the tabs,
-- a book (pages turned by taps), the quick panel, Settings and Sync with a
-- computer. Checks go to <out>/kobo-checks.txt ("ok …" / "FAIL …").
--   GZ_EMU_BOOK=book.epub GZ_EMU_MODEL=clara run.sh tools/gzreader/emulator/kobo_tour.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function UIM() return require("ui/uimanager") end
local function W() return require("device").screen:getWidth() end
local function H() return require("device").screen:getHeight() end
local function check(E, ok, what)
    local f = io.open(E.out .. "/kobo-checks.txt", "a")
    f:write(ok and "ok   " or "FAIL ", what, "\n")
    f:close()
    E.say(ok and "ok" or "FAIL", what)
end
local function top()
    local st = UIM()._window_stack
    return st[#st] and st[#st].widget
end
local function closeTop() local w = top(); if w then UIM():close(w) end end
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end

add({ fn = function(E)
    local Device = require("device")
    check(E, Device:isKobo() and not Device:isKindle(), "a Kobo (" .. tostring(Device.model) .. ")")
    check(E, Device.home_dir == "/mnt/onboard", "home folder /mnt/onboard")
end, after = 1 })
shot("01-guide")
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
shot("02-home")
add({ fn = function(E)
    local p = plugin()
    check(E, p ~= nil and p:libraryDir() == "/mnt/onboard/GZreader", "the GZreader folder on the Kobo's drive: " .. tostring(p and p:libraryDir()))
    check(E, require("gzreader_copy").modelName() == (E.model == "libra" and "Kobo Libra 2" or "Kobo Clara HD"),
        "named " .. require("gzreader_copy").modelName())
end, after = 1 })
-- the tabs along the bottom (five, evenly spread)
for i, tab in ipairs({ "Downloads", "Catalog", "Notes", "Calendar", "Home" }) do
    local col = ({ 2, 3, 4, 5, 1 })[i]
    add({ tap = function() return W() * (col - 0.5) / 5, H() - 60 end, after = 6 })
    shot("03-tab-" .. tab:lower())
    if tab == "Calendar" then
        add({ fn = function(E) check(E, E.findText("Type a calendar link") ~= nil, "a tap on the tab bar opens the Calendar tab") end, after = 0.5 })
    end
end
-- a book, pages turned with taps on the right
add({ fn = function()
    os.execute("mkdir -p /mnt/onboard/GZreader && cp '" .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. "' /mnt/onboard/GZreader/book.epub")
    require("apps/reader/readerui"):showReader("/mnt/onboard/GZreader/book.epub")
end, after = 20 })
shot("04-book")
add({ fn = function(E)
    local ui = require("apps/reader/readerui").instance
    E.page0 = ui and ui.document and ui:getCurrentPage()
end, after = 0.5 })
add({ tap = function() return W() * 0.9, H() * 0.5 end, after = 4 })
add({ tap = function() return W() * 0.9, H() * 0.5 end, after = 4 })
shot("05-page-turned")
add({ fn = function(E)
    local ui = require("apps/reader/readerui").instance
    local p = ui and ui:getCurrentPage()
    check(E, E.page0 and p and p > E.page0, "taps on the right turn pages (" .. tostring(E.page0) .. " → " .. tostring(p) .. ")")
end, after = 0.5 })
-- the quick panel: a swipe down from the top
add({ swipe = { 540, 5, 540, 700 }, after = 4 })
shot("06-quick-panel")
add({ fn = function(E)
    local w = top()
    check(E, w and w.name == "gzreader quick panel", "a swipe down from the top opens the quick panel (" .. E.top() .. ")")
    closeTop()
end, after = 3 })
add({ fn = function() require("apps/reader/readerui").instance:onHome() end, after = 8 })
shot("07-home-after-book")
-- Sync with a computer: GZreader steps aside for KOReader's USB storage mode
add({ fn = function() require("gzreader_usbsync").show(plugin()) end, after = 4 })
shot("08-sync-with-computer")
add({ fn = function(E)
    local w = top()
    local title = w and w.title or ""
    check(E, title:find("so the Kobo can share its USB drive", 1, true) ~= nil and E.findText("Connect to computer (USB drive)") ~= nil,
        "Sync with a computer: Connect to computer, in the Kobo's words")
    closeTop()
end, after = 2 })
-- Settings
add({ fn = function()
    require("modules/settings/zen_settings_page").show(require("apps/filemanager/filemanager").instance.zenos, {})
end, after = 5 })
shot("09-settings")
add({ fn = function(E)
    E.say("windows:", E.top())
    closeTop()
end, after = 2 })
add({ fn = function(E)
    local f = io.open("gzreader.log")
    local log = f and f:read("*a") or ""
    if f then f:close() end
    local errs = {}
    for line in log:gmatch("[^\n]+") do
        if line:find("%[ERR") or line:find("%[WARN") then errs[#errs + 1] = line end
    end
    check(E, #errs == 0, "no warnings or errors in GZreader's log" .. (#errs > 0 and (": " .. table.concat(errs, " | "):sub(1, 600)) or ""))
end, after = 1 })
return s
