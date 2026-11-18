--[[--
An Immich album's photos as a grid of thumbnails (gzreader_immichpick.lua):
a tap picks a photo (a thick frame and its number in the order picked), a
second tap lets it go; ‹ › turn the pages (more photos are asked for at the
end); **Add** fetches the picked photos' previews and hands them on.
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
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Log = require("gzreader_log")
local Pick = require("gzreader_immichpick")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen
local lfs = require("libs/libkoreader-lfs")

local function S(n) return Screen:scaleBySize(n) end

local Grid = InputContainer:extend{
    name = "gz_immich_grid",
    covers_fullscreen = true,
    source = nil, album = nil, title = "",
    on_pick = nil,
}

function Grid:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.photos, self.next, self.done_listing = {}, nil, false
    self.picked = {} -- ids, in the order picked
    self.page = 1
    self.thumbs = {} -- id → path (fetched)
    self.ges_events = {
        TapGrid = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        SwipeGrid = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    self.key_events = Device:hasKeys() and { Close = { { "Back" } } } or {}
    self.bar_h, self.foot_h = S(56), S(56)
    local cols, rows, cell = Pick.grid(self.dimen.w, self.dimen.h - self.bar_h - self.foot_h)
    self.cols, self.rows, self.cell = cols, rows, cell
    self[1] = VerticalGroup:new{}
end

function Grid:perScreen() return self.cols * self.rows end

--- The photos on the page shown (fetching more from Immich when the list runs out).
function Grid:pagePhotos()
    local from = (self.page - 1) * self:perScreen() + 1
    local out = {}
    for i = from, math.min(#self.photos, from + self:perScreen() - 1) do out[#out + 1] = self.photos[i] end
    return out
end

--- Asks Immich for photos until the page shown is full (or there are no
--- more), and fetches its thumbnails; then shows it.
function Grid:load()
    local busy = InfoMessage:new{ text = _("Loading photos…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local err
    while not self.done_listing and #self.photos < self.page * self:perScreen() do
        local page, e = self.source.photos(self.album, self.next)
        if not page then err = e; break end
        for _i, p in ipairs(page.photos) do self.photos[#self.photos + 1] = p end
        self.next = page.next
        if not page.next or #page.photos == 0 then self.done_listing = true end
    end
    local thumbs = select(2, Pick.dir())
    for _i, p in ipairs(self:pagePhotos()) do
        if not self.thumbs[p.id] then
            local path = thumbs .. "/" .. p.id
            if lfs.attributes(path, "mode") == "file" or self.source.thumbnail(p.id, path) then self.thumbs[p.id] = path end
        end
    end
    UIManager:close(busy)
    if err then
        Log.warn("immich pick: photos:", tostring(err))
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't read the photos (%1)."), tostring(err)), timeout = 4 })
    end
    self:build()
    UIManager:setDirty(self, "full")
end

--- A thumbnail (any kind Immich sends: WebP, JPEG…; read from its bytes)
--- fitted into a square `side` wide; kept while the grid is open.
function Grid:thumb(path, side)
    self.bbs = self.bbs or {}
    local key = path .. ":" .. side
    if self.bbs[key] == nil then
        local f = io.open(path, "rb")
        local data = f and f:read("*a")
        if f then f:close() end
        local bb
        if data and #data > 0 then
            local RenderImage = require("ui/renderimage")
            local ok, img = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
            if ok and img then
                local iw, ih = img:getWidth(), img:getHeight()
                local k = math.min(side / iw, side / ih)
                local nw, nh = math.max(1, math.floor(iw * k)), math.max(1, math.floor(ih * k))
                bb = (nw ~= iw or nh ~= ih) and RenderImage:scaleBlitBuffer(img, nw, nh, true) or img
            end
        end
        self.bbs[key] = bb or false
    end
    return self.bbs[key] or nil
end

function Grid:pickedIndex(id)
    for i, x in ipairs(self.picked) do if x == id then return i end end
end

--- Picks or lets go of photo `p`.
function Grid:toggle(p)
    local i = self:pickedIndex(p.id)
    if i then table.remove(self.picked, i)
    elseif #self.picked >= Pick.MAX_PICK then
        UIManager:show(InfoMessage:new{ text = T(_("At most %1 photos at a time."), Pick.MAX_PICK), timeout = 2 })
        return
    else self.picked[#self.picked + 1] = p.id end
    self:build()
    UIManager:setDirty(self, "ui")
end

function Grid:build()
    local w = self.dimen.w
    self.cells = {}
    local bar = HorizontalGroup:new{ align = "center",
        Button:new{ text = "\u{2190}", bordersize = 0, width = S(56), callback = function() self:onClose() end, show_parent = self },
        LeftContainer:new{ dimen = Geom:new{ w = w - S(56) - S(150), h = self.bar_h },
            TextWidget:new{ text = self.title, face = Font:getFace("tfont", 20), max_width = w - S(56) - S(160) } },
        Button:new{ text = #self.picked > 0 and T(_("Add (%1)"), #self.picked) or _("Add"), enabled = #self.picked > 0,
            width = S(140), callback = function() self:add() end, show_parent = self },
    }
    self.add_button = bar[3]
    local grid = VerticalGroup:new{}
    local list = self:pagePhotos()
    local cell = self.cell
    local pad = S(4)
    for r = 1, self.rows do
        local row = HorizontalGroup:new{}
        for c = 1, self.cols do
            local p = list[(r - 1) * self.cols + c]
            if p then
                local n = self:pickedIndex(p.id)
                local path = self.thumbs[p.id]
                local inside
                local tb = path and self:thumb(path, cell - 2 * pad - 2 * S(5))
                if tb then
                    inside = ImageWidget:new{ image = tb, image_disposable = false }
                else
                    inside = TextWidget:new{ text = p.filename ~= "" and p.filename or "?", face = Font:getFace("cfont", 12), max_width = cell - S(16) }
                end
                local box = FrameContainer:new{ width = cell - 2 * pad, height = cell - 2 * pad, padding = 0, margin = 0,
                    bordersize = n and S(5) or Size.border.thin, background = Blitbuffer.COLOR_WHITE,
                    CenterContainer:new{ dimen = Geom:new{ w = cell - 2 * pad - 2 * (n and S(5) or Size.border.thin), h = cell - 2 * pad - 2 * (n and S(5) or Size.border.thin) }, inside } }
                local holder = FrameContainer:new{ padding = pad, margin = 0, bordersize = 0, box }
                if n then
                    -- (the number in the order picked, in a black corner)
                    local badge = FrameContainer:new{ background = Blitbuffer.COLOR_BLACK, bordersize = 0, padding = S(4), margin = 0,
                        TextWidget:new{ text = tostring(n), face = Font:getFace("cfont", 16), bold = true, fgcolor = Blitbuffer.COLOR_WHITE } }
                    local paint = holder.paintTo
                    holder.paintTo = function(h, bb, x, y)
                        paint(h, bb, x, y)
                        badge:paintTo(bb, x + pad + S(5), y + pad + S(5))
                    end
                end
                self.cells[#self.cells + 1] = { w = holder, photo = p }
                row[#row + 1] = holder
            else
                row[#row + 1] = HorizontalSpan:new{ width = cell }
            end
        end
        grid[#grid + 1] = row
    end
    local total = math.max(1, math.ceil(#self.photos / self:perScreen()))
    local more = not self.done_listing
    local foot = HorizontalGroup:new{ align = "center",
        Button:new{ text = "\u{2039}", width = S(90), enabled = self.page > 1, callback = function() self:turn(-1) end, show_parent = self },
        CenterContainer:new{ dimen = Geom:new{ w = w - S(200), h = self.foot_h },
            TextWidget:new{ text = #self.photos == 0 and _("No photos here.") or T(_("Page %1 of %2"), self.page, total .. (more and "+" or "")),
                face = Font:getFace("cfont", 16) } },
        Button:new{ text = "\u{203A}", width = S(90), enabled = self.page < total or more, callback = function() self:turn(1) end, show_parent = self },
    }
    local gh = self.dimen.h - self.bar_h - self.foot_h
    self[1] = FrameContainer:new{ width = self.dimen.w, height = self.dimen.h, padding = 0, margin = 0, bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.bar_h }, bar },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = gh }, VerticalGroup:new{ grid, VerticalSpan:new{ width = 0 } } },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = self.foot_h }, foot },
        } }
end

function Grid:turn(d)
    local total = math.ceil(#self.photos / self:perScreen())
    if d > 0 and self.page >= total and self.done_listing then return end
    if d < 0 and self.page <= 1 then return end
    self.page = self.page + d
    self:load()
end

function Grid:onTapGrid(_arg, ges)
    for _i, c in ipairs(self.cells or {}) do
        if c.w.dimen and ges.pos:intersectWith(c.w.dimen) then self:toggle(c.photo); return true end
    end
    return false
end

function Grid:onSwipeGrid(_arg, ges)
    if ges.direction == "west" then self:turn(1); return true end
    if ges.direction == "east" then self:turn(-1); return true end
    return false
end

--- Add: the picked photos' previews, fetched, handed on.
function Grid:add()
    if #self.picked == 0 then return end
    local by = {}
    for _i, p in ipairs(self.photos) do by[p.id] = p end
    local list = {}
    for _i, id in ipairs(self.picked) do list[#list + 1] = by[id] end
    local busy = InfoMessage:new{ text = T(_("Fetching %1 photo(s)…"), #list), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local files, err = Pick.fetchPreviews(self.source, list)
    UIManager:close(busy)
    if not files then
        Log.warn("immich pick: preview:", tostring(err))
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't fetch the photos (%1)."), tostring(err)), timeout = 4 })
    end
    Log.info("immich pick:", #files, "photo(s) picked from", self.source.kind)
    UIManager:close(self, "full")
    if self.on_pick then self.on_pick(files) end
end

function Grid:onClose()
    UIManager:close(self, "full")
    return true
end

function Grid:onCloseWidget()
    -- (the thumbnails aren't kept)
    for _id, path in pairs(self.thumbs or {}) do os.remove(path) end
    for _k, bb in pairs(self.bbs or {}) do if bb then bb:free() end end
    self.bbs = nil
end

return Grid
