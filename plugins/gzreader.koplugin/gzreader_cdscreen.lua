--[[--
Music's player: a portable CD player with headphones (gzreader_deck.lua),
the album's cover on the disc, the track and time on its display; the track
and the album under it, then the controls and the queue, like the back of a
CD case.

Keys (Kindle Keyboard): Q previous, W play / pause, E next, A shuffle,
S repeat, D stop; ◀ ▶ previous / next; ▲ ▼ through the queue, Press plays
the one picked; Back (or Menu) closes, the music keeps playing. Touch: the
buttons, and a tap on a track plays it.
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
local InputContainer = require("ui/widget/container/inputcontainer")
local Menu = require("ui/widget/menu")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Touch = require("gzreader_touch")
local _ = require("gettext")

local CDScreen = InputContainer:extend{ name = "gzreader cd player", plugin = nil, covers_fullscreen = true }

local function Music() return require("gzreader_music") end
local function fmtTime(ms)
    local s = math.floor((tonumber(ms) or 0) / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function face(size, bold) return Font:getFace(bold and "smalltfont" or "cfont", size) end
local function S(px) return Device.screen:scaleBySize(px) end

function CDScreen:init()
    local sw, sh = Device.screen:getWidth(), Device.screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.key_events = {
        Prev = { { "Q" } }, Toggle = { { "W" } }, Next = { { "E" } },
        Shuffle = { { "A" } }, Repeat = { { "S" } }, Stop = { { "D" } },
        PrevKey = { { "Left" } }, NextKey = { { "Right" } },
        Up = { { "Up" } }, Down = { { "Down" } }, Play = { { "Press" } },
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        CloseMenu = { { "Menu" } },
    }
    self.picked = nil
    self.listener_key = "cdscreen-" .. tostring(self)
    Music().listeners[self.listener_key] = function() self.picked = nil; self:refresh() end
    self:build()
end

function CDScreen:player() return Music().current end

--- The album's cover (cover.jpg in its folder), once per album.
function CDScreen:cover(p)
    local dir = p and p.c and p.c.dir
    if dir == self.cover_dir then return self.cover_bb end
    if self.cover_bb then self.cover_bb:free(); self.cover_bb = nil end
    self.cover_dir = dir
    local f = dir and io.open(dir .. "/cover.jpg", "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local RenderImage = require("ui/renderimage")
    local ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    if ok and bb then self.cover_bb = bb end
    return self.cover_bb
end

function CDScreen:control(key, label, callback, width)
    local side = Touch.keys() and S(26) or 0
    local btn = Button:new{ text = label, callback = callback, width = width - side - (side > 0 and Size.padding.default or 0),
        bordersize = Size.border.thin, radius = Size.radius.button, text_font_size = 16, text_font_bold = false, show_parent = self }
    if side == 0 then return btn end
    local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = side, h = side }, key, "square")
    return HorizontalGroup:new{ align = "center", sc, HorizontalSpan:new{ width = Size.padding.default }, btn }
end

--- A track in the queue: tap plays it.
local Row = InputContainer:extend{ w = 0, h = 0, n = 0, screen = nil }
function Row:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    local range = function() return self.dimen end
    self.ges_events = { TapRow = { GestureRange:new{ ges = "tap", range = range } } }
end
function Row:onTapRow()
    local p = self.screen:player()
    if p then p:jump(self.n) end
    self.screen.picked = nil
    self.screen:refresh()
    return true
end

function CDScreen:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local inner = math.floor(sw * 0.9)
    local p = self:player()
    local group = VerticalGroup:new{ align = "center" }
    local function add(w) group[#group + 1] = w end
    local function gap(px) add(VerticalSpan:new{ width = S(px) }) end
    local t = p and p:track() or {}
    local deck_w = math.min(math.floor(sw * 0.86), math.floor(sh * 0.36 * 360 / 300))
    add(require("gzreader_deck").CD:new{ w = deck_w, state = {
        cover_bb = self:cover(p), track = p and p.order[p.at] or nil,
        time = p and (p.waiting and "--:--" or fmtTime(p:position())) or "", playing = p and p.playing,
    } })
    gap(6)
    if not p then
        add(TextWidget:new{ text = _("Nothing playing."), face = face(18, true) })
    else
        add(TextWidget:new{ text = t.title or "?", face = face(20, true), max_width = inner })
        add(TextWidget:new{ text = ((t.artist or p.c.artist) and ((t.artist or p.c.artist) .. " — ") or "") .. (p.c.title or ""),
            face = face(15), max_width = inner })
        gap(6)
        local dur = tonumber(t.duration) or 0
        local okp, BookProgress = pcall(require, "common/ui/book_progress")
        if okp and BookProgress.edges and dur > 0 then
            add(BookProgress.edges(math.min(1, p:position() / dur), inner, S(10)))
        end
        add(TextWidget:new{ text = (p.waiting and _("downloading…") or fmtTime(p:position())) .. " / " .. fmtTime(dur)
            .. (p.playing and "" or ("  ·  " .. _("paused"))), face = face(14) })
    end
    gap(10)
    -- the CD player's pill buttons (gzreader_skeuo.lua)
    local Skeuo = require("gzreader_skeuo")
    local function pills(defs)
        local gapw = S(8)
        local kw = math.floor((inner - 2 * gapw) / 3)
        local rowg = HorizontalGroup:new{ align = "center" }
        for k, d in ipairs(defs) do
            if k > 1 then rowg[#rowg + 1] = HorizontalSpan:new{ width = gapw } end
            rowg[#rowg + 1] = Skeuo.Key:new{ shape = "pill", w = kw, h = S(48), label = d[1],
                letter = Touch.keys() and d[2] or nil, callback = d[3], down = d[4] and true or false, icon = d.icon }
        end
        return rowg
    end
    local rep = p and p["repeat"] or "off"
    add(pills({
        { "", "Q", function() self:onPrev() end, icon = "prev" },
        { "", "W", function() self:onToggle() end, p and p.playing, icon = (p and p.playing) and "pause" or "play" },
        { "", "E", function() self:onNext() end, icon = "next" },
    }))
    gap(8)
    add(pills({
        { (p and p.shuffle) and _("Shuffle on") or _("Shuffle"), "A", function() self:onShuffle() end, p and p.shuffle },
        { ({ off = _("Repeat"), all = _("Repeat all"), one = _("Repeat one") })[rep] or _("Repeat"), "S",
            function() self:onRepeat() end, rep ~= "off" },
        { _("Stop"), "D", function() self:onStop() end, icon = "stop" },
    }))
    gap(10)
    -- the queue: the back insert of a CD case, its spines either side
    if p then
        local rows = math.max(3, math.floor((sh * 0.27) / S(30)))
        local first = math.max(1, math.min((self.picked or p.at) - 1, #p.order - rows + 1))
        local spine_w = S(22)
        local list_w = inner - 2 * spine_w - S(4)
        local list = VerticalGroup:new{ align = "left" }
        local rh = S(30)
        for n = first, math.min(#p.order, first + rows - 1) do
            local tr = p.c.tracks[p.order[n]] or {}
            local cur, sel = n == p.at, n == self.picked
            local ink = cur and Blitbuffer.COLOR_WHITE or nil
            local line = HorizontalGroup:new{ align = "center",
                TextWidget:new{ text = string.format("%02d", n), face = face(14), bold = cur, fgcolor = ink },
                HorizontalSpan:new{ width = S(10) },
                TextWidget:new{ text = (cur and "\u{25B6} " or "") .. (tr.title or "?"), face = face(15), bold = cur,
                    fgcolor = ink, max_width = list_w - S(100) },
            }
            local dur = TextWidget:new{ text = fmtTime(tr.duration), face = face(14), fgcolor = ink }
            local content = HorizontalGroup:new{ align = "center", line,
                HorizontalSpan:new{ width = math.max(S(4), list_w - S(24) - line:getSize().w - dur:getSize().w) }, dur }
            local frame = FrameContainer:new{ width = list_w, height = rh, padding = 0, padding_left = S(8),
                bordersize = sel and S(2) or 0, color = Blitbuffer.COLOR_BLACK,
                background = cur and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.04), radius = cur and S(4) or 0, content }
            local r = Row:new{ w = list_w, h = rh, n = n, screen = self }
            r[1] = frame
            list[#list + 1] = r
        end
        local title = ((p.c.title or "") .. ((p.c.artist and p.c.artist ~= "") and ("  ·  " .. p.c.artist) or ""))
        local list_h = list:getSize().h + S(8)
        add(FrameContainer:new{ padding = 0, bordersize = S(2), radius = S(2), background = Blitbuffer.gray(0.04),
            HorizontalGroup:new{ align = "top",
                Skeuo.Spine:new{ w = spine_w, h = list_h, text = title },
                FrameContainer:new{ padding = S(4), bordersize = 0, background = Blitbuffer.gray(0.04), list },
                Skeuo.Spine:new{ w = spine_w, h = list_h, text = title, down_up = true },
            } })
    end
    gap(6)
    if not Touch.on() then
        add(TextWidget:new{ text = _("◀ ▶ track · ▲ ▼ the queue, Press plays · Back: close (keeps playing)"),
            face = face(13), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = inner })
    else
        add(Touch.chips(inner, { { _("Close (keeps playing)"), function() self:onClose() end } }, self))
    end
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group } }
    self:schedule()
end

--- The time on the display: every 30 s (each redraw costs battery).
function CDScreen:schedule()
    if self.tick then UIManager:unschedule(self.tick) end
    self.tick = function()
        self.tick = nil
        local p = self:player()
        if p and p.playing then self:build(); UIManager:setDirty(self, "fast") end
    end
    UIManager:scheduleIn(30, self.tick)
end

function CDScreen:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

local function act(self, fn)
    local p = self:player()
    if p then fn(p) end
    self:refresh()
    return true
end
function CDScreen:onPrev() return act(self, function(p) p:step(-1) end) end
function CDScreen:onNext() return act(self, function(p) p:step(1) end) end
function CDScreen:onPrevKey() return self:onPrev() end
function CDScreen:onNextKey() return self:onNext() end
function CDScreen:onToggle() return act(self, function(p) p:toggle() end) end
function CDScreen:onShuffle() return act(self, function(p) p:setShuffle(not p.shuffle) end) end
function CDScreen:onRepeat() return act(self, function(p) p:cycleRepeat() end) end
function CDScreen:onStop() return act(self, function(p) p:stop() end) end
function CDScreen:onUp()
    local p = self:player()
    if p then self.picked = math.max(1, (self.picked or p.at) - 1) end
    self:refresh()
    return true
end
function CDScreen:onDown()
    local p = self:player()
    if p then self.picked = math.min(#p.order, (self.picked or p.at) + 1) end
    self:refresh()
    return true
end
function CDScreen:onPlay()
    local p = self:player()
    if p and self.picked and self.picked ~= p.at then p:jump(self.picked) elseif p then p:toggle() end
    self.picked = nil
    self:refresh()
    return true
end

function CDScreen:onClose() UIManager:close(self, "full"); return true end
function CDScreen:onCloseMenu() return self:onClose() end

function CDScreen:onShow() UIManager:setDirty(self, "full") end

function CDScreen:onCloseWidget()
    Music().listeners[self.listener_key] = nil
    if self.tick then UIManager:unschedule(self.tick); self.tick = nil end
    if self.cover_bb then self.cover_bb:free(); self.cover_bb = nil end
end

function CDScreen.show(plugin)
    local w = CDScreen:new{ plugin = plugin }
    UIManager:show(w)
    return w
end

return CDScreen
