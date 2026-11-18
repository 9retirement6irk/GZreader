--[[--
The lasso (the Kindle Scribe notebook's; the owner's video IMG_0275,
2026-11-17): a loop drawn around some strokes chooses them. Chosen, they
have a dashed frame with a handle at each corner: drag inside it to move
them, a handle to make them bigger or smaller (in proportion, from the
opposite corner); beside it, Copy, Cut and Delete. A tap elsewhere lets go
of them. With something copied, a tap on an empty place offers Paste,
there. Undo takes back a move, a resize, a cut, a paste.

The rules live here, pure (tested): what a loop encloses (`pick`), where a
touch lands on the frame (`hit`), moving and scaling, the clipboard (kept
for the session, in the drawing's own units: pasted into another page or
drawing, or at another zoom, it's the same size on the page).

gzreader_sketch.lua calls these from its contacts (`tool == "lasso"`);
gzreader_drawscreen.lua draws the loop, the frame and the buttons.
]]

local Lasso = {
    --- What's copied: { strokes = { { points (scene units, from the frame's corner), width, color, kind } }, w, h }.
    clipboard = nil,
    --- A stroke is chosen when more than this share of its points are inside the loop.
    SHARE = 0.5,
    --- Never smaller or bigger than this many times its size, in one drag.
    MIN_SCALE = 0.2, MAX_SCALE = 5,
}

--- Is (x, y) inside the closed loop `poly` ({ {x, y}, … })? (crossings of a ray to the right)
function Lasso.inside(poly, x, y)
    local n = #poly
    if n < 3 then return false end
    local inside = false
    local j = n
    for i = 1, n do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

--- The strokes of `strokes` (not rubbed out) that loop `poly` encloses: more than SHARE of their points inside.
function Lasso.pick(strokes, poly)
    local out = {}
    if #poly < 3 then return out end
    -- (the loop's own rectangle first: most strokes are nowhere near)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _i, p in ipairs(poly) do
        x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
    end
    for _i, st in ipairs(strokes) do
        if not st.gone and #st.points > 0 then
            local n = 0
            for _j, p in ipairs(st.points) do
                if p[1] >= x0 and p[1] <= x1 and p[2] >= y0 and p[2] <= y1 and Lasso.inside(poly, p[1], p[2]) then n = n + 1 end
            end
            if n > Lasso.SHARE * #st.points then out[#out + 1] = st end
        end
    end
    return out
end

--- Where (x, y) lands on a chosen frame `box` ({ x0, y0, x1, y1 }): "nw",
--- "ne", "sw", "se" (within `reach` of that corner), "inside", or nil.
function Lasso.hit(box, x, y, reach)
    if not box then return nil end
    local function near(cx, cy) return math.abs(x - cx) <= reach and math.abs(y - cy) <= reach end
    if near(box.x0, box.y0) then return "nw" end
    if near(box.x1, box.y0) then return "ne" end
    if near(box.x0, box.y1) then return "sw" end
    if near(box.x1, box.y1) then return "se" end
    if x >= box.x0 and x <= box.x1 and y >= box.y0 and y <= box.y1 then return "inside" end
    return nil
end

--- The points of `strokes` as they are now: { [stroke] = { {x, y, w}, … } } (to go back to, or to scale from).
function Lasso.snapshot(strokes)
    local snap = {}
    for _i, st in ipairs(strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do pts[j] = { p[1], p[2], p[3] } end
        snap[st] = pts
    end
    return snap
end

--- `strokes` put back as in `snap`.
function Lasso.restore(strokes, snap)
    for _i, st in ipairs(strokes) do
        local pts = snap[st]
        if pts then
            local own = {}
            for j, p in ipairs(pts) do own[j] = { p[1], p[2], p[3] } end
            st.points = own
        end
    end
end

--- How a drag of corner `part` from (x0, y0) to (x, y) scales frame `box`:
--- the factor (in proportion, by whichever of width and height grew more)
--- and the corner that stays put.
function Lasso.scaleFor(box, part, x0, y0, x, y)
    local ax = (part == "nw" or part == "sw") and box.x1 or box.x0
    local ay = (part == "nw" or part == "ne") and box.y1 or box.y0
    local w, h = math.max(1, box.x1 - box.x0), math.max(1, box.y1 - box.y0)
    -- (the corner itself goes where the pen went, from where it was)
    local cx = ((part == "nw" or part == "sw") and box.x0 or box.x1) + (x - x0)
    local cy = ((part == "nw" or part == "ne") and box.y0 or box.y1) + (y - y0)
    local f = math.max(math.abs(cx - ax) / w, math.abs(cy - ay) / h)
    f = math.max(Lasso.MIN_SCALE, math.min(Lasso.MAX_SCALE, f))
    return f, ax, ay
end

--- The frame `box` after a drag: moved by (dx, dy), or (a corner) scaled by `f` from (ax, ay).
function Lasso.boxAfter(box, part, dx, dy, f, ax, ay)
    if part == "inside" then return { x0 = box.x0 + dx, y0 = box.y0 + dy, x1 = box.x1 + dx, y1 = box.y1 + dy } end
    local function sx(v) return ax + (v - ax) * f end
    local function sy(v) return ay + (v - ay) * f end
    local x0, x1, y0, y1 = sx(box.x0), sx(box.x1), sy(box.y0), sy(box.y1)
    return { x0 = math.min(x0, x1), y0 = math.min(y0, y1), x1 = math.max(x0, x1), y1 = math.max(y0, y1) }
end

--- `strokes` moved by (dx, dy) from where `snap` has them.
function Lasso.move(strokes, snap, dx, dy)
    for _i, st in ipairs(strokes) do
        local pts = {}
        for j, p in ipairs(snap[st] or st.points) do pts[j] = { p[1] + dx, p[2] + dy, p[3] } end
        st.points = pts
    end
end

--- `strokes` scaled by `f` from (ax, ay), from where `snap` has them.
function Lasso.scale(strokes, snap, f, ax, ay)
    for _i, st in ipairs(strokes) do
        local pts = {}
        for j, p in ipairs(snap[st] or st.points) do pts[j] = { ax + (p[1] - ax) * f, ay + (p[2] - ay) * f, p[3] } end
        st.points = pts
    end
end

--- `strokes` copied (kept in `Lasso.clipboard`): their points in scene
--- units from the corner of the rectangle around them. `to_scene(x, y)`:
--- the sketch's, from canvas pixels.
function Lasso.copy(strokes, to_scene)
    local list = {}
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _i, st in ipairs(strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do
            local sx, sy = to_scene(p[1], p[2])
            pts[j] = { sx, sy, p[3] }
            x0, y0, x1, y1 = math.min(x0, sx), math.min(y0, sy), math.max(x1, sx), math.max(y1, sy)
        end
        list[#list + 1] = { points = pts, width = st.width, color = st.color, kind = st.kind }
    end
    if #list == 0 then return nil end
    for _i, st in ipairs(list) do
        for _j, p in ipairs(st.points) do p[1], p[2] = p[1] - x0, p[2] - y0 end
    end
    Lasso.clipboard = { strokes = list, w = x1 - x0, h = y1 - y0 }
    return Lasso.clipboard
end

--- New strokes from `clip`, its middle at scene point (sx, sy). `to_canvas(x, y)`: the sketch's, to canvas pixels.
function Lasso.fromClip(clip, sx, sy, to_canvas)
    local out = {}
    local ox, oy = sx - clip.w / 2, sy - clip.h / 2
    for _i, st in ipairs(clip.strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do
            local cx, cy = to_canvas(ox + p[1], oy + p[2])
            pts[j] = { cx, cy, p[3] }
        end
        out[#out + 1] = { points = pts, width = st.width, color = st.color, kind = st.kind }
    end
    return out
end

return Lasso
