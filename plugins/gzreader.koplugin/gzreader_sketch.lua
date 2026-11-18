--[[--
What the drawing screen draws, from the touch screen's raw contacts: no UI,
so it's tested on its own (`sketch_test.lua`).

Two ways of drawing, by the Kindle:
  * **a pen** (the Kindle Scribe: KOReader's wacom protocol, the pen in its
    own slot): only the pen draws (its other end, or the pen with its side
    button held — `side_button` — rubs out). Fingers never draw, and while the pen is
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

local bit = require("bit")
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
    --- Pinch to zoom: at most this many times the page's fitted size.
    MAX_ZOOM = 4,
    --- A finger Kindle: a second finger this soon after the first makes a
    --- pinch (the first's stroke just begun is dropped); later, it's ignored.
    PINCH_WINDOW = 0.3,
    --- A pen Kindle: the two fingers of a pinch land within this of each other.
    PINCH_PAIR = 0.5,
    --- A pinch that changes the size less than this (a share) and moves less
    --- than PAN_MIN screen pixels does nothing (two fingers resting).
    --- A pinch or a one-finger pan shows on the page as it goes, at most once in this many seconds.
    LIVE_INTERVAL = 0.3,
    PINCH_MIN = 0.08,
    PAN_MIN = 24,
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
    self.zoomed = false -- (pinched bigger than the page's fit: `fit` keeps the fitted view)
    -- the scene point at the canvas's top left (an opened drawing is moved and scaled to fit)
    self.ox, self.oy = 0, 0
    self.layer_files = {} -- (the files of the pencil's layer in an opened drawing: dropped, made again)
    self.locked = {} -- an opened drawing's shapes and pictures: kept as they are, shown, not changed here
    self.texts = {} -- text boxes (memos' text elements, gzreader_drawtext.lua): moved, resized, typed in here
    self.text_gone = {} -- [box] = true: taken off (deleted, undone, cleared)
    self.base_texts = {} -- [box] = true: the opened drawing's own (written back in their place)
    self.tap_slop = opts.tap_slop or Sketch.TAP_SLOP
    self.width = opts.width or 2
    self.color = Sketch.inkColor(opts.color) -- nil: memos' ink
    self.tool = "pen" -- or "eraser"
    self.writing = opts.writing or "pen" -- the writing tool: Sketch.TOOL_IDS
    self.strokes = {} -- { points = { {x, y}, … } (canvas px), width, color (nil: memos' ink), gone }
    self.history = {} -- { kind = "add"|"erase"|"clear", strokes = { … } }
    self.contacts = {} -- slot → { kind = "draw"|"erase"|"tap"|"ignore", … }
    self.pen = { near = false, last = nil, left = nil }
    self.stats = { ignored = 0, palm = 0 }
    -- the pen's side button held (the Scribe's Premium Pen: KOReader's
    -- input.stylus_eraser_active): the pen rubs out while it's held, as on the Scribe
    self.side_button = false
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

-- ------------------------------------------------------------ pen pressure and tilt

--- What the pen has been seen to report (kept between drawings by the
--- drawing screen): its pressure and tilt come as raw numbers whose top
--- differs between pens and Kindles, so the range is learned from the pen.
--- p_seen / t_seen: the highest pressure and tilt seen; n: samples.
Sketch.range = { p_seen = 0, t_seen = 0, n = 0 }
Sketch.PRESSURE_GUESS = 4095 -- (a Wacom EMR pen's 4096 levels, until the pen shows otherwise)
Sketch.PRESSURE_SAMPLES = 300 -- after this many, a pen that never came near the guess sets the top itself
Sketch.TILT_DEGREES = 60 -- a pen laid this far over counts as fully tilted

function Sketch.noteRange(range, pressure, tx, ty)
    if type(pressure) == "number" and pressure > 0 then
        range.n = (range.n or 0) + 1
        if pressure > (range.p_seen or 0) then range.p_seen = pressure end
    end
    local t = math.max(math.abs(tonumber(tx) or 0), math.abs(tonumber(ty) or 0))
    if t > (range.t_seen or 0) then range.t_seen = t end
end

--- The pressure that counts as full.
function Sketch.pressureTop(range)
    local seen, n = range.p_seen or 0, range.n or 0
    if seen > Sketch.PRESSURE_GUESS then return seen end
    if n >= Sketch.PRESSURE_SAMPLES and seen > 0 and seen < 0.6 * Sketch.PRESSURE_GUESS then return seen end
    return Sketch.PRESSURE_GUESS
end

--- The tilt that counts as full: pens report degrees (up to about 60 to 90)
--- or hundredths of a degree (up to 9000).
function Sketch.tiltTop(range)
    return (range.t_seen or 0) > 127 and Sketch.TILT_DEGREES * 100 or Sketch.TILT_DEGREES
end

--- How heavy the line is at a point, 0 to 1 (0.5: the chosen thickness, as
--- a stroke without pressure), from the pen's pressure and tilt: pressing
--- harder makes it heavier, and so does laying the pen over (as shading
--- with the side of a pencil). nil without a pressure.
function Sketch.weight(range, pressure, tx, ty)
    if type(pressure) ~= "number" or pressure <= 0 then return nil end
    local p = math.min(1, pressure / Sketch.pressureTop(range))
    tx, ty = tonumber(tx) or 0, tonumber(ty) or 0
    local t = math.min(1, math.sqrt(tx * tx + ty * ty) / Sketch.tiltTop(range))
    return math.max(0.05, math.min(1, p * (1 + 0.9 * t)))
end

--- The ink's radius for a weight: from 0.4 of the chosen thickness's to 1.6 of it.
function Sketch.weightRadius(r, w)
    if not w then return r end
    return math.max(1, math.floor(r * (0.4 + 1.2 * w) + 0.5))
end

-- ---------------------------------------------------------------- the pencil

--- The paper's tooth at pixel (x, y), 0 to 1: the same for the same pixel
--- every time (a page drawn again looks the same), uneven from one pixel
--- to the next and in small clumps, as graphite catches on paper.
local bxor, tobit, rshift, band, floor = bit.bxor, bit.tobit, bit.rshift, bit.band, math.floor
local function grainHash(a, b)
    local h = bxor(tobit(a * 374761393), tobit(b * 668265263))
    h = bxor(h, rshift(h, 15))
    h = tobit(band(h, 0xFFFF) * 40503 + rshift(h, 16) * 30011)
    h = bxor(h, rshift(h, 13))
    return band(h, 0xFFFF) / 65536
end
-- (worked out once for a 256 x 256 patch that repeats over the page: a pencil
-- line asks for every pixel under it, several times over)
local GRAIN_SIDE = 256
local grain_patch
local function grainPatch()
    if not grain_patch then
        grain_patch = {}
        for y = 0, GRAIN_SIDE - 1 do
            for x = 0, GRAIN_SIDE - 1 do
                grain_patch[y * GRAIN_SIDE + x] = 0.65 * grainHash(x, y) + 0.35 * grainHash(floor(x / 2), floor(y / 2) + 7919)
            end
        end
    end
    return grain_patch
end
function Sketch.grain(x, y)
    return (grain_patch or grainPatch())[band(y, GRAIN_SIDE - 1) * GRAIN_SIDE + band(x, GRAIN_SIDE - 1)]
end

--- How much of the paper a tool with a grain covers, 0 to 1, at weight `w`
--- (the pen's pressure; none: as 0.5): light is sparse, pressed is nearly
--- solid. nil for a tool without a grain.
function Sketch.grainDensity(kind, w)
    if not Sketch.toolStyle(kind).grain then return nil end
    return 0.38 + 0.47 * math.max(0, math.min(1, w or 0.5))
end

--- True when a grained tool marks pixel (x, y), `d2` the square of its
--- distance from the middle of a line of radius `r` (thinner at its edges).
function Sketch.grainHit(x, y, density, d2, r)
    local edge = r > 0 and (1 - 0.45 * math.min(1, d2 / (r * r))) or 1
    return Sketch.grain(x, y) < density * edge
end

-- ------------------------------------------------- the pencil, for Memos

--- (The pencil's ink is ordinary see-through strokes in a saved drawing, as
--- the highlighter's: Memos' editor can move and erase them. For a few beta
--- builds it was carried as one picture with the strokes hidden under it
--- (customData.gzLayer); `fromScene` still leaves such a picture out and the
--- strokes come back shown at the next save. The owner, 2026-11-17: Memos'
--- note view shows the saved picture, texture and all; only its editor
--- draws from the strokes, and there they must stay editable.)

-- ------------------------------------------------------------ writing tools

--- The writing tools (as on the Kindle Scribe): how each draws. `scale`:
--- its width against the pen's at the same thickness; `lo`..`hi`: the
--- radius from the lightest to the heaviest press (`curve`: pressure raised
--- to it first: the fountain pen stays thin until you press, then swells);
--- `flat`: no pressure; `gray`: its ink on the screen (0 black … 255 paper),
--- painted only where it darkens, so it never lightens ink under it;
--- `opacity`: Memos' for it. A stroke keeps its tool (`kind`; nil: the pen).
Sketch.TOOL_IDS = { "pen", "fountain", "marker", "pencil", "highlighter" }
--- The pen button's own (the Kindle Scribe's order); the highlighter has a button to itself.
Sketch.PEN_IDS = { "pen", "fountain", "marker", "pencil" }
Sketch.TOOL_STYLE = {
    pen = { icon = "pen", scale = 1, lo = 0.4, hi = 1.6 },
    -- (grain: drawn as graphite on the paper's tooth, see Sketch.grain; `gray` is the tone it reads as)
    -- (scale: wider than the pen's line. At 0.7 a pencil line at Fine to Medium was two or three
    -- pixels across: too thin for its grain to show, a faint hairline once the picture was
    -- shown smaller than the Kindle's screen, as in Memos; the owner, 2026-11-17)
    pencil = { icon = "pencil", scale = 1.3, lo = 0.75, hi = 1.2, gray = 0x60, opacity = 70, grain = true },
    fountain = { icon = "fountain", scale = 1, lo = 0.15, hi = 2.8, curve = 1.6 },
    marker = { icon = "marker", scale = 1.9, flat = true }, -- (a felt tip: black, as wide all along)
    highlighter = { icon = "highlighter", scale = 3.5, flat = true, gray = 0xC8, opacity = 35 },
}

--- What the pen's shortcut (side) button switches to while it's held:
--- "eraser" (as on the Scribe out of the box) or a writing tool (Settings →
--- Notes → Pen's shortcut button; `sketch.shortcut`).
Sketch.SHORTCUTS = { "eraser", "pen", "pencil", "fountain", "marker", "highlighter" }
function Sketch.shortcutTool(sk)
    local v = sk and sk.shortcut
    if v == "eraser" or Sketch.TOOL_STYLE[v] then return v end
    return "eraser"
end

--- A tool's style (unknown: the pen's).
function Sketch.toolStyle(kind) return Sketch.TOOL_STYLE[kind or "pen"] or Sketch.TOOL_STYLE.pen end

--- The ink's radius for tool `kind`, from the pen's radius `r` at the chosen
--- thickness and the point's weight `w` (0..1, nil: no pressure).
function Sketch.toolRadius(kind, r, w)
    local st = Sketch.toolStyle(kind)
    local base = r * st.scale
    if st.flat or not w then return math.max(1, math.floor(base + 0.5)) end
    local wc = st.curve and (w ^ st.curve) or w
    return math.max(1, math.floor(base * (st.lo + (st.hi - st.lo) * wc) + 0.5))
end

--- The tool a stroke from Memos was drawn with: ours (customData.gzTool),
--- else a see-through one is a highlighter (opacity ≤ 50) or a pencil (< 100).
function Sketch.toolOf(el)
    local cd = type(el) == "table" and el.customData
    local id = type(cd) == "table" and cd.gzTool
    if id and Sketch.TOOL_STYLE[id] then return id ~= "pen" and id or nil end
    local o = tonumber(type(el) == "table" and el.opacity) or 100
    if o <= 50 then return "highlighter" end
    if o < 100 then return "pencil" end
    return nil
end

--- On the page, and not on something laid over it (`holes`: the toolbar,
--- the page buttons, an open panel; screen rectangles { x, y, w, h }).
function Sketch:inCanvas(x, y)
    local c = self.canvas
    if not (x >= c.x and y >= c.y and x < c.x + c.w and y < c.y + c.h) then return false end
    for _i, r in ipairs(self.holes or {}) do
        if x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h then return false end
    end
    return true
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

--- The text boxes on the page (not taken off).
function Sketch:liveTexts()
    local out = {}
    for _i, el in ipairs(self.texts) do if not self.text_gone[el] then out[#out + 1] = el end end
    return out
end

--- The text box at canvas point (x, y), top one first, and which part:
--- "resize" (its corner handle) or "move". nil when there's none.
function Sketch:textAt(x, y)
    local DrawText = require("gzreader_drawtext")
    local live = self:liveTexts()
    local function toCanvas(sx, sy) return self:toCanvas(sx, sy) end
    for i = #live, 1, -1 do
        local part = DrawText.partAt(DrawText.rect(live[i], toCanvas), x, y, self.text_handle)
        if part then return live[i], part end
    end
end

local function textChanged(self, el, before)
    local DrawText = require("gzreader_drawtext")
    self.history[#self.history + 1] = { kind = "text", el = el, before = before, after = DrawText.snap(el, self.text_gone[el]) }
    self.redone = {}
end

--- A new text box (gzreader_drawtext.lua's element) on the page; Undo takes it off.
function Sketch:addText(el)
    self.texts[#self.texts + 1] = el
    self.text_gone[el] = nil
    textChanged(self, el, { gone = true, x = el.x, y = el.y, width = el.width, height = el.height, text = el.text })
end

--- A box's `fields` (text, x, y, width, height) changed; Undo puts them back.
function Sketch:changeText(el, fields)
    local before = require("gzreader_drawtext").snap(el, self.text_gone[el])
    for k, v in pairs(fields) do el[k] = v end
    textChanged(self, el, before)
end

--- A box taken off the page; Undo brings it back.
function Sketch:removeText(el)
    local before = require("gzreader_drawtext").snap(el, self.text_gone[el])
    self.text_gone[el] = true
    textChanged(self, el, before)
end

--- Nothing on the page: no strokes, no shapes or text (its paper doesn't count).
function Sketch:isEmpty()
    if #self:live() > 0 then return false end
    if #self:liveTexts() > 0 then return false end
    for _i, el in ipairs(self.locked) do
        if not (self.base and require("gzreader_notepaper").isBackground(self.base, el)) then return false end
    end
    return true
end

--- The page's paper: one of `gzreader_notepaper.lua`'s ids, "blank", or
--- "other" (a picture under the drawing that isn't one of them).
function Sketch:paper()
    local key = tostring(self.base) .. ":" .. tostring(self.paper_changes)
    if self._paper_key == key then return self._paper_id end
    local id = self:paperNow()
    self._paper_key, self._paper_id = key, id
    return id
end

function Sketch:paperNow()
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
        for j, p in ipairs(st.points) do local x, y = self:toScene(p[1], p[2]); pts[j] = { x, y, p[3] } end
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
        for j, p in ipairs(scene_pts[i]) do local x, y = self:toCanvas(p[1], p[2]); st.points[j] = { x, y, p[3] } end
    end
    self.fit, self.zoomed = { per_unit = self.per_unit, ox = self.ox, oy = self.oy }, false
end

-- ------------------------------------------------------------- zoom

--- The view the page has when it isn't zoomed (refit's, or as it was made).
function Sketch:fitView()
    return self.fit or { per_unit = self.max_per_unit or self.per_unit, ox = 0, oy = 0 }
end

--- Moves the view to `per_unit`, `ox`, `oy`; the strokes (kept in canvas
--- pixels) move with it.
function Sketch:setView(per_unit, ox, oy)
    local scene_pts = {}
    for i, st in ipairs(self.strokes) do
        local pts = {}
        for j, p in ipairs(st.points) do local x, y = self:toScene(p[1], p[2]); pts[j] = { x, y, p[3] } end
        scene_pts[i] = pts
    end
    self.per_unit, self.ox, self.oy = per_unit, ox, oy
    for i, st in ipairs(self.strokes) do
        for j, p in ipairs(scene_pts[i]) do local x, y = self:toCanvas(p[1], p[2]); st.points[j] = { x, y, p[3] } end
    end
end

--- Back to the page's fitted view (before saving: the picture is made from what's on screen).
function Sketch:unzoom()
    if not self.zoomed then return false end
    local f = self:fitView()
    self:setView(f.per_unit, f.ox, f.oy)
    self.zoomed = false
    return true
end

--- Zoomed by `scale` around canvas point (fx, fy), which ends up at (tx, ty)
--- (a pinch: the fingers' middle at the start and at the end). Never smaller
--- than the fitted page (near it: back to it), at most MAX_ZOOM times it, and
--- never moved off the page. Returns the zoom now (1: fitted).
function Sketch:zoomBy(scale, fx, fy, tx, ty)
    local f = self:fitView()
    local pu = math.max(f.per_unit, math.min(f.per_unit * Sketch.MAX_ZOOM, self.per_unit * scale))
    if pu <= f.per_unit * 1.03 then
        self:unzoom()
        return 1
    end
    local sx, sy = self:toScene(fx, fy)
    local ox, oy = sx - tx / pu, sy - ty / pu
    -- (the window stays on the page: within the fitted view)
    local c = self.canvas
    ox = math.max(f.ox, math.min(f.ox + c.w / f.per_unit - c.w / pu, ox))
    oy = math.max(f.oy, math.min(f.oy + c.h / f.per_unit - c.h / pu, oy))
    self:setView(pu, ox, oy)
    self.zoomed = true
    return pu / f.per_unit
end

--- The zoom now (1: the fitted page).
function Sketch:zoom() return self.per_unit / self:fitView().per_unit end

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

--- Puts a picture on the page, as memos' drawing sheet places one: an
--- `image` element `w` x `h` (scene units) centred on scene point (cx, cy),
--- its pixels a file of the scene (`data_url`, `mime`). It's kept like
--- memos' own pictures (shown, under the ink, not changed here); undo takes
--- it off. Returns the element.
function Sketch:addPicture(data_url, mime, w, h, cx, cy, now)
    if not self.base then self.base = Drawing.newScene() end
    local base = self.base
    base.files = type(base.files) == "table" and base.files or {}
    local file_id = Drawing.randomId()
    base.files[file_id] = { mimeType = mime or "image/jpeg", id = file_id, dataURL = data_url, created = now or (os.time() * 1000) }
    local el = {
        id = Drawing.randomId(), type = "image", x = cx - w / 2, y = cy - h / 2, width = w, height = h,
        angle = 0, strokeColor = "transparent", backgroundColor = "transparent", strokeWidth = 1, opacity = 100,
        isDeleted = false, groupIds = Drawing.list(), boundElements = Drawing.list(), seed = Drawing.randomSeed(),
        locked = false, fileId = file_id, status = "saved", scale = Drawing.list({ 1, 1 }),
        version = 1, versionNonce = Drawing.randomSeed(), updated = now or (os.time() * 1000),
    }
    base.elements = base.elements or Drawing.list()
    base.elements[#base.elements + 1] = el
    self.locked[#self.locked + 1] = el
    self.history[#self.history + 1] = { kind = "picture", el = el, strokes = {} }
    self.redone = {}
    return el
end

Sketch.PICTURE_SHARE = 0.6 -- a picture placed at most this share of the page shown, across and down
Sketch.PICTURE_STEP = 24 -- several pictures fan out by this (scene units), as memos' drawing sheet does

--- Where pictures go and how big (scene units): `n` pictures, each { w, h }
--- pixels, centred on the middle of what's shown (fanned out a step down and
--- to the right each, as memos' drawing sheet places several), each at most
--- PICTURE_SHARE of the page shown and never bigger than its own pixels.
--- Returns { { cx, cy, w, h } }.
function Sketch.placePictures(sizes, view)
    local out = {}
    local n = #sizes
    for i, sz in ipairs(sizes) do
        local pw, ph = math.max(1, sz.w or 1), math.max(1, sz.h or 1)
        local fit = math.min(1, view.w * Sketch.PICTURE_SHARE / pw, view.h * Sketch.PICTURE_SHARE / ph)
        local off = (i - (n + 1) / 2) * Sketch.PICTURE_STEP
        out[i] = { cx = view.cx + off, cy = view.cy + off, w = pw * fit, h = ph * fit }
    end
    return out
end

local function dropPicture(self, el)
    for i, x in ipairs(self.base and self.base.elements or {}) do if x == el then table.remove(self.base.elements, i); break end end
    for i, x in ipairs(self.locked) do if x == el then table.remove(self.locked, i); break end end
end

local function putPicture(self, el)
    self.base.elements[#self.base.elements + 1] = el
    self.locked[#self.locked + 1] = el
end

--- A scene point in canvas pixels, and back.
function Sketch:toCanvas(sx, sy) return (sx - self.ox) * self.per_unit, (sy - self.oy) * self.per_unit end
function Sketch:toScene(cx, cy) return cx / self.per_unit + self.ox, cy / self.per_unit + self.oy end

--- The pen's widths (memos' stroke widths: its own are 1, 2 and 4; any number draws).
Sketch.WIDTHS = { 0.5, 1, 2, 4, 7 }

local function snapWidth(w)
    w = tonumber(w) or 2
    return math.max(0.25, math.min(12, w))
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
        -- (and this is the view to come back to: a pinch is measured from it, and
        -- never smaller than it; without it, a page that didn't fit at full size
        -- (a journal's drawing under its prompt) was taken for zoomed out, and
        -- couldn't be pinched bigger or moved with a finger)
        self.fit = { per_unit = self.per_unit, ox = self.ox, oy = self.oy }
    end
    for _i, el in ipairs(Drawing.liveElements(scene)) do
        if el.type == "freedraw" and type(el.points) == "table" and #el.points > 0 then
            local pts = {}
            for _j, p in ipairs(el.points) do
                local cx, cy = self:toCanvas((el.x or 0) + (p[1] or 0), (el.y or 0) + (p[2] or 0))
                -- (drawn with a pen's pressure, here or in Memos: each point's weight)
                pts[#pts + 1] = { cx, cy, el.simulatePressure == false and tonumber(p[3]) or nil }
            end
            local kind = Sketch.toolOf(el)
            if Sketch.toolStyle(kind).grain and tonumber(el.opacity) == 0 then
                -- (hidden under a picture of the pencil's ink by a few beta builds: shown again)
                el.opacity = Sketch.toolStyle(kind).opacity
            end
            -- (Memos is given the tool's own width: the thickness chosen is that over its scale)
            local width = snapWidth((tonumber(el.strokeWidth) or 2) / Sketch.toolStyle(kind).scale)
            self.strokes[#self.strokes + 1] = { points = pts, width = width, color = Sketch.inkColor(el.strokeColor), el = el, kind = kind }
        elseif el.type == "image" and type(el.customData) == "table" and el.customData.gzLayer then
            -- (the picture of the pencil's ink made for Memos at the last save: made again
            -- from the strokes at the next, so neither shown nor kept; no longer made, see above)
            self.layer_files[el.fileId or ""] = true
        elseif el.type == "text" and type(el.text) == "string" then
            -- (a text box, here or from memos: moved, resized and typed in like a new one)
            self.texts[#self.texts + 1] = el
            self.base_texts[el] = true
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
    -- (a pen that tells how hard it's pressed: each point's weight, and the line as wide)
    local w = contact.weight
    pts[#pts + 1] = { cx, cy, w }
    local kind = contact.stroke.kind
    local r = Sketch.toolRadius(kind, self:radius(contact.stroke.width), w and (last and last[3] and (last[3] + w) / 2 or w) or nil)
    local from = last or { cx, cy }
    out.segments[#out.segments + 1] = { from[1] + self.canvas.x, from[2] + self.canvas.y, cx + self.canvas.x, cy + self.canvas.y, r,
        contact.stroke.color, Sketch.toolStyle(kind).gray, Sketch.grainDensity(kind, w) }
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
            contact.stroke = { points = {}, width = contact.width, color = contact.color, kind = contact.writing }
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
--- The canvas rectangle stroke `st` is drawn in ({ x0, y0, x1, y1 }, a little over: as wide as its tool can make it).
function Sketch:strokeBox(st)
    local r = Sketch.toolRadius(st.kind, self:radius(st.width), 1) + 2
    local x0, y0, x1, y1
    for _i, p in ipairs(st.points) do
        x0, y0 = math.min(x0 or p[1], p[1]), math.min(y0 or p[2], p[2])
        x1, y1 = math.max(x1 or p[1], p[1]), math.max(y1 or p[2], p[2])
    end
    if not x0 then return nil end
    return { x0 = math.floor(x0 - r), y0 = math.floor(y0 - r), x1 = math.ceil(x1 + r), y1 = math.ceil(y1 + r) }
end

--- The rectangle around `strokes` (and `area`, when given): what changes on the page when they come or go.
function Sketch:strokesArea(strokes, area)
    for _i, st in ipairs(strokes or {}) do
        local b = self:strokeBox(st)
        if b then
            if area then
                area.x0, area.y0, area.x1, area.y1 = math.min(area.x0, b.x0), math.min(area.y0, b.y0), math.max(area.x1, b.x1), math.max(area.y1, b.y1)
            else
                area = b
            end
        end
    end
    return area
end

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
        local reach = self:radius(self.eraser_width or 4)
        local st = self:strokeAt(px, py, reach)
        while st do
            st.gone = true
            contact.erased[#contact.erased + 1] = st
            if self.selection then self.selection = nil; out.sel_changed = true end
            out.redraw = true
            -- (what changed: only this much of the page needs drawing again)
            out.area = self:strokesArea({ st }, out.area)
            st = self:strokeAt(px, py, reach)
        end
    end
    contact.last = { cx, cy }
end

--- A finger landing at `s` while one other finger is down: the pinch's other
--- finger's slot, or nil. A finger Kindle: the other is drawing, begun within
--- PINCH_WINDOW. A pen Kindle: the other (fingers don't draw there) landed
--- within PINCH_PAIR, and nothing else is down (a hand is three or more).
local function pinchPartner(self, s, now)
    local other, n = nil, 0
    for slot, c in pairs(self.contacts) do
        if slot ~= s.slot and c.kind ~= "tap" then
            n = n + 1
            other = slot
        end
    end
    if n ~= 1 then return nil end
    local oc = self.contacts[other]
    if oc.pen or not oc.inside or oc.palm then return nil end
    if self.pen_only then
        if (oc.kind == "ignore" or oc.kind == "pan") and oc.t0 and now - oc.t0 <= Sketch.PINCH_PAIR then return other end
    elseif oc.kind == "draw" and oc.t0 and now - oc.t0 <= Sketch.PINCH_WINDOW then
        return other
    end
end

local function startContact(self, s, now, out)
    local pen = isPen(self, s)
    local inside = self:inCanvas(s.x, s.y)
    local c = { x0 = s.x, y0 = s.y, moved = 0, pen = pen, t0 = now, inside = inside, x = s.x, y = s.y }
    if inside and not pen and self.pinch then
        -- a third finger: not a pinch (a hand)
        self.pinch.cancel = true
        c.kind = "ignore"
        self.contacts[s.slot] = c
        return c
    end
    local partner = inside and not pen and pinchPartner(self, s, now)
    if partner then
        local oc = self.contacts[partner]
        if oc.kind == "draw" then
            -- (a finger Kindle: the stroke the first finger began is dropped)
            if self.drawing_slot == partner then self.drawing_slot = nil end
            out.redraw = true
        end
        oc.kind, c.kind = "pinch", "pinch"
        self.pinch = { a = partner, b = s.slot, a0 = { oc.x, oc.y }, b0 = { s.x, s.y }, a1 = { oc.x, oc.y }, b1 = { s.x, s.y }, at = now }
        self.contacts[s.slot] = c
        return c
    end
    if self.pull_zone and s.y < self.pull_zone and not (pen and inside) then
        -- from the top edge (or the top bar): a tap there, or a pull down that opens the quick panel
        c.kind, c.pull = "tap", true
    elseif not inside then
        c.kind = "tap"
    elseif self.tool == "hand" then
        -- the hand: the pen (or a finger) takes hold of the page and moves it
        c.kind, c.slot = "pan", s.slot
        c.px, c.py, c.at = s.x, s.y, now
    elseif self.tool == "text" then
        -- the text tool: a box under the finger or pen moves (its corner: resizes); a tap elsewhere adds one
        local el, part = self:textAt(s.x - self.canvas.x, s.y - self.canvas.y)
        c.kind, c.el, c.part, c.at = "text", el, part, now
        if el then c.orig = { x = el.x, y = el.y, width = el.width, height = el.height } end
    elseif self.pen_only and not pen and self.zoomed then
        -- A pen Kindle, zoomed in: a finger moves the page (a second, at once: a pinch).
        -- Whatever else rests on the screen: only "the first finger down, nothing else
        -- there" could move it before, and a thumb holding the Kindle by its edge was
        -- enough for no finger to (the owner, 2026-11-17).
        c.kind, c.slot = "pan", s.slot
        c.px, c.py, c.at = s.x, s.y, now
    elseif self.pen_only and not pen then
        c.kind = "ignore" -- fingers don't draw on a pen Kindle
        self.stats.ignored = self.stats.ignored + 1
    elseif self.drawing_slot ~= nil and self.drawing_slot ~= s.slot then
        c.kind = "ignore" -- one stroke at a time
        self.stats.ignored = self.stats.ignored + 1
    elseif self.tool == "lasso" and s.tool ~= Sketch.TOOL_ERASER and not (pen and self.side_button and Sketch.shortcutTool(self) == "eraser") then
        -- the lasso: on what's chosen, it's moved (a corner: resized); elsewhere, a loop is drawn (a tap: lets go, or Paste)
        local Lasso = require("gzreader_lasso")
        local cx, cy = s.x - self.canvas.x, s.y - self.canvas.y
        c.kind = "lasso"
        self.drawing_slot = s.slot
        local box = self:selectionBox()
        c.part = box and Lasso.hit(box, cx, cy, self.lasso_handle or 24) or nil
        if c.part then
            -- (the strokes' own box is what moves and grows; the frame is that with a little room around it)
            c.box0, c.pad, c.snap, c.at = self:strokesArea(self.selection.strokes), self.lasso_pad or 0, Lasso.snapshot(self.selection.strokes), now
        else
            c.loop = { { cx, cy } }
        end
    elseif s.tool == Sketch.TOOL_ERASER or self.tool == "eraser" or (pen and self.side_button and Sketch.shortcutTool(self) == "eraser") then
        c.kind = "erase"
        c.erased = {}
        self.drawing_slot = s.slot
        erase(self, c, s.x, s.y, out)
    else
        c.kind = "draw"
        c.width = self.width
        c.color = self.color
        c.pieces = {} -- (on paper: the parts of the stroke on it)
        -- (the writing tool: the pen's own stroke has no kind; the pencil and the
        -- highlighter are grey, so they take no colour)
        -- (the pen's shortcut button held: its tool instead of the one in hand)
        local writing = (pen and self.side_button) and Sketch.shortcutTool(self) or self.writing
        local kind = writing ~= "pen" and Sketch.TOOL_STYLE[writing] and writing or nil
        local style = Sketch.toolStyle(kind)
        c.writing = kind
        c.color = not style.gray and self.color or nil
        c.stroke = { points = {}, width = self.width, color = c.color, kind = kind }
        self.drawing_slot = s.slot
        if self.tool == "shape" and Sketch.SHAPE_SET[self.shape or ""] then
            -- a shape: from where the pen lands to where it lifts (drawn then), in the pen's ink
            c.shape, c.writing, c.color = self.shape, nil, self.color
            c.stroke = { points = {}, width = self.width, color = self.color }
            self.contacts[s.slot] = c
            return c
        end
        -- a pen with pressure (and the setting on): the whole stroke has weights (not a highlighter's)
        if self.pressure_on ~= false and pen and s.pressure ~= nil and not style.flat then
            c.pressured = true
            c.weight = Sketch.weight(Sketch.range, s.pressure, s.tilt_x, s.tilt_y) or 0.5
        end
        addPoint(self, c, s.x, s.y, out)
    end
    self.contacts[s.slot] = c
    return c
end

--- The pinch over (a finger lifted): zoomed (and moved) as the fingers did.
--- The pinch so far, put on the page: zoomed and moved as the fingers have
--- gone since it was last put on (true when the view changed). `final`: the
--- fingers lifted (the small-movement limits are for a whole pinch).
local function applyPinch(self, out, final)
    local p = self.pinch
    local function dist(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
    local d0, d1 = math.max(1, dist(p.a0, p.b0)), dist(p.a1, p.b1)
    local scale = d1 / d0
    local m0 = { (p.a0[1] + p.b0[1]) / 2, (p.a0[2] + p.b0[2]) / 2 }
    local m1 = { (p.a1[1] + p.b1[1]) / 2, (p.a1[2] + p.b1[2]) / 2 }
    local moved = dist(m0, m1)
    -- (once it has shown on the page, the rest follows however small)
    if not p.live and math.abs(scale - 1) < Sketch.PINCH_MIN and (moved < Sketch.PAN_MIN or not self.zoomed) then return false end
    if not p.live and math.abs(scale - 1) < Sketch.PINCH_MIN then scale = 1 end -- (two fingers dragged: moved, not zoomed)
    if p.live and not final and math.abs(scale - 1) < 0.02 and moved < 4 then return false end
    local cv = self.canvas
    local before = self:zoom()
    local now_zoom = self:zoomBy(scale, m0[1] - cv.x, m0[2] - cv.y, m1[1] - cv.x, m1[2] - cv.y)
    p.a0, p.b0 = { p.a1[1], p.a1[2] }, { p.b1[1], p.b1[2] }
    p.from = p.from or before
    p.live = true
    out.redraw, out.view = true, true
    if final then out.zoom = { from = p.from, to = now_zoom } end
    return true
end

local function endPinch(self, out)
    local p = self.pinch
    for _i, slot in ipairs({ p.a, p.b }) do
        local c = self.contacts[slot]
        if c then c.kind = "ignore" end -- (the other finger, still down, does nothing more)
    end
    if not p.cancel then applyPinch(self, out, true) end
    self.pinch = nil
end

--- One finger on a zoomed page (a pen Kindle: fingers don't draw there)
--- moves the page with it. True when the view changed.
local function applyPan(self, c, out)
    local dx, dy = c.x - c.px, c.y - c.py
    if not c.panning and math.abs(dx) < Sketch.PAN_MIN and math.abs(dy) < Sketch.PAN_MIN then return false end
    if dx == 0 and dy == 0 then return false end
    -- (the first to move is the one that moves the page: a thumb resting at the
    -- screen's edge, or the side of a hand, is another contact and stays still)
    local holder = self.pan_slot ~= nil and self.contacts[self.pan_slot]
    if not (holder and holder.kind == "pan") then self.pan_slot = nil end -- (lifted, or dropped when the pen came)
    if self.pan_slot ~= nil and self.pan_slot ~= c.slot then return false end
    if not c.panning then self.stats.panned = (self.stats.panned or 0) + 1 end
    self.pan_slot = c.slot
    c.panning = true
    local cv = self.canvas
    self:zoomBy(1, c.px - cv.x, c.py - cv.y, c.x - cv.x, c.y - cv.y)
    c.px, c.py = c.x, c.y
    out.redraw, out.view = true, true
    return true
end

--- The lasso's frame as the drag of contact `c` has it now (and, for a corner, the scale and the corner that stays).
local function lassoDrag(c)
    local Lasso = require("gzreader_lasso")
    local pad = c.pad or 0
    local function framed(b) return { x0 = b.x0 - pad, y0 = b.y0 - pad, x1 = b.x1 + pad, y1 = b.y1 + pad } end
    if c.part == "inside" then return framed(Lasso.boxAfter(c.box0, "inside", c.x - c.x0, c.y - c.y0)) end
    local f, ax, ay = Lasso.scaleFor(c.box0, c.part, c.x0, c.y0, c.x, c.y)
    return framed(Lasso.boxAfter(c.box0, c.part, 0, 0, f, ax, ay)), f, ax, ay
end

--- The lasso's contact moved: the loop grows (`out.loop`: its new bits, in
--- screen pixels, to draw), or the chosen strokes' frame follows, a step at
--- a time (`out.sel_preview`; the strokes themselves move when it lifts).
local function lassoMove(self, c, s, now, out)
    if c.part then
        if self.selection and c.moved > self.tap_slop and now - c.at >= Sketch.LIVE_INTERVAL then
            self.selection.preview = lassoDrag(c)
            out.sel_preview = true
            c.at = now
        end
        return
    end
    local cx, cy = s.x - self.canvas.x, s.y - self.canvas.y
    local last = c.loop[#c.loop]
    if math.abs(cx - last[1]) + math.abs(cy - last[2]) >= 3 then
        c.loop[#c.loop + 1] = { cx, cy }
        out.loop = out.loop or {}
        out.loop[#out.loop + 1] = { last[1] + self.canvas.x, last[2] + self.canvas.y, s.x, s.y }
    end
end

--- The lasso's contact lifted.
local function lassoEnd(self, c, out)
    local Lasso = require("gzreader_lasso")
    local sel = self.selection
    if c.part then
        if not sel then return end
        local shown = sel.preview ~= nil
        sel.preview = nil
        if c.moved <= self.tap_slop then
            if shown then out.sel_changed = true end
            return
        end
        if c.part == "inside" then
            Lasso.move(sel.strokes, c.snap, c.x - c.x0, c.y - c.y0)
        else
            local f, ax, ay = select(2, lassoDrag(c))
            Lasso.scale(sel.strokes, c.snap, f, ax, ay)
        end
        -- (strokes of an opened drawing: written again where they are now, not as they came)
        for _i, st in ipairs(sel.strokes) do st.el = nil end
        self.history[#self.history + 1] = { kind = "move", strokes = sel.strokes, before = c.snap, after = Lasso.snapshot(sel.strokes) }
        self.redone = {}
        local b = c.box0
        out.area = self:strokesArea(sel.strokes, { x0 = b.x0, y0 = b.y0, x1 = b.x1, y1 = b.y1 })
        out.redraw, out.stroke_done, out.sel_changed = true, true, true
        return
    end
    if c.moved <= self.tap_slop then
        -- a tap: lets go of what's chosen; with nothing chosen and something copied, Paste here
        if sel then
            self.selection = nil
            out.sel_changed = true
        elseif Lasso.clipboard then
            out.paste_at = { x = c.x0, y = c.y0 }
        end
        return
    end
    local picked = Lasso.pick(self.strokes, c.loop)
    self.selection = #picked > 0 and { strokes = picked } or nil
    out.sel_changed = true
end

local function endContact(self, slot, out)
    local c = self.contacts[slot]
    if not c then return end
    self.contacts[slot] = nil
    if self.drawing_slot == slot then self.drawing_slot = nil end
    if c.kind == "lasso" then return lassoEnd(self, c, out) end
    if c.kind == "pinch" and self.pinch then return endPinch(self, out) end
    if c.kind == "pan" then
        applyPan(self, c, out)
        if self.pan_slot == slot then self.pan_slot = nil end
        return
    end
    if c.kind == "text" then
        if c.moved <= self.tap_slop then
            out.text_tap = { el = c.el, x = c.x0 - self.canvas.x, y = c.y0 - self.canvas.y }
        elseif c.el then
            Sketch.dragText(self, c)
            local o = c.orig
            textChanged(self, c.el, { x = o.x, y = o.y, width = o.width, height = o.height, text = c.el.text })
            out.redraw, out.stroke_done = true, true
        end
        return
    end
    if c.kind == "draw" and c.shape then
        local pts = c.moved > self.tap_slop and self:shapePoints(c.shape, c.x0, c.y0, c.x, c.y) or {}
        for _i, p in ipairs(pts) do c.stroke.points[#c.stroke.points + 1] = p end
        out.redraw = #pts > 0
    end
    -- held still at its end (shapes cleaned up: the Newton's way): a rough line, circle,
    -- triangle or box becomes a clean one, where it was drawn
    if c.kind == "draw" and not c.shape and self.snap_shapes and c.stroke and #c.pieces == 0
        and require("gzreader_shapesnap").held(c.trail, c.lift_at) then
        local SS = require("gzreader_shapesnap")
        local kind, clean = SS.recognise(c.stroke.points)
        if kind then
            local before = self:strokeBox(c.stroke)
            for _i, p in ipairs(clean) do p[1], p[2] = math.floor(p[1] + 0.5), math.floor(p[2] + 0.5) end
            c.stroke.points = clean
            out.redraw = true
            out.area = self:strokesArea({ c.stroke }, before)
            out.snapped = kind
            self.snapped = (self.snapped or 0) + 1
        end
    end
    if c.kind == "draw" and (#c.pieces > 0 or (c.stroke and #c.stroke.points > 0)) then
        if c.stroke and #c.stroke.points > 0 then
            c.pieces[#c.pieces + 1] = c.stroke
            self.strokes[#self.strokes + 1] = c.stroke
        end
        -- (one Undo takes back the whole stroke, every piece of it)
        self.history[#self.history + 1] = { kind = "add", strokes = c.pieces }
        self.redone = {}
        out.stroke_done = true
    elseif c.kind == "erase" and #c.erased > 0 then
        self.history[#self.history + 1] = { kind = "erase", strokes = c.erased }
        self.redone = {}
        out.stroke_done = true
    elseif c.kind == "tap" and c.pull and Sketch.pulledDown(c.x0, c.y0, c.x, c.y, self.pull_distance or Sketch.PULL_DISTANCE) then
        out.pull = true
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
        if s.pressure ~= nil or s.tilt_x ~= nil then Sketch.noteRange(Sketch.range, s.pressure, s.tilt_x, s.tilt_y) end
        local c = self.contacts[s.slot]
        local down = s.id ~= nil and s.id ~= -1 and s.x ~= nil and s.y ~= nil
        if down then
            if not c then
                if not pen and self:palmGuard(now) then
                    self.contacts[s.slot] = { kind = "ignore", x0 = s.x, y0 = s.y, moved = 0, palm = true }
                    self.stats.palm = self.stats.palm + 1
                else
                    startContact(self, s, now, out)
                end
            else
                c.moved = math.max(c.moved, math.abs(s.x - c.x0), math.abs(s.y - c.y0))
                if c.kind == "draw" and c.pressured then
                    -- (eased: a pen's pressure jumps about from sample to sample)
                    local w = Sketch.weight(Sketch.range, s.pressure, s.tilt_x, s.tilt_y)
                    if w then c.weight = 0.5 * c.weight + 0.5 * w end
                end
                c.x, c.y = s.x, s.y
                if c.kind == "pinch" and self.pinch then
                    local p = self.pinch
                    if s.slot == p.a then p.a1 = { s.x, s.y } elseif s.slot == p.b then p.b1 = { s.x, s.y } end
                    -- (the page follows the fingers, a step at a time: e-ink can't redraw at every sample)
                    if not p.cancel and now - p.at >= Sketch.LIVE_INTERVAL and applyPinch(self, out, false) then p.at = now end
                elseif c.kind == "pan" then
                    if now - c.at >= Sketch.LIVE_INTERVAL and applyPan(self, c, out) then c.at = now end
                elseif c.kind == "text" then
                    -- (the box follows, a step at a time: e-ink can't redraw at every sample)
                    if c.el and c.moved > self.tap_slop and now - c.at >= Sketch.LIVE_INTERVAL then
                        Sketch.dragText(self, c)
                        out.redraw = true
                        c.at = now
                    end
                elseif c.kind == "draw" then
                    if not c.shape then addPoint(self, c, s.x, s.y, out) end -- (a shape: drawn when the pen lifts)
                    -- (the stroke's last moments, to tell a hold at its end: gzreader_shapesnap.lua)
                    if self.snap_shapes and not c.shape then
                        local tr = c.trail or {}
                        tr[#tr + 1] = { now, s.x, s.y }
                        if #tr > 60 then table.remove(tr, 1) end
                        c.trail = tr
                    end
                elseif c.kind == "lasso" then lassoMove(self, c, s, now, out)
                elseif c.kind == "erase" then erase(self, c, s.x, s.y, out) end
            end
        elseif c then
            c.lift_at = now
            endContact(self, s.slot, out)
        end
    end
    return out
end

-- ------------------------------------------------------------------ shapes

--- The shapes (the Kindle Scribe's): drawn corner to corner, kept as a
--- stroke along the shape's outline (Memos' drawings have no triangle, and
--- a stroke is undone, rubbed out and sent like any other).
--- A pull down from the top edge: the quick panel, as at Home and in a book.
--- `pull_zone` (screen pixels from the top; set by the drawing screen: its top
--- bar, or a strip when it's folded away) is where one may start.
Sketch.PULL_DISTANCE = 60

--- True when a contact from (x0, y0) to (x1, y1) went down far enough, more down than across.
function Sketch.pulledDown(x0, y0, x1, y1, distance)
    local dy = (y1 or y0) - y0
    return dy >= (distance or Sketch.PULL_DISTANCE) and math.abs((x1 or x0) - x0) < dy
end

Sketch.SHAPES = { "square", "circle", "triangle", "line", "arrow" }
Sketch.SHAPE_SET = { square = true, circle = true, triangle = true, line = true, arrow = true }
Sketch.ERASER_WIDTHS = { 1, 2, 4, 7, 12 } -- how near a stroke the eraser takes it (the pen's widths, and a wider one)

--- Shape `kind`'s outline from (x0, y0) to (x1, y1), as { x, y } points.
function Sketch.outline(kind, x0, y0, x1, y1)
    local pts = {}
    local function to(x, y) pts[#pts + 1] = { x, y } end
    if kind == "square" then
        to(x0, y0); to(x1, y0); to(x1, y1); to(x0, y1); to(x0, y0)
    elseif kind == "circle" then
        local cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, math.abs(x1 - x0) / 2, math.abs(y1 - y0) / 2
        local n = math.max(24, math.min(96, math.floor((rx + ry) / 4)))
        for i = 0, n do
            local a = 2 * math.pi * i / n
            to(cx + rx * math.cos(a), cy + ry * math.sin(a))
        end
    elseif kind == "triangle" then
        local top, bottom = math.min(y0, y1), math.max(y0, y1)
        to((x0 + x1) / 2, top); to(math.max(x0, x1), bottom); to(math.min(x0, x1), bottom); to((x0 + x1) / 2, top)
    elseif kind == "line" then
        to(x0, y0); to(x1, y1)
    elseif kind == "arrow" then
        local dx, dy = x1 - x0, y1 - y0
        local len = math.sqrt(dx * dx + dy * dy)
        to(x0, y0); to(x1, y1)
        if len > 0 then
            -- the head: two barbs back from the tip, the line retraced between them
            local h = math.max(8, math.min(len * 0.3, 40))
            local ux, uy = dx / len, dy / len
            local bx, by = x1 - ux * h, y1 - uy * h
            to(bx - uy * h * 0.5, by + ux * h * 0.5); to(x1, y1); to(bx + uy * h * 0.5, by - ux * h * 0.5)
        end
    end
    return pts
end

--- The outline in canvas points, from two screen points, kept on the paper.
function Sketch:shapePoints(kind, sx0, sy0, sx1, sy1)
    local page = self:pageRect()
    local function at(x, y)
        local cx, cy = x - self.canvas.x, y - self.canvas.y
        if page then
            cx = math.max(page.x, math.min(page.x + page.w, cx))
            cy = math.max(page.y, math.min(page.y + page.h, cy))
        end
        return cx, cy
    end
    local x0, y0 = at(sx0, sy0)
    local x1, y1 = at(sx1, sy1)
    local pts = Sketch.outline(kind, x0, y0, x1, y1)
    -- (points a stroke keeps are whole pixels apart at least: corners stay corners)
    for _i, p in ipairs(pts) do p[1], p[2] = math.floor(p[1] + 0.5), math.floor(p[2] + 0.5) end
    return pts
end

-- ------------------------------------------------------------------ tools

function Sketch:setWidth(w) self.width = w; self.tool = "pen" end

--- The pen's colours: memos' ink, then its drawing editor's seven hues
--- (web/src/components/DrawingSheet/useCanvasTheme.ts), so a stroke drawn
--- here is one of the colours Memos offers.
Sketch.COLORS = {
    { id = "ink", value = Drawing.INK }, { id = "gray", value = "#868e96" }, { id = "red", value = "#e03131" },
    { id = "orange", value = "#f08c00" }, { id = "green", value = "#2f9e44" }, { id = "teal", value = "#0c8599" },
    { id = "blue", value = "#1971c2" }, { id = "violet", value = "#7048e8" },
}

--- A stroke's colour as kept here: "#rrggbb" in lower case, or nil for memos' ink (and for anything that isn't a colour).
function Sketch.inkColor(c)
    if type(c) ~= "string" then return nil end
    c = c:lower()
    if not c:match("^#%x%x%x%x%x%x$") or c == Drawing.INK then return nil end
    return c
end

function Sketch:setColor(c) self.color = Sketch.inkColor(c); self.tool = "pen" end
function Sketch:setTool(tool)
    self.tool = tool
    if tool ~= "lasso" then self.selection = nil end
end

-- ------------------------------------------------------------------ the lasso

--- The frame around the chosen strokes ({ x0, y0, x1, y1 }, canvas pixels), or nil.
function Sketch:selectionBox()
    local sel = self.selection
    if not sel then return nil end
    local b = self:strokesArea(sel.strokes)
    -- (a little room around them: the frame's lines aren't on the strokes' own)
    local pad = self.lasso_pad or 0
    if b and pad > 0 then b.x0, b.y0, b.x1, b.y1 = b.x0 - pad, b.y0 - pad, b.x1 + pad, b.y1 + pad end
    return b
end

--- Lets go of the chosen strokes. True when some were chosen.
function Sketch:clearSelection()
    if not self.selection then return false end
    self.selection = nil
    return true
end

--- Copies the chosen strokes (for Paste, here or in another drawing). True when there were some.
function Sketch:lassoCopy()
    local sel = self.selection
    if not sel then return false end
    return require("gzreader_lasso").copy(sel.strokes, function(x, y) return self:toScene(x, y) end) ~= nil
end

--- Takes the chosen strokes off the page (Undo brings them back). Returns true and where they were.
function Sketch:lassoDelete()
    local sel = self.selection
    if not sel then return false end
    local area = self:strokesArea(sel.strokes)
    for _i, st in ipairs(sel.strokes) do st.gone = true end
    self.history[#self.history + 1] = { kind = "erase", strokes = sel.strokes }
    self.redone = {}
    self.selection = nil
    return true, area
end

--- Copies the chosen strokes and takes them off the page.
function Sketch:lassoCut()
    if not self:lassoCopy() then return false end
    return self:lassoDelete()
end

--- Pastes what was copied, its middle at screen point (x, y): new strokes,
--- chosen (to move into place). Returns true and where they are.
function Sketch:lassoPaste(x, y)
    local Lasso = require("gzreader_lasso")
    local clip = Lasso.clipboard
    if not clip then return false end
    local sx, sy = self:toScene(x - self.canvas.x, y - self.canvas.y)
    local new = Lasso.fromClip(clip, sx, sy, function(px, py) return self:toCanvas(px, py) end)
    if #new == 0 then return false end
    for _i, st in ipairs(new) do self.strokes[#self.strokes + 1] = st end
    self.history[#self.history + 1] = { kind = "add", strokes = new }
    self.redone = {}
    self.selection = { strokes = new }
    return true, self:strokesArea(new)
end

function Sketch:canUndo() return #self.history > 0 end
function Sketch:canRedo() return #(self.redone or {}) > 0 end

--- Does again what the last Undo took back. True when something changed.
function Sketch:redo()
    local h = table.remove(self.redone or {})
    if not h then return false end
    self.selection = nil
    if h.kind == "move" then
        -- (strokes moved or resized with the lasso: where they went)
        require("gzreader_lasso").restore(h.strokes, h.after)
        self.history[#self.history + 1] = h
        return true
    end
    if h.kind == "text" then
        self.text_gone[h.el] = not require("gzreader_drawtext").restore(h.el, h.after) or nil
        self.history[#self.history + 1] = h
        return true
    end
    for _i, el in ipairs(h.texts or {}) do self.text_gone[el] = h.kind == "clear" or nil end
    if h.kind == "add" then
        for _i, st in ipairs(h.strokes) do
            st.gone, st.undone = false, nil
            self.strokes[#self.strokes + 1] = st
        end
    else
        for _i, st in ipairs(h.strokes) do st.gone = true end
    end
    self.history[#self.history + 1] = h
    return true, self:stepArea(h)
end

--- The part of the page an undone or redone step changes: its strokes'
--- (nil for a step with text boxes or the whole page: all of it is drawn again).
function Sketch:stepArea(h)
    if (h.kind ~= "add" and h.kind ~= "erase") or (h.texts and #h.texts > 0) then return nil end
    return self:strokesArea(h.strokes)
end

--- Takes back the last stroke, erase or clear. True when something changed.
function Sketch:undo()
    local h = table.remove(self.history)
    if not h then return false end
    self.redone = self.redone or {}
    self.redone[#self.redone + 1] = h
    self.selection = nil
    if h.kind == "move" then
        require("gzreader_lasso").restore(h.strokes, h.before)
        return true
    end
    if h.kind == "text" then
        self.text_gone[h.el] = not require("gzreader_drawtext").restore(h.el, h.before) or nil
        return true
    end
    for _i, el in ipairs(h.texts or {}) do self.text_gone[el] = nil end
    if h.kind == "add" then
        for _i, st in ipairs(h.strokes) do st.gone = true; st.undone = true end
    else
        for _i, st in ipairs(h.strokes) do st.gone = false end
    end
    -- strokes taken back by an undo go for good (an erase can't bring them back)
    local kept = {}
    for _i, st in ipairs(self.strokes) do if not st.undone then kept[#kept + 1] = st end end
    self.strokes = kept
    return true, self:stepArea(h)
end

--- Clears the page (undo brings it back). True when something changed.
function Sketch:clear()
    local live, texts = self:live(), self:liveTexts()
    if #live == 0 and #texts == 0 then return false end
    for _i, st in ipairs(live) do st.gone = true end
    for _i, el in ipairs(texts) do self.text_gone[el] = true end
    self.history[#self.history + 1] = { kind = "clear", strokes = live, texts = texts }
    self.redone = {}
    return true
end

-- ----------------------------------------------------------------- output

-- undo and redo of a picture put on the page (Sketch:addPicture): around the strokes' own
do
    local strokes_undo, strokes_redo = Sketch.undo, Sketch.redo
    function Sketch:undo()
        local h = self.history[#self.history]
        if h and h.kind == "picture" then
            table.remove(self.history)
            self.redone = self.redone or {}
            self.redone[#self.redone + 1] = h
            dropPicture(self, h.el)
            return true
        end
        return strokes_undo(self)
    end
    function Sketch:redo()
        local h = self.redone and self.redone[#self.redone]
        if h and h.kind == "picture" then
            table.remove(self.redone)
            putPicture(self, h.el)
            self.history[#self.history + 1] = h
            return true
        end
        return strokes_redo(self)
    end
end

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
    local boxes = {}
    for _i, el in ipairs(self.locked) do boxes[#boxes + 1] = el end
    for _i, el in ipairs(self:liveTexts()) do boxes[#boxes + 1] = el end
    for _i, el in ipairs(boxes) do
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
        for _i, el in ipairs(self:liveTexts()) do locked[el] = true end
        scene.elements = Drawing.list()
        for _i, el in ipairs(self.base.elements or {}) do
            if keep[el] or locked[el] then scene.elements[#scene.elements + 1] = el end
        end
        -- (without the last save's pencil layer: its picture isn't carried along)
        if next(self.layer_files) and type(self.base.files) == "table" then
            scene.files = {}
            for id, f in pairs(self.base.files) do if not self.layer_files[id] then scene.files[id] = f end end
        end
    else
        scene = Drawing.newScene(paper)
    end
    for _i, st in ipairs(self:live()) do
        if not st.el then
            local pts = {}
            for j, p in ipairs(st.points) do
                local sx, sy = self:toScene(p[1], p[2])
                pts[j] = { sx, sy, p[3] }
            end
            local style = Sketch.toolStyle(st.kind)
            local el = Drawing.addStroke(scene, pts, { width = math.min(12, st.width * style.scale),
                color = st.color or Drawing.INK, opacity = style.opacity })
            if el and st.kind then el.customData = { gzTool = st.kind } end
        end
    end
    -- text boxes made here: after the strokes (memos draws them on top)
    for _i, el in ipairs(self:liveTexts()) do
        if not self.base_texts[el] then scene.elements[#scene.elements + 1] = el end
    end
    return scene
end

--- A text box dragged by contact `c`: moved, or (its corner) resized; its
--- lines wrap at the new width, and it's never shorter than they are
--- (`text_height(el)`, the drawing screen's measure, in scene units).
function Sketch.dragText(self, c)
    local el, o = c.el, c.orig
    if not (el and o) then return end
    local dx, dy = (c.x - c.x0) / self.per_unit, (c.y - c.y0) / self.per_unit
    local round2 = Drawing.round2
    if c.part == "resize" then
        local DrawText = require("gzreader_drawtext")
        el.width = round2(math.max(DrawText.MIN_WIDTH, o.width + dx))
        local need = self.text_height and self.text_height(el) or 0
        el.height = round2(math.max(need, o.height + dy, (tonumber(el.fontSize) or DrawText.SIZE) * DrawText.LINE_HEIGHT))
    else
        el.x, el.y = round2(o.x + dx), round2(o.y + dy)
    end
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
