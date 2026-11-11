--[[--
The bookshelves' theme and ornaments (Home's shelf, Downloads in the
Bookshelf view, the Catalog's ledges): after AndyHazz's Bookshelf plugin
(https://github.com/AndyHazz/bookshelf.koplugin, AGPL-3.0), whose oak plank
and two ornaments (a potted plant, a cactus) these are:
icons/shelf/plank-oak.png (its plank's top and front, in greys) and
icons/shelf/ornament-*.svg.

- A theme is the plank the books stand on: Plain (drawn in flat greys, as
  before), Oak (the wood's grain) or Walnut (the same wood, darker).
- Ornaments stand on a shelf's free end, like a plant on a half-empty
  shelf: where there's room (nothing moves for them), on every page (the
  bottom shelf keeps room for one), or not at all. Which one stands where
  is the same every time a page is shown. Your own: PNG or SVG files in
  koreader/settings/gzreader/ornaments (the picture's bottom edge stands on
  the plank).

shelf.lua (the spines and boards), gzreader_shelfview.lua (Downloads) and
gzreader_bookshop.lua (the Catalog) ask this module; without it they draw as
before.
]]

local _ = require("gettext")

local Theme = {
    SETTING = "gzreader_shelf_theme",
    ORNAMENTS = "gzreader_shelf_ornaments",
    DEFAULT = "oak",
    ORNAMENTS_DEFAULT = "room",
    ORDER = { "plain", "oak", "walnut" },
    THEMES = {
        plain = { plank = nil },
        oak = { plank = "plank-oak.png", darken = 0 },
        walnut = { plank = "plank-oak.png", darken = 0.45 },
    },
    HEIGHT = 0.8,       -- an ornament's height, of the books' room on the shelf
    MIN_W = 24,         -- the narrowest one worth standing (px at 160 dpi)
    MARGIN = 10,        -- between it and the books, and the shelf's end
    SURFACE_ROWS = 24,  -- plank-oak.png: its top's rows, then its front's
    FRONT_ROWS = 8,
    BUILT_IN = { "ornament-plant.svg", "ornament-cactus.svg" },
}

local root = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"

local function S(px) return require("device").screen:scaleBySize(px) end

---------------------------------------------------------------- settings

function Theme.labels()
    return { plain = _("Plain"), oak = _("Oak"), walnut = _("Walnut") }
end

--- The theme chosen ("plain", "oak" or "walnut").
function Theme.get()
    local v = G_reader_settings and G_reader_settings:readSetting(Theme.SETTING)
    if type(v) == "string" and Theme.THEMES[v] then return v end
    return Theme.DEFAULT
end

--- Ornaments: "off", "room" (where there's room) or "always" (every page).
function Theme.ornaments()
    local v = G_reader_settings and G_reader_settings:readSetting(Theme.ORNAMENTS)
    if v == "off" or v == "room" or v == "always" then return v end
    return Theme.ORNAMENTS_DEFAULT
end

--- What's drawn is drawn again: the planks and spines kept, the shelves on screen.
function Theme.changed()
    Theme.planks, Theme.images, Theme.found = {}, {}, nil
    pcall(function()
        package.loaded["gzreader_shelfview"]._per_page = nil -- (a page's count depends on the room kept)
    end)
    pcall(function()
        local UIManager = require("ui/uimanager")
        local FileManager = require("apps/filemanager/filemanager")
        local fm = FileManager.instance
        if fm and fm.file_chooser then fm.file_chooser:updateItems() end
        local zen = fm and fm.zenos
        local home = zen and require("common/shared_state").get(zen, "home")
        if home and home.rebuildActive then home.rebuildActive() end
        UIManager:setDirty("all", "ui")
    end)
end

function Theme.set(id)
    if not Theme.THEMES[id] then return false end
    G_reader_settings:saveSetting(Theme.SETTING, id)
    Theme.changed()
    return true
end

function Theme.setOrnaments(v)
    if v ~= "off" and v ~= "room" and v ~= "always" then return false end
    G_reader_settings:saveSetting(Theme.ORNAMENTS, v)
    Theme.changed()
    return true
end

---------------------------------------------------------------- the plank

Theme.planks = {}

--- The plank's picture for a board w wide, its top top_h tall and its front
--- front_h (one buffer, the top above the front), or nil in the Plain theme
--- (or when the picture can't be made: the board is drawn in greys then).
function Theme.plank(w, top_h, front_h)
    local th = Theme.THEMES[Theme.get()]
    if not (th and th.plank) or w < 8 or top_h < 1 or front_h < 1 then return nil end
    local key = table.concat({ Theme.get(), w, top_h, front_h }, ":")
    local have = Theme.planks[key]
    if have ~= nil then return have or nil end
    local ok, bb = pcall(function()
        local Blitbuffer = require("ffi/blitbuffer")
        local RenderImage = require("ui/renderimage")
        local src = RenderImage:renderImageFile(root .. "/icons/shelf/" .. th.plank, false)
        if not src then error("no picture") end
        local sw = src:getWidth()
        local function part(y0, rows, to_h)
            local piece = Blitbuffer.new(sw, rows, src:getType())
            piece:blitFrom(src, 0, 0, 0, y0, sw, rows)
            local scaled = RenderImage:scaleBlitBuffer(piece, w, to_h, true)
            return scaled
        end
        local out = Blitbuffer.new(w, top_h + front_h, Blitbuffer.TYPE_BB8)
        local top = part(0, Theme.SURFACE_ROWS, top_h)
        out:blitFrom(top, 0, 0, 0, 0, w, top_h)
        top:free()
        local front = part(Theme.SURFACE_ROWS, Theme.FRONT_ROWS, front_h)
        out:blitFrom(front, 0, top_h, 0, 0, w, front_h)
        front:free()
        src:free()
        if (th.darken or 0) > 0 then out:darkenRect(0, 0, w, top_h + front_h, th.darken) end
        return out
    end)
    -- (a few boards' widths at most: Home's, Downloads', the Catalog's ledges)
    local n = 0
    for _k in pairs(Theme.planks) do n = n + 1 end
    if n > 8 then
        for k, v in pairs(Theme.planks) do if v then v:free() end; Theme.planks[k] = nil end
    end
    Theme.planks[key] = ok and bb or false
    return ok and bb or nil
end

---------------------------------------------------------------- ornaments

--- A picture's width / height from its file: an SVG's viewBox, a PNG's header.
function Theme.aspectOf(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local head = f:read(4096) or ""
    f:close()
    if head:sub(1, 8) == "\137PNG\r\n\26\n" and #head >= 24 then
        local function u32(i)
            local a, b, c, d = head:byte(i, i + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        local w, h = u32(17), u32(21)
        if w > 0 and h > 0 then return w / h end
        return nil
    end
    local x, y, w, h = head:match('viewBox%s*=%s*["\']%s*([%-%d%.]+)[%s,]+([%-%d%.]+)[%s,]+([%d%.]+)[%s,]+([%d%.]+)')
    w, h = tonumber(w), tonumber(h)
    if x and y and w and h and w > 0 and h > 0 then return w / h end
    return nil
end

--- The reader's own ornaments' folder (made when asked with `make`).
function Theme.userDir(make)
    local ok, dir = pcall(function() return require("datastorage"):getSettingsDir() .. "/gzreader/ornaments" end)
    if not ok then return nil end
    if make then
        local lfs = require("libs/libkoreader-lfs")
        lfs.mkdir(dir:match("^(.*)/[^/]+$"))
        lfs.mkdir(dir)
    end
    return dir
end

--- Every ornament: { { path, aspect, name } }, Bookshelf's two first, then
--- the reader's own files by name. Looked up once (Theme.changed forgets).
function Theme.list()
    if Theme.found then return Theme.found end
    local out = {}
    for _i, name in ipairs(Theme.BUILT_IN) do
        local path = root .. "/icons/shelf/" .. name
        local aspect = Theme.aspectOf(path)
        if aspect then out[#out + 1] = { path = path, aspect = aspect, name = name } end
    end
    local dir = Theme.userDir(false)
    local okl, lfs = pcall(require, "libs/libkoreader-lfs")
    if dir and okl and lfs.attributes(dir, "mode") == "directory" then
        local names = {}
        for name in lfs.dir(dir) do
            local lower = name:lower()
            if name:sub(1, 1) ~= "." and (lower:match("%.svg$") or lower:match("%.png$")) then names[#names + 1] = name end
        end
        table.sort(names)
        for i = 1, math.min(#names, 40) do
            local path = dir .. "/" .. names[i]
            local aspect = Theme.aspectOf(path)
            if aspect then out[#out + 1] = { path = path, aspect = aspect, name = names[i] } end
        end
    end
    Theme.found = out
    return out
end

local function hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

--- The ornament for a place (`seed`: the same place, the same ornament), or nil.
function Theme.pick(seed)
    local list = Theme.list()
    if #list == 0 then return nil end
    return list[hash(seed) % #list + 1]
end

--- The size `entry` stands at beside books `stand_h` tall, in `free_w` of
--- room: w, h; nil when it doesn't fit (it's never squeezed under 2/3).
function Theme.size(entry, stand_h, free_w)
    local h = math.floor(stand_h * Theme.HEIGHT)
    local w = math.floor(h * entry.aspect)
    local most = free_w - 2 * S(Theme.MARGIN)
    if w > most then
        local scale = most / w
        if scale < 2 / 3 then return nil end
        w, h = math.floor(w * scale), math.floor(h * scale)
    end
    if w < S(Theme.MIN_W) or h < S(Theme.MIN_W) then return nil end
    return w, h
end

--- The room the bottom shelf of a page keeps for an ornament ("on every
--- page"), for books `stand_h` tall: 0 otherwise.
function Theme.reserve(stand_h)
    if Theme.ornaments() ~= "always" then return 0 end
    local list = Theme.list()
    if #list == 0 then return 0 end
    local widest = 0
    for _i, e in ipairs(list) do widest = math.max(widest, math.min(e.aspect, 1)) end
    return math.floor(stand_h * Theme.HEIGHT * widest) + 2 * S(Theme.MARGIN)
end

Theme.images = {}

local function image(entry, w, h)
    local key = entry.path .. "@" .. w .. "x" .. h
    local have = Theme.images[key]
    if have ~= nil then return have or nil end
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        if entry.path:lower():match("%.svg$") then return RenderImage:renderSVGImageFile(entry.path, w, h) end
        return RenderImage:renderImageFile(entry.path, false, w, h)
    end)
    local n = 0
    for _k in pairs(Theme.images) do n = n + 1 end
    if n > 12 then
        for k, v in pairs(Theme.images) do if v then v:free() end; Theme.images[k] = nil end
    end
    Theme.images[key] = ok and bb or false
    return ok and bb or nil
end

--- Stand an ornament on the board at board_y, in the free room from
--- `left` to `right` (the shelf's end, or where its devices begin), for
--- books `stand_h` tall. Returns its place { x, y, w, h } or nil (ornaments
--- off, no room, nothing to stand).
function Theme.paintOrnament(bb, seed, left, right, board_y, stand_h)
    if Theme.ornaments() == "off" then return nil end
    local entry = Theme.pick(seed)
    if not entry then return nil end
    local w, h = Theme.size(entry, stand_h, right - left)
    if not w then return nil end
    local img = image(entry, w, h)
    if not img then return nil end
    local iw, ih = img:getWidth(), img:getHeight()
    local x = right - S(Theme.MARGIN) - iw
    local y = board_y - ih
    -- where it stands on the board, then the piece
    bb:darkenRect(x + math.floor(iw * 0.15), board_y, math.floor(iw * 0.7), S(2), 0.30)
    local Blitbuffer = require("ffi/blitbuffer")
    local t = img:getType()
    if t == Blitbuffer.TYPE_BBRGB32 or t == Blitbuffer.TYPE_BB8A then
        bb:alphablitFrom(img, x, y, 0, 0, iw, ih)
    else
        bb:blitFrom(img, x, y, 0, 0, iw, ih)
    end
    return { x = x, y = y, w = iw, h = ih }
end

---------------------------------------------------------------- Settings

--- Settings → Downloads → Appearance → Bookshelf theme.
function Theme.settingsItem()
    local labels = Theme.labels()
    local items = {}
    for _i, id in ipairs(Theme.ORDER) do
        items[#items + 1] = {
            text = labels[id],
            radio = true,
            checked_func = function() return Theme.get() == id end,
            callback = function() Theme.set(id) end,
        }
    end
    items[#items].separator = true
    for _i, o in ipairs({ { "off", _("No ornaments") }, { "room", _("Ornaments where there's room") },
            { "always", _("An ornament on every page") } }) do
        items[#items + 1] = {
            text = o[2],
            radio = true,
            checked_func = function() return Theme.ornaments() == o[1] end,
            callback = function() Theme.setOrnaments(o[1]) end,
        }
    end
    items[#items].separator = true
    items[#items + 1] = {
        text = _("Your own ornaments…"),
        keep_menu_open = true,
        callback = function()
            local dir = Theme.userDir(true)
            Theme.found = nil
            pcall(function()
                require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
                    text = require("ffi/util").template(_("Put PNG or SVG pictures in this folder (with the Kindle connected to a computer) and they stand on the shelves with the others:\n\n%1\n\nA picture's bottom edge stands on the plank; leave its background transparent."), tostring(dir)),
                })
            end)
        end,
    }
    return {
        text = _("Bookshelf theme"),
        help_text = _("The plank the books stand on, and the ornaments on the shelves' free ends: Home, Downloads and the Catalog in the Bookshelf view."),
        sub_item_table = items,
    }
end

return Theme
