--[[--
What differs between GZreader's Kindles, three kinds:
- a keyboard (Kindle 2, DX, Kindle 3): letter keys (shown in squares next
  to items) and key hints;
- a 5-way and no keyboard (Kindle 4): the 5-way moves, Press picks, Menu
  opens each screen's options;
- a touch screen (Kindle Touch, Paperwhite 3): buttons to tap.
And audio only where there is a speaker.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")

local Touch = {}

--- A touch screen (Kindle Touch, Paperwhite…).
function Touch.on() return Device:isTouchDevice() == true end

--- A keyboard: letter keys (shown in squares next to items) and key hints.
function Touch.keys() return Device:hasKeyboard() == true end

--- Keys but no keyboard and no touch screen (the Kindle 4): the 5-way,
--- Press, Menu, Back, Home and the page keys.
function Touch.dpad()
    return not Touch.on() and not Touch.keys() and Device.hasKeys ~= nil and Device:hasKeys() == true
end

--- A speaker or headphone jack GZreader can play audiobooks through: the
--- Kindle 2, DX, Kindle 3 and Kindle Touch. The Kindle 4 and the
--- Paperwhites have no audio.
function Touch.audio()
    local m = Device.model or ""
    return m == "Kindle2" or m == "KindleDX" or m == "KindleDXG" or m == "Kindle3" or m == "KindleTouch"
end

--- The DX or DX Graphite: the 9.7" 824 × 1200 screen (KOReader's Kindle 2
--- class runs the DX, so by its size).
function Touch.dx()
    local m = Device.model or ""
    if m ~= "Kindle2" and m ~= "KindleDX" and m ~= "KindleDXG" then return false end
    local s = Device.screen
    local ok, small = pcall(function() return math.min(s:getWidth(), s:getHeight()) end)
    return ok and small > 600 or false
end

--- Read aloud (the Kindle's voice): every Kindle with audio. Shift + Sym on
--- a keyboard; the quick panel's Read aloud button on a touch screen.
function Touch.tts() return Touch.audio() end

--- The letter for a list item only when there are keys to press it.
function Touch.letter(key) if Touch.keys() then return key end end

--- `with_keys` on a Kindle with a keyboard, `touch` on a touch screen,
--- `dpad` (or `with_keys`) on a Kindle 4.
function Touch.text(with_keys, touch, dpad)
    if Touch.keys() then return with_keys end
    if Touch.on() then return touch end
    return dpad or with_keys
end

--- A row of buttons (touch): actions = { { text, callback }, … }.
function Touch.buttonRow(width, actions, opts)
    local ButtonTable = require("ui/widget/buttontable")
    opts = opts or {}
    local row = {}
    for _i, a in ipairs(actions) do
        row[#row + 1] = { text = a.text or a[1], callback = a.callback or a[2], enabled = a.enabled ~= false,
            font_size = opts.font_size, font_bold = opts.bold }
    end
    return ButtonTable:new{ width = width, buttons = { row }, zero_sep = true, show_parent = opts.show_parent,
        sep_width = 0 }
end

--- How wide each chip of a row is: icon chips (`icon_file`) square-ish,
--- `icon_w` wide; text chips share the rest. Returns { w, … } per action.
function Touch.chipWidths(width, actions, gap, icon_w)
    local n, icons = #actions, 0
    for _i, a in ipairs(actions) do if a.icon_file then icons = icons + 1 end end
    local text_w = n > icons and math.floor((width - gap * (n - 1) - icon_w * icons) / (n - icons)) or 0
    local out = {}
    for i, a in ipairs(actions) do out[i] = a.icon_file and icon_w or text_w end
    return out
end

--- A chip with a picture (an SVG file) instead of text: `h` tall, framed like the others.
local function iconChip(a, w, h, show_parent)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Size = require("ui/size")
    local b = Size.border.thin
    local isz = math.floor(h * 0.6)
    local box = InputContainer:new{ dimen = Geom:new{ w = w, h = h }, show_parent = show_parent,
        FrameContainer:new{ width = w, height = h, padding = 0, margin = 0, bordersize = b, radius = Size.radius.button,
            CenterContainer:new{ dimen = Geom:new{ w = w - 2 * b, h = h - 2 * b },
                IconWidget:new{ file = a.icon_file, width = isz, height = isz, alpha = true } } } }
    box.ges_events = { TapChip = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    function box:onTapChip() if a.callback then a.callback() end return true end
    box.gz_label = a.label -- (what it does, for tests and logs)
    return box
end

--- A row of rounded buttons ("chips"), spread over `width`. An action is
--- { text, callback } or { icon_file = "….svg", label, callback } (a
--- narrower chip with a picture).
function Touch.chips(width, actions, show_parent)
    local Button = require("ui/widget/button")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local Size = require("ui/size")
    local gap = Device.screen:scaleBySize(10)
    local icon_w = Device.screen:scaleBySize(46)
    local nicons = 0
    for _i, a in ipairs(actions) do if a.icon_file then nicons = nicons + 1 end end
    if nicons > 0 and #actions > 4 then gap = Device.screen:scaleBySize(6) end -- (six on a 600 px screen)
    local widths = Touch.chipWidths(width, actions, gap, icon_w)
    local small = nicons > 0 and #actions > 4
    -- the text chips first: an icon chip is as tall as they are
    local made, h = {}, nil
    for i, a in ipairs(actions) do
        if not a.icon_file then
            made[i] = Button:new{
                text = a.text or a[1], callback = a.callback or a[2], width = widths[i], show_parent = show_parent,
                bordersize = Size.border.thin, radius = Size.radius.button, margin = 0,
                padding = Size.padding.small, text_font_size = small and 16 or 17, text_font_bold = false,
            }
            h = h or made[i]:getSize().h
        end
    end
    local row = HorizontalGroup:new{ align = "center" }
    for i, a in ipairs(actions) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = made[i] or iconChip(a, widths[i], h or Device.screen:scaleBySize(40), show_parent)
    end
    return row
end

--- On a touch Kindle: buttons in place of a tab view's key hints (the Menu's
--- subtitle, under its title). Call after the Menu is built and decorated.
function Touch.actionRow(menu, actions)
    if not Touch.on() then return end
    menu._gz_actions = actions or menu._gz_actions
    actions = menu._gz_actions
    local tb = menu and menu.title_bar
    local sub = tb and (tb.inner_subtitle_group or tb.subtitle_widget)
    if not (tb and sub and tb.title_group and actions) then return end
    local idx
    for i, w in ipairs(tb.title_group) do
        if w == tb._gz_action_row then return w end -- (there already)
        if w == sub then idx = i end
    end
    if not idx then return end
    local Screen = Device.screen
    local width = math.floor((menu.dimen and menu.dimen.w or Screen:getWidth()) * 0.94)
    local row = Touch.chips(width, actions, menu.show_parent or menu)
    local old_h = sub:getSize().h
    tb.title_group[idx] = row
    tb._gz_action_row = row
    tb.title_group:resetLayout()
    -- the title bar is taller now: the Menu lays its page out from its height
    local grow = row:getSize().h - old_h
    if grow > 0 and tb.titlebar_height then
        tb.titlebar_height = tb.titlebar_height + grow
        if tb.dimen then tb.dimen.h = tb.dimen.h + grow end
        -- (and its bottom line goes down as much)
        local VerticalSpan = require("ui/widget/verticalspan")
        for _i, w in ipairs(tb) do
            if w ~= tb.title_group and type(w) == "table" and getmetatable(w[1]) == VerticalSpan then
                w[1].width = w[1].width + grow
                if w.resetLayout then w:resetLayout() end
            end
        end
    end
    if menu.updateItems then pcall(menu.updateItems, menu) end
    UIManager:setDirty(menu.show_parent or menu, "ui")
    return row
end

return Touch
