-- The drawing's paper chooser on a colour screen (any touch model; GZ_EMU_MODEL=scribe
-- is the size the papers were made for): the chooser as a new drawing shows it,
-- painted into a colour canvas as a colour Kindle would show it, and scrolled to
-- its last rows. Writes papers-1.png and papers-2.png, and counts the coloured
-- pixels (the papers and their tiles are in colour).
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
add({ fn = function()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local Screen = require("device").screen
    local Blitbuffer = require("ffi/blitbuffer")
    E.real_color = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    local Pages = require("gzreader_drawpages")
    local function shot(current, name)
        local list = Pages.showPapers{ current = current, create = true, on_pick = function() end, on_back = function() end }
        local out = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
        out:fill(Blitbuffer.COLOR_WHITE)
        list:paintTo(out, 0, 0)
        local n = 0
        for y = 0, out:getHeight() - 1, 3 do
            for x = 0, out:getWidth() - 1, 3 do
                local c = out:getPixel(x, y):getColorRGB32()
                if math.abs(c.r - c.g) > 24 or math.abs(c.g - c.b) > 24 then n = n + 1 end
            end
        end
        out:writePNG(E.out .. "/" .. name)
        out:free()
        UIM():close(list)
        return n, #list.papers
    end
    local n1, count = shot("legal", "papers-1.png")
    local n2 = shot("music", "papers-2.png")
    E.say("papers:", count, "coloured pixels (every third):", n1, n2)
    Screen.isColorEnabled = E.real_color
end, after = 4 })
return s
