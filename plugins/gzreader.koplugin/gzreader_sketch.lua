--[[--
What the drawing screen draws, from the touch screen's raw contacts: no UI,
so it's tested on its own (`sketch_test.lua`).

Two ways of drawing, by the Kindle:
  * **a pen** (the Kindle Scribe: KOReader's wacom protocol, the pen in its
    own slot): only the pen draws. Fingers never draw, and while the pen is
    near the screen (hovering or touching) and for a moment after it leaves,
    every finger contact is ignored: a hand resting on the screen while you
    draw does nothing (palm rejection). With the pen away, a finger can still
    tap the toolbar.
  * **a finger** (every other touch Kindle): one finger draws; a second
    contact while drawing is ignored.

`Sketch:frame(slots, now)` takes one input frame (KOReader's MTSlots: `slot`,
`id` (-1 when lifted or hovering), `x`, `y`, `tool` 0 finger / 1 pen /
2 eraser) and says what to paint: new stroke `segments`, `redraw` (an undo
or an erase), and `taps` outside the canvas (the toolbar's business).
Coordinates are screen pixels; strokes are kept relative to the canvas.
]]

local Drawing = require("gzreader_drawing")

local Sketch = {
    TOOL_FINGER = 0,
    TOOL_PEN = 1,
    TOOL_ERASER = 2,
    --- Seconds finger contacts stay ignored after the pen leaves the screen.
    PEN_GRACE = 0.6,
    --- Seconds without a word from the pen after which it counts as gone
    --- (in case its leaving was missed).
    PEN_TIMEOUT = 5,
    --- Screen pixels a tap may move (scaled by the caller).
    TAP_SLOP = 24,
    --- Points closer than this (screen pixels) to the last one aren't kept.
    MIN_STEP = 1,
    --- Padding around the drawing in the PNG, in scene units (memos' export).
    PADDING = 24,
}
Sketch.__index = Sketch

--- opts: `canvas` { x, y, w, h } (screen pixels), `pen_only` (a pen Kindle),
--- `pen_slot` (KOReader's `input.pen_slot`), `per_unit` (screen pixels per
--- scene unit), `tap_slop`, `width` (1, 2 or 4: memos' pen widths).
function Sketch.new(opts)
    local self = setmetatable({}, Sketch)
    self.canvas = opts.canvas
    self.pen_only = opts.pen_only == true
    self.pen_slot = opts.pen_slot
    self.per_unit = opts.per_unit or Drawing.SCREEN_PER_UNIT
    self.max_per_unit = self.per_unit -- (an opened drawing is shrunk to fit, never enlarged past this)
    -- the scene point at the canvas's top left (an opened drawing is moved and scaled to fit)
    self.ox, self.oy = 0, 0
    self.locked = {} -- an opened drawing's shapes and text: kept as they are, shown, not changed here
    self.tap_slop = opts.tap_slop or Sketch.TAP_SLOP
    self.width = opts.width or 2
    self.tool = "pen" -- or "eraser"
    self.strokes = {} -- { points = { {x, y}, … } (canvas px), width, gone }
    self.history = {} -- { kind = "add"|"erase"|"clear", strokes = { … } }
    self.contacts = {} -- slot → { kind = "draw"|"erase"|"tap"|"ignore", … }
    self.pen = { near = false, last = nil, left = nil }
    self.stats = { ignored = 0, palm = 0 }
    return self
end

--- The pen Kindles: KOReader reads their pen with its wacom protocol.
function Sketch.penDevice(device)
    local input = device and device.input
    if input and input.wacom_protocol then return true end
    local model = device and device.model
    return type(model) == "string" and model:match("Scribe") ~= nil
end

--- Screen pixels per scene unit for a screen of `dpi`: 2 at 300 dpi (memos
--- exports at 2x, so a drawing comes back at the screen's size), never under 1.
function Sketch.perUnitFor(dpi)
    return math.max(1, (tonumber(dpi) or 300) / 150)
end

--- The radius (screen pixels) a stroke of memos width `width` is drawn with:
--- as wide as memos draws a stroke whose width follows its speed.
function Sketch.radiusFor(width, per_unit)
    local d = Drawing.strokeDiameter(width) * Drawing.SPEED_WIDTH * (per_unit or Drawing.SCREEN_PER_UNIT)
    return math.max(1, math.floor(d / 2 + 0.5))
end

function Sketch:radius(width) return Sketch.radiusFor(width or self.width, self.per_unit) end

function Sketch:inCanvas(x, y)
    local c = self.canvas
    return x >= c.x and y >= c.y and x < c.x + c.w and y < c.y + c.h
end

--- True while finger contacts are ignored: the pen near, or just gone.
function Sketch:palmGuard(now)
    if not self.pen_only then return false end
    local p = self.pen
    if p.near and p.last and now - p.last > Sketch.PEN_TIMEOUT then p.near = false; p.left = p.last end
    if p.near then return true end
    return p.left ~= nil and now - p.left < Sketch.PEN_GRACE
end

local function isPen(self, s)
    return s.tool == Sketch.TOOL_PEN or s.tool == Sketch.TOOL_ERASER
        or (self.pen_slot ~= nil and s.slot == self.pen_slot)
end

--- Strokes still showing.
function Sketch:live()
    local out = {}
    for _i, st in ipairs(self.strokes) do if not st.gone then out[#out + 1] = st end end
    return out
end

--- Nothing on the page: no strokes, no shapes or text (its paper doesn't count).
function Sketch:isEmpty()
    if #self:live() > 0 then return false end
    for _i, el in ipairs(self.locked) do
        if not (self.base and require("gzreader_notepaper").isBackground(self.base, el)) then return false end
    end
    return true
end

--- The page's paper: one of `gzreader_notepaper.lua`'s ids, "blank", or
--- "other" (a picture under the drawing that isn't one of them).
function Sketch:paper()
    local Notepaper = require("gzreader_notepaper")
    local bg = self.base and Notepaper.background(self.base)
    if not bg then return "blank" end
    return Notepaper.idOf(self.base, bg) or "other"
end

--- Fits the page (its shapes, pictures and strokes) to the canvas again, at
--- most `max_per_unit` screen pixels a unit, with a margin; the strokes
--- move with it.
function Sketch:refit()
    local scene_pts = {}
    for i, st in ipairs(self.strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do pts[j] = { self:toScene(p[1], p[2]) } end
        scene_pts[i] = pts
    end
    local minX, minY, maxX, maxY
    local function grow(x, y)
        minX, minY = math.min(minX or x, x), math.min(minY or y, y)
        maxX, maxY = math.max(maxX or x, x), math.max(maxY or y, y)
    end
    for _i, el in ipairs(self.locked) do
        local x, y = tonumber(el.x) or 0, tonumber(el.y) or 0
        grow(x, y); grow(x + (tonumber(el.width) or 0), y + (tonumber(el.height) or 0))
    end
    for i, st in ipairs(self.strokes) do
        if not st.gone then for _j, p in ipairs(scene_pts[i]) do grow(p[1], p[2]) end end
    end
    if not minX then return end
    local margin = Sketch.PADDING
    local c = self.canvas
    local fit = math.min((c.w - 2 * margin) / math.max(1, maxX - minX), (c.h - 2 * margin) / math.max(1, maxY - minY))
    self.per_unit = math.max(0.05, math.min(self.max_per_unit or self.per_unit, fit))
    -- (in the middle across, at the top)
    self.ox, self.oy = minX - (c.w / self.per_unit - (maxX - minX)) / 2, minY - margin / self.per_unit
    for i, st in ipairs(self.strokes) do
        for j, p in ipairs(scene_pts[i]) do st.points[j] = { self:toCanvas(p[1], p[2]) } end
    end
end

--- Puts the page on paper `id` (`gzreader_notepaper.lua`; "blank": none),
--- in place of its paper if it had one, and fits it to the canvas again.
function Sketch:setPaper(id)
    local Notepaper = require("gzreader_notepaper")
    if not self.base then self.base = Drawing.newScene() end
    local base = self.base
    local old = Notepaper.background(base)
    if old then
        for i, el in ipairs(base.elements) do if el == old then table.remove(base.elements, i); break end end
        for i, el in ipairs(self.locked) do if el == old then table.remove(self.locked, i); break end end
        if type(base.files) == "table" and old.fileId then base.files[old.fileId] = nil end
    end
    local el, file_id, file = Notepaper.element(id)
    if el then
        base.files = type(base.files) == "table" and base.files or {}
        base.files[file_id] = file
        table.insert(base.elements, 1, el)
        table.insert(self.locked, 1, el)
    end
    self.paper_changes = (self.paper_changes or 0) + 1
    self:refit()
    return true
end

--- A scene point in canvas pixels, and back.
function Sketch:toCanvas(sx, sy) return (sx - self.ox) * self.per_unit, (sy - self.oy) * self.per_unit end
function Sketch:toScene(cx, cy) return cx / self.per_unit + self.ox, cy / self.per_unit + self.oy end

local function snapWidth(w)
    w = tonumber(w) or 2
    if w <= 1.5 then return 1 elseif w < 3 then return 2 end
    return 4
end

--- A sketch of an existing drawing (a memos scene), to go on with it. It's
--- scaled down to fit the canvas if it's bigger (never up: `opts.per_unit`
--- at most) and placed at its top left with a margin. Its pen strokes can be
--- rubbed out like new ones; everything else (shapes, text, pictures made in
--- memos) is kept as it is (`locked`). Strokes left alone go back unchanged.
function Sketch.fromScene(scene, opts)
    local self = Sketch.new(opts)
    self.base = scene
    local b = Drawing.bounds(scene)
    if not b then return self end
    local margin = Sketch.PADDING
    local c = self.canvas
    if b.x >= 0 and b.y >= 0 and (b.x + b.w) * self.per_unit <= c.w and (b.y + b.h) * self.per_unit <= c.h then
        -- (it fits where it was drawn, at full size: a drawing made here comes back as it was)
        self.ox, self.oy = 0, 0
    else
        local fit = math.min((c.w - 2 * margin) / math.max(1, b.w), (c.h - 2 * margin) / math.max(1, b.h))
        self.per_unit = math.max(0.05, math.min(self.per_unit, fit))
        -- (in the middle across, at the top)
        self.ox, self.oy = b.x - (c.w / self.per_unit - b.w) / 2, b.y - margin / self.per_unit
    end
    for _i, el in ipairs(Drawing.liveElements(scene)) do
        if el.type == "freedraw" and type(el.points) == "table" and #el.points > 0 then
            local pts = {}
            for _j, p in ipairs(el.points) do
                local cx, cy = self:toCanvas((el.x or 0) + (p[1] or 0), (el.y or 0) + (p[2] or 0))
                pts[#pts + 1] = { cx, cy }
            end
            self.strokes[#self.strokes + 1] = { points = pts, width = snapWidth(el.strokeWidth), el = el }
        else
            self.locked[#self.locked + 1] = el
        end
    end
    return self
end

-- ------------------------------------------------------------------ input

--- The page's paper on the canvas (canvas pixels), or nil on a blank page:
--- strokes stay on the paper.
function Sketch:pageRect()
    local key = tostring(self.base) .. ":" .. self.per_unit .. ":" .. self.ox .. ":" .. self.oy .. ":" .. tostring(self.paper_changes)
    if self._page_key == key then return self._page end
    local bg = self.base and require("gzreader_notepaper").background(self.base)
    local rect
    if bg then
        local x1, y1 = self:toCanvas(tonumber(bg.x) or 0, tonumber(bg.y) or 0)
        local x2, y2 = self:toCanvas((tonumber(bg.x) or 0) + (tonumber(bg.width) or 0), (tonumber(bg.y) or 0) + (tonumber(bg.height) or 0))
        rect = { x = x1, y = y1, w = x2 - x1, h = y2 - y1 }
    end
    self._page, self._page_key = rect, key
    return rect
end

--- `rect` less `inset` on every side (a stroke's ink stays on the paper).
local function inset(rect, d)
    return { x = rect.x + d, y = rect.y + d, w = math.max(0, rect.w - 2 * d), h = math.max(0, rect.h - 2 * d) }
end
local function inRect(r, x, y) return x >= r.x and y >= r.y and x <= r.x + r.w and y <= r.y + r.h end

--- Where the line from `a` (on the page) to `b` (off it) leaves `r`.
function Sketch.edgePoint(r, a, b)
    local t = 1
    local dx, dy = b[1] - a[1], b[2] - a[2]
    if dx > 0 and b[1] > r.x + r.w then t = math.min(t, (r.x + r.w - a[1]) / dx) end
    if dx < 0 and b[1] < r.x then t = math.min(t, (r.x - a[1]) / dx) end
    if dy > 0 and b[2] > r.y + r.h then t = math.min(t, (r.y + r.h - a[2]) / dy) end
    if dy < 0 and b[2] < r.y then t = math.min(t, (r.y - a[2]) / dy) end
    t = math.max(0, t)
    return a[1] + dx * t, a[2] + dy * t
end

--- A point (canvas pixels) onto the contact's stroke, and its ink segment.
local function appendPoint(self, contact, cx, cy, out)
    local pts = contact.stroke.points
    local last = pts[#pts]
    if last and math.abs(cx - last[1]) < Sketch.MIN_STEP and math.abs(cy - last[2]) < Sketch.MIN_STEP then return end
    pts[#pts + 1] = { cx, cy }
    local r = self:radius(contact.stroke.width)
    local from = last or { cx, cy }
    out.segments[#out.segments + 1] = { from[1] + self.canvas.x, from[2] + self.canvas.y, cx + self.canvas.x, cy + self.canvas.y, r }
end

--- A drawing contact at screen (x, y). On paper, the stroke stays on it: it
--- ends where it leaves the paper, and starts again where it comes back.
local function addPoint(self, contact, x, y, out)
    local cx, cy = x - self.canvas.x, y - self.canvas.y
    local page = self:pageRect()
    if page then
        page = inset(page, self:radius(contact.width))
        local inside = inRect(page, cx, cy)
        local prev = contact.prev
        contact.prev = { cx, cy, inside }
        if not inside then
            if prev and prev[3] and contact.stroke then
                -- leaving the paper: up to its edge, and that piece is done
                local ex, ey = Sketch.edgePoint(page, prev, { cx, cy })
                appendPoint(self, contact, ex, ey, out)
                contact.pieces[#contact.pieces + 1] = contact.stroke
                self.strokes[#self.strokes + 1] = contact.stroke
                contact.stroke = nil
            end
            if contact.stroke and #contact.stroke.points == 0 then contact.stroke = nil end -- (begun off the paper)
            return
        end
        if not contact.stroke then
            contact.stroke = { points = {}, width = contact.width }
            if prev and not prev[3] then
                -- back on the paper: from its edge
                local ex, ey = Sketch.edgePoint(page, { cx, cy }, prev)
                appendPoint(self, contact, ex, ey, out)
            end
        end
    end
    appendPoint(self, contact, cx, cy, out)
end

local function distToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
    local qx, qy = ax + t * dx - px, ay + t * dy - py
    return math.sqrt(qx * qx + qy * qy)
end
Sketch.distToSegment = distToSegment

--- The live stroke under canvas point (x, y) within `reach` pixels, or nil.
function Sketch:strokeAt(x, y, reach)
    for i = #self.strokes, 1, -1 do
        local st = self.strokes[i]
        if not st.gone then
            local r = reach + self:radius(st.width)
            local pts = st.points
            if #pts == 1 then
                if distToSegment(x, y, pts[1][1], pts[1][2], pts[1][1], pts[1][2]) <= r then return st end
            else
                for j = 2, #pts do
                    if distToSegment(x, y, pts[j - 1][1], pts[j - 1][2], pts[j][1], pts[j][2]) <= r then return st end
                end
            end
        end
    end
end

local function erase(self, contact, x, y, out)
    local cx, cy = x - self.canvas.x, y - self.canvas.y
    -- along the eraser's way since the last frame, not only where it is now
    local from = contact.last or { cx, cy }
    local steps = math.max(1, math.ceil(math.max(math.abs(cx - from[1]), math.abs(cy - from[2])) / 4))
    for k = 1, steps do
        local px, py = from[1] + (cx - from[1]) * k / steps, from[2] + (cy - from[2]) * k / steps
        local reach = self:radius(4)
        local st = self:strokeAt(px, py, reach)
        while st do
            st.gone = true
            contact.erased[#contact.erased + 1] = st
            out.redraw = true
            st = self:strokeAt(px, py, reach)
        end
    end
    contact.last = { cx, cy }
end

local function startContact(self, s, now, out)
    local pen = isPen(self, s)
    local inside = self:inCanvas(s.x, s.y)
    local c = { x0 = s.x, y0 = s.y, moved = 0, pen = pen }
    if not inside then
        c.kind = "tap"
    elseif self.pen_only and not pen then
        c.kind = "ignore" -- fingers don't draw on a pen Kindle
        self.stats.ignored = self.stats.ignored + 1
    elseif self.drawing_slot ~= nil and self.drawing_slot ~= s.slot then
        c.kind = "ignore" -- one stroke at a time
        self.stats.ignored = self.stats.ignored + 1
    elseif s.tool == Sketch.TOOL_ERASER or self.tool == "eraser" then
        c.kind = "erase"
        c.erased = {}
        self.drawing_slot = s.slot
        erase(self, c, s.x, s.y, out)
    else
        c.kind = "draw"
        c.width = self.width
        c.pieces = {} -- (on paper: the parts of the stroke on it)
        c.stroke = { points = {}, width = self.width }
        self.drawing_slot = s.slot
        addPoint(self, c, s.x, s.y, out)
    end
    self.contacts[s.slot] = c
    return c
end

local function endContact(self, slot, out)
    local c = self.contacts[slot]
    if not c then return end
    self.contacts[slot] = nil
    if self.drawing_slot == slot then self.drawing_slot = nil end
    if c.kind == "draw" and (#c.pieces > 0 or (c.stroke and #c.stroke.points > 0)) then
        if c.stroke and #c.stroke.points > 0 then
            c.pieces[#c.pieces + 1] = c.stroke
            self.strokes[#self.strokes + 1] = c.stroke
        end
        -- (one Undo takes back the whole stroke, every piece of it)
        self.history[#self.history + 1] = { kind = "add", strokes = c.pieces }
        out.stroke_done = true
    elseif c.kind == "erase" and #c.erased > 0 then
        self.history[#self.history + 1] = { kind = "erase", strokes = c.erased }
    elseif c.kind == "tap" and c.moved <= self.tap_slop then
        out.taps[#out.taps + 1] = { x = c.x0, y = c.y0, pen = c.pen }
    end
end

--- The stroke being drawn (shown, not yet in `strokes`), if any.
function Sketch:current()
    local c = self.drawing_slot and self.contacts[self.drawing_slot]
    return c and c.stroke
end

--- Finger contacts under way when the pen arrives: dropped (a palm that
--- landed first). A finger stroke can't be under way on a pen Kindle.
local function dropFingers(self)
    for slot, c in pairs(self.contacts) do
        if not c.pen and c.kind ~= "ignore" then
            c.kind = "ignore"
            self.stats.palm = self.stats.palm + 1
        end
        if not c.pen and slot == self.drawing_slot then self.drawing_slot = nil end
    end
end

--- One input frame. `slots`: { { slot, id, x, y, tool }, … } (screen
--- coordinates). Returns { segments = { {x1, y1, x2, y2, r}, … }, redraw,
--- taps = { {x, y, pen}, … }, stroke_done }.
function Sketch:frame(slots, now)
    local out = { segments = {}, taps = {}, redraw = false }
    for _i, s in ipairs(slots) do
        local pen = isPen(self, s)
        if pen and self.pen_only then
            if s.tool == Sketch.TOOL_PEN or s.tool == Sketch.TOOL_ERASER then
                if not self.pen.near then dropFingers(self) end
                self.pen.near, self.pen.last, self.pen.left = true, now, nil
            else
                -- the pen's slot back to "finger": the pen left the screen
                if self.pen.near then self.pen.left = now end
                self.pen.near = false
            end
        end
        local c = self.contacts[s.slot]
        local down = s.id ~= nil and s.id ~= -1 and s.x ~= nil and s.y ~= nil
        if down then
            if not c then
                if not pen and self:palmGuard(now) then
                    self.contacts[s.slot] = { kind = "ignore", x0 = s.x, y0 = s.y, moved = 0 }
                    self.stats.palm = self.stats.palm + 1
                else
                    startContact(self, s, now, out)
                end
            else
                c.moved = math.max(c.moved, math.abs(s.x - c.x0), math.abs(s.y - c.y0))
                if c.kind == "draw" then addPoint(self, c, s.x, s.y, out)
                elseif c.kind == "erase" then erase(self, c, s.x, s.y, out) end
            end
        elseif c then
            endContact(self, s.slot, out)
        end
    end
    return out
end

-- ------------------------------------------------------------------ tools

function Sketch:setWidth(w) self.width = w; self.tool = "pen" end
function Sketch:setTool(tool) self.tool = tool end

function Sketch:canUndo() return #self.history > 0 end

--- Takes back the last stroke, erase or clear. True when something changed.
function Sketch:undo()
    local h = table.remove(self.history)
    if not h then return false end
    if h.kind == "add" then
        for _i, st in ipairs(h.strokes) do st.gone = true; st.undone = true end
    else
        for _i, st in ipairs(h.strokes) do st.gone = false end
    end
    -- strokes taken back by an undo go for good (an erase can't bring them back)
    local kept = {}
    for _i, st in ipairs(self.strokes) do if not st.undone then kept[#kept + 1] = st end end
    self.strokes = kept
    return true
end

--- Clears the page (undo brings it back). True when something changed.
function Sketch:clear()
    local live = self:live()
    if #live == 0 then return false end
    for _i, st in ipairs(live) do st.gone = true end
    self.history[#self.history + 1] = { kind = "clear", strokes = live }
    return true
end

-- ----------------------------------------------------------------- output

--- The box the live strokes cover, in canvas pixels, ink included; nil when empty.
function Sketch:bounds()
    local minX, minY, maxX, maxY
    for _i, st in ipairs(self:live()) do
        local r = self:radius(st.width)
        for _j, p in ipairs(st.points) do
            minX = math.min(minX or p[1] - r, p[1] - r)
            minY = math.min(minY or p[2] - r, p[2] - r)
            maxX = math.max(maxX or p[1] + r, p[1] + r)
            maxY = math.max(maxY or p[2] + r, p[2] + r)
        end
    end
    for _i, el in ipairs(self.locked) do
        local x0, y0 = self:toCanvas(el.x or 0, el.y or 0)
        local x1, y1 = self:toCanvas((el.x or 0) + (tonumber(el.width) or 0), (el.y or 0) + (tonumber(el.height) or 0))
        minX, minY = math.min(minX or x0, x0, x1), math.min(minY or y0, y0, y1)
        maxX, maxY = math.max(maxX or x1, x0, x1), math.max(maxY or y1, y0, y1)
    end
    if not minX then return nil end
    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

--- The part of the canvas the PNG shows: the strokes plus memos' padding,
--- inside the canvas, whole pixels. nil when nothing is drawn.
function Sketch:cropRect()
    local b = self:bounds()
    if not b then return nil end
    local pad = Sketch.PADDING * self.per_unit
    local x0 = math.max(0, math.floor(b.x - pad))
    local y0 = math.max(0, math.floor(b.y - pad))
    local x1 = math.min(self.canvas.w, math.ceil(b.x + b.w + pad))
    local y1 = math.min(self.canvas.h, math.ceil(b.y + b.h + pad))
    return { x = x0, y = y0, w = math.max(1, x1 - x0), h = math.max(1, y1 - y0) }
end

--- The drawing as a memos scene. An opened drawing keeps its own elements
--- in their order (strokes rubbed out left out, the rest unchanged), its
--- paper, files and anything else it has; new strokes come after.
function Sketch:scene(paper)
    local scene
    if self.base then
        scene = {}
        for k, v in pairs(self.base) do scene[k] = v end
        local keep = {}
        for _i, st in ipairs(self:live()) do if st.el then keep[st.el] = true end end
        local locked = {}
        for _i, el in ipairs(self.locked) do locked[el] = true end
        scene.elements = Drawing.list()
        for _i, el in ipairs(self.base.elements or {}) do
            if keep[el] or locked[el] then scene.elements[#scene.elements + 1] = el end
        end
    else
        scene = Drawing.newScene(paper)
    end
    for _i, st in ipairs(self:live()) do
        if not st.el then
            local pts = {}
            for j, p in ipairs(st.points) do pts[j] = { self:toScene(p[1], p[2]) } end
            Drawing.addStroke(scene, pts, { width = st.width, color = Drawing.INK })
        end
    end
    return scene
end

--- The centres of the discs that paint a segment of radius `r` (one every
--- r/2 pixels, both ends included): what the screen stamps.
function Sketch.stamps(x1, y1, x2, y2, r)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local step = math.max(1, r / 2)
    local n = math.max(1, math.ceil(len / step))
    local out = {}
    for i = 0, n do out[#out + 1] = { math.floor(x1 + dx * i / n + 0.5), math.floor(y1 + dy * i / n + 0.5) } end
    return out
end

--- Half-widths of a disc of radius `r`, row by row (dy = -r … r): { [dy] = dx }.
function Sketch.disc(r)
    local rows = {}
    for dy = -r, r do rows[dy] = math.floor(math.sqrt(math.max(0, r * r - dy * dy)) + 0.5) end
    return rows
end

return Sketch
