--[[--
What differs between Kindles with a keyboard (Kindle 2, DX, Kindle 3) and
touch Kindles (Paperwhite…): letter keys and key hints only where there are
keys; buttons to tap where there aren't; audio only where there is a speaker.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")

local Touch = {}

--- A touch screen (Paperwhite, Kindle Touch, Oasis…).
function Touch.on() return Device:isTouchDevice() == true end

--- A keyboard: letter keys (shown in squares next to items) and key hints.
function Touch.keys() return Device:hasKeyboard() == true end

--- A speaker or headphone jack GZreader can play through (audiobooks, read
--- aloud): the Kindle 2, DX and Kindle 3. The Paperwhites have no audio.
function Touch.audio()
    local m = Device.model or ""
    return m == "Kindle2" or m == "KindleDX" or m == "KindleDXG" or m == "Kindle3"
end

--- The letter for a list item only when there are keys to press it.
function Touch.letter(key) if Touch.keys() then return key end end

--- `with_keys` on a Kindle with a keyboard, `touch` otherwise.
function Touch.text(with_keys, touch) if Touch.keys() then return with_keys end return touch end

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

return Touch
