-- Full-screen QR code shown while waiting for the phone to complete pairing.
-- With `address` and `pin`: also the address to type into a browser and the
-- PIN it asks for (the setup page, gzreader_phone.lua).

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local QRWidget = require("ui/widget/qrwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template
local Input = Device.input
local Screen = Device.screen

local PairScreen = InputContainer:extend{
    name = "QR code screen",
    modal = true,
    url = nil,
    on_cancel = nil,
    address = nil, -- typed into a browser (with `pin`)
    pin = nil,     -- 6 digits
}

local function spacedPin(pin) return pin:sub(1, 3) .. " " .. pin:sub(4) end

function PairScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then
        self.key_events.Cancel = { { Input.group.Back } }
    end
    local text_w = math.floor(sw * 0.86)
    local qr_size = math.floor(math.min(sw, sh * 0.62) * (self.pin and 0.6 or 0.72))
    local gap = VerticalSpan:new{ width = Size.span.vertical_large * 2 }

    local group = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = self.title or _("Connect to Grimmory"),
            face = Font:getFace("tfont", 26),
            width = text_w,
            alignment = "center",
        },
        gap,
        TextBoxWidget:new{
            text = self.instructions or _("Scan this code with your phone, then sign in on the page that opens."),
            face = Font:getFace("cfont", 18),
            width = text_w,
            alignment = "center",
        },
        gap,
        QRWidget:new{ text = self.url, width = qr_size, height = qr_size },
        gap,
    }
    if self.pin and self.address then
        -- or type the address into any browser on the Wi-Fi, then the PIN
        table.insert(group, TextBoxWidget:new{
            text = _("Or in a browser on the same Wi-Fi, go to"),
            face = Font:getFace("cfont", 18),
            width = text_w,
            alignment = "center",
        })
        table.insert(group, TextBoxWidget:new{ text = self.address, face = Font:getFace("tfont", 26), bold = true,
            width = text_w, alignment = "center" })
        table.insert(group, VerticalSpan:new{ width = Size.span.vertical_large })
        self.pin_widget = TextBoxWidget:new{
            text = T(_("PIN %1"), spacedPin(self.pin)),
            face = Font:getFace("tfont", 30),
            bold = true,
            width = text_w,
            alignment = "center",
        }
        table.insert(group, self.pin_widget)
        table.insert(group, gap)
    else
        table.insert(group, TextBoxWidget:new{
            text = _("Same Wi-Fi as this Kindle. No camera? Open this address:") .. "\n" .. self.url,
            face = Font:getFace("smallinfofont", 16),
            width = text_w,
            alignment = "center",
        })
        table.insert(group, gap)
    end
    if Device:isTouchDevice() then
        table.insert(group, Button:new{
            text = self.button_text or _("Cancel"),
            width = math.floor(sw * 0.4),
            callback = function() self:onCancel() end,
        })
    else
        table.insert(group, TextBoxWidget:new{
            text = self.footer or _("Press Back to cancel."),
            face = Font:getFace("smallinfofont", 16),
            width = text_w,
            alignment = "center",
        })
    end

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        width = sw,
        height = sh,
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group },
    }
end

--- A new PIN, or (pin nil) why there's none now.
function PairScreen:setPin(pin, why)
    if not self.pin_widget then return end
    self.pin_widget:setText(pin and T(_("PIN %1"), spacedPin(pin)) or why or "")
    UIManager:setDirty(self, "ui")
end

function PairScreen:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function PairScreen:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

function PairScreen:onCancel()
    UIManager:close(self)
    if self.on_cancel then self.on_cancel() end
    return true
end

return PairScreen
