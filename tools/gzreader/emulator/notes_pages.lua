-- Drawings with pages and notepaper, on a touch Kindle: the Notes tab's Draw
-- button opens a new note on a page to draw on; Paper puts it on College
-- ruled; + New page adds a second page (on the same paper), Paper turns it
-- to Graph; a third on Dot grid, with a stroke off the paper's edge (it stops
-- there); ◀ ▶ go between them; Done, a title, Save: Memos gets one note with
-- three drawings in page order, each with its paper as Memos keeps a
-- background. Then Edit opens the three pages again, in order.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_pages.lua <out>
-- Checks go to <out>/notes-pages-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function chip(label)
    local N = require("gzreader_notes")
    local row = N.board and N.board.title_bar and N.board.title_bar._gz_action_row
    for _i, w in ipairs(row or {}) do
        if w.dimen and w.text == label then return { w.dimen.x + math.floor(w.dimen.w / 2), w.dimen.y + math.floor(w.dimen.h / 2) } end
    end
end
local function stroke(E, x1, y1, x2, y2)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.finger({ { math.floor(W * x1), math.floor(H * y1) }, { math.floor(W * (x1 + x2) / 2), math.floor(H * (y1 + y2) / 2 + 20) },
        { math.floor(W * x2), math.floor(H * y2) } }, 0.4)
end
local TITLE = "Two pages of notes"

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    G_reader_settings:delSetting("gzreader_drawing_paper")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ shot = "1-board", after = 0.5 })
add({ fn = function(E)
    check(chip("Note") and chip("Draw"), "the Notes tab has Note and Draw")
    -- (is the text page drawn before the drawing screen? count its paints)
    local Ed = require("gzreader_noteeditor").Editor
    local paint = Ed.paintTo
    E.editor_paints = 0
    Ed.paintTo = function(w, ...) E.editor_paints = E.editor_paints + 1; return paint(w, ...) end
    E.restore_paint = function() Ed.paintTo = paint end
    E.tap(chip("Draw"))
end, after = 4 })
add({ shot = "2-draw-opens-a-page", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local e = editor()
    E.restore_paint()
    check(d and top() == d and #d.pages == 1 and d.sketch:paper() == "blank" and e and not e.input:isKeyboardVisible()
        and E.editor_paints == 0,
        "Draw: a new note on a page to draw on (blank), the drawing screen up at once (the text page not drawn first, no keyboard) ("
        .. E.editor_paints .. " paints of the text page)")
    E.tap(button("paper"))
end, after = 2 })
add({ shot = "3-paper-list", after = 0.5 })
add({ fn = function(E) E.tap("College ruled") end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d.sketch:paper() == "college" and d.color_bb ~= nil, "Paper → College ruled: the page on it")
    stroke(E, 0.2, 0.3, 0.7, 0.32)
end, after = 2 })
add({ shot = "4-college", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 1, "drawn on the paper")
    E.tap(button("newpage"))
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(#d.pages == 2 and d.index == 2 and d.sketch:paper() == "college" and d.sketch:isEmpty(),
        "+ New page: a second page, on the last paper chosen")
    E.tap(button("paper"))
end, after = 2 })
add({ fn = function(E) E.tap("Graph") end, after = 4 })
add({ fn = function(E)
    stroke(E, 0.3, 0.5, 0.6, 0.7)
end, after = 2 })
add({ shot = "5-graph-page-2", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d.sketch:paper() == "graph" and #d.sketch:live() == 1, "page 2 on Graph, drawn on")
    E.tap(button("newpage"))
end, after = 4 })
add({ fn = function(E) E.tap(button("paper")) end, after = 2 })
add({ fn = function(E) E.tap("Dot grid") end, after = 4 })
add({ fn = function(E)
    -- from the middle of the page off its right edge (and the screen's)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.finger({ { math.floor(W * 0.5), math.floor(H * 0.6) }, { math.floor(W * 0.8), math.floor(H * 0.6) },
        { W - 3, math.floor(H * 0.6) } }, 0.4)
end, after = 2 })
add({ shot = "6-dots-edge", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local page = d.sketch:pageRect()
    local maxx = 0
    for _i, st in ipairs(d.sketch:live()) do for _j, p in ipairs(st.points) do maxx = math.max(maxx, p[1]) end end
    check(d.index == 3 and d.sketch:paper() == "dots" and #d.sketch:live() == 1 and page and maxx <= page.x + page.w,
        "page 3 on Dot grid: a stroke off the paper's edge stops at it (" .. math.floor(maxx) .. " ≤ " .. math.floor(page and page.x + page.w or 0) .. ")")
    E.tap(button("prev"))
end, after = 4 })
add({ fn = function(E) E.tap(button("prev")) end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d.index == 1 and d.sketch:paper() == "college" and #d.sketch:live() == 1, "◀ ◀: back to page 1, as it was")
    E.tap(button("done"))
end, after = 4 })
add({ shot = "7-editor", after = 0.5 })
add({ fn = function(E)
    local e = editor()
    check(e and not screen() and #e.pages == 3 and e:drawingLabel():match("3") and e.pages[1].path and e.pages[3].path,
        "Done: the note's editor, Drawings (3)")
    local Drawing = require("gzreader_drawing")
    local Notepaper = require("gzreader_notepaper")
    local s1 = e.pages[1].path and Drawing.readFile(e.pages[1].path)
    local s2 = e.pages[2].path and Drawing.readFile(e.pages[2].path)
    local b1, b2 = s1 and Notepaper.background(s1), s2 and Notepaper.background(s2)
    check(b1 and b2 and Notepaper.idOf(s1, b1) == "college" and Notepaper.idOf(s2, b2) == "graph",
        "each page's file: its paper as Memos keeps a background, then its stroke")
    for i = 1, 3 do os.execute("cp '" .. e.pages[i].path .. "' '" .. E.out .. "/page-" .. i .. ".canvas.png'") end
    e.input:setText("# " .. TITLE)
    e:save()
end, after = 1 })
add({ wait_for = function() local q = plugin().store.memos.queue; return q and #q == 0 end, timeout = 30 })
add({ fn = function(E)
    local c = require("gzreader_memos"):new(plugin().store.memos)
    local list = c:list(nil, nil, 50)
    local note
    for _i, m in ipairs(list and list.memos or {}) do if m.content == "# " .. TITLE then note = m end end
    -- in Memos, in page order (Memos lists a note's attachments newest first: GZreader puts them back)
    local papers = {}
    local Drawing = require("gzreader_drawing")
    local Notepaper = require("gzreader_notepaper")
    for i, a in ipairs(note and note.attachments or {}) do
        local tmp = E.out .. "/memos-" .. i .. ".png"
        local sc = c:download(a, tmp) and Drawing.readFile(tmp)
        local bg = sc and Notepaper.background(sc)
        papers[i] = bg and Notepaper.idOf(sc, bg) or "?"
    end
    check(note and #note.attachments == 3 and table.concat(papers, ",") == "college,graph,dots",
        "Save: one note in Memos with its three drawings, in page order (" .. table.concat(papers, ",") .. ")")
    E.note = note
    local Notes = require("gzreader_notes")
    Notes.refresh(plugin(), function() end)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    for _i, m in ipairs(Notes.notes or {}) do if m.name == E.note.name then Notes.edit(plugin(), m) end end
end, after = 6 })
add({ shot = "7-edit-opens-pages", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d and #d.pages == 3 and d.sketch:paper() == "college" and #d.sketch:live() == 1,
        "Edit: the note's three drawings open as its pages, in order (page 1 on College ruled)")
    E.tap(button("next"))
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d and d.index == 2 and d.sketch:paper() == "graph", "▶: page 2, on Graph")
    E.tap(button("cancel"))
end, after = 3 })
add({ fn = function(E)
    local f = io.open(E.out .. "/notes-pages-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
