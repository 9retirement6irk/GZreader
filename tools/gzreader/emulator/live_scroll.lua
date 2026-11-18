-- Scrolling that follows the finger (gzreader_livescroll.lua): with Layout →
-- Scroll up and down on, the notes list moves while the finger drags (not
-- only when it lifts), and so does an opened note that's longer than the
-- screen. The finger goes down, moves in steps a moment apart and stays
-- down while the checks look; then it lifts.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh live_scroll.lua <out>
-- Checks go to <out>/live-scroll-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function view() for _i, w in ipairs(UIM()._window_stack) do if w.widget.scroller and w.widget.memo then return w.widget end end end
local W, H
--- The screen's refreshes from now on, recorded (mode, region); `stop()` gives them back.
local function record()
    local got, real = {}, UIM()._refresh
    UIM()._refresh = function(self, mode, region, dither)
        got[#got + 1] = { mode = mode, region = region and { x = region.x, y = region.y, w = region.w, h = region.h } }
        return real(self, mode, region, dither)
    end
    return function() UIM()._refresh = real; return got end
end
--- Refreshes that reach outside `area` (whole-screen ones included), as text.
local function outside(got, area)
    local out, all = {}, {}
    for _i, r in ipairs(got) do
        local g = r.region
        local t = tostring(r.mode) .. (g and ("@" .. g.x .. "," .. g.y .. " " .. g.w .. "x" .. g.h) or "@all")
        all[#all + 1] = t
        if not g or g.y < area.y - 1 or g.y + g.h > area.y + area.h + 1 or g.x < area.x - 1 or g.x + g.w > area.x + area.w + 1 then out[#out + 1] = t end
    end
    return out, all
end

add({ fn = function()
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().show(p)
end, after = 8 })
add({ fn = function() N().setScrolling(plugin(), true) end, after = 4 })
add({ fn = function(E)
    local b = N().board
    check(b._gz_scroll ~= nil and b._gz_y == 0 and b._gz_scroll.max_y > 130, "the notes list scrolls (Layout → Scroll up and down)")
    E.board_area = b:notesRegion()
    E.stop = record()
    E.fingerDown(W * 0.5, H * 0.75)
    E.fingerMove(W * 0.5, H * 0.75 - 60, 0.3)
    E.fingerMove(W * 0.5, H * 0.75 - 120, 0.6)
end, after = 2 })
add({ shot = "1-list-following", after = 0.2 })
add({ fn = function(E)
    local b = N().board
    E.mid = b._gz_y
    check(b._gz_y >= 60 and b._gz_y <= 130, "the finger 120 px up and still down: the notes have followed (" .. b._gz_y .. " px)")
    E.fingerMove(W * 0.5, H * 0.75 - 200, 0.3)
    E.fingerMove(W * 0.5, H * 0.75 - 260, 0.9)
    E.fingerUp(2.5)
end, after = 4 })
add({ fn = function(E)
    local b = N().board
    local want = math.min(260, b._gz_scroll.max_y)
    check(b._gz_y == want and b._gz_pan == nil, "lifted (slowly) 260 px up: the notes settled there, or at their end (" .. b._gz_y .. " of " .. want .. " px)")
    local got = E.stop()
    local a = E.board_area or { x = 0, y = 0, w = 0, h = 0 }
    local out, all = outside(got, a)
    local settled = got[#got] and got[#got].mode == "partial"
    check(E.board_area and #got > 1 and #out == 0 and settled,
        "the list's steps and the clean refresh at the end: only the notes' window (" .. a.x .. "," .. a.y .. " " .. a.w .. "x" .. a.h
            .. "), not the buttons above or the tab bar under it (" .. table.concat(all, " ") .. ")")
    -- an opened note longer than the screen
    local memo = { name = "memos/live", content = ("A long note.\n\n" .. string.rep("Line after line of it, to scroll through.\n\n", 60)),
        visibility = "PRIVATE", createTime = "2026-11-16T10:00:00Z", updateTime = "2026-11-16T10:00:00Z" }
    N().showNote(plugin(), memo)
end, after = 4 })
add({ fn = function(E)
    local v = view()
    check(v and v.scroller._gz_live ~= nil, "an opened note: its page follows the finger too")
    if not v then return end
    v.scroller:initState()
    E.stop = record()
    E.fingerDown(W * 0.5, H * 0.7)
    E.fingerMove(W * 0.5, H * 0.7 - 80, 0.3)
    E.fingerMove(W * 0.5, H * 0.7 - 150, 0.7)
end, after = 2 })
add({ shot = "2-note-following", after = 0.2 })
add({ fn = function(E)
    local v = view()
    local y = v and v.scroller:getScrolledOffset().y or -1
    check(y >= 80 and y <= 160, "the finger 150 px up and still down: the note has followed (" .. y .. " px)")
    E.fingerMove(W * 0.5, H * 0.7 - 300, 0.4)
    E.fingerUp(2.5)
end, after = 4 })
add({ fn = function(E)
    local v = view()
    local y = v and v.scroller:getScrolledOffset().y or -1
    check(y == 300, "lifted 300 px up: the note settled there, the drag counted once (" .. y .. " px)")
    local got = E.stop()
    local d = v and v.scroller.dimen or { x = 0, y = 0, w = 0, h = 0 }
    local out, all = outside(got, d)
    check(v and #got > 1 and #out == 0 and got[#got].mode == "partial" and d.y > 0,
        "an opened note's steps and the clean refresh at the end: only its scrolling part (" .. d.x .. "," .. d.y .. " " .. d.w .. "x" .. d.h
            .. "), not its top bar (" .. table.concat(all, " ") .. ")")
    local f = io.open(E.out .. "/live-scroll-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
