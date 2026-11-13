-- Drawings in the Notes tab: on the board's cards (Compact and Full) and on
-- the note's page, as big as there's room for, under the note's heading.
-- Two notes are put in Memos first (demo/mock_memos.py --sample on 18090):
-- "# Garden plan" + text + a small drawing made by GZreader, and a note that's
-- only a big drawing made in memos' web app.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_drawings.lua <out>
-- GZ_DRAWING_SMALL / GZ_DRAWING_BIG: the PNGs (default: tests/media's).
-- Checks go to <out>/notes-drawings-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."
local MEDIA = here .. "/../tests/media/"
local SMALL = os.getenv("GZ_DRAWING_SMALL") or (MEDIA .. "memos-drawing.canvas.png")
local BIG = os.getenv("GZ_DRAWING_BIG") or (MEDIA .. "memos-drawing.canvas.png")
local garden

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local Memos = require("gzreader_memos")
    local c = Memos:new(p.store.memos)
    local m1 = c:create("Only a drawing? No: this one has no heading, just a line.", "PRIVATE")
    local a1 = m1 and c:uploadAttachment(BIG, "drawing-20261111-222305.canvas.png", m1.name)
    garden = c:create("# Garden plan\nBeds by the fence, tomatoes on the left. #garden", "PRIVATE")
    local a2 = garden and c:uploadAttachment(SMALL, "drawing-20261112-195442.canvas.png", garden.name)
    check(m1 and a1 and garden and a2, "two notes with drawings in Memos")
    E.say("small", SMALL, "big", BIG)
    local Notes = require("gzreader_notes")
    Notes.setView(p, "columns", "two")
    Notes.setView(p, "display", "compact")
    Notes.show(p)
end, after = 6 })
add({ fn = function(E)
    -- (the board fetched the drawings it shows, then drew itself again)
    local Notes = require("gzreader_notes")
    local Memos = require("gzreader_memos")
    local lfs = require("libs/libkoreader-lfs")
    local got = 0
    for _i, m in ipairs(Notes.notes or {}) do
        for _j, a in ipairs(m.attachments or {}) do
            if Notes.isDrawing(a) and lfs.attributes(Memos.filePath(a), "mode") == "file" then got = got + 1 end
        end
    end
    check(got >= 2, "the board downloaded the drawings by itself (" .. got .. ")")
end, after = 1 })
add({ shot = "1-board-compact", after = 1 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local m
    for _i, n in ipairs(Notes.notes or {}) do if n.name == garden.name then m = n end end
    check(m ~= nil, "the garden note is on the board")
    Notes.showNote(plugin(), m)
end, after = 3 })
add({ shot = "2-note-page", after = 1 })
add({ fn = function(E)
    local v = top()
    local n_att = 0
    for _i, pk in ipairs(v.picks or {}) do if pk.att then n_att = n_att + 1 end end
    check(n_att == 1, "the note's page: the drawing is one of its picks (a tap opens it), not a row under Attachments")
    UIM():close(v)
    local Notes = require("gzreader_notes")
    local m1
    for _i, n in ipairs(Notes.notes or {}) do
        if (n.content or ""):match("^Only a drawing") then m1 = n end
    end
    Notes.showNote(plugin(), m1)
end, after = 3 })
add({ shot = "3-note-page-big", after = 1 })
add({ fn = function(E)
    UIM():close(top())
    local Notes = require("gzreader_notes")
    Notes.setView(plugin(), "display", "full")
end, after = 5 })
add({ shot = "4-board-full", after = 1 })
-- Edit on the note with memos' big drawing: the drawing opens, scaled to fit, its shapes and text kept
local big, big_att, big_before
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    Notes.setView(plugin(), "display", "compact")
    for _i, n in ipairs(Notes.notes or {}) do
        if (n.content or ""):match("^Only a drawing") then big = n end
    end
    big_att = big and Notes.drawings(big)[1]
    local Memos = require("gzreader_memos")
    local f = big_att and io.open(Memos.filePath(big_att), "rb")
    big_before = f and f:read("*a")
    if f then f:close() end
    Notes.edit(plugin(), big)
end, after = 4 })
add({ shot = "5-edit-opens-the-drawing", after = 1 })
add({ fn = function(E)
    local d = top()
    local sk = d and d.sketch
    check(d and d.name == "gz_drawscreen" and sk and #sk.strokes == 6 and #sk.locked == 2,
        "Edit on a note with a drawing opens the drawing: its 6 strokes, its ellipse and text kept")
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.finger({ { math.floor(W * 0.2), math.floor(H * 0.85) }, { math.floor(W * 0.5), math.floor(H * 0.9) }, { math.floor(W * 0.8), math.floor(H * 0.85) } }, 0.4)
end, after = 2 })
add({ shot = "6-edited", after = 0.5 })
add({ fn = function(E)
    local d = top()
    for _i, b in ipairs(d.buttons) do
        if b.tool.id == "done" then E.tap({ b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) }) end
    end
end, after = 3 })
add({ fn = function(E)
    local e
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.input and w.widget.on_save then e = w.widget end end
    check(e and e.drawing and e.drawing.path and e:hasDrawing(), "Done: back in the note's editor with the edited drawing")
    if e then e:save() end
end, after = 1 })
add({ wait_for = function() local q = plugin().store.memos.queue; return q and #q == 0 end, timeout = 25 })
add({ fn = function(E)
    local Memos = require("gzreader_memos")
    local c = Memos:new(plugin().store.memos)
    local list = c:list(nil, nil, 50)
    local now
    for _i, m in ipairs(list and list.memos or {}) do if m.name == big.name then now = m end end
    local same = now and #now.attachments == 1 and now.attachments[1].name == big_att.name
    local tmp = E.out .. "/big-after.png"
    local got = same and c:download(now.attachments[1], tmp)
    local f = got and io.open(tmp, "rb")
    local after = f and f:read("*a")
    if f then f:close() end
    local scene = after and require("gzreader_drawing").readScene(after)
    check(same and after and after ~= big_before and scene and #scene.elements == 9,
        "sent: the same attachment in Memos, its file replaced, 9 elements (8 kept + the new stroke)")
end, after = 0.5 })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-drawings-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
