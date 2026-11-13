--[[--
The drawing screen (touch Kindles): a page to draw on, saved as a memos
drawing (`gzreader_drawing.lua`): a PNG named `drawing-…canvas.png` with the
strokes inside, which memos opens as a drawing you can go on editing.

  [Cancel] [Thin] [Medium] [Thick] [Eraser] [Undo] [Clear] [Done]
  Draw with the pen. Your hand can rest on the screen.
  ┌──────────────────────────── the page ───────────────────────────┐

- A pen Kindle (the Scribe) draws with the pen only, and ignores the hand
  while the pen is near (palm rejection); the pen's other end rubs out.
  Every other touch Kindle draws with one finger.
- The screen reads the touch screen's contacts itself while it's on top
  (it stands in for KOReader's gesture detector, which gets them back when
  the screen closes or a dialog covers it): `gzreader_sketch.lua` turns them
  into strokes, and new ink is put straight on the screen with the fastest
  black-and-white refresh (A2).
- Eraser rubs out whole strokes, as memos' eraser does. Undo takes back the
  last stroke, rub-out or Clear.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local Drawing = require("gzreader_drawing")
local Log = require("gzreader_log")
local Notepaper = require("gzreader_notepaper")
local Sketch = require("gzreader_sketch")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local DrawScreen = InputContainer:extend{
    name = "gz_drawscreen",
    covers_fullscreen = true,
    -- the note's drawings: { att (in Memos), path (a copy here, edited or new), filename, changed }
    pages = nil,
    start = 1, -- the page shown first
    on_done = nil, -- function(pages): every page, in order, as the note should have them
    on_cancel = nil,
}

--- Where drawings wait until they're in Memos.
function DrawScreen.dir()
    local dir = DataStorage:getSettingsDir() .. "/gzreader-drawings"
    lfs.mkdir(dir)
    return dir
end

--- A new drawing's file: memos' name for it, made unique (two pages in one second).
function DrawScreen.newPath()
    local dir = DrawScreen.dir()
    local name = Drawing.fileName()
    local base = name:sub(1, -#Drawing.SUFFIX - 1)
    local k = 1
    while lfs.attributes(dir .. "/" .. name, "mode") do
        k = k + 1
        name = base .. "-" .. k .. Drawing.SUFFIX
    end
    return dir .. "/" .. name, name
end

--- The paper new pages start on: the last one chosen.
function DrawScreen.lastPaper()
    return G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_paper") or "blank"
end
function DrawScreen.setLastPaper(id)
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_paper", id) end
end

DrawScreen.TOOLS = {
    { id = "cancel", label = _("Cancel") },
    { id = "w1", label = _("Thin"), width = 1 },
    { id = "w2", label = _("Medium"), width = 2 },
    { id = "w4", label = _("Thick"), width = 4 },
    { id = "eraser", label = _("Eraser") },
    { id = "undo", label = _("Undo") },
    { id = "clear", label = _("Clear") },
    { id = "done", label = _("Done") },
}
-- the second row: the page's paper, and the note's pages
DrawScreen.PAGE_TOOLS = {
    { id = "paper", label = _("Paper"), span = 3 },
    { id = "prev", label = "\u{25C0}" },
    { id = "page", label = "", span = 2, passive = true },
    { id = "next", label = "\u{25B6}" },
    { id = "newpage", label = "+ " .. _("New page"), span = 2 },
}

function DrawScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.pen_only = Sketch.penDevice(Device)
    self.button_h, self.hint_h = S(48), S(26)
    self.bar_h = 2 * self.button_h + self.hint_h
    self.canvas = { x = 0, y = self.bar_h, w = sw, h = sh - self.bar_h }
    self.pages = self.pages or {}
    if #self.pages == 0 then self.pages[1] = { new = true } end
    self.index = math.max(1, math.min(self.start or 1, #self.pages))
    local c = self.canvas
    self.canvas_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BB8) -- what's on the screen
    self.ink_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BB8) -- the ink alone (the PNG's ink)
    self.color_bb = nil -- the pictures under the ink, in colour (the PNG's paper), when there are some
    self.discs = {}
    self:layoutBar()
    self:showPage(self.index, true)
end

--- A sketch on the canvas: of `scene` (a drawing to go on with), else a new page on `paper`.
function DrawScreen:newSketch(scene, paper)
    local opts = {
        canvas = self.canvas,
        pen_only = self.pen_only,
        pen_slot = Device.input and Device.input.pen_slot,
        per_unit = Sketch.perUnitFor(Screen:getDPI()),
        tap_slop = S(Sketch.TAP_SLOP),
    }
    if scene then return Sketch.fromScene(scene, opts) end
    local sk = Sketch.new(opts)
    if paper and paper ~= "blank" then sk:setPaper(paper) end
    return sk
end

--- Page `p`'s sketch, read from its file the first time (nil, err when it can't be).
function DrawScreen:sketchOf(p)
    if p.sketch then return p.sketch end
    if p.new then
        p.sketch = self:newSketch(nil, p.paper or DrawScreen.lastPaper())
        return p.sketch
    end
    local file = p.path or (p.att and require("gzreader_memos").filePath(p.att))
    if not file then return nil, "no-file" end
    local scene, err = Drawing.readFile(file)
    if not scene then return nil, err end
    p.sketch = self:newSketch(scene)
    p.opened = true
    return p.sketch
end

--- Shows page `i` (`first`: while opening).
function DrawScreen:showPage(i, first)
    local p = self.pages[i]
    local sk, err = self:sketchOf(p)
    if not sk then
        Log.warn("drawing: page", i, "not opened:", tostring(err))
        p.sketch = self:newSketch(nil, "blank")
        p.broken = true
        sk = p.sketch
    end
    self.index = i
    self.page = p
    self.sketch = sk
    sk.canvas = self.canvas
    sk.pen_only = self.pen_only
    self:repaintCanvas()
    if not first then UIManager:setDirty(self, "ui") end
end

--- This page changed (drawn on, rubbed out, its paper).
function DrawScreen:touched()
    self.page.modified = true
    self.changed = true
end
-- ------------------------------------------------------------------ the bar

function DrawScreen:layoutBar()
    local sw = self.dimen.w
    local gap = S(4)
    self.buttons = {}
    local function row(tools, y)
        local units = 0
        for _i, t in ipairs(tools) do units = units + (t.span or 1) end
        local unit = (sw - gap * (#tools + 1)) / units
        local x = gap
        for _i, t in ipairs(tools) do
            local w = math.floor(unit * (t.span or 1))
            self.buttons[#self.buttons + 1] = { tool = t, rect = Geom:new{ x = math.floor(x), y = y, w = w, h = self.button_h - S(8) } }
            x = x + w + gap
        end
    end
    row(DrawScreen.TOOLS, S(4))
    row(DrawScreen.PAGE_TOOLS, self.button_h + S(4))
end

function DrawScreen:selected(t)
    local sk = self.sketch
    if t.width then return sk.tool == "pen" and sk.width == t.width end
    if t.id == "eraser" then return sk.tool == "eraser" end
    return false
end

function DrawScreen:enabled(t)
    if t.id == "undo" then return self.sketch:canUndo() end
    if t.id == "clear" then return #self.sketch:live() > 0 end
    if t.id == "prev" then return self.index > 1 end
    if t.id == "next" then return self.index < #self.pages end
    return true
end

--- A button's text (the paper's name, the page number).
function DrawScreen:label(t)
    if t.id == "page" then return T(_("Page %1 of %2"), self.index, #self.pages) end
    if t.id == "paper" then
        local id = self.sketch:paper()
        if id == "blank" then return _("Blank paper") .. " \u{25BE}" end
        local p = Notepaper.get(id)
        return (p and p.label or _("Picture")) .. " \u{25BE}"
    end
    return t.label
end

function DrawScreen:hint()
    if self.pen_only then return _("Draw with the pen. Your hand can rest on the screen; the pen's other end rubs out.") end
    return _("Draw with one finger.")
end

function DrawScreen:paintBar(bb, x, y)
    bb:paintRect(x, y, self.dimen.w, self.bar_h, Blitbuffer.COLOR_WHITE)
    for _i, b in ipairs(self.buttons) do
        local t, r = b.tool, b.rect
        local sel, on = self:selected(t), self:enabled(t)
        local fg = sel and Blitbuffer.COLOR_WHITE or (on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY)
        local frame = FrameContainer:new{
            width = r.w, height = r.h, padding = 0, margin = 0, radius = S(6),
            bordersize = t.passive and 0 or ((t.id == "done") and Size.border.thick or Size.border.thin),
            background = sel and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = r.w - 4, h = r.h - 4 },
                TextWidget:new{ text = self:label(t), face = Font:getFace("cfont", 16), bold = sel or t.id == "done",
                    fgcolor = fg, max_width = r.w - S(6) } },
        }
        frame:paintTo(bb, x + r.x, y + r.y)
        frame:free()
    end
    local hint = TextWidget:new{ text = self:hint(), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = self.dimen.w - S(16) }
    local hw = hint:getSize().w
    hint:paintTo(bb, x + math.floor((self.dimen.w - hw) / 2), y + 2 * self.button_h + S(2))
    hint:free()
    bb:paintRect(x, y + self.bar_h - Size.line.medium, self.dimen.w, Size.line.medium, Blitbuffer.COLOR_DARK_GRAY)
end

function DrawScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = self.canvas
    bb:blitFrom(self.canvas_bb, x + c.x, y + c.y, 0, 0, c.w, c.h)
    self:paintBar(bb, x, y)
end

-- ---------------------------------------------------------------- the ink

function DrawScreen:disc(r)
    if not self.discs[r] then self.discs[r] = Sketch.disc(r) end
    return self.discs[r]
end

--- Ink for one segment (screen coordinates) into the page, and into `screen_bb` too when given.
function DrawScreen:ink(seg, screen_bb)
    local c = self.sketch.canvas
    local r = seg[5]
    local rows = self:disc(r)
    for _i, p in ipairs(Sketch.stamps(seg[1], seg[2], seg[3], seg[4], r)) do
        for dy = -r, r do
            local dx = rows[dy]
            self.canvas_bb:paintRect(p[1] - dx - c.x, p[2] + dy - c.y, 2 * dx + 1, 1, Blitbuffer.COLOR_BLACK)
            self.ink_bb:paintRect(p[1] - dx - c.x, p[2] + dy - c.y, 2 * dx + 1, 1, Blitbuffer.COLOR_BLACK)
            if screen_bb then screen_bb:paintRect(p[1] - dx, p[2] + dy, 2 * dx + 1, 1, Blitbuffer.COLOR_BLACK) end
        end
    end
end

local function strokeSegments(sk, st)
    local c, r, out = sk.canvas, sk:radius(st.width), {}
    local pts = st.points
    for i = 1, #pts do
        local a, b = pts[math.max(1, i - 1)], pts[i]
        out[#out + 1] = { a[1] + c.x, a[2] + c.y, b[1] + c.x, b[2] + c.y, r }
    end
    return out
end

--- Picture `el` of the page's scene, at w x h (cached for the page): a
--- BlitBuffer, or nil when it can't be read.
function DrawScreen:picture(el, w, h)
    local p = self.page
    p.pictures = p.pictures or {}
    local key = tostring(el.fileId) .. ":" .. w .. "x" .. h
    if p.pictures[key] ~= nil then return p.pictures[key] or nil end
    local base = self.sketch.base
    local f = base and type(base.files) == "table" and base.files[el.fileId]
    local url = type(f) == "table" and f.dataURL
    local b64 = type(url) == "string" and url:match("^data:image/[%w.+-]+;base64,(.+)$")
    local bb
    if b64 then
        local ok, data = pcall(require("ffi/sha2").base64_to_bin, b64)
        if ok and data then
            local okr, img = pcall(function()
                return require("ui/renderimage"):renderImageData(data, #data, false, w, h)
            end)
            if okr and img then
                if img:getWidth() ~= w or img:getHeight() ~= h then
                    img = require("ui/renderimage"):scaleBlitBuffer(img, w, h, true)
                end
                bb = img
            end
        end
    end
    if not bb then Log.warn("drawing: a picture in the drawing couldn't be shown") end
    p.pictures[key] = bb or false
    return bb
end

--- A picture of the page (its paper, a picture added in Memos) under the
--- ink: grey on the screen, in colour in the PNG.
function DrawScreen:paintPicture(el)
    local sk = self.sketch
    local c = self.canvas
    local x1, y1 = sk:toCanvas(tonumber(el.x) or 0, tonumber(el.y) or 0)
    local x2, y2 = sk:toCanvas((tonumber(el.x) or 0) + (tonumber(el.width) or 0), (tonumber(el.y) or 0) + (tonumber(el.height) or 0))
    x1, y1, x2, y2 = math.floor(x1 + 0.5), math.floor(y1 + 0.5), math.floor(x2 + 0.5), math.floor(y2 + 0.5)
    local w, h = x2 - x1, y2 - y1
    if w < 2 or h < 2 then return false end
    local bb = self:picture(el, w, h)
    if not bb then return false end
    -- (only what's on the canvas)
    local sx, sy = math.max(0, -x1), math.max(0, -y1)
    local dx, dy = math.max(0, x1), math.max(0, y1)
    local bw, bh = math.min(w - sx, c.w - dx), math.min(h - sy, c.h - dy)
    if bw <= 0 or bh <= 0 then return true end
    self.canvas_bb:blitFrom(bb, dx, dy, sx, sy, bw, bh)
    if not self.color_bb then
        self.color_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BBRGB24)
        self.color_bb:fill(Blitbuffer.ColorRGB24(DrawScreen.hexRGB(Drawing.PAPER)))
    end
    self.color_bb:blitFrom(bb, dx, dy, sx, sy, bw, bh)
    return true
end

--- An opened drawing's shapes and text (made in memos), drawn simply: kept
--- as they are, not changed here. Pictures go under them.
function DrawScreen:paintLocked(list)
    local sk = self.sketch
    local c = sk.canvas
    local function seg(ax, ay, bx, by, r)
        local x1, y1 = sk:toCanvas(ax, ay)
        local x2, y2 = sk:toCanvas(bx, by)
        self:ink({ x1 + c.x, y1 + c.y, x2 + c.x, y2 + c.y, r })
    end
    for _i, el in ipairs(list or sk.locked) do
        local x, y = tonumber(el.x) or 0, tonumber(el.y) or 0
        local w, h = tonumber(el.width) or 0, tonumber(el.height) or 0
        local r = math.max(1, math.floor(Sketch.radiusFor(tonumber(el.strokeWidth) or 2, sk.per_unit) / 2 + 0.5))
        if el.type == "image" and self:paintPicture(el) then -- luacheck: ignore 542
            -- (drawn: its pixels)
        elseif el.type == "rectangle" or el.type == "image" then
            seg(x, y, x + w, y, r); seg(x + w, y, x + w, y + h, r); seg(x + w, y + h, x, y + h, r); seg(x, y + h, x, y, r)
        elseif el.type == "diamond" then
            seg(x + w / 2, y, x + w, y + h / 2, r); seg(x + w, y + h / 2, x + w / 2, y + h, r)
            seg(x + w / 2, y + h, x, y + h / 2, r); seg(x, y + h / 2, x + w / 2, y, r)
        elseif el.type == "ellipse" then
            local n, px, py = 48, nil, nil
            for k = 0, n do
                local a = 2 * math.pi * k / n
                local qx, qy = x + w / 2 + w / 2 * math.cos(a), y + h / 2 + h / 2 * math.sin(a)
                if px then seg(px, py, qx, qy, r) end
                px, py = qx, qy
            end
        elseif (el.type == "line" or el.type == "arrow") and type(el.points) == "table" then
            local pts = el.points
            for k = 2, #pts do seg(x + pts[k - 1][1], y + pts[k - 1][2], x + pts[k][1], y + pts[k][2], r) end
            if el.type == "arrow" and #pts >= 2 then
                local a, b = pts[#pts - 1], pts[#pts]
                local ang = math.atan2(b[2] - a[2], b[1] - a[1])
                local len = 4 * (tonumber(el.strokeWidth) or 2) + 6
                for _j, d in ipairs({ 2.6, -2.6 }) do
                    seg(x + b[1], y + b[2], x + b[1] + len * math.cos(ang + d), y + b[2] + len * math.sin(ang + d), r)
                end
            end
        elseif el.type == "text" and type(el.text) == "string" and el.text ~= "" then
            local cx, cy = sk:toCanvas(x, y)
            local px = math.max(6, math.floor((tonumber(el.fontSize) or 20) * sk.per_unit))
            local one = Screen:scaleBySize(100) / 100
            local tw = TextWidget:new{ text = el.text:gsub("\n", " "), face = Font:getFace("cfont", math.max(6, math.floor(px / one))),
                fgcolor = Blitbuffer.COLOR_BLACK }
            tw:paintTo(self.canvas_bb, math.floor(cx), math.floor(cy))
            tw:paintTo(self.ink_bb, math.floor(cx), math.floor(cy))
            tw:free()
        end
    end
end

--- The page drawn again from the strokes (after an undo, a rub-out, Clear).
function DrawScreen:repaintCanvas()
    self.canvas_bb:fill(Blitbuffer.COLOR_WHITE)
    self.ink_bb:fill(Blitbuffer.COLOR_WHITE)
    if self.color_bb then self.color_bb:free(); self.color_bb = nil end
    -- pictures first (the paper at the bottom), then shapes and text, then the strokes
    local pictures, others = {}, {}
    for _i, el in ipairs(self.sketch.locked) do
        if el.type == "image" then pictures[#pictures + 1] = el else others[#others + 1] = el end
    end
    self:paintLocked(pictures)
    self:paintLocked(others)
    local list = self.sketch:live()
    local cur = self.sketch:current()
    if cur then list[#list + 1] = cur end
    for _i, st in ipairs(list) do
        for _j, seg in ipairs(strokeSegments(self.sketch, st)) do self:ink(seg) end
    end
end

function DrawScreen:redrawAll()
    self:repaintCanvas()
    UIManager:setDirty(self, "ui")
end

-- --------------------------------------------------------------- the input

--- Takes the touch screen's contacts while this screen is on top.
function DrawScreen:hook()
    local input = Device.input
    local gd = input and input.gesture_detector
    if not gd or self._gd then return end
    self._gd = gd
    self._own_feed = rawget(gd, "feedEvent")
    local orig = gd.feedEvent
    local screen = self
    rawset(gd, "feedEvent", function(det, tevs)
        if screen._closed or UIManager:getTopmostVisibleWidget() ~= screen then return orig(det, tevs) end
        local ok, err = pcall(screen.onContacts, screen, det, tevs)
        if not ok then Log.warn("drawing: input:", tostring(err)) end
        return {}
    end)
    -- (a tap still under way, e.g. the one that opened this screen, is forgotten)
    pcall(gd.dropContacts, gd)
    if input.clearTimeouts then pcall(input.clearTimeouts, input) end
end

function DrawScreen:unhook()
    local gd = self._gd
    if not gd then return end
    rawset(gd, "feedEvent", self._own_feed)
    self._gd = nil
    pcall(gd.dropContacts, gd)
    local input = Device.input
    if input and input.clearTimeouts then pcall(input.clearTimeouts, input) end
end

--- One input frame from KOReader: contacts in screen coordinates, to the sketch.
function DrawScreen:onContacts(det, tevs)
    local time = require("ui/time")
    local slots, now = {}, nil
    for _i, tev in ipairs(tevs) do
        local x, y = tev.x, tev.y
        if x and y then
            local ges = { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
            if det.adjustGesCoordinate then pcall(det.adjustGesCoordinate, det, ges) end
            x, y = ges.pos.x, ges.pos.y
        end
        slots[#slots + 1] = { slot = tev.slot, id = tev.id, x = x, y = y, tool = tev.tool }
        if tev.timev and not now then now = time.to_s(tev.timev) end
    end
    now = now or time.to_s(time.now())
    local out = self.sketch:frame(slots, now)
    self:apply(out)
end

function DrawScreen:apply(out)
    if out.redraw then
        self:touched()
        self:redrawAll()
    elseif #out.segments > 0 then
        self:touched()
        local screen_bb = Screen.bb
        local x0, y0, x1, y1
        for _i, seg in ipairs(out.segments) do
            self:ink(seg, screen_bb)
            local r = seg[5]
            x0 = math.min(x0 or math.huge, seg[1] - r, seg[3] - r)
            y0 = math.min(y0 or math.huge, seg[2] - r, seg[4] - r)
            x1 = math.max(x1 or -math.huge, seg[1] + r, seg[3] + r)
            y1 = math.max(y1 or -math.huge, seg[2] + r, seg[4] + r)
        end
        local c = self.canvas
        x0, y0 = math.max(c.x, math.floor(x0) - 1), math.max(c.y, math.floor(y0) - 1)
        x1, y1 = math.min(c.x + c.w, math.ceil(x1) + 1), math.min(c.y + c.h, math.ceil(y1) + 1)
        if x1 > x0 and y1 > y0 then
            -- (the ink is on the screen already: only a refresh, no repaint)
            UIManager:setDirty(nil, "a2", Geom:new{ x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
        end
    end
    if out.stroke_done and #self.sketch.history == 1 then
        -- Undo and Clear wake up after the first stroke
        self:refreshBar()
    end
    for _i, tap in ipairs(out.taps) do self:tapAt(tap.x, tap.y) end
end

function DrawScreen:tapAt(x, y)
    for _i, b in ipairs(self.buttons) do
        local r = b.rect
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return self:use(b.tool) end
    end
end

function DrawScreen:refreshBar()
    UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.bar_h })
end

function DrawScreen:use(t)
    local sk = self.sketch
    if t.width then sk:setWidth(t.width); self:refreshBar()
    elseif t.id == "eraser" then sk:setTool(sk.tool == "eraser" and "pen" or "eraser"); self:refreshBar()
    elseif t.id == "undo" then if sk:undo() then self:touched(); self:redrawAll() end
    elseif t.id == "clear" then if sk:clear() then self:touched(); self:redrawAll() end
    elseif t.id == "cancel" then self:cancel()
    elseif t.id == "done" then self:done()
    elseif t.id == "paper" then self:pickPaper()
    elseif t.id == "prev" then if self.index > 1 then self:showPage(self.index - 1) end
    elseif t.id == "next" then if self.index < #self.pages then self:showPage(self.index + 1) end
    elseif t.id == "newpage" then self:newPage() end
end

--- + New page: another drawing for the note, on the last paper chosen.
function DrawScreen:newPage()
    self.pages[#self.pages + 1] = { new = true, paper = DrawScreen.lastPaper(), modified = true }
    self.changed = true
    self:showPage(#self.pages)
    Log.info("drawing: a new page,", #self.pages, "now")
end

--- Paper: the page's background (and the one new pages start on).
function DrawScreen:pickPaper()
    local dialog
    local rows = {}
    local cur = self.sketch:paper()
    for _i, p in ipairs(Notepaper.LIST) do
        rows[#rows + 1] = { { text = p.label .. (p.id == cur and "  \u{2713}" or ""), align = "left", callback = function()
            UIManager:close(dialog)
            DrawScreen.setLastPaper(p.id)
            if p.id ~= cur then self:setPaper(p.id) end
        end } }
    end
    dialog = ButtonDialog:new{ title = _("Paper"), buttons = rows }
    UIManager:show(dialog)
    return dialog
end

function DrawScreen:setPaper(id)
    self.sketch:setPaper(id)
    self:touched()
    Log.info("drawing: paper", id)
    self:redrawAll()
end

-- ---------------------------------------------------------------- closing

function DrawScreen:onShow()
    self:hook()
    UIManager:setDirty(self, "full")
end

function DrawScreen:onCloseWidget()
    self._closed = true
    self:unhook()
    for _i, bb in ipairs({ "canvas_bb", "ink_bb", "color_bb" }) do
        if self[bb] then self[bb]:free(); self[bb] = nil end
    end
    for _i, p in ipairs(self.pages or {}) do
        for _k, bb in pairs(p.pictures or {}) do if bb then bb:free() end end
        p.pictures = nil
    end
    local sk = self.sketch
    if sk then
        Log.info("drawing: closed;", #self.pages, "pages;", #sk:live(), "strokes on the last;", sk.stats.palm,
            "palm contacts and", sk.stats.ignored, "other contacts ignored")
    end
end

function DrawScreen:close()
    UIManager:close(self, "full")
end

function DrawScreen:cancel()
    if not self.changed then
        self:close()
        if self.on_cancel then self.on_cancel() end
        return
    end
    local dialog
    dialog = ButtonDialog:new{ title = _("Leave without keeping these changes?"), buttons = {
        { { text = _("Discard changes"), align = "left", callback = function()
            UIManager:close(dialog); self:close()
            if self.on_cancel then self.on_cancel() end
        end } },
        { { text = _("Keep drawing"), align = "left", callback = function() UIManager:close(dialog) end } },
    } }
    UIManager:show(dialog)
end

--- `#rrggbb` as r, g, b.
function DrawScreen.hexRGB(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- The PNG's pixels: the cropped page (canvas pixels `crop`), 8-bit RGB rows:
--- the ink (`ink_bb`, grey 0 ink … 255 none) in memos' ink colour over the
--- pictures (`color_bb`, in colour) or memos' paper. Returns a uint8_t array
--- and its size.
function DrawScreen.pixels(ink_bb, crop, color_bb)
    local pr, pg, pb = DrawScreen.hexRGB(Drawing.PAPER)
    local ir, ig, ib = DrawScreen.hexRGB(Drawing.INK)
    local w, h = crop.w, crop.h
    local mem = ffi.new("uint8_t[?]", w * h * 3)
    -- (an 8-bit page, not rotated: its rows straight from memory)
    local data = ink_bb.data and ffi.cast("uint8_t *", ink_bb.data)
    local stride = tonumber(ink_bb.stride)
    local i = 0
    if not color_bb then
        local lr, lg, lb = ffi.new("uint8_t[256]"), ffi.new("uint8_t[256]"), ffi.new("uint8_t[256]")
        for g = 0, 255 do
            local f = g / 255
            lr[g] = math.floor(ir + (pr - ir) * f + 0.5)
            lg[g] = math.floor(ig + (pg - ig) * f + 0.5)
            lb[g] = math.floor(ib + (pb - ib) * f + 0.5)
        end
        for y = crop.y, crop.y + h - 1 do
            local row = data and (y * stride)
            for x = crop.x, crop.x + w - 1 do
                local g = data and data[row + x] or ink_bb:getPixel(x, y):getColor8().a
                mem[i], mem[i + 1], mem[i + 2] = lr[g], lg[g], lb[g]
                i = i + 3
            end
        end
        return mem, w * h * 3
    end
    local cdata = color_bb.data and ffi.cast("uint8_t *", color_bb.data)
    local cstride = tonumber(color_bb.stride)
    for y = crop.y, crop.y + h - 1 do
        local row = data and (y * stride)
        local crow = cdata and (y * cstride)
        for x = crop.x, crop.x + w - 1 do
            local g = data and data[row + x] or ink_bb:getPixel(x, y):getColor8().a
            local r, gg, b
            if cdata then
                local o = crow + x * 3
                r, gg, b = cdata[o], cdata[o + 1], cdata[o + 2]
            else
                local c = color_bb:getPixel(x, y)
                r, gg, b = c.r or pr, c.g or pg, c.b or pb
            end
            local f = g / 255
            mem[i] = math.floor(ir + (r - ir) * f + 0.5)
            mem[i + 1] = math.floor(ig + (gg - ig) * f + 0.5)
            mem[i + 2] = math.floor(ib + (b - ib) * f + 0.5)
            i = i + 3
        end
    end
    return mem, w * h * 3
end

--- Saves the page shown: the PNG of the page (cropped, memos' colours) with
--- the scene inside. Returns { path, filename } or nil, err.
function DrawScreen:save()
    local sk, p = self.sketch, self.page
    local crop = sk:cropRect()
    if not crop then return nil, "empty" end
    local path, filename = p.path, p.path and p.path:match("[^/]+$")
    if not path then
        if p.att and p.att.filename then
            filename = p.att.filename
            path = DrawScreen.dir() .. "/" .. filename
        else
            path, filename = DrawScreen.newPath()
        end
    end
    local tmp = path .. ".pixels.png"
    local mem = DrawScreen.pixels(self.ink_bb, crop, self.color_bb)
    local Png = require("ffi/png")
    local ok, err = Png.encodeToFile(tmp, mem, crop.w, crop.h, 3)
    if ok == false then os.remove(tmp); return nil, err or "png" end
    local wrote, why = Drawing.writeFile(tmp, sk:scene(), path)
    os.remove(tmp)
    if not wrote then return nil, why end
    Log.info("drawing: saved,", #sk:live(), "strokes, paper", sk:paper(), crop.w .. "x" .. crop.h, lfs.attributes(path, "size") or 0, "bytes")
    return { path = path, filename = filename }
end

--- Done: every page as the note should have it, in order:
--- { att, path, filename, changed, removed } (a page left as it was: no path
--- of its own unless it had one; emptied: removed, when it's in Memos).
function DrawScreen:done()
    local results = {}
    for i, p in ipairs(self.pages) do
        if not p.modified then
            -- left as it was (this time): as it came
            if p.att or p.path then
                results[#results + 1] = { att = p.att, path = p.path, filename = p.filename, changed = p.changed, removed = p.removed }
            end
        else
            if self.index ~= i then self:showPage(i, true) end
            if self.sketch:isEmpty() then
                if p.path and not p.att then os.remove(p.path) end
                if p.att then results[#results + 1] = { att = p.att, removed = true, changed = true } end
            else
                local res, err = self:save()
                if not res then
                    Log.warn("drawing: couldn't save page", i, tostring(err))
                    UIManager:show(require("ui/widget/infomessage"):new{ text = _("Couldn't save the drawing."), timeout = 3 })
                    return
                end
                results[#results + 1] = { att = p.att, path = res.path, filename = res.filename, changed = true }
            end
        end
    end
    self:close()
    if self.on_done then self.on_done(results) end
end

--- opts: pages ({ att, path, filename, changed, removed }: the note's
--- drawings; none: a new page), start (the page shown first),
--- on_done(pages), on_cancel.
function DrawScreen.show(opts)
    local pages = {}
    for _i, p in ipairs(opts.pages or {}) do
        if not p.removed then
            pages[#pages + 1] = { att = p.att, path = p.path, filename = p.filename, changed = p.changed }
        end
    end
    -- (pages taken off earlier stay off: given back as they were)
    local gone = {}
    for _i, p in ipairs(opts.pages or {}) do if p.removed then gone[#gone + 1] = p end end
    local on_done = opts.on_done
    local w = DrawScreen:new{ pages = pages, start = opts.start, on_cancel = opts.on_cancel,
        on_done = on_done and function(res)
            for _i, p in ipairs(gone) do res[#res + 1] = p end
            on_done(res)
        end }
    UIManager:show(w, "full")
    return w
end

return DrawScreen
