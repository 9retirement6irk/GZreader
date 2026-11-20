--[[--
The Stickers tool's picker (gzreader_stickers.lua): a category of Kid Pix
stickers as a grid, a tap picks one. The category's name at the top opens the
list of categories; ‹ › (or a swipe) turn the pages. A category's pictures
are fetched from the Memos server the first time it's opened, then kept.

    StickerGrid.show(plugin, { on_pick = function(item, cat) end })
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Log = require("gzreader_log")
local Stickers = require("gzreader_stickers")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

local function S(n) return Screen:scaleBySize(n) end

local Grid = InputContainer:extend{
    name = "gz_sticker_grid",
    covers_fullscreen = true,
    plugin = nil, index = nil, cat = nil,
    on_pick = nil,
}

--- How many stickers a screen shows: cols, rows, a cell's side.
function Grid.layout(w, h)
    local cols = w >= 1000 and 5 or 4
    local cell = math.floor(w / cols)
    return cols, math.max(1, math.floor(h / cell)), cell
end

function Grid:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.page = 1
    self.ges_events = {
        TapGrid = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        SwipeGrid = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    self.key_events = Device:hasKeys() and { Close = { { "Back" } } } or {}
    self.bar_h, self.foot_h = S(56), S(56)
    self.cols, self.rows, self.cell = Grid.layout(self.dimen.w, self.dimen.h - self.bar_h - self.foot_h)
    self[1] = VerticalGroup:new{}
end

function Grid:perScreen() return self.cols * self.rows end

function Grid:pages() return math.max(1, math.ceil(#self.cat.items / self:perScreen())) end

--- A sticker's picture fitted into a square `side` wide (kept while the picker is open).
function Grid:thumb(item, side)
    self.bbs = self.bbs or {}
    local key = item.file .. ":" .. side
    if self.bbs[key] == nil then
        -- (drawn from its SVG, fitted into the square)
        local bb = Stickers.render(item, side, side)
        self.bbs[key] = bb or false
    end
    return self.bbs[key] or nil
end

function Grid:build()
    local w = self.dimen.w
    self.cells = {}
    local cat = self.cat
    local bar = HorizontalGroup:new{ align = "center",
        Button:new{ text = "\u{2190}", bordersize = 0, width = S(56), callback = function() self:onClose() end, show_parent = self },
        Button:new{ text = cat.name .. "  \u{25BE}", bordersize = 0, width = w - S(112), callback = function() self:chooseCategory() end,
            show_parent = self },
        HorizontalSpan:new{ width = S(56) },
    }
    local grid = VerticalGroup:new{}
    local from = (self.page - 1) * self:perScreen()
    local cell, pad = self.cell, S(6)
    for r = 1, self.rows do
        local row = HorizontalGroup:new{}
        for c = 1, self.cols do
            local item = cat.items[from + (r - 1) * self.cols + c]
            if item then
                local tb = self:thumb(item, cell - 2 * pad - S(8))
                local inside = tb and ImageWidget:new{ image = tb, image_disposable = false, alpha = true }
                    or TextWidget:new{ text = item.name ~= "" and item.name or "?", face = Font:getFace("cfont", 12), max_width = cell - S(16) }
                local holder = FrameContainer:new{ padding = pad, margin = 0, bordersize = 0,
                    CenterContainer:new{ dimen = Geom:new{ w = cell - 2 * pad, h = cell - 2 * pad }, inside } }
                self.cells[#self.cells + 1] = { w = holder, item = item }
                row[#row + 1] = holder
            else
                row[#row + 1] = HorizontalSpan:new{ width = cell }
            end
        end
        grid[#grid + 1] = row
    end
    local foot = HorizontalGroup:new{ align = "center",
        Button:new{ text = "\u{2039}", width = S(90), enabled = self.page > 1, callback = function() self:turn(-1) end, show_parent = self },
        CenterContainer:new{ dimen = Geom:new{ w = w - S(200), h = self.foot_h },
            TextWidget:new{ text = T(_("Page %1 of %2"), self.page, self:pages()), face = Font:getFace("cfont", 16) } },
        Button:new{ text = "\u{203A}", width = S(90), enabled = self.page < self:pages(), callback = function() self:turn(1) end, show_parent = self },
    }
    self[1] = FrameContainer:new{ width = self.dimen.w, height = self.dimen.h, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.bar_h }, bar },
            -- (the stickers from the top down)
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.rows * cell }, grid },
            VerticalSpan:new{ width = self.dimen.h - self.bar_h - self.foot_h - self.rows * cell },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.foot_h }, foot },
        } }
end

function Grid:turn(d)
    local p = self.page + d
    if p < 1 or p > self:pages() then return end
    self.page = p
    self:build()
    UIManager:setDirty(self, "ui")
end

--- Category `cat` shown (its pictures fetched first when they aren't all here).
function Grid:showCategory(cat)
    local function show()
        self.cat, self.page = cat, 1
        if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_sticker_category", cat.slug) end
        self:build()
        UIManager:setDirty(self, "full")
    end
    if Stickers.have(cat) == #cat.items then return show() end
    local server = Stickers.server(self.plugin)
    if not server then
        if Stickers.have(cat) > 0 then return show() end
        return UIManager:show(InfoMessage:new{ text = Stickers.why("no_server"), timeout = 5 })
    end
    require("gzreader_net").run(function()
        local busy = InfoMessage:new{ text = T(_("Fetching %1 stickers…"), cat.name), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local n, err = Stickers.fetchCategory(server, cat)
        UIManager:close(busy)
        if n == 0 then return UIManager:show(InfoMessage:new{ text = Stickers.why(err), timeout = 5 }) end
        show()
    end, { reason = "stickers" })
end

--- The list of categories (each with how many stickers it has).
function Grid:chooseCategory()
    local Menu = require("ui/widget/menu")
    local menu
    local items = {}
    for _i, c in ipairs(self.index.categories) do
        items[#items + 1] = { text = c.name, mandatory = tostring(#c.items), bold = c == self.cat,
            callback = function() UIManager:close(menu); self:showCategory(c) end }
    end
    menu = Menu:new{ title = _("Stickers"), item_table = items, width = Screen:getWidth(), height = Screen:getHeight(),
        is_borderless = true, covers_fullscreen = true }
    UIManager:show(menu)
    return menu
end

function Grid:onTapGrid(_arg, ges)
    for _i, c in ipairs(self.cells or {}) do
        if c.w.dimen and ges.pos:intersectWith(c.w.dimen) then
            if not Stickers.path(c.item) then return true end
            Log.info("stickers: picked", c.item.file)
            UIManager:close(self, "full")
            if self.on_pick then self.on_pick(c.item, self.cat) end
            return true
        end
    end
    return false
end

function Grid:onSwipeGrid(_arg, ges)
    if ges.direction == "west" then self:turn(1); return true end
    if ges.direction == "east" then self:turn(-1); return true end
    return false
end

function Grid:onClose()
    UIManager:close(self, "full")
    return true
end

function Grid:onCloseWidget()
    for _k, bb in pairs(self.bbs or {}) do if bb then bb:free() end end
    self.bbs = nil
end

--- The picker, at the category last opened (the first one the first time).
--- The list of stickers comes from the Memos server the first time (Wi-Fi).
function Grid.show(plugin, opts)
    opts = opts or {}
    local function open(index)
        local last = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_sticker_category")
        local cat = index.categories[1]
        for _i, c in ipairs(index.categories) do if c.slug == last then cat = c end end
        local grid = Grid:new{ plugin = plugin, index = index, on_pick = opts.on_pick }
        grid.cat = cat
        UIManager:show(grid)
        grid:showCategory(cat)
        return grid
    end
    local index = Stickers.index()
    if index then return open(index) end
    local server = Stickers.server(plugin)
    if not server then return UIManager:show(InfoMessage:new{ text = Stickers.why("no_server"), timeout = 5 }) end
    require("gzreader_net").run(function()
        local busy = InfoMessage:new{ text = _("Fetching the stickers…"), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local got, err = Stickers.fetchIndex(server)
        UIManager:close(busy)
        if not got then
            Log.warn("stickers: the list:", tostring(err))
            return UIManager:show(InfoMessage:new{ text = Stickers.why(err), timeout = 5 })
        end
        open(got)
    end, { reason = "stickers" })
end

return Grid
