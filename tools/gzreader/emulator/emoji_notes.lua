-- Emoji in text (OpenMoji's black font as the last fallback, frontend/ui/font.lua):
-- KOReader's real text code finds 😀 👍 📚 🎉 in it; a note with emoji in the
-- Notes tab (sticky notes) and opened.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh emoji_notes.lua <out>
-- Checks go to <out>/emoji-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local TEXT = "Weekend \u{1F600} \u{1F44D} \u{1F4DA} \u{1F389} \u{2764} \u{2705}"

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local Font = require("ui/font")
    local RenderText = require("ui/rendertext")
    check(Font.EMOJI_FALLBACK ~= nil and Font.fallbacks[#Font.fallbacks] == Font.EMOJI_FALLBACK,
        "the emoji font is the last fallback: " .. tostring(Font.fallbacks[#Font.fallbacks]))
    local ef = Font:getFace(Font.EMOJI_FALLBACK, 20)
    check(ef and ef.ftsize:hasGlyph(0x1F600) and ef.ftsize:hasGlyph(0x1F4DA), "it opens, and has 😀 and 📚")
    -- the interface font has no 😀: KOReader's text code finds it through the fallbacks
    local face = Font:getFace("cfont", 20)
    local found = {}
    for _i, cp in ipairs({ 0x1F600, 0x1F44D, 0x1F4DA, 0x1F389 }) do
        local g = RenderText:getGlyph(face, cp)
        local inked = 0
        if g and g.bb then
            for y = 0, g.bb:getHeight() - 1 do
                for x = 0, g.bb:getWidth() - 1 do
                    local c = g.bb:getPixel(x, y)
                    if (c.a or (c.getColor8 and c:getColor8().a) or 0) > 0 then inked = inked + 1 end
                end
            end
        end
        found[#found + 1] = string.format("U+%X:%d", cp, inked)
        if inked < 20 then found.bad = true end
    end
    check(not face.ftsize:hasGlyph(0x1F600) and not found.bad, "😀 👍 📚 🎉 drawn from it (inked pixels " .. table.concat(found, " ") .. ")")
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_memos"):new(p.store.memos):create(TEXT .. "\n\nBring snacks \u{1F36A}", "PRIVATE")
    require("gzreader_notes").show(p)
end, after = 8 })
add({ shot = "1-sticky-notes", after = 0.5 })
add({ fn = function(E)
    local N = require("gzreader_notes")
    for _i, m in ipairs(N.visible()) do
        if tostring(m.content):find("Weekend", 1, true) then E.v = N.showNote(plugin(), m) end
    end
    check(E.v ~= nil, "the note opens")
end, after = 5 })
add({ shot = "2-opened", after = 0.5 })
add({ fn = function(E)
    -- a colour screen (Colorsoft): the same text drawn into a colour canvas, both
    -- ways KOReader draws text (TextBoxWidget: xtext; TextWidget: RenderText)
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local Font = require("ui/font")
    local was = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    local function coloured(bb)
        local n = 0
        for y = 0, bb:getHeight() - 1 do
            for x = 0, bb:getWidth() - 1 do
                local c = bb:getPixel(x, y):getColorRGB32()
                if math.abs(c.r - c.g) > 40 or math.abs(c.g - c.b) > 40 then n = n + 1 end
            end
        end
        return n
    end
    local tb = require("ui/widget/textboxwidget"):new{ text = TEXT, face = Font:getFace("cfont", 24), width = 700 }
    local h = tb:getSize().h
    local out = Blitbuffer.new(700, h * 2 + 20, Blitbuffer.TYPE_BBRGB32)
    out:fill(Blitbuffer.COLOR_WHITE)
    tb:paintTo(out, 0, 0)
    local n1 = coloured(out)
    local tw = require("ui/widget/textwidget"):new{ text = TEXT, face = Font:getFace("cfont", 24) }
    tw:paintTo(out, 0, h + 20)
    local n2 = coloured(out) - n1
    out:writePNG(E.out .. "/3-colour.png")
    tb:free(); tw:free()
    Screen.isColorEnabled = was
    check(n1 > 300, "colour screen, a text box: the emoji in colour (" .. n1 .. " coloured pixels)")
    check(n2 > 300, "colour screen, a one-line text: the emoji in colour (" .. n2 .. " coloured pixels)")
    -- and a grey screen: nothing coloured
    local grey = Blitbuffer.new(700, h, Blitbuffer.TYPE_BBRGB32)
    grey:fill(Blitbuffer.COLOR_WHITE)
    local tb2 = require("ui/widget/textboxwidget"):new{ text = TEXT, face = Font:getFace("cfont", 24), width = 700 }
    tb2:paintTo(grey, 0, 0)
    check(coloured(grey) == 0, "grey screen: black emoji, nothing coloured")
    tb2:free()
end, after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/emoji-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
