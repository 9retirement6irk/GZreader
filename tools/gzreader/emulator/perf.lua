-- How much CPU GZreader's everyday work takes, for CI (ci-test.sh): a first
-- start up to Home, opening a book (GZ_EMU_BOOK), 20 page turns, back to
-- Home, the quick panel three times, ten moves of the 5-way on Home.
-- Each phase's CPU time (this process only: background jobs are their own
-- processes) goes to <out>/perf.json with a calibration: a fixed piece of
-- Lua timed on the same machine, so perf_check.py can compare runs made on
-- faster or slower CI machines against perf_baseline.json.
--
--   GZ_EMU_BOOK=book.epub run.sh perf.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local P = { phases = {}, order = {} }

local function cpu(E) return os.clock() - E.clock0 end
local function begin(name) add({ fn = function(E) P.cur = { name = name, c0 = cpu(E), t0 = E.now() } end, after = 0.1 }) end
local function stop() add({ fn = function(E)
    local c = P.cur
    P.phases[c.name] = { cpu = cpu(E) - c.c0, wall = E.now() - c.t0 }
    P.order[#P.order + 1] = c.name
    E.say(string.format("PERF %s: CPU %.2f s (%.1f s)", c.name, P.phases[c.name].cpu, P.phases[c.name].wall))
end, after = 0.5 }) end

--- A fixed piece of work (tables, strings, closures, as UI code does), timed
--- three times: its median is this machine's speed.
local function calibrate()
    local runs = {}
    for r = 1, 3 do
        local t0 = os.clock()
        local keep = {}
        for i = 1, 150000 do
            local t = { i, tostring(i), name = "item" .. (i % 97) }
            keep[i % 256 + 1] = t
            local f = function() return t.name:upper() end
            if i % 3 == 0 then keep[(i * 7) % 256 + 1] = f() end
        end
        local parts = {}
        for i = 1, 20000 do parts[#parts + 1] = string.format("%05d:%s", i, keep[i % 256 + 1] and "x" or "y") end
        local _ = table.concat(parts, ",")
        runs[r] = os.clock() - t0
    end
    table.sort(runs)
    return runs[2]
end

-- 1. the first start (16 s: up to the setup guide), then Home (the guide closed, as keeps.lua does)
add({ fn = function(E)
    P.phases.startup = { cpu = cpu(E), wall = E.now() - E.start }
    P.order[#P.order + 1] = "startup"
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    E.say(string.format("PERF startup: CPU %.2f s (%.1f s)", P.phases.startup.cpu, P.phases.startup.wall))
end, after = 8 })

-- 2. a book opens
begin("open a book")
add({ fn = function()
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/perf.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/perf.epub")
end, after = 1 })
add({ wait_for = function()
    local ui = require("apps/reader/readerui").instance
    return ui and ui.document and ui.document:getCurrentPage() ~= nil
end, timeout = 90, after = 8 })
stop()

-- 3. page turns (a tap on the right where there's no page key)
begin("20 page turns")
for _i = 1, 20 do
    add({ fn = function(E)
        if not pcall(E.key, "RPgFwd") then
            local Screen = require("device").screen
            E.tap({ Screen:getWidth() * 0.9, Screen:getHeight() / 2 })
        end
    end, after = 2 })
end
stop()

-- 4. back to Home
begin("close the book")
add({ fn = function(E)
    if not pcall(E.key, "Home") then UIM():sendEvent(require("ui/event"):new("Home")) end
end, after = 10 })
stop()

-- 5. the quick panel, three times (the Menu key; a swipe down from the top on touch models)
begin("quick panel x3")
for _i = 1, 3 do
    add({ fn = function(E)
        if not pcall(E.key, "Menu") then
            local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
            E.swipe(W / 2, 3, W / 2, H / 2)
        end
    end, after = 3 })
    add({ fn = function(E) if not pcall(E.key, "Back") then local st = UIM()._window_stack; UIM():close(st[#st].widget) end end, after = 3 })
end
stop()

-- 6. moving around Home with the 5-way
begin("10 moves on Home")
for i = 1, 10 do add({ fn = function(E) pcall(E.key, i % 2 == 0 and "Left" or "Right") end, after = 1.5 }) end
stop()

add({ fn = function(E)
    collectgarbage(); collectgarbage()
    local n = 0
    for _k in pairs(package.loaded) do n = n + 1 end
    local out = { model = E.model, calibration = calibrate(), lua_mb = collectgarbage("count") / 1024,
        modules = n, phases = P.phases, order = P.order }
    E.say(string.format("PERF calibration %.3f s, Lua memory %.1f MB, modules %d", out.calibration, out.lua_mb, n))
    local f = io.open(E.out .. "/perf.json", "w")
    f:write(require("json").encode(out), "\n")
    f:close()
end, after = 1 })
return s
