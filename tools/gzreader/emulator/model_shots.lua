-- The landing page's screenshots for one model (docs/index.html's model
-- picker; docs/screenshots/models/<model>/). The same screens on every model,
-- reached through GZreader's own calls rather than keys or taps, so one tour
-- runs on keyboard Kindles, touch Kindles, the Scribe, Kobos and Nooks:
--   home      Home with the book being read
--   reading   a page of Persuasion
--   panel     the quick panel in the book
--   catalog   the Catalog's Books page
--   notes     the Notes tab (Memos)
--   settings  Settings
--   drawing   (touch and pen models) a drawing with a house and the sun
-- Needs the demo servers: demo/demo_grimmory.py on 18080, demo/demo_plex.py
-- on 18090, demo/mock_memos.py --sample on 18091; GZ_SHOTS_LIB: the library
-- from demo/make_library.py (books copied in from it).
--   tools/gzreader/emulator/model_shots.sh <tree>/koreader <library dir> <out>
-- runs it on every model and writes the PNGs where the page wants them.
-- Each shot's name goes to <out>/shots.txt as it's taken.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local LIB = os.getenv("GZ_SHOTS_LIB")
local MODEL = os.getenv("GZ_EMU_MODEL") or "k3"
local function UIM() return require("ui/uimanager") end
local function fm() return require("apps/filemanager/filemanager").instance end
local function plugin() return fm() and fm().gzreader end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function closeTop(names)
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if not names or names[w.name] then UIM():close(w) end
    end
end
-- everything above Home closed (the file manager and Home stay)
local function closeAbove()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name ~= "home" and w ~= fm() then UIM():close(w) end
    end
end
local taken = {}
local function shot(name, after)
    add({ shot = name, after = after or 1 })
    add({ fn = function(E)
        taken[#taken + 1] = name
        local f = io.open(E.out .. "/shots.txt", "w")
        if f then f:write(table.concat(taken, "\n") .. "\n"); f:close() end
    end })
end
local function home_dir() return G_reader_settings:readSetting("home_dir") or "/mnt/us/GZreader" end

-- past the setup guide, signed in to the demo servers, books copied in
add({ fn = function(E)
    closeTop({ ["setup guide"] = true, ["QR code screen"] = true })
    local p = plugin()
    E.say("model", MODEL, "login", tostring(p.api:login("http://127.0.0.1:18080", "reader", "demo")))
    local Plex = require("gzreader_plex")
    Plex.TV = "http://127.0.0.1:18090"
    p.store.plex = p.store.plex or {}
    p.store.plex.token, p.store.plex.username = "plex-token", "Reader"
    pcall(function() return Plex:new(p.store.plex):connect("plex-token", "srv1") end)
    p.store.memos = { server = "http://127.0.0.1:18091", token = "memos-test-token", prefix = "/api/v1", user = "Reader" }
    if p.saveStore then p:saveStore() end
    if LIB then
        for _i, id in ipairs({ 4, 1, 6, 2, 9, 3 }) do
            os.execute(string.format("cp '%s/%d.epub' '%s/' 2>/dev/null", LIB, id, home_dir()))
        end
        E.say("books copied to", home_dir())
    end
end, after = 8 })
-- a book open, a few pages in (Persuasion, 4.epub)
add({ fn = function() require("apps/reader/readerui"):showReader(home_dir() .. "/4.epub") end, after = 30 })
add({ fn = function()
    local Event = require("ui/event")
    local r = require("apps/reader/readerui").instance
    if r then r:handleEvent(Event:new("GotoViewRel", 2)) end
end, after = 5 })
shot("reading", 2)
add({ fn = function() require("gzreader_panel").show(plugin() or require("apps/reader/readerui").instance) end, after = 6 })
shot("panel")
add({ fn = function() closeTop({ ["gzreader quick panel"] = true }) end, after = 3 })
add({ fn = function() local r = require("apps/reader/readerui").instance; if r then r:onHome() end end, after = 14 })
add({ fn = function() closeAbove() end, after = 4 })
shot("home", 2)
-- the Catalog's Books page
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 16 })
shot("catalog", 2)
add({ fn = function()
    local b = require("gzreader_browser").current
    if b and b.menu then UIM():close(b.menu) end
    closeAbove()
end, after = 5 })
-- the Notes tab
-- (the Kindle 2 and DX have no Wi-Fi: their Catalog is the sync's copy, or the
-- way to sync with a computer when there's none yet, and their notes come with
-- a sync: no Notes shot there)
local function noWifi() return require("gzreader_net").usb end
add({ fn = function(E)
    E.no_wifi = noWifi() and true or false
    if not E.no_wifi then require("gzreader_notes").show(plugin()) end
end, after = 12 })
add({ fn = function(E)
    if E.no_wifi then return end
    E.shot("notes")
    taken[#taken + 1] = "notes"
end, after = 1 })
add({ fn = function() closeAbove() end, after = 4 })
-- Settings
add({ fn = function() require("gzreader_homemenu").settings() end, after = 8 })
shot("settings", 2)
add({ fn = function() closeAbove() end, after = 4 })
-- a drawing, on models with touch or a pen
add({ fn = function(E)
    local Device = require("device")
    E.can_draw = Device:isTouchDevice() and true or false
    E.say("drawing:", E.can_draw and "yes" or "no (no touch screen)")
    if E.can_draw then require("gzreader_notes").draw(plugin()) end
end, after = 6 })
-- a new drawing asks for its paper first ("Choose a template"): Create, on Blank
add({ fn = function(E)
    local w = top()
    if E.can_draw and w and w.name == "gz_paperlist" and w.pick then w:pick(w:chosenIndex()) end
end, after = 6 })
-- (each stroke its own step: a stroke's events are timed from when it's sent)
local function stroke(pts)
    add({ fn = function(E)
        if not E.can_draw then return end
        local Device = require("device")
        local W, H = Device.screen:getWidth(), Device.screen:getHeight()
        -- (the Scribe and the Kobo Elipsa draw with the pen only)
        local pen = Device.input.wacom_protocol or MODEL == "condor"
        local px = {}
        for i, p in ipairs(pts) do px[i] = { math.floor(W * p[1]), math.floor(H * p[2]) } end
        if pen then E.pen(px, 0.5) else E.finger(px, 0.5) end
    end, after = 2.5 })
end
stroke({ { 0.30, 0.55 }, { 0.30, 0.78 }, { 0.62, 0.78 }, { 0.62, 0.55 } }) -- walls
stroke({ { 0.27, 0.56 }, { 0.46, 0.40 }, { 0.65, 0.56 } })                 -- roof
stroke({ { 0.42, 0.78 }, { 0.42, 0.67 }, { 0.50, 0.67 }, { 0.50, 0.78 } }) -- door
local sun = {}
for k = 0, 16 do
    local a = k / 16 * 2 * math.pi
    sun[#sun + 1] = { 0.78 + 0.07 * math.cos(a), 0.25 + 0.052 * math.sin(a) }
end
stroke(sun)
add({ wait = 3 })
add({ fn = function(E) if E.can_draw then E.shot("drawing"); taken[#taken + 1] = "drawing" end end, after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/shots.txt", "w")
    if f then f:write(table.concat(taken, "\n") .. "\n"); f:close() end
end })
return s
