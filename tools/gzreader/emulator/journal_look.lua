-- A journal entry on a touch Kindle, looking as the owner's Memos fork's web
-- journal does: a face beside a slider of the seven steps (Overall today /
-- Right now above it), chips that fill black when chosen (feelings, what's
-- behind it), activities with their icons. Picks a step on the slider, a
-- feeling, a cause and an activity, and saves.
--   python3 -I demo/mock_memos.py 18090 --sample --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh journal_look.lua <out>
-- Checks go to <out>/journal-look-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function journal() for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_journal" then return w.widget end end end
local function mid(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function jb(id) local b = journal() and journal().buttons[id]; return b and b.dimen and mid(b.dimen) end
local MODEL = os.getenv("GZ_EMU_MODEL") or "pw3"
local function tap(E, p) if MODEL == "scribe" then E.penTap(p) else E.tap(p) end end

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    local Notes = require("gzreader_notes")
    Notes.journal(p)
end, after = 5 })
add({ shot = "1-not-chosen", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(j ~= nil and j.inline, "the journal, touch: the web's look")
    check(j.buttons["mood-1"] and j.buttons["mood-7"] and j.buttons["kind-today"].gz_on, "the slider's seven steps; Overall today chosen")
    local fw
    local function walk(w)
        if type(w) ~= "table" or fw then return end
        if w.valence and w.size and w.faded ~= nil then fw = w; return end
        for _i, k in ipairs(w) do walk(k) end
    end
    walk(j[1])
    check(fw and fw.faded and fw.valence == "neutral", "a faded neutral face before a step is chosen")
    check(j.buttons["did-work"] and j.buttons["did-reading"], "the activities as chips")
    tap(E, jb("mood-6"))
end, after = 3 })
add({ fn = function(E)
    local j = journal()
    check(j.state.valence == "pleasant", "a tap on the slider's 6th step: Pleasant")
    check(j.buttons["felt-grateful"] or j.buttons["felt-happy"], "the feelings nearest it, as chips")
    check(j.buttons["mood-clear"] ~= nil, "Clear beside the step's name")
    local f = j.buttons["felt-grateful"] and "felt-grateful" or "felt-happy"
    E.say("feeling", f)
    tap(E, jb(f))
end, after = 3 })
add({ fn = function(E)
    local first
    for id, b in pairs(journal().buttons) do if id:match("^impact%-") and not first then first = id end end
    E.say("cause", first)
    if first then tap(E, jb(first)) end
end, after = 3 })
add({ fn = function(E) tap(E, jb("did-reading")) end, after = 3 })
add({ shot = "2-chosen", after = 0.5 })
add({ fn = function(E)
    local j = journal()
    check(#j.state.feelings == 1 and #j.state.impacts == 1, "a feeling and a cause chosen")
    check(j.buttons["did-reading"].gz_on and j.buttons["did-reading"].background == require("ffi/blitbuffer").COLOR_BLACK,
        "Reading chosen: its chip filled black")
    -- a drag along the slider: Very unpleasant
    local a, b = j.buttons["mood-6"].dimen, j.buttons["mood-1"].dimen
    E.finger({ mid(a), { math.floor((a.x + b.x) / 2), mid(a)[2] }, mid(b) }, 1.2)
end, after = 3 })
add({ shot = "3-dragged", after = 0.5 })
add({ fn = function(E)
    check(journal().state.valence == "very-unpleasant", "dragged along the slider to its start: Very unpleasant")
    tap(E, jb("mood-6"))
end, after = 3 })
add({ fn = function(E) journal():save() end, after = 6 })
add({ fn = function(E)
    local Memos = require("gzreader_memos")
    local c = Memos:new(plugin().store.memos)
    local page = c:list()
    local found
    for _i, m in ipairs(page and page.memos or {}) do if (m.content or ""):match("#mood/pleasant") then found = m end end
    check(found and found.content:match("#did/reading") and found.content:match("#felt/"), "saved: the mood, feeling and activity as tags")
    E.found = found
    local Notes = require("gzreader_notes")
    if found then Notes.showNote(plugin(), found) end
end, after = 4 })
add({ shot = "4-entry", after = 0.5 })
add({ fn = function(E)
    local v
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.memo and w.widget.picks then v = w.widget end end
    local face, chips = nil, 0
    local function walk(w)
        if type(w) ~= "table" then return end
        if w.valence and w.size and w.faded ~= nil then face = face or w end
        if w.background and w.radius and w[1] and w[1].text and tostring(w[1].text):match("^#") then chips = chips + 1 end
        for _i, k in ipairs(w) do walk(k) end
    end
    walk(v and v[1])
    check(face and face.valence == "pleasant", "the entry's page: its mood's face beside the time (" .. tostring(face and face.valence) .. ")")
    check(chips >= 4, "…its tags as grey chips (" .. chips .. ")")
    local f = io.open(E.out .. "/journal-look-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
