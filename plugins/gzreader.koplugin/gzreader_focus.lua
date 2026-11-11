--[[--
The Grimmory tab's selection (Kindles with keys) kept when a page is drawn
again: when the fresh copy of a list arrives, covers come in, a download
starts or ends. Before, every redraw put it back on the first book, so
moving down while the tab was still loading, or downloading a book, lost
your place.

What's selected is remembered by what it is (a book's id, the first page's
cards), not where it was, and found again in the new page.
]]

local Focus = {}

--- What an entry is: a book by its id, the first page's cards by their id,
--- other rows by their text.
function Focus.keyOf(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.book) == "table" and entry.book.id ~= nil then return "book:" .. tostring(entry.book.id) end
    if entry.gz_id then return "id:" .. tostring(entry.gz_id) end
    if entry.gz_action then return "action:" .. tostring(entry.gz_action) end
    if type(entry.text) == "string" then return "text:" .. entry.text end
    return nil
end

--- What's selected in `m` (a Menu): { key, x, y }, or nil.
function Focus.current(m)
    local sel = m and m.selected
    local row = sel and type(m.layout) == "table" and m.layout[sel.y]
    local w = row and row[sel.x]
    local key = w and Focus.keyOf(w.entry)
    if not key then return nil end
    return { key = key, x = sel.x, y = sel.y }
end

--- Where `want` is in `m`'s layout now: x, y (the same place if it's still
--- there, else the same row, else anywhere), or nil.
function Focus.find(m, want)
    if not (want and want.key and type(m.layout) == "table") then return nil end
    local row_hit, any_hit
    for y, row in ipairs(m.layout) do
        for x, w in ipairs(row) do
            if type(w) == "table" and Focus.keyOf(w.entry) == want.key then
                if x == want.x and y == want.y then return x, y end
                if y == want.y and not row_hit then row_hit = { x, y } end
                if not any_hit then any_hit = { x, y } end
            end
        end
    end
    local hit = row_hit or any_hit
    if hit then return hit[1], hit[2] end
    return nil
end

--- Has the selection been moved (5-way) since the page was drawn? When it
--- hasn't, a redraw places it as the page always did.
function Focus.moved(m)
    local was, sel = m._gz_drawn_sel, m.selected
    if not sel then return false end
    return not was or was.x ~= sel.x or was.y ~= sel.y
end

--- The index in `items` of the entry `want` stands for, or nil.
function Focus.indexIn(items, want)
    if not (want and want.key) then return nil end
    for i, e in ipairs(items or {}) do
        if Focus.keyOf(e) == want.key then return i end
    end
    return nil
end

--- Keep the selection of the browser's Menu across redraws of the same page
--- (wraps m.updateItems; put it on after the cover views). `has_keys`: the
--- Kindle has a 5-way (on touch Kindles nothing is selected).
function Focus.apply(m, has_keys)
    if not m or m._gz_focus or not has_keys then return end
    m._gz_focus = true
    local inner = m.updateItems
    m.updateItems = function(menu, select_number, no_recalculate_dimen)
        -- the same list and page drawn again: what was selected stays so
        local want = menu._gz_focus_want
        menu._gz_focus_want = nil
        if not want and menu._gz_drawn_items == menu.item_table and menu._gz_drawn_page == menu.page
                and Focus.moved(menu) then
            want = Focus.current(menu)
        end
        local res = inner(menu, select_number, no_recalculate_dimen)
        menu._gz_drawn_items, menu._gz_drawn_page = menu.item_table, menu.page
        if want then
            local x, y = Focus.find(menu, want)
            if x and menu.selected and (menu.selected.x ~= x or menu.selected.y ~= y) then
                local okf, FocusManager = pcall(require, "ui/widget/focusmanager")
                menu:moveFocusTo(x, y, okf and type(FocusManager) == "table" and FocusManager.FOCUS_ONLY_ON_NT or nil)
            end
            -- (still the user's choice: kept again at the next redraw)
            menu._gz_drawn_sel = nil
        else
            -- where the page itself put it: a redraw may put it elsewhere
            -- (the first book once its cover is in), as it always did
            menu._gz_drawn_sel = menu.selected and { x = menu.selected.x, y = menu.selected.y } or nil
        end
        return res
    end
end

--- A new copy of the list on screen is about to replace it (the same list,
--- fresher): the item to show it from (its page) and remember what's
--- selected so it's selected again. Returns the index or nil.
function Focus.carry(m, new_items)
    local want = m and m._gz_focus and m._gz_drawn_items == m.item_table and Focus.moved(m) and Focus.current(m)
    if not want then return nil end
    local i = Focus.indexIn(new_items, want)
    if i then m._gz_focus_want = want end
    return i
end

return Focus
