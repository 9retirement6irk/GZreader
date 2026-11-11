-- GZreader: the Home strip as a bookshelf. Books stand on wooden shelves with
-- their spines out (title, author, number in the series); the one the 5-way
-- is on, or that was tapped, is pulled out and shows its cover. Tap it (or
-- Press, or its letter) to open it. One shelf of the most recent books (two on the DX).
--
-- Drawn with rectangles and text (e-ink greys), with depth in the manner of
-- AndyHazz's Bookshelf plugin: the shelf is seen from a little above, so each
-- book shows the top of its page block, the title and author run along the
-- spine, the books cast a shadow on the wall behind them, and the board has a
-- top (darker at the back), a front and a shadow below. A spine is drawn once
-- and kept (spine_cache) until the shelf changes size.
-- Downloads' bookshelf (gzreader_shelfview.lua) uses the same spines and boards.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local cover_common = require("modules/filebrowser/patches/home/widgets/cover_common")
local CoverUtils = require("common/cover_utils")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local M = {}

M.BOARD_H = 14     -- the shelf board under the books (px at 160 dpi)
M.UNDER_H = 6      -- its shadow on the wall below
M.MIN_SPINE = 44   -- (1.22.6: wider, for bigger type; were 34-46)
M.MAX_SPINE = 58
--- How many spines a shelf of `width` holds.
function M.perRow(width)
    return math.max(4, math.min(24, math.floor((width - S(16)) / S(M.MAX_SPINE))))
end

local function hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local SHADES = { 0.78, 0.55, 0.30, 0.68, 0.18, 0.45, 0.85, 0.38 }

local function book_title(book)
    if book.is_group == true then
        return tostring(book.group_label or "")
    end
    local t = book.title
    if type(t) ~= "string" or t == "" then
        t = (tostring(book.path or ""):match("([^/]+)$") or ""):gsub("%.[^%.]+$", "")
    end
    return t
end

local function book_author(book)
    if book.is_group == true then
        return book.group_count and (tostring(book.group_count) .. " \u{25A4}") or ""
    end
    local a = book.authors
    if (type(a) ~= "string" or a == "") and book.path then
        -- GZreader: the file has none, Grimmory knows them (its download entry)
        local get = rawget(_G, "__GZ_GRIMMORY_AUTHORS")
        local ok, got = pcall(function() return get and get(book.path) end)
        if ok and type(got) == "string" then a = got end
    end
    if type(a) ~= "string" then return "" end
    return (a:gsub("\n.*$", ""))
end

local function book_number(book)
    local i = tonumber(book.series_index)
    if not i then return nil end
    return i == math.floor(i) and tostring(math.floor(i)) or string.format("%.1f", i)
end

--- Each book's spine: width, height and shade, the same every time.
function M.look(book, area_h)
    local h = hash(book.path or book.group_label or book.title)
    local w = S(M.MIN_SPINE) + (h % (S(M.MAX_SPINE) - S(M.MIN_SPINE) + 1))
    local tall = 0.84 + ((math.floor(h / 7) % 17) / 100)
    return {
        w = w,
        h = math.max(S(60), math.floor(area_h * math.min(1, tall))),
        shade = SHADES[(math.floor(h / 13) % #SHADES) + 1],
    }
end

local spine_cache = {}
local spine_cache_n = 0

local function cache_key(book, w, h, shade)
    return table.concat({ tostring(book.path or book.group_label), book_title(book), book_author(book),
        tostring(book_number(book)), w, h, shade }, "\30")
end

--- How dark (+) or light (-) a spine is across its width (0: left, 1: right):
--- a rounded spine lit from the left.
local ROUND = { { 0, 0.50 }, { 0.09, 0.12 }, { 0.26, -0.30 }, { 0.48, 0 }, { 0.78, 0.12 }, { 1, 0.55 } }
local function roundness(t)
    for k = 2, #ROUND do
        local a, b = ROUND[k - 1], ROUND[k]
        if t <= b[1] then return a[2] + (b[2] - a[2]) * (t - a[1]) / (b[1] - a[1]) end
    end
    return ROUND[#ROUND][2]
end

--- Shade a stood-up rectangle (a spine, a cover's spine edge) as rounded.
function M.shadeRound(bb, x, y, w, h, strength)
    strength = strength or 1
    for i = 0, w - 1 do
        local f = roundness(w > 1 and i / (w - 1) or 0.5) * strength
        if f > 0.01 then bb:darkenRect(x + i, y, 1, h, f)
        elseif f < -0.01 then bb:lightenRect(x + i, y, 1, h, -f) end
    end
end

--- Room kept at a spine's foot (px at 160 dpi): the letter key's square on
--- a Kindle with a keyboard; a little on the others.
function M.foot()
    local ok, keys = pcall(function() return Device:hasKeyboard() and not Device:isTouchDevice() end)
    return (ok and keys) and 36 or 16
end

-- A line of text's height at a type size (measured once).
local line_h = {}
local function lineH(size)
    if not line_h[size] then
        local t = TextWidget:new{ text = "Ag", face = Font:getFace("cfont", size) }
        line_h[size] = t:getSize().h
        t:free()
    end
    return line_h[size]
end

-- How much of the author's line may tuck under the title's (a line's height
-- has room above and below the letters).
local function tuck(size) return math.floor(lineH(size) * 0.22) end

--- The type sizes for a spine `w` px across: the biggest title (and author)
--- that fit across it, and the smallest the title may shrink to so a long
--- one shows more of itself.
local PAIRS = { { 20, 15 }, { 19, 14 }, { 18, 14 }, { 17, 13 }, { 16, 12 }, { 15, 12 }, { 14, 11 }, { 13, 10 }, { 12, 10 } }
local SINGLE = { 24, 22, 21, 20, 19, 18, 17, 16, 15 }
function M.spineType(w, two)
    local across = w - S(2)
    if two then
        for _i, p in ipairs(PAIRS) do
            if lineH(p[1]) + lineH(p[2]) - tuck(p[2]) <= across then return p[1], p[2], math.min(p[1], math.max(p[1] - 3, 14)) end
        end
        return 12, 10, 12
    end
    for _i, n in ipairs(SINGLE) do
        if lineH(n) <= across then return n, nil, math.min(n, math.max(n - 4, 15)) end
    end
    return 15, nil, 15
end

--- The look of a spine and its shelf follows AndyHazz's Bookshelf plugin
--- (https://github.com/AndyHazz/bookshelf.koplugin, AGPL-3.0;
--- lib/bookshelf_spine_shelf.lua): seen from a little above (12 degrees), so
--- each book shows the top of its page block between its boards; the title
--- runs along the spine with the author after it in smaller type, the number
--- in a series level at the foot; the spine a touch darker at its left edge
--- than its right. Redrawn here for GZreader's greys and letter keys.
M.VIEW_SIN = 0.208      -- sin(12 deg): a depth d shows as d * this
M.COVER_ASPECT = 1.5    -- a cover's height to its width
M.TOP_MAX = 0.2         -- the page block's top: at most this much of the book,
M.TOP_MOST = 13         -- and this many px (at 160 dpi): GZreader's spines are short, the room is the title's
M.RAMP = 0.13           -- how much darker the left edge is, lighter the right
M.BOARD_SHADE = 0.55    -- the boards and the outline: this much darker than the cloth

--- How tall the top of a book h tall shows (0 for a short one): its depth
--- into the shelf is its cover's width.
function M.topEdge(h)
    if h < S(60) then return 0 end
    local e = math.floor(h / M.COVER_ASPECT * M.VIEW_SIN)
    return math.max(S(5), math.min(e, math.floor(h * M.TOP_MAX), S(M.TOP_MOST)))
end

--- The boards' and outline's darkness for a cloth of `shade`.
function M.boardShade(shade) return math.min(1, shade + (1 - shade) * M.BOARD_SHADE) end

--- The top of the page block (w x edge) at x, y on a spine of `shade`: the
--- boards up the sides, a row above the paper (their outer corners left to
--- whatever is behind: Spine:paintTo doesn't copy them), fine page lines.
function M.paintTop(bb, x, y, w, edge, shade)
    if edge <= 1 then return end
    local board = Blitbuffer.gray(M.boardShade(shade))
    local bw = math.max(2, math.min(S(3), math.floor(w * 0.1)))
    local inner_w = w - 2 * bw
    bb:paintRect(x, y, w, edge, board)
    if inner_w > 2 then
        -- (the row above the paper, between the boards: the wall's shadow)
        bb:paintRect(x + bw, y, inner_w, 1, Blitbuffer.gray(0.55))
        bb:paintRect(x + bw, y + 1, inner_w, edge - 1, Blitbuffer.gray(0.06))
        local pitch = math.max(2, math.floor(S(1.4)))
        local cx = x + bw + 1
        while cx < x + bw + inner_w - 1 do
            local lw = math.min(1 + ((cx * 73 + 41) % pitch), x + bw + inner_w - cx)
            bb:paintRect(cx, y + 1, lw, edge - 1, Blitbuffer.gray(0.34))
            cx = cx + pitch + 1
        end
        -- (where the boards meet the spine they turn in: a pixel each side)
        bb:paintRect(x + bw, y + edge - 1, 1, 1, board)
        bb:paintRect(x + bw + inner_w - 1, y + edge - 1, 1, 1, board)
    end
end

--- The cloth's light across a spine (w x h at x, y): darker at the left
--- edge, lighter at the right.
function M.shadeRamp(bb, x, y, w, h)
    if w < 3 then return end
    for i = 0, w - 1 do
        local f = M.RAMP * (2 * i / (w - 1) - 1)
        if f < -0.02 then bb:darkenRect(x + i, y, 1, h, -f)
        elseif f > 0.02 then bb:lightenRect(x + i, y, 1, h, f * 0.8) end
    end
end

--- A title in lines no longer than `room` (width(str) measures): as few as
--- it takes, `max_lines` at most, two lines of about the same length. nil
--- when it can't be done (a word too long, too many lines).
function M.wrapTitle(text, room, width, max_lines)
    local words = {}
    for wd in tostring(text or ""):gmatch("%S+") do words[#words + 1] = wd end
    if #words == 0 then return { "" } end
    local lines, cur = {}, nil
    for _i, wd in ipairs(words) do
        if width(wd) > room then return nil end
        local try = cur and (cur .. " " .. wd) or wd
        if cur and width(try) > room then
            lines[#lines + 1] = cur
            cur = wd
        else
            cur = try
        end
    end
    lines[#lines + 1] = cur
    if #lines > max_lines then return nil end
    if #lines == 2 then
        -- (the split that leaves the two most alike)
        local best, best_w
        for k = 1, #words - 1 do
            local wa, wb = width(table.concat(words, " ", 1, k)), width(table.concat(words, " ", k + 1))
            if wa <= room and wb <= room and (not best_w or math.max(wa, wb) < best_w) then best, best_w = k, math.max(wa, wb) end
        end
        if best then lines = { table.concat(words, " ", 1, best), table.concat(words, " ", best + 1) } end
    end
    return lines
end

M.TITLE_MIN = 12   -- the smallest type a title is set in on a spine
M.AUTHOR_MIN = 10
M.AUTHOR_STUB = 44 -- a cut author's name after the title is shown from this much room (px at 160 dpi)
M.AUTHOR_SEEK = 3  -- a title goes this many sizes smaller to make room for its author

--- How a spine is lettered: the whole title first, in the biggest type it
--- fits in (in lines across the spine when one isn't enough), then its
--- author: after the title's last line where there's room, else on a line
--- of its own (the title up to AUTHOR_SEEK sizes smaller if that shows the
--- whole name; else what fits of it). `room`: the run along the spine; `across`: the spine's width.
--- m = { width(str, size, bold), lineH(size), tuck(size), gap, max }.
--- Returns { size, lines, author = "after" | "line" | nil, a_size, cut = true when the title itself is cut }.
function M.fitSpine(title, author, room, across, m)
    local function height(size, n) return (n - 1) * (m.lineH(size) - m.tuck(size)) + m.lineH(size) end
    local first, bare -- (the first with some of the author; the first with none)
    for size = m.max, M.TITLE_MIN, -1 do
        if first and size < first.size - M.AUTHOR_SEEK then break end
        local max_lines = 0
        while height(size, max_lines + 1) <= across do max_lines = max_lines + 1 end
        local lines = max_lines > 0 and M.wrapTitle(title, room, function(str) return m.width(str, size, true) end, max_lines)
        if lines then
            local a_size = math.max(M.AUTHOR_MIN, size - 3)
            local cand = { size = size, lines = lines, a_size = a_size }
            if author == "" then return cand end
            local left = room - m.width(lines[#lines], size, true) - m.gap
            local a_w = m.width(author, a_size, false)
            local line_fits = height(size, #lines) + m.lineH(a_size) - m.tuck(a_size) <= across
            if a_w <= left then
                cand.author = "after"
                return cand
            end
            if line_fits and a_w <= room then
                cand.author = "line"
                return cand
            end
            cand.author = (line_fits and "line") or (left >= S(M.AUTHOR_STUB) and "after") or nil
            if cand.author and not first then first = cand end
            if not bare then bare = cand end
        end
    end
    -- the title whole; of a long author's name, what fits (on its own line, or after the title)
    if first or bare then return first or bare end
    -- too long even in the smallest type: as many lines as fit, the last one cut
    local size = M.TITLE_MIN
    local max_lines = 1
    while height(size, max_lines + 1) <= across do max_lines = max_lines + 1 end
    local lines, cur = {}, nil
    for wd in tostring(title or ""):gmatch("%S+") do
        local try = cur and (cur .. " " .. wd) or wd
        if cur and #lines < max_lines - 1 and m.width(try, size, true) > room then
            lines[#lines + 1] = cur
            cur = wd
        else
            cur = try
        end
    end
    lines[#lines + 1] = cur or ""
    return { size = size, lines = lines, a_size = M.AUTHOR_MIN, cut = true }
end

local function draw_spine(book, w, h, shade)
    -- drawn lying down (h wide, w tall; its left end is the book's top), then stood up
    local lying = Blitbuffer.new(h, w, Blitbuffer.TYPE_BB8)
    local dark = shade >= 0.5
    local ink = dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    lying:fill(Blitbuffer.gray(shade))
    local edge = M.topEdge(h)
    local foot = S(M.foot())
    -- the number in a series: level at the foot (above the letter key's square)
    local num = book_number(book)
    local n_widget, n_size
    if num then
        n_widget = TextWidget:new{ text = num, face = Font:getFace("cfont", 14), bold = true, fgcolor = ink, max_width = w - S(4) }
        n_size = n_widget:getSize()
    end
    -- the title along the spine, the author after it in smaller type; both
    -- centred in the run between the page block and the foot
    local x0 = edge + S(4)
    local x1 = h - foot - (n_size and (n_size.h + S(2)) or 0)
    local room = x1 - x0
    local across = w - S(4)
    local gap = S(10)
    local text, author = book_title(book), book_author(book)
    local function tw(str, size, bold, max_w)
        return TextWidget:new{ text = str, face = Font:getFace("cfont", size), bold = bold, fgcolor = ink, max_width = max_w }
    end
    local fit = M.fitSpine(text, author, room, across, {
        width = function(str, size, bold)
            local m = TextWidget:new{ text = str, face = Font:getFace("cfont", size), bold = bold }
            local mw = m:getSize().w
            m:free()
            return mw
        end,
        lineH = lineH, tuck = tuck, gap = gap,
        -- (with an author: type that leaves a line for it)
        max = (M.spineType(w, author ~= "")),
    })
    local lh = lineH(fit.size)
    local pitch = lh - tuck(fit.size)
    local block = (#fit.lines - 1) * pitch + lh
    local a_lh = fit.author and lineH(fit.a_size) or 0
    if fit.author == "line" then block = block + a_lh - tuck(fit.a_size) end
    local top = math.max(0, math.floor((w - block) / 2))
    for i, str in ipairs(fit.lines) do
        local line = tw(str, fit.size, true, room)
        local lw = line:getSize().w
        local auth
        if fit.author == "after" and i == #fit.lines then
            auth = tw(author, fit.a_size, false, math.max(1, room - lw - gap))
        end
        local full = lw + (auth and (gap + auth:getSize().w) or 0)
        local lx = x0 + math.max(0, math.floor((room - full) / 2))
        local ly = top + (i - 1) * pitch
        line:paintTo(lying, lx, ly)
        if auth then
            auth:paintTo(lying, lx + lw + gap, ly + math.floor((lh - a_lh) / 2) + S(1))
            auth:free()
        end
        line:free()
    end
    if fit.author == "line" then
        local auth = tw(author, fit.a_size, false, room)
        auth:paintTo(lying, x0 + math.max(0, math.floor((room - auth:getSize().w) / 2)), top + #fit.lines * pitch + tuck(fit.size) - tuck(fit.a_size))
        auth:free()
    end
    local stood = lying:rotatedCopy(270)
    lying:free()
    M.shadeRamp(stood, 0, edge, w, h - edge)
    if n_widget then
        n_widget:paintTo(stood, math.floor((w - n_size.w) / 2), h - foot - n_size.h)
        n_widget:free()
    end
    stood:paintBorder(0, edge, w, h - edge, 1, Blitbuffer.gray(M.boardShade(shade)))
    M.paintTop(stood, 0, 0, w, edge, shade)
    return stood
end

local function spine_bb(book, w, h, shade)
    local key = cache_key(book, w, h, shade)
    local bb = spine_cache[key]
    if bb then return bb end
    if spine_cache_n > 80 then
        for k, v in pairs(spine_cache) do v:free(); spine_cache[k] = nil end
        spine_cache_n = 0
    end
    bb = draw_spine(book, w, h, shade)
    spine_cache[key] = bb
    spine_cache_n = spine_cache_n + 1
    return bb
end

--- Forget the spines drawn (the look changed).
function M.forgetSpines()
    for k, v in pairs(spine_cache) do v:free(); spine_cache[k] = nil end
    spine_cache_n = 0
end

--- A spine (w x h) standing with its foot on the board.
local Spine = WidgetContainer:extend{ w = 0, h = 0, book = nil, shade = 0.5 }
function Spine:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spine:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local img = spine_bb(self.book, self.w, self.h, self.shade)
    local w, h = self.w, self.h
    if M.topEdge(h) > 1 and w > 4 then
        -- the boards' tips: their outer corners aren't drawn (what's behind shows)
        local bw = math.max(2, math.min(S(3), math.floor(w * 0.1)))
        bb:blitFrom(img, x + 1, y, 1, 0, bw - 1, 1)
        bb:blitFrom(img, x + w - bw, y, w - bw, 0, bw - 1, 1)
        bb:blitFrom(img, x, y + 1, 0, 1, w, h - 1)
    else
        bb:blitFrom(img, x, y, 0, 0, w, h)
    end
    -- the foot's corners take the board's tone below them: a slightly
    -- rounded foot, as a real book's
    if y + h < bb:getHeight() and w > 4 then
        bb:blitFrom(bb, x, y + h - 1, x, y + h, 1, 1)
        bb:blitFrom(bb, x + w - 1, y + h - 1, x + w - 1, y + h, 1, 1)
    end
end
function Spine:free() end -- (the picture stays in spine_cache)

--- A spine widget for `book` ({ path, title, authors, series_index }).
function M.newSpine(book, w, h, shade)
    return Spine:new{ w = w, h = h, book = book, shade = shade }
end

---------------------------------------------------------------- depth

M.STAND = 3        -- how far back from its front edge the books stand on the board's top
M.PLANK_BANDS = 5  -- the top is drawn in this many steps (what e-ink can show)
M.PLANK = 0.52     -- the plank's darkness (its front)

--- The board under the books at board_y, `w` wide: its top seen from above,
--- darkest at the back and lighter towards the front edge (narrower at the
--- back), a bright line along the edge, the front, and its shadow on the wall.
function M.paintBoard(bb, x, board_y, w)
    local stand = S(M.STAND)
    local top_h, front_h = S(5) + stand, S(M.BOARD_H) - S(5)
    local y0 = board_y - stand
    local base = M.PLANK
    for i = 0, top_h - 1 do
        local inset = math.floor((top_h - i) * S(6) / top_h)
        local band = math.floor(i * M.PLANK_BANDS / top_h) / (M.PLANK_BANDS - 1)
        -- (lit 0.50 at the back to 0.95 at the front, of the plank's own tone)
        local lit = (1 - base) * (0.50 + 0.45 * band)
        bb:paintRect(x + inset, y0 + i, w - 2 * inset, 1, Blitbuffer.gray(1 - lit))
    end
    local fy = y0 + top_h
    bb:paintRect(x, fy, w, front_h, Blitbuffer.gray(base))
    bb:paintRect(x, fy, w, 1, Blitbuffer.gray(base * 0.45))
    bb:paintRect(x, fy + front_h - 1, w, 1, Blitbuffer.gray(math.min(1, base + 0.3)))
    local under = S(M.UNDER_H)
    for i = 0, under - 1 do
        bb:darkenRect(x + S(4), fy + front_h + i, w - S(8), 1, 0.45 * (1 - i / under))
    end
end

M.RECESS_MAX = 0.26   -- the books' shadow on the wall behind them: at their feet
M.RECESS_TOP = 0.5    -- what's left of it at their tops
M.RECESS_HALO = 6     -- how far it shows above them (px at 160 dpi)
M.RECESS_SIDE = 14    -- and past the ends of a run

--- How tall the shadow stands at px: the tallest of each book's height less
--- the distance to it (a book's shadow leans over what's beside it and falls
--- away at 45 degrees), within `reach`.
function M.recessHorizon(spans, px, reach)
    local best = 0
    for _i, sp in ipairs(spans) do
        local d
        if px < sp.x then d = sp.x - px elseif px >= sp.x + sp.w then d = px - (sp.x + sp.w) + 1 else d = 0 end
        if d <= reach and sp.h - d > best then best = sp.h - d end
    end
    return best
end

--- Where the books stand: their shadow on the wall behind them (a little
--- above their tops, leaning over a shorter neighbour, and past the ends of
--- the row) and where they touch the board.
--- spans = { { x, w, h }, ... } in order, standing on board_y.
function M.paintDepth(bb, board_y, spans)
    if #spans == 0 then return end
    local halo, reach = S(M.RECESS_HALO), S(M.RECESS_SIDE)
    local foot_y = board_y - S(M.STAND)
    local bw = bb:getWidth()
    -- the wall beside and above shorter books: slices, each from where the
    -- book under it ends up to the horizon
    local step = math.max(2, S(2))
    local function slice(px, from_h, dist)
        if px < 0 or px + step > bw then return end
        local top_h = M.recessHorizon(spans, px, reach) + (from_h > 0 and halo or 0)
        if top_h <= from_h then return end
        local fade = 1 - 0.85 * math.min(1, dist / reach)
        local bands = 6
        local span_h = top_h - from_h
        for b = 0, bands - 1 do
            local y1 = from_h + math.floor(span_h * b / bands)
            local y2 = from_h + math.floor(span_h * (b + 1) / bands)
            -- (strongest at the foot, gone at its top edge)
            local t = (b + 0.5) / bands
            local strength = M.RECESS_MAX * (1 - (1 - M.RECESS_TOP) * (y1 + y2) / 2 / math.max(1, top_h)) * fade * (1 - t) ^ 1.5
            if y2 > y1 and strength > 0.02 then bb:darkenRect(px, foot_y - y2, step, y2 - y1, strength) end
        end
    end
    local first, last = spans[1], spans[#spans]
    for px = first.x - reach, first.x - 1, step do slice(px, 0, first.x - px) end
    for px = last.x + last.w, last.x + last.w + reach, step do slice(px, 0, px - (last.x + last.w)) end
    for k, sp in ipairs(spans) do
        local nxt = spans[k + 1]
        -- a gap after it (a cover turned out, an ornament): its shadow falls into the gap
        if nxt and nxt.x > sp.x + sp.w then
            for px = sp.x + sp.w, math.min(nxt.x - 1, sp.x + sp.w + reach), step do slice(px, 0, px - (sp.x + sp.w)) end
            for px = math.max(sp.x + sp.w + reach + 1, nxt.x - reach), nxt.x - 1, step do slice(px, 0, nxt.x - px) end
        end
        -- a little of it shows above the book's top
        for b = 0, 2 do
            local y2 = sp.h + math.floor(halo * (b + 1) / 3)
            local y1 = sp.h + math.floor(halo * b / 3)
            bb:darkenRect(sp.x, foot_y - y2, sp.w, y2 - y1, M.RECESS_MAX * M.RECESS_TOP * (1 - (b + 0.5) / 3) ^ 2.2)
        end
        -- where it touches the board
        bb:darkenRect(sp.x, board_y, sp.w + S(1), S(2), 0.30)
    end
end

M.PAGES = 6 -- how far the pages show behind a cover (px at 160 dpi)

--- A book seen from the front: its cover with the pages behind it (right
--- and bottom), a drop shadow, and the spine's edge rounded on the left.
--- Paints `cover` (a widget of cw x ch) at cx, cy.
function M.paintBook(bb, cover, cx, cy, cw, ch)
    local p = S(M.PAGES)
    -- the shadow on whatever is behind (soft: two steps)
    bb:darkenRect(cx + p + S(5), cy + p + S(5), cw, ch, 0.18)
    bb:darkenRect(cx + p + S(2), cy + p + S(2), cw, ch, 0.22)
    -- the pages: a block of thin lines, its edge drawn
    bb:paintRect(cx + S(2), cy + S(2), cw + p - S(2), ch + p - S(2), Blitbuffer.gray(0.06))
    for yy = cy + S(4), cy + ch + p - S(2), math.max(2, S(3)) do
        bb:paintRect(cx + cw, yy, p - 1, 1, Blitbuffer.gray(0.28))
    end
    for xx = cx + S(4), cx + cw + p - S(2), math.max(2, S(3)) do
        bb:paintRect(xx, cy + ch, 1, p - 1, Blitbuffer.gray(0.28))
    end
    bb:paintBorder(cx + S(2), cy + S(2), cw + p - S(2), ch + p - S(2), 1, Blitbuffer.gray(0.7))
    cover:paintTo(bb, cx, cy)
    -- the spine's edge: rounded, darker
    local edge = math.max(S(6), math.floor(cw * 0.06))
    M.shadeRound(bb, cx, cy, edge, ch, 0.8)
    bb:paintRect(cx + edge, cy, 1, ch, Blitbuffer.gray(0.55))
end

--- A widget showing `cover` as a book (paintBook): the cover's size plus
--- the pages and shadow (S(PAGES) + S(5) more each way).
local Book3D = WidgetContainer:extend{}
function Book3D:getSize()
    local s = self[1]:getSize()
    local extra = S(M.PAGES) + S(5)
    return Geom:new{ w = s.w + extra, h = s.h + extra }
end
function Book3D:paintTo(bb, x, y)
    local s = self[1]:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = s.w, h = s.h }
    M.paintBook(bb, self[1], x, y, s.w, s.h)
end
function M.book3d(cover) return Book3D:new{ cover } end

---------------------------------------------------------------- an empty shelf: cobwebs

local function line(bb, x0, y0, x1, y1, c)
    local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
    for i = 0, n do
        bb:paintRect(math.floor(x0 + (x1 - x0) * i / n + 0.5), math.floor(y0 + (y1 - y0) * i / n + 0.5), 1, 1, c)
    end
end

--- A cobweb in a corner at (ax, ay), opening towards (sx, sy) = (±1, ±1).
local function cobweb(bb, ax, ay, sx, sy, r)
    local c = Blitbuffer.gray(0.45)
    local threads = 6
    local ends = {}
    for k = 0, threads - 1 do
        local a = (math.pi / 2) * k / (threads - 1)
        local ex, ey = ax + sx * math.cos(a) * r, ay + sy * math.sin(a) * r
        line(bb, ax, ay, ex, ey, c)
        ends[#ends + 1] = a
    end
    for _i, f in ipairs({ 0.28, 0.5, 0.72, 0.92 }) do
        for k = 1, #ends - 1 do
            local a0, a1 = ends[k], ends[k + 1]
            local x0, y0 = ax + sx * math.cos(a0) * r * f, ay + sy * math.sin(a0) * r * f
            local x1, y1 = ax + sx * math.cos(a1) * r * f, ay + sy * math.sin(a1) * r * f
            -- (sagging a little towards the corner)
            local am = (a0 + a1) / 2
            local mx, my = ax + sx * math.cos(am) * r * f * 0.9, ay + sy * math.sin(am) * r * f * 0.9
            line(bb, x0, y0, mx, my, c)
            line(bb, mx, my, x1, y1, c)
        end
    end
end

M.cobweb = cobweb -- (GZreader's Grimmory tab: an empty compartment)

---------------------------------------------------------------- a shelf

local Shelf = WidgetContainer:extend{ w = 0, h = 0 }

function Shelf:getSize() return Geom:new{ w = self.w, h = self.h } end

function Shelf:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local area_h = self.area_h
    local board_y = y + area_h
    M.paintBoard(bb, x, board_y, self.w)
    -- the book picked is turned to show its cover, in its place: the books
    -- after it move along (those that no longer fit aren't shown; if the one
    -- picked wouldn't fit, the shelf starts further along)
    local menu = self.menu
    local picked
    for i, slot in ipairs(self.slots) do
        local t = slot.target
        if t and menu and menu._zen_home_focus_id == t.id and slot.book.is_group ~= true then picked = i end
    end
    local face_w = self.cover_w + 2 * S(6) + S(M.PAGES) + S(5)
    local function width_of(i) return i == picked and face_w or self.slots[i].w end
    local room = self.w - S(8) - S(4)
    local first = 1
    if picked then
        local used = 0
        for i = 1, picked do used = used + width_of(i) end
        while used > room and first < picked do used = used - width_of(first); first = first + 1 end
    end
    if self.empty_text then
        -- nothing on it yet: cobwebs in its corners, and a word
        local r = math.min(S(90), math.floor(area_h * 0.4))
        cobweb(bb, x + S(2), y + S(2), 1, 1, r)
        cobweb(bb, x + self.w - S(2), board_y - 1, -1, -1, math.floor(r * 0.8))
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local msg = TextBoxWidget:new{ text = self.empty_text, face = Font:getFace("cfont", 17),
            width = self.w - S(80), alignment = "center", fgcolor = Blitbuffer.gray(0.75) }
        msg:paintTo(bb, x + S(40), y + math.floor((area_h - msg:getSize().h) / 2))
        msg:free()
    end
    self.overlay = nil
    local px = S(8)
    local spans = {}
    for i, slot in ipairs(self.slots) do
        local w = width_of(i)
        if i < first or px + w > S(8) + room then
            slot.hidden = true
        else
            slot.hidden = false
            if i == picked then
                if not slot.cover then
                    slot.cover = cover_common.make_cover_widget(slot.book, self.cover_w, self.cover_h, {
                        border = cover_common.BORDER_SIZE, background = Blitbuffer.COLOR_LIGHT_GRAY })
                end
                -- (the spine's own paint: its focus place and taps)
                self[i]:paintTo(bb, x + px, board_y - slot.h)
                bb:paintRect(x + px, board_y - slot.h, slot.w, slot.h, Blitbuffer.COLOR_WHITE)
                local cs = slot.cover:getSize()
                local cx = x + px + S(6)
                local cy = board_y - cs.h - S(M.PAGES)
                M.paintBook(bb, slot.cover, cx, cy, cs.w, cs.h)
                for k = 0, 1 do
                    bb:paintBorder(cx - S(3) - k, cy - S(3) - k, cs.w + 2 * (S(3) + k), cs.h + 2 * (S(3) + k), 1, Blitbuffer.COLOR_BLACK)
                end
                self.overlay = { rect = Geom:new{ x = cx, y = cy, w = cs.w, h = cs.h }, slot = slot }
            else
                self[i]:paintTo(bb, x + px, board_y - slot.h)
                spans[#spans + 1] = { x = x + px, w = w, h = slot.h }
            end
            px = px + w
        end
        if i ~= picked and slot.cover then slot.cover:free(); slot.cover = nil end
    end
    M.paintDepth(bb, board_y, spans)
end

function Shelf:free()
    for _i, slot in ipairs(self.slots or {}) do
        if slot.cover then slot.cover:free(); slot.cover = nil end
    end
    for i = 1, #self do if self[i].free then pcall(self[i].free, self[i]) end end
end

--- The shelves for `books`: { widget, targets, jobs }.
--- opts = { ctx, width, height, rows, per_row, interactive, source_name, row_offset }
--- per_row: fill each shelf up to it before the next (else shared evenly).
function M.build(books, opts)
    local ctx = opts.ctx
    local width, height = opts.width, opts.height
    local rows = math.max(1, opts.rows or 1)
    local gap = S(10)
    local row_h = math.floor((height - gap * (rows - 1)) / rows)
    local area_h = row_h - S(M.BOARD_H) - S(M.UNDER_H)
    local ratio = tonumber(CoverUtils.getRatio and CoverUtils.getRatio()) or 2 / 3
    -- (the size the cover is drawn at, so a pre-sized one is found)
    local cover_w, cover_h = cover_common.uniform_dims(math.floor(area_h * 0.86 * ratio), math.floor(area_h * 0.86))
    local per_row = tonumber(opts.per_row) or math.ceil(#books / rows)
    local targets, jobs = {}, {}
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local group = VerticalGroup:new{ align = "left" }
    local menu = ctx.menu
    for r = 1, rows do
        local shelf = Shelf:new{ w = width, h = row_h, area_h = area_h, slots = {}, menu = menu,
            cover_w = cover_w, cover_h = cover_h, empty_text = #books == 0 and r == 1 and opts.empty_text or nil }
        local x = S(8)
        for i = (r - 1) * per_row + 1, math.min(#books, r * per_row) do
            local book = books[i]
            local look = M.look(book, area_h)
            if x + look.w > width - S(4) then break end
            local slot = { x = x, w = look.w, h = look.h, book = book }
            local spine = Spine:new{ w = look.w, h = look.h, book = book, shade = look.shade }
            local item = spine
            local path = book.path
            local function open()
                if book.is_group == true then
                    return type(ctx.openStripGroup) == "function" and ctx.openStripGroup(book) or false
                end
                ctx.openBook(path)
                return true
            end
            if opts.interactive and Device:isTouchDevice() then
                local whole = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
                local tap = InputContainer:new{
                    dimen = Geom:new{ w = look.w, h = look.h },
                    ges_events = {
                        TapSpine = { GestureRange:new{ ges = "tap", range = whole } },
                        HoldSpine = { GestureRange:new{ ges = "hold", range = whole } },
                    },
                }
                tap.onTapSpine = function(self_, _, ges)
                    if not (ges and ges.pos) then return false end
                    if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
                    local ov = shelf.overlay
                    if ov and ov.rect:contains(ges.pos) then
                        if ov.slot ~= slot then return false end -- (its own tap handler opens it)
                        return open()
                    end
                    if slot.hidden or not (self_.dimen and self_.dimen:contains(ges.pos)) then return false end
                    if book.is_group == true or not (slot.target and type(ctx.focusHomeTarget) == "function") then
                        return open()
                    end
                    if menu and menu._zen_home_focus_id == slot.target.id then return open() end
                    ctx.focusHomeTarget(slot.target)
                    return true
                end
                tap.onHoldSpine = function(self_, _, ges)
                    if not (ges and ges.pos) then return false end
                    local ov = shelf.overlay
                    local on_cover = ov and ov.slot == slot and ov.rect:contains(ges.pos)
                    if not on_cover and (slot.hidden or ov and ov.rect:contains(ges.pos)
                            or not (self_.dimen and self_.dimen:contains(ges.pos))) then return false end
                    if book.is_group == true then
                        return type(ctx.showStripGroupMenu) == "function" and ctx.showStripGroupMenu(book) or false
                    end
                    return ctx.showBookMenu and ctx.showBookMenu(path, opts.source_name) or false
                end
                tap[1] = spine
                item = tap
            end
            if opts.interactive and type(ctx.prepareHomeFocusTarget) == "function" then
                local target = {
                    key = (book.is_group == true and "group:" or "book:") .. tostring(book.group_label or path),
                    subrow = (opts.row_offset or 0) + r,
                    col = #shelf.slots + 1,
                    path = book.is_group ~= true and path or nil,
                    width = look.w,
                    height = look.h,
                    slow_refresh = true, -- (a cover: greys, not the quick black-and-white refresh)
                    badge_at_bottom = true, -- (the letter key at the foot of the spine)
                    own_focus_box = book.is_group ~= true, -- (the cover pulled out draws it)
                    activate = open,
                    context = function()
                        if book.is_group == true then
                            return type(ctx.showStripGroupMenu) == "function" and ctx.showStripGroupMenu(book) or false
                        end
                        return ctx.showBookMenu and ctx.showBookMenu(path, opts.source_name) or false
                    end,
                }
                if book.is_group ~= true then
                    target.focus_rect = function()
                        local d = shelf.dimen
                        if not d then return { x = 0, y = 0, w = 1, h = 1 } end
                        return { x = d.x, y = d.y - S(8), w = shelf.w, h = shelf.h + S(8) }
                    end
                end
                slot.target = target
                item = ctx.prepareHomeFocusTarget(target, item)
                targets[#targets + 1] = target
            end
            if book.is_group ~= true and book.is_cover_pending and path then
                jobs[#jobs + 1] = { book = book, path = path, width = cover_w, height = cover_h }
            end
            shelf.slots[#shelf.slots + 1] = slot
            shelf[#shelf.slots] = item
            x = x + look.w
        end
        group[#group + 1] = shelf
        if r < rows then group[#group + 1] = VerticalSpan:new{ width = gap } end
    end
    return group, targets, jobs, cover_w, cover_h
end

return M
