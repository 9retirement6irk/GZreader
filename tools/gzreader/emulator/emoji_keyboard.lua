-- The emoji keys (gzreader_emojikeyboard.lua) on KOReader's real keyboard:
-- ☺ beside Shift, the space bar its own size, a tap on ☺ turns the keys to
-- emoji (the keyboard keeps its height), an emoji typed, ABC back.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh emoji_keyboard.lua <out>
-- Checks go to <out>/emoji-keyboard-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function find(kb, label)
    for _r, row in ipairs(kb.layout or {}) do
        for _c, k in ipairs(row) do if k.label == label then return k end end
    end
end
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    E.dlg = require("ui/widget/inputdialog"):new{ title = "Emoji", input = "Hi ", allow_newline = true }
    UIM():show(E.dlg)
    E.dlg:onShowKeyboard()
end, after = 3 })
add({ shot = "1-letters", after = 0.5 })
add({ fn = function(E)
    local kb = E.dlg._input_widget._keyboard or E.dlg._input_widget.keyboard
    E.kb = kb
    local row
    for _r, r in ipairs(kb.layout) do if find({ layout = { r } }, "☺") then row = r end end
    local labels = {}
    for _i, k in ipairs(row or {}) do labels[#labels + 1] = k.label end
    check(row and labels[2] == "☺" and row[1].width == row[2].width, "☺ right after Shift, the two the same width: " .. table.concat(labels, " "))
    local space = find(kb, "_")
    local letter = find(kb, "q")
    check(space and letter and space.width > 2.5 * letter.width, "the space bar its own size (" .. (space and space.width or 0) .. " px, a letter " .. (letter and letter.width or 0) .. ")")
    E.h = kb.dimen.h
    find(kb, "☺").callback()
end, after = 3 })
add({ shot = "2-emoji", after = 0.5 })
add({ fn = function(E)
    local kb = E.kb
    check(kb.gz_emoji_on and find(kb, "ABC") and #kb.layout[1] == 10 and kb.dimen.h == E.h,
        "a tap on ☺: the keys are emoji, the keyboard the same height (" .. kb.dimen.h .. " px)")
    local first = kb.layout[1][1]
    first.callback()
    local text = E.dlg:getInputText()
    check(text == "Hi " .. first.label, "a tap on an emoji types it: " .. text)
    find(kb, "▶").callback()
end, after = 3 })
add({ shot = "3-page-2", after = 0.5 })
add({ fn = function(E)
    local kb = E.kb
    find(kb, "ABC").callback()
    check(not kb.gz_emoji_on and find(kb, "☺") and find(kb, "q"), "ABC: the letters again")
end, after = 3 })
add({ shot = "4-letters-again", after = 0.5 })
add({ fn = function(E)
    local f = io.open(E.out .. "/emoji-keyboard-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
