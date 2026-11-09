-- The reader's top status bar (ZenOS; the clock by default) stays on screen
-- while KOReader's layout menu is open and after it closes: it used to be
-- drawn only while the book was the topmost window, so it went missing when
-- the menu opened from the quick panel and came back at the next page turn.
-- Touch models (pw3, kt). GZ_EMU_BOOK: an EPUB. Writes <out>/topbar_layout.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function rui() return require("apps/reader/readerui").instance end
-- dark pixels in the top status bar's band of what the panel shows
local function barInk(E)
    local bb, n = E.display, 0
    local w = bb:getWidth()
    for y = 2, 36, 2 do
        for x = 0, w - 1, 2 do
            if bb:getPixel(x, y):getColor8().a < 128 then n = n + 1 end
        end
    end
    return n
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/topbar.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/topbar.epub")
end, after = 20 })
add({ fn = function(E)
    check(barInk(E) > 0, "the book open: the top status bar is drawn")
end, after = 1 })
add({ fn = function(E)
    local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    E.swipe(W / 2, 3, W / 2, H / 2)
end, after = 5 })
add({ fn = function()
    local w = top()
    check(w and w.name == "gzreader quick panel", "the quick panel (top: " .. tostring(w and w.name) .. ")")
    -- what the Layout tile does (the panel closes, then the menu opens with force)
    if w and w.pick then w:pick({ label = "Layout", run = function() rui().config:onShowConfigMenu(true) end }) end
end, after = 5 })
add({ fn = function(E)
    local cd = rui().config.config_dialog
    check(cd ~= nil and top() == cd, "KOReader's layout menu is open")
    check(barInk(E) > 0, "layout menu open: the top status bar is still drawn")
end, after = 1 })
add({ shot = "topbar-1-layout" })
add({ fn = function()
    local ui = rui()
    ui:handleEvent(require("ui/event"):new("SetFontSize", (ui.document.configurable.font_size or 22) + 4))
    UIM():setDirty(ui, "full")
end, after = 6 })
add({ fn = function(E)
    check(barInk(E) > 0, "a bigger font with the menu open: the top status bar is still drawn")
end, after = 1 })
add({ shot = "topbar-2-font" })
add({ fn = function() rui().config:onCloseConfigMenu() end, after = 4 })
add({ fn = function(E)
    check(top() == rui(), "the menu closed")
    check(barInk(E) > 0, "menu closed: the top status bar is drawn")
end, after = 1 })
add({ shot = "topbar-3-closed" })
add({ fn = function(E)
    local f = io.open(E.out .. "/topbar_layout.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
