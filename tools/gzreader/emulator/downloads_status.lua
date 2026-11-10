-- The download status in the status bar (a download icon, its percentage,
-- how many wait): when it changes, only the status item is refreshed, on
-- the Downloads tab and on Home, never the whole screen.
--   GZ_EMU_TREE=<tree>/koreader ./run.sh downloads_status.lua <out>
-- Writes <out>/downloads_status.txt (every screen refresh after each change).
local s = { start = 12, { key = "Back", after = 4 } }
local lines = {}
local function say(t) lines[#lines + 1] = t end
local refreshes = {}
-- (what reaches the screen, after GZreader's e-ink rules: gzreader_eink.lua)
local function watch()
    local Screen = require("device").screen
    if Screen._gz_watch then return end
    Screen._gz_watch = true
    for _i, kind in ipairs({ "Full", "FlashUI", "FlashPartial", "UI", "Partial", "Fast" }) do
        local name = "refresh" .. kind .. "Imp"
        local orig = Screen[name]
        if type(orig) == "function" then
            Screen[name] = function(scr, x, y, w, h, ...)
                -- (the outermost only: the framebuffer's kinds call one another)
                if not Screen._gz_in then
                    refreshes[#refreshes + 1] = string.format("%s %sx%s+%s+%s", kind:lower(), tostring(w), tostring(h), tostring(x), tostring(y))
                end
                local was = Screen._gz_in
                Screen._gz_in = true
                local r = { orig(scr, x, y, w, h, ...) }
                Screen._gz_in = was
                return unpack(r)
            end
        end
    end
end
-- a stand-in download at `pct` percent, with `waiting` queued
local function fake(pct, waiting)
    local D = require("gzreader_download")
    D.active = D.active or { title = "Big Book", expected = 1000, book_id = "1" }
    D.active.last_size = pct * 10
    D.queue = {}
    for i = 1, waiting do D.queue[i] = { book = { id = 100 + i, title = "Q" .. i } } end
end
local function step(name, pct, waiting)
    s[#s + 1] = { fn = function()
        watch()
        refreshes = {}
        fake(pct, waiting)
        require("gzreader_tasks").changed()
    end, after = 4 }
    s[#s + 1] = { fn = function()
        local Screen = require("device").screen
        local W, H = Screen:getWidth(), Screen:getHeight()
        local big = 0
        for _i, r in ipairs(refreshes) do
            local w, h = r:match(" (%d+)x(%d+)")
            if r:match("^full") or r:match("^flash") or (tonumber(w) and tonumber(w) * tonumber(h) > W * H / 3) then big = big + 1 end
        end
        say(string.format("%s %s: %d refresh(es), %d big or flashing: %s", big == 0 and "ok  " or "FAIL", name, #refreshes, big,
            table.concat(refreshes, " | ")))
    end, after = 1 }
end
s[#s + 1] = { combo = { "Alt", "W" }, after = 10 } -- the Downloads tab
step("Downloads tab, 10% +1", 10, 1)
step("Downloads tab, 11% +1", 11, 1)
step("Downloads tab, 100% (wider) +1", 100, 1)
step("Downloads tab, 5% (narrower) +0", 5, 0)
-- a book done: the Downloads tab shows it again (main.lua refreshDownloadsTab), with no key pressed
s[#s + 1] = { fn = function()
    os.execute("cp /root/work/demo/lib/1.epub /mnt/us/GZreader/ 2>/dev/null")
end, after = 12 } -- (no key for a while)
s[#s + 1] = { fn = function()
    watch()
    refreshes = {}
    local fm = require("apps/filemanager/filemanager").instance
    local ok = pcall(function() fm.gzreader:refreshDownloadsTab() end)
    s.refreshed = ok
end, after = 4 }
s[#s + 1] = { fn = function()
    local flashed = 0
    for _i, r in ipairs(refreshes) do if r:match("^full") or r:match("^flash") then flashed = flashed + 1 end end
    say(string.format("%s a book arrived on the Downloads tab (no key pressed): %d refresh(es), %d flashing: %s",
        flashed == 0 and "ok  " or "FAIL", #refreshes, flashed, table.concat(refreshes, " | ")))
end, after = 1 }
s[#s + 1] = { combo = { "Alt", "Q" }, after = 10 } -- Home
step("Home, 20% +2", 20, 2)
step("Home, 21% +2", 21, 2)
-- what you do still flashes: switching tabs
s[#s + 1] = { fn = function() refreshes = {} end, after = 1 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 10 }
s[#s + 1] = { fn = function()
    local flashed = 0
    for _i, r in ipairs(refreshes) do if r:match("^full") or r:match("^flash") then flashed = flashed + 1 end end
    say(string.format("%s switching tabs with a key still flashes: %s", flashed > 0 and "ok  " or "FAIL", table.concat(refreshes, " | ")))
end, after = 1 }
s[#s + 1] = { fn = function(E)
    local f = io.open(E.out .. "/downloads_status.txt", "w")
    if f then f:write(table.concat(lines, "\n"), "\n"); f:close() end
end, after = 1 }
return s
