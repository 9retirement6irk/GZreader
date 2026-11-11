--[[--
Less ghosting on the Kindles without REAGL (Kindle 2, DX, 3, 4).

Their screens have two ways to update: a flash (black, then the picture:
clean) and a partial update (no flash: quick, but a trace of what was there
stays, and traces add up). KOReader flashes the reader every few pages; most
of its other screens update without one, so on a Kindle 3 a menu, a tab or
the quick panel left a grey copy of itself behind (the emulator's
GZ_EMU_GHOST=1 shows it: 10–25 % of the screen).

Here, on those Kindles (Settings → General → Screen refresh → Flash when the screen changes;
on by default):
- an update of most of the screen (60 % or more) that isn't a page turn
  flashes: switching tabs, opening or closing a menu, the quick panel, a list's
  next page;
- the first update after a full-screen window opens or closes (a book, a
  full-screen menu) flashes, page or not.
Only what you did flashes: an update with no key or tap in the last INPUT_S
seconds (a book finishing its download and the Downloads tab showing it,
covers arriving, the download status) doesn't, whatever its size; on a
Kindle 3 the whole screen flashed as downloads finished (2026-11-08).
Small updates (the clock, typing) don't, nor does anything the 5-way's arrows
do (moving along the tab bar, around the quick panel or a list: those redraw
the whole screen but flashing at every step is too much). Inside the
audiobook and music players (gz_player windows) and the note editor
(gz_no_flash: typing) nothing flashes but opening and closing them.

Page turns are their own setting (Settings → Reader → Appearance → Flash on
every page turn; on by default on those Kindles, off elsewhere, offered on
every device): on, every page turn flashes, as the Kindle's own reader does;
off, KOReader's every 6 pages (which left a grey trace of the last pages on
a Kindle 3). A rate chosen in the book's menu (Screen → E-ink settings →
Full refresh rate) wins until the setting is changed again.
]]

local Eink = {
    AREA = 0.6,          -- the share of the screen an update must cover to flash
    INPUT_S = 10,        -- s: an update this long after a key or tap is still its doing
    SETTING = "gzreader_eink_flash",
    PAGE_SETTING = "gzreader_flash_page_turns",
    LEGACY = { Kindle2 = true, KindleDXG = true, Kindle3 = true, Kindle4 = true },
}

--- A Kindle without REAGL (einkfb: flash or partial).
function Eink.applies()
    local ok, Device = pcall(require, "device")
    return ok and Device.isKindle and Device:isKindle() and Eink.LEGACY[Device.model] == true or false
end

--- In a book, ZenOS's top bar updates the clock and battery every minute (a
--- partial e-ink refresh while nobody turns a page). On the Kindles without
--- REAGL they're updated with each page instead (every turn repaints the bar;
--- the clock shows the time of the last turn). G_reader_settings
--- "gzreader_reader_clock_minute": true/false to choose.
Eink.CLOCK_SETTING = "gzreader_reader_clock_minute"
function Eink.minuteClock()
    local v = G_reader_settings:readSetting(Eink.CLOCK_SETTING)
    if v ~= nil then return v == true end
    return not Eink.applies()
end

function Eink.enabled()
    return Eink.applies() and G_reader_settings:readSetting(Eink.SETTING) ~= false
end

function Eink.setEnabled(on)
    G_reader_settings:saveSetting(Eink.SETTING, on and true or false)
end

--- Every page turn flashes: the setting, or by default on the Kindles
--- without REAGL (Kindle 2, DX, 3, 4). Until 1.26.7 it went with
--- "Flash when the screen changes"; turned off there, it stays off here.
function Eink.flashPageTurns()
    local on = G_reader_settings:readSetting(Eink.PAGE_SETTING)
    if on ~= nil then return on == true end
    if Eink.applies() and G_reader_settings:readSetting(Eink.SETTING) == false then return false end
    return Eink.applies()
end

--- The setting's tick: also right when a rate was chosen in a book's menu
--- (ticked for "every page").
function Eink.pageTurnsTicked()
    if Eink.rateChosen() then return G_reader_settings:readSetting("full_refresh_count") == 1 end
    return Eink.flashPageTurns()
end

--- Turning it on or off also drops a rate chosen in a book's menu (the
--- latest choice counts; that menu can set one again).
function Eink.setFlashPageTurns(on)
    G_reader_settings:saveSetting(Eink.PAGE_SETTING, on and true or false)
    G_reader_settings:delSetting("full_refresh_count")
    Eink.pageRate()
end

--- A refresh rate chosen in the book's menu: it wins over the setting.
function Eink.rateChosen()
    return G_reader_settings:readSetting("full_refresh_count") ~= nil
end

--- Page turns: every one flashes, or KOReader's every 6 (unless a rate was
--- chosen in the book's menu, or night mode sets its own).
function Eink.pageRate()
    if Eink.rateChosen() or G_reader_settings:isTrue("night_mode") then return end
    local UIManager = require("ui/uimanager")
    UIManager.FULL_REFRESH_COUNT = Eink.flashPageTurns() and 1 or 6
end

local QUIET = { ui = true, ["[ui]"] = true, partial = true, ["[partial]"] = true }

-- The 5-way's arrows (and their repeats)
Eink.ARROWS = { Left = true, Right = true, Up = true, Down = true }
Eink.ARROW_S = 1.5   -- how long after an arrow a big update is still its doing

--- The mode an update gets (pure: run_tests.lua). `region` nil: the whole
--- screen; `pending`: a full-screen window just opened or closed; `arrow`:
--- an arrow key was just pressed (moving the focus); `background`: no key or
--- tap for INPUT_S seconds (nothing you did: no flash).
function Eink.promote(mode, region, screen_w, screen_h, pending, arrow, background)
    if not QUIET[mode] then return mode, false end
    if (arrow or background) and not pending then return mode, false end
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
    if Eink.installed then return end
    Eink.installed = true
    -- (every device: page turns can flash anywhere)
    Eink.pageRate()
    if not Eink.applies() then return end
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    local time = require("ui/time")
    local orig_refresh = UIManager._refresh
    UIManager._refresh = function(self, mode, region, dither)
        if mode and not self.currently_scrolling and Eink.enabled() then
            local pending = Eink.pending and os.time() - Eink.pending <= 3   -- (an opened window's own update)
            local arrow = Eink.arrow_at and time.to_s(time.now() - Eink.arrow_at) < Eink.ARROW_S
                or Eink.inPlayer(self._window_stack)   -- (in a player: only its own opening flashes)
            local background = not (Eink.input_at and time.to_s(time.now() - Eink.input_at) < Eink.INPUT_S)
            local promoted, flashed = Eink.promote(mode, region, Screen:getWidth(), Screen:getHeight(), pending, arrow, background)
            if flashed then Eink.pending = nil end
            mode = promoted
        end
        return orig_refresh(self, mode, region, dither)
    end
    -- the last key: an arrow (focus moving: no flash) or not
    local orig_input = UIManager.handleInputEvent
    UIManager.handleInputEvent = function(self, ev, ...)
        if type(ev) == "table" and ev.handler ~= "onKeyRelease" then Eink.input_at = time.now() end -- (a key or a tap)
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
