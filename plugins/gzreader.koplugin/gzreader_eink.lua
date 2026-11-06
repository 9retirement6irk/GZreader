--[[--
Less ghosting on the Kindles without REAGL (Kindle 2, DX, 3, 4).

Their screens have two ways to update: a flash (black, then the picture:
clean) and a partial update (no flash: quick, but a trace of what was there
stays, and traces add up). KOReader flashes the reader every few pages; most
of its other screens update without one, so on a Kindle 3 a menu, a tab or
the quick panel left a grey copy of itself behind (the emulator's
GZ_EMU_GHOST=1 shows it: 10–25 % of the screen).

Here, on those Kindles (Settings → Advanced → Flash when the screen changes;
on by default):
- an update of most of the screen (60 % or more) that isn't a page turn
  flashes: switching tabs, opening or closing a menu, the quick panel, a list's
  next page;
- the first update after a full-screen window opens or closes (a book, a
  full-screen menu) flashes, page or not.
Small updates (the clock, typing) don't, nor does anything the 5-way's arrows
do (moving along the tab bar, around the quick panel or a list: those redraw
the whole screen but flashing at every step is too much). Inside the
audiobook and music players (gz_player windows) and the note editor
(gz_no_flash: typing) nothing flashes but opening and closing them. Page
turns flash
every page, as the Kindle's own reader does, unless a rate was chosen in the
book's menu (Screen → E-ink settings → Full refresh rate; KOReader's default
is every 6 pages, which left a grey trace of the last pages on the page).
]]

local Eink = {
    AREA = 0.6,          -- the share of the screen an update must cover to flash
    SETTING = "gzreader_eink_flash",
    LEGACY = { Kindle2 = true, KindleDXG = true, Kindle3 = true, Kindle4 = true },
}

--- A Kindle without REAGL (einkfb: flash or partial).
function Eink.applies()
    local ok, Device = pcall(require, "device")
    return ok and Device.isKindle and Device:isKindle() and Eink.LEGACY[Device.model] == true or false
end

function Eink.enabled()
    return Eink.applies() and G_reader_settings:readSetting(Eink.SETTING) ~= false
end

function Eink.setEnabled(on)
    G_reader_settings:saveSetting(Eink.SETTING, on and true or false)
    Eink.pageRate()
end

--- Page turns: every one flashes (unless a rate was chosen in the book's menu).
function Eink.pageRate()
    if G_reader_settings:readSetting("full_refresh_count") ~= nil or G_reader_settings:isTrue("night_mode") then return end
    local UIManager = require("ui/uimanager")
    UIManager.FULL_REFRESH_COUNT = Eink.enabled() and 1 or 6
end

local QUIET = { ui = true, ["[ui]"] = true, partial = true, ["[partial]"] = true }

-- The 5-way's arrows (and their repeats)
Eink.ARROWS = { Left = true, Right = true, Up = true, Down = true }
Eink.ARROW_S = 1.5   -- how long after an arrow a big update is still its doing

--- The mode an update gets (pure: run_tests.lua). `region` nil: the whole
--- screen; `pending`: a full-screen window just opened or closed; `arrow`:
--- an arrow key was just pressed (moving the focus).
function Eink.promote(mode, region, screen_w, screen_h, pending, arrow)
    if not QUIET[mode] then return mode, false end
    if arrow and not pending then return mode, false end
    local big = not region or (region.w * region.h >= Eink.AREA * screen_w * screen_h)
    if not big then return mode, false end
    local page_turn = region == nil and (mode == "partial" or mode == "[partial]")
    if page_turn and not pending then return mode, false end
    return region and "flashui" or "full", true
end

--- A window where nothing flashes but its own opening and closing: the
--- audiobook and music players (gz_player), the note editor (gz_no_flash:
--- typing redraws most of the screen, and every key flashed it until 1.23.11).
local function quiet(w) return type(w) == "table" and (w.gz_player == true or w.gz_no_flash == true) end

--- Such a window is open.
function Eink.inPlayer(stack)
    for _i, w in ipairs(stack or {}) do
        if quiet(w.widget) then return true end
    end
    return false
end

--- Does opening or closing `widget` call for a flash? A full-screen window,
--- but inside a quiet one (a player, the note editor) only that one itself.
function Eink.flashesFor(widget, stack)
    if type(widget) ~= "table" or not widget.covers_fullscreen then return false end
    return quiet(widget) or not Eink.inPlayer(stack)
end

function Eink.install()
    if Eink.installed or not Eink.applies() then return end
    Eink.installed = true
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    local time = require("ui/time")
    local orig_refresh = UIManager._refresh
    UIManager._refresh = function(self, mode, region, dither)
        if mode and not self.currently_scrolling and Eink.enabled() then
            local pending = Eink.pending and os.time() - Eink.pending <= 3   -- (an opened window's own update)
            local arrow = Eink.arrow_at and time.to_s(time.now() - Eink.arrow_at) < Eink.ARROW_S
                or Eink.inPlayer(self._window_stack)   -- (in a player: only its own opening flashes)
            local promoted, flashed = Eink.promote(mode, region, Screen:getWidth(), Screen:getHeight(), pending, arrow)
            if flashed then Eink.pending = nil end
            mode = promoted
        end
        return orig_refresh(self, mode, region, dither)
    end
    Eink.pageRate()
    -- the last key: an arrow (focus moving: no flash) or not
    local orig_input = UIManager.handleInputEvent
    UIManager.handleInputEvent = function(self, ev, ...)
        if type(ev) == "table" and (ev.handler == "onKeyPress" or ev.handler == "onKeyRepeat") then
            local key = type(ev.args) == "table" and ev.args[1]
            Eink.arrow_at = type(key) == "table" and Eink.ARROWS[key.key] and time.now() or nil
        end
        return orig_input(self, ev, ...)
    end
    local orig_show, orig_close = UIManager.show, UIManager.close
    UIManager.show = function(self, widget, ...)
        if Eink.flashesFor(widget, self._window_stack) then Eink.pending = os.time() end
        return orig_show(self, widget, ...)
    end
    UIManager.close = function(self, widget, ...)
        if Eink.flashesFor(widget, self._window_stack) then Eink.pending = os.time() end
        return orig_close(self, widget, ...)
    end
end

return Eink
