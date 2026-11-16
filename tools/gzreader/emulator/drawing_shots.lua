-- Screenshots for the README and the wiki: the Notes tab with a drawing
-- (Layout → Full), the drawing note's page, the drawing screen with a house
-- and the sun drawn by finger, and the notepaper picker (pw3).
--   python3 demo/make_sketches.py <PatrickHand-Regular.ttf> demo   (once)
--   python3 -I demo/mock_memos.py 18090 --sample --drawings &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader ./run.sh drawing_shots.lua <out>
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function named(name)
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end
end
local function mid(r) return { r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) } end
local function button(id)
    local d = named("gz_drawscreen")
    for _i, b in ipairs(d and d.buttons or {}) do if b.tool.id == id then return mid(b.rect) end end
end
local function shelf()
    for _i, n in ipairs(N().notes or {}) do if (n.content or ""):match("Shelf sketch") then return n end end
end
-- a line through points given as fractions of the screen
local function line(E, pts)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    local px = {}
    for i, p in ipairs(pts) do px[i] = { math.floor(W * p[1]), math.floor(H * p[2]) } end
    E.finger(px, 0.5)
end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().setView(p, "columns", "two")
    N().setView(p, "display", "full")
    N().show(p)
end, after = 14 })
add({ shot = "drawing-board", after = 1 })
add({ fn = function(E)
    local m = shelf()
    E.say("shelf note:", tostring(m and m.name))
    if m then N().showNote(plugin(), m) end
end, after = 8 })
add({ shot = "drawing-note", after = 1 })
-- a new drawing: a house and the sun, with a finger
add({ fn = function() UIM():close(top()); N().draw(plugin()) end, after = 6 })
add({ fn = function(E)
    line(E, { { 0.30, 0.55 }, { 0.30, 0.78 }, { 0.62, 0.78 }, { 0.62, 0.55 } })   -- walls
end, after = 2 })
add({ fn = function(E) line(E, { { 0.27, 0.56 }, { 0.46, 0.40 }, { 0.65, 0.56 } }) end, after = 2 })  -- roof
add({ fn = function(E) line(E, { { 0.42, 0.78 }, { 0.42, 0.67 }, { 0.50, 0.67 }, { 0.50, 0.78 } }) end, after = 2 })  -- door
add({ fn = function(E)
    local pts = {}
    for k = 0, 16 do
        local a = k / 16 * 2 * math.pi
        pts[#pts + 1] = { 0.78 + 0.07 * math.cos(a), 0.25 + 0.052 * math.sin(a) }
    end
    line(E, pts)
end, after = 2 })
add({ fn = function(E)
    for k = 0, 7 do
        local a = k / 8 * 2 * math.pi
        line(E, { { 0.78 + 0.095 * math.cos(a), 0.25 + 0.07 * math.sin(a) }, { 0.78 + 0.13 * math.cos(a), 0.25 + 0.097 * math.sin(a) } })
    end
end, after = 3 })
add({ fn = function(E) line(E, { { 0.12, 0.79 }, { 0.88, 0.79 } }) end, after = 3 })  -- the ground
add({ shot = "drawing-screen", after = 1 })
add({ fn = function(E) local b = button("paper"); if b then E.tap(b) end end, after = 5 })
add({ shot = "drawing-paper", after = 1 })
return s
