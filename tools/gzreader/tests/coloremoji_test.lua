-- Emoji (OpenMoji): the black font as KOReader's last fallback, and
-- frontend/gzcoloremoji.lua drawing the colour font's layers on a colour
-- screen. Expected glyph numbers and colours are fontTools' reading of the
-- same font.
--   luajit coloremoji_test.lua <repo>   (from tools/gzreader/tests)
local REPO = arg[1] or "../../.."
package.path = REPO .. "/frontend/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. what) end
end
local function read(p) local f = assert(io.open(REPO .. "/" .. p, "rb")); local s = f:read("*a"); f:close(); return s end

-- ------------------------------------------------------------ stubs
local colour_screen = true
local drawn = {}
local Font = {
    EMOJI_FALLBACK = "../plugins/gzreader.koplugin/fonts/OpenMoji-black-glyf.ttf",
    fallbacks = { "NotoSans-Regular.ttf", "freefont/FreeSans.ttf", "../plugins/gzreader.koplugin/fonts/OpenMoji-black-glyf.ttf" },
}
local has = { -- what each fallback has
    ["NotoSans-Regular.ttf"] = {},
    ["freefont/FreeSans.ttf"] = { [0x2764] = true },
    [Font.EMOJI_FALLBACK] = { [0x2764] = true, [0x1F600] = true, [0x1F4DA] = true },
}
local function face(name, size)
    return { realname = name, orig_size = size, ftsize = { hasGlyph = function(_s, c) return (has[name] or {})[c] == true end } }
end
function Font:getFace(name, size) return face(name, size) end
package.loaded["ui/font"] = Font
package.loaded["device"] = { screen = { isColorEnabled = function() return colour_screen end } }
package.loaded["ffi/blitbuffer"] = {
    ColorRGB32 = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    COLOR_BLACK = { black = true },
}
package.loaded["ui/rendertext"] = {
    getGlyphByIndex = function(_s, f, gid)
        return { l = 1, t = 10, bb = { getWidth = function() return 4 end, getHeight = function() return 5 end, face = f, gid = gid } }
    end,
}
local bb = {
    colorblitFromRGB32 = function(_s, g, x, y, _sx, _sy, _w, _h, c) drawn[#drawn + 1] = { gid = g.gid, x = x, y = y, c = c, font = g.face.realname } end,
    colorblitFrom = function(_s, g, x, y, _sx, _sy, _w, _h, c) drawn[#drawn + 1] = { gid = g.gid, x = x, y = y, c = c, grey = true } end,
}

local E = require("gzcoloremoji")
E.FILE = REPO .. "/plugins/gzreader.koplugin/fonts/OpenMoji-color-glyf_colr_0.ttf"

-- ------------------------------------------------------------ reading the colour font
check(E.load() ~= nil, "the colour font's COLR, CPAL and cmap are read")
check(E.glyphOf(0x1F600) == 2222 and E.glyphOf(0x1F4DA) == 2007 and E.glyphOf(0x1F44D) == 944,
    "glyph numbers from its cmap (😀 2222, 📚 2007, 👍 944): " .. tostring(E.glyphOf(0x1F600)))
check(E.glyphOf(0x41) == nil, "a letter isn't in it")
local L = E.layers(2222)
check(L and #L == 8 and L[1].gid == 23029 and L[1].r == 0xFC and L[1].g == 0xEA and L[1].b == 0x2B and L[1].a == 0xFF
    and L[8].gid == 23032 and L[8].r == 0 and L[8].g == 0 and L[8].b == 0,
    "😀: 8 layers, yellow first (#FCEA2B), its black outline last")
local B = E.layers(2007)
check(B and #B == 10 and B[1].gid == 21417 and B[1].r == 0xFF and B[1].g == 0xFF and B[1].b == 0xFF, "📚: 10 layers, white first")
check(E.layers(5) == nil, "a glyph that isn't an emoji has no layers")
-- (only those three tables are read from the file, not its 2.8 MB)
local from_file = E.load()
local whole = read("plugins/gzreader.koplugin/fonts/OpenMoji-color-glyf_colr_0.ttf")
local from_bytes = E.load(whole)
check(from_file and from_bytes and #from_file.COLR == 281192 and #from_file.CPAL == 162 and #from_file.cmap == 5800
    and from_file.COLR == from_bytes.COLR and from_file.CPAL == from_bytes.CPAL and from_file.cmap == from_bytes.cmap,
    "the tables read from the file (seeking to each) are the same as from the whole file's bytes")
check(E.load(whole:sub(1, 100000)) == nil and E.load("") == nil, "a cut-short font file isn't read (no colour)")
E.reset()
check(E.load() ~= nil and E.glyphOf(0x1F600) == 2222, "…and read again after a reset")
whole = nil

-- ------------------------------------------------------------ drawing
local black = face(Font.EMOJI_FALLBACK, 20)
check(E.drawGlyph(bb, black, 2222, 100, 50, { fg = true }) == true and #drawn == 8, "a colour screen: 😀 drawn as its 8 layers")
check(drawn[1].gid == 23029 and drawn[1].c.r == 0xFC and drawn[1].x == 101 and drawn[1].y == 40
    and drawn[1].font:find("OpenMoji%-color%-glyf_colr_0%.ttf$") ~= nil and drawn[8].gid == 23032,
    "…in order, each in its colour, from the colour font at the same size, at the glyph's origin")
drawn = {}
check(E.drawGlyph(bb, face("NotoSans-Regular.ttf", 20), 2222, 0, 0) == false and #drawn == 0, "another font's glyph: drawn as usual")
check(E.drawGlyph(bb, black, 5, 0, 0) == false and #drawn == 0, "a glyph of the emoji font without colour layers: as usual")
colour_screen = false
check(E.drawGlyph(bb, black, 2222, 0, 0) == false and #drawn == 0, "a grey screen: the black emoji, as usual")
check(E.drawChar(bb, face("NotoSans-Regular.ttf", 20), 0x1F600, 0, 0) == false, "…and through RenderText's path too")
colour_screen = true
local noto = face("NotoSans-Regular.ttf", 20)
check(E.drawChar(bb, noto, 0x1F600, 10, 30) == true and #drawn == 8, "RenderText's path: 😀 (only the emoji font has it) in colour")
drawn = {}
check(E.drawChar(bb, noto, 0x2764, 10, 30) == false and #drawn == 0, "❤ comes from FreeSans first: drawn as usual (black text)")
check(E.drawChar(bb, noto, 0x41, 10, 30) == false, "a letter: as usual")

check(E.wanted("Weekend \u{1F600}") == true and E.wanted("Weekend") == false and E.wanted(nil) == false,
    "a text box with an emoji above U+FFFF on a colour screen draws into a colour canvas")
colour_screen = false
check(E.wanted("Weekend \u{1F600}") == false, "…not on a grey screen")
colour_screen = true

-- ------------------------------------------------------------ what it costs where there's no colour
-- (asked for every character from U+2000 up and every emoji glyph, on every
-- device, and wanted() for every text box's whole text at each render)
local real_device, real_find = package.loaded["device"], string.find
local finds = 0
local function counting(...) finds = finds + 1; return real_find(...) end
local asked = { screen = 0, colour = 0 }
E.reset()
package.loaded["device"] = { screen = {
    isColorScreen = function() asked.screen = asked.screen + 1; return false end,
    isColorEnabled = function() asked.colour = asked.colour + 1; return false end,
} }
drawn = {}
string.find = counting
for _ = 1, 3 do
    E.on(); E.wanted("Weekend \u{1F600}"); E.drawGlyph(bb, black, 2222, 0, 0); E.drawChar(bb, noto, 0x1F600, 0, 0)
end
string.find = real_find
check(asked.screen == 1 and asked.colour == 0 and finds == 0 and #drawn == 0,
    "a grey screen: asked once whether it's a colour screen, then nothing (no setting read, no text scanned): "
    .. asked.screen .. " " .. asked.colour .. " " .. finds)
E.reset()
local enabled = false
package.loaded["device"] = { screen = {
    isColorScreen = function() return true end,
    isColorEnabled = function() asked.colour = asked.colour + 1; return enabled end,
} }
finds = 0
string.find = counting
local off = E.wanted("Weekend \u{1F600}")
string.find = real_find
check(off == false and finds == 0, "a colour screen with colour rendering off: the text isn't scanned either")
enabled = true
check(E.wanted("Weekend \u{1F600}") == true and E.drawChar(bb, noto, 0x1F600, 10, 30) == true,
    "…turned on: asked each time (it can be turned on and off), so emoji are in colour again")
enabled = false
check(E.wanted("Weekend \u{1F600}") == false, "…and off again")
E.reset()
package.loaded["device"] = nil
check(E.on() == false, "no device yet (early in start-up): not colour, and nothing loaded for it")
package.loaded["device"] = real_device
check(E.on() == true, "…the device once it's there")
local on_src = read("frontend/gzcoloremoji.lua"):match("\nfunction M%.on%(%)(.-)\nend\n")
check(on_src ~= nil and not on_src:find("pcall", 1, true) and not on_src:find("require", 1, true) and not on_src:find("function", 1, true),
    "M.on(): no pcall, require or new function each time")
drawn = {}

-- ------------------------------------------------------------ where it's wired in
local fontlua = read("frontend/ui/font.lua")
check(fontlua:find('local emoji = "plugins/gzreader.koplugin/fonts/OpenMoji-black-glyf.ttf"', 1, true) ~= nil
    and fontlua:find("Font.fallbacks[#Font.fallbacks + 1] = emoji", 1, true) ~= nil
    and fontlua:find("Font.EMOJI_FALLBACK = emoji", 1, true) ~= nil,
    "font.lua: the black emoji font is the last fallback (Font.EMOJI_FALLBACK)")
check(read("frontend/ui/rendertext.lua"):find("GzColourEmoji.drawChar(dest_bb, face, charcode, x + pen_x, baseline, fgcolor)", 1, true) ~= nil,
    "rendertext.lua: renderUtf8Text asks for a colour emoji first")
check(read("frontend/ui/widget/textwidget.lua"):find("GzColourEmoji.drawGlyph(bb, face, xglyph.glyph", 1, true) ~= nil,
    "textwidget.lua: a one-line text's glyphs ask for a colour emoji first")
check(read("frontend/ui/widget/textboxwidget.lua"):find("or GzColourEmoji.wanted(self.text)", 1, true) ~= nil,
    "textboxwidget.lua: a colour canvas when the text has emoji")
check(read("frontend/ui/widget/textboxwidget.lua"):find("GzColourEmoji.drawGlyph(self._bb, face, xglyph.glyph", 1, true) ~= nil,
    "textboxwidget.lua: each glyph asks for a colour emoji first")
local notices = read("plugins/gzreader.koplugin/THIRD_PARTY_NOTICES.md")
local lic = io.open(REPO .. "/plugins/gzreader.koplugin/fonts/OpenMoji-LICENSE.txt")
check(notices:find("All emojis designed by [OpenMoji](https://openmoji.org/)", 1, true) ~= nil and notices:find("CC BY-SA 4.0", 1, true) ~= nil
    and lic ~= nil and lic:read("*l"):find("Attribution%-ShareAlike 4.0") ~= nil,
    "OpenMoji credited as its licence asks, the licence beside the fonts")
if lic then lic:close() end
local pk = read("tools/gzreader/package-kindle.sh")
local cut = pk:find('rm -f "$STAGE/full/GZreader/app/plugins/gzreader.koplugin/fonts/OpenMoji-color-glyf_colr_0.ttf"', 1, true)
check(cut ~= nil and pk:find('[ "$PLATFORM" = "kindle-legacy" ] || [ "$PLATFORM" = "kindle" ]', 1, true) ~= nil
    and pk:find('cp -a "$KO" "$STAGE/full/GZreader/app"', 1, true) < cut
    and pk:find('rm -f "$KO/plugins/gzreader.koplugin/fonts/OpenMoji', 1, true) == nil,
    "package-kindle.sh: the Kindle 2/3/DX and Kindle 4/Touch full installs go without the colour font; the update package keeps it")
local black_ttf = io.open(REPO .. "/plugins/gzreader.koplugin/fonts/OpenMoji-black-glyf.ttf", "rb")
check(black_ttf ~= nil and black_ttf:read(4) == "\0\1\0\0", "the black font is there (TrueType)")
if black_ttf then black_ttf:close() end

print(("coloremoji: %d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
