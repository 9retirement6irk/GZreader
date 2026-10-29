-- Full-screen QR code shown while waiting for the phone to complete pairing.

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
local Input = Device.input
local Screen = Device.screen

local PairScreen = InputContainer:extend{
    name = "QR code screen",
    modal = true,
    url = nil,
    on_cancel = nil,
}

function PairScreen:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then
        self.key_events.Cancel = { { Input.group.Back } }
    end
    local text_w = math.floor(sw * 0.86)
    local qr_size = math.floor(math.min(sw, sh * 0.62) * 0.72)
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
            text = self.instructions or _("Scan this code with your phone's camera, then sign in on the page that opens. Your phone must be on the same Wi-Fi as this Kindle."),
            face = Font:getFace("cfont", 18),
            width = text_w,
            alignment = "center",
        },
        gap,
        QRWidget:new{ text = self.url, width = qr_size, height = qr_size },
        gap,
        TextBoxWidget:new{
            text = _("No camera? Type this address into your phone's browser:") .. "\n" .. self.url,
            face = Font:getFace("smallinfofont", 16),
            width = text_w,
            alignment = "center",
        },
        gap,
    }
    if Device:isTouchDevice() then
        table.insert(group, Button:new{
            text = _("Cancel"),
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
