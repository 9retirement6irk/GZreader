--[[--
The Catalog's Magazines page as a magazine stand (the Bookshelf view; the
other views keep the list). gzreader_magazines.lua says which library holds
the magazines.

- a striped awning across the top, the magazine library's name on its plate;
- the search slip (as on the Books page);
- wire racks with the covers face out, a rail across their feet: Latest
  issues, then the magazines with the newest issues, each rack its own
  magazine; a price tag at the end ("+N more") opens the whole list;
- the counter below, with two drawers: Magazines A–Z and All issues.

A tap (or Press, or its letter) opens what it opened in the list: the page
draws the browser's own root items (gzreader_browser.lua, magazineItems: each
has a gz_id; Q search, W Latest issues, E Magazines A–Z, R All issues). Covers
come from gzreader_covers.lua. The issues (the newest 200) are kept like the
other lists (gzreader_listcache.lua) and fetched again each time the page opens.
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

local Stand = {
    COLS = 5,      -- a rack: four covers and the price tag
    SHOWN = 4,     -- covers on a rack
    RATIO = 0.76,  -- a magazine's width to its height (US letter is 0.77)
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------- where things go

--- Where everything goes in a w x h page (px; s = the screen's scale
--- function). Pure: tested in run_tests.lua.
function Stand.layout(w, h, s)
    s = s or S
    local L = { w = w, h = h }
    local pad = s(12)
    L.awning = { x = 0, y = 0, w = w, h = clamp(math.floor(h * 0.055), s(32), s(54)), scallop = s(9) }
    L.slip = { x = pad, y = L.awning.y + L.awning.h + L.awning.scallop + s(12), w = w - 2 * pad, h = s(30) }
    local counter_h = clamp(math.floor(h * 0.13), s(70), s(112))
    L.counter = { x = s(6), y = h - counter_h - s(2), w = w - 2 * s(6), h = counter_h, top = s(12) }
    local dw = math.floor((L.counter.w - 3 * s(14)) / 2)
    L.drawers = {}
    for i = 1, 2 do
        L.drawers[i] = { x = L.counter.x + s(14) + (i - 1) * (dw + s(14)), y = L.counter.y + L.counter.top + s(8),
            w = dw, h = counter_h - L.counter.top - s(16) }
    end
    -- the racks share what's left: three when there's room, else two
    local top = L.slip.y + L.slip.h + s(10)
    local room = L.counter.y - s(6) - top
    local sign_h, lip_h, gap = s(24), s(12), s(8)
    local fixed = sign_h + s(4) + lip_h + gap
    local rows = (room / 3 - fixed) >= s(100) and 3 or 2
    local cover_h = math.floor(room / rows - fixed)
    local cgap = s(10)
    local col_w = math.floor((w - 2 * pad - (Stand.COLS - 1) * cgap) / Stand.COLS)
    local box_w = col_w - s(6)
    local box_h = math.min(cover_h, math.floor(box_w / Stand.RATIO))
    box_w = math.min(box_w, math.floor(box_h * Stand.RATIO + 0.5))
    L.posts = { left = s(4), right = w - s(4) - s(6), w = s(6), top = top - s(4), bottom = L.counter.y }
    L.racks = {}
    local y = top
    for i = 1, rows do
        local sign = { x = pad + s(6), y = y, h = sign_h }
        local area_top = y + sign_h + s(4)
        local feet = area_top + cover_h -- where the covers stand
        local cols = {}
        for c = 1, Stand.COLS do cols[c] = { x = pad + (c - 1) * (col_w + cgap), w = col_w } end
        L.racks[i] = { sign = sign, top = area_top, cover_h = cover_h, box_w = box_w, box_h = box_h, cols = cols,
            feet = feet, lip = { x = s(10), y = feet - math.floor(lip_h / 2), w = w - 2 * s(10), h = lip_h } }
        y = feet + lip_h + gap
    end
    L.fits = box_h >= s(40) and box_w >= s(30)
    return L
end

---------------------------------------------------------------- what's on it

--- The racks' contents from the issues (newest first): Latest issues, then
--- the magazines with the newest issues, one a rack. Pure.
--- Returns { { kind = "latest" | "magazine", label, books, group }, … } (`rows` of them).
function Stand.racks(issues, rows)
    local Mag = require("gzreader_magazines")
    local out = { { kind = "latest", label = _("Latest issues"), books = {} } }
    for i = 1, math.min(Stand.SHOWN, #(issues or {})) do out[1].books[i] = issues[i] end
    out[1].total = #(issues or {})
    local groups = Mag.groups(issues)
    -- (one magazine only: its own rack would be Latest issues again)
    if #groups >= 2 then
        for _i, g in ipairs(groups) do
            if #out >= rows then break end
            local books = {}
            for k = 1, math.min(Stand.SHOWN, #g.issues) do books[k] = g.issues[k] end
            out[#out + 1] = { kind = "magazine", label = g.name, books = books, group = g, total = #g.issues }
        end
    end
    return out
end

---------------------------------------------------------------- the issues (kept, fetched)

local function standKey(browser, id)
    return require("gzreader_bookshop").cacheKey(browser, "stand:" .. tostring(id))
end

--- The stand's issues now (the saved copy), and a fresh fetch once per visit;
--- the page is drawn again when it's back.
function Stand.lists(browser)
    local Mag = require("gzreader_magazines")
    local m = Mag.get(browser.plugin)
    local st = browser._stand or {}
    browser._stand = st
    if not m then return st end
    if st.id ~= tostring(m.id) then
        st.id, st.asked, st.fetched = tostring(m.id), nil, nil
        local kept = require("gzreader_listcache").get(standKey(browser, m.id))
        st.issues = type(kept) == "table" and kept.issues or nil
        st.total = type(kept) == "table" and kept.total or nil
        Mag.noteIssues(st.issues)
    end
    if not st.asked then
        st.asked = true
        Stand.fetch(browser, m)
    end
    return st
end

function Stand.fetch(browser, m)
    local st = browser._stand
    if not (browser.api and browser.api.isPaired and browser.api:isPaired()) then return end
    local Net = require("gzreader_net")
    local function go()
        st.loading = true
        local api = browser.api
        require("gzreader_async").run(api, function()
            local issues, total = require("gzreader_magazines").fetch(api, m.id)
            return issues and { issues = issues, total = total } or nil
        end, function(res)
            st.loading = false
            st.fetched = true
            if type(res) == "table" and type(res.issues) == "table" then
                st.issues, st.total = res.issues, res.total
                require("gzreader_magazines").noteIssues(res.issues)
                require("gzreader_listcache").put(standKey(browser, m.id), res)
            end
            local menu = browser.menu
            local Shop = require("gzreader_bookshop")
            if menu and not browser.closed and Shop.applies(menu) and menu.item_table.gz_catalog == "magazines" then pcall(menu.updateItems, menu) end
        end, "magazine stand")
    end
    if Net.connected() then return go() end
    Net.run(go, { quiet = true, reason = "Catalog: magazines", usb = true })
end

---------------------------------------------------------------- painting

local function draw() return require("gzreader_bookshop").draw end

--- The awning: stripes, a scalloped edge, the plate with the library's name.
local function paintAwning(bb, r, name)
    local d = draw()
    local stripe = S(22)
    local dark, light = d.gray(0.8), Blitbuffer.COLOR_WHITE -- (gray(v): how dark)
    local k = 0
    for sx = r.x, r.x + r.w - 1, stripe do
        local sw = math.min(stripe, r.x + r.w - sx)
        local c = (k % 2 == 0) and dark or light
        local is_light = k % 2 == 1
        bb:paintRect(sx, r.y, sw, r.h, c)
        -- its scallop: a half disc under the stripe
        local rad = math.floor(stripe / 2)
        local cx = sx + rad
        for dy = 0, r.scallop - 1 do
            local half = math.floor(math.sqrt(math.max(0, rad * rad - (dy * rad / r.scallop) ^ 2)))
            bb:paintRect(math.max(r.x, cx - half), r.y + r.h + dy, math.min(2 * half, r.x + r.w - (cx - half)), 1, c)
        end
        -- (the light stripes' edge, so they show on the white wall)
        if is_light then
            bb:paintRect(sx, r.y, 1, r.h, d.gray(0.55))
            bb:paintRect(sx + sw - 1, r.y, 1, r.h, d.gray(0.55))
        end
        k = k + 1
    end
    -- the rail it hangs from, and its shadow
    bb:paintRect(r.x, r.y, r.w, math.max(2, S(4)), Blitbuffer.COLOR_BLACK)
    for i = 0, S(3) - 1 do bb:darkenRect(r.x, r.y + r.h + r.scallop + i, r.w, 1, 0.25 * (1 - i / S(3))) end
    -- the plate
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = name, face = d.hand(22), bold = true, max_width = math.floor(r.w * 0.6) }
    local sz = t:getSize()
    local pw, ph = sz.w + S(28), math.min(r.h - S(8), sz.h + S(8))
    local px, py = r.x + math.floor((r.w - pw) / 2), r.y + math.floor((r.h - ph) / 2) + S(2)
    bb:paintRect(px + S(3), py + S(3), pw, ph, d.gray(0.45))
    bb:paintRect(px, py, pw, ph, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(px, py, pw, ph, math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
    t:paintTo(bb, px + S(14), py + math.floor((ph - sz.h) / 2))
    t:free()
end

--- A rack's back: a wire grid between the posts.
local function paintGrid(bb, x, y, w, h)
    local d = draw()
    bb:paintRect(x, y, w, h, d.gray(0.04))
    local step = S(18)
    for gx = x + step, x + w - 1, step do bb:paintRect(gx, y, 1, h, d.gray(0.22)) end
    for gy = y + step, y + h - 1, step do bb:paintRect(x, gy, w, 1, d.gray(0.22)) end
end

--- The rail across the covers' feet: two wires and their posts.
local function paintLip(bb, r, cols)
    local d = draw()
    local wire = math.max(2, S(3))
    bb:paintRect(r.x, r.y, r.w, wire, d.gray(0.75))
    bb:paintRect(r.x, r.y + r.h - wire - S(1), r.w, wire + S(1), d.gray(0.9))
    for _i, c in ipairs(cols) do
        bb:paintRect(c.x + math.floor(c.w / 2), r.y, math.max(1, S(2)), r.h, d.gray(0.7))
    end
    for i = 0, S(4) - 1 do bb:darkenRect(r.x + S(4), r.y + r.h + i, r.w - S(8), 1, 0.3 * (1 - i / S(4))) end
end

--- A price tag hanging from the rail (the rack's whole list).
local function paintTag(bb, col, rail_y, label)
    local d = draw()
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = d.hand(18), max_width = col.w - S(10) }
    local sz = t:getSize()
    local tw, th = sz.w + S(22), sz.h + S(10)
    local tx = col.x + math.floor((col.w - tw) / 2)
    local ty = rail_y - th - S(26)
    -- its string to the rail
    bb:paintRect(tx + S(10), ty + math.floor(th / 2), 1, rail_y - ty - math.floor(th / 2), Blitbuffer.COLOR_BLACK)
    bb:paintRect(tx + S(2), ty + S(2), tw, th, d.gray(0.35))
    bb:paintRect(tx, ty, tw, th, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(tx, ty, tw, th, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    bb:paintCircle(tx + S(10), ty + math.floor(th / 2), math.max(2, S(3)), Blitbuffer.COLOR_BLACK, 1)
    t:paintTo(bb, tx + S(18), ty + math.floor((th - sz.h) / 2))
    t:free()
    return { x = tx, y = ty, w = tw, h = th }
end

--- A label tag in the top corner of a cover (ON KINDLE).
local function cornerTag(bb, x, y, w, label)
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 9), bold = true, fgcolor = Blitbuffer.COLOR_WHITE }
    local tsz = t:getSize()
    local tx, ty = x + w - tsz.w - S(8), y + S(4)
    bb:paintRect(tx - S(3), ty, tsz.w + S(6), tsz.h, Blitbuffer.COLOR_BLACK)
    t:paintTo(bb, tx, ty)
    t:free()
end

--- A drawer of the counter: its front, a card in a holder (name, count,
--- letter) and a knob.
local function paintDrawer(bb, menu, r, name, sub, letter, focused)
    local d = draw()
    bb:paintRect(r.x, r.y, r.w, r.h, d.gray(0.3))
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(1, S(2)), d.gray(0.7))
    local cw, ch = math.floor(r.w * 0.8), math.floor(r.h * 0.62)
    local cx, cy = r.x + math.floor((r.w - cw) / 2), r.y + S(6)
    bb:paintRect(cx - S(3), cy - S(3), cw + S(6), ch + S(6), d.gray(0.75)) -- the holder
    bb:paintRect(cx, cy, cw, ch, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(cx, cy, cw, ch, 1, Blitbuffer.COLOR_BLACK)
    local side = (letter and menu.is_enable_shortcut) and S(20) or 0
    if side > 0 then d.badge(bb, menu, letter, cx + S(6), cy + math.floor((ch - side) / 2), side) end
    local tx = cx + S(10) + (side > 0 and side + S(4) or 0)
    local sub_w = 0
    if sub and sub ~= "" then
        local TextWidget = require("ui/widget/textwidget")
        local t = TextWidget:new{ text = sub, face = Font:getFace("cfont", 11), fgcolor = d.gray(0.75) }
        local tsz = t:getSize()
        sub_w = tsz.w + S(8)
        t:paintTo(bb, cx + cw - tsz.w - S(8), cy + math.floor((ch - tsz.h) / 2))
        t:free()
    end
    d.text(bb, name, d.hand(20), tx, cy + math.floor(ch / 2), { middle = true, max_width = cw - (tx - cx) - S(6) - sub_w })
    local ky = cy + ch + math.floor((r.y + r.h - cy - ch) / 2)
    bb:paintCircle(r.x + math.floor(r.w / 2), ky, math.max(3, S(5)), d.gray(0.85))
    if focused then
        bb:paintBorder(r.x - S(4), r.y - S(4), r.w + S(8), r.h + S(8), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    end
end

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }

function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

function Page:paintRack(bb, ox, oy, i)
    local d = draw()
    local L, menu = self.L, self.menu
    local R = L.racks[i]
    local spec = self.racks[i]
    paintGrid(bb, ox + L.posts.left + L.posts.w, oy + R.top - S(6), L.w - 2 * (L.posts.left + L.posts.w), R.feet - R.top + S(6))
    local feet = oy + R.feet
    if not spec then return end
    local sr = d.sign(bb, menu, { x = ox + R.sign.x, y = oy + R.sign.y, h = R.sign.h }, spec.label, spec.count, spec.letter)
    if spec.sign_hot then
        spec.sign_hot.dimen = Geom:new(sr)
        if spec.sign_hot.focused then d.focusRing(bb, sr) end
    end
    local msg = #spec.items == 0 and (spec.loading and _("Fetching your magazines…") or spec.empty) or ""
    if msg ~= "" then
        d.text(bb, msg, d.hand(20), ox + math.floor(L.w / 2), feet - math.floor(R.cover_h / 2), { center = true, middle = true, color = d.gray(0.7) })
    end
    local plugin = self.browser and self.browser.plugin
    local rings = {}
    for c, item in ipairs(spec.items) do
        local col = R.cols[c]
        local cx = ox + col.x
        if item.book then
            local widget, iw, ih = d.cover(item.book, R.box_w, R.box_h, nil)
            local x = cx + math.floor((col.w - iw) / 2)
            local y = feet - ih
            bb:paintRect(x + S(4), y + S(4), iw, ih, d.gray(0.4)) -- its shadow on the grid
            widget:paintTo(bb, x, y)
            if widget.free then widget:free() end
            bb:paintBorder(x, y, iw, ih, 1, Blitbuffer.COLOR_BLACK)
            item.hot.dimen = Geom:new{ x = x, y = y, w = iw, h = ih }
            if plugin and type(plugin.localPathFor) == "function" and plugin:localPathFor(item.book.id) then
                cornerTag(bb, x, y, iw, _("ON KINDLE"))
            end
            if item.hot.focused then rings[#rings + 1] = item.hot.dimen end
        else
            local r = paintTag(bb, { x = cx, w = col.w }, feet - math.floor(R.lip.h / 2), item.label)
            item.hot.dimen = Geom:new(r)
            if item.hot.focused then rings[#rings + 1] = item.hot.dimen end
        end
    end
    -- the rail over the covers' feet, then the focus over everything
    paintLip(bb, { x = ox + R.lip.x, y = oy + R.lip.y, w = R.lip.w, h = R.lip.h }, (function()
        local out = {}
        for _k, c in ipairs(R.cols) do out[#out + 1] = { x = ox + c.x, w = c.w } end
        return out
    end)())
    for _k, r in ipairs(rings) do d.focusRing(bb, r) end
end

function Page:paintTo(bb, x, y)
    local d = draw()
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local L, menu = self.L, self.menu
    d.wall(bb, x, y, self.w, self.h)
    -- the stand's posts
    local P = L.posts
    for _i, px in ipairs({ P.left, P.right }) do
        bb:paintRect(x + px, y + P.top, P.w, P.bottom - P.top, d.gray(0.35))
        bb:paintRect(x + px + P.w - 1, y + P.top, 1, P.bottom - P.top, d.gray(0.7))
    end
    paintAwning(bb, { x = x + L.awning.x, y = y + L.awning.y, w = L.awning.w, h = L.awning.h, scallop = L.awning.scallop }, self.name)
    d.slip(bb, menu, { x = x + L.slip.x, y = y + L.slip.y, w = L.slip.w, h = L.slip.h }, self.search_text, self.search_letter, self.search_hot)
    for i = 1, #L.racks do self:paintRack(bb, x, y, i) end
    -- the counter
    local C = L.counter
    bb:paintRect(x + C.x + S(4), y + C.y + S(4), C.w, C.h, d.gray(0.25))
    bb:paintRect(x + C.x, y + C.y, C.w, C.h, d.gray(0.55))
    d.ledge(bb, { x = x + C.x - S(4), y = y + C.y, w = C.w + S(8), h = C.top })
    for i, dr in ipairs(self.drawers) do
        local r = L.drawers[i]
        local rr = { x = x + r.x, y = y + r.y, w = r.w, h = r.h }
        paintDrawer(bb, menu, rr, dr.name, dr.sub, dr.letter, dr.hot.focused)
        dr.hot.dimen = Geom:new(rr)
    end
end

---------------------------------------------------------------- building it

--- Draw the stand in place of the Magazines page's list (m: the browser's
--- Menu, W x H the room the bookshop has). False when it doesn't fit.
function Stand.build(m, browser, W, H, select_number, old_dimen)
    local Shop = require("gzreader_bookshop")
    local Mag = require("gzreader_magazines")
    local L = Stand.layout(W, H)
    if not L.fits then return false end
    local mag = Mag.get(browser.plugin)
    local by = Shop.entryById(m)
    local Covers = require("gzreader_covers")
    Covers.beginPage()
    local search = by.mag_search
    local page = Page:new{ w = W, h = H, L = L, menu = m, browser = browser,
        name = mag and mag.name or _("Magazines"),
        search_text = _("Search magazines…") }
    local function hot(entry)
        local h = Shop.Hot:new{ menu = m, entry = entry, shop = page }
        page[#page + 1] = h
        return h
    end
    page.search_hot = hot(search and search.entry)
    page.search_letter = search and Shop.letterOf(m, search.idx)
    m.layout = { { page.search_hot } }
    -- the racks
    local st = Stand.lists(browser)
    local Browser_ = require("gzreader_browser")
    local issues = {}
    for _i, b in ipairs(type(st.issues) == "table" and st.issues or {}) do
        if type(b) == "table" and (browser.isReadable or Browser_.isReadable)(b) then issues[#issues + 1] = b end
    end
    local wanted = {}
    page.racks = {}
    for i, rack in ipairs(Stand.racks(issues, #L.racks)) do
        local root = rack.kind == "latest" and by.mag_latest or nil
        local entry = root and root.entry
            or { text = rack.label, callback = function() browser:openMagazine(rack.group) end }
        local spec = {
            label = rack.label,
            count = rack.total and rack.total > 0 and tostring(rack.kind == "latest" and (st.total or rack.total) or rack.total) or nil,
            letter = root and Shop.letterOf(m, root.idx),
            items = {},
            loading = st.loading and not st.fetched,
            empty = i == 1 and _("No issues in this library yet") or "",
        }
        spec.sign_hot = hot(entry)
        local row = {}
        for _k, book in ipairs(rack.books) do
            local item = { book = book, hot = hot(browser:bookItem(book)) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
            wanted[#wanted + 1] = { id = book.id }
        end
        if #rack.books > 0 then
            local more = (tonumber(rack.kind == "latest" and st.total or rack.total) or 0) - #rack.books
            local item = { label = more > 0 and T(_("+%1 more"), more) or _("See all"), hot = hot(entry) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
        end
        if #row == 0 then row[1] = spec.sign_hot end
        m.layout[#m.layout + 1] = row
        page.racks[i] = spec
    end
    -- the drawers
    local groups = Mag.groups(issues)
    page.drawers = {}
    local drow = {}
    for _i, d in ipairs({
        { id = "mag_titles", name = _("Magazines A–Z"), sub = #groups > 0 and (#groups == 1 and _("1 magazine") or T(_("%1 magazines"), #groups)) or _("by title") },
        { id = "mag_all", name = _("All issues"), sub = tonumber(st.total) and (st.total == 1 and _("1 issue") or T(_("%1 issues"), st.total)) or _("A–Z") },
    }) do
        local root = by[d.id]
        d.letter = root and Shop.letterOf(m, root.idx)
        d.hot = hot(root and root.entry)
        page.drawers[#page.drawers + 1] = d
        drow[#drow + 1] = d.hot
    end
    m.layout[#m.layout + 1] = drow
    table.insert(m.item_group, page)
    m._gz_shop = page
    -- start on the first cover; back from a list: on what opened it
    local fx, fy = 1, m.layout[2] and 2 or 1
    local back = m._gz_shop_last or (select_number and m.item_table[select_number])
    if back then
        for yy, r in ipairs(m.layout) do
            for xx, h in ipairs(r) do
                if h.entry == back or (type(back) == "table" and back.gz_id and type(h.entry) == "table" and h.entry.gz_id == back.gz_id) then
                    fx, fy = xx, yy
                end
            end
        end
    end
    m:updatePageInfo(fy)
    if fx > 1 and Device:hasDPad() then m:moveFocusTo(fx, fy) end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    local items = m.item_table
    Covers.fetch(browser.plugin, wanted, function(got)
        if got > 0 and m.item_table == items and not m._gz_closed and Shop.applies(m) then pcall(m.updateItems, m) end
    end)
end

return Stand
