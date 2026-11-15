-- GZreader: a book whose pictures are fitted to the screen (GZreader's
-- gzreader_picturebook.lua) can use the room the title bar and the status bar
-- leave when they're hidden with a tap. KOReader keeps the status bar's
-- height in the bottom margin of an EPUB while it's hidden, and ZenOS keeps
-- the title bar's in the top margin; for such a book both are given back.
local M = {}

local function fills(view)
    local PB = package.loaded["gzreader_picturebook"]
    local ui = view and view.ui
    return PB ~= nil and type(PB.fillsHiddenBars) == "function" and ui ~= nil and PB.fillsHiddenBars(ui) == true
end

--- For a book's margins: (the title bar's reserve, px to take off the bottom
--- margin). top_hidden / bottom_hidden: the bars hidden with a tap.
function M.margins(view, reserve, top_hidden, bottom_hidden)
    reserve = tonumber(reserve) or 0
    if not (top_hidden or bottom_hidden) or not fills(view) then return reserve, 0 end
    local cut = 0
    local footer = view.footer
    if bottom_hidden and footer and not footer.reclaim_height and type(footer.getHeight) == "function" then
        local ok, h = pcall(footer.getHeight, footer)
        cut = ok and tonumber(h) or 0
    end
    return top_hidden and 0 or reserve, cut
end

--- The title bar alone was hidden or shown with a tap: lay the book out
--- again when its pictures fill the room (a status bar change does it itself).
function M.topToggled(view)
    if not fills(view) then return end
    local PB = package.loaded["gzreader_picturebook"]
    if PB and type(PB.onBarsChanged) == "function" then PB.onBarsChanged(view.ui) end
end

return M
