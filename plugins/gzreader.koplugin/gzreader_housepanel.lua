--[[--
The House tab's controls in the Bookshelf view (the other views keep the
windows of buttons, gzreader_house.lua): what opens when a dimmable light,
a thermostat or a speaker is tapped, drawn as the thing itself.

- a dimmer: a column of ten indicator lights, each a level to tap (the ones
  up to the light's level lit), a rocker (On over Off, the half that's
  pressed sunk), − and + for a step, and the bulb's colours as round gels;
- a thermostat: its dial, large, the target in the middle, round − and +
  keys either side, and its modes on a slide switch (the one it's in
  pressed in);
- choosing music (a Music Assistant player's Music… key): a key for each
  of its shelves, with what stands on it (a cassette for playlists, a
  record in its sleeve for albums, a record for artists, a radio), Search…
  and Back;
- a speaker or TV: a display window (what plays, who by, the volume), the
  transport keys, the volume as ten lights between − and +, Mute, Shuffle
  and Repeat as keys with a lamp each, Music… and the power key: the ones
  the player can do.

Each press does what the window's button did (House:run), and the panel
stays open, showing what came back. A level (a volume, a brightness, a
target) shows at once and is sent when the presses stop (House:level). A tap outside it, × or Back closes it.
On a Kindle with a keyboard the keys carry letters (not the twenty lights:
the 5-way reaches those) and the 5-way moves a frame from control to
control; Press presses.

`Panel.spec` says what is on a panel and where (in its own units, 420
wide): pure, tested in run_tests.lua. The widget scales it to the screen.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local T = require("ffi/util").template
local _ = require("gettext")

local Screen = Device.screen

local Panel = {
    W = 420,                       -- a panel's width in its own units
    LETTERS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F", "G", "H", "J", "K", "L" },
}

local function HA() return require("gzreader_homeassistant") end
local function Shop() return require("gzreader_bookshop") end
local function View() return require("gzreader_houseview") end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function gray(v) return Blitbuffer.gray(clamp(v, 0, 1)) end

--- The panels instead of the windows of buttons: in the Bookshelf view.
function Panel.wanted()
    local ok, yes = pcall(function() return Shop().bookshelf() end)
    return ok and yes == true
end

---------------------------------------------------------------- what's on a panel

--- What a panel shows for device `e`: { kind, title, state, w, h, controls }.
--- A control: { id, kind ("key", "seg", "swatch", "lcd", "art", "label"),
--- x, y, w, h, label, sym, on (pressed in), lamp (true/false: it has one,
--- lit or not), lit (a light of a ladder), dim (can't be pressed now),
--- round, act = { what, arg } (House:run) or open ("music", "close") }.
--- `o`: { label (the device's name), unit (the thermostat's), touch }.
function Panel.spec(kind, e, o)
    local Ha = HA()
    o = o or {}
    local W = Panel.W
    local P = { kind = kind, title = o.label or e.name or e.id, state = Ha.stateText(e) or "", w = W, controls = {} }
    local function add(c) P.controls[#P.controls + 1] = c; return c end
    if o.touch then add({ id = "close", kind = "key", x = W - 56, y = 12, w = 40, h = 34, sym = "close", open = "close" }) end
    local on = e.state == "on"

    if kind == "light" then
        local level = on and clamp(math.ceil((e.bri or 100) / 10), 1, 10) or 0
        for i = 10, 1, -1 do
            add({ id = "level" .. i * 10, kind = "seg", x = 28, y = 64 + (10 - i) * 28, w = 124, h = 24, label = i * 10 .. "%",
                lit = i <= level, act = { "brightness", i * 10 } })
        end
        add({ id = "on", kind = "key", x = 176, y = 64, w = 216, h = 92, label = _("On"), on = on, act = { "on" }, big = true })
        add({ id = "off", kind = "key", x = 176, y = 164, w = 216, h = 92, label = _("Off"), on = not on, act = { "off" }, big = true })
        local cur = on and (e.bri or 100) or 0
        add({ id = "down", kind = "key", x = 176, y = 272, w = 104, h = 68, sym = "minus", dim = not (on and cur > 1),
            act = { "brightness", math.max(1, cur - 10) } })
        add({ id = "up", kind = "key", x = 288, y = 272, w = 104, h = 68, sym = "plus", dim = cur >= 100,
            act = { "brightness", math.min(100, cur + 10) } })
        P.h = 364
        if e.col then
            -- a bulb that takes a colour: round gels, the one it has now ringed
            local n = #Ha.BULB_COLORS
            local sw = math.floor((W - 56) / n)
            for i, c in ipairs(Ha.BULB_COLORS) do
                add({ id = "color" .. i, kind = "swatch", x = 28 + (i - 1) * sw, y = 360, w = sw - 4, h = 64, label = c[2], color = c[1],
                    on = on and e.rgb == c[1], act = { "color", c[1] } })
            end
            P.h = 440
        end

    elseif kind == "climate" then
        local fit = View().fitting(e, o.colour)
        add({ id = "dial", kind = "art", x = 100, y = 58, w = 220, h = 251, fit = fit, text = fit.text })
        local function step(id, dir, x)
            local t = Ha.nextTarget(e, dir, o.unit)
            add({ id = id, kind = "key", x = x, y = 148, w = 68, h = 68, round = true, sym = dir < 0 and "minus" or "plus",
                dim = not (e.target ~= nil and t ~= e.target), act = { "target", t } })
        end
        step("cooler", -1, 24)
        step("warmer", 1, 328)
        local now = {}
        if e.cur then now[#now + 1] = T(_("%1 now"), Ha.fmt(e.cur) .. "°") end
        if e.action and e.action ~= "idle" and e.action ~= "off" then now[#now + 1] = e.action end
        add({ id = "now", kind = "label", x = 24, y = 312, w = W - 48, h = 24, label = table.concat(now, " · ") })
        P.h = 352
        if e.modes and #e.modes > 0 then
            -- its modes on a slide switch: the one it's in pressed in
            local n = #e.modes
            local mw = math.floor((W - 48) / n)
            add({ id = "track", kind = "track", x = 24, y = 346, w = mw * n, h = 52 })
            for i, m in ipairs(e.modes) do
                add({ id = "mode_" .. m, kind = "key", x = 24 + (i - 1) * mw + 3, y = 349, w = mw - 6, h = 46, label = Ha.modeName(m),
                    on = e.state == m, flat = true, act = { "mode", m } })
            end
            P.h = 416
        end

    elseif kind == "media" then
        local off = e.state == "off" or e.state == "standby"
        local playing = e.state == "playing" or e.state == "buffering"
        local lines = {}
        if (playing or e.state == "paused") and e.title then
            lines[1] = e.title
            lines[2] = e.artist
        end
        local last = Ha.stateText(e) or ""
        if e.title and (playing or e.state == "paused") then last = playing and _("Playing") or _("Paused") end
        if e.vol then last = last .. " · " .. (e.muted and T(_("Volume %1% · muted"), e.vol) or T(_("Volume %1%"), e.vol)) end
        add({ id = "display", kind = "lcd", x = 28, y = 58, w = W - 56, h = 86, lines = lines, foot = last })
        -- the transport keys
        if Ha.can(e, "previous") then add({ id = "previous", kind = "key", x = 28, y = 158, w = 110, h = 62, sym = "previous", dim = off, act = { "previous" } }) end
        if Ha.can(e, "play") or Ha.can(e, "pause") then
            add({ id = "play_pause", kind = "key", x = 148, y = 158, w = 124, h = 62, sym = playing and "pause" or "play", dim = off, act = { "play_pause" } })
        end
        if Ha.can(e, "next") then add({ id = "next", kind = "key", x = 282, y = 158, w = 110, h = 62, sym = "next", dim = off, act = { "next" } }) end
        -- the volume: ten lights between − and +
        if Ha.can(e, "volume_set") and e.vol then
            add({ id = "quieter", kind = "key", x = 28, y = 236, w = 46, h = 46, sym = "minus", dim = e.vol <= 0, act = { "volume", Ha.nextVolume(e, -1) } })
            for i = 1, 10 do
                add({ id = "volume" .. i * 10, kind = "seg", x = 82 + (i - 1) * 26, y = 236, w = 22, h = 46, lit = e.vol >= i * 10 - 5, tall = true,
                    act = { "volume", i * 10 } })
            end
            add({ id = "louder", kind = "key", x = 346, y = 236, w = 46, h = 46, sym = "plus", dim = e.vol >= 100, act = { "volume", Ha.nextVolume(e, 1) } })
        elseif Ha.can(e, "volume_step") then
            add({ id = "quieter", kind = "key", x = 28, y = 236, w = 178, h = 46, label = _("Quieter"), act = { "volume_down" } })
            add({ id = "louder", kind = "key", x = 214, y = 236, w = 178, h = 46, label = _("Louder"), act = { "volume_up" } })
        end
        -- mute, shuffle, repeat: a key with a lamp each
        if Ha.can(e, "volume_mute") then
            add({ id = "mute", kind = "key", x = 28, y = 298, w = 116, h = 52, label = _("Mute"), lamp = e.muted == true, act = { "mute" } })
        end
        if Ha.can(e, "shuffle") and e.shuffle ~= nil then
            add({ id = "shuffle", kind = "key", x = 152, y = 298, w = 116, h = 52, label = _("Shuffle"), lamp = e.shuffle == true, act = { "shuffle" } })
        end
        if Ha.can(e, "repeat") and e.rep then
            local words = { off = _("Repeat"), all = _("Repeat all"), one = _("Repeat one") }
            add({ id = "repeat", kind = "key", x = 276, y = 298, w = 116, h = 52, label = words[e.rep], lamp = e.rep ~= "off", act = { "repeat" } })
        end
        -- music (Music Assistant's players) and the power key
        local music = e.ma and e.entry and Ha.can(e, "play_media")
        local power = (off and Ha.can(e, "turn_on") and { _("Turn on"), "media_on" }) or (not off and Ha.can(e, "turn_off") and { _("Turn off"), "media_off" }) or nil
        if music then add({ id = "music", kind = "key", x = 28, y = 362, w = power and 178 or 364, h = 52, label = _("Music…"), open = "music" }) end
        if power then
            add({ id = "power", kind = "key", x = music and 214 or 28, y = 362, w = music and 178 or 364, h = 52, label = power[1], sym = "power", act = { power[2] } })
        end
        P.h = 430
        -- (a player with few buttons: no gaps where the others would be)
        Panel.close(P, { 158, 236, 298, 362 })

    elseif kind == "music" then
        -- what to play on it: Music Assistant's shelves, a search, or back to its buttons
        local Music = require("gzreader_housemusic")
        local art = { playlist = "cassette", album = "sleeve", artist = "disc", radio = "radio" }
        P.title = T(_("Play on %1"), P.title)
        P.state = ""
        for i, k in ipairs(Ha.MUSIC_KINDS) do
            add({ id = k[1], kind = "key", x = 28 + ((i - 1) % 2) * 186, y = 60 + math.floor((i - 1) / 2) * 136, w = 178, h = 124, label = k[2],
                fit = Music.art(art[k[1]] or "disc"), open = "list", media_type = k[1] })
        end
        local y = 60 + math.ceil(#Ha.MUSIC_KINDS / 2) * 136
        add({ id = "search", kind = "key", x = 28, y = y, w = 240, h = 52, label = _("Search…"), open = "search" })
        add({ id = "back", kind = "key", x = 276, y = y, w = 116, h = 52, label = _("Back"), open = "back" })
        P.h = y + 68
    end
    return P
end

--- Take out a panel's empty rows: what is on or below a row with nothing
--- in it moves up by that row's height. `rows`: the rows' y, top to bottom.
function Panel.close(P, rows)
    local shift, to = 0, {}
    for i, y in ipairs(rows) do
        local used = false
        for _j, c in ipairs(P.controls) do if c.y == y then used = true end end
        to[y] = y - shift
        if not used then shift = shift + ((rows[i + 1] or (P.h - 16)) - y) end
    end
    for _j, c in ipairs(P.controls) do if to[c.y] then c.y = to[c.y] end end
    P.h = P.h - shift
    return P
end

--- Whether a control can be pressed.
function Panel.pressable(c)
    return type(c) == "table" and (c.act ~= nil or c.open ~= nil) and not c.dim
end

--- Letters for a panel's keys, in order (the lights of a ladder have none:
--- the 5-way reaches them): { [letter] = control }, and each control's
--- `letter` set.
function Panel.letters(P)
    local by, n = {}, 0
    for _i, c in ipairs(P.controls) do
        c.letter = nil
        if Panel.pressable(c) and c.kind ~= "seg" and c.kind ~= "swatch" and c.id ~= "close" then
            n = n + 1
            c.letter = Panel.LETTERS[n]
            if c.letter then by[c.letter] = c end
        end
    end
    return by
end

--- From control `cur` (an index, or nil), the control the 5-way moves the
--- frame to in direction `dir` ("up", "down", "left", "right"): the nearest
--- pressable one that way, or `cur` when there is none.
function Panel.move(P, cur, dir)
    local from = cur and P.controls[cur]
    if not from then
        for i, c in ipairs(P.controls) do if Panel.pressable(c) and c.id ~= "close" then return i end end
        return cur
    end
    local fx, fy = from.x + from.w / 2, from.y + from.h / 2
    local best, best_d
    for i, c in ipairs(P.controls) do
        if i ~= cur and Panel.pressable(c) then
            local dx, dy = c.x + c.w / 2 - fx, c.y + c.h / 2 - fy
            local along, across, beside
            if dir == "left" or dir == "right" then
                along, across = dir == "left" and -dx or dx, math.abs(dy)
                beside = c.y < from.y + from.h and from.y < c.y + c.h
            else
                along, across = dir == "up" and -dy or dy, math.abs(dx)
                beside = c.x < from.x + from.w and from.x < c.x + c.w
            end
            -- that way: in line with this one, or more that way than sideways
            if along > 1 and (beside or across <= along) then
                local d = along + (beside and 0 or across * 2)
                if not best_d or d < best_d then best, best_d = i, d end
            end
        end
    end
    return best or cur
end

--- The control at a point of the panel (its own units), or nil.
function Panel.at(P, x, y)
    for i = #P.controls, 1, -1 do
        local c = P.controls[i]
        if Panel.pressable(c) and x >= c.x - 2 and x < c.x + c.w + 2 and y >= c.y - 2 and y < c.y + c.h + 2 then return c, i end
    end
end

---------------------------------------------------------------- the widget

local Widget = InputContainer:extend{ name = "gzreader house panel", tab = nil, kind = nil, e = nil }

function Widget:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local back = Device.input and Device.input.group and Device.input.group.Back or "Back"
    self.key_events = {
        Close = { { back } },
        MoveUp = { { "Up" } }, MoveDown = { { "Down" } }, MoveLeft = { { "Left" } }, MoveRight = { { "Right" } },
        Press = { { "Press" } },
        Letter = { { Panel.LETTERS } },
    }
    if Device:isTouchDevice() then
        self.ges_events = { TapPanel = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    self.letters = Device:hasKeyboard()            -- (letters on the keys)
    self.frame = Device:hasDPad()                  -- (the 5-way's frame)
    self:setDevice(self.e)
end

--- Show device `e` (as it is now).
function Widget:setDevice(e)
    self.e = e
    local tab = self.tab
    local focus_id = self.P and self.focus and self.P.controls[self.focus] and self.P.controls[self.focus].id
    self.P = Panel.spec(self.kind, e, { label = tab:label(e), unit = tab:unit(), touch = Device:isTouchDevice(),
        colour = require("gzreader_colour").enabled() })
    self.by_letter = self.letters and Panel.letters(self.P) or {}
    self.focus = nil
    if self.frame then
        for i, c in ipairs(self.P.controls) do if c.id == focus_id and Panel.pressable(c) then self.focus = i end end
        self.focus = self.focus or Panel.move(self.P, nil, "down")
    end
    -- its place on the screen: as wide as fits, in the middle
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local k = math.min((sw - Screen:scaleBySize(24)) / self.P.w, (sh - Screen:scaleBySize(40)) / self.P.h, Screen:scaleBySize(100) / 100 * 1.25)
    self.k = k
    local w, h = math.floor(self.P.w * k), math.floor(self.P.h * k)
    local old = self.box
    self.box = Geom:new{ x = math.floor((sw - w) / 2), y = math.floor((sh - h) / 2), w = w, h = h }
    return old
end

function Widget:getSize() return Geom:new{ w = self.dimen.w, h = self.dimen.h } end

local function face(px, bold)
    local size = math.max(7, math.floor(px / Screen:scaleBySize(1) + 0.5))
    return Font:getFace(bold and "smalltfont" or "cfont", size)
end

local function words(bb, str, px, bold, cx, cy, max_w, color)
    if not str or str == "" then return end
    local TextWidget = require("ui/widget/textwidget")
    local tw
    for _i, s in ipairs({ px, px * 0.86, px * 0.74 }) do
        if tw then tw:free() end
        tw = TextWidget:new{ text = str, face = face(s, bold), bold = bold, fgcolor = color, max_width = max_w }
        if not tw:isTruncated() then break end
    end
    local sz = tw:getSize()
    tw:paintTo(bb, math.floor(cx - sz.w / 2), math.floor(cy - sz.h / 2))
    tw:free()
end

--- A triangle pointing left (dir -1) or right (1), w wide and h high.
local function triangle(bb, x, y, w, h, dir, color)
    for i = 0, w - 1 do
        local t = dir > 0 and (w - i) / w or (i + 1) / w
        local hh = math.max(1, math.floor(h * t))
        bb:paintRect(x + i, y + math.floor((h - hh) / 2), 1, hh, color)
    end
end

--- A key's mark instead of a word: − + × ▶ ❚❚ ⏮ ⏭.
local function symbol(bb, sym, cx, cy, u, color)
    local t = math.max(2, math.floor(u * 0.22))
    if sym == "minus" or sym == "plus" then
        bb:paintRect(cx - u, cy - math.floor(t / 2), 2 * u, t, color)
        if sym == "plus" then bb:paintRect(cx - math.floor(t / 2), cy - u, t, 2 * u, color) end
    elseif sym == "close" then
        for i = -u, u do
            bb:paintRect(cx + i - math.floor(t / 2), cy + i - math.floor(t / 2), t, t, color)
            bb:paintRect(cx + i - math.floor(t / 2), cy - i - math.floor(t / 2), t, t, color)
        end
    elseif sym == "play" then
        triangle(bb, cx - math.floor(u * 0.8), cy - u, math.floor(u * 1.8), 2 * u, 1, color)
    elseif sym == "pause" then
        local bw = math.floor(u * 0.6)
        bb:paintRect(cx - bw - math.floor(u * 0.25), cy - u, bw, 2 * u, color)
        bb:paintRect(cx + math.floor(u * 0.25), cy - u, bw, 2 * u, color)
    elseif sym == "next" or sym == "previous" then
        local dir = sym == "next" and 1 or -1
        local tw = math.floor(u * 1.1)
        local bw = math.max(2, math.floor(u * 0.3))
        local x0 = cx - tw - math.floor(bw / 2)
        if dir > 0 then
            triangle(bb, x0, cy - u, tw, 2 * u, 1, color)
            triangle(bb, x0 + tw, cy - u, tw, 2 * u, 1, color)
            bb:paintRect(x0 + 2 * tw, cy - u, bw, 2 * u, color)
        else
            bb:paintRect(x0, cy - u, bw, 2 * u, color)
            triangle(bb, x0 + bw, cy - u, tw, 2 * u, -1, color)
            triangle(bb, x0 + bw + tw, cy - u, tw, 2 * u, -1, color)
        end
    end
end

--- A letter's badge (Kindles with a keyboard).
local function badge(bb, letter, x, y, side)
    bb:paintRect(x, y, side, side, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, side, side, math.max(1, math.floor(side / 12)), Blitbuffer.COLOR_BLACK, math.floor(side / 6))
    words(bb, letter, side * 0.62, true, x + side / 2, y + side / 2)
end

function Widget:paintControl(bb, c, r)
    local k = self.k
    local function s(v) return math.max(1, math.floor(v * k + 0.5)) end
    local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
    local bw = math.max(2, s(2.5))
    if c.kind == "key" then
        local rad = c.round and math.floor(r.h / 2) or s(8)
        local drop = c.flat and 0 or s(5)
        local ink = c.dim and gray(0.4) or BLACK
        local y = r.y
        if c.on then
            -- pressed in: sunk by its drop, darker, no shadow under it
            y = r.y + drop
            bb:paintRoundedRect(r.x, y, r.w, r.h, c.flat and BLACK or gray(0.22), rad)
            if c.flat then ink = WHITE end
        else
            if drop > 0 and not c.dim then bb:paintRoundedRect(r.x, r.y + drop, r.w, r.h, gray(0.55), rad) end
            bb:paintRoundedRect(r.x, y, r.w, r.h, c.flat and gray(0.04) or WHITE, rad)
        end
        if not (c.flat and not c.on) then bb:paintBorder(r.x, y, r.w, r.h, bw, c.dim and gray(0.4) or BLACK, rad) end
        local cx, cy = r.x + r.w / 2, y + r.h / 2
        if c.lamp ~= nil then
            -- its lamp: lit or not, above the word
            local lr = s(5)
            local ly = y + s(11)
            if c.lamp then bb:paintCircle(math.floor(cx), ly, lr, BLACK)
            else
                bb:paintCircle(math.floor(cx), ly, lr, WHITE)
                bb:paintCircle(math.floor(cx), ly, lr, BLACK, math.max(1, s(1.5)))
            end
            cy = cy + s(7)
        end
        if c.fit then
            -- a drawing above its word
            local ah = r.h - s(40)
            local aw = math.floor(ah * 200 / 160)
            local img = View().artImage(c.fit, aw, ah)
            if img then bb:alphablitFrom(img, math.floor(cx - img:getWidth() / 2), y + s(8), 0, 0, img:getWidth(), img:getHeight()) end
            words(bb, c.label, s(17), true, cx, y + r.h - s(18), r.w - s(10), ink)
        elseif c.label then
            words(bb, c.label, s(c.big and 30 or 17), c.big or c.on, cx, cy, r.w - s(10), ink)
        elseif c.sym then
            symbol(bb, c.sym, math.floor(cx), math.floor(cy), s(c.sym == "close" and 8 or math.min(c.w, c.h) * 0.2), ink)
        end
        if c.letter then badge(bb, c.letter, r.x - s(6), r.y - s(6), s(22)) end
    elseif c.kind == "seg" then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, c.lit and BLACK or WHITE, s(3))
        bb:paintBorder(r.x, r.y, r.w, r.h, bw, BLACK, s(3))
        if c.label then words(bb, c.label, s(15), c.lit, r.x + r.w / 2, r.y + r.h / 2, r.w - s(6), c.lit and WHITE or gray(0.75)) end
    elseif c.kind == "swatch" then
        local rr = math.floor(math.min(r.w, s(38)) / 2)
        local cx, cy = math.floor(r.x + r.w / 2), r.y + rr + s(3)
        local R, G, B = tonumber(c.color:sub(2, 3), 16) or 0, tonumber(c.color:sub(4, 5), 16) or 0, tonumber(c.color:sub(6, 7), 16) or 0
        -- (a grey screen: each gel a different grey, by how light the colour is)
        local col = require("gzreader_colour").enabled() and Blitbuffer.ColorRGB32(R, G, B, 0xFF)
            or gray(1 - (0.3 * R + 0.59 * G + 0.11 * B) / 255)
        bb:paintCircle(cx, cy, rr, col)
        bb:paintCircle(cx, cy, rr, BLACK, c.on and math.max(3, s(5)) or math.max(1, s(2)))
        words(bb, c.label, s(12), c.on, cx, r.y + r.h - s(8), r.w + s(2))
    elseif c.kind == "lcd" then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, BLACK, s(6))
        bb:paintBorder(r.x + s(4), r.y + s(4), r.w - s(8), r.h - s(8), 1, gray(0.55), s(4))
        local cx = r.x + r.w / 2
        if c.lines and c.lines[1] then
            words(bb, c.lines[1], s(19), true, cx, r.y + s(22), r.w - s(24), WHITE)
            words(bb, c.lines[2], s(15), false, cx, r.y + s(44), r.w - s(24), WHITE)
            words(bb, c.foot, s(13), false, cx, r.y + r.h - s(16), r.w - s(24), gray(0.2))
        else
            words(bb, c.foot, s(18), true, cx, r.y + r.h / 2, r.w - s(24), WHITE)
        end
    elseif c.kind == "track" then
        bb:paintRoundedRect(r.x, r.y, r.w, r.h, gray(0.3), s(10))
        bb:paintRoundedRect(r.x + s(2), r.y + s(2), r.w - s(4), r.h - s(4), gray(0.1), s(9))
        bb:paintBorder(r.x, r.y, r.w, r.h, bw, BLACK, s(10))
    elseif c.kind == "art" then
        local img = View().artImage(c.fit, r.w, r.h)
        if img then bb:alphablitFrom(img, r.x + math.floor((r.w - img:getWidth()) / 2), r.y, 0, 0, img:getWidth(), img:getHeight()) end
        if c.text then
            local kk = r.w / View().VB_W
            words(bb, c.text, 50 * kk, true, r.x + 114 * kk, r.y + 126 * kk)
        end
    elseif c.kind == "label" then
        words(bb, c.label, s(16), false, r.x + r.w / 2, r.y + r.h / 2, r.w, gray(0.85))
    end
end

function Widget:paintTo(bb, x, y)
    local P, k, box = self.P, self.k, self.box
    local function s(v) return math.max(1, math.floor(v * k + 0.5)) end
    local BLACK = Blitbuffer.COLOR_BLACK
    local bx, by = x + box.x, y + box.y
    -- the panel: a plate with a screw in each corner
    bb:paintRoundedRect(bx + s(8), by + s(8), box.w, box.h, gray(0.45), s(14))
    bb:paintRoundedRect(bx, by, box.w, box.h, gray(0.07), s(14))
    bb:paintBorder(bx, by, box.w, box.h, math.max(2, s(3)), BLACK, s(14))
    bb:paintBorder(bx + s(6), by + s(6), box.w - s(12), box.h - s(12), 1, gray(0.3), s(9))
    for _i, p in ipairs({ { 14, 14 }, { P.w - 14, P.h - 14 }, { 14, P.h - 14 }, { P.w - 14, 14 } }) do
        -- (not under the × on a touch screen)
        if not (self.P.controls[1] and self.P.controls[1].id == "close" and p[1] > P.w / 2 and p[2] < P.h / 2) then
            bb:paintCircle(bx + s(p[1]), by + s(p[2]), s(5), gray(0.2))
            bb:paintCircle(bx + s(p[1]), by + s(p[2]), s(5), BLACK, math.max(1, s(1.2)))
        end
    end
    -- its name on label tape
    local TextWidget = require("ui/widget/textwidget")
    local name = TextWidget:new{ text = tostring(P.title):upper(), face = face(s(15), true), bold = true, fgcolor = Blitbuffer.COLOR_WHITE,
        max_width = box.w - s(120) }
    local nsz = name:getSize()
    local tx, ty, th = bx + s(28), by + s(16), s(28)
    bb:paintRect(tx + s(3), ty + s(3), nsz.w + s(22), th, gray(0.35))
    bb:paintRect(tx, ty, nsz.w + s(22), th, BLACK)
    name:paintTo(bb, tx + s(11), ty + math.floor((th - nsz.h) / 2))
    name:free()
    if P.kind == "light" then
        -- (what it is now, beside its name: the dimmer has no display of its own)
        words(bb, P.state, s(16), false, bx + (s(28) + nsz.w + s(22) + box.w - s(60)) / 2, ty + th / 2, box.w - nsz.w - s(130), gray(0.85))
    end
    self.rects = {}
    for i, c in ipairs(P.controls) do
        local r = { x = bx + s(c.x), y = by + s(c.y), w = s(c.w), h = s(c.h) }
        self.rects[i] = r
        self:paintControl(bb, c, r)
    end
    local f = self.focus and self.rects[self.focus]
    if f then
        local o = s(4)
        bb:paintBorder(f.x - o, f.y - o, f.w + 2 * o, f.h + 2 * o + (self.P.controls[self.focus].kind == "key" and not self.P.controls[self.focus].flat and s(5) or 0),
            math.max(2, s(3)), BLACK, s(6))
    end
end

function Widget:dirty(old)
    local r = self.box
    if old then r = old:combine(self.box) end
    local pad = Screen:scaleBySize(16)
    UIManager:setDirty(self, function() return "ui", Geom:new{ x = r.x - pad, y = r.y - pad, w = r.w + 2 * pad, h = r.h + 2 * pad } end)
end

function Widget:onShow()
    self:dirty()
    return true
end

function Widget:onCloseWidget()
    self.closed = true
    local r = self.box
    local pad = Screen:scaleBySize(16)
    UIManager:setDirty(nil, function() return "ui", Geom:new{ x = r.x - pad, y = r.y - pad, w = r.w + 2 * pad, h = r.h + 2 * pad } end)
end

function Widget:onClose()
    UIManager:close(self)
    return true
end

--- The device as the tab has it now (it was switched, or refreshed).
function Widget:sync()
    local now = HA().find(self.tab.house, self.e.id)
    if not now or self.closed then return end
    local old = self:setDevice(now)
    self:dirty(old)
end

--- Press a control: what its button did in the window; the tab draws
--- itself again when Home Assistant has answered, and this panel with it.
function Widget:press(c)
    if not Panel.pressable(c) then return true end
    local tab = self.tab
    if c.open == "close" then return self:onClose() end
    if c.open == "music" then
        UIManager:close(self)
        tab:musicDialog(self.e)
        return true
    end
    if c.open == "list" then
        UIManager:close(self)
        tab:musicList(self.e, c.media_type, c.label, 0)
        return true
    end
    if c.open == "search" then
        UIManager:close(self)
        tab:musicSearch(self.e)
        return true
    end
    if c.open == "back" then
        UIManager:close(self)
        tab:mediaDialog(HA().find(tab.house, self.e.id) or self.e)
        return true
    end
    -- a level (a volume, a brightness, a target): shown at once, sent when the presses stop
    if HA().LEVELS[c.act[1]] then tab:level(self.e, c.act[1], c.act[2])
    else tab:run(self.e, c.act[1], c.act[2]) end
    return true
end

function Widget:onTapPanel(_arg, ges)
    local box = self.box
    if not ges or not ges.pos or not ges.pos:intersectWith(box) then return self:onClose() end
    local c = Panel.at(self.P, (ges.pos.x - box.x) / self.k, (ges.pos.y - box.y) / self.k)
    if c then self:press(c) end
    return true
end

function Widget:onLetter(_arg, key)
    local c = key and self.by_letter[key.key]
    if c then self:press(c) end
    return true
end

function Widget:onPress()
    local c = self.focus and self.P.controls[self.focus]
    if c then self:press(c) end
    return true
end

function Widget:step(dir)
    local to = Panel.move(self.P, self.focus, dir)
    if to ~= self.focus then
        self.focus = to
        self:dirty()
    end
    return true
end
function Widget:onMoveUp() return self:step("up") end
function Widget:onMoveDown() return self:step("down") end
function Widget:onMoveLeft() return self:step("left") end
function Widget:onMoveRight() return self:step("right") end

Panel.Widget = Widget

--- Open the panel for device `e` of House tab `tab`: kind "light",
--- "climate", "media" or "music" (what to play on a Music Assistant player).
function Panel.show(tab, e, kind)
    local w = Widget:new{ tab = tab, e = e, kind = kind }
    tab.panel = w
    UIManager:show(w)
    return w
end

return Panel
