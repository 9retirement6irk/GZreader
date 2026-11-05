-- The Music tab (with tests/mock_plex.py on 127.0.0.1:18090 standing in for
-- plex.tv and a Plex server): the tab bar with Music on (6 tabs), then with 7;
-- signing in with a code (plex.tv/link), Artists → an album → Play (it
-- downloads, then plays), Now playing, the Home and Reading menus' Music line.
-- The player is stubbed (the emulator has no sound): Engine.exec / alive.
-- Writes <out>/music.txt (ok / FAIL lines) and screenshots.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local PX = "http://127.0.0.1:18090"
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function stack() return require("ui/uimanager")._window_stack end
local function top() local st = stack(); return st[#st] and st[#st].widget end
local function menuTitled(pat)
    -- (1.22: the Music tab is the CD player's library: its lists on the insert)
    local CD = package.loaded["gzreader_cdscreen"]
    local cd = CD and CD.instance
    if cd and cd.nav and cd.mode == "library" and tostring(cd.nav.title):match(pat) then return cd.nav end
    for i = #stack(), 1, -1 do
        local w = stack()[i].widget
        if w.item_table and tostring(w.title):match(pat) then return w end
    end
    -- (the Music tab's list changes in place: its Menu)
    local Tab = package.loaded["gzreader_musictab"]
    if pat ~= "^Now playing" and Tab and Tab.instance and not Tab.instance.closed then return Tab.instance.menu end
end
local function pick(menu, pat)
    for _i, it in ipairs(menu and menu.item_table or {}) do
        if tostring(it.text or (it.text_func and it.text_func()) or ""):match(pat) then return it end
    end
end
local function tabsOn(ids)
    local fm = require("apps/filemanager/filemanager").instance
    local zen = fm.zenos
    for id, on in pairs(ids) do zen.config.navbar.show_tabs[id] = on end
    if zen.saveConfig then zen:saveConfig() else require("config/manager").save(zen.config) end
    local reinject = rawget(_G, "__ZEN_UI_REINJECT_NAVBARS") or rawget(_G, "__ZEN_UI_REINJECT_FM_NAVBAR")
    if type(reinject) == "function" then reinject() end
end

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    require("gzreader_plex").TV = PX
    local E = require("gzreader_audioengine")
    E.exec = function() return 0 end
    E.alive = function() return true end
    G_reader_settings:saveSetting("gzreader_audio_players", { mp3 = "mp3-mfw", aac = "aac-mfw" })
end, after = 6 })
add({ shot = "1-bar-5" })
add({ fn = function() tabsOn({ ct_music = true }) end, after = 6 })
add({ shot = "2-bar-6" })
add({ fn = function() tabsOn({ continue = true }) end, after = 6 })
add({ shot = "3-bar-7" })
add({ fn = function() tabsOn({ favorites = true }) end, after = 6 })
add({ shot = "4-bar-8-asked" })
add({ fn = function() tabsOn({ continue = false, favorites = false }) end, after = 6 })
add({ fn = function() require("gzreader_musictab").show(plugin()) end, after = 4 })
add({ shot = "5-music-signed-out" })
add({ fn = function(E)
    local m = menuTitled("^Music")
    check(m and pick(m, "plex.tv/link"), "Music tab: sign in with a code or the phone page")
    pick(m, "plex.tv/link").callback()
end, after = 8 })
add({ shot = "6-code" })
add({ fn = function(E)
    local w = top()
    check(w and w.name == "plex code screen", "the code screen")
    -- the person enters the code at plex.tv/link: the mock marks the newest PIN signed in
    local http = require("socket.http")
    local body = http.request(PX .. "/ctl/log")
    local id
    for pid in tostring(body):gmatch('"/api/v2/pins/(%d+)"') do id = pid end
    http.request(PX .. "/ctl/claim?id=" .. tostring(id))
    E.say("claimed pin", tostring(id))
end, after = 20 })
add({ shot = "7-signed-in" })
add({ fn = function(E)
    local m = menuTitled("^Music")
    local ps = plugin().store.plex or {}
    check(ps.token ~= nil and ps.server and ps.server.name == "Home Server" and m and pick(m, "^Artists"), "signed in: Artists, Albums, Playlists, Search")
    pick(m, "^Artists").callback()
end, after = 6 })
add({ fn = function(E)
    local m = menuTitled("^Artists")
    check(m and pick(m, "The Tones"), "Artists")
    pick(m, "The Tones").callback()
end, after = 6 })
add({ fn = function(E)
    local m = menuTitled("^The Tones")
    check(m and pick(m, "MP3 Album"), "an artist's albums")
    pick(m, "MP3 Album").callback()
end, after = 6 })
add({ shot = "8-album" })
add({ fn = function(E)
    local m = menuTitled("^MP3 Album")
    check(m and pick(m, "^Play$") and pick(m, "^1%. Tone A"), "the album: Play, Shuffle, Download, its tracks")
    plugin().store.plex["repeat"] = "all" -- (3-second tracks: keep going round)
    pick(m, "^Play$").callback()
end, after = 15 })
add({ shot = "9-now-playing" })
add({ fn = function(E)
    local Music = require("gzreader_music")
    check(Music.current and Music.current.playing and not Music.current.waiting and tostring(Music.nowText()):match("^Tone [AB] — The Tones$"),
        "Play: downloaded, playing " .. tostring(Music.nowText()))
    local UIM = require("ui/uimanager")
    local st = UIM._window_stack
    local m = st[#st] and st[#st].widget
    check(m and m.name == "gzreader cd player" and m.onNext and m.onToggle, "Now playing: the CD player, with its controls")
    if m then UIM:close(m) end
end, after = 3 })
add({ fn = function() require("gzreader_homemenu").show(plugin()) end, after = 4 })
add({ shot = "10-home-menu" })
add({ fn = function(E)
    local m = top()
    check(m and pick(m, "^Music: Tone [AB]"), "Home menu: Music: what's playing")
    require("ui/uimanager"):close(m)
end, after = 3 })
add({ fn = function(E)
    local Device = require("device")
    local dir = (Device.home_dir or "/mnt/us") .. "/GZreader"
    os.execute("mkdir -p '" .. dir .. "' && cp '" .. os.getenv("GZ_EMU_BOOK") .. "' '" .. dir .. "/music.epub'")
    require("apps/reader/readerui"):showReader(dir .. "/music.epub")
end, after = 25 })
add({ fn = function()
    local ui = require("apps/reader/readerui").instance
    require("gzreader_readmenu").show(ui and ui.gzreader)
end, after = 4 })
add({ shot = "11-reading-menu" })
add({ fn = function(E)
    local m = top()
    check(m and pick(m, "^Music: Tone [AB]"), "Reading menu: Music: what's playing")
    local out = io.open(E.out .. "/music.txt", "w"); out:write(table.concat(lines, "\n"), "\n"); out:close()
end, after = 1 })
return s
