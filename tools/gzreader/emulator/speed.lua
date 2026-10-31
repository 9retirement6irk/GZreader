-- luacheck: globals os io
-- How long GZreader takes for everyday keys (with demo/demo_grimmory.py on
-- 127.0.0.1:18080): after the setup guide and with four books in Recent,
-- each step's CPU time and the time to its last screen refresh, done twice
-- (the first time also loads and compiles the code it needs). A sampling
-- profiler (debug.sethook) notes where the CPU went in each step.
-- Run with a CPU quota for Kindle-like numbers: run.sh speed.lua speed 20
local readme = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local s = { start = readme.start }
for _i, step in ipairs(readme) do
    s[#s + 1] = step
    if step.shot == "home-empty" then break end
end
local function add(t) s[#s + 1] = t end
local function key(k, after) add({ key = k, after = after or 3 }) end

local books = { "9", "10", "11", "12" }
for i, b in ipairs(books) do
    add({ fn = function()
        os.execute("mkdir -p /mnt/us/GZreader && cp /root/work/demo/lib/" .. b .. ".epub /mnt/us/GZreader/book" .. i .. ".epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book" .. i .. ".epub")
    end, after = 14 })
    key("RPgFwd", 3)
    key("Back", 10)
end
add({ wait = 6 })

-- the profiler: every 2000 Lua instructions, the 3 innermost Lua frames
local P = { label = nil, samples = {}, results = {} }
local function sample()
    if not P.label then return end
    local parts = {}
    for level = 2, 12 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        if info.what ~= "C" and info.short_src then
            local src = info.short_src:gsub("^.*/plugins/", ""):gsub("^.*/frontend/", "")
            parts[#parts + 1] = src .. ":" .. tostring(info.currentline)
            if #parts == 3 then break end
        end
    end
    local k = table.concat(parts, " < ")
    P.samples[k] = (P.samples[k] or 0) + 1
    P.total = (P.total or 0) + 1
end

-- forks (os.execute / io.popen: slow on a Kindle 3 with a big process),
-- files opened, and the refreshes (mode, area)
local function caller()
    for level = 3, 8 do
        local info = debug.getinfo(level, "Sl")
        if info and info.short_src and not info.short_src:match("speed%.lua") then
            return info.short_src:gsub("^.*/plugins/", ""):gsub("^.*/frontend/", "") .. ":" .. tostring(info.currentline)
        end
    end
    return "?"
end
local function wrapIO(E)
    if P.wrapped then return end
    P.wrapped = true
    local real_execute, real_popen, real_open = os.execute, io.popen, io.open
    os.execute = function(cmd, ...)
        if P.label then P.forks[#P.forks + 1] = "execute " .. tostring(cmd):sub(1, 60) .. " @ " .. caller() end
        return real_execute(cmd, ...)
    end
    io.popen = function(cmd, ...)
        if P.label then P.forks[#P.forks + 1] = "popen " .. tostring(cmd):sub(1, 60) .. " @ " .. caller() end
        return real_popen(cmd, ...)
    end
    io.open = function(path, ...)
        if P.label then
            local k = tostring(path):gsub("^.*/koreader/", ""):gsub("%d+", "#")
            P.opens[k] = (P.opens[k] or 0) + 1
            P.nopen = P.nopen + 1
        end
        return real_open(path, ...)
    end
    local Screen = require("device").screen
    for _i, mode in ipairs({ "Full", "Partial", "FlashPartial", "UI", "FlashUI", "Fast", "A2" }) do
        local name = "refresh" .. mode .. "Imp"
        local orig = Screen[name]
        if orig then
            Screen[name] = function(self, x, y, w, h, ...)
                if P.label then
                    local area = (w or Screen:getWidth()) * (h or Screen:getHeight())
                    P.refs[#P.refs + 1] = string.format("%s %d%%", mode, math.floor(area * 100 / (Screen:getWidth() * Screen:getHeight()) + 0.5))
                end
                return orig(self, x, y, w, h, ...)
            end
        end
    end
    E.say("instrumented")
end

local function begin(label)
    add({ fn = function(E)
        wrapIO(E)
        P.forks, P.opens, P.nopen, P.refs = {}, {}, 0, {}
        P.samples, P.total = {}, 0
        P.label = label
        P.cpu0 = os.clock()
        P.t0 = E.now()
        P.refreshes0 = E.refreshes
        E.last_refresh_t = nil
        debug.sethook(sample, "", 2000)
    end, after = 0.05 })
end

local function finish(label, idle_s)
    add({ fn = function(E)
        debug.sethook()
        P.label = nil
        local cpu = os.clock() - P.cpu0
        local wall = E.last_refresh_t and (E.last_refresh_t - P.t0) or -1
        local list = {}
        for k, v in pairs(P.samples) do list[#list + 1] = { k, v } end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        E.say(string.format("SPEED %-28s cpu %.2f s  last refresh after %.2f s  refreshes %d  samples %d",
            label, cpu, wall, E.refreshes - P.refreshes0, P.total or 0))
        for i = 1, math.min(6, #list) do
            E.say(string.format("   %3d%%  %s", math.floor(list[i][2] * 100 / math.max(1, P.total) + 0.5), list[i][1]))
        end
        E.say("   refreshes: " .. table.concat(P.refs, ", "))
        for _i, f in ipairs(P.forks) do E.say("   fork: " .. f) end
        local ol = {}
        for k, v in pairs(P.opens) do ol[#ol + 1] = { k, v } end
        table.sort(ol, function(a, b) return a[2] > b[2] end)
        local top = {}
        for i = 1, math.min(5, #ol) do top[#top + 1] = ol[i][1] .. " x" .. ol[i][2] end
        E.say("   files opened: " .. P.nopen .. (#top > 0 and (" (" .. table.concat(top, "; ") .. ")") or ""))
        P.results[#P.results + 1] = { label, cpu, wall }
    end, after = idle_s or 0.5 })
end

local function step(label, k, wait)
    begin(label)
    key(k, wait or 6)
    finish(label)
end

for round = 1, 2 do
    local r = " (" .. round .. ")"
    begin("idle 6 s" .. r); add({ wait = 6 }); finish("idle 6 s" .. r)
    step("Home: Down" .. r, "Down", 4)
    step("Home: Down" .. r, "Down", 4)
    step("Home: Up" .. r, "Up", 4)
    step("Home: Up" .. r, "Up", 4)
    step("Downloads (X)" .. r, "X", 8)
    step("Downloads: Down" .. r, "Down", 4)
    step("Grimmory (C)" .. r, "C", 10)
    step("Grimmory: Down" .. r, "Down", 4)
    step("Notes (V)" .. r, "V", 8)
    key("Back", 4)
    step("Calendar (B)" .. r, "B", 8)
    key("Back", 4)
    step("Home (Z)" .. r, "Z", 8)
    step("Home menu (Menu)" .. r, "Menu", 6)
    step("Home menu: Down" .. r, "Down", 4)
    key("Back", 4)
    step("Settings (Menu, U)" .. r, "Menu", 4)
    step("Settings open" .. r, "U", 8)
    step("Settings: Down" .. r, "Down", 4)
    step("Settings: Press" .. r, "Press", 6)
    step("Settings: Back" .. r, "Back", 5)
    step("Settings: Home key" .. r, "Home", 8)
end
add({ fn = function(E)
    E.say("SPEED summary (cpu s / to last refresh s):")
    for _i, x in ipairs(P.results) do E.say(string.format("SPEED  %-30s %6.2f %6.2f", x[1], x[2], x[3])) end
end, after = 1 })
return s
