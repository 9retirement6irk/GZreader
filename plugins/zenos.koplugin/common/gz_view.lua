-- GZreader: how books are shown, one choice for Home's book strip, Downloads
-- and the other book folders (the quick panel's View):
--   "bookshelf"            spines standing on shelves (the default)
--   "mosaic_image"         tiles
--   "list_image_meta"      a list with details
--   "list_image_filename"  a simple list
--
-- The bookshelf is drawn over CoverBrowser's tiles mode (it keeps the tiles'
-- covers, pages and cached book information): CoverBrowser's own setting is
-- "mosaic_image" then, and G_reader_settings "gzreader_view" says
-- "bookshelf". Home's strip is a shelf when its preset allows it (shelf =
-- true; never on the end-of-book page) and the view is the bookshelf.

local M = {}

M.MODES = { "bookshelf", "list_image_meta", "list_image_filename", "mosaic_image" }

local function bim()
    local ok, BIM = pcall(require, "bookinfomanager")
    return ok and BIM or nil
end

local function coverbrowserMode()
    local BIM = bim()
    return BIM and BIM.getSetting and BIM:getSetting("filemanager_display_mode") or nil
end

--- The view: "bookshelf", or CoverBrowser's mode (nil: the plain list).
function M.get()
    local cb = coverbrowserMode()
    if G_reader_settings:readSetting("gzreader_view") == "bookshelf" and cb == "mosaic_image" then
        return "bookshelf"
    end
    return cb
end

function M.isBookshelf()
    return M.get() == "bookshelf"
end

--- Home's strip is a shelf (its config allows it, and the view is the bookshelf)?
function M.stripShelf(module_cfg)
    return type(module_cfg) == "table" and module_cfg.shelf == true and M.isBookshelf()
end

local function fileManager()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    return ok and FileManager and FileManager.instance or nil
end

--- Choose a view (one of M.MODES); redraws Downloads and Home.
function M.set(mode)
    local was = M.get()
    G_reader_settings:saveSetting("gzreader_view", mode == "bookshelf" and "bookshelf" or "other")
    local cb_mode = mode == "bookshelf" and "mosaic_image" or mode
    local fm = fileManager()
    if fm and type(fm.onSetDisplayMode) == "function" then
        pcall(fm.onSetDisplayMode, fm, cb_mode)
    else
        local BIM = bim()
        if BIM and BIM.saveSetting then pcall(BIM.saveSetting, BIM, "filemanager_display_mode", cb_mode) end
    end
    if was ~= mode and fm then
        -- tiles <-> bookshelf: the same CoverBrowser mode, so redraw by hand
        local fc = fm.file_chooser
        if fc then
            pcall(function()
                if fc._recalculateDimen then fc:_recalculateDimen() end
                fc:refreshPath()
            end)
        end
        M.redrawHome()
    end
end

--- Home again, from scratch (the view or the shelf's order changed).
function M.redrawHome()
    local fm = fileManager()
    local zen = rawget(_G, "__ZEN_UI_PLUGIN") or (fm and fm.zenos)
    local ok_ss, shared = pcall(require, "common/shared_state")
    local home = ok_ss and zen and shared.get(zen, "home")
    if home then
        pcall(function()
            if home.invalidateLibraryCache then home.invalidateLibraryCache() end
            if home.rebuildActive then home.rebuildActive() end
        end)
    end
end

---------------------------------------------------------------- the shelf's order

--- Home's shelf in the order chosen with Sort (GZreader's sort dialog sets
--- "gzreader_shelf_sort"; none, or "access": most recently read first).
function M.shelfSort()
    local mode = G_reader_settings:readSetting("gzreader_shelf_sort")
    if not mode or mode == "access" then return nil end
    return mode .. (G_reader_settings:isTrue("reverse_collate") and ":r" or "")
end

local function natural(s)
    return (tostring(s or ""):lower():gsub("%d+", function(d) return string.format("%012d", tonumber(d)) end))
end

--- `paths` (most recently read first) sorted as chosen (a new table).
function M.sortPaths(paths)
    local key = M.shelfSort()
    if not key or type(paths) ~= "table" or #paths < 2 then return paths end
    local mode, rev = key:match("^([^:]+)(:?r?)$")
    local ok_bim, BIM = pcall(require, "bookinfomanager")
    local lfs = require("libs/libkoreader-lfs")
    local rows = {}
    for i, path in ipairs(paths) do
        local info = ok_bim and BIM:getBookInfo(path, false) or nil
        local name = tostring(path):match("([^/]+)$") or ""
        local title = info and not info.ignore_meta and info.title or name:gsub("%.[^%.]+$", "")
        local r = { path = path, i = i, title = natural(tostring(title):gsub("^[Tt]he%s+", ""):gsub("^[Aa]n?%s+", "")) }
        if mode == "authors" then
            r.k1 = natural(info and info.authors or "\255")
        elseif mode == "series" then
            r.k1 = natural(info and info.series or "\255")
            r.k2 = tonumber(info and info.series_index) or 0
        elseif mode == "date" then
            r.k2 = -(lfs.attributes(path, "modification") or 0)
        elseif mode == "size" then
            r.k2 = lfs.attributes(path, "size") or 0
        elseif mode == "natural" then
            r.k1 = natural(name)
        elseif mode == "percent_unopened_last" then
            local pct
            pcall(function()
                local DocSettings = require("docsettings")
                if DocSettings:hasSidecarFile(path) then
                    pct = tonumber(DocSettings:open(path):readSetting("percent_finished"))
                end
            end)
            r.k2 = pct and -pct or 1 -- (furthest read first; never opened last)
        end
        rows[#rows + 1] = r
    end
    table.sort(rows, function(a, b)
        if (a.k1 or "") ~= (b.k1 or "") then return (a.k1 or "") < (b.k1 or "") end
        if (a.k2 or 0) ~= (b.k2 or 0) then return (a.k2 or 0) < (b.k2 or 0) end
        if a.title ~= b.title then return a.title < b.title end
        return a.i < b.i
    end)
    local out = {}
    for k, r in ipairs(rows) do out[rev == ":r" and (#rows - k + 1) or k] = r.path end
    return out
end

return M
