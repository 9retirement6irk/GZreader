-- The audiobook player: cover, chapter, progress, controls with letter
-- keys (sleep timer, volume, chapters), then Stop → back to Home.
-- Needs a stand-in gst-launch-0.10 on PATH that just waits (no audio here):
--   printf '#!/bin/sh\nexec sleep 600\n' > /usr/local/bin/gst-launch-0.10
local s = { start = 12, { key = "Back", after = 4 } }
s[#s + 1] = { fn = function(E)
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
    chapters[1].title = "Prologue"
    f = io.open(dir .. "/audiobook.json", "wb")
    f:write(require("json").encode({ id = "10", title = "A Walk in the Woods", author = "Bill Bryson", durationMs = 600000,
        chapters = chapters, files = { "audiobook.m4b.chunks/c0.aac" },
        tracks = { { file = "audiobook.m4b", start = 0, durationMs = 600000,
            chunks = { dir = "audiobook.m4b.chunks", starts = starts } } } }))
    f:close()
    os.execute("cp " .. (os.getenv("GZ_EMU_COVER") or "cover.jpg") .. " '" .. dir .. "/cover.jpg'")
    plugin.store.audiobooks = { ["10"] = { title = "A Walk in the Woods", author = "Bill Bryson", pos_ms = 160000 } }
    G_reader_settings:saveSetting("gzreader_audio_players", { aac = "aac-mfw", mp3 = "mp3-mfw" })
    G_reader_settings:saveSetting("gzreader_tts_volume", 10)
    require("gzreader_abfolder").start(plugin)
    require("gzreader_abfolder").open(plugin, "10")
end, after = 6 }
s[#s + 1] = { shot = "player" }
s[#s + 1] = { key = "W", after = 4 }   -- Sleep timer
s[#s + 1] = { shot = "sleep" }
s[#s + 1] = { key = "W", after = 4 }   -- 30 minutes
s[#s + 1] = { key = "S", after = 3 }   -- Louder
s[#s + 1] = { key = "S", after = 3 }
s[#s + 1] = { fn = function(E) print("[emu] volume: " .. tostring(G_reader_settings:readSetting("gzreader_tts_volume"))) end, after = 1 }
s[#s + 1] = { shot = "player-2" }
s[#s + 1] = { key = "Q", after = 5 }   -- Chapters
s[#s + 1] = { shot = "chapters" }
s[#s + 1] = { key = "Menu", after = 4 } -- the Menu key closes the list
s[#s + 1] = { fn = function(E) print("[emu] after Menu in chapters: " .. E.top()) end, after = 1 }
s[#s + 1] = { key = "E", after = 6 }   -- Stop
s[#s + 1] = { fn = function(E)
    print("[emu] after Stop: " .. E.top() .. " playing: " .. tostring(require("gzreader_audiobook").current))
end, after = 1 }
s[#s + 1] = { shot = "home" }
return s
