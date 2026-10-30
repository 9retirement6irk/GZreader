-- Audiobooks as tiles: an audiobook in the old layout gets a stand-in book
-- (with a cover), shown in Downloads → Audiobooks; opening it starts the
-- player; afterwards it's in Recent on Home. GZ_EMU_COVER: a JPEG cover.
local s = { start = 12, { key = "Back", after = 4 } }
s[#s + 1] = { fn = function(E)
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local lib = plugin:libraryDir()
    local dir = lib .. "/Audiobooks/10"
    os.execute("mkdir -p '" .. dir .. "/audiobook.m4b.chunks'")
    for i = 0, 3 do
        local f = io.open(dir .. "/audiobook.m4b.chunks/c" .. i .. ".aac", "wb"); f:write("x"); f:close()
    end
    local f = io.open(dir .. "/audiobook.m4b.chunks/index.json", "wb")
    f:write('{"starts":[0,15000,30000,45000],"durationMs":60000,"count":4}'); f:close()
    f = io.open(dir .. "/audiobook.json", "wb")
    f:write(require("json").encode({ id = "10", title = "A Walk in the Woods", author = "Bill Bryson", durationMs = 3600000,
        files = { "audiobook.m4b.chunks/c0.aac" },
        tracks = { { file = "audiobook.m4b", start = 0, durationMs = 3600000,
            chunks = { dir = "audiobook.m4b.chunks", starts = { 0, 15000, 30000, 45000 } } } } }))
    f:close()
    os.execute("cp " .. (os.getenv("GZ_EMU_COVER") or "cover.jpg") .. " '" .. dir .. "/cover.jpg'")
    plugin.store.audiobooks = { ["10"] = { title = "A Walk in the Woods", author = "Bill Bryson", pos_ms = 1200000 } }
    G_reader_settings:saveSetting("gzreader_audio_players", { aac = "aac-mfw", mp3 = "mp3-mfw" })
    require("gzreader_abfolder").start(plugin)
    local lfs = require("libs/libkoreader-lfs")
    print("[emu] stand-in: " .. tostring(lfs.attributes(lib .. "/Audiobooks/A Walk in the Woods.epub", "size")) .. " bytes")
end, after = 2 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 6 }
s[#s + 1] = { shot = "downloads" }
s[#s + 1] = { key = "Q", after = 8 } -- the Audiobooks folder
s[#s + 1] = { shot = "audiobooks" }
s[#s + 1] = { key = "Q", after = 8 } -- the audiobook's tile
s[#s + 1] = { fn = function(E) print("[emu] after opening the tile: " .. E.top()) end, after = 1 }
s[#s + 1] = { shot = "player" }
s[#s + 1] = { wait = 8 }
s[#s + 1] = { key = "Back", after = 3 }
s[#s + 1] = { key = "Back", after = 3 }
s[#s + 1] = { combo = { "Alt", "Q" }, after = 8 }
s[#s + 1] = { fn = function(E)
    print("[emu] home: " .. E.top())
    local RH = require("readhistory")
    print("[emu] history: " .. #(RH.hist or {}) .. " " .. tostring(RH.hist and RH.hist[1] and RH.hist[1].file))
    local LP = require("common/library_paths")
    print("[emu] in home dir: " .. tostring(LP.isInHomeDir("/mnt/us/GZreader/Audiobooks/A Walk in the Woods.epub")))
    local zen = rawget(_G, "__ZEN_UI_PLUGIN")
    print("[emu] home module: " .. tostring(zen and require("common/shared_state").get(zen, "home")))
end, after = 1 }
s[#s + 1] = { shot = "home" }
return s
