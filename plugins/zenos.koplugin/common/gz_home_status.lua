-- GZreader: whether Home shows the status bar across the top, the one the
-- other tabs have.
--
-- Home's presets put the status bar inside the current-book widget
-- ("featured", its own show_status_bar) and turn Home's bar off
-- (show_status_bar = false). That bar is only drawn next to a book: with no
-- book to show (nothing read yet, history cleared) or the widget off, Home
-- had no status bar at all (no clock, battery, Wi-Fi). Then Home shows the
-- usual one instead, and goes back to the book's own when there's a book.

local M = {}

local function featured_cfg(dcfg)
    local modules = type(dcfg) == "table" and type(dcfg.modules) == "table" and dcfg.modules or {}
    local mcfg = modules.featured
    return type(mcfg) == "table" and mcfg or nil
end

local function has_featured_row(rows)
    for _i, comp in ipairs(rows or {}) do
        if comp.id == "featured" then return true end
    end
    return false
end

--- Whether the current-book widget is set to carry the status bar.
function M.embedded(dcfg)
    local mcfg = featured_cfg(dcfg)
    return mcfg ~= nil and mcfg.show_status_bar == true
end

--- Whether Home shows the status bar across the top.
-- dcfg: Home's settings; rows: the rows on Home (resolve_rows);
-- has_book: function() → whether the current-book widget has a book to show
-- (asked only when it matters; nil: assume it has one).
function M.wanted(dcfg, rows, has_book)
    if type(dcfg) ~= "table" then return true end
    if dcfg.show_status_bar ~= false then return true end
    -- Home's bar is off: on purpose, unless the book widget carries it
    if not M.embedded(dcfg) then return false end
    if not has_featured_row(rows) then return true end
    if type(has_book) ~= "function" then return false end
    local ok, yes = pcall(has_book)
    if not ok then return false end
    return not yes
end

return M
