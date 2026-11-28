-- A note with a <details> section (the fork's "Text from …" blocks), as
-- Memos' web app shows it: on the note's page a row with a chevron and the
-- section's title, folded until tapped, its code in a grey box; a journal
-- entry's mood, feeling and activity tags as the state of mind panel after
-- the text (journal_state.lua); in the note editor (the formatted page) the same row, the chevron
-- opening and folding it, what's in it indented. Save leaves the note as it was.
--   python3 -I demo/mock_memos.py 18090 &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh notes_details.lua <out>
-- Checks go to <out>/notes-details-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local note, c
local CONTENT = "## Tuesday, November 17, 2026\n\n#mood/neutral #mood/today #felt/drained #did/work\n\n"
    .. "<details>\n<summary>Text from drawing-20261117-185526.canvas.png</summary>\n\n"
    .. "```text\nWork took most of my energy this week.\n\nGrateful for a quiet evening.\n```\n\n</details>\n\n"
    .. "Later: a walk by the river. #outside\n\n#errands #home\n"
local function find(test) for _i, w in ipairs(UIM()._window_stack) do if test(w.widget) then return w.widget end end end
local function view() return find(function(w) return w.memo and w.picks end) end
local function editor() return find(function(w) return w.rich_input end) end
local function sectionLine(r, b) for _i, l in ipairs(r.lines) do if l.section and l.section.start and (not b or l.b == b) then return l end end end
local function onScreen(r, x, y) return { r.dimen.x + x, r.dimen.y + y } end
-- the texts on the note's page, in order
local function texts(w, out)
    out = out or {}
    if type(w) ~= "table" then return out end
    if type(w.text) == "string" and (w.face or w.charlist) then out[#out + 1] = w.text end
    for _i, k in ipairs(w) do texts(k, out) end
    return out
end

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    c = require("gzreader_memos"):new(p.store.memos)
    note = c:create(CONTENT, "PRIVATE")
    check(note ~= nil, "a journal entry with a <details> section in Memos")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    local m
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then m = n end end
    check(m ~= nil, "the note is on the board")
    Notes.showNote(plugin(), m)
end, after = 6 })
add({ shot = "1-page-folded", after = 1 })
add({ fn = function(E)
    local v = view()
    local t = table.concat(texts(v[1]), "|")
    E.say("page texts", t)
    local pick
    for i, pk in ipairs(v.picks or {}) do if pk.details then pick = i end end
    check(pick and v.picks[pick].open == false and t:find("Text from drawing-20261117-185526.canvas.png", 1, true)
        and not t:find("Work took most", 1, true) and not t:find("<details>", 1, true) and not t:find("<summary>", 1, true),
        "the note's page: the section a row with its title, folded (no <details> or <summary> shown)")
    local b = t:find("Text from drawing", 1, true)
    local a = t:find("Overall today", 1, true)
    local h = t:find("Tuesday, November 17, 2026", 1, true)
    check(h and a and b and h < b and b < a and not t:find("#mood/neutral", 1, true) and t:find("Drained", 1, true)
        and t:find("#errands", 1, true) and t:find("#home", 1, true),
        "the journal's tags as the state of mind panel after the text (not as chips); other tag lines where they are")
    E.pick = pick
    v:pickIndex(pick)
end, after = 3 })
add({ shot = "2-page-open", after = 1 })
add({ fn = function(E)
    local v = view()
    local t = table.concat(texts(v[1]), "|")
    check(v.picks[E.pick].open == true and t:find("Work took most of my energy this week.\n\nGrateful", 1, true) and t:find("text", 1, true),
        "a tap opens it: its text in a code box, as written")
    v:onEdit()
end, after = 6 })
add({ shot = "3-editor-folded", after = 1 })
add({ fn = function(E)
    local r = editor().rich_input
    local l = sectionLine(r)
    check(l and l.section.folded and l.section.title == "Text from drawing-20261117-185526.canvas.png",
        "the editor: the section a row with a chevron and its title, folded")
    local shown = false
    for _i, x in ipairs(r.lines) do if not x.section and table.concat(x.b.chars):find("Work took", 1, true) then shown = true end end
    check(not shown, "…what's in it not shown")
    if l then E.tap(onScreen(r, l.x0 + 8, l.y - r.top + math.floor(l.h / 2))) end
end, after = 3 })
add({ shot = "4-editor-open", after = 1 })
add({ fn = function(E)
    local e = editor()
    local r = e.rich_input
    local l = sectionLine(r)
    local inner
    for _i, x in ipairs(r.lines) do if not x.section and table.concat(x.b.chars):find("Work took", 1, true) then inner = x end end
    check(l and not l.section.folded and inner and inner.x0 > l.x0, "a tap on the chevron opens it: what's in it shown, indented")
    check(not r:isTextEdited(), "the note unchanged by opening it")
    e:save()
end, after = 6 })
add({ fn = function(E)
    local now = c:get(note.name)
    -- (Memos keeps a note without its last line break)
    local sent = 0
    for _i, q in ipairs(plugin().store.memos.queue or {}) do if q.op == "update" then sent = sent + 1 end end
    check(sent == 0 and now and now.content == CONTENT:gsub("\n$", ""), "Save: nothing changed, nothing sent; the note in Memos as it was")
    local f = io.open(E.out .. "/notes-details-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, x in ipairs(lines) do E.say("check", x) end
end, after = 1 })
return s
