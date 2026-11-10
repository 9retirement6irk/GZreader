--[[--
The Grimmory tab's lists in the Bookshelf view, in the bookshop's style
(gzreader_bookshop.lua draws its first page):

- books (All books, a library's, a shelf's, an author's, a series', Continue
  reading, Recently added, a search): covers face out on display ledges, a
  price-tag label under each on the ledge (its letter, your stars or how far
  you are); a ribbon in the ones you're reading, a tick on the finished ones,
  ON KINDLE on the ones downloaded. Load more / Earlier books are bundles of
  spines tied with a tag;
- libraries, shelves and authors (and the Catalog's Audiobooks page, its
  authors, shelves and series, with cassettes in them): bookcase
  compartments with a card clipped
  to each (name, how many, letter): spines between bookends, a book face
  out with the shelf's name, the author's initial on a divider. Magic
  shelves say so, never their rules;
- series: piles of books lying flat, one per series, a card under each;
- audiobooks: a tape rack, a cassette's spine for each (▶ when it's on the
  Kindle);
- a search that found nothing: the same display ledges as its results,
  empty, cobwebs on each, and a card between them saying so.

A search or Refresh line at the top of a list is a slip pinned above it
(and a sign beside it); on later pages a sign shows the list's name. Every
entry keeps the Menu's letter for its place on the page; the 5-way moves
over them; Page turns go through the list as before.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local Views = {
    TAG_TITLE = 14,  -- a tag's title and author type (were 11 and 10)
    TAG_AUTHOR = 12,
    TAG_H = 44,      -- its height (px at 160 dpi)
    TAG_W = 150,     -- the narrowest a tag may be (sets the books a row)
}

local function Shop() return require("gzreader_bookshop") end
local function Shelf() return require("modules/filebrowser/patches/home/widgets/shelf") end

---------------------------------------------------------------- which view

--- "ledges", "tapes", "piles", "bay" or nil (stays as it is) for a list.
function Views.kindOf(items)
    for _i, e in ipairs(type(items) == "table" and items or {}) do
        if type(e) == "table" then
            if e.gz_kind == "nothing_found" then return "ledges" end -- (empty, cobwebs)
            if type(e.book) == "table" then return e.cover_kind == "audiobook" and "tapes" or "ledges" end
            if e.gz_kind == "series" then return "piles" end
            if e.gz_kind == "library" or e.gz_kind == "shelf" or e.gz_kind == "author" then return "bay" end
            -- (the Catalog's Audiobooks page and its series: compartments too)
            if e.gz_kind == "section" or e.gz_kind == "collection" then return "bay" end
        end
    end
    return nil
end

local function isHeader(e) return type(e) == "table" and (e.gz_action == "search" or e.gz_action == "refresh") end

--- How many entries at the start of the list go above it (search, refresh).
function Views.headerCount(items)
    local n = 0
    for _i, e in ipairs(type(items) == "table" and items or {}) do
        if isHeader(e) then n = n + 1 else break end
    end
    return n
end

---------------------------------------------------------------- where things go (pure: run_tests.lua)

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- The slots of a w x h page for `kind`, below a band when `band`.
--- { band = { x, y, w, h } or nil, slots = { { x, y, w, h, row, col } }, rows, cols, ... }
function Views.layout(kind, w, h, band, s)
    s = s or S
    local L = { kind = kind, w = w, h = h, slots = {} }
    local pad = s(12)
    local top = s(6)
    if band then
        L.band = { x = pad, y = top, w = w - 2 * pad, h = s(30) }
        top = top + s(30) + s(10)
    end
    local avail = h - top - s(4)
    local function grid(rows, cols, x0, y0, gw, gh, gap_x)
        local cw = math.floor((gw - (cols - 1) * gap_x) / cols)
        local rh = math.floor(gh / rows)
        for r = 1, rows do
            for c = 1, cols do
                L.slots[#L.slots + 1] = { x = x0 + (c - 1) * (cw + gap_x), y = y0 + (r - 1) * rh, w = cw, h = rh, row = r, col = c }
            end
        end
        L.rows, L.cols = rows, cols
    end
    if kind == "ledges" then
        -- a ledge row: the cover, its pages, the ledge, the tag under it
        -- (its title and author: 1.22.3; bigger type: 1.22.6)
        local fixed = s(11) + s(10) + s(Views.TAG_H + 4) + s(8)
        local rows = clamp(math.floor(avail / (s(88) + fixed)), 1, 4)  -- (3 rows on a Kindle 3)
        local box_h = math.floor(avail / rows) - fixed
        local box_w = math.floor(box_h * 0.7)
        local gap = s(14)
        local cols = clamp(math.floor((w - 2 * pad + gap) / (box_w + s(11) + gap)), 2, 8)
        -- (each tag wide enough for a title in its bigger type: 3 a row on
        -- a Kindle 3 or a Paperwhite)
        cols = math.max(2, math.min(cols, math.floor((w - 2 * pad + gap) / (s(Views.TAG_W) + gap))))
        grid(rows, cols, pad, top, w - 2 * pad, avail, gap)
        L.box_h = box_h
        L.box_w = math.min(box_w, L.slots[1].w - s(11))
        L.fixed = fixed
    elseif kind == "bay" then
        local inner = avail - s(11)
        local rows = clamp(math.floor(inner / s(76)), 2, 8)
        L.case = { x = s(10), y = top, w = w - 2 * s(10), h = avail, top = s(8), side = s(3) }
        grid(rows, 2, L.case.x + s(3), top + s(8), L.case.w - 2 * s(3), avail - s(11), s(7))
    elseif kind == "piles" then
        local rows = clamp(math.floor(avail / s(165)), 1, 3)
        local cols = clamp(math.floor((w - 2 * pad) / s(170)), 2, 5)
        grid(rows, cols, pad, top, w - 2 * pad, avail, s(10))
    elseif kind == "tapes" then
        local inner = avail - s(14)
        local row_h = s(35)
        local rows = clamp(math.floor(inner / row_h), 2, 16)
        L.case = { x = s(10), y = top, w = w - 2 * s(10), h = avail, top = s(10), side = s(3) }
        grid(rows, 2, L.case.x + s(10), top + s(10) + s(4), L.case.w - 2 * s(10), rows * row_h, s(12))
    end
    L.fits = #L.slots > 0 and L.slots[1].w >= s(60) and L.slots[1].h >= s(30) and (kind ~= "ledges" or L.box_h >= s(50))
    return L
end

--- What a book's label on the ledge says: your stars, else how far you are.
function Views.bookLabel(book)
    local rating = tonumber(book.personalRating)
    if rating and rating > 0 then
        local stars = math.max(1, math.min(5, math.floor(rating / 2 + 0.5)))
        return string.rep("★", stars) .. string.rep("☆", 5 - stars)
    end
    local pct = tonumber(book.readProgress)
    if pct and pct > 0 then return T("%1%", math.floor(pct + 0.5)) end
    return nil
end

--- A compartment's card for a library, shelf or author (or a page's section:
--- what it says under its name).
function Views.cardOf(e)
    if e.gz_kind == "section" then return e.mandatory or "" end
    local n = tonumber(e.gz_count)
    local count = n and (e.gz_audio and (n == 1 and _("1 audiobook") or T(_("%1 audiobooks"), n))
        or (n == 1 and _("1 book") or T(_("%1 books"), n))) or nil
    if e.gz_kind == "shelf" and e.gz_magic then
        return count and T(_("magic · %1"), count) or _("magic shelf")
    end
    return count or e.mandatory or ""
end

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }
function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

local function hand(size) return Shop().draw.hand(size) end

function Page:paintBand(bb, x, y)
    local D = Shop().draw
    local b = self.L.band
    if not b then return end
    local bx, by, bw, bh = x + b.x, y + b.y, b.w, b.h
    if #self.headers == 0 then
        -- a later page: the list's name on a sign
        D.sign(bb, self.menu, { x = bx, y = by + S(3), h = bh - S(6) }, self.title or "", self.page_text, nil)
        return
    end
    -- signs (Refresh…) on the right, the slip (search) taking the rest
    local right = bx + bw
    for k = #self.headers, 1, -1 do
        local hd = self.headers[k]
        if hd.entry.gz_action ~= "search" then
            local label = hd.entry.gz_action == "refresh" and _("Refresh") or (hd.entry.text or "")
            local TextWidget = require("ui/widget/textwidget")
            local t = TextWidget:new{ text = label, face = hand(20) }
            local side = (hd.letter and self.menu.is_enable_shortcut) and S(20) or 0
            local w = S(8) + (side > 0 and side + S(8) or 0) + t:getSize().w + S(12)
            t:free()
            local r = D.sign(bb, self.menu, { x = right - w, y = by + S(3), h = bh - S(6) }, label, nil, hd.letter)
            hd.hot.dimen = Geom:new(r)
            if hd.hot.focused then D.focusRing(bb, r) end
            right = right - w - S(10)
        end
    end
    for _k, hd in ipairs(self.headers) do
        if hd.entry.gz_action == "search" then
            local sw = right - bx
            bb:paintRect(bx + S(2), by + S(3), sw, bh, D.gray(0.3))
            bb:paintRect(bx, by, sw, bh, Blitbuffer.COLOR_WHITE)
            bb:paintRect(bx + S(4), by + bh - S(8), sw - S(8), 1, D.gray(0.25))
            bb:paintBorder(bx, by, sw, bh, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
            D.clip(bb, bx + math.floor(sw / 2), by, S(28))
            local r = math.floor(bh * 0.2)
            local mx, my = bx + S(12) + r, by + math.floor(bh / 2) - S(2)
            bb:paintCircle(mx, my, r, Blitbuffer.COLOR_BLACK, math.max(2, S(2)))
            for k = 0, math.floor(r * 0.9) do
                bb:paintRect(mx + r - S(1) + k, my + r - S(1) + k, math.max(2, S(3)), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
            end
            local side = (hd.letter and self.menu.is_enable_shortcut) and S(20) or 0
            local label = (hd.entry.text or ""):gsub("…$", "")
            D.text(bb, label .. "…", hand(20), mx + r + S(14), by + math.floor(bh / 2),
                { middle = true, color = D.gray(0.6), max_width = sw - S(60) - side })
            if side > 0 then D.badge(bb, self.menu, hd.letter, bx + sw - side - S(8), by + math.floor((bh - side) / 2), side) end
            hd.hot.dimen = Geom:new{ x = bx, y = by, w = sw, h = bh }
            if hd.hot.focused then D.focusRing(bb, hd.hot.dimen) end
            break
        end
    end
end

--- A message where there's nothing to show (Nothing here yet, No books match…).
local function message(bb, text, x, y, w)
    local D = Shop().draw
    D.text(bb, text, hand(22), x + math.floor(w / 2), y, { center = true, middle = true, color = D.gray(0.7), max_width = w - S(20) })
end

function Page:paintLedges(bb, x, y)
    local D = Shop().draw
    local Sh = Shelf()
    local L = self.L
    local p = S(Sh.PAGES)
    local nothing -- (a search that found nothing)
    -- the ledges, one per row (drawn after the books: the books stand on them)
    local ledges = {}
    for r = 1, L.rows do
        local s1 = L.slots[(r - 1) * L.cols + 1]
        local base = y + s1.y + s1.h - S(8) - S(40) - S(10)
        ledges[r] = { x = x + S(8), y = base, w = self.w - 2 * S(8), h = S(10) }
    end
    for k, sl in ipairs(self.slots) do
        local slot = L.slots[k]
        local led = ledges[slot.row]
        local cx = x + slot.x
        local bottom = led.y
        local e = sl.entry
        if e.book then
            local book = e.book
            local widget, iw, ih = D.cover(book, L.box_w, L.box_h)
            local bx = cx + math.floor((slot.w - iw - p) / 2)
            local by = bottom - ih - p
            Sh.paintBook(bb, widget, bx, by, iw, ih)
            if widget.free then widget:free() end
            sl.hot.dimen = Geom:new{ x = bx, y = by, w = iw, h = ih }
            local pct = tonumber(book.readProgress)
            if pct and pct >= 99.5 then
                -- finished: a tick in a circle on the corner
                local r = S(11)
                local tx, ty = bx + iw - r - S(5), by + r + S(5)
                bb:paintCircle(tx, ty, r, Blitbuffer.COLOR_WHITE)
                bb:paintCircle(tx, ty, r, Blitbuffer.COLOR_BLACK, math.max(2, S(2)))
                for i = 0, S(4) do bb:paintRect(tx - S(5) + i, ty + i - S(1), math.max(2, S(2)), math.max(2, S(2)), Blitbuffer.COLOR_BLACK) end
                for i = 0, S(7) do bb:paintRect(tx - S(1) + i, ty + S(3) - i, math.max(2, S(2)), math.max(2, S(2)), Blitbuffer.COLOR_BLACK) end
            elseif pct and pct > 0 then
                D.ribbon(bb, bx + iw - S(16), by - S(2), S(9), math.min(S(26), math.floor(ih * 0.25)), Blitbuffer.COLOR_BLACK)
            end
            if self.browser and self.browser.plugin and self.browser.plugin.localPathFor
                    and self.browser.plugin:localPathFor(book.id) then
                local TextWidget = require("ui/widget/textwidget")
                local t = TextWidget:new{ text = _("ON KINDLE"), face = Font:getFace("cfont", 8), bold = true, fgcolor = Blitbuffer.COLOR_WHITE }
                local ts = t:getSize()
                bb:paintRect(bx + S(8), by + ih - ts.h - S(6), ts.w + S(6), ts.h, Blitbuffer.COLOR_BLACK)
                t:paintTo(bb, bx + S(11), by + ih - ts.h - S(6))
                t:free()
            end
            -- its tag on the ledge's front: its letter, title and author (and
            -- your stars or how far you are)
            Views.paintTag(bb, self.menu, cx, led.y + led.h + S(4), slot.w, sl.letter, book)
            if sl.hot.focused then D.focusRing(bb, sl.hot.dimen) end
        elseif e.gz_action == "more" or e.gz_action == "earlier" then
            local r = D.bundle(bb, { x = cx, w = slot.w }, bottom, L.box_h,
                e.gz_action == "more" and _("Load more") or _("Earlier"), e.gz_action)
            sl.hot.dimen = Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
            if sl.hot.focused then D.focusRing(bb, sl.hot.dimen) end
            local side = (sl.letter and self.menu.is_enable_shortcut) and S(18) or 0
            if side > 0 then D.badge(bb, self.menu, sl.letter, cx + math.floor((slot.w - side) / 2), led.y + led.h + S(8), side) end
        elseif e.gz_kind == "nothing_found" then
            nothing = e
        else
            message(bb, e.text or "", x + L.slots[1].x, bottom - math.floor(L.box_h / 2), self.w - 2 * L.slots[1].x)
        end
    end
    if nothing then
        -- a search that found nothing: every ledge empty, cobwebs on each
        -- (alternating corners), the message on a card between them
        local web = Shelf().cobweb
        for r = 1, L.rows do
            local top = y + L.slots[(r - 1) * L.cols + 1].y
            local led = ledges[r]
            local rad = math.max(S(20), math.min(S(70), math.floor((led.y - top) * 0.6)))
            local left, right = led.x + S(2), led.x + led.w - S(3)
            if web then
                if r % 2 == 1 then
                    web(bb, left, top, 1, 1, rad)
                    web(bb, right, led.y - 1, -1, -1, math.floor(rad * 0.7))
                else
                    web(bb, right, top, -1, 1, rad)
                    web(bb, left, led.y - 1, 1, -1, math.floor(rad * 0.7))
                end
            end
        end
        local mid = math.ceil(L.rows / 2)
        local top = y + L.slots[(mid - 1) * L.cols + 1].y
        Views.paintNothingCard(bb, nothing.text or "", x, top, self.w, ledges[mid].y - top)
    end
    for r = 1, L.rows do D.ledge(bb, ledges[r]) end
end

--- A price tag under a cover (x, y: its top-left; w: the slot's width).
function Views.paintTag(bb, menu, x, y, w, letter, book)
    local D = Shop().draw
    local TextWidget = require("ui/widget/textwidget")
    local side = (letter and menu.is_enable_shortcut) and S(18) or 0
    local tw, th = w - S(4), S(Views.TAG_H)
    local tx0 = x + S(2)
    bb:paintRect(tx0 + S(2), y + S(2), tw, th, D.gray(0.3))
    bb:paintRect(tx0, y, tw, th, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(tx0, y, tw, th, 1, Blitbuffer.COLOR_BLACK)
    local tx = tx0 + S(4)
    if side > 0 then D.badge(bb, menu, letter, tx, y + S(3), side); tx = tx + side + S(4) end
    local room = tx0 + tw - tx - S(4)
    local t = TextWidget:new{ text = book.title or "?", face = Font:getFace("cfont", Views.TAG_TITLE), bold = true, max_width = room }
    t:paintTo(bb, tx, y + S(2))
    local t_h = t:getSize().h
    t:free()
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    local label = Views.bookLabel(book)
    local second = authors ~= "" and authors or ""
    if label then second = second ~= "" and (label .. "  " .. second) or label end
    if second ~= "" then
        -- (under the letter too: the whole tag's width)
        local ax = side > 0 and (tx0 + S(4)) or tx
        local a = TextWidget:new{ text = second, face = Font:getFace("cfont", Views.TAG_AUTHOR), fgcolor = D.gray(0.85),
            max_width = tx0 + tw - ax - S(4) }
        a:paintTo(bb, ax, y + S(1) + math.max(t_h, side))
        a:free()
    end
end

function Page:paintBay(bb, x, y)
    local D = Shop().draw
    local c = self.L.case
    local cx, cy = x + c.x, y + c.y
    -- as many rows as there are compartments to fill (a short list: a
    -- smaller bookcase, not one full of cobwebs)
    local used = 0
    for k in pairs(self.slots) do used = math.max(used, k) end
    local rows = math.max(1, math.min(self.L.rows, math.ceil(used / 2)))
    local last = self.L.slots[rows * 2]
    local ch = last.y + last.h + S(3) - c.y
    bb:paintRect(cx + S(4), cy + S(4), c.w, ch, D.gray(0.25))
    bb:paintRect(cx, cy, c.w, ch, D.gray(0.86))
    for i = 0, c.top - 1 do bb:paintRect(cx - S(2), cy + i, c.w + S(4), 1, D.gray(0.7 + 0.15 * i / c.top)) end
    for k, slot in ipairs(self.L.slots) do
        if k > rows * 2 then break end
        local sl = self.slots[k]
        local sx, sy = x + slot.x, y + slot.y
        if not sl then
            Shop().paintCompartment(bb, self.menu, sx, sy, slot.w, slot.h, { kind = "empty" })
        elseif sl.entry.gz_kind then
            local e = sl.entry
            local kind = e.gz_contents or e.gz_kind == "library" and "spines" or e.gz_kind == "shelf" and "faceout" or "dividers"
            local name = e.text or ""
            local initial = name:match("^[%w]") and name:sub(1, 1):upper() or "·"
            Shop().paintCompartment(bb, self.menu, sx, sy, slot.w, slot.h,
                { kind = kind, name = name, sub = Views.cardOf(e), letter = sl.letter, hot = sl.hot },
                { seed = name, shelf_name = name, letters = { initial } })
        else
            Shop().paintCompartment(bb, self.menu, sx, sy, slot.w, slot.h, { kind = "empty" })
            message(bb, sl.entry.text or "", sx, sy + math.floor(slot.h / 2), slot.w)
            if sl.hot then sl.hot.dimen = Geom:new{ x = sx, y = sy, w = slot.w, h = slot.h } end
        end
    end
end

--- Where the "nothing found" card goes in the area cx, cy, cw, ch (tw, th:
--- the message's size): in its middle, never wider. Pure: run_tests.lua.
function Views.nothingCard(cx, cy, cw, ch, tw, th, s)
    s = s or S
    local w = math.min(cw - s(40), tw + s(48))
    local h = th + s(36)
    return { x = cx + math.floor((cw - w) / 2), y = cy + math.floor((ch - h) / 2), w = w, h = h }
end

--- The card pinned in the middle of the area, with the message.
function Views.paintNothingCard(bb, msg, cx, cy, cw, ch)
    local D = Shop().draw
    local TextWidget = require("ui/widget/textwidget")
    local face = hand(22)
    local probe = TextWidget:new{ text = msg, face = face }
    local sz = probe:getSize()
    probe:free()
    local r = Views.nothingCard(cx, cy, cw, ch, sz.w, sz.h)
    bb:paintRect(r.x + S(3), r.y + S(3), r.w, r.h, D.gray(0.35))
    bb:paintRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    D.clip(bb, r.x + math.floor(r.w / 2), r.y, S(24))
    D.text(bb, msg, face, r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2) + S(4),
        { center = true, middle = true, max_width = r.w - S(24) })
end

function Page:paintPiles(bb, x, y)
    local D = Shop().draw
    local L = self.L
    local card_h, board_h = S(48), S(10)
    for r = 1, L.rows do
        local s1 = L.slots[(r - 1) * L.cols + 1]
        local by = y + s1.y + s1.h - card_h - S(8) - board_h
        -- the board the piles stand on
        for i = 0, board_h - 1 do bb:paintRect(x + S(8), by + i, self.w - 2 * S(8), 1, D.gray(0.62 - 0.2 * i / board_h)) end
        bb:paintRect(x + S(8), by, self.w - 2 * S(8), math.max(2, S(3)), D.gray(0.25))
        for i = 0, S(4) - 1 do bb:darkenRect(x + S(12), by + board_h + i, self.w - 2 * S(12), 1, 0.35 * (1 - i / S(4))) end
    end
    for k, sl in ipairs(self.slots) do
        local slot = L.slots[k]
        local sx, sy = x + slot.x, y + slot.y
        local board_y = sy + slot.h - card_h - S(8) - board_h
        local e = sl.entry
        if e.gz_kind == "series" then
            local n = clamp(tonumber(e.gz_count) or 3, 1, 8)
            local room = board_y - sy - S(6)
            local bh = clamp(math.floor(room / n), S(8), S(15))
            local cxm = sx + math.floor(slot.w / 2)
            local yy = board_y
            for j = 1, n do
                local hv = D.hash((e.gz_name or e.text or "") .. j)
                local bw = math.floor(slot.w * (0.62 + (hv % 22) / 100))
                local bx = cxm - math.floor(bw / 2) + (math.floor(hv / 7) % S(9)) - S(4)
                local shade = ({ 0.78, 0.12, 0.55, 0.3, 0.88, 0.45, 0.2, 0.65 })[(hv % 8) + 1]
                bb:paintRect(bx, yy - bh, bw, bh, D.gray(shade))
                bb:darkenRect(bx, yy - S(2), bw, S(2), 0.3)
                bb:lightenRect(bx, yy - bh, bw, S(2), 0.3)
                bb:paintBorder(bx, yy - bh, bw, bh, 1, D.gray(0.9))
                bb:paintRect(bx + bw - S(4), yy - bh + S(2), S(3), bh - S(4), D.gray(0.08))
                -- its number in the series on the spine
                if bh >= S(12) then
                    D.text(bb, tostring(j), Font:getFace("cfont", 8), bx + S(6), yy - math.floor(bh / 2),
                        { bold = true, middle = true, color = shade >= 0.5 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK })
                end
                yy = yy - bh
            end
            sl.hot.dimen = Geom:new{ x = sx, y = sy, w = slot.w, h = slot.h }
            -- its card under the board
            local cw = slot.w - S(8)
            local ccx, ccy = sx + S(4), board_y + board_h + S(6)
            bb:paintRect(ccx + S(3), ccy + S(3), cw, card_h, D.gray(0.35))
            bb:paintRect(ccx, ccy, cw, card_h, Blitbuffer.COLOR_WHITE)
            bb:paintBorder(ccx, ccy, cw, card_h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
            local side = (sl.letter and self.menu.is_enable_shortcut) and S(20) or 0
            local tx = ccx + S(6)
            if side > 0 then D.badge(bb, self.menu, sl.letter, tx, ccy + S(5), side); tx = tx + side + S(6) end
            local sz = D.text(bb, e.gz_name or e.text or "", hand(19), tx, ccy + S(3), { max_width = ccx + cw - tx - S(6) })
            local sub = T(_("%1 books"), tostring(e.gz_count or "?"))
            if e.gz_authors and e.gz_authors ~= "" then sub = sub .. " · " .. e.gz_authors end
            D.text(bb, sub, Font:getFace("cfont", 10), ccx + S(6), ccy + S(4) + math.max(sz.h, side),
                { color = D.gray(0.8), max_width = cw - S(12) })
            if sl.hot.focused then D.focusRing(bb, Geom:new{ x = ccx, y = ccy, w = cw, h = card_h }) end
        else
            message(bb, e.text or "", sx, board_y - S(40), slot.w)
        end
    end
end

function Page:paintTapes(bb, x, y)
    local D = Shop().draw
    local L = self.L
    local c = L.case
    local cx, cy = x + c.x, y + c.y
    local bottom = y + L.slots[#L.slots].y + L.slots[#L.slots].h + S(8)
    local ch = bottom - cy
    bb:paintRect(cx + S(4), cy + S(4), c.w, ch, D.gray(0.25))
    bb:paintRect(cx, cy, c.w, ch, D.gray(0.82))
    bb:paintRect(cx + c.side, cy + c.top, c.w - 2 * c.side, ch - c.top - c.side, D.gray(0.12))
    for i = 0, c.top - 1 do bb:paintRect(cx - S(2), cy + i, c.w + S(4), 1, D.gray(0.7 + 0.15 * i / c.top)) end
    local looks = { 0.06, 0.78, 0.4, 0.06, 0.78 }
    for k, sl in ipairs(self.slots) do
        local slot = L.slots[k]
        local sx, sy, sw, sh = x + slot.x, y + slot.y + S(2), slot.w, slot.h - S(6)
        local e = sl.entry
        local shade = e.book and looks[(D.hash(e.book.id) % #looks) + 1] or 0
        local ink = shade >= 0.5 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        bb:paintRect(sx + S(2), sy + S(3), sw, sh, D.gray(0.4))
        bb:paintRect(sx, sy, sw, sh, D.gray(shade))
        bb:lightenRect(sx, sy, sw, math.floor(sh * 0.35), 0.25)
        bb:paintBorder(sx, sy, sw, sh, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
        bb:paintRect(sx + S(4), sy + S(3), math.max(1, S(2)), sh - S(6), D.gray(0.5))
        local tx = sx + S(10)
        local side = (sl.letter and self.menu.is_enable_shortcut) and S(18) or 0
        if side > 0 then D.badge(bb, self.menu, sl.letter, tx, sy + math.floor((sh - side) / 2), side); tx = tx + side + S(6) end
        local right = sx + sw - S(8)
        local here = e.book and self.here and self.here[tostring(e.book.id)]
        if here then
            -- on the Kindle: a play mark at the end
            local sym = math.floor(sh * 0.45)
            local Skeuo = require("gzreader_skeuo")
            bb:paintRect(right - sym - S(4), sy + math.floor((sh - sym) / 2) - S(2), sym + S(6), sym + S(4), Blitbuffer.COLOR_WHITE)
            Skeuo.symbol(bb, "play", right - math.floor(sym / 2) - S(1), sy + math.floor(sh / 2), sym)
            right = right - sym - S(10)
        end
        local title = e.book and (e.book.title or "?") or ((e.text or ""):gsub("…$", "") .. "…")
        local authors = e.book and type(e.book.authors) == "table" and table.concat(e.book.authors, ", ") or ""
        local a_w = 0
        if authors ~= "" then
            local TextWidget = require("ui/widget/textwidget")
            local a = TextWidget:new{ text = authors, face = Font:getFace("cfont", 10), fgcolor = ink, max_width = math.floor((right - tx) * 0.4) }
            a_w = a:getSize().w
            a:paintTo(bb, right - a_w, sy + math.floor((sh - a:getSize().h) / 2))
            a:free()
        end
        D.text(bb, title, hand(18), tx, sy + math.floor(sh / 2), { middle = true, color = ink, max_width = right - tx - a_w - S(8) })
        sl.hot.dimen = Geom:new{ x = sx, y = sy, w = sw, h = sh }
        if sl.hot.focused then D.focusRing(bb, sl.hot.dimen) end
    end
end

function Page:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    Shop().draw.wall(bb, x, y, self.w, self.h)
    self:paintBand(bb, x, y)
    local kind = self.L.kind
    if kind == "ledges" then self:paintLedges(bb, x, y)
    elseif kind == "bay" then self:paintBay(bb, x, y)
    elseif kind == "piles" then self:paintPiles(bb, x, y)
    elseif kind == "tapes" then self:paintTapes(bb, x, y) end
end

---------------------------------------------------------------- building a page

--- Draw the page of `m` (a Grimmory tab list) as `kind`. False: it doesn't
--- fit (the usual view instead).
function Views.build(m, browser, kind, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    m:_recalculateDimen(no_recalculate_dimen)
    local W = m.item_dimen.w
    local H = m.available_height
    local nhead = Views.headerCount(m.item_table)
    local L = Views.layout(kind, W, H, nhead > 0)
    if not L.fits then return false end
    -- as many on a page as there are places (the Menu's letters, its pages)
    if m.items_per_page ~= #L.slots then
        m.items_per_page = #L.slots
        m:_recalculateDimen(false)
    end
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    local Shop_ = Shop()
    local Hot = Shop_.Hot
    local page = Page:new{ w = W, h = H, L = L, menu = m, browser = browser, headers = {}, slots = {},
        title = m.title, page_text = m.page_num > 1 and T("%1 / %2", m.page, m.page_num) or nil }
    local per = m.perpage
    local offset = (m.page - 1) * per
    require("gzreader_covers").beginPage()
    local wanted = {}
    local header_row = {}
    local rows = {}
    local slot_k = 0
    for i = 1, per do
        local e = m.item_table[offset + i]
        if not e then break end
        e.idx = offset + i
        local letter = m.is_enable_shortcut and m.item_shortcuts and m.item_shortcuts[i] or nil
        local hot = Hot:new{ menu = m, entry = e, shop = page }
        if offset + i <= nhead then
            page.headers[#page.headers + 1] = { entry = e, letter = letter, hot = hot }
            page[#page + 1] = hot
            header_row[#header_row + 1] = hot
        else
            slot_k = slot_k + 1
            local slot = L.slots[slot_k]
            if not slot then break end
            page.slots[slot_k] = { entry = e, letter = letter, hot = hot }
            local selectable = e.select_enabled ~= false
            if selectable then
                page[#page + 1] = hot
                rows[slot.row] = rows[slot.row] or {}
                table.insert(rows[slot.row], hot)
            end
            if e.book and kind == "ledges" then wanted[#wanted + 1] = { id = e.book.id } end
        end
    end
    if kind == "tapes" then
        -- which audiobooks are on the Kindle
        page.here = {}
        pcall(function()
            local Audiobook = require("gzreader_audiobook")
            for _k, sl in pairs(page.slots) do
                local b = sl.entry.book
                if b and Audiobook.load(browser.plugin, b.id) ~= nil then page.here[tostring(b.id)] = true end
            end
        end)
    end
    if #header_row > 0 then m.layout[#m.layout + 1] = header_row end
    for r = 1, L.rows or 0 do
        if rows[r] and #rows[r] > 0 then m.layout[#m.layout + 1] = rows[r] end
    end
    table.insert(m.item_group, page)
    m._gz_view = page
    -- the focus: on what was chosen (back from it), else the first thing in the list
    local fx, fy = 1, (#header_row > 0 and m.layout[2]) and 2 or 1
    local back = select_number and m.item_table[offset + select_number]
    if back then
        for yy, r in ipairs(m.layout) do
            for xx, h in ipairs(r) do if h.entry == back then fx, fy = xx, yy end end
        end
    end
    m:updatePageInfo(1)
    if (fx > 1 or fy > 1) and Device:hasDPad() and m.layout[fy] then
        local FocusManager = require("ui/widget/focusmanager")
        m:moveFocusTo(fx, fy, FocusManager.FOCUS_ONLY_ON_NT)
    end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    if #wanted > 0 then
        local items, pg = m.item_table, m.page
        require("gzreader_covers").fetch(browser.plugin, wanted, function(got)
            if got > 0 and m.item_table == items and m.page == pg and not m._gz_closed then pcall(m.updateItems, m) end
        end)
    end
    return true
end

return Views
