-- Pen ↔ hand at one tap: the top bar's hand moves the page with the pen;
-- tapped again (now the pen's icon), back to the pen as it was. The hand's
-- own button, tapped again, goes back too. The pen's shortcut button can be
-- the hand (Settings → Notes): held, the pen moves the page.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh pen_hand.lua <out>
-- No Memos needed. Checks go to <out>/pen-hand-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local W, H
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    for _i, b in ipairs(screen().buttons) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) }, b end
    end
end
local function stroke(E, fy)
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { math.floor(W * (0.3 + 0.03 * i)), math.floor(H * fy), 2000 } end
    E.pen(pts, 0.5)
end
add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:saveSetting("gzreader_drawing_writing", "pencil")
    G_reader_settings:delSetting("gzreader_drawing_shortcut")
    require("gzreader_drawscreen").show{ title = "Pen and hand", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    local p, b = button("penhand")
    check(p and b.tool.icon == "hand" and d.tool == "pen" and d.writing == "pencil", "the top bar has the hand (the pencil in hand)")
    -- zoomed in, so there's somewhere to move to
    local c = d.sketch.canvas
    d.sketch:zoomBy(2, c.w / 2, c.h / 2, c.w / 2, c.h / 2)
    d:repaintCanvas()
    E.tap(p)
end, after = 2 })
add({ shot = "1-hand", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local b = select(2, button("penhand"))
    check(d.tool == "hand" and b.tool.icon == "pencil", "one tap: the hand in hand; the button shows the pencil (to go back)")
    E.ox = d.sketch.ox
    stroke(E, 0.5)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 0 and d.sketch.ox ~= E.ox, "the pen moved the page; nothing drawn")
    E.tap(button("penhand"))
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.tool == "pen" and d.writing == "pencil", "tapped again: back to the pencil")
    stroke(E, 0.6)
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 1, "…and it draws")
    -- the side toolbar's hand, tapped twice, does the same
    E.tap(button("hand"))
end, after = 2 })
add({ fn = function(E)
    check(screen().tool == "hand", "the toolbar's hand: the hand")
    E.tap(button("hand"))
end, after = 2 })
add({ fn = function(E)
    check(screen().tool == "pen", "…tapped again: back to the pen")
    -- the pen's shortcut button as the hand: held, the pen moves the page
    G_reader_settings:saveSetting("gzreader_drawing_shortcut", "hand")
    E.ox2 = screen().sketch.ox
    E.penSideButton(true)
end, after = 1 })
add({ fn = function(E) stroke(E, 0.4) end, after = 3 })
add({ fn = function(E) E.penSideButton(false) end, after = 1 })
add({ fn = function(E)
    local d = screen()
    check(#d.sketch:live() == 1 and d.sketch.ox ~= E.ox2, "the shortcut button held (set to the hand): the pen moves the page, nothing drawn")
    G_reader_settings:delSetting("gzreader_drawing_shortcut")
    local f = io.open(E.out .. "/pen-hand-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
