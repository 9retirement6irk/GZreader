-- The drawing screen's papers, as the Kindle Scribe's templates: a new
-- drawing asks which paper first (a grid of small square tiles, six to a
-- row, four on a narrow screen; a tap chooses, Create starts the drawing,
-- Cancel leaves), and Paper on the drawing screen opens the same window (a
-- tap chooses, Done takes it). Six papers of your own are added (copies of a paper), after
-- GZreader's eighteen; where the grid is longer than the screen it scrolls.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh paper_list.lua <out>
-- Checks go to <out>/paper-list-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local W, H
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local function list() return find("gz_paperlist") end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function tap(E, p) if PEN then E.penTap(p) else E.tap(p) end end
local function cell(l, id)
    for i, p in ipairs(l.papers) do
        if p.id == id then local d = l.rows[i].dimen; return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 3) }, d end
    end
end
local cancelled = 0

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local NP = require("gzreader_notepaper")
    local dir = NP.ownDir()
    os.execute("mkdir -p '" .. dir .. "'")
    local src = NP.path(NP.get("college"))
    for i = 1, 6 do os.execute(string.format("cp '%s' '%s/Mine %d.png'", src, dir, i)) end
    G_reader_settings:delSetting("gzreader_drawing_paper")
    require("gzreader_drawscreen").show{ title = "Papers", choose_paper = true, on_done = function() end,
        on_cancel = function() cancelled = cancelled + 1 end }
end, after = 3 })
add({ shot = "1-new-drawing", after = 0.5 })
add({ fn = function(E)
    local l = list()
    local names = {}
    for _i, p in ipairs(l and l.papers or {}) do names[#names + 1] = p.label end
    check(l and l.create and screen() == nil and l.title == "New drawing" and #l.papers == 24
        and table.concat(names, ", "):find("^Blank, Medium ruled, Medium ruled with margin, Wide ruled, Wide ruled with margin, "
            .. "Narrow ruled, Narrow ruled with margin, Vertical ruled, Vertical ruled with margin, Graph, Dotted, Checklist, "
            .. "Daily planner, Weekly planner, Monthly planner, Habit tracker, Storyboard, Music, Mine 1") ~= nil,
        "a new drawing asks which paper first: " .. table.concat(names, ", "))
    local cols = require("gzreader_drawpages").paperCell(l.win and l.win.w or W)
    local first, last = l.rows[1].dimen, l.rows[cols].dimen
    check(first.y == last.y and l.rows[cols + 1].dimen.y > first.y and last.x + last.w <= W and first.w < W / cols,
        "…small tiles, " .. cols .. " to a row, the row wholly on screen (" .. (last.x + last.w) .. " of " .. W .. ")")
    check(l.current == "blank" and E.findText("Create") ~= nil and E.findText("Cancel") ~= nil,
        "…Blank chosen to begin with; Cancel and Create under the grid")
    local win = l.win
    check(win and l.covers_fullscreen == false and win.x > 0 and win.y > 0 and win.x + win.w < W and win.y + win.h < H
        and first.x >= win.x and first.y >= win.y and last.x + last.w <= win.x + win.w,
        "…in a window over the Notes tab (" .. (win and (win.w .. "x" .. win.h .. " at " .. win.x .. "," .. win.y) or "none")
            .. "), the tiles inside it")
    tap(E, (cell(l, "ruled-narrow")))
end, after = 3 })
add({ shot = "2-narrow-chosen", after = 0.5 })
add({ fn = function(E)
    local l = list()
    check(l and l.current == "ruled-narrow" and screen() == nil, "a tap on Narrow ruled: chosen (not started yet)")
    tap(E, "Create")
end, after = 4 })
add({ shot = "3-drawing-on-narrow", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(list() == nil and d and d.sketch:paper() == "ruled-narrow" and G_reader_settings:readSetting("gzreader_drawing_paper") == "ruled-narrow",
        "Create: the drawing screen, its page on Narrow ruled (new pages start on it too)")
    -- the paper is kept in colour under the ink (a colour screen shows it so; the picture sent to Memos has it)
    local blue = 0
    local bb = d and d.color_bb
    if bb then
        for y = 0, bb:getHeight() - 1, 3 do
            for x = 0, bb:getWidth() - 1, 3 do
                local c = bb:getPixel(x, y):getColorRGB32()
                if c.b > c.r + 30 then blue = blue + 1 end
            end
        end
    end
    check(blue > 50, "…the paper kept in colour (its blue rules: " .. blue .. " sampled points), for a colour screen and for Memos")
    tap(E, button("paper"))
end, after = 3 })
add({ shot = "4-paper", after = 0.5 })
add({ fn = function(E)
    local l = list()
    local pw = l and l.win
    check(l and not l.create and l.window and l.current == "ruled-narrow" and E.findText("Create") == nil and E.findText("Done") ~= nil
        and E.findText("Cancel") ~= nil and pw and l.covers_fullscreen == false and pw.x > 0 and pw.y > 0 and pw.x + pw.w < W and pw.y + pw.h < H,
        "Paper on the drawing screen: the same window over the drawing, the page's paper chosen, Cancel and Done (no Create)")
    E.scrolls = l.scroller._is_scrollable
    E.offset0 = l.scroller:getScrolledOffset().y
    -- a drag up the grid (a finger: the pen draws, not scrolls)
    -- (opened at the chosen paper: at the end already, so the other way)
    -- (inside the window's grid, clear of its buttons)
    if E.scrolls and E.offset0 > 0 then
        E.finger({ { W * 0.5, H * 0.35 }, { W * 0.5, H * 0.5 }, { W * 0.5, H * 0.65 } }, 0.4)
    elseif E.scrolls then
        E.finger({ { W * 0.5, H * 0.65 }, { W * 0.5, H * 0.5 }, { W * 0.5, H * 0.35 } }, 0.4)
    end
end, after = 3 })
add({ shot = "5-scrolled", after = 0.5 })
add({ fn = function(E)
    local l = list()
    local off = l.scroller:getScrolledOffset().y
    if E.scrolls then
        check(off ~= E.offset0,
            "more rows than fit: a drag scrolls the grid (" .. E.offset0 .. " -> " .. off .. " px)")
    else
        check(off == 0, "every row fits this screen: nothing to scroll")
    end
    -- tap the lowest of GZreader's papers wholly on screen
    local view = l.scroller.dimen
    for i = #l.rows, 1, -1 do
        local d = l.rows[i].dimen
        if d.y and d.y >= view.y and d.y + d.h <= view.y + view.h and not l.papers[i].id:find("^own:") then
            E.last_id = l.papers[i].id
            tap(E, { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 3) })
            break
        end
    end
end, after = 3 })
add({ shot = "6-picked", after = 0.5 })
add({ fn = function(E)
    local l = list()
    check(E.last_id ~= nil and E.last_id ~= "ruled-narrow" and l and l.current == E.last_id and screen().sketch:paper() == "ruled-narrow",
        "a tap on a tile: chosen in the window, the page not changed yet (" .. tostring(E.last_id) .. ")")
    E.tap("Done")
end, after = 3 })
add({ shot = "6b-done", after = 0.5 })
add({ fn = function(E)
    check(list() == nil and screen().sketch:paper() == E.last_id, "Done: the page on that paper")
    -- a new drawing, cancelled: nothing opens
    UIM():close(screen())
    require("gzreader_drawscreen").show{ title = "Papers", choose_paper = true, on_done = function() end,
        on_cancel = function() cancelled = cancelled + 1 end }
end, after = 3 })
add({ shot = "7-new-again", after = 0.5 })
add({ fn = function(E) tap(E, "Cancel") end, after = 3 })
add({ fn = function(E)
    check(list() == nil and screen() == nil and cancelled == 1, "a new drawing, Cancel: no drawing screen, the note told so")
    require("gzreader_drawscreen").show{ title = "Papers", choose_paper = true, on_done = function() end,
        on_cancel = function() cancelled = cancelled + 1 end }
end, after = 3 })
add({ fn = function(E) tap(E, { math.floor(W / 2), math.floor(H * 0.05) }) end, after = 3 })
add({ fn = function(E)
    check(list() == nil and screen() == nil and cancelled == 2, "…a tap outside the window: Cancel too")
    -- a page on a paper GZreader no longer offers stays on it
    local NP = require("gzreader_notepaper")
    local sc = NP.scene("college")
    check(NP.get("college") ~= nil and NP.idOf(sc, sc.elements[1]) == "college",
        "a page on College ruled (no longer offered): still known as it")
    os.execute("rm -rf '" .. NP.ownDir() .. "'")
    local f = io.open(E.out .. "/paper-list-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
