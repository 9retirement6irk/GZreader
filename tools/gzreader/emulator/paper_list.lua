-- The drawing screen's Paper: a grid that scrolls (three pictures to a row,
-- each with its name, the page's ticked), not a grid in pages (the old
-- grid's third column went off the Scribe's screen). Six papers of your own
-- are added (copies of College ruled) so the grid is longer than the
-- screen: a drag up scrolls it, and a tap on a picture puts the page on it.
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
    require("gzreader_drawscreen").show{ title = "Papers", on_done = function() end, on_cancel = function() end }
end, after = 3 })
add({ fn = function(E) tap(E, button("paper")) end, after = 3 })
add({ shot = "1-paper-list", after = 0.5 })
add({ fn = function(E)
    local l = list()
    local names = {}
    for _i, p in ipairs(l and l.papers or {}) do names[#names + 1] = p.label end
    E.total = l and #l.papers
    check(l and l.kind == "papers" and #l.rows == #l.papers and #l.papers >= 12,
        "Paper: a grid that scrolls, a cell each (" .. tostring(E.total) .. "): " .. table.concat(names, ", "))
    local third = l.rows[3].dimen
    check(l.rows[1].dimen.y == third.y and third.x + third.w <= W and l.scroller._is_scrollable,
        "…three to a row, the third wholly on screen (" .. (third.x + third.w) .. " of " .. W .. "), longer than the screen")
    E.offset0 = l.scroller:getScrolledOffset().y
    -- a drag up the list (a finger: the pen draws, not scrolls)
    E.finger({ { W * 0.5, H * 0.8 }, { W * 0.5, H * 0.6 }, { W * 0.5, H * 0.4 } }, 0.4)
end, after = 3 })
add({ shot = "2-scrolled", after = 0.5 })
add({ fn = function(E)
    local l = list()
    local off = l.scroller:getScrolledOffset().y
    check(off > E.offset0, "a drag up: the grid scrolls (" .. E.offset0 .. " -> " .. off .. " px)")
    -- tap the lowest built-in paper wholly on screen (the copies of your own
    -- are College ruled, byte for byte, so the page would read back as that)
    local view = l.scroller.dimen
    for i = #l.rows, 1, -1 do
        local d = l.rows[i].dimen
        if d.y and d.y >= view.y and d.y + d.h <= view.y + view.h and not l.papers[i].id:find("^own:") then
            E.last_id = l.papers[i].id
            E.tapped = table.concat({ i, d.x, d.y, d.w, d.h }, ",")
            tap(E, { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) })
            break
        end
    end
end, after = 3 })
add({ fn = function(E)
    check(E.last_id ~= nil and E.last_id ~= "blank" and list() == nil and screen().sketch:paper() == E.last_id, "a tap on a picture: the page on that paper (" .. tostring(E.last_id) .. "; list open: " .. tostring(list() ~= nil) .. ", paper " .. tostring(screen().sketch:paper()) .. ", tapped " .. tostring(E.tapped) .. ")")
    os.execute("rm -rf '" .. require("gzreader_notepaper").ownDir() .. "'")
    local f = io.open(E.out .. "/paper-list-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
