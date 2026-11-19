-- The journal's mood slider dragged with a finger: the dot follows the
-- finger while it's down (each step shown as it's reached), and where it's
-- let go is the mood, the dot there.
--   python3 -I demo/mock_memos.py 18090 --sample --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh mood_drag.lua <out>
-- Checks go to <out>/mood-drag-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function journal() for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_journal" then return w.widget end end end
local function mid(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function jb(id) local b = journal() and journal().buttons[id]; return b and b.dimen and mid(b.dimen) end
local refreshes = {}

add({ fn = function(_E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    require("gzreader_notes").journal(p)
end, after = 5 })
add({ fn = function(E)
    -- (each refresh of the screen asked for: its kind)
    local U = UIM()
    local o = U._refresh
    U._refresh = function(self, mode, region, ...)
        if mode then refreshes[#refreshes + 1] = mode end
        return o(self, mode, region, ...)
    end
    local a, b = jb("mood-2"), jb("mood-5")
    E.fingerDown(a[1], a[2])
    for i = 1, 6 do E.fingerMove(a[1] + (b[1] - a[1]) * i / 6, a[2], 0.15 * i) end
end, after = 2.5 })
add({ shot = "1-dragging", after = 0 })
add({ fn = function(E)
    local j = journal()
    local sl = j.mood_slider
    check(sl and sl.dragging == 5, "the finger down on the slider, moved to the 5th step: the dot there (" .. tostring(sl and sl.dragging) .. ")")
    check(j.state.valence == nil, "…the mood not chosen yet (the finger's still down)")
    local n = #refreshes
    check(n >= 2, "…the dot shown as it moved (" .. n .. " refreshes: " .. table.concat(refreshes, ",") .. ")")
    local fast = 0
    for _i, k in ipairs(refreshes) do if k == "fast" or k == "a2" then fast = fast + 1 end end
    check(fast == 0, "…in grey (no black-and-white-only refreshes, which lose the slider's greys)")
    E.fingerUp()
end, after = 3 })
add({ shot = "2-let-go", after = 0 })
add({ fn = function(E)
    local j = journal()
    check(j.state.valence == "slightly-pleasant", "let go: Slightly pleasant (" .. tostring(j.state.valence) .. ")")
    local sl = j.mood_slider
    check(sl and not sl.dragging and sl.thumb_at == 5, "…the dot on the 5th step (" .. tostring(sl and sl.thumb_at) .. ")")
    local f = io.open(E.out .. "/mood-drag-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
