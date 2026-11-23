-- GZreader: emoji in colour on a colour screen (Kindle Colorsoft, Scribe
-- Colorsoft, colour Kobos).
--
-- Emoji come from OpenMoji's black font, the last of KOReader's fallback fonts
-- (frontend/ui/font.lua: Font.EMOJI_FALLBACK): text is laid out with it on
-- every device, and a grey screen draws its black emoji. KOReader can't draw
-- colour fonts, but OpenMoji's colour font (COLR version 0) is made of plain
-- outline glyphs in layers, each with a palette colour, and its emoji have the
-- same glyph numbers as the black font's. So on a colour screen, where KOReader
-- would draw a glyph of the black font, this draws the colour font's layers for
-- that glyph number instead, each in its colour (each layer an ordinary glyph,
-- through RenderText's cache). Called from RenderText:renderUtf8Text and
-- TextBoxWidget (the two places KOReader draws text).
--
-- The fonts: plugins/gzreader.koplugin/fonts/, OpenMoji (CC BY-SA 4.0), see
-- plugins/gzreader.koplugin/THIRD_PARTY_NOTICES.md.

local M = {
    FILE = "plugins/gzreader.koplugin/fonts/OpenMoji-color-glyf_colr_0.ttf",
}

local tables -- false: the colour font couldn't be read
local base_cache = {} -- gid -> list of { gid, colour } (false: not a colour glyph)
local char_cache = {} -- charcode -> black font gid, or false

local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a * 256 + b end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return ((a * 256 + b) * 256 + c) * 256 + d end

--- The font's COLR, CPAL and cmap tables (as strings), read once.
--- `data` (tests): the font file's bytes.
function M.load(data)
    if tables ~= nil and not data then return tables or nil end
    tables = false
    if not data then
        local f = io.open(M.FILE, "rb")
        if not f then return nil end
        data = f:read("*a")
        f:close()
    end
    if not data or #data < 12 then return nil end
    local t = {}
    for i = 0, u16(data, 4) - 1 do
        local rec = 12 + i * 16
        local tag = data:sub(rec + 1, rec + 4)
        if tag == "COLR" or tag == "CPAL" or tag == "cmap" then
            local off, len = u32(data, rec + 8), u32(data, rec + 12)
            t[tag] = data:sub(off + 1, off + len)
        end
    end
    if not (t.COLR and t.CPAL and t.cmap) or u16(t.COLR, 0) ~= 0 then return nil end
    tables = t
    return t
end

--- Forget what was read (tests).
function M.reset() tables, base_cache, char_cache = nil, {}, {} end

--- The palette's colour `i` (palette 0) as r, g, b, a; nil for the text's own colour.
local function paletteColour(t, i)
    if i == 0xFFFF then return nil end
    local cpal = t.CPAL
    if i >= u16(cpal, 2) then return nil end
    local records = u32(cpal, 8)
    local first = u16(cpal, 12) -- (palette 0's first colour record)
    local o = records + (first + i) * 4
    local b, g, r, a = cpal:byte(o + 1, o + 4)
    return r, g, b, a
end

--- The colour layers of glyph `gid`: { { gid, r, g, b, a } … }, or nil when
--- it isn't a colour glyph.
function M.layers(gid)
    local cached = base_cache[gid]
    if cached ~= nil then return cached or nil end
    local t = M.load()
    base_cache[gid] = false
    if not t then return nil end
    local colr = t.COLR
    local n_base, base_off, layer_off = u16(colr, 2), u32(colr, 4), u32(colr, 8)
    -- (the base records are sorted by glyph number)
    local lo, hi = 0, n_base - 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local o = base_off + mid * 6
        local g = u16(colr, o)
        if g == gid then
            local first, count = u16(colr, o + 2), u16(colr, o + 4)
            local list = {}
            for k = 0, count - 1 do
                local lo2 = layer_off + (first + k) * 4
                local r, gg, b, a = paletteColour(t, u16(colr, lo2 + 2))
                list[#list + 1] = { gid = u16(colr, lo2), r = r, g = gg, b = b, a = a }
            end
            base_cache[gid] = list
            return list
        elseif g < gid then lo = mid + 1 else hi = mid - 1 end
    end
    return nil
end

--- The glyph number of `charcode` (the colour and black fonts share them), or nil.
function M.glyphOf(charcode)
    local cached = char_cache[charcode]
    if cached ~= nil then return cached or nil end
    char_cache[charcode] = false
    local t = M.load()
    if not t then return nil end
    local cmap = t.cmap
    for i = 0, u16(cmap, 2) - 1 do
        local sub = u32(cmap, 4 + i * 8 + 4)
        if u16(cmap, sub) == 12 then -- (segmented coverage: every emoji, above U+FFFF too)
            local ngroups = u32(cmap, sub + 12)
            local lo, hi = 0, ngroups - 1
            while lo <= hi do
                local mid = math.floor((lo + hi) / 2)
                local o = sub + 16 + mid * 12
                local s, e = u32(cmap, o), u32(cmap, o + 4)
                if charcode < s then hi = mid - 1
                elseif charcode > e then lo = mid + 1
                else
                    local gid = u32(cmap, o + 8) + (charcode - s)
                    char_cache[charcode] = gid
                    return gid
                end
            end
            return nil
        end
    end
    return nil
end

--- Whether emoji are drawn in colour now: a colour screen with colour
--- rendering on, and the colour font there.
function M.on()
    local ok, Screen = pcall(function() return require("device").screen end)
    if not ok or not Screen or not Screen.isColorEnabled or not Screen:isColorEnabled() then return false end
    return M.load() ~= nil
end

--- Whether text `text` may hold an emoji to draw in colour (a character
--- above U+FFFF, where the emoji are), on a colour screen: TextBoxWidget then
--- draws into a colour canvas.
function M.wanted(text)
    return type(text) == "string" and text:find("[\240-\244]") ~= nil and M.on()
end

--- Whether `face` is the black emoji font (the fallback emoji come from).
local FontModule -- (ui/font, once it's loaded: it loads this module's callers)
function M.isEmojiFace(face)
    if face == nil then return false end
    FontModule = FontModule or package.loaded["ui/font"] or require("ui/font")
    local name = FontModule.EMOJI_FALLBACK
    return name ~= nil and face.realname == name
end

--- The colour font at `face`'s size.
local function colourFace(face)
    local Font = require("ui/font")
    local name = Font.EMOJI_FALLBACK and Font.EMOJI_FALLBACK:gsub("OpenMoji%-black%-glyf%.ttf$", "OpenMoji-color-glyf_colr_0.ttf")
    return name and Font:getFace(name, face.orig_size)
end

--- Draws glyph `gid` of the black emoji font `face` in colour into `bb`,
--- its origin at `x`, `baseline` (`fgcolor` for layers in the text's colour).
--- Returns true when drawn (false: draw the glyph as usual).
function M.drawGlyph(bb, face, gid, x, baseline, fgcolor)
    if not M.isEmojiFace(face) or not M.on() then return false end
    local list = M.layers(gid)
    if not list then return false end
    local cf = colourFace(face)
    if not cf then return false end
    local Blitbuffer = require("ffi/blitbuffer")
    local RenderText = require("ui/rendertext")
    for _i, l in ipairs(list) do
        local g = RenderText:getGlyphByIndex(cf, l.gid)
        if g and g.bb then
            local colour = l.r and Blitbuffer.ColorRGB32(l.r, l.g, l.b, l.a or 0xFF) or fgcolor
            local w, h = g.bb:getWidth(), g.bb:getHeight()
            if colour and colour.r then
                bb:colorblitFromRGB32(g.bb, x + g.l, baseline - g.t, 0, 0, w, h, colour)
            else
                bb:colorblitFrom(g.bb, x + g.l, baseline - g.t, 0, 0, w, h, colour or Blitbuffer.COLOR_BLACK)
            end
        end
    end
    return true
end

--- The same for `charcode` drawn with `face` (RenderText's path: no glyph
--- numbers there). True when drawn in colour.
function M.drawChar(bb, face, charcode, x, baseline, fgcolor)
    if charcode < 0x2000 or not M.on() or face.ftsize:hasGlyph(charcode) then return false end
    local Font = require("ui/font")
    -- (the first fallback that has it, as RenderText:getGlyph picks: an emoji
    -- FreeSans also has, ❤ or ☺, stays FreeSans's)
    for _i, name in ipairs(Font.fallbacks) do
        local fb = Font:getFace(name, face.orig_size)
        if fb and fb.ftsize:hasGlyph(charcode) then
            if not M.isEmojiFace(fb) then return false end
            local gid = M.glyphOf(charcode)
            return gid ~= nil and M.drawGlyph(bb, fb, gid, x, baseline, fgcolor)
        end
    end
    return false
end

return M
