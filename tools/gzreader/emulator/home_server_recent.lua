-- Home's "Recently read on every device" (demo/demo_grimmory.py on 127.0.0.1:18080;
-- any model): sign in, download one book and read it here, turn the option on. Home's
-- current book and Recent strip then also show what Grimmory has in progress: books
-- that aren't on this Kindle (an arrow on the cover) and audiobooks (cassettes). Then a
-- tap on a book that isn't here (its page, with Download) and on an audiobook (its
-- question). With GZ_EMU_TAPE=1, one audiobook is on the Kindle too (its cassette has
-- no arrow); GZ_EMU_NO_BOOK=1: no book read here (the current book is then the
-- server's); GZ_EMU_VIEW=covers: the strip as covers, not the bookshelf; GZ_EMU_PICK="x,y":
-- a tap there before the rest (on the shelf, a cassette on its side: it turns to face
-- out). Prints the merged history and what each tap opened.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function closeAll(E)
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end
local function redraw() require("common/gz_view").redrawHome() end

add({ fn = closeAll, after = 6 })
add({ fn = function(E) E.say("login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo"))) end, after = 2 })
-- one book on the Kindle, read here just now (Emma: Grimmory also has it in progress)
add({ fn = function()
    if os.getenv("GZ_EMU_VIEW") == "covers" then
        local V = require("common/gz_view")
        if V.isBookshelf() then V.set("mosaic_image") end
    end
    if os.getenv("GZ_EMU_NO_BOOK") == "1" then return end
    plugin():downloadAndOpen(plugin().api:getBookDetail(3) or { id = 3 }, nil, { no_open = true })
end, after = 12 })
add({ fn = function(E)
    local p = plugin()
    local path = p:localPathFor(3)
    E.say("downloaded:", tostring(path))
    if path then require("readhistory"):addItem(path, os.time()) end
    if os.getenv("GZ_EMU_TAPE") == "1" then
        -- an audiobook on the Kindle (as audiobook_tiles.lua makes one), played a week ago
        local dir = require("gzreader_audiobook").dir(p, 103)
        os.execute("mkdir -p '" .. dir .. "/audiobook.m4b.chunks'")
        for i = 0, 3 do local f = io.open(dir .. "/audiobook.m4b.chunks/c" .. i .. ".aac", "wb"); f:write("x"); f:close() end
        local f = io.open(dir .. "/audiobook.m4b.chunks/index.json", "wb")
        f:write('{"starts":[0,15000,30000,45000],"durationMs":60000,"count":4}'); f:close()
        f = io.open(dir .. "/audiobook.json", "wb")
        f:write(require("json").encode({ id = 103, title = "The Wind in the Willows", author = "Kenneth Grahame", durationMs = 3600000,
            files = { "audiobook.m4b.chunks/c0.aac" },
            tracks = { { file = "audiobook.m4b", start = 0, durationMs = 3600000,
                chunks = { dir = "audiobook.m4b.chunks", starts = { 0, 15000, 30000, 45000 } } } } }))
        f:close()
        p.store.audiobooks = p.store.audiobooks or {}
        p.store.audiobooks[103] = { title = "The Wind in the Willows", author = "Kenneth Grahame", pos_ms = 420000 }
        local Folder = require("gzreader_abfolder")
        Folder.start(p)
        local stub = Folder.stubPath(p, 103)
        E.say("stand-in:", tostring(stub))
        if stub then require("readhistory"):addItem(stub, os.time() - 7 * 86400) end
    end
    redraw()
end, after = 8 })
add({ shot = "recent-0-off" })
add({ fn = function(E)
    local Recent = require("gzreader_serverrecent")
    Recent.set(plugin(), true)
end, after = 12 })
add({ fn = function(E)
    local Recent = require("gzreader_serverrecent")
    local kept = Recent.kept(plugin())
    E.say("kept:", tostring(kept and #kept.items), "stamp:", Recent.stamp(plugin()))
    for _i, e in ipairs(Recent.entries(plugin())) do
        E.say("  ", e.key, e.audio and "audiobook" or "book", tostring(e.time), tostring(e.path), e.title)
    end
    redraw()
end, after = 10 })
add({ shot = "recent-1-on" })
-- GZ_EMU_PICK="x,y": a tap there (a cassette on its side on the shelf: it turns to face out)
if os.getenv("GZ_EMU_PICK") then
    local px, py = os.getenv("GZ_EMU_PICK"):match("(%d+),(%d+)")
    add({ tap = { tonumber(px), tonumber(py) }, after = 6 })
    add({ shot = "recent-1b-picked" })
end
add({ fn = function(E)
    local ZR = require("common/gz_server_recent")
    local ok = ZR.open("gzserver:2") -- Moby Dick: not on this Kindle
    E.say("tap on a book that isn't here:", tostring(ok), "top:", E.top())
end, after = 8 })
add({ shot = "recent-2-book-page" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    local ok = require("common/gz_server_recent").open("gzserver:101") -- an audiobook
    E.say("tap on an audiobook that isn't here:", tostring(ok), "top:", E.top())
end, after = 6 })
add({ shot = "recent-3-audiobook-ask" })
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    -- off again: Home as before
    require("gzreader_serverrecent").set(plugin(), false)
    redraw()
end, after = 8 })
add({ shot = "recent-4-off-again" })
return s
