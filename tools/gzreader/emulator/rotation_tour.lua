-- Screen rotation (gzreader_rotation.lua) with the real widgets: the
-- Auto-rotate tile (an accelerometer pretended on pw3), the Notes tab → a note
-- → the note editor turned to landscape the way the accelerometer does it
-- (UIManager:sendEvent of SetRotationMode, to the window in front), what was
-- typed kept, the note and the Notes tab laid out again as each closes; a
-- book turned with Rotate, then Home: still landscape.
--   python3 -I demo/mock_memos.py 18090 --sample &
--   GZ_EMU_MODEL=pw3 GZ_EMU_BOOK=<an epub> GZ_EMU_TREE=<tree>/koreader run.sh rotation_tour.lua <out>
-- Checks go to <out>/rotation-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function Screen() return require("device").screen end
local function plugin() local fm = require("apps/filemanager/filemanager").instance; return fm and fm.gzreader end
local function find(pred)
    local st = UIM()._window_stack
    for i = #st, 1, -1 do local w = st[i].widget; if pred(w) then return w end end
end
local function editor() return find(function(w) return w.on_save and w.input end) end
local function noteview() return find(function(w) return w.memo and w.picks end) end
local function board() return require("gzreader_notes").board end
local function landscape() return Screen():getWidth() > Screen():getHeight() end
local function turn(mode)
    -- what KOReader's input does with an accelerometer event: sent to the window in front
    local Event = require("ui/event")
    UIM():sendEvent(Event:new("SetRotationMode", mode))
end
local note
-- (the emulator's own shots copy the panel's pixels as they're refreshed, which
-- doesn't follow a turned screen on touch models: the screen as you see it instead)
local function view(name)
    return { fn = function(E)
        local BB = require("ffi/blitbuffer")
        local bb = Screen().bb
        local w, h = bb:getWidth(), bb:getHeight()
        local c = BB.new(w, h, BB.TYPE_BBRGB32)
        c:blitFrom(bb, 0, 0, 0, 0, w, h)
        c:writePNG(E.out .. "/" .. name .. ".png")
        c:free()
    end, after = 0.5 }
end

add({ fn = function(E)
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.name == "setup guide" or w.widget.name == "QR code screen" then UIM():close(w.widget) end
    end
    check(G_reader_settings:isTrue("lock_rotation"), "at start: Home and books keep the screen's rotation (lock_rotation ticked once)")
    -- the Rotate tile: as on an Oasis or Scribe
    local Device = require("device")
    Device.hasGSensor = function() return true end
    local Panel = require("gzreader_panel")
    local tile
    for _i, t in ipairs(Panel.controls(plugin())) do if t.id == "rotate" then tile = t end end
    check(tile and tile.on and tile.label == "Rotate" and tile.sub == "Auto", "a Kindle with an accelerometer: Rotate tile, Auto")
    if tile then tile.run() end
    check(G_reader_settings:isTrue("input_ignore_gsensor"), "a tap: Manual")
    for _i, t in ipairs(Panel.controls(plugin())) do if t.id == "rotate" then tile = t end end
    check(tile and tile.sub == "Manual" and tile.side, "…the tile says Manual, the turn on its side")
    if tile then tile.run() end
    check(not G_reader_settings:isTrue("input_ignore_gsensor"), "a tap again: Auto")
    local p = plugin()
    p.store.memos = { server = "http://127.0.0.1:18090", token = "memos-test-token", prefix = "/api/v1", user = "Will" }
    note = require("gzreader_memos"):new(p.store.memos):create("Rotation test\n\n- [ ] one\n- [x] two", "PRIVATE")
    require("gzreader_notes").show(p)
end, after = 6 })
add({ fn = function(E)
    local Notes = require("gzreader_notes")
    for _i, n in ipairs(Notes.notes or {}) do if n.name == note.name then Notes.showNote(plugin(), n) end end
end, after = 3 })
add(view("1-note-portrait"))
add({ fn = function(E)
    local v = noteview()
    check(v and not landscape(), "a note open, portrait")
    turn(1)
end, after = 4 })
add(view("2-note-landscape"))
add({ fn = function(E)
    local v = noteview()
    check(landscape() and v and v.dimen.w == Screen():getWidth() and v.dimen.h == Screen():getHeight(),
        "turned: the note laid out landscape (" .. tostring(v and v.dimen.w) .. " × " .. tostring(v and v.dimen.h) .. ")")
    local fm = require("apps/filemanager/filemanager").instance
    check(fm and fm.dimen.w == Screen():getWidth(), "Home under it turned too")
    v:onEdit()
end, after = 4 })
add({ fn = function(E)
    local e = editor()
    check(e ~= nil, "the note editor open")
    if e and e.rich then
        e.input:addChars(" more")
    elseif e then
        e.input:addChars(" more")
    end
    E.before_text = e and e:text()
    turn(0)
end, after = 4 })
add(view("3-editor-portrait"))
add({ fn = function(E)
    local e = editor()
    check(not landscape() and e and e.dimen.w == Screen():getWidth(), "the editor turned back to portrait")
    check(e and e:text() == E.before_text and E.before_text:find("more", 1, true), "what was typed is still there")
    check(e and e:changed(), "…and it still counts as changed (Back saves it)")
    turn(1)
end, after = 4 })
add(view("4-editor-landscape"))
add({ fn = function(E)
    local e = editor()
    check(landscape() and e and e.dimen.w == Screen():getWidth() and e:text() == E.before_text, "landscape again, the text kept")
    -- close without saving (the dialog's Discard, as a tap would)
    UIM():close(e, "full")
end, after = 4 })
add(view("5-note-after-editor"))
add({ fn = function(E)
    local v = noteview()
    check(v and v.dimen.w == Screen():getWidth(), "the note under it already landscape")
    turn(0)
end, after = 4 })
add({ fn = function(E)
    local v = noteview()
    check(v and v.dimen.w == Screen():getWidth() and not landscape(), "the note turned to portrait")
    turn(1)
end, after = 4 })
add({ fn = function(E)
    local v = noteview()
    if v then v:onClose() end
end, after = 5 })
add(view("6-notes-tab-landscape"))
add({ fn = function(E)
    local b = board()
    check(b and b.dimen and b.dimen.w == Screen():getWidth() and b.dimen.h == Screen():getHeight(),
        "the Notes tab laid out landscape when the note closed (" .. tostring(b and b.dimen and b.dimen.w) .. ")")
    -- a book turned, then Home
    local book = os.getenv("GZ_EMU_BOOK")
    if b then UIM():close(b) end
    E.landscape_before_book = landscape()
    if book then require("apps/reader/readerui"):showReader(book) end
end, after = 10 })
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    check(R ~= nil and landscape(), "a book opened from a landscape Home: landscape")
    if R then R:handleEvent(require("ui/event"):new("SetRotationMode", 0)) end
end, after = 5 })
add({ fn = function(E)
    check(not landscape(), "the book turned to portrait (Rotate)")
    local R = require("apps/reader/readerui").instance
    if R then R:handleEvent(require("ui/event"):new("SetRotationMode", 1)) end
end, after = 5 })
add({ fn = function(E)
    check(landscape(), "…and back to landscape")
    local R = require("apps/reader/readerui").instance
    if R then R:onHome() end
end, after = 8 })
add(view("7-home-after-book"))
add({ fn = function(E)
    local fm = require("apps/filemanager/filemanager").instance
    check(fm and landscape() and fm.dimen.w == Screen():getWidth(), "Home after a landscape book: still landscape")
    local f = io.open(E.out .. "/rotation-checks.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 0.5 })
return s
