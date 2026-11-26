-- The pen's eraser removes highlights (gzreader_peneraser.lua): a book
-- (GZ_EMU_BOOK) with two highlights; the eraser end rubbed over the first
-- removes it and leaves the second; the tip over the second leaves it.
--   GZ_EMU_MODEL=scribe GZ_EMU_BOOK=<epub> GZ_EMU_TREE=<tree>/koreader run.sh pen_eraser.lua <out>
-- Checks go to <out>/pen-eraser-checks.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function reader() return require("apps/reader/readerui").instance end
local function count() return #reader().annotation.annotations end
-- the screen box of highlight `n` (its first), as the page shows it
local function boxOf(n)
    local ui = reader()
    for _i, box in ipairs(ui.view.highlight.visible_boxes or {}) do
        if box.index == n then
            local r = box.rect
            if ui.view.pageToScreenTransform then
                local ok, sr = pcall(ui.view.pageToScreenTransform, ui.view, ui.view.state.page, r)
                if ok and type(sr) == "table" and sr.x then r = sr end
            end
            return r
        end
    end
end
local function stroke(n, eraser)
    return function(E)
        local r = boxOf(n)
        E.say("box", n, r and (math.floor(r.x) .. "," .. math.floor(r.y) .. " " .. math.floor(r.w) .. "x" .. math.floor(r.h)) or "none")
        if not r then return end
        local y = r.y + r.h / 2
        E.pen({ { r.x + 2, y }, { r.x + r.w / 3, y + 1 }, { r.x + 2 * r.w / 3, y }, { r.x + r.w - 2, y + 1 } }, 0.5, eraser)
    end
end
add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    require("apps/reader/readerui"):showReader(os.getenv("GZ_EMU_BOOK"))
end, after = 14 })
add({ fn = function() reader():handleEvent(require("ui/event"):new("GotoPage", 4)) end, after = 3 })
add({ fn = function(E)
    local ui = reader()
    local doc = ui.document
    local function words(from, n)
        local p1 = from
        for _i = 1, n do p1 = doc:getNextVisibleWordEnd(p1) or p1 end
        return p1
    end
    local p0 = doc:getNextVisibleWordStart(doc:getXPointer()) or doc:getXPointer()
    local p1 = words(p0, 4)
    local q0 = p1
    for _i = 1, 30 do q0 = doc:getNextVisibleWordStart(q0) or q0 end
    local q1 = words(q0, 4)
    for _i, pair in ipairs({ { p0, p1 }, { q0, q1 } }) do
        local item = { page = pair[1], pos0 = pair[1], pos1 = pair[2], drawer = "lighten", color = "yellow",
            text = doc:getTextFromXPointers(pair[1], pair[2]), chapter = "Chapter" }
        local index = ui.annotation:addItem(item)
        ui:handleEvent(require("ui/event"):new("AnnotationsModified", { item, nb_highlights_added = 1, index_modified = index }))
    end
    UIM():setDirty(ui, "ui")
    E.say("highlights:", count(), "eraser watching:", tostring(require("gzreader_peneraser").active == ui))
    check(require("gzreader_peneraser").active == ui, "the book open: the eraser watched for")
end, after = 4 })
add({ shot = "eraser-1-two-highlights" })
add({ fn = stroke(1, true), after = 4 })
add({ shot = "eraser-2-rubbed-out" })
add({ fn = function(E)
    E.say("after the eraser:", count())
    check(count() == 1, "the eraser over the first highlight: removed, the other left")
end, after = 1 })
add({ fn = function(E) E.before_tip = count() end })
add({ fn = stroke(1, false), after = 4 })
add({ fn = function(E)
    -- (the tip is a finger: a tap on a highlight opens its menu; close it)
    E.say("after the tip:", count())
    check(count() == E.before_tip, "the pen's tip over a highlight: it stays")
    local st = UIM()._window_stack
    while #st > 0 and st[#st].widget ~= reader() do UIM():close(st[#st].widget) end
    local f = io.open(E.out .. "/pen-eraser-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
