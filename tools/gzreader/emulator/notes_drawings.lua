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
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-drawings-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
