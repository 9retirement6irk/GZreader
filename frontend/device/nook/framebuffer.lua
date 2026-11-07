--[[--
The Nook 1st Edition's e-ink screen for KOReader: an 8-bit grey page
(600 × 800) that GZreader draws on (display_hw.lua). The colour touchscreen
under it is the LCD module's (device/nook/lcd.lua), through the same
display_hw.

Each e-ink refresh goes through the Nook's kernel (the direct, per-area way
froze the Nook). Its refresh without a flash (display_hw's einkPan: the
areas that changed, GU) is used for every update that doesn't ask for a
flash; one that does (a full refresh) gets the kernel's full redraw. Every
update is copied into the page at once, and the refresh comes after, once
for all of them: one when the updates stop coming (DEBOUNCE_MS), and no
later than MAX_DELAY_MS after the first one.

With GZ_NOOK_EPD=flash (every refresh a full redraw, with its flash, as up
to 1.26.6) GZreader asks for as few as it can:

- after a tap or a button (and for a big change, like a new page or a
  dialog): one refresh when the updates stop coming (DEBOUNCE_MS), and no
  later than MAX_DELAY_MS after the first one. A tap's highlight, the page
  it opens and the status bar under it are then one flash, not three;
- a popup that opens by itself (a download's progress, a message): soon,
  like a tap's answer; while it stays up, its changes (the progress bar)
  every DIALOG_EVERY_MS at most;
- small changes nobody asked for under no popup (the clock, the battery,
  the footer while you read): no refresh of their own. They show with the
  next refresh, or after BACKGROUND_MAX_S at the latest.

A refresh that flashes is asked for (a full refresh) counts as big.
]]

local BB = require("ffi/blitbuffer")
local logger = require("logger")
local time = require("ui/time")

local framebuffer = {
    DEBOUNCE_MS = 150,
    MAX_DELAY_MS = 600,
    INPUT_WINDOW_MS = 2500, -- (updates this soon after a tap or button are its answer)
    BIG_AREA = 0.25, -- (of the page)
    BACKGROUND_MAX_S = 300,
    DIALOG_EVERY_MS = 4000,
}

function framebuffer:init()
    local HW = require("device/nook/display_hw")
    local ok, err = HW:open()
    if not ok then error("Nook screen: " .. tostring(err)) end
    self.hw = HW
    self.bb = BB.new(HW.EINK_W, HW.EINK_H, BB.TYPE_BB8)
    self.bb:fill(BB.COLOR_WHITE)
    self.last_input = nil
    self.pending = nil
    framebuffer.parent.init(self)
end

--- The time now (fts); a test replaces it.
function framebuffer:now() return time.now() end

--- Run `fn` in `ms` milliseconds, cancelling the last one asked for; a test
--- replaces it.
function framebuffer:schedule(ms, fn)
    local UIManager = require("ui/uimanager")
    if self.scheduled then UIManager:unschedule(self.scheduled) end
    self.scheduled = fn
    if fn then UIManager:scheduleIn(ms / 1000, fn) end
end

--- A tap, a swipe or a button (device.lua): what's drawn soon after is its answer.
function framebuffer:noteInput()
    self.last_input = self:now()
end

--- The kernel's refresh, now, for everything copied in since the last one.
function framebuffer:flush()
    if self.scheduled then self:schedule(nil, nil) end
    local p = self.pending
    if not p then return end
    self.pending = nil
    self.last_flush = self:now()
    self.flushed_top = self:topWidget()
    local ok, err
    if self.hw.partial and not p.flash then
        ok, err = pcall(self.hw.einkPan, self.hw)
    else
        ok, err = pcall(self.hw.einkRedraw, self.hw)
    end
    if not ok then logger.warn("nook: e-ink refresh failed:", err) end
    if p.count > 1 then logger.dbg("nook: one e-ink refresh for", p.count, "updates") end
end

--- The widget on top of the screen (a popup, or the Home/reader screen
--- under it); a test replaces it.
function framebuffer:topWidget()
    local ok, UIManager = pcall(require, "ui/uimanager")
    local stack = ok and rawget(UIManager, "_window_stack")
    local top = type(stack) == "table" and stack[#stack]
    return type(top) == "table" and top.widget or nil
end

function framebuffer:_later(kind, now)
    local p = self.pending
    if not p then
        p = { first = now, count = 0 }
        self.pending = p
    end
    p.count = p.count + 1
    local ms
    if kind == "now" then
        p.asked = p.asked or now
        -- a little after the last update, but not long after the first one asked
        local deadline = p.asked + time.ms(self.MAX_DELAY_MS)
        ms = math.max(0, math.min(time.to_ms(deadline - now), self.DEBOUNCE_MS))
    elseif p.asked then
        return -- (a refresh is coming anyway)
    elseif kind == "dialog" then
        -- a popup's own changes: every so often
        local next_ok = (self.last_flush or 0) + time.ms(self.DIALOG_EVERY_MS)
        ms = math.max(self.DEBOUNCE_MS, time.to_ms(next_ok - now))
        if self.scheduled and p.dialog_due and p.dialog_due <= now + time.ms(ms) then return end
        p.dialog_due = now + time.ms(ms)
    else
        local deadline = p.first + time.s(self.BACKGROUND_MAX_S)
        ms = math.max(0, time.to_ms(deadline - now))
        if self.scheduled and p.background_due == deadline then return end
        p.background_due = deadline
    end
    self:schedule(ms, function()
        self.scheduled = nil
        self:flush()
    end)
end

local function update(self, waveform, flash, x, y, w, h)
    x, y, w, h = self.bb:getBoundedRect(x, y, w, h)
    x, y, w, h = self.bb:getPhysicalRect(x, y, w, h)
    if w <= 0 or h <= 0 then return end
    if self.hw.direct then
        local ok, err = pcall(self.hw.eink, self.hw, self.bb, x, y, w, h, waveform, flash)
        if not ok then logger.warn("nook: e-ink refresh failed:", err) end
        return
    end
    local ok, err = pcall(self.hw.einkStage, self.hw, self.bb, y, h)
    if not ok then logger.warn("nook: e-ink update failed:", err); return end
    local now = self:now()
    local asked = self.last_input and now - self.last_input <= time.ms(self.INPUT_WINDOW_MS)
    local big = flash or w * h >= self.BIG_AREA * self.bb:getWidth() * self.bb:getHeight()
    -- (without a flash, nothing needs to wait)
    local kind = (asked or big or self.hw.partial) and "now" or "background"
    if kind == "background" then
        local top = self:topWidget()
        if top and not top.covers_fullscreen then
            -- a popup: a new one shows soon, an open one's changes now and then
            kind = top ~= self.flushed_top and "now" or "dialog"
        end
    end
    self:_later(kind, now)
    if flash then self.pending.flash = true end
end

function framebuffer:refreshFullImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshFlashPartialImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshFlashUIImp(x, y, w, h) update(self, "gc", true, x, y, w, h) end
function framebuffer:refreshPartialImp(x, y, w, h) update(self, "gu", false, x, y, w, h) end
function framebuffer:refreshUIImp(x, y, w, h) update(self, "gu", false, x, y, w, h) end
function framebuffer:refreshFastImp(x, y, w, h) update(self, "du", false, x, y, w, h) end
function framebuffer:refreshA2Imp(x, y, w, h) update(self, "du", false, x, y, w, h) end

function framebuffer:close()
    if self.hw and not self.hw.direct then pcall(self.flush, self) end
    if self.hw then pcall(self.hw.close, self.hw) end
    if self.bb then self.bb:free(); self.bb = nil end
end

return require("ffi/framebuffer"):extend(framebuffer)
