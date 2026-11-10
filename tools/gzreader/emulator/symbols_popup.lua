-- The symbols popup (frontend/gzsymbols.lua) on a Kindle with a keyboard
-- (k2, k3, dx, dxg): a text box, a lone Sym opens the popup, the 5-way
-- moves, Press types the symbol and the popup stays up for more; a letter
-- is typed with it up; Sym closes it. Writes <out>/symbols_popup.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local state = {}
local function popupShown()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "GzSymbols" then return w.widget end
    end
end
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    local InputDialog = require("ui/widget/inputdialog")
    state.dialog = InputDialog:new{ title = "Search", input = "" }
    UIM():show(state.dialog)
end, after = 4 })
add({ key = "A", after = 2 })
add({ key = "Sym", after = 4 })
add({ fn = function() check(popupShown() ~= nil, "a lone Sym opens the symbols popup") end, after = 1 })
add({ shot = "symbols-1-open" })
add({ key = "Down", after = 2 })
add({ key = "Right", after = 2 })
add({ shot = "symbols-2-comma" })
add({ key = "Press", after = 3 })
add({ fn = function()
    check(popupShown() ~= nil, "Press types and the popup stays up")
    check(state.dialog:getInputText() == "a,", "the comma typed: " .. state.dialog:getInputText())
end, after = 1 })
add({ key = "Right", after = 2 })
add({ key = "Press", after = 3 })
add({ key = "Press", after = 3 })
add({ fn = function()
    local p = popupShown()
    check(p ~= nil and p.selected.x == 3 and p.selected.y == 2, "still up after more, on the dot")
    check(state.dialog:getInputText() == "a,..", "two dots typed: " .. state.dialog:getInputText())
end, after = 1 })
add({ shot = "symbols-3-typed" })
add({ key = "B", after = 3 })
add({ fn = function()
    check(popupShown() ~= nil and state.dialog:getInputText() == "a,..b", "a letter is typed, still up: " .. state.dialog:getInputText())
end, after = 1 })
add({ key = "Sym", after = 3 })
add({ fn = function()
    check(popupShown() == nil and state.dialog:getInputText() == "a,..b", "Sym closes it, nothing typed")
end, after = 1 })
add({ shot = "symbols-4-closed" })
add({ key = "Sym", after = 4 })
add({ fn = function()
    local p = popupShown()
    check(p ~= nil and p.selected.x == 3 and p.selected.y == 2, "opens again on the dot")
end, after = 1 })
add({ key = "Sym", after = 3 })
add({ fn = function(E)
    UIM():close(state.dialog)
    local f = io.open(E.out .. "/symbols_popup.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
