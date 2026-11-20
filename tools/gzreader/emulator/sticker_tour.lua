-- The drawing screen's Stickers tool, on a touch Kindle: the Kid Pix stickers
-- from the Memos fork (demo/mock_memos.py --stickers on 18090), the picker,
-- two stickers put down on ruled paper, Undo.
--   python3 -I demo/mock_memos.py 18090 --stickers &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh sticker_tour.lua <out>
-- Checks go to <out>/sticker-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function screen() return find("gz_drawscreen") end
local W, H
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = require("apps/filemanager/filemanager").instance.gzreader
    p.store.memos = { server = os.getenv("GZ_STICKER_SERVER") or "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    G_reader_settings:delSetting("gzreader_drawing_sticker")
    G_reader_settings:delSetting("gzreader_drawing_sticker_category")
    os.execute("rm -rf '" .. require("gzreader_stickers").dir() .. "'")
    require("gzreader_drawscreen").show{ title = "Stickers", plugin = p, on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E) screen():setPaper("ruled-medium") end, after = 3 })
add({ fn = function(E)
    check(button("sticker") ~= nil, "the tools down the side have Stickers")
    E.tap(button("sticker"))
end, after = 6 })
add({ shot = "1-picker", after = 0.5 })
add({ fn = function(E)
    local g = find("gz_sticker_grid")
    check(g and g.cat and g.cat.slug == "animals" and #g.cells == 3, "no sticker chosen yet: the picker, at the first category (its 3 stickers fetched)")
    E.tap({ g.cells[2].w.dimen.x + 20, g.cells[2].w.dimen.y + 20 })
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(not find("gz_sticker_grid") and d.tool == "sticker" and d.sticker and d.sticker.name == "Baby Zebra",
        "a sticker tapped: the picker closes, the Stickers tool in hand with it")
    E.tap({ math.floor(W * 0.4), math.floor(H * 0.35) })
end, after = 3 })
add({ fn = function(E) E.tap({ math.floor(W * 0.6), math.floor(H * 0.55) }) end, after = 3 })
add({ shot = "2-stamped", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local pics = d.sketch:movablePictures()
    check(#pics == 2 and pics[1].width == 30 * require("gzreader_stickers").SIZES[2], "two taps: two stickers on the page (Medium)")
    -- the clear ground: the paper's lines go on under the sticker, not a box
    local el = pics[1]
    local x0, y0 = d.sketch:toCanvas(el.x, el.y)
    local px = d.canvas_bb:getPixel(math.floor(x0) + 2, math.floor(y0) + 2)
    local v = px.a or (px.getColor8 and px:getColor8().a)
    check(v and v > 200, "…around the sticker the page shows, not a dark box (corner pixel " .. tostring(v) .. ")")
    E.tap(button("sticker"))
end, after = 3 })
add({ shot = "3-panel", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    check(d.flyout == "sticker" and button("ss3") ~= nil and button("sticker-pick") ~= nil, "Stickers again: its panel (another sticker, Small / Medium / Large)")
    E.tap(button("ss3"))
end, after = 2 })
add({ fn = function(E)
    check(screen().sticker_size == 3, "Large chosen")
    E.tap({ math.floor(W * 0.45), math.floor(H * 0.78) })
end, after = 3 })
add({ shot = "4-large", after = 0.5 })
add({ fn = function(E)
    E.tap(button("undo"))
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:movablePictures() == 2, "Undo takes the last sticker off")
    local f = io.open(E.out .. "/sticker-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
