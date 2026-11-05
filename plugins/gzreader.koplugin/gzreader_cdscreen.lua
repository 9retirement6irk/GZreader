--[[--
Music's player: a portable CD player with headphones (gzreader_deck.lua),
the album's cover on the disc, the track and time on its display; the track
and the album under it, then the controls and the queue, like the back of a
CD case.

Everything music happens here (1.22): the CD case insert under the
controls is either the queue or the library (F switches; the Music tab, the
quick panel and Downloads → Music open it): Downloaded, Shuffle all,
Artists, Albums, Playlists, Search and the Plex account, an album or
playlist's Play / Shuffle / Download / Delete and its tracks. The lists are
the Music tab's (gzreader_musictab.lua), shown on the insert instead of a
menu.

Keys (Kindle Keyboard): Q previous, W play / pause, E next, A shuffle,
S repeat, D stop, F queue / library; ◀ ▶ previous / next track (in the
library: its pages); ▲ ▼ through the list, Press plays or opens the one
picked; Back goes back up the library, then closes (the music keeps
playing); Home: Home. Touch: the buttons, a tap on a line.
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

local CDScreen = InputContainer:extend{ name = "gzreader cd player", plugin = nil, covers_fullscreen = true, library = false }

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
        Library = { { "F" } },
        Home = { { "Home" } },
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        CloseMenu = { { "Menu" } },
    }
    self.picked = nil
    self.mode = (self.library or not Music().current) and "library" or "now"
    self.listener_key = "cdscreen-" .. tostring(self)
    Music().listeners[self.listener_key] = function()
        self.picked = nil
        -- (the library's first list says what plays: keep it current)
        if self.nav and #self.nav.item_table_stack == 0 then self.nav.item_table = self.tab:rootItems() end
        self:refresh()
    end
    CDScreen.instance = self
    self:build()
end

---------------------------------------------------------------- the library

--- The Music tab's lists, on the case insert: a stand-in for its Menu
--- (what gzreader_musictab.lua uses of it).
local Nav = {}
Nav.__index = Nav

function Nav:switchItemTable(title, items)
    local depth = #self.item_table_stack
    if depth > self.depth then
        table.insert(self.sels, self.screen.sel or 1) -- a list opened: where we were, for Back
        self.screen.sel = 1
    end
    self.depth = depth
    if title then self.title = title end
    if items then self.item_table = items end
    self.screen.sel = math.max(1, math.min(self.screen.sel or 1, #self.item_table))
    self.screen:refresh()
end

function Nav:onClose()
    local prev = table.remove(self.item_table_stack)
    if prev then
        self.item_table = prev
        self.title = prev.title or self.title
        self.screen.sel = table.remove(self.sels) or 1
    end
    self.depth = #self.item_table_stack
    self.screen:refresh()
end

function CDScreen:ensureLibrary()
    if self.nav then return end
    local Tab = require("gzreader_musictab")
    self.tab = Tab.new(self.plugin)
    self.nav = setmetatable({ screen = self, item_table_stack = {}, sels = {}, depth = 0, title = _("Music") }, Nav)
    self.tab.menu = self.nav
    self.nav.item_table = self.tab:rootItems()
    self.sel = 1
end

--- What plays, on the insert (the library: back to it with F).
function CDScreen:showNow()
    self.mode = Music().current and "now" or "library"
    self.picked = nil
    self:refresh()
end

function CDScreen:selectLine(i)
    local it = self.nav and self.nav.item_table[i]
    if not it or it.select_enabled == false then return end
    self.sel = i
    if it.callback then it.callback() else self:refresh() end
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
    local lib = self.mode == "library"
    if lib then self:ensureLibrary() end
    local deck_w = math.min(math.floor(sw * 0.86), math.floor(sh * (lib and 0.22 or 0.36) * 360 / 300))
    add(require("gzreader_deck").CD:new{ w = deck_w, state = {
        cover_bb = self:cover(p), track = p and p.order[p.at] or nil,
        time = p and (p.waiting and "--:--" or fmtTime(p:position())) or "", playing = p and p.playing,
    } })
    gap(6)
    if lib then
        -- (the library: what plays is on the display; the room goes to the list)
        add(TextWidget:new{ text = p and ((t.title or "?") .. "  ·  " .. (p.c.title or "")) or _("Nothing playing."),
            face = face(15, true), max_width = inner })
    elseif not p then
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
    if not lib then add(pills({
        { (p and p.shuffle) and _("Shuffle on") or _("Shuffle"), "A", function() self:onShuffle() end, p and p.shuffle },
        { ({ off = _("Repeat"), all = _("Repeat all"), one = _("Repeat one") })[rep] or _("Repeat"), "S",
            function() self:onRepeat() end, rep ~= "off" },
        { _("Stop"), "D", function() self:onStop() end, icon = "stop" },
    })) end
    gap(10)
    -- the insert's two sides: the queue and the library (F)
    add(self:insertTabs(inner))
    gap(4)
    if lib then
        local used = group:getSize().h
        group:resetLayout() -- (measured: its layout is worked out again with the insert)
        add(self:libraryInsert(inner, sh - used - S(60)))
    -- the queue: the back insert of a CD case, its spines either side
    elseif p then
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
        add(TextWidget:new{ text = lib and _("▲ ▼ choose, Press opens · ◀ ▶ pages · Back: back · F: the queue")
            or _("◀ ▶ track · ▲ ▼ the queue, Press plays · F: library · Back: close (keeps playing)"),
            face = face(13), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = inner })
    else
        add(Touch.chips(inner, { lib and #(self.nav and self.nav.item_table_stack or {}) > 0
            and { _("Back"), function() self:onClose() end } or { _("Close (keeps playing)"), function() self:onClose(true) end } }, self))
    end
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, width = sw, height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group } }
    self:schedule()
end

--- The insert's two tabs: Queue and Library (F, or a tap).
local Tab_ = InputContainer:extend{ w = 0, h = 0, on = false, label = "", screen = nil, mode = nil }
function Tab_:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    local range = function() return self.dimen end
    self.ges_events = { TapTab = { GestureRange:new{ ges = "tap", range = range } } }
    self[1] = FrameContainer:new{ width = self.w, height = self.h, padding = 0, bordersize = S(2), radius = S(4),
        color = Blitbuffer.COLOR_BLACK, background = self.on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = self.w - S(4), h = self.h - S(4) },
            TextWidget:new{ text = self.label, face = face(15, true), fgcolor = self.on and Blitbuffer.COLOR_WHITE or nil } } }
end
function Tab_:onTapTab()
    if self.screen.mode ~= self.mode then self.screen:onLibrary() end
    return true
end

function CDScreen:insertTabs(inner)
    local key = Touch.keys() and "F  " or ""
    local w = math.floor((inner - S(8)) / 2)
    local lib = self.mode == "library"
    return HorizontalGroup:new{ align = "center",
        Tab_:new{ w = w, h = S(30), on = not lib, label = (lib and key or "") .. _("Queue"), screen = self, mode = "now" },
        HorizontalSpan:new{ width = S(8) },
        Tab_:new{ w = w, h = S(30), on = lib, label = (lib and "" or key) .. _("Library"), screen = self, mode = "library" },
    }
end

--- A line of the library: tap opens it.
local Line = InputContainer:extend{ w = 0, h = 0, i = 0, screen = nil }
function Line:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    local range = function() return self.dimen end
    self.ges_events = { TapLine = { GestureRange:new{ ges = "tap", range = range } } }
end
function Line:onTapLine() self.screen:selectLine(self.i); return true end

--- The library's list on the CD case insert, `h` high at most.
function CDScreen:libraryInsert(inner, h)
    local nav = self.nav
    local items = nav.item_table
    local spine_w = S(22)
    local list_w = inner - 2 * spine_w - S(4)
    local rh = S(32)
    local rows = math.max(3, math.floor((h - S(16)) / rh))
    self.rows = rows
    local sel = math.max(1, math.min(self.sel or 1, #items))
    local first = math.floor((sel - 1) / rows) * rows + 1
    local list = VerticalGroup:new{ align = "left" }
    for i = first, math.min(#items, first + rows - 1) do
        local it = items[i]
        local on = i == sel and Device:hasDPad()
        local off = it.select_enabled == false
        local right = it.mandatory and TextWidget:new{ text = tostring(it.mandatory), face = face(13),
            fgcolor = on and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_DARK_GRAY } or nil
        local rw = right and right:getSize().w or 0
        local left = TextWidget:new{ text = it.text or "", face = face(15, it.bold), bold = it.bold,
            fgcolor = on and Blitbuffer.COLOR_WHITE or (off and Blitbuffer.COLOR_DARK_GRAY or nil),
            max_width = list_w - S(24) - rw - S(10) }
        local content = HorizontalGroup:new{ align = "center", left }
        if right then
            content[#content + 1] = HorizontalSpan:new{ width = math.max(S(6), list_w - S(20) - left:getSize().w - rw) }
            content[#content + 1] = right
        end
        local line = Line:new{ w = list_w, h = rh, i = i, screen = self }
        line[1] = FrameContainer:new{ width = list_w, height = rh, padding = 0, padding_left = S(8), bordersize = 0,
            background = on and Blitbuffer.COLOR_BLACK or Blitbuffer.gray(0.04), radius = on and S(4) or 0, content }
        list[#list + 1] = line
    end
    local pages = math.max(1, math.ceil(#items / rows))
    local title = (nav.title or _("Music")) .. (pages > 1 and ("  ·  " .. math.ceil(sel / rows) .. "/" .. pages) or "")
    local list_h = math.max(list:getSize().h, rows * rh) + S(8)
    local Skeuo = require("gzreader_skeuo")
    return FrameContainer:new{ padding = 0, bordersize = S(2), radius = S(2), background = Blitbuffer.gray(0.04),
        HorizontalGroup:new{ align = "top",
            Skeuo.Spine:new{ w = spine_w, h = list_h, text = title },
            FrameContainer:new{ padding = S(4), bordersize = 0, background = Blitbuffer.gray(0.04), width = list_w + S(8), height = list_h, list },
            Skeuo.Spine:new{ w = spine_w, h = list_h, text = title, down_up = true },
        } }
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
function CDScreen:onPrevKey()
    if self.mode == "library" then return self:pageBy(-1) end
    return self:onPrev()
end
function CDScreen:onNextKey()
    if self.mode == "library" then return self:pageBy(1) end
    return self:onNext()
end
function CDScreen:pageBy(dir)
    local n = self.nav and #self.nav.item_table or 0
    local rows = self.rows or 8
    self.sel = math.max(1, math.min(n, (self.sel or 1) + dir * rows))
    self:refresh()
    return true
end
function CDScreen:onLibrary()
    self.mode = self.mode == "library" and (Music().current and "now" or "library") or "library"
    self.picked = nil
    self:refresh()
    return true
end
function CDScreen:onHome()
    return require("gzreader_tabs").goHome(self)
end
function CDScreen:onToggle() return act(self, function(p) p:toggle() end) end
function CDScreen:onShuffle() return act(self, function(p) p:setShuffle(not p.shuffle) end) end
function CDScreen:onRepeat() return act(self, function(p) p:cycleRepeat() end) end
function CDScreen:onStop() return act(self, function(p) p:stop() end) end
function CDScreen:onUp()
    if self.mode == "library" then
        self.sel = math.max(1, (self.sel or 1) - 1)
        self:refresh()
        return true
    end
    local p = self:player()
    if p then self.picked = math.max(1, (self.picked or p.at) - 1) end
    self:refresh()
    return true
end
function CDScreen:onDown()
    if self.mode == "library" then
        self.sel = math.min(#self.nav.item_table, (self.sel or 1) + 1)
        self:refresh()
        return true
    end
    local p = self:player()
    if p then self.picked = math.min(#p.order, (self.picked or p.at) + 1) end
    self:refresh()
    return true
end
function CDScreen:onPlay()
    if self.mode == "library" then
        self:selectLine(self.sel or 1)
        return true
    end
    local p = self:player()
    if p and self.picked and self.picked ~= p.at then p:jump(self.picked) elseif p then p:toggle() end
    self.picked = nil
    self:refresh()
    return true
end

function CDScreen:onClose(really)
    -- the library: back up a list first
    if not really and self.mode == "library" and self.nav and #self.nav.item_table_stack > 0 then
        self.nav:onClose()
        return true
    end
    UIManager:close(self, "full")
    return true
end
function CDScreen:onCloseMenu() return self:onClose() end

function CDScreen:onShow() UIManager:setDirty(self, "full") end

function CDScreen:onCloseWidget()
    Music().listeners[self.listener_key] = nil
    if self.tab then self.tab.closed = true end
    if CDScreen.instance == self then CDScreen.instance = nil end
    if self.tick then UIManager:unschedule(self.tick); self.tick = nil end
    if self.cover_bb then self.cover_bb:free(); self.cover_bb = nil end
end

--- The CD player: what plays (or the library when nothing does, or with
--- opts.library).
function CDScreen.show(plugin, opts)
    local open = CDScreen.instance
    if open then
        if opts and opts.library then open.mode = "library" else open:showNow() end
        open:refresh()
        return open
    end
    local w = CDScreen:new{ plugin = plugin, library = opts and opts.library or false }
    UIManager:show(w)
    return w
end

return CDScreen
