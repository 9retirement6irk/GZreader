--[[--
Settings → Downloads → Appearance → Bookshelf theme (and a hold on an
ornament on the shelves): the shelves' look as tiles, each a small picture
of what it does, with a preview of your shelf at the top. The sleep
screen's tiles (gzreader_sleeppreview.lua) are the model.

  * Bookshelf theme: the preview; which screens have ornaments (Home,
    Downloads, Catalog: chips); Plank (Oak, Walnut, Plain); Ornaments
    (None, Where there's room, On every page); Where on the shelf (Right
    end, Left end, Scattered); How many on a page (One, Up to two, Up to
    three, Every shelf); then Which ornaments and Your own ornaments.
  * Which ornaments: every ornament as a tile (a tick: it stands on the
    shelves; a seasonal one says whether it's in season), the one tapped
    or held last on a shelf at the top. A tap puts it on the shelves or
    takes it off; a hold only shows it.

A tap changes the setting at once and draws the screen again; the shelves
under it are drawn again when it closes (Theme.defer). Kindles with keys:
the 5-way moves, Press chooses, the page keys turn the ornaments' pages,
Back closes. Each tile's picture is drawn once while the screen is open;
only the preview is drawn again after a change.
]]

local Device = require("device")
local _ = require("gettext")

local Screen = Device.screen
local function S(n) return Screen:scaleBySize(n) end
local function T(...) return require("ffi/util").template(...) end
local function Theme() return require("gzreader_shelftheme") end
local function Sh() return require("modules/filebrowser/patches/home/widgets/shelf") end

local P = {
    -- spines for the preview when the reader has read few books yet (public domain)
    SAMPLE = {
        { "Pride and Prejudice", "Jane Austen" }, { "Moby-Dick", "Herman Melville" },
        { "Jane Eyre", "Charlotte Brontë" }, { "Middlemarch", "George Eliot" },
        { "Dracula", "Bram Stoker" }, { "Emma", "Jane Austen" }, { "Walden", "Henry David Thoreau" },
        { "Little Women", "Louisa May Alcott" }, { "Frankenstein", "Mary Shelley" },
        { "The Odyssey", "Homer" }, { "Persuasion", "Jane Austen" }, { "Ivanhoe", "Walter Scott" },
    },
    COLS = 3,
}

---------------------------------------------------------------- the choices

--- The theme screen's choices, section by section: { title, cols,
--- { { id, label, on(), pick() } } }. pick() changes the setting.
function P.sections()
    local Th = Theme()
    local labels = Th.labels()
    local function radio(get, set, list)
        local out = {}
        for i, c in ipairs(list) do
            out[i] = { id = c[1], label = c[2], on = function() return get() == c[1] end, pick = function() set(c[1]) end }
        end
        return out
    end
    return {
        { title = _("Plank"), kind = "plank", items = radio(Th.get, Th.set,
            { { "oak", labels.oak }, { "walnut", labels.walnut }, { "plain", labels.plain } }) },
        { title = _("Ornaments"), kind = "mode", items = radio(Th.ornaments, Th.setOrnaments,
            { { "off", _("None") }, { "room", _("Where there's room") }, { "always", _("On every page") } }) },
        { title = _("Where on the shelf"), kind = "side", items = radio(Th.side, Th.setSide,
            { { "right", _("Right end") }, { "left", _("Left end") }, { "scattered", _("Scattered") } }) },
        { title = _("How many on a page"), kind = "count", items = radio(
            function() local c = Th.count(); return c == math.huge and "all" or c end, Th.setCount,
            { { 1, _("One") }, { 2, _("Up to two") }, { 3, _("Up to three") }, { "all", _("Every shelf") } }) },
    }
end

--- The screens that have ornaments, as chips: { id, label, on(), pick() }.
function P.places()
    local Th = Theme()
    local names = { home = _("Home"), downloads = _("Downloads"), catalog = _("Catalog") }
    local out = {}
    for i, id in ipairs(Th.PLACE_ORDER) do
        out[i] = { id = id, label = names[id], on = function() return Th.placeOn(id) end,
            pick = function() Th.setPlace(id, not Th.placeOn(id)) end }
    end
    return out
end

--- Which ornaments stand now, of how many: on, total.
function P.counts()
    local Th = Theme()
    local on, all = 0, Th.list()
    for _i, e in ipairs(all) do if Th.isOn(e) then on = on + 1 end end
    return on, #all
end

--- A seasonal ornament's tag: "In season", "Not in season", or nil (not
--- seasonal, or ticked / unticked by hand: it follows that).
function P.seasonTag(entry)
    local Th = Theme()
    if not entry.season or Th.byHand(entry) ~= nil then return nil end
    local month, day = Th.date()
    return Th.inSeason(entry.season, month, day) and _("In season") or _("Not in season")
end

--- The ornament the Which ornaments preview starts with: a seasonal one in
--- its season, else the first standing, else the first.
function P.firstShown()
    local Th = Theme()
    local on, seasonal = Th.standing()
    return seasonal[1] or on[1] or Th.list()[1]
end

--- Is there a seasonal ornament ticked or unticked by hand (Seasonal ones
--- in their season again does something)?
function P.seasonalByHand()
    local Th = Theme()
    for _i, e in ipairs(Th.list()) do
        if e.season and Th.byHand(e) ~= nil then return true end
    end
    return false
end

--- Which page of the ornaments shows `n` of them with `per` on a page:
--- pages, first and last index on page `pg`. (The last place on the last
--- page is Your own….)
function P.pageOf(n, per, pg)
    local total = n + 1
    local pages = math.max(1, math.ceil(total / per))
    pg = math.max(1, math.min(pages, pg or 1))
    local first = (pg - 1) * per + 1
    return pages, pg, first, math.min(total, first + per - 1)
end

--- The ornaments a tile's picture uses (those standing, else any): a list.
function P.sampleOrnaments(n)
    local Th = Theme()
    local on = Th.standing()
    local list = #on > 0 and on or Th.list()
    local out = {}
    for i = 1, n do out[i] = list[((i - 1) % math.max(1, #list)) + 1] end
    return out
end

---------------------------------------------------------------- layout

--- The theme screen's places for a screen sw × sh: picture heights and
--- where each part starts (pure arithmetic, for the tests too).
function P.themeLayout(sw, sh)
    local pad, gap, top = S(12), S(8), S(56)
    local chip_h, label_h, cap_h, row_h, sec_gap = S(32), S(24), S(28), S(42), S(6)
    local fixed = top + S(8) + S(6) + chip_h + S(6) + 4 * (label_h + cap_h) + 3 * sec_gap + 2 * row_h + S(10)
    -- the preview is twice a tile's picture; Where's are taller, How many's lower
    local ph = math.floor((sh - fixed) / (2 + 1 + 1 + 1.25 + 0.9))
    ph = math.max(S(36), math.min(S(120), ph))
    local L = { pad = pad, gap = gap, top = top, chip_h = chip_h, label_h = label_h, cap_h = cap_h, row_h = row_h,
        sw = sw, sh = sh, ph = ph }
    local y = top + S(8)
    L.preview = { x = pad, y = y, w = sw - 2 * pad, h = 2 * ph }
    y = y + 2 * ph + S(6)
    L.chips_y = y
    y = y + chip_h + S(6)
    L.sections = {}
    for i, f in ipairs({ 1, 1, 1.25, 0.9 }) do
        local h = math.floor(ph * f)
        L.sections[i] = { label_y = y, y = y + label_h, ph = h }
        y = y + label_h + h + cap_h + sec_gap
    end
    L.rows_y = y - sec_gap + S(4)
    return L
end

--- The Which ornaments screen's places: columns, rows, tile size.
function P.whichLayout(sw, sh)
    local pad, gap, top = S(12), S(8), S(56)
    local L = { pad = pad, gap = gap, top = top, cap_h = S(26), sw = sw, sh = sh }
    L.hint_y = top + S(8)
    L.preview = { x = pad, y = top + S(36), w = sw - 2 * pad, h = S(118) }
    L.caption_y = L.preview.y + L.preview.h + S(4)
    L.grid_y = L.caption_y + S(30)
    local bottom = sh - S(44) -- (the footer: the page and Seasonal ones in their season again)
    L.cols = sw > sh and 5 or 4
    L.tw = math.floor((sw - 2 * pad - (L.cols - 1) * gap) / L.cols)
    local room = bottom - L.grid_y
    local rows = 5
    local ph = math.floor((room - (rows - 1) * gap) / rows) - L.cap_h
    while rows > 2 and ph < math.floor(L.tw * 0.5) do
        rows = rows - 1
        ph = math.floor((room - (rows - 1) * gap) / rows) - L.cap_h
    end
    L.rows, L.ph = rows, math.min(ph, math.floor(L.tw * 0.75))
    L.per = L.cols * L.rows
    L.footer_y = bottom + S(6)
    return L
end

---------------------------------------------------------------- drawing

--- The preview's books: the reader's recent ones (their spines as on
--- Home), then sample titles.
function P.books()
    if P._books then return P._books end
    local out = {}
    pcall(function()
        for _i, h in ipairs(require("readhistory").hist or {}) do
            if h.file and not h.dim then out[#out + 1] = { path = h.file } end
            if #out >= 14 then break end
        end
    end)
    for i, b in ipairs(P.SAMPLE) do
        if #out >= 14 then break end
        out[#out + 1] = { path = "gz-sample:" .. i, title = b[1], authors = b[2] }
    end
    P._books = out
    return out
end

--- A shelf in bb at x, y, w × h: the plank of theme `o.theme` (the one in
--- use when nil), books from o.books (o.first on, at most o.count; o.blocks:
--- plain blocks, for small pictures), and o.orns = { { entry, side =
--- "right" | "left" | "center" } }. o.keep: the books leave room for the
--- right one; else it stands only where there's room.
function P.paintShelf(bb, x, y, w, h, o)
    local Blitbuffer = require("ffi/blitbuffer")
    local M, Th = Sh(), Theme()
    local board_y
    if o.thin then
        -- (a small picture: a thin plank of the theme in use, or greys)
        local top_h, front_h = math.max(2, math.floor(h * 0.1)), math.max(2, math.floor(h * 0.08))
        board_y = y + h - top_h - front_h - math.max(1, math.floor(h * 0.05))
        local wood = Th.plank(w, top_h, front_h)
        if wood then bb:blitFrom(wood, x, board_y, 0, 0, w, top_h + front_h) else
            bb:paintRect(x, board_y, w, top_h, Blitbuffer.gray(0.3))
            bb:paintRect(x, board_y + top_h, w, front_h, Blitbuffer.gray(M.PLANK))
        end
        bb:darkenRect(x + 2, board_y + top_h + front_h, w - 4, math.max(1, math.floor(h * 0.05)), 0.3)
        board_y = board_y + math.floor(top_h / 2)
    else
        board_y = y + h - S(M.BOARD_H) - S(M.UNDER_H)
        Th.preview_theme = o.theme
        pcall(M.paintBoard, bb, x, board_y, w)
        Th.preview_theme = nil
    end
    local room_h = math.max(4, math.floor((board_y - y - S(2)) * (o.book_h or 1)))
    local plans = {}
    for i, orn in ipairs(o.orns or {}) do
        local stand_h = math.floor(room_h * (orn.scale or 1))
        local okp, plan = pcall(Th.planFor, orn.entry, w, stand_h, true)
        plans[i] = okp and plan or nil
    end
    local px, right = x + S(4), x + w - S(4)
    for i, orn in ipairs(o.orns or {}) do
        local plan = plans[i]
        if plan and orn.side == "left" then
            Th.paintPlanned(bb, plan, px + S(2), board_y)
            px = px + plan.room
        elseif plan and orn.side == "center" then
            Th.paintPlanned(bb, plan, x + math.floor((w - plan.w) / 2), board_y)
        end
    end
    local keep = 0
    for i, orn in ipairs(o.orns or {}) do
        if plans[i] and (orn.side == nil or orn.side == "right") and o.keep then keep = plans[i].room end
    end
    local books = o.books or {}
    local spans = {}
    for k = 1, math.min(o.count or #books, #books) do
        local book = books[((o.first or 1) + k - 2) % #books + 1]
        local look = M.look(book, room_h)
        local bw, bh = look.w, look.h
        if o.blocks then
            -- (Home's spines are at least S(60) tall: little blocks follow the room)
            bw = math.max(3, math.floor(bw * (o.blocks_w or 0.42)))
            bh = math.floor(room_h * (0.78 + (look.w % 7) / 30))
        end
        if px + bw > right - keep then break end
        if o.blocks then
            local top = board_y - bh
            bb:paintRect(px, top, bw, bh, Blitbuffer.gray(look.shade))
            bb:paintRect(px, top, bw, math.max(1, math.floor(bh * 0.07)), Blitbuffer.gray(0.08))
            bb:paintBorder(px, top, bw, bh, 1, Blitbuffer.gray(math.min(1, look.shade + 0.35)))
        else
            pcall(function() M.newSpine(book, bw, bh, look.shade):paintTo(bb, px, board_y - bh) end)
        end
        spans[#spans + 1] = { x = px, w = bw, h = bh }
        px = px + bw
    end
    if not o.blocks then pcall(M.paintDepth, bb, board_y, spans) end
    for i, orn in ipairs(o.orns or {}) do
        local plan = plans[i]
        if plan and (orn.side == nil or orn.side == "right") and (o.keep or px + plan.room <= right) then
            Th.paintPlanned(bb, plan, right - S(Th.MARGIN) - plan.w, board_y)
        end
    end
end

--- A page of `rows` small shelves (Where / How many tiles): orns[row] =
--- { entry, side } or nil.
function P.paintPage(bb, x, y, w, h, rows, orns)
    local gap = math.max(2, S(4))
    local rh = math.floor((h - gap * (rows - 1)) / rows)
    for r = 1, rows do
        local o = orns[r]
        P.paintShelf(bb, x, y + (r - 1) * (rh + gap), w, rh, { books = P.books(), first = r * 3, blocks = true, thin = true,
            blocks_w = 0.3, book_h = 0.75, keep = true, orns = o and { { entry = o[1], side = o[2], scale = 2 } } or {} })
    end
end

--- What a theme screen tile shows: draws into bb (w × h) for section
--- `kind`, choice `id`.
function P.paintChoice(bb, w, h, kind, id)
    local books = P.books()
    local orn = P.sampleOrnaments(4)
    if kind == "plank" then
        P.paintShelf(bb, 0, S(4), w, h - S(4), { theme = id, books = books, blocks = true, book_h = 0.8, count = 8 })
    elseif kind == "mode" then
        local o = id == "off" and {} or { { entry = orn[1], scale = 1.5 } }
        P.paintShelf(bb, 0, S(4), w, h - S(4), { books = books, blocks = true, book_h = 0.8, first = 4,
            count = id == "always" and 12 or 6, keep = id == "always", orns = o })
    elseif kind == "side" then
        local two = id == "right" and { "right", "right" } or id == "left" and { "left", "left" } or { "right", "left" }
        P.paintPage(bb, S(2), S(2), w - S(4), h - S(4), 3, { nil, { orn[1], two[1] }, { orn[2], two[2] } })
    elseif kind == "count" then
        local rows = id == "all" and 4 or 3
        local n = id == "all" and 4 or id
        local orns = {}
        for r = rows - n + 1, rows do orns[r] = { orn[(r - 1) % #orn + 1], "right" } end
        P.paintPage(bb, S(2), S(2), w - S(4), h - S(4), rows, orns)
    end
end

--- The theme screen's preview: a shelf of the reader's books with the
--- ornament the settings put there (on the first screen that has them).
function P.paintPreview(bb, w, h)
    local Th = Theme()
    local place = "home"
    for _i, id in ipairs(Th.PLACE_ORDER) do if Th.placeOn(id) then place = id; break end end
    local sides, nth = Th.rowsFor(place, { 1 })
    local orns = {}
    if sides[1] then
        local e = Th.pick("gz-preview", nth[1])
        if e then orns[1] = { entry = e, side = sides[1] } end
    end
    P.paintShelf(bb, 0, S(2), w, h - S(2), { books = P.books(), count = Th.keeps(place, 1, 1) and 14 or 9,
        keep = Th.keeps(place, 1, 1), orns = orns })
    return place
end

---------------------------------------------------------------- the parts

local function lazy()
    if P._W then return P._W end
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")

    local function text(bb, str, x, y, size, o)
        o = o or {}
        local t = TextWidget:new{ text = str, face = Font:getFace(o.font or "cfont", size), bold = o.bold,
            fgcolor = o.fg or Blitbuffer.COLOR_BLACK, max_width = o.max_width }
        local sz = t:getSize()
        local px = x
        if o.align == "center" then px = x - math.floor(sz.w / 2) elseif o.align == "right" then px = x - sz.w end
        t:paintTo(bb, px, y)
        t:free()
        return sz
    end

    -- a choice on a screen: a tile (picture + caption), a chip or a row
    local Spot = InputContainer:extend{ kind = "tile", w = 0, h = 0, ph = 0, label = "", value = nil,
        on = false, check = nil, faded = false, tag = nil, art = nil, callback = nil, hold_callback = nil }

    function Spot:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
        local range = function() return self.dimen end
        self.ges_events = {
            TapSpot = { GestureRange:new{ ges = "tap", range = range } },
            HoldSpot = { GestureRange:new{ ges = "hold", range = range } },
        }
    end
    function Spot:getSize() return Geom:new{ w = self.w, h = self.h } end
    function Spot:onTapSpot() if self.callback then self.callback(self) end; return true end
    function Spot:onHoldSpot()
        if self.hold_callback then self.hold_callback(self) elseif self.callback then self.callback(self) end
        return true
    end
    function Spot:onFocus() self.focused = true; return true end
    function Spot:onUnfocus() self.focused = false; return true end

    --- The tile's picture, drawn once (self.art(bb, w, h)) and kept.
    function Spot:picture(w, h)
        if self.pic and self.pic:getWidth() == w and self.pic:getHeight() == h then return self.pic end
        if self.pic then self.pic:free() end
        local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        if self.art then pcall(self.art, bb, w, h) end
        self.pic = bb
        return bb
    end

    function Spot:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w, h = self.w, self.h
        local black, white = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
        if self.kind == "chip" then
            local r = math.floor(h / 2)
            if self.on then bb:paintRoundedRect(x, y, w, h, black, r) else
                bb:paintRoundedRect(x, y, w, h, white, r)
                bb:paintBorder(x, y, w, h, math.max(1, S(1)), black, r)
            end
            text(bb, (self.on and "\u{2713} " or "") .. self.label, x + math.floor(w / 2), y + math.floor((h - S(20)) / 2) - S(1), 14,
                { align = "center", fg = self.on and white or black, max_width = w - S(8) })
        elseif self.kind == "row" then
            bb:paintRect(x, y, w, math.max(1, S(1)), Blitbuffer.gray(0.3))
            text(bb, self.label, x + S(6), y + math.floor((h - S(24)) / 2), 17)
            text(bb, (self.value and (self.value .. "  ") or "") .. "\u{203A}", x + w - S(6), y + math.floor((h - S(24)) / 2), 17,
                { align = "right", fg = Blitbuffer.gray(0.6) })
        else
            local ph = self.ph
            local frame = self.on and math.max(4, S(4)) or math.max(1, S(1))
            bb:paintRect(x, y, w, ph, white)
            local inner = frame
            local pic = self:picture(w - 2 * inner, ph - 2 * inner)
            bb:blitFrom(pic, x + inner, y + inner, 0, 0, pic:getWidth(), pic:getHeight())
            if self.faded then bb:lightenRect(x + inner, y + inner, w - 2 * inner, ph - 2 * inner, 0.65) end
            bb:paintBorder(x, y, w, ph, frame, black)
            if self.check ~= nil then -- a tick (stands on the shelves) or an empty ring
                local r = S(12)
                local cx, cy = x + w - inner - S(6) - r, y + inner + S(6) + r
                if self.check then
                    bb:paintCircle(cx, cy, r, black)
                    text(bb, "\u{2713}", cx, cy - S(11), 15, { align = "center", fg = white, bold = true })
                else
                    bb:paintCircle(cx, cy, r, white)
                    bb:paintCircle(cx, cy, r, Blitbuffer.gray(0.6), math.max(2, S(2)))
                end
            end
            if self.tag then
                local tw = TextWidget:new{ text = self.tag, face = Font:getFace("cfont", 11) }
                local sz = tw:getSize()
                local tx, ty = x + inner + S(4), y + inner + S(4)
                local now = self.tag == _("In season")
                bb:paintRect(tx, ty, sz.w + S(8), sz.h + S(2), now and black or white)
                bb:paintBorder(tx, ty, sz.w + S(8), sz.h + S(2), math.max(1, S(1)), black)
                tw:free()
                text(bb, self.tag, tx + S(4), ty + S(1), 11, { fg = now and white or black })
            end
            -- the caption: white on black for the choice in use (a radio's)
            local cap_h = h - ph
            local fg = (self.on and self.check == nil) and white or (self.faded and Blitbuffer.gray(0.55) or black)
            if self.on and self.check == nil then bb:paintRect(x, y + ph, w, cap_h, black) end
            local label = TextBoxWidget:new{ text = self.label, face = Font:getFace("cfont", 14), width = w - S(4),
                alignment = "center", height = cap_h - S(2), height_adjust = true, height_overflow_show_ellipsis = true,
                fgcolor = fg, bgcolor = (self.on and self.check == nil) and black or white }
            label:paintTo(bb, x + S(2), y + ph + S(2))
            label:free()
        end
        if self.focused then
            bb:paintBorder(x - S(4), y - S(4), w + 2 * S(4), h + 2 * S(4), math.max(3, S(3)), black)
        end
    end
    function Spot:free()
        if self.pic then self.pic:free(); self.pic = nil end
    end

    P._W = { Spot = Spot, text = text, Blitbuffer = Blitbuffer, Geom = Geom, GestureRange = GestureRange }
    return P._W
end

---------------------------------------------------------------- a screen

local function screenClass()
    if P._Screen then return P._Screen end
    local FocusManager = require("ui/widget/focusmanager")
    local UIManager = require("ui/uimanager")
    local W = lazy()
    local Blitbuffer = W.Blitbuffer

    local Base = FocusManager:extend{ modal = true, covers_fullscreen = true, title = "" }

    function Base:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        self.dimen = W.Geom:new{ x = 0, y = 0, w = sw, h = sh }
        -- (added to FocusManager's own: the 5-way's moves and Press)
        self.key_events = self.key_events or {}
        self.key_events.CloseBack = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } }
        self.key_events.Close = { { "Menu" } }
        self.close_box = W.Geom:new{ x = sw - S(64), y = 0, w = S(64), h = S(56) }
        self.ges_events = self.ges_events or {}
        self.ges_events.TapClose = { W.GestureRange:new{ ges = "tap", range = function() return self.close_box end } }
        self:build()
    end

    --- (subclasses: self.spots = { { spot, x, y } }, self.layout, self.labels)
    function Base:place(spot, x, y)
        self.spots[#self.spots + 1] = { spot = spot, x = x, y = y }
        self[#self + 1] = spot
        return spot
    end

    function Base:paintHeader(bb, x, y)
        local sw = self.dimen.w
        bb:paintRect(x, y, sw, self.dimen.h, Blitbuffer.COLOR_WHITE)
        W.text(bb, self.title, x + S(20), y + S(14), 22, { font = "tfont", bold = true, max_width = sw - S(100) })
        W.text(bb, "\u{00D7}", x + sw - S(44), y + S(10), 28)
        bb:paintRect(x, y + S(56), sw, math.max(1, S(1)), Blitbuffer.COLOR_DARK_GRAY)
    end

    function Base:paintSpots(bb, x, y)
        for _i, p in ipairs(self.spots) do p.spot:paintTo(bb, x + p.x, y + p.y) end
    end

    function Base:changed()
        self:refreshValues()
        UIManager:setDirty(self, "ui")
    end

    function Base:onTapClose() UIManager:close(self); return true end
    function Base:onClose() UIManager:close(self); return true end
    function Base:onCloseBack() UIManager:close(self); return true end

    function Base:onFocusMove(args)
        local r = FocusManager.onFocusMove(self, args)
        UIManager:setDirty(self, "ui")
        return r
    end

    function Base:onShow()
        if Device:hasDPad() and self.layout and self.layout[1] then self:moveFocusTo(1, 1) end
        UIManager:setDirty(self, "full")
        return true
    end

    function Base:freeSpots()
        for _i, p in ipairs(self.spots or {}) do p.spot:free() end
    end

    P._Screen = Base
    return Base
end

--- The Bookshelf theme screen.
local function themeScreen()
    if P._ThemeScreen then return P._ThemeScreen end
    local Base = screenClass()
    local UIManager = require("ui/uimanager")
    local W = lazy()
    local Blitbuffer = W.Blitbuffer
    local Screen1 = Base:extend{ name = "gzreader bookshelf theme" }

    function Screen1:build()
        self.title = _("Bookshelf theme")
        local L = P.themeLayout(self.dimen.w, self.dimen.h)
        self.L = L
        self.spots, self.layout, self.labels = {}, {}, {}
        -- the screens with ornaments: chips beside the preview's caption
        local row = {}
        local places = P.places()
        local chip_w = math.floor((L.sw - 2 * L.pad - 2 * S(8)) / 3)
        for i, c in ipairs(places) do
            local spot = self:place(W.Spot:new{ kind = "chip", w = chip_w, h = L.chip_h, label = c.label,
                on = c.on(), callback = function() c.pick(); self:changed() end }, L.pad + (i - 1) * (chip_w + S(8)), L.chips_y)
            spot.choice = c
            row[#row + 1] = spot
        end
        self.layout[#self.layout + 1] = row
        for si, sec in ipairs(P.sections()) do
            local S_ = L.sections[si]
            local cols = #sec.items
            local tw = math.floor((L.sw - 2 * L.pad - (cols - 1) * L.gap) / cols)
            self.labels[#self.labels + 1] = { text = sec.title, y = S_.label_y }
            row = {}
            for i, c in ipairs(sec.items) do
                local kind, id = sec.kind, c.id
                local spot = self:place(W.Spot:new{ w = tw, h = S_.ph + L.cap_h, ph = S_.ph, label = c.label, on = c.on(),
                    art = function(bb, w, h) P.paintChoice(bb, w, h, kind, id) end,
                    callback = function() c.pick(); self:changed() end }, L.pad + (i - 1) * (tw + L.gap), S_.y)
                spot.choice = c
                row[#row + 1] = spot
            end
            self.layout[#self.layout + 1] = row
        end
        local rw = L.sw - 2 * L.pad
        self.which = self:place(W.Spot:new{ kind = "row", w = rw, h = L.row_h, label = _("Which ornaments"),
            callback = function() P.showWhich(function() self:changed() end) end }, L.pad, L.rows_y)
        self.layout[#self.layout + 1] = { self.which }
        local own = self:place(W.Spot:new{ kind = "row", w = rw, h = L.row_h, label = _("Your own ornaments…"),
            callback = function() Theme().showOwnFolder() end }, L.pad, L.rows_y + L.row_h)
        self.layout[#self.layout + 1] = { own }
        self:refreshValues()
    end

    function Screen1:refreshValues()
        for _i, p in ipairs(self.spots) do
            if p.spot.choice then p.spot.on = p.spot.choice.on() end
        end
        local on, total = P.counts()
        self.which.value = T(_("%1 of %2"), on, total)
        if self.preview_bb then self.preview_bb:free(); self.preview_bb = nil end
    end

    function Screen1:paintTo(bb, x, y)
        local L = self.L
        self:paintHeader(bb, x, y)
        local pv = L.preview
        if not self.preview_bb then
            local pb = Blitbuffer.new(pv.w - 2, pv.h - 2, Blitbuffer.TYPE_BB8)
            pb:fill(Blitbuffer.COLOR_WHITE)
            local ok, place = pcall(P.paintPreview, pb, pv.w - 2, pv.h - 2)
            self.preview_place = ok and place or "home"
            self.preview_bb = pb
        end
        bb:blitFrom(self.preview_bb, x + pv.x + 1, y + pv.y + 1, 0, 0, pv.w - 2, pv.h - 2)
        bb:paintBorder(x + pv.x, y + pv.y, pv.w, pv.h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
        for _i, l in ipairs(self.labels) do
            W.text(bb, l.text, x + L.pad, y + l.y + S(2), 14, { bold = true, fg = Blitbuffer.gray(0.8) })
        end
        self:paintSpots(bb, x, y)
    end

    function Screen1:onCloseWidget()
        self:freeSpots()
        if self.preview_bb then self.preview_bb:free(); self.preview_bb = nil end
        P.open = nil
        P._books = nil
        Theme().defer(false)
        UIManager:setDirty(nil, "full")
        if self.on_done then pcall(self.on_done) end
    end

    P._ThemeScreen = Screen1
    return Screen1
end

--- The Which ornaments screen.
local function whichScreen()
    if P._WhichScreen then return P._WhichScreen end
    local Base = screenClass()
    local UIManager = require("ui/uimanager")
    local W = lazy()
    local Blitbuffer = W.Blitbuffer
    local Screen2 = Base:extend{ name = "gzreader which ornaments", page = 1 }

    function Screen2:build()
        self.title = _("Which ornaments")
        local Th = Theme()
        local L = P.whichLayout(self.dimen.w, self.dimen.h)
        self.L = L
        self.entries = Th.list()
        self.shown = self.shown or P.firstShown()
        self.spots, self.layout, self.labels = {}, {}, {}
        local pages, pg, first, last = P.pageOf(#self.entries, L.per, self.page)
        self.pages, self.page = pages, pg
        local row
        for i = first, last do
            local k = i - first
            local col, r = k % L.cols, math.floor(k / L.cols)
            if col == 0 then row = {}; self.layout[#self.layout + 1] = row end
            local x, y = L.pad + col * (L.tw + L.gap), L.grid_y + r * (L.ph + L.cap_h + L.gap)
            local e = self.entries[i]
            local spot
            if e then
                spot = W.Spot:new{ w = L.tw, h = L.ph + L.cap_h, ph = L.ph, label = e.label,
                    art = function(bb, w, h)
                        local tall = e.tall or Th.HEIGHT
                        P.paintShelf(bb, 0, S(2), w, h - S(2), { books = {}, orns = { { entry = e, side = "center",
                            scale = 0.82 / tall * (0.7 + 0.3 * tall) } } })
                    end,
                    callback = function() Th.setOn(e, not Th.isOn(e)); self.shown = e; self:changed() end,
                    hold_callback = function() self.shown = e; self:changed() end }
                spot.entry = e
            else
                spot = W.Spot:new{ w = L.tw, h = L.ph + L.cap_h, ph = L.ph, label = _("Your own…"),
                    art = function(bb, w, h)
                        local m = S(14)
                        local dash = S(6)
                        for dx = m, w - m, 2 * dash do
                            bb:paintRect(dx, m, math.min(dash, w - m - dx), math.max(2, S(2)), Blitbuffer.gray(0.6))
                            bb:paintRect(dx, h - m, math.min(dash, w - m - dx), math.max(2, S(2)), Blitbuffer.gray(0.6))
                        end
                        for dy = m, h - m, 2 * dash do
                            bb:paintRect(m, dy, math.max(2, S(2)), math.min(dash, h - m - dy), Blitbuffer.gray(0.6))
                            bb:paintRect(w - m, dy, math.max(2, S(2)), math.min(dash, h - m - dy), Blitbuffer.gray(0.6))
                        end
                        W.text(bb, "+", math.floor(w / 2), math.floor(h / 2) - S(20), 28, { align = "center", fg = Blitbuffer.gray(0.6) })
                    end,
                    callback = function() Th.showOwnFolder() end }
            end
            self:place(spot, x, y)
            row[#row + 1] = spot
        end
        self.reset = nil
        if P.seasonalByHand() then
            local rw = math.floor(L.sw / 2)
            self.reset = self:place(W.Spot:new{ kind = "chip", w = rw, h = S(30), label = _("Seasonal ones in their season again"),
                callback = function() Th.resetChosen(); self:changed() end }, L.sw - L.pad - rw, L.footer_y)
            self.layout[#self.layout + 1] = { self.reset }
        end
        self.key_events.NextPage = { { Device.input and Device.input.group and Device.input.group.PgFwd or "RPgFwd" } }
        self.key_events.PrevPage = { { Device.input and Device.input.group and Device.input.group.PgBack or "RPgBack" } }
        self:refreshValues()
    end

    function Screen2:refreshValues()
        local Th = Theme()
        for _i, p in ipairs(self.spots) do
            local e = p.spot.entry
            if e then
                p.spot.check = Th.isOn(e)
                p.spot.faded = not p.spot.check
                p.spot.tag = P.seasonTag(e)
                p.spot.on = e == self.shown
            end
        end
        if self.preview_bb then self.preview_bb:free(); self.preview_bb = nil end
    end

    function Screen2:turn(d)
        if self.pages <= 1 then return false end
        local pg = (self.page - 1 + d) % self.pages + 1
        self:freeSpots()
        for i = #self, 1, -1 do self[i] = nil end
        self.page = pg
        self:build()
        if Device:hasDPad() and self.layout[1] then self:moveFocusTo(1, 1) end
        UIManager:setDirty(self, "ui")
        return true
    end
    function Screen2:onNextPage() return self:turn(1) end
    function Screen2:onPrevPage() return self:turn(-1) end

    function Screen2:paintTo(bb, x, y)
        local L = self.L
        self:paintHeader(bb, x, y)
        W.text(bb, _("Tap one to put it on the shelves or take it off; hold one to see it."), x + L.pad, y + L.hint_y, 14,
            { fg = Blitbuffer.gray(0.7), max_width = L.sw - 2 * L.pad })
        local pv = L.preview
        if not self.preview_bb then
            local pb = Blitbuffer.new(pv.w - 2, pv.h - 2, Blitbuffer.TYPE_BB8)
            pb:fill(Blitbuffer.COLOR_WHITE)
            if self.shown then
                pcall(P.paintShelf, pb, 0, S(2), pv.w - 2, pv.h - 4, { books = P.books(), first = 3, keep = true,
                    orns = { { entry = self.shown, scale = 1.1 } } })
            end
            self.preview_bb = pb
        end
        bb:blitFrom(self.preview_bb, x + pv.x + 1, y + pv.y + 1, 0, 0, pv.w - 2, pv.h - 2)
        bb:paintBorder(x + pv.x, y + pv.y, pv.w, pv.h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
        if self.shown then
            local e = self.shown
            local cap = e.when and T(_("Preview: %1 on your shelf (%2)"), e.label, e.when) or T(_("Preview: %1 on your shelf"), e.label)
            W.text(bb, cap, x + L.pad, y + L.caption_y, 13, { fg = Blitbuffer.gray(0.75), max_width = L.sw - 2 * L.pad })
        end
        self:paintSpots(bb, x, y)
        if self.pages > 1 then
            W.text(bb, T(_("Page %1 of %2"), self.page, self.pages), x + L.pad, y + L.footer_y + S(4), 14, { fg = Blitbuffer.gray(0.7) })
        end
    end

    function Screen2:onCloseWidget()
        self:freeSpots()
        if self.preview_bb then self.preview_bb:free(); self.preview_bb = nil end
        if self.on_done then pcall(self.on_done) end
    end

    P._WhichScreen = Screen2
    return Screen2
end

---------------------------------------------------------------- showing

--- The Bookshelf theme screen; `on_done` after it closes.
function P.show(on_done)
    local UIManager = require("ui/uimanager")
    if P.open then UIManager:close(P.open) end
    Theme().defer(true)
    pcall(function() require("gzreader_log").info("shelf theme: the theme screen") end)
    local w = themeScreen():new{ on_done = on_done }
    P.open = w
    UIManager:show(w)
    return w
end

--- Which ornaments (over the theme screen); `on_done` after it closes.
function P.showWhich(on_done)
    local UIManager = require("ui/uimanager")
    local w = whichScreen():new{ on_done = on_done }
    UIManager:show(w)
    return w
end

return P
