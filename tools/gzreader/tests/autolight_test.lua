-- gzreader_autolight.lua's pure part: the curve from the room's light to the
-- front light's, your taste, and gentle changes.
--   luajit autolight_test.lua <plugin dir>
package.path = (arg[1] or "../../../plugins/gzreader.koplugin") .. "/?.lua;" .. package.path
local A = require("gzreader_autolight")
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end end
local function near(a, b, e) return math.abs(a - b) <= (e or 0.02) end

check(near(A.curve(0), 0.08) and near(A.curve(1), 0.152) and near(A.curve(10), 0.33) and near(A.curve(100), 0.56)
    and near(A.curve(1000), 0.80) and near(A.curve(50000), 0.80) and A.curve(-5) == A.curve(0) and A.curve(nil) == A.curve(0),
    "the curve: dim in the dark, brighter with the room (by its logarithm), most of it from 1,000 lux")
check(A.curve(5) < A.curve(50) and A.curve(50) < A.curve(500), "…always brighter for a brighter room")
check(A.target(0, 0, 24, 0) == 2 and A.target(100, 0, 24, 0) == 13 and A.target(1000, 0, 24, 0) == 19,
    "levels on the Kindle's 0–24: 2 in the dark, 13 at 100 lux, 19 in daylight")
check(A.target(100, 0, 24, 0.2) == 18 and A.target(100, 0, 24, -1) == 0 and A.target(1000, 0, 24, 1) == 24,
    "your taste moves it (and it stays in range)")
check(A.next(10, 11, 0, 24) == nil and A.next(10, 12, 0, 24) == 12, "a small difference is left alone (less than 6% of the range)")
check(A.next(2, 20, 0, 24) == 8 and A.next(20, 2, 0, 24) == 14, "a big one: a quarter of the range at a look, not all at once")
check(A.next(0, 5, 0, 100) == nil and A.next(0, 7, 0, 100) == 7 and A.next(0, 50, 0, 100) == 25, "…on a 0–100 range too")
local o = A.offsetFor(18, 100, 0, 24)
check(near(o, 18 / 24 - A.curve(100), 0.001) and A.target(100, 0, 24, o) == 18, "set yourself to 18 at 100 lux: remembered, and 100 lux gives 18 again")
check(A.target(1000, 0, 24, o) > A.target(1000, 0, 24, 0), "…and brighter than the curve in other rooms too")
check(A.offsetFor(0, 0, 0, 24) < 0 and A.offsetFor(24, 1000, 0, 24) > 0, "darker or brighter than the curve: a minus or a plus")

print(string.format("auto light: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
