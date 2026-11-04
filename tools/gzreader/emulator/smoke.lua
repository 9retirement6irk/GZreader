-- Start-up check for CI (any GZ_EMU_MODEL): GZreader starts, the setup
-- guide shows, Home shows, a book (GZ_EMU_BOOK) opens, a page turns, Home
-- again. Writes <out>/smoke.txt: "ok" or what failed.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local seen = {}
local function stackNames()
    local out = {}
    for _i, w in ipairs(require("ui/uimanager")._window_stack) do out[#out + 1] = tostring(w.widget.name or w.widget.title or "?") end
    return table.concat(out, ",")
end
add({ fn = function()
    seen.guide = stackNames():find("setup guide", 1, true) ~= nil
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ shot = "home" })
add({ fn = function() seen.home = stackNames():find("home", 1, true) ~= nil end, after = 1 })
add({ fn = function()
    local Device = require("device")
    local dir = (Device.home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/smoke.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/smoke.epub")
end, after = 25 })
add({ fn = function()
    local ui = require("apps/reader/readerui").instance
    seen.book = ui ~= nil and ui.document ~= nil
    seen.page1 = ui and ui.document and ui.document:getCurrentPage() or nil
end, after = 1 })
add({ key = "RPgFwd", after = 5 })
add({ fn = function()
    local ui = require("apps/reader/readerui").instance
    seen.page2 = ui and ui.document and ui.document:getCurrentPage() or nil
end, after = 1 })
add({ shot = "book" })
add({ key = "Home", after = 10 })
add({ shot = "home-again" })
add({ fn = function(E)
    seen.closed = require("apps/reader/readerui").instance == nil
    local problems = {}
    if not seen.guide then problems[#problems + 1] = "no setup guide at start" end
    if not seen.home then problems[#problems + 1] = "no Home" end
    if not seen.book then problems[#problems + 1] = "the book didn't open" end
    if not (seen.page1 and seen.page2 and seen.page2 > seen.page1) then
        problems[#problems + 1] = "the page didn't turn (" .. tostring(seen.page1) .. " -> " .. tostring(seen.page2) .. ")"
    end
    if not seen.closed then problems[#problems + 1] = "Home didn't close the book" end
    local f = io.open(E.out .. "/smoke.txt", "w")
    f:write(#problems == 0 and "ok\n" or table.concat(problems, "; ") .. "\n")
    f:close()
end, after = 1 })
return s
