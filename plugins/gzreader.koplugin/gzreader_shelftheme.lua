--[[--
The bookshelves' theme and ornaments (Home's shelf, Downloads in the
Bookshelf view, the Catalog's ledges): after AndyHazz's Bookshelf plugin
(https://github.com/AndyHazz/bookshelf.koplugin, AGPL-3.0), whose oak plank
is icons/shelf/plank-oak.png (its top and front, in greys), and whose two
ornaments (a potted plant, a cactus) are redrawn here. The ornaments are
shaded drawings (light from the upper left), GZreader's own but for those
two, some of them seasonal: a Christmas tree, a present and a snowman in
winter, a pumpkin in autumn, tulips in spring. They ship as pictures
(icons/shelf/ornament-*.png) rendered from tools/gzreader/ornaments/*.svg:
the Kindle's SVG renderer draws gradients far too dark.

- A theme is the plank the books stand on: Plain (drawn in flat greys, as
  before), Oak (the wood's grain) or Walnut (the same wood, darker).
- Ornaments stand on a shelf's free end, like a plant on a half-empty
  shelf: where there's room (nothing moves for them), on every page (the
  shelves that get one keep room for it), or not at all. Where and how
  many: on Home, in Downloads, in the Catalog (each can be off); one, two or
  three on a page at most, or one on every shelf; at the right end of the
  shelf, the left, or scattered (right, then left, then right). Which one stands where
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
    CHOSEN = "gzreader_shelf_ornament_set", -- { [file name] = true / false }: ticked or unticked by hand
    FAVOUR = 2,         -- in its season, a seasonal ornament takes 2 places of 3
}

--- The ornaments that come with GZreader: Bookshelf's two, then GZreader's
--- own. tall: its height, of the books' room (HEIGHT when not given).
--- season: { from month, day, to month, day }: it stands only then, unless
--- ticked by hand (Settings).
Theme.BUILT_IN = {
    { file = "ornament-plant.png", label = _("Potted plant") },
    { file = "ornament-cactus.png", label = _("Cactus") },
    { file = "ornament-globe.png", label = _("Globe"), tall = 0.72 },
    { file = "ornament-hourglass.png", label = _("Hourglass"), tall = 0.6 },
    { file = "ornament-cat.png", label = _("Cat"), tall = 0.62 },
    { file = "ornament-tulips.png", label = _("Tulips"), season = { 3, 1, 5, 31 }, when = _("March to May") },
    { file = "ornament-pumpkin.png", label = _("Pumpkin"), tall = 0.42, season = { 9, 15, 11, 30 }, when = _("mid-September to November") },
    { file = "ornament-christmas-tree.png", label = _("Christmas tree"), tall = 0.95, season = { 11, 20, 1, 6 }, when = _("20 November to 6 January") },
    { file = "ornament-present.png", label = _("Present"), tall = 0.42, season = { 12, 1, 1, 6 }, when = _("December to 6 January") },
    { file = "ornament-snowman.png", label = _("Snowman"), tall = 0.8, season = { 12, 1, 2, 28 }, when = _("December to February") },
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

--- Where ornaments stand: { home, downloads, catalog } (all, to begin with).
Theme.PLACES = "gzreader_shelf_ornament_places"
Theme.PLACE_ORDER = { "home", "downloads", "catalog" }
function Theme.placeOn(place)
    local t = G_reader_settings and G_reader_settings:readSetting(Theme.PLACES)
    if type(t) ~= "table" or t[place] == nil then return true end
    return t[place] == true
end
function Theme.setPlace(place, on)
    local t = {}
    local old = G_reader_settings:readSetting(Theme.PLACES)
    for k, v in pairs(type(old) == "table" and old or {}) do t[k] = v end
    t[place] = on and true or false
    G_reader_settings:saveSetting(Theme.PLACES, t)
    Theme.changed()
end

--- How many on a page at most: 1 (to begin with), 2, 3, or "all" (every shelf).
Theme.COUNT = "gzreader_shelf_ornament_count"
function Theme.count()
    local v = G_reader_settings and G_reader_settings:readSetting(Theme.COUNT)
    if v == "all" then return math.huge end
    v = tonumber(v)
    if v and v >= 1 and v <= 3 then return math.floor(v) end
    return 1
end
function Theme.setCount(v)
    if v ~= "all" and not (tonumber(v) and tonumber(v) >= 1 and tonumber(v) <= 3) then return false end
    G_reader_settings:saveSetting(Theme.COUNT, v)
    Theme.changed()
    return true
end

--- Which end of a shelf: "right" (to begin with), "left", or "scattered"
--- (the first on a page on the right, the next on the left, then right…).
Theme.SIDE = "gzreader_shelf_ornament_side"
function Theme.side()
    local v = G_reader_settings and G_reader_settings:readSetting(Theme.SIDE)
    if v == "left" or v == "scattered" then return v end
    return "right"
end
function Theme.setSide(v)
    if v ~= "right" and v ~= "left" and v ~= "scattered" then return false end
    G_reader_settings:saveSetting(Theme.SIDE, v)
    Theme.changed()
    return true
end

--- Which of a page's shelves get an ornament, and at which end:
--- { [row] = "right" | "left" }, and { [row] = which of the page's
--- ornaments it is: 1, 2… }. `occupied`: the rows with books on them,
--- top down. The lowest ones are taken, as many as the count allows (the
--- free room is on a page's last shelves); the sides are dealt top down.
function Theme.rowsFor(place, occupied)
    local out, nth = {}, {}
    if Theme.ornaments() == "off" or not Theme.placeOn(place) then return out, nth end
    local n = math.min(Theme.count(), #occupied)
    local side = Theme.side()
    for k = 1, n do
        local row = occupied[#occupied - n + k]
        out[row] = side == "scattered" and (k % 2 == 1 and "right" or "left") or side
        nth[row] = k
    end
    return out, nth
end

--- Does shelf `row` of `rows` keep room for an ornament ("on every page")?
function Theme.keeps(place, row, rows)
    if Theme.ornaments() ~= "always" or not Theme.placeOn(place) then return false end
    return row > rows - math.min(Theme.count(), rows)
end

--- What's drawn is drawn again: the planks and spines kept, the shelves on screen.
function Theme.changed()
    for _k, v in pairs(Theme.images or {}) do if v and v.bb then v.bb:free() end end
    for _k, v in pairs(Theme.planks or {}) do if v then v:free() end end
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

--- Every ornament there is: { { path, aspect, name, label, tall, season, when } },
--- GZreader's first, then the reader's own files by name. Looked up once
--- (Theme.changed forgets).
function Theme.list()
    if Theme.found then return Theme.found end
    local out = {}
    for _i, def in ipairs(Theme.BUILT_IN) do
        local path = root .. "/icons/shelf/" .. def.file
        local aspect = Theme.aspectOf(path)
        if aspect then
            out[#out + 1] = { path = path, aspect = aspect, name = def.file, label = def.label, tall = def.tall, season = def.season, when = def.when }
        end
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
            if aspect then out[#out + 1] = { path = path, aspect = aspect, name = names[i], label = (names[i]:gsub("%.[^%.]+$", "")), own = true } end
        end
    end
    Theme.found = out
    return out
end

--- Today as month, day (Theme.today can stand in: tests).
function Theme.date()
    if Theme.today then return Theme.today[1], Theme.today[2] end
    local t = os.date("*t")
    return t.month, t.day
end

--- Is month, day within season { m1, d1, m2, d2 } (it may run over New Year)?
function Theme.inSeason(season, month, day)
    if not season then return true end
    local now, from, to = month * 100 + day, season[1] * 100 + season[2], season[3] * 100 + season[4]
    if from <= to then return now >= from and now <= to end
    return now >= from or now <= to
end

local function chosen()
    local t = G_reader_settings and G_reader_settings:readSetting(Theme.CHOSEN)
    return type(t) == "table" and t or {}
end

--- Does `entry` stand on the shelves now? Ticked or unticked by hand: that;
--- else a seasonal one in its season, the others always.
function Theme.isOn(entry)
    local by_hand = chosen()[entry.name]
    if by_hand ~= nil then return by_hand == true end
    local month, day = Theme.date()
    return Theme.inSeason(entry.season, month, day)
end

function Theme.setOn(entry, on)
    local t = {}
    for k, v in pairs(chosen()) do t[k] = v end
    t[entry.name] = on and true or false
    G_reader_settings:saveSetting(Theme.CHOSEN, t)
    Theme.changed()
end

--- The seasonal ones back to their seasons, the others back on.
function Theme.resetChosen()
    G_reader_settings:saveSetting(Theme.CHOSEN, {})
    Theme.changed()
end

--- The ornaments standing now, and those of them in their season (not
--- ticked by hand: those stand all year, like the others).
function Theme.standing()
    local on, seasonal = {}, {}
    local by_hand = chosen()
    for _i, e in ipairs(Theme.list()) do
        if Theme.isOn(e) then
            on[#on + 1] = e
            if e.season and by_hand[e.name] == nil then seasonal[#seasonal + 1] = e end
        end
    end
    return on, seasonal
end

local function hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

--- The ornament for a page (`seed`: the same page, the same ornaments) and
--- its place among the page's ornaments (`nth`: 1, 2, 3…), or nil. A page's
--- ornaments differ from each other while there are enough; in their
--- season the seasonal ones take FAVOUR places of FAVOUR + 1.
function Theme.pick(seed, nth)
    nth = nth or 1
    local on, seasonal = Theme.standing()
    if #on == 0 then return nil end
    -- (the hash's low digits follow the seed's last letter: taken from higher up)
    local h = math.floor(hash(seed) / 131)
    if #seasonal == 0 or #seasonal == #on then return on[(h + nth) % #on + 1] end
    local regular = {}
    for _i, e in ipairs(on) do
        local s = false
        for _j, x in ipairs(seasonal) do if x == e then s = true end end
        if not s then regular[#regular + 1] = e end
    end
    local function festive(j) return (j + h) % (Theme.FAVOUR + 1) ~= 0 end
    -- how many seasonal ones the page has had by this place (no more than there are)
    local had = 0
    for j = 1, nth - 1 do if festive(j) and had < #seasonal then had = had + 1 end end
    if festive(nth) and had < #seasonal then return seasonal[(h + had) % #seasonal + 1] end
    return regular[(h + nth - 1 - had) % #regular + 1]
end

--- The size `entry` stands at beside books `stand_h` tall, in `free_w` of
--- room: w, h; nil when it doesn't fit (it's never squeezed under 2/3).
function Theme.size(entry, stand_h, free_w)
    local h = math.floor(stand_h * (entry.tall or Theme.HEIGHT))
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

--- The room a shelf keeps for an ornament when it keeps any (Theme.keeps),
--- for books `stand_h` tall: the widest one standing now.
function Theme.reserve(stand_h)
    if Theme.ornaments() == "off" then return 0 end
    local list = Theme.standing()
    if #list == 0 then return 0 end
    local widest = 0
    for _i, e in ipairs(list) do widest = math.max(widest, math.min((e.tall or Theme.HEIGHT) * e.aspect, Theme.HEIGHT)) end
    return math.floor(stand_h * widest) + 2 * S(Theme.MARGIN)
end

Theme.images = {}

--- How many rows at the foot of a picture are empty (transparent): an
--- ornament stands on its lowest drawn row, not on its picture's edge
--- (Bookshelf's two leave a margin there).
function Theme.emptyFoot(bb)
    local w, h = bb:getWidth(), bb:getHeight()
    local step = math.max(1, math.floor(w / 48))
    for y = h - 1, math.max(0, h - math.floor(h / 3)), -1 do
        for x = 0, w - 1, step do
            local c = bb:getPixel(x, y)
            local alpha = c and c.alpha
            if alpha == nil or alpha > 40 then return h - 1 - y end
        end
    end
    return 0
end

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
        for k, v in pairs(Theme.images) do if v then v.bb:free() end; Theme.images[k] = nil end
    end
    local got = false
    if ok and bb then
        local okf, foot = pcall(Theme.emptyFoot, bb)
        got = { bb = bb, foot = okf and foot or 0 }
    end
    Theme.images[key] = got
    return got or nil
end

--- The ornament for a place (`seed`) if it fits in `free_w` beside books
--- `stand_h` tall: { entry, img, w, h, foot, room (the width it takes with
--- its margins) }, or nil.
function Theme.plan(seed, free_w, stand_h, nth)
    if Theme.ornaments() == "off" then return nil end
    local entry = Theme.pick(seed, nth)
    if not entry then return nil end
    local w, h = Theme.size(entry, stand_h, free_w)
    if not w then return nil end
    local got = image(entry, w, h)
    if not got then return nil end
    local iw, ih = got.bb:getWidth(), got.bb:getHeight()
    return { entry = entry, img = got.bb, w = iw, h = ih - got.foot, foot = got.foot, room = iw + 2 * S(Theme.MARGIN) }
end

--- Paint a planned ornament with its left edge at x, standing on the board
--- at board_y (its lowest drawn row where the books' feet are).
function Theme.paintPlanned(bb, plan, x, board_y)
    local img = plan.img
    local y = board_y - plan.h
    local Blitbuffer = require("ffi/blitbuffer")
    local t = img:getType()
    if t == Blitbuffer.TYPE_BBRGB32 or t == Blitbuffer.TYPE_BB8A then
        bb:alphablitFrom(img, x, y, 0, 0, plan.w, plan.h)
    else
        bb:blitFrom(img, x, y, 0, 0, plan.w, plan.h)
    end
    -- where it touches the board
    bb:darkenRect(x + math.floor(plan.w * 0.12), board_y, math.floor(plan.w * 0.76), S(2), 0.30)
    return { x = x, y = y, w = plan.w, h = plan.h }
end

--- Stand an ornament at the right end of the free room from `left` to
--- `right`, for books `stand_h` tall. Returns its place or nil.
function Theme.paintOrnament(bb, seed, left, right, board_y, stand_h, nth)
    local plan = Theme.plan(seed, right - left, stand_h, nth)
    if not plan then return nil end
    return Theme.paintPlanned(bb, plan, right - S(Theme.MARGIN) - plan.w, board_y)
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
    do
        local where = {}
        for _i, pl in ipairs({ { "home", _("On Home") }, { "downloads", _("In Downloads") }, { "catalog", _("In the Catalog") } }) do
            where[#where + 1] = {
                text = pl[2],
                checked_func = function() return Theme.placeOn(pl[1]) end,
                callback = function() Theme.setPlace(pl[1], not Theme.placeOn(pl[1])) end,
            }
        end
        where[#where].separator = true
        for _i, c in ipairs({ { 1, _("One on a page") }, { 2, _("Up to two on a page") }, { 3, _("Up to three on a page") }, { "all", _("One on every shelf") } }) do
            where[#where + 1] = {
                text = c[2],
                radio = true,
                checked_func = function() return Theme.count() == (c[1] == "all" and math.huge or c[1]) end,
                callback = function() Theme.setCount(c[1]) end,
            }
        end
        where[#where].separator = true
        for _i, sd in ipairs({ { "right", _("At the right end of the shelf") }, { "left", _("At the left end of the shelf") },
                { "scattered", _("Scattered: right, then left, then right") } }) do
            where[#where + 1] = {
                text = sd[2],
                radio = true,
                checked_func = function() return Theme.side() == sd[1] end,
                callback = function() Theme.setSide(sd[1]) end,
            }
        end
        items[#items + 1] = {
            text = _("Where and how many"),
            help_text = _("Which screens have ornaments, how many a page has at most (a page's lowest shelves with books get them), and which end of the shelf they stand at. In the Catalog they stand in a ledge's free place, on the right."),
            sub_item_table = where,
        }
    end
    items[#items + 1] = {
        text = _("Which ornaments"),
        help_text = _("Tick the ones that may stand on the shelves. A seasonal one stands in its season; tick it to have it all year, untick it to never have it."),
        sub_item_table_func = function()
            local which = {}
            for _i, e in ipairs(Theme.list()) do
                which[#which + 1] = {
                    text_func = function()
                        if e.season and chosen()[e.name] == nil then
                            return e.label .. " (" .. e.when .. ")"
                        end
                        return e.label
                    end,
                    checked_func = function() return Theme.isOn(e) end,
                    callback = function() Theme.setOn(e, not Theme.isOn(e)) end,
                }
            end
            which[#which].separator = true
            which[#which + 1] = {
                text = _("Seasonal ones in their season again"),
                keep_menu_open = true,
                callback = function(touchmenu)
                    Theme.resetChosen()
                    if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                end,
            }
            return which
        end,
    }
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
