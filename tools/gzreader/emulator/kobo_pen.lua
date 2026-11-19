-- A Kobo with a pen (Elipsa 2E, as KOReader's Kobo_condor): the pen draws
-- with its pressure and a finger doesn't (a hand can rest on the screen),
-- as on the Kindle Scribe; the pen's other end rubs out; the pen / finger
-- button makes a finger draw instead.
--   GZ_EMU_MODEL=condor GZ_EMU_TREE=<a Kobo package's tree>/koreader run.sh kobo_pen.lua <out>
-- Checks go to <out>/kobo-pen-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function line(fy, pressure)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { W * (0.3 + 0.04 * i), H * fy + 20 * math.sin(i), pressure } end
    return pts
end

add({ fn = function(_E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_draw_with_finger")
    G_reader_settings:saveSetting("gzreader_drawing_paper", "blank")
    require("gzreader_drawscreen").show{ on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    local Device = require("device")
    check(Device.model == "Kobo_condor" and d and d.has_pen and d.pen_only and not d.pen_fast,
        "a Kobo Elipsa 2E: a pen device, the pen draws (" .. tostring(Device.model) .. "; not the Scribe's pen mode)")
    check(button("fingers") ~= nil, "…the pen / finger button in the tools")
    E.finger(line(0.25), 0.4)
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 0, "a finger draws nothing (a hand can rest on the screen)")
    E.pen(line(0.35, 3000), 0.4)
end, after = 3 })
add({ shot = "1-pen", after = 0.5 })
add({ fn = function(E)
    local sk = screen().sketch
    local st = sk:live()[1]
    local p = st and st.points[2]
    check(#sk:live() == 1, "the pen draws a stroke")
    check(p and p[3] ~= nil, "…with its pressure, from the panel (ABS_MT_PRESSURE): " .. tostring(p and p[3]))
    -- the pen's other end, across it
    E.pen({ { W * 0.5, H * 0.3 }, { W * 0.5, H * 0.35 }, { W * 0.5, H * 0.4 } }, 0.3, true)
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 0, "the pen's other end rubs out the stroke it crosses")
    E.pen({ button("fingers") }, 0.05)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(not d.pen_only and G_reader_settings:isTrue("gzreader_draw_with_finger"), "the pen / finger button: a finger draws now")
    E.finger(line(0.5), 0.4)
end, after = 3 })
add({ shot = "2-finger", after = 0.5 })
add({ fn = function(E)
    check(#screen().sketch:live() == 1, "…a finger stroke drawn")
    E.pen({ button("fingers") }, 0.05)
end, after = 3 })
add({ fn = function(E)
    check(screen().pen_only, "…and back to the pen")
    local f = io.open(E.out .. "/kobo-pen-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
