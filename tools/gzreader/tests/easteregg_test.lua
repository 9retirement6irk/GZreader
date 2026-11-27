-- gzreader_easteregg.lua's pure part: the version's taps (seven open it, a
-- pause starts again, "N more" near the end) and the animation's frames.
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

-- the frames: a book whose pages turn, each turn writing the next letter of "GZreader"
check(table.concat(Egg.WORD) == "GZreader" and Egg.FRAMES == 8 * 4 + 1, "the name's eight letters: three frames of a turning page and the letter, each; then the last page")
local f = Egg.frame(1)
check(f.leaf == 1 and f.letter == nil and f.written == "" and not f.finale, "it starts with a page lifting off the right, nothing written yet")
check(Egg.frame(2).leaf == 2 and Egg.frame(3).leaf == 3, "…upright at the spine, then over the left page")
f = Egg.frame(4)
check(f.leaf == 0 and f.letter == "G" and f.written == "", "…and the first letter is on the right page: G")
f = Egg.frame(5)
check(f.leaf == 1 and f.letter == nil and f.written == "G", "the next page turns: G is now on the left page")
check(Egg.frame(8).letter == "Z" and Egg.frame(12).letter == "r" and Egg.frame(12).written == "GZ", "Z, then r, the left page keeping what's written")
f = Egg.frame(32)
check(f.letter == "r" and f.written == "GZreade", "the last letter")
f = Egg.frame(33)
check(f.finale and f.leaf == 0 and f.written == "GZreader" and f.letter == nil, "the last page: the whole name")
check(Egg.frame(0).leaf == 1 and Egg.frame(99).finale, "a frame outside: the nearest one")
local seen = {}
for n = 1, Egg.FRAMES do local fr = Egg.frame(n); if fr.letter then seen[#seen + 1] = fr.letter end end
check(table.concat(seen) == "GZreader", "every letter once, in order")
check(Egg.wait(1) < Egg.wait(4) and Egg.wait(4) < Egg.wait(33), "a turning page moves on quickly, a letter stays to be read, the last page longest")
check(Egg.new == nil and Egg.slide == nil and Egg.BEST == nil, "the game it replaced is gone (nothing kept in the settings)")

print(string.format("easter egg: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
