--[[--
Highlights that show on a greyscale Kindle whatever their colour.

KOReader draws a coloured "lighten" highlight by multiplying the page with the
colour; on a greyscale screen that is the colour's brightness, so a yellow
highlight (Grimmory's web reader's default) comes out only ~6% darker than the
page: next to invisible on a Kindle. Here, on a screen that isn't showing
colour, a highlight colour too light to see is drawn like KOReader's own grey
highlight (darkened by the "highlight_lighten_factor" setting, 0.2 by default).
Darker colours are drawn as before. The highlight's colour itself is not
changed, so it stays the same in Grimmory.

The other direction (a Kindle's grey highlight sent to Grimmory as the web
reader's yellow) is in gzreader_annosync.lua.
]]

local HL = { installed = false }

--- Brightness (0 = black … 1 = white) of a colour with r, g, b in 0..255.
function HL.luminance(color)
    if type(color) ~= "table" and type(color) ~= "cdata" then return nil end
    local ok, r, g, b = pcall(function() return color.r, color.g, color.b end)
    if not ok or not r or not g or not b then return nil end
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
end

--- Whether a highlight in this colour, drawn by multiplying, would be lighter
--- than the plain grey highlight (darkened by `factor`).
function HL.tooLight(color, factor)
    local lum = HL.luminance(color)
    return lum ~= nil and (1 - lum) < (factor or 0.2)
end

function HL.install()
    if HL.installed then return end
    local ok, ReaderView = pcall(require, "apps/reader/modules/readerview")
    if not ok or type(ReaderView) ~= "table" or not ReaderView.drawHighlightRect then return end
    HL.installed = true
    local Screen = require("device").screen
    local Blitbuffer = require("ffi/blitbuffer")
    local orig = ReaderView.drawHighlightRect
    function ReaderView:drawHighlightRect(bb, x, y, rect, drawer, color, draw_note_mark)
        if drawer == "lighten" and color and not (Blitbuffer.isColor8 and Blitbuffer.isColor8(color))
                and not (Screen.isColorEnabled and Screen:isColorEnabled()) then
            local factor = self.highlight and self.highlight.lighten_factor or 0.2
            if HL.tooLight(color, factor) then color = nil end -- (drawn as the grey highlight)
        end
        return orig(self, bb, x, y, rect, drawer, color, draw_note_mark)
    end
end

return HL
