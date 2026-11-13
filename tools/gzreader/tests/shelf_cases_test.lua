-- Downloads → Audiobooks and Music in the Bookshelf view
-- (gzreader_shelfview.lua): every tape and CD faces out with its cover, its
-- name on a plate on the shelf under it; a tap opens it (nothing turns), no
-- room is kept for a turned book, and every page's cases fit their shelves.
--   luajit shelf_cases_test.lua <repo>
local REPO = arg[1] or "../../.."
local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local HOME = "/mnt/us/GZreader"
_G.G_reader_settings = { readSetting = function(_s, k) if k == "home_dir" then return HOME end end }

---------------------------------------------------------------- stand-ins

local log -- what was painted: { op, ... }
local function rec(op) return function(_s, ...) log[#log + 1] = { op, ... } end end
local bbclass = {}
for _i, op in ipairs({ "paintRect", "paintBorder", "darkenRect", "lightenRect", "paintRoundedRect", "paintCircle",
        "alphablitFrom", "blitFrom", "fill", "free" }) do bbclass[op] = rec(op) end
bbclass.getWidth = function() return 600 end
bbclass.__index = bbclass
local function newBB() return setmetatable({}, bbclass) end

local function class(base)
    local c = base or {}
    c.extend = function(self, o) o = o or {}; o.__index = o; return setmetatable(o, { __index = self }) end
    c.new = function(self, o) o = setmetatable(o or {}, self); if o.init then o:init() end; return o end
    c.__index = c
    return c
end

local Geom = {}
Geom.__index = Geom
function Geom:new(o) return setmetatable(o or {}, Geom) end
function Geom:copy() return Geom:new{ x = self.x, y = self.y, w = self.w, h = self.h } end
function Geom:combine(o)
    local x, y = math.min(self.x, o.x), math.min(self.y, o.y)
    return Geom:new{ x = x, y = y, w = math.max(self.x + self.w, o.x + o.w) - x, h = math.max(self.y + self.h, o.y + o.h) - y }
end

local TextWidget = class()
function TextWidget:getSize()
    return { w = math.min(#(self.text or "") * 6, self.max_width or 1e9), h = 15 }
end
function TextWidget:paintTo(_bb, x, y) log[#log + 1] = { "text", self.text, x, y, self.max_width } end
function TextWidget:free() end

local covers_made = 0
local spines_made = 0
local ticks = {}
local stubs = {
    ["ffi/blitbuffer"] = { COLOR_WHITE = "white", COLOR_BLACK = "black", COLOR_LIGHT_GRAY = "lightgray",
        TYPE_BB8 = 1, gray = function(v) return v end, new = function() return newBB() end },
    ["device"] = { screen = { scaleBySize = function(_s, v) return v end, getWidth = function() return 600 end,
        getHeight = function() return 800 end } },
    ["ui/font"] = { getFace = function() return {} end },
    ["ui/geometry"] = Geom,
    ["ui/gesturerange"] = { new = function(_s, o) return o end },
    ["ui/widget/container/inputcontainer"] = class(),
    ["ui/widget/container/widgetcontainer"] = class(),
    ["ui/widget/textwidget"] = TextWidget,
    ["ui/uimanager"] = { setDirty = function() end, nextTick = function(_s, f) ticks[#ticks + 1] = f end,
        scheduleIn = function() end },
    ["gettext"] = setmetatable({}, { __call = function(_s, s) return s end }),
    ["libs/libkoreader-lfs"] = { attributes = function() return nil end },
    ["docsettings"] = { findCustomMetadataFile = function() return nil end },
    ["bookinfomanager"] = { getBookInfo = function(_s, path)
        return { title = "T:" .. path:match("([^/]+)%.epub$"), has_cover = true }
    end, extractInBackground = function() return false end },
    ["gzreader_touch"] = { dx = function() return false end },
    ["common/gz_view"] = { isBookshelf = function() return true end },
    ["common/cover_utils"] = { getRatio = function() return 2 / 3 end },
    ["modules/filebrowser/patches/home/widgets/cover_common"] = {
        uniform_dims = function(w, h) return w, h end,
        make_cover_widget = function(book, w, h)
            covers_made = covers_made + 1
            return { book = book, getSize = function() return { w = w, h = h } end,
                paintTo = function(_s, _bb, x, y) log[#log + 1] = { "cover", book.path, x, y, w, h } end,
                free = function() end }
        end,
    },
    ["modules/filebrowser/patches/home/widgets/shelf"] = {
        BOARD_H = 14, UNDER_H = 6, MIN_SPINE = 44, MAX_SPINE = 58, PAGES = 6,
        look = function() return { w = 50, h = 120, shade = 0.4 } end,
        newSpine = function(book)
            spines_made = spines_made + 1
            return { paintTo = function(_s, _bb, x, y) log[#log + 1] = { "spine", book.path, x, y } end }
        end,
        paintBoard = function() end, paintDepth = function() end, shadeRound = function() end,
        paintBook = function(_bb, cover, x, y) log[#log + 1] = { "book", cover.book.path, x, y } end,
    },
}
for n, v in pairs(stubs) do package.preload[n] = function() return v end end
package.path = REPO .. "/plugins/gzreader.koplugin/?.lua;" .. package.path

local okv, View = pcall(require, "gzreader_shelfview")
check(okv, "the shelf view loads " .. (okv and "" or tostring(View)))
if not okv then print(pass .. " passed, " .. fail .. " failed"); os.exit(1) end

local function entries(folder, n)
    local t = {}
    for i = 1, n do
        local p = HOME .. "/" .. folder .. "/" .. folder:sub(1, 1) .. i .. ".epub"
        t[i] = { is_file = true, path = p, text = p:match("([^/]+)$") }
    end
    return t
end

local function menuFor(items)
    local menu = { name = "filemanager", item_table = items, inner_dimen = { w = 600, h = 700 }, page = 1,
        item_group = {}, show_parent = {}, dimen = Geom:new{ x = 0, y = 0, w = 600, h = 700 } }
    function menu:onMenuSelect(e) self.opened = e end
    function menu.updateItems() end
    View.recalculateDimen(menu)
    View.buildUI(menu)
    return menu
end

local function paintAll(menu)
    log = {}
    local y = 0
    for _i, row in ipairs(menu.item_group) do
        row:paintTo(newBB(), 0, y)
        y = y + row.h
    end
    return log
end

local function itemsOf(menu)
    local t = {}
    for _i, row in ipairs(menu.item_group) do
        for _j, it in ipairs(row.items) do t[#t + 1] = { it = it, row = row } end
    end
    return t
end

---------------------------------------------------------------- what turns

print("Which lists have something that turns")
do
    local tapes, cds = entries("Audiobooks", 3), entries("Music", 3)
    check(View.caseOf(tapes[1]) == "tape" and View.caseOf(cds[1]) == "cd", "stand-ins in Audiobooks are tapes, in Music CDs")
    check(View.caseOf({ is_file = true, path = HOME .. "/Books/Audiobooks/x.epub" }) == nil, "an Audiobooks folder elsewhere: books")
    check(not View.anyTurns(tapes) and not View.anyTurns(cds), "Audiobooks, Music: nothing turns")
    check(not View.anyTurns({ { is_file = false, path = HOME .. "/Folder", text = "Folder/" } }), "only folders: nothing turns")
    local mixed = entries("Audiobooks", 2)
    mixed[3] = { is_file = true, path = HOME .. "/Book.epub", text = "Book.epub" }
    check(View.anyTurns(mixed), "a book on the list: it turns")
    check(View.anyTurns({ { is_file = false, path = HOME .. "/S", series_items = { mixed[3] } } }), "a series: it turns")
    check(not View.TURNS.tape and not View.TURNS.cd and View.CASES.tape and View.CASES.cd, "tapes and CDs never turn")
end

---------------------------------------------------------------- pages

print("Audiobooks: every tape faces out, with its cover and its name under it")
do
    covers_made, spines_made = 0, 0
    local items = entries("Audiobooks", 14)
    local menu = menuFor(items)
    check(View.no_turn == true, "no room kept for a turned book")
    local all_fit = true
    for first = 0, #items - 1, menu.perpage do
        if not View.pageFits(items, first, menu.perpage, menu._gz_rows, menu._gz_row_h, menu._gz_width) then all_fit = false end
    end
    check(menu.perpage >= 3 and all_fit, "every page's tapes fit on its shelves (" .. menu.perpage .. " a page)")
    local painted = paintAll(menu)
    local shown = itemsOf(menu)
    check(#shown == math.min(#items, menu.perpage), "the page's tapes are all on its shelves (" .. #shown .. ")")
    local hidden, plates_ok, covers_ok = 0, true, true
    for _i, s in ipairs(shown) do
        local it, row = s.it, s.row
        if it.hidden then hidden = hidden + 1 end
        local board_y = row.dimen.y + row.h - 14 - 6
        local plate, cover
        for _j, op in ipairs(painted) do
            if op[1] == "text" and op[2] == it.book.title and op[4] > board_y then plate = op end
            if op[1] == "cover" and op[2] == it.entry.path and op[4] < board_y then cover = op end
        end
        if not plate or plate[5] > it.w then plates_ok = false end
        if not cover then covers_ok = false end
    end
    check(hidden == 0, "none hidden for want of room")
    check(covers_ok, "each tape shows its cover")
    check(plates_ok, "each tape's title on a plate on the shelf under it, no wider than the tape")
    check(spines_made == 0, "no spines drawn for tapes")
    local first = shown[1].it
    check(first.dimen.h > first.face_h, "a tap on the plate counts as on the tape")
    -- the covers are kept between repaints (a 5-way step repaints the shelf)
    local before = covers_made
    paintAll(menu)
    check(covers_made == before, "covers kept between repaints, not made again")

    -- a tap opens it straight away
    ticks = {}
    first:onTapShelfItem()
    for _i, f in ipairs(ticks) do f() end
    check(menu.opened == first.entry and menu._gz_picked == nil, "a tap opens the audiobook (no turning first)")
    -- the 5-way's one has a frame
    local function frames(p)
        local n = 0
        for _i, op in ipairs(p) do if op[1] == "paintBorder" and op[7] == "black" then n = n + 1 end end
        return n
    end
    local plain = frames(paintAll(menu))
    first:onFocus()
    check(menu._gz_picked == nil and first.focused, "the 5-way on a tape: nothing turns")
    check(frames(paintAll(menu)) == plain + 2, "the 5-way's tape has a frame")
    first:onUnfocus()
end

print("Music: every CD faces out, with its cover and its name under it")
do
    covers_made, spines_made = 0, 0
    local items = entries("Music", 9)
    local menu = menuFor(items)
    local painted = paintAll(menu)
    local shown = itemsOf(menu)
    local ok = #shown > 0
    for _i, s in ipairs(shown) do
        local plate, cover
        for _j, op in ipairs(painted) do
            if op[1] == "text" and op[2] == s.it.book.title then plate = op end
            if op[1] == "cover" and op[2] == s.it.entry.path then cover = op end
        end
        if s.it.hidden or not plate or not cover then ok = false end
    end
    check(ok and spines_made == 0, "each CD: its cover, its title under it, no spine (" .. #shown .. " on the page)")
end

print("Downloads with books: as before")
do
    covers_made, spines_made = 0, 0
    local items = {}
    for i = 1, 6 do items[i] = { is_file = true, path = HOME .. "/B" .. i .. ".epub", text = "B" .. i .. ".epub" } end
    local menu = menuFor(items)
    check(View.no_turn == false, "room kept for the turned book")
    paintAll(menu)
    check(spines_made == 6 and covers_made == 0, "books stand as spines")
    local it = itemsOf(menu)[1].it
    it:onTapShelfItem()
    check(menu._gz_picked == it.idx and menu.opened == nil, "a tap on a book turns it (a second one opens it)")
    covers_made = 0
    paintAll(menu)
    check(covers_made == 1, "the turned book shows its cover")
end

print(pass .. " passed, " .. fail .. " failed")
os.exit(fail == 0 and 0 or 1)
