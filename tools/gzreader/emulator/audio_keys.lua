-- luacheck: globals EMU
-- Audiobook keys (1.6.2): pause and play again (the player process is
-- stopped and started again from the same place), the volume rocker in the
-- player, on Home and while reading, D (about the book: Grimmory's
-- description), the Home key from the player and from Settings, sleep
-- (pauses) and closing GZreader (stops the player).
-- Needs a stand-in gst-launch-0.10 on PATH (no audio here), e.g.
--   printf '#!/bin/sh\necho "$$ $*" >> /tmp/gst-standin.log\ncat > /dev/null\nexec sleep 600\n' \
--     > /usr/local/bin/gst-launch-0.10
local s = { start = 12, { key = "Back", after = 4 } }
local function add(t) s[#s + 1] = t end
local function key(k, after) add({ key = k, after = after or 3 }) end
local function shot(name, after) add({ shot = name, after = after or 1 }) end
local function say(label, fn) add({ fn = function(E) E.say(label, fn()) end, after = 1 }) end
local function gst()
    local f = io.popen("pidof sleep 2>/dev/null; tail -n 1 /tmp/gst-standin.log 2>/dev/null")
    local out = f:read("*a"); f:close()
    return (out:gsub("\n", " | "))
end
local function state()
    local AB = require("gzreader_audiobook")
    local p = AB.current
    return p and string.format("playing=%s paused=%s pos=%d engine=%s", tostring(p.playing), tostring(p.paused),
        math.floor(p:globalPos()), tostring(require("gzreader_audioengine").active())) or "no player"
end
local function vol() return tostring(G_reader_settings:readSetting("gzreader_tts_volume")) end

add({ fn = function()
    os.execute("rm -f /tmp/gst-standin.log")
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local lib = plugin:libraryDir()
    local dir = lib .. "/.audiobooks/10"
    os.execute("mkdir -p '" .. dir .. "/audiobook.m4b.chunks'")
    local starts = {}
    for i = 0, 39 do
        local f = io.open(dir .. "/audiobook.m4b.chunks/c" .. i .. ".aac", "wb"); f:write("x"); f:close()
        starts[#starts + 1] = i * 15000
    end
    local f = io.open(dir .. "/audiobook.m4b.chunks/index.json", "wb")
    f:write(require("json").encode({ starts = starts, durationMs = 600000, count = 40 })); f:close()
    local chapters = {}
    for i = 1, 12 do chapters[i] = { title = "Chapter " .. i .. ": On the Trail", startTimeMs = (i - 1) * 50000 } end
    f = io.open(dir .. "/audiobook.json", "wb")
    f:write(require("json").encode({ id = "10", title = "A Walk in the Woods", author = "Bill Bryson", narrator = "Rob McQuay",
        durationMs = 600000, chapters = chapters, files = { "audiobook.m4b.chunks/c0.aac" },
        description = "Back in America after twenty years in Britain, Bill Bryson decided to reacquaint himself with his native country by walking the 2,100-mile Appalachian Trail.\n\nThe trail offers an astonishing landscape of silent forests and sparkling lakes, and to a writer with the comic genius of Bill Bryson, it also provides endless opportunities to witness the folly of his fellow human beings.",
        tracks = { { file = "audiobook.m4b", start = 0, durationMs = 600000,
            chunks = { dir = "audiobook.m4b.chunks", starts = starts } } } }))
    f:close()
    os.execute("cp /root/work/demo/lib/10.jpg '" .. dir .. "/cover.jpg'")
    plugin.store.audiobooks = { ["10"] = { title = "A Walk in the Woods", author = "Bill Bryson", pos_ms = 160000 } }
    G_reader_settings:saveSetting("gzreader_audio_players", { aac = "aac-mfw", mp3 = "mp3-mfw" })
    G_reader_settings:saveSetting("gzreader_tts_volume", 10)
    require("gzreader_abfolder").start(plugin)
    require("gzreader_abfolder").open(plugin, "10")
end, after = 8 })
say("opened:", state)
say("gst:", gst)
shot("ak-1-playing")
-- pause and play again
key("Press", 3)
say("after pause:", state)
say("gst after pause:", gst)
shot("ak-2-paused")
add({ wait = 4 })
key("Press", 4)
say("after play:", state)
say("gst after play:", gst)
shot("ak-3-playing-again")
-- the volume rocker on the player
key("VPlus", 2); key("VPlus", 2)
say("volume after 2x VPlus:", vol)
shot("ak-4-volume-up")
key("VMinus", 2)
say("volume after VMinus:", vol)
-- D: about this book
key("D", 4)
shot("ak-5-about")
key("Back", 3)
-- the Home key: Home, the audio keeps playing
key("Home", 8)
say("after Home key:", function() return state() .. " | top: " .. EMU.top() end)
shot("ak-6-home")
-- the rocker on Home: a note with the level
key("VPlus", 1)
shot("ak-7-home-volume", 0.5)
say("volume on Home:", vol)
add({ wait = 3 })
-- Settings → Home key
key("Menu", 4); key("U", 8)
shot("ak-8-settings")
key("Home", 8)
say("after Home in Settings:", function() return EMU.top() end)
shot("ak-9-home-from-settings")
-- sleep: the player pauses (stopped, place kept)
add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("Suspend"))
    E.say("suspended:", state(), "|", gst())
    UIManager:broadcastEvent(Event:new("Resume"))
end, after = 3 })
-- play again from Home (Q = the featured book: the audiobook), then close GZreader
key("Q", 8)
say("reopened:", state)
key("Press", 4)
say("playing again:", function() return state() .. " | " .. gst() end)
add({ fn = function(E)
    require("gzreader_audioctl").stopAll("test: as UIManager:quit does")
    E.say("after close:", state(), "| gst:", gst(), "| saved pos:",
        tostring(require("apps/filemanager/filemanager").instance.gzreader.store.audiobooks["10"].pos_ms))
end, after = 3 })
return s
