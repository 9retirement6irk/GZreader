--[[--
The drawing screen (touch Kindles): a page to draw on, saved as a memos
drawing (`gzreader_drawing.lua`): a PNG named `drawing-…canvas.png` with the
strokes inside, which memos opens as a drawing you can go on editing.

  [✕]  The note's name                                   [Done]
  ┌──┐
  │✎ │  the page, the whole screen under the top bar
  │⌫ │
  │↶ │  the tools down one side (icons): pen (again: its thickness),
  │↷ │  eraser (again: Clear the page), undo, redo, paper, all pages,
  │▤ │  move the toolbar to the other side, hide it
  │▦ │
  └──┘                 ( ◀  2 / 3  ▶  + )

- A pen Kindle (the Scribe) draws with the pen only, and ignores the hand
  while the pen is near (palm rejection); the pen's other end rubs out.
  Its toolbar's pen / finger button switches to drawing with one finger
  (and back), kept for next time. Every other touch Kindle draws with one
  finger. The toolbar's hand moves a zoomed page with the pen (or a finger);
  so do two fingers (on a pen Kindle drawing with the pen, one).
- The screen reads the touch screen's contacts itself while it's on top
  (it stands in for KOReader's gesture detector, which gets them back when
  the screen closes or a dialog covers it): `gzreader_sketch.lua` turns them
  into strokes, and new ink is put straight on the screen with the fastest
  black-and-white refresh (A2). The controls lie over the page: a touch on
  one is a tap, never ink, and ink running under one isn't painted over it.
- Eraser rubs out whole strokes, as memos' eraser does. Undo takes back the
  last stroke, rub-out or Clear; Redo does it again.
- Paper and All pages open their own screens (`gzreader_drawpages.lua`).
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
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
    ox = 0, oy = 0, -- (where its corner is on the screen: not 0, 0 in a pane beside a book)
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
    -- (GZreader/notes/drawings; before 1.35, in the app's settings: gzreader_places)
    local dir = require("gzreader_places").notes("drawings", DataStorage:getSettingsDir() .. "/gzreader-drawings")
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

--- True when `pages` (a note's drawings) has none to show: a new drawing, which asks for its paper.
function DrawScreen.asksPaper(pages)
    for _i, p in ipairs(pages or {}) do if not p.removed then return false end end
    return true
end

--- The paper new pages start on: the last one chosen.
function DrawScreen.lastPaper()
    return G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_paper") or "blank"
end
function DrawScreen.setLastPaper(id)
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_paper", id) end
end

DrawScreen.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/draw/"

-- the strip down the side of the page, as the Kindle Scribe's (icons;
-- `label`: what each does, for logs and tests). Paper and All pages are in
-- the top bar; the side and the pen's shortcut button under More.
DrawScreen.SIDE_TOOLS = {
    { id = "pen", icon = "pen", label = _("Pen") },
    { id = "highlighter", icon = "highlighter", label = _("Highlighter") },
    { id = "shape", icon = "shapes", label = _("Shapes") },
    { id = "text", icon = "text", label = _("Text") },
    { id = "eraser", icon = "eraser", label = _("Eraser") },
    { id = "lasso", icon = "lasso", label = _("Lasso") },
    { id = "hand", icon = "hand", label = _("Move the page") },
    -- (pen Kindles only: draw with the pen, or with a finger; gzreader_draw_with_finger)
    { id = "fingers", icon = "stylus", pen_device = true, label = _("Draw with the pen or a finger") },
    { id = "sep", sep = true, passive = true },
    { id = "undo", icon = "undo", label = _("Undo") },
    { id = "redo", icon = "redo", label = _("Redo") },
    { id = "more", icon = "more", label = _("More") },
}
-- (kept: the tools by id, for callers and tests from before the side strip)
DrawScreen.TOOLS = DrawScreen.SIDE_TOOLS

--- Which side the toolbar is on ("left" or "right"; left-handers want it on the right).
function DrawScreen.side()
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_toolbar_side")
    return v == "right" and "right" or "left"
end
--- A colour screen (Kindle Colorsoft; KOReader's colour rendering on): the pen has colours.
function DrawScreen.hasColor()
    local ok, on = pcall(function() return Screen.isColorEnabled and Screen:isColorEnabled() end)
    return ok and on == true
end

--- The pen's colour new drawings start with (the last one chosen; memos' ink without a colour screen): nil is the ink.
function DrawScreen.lastColor()
    if not DrawScreen.hasColor() then return nil end
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_color")
    for _i, c in ipairs(Sketch.COLORS) do if c.value == v then return Sketch.inkColor(v) end end
    return nil
end

--- Pen pressure and tilt (a Kindle with a pen): on unless turned off in the pen's choices.
function DrawScreen.pressureOn()
    return not (G_reader_settings and G_reader_settings:isFalse("gzreader_drawing_pressure"))
end

--- What the pen has been seen to report, kept between drawings (Sketch.range).
function DrawScreen.loadPenRange()
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_pen_range")
    if type(v) == "table" then
        Sketch.range = { p_seen = tonumber(v.p_seen) or 0, t_seen = tonumber(v.t_seen) or 0, n = tonumber(v.n) or 0 }
    end
    return Sketch.range
end

function DrawScreen.savePenRange(before)
    local r = Sketch.range
    if (r.n or 0) == 0 or not G_reader_settings then return end
    if before and before.p_seen == r.p_seen and before.t_seen == r.t_seen and (before.n or 0) >= Sketch.PRESSURE_SAMPLES then return end
    G_reader_settings:saveSetting("gzreader_pen_range", { p_seen = r.p_seen, t_seen = r.t_seen, n = math.min(r.n, 100000) })
    -- (numbers only: what the pen's range is, for a report)
    Log.info("drawing: pen pressure up to", r.p_seen, "of", Sketch.pressureTop(r), "tilt up to", r.t_seen, "of", Sketch.tiltTop(r), "samples", r.n)
    -- (how the pen is held: its usual lean while drawing, in degrees, to tell where "laid over" should start)
    if (r.lean_n or 0) > 0 then
        Log.info("drawing: pen lean while drawing: average", math.floor(r.lean_sum / r.lean_n + 0.5), "degrees, most", math.floor(r.lean_max + 0.5),
            "; counts as laid over from", Sketch.TILT_FROM, "to", Sketch.TILT_DEGREES)
    end
end

--- The writing tool new drawings start with (the last one chosen: Sketch.TOOL_IDS).
function DrawScreen.lastWriting()
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_writing")
    return Sketch.TOOL_STYLE[v] and v or "pen"
end

--- The pen's shortcut button's tool (Settings → Notes): Sketch.SHORTCUTS, "eraser" by default.
function DrawScreen.shortcut()
    local v = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_shortcut")
    for _i, id in ipairs(Sketch.SHORTCUTS) do if id == v then return v end end
    return "eraser"
end

DrawScreen.WRITING_NAMES = { pen = _("Pen"), pencil = _("Pencil"), fountain = _("Fountain pen"), marker = _("Marker"),
    highlighter = _("Highlighter") }

--- A number setting that must be one of `list` (else `default`).
local function oneOf(key, list, default)
    local v = G_reader_settings and tonumber(G_reader_settings:readSetting(key))
    for _i, w in ipairs(list) do if w == v then return v end end
    return default
end

--- The pen's width new drawings start with (the last one chosen).
function DrawScreen.lastWidth()
    local v = G_reader_settings and tonumber(G_reader_settings:readSetting("gzreader_drawing_width"))
    for _i, w in ipairs(Sketch.WIDTHS) do if w == v then return v end end
    return 2
end

function DrawScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    -- Beside a book (gzreader_splitview), or under a journal entry's prompt
    -- (gzreader_journalscreen, `journal`): the drawing in its part of the screen
    -- (`pane`: { x, y, w, h }), the book or the entry in the rest. Everything here is laid out
    -- and drawn from the pane's own corner; (ox, oy) is where that is on the screen.
    self.ox, self.oy = 0, 0
    if self.pane then
        sw, sh = self.pane.w, self.pane.h
        self.ox, self.oy = self.pane.x, self.pane.y
        self.dimen = Geom:new{ x = self.ox, y = self.oy, w = sw, h = sh }
        self.covers_fullscreen = false -- (the book or the entry is beside it, and is painted)
        self._pane_slots = {}
    end
    -- a pen Kindle (the Scribe): the pen draws and a hand can rest on the screen,
    -- or (the toolbar's pen / finger button) a finger draws, as on the other Kindles
    self.has_pen = Sketch.penDevice(Device)
    self.pen_only = self.has_pen and not (G_reader_settings and G_reader_settings:isTrue("gzreader_draw_with_finger"))
    -- (the Scribe: its display driver's pen mode, for ink that keeps up with the pen; gzreader_penmode)
    self.pen_fast = self.has_pen and require("gzreader_penmode").supported(Device)
    self.top_h = S(52)
    self.bar_h = self.top_h
    self.top_hidden = false -- (folded away by the tab under it)
    self.tool_sz = S(48)
    -- (a pane is half the screen's height when the book is above it: the tools a little smaller, so all of them fit)
    if self.pane then self.tool_sz = DrawScreen.paneToolSize(sh, self.top_h, #DrawScreen.SIDE_TOOLS) end
    -- the page is the whole screen: the top bar lies over it, and folds away (its tab)
    self.canvas = { x = 0, y = 0, w = sw, h = sh }
    -- a new drawing: its name and tags, set from the top bar ({ title, tags, offered })
    if self.meta then
        self.meta.title = self.meta.title or ""
        self.meta.tags = self.meta.tags or {}
    end
    self.pages = self.pages or {}
    if #self.pages == 0 then self.pages[1] = { new = true } end
    self.index = math.max(1, math.min(self.start or 1, #self.pages))
    self.gone = {} -- pages deleted here: { att, removed = true } for those in Memos
    -- (a drawing left unsaved, opened again as a new note: kept under its id until saved)
    local Draft = require("gzreader_drawdraft")
    if not self.journal and Draft.reopened then self.draft_id, Draft.reopened = Draft.reopened, nil end
    self.toolbar_side = DrawScreen.side()
    self.toolbar_hidden = false
    self.flyout = nil -- "pen" (its widths) or "eraser" (Clear page), open beside the toolbar
    self.tool, self.width = "pen", DrawScreen.lastWidth()
    self.writing = DrawScreen.lastWriting()
    -- (the highlighter has a button of its own, and its own width)
    if self.writing == "highlighter" then self.tool, self.writing = "highlighter", "pen" end
    self.hl_width = oneOf("gzreader_drawing_hl_width", Sketch.WIDTHS, 2)
    self.eraser_width = oneOf("gzreader_drawing_eraser_width", Sketch.ERASER_WIDTHS, 4)
    local shape = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_shape")
    self.shape = Sketch.SHAPE_SET[shape or ""] and shape or "square"
    self.has_color = DrawScreen.hasColor()
    -- a Kindle with a pen: its pressure and tilt make the line heavier (a choice in the pen's panel)
    self.pressure_on = DrawScreen.pressureOn()
    -- draw and hold: a rough shape becomes a clean one (on unless turned off in the Shapes panel)
    self.snap_shapes = not (G_reader_settings and G_reader_settings:isFalse("gzreader_drawing_snap"))
    -- the text tool's Write: what's written with it turns into text (gzreader_handwriting.lua)
    self.write_text = G_reader_settings ~= nil and G_reader_settings:isTrue("gzreader_drawing_write_text")
    local was = DrawScreen.loadPenRange()
    self._pen_range_was = { p_seen = was.p_seen, t_seen = was.t_seen, n = was.n }
    self.color = DrawScreen.lastColor()
    local c = self.canvas
    -- what's on the screen (in colour on a colour screen)
    self.canvas_bb = Blitbuffer.new(c.w, c.h, self.has_color and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8)
    self.tint_bb = nil -- the ink's colour at each point (the PNG's ink colours), once a stroke isn't memos' ink
    self.ink_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BB8) -- the ink alone (the PNG's ink)
    self.color_bb = nil -- the pictures under the ink, in colour (the PNG's paper), when there are some
    self.discs = {}
    self.icons = {}
    self:layoutBar()
    -- (numbers only, for a report: how the screen is turned and what the page is drawn on)
    if Log.enabled then
        Log.info("drawing: opened,", #self.pages, "pages,", DrawScreen.screenInfo(Screen, self.canvas_bb, c.w, c.h) .. ",",
            self.pen_fast and "pen mode" or "no pen mode")
    end
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
    if p.scene then
        -- (a page made ready elsewhere: a PDF's page to mark up)
        p.sketch = self:newSketch(p.scene)
        p.scene = nil
        return p.sketch
    end
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

--- Shows page `i` (`first`: while opening; nothing asked of the screen).
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
    self.text_sel = nil -- (a text box chosen on another page)
    sk.canvas = self.canvas
    sk.pen_only = self.pen_only
    sk.holes = self.holes
    sk.pull_zone, sk.pull_distance = self.pull_zone, S(Sketch.PULL_DISTANCE)
    -- (the pen and its width stay as they were from page to page)
    self:syncTool()
    self:fitPane()
    self:repaintCanvas()
    if not first then UIManager:setDirty(self, "ui") end
    if Log.enabled then self:noteMemory(i, first) end
end

-- ---------------------------------------------------------------- numbers for the log
-- (while diagnostic logging is on: how long full redraws take and how much
-- memory Lua holds, so drawing can be tuned on each Kindle; numbers only)

--- At most this many full redraws written one by one while the screen is open (the rest only counted)…
DrawScreen.DIAG_REDRAWS = 5
--- …and this many pages shown.
DrawScreen.DIAG_PAGES = 50
DrawScreen.ROTATIONS = { [0] = "upright", [1] = "clockwise", [2] = "upside down", [3] = "counter-clockwise" }
DrawScreen.BB_TYPES = { "BB4", "BB8", "BB8A", "BBRGB16", "BBRGB24", "BBRGB32" }

--- Seconds, from the monotonic clock (stood in for by the tests).
function DrawScreen.clock()
    local time = require("ui/time")
    return time.to_s(time.now())
end

--- "rotation 0 (upright), canvas BB8 1860x2480": how the screen is turned and
--- what the page is drawn on (a "?" for what `screen` or `bb` can't say).
function DrawScreen.screenInfo(screen, bb, w, h)
    local rot = "?"
    local ok, r = pcall(function() return screen.getRotationMode and screen:getRotationMode() end)
    if ok and type(r) == "number" then rot = r .. (DrawScreen.ROTATIONS[r] and (" (" .. DrawScreen.ROTATIONS[r] .. ")") or "") end
    local kind = "?"
    local okt, t = pcall(function() return bb and bb.getType and bb:getType() end)
    if okt and t ~= nil and t ~= false then
        local n = tonumber(t)
        kind = tostring(n or t)
        for _i, name in ipairs(DrawScreen.BB_TYPES) do
            local okv, v = pcall(function() return Blitbuffer["TYPE_" .. name] end)
            if okv and n and type(v) == "number" and v == n then kind = name; break end
        end
    end
    return string.format("rotation %s, canvas %s %sx%s", rot, kind, tostring(w or "?"), tostring(h or "?"))
end

--- This screen's numbers for the log, made when first needed.
function DrawScreen:diag()
    local d = self._diag
    if not d then
        d = { redraws = 0, redraw_s = 0, redraw_max = 0, pages = 0, mem_max = 0 }
        self._diag = d
    end
    return d
end

--- A full redraw took `seconds` for `strokes` strokes: counted, and the first few written.
function DrawScreen:noteRedraw(seconds, strokes)
    local d = self:diag()
    d.redraws = d.redraws + 1
    d.redraw_s = d.redraw_s + seconds
    if seconds > d.redraw_max then d.redraw_max = seconds end
    if d.redraws > DrawScreen.DIAG_REDRAWS then return end
    local c, sk = self.canvas or {}, self.sketch
    local zoom = ""
    if sk and sk.zoomed and sk.zoom then
        local ok, z = pcall(sk.zoom, sk)
        if ok and type(z) == "number" then zoom = string.format(", zoom %.2fx", z) end
    end
    Log.info(string.format("drawing: full redraw %d: %.0f ms, %d strokes, %s%s%s", d.redraws, seconds * 1000, strokes or 0,
        DrawScreen.screenInfo(Screen, self.canvas_bb, c.w, c.h), zoom,
        d.redraws == DrawScreen.DIAG_REDRAWS and " (the rest only counted)" or ""))
end

--- Page `i` shown: Lua's memory (KB; nothing collected), the session's highest kept, the first few written.
function DrawScreen:noteMemory(i, first)
    local d = self:diag()
    local kb = math.floor(collectgarbage("count") + 0.5)
    if kb > d.mem_max then d.mem_max = kb end
    d.pages = d.pages + 1
    if d.pages > DrawScreen.DIAG_PAGES then return end
    Log.info(string.format("drawing: page %d of %d shown%s, Lua memory %d KB%s", i, #(self.pages or {}), first and " (opening)" or "", kb,
        d.pages == DrawScreen.DIAG_PAGES and " (no more of these lines this time)" or ""))
end

--- The numbers while the screen was open, in one line (nil when there are none).
function DrawScreen:diagSummary()
    local d = self._diag
    if not d then return nil end
    return string.format("drawing: full redraws: %d, %.0f ms in all, longest %.0f ms; pages shown %d; Lua memory at most %d KB",
        d.redraws, d.redraw_s * 1000, d.redraw_max * 1000, d.pages, d.mem_max)
end

--- This page changed (drawn on, rubbed out, its paper).
function DrawScreen:touched()
    self.page.modified = true
    self.page.thumb_stale = true
    self.changed = true
    self:keepSoon()
end

-- ----------------------------------------------- kept as it's drawn (gzreader_drawdraft)

--- Something changed: the drawing written down at the next pause (DrawDraft.PAUSE
--- seconds without a change), at most every DrawDraft.EVERY seconds, and anyway
--- after DrawDraft.LONGEST seconds of drawing without a pause. So a drawing never
--- saved (GZreader stopped, the battery ran out) comes back at the next start.
function DrawScreen:keepSoon(now, at_least)
    local Draft = require("gzreader_drawdraft")
    now = now or os.time()
    self._keep_since = self._keep_since or now
    if not self._keep_task then
        self._keep_task = function()
            if self._closed then self._keep_planned = nil; return end
            -- (the pen on the page, or moved a moment ago: about to write. Later.)
            local wait = self:keepWait()
            if wait then
                UIManager:scheduleIn(wait, self._keep_task)
                return
            end
            self._keep_planned = nil
            self:keepNow(nil, true)
        end
    end
    local wait = math.max(Draft.PAUSE, at_least or 0)
    if self._kept_at then wait = math.max(wait, Draft.EVERY - (now - self._kept_at)) end
    -- (drawing on and on: not pushed back past LONGEST from the first change)
    if self._keep_planned and now - self._keep_since >= Draft.LONGEST then return end
    UIManager:unschedule(self._keep_task)
    UIManager:scheduleIn(math.max(0, wait), self._keep_task)
    self._keep_planned = now + wait
end

--- Every page as Memos' scene, for the copy kept as it's drawn.
function DrawScreen:keptPages()
    local out = {}
    for _i, p in ipairs(self.pages or {}) do
        local scene
        if p.sketch then
            scene = p.sketch:scene()
        elseif p.scene then
            scene = p.scene
        else
            local file = p.path or (p.att and require("gzreader_memos").filePath(p.att))
            scene = file and Drawing.readFile(file)
        end
        if scene then out[#out + 1] = scene end
    end
    return out
end

--- Not yet (seconds to wait), or nil: the pen (or a finger) is on the page, or
--- moved less than Draft.QUIET seconds ago (hovering counts: about to write).
--- After Draft.LONGEST seconds of drawing on and on, only between strokes.
function DrawScreen:keepWait(now)
    local Draft = require("gzreader_drawdraft")
    local sk = self.sketch
    if sk and next(sk.contacts or {}) ~= nil then return Draft.RETRY end
    local time = require("ui/time")
    now = now or time.now()
    local long = self._keep_since and os.time() - self._keep_since >= Draft.LONGEST
    if self._input_at and not long then
        local since = time.to_s(now - self._input_at)
        if since < Draft.QUIET then return math.max(0.2, Draft.QUIET - since) end
    end
    return nil
end

--- The record kept for this drawing (every page, as Memos' scene; a journal entry's state).
function DrawScreen:keptRecord()
    local Draft = require("gzreader_drawdraft")
    local under = self.journal and self.journal.under
    return { kind = under and "journal" or "note", title = self.meta and self.meta.title or nil,
        pages = self:keptPages(), journal = under and { state = Draft.entryState(under.state) } or nil }
end

--- The drawing written down (see keepSoon). `later`: in a background process,
--- so the pen isn't held up (Draft.writeLater); else now, here (going to sleep,
--- back to the journal entry). true when it was (or is on its way).
function DrawScreen:keepNow(why, later)
    if self._keep_task then UIManager:unschedule(self._keep_task) end
    self._keep_planned, self._keep_since = nil, nil
    if not self.changed then return false end
    local Draft = require("gzreader_drawdraft")
    local under = self.journal and self.journal.under
    -- (its own file: a journal entry's stays the entry's, every time its drawing opens)
    if not self.draft_id then
        self.draft_id = (under and under.draft_id) or Draft.newId()
        if under then under.draft_id = self.draft_id end
    end
    self._kept_at = os.time()
    if later then
        Draft.writeLater(self.draft_id, function() return self:keptRecord() end, function(ok, n, pages, took)
            if ok then
                Log.info(string.format("drawing: a copy kept (%s, in the background), %d page(s), %d bytes, about %d s",
                    why or "a pause", pages or 0, n or 0, took or 0))
            elseif n == "busy" then
                -- (another background job: again shortly, still between strokes)
                if not self._closed then self:keepSoon(nil, Draft.RETRY * 5) end
            elseif n ~= "stale" then
                Log.warn("drawing: couldn't keep a copy:", tostring(n))
            end
        end)
        return true
    end
    local t0 = os.clock()
    local ok, rec = pcall(self.keptRecord, self)
    if not ok then Log.warn("drawing: couldn't keep a copy:", tostring(rec)); return false end
    local wrote, n = Draft.write(self.draft_id, rec)
    if not wrote then Log.warn("drawing: couldn't keep a copy:", tostring(n)); return false end
    Log.info(string.format("drawing: a copy kept (%s), %d page(s), %d bytes, %.2f s", why or "a pause",
        #rec.pages, n or 0, os.clock() - t0))
    return true
end

--- The Kindle going to sleep: what's drawn is written down first.
function DrawScreen:onSuspend()
    if self._keep_planned then self:keepNow("going to sleep") end
end

-- ------------------------------------------------------------- the controls

DrawScreen.WIDTH_NAMES = { _("Fine"), _("Thin"), _("Medium"), _("Thick"), _("Heavy") }
DrawScreen.SHAPE_NAMES = { square = _("Square"), circle = _("Circle"), triangle = _("Triangle"), line = _("Line"), arrow = _("Arrow") }

--- The tool in hand as the sketch needs it: the highlighter is a writing
--- tool with a width of its own; a shape is drawn in the pen's ink.
function DrawScreen:syncTool()
    local sk = self.sketch
    if not sk then return end
    local hl = self.tool == "highlighter"
    -- (the text tool's Write: the pen writes, and it's read as words after a pause)
    local hw = self.tool == "text" and self.write_text == true
    sk.tool = (hl or hw) and "pen" or self.tool
    sk.writing = hl and "highlighter" or hw and "pen" or self.writing
    sk.width = hl and self.hl_width or hw and 2 or self.width
    sk.hw = hw or nil
    sk.color = self.color
    sk.shape = self.shape
    sk.eraser_width = self.eraser_width
    sk.pressure_on = self.pressure_on
    sk.snap_shapes = self.snap_shapes and not hw
    -- the lasso: how near a corner of the frame counts as its handle; another tool lets go of what's chosen
    sk.lasso_handle, sk.lasso_pad = S(26), S(10)
    if self.tool ~= "lasso" then
        self.paste_at = nil
        if sk:clearSelection() then self:layoutBar(); UIManager:setDirty(self, "ui") end
    end
    -- text boxes: their corner handle, and how tall their lines are
    sk.text_handle = S(44)
    sk.text_height = function(el) return self:textHeight(el) end
end

--- The rows of the panel `which` (a list, as the Kindle Scribe's: a name at
--- the left, a picture at the right; the one in use is dark).
function DrawScreen:flyoutRows(which)
    local rows = {}
    if which == "pen" then
        for _i, id in ipairs(Sketch.PEN_IDS) do
            rows[#rows + 1] = { id = "t-" .. id, row = true, writing = id, icon = Sketch.TOOL_STYLE[id].icon, label = DrawScreen.WRITING_NAMES[id] }
        end
        rows[#rows + 1] = { id = "widths", cells = "width" }
        if self.has_color then rows[#rows + 1] = { id = "colors", cells = "color" } end
        if self.has_pen then
            rows[#rows + 1] = { id = "pressure", row = true, switch = self.pressure_on, label = _("Pressure and tilt") }
        end
    elseif which == "highlighter" then
        for k, w in ipairs(Sketch.WIDTHS) do
            rows[#rows + 1] = { id = "hw" .. tostring(w), row = true, hl_width = w, bar = k, label = DrawScreen.WIDTH_NAMES[k] }
        end
    elseif which == "shape" then
        for _i, id in ipairs(Sketch.SHAPES) do
            rows[#rows + 1] = { id = "s-" .. id, row = true, shape = id, icon = id, label = DrawScreen.SHAPE_NAMES[id] }
        end
        -- (or with any pen: draw it roughly and hold the pen still at the end: gzreader_shapesnap.lua)
        rows[#rows + 1] = { id = "snap", row = true, switch = self.snap_shapes, label = _("Draw and hold: clean shapes") }
    elseif which == "text" then
        rows[#rows + 1] = { id = "write-text", row = true, switch = self.write_text == true, label = _("Write by hand: it turns into text") }
        rows[#rows + 1] = { id = "hw-how", row = true, label = T(_("Read: %1"), DrawScreen.hwEngineName(self.plugin)) }
    elseif which == "eraser" then
        for k, w in ipairs(Sketch.ERASER_WIDTHS) do
            rows[#rows + 1] = { id = "e" .. tostring(w), row = true, eraser_width = w, bar = k, hollow = true, label = DrawScreen.WIDTH_NAMES[k] }
        end
        rows[#rows + 1] = { id = "clear", row = true, label = _("Erase page") }
    elseif which == "more" then
        rows[#rows + 1] = { id = "side", row = true, label = self.toolbar_side == "left" and _("Move to right side") or _("Move to left side") }
        if self.has_pen then
            rows[#rows + 1] = { id = "shortcut", row = true,
                label = T(_("Stylus shortcut: %1"), DrawScreen.SHORTCUT_NAMES[DrawScreen.shortcut()] or DrawScreen.shortcut()) }
            -- (the Scribe: the display's own pen mode, on unless turned off here)
            if require("gzreader_penmode").capable(Device) then
                rows[#rows + 1] = { id = "penmode", row = true, switch = self.pen_fast == true, label = _("Fast ink (Kindle pen mode)") }
            end
        end
    elseif which == "options" then
        rows[#rows + 1] = { id = "newpage2", row = true, label = _("New page") }
        if DrawScreen.immich then rows[#rows + 1] = { id = "immich", row = true, label = _("Picture from Immich…") } end
        rows[#rows + 1] = { id = "clear", row = true, label = _("Erase page") }
        if self.sketch and self.sketch.zoomed then rows[#rows + 1] = { id = "whole", row = true, label = _("Whole page") } end
        rows[#rows + 1] = { id = "cancel", row = true, label = _("Close without saving") }
        -- (a note that's already there: its archive and delete, as in its own menus)
        if self.note_actions then
            rows[#rows + 1] = { id = "archive-note", row = true, label = _("Archive note") }
            rows[#rows + 1] = { id = "delete-note", row = true, label = _("Delete note…") }
        end
    elseif which == "tags" then
        local seen = {}
        local function tag(name)
            if seen[name] then return end
            seen[name] = true
            rows[#rows + 1] = { id = "tag-" .. name, row = true, tagname = name, label = "#" .. name }
        end
        for _i, name in ipairs(self.meta and self.meta.tags or {}) do tag(name) end
        for _i, t in ipairs(self.meta and self.meta.offered or {}) do
            if #rows < DrawScreen.TAGS_OFFERED then tag(type(t) == "table" and t.tag or t) end
        end
        rows[#rows + 1] = { id = "newtag", row = true, label = "+ " .. _("New tag") }
    end
    return rows
end
DrawScreen.TAGS_OFFERED = 9
--- Beside what the lasso chose (the Kindle Scribe's: copy, cut; and delete).
DrawScreen.SELECTION_TOOLS = {
    { id = "sel-copy", icon = "copy", label = _("Copy") },
    { id = "sel-cut", icon = "cut", label = _("Cut") },
    { id = "sel-delete", icon = "lasso-delete", label = _("Delete") },
    { id = "sel-text", icon = "text", label = _("To text") },
}
DrawScreen.SHORTCUT_NAMES = { eraser = _("Eraser"), pen = _("Pen"), pencil = _("Pencil"), fountain = _("Fountain pen"),
    marker = _("Marker"), highlighter = _("Highlighter") }

--- Lays out what's over the page, as the Kindle Scribe's notebook: the top
--- bar (Back, the drawing's name, pages, paper, tags, options, Done) with a
--- tab under it that folds it away; the tools down one side under a round
--- button that folds them into one; the page buttons at the bottom; and a
--- panel open beside what was tapped. `self.buttons`: { tool, rect, group }.
--- The top bar's icons, right to left (⋮ first, by Done), as the note editor's
--- (gzreader_notebar.noteIcons): who can see it, its space, a tag, a photo from
--- Immich; then the drawing's own: paper, all pages; a note's Delete and
--- Archive (also in ⋮). What doesn't fit the screen's width is left to ⋮.
function DrawScreen:topIcons()
    local icons = { { id = "options", icon = "more", label = _("Options") } }
    local note = self.note_icons and self.note_icons(self) or nil
    if note then
        local NoteBar = require("gzreader_notebar")
        local list = NoteBar.noteIcons(note)
        for i = #list, 1, -1 do
            local ic = list[i]
            local labels = { photos = _("Picture from Immich…"), tag = _("Tags"), space = _("Space"), visibility = _("Who can see it") }
            icons[#icons + 1] = { id = "note-" .. ic[1], icon = ic[2], label = labels[ic[1]], fn = ic[3] }
        end
        -- (a new drawing: its tags in the panel, as before)
        if self.meta then
            for _i, t in ipairs(icons) do if t.id == "note-tag" then t.id, t.fn = "tag", nil end end
        end
    else
        if self.meta then icons[#icons + 1] = { id = "tag", icon = "tag", label = _("Tags") } end
        if DrawScreen.immich and not self.journal then
            icons[#icons + 1] = { id = "immich", icon = "photos", label = _("Picture from Immich…") }
        end
    end
    icons[#icons + 1] = { id = "paper", icon = "paper", label = _("Paper") }
    icons[#icons + 1] = { id = "pages", icon = "pages", label = _("All pages") }
    if self.note_actions then
        -- (a note that's already there: Archive and Delete in the bar, as an opened note has; also in ⋮)
        icons[#icons + 1] = { id = "delete-note", icon = "trash", label = _("Delete note…") }
        icons[#icons + 1] = { id = "archive-note", icon = "archive", label = _("Archive note") }
    end
    if self.journal then table.insert(icons, 2, { id = "typing", label = _("Aa") }) end -- (back to typing the entry)
    return icons
end

--- The note's space, who can see it or its tags changed (the editor behind): the bar again.
function DrawScreen:barChanged()
    if self._closed then return end
    self:layoutBar()
    UIManager:setDirty(self, "ui")
end

function DrawScreen:layoutBar()
    local sw, sh = self.dimen.w, self.dimen.h
    local ts, pad, gap = self.tool_sz, S(3), S(8)
    self.buttons, self.holes, self.frames = {}, {}, {}
    local function add(tool, x, y, w, h, group)
        local b = { tool = tool, rect = Geom:new{ x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }, group = group }
        self.buttons[#self.buttons + 1] = b
        return b
    end
    -- the top bar, and its tab
    local top = self.top_hidden and 0 or self.top_h
    local tab_w, tab_h = S(64), S(22)
    self.frames.tab = Geom:new{ x = math.floor((sw - tab_w) / 2), y = top == 0 and 0 or top - Size.line.medium, w = tab_w, h = tab_h }
    add({ id = "topfold", icon = self.top_hidden and "down" or "up", small = true,
        label = self.top_hidden and _("Show the top bar") or _("Hide the top bar") },
        self.frames.tab.x, self.frames.tab.y, tab_w, tab_h, "tab")
    local anchors = {}
    if not self.top_hidden then
        self.frames.top = Geom:new{ x = 0, y = 0, w = sw, h = self.top_h }
        local bh = self.top_h - S(8)
        -- (a journal entry's drawing: back to the entry, and Save saves the entry)
        -- (✕ closes, asking Save or Discard when something changed; a journal entry's: ← back to it)
        add({ id = "cancel", icon = self.journal and "back" or "close", label = self.journal and _("Back to the entry") or _("Close") },
            S(4), S(4), bh, bh, "top")
        local done_w = S(84)
        local x = sw - done_w - S(6)
        add({ id = "done", label = self.journal and _("Save") or _("Done") }, x, S(6), done_w, self.top_h - S(12), "top")
        local icons = self:topIcons()
        -- (as many as leave the name room, right to left; the rest are in ⋮)
        local room = require("gzreader_notebar").fit(#icons - 1, x, bh, 0)
        for i, t in ipairs(icons) do
            if i == 1 or i - 1 <= room then
                x = x - bh - S(2)
                anchors[t.id] = add(t, x, S(4), bh, bh, "top")
            end
        end
        -- the drawing's name (a new drawing's: tap to change it)
        local left = S(4) + bh + S(6)
        add({ id = "title", passive = not self.meta, title = true, label = _("Rename") }, left, 0, x - left - S(6), self.top_h, "top")
    end
    -- the tools, under their round button
    local tx = self.toolbar_side == "left" and gap or (sw - gap - ts - 2 * pad)
    local ty = top + tab_h + S(8)
    self.frames.fold = Geom:new{ x = tx + pad, y = ty, w = ts, h = ts }
    if self.toolbar_hidden then
        add({ id = "show", round = true, dark = true, label = _("Show the toolbar") }, tx + pad, ty, ts, ts, "fold")
    else
        add({ id = "hide", icon = "up", round = true, label = _("Hide the toolbar") }, tx + pad, ty, ts, ts, "fold")
        local tools = DrawScreen.SIDE_TOOLS
        local sy = ty + ts + S(8)
        local y = sy + pad
        for _k, t in ipairs(tools) do
          if not t.pen_device or self.has_pen then
            local h = t.sep and S(12) or ts
            anchors[t.id] = add(t, tx + pad, y, ts, h, "toolbar")
            y = y + h
          end
        end
        self.frames.toolbar = Geom:new{ x = tx, y = sy, w = ts + 2 * pad, h = y - sy + pad }
    end
    -- the pages: ◀ 2 / 3 ▶ +
    local lw = S(84)
    local pw = 3 * ts + lw + 2 * pad
    local px, py = math.floor((sw - pw) / 2), sh - ts - 2 * pad - S(10)
    self.frames.pill = Geom:new{ x = px, y = py, w = pw, h = ts + 2 * pad }
    add({ id = "prev", icon = "left", label = _("Previous page") }, px + pad, py + pad, ts, ts, "pill")
    add({ id = "page", passive = true }, px + pad + ts, py + pad, lw, ts, "pill")
    add({ id = "next", icon = "right", label = _("Next page") }, px + pad + ts + lw, py + pad, ts, ts, "pill")
    add({ id = "newpage", icon = "plus", label = _("New page") }, px + pad + 2 * ts + lw, py + pad, ts, ts, "pill")
    -- a panel: beside the tool tapped, or under the top bar's button
    local anchor = self.flyout and anchors[DrawScreen.FLYOUT_ANCHOR[self.flyout] or self.flyout]
    if anchor then
        local rows = self:flyoutRows(self.flyout)
        local rh = S(44)
        local fw = math.min(sw - 2 * gap, S(280))
        if self.flyout == "pen" then
            fw = math.max(fw, #Sketch.WIDTHS * (ts + S(6)) + S(18), self.has_color and (#Sketch.COLORS * (ts + S(6)) + S(18)) or 0)
        end
        local fh = 0
        for _i, r in ipairs(rows) do fh = fh + (r.cells and (ts + S(10)) or rh) end
        fh = fh + 2 * pad
        local fx, fy
        if anchor.group == "top" then
            fx, fy = math.min(sw - gap - fw, math.max(gap, anchor.rect.x + anchor.rect.w - fw)), self.top_h + S(4)
        else
            fx = self.toolbar_side == "left" and (anchor.rect.x + anchor.rect.w + pad + S(2)) or (anchor.rect.x - pad - S(2) - fw)
            fy = math.max(top + S(4), math.min(anchor.rect.y, sh - fh - gap))
        end
        self.frames.flyout = Geom:new{ x = fx, y = fy, w = fw, h = fh }
        local y = fy + pad
        for _i, r in ipairs(rows) do
            if r.cells == "width" then
                for k, w in ipairs(Sketch.WIDTHS) do
                    add({ id = "w" .. tostring(w), width = w, label = DrawScreen.WIDTH_NAMES[k] }, fx + S(9) + (k - 1) * (ts + S(6)), y + S(5), ts, ts, "flyout")
                end
                y = y + ts + S(10)
            elseif r.cells == "color" then
                for k, col in ipairs(Sketch.COLORS) do
                    add({ id = "c-" .. col.id, color = col.value, label = col.id }, fx + S(9) + (k - 1) * (ts + S(6)), y + S(5), ts, ts, "flyout")
                end
                y = y + ts + S(10)
            else
                add(r, fx + pad, y, fw - 2 * pad, rh, "flyout")
                y = y + rh
            end
        end
    else
        self.flyout = nil
    end
    -- the lasso: Copy, Cut, Delete, To text beside what's chosen (not while it's being dragged); Paste where an empty place was tapped
    local sk0 = self.sketch
    local box = sk0 and sk0.selection and not sk0.selection.preview and sk0:selectionBox()
    if box then
        local cv = self.canvas
        local bs = S(44)
        local mw, mh = bs + 2 * pad, #DrawScreen.SELECTION_TOOLS * bs + 2 * pad
        local mx = cv.x + box.x0 - mw - S(14)
        local tools = self.frames.toolbar or self.frames.fold
        local blocked = self.toolbar_side == "left" and tools and mx < tools.x + tools.w + S(6)
        if mx < gap or blocked then mx = cv.x + box.x1 + S(14) end
        mx = math.max(gap, math.min(sw - mw - gap, mx))
        local my = math.max(top + tab_h + S(4), math.min(sh - mh - gap, cv.y + box.y0))
        self.frames.selmenu = Geom:new{ x = math.floor(mx), y = math.floor(my), w = mw, h = mh }
        for k, t in ipairs(DrawScreen.SELECTION_TOOLS) do
            add(t, mx + pad, my + pad + (k - 1) * bs, bs, bs, "selection")
        end
    end
    if self.paste_at and not box then
        local qw, qh = S(120), S(52)
        local qx = math.max(gap, math.min(sw - qw - gap, self.paste_at.x - qw / 2))
        local qy = math.max(top + tab_h + S(4), math.min(sh - qh - gap, self.paste_at.y - qh - S(12)))
        self.frames.paste = Geom:new{ x = math.floor(qx), y = math.floor(qy), w = qw, h = qh }
        add({ id = "paste", label = _("Paste") }, qx + pad, qy + pad, qw - 2 * pad, qh - 2 * pad, "selection")
    end
    for _k, r in pairs(self.frames) do self.holes[#self.holes + 1] = r end
    -- a pull down from the top bar (or, folded away, the top edge) opens the quick panel
    self.pull_zone = top > 0 and top or DrawScreen.EDGE()
    if self.sketch then self.sketch.holes, self.sketch.pull_zone = self.holes, self.pull_zone end
end
--- The strip along the top edge a pull down starts in while the top bar is folded away.
DrawScreen.EDGE = function() return S(24) end
--- (a panel opens at the button of the same name; these at another's)
DrawScreen.FLYOUT_ANCHOR = { tags = "tag" }

function DrawScreen:selected(t)
    if t.writing then return self.tool == "pen" and self.writing == t.writing end
    if t.width then return self.tool ~= "highlighter" and self.width == t.width end
    if t.hl_width then return self.hl_width == t.hl_width end
    if t.shape then return self.tool == "shape" and self.shape == t.shape end
    if t.eraser_width then return self.eraser_width == t.eraser_width end
    if t.color then return Sketch.inkColor(t.color) == self.color end
    if t.tagname then
        for _i, name in ipairs(self.meta and self.meta.tags or {}) do if name == t.tagname then return true end end
        return false
    end
    if t.id == "pen" or t.id == "highlighter" or t.id == "shape" or t.id == "eraser" or t.id == "text" or t.id == "hand" or t.id == "lasso" then return self.tool == t.id end
    if t.id == "fingers" then return not self.pen_only end
    if t.id == "more" or t.id == "options" then return self.flyout == t.id end
    if t.id == "tag" then return self.flyout == "tags" end
    return false
end

function DrawScreen:enabled(t)
    if t.id == "undo" then return self.sketch:canUndo() end
    if t.id == "redo" then return self.sketch:canRedo() end
    if t.id == "clear" then return #self.sketch:live() > 0 or #self.sketch:liveTexts() > 0 end
    if t.id == "prev" then return self.index > 1 end
    if t.id == "next" then return self.index < #self.pages end
    return true
end

--- A button's text (the page number).
function DrawScreen:label(t)
    if t.id == "page" then return self.index .. " / " .. #self.pages end
    return t.label
end

--- The drawing's name in the top bar (a new drawing's: yours, once given), and what draws under it.
function DrawScreen:heading()
    if self.meta then return self.meta.title ~= "" and self.meta.title or _("Untitled drawing") end
    return self.title and self.title ~= "" and self.title or _("Drawing")
end
function DrawScreen:hint()
    local paper = Notepaper.get(self.sketch:paper())
    local on = paper and paper.id ~= "blank" and paper.label or nil
    -- zoomed (pinch): how much, and how back
    if self.sketch.zoomed then
        return string.format("%.1f\u{00D7}", self.sketch:zoom()) .. " \u{00B7} " .. _("pinch in for the whole page")
    end
    if self.meta and #self.meta.tags > 0 then
        local out = {}
        for i, name in ipairs(self.meta.tags) do out[i] = "#" .. name end
        return table.concat(out, " ")
    end
    if self.tool == "lasso" and self.sketch.selection then
        return _("Drag inside the frame to move, a corner to resize; tap elsewhere when it's in place")
    end
    if self.tool == "text" and self.write_text then
        return self.pen_only and _("Write with the pen: each word turns into text when you lift it")
            or _("Write with your finger: each word turns into text when you lift it")
    end
    if self.tool == "text" then
        return self.text_sel and _("Drag the box to move it, its corner to resize it; tap it to change its words")
            or _("Tap where a text box goes; tap a box to choose it")
    end
    local how = self.pen_only and _("Draw with the pen; your hand can rest on the screen") or _("Draw with one finger")
    return on and (how .. " \u{00B7} " .. on) or how
end

--- An icon, drawn once and kept (`dim`: for a button that does nothing now).
function DrawScreen:icon(name, size, dim)
    local key = name .. ":" .. size .. (dim and ":dim" or "")
    if not self.icons[key] then
        local IconWidget = require("ui/widget/iconwidget")
        local file = name == "close" and (DrawScreen.ICON_DIR .. "../panel/close.svg") or (DrawScreen.ICON_DIR .. name .. ".svg")
        self.icons[key] = IconWidget:new{ file = file, width = size, height = size, alpha = true, dim = dim or nil }
    end
    return self.icons[key]
end

local function textAt(bb, x, y, w, h, text, size, bold, color, left)
    local tw = TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = bold, fgcolor = color or Blitbuffer.COLOR_BLACK,
        max_width = w }
    local sz = tw:getSize()
    tw:paintTo(bb, x + (left and 0 or math.floor((w - sz.w) / 2)), y + math.floor((h - sz.h) / 2))
    tw:free()
    return sz.w
end

--- The picture of the tool in hand (the toolbar's buttons, and the round one when they're folded away).
function DrawScreen:toolIcon(id)
    if id == "pen" then return Sketch.toolStyle(self.writing).icon end
    if id == "fingers" then return self.pen_only and "stylus" or "finger" end
    if id == "shape" then return self.shape or "shapes" end
    return id == "highlighter" and "highlighter" or id == "eraser" and "eraser" or id
end

function DrawScreen:paintButton(bb, x, y, b)
    local t, r = b.tool, b.rect
    local sel, on = self:selected(t), self:enabled(t)
    local bx, by = x + r.x, y + r.y
    if t.sep then
        bb:paintRect(bx + S(6), by + math.floor(r.h / 2), r.w - S(12), Size.line.medium, Blitbuffer.COLOR_BLACK)
    elseif t.title then
        -- the name, and under it the hint (or the tags); a pencil after a name that can be changed
        local w = textAt(bb, bx, by + S(4), r.w - (self.meta and S(26) or 0), S(24), self:heading(), 17, true, nil, true)
        if self.meta then self:icon("edit", S(16)):paintTo(bb, bx + w + S(8), by + S(8)) end
        textAt(bb, bx, by + S(27), r.w, S(20), self:hint(), 12, false, Blitbuffer.COLOR_DARK_GRAY, true)
    elseif t.row then
        -- a panel's row: its name, and at the right a picture, a line as thick, or a switch
        textAt(bb, bx + S(12), by, r.w - S(70), r.h, self:label(t), 16, false, on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, true)
        local rx = bx + r.w - S(12)
        if t.icon then
            local isz = S(22)
            self:icon(t.icon, isz):paintTo(bb, rx - isz, by + math.floor((r.h - isz) / 2))
        elseif t.bar then
            local h = S(2) + t.bar * S(4)
            local w = S(56)
            if t.hollow then
                bb:paintBorder(rx - w, by + math.floor((r.h - h) / 2), w, h, Size.border.thin, Blitbuffer.COLOR_BLACK, math.floor(h / 2))
            else
                bb:paintRoundedRect(rx - w, by + math.floor((r.h - h) / 2), w, h, Blitbuffer.COLOR_GRAY_9, math.floor(h / 2))
            end
        elseif t.switch ~= nil then
            local w, h = S(40), S(22)
            local sx, sy = rx - w, by + math.floor((r.h - h) / 2)
            bb:paintRoundedRect(sx, sy, w, h, t.switch and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE, math.floor(h / 2))
            bb:paintBorder(sx, sy, w, h, Size.border.thin, Blitbuffer.COLOR_BLACK, math.floor(h / 2))
            local d = h - S(6)
            bb:paintRoundedRect(t.switch and (sx + w - d - S(3)) or (sx + S(3)), sy + S(3), d, d,
                t.switch and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK, math.floor(d / 2))
        elseif t.tagname and sel then
            textAt(bb, rx - S(24), by, S(24), r.h, "\u{2713}", 16, true)
        end
        if sel and not t.tagname then bb:invertRect(bx, by, r.w, r.h) end
    elseif t.round then
        -- the toolbar's round button: a ring; the tools folded away: dark, the tool in hand on it
        local rad = math.floor(r.w / 2)
        if t.dark then
            local isz = math.floor(r.h * 0.5)
            bb:paintRoundedRect(bx, by, r.w, r.h, Blitbuffer.COLOR_WHITE, rad)
            self:icon(self:toolIcon(self.tool), isz):paintTo(bb, bx + math.floor((r.w - isz) / 2), by + math.floor((r.h - isz) / 2))
            -- (dark, and round: inverted a row at a time)
            for dy = 0, r.h - 1 do
                local off = dy + 0.5 - rad
                local dx = math.floor(math.sqrt(math.max(0, rad * rad - off * off)))
                if dx > 0 then bb:invertRect(bx + rad - dx, by + dy, 2 * dx, 1) end
            end
        else
            local isz = math.floor(r.h * 0.5)
            self:icon(t.icon, isz):paintTo(bb, bx + math.floor((r.w - isz) / 2), by + math.floor((r.h - isz) / 2))
        end
    elseif t.icon then
        local isz = t.small and math.floor(r.h * 0.9) or math.floor(r.h * 0.56)
        -- (the toolbar's pen shows the writing tool in hand; Shapes, the shape)
        local icon = (t.id == "pen" or t.id == "shape" or t.id == "fingers") and self:toolIcon(t.id) or t.icon
        self:icon(icon, isz, not on):paintTo(bb, bx + math.floor((r.w - isz) / 2), by + math.floor((r.h - isz) / 2))
        if t.id == "pen" then
            -- the pen's width, as a dot in the corner
            local d = math.max(2, math.min(S(9), self.sketch:radius(self.width)))
            if sel then bb:invertRect(bx + S(2), by + S(2), r.w - S(4), r.h - S(4)) end
            if self.color then
                -- (its colour too: a square, drawn after the button is inverted)
                local q = math.max(d, S(5))
                bb:paintRectRGB32(bx + r.w - S(8) - 2 * q, by + r.h - S(8) - 2 * q, 2 * q, 2 * q, DrawScreen.rgb32(self.color))
            else
                bb:paintRoundedRect(bx + r.w - S(8) - d, by + r.h - S(8) - d, 2 * d, 2 * d,
                    sel and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK, d)
            end
        elseif sel then bb:invertRect(bx + S(2), by + S(2), r.w - S(4), r.h - S(4)) end
    elseif t.color then
        -- a colour: a filled square; the one in use has a thick frame around it
        local m = sel and S(7) or S(4)
        bb:paintRectRGB32(bx + m, by + m, r.w - 2 * m, r.h - 2 * m, DrawScreen.rgb32(t.color))
        if sel then bb:paintBorder(bx, by, r.w, r.h, Size.border.thick, Blitbuffer.COLOR_BLACK, S(6)) end
    elseif t.width then
        -- a thickness: a short line as thick as the pen draws it
        local h = math.max(2, 2 * self.sketch:radius(t.width) + 1)
        local w = math.floor(r.w * 0.6)
        bb:paintRoundedRect(bx + math.floor((r.w - w) / 2), by + math.floor((r.h - h) / 2), w, h, Blitbuffer.COLOR_BLACK, math.floor(h / 2))
        if sel then bb:invertRect(bx, by, r.w, r.h) end
    elseif t.passive then
        textAt(bb, bx, by, r.w, r.h, self:label(t), 16, true)
    else
        local primary = t.id == "done"
        bb:paintBorder(bx, by, r.w, r.h, primary and Size.border.thick or Size.border.thin, Blitbuffer.COLOR_BLACK, S(6))
        textAt(bb, bx + S(4), by, r.w - S(8), r.h, self:label(t), 16, primary, on and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY)
    end
end

--- The top bar, the toolbar, the page buttons and an open panel, over the page.
function DrawScreen:paintBar(bb, x, y)
    local sw = self.dimen.w
    if self.frames.top then
        bb:paintRect(x, y, sw, self.top_h, Blitbuffer.COLOR_WHITE)
        bb:paintRect(x, y + self.top_h - Size.line.medium, sw, Size.line.medium, Blitbuffer.COLOR_BLACK)
    end
    local function frame(name)
        local f = self.frames[name]
        if not f then return end
        local radius = (name == "pill" or name == "fold") and math.floor(f.h / 2) or name == "flyout" and 0 or S(8)
        bb:paintRoundedRect(x + f.x, y + f.y, f.w, f.h, Blitbuffer.COLOR_WHITE, radius)
        bb:paintBorder(x + f.x, y + f.y, f.w, f.h, Size.border.thin, Blitbuffer.COLOR_BLACK, radius)
    end
    -- (beside a book: a line between the two)
    if self.pane and not self.sticky then
        local t = Size.line.thick
        if self.pane.y > 0 then bb:paintRect(x, y, sw, t, Blitbuffer.COLOR_BLACK) end
        if self.pane.x > 0 then bb:paintRect(x, y, t, self.dimen.h, Blitbuffer.COLOR_BLACK) end
    end
    for _i, name in ipairs({ "tab", "fold", "toolbar", "pill", "selmenu", "paste" }) do frame(name) end
    for _i, b in ipairs(self.buttons) do if b.group ~= "flyout" then self:paintButton(bb, x, y, b) end end
    -- (an open panel over everything else)
    frame("flyout")
    for _i, b in ipairs(self.buttons) do if b.group == "flyout" then self:paintButton(bb, x, y, b) end end
end

function DrawScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = self.canvas
    bb:blitFrom(self.canvas_bb, x + c.x, y + c.y, 0, 0, c.w, c.h)
    self:paintSelection(bb, x + c.x, y + c.y)
    self:paintLasso(bb, x + c.x, y + c.y)
    self:paintShapePreview(bb, x + c.x, y + c.y)
    self:paintBar(bb, x, y)
    if self.sticky then
        -- (the quick note's drawing: a sticky note of its own, framed, over what's around it)
        bb:paintBorder(x, y, self.dimen.w, self.dimen.h, Size.border.thick, Blitbuffer.COLOR_BLACK)
    end
    self._shown = { undo = self.sketch:canUndo(), redo = self.sketch:canRedo() }
end

-- ---------------------------------------------------------------- the ink

function DrawScreen:disc(r)
    if not self.discs[r] then self.discs[r] = Sketch.disc(r) end
    return self.discs[r]
end

--- "#rrggbb" as a colour to paint with.
function DrawScreen.rgb32(hex)
    local r, g, b = DrawScreen.hexRGB(hex)
    return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
end

--- Ink for one segment (screen coordinates; seg[6]: its colour, nil for memos'
--- ink) into the page, and into `screen_bb` too when given. A colour shows
--- on a colour screen (black on the others) and always goes into the PNG.
function DrawScreen:ink(seg, screen_bb)
    local c = self.sketch.canvas
    local r = seg[5]
    local rows = self:disc(r)
    local hex = seg[6]
    if hex and not self.tint_bb then
        -- (the first coloured stroke: everything before it is memos' ink)
        self.tint_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BBRGB24)
        self.tint_bb:fill(DrawScreen.rgb32(Drawing.INK))
    end
    local tint = self.tint_bb and DrawScreen.rgb32(hex or Drawing.INK)
    local shown = hex and self.has_color and DrawScreen.rgb32(hex)
    if seg[7] then return self:inkGray(seg, screen_bb, rows, tint) end
    for _i, p in ipairs(Sketch.stamps(seg[1], seg[2], seg[3], seg[4], r)) do
        -- (ink that runs under the toolbar is on the page, not painted over the toolbar)
        local under = screen_bb and self:underControls(p[1], p[2], r)
        for dy = -r, r do
            local dx = rows[dy]
            local px, py, pw = p[1] - dx - c.x, p[2] + dy - c.y, 2 * dx + 1
            self.ink_bb:paintRect(px, py, pw, 1, Blitbuffer.COLOR_BLACK)
            if tint then self.tint_bb:paintRectRGB32(px, py, pw, 1, tint) end
            if shown then
                self.canvas_bb:paintRectRGB32(px, py, pw, 1, shown)
                if screen_bb and not under then screen_bb:paintRectRGB32(p[1] - dx + self.ox, p[2] + dy + self.oy, pw, 1, shown) end
            else
                self.canvas_bb:paintRect(px, py, pw, 1, Blitbuffer.COLOR_BLACK)
                if screen_bb and not under then screen_bb:paintRect(p[1] - dx + self.ox, p[2] + dy + self.oy, pw, 1, Blitbuffer.COLOR_BLACK) end
            end
        end
    end
end

--- A grey tool's ink (the pencil, the highlighter: seg[7], 0 black … 255
--- paper): painted only where it darkens a pixel, so ink already there (and
--- written over a highlighter later) stays as dark as it was.
--- A grey page's bytes, to read and write its pixels directly (one byte
--- each, a row every `stride` bytes): nil for a page in colour or turned,
--- which goes through Blitbuffer's own getPixel and setPixel. A pencil or
--- highlighter line touches every pixel under it several times; through
--- getPixel each of those made two small objects, thousands a second, and
--- the grey tools drew far slower than the pen (the owner, 2026-11-17).
function DrawScreen.bytes(bb)
    if not bb or bb:getType() ~= Blitbuffer.TYPE_BB8 or bb:getRotation() ~= 0 or bb:getInverse() ~= 0 then return nil end
    return ffi.cast("uint8_t *", bb.data), tonumber(bb.stride)
end

function DrawScreen:inkGray(seg, screen_bb, rows, tint)
    local c = self.sketch.canvas
    local r, gray = seg[5], seg[7]
    -- The pencil: graphite on the paper's tooth (Sketch.grain): only some of the
    -- line's pixels are marked, more of them the harder it's pressed and fewer at
    -- its edges, each darker than the tone the line reads as.
    local grain = seg[8]
    if grain then gray = math.floor(gray * 0.55) end
    local g8 = Blitbuffer.Color8(gray)
    local cw, ch = self.ink_bb:getWidth(), self.ink_bb:getHeight()
    local ink, ink_stride = DrawScreen.bytes(self.ink_bb)
    local page, page_stride = DrawScreen.bytes(self.canvas_bb)
    local scr, scr_stride = DrawScreen.bytes(screen_bb)
    local grainHit = Sketch.grainHit
    local sw, sh = screen_bb and screen_bb:getWidth() or 0, screen_bb and screen_bb:getHeight() or 0
    local function darken(bb, x, y, bw, bh)
        if x < 0 or y < 0 or x >= bw or y >= bh then return end
        if bb:getPixel(x, y):getColor8().a > gray then bb:setPixel(x, y, g8) end
    end
    -- (the pencil's specks hide the scallops of discs set a little further apart: fewer to paint)
    for _i, p in ipairs(Sketch.stamps(seg[1], seg[2], seg[3], seg[4], grain and 1.4 * r or r)) do
        local under = screen_bb and self:underControls(p[1], p[2], r)
        for dy = -r, r do
            local dx = rows[dy]
            local px, py = p[1] - dx - c.x, p[2] + dy - c.y
            for k = 0, 2 * dx do
                -- (the grain goes by the page's pixel: the same wherever the stroke is drawn from)
                local x = px + k
                local hit = not grain or grainHit(x, py, grain, (k - dx) * (k - dx) + dy * dy, r)
                local on_page = hit and x >= 0 and py >= 0 and x < cw and py < ch
                if on_page and ink then
                    local i = py * ink_stride + x
                    if ink[i] > gray then
                        ink[i] = gray
                        if tint then self.tint_bb:setPixel(x, py, tint) end
                    end
                elseif on_page and self.ink_bb:getPixel(x, py):getColor8().a > gray then
                    self.ink_bb:setPixel(x, py, g8)
                    if tint then self.tint_bb:setPixel(x, py, tint) end
                end
                if on_page and page then
                    local i = py * page_stride + x
                    if page[i] > gray then page[i] = gray end
                elseif on_page then
                    darken(self.canvas_bb, x, py, cw, ch)
                end
                if hit and screen_bb and not under then
                    -- On the screen, while the pen moves: black points an e-ink screen shows at once
                    -- (the pencil: all of them; the highlighter: one in four, so it reads as light).
                    -- A refresh that shows greys takes about half a second each time, which made the
                    -- pencil lag far behind the pen (the owner, 2026-11-16). The real grey is on the
                    -- page (canvas_bb) and shows when the stroke ends.
                    local sx, sy = p[1] - dx + k + self.ox, p[2] + dy + self.oy
                    if sx >= 0 and sy >= 0 and sx < sw and sy < sh and (grain or gray < 0x80 or (sx + 2 * sy) % 4 == 0) then
                        if scr then
                            local i = sy * scr_stride + sx
                            if scr[i] > gray then scr[i] = 0 end
                        elseif screen_bb:getPixel(sx, sy):getColor8().a > gray then
                            screen_bb:setPixel(sx, sy, Blitbuffer.COLOR_BLACK)
                        end
                    end
                end
            end
        end
    end
end

--- True when a disc of radius `r` at screen (x, y) touches something laid over the page.
function DrawScreen:underControls(x, y, r)
    for _i, h in ipairs(self.holes or {}) do
        if x + r >= h.x and x - r < h.x + h.w and y + r >= h.y and y - r < h.y + h.h then return true end
    end
    return false
end

local function strokeSegments(sk, st)
    local c, r, out = sk.canvas, sk:radius(st.width), {}
    local pts = st.points
    local gray = Sketch.toolStyle(st.kind).gray
    for i = 1, #pts do
        local a, b = pts[math.max(1, i - 1)], pts[i]
        -- (a stroke with a pen's pressure: as wide as it was pressed, as its tool draws it)
        local w = b[3] and (a[3] and (a[3] + b[3]) / 2 or b[3]) or nil
        local t = b[4] and (a[4] and (a[4] + b[4]) / 2 or b[4]) or nil -- (…and as far as it was laid over)
        local pr = Sketch.toolRadius(st.kind, r, w, t)
        out[#out + 1] = { a[1] + c.x, a[2] + c.y, b[1] + c.x, b[2] + c.y, pr, st.color, gray, Sketch.grainDensity(st.kind, w, t) }
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
                -- (0 x 0: as it is, for a zoomed page's part)
                if w == 0 then return require("ui/renderimage"):renderImageData(data, #data, false) end
                return require("ui/renderimage"):renderImageData(data, #data, false, w, h)
            end)
            if okr and img then
                if w > 0 and (img:getWidth() ~= w or img:getHeight() ~= h) then
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
    if sk.zoomed then return self:paintPicturePart(el, x1, y1, w, h) end
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

--- Zoomed: only the part of picture `el` (w x h at x1, y1 on the canvas)
--- that's on the canvas, scaled from the picture as it is (not the whole
--- picture at the zoomed size: at 4x a page would be tens of MB).
function DrawScreen:paintPicturePart(el, x1, y1, w, h)
    local c = self.canvas
    local src = self:picture(el, 0, 0)
    if not src then return false end
    local iw, ih = src:getWidth(), src:getHeight()
    local dx0, dy0 = math.max(0, x1), math.max(0, y1)
    local dx1, dy1 = math.min(c.w, x1 + w), math.min(c.h, y1 + h)
    if dx1 - dx0 < 1 or dy1 - dy0 < 1 then return true end
    local sx0, sy0 = math.floor((dx0 - x1) * iw / w), math.floor((dy0 - y1) * ih / h)
    local sx1, sy1 = math.ceil((dx1 - x1) * iw / w), math.ceil((dy1 - y1) * ih / h)
    sx1, sy1 = math.min(iw, math.max(sx0 + 1, sx1)), math.min(ih, math.max(sy0 + 1, sy1))
    local view = src:viewport(sx0, sy0, sx1 - sx0, sy1 - sy0)
    local ok, part = pcall(function()
        return require("ui/renderimage"):scaleBlitBuffer(view, dx1 - dx0, dy1 - dy0, false)
    end)
    if not ok or not part then return false end
    self.canvas_bb:blitFrom(part, dx0, dy0, 0, 0, dx1 - dx0, dy1 - dy0)
    if not self.color_bb then
        self.color_bb = Blitbuffer.new(c.w, c.h, Blitbuffer.TYPE_BBRGB24)
        self.color_bb:fill(Blitbuffer.ColorRGB24(DrawScreen.hexRGB(Drawing.PAPER)))
    end
    self.color_bb:blitFrom(part, dx0, dy0, 0, 0, dx1 - dx0, dy1 - dy0)
    part:free()
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
    local t0 = Log.enabled and DrawScreen.clock() or nil -- (for the log)
    self.canvas_bb:fill(Blitbuffer.COLOR_WHITE)
    self.ink_bb:fill(Blitbuffer.COLOR_WHITE)
    if self.color_bb then self.color_bb:free(); self.color_bb = nil end
    if self.tint_bb then self.tint_bb:free(); self.tint_bb = nil end
    -- pictures first (the paper at the bottom), then shapes and text, then the strokes
    local pictures, others = {}, {}
    for _i, el in ipairs(self.sketch.locked) do
        if el.type == "image" then pictures[#pictures + 1] = el else others[#others + 1] = el end
    end
    self:paintLocked(pictures)
    self:paintLocked(others)
    for _i, el in ipairs(self.sketch:liveTexts()) do self:paintText(el) end
    local list = self.sketch:live()
    local cur = self.sketch:current()
    if cur then list[#list + 1] = cur end
    -- (highlighters under the rest: drawn first)
    local under, over = {}, {}
    for _i, st in ipairs(list) do
        if st.kind == "highlighter" then under[#under + 1] = st else over[#over + 1] = st end
    end
    for _i, st in ipairs(over) do under[#under + 1] = st end
    list = under
    for _i, st in ipairs(list) do
        for _j, seg in ipairs(strokeSegments(self.sketch, st)) do self:ink(seg) end
    end
    if t0 then self:noteRedraw(DrawScreen.clock() - t0, #list) end
end

function DrawScreen:redrawAll()
    self:repaintCanvas()
    UIManager:setDirty(self, "ui")
end

--- Only `area` of the page ({ x0, y0, x1, y1 }, canvas pixels) drawn again
--- from what's in it, and only that refreshed: a rubbed-out stroke, an Undo.
--- The whole page was drawn again from every stroke for each, and the whole
--- screen refreshed (the owner, 2026-11-17: "it can be very slow"). Returns
--- false when it can't be done just for a part (zoomed in: the paper is
--- scaled for the view; a shape or text box there): the caller draws it all.
function DrawScreen:repaintArea(area)
    local sk, c = self.sketch, self.canvas
    if not area or sk.zoomed then return false end
    local x0, y0 = math.max(0, area.x0), math.max(0, area.y0)
    local x1, y1 = math.min(c.w, area.x1), math.min(c.h, area.y1)
    local w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0 then return true end
    if w * h > 0.5 * c.w * c.h then return false end -- (most of the page: all of it is as quick)
    local function crosses(ax0, ay0, ax1, ay1) return ax1 > x0 and ax0 < x1 and ay1 > y0 and ay0 < y1 end
    -- (shapes and text made in Memos, text boxes: drawn whole; with one in the area, the whole page)
    local pictures = {}
    for _i, el in ipairs(sk.locked) do
        local ex0, ey0 = sk:toCanvas(tonumber(el.x) or 0, tonumber(el.y) or 0)
        local ex1, ey1 = sk:toCanvas((tonumber(el.x) or 0) + (tonumber(el.width) or 0), (tonumber(el.y) or 0) + (tonumber(el.height) or 0))
        if el.type == "image" then
            pictures[#pictures + 1] = { el = el, x = math.floor(ex0 + 0.5), y = math.floor(ey0 + 0.5),
                w = math.floor(ex1 + 0.5) - math.floor(ex0 + 0.5), h = math.floor(ey1 + 0.5) - math.floor(ey0 + 0.5) }
        elseif crosses(math.min(ex0, ex1) - S(8), math.min(ey0, ey1) - S(8), math.max(ex0, ex1) + S(8), math.max(ey0, ey1) + S(8)) then
            return false
        end
    end
    if #sk:liveTexts() > 0 then
        local DrawText = require("gzreader_drawtext")
        for _i, el in ipairs(sk:liveTexts()) do
            local r = DrawText.rect(el, function(sx, sy) return sk:toCanvas(sx, sy) end)
            if crosses(r.x - S(8), r.y - S(8), r.x + r.w + S(8), r.y + r.h + S(8)) then return false end
        end
    end
    -- the pictures' parts first (their cached pictures at this size; one that can't be had: the whole page)
    local parts = {}
    for _i, p in ipairs(pictures) do
        if p.w >= 2 and p.h >= 2 and crosses(p.x, p.y, p.x + p.w, p.y + p.h) then
            local bb = self:picture(p.el, p.w, p.h)
            if not bb then return false end
            parts[#parts + 1] = { bb = bb, p = p }
        end
    end
    -- the area as an empty page…
    self.canvas_bb:paintRect(x0, y0, w, h, Blitbuffer.COLOR_WHITE)
    self.ink_bb:paintRect(x0, y0, w, h, Blitbuffer.COLOR_WHITE)
    if self.tint_bb then self.tint_bb:paintRectRGB32(x0, y0, w, h, DrawScreen.rgb32(Drawing.INK)) end
    if self.color_bb then self.color_bb:paintRectRGB32(x0, y0, w, h, DrawScreen.rgb32(Drawing.PAPER)) end
    -- …its paper…
    for _i, part in ipairs(parts) do
        local p = part.p
        local dx0, dy0 = math.max(x0, p.x), math.max(y0, p.y)
        local dx1, dy1 = math.min(x1, p.x + p.w), math.min(y1, p.y + p.h)
        if dx1 > dx0 and dy1 > dy0 then
            self.canvas_bb:blitFrom(part.bb, dx0, dy0, dx0 - p.x, dy0 - p.y, dx1 - dx0, dy1 - dy0)
            if self.color_bb then self.color_bb:blitFrom(part.bb, dx0, dy0, dx0 - p.x, dy0 - p.y, dx1 - dx0, dy1 - dy0) end
        end
    end
    -- …and the bits of line that cross it (highlighters under the rest, as on the whole page;
    -- a bit reaching outside paints what's there already again: the same pixels)
    local list = sk:live()
    local cur = sk:current()
    if cur then list[#list + 1] = cur end
    for pass = 1, 2 do
        for _i, st in ipairs(list) do
            if (st.kind == "highlighter") == (pass == 1) then
                local b = sk:strokeBox(st)
                if b and crosses(b.x0, b.y0, b.x1, b.y1) then
                    for _j, seg in ipairs(strokeSegments(sk, st)) do
                        local r = seg[5] + 2
                        if crosses(math.min(seg[1], seg[3]) - c.x - r, math.min(seg[2], seg[4]) - c.y - r,
                            math.max(seg[1], seg[3]) - c.x + r, math.max(seg[2], seg[4]) - c.y + r) then
                            self:ink(seg)
                        end
                    end
                end
            end
        end
    end
    local shown = Geom:new{ x = x0 + c.x + self.ox, y = y0 + c.y + self.oy, w = w, h = h }
    UIManager:setDirty(self, function() return "ui", shown end)
    return true
end

-- --------------------------------------------------------------- the input

--- Takes the touch screen's contacts while this screen is on top.
--- Beside a book: is this input frame the drawing's? It is when any of its
--- contacts began in the pane; a frame of contacts that all began on the
--- book goes to KOReader as usual (a tap or a swipe there turns the page).
--- A contact belongs where it first touched, wherever it goes after.
function DrawScreen:paneFrame(det, tevs)
    local p, slots = self.pane, self._pane_slots
    local ours, lifted = false, {}
    local pen_slot = self.sketch and self.sketch.pen_slot
    local function inPane(tev)
        local x, y = tev.x, tev.y
        if det and det.adjustGesCoordinate then -- (the screen turned: where that is on it)
            local ges = { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
            pcall(det.adjustGesCoordinate, det, ges)
            x, y = ges.pos.x, ges.pos.y
        end
        return x >= p.x and y >= p.y and x < p.x + p.w and y < p.y + p.h
    end
    for _i, tev in ipairs(tevs) do
        local down = tev.id ~= nil and tev.id ~= -1
        if down and slots[tev.slot] == nil and tev.x and tev.y then
            slots[tev.slot] = inPane(tev)
        end
        if slots[tev.slot] then ours = true end
        if pen_slot ~= nil and tev.slot == pen_slot then
            -- (the pen up, hovering or gone: the drawing's while it was last over the pane,
            -- so it knows the pen has left; else a finger was taken for a resting hand
            -- for seconds after writing)
            if not down and slots[tev.slot] == nil then
                if tev.x and tev.y and (tev.x ~= 0 or tev.y ~= 0) then self._pen_over = inPane(tev) end
                if self._pen_over then ours = true end
            elseif down then
                self._pen_over = slots[tev.slot] == true
            end
        end
        if not down then lifted[#lifted + 1] = tev.slot end
    end
    for _i, slot in ipairs(lifted) do slots[slot] = nil end
    return ours
end

--- Beside a book: what the drawing doesn't take (a tap or swipe on the book,
--- a key) goes on to the book under it; under a journal entry's prompt, to the entry.
function DrawScreen:handleEvent(event)
    local handled = InputContainer.handleEvent(self, event)
    if handled or not self.pane or self._closed then return handled end
    if self.sticky then
        -- the quick note's drawing: a tap outside it is ✕ (asks when something was drawn);
        -- nothing goes on to the book or Home under it
        local ges = event.handler == "onGesture" and event.args and event.args[1]
        if ges and ges.ges == "tap" and ges.pos and not ges.pos:intersectWith(self.dimen)
                and UIManager:getTopmostVisibleWidget() == self then
            self:cancel()
        end
        return true
    end
    if self.journal then
        local under = self.journal.under
        if under and UIManager:getTopmostVisibleWidget() == self then return under:handleEvent(event) end
        return handled
    end
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader = ok and ReaderUI and ReaderUI.instance
    if reader and UIManager:getTopmostVisibleWidget() == self then return reader:handleEvent(event) end
    return handled
end

--- The side of a tool's button in a pane `h` tall under a top bar `top`
--- tall, with `count` tools down the side (and the round button above them).
function DrawScreen.paneToolSize(h, top, count)
    local room = h - top - S(22) - S(8) - S(8) - S(12) - S(24)
    return math.max(S(30), math.min(S(48), math.floor(room / (count + 0.4))))
end

--- Beside a book: the paper as wide as the pane (a pane is half the screen:
--- a whole page in it would be a narrow strip), from its top; the rest is
--- reached by moving the page (a finger, or the hand tool).
function DrawScreen:fitPane()
    local sk = self.sketch
    local page = sk and sk:pageRect()
    -- (a journal's drawing is as wide as the screen: the whole page shows, as in the full screen)
    if not (self.pane and page and page.w > 0) or self.journal or self.sticky then return end
    local scale = math.min(Sketch.MAX_ZOOM or 4, self.canvas.w / page.w)
    if scale > 1.02 then sk:zoomBy(scale, page.x, page.y, 0, 0) end
end

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
        -- (beside a book: touches that began on the book are the book's, as KOReader reads them)
        if screen.pane and not screen:paneFrame(det, tevs) then return orig(det, tevs) end
        -- (the pen moved, on the page or hovering: no copy kept for a moment, see keepWait)
        screen._input_at = require("ui/time").now()
        -- (the pen's side button, as KOReader reads it: BTN_STYLUS or BTN_STYLUS2; held, the pen rubs out)
        if screen.sketch then
            local held = input.stylus_eraser_active == true or input.stylus_highlighter_active == true
            if held ~= screen.sketch.side_button then
                Log.info("drawing: the pen's side button", held and ("held (" .. DrawScreen.shortcut() .. ")") or "let go",
                    input.stylus_eraser_active and "BTN_STYLUS" or input.stylus_highlighter_active and "BTN_STYLUS2" or "")
            end
            screen.sketch.side_button = held
            screen.sketch.shortcut = DrawScreen.shortcut()
        end
        local ok, err = pcall(screen.onContacts, screen, det, tevs)
        if not ok then Log.warn("drawing: input:", tostring(err)) end
        screen:stillHere()
        return {}
    end)
    -- A Kindle with a pen: its pressure and tilt from the digitizer itself, when
    -- the device KOReader reads the pen from doesn't pass them on (gzreader_penraw).
    if self.has_pen and not self.penraw then
        local PenRaw = require("gzreader_penraw")
        local raw, why = PenRaw.open()
        self.penraw = raw
        if raw then
            Log.info("drawing: pen pressure and tilt also read from", raw.name, raw.event, "abs", PenRaw.absCaps(raw.event))
        else
            Log.info("drawing: the pen's digitizer not read:", tostring(why))
        end
    end
    if self.pen_fast then
        require("gzreader_penmode").hook(Screen, UIManager)
        Log.info("drawing: the Kindle's pen mode will be used for ink")
    end
    -- (a tap still under way, e.g. the one that opened this screen, is forgotten)
    pcall(gd.dropContacts, gd)
    if input.clearTimeouts then pcall(input.clearTimeouts, input) end
end

--- Drawing keeps the Kindle awake. The touches are the drawing's (KOReader
--- never sees them as gestures), so KOReader's "InputEvent" hook didn't run
--- either, and AutoSuspend (which keeps the Kindle's own sleep timer back and
--- puts it to sleep after its idle time) took a page of drawing for an idle
--- Kindle: it fell asleep while you drew. Told at most once every few seconds.
DrawScreen.AWAKE_EVERY = 5
function DrawScreen:stillHere(now)
    now = now or os.time()
    if self._awake_at and now - self._awake_at < DrawScreen.AWAKE_EVERY then return false end
    self._awake_at = now
    local hook = UIManager.event_hook
    if hook and hook.execute then pcall(hook.execute, hook, "InputEvent") end
    return true
end

function DrawScreen:unhook()
    local gd = self._gd
    if not gd then return end
    rawset(gd, "feedEvent", self._own_feed)
    self._gd = nil
    if self._ink_timer then UIManager:unschedule(self._ink_timer); self._ink_timer = nil end
    if self._settle_timer then UIManager:unschedule(self._settle_timer); self._settle_timer = nil end
    do
        local PenMode = require("gzreader_penmode")
        local st = PenMode.unhook()
        -- (numbers only: how long pen mode's waits were, the long ones already written as they happened)
        if st and Log.enabled then Log.info(PenMode.waitSummary(st)) end
        if st then
            -- (numbers only, for a report: how the pen mode went)
            Log.info(string.format("drawing: pen mode: on %d times, %d runs of ink in %d updates, %d the ordinary way; waited %.0f ms before and %.0f ms after%s",
                st.entered or 0, st.runs or 0, st.updates or 0, self._ink_ordinary or 0, (st.waited_before or 0) * 1000, (st.waited_after or 0) * 1000,
                PenMode.failed and ("; refused: " .. tostring(PenMode.failed)) or ""))
        end
    end
    -- (numbers only: full redraws and Lua's memory while the screen was open)
    if self._diag and Log.enabled then Log.info(self:diagSummary()) end
    if self.penraw then
        -- (numbers only: where the pen's pressure came from, for a report)
        Log.info("drawing: pen pressure from KOReader's events:", self._pressure_events or 0, "frames; from the digitizer:",
            self._pressure_raw or 0, "frames;", self.penraw.state.n or 0, "values read")
        require("gzreader_penraw").close(self.penraw)
        self.penraw = nil
    end
    pcall(gd.dropContacts, gd)
    local input = Device.input
    if input and input.clearTimeouts then pcall(input.clearTimeouts, input) end
end

--- One input frame from KOReader: contacts in screen coordinates, to the sketch.
function DrawScreen:onContacts(det, tevs)
    local time = require("ui/time")
    local slots, now = {}, nil
    -- (the digitizer's latest pressure and tilt, for the pen's slot when KOReader's event has none)
    local raw = self.penraw and require("gzreader_penraw").read(self.penraw)
    local pen_slot = Device.input and Device.input.pen_slot
    for _i, tev in ipairs(tevs) do
        local x, y = tev.x, tev.y
        if x and y then
            local ges = { ges = "tap", pos = Geom:new{ x = x, y = y, w = 0, h = 0 } }
            if det.adjustGesCoordinate then pcall(det.adjustGesCoordinate, det, ges) end
            -- (beside a book: from the pane's own corner)
            x, y = ges.pos.x - self.ox, ges.pos.y - self.oy
        end
        local pressure, tilt_x, tilt_y = tev.gz_pressure, tev.gz_tilt_x, tev.gz_tilt_y
        if pressure ~= nil then
            self._pressure_events = (self._pressure_events or 0) + 1
        elseif raw and raw.pressure ~= nil and pen_slot ~= nil and tev.slot == pen_slot then
            pressure, tilt_x, tilt_y = raw.pressure, tilt_x or raw.tilt_x, tilt_y or raw.tilt_y
            self._pressure_raw = (self._pressure_raw or 0) + 1
        end
        slots[#slots + 1] = { slot = tev.slot, id = tev.id, x = x, y = y, tool = tev.tool,
            pressure = pressure, tilt_x = tilt_x, tilt_y = tilt_y }
        if tev.timev and not now then now = time.to_s(tev.timev) end
    end
    -- How far behind the pen this frame is handled (the pen's samples are stamped by the
    -- kernel on the clock KOReader reads): behind, the ink is shown less often until it has
    -- caught up (DrawScreen.inkInterval).
    local real = time.to_s(time.now())
    self._lag = now and math.max(0, real - now) or 0
    if self._lag > 5 then self._lag = 0 end -- (not the same clock: nothing to go by)
    self._now = real
    now = now or real
    local cpu = os.clock()
    local out = self.sketch:frame(slots, now)
    self:apply(out)
    -- (how long a stroke's frames took to handle, for the long strokes' line in the log)
    local st = self._stroke_stats
    if st then st.cpu = (st.cpu or 0) + os.clock() - cpu end
end

local function intersects(a, x0, y0, x1, y1)
    return x1 >= a.x and x0 < a.x + a.w and y1 >= a.y and y0 < a.y + a.h
end

function DrawScreen:apply(out)
    if out.zoom then
        Log.info(string.format("drawing: zoom %.2fx -> %.2fx", out.zoom.from, out.zoom.to))
    end
    if (out.redraw or #out.segments > 0) and self.flyout then
        -- drawing puts an open panel away
        self.flyout = nil
        self:layoutBar()
        out.redraw = true
        out.area = nil -- (the panel's place too: the whole screen)
    end
    if out.panned then UIManager:setDirty(self, "ui") end
    if out.redraw then
        -- (the view moved, by a pinch or a finger: the page itself is as it was)
        if not out.view then self:touched() end
        -- (a stroke rubbed out: only where it was)
        if out.view or not self:repaintArea(out.area) then self:redrawAll() end
    elseif #out.segments > 0 then
        self:touched()
        local screen_bb = Screen.bb
        local x0, y0, x1, y1
        local grey = false
        -- (ink again before what was left for a pause was done: it waits for the next pause)
        if self._settle_timer then UIManager:unschedule(self._settle_timer); self._settle_timer = nil end
        local c0 = self.canvas
        for _i, seg in ipairs(out.segments) do
            self:ink(seg, screen_bb)
            if self.pen_fast then
                -- (pen mode: each bit of line as a small update of its own; PenMode.split joins them)
                local r = seg[5]
                local sx0 = math.max(c0.x, math.floor(math.min(seg[1], seg[3]) - r) - 1)
                local sy0 = math.max(c0.y, math.floor(math.min(seg[2], seg[4]) - r) - 1)
                local sx1 = math.min(c0.x + c0.w, math.ceil(math.max(seg[1], seg[3]) + r) + 1)
                local sy1 = math.min(c0.y + c0.h, math.ceil(math.max(seg[2], seg[4]) + r) + 1)
                if sx1 > sx0 and sy1 > sy0 then
                    local list = self._pen_rects or {}
                    self._pen_rects = list
                    list[#list + 1] = { x = sx0 + self.ox, y = sy0 + self.oy, w = sx1 - sx0, h = sy1 - sy0 }
                end
            end
            -- (a grey tool without a grain, the highlighter: its real grey needs a refresh when the
            -- stroke ends. The pencil's specks are on the screen already as it draws, as dark as
            -- they'll be: no refresh after, which flashed the page at every stroke; the owner, 2026-11-17)
            if seg[7] and not seg[8] then grey = true end
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
            -- (a grey tool's ink is on the screen as black points for now: the same fast refresh as the pen's)
            self:showInk(x0, y0, x1, y1)
            if grey then self._stroke_grey = true end
            -- (the stroke's area, cleaned up once it's done)
            local d = self._stroke_area
            if d then
                d.x0, d.y0, d.x1, d.y1 = math.min(d.x0, x0), math.min(d.y0, y0), math.max(d.x1, x1), math.max(d.y1, y1)
            else
                self._stroke_area = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
            end
        end
    end
    -- the lasso
    if out.loop then
        -- (its loop as it's drawn: dashes on the screen only, gone when the pen lifts)
        local screen_bb = Screen.bb
        local t = math.max(2, S(3))
        local x0, y0, x1, y1
        for _i, seg in ipairs(out.loop) do
            self._loop_phase = DrawScreen.dashed(screen_bb, seg[1] + self.ox, seg[2] + self.oy, seg[3] + self.ox, seg[4] + self.oy, t, self._loop_phase)
            x0, y0 = math.min(x0 or seg[1], seg[1], seg[3]), math.min(y0 or seg[2], seg[2], seg[4])
            x1, y1 = math.max(x1 or seg[1], seg[1], seg[3]), math.max(y1 or seg[2], seg[2], seg[4])
        end
        self:showInk(math.floor(x0) - 1, math.floor(y0) - 1, math.ceil(x1) + t + 1, math.ceil(y1) + t + 1)
    end
    if out.paste_at then
        self.paste_at = out.paste_at
        self:layoutBar()
        UIManager:setDirty(self, "ui")
    end
    if out.sel_preview then UIManager:setDirty(self, "ui") end
    if out.shape_preview then
        -- (a shape's outline following the pen: black on the page, so the quick refresh, and only where it is and was)
        local a = out.shape_preview
        local c = self.canvas
        local x0, y0 = math.max(c.x, c.x + a.x0 - 1), math.max(c.y, c.y + a.y0 - 1)
        local x1, y1 = math.min(c.x + c.w, c.x + a.x1 + 1), math.min(c.y + c.h, c.y + a.y1 + 1)
        if x1 > x0 and y1 > y0 then
            local region = Geom:new{ x = x0 + (self.ox or 0), y = y0 + (self.oy or 0), w = x1 - x0, h = y1 - y0 }
            self.shape_refreshes = (self.shape_refreshes or 0) + 1
            UIManager:setDirty(self, function() return "fast", region end)
        end
    end
    if out.sel_changed then
        -- (chosen, let go of, moved: the loop goes, the frame and its buttons are where they belong)
        self._loop_phase = nil
        self.paste_at = nil
        self:flushInk()
        self:layoutBar()
        UIManager:setDirty(self, "ui")
        local sel = self.sketch.selection
        Log.info("drawing: lasso,", sel and #sel.strokes or 0, "strokes and", sel and #(sel.pictures or {}) or 0, "pictures chosen")
    end
    if out.stroke_done then self:flushInk(true) end
    if out.stroke_done and self.sketch.hw then self:hwSoon() end
    if out.stroke_done then
        local d = self._stroke_area
        local clean = d and (self._stroke_grey or DrawScreen.inkRefreshFor(self.sketch.locked) ~= "a2")
        -- Undo and Redo wake up or go to sleep
        local shown = self._shown or {}
        local bar = shown.undo ~= self.sketch:canUndo() or shown.redo ~= self.sketch:canRedo()
        if self.pen_fast and require("gzreader_penmode").on then
            -- Pen mode: nothing else may be on its way to the screen while ink is. What a
            -- stroke leaves to do (its area shown properly, a highlighter's grey, Undo waking
            -- up) waits for a pause in the writing (the Kindle's notebook does nothing at
            -- the end of a stroke either), all of it at once.
            local w = self._settle or {}
            self._settle = w
            if clean then
                if w.x0 then
                    w.x0, w.y0, w.x1, w.y1 = math.min(w.x0, d.x0), math.min(w.y0, d.y0), math.max(w.x1, d.x1), math.max(w.y1, d.y1)
                else
                    w.x0, w.y0, w.x1, w.y1 = d.x0, d.y0, d.x1, d.y1
                end
                w.grey = w.grey or self._stroke_grey or false
            end
            w.bar = w.bar or bar
            if w.x0 or w.bar then
                if self._settle_timer then UIManager:unschedule(self._settle_timer) end
                self._settle_timer = function()
                    self._settle_timer = nil
                    if not self._closed then self:settle() end
                end
                UIManager:scheduleIn(DrawScreen.SETTLE, self._settle_timer)
            end
        else
            if clean then self:cleanStroke(d, self._stroke_grey) end
            if bar then self:refreshBar() end
        end
        self._stroke_area, self._stroke_grey = nil, nil
    end
    for _i, tap in ipairs(out.taps) do self:tapAt(tap.x, tap.y) end
    if out.text_tap then self:textTap(out.text_tap) end
    if out.pull then self:pullPanel() end
end

--- A finished stroke's area shown properly: a grey tool's (the highlighter:
--- the page painted again, so its real grey replaces the black points), or
--- ink on a paper (shown with a refresh that keeps the paper's greys).
function DrawScreen:cleanStroke(d, grey)
    local area = Geom:new{ x = d.x0 + self.ox, y = d.y0 + self.oy, w = d.x1 - d.x0, h = d.y1 - d.y0 }
    if grey then
        UIManager:setDirty(self, function() return "ui", area end)
    else
        UIManager:setDirty(nil, "ui", area)
    end
end

--- Pen mode: what the strokes left for a pause in the writing, done now
--- (these are ordinary updates: gzreader_penmode turns pen mode off for them).
function DrawScreen:settle()
    if self._settle then require("gzreader_penmode").settled() end -- (when, for the log)
    local w = self._settle
    self._settle = nil
    if not w then return end
    if w.x0 then self:cleanStroke(w, w.grey) end
    if w.bar then self:refreshBar() end
end
--- Seconds without ink before a stroke's leftovers are done in pen mode.
DrawScreen.SETTLE = 0.5

--- The quick panel over the drawing (a pull down from the top), as at Home
--- and in a book. The drawing stays as it is under it; while the panel is
--- on top it gets the touches (`hook` hands them back to KOReader).
function DrawScreen:pullPanel()
    if not self.plugin then return false end
    if self.flyout then self:setFlyout(nil) end
    Log.info("drawing: the quick panel pulled down")
    require("gzreader_panel").show(self.plugin)
    return true
end

-- ----------------------------------------------------------- text boxes

--- A box's lines as KOReader lays them out: its text at its size, as wide as the box (canvas pixels).
function DrawScreen:textWidget(el)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local sk = self.sketch
    local px = math.max(6, math.floor((tonumber(el.fontSize) or 20) * sk.per_unit))
    local one = Screen:scaleBySize(100) / 100
    return TextBoxWidget:new{ text = el.text ~= "" and el.text or " ", face = Font:getFace("cfont", math.max(6, math.floor(px / one))),
        width = math.max(S(20), math.floor((tonumber(el.width) or 100) * sk.per_unit)), fgcolor = Blitbuffer.COLOR_BLACK }
end

--- How tall a box's lines are, in scene units.
function DrawScreen:textHeight(el)
    local tw = self:textWidget(el)
    local h = tw:getSize().h
    tw:free()
    return h / self.sketch.per_unit
end

--- A box into the page (and the PNG's ink).
function DrawScreen:paintText(el)
    local cx, cy = self.sketch:toCanvas(tonumber(el.x) or 0, tonumber(el.y) or 0)
    local tw = self:textWidget(el)
    tw:paintTo(self.canvas_bb, math.floor(cx), math.floor(cy))
    tw:paintTo(self.ink_bb, math.floor(cx), math.floor(cy))
    tw:free()
end

--- A dashed line from (x0, y0) to (x1, y1) on `bb` (`phase`: where in the dash it starts; returns where it ends).
function DrawScreen.dashed(bb, x0, y0, x1, y1, t, phase)
    local dx, dy = x1 - x0, y1 - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local on, period = S(7), S(13)
    phase = phase or 0
    local n = math.max(1, math.ceil(len / 2))
    for i = 0, n do
        local d = len * i / n
        if (phase + d) % period < on then
            bb:paintRect(math.floor(x0 + dx * i / n), math.floor(y0 + dy * i / n), t, t, Blitbuffer.COLOR_BLACK)
        end
    end
    return (phase + len) % period
end

--- What the lasso chose: a dashed frame with a handle at each corner (where
--- it's being dragged to, while it is). On the screen only, never in the PNG.
--- A shape being dragged out: its outline as it is now, in the pen's width (on the
--- screen only; the shape itself is drawn on the page when the pen lifts).
function DrawScreen:paintShapePreview(bb, x, y)
    local sk = self.sketch
    local p = sk and sk.shape_preview
    if not p or #p.points < 2 then return end
    local c = self.canvas
    local r = Sketch.toolRadius(nil, sk:radius(p.width), nil)
    local rows = self:disc(r)
    for i = 2, #p.points do
        local a, b = p.points[i - 1], p.points[i]
        for _j, q in ipairs(Sketch.stamps(a[1], a[2], b[1], b[2], r)) do
            for dy = -r, r do
                local dx = rows[dy]
                local px, py = q[1] - dx, q[2] + dy
                -- (kept on the page: not over the bars)
                if py >= 0 and py < c.h then
                    local x0, x1 = math.max(0, px), math.min(c.w, px + 2 * dx + 1)
                    if x1 > x0 then bb:paintRect(x + x0, y + py, x1 - x0, 1, Blitbuffer.COLOR_BLACK) end
                end
            end
        end
    end
end

function DrawScreen:paintLasso(bb, x, y)
    local sk = self.sketch
    local sel = sk and sk.selection
    if not sel then return end
    local box = sel.preview or sk:selectionBox()
    if not box then return end
    local t = math.max(2, S(2))
    local x0, y0, x1, y1 = x + math.floor(box.x0), y + math.floor(box.y0), x + math.ceil(box.x1), y + math.ceil(box.y1)
    DrawScreen.dashed(bb, x0, y0, x1, y0, t)
    DrawScreen.dashed(bb, x1, y0, x1, y1, t)
    DrawScreen.dashed(bb, x0, y1, x1, y1, t)
    DrawScreen.dashed(bb, x0, y0, x0, y1, t)
    local hs = S(16)
    for _i, p in ipairs({ { x0, y0 }, { x1, y0 }, { x0, y1 }, { x1, y1 } }) do
        local hx, hy = p[1] - math.floor(hs / 2), p[2] - math.floor(hs / 2)
        bb:paintRect(hx, hy, hs, hs, Blitbuffer.COLOR_BLACK)
        bb:paintRect(hx + t, hy + t, hs - 2 * t, hs - 2 * t, Blitbuffer.COLOR_WHITE)
    end
end

--- The chosen box: a frame around it and its resize handle (on the screen only, never in the PNG).
function DrawScreen:paintSelection(bb, x, y)
    local el = self.text_sel
    if not el or self.sketch.text_gone[el] then return end
    local DrawText = require("gzreader_drawtext")
    local sk = self.sketch
    local r = DrawText.rect(el, function(sx, sy) return sk:toCanvas(sx, sy) end)
    local pad = S(4)
    bb:paintBorder(x + math.floor(r.x) - pad, y + math.floor(r.y) - pad, math.floor(r.w) + 2 * pad, math.floor(r.h) + 2 * pad,
        Size.border.thin, Blitbuffer.COLOR_BLACK, S(4))
    local hs = S(18)
    local hx, hy = x + math.floor(r.x + r.w) - math.floor(hs / 2), y + math.floor(r.y + r.h) - math.floor(hs / 2)
    bb:paintRect(hx, hy, hs, hs, Blitbuffer.COLOR_BLACK)
    bb:paintRect(hx + S(4), hy + S(4), hs - S(8), hs - S(8), Blitbuffer.COLOR_WHITE)
end

--- A tap with the text tool: on the chosen box, its words to change; on
--- another box, that one chosen; elsewhere, a new box there (or, with one
--- chosen, nothing chosen).
function DrawScreen:textTap(t)
    if t.el then
        if t.el == self.text_sel then return self:editText(t.el) end
        self.text_sel = t.el
        UIManager:setDirty(self, "ui")
        return
    end
    if self.text_sel then
        self.text_sel = nil
        UIManager:setDirty(self, "ui")
        return
    end
    return self:newText(t.x, t.y)
end

--- Asks for the words of a box: `text` to start with; on_done(text) or on_delete().
function DrawScreen:askText(title, text, on_done, on_delete, ok_text)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    local row = { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end } }
    if on_delete then
        row[#row + 1] = { text = _("Delete"), callback = function() UIManager:close(d); on_delete() end }
    end
    row[#row + 1] = { text = ok_text or (text == "" and _("Add") or _("Save")), is_enter_default = false, callback = function()
        local v = d:getInputText() or ""
        UIManager:close(d)
        on_done(v)
    end }
    d = InputDialog:new{ title = title, input = text, allow_newline = true, gz_multiline = true, gz_hash_key = true, buttons = { row } }
    self.text_dialog = d
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

--- A new box at canvas point (x, y): its words asked for, then on the page, chosen.
function DrawScreen:newText(x, y)
    local sk = self.sketch
    local c = self.canvas
    return self:askText(_("Text box"), "", function(text)
        if text:gsub("%s", "") == "" then return end
        local DrawText = require("gzreader_drawtext")
        local sx, sy = sk:toScene(x, y)
        local w = math.max(S(120), math.min(c.w * 0.5, c.w - x - S(16))) / sk.per_unit
        local el = DrawText.element(sx, sy, w, text, self.color)
        el.height = Drawing.round2(math.max(el.height, self:textHeight(el)))
        sk:addText(el)
        self.text_sel = el
        self:touched()
        self:redrawAll()
        Log.info("drawing: a text box added")
    end)
end

--- The chosen box's words: changed, or the box deleted.
function DrawScreen:editText(el)
    local sk = self.sketch
    return self:askText(_("Text box"), el.text, function(text)
        if text:gsub("%s", "") == "" then
            sk:removeText(el)
            self.text_sel = nil
        else
            local probe = { text = text, width = el.width, fontSize = el.fontSize }
            sk:changeText(el, { text = text, height = Drawing.round2(math.max(el.height, self:textHeight(probe))) })
        end
        self:touched()
        self:redrawAll()
    end, function()
        sk:removeText(el)
        self.text_sel = nil
        self:touched()
        self:redrawAll()
        Log.info("drawing: a text box deleted")
    end)
end

-- ---------------------------------------------------- handwriting to text

--- How writing is read now, for the text tool's panel.
function DrawScreen.hwEngineName(plugin)
    local e = require("gzreader_handwriting").engine(plugin)
    return e == "claude" and _("with Claude") or e == "openai" and _("online (your service)") or _("on the Kindle")
end

function DrawScreen.hwHow(plugin)
    local e = require("gzreader_handwriting").engine(plugin)
    if e == "kindle" then
        return _("Your writing is read on the Kindle: nothing leaves it, and no Wi-Fi is needed. It reads printed writing best: letters apart, English words and digits.\n\nFor joined-up writing, Claude or another online service reads much better: Settings → Notes → Handwriting to text.")
    end
    return T(_("Your writing is read %1: only the writing being read is sent, as a black-and-white picture, never the page or your other notes. Wi-Fi turns on for it.\n\nSettings → Notes → Handwriting to text changes this."),
        DrawScreen.hwEngineName(plugin))
end

--- The text size (scene units) for writing whose lines are `line_h` canvas pixels high.
function DrawScreen:hwSize(line_h)
    local DrawText = require("gzreader_drawtext")
    local size = math.floor(line_h / self.sketch.per_unit * 0.7 + 0.5)
    return math.max(DrawText.SIZE * 0.8, math.min(48, size))
end

--- `strokes` (live, on this page) read as `text`: they go and the words go
--- in a text box: box `into` (the Write box) when given, at its end (a new
--- line when `newline`), else a new box where the writing was. One undo.
function DrawScreen:placeText(strokes, text, into, newline)
    local sk = self.sketch
    local live = {}
    for _i, st in ipairs(strokes) do if not st.gone then live[#live + 1] = st end end
    if #live == 0 or text:gsub("%s", "") == "" then return nil end
    local DrawText = require("gzreader_drawtext")
    local area = sk:strokesArea(live)
    local el, fields
    if into then
        local joined = (into.text or "") .. ((into.text or "") == "" and "" or (newline and "\n" or " ")) .. text
        local probe = { text = joined, width = into.width, fontSize = into.fontSize }
        el, fields = into, { text = joined, height = Drawing.round2(math.max(into.height, self:textHeight(probe))) }
    else
        local lines = 1
        for _l in text:gmatch("\n") do lines = lines + 1 end
        local size = self:hwSize((area.y1 - area.y0) / lines)
        local sx, sy = sk:toScene(area.x0, area.y0)
        local c = self.canvas
        local w = math.max(area.x1 - area.x0, math.min(c.w * 0.6, c.w - area.x0 - S(16))) / sk.per_unit
        el = DrawText.element(sx, sy, w, text, self.color, size)
        el.height = Drawing.round2(math.max(el.height, self:textHeight(el)))
    end
    sk:convertWriting(live, el, fields)
    self:touched()
    self:redrawAll()
    return el
end

--- The text tool's Write: the pen lifted, writing read a moment later
--- (DrawScreen.HW_PAUSE; a new stroke meanwhile puts it off).
function DrawScreen:hwSoon()
    local Hw = require("gzreader_handwriting")
    if not self._hw_task then
        self._hw_task = function()
            if self._closed then return end
            -- (still writing: later)
            if self.sketch.drawing_slot ~= nil then return UIManager:scheduleIn(Hw.PAUSE, self._hw_task) end
            self:hwNow()
        end
    end
    UIManager:unschedule(self._hw_task)
    UIManager:scheduleIn(Hw.PAUSE, self._hw_task)
end

--- What's been written with Write since the last reading: read, and into the box.
function DrawScreen:hwNow()
    local Hw = require("gzreader_handwriting")
    local sk = self.sketch
    local pending = {}
    for _i, st in ipairs(sk:live()) do
        if st.hw and not st.hw_reading then pending[#pending + 1] = st end
    end
    if #pending == 0 then return end
    for _i, st in ipairs(pending) do st.hw_reading = true end
    local area = sk:strokesArea(pending)
    -- into the box being written in, when this follows on from it (the same line, or the next)
    local into, newline = self.hw_box, false
    if into and (sk.text_gone[into] or not self:hwFollows(into, area)) then into = nil end
    if into then newline = self:hwNextLine(into, area) end
    local t0 = os.time()
    Hw.read(self.plugin, Hw.flat(pending), function(text, why)
        if self._closed or sk ~= self.sketch then return end
        for _i, st in ipairs(pending) do st.hw_reading = nil end
        if not text or text:gsub("%s", "") == "" then
            -- (not read: the writing stays as it is, and isn't tried again)
            for _i, st in ipairs(pending) do st.hw = nil end
            Log.info("drawing: writing not read:", tostring(why or "nothing in it"))
            if why then
                UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3,
                    text = T(_("Your writing couldn't be read (%1). It's kept as you wrote it."), why) })
            end
            return
        end
        local el = self:placeText(pending, (text:gsub("\n+", " ")), into, newline)
        if el then
            self.hw_box = el
            Log.info("drawing: writing turned into text,", #pending, "strokes,", #text, "characters,", os.time() - t0, "s")
        end
    end, { radius = sk:radius(2) })
end

--- Does writing in canvas `area` follow on from box `el`: to its right on its
--- last line, or on the line under it, near its left edge?
function DrawScreen:hwFollows(el, area)
    local DrawText = require("gzreader_drawtext")
    local r = DrawText.rect(el, function(x, y) return self.sketch:toCanvas(x, y) end)
    local line = (el.fontSize or DrawText.SIZE) * 1.25 * self.sketch.per_unit
    local cy = (area.y0 + area.y1) / 2
    return cy >= r.y - line * 0.5 and cy <= r.y + r.h + line * 1.6 and area.x0 >= r.x - line * 2
end

function DrawScreen:hwNextLine(el, area)
    local DrawText = require("gzreader_drawtext")
    local r = DrawText.rect(el, function(x, y) return self.sketch:toCanvas(x, y) end)
    local line = (el.fontSize or DrawText.SIZE) * 1.25 * self.sketch.per_unit
    return (area.y0 + area.y1) / 2 > r.y + r.h + line * 0.2
end

--- The lasso's To text: the chosen writing read, shown to check and change,
--- then a text box where it was (Convert), or left as it is (Cancel).
function DrawScreen:selectionToText()
    local Hw = require("gzreader_handwriting")
    local sk = self.sketch
    local sel = sk.selection
    local strokes = {}
    for _i, st in ipairs(sel and sel.strokes or {}) do if not st.gone and #(st.points or {}) >= 2 then strokes[#strokes + 1] = st end end
    if #strokes == 0 then
        return UIManager:show(require("ui/widget/infomessage"):new{ timeout = 3, text = _("Choose some writing with the lasso first.") })
    end
    local busy = require("ui/widget/infomessage"):new{ text = _("Reading your writing…") }
    UIManager:show(busy)
    UIManager:forceRePaint()
    Log.info("drawing: lasso, to text:", #strokes, "strokes")
    Hw.read(self.plugin, Hw.flat(strokes), function(text, why)
        UIManager:close(busy)
        if self._closed then return end
        if not text or text:gsub("%s", "") == "" then
            return UIManager:show(require("ui/widget/infomessage"):new{ timeout = 4,
                text = why and T(_("Your writing couldn't be read (%1)."), why) or _("Nothing in it could be read as words.") })
        end
        self:askText(_("Text from your writing"), text, function(v)
            if self:placeText(strokes, v) then
                self.paste_at = nil
                self:layoutBar()
                UIManager:setDirty(self, "ui")
                Log.info("drawing: lasso, writing turned into text,", #v, "characters")
            end
        end, nil, _("Convert"))
    end, { radius = sk:radius(2) })
end

--- How fresh ink is put on the e-ink screen. A2 (the quickest) only goes
--- cleanly between black and white: from a grey pixel (a notepaper's lines,
--- a PDF page, a picture) its black came out light, so a stroke had gaps
--- wherever it crossed a ruled line (the owner's Scribe, 2026-11-16). With
--- a picture under the page: DU ("fast"), which goes from any grey to black.
--- How often the new ink is put on the screen, in seconds, for a pen `lag`
--- seconds ahead of what's handled. A pen reports a few hundred points a
--- second; a screen refresh for each took longer than the points came in,
--- so a long line fell further and further behind the pen (the owner,
--- 2026-11-17). The ink is always painted at once; it's shown at most this
--- often: 60 times a second, and only 8 while the drawing is behind, so
--- the handling catches up instead of falling further back.
function DrawScreen.inkInterval(lag)
    if (lag or 0) > DrawScreen.LAG_LIMIT then return DrawScreen.INK_BEHIND end
    return DrawScreen.INK_STEP
end
DrawScreen.INK_STEP, DrawScreen.INK_BEHIND, DrawScreen.LAG_LIMIT = 1 / 60, 1 / 8, 0.05

--- New ink in the screen rectangle (x0, y0)-(x1, y1): shown now, or with what comes next.
function DrawScreen:showInk(x0, y0, x1, y1)
    local d = self._ink_due
    if d then
        d.x0, d.y0, d.x1, d.y1 = math.min(d.x0, x0), math.min(d.y0, y0), math.max(d.x1, x1), math.max(d.y1, y1)
    else
        self._ink_due = { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
    end
    local st = self._stroke_stats or { frames = 0, shown = 0, lag = 0 }
    self._stroke_stats = st
    st.frames, st.lag = st.frames + 1, math.max(st.lag, self._lag or 0)
    local now = self._now or 0
    if now - (self._ink_shown_at or 0) >= DrawScreen.inkInterval(self._lag) then return self:flushInk() end
    -- (the pen held still after this: what's due is shown a moment later all the same)
    if not self._ink_timer then
        self._ink_timer = function()
            self._ink_timer = nil
            if not self._closed then self:flushInk() end
        end
        UIManager:scheduleIn(DrawScreen.INK_BEHIND, self._ink_timer)
    end
end

--- Shows the ink that's due. `done`: the stroke ended (a long one's numbers go to the log).
function DrawScreen:flushInk(done)
    local d = self._ink_due
    if d then
        self._ink_due = nil
        self._ink_shown_at = self._now or 0
        if self._stroke_stats then self._stroke_stats.shown = self._stroke_stats.shown + 1 end
        local rects = self._pen_rects
        self._pen_rects = nil
        local fast = false
        if self.pen_fast and rects and #rects > 0 then
            -- (the Scribe's pen mode: small updates sent to the screen at once, not at the next repaint)
            local PenMode = require("gzreader_penmode")
            fast = PenMode.ink(Screen, rects)
            if PenMode.failed then
                self.pen_fast = false
                Log.info("drawing: the Kindle's pen mode can't be used here, ink shown as before:", tostring(PenMode.failed))
            end
        end
        if not fast then
            if self.pen_fast then self._ink_ordinary = (self._ink_ordinary or 0) + 1 end
            UIManager:setDirty(nil, self:inkRefresh(), Geom:new{ x = d.x0 + self.ox, y = d.y0 + self.oy, w = d.x1 - d.x0, h = d.y1 - d.y0 })
        end
    end
    if done then
        local st = self._stroke_stats
        self._stroke_stats = nil
        -- (numbers only, for a report: how a long stroke kept up)
        if st and st.frames >= DrawScreen.LONG_STROKE then
            Log.info(string.format("drawing: a long stroke: %d frames, shown %d times, at most %.0f ms behind the pen, %.2f ms a frame to handle",
                st.frames, st.shown, st.lag * 1000, (st.cpu or 0) * 1000 / st.frames))
        end
    end
end
DrawScreen.LONG_STROKE = 300

function DrawScreen.inkRefreshFor(locked)
    for _i, el in ipairs(locked or {}) do
        if el.type == "image" then return "fast" end
    end
    return "a2"
end

function DrawScreen:inkRefresh() return DrawScreen.inkRefreshFor(self.sketch.locked) end

function DrawScreen:tapAt(x, y)
    for i = #self.buttons, 1, -1 do -- (an open panel's buttons are last: first asked)
        local b = self.buttons[i]
        local r = b.rect
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            if b.tool.passive then return end
            return self:use(b.tool)
        end
    end
    -- a tap beside an open panel puts it away
    if self.flyout and not intersects(self.frames.flyout, x, y, x, y) then self:setFlyout(nil) end
end

--- The toolbar (and the other controls) drawn again.
function DrawScreen:refreshBar()
    -- (Undo or Redo woke up or went to sleep: only the tools change, so only they are
    -- refreshed; it was the whole screen, after the first stroke of every drawing)
    local f = self.frames and self.frames.toolbar
    if f and f.w and f.w > 0 then
        local area = Geom:new{ x = f.x + self.ox, y = f.y + self.oy, w = f.w, h = f.h }
        UIManager:setDirty(self, function() return "ui", area end)
    else
        UIManager:setDirty(self, "ui")
    end
end

function DrawScreen:setFlyout(which)
    self.flyout = which
    self:layoutBar()
    UIManager:setDirty(self, "ui")
end

--- The pen's colour ("#rrggbb"; memos' ink: its own colour or nil), kept for next time.
function DrawScreen:setColor(hex)
    self.color = Sketch.inkColor(hex)
    if self.tool ~= "shape" then self.tool = "pen" end
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_color", self.color or Drawing.INK) end
    self:syncTool()
end

--- A pen Kindle: draw with a finger (true), as the Kindles without a pen do, or
--- with the pen (false: fingers don't draw, a hand can rest on the screen, and
--- a finger moves a zoomed page). Kept for next time.
function DrawScreen:setDrawWithFinger(on)
    if not self.has_pen then return end
    self.pen_only = not on
    if self.sketch then self.sketch.pen_only = self.pen_only end
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_draw_with_finger", on == true) end
    Log.info("drawing: draw with", on and "a finger" or "the pen")
    self:layoutBar()
    UIManager:setDirty(self, "ui")
end

--- The tool in hand ("pen", "highlighter", "shape", "eraser"), and the pen's width.
function DrawScreen:setTool(tool, width)
    if tool ~= "text" and self.text_sel then self.text_sel = nil; UIManager:setDirty(self, "ui") end
    self.tool = tool
    if width then
        self.width = width
        if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_width", width) end
    end
    self:syncTool()
end

--- The writing tool (Sketch.TOOL_IDS), kept for next time; the pen in hand
--- (the highlighter: its own button).
function DrawScreen:setWriting(id)
    if not Sketch.TOOL_STYLE[id] then return end
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_writing", id) end
    if id == "highlighter" then
        self:setTool("highlighter")
    else
        self.writing = id
        self:setTool("pen")
    end
    Log.info("drawing: writing with the", id)
end

--- A setting kept for next time.
local function keep(key, value)
    if G_reader_settings then G_reader_settings:saveSetting(key, value) end
end

--- The drawing's name (a new drawing's), asked for in a small window.
function DrawScreen:rename()
    if not self.meta then return end
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("Name this drawing"),
        input = self.meta.title,
        input_hint = _("Untitled drawing"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), is_enter_default = true, callback = function()
                self.meta.title = (dialog:getInputText() or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                UIManager:close(dialog)
                self.changed = true
                UIManager:setDirty(self, "ui")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Tag `name` on the drawing, or off it when it's there.
function DrawScreen:toggleTag(name)
    if not self.meta then return end
    self.meta.tags = require("gzreader_newdrawing").toggle(self.meta.tags, name)
    self.changed = true
end

--- A tag of your own, asked for in a small window.
function DrawScreen:newTag()
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = _("New tag"),
        input_hint = _("tag"),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Add"), is_enter_default = true, callback = function()
                local name = require("gzreader_noteeditor").cleanTag(dialog:getInputText() or "")
                UIManager:close(dialog)
                if name ~= "" then
                    local had = false
                    for _i, t in ipairs(self.meta.tags) do if t == name then had = true end end
                    if not had then self:toggleTag(name) end
                end
                self:setFlyout("tags")
            end },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- The pen's shortcut button: the next tool (Settings → Notes has the same choice).
function DrawScreen:nextShortcut()
    local now, list = DrawScreen.shortcut(), Sketch.SHORTCUTS
    local k = 1
    for i, id in ipairs(list) do if id == now then k = i end end
    local id = list[k % #list + 1]
    keep("gzreader_drawing_shortcut", id)
    Log.info("drawing: the pen's shortcut button:", id)
end

function DrawScreen:use(t)
    local sk = self.sketch
    -- a tool: taken in hand; again: its choices
    local function tool(id)
        if self.tool == id then self:setFlyout(self.flyout ~= id and id or nil) else self:setTool(id); self:setFlyout(nil) end
    end
    -- (Paste was on offer and something else was tapped: put away)
    if self.paste_at and t.id ~= "paste" then
        self.paste_at = nil
        self:layoutBar()
        UIManager:setDirty(self, "ui")
    end
    if t.writing then self:setWriting(t.writing); self:setFlyout("pen") -- (stays open: a thickness next)
    elseif t.width then self:setTool(self.tool == "shape" and "shape" or "pen", t.width); self:setFlyout(nil)
    elseif t.hl_width then
        self.hl_width = t.hl_width
        keep("gzreader_drawing_hl_width", t.hl_width)
        self:setTool("highlighter"); self:setFlyout(nil)
    elseif t.shape then
        self.shape = t.shape
        keep("gzreader_drawing_shape", t.shape)
        self:setTool("shape"); self:setFlyout(nil)
        Log.info("drawing: shape", t.shape)
    elseif t.eraser_width then
        self.eraser_width = t.eraser_width
        keep("gzreader_drawing_eraser_width", t.eraser_width)
        self:setTool("eraser"); self:setFlyout(nil)
    elseif t.color then self:setColor(t.color); self:setFlyout(nil)
    elseif t.tagname then self:toggleTag(t.tagname); self:setFlyout("tags")
    elseif t.id == "newtag" then self:newTag()
    elseif t.id == "tag" then self:setFlyout(self.flyout ~= "tags" and "tags" or nil)
    elseif t.id == "title" then self:setFlyout(nil); self:rename()
    elseif t.id == "snap" then
        self.snap_shapes = not self.snap_shapes
        keep("gzreader_drawing_snap", self.snap_shapes)
        self:syncTool()
        Log.info("drawing: draw and hold for clean shapes", self.snap_shapes and "on" or "off")
        self:setFlyout("shape")
    elseif t.id == "pressure" then
        self.pressure_on = not self.pressure_on
        keep("gzreader_drawing_pressure", self.pressure_on)
        self:syncTool()
        self:setFlyout("pen") -- (laid out again: its switch changed)
    elseif t.id == "pen" or t.id == "highlighter" or t.id == "shape" or t.id == "eraser" then tool(t.id)
    elseif t.id == "lasso" then
        -- the lasso: a loop around strokes chooses them (to move, resize, copy, cut, delete)
        self:setTool("lasso"); self:setFlyout(nil)
        Log.info("drawing: the lasso")
    elseif t.id == "sel-copy" then
        -- (as the Kindle's: copied, and let go of; a tap on an empty place then offers Paste)
        local n = sk.selection and #sk.selection.strokes or 0
        if sk:lassoCopy() then
            sk:clearSelection()
            Log.info("drawing: lasso,", n, "strokes copied")
        end
        self:layoutBar()
        UIManager:setDirty(self, "ui")
    elseif t.id == "sel-cut" or t.id == "sel-delete" then
        local n = sk.selection and #sk.selection.strokes or 0
        local changed, area
        if t.id == "sel-cut" then changed, area = sk:lassoCut() else changed, area = sk:lassoDelete() end
        if changed then
            self:touched()
            Log.info("drawing: lasso,", n, "strokes", t.id == "sel-cut" and "cut" or "deleted")
            self:layoutBar()
            if not self:repaintArea(area) then self:repaintCanvas() end
        else
            self:layoutBar()
        end
        UIManager:setDirty(self, "ui")
    elseif t.id == "paste" then
        local at = self.paste_at
        self.paste_at = nil
        local changed, area
        if at then changed, area = sk:lassoPaste(at.x, at.y) end
        if changed then
            self:touched()
            Log.info("drawing: lasso,", #sk.selection.strokes, "strokes pasted")
            if not self:repaintArea(area) then self:repaintCanvas() end
        end
        self:layoutBar()
        UIManager:setDirty(self, "ui")
    elseif t.id == "hand" then
        -- the hand: the pen (or a finger) moves the page about, and nothing is drawn
        self:setTool("hand"); self:setFlyout(nil)
        Log.info("drawing: the hand tool")
    elseif t.id == "fingers" then
        self:setDrawWithFinger(self.pen_only)
    elseif t.id == "text" then
        -- (in hand already: its panel, Type or Write by hand)
        if self.tool == "text" then self:setFlyout(self.flyout ~= "text" and "text" or nil)
        else self:setTool("text"); self:setFlyout(nil) end
        Log.info("drawing: the text tool", self.write_text and "(write by hand)" or "")
    elseif t.id == "write-text" then
        self.write_text = not self.write_text
        keep("gzreader_drawing_write_text", self.write_text)
        self.hw_box = nil
        self:setTool("text")
        Log.info("drawing: the text tool:", self.write_text and "write by hand" or "type")
        self:setFlyout("text")
    elseif t.id == "hw-how" then
        self:setFlyout(nil)
        UIManager:show(require("ui/widget/infomessage"):new{ text = DrawScreen.hwHow(self.plugin) })
    elseif t.id == "sel-text" then
        self:selectionToText()
    elseif t.id == "more" or t.id == "options" then self:setFlyout(self.flyout ~= t.id and t.id or nil)
    elseif t.id == "shortcut" then self:nextShortcut(); self:setFlyout("more")
    elseif t.id == "penmode" then
        local PenMode = require("gzreader_penmode")
        local on = not self.pen_fast
        keep(PenMode.SETTING, on)
        if on then
            PenMode.failed = nil -- (asked for again: tried again)
            self.pen_fast = PenMode.supported(Device)
            if self.pen_fast then PenMode.hook(Screen, UIManager) end
        else
            self.pen_fast = false
            PenMode.unhook()
        end
        Log.info("drawing: the Kindle's pen mode", self.pen_fast and "on" or "off")
        self:setFlyout("more")
    elseif t.id == "undo" or t.id == "redo" then
        local changed, area
        if t.id == "undo" then changed, area = sk:undo() else changed, area = sk:redo() end
        if changed then
            self:touched()
            -- (a stroke taken back or put back: only where it is; and the tools, for Undo and Redo themselves)
            if self:repaintArea(area) then self:refreshBar() else self:redrawAll() end
        end
    elseif t.id == "clear" then
        self.flyout = nil
        self:layoutBar()
        if sk:clear() then self:touched() end
        self:redrawAll()
    elseif t.id == "whole" then
        self.flyout = nil
        self:layoutBar()
        sk:unzoom()
        self:redrawAll()
    elseif t.id == "cancel" and self.journal and not t.row then
        -- a journal entry's drawing: back to the whole entry, the drawing kept
        self.flyout = nil; self.after = "entry"; self:done()
    elseif t.id == "cancel" then self.flyout = nil; self:layoutBar(); self:cancel()
    elseif t.id == "typing" then
        -- a journal entry's drawing: back to typing (the drawing kept)
        Log.info("drawing: journal, back to typing")
        self.after = "typing"; self:done()
    elseif t.id == "archive-note" or t.id == "delete-note" then
        self.flyout = nil
        self:layoutBar()
        self:redrawAll()
        Log.info("drawing:", t.id)
        if t.id == "archive-note" then self.note_actions.archive(self) else self.note_actions.delete(self) end
    elseif t.id == "done" then
        -- (a journal entry's: Save, the drawing kept and the entry saved)
        if self.journal then self.after = "save" end
        self:done()
    elseif t.id == "paper" then self:pickPaper()
    elseif t.id == "pages" then self:showPages()
    elseif t.id == "side" then
        self.toolbar_side = self.toolbar_side == "left" and "right" or "left"
        keep("gzreader_drawing_toolbar_side", self.toolbar_side)
        self:setFlyout(nil)
    elseif t.id == "hide" or t.id == "show" then
        self.toolbar_hidden = t.id == "hide"
        self:setFlyout(nil)
    elseif t.id == "topfold" then
        self.top_hidden = not self.top_hidden
        self:setFlyout(nil)
        UIManager:setDirty(self, "ui")
        Log.info("drawing: the top bar", self.top_hidden and "folded away" or "shown")
    elseif t.id == "prev" then if self.index > 1 then self:showPage(self.index - 1) end
    elseif t.id == "next" then if self.index < #self.pages then self:showPage(self.index + 1) end
    elseif t.id == "newpage" or t.id == "newpage2" then self.flyout = nil; self:newPage()
    elseif t.id == "immich" then self:setFlyout(nil); self:pickPictures()
    elseif t.fn and t.id:sub(1, 5) == "note-" then
        -- (the note's own icons: the editor behind does it, as in its bar)
        self:setFlyout(nil)
        t.fn()
    end
end

-- ------------------------------------------------------------------ pages

--- + New page: another drawing for the note, on the last paper chosen,
--- after page `after` (the page shown).
function DrawScreen:newPage(after)
    after = after or self.index
    table.insert(self.pages, after + 1, { new = true, paper = DrawScreen.lastPaper(), modified = true })
    self.changed = true
    if after + 1 < #self.pages then self.reordered = true end
    self:showPage(after + 1)
    Log.info("drawing: a new page,", #self.pages, "now")
end

--- A copy of page `i`, after it.
function DrawScreen:duplicatePage(i)
    local sk = self:sketchOf(self.pages[i])
    if not sk then return false end
    local copy = Drawing.decode(Drawing.encode(sk:scene()))
    if not copy then return false end
    table.insert(self.pages, i + 1, { new = true, modified = true, sketch = self:newSketch(copy) })
    self.changed, self.reordered = true, true
    Log.info("drawing: page", i, "duplicated")
    return true
end

--- Moves page `i` one place (`d`: -1 earlier, 1 later).
function DrawScreen:movePage(i, d)
    local j = i + d
    if j < 1 or j > #self.pages then return false end
    self.pages[i], self.pages[j] = self.pages[j], self.pages[i]
    if self.index == i then self.index = j elseif self.index == j then self.index = i end
    self.changed, self.reordered = true, true
    return true
end

--- Takes page `i` off the note (the only page: emptied instead).
function DrawScreen:deletePage(i)
    local p = table.remove(self.pages, i)
    if not p then return false end
    self.gone[#self.gone + 1] = p
    for _k, bb in pairs(p.pictures or {}) do if bb then bb:free() end end
    p.pictures = nil
    if p.thumb then p.thumb:free(); p.thumb = nil end
    if #self.pages == 0 then self.pages[1] = { new = true, paper = DrawScreen.lastPaper(), modified = true } end
    self.changed = true
    self:showPage(math.max(1, math.min(self.index > i and self.index - 1 or self.index, #self.pages)), true)
    Log.info("drawing: page", i, "deleted,", #self.pages, "left")
    return true
end

--- Page `i` as a small picture at most w x h (kept until the page changes):
--- its paper when it has one, else the whole page.
function DrawScreen:pageThumb(i, w, h)
    local p = self.pages[i]
    local key = w .. "x" .. h
    if p.thumb and not p.thumb_stale and p.thumb_key == key then return p.thumb end
    if p.thumb then p.thumb:free(); p.thumb = nil end
    local shown = self.index
    if shown ~= i then self:showPage(i, true) end
    local c = self.canvas
    local r = self.sketch:pageRect()
    local x0, y0, cw, ch = 0, 0, c.w, c.h
    if r then
        x0, y0 = math.max(0, math.floor(r.x)), math.max(0, math.floor(r.y))
        cw, ch = math.min(c.w - x0, math.floor(r.w)), math.min(c.h - y0, math.floor(r.h))
    end
    local scale = math.min(w / cw, h / ch)
    local part = Blitbuffer.new(cw, ch, Blitbuffer.TYPE_BB8)
    part:blitFrom(self.canvas_bb, 0, 0, x0, y0, cw, ch)
    local small = part:scale(math.max(1, math.floor(cw * scale)), math.max(1, math.floor(ch * scale)))
    part:free()
    p.thumb, p.thumb_key, p.thumb_stale = small, key, nil
    if shown ~= i then self:showPage(shown, true) end
    return small
end

-- ------------------------------------------------------------ pictures

--- Photos from Immich (gzreader_immichpick.lua), placed on the page as
--- memos' drawing sheet places them: in the middle of what's shown.
function DrawScreen:pickPictures()
    require("gzreader_immichpick").show(DrawScreen.immich, { on_pick = function(files)
        if self._closed then for _i, f in ipairs(files) do os.remove(f.path) end; return end
        self:addPictures(files)
    end })
end

--- Puts pictures (files { path, type, w, h }) on the page shown; undo takes each off.
function DrawScreen:addPictures(files)
    local sk = self.sketch
    local c = self.canvas
    -- what's shown, in scene units (the canvas is the page on the screen)
    local x0, y0 = sk:toScene(0, 0)
    local x1, y1 = sk:toScene(c.w, c.h)
    local view = { cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, w = x1 - x0, h = y1 - y0 }
    local sizes = {}
    for i, f in ipairs(files) do sizes[i] = { w = f.w, h = f.h } end
    local places = Sketch.placePictures(sizes, view)
    local b64 = require("ffi/sha2").bin_to_base64
    local added, els = 0, {}
    for i, f in ipairs(files) do
        local fh = io.open(f.path, "rb")
        local data = fh and fh:read("*a")
        if fh then fh:close() end
        os.remove(f.path) -- (its pixels are in the drawing now)
        if data and #data > 0 then
            local pl = places[i]
            els[#els + 1] = sk:addPicture("data:" .. (f.type or "image/jpeg") .. ";base64," .. b64(data), f.type or "image/jpeg", pl.w, pl.h, pl.cx, pl.cy)
            added = added + 1
        end
    end
    if added > 0 then
        self:touched()
        Log.info("drawing:", added, "picture(s) from Immich placed, chosen with the lasso to move and size")
        -- chosen with the lasso: drag to move them, a corner to make them bigger or smaller
        self:setTool("lasso"); self:setFlyout(nil)
        sk:selectPictures(els)
        self:layoutBar()
        self:redrawAll()
    end
    return added
end

--- All pages: small pictures of the note's pages, to go to one, add, copy, move or delete.
function DrawScreen:showPages()
    self:setFlyout(nil)
    return require("gzreader_drawpages").showPages(self)
end

--- Paper: the page's background (and the one new pages start on), picked from pictures of each.
function DrawScreen:pickPaper()
    self:setFlyout(nil)
    return require("gzreader_drawpages").showPapers{
        current = self.sketch:paper(),
        title = T(_("Paper for page %1"), self.index),
        on_pick = function(id)
            DrawScreen.setLastPaper(id)
            if id ~= self.sketch:paper() then self:setPaper(id) end
        end,
    }
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
    if self._hw_task then UIManager:unschedule(self._hw_task) end
    self._closed = true
    if self._keep_task then UIManager:unschedule(self._keep_task) end
    -- (beside a book: the book has the whole screen again)
    if self.pane and not self.journal then pcall(function() require("gzreader_splitview").closed(self) end) end
    self:unhook()
    pcall(DrawScreen.savePenRange, self._pen_range_was)
    for _i, bb in ipairs({ "canvas_bb", "ink_bb", "color_bb", "tint_bb" }) do
        if self[bb] then self[bb]:free(); self[bb] = nil end
    end
    for _i, p in ipairs(self.pages or {}) do
        for _k, bb in pairs(p.pictures or {}) do if bb then bb:free() end end
        p.pictures = nil
        if p.thumb then p.thumb:free(); p.thumb = nil end
    end
    for _k, icon in pairs(self.icons or {}) do if icon.free then icon:free() end end
    self.icons = {}
    local sk = self.sketch
    if sk then
        Log.info("drawing: closed;", #self.pages, "pages;", #sk:live(), "strokes on the last;", sk.stats.palm,
            "palm contacts and", sk.stats.ignored, "other contacts ignored;", sk.stats.panned or 0, "moves of the page by a finger or the hand tool")
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
    -- (✕ with something drawn: Save, Discard or Keep drawing, as the note editor's ✕)
    local dialog
    dialog = ButtonDialog:new{ title = _("Save this drawing?"), buttons = {
        { { text = _("Save"), align = "left", callback = function()
            UIManager:close(dialog)
            Log.info("drawing: closed with changes: saved")
            self:done()
        end } },
        { { text = _("Discard changes"), align = "left", callback = function()
            if not self.journal then require("gzreader_drawdraft").clear(self.draft_id, "discarded") end
            if self._keep_task then UIManager:unschedule(self._keep_task) end
            UIManager:close(dialog); self:close()
            if self.on_cancel then self.on_cancel() end
        end } },
        { { text = _("Keep drawing"), align = "left", callback = function() UIManager:close(dialog) end } },
    } }
    self.leave_dialog = dialog
    UIManager:show(dialog)
end

--- `#rrggbb` as r, g, b.
function DrawScreen.hexRGB(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

--- The PNG's pixels: the cropped page (canvas pixels `crop`), 8-bit RGB rows:
--- the ink (`ink_bb`, grey 0 ink … 255 none) in memos' ink colour, or in
--- each stroke's own (`tint_bb`, when a stroke has one), over the pictures
--- (`color_bb`, in colour) or memos' paper. Returns a uint8_t array and its size.
function DrawScreen.pixels(ink_bb, crop, color_bb, tint_bb)
    local pr, pg, pb = DrawScreen.hexRGB(Drawing.PAPER)
    local ir, ig, ib = DrawScreen.hexRGB(Drawing.INK)
    local w, h = crop.w, crop.h
    local mem = ffi.new("uint8_t[?]", w * h * 3)
    -- (an 8-bit page, not rotated: its rows straight from memory)
    local data = ink_bb.data and ffi.cast("uint8_t *", ink_bb.data)
    local stride = tonumber(ink_bb.stride)
    local i = 0
    if not color_bb and not tint_bb then
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
    -- (a 24-bit buffer's rows straight from memory too; otherwise pixel by pixel)
    local function rows(bb)
        if not bb then return nil end
        return bb.data and ffi.cast("uint8_t *", bb.data), tonumber(bb.stride)
    end
    local function at(bb, bdata, bstride, x, y, dr, dg, db)
        if not bb then return dr, dg, db end
        if bdata then
            local o = y * bstride + x * 3
            return bdata[o], bdata[o + 1], bdata[o + 2]
        end
        local c = bb:getPixel(x, y)
        return c.r or dr, c.g or dg, c.b or db
    end
    local cdata, cstride = rows(color_bb)
    local tdata, tstride = rows(tint_bb)
    for y = crop.y, crop.y + h - 1 do
        local row = data and (y * stride)
        for x = crop.x, crop.x + w - 1 do
            local g = data and data[row + x] or ink_bb:getPixel(x, y):getColor8().a
            local r, gg, b = at(color_bb, cdata, cstride, x, y, pr, pg, pb)
            local f = g / 255
            if g == 255 then
                mem[i], mem[i + 1], mem[i + 2] = r, gg, b
            else
                local tr, tg, tb = at(tint_bb, tdata, tstride, x, y, ir, ig, ib)
                mem[i] = math.floor(tr + (r - tr) * f + 0.5)
                mem[i + 1] = math.floor(tg + (gg - tg) * f + 0.5)
                mem[i + 2] = math.floor(tb + (b - tb) * f + 0.5)
            end
            i = i + 3
        end
    end
    return mem, w * h * 3
end

--- Saves the page shown: the PNG of the page (cropped, memos' colours) with
--- the scene inside. Returns { path, filename } or nil, err.
function DrawScreen:save()
    local sk, p = self.sketch, self.page
    -- (zoomed: the whole page again first; the picture is made from the screen's)
    if sk:unzoom() then self:repaintCanvas() end
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
    local mem = DrawScreen.pixels(self.ink_bb, crop, self.color_bb, self.tint_bb)
    local Png = require("ffi/png")
    local ok, err = Png.encodeToFile(tmp, mem, crop.w, crop.h, 3)
    if ok == false then os.remove(tmp); return nil, err or "png" end
    local scene = sk:scene()
    local wrote, why = Drawing.writeFile(tmp, scene, path)
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
    -- "Saving…" at once when pages are to be made into pictures (a second or more on a big screen)
    local box
    for _i, p in ipairs(self.pages) do
        if p.modified then box = require("gzreader_saving").show(); break end
    end
    local function closeBox() if box then require("gzreader_saving").close(box); box = nil end end
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
                    closeBox()
                    UIManager:show(require("ui/widget/infomessage"):new{ text = _("Couldn't save the drawing."), timeout = 3 })
                    return
                end
                results[#results + 1] = { att = p.att, path = res.path, filename = res.filename, changed = true }
            end
        end
    end
    -- pages deleted here: gone from Memos too; a new one's waiting file with it
    for _i, p in ipairs(self.gone or {}) do
        if p.att then results[#results + 1] = { att = p.att, removed = true, changed = true }
        elseif p.path then os.remove(p.path) end
    end
    results.reordered = self.reordered or nil
    -- the copy kept as it's drawn: a journal entry's goes on until the entry's saved
    -- (the entry keeps the drawing until then); a note's drawing is saved now
    if self.journal then
        if self._keep_planned or self.changed then self:keepNow("back to the entry") end
    else
        require("gzreader_drawdraft").clear(self.draft_id, "saved")
    end
    if self._keep_task then UIManager:unschedule(self._keep_task) end
    self:close()
    if self.on_done then self.on_done(results) end
    -- (the note's own Saving… follows when it's saved from here: this one goes once that's up)
    if box then UIManager:scheduleIn(0.2, closeBox) end
end

--- opts: pages ({ att, path, filename, changed, removed }: the note's
--- drawings, or { scene }: a new page ready to draw on, e.g. a PDF's page;
--- none: a new page), start (the page shown first),
--- on_done(pages), on_cancel; meta ({ title, tags, offered }: a new
--- drawing's name and tags, set in the top bar and given back as
--- pages.title and pages.tags); choose_paper: a new drawing (no pages) asks
--- which paper first, as the Kindle Scribe's Create notebook does (Cancel
--- there: on_cancel, nothing opened).
function DrawScreen.show(opts)
    -- Beside a book (gzreader_splitview): this drawing opens in the notes' part of the
    -- screen, on the paper used last (no chooser over the book), named for the book.
    local split = package.loaded["gzreader_splitview"]
    local taken = split and not opts.journal and not opts.sticky and split.take()
    if taken then
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.pane, o.choose_paper = taken.pane, nil
        if type(o.meta) == "table" and (o.meta.title or "") == "" and (taken.title or "") ~= "" then
            o.meta.title = T(_("Notes on %1"), taken.title)
        end
        opts = o
    end
    if opts.choose_paper and DrawScreen.asksPaper(opts.pages) then
        return require("gzreader_drawpages").showPapers{
            create = true,
            current = DrawScreen.lastPaper(),
            title = _("New drawing"),
            on_pick = function(id)
                DrawScreen.setLastPaper(id)
                Log.info("drawing: new, on paper", id)
                local o = {}
                for k, v in pairs(opts) do o[k] = v end
                o.choose_paper = nil
                DrawScreen.show(o)
            end,
            on_back = function() if opts.on_cancel then opts.on_cancel() end end,
        }
    end
    -- (the plugin, when a way to Immich is set up: Picture from Immich in ⋮; one drawing screen at a time)
    DrawScreen.immich = opts.immich

    local pages = {}
    for _i, p in ipairs(opts.pages or {}) do
        if not p.removed then
            pages[#pages + 1] = { att = p.att, path = p.path, filename = p.filename, changed = p.changed,
                new = p.scene and true or nil, scene = p.scene, modified = p.scene and true or nil }
        end
    end
    -- (pages taken off earlier stay off: given back as they were)
    local gone = {}
    for _i, p in ipairs(opts.pages or {}) do if p.removed then gone[#gone + 1] = p end end
    local on_done = opts.on_done
    local w
    w = DrawScreen:new{ pages = pages, start = opts.start, on_cancel = opts.on_cancel, title = opts.title, meta = opts.meta,
        plugin = opts.plugin, -- (the quick panel, pulled down)
        pane = opts.pane,
        sticky = opts.sticky, -- the quick note's drawing: `pane` is a sticky note's window (gzreader_noteeditor)
        journal = opts.journal, -- { under }: a journal entry's drawing, in `pane` under its prompt (the entry: `under`)
        note_actions = opts.note_actions, -- { archive(screen), delete(screen) }: a note that's already there
        note_icons = opts.note_icons, -- fn(screen) → the note's icons' actions (gzreader_notebar.noteIcons)
        on_done = on_done and function(res)
            for _i, p in ipairs(gone) do res[#res + 1] = p end
            -- (a journal entry's: what comes next, "entry", "typing" or "save")
            res.after = w.after
            -- (a new drawing: the name and tags given in the top bar)
            if w.meta then res.title, res.tags = w.meta.title, w.meta.tags end
            on_done(res)
        end }
    if w.pane then
        UIManager:show(w, "ui", nil, w.pane.x, w.pane.y)
    else
        UIManager:show(w, "full")
    end
    return w
end

return DrawScreen
