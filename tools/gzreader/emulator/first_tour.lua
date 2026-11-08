-- The tours after the setup guide on a touch Kindle (GZ_EMU_MODEL=kt, pw3,
-- nst): GZreader's quick panel tour at Home (gzreader_tour.lua: ZenOS's menu
-- tour, as "Get Started" starts it), then the first book's page browser tour.
-- Screenshots each step (h01…, t01…); <out>/stack.txt has the windows open at
-- each step, <out>/first_tour.txt one "ok …"/"FAIL …" line per check.
--   GZ_EMU_BOOK=book.epub GZ_EMU_MODEL=pw3 run.sh tools/gzreader/emulator/first_tour.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function names()
    local out = {}
    for i, w in ipairs(UIM()._window_stack) do out[#out + 1] = i .. ":" .. tostring(w.widget.name or w.widget.title or (w.widget.steps and "coachmark") or "?") end
    return table.concat(out, " | ")
end
local function log(E, what) local f = io.open(E.out .. "/stack.txt", "a"); f:write(what, "  ", names(), "\n"); f:close() end
add({ fn = function(E)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    -- what "Get Started" leaves: both tours pending
    local fm = require("apps/filemanager/filemanager").instance
    local z = fm.zenos
    z.config._meta.quickstart_menu_tour_pending = true
    z.config._meta.quickstart_reader_tour_pending = true
    z:saveConfig()
    require("common/quickstart/menu_tour").start(z)
    log(E, "home")
end, after = 3 })
for i = 1, 4 do
    add({ fn = function(E) log(E, "home step " .. i) end, after = 0.5 })
    add({ shot = string.format("h%02d", i), after = 1 })
    add({ fn = function(E)
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        local st = UIM()._window_stack
        local top = st[#st] and st[#st].widget
        if top and top.steps then E.tap(function() return W / 2, H * 0.97 end) end
    end, after = 3 })
end
add({ fn = function(E)
    log(E, "home+4s")
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/tour.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/tour.epub")
end, after = 12 })
for i = 1, 8 do
    add({ fn = function(E) log(E, "step " .. i) end, after = 0.5 })
    add({ shot = string.format("t%02d", i), after = 1 })
    add({ fn = function(E)
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        local st = UIM()._window_stack
        local top = st[#st] and st[#st].widget
        if top and top.steps then
            local step = top.steps[top._step or 1]
            if step and step.swipe_up then E.swipe(W / 2, H - 20, W / 2, H / 2)
            else E.tap(function() return W / 2, H * 0.97 end) end
        end
    end, after = 4 })
end
add({ fn = function(E)
    log(E, "end")
    local st, panel, browser = UIM()._window_stack, false, false
    for _i, w in ipairs(st) do
        if w.widget.name == "gzreader quick panel" then panel = true end
        if (w.widget.name or w.widget.title) == "Page browser" then browser = true end
    end
    local meta = require("apps/reader/readerui").instance.zenos.config._meta
    local f = io.open(E.out .. "/first_tour.txt", "w")
    if require("device"):isTouchDevice() then
        f:write((not panel and browser and "ok   " or "FAIL ") .. "the page browser tour ends on the page browser, the quick panel closed\n")
    else
        -- (keyboard Kindles: no touch tours; the Menu key opens the panel)
        f:write((not panel and not browser and "ok   " or "FAIL ") .. "keyboard Kindle: no tour, nothing opened over the book\n")
    end
    f:write((meta.quickstart_menu_tour_pending == false and meta.quickstart_reader_tour_pending == false and "ok   " or "FAIL ")
        .. "both tours done\n")
    f:close()
end, after = 1 })
add({ shot = "t99-end" })
return s
