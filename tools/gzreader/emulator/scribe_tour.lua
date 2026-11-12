-- GZreader on a Kindle Scribe (GZ_EMU_MODEL=scribe: 1860 × 2480 at 300 dpi, a
-- touch screen and a pen), for screenshots and a first look at the pen: the
-- demo library (demo/demo_grimmory.py on 18080, demo/demo_plex.py on 18090,
-- a library from demo/make_library.py with audio.json), a few of its books
-- copied in, one open, then Home, the Downloads tab, the Catalog, a book's
-- page, the quick panel, Settings and the Notes tab, by touch.
-- Then the pen: a pen tap opens a quick panel tile, as a finger's would; and
-- with KOReader's Input:registerStylusCallback (what a drawing screen would
-- use) a pen stroke reaches the callback, tagged pen, and no gesture; the
-- eraser end comes tagged eraser. "[emu] pen:" lines say what arrived.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh scribe_tour.lua <out>
-- GZ_SCRIBE_LIB: the demo library's folder (books copied from it).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local LIB = os.getenv("GZ_SCRIBE_LIB")
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function closeTop(names)
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if not names or names[w.name] then UIM():close(w) end
    end
end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
-- close everything above Home (the file manager and Home stay)
local function closeAbove()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name ~= "home" and w ~= fm() then UIM():close(w) end
    end
end

-- KOReader takes it for a Scribe: its device class, MTK display, pen protocol
add({ fn = function(E)
    local Device = require("device")
    local Screen = Device.screen
    check(Device.model == "KindleScribe" and Device:isMTK() and Device:isTouchDevice(),
        "a Kindle Scribe to KOReader (" .. tostring(Device.model) .. ", MTK, touch)")
    check(Screen:getWidth() == 1860 and Screen:getHeight() == 2480 and Screen:getDPI() == 300,
        "its screen: 1860 × 2480 at 300 dpi (" .. Screen:getWidth() .. " × " .. Screen:getHeight() .. " at " .. Screen:getDPI() .. ")")
    check(Device.input.wacom_protocol == true and E.mtk_fast == true, "the pen's protocol on, the display's fast mode on")
end })
-- past the setup guide, signed in to the demo Grimmory and Plex, books copied in
add({ fn = function(E)
    closeTop({ ["setup guide"] = true, ["QR code screen"] = true })
    E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo")))
    local Plex = require("gzreader_plex")
    Plex.TV = "http://127.0.0.1:18090"
    local p = plugin()
    p.store.plex = p.store.plex or {}
    p.store.plex.token = "plex-token"
    p.store.plex.username = "Reader"
    pcall(function() return Plex:new(p.store.plex):connect("plex-token", "srv1") end)
    if p.saveStore then p:saveStore() end
    if LIB then
        local home = G_reader_settings:readSetting("home_dir") or "/mnt/us/GZreader"
        for _i, id in ipairs({ 4, 1, 6, 2, 9, 3 }) do
            os.execute(string.format("cp '%s/%d.epub' '%s/' 2>/dev/null", LIB, id, home))
        end
        E.say("books copied to", home)
    end
end, after = 8 })
-- a book open: Persuasion (4.epub), a few pages in
add({ fn = function(E)
    local home = G_reader_settings:readSetting("home_dir") or "/mnt/us/GZreader"
    require("apps/reader/readerui"):showReader(home .. "/4.epub")
end, after = 30 })
add({ swipe = { 1500, 1300, 300, 1300 }, after = 4 })
add({ swipe = { 1500, 1300, 300, 1300 }, after = 4 })
shot("scribe-reading", 2)
add({ fn = function() require("gzreader_panel").show(plugin() or require("apps/reader/readerui").instance) end, after = 6 })
shot("scribe-panel-in-book")
add({ fn = function() closeTop({ ["gzreader quick panel"] = true }) end, after = 3 })
add({ fn = function() require("apps/reader/readerui").instance:onHome() end, after = 14 })
shot("scribe-home", 2)
add({ fn = function(E)
    -- the tab bar's places, for scripted taps (its labels are painted)
    local bb = require("device").screen
    E.say("screen", bb:getWidth(), bb:getHeight())
end })
-- the Catalog: Books, then a book's page
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 16 })
shot("scribe-catalog-books", 2)
add({ fn = function(E)
    local b = require("gzreader_browser").current
    local m = b and b.menu
    for _i, it in ipairs(m and m.item_table or {}) do
        local t = tostring(it.text or (it.text_func and it.text_func()) or "")
        if t:match("^All books") then
            if it.callback then it.callback() else m:onMenuSelect(it) end
            E.say("all books")
            return
        end
    end
end, after = 10 })
shot("scribe-catalog-all-books", 2)
add({ fn = function(E)
    local w = top()
    for _i, it in ipairs(w and w.item_table or {}) do
        local t = tostring(it.text or (it.text_func and it.text_func()) or "")
        if t:match("Moby") then
            if it.callback then it.callback() else w:onMenuSelect(it) end
            E.say("book page")
            return
        end
    end
end, after = 10 })
shot("scribe-book-page", 2)
add({ fn = function()
    closeTop({ ["gzreader book page"] = true })
    local b = require("gzreader_browser").current
    if b and b.menu then UIM():close(b.menu) end
    closeAbove()
end, after = 6 })
-- the tab bar by touch: Downloads, Notes, then Home again (its labels are
-- painted: tapped by place, 1860 × 2480)
add({ tap = { 583, 2356 }, after = 12 })
shot("scribe-downloads", 2)
add({ tap = { 1265, 2356 }, after = 10 })
shot("scribe-notes", 2)
add({ tap = { 233, 2356 }, after = 8 })
-- the quick panel at Home; a pen tap on its Settings tile
add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 6 })
shot("scribe-panel")
add({ fn = function(E)
    local w = top()
    local placed = w and (w.placed or (w.widget and w.widget.placed)) or {}
    for _i, pl in ipairs(placed) do
        local tile = pl.tile or pl
        local label = tostring(tile.label or tile.text or "")
        if label == "Settings" and tile.dimen then
            local d = tile.dimen
            E.say("pen: tapping the Settings tile at", math.floor(d.x + d.w / 2), math.floor(d.y + d.h / 2))
            E.penTap({ d.x + d.w / 2, d.y + d.h / 2 })
            return
        end
    end
    E.say("pen: no Settings tile found; opening Settings directly")
    closeTop({ ["gzreader quick panel"] = true })
    require("gzreader_homemenu").settings()
    E.pen_fallback = true
end, after = 8 })
add({ fn = function(E)
    local w = top()
    E.say("pen: after the pen tap, on top:", tostring(w and (w.name or w.title)), E.pen_fallback and "(opened directly)" or "")
    check(not E.pen_fallback and w and w.name == "zen_settings", "a pen tap works as a finger's: the Settings tile opened Settings")
end })
shot("scribe-settings", 2)
add({ fn = function() closeAbove() end, after = 4 })
-- the pen on its own: KOReader's stylus callback (what a drawing screen would use)
add({ fn = function(E)
    local Device = require("device")
    local input = Device.input
    E.pen_points, E.pen_tools, E.pen_gestures = 0, {}, 0
    local orig_ges = UIM().sendEvent
    E.pen_orig_send = orig_ges
    UIM().sendEvent = function(self, ev, ...)
        if ev and ev.handler == "onGesture" then E.pen_gestures = E.pen_gestures + 1 end
        return orig_ges(self, ev, ...)
    end
    input:registerStylusCallback(function(_input, slot)
        E.pen_points = E.pen_points + 1
        E.pen_tools[tostring(slot.tool)] = true
        E.pen_last = { slot.x, slot.y }
        return true -- (taken: no tap or swipe from it)
    end)
    E.say("pen: stylus callback registered, wacom", tostring(input.wacom_protocol), "pen slot", tostring(input.pen_slot))
end, after = 1 })
add({ pen = { { 400, 900 }, { 600, 950 }, { 800, 1050 }, { 1000, 1000 }, { 1200, 900 }, { 1400, 950 } }, sec = 0.6, after = 3 })
add({ fn = function(E)
    E.say("pen: stroke ->", E.pen_points, "points to the callback, tools", (function()
        local t = {} for k in pairs(E.pen_tools) do t[#t + 1] = k end return table.concat(t, ",") end)(),
        "last", E.pen_last and (math.floor(E.pen_last[1]) .. "," .. math.floor(E.pen_last[2])) or "-",
        "gestures", E.pen_gestures)
    check(E.pen_points >= 6 and E.pen_tools["1"] and E.pen_gestures == 0 and E.pen_last
            and math.floor(E.pen_last[1]) == 1400 and math.floor(E.pen_last[2]) == 950,
        "a pen stroke with a stylus callback: every point to the callback, tagged pen, where it was drawn, and no gesture")
    E.pen_points, E.pen_tools = 0, {}
end })
add({ pen = { { 700, 1500 }, { 900, 1500 } }, sec = 0.3, eraser = true, after = 3 })
add({ fn = function(E)
    E.say("pen: eraser ->", E.pen_points, "points, tools", (function()
        local t = {} for k in pairs(E.pen_tools) do t[#t + 1] = k end return table.concat(t, ",") end)(),
        "gestures", E.pen_gestures)
    check(E.pen_points >= 2 and E.pen_tools["2"] and not E.pen_tools["1"] and E.pen_gestures == 0,
        "the eraser end: tagged eraser, no gesture")
    require("device").input:unregisterStylusCallback()
    UIM().sendEvent = E.pen_orig_send
end })
shot("scribe-home-end", 1)
add({ fn = function(E)
    local f = io.open(E.out .. "/scribe-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end })
return s
