--[[--
Music's player: three tabs along the top (Now playing, Queue, Library),
each a whole screen, with big keys for touch Kindles.

- Now playing: the portable CD player (gzreader_deck.lua) with the album's
  cover over the disc and the track and time on its display; the track, a
  progress strip (tap it to jump to that time), previous · play / pause ·
  next (play the biggest), then shuffle · repeat · the volume.
- Queue: what plays on a strip at the top (tap it for Now playing; its
  pause key), the queue on the back of a CD case in big rows (tap one to
  play it), the pages, Shuffle and Stop.
- Library: the Music tab's lists (gzreader_musictab.lua) on the same CD
  case: Recently played, Recently added, Playlists, Albums, Artists, On
  this Kindle; Search above the list, Shuffle all and the Plex account
  below it (on a Kindle with keys they are lines of the list, so the 5-way
  reaches them). Inside a list: Back and where you are at the top.

Keys (Kindle 2, Keyboard, DX), each on its button: Q previous, W play /
pause, E next, A shuffle, S repeat, D stop; Z X C the tabs (F still goes
between the queue and the library). Now playing: ◀ ▶ 10 s back / ahead,
Press play / pause. The lists: ▲ ▼ choose, Press plays or opens, ◀ ▶
pages. Back goes back up the library, then closes (the music keeps
playing); Home: Home. The volume: the Kindle's volume keys.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Touch = require("gzreader_touch")
local _ = require("gettext")
local T = require("ffi/util").template

local CDScreen = InputContainer:extend{ name = "gzreader cd player", plugin = nil, covers_fullscreen = true, library = false,
    gz_player = true } -- (gz_player: no flashes inside it on a Kindle 3, gzreader_eink)

local function Music() return require("gzreader_music") end
local function Engine() return require("gzreader_audioengine") end
local function fmtTime(ms)
    local s = math.floor((tonumber(ms) or 0) / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function face(size, bold) return Font:getFace(bold and "smalltfont" or "cfont", size) end
local function S(px) return Device.screen:scaleBySize(px) end

--- Sizes from the mockup (600 × 800, a Kindle Touch), scaled to the screen.
--- Everything you tap is 56 or more (about 8.5 mm on a Kindle Touch); the
--- progress strip is 48 high, the whole of it a target.
CDScreen.SIZE = { top = 56, transport = 96, modes = 64, row = 62, pager = 60, mini = 72, seek = 48, margin = 24, close = 56 }
CDScreen.SEEK_MS = 10000   -- ◀ ▶ on Now playing
CDScreen.SEEK_GATHER = 0.8 -- presses close together: the player started once, where they end
CDScreen.VOLUME_MAX = 15

--- The tabs: what each shows, its key, its name.
CDScreen.TABS = {
    { mode = "now", key = "Z", label = _("Now playing") },
    { mode = "queue", key = "X", label = _("Queue") },
    { mode = "library", key = "C", label = _("Library") },
}

--- How many rows of `row` (+ a gap of `gap`) fit in `h` (at least 3).
function CDScreen.rowsFor(h, row, gap)
    return math.max(3, math.floor((h - 2 * gap) / (row + gap)))
end

--- The page holding line `at` of `n`, `rows` a page: its first line, the
--- page's number and how many there are.
function CDScreen.pageOf(at, rows, n)
    local pages = math.max(1, math.ceil(n / rows))
    local page = math.max(1, math.min(pages, math.floor((math.max(1, at) - 1) / rows) + 1))
    return (page - 1) * rows + 1, page, pages
end

--- The keys (Kindles with a keyboard): event → key.
function CDScreen.keyEvents()
    return {
        Prev = { { "Q" } }, Toggle = { { "W" } }, Next = { { "E" } },
        Shuffle = { { "A" } }, Repeat = { { "S" } }, Stop = { { "D" } },
        TabNow = { { "Z" } }, TabQueue = { { "X" } }, TabLibrary = { { "C" } },
        Library = { { "F" } },
        PrevKey = { { "Left" } }, NextKey = { { "Right" } },
        Up = { { "Up" } }, Down = { { "Down" } }, Play = { { "Press" } },
        Home = { { "Home" } },
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        CloseMenu = { { "Menu" } },
    }
end

function CDScreen:init()
    local sw, sh = Device.screen:getWidth(), Device.screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.key_events = CDScreen.keyEvents()
    self.picked = nil
    self.mode = (self.library or not Music().current) and "library" or "now"
    self.listener_key = "cdscreen-" .. tostring(self)
    Music().listeners[self.listener_key] = function()
        self.picked = nil
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
    self.nav.item_table = self.tab:playerRootItems(not Touch.on())
    self.sel = 1
end

--- What plays (the library when nothing does).
function CDScreen:showNow()
    self.mode = Music().current and "now" or "library"
    self.picked = nil
    self:refresh()
end

--- Show tab `mode` ("now", "queue", "library").
function CDScreen:setMode(mode)
    self.mode = mode
    self.picked = nil
    if mode == "library" then self:ensureLibrary() end
    self:refresh()
    return true
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

---------------------------------------------------------------- pieces

--- Something you tap: `callback`; what it shows is its [1].
local Tap = InputContainer:extend{ w = 0, h = 0, callback = nil }
CDScreen.Tap = Tap
function Tap:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    local range = function() return self.dimen end
    self.ges_events = { TapIt = { GestureRange:new{ ges = "tap", range = range } } }
end
function Tap:onTapIt()
    if self.callback then self.callback() end
    return true
end

--- The progress strip: the whole of it a target; a tap jumps to that time.
local SeekBar = InputContainer:extend{ w = 0, h = 0, frac = 0, screen = nil }
CDScreen.SeekBar = SeekBar
function SeekBar:init()
    self.dimen = Geom:new{ w = self.w, h = self.h }
    local range = function() return self.dimen end
    self.ges_events = { TapSeek = { GestureRange:new{ ges = "tap", range = range } } }
end
function SeekBar:getSize() return Geom:new{ w = self.w, h = self.h } end
function SeekBar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local w = self.w
    local b = math.max(1, S(2))
    local th = S(12)
    local ty = y + math.floor((self.h - th) / 2)
    bb:paintRect(x, ty, w, th, Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + b, ty + b, w - 2 * b, th - 2 * b, Blitbuffer.COLOR_WHITE)
    local frac = math.max(0, math.min(1, self.frac or 0))
    local fw = math.floor((w - 2 * b) * frac)
    if fw > 0 then bb:paintRect(x + b, ty + b, fw, th - 2 * b, Blitbuffer.gray(0.6)) end
    local r = S(13)
    local cx = x + math.max(r, math.min(w - r, math.floor(w * frac)))
    local cy = y + math.floor(self.h / 2)
    bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK)
    bb:paintCircle(cx, cy, r - S(3), Blitbuffer.COLOR_WHITE)
    bb:paintCircle(cx, cy, r - S(5), Blitbuffer.COLOR_BLACK)
end
--- Where the tap was, as a fraction of the strip.
function SeekBar:fracAt(ges)
    if not (ges and ges.pos and self.dimen and self.dimen.x) then return nil end
    return math.max(0, math.min(1, (ges.pos.x - self.dimen.x) / math.max(1, self.dimen.w)))
end
function SeekBar:onTapSeek(_arg, ges)
    local f = self:fracAt(ges)
    if f and self.screen then self.screen:seekToFrac(f) end
    return true
end

--- A key (gzreader_skeuo.lua): its letter on it on Kindles with a keyboard.
function CDScreen:key(o)
    local Skeuo = require("gzreader_skeuo")
    return Skeuo.Key:new{ shape = o.shape or "key", w = o.w, h = o.h, label = o.label or "", icon = o.icon,
        letter = Touch.keys() and o.letter or nil, callback = o.callback, down = o.down and true or false,
        font_size = o.font_size or 16 }
end

local function text(str, size, bold, max_width, color)
    return TextWidget:new{ text = str, face = face(size, bold), bold = bold, max_width = max_width, fgcolor = color }
end

--- The keys' hints under a screen (Kindles with a keyboard: what has no
--- button). Nothing on touch Kindles.
local function hint(str, inner)
    if not Touch.keys() then return nil end
    return text(str, 13, false, inner, Blitbuffer.COLOR_DARK_GRAY)
end

--- Close, then the three tabs.
function CDScreen:topRow(inner)
    local h = S(CDScreen.SIZE.top)
    local gap = S(8)
    local keys = Touch.keys()
    local up = keys and self.mode == "library" and self.nav and #self.nav.item_table_stack > 0
    local close_w = keys and S(84) or S(CDScreen.SIZE.close)
    local row = HorizontalGroup:new{ align = "center",
        -- (on a Kindle with keys: which key closes; in a list Back goes up one, so Home)
        self:key{ w = close_w, h = h, label = keys and (up and _("Home") or _("Back")) or "\u{00D7}", font_size = keys and 15 or 26,
            callback = function() self:onClose(true) end },
    }
    local w = math.floor((inner - close_w - 3 * gap) / 3)
    local p = self:player()
    for _i, t in ipairs(CDScreen.TABS) do
        local label = t.label
        if t.mode == "queue" and p and #p.order > 0 then label = T("%1 · %2", label, #p.order) end
        row[#row + 1] = HorizontalSpan:new{ width = gap }
        row[#row + 1] = self:key{ w = w, h = h, label = label, letter = t.key, down = self.mode == t.mode, font_size = 16,
            callback = function() self:setMode(t.mode) end }
    end
    return row
end

--- What plays, on a strip (the Queue and Library tabs): tap it for Now
--- playing; its pause key.
function CDScreen:miniBar(inner, p)
    local h = S(CDScreen.SIZE.mini)
    local t = p:track() or {}
    local key_w = S(Touch.keys() and 100 or 80)
    local pad = S(10)
    local cover = self:cover(p)
    local thumb
    local side = S(52)
    if cover then
        local ImageWidget = require("ui/widget/imagewidget")
        thumb = ImageWidget:new{ image = cover, image_disposable = false, width = side, height = side, scale_factor = 0 }
    else
        thumb = FrameContainer:new{ padding = 0, bordersize = S(2), background = Blitbuffer.gray(0.35),
            CenterContainer:new{ dimen = Geom:new{ w = side - 2 * S(2), h = side - 2 * S(2) }, VerticalSpan:new{ width = 0 } } }
    end
    local text_w = inner - 2 * S(2) - pad - side - pad - key_w - S(8) - pad
    local pos = self.seek_target or p:position()
    local info = VerticalGroup:new{ align = "left",
        text(t.title or "?", 17, true, text_w),
        text((p.waiting and _("downloading…") or (fmtTime(pos) .. " / " .. fmtTime(t.duration)))
            .. "  ·  " .. (p.c.artist or p.c.title or ""), 14, false, text_w),
    }
    local area = Tap:new{ w = side + pad + text_w, h = h - 2 * S(2), callback = function() self:setMode("now") end }
    area[1] = HorizontalGroup:new{ align = "center", thumb, HorizontalSpan:new{ width = pad }, info }
    return FrameContainer:new{ width = inner, height = h, padding = 0, padding_left = pad, bordersize = S(2), radius = S(14),
        background = Blitbuffer.gray(0.08),
        HorizontalGroup:new{ align = "center",
            area,
            HorizontalSpan:new{ width = S(8) },
            self:key{ w = key_w, h = S(58), icon = p.playing and "pause" or "play", letter = "W", down = p.playing,
                callback = function() self:onToggle() end },
        } }
end

--- Lines on the back of a CD case, its spines either side. `lines`:
--- { text, right, bold, current (black), selected (ringed), dim,
--- callback }; `rows` of them fit; `title` on the spines.
function CDScreen:case(inner, lines, rows, title)
    local Skeuo = require("gzreader_skeuo")
    local spine_w = S(26)
    local list_w = inner - 2 * spine_w - S(4) - S(12)
    local rh, gap = S(CDScreen.SIZE.row), S(4)
    local list = VerticalGroup:new{ align = "left" }
    for i, l in ipairs(lines) do
        if i > 1 then list[#list + 1] = VerticalSpan:new{ width = gap } end
        local ink = l.current and Blitbuffer.COLOR_WHITE or (l.dim and Blitbuffer.COLOR_DARK_GRAY or nil)
        local right = l.right and text(tostring(l.right), 15, false, math.floor(list_w * 0.4), ink) or nil
        local press = l.selected and l.press and FrameContainer:new{ padding = 0, padding_left = S(4), padding_right = S(4),
            bordersize = S(2), radius = S(3), background = Blitbuffer.COLOR_WHITE, text(l.press, 12, true) } or nil
        local rw = (right and right:getSize().w or 0) + (press and (press:getSize().w + S(8)) or 0)
        local left = text(l.text or "", 18, l.bold or l.current, list_w - S(28) - rw - S(10), ink)
        local content = HorizontalGroup:new{ align = "center", left }
        content[#content + 1] = HorizontalSpan:new{ width = math.max(S(6), list_w - S(28) - left:getSize().w - rw) }
        if press then content[#content + 1] = press; content[#content + 1] = HorizontalSpan:new{ width = S(8) } end
        if right then content[#content + 1] = right end
        local line = Tap:new{ w = list_w, h = rh, callback = l.callback }
        local b = l.selected and S(3) or 0
        line[1] = FrameContainer:new{ width = list_w, height = rh, padding = 0, padding_left = S(12) - b,
            bordersize = b, color = Blitbuffer.COLOR_BLACK, radius = (l.current or l.selected) and S(8) or 0,
            background = l.current and Blitbuffer.COLOR_BLACK or (l.selected and Blitbuffer.COLOR_WHITE or Blitbuffer.gray(0.05)),
            LeftContainer:new{ dimen = Geom:new{ w = list_w - S(12), h = rh - 2 * b }, content } }
        list[#list + 1] = line
    end
    local list_h = rows * rh + (rows - 1) * gap + S(12)
    return FrameContainer:new{ padding = 0, bordersize = S(3), radius = S(4), background = Blitbuffer.gray(0.05),
        HorizontalGroup:new{ align = "top",
            Skeuo.Spine:new{ w = spine_w, h = list_h, text = title },
            FrameContainer:new{ padding = S(6), bordersize = 0, background = Blitbuffer.gray(0.05), width = list_w + S(12), height = list_h, list },
            Skeuo.Spine:new{ w = spine_w, h = list_h, text = title, down_up = true },
        } }
end

--- ▲ Up / Down ▼ (◀ ▶ on a Kindle with keys) round `what` (the page).
function CDScreen:pager(inner, what)
    local keys = Touch.keys()
    local w, h = S(124), S(CDScreen.SIZE.pager)
    return HorizontalGroup:new{ align = "center",
        self:key{ w = w, h = h, label = keys and _("◀ Page") or _("▲ Up"), callback = function() self:pageBy(-1) end },
        CenterContainer:new{ dimen = Geom:new{ w = inner - 2 * w, h = h }, text(what, 17) },
        self:key{ w = w, h = h, label = keys and _("Page ▶") or _("Down ▼"), callback = function() self:pageBy(1) end },
    }
end

---------------------------------------------------------------- the tabs

--- Now playing: the CD player, the track, the strip, the keys.
function CDScreen:nowBody(inner, avail, p)
    local SZ = CDScreen.SIZE
    local below = VerticalGroup:new{ align = "center" }
    local function add(w) if w then below[#below + 1] = w end end
    local function gap(px) add(VerticalSpan:new{ width = S(px) }) end
    local t = p and p:track() or {}
    local dur = tonumber(t.duration) or 0
    local pos = p and (self.seek_target or p:position()) or 0
    if not p then
        add(text(_("Nothing playing."), 22, true, inner))
        gap(6)
        add(text(_("Choose an album or a playlist in the Library."), 16, false, inner))
    else
        add(text(t.title or "?", 24, true, inner))
        add(text(((t.artist or p.c.artist) and ((t.artist or p.c.artist) .. " — ") or "") .. (p.c.title or ""), 16, false, inner))
        gap(10)
        local tw = S(52)
        add(HorizontalGroup:new{ align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = tw, h = S(SZ.seek) },
                text(p.waiting and "--:--" or fmtTime(pos), 15) },
            HorizontalSpan:new{ width = S(8) },
            SeekBar:new{ w = inner - 2 * tw - 2 * S(8), h = S(SZ.seek), frac = dur > 0 and pos / dur or 0, screen = self },
            HorizontalSpan:new{ width = S(8) },
            CenterContainer:new{ dimen = Geom:new{ w = tw, h = S(SZ.seek) }, text(fmtTime(dur), 15) },
        })
    end
    gap(16)
    -- previous · play / pause · next: play the biggest
    local th, kg = S(SZ.transport), S(16)
    local mid = math.floor(inner * 0.38)
    local side = math.floor((inner - mid - 2 * kg) / 2)
    local playing = p and p.playing
    add(HorizontalGroup:new{ align = "center",
        self:key{ shape = "pill", w = side, h = th, icon = "prev", letter = "Q", callback = function() self:onPrev() end },
        HorizontalSpan:new{ width = kg },
        self:key{ shape = "pill", w = mid, h = th, icon = playing and "pause" or "play", label = playing and _("Pause") or _("Play"),
            letter = "W", down = playing, font_size = 19, callback = function() self:onToggle() end },
        HorizontalSpan:new{ width = kg },
        self:key{ shape = "pill", w = side, h = th, icon = "next", letter = "E", callback = function() self:onNext() end },
    })
    gap(20)
    -- shuffle · repeat · the volume (− + on touch Kindles; the volume keys on the others)
    local mh, mg = S(SZ.modes), S(12)
    local vol = Engine().volume()
    local vol_w, volw
    if Touch.keys() then
        vol_w = math.floor(inner * 0.3)
        volw = FrameContainer:new{ width = vol_w, height = mh - S(5), padding = 0, bordersize = S(2), radius = S(12),
            CenterContainer:new{ dimen = Geom:new{ w = vol_w - S(4), h = mh - S(9) }, VerticalGroup:new{ align = "center",
                text(T(_("Volume %1"), vol), 16, true), text(_("the volume keys"), 13, false, vol_w - S(8)) } } }
    else
        local kw = S(64)
        vol_w = 2 * kw + S(80)
        volw = HorizontalGroup:new{ align = "center",
            self:key{ w = kw, h = mh, label = "\u{2212}", font_size = 24, callback = function() self:stepVolume(-1) end },
            CenterContainer:new{ dimen = Geom:new{ w = S(80), h = mh }, VerticalGroup:new{ align = "center",
                text(_("Volume"), 13), text(tostring(vol), 18, true) } },
            self:key{ w = kw, h = mh, label = "+", font_size = 24, callback = function() self:stepVolume(1) end },
        }
    end
    local mw = math.floor((inner - vol_w - 2 * mg) / 2)
    local rep = p and p["repeat"] or "off"
    add(HorizontalGroup:new{ align = "center",
        self:key{ w = mw, h = mh, label = (p and p.shuffle) and _("Shuffle on") or _("Shuffle"), letter = "A", down = p and p.shuffle,
            callback = function() self:onShuffle() end },
        HorizontalSpan:new{ width = mg },
        self:key{ w = mw, h = mh, label = ({ off = _("Repeat"), all = _("Repeat all"), one = _("Repeat one") })[rep] or _("Repeat"),
            letter = "S", down = rep ~= "off", callback = function() self:onRepeat() end },
        HorizontalSpan:new{ width = mg },
        volw,
    })
    local h = hint(_("◀ ▶ 10 s back / ahead  ·  D stop  ·  Back: close (the music keeps playing)"), inner)
    if h then gap(14); add(h) end
    -- the CD player gets the room left (the drawing is 360 × 300)
    local room = avail - below:getSize().h - S(12)
    local deck_w = math.min(math.floor(room * 360 / 300), math.floor(inner * 0.86))
    local body = VerticalGroup:new{ align = "center" }
    local extra = math.max(0, room - math.floor(deck_w * 300 / 360))
    body[#body + 1] = VerticalSpan:new{ width = math.floor(extra / 3) }
    if deck_w >= S(120) then
        body[#body + 1] = require("gzreader_deck").CD:new{ w = deck_w, state = {
            cover_bb = self:cover(p), track = p and p.order[p.at] or nil,
            time = p and (p.waiting and "--:--" or fmtTime(pos)) or "", playing = p and p.playing,
        } }
    end
    body[#body + 1] = VerticalSpan:new{ width = S(12) + math.floor(extra / 3) }
    body[#body + 1] = below
    return body
end

--- Queue: the strip, the queue in big rows, the pages, Shuffle and Stop.
function CDScreen:queueBody(inner, avail, p)
    local body = VerticalGroup:new{ align = "center" }
    local function add(w) if w then body[#body + 1] = w end end
    local function gap(px) add(VerticalSpan:new{ width = S(px) }) end
    if not p then
        gap(60)
        add(text(_("Nothing in the queue."), 20, true, inner))
        gap(8)
        add(text(_("Choose an album or a playlist in the Library."), 16, false, inner))
        gap(24)
        add(self:key{ w = S(220), h = S(CDScreen.SIZE.pager), label = _("Library"), letter = "C", callback = function() self:setMode("library") end })
        return body
    end
    local SZ = CDScreen.SIZE
    local h = hint(_("▲ ▼ choose  ·  Press plays it  ·  ◀ ▶ pages"), inner)
    local fixed = S(SZ.mini) + S(14) + S(14) + S(SZ.pager) + S(14) + S(SZ.modes) + (h and (S(10) + h:getSize().h) or 0)
    local rows = CDScreen.rowsFor(avail - fixed - S(6), S(SZ.row), S(4))
    self.rows = rows
    local first = CDScreen.pageOf(self.picked or p.at, rows, #p.order)
    local pages = math.max(1, math.ceil(#p.order / rows))
    local dpad = Device:hasDPad()
    local lines = {}
    for n = first, math.min(#p.order, first + rows - 1) do
        local tr = p.c.tracks[p.order[n]] or {}
        local cur = n == p.at
        lines[#lines + 1] = { text = string.format("%02d  ", n) .. (cur and "\u{25B6} " or "") .. (tr.title or "?"),
            right = fmtTime(tr.duration), current = cur, selected = dpad and self.picked == n and not cur, press = _("Press plays"),
            callback = function()
                local pl = self:player()
                if pl then pl:jump(n) end
                self.picked = nil
                self:refresh()
            end }
    end
    add(self:miniBar(inner, p))
    gap(14)
    add(self:case(inner, lines, rows, (p.c.title or "") .. ((p.c.artist and p.c.artist ~= "") and ("  ·  " .. p.c.artist) or "")))
    gap(14)
    add(self:pager(inner, pages > 1 and T(_("tracks %1–%2 of %3"), first, math.min(#p.order, first + rows - 1), #p.order)
        or T(_("%1 tracks"), #p.order)))
    gap(14)
    local kw = math.floor((inner - S(12)) / 2)
    add(HorizontalGroup:new{ align = "center",
        self:key{ w = kw, h = S(SZ.modes), label = p.shuffle and _("Shuffle on") or _("Shuffle"), letter = "A", down = p.shuffle,
            callback = function() self:onShuffle() end },
        HorizontalSpan:new{ width = S(12) },
        self:key{ w = kw, h = S(SZ.modes), icon = "stop", label = _("Stop"), letter = "D", callback = function() self:onStop() end },
    })
    if h then gap(10); add(h) end
    return body
end

--- Library: the strip, the lists (Search above, Shuffle all and the
--- account below at the top), Back and where you are inside them.
function CDScreen:libraryBody(inner, avail, p)
    local SZ = CDScreen.SIZE
    local nav = self.nav
    local items = nav.item_table
    local depth = #nav.item_table_stack
    local touch = Touch.on()
    local body = VerticalGroup:new{ align = "center" }
    local parts = {}
    local function part(w) parts[#parts + 1] = w end
    if p then part(self:miniBar(inner, p)) end
    if depth > 0 then
        local prev = nav.item_table_stack[#nav.item_table_stack]
        local where = depth == 1 and T(_("Library › %1"), nav.title or "")
            or T("… › %1 › %2", prev and prev.title or "", nav.title or "")
        local bw = S(124)
        part(LeftContainer:new{ dimen = Geom:new{ w = inner, h = S(SZ.top) }, HorizontalGroup:new{ align = "center",
            self:key{ w = bw, h = S(SZ.top), label = Touch.keys() and _("Back") or _("‹ Back"), callback = function() self:onClose() end },
            HorizontalSpan:new{ width = S(14) },
            text(where, 17, true, inner - bw - S(14)),
        } })
    elseif touch and items.gz_search then
        -- the search field: a tap asks for the words
        local f = Tap:new{ w = inner, h = S(SZ.top), callback = items.gz_search }
        f[1] = FrameContainer:new{ width = inner, height = S(SZ.top), padding = 0, padding_left = S(14), bordersize = S(2), radius = S(12),
            background = Blitbuffer.COLOR_WHITE,
            LeftContainer:new{ dimen = Geom:new{ w = inner - S(18), h = S(SZ.top) - S(4) },
                text(_("Search artists, albums, tracks…"), 17, false, inner - S(28), Blitbuffer.COLOR_DARK_GRAY) } }
        part(f)
    end
    local after = {}
    if depth == 0 and touch and (items.gz_shuffle or items.gz_account) then
        local row = HorizontalGroup:new{ align = "center" }
        local n = (items.gz_shuffle and 1 or 0) + (items.gz_account and 1 or 0)
        local kw = math.floor((inner - (n - 1) * S(12)) / n)
        if items.gz_shuffle then
            row[#row + 1] = self:key{ w = kw, h = S(SZ.modes), label = _("Shuffle all on Kindle"), callback = items.gz_shuffle }
        end
        if items.gz_account then
            if #row > 0 then row[#row + 1] = HorizontalSpan:new{ width = S(12) } end
            row[#row + 1] = self:key{ w = kw, h = S(SZ.modes), label = items.gz_account.text, font_size = 14, callback = items.gz_account.callback }
        end
        after[#after + 1] = row
    end
    local h = hint(depth > 0 and _("▲ ▼ choose  ·  Press opens  ·  ◀ ▶ pages  ·  Back: up a level")
        or _("▲ ▼ choose  ·  Press opens  ·  ◀ ▶ pages  ·  Back: close (the music keeps playing)"), inner)
    local fixed = S(6)
    for _i, w in ipairs(parts) do fixed = fixed + w:getSize().h + S(14) end
    for _i, w in ipairs(after) do fixed = fixed + w:getSize().h + S(14) end
    if h then fixed = fixed + S(10) + h:getSize().h end
    -- the pages: when they're needed, or inside a list (where you'd look for them)
    local rows = CDScreen.rowsFor(avail - fixed, S(SZ.row), S(4))
    local needs_pager = depth > 0 or #items > rows
    if needs_pager then
        rows = CDScreen.rowsFor(avail - fixed - S(SZ.pager) - S(14), S(SZ.row), S(4))
    end
    self.rows = rows
    -- (a list that fits: the case only as long as it)
    local drawn = needs_pager and rows or math.max(3, #items)
    local sel = math.max(1, math.min(self.sel or 1, #items))
    local first, page, pages = CDScreen.pageOf(sel, rows, #items)
    local dpad = Device:hasDPad()
    local lines = {}
    for i = first, math.min(#items, first + rows - 1) do
        local it = items[i]
        lines[#lines + 1] = { text = it.text or (it.text_func and it.text_func()) or "", right = it.mandatory, bold = it.bold,
            dim = it.select_enabled == false, selected = dpad and i == sel, press = it.callback and _("Press opens") or nil,
            callback = function() self:selectLine(i) end }
    end
    for _i, w in ipairs(parts) do body[#body + 1] = w; body[#body + 1] = VerticalSpan:new{ width = S(14) } end
    body[#body + 1] = self:case(inner, lines, drawn, (nav.title or _("Music")) .. (pages > 1 and ("  ·  " .. page .. "/" .. pages) or ""))
    if needs_pager then
        body[#body + 1] = VerticalSpan:new{ width = S(14) }
        body[#body + 1] = self:pager(inner, pages > 1 and T(_("%1–%2 of %3"), first, math.min(#items, first + rows - 1), #items)
            or T(_("%1 in all"), #items))
    end
    for _i, w in ipairs(after) do body[#body + 1] = VerticalSpan:new{ width = S(14) }; body[#body + 1] = w end
    if h then body[#body + 1] = VerticalSpan:new{ width = S(10) }; body[#body + 1] = h end
    return body
end

function CDScreen:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local margin = S(CDScreen.SIZE.margin)
    local inner = sw - 2 * margin
    local p = self:player()
    if self.mode == "library" then self:ensureLibrary() end
    local top = S(16)
    local group = VerticalGroup:new{ align = "center", self:topRow(inner), VerticalSpan:new{ width = S(14) } }
    local avail = sh - top - group:getSize().h - S(16)
    group:resetLayout()
    local body
    if self.mode == "now" then body = self:nowBody(inner, avail, p)
    elseif self.mode == "queue" then body = self:queueBody(inner, avail, p)
    else body = self:libraryBody(inner, avail, p) end
    group[#group + 1] = body
    self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, padding_top = top,
        padding_left = margin, width = sw, height = sh, group }
    self:schedule()
end

---------------------------------------------------------------- doing

--- The time on the display: every 30 s (each redraw costs battery).
function CDScreen:schedule()
    if self.tick then UIManager:unschedule(self.tick) end
    self.tick = function()
        self.tick = nil
        local p = self:player()
        if p and p.playing and not self.closed then self:build(); UIManager:setDirty(self, "fast") end
    end
    UIManager:scheduleIn(30, self.tick)
end

function CDScreen:refresh()
    if self.closed then return end
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
function CDScreen:onToggle() return act(self, function(p) p:toggle() end) end
function CDScreen:onShuffle() return act(self, function(p) p:setShuffle(not p.shuffle) end) end
function CDScreen:onRepeat() return act(self, function(p) p:cycleRepeat() end) end
function CDScreen:onStop() return act(self, function(p) p:stop() end) end
function CDScreen:onTabNow() return self:setMode("now") end
function CDScreen:onTabQueue() return self:setMode("queue") end
function CDScreen:onTabLibrary() return self:setMode("library") end
--- F (as before the tabs): between the queue and the library.
function CDScreen:onLibrary()
    if self.mode == "library" then return self:setMode(self:player() and "queue" or "library") end
    return self:setMode("library")
end

--- A tap on the progress strip: that point of the track.
function CDScreen:seekToFrac(frac)
    local p = self:player()
    local t = p and p:track()
    local dur = t and tonumber(t.duration) or 0
    if not p or p.waiting or dur <= 0 then return end
    p:seekTo(math.floor(math.max(0, math.min(1, frac)) * dur))
    self:refresh()
end

--- ◀ ▶ on Now playing: 10 s back or ahead. Presses close together are
--- added up and the player started once, where they end (each start costs
--- a Kindle 3 a second or two).
function CDScreen:queueSeek(delta)
    local p = self:player()
    if not p or p.waiting then return true end
    self.seek_target = math.max(0, (self.seek_target or p:position()) + delta)
    if self.seek_apply then UIManager:unschedule(self.seek_apply) end
    self.seek_apply = function()
        self.seek_apply = nil
        local target = self.seek_target
        self.seek_target = nil
        if target and Music().current == p then p:seekTo(target) end
        self:refresh()
    end
    UIManager:scheduleIn(CDScreen.SEEK_GATHER, self.seek_apply)
    -- (the time shown moves at once)
    if not self.closed then
        self:build()
        UIManager:setDirty(self, "fast")
    end
    return true
end

function CDScreen:onPrevKey()
    if self.mode == "now" then return self:queueSeek(-CDScreen.SEEK_MS) end
    return self:pageBy(-1)
end
function CDScreen:onNextKey()
    if self.mode == "now" then return self:queueSeek(CDScreen.SEEK_MS) end
    return self:pageBy(1)
end

--- A page up or down the queue or the library's list.
function CDScreen:pageBy(dir)
    local rows = self.rows or 6
    if self.mode == "queue" then
        local p = self:player()
        if not p then return true end
        local first = CDScreen.pageOf(self.picked or p.at, rows, #p.order)
        self.picked = math.max(1, math.min(#p.order, first + dir * rows))
    elseif self.mode == "library" and self.nav then
        local n = #self.nav.item_table
        local first = CDScreen.pageOf(self.sel or 1, rows, n)
        self.sel = math.max(1, math.min(n, first + dir * rows))
    end
    self:refresh()
    return true
end

--- The volume, − or + (touch Kindles; the others have their volume keys).
function CDScreen:stepVolume(dir)
    local E = Engine()
    E.setVolume(E.volume() + dir)
    self:refreshVolume()
    return true
end
--- After a volume change (here or the volume keys, gzreader_audioctl): a
--- quick redraw, no flash.
function CDScreen:refreshVolume()
    if self.closed then return end
    self:build()
    UIManager:setDirty(self, "fast")
end

function CDScreen:onHome()
    return require("gzreader_tabs").goHome(self)
end
function CDScreen:onUp()
    if self.mode == "library" then
        self.sel = math.max(1, (self.sel or 1) - 1)
    elseif self.mode == "queue" then
        local p = self:player()
        if p then self.picked = math.max(1, (self.picked or p.at) - 1) end
    else
        return true
    end
    self:refresh()
    return true
end
function CDScreen:onDown()
    if self.mode == "library" then
        self.sel = math.min(#self.nav.item_table, (self.sel or 1) + 1)
    elseif self.mode == "queue" then
        local p = self:player()
        if p then self.picked = math.min(#p.order, (self.picked or p.at) + 1) end
    else
        return true
    end
    self:refresh()
    return true
end
function CDScreen:onPlay()
    if self.mode == "library" then
        self:selectLine(self.sel or 1)
        return true
    end
    local p = self:player()
    if self.mode == "queue" and p and self.picked and self.picked ~= p.at then p:jump(self.picked) elseif p then p:toggle() end
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

--- A music download's progress: its line in the library, kept current.
function CDScreen:onGzMusicDownload(st)
    if self.mode == "library" and self.nav and require("gzreader_musictab").updateProgress(self.nav.item_table, st) then
        self:refresh()
    end
end

function CDScreen:onCloseWidget()
    self.closed = true
    Music().listeners[self.listener_key] = nil
    if self.tab then self.tab.closed = true end
    if CDScreen.instance == self then CDScreen.instance = nil end
    if self.tick then UIManager:unschedule(self.tick); self.tick = nil end
    if self.cover_bb then self.cover_bb:free(); self.cover_bb = nil end
end

--- The player: what plays (or the library when nothing does, or with
--- opts.library).
function CDScreen.show(plugin, opts)
    local open = CDScreen.instance
    if open then
        if opts and opts.library then open:setMode("library") else open:showNow() end
        return open
    end
    local w = CDScreen:new{ plugin = plugin, library = opts and opts.library or false }
    UIManager:show(w)
    return w
end

return CDScreen
