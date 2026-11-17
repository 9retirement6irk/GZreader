-- Split view (gzreader_splitview.lua): on a big screen, the quick panel's
-- "Notes beside the book" puts the book in one half and a page for notes in
-- the other. Upright (the Scribe): the book on top, the notes under it. The
-- pen draws in the notes; a swipe on the book turns its page, and the notes
-- stay; Done saves the note and the book has the whole screen again.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_BOOK=<epub> GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh split_view.lua <out>
-- Checks go to <out>/split-view-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local r = require("apps/reader/readerui").instance; return r and r.gzreader end
local function rui() return require("apps/reader/readerui").instance end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local W, H
local Split
local LAND = os.getenv("GZ_SPLIT_LANDSCAPE") == "1"
--- A point on the screen as the touch panel reports it (turned clockwise: the panel isn't).
local function raw(x, y)
    if LAND then return y, W - x end
    return x, y
end
local function P(x, y) local rx, ry = raw(x, y); return { rx, ry } end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return P(d.ox + b.rect.x + math.floor(b.rect.w / 2), d.oy + b.rect.y + math.floor(b.rect.h / 2)) end
    end
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/split.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/split.epub")
end, after = 8 })
add({ fn = function(E)
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    G_reader_settings:saveSetting("gzreader_drawing_paper", "ruled-medium")
    rui():handleEvent(require("ui/event"):new("GotoViewRel", 2))
    -- GZ_SPLIT_LANDSCAPE=1: the screen on its side (the book at the left, the notes at the right)
    if os.getenv("GZ_SPLIT_LANDSCAPE") == "1" then
        rui():handleEvent(require("ui/event"):new("SetRotationMode", 1))
    end
end, after = 5 })
add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.say("screen", W, H)
end, after = 1 })
add({ fn = function(E)
    Split = require("gzreader_splitview")
    E.page0 = rui().document:getCurrentPage()
    E.pages0 = rui().document:getPageCount()
    local tiles = {}
    for _i, t in ipairs(require("gzreader_panel").readerTiles and require("gzreader_panel").readerTiles(plugin(), rui()) or {}) do tiles[#tiles + 1] = t.id end
    check(Split.available() and Split.tile(plugin()) ~= nil, "a big touch screen, Memos connected: Notes beside the book is offered (" .. table.concat(tiles, ",") .. ")")
    local ok, why = Split.open(plugin())
    E.opened = ok
    check(ok == true, "it opens (" .. tostring(why) .. ")")
end, after = 6 })
add({ shot = "1-split", after = 0.5 })
add({ fn = function(E)
    local d, r = screen(), rui()
    local b, p = Split.rects(W, H)
    check(d and d.pane and d.pane.x == p.x and d.pane.y == p.y and d.pane.w == p.w and d.pane.h == p.h and d.dimen.x == p.x and d.dimen.y == p.y
        and d.canvas.w == p.w and d.canvas.h == p.h and not d.covers_fullscreen and (p.x > 0) == (W > H),
        "the notes in the " .. (W > H and "right" or "lower") .. " half (at " .. p.x .. "," .. p.y .. ", " .. p.w .. "x" .. p.h .. "), the book not covered")
    check(r.dimen.w == b.w and r.dimen.h == b.h and r.view.dimen.h == b.h and r.view.dimen.w == b.w and r.document:getPageCount() > E.pages0,
        "the book laid out again in the " .. (W > H and "left" or "upper") .. " half (" .. r.view.dimen.w .. "x" .. r.view.dimen.h .. "; " .. E.pages0
            .. " pages became " .. r.document:getPageCount() .. ")")
    local last
    for _i, bt in ipairs(d.buttons) do if bt.tool.id == "more" then last = bt end end
    check(last and last.rect.y + last.rect.h <= p.h, "every tool fits the pane (the last ends " .. tostring(last and (last.rect.y + last.rect.h)) .. " of " .. p.h .. " down)")
    check(d and d.meta and d.meta.title:find("^Notes on ") ~= nil and d.sketch:paper() == "ruled-medium" and d.sketch.zoomed,
        "the note named for the book (" .. tostring(d and d.meta and d.meta.title) .. "), on the last paper, as wide as the pane")
    -- the pen draws in the notes
    E.pen({ P(p.x + p.w * 0.3, p.y + p.h * 0.5), P(p.x + p.w * 0.5, p.y + p.h * 0.55), P(p.x + p.w * 0.7, p.y + p.h * 0.5) }, 0.4)
    E.book = b
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    local st = d.sketch:live()[1]
    local _, p = Split.rects(W, H)
    -- (the stroke's place on the screen: half way down the pane)
    local mid = st and st.points[math.floor(#st.points / 2 + 0.5)]
    check(#d.sketch:live() == 1 and mid and math.abs(mid[2] - p.h * 0.55) < p.h * 0.08,
        "the pen in the notes: a stroke, where the pen was (" .. tostring(mid and math.floor(mid[2])) .. " of " .. p.h .. " down the pane)")
    E.page1 = rui().document:getCurrentPage()
    -- a swipe on the book turns its page
    local ax, ay = raw(E.book.w * 0.8, E.book.h * 0.4)
    local bx, by = raw(E.book.w * 0.2, E.book.h * 0.4)
    E.swipe(ax, ay, bx, by, 0.2)
end, after = 4 })
add({ shot = "2-page-turned", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local page = rui().document:getCurrentPage()
    check(page > E.page1 and d ~= nil and #d.sketch:live() == 1, "a swipe on the book: its next page (" .. E.page1 .. " to " .. page .. "), the notes still there")
    -- a tap on the book's right side too
    E.tap(P(E.book.w * 0.9, E.book.h * 0.5))
end, after = 4 })
add({ fn = function(E)
    local page = rui().document:getCurrentPage()
    check(screen() ~= nil and #screen().sketch:live() == 1, "a tap on the book: nothing drawn in the notes (book page " .. page .. ")")
    -- the pen on the book doesn't draw
    E.pen({ P(E.book.w * 0.3, E.book.h * 0.4), P(E.book.w * 0.5, E.book.h * 0.42) }, 0.3)
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 1, "the pen on the book: nothing drawn")
    E.penTap(button("done"))
end, after = 6 })
add({ wait_for = function()
    local q = plugin().store.memos.queue
    return q and #q == 0
end, timeout = 25 })
add({ shot = "3-closed", after = 0.5 })
add({ fn = function(E)
    local r = rui()
    check(screen() == nil and Split.active == nil and r.dimen.h == H and r.view.dimen.h == H and r.view.dimen.w == W,
        "Done: the notes closed, the book has the whole screen again (" .. r.view.dimen.h .. " tall)")
    local Memos = require("gzreader_memos")
    local list = Memos:new(plugin().store.memos):list(nil, nil, 20)
    local found
    for _i, m in ipairs(list and list.memos or {}) do if m.content:find("^# Notes on ") then found = m end end
    check(found and #found.attachments == 1, "the note in Memos: " .. tostring(found and found.content) .. ", " .. tostring(found and #found.attachments) .. " drawing")
    local f = io.open(E.out .. "/split-view-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
