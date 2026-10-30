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
local function icon(name, size)
    local ok, face = pcall(Font.getFace, Font, ICON_FONT, size)
    return TextWidget:new{ text = ICONS[name], face = ok and face or Font:getFace("cfont", size) }
end
local function iconText(name, text, size, opts)
    opts = opts or {}
    return HorizontalGroup:new{ align = "center", icon(name, size), HorizontalSpan:new{ width = S(5) },
        TextWidget:new{ text = text, face = Font:getFace("cfont", size), bold = opts.bold, fgcolor = opts.fgcolor,
            max_width = opts.max_width } }
end

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
      text = "Receipt for the conference registration, for expenses.",
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

function Board:note(m, key, w, h, shade)
    local pad = S(8)
    local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = S(24), h = S(24) }, key, "square")
    local inner_w = w - 2 * pad - 2 * Size.border.thin
    local head = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = S(24) },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            HorizontalGroup:new{ sc, HorizontalSpan:new{ width = S(6) },
                TextWidget:new{ text = m.date, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY } } },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            m.pinned and icon("pin", 15) or HorizontalSpan:new{ width = 0 } },
    }
    local body_h = h - S(24) - S(22) - S(20) - 3 * pad
    local body = TextBoxWidget:new{ text = noteText(m), face = Font:getFace("cfont", 16), width = inner_w,
        height = body_h, height_adjust = false, height_overflow_show_ellipsis = true, bgcolor = shade }
    return FrameContainer:new{
        width = w, height = h, padding = pad, margin = 0, bordersize = Size.border.thin,
        radius = S(4), background = shade, color = Blitbuffer.COLOR_DARK_GRAY,
        VerticalGroup:new{ align = "left",
            head,
            VerticalSpan:new{ width = S(6) },
            body,
            VerticalSpan:new{ width = S(4) },
            TextWidget:new{ text = tagLine(m), face = Font:getFace("cfont", 13), bold = true, max_width = inner_w },
            footerRow(m, 13),
        },
    }
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
    local shades = { Blitbuffer.gray(0.12), Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_WHITE, Blitbuffer.gray(0.12),
        Blitbuffer.gray(0.12), Blitbuffer.COLOR_WHITE }
    local grid = VerticalGroup:new{ align = "left" }
    for r = 1, rows do
        local row = HorizontalGroup:new{ align = "top" }
        for c = 1, cols do
            local i = (r - 1) * cols + c
            local m = (self.memos or M.MEMOS)[i]
            if m then
                row[#row + 1] = self:note(m, keys[i], cell_w, cell_h, shades[i])
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
    UIManager:show(b)
    return b
end

---------------------------------------------------------------- one note

local Note = InputContainer:extend{ covers_fullscreen = true, memo = nil }

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
    add(TextBoxWidget:new{ text = noteText(m), face = Font:getFace("cfont", 21), width = inner })
    add(VerticalSpan:new{ width = S(14) })
    add(iconText("tag", tagLine(m), 17, { bold = true }))
    if m.place then
        add(VerticalSpan:new{ width = S(6) })
        add(iconText("place", m.place, 17))
    end
    local keys = { "Q", "W", "E" }
    if #m.attachments > 0 then
        add(VerticalSpan:new{ width = S(18) })
        add(TextWidget:new{ text = "Attachments", face = Font:getFace("smalltfont", 17), bold = true })
        add(VerticalSpan:new{ width = S(6) })
        for i, a in ipairs(m.attachments) do
            local sc = Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, keys[i], "square")
            add(FrameContainer:new{ padding = S(8), bordersize = Size.border.thin, radius = S(4), width = inner,
                HorizontalGroup:new{ align = "center", sc, HorizontalSpan:new{ width = S(10) },
                    iconText(a.kind == "pdf" and "pdf" or "image", a.name, 18),
                    HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = a.size .. " · open", face = Font:getFace("cfont", 14), fgcolor = Blitbuffer.COLOR_DARK_GRAY } } })
        end
    end
    local footer = CenterContainer:new{ dimen = Geom:new{ w = sw, h = S(36) },
        TextWidget:new{ text = "E  edit    P  pin    Back  board", face = Font:getFace("cfont", 14),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY } }
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = S(46) },
                TextWidget:new{ text = "Note", face = Font:getFace("smalltfont", 22), bold = true } },
            FrameContainer:new{ padding = 0, padding_left = S(24), bordersize = 0, width = sw, height = sh - S(46) - S(36), g },
            footer,
        },
    }
end

function M.showNote(i)
    local n = Note:new{ memo = M.MEMOS[i] }
    UIManager:show(n)
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

function M.showTags()
    local items = {}
    for _i, t in ipairs({ { "reading", 12 }, { "travel", 7 }, { "ideas", 9 }, { "quotes", 15 }, { "work", 4 },
            { "hiking", 3 }, { "shopping", 6 }, { "gzreader", 2 } }) do
        items[#items + 1] = { text = "#" .. t[1], mandatory = t[2] .. " notes" }
    end
    local menu = Menu:new{ title = "Filter by tag", item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = true, title_bar_fm_style = true }
    UIManager:show(menu)
    return menu
end

---------------------------------------------------------------- new note

function M.showNew()
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{
        title = "New note",
        input = "Bryson says the AT is 2,190 miles. Check how much of Georgia is doable in 3 days. #travel #hiking",
        input_hint = "Write a note. #tags become tags.",
        description = "Saved to Memos when Wi-Fi is on (kept on the Kindle until then).",
        allow_newline = true,
        buttons = { {
            { text = "Cancel", id = "close", callback = function() UIManager:close(d) end },
            { text = "Private ▾", callback = function() end },
            { text = "Save", is_enter_default = true, callback = function() UIManager:close(d) end },
        } },
    }
    UIManager:show(d)
    return d
end

return M
