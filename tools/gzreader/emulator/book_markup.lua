-- Mark up a book's page (gzreader_bookmarkup.lua): a book (GZ_EMU_BOOK), the
-- quick panel's Mark up page, the drawing screen on the page, a line drawn,
-- Done, Save: the note in Memos (the test suite's mock_memos.py on 18390)
-- with the page under the ink and the book's line in its text.
--   python3 -I demo/mock_memos.py 18390 &
--   GZ_EMU_MODEL=scribe GZ_EMU_BOOK=<epub> GZ_EMU_TREE=<tree>/koreader run.sh book_markup.lua <out>
-- Checks go to <out>/book-markup-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
local function find(test) local st = UIM()._window_stack; for i = #st, 1, -1 do if test(st[i].widget) then return st[i].widget end end end
local function drawing() return find(function(w) return w.name == "gz_drawscreen" end) end
local function editor() return find(function(w) return w.sheetStrip and w.on_save end) end
local SERVER = "http://127.0.0.1:18390"
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = require("apps/filemanager/filemanager").instance.gzreader
    p.store.memos = { server = SERVER, token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 14 })
add({ fn = function(E)
    local Panel = require("gzreader_panel")
    local tiles = Panel.bookTiles(reader().gzreader, reader())
    local tile
    for _i, t in ipairs(tiles) do if t.id == "markup" then tile = t end end
    check(tile ~= nil, "the quick panel in a book has Mark up page")
    if tile then tile.run() end
end, after = 6 })
add({ shot = "markup-1-page" })
add({ fn = function(E)
    local d = drawing()
    check(d ~= nil, "the drawing screen is open")
    local pic
    for _i, el in ipairs(d and d.sketch.locked or {}) do if el.type == "image" then pic = el end end
    check(pic ~= nil and pic.locked == true, "…with the book's page under it as a locked picture")
    -- a line drawn with the pen
    if d then
        local c = d.canvas
        local x, y, w = c.x + (d.ox or 0) + math.floor(c.w * 0.2), c.y + (d.oy or 0) + math.floor(c.h * 0.55), math.floor(c.w * 0.6)
        local pts = {}
        for i = 0, 10 do pts[#pts + 1] = { x + math.floor(w * 0.1 * i), y + math.floor(25 * math.sin(i)) } end
        E.pen(pts, 0.5)
        E.penAway(0.6)
    end
end, after = 3 })
add({ shot = "markup-2-drawn" })
add({ fn = function(E)
    local d = drawing()
    E.say("strokes:", tostring(d and #d.sketch:live()))
    check(d ~= nil and #d.sketch:live() >= 1, "a line drawn over the page")
    local done
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == "done" then done = { b.rect.x + d.ox + math.floor(b.rect.w / 2), b.rect.y + d.oy + math.floor(b.rect.h / 2) } end
    end
    if done then E.penTap(done) end
end, after = 5 })
add({ shot = "markup-3-note" })
add({ fn = function(E)
    local e = editor()
    check(e ~= nil, "Done: the new note's page")
    if e then pcall(e.save, e) end
end, after = 12 })
add({ fn = function(E)
    local p = reader() and reader().gzreader or require("apps/filemanager/filemanager").instance.gzreader
    local q = p.store.memos.queue or {}
    E.say("queue:", #q, tostring(q[1] and q[1].op), tostring(q[1] and q[1].content))
    local page = require("gzreader_memos"):new(p.store.memos):list()
    local note
    for _i, m in ipairs(page and page.memos or {}) do if (m.content or ""):find("Marked up in", 1, true) then note = m end end
    E.say("note:", tostring(note and note.content), "attachments:", tostring(note and #(note.attachments or {})))
    check(note ~= nil and note.content:find("Marked up in *", 1, true) ~= nil, "Save: the note in Memos says which book and page")
    check(note ~= nil and #(note.attachments or {}) >= 1, "…with the drawing attached")
    local f = io.open(E.out .. "/book-markup-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
