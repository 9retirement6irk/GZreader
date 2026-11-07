local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Pill = require("common/ui/pill")
local TextWidget = require("ui/widget/textwidget")
local utils = require("common/utils")

local M = {}

local function clamp_ratio(value)
    value = tonumber(value)
    if not value then return nil end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

function M.bar(ratio, width, height)
    ratio = clamp_ratio(ratio) or 0
    width = math.max(1, math.floor(tonumber(width) or 1))
    height = math.max(1, math.floor(tonumber(height) or 1))
    local fill_w = math.floor(width * ratio)
    return {
        dimen = Geom:new{ w = width, h = height },
        getSize = function(self) return self.dimen end,
        handleEvent = function() return false end,
        free = function() end,
        paintTo = function(_self, bb, x, y)
            Pill.paint(bb, x, y, width, height, Blitbuffer.COLOR_LIGHT_GRAY)
            if fill_w > 0 then
                Pill.paint(bb, x, y, math.min(width, math.max(fill_w, height)),
                    height, Blitbuffer.COLOR_GRAY_5)
            end
        end,
    }
end

-- GZreader: progress as a book's page edges seen from the top: the pages
-- read darker, the rest light, and a ribbon bookmark where you are. The
-- ribbon hangs a little above and below (pad, in the widget's height).
function M.edges(ratio, width, height)
    ratio = clamp_ratio(ratio) or 0
    width = math.max(8, math.floor(tonumber(width) or 8))
    height = math.max(6, math.floor(tonumber(height) or 6))
    local Screen = require("device").screen
    local pad = math.max(2, Screen:scaleBySize(3))
    local rib_w = math.max(4, Screen:scaleBySize(7))
    return {
        dimen = Geom:new{ w = width, h = height + 2 * pad },
        getSize = function(self) return self.dimen end,
        handleEvent = function() return false end,
        free = function() end,
        paintTo = function(_self, bb, x, y)
            local by, bh = y + pad, height
            local split = x + math.floor((width - 1) * ratio)
            for xx = x, x + width - 1 do
                local read = xx < split
                local dark = (xx - x) % 2 == 0
                local c = read and (dark and 0.62 or 0.42) or (dark and 0.22 or 0.06)
                bb:paintRect(xx, by, 1, bh, Blitbuffer.gray(c))
            end
            -- the top and bottom covers' edges, and the round fore-edge
            bb:paintRect(x, by, width, 1, Blitbuffer.gray(0.75))
            bb:paintRect(x, by + bh - 1, width, 1, Blitbuffer.gray(0.85))
            bb:paintRect(x + width - 1, by + 1, 1, bh - 2, Blitbuffer.gray(0.7))
            -- the ribbon: from above the pages to below them, a notch at its end
            local rx = math.max(x, math.min(x + width - rib_w, split - math.floor(rib_w / 2)))
            local bottom = by + bh + pad
            bb:paintRect(rx, y, rib_w, bottom - y - math.floor(rib_w / 2), Blitbuffer.COLOR_BLACK)
            local half = math.floor(rib_w / 2)
            for k = 0, half - 1 do
                -- (two points: the notch between them)
                bb:paintRect(rx, bottom - half + k, half - k, 1, Blitbuffer.COLOR_BLACK)
                bb:paintRect(rx + rib_w - (half - k), bottom - half + k, half - k, 1, Blitbuffer.COLOR_BLACK)
            end
            bb:paintRect(rx + 1, y + 1, 1, bottom - y - rib_w, Blitbuffer.gray(0.6))
        end,
    }
end

function M.build(opts)
    opts = opts or {}
    local ratio = clamp_ratio(opts.ratio)
    if ratio == nil then return nil end

    local width = math.max(1, math.floor(tonumber(opts.width) or 1))
    local bar_h = math.max(1, math.floor(tonumber(opts.bar_height) or 1))
    local left_text = opts.left_text
        or string.format("%d%%", math.floor(ratio * 100 + 0.5))
    local pages = tonumber(opts.pages)
    local right_text = opts.right_text
        or (pages and pages > 0 and utils.formatPageCount(pages, true) or "")
    local left = TextWidget:new{
        text = left_text,
        face = opts.face,
        bold = opts.bold == true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local right = TextWidget:new{
        text = right_text,
        face = opts.face,
        bold = opts.bold == true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local gap = math.max(2, math.floor(tonumber(opts.gap) or width * 0.02))
    local bar_w = math.max(20,
        width - left:getSize().w - right:getSize().w - gap * 2)
    return HorizontalGroup:new{
        align = "center",
        left,
        HorizontalSpan:new{ width = gap },
        opts.style == "edges" and M.edges(ratio, bar_w, bar_h) or M.bar(ratio, bar_w, bar_h),
        HorizontalSpan:new{ width = gap },
        right,
    }
end

return M
