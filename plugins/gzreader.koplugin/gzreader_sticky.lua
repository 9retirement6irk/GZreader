--[[--
Drawing for the Notes tab: Patrick Hand, sticky notes (paper, shadow, tape,
a small tilt), Memos Markdown made readable, and pictures.

KOReader only turns images by 90°, so a note is painted into an 8-bit image
and turned by a degree or two here (bilinear, a few hundred thousand pixels
per page; the Notes tab keeps the result while it's open).
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local ffi = require("ffi")

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Sticky = {}

local root = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
root = root:gsub("^%./", "")
Sticky.FONT = root .. "/fonts/PatrickHand-Regular.ttf" -- SIL Open Font License, PatrickHand-OFL.txt

-- KOReader opens a font name as <its fonts folder>/<name>, so a plugin's font
-- is named relative to that folder ("../plugins/…" from ./fonts).
local hand_name
function Sticky.fontName()
    if hand_name ~= nil then return hand_name or nil end
    hand_name = false
    local ok, FontList = pcall(require, "fontlist")
    local fontdir = (ok and type(FontList) == "table" and FontList.fontdir) or "./fonts"
    local name
    if Sticky.FONT:match("^/") or fontdir:match("^/") then
        name = Sticky.FONT:match("^/") and Sticky.FONT or nil
    else
        local depth = select(2, fontdir:gsub("^%./", ""):gsub("[^/]+", ""))
        name = string.rep("../", depth) .. Sticky.FONT
    end
    local f = name and io.open(fontdir .. "/" .. name, "rb")
    if f then f:close(); hand_name = name end
    return hand_name or nil
end

--- Patrick Hand at `size` (one weight: callers use TextWidget's bold for tags).
function Sticky.hand(size)
    local name = Sticky.fontName()
    local face = name and Font:getFace(name, size)
    return face or Font:getFace("cfont", size)
end

-- ZenOS's icon font (Symbols Nerd Font subset): tag, location arrow, file,
-- image, calendar, star (pinned).
local ICON_FONT = "./plugins/zenos.koplugin/fonts/SymbolsNerdFont-Regular.ttf"
Sticky.ICONS = { pin = "\u{F04CE}", place = "\u{F124}", attach = "\u{F0224}", pdf = "\u{F0224}",
    image = "\u{F02F5}", tag = "\u{F12F7}", date = "\u{F073}" }
function Sticky.iconFace(size)
    local ok, face = pcall(Font.getFace, Font, ICON_FONT, size)
    return ok and face or Font:getFace("cfont", size)
end

---------------------------------------------------------------- pictures

--- `src` (8-bit gray) turned by `deg` degrees on white, smoothed.
function Sticky.rotate(src, deg)
    local a = math.rad(deg)
    local ca, sa = math.cos(a), math.sin(a)
    local sw, sh = src:getWidth(), src:getHeight()
    local dw = math.ceil(math.abs(sw * ca) + math.abs(sh * sa))
    local dh = math.ceil(math.abs(sw * sa) + math.abs(sh * ca))
    local dst = Blitbuffer.new(dw, dh, Blitbuffer.TYPE_BB8)
    local sp, ss = ffi.cast("uint8_t*", src.data), tonumber(src.stride)
    local dp, ds = ffi.cast("uint8_t*", dst.data), tonumber(dst.stride)
    local scx, scy, dcx, dcy = sw / 2, sh / 2, dw / 2, dh / 2
    for y = 0, dh - 1 do
        local ry = y - dcy
        local row = y * ds
        for x = 0, dw - 1 do
            local rx = x - dcx
            local fx = ca * rx + sa * ry + scx
            local fy = -sa * rx + ca * ry + scy
            local x0, y0 = math.floor(fx), math.floor(fy)
            local v = 255
            if x0 >= 0 and y0 >= 0 and x0 < sw - 1 and y0 < sh - 1 then
                local tx, ty = fx - x0, fy - y0
                local i = y0 * ss + x0
                local top = sp[i] + (sp[i + 1] - sp[i]) * tx
                local bot = sp[i + ss] + (sp[i + ss + 1] - sp[i + ss]) * tx
                v = top + (bot - top) * ty
            end
            dp[row + x] = v
        end
    end
    return dst
end

-- Each note's look, by its place on the page (the same every time).
Sticky.LOOK = {
    { angle = -2.4, shade = 0.10, tape = true, tape_shift = -20 },
    { angle = 1.9, shade = 0.00 },
    { angle = 1.2, shade = 0.04 },
    { angle = -1.7, shade = 0.16, tape = true, tape_shift = 25 },
    { angle = 2.6, shade = 0.12, tape = true, tape_shift = 5 },
    { angle = -1.1, shade = 0.02 },
}

function Sticky.look(i) return Sticky.LOOK[(i - 1) % #Sticky.LOOK + 1] end

function Sticky.paper(look)
    return look.shade > 0 and Blitbuffer.gray(look.shade) or Blitbuffer.COLOR_WHITE
end

--- `widget` (w x h) as a sticky note: shadow, paper, tape, tilt. A new image.
function Sticky.image(widget, w, h, look, focused)
    local m = S(10)
    local canvas = Blitbuffer.new(w + 2 * m, h + 2 * m, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    canvas:paintRect(m + S(4), m + S(5), w, h, Blitbuffer.gray(0.30)) -- shadow
    widget:paintTo(canvas, m, m)
    if focused then -- the 5-way's place: a thick frame
        local t = S(3)
        canvas:paintRect(m, m, w, t, Blitbuffer.COLOR_BLACK)
        canvas:paintRect(m, m + h - t, w, t, Blitbuffer.COLOR_BLACK)
        canvas:paintRect(m, m, t, h, Blitbuffer.COLOR_BLACK)
        canvas:paintRect(m + w - t, m, t, h, Blitbuffer.COLOR_BLACK)
    end
    if look.tape then
        local tw, th = S(70), S(18)
        local tx = m + math.floor((w - tw) / 2) + S(look.tape_shift or 0)
        canvas:paintRect(tx, m - math.floor(th / 2), tw, th, Blitbuffer.gray(0.22))
    end
    local img = Sticky.rotate(canvas, look.angle or 0)
    canvas:free()
    return img
end

--- A picture file shrunk to fit max_w x max_h (a new image), or nil.
function Sticky.picture(path, max_w, max_h)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local RenderImage = require("ui/renderimage")
    local ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    if not ok or not bb then return nil end
    local sc = math.min(max_w / bb:getWidth(), max_h / bb:getHeight(), 1)
    if sc < 1 then
        bb = RenderImage:scaleBlitBuffer(bb, math.max(1, math.floor(bb:getWidth() * sc)),
            math.max(1, math.floor(bb:getHeight() * sc)), true)
    end
    return bb
end

---------------------------------------------------------------- Markdown

-- Memos notes are Markdown. The Kindle shows them as plain text that reads
-- well: checklists as boxes, bullets as •, headings on their own, ** and _
-- markers dropped, links as their text, images as pictures.

--- The note's lines: { kind = "text"|"check"|"heading"|"image", text, done, level, src }
function Sticky.lines(content)
    local out = {}
    for line in ((content or "") .. "\n"):gmatch("(.-)\r?\n") do
        local mark, rest = line:match("^%s*[%-%*] %[([ xX])%]%s*(.*)$")
        local hashes, head = line:match("^(#+)%s+(.*)$")
        local src = line:match("^%s*!%[[^%]]*%]%(([^%)%s]+)[^%)]*%)%s*$")
        if mark then
            out[#out + 1] = { kind = "check", done = mark ~= " ", text = rest }
        elseif src then
            out[#out + 1] = { kind = "image", src = src }
        elseif hashes and #hashes <= 6 then
            out[#out + 1] = { kind = "heading", level = #hashes, text = head }
        else
            out[#out + 1] = { kind = "text", text = line }
        end
    end
    while #out > 0 and out[#out].kind == "text" and out[#out].text == "" do table.remove(out) end
    return out
end

--- Inline Markdown made plain: **bold**, *it*, `code`, [text](url), bullets.
function Sticky.plain(s)
    s = s:gsub("!%[([^%]]*)%]%([^%)]*%)", "%1")
    s = s:gsub("%[([^%]]+)%]%([^%)]*%)", "%1")
    s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("__(.-)__", "%1")
    s = s:gsub("%f[%w%*]%*([^%*\n]+)%*", "%1"):gsub("%f[%w_]_([^_\n]+)_", "%1")
    s = s:gsub("~~(.-)~~", "%1"):gsub("`([^`]*)`", "%1")
    s = s:gsub("^(%s*)[%-%*%+] ", "%1\u{2022} ")
    s = s:gsub("^>%s?", "\u{201C}")
    return s
end

--- A line with nothing but #tags (shown on their own row instead).
function Sticky.tagsOnly(text)
    local n = 0
    for word in text:gmatch("%S+") do
        if not word:match("^#[%w_%-/]+$") then return false end
        n = n + 1
    end
    return n > 0
end

--- The whole note as plain text (sticky notes): boxes for checklists, no
--- blank lines (a sticky note is small), tag-only lines left out.
function Sticky.preview(content)
    local t = {}
    for _i, l in ipairs(Sticky.lines(content)) do
        if l.kind == "check" then t[#t + 1] = (l.done and "\u{2611} " or "\u{2610} ") .. Sticky.plain(l.text)
        elseif l.kind == "heading" then t[#t + 1] = Sticky.plain(l.text)
        elseif l.kind == "text" and l.text:match("%S") and not Sticky.tagsOnly(l.text) then t[#t + 1] = Sticky.plain(l.text) end
    end
    return (table.concat(t, "\n"):gsub("^%s+", ""))
end

--- The first picture in a note (its src: an attachment path or a link).
function Sticky.firstImage(content)
    for _i, l in ipairs(Sticky.lines(content)) do
        if l.kind == "image" then return l.src end
    end
end

--- Tick or untick the n-th checklist item. Returns the new content.
function Sticky.toggle(content, n)
    local k = 0
    local out = {}
    for line in ((content or "") .. "\n"):gmatch("(.-)\n") do
        local pre, mark, post = line:match("^(%s*[%-%*] %[)([ xX])(%].*)$")
        if pre then
            k = k + 1
            if k == n then line = pre .. (mark == " " and "x" or " ") .. post end
        end
        out[#out + 1] = line
    end
    if out[#out] == "" then table.remove(out) end
    return table.concat(out, "\n")
end

--- os.time for UTC fields (summer time included).
function Sticky.timegm(f)
    local t = os.time(f) -- read as local time
    local lt, ut = os.date("*t", t), os.date("!*t", t)
    ut.isdst = lt.isdst
    return t + (os.time(lt) - os.time(ut))
end

--- "Today 9:12 PM", "Yesterday", "Oct 25", "Oct 25, 2025" from an RFC 3339 time.
function Sticky.when(iso, now)
    if type(iso) ~= "string" then return "" end
    local y, mo, d, h, mi = iso:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if not y then return "" end
    -- RFC 3339 is UTC here (Memos sends Z); shown in GZreader's time zone
    local t = Sticky.timegm{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi) }
    now = now or os.time()
    local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    local dt, dn = os.date("*t", t), os.date("*t", now)
    local clock = string.format("%d:%02d %s", (dt.hour % 12 == 0) and 12 or dt.hour % 12, dt.min, dt.hour < 12 and "AM" or "PM")
    if dt.year == dn.year and dt.yday == dn.yday then return "Today " .. clock end
    if dt.year == dn.year and dt.yday == dn.yday - 1 then return "Yesterday" end
    if dt.year == dn.year then return months[dt.month] .. " " .. dt.day end
    return months[dt.month] .. " " .. dt.day .. ", " .. dt.year
end

return Sticky
