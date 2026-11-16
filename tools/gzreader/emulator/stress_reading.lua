-- Reading under stress (any model): a ~30 MB EPUB (GZ_STRESS_HUGE) opened,
-- timed, jumped through (50 %, 95 %, back), a highlight, a highlight with a
-- note, two bookmarks, read aloud for a while (the Kindle voice stood in for
-- by emu.lua's lipc stub; TTS.duration shortened so it crosses pages),
-- closed and opened again (the layout cache), the marks still there; then a
-- big picture book (GZ_STRESS_PICS) opened, timed, pages turned.
-- Checks to <out>/stress.txt (ok / FAIL lines, plus "time" lines).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local HUGE = "/mnt/us/GZreader/huge.epub"
local PICS = "/mnt/us/GZreader/picbook.epub"
local R = { lines = {} }
local function line(t) R.lines[#R.lines + 1] = t end
local function check(ok, what) line((ok and "ok " or "FAIL ") .. what) end
local function reader() return require("apps/reader/readerui").instance end
local function ready() local ui = reader(); return ui and ui.document and ui.gz_ready_seen end
local Event = require("ui/event")

-- mark ReaderReady
add({ fn = function()
    local ReaderUI = require("apps/reader/readerui")
    local orig = ReaderUI.onReaderReady
    ReaderUI.onReaderReady = function(self, ...)
        self.gz_ready_seen = true
        if orig then return orig(self, ...) end
    end
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    os.execute("mkdir -p /mnt/us/GZreader && cp '" .. os.getenv("GZ_STRESS_HUGE") .. "' " .. HUGE
        .. " && cp '" .. os.getenv("GZ_STRESS_PICS") .. "' " .. PICS)
end, after = 6 })

local function openTimed(path, label, settle)
    add({ fn = function()
        R.t0 = require("ui/time").now(); R.c0 = os.clock()
        require("apps/reader/readerui"):showReader(path)
    end, after = 0.5 })
    add({ wait_for = function() return ready() end, timeout = 600, label = label, after = 2 })
    if settle then
        -- (a picture book's first opening fits it and opens it once more:
        -- gzreader_picturebook.lua's PB.reopen; time it to the second one)
        add({ wait = settle })
        add({ wait_for = function() return ready() end, timeout = 120, label = label .. " (reopened)", after = 2 })
    end
    add({ fn = function()
        local time = require("ui/time")
        local ok = ready()
        local secs = time.to_s(time.now() - R.t0)
        line(string.format("time %s: %.1f s wall%s, %.1f s CPU (this process)", label, secs,
            settle and string.format(" (with a %d s wait for the reopening)", settle) or "", os.clock() - R.c0))
        check(ok, label .. " opened")
        local ui = reader()
        if ui and ui.document then
            line(string.format("info %s: %d pages", label, ui.document:getPageCount()))
        end
    end, after = 1 })
end

openTimed(HUGE, "huge first open")
add({ shot = "1-huge" })
add({ fn = function() R.p1 = reader().document:getCurrentPage(); reader():handleEvent(Event:new("GotoViewRel", 1)) end, after = 3 })
add({ fn = function() check(reader().document:getCurrentPage() == R.p1 + 1, "page turn on the huge book") end, after = 1 })
-- deep jumps
add({ fn = function()
    R.j0 = os.clock()
    reader():handleEvent(Event:new("GotoPercent", 50))
end, after = 3 })
add({ fn = function()
    local n = reader().document:getPageCount()
    local p = reader().document:getCurrentPage()
    line(string.format("time jump to 50%%: %.2f s CPU", os.clock() - R.j0))
    check(math.abs(p - n / 2) < n * 0.02, "jump to 50% (page " .. p .. " of " .. n .. ")")
end, after = 1 })
add({ shot = "2-huge-50" })
-- highlight + highlight with note at 50 %
add({ fn = function()
    local ui = reader()
    local doc = ui.document
    local xp = doc:getXPointer()
    local s0 = doc:getNextVisibleWordStart(xp) or xp
    local e = s0
    for _i = 1, 6 do e = doc:getNextVisibleWordEnd(e) or e end
    R.hl_text = doc:getTextFromXPointers(s0, e)
    local item = { page = s0, pos0 = s0, pos1 = e, drawer = "lighten", color = "yellow",
        text = R.hl_text, chapter = "x" }
    local index = ui.annotation:addItem(item)
    ui:handleEvent(Event:new("AnnotationsModified", { item, nb_highlights_added = 1, index_modified = index }))
    -- a second one, a few words on, with a note
    local s1 = doc:getNextVisibleWordStart(e) or e
    local e1 = s1
    for _i = 1, 4 do e1 = doc:getNextVisibleWordEnd(e1) or e1 end
    local item2 = { page = s1, pos0 = s1, pos1 = e1, drawer = "lighten", color = "green",
        text = doc:getTextFromXPointers(s1, e1), note = "Stress note", chapter = "x" }
    local index2 = ui.annotation:addItem(item2)
    ui:handleEvent(Event:new("AnnotationsModified", { item2, nb_highlights_added = 1, index_modified = index2 }))
    check(R.hl_text and #R.hl_text > 0, "highlight text: " .. tostring(R.hl_text))
end, after = 3 })
add({ shot = "3-highlights" })
add({ fn = function() reader().bookmark:toggleBookmark() end, after = 3 })
add({ fn = function() R.j0 = os.clock(); reader():handleEvent(Event:new("GotoPercent", 95)) end, after = 3 })
add({ fn = function() line(string.format("time jump to 95%%: %.2f s CPU", os.clock() - R.j0)); reader().bookmark:toggleBookmark() end, after = 3 })
add({ fn = function()
    local n = 0
    for _i, a in ipairs(reader().annotation.annotations) do if not a.drawer then n = n + 1 end end
    check(n == 2, "two bookmarks (" .. n .. ")")
end, after = 1 })
-- read aloud from 95 %: short estimates so it crosses a page
add({ fn = function()
    local plugin = reader().gzreader
    R.tts = plugin and plugin.tts
    if not R.tts then line("info read aloud: not on this model"); return end
    local TTS = require("gzreader_tts")
    G_reader_settings:saveSetting("gzreader_tts_template", { target = TTS.TARGETS[1], fields = { { "text", str = "x" } } })
    R.said = {}
    local orig_say = TTS.say
    TTS.say = function(text, ...)
        R.said[#R.said + 1] = text
        return orig_say(text, ...)
    end
    TTS.duration = function() return 0.6 end
    R.tts_p0 = reader().document:getCurrentPage()
    R.tts:start()
end, after = 25 })
add({ shot = "4-read-aloud" })
add({ fn = function()
    if not R.tts then return end
    local p = reader().document:getCurrentPage()
    check(R.tts.active, "read aloud still going")
    check(#R.said >= 8, "read aloud said " .. #R.said .. " pieces")
    check(p > R.tts_p0, "read aloud turned the page (" .. R.tts_p0 .. " -> " .. p .. ")")
    local long = 0
    for _i, t in ipairs(R.said) do if #t > 600 then long = long + 1 end end
    check(long == 0, "no piece over 600 characters (" .. long .. ")")
    -- a manual page turn while reading restarts from the new page
    reader():handleEvent(Event:new("GotoViewRel", 1))
end, after = 4 })
add({ fn = function()
    if not R.tts then return end
    check(R.tts.active, "read aloud survives a manual page turn")
    R.tts:stop()
    check(not R.tts.active, "read aloud stopped")
end, after = 2 })
-- close, reopen: cache + marks
add({ fn = function() reader():onHome() end, after = 10 })
openTimed(HUGE, "huge second open (cache)")
add({ fn = function()
    local hl, bm, note = 0, 0, 0
    for _i, a in ipairs(reader().annotation.annotations) do
        if a.drawer then hl = hl + 1; if a.note then note = note + 1 end else bm = bm + 1 end
    end
    check(hl == 2 and bm == 2 and note == 1, string.format("marks kept: %d highlights (%d with a note), %d bookmarks", hl, note, bm))
    local p = reader().document:getCurrentPage()
    check(p > reader().document:getPageCount() * 0.9, "reopened where it was left (page " .. p .. ")")
end, after = 1 })
add({ fn = function() reader():onHome() end, after = 10 })
-- the picture book
openTimed(PICS, "picture book first open", 6)
add({ shot = "5-picbook" })
add({ fn = function()
    R.pp = reader().document:getCurrentPage()
    R.pc = os.clock()
    for _i = 1, 5 do reader():handleEvent(Event:new("GotoViewRel", 1)) end
end, after = 4 })
add({ fn = function()
    line(string.format("time picture book 5 page turns: %.2f s CPU", os.clock() - R.pc))
    check(reader().document:getCurrentPage() >= R.pp + 5, "picture book pages turn (" .. R.pp .. " -> " .. reader().document:getCurrentPage() .. ")")
end, after = 1 })
add({ shot = "6-picbook-6" })
add({ fn = function() reader():onHome() end, after = 10 })
openTimed(PICS, "picture book second open")
add({ fn = function(E)
    reader():onHome()
    local f = io.open(E.out .. "/stress.txt", "w")
    f:write(table.concat(R.lines, "\n"), "\n")
    f:close()
end, after = 8 })
return s
