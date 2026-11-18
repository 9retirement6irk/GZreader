-- gzreader_shapesnap.lua: rough strokes (with a hand's wobble) recognised as
-- a line, a circle, a triangle, a box or another polygon; writing and
-- scribbles left alone; and the pen's hold at the end.
--   luajit shapesnap_test.lua <plugin dir>
package.path = (arg[1] or "../../../plugins/gzreader.koplugin") .. "/?.lua;" .. package.path
local SS = require("gzreader_shapesnap")
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end end
math.randomseed(7)
local function wobble(v, amt) return v + (math.random() - 0.5) * 2 * amt end
--- A path through `corners`, `n` points a side, wobbling by `amt`.
local function path(corners, n, amt)
    local out = {}
    for k = 1, #corners - 1 do
        local a, b = corners[k], corners[k + 1]
        for i = 0, n - 1 do
            local t = i / n
            out[#out + 1] = { wobble(a[1] + (b[1] - a[1]) * t, amt), wobble(a[2] + (b[2] - a[2]) * t, amt) }
        end
    end
    local z = corners[#corners]
    out[#out + 1] = { wobble(z[1], amt), wobble(z[2], amt) }
    return out
end
local function ring(cx, cy, rx, ry, n, amt, gap)
    local out = {}
    for i = 0, n - (gap or 0) do
        local t = 2 * math.pi * i / n
        out[#out + 1] = { wobble(cx + rx * math.cos(t), amt), wobble(cy + ry * math.sin(t), amt) }
    end
    return out
end

local kind, pts = SS.recognise(path({ { 100, 100 }, { 400, 160 } }, 30, 4))
check(kind == "line" and #pts == 2 and math.abs(pts[1][1] - 100) < 6 and math.abs(pts[2][1] - 400) < 6, "a wobbly line: a straight one, end to end")
kind = SS.recognise(path({ { 100, 100 }, { 250, 300 }, { 400, 100 } }, 20, 3))
check(kind == nil, "a V (open, bent): not a shape")
kind, pts = SS.recognise(ring(300, 300, 120, 120, 60, 6))
check(kind == "circle" and #pts > 24, "a rough circle: a round one")
kind, pts = SS.recognise(ring(300, 300, 200, 80, 60, 5, 3))
local x0, x1 = math.huge, -math.huge
for _i, p in ipairs(pts or {}) do x0, x1 = math.min(x0, p[1]), math.max(x1, p[1]) end
check(kind == "circle" and x1 - x0 > 380, "an oval, not quite closed: an oval as wide as it was drawn")
kind, pts = SS.recognise(path({ { 300, 100 }, { 450, 350 }, { 150, 350 }, { 300, 104 } }, 25, 4))
check(kind == "triangle" and #pts == 4, "a rough triangle: three straight sides through its corners")
kind, pts = SS.recognise(path({ { 100, 100 }, { 400, 104 }, { 398, 300 }, { 102, 297 }, { 103, 106 } }, 25, 4))
check(kind == "rectangle" and #pts == 5 and pts[1][1] == pts[4][1] and pts[1][2] == pts[2][2], "a rough box: a straight-sided one, level")
kind, pts = SS.recognise(path({ { 250, 100 }, { 400, 250 }, { 250, 400 }, { 100, 250 }, { 248, 104 } }, 25, 4))
check(kind == "polygon" and #pts == 5, "a diamond (a box on its point): its four corners, kept as drawn")
kind = SS.recognise(path({ { 100, 100 }, { 110, 105 } }, 5, 1))
check(kind == nil, "something tiny: left alone")
-- writing: a squiggle like a word
local word = {}
for i = 0, 80 do word[#word + 1] = { 100 + i * 4, 200 + 25 * math.sin(i * 0.9) + (i % 7) * 3 } end
check(SS.recognise(word) == nil, "writing (a squiggle across): left alone")
local scribble = {}
for i = 0, 120 do scribble[#scribble + 1] = { 300 + 80 * math.sin(i * 1.7), 300 + 60 * math.cos(i * 2.3) } end
check(SS.recognise(scribble) == nil, "a scribble back and forth: left alone")
-- the hold
check(SS.held({ { 0, 100, 100 }, { 0.2, 200, 100 }, { 0.3, 201, 101 }, { 0.9, 202, 100 } }, 0.95), "held still 0.6 s at the end: yes")
check(not SS.held({ { 0, 100, 100 }, { 0.2, 200, 100 }, { 0.6, 260, 100 }, { 0.7, 261, 100 } }, 0.75), "lifted soon after moving: no")
check(not SS.held({}, 1), "no samples: no")

print(string.format("shape snap: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
