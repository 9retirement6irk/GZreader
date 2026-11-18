-- The lasso (gzreader_lasso.lua; the Kindle Scribe notebook's): a loop
-- around strokes chooses them (a dashed frame, a handle at each corner,
-- Copy / Cut / Delete beside it); dragged from inside they move, from a
-- corner they grow; Copy, then a tap on an empty place offers Paste there;
-- Cut and Undo; saved, the drawing has the strokes where they were put.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh lasso.lua <out>
-- (pw3 too: a finger.) No Memos needed. Checks go to <out>/lasso-checks.txt.
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
local function tapAt(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function draw(E, pts, sec)
    for _i, p in ipairs(pts) do p[3] = 2000 end
    if PEN then E.pen(pts, sec or 0.5) else E.finger(pts, sec or 0.5) end
end
local function line(E, fx0, fy0, fx1, fy1)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = pt(fx0 + (fx1 - fx0) * i / 10, fy0 + (fy1 - fy0) * i / 10) end
    draw(E, pts)
end
--- A loop around the rectangle (fx0, fy0)-(fx1, fy1), slowly (its dashes are drawn as it goes).
local function loop(E, fx0, fy0, fx1, fy1)
    local pts = {}
    local corners = { { fx0, fy0 }, { fx1, fy0 }, { fx1, fy1 }, { fx0, fy1 }, { fx0, fy0 + 0.01 } }
    for k = 1, #corners - 1 do
        for i = 0, 5 do
            pts[#pts + 1] = pt(corners[k][1] + (corners[k + 1][1] - corners[k][1]) * i / 6, corners[k][2] + (corners[k + 1][2] - corners[k][2]) * i / 6)
        end
    end
    pts[#pts + 1] = pt(fx0, fy0 + 0.01)
    draw(E, pts, 1.2)
end
--- A drag of the screen point `from` by (dx, dy) pixels, in steps a moment apart (the frame follows).
local function drag(E, from, dx, dy)
    local pts = {}
    for i = 0, 6 do pts[#pts + 1] = { math.floor(from[1] + dx * i / 6), math.floor(from[2] + dy * i / 6) } end
    draw(E, pts, 1.6)
end
local function box() local d = screen(); return d.sketch:selectionBox() end
local function bytes(bb) return bb and require("ffi").string(bb.data, bb.stride * bb:getHeight()) or "" end
local function exact()
    local d = screen()
    local a1, a2 = bytes(d.canvas_bb), bytes(d.ink_bb)
    d:repaintCanvas()
    return a1 == bytes(d.canvas_bb) and a2 == bytes(d.ink_bb)
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_writing")
    require("gzreader_lasso").clipboard = nil
    require("gzreader_drawscreen").show{ title = "Lasso", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E) screen():setPaper("ruled-medium") end, after = 3 })
-- two strokes close together, one far below
add({ fn = function(E) line(E, 0.35, 0.25, 0.55, 0.25) end, after = 2 })
add({ fn = function(E) line(E, 0.35, 0.29, 0.55, 0.31) end, after = 2 })
add({ fn = function(E) line(E, 0.35, 0.75, 0.6, 0.75) end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 3 and button("lasso") ~= nil, "three strokes; the tools have a lasso (after the eraser)")
    d:repaintCanvas() -- (the page as its strokes draw it: what the comparisons below start from)
    tap(E, "lasso")
end, after = 2 })
add({ fn = function(E)
    check(screen().tool == "lasso" and screen().sketch.tool == "lasso", "the lasso in hand")
    loop(E, 0.3, 0.21, 0.62, 0.35)
end, after = 3 })
add({ shot = "1-chosen", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local sel = d.sketch.selection
    local b = box()
    check(sel and #sel.strokes == 2 and #d.sketch:live() == 3, "a loop around the first two: those two chosen, nothing drawn on the page")
    check(b and button("sel-copy") and button("sel-cut") and button("sel-delete") and d.frames.selmenu ~= nil
        and (d.frames.selmenu.x + d.frames.selmenu.w <= d.canvas.x + b.x0 or d.frames.selmenu.x >= d.canvas.x + b.x1),
        "…a frame around them, and Copy, Cut, Delete beside it (not over it)")
    E.box0 = { x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1 }
    -- dragged from the middle of the frame: down by a fifth of the screen
    drag(E, { d.canvas.x + (b.x0 + b.x1) / 2, d.canvas.y + (b.y0 + b.y1) / 2 }, 60, math.floor(H * 0.2))
end, after = 3 })
add({ shot = "2-moved", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local b = box()
    check(b and math.abs((b.x0 - E.box0.x0) - 60) <= 2 and math.abs((b.y0 - E.box0.y0) - math.floor(H * 0.2)) <= 2 and #d.sketch.selection.strokes == 2,
        "dragged from inside the frame: the two strokes moved with it (60 across, a fifth of the screen down), still chosen")
    check(exact(), "…the page is exactly what drawing all of it again gives (where they were: the paper again; where they are: the strokes)")
    E.box1 = { x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1 }
    -- the bottom right handle dragged out by half the frame's width
    drag(E, { d.canvas.x + b.x1, d.canvas.y + b.y1 }, math.floor((b.x1 - b.x0) / 2), 6)
end, after = 3 })
add({ shot = "3-bigger", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local b = box()
    local pad = 2 * (d.sketch.lasso_pad or 0) -- (the frame has room around the strokes; the strokes are what grow)
    local grew = (b.x1 - b.x0 - pad) / (E.box1.x1 - E.box1.x0 - pad)
    check(grew > 1.35 and grew < 1.75 and math.abs(b.x0 - E.box1.x0) <= 3 and math.abs(b.y0 - E.box1.y0) <= 3,
        "the bottom right handle dragged out: about one and a half times as big, from the top left corner (" .. string.format("%.2f", grew) .. "x)")
    check(exact(), "…exactly as drawing the page again gives")
    tap(E, "sel-copy")
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local clip = require("gzreader_lasso").clipboard
    check(clip and #clip.strokes == 2 and d.sketch.selection == nil and button("sel-copy") == nil, "Copy: the two strokes kept; let go of (as the Kindle's)")
    tapAt(E, pt(0.5, 0.55)) -- (an empty place)
end, after = 3 })
add({ shot = "4-paste-offered", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local p = button("paste")
    check(p ~= nil and d.frames.paste ~= nil and math.abs(p[1] - W * 0.5) < W * 0.1 and p[2] < H * 0.55, "a tap on an empty place: Paste, there")
    tap(E, "paste")
end, after = 3 })
add({ shot = "5-pasted", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local b = box()
    check(#d.sketch:live() == 5 and d.sketch.selection and #d.sketch.selection.strokes == 2 and b
        and math.abs((b.x0 + b.x1) / 2 + d.canvas.x - W * 0.5) < 6 and math.abs((b.y0 + b.y1) / 2 + d.canvas.y - H * 0.55) < 6,
        "Paste: two new strokes, their middle where the tap was, chosen (to move into place)")
    check(exact(), "…exactly as drawing the page again gives")
    tap(E, "sel-cut")
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 3 and d.sketch.selection == nil and exact(), "Cut: the pasted strokes off the page again (and the page exact)")
    tap(E, "undo")
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 5 and exact(), "Undo: they're back")
    -- another tool lets go; and the drawing saved has the moved strokes where they are
    tap(E, "pen")
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.tool == "pen" and d.sketch.selection == nil and button("sel-copy") == nil, "the pen taken again: nothing chosen, no frame")
    local res = d:save()
    local scene = res and require("gzreader_drawing").readFile(res.path)
    local n, lowest = 0, math.huge
    for _i, el in ipairs(scene and scene.elements or {}) do
        if el.type == "freedraw" then n = n + 1; lowest = math.min(lowest, el.y) end
    end
    -- (the first stroke was drawn a quarter of the way down the screen and moved a fifth further)
    local sy = select(2, d.sketch:toScene(0, H * 0.40 - d.canvas.y))
    check(n == 5 and lowest > sy, "saved: five strokes in the drawing, none left where the moved ones were (the topmost at " .. string.format("%.0f", lowest) .. ", below " .. string.format("%.0f", sy) .. ")")
    if res then os.remove(res.path) end
    require("gzreader_lasso").clipboard = nil
    local f = io.open(E.out .. "/lasso-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
