--[[--
A journal mood's face, as the owner's Memos fork draws it (web
components/Journal/MoodFace.tsx): a glossy round face for each of the seven
steps from very unpleasant to very pleasant, its mouth bending further at
each step. On a colour screen it has the web's colours; elsewhere they
become greys of the same lightness (the web makes neighbouring steps differ
in lightness too, so they read without colour), drawn pixel by pixel.

    MoodFace.paint(bb, x, y, size, valence, faded)
    MoodFace.widget{ valence = "pleasant", size = 40, faded = false }
]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local MoodFace = {}

MoodFace.VALENCES = { "very-unpleasant", "unpleasant", "slightly-unpleasant", "neutral", "slightly-pleasant", "pleasant", "very-pleasant" }

-- the web's colours for each step (MoodFace.tsx's FACES): fill, highlight, edge, ink
MoodFace.COLORS = {
    ["very-unpleasant"] = { "#363a8a", "#8a90dc", "#20235a", "#ffffff" },
    unpleasant = { "#5468c0", "#bcc6f4", "#303d88", "#ffffff" },
    ["slightly-unpleasant"] = { "#9cb0de", "#e4ebfa", "#58699c", "#1a2440" },
    neutral = { "#cfc4a8", "#fbf6e6", "#8a7a58", "#2b2418" },
    ["slightly-pleasant"] = { "#f4d27e", "#fff5d6", "#a8821e", "#3d2a00" },
    pleasant = { "#f2a44a", "#ffe0b0", "#a85e18", "#3d2000" },
    ["very-pleasant"] = { "#d9621c", "#ffc48c", "#7a3006", "#2a1000" },
}

--- A colour's lightness as a grey level (0 black … 255 white).
function MoodFace.grey(hex)
    local r, g, b = tostring(hex):match("^#(%x%x)(%x%x)(%x%x)$")
    if not r then return 0 end
    return math.floor(0.299 * tonumber(r, 16) + 0.587 * tonumber(g, 16) + 0.114 * tonumber(b, 16) + 0.5)
end

--- A step's greys: { fill, light, edge, ink } (0–255).
function MoodFace.greys(valence)
    local c = MoodFace.COLORS[valence] or MoodFace.COLORS.neutral
    return { fill = MoodFace.grey(c[1]), light = MoodFace.grey(c[2]), edge = MoodFace.grey(c[3]), ink = MoodFace.grey(c[4]) }
end

--- A step as a number from -1 (very unpleasant) to 1 (very pleasant).
function MoodFace.score(valence)
    for i, v in ipairs(MoodFace.VALENCES) do if v == valence then return (i - 4) / 3 end end
    return 0
end

--- The mouth (in the face's 40 × 40 box): its corners' height and its middle's
--- (the corners rise and the middle drops as the feeling gets more pleasant).
function MoodFace.mouth(valence)
    local s = MoodFace.score(valence)
    return 27 - 2.2 * s, 27 + 6.5 * s
end

--- What a pixel of the face is, at (u, v) in the 40 × 40 box: nil outside
--- it; "edge"; "ink" (an eye or the mouth); or "fill", with how far it is
--- from the light at the upper left (0 … 1) and whether it's in the shine.
function MoodFace.part(u, v, valence)
    local dx, dy = u - 20, v - 20
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 17.6 then return nil end
    if d > 16.4 then return "edge" end
    -- the eyes
    local function near(cx, cy, r) return (u - cx) ^ 2 + (v - cy) ^ 2 <= r * r end
    if near(14, 18, 2) or near(26, 18, 2) then return "ink" end
    -- the mouth: a quadratic curve from (13, corner) through (20, middle) to (27, corner), 2.2 wide
    if u >= 12 and u <= 28 then
        local corner, middle = MoodFace.mouth(valence)
        local best = math.huge
        for k = 0, 24 do
            local t2 = k / 24
            local px = (1 - t2) ^ 2 * 13 + 2 * (1 - t2) * t2 * 20 + t2 ^ 2 * 27
            local py = (1 - t2) ^ 2 * corner + 2 * (1 - t2) * t2 * middle + t2 ^ 2 * corner
            local dd = (u - px) ^ 2 + (v - py) ^ 2
            if dd < best then best = dd end
        end
        if best <= 1.21 then return "ink" end
    end
    -- the glossy fill: light at the upper left, the step's colour toward the edge;
    -- the shine, an ellipse at the top, white at 45 %
    local gx, gy = u - 15.2, v - 12
    local t = math.min(1, math.sqrt(gx * gx + gy * gy) / 30)
    local ex, ey = (u - 20) / 11, (v - 11) / 6
    return "fill", t, ex * ex + ey * ey <= 1
end

--- One channel's level (0–255) for a part, from `g` ({ fill, light, edge, ink }).
local function level(g, kind, t, shine, faded)
    local l
    if kind == "edge" then l = g.edge
    elseif kind == "ink" then l = g.ink
    else
        l = g.light + (g.fill - g.light) * t
        if shine then l = l + (255 - l) * 0.45 end
    end
    if faded then l = l + (255 - l) * 0.6 end
    return math.max(0, math.min(255, math.floor(l + 0.5)))
end

--- How a pixel of the face looks: the grey at (u, v) in the 40 × 40 box, or
--- nil outside it. `faded`: lighter (a face not chosen yet).
function MoodFace.pixel(u, v, valence, g, faded)
    local kind, t, shine = MoodFace.part(u, v, valence)
    if not kind then return nil end
    return level(g or MoodFace.greys(valence), kind, t, shine, faded)
end

--- A step's colours as three channels: { r = { fill, light, edge, ink }, g = …, b = … }.
function MoodFace.channels(valence)
    local c = MoodFace.COLORS[valence] or MoodFace.COLORS.neutral
    local out = { r = {}, g = {}, b = {} }
    for i, name in ipairs({ "fill", "light", "edge", "ink" }) do
        local r, g, b = c[i]:match("^#(%x%x)(%x%x)(%x%x)$")
        out.r[name], out.g[name], out.b[name] = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    end
    return out
end

--- The pixel in colour: r, g, b, or nil outside the face.
function MoodFace.rgbPixel(u, v, valence, ch, faded)
    local kind, t, shine = MoodFace.part(u, v, valence)
    if not kind then return nil end
    ch = ch or MoodFace.channels(valence)
    return level(ch.r, kind, t, shine, faded), level(ch.g, kind, t, shine, faded), level(ch.b, kind, t, shine, faded)
end

--- Does the face go on in colour? (A colour screen showing colour.)
function MoodFace.colour()
    return require("gzreader_colour").enabled() and Blitbuffer.ColorRGB32 ~= nil
end

--- A step's own colour to paint with (its fill): in colour on a colour
--- screen, else its grey.
function MoodFace.fillColor(valence)
    if MoodFace.colour() then
        local ch = MoodFace.channels(valence)
        return Blitbuffer.ColorRGB32(ch.r.fill, ch.g.fill, ch.b.fill, 0xFF)
    end
    return Blitbuffer.Color8(MoodFace.greys(valence).fill)
end

--- Paints the face `size` pixels square at (x, y) on `bb` (in the web's
--- colours on a colour screen, greys of the same lightness elsewhere).
function MoodFace.paint(bb, x, y, size, valence, faded)
    local k = 40 / size
    if MoodFace.colour() then
        local ch = MoodFace.channels(valence)
        for j = 0, size - 1 do
            local v = (j + 0.5) * k
            for i = 0, size - 1 do
                local r, g, b = MoodFace.rgbPixel((i + 0.5) * k, v, valence, ch, faded)
                if r then bb:setPixel(x + i, y + j, Blitbuffer.ColorRGB32(r, g, b, 0xFF)) end
            end
        end
        return
    end
    local g = MoodFace.greys(valence)
    for j = 0, size - 1 do
        local v = (j + 0.5) * k
        for i = 0, size - 1 do
            local lv = MoodFace.pixel((i + 0.5) * k, v, valence, g, faded)
            if lv then bb:setPixel(x + i, y + j, Blitbuffer.Color8(lv)) end
        end
    end
end

local Face = Widget:extend{ valence = "neutral", size = 40, faded = false }

function Face:getSize() return Geom:new{ w = self.size, h = self.size } end

function Face:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.size, h = self.size }
    MoodFace.paint(bb, x, y, self.size, self.valence, self.faded)
end

--- A widget showing the face: { valence, size, faded }.
function MoodFace.widget(o) return Face:new(o) end

return MoodFace
