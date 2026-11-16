-- The pen's pressure and tilt in the Notes tab's drawing screen, on a Kindle
-- Scribe (GZ_EMU_MODEL=scribe): KOReader's input keeps them with the pen's
-- slot (gz_pressure, gz_tilt_x), the stroke is as wide as it's pressed and
-- wider with the pen laid over, the drawing has memos' pressures, and
-- "Pressure and tilt" in the pen's choices turns it off.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh pen_pressure.lua <out>
-- Checks go to <out>/pen-pressure-checks.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local W, H = 1860, 2480
-- a line from (x1, y) to (x2, y): pressure from p1 to p2 (of 4095), tilt from t1 to t2 degrees
local function line(y, p1, p2, t1, t2)
    local pts = {}
    for i = 0, 12 do
        local f = i / 12
        pts[#pts + 1] = { W * (0.3 + 0.5 * f), H * y, p1 + (p2 - p1) * f, t1 and (t1 + (t2 - t1) * f) or nil }
    end
    return pts
end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_pressure")
    G_reader_settings:delSetting("gzreader_pen_range")
    G_reader_settings:saveSetting("gzreader_drawing_paper", "blank")
    require("gzreader_sketch").range = { p_seen = 0, t_seen = 0, n = 0 }
    require("gzreader_drawscreen").show{ title = "Pressure", on_done = function(res) s.pages = res end }
end, after = 8 })
add({ fn = function(E)
    local d = screen()
    check(d and d.pen_only and d.pressure_on, "a Kindle with a pen: the drawing screen, pressure and tilt on")
    E.pen(line(0.25, 300, 4000), 0.5)
end, after = 4 })
add({ fn = function(E)
    local st = screen().sketch:live()[1]
    local n = st and #st.points or 0
    check(st and n >= 8 and st.points[1][3] and st.points[1][3] < 0.2 and st.points[n][3] > 0.8,
        "a stroke pressed harder and harder: its points' weights rise (" .. tostring(st and st.points[1][3]) .. " to " .. tostring(st and st.points[n][3]) .. ")")
    local tev = require("device").input.ev_slots[require("device").input.pen_slot]
    check(tev and tev.gz_pressure ~= nil, "KOReader's input keeps the pen's pressure with its slot")
    E.pen(line(0.4, 2000, 2000, 0, 58), 0.5)
end, after = 4 })
add({ fn = function(E)
    local st = screen().sketch:live()[2]
    local n = st and #st.points or 0
    check(st and st.points[n][3] > st.points[1][3] + 0.25, "the same pressure with the pen laid over more and more: wider towards the end")
    E.penTap(button("pen"))
end, after = 3 })
add({ shot = "1-pressure-on", after = 1 })
add({ fn = function(E)
    check(button("pressure") ~= nil, "the pen's choices have Pressure and tilt")
    E.penTap(button("pressure"))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d.pressure_on == false and G_reader_settings:isFalse("gzreader_drawing_pressure") and d.sketch.pressure_on == false,
        "a tap turns it off (kept for next time)")
    E.penTap(button("w2"))
end, after = 3 })
add({ fn = function(E) E.pen(line(0.55, 300, 4000), 0.5) end, after = 4 })
add({ shot = "2-three-strokes", after = 1 })
add({ fn = function(E)
    local d = screen()
    local st = d.sketch:live()[3]
    check(st and st.points[1][3] == nil, "off: an even line of the chosen thickness")
    -- what was painted: the first stroke is wider at its end than at its start, the third the same all along
    local c = d.canvas
    local function thickness(x, y)
        local n = 0
        for dy = -60, 60 do
            local px, py = math.floor(x) - c.x, math.floor(y) + dy - c.y
            if d.ink_bb:getPixel(px, py):getColor8().a < 128 then n = n + 1 end
        end
        return n
    end
    local a1, a2 = thickness(W * 0.34, H * 0.25), thickness(W * 0.76, H * 0.25)
    local c1, c2 = thickness(W * 0.34, H * 0.55), thickness(W * 0.76, H * 0.55)
    check(a2 >= a1 + 2 and c1 == c2,
        "on the page: the pressed stroke goes from " .. a1 .. " to " .. a2 .. " px thick; the even one is " .. c1 .. " and " .. c2)
    E.penTap(button("done"))
end, after = 6 })
add({ fn = function(E)
    local page = s.pages and s.pages[1]
    local Drawing = require("gzreader_drawing")
    local scene = page and page.path and Drawing.readFile(page.path)
    local els = {}
    for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "freedraw" then els[#els + 1] = el end end
    check(#els == 3 and els[1].simulatePressure == false and els[1].points[#els[1].points][3] > 0.8 and els[1].points[1][3] < 0.2
        and els[2].simulatePressure == false and els[3].simulatePressure == true,
        "Done: the drawing has the pen's pressures for the first two strokes (memos draws them by pressure), none for the even one")
    local r = G_reader_settings:readSetting("gzreader_pen_range")
    check(type(r) == "table" and r.p_seen == 4000 and r.t_seen == 58, "the pen's range (numbers only) is kept for next time: pressure up to "
        .. tostring(r and r.p_seen) .. ", tilt up to " .. tostring(r and r.t_seen))
    G_reader_settings:delSetting("gzreader_drawing_pressure")
    local f = io.open(E.out .. "/pen-pressure-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
