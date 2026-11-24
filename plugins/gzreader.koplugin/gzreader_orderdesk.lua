--[[--
The Catalog's Requests page as the bookshop's order desk (the Bookshelf view;
the other views keep the list). gzreader_bo_requests.lua has the requests
themselves (BookOrbit's, with its API key).

- a plate across the top: Order desk;
- On order: the requests still on their way, each an order slip clipped to
  a rail (book or audiobook, title, author, how far it is in four steps:
  asked, approved, being found, in the library; its status stamped below);
- Arrived: what came in, standing on a shelf (a book's cover, an audiobook
  as a cassette);
- the counter: the order pad (Request a book…) and a drawer for what
  didn't arrive (declined, cancelled, failed).

More than fit: a tag at the end ("+N more") opens that group's list; so does
its sign. A tap (or Press, or its letter) on a slip opens what its row opened
in the list. On a colour screen the stamps' frames are in colour (amber
waiting, blue on its way, green arrived).
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

local Desk = {
    STEPS = 4,    -- asked, approved, being found, in the library
    RATIO = 0.68, -- an arrived book's width to its height
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------- what's on it

local STAGE = { pending = 1, approved = 2, searching = 3, grabbed = 3, downloading = 3, importing = 3, needs_review = 3, available = 4 }
local CLOSED = { rejected = true, cancelled = true, failed = true }

--- How far a request is, 1 to 4 (nil: it didn't arrive).
function Desk.stage(status) return STAGE[status] end

--- The requests by where they are on the desk (the list's order kept):
--- on order, arrived, and the ones that didn't arrive. Pure.
function Desk.groups(list)
    local g = { order = {}, arrived = {}, closed = {} }
    for _i, r in ipairs(type(list) == "table" and list or {}) do
        if type(r) == "table" then
            if r.status == "available" then g.arrived[#g.arrived + 1] = r
            elseif CLOSED[r.status] then g.closed[#g.closed + 1] = r
            else g.order[#g.order + 1] = r end
        end
    end
    return g
end

--- How many of `n` things are shown in `cols` places: all when they fit,
--- else one place less (the last is the "+N more" tag). Pure.
function Desk.shown(n, cols)
    if n <= cols then return n end
    return cols - 1
end

---------------------------------------------------------------- where things go

--- Where everything goes in a w x h page (px; s = the screen's scale
--- function). Pure: tested in run_tests.lua.
function Desk.layout(w, h, s)
    s = s or S
    local L = { w = w, h = h }
    local pad = s(12)
    L.plate = { y = s(6), h = s(30) }
    local counter_h = clamp(math.floor(h * 0.14), s(74), s(116))
    L.counter = { x = s(6), y = h - counter_h - s(2), w = w - 2 * s(6), h = counter_h, top = s(12) }
    local inner_y, inner_h = L.counter.y + L.counter.top + s(8), counter_h - L.counter.top - s(16)
    local drawer_w = clamp(math.floor(L.counter.w * 0.34), s(120), s(240))
    L.pad = { x = L.counter.x + s(14), y = inner_y, w = L.counter.w - drawer_w - 3 * s(14), h = inner_h }
    L.drawer = { x = L.pad.x + L.pad.w + s(14), y = inner_y, w = drawer_w, h = inner_h }
    -- the rail and the shelf share what's left: the rail a little more
    local top = L.plate.y + L.plate.h + s(10)
    local room = L.counter.y - s(8) - top
    local sign_h, ledge_h, gap = s(24), s(10), s(8)
    local fixed = sign_h + s(10) + ledge_h + gap
    local rail_h = math.floor(room * 0.56)
    local cgap = s(12)
    local cols = clamp(math.floor((w - 2 * pad + cgap) / (s(150) + cgap)), 2, 5)
    local col_w = math.floor((w - 2 * pad - (cols - 1) * cgap) / cols)
    L.cols = {}
    for c = 1, cols do L.cols[c] = { x = pad + (c - 1) * (col_w + cgap), w = col_w } end
    L.rows = {}
    local y = top
    for i, row_h in ipairs({ rail_h, room - rail_h }) do
        local area_top = y + sign_h + s(10)
        local area_h = row_h - fixed
        local feet = area_top + area_h
        L.rows[i] = { sign = { x = pad + s(6), y = y, h = sign_h }, top = area_top, h = area_h, feet = feet,
            ledge = { x = s(8), y = feet, w = w - 2 * s(8), h = ledge_h } }
        y = feet + ledge_h + gap
    end
    -- a slip hangs from the rail (its clip above it); a book stands on the shelf
    local R1, R2 = L.rows[1], L.rows[2]
    L.rail = { x = s(8), y = R1.top - s(2), w = w - 2 * s(8), h = math.max(2, s(3)) }
    L.slip = { w = math.min(col_w, s(190)), h = math.min(R1.h - s(8), s(200)), y = R1.top + s(6) }
    local book_h = math.min(R2.h - s(4), s(170))
    L.book = { h = book_h, w = math.min(col_w - s(8), math.floor(book_h * Desk.RATIO + 0.5)) }
    L.fits = L.slip.h >= s(96) and L.book.h >= s(56) and L.book.w >= s(36)
    return L
end

---------------------------------------------------------------- painting

local function draw() return require("gzreader_bookshop").draw end

local INK = { wait = { 0x8a, 0x4b, 0x00 }, move = { 0x1d, 0x5f, 0xa8 }, ok = { 0x1f, 0x6f, 0x38 } }

--- A stamp's colour on a colour screen (a ColorRGB32), else nil.
function Desk.ink(status)
    local ok, Colour = pcall(require, "gzreader_colour")
    if not ok or not Colour.enabled() or not Blitbuffer.ColorRGB32 then return nil end
    local c = status == "available" and INK.ok or ((status == "pending" or status == "needs_review") and INK.wait or INK.move)
    return Blitbuffer.ColorRGB32(c[1], c[2], c[3], 0xFF)
end

--- A frame `t` thick, in `rgb` when there's one (a colour screen), else black.
local function frame(bb, x, y, w, h, t, rgb)
    if not (rgb and bb.paintRectRGB32) then return bb:paintBorder(x, y, w, h, t, Blitbuffer.COLOR_BLACK) end
    bb:paintRectRGB32(x, y, w, t, rgb)
    bb:paintRectRGB32(x, y + h - t, w, t, rgb)
    bb:paintRectRGB32(x, y, t, h, rgb)
    bb:paintRectRGB32(x + w - t, y, t, h, rgb)
end

--- The plate across the top.
local function paintPlate(bb, x, y, w, r, name)
    local d = draw()
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = name, face = d.hand(22), bold = true, max_width = math.floor(w * 0.7) }
    local sz = t:getSize()
    local pw, ph = sz.w + S(36), r.h
    local px, py = x + math.floor((w - pw) / 2), y + r.y
    -- the two chains it hangs from
    for _i, cx in ipairs({ px + S(12), px + pw - S(12) }) do bb:paintRect(cx, y, math.max(1, S(2)), r.y, d.gray(0.6)) end
    bb:paintRect(px + S(3), py + S(3), pw, ph, d.gray(0.45))
    bb:paintRect(px, py, pw, ph, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(px, py, pw, ph, math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
    t:paintTo(bb, px + S(18), py + math.floor((ph - sz.h) / 2))
    t:free()
end

--- How far it is: four dots on a line, the first `stage` filled.
local function paintTrack(bb, x, y, w, stage)
    local r = math.max(3, S(5))
    local step = math.floor((math.min(w, S(120)) - 2 * r) / (Desk.STEPS - 1))
    local cy = y + r
    bb:paintRect(x + r, cy - math.max(1, S(1)), step * (Desk.STEPS - 1), math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
    for i = 1, Desk.STEPS do
        local cx = x + r + (i - 1) * step
        bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK)
        if i > (stage or 0) then bb:paintCircle(cx, cy, r - math.max(1, S(2)), Blitbuffer.COLOR_WHITE) end
    end
    return 2 * r
end

--- An order slip clipped to the rail: r = { x, y, w, h }.
local function paintSlip(bb, menu, r, req, letter)
    local d = draw()
    local Requests = require("gzreader_bo_requests")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    bb:paintRect(r.x + S(3), r.y + S(3), r.w, r.h, d.gray(0.4))
    bb:paintRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    d.clip(bb, r.x + math.floor(r.w / 2), r.y + S(2), S(26))
    local p = S(8)
    local iw = r.w - 2 * p
    -- from the bottom up: the stamp, the track
    local status = Requests.statusText(req.status)
    local stamp_h = S(18)
    local sy = r.y + r.h - p - stamp_h
    local ssz = d.text(bb, status, Font:getFace("cfont", 9), r.x + p + S(6), sy + math.floor(stamp_h / 2), { middle = true, bold = true, max_width = iw - S(12) })
    frame(bb, r.x + p, sy, math.min(iw, ssz.w + S(12)), stamp_h, math.max(2, S(2)), Desk.ink(req.status))
    local ty = sy - S(8) - 2 * math.max(3, S(5))
    paintTrack(bb, r.x + p, ty, iw, Desk.stage(req.status))
    -- from the top down: what it is, its title, who wrote it
    local y = r.y + S(12)
    local side = d.badge(bb, menu, letter, r.x + r.w - p - S(18), y - S(2), S(18))
    local kind = req.kind == "audiobook" and _("AUDIOBOOK") or _("BOOK")
    local ksz = d.text(bb, kind, Font:getFace("cfont", 8), r.x + p, y, { bold = true, color = d.gray(0.75), max_width = iw - (side > 0 and side + S(4) or 0) })
    y = y + ksz.h + S(2)
    local who = type(req.authors) == "table" and table.concat(req.authors, ", ") or ""
    local who_h = who ~= "" and S(15) or 0
    local room = ty - S(4) - who_h - y
    if room > S(14) then
        local tb = TextBoxWidget:new{ text = req.title or "?", face = d.hand(19), width = iw, height = room,
            height_adjust = true, height_overflow_show_ellipsis = true }
        tb:paintTo(bb, r.x + p, y)
        y = y + math.min(room, tb:getSize().h)
        tb:free()
    end
    if who ~= "" and y + who_h <= ty - S(2) then
        d.text(bb, who, Font:getFace("cfont", 10), r.x + p, y + S(1), { color = d.gray(0.75), max_width = iw })
    end
end

--- A tag hanging from the rail or standing on the shelf ("+3 more").
local function paintTag(bb, col, top, label)
    local d = draw()
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = d.hand(18), max_width = col.w - S(24) }
    local sz = t:getSize()
    local tw, th = sz.w + S(22), sz.h + S(10)
    local tx = col.x + math.floor((col.w - tw) / 2)
    local ty = top + S(22)
    bb:paintRect(tx + S(10), top, 1, ty - top + math.floor(th / 2), Blitbuffer.COLOR_BLACK) -- its string
    bb:paintRect(tx + S(2), ty + S(2), tw, th, d.gray(0.35))
    bb:paintRect(tx, ty, tw, th, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(tx, ty, tw, th, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    bb:paintCircle(tx + S(10), ty + math.floor(th / 2), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    t:paintTo(bb, tx + S(18), ty + math.floor((th - sz.h) / 2))
    t:free()
    return { x = tx, y = ty, w = tw, h = th }
end

--- What arrived, standing on the shelf at `feet` in the column: a book's
--- cover, an audiobook as a cassette with its title on the label.
local function paintArrived(bb, col, feet, L, req)
    local d = draw()
    if req.kind == "audiobook" then
        local cw = math.min(col.w - S(8), math.floor(L.book.h * 1.25))
        local ch = math.floor(cw * 0.62)
        local x, y = col.x + math.floor((col.w - cw) / 2), feet - ch
        d.cassette(bb, x, y, cw, ch)
        -- its title on a strip across the top of the label, clear of the reels
        local sh = S(12)
        bb:paintRect(x + S(5), y + S(4), cw - S(10), sh, Blitbuffer.COLOR_WHITE)
        bb:paintRect(x + S(5), y + S(4) + sh, cw - S(10), 1, d.gray(0.6))
        d.text(bb, req.title or "?", Font:getFace("cfont", 8), x + math.floor(cw / 2), y + S(4) + math.floor(sh / 2),
            { center = true, middle = true, bold = true, max_width = cw - S(16) })
        return { x = x, y = y, w = cw, h = ch }
    end
    local iw, ih = L.book.w, L.book.h
    local img = req.book_id and require("gzreader_covers").image(req.book_id, nil, iw, ih) or nil
    if img then iw, ih = img:getWidth(), img:getHeight() end
    local x, y = col.x + math.floor((col.w - iw) / 2), feet - ih
    bb:paintRect(x + S(4), y + S(2), iw, ih - S(2), d.gray(0.4))
    if img then
        bb:blitFrom(img, x, y, 0, 0, iw, ih)
    else
        -- no cover yet: a plain bound book with its title and author
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local paper = d.gray(0.14)
        bb:paintRect(x, y, iw, ih, paper)
        bb:paintRect(x + S(5), y, math.max(1, S(1)), ih, d.gray(0.5)) -- its hinge
        local tw = iw - S(18)
        local title = TextBoxWidget:new{ text = req.title or "?", face = Font:getFace("cfont", 11), bold = true, width = tw, alignment = "center",
            bgcolor = paper, height = math.floor(ih * 0.55), height_adjust = true, height_overflow_show_ellipsis = true }
        title:paintTo(bb, x + S(12), y + S(12))
        title:free()
        local who = type(req.authors) == "table" and table.concat(req.authors, ", ") or ""
        if who ~= "" then
            d.text(bb, who, Font:getFace("cfont", 9), x + S(6) + math.floor((iw - S(6)) / 2), y + ih - S(14), { center = true, middle = true, max_width = tw })
        end
    end
    bb:paintBorder(x, y, iw, ih, 1, Blitbuffer.COLOR_BLACK)
    return { x = x, y = y, w = iw, h = ih }
end

--- The order pad on the counter: a plus, Request a book…, what it asks.
local function paintPad(bb, menu, r, letter, focused)
    local d = draw()
    bb:paintRect(r.x + S(3), r.y + S(3), r.w, r.h, d.gray(0.7))
    bb:paintRect(r.x, r.y, r.w, r.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
    local cy = r.y + math.floor(r.h / 2)
    local x = r.x + S(12)
    local side = d.badge(bb, menu, letter, x, cy - S(10), S(20))
    if side > 0 then x = x + side + S(8) end
    local arm, th = S(9), math.max(3, S(4))
    bb:paintRect(x, cy - math.floor(th / 2), 2 * arm, th, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + arm - math.floor(th / 2), cy - arm, th, 2 * arm, Blitbuffer.COLOR_BLACK)
    x = x + 2 * arm + S(10)
    local width = r.x + r.w - S(8) - x
    local two = r.h >= S(52)
    d.text(bb, _("Request a book…"), d.hand(22), x, two and cy - S(9) or cy, { middle = true, max_width = width })
    if two then
        d.text(bb, _("Title, author, book or audiobook"), Font:getFace("cfont", 10), x, cy + S(13), { middle = true, color = d.gray(0.75), max_width = width })
    end
    if focused then d.focusRing(bb, r) end
end

--- The counter's drawer: a card in a holder (name, count) and a knob.
local function paintDrawer(bb, r, name, sub, focused)
    local d = draw()
    bb:paintRect(r.x, r.y, r.w, r.h, d.gray(0.3))
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(1, S(2)), d.gray(0.7))
    local cw, ch = r.w - S(16), math.floor(r.h * 0.6)
    local cx, cy = r.x + S(8), r.y + S(6)
    bb:paintRect(cx - S(3), cy - S(3), cw + S(6), ch + S(6), d.gray(0.75))
    bb:paintRect(cx, cy, cw, ch, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(cx, cy, cw, ch, 1, Blitbuffer.COLOR_BLACK)
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = sub, face = Font:getFace("cfont", 11), fgcolor = d.gray(0.75) }
    local ssz = t:getSize()
    t:paintTo(bb, cx + cw - S(6) - ssz.w, cy + math.floor((ch - ssz.h) / 2))
    t:free()
    d.text(bb, name, d.hand(18), cx + S(8), cy + math.floor(ch / 2), { middle = true, max_width = cw - S(22) - ssz.w })
    bb:paintCircle(r.x + math.floor(r.w / 2), cy + ch + math.floor((r.y + r.h - cy - ch) / 2), math.max(3, S(5)), d.gray(0.85))
    if focused then d.focusRing(bb, r) end
end

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }

function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

function Page:paintRow(bb, ox, oy, i)
    local d = draw()
    local L, menu = self.L, self.menu
    local R, spec = L.rows[i], self.rows[i]
    local sr = d.sign(bb, menu, { x = ox + R.sign.x, y = oy + R.sign.y, h = R.sign.h }, spec.label, spec.count, nil)
    spec.sign_hot.dimen = Geom:new(sr)
    if i == 1 then
        local rail = L.rail
        bb:paintRect(ox + rail.x, oy + rail.y, rail.w, rail.h, d.gray(0.8))
        bb:paintRect(ox + rail.x, oy + rail.y + rail.h, rail.w, 1, d.gray(0.35))
    end
    if #spec.items == 0 and spec.message ~= "" then
        d.text(bb, spec.message, d.hand(20), ox + math.floor(L.w / 2), oy + R.top + math.floor(R.h / 2),
            { center = true, middle = true, color = d.gray(0.7), max_width = L.w - S(40) })
    end
    local rings = {}
    if spec.sign_hot.focused then rings[#rings + 1] = spec.sign_hot.dimen end
    for c, item in ipairs(spec.items) do
        local col = { x = ox + L.cols[c].x, w = L.cols[c].w }
        local r
        if item.more then
            r = paintTag(bb, col, i == 1 and (oy + L.rail.y + L.rail.h) or (oy + R.top), item.more)
        elseif i == 1 then
            r = { x = col.x + math.floor((col.w - L.slip.w) / 2), y = oy + L.slip.y, w = L.slip.w, h = L.slip.h }
            paintSlip(bb, menu, r, item.req, item.letter)
        else
            r = paintArrived(bb, col, oy + R.feet, L, item.req)
        end
        item.hot.dimen = Geom:new(r)
        if item.hot.focused then rings[#rings + 1] = item.hot.dimen end
    end
    d.ledge(bb, { x = ox + R.ledge.x, y = oy + R.ledge.y, w = R.ledge.w, h = R.ledge.h })
    for _k, r in ipairs(rings) do d.focusRing(bb, r) end
end

function Page:paintTo(bb, x, y)
    local d = draw()
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local L, menu = self.L, self.menu
    d.wall(bb, x, y, self.w, self.h)
    paintPlate(bb, x, y, self.w, L.plate, _("Order desk"))
    for i = 1, #L.rows do self:paintRow(bb, x, y, i) end
    local C = L.counter
    bb:paintRect(x + C.x + S(4), y + C.y + S(4), C.w, C.h, d.gray(0.25))
    bb:paintRect(x + C.x, y + C.y, C.w, C.h, d.gray(0.55))
    d.ledge(bb, { x = x + C.x - S(4), y = y + C.y, w = C.w + S(8), h = C.top })
    local pr = { x = x + L.pad.x, y = y + L.pad.y, w = L.pad.w, h = L.pad.h }
    paintPad(bb, menu, pr, self.pad_letter, self.pad_hot.focused)
    self.pad_hot.dimen = Geom:new(pr)
    local dr = { x = x + L.drawer.x, y = y + L.drawer.y, w = L.drawer.w, h = L.drawer.h }
    paintDrawer(bb, dr, _("Didn't arrive"), self.closed_count, self.drawer_hot.focused)
    self.drawer_hot.dimen = Geom:new(dr)
end

---------------------------------------------------------------- building it

--- Draw the order desk in place of the Requests page's list (m: the
--- browser's Menu, W x H the room the bookshop has). False when it doesn't fit.
function Desk.build(m, browser, W, H, select_number, old_dimen)
    local Shop = require("gzreader_bookshop")
    local L = Desk.layout(W, H)
    if not L.fits then return false end
    local st = type(browser._requests) == "table" and browser._requests or {}
    local g = Desk.groups(st.list)
    local page = Page:new{ w = W, h = H, L = L, menu = m, browser = browser }
    local function hot(entry)
        local h = Shop.Hot:new{ menu = m, entry = entry, shop = page }
        page[#page + 1] = h
        return h
    end
    -- the list's own rows, by request: a slip opens what its row opened
    local row_of, new_entry, new_idx = {}, nil, nil
    for idx, e in ipairs(m.item_table) do
        if type(e) == "table" then
            if e.gz_request ~= nil then row_of[tostring(e.gz_request)] = { entry = e, idx = idx } end
            if e.gz_action == "request" then new_entry, new_idx = e, idx end
        end
    end
    local function listOf(title, reqs)
        return { text = title, keep_menu_open = true, callback = function()
            local items = {}
            for _i, r in ipairs(reqs) do
                local row = row_of[tostring(r.id)]
                if row then items[#items + 1] = row.entry end
            end
            browser:push(title, require("gzreader_rows").mark(items))
        end }
    end
    local waiting = st.list == nil and (st.err and browser.plugin:describeError(st.err) or _("Fetching your requests…")) or nil
    page.rows = {}
    m.layout = {}
    for i, def in ipairs({
        { label = _("On order"), reqs = g.order, empty = _("Nothing on order. Ask for a book at the desk.") },
        { label = _("Arrived"), reqs = g.arrived, empty = _("What comes in stands here.") },
    }) do
        local all = listOf(def.label, def.reqs)
        local spec = { label = def.label, count = #def.reqs > 0 and tostring(#def.reqs) or nil, items = {},
            message = waiting and (i == 1 and waiting or "") or def.empty,
            sign_hot = hot(#def.reqs > 0 and all or nil) }
        local n = Desk.shown(#def.reqs, #L.cols)
        local row = {}
        for k = 1, n do
            local r = def.reqs[k]
            local own = row_of[tostring(r.id)]
            local item = { req = r, hot = hot(own and own.entry), letter = own and Shop.letterOf(m, own.idx) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
        end
        if #def.reqs > n then
            local item = { more = T(_("+%1 more"), #def.reqs - n), hot = hot(all) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
        end
        if #row > 0 then m.layout[#m.layout + 1] = row end
        page.rows[i] = spec
    end
    page.pad_hot = hot(new_entry)
    page.pad_letter = Shop.letterOf(m, new_idx)
    page.drawer_hot = hot(#g.closed > 0 and listOf(_("Didn't arrive"), g.closed) or nil)
    page.closed_count = #g.closed > 0 and tostring(#g.closed) or _("none")
    m.layout[#m.layout + 1] = #g.closed > 0 and { page.pad_hot, page.drawer_hot } or { page.pad_hot }
    table.insert(m.item_group, page)
    m._gz_shop = page
    -- start on the first slip (the pad when there's none); back from a list: on what opened it
    local fx, fy = 1, 1
    local back = m._gz_shop_last or (select_number and m.item_table[select_number])
    if back then
        for yy, r in ipairs(m.layout) do
            for xx, h in ipairs(r) do
                if h.entry == back then fx, fy = xx, yy end
            end
        end
    end
    m:updatePageInfo(fy)
    if fx > 1 and Device:hasDPad() then m:moveFocusTo(fx, fy) end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    -- the arrived books' covers
    local wanted = {}
    for _i, item in ipairs(page.rows[2].items) do
        if item.req and item.req.kind ~= "audiobook" and item.req.book_id then wanted[#wanted + 1] = { id = item.req.book_id } end
    end
    if #wanted > 0 then
        local Covers = require("gzreader_covers")
        Covers.beginPage()
        local items = m.item_table
        Covers.fetch(browser.plugin, wanted, function(got)
            if got > 0 and m.item_table == items and not m._gz_closed and Shop.applies(m) then pcall(m.updateItems, m) end
        end)
    end
end

return Desk
