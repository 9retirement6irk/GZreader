--[[--
The Grimmory tab's first page as a bookshop (the Bookshelf view,
common/gz_view.lua; the other views keep the list):

- a search slip pinned to the wall;
- two display ledges with covers face out: Continue reading (a ribbon and
  how far you are) and Recently added (a "new" tag), each ending in a tied
  bundle of spines that opens the whole list;
- a bookcase bay below, a compartment each for All books, Libraries,
  Shelves, Authors, Series and Audiobooks (Downloaded books on Kindles
  without a speaker), each with a card clipped to it: its name, how many,
  its letter. What stands in it says what it is: spines, spines between
  bookends, a book face out, letter dividers, piles lying flat, tapes.

The page draws the browser's own root items (gzreader_browser.lua,
rootItems: each has a gz_id), so a letter opens what it opened in the list
(the Menu's shortcuts: Q search, W Continue reading, E Recently added, R All
books, T Libraries, Y Shelves, U Authors, I Series, O Downloaded books,
P Audiobooks). The 5-way moves between the slip, the covers and the
compartments; Press or a tap opens. Covers come from gzreader_covers.lua;
the two lists are Grimmory's (kept like the list views keep them,
gzreader_listcache.lua) and fetched again each time the tab opens.

Counts come from what GZreader already keeps (the library index, the saved
lists): nothing is fetched for them. Magic shelves are only counted; their
rules are never shown.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local Shop = {
    COLS = 5,            -- a ledge: four covers and the bundle
    SHOWN = 4,           -- covers on a ledge
    LIST_LIMIT = 30,     -- what Grimmory is asked for (as the list views)
}

local function Shelf() return require("modules/filebrowser/patches/home/widgets/shelf") end

local function hand(size)
    local ok, Sticky = pcall(require, "gzreader_sticky")
    if ok and Sticky.hand then return Sticky.hand(size) end
    return Font:getFace("cfont", size)
end

local function hash(s)
    local h = 5381
    s = tostring(s or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

---------------------------------------------------------------- when

--- The Bookshelf view?
function Shop.bookshelf()
    local ok, on = pcall(function() return require("common/gz_view").isBookshelf() end)
    return ok and on == true
end

--- The Grimmory tab's root in the bookshelf view?
function Shop.applies(m)
    if type(m) ~= "table" or type(m.item_table) ~= "table" or not m.item_table.gz_root then return false end
    return Shop.bookshelf()
end

---------------------------------------------------------------- where things go

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

--- Where everything goes in a w x h page (px; s = the screen's scale
--- function). Pure: tested in run_tests.lua.
function Shop.layout(w, h, s)
    s = s or S
    local L = { w = w, h = h }
    local pad = s(12)
    L.slip = { x = pad, y = s(6), w = w - 2 * pad, h = s(30) }
    local cell_h = clamp(math.floor(h * 0.12), s(60), s(100))
    local top_b, side_b, gap = s(8), s(3), s(7)
    local case_h = top_b + 3 * cell_h + side_b
    L.case = { x = s(10), y = h - case_h - s(2), w = w - 2 * s(10), h = case_h, top = top_b, side = side_b, gap = gap }
    -- the two ledges share what's left
    local sign_h, ledge_h = s(24), s(10)
    local y = L.slip.y + L.slip.h + s(8)
    local fixed = sign_h + s(6) + ledge_h + s(8)
    local cover_h = math.floor((L.case.y - s(4) - y - 2 * fixed) / 2)
    local cgap = s(12)
    local col_w = math.floor((w - 2 * pad - (Shop.COLS - 1) * cgap) / Shop.COLS)
    local extra = s(6) + s(5) -- the pages and shadow behind a cover (shelf.lua paintBook: PAGES + 5)
    local box_w = col_w - extra
    local box_h = math.min(cover_h - extra, math.floor(box_w * 1.6))
    L.ledges = {}
    for i = 1, 2 do
        local sign = { x = pad, y = y, h = sign_h }
        local area_top = y + sign_h + s(6)
        local ledge = { x = s(8), y = area_top + cover_h, w = w - 2 * s(8), h = ledge_h }
        local cols = {}
        for c = 1, Shop.COLS do
            cols[c] = { x = pad + (c - 1) * (col_w + cgap), w = col_w }
        end
        L.ledges[i] = { sign = sign, top = area_top, cover_h = cover_h, box_w = box_w, box_h = box_h, cols = cols, ledge = ledge }
        y = ledge.y + ledge_h + s(8)
    end
    -- too short a page (landscape on a small screen): the list instead
    L.fits = box_h >= s(40) and box_w >= s(30)
    -- the compartments: two columns, three rows
    local inner_x = L.case.x + side_b
    local inner_w = L.case.w - 2 * side_b
    local cell_w = math.floor((inner_w - gap) / 2)
    L.cells = {}
    for r = 1, 3 do
        for c = 1, 2 do
            L.cells[#L.cells + 1] = {
                x = inner_x + (c - 1) * (cell_w + gap), y = L.case.y + top_b + (r - 1) * cell_h,
                w = cell_w, h = cell_h,
            }
        end
    end
    L.cell_h = cell_h
    return L
end

---------------------------------------------------------------- what goes where

--- The compartments, in order: { id, kind } (the kind says what stands in
--- it). Audiobooks only where there's a speaker; Downloaded books otherwise.
function Shop.compartments(audio)
    return {
        { id = "all", kind = "spines" },
        { id = "libraries", kind = "bookends" },
        { id = "shelves", kind = "faceout" },
        { id = "authors", kind = "dividers" },
        { id = "series", kind = "piles" },
        -- (no speaker: no audiobooks; an empty compartment, cobwebs in it)
        audio and { id = "audiobooks", kind = "tapes" } or { kind = "empty" },
    }
end

local function thousands(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
Shop.thousands = thousands

local function countOf(map)
    local n = 0
    for _k, _v in pairs(type(map) == "table" and map or {}) do n = n + 1 end
    return n
end

--- What a compartment's card says under its name. `known`: what GZreader
--- keeps (index = the library index, libraries / shelves / audiobooks = the
--- saved lists, downloaded = how many books are on the Kindle). Pure.
function Shop.cardText(id, known)
    known = known or {}
    local idx = known.index
    if id == "all" then
        return idx and tonumber(idx.total) and T(_("%1 books"), thousands(idx.total)) or _("A–Z")
    elseif id == "libraries" then
        local counts = idx and idx.libraries or nil
        local names, n = {}, 0
        for _i, lib in ipairs(type(known.libraries) == "table" and known.libraries or {}) do
            if type(lib) == "table" and lib.id and (not counts or (tonumber(counts[tostring(lib.id)]) or 0) > 0) then
                n = n + 1
                if type(lib.name) == "string" then names[#names + 1] = lib.name end
            end
        end
        if n == 0 and counts then
            for _k, c in pairs(counts) do if (tonumber(c) or 0) > 0 then n = n + 1 end end
        end
        if n == 0 then return _("by library") end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        local list = names[1] and (names[1] .. (names[2] and (", " .. names[2]) or "") .. (names[3] and "…" or "")) or nil
        return list and (tostring(n) .. " · " .. list) or (n == 1 and _("1 library") or T(_("%1 libraries"), n))
    elseif id == "shelves" then
        local n, magic = 0, 0
        for _i, sh in ipairs(type(known.shelves) == "table" and known.shelves or {}) do
            if type(sh) == "table" and sh.id then
                n = n + 1
                if sh.magic then magic = magic + 1 end
            end
        end
        if n == 0 then return _("yours and magic") end
        if magic > 0 then return T(_("%1 · %2 magic"), n, magic) end
        return n == 1 and _("1 shelf") or T(_("%1 shelves"), n)
    elseif id == "authors" then
        local n = idx and countOf(idx.authors) or 0
        return n > 0 and T(_("%1 · A–Z"), thousands(n)) or _("A–Z")
    elseif id == "series" then
        -- (series of two books or more: the list doesn't show the others)
        local n = 0
        for _k, sr in pairs(idx and idx.series or {}) do
            if type(sr) ~= "table" or (tonumber(sr.count) or 0) >= 2 then n = n + 1 end
        end
        return n > 0 and (n == 1 and _("1 series") or T(_("%1 series"), thousands(n))) or _("in order")
    elseif id == "audiobooks" then
        local n = tonumber(known.audiobooks)
        return n and n > 0 and (n == 1 and _("1 audiobook") or T(_("%1 audiobooks"), thousands(n))) or _("M4B and MP3")
    elseif id == "downloaded" then
        local n = tonumber(known.downloaded) or 0
        return n > 0 and T(_("%1 on this Kindle"), n) or _("on this Kindle")
    end
    return ""
end

--- The books a ledge shows: readable ones (as the list views), in order.
function Shop.ledgeBooks(list, readable)
    local out = {}
    for _i, b in ipairs(type(list) == "table" and list or {}) do
        if type(b) == "table" and b.id and (not readable or readable(b)) then out[#out + 1] = b end
    end
    return out
end

--- The bundle's tag: "+N more", or "See all" when they're all on the ledge.
function Shop.moreText(total)
    local more = (tonumber(total) or 0) - Shop.SHOWN
    return more > 0 and T(_("+%1 more"), more) or _("See all")
end

---------------------------------------------------------------- the lists (cached, fetched)

local function cacheKey(browser, what)
    local store = browser.plugin.store or {}
    return tostring(store.server) .. "|" .. tostring(store.username) .. "|" .. what
end

local ENDPOINT = { continue = "continue-reading", recent = "recently-added" }

--- The two ledges' books now (saved copies), and a fresh fetch once per
--- visit; the page is drawn again when it's back.
function Shop.lists(browser)
    local st = browser._shop or {}
    browser._shop = st
    local Cache = require("gzreader_listcache")
    for id, ep in pairs(ENDPOINT) do
        if st[id] == nil then st[id] = Cache.get(cacheKey(browser, "simple:" .. ep)) end
    end
    if not st.asked then
        st.asked = true
        Shop.fetch(browser)
    end
    return st
end

function Shop.fetch(browser)
    local st = browser._shop
    if not (browser.api and browser.api.isPaired and browser.api:isPaired()) then return end
    local Net = require("gzreader_net")
    local function go()
        st.loading = true
        local api = browser.api
        require("gzreader_async").run(api, function()
            return { continue = api:continueReading(Shop.LIST_LIMIT),
                recent = api:simpleList(ENDPOINT.recent, Shop.LIST_LIMIT) }
        end, function(res)
            st.loading = false
            if type(res) == "table" then
                local Cache = require("gzreader_listcache")
                for id, ep in pairs(ENDPOINT) do
                    if type(res[id]) == "table" then
                        st[id] = res[id]
                        Cache.put(cacheKey(browser, "simple:" .. ep), res[id])
                    end
                end
            end
            st.fetched = true
            local m = browser.menu
            if m and not browser.closed and Shop.applies(m) then pcall(m.updateItems, m) end
        end, "bookshop")
    end
    if Net.connected() then return go() end
    Net.run(go, { quiet = true, reason = "Grimmory tab", usb = true })
end

--- What the cards count (nothing fetched: what GZreader keeps).
function Shop.known(browser)
    -- (kept a minute: it read three saved lists and checked every downloaded
    -- file each time the front page was drawn, on every return to it)
    local st = browser._shop or {}
    browser._shop = st
    if st.known and os.time() - (st.known_at or 0) < Shop.KNOWN_SECONDS then return st.known end
    local known = Shop.readKnown(browser)
    st.known, st.known_at = known, os.time()
    return known
end
Shop.KNOWN_SECONDS = 60

function Shop.readKnown(browser)
    local Cache = require("gzreader_listcache")
    local known = {}
    pcall(function() known.index = require("gzreader_index").load(browser.plugin.store) end)
    known.libraries = Cache.get(cacheKey(browser, "libraries"))
    known.shelves = Cache.get(cacheKey(browser, "shelves"))
    local ab = Cache.get(cacheKey(browser, "audiobooks"))
    known.audiobooks = type(ab) == "table" and tonumber(ab.totalElements) or nil
    local lfs = require("libs/libkoreader-lfs")
    local n = 0
    for _id, e in pairs(browser.plugin.store and browser.plugin.store.downloads or {}) do
        if type(e) == "table" and e.path and lfs.attributes(e.path, "mode") == "file" then n = n + 1 end
    end
    known.downloaded = n
    return known
end

---------------------------------------------------------------- something you can pick

local Hot = InputContainer:extend{ menu = nil, entry = nil, rect = nil }

function Hot:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = 0, h = 0 }
    local range = function() return self.dimen end
    self.ges_events = {
        TapShop = { GestureRange:new{ ges = "tap", range = range } },
        HoldShop = { GestureRange:new{ ges = "hold", range = range } },
    }
end

function Hot:getSize() return Geom:new{ w = self.dimen.w, h = self.dimen.h } end
function Hot:paintTo() end -- (the page paints it)

function Hot:onTapShop()
    if not self.entry then return true end
    local menu, entry = self.menu, self.entry
    UIManager:nextTick(function() menu:onMenuSelect(entry) end)
    return true
end

function Hot:onHoldShop()
    if self.entry and self.menu.onMenuHold then self.menu:onMenuHold(self.entry) end
    return true
end

local function redraw(menu, shop)
    UIManager:setDirty(menu.show_parent, function()
        return "ui", shop and shop.dimen or menu.dimen
    end)
end

function Hot:onFocus() self.focused = true; redraw(self.menu, self.shop); return true end
function Hot:onUnfocus() self.focused = false; redraw(self.menu, self.shop); return true end

---------------------------------------------------------------- painting bits

local function gray(v) return Blitbuffer.gray(math.max(0, math.min(1, v))) end

local function text(bb, str, face, x, y, opts)
    opts = opts or {}
    local TextWidget = require("ui/widget/textwidget")
    local tw = TextWidget:new{ text = str, face = face, bold = opts.bold, fgcolor = opts.color, max_width = opts.max_width }
    local sz = tw:getSize()
    if opts.center then x = x - math.floor(sz.w / 2) end
    if opts.middle then y = y - math.floor(sz.h / 2) end
    tw:paintTo(bb, x, y)
    tw:free()
    return sz
end

local function badge(bb, menu, letter, x, y, side)
    if not (letter and menu.is_enable_shortcut) then return 0 end
    side = side or S(20)
    local Menu = require("ui/widget/menu")
    local ok, icon = pcall(Menu.getItemShortCutIcon, nil, Geom:new{ w = side, h = side }, letter, "square")
    if not (ok and icon) then return 0 end
    bb:paintRect(x, y, side, side, Blitbuffer.COLOR_WHITE)
    icon:paintTo(bb, x, y)
    if icon.free then icon:free() end
    return side
end

local function focusRing(bb, r)
    local o = S(4)
    bb:paintBorder(r.x - o, r.y - o, r.w + 2 * o, r.h + 2 * o, math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
end

--- A clip (bulldog clip seen from the front) centred at cx on y.
local function clip(bb, cx, y, w)
    local h = S(8)
    local x = cx - math.floor(w / 2)
    for i = 0, h - 1 do bb:paintRect(x, y - h + i + S(2), w, 1, gray(0.3 + 0.35 * i / h)) end
    bb:paintBorder(x, y - h + S(2), w, h, 1, gray(0.85))
end

--- The wall: white with faint boards.
local function paintWall(bb, x, y, w, h)
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    local step = S(48)
    for sx = x + step, x + w - 1, step do bb:paintRect(sx, y, math.max(1, S(2)), h, gray(0.06)) end
end

local function paintSign(bb, menu, sign, label, count, letter)
    local face = hand(20)
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = face, fgcolor = Blitbuffer.COLOR_WHITE }
    local c = count and TextWidget:new{ text = count, face = Font:getFace("cfont", 11), fgcolor = gray(0.2) } or nil
    local side = (letter and menu.is_enable_shortcut) and S(20) or 0
    local inner = S(8) + (side > 0 and side + S(8) or 0) + t:getSize().w + (c and (S(8) + c:getSize().w) or 0) + S(12)
    local x, y, h = sign.x, sign.y, sign.h
    bb:paintRect(x + S(3), y + S(3), inner, h, gray(0.25)) -- its shadow
    bb:paintRect(x, y, inner, h, gray(0.82))
    bb:paintBorder(x, y, inner, h, math.max(2, S(3)), gray(0.45))
    local cx = x + S(8)
    if side > 0 then badge(bb, menu, letter, cx, y + math.floor((h - side) / 2), side); cx = cx + side + S(8) end
    t:paintTo(bb, cx, y + math.floor((h - t:getSize().h) / 2))
    cx = cx + t:getSize().w + S(8)
    if c then c:paintTo(bb, cx, y + math.floor((h - c:getSize().h) / 2)); c:free() end
    t:free()
    return { x = x, y = y, w = inner, h = h }
end

local function paintLedge(bb, r)
    for i = 0, r.h - 1 do bb:paintRect(r.x, r.y + i, r.w, 1, gray(0.10 + 0.32 * i / r.h)) end
    bb:paintBorder(r.x, r.y, r.w, r.h, math.max(1, S(1)), gray(0.85))
    -- its shadow on the wall, and the covers' on its top
    for i = 0, S(4) - 1 do bb:darkenRect(r.x + S(4), r.y + r.h + i, r.w - S(8), 1, 0.35 * (1 - i / S(4))) end
end

--- A ribbon hanging from a cover's top edge at x (a notch at its end).
local function ribbon(bb, x, y, w, h, color)
    local notch = math.floor(w / 2)
    for i = 0, h - 1 do
        if i < h - notch then
            bb:paintRect(x, y + i, w, 1, color)
        else
            local k = i - (h - notch)
            bb:paintRect(x, y + i, notch - k, 1, color)
            bb:paintRect(x + w - (notch - k), y + i, notch - k, 1, color)
        end
    end
end

--- A cover-sized stand-in: a shade, the title and author.
local function standIn(book, w, h)
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local shades = { 0.75, 0.15, 0.45, 0.6 }
    local shade = shades[(hash(book.id) % #shades) + 1]
    local ink = shade >= 0.5 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    local tw = w - S(12)
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    local group = VerticalGroup:new{ align = "center",
        TextBoxWidget:new{ text = book.title or "?", face = Font:getFace("cfont", 13), bold = true, width = tw,
            alignment = "center", fgcolor = ink, height = math.floor(h * 0.6), height_adjust = true, height_overflow_show_ellipsis = true },
        VerticalSpan:new{ width = S(4) },
        TextBoxWidget:new{ text = authors, face = Font:getFace("cfont", 10), width = tw, alignment = "center", fgcolor = ink,
            height = math.floor(h * 0.25), height_adjust = true, height_overflow_show_ellipsis = true },
    }
    return FrameContainer:new{ width = w, height = h, padding = 0, margin = 0, bordersize = 1,
        color = Blitbuffer.COLOR_BLACK, background = gray(shade),
        CenterContainer:new{ dimen = Geom:new{ w = w - 2, h = h - 2 }, group } }
end

--- A tied bundle of spines with a tag, in the column `col` standing on y.
local function paintBundle(bb, col, bottom, h, label, seed)
    local n, sw = 5, math.max(S(10), math.floor(col.w / 8))
    local total = n * sw + (n - 1)
    local x = col.x + math.floor((col.w - total) / 2)
    local shades = { 0.75, 0.15, 0.55, 0.3, 0.85, 0.45 }
    for k = 1, n do
        local sh = math.floor(h * (0.78 + ((hash(seed .. k) % 20) / 100)))
        local sx = x + (k - 1) * (sw + 1)
        bb:paintRect(sx, bottom - sh, sw, sh, gray(shades[(hash(seed .. k) % #shades) + 1]))
        Shelf().shadeRound(bb, sx, bottom - sh, sw, sh, 0.8)
        bb:paintBorder(sx, bottom - sh, sw, sh, 1, gray(0.9))
    end
    -- the twine round them, and the tag on it
    local ty = bottom - math.floor(h * 0.45)
    bb:paintRect(x - S(2), ty, total + S(4), math.max(2, S(2)), Blitbuffer.COLOR_BLACK)
    local TextWidget = require("ui/widget/textwidget")
    local t = TextWidget:new{ text = label, face = hand(16), max_width = col.w + S(10) }
    local tsz = t:getSize()
    local tw, th = tsz.w + S(12), tsz.h + S(4)
    local tx, tyy = col.x + math.floor((col.w - tw) / 2), ty - math.floor(th / 2)
    bb:paintRect(tx + S(2), tyy + S(2), tw, th, gray(0.35))
    bb:paintRect(tx, tyy, tw, th, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(tx, tyy, tw, th, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    t:paintTo(bb, tx + S(6), tyy + S(2))
    t:free()
    return { x = math.min(x, tx), y = bottom - h, w = math.max(total, tw), h = h }
end

---------------------------------------------------------------- the compartments' contents

local SPINE_SHADES = { 0.78, 0.12, 0.55, 0.3, 0.88, 0.45, 0.2, 0.65 }

local function spine(bb, x, bottom, w, h, seed)
    local shade = SPINE_SHADES[(hash(seed) % #SPINE_SHADES) + 1]
    bb:paintRect(x, bottom - h, w, h, gray(shade))
    -- two bands near the top
    local band = shade >= 0.5 and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    bb:paintRect(x, bottom - h + S(6), w, 1, band)
    bb:paintRect(x, bottom - h + S(9), w, 1, band)
    Shelf().shadeRound(bb, x, bottom - h, w, h, 0.8)
    bb:paintBorder(x, bottom - h, w, h, 1, gray(0.9))
end

local function spines(bb, x, bottom, room_w, max_h, seed, count)
    local spans, k = {}, 0
    while true do
        k = k + 1
        local hv = hash(seed .. ":" .. k)
        local w = S(10) + hv % S(5)
        if (count and k > count) or x + w > room_w then break end
        local h = math.floor(max_h * (0.72 + (math.floor(hv / 7) % 26) / 100))
        spine(bb, x, bottom, w, h, seed .. k)
        spans[#spans + 1] = { x = x, w = w, h = h }
        x = x + w + 1
    end
    return x, spans
end

local function bookend(bb, x, bottom, h)
    local w = S(6)
    bb:paintRect(x, bottom - h, w, h, gray(0.6))
    bb:paintRect(x - S(3), bottom - S(3), w + S(6), S(3), gray(0.7))
    bb:paintBorder(x, bottom - h, w, h, 1, gray(0.9))
    return x + w + S(4)
end

local function divider(bb, x, bottom, h, letter)
    local w = S(22)
    bb:paintRect(x, bottom - h, w, h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, bottom - h, w, h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    text(bb, letter, Font:getFace("cfont", 13), x + math.floor(w / 2), bottom - h + S(4), { bold = true, center = true })
    return x + w + S(3)
end

local function flatPile(bb, cx, bottom, n, seed)
    local y = bottom
    for k = 1, n do
        local hv = hash(seed .. "p" .. k)
        local w = S(36) + hv % S(14)
        local h = S(8)
        local x = cx - math.floor(w / 2) + (math.floor(hv / 11) % S(7)) - S(3)
        bb:paintRect(x, y - h, w, h, gray(SPINE_SHADES[(hv % #SPINE_SHADES) + 1]))
        bb:darkenRect(x, y - S(2), w, S(2), 0.3)
        bb:lightenRect(x, y - h, w, S(2), 0.3)
        bb:paintBorder(x, y - h, w, h, 1, gray(0.9))
        -- the pages' edge on the right
        bb:paintRect(x + w - S(3), y - h + S(2), S(2), h - S(4), gray(0.08))
        y = y - h
    end
end

local function tapePile(bb, cx, bottom, n, seed)
    local y = bottom
    for k = 1, n do
        local hv = hash(seed .. "t" .. k)
        local w, h = S(38), S(11)
        local x = cx - math.floor(w / 2) + (hv % S(5)) - S(2)
        bb:paintRect(x, y - h, w, h, gray(SPINE_SHADES[(hv % #SPINE_SHADES) + 1]))
        bb:lightenRect(x, y - h, w, S(3), 0.35)
        bb:paintBorder(x, y - h, w, h, 1, gray(0.9))
        y = y - h - 1
    end
end

--- A cassette seen from the front (w x h) with its top-left at x, y.
local function cassette(bb, x, y, w, h)
    bb:paintRoundedRect(x, y, w, h, gray(0.72), S(4))
    bb:paintBorder(x, y, w, h, 1, gray(0.95), S(4))
    local lx, ly, lw, lh = x + S(5), y + S(4), w - S(10), math.floor(h * 0.55)
    bb:paintRect(lx, ly, lw, lh, gray(0.05))
    local r = math.max(S(4), math.floor(lh * 0.28))
    for _i, hx in ipairs({ lx + math.floor(lw * 0.28), lx + math.floor(lw * 0.72) }) do
        bb:paintCircle(hx, ly + math.floor(lh / 2), r, Blitbuffer.COLOR_BLACK)
        bb:paintCircle(hx, ly + math.floor(lh / 2), r - math.max(1, S(2)), Blitbuffer.COLOR_WHITE)
    end
    -- the head opening at the bottom
    local hw = math.floor(w * 0.5)
    for i = 0, S(7) - 1 do
        local inset = math.floor((S(7) - i) * S(3) / S(7))
        bb:paintRect(x + math.floor((w - hw) / 2) - S(3) + inset, y + h - S(7) + i, hw + 2 * S(3) - 2 * inset, 1, gray(0.85))
    end
end

local function miniCover(bb, x, bottom, w, h, label)
    bb:darkenRect(x + S(3), bottom - h + S(3), w, h - S(3), 0.3)
    bb:paintRect(x, bottom - h, w, h, gray(0.8))
    bb:paintBorder(x, bottom - h, w, h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    Shelf().shadeRound(bb, x, bottom - h, S(5), h, 0.8)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local tb = TextBoxWidget:new{ text = label, face = Font:getFace("cfont", 9), bold = true, width = w - S(9),
        fgcolor = Blitbuffer.COLOR_WHITE, bgcolor = gray(0.8), height = h - S(8), height_adjust = true, height_overflow_show_ellipsis = true }
    tb:paintTo(bb, x + S(6), bottom - h + S(4))
    tb:free()
    return x + w + S(6)
end

--- What stands in a compartment, in the room left of its card.
local function paintContents(bb, kind, room, info)
    local x, bottom, right, h = room.x, room.bottom, room.right, room.h
    local sd = info.seed or "" -- (lists: each compartment its own books)
    local spans = {}
    if kind == "spines" then
        local _, sp = spines(bb, x, bottom, right, h, sd .. "all")
        spans = sp
    elseif kind == "bookends" then
        local groups = math.max(1, math.min(3, info.libraries or 3))
        local per = math.max(2, math.floor(11 / groups))
        for g = 1, groups do
            local nx, sp = spines(bb, x, bottom, right - S(12), h * 0.95, sd .. "lib" .. g, per)
            for _i, s in ipairs(sp) do spans[#spans + 1] = s end
            x = nx + S(2)
            if g < groups and x + S(14) < right then x = bookend(bb, x, bottom, math.floor(h * 0.7)) end
        end
    elseif kind == "faceout" then
        local cw = math.min(S(42), math.floor(h * 0.62))
        x = miniCover(bb, x, bottom, cw, math.floor(h * 0.86), info.shelf_name or _("Shelves"))
        local _, sp = spines(bb, x, bottom, right, h * 0.95, sd .. "shelf")
        spans = sp
    elseif kind == "dividers" then
        local letters = info.letters or { "A", "M" }
        for g, l in ipairs(letters) do
            x = divider(bb, x, bottom, math.floor(h * 0.98), l)
            local nx, sp = spines(bb, x, bottom, right, h * 0.82, sd .. "au" .. g, 4)
            for _i, s in ipairs(sp) do spans[#spans + 1] = s end
            x = nx + S(2)
        end
    elseif kind == "piles" then
        local pw = S(52)
        local n = 0
        while x + pw <= right and n < 3 do
            n = n + 1
            flatPile(bb, x + math.floor(pw / 2), bottom, 3 + (hash("pile" .. n) % 4), "pile" .. n)
            x = x + pw + S(4)
        end
    elseif kind == "tapes" then
        local cw = math.min(S(64), math.floor((right - x) * 0.45))
        local ch = math.floor(cw * 0.63)
        cassette(bb, x, bottom - ch - S(2), cw, ch)
        x = x + cw + S(8)
        local n = 0
        while x + S(42) <= right and n < 2 do
            n = n + 1
            tapePile(bb, x + S(20), bottom, 4 + n, "tp" .. n)
            x = x + S(46)
        end
    elseif kind == "downloaded" then
        local _, sp = spines(bb, x, bottom, right, h, "dl")
        spans = sp
        -- a bookmark in the first one
        if sp[1] then
            local s = sp[1]
            bb:paintRect(s.x + math.floor(s.w / 2) - S(2), bottom - s.h - S(10), S(4), S(14), Blitbuffer.COLOR_BLACK)
        end
    end
    if #spans > 0 then pcall(Shelf().paintDepth, bb, bottom, spans) end
end

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }

function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

local function coverImage(book, w, h)
    local Covers = require("gzreader_covers")
    local img = Covers.image(book.id, nil, w, h)
    if img then
        local ImageWidget = require("ui/widget/imagewidget")
        return ImageWidget:new{ image = img, image_disposable = false }, img:getWidth(), img:getHeight()
    end
    return standIn(book, w, h), w, h
end

function Page:paintLedge(bb, ox, oy, i, L)
    local menu = self.menu
    local led = L.ledges[i]
    local spec = self.ledges[i]
    local sr = paintSign(bb, menu, { x = ox + led.sign.x, y = oy + led.sign.y, h = led.sign.h }, spec.label, spec.count, spec.letter)
    spec.sign_hot.dimen = Geom:new(sr)
    if spec.sign_hot.focused then focusRing(bb, sr) end
    local ledge = { x = ox + led.ledge.x, y = oy + led.ledge.y, w = led.ledge.w, h = led.ledge.h }
    local bottom = ledge.y
    local Sh = Shelf()
    local p = S(Sh.PAGES)
    if #spec.books == 0 then
        local msg = spec.loading and _("Fetching from Grimmory…") or spec.empty
        text(bb, msg, hand(20), ox + math.floor(L.w / 2), bottom - math.floor(led.cover_h / 2), { center = true, middle = true, color = gray(0.7) })
    end
    for c, item in ipairs(spec.items) do
        local col = led.cols[c]
        local cx = ox + col.x
        if item.book then
            local widget, iw, ih = coverImage(item.book, led.box_w, led.box_h)
            local x = cx + math.floor((col.w - iw - p) / 2)
            local y = bottom - ih - p
            Sh.paintBook(bb, widget, x, y, iw, ih)
            if widget.free then widget:free() end
            item.hot.dimen = Geom:new{ x = x, y = y, w = iw, h = ih }
            if spec.kind == "continue" then
                -- a ribbon, and how far you are on a strip at the bottom
                ribbon(bb, x + iw - S(16), y - S(2), S(9), math.min(S(26), math.floor(ih * 0.25)), Blitbuffer.COLOR_BLACK)
                local pct = tonumber(item.book.readProgress)
                if pct then
                    local sh = S(16)
                    local sy = y + ih - sh - S(3)
                    local sx, sw = x + S(8), iw - S(12)
                    bb:paintRect(sx, sy, sw, sh, Blitbuffer.COLOR_WHITE)
                    bb:paintBorder(sx, sy, sw, sh, 1, Blitbuffer.COLOR_BLACK)
                    local TextWidget = require("ui/widget/textwidget")
                    local lt = TextWidget:new{ text = T("%1%", math.floor(pct + 0.5)), face = Font:getFace("cfont", 10), bold = true }
                    local lsz = lt:getSize()
                    lt:paintTo(bb, sx + sw - S(3) - lsz.w, sy + math.floor((sh - lsz.h) / 2))
                    lt:free()
                    local bw = sw - lsz.w - S(12)
                    if bw > S(10) then
                        local by = sy + math.floor(sh / 2) - S(2)
                        bb:paintBorder(sx + S(4), by, bw, S(5), 1, Blitbuffer.COLOR_BLACK)
                        bb:paintRect(sx + S(4), by, math.floor(bw * math.max(0, math.min(100, pct)) / 100), S(5), Blitbuffer.COLOR_BLACK)
                    end
                end
            else
                -- a "new" tag on the top corner
                local TextWidget = require("ui/widget/textwidget")
                local t = TextWidget:new{ text = _("NEW"), face = Font:getFace("cfont", 9), bold = true, fgcolor = Blitbuffer.COLOR_WHITE }
                local tsz = t:getSize()
                local tx, ty = x + iw - tsz.w - S(8), y + S(4)
                bb:paintRect(tx - S(3), ty, tsz.w + S(6), tsz.h, Blitbuffer.COLOR_BLACK)
                t:paintTo(bb, tx, ty)
                t:free()
            end
            if item.hot.focused then focusRing(bb, item.hot.dimen) end
        else
            local r = paintBundle(bb, { x = cx, w = col.w }, bottom, led.box_h, item.label, spec.kind)
            item.hot.dimen = Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
            if item.hot.focused then focusRing(bb, item.hot.dimen) end
        end
    end
    paintLedge(bb, ledge)
end

--- A compartment of the bookcase (x, y, w, h): its back, its board, what
--- stands in it and its card (spec = { kind, name, sub, letter, hot }).
--- kind "empty": nothing, cobwebs in its corners.
function Shop.paintCompartment(bb, menu, x, y, w, h, spec, info)
    -- the back of the compartment, darker at the top (the shelf above's shadow)
    bb:paintRect(x, y, w, h, gray(0.1))
    for i = 0, S(6) - 1 do bb:darkenRect(x, y + i, w, 1, 0.4 * (1 - i / S(6))) end
    local board_h = S(10)
    local by = y + h - board_h
    for i = 0, board_h - 1 do bb:paintRect(x, by + i, w, 1, gray(0.62 - 0.2 * i / board_h)) end
    bb:paintRect(x, by, w, math.max(2, S(3)), gray(0.25))
    if spec.kind == "empty" then
        local Sh = Shelf()
        local r = math.min(S(70), math.floor((h - board_h) * 0.75))
        if Sh.cobweb then
            Sh.cobweb(bb, x + 1, y + 1, 1, 1, r)
            Sh.cobweb(bb, x + w - 2, by - 1, -1, -1, math.floor(r * 0.7))
        end
        return
    end
    -- the card on the right, as wide as its name (an author's full name:
    -- 1.22.2 cut long ones off), at most most of the compartment
    local TextWidget = require("ui/widget/textwidget")
    local probe = TextWidget:new{ text = spec.name or "", face = hand(19) }
    local name_w = probe:getSize().w
    probe:free()
    local card_w = math.max(math.min(S(118), math.floor(w * 0.44)), math.min(name_w + S(16), math.floor(w * 0.72)))
    local card_h = math.min(h - S(18), S(62))
    local cx, cy = x + w - card_w - S(6), by - card_h
    -- what stands in it, left of the card
    paintContents(bb, spec.kind, { x = x + S(8), bottom = by, right = cx - S(8), h = math.min(h - S(12), S(70)) }, info or {})
    bb:paintRect(cx + S(3), cy + S(3), card_w, card_h, gray(0.35))
    bb:paintRect(cx, cy, card_w, card_h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(cx, cy, card_w, card_h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    clip(bb, cx + math.floor(card_w / 2), cy, S(20))
    local name_sz = text(bb, spec.name or "", hand(19), cx + S(7), cy + S(4), { max_width = card_w - S(12) })
    local side = (spec.letter and menu.is_enable_shortcut) and S(20) or 0
    text(bb, spec.sub or "", Font:getFace("cfont", 10), cx + S(7), cy + S(5) + name_sz.h,
        { color = gray(0.8), max_width = card_w - S(12) - (side > 0 and side + S(4) or 0) })
    if side > 0 then badge(bb, menu, spec.letter, cx + card_w - side - S(5), cy + card_h - side - S(5), side) end
    if spec.hot then
        spec.hot.dimen = Geom:new{ x = x, y = y, w = w, h = h }
        if spec.hot.focused then
            bb:paintBorder(cx - S(4), cy - S(4), card_w + S(8), card_h + S(8), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
        end
    end
end

function Page:paintCell(bb, ox, oy, k, L)
    local cell = L.cells[k]
    local spec = self.cells[k]
    if not spec then return end
    Shop.paintCompartment(bb, self.menu, ox + cell.x, oy + cell.y, cell.w, cell.h, spec, self.info)
end

function Page:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local L = self.L
    local menu = self.menu
    paintWall(bb, x, y, self.w, self.h)
    -- the search slip
    local s = L.slip
    local sx, sy = x + s.x, y + s.y
    bb:paintRect(sx + S(2), sy + S(3), s.w, s.h, gray(0.3))
    bb:paintRect(sx, sy, s.w, s.h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(sx + S(4), sy + s.h - S(8), s.w - S(8), 1, gray(0.25))
    bb:paintBorder(sx, sy, s.w, s.h, math.max(1, S(1)), Blitbuffer.COLOR_BLACK)
    clip(bb, sx + math.floor(s.w / 2), sy, S(28))
    local r = math.floor(s.h * 0.2)
    local mx, my = sx + S(12) + r, sy + math.floor(s.h / 2) - S(2)
    bb:paintCircle(mx, my, r, Blitbuffer.COLOR_BLACK, math.max(2, S(2)))
    for k = 0, math.floor(r * 0.9) do
        bb:paintRect(mx + r - S(1) + k, my + r - S(1) + k, math.max(2, S(3)), math.max(2, S(3)), Blitbuffer.COLOR_BLACK)
    end
    local side = (self.search_letter and menu.is_enable_shortcut) and S(20) or 0
    text(bb, _("Search titles, authors, series…"), hand(20), mx + r + S(14), sy + math.floor(s.h / 2),
        { middle = true, color = gray(0.6), max_width = s.w - S(60) - side })
    if side > 0 then badge(bb, menu, self.search_letter, sx + s.w - side - S(8), sy + math.floor((s.h - side) / 2), side) end
    self.search_hot.dimen = Geom:new{ x = sx, y = sy, w = s.w, h = s.h }
    if self.search_hot.focused then focusRing(bb, self.search_hot.dimen) end
    -- the ledges
    for i = 1, 2 do self:paintLedge(bb, x, y, i, L) end
    -- the bookcase
    local c = L.case
    local cx, cy = x + c.x, y + c.y
    bb:paintRect(cx + S(4), cy + S(4), c.w, c.h, gray(0.25))
    bb:paintRect(cx, cy, c.w, c.h, gray(0.86))
    for i = 0, c.top - 1 do bb:paintRect(cx - S(2), cy + i, c.w + S(4), 1, gray(0.7 + 0.15 * i / c.top)) end
    for k = 1, #L.cells do self:paintCell(bb, x, y, k, L) end
end

---------------------------------------------------------------- shared with the lists' views

Shop.Hot = Hot
Shop.draw = {
    gray = gray, text = text, badge = badge, focusRing = focusRing, clip = clip, wall = paintWall,
    sign = paintSign, ledge = paintLedge, ribbon = ribbon, bundle = paintBundle, spine = spine,
    spines = spines, flatPile = flatPile, tapePile = tapePile, cassette = cassette, cover = coverImage,
    hand = hand, hash = hash,
}

---------------------------------------------------------------- building it

local function entryById(m)
    local by = {}
    for i, e in ipairs(m.item_table) do
        if type(e) == "table" and e.gz_id then by[e.gz_id] = { entry = e, idx = i } end
    end
    return by
end

local function letterOf(m, idx)
    local per = m.perpage or #m.item_table
    if not idx or idx > per or not m.is_enable_shortcut then return nil end
    return m.item_shortcuts and m.item_shortcuts[idx]
end

--- Draw the bookshop in place of the root list (m: the browser's Menu).
function Shop.build(m, browser, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    -- one page, whatever the lists before it used (tiles: 9 a page)
    if m.items_per_page ~= #m.item_table then
        m.items_per_page = #m.item_table
        no_recalculate_dimen = false
    end
    m:_recalculateDimen(no_recalculate_dimen)
    local W = m.item_dimen.w
    -- (one page: its page numbers aren't shown, the bookshop takes their room)
    local H = m.available_height
    pcall(function()
        local Size = require("ui/size")
        H = H + math.max(m.page_return_arrow:getSize().h, m.page_info_text:getSize().h) + Size.padding.button
    end)
    local L = Shop.layout(W, H)
    if not L.fits then return false end
    local by = entryById(m)
    local Covers = require("gzreader_covers")
    Covers.beginPage()
    local page = Page:new{ w = W, h = H, L = L, menu = m }
    local function hot(entry)
        local h = Hot:new{ menu = m, entry = entry, shop = page }
        page[#page + 1] = h
        return h
    end
    -- the slip
    local search = by.search
    page.search_hot = hot(search and search.entry)
    page.search_letter = search and letterOf(m, search.idx)
    m.layout[1] = { page.search_hot }
    -- the ledges
    local st = Shop.lists(browser)
    local wanted = {}
    page.ledges = {}
    for i, id in ipairs({ "continue", "recent" }) do
        local root = by[id]
        local books = Shop.ledgeBooks(st[id], browser.isReadable or require("gzreader_browser").isReadable)
        local spec = {
            kind = id,
            label = id == "continue" and _("Continue reading") or _("Recently added"),
            count = #books > 0 and tostring(#books) or nil,
            letter = root and letterOf(m, root.idx),
            books = books, items = {},
            loading = st.loading and not st.fetched,
            empty = id == "continue" and _("Nothing in progress yet") or _("Nothing new yet"),
        }
        spec.sign_hot = hot(root and root.entry)
        local row = {}
        for k = 1, math.min(Shop.SHOWN, #books) do
            local book = books[k]
            local entry = browser:bookItem(book)
            local item = { book = book, hot = hot(entry) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
            wanted[#wanted + 1] = { id = book.id }
        end
        if #books > 0 then
            local item = { label = Shop.moreText(#books), hot = hot(root and root.entry) }
            spec.items[#spec.items + 1] = item
            row[#row + 1] = item.hot
        end
        if #row == 0 then row[1] = spec.sign_hot end
        m.layout[#m.layout + 1] = row
        page.ledges[i] = spec
    end
    -- the compartments
    local known = Shop.known(browser)
    local idx = known.index
    local info = {}
    do
        local libs = 0
        for _k, c in pairs(idx and idx.libraries or {}) do if (tonumber(c) or 0) > 0 then libs = libs + 1 end end
        info.libraries = libs > 0 and libs or nil
        for _i, sh in ipairs(type(known.shelves) == "table" and known.shelves or {}) do
            if type(sh) == "table" and type(sh.name) == "string" and not sh.magic then info.shelf_name = sh.name; break end
        end
        local names = {}
        for name in pairs(idx and idx.authors or {}) do names[#names + 1] = name end
        if #names > 1 then
            table.sort(names, function(a, b) return a:lower() < b:lower() end)
            local first = names[1]:sub(1, 1):upper()
            local mid = names[math.floor(#names / 2) + 1]:sub(1, 1):upper()
            if first:match("%a") and mid:match("%a") then info.letters = first ~= mid and { first, mid } or { first } end
        end
    end
    page.info = info
    page.cells = {}
    local names = {
        all = _("All books"), libraries = _("Libraries"), shelves = _("Shelves"), authors = _("Authors"),
        series = _("Series"), audiobooks = _("Audiobooks"), downloaded = _("Downloaded"),
    }
    local audio = by.audiobooks ~= nil
    local row
    for k, comp in ipairs(Shop.compartments(audio)) do
        local spec = { kind = comp.kind }
        if comp.id then
            local root = by[comp.id]
            spec.name, spec.sub, spec.letter = names[comp.id], Shop.cardText(comp.id, known), root and letterOf(m, root.idx)
            spec.hot = hot(root and root.entry)
        end
        page.cells[k] = spec
        if k % 2 == 1 then row = {}; m.layout[#m.layout + 1] = row end
        if spec.hot then row[#row + 1] = spec.hot end
    end
    page.L = L
    table.insert(m.item_group, page)
    m._gz_shop = page
    -- start on the first cover (or what's there); back from a list: on
    -- what opened it
    local fx, fy = 1, m.layout[2] and 2 or 1
    local back = m._gz_shop_last or (select_number and m.item_table[select_number])
    if back then
        for y, r in ipairs(m.layout) do
            for x, h in ipairs(r) do
                if h.entry == back then fx, fy = x, y end
            end
        end
    end
    m:updatePageInfo(fy)
    if fx > 1 and Device:hasDPad() then m:moveFocusTo(fx, fy) end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    -- covers not on the Kindle yet: fetch them, then draw the page again
    local items = m.item_table
    Covers.fetch(browser.plugin, wanted, function(got)
        if got > 0 and m.item_table == items and not m._gz_closed and Shop.applies(m) then pcall(m.updateItems, m) end
    end)
end

--- Take over the browser's root page in the bookshelf view.
function Shop.apply(browser)
    local m = browser.menu
    if not m or m._gz_bookshop then return end
    m._gz_bookshop = true
    local orig_update = m.updateItems
    m.updateItems = function(menu, select_number, no_recalculate_dimen)
        if Shop.applies(menu) and not menu._gz_shop_failed then
            local ok, res = pcall(Shop.build, menu, browser, select_number, no_recalculate_dimen)
            if ok and res ~= false then return end
            local err = res
            if not ok then
                require("gzreader_log").warn("bookshop:", tostring(err))
                menu._gz_shop_failed = true
            end
        end
        menu._gz_shop = nil
        -- the lists: in the bookshop's style too (gzreader_shopviews.lua)
        local kind = Shop.bookshelf() and not menu._gz_view_failed and require("gzreader_shopviews").kindOf(menu.item_table)
        if kind then
            local ok, res = pcall(require("gzreader_shopviews").build, menu, browser, kind, select_number, no_recalculate_dimen)
            if ok and res then return end
            if not ok then
                require("gzreader_log").warn("bookshop list:", tostring(res))
                menu._gz_view_failed = true
            end
        end
        menu._gz_view = nil
        return orig_update(menu, select_number, no_recalculate_dimen)
    end
    -- what's opened from it (a tap, Press or its letter): back from it, the
    -- focus is on it again
    local orig_select = m.onMenuSelect
    m.onMenuSelect = function(menu, item, ...)
        if menu._gz_shop then menu._gz_shop_last = item end
        return orig_select(menu, item, ...)
    end
    -- (it was drawn as a list before this: draw it again)
    if Shop.applies(m) then pcall(m.updateItems, m) end
end

return Shop
