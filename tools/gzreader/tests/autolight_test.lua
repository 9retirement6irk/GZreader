-- gzreader_autolight.lua's pure part: the curve from the room's light to the
-- front light's, your taste, and gentle changes; the light's real level;
-- Darker text (gzreader_darktext.lua).
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

-- the adjustments (Settings → Brightness)
check(A.target(1000, 0, 24, 0, nil, 12) == 12 and A.target(0, 0, 24, 0, 6, nil) == 6 and A.target(100, 0, 24, 0, 6, 20) == 13,
    "never brighter / never dimmer than: the level kept between them (inside them: as the room asks)")
check(A.target(100, 0, 24, 0, 20, 6) == 13 and A.target(0, 0, 24, 0, 30, nil) == 24 and A.target(0, 0, 24, 0, -5, nil) == 2,
    "…the two the wrong way round, or out of range: read sensibly")
check(A.next(2, 20, 0, 24, A.SPEEDS.slow.step) == 5 and A.next(2, 20, 0, 24, A.SPEEDS.fast.step) == 14 and A.next(2, 20, 0, 24) == 8,
    "slowly, normally, quickly: a smaller or bigger step at a look")
check(A.SPEEDS.slow.every > A.SPEEDS.normal.every and A.SPEEDS.normal.every > A.SPEEDS.fast.every and A.SPEEDS.normal.every == A.LOOK_EVERY,
    "…and looks less or more often (normal: every " .. A.LOOK_EVERY .. " s)")
package.loaded["gettext"] = function(t) return t end
check(A.tasteText(0) == "as it is" and A.tasteText(0.1) == "+10%" and A.tasteText(-0.2) == "\u{2212}20%" and A.tasteText(0.123) == "+12%",
    "brighter or dimmer, in words: as it is, +10%, −20%")
local zero = false
for _i, t in ipairs(A.TASTES) do if t == 0 then zero = true end end
check(zero and A.TASTES[1] < 0 and A.TASTES[#A.TASTES] > 0, "the choices: dimmer, as the room asks, brighter")

-- the light's real level (read through powerd's lipc), put right when something else moved it
package.loaded["gzreader_log"] = { info = function() end, warn = function() end }
local P = { fl_intensity = 10, lipc_handle = {} }
function P:frontlightIntensity() return self.fl_intensity end
function P:frontlightIntensityHW() return 17 end
check(A.realLevel(P, 0, 24) == 17 and P.fl_intensity == 17, "the light's real level: 17 (moved by the Kindle), and KOReader's idea of it put right")
function P:frontlightIntensityHW() return 99 end
P.fl_intensity = 12
check(A.realLevel(P, 0, 24) == 12, "…a level out of range: what KOReader has kept")
P.lipc_handle = nil
function P:frontlightIntensityHW() return 3 end
check(A.realLevel(P, 0, 24) == 12, "…without lipc (the kernel's own numbers): what KOReader has kept")
P.lipc_handle = {}
function P:frontlightIntensityHW() error("lipc gone") end
check(A.realLevel(P, 0, 24) == 12, "…lipc failing: what KOReader has kept")

-- Darker text (gzreader_darktext.lua): a colder temperature sent with every screen update, only while reading
local store = {}
G_reader_settings = { readSetting = function(_s, k) return store[k] end, saveSetting = function(_s, k, v) store[k] = v end }
package.loaded["ui/uimanager"] = { setDirty = function() end }
local D = require("gzreader_darktext")
local req = { temp = 4096 }
local kindle = { isKindle = function() return true end, screen = { update_data = req } }
local kobo = { isKindle = function() return false end, screen = { update_data = { temp = 4096 } } }
local emu = { isKindle = function() return true end, screen = {} }
check(D.available(kindle) and not D.available(kobo) and not D.available(emu), "Darker text: Kindles whose screen updates carry a temperature")
check(D.level() == "off" and D.onReading(kindle) == nil and req.temp == 4096, "Darker text: off at first: nothing changed in a book")
D.set("more", kindle)
check(req.temp == 10 and D.applied == 10, "Darker text: Darker chosen in a book: 10 °C sent")
D.onSuspend(kindle)
check(req.temp == 4096, "Darker text: going to sleep: the panel's own temperature")
D.onResume(kindle)
check(req.temp == 10, "Darker text: awake again in the book: darker again")
D.onClosed(kindle)
check(req.temp == 4096 and D.applied == nil, "Darker text: the book closed: the panel's own")
D.set("most", kindle)
check(req.temp == 4096, "Darker text: chosen at Home: only from the next book")
D.onReading(kindle)
check(req.temp == 4, "…the next book: Darkest, 4 °C")
D.set("off", kindle)
check(req.temp == 4096 and D.menuItem(kobo) == nil, "Darker text: Off: the panel's own again; not offered without a Kindle's screen")
package.loaded["gettext"] = function(t) return t end
package.loaded["ffi/util"] = { template = function(t, a) return (t:gsub("%%1", a)) end }
local it = D.menuItem(kindle)
check(it and #it.sub_item_table == 4 and it.text_func() == "Darker text (experimental): Off", "Darker text: its row: four choices, Off first")
D.onClosed(kindle)

print(string.format("auto light: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
