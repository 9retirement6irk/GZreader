--[[--
GZreader: an 8-bit shadow screen for the Kindle 2/3/DX's 4-bit e-ink
framebuffer (and the Kindle 4's 8-bit one with inverted grey levels).

KOReader's fast C blitter doesn't handle 4-bit buffers, so on the Kindle 3
every glyph, icon and cover was drawn pixel by pixel in Lua (canUseCBB = no).
That drawing was most of the CPU time of every key press. Here KOReader
draws into an ordinary 8-bit buffer instead, where the C blitter works, and
just before each e-ink refresh the refreshed rectangle is packed into the
framebuffer (two pixels per byte, in the panel's inverted grey levels; on
the Kindle 4, one byte per pixel, inverted: the C blitter can't draw
inverted either).

The packing loop works in physical coordinates (rotation is the shadow
buffer's, as it was the framebuffer's). Night mode becomes a "hardware"
inversion: the packing inverts the grey levels (the device then reports
canHWInvert), so everything is drawn as by day with the C blitter, and
pictures are inverted exactly as before (KOReader's "don't invert images"
option works as on devices that invert in hardware).
]]

local bit = require("bit")
local ffi = require("ffi")
local BB = require("ffi/blitbuffer")
local logger = require("logger")

local band, bor, rshift = bit.band, bit.bor, bit.rshift

local ShadowFB = {}

--- Copy the physical rectangle (x, y, w, h) of `shadow` (8 bit) into an
--- 8-bit `fb`, grey levels flipped when `invert`.
local function copy8(shadow, fb, x, y, w, h, invert)
    local fw, fh = fb.w, fb.h
    if x < 0 then w = w + x; x = 0 end
    if y < 0 then h = h + y; y = 0 end
    if x + w > fw then w = fw - x end
    if y + h > fh then h = fh - y end
    if w <= 0 or h <= 0 then return end
    local sp = ffi.cast("uint8_t *", shadow.data)
    local dp = ffi.cast("uint8_t *", fb.data)
    local sstride, dstride = tonumber(shadow.stride), tonumber(fb.stride)
    if not invert then
        for row = y, y + h - 1 do ffi.copy(dp + row * dstride + x, sp + row * sstride + x, w) end
        return
    end
    for row = y, y + h - 1 do
        local s = sp + row * sstride + x
        local d = dp + row * dstride + x
        for i = 0, w - 1 do d[i] = bit.bxor(s[i], 0xFF) end
    end
end

--- Pack the physical rectangle (x, y, w, h) of `shadow` (8 bit) into `fb` (4 bit).
function ShadowFB.pack(shadow, fb, x, y, w, h, invert)
    if fb:getType() == BB.TYPE_BB8 then return copy8(shadow, fb, x, y, w, h, invert) end
    local fw, fh = fb.w, fb.h
    if x < 0 then w = w + x; x = 0 end
    if y < 0 then h = h + y; y = 0 end
    -- whole bytes: from an even column, an even number of columns
    if band(x, 1) == 1 then x = x - 1; w = w + 1 end
    if band(w, 1) == 1 then w = w + 1 end
    if x + w > fw then w = fw - x end
    if y + h > fh then h = fh - y end
    if w <= 0 or h <= 0 then return end
    local sp = ffi.cast("uint8_t *", shadow.data)
    local dp = ffi.cast("uint8_t *", fb.data)
    local sstride, dstride = tonumber(shadow.stride), tonumber(fb.stride)
    local pairs_n = rshift(w, 1)
    local last_odd = band(w, 1) == 1 -- (only at an odd-width right edge)
    local flip = invert and 0xFF or 0x00
    for row = y, y + h - 1 do
        local s = sp + row * sstride + x
        local d = dp + row * dstride + rshift(x, 1)
        for i = 0, pairs_n - 1 do
            local a = bit.bxor(s[2 * i], flip)
            local b = bit.bxor(s[2 * i + 1], flip)
            d[i] = bor(band(a, 0xF0), rshift(b, 4))
        end
        if last_odd then
            local a = bit.bxor(s[2 * pairs_n], flip)
            d[pairs_n] = bor(band(a, 0xF0), band(d[pairs_n], 0x0F))
        end
    end
end

--- The other way (the screen as it is when we start).
local function unpackScreen(fb, shadow, invert)
    local sp = ffi.cast("uint8_t *", shadow.data)
    local dp = ffi.cast("uint8_t *", fb.data)
    local sstride, dstride = tonumber(shadow.stride), tonumber(fb.stride)
    local flip = invert and 0xFF or 0x00
    if fb:getType() == BB.TYPE_BB8 then
        for row = 0, fb.h - 1 do
            local s, d = sp + row * sstride, dp + row * dstride
            for col = 0, fb.w - 1 do s[col] = bit.bxor(d[col], flip) end
        end
        return
    end
    for row = 0, fb.h - 1 do
        local s = sp + row * sstride
        local d = dp + row * dstride
        for col = 0, fb.w - 1 do
            local byte = d[rshift(col, 1)]
            local nib = band(col, 1) == 0 and rshift(byte, 4) or band(byte, 0x0F)
            s[col] = bit.bxor(bor(nib * 16, nib), flip)
        end
    end
end

--- A new shadow buffer for the screen's current framebuffer BB.
local function setup(screen)
    local fb = screen.bb
    if not fb or screen.full_bb then return false end
    local t = fb:getType()
    -- 4-bit, or 8-bit with inverted levels (the Kindle 4): what the C blitter can't draw on
    if not (t == BB.TYPE_BB4 or (t == BB.TYPE_BB8 and fb:getInverse() == 1)) then return false end
    local shadow = BB.new(fb.w, fb.h, BB.TYPE_BB8)
    -- the panel's 4-bit levels are inverted (0xF = black): its BB says so
    local invert = fb:getInverse() == 1
    unpackScreen(fb, shadow, invert)
    shadow:setRotation(fb:getRotation())
    screen._gz_fb_bb = fb
    screen._gz_fb_invert = invert
    screen.bb = shadow
    return true
end

--- Pack what changed in the shadow buffer into the framebuffer (logical rect).
function ShadowFB.sync(screen, x, y, w, h)
    local sb, real = screen.bb, screen._gz_fb_bb
    if not real or sb == real then return end
    if not (x and y and w and h) then
        x, y, w, h = 0, 0, sb:getWidth(), sb:getHeight()
    end
    x, y, w, h = sb:getBoundedRect(x, y, w, h)
    x, y, w, h = sb:getPhysicalRect(x, y, w, h)
    -- the panel's own inversion, flipped again in night mode
    ShadowFB.pack(sb, real, x, y, w, h, screen._gz_fb_invert ~= (screen._gz_night == true))
end

--- Put the shadow buffer in front of `screen` (an einkfb framebuffer object).
--- Returns true when done (the C blitter can then be used).
function ShadowFB.install(screen)
    if screen._gz_shadow then return true end
    -- off: a file named gz-no-shadow-screen in the koreader folder (over USB), or KO_NO_SHADOW_FB=1
    if os.getenv("KO_NO_SHADOW_FB") == "1" then return false end
    local f = io.open("gz-no-shadow-screen", "rb")
    if f then f:close(); return false end
    local ok, done = pcall(setup, screen)
    if not (ok and done) then
        if not ok then logger.warn("GZreader: no shadow screen:", done) end
        return false
    end
    screen._gz_shadow = true
    -- night mode: inverted while packing (see the top)
    screen.setHWNightmode = function(self, toggle) self._gz_night = toggle and true or false end
    screen.getHWNightmode = function(self) return self._gz_night == true end
    for _i, name in ipairs({ "refreshPartialImp", "refreshFullImp" }) do
        local orig = screen[name]
        screen[name] = function(self, x, y, w, h, d)
            ShadowFB.sync(self, x, y, w, h)
            return orig(self, x, y, w, h, d)
        end
    end
    -- a re-initialised framebuffer (hardware rotation, not used on the Kindle 3) gets a new shadow
    local orig_reinit = screen.reinit
    if orig_reinit then
        screen.reinit = function(self, ...)
            local r = { orig_reinit(self, ...) }
            if self.bb and (self.bb:getType() == BB.TYPE_BB4 or self.bb:getType() == BB.TYPE_BB8) then setup(self) end
            return unpack(r)
        end
    end
    logger.info("GZreader: 8-bit shadow screen in front of the framebuffer (C blitter on)")
    return true
end

return ShadowFB
