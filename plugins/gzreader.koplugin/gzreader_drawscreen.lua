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
local Sketch = require("gzreader_sketch")
local _ = require("gettext")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local DrawScreen = InputContainer:extend{
    name = "gz_drawscreen",
    covers_fullscreen = true,
    sketch = nil, -- a Sketch to go on with (reopening a drawing)
    scene = nil, -- a memos scene to go on with (a drawing already in Memos)
    path = nil, -- where the drawing is kept (reopening: the same file)
    on_done = nil, -- function({ path, filename, sketch }) or nil when nothing is drawn
    on_cancel = nil,
}

--- Where drawings wait until they're in Memos.
function DrawScreen.dir()
    local dir = DataStorage:getSettingsDir() .. "/gzreader-drawings"
    lfs.mkdir(dir)
    return dir
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

function DrawScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.pen_only = Sketch.penDevice(Device)
    self.button_h, self.hint_h = S(48), S(26)
    self.bar_h = self.button_h + self.hint_h
    local canvas = { x = 0, y = self.bar_h, w = sw, h = sh - self.bar_h }
    if not self.sketch and self.scene then
        self.sketch = Sketch.fromScene(self.scene, {
            canvas = canvas,
            pen_only = self.pen_only,
            pen_slot = Device.input and Device.input.pen_slot,
            per_unit = Sketch.perUnitFor(Screen:getDPI()),
            tap_slop = S(Sketch.TAP_SLOP),
        })
    elseif not self.sketch then
        self.sketch = Sketch.new{
            canvas = canvas,
            pen_only = self.pen_only,
            pen_slot = Device.input and Device.input.pen_slot,
            per_unit = Sketch.perUnitFor(Screen:getDPI()),
            tap_slop = S(Sketch.TAP_SLOP),
        }
    else
        self.sketch.canvas = canvas
        self.sketch.pen_only = self.pen_only
    end
    self.canvas_bb = Blitbuffer.new(canvas.w, canvas.h, Blitbuffer.TYPE_BB8)
    self.discs = {}
    self.changed = false
    self:layoutBar()
    self:repaintCanvas()
end

-- ------------------------------------------------------------------ the bar

function DrawScreen:layoutBar()
    local sw = self.dimen.w
    local n = #DrawScreen.TOOLS
    local gap = S(4)
    local w = math.floor((sw - gap * (n + 1)) / n)
    self.buttons = {}
    for i, t in ipairs(DrawScreen.TOOLS) do
        self.buttons[i] = { tool = t, rect = Geom:new{ x = gap + (i - 1) * (w + gap), y = S(4), w = w, h = self.button_h - S(8) } }
    end
end

function DrawScreen:selected(t)
    local sk = self.sketch
    if t.width then return sk.tool == "pen" and sk.width == t.width end
    if t.id == "eraser" then return sk.tool == "eraser" end
    return false
end

function DrawScreen:enabled(t)
    if t.id == "undo" then return self.sketch:canUndo() end
    if t.id == "clear" then return not self.sketch:isEmpty() end
    return true
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
            bordersize = (t.id == "done") and Size.border.thick or Size.border.thin,
            background = sel and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = r.w - 4, h = r.h - 4 },
                TextWidget:new{ text = t.label, face = Font:getFace("cfont", 16), bold = sel or t.id == "done",
                    fgcolor = fg, max_width = r.w - S(6) } },
        }
        frame:paintTo(bb, x + r.x, y + r.y)
        frame:free()
    end
    local hint = TextWidget:new{ text = self:hint(), face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = self.dimen.w - S(16) }
    local hw = hint:getSize().w
    hint:paintTo(bb, x + math.floor((self.dimen.w - hw) / 2), y + self.button_h + S(2))
    hint:free()
    bb:paintRect(x, y + self.bar_h - Size.line.medium, self.dimen.w, Size.line.medium, Blitbuffer.COLOR_DARK_GRAY)
end

function DrawScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = self.sketch.canvas
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

--- An opened drawing's shapes and text (made in memos), drawn simply: kept
--- as they are, not changed here.
function DrawScreen:paintLocked()
    local sk = self.sketch
    local c = sk.canvas
    local function seg(ax, ay, bx, by, r)
        local x1, y1 = sk:toCanvas(ax, ay)
        local x2, y2 = sk:toCanvas(bx, by)
        self:ink({ x1 + c.x, y1 + c.y, x2 + c.x, y2 + c.y, r })
    end
    for _i, el in ipairs(sk.locked) do
        local x, y = tonumber(el.x) or 0, tonumber(el.y) or 0
        local w, h = tonumber(el.width) or 0, tonumber(el.height) or 0
        local r = math.max(1, math.floor(Sketch.radiusFor(tonumber(el.strokeWidth) or 2, sk.per_unit) / 2 + 0.5))
        if el.type == "rectangle" or el.type == "image" then
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
            tw:free()
        end
    end
end

--- The page drawn again from the strokes (after an undo, a rub-out, Clear).
function DrawScreen:repaintCanvas()
    self.canvas_bb:fill(Blitbuffer.COLOR_WHITE)
    self:paintLocked()
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
        self.changed = true
        self:redrawAll()
    elseif #out.segments > 0 then
        self.changed = true
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
        local c = self.sketch.canvas
        x0, y0 = math.max(c.x, math.floor(x0) - 1), math.max(c.y, math.floor(y0) - 1)
        x1, y1 = math.min(c.x + c.w, math.ceil(x1) + 1), math.min(c.y + c.h, math.ceil(y1) + 1)
        if x1 > x0 and y1 > y0 then
            -- (the ink is on the screen already: only a refresh, no repaint)
            UIManager:setDirty(nil, "a2", Geom:new{ x = x0, y = y0, w = x1 - x0, h = y1 - y0 })
        end
    end
    if out.stroke_done and #self.sketch.history == 1 then
        -- Undo and Clear wake up after the first stroke
        UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.bar_h })
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
    elseif t.id == "undo" then if sk:undo() then self.changed = true; self:redrawAll() end
    elseif t.id == "clear" then if sk:clear() then self.changed = true; self:redrawAll() end
    elseif t.id == "cancel" then self:cancel()
    elseif t.id == "done" then self:done() end
end

-- ---------------------------------------------------------------- closing

function DrawScreen:onShow()
    self:hook()
    UIManager:setDirty(self, "full")
end

function DrawScreen:onCloseWidget()
    self._closed = true
    self:unhook()
    if self.canvas_bb then self.canvas_bb:free(); self.canvas_bb = nil end
    Log.info("drawing: closed;", #self.sketch:live(), "strokes;", self.sketch.stats.palm, "palm contacts and",
        self.sketch.stats.ignored, "other contacts ignored")
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

--- Grey `g` on the page (0 ink … 255 paper) as memos' ink on memos' paper.
local function hexRGB(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- The PNG's pixels: the cropped page (canvas pixels `crop`) in memos' colours,
--- 8-bit RGB rows. Returns a uint8_t array and its size.
function DrawScreen.pixels(canvas_bb, crop)
    local pr, pg, pb = hexRGB(Drawing.PAPER)
    local ir, ig, ib = hexRGB(Drawing.INK)
    local w, h = crop.w, crop.h
    local mem = ffi.new("uint8_t[?]", w * h * 3)
    local lr, lg, lb = ffi.new("uint8_t[256]"), ffi.new("uint8_t[256]"), ffi.new("uint8_t[256]")
    for g = 0, 255 do
        local f = g / 255
        lr[g] = math.floor(ir + (pr - ir) * f + 0.5)
        lg[g] = math.floor(ig + (pg - ig) * f + 0.5)
        lb[g] = math.floor(ib + (pb - ib) * f + 0.5)
    end
    -- (an 8-bit page, not rotated: its rows straight from memory)
    local data = canvas_bb.data and ffi.cast("uint8_t *", canvas_bb.data)
    local stride = tonumber(canvas_bb.stride)
    local i = 0
    for y = crop.y, crop.y + h - 1 do
        local row = data and (y * stride)
        for x = crop.x, crop.x + w - 1 do
            local g = data and data[row + x] or canvas_bb:getPixel(x, y):getColor8().a
            mem[i], mem[i + 1], mem[i + 2] = lr[g], lg[g], lb[g]
            i = i + 3
        end
    end
    return mem, w * h * 3
end

--- Saves the drawing: the PNG of the strokes (cropped, memos' colours) with
--- the scene inside. Returns { path, filename } or nil, err.
function DrawScreen:save()
    local sk = self.sketch
    local crop = sk:cropRect()
    if not crop then return nil, "empty" end
    local filename = self.path and self.path:match("[^/]+$") or Drawing.fileName()
    local path = self.path or (DrawScreen.dir() .. "/" .. filename)
    local tmp = path .. ".pixels.png"
    local mem = DrawScreen.pixels(self.canvas_bb, crop)
    local Png = require("ffi/png")
    local ok, err = Png.encodeToFile(tmp, mem, crop.w, crop.h, 3)
    if ok == false then os.remove(tmp); return nil, err or "png" end
    local wrote, why = Drawing.writeFile(tmp, sk:scene(), path)
    os.remove(tmp)
    if not wrote then return nil, why end
    Log.info("drawing: saved,", #sk:live(), "strokes,", crop.w .. "x" .. crop.h, lfs.attributes(path, "size") or 0, "bytes")
    return { path = path, filename = filename }
end

function DrawScreen:done()
    if self.scene and not self.changed then -- (a drawing opened and left as it was: nothing to send)
        self:close()
        if self.on_cancel then self.on_cancel() end
        return
    end
    if self.sketch:isEmpty() then
        self:close()
        if self.path then os.remove(self.path) end
        if self.on_done then self.on_done(nil) end
        return
    end
    local res, err = self:save()
    if not res then
        Log.warn("drawing: couldn't save:", tostring(err))
        UIManager:show(require("ui/widget/infomessage"):new{ text = _("Couldn't save the drawing."), timeout = 3 })
        return
    end
    res.sketch = self.sketch
    self:close()
    if self.on_done then self.on_done(res) end
end

--- opts: sketch and path (to go on with a drawing drawn here), or scene (a
--- drawing from Memos to go on with), on_done(result or nil), on_cancel.
function DrawScreen.show(opts)
    local w = DrawScreen:new{ sketch = opts.sketch, scene = opts.scene, path = opts.path, on_done = opts.on_done,
        on_cancel = opts.on_cancel }
    UIManager:show(w, "full")
    return w
end

return DrawScreen
