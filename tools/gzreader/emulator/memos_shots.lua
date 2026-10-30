-- Screenshots of the Memos mockup (mockups/memos_mockup.lua): board, a note,
-- filters, tags, the full-page editor (new, and editing with the toolbar
-- focused), and a PDF attachment opened in the reader.
local Mock = dofile("/root/work/koreader/tools/gzreader/emulator/mockups/memos_mockup.lua")
local UIManager = require("ui/uimanager")
local top
local function show(fn) return { fn = function() if top then UIManager:close(top, "full") end top = fn() end, after = 4 } end
return {
    start = 12,
    { key = "Back", after = 4 },
    show(function() return Mock.showBoard() end),
    { shot = "1-board" },
    show(function() return Mock.showNote(2) end),
    { shot = "2-note" },
    -- a checklist: W ticks "water filter" off again… here: untick it, tick socks
    show(function() return Mock.showNote(5, 3) end),
    { shot = "2b-checklist" },
    show(function() Mock.toggle(5, 3); Mock.toggle(5, 1); return Mock.showNote(5, 1) end),
    { shot = "2c-checklist-ticked" },
    show(function() return Mock.showBoard({ filter_label = "#travel" }) end),
    { fn = function() Mock.showFilters() end, after = 4 },
    { shot = "3-filters" },
    { key = "Back", after = 2 },
    show(function() return Mock.showTags() end),
    { shot = "4-tags" },
    show(function() return Mock.showNew() end),
    { shot = "5-new" },
    show(function() return Mock.showEdit(2) end),
    { shot = "6-edit" },
    show(function() return Mock.showEdit(2, 2) end),
    { shot = "7-edit-toolbar" },
    show(function() return Mock.showEdit(2, 7) end),
    { shot = "8-edit-tag" },
    { fn = function() Mock.showTagPicker() end, after = 4 },
    { shot = "8b-tag-picker" },
    { key = "Back", after = 2 },
    show(function() return Mock.showEdit(2, 8) end),
    { shot = "8-edit-save" },
    show(function() return Mock.showNote(6) end),
    { shot = "2d-image" },
    { fn = function() if top then UIManager:close(top) top = nil end
        require("apps/reader/readerui"):showReader("/root/work/emu/mock/trail.pdf") end, after = 20 },
    { shot = "9-pdf" },
}
