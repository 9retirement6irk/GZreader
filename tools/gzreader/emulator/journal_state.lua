-- A journal entry's page with the state of mind panel at its foot, as the
-- owner's Memos fork shows it: the mood (face, Overall today, the step's
-- name, the seven steps), Feelings, Because of (with icons) and Did (tiles);
-- the line of journal tags left out, other tags where they are. A tap on a
-- feeling shows the notes with that tag. Then the same page on a colour
-- screen (the fork's colours on the scale).
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh journal_state.lua <out>
-- Checks go to <out>/journal-state-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local note
local CONTENT = "## A slow, good Thursday\n\nLong walk after lunch while the sun was out, then two chapters on the sofa. "
    .. "Called Sam in the evening. #camping\n\n#mood/pleasant #mood/today #felt/grateful #felt/calm #felt/content "
    .. "#impact/friends #impact/weather #did/exercise #did/reading #did/friends\n"
local function find(test) for _i, w in ipairs(UIM()._window_stack) do if test(w.widget) then return w.widget end end end
local function view() return find(function(w) return w.memo and w.picks end) end
local function texts(w, out)
    out = out or {}
    if type(w) ~= "table" then return out end
    if type(w.text) == "string" and (w.face or w.charlist) then out[#out + 1] = w.text end
    for _i, k in ipairs(w) do texts(k, out) end
    return out
end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    note = require("gzreader_memos"):new(p.store.memos):create(CONTENT, "PRIVATE")
    check(note ~= nil, "a journal entry in Memos")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function()
    local Notes = require("gzreader_notes")
    local m
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then m = n end end
    check(m ~= nil, "the entry is on the board")
    Notes.showNote(plugin(), m)
end, after = 6 })
add({ shot = "1-entry-grey", after = 1 })
add({ fn = function(E)
    local v = view()
    local t = table.concat(texts(v[1]), "|")
    E.say("page texts", t)
    -- (the paragraphs are drawn by gzreader_inline.lua, whose words this walk doesn't read)
    local head, mood = t:find("A slow, good Thursday", 1, true), t:find("Overall today", 1, true)
    check(head and mood and head < mood and t:find("Pleasant", 1, true) and t:find("+2", 1, true) and t:find("\u{2212}3", 1, true),
        "the panel after the text: Overall today, Pleasant, the steps −3 … +3")
    check(t:find("Feelings", 1, true) and t:find("Grateful", 1, true) and t:find("Because of", 1, true) and t:find("Weather", 1, true)
        and t:find("Did", 1, true) and t:find("Reading", 1, true),
        "Feelings, Because of and Did with their words")
    check(not t:find("#felt/", 1, true) and not t:find("#mood/", 1, true) and not t:find("#did/", 1, true),
        "the journal's tag line left out (not drawn as chips)")
    local calm
    for i, pk in ipairs(v.picks or {}) do if pk.tag == "felt/calm" then calm = i end end
    check(calm ~= nil, "each item can be tapped (its tag)")
    E.calm = calm
end, after = 1 })
add({ fn = function(E)
    -- the same page on a colour screen
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local was = Screen.isColorEnabled
    Screen.isColorEnabled = function() return true end
    local v = view()
    v:build()
    local out = Blitbuffer.new(Screen:getWidth(), Screen:getHeight(), Blitbuffer.TYPE_BBRGB32)
    out:fill(Blitbuffer.COLOR_WHITE)
    v[1]:paintTo(out, 0, 0)
    local n = 0
    for y = 0, out:getHeight() - 1, 3 do
        for x = 0, out:getWidth() - 1, 3 do
            local c = out:getPixel(x, y):getColorRGB32()
            if math.abs(c.r - c.g) > 12 or math.abs(c.g - c.b) > 12 then n = n + 1 end
        end
    end
    out:writePNG(E.out .. "/2-entry-colour.png")
    out:free()
    Screen.isColorEnabled = was
    v:build()
    E.say("colour screen: coloured pixels sampled:", tostring(n))
    check(n > 200, "colour screen: the scale and the face in colour (" .. n .. " coloured pixels sampled)")
end, after = 2 })
add({ fn = function(E)
    view():pickIndex(E.calm)
end, after = 4 })
add({ shot = "3-board-felt-calm", after = 1 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    check(view() == nil and Notes.filter and Notes.filter.kind == "tag" and Notes.filter.value == "felt/calm",
        "a tap on Calm: the page closes, the board shows the notes tagged #felt/calm")
    local f = io.open(E.out .. "/journal-state-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
    E.say(table.concat(lines, "\n"))
end, after = 1 })
return s
