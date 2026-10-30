-- Screenshots of the Memos mockup (mockups/memos_mockup.lua): board, a note,
-- filters, tags, a new note, and a PDF attachment opened in the reader.
local Mock = dofile("/root/work/koreader/tools/gzreader/emulator/mockups/memos_mockup.lua")
local UIManager = require("ui/uimanager")
local top
local function close() if top then UIManager:close(top) top = nil end end
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function() top = Mock.showBoard() end, after = 4 },
    { shot = "1-board" },
    { fn = function() close(); top = Mock.showNote(2) end, after = 4 },
    { shot = "2-note" },
    { fn = function() close(); top = Mock.showBoard({ filter_label = "#travel" }) end, after = 3 },
    { fn = function() Mock.showFilters() end, after = 4 },
    { shot = "3-filters" },
    { key = "Back", after = 2 },
    { fn = function() close(); top = Mock.showTags() end, after = 4 },
    { shot = "4-tags" },
    { fn = function() close(); top = Mock.showBoard() end, after = 2 },
    { fn = function() Mock.showNew() end, after = 5 },
    { shot = "5-new" },
    { key = "Back", after = 2 },
    { fn = function() close(); require("apps/reader/readerui"):showReader("/root/work/emu/mock/trail.pdf") end, after = 20 },
    { shot = "6-pdf" },
}
