-- Tidy handwriting (gzreader_tidy.lua): writing drawn with the pen on a
-- slope, one word bigger and the gaps uneven; chosen with the lasso, then
-- Tidy: the line level, the words even; Undo puts it back.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh tidy.lua <out>
-- Checks go to <out>/tidy-checks.txt.
local s = { start = 14 }
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
local function pen(E, pts, sec)
    for _i, p in ipairs(pts) do p[3] = 2000 end
    E.pen(pts, sec or 0.4)
end
-- a letter: a zigzag `h` tall from x on a baseline that rises 0.12 per pixel
local function letter(E, x, h)
    local y0 = math.floor(H * 0.42 - (x - W * 0.15) * 0.12)
    pen(E, { { x, y0 }, { x + h * 0.3, y0 - h }, { x + h * 0.6, y0 }, { x + h * 0.75, y0 - h * 0.5 } })
end
local function baselines(d)
    local Tidy = require("gzreader_tidy")
    local lo, hi = math.huge, -math.huge
    for _i, st in ipairs(d.sketch:live()) do
        local b = Tidy.box(st.points)
        lo, hi = math.min(lo, b.y1), math.max(hi, b.y1)
    end
    return hi - lo
end
add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_writing")
    require("gzreader_drawscreen").show{ title = "Tidy", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E) screen():setPaper("ruled-medium") end, after = 3 })
-- three words: 3 letters, 3 bigger letters, 2 letters; uneven gaps
local words = { { x = 0.15, n = 3, h = 60 }, { x = 0.38, n = 3, h = 84 }, { x = 0.72, n = 2, h = 60 } }
for _i, w in ipairs(words) do
    for k = 0, w.n - 1 do
        add({ fn = function(E) letter(E, math.floor(W * w.x + k * w.h * 0.9), w.h) end, after = 1 })
    end
end
add({ shot = "tidy-1-written" })
add({ fn = function(E)
    local d = screen()
    E.before = baselines(d)
    E.say("tidy: strokes", #d.sketch:live(), "baselines spread", math.floor(E.before))
    E.penTap(button("lasso"))
end, after = 2 })
add({ fn = function(E)
    -- a loop round all of it
    local x0, x1, y0, y1 = W * 0.1, W * 0.92, H * 0.22, H * 0.48
    local c = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 }, { x0, y0 + 10 } }
    local pts = {}
    for k = 1, #c - 1 do
        for i = 0, 5 do pts[#pts + 1] = { math.floor(c[k][1] + (c[k + 1][1] - c[k][1]) * i / 6), math.floor(c[k][2] + (c[k + 1][2] - c[k][2]) * i / 6) } end
    end
    pen(E, pts, 1.2)
end, after = 3 })
add({ shot = "tidy-2-chosen" })
add({ fn = function(E)
    local d = screen()
    local n = d.sketch.selection and #d.sketch.selection.strokes or 0
    check(n == 8 and button("sel-tidy") ~= nil, "the lasso chose the writing (" .. n .. " strokes); Tidy is beside Copy, Cut, Delete, To text")
    E.penTap(button("sel-tidy"))
end, after = 4 })
add({ shot = "tidy-3-tidied" })
add({ fn = function(E)
    local d = screen()
    local after = baselines(d)
    E.say("tidy: baselines spread after", string.format("%.1f", after))
    check(E.before > 60 and after < 6, ("Tidy: the line level (its bottoms %d px apart, then %.1f)"):format(math.floor(E.before), after))
    local h = d.sketch.history[#d.sketch.history]
    check(h and h.kind == "move", "Tidy: one step to undo")
    E.penTap(button("undo"))
end, after = 3 })
add({ shot = "tidy-4-undone" })
add({ fn = function(E)
    local d = screen()
    local back = baselines(d)
    check(math.abs(back - E.before) < 0.5, "Undo: the writing as it was")
    local f = io.open(E.out .. "/tidy-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 1 })
return s
