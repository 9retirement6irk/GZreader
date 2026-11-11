-- Screenshots of the Catalog for the README, the landing page and the wiki
-- (any model; demo/demo_grimmory.py on 127.0.0.1:18080 and
-- demo/demo_plex.py on 127.0.0.1:18090, both with a library made by
-- demo/make_library.py, which has audio.json): signed in to both, the
-- Catalog's Books, Audiobooks and Music pages, a book, an audiobook and an
-- album downloaded from them, Home and Downloads with them, a book open, the
-- quick panel, Settings. The players are stubbed (the emulator has no sound).
-- GZ_SHOTS_SET=pw (or kt): the shorter set by touch, named pw-… (kt-…); a
-- Paperwhite has no audio, so its Catalog is the Books page alone.
-- GZ_SHOTS_SET=more (k3), k4 (k4) or pwmore (pw3): the setup guide's pages
-- (k3), Notes and Calendar (demo/mock_memos.py 18097 --sample, demo/demo_caldav.py 18095).
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local PX = "http://127.0.0.1:18090"
local SET = os.getenv("GZ_SHOTS_SET")
local TOUCH = SET == "pw" or SET == "kt"
local MORE = SET == "more" or SET == "k4" or SET == "pwmore"
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function UIM() return require("ui/uimanager") end
local function top() local st = UIM()._window_stack; return st[#st] and st[#st].widget end
local function closeTop(names)
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if not names or names[w.name] then UIM():close(w) end
    end
end
local function browser() return require("gzreader_browser").current end
local function closeCatalog()
    local b = browser()
    if b and b.menu then UIM():close(b.menu) end
    local st = UIM()._window_stack
    for i = #st, 1, -1 do
        local w = st[i].widget
        if w.item_table and (w.item_table.gz_catalog or w.title == "Books" or w.title == "Audiobooks" or w.title == "Music") then UIM():close(w) end
    end
end
local function pick(menu, pat)
    for _i, it in ipairs(menu and menu.item_table or {}) do
        local t = tostring(it.text or (it.text_func and it.text_func()) or "")
        if t:match(pat) then return it end
    end
end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function wait(t) add({ wait = t }) end
local function say(E, ...) E.say(...) end
local function listTop(E, what)
    local w = top()
    local out = {}
    for i, it in ipairs(w and w.item_table or {}) do
        if i > 14 then break end
        out[#out + 1] = tostring(it.text or (it.text_func and it.text_func()) or "?")
    end
    say(E, what, tostring(w and (w.name or w.title)), table.concat(out, " | "))
end

-- first start: the setup guide's first two pages (keys), then past it,
-- signed in to the demo Grimmory and Plex
if SET == "more" then
    -- (Next on the first page opens the QR code; Back, then Press goes on)
    add({ key = "RPgFwd", after = 5 })
    add({ key = "Back", after = 3 })
    add({ key = "Press", after = 4 })
    for i = 1, 8 do
        shot("guide-" .. i)
        add({ key = "RPgFwd", after = 4 })
    end
elseif not TOUCH and not MORE then
    shot("setup-connect")
    add({ key = "RPgFwd", after = 6 })
    shot("setup-qr")
end
add({ fn = function(E)
    closeTop({ ["setup guide"] = true, ["QR code screen"] = true })
    local Eng = require("gzreader_audioengine")
    Eng.exec = function() return 0 end
    Eng.alive = function() return true end
    G_reader_settings:saveSetting("gzreader_audio_players", { mp3 = "mp3-mfw", aac = "aac-mfw" })
    say(E, "login", tostring(plugin().api:login("http://127.0.0.1:18080", "reader", "demo")))
    local Plex = require("gzreader_plex")
    Plex.TV = PX
    local p = plugin()
    p.store.plex = p.store.plex or {}
    p.store.plex.token = "plex-token"
    p.store.plex.username = "Reader"
    local ok, err = pcall(function() return Plex:new(p.store.plex):connect("plex-token", "srv1") end)
    say(E, "plex", tostring(ok), tostring(err), tostring(p.store.plex.server and p.store.plex.server.uri))
    if p.saveStore then p:saveStore() end
end, after = 8 })
local function menu()
    local b = browser()
    if b and b.menu and not b.closed then
        local w = top()
        if w and w.item_table and w ~= b.menu then return w end
        return b.menu
    end
    local w = top()
    if w and w.item_table then return w end
end
local function choose(pat)
    return { fn = function(E)
        local m = menu()
        local it = pick(m, pat)
        say(E, "choose", pat, it and "found" or "MISSING", tostring(m and m.title))
        if it then
            if it.callback then it.callback() else m:onMenuSelect(it) end
        end
    end }
end
local function step(t, after) t.after = after or 4; add(t) end
local function findBook(pat)
    local h = io.popen("find /mnt/us/GZreader -maxdepth 1 -name '*.epub' 2>/dev/null")
    local all = h:read("*a"); h:close()
    for line in all:gmatch("[^\n]+") do if line:match(pat) then return line end end
end

if MORE then
    local pre = SET == "k4" and "k4-" or SET == "pwmore" and "pw-" or ""
    add({ fn = function(E)
        local Notes = require("gzreader_notes")
        local ok, err = Notes.connect(plugin(), "127.0.0.1:18097", "memos-test-token")
        say(E, "memos", tostring(ok), tostring(err))
        if Notes.connect_menu then UIM():close(Notes.connect_menu, "full"); Notes.connect_menu = nil end
        Notes.show(plugin())
    end, after = 14 })
    shot(pre .. (SET == "pwmore" and "notes" or "notes-board"))
    if SET == "k4" then return s end
    if SET ~= "pwmore" then
        add({ key = "W", after = 6 })
        shot("notes-note")
        add({ key = "Back", after = 3 })
        add({ key = "Back", after = 3 })
    end
    add({ fn = function(E)
        local Cal = require("gzreader_calendar")
        say(E, "caldav", tostring(Cal.connect(plugin(), "127.0.0.1:18095", "reader", "demo-app-password")))
        if Cal.connect_menu then UIM():close(Cal.connect_menu, "full"); Cal.connect_menu = nil end
        Cal.cached_at = nil
        Cal.show(plugin())
    end, after = 20 })
    shot(SET == "pwmore" and "pw-calendar" or "calendar-agenda")
    if SET == "pwmore" then return s end
    add({ key = "M", after = 4 })
    add({ key = "E", after = 6 }) -- Week
    shot("calendar-week")
    return s
end

if TOUCH then
    -- by touch: things downloaded first, then the pages, Downloads, the panel
    for _i, id in ipairs({ 2, 3, 4, 6, 12 }) do
        add({ fn = function() plugin():downloadAndOpen(plugin().api:getBookDetail(id) or { id = id }, nil, { no_open = true }) end, after = 6 })
    end
    add({ fn = function(E)
        if SET ~= "kt" then return end -- (a Paperwhite can't play one)
        require("gzreader_audiobook").download(plugin(), { id = 102, title = "Treasure Island", authors = { "Robert Louis Stevenson" }, primaryFileType = "AUDIOBOOK" },
            function(ok) E.say("audiobook 102", tostring(ok)) end)
    end, after = 20 })
    if SET == "kt" then -- (a Paperwhite has no Music page)
        add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 8 })
        add({ fn = function() browser():openSection("music") end, after = 8 })
        step(choose("^Albums"), 6)
        step(choose("Night Trains"), 6)
        step(choose("^Download"), 15)
    end
    add({ fn = closeCatalog, after = 3 })
    add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 12 })
    shot(SET .. "-catalog-books")
    if SET == "kt" then
        add({ swipe = { 500, 400, 100, 400 }, after = 12 }) -- (to the next page)
        shot("kt-catalog-audiobooks")
        add({ swipe = { 500, 400, 100, 400 }, after = 12 })
        shot("kt-catalog-music")
    end
    -- the tab bar's Downloads and Home (its labels are painted: tapped by place)
    local bar = SET == "kt" and { y = 756, dl = 188, home = 74 } or { y = 1405, dl = 337, home = 133 }
    add({ tap = { bar.dl, bar.y }, after = 10 })
    shot(SET .. "-downloads-shelf")
    add({ tap = { bar.home, bar.y }, after = 6 })
    add({ fn = function() require("gzreader_panel").show(plugin()) end, after = 5 })
    shot(SET .. "-panel")
    add({ fn = function() closeTop({ ["gzreader quick panel"] = true }) end, after = 3 })
    add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
    shot(SET .. "-settings")
    return s
end

-- the Catalog: Books → All books → a book's page → Download
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 14 })
step(choose("^All books"), 8)
shot("catalog-all-books")
add({ fn = function(E) listTop(E, "all books") end })
step(choose("Persuasion"), 10)
shot("catalog-book-page")
add({ key = "Press", after = 2 })
shot("catalog-book-downloading", 1)
wait(12)
add({ fn = function() closeTop({ ["gzreader book page"] = true }) end, after = 2 })
add({ fn = function(E) listTop(E, "after book download") end })
-- Audiobooks → All audiobooks → an audiobook's page → Download
add({ fn = function() browser():openSection("audiobooks") end, after = 10 })
step(choose("^All audiobooks"), 8)
shot("catalog-all-audiobooks")
add({ fn = function(E) listTop(E, "all audiobooks") end })
step(choose("Treasure Island"), 10)
shot("catalog-audiobook-confirm")
add({ key = "Right", after = 1 })
add({ key = "Press", after = 2 })
shot("catalog-audiobook-downloading", 1)
wait(20)
add({ fn = function(E) local w = top(); say(E, "after audiobook download", tostring(w and w.name)) end })
shot("audiobook-player")
add({ fn = function()
    local w = top()
    if w and w ~= (browser() or {}).menu and not w.item_table then UIM():close(w) end
end, after = 3 })
-- Music → Albums → an album → Download
add({ fn = function() closeTop({ ["gzreader book page"] = true }) end, after = 2 })
add({ fn = function() browser():openSection("music") end, after = 10 })
step(choose("^Albums"), 8)
shot("catalog-albums")
add({ fn = function(E) listTop(E, "albums") end })
step(choose("Low Tide"), 8)
shot("catalog-album")
add({ fn = function(E) listTop(E, "album") end })
step(choose("^Download"), 3)
shot("catalog-album-downloading", 1)
wait(15)
-- a few more books and an audiobook, without opening them
for _i, id in ipairs({ 2, 3, 6, 1, 12, 13 }) do
    add({ fn = function(E)
        local api = plugin().api
        local b = api:getBookDetail(id) or { id = id }
        say(E, "download", tostring(b.title))
        plugin():downloadAndOpen(b, nil, { no_open = true })
    end, after = 6 })
end
add({ fn = function(E)
    local A = require("gzreader_audiobook")
    A.download(plugin(), { id = 101, title = "Pride and Prejudice", authors = { "Jane Austen" }, primaryFileType = "AUDIOBOOK" },
        function(ok) E.say("audiobook 101", tostring(ok)) end)
end, after = 20 })
-- the three pages again, with things downloaded
add({ fn = function()
    local b = browser()
    if b and b.menu then UIM():close(b.menu) end
    closeTop({ ["gzreader book page"] = true })
end, after = 3 })
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 10 })
shot("catalog-books")
add({ fn = function() browser():openSection("audiobooks") end, after = 10 })
shot("catalog-audiobooks")
add({ fn = function() browser():openSection("music") end, after = 10 })
shot("catalog-music")
add({ fn = function()
    local b = browser()
    if b and b.menu then UIM():close(b.menu) end
end, after = 4 })
add({ key = "Menu", after = 4 })
shot("home-panel")
add({ key = "Back", after = 3 })
add({ key = "X", after = 8 })
shot("downloads-shelf")
add({ key = "Z", after = 6 })
-- books opened (Home's shelf), then one read, the quick panel there
for _i, pat in ipairs({ "Persuasion", "Emma", "Innocence" }) do
    add({ fn = function(E)
        local f = findBook(pat)
        say(E, "open", tostring(f))
        if f then require("apps/reader/readerui"):showReader(f) end
    end, after = 22 })
    add({ fn = function() local ui = require("apps/reader/readerui").instance; if ui then ui:onHome() end end, after = 8 })
end
add({ fn = function(E)
    local f = findBook("Moby")
    say(E, "book", tostring(f))
    if f then require("apps/reader/readerui"):showReader(f) end
end, after = 25 })
add({ key = "RPgFwd", after = 3 })
add({ key = "RPgFwd", after = 3 })
shot("reading")
add({ key = "Menu", after = 4 })
shot("reading-panel")
add({ key = "Back", after = 3 })
add({ fn = function() local ui = require("apps/reader/readerui").instance; if ui then ui:onHome() end end, after = 8 })
shot("home")
-- music playing: the CD player, then the quick panel's Music tile
add({ fn = function() plugin():onShowGrimmoryLibrary() end, after = 8 })
add({ fn = function() browser():openSection("music") end, after = 8 })
step(choose("^Albums"), 6)
step(choose("Low Tide"), 6)
add({ fn = function(E) plugin().store.plex["repeat"] = "all" end })
step(choose("^Play$"), 10)
shot("music-cd-player")
add({ fn = function(E) local w = top(); say(E, "playing", tostring(w and w.name)) end })
add({ fn = function()
    closeTop({ ["gzreader cd player"] = true })
    local b = browser()
    if b and b.menu then UIM():close(b.menu) end
end, after = 4 })
add({ key = "Menu", after = 4 })
shot("home-panel-playing")
add({ key = "Back", after = 3 })
-- Settings
add({ fn = function() require("gzreader_homemenu").settings() end, after = 6 })
shot("settings")
return s
