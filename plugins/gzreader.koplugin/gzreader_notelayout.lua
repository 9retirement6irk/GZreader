--[[--
The Notes tab's views, after the Memos web app's: how many notes side by
side (List, Two, Three, Auto) and how long a note is on the board (Compact:
every note the same size, a long one cut off; Full: each note as long as it
needs, nothing cut off). L on the board (or Layout, More → Layout), and
Settings → Connections → Memos (Notes) → Layout.

Only arithmetic here (no widgets), so it can be tested on its own:
gzreader_notes.lua measures the notes and draws what this lays out.
]]

local NL = {}

NL.COLUMNS = { "list", "2", "3", "auto" }
NL.DISPLAYS = { "compact", "full" }
NL.DEFAULT = { columns = "2", display = "compact" } -- (the board before views: two side by side, compact)
NL.MAX_COLS = 4
-- Auto: as many columns as fit at least this wide (in scaled pixels, so the
-- same number on every Kindle held the same way): about 22 characters of the
-- notes' handwriting a line. Two upright, three sideways.
NL.AUTO_MIN_W = 230
-- Compact: rows of notes at least this tall (scaled), at most ROWS of them:
-- three upright (as before), two sideways.
NL.ROW_MIN_H = 180
NL.ROWS = 3
-- Full: a note too long for a column goes on in the next one (or on the next
-- page); a part has at least this many lines, unless the column is empty.
NL.MIN_PART = 3

local function oneOf(v, list, default)
    for _i, x in ipairs(list) do if v == x then return v end end
    return default
end

--- The view in `prefs` (Settings → Notes' table), checked: { columns, display }.
function NL.view(prefs)
    prefs = prefs or {}
    return {
        columns = oneOf(prefs.columns, NL.COLUMNS, NL.DEFAULT.columns),
        display = oneOf(prefs.display, NL.DISPLAYS, NL.DEFAULT.display),
    }
end

--- How many columns for `choice` on a board `width` pixels wide; `min_w` is
--- AUTO_MIN_W scaled for this screen.
function NL.columns(choice, width, min_w)
    if choice == "list" then return 1 end
    if choice == "3" then return 3 end
    if choice == "auto" then
        local n = math.floor((tonumber(width) or 0) / math.max(1, tonumber(min_w) or 1))
        return math.max(1, math.min(NL.MAX_COLS, n))
    end
    return 2
end

--- Compact: how many rows of `cols` notes in `height` pixels (`row_min_h`:
--- ROW_MIN_H scaled). With letter keys (`max_items`, how many there are),
--- no more notes on a page than keys to open them.
function NL.rows(cols, height, row_min_h, max_items)
    local rows = math.floor((tonumber(height) or 0) / math.max(1, tonumber(row_min_h) or 1))
    rows = math.max(2, math.min(NL.ROWS, rows))
    if max_items then rows = math.max(1, math.min(rows, math.floor(max_items / math.max(1, cols)))) end
    return rows
end

--- Full: lay notes out on pages, as many as fit, like Memos' masonry view:
--- each note goes into the column with the most room left (the leftmost of
--- equals), in order; a note that doesn't fit ends the page.
---
--- `notes[i]` = { top = h, blocks = { h, h, … } }: `top` is what every part
--- of the note has (its frame, the date line, the room around it), `blocks`
--- what can be split between parts (its lines of text, each picture, and
--- the tags and place last). A note taller than a whole column is split
--- between blocks: what fits, then the rest at the top of the column to its
--- right when that one is still empty (read on like a newspaper), else at
--- the top of the next page ("continued"); notes after it come after it.
---
--- opts.max_parts: no more parts on a page (letter keys).
--- Returns pages: { { { note = i, from = b, to = b2, col = c, y = y, h = h }, … }, … }
--- (`from` > `to` for a note with no blocks).
function NL.paginate(notes, cols, page_h, opts)
    opts = opts or {}
    cols = math.max(1, cols or 1)
    local max_parts = opts.max_parts
    local pages = {}
    local i, b = 1, 1 -- the note and its first block not placed yet
    while i <= #notes do
        local page = {}
        local y = {}
        for c = 1, cols do y[c] = 0 end
        local cont -- the column a split note goes on in
        while i <= #notes and not (max_parts and #page >= max_parts) do
            local c = 1
            for k = 2, cols do if y[k] < y[c] then c = k end end
            if cont then c, cont = cont, nil end
            local room = page_h - y[c]
            local n = notes[i]
            local blocks = n.blocks or {}
            local used, k = n.top or 0, b - 1
            while k < #blocks and used + blocks[k + 1] <= room do k = k + 1; used = used + blocks[k] end
            local function place(to, h)
                page[#page + 1] = { note = i, from = b, to = to, col = c, y = y[c], h = h }
            end
            if k == #blocks and used <= room then -- the rest of the note fits
                place(k, used)
                y[c] = y[c] + used
                i, b = i + 1, 1
            else
                local rest = n.top or 0
                for j = b, #blocks do rest = rest + blocks[j] end
                local empty = y[c] == 0
                if rest <= page_h and not empty then
                    break -- fits on a fresh page: starts it
                elseif k - b + 1 >= NL.MIN_PART or empty then
                    if k >= b then
                        place(k, used) -- part of a long note; the rest goes on
                        b = k + 1
                    else
                        -- (not even one block fits an empty column: shown anyway, cut)
                        place(b, page_h)
                        b = b + 1
                        if b > #blocks then i, b = i + 1, 1 end
                    end
                    y[c] = page_h
                    if b > 1 then -- on in the empty column to the right, or on the next page
                        if c < cols and y[c + 1] == 0 then cont = c + 1 else break end
                    end
                else
                    break -- (the column with the most room is too short for a part: so are the others)
                end
            end
        end
        if #page == 0 then break end -- (can't happen: an empty page always takes something)
        pages[#pages + 1] = page
    end
    return pages
end

--- The page (1…) on which note `idx` starts, or the last page.
function NL.pageOf(pages, idx)
    for p, page in ipairs(pages) do
        for _j, part in ipairs(page) do
            if part.note >= idx then return p end
        end
    end
    return math.max(1, #pages)
end

return NL
