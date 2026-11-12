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

--- A row of rounded buttons ("chips"), spread over `width`.
function Touch.chips(width, actions, show_parent)
    local Button = require("ui/widget/button")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local Size = require("ui/size")
    local gap = Device.screen:scaleBySize(10)
    local n = #actions
    local w = math.floor((width - gap * (n - 1)) / n)
    local row = HorizontalGroup:new{ align = "center" }
    for i, a in ipairs(actions) do
        if i > 1 then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        row[#row + 1] = Button:new{
            text = a.text or a[1], callback = a.callback or a[2], width = w, show_parent = show_parent,
            bordersize = Size.border.thin, radius = Size.radius.button, margin = 0,
            padding = Size.padding.small, text_font_size = 17, text_font_bold = false,
        }
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

--- KOReader's "Disable double tap" (disable_double_tap) is left out of Settings
--- → KOReader (zenos common/gz_settings.lua KOREADER_HIDDEN): GZreader has no
--- double-tap actions (no gestures plugin), so unticked it only made every tap
--- in a book wait for a second one. A saved untick is cleared (the default,
--- taps at once; a book opened after reads it).
--- Once only (gzreader_double_tap_cleared): About → Advanced → KOReader
--- settings has KOReader's whole menu, where it can be unticked on purpose.
function Touch.forgetKOReaderDoubleTap()
    if G_reader_settings:isTrue("gzreader_double_tap_cleared") then return false end
    G_reader_settings:makeTrue("gzreader_double_tap_cleared")
    if G_reader_settings:readSetting("disable_double_tap") == false then
        G_reader_settings:delSetting("disable_double_tap")
        require("gzreader_log").info("touch: KOReader's \"Disable double tap\" back on (GZreader has no double-tap actions)")
        return true
    end
    return false
end

return Touch
