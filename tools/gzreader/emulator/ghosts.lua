-- Ghost-process check (run the emulator with setsid, see ghosts.sh):
-- sign in, download and read a book, read aloud, open and close books,
-- play / close / stop an audiobook, browse the Grimmory tab with covers,
-- then restart GZreader with an audiobook playing. Prints every process
-- in the emulator's session at each step.
local s = dofile("/root/work/koreader/tools/gzreader/emulator/readme_shots.lua")
local function add(t) s[#s + 1] = t end
local function snap(label)
    add({ fn = function()
        local sid = os.getenv("GZ_SID") -- ghosts.sh's session (the emulated /proc/self can't tell)
        local p = io.popen("ps -e -o pid=,ppid=,etimes=,sid=,args= 2>/dev/null")
        local out = {}
        for line in p:lines() do
            local fields = { line:match("^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.*)$") }
            if fields[4] == sid and not fields[5]:match("^ps ") and not fields[5]:match("^sh %-c ps") then
                out[#out + 1] = string.format("  %6s %6s %5ss  %s", fields[1], fields[2], fields[3], fields[5]:sub(1, 110))
            end
        end
        p:close()
        print("[emu] PROCS " .. label .. " (" .. #out .. ")\n" .. table.concat(out, "\n"))
    end, after = 1 })
end
snap("after setup, download, reading, read aloud")
-- open and close books from Home a few times
for i = 1, 3 do
    add({ combo = { "Alt", "Q" }, after = 4 })
    add({ key = "Menu", after = 3 })
    add({ key = "W", after = 12 })        -- Continue reading (last book) (Q: Manage when one is highlighted)
    add({ key = "RPgFwd", after = 3 })
    add({ key = "Back", after = 8 })
    if i == 3 then snap("after opening and closing a book 3 times") end
end
-- an audiobook: play, close (keeps playing), reopen, stop
add({ fn = function()
    local plugin = require("apps/filemanager/filemanager").instance.gzreader
    local dir = plugin:libraryDir() .. "/.audiobooks/10"
    os.execute("mkdir -p '" .. dir .. "/audiobook.m4b.chunks'")
    local starts = {}
    for i = 0, 9 do
        local f = io.open(dir .. "/audiobook.m4b.chunks/c" .. i .. ".aac", "wb"); f:write("x"); f:close()
        starts[#starts + 1] = i * 15000
    end
    local f = io.open(dir .. "/audiobook.m4b.chunks/index.json", "wb")
    f:write(require("json").encode({ starts = starts, durationMs = 150000, count = 10 })); f:close()
    f = io.open(dir .. "/audiobook.json", "wb")
    f:write(require("json").encode({ id = "10", title = "A Walk in the Woods", author = "Bill Bryson", durationMs = 150000,
        chapters = { { title = "One", startTimeMs = 0 } }, files = { "audiobook.m4b.chunks/c0.aac" },
        tracks = { { file = "audiobook.m4b", start = 0, durationMs = 150000,
            chunks = { dir = "audiobook.m4b.chunks", starts = starts } } } }))
    f:close()
    plugin.store.audiobooks = plugin.store.audiobooks or {}
    plugin.store.audiobooks["10"] = { title = "A Walk in the Woods", author = "Bill Bryson", pos_ms = 20000 }
    G_reader_settings:saveSetting("gzreader_audio_players", { aac = "aac-mfw", mp3 = "mp3-mfw" })
    require("gzreader_abfolder").start(plugin)
    require("gzreader_abfolder").open(plugin, "10")
end, after = 6 })
snap("audiobook playing")
add({ key = "Back", after = 4 })          -- close, keeps playing
add({ fn = function() require("gzreader_abfolder").open(require("apps/filemanager/filemanager").instance.gzreader, "10") end, after = 5 })
add({ key = "E", after = 6 })             -- Stop
snap("audiobook stopped")
-- pause an audiobook, then open a book: the player must go (read aloud needs the sound device)
add({ fn = function() require("gzreader_abfolder").open(require("apps/filemanager/filemanager").instance.gzreader, "10") end, after = 5 })
add({ key = "Press", after = 3 })         -- pause
add({ key = "Back", after = 3 })
add({ key = "Menu", after = 3 })
add({ key = "W", after = 12 })            -- Continue reading (a book)
snap("audiobook paused, then a book opened")
add({ key = "Back", after = 8 })
-- Grimmory tab with covers
add({ combo = { "Alt", "R" }, after = 8 })
add({ key = "E", after = 15 })            -- All books
add({ key = "RPgFwd", after = 12 })
add({ key = "Back", after = 3 })
add({ key = "Back", after = 3 })
add({ wait = 10 })
snap("after browsing Grimmory with covers")
-- restart GZreader (as an update does) with an audiobook playing
add({ fn = function() require("gzreader_abfolder").open(require("apps/filemanager/filemanager").instance.gzreader, "10") end, after = 6 })
add({ key = "Back", after = 3 })
snap("audiobook playing, just before the restart")
add({ fn = function() require("ui/uimanager"):restartKOReader() end, after = 5 })
return s
