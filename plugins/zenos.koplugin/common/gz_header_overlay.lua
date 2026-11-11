--[[
GZreader: windows over a book that leave the reader's top status bar in view.
The top bar is only drawn while the book is the topmost window
(`reader_top_status_bar.lua`'s `is_view_active_top`). KOReader's layout menu
(the bottom config menu: font size, margins, spacing…) sits at the bottom of
the screen, but it is a window of its own, so while it was open the book was
redrawn without the bar (font size changes, and the quick panel's area, which
is cleared just as the menu opens), and closing the menu redraws only the
menu's own area: the bar stayed missing until the next page turn.
]]
local M = {}

--- True when `top_widget` is the open layout menu of the book `view` shows.
function M.leavesHeader(view, top_widget)
    if not (view and view.ui and top_widget) then return false end
    local config = view.ui.config
    local dialog = config and config.config_dialog
    return dialog ~= nil and top_widget == dialog
end

return M
