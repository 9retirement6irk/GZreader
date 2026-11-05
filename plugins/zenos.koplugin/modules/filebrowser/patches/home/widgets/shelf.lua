-- GZreader: the Home strip as a bookshelf. Books stand on wooden shelves with
-- their spines out (title, author, number in the series); the one the 5-way
-- is on, or that was tapped, is pulled out and shows its cover. Tap it (or
-- Press, or its letter) to open it. One shelf: the most recent books.
--
-- Drawn with rectangles and text (e-ink greys), with some depth: spines are
-- rounded with light from the left (darker edges, a highlight), cast a shadow
-- on the wall, and the board has a top, a front edge and a shadow below. A
-- spine is drawn once and kept (spine_cache) until the shelf changes size.
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
M.MIN_SPINE = 34
M.MAX_SPINE = 46
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

local function draw_spine(book, w, h, shade)
    -- drawn lying down (h wide, w tall), then stood up
    local lying = Blitbuffer.new(h, w, Blitbuffer.TYPE_BB8)
    local dark = shade >= 0.5
    local ink = dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    lying:fill(Blitbuffer.gray(shade))
    -- the top: the headband over the pages; bands near each end (the bottom
    -- one above the letter key's square)
    local cap = math.max(3, S(5))
    lying:paintRect(0, 0, cap, w, Blitbuffer.gray(math.max(0, shade - 0.25)))
    lying:paintRect(cap, 0, 1, w, Blitbuffer.gray(math.min(1, shade + 0.25)))
    for _i, bx in ipairs({ cap + S(5), h - S(36) }) do
        lying:paintRect(bx, 0, 1, w, Blitbuffer.gray(math.max(0, shade - 0.3)))
        lying:paintRect(bx + 1, 0, S(2), w, ink)
        lying:paintRect(bx + 1 + S(2), 0, 1, w, Blitbuffer.gray(math.min(1, shade + 0.3)))
    end
    -- the top of the spine: its number in the series, then the title and
    -- author; the bottom is kept for the letter key's square
    local num = book_number(book)
    local x0 = cap + S(12)
    if num then
        local n = TextWidget:new{ text = num, face = Font:getFace("cfont", 12), bold = true, fgcolor = ink }
        local ns = n:getSize()
        n:paintTo(lying, x0, math.floor((w - ns.h) / 2))
        x0 = x0 + ns.w + S(8)
        n:free()
    end
    local room = h - x0 - S(42)
    local author = book_author(book)
    -- (every spine with an author shows it: the narrow ones in smaller type;
    -- 1.22.3 left it off spines under 37 px)
    local two = author ~= ""
    local narrow = w < S(37)
    local title_face = Font:getFace("cfont", two and (narrow and 12 or 14) or 15)
    local title = TextWidget:new{ text = book_title(book), face = title_face, bold = true, fgcolor = ink, max_width = room }
    local th = title:getSize().h
    if two then
        local auth = TextWidget:new{ text = author, face = Font:getFace("cfont", narrow and 10 or 11), fgcolor = ink, max_width = room }
        local ah = auth:getSize().h
        local top = math.floor((w - th - ah + S(2)) / 2)
        title:paintTo(lying, x0, top)
        auth:paintTo(lying, x0, top + th - S(2))
        auth:free()
    else
        title:paintTo(lying, x0, math.floor((w - th) / 2))
    end
    title:free()
    local stood = lying:rotatedCopy(270)
    lying:free()
    M.shadeRound(stood, 0, 0, w, h)
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

--- A spine (w x h), its edge drawn darker.
local Spine = WidgetContainer:extend{ w = 0, h = 0, book = nil, shade = 0.5 }
function Spine:getSize() return Geom:new{ w = self.w, h = self.h } end
function Spine:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local img = spine_bb(self.book, self.w, self.h, self.shade)
    bb:blitFrom(img, x, y, 0, 0, self.w, self.h)
    bb:paintBorder(x, y, self.w, self.h, 1, Blitbuffer.gray(0.9))
end
function Spine:free() end -- (the picture stays in spine_cache)

--- A spine widget for `book` ({ path, title, authors, series_index }).
function M.newSpine(book, w, h, shade)
    return Spine:new{ w = w, h = h, book = book, shade = shade }
end

---------------------------------------------------------------- depth

--- The board under the books at board_y, `w` wide: a top seen from above
--- (narrower at the back), a front edge, and its shadow on the wall.
function M.paintBoard(bb, x, board_y, w)
    local top_h, front_h = S(5), S(M.BOARD_H) - S(5)
    for i = 0, top_h - 1 do
        local inset = math.floor((top_h - i) * S(6) / top_h)
        bb:paintRect(x + inset, board_y + i, w - 2 * inset, 1, Blitbuffer.gray(0.16 + 0.12 * i / top_h))
    end
    local fy = board_y + top_h
    bb:paintRect(x, fy, w, front_h, Blitbuffer.gray(0.58))
    bb:paintRect(x, fy, w, 1, Blitbuffer.gray(0.30))
    bb:paintRect(x, fy + front_h - 1, w, 1, Blitbuffer.gray(0.85))
    local under = S(M.UNDER_H)
    for i = 0, under - 1 do
        bb:darkenRect(x + S(4), fy + front_h + i, w - S(8), 1, 0.45 * (1 - i / under))
    end
end

--- Where the books stand: a contact shadow on the board's top, and each
--- spine's shadow on the wall beside a shorter neighbour (light from the left).
--- spans = { { x, w, h }, ... } in order, standing on board_y.
function M.paintDepth(bb, board_y, spans)
    for k, sp in ipairs(spans) do
        bb:darkenRect(sp.x, board_y, sp.w + S(2), S(3), 0.35)
        local nxt = spans[k + 1]
        local drop = sp.h - (nxt and nxt.x == sp.x + sp.w and nxt.h or 0)
        if drop > S(6) then
            bb:darkenRect(sp.x + sp.w, board_y - sp.h + S(5), S(5), drop - S(5), 0.30)
            bb:darkenRect(sp.x + sp.w + S(5), board_y - sp.h + S(8), S(3), drop - S(8), 0.15)
        end
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
--- opts = { ctx, width, height, rows, interactive, source_name, row_offset }
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
    local per_row = math.ceil(#books / rows)
    local targets, jobs = {}, {}
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local group = VerticalGroup:new{ align = "left" }
    local menu = ctx.menu
    for r = 1, rows do
        local shelf = Shelf:new{ w = width, h = row_h, area_h = area_h, slots = {}, menu = menu,
            cover_w = cover_w, cover_h = cover_h, empty_text = #books == 0 and opts.empty_text or nil }
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
