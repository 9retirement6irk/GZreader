-- Pause an audiobook, then open a book: the player process must be gone
-- (the Kindle voice needs the sound device). Run with GZ_SID set (ghosts.sh).
local s = { start = 12, { key = "Back", after = 4 } }
local function procs(label)
    return { fn = function()
        local sid = os.getenv("GZ_SID")
        local p = io.popen("ps -e -o pid=,ppid=,etimes=,sid=,args= 2>/dev/null")
        local out = {}
        for line in p:lines() do
            local f = { line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.*)$") }
            if f[4] == sid and f[5]:match("gst%-launch") then out[#out + 1] = "  " .. f[1] .. " " .. f[5] end
        end
        p:close()
        print("[emu] PLAYERS " .. label .. " (" .. #out .. ")\n" .. table.concat(out, "\n"))
    end, after = 1 }
end
s[#s + 1] = { fn = function()
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local dir = plugin:libraryDir() .. "/.audiobooks/10"
    os.execute("mkdir -p '" .. dir .. "/audiobook.m4b.chunks'")
    for i = 0, 3 do local f = io.open(dir .. "/audiobook.m4b.chunks/c" .. i .. ".aac", "wb"); f:write("x"); f:close() end
    local f = io.open(dir .. "/audiobook.m4b.chunks/index.json", "wb")
    f:write('{"starts":[0,15000,30000,45000],"durationMs":60000,"count":4}'); f:close()
    f = io.open(dir .. "/audiobook.json", "wb")
    f:write(require("json").encode({ id = "10", title = "A Walk in the Woods", durationMs = 600000,
        files = { "audiobook.m4b.chunks/c0.aac" }, tracks = { { file = "audiobook.m4b", start = 0, durationMs = 600000,
        chunks = { dir = "audiobook.m4b.chunks", starts = { 0, 15000, 30000, 45000 } } } } }))
    f:close()
    plugin.store.audiobooks = { ["10"] = { title = "A Walk in the Woods", pos_ms = 20000 } }
    G_reader_settings:saveSetting("gzreader_audio_players", { aac = "aac-mfw", mp3 = "mp3-mfw" })
    os.execute("mkdir -p /mnt/us/GZreader && cp /root/work/demo/lib/1.epub /mnt/us/GZreader/book.epub")
    require("gzreader_abfolder").start(plugin)
    require("gzreader_abfolder").open(plugin, "10")
end, after = 6 }
s[#s + 1] = procs("playing")
s[#s + 1] = { key = "Press", after = 3 }  -- pause
s[#s + 1] = { key = "Back", after = 3 }
s[#s + 1] = procs("paused, player closed")
s[#s + 1] = { fn = function() require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub") end, after = 15 }
s[#s + 1] = procs("after opening a book")
return s
