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
  Every other touch Kindle draws with one finger.
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
    { id = "hand", icon = "hand", label = _("Move the page") },
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
    self.pen_only = Sketch.penDevice(Device)
    self.top_h = S(52)
    self.bar_h = self.top_h
    self.top_hidden = false -- (folded away by the tab under it)
    self.tool_sz = S(48)
    -- the page is the whole screen: the top bar lies over it, and folds away (its tab)
    self.canvas = { x = 0, y = 0, w = sw, h = sh }
    if self.inline then
        -- Inline (a journal entry's box): a window onto a page as big as the
        -- screen, moved around by a finger (a pen Kindle) or the hand tool;
        -- touches outside the window go to the screen under it.
        local r = self.inline.rect
        self.window = Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
        self.dimen = Geom:new{ x = r.x, y = r.y, w = r.w, h = r.h }
        self.covers_fullscreen = false
        self.pan_x, self.pan_y = 0, 0
        self.canvas = { x = r.x, y = r.y, w = math.max(r.w, sw), h = math.max(r.h, sh) }
        self._passing = {}
    end
    -- a new drawing: its name and tags, set from the top bar ({ title, tags, offered })
    if self.meta then
        self.meta.title = self.meta.title or ""
        self.meta.tags = self.meta.tags or {}
    end
    self.pages = self.pages or {}
    if #self.pages == 0 then self.pages[1] = { new = true } end
    self.index = math.max(1, math.min(self.start or 1, #self.pages))
    self.gone = {} -- pages deleted here: { att, removed = true } for those in Memos
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
    self:repaintCanvas()
    if not first then UIManager:setDirty(self, "ui") end
end

--- This page changed (drawn on, rubbed out, its paper).
function DrawScreen:touched()
    self.page.modified = true
    self.page.thumb_stale = true
    self.changed = true
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
    sk.tool = hl and "pen" or self.tool
    sk.writing = hl and "highlighter" or self.writing
    sk.width = hl and self.hl_width or self.width
    sk.color = self.color
    sk.shape = self.shape
    sk.eraser_width = self.eraser_width
    sk.pressure_on = self.pressure_on
    -- text boxes: their corner handle, and how tall their lines are
    sk.text_handle = S(44)
    sk.text_height = function(el) return self:textHeight(el) end
    if self.window then
        -- inline: the page moves under the window (a finger on a pen Kindle, or the hand tool)
        sk.inline_pan = true
        sk.on_pan = function(dx, dy) return self:panBy(dx, dy) end
    end
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
        if self.pen_only then
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
    elseif which == "eraser" then
        for k, w in ipairs(Sketch.ERASER_WIDTHS) do
            rows[#rows + 1] = { id = "e" .. tostring(w), row = true, eraser_width = w, bar = k, hollow = true, label = DrawScreen.WIDTH_NAMES[k] }
        end
        rows[#rows + 1] = { id = "clear", row = true, label = _("Erase page") }
    elseif which == "more" then
        rows[#rows + 1] = { id = "side", row = true, label = self.toolbar_side == "left" and _("Move to right side") or _("Move to left side") }
        if self.pen_only then
            rows[#rows + 1] = { id = "shortcut", row = true,
                label = T(_("Stylus shortcut: %1"), DrawScreen.SHORTCUT_NAMES[DrawScreen.shortcut()] or DrawScreen.shortcut()) }
        end
    elseif which == "options" then
        rows[#rows + 1] = { id = "newpage2", row = true, label = _("New page") }
        rows[#rows + 1] = { id = "clear", row = true, label = _("Erase page") }
        if self.sketch and self.sketch.zoomed then rows[#rows + 1] = { id = "whole", row = true, label = _("Whole page") } end
        rows[#rows + 1] = { id = "cancel", row = true, label = _("Close without saving") }
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
DrawScreen.SHORTCUT_NAMES = { eraser = _("Eraser"), pen = _("Pen"), pencil = _("Pencil"), fountain = _("Fountain pen"),
    marker = _("Marker"), highlighter = _("Highlighter") }

--- Lays out what's over the page, as the Kindle Scribe's notebook: the top
--- bar (Back, the drawing's name, pages, paper, tags, options, Done) with a
--- tab under it that folds it away; the tools down one side under a round
--- button that folds them into one; the page buttons at the bottom; and a
--- panel open beside what was tapped. `self.buttons`: { tool, rect, group }.
function DrawScreen:layoutBar()
    if self.window then return self:layoutInline() end
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
        add({ id = "cancel", icon = "back", label = _("Close") }, S(4), S(4), bh, bh, "top")
        local done_w = S(84)
        local x = sw - done_w - S(6)
        add({ id = "done", label = _("Done") }, x, S(6), done_w, self.top_h - S(12), "top")
        local icons = { { id = "options", icon = "more", label = _("Options") } }
        if self.meta then icons[#icons + 1] = { id = "tag", icon = "tag", label = _("Tags") } end
        icons[#icons + 1] = { id = "paper", icon = "paper", label = _("Paper") }
        icons[#icons + 1] = { id = "pages", icon = "pages", label = _("All pages") }
        for _i, t in ipairs(icons) do
            x = x - bh - S(2)
            anchors[t.id] = add(t, x, S(4), bh, bh, "top")
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
            local h = t.sep and S(12) or ts
            anchors[t.id] = add(t, tx + pad, y, ts, h, "toolbar")
            y = y + h
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
    if t.id == "pen" or t.id == "highlighter" or t.id == "shape" or t.id == "eraser" or t.id == "text" or t.id == "hand" then return self.tool == t.id end
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
        local icon = (t.id == "pen" or t.id == "shape") and self:toolIcon(t.id) or t.icon
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
    for _i, name in ipairs({ "tab", "fold", "toolbar", "pill" }) do frame(name) end
    for _i, b in ipairs(self.buttons) do if b.group ~= "flyout" then self:paintButton(bb, x, y, b) end end
    -- (an open panel over everything else)
    frame("flyout")
    for _i, b in ipairs(self.buttons) do if b.group == "flyout" then self:paintButton(bb, x, y, b) end end
end

function DrawScreen:paintTo(bb, x, y)
    if self.window then return self:paintInline(bb) end
    self.dimen.x, self.dimen.y = x, y
    local c = self.canvas
    bb:blitFrom(self.canvas_bb, x + c.x, y + c.y, 0, 0, c.w, c.h)
    self:paintSelection(bb, x + c.x, y + c.y)
    self:paintBar(bb, x, y)
    self._shown = { undo = self.sketch:canUndo(), redo = self.sketch:canRedo() }
end

-- ------------------------------------------------------------- inline (a journal entry)

DrawScreen.INLINE_TOOLS = {
    { id = "pen", icon = "pen", label = _("Pen") },
    { id = "eraser", icon = "eraser", label = _("Eraser") },
    { id = "hand", icon = "hand", label = _("Move the page") },
    { id = "undo", icon = "undo", label = _("Undo") },
    { id = "redo", icon = "redo", label = _("Redo") },
    { id = "typing", label = _("Aa"), label_button = true },
}

--- Inline: the tools in a row along the window's top right corner (they're
--- over the page: a touch there is a tap, never ink).
function DrawScreen:layoutInline()
    local w = self.window
    local ts, gap = S(44), S(4)
    self.buttons, self.holes, self.frames = {}, {}, {}
    local n = #DrawScreen.INLINE_TOOLS
    local typing_w = S(56)
    local bar_w = (n - 1) * ts + typing_w + (n + 1) * gap
    local bx, by = w.x + w.w - bar_w - S(4), w.y + S(4)
    self.frames.toolbar = Geom:new{ x = bx, y = by, w = bar_w, h = ts + 2 * gap }
    local x = bx + gap
    for _i, t in ipairs(DrawScreen.INLINE_TOOLS) do
        local bw = t.label_button and typing_w or ts
        self.buttons[#self.buttons + 1] = { tool = t, rect = Geom:new{ x = x, y = by + gap, w = bw, h = ts }, group = "inline" }
        x = x + bw + gap
    end
    self.holes[1] = self.frames.toolbar
    if self.sketch then self.sketch.holes = self.holes end
end

--- Inline: the window onto the page, its frame, the tools.
function DrawScreen:paintInline(bb)
    local w, c = self.window, self.canvas
    bb:blitFrom(self.canvas_bb, w.x, w.y, w.x - c.x, w.y - c.y, w.w, w.h)
    bb:paintBorder(w.x, w.y, w.w, w.h, Size.border.thin, Blitbuffer.COLOR_BLACK, S(4))
    local f = self.frames.toolbar
    bb:paintRoundedRect(f.x, f.y, f.w, f.h, Blitbuffer.COLOR_WHITE, S(8))
    bb:paintBorder(f.x, f.y, f.w, f.h, Size.border.thin, Blitbuffer.COLOR_BLACK, S(8))
    for _i, b in ipairs(self.buttons) do
        if b.tool.label_button then
            local r = b.rect
            bb:paintBorder(r.x, r.y + S(4), r.w, r.h - S(8), Size.border.thick, Blitbuffer.COLOR_BLACK, S(6))
            textAt(bb, r.x, r.y, r.w, r.h, b.tool.label, 16, true)
        else
            self:paintButton(bb, 0, 0, b)
        end
    end
    self._shown = { undo = self.sketch:canUndo(), redo = self.sketch:canRedo() }
end

--- Inline: the page moved under the window by (dx, dy) screen pixels (as a
--- finger drags it), kept on the page. True when it moved.
function DrawScreen:panBy(dx, dy)
    local w, c = self.window, self.canvas
    local px = math.max(0, math.min(c.w - w.w, self.pan_x - dx))
    local py = math.max(0, math.min(c.h - w.h, self.pan_y - dy))
    if px == self.pan_x and py == self.pan_y then return false end
    self.pan_x, self.pan_y = px, py
    c.x, c.y = w.x - px, w.y - py
    return true
end

--- Inline: whether this input frame is the screen under the window's (a
--- touch that started outside the window, until it's lifted).
function DrawScreen:passThrough(det, tevs)
    local w = self.window
    local pass = false
    for _i, t in ipairs(tevs) do
        local s = t.slot
        if self._passing[s] then
            pass = true
            if t.id == -1 then self._passing[s] = nil end
        elseif t.id ~= -1 and not (self.sketch and self.sketch.contacts[s]) and t.x and t.y then
            local ges = { ges = "tap", pos = Geom:new{ x = t.x, y = t.y, w = 0, h = 0 } }
            if det and det.adjustGesCoordinate then pcall(det.adjustGesCoordinate, det, ges) end
            local x, y = ges.pos.x, ges.pos.y
            if not (x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h) then
                self._passing[s] = true
                pass = true
            end
        end
    end
    return pass
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
                if screen_bb and not under then screen_bb:paintRectRGB32(p[1] - dx, p[2] + dy, pw, 1, shown) end
            else
                self.canvas_bb:paintRect(px, py, pw, 1, Blitbuffer.COLOR_BLACK)
                if screen_bb and not under then screen_bb:paintRect(p[1] - dx, p[2] + dy, pw, 1, Blitbuffer.COLOR_BLACK) end
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
                    local sx, sy = p[1] - dx + k, p[2] + dy
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
    local w = self.window
    if w and (x - r < w.x or x + r >= w.x + w.w or y - r < w.y or y + r >= w.y + w.h) then return true end
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
        local pr = Sketch.toolRadius(st.kind, r, b[3] and (a[3] and (a[3] + b[3]) / 2 or b[3]) or nil)
        out[#out + 1] = { a[1] + c.x, a[2] + c.y, b[1] + c.x, b[2] + c.y, pr, st.color, gray,
            Sketch.grainDensity(st.kind, b[3] and (a[3] and (a[3] + b[3]) / 2 or b[3]) or nil) }
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
        -- (inline: a touch that starts outside the window is the screen under it's)
        if screen.window and screen:passThrough(det, tevs) then return orig(det, tevs) end
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
        return {}
    end)
    -- A Kindle with a pen: its pressure and tilt from the digitizer itself, when
    -- the device KOReader reads the pen from doesn't pass them on (gzreader_penraw).
    if self.pen_only and not self.penraw then
        local PenRaw = require("gzreader_penraw")
        local raw, why = PenRaw.open()
        self.penraw = raw
        if raw then
            Log.info("drawing: pen pressure and tilt also read from", raw.name, raw.event, "abs", PenRaw.absCaps(raw.event))
        else
            Log.info("drawing: the pen's digitizer not read:", tostring(why))
        end
    end
    -- (a tap still under way, e.g. the one that opened this screen, is forgotten)
    pcall(gd.dropContacts, gd)
    if input.clearTimeouts then pcall(input.clearTimeouts, input) end
end

function DrawScreen:unhook()
    local gd = self._gd
    if not gd then return end
    rawset(gd, "feedEvent", self._own_feed)
    self._gd = nil
    if self._ink_timer then UIManager:unschedule(self._ink_timer); self._ink_timer = nil end
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
            x, y = ges.pos.x, ges.pos.y
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
    end
    if out.panned then UIManager:setDirty(self, "ui") end
    if out.redraw then
        -- (the view moved, by a pinch or a finger: the page itself is as it was)
        if not out.view then self:touched() end
        self:redrawAll()
    elseif #out.segments > 0 then
        self:touched()
        local screen_bb = Screen.bb
        local x0, y0, x1, y1
        local grey = false
        for _i, seg in ipairs(out.segments) do
            self:ink(seg, screen_bb)
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
    if out.stroke_done then self:flushInk(true) end
    if out.stroke_done and self._stroke_area and (self._stroke_grey or DrawScreen.inkRefreshFor(self.sketch.locked) ~= "a2") then
        local d = self._stroke_area
        local area = Geom:new{ x = d.x0, y = d.y0, w = d.x1 - d.x0, h = d.y1 - d.y0 }
        if self._stroke_grey then
            -- (a grey tool's stroke: the page painted again, so its real grey replaces the black points)
            UIManager:setDirty(self, function() return "ui", area end)
        else
            UIManager:setDirty(nil, "ui", area)
        end
    end
    if out.stroke_done then self._stroke_area, self._stroke_grey = nil, nil end
    if out.stroke_done then
        -- Undo and Redo wake up or go to sleep
        local shown = self._shown or {}
        if shown.undo ~= self.sketch:canUndo() or shown.redo ~= self.sketch:canRedo() then self:refreshBar() end
    end
    for _i, tap in ipairs(out.taps) do self:tapAt(tap.x, tap.y) end
    if out.text_tap then self:textTap(out.text_tap) end
    if out.pull then self:pullPanel() end
end

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
function DrawScreen:askText(title, text, on_done, on_delete)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    local row = { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end } }
    if on_delete then
        row[#row + 1] = { text = _("Delete"), callback = function() UIManager:close(d); on_delete() end }
    end
    row[#row + 1] = { text = text == "" and _("Add") or _("Save"), is_enter_default = false, callback = function()
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
        UIManager:setDirty(nil, self:inkRefresh(), Geom:new{ x = d.x0, y = d.y0, w = d.x1 - d.x0, h = d.y1 - d.y0 })
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
    UIManager:setDirty(self, "ui")
end

function DrawScreen:setFlyout(which)
    if self.window then which = nil end -- (inline: no panels; its few tools are all in its row)
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
    elseif t.id == "pressure" then
        self.pressure_on = not self.pressure_on
        keep("gzreader_drawing_pressure", self.pressure_on)
        self:syncTool()
        self:setFlyout("pen") -- (laid out again: its switch changed)
    elseif t.id == "pen" or t.id == "highlighter" or t.id == "shape" or t.id == "eraser" then tool(t.id)
    elseif t.id == "hand" then
        -- the hand: the pen (or a finger) moves the page about, and nothing is drawn
        self:setTool("hand"); self:setFlyout(nil)
        Log.info("drawing: the hand tool")
    elseif t.id == "text" then
        self:setTool("text"); self:setFlyout(nil)
        Log.info("drawing: the text tool")
    elseif t.id == "more" or t.id == "options" then self:setFlyout(self.flyout ~= t.id and t.id or nil)
    elseif t.id == "shortcut" then self:nextShortcut(); self:setFlyout("more")
    elseif t.id == "undo" then if sk:undo() then self:touched(); self:redrawAll() end
    elseif t.id == "redo" then if sk:redo() then self:touched(); self:redrawAll() end
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
    elseif t.id == "cancel" then self.flyout = nil; self:layoutBar(); self:cancel()
    elseif t.id == "typing" then
        -- inline: back to typing (the drawing kept, given back to the journal)
        Log.info("drawing: inline, back to typing")
        self:done()
    elseif t.id == "done" then self:done()
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
    elseif t.id == "newpage" or t.id == "newpage2" then self.flyout = nil; self:newPage() end
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
    self._closed = true
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
    -- pages deleted here: gone from Memos too; a new one's waiting file with it
    for _i, p in ipairs(self.gone or {}) do
        if p.att then results[#results + 1] = { att = p.att, removed = true, changed = true }
        elseif p.path then os.remove(p.path) end
    end
    results.reordered = self.reordered or nil
    self:close()
    if self.on_done then self.on_done(results) end
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
        inline = opts.inline, -- { rect }: drawn in a box on the screen under it (a journal entry)
        on_done = on_done and function(res)
            for _i, p in ipairs(gone) do res[#res + 1] = p end
            -- (a new drawing: the name and tags given in the top bar)
            if w.meta then res.title, res.tags = w.meta.title, w.meta.tags end
            on_done(res)
        end }
    UIManager:show(w, opts.inline and "ui" or "full")
    return w
end

return DrawScreen
