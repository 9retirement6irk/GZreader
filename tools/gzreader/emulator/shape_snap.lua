-- Draw and hold (the Apple Newton's shapes): a rough triangle drawn with the
-- pen and held still at its end becomes a clean one; one lifted at once is
-- left as drawn. The switch is in the Shapes panel.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh shape_snap.lua <out>   (pw3: a finger)
-- Checks go to <out>/shape-snap-checks.txt; shots 1-held, 2-not-held.
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
--- A rough triangle (a wobble on each side), then `hold` more samples still at its end.
local function triangle(fx, fy, size, hold)
    local c = { { fx, fy - size }, { fx + size, fy + size }, { fx - size, fy + size }, { fx + 0.01, fy - size + 0.015 } }
    local pts = {}
    for k = 1, 3 do
        local a, b = c[k], c[k + 1]
        for i = 0, 11 do
            local t = i / 12
            pts[#pts + 1] = { math.floor(W * (a[1] + (b[1] - a[1]) * t)) + (i % 3) * 3, math.floor(H * (a[2] + (b[2] - a[2]) * t)) - (i % 2) * 3, 2000 }
        end
    end
    local last = { math.floor(W * c[4][1]), math.floor(H * c[4][2]), 2000 }
    pts[#pts + 1] = last
    for k = 1, hold do pts[#pts + 1] = { last[1] + (k % 2), last[2], 2000 } end
    return pts
end
local function stroke(E, pts, sec) if PEN then E.pen(pts, sec) else E.finger(pts, sec) end end
add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_snap")
    require("gzreader_drawscreen").show{ title = "Shapes", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E)
    check(screen().snap_shapes and screen().sketch.snap_shapes, "draw and hold: on")
    -- 37 points over 0.8 s, then 37 more still over 0.8 s
    stroke(E, triangle(0.35, 0.35, 0.12, 37), 1.6)
end, after = 4 })
add({ shot = "1-held", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local st = d.sketch:live()[1]
    check(st and #st.points == 4 and (d.sketch.snapped or 0) == 1, "held at its end: a clean triangle (" .. (st and #st.points or 0) .. " points)")
    stroke(E, triangle(0.65, 0.65, 0.12, 0), 0.8)
end, after = 4 })
add({ shot = "2-not-held", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local st = d.sketch:live()[2]
    check(st and #st.points > 20 and (d.sketch.snapped or 0) == 1, "lifted at once: left as drawn (" .. (st and #st.points or 0) .. " points)")
    -- the switch in the Shapes panel
    d:setFlyout("shape")
    local found
    for _i, b in ipairs(d.buttons) do if b.tool.id == "snap" then found = b end end
    check(found and found.tool.switch == true, "the Shapes panel: Draw and hold: clean shapes (on)")
    if found then d:use(found.tool) end
    check(not d.snap_shapes and not d.sketch.snap_shapes and G_reader_settings:isFalse("gzreader_drawing_snap"), "…turned off, and kept")
    G_reader_settings:delSetting("gzreader_drawing_snap")
    local f = io.open(E.out .. "/shape-snap-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
