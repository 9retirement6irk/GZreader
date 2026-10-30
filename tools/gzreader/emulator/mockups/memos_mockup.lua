--[[--
Mockup of a Memos tab for GZreader (sample data, no network): a board of
sticky notes, an expanded note, filters and a new memo. For screenshots in
the emulator (memos_shots.lua); nothing here talks to a Memos server.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local M = {}

-- ZenOS's icon font (a subset of Symbols Nerd Font: no pin, paperclip or map
-- marker yet, so the nearest it has: star = pinned, location arrow = place,
-- file = attachment, tag-multiple = tags)
local ICON_FONT = "./plugins/zenos.koplugin/fonts/SymbolsNerdFont-Regular.ttf"
local ICONS = { pin = "\u{F04CE}", place = "\u{F124}", attach = "\u{F0224}", pdf = "\u{F0224}", image = "\u{F02F5}",
    tag = "\u{F12F7}", date = "\u{F073}" }
-- handwriting (Patrick Hand, SIL Open Font License) for the notes themselves;
-- it has one weight, so "bold" is KOReader's synthetic bold (TextWidget bold)
local HAND = "./fonts/handwriting/PatrickHand-Regular.ttf"
local function hand(size)
    local ok, face = pcall(Font.getFace, Font, HAND, size)
    return ok and face or Font:getFace("cfont", size)
end

local function icon(name, size)
    local ok, face = pcall(Font.getFace, Font, ICON_FONT, size)
    return TextWidget:new{ text = ICONS[name], face = ok and face or Font:getFace("cfont", size) }
end
local function iconText(name, text, size, opts)
    opts = opts or {}
    return HorizontalGroup:new{ align = "center", icon(name, size), HorizontalSpan:new{ width = S(5) },
        TextWidget:new{ text = text, face = opts.face or Font:getFace("cfont", size), bold = opts.bold,
            fgcolor = opts.fgcolor, max_width = opts.max_width } }
end

---------------------------------------------------------------- inline images

-- Markdown images (![alt](url)) in a note: in Memos they are attachments
-- (/file/attachments/…) or links; GZreader would download each once, keep it,
-- and show it shrunk to fit. Here the "url" is a local sample file.
local function imageOf(text)
    return text:match("!%[[^%]]*%]%(([^%)]+)%)")
end
local function withoutImages(text)
    return (text:gsub("\n?!%[[^%]]*%]%([^%)]+%)", ""))
end
local function imageWidget(path, max_w, max_h)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a"); f:close()
    local RenderImage = require("ui/renderimage")
    local bb = RenderImage:renderImageData(data, #data, false)
    if not bb then return nil end
    local sc = math.min(max_w / bb:getWidth(), max_h / bb:getHeight(), 1)
    bb = RenderImage:scaleBlitBuffer(bb, math.floor(bb:getWidth() * sc), math.floor(bb:getHeight() * sc), true)
    return FrameContainer:new{ padding = 0, bordersize = Size.border.thin,
        require("ui/widget/imagewidget"):new{ image = bb, image_disposable = true } }
end
M.imageWidget = imageWidget

---------------------------------------------------------------- sticky notes

local ffi = require("ffi")
local ImageWidget = require("ui/widget/imagewidget")

--- `src` (an 8-bit gray image) turned by `deg` degrees, on white, smoothed
--- (bilinear). KOReader only turns images by 90°, so this does it by hand:
--- a few hundred thousand pixels per page, kept while the board is open.
local function rotate(src, deg)
    local a = math.rad(deg)
    local ca, sa = math.cos(a), math.sin(a)
    local sw, sh = src:getWidth(), src:getHeight()
    local dw = math.ceil(math.abs(sw * ca) + math.abs(sh * sa))
    local dh = math.ceil(math.abs(sw * sa) + math.abs(sh * ca))
    local dst = Blitbuffer.new(dw, dh, Blitbuffer.TYPE_BB8)
    local sp, ss = ffi.cast("uint8_t*", src.data), tonumber(src.stride)
    local dp, ds = ffi.cast("uint8_t*", dst.data), tonumber(dst.stride)
    local scx, scy, dcx, dcy = sw / 2, sh / 2, dw / 2, dh / 2
    for y = 0, dh - 1 do
        local ry = y - dcy
        local row = y * ds
        for x = 0, dw - 1 do
            local rx = x - dcx
            local fx = ca * rx + sa * ry + scx
            local fy = -sa * rx + ca * ry + scy
            local x0, y0 = math.floor(fx), math.floor(fy)
            local v = 255
            if x0 >= 0 and y0 >= 0 and x0 < sw - 1 and y0 < sh - 1 then
                local tx, ty = fx - x0, fy - y0
                local i = y0 * ss + x0
                local top = sp[i] + (sp[i + 1] - sp[i]) * tx
                local bot = sp[i + ss] + (sp[i + ss + 1] - sp[i + ss]) * tx
                v = top + (bot - top) * ty
            end
            dp[row + x] = v
        end
    end
    return dst
end

--- A note as paper: soft shadow, the note, a strip of tape; then tilted.
local function stickyImage(widget, w, h, opts)
    local m = S(10)
    local canvas = Blitbuffer.new(w + 2 * m, h + 2 * m, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    canvas:paintRect(m + S(4), m + S(5), w, h, Blitbuffer.gray(0.30)) -- shadow
    widget:paintTo(canvas, m, m)
    if opts.tape then
        local tw, th = S(70), S(18)
        local tx = m + math.floor((w - tw) / 2) + (opts.tape_shift or 0)
        canvas:paintRect(tx, m - th / 2, tw, th, Blitbuffer.gray(0.22))
        canvas:paintRect(tx, m - th / 2, tw, 1, Blitbuffer.gray(0.40))
        canvas:paintRect(tx, m + th / 2 - 1, tw, 1, Blitbuffer.gray(0.40))
    end
    local img = rotate(canvas, opts.angle or 0)
    canvas:free()
    return img
end

-- each note's look, by its place on the page (same every time)
M.LOOK = {
    { angle = -2.4, shade = 0.10, tape = true, tape_shift = -20, dx = -4, dy = 2 },
    { angle = 1.9, shade = 0.00, tape = false, dx = 3, dy = -2 },
    { angle = 1.2, shade = 0.04, tape = false, dx = 2, dy = 3 },
    { angle = -1.7, shade = 0.16, tape = true, tape_shift = 25, dx = -3, dy = 0 },
    { angle = 2.6, shade = 0.12, tape = true, tape_shift = 5, dx = 4, dy = -3 },
    { angle = -1.1, shade = 0.02, tape = false, dx = -2, dy = 2 },
}

M.MEMOS = {
    { id = 1, date = "Today 9:12 PM", pinned = true, tags = { "reading" },
      text = "Finish A Walk in the Woods before the trip. Bryson's chapter on the Smokies is the funniest so far.",
      place = nil, attachments = {} },
    { id = 2, date = "Today 2:40 PM", tags = { "travel", "hiking" }, place = "Amicalola Falls",
      text = "Trail plan for the Georgia section. Permit is booked. Map and gear list attached.",
      attachments = { { name = "Trail map.pdf", kind = "pdf", size = "34 KB" } } },
    { id = 3, date = "Yesterday", tags = { "quotes" },
      text = "\"The woods were full of ghosts.\" Think about using this as the opening line.", attachments = {} },
    { id = 4, date = "Oct 27", tags = { "ideas", "gzreader" },
      text = "Notes tab for the Kindle: sticky notes, open with a letter key, filter by tag.", attachments = {} },
    { id = 5, date = "Oct 25", tags = { "shopping" }, place = "Home",
      text = "- [ ] headlamp batteries\n- [x] water filter\n- [ ] wool socks", attachments = {} },
    { id = 6, date = "Oct 22", tags = { "work" }, place = "Library",
      text = "Receipt for the conference registration, for expenses.\n![receipt](/root/work/emu/mock/receipt.jpg)",
      attachments = { { name = "receipt.jpg", kind = "image", size = "210 KB" } } },
}

local function noteText(m, max)
    local t = m.text:gsub("%- %[ %]", "☐"):gsub("%- %[x%]", "☑")
    if max and #t > max then t = t:sub(1, max):gsub("%s+%S*$", "") .. "…" end
    return t
end

local function tagLine(m)
    local t = {}
    for _i, tag in ipairs(m.tags) do t[#t + 1] = "#" .. tag end
    return table.concat(t, "  ")
end

local function footerRow(m, size)
    local row = HorizontalGroup:new{ align = "center" }
    if m.place then row[#row + 1] = iconText("place", m.place, size) end
    if #m.attachments > 0 then
        if #row > 0 then row[#row + 1] = HorizontalSpan:new{ width = S(12) } end
        row[#row + 1] = iconText("attach", tostring(#m.attachments), size)
    end
    if #row == 0 then row[1] = TextWidget:new{ text = " ", face = Font:getFace("cfont", size) } end
    return row
end

---------------------------------------------------------------- the board

local Board = InputContainer:extend{ covers_fullscreen = true, filter_label = "All notes" }

function Board:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self:build()
end

function Board:note(m, key, w, h, look)
    local shade = look.shade > 0 and Blitbuffer.gray(look.shade) or Blitbuffer.COLOR_WHITE
    local pad = S(8)
    local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = S(24), h = S(24) }, key, "square")
    local inner_w = w - 2 * pad - 2 * Size.border.thin
    local head = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = S(24) },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            HorizontalGroup:new{ sc, HorizontalSpan:new{ width = S(6) },
                TextWidget:new{ text = m.date, face = hand(15), fgcolor = Blitbuffer.COLOR_DARK_GRAY } } },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            m.pinned and icon("pin", 15) or HorizontalSpan:new{ width = 0 } },
    }
    local body_h = h - S(24) - S(22) - S(20) - 3 * pad
    local img_path = imageOf(m.text)
    local thumb = img_path and imageWidget(img_path, inner_w, math.floor(body_h * 0.55))
    local text_h = thumb and (body_h - thumb:getSize().h - S(4)) or body_h
    local body = TextBoxWidget:new{ text = noteText({ text = withoutImages(m.text) }), face = hand(19), width = inner_w,
        height = text_h, height_adjust = false, height_overflow_show_ellipsis = true, bgcolor = shade }
    if thumb then
        body = VerticalGroup:new{ align = "left", body, VerticalSpan:new{ width = S(4) }, thumb }
    end
    local paper = FrameContainer:new{
        width = w, height = h, padding = pad, margin = 0, bordersize = Size.border.thin,
        radius = 0, background = shade, color = Blitbuffer.COLOR_DARK_GRAY,
        VerticalGroup:new{ align = "left",
            head,
            VerticalSpan:new{ width = S(6) },
            body,
            VerticalSpan:new{ width = S(4) },
            TextWidget:new{ text = tagLine(m), face = hand(16), bold = true, max_width = inner_w },
            footerRow(m, 13),
        },
    }
    -- paper, not a box: a shadow, sometimes tape, and a small tilt
    local img = stickyImage(paper, w, h, look)
    paper:free()
    return ImageWidget:new{ image = img, image_disposable = true }
end

function Board:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local margin = S(10)
    local gap = S(10)
    local title_h = S(46)
    local footer_h = S(36)
    local cols, rows = 2, 3
    local cell_w = math.floor((sw - 2 * margin - (cols - 1) * gap) / cols)
    local cell_h = math.floor((sh - title_h - footer_h - 2 * margin - (rows - 1) * gap) / rows)
    local keys = { "Q", "W", "E", "R", "T", "Y" }
    local grid = VerticalGroup:new{ align = "left" }
    -- notes a little smaller than their cell: room for the tilt and the nudge
    local note_w, note_h = math.floor(cell_w * 0.88), math.floor(cell_h * 0.86)
    for r = 1, rows do
        local row = HorizontalGroup:new{ align = "top" }
        for c = 1, cols do
            local i = (r - 1) * cols + c
            local m = (self.memos or M.MEMOS)[i]
            if m then
                local look = M.LOOK[i]
                local note = self:note(m, keys[i], note_w, note_h, look)
                row[#row + 1] = CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h },
                    HorizontalGroup:new{ HorizontalSpan:new{ width = math.max(0, S(look.dx) * 2) },
                        VerticalGroup:new{ VerticalSpan:new{ width = math.max(0, S(look.dy) * 2) }, note } } }
                if c < cols then row[#row + 1] = HorizontalSpan:new{ width = gap } end
            end
        end
        grid[#grid + 1] = row
        if r < rows then grid[#grid + 1] = VerticalSpan:new{ width = gap } end
    end
    local title = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = title_h },
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
            TextWidget:new{ text = "Notes", face = Font:getFace("smalltfont", 22), bold = true } },
        LeftContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = margin },
                TextWidget:new{ text = self.filter_label, face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY } } },
        RightContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
            HorizontalGroup:new{ TextWidget:new{ text = "1 / 7", face = Font:getFace("cfont", 14) }, HorizontalSpan:new{ width = margin } } },
    }
    local footer = CenterContainer:new{ dimen = Geom:new{ w = sw, h = footer_h },
        TextWidget:new{ text = "N  new note    F  filter    Menu  more    ◀ ▶  pages",
            face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY } }
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "center",
            title,
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh - title_h - footer_h }, grid },
            footer,
        },
    }
end

function M.showBoard(opts)
    local b = Board:new(opts or {})
    UIManager:show(b, "full")
    return b
end

---------------------------------------------------------------- one note

local Note = InputContainer:extend{ covers_fullscreen = true, memo = nil, focus = nil }

-- "- [ ] text" / "- [x] text" lines are checklist items: each gets a letter
-- key; pressing it ticks or unticks the box and saves the note to Memos.
local function parseLines(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local mark, rest = line:match("^%- %[([ xX])%]%s*(.*)$")
        if mark then out[#out + 1] = { check = true, done = mark ~= " ", text = rest }
        else out[#out + 1] = { text = line } end
    end
    return out
end

function M.toggle(i, n)
    local m = M.MEMOS[i]
    local k = 0
    m.text = (m.text .. "\n"):gsub("(%- %[)([ xX])(%][^\n]*\n)", function(a, mark, b)
        k = k + 1
        if k == n then mark = mark == " " and "x" or " " end
        return a .. mark .. b
    end):gsub("\n$", "")
end

function Note:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local m = self.memo
    local inner = sw - 2 * S(24)
    local g = VerticalGroup:new{ align = "left" }
    local function add(w) g[#g + 1] = w end
    add(VerticalSpan:new{ width = S(18) })
    add(iconText("date", m.date .. (m.pinned and "   ·   pinned" or ""), 15, { fgcolor = Blitbuffer.COLOR_DARK_GRAY }))
    add(VerticalSpan:new{ width = S(12) })
    local keys = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }
    local n, para = 0, {}
    local function flush()
        local t = table.concat(para, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
        para = {}
        if t ~= "" then add(TextBoxWidget:new{ text = t, face = hand(25), width = inner }) end
    end
    for _i, l in ipairs(parseLines(m.text)) do
        local img = imageOf(l.text)
        if img then
            flush()
            local w = imageWidget(img, inner, math.floor(sh * 0.45))
            if w then add(VerticalSpan:new{ width = S(8) }); add(w); add(VerticalSpan:new{ width = S(8) }) end
        elseif l.check then
            flush()
            n = n + 1
            local focused = self.focus == n
            local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, keys[n], "square")
            add(FrameContainer:new{
                padding = S(4), margin = 0, bordersize = focused and Size.border.thick or 0, width = inner,
                HorizontalGroup:new{ align = "center", sc, HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = l.done and "\u{2611}" or "\u{2610}", face = Font:getFace("cfont", 26) },
                    HorizontalSpan:new{ width = S(8) },
                    TextWidget:new{ text = l.text, face = hand(25), max_width = inner - S(90),
                        fgcolor = l.done and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK } } })
        else
            para[#para + 1] = l.text
        end
    end
    flush()
    add(VerticalSpan:new{ width = S(14) })
    add(iconText("tag", tagLine(m), 17, { face = hand(20), bold = true }))
    if m.place then
        add(VerticalSpan:new{ width = S(6) })
        add(iconText("place", m.place, 17))
    end
    if #m.attachments > 0 then
        add(VerticalSpan:new{ width = S(18) })
        add(TextWidget:new{ text = "Attachments", face = Font:getFace("smalltfont", 17), bold = true })
        add(VerticalSpan:new{ width = S(6) })
        for i, a in ipairs(m.attachments) do
            local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, keys[n + i], "square")
            add(FrameContainer:new{ padding = S(8), bordersize = Size.border.thin, radius = S(4), width = inner,
                HorizontalGroup:new{ align = "center", sc, HorizontalSpan:new{ width = S(10) },
                    iconText(a.kind == "pdf" and "pdf" or "image", a.name, 18),
                    HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = a.size .. " · open", face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY } } })
        end
    end
    local hint = n > 0 and ("Q\u{2013}" .. keys[n] .. "  tick / untick (saved to Memos)    E  edit    Back  board")
        or "Alt+E  edit    P  pin    Back  board"
    local footer = CenterContainer:new{ dimen = Geom:new{ w = sw, h = S(36) },
        TextWidget:new{ text = hint, face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY } }
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = S(46) },
                TextWidget:new{ text = "Note", face = Font:getFace("smalltfont", 22), bold = true } },
            LeftContainer:new{ dimen = Geom:new{ w = sw, h = sh - S(46) - S(36) },
                HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = S(24) },
                    require("ui/widget/container/topcontainer"):new{ dimen = Geom:new{ w = inner, h = sh - S(46) - S(36) }, g } } },
            footer,
        },
    }
end

function M.showNote(i, focus)
    local n = Note:new{ memo = M.MEMOS[i], focus = focus }
    UIManager:show(n, "full")
    return n
end

---------------------------------------------------------------- filters

local function keyed(dialog)
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    return dialog
end

function M.showFilters()
    local function row(text) return { { text = text, align = "left", callback = function() end } } end
    local d = keyed(ButtonDialog:new{
        title = "Show notes",
        buttons = {
            row("All notes  ✓"),
            row("Tag: #reading, #travel, #ideas …  ›"),
            row("Date: today, this week, a month …  ›"),
            row("Place: Home, Library, Amicalola Falls …  ›"),
            row("With attachments (PDF, images)"),
            row("Pinned"),
            row("Search text…"),
        },
    })
    UIManager:show(d)
    return d
end

--- The # Tag button: your tags with letter keys, or a new one.
function M.showTagPicker()
    local rows = {}
    for _i, t in ipairs({ "travel", "hiking", "reading", "ideas", "quotes", "work" }) do
        rows[#rows + 1] = { { text = "#" .. t, align = "left", callback = function() end } }
    end
    rows[#rows + 1] = { { text = "New tag…", align = "left", callback = function() end } }
    local d = keyed(ButtonDialog:new{ title = "Add a tag", buttons = rows })
    UIManager:show(d)
    return d
end

local Blank = InputContainer:extend{ covers_fullscreen = true }
function Blank:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self[1] = FrameContainer:new{ width = self.dimen.w, height = self.dimen.h, bordersize = 0, padding = 0,
        background = Blitbuffer.COLOR_WHITE, VerticalSpan:new{ width = 0 } }
end

function M.showTags()
    local blank = Blank:new{}
    UIManager:show(blank, "full")
    local items = {}
    for _i, t in ipairs({ { "reading", 12 }, { "travel", 7 }, { "ideas", 9 }, { "quotes", 15 }, { "work", 4 },
            { "hiking", 3 }, { "shopping", 6 }, { "gzreader", 2 } }) do
        items[#items + 1] = { text = "#" .. t[1], mandatory = t[2] .. " notes" }
    end
    local menu = Menu:new{ title = "Filter by tag", item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = false, -- (so the white page under it is drawn; ZenOS keeps the bottom for its tab bar)
        title_bar_fm_style = true, close_callback = function() UIManager:close(blank) end }
    UIManager:show(menu, "full")
    local orig = menu.onCloseWidget
    menu.onCloseWidget = function(...) UIManager:close(blank); if orig then return orig(...) end end
    return menu
end

---------------------------------------------------------------- new / edit

--[[ Full-page editor. The text is Memos' Markdown. Above it, a toolbar:
     • List  ☐ Check  1. Numbered  H Heading  I Italic  B Bold  |  Save
   The toolbar is at the bottom: ▼ from the last line (or Alt + ▼) moves to
   it; ◀ ▶ choose, Press applies to the current line or selection, ▲ goes
   back to the text.
   Shortcuts from anywhere: Alt+L list, Alt+C checklist, Alt+N numbered,
   Alt+H heading, Alt+I italic, Alt+B bold, Alt+S save. ]]

M.TOOLS = {
    { id = "list", label = "\u{2022} List", key = "Alt+L", md = "- " },
    { id = "check", label = "\u{2610} Check", key = "Alt+C", md = "- [ ] " },
    { id = "numbered", label = "1. Num", key = "Alt+N", md = "1. " },
    { id = "heading", label = "H Head", key = "Alt+H", md = "## " },
    { id = "italic", label = "I", key = "Alt+I", md = "*…*", italic = true },
    { id = "bold", label = "B", key = "Alt+B", md = "**…**", bold = true },
    { id = "tag", label = "# Tag", key = "Alt+G", md = "#tag (the Kindle keyboard has no # key)" },
}

local Editor = InputContainer:extend{ covers_fullscreen = true, title = "New note", text = "", focus_tool = nil,
    visibility = "Private" }

function Editor:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local margin = S(12)
    local inner = sw - 2 * margin
    -- title row: what this is, and where it goes
    local title_h = S(44)
    local title = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = title_h },
        LeftContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = margin },
                TextWidget:new{ text = self.title, face = Font:getFace("smalltfont", 21), bold = true } } },
        RightContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
            HorizontalGroup:new{ TextWidget:new{ text = self.visibility .. "  \u{25BE}", face = Font:getFace("cfont", 15) },
                HorizontalSpan:new{ width = margin } } },
    }
    -- the toolbar, then Save, on one row
    local tool_h = S(40)
    local bar = HorizontalGroup:new{ align = "center" }
    local save_w = S(70)
    local tool_w = math.floor((inner - save_w - S(10)) / #M.TOOLS)
    for i, t in ipairs(M.TOOLS) do
        local focused = self.focus_tool == i
        local txt = TextWidget:new{ text = t.label, face = Font:getFace(t.italic and "infofont" or "cfont", 15),
            bold = t.bold or focused, fgcolor = focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK }
        if t.italic then txt = TextWidget:new{ text = "I", face = Font:getFace("./fonts/noto/NotoSerif-Italic.ttf", 19),
            fgcolor = focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } end
        bar[#bar + 1] = FrameContainer:new{
            width = tool_w, height = tool_h, padding = 0, margin = 0, bordersize = Size.border.thin,
            background = focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{ dimen = Geom:new{ w = tool_w - 2, h = tool_h - 2 }, txt },
        }
    end
    bar[#bar + 1] = HorizontalSpan:new{ width = S(10) }
    local save_focused = self.focus_tool == #M.TOOLS + 1
    bar[#bar + 1] = FrameContainer:new{
        width = save_w, height = tool_h, padding = 0, bordersize = Size.border.thick, radius = S(6),
        background = save_focused and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{ dimen = Geom:new{ w = save_w - 4, h = tool_h - 4 },
            TextWidget:new{ text = "Save", face = Font:getFace("cfont", 18), bold = true,
                fgcolor = save_focused and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK } },
    }
    local hint_tool = self.focus_tool and M.TOOLS[self.focus_tool]
    local hint = hint_tool and (hint_tool.label:gsub("^%S+%s*", "") .. ": " .. hint_tool.md .. "   (" .. hint_tool.key .. ")   ·   \u{25C0} \u{25B6} choose   Press apply   \u{25B2} text")
        or (self.focus_tool and "Save to Memos   (Alt+S)   ·   \u{25B2} back to the text")
        or "\u{25BC} toolbar   ·   Alt+G tag  Alt+C check  Alt+B bold  Alt+S save"
    -- the text
    local footer_h = S(30)
    local text_h = sh - title_h - tool_h - footer_h - S(28)
    local InputText = require("ui/widget/inputtext")
    self.input = InputText:new{
        text = self.text, width = inner, height = text_h, scroll = true, face = Font:getFace("cfont", 20),
        parent = self, focused = not self.focus_tool, padding = S(8), margin = 0, bordersize = Size.border.thin,
        hint = "Write a note. #tags become tags.",
    }
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "center",
            title,
            self.input,
            VerticalSpan:new{ width = S(10) },
            bar, -- at the bottom: ▼ from the last line reaches it, ▲ goes back to the text
            VerticalSpan:new{ width = S(8) },
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = footer_h },
                TextWidget:new{ text = hint, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    max_width = inner } },
        },
    }
end

function M.showNew(opts)
    local e = Editor:new(opts or {})
    UIManager:show(e, "full")
    return e
end

function M.showEdit(i, focus_tool)
    local m = M.MEMOS[i]
    local md = "## Georgia section\n\n" .. m.text .. "\n\n- [x] permit\n- [ ] trail map printed\n- [ ] **bear bag**\n\n#travel #hiking"
    local e = Editor:new{ title = "Edit note", text = md, focus_tool = focus_tool }
    UIManager:show(e, "full")
    return e
end

return M
