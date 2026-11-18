-- gzreader_easteregg.lua's pure part: the version's taps (seven open it, a
-- pause starts again, "N more" near the end) and the 15 puzzle's board.
--   luajit easteregg_test.lua <plugin dir>
package.path = (arg[1] or "../../../plugins/gzreader.koplugin") .. "/?.lua;" .. package.path
local Egg = require("gzreader_easteregg")
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end end

-- the taps
local st, said, opened = {}, {}, 0
for i = 1, 7 do
    local r = Egg.tap(st, 100 + i)
    said[#said + 1] = r.left and tostring(r.left) or "-"
    if r.open then opened = opened + 1 end
end
check(opened == 1 and table.concat(said, ",") == "-,-,-,3,2,1,-", "seven taps open it; from the fourth: 3, 2, 1 more")
st = {}
for i = 1, 6 do Egg.tap(st, 200 + i) end
local r = Egg.tap(st, 206 + Egg.WINDOW + 1)
check(not r.open and r.count == 1, "a pause longer than " .. Egg.WINDOW .. " s: the count starts again")
st = {}
for i = 1, 7 do Egg.tap(st, 300 + i) end
check(Egg.tap(st, 308).count == 1, "…and again from one after it opened")

-- the board
local b = Egg.new()
check(b.side == 4 and b[1] == 1 and b[15] == 15 and b[16] == 0 and b.gap == 16 and Egg.solved(b), "a new board: 1–15 in order, the gap last")
check(Egg.slide(b, 1) == nil and Egg.slide(b, 16) == nil, "a tile not in the gap's row or column, or the gap itself: nothing")
local changed = Egg.slide(b, 13)
check(changed and #changed == 4 and b[13] == 0 and b[14] == 13 and b[15] == 14 and b[16] == 15 and b.gap == 13 and b.moves == 1,
    "a tile three along the gap's row: it and the two between slide over (one move)")
check(not Egg.solved(b), "…no longer solved")
check(Egg.slide(b, 1) and b[1] == 0 and b[5] == 1 and b[9] == 5 and b[13] == 9 and b.gap == 1, "…and up a column")
local b2 = Egg.new()
check(Egg.slideDir(b2, "up") == nil and Egg.slideDir(b2, "left") == nil, "the gap in the corner: nothing below or right of it to move")
check(Egg.slideDir(b2, "down") and b2[16] == 12 and b2.gap == 12 and Egg.slideDir(b2, "up") and Egg.solved(b2),
    "▼: the tile above the gap comes down; ▲: back up (solved again)")
-- shuffled: solvable (made from solved by legal slides), not solved, moves at 0
local seq, n = { 1, 2, 3, 4 }, 0
local function rand(k) n = n + 1; return seq[(n % #seq) + 1] % k + 1 end
local s = Egg.shuffle(Egg.new(), 50, rand)
check(not Egg.solved(s) and s.moves == 0, "shuffled: not solved, no moves counted")
local seen = {}
for i = 1, 16 do seen[s[i]] = (seen[s[i]] or 0) + 1 end
local ok = true
for v = 0, 15 do if seen[v] ~= 1 then ok = false end end
check(ok, "…every tile and the gap once")
-- the parity: a reachable board has (inversions + the gap's row from the bottom) odd (4 x 4)
local inv, flat = 0, {}
for i = 1, 16 do if s[i] ~= 0 then flat[#flat + 1] = s[i] end end
for i = 1, #flat do for j = i + 1, #flat do if flat[i] > flat[j] then inv = inv + 1 end end end
local gap_row_from_bottom = 4 - math.floor((s.gap - 1) / 4)
check((inv + gap_row_from_bottom) % 2 == 1, "…and solvable (its parity is a reachable board's)")

print(string.format("easter egg: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
