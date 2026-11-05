--[[--
The players' pictures: a cassette walkman with headphones (audiobooks) and
a portable CD player with headphones (music), in greys for e-ink.

The bodies are drawings (icons/shelf/walkman_player.svg, cd_player.svg);
what changes is drawn over them:
- the walkman: the cassette in its window, its label hand-written with the
  book's title and chapter (and the cover), the tape moving from the left
  reel to the right one as the chapter plays, ▶ or ❚❚ and the counter;
- the CD player: the disc under the lid with the album's cover on it, and
  the track number and time on its little display.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local root = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"

local Deck = {}

local svg_cache = {}
local function body(name, w, h)
    local key = name .. w .. "x" .. h
    if svg_cache[key] then return svg_cache[key] end
    local ok, bb = pcall(function()
        return require("ui/renderimage"):renderSVGImageFile(root .. "/icons/shelf/" .. name .. ".svg", w, h)
    end)
    if not ok or not bb then return nil end
    for k, v in pairs(svg_cache) do v:free(); svg_cache[k] = nil end -- (one size at a time)
    svg_cache[key] = bb
    return bb
end

--- A font size for `px` pixels of the drawing's scale.
local function fs(px) return math.max(7, math.floor(px / Screen:scaleBySize(1) + 0.5)) end

local function hand(size)
    local ok, Sticky = pcall(require, "gzreader_sticky")
    if ok and Sticky.hand then return Sticky.hand(size) end
    return Font:getFace("cfont", size)
end

local function text(bb, str, face, x, y, max_w, color, bold)
    local t = TextWidget:new{ text = str or "", face = face, max_width = max_w, fgcolor = color, bold = bold }
    local s = t:getSize()
    t:paintTo(bb, x, y)
    t:free()
    return s
end

--- A picture scaled to fit w x h (kept: covers are small).
local scaled = {}
local function fit(src, w, h)
    if not src then return nil end
    local key = tostring(src) .. w .. "x" .. h
    if scaled.key == key then return scaled.bb end
    if scaled.bb then scaled.bb:free() end
    local k = math.min(w / src:getWidth(), h / src:getHeight())
    local ok, bb = pcall(function()
        return require("ui/renderimage"):scaleBlitBuffer(src, math.max(1, math.floor(src:getWidth() * k)),
            math.max(1, math.floor(src:getHeight() * k)), false)
    end)
    scaled.key, scaled.bb = key, ok and bb or nil
    return scaled.bb
end

local function triangle(bb, x, y, h, color)
    for i = 0, h - 1 do
        local half = math.abs(i - (h - 1) / 2)
        local w = math.floor(((h - 1) / 2 - half) * 1.7) + 1
        bb:paintRect(x, y + i, w, 1, color)
    end
end

---------------------------------------------------------------- the walkman

--- state = { title, line2, progress (0-1: the chapter), playing, cover_bb, counter }
local Walkman = WidgetContainer:extend{ w = 300, state = nil }
Deck.Walkman = Walkman

function Walkman:getSize() return Geom:new{ w = self.w, h = math.floor(self.w * 300 / 320) } end

function Walkman:paintTo(bb, x, y)
    local w = self.w
    local h = math.floor(w * 300 / 320)
    self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
    local k = w / 320
    local function R(v) return math.floor(v * k + 0.5) end
    local img = body("walkman_player", w, h)
    if img then bb:alphablitFrom(img, x, y, 0, 0, img:getWidth(), img:getHeight()) end
    local st = self.state or {}
    -- the cassette
    local cx, cy, cw, ch = x + R(36), y + R(76), R(128), R(88)
    bb:paintRect(cx, cy, cw, ch, Blitbuffer.gray(0.16))
    bb:paintBorder(cx, cy, cw, ch, 1, Blitbuffer.gray(0.6))
    for _i, sx in ipairs({ cx + R(5), cx + cw - R(5) }) do
        for _j, sy in ipairs({ cy + R(5), cy + ch - R(5) }) do bb:paintCircle(sx, sy, math.max(1, R(2)), Blitbuffer.gray(0.6)) end
    end
    -- its label: the cover, the title and the chapter, written by hand
    local lx, ly, lw, lh = cx + R(6), cy + R(5), cw - R(12), R(38)
    bb:paintRect(lx, ly, lw, lh, Blitbuffer.COLOR_WHITE)
    bb:paintRect(lx, ly + math.floor(lh * 0.55), lw, 1, Blitbuffer.gray(0.25))
    bb:paintRect(lx, ly + lh - R(4), lw, math.max(1, R(3)), Blitbuffer.gray(0.45))
    local tx = lx + R(4)
    local cover = fit(st.cover_bb, R(26), lh - R(8))
    if cover then
        bb:blitFrom(cover, lx + R(3), ly + R(2), 0, 0, cover:getWidth(), cover:getHeight())
        tx = lx + R(3) + cover:getWidth() + R(4)
    end
    text(bb, st.title, hand(fs(R(15))), tx, ly - R(1), lx + lw - tx - R(2), Blitbuffer.COLOR_BLACK)
    text(bb, st.line2, hand(fs(R(11))), tx, ly + math.floor(lh * 0.55) - R(1), lx + lw - tx - R(2), Blitbuffer.gray(0.75))
    -- the tape window and the reels: the tape goes from left to right as the chapter plays
    local wx, wy, ww, wh = cx + R(30), cy + R(48), R(68), R(32)
    bb:paintRect(wx, wy, ww, wh, Blitbuffer.gray(0.45))
    bb:paintBorder(wx, wy, ww, wh, 1, Blitbuffer.gray(0.85))
    local p = math.max(0, math.min(1, tonumber(st.progress) or 0))
    local rcy = wy + math.floor(wh / 2)
    for i, rx in ipairs({ wx + R(16), wx + ww - R(16) }) do
        local frac = i == 1 and (1 - p) or p
        bb:paintCircle(rx, rcy, R(6) + math.floor(R(9) * frac), Blitbuffer.gray(0.82))
        bb:paintCircle(rx, rcy, R(5), Blitbuffer.gray(0.08))
        for a = 0, 5 do
            local ang = a * math.pi / 3
            bb:paintRect(rx + math.floor(math.cos(ang) * R(3)), rcy + math.floor(math.sin(ang) * R(3)), math.max(1, R(1.5)), math.max(1, R(1.5)), Blitbuffer.gray(0.7))
        end
        bb:paintCircle(rx, rcy, math.max(1, R(1.5)), Blitbuffer.gray(0.9))
    end
    -- the panel under the window: ▶ or ❚❚, and the counter
    local px, py, ph = x + R(44), y + R(194), R(38)
    if st.playing then
        triangle(bb, px, py, ph, Blitbuffer.gray(0.06))
    else
        bb:paintRect(px, py, R(12), ph, Blitbuffer.gray(0.06))
        bb:paintRect(px + R(20), py, R(12), ph, Blitbuffer.gray(0.06))
    end
    if st.counter then
        local digits = tostring(st.counter)
        local dw, dh = R(17), R(26)
        local n = #digits
        local bx = x + R(158) - n * (dw + R(2)) - R(4)
        local by = y + R(200)
        bb:paintRect(bx - R(3), by - R(3), n * (dw + R(2)) + R(4), dh + R(6), Blitbuffer.gray(0.9))
        for i = 1, n do
            local dx = bx + (i - 1) * (dw + R(2))
            bb:paintRect(dx, by, dw, dh, Blitbuffer.COLOR_WHITE)
            bb:paintRect(dx, by + math.floor(dh / 2), dw, 1, Blitbuffer.gray(0.3))
            local face = Font:getFace("cfont", fs(R(17)))
            local t = TextWidget:new{ text = digits:sub(i, i), face = face, bold = true }
            local s = t:getSize()
            t:paintTo(bb, dx + math.floor((dw - s.w) / 2), by + math.floor((dh - s.h) / 2))
            t:free()
        end
    end
end

---------------------------------------------------------------- the CD player

--- state = { cover_bb, track (number), time (text), playing }
local CD = WidgetContainer:extend{ w = 300, state = nil }
Deck.CD = CD

function CD:getSize() return Geom:new{ w = self.w, h = math.floor(self.w * 300 / 360) } end

function CD:paintTo(bb, x, y)
    local w = self.w
    local h = math.floor(w * 300 / 360)
    self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
    local k = w / 360
    local function R(v) return math.floor(v * k + 0.5) end
    local img = body("cd_player", w, h)
    if img then bb:alphablitFrom(img, x, y, 0, 0, img:getWidth(), img:getHeight()) end
    local st = self.state or {}
    -- the disc, seen through the lid
    local dx, dy = x + R(180), y + R(126)
    bb:paintCircle(dx, dy, R(78), Blitbuffer.gray(0.12))
    for _i, r in ipairs({ 72, 64, 56 }) do bb:paintCircle(dx, dy, R(r), Blitbuffer.gray(0.3), 1) end
    for i = 0, R(30) do -- (a shine)
        local a = math.pi * (1.1 + i / R(30) * 0.35)
        bb:paintRect(dx + math.floor(math.cos(a) * R(66)), dy + math.floor(math.sin(a) * R(66)), math.max(1, R(3)), math.max(1, R(3)), Blitbuffer.COLOR_WHITE)
    end
    -- the label: the album's cover, round
    local rl = R(44)
    bb:paintCircle(dx, dy, rl, Blitbuffer.gray(0.4))
    local cover = fit(st.cover_bb, 2 * rl, 2 * rl)
    if cover then
        local cw, ch = cover:getWidth(), cover:getHeight()
        for row = -rl, rl - 1 do
            local half = math.floor(math.sqrt(math.max(0, rl * rl - (row + 0.5) ^ 2)))
            local sy = row + math.floor(ch / 2)
            if half > 0 and sy >= 0 and sy < ch then
                local sx = math.floor(cw / 2) - half
                local ox = math.max(0, sx)
                bb:blitFrom(cover, dx - half + (ox - sx), dy + row, ox, sy, math.min(2 * half, cw - ox), 1)
            end
        end
    end
    bb:paintCircle(dx, dy, R(10), Blitbuffer.gray(0.08))
    bb:paintCircle(dx, dy, R(10), Blitbuffer.gray(0.5), 1)
    bb:paintCircle(dx, dy, R(4), Blitbuffer.gray(0.85))
    -- the display: ▶ / ❚❚, the track, the time
    local lx, ly, lw, lh = x + R(146), y + R(226), R(68), R(22)
    local mark = R(9)
    if st.playing then triangle(bb, lx + R(4), ly + math.floor((lh - mark) / 2), mark, Blitbuffer.gray(0.9))
    else
        bb:paintRect(lx + R(4), ly + math.floor((lh - mark) / 2), R(3), mark, Blitbuffer.gray(0.9))
        bb:paintRect(lx + R(9), ly + math.floor((lh - mark) / 2), R(3), mark, Blitbuffer.gray(0.9))
    end
    local face = Font:getFace("cfont", fs(R(13)))
    text(bb, st.track and string.format("%02d", st.track) or "--", face, lx + R(16), ly + R(2), R(20), Blitbuffer.gray(0.9), true)
    local t = TextWidget:new{ text = st.time or "", face = face, bold = true, fgcolor = Blitbuffer.gray(0.9) }
    local ts = t:getSize()
    t:paintTo(bb, lx + lw - ts.w - R(3), ly + math.floor((lh - ts.h) / 2))
    t:free()
end

function Deck.freeAll()
    for k, v in pairs(svg_cache) do v:free(); svg_cache[k] = nil end
    if scaled.bb then scaled.bb:free(); scaled.bb, scaled.key = nil, nil end
end

return Deck
