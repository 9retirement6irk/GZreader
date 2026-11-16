-- A book's default font size on big screens (plugins/zenos.koplugin/common/gz_book_font.lua).
-- Usage: luajit book_font_test.lua <repo>
local REPO = arg[1] or "../../.."
local passed, failed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end

local function settings(t)
    local s = { t = t or {} }
    function s:readSetting(k) return self.t[k] end
    function s:saveSetting(k, v) self.t[k] = v end
    function s:isTrue(k) return self.t[k] == true end
    return s
end
local function dev(w, h, dpi)
    return { display_dpi = dpi, screen = { getWidth = function() return w end, getHeight = function() return h end } }
end
local scribe, k3, pw3, oasis, dx = dev(1860, 2480, 300), dev(600, 800, 167), dev(1072, 1448, 300), dev(1264, 1680, 300), dev(824, 1200, 150)
package.loaded["device"] = scribe

local F = dofile(REPO .. "/plugins/zenos.koplugin/common/gz_book_font.lua")

-- the default
check(F.defaultSize(k3) == 23 and F.defaultSize(pw3) == 23 and F.defaultSize(oasis) == 23, "6-7\" Kindles: ZenOS's 23")
check(F.defaultSize(scribe) == 14, "Scribe: 14 (" .. F.defaultSize(scribe) .. ")")
check(F.defaultSize(dev(2480, 1860, 300)) == 14, "…turned sideways too")
check(F.defaultSize(dx) == 16, "DX: 16 (" .. F.defaultSize(dx) .. ")")
check(F.defaultSize(dev(1860, 2480, nil)) == 23, "no DPI known: 23")
-- the same size to the eye: KOReader scales a size by the screen's width / 600
local function points(size, d, w) return size * (w / 600) / d * 72 end
local p_pw3, p_scribe = points(23, 300, 1072), points(14, 300, 1860)
check(math.abs(p_scribe - p_pw3) < 1.0, string.format("Scribe at 14 ≈ Paperwhite at 23 (%.1f pt, %.1f pt; at 23 the Scribe was %.1f)",
    p_scribe, p_pw3, points(23, 300, 1860)))

-- the global size, once
local g = settings({ copt_font_size = 23 })
check(F.migrateGlobal(g, scribe) == 14 and g.t.copt_font_size == 14 and g.t[F.GLOBAL_DONE], "Scribe: the saved default 23 becomes 14")
g.t.copt_font_size = 23
check(F.migrateGlobal(g, scribe) == nil and g.t.copt_font_size == 23, "…only once (23 chosen again afterwards stays)")
g = settings({})
check(F.migrateGlobal(g, scribe) == 14 and g.t.copt_font_size == 14, "nothing saved: 14")
g = settings({ copt_font_size = 22.5 })
check(F.migrateGlobal(g, scribe) == 14, "22.5 (the owner's Scribe): 14")
g = settings({ copt_font_size = 30 })
check(F.migrateGlobal(g, scribe) == nil and g.t.copt_font_size == 30, "a size chosen (30): kept")
g = settings({ copt_font_size = 23 })
check(F.migrateGlobal(g, pw3) == nil and g.t.copt_font_size == 23 and not g.t[F.GLOBAL_DONE], "Paperwhite: nothing changes")

-- each book, once
local book = settings({})
local conf = { font_size = 22.5 }
check(F.checkBook(conf, book, scribe) == 14 and conf.font_size == 14 and book.t[F.BOOK_DONE], "a book kept at 22.5: 14")
conf.font_size = 23
check(F.checkBook(conf, book, scribe) == nil and conf.font_size == 23, "…only once (a later 23 stays)")
book, conf = settings({}), { font_size = 18 }
check(F.checkBook(conf, book, scribe) == nil and conf.font_size == 18 and book.t[F.BOOK_DONE], "a book at 18 (chosen): kept")
book, conf = settings({}), { font_size = 23 }
check(F.checkBook(conf, book, k3) == nil and conf.font_size == 23 and not book.t[F.BOOK_DONE], "Kindle 3: nothing changes")

-- installed on ReaderFont: the size is set before KOReader hands it to the document
local handed
local ReaderFont = { onReadSettings = function(self) handed = self.configurable.font_size end }
check(F.install(ReaderFont) == true and F.install(ReaderFont) == false, "wrapped once")
local rf = setmetatable({ configurable = { font_size = 23 } }, { __index = ReaderFont })
rf:onReadSettings(settings({}))
check(handed == 14, "a book opened on a Scribe: the document gets 14 (" .. tostring(handed) .. ")")

-- where it's called from
local function read(p) local f = assert(io.open(REPO .. "/" .. p)); local s = f:read("*a"); f:close(); return s end
check(read("plugins/zenos.koplugin/common/reader_defaults.lua"):find('CRE_DEFAULTS.copt_font_size = require("common/gz_book_font").defaultSize()', 1, true) ~= nil,
    "ZenOS's reading defaults (the setup guide) use it")
check(read("plugins/zenos.koplugin/modules/reader/patches/status_on_open.lua"):find('require("common/gz_book_font").install()', 1, true) ~= nil,
    "installed with the reader's patches (before a book opens)")

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
