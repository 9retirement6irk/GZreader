-- Narrated EPUBs (gzreader_narration.lua): a small EPUB 3 with media
-- overlays (GZ_EMU_BOOK, made by tests/make_narrated_epub.py), its
-- narration played from the first page: the sentence being read
-- highlighted, the next as the audio goes on, then chapter 2 on its page.
-- The emulator has no sound: the player is stood in for, its time moved on.
--   GZ_EMU_MODEL=scribe GZ_EMU_BOOK=<narrated epub> GZ_EMU_TREE=<tree>/koreader run.sh narration.lua <out>
-- Checks go to <out>/narration-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 12 })
add({ fn = function(E)
    local N = require("gzreader_narration")
    local Engine = require("gzreader_audioengine")
    E.plays = {}
    Engine.chosen = function(fmt) return { id = "emu-" .. tostring(fmt) } end
    Engine.play = function(_p, src) E.plays[#E.plays + 1] = src; return true, src.offset_ms end
    Engine.running = function() return true end
    Engine.stop = function() end
    check(N.available(reader()), "the book has narration (8 sentences)")
    local ok, why = N.play(reader())
    E.say("narration: play", tostring(ok), tostring(why), "file", tostring(E.plays[1] and E.plays[1].path))
    check(ok and E.plays[1] and E.plays[1].offset_ms == 0 and E.plays[1].path:find("gz%-narration") ~= nil,
        "Play from this page: the audio copied out of the book, played from the first sentence")
end, after = 2 })
-- (the audio's time set by hand: the narration at `sec` seconds, looked at once)
local function at(sec)
    local cur = require("gzreader_narration").current
    local T = require("ui/time")
    cur.t0 = T.to_s(T.now()) - sec + cur.base / 1000
    cur:tick()
    return cur
end
add({ fn = function(E)
    local cur = require("gzreader_narration").current
    E.lit = {}
    local orig = cur.highlight
    cur.highlight = function(self, p) E.lit[#E.lit + 1] = p.id; return orig(self, p) end
    at(1)
    E.say("narration: sentence", cur.i, "lit", table.concat(E.lit, ","))
    check(cur.i == 1, "the first sentence highlighted")
end, after = 2 })
add({ shot = "narration-1-first" })
add({ fn = function(E)
    local cur = at(4)
    E.say("narration: sentence", cur.i, "lit", table.concat(E.lit, ","))
    check(cur.i == 2 and E.lit[#E.lit] == "c1s2", "four seconds on: the second sentence highlighted")
end, after = 2 })
add({ shot = "narration-2-second" })
add({ fn = function(E)
    local cur = at(12.5)
    E.at_ch2 = cur.i
    local doc = reader().document
    local xp = cur:xpOf(cur.book.pars[5])
    E.ch2_on_page = xp and doc:isXPointerInCurrentPage(xp)
    E.say("narration: sentence", cur.i, "lit", table.concat(E.lit, ","), "chapter 2 on the page", tostring(E.ch2_on_page))
end, after = 2 })
add({ shot = "narration-3-chapter2" })
add({ fn = function(E)
    local N = require("gzreader_narration")
    check(E.at_ch2 == 5 and E.lit[#E.lit] ~= nil and table.concat(E.lit, ","):find("c2s1", 1, true) ~= nil and E.ch2_on_page,
        "past chapter 1's narration: chapter 2's first sentence highlighted, its page turned to")
    check(#E.plays == 2 and E.plays[2].offset_ms == 0, "chapter 2's audio started from its own place")
    N.stop("the tour's end")
    check(N.current == nil, "stopped")
    local f = io.open(E.out .. "/narration-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
