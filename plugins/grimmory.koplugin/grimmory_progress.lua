--[[--
Download progress dialog: the progress bar plus "42% · 116.3 MB of 276.4 MB".
]]

local ProgressbarDialog = require("ui/widget/progressbardialog")
local _ = require("gettext")
local T = require("ffi/util").template

local Progress = ProgressbarDialog:extend{}

function Progress.size(bytes)
    bytes = bytes or 0
    if bytes >= 1024 * 1024 * 1024 then return string.format("%.2f GB", bytes / (1024 * 1024 * 1024)) end
    if bytes >= 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
    return string.format("%d KB", math.floor(bytes / 1024 + 0.5))
end

function Progress.status(done, total)
    if total and total > 0 then
        local pct = math.floor(math.min(done, total) * 100 / total)
        return T(_("%1% · %2 of %3"), pct, Progress.size(done), Progress.size(total))
    end
    return T(_("%1 downloaded"), Progress.size(done))
end

function Progress:init()
    if not self.progress_max or self.progress_max <= 0 then self.progress_max = nil end
    ProgressbarDialog.init(self)
    local Font = require("ui/font")
    local Screen = require("device").screen
    local TextWidget = require("ui/widget/textwidget")
    self.status_widget = TextWidget:new{
        text = Progress.status(0, self.progress_max),
        face = Font:getFace("smallffont"),
        max_width = Screen:getWidth() - Screen:scaleBySize(80),
    }
    local group = self[1][1]
    table.insert(group, self.status_widget)
    group:resetLayout()
    self.done = 0
end

function Progress:reportProgress(done)
    self.done = done
    local text = self.status_text or Progress.status(done, self.progress_max)
    if text ~= self.status_widget.text then self.status_widget:setText(text) end
    if self.progress_bar_visible then
        self.progress_bar:setPercentage(math.min(done, self.progress_max) / self.progress_max)
    end
    return self:redrawProgressbarIfNeeded()
end

function Progress:redrawProgressbarIfNeeded()
    if self.progress_bar_visible then
        return ProgressbarDialog.redrawProgressbarIfNeeded(self)
    end
    if os.time() - (self.last_text_redraw or 0) >= (self.refresh_time_seconds or 2) then
        self.last_text_redraw = os.time()
        self:redrawProgressbar()
        return true
    end
end

--- Replace the status line (e.g. "Preparing the audio…").
function Progress:setStatus(text)
    self.status_text = text
    self:reportProgress(self.done or 0)
end

return Progress
