--[[--
The drawing screen's top bar for the note screens on touch Kindles (the note
editor, an opened note), so all three look and work alike:

  ←  The note's name                         icons…  [Action]
     a grey line under it
  ─────────────────────────────────────────────────────────────

The drawing screen paints its own (gzreader_drawscreen.lua); this builds the
same thing from widgets, with the same icons (icons/draw/).

  NoteBar.build{ width, height, title, hint, back = fn, back_icon = "close",
      icons = { { id, icon, fn, guarded }, … }, action = { id, text, fn, guarded },
      tap = function(widget, fn, guarded) … end }
  Without a touch screen: no `back`, no icons; `note` is a grey word at the
  right (the key that has the rest: "M more").
  → the bar widget, { [id] = its tap target } (back is "back").
]]

local Screen = require("device").screen

local function S(n) return Screen:scaleBySize(n) end

local NoteBar = {}

NoteBar.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/draw/"
NoteBar.HEIGHT = 52 -- (scaled) the drawing screen's

function NoteBar.height() return S(NoteBar.HEIGHT) end

function NoteBar.build(o)
    -- (KOReader's widgets, loaded when a bar is built: the tests' stand-ins load this module without them)
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local sw, h = o.width, o.height or NoteBar.height()
    local line = Size.line.medium
    local bh = h - S(8)
    local tap = o.tap or function(w) return w end
    local buttons = {}
    local function iconButton(id, icon, fn, guarded)
        local isz = math.floor(bh * 0.56)
        local w = FrameContainer:new{ width = bh, height = bh, padding = 0, margin = 0, bordersize = 0,
            CenterContainer:new{ dimen = Geom:new{ w = bh, h = bh },
                IconWidget:new{ file = NoteBar.ICON_DIR .. icon .. ".svg", width = isz, height = isz, alpha = true } } }
        local t = tap(w, fn, guarded)
        buttons[id] = t
        return t
    end
    -- (no `back`: a Kindle without a touch screen, where keys do what the buttons do)
    local back = o.back and iconButton("back", o.back_icon or "back", o.back, false) or HorizontalSpan:new{ width = S(8) }
    local right = HorizontalGroup:new{ align = "center" }
    if o.note then
        -- (…and at the right, in grey, the key that has the rest)
        right[#right + 1] = TextWidget:new{ text = o.note, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
        right[#right + 1] = HorizontalSpan:new{ width = S(6) }
    end
    -- (as many as leave the name room: the rest are in ⋮, see NoteBar.fit)
    local icons = o.icons or {}
    local room = NoteBar.fit(#icons, sw, bh, o.action and S(110) or 0)
    for i, ic in ipairs(icons) do
        if i <= room or ic.always then right[#right + 1] = iconButton(ic[1], ic[2], ic[3], ic[4]) end
    end
    if o.action then
        local a = o.action
        right[#right + 1] = HorizontalSpan:new{ width = S(4) }
        local t = tap(FrameContainer:new{ padding = S(6), padding_left = S(18), padding_right = S(18), margin = 0,
            radius = S(6), bordersize = Size.border.thick, background = Blitbuffer.COLOR_WHITE,
            TextWidget:new{ text = a[2], face = Font:getFace("cfont", 16), bold = true } }, a[3], a[4])
        buttons[a[1]] = t
        right[#right + 1] = t
    end
    right[#right + 1] = HorizontalSpan:new{ width = S(6) }
    local left_w = S(4) + back:getSize().w + S(6)
    local title_w = math.max(S(60), sw - left_w - right:getSize().w - S(10))
    local title = VerticalGroup:new{ align = "left",
        TextWidget:new{ text = o.title or "", face = Font:getFace("cfont", 17), bold = true, max_width = title_w } }
    if o.hint and o.hint ~= "" then
        title[#title + 1] = TextWidget:new{ text = o.hint, face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = title_w }
    end
    local bar = VerticalGroup:new{ align = "left",
        OverlapGroup:new{ dimen = Geom:new{ w = sw, h = h - line },
            LeftContainer:new{ dimen = Geom:new{ w = sw, h = h - line },
                HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = S(4) }, back, HorizontalSpan:new{ width = S(6) }, title } },
            RightContainer:new{ dimen = Geom:new{ w = sw, h = h - line }, right } },
        LineWidget:new{ background = Blitbuffer.COLOR_BLACK, dimen = Geom:new{ w = sw, h = line } } }
    return bar, buttons
end

--- The note's own icons, the same in the note editor's bar and the drawing
--- screen's (the owner, 2026-11-19): a photo from Immich, a tag, the note's
--- space and who can see it. `o`: photos, tag, space (fns; nil: not offered),
--- visibility (PRIVATE, PROTECTED, PUBLIC or SPACE), pick_visibility (fn).
--- → { { id, icon, fn }, … } in that order.
NoteBar.VIS_ICON = { PRIVATE = "vis-private", PROTECTED = "vis-protected", PUBLIC = "vis-public", SPACE = "vis-space" }
function NoteBar.noteIcons(o)
    local out = {}
    if o.photos then out[#out + 1] = { "photos", "photos", o.photos, true } end
    if o.tag then out[#out + 1] = { "tag", "tag", o.tag, true } end
    if o.space then out[#out + 1] = { "space", "space", o.space, true } end
    if o.pick_visibility then
        out[#out + 1] = { "visibility", NoteBar.VIS_ICON[o.visibility] or "vis-private", o.pick_visibility, true }
    end
    return out
end

--- How many of `n` icons (each `bh` wide) fit in a bar `width` wide beside
--- ✕ and the name (at least NAME_MIN), `reserve` more taken (Done).
NoteBar.NAME_MIN = 120
function NoteBar.fit(n, width, bh, reserve)
    local left = S(4) + bh + S(6)
    local free = width - left - S(NoteBar.NAME_MIN) - (reserve or 0) - S(12)
    return math.max(0, math.min(n, math.floor(free / (bh + S(2)))))
end

--- A note's name for the bar: its first line of text (heading marks, list
--- marks and emphasis off), at most 48 characters; nil when it has none.
function NoteBar.nameOf(text)
    for l in (text or ""):gmatch("[^\n]+") do
        -- (a line of only #tags: not a name; "# Heading" has a space after #)
        if l:gsub("#[^%s#]+", ""):match("^%s*$") then l = "" end
        local t = l:gsub("^%s*#+%s*", ""):gsub("^%s*[-*]%s+%[.%]%s*", ""):gsub("^%s*[-*>]%s+", ""):gsub("[*_`]", "")
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        -- (not a picture, not a line of only #tags)
        if t ~= "" and t ~= "&nbsp;" and not t:match("^!%[") then
            return #t > 48 and (t:sub(1, 48):gsub("[\128-\191]*$", "") .. "…") or t
        end
    end
end

return NoteBar
