-- The first book's page browser tip over a picture book (touch models: kt,
-- pw3, scribe). A picture book closes and opens again a second after it opens
-- (its fitted layout), with the tip already on screen; a swipe on the tip then
-- opened the page browser of the closed book and GZreader quit ("attempt to
-- index field 'document'", owner's Kindle Scribe, 2026-11-16).
-- Checks in <out>/tour_reopen.txt.
--   GZ_EMU_BOOK=pictures.epub GZ_EMU_MODEL=scribe run.sh tools/gzreader/emulator/tour_reopen.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function UIM() return require("ui/uimanager") end
local function top()
    local st = UIM()._window_stack
    return st[#st] and st[#st].widget
end
local function check(E, ok, what)
    local f = io.open(E.out .. "/tour_reopen.txt", "a")
    f:write((ok and "ok   " or "FAIL ") .. what .. "\n")
    f:close()
end
local first_ui
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    -- the quick panel's tour done, the page browser tip still to come
    local z = require("apps/filemanager/filemanager").instance.zenos
    z.config._meta.quickstart_menu_tour_pending = false
    z.config._meta.quickstart_reader_tour_pending = true
    z:saveConfig()
    local dir = (require("device").home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/reopen.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/reopen.epub")
end, after = 1 })
-- the first ReaderUI, as the tip saw it
add({ fn = function() first_ui = require("apps/reader/readerui").instance end, after = 45 })
add({ shot = "01-tip-after-reopen" })
add({ fn = function(E)
    local now = require("apps/reader/readerui").instance
    check(E, first_ui ~= nil and now ~= nil and now ~= first_ui and first_ui.document == nil,
        "the picture book was closed and opened again")
    local t = top()
    check(E, t ~= nil and t.steps ~= nil, "the page browser tip is still on screen after the reopen")
    if t and t.steps then
        local W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
        E.swipe(W / 2, H - 20, W / 2, H / 2)
    end
end, after = 6 })
add({ shot = "02-after-swipe" })
add({ fn = function(E)
    local t = top()
    local now = require("apps/reader/readerui").instance
    check(E, t ~= nil and (t.name or t.title) == "Page browser", "a swipe on the tip opens the page browser")
    check(E, t ~= nil and t.ui == now and now.document ~= nil, "the page browser is the open book's")
end, after = 1 })
return s
