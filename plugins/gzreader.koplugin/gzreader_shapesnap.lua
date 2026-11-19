--[[--
Shapes cleaned up, as the Apple Newton (and an iPad) do it: draw a rough
line, circle, triangle or box, keep the pen still on the glass for a moment
at the end, and the stroke becomes a clean one, in the same place.

  ShapeSnap.recognise(points) → kind ("line" | "circle" | "triangle" |
      "rectangle" | "polygon"), points (the clean outline), or nil
  ShapeSnap.held(times_and_points, now) → true when the pen has kept still
      for HOLD seconds at the stroke's end

Pure (shapesnap_test.lua); gzreader_sketch.lua does it at the pen's lift.
]]

local ShapeSnap = {
    HOLD = 0.6, -- seconds the pen keeps still at the end
    STILL = 8, -- pixels it may wander meanwhile
    MIN_SIZE = 24, -- a shape smaller than this (pixels) is left as it was drawn
    LINE_BEND = 0.06, -- a line: no point further off its chord than this much of its length
    CLOSED = 0.22, -- a closed shape: its ends nearer than this much of its size
    ROUND = 0.16, -- a circle: its points' distance from the middle varies less than this
}

local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

--- How far point p is from the line through a and b.
local function offLine(p, a, b)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return dist(p, a) end
    return math.abs(dy * p[1] - dx * p[2] + b[1] * a[2] - b[2] * a[1]) / len
end

--- Ramer–Douglas–Peucker: the points that matter, within `eps` of the rest.
local function simplify(pts, eps, i, j, keep)
    local far, at = -1, nil
    for k = i + 1, j - 1 do
        local d = offLine(pts[k], pts[i], pts[j])
        if d > far then far, at = d, k end
    end
    if at and far > eps then
        simplify(pts, eps, i, at, keep)
        keep[at] = true
        simplify(pts, eps, at, j, keep)
    end
end

local function bbox(pts)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _i, p in ipairs(pts) do
        x0, y0 = math.min(x0, p[1]), math.min(y0, p[2])
        x1, y1 = math.max(x1, p[1]), math.max(y1, p[2])
    end
    return x0, y0, x1, y1
end

--- The corners of a closed stroke (drawn round once), in order.
local function corners(pts, size)
    -- (start from the point furthest from the first: a corner is rarely where the pen started)
    local far, at = -1, 1
    for k, p in ipairs(pts) do
        local d = dist(p, pts[1])
        if d > far then far, at = d, k end
    end
    local ring = {}
    for k = at, #pts do ring[#ring + 1] = pts[k] end
    for k = 1, at do ring[#ring + 1] = pts[k] end
    local keep = { [1] = true, [#ring] = true }
    simplify(ring, size * 0.09, 1, #ring, keep)
    local out = {}
    for k = 1, #ring - 1 do if keep[k] then out[#out + 1] = ring[k] end end
    -- (two corners nearly on top of each other are one)
    local merged = {}
    for _k, p in ipairs(out) do
        if #merged == 0 or dist(p, merged[#merged]) > size * 0.15 then merged[#merged + 1] = p end
    end
    if #merged > 2 and dist(merged[1], merged[#merged]) <= size * 0.15 then table.remove(merged) end
    -- (a corner on a nearly straight run isn't one)
    local again = true
    while again and #merged > 3 do
        again = false
        for k = 1, #merged do
            local a, b, c = merged[(k - 2) % #merged + 1], merged[k], merged[k % #merged + 1]
            if offLine(b, a, c) < size * 0.08 then table.remove(merged, k); again = true; break end
        end
    end
    return merged
end

--- What a stroke (points { x, y }) is, and its clean outline; nil when it's
--- none of these (writing, a scribble) or too small.
function ShapeSnap.recognise(pts)
    if type(pts) ~= "table" or #pts < 4 then return nil end
    local x0, y0, x1, y1 = bbox(pts)
    local w, h = x1 - x0, y1 - y0
    local size = math.max(w, h)
    if size < ShapeSnap.MIN_SIZE then return nil end
    local a, b = pts[1], pts[#pts]
    local chord = dist(a, b)
    -- a line: every point near the chord from the first to the last
    if chord >= 0.8 * size then
        local worst = 0
        for _i, p in ipairs(pts) do worst = math.max(worst, offLine(p, a, b)) end
        if worst <= ShapeSnap.LINE_BEND * chord then
            return "line", { { a[1], a[2] }, { b[1], b[2] } }
        end
        return nil
    end
    -- closed: the ends meet
    if chord > ShapeSnap.CLOSED * size then return nil end
    -- a circle (or an oval): every point about as far from the middle (in the box's own proportions)
    local cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, math.max(1, w / 2), math.max(1, h / 2)
    local sum, sum2, n = 0, 0, 0
    for _i, p in ipairs(pts) do
        local r = math.sqrt(((p[1] - cx) / rx) ^ 2 + ((p[2] - cy) / ry) ^ 2)
        sum, sum2, n = sum + r, sum2 + r * r, n + 1
    end
    local mean = sum / n
    local sd = math.sqrt(math.max(0, sum2 / n - mean * mean))
    local cs = corners(pts, size)
    if sd / mean < ShapeSnap.ROUND and #cs > 4 or (#cs >= 3 and sd / mean < ShapeSnap.ROUND * 0.6) then
        local out = {}
        local m = math.max(24, math.min(96, math.floor((rx + ry) / 4)))
        for i = 0, m do
            local t = 2 * math.pi * i / m
            out[#out + 1] = { cx + rx * math.cos(t), cy + ry * math.sin(t) }
        end
        return "circle", out
    end
    if #cs == 3 then
        return "triangle", { { cs[1][1], cs[1][2] }, { cs[2][1], cs[2][2] }, { cs[3][1], cs[3][2] }, { cs[1][1], cs[1][2] } }
    end
    if #cs == 4 then
        -- sides near level and upright: a box (its own box); else the four corners as drawn
        local level = true
        for k = 1, 4 do
            local p, q = cs[k], cs[k % 4 + 1]
            local ang = math.deg(math.atan2(math.abs(q[2] - p[2]), math.abs(q[1] - p[1])))
            if not (ang < 12 or ang > 78) then level = false end
        end
        if level then
            return "rectangle", { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 }, { x0, y0 } }
        end
        local out = {}
        for k = 1, 4 do out[k] = { cs[k][1], cs[k][2] } end
        out[5] = { cs[1][1], cs[1][2] }
        return "polygon", out
    end
    if #cs >= 5 and #cs <= 8 then
        local out = {}
        for k = 1, #cs do out[k] = { cs[k][1], cs[k][2] } end
        out[#out + 1] = { cs[1][1], cs[1][2] }
        return "polygon", out
    end
    return nil
end

--- Whether the pen kept still at the end: `trail` = { { t, x, y }, … } (the
--- stroke's last samples, oldest first), `now` the time of the lift.
function ShapeSnap.held(trail, now)
    if type(trail) ~= "table" or #trail == 0 then return false end
    local last = trail[#trail]
    local since = last[1]
    for k = #trail, 1, -1 do
        local p = trail[k]
        if math.abs(p[2] - last[2]) > ShapeSnap.STILL or math.abs(p[3] - last[3]) > ShapeSnap.STILL then break end
        since = p[1]
    end
    return (now or last[1]) - since >= ShapeSnap.HOLD
end

return ShapeSnap
