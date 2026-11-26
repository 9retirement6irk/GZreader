-- Handwriting on the keyboard (gzreader_hwkeyboard.lua): a text box, the
-- ✍ key in the 🌐 key's place, the writing pad, a word written with the pen
-- and typed into the box; ⌫, space; ⌨ the keys again.
-- The Kindle's own reader is asked too and what it read is logged (synthetic
-- strokes); the box's check uses a stand-in reader so it doesn't depend on
-- handwriting quality.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh hw_keyboard.lua <out>
-- Checks go to <out>/hw-keyboard-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function kb()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.KEYS and w.inputbox then return w end
    end
end
local function keyNamed(label)
    local k = kb()
    for _r, row in ipairs(k and k.layout or {}) do
        for _c, key in ipairs(row) do
            if key.label == label then
                local d = key[1] and key[1].dimen or key.dimen
                return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) }
            end
        end
    end
end
-- printed capital letters, pad coordinates scaled to its area
local function letterL(a, x, h) return { { a.x + x, a.y + 20 }, { a.x + x, a.y + 20 + h }, { a.x + x + h * 0.5, a.y + 20 + h } } end
local function letterI(a, x, h) return { { a.x + x, a.y + 20 }, { a.x + x, a.y + 20 + h } } end
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local InputDialog = require("ui/widget/inputdialog")
    E.dialog = InputDialog:new{ title = "Search", input = "find" }
    UIM():show(E.dialog)
    E.dialog:onShowKeyboard()
end, after = 4 })
add({ shot = "hwkb-1-keys" })
add({ fn = function(E)
    local at = keyNamed("✍")
    check(at ~= nil and keyNamed("🌐") == nil, "the keyboard: ✍ in the 🌐 key's place")
    E.say("hwkb: ✍ at", at and at[1], at and at[2])
    if at then E.tap(at) end
end, after = 4 })
add({ shot = "hwkb-2-pad" })
add({ fn = function(E)
    local HwKb = require("gzreader_hwkeyboard")
    local pad = HwKb.active
    local a = pad and pad:area()
    check(pad ~= nil and a ~= nil and a.h > 100, "✍: the writing pad in the keys' place (" .. tostring(a and (a.w .. "x" .. a.h)) .. ")")
    if not a then return end
    E.area = a
    -- the Kindle's own reader, for the log: what it makes of an L and an I
    local Hw = require("gzreader_handwriting")
    E.real_read = Hw.read
    Hw.read = function(plugin, flat, done, opts)
        E.real_read(plugin, flat, function(text, why) E.say("hwkb: the Kindle's reader read:", tostring(text), tostring(why)) end, { here = true })
        E.flat = #flat
        done("hello")
    end
    local h = math.floor(a.h * 0.45)
    E.pen(letterL(a, 60, h), 0.4)
    E.pen(letterI(a, 60 + h, h), 0.3)
end, after = 1 })
add({ shot = "hwkb-3-written" })
add({ fn = function(E) end, after = 3 })
add({ fn = function(E)
    local text = E.dialog:getInputText()
    E.say("hwkb: the box says", text)
    check(E.flat == 2 and text == "find hello", "the writing read a moment after the pen lifted, typed after a space (" .. tostring(text) .. ")")
end, after = 1 })
add({ shot = "hwkb-4-typed" })
add({ fn = function(E)
    -- a finger on the pad of a pen Kindle doesn't write
    E.finger({ { E.area.x + 200, E.area.y + 40 }, { E.area.x + 260, E.area.y + 90 } }, 0.3)
end, after = 3 })
add({ fn = function(E)
    check(E.dialog:getInputText() == "find hello", "a finger on the pad: no writing (the pen Kindle)")
    -- the pad's own keys: ⌫ then space
    local pad = require("gzreader_hwkeyboard").active
    local ok = pcall(function()
        pad.kb.inputbox:delChar()
    end)
    check(ok and E.dialog:getInputText() == "find hell", "⌫ on the pad")
    -- ⌨: the keys again
    require("gzreader_hwkeyboard").keys(kb())
end, after = 3 })
add({ shot = "hwkb-5-keys-again" })
add({ fn = function(E)
    check(require("gzreader_hwkeyboard").active == nil and keyNamed("✍") ~= nil, "⌨: the keys again, ✍ still there")
    require("gzreader_handwriting").read = E.real_read
    UIM():close(E.dialog)
    local f = io.open(E.out .. "/hw-keyboard-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n"); f:close()
end, after = 2 })
return s
