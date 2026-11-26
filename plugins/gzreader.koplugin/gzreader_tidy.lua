--[[--
Tidy handwriting (the drawing screen: choose writing with the lasso, then
Tidy). It doesn't read the writing or change its letters: it moves and sizes
whole words so the page looks neater.

- Lines: the strokes are sorted into lines of writing (by height on the
  page), and each line into words (by the gaps between strokes).
- Level: a line that runs uphill or downhill is turned flat, and each word
  is set on the line's baseline (the bottoms of its letters).
- Even size: a word much bigger or smaller than the others on its line is
  brought towards their size (at most a quarter bigger or a fifth smaller).
- Even spacing: the gaps between words on a line are made the same.

One Undo puts it all back. Shapes, highlighter and text boxes aren't
touched. Everything is worked out from the strokes' points (canvas pixels);
nothing is sent anywhere.
]]

local Tidy = {
    MAX_TILT = math.rad(20), -- steeper than this: not a line of writing, left as it is
    GROW = 1.25,             -- a word is made at most this much bigger…
    SHRINK = 0.8,            -- …or this much smaller
    SAME = 0.06,             -- closer than this to the line's size: left as it is
    WORD_GAP = 0.45,         -- a gap wider than this (× letter height) starts a new word
    LINE_GAP = 0.75,         -- a stroke this far (× letter height) from a line's middle starts another line
}

local function median(t)
    if #t == 0 then return nil end
    local s = {}
    for i, v in ipairs(t) do s[i] = v end
    table.sort(s)
    local m = math.floor((#s + 1) / 2)
    if #s % 2 == 1 then return s[m] end
    return (s[m] + s[m + 1]) / 2
end
Tidy.median = median

--- A stroke's box: { x0, y0, x1, y1, cx, cy, h }.
function Tidy.box(points)
    local x0, y0, x1, y1
    for _i, p in ipairs(points) do
        x0, y0 = math.min(x0 or p[1], p[1]), math.min(y0 or p[2], p[2])
        x1, y1 = math.max(x1 or p[1], p[1]), math.max(y1 or p[2], p[2])
    end
    if not x0 then return nil end
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, h = y1 - y0, w = x1 - x0 }
end

--- The strokes Tidy works on: live writing (not shapes, highlighter or
--- rubbed out), with at least two points.
function Tidy.writing(strokes)
    local out = {}
    for _i, st in ipairs(strokes or {}) do
        if not st.gone and not st.shape and st.kind ~= "highlighter" and type(st.points) == "table" and #st.points >= 2 then
            out[#out + 1] = st
        end
    end
    return out
end

-- items: { st, pts (a copy being changed), b (its box) }
local function itemsOf(strokes)
    local items = {}
    for _i, st in ipairs(strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do pts[j] = { p[1], p[2], p[3], p[4] } end
        local b = Tidy.box(pts)
        if b then items[#items + 1] = { st = st, pts = pts, b = b } end
    end
    return items
end

local function refresh(it) it.b = Tidy.box(it.pts) end

--- The letters' height: the middle stroke height, leaving out dots.
function Tidy.letterHeight(items)
    local hs = {}
    for _i, it in ipairs(items) do hs[#hs + 1] = it.b.h end
    local m = median(hs) or 0
    local big = {}
    for _i, h in ipairs(hs) do if h >= m * 0.4 then big[#big + 1] = h end end
    return math.max(median(big) or m, 1)
end

--- Where a line's middle is expected at x: its last stroke's, carried on
--- along the slope of the strokes so far (a line running uphill stays one).
function Tidy.expect(line, x)
    local last = line[#line].b
    if #line < 3 then return last.cy end
    local n, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
    for _i, it in ipairs(line) do
        local px, py = it.b.cx, it.b.cy
        n, sx, sy, sxx, sxy = n + 1, sx + px, sy + py, sxx + px * px, sxy + px * py
    end
    local d = n * sxx - sx * sx
    if d == 0 then return last.cy end
    local k = (n * sxy - sx * sy) / d
    local lim = math.tan(math.rad(25))
    k = math.max(-lim, math.min(lim, k))
    return last.cy + k * (x - last.cx)
end

--- Items sorted into lines, top to bottom: { { items… }, … }. Followed left
--- to right, so a line running uphill stays one line; small marks (dots,
--- accents, commas) join the line of the stroke nearest them.
function Tidy.lines(items, H)
    local big, small = {}, {}
    for _i, it in ipairs(items) do
        if it.b.h < 0.4 * H and it.b.w < 0.6 * H then small[#small + 1] = it else big[#big + 1] = it end
    end
    if #big == 0 then big, small = small, {} end
    table.sort(big, function(a, b) return a.b.x0 < b.b.x0 end)
    local lines = {}
    for _i, it in ipairs(big) do
        local best, bd
        for _k, line in ipairs(lines) do
            local d = math.abs(it.b.cy - Tidy.expect(line, it.b.cx))
            if d <= Tidy.LINE_GAP * H and (not bd or d < bd) then best, bd = line, d end
        end
        if best then best[#best + 1] = it else lines[#lines + 1] = { it } end
    end
    for _i, it in ipairs(small) do
        local best, bd
        for _k, line in ipairs(lines) do
            for _m, o in ipairs(line) do
                local dx = math.max(0, o.b.x0 - it.b.cx, it.b.cx - o.b.x1)
                local dy = math.max(0, o.b.y0 - it.b.cy, it.b.cy - o.b.y1)
                local d = dx * dx + dy * dy
                if not bd or d < bd then best, bd = line, d end
            end
        end
        if best then best[#best + 1] = it else lines[#lines + 1] = { it } end
    end
    for _i, line in ipairs(lines) do
        local sum = 0
        for _k, it in ipairs(line) do sum = sum + it.b.cy end
        line.cy = sum / #line
    end
    table.sort(lines, function(a, b) return a.cy < b.cy end)
    return lines
end

--- A line's items sorted into words, left to right: { { items…, x0, x1 }, … }.
function Tidy.words(line, H)
    local sorted = {}
    for i, it in ipairs(line) do sorted[i] = it end
    table.sort(sorted, function(a, b) return a.b.x0 < b.b.x0 end)
    local words = {}
    for _i, it in ipairs(sorted) do
        local w = words[#words]
        if w and it.b.x0 <= w.x1 + Tidy.WORD_GAP * H then
            w[#w + 1] = it
            w.x1 = math.max(w.x1, it.b.x1)
        else
            words[#words + 1] = { it, x0 = it.b.x0, x1 = it.b.x1 }
        end
    end
    return words
end

local function wordBox(w)
    local x0, y0, x1, y1
    for _i, it in ipairs(w) do
        local b = it.b
        x0, y0 = math.min(x0 or b.x0, b.x0), math.min(y0 or b.y0, b.y0)
        x1, y1 = math.max(x1 or b.x1, b.x1), math.max(y1 or b.y1, b.y1)
    end
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, cx = (x0 + x1) / 2 }
end

--- Where a word sits: the middle of its letters' bottoms (dots left out).
function Tidy.baseline(w, H)
    local ys = {}
    for _i, it in ipairs(w) do if it.b.h >= 0.4 * H then ys[#ys + 1] = it.b.y1 end end
    if #ys == 0 then for _i, it in ipairs(w) do ys[#ys + 1] = it.b.y1 end end
    return median(ys)
end

--- How big a word's letters are (dots left out).
function Tidy.size(w, H)
    local hs = {}
    for _i, it in ipairs(w) do if it.b.h >= 0.4 * H then hs[#hs + 1] = it.b.h end end
    return median(hs) or H
end

local function each(w, fn)
    for _i, it in ipairs(w) do
        for _j, p in ipairs(it.pts) do fn(p) end
        refresh(it)
    end
end

--- The slope of a line (radians, by the words' baselines): 0 with one word.
function Tidy.tilt(words, H)
    if #words < 2 then return 0 end
    local n, sx, sy, sxx, sxy = 0, 0, 0, 0, 0
    for _i, w in ipairs(words) do
        local x, y = wordBox(w).cx, Tidy.baseline(w, H)
        n, sx, sy, sxx, sxy = n + 1, sx + x, sy + y, sxx + x * x, sxy + x * y
    end
    local d = n * sxx - sx * sx
    if d == 0 then return 0 end
    return math.atan((n * sxy - sx * sy) / d)
end

--- Tidy one line's items (their copies' points change). Returns what was done.
function Tidy.line(line, H)
    local done = { turned = false, moved = 0, sized = 0, spaced = false }
    local words = Tidy.words(line, H)
    -- level: the line turned flat about its middle
    local a = Tidy.tilt(words, H)
    if a ~= 0 and math.abs(a) <= Tidy.MAX_TILT and math.abs(a) > math.rad(1) then
        local x0, x1, ys = math.huge, -math.huge, {}
        for _i, w in ipairs(words) do
            x0, x1 = math.min(x0, w.x0), math.max(x1, w.x1)
            ys[#ys + 1] = Tidy.baseline(w, H)
        end
        local ox, oy = (x0 + x1) / 2, median(ys)
        local c, s = math.cos(-a), math.sin(-a)
        for _i, w in ipairs(words) do
            each(w, function(p)
                local dx, dy = p[1] - ox, p[2] - oy
                p[1], p[2] = ox + dx * c - dy * s, oy + dx * s + dy * c
            end)
        end
        done.turned = true
        words = Tidy.words(line, H)
    end
    -- each word on the line's baseline
    local bases = {}
    for i, w in ipairs(words) do bases[i] = Tidy.baseline(w, H) end
    local B = median(bases)
    for i, w in ipairs(words) do
        local dy = B - bases[i]
        if math.abs(dy) >= 1 then
            each(w, function(p) p[2] = p[2] + dy end)
            done.moved = done.moved + 1
        end
    end
    -- even size: towards the line's
    if #words >= 2 then
        local sizes = {}
        for i, w in ipairs(words) do sizes[i] = Tidy.size(w, H) end
        local target = median(sizes)
        for i, w in ipairs(words) do
            local f = math.max(Tidy.SHRINK, math.min(Tidy.GROW, target / math.max(sizes[i], 1)))
            if math.abs(f - 1) > Tidy.SAME then
                local ax = wordBox(w).x0
                each(w, function(p) p[1], p[2] = ax + (p[1] - ax) * f, B + (p[2] - B) * f end)
                done.sized = done.sized + 1
            end
        end
    end
    -- even spacing: the gaps the same
    if #words >= 3 then
        local boxes, gaps = {}, {}
        for i, w in ipairs(words) do boxes[i] = wordBox(w) end
        for i = 2, #boxes do gaps[#gaps + 1] = boxes[i].x0 - boxes[i - 1].x1 end
        local G = math.max(Tidy.WORD_GAP * H, math.min(2 * H, median(gaps)))
        local x = boxes[1].x1
        for i = 2, #words do
            local dx = (x + G) - boxes[i].x0
            if math.abs(dx) >= 1 then
                each(words[i], function(p) p[1] = p[1] + dx end)
                done.spaced = true
            end
            x = boxes[i].x1 + dx
        end
    end
    return done
end

--- Work out the tidied points for `strokes`: { [stroke] = points }, and a
--- summary { lines, words, turned, moved, sized, spaced }.
function Tidy.plan(strokes)
    local items = itemsOf(Tidy.writing(strokes))
    local sum = { lines = 0, words = 0, turned = 0, moved = 0, sized = 0, spaced = 0 }
    local out = {}
    if #items == 0 then return out, sum end
    local H = Tidy.letterHeight(items)
    for _i, line in ipairs(Tidy.lines(items, H)) do
        local lh = Tidy.letterHeight(line)
        sum.lines = sum.lines + 1
        sum.words = sum.words + #Tidy.words(line, lh)
        local d = Tidy.line(line, lh)
        sum.turned = sum.turned + (d.turned and 1 or 0)
        sum.moved, sum.sized = sum.moved + d.moved, sum.sized + d.sized
        sum.spaced = sum.spaced + (d.spaced and 1 or 0)
    end
    for _i, it in ipairs(items) do out[it.st] = it.pts end
    return out, sum
end

--- Tidy `strokes` in sketch `sk` as one step Undo takes back. Returns
--- changed, the area to draw again (canvas pixels, or nil), the summary.
function Tidy.apply(sk, strokes)
    local Lasso = require("gzreader_lasso")
    local writing = Tidy.writing(strokes)
    local plan, sum = Tidy.plan(writing)
    local list = {}
    for _i, st in ipairs(writing) do if plan[st] then list[#list + 1] = st end end
    if #list == 0 then return false, nil, sum end
    local before = Lasso.snapshot(list)
    local area = sk.strokesArea and sk:strokesArea(list) or nil
    local moved = false
    for _i, st in ipairs(list) do
        for j, p in ipairs(plan[st]) do
            local q = st.points[j]
            if math.abs(p[1] - q[1]) > 0.01 or math.abs(p[2] - q[2]) > 0.01 then moved = true end
        end
        st.points = plan[st]
    end
    if not moved then
        Lasso.restore(list, before)
        return false, nil, sum
    end
    sk.history[#sk.history + 1] = { kind = "move", strokes = list, before = before, after = Lasso.snapshot(list) }
    sk.redone = {}
    if sk.strokesArea then area = sk:strokesArea(list, area) end
    return true, area, sum
end

return Tidy
