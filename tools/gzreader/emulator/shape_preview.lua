-- The shape tool shows the shape while it's dragged out (its outline
-- follows the pen), not only once the pen lifts.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh shape_preview.lua <out>   (pw3: a finger)
-- No Memos needed. Checks go to <out>/shape-preview-checks.txt; shots 1-dragging, 2-lifted.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local PEN = (os.getenv("GZ_EMU_MODEL") or "scribe") == "scribe"
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
--- How many black pixels the screen has in the rectangle (fractions of the screen).
local function black(fx0, fy0, fx1, fy1)
    local bb = require("device").screen.bb
    local n = 0
    for y = math.floor(H * fy0), math.floor(H * fy1), 2 do
        for x = math.floor(W * fx0), math.floor(W * fx1), 2 do
            if bb:getPixel(x, y):getColor8().a < 64 then n = n + 1 end
        end
    end
    return n
end
add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    require("gzreader_drawscreen").show{ title = "Shapes", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    d.sketch.tool, d.sketch.shape = "shape", "circle"
    d.tool = "shape"
    E.before = black(0.2, 0.25, 0.75, 0.65)
    -- the pen down and dragged, held there (not lifted): the frames are sent by hand
    local sk, t0 = d.sketch, os.time()
    local function at(fx, fy, dt)
        local frame = { { slot = sk.pen_slot or 0, id = 7, x = math.floor(W * fx), y = math.floor(H * fy), tool = PEN and require("gzreader_sketch").TOOL_PEN or nil } }
        d:apply(sk:frame(frame, t0 + dt))
    end
    at(0.3, 0.3, 0)
    at(0.4, 0.4, 0.2)
    at(0.5, 0.5, 0.4)
    at(0.65, 0.6, 0.6)
end, after = 3 })
add({ shot = "1-dragging", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local p = d.sketch.shape_preview
    local now = black(0.2, 0.25, 0.75, 0.65)
    check(p ~= nil and #p.points > 20 and #d.sketch:live() == 0, "the pen still down: the circle's outline is kept to show, nothing on the page yet")
    check(now > E.before + 100, "…and it's on the screen (" .. (now - E.before) .. " dark pixels more)")
    check((d.shape_refreshes or 0) == 3, "…shown at each step of the pen (" .. tostring(d.shape_refreshes) .. " refreshes of its part of the screen)")
    E.dragging = now
    d:apply(d.sketch:frame({ { slot = d.sketch.pen_slot or 0, id = -1 } }, os.time() + 1))
end, after = 3 })
add({ shot = "2-lifted", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local now = black(0.2, 0.25, 0.75, 0.65)
    check(d.sketch.shape_preview == nil and #d.sketch:live() == 1, "lifted: the circle is on the page, the outline put away")
    check(math.abs(now - E.dragging) < E.dragging * 0.15, "…and the screen shows it where the outline was (" .. now .. " dark pixels, " .. E.dragging .. " while dragging)")
    local f = io.open(E.out .. "/shape-preview-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
