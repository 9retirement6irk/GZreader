--[[--
Two screens of the drawing screen (`gzreader_drawscreen.lua`), each a grid
of small pictures:

- All pages: the note's pages, three across. Tap a page to choose it (a
  thick frame), tap it again (or Open) to go to it. The buttons under them
  act on the chosen page: Add after, Duplicate, Move earlier / later,
  Delete.
- Paper: every paper (Blank, the ones that come with GZreader, your own
  PNGs in settings/gzreader-notepaper) as small square tiles, six to a row (as
  the Kindle Scribe's templates); tap one to put the page on it.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Notepaper = require("gzreader_notepaper")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Pages = {}

-- ---------------------------------------------------------------- the grid

--- A full-screen grid of pictures with a line under each.
--- count(), picture(i, w, h) → widget or nil (an empty frame), caption(i),
--- chosen(i), on_tap(i), actions() → rows of { text, callback, enabled },
--- on_back().
local Grid = InputContainer:extend{
    name = "gz_drawgrid",
    covers_fullscreen = true,
    title = "", hint = nil, cols = 3, first = 1,
}

--- How the cells fit: cell width, picture height, rows a screen.
function Pages.fit(width, height, cols, gap, caption_h)
    local cw = math.floor((width - (cols + 1) * gap) / cols)
    local ph = math.floor(cw * 1.3)
    local rows = math.max(1, math.floor((height + gap) / (ph + caption_h + gap)))
    return cw, ph, rows
end

function Grid:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self:build()
end

function Grid:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local gap, cap_h = S(12), S(26)
    local n = self.count()
    -- the top: Back and the title
    local back = Button:new{ text = "\u{2190} " .. _("Back"), callback = function() self:back() end, show_parent = self,
        bordersize = Size.border.thin, radius = Size.radius.button, margin = 0, padding = Size.padding.small, text_font_size = 17 }
    local top = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = S(8) }, back, HorizontalSpan:new{ width = S(12) },
        TextWidget:new{ text = self.title_fn and self.title_fn() or self.title, face = Font:getFace("cfont", 19), bold = true,
            max_width = sw - back:getSize().w - S(40) } }
    local col = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = S(6) }, top, VerticalSpan:new{ width = S(6) } }
    if self.hint then
        col[#col + 1] = HorizontalGroup:new{ HorizontalSpan:new{ width = S(12) },
            TextWidget:new{ text = self.hint, face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = sw - S(24) } }
        col[#col + 1] = VerticalSpan:new{ width = S(4) }
    end
    -- the buttons under the grid
    local rows = self.actions and self.actions() or {}
    local table_rows = {}
    for _i, row in ipairs(rows) do
        local r = {}
        for _j, a in ipairs(row) do
            r[#r + 1] = { text = a.text, enabled = a.enabled ~= false, font_size = 16, font_bold = false,
                callback = function() a.callback() end }
        end
        table_rows[#table_rows + 1] = r
    end
    local bottom = #table_rows > 0 and ButtonTable:new{ width = sw - S(16), buttons = table_rows, zero_sep = true, show_parent = self } or nil
    local bottom_h = bottom and (bottom:getSize().h + S(8)) or 0
    local used = col:getSize().h
    local pager_h = S(48)
    local cw, ph, per_col = Pages.fit(sw, sh - used - bottom_h - pager_h, self.cols, gap, cap_h)
    local per = per_col * self.cols
    self.per = per
    local pages = math.max(1, math.ceil(n / per))
    self.first = math.max(1, math.min(self.first, (pages - 1) * per + 1))
    self.cells = {}
    local k = self.first
    for _r = 1, per_col do
        if k > n then break end
        local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = gap } }
        for _c = 1, self.cols do
            if k > n then break end
            row[#row + 1] = self:cell(k, cw, ph, cap_h)
            row[#row + 1] = HorizontalSpan:new{ width = gap }
            k = k + 1
        end
        col[#col + 1] = row
        col[#col + 1] = VerticalSpan:new{ width = gap }
    end
    if pages > 1 then
        local page = math.floor((self.first - 1) / per) + 1
        col[#col + 1] = HorizontalGroup:new{ HorizontalSpan:new{ width = S(8) }, ButtonTable:new{ width = sw - S(16), zero_sep = true, show_parent = self,
            buttons = { { { text = "\u{25C0}", enabled = page > 1, callback = function() self.first = self.first - per; self:refresh() end },
                { text = T(_("%1 of %2"), page, pages), enabled = false },
                { text = "\u{25B6}", enabled = page < pages, callback = function() self.first = self.first + per; self:refresh() end } } } } }
    end
    col:resetLayout() -- (measured above, before its rows were in)
    self.bottom = bottom
    self.body = col
    self[1] = FrameContainer:new{ width = sw, height = sh, padding = 0, margin = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE, col }
end

function Grid:cell(i, cw, ph, cap_h)
    local chosen = self.chosen and self.chosen(i)
    local b = chosen and Size.border.thick or Size.border.thin
    local pic = self.picture(i, cw - 2 * b - S(4), ph - 2 * b - S(4)) or HorizontalSpan:new{ width = 1 }
    local cell = InputContainer:new{ dimen = Geom:new{ w = cw, h = ph + cap_h }, index = i,
        VerticalGroup:new{ align = "center",
            FrameContainer:new{ width = cw, height = ph, padding = 0, margin = 0, bordersize = b, radius = S(4),
                color = chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * b, h = ph - 2 * b }, pic } },
            CenterContainer:new{ dimen = Geom:new{ w = cw, h = cap_h },
                TextWidget:new{ text = self.caption(i), face = Font:getFace("cfont", 14), bold = chosen == true, max_width = cw } } } }
    cell.ges_events = { TapCell = { GestureRange:new{ ges = "tap", range = function() return cell.dimen end } } }
    local grid = self
    function cell:onTapCell() grid.on_tap(i); return true end
    self.cells[#self.cells + 1] = cell
    return cell
end

function Grid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    self[1]:paintTo(bb, x, y)
    if self.bottom then
        local sz = self.bottom:getSize()
        self.bottom:paintTo(bb, x + S(8), y + self.dimen.h - sz.h - S(4))
    end
end

--- (the buttons under the grid are painted apart from the column: they get the touches too)
function Grid:handleEvent(event)
    if self.bottom and self.bottom:handleEvent(event) then return true end
    return InputContainer.handleEvent(self, event)
end

function Grid:refresh()
    if self[1] and self[1].free then self[1]:free() end
    if self.bottom and self.bottom.free then self.bottom:free() end
    self:build()
    UIManager:setDirty(self, "ui")
end

function Grid:back()
    UIManager:close(self, "ui")
    if self.on_back then self.on_back() end
end

function Grid:onCloseWidget()
    if self[1] and self[1].free then self[1]:free() end
end

Pages.Grid = Grid

-- ------------------------------------------------------------- all pages

--- The note's pages (`ds`: the drawing screen).
function Pages.showPages(ds)
    local grid
    local sel = ds.index
    local function redraw() sel = math.max(1, math.min(sel, #ds.pages)); grid.first = math.floor((sel - 1) / grid.per) * grid.per + 1; grid:refresh() end
    local function open()
        UIManager:close(grid, "ui")
        ds:showPage(sel)
    end
    grid = Grid:new{
        title_fn = function() return #ds.pages == 1 and _("1 page") or T(_("%1 pages"), #ds.pages) end,
        hint = _("Tap a page to choose it. Tap it again to open it."),
        count = function() return #ds.pages end,
        picture = function(i, w, h)
            local ok, bb = pcall(ds.pageThumb, ds, i, w, h)
            if not ok or not bb then return nil end
            return ImageWidget:new{ image = bb, image_disposable = false, width = bb:getWidth(), height = bb:getHeight() }
        end,
        caption = function(i) return tostring(i) end,
        chosen = function(i) return i == sel end,
        on_tap = function(i)
            if i == sel then return open() end
            sel = i
            grid:refresh()
        end,
        actions = function()
            return {
                { { text = _("Open"), callback = open },
                  { text = "+ " .. _("Add after"), callback = function()
                      ds:newPage(sel); sel = sel + 1; redraw()
                  end },
                  { text = _("Duplicate"), callback = function()
                      if ds:duplicatePage(sel) then sel = sel + 1 end
                      redraw()
                  end } },
                { { text = "\u{25C0} " .. _("Move"), enabled = sel > 1, callback = function()
                      if ds:movePage(sel, -1) then sel = sel - 1 end
                      redraw()
                  end },
                  { text = _("Move") .. " \u{25B6}", enabled = sel < #ds.pages, callback = function()
                      if ds:movePage(sel, 1) then sel = sel + 1 end
                      redraw()
                  end },
                  { text = _("Delete"), callback = function()
                      local dialog
                      dialog = ButtonDialog:new{ title = T(_("Delete page %1?"), sel), buttons = {
                          { { text = _("Delete the page"), align = "left", callback = function()
                              UIManager:close(dialog); ds:deletePage(sel); redraw()
                          end } },
                          { { text = _("Keep it"), align = "left", callback = function() UIManager:close(dialog) end } },
                      } }
                      UIManager:show(dialog)
                      grid.dialog = dialog
                  end } },
            }
        end,
        on_back = function() ds:showPage(ds.index) end,
    }
    grid.kind = "pages"
    grid.selected = function() return sel end
    UIManager:show(grid, "ui")
    return grid
end

-- ------------------------------------------------------------------ paper

--- The paper chooser, as the Kindle Scribe's "Choose a template" (the
--- owner, 2026-11-16, with photos of it): a grid of small rounded square
--- tiles, six to a row (four on a narrow screen), each a corner of the
--- paper drawn large enough to tell it by, its name under it; the chosen
--- one has a thick border. More rows than fit: the grid scrolls (a finger).
--- A page's paper: a tap picks. A new drawing (`create`): a tap chooses,
--- Create starts the drawing on it, Cancel leaves.
local PaperList = InputContainer:extend{
    name = "gz_paperlist",
    covers_fullscreen = true,
    kind = "papers",
    title = "", papers = nil, current = nil, on_pick = nil, create = nil,
}

--- A line of a paper's name (names run to three: "Medium ruled with margin").
Pages.PAPER_FONT = 13
Pages.PAPER_LINE = S(20)

--- The grid's sizes for a screen `width` wide: columns, a tile's side, a
--- cell's width and height, the gap between cells.
function Pages.paperCell(width)
    local cols = width >= 1000 and 6 or 4
    local gap = S(10)
    local cell_w = math.floor((width - ScrollableContainer:getScrollbarWidth() - S(12) - gap * (cols + 1)) / cols)
    local tile = math.floor(cell_w * 0.82)
    return cols, tile, cell_w, tile + S(4) + 3 * Pages.PAPER_LINE, gap
end

function PaperList:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local back = Button:new{ text = "\u{2190} " .. _("Back"), callback = function() self:back() end, show_parent = self,
        bordersize = Size.border.thin, radius = Size.radius.button, margin = 0, padding = Size.padding.small, text_font_size = 17 }
    local head = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = S(6) },
        HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = S(8) }, back, HorizontalSpan:new{ width = S(12) },
            TextWidget:new{ text = self.title, face = Font:getFace("cfont", 19), bold = true, max_width = sw - back:getSize().w - S(40) } },
        VerticalSpan:new{ width = S(10) },
        HorizontalGroup:new{ HorizontalSpan:new{ width = S(14) },
            TextWidget:new{ text = _("Choose a template"), face = Font:getFace("cfont", 16), bold = true, max_width = sw - S(28) } },
        VerticalSpan:new{ width = S(8) } }
    -- a new drawing: Cancel and Create under the grid
    local foot
    if self.create then
        local bw = math.min(S(150), math.floor((sw - S(60)) / 2))
        local function btn(text, dark, fn)
            return Button:new{ text = text, callback = fn, show_parent = self, width = bw, bordersize = Size.border.thick,
                radius = S(4), margin = 0, padding = S(10), text_font_size = 18, preselect = dark or nil }
        end
        foot = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = S(8) },
            HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = sw - 2 * bw - S(12) - S(16) - 4 * Size.border.thick },
                btn(_("Cancel"), false, function() self:back() end), HorizontalSpan:new{ width = S(12) },
                btn(_("Create"), true, function() self:pick(self:chosenIndex()) end) },
            VerticalSpan:new{ width = S(10) } }
    end
    local cols, tile, cell_w, cell_h, gap = Pages.paperCell(sw)
    local grid = VerticalGroup:new{ align = "left" }
    local line
    local face = Font:getFace("cfont", Pages.PAPER_FONT)
    self.rows = {}
    for i, paper in ipairs(self.papers) do
        local chosen = paper.id == self.current
        local b = chosen and S(4) or Size.border.thin
        local inner = tile - 2 * b - S(10)
        local small = Notepaper.tile(paper)
        local path = small or Notepaper.path(paper)
        local pic
        if small then
            pic = ImageWidget:new{ file = small, width = inner, height = inner, scale_factor = 0 }
        elseif path then -- (your own paper: the whole page, small)
            pic = ImageWidget:new{ file = path, width = math.floor(inner / 1.3), height = inner, scale_factor = 0 }
        else
            pic = HorizontalSpan:new{ width = 1 }
        end
        local cell = InputContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, show_parent = self,
            VerticalGroup:new{ align = "center",
                FrameContainer:new{ width = tile, height = tile, padding = 0, margin = 0, bordersize = b, radius = S(12),
                    color = chosen and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, background = Blitbuffer.COLOR_WHITE,
                    CenterContainer:new{ dimen = Geom:new{ w = tile - 2 * b, h = tile - 2 * b }, pic } },
                VerticalSpan:new{ width = S(4) },
                TextBoxWidget:new{ text = paper.label, face = face, bold = chosen, width = cell_w, alignment = "center",
                    height = cell_h - tile - S(4), height_adjust = true, height_overflow_show_ellipsis = true } } }
        cell.ges_events = { TapPaper = { GestureRange:new{ ges = "tap", range = function() return cell.dimen end } } }
        local me = self
        function cell:onTapPaper() me:tapped(i); return true end
        self.rows[i] = cell
        if (i - 1) % cols == 0 then
            line = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = gap } }
            grid[#grid + 1] = line
            grid[#grid + 1] = VerticalSpan:new{ width = gap }
        end
        line[#line + 1] = cell
        line[#line + 1] = HorizontalSpan:new{ width = gap }
    end
    local view_h = sh - head:getSize().h - (foot and foot:getSize().h or 0) - S(8)
    self.scroller = ScrollableContainer:new{ dimen = Geom:new{ w = sw - S(12), h = view_h }, show_parent = self,
        swipe_full_view = false, grid }
    self.cropping_widget = self.scroller
    self[1] = FrameContainer:new{ width = sw, height = sh, padding = 0, margin = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", head, HorizontalGroup:new{ HorizontalSpan:new{ width = S(6) }, self.scroller }, foot } }
    -- (the chosen paper in view; after a tap: where the grid was. The
    -- scroller measures itself when first painted: before that it can't be moved.)
    self.scroller:initState()
    local row_h = cell_h + gap
    local total = math.ceil(#self.papers / cols) * row_h
    if self.keep_offset then
        if self.scroller._is_scrollable then self.scroller:setScrolledOffset(self.keep_offset) end
        self.keep_offset = nil
    elseif self.scroller._is_scrollable then
        for i, paper in ipairs(self.papers) do
            local r = math.floor((i - 1) / cols)
            if paper.id == self.current and (r + 1) * row_h > view_h and total > view_h then
                self.scroller:scrollToRatio(0, math.min(1, (r * row_h + view_h / 2) / total))
            end
        end
    end
end

function PaperList:chosenIndex()
    for i, paper in ipairs(self.papers) do if paper.id == self.current then return i end end
    return 1
end

--- A tap on paper `i`: the page's paper is picked at once; a new drawing's is chosen (Create starts it).
function PaperList:tapped(i)
    if not self.create then return self:pick(i) end
    if self.papers[i].id == self.current then return end
    self.current = self.papers[i].id
    self.keep_offset = self.scroller and self.scroller._is_scrollable and self.scroller:getScrolledOffset() or nil
    self:free()
    self:init()
    UIManager:setDirty(self, "ui")
end

function PaperList:pick(i)
    UIManager:close(self, "ui")
    if self.on_pick then self.on_pick(self.papers[i].id) end
end

function PaperList:back()
    UIManager:close(self, "ui")
    if self.on_back then self.on_back() end
end

Pages.PaperList = PaperList

--- opts: current (the page's paper id), title, on_pick(id), on_back();
--- create: a new drawing's (a tap chooses; Create picks, Cancel is on_back).
function Pages.showPapers(opts)
    local list = PaperList:new{
        title = opts.title or _("Paper"),
        papers = Notepaper.all(),
        current = opts.current,
        on_pick = opts.on_pick,
        on_back = opts.on_back,
        create = opts.create,
    }
    UIManager:show(list, "ui")
    return list
end

return Pages
