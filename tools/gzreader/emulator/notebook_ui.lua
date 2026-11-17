-- The drawing screen as the Kindle Scribe's notebook: the top bar (Back,
-- the drawing's name with a pencil, pages, paper, tags, options, Done) and
-- the tab that folds it away; the tools down the side (pen, highlighter,
-- shapes, eraser; undo, redo, more) under a round button that folds them
-- into one; each tool's panel (a list: the name at the left); shapes drawn
-- corner to corner; a new drawing named and tagged from the top bar.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh notebook_ui.lua <out>
-- Checks go to <out>/notebook-ui-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local MODEL = os.getenv("GZ_EMU_MODEL") or "scribe"
local PEN = MODEL == "scribe"
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) }, b end
    end
end
local function ids(group)
    local out = {}
    for _i, b in ipairs(screen().buttons) do if b.group == group then out[#out + 1] = b.tool.id end end
    return table.concat(out, ",")
end
local function tap(E, p) if not p then return end; if PEN then E.penTap(p) else E.tap(p) end end
local function draw(E, pts) if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end end
local done

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    for _i, k in ipairs({ "gzreader_drawing_writing", "gzreader_drawing_shape", "gzreader_drawing_toolbar_side" }) do G_reader_settings:delSetting(k) end
    G_reader_settings:saveSetting("gzreader_drawing_paper", "ruled-medium")
    require("gzreader_drawscreen").show{ meta = { title = "", tags = {}, offered = { { tag = "work", count = 3 }, { tag = "ideas", count = 1 } } },
        on_done = function(res) done = res end, on_cancel = function() end }
end, after = 3 })
add({ shot = "1-notebook", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(ids("top") == "cancel,done,options,tag,paper,pages,title" and d.canvas.y == 0 and d.canvas.h == H,
        "the top bar: Back, the name, pages, paper, tags, options, Done (" .. ids("top") .. "); the page is the whole screen")
    check(ids("toolbar") == "pen,highlighter,shape,eraser,sep,undo,redo,more" and ids("fold") == "hide",
        "the tools: pen, highlighter, shapes, eraser; undo, redo, more; a round button above (" .. ids("toolbar") .. ")")
    check(d:heading() == "Untitled drawing", "a new drawing: Untitled drawing, a pencil after it")
    tap(E, (button("pen")))
end, after = 3 })
add({ shot = "2-pen-panel", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "pen" and ids("flyout"):find("^t%-pen,t%-fountain,t%-marker,t%-pencil,w0.5,w1,w2,w4,w7") ~= nil,
        "the pen again: Pen, Fountain pen, Marker, Pencil, then five thicknesses (" .. ids("flyout") .. ")")
    tap(E, (button("t-marker")))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d.writing == "marker" and d.sketch.writing == "marker" and d.flyout == "pen", "Marker: in hand, the panel stays for a thickness")
    tap(E, (button("w4")))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d.width == 4 and d.flyout == nil, "Thick: chosen, the panel away")
    draw(E, { { W * 0.4, H * 0.3 }, { W * 0.5, H * 0.32 }, { W * 0.6, H * 0.3 } })
end, after = 3 })
add({ fn = function(E)
    local sk = screen().sketch
    check(#sk:live() == 1 and sk:live()[1].kind == "marker", "a stroke: drawn with the marker")
    tap(E, (button("highlighter")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("highlighter"))) end, after = 3 })
add({ shot = "3-highlighter-panel", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d.tool == "highlighter" and d.sketch.writing == "highlighter" and d.flyout == "highlighter" and ids("flyout") == "hw0.5,hw1,hw2,hw4,hw7",
        "Highlighter, and again: Fine, Thin, Medium, Thick, Heavy (" .. ids("flyout") .. ")")
    tap(E, (button("hw4")))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d.hl_width == 4 and d.sketch.width == 4 and d.width == 4 and d.flyout == nil, "Thick: the highlighter's own width")
    tap(E, (button("shape")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("shape"))) end, after = 3 })
add({ shot = "4-shapes-panel", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "shape" and ids("flyout") == "s-square,s-circle,s-triangle,s-line,s-arrow",
        "Shapes, and again: Square, Circle, Triangle, Line, Arrow (" .. ids("flyout") .. ")")
    tap(E, (button("s-circle")))
end, after = 3 })
add({ fn = function(E)
    check(screen().shape == "circle" and screen().sketch.tool == "shape", "Circle: in hand")
    draw(E, { { W * 0.35, H * 0.45 }, { W * 0.5, H * 0.52 }, { W * 0.65, H * 0.6 } })
end, after = 3 })
add({ fn = function(E)
    local sk = screen().sketch
    local st = sk:live()[2]
    local minx, maxx = math.huge, -math.huge
    for _i, p in ipairs(st and st.points or {}) do minx, maxx = math.min(minx, p[1]), math.max(maxx, p[1]) end
    check(st and #st.points >= 24 and math.abs((maxx - minx) - W * 0.3) < W * 0.03 and st.points[1][1] == st.points[#st.points][1],
        "a drag: a circle from corner to corner, one closed stroke (" .. (st and #st.points or 0) .. " points, " .. math.floor(maxx - minx) .. " px wide)")
    tap(E, (button("s-arrow") or button("shape")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("s-arrow"))) end, after = 3 })
add({ fn = function(E)
    draw(E, { { W * 0.3, H * 0.7 }, { W * 0.5, H * 0.7 }, { W * 0.7, H * 0.7 } })
end, after = 3 })
add({ shot = "5-shapes-drawn", after = 0.5 })
add({ fn = function(E)
    local sk = screen().sketch
    check(#sk:live() == 3 and #sk:live()[3].points == 5, "Arrow: a line and its head, one stroke")
    tap(E, (button("undo")))
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 2, "Undo takes the arrow back")
    tap(E, (button("eraser")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("eraser"))) end, after = 3 })
add({ shot = "6-eraser-panel", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "eraser" and ids("flyout") == "e1,e2,e4,e7,e12,clear",
        "Eraser, and again: Fine to Heavy, then Erase page (" .. ids("flyout") .. ")")
    tap(E, (button("e12")))
end, after = 3 })
add({ fn = function(E)
    check(screen().eraser_width == 12 and screen().sketch.eraser_width == 12, "Heavy: the eraser reaches further")
    tap(E, (button("more")))
end, after = 3 })
add({ shot = "7-more-panel", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "more" and ids("flyout"):find("^side") ~= nil and (not PEN or ids("flyout") == "side,shortcut"),
        "More: Move to right side" .. (PEN and ", Stylus shortcut" or "") .. " (" .. ids("flyout") .. ")")
    tap(E, (button("side")))
end, after = 3 })
add({ fn = function(E)
    local _, b = button("pen")
    check(screen().toolbar_side == "right" and b.rect.x > W / 2, "Move to right side: the tools at the right")
    tap(E, (button("more")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("side"))) end, after = 3 })
add({ fn = function(E) tap(E, (button("hide"))) end, after = 3 })
add({ shot = "8-tools-folded", after = 0.5 })
add({ fn = function(E)
    check(screen().toolbar_hidden and ids("toolbar") == "" and ids("fold") == "show", "the round button: the tools folded into one (the tool in hand on it)")
    tap(E, (button("topfold")))
end, after = 3 })
add({ shot = "9-top-folded", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d.top_hidden and ids("top") == "" and d.frames.top == nil and d.frames.tab.y == 0, "the tab: the top bar folded away, its tab at the top edge")
    -- the page's top is free to draw on now
    draw(E, { { W * 0.4, 30 }, { W * 0.5, 34 }, { W * 0.6, 30 } })
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 2, "(the eraser in hand: nothing drawn)")
    tap(E, (button("topfold")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("show"))) end, after = 3 })
add({ fn = function(E)
    check(not screen().top_hidden and not screen().toolbar_hidden and ids("top") ~= "", "both back")
    tap(E, (button("tag")))
end, after = 3 })
add({ shot = "10-tags", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "tags" and ids("flyout") == "tag-work,tag-ideas,newtag", "the tag button: your tags, and New tag (" .. ids("flyout") .. ")")
    tap(E, (button("tag-ideas")))
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(#d.meta.tags == 1 and d.meta.tags[1] == "ideas" and d:hint() == "#ideas", "a tap: the tag on the drawing, shown under its name")
    tap(E, (button("tag")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("title"))) end, after = 4 })
add({ shot = "11-rename", after = 0.5 })
add({ fn = function(E)
    local dialog
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Name this drawing" then dialog = w.widget end end
    check(dialog ~= nil, "a tap on the name: Name this drawing")
    if dialog then dialog:addTextToInput("Garden plan"); E.tap("Save") end
end, after = 4 })
add({ shot = "12-named", after = 0.5 })
add({ fn = function(E)
    check(screen() and screen():heading() == "Garden plan", "Save: the name in the top bar")
    tap(E, (button("options")))
end, after = 3 })
add({ shot = "13-options", after = 0.5 })
add({ fn = function(E)
    check(screen().flyout == "options" and ids("flyout") == "newpage2,clear,cancel", "Options: New page, Erase page, Close without saving (" .. ids("flyout") .. ")")
    tap(E, (button("options")))
end, after = 3 })
add({ fn = function(E) tap(E, (button("done"))) end, after = 5 })
add({ fn = function(E)
    check(screen() == nil and done and #done == 1 and done.title == "Garden plan" and done.tags and done.tags[1] == "ideas",
        "Done: the page, with the name and tags given in the top bar")
    if done and done[1] and done[1].path then os.remove(done[1].path) end
    local f = io.open(E.out .. "/notebook-ui-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
