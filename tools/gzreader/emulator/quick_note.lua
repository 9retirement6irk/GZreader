-- The quick panel's Quick note tile, in a book: there while Memos is
-- connected (a stand-in connection: memos.example.com, which never answers), it
-- opens the note editor over the book; Save closes it and the book is still
-- there, the note queued. GZ_EMU_BOOK: an EPUB. Keyboard models: the tile's
-- letter and Alt+S; touch models: taps. Writes <out>/quick_note.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local TOUCH = { kt = true, pw3 = true, nst = true }
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
add({ fn = function(E)
    local f = io.open(E.out .. "/quick_note.txt", "w")
    if f then f:write(table.concat(lines, "\n") .. "\n"); f:close() end
    for _i, l in ipairs(lines) do print("[emu] " .. l) end
end, after = 1 })
return s
