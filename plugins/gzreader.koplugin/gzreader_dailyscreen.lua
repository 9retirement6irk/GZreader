--[[--
The daily paper on the screen (the edition itself: gzreader_daily.lua).

- On Home's bookshelf: a folded newspaper on its side among the books, at
  the start of the first shelf. Picked (a tap, the 5-way) it turns to show
  its front page small (the name, the date, the lead headline), as a book
  shows its cover; a second tap (a press) opens the paper. ZenOS's
  shelf.lua asks for it through __GZ_SHELF_PAPER.
- Optional, off: Home's "Daily paper" widget, a wider folded newspaper with
  the headlines as a row above the books.
- The paper: laid out as a newspaper. The nameplate and the date, the lead
  story across the page, the others in columns (2, or 3 on a wide screen),
  each with its section, headline, source and how it begins; more pages
  behind (swipe, the page keys, or the arrows at the foot). A tap on a story
  (the 5-way: move the frame, press) opens it as text to page through, with
  a QR code of its link for the rest of it on a phone.
- Settings → Home → Daily paper: on/off, on the bookshelf, as a row, the feeds.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

local function Daily() return require("gzreader_daily") end

local Paper = {
    HOME_SIZE = "m",
    MAX_HEADLINES = 6,
}

local function info(text, timeout) UIManager:show(InfoMessage:new{ text = text, timeout = timeout }) end

---------------------------------------------------------------- words

--- "Tuesday, November 17".
function Paper.dateText(t)
    return (os.date("%A, %B %d", t or os.time()):gsub(" 0(%d)$", " %1"))
end

--- "7:05" (the Kindle's clock).
function Paper.timeText(t)
    return (os.date("%H:%M", t):gsub("^0", ""))
end

--- What the paper says about itself under the headlines / beside Refresh.
function Paper.statusText(plugin, now)
    local D = Daily()
    now = now or os.time()
    local edition = D.load()
    if D.refreshing then return _("fetching today's paper…") end
    if not edition then
        if D.last_error then return _("couldn't fetch the paper") end
        return _("comes when Wi-Fi is on")
    end
    if edition.day ~= D.day(now) then
        return T(_("from %1"), Paper.dateText(edition.at))
    end
    return T(_("%1 stories · %2"), D.count(edition), Paper.timeText(edition.at))
end

---------------------------------------------------------------- type

local function face(file, size, fallback)
    local ok, f = pcall(Font.getFace, Font, file, size)
    if ok and f then return f end
    return Font:getFace(fallback or "smallinfofont", size)
end
local function serifBold(size) return face("NotoSerif-Bold.ttf", size, "smallinfofontbold") end
local function serif(size) return face("NotoSerif-Regular.ttf", size, "smallinfofont") end
local function serifItalic(size) return face("NotoSerif-Italic.ttf", size, "smallinfofont") end

--- A widget drawn by a function: paint(bb, x, y).
local function drawn(w, h, paint)
    return {
        dimen = Geom:new{ w = w, h = h },
        getSize = function(self) return self.dimen end,
        handleEvent = function() return false end,
        free = function() end,
        paintTo = function(_self, bb, x, y) paint(bb, x, y) end,
    }
end

--- A story's picture `w` wide: scaled to that width, and cut to `max_h`
--- when it's taller (a little off the top, more off the bottom). nil when
--- the file can't be drawn.
function Paper.pictureWidget(path, w, max_h)
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        local src = RenderImage:renderImageFile(path, false)
        if not src then return nil end
        local sw, sh = src:getWidth(), src:getHeight()
        if sw < 8 or sh < 8 then src:free(); return nil end
        local tw, th = Paper.pictureSize(sw, sh, w)
        return RenderImage:scaleBlitBuffer(src, tw, th, true)
    end)
    if not ok or not bb then return nil end
    local h = math.min(bb:getHeight(), max_h)
    local off = math.floor((bb:getHeight() - h) / 3)
    local pic = drawn(w, h, function(out, x, y)
        if not bb then return end
        out:blitFrom(bb, x, y, 0, off, w, h)
        out:paintBorder(x, y, w, h, 1, Blitbuffer.COLOR_GRAY)
    end)
    pic.free = function()
        if bb then bb:free(); bb = nil end
    end
    return pic
end

--- A `sw` × `sh` picture scaled to `w` wide.
function Paper.pictureSize(sw, sh, w)
    return w, math.max(1, math.floor(sh * w / math.max(1, sw) + 0.5))
end

---------------------------------------------------------------- Home's widget

--- Where things go on Home's folded newspaper, w × h: the sheet (with room
--- for its shadow), and how many headlines fit under the lead in 2 columns.
function Paper.homeLayout(w, h, sizes)
    local shadow, pad = sizes.shadow, sizes.pad
    local sheet_w, sheet_h = w - shadow - sizes.margin * 2, h - shadow - sizes.top
    local inner_w = sheet_w - pad * 2
    local body_h = sheet_h - pad * 2 - sizes.mast_h - sizes.rules_h
    local lead = body_h >= sizes.lead_h
    local rest = body_h - (lead and sizes.lead_h or 0)
    local rows = math.max(0, math.min(3, math.floor(rest / sizes.line_h)))
    return { x = sizes.margin, y = sizes.top, w = sheet_w, h = sheet_h, inner_w = inner_w, lead = lead, rows = rows,
        col_w = math.floor((inner_w - sizes.gutter) / 2) }
end

--- The front page for Home (ZenOS's home/components/registry: build(ctx)):
--- a folded newspaper lying on Home, its name across the top, the lead
--- headline, the next ones in two columns.
function Paper.homeWidget(plugin, ctx)
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end
    local D = Daily()

    local w, h = ctx.width, ctx.height
    local now = os.time()
    local on = D.enabled(plugin)
    local edition = on and D.load() or nil

    local mast = TextWidget:new{ text = _("The Daily Paper"), face = serifBold(14) }
    local small = serifItalic(8)
    local date = TextWidget:new{ text = Paper.dateText(now), face = small, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    local status = TextWidget:new{ text = on and Paper.statusText(plugin, now) or _("off: Settings → Home → Daily paper"),
        face = small, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    local lead_face, line_face = serifBold(11), serif(9)
    local probe_lead = TextWidget:new{ text = "Ag", face = lead_face }
    local probe_line = TextWidget:new{ text = "Ag", face = line_face }
    local sizes = {
        shadow = S(3), pad = S(6), margin = S(2), top = S(2), gutter = S(14),
        mast_h = mast:getSize().h, rules_h = S(7), lead_h = probe_lead:getSize().h + S(2), line_h = probe_line:getSize().h,
    }
    probe_lead:free(); probe_line:free()
    local L = Paper.homeLayout(w, h, sizes)
    -- (keyboard Kindles: the row's letter key is drawn in its top left corner)
    local key_w = (Device:hasKeyboard() and G_reader_settings and G_reader_settings:nilOrTrue("gzreader_tab_key_hints")) and S(24) or 0
    local side_w = math.max(10, math.floor((L.inner_w - mast:getSize().w) / 2) - S(6))
    date:setMaxWidth(side_w - key_w)
    status:setMaxWidth(side_w)

    local texts = {}
    local front = D.front(edition, (L.lead and 1 or 0) + L.rows * 2)
    local lead = L.lead and front[1] and TextWidget:new{ text = front[1].title, face = lead_face, max_width = L.inner_w } or nil
    for i = (lead and 2 or 1), #front do
        texts[#texts + 1] = TextWidget:new{ text = front[i].title, face = line_face, max_width = L.col_w }
    end
    local empty
    if #front == 0 then
        empty = TextWidget:new{ face = serifItalic(10), max_width = L.inner_w, fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            text = not on and _("Turn the daily paper on in Settings.") or D.refreshing and _("Fetching today's paper…")
                or _("No paper yet. It's fetched once a day, when Wi-Fi is on.") }
    end

    local sheet = drawn(w, h, function(bb, x, y)
        local sx, sy = x + L.x, y + L.y
        -- the pages under the top one, then the sheet
        bb:paintRect(sx + sizes.shadow, sy + sizes.shadow, L.w, L.h, Blitbuffer.COLOR_GRAY)
        bb:paintRect(sx + 1, sy + 1, L.w, L.h, Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(sx, sy, L.w, L.h, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(sx, sy, L.w, L.h, 1, Blitbuffer.COLOR_DARK_GRAY)
        local ix, iy = sx + sizes.pad, sy + sizes.pad
        mast:paintTo(bb, ix + math.floor((L.inner_w - mast:getSize().w) / 2), iy)
        local side_y = iy + sizes.mast_h - date:getSize().h - S(2)
        date:paintTo(bb, ix + key_w, side_y)
        status:paintTo(bb, ix + L.inner_w - status:getSize().w, side_y)
        local ry = iy + sizes.mast_h + S(1)
        bb:paintRect(ix, ry, L.inner_w, S(2), Blitbuffer.COLOR_BLACK)
        bb:paintRect(ix, ry + S(3), L.inner_w, 1, Blitbuffer.COLOR_BLACK)
        local by = iy + sizes.mast_h + sizes.rules_h
        if empty then
            empty:paintTo(bb, ix + math.floor((L.inner_w - empty:getSize().w) / 2), by + S(4))
            return
        end
        if lead then
            lead:paintTo(bb, ix, by)
            by = by + sizes.lead_h
        end
        if #texts > 0 then
            local rows = math.ceil(#texts / 2)
            bb:paintRect(ix + L.col_w + math.floor(sizes.gutter / 2), by + S(1), 1, rows * sizes.line_h - S(2), Blitbuffer.COLOR_GRAY)
            for i, t in ipairs(texts) do
                local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
                t:paintTo(bb, ix + col * (L.col_w + sizes.gutter), by + row * sizes.line_h)
            end
        end
    end)
    sheet.free = function()
        for _i, t in ipairs(texts) do t:free() end
        for _i, t in ipairs({ mast, date, status, lead, empty }) do if t then t:free() end end
    end

    local function open() Paper.show(plugin) end
    local box = InputContainer:new{ dimen = Geom:new{ w = w, h = h } }
    box[1] = sheet
    if Device:isTouchDevice() then
        box.ges_events = { GzDailyTap = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
        box.onGzDailyTap = function() open(); return true end
    end
    if type(ctx.setWidgetActions) == "function" then ctx.setWidgetActions{ activate = open } end

    -- (the row is drawn again when an edition comes; today's is asked for when it's missing)
    Paper.home = { menu = ctx.menu }
    D.listen("home", Paper.redrawHome)
    if on then UIManager:nextTick(function() pcall(D.maybeRefresh, plugin) end) end
    return box
end

---------------------------------------------------------------- on Home's bookshelf

--- Is the newspaper wanted on Home's bookshelf? (On unless unticked.)
function Paper.onShelf(plugin)
    local D = Daily()
    return D.enabled(plugin) and D.store(plugin).shelf ~= false
end

--- The newspaper's size on a shelf whose books stand in `area_h`: a front
--- page a little lower than the books, as wide as a cover at least.
function Paper.shelfSize(area_h, cover_w)
    local h = math.floor(area_h * 0.8)
    return math.max(math.floor(h * 0.7), math.min(cover_w or 0, math.floor(h * 0.8))), h
end

--- How thick the folded newspaper is, on its side: a fat paper, a fifth as
--- thick as the books are tall.
function Paper.spineWidth(area_h)
    return math.max(24, math.floor(area_h * 0.2))
end

--- … and how tall: nearly as tall as the room the books stand in.
function Paper.spineHeight(area_h)
    return math.floor(area_h * 0.93)
end

--- The newspaper standing among Home's books (ZenOS's shelf.lua asks
--- through __GZ_SHELF_PAPER): { spine, spine_w, h, face, face_w, face_h,
--- open } or nil. On its side until it's picked, as the books are: the fold
--- with the name along it. Picked, its front page small: the name, the date,
--- the lead headline, and columns of grey lines.
function Paper.shelfItem(plugin, ctx, area_h, cover_w)
    if not Paper.onShelf(plugin) then return nil end
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end
    local D = Daily()
    local w, h = Paper.shelfSize(area_h, cover_w)
    local pad, pages = S(4), S(3)
    local sheet_w, sheet_h = w - pages, h - pages
    local inner_w = sheet_w - pad * 2
    local now = os.time()
    local edition = D.load()
    local today = edition and edition.day == D.day(now)

    -- the name as big as fits across the sheet
    local mast
    for size = 12, 5, -1 do
        if mast then mast:free() end
        mast = TextWidget:new{ text = _("The Daily Paper"), face = serifBold(size) }
        if mast:getSize().w <= inner_w then break end
    end
    mast:setMaxWidth(inner_w)
    local date = TextWidget:new{ text = (os.date("%a, %b %d", now):gsub(" 0(%d)$", " %1")), face = serifItalic(6),
        max_width = inner_w, fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    local front = D.front(edition, 1)[1]
    local words = front and front.title or D.refreshing and _("Fetching today's paper…") or _("No paper yet")
    if front and not today then words = front.title end
    local lead_face = serifBold(7)
    local lead = TextBoxWidget:new{ text = words, face = lead_face, width = inner_w, alignment = "left" }
    local max_lines = 4
    if lead:getSize().h > lead:getLineHeight() * max_lines then
        local lh = lead:getLineHeight()
        lead:free()
        lead = TextBoxWidget:new{ text = words, face = lead_face, width = inner_w, alignment = "left",
            height = lh * max_lines, height_adjust = true, height_overflow_show_ellipsis = true }
    end

    local shelf_pic -- (made at the first paint; false: none)
    local widget = drawn(w, h, function(bb, x, y)
        -- the pages behind, then the front page
        bb:paintRect(x + pages, y + pages, sheet_w, sheet_h, Blitbuffer.COLOR_GRAY)
        bb:paintRect(x + math.floor(pages / 2), y + math.floor(pages / 2), sheet_w, sheet_h, Blitbuffer.COLOR_LIGHT_GRAY)
        bb:paintBorder(x + math.floor(pages / 2), y + math.floor(pages / 2), sheet_w, sheet_h, 1, Blitbuffer.COLOR_DARK_GRAY)
        bb:paintRect(x, y, sheet_w, sheet_h, Blitbuffer.COLOR_WHITE)
        bb:paintBorder(x, y, sheet_w, sheet_h, 1, Blitbuffer.COLOR_BLACK)
        local ix, cy = x + pad, y + pad
        mast:paintTo(bb, ix + math.floor((inner_w - mast:getSize().w) / 2), cy)
        cy = cy + mast:getSize().h
        bb:paintRect(ix, cy, inner_w, math.max(2, S(1)), Blitbuffer.COLOR_BLACK)
        cy = cy + math.max(2, S(1)) + 1
        date:paintTo(bb, ix + math.floor((inner_w - date:getSize().w) / 2), cy)
        cy = cy + date:getSize().h
        bb:paintRect(ix, cy, inner_w, 1, Blitbuffer.COLOR_BLACK)
        cy = cy + S(3)
        lead:paintTo(bb, ix, cy)
        cy = cy + lead:getSize().h + S(3)
        -- the rest of the page: two columns of lines, a picture in the first
        local bottom = y + sheet_h - pad
        local gutter = S(4)
        local col_w = math.floor((inner_w - gutter) / 2)
        local step = math.max(3, S(3))
        if bottom - cy >= step * 3 then
            bb:paintRect(ix + col_w + math.floor(gutter / 2), cy, 1, bottom - cy, Blitbuffer.COLOR_GRAY)
            local pic_h = math.min(math.floor(col_w * 0.7), math.floor((bottom - cy) / 2))
            -- (the lead story's own picture, when it has one)
            if shelf_pic == nil then
                local path = front and D.pictures(plugin) and D.picturePath(front.item)
                shelf_pic = path and Paper.pictureWidget(path, col_w, pic_h) or false
            end
            if shelf_pic then
                pic_h = shelf_pic:getSize().h
                shelf_pic:paintTo(bb, ix, cy)
            else
                bb:paintRect(ix, cy, col_w, pic_h, Blitbuffer.COLOR_LIGHT_GRAY)
                bb:paintBorder(ix, cy, col_w, pic_h, 1, Blitbuffer.COLOR_GRAY)
            end
            local n = 0
            for ly = cy, bottom - 1, step do
                n = n + 1
                if ly >= cy + pic_h + step then bb:paintRect(ix, ly, col_w - (n % 5 == 0 and math.floor(col_w / 3) or 0), 1, Blitbuffer.COLOR_GRAY) end
                bb:paintRect(ix + col_w + gutter, ly, col_w - (n % 4 == 0 and math.floor(col_w / 4) or 0), 1, Blitbuffer.COLOR_GRAY)
            end
        end
    end)
    widget.free = function()
        mast:free(); date:free(); lead:free()
        if shelf_pic then shelf_pic:free(); shelf_pic = nil end
    end
    -- on its side: a folded newspaper standing among the books, nearly as
    -- tall as they are and a good deal thicker than a thin book. Seen from
    -- the fold: the front page wrapped round it (its name up the fold, a
    -- rule, the lead headline, a picture and columns of print), the fold's
    -- curve shaded, and behind it the edges of the sheets, none quite as
    -- tall as the next.
    local spine_w, spine_h = Paper.spineWidth(area_h), Paper.spineHeight(area_h)
    local spine_bb
    local spine = drawn(spine_w, spine_h, function(bb, x, y)
        if not spine_bb then
            -- drawn lying down (spine_h wide, spine_w tall; its left end is the
            -- top, its upper edge the fold), then stood up as the books' spines are
            local L = spine_h
            local lying = Blitbuffer.new(L, spine_w, Blitbuffer.TYPE_BB8)
            lying:fill(Blitbuffer.COLOR_WHITE)
            local px1 = math.max(1, S(1))
            local edges = math.max(5, math.floor(spine_w * 0.2))
            local fold_w = spine_w - edges
            -- the sheets' edges: fine lines of uneven grey, their tops stepped
            for ly = fold_w, spine_w - 1 do
                local n = ly - fold_w
                local top = S(4) + ((n * 37 + 11) % 6) * px1
                lying:paintRect(top, ly, L - top, 1, n % 2 == 0 and Blitbuffer.gray(0.30 + ((n * 13) % 4) * 0.09) or Blitbuffer.gray(0.06))
            end
            lying:paintRect(S(4), spine_w - 1, L - S(4), 1, Blitbuffer.gray(0.6))
            lying:paintRect(S(2), fold_w - 1, L - S(2), 1, Blitbuffer.gray(0.5))
            lying:paintRect(S(2), fold_w - 2, L - S(2), 1, Blitbuffer.gray(0.12))
            -- the fold's curve: darker towards its outer edge, its top corner rounded
            local r = math.max(3, S(5))
            local shades = { 0.75, 0.32, 0.2, 0.12, 0.07, 0.03 }
            for k, g in ipairs(shades) do lying:paintRect(r, k - 1, L - r, 1, Blitbuffer.gray(g)) end
            for k = 0, r - 1 do
                local cut = r - math.floor(math.sqrt(math.max(0, r * r - (r - k) * (r - k))) + 0.5)
                lying:paintRect(0, k, cut, 1, Blitbuffer.COLOR_WHITE)
                lying:paintRect(cut, k, px1, 1, Blitbuffer.gray(0.75))
            end
            lying:paintRect(0, r, 1, fold_w - r, Blitbuffer.gray(0.75)) -- (the folded page's top edge)
            -- the front page, wrapped round the fold. Its band of print:
            local band_y, band_h = #shades + S(1), fold_w - #shades - S(4)
            -- the name, as big as the band lets it be
            local name
            for size = 20, 6, -1 do
                if name then name:free() end
                name = TextWidget:new{ text = _("The Daily Paper"), face = serifBold(size) }
                if name:getSize().h <= band_h and name:getSize().w <= math.floor(L * 0.5) then break end
            end
            local ns = name:getSize()
            local cx = S(9)
            name:paintTo(lying, cx, band_y + math.max(0, math.floor((band_h - ns.h) / 2)))
            name:free()
            cx = cx + ns.w + S(5)
            -- the rules under the name
            lying:paintRect(cx, band_y, math.max(2, S(2)), band_h, Blitbuffer.COLOR_BLACK)
            lying:paintRect(cx + math.max(2, S(2)) + px1, band_y, 1, band_h, Blitbuffer.COLOR_BLACK)
            cx = cx + math.max(2, S(2)) + px1 + S(4)
            -- the lead headline, in two lines when the band takes them
            local room = L - cx - S(6)
            local head_room = math.floor(room * 0.55)
            if head_room > S(40) then
                local hl = TextBoxWidget:new{ text = words, face = serifBold(band_h >= S(40) and 7 or 6), width = head_room, alignment = "left" }
                local lines = math.max(1, math.floor(band_h / hl:getLineHeight()))
                if hl:getSize().h > hl:getLineHeight() * lines then
                    local lh = hl:getLineHeight()
                    hl:free()
                    hl = TextBoxWidget:new{ text = words, face = serifBold(band_h >= S(40) and 7 or 6), width = head_room, alignment = "left",
                        height = lh * lines, height_adjust = true, height_overflow_show_ellipsis = true }
                end
                hl:paintTo(lying, cx, band_y + math.max(0, math.floor((band_h - hl:getSize().h) / 2)))
                hl:free()
                cx = cx + head_room + S(5)
                lying:paintRect(cx - S(3), band_y, 1, band_h, Blitbuffer.gray(0.5))
            end
            -- a picture, then columns of print seen end on
            local pic_len = math.min(math.floor(band_h * 1.2), math.floor((L - cx) * 0.4))
            if pic_len > S(10) then
                lying:paintRect(cx, band_y + px1, pic_len, band_h - 2 * px1, Blitbuffer.gray(0.3))
                lying:paintBorder(cx, band_y + px1, pic_len, band_h - 2 * px1, 1, Blitbuffer.gray(0.6))
                cx = cx + pic_len + S(4)
            end
            local step = math.max(3, S(3))
            local half = math.floor(band_h / 2)
            for lx = cx, L - S(5), step do
                local short = ((lx * 7) % 5 == 0) and math.floor(half / 3) or 0
                lying:paintRect(lx, band_y, 1, half - S(2) - short, Blitbuffer.gray(0.4))
                lying:paintRect(lx, band_y + half + S(1), 1, band_h - half - S(1) - (((lx * 3) % 4 == 0) and math.floor(half / 4) or 0), Blitbuffer.gray(0.4))
            end
            spine_bb = lying:rotatedCopy(270)
            lying:free()
            -- the foot, on the board
            spine_bb:paintRect(0, spine_h - 1, spine_w, 1, Blitbuffer.gray(0.75))
        end
        bb:blitFrom(spine_bb, x, y, 0, 0, spine_w, spine_h)
        Paper.home.spine_at = { x = x, y = y, w = spine_w, h = spine_h }
    end)
    spine.free = function()
        if spine_bb then spine_bb:free(); spine_bb = nil end
    end
    -- (the shelf is drawn again when an edition comes; today's is asked for when it's missing)
    Paper.home = { menu = ctx and ctx.menu, shelf = true }
    D.listen("home", Paper.redrawHome)
    UIManager:nextTick(function() pcall(D.maybeRefresh, plugin) end)
    return { spine = spine, spine_w = spine_w, h = spine_h, face = widget, face_w = w, face_h = h,
        open = function() Paper.show(plugin) end }
end

--- Home's shelf (or the paper's row) again: an edition came, or a try began
--- or ended, while Home is up.
function Paper.redrawHome()
    local home = Paper.home
    if not (home and home.menu and type(home.menu._zen_home_rebuild_rows) == "function") then return end
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_r and ReaderUI.instance then return end
    local ok, done = pcall(home.menu._zen_home_rebuild_rows, { [Daily().ROW_ID] = true, strip = true })
    if ok and done then
        pcall(function()
            local fm = require("apps/filemanager/filemanager").instance
            if fm then UIManager:setDirty(fm, "ui") end
        end)
    else
        pcall(function() require("common/gz_view").redrawHome() end)
    end
end

--- The newspaper on Home's shelf, and the row among Home's widgets for
--- whoever wants the headlines there (ZenOS registers Home's API when it
--- starts, after GZreader: called a tick later).
function Paper.install(plugin)
    rawset(_G, "__GZ_SHELF_PAPER", function(ctx, area_h, cover_w) return Paper.shelfItem(plugin, ctx, area_h, cover_w) end)
    local register = rawget(_G, "__ZENOS_REGISTER_HOME_ITEM")
    if type(register) ~= "function" then return false end
    return register(Daily().ROW_ID, function(ctx) return Paper.homeWidget(plugin, ctx) end,
        { label = _("Daily paper"), size = Paper.HOME_SIZE })
end

--- Is the widget ticked in Home's widgets?
function Paper.onHome()
    local ok, on = pcall(function()
        local dcfg = require("config/preset_store").getSettings("home")
        return type(dcfg.rows) == "table" and type(dcfg.rows.enabled) == "table" and dcfg.rows.enabled[Daily().ROW_ID] == true
    end)
    return ok and on == true
end

--- Tick (or untick) the widget in Home's widgets, as Settings → Home →
--- Widgets does. Returns true, or false and "full" (no room on Home: a
--- widget has to go first) or "unavailable".
function Paper.setOnHome(on)
    local ok, res, why = pcall(function()
        local PresetStore = require("config/preset_store")
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local id = Daily().ROW_ID
        local dcfg = PresetStore.getSettings("home")
        if type(dcfg) ~= "table" or type(dcfg.rows) ~= "table" or type(dcfg.rows.enabled) ~= "table" then return false, "unavailable" end
        if on then
            local comp = Registry.get(id)
            if not comp then return false, "unavailable" end
            if dcfg.rows.enabled[id] ~= true
                    and Registry.totalUnits(dcfg.rows.enabled, dcfg.modules) + Registry.sizeUnits(comp) > Registry.CAPACITY_UNITS then
                return false, "full"
            end
            if dcfg.rows.enabled[id] ~= true then
                -- newly on Home: above the books (Home's bookshelf takes the room
                -- under itself, so it stays last), else at the end
                local order = {}
                for _i, rid in ipairs(type(dcfg.rows.order) == "table" and dcfg.rows.order or {}) do
                    if rid ~= id then order[#order + 1] = rid end
                end
                local at = #order + 1
                for i, rid in ipairs(order) do if rid == "strip" then at = i end end
                table.insert(order, at, id)
                dcfg.rows.order = order
            end
        end
        dcfg.rows.enabled[id] = on and true or false
        PresetStore.saveSettings("home", dcfg)
        return true
    end)
    if not ok then return false, "unavailable" end
    if res then pcall(function() require("common/gz_view").redrawHome() end) end
    return res, why
end

---------------------------------------------------------------- the paper

--- The edition's stories in reading order: { item, topic, kicker = true on
--- the first of its section }.
function Paper.stories(edition)
    local out = {}
    for _i, s in ipairs(type(edition) == "table" and edition.sections or {}) do
        for j, item in ipairs(s.items) do
            out[#out + 1] = { item = item, topic = s.topic, kicker = j == 1 }
        end
    end
    return out
end

--- The start of a story for the page: one paragraph, at most `max` bytes.
function Paper.excerpt(text, max)
    local s = tostring(text or ""):gsub("%s*\n+%s*", " "):gsub("^%s+", "")
    return require("gzreader_feeds").cut(s, max or 420)
end

--- Columns on a page `width_px` wide at `dpi`: 2 on a 6" Kindle, 3 from
--- about 5.4" of width (the DX, the Scribe).
function Paper.columnCount(width_px, dpi)
    local inches = width_px / math.max(1, dpi or 167)
    return inches >= 5.4 and 3 or 2
end

--- Fill `cols` columns `col_h` tall with stories from `start` (of `n`), top
--- to bottom, left to right. height(i) → a story's block height. Returns
--- the placements { { i, col, y } } and the first story that isn't on the
--- page (n + 1 when all are). A story taller than a column gets one to
--- itself. When a story doesn't fit under the ones above it and a quarter
--- of the column or more would stay empty, it waits for the top of the next
--- column and the stories after it that do fit (3 at most) go there
--- instead: no white holes under a short story.
function Paper.fill(start, n, cols, col_h, gap, height)
    local placed, i, held = {}, start, nil
    for col = 1, cols do
        local y = 0
        if held then
            placed[#placed + 1] = { i = held, col = col, y = 0 }
            y = height(held) + gap
            held = nil
        end
        while i <= n and y < col_h do
            local h = height(i)
            if y > 0 and y + h > col_h then
                if col < cols and (col_h - y) >= col_h * 0.25 then
                    held = i
                    i = i + 1
                    local tried = 0
                    while i <= n and tried < 3 do
                        local h2 = height(i)
                        if y + h2 > col_h then break end
                        placed[#placed + 1] = { i = i, col = col, y = y }
                        y = y + h2 + gap
                        i = i + 1
                        tried = tried + 1
                    end
                end
                break
            end
            placed[#placed + 1] = { i = i, col = col, y = y }
            y = y + h + gap
            i = i + 1
        end
        if i > n and not held then break end
    end
    return placed, i
end

--- Today's calendar events wanted on the front page? (On unless unticked.)
function Paper.calendarOn(plugin)
    return Daily().store(plugin).calendar ~= false
end

--- Today's events from what the Calendar tab last synced (kept on the
--- Kindle: nothing is fetched for this): { { title, when } }, all-day ones
--- first, then by time. `events`: the list to look in (else the kept one).
function Paper.todayEvents(now, events)
    now = now or os.time()
    if not events then
        local ok, cache = pcall(function() return require("gzreader_caldav").loadCache() end)
        events = ok and type(cache) == "table" and cache.events or {}
    end
    local d = os.date("*t", now)
    local from = os.time{ year = d.year, month = d.month, day = d.day, hour = 0 }
    local to = os.time{ year = d.year, month = d.month, day = d.day + 1, hour = 0 }
    local twelve = G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock")
    local out = {}
    for _i, ev in ipairs(type(events) == "table" and events or {}) do
        local start, finish = tonumber(ev.start), tonumber(ev.finish)
        if start and start < to and math.max(finish or start, start + 1) > from then
            local when
            if ev.all_day then
                when = _("All day")
            elseif start < from then
                when = _("Until") .. " " .. Paper.clockText(finish or start, twelve)
            else
                when = Paper.clockText(start, twelve)
            end
            out[#out + 1] = { title = (ev.title and ev.title ~= "") and ev.title or _("(no title)"), when = when,
                all_day = ev.all_day == true, start = start }
        end
    end
    table.sort(out, function(a, b)
        if a.all_day ~= b.all_day then return a.all_day end
        if a.start ~= b.start then return a.start < b.start end
        return a.title < b.title
    end)
    return out
end

--- "9:05", or "9:05 AM" with the 12-hour clock.
function Paper.clockText(t, twelve)
    if twelve then return (os.date("%I:%M %p", t):gsub("^0", "")) end
    return (os.date("%H:%M", t):gsub("^0", ""))
end

--- The diary line for the front page: "All day Birthday  ·  9:00 Dentist  ·  …".
function Paper.diaryText(list, max)
    local parts = {}
    for i, ev in ipairs(list) do
        if i > (max or 8) then
            parts[#parts + 1] = T(_("and %1 more"), #list - (max or 8))
            break
        end
        parts[#parts + 1] = ev.when .. " " .. ev.title
    end
    return table.concat(parts, "   \u{00B7}   ")
end

local PaperPage -- (the page's widget class, made at the first show)

local function pageClass()
    if PaperPage then return PaperPage end
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local S = function(n) return Screen:scaleBySize(n) end
    local D = Daily()

    PaperPage = InputContainer:extend{ covers_fullscreen = true, page = 1 }

    function PaperPage:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        self.starts = { 1 }
        self.keys = Device:hasDPad() and not Device:isTouchDevice()
        if Device:hasKeys() then
            local g = Device.input.group
            self.key_events = {
                GzClose = { { g.Back } },
                GzNextPage = { { g.PgFwd } },
                GzPrevPage = { { g.PgBack } },
                GzFocusNext = { { { "Down", "Right" } } },
                GzFocusPrev = { { { "Up", "Left" } } },
                GzPress = { { "Press" } },
            }
        end
        if Device:isTouchDevice() then
            local range = function() return self.dimen end
            self.ges_events = {
                GzTap = { GestureRange:new{ ges = "tap", range = range } },
                GzSwipe = { GestureRange:new{ ges = "swipe", range = range } },
            }
        end
        self:build()
    end

    function PaperPage:freeWidgets()
        for _i, w in ipairs(self.widgets or {}) do pcall(function() w:free() end) end
        self.widgets = {}
    end

    --- One story's block, `w` wide: its section over the first of each, the
    --- headline, where it's from, and how it begins.
    function PaperPage:block(story, w, lead)
        local parts, h = {}, 0
        local function add(widget, gap)
            self.widgets[#self.widgets + 1] = widget
            parts[#parts + 1] = { widget = widget, y = h }
            h = h + widget:getSize().h + (gap or 0)
        end
        if story.kicker then
            add(TextWidget:new{ text = D.topicLabel(story.topic):upper(), face = Font:getFace("smallinfofontbold", 8), max_width = w }, S(1))
        end
        local head = TextBoxWidget:new{ text = story.item.title, face = serifBold(lead and 17 or 12), width = w, alignment = "left" }
        local max_lines = lead and 3 or 4
        if head:getSize().h > head:getLineHeight() * max_lines then
            local lh = head:getLineHeight()
            head:free()
            head = TextBoxWidget:new{ text = story.item.title, face = serifBold(lead and 17 or 12), width = w, alignment = "left",
                height = lh * max_lines, height_adjust = true, height_overflow_show_ellipsis = true }
        end
        add(head, S(2))
        if story.item.source and story.item.source ~= "" then
            add(TextWidget:new{ text = story.item.source, face = serifItalic(8), max_width = w, fgcolor = Blitbuffer.COLOR_DARK_GRAY }, S(2))
        end
        local pic_path = D.pictures(self.plugin) and D.picturePath(story.item)
        local pic = pic_path and Paper.pictureWidget(pic_path, w, math.floor(w * (lead and 0.3 or 0.5)))
        if pic then add(pic, S(4)) end
        local text = Paper.excerpt(story.item.text, lead and 700 or 420)
        if text ~= "" and text ~= story.item.title then
            local body = TextBoxWidget:new{ text = text, face = serif(10), width = w, alignment = "left", justified = true }
            local lines = (lead and 4 or 5) - (pic and 2 or 0)
            if body:getSize().h > body:getLineHeight() * lines then
                local lh = body:getLineHeight()
                body:free()
                body = TextBoxWidget:new{ text = text, face = serif(10), width = w, alignment = "left", justified = true,
                    height = lh * lines, height_adjust = true, height_overflow_show_ellipsis = true }
            end
            add(body)
        end
        return { parts = parts, h = h, story = story }
    end

    --- Lay the current page out: the nameplate, the stories in columns.
    function PaperPage:build()
        self:freeWidgets()
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        local inner_w = W - margin * 2
        local edition = D.load()
        local stories = Paper.stories(edition)
        self.n = #stories
        local first = self.page == 1
        local y = S(8)
        self.header = {}
        local function head(widget, x, gap)
            self.widgets[#self.widgets + 1] = widget
            self.header[#self.header + 1] = { widget = widget, x = x, y = y }
            if gap then y = y + widget:getSize().h + gap end
        end
        local name = TextWidget:new{ text = _("The Daily Paper"), face = serifBold(first and 26 or 13), max_width = inner_w - S(60) }
        head(name, margin + math.floor((inner_w - name:getSize().w) / 2), S(2))
        self.rules = { { y = y, h = S(first and 3 or 2) }, { y = y + S(first and 5 or 4), h = 1 } }
        y = y + S(first and 8 or 6)
        if first then
            local line = TextWidget:new{ text = Paper.dateText(edition and edition.at or nil) .. os.date(", %Y", edition and edition.at or nil),
                face = serifItalic(9), max_width = math.floor(inner_w * 0.6) }
            head(line, margin)
            local status = TextWidget:new{ text = Paper.statusText(self.plugin), face = serifItalic(9), max_width = math.floor(inner_w * 0.4) }
            head(status, margin + inner_w - status:getSize().w, S(2))
            self.rules[#self.rules + 1] = { y = y, h = 1 }
            y = y + S(6)
        end
        -- the weather box: now and the next days, each with its sky's engraving
        self.weather = nil
        local Wx = require("gzreader_weather")
        if first and edition and Wx.on(self.plugin) then
            local cells = Wx.cells(edition.weather, nil, 4)
            if #cells > 0 then
                local label = TextWidget:new{ text = _("WEATHER"), face = Font:getFace("smallinfofontbold", 8) }
                local lw = label:getSize().w + S(10)
                self.widgets[#self.widgets + 1] = label
                local icon = S(44)
                local cell_w = math.floor((inner_w - lw) / #cells)
                local built = {}
                for i, c in ipairs(cells) do
                    local day = TextWidget:new{ text = c.head, face = Font:getFace("smallinfofontbold", 9), max_width = cell_w - icon - S(12) }
                    local line = TextWidget:new{ text = c.line, face = serif(10), max_width = cell_w - icon - S(12) }
                    self.widgets[#self.widgets + 1] = day
                    self.widgets[#self.widgets + 1] = line
                    built[i] = { head = day, line = line, kind = c.kind }
                end
                local box_h = icon + S(8)
                self.weather = { x = margin, y = y, w = inner_w, h = box_h, label = label, label_w = lw, cells = built, cell_w = cell_w, icon = icon }
                y = y + box_h + S(7)
            end
        end
        -- today's diary: the day's calendar events in a ruled box under the date
        self.diary = nil
        if first and Paper.calendarOn(self.plugin) then
            local list = Paper.todayEvents()
            if #list > 0 then
                local label = TextWidget:new{ text = _("TODAY"), face = Font:getFace("smallinfofontbold", 8) }
                local lw = label:getSize().w + S(10)
                local text = TextBoxWidget:new{ text = Paper.diaryText(list), face = serif(10), width = inner_w - lw - S(12), alignment = "left" }
                if text:getSize().h > text:getLineHeight() * 3 then
                    local lh = text:getLineHeight()
                    text:free()
                    text = TextBoxWidget:new{ text = Paper.diaryText(list), face = serif(10), width = inner_w - lw - S(12), alignment = "left",
                        height = lh * 3, height_adjust = true, height_overflow_show_ellipsis = true }
                end
                self.widgets[#self.widgets + 1] = label
                self.widgets[#self.widgets + 1] = text
                local box_h = text:getSize().h + S(8)
                self.diary = { x = margin, y = y, w = inner_w, h = box_h, label = label, text = text, label_w = lw }
                y = y + box_h + S(7)
            end
        end
        -- the foot: fetch, the page, the arrows
        local foot_face = Font:getFace("smallinfofont", 10)
        local fetch = TextWidget:new{ text = (edition and edition.day == D.day()) and _("Fetch again") or _("Fetch today's paper"), face = foot_face }
        local foot_h = fetch:getSize().h + S(10)
        local foot_y = H - foot_h
        self.widgets[#self.widgets + 1] = fetch
        self.foot = { y = foot_y, h = foot_h, fetch = { widget = fetch, x = margin, y = foot_y + S(5), w = fetch:getSize().w + S(20) } }
        self.close_w = Device:isTouchDevice() and S(48) or 0

        self.blocks, self.col_rules = {}, {}
        self.message = nil
        local body_h = foot_y - y - S(4)
        if self.n == 0 then
            local msg = TextBoxWidget:new{ width = inner_w, alignment = "center", face = serifItalic(12),
                text = D.refreshing and _("Fetching today's paper…") or D.last_error and D.why(D.last_error)
                    or _("No paper yet. It's fetched once a day, when Wi-Fi is on.") }
            self.widgets[#self.widgets + 1] = msg
            self.message = { widget = msg, x = margin, y = y + math.floor(body_h / 3) }
            self.next_start = 1
        else
            local start = self.starts[self.page] or 1
            if first then
                -- the lead story across the page
                local lead = self:block(stories[1], inner_w, true)
                lead.x, lead.y, lead.w = margin, y, inner_w
                self.blocks[#self.blocks + 1] = lead
                y = y + lead.h + S(6)
                self.rules[#self.rules + 1] = { y = y - S(3), h = 1 }
                start = 2
            end
            local cols = Paper.columnCount(W, Screen:getDPI())
            local gutter = S(16)
            local col_w = math.floor((inner_w - gutter * (cols - 1)) / cols)
            local col_h = foot_y - y - S(4)
            local gap = S(9)
            local built = {}
            local placed, nxt = Paper.fill(start, self.n, cols, col_h, gap, function(i)
                built[i] = built[i] or self:block(stories[i], col_w, false)
                return built[i].h
            end)
            for _i, p in ipairs(placed) do
                local b = built[p.i]
                b.x, b.y, b.w = margin + (p.col - 1) * (col_w + gutter), y + p.y, col_w
                b.clip = math.min(b.h, col_h - p.y)
                b.rule = p.y > 0 -- (a hairline above every story but a column's first)
                self.blocks[#self.blocks + 1] = b
            end
            for c = 1, cols - 1 do
                self.col_rules[#self.col_rules + 1] = { x = margin + c * (col_w + gutter) - math.floor(gutter / 2), y = y, h = col_h }
            end
            self.next_start = nxt
            self.starts[self.page + 1] = nxt
        end
        self.has_next = self.next_start <= self.n
        local label = TextWidget:new{ face = foot_face,
            text = (self.page > 1 and "\u{2039}  " or "") .. T(_("Page %1"), self.page) .. (self.has_next and "  \u{203A}" or "") }
        self.widgets[#self.widgets + 1] = label
        self.foot.label = { widget = label, x = margin + inner_w - label:getSize().w, y = foot_y + S(5) }
        if self.keys then self.focus = math.min(self.focus or 1, #self.blocks + 1) end
    end

    function PaperPage:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local W, H = self.dimen.w, self.dimen.h
        local margin = S(12)
        bb:paintRect(x, y, W, H, Blitbuffer.COLOR_WHITE)
        for _i, hd in ipairs(self.header) do hd.widget:paintTo(bb, x + hd.x, y + hd.y) end
        for _i, r in ipairs(self.rules) do bb:paintRect(x + margin, y + r.y, W - margin * 2, r.h, Blitbuffer.COLOR_BLACK) end
        if self.close_w > 0 then
            -- a cross in the corner
            local cx, cy, arm = x + W - math.floor(self.close_w / 2), y + math.floor(self.close_w / 2), S(7)
            for d = -arm, arm do
                bb:paintRect(cx + d, cy + d, 2, 2, Blitbuffer.COLOR_BLACK)
                bb:paintRect(cx + d, cy - d, 2, 2, Blitbuffer.COLOR_BLACK)
            end
        end
        if self.weather then
            local wx = self.weather
            bb:paintBorder(x + wx.x, y + wx.y, wx.w, wx.h, 1, Blitbuffer.COLOR_BLACK)
            bb:paintRect(x + wx.x + 1, y + wx.y + 1, wx.label_w - 2, wx.h - 2, Blitbuffer.COLOR_WHITE)
            wx.label:paintTo(bb, x + wx.x + S(5), y + wx.y + math.floor((wx.h - wx.label:getSize().h) / 2))
            bb:invertRect(x + wx.x + 1, y + wx.y + 1, wx.label_w - 2, wx.h - 2)
            for i, c in ipairs(wx.cells) do
                local cx = x + wx.x + wx.label_w + (i - 1) * wx.cell_w
                if i > 1 then bb:paintRect(cx, y + wx.y + S(5), 1, wx.h - S(10), Blitbuffer.COLOR_GRAY) end
                require("gzreader_weather").icon(bb, c.kind, cx + S(6), y + wx.y + S(4), wx.icon)
                local tx = cx + S(6) + wx.icon + S(6)
                local th = c.head:getSize().h + c.line:getSize().h
                local ty = y + wx.y + math.floor((wx.h - th) / 2)
                c.head:paintTo(bb, tx, ty)
                c.line:paintTo(bb, tx, ty + c.head:getSize().h)
            end
        end
        if self.diary then
            local dy = self.diary
            bb:paintBorder(x + dy.x, y + dy.y, dy.w, dy.h, 1, Blitbuffer.COLOR_BLACK)
            bb:paintRect(x + dy.x, y + dy.y, dy.label_w, dy.h, Blitbuffer.COLOR_BLACK)
            -- (white on black: the label painted, then its box turned over)
            bb:paintRect(x + dy.x + 1, y + dy.y + 1, dy.label_w - 2, dy.h - 2, Blitbuffer.COLOR_WHITE)
            dy.label:paintTo(bb, x + dy.x + S(5), y + dy.y + math.floor((dy.h - dy.label:getSize().h) / 2))
            bb:invertRect(x + dy.x + 1, y + dy.y + 1, dy.label_w - 2, dy.h - 2)
            dy.text:paintTo(bb, x + dy.x + dy.label_w + S(6), y + dy.y + S(4))
        end
        if self.message then self.message.widget:paintTo(bb, x + self.message.x, y + self.message.y) end
        for _i, r in ipairs(self.col_rules) do bb:paintRect(x + r.x, y + r.y, 1, r.h, Blitbuffer.COLOR_GRAY) end
        for i, b in ipairs(self.blocks) do
            if b.rule then bb:paintRect(x + b.x, y + b.y - S(5), b.w, 1, Blitbuffer.COLOR_GRAY) end
            for _j, part in ipairs(b.parts) do
                if not b.clip or part.y + part.widget:getSize().h <= b.clip then
                    part.widget:paintTo(bb, x + b.x, y + b.y + part.y)
                end
            end
            if self.keys and self.focus == i then
                bb:paintBorder(x + b.x - S(4), y + b.y - S(3), b.w + S(8), math.min(b.h, b.clip or b.h) + S(6), S(2), Blitbuffer.COLOR_BLACK)
            end
        end
        local f = self.foot
        bb:paintRect(x + margin, y + f.y, W - margin * 2, 1, Blitbuffer.COLOR_BLACK)
        f.fetch.widget:paintTo(bb, x + f.fetch.x, y + f.fetch.y)
        f.label.widget:paintTo(bb, x + f.label.x, y + f.label.y)
        if self.keys and self.focus == #self.blocks + 1 then
            bb:paintBorder(x + f.fetch.x - S(4), y + f.fetch.y - S(2), f.fetch.widget:getSize().w + S(8), f.fetch.widget:getSize().h + S(4), S(2), Blitbuffer.COLOR_BLACK)
        end
    end

    function PaperPage:redraw(full)
        UIManager:setDirty(self, function() return full and "partial" or "ui", self.dimen end)
    end

    function PaperPage:turn(by)
        local to = self.page + by
        if to < 1 or (by > 0 and not self.has_next) then return true end
        self.page = to
        self.focus = self.keys and (by > 0 and 1 or 9999) or nil
        self:build()
        self:redraw(true)
        return true
    end

    --- The edition changed (a new one came, a try began or ended): from page 1.
    function PaperPage:reload()
        self.page, self.starts = 1, { 1 }
        self:build()
        self:redraw(true)
    end

    function PaperPage:open(i)
        local b = self.blocks[i]
        if b then return Paper.article(self.plugin, b.story.item) end
        if i == #self.blocks + 1 then return Paper.refresh(self.plugin, self) end
    end

    function PaperPage:onGzNextPage() return self:turn(1) end
    function PaperPage:onGzPrevPage() return self:turn(-1) end
    function PaperPage:onGzClose() UIManager:close(self); return true end
    function PaperPage:onGzPress() self:open(self.focus or 0); return true end
    function PaperPage:onGzFocusNext()
        if not self.keys then return self:turn(1) end
        if self.focus < #self.blocks + 1 then self.focus = self.focus + 1; self:redraw() elseif self.has_next then self:turn(1) end
        return true
    end
    function PaperPage:onGzFocusPrev()
        if not self.keys then return self:turn(-1) end
        if self.focus > 1 then self.focus = self.focus - 1; self:redraw() elseif self.page > 1 then self:turn(-1) end
        return true
    end

    --- What's at a point of the page: "close", "fetch", "next", "prev", or a story's number.
    function PaperPage:at(px, py)
        local W = self.dimen.w
        if self.close_w > 0 and px >= W - self.close_w and py <= self.close_w then return "close" end
        if py >= self.foot.y then
            if px <= self.foot.fetch.x + self.foot.fetch.w then return "fetch" end
            if px >= W * 0.75 then return "next" end
            if px >= W * 0.5 then return "prev" end
            return nil
        end
        local dy = self.diary
        if dy and px >= dy.x and px < dy.x + dy.w and py >= dy.y and py < dy.y + dy.h then return "diary" end
        for i, b in ipairs(self.blocks) do
            if px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + math.min(b.h, b.clip or b.h) then return i end
        end
    end

    function PaperPage:onGzTap(_arg, ges)
        local what = self:at(ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
        if what == "close" then return self:onGzClose() end
        if what == "fetch" then Paper.refresh(self.plugin, self); return true end
        if what == "next" then return self:turn(1) end
        if what == "prev" then return self:turn(-1) end
        if what == "diary" then
            -- (the Calendar tab, for the day's events in full)
            UIManager:close(self)
            UIManager:nextTick(function() pcall(function() require("gzreader_calendar").show(self.plugin) end) end)
            return true
        end
        if what then self:open(what) end
        return true
    end

    function PaperPage:onGzSwipe(_arg, ges)
        if ges.direction == "west" then return self:turn(1) end
        if ges.direction == "east" then return self:turn(-1) end
        return false -- (down from the top: the quick panel)
    end

    function PaperPage:onCloseWidget()
        self.closed = true
        self:freeWidgets()
        D.listen("paper", nil)
        if Paper.instance == self then Paper.instance = nil end
    end

    return PaperPage
end

--- Fetch now (asked for: Wi-Fi is turned on for it, and what went wrong is said).
function Paper.refresh(plugin, self)
    local D = Daily()
    if D.refreshing then return info(D.why("busy"), 2) end
    require("gzreader_net").run(function()
        D.refresh(plugin, function(ok, err)
            if not ok and not (self and self.closed) then info(D.why(err), 4) end
        end)
    end, { reason = "the daily paper" })
end

--- Open the paper: a newspaper's front page, the stories in columns; more
--- pages behind it.
function Paper.show(plugin)
    local D = Daily()
    if D.noWifi() then return info(D.why("usb")) end
    if not D.enabled(plugin) then
        return info(_("The daily paper is off. Turn it on in Settings → Home → Daily paper."))
    end
    if Paper.instance and not Paper.instance.closed then return Paper.instance end
    local self = pageClass():new{ plugin = plugin }
    Paper.instance = self
    D.listen("paper", function() if not self.closed then self:reload() end end)
    UIManager:show(self)
    pcall(D.maybeRefresh, plugin)
    return self
end

--- One story: its text to page through; its link as a QR code.
function Paper.articleText(item)
    local parts = {}
    local by = item.source or ""
    if item.at then by = by .. (by ~= "" and " · " or "") .. Paper.dateText(item.at) .. ", " .. Paper.timeText(item.at) end
    if by ~= "" then parts[#parts + 1] = by end
    if item.text and item.text ~= "" then parts[#parts + 1] = item.text end
    if item.link then
        parts[#parts + 1] = item.full and _("From the story's own page. QR code shows its link for your phone.")
            or (not item.text or #item.text < 600)
            and _("This feed carries only a summary, and the story's page gave no more. The whole story is at its link: QR code shows it for your phone.")
            or _("The story's own page: QR code shows its link for your phone.")
    end
    return table.concat(parts, "\n\n")
end

function Paper.article(_plugin, item)
    local TextViewer = require("ui/widget/textviewer")
    local viewer
    local buttons = { {} }
    if item.link then
        buttons[1][#buttons[1] + 1] = { text = _("QR code"), callback = function()
            local QRMessage = require("ui/widget/qrmessage")
            UIManager:show(QRMessage:new{ text = item.link, width = Device.screen:getWidth(), height = Device.screen:getHeight() })
        end }
    end
    buttons[1][#buttons[1] + 1] = { text = _("Close"), id = "close", callback = function() UIManager:close(viewer) end }
    viewer = TextViewer:new{
        title = item.title, title_multilines = true, text = Paper.articleText(item),
        width = Device.screen:getWidth(), height = Device.screen:getHeight(),
        buttons_table = buttons, add_default_buttons = false,
    }
    UIManager:show(viewer)
    return viewer
end

---------------------------------------------------------------- settings

local function feedLabel(f)
    local D = Daily()
    return (f.name and (f.name .. " · ") or "") .. D.site(f.url)
end

--- feeds.txt in the GZreader folder or at the top of the Kindle's drive.
function Paper.feedFiles(plugin)
    local out = {}
    local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
    if type(home) == "string" then
        out[#out + 1] = home .. "/feeds.txt"
        local parent = home:match("^(.*)/[^/]+/?$")
        if parent and parent ~= "" then out[#out + 1] = parent .. "/feeds.txt" end
    end
    if plugin and plugin.feeds_file then table.insert(out, 1, plugin.feeds_file) end
    return out
end

--- Add the feeds of a feeds.txt. Returns how many were added and the file, or nil and why.
function Paper.importFile(plugin)
    local D = Daily()
    for _i, path in ipairs(Paper.feedFiles(plugin)) do
        local f = io.open(path, "rb")
        if f then
            local entries = D.parseFeedLines(f:read("*a"))
            f:close()
            if #entries == 0 then return nil, T(_("%1 has no feeds in it."), path) end
            local added = 0
            for _j, e in ipairs(entries) do
                if D.addFeed(plugin, e.url, e.name, e.topic) then added = added + 1 end
            end
            return added, path
        end
    end
    return nil, _("No feeds.txt found. Put one in the GZreader folder or at the top of the Kindle's USB drive: one feed address per line (\"Name | address\", or \"Topic | Name | address\").")
end

local function changedFeeds(plugin)
    plugin:save()
    -- (today's paper is made again from the new list at the next look)
    Daily().feedsChanged()
end

function Paper.typeAddFeed(plugin, after)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local D = Daily()
    local d
    d = MultiInputDialog:new{
        title = _("Add a feed"),
        fields = {
            { description = _("Feed address (RSS or Atom)"), text = "", hint = "https://blog.example.com/feed" },
            { description = _("Name (optional)"), text = "" },
            { description = _("Section (optional)"), text = "", hint = D.topicLabel(D.OWN_TOPIC) },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Add"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                local entry, err = D.addFeed(plugin, f[1], f[2], f[3])
                if not entry then
                    return info(err == "have" and _("That feed is already in the paper.")
                        or err == "full" and _("That's as many feeds as the paper takes. Remove one first.")
                        or _("That isn't a feed's address. It looks like https://blog.example.com/feed"))
                end
                changedFeeds(plugin)
                if after then after() end
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- Settings → Home → Daily paper → Feeds.
function Paper.feedItems(plugin)
    local D = Daily()
    local st = D.store(plugin)
    local items = {}
    local last
    for _i, f in ipairs(D.DEFAULT_FEEDS) do
        if last and last ~= f.topic and items[#items] then items[#items].separator = true end
        last = f.topic
        items[#items + 1] = {
            text = D.topicLabel(f.topic) .. ": " .. f.name,
            checked_func = function() return D.defaultOn(plugin, f) end,
            callback = function()
                D.setDefaultOn(plugin, f, not D.defaultOn(plugin, f))
                changedFeeds(plugin)
            end,
        }
    end
    if items[#items] then items[#items].separator = true end
    for i, f in ipairs(st.feeds) do
        items[#items + 1] = {
            text = feedLabel(f),
            checked_func = function() return f.enabled ~= false end,
            callback = function()
                if f.enabled == false then f.enabled = nil else f.enabled = false end
                changedFeeds(plugin)
            end,
            hold_callback = function(touchmenu)
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:show(ConfirmBox:new{
                    text = T(_("Remove %1 from the paper?"), feedLabel(f)), ok_text = _("Remove"),
                    ok_callback = function()
                        table.remove(st.feeds, i)
                        changedFeeds(plugin)
                        if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
                    end,
                })
            end,
        }
    end
    items[#items + 1] = { text = _("Add a feed"), keep_menu_open = true, callback = function(touchmenu)
        Paper.typeAddFeed(plugin, function() if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end end)
    end }
    items[#items + 1] = { text = _("Add from a browser (QR code)"), keep_menu_open = true, callback = function() Paper.browserSetup(plugin) end }
    items[#items + 1] = { text = _("Add from feeds.txt"), keep_menu_open = true, callback = function(touchmenu)
        local added, where = Paper.importFile(plugin)
        if not added then return info(where) end
        changedFeeds(plugin)
        info(T(_("%1 feeds added from %2."), added, where), 4)
        if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
    end }
    items[#items + 1] = { text = _("About feeds"), keep_menu_open = true, callback = function()
        info(_("A feed is a site's list of its newest stories (RSS or Atom); most news sites and blogs have one. Tick the ones GZreader comes with, or add your own: type its address, or put a feeds.txt in the GZreader folder with one address per line (\"Name | address\", or \"Topic | Name | address\"). Hold one of your own feeds to remove it.\n\nThe paper shows what a feed carries: some carry whole stories, many only a summary."))
    end }
    return items
end

--- Set the weather's town: found with Open-Meteo (Wi-Fi turned on for it).
--- after(ok) once it's known.
function Paper.setTown(plugin, town, after)
    local W = require("gzreader_weather")
    require("gzreader_net").run(function()
        local found, err = W.geocode(town)
        if not found then
            info(err == "not found" and T(_("No town called “%1” was found. Try its name with the country, or a bigger town nearby."), town)
                or _("Couldn't look the town up. Check the Wi-Fi and try again."))
            return after and after(false)
        end
        local w = W.store(plugin)
        w.lat, w.lon, w.place = found.lat, found.lon, found.place
        w.unit = w.unit or found.unit
        plugin:save()
        Daily().feedsChanged()
        info(T(_("Weather for %1."), found.place), 3)
        if after then after(true) end
    end, { reason = "the weather's town" })
end

--- Settings → Home → Daily paper → Weather.
function Paper.weatherItems(plugin)
    local W = require("gzreader_weather")
    local function w() return W.store(plugin) end
    local function unit() return w().unit or "C" end
    return {
        {
            text = _("Weather on the front page"),
            help_text = _("A weather box at the top of the front page: now and the next days, each with a small drawing of its sky. It comes with the day's paper: from your Home Assistant when the House tab's is connected (nothing leaves your network), otherwise from Open-Meteo (open-meteo.com, free, no account) for the town you set here. Open-Meteo is sent the town's name once, to find it, and after that its coordinates rounded to about a kilometre; neither is written to the log."),
            checked_func = function() return w().off ~= true end,
            callback = function()
                w().off = (w().off ~= true) or nil
                plugin:save()
            end,
        },
        {
            text_func = function()
                if W.source(plugin) == "ha" then return _("From your Home Assistant") end
                return w().place and T(_("Town: %1"), w().place) or _("Town (none set: no weather yet)")
            end,
            enabled_func = function() return W.source(plugin) ~= "ha" end,
            keep_menu_open = true,
            callback = function(touchmenu)
                local InputDialog = require("ui/widget/inputdialog")
                local d
                d = InputDialog:new{
                    title = _("Town for the weather"), input = "", input_hint = _("e.g. Springfield, Illinois"),
                    buttons = { {
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                        { text = _("Find"), is_enter_default = true, callback = function()
                            local town = d:getInputText()
                            UIManager:close(d)
                            Paper.setTown(plugin, town, function() if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end end)
                        end },
                    } },
                }
                UIManager:show(d)
                d:onShowKeyboard()
            end,
        },
        {
            text_func = function() return unit() == "F" and _("Degrees: Fahrenheit") or _("Degrees: Celsius") end,
            help_text = _("For Open-Meteo's weather. Home Assistant's comes in its own unit."),
            enabled_func = function() return W.source(plugin) ~= "ha" end,
            keep_menu_open = true,
            callback = function(touchmenu)
                w().unit = unit() == "F" and "C" or "F"
                plugin:save()
                Daily().feedsChanged()
                if touchmenu and touchmenu.updateItems then touchmenu:updateItems() end
            end,
        },
    }
end

--- The setup page (gzreader_phone.lua) at its Daily paper section.
function Paper.browserSetup(plugin)
    require("gzreader_net").run(function()
        require("gzreader_phone").open(plugin, { section = "paper" })
    end, { reason = "setting up the daily paper" })
end

--- Settings → Home → Daily paper.
function Paper.settingsItems(plugin)
    local D = Daily()
    if D.noWifi() then
        return { { text = _("The daily paper is fetched over Wi-Fi, and this Kindle syncs through a computer (it has no Wi-Fi, or Sync through a computer is chosen in Settings → Connections)."), enabled = false } }
    end
    local function on() return D.enabled(plugin) end
    return {
        {
            text = _("Daily paper"),
            help_text = _("Once a day GZreader fetches the feeds you tick (news sites' and blogs' lists of their newest stories) and puts them together as a paper to read on Home, also with Wi-Fi off afterwards. Fetching a feed tells its site this Kindle's internet address, as opening the site in a browser would; nothing else is sent."),
            checked_func = on,
            callback = function()
                local st = D.store(plugin)
                st.enabled = not st.enabled or nil
                plugin:save()
                if st.enabled then
                    pcall(D.maybeRefresh, plugin)
                elseif Paper.onHome() then
                    Paper.setOnHome(false)
                end
                pcall(function() require("common/gz_view").redrawHome() end)
            end,
        },
        {
            text = _("On Home's bookshelf"),
            help_text = _("The newspaper stands at the start of Home's bookshelf, among your books (Home's Bookshelf view). Tap it to read."),
            enabled_func = on,
            checked_func = function() return Paper.onShelf(plugin) end,
            callback = function()
                local st = D.store(plugin)
                if st.shelf == false then st.shelf = nil else st.shelf = false end
                plugin:save()
                pcall(function() require("common/gz_view").redrawHome() end)
            end,
        },
        {
            text = _("Headlines as a row on Home"),
            help_text = _("A wider newspaper with the day's headlines as one of Home's widgets, above the books. It takes a widget's room on Home; the newspaper on the shelf doesn't."),
            enabled_func = on,
            checked_func = function() return on() and Paper.onHome() end,
            callback = function()
                local ok, why = Paper.setOnHome(not Paper.onHome())
                if not ok then
                    info(why == "full" and _("Home has no room for it. Turn another widget off in Settings → Home → Widgets first.")
                        or _("Home's widgets can't be changed from here just now. Use Settings → Home → Widgets."))
                end
            end,
        },
        {
            text = _("Whole stories"),
            help_text = _("Many feeds carry only a sentence or two of each story. With this on, such a story's own web page is fetched with the paper and the article taken out of it, as a browser's reader view does, so the paper reads whole with Wi-Fi off. It makes the day's fetch longer (a page a story, up to five minutes in all on a slow Kindle, in the background). Stories behind a paywall, or on pages built by scripts, keep the feed's summary. A story's page can be on another site than its feed (Hacker News links anywhere); that site then also sees this Kindle's internet address."),
            enabled_func = on,
            checked_func = function() return on() and D.fullStories(plugin) end,
            callback = function()
                local st = D.store(plugin)
                if st.full == false then st.full = nil else st.full = false end
                plugin:save()
                D.feedsChanged()
            end,
        },
        {
            text = _("Pictures"),
            help_text = _("The lead story's picture and a few more (eight at most), fetched with the paper and shown in grey. Pictures often come from another site than the feed's (a picture server), which then also sees this Kindle's internet address. Without them the paper is fetched faster and takes less room."),
            enabled_func = on,
            checked_func = function() return on() and D.pictures(plugin) end,
            callback = function()
                local st = D.store(plugin)
                if st.pictures == false then st.pictures = nil else st.pictures = false end
                plugin:save()
                D.feedsChanged()
            end,
        },
        { text = _("Weather"), enabled_func = on, sub_item_table_func = function() return Paper.weatherItems(plugin) end },
        {
            text = _("Today's calendar events"),
            help_text = _("Today's events from the Calendar tab's calendars in a box at the top of the front page (all-day ones first). They are the ones the Calendar tab last synced, kept on this Kindle: nothing is fetched for it, and nothing about them leaves the Kindle. A tap on the box opens the Calendar tab. Nothing is shown on a day without events."),
            enabled_func = on,
            checked_func = function() return on() and Paper.calendarOn(plugin) end,
            callback = function()
                local st = D.store(plugin)
                if st.calendar == false then st.calendar = nil else st.calendar = false end
                plugin:save()
            end,
        },
        { text = _("Feeds"), enabled_func = on, sub_item_table_func = function() return Paper.feedItems(plugin) end },
        {
            text = _("Set up from a browser (QR code)"),
            help_text = _("Opens the setup page at Daily paper: scan the code with your phone (or open the address on a computer on the same Wi-Fi) to tick feeds and paste your own, instead of typing them here."),
            keep_menu_open = true, separator = true,
            callback = function() Paper.browserSetup(plugin) end,
        },
        { text = _("Read the paper"), enabled_func = on, keep_menu_open = true, callback = function() Paper.show(plugin) end },
        { text_func = function() return T(_("Fetch now (%1)"), Paper.statusText(plugin)) end, enabled_func = on, keep_menu_open = true,
          callback = function() Paper.refresh(plugin) end },
    }
end

return Paper
