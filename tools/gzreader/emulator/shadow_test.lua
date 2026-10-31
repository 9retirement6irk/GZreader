-- frontend/device/kindle/shadowfb.lua: drawing into the 8-bit shadow screen with the C
-- blitter and packing gives the same 4-bit framebuffer bytes as drawing into it in Lua
-- (as before), rotated and in night mode. Run from a KOReader tree with its luajit.
require("setupkoenv")
package.path = "frontend/?.lua;" .. package.path
local BB = require("ffi/blitbuffer")
package.loaded["logger"] = { info = function() end, warn = print, dbg = function() end }
local Shadow = dofile("frontend/device/kindle/shadowfb.lua")
local ffi = require("ffi")
local fails = 0
local function check(ok, msg) if not ok then fails = fails + 1 end print((ok and "ok   " or "FAIL ") .. msg) end
local W, H = 600, 800
local function mkscreen()
    local fb = BB.new(W, H, BB.TYPE_BB4); fb:invert(); fb:fill(BB.COLOR_WHITE)
    local scr = { bb = fb, calls = {} }
    function scr:refreshPartialImp(x, y, w, h) self.calls[#self.calls + 1] = { x, y, w, h } end
    function scr:refreshFullImp(x, y, w, h) self.calls[#self.calls + 1] = { x, y, w, h } end
    return scr
end
pcall(ffi.cdef, "int memcmp(const void *a, const void *b, size_t n);")
local function eq(a, b)
    return ffi.C.memcmp(a.data, b.data, tonumber(a.stride) * H) == 0
end
local img = BB.new(37, 53, BB.TYPE_BB8)
for y = 0, 52 do for x = 0, 36 do img:setPixel(x, y, BB.Color8((x * 7 + y * 3) % 256)) end end
local function draw(bb)
    bb:fill(BB.COLOR_WHITE)
    bb:paintRect(10, 20, 101, 33, BB.COLOR_BLACK)
    bb:paintRect(301, 401, 50, 7, BB.COLOR_GRAY)
    bb:paintRect(0, 0, 1, 800, BB.COLOR_DARK_GRAY)
    bb:paintRect(599, 0, 1, 800, BB.COLOR_LIGHT_GRAY)
    bb:blitFrom(img, 123, 77, 0, 0, 37, 53)
    bb:blitFrom(img, 0, 700, 3, 5, 30, 40)
end
for _i, case in ipairs({ { rot = 0 }, { rot = 1 }, { rot = 2 }, { rot = 3 }, { rot = 0, night = true }, { rot = 1, night = true } }) do
    -- reference: straight into the inverted BB4 (as without the shadow)
    local ref = BB.new(W, H, BB.TYPE_BB4); ref:invert()
    ref:setRotation(case.rot)
    if case.night then ref:invert() end
    BB:setUseCBB(false) -- (as before: no C blitter on the Kindle 3)
    draw(ref)
    BB:setUseCBB(true)
    -- shadow
    local scr = mkscreen()
    check(Shadow.install(scr) and scr.bb:getType() == BB.TYPE_BB8, "installed")
    scr.bb:setRotation(case.rot)
    if case.night then scr:setHWNightmode(true) end
    draw(scr.bb)
    scr:refreshPartialImp(0, 0, scr.bb:getWidth(), scr.bb:getHeight())
    check(eq(ref, scr._gz_fb_bb), string.format("rotation %d%s: framebuffer bytes identical", case.rot, case.night and " night" or ""))
    -- a small region only: the rest unchanged
    scr.bb:paintRect(5, 5, 3, 3, BB.COLOR_BLACK)
    BB:setUseCBB(false); ref:paintRect(5, 5, 3, 3, BB.COLOR_BLACK); BB:setUseCBB(true)
    scr:refreshFullImp(4, 4, 6, 6)
    check(eq(ref, scr._gz_fb_bb), string.format("rotation %d%s: odd-sized region", case.rot, case.night and " night" or ""))
end
print("C blitter in the shadow:", BB:getUseCBB())
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
