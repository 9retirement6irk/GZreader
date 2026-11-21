-- The Kindle Scribe's pen mode (gzreader_penmode.lua) in the drawing
-- screen: with a display driver that has it (stood in for here: the
-- emulator's screen has no such call), a stroke's ink goes to the screen
-- at once as small "fast" updates with pen mode on; anything else that
-- updates the screen (a tap on the toolbar, a highlighter's grey when the
-- writing pauses, closing) has pen mode turned off first. Every update of
-- the screen is recorded with whether pen mode was on when it was sent.
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh pen_mode.lua <out>
-- No Memos needed. Checks go to <out>/pen-mode-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local function button(id)
    local d = screen()
    for _i, b in ipairs(d and d.buttons or {}) do
        if b.tool.id == id then return { b.rect.x + math.floor(b.rect.w / 2), b.rect.y + math.floor(b.rect.h / 2) } end
    end
end
local function line(E, fy, fx0, fx1, n)
    local pts = {}
    n = n or 24
    for i = 0, n do
        local p = pt(fx0 + (fx1 - fx0) * i / n, fy + 0.02 * math.sin(i / 2))
        p[3] = 2000
        pts[#pts + 1] = p
    end
    E.pen(pts, 0.5)
end
local PM
local sent, driver = {}, {}
local IMPS = { "refreshFullImp", "refreshPartialImp", "refreshNoMergePartialImp", "refreshFlashPartialImp",
    "refreshUIImp", "refreshNoMergeUIImp", "refreshFlashUIImp", "refreshFastImp", "refreshA2Imp" }
local function reset() sent, driver = {}, {} end
--- { ink = updates sent as ink, ink_off = …with pen mode off, big = …of 6000 pixels or more,
---   other = ordinary updates, other_on = …with pen mode on }
local function tally()
    local t = { ink = 0, ink_off = 0, big = 0, other = 0, other_on = 0, names = {} }
    for _i, u in ipairs(sent) do
        if u.ink then
            t.ink = t.ink + 1
            if not u.on then t.ink_off = t.ink_off + 1 end
            if u.w * u.h >= PM.MAX_AREA then t.big = t.big + 1 end
        else
            t.other = t.other + 1
            if u.on then t.other_on = t.other_on + 1 end
            t.names[#t.names + 1] = u.name:gsub("^refresh", ""):gsub("Imp$", "")
        end
    end
    return t
end

add({ fn = function(E)
    W, H = require("device").screen:getWidth(), require("device").screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    G_reader_settings:delSetting("gzreader_drawing_writing")
    PM = require("gzreader_penmode")
    G_reader_settings:delSetting(PM.SETTING)
    -- a display driver with pen mode, stood in for; its calls recorded
    PM.capable = function() return true end
    PM.send = function(_screen, mode) driver[#driver + 1] = mode == PM.ON and "on" or "off"; return 0 end
    PM.wait = function() driver[#driver + 1] = "wait" end
    PM.sleep = function(sec) driver[#driver + 1] = string.format("sleep %.2f", sec) end
    -- every update the screen is sent, under the pen mode's own watch (set first, so it wraps these)
    local Screen = require("device").screen
    for _i, name in ipairs(IMPS) do
        local orig = Screen[name]
        if orig then
            rawset(Screen, name, function(fb, x, y, w, h, ...)
                sent[#sent + 1] = { name = name, w = w, h = h, on = PM.on == true, ink = PM.sending == true }
                return orig(fb, x, y, w, h, ...)
            end)
        end
    end
    require("gzreader_drawscreen").show{ title = "Pen mode", on_done = function() end, on_cancel = function() end }
end, after = 4 })
add({ fn = function(E)
    local d = screen()
    check(d and d.pen_fast == true and PM.hooked ~= nil, "a pen Kindle whose display has a pen mode: the drawing screen will use it")
    reset()
    line(E, 0.3, 0.3, 0.7)
end, after = 0.3 })
add({ fn = function(E)
    -- (0.3 s after the stroke: before the pause that settles it)
    local d = screen()
    local t = tally()
    check(d and #d.sketch:live() == 1 and t.ink >= 3 and t.ink_off == 0 and t.big == 0 and driver[#driver] == "on" and (#driver == 1 or driver[1] == "wait"),
        "a pen stroke: pen mode on (after the last ordinary update, if it was just sent), then its ink in " .. t.ink .. " small updates (none of "
            .. PM.MAX_AREA .. " pixels or more; all with pen mode on) [" .. table.concat(driver, ",") .. "]")
    check(t.other == 0 and PM.on == true, "…nothing else sent to the screen during it or right after (" .. t.other .. " other updates), pen mode still on for the next stroke")
    reset()
    line(E, 0.4, 0.3, 0.7)
end, after = 0.3 })
add({ fn = function(E)
    local t = tally()
    check(t.ink >= 3 and t.ink_off == 0 and #driver == 0 and t.other == 0, "a second stroke straight after: ink only, pen mode never left (" .. t.ink .. " updates, no driver call)")
end, after = 2 })
add({ fn = function(E)
    -- a pause: Undo woke up after the first stroke; shown now, with pen mode off first
    local t = tally()
    check(t.other >= 1 and t.other_on == 0 and driver[#driver] == "off" and PM.on == false,
        "a pause in the writing: what the strokes left (Undo waking up) shown now, pen mode off first (" .. table.concat(t.names, ",") .. "; ["
            .. table.concat(driver, ",") .. "]), never an ordinary update with pen mode on")
    reset()
    -- the highlighter: black points while drawing (ink), its grey at the pause (an ordinary update)
    E.penTap(button("highlighter"))
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    if d.flyout then E.penTap(button("highlighter")) end
end, after = 2 })
add({ fn = function(E) reset(); line(E, 0.5, 0.3, 0.7) end, after = 0.25 })
add({ fn = function(E)
    local t = tally()
    E.hl_ink, E.hl_other = t.ink, t.other
    check(t.ink >= 2 and t.ink_off == 0 and t.other_on == 0, "the highlighter: its points as ink in pen mode while it's drawn (" .. t.ink .. " updates)")
end, after = 2 })
add({ shot = "1-after-pause", after = 0.3 })
add({ fn = function(E)
    local t = tally()
    check(t.other > E.hl_other and t.other_on == 0 and PM.on == false, "…its real grey at the pause, as an ordinary update with pen mode off (" .. table.concat(t.names, ",") .. ")")
    reset()
    -- a stroke, then the toolbar tapped at once: pen mode off (after the ink's time), then the toolbar's update
    line(E, 0.6, 0.3, 0.7)
    E.penTap(button("eraser"))
end, after = 2 })
add({ fn = function(E)
    local t = tally()
    local saw_sleep = false
    for _i, c in ipairs(driver) do if c:match("^sleep") then saw_sleep = true end end
    check(screen().tool == "eraser" and t.ink >= 2 and t.ink_off == 0 and t.other >= 1 and t.other_on == 0 and saw_sleep,
        "the toolbar tapped right after a stroke: the ink's time waited out, pen mode off, then the toolbar's update [" .. table.concat(driver, ",") .. "]")
    -- the eraser across the last line: its place shown as ink is, in pen mode, not as an ordinary update
    E.erase_before = #screen().sketch:live()
    reset()
    local pts = {}
    for i = 0, 6 do local p = pt(0.5, 0.56 + 0.01 * i); p[3] = 2000; pts[#pts + 1] = p end
    E.pen(pts, 0.3)
end, after = 0.3 })
add({ fn = function(E)
    local t = tally()
    local d = screen()
    check(#d.sketch:live() == E.erase_before - 1 and t.ink >= 1 and t.ink_off == 0 and t.big == 0 and t.other == 0 and PM.on == true,
        "the eraser: the line rubbed out, its place shown in " .. t.ink .. " small updates in pen mode, no ordinary update ("
            .. t.other .. "), pen mode still on [" .. table.concat(driver, ",") .. "]")
    -- turned off by hand (⋮ More → Fast ink): ink the ordinary way
    E.penTap(button("more"))
end, after = 2 })
add({ fn = function(E)
    check(button("penmode") ~= nil, "⋮ More: Fast ink (Kindle pen mode), a switch")
    E.penTap(button("penmode"))
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    check(d.pen_fast == false and G_reader_settings:isFalse(PM.SETTING) and PM.hooked == nil, "…tapped: off, kept for next time, the screen no longer watched")
    if d.flyout then E.penTap(button("more")) end
end, after = 2 })
add({ fn = function(E) E.penTap(button("pen")) end, after = 2 })
add({ fn = function(E)
    local d = screen()
    if d.flyout then E.penTap(button("pen")) end
end, after = 2 })
add({ fn = function(E) reset(); line(E, 0.7, 0.3, 0.7) end, after = 2 })
add({ fn = function(E)
    local t = tally()
    check(t.ink == 0 and #driver == 0 and t.other >= 1, "a stroke with it off: no pen mode, ink shown the ordinary way as before (" .. t.other .. " updates)")
    G_reader_settings:delSetting(PM.SETTING)
    local f = io.open(E.out .. "/pen-mode-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
