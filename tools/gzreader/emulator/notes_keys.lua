-- The Notes tab on Kindles without a touch screen. On a keyboard Kindle
-- (the default, a Kindle 3) every function has a key: N new note, J journal,
-- K search, G tags, D drawings, A all, F filter, L layout, S sort, M
-- connection, and H lists them (Z X C V B switch the bottom tabs). The journal screen works with the 5-way
-- and with keys (1–7 the step, T, F, I, A, G, P, W, S). A note's drawings
-- are shown, every page, but can't be made or changed: no New sheet, and
-- Edit opens the note's text. On a Kindle 4 (GZ_EMU_MODEL=k4: no letters)
-- Menu reaches the same list and the 5-way works the journal.
--   python3 -I demo/mock_memos.py 18090 --sample --drawings --journal &
--   GZ_EMU_TREE=<tree>/koreader run.sh notes_keys.lua <out>          (Kindle 3)
--   GZ_EMU_MODEL=k4 GZ_EMU_TREE=<tree>/koreader run.sh notes_keys.lua <out>
-- Checks go to <out>/notes-keys-checks.txt.
local MODEL = os.getenv("GZ_EMU_MODEL") or "k3"
local K4 = MODEL == "k4"
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function N() return require("gzreader_notes") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function named(name)
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == name then return w.widget end end
end
local function journal() return named("gz_journal") end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function shot(name) add({ shot = name, after = 0.5 }) end
local function rowTexts(d)
    local t = {}
    for _i, row in ipairs(d and d.buttons or {}) do t[#t + 1] = row[1].text end
    return table.concat(t, "|")
end
local function state()
    local http = require("socket.http")
    return require("json").decode((http.request("http://127.0.0.1:18090/__state")))
end

add({ fn = function()
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    N().show(p)
end, after = 9 })
shot("01-board")
add({ fn = function()
    local Touch = require("gzreader_touch")
    check(top() == N().board and not Touch.on() and N().canDraw(plugin()) == false,
        "the board on a Kindle without a touch screen: drawings can't be made here")
    local tb = N().board.title_bar
    check(tb._gz_action_rows == nil, "…no buttons to tap: keys instead")
end, after = 1 })
key(K4 and "Menu" or "H", 3)
shot("02-menu")
add({ fn = function(E)
    local d = top()
    local texts = rowTexts(d)
    E.say("menu:", texts)
    check(texts:find("New note", 1, true) and texts:find("Journal entry", 1, true) and texts:find("Search", 1, true) and texts:find("Tags", 1, true)
        and texts:find("Only notes with drawings", 1, true) and texts:find("Filter", 1, true) and texts:find("Connection", 1, true)
        and not texts:find("New sheet", 1, true),
        "Menu (H on a keyboard): New note, Journal entry, Search, Tags, Only notes with drawings, Filter… (no New sheet): " .. texts)
    if not K4 then check(texts:find("(J)", 1, true) and texts:find("(K)", 1, true) and texts:find("(D)", 1, true), "…each with its key") end
    UIM():close(d)
end, after = 3 })

if not K4 then
    -- D: only the notes with drawings; A: all again
    key("D", 5)
    shot("03-drawings-only")
    add({ fn = function()
        local n = #N().visible()
        check(N().filter.kind == "drawings" and n == 1 and N().title():match("Drawings"), "D: only the notes with drawings (" .. n .. ")")
    end, after = 1 })
    key("A", 5)
    add({ fn = function() check(N().filter.kind == "all" and #N().visible() > 3, "A: all the notes again") end, after = 1 })
    key("G", 4)
    shot("04-tags")
    add({ fn = function()
        local t = top()
        check(t ~= N().board and t.item_table and t.item_table[1] and tostring(t.item_table[1].text):match("^#"), "G: your tags, to pick one")
        UIM():close(t)
    end, after = 3 })
    key("K", 4)
    shot("05-search")
    add({ fn = function()
        local t = top()
        check(t and t.getInputText ~= nil, "K: search")
        for _i, w in ipairs(UIM()._window_stack) do if w.widget.getInputText then w.widget:addTextToInput("ghosts") end end
    end, after = 2 })
    add({ fn = function()
        for _i, w in ipairs(UIM()._window_stack) do
            if w.widget.getInputText then
                local q = w.widget:getInputText()
                UIM():close(w.widget)
                N().setFilter(plugin(), { kind = "search", value = q })
            end
        end
    end, after = 5 })
    add({ fn = function()
        check(N().filter.kind == "search" and #N().visible() == 1, "…the notes with the words (" .. #N().visible() .. ")")
        N().setFilter(plugin(), { kind = "all" })
    end, after = 5 })
end

-- the note with two sheets: shown, every page; Edit opens its text only
add({ fn = function(E)
    local memo
    for _i, m in ipairs(N().notes or {}) do if tostring(m.content):match("Shelf sketch") then memo = m end end
    check(memo ~= nil and #N().drawings(memo) == 2, "a note with two sheets (drawn on a touch Kindle)")
    E.memo = memo
    N().showNote(plugin(), memo)
end, after = 8 })
shot("06-note-with-sheets")
add({ fn = function(E)
    local v = top()
    check(v and v.memo == E.memo and #v.picks == 2 and v.picks[1].att and v.picks[2].att, "its page shows both sheets (each can be opened full screen)")
    E.say("picks:", #v.picks)
    v:pickIndex(2)
end, after = 5 })
shot("07-sheet-full-screen")
add({ fn = function(E)
    local t = top()
    check(t ~= nil and t.memo == nil and t.image ~= nil or (t and t.fullscreen), "a sheet opened: the picture, full screen")
    UIM():close(t)
end, after = 3 })
add({ fn = function(E)
    local v = top()
    v:onEdit()
end, after = 6 })
shot("08-edit-is-text")
add({ fn = function(E)
    local ed, draw
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.on_save and w.widget.input then ed = w.widget end
        if w.widget.name == "gz_drawscreen" then draw = w.widget end
    end
    check(ed ~= nil and draw == nil and ed:canDraw() == false and #ed:sheets() == 2 and not ed.rich,
        "Edit: the note's text (Markdown), not the drawing screen; its sheets stay as they are")
    ed.input:addChars(" Measured twice.")
end, after = 2 })
add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.on_save and w.widget.input then w.widget:save() end end
end, after = 8 })
add({ fn = function(E)
    local m
    for _i, x in ipairs(state().memos) do if x.content:match("Shelf sketch") then m = x end end
    check(m and m.content:match("Measured twice%.") and #m.attachments == 2, "Save: the text changed in Memos, both sheets still on the note")
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.memo and w.widget.picks then UIM():close(w.widget) end end
end, after = 4 })

-- the journal: keys (keyboard) or the 5-way (Kindle 4)
if K4 then
    key("Menu", 3)
    add({ fn = function(E)
        local d = top()
        for _i, row in ipairs(d.buttons or {}) do if row[1].text:match("^Journal entry") then row[1].callback() end end
    end, after = 5 })
else
    key("J", 5)
end
shot("09-journal")
add({ fn = function()
    local j = journal()
    check(j and top() == j, "the journal screen")
    local f = j and j:getFocusItem()
    check(f and f.gz_id == "mood-4", "the 5-way starts on the middle step (" .. tostring(f and f.gz_id) .. ")")
end, after = 1 })
key("Right", 2)
key("Right", 2)
key("Press", 3)
shot("10-journal-step")
add({ fn = function()
    local j = journal()
    local f = j:getFocusItem()
    check(j.state.valence == "pleasant" and f and f.gz_id == "mood-6", "▶ ▶ Press: Pleasant chosen, the 5-way still on it (" .. tostring(f and f.gz_id) .. ")")
end, after = 1 })
key("Down", 2)
key("Press", 3)
add({ fn = function()
    local j = journal()
    check(#j.state.feelings == 1, "▼ Press: a feeling word chosen (" .. tostring(j.state.feelings[1]) .. ")")
end, after = 1 })
if not K4 then
    key("T", 3)
    add({ fn = function() check(journal().state.kind == "now", "T: right now") end, after = 1 })
    add({ combo = { "Alt", "W" }, after = 3 })
    add({ fn = function() check(journal().state.valence == "unpleasant", "Alt+W (2 on the Kindle Keyboard): the second step") end, after = 1 })
    add({ combo = { "Alt", "Y" }, after = 3 })
    add({ fn = function() check(journal().state.valence == "pleasant", "Alt+Y (6 on the Kindle Keyboard): the sixth") end, after = 1 })
    key("P", 3)
    key("A", 3)
    shot("11-journal-activities")
    add({ fn = function(E)
        local j = journal()
        check(j.picker ~= nil and top() == j.picker, "A: your activities, to tick")
        for _i, row in ipairs(j.picker.buttons) do for _k, b in ipairs(row) do if b.text == "Reading" then b.callback() end end end
    end, after = 3 })
    add({ fn = function(E)
        local j = journal()
        for _i, row in ipairs(j.picker.buttons) do for _k, b in ipairs(row) do if b.text == "Done" then b.callback() end end end
    end, after = 3 })
    add({ fn = function() check(journal().state.activities[1] == "reading", "…Reading ticked") end, after = 1 })
    shot("12-journal-ready")
    key("S", 8)
else
    add({ fn = function() journal():save() end, after = 8 })
end
shot("13-saved")
add({ fn = function(E)
    local found
    for _i, m in ipairs(state().memos) do if m.content:match("#mood/pleasant") then found = m end end
    check(not journal() and found ~= nil and found.visibility == "PRIVATE", "saved: Memos has the entry (" .. tostring(found and found.content:gsub("\n", "\\n")) .. ")")
    local f = io.open(E.out .. "/notes-keys-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
