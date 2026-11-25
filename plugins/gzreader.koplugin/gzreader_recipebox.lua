--[[--
The Recipes tab in the Bookshelf view (common/gz_view.lua; the other views
keep the list, gzreader_recipes.lua): your Mealie recipes as a recipe box
on the kitchen counter, seen from the front.

- Refresh on a sign above the box, with how many recipes and when;
- Mealie's categories as the index dividers' tabs along the top of the box:
  All first, the chosen one standing taller, in black; when there are more
  than fit, the last tab is More… (the list's Category window);
- the recipes as cards filed in the box, one behind the other: each shows
  its top edge with the name in handwriting and how long it takes. A page
  holds as many cards as the box is deep, so the pages are this view's own;
- on the box's front, a brass label holder for Search (it shows the words
  searched for) and two tags: the order, and More cards while Mealie has
  more.

On a colour screen the box is wood, the cards cream and the dividers' tabs
in three colours; greys everywhere else.

The page draws the tab's own rows (Recipes:rootItems), so a tap, Press or a
letter does what the row did; only the dividers' tabs are this view's (they
set the tab's category as the Category window does). Letters go to what
does something, in order; the 5-way moves over them.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local View = {
    CARD_H = 48,         -- how much of a filed card shows
    TAB_W = 86,          -- the narrowest a divider's tab may be (sets how many)
    MAX_TABS = 7,
    -- { grey (0 white … 1 black), { r, g, b } on a colour screen }
    PAL = {
        counter = { 0.10, { 235, 228, 211 } },
        wood = { 0.40, { 189, 143, 98 } },
        well = { 0.62, { 128, 88, 50 } },
        grain = { 0.52, { 160, 116, 74 } },
        card = { 0, { 252, 247, 232 } },
        rule = { 0.25, { 150, 190, 212 } },
        brass = { 0.16, { 220, 187, 106 } },
        tabs = { { 0.10, { 241, 200, 118 } }, { 0.22, { 156, 199, 165 } }, { 0.03, { 234, 165, 149 } } },
    },
}

local function Shop() return require("gzreader_bookshop") end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------- when

--- What each row of the tab's list is in the box: "refresh", "search",
--- "category", "order", "card" (a recipe), "more" (More recipes) or "note"
--- (anything else: Loading…, nothing found, why it couldn't update).
function View.kinds(items)
    local out = {}
    for i, it in ipairs(items or {}) do
        local k = "note"
        if type(it) == "table" then
            if it.gz_recipe then k = "card"
            elseif it.gz_more then k = "more"
            elseif it.gz_recipes == "refresh" or it.gz_recipes == "search" or it.gz_recipes == "category" or it.gz_recipes == "order" then
                k = it.gz_recipes
            end
        end
        out[i] = k
    end
    return out
end

--- The box instead of the list: the Bookshelf view, and the connected
--- tab's rows (it has a Search row).
function View.applies(m, tab)
    if type(m) ~= "table" or type(m.item_table) ~= "table" or not tab then return false end
    if not Shop().bookshelf() then return false end
    for _i, it in ipairs(m.item_table) do
        if type(it) == "table" and it.gz_recipes == "search" then return true end
    end
    return false
end

---------------------------------------------------------------- the dividers

--- The dividers' tabs for `n` places: { { all = true } | { id, name } |
--- { more = true }, …, chosen = index }. `cats`: Mealie's categories
--- ({ id, name }, as last fetched; may be nil), `chosen`: the tab's
--- category ({ id, name }) or nil for All. All is always first; when the
--- categories don't all fit the last tab is More…, and the chosen one is
--- always among those shown.
function View.dividers(cats, chosen, n)
    n = math.max(2, n or 2)
    local out = { { all = true } }
    local list = {}
    for _i, c in ipairs(type(cats) == "table" and cats or {}) do
        if type(c) == "table" and c.id and c.name then list[#list + 1] = { id = c.id, name = c.name } end
    end
    local known = false
    for _i, c in ipairs(list) do if chosen and c.id == chosen.id then known = true end end
    if chosen and not known then list[#list + 1] = { id = chosen.id, name = chosen.name or "?" } end
    if #list + 1 <= n then
        for _i, c in ipairs(list) do out[#out + 1] = c end
    else
        local room = n - 2 -- (between All and More…)
        local shown, has = {}, false
        for i = 1, room do
            shown[i] = list[i]
            if chosen and list[i].id == chosen.id then has = true end
        end
        if chosen and not has and room >= 1 then
            for _i, c in ipairs(list) do if c.id == chosen.id then shown[room] = c end end
        end
        for _i, c in ipairs(shown) do out[#out + 1] = c end
        out[#out + 1] = { more = true }
    end
    out.chosen = 1
    for i, d in ipairs(out) do
        if chosen and d.id == chosen.id then out.chosen = i end
    end
    -- (a category chosen that has no place of its own: 2 places only)
    if chosen and out.chosen == 1 and out[#out].more then out.chosen = #out end
    return out
end

---------------------------------------------------------------- where things go

--- Where everything goes in a w x h page (px; s = the screen's scale
--- function). `kinds`: View.kinds. Pure: tested in run_tests.lua.
--- { fits, per_page, tabs (how many dividers fit), tab = { x, y, w, h, gap },
--- sign, box, well, front, search, tags = { y, h }, pages = { { first, last } }
--- (indexes into `flow`), flow = { i… } (the rows that are cards or notes,
--- in order), slot(k) → the k-th card's place on its page }.
function View.layout(kinds, w, h, s)
    s = s or S
    local pad = s(22)
    local top, sign_h, gap = s(6), s(30), s(8)
    local tab_h, front_h, foot = s(32), s(104), s(12)
    local card_h = s(View.CARD_H)
    local wall = s(10)
    local L = { w = w, h = h, fits = true, card_h = card_h, pages = {}, flow = {} }
    L.sign = { x = pad, y = top, w = w - 2 * pad, h = sign_h }
    local box_x, box_w = pad, w - 2 * pad
    local tabs_y = top + sign_h + gap
    local box_y = tabs_y + tab_h
    local front_y = h - foot - front_h
    local well_h = front_y - box_y
    L.per_page = math.floor((well_h - s(10)) / card_h)
    if L.per_page < 2 or box_w < s(260) then
        L.fits = false
        return L
    end
    L.box = { x = box_x, y = box_y, w = box_w, h = front_y + front_h - box_y }
    L.well = { x = box_x + wall, y = box_y, w = box_w - 2 * wall, h = well_h }
    L.front = { x = box_x, y = front_y, w = box_w, h = front_h }
    local tgap = s(5)
    local tabs_w = box_w - 2 * s(14)
    L.tabs = clamp(math.floor((tabs_w + tgap) / (s(View.TAB_W) + tgap)), 2, View.MAX_TABS)
    L.tab = { x = box_x + s(14), y = tabs_y, w = math.floor((tabs_w - (L.tabs - 1) * tgap) / L.tabs), h = tab_h, gap = tgap }
    local sw = math.min(box_w - s(48), s(340))
    L.search = { x = box_x + math.floor((box_w - sw) / 2), y = front_y + s(12), w = sw, h = s(44) }
    L.tags = { y = front_y + s(64), h = s(30) }
    for i, k in ipairs(kinds or {}) do
        if k == "card" or k == "note" then L.flow[#L.flow + 1] = i end
    end
    local n = #L.flow
    for first = 1, math.max(n, 1), L.per_page do
        L.pages[#L.pages + 1] = { first = first, last = math.min(n, first + L.per_page - 1) }
    end
    -- the cards stand on the box's floor: the page's last one lowest
    function L.slot(k, count)
        local y = front_y - (count - k + 1) * card_h
        local shift = (k % 2 == 0) and s(8) or 0
        return { x = L.well.x + s(4) + shift, y = y, w = L.well.w - s(8) - s(8), h = card_h }
    end
    return L
end

--- The page the list's row `idx` is on (1 when it's on every page).
function View.pageOf(L, idx)
    for k, i in ipairs(L.flow or {}) do
        if i == idx then return math.floor((k - 1) / L.per_page) + 1 end
    end
    return 1
end

---------------------------------------------------------------- painting bits

local function ink(bb, colour, c)
    if colour and bb.paintRectRGB32 and Blitbuffer.ColorRGB32 then
        return Blitbuffer.ColorRGB32(c[2][1], c[2][2], c[2][3], 0xFF), true
    end
    return Blitbuffer.gray(c[1]), false
end

--- A filled (rounded) rectangle in one of the palette's colours.
local function fill(bb, colour, c, x, y, w, h, r)
    if w <= 0 or h <= 0 then return end
    local col, rgb = ink(bb, colour, c)
    if rgb then
        if r and r > 0 and bb.paintRoundedRectRGB32 then bb:paintRoundedRectRGB32(x, y, w, h, col, r)
        else bb:paintRectRGB32(x, y, w, h, col) end
    elseif r and r > 0 then bb:paintRoundedRect(x, y, w, h, col, r)
    else bb:paintRect(x, y, w, h, col) end
end
View.fillWith = fill

local BLACK = { 1, { 20, 20, 20 } }

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }
function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

local function ring(bb, pl, r, inset)
    if not pl.hot then return end
    pl.hot.dimen = Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
    if pl.hot.focused then
        local o = inset or 0
        Shop().draw.focusRing(bb, { x = r.x + o, y = r.y + o, w = r.w - 2 * o, h = r.h - 2 * o })
    end
end

function Page:paintSign(bb, x, y, pl)
    local D = Shop().draw
    local r = D.sign(bb, self.menu, { x = x + pl.x, y = y + pl.y + S(3), h = pl.h - S(6) }, pl.entry.text or "", nil, pl.letter)
    ring(bb, pl, r)
    if pl.entry.mandatory and pl.entry.mandatory ~= "" then
        local TextWidget = require("ui/widget/textwidget")
        local t = TextWidget:new{ text = pl.entry.mandatory, face = Font:getFace("cfont", 13), fgcolor = D.gray(0.85),
            max_width = pl.w - r.w - S(12) }
        local sz = t:getSize()
        t:paintTo(bb, x + pl.x + pl.w - sz.w, y + pl.y + math.floor((pl.h - sz.h) / 2))
        t:free()
    end
end

--- A divider's tab: its top corners round, standing on the box's edge.
function Page:paintTab(bb, x, y, pl)
    local D = Shop().draw
    local bw, r = math.max(2, S(2)), S(7)
    local drop = pl.chosen and 0 or S(6)
    local tx, ty, th = x + pl.x, y + pl.y + drop, pl.h - drop
    fill(bb, self.colour, pl.chosen and BLACK or View.PAL.tabs[(pl.n - 1) % #View.PAL.tabs + 1], tx, ty, pl.w, th + r, r)
    bb:paintBorder(tx, ty, pl.w, th + r, bw, Blitbuffer.COLOR_BLACK, r)
    local side = pl.letter and self.menu.is_enable_shortcut and S(16) or 0
    if side > 0 then D.badge(bb, self.menu, pl.letter, tx + S(4), ty + math.floor((th - side) / 2), side) end
    local room = pl.w - S(8) - (side > 0 and side + S(4) or 0)
    D.text(bb, pl.label, Font:getFace("cfont", 12), tx + pl.w - S(4) - math.floor(room / 2), ty + math.floor(th / 2),
        { center = true, middle = true, bold = true, color = pl.chosen and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK, max_width = room })
    ring(bb, pl, { x = tx, y = ty, w = pl.w, h = th }, S(5))
end

--- A filed card: its top edge, the name in handwriting, the time.
function Page:paintCard(bb, x, y, pl)
    local D = Shop().draw
    local bw, r = math.max(2, S(2)), S(6)
    local cx, cy = x + pl.x, y + pl.y
    fill(bb, self.colour, View.PAL.card, cx, cy, pl.w, pl.h + r, r)
    bb:paintBorder(cx, cy, pl.w, pl.h + r, bw, Blitbuffer.COLOR_BLACK, r)
    local mid = cy + math.floor(pl.h / 2)
    if pl.kind == "note" then
        D.text(bb, pl.entry.text or "", Font:getFace("cfont", 13), cx + math.floor(pl.w / 2), mid,
            { center = true, middle = true, color = D.gray(0.8), max_width = pl.w - S(24) })
        return
    end
    local left = cx + S(14)
    local side = pl.letter and self.menu.is_enable_shortcut and S(20) or 0
    if side > 0 then left = left + D.badge(bb, self.menu, pl.letter, left, mid - math.floor(side / 2), side) + S(8) end
    local right = cx + pl.w - S(14)
    local time = pl.entry.mandatory
    if time and time ~= "" then
        local TextWidget = require("ui/widget/textwidget")
        local t = TextWidget:new{ text = time, face = Font:getFace("cfont", 12), fgcolor = D.gray(0.85), max_width = math.floor(pl.w * 0.4) }
        local sz = t:getSize()
        t:paintTo(bb, right - sz.w, mid - math.floor(sz.h / 2))
        t:free()
        right = right - sz.w - S(10)
    end
    D.text(bb, pl.entry.text or "", D.hand(22), left, mid, { middle = true, max_width = right - left })
    -- the card's ruled line, under the name
    fill(bb, self.colour, View.PAL.rule, cx + bw, cy + pl.h - math.max(1, S(1)), pl.w - 2 * bw, math.max(1, S(1)))
    ring(bb, pl, { x = cx, y = cy, w = pl.w, h = pl.h }, S(5))
end

--- The brass label holder on the box's front: Search.
function Page:paintSearch(bb, x, y, pl)
    local D = Shop().draw
    local bw = math.max(2, S(2))
    local sx, sy = x + pl.x, y + pl.y
    fill(bb, self.colour, View.PAL.brass, sx, sy, pl.w, pl.h, S(4))
    bb:paintBorder(sx, sy, pl.w, pl.h, bw, Blitbuffer.COLOR_BLACK, S(4))
    local m = S(6)
    local ix, iy, iw, ih = sx + S(16), sy + m, pl.w - 2 * S(16), pl.h - 2 * m
    fill(bb, self.colour, View.PAL.card, ix, iy, iw, ih)
    bb:paintBorder(ix, iy, iw, ih, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    for _i, px in ipairs({ sx + S(8), sx + pl.w - S(8) }) do
        bb:paintCircle(px, sy + math.floor(pl.h / 2), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    end
    local side = pl.letter and self.menu.is_enable_shortcut and S(20) or 0
    local left = ix + S(8)
    if side > 0 then left = left + D.badge(bb, self.menu, pl.letter, left, iy + math.floor((ih - side) / 2), side) + S(6) end
    local words = pl.entry.mandatory
    local has = type(words) == "string" and words ~= ""
    D.text(bb, has and ("“" .. words .. "”") or _("Search the box"), has and D.hand(20) or Font:getFace("cfont", 14),
        left, iy + math.floor(ih / 2), { middle = true, max_width = ix + iw - S(8) - left, color = has and Blitbuffer.COLOR_BLACK or D.gray(0.8) })
    ring(bb, pl, { x = sx, y = sy, w = pl.w, h = pl.h })
end

--- A paper tag on the box's front (the order; More cards).
function Page:paintTag(bb, x, y, pl)
    local D = Shop().draw
    local bw = math.max(2, S(2))
    local tx, ty = x + pl.x, y + pl.y
    local r = math.floor(pl.h / 2)
    fill(bb, self.colour, View.PAL.card, tx, ty, pl.w, pl.h, r)
    bb:paintBorder(tx, ty, pl.w, pl.h, bw, Blitbuffer.COLOR_BLACK, r)
    local side = pl.letter and self.menu.is_enable_shortcut and S(18) or 0
    local left = tx + S(12)
    if side > 0 then left = left + D.badge(bb, self.menu, pl.letter, left, ty + math.floor((pl.h - side) / 2), side) + S(6) end
    D.text(bb, pl.label, Font:getFace("cfont", 13), left, ty + math.floor(pl.h / 2), { middle = true, bold = true, max_width = tx + pl.w - S(12) - left })
    ring(bb, pl, { x = tx, y = ty, w = pl.w, h = pl.h })
end

function Page:paintTo(bb, x, y)
    local L = self.L
    local bw = math.max(2, S(2))
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    fill(bb, self.colour, View.PAL.counter, x, y, self.w, self.h)
    local by = {}
    for _i, pl in ipairs(self.places) do
        by[pl.kind] = by[pl.kind] or {}
        table.insert(by[pl.kind], pl)
    end
    local function each(kind, fn) for _i, pl in ipairs(by[kind] or {}) do fn(self, bb, x, y, pl) end end
    each("refresh", self.paintSign)
    each("tab", self.paintTab)
    -- the box: its side walls, the well the cards stand in
    local b, w, f = L.box, L.well, L.front
    fill(bb, self.colour, View.PAL.wood, x + b.x, y + b.y, b.w, b.h)
    fill(bb, self.colour, View.PAL.well, x + w.x, y + w.y, w.w, w.h)
    each("card", self.paintCard)
    each("note", self.paintCard)
    -- its front, over the foot of the last card: wood, with the grain
    fill(bb, self.colour, View.PAL.wood, x + f.x, y + f.y, f.w, f.h)
    for gy = y + f.y + S(13), y + f.y + f.h - S(4), S(13) do
        fill(bb, self.colour, View.PAL.grain, x + f.x + bw, gy, f.w - 2 * bw, math.max(1, S(1)))
    end
    bb:paintBorder(x + b.x, y + b.y, b.w, b.h, bw, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + f.x, y + f.y, f.w, bw, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + w.x - bw, y + w.y, bw, w.h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + w.x + w.w, y + w.y, bw, w.h, Blitbuffer.COLOR_BLACK)
    each("search", self.paintSearch)
    each("order", self.paintTag)
    each("more", self.paintTag)
end

View.Page = Page

---------------------------------------------------------------- building a page

--- A tag's width for its label (measured; a guess where it can't be).
local function tagWidth(label, has_letter)
    local w = S(36) + #label * S(8)
    pcall(function()
        local TextWidget = require("ui/widget/textwidget")
        local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 13), bold = true }
        w = S(36) + t:getSize().w
        t:free()
    end)
    return w + (has_letter and S(24) or 0)
end

--- What's on page `n`: each place with its row of the list (entry), or,
--- for a divider's tab, an entry of its own; its letter (the ones that do
--- something, in order). `tab`: the Recipes tab (its cats, filter,
--- setFilter, askCategory). `width_of(label)`: a tag's width (tests).
function View.fill(L, n, items, kinds, tab, shortcuts, width_of)
    width_of = width_of or tagWidth
    local out = {}
    local k = 0
    local function letter()
        k = k + 1
        return shortcuts and shortcuts[k] or nil
    end
    local function rowOf(kind)
        for i, kk in ipairs(kinds) do if kk == kind then return items[i], i end end
    end
    local function acts(e) return type(e) == "table" and type(e.callback) == "function" and e.select_enabled ~= false end
    -- Refresh
    local e, i = rowOf("refresh")
    if e then
        out[#out + 1] = { kind = "refresh", x = L.sign.x, y = L.sign.y, w = L.sign.w, h = L.sign.h, entry = e, i = i, acts = acts(e), letter = acts(e) and letter() or nil }
    end
    -- the dividers
    local chosen = tab and tab.filter and tab.filter.category or nil
    local divs = View.dividers(tab and tab.cats, chosen, L.tabs)
    for d, div in ipairs(divs) do
        local entry
        if div.all then
            entry = { text = _("All"), gz_divider = "all", callback = function() tab:setFilter({ category = false }) end }
        elseif div.more then
            entry = { text = _("More…"), gz_divider = "more", callback = function() tab:askCategory() end }
        else
            entry = { text = div.name, gz_divider = div.id, callback = function() tab:setFilter({ category = { id = div.id, name = div.name } }) end }
        end
        out[#out + 1] = { kind = "tab", n = d, chosen = divs.chosen == d, label = entry.text, entry = entry, acts = true, letter = letter(),
            x = L.tab.x + (d - 1) * (L.tab.w + L.tab.gap), y = L.tab.y, w = L.tab.w, h = L.tab.h }
    end
    -- this page's cards
    local page = L.pages[n] or { first = 1, last = 0 }
    local count = page.last - page.first + 1
    for kk = page.first, page.last do
        local idx = L.flow[kk]
        local row = items[idx]
        local slot = L.slot(kk - page.first + 1, count)
        local a = kinds[idx] == "card" and acts(row)
        out[#out + 1] = { kind = kinds[idx], x = slot.x, y = slot.y, w = slot.w, h = slot.h, entry = row, i = idx, acts = a, letter = a and letter() or nil }
    end
    -- the front: Search, then the order and More cards side by side
    e, i = rowOf("search")
    if e then
        out[#out + 1] = { kind = "search", x = L.search.x, y = L.search.y, w = L.search.w, h = L.search.h, entry = e, i = i, acts = acts(e), letter = acts(e) and letter() or nil }
    end
    local tags = {}
    local oe, oi = rowOf("order")
    if oe then tags[#tags + 1] = { kind = "order", entry = oe, i = oi, label = tostring(oe.mandatory or oe.text or "") } end
    local me, mi = rowOf("more")
    if me then
        local label = _("More cards")
        if me.mandatory and me.mandatory ~= "" then label = label .. " · " .. me.mandatory end
        tags[#tags + 1] = { kind = "more", entry = me, i = mi, label = label }
    end
    local tgap, total = S(12), 0
    for _t, t in ipairs(tags) do
        t.acts = acts(t.entry)
        t.letter = t.acts and letter() or nil
        t.w = math.min(width_of(t.label, t.letter ~= nil and shortcuts ~= nil), math.floor((L.front.w - S(24) - tgap) / 2))
        total = total + t.w
    end
    total = total + tgap * math.max(0, #tags - 1)
    local tx = L.front.x + math.floor((L.front.w - total) / 2)
    for _t, t in ipairs(tags) do
        t.x, t.y, t.h = tx, L.tags.y, L.tags.h
        tx = tx + t.w + tgap
        out[#out + 1] = t
    end
    return out
end

--- Draw the page of `m` (the Recipes tab's list) as the box. False: it
--- doesn't fit (the list instead).
function View.build(m, tab, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    local wanted = m.page or 1
    m:_recalculateDimen(no_recalculate_dimen)
    local W, H = m.item_dimen.w, m.available_height
    local kinds = View.kinds(m.item_table)
    local L = View.layout(kinds, W, H)
    if not L.fits then return false end
    -- the pages are this view's (the cards the box holds), not the Menu's rows
    m.page_num = #L.pages
    m.page = clamp(wanted, 1, m.page_num)
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    local Hot = Shop().Hot
    local page = Page:new{ w = W, h = H, L = L, menu = m, colour = require("gzreader_colour").enabled() }
    page.places = View.fill(L, m.page, m.item_table, kinds, tab, m.is_enable_shortcut and m.item_shortcuts or nil)
    local rows, row_y = {}, nil
    page.by_letter = {}
    for _i, pl in ipairs(page.places) do
        if pl.acts then
            if pl.i then pl.entry.idx = pl.i end
            pl.hot = Hot:new{ menu = m, entry = pl.entry, shop = page }
            page[#page + 1] = pl.hot
            if pl.y ~= row_y then
                rows[#rows + 1] = {}
                row_y = pl.y
            end
            table.insert(rows[#rows], pl.hot)
            if pl.letter then page.by_letter[pl.letter] = pl.entry end
        end
    end
    for _i, r in ipairs(rows) do m.layout[#m.layout + 1] = r end
    table.insert(m.item_group, page)
    m._gz_box = page
    -- the focus: on what was chosen (back from it), else the first card
    local fx, fy = 1, 1
    local back = m._gz_box_last
    for yy, r in ipairs(m.layout) do
        for xx, h in ipairs(r) do
            local e = h.entry
            if back then
                if e == back or (e.gz_recipe and e.gz_recipe == back.gz_recipe) or (e.gz_divider and e.gz_divider == back.gz_divider)
                        or (e.gz_recipes and e.gz_recipes == back.gz_recipes) or (e.gz_more and back.gz_more) then
                    fx, fy = xx, yy
                end
            elseif e.gz_recipe and fy == 1 then
                fx, fy = xx, yy
            end
        end
    end
    m:updatePageInfo(select_number or 1)
    if (fx > 1 or fy > 1) and Device:hasDPad() and m.layout[fy] then
        local FocusManager = require("ui/widget/focusmanager")
        m:moveFocusTo(fx, fy, FocusManager.FOCUS_ONLY_ON_NT)
    end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    return true
end

--- Take over the Recipes tab's list in the Bookshelf view.
function View.apply(tab)
    local m = tab and tab.menu
    if not m or m._gz_box_applied or type(m.updateItems) ~= "function" then return end
    m._gz_box_applied = true
    local orig_update = m.updateItems
    m.updateItems = function(menu, select_number, no_recalculate_dimen)
        if not menu._gz_box_failed and View.applies(menu, tab) then
            local ok, res = pcall(View.build, menu, tab, select_number, no_recalculate_dimen)
            if ok and res ~= false then return end
            if not ok then
                require("gzreader_log").warn("recipe box:", tostring(res))
                menu._gz_box_failed = true
            end
        end
        menu._gz_box = nil
        return orig_update(menu, select_number, no_recalculate_dimen)
    end
    -- a letter: what has it in the box (the Menu counts rows a page)
    local orig_key = m.onSelectByShortCut
    m.onSelectByShortCut = function(menu, arg, keyevent)
        local page = menu._gz_box
        if not page then return orig_key and orig_key(menu, arg, keyevent) end
        local entry = keyevent and page.by_letter[keyevent.key]
        if entry then menu:onMenuSelect(entry) end
        return true
    end
    -- what's chosen: the focus stays on it when the box is drawn again
    local orig_select = m.onMenuSelect
    m.onMenuSelect = function(menu, item, ...)
        if menu._gz_box then menu._gz_box_last = item end
        return orig_select(menu, item, ...)
    end
    if View.applies(m, tab) then pcall(m.updateItems, m) end
end

return View
