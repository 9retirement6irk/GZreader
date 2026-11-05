--[[--
GZreader's own folders in the home folder: Audiobooks and Music. In lists
and tiles they're always first, whatever the sort; on the bookshelf they
stand to the right of the books (gzreader_shelfview.lua).
]]

local _ = require("gettext")

local Order = {
    SPECIAL = {
        Audiobooks = { icon = "walkman", ratio = 126 / 150, label = _("Audiobooks") },
        Music = { icon = "cdplayer", ratio = 150 / 132, label = _("Music") },
    },
    SPECIAL_ORDER = { "Audiobooks", "Music" },
}

local function homeDir()
    local h = G_reader_settings:readSetting("home_dir")
    return h and (h:gsub("/+$", "")) or nil
end

--- "Audiobooks" / "Music" for GZreader's own folders (in the home folder), else nil.
function Order.specialOf(entry)
    if type(entry) ~= "table" or entry.is_file or type(entry.path) ~= "string" then return nil end
    local dir, name = entry.path:gsub("/+$", ""):match("^(.*)/([^/]+)$")
    if not (name and Order.SPECIAL[name]) then return nil end
    local home = homeDir()
    if home and dir ~= home then return nil end
    return name
end

--- Move them to the top of a file list (after "..").
function Order.specialsFirst(items)
    local found = {}
    for i = #items, 1, -1 do
        local name = Order.specialOf(items[i])
        if name then found[name] = table.remove(items, i) end
    end
    local at = 1
    while items[at] and items[at].is_go_up do at = at + 1 end
    for _i, name in ipairs(Order.SPECIAL_ORDER) do
        if found[name] then table.insert(items, at, found[name]); at = at + 1 end
    end
end

return Order
