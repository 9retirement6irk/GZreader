-- A rubbed-out stroke, an Undo, a Redo: only that part of the page is drawn
-- again and refreshed (DrawScreen:repaintArea), and what's on the page then
-- is exactly what drawing the whole page again gives (compared byte for
-- byte: the page as shown, the ink alone, and the paper's colours), with a
-- pen line, a pencil line and a highlighter crossing each other on ruled paper.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh partial_repaint.lua <out>
-- (pw3 too: a finger.) No Memos needed. Checks go to <out>/partial-repaint-checks.txt.
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
local function stroke(E, x0, y0, x1, y1)
    local pts = {}
    for i = 0, 12 do
        local p = pt(x0 + (x1 - x0) * i / 12, y0 + (y1 - y0) * i / 12)
        p[3] = 1500 + 150 * i
        pts[#pts + 1] = p
    end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end
local function bytes(bb)
    if not bb then return "" end
    return require("ffi").string(bb.data, bb.stride * bb:getHeight())
end
--- The page's three pictures now, as strings.
local function snapshot() local d = screen(); return { bytes(d.canvas_bb), bytes(d.ink_bb), bytes(d.color_bb) } end
--- True when the page is what drawing all of it again gives.
local function exact()
    local d = screen()
    local a = snapshot()
    d:repaintCanvas()
    local b = snapshot()
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3], #a[1]
end
local got, real
local function record()
    got, real = {}, UIM()._refresh
    UIM()._refresh = function(self, mode, region, dither)
        got[#got + 1] = region and (region.w * region.h) or (W * H)
        return real(self, mode, region, dither)
    end
end
local function biggest()
    UIM()._refresh = real
    local m = 0
    for _i, a in ipairs(got) do m = math.max(m, a) end
    return m, #got
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_writing")
    require("gzreader_drawscreen").show{ title = "Partial", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E) screen():setPaper("ruled-medium") end, after = 3 })
-- a pen line across, a second one under it
add({ fn = function(E) stroke(E, 0.3, 0.30, 0.8, 0.34) end, after = 2 })
add({ fn = function(E) stroke(E, 0.3, 0.50, 0.8, 0.46) end, after = 2 })
-- a pencil line down through both
add({ fn = function(E) tap(E, "pen") end, after = 2 })
add({ fn = function(E) tap(E, "t-pencil") end, after = 2 })
add({ fn = function(E) if screen().flyout then tap(E, "pen") end end, after = 2 })
add({ fn = function(E) stroke(E, 0.45, 0.22, 0.5, 0.58) end, after = 2 })
-- a highlighter over the first line
add({ fn = function(E) tap(E, "highlighter") end, after = 2 })
add({ fn = function(E) if screen().flyout then tap(E, "highlighter") end end, after = 2 })
add({ fn = function(E) stroke(E, 0.25, 0.32, 0.85, 0.32) end, after = 3 })
add({ shot = "1-drawn", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local kinds = {}
    for _i, st in ipairs(d.sketch:live()) do kinds[#kinds + 1] = st.kind or "pen" end
    check(table.concat(kinds, ",") == "pen,pen,pencil,highlighter" and d.sketch:paper() == "ruled-medium",
        "on ruled paper: two pen lines, a pencil line through them, a highlighter over the first (" .. table.concat(kinds, ",") .. ")")
    -- (the page as its strokes draw it: ink drawn live with a pen's pressure is a pixel wider or
    -- narrower here and there than the same stroke drawn again, so the comparisons start from this)
    local live_same = exact()
    E.say("live ink the same as drawn again:", tostring(live_same))
    -- the eraser across the second pen line (away from the others' crossing)
    tap(E, "eraser")
end, after = 2 })
add({ fn = function(E) if screen().flyout then tap(E, "eraser") end end, after = 2 })
add({ fn = function(E)
    record()
    local pts = { pt(0.7, 0.44), pt(0.7, 0.47), pt(0.7, 0.50) }
    if PEN then E.pen(pts, 0.3) else E.finger(pts, 0.3) end
end, after = 3 })
add({ shot = "2-rubbed-out", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local big, n = biggest()
    check(#d.sketch:live() == 3, "the eraser across the second pen line: it's gone (" .. #d.sketch:live() .. " strokes left)")
    check(n > 0 and big < 0.5 * W * H, "…only its part of the screen refreshed (at most " .. math.floor(100 * big / (W * H)) .. " % of the screen in a refresh; it was all of it)")
    local same, size = exact()
    check(same and size > 1000, "…and the page is exactly what drawing all of it again gives: the paper's lines back where the line was, the pencil line that crossed it whole")
    record()
    tap(E, "undo")
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local big = biggest()
    check(#d.sketch:live() == 4 and big < 0.5 * W * H, "Undo: the line back, only its part refreshed (" .. math.floor(100 * big / (W * H)) .. " %)")
    check((exact()), "…exactly as drawing the whole page again gives")
    record()
    tap(E, "undo") -- (the highlighter's stroke taken back: under it the pen line and the pencil stay)
end, after = 3 })
add({ shot = "3-highlighter-undone", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local big = biggest()
    check(#d.sketch:live() == 3 and big < 0.5 * W * H, "Undo again: the highlighter gone, only its part refreshed (" .. math.floor(100 * big / (W * H)) .. " %)")
    check((exact()), "…exactly: the pen line it lay over still black, the paper under it clean")
    record()
    tap(E, "redo")
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local big = biggest()
    check(#d.sketch:live() == 4 and big < 0.5 * W * H, "Redo: the highlighter back, only its part refreshed (" .. math.floor(100 * big / (W * H)) .. " %)")
    check((exact()), "…exactly: under the ink, as it was drawn")
    local f = io.open(E.out .. "/partial-repaint-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
