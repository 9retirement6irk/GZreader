-- The quick panel's Quick note tile, in a book: there while Memos is
-- connected (a stand-in connection: memos.example.com, which never answers), it
-- opens the note editor in a window over the book (not the whole screen; on
-- touch models above the on-screen keyboard); Save closes it and the book is
-- still there, the note queued. GZ_EMU_BOOK: an EPUB. Keyboard models: the tile's
-- letter and Alt+S; touch models: taps. Writes <out>/quick_note.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local TOUCH = { kt = true, pw3 = true, nst = true, scribe = true }
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
--- The note editor (on a touch model the on-screen keyboard is above it).
local function editor()
    local st = UIM()._window_stack
    for i = #st, 1, -1 do local w = st[i].widget; if w.input and w.on_save then return w end end
end
local function plugin() return require("apps/reader/readerui").instance.gzreader end
local function tapTile(E, label)
    local w = top()
    for _i, p in ipairs(w and w.placed or {}) do
        if p.tile.label == label then
            if TOUCH[E.model] then
                local d = p.tile.dimen
                E.tap({ d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) })
            elseif E.model == "k4" then -- (no letter keys: as Press on the tile)
                p.tile.callback()
            else
                E.key(p.tile.key_letter)
            end
            return true
        end
    end
end
local function tiles()
    local w = top()
    local out = {}
    for _i, p in ipairs(w and w.placed or {}) do out[#out + 1] = tostring(p.tile.label) end
    return "|" .. table.concat(out, "|") .. "|"
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function()
    os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/note.epub")
    require("apps/reader/readerui"):showReader("/mnt/us/GZreader/note.epub")
end, after = 20 })
-- not connected: no tile
add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 4 })
add({ fn = function()
    check(top() and top().name == "gzreader quick panel" and not tiles():find("Quick note", 1, true),
        "Memos not connected: no Quick note tile " .. tiles())
    UIM():close(top())
    -- (a stand-in connection: the send a moment later fails, the note stays queued)
    plugin().store.memos = { server = "https://memos.example.com", token = "emulator", user = "Test" }
end, after = 3 })
add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 4 })
add({ fn = function()
    check(tiles():find("|Quick note|", 1, true), "Memos connected: Quick note on the panel in a book " .. tiles())
end, after = 1 })
add({ shot = "qn-1-panel" })
add({ fn = function(E) check(tapTile(E, "Quick note"), "Quick note picked") end, after = 6 })
add({ fn = function()
    local ed = editor()
    check(ed and ed.memo == nil and require("apps/reader/readerui").instance ~= nil,
        "the new-note editor over the book (top: " .. tostring(top() and (top().name or top().input and "editor")) .. ")")
    if ed and ed.input then ed.input:addChars("Remember page 12 #reading") end
end, after = 3 })
add({ fn = function(E)
    local ed = editor()
    local d = ed and ed.frame and ed.frame.dimen
    local Screen = require("device").screen
    local W, H = Screen:getWidth(), Screen:getHeight()
    local where = d and string.format("%dx%d at %d,%d on %dx%d", d.w, d.h, d.x, d.y, W, H) or "no window"
    check(ed and ed.covers_fullscreen == false and d and d.x > 0 and d.y > 0 and d.x + d.w < W and d.y + d.h < H
        and d.h < H / 2, "a window over the book, not the whole screen: " .. where)
    local st = UIM()._window_stack
    local under = false
    for i = 1, #st do if st[i].widget == ed and i > 1 and st[i - 1].widget.covers_fullscreen then under = true end end
    check(under and require("apps/reader/readerui").instance.document ~= nil, "…the book is under it, still drawn")
    if TOUCH[E.model] then
        local kb = ed and ed.input and ed.input.keyboard
        local kd = kb and kb.dimen
        check(kd and d and d.y + d.h <= kd.y, "…above the on-screen keyboard (keyboard at y " .. tostring(kd and kd.y) .. ")")
    end
end, after = 1 })
add({ shot = "qn-2-editor" })
add({ fn = function(E)
    local ed = editor()
    if TOUCH[E.model] then
        -- (the on-screen keyboard is up: Save is on the toolbar under the title)
        if ed and ed.save then ed:save() end
    else
        E.combo("Alt", "S")
    end
end, after = 5 })
add({ fn = function()
    local q = plugin().store.memos.queue or {}
    local ReaderUI = require("apps/reader/readerui")
    local still_editing = editor() ~= nil
    check(not still_editing and ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil, "Save: the editor closed, the book still open")
    check(#q == 1 and q[1].op == "create" and q[1].content == "Remember page 12 #reading" and q[1].visibility == "PRIVATE",
        "…the note queued for Memos, private (" .. #q .. ")")
    check(package.loaded["gzreader_notes"] and require("gzreader_notes").notes == nil,
        "…the board's notes weren't loaded")
end, after = 3 })
add({ shot = "qn-3-saved" })
-- touch: a tap outside the window (nothing written) closes it, the book stays
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    require("gzreader_notes").quickNote(plugin())
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local d = editor() and editor().frame.dimen
    check(d ~= nil, "Quick note again: the window")
    if d then E.tap({ math.floor(d.x + d.w / 2), math.max(2, d.y - 20) }) end
end, after = 4 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ReaderUI = require("apps/reader/readerui")
    check(editor() == nil and ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil,
        "…a tap above it closes it (nothing written), the book still open")
end, after = 1 })
-- touch: something written, a tap outside asks Save this note?, with the
-- keyboard out of the way (it used to hide the dialog's lower rows)
local function kbShown()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "VirtualKeyboard" then return true end end
    return false
end
local function dialog()
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Save this note?" then return w.widget end end
end
local function askToSave(E)
    local d = editor() and editor().frame.dimen
    if d then E.tap({ math.floor(d.x + d.w / 2), math.max(2, d.y - 20) }) end
end
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    require("gzreader_notes").quickNote(plugin())
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(kbShown(), "Quick note: the keyboard is up")
    editor().input:addChars("Half a thought")
    askToSave(E)
end, after = 4 })
add({ shot = "qn-4-ask" })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local dl = dialog()
    check(dl ~= nil and not kbShown(), "…a tap outside with something written: Save this note?, the keyboard out of the way")
    E.tap("Keep writing")
end, after = 4 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(dialog() == nil and editor() ~= nil and kbShown(), "Keep writing: back to the note, the keyboard back")
    askToSave(E)
end, after = 4 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    -- (the dialog's Save row, just above Discard: "Save" alone would find its title)
    local dd = E.findText("Discard")
    if dd then E.tap({ math.floor(dd.x + dd.w / 2), math.floor(dd.y - dd.h / 2) }) end
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local q = plugin().store.memos.queue or {}
    check(editor() == nil and not kbShown() and #q >= 1 and q[#q].content == "Half a thought",
        "…Save in the dialog saves the note (" .. #q .. " queued) and the keyboard stays away")
end, after = 1 })
-- touch: Draw from the quick note, Close the drawing screen, then a tap
-- outside: the note and its keyboard both go (the keyboard used to stay
-- over the book; the owner, 2026-11-16)
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    require("gzreader_notes").quickNote(plugin())
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    -- (a sticky note: its pencil opens a sticky note of its own to draw on, in a window)
    local ed = editor()
    local d = ed and ed.pencil_tap and ed.pencil_tap.dimen
    check(d ~= nil and d.w > 0 and type(ed.frame.background) == "cdata", "Quick note: a sticky note, with a pencil at the top")
    if d then E.tap({ d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) }) end
end, after = 5 })
add({ shot = "qn-4b-sticky-drawing" })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ds
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then ds = w.widget end end
    local Screen = require("device").screen
    check(ds and ds.sticky and ds.pane and ds.covers_fullscreen == false and ds.pane.w < Screen:getWidth()
        and ds.pane.h < Screen:getHeight(), "…the pencil: a sticky note to draw on, in a window (not the whole screen; no paper to choose)")
    -- a line on it, then a tap outside it: Save this drawing? → Save
    local p = ds.pane
    local pts = {}
    for i = 0, 8 do pts[#pts + 1] = { p.x + math.floor(p.w * (0.3 + 0.05 * i)), p.y + math.floor(p.h * 0.6) } end
    if E.model == "scribe" then E.pen(pts, 0.4); E.penAway(0.3) else E.finger(pts, 0.4) end
end, after = 3 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ds
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then ds = w.widget end end
    check(ds and ds.changed, "…drawn on")
    E.tap({ 10, 10 })
end, after = 3 })
add({ shot = "qn-4c-outside" })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local asked
    for _i, w in ipairs(UIM()._window_stack) do
        if w.widget.title == "Leave without keeping these changes?" or w.widget.title == "Save this drawing?" then asked = w.widget end
    end
    check(asked ~= nil, "…a tap outside the drawing: asked first (nothing went to the book under it)")
    E.tap("Keep drawing")
end, after = 3 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ds
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then ds = w.widget end end
    check(ds ~= nil, "…Keep drawing: still drawing")
    -- (the buttons' places are the window's own: from its corner)
    for _i, b in ipairs(ds and ds.buttons or {}) do
        if b.tool.id == "done" then E.tap({ ds.ox + b.rect.x + math.floor(b.rect.w / 2), ds.oy + b.rect.y + math.floor(b.rect.h / 2) }) end
    end
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ed = editor()
    check(ed ~= nil and ed:hasDrawing(), "Done: back to the quick note, the drawing with it (its pencil black)")
    local d = ed and ed.pencil_tap and ed.pencil_tap.dimen
    if d then E.tap({ d.x + math.floor(d.w / 2), d.y + math.floor(d.h / 2) }) end
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ds
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then ds = w.widget end end
    check(ds ~= nil and not kbShown(), "the pencil again: the drawing, no keyboard over it")
    for _i, b in ipairs(ds and ds.buttons or {}) do
        if b.tool.id == "cancel" and not b.tool.row then
            E.tap({ ds.ox + b.rect.x + math.floor(b.rect.w / 2), ds.oy + b.rect.y + math.floor(b.rect.h / 2) })
        end
    end
end, after = 5 })
add({ shot = "qn-5-after-draw" })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    check(editor() ~= nil and kbShown(), "Close: back to the quick note, the keyboard back")
    askToSave(E)
end, after = 5 })
add({ shot = "qn-6-closed" })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    -- (a drawing in it now: the tap outside asks; Discard)
    local asked
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.title == "Save this note?" then asked = true end end
    check(asked, "…a tap outside the quick note with a drawing in it: Save this note?")
    E.tap("Discard")
end, after = 3 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local n = 0
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "VirtualKeyboard" then n = n + 1 end end
    local ReaderUI = require("apps/reader/readerui")
    check(editor() == nil and n == 0 and ReaderUI.instance ~= nil and ReaderUI.instance.document ~= nil,
        "…a tap outside: the note closes and the keyboard goes with it (" .. n .. " keyboards left), the book there")
end, after = 1 })
-- the same, with the note closed at once (a tap outside while the Kindle
-- is still redrawing after the drawing screen): the keyboard, due back a
-- moment later, mustn't come up for a note that's gone
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    require("gzreader_notes").quickNote(plugin())
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    editor():openDrawing()
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local ds
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "gz_drawscreen" then ds = w.widget end end
    local ed = editor()
    ds:cancel()
    ed:onCloseDialog()
    -- (the sticky drawing's window gone with it)
    check(ed.drawing_rect == nil, "…the sticky drawing's window gone with it")
end, after = 5 })
add({ fn = function(E)
    if not TOUCH[E.model] then return end
    local n = 0
    for _i, w in ipairs(UIM()._window_stack) do if w.widget.name == "VirtualKeyboard" then n = n + 1 end end
    check(editor() == nil and n == 0, "…the note closed straight after the drawing screen: no keyboard left over the book (" .. n .. ")")
end, after = 1 })
add({ shot = "qn-7-race" })
add({ fn = function(E)
    local f = io.open(E.out .. "/quick_note.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
