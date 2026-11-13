-- Music's player and its three tabs (Now playing, Queue, Library) on any
-- model with audio (kt for touch, k3/dx for keys): an album "plays" (the
-- player is stood in for: the emulator has no sound) and Plex is stood in
-- for, so no servers are needed. Screenshots of each tab and of a list
-- inside the library; <out>/player-tabs.txt (ok / FAIL lines).
--   GZ_EMU_MODEL=kt [GZ_PLAYER_COVER=cover.jpg] run.sh music_player_tabs.lua <out>
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function plugin()
    local fm = require("apps/filemanager/filemanager").instance
    return fm and fm.gzreader
end
local function cd() return package.loaded["gzreader_cdscreen"] and package.loaded["gzreader_cdscreen"].instance end
local TRACKS = { { "Low Tide", 197 }, { "Sandbar", 214 }, { "Saltwater Radio", 231 }, { "Gulls", 248 }, { "Driftwood", 182 },
    { "Tidepool", 167 }, { "Lighthouse Keeper", 261 }, { "Undertow", 219 }, { "Shell Collection", 178 }, { "Pier at Night", 284 },
    { "Fog Horn", 203 }, { "High Water", 240 } }

add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    local Music = require("gzreader_music")
    local p = plugin()
    p.store.plex = { username = "reader", server = { name = "Home Server" } }
    Music.plex = function() return { isConnected = function() return true end } end
    Music.downloaded = function() return { {}, {}, {} } end
    local c = { dir = "/tmp/gz-player-tabs", title = "Low Tide", artist = "The Gullwings", kind = "album", key = "1", tracks = {} }
    -- (a cover for the disc: GZ_PLAYER_COVER, a JPEG, if given)
    os.execute("rm -rf " .. c.dir .. " && mkdir -p " .. c.dir)
    if os.getenv("GZ_PLAYER_COVER") then os.execute("cp '" .. os.getenv("GZ_PLAYER_COVER") .. "' " .. c.dir .. "/cover.jpg") end
    for i, t in ipairs(TRACKS) do c.tracks[i] = { title = t[1], duration = t[2] * 1000, file = "t" .. i .. ".mp3", key = tostring(i) } end
    local pl = Music.Player:new(p, c, 2, false)
    pl.playing = true
    pl.position = function() return 72000 end
    pl.seeks = {}
    pl.seekTo = function(self, ms) self.seeks[#self.seeks + 1] = ms end
    Music.current = pl
    require("gzreader_cdscreen").show(p)
end, after = 6 })
add({ shot = "1-now-playing" })
add({ fn = function()
    local w = cd()
    check(w and w.mode == "now", "opens on Now playing while something plays")
    w:onNextKey(); w:onNextKey()
end, after = 3 })
add({ fn = function()
    local w = cd()
    local pl = require("gzreader_music").current
    check(#pl.seeks == 1 and pl.seeks[1] == 92000, "▶ twice: one seek, 20 s on (" .. table.concat(pl.seeks, ",") .. ")")
    w:onTabQueue()
end, after = 4 })
add({ shot = "2-queue" })
add({ fn = function()
    local w = cd()
    check(w.mode == "queue" and w.rows and w.rows >= 5, "the queue: " .. tostring(w.rows) .. " rows a page")
    w:onDown(); w:onDown()
end, after = 3 })
add({ shot = "3-queue-picked" })
add({ fn = function()
    local w = cd()
    check(w.picked == 4, "▲ ▼ move the outline")
    w:onTabLibrary()
end, after = 4 })
add({ shot = "4-library" })
add({ fn = function()
    local w = cd()
    local texts = {}
    for _i, it in ipairs(w.nav.item_table) do texts[#texts + 1] = it.text end
    check(w.mode == "library" and table.concat(texts, "|"):find("Recently played|Recently added|Playlists|Albums|Artists|On this Kindle", 1, true),
        "the library's first list: " .. table.concat(texts, "|"))
    local items = {}
    for i, n in ipairs({ "Harbour Lights", "Low Tide", "Night Trains", "Nocturnes", "Paper Boats", "Pier Songs", "Quiet Hours", "Small Rooms" }) do
        items[i] = { text = n, mandatory = tostring(2014 + i), callback = function() end }
    end
    w.tab:push("Albums", items)
end, after = 4 })
add({ shot = "5-library-albums" })
add({ fn = function(E)
    local w = cd()
    check(#w.nav.item_table_stack == 1 and w.nav.title == "Albums", "inside a list: Albums")
    w:onClose()
    check(#w.nav.item_table_stack == 0 and cd() == w, "Back: up to the first list, the player still open")
    w:onTabNow()
    local out = io.open(E.out .. "/player-tabs.txt", "w"); out:write(table.concat(lines, "\n"), "\n"); out:close()
end, after = 3 })
add({ shot = "6-now-again" })
return s
