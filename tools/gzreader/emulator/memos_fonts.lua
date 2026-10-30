-- Handwriting options for the Memos notes: a sheet of weights, then the
-- same board and note in Patrick Hand, Kalam Regular (+Bold tags) and
-- Kalam Light (+Bold tags).
local Mock = dofile("/root/work/koreader/tools/gzreader/emulator/mockups/memos_mockup.lua")
local UIManager = require("ui/uimanager")
local top
local function show(fn) return { fn = function() if top then UIManager:close(top, "full") end top = fn() end, after = 4 } end
local F = "./fonts/handwriting/"
local s = { start = 12, { key = "Back", after = 4 }, show(function() return Mock.showSheet() end), { shot = "0-sheet" } }
for _i, v in ipairs({ { "patrick", F .. "PatrickHand-Regular.ttf", nil }, { "kalam", F .. "Kalam-Regular.ttf", F .. "Kalam-Bold.ttf" },
        { "kalam-light", F .. "Kalam-Light.ttf", F .. "Kalam-Bold.ttf" } }) do
    s[#s + 1] = show(function() Mock.useFont(v[2], v[3]); return Mock.showBoard() end)
    s[#s + 1] = { shot = "board-" .. v[1] }
    s[#s + 1] = show(function() return Mock.showNote(2) end)
    s[#s + 1] = { shot = "note-" .. v[1] }
end
return s
