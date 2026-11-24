--[[--
The House tab in the Bookshelf view (common/gz_view.lua; the other views
keep the list, gzreader_house.lua): Home Assistant's rooms as a wall with
their fittings mounted on it.

- a room's name on a strip of label tape, its devices in a row under it;
- a dimmable light: a rocker with a ladder of ten indicators beside it (8
  lit at 80%); a plain light, a switch, a fan, a helper: a toggle on a wall
  plate, its lever up when on and a pilot lamp above it;
- a thermostat: a round dial with the target in the middle and a pointer
  at it on the scale;
- temperature: a wall thermometer; humidity: a round gauge; a door or
  window sensor: a two-piece contact, apart when open (sensors show their
  value only);
- a lock: a deadbolt, its thumb-turn level when locked; a garage door or
  gate: a panelled door, rolled up when open; blinds: a window with its
  slats;
- a speaker: a speaker cabinet, sound coming from it while it plays; a TV:
  a television, its screen lit when on;
- scenes and scripts: keys on a keypad plate.

Under each fitting its name and what the list's row says (On · 80%,
20.5° → 21°, Locked). On a colour screen a lit lamp is in the bulb's
colour, the thermostat's scale is orange while it heats and blue while it
cools, and the thermometer is red; greys everywhere else.

With two rooms or more the wall starts in the hallway: what belongs to the
whole home (thermostats, locks, garage doors) under "Home", then a plate
for each room (how many of its lights are on, its temperature and
humidity, what plays there) and the scenes' keypad. A room's plate opens
that room: its fittings, with "All lights" first when it has several, and a
Home sign (or Back) to return. One room, or no rooms (a token that isn't an
administrator's): everything on the one wall, as before.

The page draws the tab's own rows (House:rootItems), so a tap, Press or a
letter does what the row did. Letters go to what does something (Refresh,
devices, scenes), in order; the 5-way moves over them. A page holds as much
as fits, so the pages are this view's own (the Menu's are a fixed number of
rows a page): the Menu's page, page count and letters are set here.

The fittings are drawings (SVG) made here for each state and kept in
cache/gzreader-house-wall; KOReader renders them at the size needed.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local View = {
    ART = "v1",          -- (part of a drawing's file name: change it when a drawing changes)
    VB_W = 228,          -- a drawing's own size (its viewBox)
    VB_H = 260,
    CELL = 120,          -- the narrowest a fitting's place may be (sets how many a row)
    KEYS = 4,            -- the most keys in a keypad's row
    INK = "#1a1a1a",
    SHADE = "#b5b5b5",
    RED = "#c8322b",     -- a thermometer's column on a colour screen
}

local function Shop() return require("gzreader_bookshop") end
local function HA() return require("gzreader_homeassistant") end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

---------------------------------------------------------------- when

--- What each row is on the wall: "refresh", "back" (the Home sign in a
--- room), "room" (a name on tape), "roomplate" (a room's plate in the
--- hallway), "fitting", "key" (a scene or script) or "note" (anything else:
--- a message, Why no rooms?).
function View.kinds(items, house)
    local out = {}
    for i, it in ipairs(items or {}) do
        local k = "note"
        if type(it) == "table" then
            if it.gz_house_refresh then k = "refresh"
            elseif it.gz_wall_back then k = "back"
            elseif it.gz_wall_plate then k = "roomplate"
            elseif it.gz_wall_all then k = "fitting"
            elseif it.gz_house_room or it.gz_wall_head then k = "room"
            elseif it.gz_house_id then
                local e = HA().find(house, it.gz_house_id)
                k = (e and (e.domain == "scene" or e.domain == "script")) and "key" or "fitting"
            end
        end
        out[i] = k
    end
    return out
end

--- The wall instead of the list: the Bookshelf view, and devices to show.
function View.applies(m, tab)
    if type(m) ~= "table" or type(m.item_table) ~= "table" or not (tab and tab.house) then return false end
    if not Shop().bookshelf() then return false end
    for _i, it in ipairs(m.item_table) do
        if type(it) == "table" and it.gz_house_id then return true end
    end
    return false
end

---------------------------------------------------------------- the hallway and the rooms

--- The list's rows by room: { refresh, groups = { { id, header, rows } },
--- notes (rows that belong to no room: messages, Why no rooms?) }.
function View.groups(items)
    local out = { groups = {}, notes = {} }
    local cur
    for _i, it in ipairs(items or {}) do
        if type(it) == "table" then
            if it.gz_house_refresh then out.refresh = it
            elseif it.gz_house_room then
                cur = { id = it.gz_house_room, header = it, rows = {} }
                out.groups[#out.groups + 1] = cur
            elseif it.gz_house_id and cur then cur.rows[#cur.rows + 1] = it
            else out.notes[#out.notes + 1] = it end
        end
    end
    return out
end

local function real(id) return type(id) == "string" and id:sub(1, 1) ~= "_" end

--- The hallway first (rooms behind their plates)? With two rooms or more;
--- not when the list is by kind (no rooms).
function View.hallway(items, house)
    if type(house) ~= "table" or house.by_kind then return false end
    local n = 0
    for _i, it in ipairs(items or {}) do
        if type(it) == "table" and real(it.gz_house_room) then n = n + 1 end
    end
    return n >= 2
end

--- What belongs to the whole home rather than a room (shown in the hallway
--- too): thermostats, locks, and what opens into the house.
function View.homeLevel(e)
    if type(e) ~= "table" then return false end
    if e.domain == "climate" or e.domain == "lock" then return true end
    return e.domain == "cover" and HA().GUARDED_COVERS[e.dc or ""] == true
end

--- A room at a glance, for its plate: { lights, on (of them), temp,
--- humidity (as its rows say them), playing (what plays there), count }.
function View.summary(rows, house)
    local Ha = HA()
    local sum = { lights = 0, on = 0, count = #rows }
    for _i, r in ipairs(rows) do
        local e = Ha.find(house, r.gz_house_id)
        if e then
            if e.domain == "light" then
                sum.lights = sum.lights + 1
                if e.state == "on" then sum.on = sum.on + 1 end
            elseif e.domain == "sensor" and e.dc == "temperature" and not sum.temp then sum.temp = Ha.stateText(e)
            elseif e.domain == "sensor" and e.dc == "humidity" and not sum.humidity then sum.humidity = Ha.stateText(e)
            elseif e.domain == "media_player" and e.state == "playing" and not sum.playing then sum.playing = e.title or r.text
            end
        end
    end
    return sum
end

--- A room's plate, in words: its lines under the name.
function View.plateLines(sum)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local lines = {}
    if sum.lights > 0 then
        lines[#lines + 1] = sum.on == 0 and _("Lights off") or T(_("%1 of %2 lights on"), sum.on, sum.lights)
    elseif sum.count > 0 then
        lines[#lines + 1] = T(_("%1 here"), sum.count)
    end
    if sum.temp or sum.humidity then
        lines[#lines + 1] = (sum.temp and sum.humidity) and (sum.temp .. " · " .. sum.humidity) or sum.temp or sum.humidity
    end
    if sum.playing then lines[#lines + 1] = T(_("Playing · %1"), sum.playing) end
    return lines
end

--- What the wall shows now, as rows like the list's: the hallway (`room`
--- nil), or one room. `act`: { open(room id), home(), all(room id, on) }.
--- The list's own rows are used as they are; the plates, the Home sign,
--- "Home" and "Rooms" on tape and All lights are rows made here.
function View.scene(items, house, room, act)
    local _ = require("gettext")
    local T = require("ffi/util").template
    local Ha = HA()
    local G = View.groups(items)
    local out = {}
    local function add(it) out[#out + 1] = it end
    local group
    for _i, g in ipairs(G.groups) do if g.id == room then group = g end end
    if group then
        add({ text = _("Home"), gz_wall_back = true, callback = act.home })
        if G.refresh then add(G.refresh) end
        add(group.header)
        local sum = View.summary(group.rows, house)
        if sum.lights >= 2 and real(group.id) then
            local on = sum.on > 0
            add({ text = _("All lights"), mandatory = on and T(_("%1 of %2 on"), sum.on, sum.lights) or _("Off"),
                gz_wall_all = { on = on, room = group.id }, callback = function() act.all(group.id, not on) end })
        end
        for _i, r in ipairs(group.rows) do add(r) end
    else
        if G.refresh then add(G.refresh) end
        local home = {}
        for _i, g in ipairs(G.groups) do
            for _j, r in ipairs(g.rows) do
                if View.homeLevel(Ha.find(house, r.gz_house_id)) then home[#home + 1] = r end
            end
        end
        if #home > 0 then
            add({ text = _("Home"), gz_wall_head = true, select_enabled = false })
            for _i, r in ipairs(home) do add(r) end
        end
        add({ text = _("Rooms"), gz_wall_head = true, select_enabled = false })
        local scenes
        for _i, g in ipairs(G.groups) do
            if g.id == "_scenes" then scenes = g
            else
                add({ text = g.header.text, gz_wall_plate = View.summary(g.rows, house), gz_wall_room = g.id,
                    callback = function() act.open(g.id) end })
            end
        end
        if scenes then
            add(scenes.header)
            for _i, r in ipairs(scenes.rows) do add(r) end
        end
    end
    for _i, n in ipairs(G.notes) do add(n) end
    return out
end

---------------------------------------------------------------- where things go

--- Where every row of the list goes, page by page, in a w x h wall (px; s =
--- the screen's scale function). `kinds`: View.kinds. Pure: tested in
--- run_tests.lua. { fits, cols, pages = { { first, last, places = { { i,
--- kind, x, y, w, h } } } } }; a "plate" place (no i) is a keypad's plate
--- behind the keys that follow it.
function View.layout(kinds, w, h, s)
    s = s or S
    local pad, gap, rgap = s(16), s(8), s(8)
    local cols = clamp(math.floor((w - 2 * pad + gap) / (s(View.CELL) + gap)), 2, 8)
    local cw = math.floor((w - 2 * pad - (cols - 1) * gap) / cols)
    local art_w = cw - s(10)
    local art_h = math.floor(art_w * View.VB_H / View.VB_W)
    local cap_h = s(46)
    local cell_h = s(4) + art_h + cap_h
    local band_h, tape_h, key_h, note_h = s(32), s(24), s(36), s(28)
    local tape_block = tape_h + s(6)
    local plate_h = key_h + s(22)
    local kcols = math.min(cols, View.KEYS)
    local screw = s(18)
    local kgap = s(10)
    local kw = math.floor((w - 2 * pad - 2 * screw - s(6) - (kcols - 1) * kgap) / kcols)
    -- rooms' plates in the hallway
    local pcols = clamp(math.floor((w - 2 * pad + gap) / (s(170) + gap)), 2, 5)
    local pw = math.floor((w - 2 * pad - (pcols - 1) * s(12)) / pcols) - s(2)
    local roomplate_h = s(92)
    local back_w = s(104)
    local band_y, band_x
    local base_h = s(12)
    local top, bottom = s(6), h - base_h - s(4)
    local L = { w = w, h = h, cols = cols, kcols = kcols, pcols = pcols, cell_w = cw, cell_h = cell_h, art_w = art_w, art_h = art_h,
        cap_h = cap_h, base = { x = 0, y = h - base_h, w = w, h = base_h }, pages = {}, fits = true }
    if top + tape_block + cell_h > bottom or cw < s(60) then
        L.fits = false
        return L
    end
    local page, y, col, rowtype, rowh
    local function newPage()
        page = { places = {} }
        L.pages[#L.pages + 1] = page
        y, col, rowtype, rowh = top, 0, nil, 0
    end
    local function endRow()
        if rowtype then y = y + rowh + rgap end
        rowtype, col, rowh = nil, 0, 0
        -- (a Home sign with no Refresh beside it)
        if band_y then y, band_y = band_y + band_h + rgap, nil end
    end
    local function need(hh)
        if y + hh > bottom and #page.places > 0 then newPage() end
    end
    local function put(i, kind, x, yy, ww, hh)
        local p = { i = i, kind = kind, x = x, y = yy, w = ww, h = hh }
        page.places[#page.places + 1] = p
        if i then
            page.first = page.first or i
            page.last = i
        end
        return p
    end
    newPage()
    for i, k in ipairs(kinds or {}) do
        if k == "back" then
            endRow()
            need(band_h)
            put(i, k, pad, y, back_w, band_h)
            band_y, band_x = y, pad + back_w + s(10)
        elseif k == "refresh" then
            if band_y then
                -- beside the Home sign
                put(i, k, band_x, band_y, w - pad - band_x, band_h)
                y, band_y = band_y + band_h + rgap, nil
            else
                endRow()
                need(band_h)
                put(i, k, pad, y, w - 2 * pad, band_h)
                y = y + band_h + rgap
            end
        elseif k == "roomplate" then
            if rowtype ~= "roomplate" or col >= pcols then
                endRow()
                need(roomplate_h + s(6))
                rowtype, rowh = "roomplate", roomplate_h + s(6)
            end
            put(i, k, pad + col * (pw + s(12)), y, pw, roomplate_h)
            col = col + 1
        elseif k == "room" then
            endRow()
            -- (never a room's name alone at the foot of a page)
            local nxt = kinds[i + 1]
            need(tape_block + (nxt == "fitting" and cell_h or nxt == "key" and plate_h or nxt == "roomplate" and roomplate_h + s(6) or 0))
            put(i, k, pad, y, w - 2 * pad, tape_h)
            y = y + tape_block
        elseif k == "fitting" then
            if rowtype ~= "fitting" or col >= cols then
                endRow()
                need(cell_h)
                rowtype, rowh = "fitting", cell_h
            end
            put(i, k, pad + col * (cw + gap), y, cw, cell_h)
            col = col + 1
        elseif k == "key" then
            if rowtype ~= "key" or col >= kcols then
                endRow()
                need(plate_h)
                rowtype, rowh = "key", plate_h
                put(nil, "plate", pad, y, w - 2 * pad - s(6), plate_h - s(6))
            end
            put(i, k, pad + screw + col * (kw + kgap), y + s(7), kw, key_h)
            col = col + 1
        else
            endRow()
            need(note_h)
            put(i, "note", pad, y, w - 2 * pad, note_h)
            y = y + note_h + s(4)
        end
    end
    -- (a page with nothing on it: none)
    for n = #L.pages, 1, -1 do
        if not L.pages[n].first then table.remove(L.pages, n) end
    end
    if #L.pages == 0 then L.fits = false end
    return L
end

--- The page (1…) that row `idx` of the list is on.
function View.pageOf(L, idx)
    for n, p in ipairs(L.pages or {}) do
        if idx >= p.first and idx <= p.last then return n end
    end
    return 1
end

---------------------------------------------------------------- the drawings

local function el(tag, attrs, body)
    return "<" .. tag .. " " .. attrs .. (body and (">" .. body .. "</" .. tag .. ">") or "/>")
end
local function f(fmt, ...) return string.format(fmt, ...) end

local function rect(x, y, w, h, rx, fill, stroke, sw, extra)
    return el("rect", f('x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"%s%s', x, y, w, h, rx or 0, fill or "none",
        stroke and f(' stroke="%s" stroke-width="%s"', stroke, sw or 3) or "", extra and (" " .. extra) or ""))
end
local function circle(cx, cy, r, fill, stroke, sw)
    return el("circle", f('cx="%s" cy="%s" r="%s" fill="%s"%s', cx, cy, r, fill or "none",
        stroke and f(' stroke="%s" stroke-width="%s"', stroke, sw or 3) or ""))
end
local function line(x1, y1, x2, y2, stroke, sw, round)
    return el("line", f('x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%s"%s', x1, y1, x2, y2, stroke, sw or 2,
        round and ' stroke-linecap="round"' or ""))
end
local function polygon(points, fill, stroke, sw)
    return el("polygon", f('points="%s" fill="%s"%s', points, fill,
        stroke and f(' stroke="%s" stroke-width="%s" stroke-linejoin="round"', stroke, sw or 3) or ""))
end

local function wrap(body)
    return f('<?xml version="1.0" encoding="utf-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="%dpx" height="%dpx" viewBox="0 0 %d %d">%s</svg>\n',
        View.VB_W, View.VB_H, View.VB_W, View.VB_H, body)
end

--- A darker shade of "#rrggbb" (a lamp's rays).
local function darker(hex, k)
    local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
    if not (r and g and b) then return View.INK end
    return f("#%02x%02x%02x", math.floor(r * k), math.floor(g * k), math.floor(b * k))
end

local function screw(x, y)
    return circle(x, y, 8, "#d6d6d6", View.INK, 2) .. line(x - 5, y + 3, x + 5, y - 3, View.INK, 2)
end

local function plate()
    return rect(22, 14, 200, 244, 16, View.SHADE)
        .. rect(12, 4, 200, 244, 16, "#f3f3f3", View.INK, 3)
        .. rect(19, 11, 186, 230, 10, "none", "#c9c9c9", 2)
        .. screw(112, 26) .. screw(112, 226)
end

local Draw = {}

--- A toggle on a wall plate. `lit`: the pilot lamp's colour when on.
function Draw.toggle(on, lit)
    local INK = View.INK
    local s = plate()
    if on then
        local ray = lit == INK and INK or darker(lit, 0.65)
        s = s .. line(96, 54, 90, 54, ray, 2.5, true) .. line(128, 54, 134, 54, ray, 2.5, true)
            .. line(100, 43, 96, 39, ray, 2.5, true) .. line(124, 43, 128, 39, ray, 2.5, true)
            .. circle(112, 54, 7, lit, INK, 2)
    else
        s = s .. circle(112, 54, 7, "#f3f3f3", INK, 2)
    end
    s = s .. rect(86, 76, 52, 104, 6, "#dedede", INK, 2.5) .. rect(97, 90, 30, 76, 3, INK)
    if on then
        s = s .. polygon("99,130 125,130 122,72 102,72", "#fbfbfb", INK, 3) .. line(103, 81, 121, 81, "#9a9a9a", 2)
    else
        s = s .. polygon("99,126 125,126 122,184 102,184", "#cfcfcf", INK, 3) .. line(103, 175, 121, 175, "#8a8a8a", 2)
    end
    return wrap(s)
end

--- A dimmer: a rocker, and ten indicators of which `level` are lit.
function Draw.dimmer(level, lit)
    local INK = View.INK
    local s = plate()
    for i = 0, 9 do
        s = s .. rect(52, 182 - i * 13, 18, 8, 2, i < level and lit or "#f3f3f3", INK, 2)
    end
    s = s .. rect(90, 62, 88, 130, 8, "#fbfbfb", INK, 3)
        .. rect(95, level > 0 and 67 or 130, 78, 57, 5, "#dcdcdc")
        .. line(90, 127, 178, 127, INK, 2)
        .. line(134, 86, 134, 106, INK, 3, true) .. circle(134, 160, 10, "none", INK, 3)
    return wrap(s)
end

--- A point on a dial: `a` degrees clockwise from straight up, r from (114, 126).
local function polar(a, r)
    local t = math.rad(a)
    return 114 + r * math.sin(t), 126 - r * math.cos(t)
end

--- A round thermostat. `at` (0–1): where the pointer is on its scale (the
--- target between its lowest and highest), nil for none; `arc`: the
--- scale's colour while it heats or cools (a colour screen), nil for none.
function Draw.thermostat(at, arc)
    local INK = View.INK
    local s = circle(122, 134, 98, View.SHADE) .. circle(114, 126, 98, "#ededed", INK, 3)
    if arc then
        local x1, y1 = polar(-135, 84)
        local x2, y2 = polar(135, 84)
        s = s .. el("path", f('d="M%.1f %.1f A84 84 0 1 1 %.1f %.1f" fill="none" stroke="%s" stroke-width="14"', x1, y1, x2, y2, arc))
    end
    for i = 0, 36 do
        local a = -135 + i * 7.5
        local x1, y1 = polar(a, 78)
        local x2, y2 = polar(a, i % 6 == 0 and 92 or 89)
        s = s .. line(x1, y1, x2, y2, INK, i % 6 == 0 and 3.5 or 2.5)
    end
    s = s .. circle(114, 126, 66, "#fcfcfc", INK, 3)
    if at then
        local a = -135 + clamp(at, 0, 1) * 270
        local tx, ty = polar(a, 70)
        local lx, ly = polar(a - 7, 97)
        local rx, ry = polar(a + 7, 97)
        s = s .. polygon(f("%.1f,%.1f %.1f,%.1f %.1f,%.1f", tx, ty, lx, ly, rx, ry), INK)
    end
    return wrap(s)
end

--- A wall thermometer, its column `level` (0–1) of the way up.
function Draw.thermometer(level, column)
    local INK = View.INK
    local top = 190 - math.floor(clamp(level, 0, 1) * 140)
    local s = rect(82, 18, 80, 236, 10, View.SHADE) .. rect(74, 10, 80, 236, 10, "#f3f3f3", INK, 3)
        .. circle(114, 24, 4, "#ffffff", INK, 2)
        .. rect(96, 40, 12, 160, 6, "#ffffff", INK, 2.5)
        .. rect(99, top, 6, 202 - top, 0, column)
        .. circle(102, 212, 15, column, INK, 2.5)
    for i = 0, 10 do
        s = s .. line(116, 54 + i * 13, i % 2 == 0 and 138 or 128, 54 + i * 13, INK, 2)
    end
    return wrap(s)
end

--- A round gauge (humidity), its needle `level` (0–1) along the scale.
function Draw.gauge(level)
    local INK = View.INK
    local s = circle(122, 134, 86, View.SHADE) .. circle(114, 126, 86, "#f3f3f3", INK, 3) .. circle(114, 126, 74, "#fcfcfc", "#7a7a7a", 2)
    for i = 0, 10 do
        local a = -120 + i * 24
        local x1, y1 = polar(a, i % 5 == 0 and 56 or 61)
        local x2, y2 = polar(a, 69)
        s = s .. line(x1, y1, x2, y2, INK, i % 5 == 0 and 3.5 or 2.5)
    end
    local nx, ny = polar(-120 + clamp(level, 0, 1) * 240, 52)
    s = s .. line(114, 126, nx, ny, INK, 4, true) .. circle(114, 126, 8, "#d0d0d0", INK, 2)
        -- a drop under the hub
        .. el("path", f('d="M114 150 C106 162 104 168 114 174 C124 168 122 162 114 150 Z" fill="none" stroke="%s" stroke-width="2.5" stroke-linejoin="round"', INK))
    return wrap(s)
end

--- A deadbolt: its thumb-turn level when locked, upright when unlocked,
--- slanted otherwise (jammed, on its way).
function Draw.deadbolt(how)
    local INK = View.INK
    local turn = how == "locked" and 0 or how == "unlocked" and 90 or 45
    local s = circle(122, 134, 86, View.SHADE) .. circle(114, 126, 86, "#e9e9e9", INK, 3) .. circle(114, 126, 64, "#f8f8f8", "#7a7a7a", 2)
        .. circle(39, 126, 5, "#d6d6d6", INK, 2) .. circle(189, 126, 5, "#d6d6d6", INK, 2)
        .. rect(66, 118, 104, 32, 16, "#a9a9a9", nil, nil, f('transform="rotate(%d 118 134)"', turn))
        .. rect(62, 110, 104, 32, 16, "#fcfcfc", INK, 3, f('transform="rotate(%d 114 126)"', turn))
        .. circle(114, 126, 9, "#d0d0d0", INK, 2)
    return wrap(s)
end

--- A garage door with `panels` (0–4) of its four panels down.
function Draw.garage(panels)
    local INK = View.INK
    local s = rect(14, 28, 200, 204, 0, "#d9d9d9", INK, 3) .. rect(28, 44, 172, 188, 0, "#3a3a3a", INK, 3)
    if panels > 0 then
        local dh = panels * 47
        s = s .. rect(28, 44, 172, dh, 0, "#f6f6f6", INK, 3) .. rect(30, 46, 168, 7, 0, "#9a9a9a")
        for r = 0, panels - 1 do
            local y0 = 44 + r * 47
            if r > 0 then s = s .. line(28, y0, 200, y0, INK, 2.5) end
            for c = 0, 3 do s = s .. rect(37 + c * 41, y0 + 12, 31, 25, 0, "#e4e4e4", "#6a6a6a", 2) end
        end
        s = s .. rect(103, 44 + dh - 10, 22, 6, 2, INK)
    end
    s = s .. line(0, 234, 228, 234, INK, 4)
    return wrap(s)
end

--- A window with blinds: `slats` (0–9) of them down.
function Draw.blinds(slats)
    local INK = View.INK
    local s = rect(34, 30, 176, 208, 0, View.SHADE) .. rect(26, 22, 176, 208, 0, "#f3f3f3", INK, 3)
        .. rect(40, 36, 148, 180, 0, "#ffffff", INK, 2.5)
        .. line(114, 36, 114, 216, INK, 2.5) .. line(40, 126, 188, 126, INK, 2.5)
        .. rect(36, 30, 156, 12, 2, "#d0d0d0", INK, 2.5)
    for i = 0, slats - 1 do
        s = s .. rect(40, 44 + i * 19, 148, 15, 2, "#e4e4e4", INK, 2)
    end
    -- its cord
    s = s .. line(180, 42, 180, 44 + math.max(slats, 2) * 19 + 8, "#7a7a7a", 2) .. circle(180, 44 + math.max(slats, 2) * 19 + 12, 4, "#d0d0d0", INK, 2)
    return wrap(s)
end

--- A door or window contact: its two pieces together, or apart when open.
function Draw.contact(open)
    local INK = View.INK
    local dx = open and 34 or 0
    local s = line(127, 16, 127, 244, "#7a7a7a", 2)
        .. rect(76, 58, 52, 150, 8, View.SHADE) .. rect(68, 50, 52, 150, 8, "#f3f3f3", INK, 3)
        .. circle(94, 72, 4, open and INK or "#ffffff", INK, 2)
        .. rect(142 + dx, 78, 30, 110, 6, View.SHADE) .. rect(134 + dx, 70, 30, 110, 6, "#f3f3f3", INK, 3)
    return wrap(s)
end

--- A speaker: `how` "playing" (sound coming from it), "on" (its lamp lit)
--- or "off".
function Draw.speaker(how)
    local INK = View.INK
    local on = how ~= "off"
    local cone = on and "#c4c4c4" or "#e2e2e2"
    local s = rect(62, 28, 120, 220, 10, View.SHADE) .. rect(54, 20, 120, 220, 10, "#f3f3f3", INK, 3)
        .. circle(114, 72, 20, cone, INK, 2.5) .. circle(114, 72, 7, on and INK or "#9a9a9a")
        .. circle(114, 158, 44, cone, INK, 3) .. circle(114, 158, 28, on and "#8a8a8a" or "#cfcfcf", INK, 2) .. circle(114, 158, 9, on and INK or "#9a9a9a")
        .. circle(114, 222, 5, on and INK or "#f3f3f3", INK, 2)
    if how == "playing" then
        for _i, a in ipairs({ { 12, 22 }, { 22, 36 } }) do
            -- arcs either side of the cabinet
            s = s .. el("path", f('d="M%d %d A%d %d 0 0 1 %d %d" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"',
                    178 + a[1], 130 - a[2], a[2] + 14, a[2] + 14, 178 + a[1], 130 + a[2], INK))
                .. el("path", f('d="M%d %d A%d %d 0 0 0 %d %d" fill="none" stroke="%s" stroke-width="4" stroke-linecap="round"',
                    50 - a[1], 130 - a[2], a[2] + 14, a[2] + 14, 50 - a[1], 130 + a[2], INK))
        end
    end
    return wrap(s)
end

--- A television: its screen dark when off, lit when on, a play mark while it plays.
function Draw.tv(how)
    local INK = View.INK
    local s = rect(26, 52, 192, 132, 8, View.SHADE) .. rect(18, 44, 192, 132, 8, "#f3f3f3", INK, 3)
        .. rect(28, 54, 172, 112, 4, how == "off" and "#3a3a3a" or "#ffffff", INK, 2.5)
        .. line(114, 176, 114, 204, INK, 6) .. rect(70, 204, 88, 10, 3, "#d0d0d0", INK, 2.5)
    if how == "playing" then
        s = s .. polygon("100,88 100,132 136,110", INK)
    elseif how == "on" then
        s = s .. line(44, 150, 184, 150, "#9a9a9a", 3, true) .. circle(52, 150, 5, INK)
    end
    return wrap(s)
end

--- A room plate's lever (its own size: 80 x 140), up when a light is on there.
function Draw.lever(on)
    local INK = View.INK
    local s = rect(4, 4, 72, 132, 10, "#dedede", INK, 3) .. rect(24, 24, 32, 92, 4, INK)
        .. (on and polygon("27,74 53,74 49,12 31,12", "#fbfbfb", INK, 3) or polygon("27,66 53,66 49,128 31,128", "#cfcfcf", INK, 3))
    return '<?xml version="1.0" encoding="utf-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="80px" height="140px" viewBox="0 0 80 140">' .. s .. "</svg>\n"
end

View.Draw = Draw

--- Which drawing a device gets: { key (its file's name: one per look),
--- svg (a function making it), text (to write on it: a thermostat's
--- target) }. `colour`: a colour screen. Pure: tested in run_tests.lua.
function View.fitting(e, colour)
    local Ha = HA()
    local INK = View.INK
    e = e or {}
    local d, st = e.domain, e.state
    local function hexkey(hex) return hex:sub(2):lower() end
    if d == "light" or d == "switch" or d == "fan" or d == "input_boolean" then
        local on = st == "on"
        -- (a lamp's colour means the bulb's: lights only)
        local lit = (colour and d == "light" and on and (e.rgb or Ha.WARM)) or INK
        if d == "light" and e.dim then
            local level = on and clamp(math.ceil((e.bri or 100) / 10), 1, 10) or 0
            return { key = "dimmer-" .. level .. "-" .. hexkey(lit), svg = function() return Draw.dimmer(level, lit) end }
        end
        return { key = "toggle-" .. (on and "on" or "off") .. "-" .. hexkey(lit), svg = function() return Draw.toggle(on, lit) end }
    end
    if d == "climate" then
        local lo, hi = e.min or 7, e.max or 35
        local at = (e.target and hi > lo) and clamp((e.target - lo) / (hi - lo), 0, 1) or nil
        at = at and math.floor(at * 36 + 0.5) / 36 -- (one look a tick)
        local arc = colour and Ha.iconColor(e) or nil
        local text = st == "off" and "–" or (e.target and (Ha.fmt(e.target) .. "°")) or (e.cur and (Ha.fmt(e.cur) .. "°")) or nil
        return { key = "thermostat-" .. (at and math.floor(at * 36 + 0.5) or "x") .. "-" .. (arc and hexkey(arc) or "none"),
            svg = function() return Draw.thermostat(at, arc) end, text = text }
    end
    if d == "media_player" then
        local how = (st == "playing" or st == "buffering") and "playing" or ((st == "off" or st == "standby" or st == "unavailable" or st == "unknown") and "off" or "on")
        if e.dc == "tv" or e.dc == "receiver" then return { key = "tv-" .. how, svg = function() return Draw.tv(how) end } end
        return { key = "speaker-" .. how, svg = function() return Draw.speaker(how) end }
    end
    if d == "lock" or (d == "binary_sensor" and e.dc == "lock") then
        local how
        if d == "lock" then how = (st == "locked" or st == "unlocked") and st or "other"
        else how = st == "on" and "unlocked" or "locked" end
        return { key = "deadbolt-" .. how, svg = function() return Draw.deadbolt(how) end }
    end
    if d == "cover" then
        local open = st == "open" or st == "opening"
        local frac = (open and e.pos and e.pos > 0 and e.pos < 100) and (e.pos / 100) or (open and 1 or 0)
        if Ha.GUARDED_COVERS[e.dc or ""] then
            local panels = clamp(math.floor((1 - frac) * 4 + 0.5), 0, 4)
            if open then panels = math.min(panels, 3) end
            return { key = "garage-" .. panels, svg = function() return Draw.garage(panels) end }
        end
        local slats = clamp(math.floor((1 - frac) * 9 + 0.5), 1, 9)
        if open then slats = math.min(slats, 8) end
        return { key = "blinds-" .. slats, svg = function() return Draw.blinds(slats) end }
    end
    if d == "binary_sensor" then
        local open = st == "on"
        return { key = "contact-" .. (open and "open" or "closed"), svg = function() return Draw.contact(open) end }
    end
    if d == "sensor" then
        local v = tonumber(st)
        if e.dc == "humidity" then
            local level = v and clamp(math.floor(v / 5 + 0.5), 0, 20) or 0
            return { key = "gauge-" .. level, svg = function() return Draw.gauge(level / 20) end }
        end
        -- −10 … 40 °C (14 … 104 °F) up the column, in twenty steps
        local c = v and ((e.unit == "°F") and ((v - 32) / 1.8) or v) or nil
        local level = c and clamp(math.floor((c + 10) / 50 * 20 + 0.5), 0, 20) or 0
        local column = colour and View.RED or INK
        return { key = "thermometer-" .. level .. "-" .. hexkey(column), svg = function() return Draw.thermometer(level / 20, column) end }
    end
    return { key = "toggle-off-" .. hexkey(INK), svg = function() return Draw.toggle(false, INK) end }
end

--- The drawing's file in the cache (made once for each look), or nil.
function View.artFile(fit)
    local dir = require("datastorage"):getDataDir() .. "/cache/gzreader-house-wall"
    local path = dir .. "/" .. View.ART .. "-" .. fit.key:gsub("[^%w%-]", "_") .. ".svg"
    local have = io.open(path, "rb")
    if have then have:close(); return path end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local out = io.open(path, "wb")
    if not out then return nil end
    out:write(fit.svg())
    out:close()
    return path
end

-- the drawings rendered for the page on the screen (one size at a time)
local rendered = {}

function View.free()
    for k, bb in pairs(rendered) do
        pcall(bb.free, bb)
        rendered[k] = nil
    end
end

local function art(fit, w, h)
    local key = fit.key .. "@" .. w .. "x" .. h
    if rendered[key] ~= nil then return rendered[key] or nil end
    local ok, bb = pcall(function()
        local file = View.artFile(fit)
        return file and require("ui/renderimage"):renderSVGImageFile(file, w, h) or nil
    end)
    rendered[key] = ok and bb or false
    return rendered[key] or nil
end

--- A drawing rendered w x h (kept until the tab closes), or nil.
View.artImage = art

---------------------------------------------------------------- the page

local Page = WidgetContainer:extend{ w = 0, h = 0 }
function Page:getSize() return Geom:new{ w = self.w, h = self.h } end

--- A font size for `px` pixels.
local function fs(px) return math.max(7, math.floor(px / S(1) + 0.5)) end

--- `str` in the biggest of `sizes` it fits `max_w` in (the last one cut short).
local function fitText(bb, str, sizes, cx, y, max_w, bold, color)
    local TextWidget = require("ui/widget/textwidget")
    local tw
    for k, size in ipairs(sizes) do
        if tw then tw:free() end
        tw = TextWidget:new{ text = str, face = Font:getFace("cfont", size), bold = bold, fgcolor = color,
            max_width = k == #sizes and max_w or nil }
        if tw:getSize().w <= max_w then break end
    end
    local sz = tw:getSize()
    tw:paintTo(bb, cx - math.floor(sz.w / 2), y)
    tw:free()
    return sz
end

function Page:paintRefresh(bb, x, y, pl)
    local D = Shop().draw
    local r = D.sign(bb, self.menu, { x = x + pl.x, y = y + pl.y + S(3), h = pl.h - S(6) }, pl.entry.text or "", nil, pl.letter)
    pl.hot.dimen = Geom:new(r)
    if pl.hot.focused then D.focusRing(bb, r) end
    if pl.entry.mandatory and pl.entry.mandatory ~= "" then
        local TextWidget = require("ui/widget/textwidget")
        local t = TextWidget:new{ text = pl.entry.mandatory, face = Font:getFace("cfont", 13), fgcolor = D.gray(0.8) }
        local sz = t:getSize()
        local tx, ty = x + pl.x + pl.w - sz.w, y + pl.y + math.floor((pl.h - sz.h) / 2)
        bb:paintRect(tx - S(6), ty, sz.w + S(6), sz.h, Blitbuffer.COLOR_WHITE)
        t:paintTo(bb, tx, ty)
        t:free()
    end
end

--- The Home sign in a room.
function Page:paintBack(bb, x, y, pl)
    local D = Shop().draw
    local r = D.sign(bb, self.menu, { x = x + pl.x, y = y + pl.y + S(3), h = pl.h - S(6) }, "‹ " .. (pl.entry.text or ""), nil, pl.letter)
    pl.hot.dimen = Geom:new(r)
    if pl.hot.focused then D.focusRing(bb, r) end
end

--- A room's plate in the hallway: a lever (up when a light is on there),
--- its name, and the room at a glance.
function Page:paintRoomPlate(bb, x, y, pl)
    local D = Shop().draw
    local px, py = x + pl.x, y + pl.y
    local r, bw = S(8), math.max(2, S(2))
    bb:paintRoundedRect(px + S(5), py + S(5), pl.w, pl.h, D.gray(0.3), r)
    bb:paintRoundedRect(px, py, pl.w, pl.h, D.gray(0.06), r)
    bb:paintBorder(px, py, pl.w, pl.h, bw, Blitbuffer.COLOR_BLACK, r)
    local sum = pl.entry.gz_wall_plate
    local lh = pl.h - S(20)
    local lw = math.floor(lh * 80 / 140)
    local on = sum.on > 0
    local img = art({ key = "lever-" .. (on and "on" or "off"), svg = function() return Draw.lever(on) end }, lw, lh)
    local lx = px + S(10)
    if img then bb:alphablitFrom(img, lx, py + S(10), 0, 0, img:getWidth(), img:getHeight()) end
    local tx = lx + lw + S(10)
    local room = px + pl.w - S(8) - tx
    local TextWidget = require("ui/widget/textwidget")
    local name = TextWidget:new{ text = tostring(pl.entry.text or ""):upper(), face = Font:getFace("cfont", 13), bold = true, max_width = room }
    local ty = py + S(8)
    name:paintTo(bb, tx, ty)
    ty = ty + name:getSize().h
    name:free()
    for _i, words in ipairs(View.plateLines(sum)) do
        local t = TextWidget:new{ text = words, face = Font:getFace("cfont", 12), max_width = room, fgcolor = D.gray(0.85) }
        if ty + t:getSize().h <= py + pl.h - S(4) then t:paintTo(bb, tx, ty) end
        ty = ty + t:getSize().h
        t:free()
    end
    if pl.letter then D.badge(bb, self.menu, pl.letter, px - S(4), py - S(4), S(20)) end
    pl.hot.dimen = Geom:new{ x = px, y = py, w = pl.w, h = pl.h }
    if pl.hot.focused then D.focusRing(bb, pl.hot.dimen) end
end

--- A room's name on a strip of label tape.
function Page:paintTape(bb, x, y, pl)
    local D = Shop().draw
    local TextWidget = require("ui/widget/textwidget")
    local label = tostring(pl.entry.text or ""):upper()
    local t = TextWidget:new{ text = label, face = Font:getFace("cfont", 12), bold = true, fgcolor = Blitbuffer.COLOR_WHITE,
        max_width = pl.w - S(28) }
    local sz = t:getSize()
    local tw, tx, ty = sz.w + S(24), x + pl.x, y + pl.y
    bb:paintRect(tx + S(3), ty + S(3), tw, pl.h, D.gray(0.3))
    bb:paintRect(tx, ty, tw, pl.h, Blitbuffer.COLOR_BLACK)
    bb:paintRect(tx, ty + S(2), tw, math.max(1, S(1)), D.gray(0.6))
    bb:paintRect(tx, ty + pl.h - S(3), tw, math.max(1, S(1)), D.gray(0.6))
    t:paintTo(bb, tx + S(13), ty + math.floor((pl.h - sz.h) / 2))
    t:free()
end

function Page:paintFitting(bb, x, y, pl)
    local D = Shop().draw
    local L = self.L
    local cx = x + pl.x + math.floor(pl.w / 2)
    local ax, ay = cx - math.floor(L.art_w / 2), y + pl.y + S(2)
    local fit = View.fitting(pl.device, self.colour)
    local img = art(fit, L.art_w, L.art_h)
    if img then
        bb:alphablitFrom(img, ax + math.floor((L.art_w - img:getWidth()) / 2), ay, 0, 0, img:getWidth(), img:getHeight())
    else
        bb:paintBorder(ax, ay, L.art_w, L.art_h, math.max(1, S(1)), D.gray(0.6))
    end
    if fit.text then
        -- (a thermostat's target, in the middle of its dial: 114, 126 of the drawing)
        local k = L.art_w / View.VB_W
        D.text(bb, fit.text, Font:getFace("cfont", fs(46 * k)), ax + math.floor(114 * k), ay + math.floor(126 * k),
            { center = true, middle = true, bold = true })
    end
    if pl.letter then D.badge(bb, self.menu, pl.letter, x + pl.x, y + pl.y, S(20)) end
    local ty = ay + L.art_h + S(2)
    local name = fitText(bb, pl.entry.text or "", { 14, 13, 12 }, cx, ty, pl.w - S(2), true)
    local state = pl.entry.mandatory
    if state and state ~= "" then
        if pl.opens then state = state .. " ›" end
        fitText(bb, state, { 13, 12 }, cx, ty + name.h, pl.w - S(2), false, D.gray(0.85))
    end
    if pl.hot then
        pl.hot.dimen = Geom:new{ x = x + pl.x, y = y + pl.y, w = pl.w, h = pl.h }
        if pl.hot.focused then D.focusRing(bb, { x = x + pl.x + S(4), y = y + pl.y + S(4), w = pl.w - S(8), h = pl.h - S(8) }) end
    end
end

--- A keypad's plate (the keys that follow stand on it).
function Page:paintPlate(bb, x, y, pl)
    local D = Shop().draw
    local px, py = x + pl.x, y + pl.y
    local r, bw = S(8), math.max(2, S(2))
    bb:paintRoundedRect(px + S(5), py + S(5), pl.w, pl.h, D.gray(0.3), r)
    bb:paintRoundedRect(px, py, pl.w, pl.h, D.gray(0.06), r)
    bb:paintBorder(px, py, pl.w, pl.h, bw, Blitbuffer.COLOR_BLACK, r)
    local sr = math.max(3, S(4))
    for _i, sx in ipairs({ px + S(9), px + pl.w - S(9) }) do
        bb:paintCircle(sx, py + math.floor(pl.h / 2), sr, D.gray(0.2))
        bb:paintCircle(sx, py + math.floor(pl.h / 2), sr, Blitbuffer.COLOR_BLACK, math.max(1, S(1)))
    end
end

function Page:paintKey(bb, x, y, pl)
    local D = Shop().draw
    local kx, ky = x + pl.x, y + pl.y
    local r, bw = S(5), math.max(2, S(2))
    bb:paintRoundedRect(kx, ky + S(4), pl.w, pl.h, D.gray(0.55), r)
    bb:paintRoundedRect(kx, ky, pl.w, pl.h, Blitbuffer.COLOR_WHITE, r)
    bb:paintBorder(kx, ky, pl.w, pl.h, bw, Blitbuffer.COLOR_BLACK, r)
    local side = pl.letter and self.menu.is_enable_shortcut and S(20) or 0
    if side > 0 then D.badge(bb, self.menu, pl.letter, kx + S(6), ky + math.floor((pl.h - side) / 2), side) end
    local room = pl.w - S(12) - (side > 0 and side + S(6) or 0)
    local cx = kx + pl.w - S(6) - math.floor(room / 2)
    local TextWidget = require("ui/widget/textwidget")
    local probe = TextWidget:new{ text = "Ag", face = Font:getFace("cfont", 14), bold = true }
    local th = probe:getSize().h
    probe:free()
    -- (one that can't be run now, e.g. unavailable: its name in grey, nothing to press)
    fitText(bb, pl.entry.text or "", { 14, 13, 12 }, cx, ky + math.floor((pl.h - th) / 2), room, true, not pl.hot and D.gray(0.5) or nil)
    if pl.hot then
        pl.hot.dimen = Geom:new{ x = kx, y = ky, w = pl.w, h = pl.h + S(4) }
        if pl.hot.focused then D.focusRing(bb, { x = kx, y = ky, w = pl.w, h = pl.h }) end
    end
end

function Page:paintNote(bb, x, y, pl)
    local D = Shop().draw
    local nx, ny = x + pl.x, y + pl.y
    local side = pl.letter and self.menu.is_enable_shortcut and S(20) or 0
    bb:paintRect(nx, ny, pl.w, pl.h, Blitbuffer.COLOR_WHITE)
    if side > 0 then D.badge(bb, self.menu, pl.letter, nx, ny + math.floor((pl.h - side) / 2), side) end
    D.text(bb, pl.entry.text or "", Font:getFace("cfont", 13), nx + (side > 0 and side + S(8) or 0), ny + math.floor(pl.h / 2),
        { middle = true, color = pl.hot and Blitbuffer.COLOR_BLACK or D.gray(0.7), max_width = pl.w - side - S(8) })
    if pl.hot then
        pl.hot.dimen = Geom:new{ x = nx, y = ny, w = pl.w, h = pl.h }
        if pl.hot.focused then D.focusRing(bb, pl.hot.dimen) end
    end
end

function Page:paintTo(bb, x, y)
    local D = Shop().draw
    self.dimen = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    D.wall(bb, x, y, self.w, self.h)
    -- the skirting board along the foot of the wall
    local b = self.L.base
    bb:paintRect(x + b.x, y + b.y, b.w, b.h, D.gray(0.17))
    bb:paintRect(x + b.x, y + b.y, b.w, math.max(1, S(2)), Blitbuffer.COLOR_BLACK)
    bb:paintRect(x + b.x, y + b.y + math.max(1, S(2)), b.w, math.max(1, S(2)), D.gray(0.05))
    bb:paintRect(x + b.x, y + b.y + b.h - S(4), b.w, S(4), D.gray(0.35))
    for _i, pl in ipairs(self.places) do
        if pl.kind == "refresh" then self:paintRefresh(bb, x, y, pl)
        elseif pl.kind == "back" then self:paintBack(bb, x, y, pl)
        elseif pl.kind == "roomplate" then self:paintRoomPlate(bb, x, y, pl)
        elseif pl.kind == "room" then self:paintTape(bb, x, y, pl)
        elseif pl.kind == "fitting" then self:paintFitting(bb, x, y, pl)
        elseif pl.kind == "plate" then self:paintPlate(bb, x, y, pl)
        elseif pl.kind == "key" then self:paintKey(bb, x, y, pl)
        else self:paintNote(bb, x, y, pl) end
    end
end

View.Page = Page

---------------------------------------------------------------- building a page

--- What's on page `n`: each place with its row of the list (entry), its
--- device, its letter (the ones that do something, in order) and whether
--- it opens a window (a dimmer, a thermostat, a speaker).
function View.fill(L, n, items, house, shortcuts)
    local Ha = HA()
    local out = {}
    local k = 0
    for _i, pl in ipairs(L.pages[n] and L.pages[n].places or {}) do
        local p = { kind = pl.kind, x = pl.x, y = pl.y, w = pl.w, h = pl.h, i = pl.i }
        local e = pl.i and items[pl.i]
        if e then
            p.entry = e
            p.device = e.gz_house_id and Ha.find(house, e.gz_house_id) or nil
            -- (All lights: a switch that is on when any of the room's lights is)
            if e.gz_wall_all then p.device = { domain = "switch", state = e.gz_wall_all.on and "on" or "off" } end
            p.acts = type(e.callback) == "function" and e.select_enabled ~= false
            if p.acts then
                k = k + 1
                p.letter = shortcuts and shortcuts[k] or nil
            end
            local what = p.device and Ha.action(p.device)
            p.opens = what == "light" or what == "climate" or what == "media"
        end
        out[#out + 1] = p
    end
    return out
end

--- Going between the hallway and a room, and a room's All lights.
function View.acts(m, tab)
    return {
        open = function(id)
            tab.wall_home_page, tab.wall_room, m.page = m.page, id, 1
            m:updateItems()
        end,
        home = function()
            -- (back in the hallway: the page it was on, the focus on that room's plate)
            m._gz_wall_last = { gz_wall_room = tab.wall_room }
            tab.wall_room, m.page = nil, tab.wall_home_page or 1
            m:updateItems()
        end,
        all = function(id, on) tab:allLights(id, on) end,
    }
end

--- Draw the page of `m` (the House tab's list) as the wall. False: it
--- doesn't fit (the list instead).
function View.build(m, tab, select_number, no_recalculate_dimen)
    local old_dimen = m.dimen and m.dimen:copy()
    local wanted = m.page or 1
    m:_recalculateDimen(no_recalculate_dimen)
    local W, H = m.item_dimen.w, m.available_height
    -- the hallway and its rooms (two rooms or more), or everything on the one wall
    local shown = m.item_table
    if View.hallway(shown, tab.house) then
        shown = View.scene(shown, tab.house, tab.wall_room, View.acts(m, tab))
        -- (a room that's gone, e.g. hidden in Settings: the hallway)
        if tab.wall_room and not (shown[1] and shown[1].gz_wall_back) then tab.wall_room = nil end
    else
        tab.wall_room = nil
    end
    local L = View.layout(View.kinds(shown, tab.house), W, H)
    if not L.fits then return false end
    -- the pages are this view's (what fits on each), not the Menu's rows
    m.page_num = #L.pages
    m.page = clamp(wanted, 1, m.page_num)
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    local Hot = Shop().Hot
    local page = Page:new{ w = W, h = H, L = L, menu = m, colour = require("gzreader_colour").enabled() }
    page.places = View.fill(L, m.page, shown, tab.house, m.is_enable_shortcut and m.item_shortcuts or nil)
    local frows, row_y = {}, nil
    page.by_letter = {}
    for _i, pl in ipairs(page.places) do
        if pl.acts then
            pl.entry.idx = pl.i
            pl.hot = Hot:new{ menu = m, entry = pl.entry, shop = page }
            page[#page + 1] = pl.hot
            if pl.y ~= row_y then
                frows[#frows + 1] = {}
                row_y = pl.y
            end
            table.insert(frows[#frows], pl.hot)
            if pl.letter then page.by_letter[pl.letter] = pl.entry end
        end
    end
    for _i, r in ipairs(frows) do m.layout[#m.layout + 1] = r end
    table.insert(m.item_group, page)
    m._gz_wall = page
    -- the focus: on what was chosen (back from it), else the first thing
    local fx, fy = 1, 1
    local back = m._gz_wall_last
    if back then
        for yy, r in ipairs(m.layout) do
            for xx, h in ipairs(r) do
                if h.entry == back or (h.entry.gz_house_id and h.entry.gz_house_id == back.gz_house_id)
                    or (h.entry.gz_wall_room and h.entry.gz_wall_room == back.gz_wall_room)
                    or (h.entry.gz_wall_all and back.gz_wall_all) then fx, fy = xx, yy end
            end
        end
    end
    m:updatePageInfo(select_number or 1)
    if (fx > 1 or fy > 1) and m.layout[fy] then
        -- (the focus is a nicety: the page is drawn whether or not it can be placed)
        pcall(function()
            if Device:hasDPad() then m:moveFocusTo(fx, fy, require("ui/widget/focusmanager").FOCUS_ONLY_ON_NT) end
        end)
    end
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
    return true
end

--- Take over the House tab's list in the Bookshelf view.
function View.apply(tab)
    local m = tab and tab.menu
    if not m or m._gz_wall_applied or type(m.updateItems) ~= "function" then return end
    m._gz_wall_applied = true
    local orig_update = m.updateItems
    m.updateItems = function(menu, select_number, no_recalculate_dimen)
        if not menu._gz_wall_failed and View.applies(menu, tab) then
            local ok, res = pcall(View.build, menu, tab, select_number, no_recalculate_dimen)
            if ok and res ~= false then return end
            if not ok then
                require("gzreader_log").warn("house wall:", tostring(res))
                menu._gz_wall_failed = true
            end
        end
        menu._gz_wall = nil
        return orig_update(menu, select_number, no_recalculate_dimen)
    end
    -- a letter: what has it on the wall (the Menu counts rows a page)
    local orig_key = m.onSelectByShortCut
    m.onSelectByShortCut = function(menu, arg, keyevent)
        local page = menu._gz_wall
        if not page then return orig_key and orig_key(menu, arg, keyevent) end
        local entry = keyevent and page.by_letter[keyevent.key]
        if entry then menu:onMenuSelect(entry) end
        return true
    end
    -- what's chosen: the focus stays on it when the wall is drawn again
    local orig_select = m.onMenuSelect
    m.onMenuSelect = function(menu, item, ...)
        if menu._gz_wall then menu._gz_wall_last = item end
        return orig_select(menu, item, ...)
    end
    -- Back in a room: the hallway (not out of the tab)
    local orig_back = m.onClose
    m.onClose = function(menu, ...)
        if menu._gz_wall and tab.wall_room then
            View.acts(menu, tab).home()
            return true
        end
        if orig_back then return orig_back(menu, ...) end
    end
    local orig_close = m.onCloseWidget
    m.onCloseWidget = function(menu, ...)
        View.free()
        if orig_close then return orig_close(menu, ...) end
    end
    if View.applies(m, tab) then pcall(m.updateItems, m) end
end

return View
