--[[
GZreader: the title of the file manager's status row when it lists the home
folder, which in GZreader is always the GZreader folder: the Downloads tab.
ZenOS's other tabs (History, Collections, Favorites…) and GZreader's own
(Grimmory, Music…) name themselves there; the Downloads tab showed only the
row's centre items (nothing, by default). The navbar's label for the tab
(Settings → Interface → Navbar, `books_label`) wins when one is set, as it
does on the tab itself.
]]
local M = {}

--- The title for the status row at `norm_path`, or nil (keep ZenOS's own).
-- `norm_path`, `home_dir`: normalised folder paths; `navbar`: ZenOS's navbar
-- config (may be nil); `in_series_view`: a virtual series folder is open;
-- `gettext`: KOReader's `_`.
function M.downloads(norm_path, home_dir, navbar, in_series_view, gettext)
    if not norm_path or not home_dir or norm_path ~= home_dir or in_series_view then
        return nil
    end
    local custom = type(navbar) == "table" and navbar.books_label
    if type(custom) == "string" and custom ~= "" then return custom end
    return (gettext or function(s) return s end)("Downloads")
end

return M
