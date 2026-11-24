--[[--
Music Assistant's lists in the Bookshelf view (the other views keep the
plain list, gzreader_house.lua's musicShow): what Choose music shows, as
the things themselves on shelves.

- a radio station: a transistor radio;
- a playlist: a cassette;
- an album: a record half out of its sleeve;
- an artist: a record; a song: a single (the big hole);
- More…: a card with three dots.

Under each its name and, where there is one, who it's by (a search: what
kind of thing it is). A tap, Press or its letter plays it, as the list's
row did.

The list stays the Menu's: its title bar, its pages and its letters. Only
how a page is drawn changes, and how many things a page holds
(`items_per_page`: what fits on the shelves). The drawings are made here
(SVG) and rendered and kept by gzreader_houseview.lua, as the wall's are.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local Music = {
    ART = "v1",     -- (part of a drawing's name: change it when a drawing changes)
    VB_W = 200,     -- a drawing's own size
    VB_H = 160,
    CELL = 125,     -- the narrowest a thing's place may be
}

local function Shop() return require("gzreader_bookshop") end
local function View() return require("gzreader_houseview") end
local function Panel() return require("gzreader_housepanel") end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------- the drawings

local INK, SHADE = "#1a1a1a", "#b5b5b5"
local function f(fmt, ...) return string.format(fmt, ...) end
local function rect(x, y, w, h, rx, fill, stroke, sw)
    return f('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"%s/>', x, y, w, h, rx or 0, fill or "none",
        stroke and f(' stroke="%s" stroke-width="%s"', stroke, sw or 3) or "")
end
local function circle(cx, cy, r, fill, stroke, sw)
    return f('<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>', cx, cy, r, fill or "none",
        stroke and f(' stroke="%s" stroke-width="%s"', stroke, sw or 3) or "")
end
local function line(x1, y1, x2, y2, stroke, sw)
    return f('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s" stroke-linecap="round"/>', x1, y1, x2, y2, stroke, sw or 2)
end
local function path(d, stroke, sw, fill)
    return f('<path d="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>', d, fill or "none", stroke, sw or 3)
end
local function wrap(body)
    return f('<?xml version="1.0" encoding="utf-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="%dpx" height="%dpx" viewBox="0 0 %d %d">%s</svg>\n',
        Music.VB_W, Music.VB_H, Music.VB_W, Music.VB_H, body)
end

local Draw = {}

--- A transistor radio (a station).
function Draw.radio()
    local s = line(150, 36, 186, 8, INK, 3) .. circle(186, 8, 4, INK)
        .. path("M56 36 Q100 6 144 36", INK, 4)
        .. rect(24, 40, 164, 108, 12, SHADE) .. rect(16, 32, 164, 108, 12, "#f3f3f3", INK, 3)
        .. circle(62, 92, 34, "#dcdcdc", INK, 3) .. circle(62, 92, 24, "none", "#7a7a7a", 2) .. circle(62, 92, 14, "none", "#7a7a7a", 2) .. circle(62, 92, 5, INK)
        .. rect(108, 48, 60, 26, 3, "#ffffff", INK, 2.5)
    for x = 114, 162, 8 do s = s .. line(x, 53, x, 60, INK, 2) end
    s = s .. line(140, 51, 140, 71, INK, 3)
        .. circle(120, 110, 12, "#ffffff", INK, 2.5) .. line(120, 110, 126, 102, INK, 2.5)
        .. circle(156, 110, 12, "#ffffff", INK, 2.5) .. line(156, 110, 150, 102, INK, 2.5)
    return wrap(s)
end

--- A cassette (a playlist).
function Draw.cassette()
    local s = rect(14, 28, 180, 116, 8, SHADE) .. rect(6, 20, 180, 116, 8, "#e9e9e9", INK, 3)
        .. rect(18, 30, 156, 64, 4, "#ffffff", INK, 2)
        .. line(28, 41, 164, 41, "#9a9a9a", 2) .. line(28, 51, 164, 51, "#9a9a9a", 2)
        .. rect(54, 60, 84, 26, 13, "#3a3a3a", INK, 2)
        .. circle(72, 73, 8, "#ffffff", INK, 2) .. circle(120, 73, 8, "#ffffff", INK, 2)
        .. f('<polygon points="44,136 52,104 140,104 148,136" fill="#d0d0d0" stroke="%s" stroke-width="2.5" stroke-linejoin="round"/>', INK)
        .. circle(78, 122, 4, "#ffffff", INK, 2) .. circle(114, 122, 4, "#ffffff", INK, 2)
        .. circle(18, 126, 3, INK) .. circle(174, 126, 3, INK)
    return wrap(s)
end

--- A record half out of its sleeve (an album).
function Draw.sleeve()
    local s = circle(130, 84, 58, "#2b2b2b", INK, 3) .. circle(130, 84, 44, "none", "#6a6a6a", 1.5) .. circle(130, 84, 32, "none", "#6a6a6a", 1.5)
        .. circle(130, 84, 16, "#ffffff", INK, 2) .. circle(130, 84, 3, INK)
        .. rect(22, 30, 116, 116, 0, SHADE) .. rect(14, 22, 116, 116, 0, "#f6f6f6", INK, 3)
        .. f('<polygon points="16,104 128,48 128,72 16,128" fill="#dcdcdc"/>')
        .. circle(72, 80, 30, "none", "#9a9a9a", 2) .. circle(72, 80, 6, "#9a9a9a")
        .. rect(14, 22, 116, 116, 0, "none", INK, 3)
    return wrap(s)
end

--- A record (an artist), or a single with its big hole (a song).
function Draw.disc(single)
    local s = circle(106, 86, 70, SHADE) .. circle(100, 80, 70, "#2b2b2b", INK, 3)
        .. circle(100, 80, 58, "none", "#6a6a6a", 1.5) .. circle(100, 80, 46, "none", "#6a6a6a", 1.5)
        .. path("M50 52 A58 58 0 0 1 80 26", "#9a9a9a", 3)
    if single then
        s = s .. circle(100, 80, 32, "#ffffff", INK, 2) .. circle(100, 80, 13, "#2b2b2b", INK, 2)
    else
        s = s .. circle(100, 80, 24, "#ffffff", INK, 2) .. circle(100, 80, 15, "none", "#9a9a9a", 1.5) .. circle(100, 80, 4, INK)
    end
    return wrap(s)
end

--- A card with three dots (More…).
function Draw.more()
    local s = rect(46, 40, 124, 88, 8, SHADE) .. rect(38, 32, 124, 88, 8, "#ffffff", INK, 3)
        .. circle(76, 76, 8, INK) .. circle(100, 76, 8, INK) .. circle(124, 76, 8, INK)
    return wrap(s)
end

Music.Draw = Draw

--- What a row of the list is drawn as: "radio", "cassette", "sleeve",
--- "disc", "single", "more", or "note" (a message: no drawing).
function Music.kindOf(row)
    if type(row) ~= "table" then return "note" end
    if row.gz_music_more then return "more" end
    if not row.gz_music_uri then return "note" end
    local k = row.gz_music_kind
    if k == "radio" then return "radio" end
    if k == "playlist" then return "cassette" end
    if k == "album" then return "sleeve" end
    if k == "track" then return "single" end
    return "disc"
end

--- The drawing for a kind: { key, svg }, or nil for a note.
function Music.art(kind)
    local make = { radio = Draw.radio, cassette = Draw.cassette, sleeve = Draw.sleeve, more = Draw.more,
        disc = function() return Draw.disc(false) end, single = function() return Draw.disc(true) end }
    if not make[kind] then return nil end
    return { key = "music-" .. Music.ART .. "-" .. kind, svg = make[kind] }
end

---------------------------------------------------------------- where things go

--- The shelves of a w x h page: { cols, rows, per (things a page), cells =
--- { { x, y, w, h } }, art_w, art_h, shelves = { y } }. Pure: tested in
--- run_tests.lua.
function Music.grid(w, h, s)
    s = s or S
    local pad, gap = s(16), s(8)
    local cols = clamp(math.floor((w - 2 * pad + gap) / (s(Music.CELL) + gap)), 2, 8)
    local cw = math.floor((w - 2 * pad - (cols - 1) * gap) / cols)
    local art_w = cw - s(20)
    local art_h = math.floor(art_w * Music.VB_H / Music.VB_W)
    local cap_h = s(44)
    local shelf_h = s(10)
    local row_h = s(6) + art_h + shelf_h + cap_h + s(6)
    local rows = math.floor((h - s(4)) / row_h)
    local G = { cols = cols, rows = rows, per = cols * math.max(rows, 0), cells = {}, shelves = {}, art_w = art_w, art_h = art_h,
        cap_h = cap_h, shelf_h = shelf_h, w = w, h = h }
    for r = 0, rows - 1 do
        local y = s(4) + r * row_h
        G.shelves[#G.shelves + 1] = y + s(6) + art_h
        for c = 0, cols - 1 do
            G.cells[#G.cells + 1] = { x = pad + c * (cw + gap), y = y, w = cw, h = row_h }
        end
    end
    return G
end

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }
function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

local function words(bb, str, sizes, bold, cx, y, max_w, color)
    if not str or str == "" then return 0 end
    local TextWidget = require("ui/widget/textwidget")
    local tw
    for k, size in ipairs(sizes) do
        if tw then tw:free() end
        tw = TextWidget:new{ text = str, face = Font:getFace("cfont", size), bold = bold, fgcolor = color, max_width = max_w }
        if not tw:isTruncated() or k == #sizes then break end
    end
    local sz = tw:getSize()
    tw:paintTo(bb, cx - math.floor(sz.w / 2), y)
    tw:free()
    return sz.h
end

function Page:paintTo(bb, x, y)
    local D = Shop().draw
    local G = self.G
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    D.wall(bb, x, y, self.w, self.h)
    -- the shelves the things stand on
    for _i, sy in ipairs(G.shelves) do
        bb:paintRect(x, y + sy + G.shelf_h, self.w, math.max(1, S(3)), D.gray(0.3))
        bb:paintRect(x, y + sy, self.w, G.shelf_h, D.gray(0.12))
        bb:paintRect(x, y + sy, self.w, math.max(1, S(2)), Blitbuffer.COLOR_BLACK)
        bb:paintRect(x, y + sy + G.shelf_h - math.max(1, S(1)), self.w, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    end
    for _i, pl in ipairs(self.places) do
        local c = pl.cell
        local cx = x + c.x + math.floor(c.w / 2)
        local ay = y + c.y + S(6)
        local fit = Music.art(pl.kind)
        if fit then
            local img = View().artImage(fit, G.art_w, G.art_h)
            if img then bb:alphablitFrom(img, cx - math.floor(img:getWidth() / 2), ay + G.art_h - img:getHeight(), 0, 0, img:getWidth(), img:getHeight()) end
            local ty = ay + G.art_h + G.shelf_h + S(3)
            local hgt = words(bb, pl.entry.text, { 14, 13, 12 }, true, cx, ty, c.w - S(4))
            words(bb, pl.entry.mandatory, { 12 }, false, cx, ty + hgt, c.w - S(4), D.gray(0.8))
        else
            -- a message: its words where a thing would stand
            words(bb, pl.entry.text, { 14, 13, 12 }, false, x + math.floor(self.w / 2), ay + math.floor(G.art_h / 2), self.w - S(40), D.gray(0.8))
        end
        if pl.letter and pl.hot then D.badge(bb, self.menu, pl.letter, x + c.x, y + c.y + S(2), S(20)) end
        if pl.hot then
            pl.hot.dimen = Geom:new{ x = x + c.x, y = y + c.y, w = c.w, h = c.h }
            if pl.hot.focused then D.focusRing(bb, { x = x + c.x + S(4), y = y + c.y + S(4), w = c.w - S(8), h = c.h - S(8) }) end
        end
    end
end

Music.Page = Page

--- What's on the Menu's page now: each row with its place and its kind.
function Music.fill(m, G)
    local out = {}
    local first = ((m.page or 1) - 1) * m.perpage
    for i = 1, m.perpage do
        local entry = m.item_table[first + i]
        if not entry then break end
        out[#out + 1] = { entry = entry, cell = G.cells[i], kind = Music.kindOf(entry), idx = first + i,
            acts = type(entry.callback) == "function" and entry.select_enabled ~= false,
            letter = m.is_enable_shortcut and m.item_shortcuts and m.item_shortcuts[i] or nil }
    end
    return out
end

--- Draw the page of `m` (one of Music Assistant's lists) as shelves.
--- False: nothing fits (the list instead).
function Music.build(m, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    m:_recalculateDimen(no_recalculate_dimen)
    local W, H = m.item_dimen.w, m.available_height
    local G = Music.grid(W, H)
    if G.per < 1 then return false end
    if m.items_per_page ~= G.per then
        -- (a page holds what the shelves do: the Menu's pages and letters follow)
        m.items_per_page = G.per
        m:_recalculateDimen()
    end
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    local Hot = Shop().Hot
    local page = Page:new{ w = W, h = H, G = G, menu = m }
    page.places = Music.fill(m, G)
    local rows, row_y = {}, nil
    for _i, pl in ipairs(page.places) do
        if pl.acts then
            pl.entry.idx = pl.idx
            pl.hot = Hot:new{ menu = m, entry = pl.entry, shop = page }
            page[#page + 1] = pl.hot
            if pl.cell.y ~= row_y then
                rows[#rows + 1] = {}
                row_y = pl.cell.y
            end
            table.insert(rows[#rows], pl.hot)
        end
    end
    for _i, r in ipairs(rows) do m.layout[#m.layout + 1] = r end
    table.insert(m.item_group, page)
    m._gz_music = page
    m:updatePageInfo(select_number or 1)
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    return true
end

--- Take over one of Music Assistant's lists in the Bookshelf view.
function Music.apply(m)
    if not m or m._gz_music_applied or type(m.updateItems) ~= "function" then return end
    m._gz_music_applied = true
    local orig_update = m.updateItems
    local own_per = m.items_per_page
    m.updateItems = function(menu, select_number, no_recalculate_dimen)
        if not menu._gz_music_failed and Panel().wanted() then
            local ok, res = pcall(Music.build, menu, select_number, no_recalculate_dimen)
            if ok and res ~= false then return end
            if not ok then
                require("gzreader_log").warn("house music shelves:", tostring(res))
                menu._gz_music_failed = true
            end
        end
        menu._gz_music = nil
        menu.items_per_page = own_per
        return orig_update(menu, select_number, no_recalculate_dimen)
    end
    if Panel().wanted() then pcall(m.updateItems, m) end
end

return Music
