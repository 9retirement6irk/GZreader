-- GZreader: the symbols popup on the Kindles with a keyboard (Kindle 2, 3, DX).
-- A lone press of the Sym key in a text box opens a small grid of symbols,
-- as the Kindle's own software does, instead of KOReader's whole on-screen
-- keyboard: the 5-way moves, pressing it types the symbol and closes the
-- popup, Sym or Back closes it. Typing a key while it's open closes it and
-- types that key. Shift + Home still shows the whole on-screen keyboard.
-- Called from frontend/ui/widget/inputtext.lua.
local M = {}

-- The Kindle 3's own symbols, row by row.
M.ROWS = {
    { ":", "<", ">", "\"", "?", "{", "}", "|", "`", "~", "£", "€" },
    { ";", ",", ".", "'", "/", "[", "]", "\\", "«", "»", "¡", "¿" },
    { "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_", "+" },
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=" },
}

-- The cell chosen last, so the popup opens where it was left (this run only).
M.last = { x = 1, y = 1 }

--- Whether a lone Sym press should open the popup on this device: only the
--- Kindles with a keyboard (they have the Sym key); not the Kindle 4's
--- ScreenKB, which has no keys to type with.
function M.wanted(device)
    return device ~= nil and device:hasKeyboard() and device:hasSymKey() and true or false
end

--- Where the popup goes (its top), given the screen's height, the popup's
--- height and the text box's place (a table with y and h, or nil). Above
--- the text box when the box is in the lower half and there's room, else
--- below it when there's room, else at the top of the screen.
function M.placeY(screen_h, popup_h, field, gap)
    gap = gap or 0
    local fallback = math.max(0, math.floor((screen_h - popup_h) / 2))
    if not (field and field.y and field.h) then
        return fallback
    end
    local above = field.y - gap - popup_h
    local below = field.y + field.h + gap
    local fits_below = below + popup_h <= screen_h
    if field.y + field.h / 2 > screen_h / 2 then
        if above >= 0 then return above end
        if fits_below then return below end
    else
        if fits_below then return below end
        if above >= 0 then return above end
    end
    return math.min(gap, math.max(0, screen_h - popup_h))
end

--- What a key pressed while the popup is open does: "close" (Sym, Back),
--- "type" (close, then the text box gets the key: letters, Sym + a letter,
--- Del) or nil (the popup's own: the 5-way).
function M.keyAction(key)
    if not key then return nil end
    local name = key.key
    if name == "SymPress" or name == "Back" then
        return "close"
    end
    if name == "Del" or (type(name) == "string" and #name == 1) then
        return "type"
    end
    return nil
end

--- Opens the popup for an InputText.
function M.show(input)
    local UIManager = require("ui/uimanager")
    local popup = M.Popup:new{ input = input }
    UIManager:show(popup)
    return popup
end

-- The widget, built the first time it's needed (the pure functions above
-- are tested without KOReader's widgets).
setmetatable(M, { __index = function(t, k)
    if k ~= "Popup" then return nil end
    local Blitbuffer = require("ffi/blitbuffer")
    local Button = require("ui/widget/button")
    local Device = require("device")
    local FocusManager = require("ui/widget/focusmanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local _ = require("gettext")
    local Screen = Device.screen

    local Popup = FocusManager:extend{
        input = nil,
        name = "GzSymbols",
    }

    function Popup:init()
        local sw = Screen:getWidth()
        local cols = #t.ROWS[1]
        local cell_w = math.floor(math.min(sw * 0.9, Screen:scaleBySize(560)) / cols)
        self.layout = {}
        local grid = VerticalGroup:new{}
        for y, row in ipairs(t.ROWS) do
            local line = HorizontalGroup:new{}
            self.layout[y] = {}
            for x, sym in ipairs(row) do
                local button = Button:new{
                    text = sym,
                    width = cell_w,
                    bordersize = 0,
                    margin = 0,
                    padding = Size.padding.large,
                    text_font_size = 22,
                    show_parent = self,
                    callback = function() self:pick(x, y) end,
                }
                table.insert(line, button)
                self.layout[y][x] = button
            end
            table.insert(grid, line)
        end
        local hint = TextWidget:new{
            text = _("(press the Sym key to close symbols)"),
            face = Font:getFace("cfont", 16),
            max_width = cell_w * cols,
        }
        self.frame = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.default,
            VerticalGroup:new{
                grid,
                VerticalSpan:new{ width = Size.padding.default },
                CenterContainer:new{
                    dimen = Geom:new{ w = cell_w * cols, h = hint:getSize().h },
                    hint,
                },
            },
        }
        self[1] = self.frame
        local size = self.frame:getSize()
        local field = self.input and self.input.dimen
        self.dimen = Geom:new{
            x = math.max(0, math.floor((sw - size.w) / 2)),
            y = t.placeY(Screen:getHeight(), size.h, field, Size.margin.default),
            w = size.w, h = size.h,
        }
        local last = t.last
        if not (self.layout[last.y] and self.layout[last.y][last.x]) then
            last = { x = 1, y = 1 }
        end
        self.selected = { x = last.x, y = last.y }
        self:moveFocusTo(last.x, last.y, FocusManager.FOCUS_ONLY_ON_NT)
    end

    function Popup:paintTo(bb, x, y)
        self.frame:paintTo(bb, x + self.dimen.x, y + self.dimen.y)
    end

    function Popup:pick(x, y)
        t.last = { x = x, y = y }
        local sym = t.ROWS[y] and t.ROWS[y][x]
        self:onClose()
        if sym and self.input then
            self.input:addChars(sym)
        end
    end

    function Popup:onClose()
        UIManager:close(self)
        return true
    end

    function Popup:onKeyPress(key)
        local action = t.keyAction(key)
        if action == "close" then
            return self:onClose()
        end
        if FocusManager.onKeyPress(self, key) then
            return true
        end
        if action == "type" then
            self:onClose()
            if self.input then
                self.input:onKeyPress(key)
            end
        end
        return true -- the popup keeps every key while it's open
    end

    function Popup:onShow()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
        return true
    end

    function Popup:onCloseWidget()
        UIManager:setDirty(nil, function() return "ui", self.dimen end)
    end

    rawset(t, "Popup", Popup)
    return Popup
end })

return M
