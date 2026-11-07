-- Nook 1st Edition: the e-ink controller commands GZreader sends
-- (device/nook/display_hw.lua, checked against B&N's kernel:
-- drivers/video/epson-13521) and the colour screen's touch handling
-- (device/nook/lcd.lua).
--   luajit nook_test.lua <koreader repo> <koreader base (ffi/)>
local REPO, KOROOT = arg[1], arg[2]
package.path = REPO .. "/frontend/?.lua;" .. KOROOT .. "/?.lua;" .. KOROOT .. "/frontend/?.lua;" .. package.path
local ffi = require("ffi")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function preload(name, val) package.preload[name] = function() return val end end
preload("libs/libkoreader-lfs", { attributes = function() end, currentdir = function() return "." end })
preload("logger", { dbg = function() end, info = function() end, warn = function(...) print("    [warn]", ...) end, err = print })
local scheduled = {}
preload("ui/uimanager", {
    scheduleIn = function(_, s, f) scheduled[f] = s end,
    unschedule = function(_, f) scheduled[f] = nil end,
    nextTick = function(_, f) scheduled[f] = 0 end,
})

------------------------------------------------------------------ display_hw
print("e-ink controller commands")
local HW = require("device/nook/display_hw")
local calls, sysfs = {}, {}
local mem = ffi.new("uint8_t[?]", 600 * 944 * 2 * 2)
local lcdmem = ffi.new("uint8_t[?]", 240 * 960 * 2)
for i = 0, 600 * 944 * 2 * 2 - 1, 2 do mem[i] = 0x34; mem[i + 1] = 0x12 end -- (Android's picture)
HW.sys = {
    open = function(path)
        return ({ ["/dev/graphics/fb0"] = 10, ["/dev/graphics/fb1"] = 12, ["/dev/graphics/fb2"] = 11 })[path] or -1
    end,
    close = function() return 0 end,
    ioctl = function(fd, req, arg)
        req = tonumber(req)
        if req == 0x4602 then -- FBIOGET_FSCREENINFO
            local id = fd == 10 and "bravo-vfb" or (fd == 12 and "s3cfb" or "S1D13521")
            ffi.copy(arg.id, id)
            arg.line_length = fd == 10 and 1200 or (fd == 12 and 480 or 600)
            arg.smem_len = fd == 10 and 600 * 944 * 2 * 2 or (fd == 12 and 240 * 960 * 2 or 600 * 800 * 3)
            return 0
        elseif req == 0x4600 then -- FBIOGET_VSCREENINFO
            arg.yoffset = 944 -- (Android last showed its second buffer)
            return 0
        end
        local rec = { fd = fd, req = req }
        if req == 0x4611 then rec.blank = tonumber(arg) end
        if req == 0x4547 then
            local hwc = ffi.cast("struct gz_s1d_hwc *", arg)
            rec.len = tonumber(hwc.value)
            rec.buf = tonumber(ffi.cast("intptr_t", hwc.buffer))
        elseif req == 0x4606 then
            rec.yoffset = tonumber(ffi.cast("struct fb_var_screeninfo *", arg).yoffset)
        elseif arg ~= nil and req >= 0x4500 and req < 0x4600 then
            local p = ffi.cast("struct gz_s1d_params *", arg)
            rec.p = { p.param[0], p.param[1], p.param[2], p.param[3], p.param[4] }
        end
        calls[#calls + 1] = rec
        return 0
    end,
    mmap = function(_a, _s, _p, _f, fd) return fd == 12 and lcdmem or mem end,
    munmap = function() return 0 end,
    write = function(path, v) sysfs[#sysfs + 1] = path .. "=" .. tostring(v); return true end,
    writeOnce = function(path, v) sysfs[#sysfs + 1] = path .. "=" .. tostring(v) .. "!"; return true end,
    -- (as Android leaves them asleep: tube off, backlight off and dimmed, taps only)
    read = function(path)
        if path:match("enable$") then return "1" end
        return ({ lcd_power = "0", backlight_power = "0", backlight_level = "8", gesture_mask = "1" })[path:match("[^/]+$")]
    end,
    find = function(dir, name)
        return (dir:match("spi") and "/sys/bus/spi/devices/spi0.0/" or "/sys/bus/i2c/devices/0-0020/") .. name
    end,
}
-- by default Android's way (the direct way froze a real Nook at its first refresh)
assert(HW:open())
local woke = table.concat(sysfs, " ")
check(HW.vfb_fd == 10 and HW.epd_fd == 11 and not HW.direct and not woke:find("enable=", 1, true),
    "by default: the kernel's e-ink updates (Android's way), left on")
check(woke:find("0-0020/gesture_mask=16!", 1, true) and woke:find("spi0.0/lcd_power=1!", 1, true)
    and woke:find("backlight_level=64", 1, true) and woke:find("backlight_power=1", 1, true),
    "the colour screen woken: LCD powered up, backlight on at Android's level, the panel reporting finger motion (one write each)")
local unblanked = false
for _i, c in ipairs(calls) do if c.req == 0x4611 and c.fd == 12 and c.blank == 0 then unblanked = true end end
check(unblanked, "…and the LCD controller unblanked (s3cfb: FBIOBLANK, as Android does)")
HW.vfb_fd, HW.epd_fd = nil, nil
calls, sysfs = {}, {}
local orig_mode = HW.epdMode
HW.epdMode = function() return "direct" end -- (GZ_NOOK_EPD=direct)
assert(HW:open())
HW.epdMode = orig_mode
check(HW.vfb_fd == 10 and HW.epd_fd == 11 and HW.direct, "GZ_NOOK_EPD=direct: finds bravo-vfb and the S1D13521 by name, drives the e-ink directly")
check(calls[1] and calls[1].req == 0x4606 and calls[1].yoffset == 0, "shows the vfb's first buffer (Android was on its second)")
check(sysfs[1] == "/sys/devices/platform/s1d13521fb.0/enable=0", "the kernel's own e-ink updates off")

local BB = require("ffi/blitbuffer")
local page = BB.new(600, 800, BB.TYPE_BB8)
page:fill(BB.COLOR_WHITE)
calls = {}
HW:eink(page, 101, 50, 199, 20, "gu", false)
local reqs = {}
for _i, c in ipairs(calls) do reqs[#reqs + 1] = string.format("%x", c.req) end
check(table.concat(reqs, " ") == "4528 4529 4522 4511 4547 4523 4536 4528",
    "an update: wait trigger, wait frames, load area, data register, burst, end, update area, wait (" .. table.concat(reqs, " ") .. ")")
local ld = calls[3].p
check(ld[1] == 0x30 and ld[2] == 0 and ld[3] == 50 and ld[4] == 600 and ld[5] == 20, "load area: 8-bit pixels (3 << 4), whole rows 50-69")
check(calls[4].p[1] == 0x154, "pixel data goes to register 0x154 (the ioctl sends just that parameter)")
local base = tonumber(ffi.cast("intptr_t", page.data))
check(calls[5].len == 600 * 20 and calls[5].buf == base + 50 * 600, "burst: the 20 rows straight from the page buffer")
local up = calls[7].p
check(up[1] == 0x200 and up[2] == 100 and up[3] == 50 and up[4] == 200 and up[5] == 20,
    "partial update, GU waveform (2 << 8), x and width made even: 100, 50, 200 × 20")
calls = {}
HW:eink(page, 0, 0, 600, 800, "gc", true)
check(calls[7].req == 0x4534 and calls[7].p[1] == 0x300, "full refresh: UPD_FULL_AREA with GC (3 << 8)")
calls = {}
HW:eink(page, 10, 10, 30, 30, "du", false)
check(calls[7].req == 0x4536 and calls[7].p[1] == 0x100, "fast refresh: DU (1 << 8)")

print("colour screen picture")
local lcd_bb = BB.new(480, 144, BB.TYPE_BBRGB16)
lcd_bb:paintRectRGB32(0, 0, 480, 144, BB.ColorRGB32(0xFF, 0, 0, 0xFF))
calls = {}
local orig_lcd_mode = HW.lcdMode
HW.lcdMode = function() return "vfb" end
HW:lcd(lcd_bb)
local row800 = ffi.cast("uint16_t *", mem + 800 * 1200)
check(row800[0] == 0xF800 and row800[479] == 0xF800, "LCD rows go to vfb rows 800-943, RGB565 (red = 0xF800)")
check(row800[480] == 0x1234, "columns 480-599 untouched")
check(calls[1].req == 0x4642 and calls[1].fd == 10, "then the vfb's update ioctl (0x4642: copies them to the LCD)")
-- a kernel without the 2D engine (/dev/s3c-g2d): the picture written into
-- the colour screen's own framebuffer, turned 90°
HW.lcdMode = function() return "direct" end
HW.lcd_direct = nil
lcd_bb:paintRectRGB32(0, 0, 1, 1, BB.ColorRGB32(0, 0, 0xFF, 0xFF)) -- (a blue top-left pixel)
HW:lcd(lcd_bb)
local fb = ffi.cast("uint16_t *", lcdmem)
check(HW.lcd_direct and fb[0 * 240 + 239] == 0x001F and fb[0 * 240 + 238] == 0xF800 and fb[479 * 240 + 96] == 0xF800
    and fb[0 * 240 + 95] == 0, "no 2D engine: written into the s3cfb framebuffer, turned 90° into columns 96-239 (top-left lands top-right)")
HW.lcdMode = orig_lcd_mode
HW.lcd_direct = false

print("Android's way (GZ_NOOK_EPD=kernel)")
HW.direct = false
page:paintRect(0, 100, 600, 1, BB.Color8(0x80))
sysfs = {}
HW:eink(page, 0, 100, 600, 1, "gu", false)
check(ffi.cast("uint16_t *", mem + 100 * 1200)[5] == 0x8410, "grey 0x80 written to the vfb as RGB565 0x8410")
check(sysfs[1] == "/sys/devices/platform/s1d13521fb.0/redraw=1", "then the kernel redraws the page")
HW.direct = true

print("giving the screens back")
sysfs, calls = {}, {}
HW:close()
check(row800[0] == 0x1234, "Android's LCD picture restored")
local joined = table.concat(sysfs, " ")
check(joined:find("enable=1", 1, true) and joined:find("redraw=1", 1, true), "kernel updates back on, Android's page redrawn")
check(joined:find("gesture_mask=1!", 1, true) and joined:find("lcd_power=0!", 1, true) and joined:find("backlight_power=0", 1, true)
    and joined:find("backlight_level=8", 1, true), "the colour screen and touch panel left as Android had them (it wakes them itself)")

------------------------------------------------------------------ lcd touch
print("colour screen touches")
local LCD = require("device/nook/lcd")
local lcd = LCD:new{ hw = nil }
lcd.range = { x = { 0, 4095 }, y = { 0, 4095 } }
local got
lcd:setTouchHandler(function(g) got = g; return "Press" end)
local keys = {}
local input = {
    nook_virtual_codes = { Press = 28 },
    handleKeyBoardEv = function(_, ev) keys[#keys + 1] = ev.code .. ":" .. ev.value; return { code = ev.code, value = ev.value } end,
}
local t = 1000
local function ev(type_, code, value, dt)
    t = t + (dt or 0)
    return lcd:onInputEvent(input, { type = type_, code = code, value = value, time = { sec = math.floor(t), usec = math.floor((t % 1) * 1e6) } })
end
local function touch(x1, y1, x2, y2, dur)
    ev(3, 0, x1); ev(3, 1, y1); ev(3, 24, 100); ev(1, 330, 1); ev(0, 0, 0)
    if x2 then ev(3, 0, x2, dur / 2); ev(3, 1, y2); ev(0, 0, 0) end
    ev(3, 24, 0, dur / 2); ev(1, 330, 0)
    return ev(0, 0, 0)
end
local out = touch(2048, 2048, nil, nil, 0.1)
check(got and got.kind == "tap" and got.x == 240 and got.y == 72, "tap in the middle: 240, 72")
check(out and #out == 2 and keys[1] == "28:1" and keys[2] == "28:0", "the handler's key name → a press and release of its code")
touch(3500, 2048, 500, 2048, 0.3)
check(got.kind == "swipe" and got.dir == "west", "right to left: swipe west")
touch(2048, 3800, 2048, 300, 0.3)
check(got.kind == "swipe" and got.dir == "north", "bottom to top: swipe north")
touch(1000, 1000, nil, nil, 1.4)
check(got.kind == "hold", "a second on one spot: hold")
lcd.flip_x = true
touch(0, 0, nil, nil, 0.1)
check(got.x == 479 and got.y == 0, "mirrored left-right (setting)")
lcd.flip_x, lcd.swap_xy = false, true
touch(0, 4095, nil, nil, 0.1)
check(got.x == 479 and got.y == 0, "across and down swapped (setting)")
lcd.swap_xy = false
lcd.on = false
got = nil
out = touch(2048, 2048, nil, nil, 0.1)
check(got == nil and out == nil and lcd.on, "a touch while dark only lights the screen")

------------------------------------------------------------------ Simple Touch
print("Nook Simple Touch: e-ink area updates")
local NST = require("device/nook/framebuffer_nst")
local got_req, got = nil, {}
local fake = setmetatable({ bb = page, fd = 5, area = ffi.new("struct gz_omap3epfb_update_area"),
    ioctl = function(fd, req, a)
        got_req = req
        got = { fd = fd, a.x0, a.y0, a.x1, a.y1, a.wvfid, a.threshold }
        return 0
    end }, { __index = NST })
fake:refreshUIImp(10, 20, 30, 40)
check(got_req == 0xC0184F83, "OMAP3EPFB_IO_REQ_AREA_UPDATE = _IOWR('O', 0x83, 24 bytes)")
check(got.fd == 5 and got[1] == 10 and got[2] == 20 and got[3] == 39 and got[4] == 59, "area: first and last pixel (10, 20)-(39, 59)")
check(got[5] == 1 and got[6] == 0, "page / UI refresh: GU waveform, grey (threshold 0)")
fake:refreshFullImp(0, 0, 600, 800)
check(got[5] == 0 and got[3] == 599 and got[4] == 799, "full refresh: GC, whole screen")
fake:refreshFastImp(0, 0, 10, 10)
check(got[5] == 2, "fast: DU")
fake:refreshUIImp(590, 790, 50, 50)
check(got[3] == 599 and got[4] == 799, "clipped to the screen")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
