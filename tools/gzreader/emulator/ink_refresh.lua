-- How fresh ink is put on the e-ink screen (gzreader_drawscreen.lua's
-- inkRefresh): on a blank page A2 (the quickest); on a page with a paper
-- (or any picture) under it, DU ("fast"), and the stroke's area cleaned up
-- with "ui" once it's done. A2 from a grey pixel left the ink light where a
-- stroke crossed a ruled line (the owner's Scribe, 2026-11-16).
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh ink_refresh.lua <out>
-- (no Memos needed: the drawing screen is opened on its own). Checks go to
-- <out>/ink-refresh-checks.txt.
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local PEN = MODEL == "scribe"
local W, H
local function pt(fx, fy) return { math.floor(W * fx), math.floor(H * fy) } end
local function wave(fx0, fy, fx1)
    local out = {}
    for i = 0, 12 do out[#out + 1] = pt(fx0 + (fx1 - fx0) * i / 12, fy + 0.03 * math.sin(i / 2)) end
    return out
end
local function screen()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then return w.widget end end
end
local modes = {}
local function record()
    local U = UIM()
    if U._gz_ink_rec then return end
    U._gz_ink_rec = true
    local orig = U.setDirty
    U.setDirty = function(self, widget, mode, region)
        if widget == nil and type(mode) == "string" and region then modes[#modes + 1] = mode end
        return orig(self, widget, mode, region)
    end
end
local function seen(m) for _i, x in ipairs(modes) do if x == m then return true end end return false end
local function draw(E, fy)
    local pts = wave(0.25, fy, 0.75)
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end

add({ fn = function(E)
    local Device = require("device")
    W, H = Device.screen:getWidth(), Device.screen:getHeight()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    record()
    require("gzreader_drawscreen").show{ title = "Ink", on_done = function() end, on_cancel = function() end }
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    check(d ~= nil and d.sketch:paper() == "blank", "the drawing screen, a blank page")
    modes = {}
    draw(E, 0.3)
end, after = 3 })
add({ fn = function(E)
    check(#screen().sketch:live() == 1 and seen("a2") and not seen("fast"),
        "a blank page: ink put on with A2, the quickest (" .. table.concat(modes, ",") .. ")")
    local d = screen()
    d.sketch:setPaper("college")
    d:redrawAll()
end, after = 3 })
add({ shot = "1-college", after = 0.5 })
add({ fn = function(E)
    check(screen().sketch:paper() == "college", "College ruled paper under the page")
    modes = {}
    draw(E, 0.55)
end, after = 3 })
add({ shot = "2-ink-over-lines", after = 0.5 })
add({ fn = function(E)
    local d = screen()
    local last
    for i = #modes, 1, -1 do if modes[i] ~= "fast" then last = modes[i]; break end end
    check(#d.sketch:live() == 2 and seen("fast") and not seen("a2"),
        "on ruled paper: ink put on with DU (\"fast\": any grey to black), never A2 (" .. table.concat(modes, ",") .. ")")
    check(last == "ui", "…and the stroke's area cleaned up once it's done (\"ui\")")
    -- a grey tool (the pencil) on a blank page: greys need a refresh that shows them ("ui")
    if d.setWriting then
        d.sketch:setPaper("blank")
        d:redrawAll()
        d:setWriting("pencil")
        modes = {}
        draw(E, 0.75)
    end
end, after = 3 })
add({ fn = function(E)
    local d = screen()
    if d.setWriting then
        check(#modes > 0 and seen("ui") and not seen("a2") and not seen("fast"),
            "the pencil on a blank page: its grey ink refreshed with \"ui\" (A2 showed it white) (" .. table.concat(modes, ",") .. ")")
    end
    local f = io.open(E.out .. "/ink-refresh-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
