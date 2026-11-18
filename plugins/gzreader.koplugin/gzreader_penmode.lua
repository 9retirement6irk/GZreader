--[[--
The Kindle Scribe's pen mode: ink that keeps up with the pen.

GZreader's ink was 150–250 ms behind the pen and came in chunks; the
Kindle's own notebook is 30–60 ms behind (the owner's videos IMG_0274 and
IMG_0276, 2026-11-17, frame by frame). Handling the pen wasn't it ("at most
0 ms behind the pen, 0.24 ms a frame" in the owner's log): the time went
between asking for a refresh and the panel showing it.

The Scribe's display driver (MTK hwtcon, "Bellatrix3": Scribe and Scribe 2)
has a mode for exactly this, which KOReader doesn't use (FBInk documents it:
fbink_mtk_toggle_pen_mode, eink/mtk-kindle.h MXCFB_SET_STYLUS_MODE):

- `ioctl(fb, MXCFB_SET_STYLUS_MODE, 1)` turns it on, `0` off;
- in it, updates must be DU (KOReader's "fast"), and small ones (under
  MIN_MDP_SIZE, 6000 pixels) skip the driver's image-processing step: that
  step is what an ordinary update waits in;
- pen-mode updates must not be on the screen together with ordinary
  ones, and it's the program's job to see to that.

So, while the drawing screen is open (`PenMode.hook`):
- new ink is shown at once with small DU updates, straight to the screen
  (`PenMode.ink`), with pen mode on (`enter`: first waiting for the last
  ordinary update to finish);
- every other update of the screen is watched for where it's sent (the
  screen's refresh…Imp methods): pen mode is turned off first (`leave`),
  once the last ink update has had time to finish (`QUIET`);
- with nothing drawn for a moment the drawing screen turns it off itself
  and does what it left for later (a highlighter's grey, Undo waking up).

If the driver refuses the ioctl (another Kindle, an older firmware), pen
mode is off for good and ink is shown as before. `PenMode.SETTING` (false)
turns it off by hand.

`PenMode.split` (which updates to send for a run of ink) is pure and tested;
`send`, `wait`, `sleep` and `now` can be stood in for.
]]

local PenMode = {
    --- _IOW('F', 0x4C, uint32_t): MXCFB_SET_STYLUS_MODE (hwtcon)
    IOCTL = 0x4004464C,
    --- EPDC_STYLUS_MODE_WITH_NO_TPS, EPDC_STYLUS_MODE_DISABLED
    ON = 1, OFF = 0,
    --- An ink update this big or bigger goes through the driver's slow step (MIN_MDP_SIZE).
    MAX_AREA = 6000,
    --- Seconds an ink update needs to finish on the panel (DU): ordinary updates wait this long after the last one.
    QUIET = 0.3,
    --- An ordinary update sent longer ago than this has finished: not waited for.
    RECENT = 1.5,
    SETTING = "gzreader_drawing_pen_mode",
    on = false,       -- pen mode is on in the driver
    failed = nil,     -- the driver refused: why (never tried again)
    last_ink = 0,     -- when the last ink update was sent
    ordinary = false, -- an ordinary update was sent since pen mode was last on (waited for before the next ink)
    queued = false,   -- an ordinary update is asked for but not sent yet (ink goes the ordinary way meanwhile)
    stats = nil,
}

local IMPS = { "refreshFullImp", "refreshPartialImp", "refreshNoMergePartialImp", "refreshFlashPartialImp",
    "refreshUIImp", "refreshNoMergeUIImp", "refreshFlashUIImp", "refreshFastImp", "refreshA2Imp" }

function PenMode.now()
    local ok, time = pcall(require, "ui/time")
    if ok and time then return time.to_s(time.now()) end
    return os.clock()
end

function PenMode.sleep(seconds)
    local ok, util = pcall(require, "ffi/util")
    if ok and util and util.usleep then util.usleep(math.floor(seconds * 1e6)) end
end

--- The ioctl itself: 0 when the driver took it; else nil and why.
function PenMode.send(screen, mode)
    local ok, rv, err = pcall(function()
        local ffi = require("ffi")
        local arg = ffi.new("uint32_t[1]", mode)
        local r = ffi.C.ioctl(screen.fd, PenMode.IOCTL, arg)
        if r ~= 0 then return r, ffi.errno() end
        return 0
    end)
    if not ok then return nil, tostring(rv) end
    if rv ~= 0 then return nil, "ioctl " .. tostring(rv) .. " errno " .. tostring(err) end
    return 0
end

--- Waits for the last ordinary update to be on the panel.
function PenMode.wait(screen)
    if screen.refreshWaitForLast then pcall(screen.refreshWaitForLast, screen) end
end

--- A Kindle with a pen and the MTK display driver (the Scribe).
function PenMode.capable(device)
    local ok, yes = pcall(function()
        return device ~= nil and device.isKindle ~= nil and device:isKindle() and device.isMTK ~= nil and device:isMTK()
            and device.input ~= nil and device.input.pen_slot ~= nil
    end)
    return ok and yes == true
end

--- …with pen mode not turned off by hand, and not refused by the driver.
function PenMode.supported(device)
    if PenMode.failed then return false end
    local ok, off = pcall(function() return G_reader_settings ~= nil and G_reader_settings:isFalse(PenMode.SETTING) end)
    if ok and off then return false end
    return PenMode.capable(device)
end

local function count(key, n)
    local s = PenMode.stats
    if s then s[key] = (s[key] or 0) + (n or 1) end
end

--- Pen mode on (once the last ordinary update is done). False when it can't be.
function PenMode.enter(screen)
    if PenMode.on then return true end
    if PenMode.failed or PenMode.queued then return false end
    if PenMode.ordinary then
        -- (only one that could still be on its way: the driver is asked about that one update)
        local t = PenMode.now()
        if t - (PenMode.ordinary_at or t) < PenMode.RECENT then
            PenMode.wait(screen)
            count("waited_before", PenMode.now() - t)
        end
        PenMode.ordinary = false
    end
    local ok, why = PenMode.send(screen, PenMode.ON)
    if not ok then
        PenMode.failed = why or "refused"
        return false
    end
    PenMode.on = true
    count("entered")
    return true
end

--- Pen mode off, once the last ink update has had time to finish.
function PenMode.leave(screen)
    if not PenMode.on then return end
    local since = PenMode.now() - PenMode.last_ink
    if since >= 0 and since < PenMode.QUIET then
        PenMode.sleep(PenMode.QUIET - since)
        count("waited_after", PenMode.QUIET - since)
    end
    PenMode.send(screen, PenMode.OFF)
    PenMode.on = false
    -- (KOReader waits for the update before a UI or flashing one to be handed to the
    -- panel; that one was ink sent in pen mode, which the driver may not keep track
    -- of: it has had its time already, so it isn't waited for)
    if screen.marker ~= nil and screen.dont_wait_for_marker ~= nil then screen.dont_wait_for_marker = screen.marker end
end

--- The updates to send for a run of ink: `rects` ({ x, y, w, h }, in the
--- order drawn) joined while what they cover together stays under
--- `max_area` pixels (a small update skips the driver's slow step; one
--- for every sample would be hundreds a second). One too big on its own
--- is cut into strips.
function PenMode.split(rects, max_area)
    max_area = max_area or PenMode.MAX_AREA
    local out = {}
    local cur
    local function push(r)
        if r.w * r.h < max_area then out[#out + 1] = r; return end
        -- (too big on its own: strips along its longer side)
        local n = math.ceil(r.w * r.h / (max_area - 1))
        if r.w >= r.h then
            local step = math.ceil(r.w / n)
            for x = r.x, r.x + r.w - 1, step do out[#out + 1] = { x = x, y = r.y, w = math.min(step, r.x + r.w - x), h = r.h } end
        else
            local step = math.ceil(r.h / n)
            for y = r.y, r.y + r.h - 1, step do out[#out + 1] = { x = r.x, y = y, w = r.w, h = math.min(step, r.y + r.h - y) } end
        end
    end
    for _i, r in ipairs(rects) do
        if r.w > 0 and r.h > 0 then
            if not cur then
                cur = { x = r.x, y = r.y, w = r.w, h = r.h }
            else
                local x0, y0 = math.min(cur.x, r.x), math.min(cur.y, r.y)
                local x1, y1 = math.max(cur.x + cur.w, r.x + r.w), math.max(cur.y + cur.h, r.y + r.h)
                if (x1 - x0) * (y1 - y0) < max_area then
                    cur.x, cur.y, cur.w, cur.h = x0, y0, x1 - x0, y1 - y0
                else
                    push(cur)
                    cur = { x = r.x, y = r.y, w = r.w, h = r.h }
                end
            end
        end
    end
    if cur then push(cur) end
    return out
end

--- New ink in `rects` (screen pixels), shown now in pen mode. False when
--- pen mode can't be used just now (the caller shows it the ordinary way).
function PenMode.ink(screen, rects)
    if not PenMode.enter(screen) then return false end
    local list = PenMode.split(rects)
    PenMode.sending = true
    for _i, r in ipairs(list) do
        local ok, err = pcall(screen.refreshFast, screen, r.x, r.y, r.w, r.h)
        if not ok then PenMode.sending = false; PenMode.failed = tostring(err); return false end
    end
    PenMode.sending = false
    PenMode.last_ink = PenMode.now()
    count("updates", #list)
    count("runs")
    return true
end

--- Watches the screen's updates while a drawing screen is open: an
--- ordinary one turns pen mode off first. `uimanager`: its setDirty (an
--- update asked for) and _repaint (those sent) are watched too, so ink
--- isn't sent in pen mode between the two.
function PenMode.hook(screen, uimanager)
    if PenMode.hooked then return end
    local saved = { screen = screen, ui = uimanager, imps = {} }
    PenMode.hooked = saved
    PenMode.stats = {}
    PenMode.on, PenMode.queued, PenMode.ordinary, PenMode.ordinary_at = false, false, true, PenMode.now()
    for _i, name in ipairs(IMPS) do
        local own = rawget(screen, name)
        local orig = screen[name]
        if orig then
            saved.imps[name] = { own = own }
            rawset(screen, name, function(fb, ...)
                if not PenMode.sending then
                    PenMode.leave(fb)
                    PenMode.ordinary, PenMode.ordinary_at = true, PenMode.now()
                end
                return orig(fb, ...)
            end)
        end
    end
    if uimanager then
        saved.dirty, saved.repaint = rawget(uimanager, "setDirty"), rawget(uimanager, "_repaint")
        local dirty, repaint = uimanager.setDirty, uimanager._repaint
        uimanager.setDirty = function(self, widget, refresh, ...)
            -- (something to paint or to refresh: sent at the next repaint)
            if widget ~= nil or refresh ~= nil then PenMode.queued = true end
            return dirty(self, widget, refresh, ...)
        end
        uimanager._repaint = function(self, ...)
            local r = repaint(self, ...)
            PenMode.queued = false
            return r
        end
    end
end

--- The drawing screen closed: pen mode off, the screen's methods as they were. Returns what happened (numbers).
function PenMode.unhook()
    local saved = PenMode.hooked
    if not saved then return nil end
    PenMode.leave(saved.screen)
    for name, was in pairs(saved.imps) do rawset(saved.screen, name, was.own) end
    if saved.ui then
        rawset(saved.ui, "setDirty", saved.dirty)
        rawset(saved.ui, "_repaint", saved.repaint)
    end
    PenMode.hooked = nil
    local stats = PenMode.stats
    PenMode.stats = nil
    return stats
end

return PenMode
