-- The note editor's Menu key (1.6.2): to the toolbar and back with the
-- cursor kept where it is. A note of 40 lines, the cursor moved to line 25
-- (the text box scrolled), Menu, ▶ to Check, Press: line 25 becomes a
-- checklist item; Menu (on Check, the tool used last), Menu back, typing.
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local function key(k, after) add({ key = k, after = after or 2 }) end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local E_ed
local function report(label)
    add({ fn = function(E)
        local ed = E_ed
        local text = ed.input:getText()
        local lines = {}
        for l in (text .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
        E.say(label, "cursor", tostring(ed.input.charpos), "tool", tostring(ed.focus_tool),
            "text focused", tostring(ed.input.focused), "| line 25:", lines[25], "| line 26:", lines[26],
            "| top line shown:", tostring(ed.input.text_widget and ed.input.text_widget.virtual_line_num))
    end, after = 1 })
end
add({ fn = function()
    local t = {}
    for i = 1, 40 do t[i] = "Line " .. i .. " of a long note" end
    E_ed = require("gzreader_noteeditor").show({ memo = { content = table.concat(t, "\n"), visibility = "PRIVATE" },
        tags = { { tag = "travel", count = 2 } }, on_save = function() end })
end, after = 4 })
add({ fn = function()
    -- the cursor to "Line 25 |of a long note" (the text box scrolls there)
    local text = E_ed.input:getText()
    local pos, line = 1, 1
    for i = 1, #text do
        if line == 25 then pos = i; break end
        if text:sub(i, i) == "\n" then line = line + 1 end
    end
    E_ed.input:moveCursorToCharPos(pos + 8)
    require("ui/uimanager"):setDirty(E_ed, "ui")
end, after = 2 })
report("at line 25:")
shot("nt-1-cursor-line25")
key("Menu", 2)
report("after Menu:")
shot("nt-2-toolbar")
key("Right", 1.5)
key("Press", 2)
report("after Check:")
shot("nt-3-checked")
key("Menu", 2)
report("Menu again (last tool):")
key("Menu", 2)
report("back to the text:")
key("X", 1.5)
report("typed X:")
shot("nt-4-typed")
add({ fn = function(E) E.say("unsaved, closing"); require("ui/uimanager"):close(E_ed) end, after = 2 })
return s
