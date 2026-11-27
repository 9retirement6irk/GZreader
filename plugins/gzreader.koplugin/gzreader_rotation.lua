--[[
Screen rotation in GZreader.

- Auto-rotate: Kindles with an accelerometer (Oasis, Scribe) turn the screen
  when the Kindle is turned. KOReader's `input_ignore_gsensor` switches it off;
  the quick panel's Rotate tile (`Rotation.tile`) switches between Auto and
  Manual, and turns the screen from its side while Manual.
- One rotation everywhere: KOReader gives Home its own rotation (`fm_rotation_mode`,
  portrait unless chosen there) and each book its own, so a book read in
  landscape went back to portrait at Home. GZreader ticks KOReader's "Keep
  current rotation across views" (`lock_rotation`) once (`setup`): Home and
  books stay as the screen is. It can be unticked in About → Advanced →
  KOReader settings → Screen → Rotation.
- GZreader's own full-screen pages (a note, the note editor, a journal entry)
  turn with the screen (`Rotation.follow`): KOReader sends a rotation only to
  the window in front, and those pages had no handler, so turning a Scribe
  while a note was open did nothing. The book or Home under the page is laid
  out again with it, and a page under it (the Notes tab) when it closes
  (`Rotation.settle`).
]]

local Rotation = {}

local function Device() return require("device") end
local function Screen() return require("device").screen end
local function UIManager() return require("ui/uimanager") end
local function _(s) return require("gettext")(s) end

---------------------------------------------------------------- auto-rotate

--- This Kindle has an accelerometer (KOReader's hasGSensor: Oasis, Scribe).
function Rotation.hasAuto()
    local d = Device()
    return d.hasGSensor ~= nil and d:hasGSensor() == true
end

--- Auto-rotate is on (KOReader's default: on).
function Rotation.autoOn()
    return not G_reader_settings:isTrue("input_ignore_gsensor")
end

--- Turns auto-rotate on or off, saved as KOReader saves it.
function Rotation.setAuto(on)
    if on then G_reader_settings:delSetting("input_ignore_gsensor")
    else G_reader_settings:makeTrue("input_ignore_gsensor") end
    local d = Device()
    if d.toggleGSensor then pcall(d.toggleGSensor, d, on and true or false) end
    pcall(function() require("gzreader_log").info("rotation: auto-rotate", on and "on" or "off") end)
end

--- The quick panel's Rotate tile, `turn` turning the screen a quarter.
--- Without an accelerometer: a tap turns the screen. With one (Oasis,
--- Scribe): "Rotate" with Auto or Manual under it, and a tap switches
--- between them (the panel stays open; Auto drawn inverted). While Manual,
--- the tile's bottom quarter (`side`) shows the rotate icon: a tap there
--- turns the screen.
function Rotation.tile(turn)
    if not Rotation.hasAuto() then
        return { id = "rotate", icon = "rotate", label = _("Rotate"), run = turn }
    end
    local auto = Rotation.autoOn()
    return { id = "rotate", icon = auto and "autorotate" or "autorotate_off", label = _("Rotate"),
        sub = auto and _("Auto") or _("Manual"), on = auto, stay = true,
        side = not auto and { icon = "rotate", run = turn } or false,
        refresh = function() return Rotation.tile(turn) end,
        run = function() Rotation.setAuto(not Rotation.autoOn()) end }
end

---------------------------------------------------------------- one rotation

--- Once: Home and books keep the screen's rotation (KOReader's "Keep current
--- rotation across views"), unless it was set either way before.
function Rotation.setup()
    if G_reader_settings:isTrue("gzreader_rotation_kept") then return false end
    G_reader_settings:makeTrue("gzreader_rotation_kept")
    if G_reader_settings:readSetting("lock_rotation") == nil then
        G_reader_settings:makeTrue("lock_rotation")
        pcall(function() require("gzreader_log").info("rotation: Home and books keep the screen's rotation") end)
        return true
    end
    return false
end

---------------------------------------------------------------- GZreader's pages

--- The book (ReaderUI) or Home (FileManager) under everything.
function Rotation.ui()
    local R = package.loaded["apps/reader/readerui"]
    if R and R.instance then return R.instance end
    local F = package.loaded["apps/filemanager/filemanager"]
    return F and F.instance or nil
end

--- Turns the screen to `mode`, laying the book or Home out again with it.
function Rotation.turnScreen(mode)
    local S = Screen()
    if S:getRotationMode() == mode then return false end
    local ui = Rotation.ui()
    local ok = false
    if ui and ui.view and ui.view.onSetRotationMode then
        ok = pcall(ui.view.onSetRotationMode, ui.view, mode)
    elseif ui and ui.onSetRotationMode then
        ok = pcall(ui.onSetRotationMode, ui, mode)
    end
    if not ok or S:getRotationMode() ~= mode then S:setRotationMode(mode) end
    return true
end

--- A page's size no longer matches the screen (it was laid out turned).
function Rotation.stale(widget)
    local d = widget and widget.dimen
    if not (d and d.w and d.h) then return false end
    local S = Screen()
    return d.w ~= S:getWidth() or d.h ~= S:getHeight()
end

--- `widget` (a full-screen page) turned to `mode`: the screen, the book or
--- Home under it, then the page itself (`relayout(widget)`, at the new size).
function Rotation.turn(widget, mode, relayout)
    if mode == nil then return false end
    local turned = Rotation.turnScreen(mode)
    if not turned and not Rotation.stale(widget) then return true end
    widget._gz_turned = true
    local ok, err = pcall(relayout, widget)
    if not ok then pcall(function() require("gzreader_log").warn("rotation: page not laid out again:", tostring(err)) end) end
    UIManager():setDirty("all", "full")
    return true
end

--- A page closed after the screen turned under it: the page now in front, if
--- it was laid out at the old size, is laid out again. Ours by their
--- `gzRelayout`; others (ZenOS's tab pages, KOReader's menus) by sending them
--- the rotation as if the screen were still turned the old way.
function Rotation.settle()
    local UI = UIManager()
    local stack = UI._window_stack or {}
    local top
    for i = #stack, 1, -1 do
        local w = stack[i].widget
        if w and not w.toast then top = w; break end
    end
    if not top or top == Rotation.ui() then return false end
    if not (top.covers_fullscreen and Rotation.stale(top)) then return false end
    if top.gzRelayout then
        local ok = pcall(top.gzRelayout, top)
        top._gz_turned = true -- (and the page under it, when it closes)
        UI:setDirty("all", "full")
        return ok
    end
    if not top.onSetRotationMode then return false end
    local S = Screen()
    local mode = S:getRotationMode()
    S:setRotationMode((mode + 1) % 4) -- (the other way round: the page's handler sees a change)
    local ok, done = pcall(top.onSetRotationMode, top, mode)
    if S:getRotationMode() ~= mode then S:setRotationMode(mode) end
    UI:setDirty("all", "full")
    return ok and done == true
end

--- `Class`'s pages turn with the screen: `relayout(page)` lays one out again
--- at the screen's size, keeping what's on it. Closing one that was turned
--- settles the page under it.
function Rotation.follow(Class, relayout)
    Class.gzRelayout = relayout
    function Class:onSetRotationMode(mode)
        return Rotation.turn(self, mode, relayout)
    end
    local closed = Class.onCloseWidget
    Class.onCloseWidget = function(self, ...)
        local r
        if closed then r = closed(self, ...) end
        if self._gz_turned then
            UIManager():nextTick(function() Rotation.settle() end)
        end
        return r
    end
    return Class
end

return Rotation
