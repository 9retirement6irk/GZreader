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

--- The paper new pages start on: the last one chosen.
function DrawScreen.lastPaper()
    return G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_paper") or "blank"
end
function DrawScreen.setLastPaper(id)
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_paper", id) end
end

DrawScreen.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/draw/"

-- the strip down the side of the page (icons; `label`: what each does, for logs and tests)
DrawScreen.SIDE_TOOLS = {
    { id = "pen", icon = "pen", label = _("Pen") },
    { id = "eraser", icon = "eraser", label = _("Eraser") },
    { id = "undo", icon = "undo", label = _("Undo") },
    { id = "redo", icon = "redo", label = _("Redo") },
    { id = "paper", icon = "paper", label = _("Paper") },
    { id = "pages", icon = "pages", label = _("All pages") },
    { id = "side", icon = "side", label = _("Move to the other side") },
    { id = "hide", icon = "hide", label = _("Hide the toolbar") },
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

DrawScreen.WRITING_NAMES = { pen = _("Pen"), pencil = _("Pencil"), fountain = _("Fountain pen"), highlighter = _("Highlighter") }

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
    self.bar_h = self.top_h -- (the page starts under the top bar)
    self.tool_sz = S(48)
    self.canvas = { x = 0, y = self.top_h, w = sw, h = sh - self.top_h }
    self.pages = self.pages or {}
    if #self.pages == 0 then self.pages[1] = { new = true } end
    self.index = math.max(1, math.min(self.start or 1, #self.pages))
    self.gone = {} -- pages deleted here: { att, removed = true } for those in Memos
    self.toolbar_side = DrawScreen.side()
    self.toolbar_hidden = false
    self.flyout = nil -- "pen" (its widths) or "eraser" (Clear page), open beside the toolbar
    self.tool, self.width = "pen", DrawScreen.lastWidth()
    self.writing = DrawScreen.lastWriting()
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
    sk.canvas = self.canvas
    sk.pen_only = self.pen_only
    sk.holes = self.holes
    -- (the pen and its width stay as they were from page to page)
    sk.tool, sk.width, sk.color = self.tool, self.width, self.color
    sk.writing = self.writing or DrawScreen.lastWriting()
    sk.pressure_on = self.pressure_on
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

--- Lays out what's over the page: the top bar (Close, the note's name,
--- Done), the tools down one side, the page buttons at the bottom, and a
--- panel open beside the toolbar. `self.buttons`: { tool, rect, group }.
function DrawScreen:layoutBar()
    local sw, sh = self.dimen.w, self.dimen.h
    local ts, pad, gap = self.tool_sz, S(3), S(8)
    self.buttons, self.holes, self.frames = {}, {}, {}
    local function add(tool, x, y, w, h, group)
        self.buttons[#self.buttons + 1] = { tool = tool, rect = Geom:new{ x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) }, group = group }
    end
    -- the top bar
    add({ id = "cancel", icon = "close", label = _("Close") }, S(4), S(4), self.top_h - S(8), self.top_h - S(8), "top")
    local done_w = S(96)
    add({ id = "done", label = _("Done") }, sw - done_w - S(6), S(6), done_w, self.top_h - S(12), "top")
    -- the tools
    local tools = self.toolbar_hidden and { { id = "show", icon = self.toolbar_side == "left" and "show" or "hide", label = _("Show the toolbar") } }
        or DrawScreen.SIDE_TOOLS
    local tw, th = ts + 2 * pad, #tools * ts + 2 * pad
    local tx = self.toolbar_side == "left" and gap or (sw - gap - tw)
    local ty = self.top_h + S(12)
    self.frames.toolbar = Geom:new{ x = tx, y = ty, w = tw, h = th }
    for k, t in ipairs(tools) do add(t, tx + pad, ty + pad + (k - 1) * ts, ts, ts, "toolbar") end
    -- the pages: ◀ 2 / 3 ▶ +
    local lw = S(84)
    local pw = 3 * ts + lw + 2 * pad
    local px, py = math.floor((sw - pw) / 2), sh - ts - 2 * pad - S(10)
    self.frames.pill = Geom:new{ x = px, y = py, w = pw, h = ts + 2 * pad }
    add({ id = "prev", icon = "left", label = _("Previous page") }, px + pad, py + pad, ts, ts, "pill")
    add({ id = "page", passive = true }, px + pad + ts, py + pad, lw, ts, "pill")
    add({ id = "next", icon = "right", label = _("Next page") }, px + pad + ts + lw, py + pad, ts, ts, "pill")
    add({ id = "newpage", icon = "plus", label = _("New page") }, px + pad + 2 * ts + lw, py + pad, ts, ts, "pill")
    -- a panel beside the toolbar
    if self.flyout and not self.toolbar_hidden then
        local fw, fh, row
        local head = S(30)
        if self.flyout == "pen" then
            -- (a row of writing tools above the thicknesses)
            fw, fh = #Sketch.WIDTHS * (ts + S(6)) + S(18), head + 2 * ts + S(28)
            if self.has_color then -- a second row: the colours
                fw, fh = math.max(fw, #Sketch.COLORS * (ts + S(6)) + S(18)), fh + ts + S(8)
            end
            if self.pen_only then -- a Kindle with a pen: pressure and tilt, on or off
                fw, fh = math.max(fw, S(300)), fh + ts + S(8)
            end
        else
            fw, fh = S(200), head + ts + S(20)
        end
        local anchor = self.flyout == "pen" and 1 or 2
        local fx = self.toolbar_side == "left" and (tx + tw + gap) or (tx - gap - fw)
        local fy = ty + pad + (anchor - 1) * ts
        self.frames.flyout = Geom:new{ x = fx, y = fy, w = fw, h = fh }
        row = fy + head + S(8)
        if self.flyout == "pen" then
            for k, id in ipairs(Sketch.TOOL_IDS) do
                add({ id = "t-" .. id, writing = id, icon = Sketch.TOOL_STYLE[id].icon, label = DrawScreen.WRITING_NAMES[id] },
                    fx + S(12) + (k - 1) * (ts + S(6)), row, ts, ts, "flyout")
            end
            row = row + ts + S(8)
            for k, w in ipairs(Sketch.WIDTHS) do
                add({ id = "w" .. tostring(w), width = w, label = DrawScreen.WIDTH_NAMES[k] }, fx + S(12) + (k - 1) * (ts + S(6)), row, ts, ts, "flyout")
            end
            if self.has_color then
                for k, col in ipairs(Sketch.COLORS) do
                    add({ id = "c-" .. col.id, color = col.value, label = col.id }, fx + S(12) + (k - 1) * (ts + S(6)), row + ts + S(8), ts, ts, "flyout")
                end
            end
            if self.pen_only then
                add({ id = "pressure", label = self.pressure_on and _("Pressure and tilt: on") or _("Pressure and tilt: off") },
                    fx + S(12), row + (self.has_color and 2 or 1) * (ts + S(8)), fw - S(24), ts, "flyout")
            end
        else
            add({ id = "clear", label = _("Clear the page") }, fx + S(12), row, fw - S(24), ts, "flyout")
        end
    end
    for _k, r in pairs(self.frames) do self.holes[#self.holes + 1] = r end
    if self.sketch then self.sketch.holes = self.holes end
end

DrawScreen.WIDTH_NAMES = { _("Extra thin"), _("Thin"), _("Medium"), _("Thick"), _("Extra thick") }

function DrawScreen:selected(t)
    local sk = self.sketch
    if t.writing then return sk.tool == "pen" and (sk.writing or "pen") == t.writing end
    if t.width then return sk.tool == "pen" and sk.width == t.width end
    if t.color then return sk.tool == "pen" and Sketch.inkColor(t.color) == sk.color end
    if t.id == "pen" then return sk.tool == "pen" end
    if t.id == "eraser" then return sk.tool == "eraser" end
    return false
end

function DrawScreen:enabled(t)
    if t.id == "undo" then return self.sketch:canUndo() end
    if t.id == "redo" then return self.sketch:canRedo() end
    if t.id == "clear" then return #self.sketch:live() > 0 end
    if t.id == "prev" then return self.index > 1 end
    if t.id == "next" then return self.index < #self.pages end
    return true
end

--- A button's text (the page number).
function DrawScreen:label(t)
    if t.id == "page" then return self.index .. " / " .. #self.pages end
    return t.label
end

--- The note's name in the top bar, and what draws under it.
function DrawScreen:heading() return self.title and self.title ~= "" and self.title or _("Drawing") end
function DrawScreen:hint()
    local paper = Notepaper.get(self.sketch:paper())
    local on = paper and paper.id ~= "blank" and paper.label or nil
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

local function textAt(bb, x, y, w, h, text, size, bold, color)
    local tw = TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = bold, fgcolor = color or Blitbuffer.COLOR_BLACK,
        max_width = w }
    local sz = tw:getSize()
    tw:paintTo(bb, x + math.floor((w - sz.w) / 2), y + math.floor((h - sz.h) / 2))
    tw:free()
end

function DrawScreen:paintButton(bb, x, y, b)
    local t, r = b.tool, b.rect
    local sel, on = self:selected(t), self:enabled(t)
    local bx, by = x + r.x, y + r.y
    if t.icon then
        local isz = math.floor(r.h * 0.56)
        -- (the toolbar's pen shows the writing tool in hand)
        local icon = t.id == "pen" and Sketch.toolStyle(self.writing).icon or t.icon
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
        bb:paintBorder(bx, by, r.w, r.h, sel and Size.border.thick or Size.border.thin, sel and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, S(6))
        local d = math.max(1, self.sketch:radius(t.width))
        bb:paintRoundedRect(bx + math.floor(r.w / 2) - d, by + math.floor(r.h / 2) - d, 2 * d + 1, 2 * d + 1, Blitbuffer.COLOR_BLACK, d)
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
    bb:paintRect(x, y, sw, self.top_h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x, y + self.top_h - Size.line.medium, sw, Size.line.medium, Blitbuffer.COLOR_BLACK)
    local left, right = self.top_h + S(6), S(96) + S(16)
    textAt(bb, x + left, y + S(4), sw - left - right, S(24), self:heading(), 17, true)
    textAt(bb, x + left, y + S(27), sw - left - right, S(20), self:hint(), 12, false, Blitbuffer.COLOR_DARK_GRAY)
    for _i, name in ipairs({ "toolbar", "pill", "flyout" }) do
        local f = self.frames[name]
        if f then
            local radius = name == "pill" and math.floor(f.h / 2) or S(10)
            bb:paintRoundedRect(x + f.x, y + f.y, f.w, f.h, Blitbuffer.COLOR_WHITE, radius)
            bb:paintBorder(x + f.x, y + f.y, f.w, f.h, name == "flyout" and Size.border.thick or Size.border.thin, Blitbuffer.COLOR_BLACK, radius)
        end
    end
    if self.frames.flyout then
        local f = self.frames.flyout
        textAt(bb, x + f.x + S(12), y + f.y + S(6), f.w - S(24), S(24),
            self.flyout == "pen" and (self.has_color and _("Writing tool, thickness and colour") or _("Writing tool and thickness"))
                or _("Eraser: rubs out whole strokes"), 14, true)
    end
    for _i, b in ipairs(self.buttons) do self:paintButton(bb, x, y, b) end
end

function DrawScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local c = self.canvas
    bb:blitFrom(self.canvas_bb, x + c.x, y + c.y, 0, 0, c.w, c.h)
    self:paintBar(bb, x, y)
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
function DrawScreen:inkGray(seg, screen_bb, rows, tint)
    local c = self.sketch.canvas
    local r, gray = seg[5], seg[7]
    local g8 = Blitbuffer.Color8(gray)
    local cw, ch = self.ink_bb:getWidth(), self.ink_bb:getHeight()
    local sw, sh = screen_bb and screen_bb:getWidth() or 0, screen_bb and screen_bb:getHeight() or 0
    local function darken(bb, x, y, bw, bh)
        if x < 0 or y < 0 or x >= bw or y >= bh then return end
        if bb:getPixel(x, y):getColor8().a > gray then bb:setPixel(x, y, g8) end
    end
    for _i, p in ipairs(Sketch.stamps(seg[1], seg[2], seg[3], seg[4], r)) do
        local under = screen_bb and self:underControls(p[1], p[2], r)
        for dy = -r, r do
            local dx = rows[dy]
            local px, py = p[1] - dx - c.x, p[2] + dy - c.y
            for k = 0, 2 * dx do
                local before = (px + k >= 0 and py >= 0 and px + k < cw and py < ch) and self.ink_bb:getPixel(px + k, py):getColor8().a
                if before and before > gray then
                    self.ink_bb:setPixel(px + k, py, g8)
                    if tint then self.tint_bb:setPixel(px + k, py, tint) end
                end
                darken(self.canvas_bb, px + k, py, cw, ch)
                if screen_bb and not under then darken(screen_bb, p[1] - dx + k, p[2] + dy, sw, sh) end
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
        local pr = Sketch.toolRadius(st.kind, r, b[3] and (a[3] and (a[3] + b[3]) / 2 or b[3]) or nil)
        out[#out + 1] = { a[1] + c.x, a[2] + c.y, b[1] + c.x, b[2] + c.y, pr, st.color, gray }
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
    if self.tint_bb then self.tint_bb:free(); self.tint_bb = nil end
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
        -- (the pen's side button, as KOReader reads it: BTN_STYLUS or BTN_STYLUS2; held, the pen rubs out)
        if screen.sketch then
            local held = input.stylus_eraser_active == true or input.stylus_highlighter_active == true
            if held ~= screen.sketch.side_button then
                Log.info("drawing: the pen's side button", held and "held (rubs out)" or "let go",
                    input.stylus_eraser_active and "BTN_STYLUS" or input.stylus_highlighter_active and "BTN_STYLUS2" or "")
            end
            screen.sketch.side_button = held
        end
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
        slots[#slots + 1] = { slot = tev.slot, id = tev.id, x = x, y = y, tool = tev.tool,
            pressure = tev.gz_pressure, tilt_x = tev.gz_tilt_x, tilt_y = tev.gz_tilt_y }
        if tev.timev and not now then now = time.to_s(tev.timev) end
    end
    now = now or time.to_s(time.now())
    local out = self.sketch:frame(slots, now)
    self:apply(out)
end

local function intersects(a, x0, y0, x1, y1)
    return x1 >= a.x and x0 < a.x + a.w and y1 >= a.y and y0 < a.y + a.h
end

function DrawScreen:apply(out)
    if (out.redraw or #out.segments > 0) and self.flyout then
        -- drawing puts an open panel away
        self.flyout = nil
        self:layoutBar()
        out.redraw = true
    end
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
    if out.stroke_done then
        -- Undo and Redo wake up or go to sleep
        local shown = self._shown or {}
        if shown.undo ~= self.sketch:canUndo() or shown.redo ~= self.sketch:canRedo() then self:refreshBar() end
    end
    for _i, tap in ipairs(out.taps) do self:tapAt(tap.x, tap.y) end
end

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
    self.flyout = which
    self:layoutBar()
    UIManager:setDirty(self, "ui")
end

--- The pen's colour ("#rrggbb"; memos' ink: its own colour or nil), kept for next time.
function DrawScreen:setColor(hex)
    self.color = Sketch.inkColor(hex)
    self.tool = "pen"
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_color", self.color or Drawing.INK) end
    self.sketch.tool, self.sketch.color = "pen", self.color
end

function DrawScreen:setTool(tool, width)
    self.tool = tool
    if width then
        self.width = width
        if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_width", width) end
    end
    self.sketch.tool, self.sketch.width = self.tool, self.width
end

--- The writing tool (Sketch.TOOL_IDS), kept for next time; the pen in hand.
function DrawScreen:setWriting(id)
    if not Sketch.TOOL_STYLE[id] then return end
    self.writing = id
    if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_writing", id) end
    self:setTool("pen")
    self.sketch.writing = id
    Log.info("drawing: writing with the", id)
end

function DrawScreen:use(t)
    local sk = self.sketch
    if t.writing then self:setWriting(t.writing); self:setFlyout("pen") -- (stays open: a thickness next)
    elseif t.width then self:setTool("pen", t.width); self:setFlyout(nil)
    elseif t.color then self:setColor(t.color); self:setFlyout(nil)
    elseif t.id == "pressure" then
        self.pressure_on = not self.pressure_on
        if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_pressure", self.pressure_on) end
        self.sketch.pressure_on = self.pressure_on
        self:setFlyout("pen") -- (laid out again: its words changed)
    elseif t.id == "pen" then
        -- the pen; again: its thickness
        if sk.tool == "pen" then self:setFlyout(self.flyout ~= "pen" and "pen" or nil) else self:setTool("pen"); self:setFlyout(nil) end
    elseif t.id == "eraser" then
        -- the eraser; again: Clear the page
        if sk.tool == "eraser" then self:setFlyout(self.flyout ~= "eraser" and "eraser" or nil) else self:setTool("eraser"); self:setFlyout(nil) end
    elseif t.id == "undo" then if sk:undo() then self:touched(); self:redrawAll() end
    elseif t.id == "redo" then if sk:redo() then self:touched(); self:redrawAll() end
    elseif t.id == "clear" then
        self.flyout = nil
        self:layoutBar()
        if sk:clear() then self:touched() end
        self:redrawAll()
    elseif t.id == "cancel" then self:cancel()
    elseif t.id == "done" then self:done()
    elseif t.id == "paper" then self:pickPaper()
    elseif t.id == "pages" then self:showPages()
    elseif t.id == "side" then
        self.toolbar_side = self.toolbar_side == "left" and "right" or "left"
        if G_reader_settings then G_reader_settings:saveSetting("gzreader_drawing_toolbar_side", self.toolbar_side) end
        self:setFlyout(nil)
    elseif t.id == "hide" or t.id == "show" then
        self.toolbar_hidden = t.id == "hide"
        self:setFlyout(nil)
    elseif t.id == "prev" then if self.index > 1 then self:showPage(self.index - 1) end
    elseif t.id == "next" then if self.index < #self.pages then self:showPage(self.index + 1) end
    elseif t.id == "newpage" then self:newPage() end
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
    local w = DrawScreen:new{ pages = pages, start = opts.start, on_cancel = opts.on_cancel, title = opts.title,
        on_done = on_done and function(res)
            for _i, p in ipairs(gone) do res[#res + 1] = p end
            on_done(res)
        end }
    UIManager:show(w, "full")
    return w
end

return DrawScreen
