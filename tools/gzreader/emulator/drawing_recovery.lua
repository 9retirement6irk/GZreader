-- A drawing that was never saved comes back (gzreader_drawdraft): a journal
-- entry's mood, words and pencil drawing; a pause in the drawing keeps it;
-- GZreader then stops without a Save (its screens just gone, as when it hung
-- and was restarted); at the next start it asks, and Open it brings the entry
-- back with its drawing on the screen, to go on with and save.
--   python3 -I demo/mock_memos.py 18090 --sample --journal &
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh drawing_recovery.lua <out>
-- (GZ_EMU_MODEL=scribe too: drawn with the pen.)
-- Checks go to <out>/drawing-recovery-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local PEN = (os.getenv("GZ_EMU_MODEL") or "pw3") == "scribe"
local function find(name) for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end end
local function journal() return find("gz_journal") end
local function screen() return find("gz_drawscreen") end
local function centre(d) return { d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) } end
local function Draft() return require("gzreader_drawdraft") end
local function stroke(E, fy)
    local d = screen()
    local p = d.pane
    local x, y, w, h = p.x + math.floor(p.w * 0.2), p.y + d.top_h + 40, math.floor(p.w * 0.6), p.h - d.top_h - 80
    local pts = {}
    for i = 0, 10 do pts[#pts + 1] = { x + math.floor(w * (0.1 + 0.08 * i)), y + math.floor(h * fy + 15 * math.sin(i)) } end
    if PEN then E.pen(pts, 0.4) else E.finger(pts, 0.4) end
end
local kept_id
local WORDS = "Speaking of work " .. os.time() -- (this run's entry: the mock Memos keeps earlier runs')

add({ fn = function(_E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    for _i, id in ipairs(Draft().list()) do Draft().clear(id, "tour") end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will", queue = {} }
    require("gzreader_notes").journal(p)
end, after = 3 })
add({ fn = function(E)
    local j = journal()
    j:setValence("slightly-pleasant")
    j.state.body = WORDS
    j:rebuild()
end, after = 2 })
add({ fn = function(E) E.tap(centre(journal().draw_chip.dimen)) end, after = 5 })
add({ fn = function(E) stroke(E, 0.25); if PEN then E.penAway(0.6) end end, after = 2 })
add({ fn = function(E) stroke(E, 0.45); if PEN then E.penAway(0.6) end end, after = 1 })
add({ fn = function(_E)
    local ids = Draft().list()
    check(#ids == 0, "drawing: nothing kept while the pen's still going (" .. #ids .. ")")
end, after = 8 }) -- (kept in a background process: a moment more)
add({ fn = function(E)
    local ids = Draft().list()
    kept_id = ids[1]
    local rec, why = nil, nil
    if kept_id then rec, why = Draft().read(kept_id) end
    E.say("read", tostring(kept_id), tostring(rec), tostring(why))
    local Drawing = require("gzreader_drawing")
    check(#ids == 1 and rec and rec.kind == "journal" and #Drawing.liveElements(rec.pages[1]) >= 3,
        "a pause of " .. Draft().PAUSE .. " s: the drawing kept, with the journal entry (" .. #ids .. " file, "
            .. tostring(rec and #Drawing.liveElements(rec.pages[1])) .. " elements: the lines and the 2 strokes)")
    check(rec and rec.journal.state.valence == "slightly-pleasant" and rec.journal.state.body == WORDS,
        "…its mood and words with it")
    -- GZreader stops here without a Save (it hung and was restarted): its screens just gone
    local d, j = screen(), journal()
    d.on_done, d.on_cancel = nil, nil
    UIM():close(d)
    j.drawing_open = nil
    UIM():close(j)
    Draft().asked = false
    Draft().check(plugin())
end, after = 3 })
add({ shot = "1-asked", after = 0.5 })
add({ fn = function(E)
    local dlg = Draft().dialog
    local title = dlg and dlg.title or ""
    check(title:find("journal entry's drawing", 1, true) ~= nil and title:find("1 page", 1, true) ~= nil,
        "the next start: asked about it (" .. title .. ")")
    local open = E.findText("Open it")
    check(open ~= nil and E.findText("Later") ~= nil and E.findText("Delete it") ~= nil, "…Open it, Later, Delete it")
    if open then E.tap(centre(open)) end
end, after = 6 })
add({ shot = "2-opened", after = 0.5 })
add({ fn = function(E)
    local j, d = journal(), screen()
    check(j and j.state.valence == "slightly-pleasant" and j.state.body == WORDS and j.draft_id == kept_id,
        "Open it: the journal entry again, its mood and words (" .. tostring(j and j.state.valence) .. ", "
            .. tostring(j and j.state.body) .. ", " .. tostring(j and j.draft_id == kept_id) .. ")")
    check(d and d.journal and #d.sketch:live() == 2, "…its drawing on the screen, the 2 strokes, to go on with (" .. tostring(d and #d.sketch:live()) .. ")")
    stroke(E, 0.65)
    if PEN then E.penAway(0.6) end
end, after = 2 })
add({ fn = function(E)
    local d = screen()
    local save
    for _i, b in ipairs(d.buttons) do
        if b.tool.id == "done" then save = { b.rect.x + d.ox + math.floor(b.rect.w / 2), b.rect.y + d.oy + math.floor(b.rect.h / 2) } end
    end
    if PEN then E.penTap(save) else E.tap(save) end
end, after = 6 })
add({ fn = function(_E)
    local q = plugin().store.memos.queue or {}
    local last = q[#q]
    local queued = last and last.op == "create" and (last.content or ""):find(WORDS, 1, true) and last.drawings and #last.drawings == 1
    local h = io.popen("curl -s http://127.0.0.1:18090/__state")
    local st = require("json").decode(h:read("*a") or "{}") or {}
    h:close()
    local sent = false
    for _i, m in ipairs(st.memos or {}) do
        if tostring(m.content):find(WORDS, 1, true) and #(m.attachments or {}) == 1 then sent = true end
    end
    check(journal() == nil and (queued or sent), "Save: the entry saved, its words and its drawing (" .. (sent and "in Memos" or "queued") .. ")")
    check(#Draft().list() == 0, "…and the kept copy crossed off")
end, after = 1 })
add({ fn = function(E)
    local f = io.open(E.out .. "/drawing-recovery-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
