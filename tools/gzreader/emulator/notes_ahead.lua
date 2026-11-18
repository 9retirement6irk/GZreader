-- The Notes board draws the notes of the next page (and the one before)
-- ahead while it's still, so a page turn only shows them. With
-- demo/mock_memos.py --sample --many 30 on 127.0.0.1:18090. Any model.
-- For each view (Compact, Full, and on touch models Scroll up and down) it
-- waits for the drawing ahead, turns pages and counts the notes that still
-- had to be painted; GZ_NOTES_AHEAD=0 turns the drawing ahead off, to see
-- the same turns without it. Writes <out>/notes-ahead-checks.txt (the checks
-- and each turn's CPU time).
local OFF = os.getenv("GZ_NOTES_AHEAD") == "0"
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function note(what) lines[#lines + 1] = "     " .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function Notes() return require("gzreader_notes") end
local painted = 0

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local Sticky = require("gzreader_sticky")
    local image = Sticky.image
    Sticky.image = function(...) painted = painted + 1; return image(...) end
    if OFF then Notes().drawAhead = function() return false end end
    E.say("connect ->", tostring(Notes().connect(plugin(), "127.0.0.1:18090", "memos-test-token")))
    if Notes().connect_menu then UIM():close(Notes().connect_menu, "full"); Notes().connect_menu = nil end
    Notes().show(plugin())
end, after = 25 })

-- `turn` (a page turn, a scroll) after the board was still for a while: how many notes it painted, its CPU time
local function turn(label, fn, expect_none)
    add({ fn = function()
        painted = 0
        local c0 = os.clock()
        fn(Notes().board)
        UIM():forceRePaint()
        local ms = (os.clock() - c0) * 1000
        if expect_none and not OFF then
            check(painted == 0, label .. ": nothing left to paint (" .. painted .. " painted)")
        end
        note(string.format("%s: %.0f ms CPU, %d notes painted", label, ms, painted))
    end, after = 8 })
end
local function view(name, set)
    add({ fn = function() set() end, after = 10 })
    add({ fn = function()
        local b = Notes().board
        check(b and (b.page_num or 1) >= 3 or b._gz_scroll ~= nil, name .. ": the board has pages to turn (" .. tostring(b and b.page_num) .. ")")
    end, after = 1 })
    turn(name .. ", next page", function(b) b:onNextPage() end, true)
    turn(name .. ", next page again", function(b) b:onNextPage() end, true)
    turn(name .. ", a page back", function(b) b:onPrevPage() end, true)
end
view("Compact", function() end)
-- right after a turn, before the board was still: as without drawing ahead
local function keptNow(label)
    local n, bytes = 0, 0
    for _k, kept in pairs(Notes().images) do
        n = n + 1
        bytes = bytes + kept.bb:getWidth() * kept.bb:getHeight()
    end
    note(string.format("%s: %d images kept, %.1f MB", label, n, bytes / 1048576))
end
add({ fn = function()
    local b = Notes().board
    keptNow("Compact, the board still (its page, the next and the one before)")
    painted = 0
    b:onNextPage(); UIM():forceRePaint()
    b:onNextPage(); UIM():forceRePaint()
    check(OFF or painted >= 4, "Compact, two quick turns: the second page is painted as before (" .. painted .. " notes)")
end, after = 8 })
view("Full", function() Notes().setView(plugin(), "display", "full") end)
add({ fn = function() keptNow("Full, the board still") end, after = 0.5 })
add({ fn = function() Notes().setView(plugin(), "display", "compact") end, after = 8 })
if os.getenv("GZ_EMU_MODEL") ~= nil and os.getenv("GZ_EMU_MODEL") ~= "k3" and os.getenv("GZ_EMU_MODEL") ~= "k4"
        and os.getenv("GZ_EMU_MODEL") ~= "dx" and os.getenv("GZ_EMU_MODEL") ~= "dxg" and os.getenv("GZ_EMU_MODEL") ~= "k2" then
    add({ fn = function() Notes().setScrolling(plugin(), true) end, after = 10 })
    turn("Scroll, most of a screen down", function(b) b:scrollBy(b._gz_scroll.view_h - b._gz_scroll.cell_h) end, true)
    turn("Scroll, down again", function(b) b:scrollBy(b._gz_scroll.view_h - b._gz_scroll.cell_h) end, true)
    turn("Scroll, back up", function(b) b:scrollBy(-(b._gz_scroll.view_h - b._gz_scroll.cell_h)) end, true)
    add({ fn = function() Notes().setScrolling(plugin(), false) end, after = 6 })
end
-- something over the board: nothing is drawn ahead meanwhile
add({ fn = function()
    local b = Notes().board
    b:onNextPage(); UIM():forceRePaint()
    Notes().showSort(plugin())
    painted = 0
end, after = 6 })
add({ fn = function()
    check(OFF or painted == 0, "with a window over the board nothing is drawn ahead (" .. painted .. ")")
    local st = UIM()._window_stack
    UIM():close(st[#st].widget)
end, after = 2 })
add({ shot = "notes-ahead" })
add({ fn = function(E)
    keptNow("at the end")
    local f = io.open(E.out .. "/notes-ahead-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
