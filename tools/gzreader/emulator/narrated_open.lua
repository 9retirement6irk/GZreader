-- A narrated EPUB opened from Home (gzreader_narratedopen.lua): the question
-- (Read, Read with narration, Listen as audiobook); Read with narration plays
-- it with the sentence highlighted; the quick panel's Read aloud is the
-- narration there; Listen as audiobook opens the audiobook player with the
-- book's chapters. The emulator has no sound: the player is stood in for.
--   GZ_EMU_MODEL=scribe GZ_EMU_BOOK=<narrated epub> GZ_EMU_TREE=<tree>/koreader run.sh narrated_open.lua <out>
-- Checks go to <out>/narrated-open-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function press(label)
    local d = top()
    for _r, row in ipairs(d and d.buttons or {}) do
        for _c, b in ipairs(row) do if b.text == label then b.callback(); return true end end
    end
    return false
end
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    -- (a Kindle with sound; no real sound in the emulator)
    require("gzreader_touch").player = function() return true end
    local Engine = require("gzreader_audioengine")
    Engine.chosen = function(fmt) return { id = "emu-" .. tostring(fmt) } end
    Engine.play = function(_p, src) return true, src.offset_ms end
    Engine.running = function() return true end
    Engine.stop = function() end
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 3 })
add({ shot = "nopen-1-question" })
add({ fn = function(E)
    local d = top()
    E.say("nopen: question", tostring(d and d.title))
    check(d and d.title and d.title:find("has its own narration", 1, true) and press("Read with narration"),
        "opening a narrated book: asked Read / Read with narration / Listen as audiobook")
end, after = 14 })
add({ shot = "nopen-2-narration" })
add({ fn = function(E)
    local N = require("gzreader_narration")
    check(reader() ~= nil and N.playingIn(reader()), "Read with narration: the book open, its narration playing")
    -- the quick panel's Read aloud is the narration here: a tap stops it
    local Panel = require("gzreader_panel")
    local tiles = Panel.bookTiles and Panel.bookTiles(reader().gzreader, reader()) or {}
    local ra
    for _i, t in ipairs(tiles) do if t.id == "readaloud" then ra = t end end
    E.say("nopen: read aloud tile", tostring(ra and ra.label), tostring(ra and ra.on))
    local narr
    for _i, t in ipairs(tiles) do if t.id == "narration" then narr = t end end
    check(ra and ra.on == true and narr == nil, "the quick panel: one Read aloud tile, on while the narration plays")
    if ra then ra.run() end
    check(not N.playingIn(reader()), "Read aloud tapped: the narration stopped")
end, after = 2 })
add({ fn = function(E)
    -- Listen as audiobook (from Home): the book's own narration as an audiobook
    reader():onHome()
end, after = 6 })
add({ fn = function(E)
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 3 })
add({ fn = function(E) check(press("Listen as audiobook"), "Listen as audiobook chosen") end, after = 1 })
add({ fn = function(E) end, after = 7 })
add({ shot = "nopen-3-audiobook" })
add({ fn = function(E)
    local cur
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.player then cur = w.widget.player end end
    E.say("nopen: audiobook", tostring(cur and cur.book.id), tostring(cur and #cur.book.chapters))
    check(cur and cur.book.id:match("^narr%-") and #cur.book.chapters == 2 and cur.book.chapters[2].title == "Chapter 2"
        and cur.book.chapters[2].startTimeMs == 12000, "the audiobook player: the book's narration, its chapters from the book's contents")
    if cur then pcall(cur.stop, cur) end
    local f = io.open(E.out .. "/narrated-open-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
