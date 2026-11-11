-- The quick panel's Layout tile in a book opens KOReader's bottom menu (size,
-- margins, spacing…) on every model, Zen mode on (a touch Kindle's Zen mode
-- blocked it). GZ_EMU_BOOK: an EPUB. Writes <out>/layout_tile.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local TOUCH = { kt = true, pw3 = true, nst = true }
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/layout.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/layout.epub")
end, after = 20 })
add({ fn = function(E)
    local zen = require("apps/filemanager/filemanager").instance
    local ok, cfg = pcall(function() return require("config/manager").load() end)
    check(ok and cfg.features.zen_mode == true, "Zen mode on")
    if TOUCH[E.model] then
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        E.swipe(W / 2, 3, W / 2, H / 2)
    else
        E.key("Menu")
    end
    return zen
end, after = 5 })
add({ shot = "layout-1-panel" })
add({ fn = function(E)
    local w = top()
    check(w and w.name == "gzreader quick panel", "the quick panel in the book (top: " .. tostring(w and w.name) .. ")")
    for _i, p in ipairs(w and w.placed or {}) do
        if p.tile.label == "Layout" then
            if TOUCH[E.model] then
                -- (a tap in the middle of the tile, where it was drawn)
                local d = p.tile.dimen
                E.tap({ d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) })
            else
                E.key(p.tile.key_letter)
            end
        end
    end
end, after = 5 })
add({ fn = function()
    local ReaderUI = require("apps/reader/readerui")
    local cd = ReaderUI.instance and ReaderUI.instance.config and ReaderUI.instance.config.config_dialog
    local shown = false
    for _i, e in ipairs(UIM()._window_stack) do if cd and e.widget == cd then shown = true end end
    check(shown, "Layout: KOReader's layout menu is open")
end, after = 1 })
add({ shot = "layout-2-menu" })
add({ fn = function(E)
    local f = io.open(E.out .. "/layout_tile.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
