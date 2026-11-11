--[[--
The Catalog tab (the Grimmory tab until 1.27.x): what's on your servers, in
pages:

  Books       Grimmory's books (the bookshop: gzreader_bookshop.lua)
  Audiobooks  Grimmory's audiobooks
  Music       Plex (gzreader_musictab.lua's lists)

Audiobooks and Music only on Kindles with a speaker or headphone jack; the
others have the Books page alone (no strip, nothing to turn to).

The tab opens on Books. A page's first list is the page: a swipe left (or
the list's next-page button, or the page-turn key) on its last page goes to
the next page, a swipe right on its first page back to the one before; the
pages go round (before Books: Music, after Music: Books). The title says
which page it is; under it a strip: ‹ the page before, a dot per page (this
one filled), the next page › (a tap on either side turns to it).
Inside a page's lists the strip is blank and swipes turn the list's pages,
as before.
]]

local _ = require("gettext")

local Catalog = {
    ORDER = { "books", "audiobooks", "music" },
}

--- The pages this Kindle has, in order (`audio`: a speaker or headphone
--- jack; asked of gzreader_touch when nil).
function Catalog.sections(audio)
    if audio == nil then
        local ok, on = pcall(function() return require("gzreader_touch").audio() end)
        audio = ok and on == true
    end
    if not audio then return { "books" } end
    local out = {}
    for _i, id in ipairs(Catalog.ORDER) do out[#out + 1] = id end
    return out
end

local TITLES = { books = _("Books"), audiobooks = _("Audiobooks"), music = _("Music") }

--- A page's title (the title bar's label).
function Catalog.title(id) return TITLES[id] or TITLES.books end

local function indexOf(list, id)
    for i, v in ipairs(list) do if v == id then return i end end
    return nil
end

--- The page `dir` (+1 next, -1 before) from `id` in `list`, round the ends
--- (before Books: Music; after Music: Books); nil with only one page.
function Catalog.step(list, id, dir)
    local i = indexOf(list, id) or 1
    if dir == 0 then return list[i] end
    if #list < 2 then return nil end
    return list[(i - 1 + dir) % #list + 1]
end

--- What the strip says: { left = "‹ Books" or nil, dots = "○ ● ○", right = "Music ›" or nil };
--- nil when there's only one page.
function Catalog.stripParts(list, id)
    if #list < 2 then return nil end
    local cur = indexOf(list, id) or 1
    local dots = {}
    for i = 1, #list do dots[i] = i == cur and "●" or "○" end
    local prev, nxt = Catalog.step(list, list[cur], -1), Catalog.step(list, list[cur], 1)
    return {
        left = prev and ("‹ " .. Catalog.title(prev)) or nil,
        dots = table.concat(dots, " "),
        right = nxt and (Catalog.title(nxt) .. " ›") or nil,
    }
end

--- Which way a tap at `x` turns in a strip of width `w` starting at `x0`:
--- -1 (the left third, when there's a page before), +1 (the right third,
--- when there's a next one), or nil.
function Catalog.hit(parts, x, x0, w)
    if not parts then return nil end
    local third = w / 3
    if x < x0 + third then return parts.left and -1 or nil end
    if x >= x0 + w - third then return parts.right and 1 or nil end
    return nil
end

--- A Catalog root list (a page)?
function Catalog.atRoot(menu)
    return type(menu) == "table" and type(menu.item_table) == "table" and menu.item_table.gz_catalog ~= nil
        and #(menu.item_table_stack or {}) == 0
end

---------------------------------------------------------------- the strip

--- The strip's widget class (made when first needed: the pure functions
--- above load no widgets).
local Strip
function Catalog.Strip()
    if Strip then return Strip end
    local Blitbuffer = require("ffi/blitbuffer")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local TextWidget = require("ui/widget/textwidget")
    Strip = require("ui/widget/container/inputcontainer"):extend{ w = 0, h = 0, browser = nil, face = nil }

    function Strip:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h }
        self.face = self.face or Font:getFace("xx_smallinfofont")
        self.ges_events = {
            TapCatalogStrip = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end

    function Strip:getSize() return Geom:new{ w = self.w, h = self.h } end
    -- (Menu:switchItemTable sets a subtitle: the strip says what it says)
    function Strip:setText() end
    function Strip:free() end

    function Strip:parts()
        local b = self.browser
        if not (b and b.menu and Catalog.atRoot(b.menu)) then return nil end
        return Catalog.stripParts(b.sections and b:sections() or Catalog.sections(), b.section or "books")
    end

    function Strip:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
        local p = self:parts()
        if not p then return end
        local function put(str, where, color, bold)
            local t = TextWidget:new{ text = str, face = self.face, fgcolor = color, bold = bold, max_width = math.floor(self.w / 3) }
            local sz = t:getSize()
            local tx = where == "left" and x or where == "right" and (x + self.w - sz.w) or (x + math.floor((self.w - sz.w) / 2))
            t:paintTo(bb, tx, y + math.floor((self.h - sz.h) / 2))
            t:free()
        end
        put(p.dots, "center", Blitbuffer.COLOR_BLACK, false)
        if p.left then put(p.left, "left", Blitbuffer.COLOR_DARK_GRAY, true) end
        if p.right then put(p.right, "right", Blitbuffer.COLOR_DARK_GRAY, true) end
    end

    function Strip:onTapCatalogStrip(_arg, ges)
        local p = self:parts()
        local dir = ges and ges.pos and Catalog.hit(p, ges.pos.x, self.dimen.x, self.w)
        if not dir then return false end
        self.browser:turnSection(dir)
        return true
    end
    return Strip
end

---------------------------------------------------------------- on the browser's Menu

--- The strip in place of the title bar's (empty) subtitle line, and the
--- page turns at a page's ends. `browser`: gzreader_browser's.
function Catalog.apply(browser)
    local m = browser.menu
    if not m or m._gz_catalog then return end
    m._gz_catalog = true
    local tb = m.title_bar
    local sw = tb and tb.subtitle_widget
    if sw and tb.title_group then
        local strip = Catalog.Strip():new{
            w = (tb.width or m.dimen.w) - 2 * (tb.title_h_padding or 0),
            h = sw:getSize().h,
            browser = browser,
        }
        for i, child in ipairs(tb.title_group) do
            if child == sw then tb.title_group[i] = strip end
        end
        if tb.inner_subtitle_group then
            for i, child in ipairs(tb.inner_subtitle_group) do
                if child == sw then tb.inner_subtitle_group[i] = strip end
            end
            tb.inner_subtitle_group:resetLayout()
        end
        tb.subtitle_widget = strip
        tb.title_group:resetLayout()
        sw:free()
        m._gz_strip = strip
    end
    local orig_next, orig_prev = m.onNextPage, m.onPrevPage
    m.onNextPage = function(menu, ...)
        if Catalog.atRoot(menu) and (menu.page or 1) >= (menu.page_num or 1) and browser:turnSection(1) then return true end
        if orig_next then return orig_next(menu, ...) end
    end
    m.onPrevPage = function(menu, ...)
        if Catalog.atRoot(menu) and (menu.page or 1) <= 1 and browser:turnSection(-1) then return true end
        if orig_prev then return orig_prev(menu, ...) end
    end
end

return Catalog
