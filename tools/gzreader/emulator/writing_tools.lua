-- The drawing screen's writing tools (the Kindle Scribe's: pen, pencil,
-- fountain pen, highlighter): the pen's panel shows them; each is chosen by
-- a tap with the pen and draws its way (the fountain pen from thin to wide
-- with pressure, the pencil grey, the highlighter broad and light, under the
-- ink: a highlighter across black ink leaves it black); the toolbar's pen
-- shows the tool in hand; the choice is kept for next time.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh writing_tools.lua <out>
-- (pw3 too: fingers, no pressure). No Memos needed. Checks go to
-- <out>/writing-tools-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function tap(E, id) local p = button(id); if PEN then E.penTap(p) else E.tap(p) end end
-- a line across the page at `fy`: light at first, pressed hard after
local function line(E, fy, fx0, fx1)
    local pts = {}
    for i = 0, 10 do
        local p = pt(fx0 + (fx1 - fx0) * i / 10, fy)
        p[3] = i < 5 and 500 or 4000
        pts[#pts + 1] = p
    end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end
local function last() local l = screen().sketch:live(); return l[#l] end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_writing")
    require("gzreader_drawscreen").show{ title = "Tools", on_done = function() end, on_cancel = function() end }
end, after = 3 })
add({ fn = function(E)
    check(screen() and screen().writing == "pen", "the drawing screen: the pen in hand (as before)")
    tap(E, "pen") -- (the pen again: its panel)
end, after = 2 })
add({ shot = "1-pen-panel", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local ids = {}
    for _i, b in ipairs(d.buttons) do if b.tool.writing then ids[#ids + 1] = b.tool.writing end end
    check(d.flyout == "pen" and table.concat(ids, ",") == "pen,pencil,fountain,highlighter",
        "the pen's panel: Pen, Pencil, Fountain pen, Highlighter (" .. table.concat(ids, ",") .. ")")
    tap(E, "t-fountain")
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.writing == "fountain" and d.flyout == "pen" and G_reader_settings:readSetting("gzreader_drawing_writing") == "fountain",
        "Fountain pen chosen (the panel stays open for a thickness; kept for next time)")
    d:setFlyout(nil)
    line(E, 0.3, 0.2, 0.8)
end, after = 3 })
add({ fn = function(E)
    local st = last()
    check(st and st.kind == "fountain", "…it draws a fountain pen stroke")
    if PEN then
        local sk = screen().sketch
        local r = sk:radius(st.width)
        local light = require("gzreader_sketch").toolRadius("fountain", r, st.points[2][3])
        local hard = require("gzreader_sketch").toolRadius("fountain", r, st.points[#st.points][3])
        check(st.points[2][3] and hard > 2 * light, "…thin where it was light, wide where it was pressed (" .. light .. " to " .. hard .. " px)")
    end
    tap(E, "pen")
end, after = 2 })
add({ fn = function(E) tap(E, "t-pencil") end, after = 2 })
add({ fn = function(E)
    screen():setFlyout(nil)
    line(E, 0.45, 0.2, 0.8)
end, after = 3 })
add({ fn = function(E)
    local st = last()
    local d = screen()
    local p = st and st.points[3]
    local g = p and d.canvas_bb:getPixel(math.floor(p[1]), math.floor(p[2])):getColor8().a
    check(st and st.kind == "pencil" and g and g > 0 and g < 0xC0, "Pencil: a grey line (" .. tostring(g) .. ")")
    -- a pen line straight down, for the highlighter to cross
    tap(E, "pen")
end, after = 2 })
add({ fn = function(E) tap(E, "t-pen") end, after = 2 })
add({ fn = function(E)
    screen():setFlyout(nil)
    local pts = {}
    for i = 0, 8 do pts[#pts + 1] = pt(0.5, 0.55 + 0.03 * i) end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end, after = 3 })
add({ fn = function(E) tap(E, "pen") end, after = 2 })
add({ fn = function(E) tap(E, "t-highlighter") end, after = 2 })
add({ fn = function(E)
    screen():setFlyout(nil)
    line(E, 0.65, 0.3, 0.7)
end, after = 3 })
add({ shot = "2-tools", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local st = last()
    local c = d.sketch.canvas
    -- where the highlighter crossed the pen's line: still black; beside it: light grey
    local x, y = pt(0.5, 0.65)[1] - c.x, pt(0.5, 0.65)[2] - c.y
    local cross = d.canvas_bb:getPixel(x, y):getColor8().a
    local beside = d.canvas_bb:getPixel(pt(0.4, 0.65)[1] - c.x, y):getColor8().a
    check(st and st.kind == "highlighter" and beside > 0x80 and beside < 0xF0,
        "Highlighter: a broad light grey band (" .. beside .. ")")
    check(cross < 0x30, "…across the pen's line, the ink stays black under it (" .. cross .. ")")
    local f = io.open(E.out .. "/writing-tools-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
