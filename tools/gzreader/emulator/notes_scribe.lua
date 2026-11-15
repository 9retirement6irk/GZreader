-- The Notes tab's screens after the Scribe / reMarkable rework, on a touch
-- Kindle: the home (Note, Draw, Journal and icons in one row; tag chips;
-- Drawings; scrolling up and down instead of pages), the
-- drawing screen (side toolbar, pen thickness, undo / redo, the toolbar on the
-- other side, hidden; the page pill), All pages (add, duplicate, move,
-- delete), the Paper picker, the editor (formatting bar at the selection, the
-- sheets strip), and a journal entry as Memos' journaling mode writes them.
--   python3 -I demo/mock_memos.py 18090 --sample --spaces --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_scribe.lua <out>
-- Checks go to <out>/notes-scribe-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function named(name)
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end
end
local function screen() return named("gz_drawscreen") end
local function journal() return named("gz_journal") end
local function grid()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.kind == "pages" or w.widget.kind == "papers" then return w.widget end end
end
local function editor()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then return w.widget end end
end
local function mid(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do if b.tool.id == id then return mid(b.rect) end end
end
local function chip(label)
    for _r, row in ipairs(N().board and N().board.title_bar and N().board.title_bar._gz_action_rows or {}) do
        for _i, w in ipairs(row) do if w.dimen and (w.text == label or w.gz_label == label) then return mid(w.dimen), w end end
    end
end
local function jb(id) local b = journal() and journal().buttons[id]; return b and mid(b.dimen) end
local function stroke(E, x1, y1, x2, y2)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.finger({ { math.floor(W * x1), math.floor(H * y1) }, { math.floor(W * (x1 + x2) / 2), math.floor(H * (y1 + y2) / 2 + 20) },
        { math.floor(W * x2), math.floor(H * y2) } }, 0.4)
end
local function state()
    local http = require("socket.http")
    local body = http.request("http://127.0.0.1:18090/__state")
    return require("json").decode(body)
end
local function shot(name) add({ shot = name, after = 0.5 }) end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    G_reader_settings:delSetting("gzreader_drawing_paper")
    G_reader_settings:delSetting("gzreader_drawing_toolbar_side")
    G_reader_settings:delSetting("gzreader_drawing_width")
    N().show(p)
end, after = 8 })
shot("01-home")
add({ fn = function(E)
    local all = select(2, chip("All"))
    local note = select(2, chip("Note"))
    check(chip("Draw") and chip("Journal") and note and note.gz_icon and chip("Sort") and chip("Filter") and chip("Layout") and chip("Search")
        and chip("Full screen") and chip("Drawings") and all and all.gz_chosen and #N().board.title_bar._gz_action_rows == 2,
        "home, two rows: Note, Draw, Journal (with pictures) and icons for Sort, Filter, Layout, Search, Full screen; then All (chosen), your tags, Drawings")
    local js = plugin().store.memos.journal
    check(js and js.space == "spaces/family" and #js.goals == 2, "the sync brought your journal settings from Memos")
    E.tap(chip("Drawings"))
end, after = 4 })
shot("02-home-drawings")
add({ fn = function(E)
    local dr = select(2, chip("Drawings"))
    check(N().filter.kind == "drawings" and dr and dr.gz_chosen and N().title():match("Drawings"), "Drawings: only the notes with a drawing (the chip chosen)")
    E.tap(chip("All"))
end, after = 4 })

-- Layout → Scroll up and down: the board moves by rows with a swipe up or down
add({ fn = function(E)
    E.pages_first = N().board._gz_first
    N().setScrolling(plugin(), true)
end, after = 4 })
shot("02a-home-scrolling")
add({ fn = function(E)
    local b = N().board
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    local sc = b._gz_scroll
    check(sc ~= nil and b._gz_y == 0 and #b.page_info == 0 and b.page_num == 1, "Layout → Scroll up and down: one long page, no page number or arrows under it")
    local rows = b.item_group[1][1]
    check(#rows == sc.rows + 1 and sc.cell_h * (sc.rows + 1) > sc.view_h, "…a part of the next row of notes shows at the bottom (" .. #rows .. " rows drawn, " .. sc.rows .. " fit)")
    E.finger({ { W * 0.5, H * 0.75 }, { W * 0.5, H * 0.75 - 130 }, { W * 0.5, H * 0.75 - 260 } }, 0.15)
end, after = 4 })
shot("02b-home-scrolled")
add({ fn = function(E)
    local b = N().board
    check(b._gz_y > 200 and b._gz_y < 330 and b._gz_scroll.shift == b._gz_y, "a swipe up of 260 px: the notes moved up as far (" .. b._gz_y .. " px), the first row cut off at the top")
    -- a note still opens by a tap where it's drawn
    local item = b.item_group[1][1][2][1]
    E.tap({ item.dimen.x + math.floor(item.dimen.w / 2), item.dimen.y + math.floor(item.dimen.h / 2) })
end, after = 5 })
add({ fn = function(E)
    local v = top()
    check(v ~= N().board and v.memo ~= nil, "a tap on a note opens it")
    UIM():close(v)
end, after = 4 })
add({ fn = function(E)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.finger({ { W * 0.5, H * 0.4 }, { W * 0.5, H * 0.4 + 300 }, { W * 0.5, H * 0.4 + 600 } }, 0.15)
end, after = 4 })
add({ fn = function(E)
    check(N().board._gz_y == 0 and top() == N().board, "a swipe down: back to the top (the tab stays open)")
    N().setScrolling(plugin(), false)
end, after = 4 })
add({ fn = function(E) check(#N().board.page_info > 0 and N().board._gz_scroll == nil, "scrolling off: pages, with their number and arrows") end, after = 1 })

-- a journal entry
add({ fn = function(E) E.tap(chip("Journal")) end, after = 4 })
shot("03-journal")
add({ fn = function(E)
    local j = journal()
    check(j and top() == j and j.buttons["mood-1"] and j.buttons["did-walk"] and j.buttons["goals"] and not j.buttons["felt-grateful"],
        "Journal: the mood steps, your activities and goals (feeling words come with a step)")
    E.tap(jb("mood-6"))
end, after = 3 })
add({ fn = function(E)
    check(journal().state.valence == "pleasant" and jb("felt-grateful") ~= nil, "a step chosen: Pleasant, and the words nearest it")
    E.tap(jb("felt-grateful"))
end, after = 3 })
add({ fn = function(E) E.tap(jb("kind-now")) end, after = 3 })
add({ fn = function(E) E.tap(jb("did-walk")) end, after = 3 })
add({ fn = function(E) E.tap(jb("impact")) end, after = 3 })
shot("04-journal-impact")
add({ fn = function(E) E.tap("Family") end, after = 3 })
add({ fn = function(E) E.tap("Done") end, after = 3 })
add({ fn = function(E) E.tap(jb("goals")) end, after = 3 })
add({ fn = function(E) E.tap("Stretch") end, after = 3 })
add({ fn = function(E) E.tap("Done") end, after = 3 })
add({ fn = function(E) E.tap(jb("prompt")) end, after = 3 })
add({ fn = function(E) E.tap(jb("write")) end, after = 4 })
add({ fn = function()
    local j = journal()
    check(j.writer ~= nil, "Write about it: a box to write in, titled with the prompt")
    j.writer:addTextToInput("Sun on the porch.")
end, after = 2 })
shot("05-journal-write")
add({ fn = function(E) E.tap("Done") end, after = 4 })
shot("06-journal-filled")
add({ fn = function(E)
    local j = journal()
    E.entry = j:content()
    check(E.entry:match("^> [^\n]+%?\n\nSun on the porch%.\n\n%- %[ %] Read 20 pages\n%- %[x%] Stretch\n\n#mood/pleasant #mood/now #felt/grateful #impact/family #did/walk\n$") ~= nil,
        "the entry: the prompt, the words, the goals, then the mood and activity tags: " .. E.entry:gsub("\n", "\\n"))
    E.tap(jb("save"))
end, after = 8 })
shot("07-journal-saved")
add({ fn = function(E)
    local found
    for _i, m in ipairs(state().memos) do if m.content == E.entry then found = m end end
    check(not journal() and found and found.visibility == "PRIVATE" and found.space == "spaces/family",
        "Save: Memos has the entry, private, in your journal space")
    E.tap(chip("Draw"))
end, after = 5 })

-- the drawing screen
shot("08-sheet")
add({ fn = function(E)
    local d = screen()
    check(d and top() == d and button("pen") and button("eraser") and button("undo") and button("redo") and button("paper")
        and button("pages") and button("side") and button("hide") and button("prev") and button("next") and button("newpage")
        and button("cancel") and button("done"),
        "Draw: the drawing screen: Close and Done above; pen, eraser, undo, redo, paper, all pages at the side; the page pill below")
    E.left_x = button("pen")[1]
    stroke(E, 0.3, 0.3, 0.7, 0.32)
end, after = 2 })
add({ fn = function(E) E.tap(button("pen")) end, after = 2 })
shot("09-pen-thickness")
add({ fn = function(E)
    check(screen().flyout == "pen" and button("w0.5") and button("w7") and not button("c-red"),
        "the pen again: its thicknesses, five of them (no colours on a black-and-white screen)")
    E.tap(button("w7"))
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.flyout == nil and d.sketch.width == 7 and G_reader_settings:readSetting("gzreader_drawing_width") == 7,
        "the thickest: chosen (and kept for next time), the choices away")
    stroke(E, 0.3, 0.5, 0.7, 0.55)
end, after = 2 })
add({ fn = function(E)
    local live = screen().sketch:live()
    check(#live == 2 and live[2].width == 7 and live[1].width ~= 7, "the next stroke is that thick")
    E.tap(button("undo"))
end, after = 2 })
add({ fn = function(E)
    check(#screen().sketch:live() == 1 and screen().sketch:canRedo(), "Undo takes it back")
    E.tap(button("redo"))
end, after = 2 })
add({ fn = function(E)
    check(#screen().sketch:live() == 2 and not screen().sketch:canRedo(), "Redo brings it back")
    -- ink never lands under the toolbar: a drag that starts on it draws nothing
    local p = button("eraser")
    E.finger({ p, { p[1] + 200, p[2] + 40 }, { p[1] + 400, p[2] + 60 } }, 0.4)
end, after = 2 })
add({ fn = function(E)
    check(#screen().sketch:live() == 2, "a drag that starts on the toolbar draws nothing")
    E.tap(button("side"))
end, after = 3 })
shot("10-toolbar-right")
add({ fn = function(E)
    check(button("pen")[1] > E.left_x + 400 and G_reader_settings:readSetting("gzreader_drawing_toolbar_side") == "right",
        "the toolbar on the other side (for the other hand), kept for next time")
    E.tap(button("hide"))
end, after = 3 })
shot("11-toolbar-hidden")
add({ fn = function(E)
    check(screen().toolbar_hidden and not button("pen") and button("show"), "hidden: only a small button to bring it back")
    E.tap(button("show"))
end, after = 3 })
add({ fn = function(E) E.tap(button("side")) end, after = 3 })
add({ fn = function(E)
    check(not screen().has_color, "a black-and-white screen: no colours in the pen's choices")
end, after = 1 })
add({ fn = function(E) E.tap(button("newpage")) end, after = 3 })
add({ fn = function(E) stroke(E, 0.3, 0.3, 0.6, 0.6) end, after = 2 })
add({ fn = function(E) E.tap(button("paper")) end, after = 4 })
shot("12-paper")
add({ fn = function(E)
    local g = grid()
    local ids = {}
    for i, p in ipairs(g and g.papers or {}) do ids[i] = p.id end
    check(g and g.kind == "papers" and table.concat(ids, ","):match("^blank,college,wide,gregg,dots,graph") ~= nil,
        "Paper: every paper pictured: " .. table.concat(ids, ","))
    E.tap("Graph")
end, after = 4 })
add({ fn = function(E)
    check(not grid() and screen().sketch:paper() == "graph", "a tap picks it: page 2 on Graph")
    E.tap(button("pages"))
end, after = 4 })
shot("13-all-pages")
add({ fn = function(E)
    local g = grid()
    check(g and g.kind == "pages" and #screen().pages == 2 and g.selected() == 2, "All pages: both, the one you were on chosen")
    E.tap("Duplicate")
end, after = 4 })
add({ fn = function(E)
    check(#screen().pages == 3 and grid().selected() == 3, "Duplicate: a copy after it, chosen")
    E.tap("\u{25C0} Move")
end, after = 4 })
add({ fn = function(E)
    check(grid().selected() == 2 and screen().reordered, "◀ Move: it's page 2 now")
    E.tap("+ Add after")
end, after = 4 })
add({ fn = function(E)
    check(#screen().pages == 4 and grid().selected() == 3, "+ Add after: a new page 3")
    E.tap("Delete")
end, after = 3 })
shot("14-delete-page")
add({ fn = function(E) E.tap("Delete the page") end, after = 4 })
shot("15-pages-after")
add({ fn = function(E)
    check(#screen().pages == 3, "Delete (after asking): three pages again")
    E.tap("Back")
end, after = 4 })
add({ fn = function(E)
    check(not grid() and top() == screen(), "Back: the drawing screen again")
    E.tap(button("done"))
end, after = 5 })
shot("16-editor-strip")
add({ fn = function(E)
    local e = editor()
    check(e and not screen() and e.rich and #e:sheets() == 3 and e.strip and e.strip.thumbs == 3 and e.strip.label:match("3 sheets"),
        "Done: the note's editor, its three sheets pictured in a strip (" .. tostring(e and e.strip and e.strip.label) .. ")")
    e.input:addChars("Trip plan for the weekend")
end, after = 3 })
add({ fn = function(E)
    local e = editor()
    local d = e.input.dimen
    E.hold({ d.x + 30, d.y + 16 })
end, after = 3 })
shot("17-format-bar")
add({ fn = function(E)
    local r = editor().input
    local rect = r:barRect()
    check(r.bar_open and rect and r:selection(), "hold a word: it's selected and the formatting bar comes up at it")
    E.tap({ r.dimen.x + rect.x + rect.cell * 2 + math.floor(rect.cell / 2), r.dimen.y + rect.y + math.floor(rect.h / 2) })
end, after = 3 })
shot("18-heading")
add({ fn = function(E)
    local e = editor()
    check(e:text():match("^# Trip plan for the weekend") ~= nil and e.input.bar_open, "H on the bar: the line is a heading (the bar stays for more)")
    e:save()
end, after = 9 })
shot("19-saved")
add({ fn = function(E)
    local made
    for _i, m in ipairs(state().memos) do if m.content:match("^# Trip plan for the weekend") then made = m end end
    local names = {}
    for i, a in ipairs(made and made.attachments or {}) do names[i] = a.filename end
    check(made and #names == 3, "Save: Memos has the note with its three sheets (" .. #names .. ")")
    E.made = made and made.name
    -- its pages in the order they had on the Kindle
    local Drawing, Notepaper, Memos = require("gzreader_drawing"), require("gzreader_notepaper"), require("gzreader_memos")
    local papers = {}
    for _i, n in ipairs(N().notes or {}) do
        if n.name == E.made then
            for i, a in ipairs(N().drawings(n)) do
                local scene = Drawing.readFile(Memos.filePath(a))
                local bg = scene and Notepaper.background(scene)
                papers[i] = bg and Notepaper.idOf(scene, bg) or "blank"
            end
        end
    end
    check(table.concat(papers, ",") == "blank,graph,graph", "…in page order: the first sheet, the copy moved before, then the Graph page (" .. table.concat(papers, ",") .. ")")
end, after = 1 })

-- a colour screen (a Kindle Colorsoft; stood in for here: this panel is grey): the pen has colours
add({ fn = function(E)
    local Screen = require("device").screen
    E.real_color = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    G_reader_settings:delSetting("gzreader_drawing_color")
    G_reader_settings:saveSetting("gzreader_drawing_paper", "blank")
    require("gzreader_drawscreen").show{ title = "Colours", on_done = function(res) E.colour_pages = res end }
end, after = 5 })
add({ fn = function(E)
    local d = screen()
    check(d and d.has_color and d.color == nil, "a colour screen: the drawing screen starts in memos' ink")
    stroke(E, 0.3, 0.3, 0.7, 0.3)
end, after = 2 })
add({ fn = function(E) E.tap(button("pen")) end, after = 2 })
shot("20-pen-colours")
add({ fn = function(E)
    check(button("c-ink") and button("c-red") and button("c-violet") and button("w7"), "the pen again: thicknesses, and under them eight colours")
    E.tap(button("c-red"))
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.flyout == nil and d.color == "#e03131" and d.sketch.color == "#e03131" and G_reader_settings:readSetting("gzreader_drawing_color") == "#e03131",
        "red: chosen (and kept for next time), the choices away")
    stroke(E, 0.3, 0.5, 0.7, 0.5)
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    local live = d.sketch:live()
    check(#live == 2 and live[1].color == nil and live[2].color == "#e03131" and d.tint_bb ~= nil, "the next stroke is red; the first stays ink")
    E.tap(button("newpage"))
end, after = 3 })
add({ fn = function(E)
    check(screen().sketch.color == "#e03131", "a new page keeps the pen's colour")
    E.tap(button("prev"))
end, after = 3 })
add({ fn = function(E) E.tap(button("done")) end, after = 5 })
add({ fn = function(E)
    local Screen = require("device").screen
    Screen.isColorEnabled = E.real_color
    local res = E.colour_pages or {}
    local page = res[1]
    check(page and page.path, "Done: the page is kept")
    local Drawing = require("gzreader_drawing")
    local scene = page and Drawing.readFile(page.path)
    local cols = {}
    for _i, el in ipairs(scene and scene.elements or {}) do if el.type == "freedraw" then cols[#cols + 1] = el.strokeColor end end
    check(table.concat(cols, ",") == "#1a1a1a,#e03131", "the drawing has the strokes' colours, as Memos writes them: " .. table.concat(cols, ","))
    -- the PNG: a red pixel on the red stroke's line, an ink one on the first
    local reds, inks = 0, 0
    local ok, err = pcall(function()
        local bb = require("ui/renderimage"):renderImageFile(page.path, false)
        for y = 0, bb:getHeight() - 1, 2 do
            for x = 0, bb:getWidth() - 1, 2 do
                local c = bb:getPixel(x, y):getColorRGB32()
                if c.r > 200 and c.g < 80 and c.b < 80 then reds = reds + 1 end
                if c.r < 40 and c.g < 40 and c.b < 40 then inks = inks + 1 end
            end
        end
        bb:free()
    end)
    check(ok and reds > 20 and inks > 20, "the picture Memos shows has the red stroke in red and the first in ink (" .. reds .. " red, " .. inks .. " ink" .. (ok and "" or (", " .. tostring(err))) .. ")")
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then UIM():close(w.widget) end end
    local f = io.open(E.out .. "/notes-scribe-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
