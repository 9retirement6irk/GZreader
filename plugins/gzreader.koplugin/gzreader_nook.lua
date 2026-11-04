--[[--
The Nook 1st Edition's colour touchscreen (480 × 144, under the e-ink page):
what GZreader shows there and what touching it does.

Panels:
- controls: the arrows and OK (the 5-way GZreader is driven with, as on a
  Kindle 4), Back, Menu, Home, page back / forward, and a button for the
  other panels (or the keyboard, while typing);
- info: while reading, the book's title, chapter, page and progress; elsewhere
  a clock; with the time, battery and Wi-Fi;
- cover: the open book's cover with its title, author and progress;
- keyboard: typing into the field on the e-ink page;
- off: dark (the backlight off).

Which panel shows when is a setting for each situation (reading, elsewhere,
typing); a touch on a panel that isn't the controls brings the controls up
for a while. Settings → Interface → Colour screen. The device side (touch
events, backlight, showing the picture) is frontend/device/nook/lcd.lua.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")

local NS = {}

local W, H = 480, 144
local function rgb(r, g, b) return Blitbuffer.ColorRGB32(r, g, b, 0xFF) end
local C = {
    bg = rgb(0x16, 0x18, 0x1c), key = rgb(0x2c, 0x31, 0x3a), key_hi = rgb(0x4a, 0x7d, 0xd8),
    key_alt = rgb(0x23, 0x27, 0x2e), ok = rgb(0x2f, 0x6f, 0xd0), text = rgb(0xf2, 0xf2, 0xf2),
    dim = rgb(0x9a, 0xa3, 0xb0), accent = rgb(0x5d, 0xa9, 0xff), bar = rgb(0x3a, 0x40, 0x4a),
    warn = rgb(0xff, 0x9f, 0x43), black = rgb(0, 0, 0),
}

local DEFAULTS = {
    reading = "info", -- info | cover | controls | off
    other = "controls", -- controls | info | off
    typing = "keyboard", -- keyboard | controls (the e-ink keyboard instead)
    touch_controls = true, -- a touch on another panel shows the controls…
    controls_s = 15, -- …for this long
    timeout = 60, -- backlight off when idle (s, 0 = never)
    level = 64, -- backlight level
    swipe = true, -- swipe to turn pages (reading)
    flip_x = false, flip_y = false, swap_xy = false, -- touch orientation
}

function NS.settings()
    local s = G_reader_settings:readSetting("gzreader_nook_lcd")
    if type(s) ~= "table" then s = {} end
    for k, v in pairs(DEFAULTS) do if s[k] == nil then s[k] = v end end
    return s
end

local function save(s)
    G_reader_settings:saveSetting("gzreader_nook_lcd", s)
    NS.apply()
end

---------------------------------------------------------------- drawing

local function utf8chars(s)
    return s:gmatch("[%z\1-\127\194-\244][\128-\191]*")
end
local function codepoint(ch)
    local b1 = ch:byte(1)
    if b1 < 0x80 then return b1 end
    local n = b1 >= 0xF0 and 4 or b1 >= 0xE0 and 3 or 2
    local cp = b1 % (2 ^ (7 - n))
    for i = 2, n do cp = cp * 64 + (ch:byte(i) or 0x80) % 64 end
    return cp
end

local faces = {}
local function face(size)
    faces[size] = faces[size] or Font:getFace("cfont", size)
    return faces[size]
end

--- Width of `text` in pixels.
local function textWidth(text, size, bold)
    local f = face(size)
    local w = 0
    for ch in utf8chars(text) do
        w = w + RenderText:getGlyph(f, codepoint(ch), bold).ax
    end
    return w
end

--- Shorten to `max_w` with an ellipsis.
local function fit(text, size, bold, max_w)
    if textWidth(text, size, bold) <= max_w then return text end
    local out = {}
    local f = face(size)
    local w = textWidth("…", size, bold)
    for ch in utf8chars(text) do
        local cw = RenderText:getGlyph(f, codepoint(ch), bold).ax
        if w + cw > max_w then break end
        w = w + cw
        out[#out + 1] = ch
    end
    return table.concat(out) .. "…"
end

--- Coloured text with its baseline at y (RenderText only does grey).
local function text(bb, x, y, str, size, color, bold)
    local f = face(size)
    local pen = x
    for ch in utf8chars(str) do
        local g = RenderText:getGlyph(f, codepoint(ch), bold)
        bb:colorblitFromRGB32(g.bb, pen + g.l, y - g.t, 0, 0, g.bb:getWidth(), g.bb:getHeight(), color)
        pen = pen + g.ax
    end
    return pen - x
end

local function centred(bb, x, y, w, h, str, size, color, bold)
    local tw = textWidth(str, size, bold)
    text(bb, x + math.floor((w - tw) / 2), y + math.floor((h + size * 0.7) / 2), str, size, color, bold)
end

---------------------------------------------------------------- state

NS.buttons = {} -- what the current picture's buttons are: { x, y, w, h, action, label }
NS.typing = false
NS.kb_hidden = false -- "Done" on the keyboard: the controls until typing ends
NS.controls_until = 0 -- a touch on another panel: the controls until then
NS.kb_mode = "abc" -- abc | ABC (one letter) | 123
NS.pressed = nil

local function readerUI()
    local RUI = package.loaded["apps/reader/readerui"]
    local ui = RUI and RUI.instance
    if ui and ui.document then return ui end
end

--- reading | typing | other
function NS.context()
    if NS.typing then return "typing" end
    local ui = readerUI()
    if ui then
        local top = UIManager:getTopmostVisibleWidget()
        if top == ui or (top and top.name == "ReaderUI") then return "reading" end
    end
    return "other"
end

function NS.panel()
    local s = NS.settings()
    local ctx = NS.context()
    if NS.test then return "test" end
    if ctx == "typing" then
        if s.typing == "keyboard" and not NS.kb_hidden then return "keyboard" end
        return "controls"
    end
    if os.time() < NS.controls_until then return "controls" end
    local p = s[ctx] or "controls"
    if p == "cover" and ctx ~= "reading" then p = "info" end
    return p
end

---------------------------------------------------------------- panels

local function button(bb, x, y, w, h, label, action, opts)
    opts = opts or {}
    local hi = NS.pressed == label
    bb:paintRoundedRectRGB32(x, y, w, h, hi and C.key_hi or opts.color or C.key, 8)
    centred(bb, x, y, w, h, label, opts.size or 22, opts.fg or C.text, opts.bold)
    NS.buttons[#NS.buttons + 1] = { x = x, y = y, w = w, h = h, action = action, label = label }
end

local P = {}

function P.controls(bb)
    local typing = NS.context() == "typing"
    -- the 5-way
    button(bb, 80, 4, 72, 42, "▲", "Up")
    button(bb, 4, 50, 72, 44, "◀", "Left")
    button(bb, 80, 50, 72, 44, "OK", "Press", { color = C.ok, bold = true })
    button(bb, 156, 50, 72, 44, "▶", "Right")
    button(bb, 80, 98, 72, 42, "▼", "Down")
    -- keys
    button(bb, 240, 4, 76, 66, _("Back"), "Back", { size = 18 })
    button(bb, 320, 4, 76, 66, _("Menu"), "Menu", { size = 18 })
    button(bb, 400, 4, 76, 66, _("Home"), "Home", { size = 18 })
    button(bb, 240, 74, 76, 66, "◀◀", "RPgBack", { color = C.key_alt })
    button(bb, 320, 74, 76, 66, "▶▶", "RPgFwd", { color = C.key_alt })
    if typing and NS.settings().typing == "keyboard" then
        button(bb, 400, 74, 76, 66, "⌨", function() NS.kb_hidden = false; NS.refresh() end, { size = 26 })
    else
        button(bb, 400, 74, 76, 66, "•••", function() NS.nextPanel() end, { size = 20 })
    end
end

local function clockText()
    local ok, datetime = pcall(require, "datetime")
    if ok and datetime.secondsToHour then
        return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    end
    return os.date("%H:%M")
end

local function statusLine(bb, x_right, y)
    local parts = {}
    local ok, cap = pcall(function() return Device:getPowerDevice():getCapacity() end)
    if ok and cap then parts[#parts + 1] = cap .. "%" end
    local okw, wifi = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    parts[#parts + 1] = (okw and wifi) and "Wi-Fi" or ""
    parts[#parts + 1] = clockText()
    local str = table.concat(parts, "   "):gsub("^%s+", "")
    local w = textWidth(str, 16)
    text(bb, x_right - w, y, str, 16, C.dim)
end

--- Page, total, percent, chapter of the open book.
local function progress(ui)
    local doc = ui.document
    local page, total
    pcall(function()
        total = doc:getPageCount()
        if ui.paging then page = ui.view.state.page else page = doc:getCurrentPage() end
    end)
    local chapter
    pcall(function() chapter = ui.toc:getTocTitleByPage(page) end)
    local title, authors
    pcall(function()
        local p = ui.doc_props or {}
        title, authors = p.display_title or p.title, p.authors
    end)
    if not title or title == "" then title = (doc.file or ""):match("([^/]+)$") or "" end
    return { page = page or 0, total = total or 0, chapter = chapter ~= "" and chapter or nil,
        title = title, authors = authors and tostring(authors):gsub("\n", ", ") or nil }
end

local function progressBar(bb, x, y, w, pr)
    bb:paintRoundedRectRGB32(x, y, w, 10, C.bar, 5)
    local frac = pr.total > 0 and math.min(1, pr.page / pr.total) or 0
    if frac > 0 then bb:paintRoundedRectRGB32(x, y, math.max(10, math.floor(w * frac)), 10, C.accent, 5) end
    return frac
end

function P.info(bb)
    local ui = readerUI()
    if ui and NS.context() == "reading" then
        local pr = progress(ui)
        text(bb, 12, 30, fit(pr.title, 22, true, 300), 22, C.text, true)
        statusLine(bb, W - 12, 28)
        if pr.chapter then text(bb, 12, 62, fit(pr.chapter, 18, false, W - 24), 18, C.dim) end
        local frac = progressBar(bb, 12, 84, W - 24, pr)
        local where = pr.total > 0 and string.format(_("Page %d of %d"), pr.page, pr.total) or ""
        text(bb, 12, 124, where, 18, C.text)
        local pct = string.format("%d%%", math.floor(frac * 100 + 0.5))
        text(bb, W - 12 - textWidth(pct, 18, true), 124, pct, 18, C.accent, true)
        return
    end
    -- elsewhere: a clock
    local t = clockText()
    text(bb, 16, 84, t, 56, C.text, true)
    text(bb, 18, 122, os.date("%A, %d %B"), 18, C.dim)
    local ok, cap = pcall(function() return Device:getPowerDevice():getCapacity() end)
    local okw, wifi = pcall(function() return require("ui/network/manager"):isWifiOn() end)
    text(bb, W - 16 - textWidth("GZreader", 18, true), 34, "GZreader", 18, C.accent, true)
    if ok and cap then
        local s = string.format(_("Battery %d%%"), cap)
        text(bb, W - 16 - textWidth(s, 16), 84, s, 16, C.dim)
    end
    local ws = (okw and wifi) and _("Wi-Fi on") or _("Wi-Fi off")
    text(bb, W - 16 - textWidth(ws, 16), 108, ws, 16, C.dim)
end

--- The open book's cover (once per book), scaled to the panel's height.
local function cover(ui)
    local file = ui.document.file
    if NS.cover_file == file then return NS.cover_bb end
    if NS.cover_bb then NS.cover_bb:free() end
    NS.cover_file, NS.cover_bb = file, nil
    local ok, img = pcall(function() return ui.document:getCoverPageImage() end)
    if ok and img then
        local iw, ih = img:getWidth(), img:getHeight()
        local scale = math.min(96 / iw, (H - 12) / ih)
        local RenderImage = require("ui/renderimage")
        local ok2, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, img,
            math.max(1, math.floor(iw * scale)), math.max(1, math.floor(ih * scale)), true)
        if ok2 and scaled then
            NS.cover_bb = scaled
        else
            img:free()
        end
    end
    return NS.cover_bb
end

function P.cover(bb)
    local ui = readerUI()
    if not ui then return P.info(bb) end
    local pr = progress(ui)
    local cb = cover(ui)
    local x = 12
    if cb then
        bb:blitFrom(cb, 6, math.floor((H - cb:getHeight()) / 2), 0, 0, cb:getWidth(), cb:getHeight())
        x = 6 + cb:getWidth() + 14
    end
    local tw = W - x - 12
    text(bb, x, 30, fit(pr.title, 22, true, tw), 22, C.text, true)
    if pr.authors then text(bb, x, 56, fit(pr.authors, 18, false, tw), 18, C.dim) end
    local frac = progressBar(bb, x, 76, tw, pr)
    local where = pr.total > 0 and string.format(_("%d of %d"), pr.page, pr.total) or ""
    text(bb, x, 112, where, 18, C.text)
    local pct = string.format("%d%%", math.floor(frac * 100 + 0.5))
    text(bb, W - 12 - textWidth(pct, 18, true), 112, pct, 18, C.accent, true)
    local t = clockText()
    text(bb, W - 12 - textWidth(t, 16), 136, t, 16, C.dim)
end

local KB = {
    abc = { "qwertyuiop", "asdfghjkl", "zxcvbnm,." },
    ["123"] = { "1234567890", "@#$%&*-+()", "!\"':;/?_" },
}

function P.keyboard(bb)
    local mode = NS.kb_mode
    local rows = KB[mode == "123" and "123" or "abc"]
    local kh, gap = 34, 2
    local function key(x, y, w, label, action, opts)
        button(bb, x + gap / 2, y + gap / 2, w - gap, kh - gap, label, action, opts)
    end
    local function chars(row)
        local out = {}
        for ch in utf8chars(row) do out[#out + 1] = ch end
        return out
    end
    -- row 1
    local r1 = chars(rows[1])
    for i, ch in ipairs(r1) do
        local c = mode == "ABC" and ch:upper() or ch
        key((i - 1) * 48, 2, 48, c, { text = c }, { size = 20 })
    end
    -- row 2 (+ ⌫ on letters)
    local r2 = chars(rows[2])
    local x0 = math.floor((W - #r2 * 48) / 2)
    for i, ch in ipairs(r2) do
        local c = mode == "ABC" and ch:upper() or ch
        key(x0 + (i - 1) * 48, 2 + kh, 48, c, { text = c }, { size = 20 })
    end
    -- row 3: ⇧ letters ⌫
    key(0, 2 + 2 * kh, 60, mode == "ABC" and "⬆" or mode == "123" and "ABC" or "⇧",
        function() NS.kb_mode = NS.kb_mode == "ABC" and "abc" or "ABC"; NS.refresh() end,
        { color = mode == "ABC" and C.key_hi or C.key_alt, size = mode == "123" and 16 or nil })
    local r3 = chars(rows[3])
    for i, ch in ipairs(r3) do
        local c = mode == "ABC" and ch:upper() or ch
        key(60 + (i - 1) * 40, 2 + 2 * kh, 40, c, { text = c }, { size = 20 })
    end
    key(60 + #r3 * 40, 2 + 2 * kh, W - 60 - #r3 * 40, "⌫", "Backspace", { color = C.key_alt })
    -- row 4
    local y4 = 2 + 3 * kh
    key(0, y4, 70, mode == "123" and "abc" or "123",
        function() NS.kb_mode = NS.kb_mode == "123" and "abc" or "123"; NS.refresh() end, { color = C.key_alt, size = 18 })
    key(70, y4, 210, _("space"), { text = " " }, { size = 16, fg = C.dim })
    key(280, y4, 100, "⏎", "Press", { color = C.ok })
    key(380, y4, 100, _("Done"), function() NS.kb_hidden = true; NS.refresh() end, { color = C.key_alt, size = 18 })
end

function P.off(bb)
    bb:fill(Blitbuffer.COLOR_BLACK)
end

--- Touch test (Settings): where the panel says you touched.
function P.test(bb)
    local t = NS.test_touch
    text(bb, 30, 26, _("Touch test: tap the corners. Hold to finish."), 16, C.dim)
    for _i, c in ipairs({ { 0, 0 }, { W - 20, 0 }, { 0, H - 20 }, { W - 20, H - 20 } }) do
        bb:paintRectRGB32(c[1], c[2], 20, 20, C.warn)
    end
    if t then
        bb:paintRectRGB32(t.x - 1, 0, 3, H, C.accent)
        bb:paintRectRGB32(0, t.y - 1, W, 3, C.accent)
        local raw = NS.lcd() and NS.lcd().touch or {}
        text(bb, 30, 120, string.format("x %d  y %d   (panel %s, %s)", t.x, t.y, tostring(raw.rx), tostring(raw.ry)), 16, C.text)
    end
end

---------------------------------------------------------------- show

function NS.lcd() return Device.lcd end

function NS.paint(bb)
    NS.buttons = {}
    bb:fill(Blitbuffer.COLOR_BLACK)
    local name = NS.panel()
    NS.current = name
    if name ~= "off" then bb:paintRectRGB32(0, 0, W, H, C.bg) end
    local fn = P[name] or P.controls
    fn(bb)
end

function NS.refresh()
    local lcd = NS.lcd()
    if not lcd then return end
    local name = NS.panel()
    if name == "off" then
        lcd:refresh()
        if lcd.on and not NS.test then lcd:setBacklight(false) end
        return
    end
    lcd:refresh()
end

--- Refresh once, soon (several changes in a row: one picture).
function NS.schedule()
    if NS._scheduled then return end
    NS._scheduled = true
    UIManager:nextTick(function()
        NS._scheduled = false
        -- typing: an input dialog is open
        local typing = false
        local InputDialog = package.loaded["ui/widget/inputdialog"]
        if InputDialog then
            for _i, w in ipairs(UIManager._window_stack or {}) do
                local mt = getmetatable(w.widget)
                while mt do
                    if mt == InputDialog then typing = true; break end
                    mt = getmetatable(mt)
                end
                if typing then break end
            end
        end
        if typing ~= NS.typing then
            NS.typing = typing
            NS.kb_hidden, NS.kb_mode = false, "abc"
        end
        local before = NS.current
        NS.refresh()
        -- (a panel that was off: light up for the new one)
        local lcd = NS.lcd()
        if lcd and before == "off" and NS.current ~= "off" and not lcd.on then lcd:setBacklight(true) end
    end)
end

--- "•••" (or a swipe up / down): the next panel for this situation, kept.
function NS.nextPanel()
    local s = NS.settings()
    local ctx = NS.context()
    if ctx == "typing" then return end
    local order = ctx == "reading" and { "info", "cover", "controls" } or { "controls", "info" }
    local i = 0
    for k, v in ipairs(order) do if v == s[ctx] then i = k end end
    s[ctx] = order[i % #order + 1]
    NS.controls_until = 0
    G_reader_settings:saveSetting("gzreader_nook_lcd", s)
    NS.refresh()
end

---------------------------------------------------------------- touch

local function hit(x, y)
    for i = #NS.buttons, 1, -1 do
        local b = NS.buttons[i]
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then return b end
    end
end

local function flash(b)
    NS.pressed = b.label
    NS.lcd():refresh()
    UIManager:scheduleIn(0.15, function()
        NS.pressed = nil
        NS.refresh()
    end)
end

function NS.onTouch(g)
    local s = NS.settings()
    if NS.test then
        if g.kind == "hold" then NS.test = nil; NS.refresh(); return end
        NS.test_touch = { x = g.x, y = g.y }
        NS.refresh()
        return
    end
    local panel = NS.current or NS.panel()
    if g.kind == "swipe" then
        if not s.swipe or (panel == "keyboard") then return end
        if g.dir == "west" then return "RPgFwd" elseif g.dir == "east" then return "RPgBack" end
        if g.dir == "north" or g.dir == "south" then
            -- (up / down: the next panel)
            return function() NS.nextPanel() end
        end
        return
    end
    if panel ~= "controls" and panel ~= "keyboard" then
        -- a touch on reading info / the cover / the clock: the controls, for a while
        if s.touch_controls then
            NS.controls_until = os.time() + s.controls_s
            UIManager:scheduleIn(s.controls_s + 0.2, function() NS.schedule() end)
            return function() NS.refresh() end
        end
        return
    end
    local b = hit(g.x, g.y)
    if not b then return end
    if os.time() < NS.controls_until then
        -- (still using the controls: keep them up)
        NS.controls_until = os.time() + s.controls_s
        UIManager:scheduleIn(s.controls_s + 0.2, function() NS.schedule() end)
    end
    flash(b)
    if type(b.action) == "table" and b.action.text and NS.kb_mode == "ABC" then
        NS.kb_mode = "abc" -- (one capital)
        UIManager:scheduleIn(0.2, function() NS.refresh() end)
    end
    return b.action
end

---------------------------------------------------------------- setup

function NS.apply()
    local lcd = NS.lcd()
    if not lcd then return end
    local s = NS.settings()
    lcd.flip_x, lcd.flip_y, lcd.swap_xy = s.flip_x, s.flip_y, s.swap_xy
    lcd.chip_swipes = s.swipe
    lcd:setLevel(s.level)
    lcd:setTimeout(s.timeout)
    Device.lcd_keyboard = s.typing == "keyboard"
    NS.refresh()
end

function NS.install()
    local lcd = NS.lcd()
    if not lcd or NS.installed then return end
    NS.installed = true
    lcd:setPainter(NS.paint)
    lcd:setTouchHandler(NS.onTouch)
    -- typing on the colour screen: no keyboard on the page (some dialogs ask for it)
    local okv, VK = pcall(require, "ui/widget/virtualkeyboard")
    if okv and VK.showKeyboard then
        local orig_vk = VK.showKeyboard
        VK.showKeyboard = function(self, ...)
            if Device.lcd_keyboard then
                NS.schedule()
                return
            end
            return orig_vk(self, ...)
        end
    end
    -- what's on the e-ink page changes what the colour screen shows
    local orig_show, orig_close = UIManager.show, UIManager.close
    UIManager.show = function(self, widget, ...)
        local r = { orig_show(self, widget, ...) }
        -- a menu or dialog opened (you're using the controls): keep them up
        -- for a while even where another panel is chosen
        if type(widget) == "table" and widget.name ~= "ReaderUI" and widget.name ~= "filemanager"
                and not widget.invisible and not widget.toast then
            local st = NS.settings()
            NS.controls_until = math.max(NS.controls_until, os.time() + st.controls_s)
            UIManager:scheduleIn(st.controls_s + 0.2, function() NS.schedule() end)
        end
        NS.schedule()
        return unpack(r)
    end
    UIManager.close = function(self, ...)
        local r = { orig_close(self, ...) }
        NS.schedule()
        return unpack(r)
    end
    -- the clock and battery: every minute while lit
    local function tick()
        if lcd.on and NS.current ~= "controls" and NS.current ~= "keyboard" then NS.refresh() end
        UIManager:scheduleIn(60 - os.time() % 60 + 1, tick)
    end
    UIManager:scheduleIn(60 - os.time() % 60 + 1, tick)
    NS.apply()
    logger.info("nook: colour screen ready")
end

--- A page turned / a book opened or closed.
function NS.onReaderChange()
    if NS.current == "info" or NS.current == "cover" or NS.panel() ~= NS.current then NS.schedule() end
end

---------------------------------------------------------------- settings

function NS.menuItems()
    local function radio(key, value, label)
        return {
            text = label,
            radio = true,
            checked_func = function() return NS.settings()[key] == value end,
            callback = function() local s = NS.settings(); s[key] = value; save(s) end,
        }
    end
    local function check(key, label, help)
        return {
            text = label,
            help_text = help,
            checked_func = function() return NS.settings()[key] == true end,
            callback = function() local s = NS.settings(); s[key] = not s[key]; save(s) end,
        }
    end
    local function seconds(n)
        if n == 0 then return _("Never") end
        if n < 60 then return string.format(_("%d seconds"), n) end
        return n == 60 and _("1 minute") or string.format(_("%d minutes"), n / 60)
    end
    local timeouts, backs = {}, {}
    for _i, n in ipairs({ 15, 30, 60, 300, 0 }) do timeouts[#timeouts + 1] = radio("timeout", n, seconds(n)) end
    for _i, n in ipairs({ 5, 15, 30, 60 }) do backs[#backs + 1] = radio("controls_s", n, seconds(n)) end
    return {
        {
            text = _("While reading"),
            sub_item_table = {
                radio("reading", "info", _("Reading info: title, chapter, page, progress")),
                radio("reading", "cover", _("Cover, title and progress")),
                radio("reading", "controls", _("Controls")),
                radio("reading", "off", _("Nothing (dark)")),
            },
        },
        {
            text = _("Elsewhere (Home, menus, lists)"),
            sub_item_table = {
                radio("other", "controls", _("Controls")),
                radio("other", "info", _("Clock, battery and Wi-Fi")),
                radio("other", "off", _("Nothing (dark)")),
            },
        },
        {
            text = _("When typing"),
            sub_item_table = {
                radio("typing", "keyboard", _("Keyboard on the colour screen")),
                radio("typing", "controls", _("Keyboard on the page (arrows to type)")),
            },
        },
        check("touch_controls", _("Touch shows the controls"),
            _("When the colour screen shows reading info, the cover or the clock, a touch brings up the controls for a while.")),
        {
            text = _("Controls stay for"),
            sub_item_table = backs,
        },
        check("swipe", _("Swipe to turn pages"),
            _("Swipe left or right on the colour screen to turn pages; up or down for its next panel.")),
        {
            text = _("Turn off when not touched for"),
            sub_item_table = timeouts,
            separator = true,
        },
        {
            text = _("Brightness"),
            sub_item_table = {
                radio("level", 24, _("Low")),
                radio("level", 64, _("Medium")),
                radio("level", 140, _("High")),
            },
        },
        {
            text = _("Touch orientation"),
            sub_item_table = {
                {
                    text = _("Touch test"),
                    help_text = _("Shows where the colour screen thinks you touched; hold to finish. If it's mirrored, fix it below."),
                    callback = function() NS.test = true; NS.test_touch = nil; NS.refresh() end,
                    separator = true,
                },
                check("flip_x", _("Mirror left and right")),
                check("flip_y", _("Mirror top and bottom")),
                check("swap_xy", _("Swap across and down")),
            },
        },
    }
end

return NS
