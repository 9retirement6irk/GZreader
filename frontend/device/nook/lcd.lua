--[[--
The Nook 1st Edition's colour touchscreen (480 × 144, under the e-ink page).

This module owns its picture and its touches; what it shows comes from a
painter (GZreader's colour screen panels, gzreader_nook.lua):

    lcd:setPainter(function(bb) ... end)   -- draw on a 480 × 144 RGB565 BlitBuffer
    lcd:setTouchHandler(function(g) ... end) -- g = { kind = "tap"|"hold"|"swipe", x, y, dir }
    lcd:refresh()                           -- paint and show

The touch handler returns what a touch does: a key name ("Up", "Press",
"Back"… delivered as a key press, as if the Nook had those keys), a
function (run on the next tick), or nothing.

The backlight turns off after `timeout` seconds without a touch; the touch
that wakes it only wakes it.
]]

local BB = require("ffi/blitbuffer")
local Event = require("ui/event")
local logger = require("logger")
local time = require("ui/time")

local W, H = 480, 144

-- linux/input.h
local EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
local ABS_X, ABS_Y, ABS_PRESSURE = 0, 1, 24
local BTN_TOUCH = 330

local LCD = {
    w = W, h = H,
    timeout = 60, -- s, 0 = never
    level = nil, -- backlight level (nil: the Nook's)
    swap_xy = false, flip_x = false, flip_y = false, -- touch orientation (settings)
    range = { x = { 0, 4095 }, y = { 0, 4095 } }, -- raw touch coordinates (updated from the panel)
    hold_s = 0.6,
    swipe_px = 60,
}
LCD.__index = LCD

function LCD:new(o)
    o = setmetatable(o or {}, self)
    -- (painted in the LCD's own format: shown with a plain copy)
    o.bb = BB.new(W, H, BB.TYPE_BBRGB16)
    o.bb:fill(BB.COLOR_BLACK)
    o.on = true
    o.touch = {}
    o.last_touch = time.now()
    return o
end

function LCD:setPainter(fn) self.painter = fn end
function LCD:setTouchHandler(fn) self.touch_handler = fn end

--- Paint and show (skipped while the backlight is off: shown when it wakes).
function LCD:refresh()
    if not self.on then self.dirty = true; return end
    self.dirty = false
    if self.painter then
        local ok, err = pcall(self.painter, self.bb)
        if not ok then logger.warn("nook lcd: paint failed:", err) end
    end
    if self.hw then
        local ok, err = pcall(self.hw.lcd, self.hw, self.bb)
        if not ok then logger.warn("nook lcd: show failed:", err) end
    end
    if self.on_present then self.on_present(self.bb) end
end

function LCD:setBacklight(on)
    if on == self.on then return end
    self.on = on
    if self.hw then pcall(self.hw.backlight, self.hw, on, on and self.level or nil) end
    if on then
        self.last_touch = time.now()
        if self.dirty then self:refresh() end
        self:scheduleSleep()
    end
end

function LCD:setLevel(level)
    self.level = level
    if self.on and self.hw then pcall(self.hw.backlight, self.hw, true, level) end
end

--- Backlight off after `timeout` s without a touch.
function LCD:scheduleSleep()
    local UIManager = require("ui/uimanager")
    if self._sleep then UIManager:unschedule(self._sleep) end
    if not self.timeout or self.timeout <= 0 then return end
    self._sleep = function()
        self._sleep = nil
        local idle = time.to_s(time.now() - self.last_touch)
        if idle >= self.timeout - 0.5 then
            self:setBacklight(false)
        else
            UIManager:scheduleIn(self.timeout - idle, self._sleep)
        end
    end
    UIManager:scheduleIn(self.timeout, self._sleep)
end

function LCD:setTimeout(s)
    self.timeout = s
    self.last_touch = time.now()
    if self.on then self:scheduleSleep() end
end

--- Raw panel coordinates → LCD pixels.
function LCD:map(rx, ry)
    if self.swap_xy then rx, ry = ry, rx end
    local xr, yr = self.range.x, self.range.y
    if self.swap_xy then xr, yr = yr, xr end
    local x = (rx - xr[1]) * (W - 1) / math.max(1, xr[2] - xr[1])
    local y = (ry - yr[1]) * (H - 1) / math.max(1, yr[2] - yr[1])
    if self.flip_x then x = W - 1 - x end
    if self.flip_y then y = H - 1 - y end
    return math.max(0, math.min(W - 1, math.floor(x + 0.5))), math.max(0, math.min(H - 1, math.floor(y + 0.5)))
end

local function keyEvents(input, name, tv)
    local code = input.nook_virtual_codes and input.nook_virtual_codes[name]
    if not code then return nil end
    local out = {}
    for _i, v in ipairs({ 1, 0 }) do
        local e = input:handleKeyBoardEv({ type = EV_KEY, code = code, value = v, time = tv })
        if e then out[#out + 1] = e end
    end
    return out
end

--- What a finished touch does (a gesture → the handler's action → events).
function LCD:gesture(g, input, tv)
    self.last_touch = time.now()
    if not self.on then
        self:setBacklight(true) -- (the waking touch does nothing else)
        return nil
    end
    self:scheduleSleep()
    if not self.touch_handler then return nil end
    local ok, action = pcall(self.touch_handler, g)
    if not ok then logger.warn("nook lcd: touch failed:", action); return nil end
    if type(action) == "string" then
        return keyEvents(input, action, tv)
    elseif type(action) == "function" then
        require("ui/uimanager"):nextTick(action)
    elseif type(action) == "table" and action.text then
        return { Event:new("TextInput", action.text) }
    end
    return nil
end

--- From the input loop: the touch panel's events (single touch: ABS_X/Y,
--- pressure and BTN_TOUCH). Returns a list of events when a touch ends.
function LCD:onInputEvent(input, ev)
    local t = self.touch
    if ev.type == EV_ABS then
        if ev.code == ABS_X then t.rx = ev.value
        elseif ev.code == ABS_Y then t.ry = ev.value
        elseif ev.code == ABS_PRESSURE then t.pressure = ev.value
        end
        return nil
    elseif ev.type == EV_KEY and ev.code == BTN_TOUCH then
        t.down_flag = ev.value ~= 0
        return nil
    elseif ev.type ~= EV_SYN then
        return nil
    end
    local down = t.down_flag
    if down == nil then down = (t.pressure or 0) > 0 end
    local now = time.timeval(ev.time)
    if down and t.rx and t.ry then
        local x, y = self:map(t.rx, t.ry)
        if not t.active then
            t.active, t.x0, t.y0, t.t0 = true, x, y, now
        end
        t.x, t.y = x, y
        return nil
    elseif not down and t.active then
        t.active = false
        local dx, dy = t.x - t.x0, t.y - t.y0
        local g
        if math.abs(dx) >= self.swipe_px or math.abs(dy) >= self.swipe_px * 0.6 then
            local dir
            if math.abs(dx) >= math.abs(dy) * 1.5 then dir = dx < 0 and "west" or "east"
            else dir = dy < 0 and "north" or "south" end
            g = { kind = "swipe", dir = dir, x = t.x0, y = t.y0, dx = dx, dy = dy }
        elseif time.to_s(now - t.t0) >= self.hold_s then
            g = { kind = "hold", x = t.x0, y = t.y0 }
        else
            g = { kind = "tap", x = t.x0, y = t.y0 }
        end
        t.pressure, t.down_flag = nil, nil
        return self:gesture(g, input, ev.time)
    end
    return nil
end

return LCD
