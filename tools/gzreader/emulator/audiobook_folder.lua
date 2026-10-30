-- Audiobooks in the Downloads tab: an audiobook in the old (visible) layout is
-- moved to the hidden folder, and opening Downloads → Audiobooks lists it.
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
    f:write(require("json").encode({ id = 10, title = "A Walk in the Woods", durationMs = 60000,
        files = { "audiobook.m4b.chunks/c0.aac" },
        tracks = { { file = "audiobook.m4b", start = 0, durationMs = 60000,
            chunks = { dir = "audiobook.m4b.chunks", starts = { 0, 15000, 30000, 45000 } } } } }))
    f:close()
    plugin.store.audiobooks = { [10] = { title = "A Walk in the Woods", pos_ms = 20000 } }
    require("gzreader_abfolder").start(plugin)
    local lfs = require("libs/libkoreader-lfs")
    print("[emu] moved: " .. tostring(lfs.attributes(lib .. "/.audiobooks/10/audiobook.json", "mode"))
        .. ", old left: " .. tostring(lfs.attributes(dir, "mode"))
        .. ", entry folder: " .. tostring(lfs.attributes(lib .. "/Audiobooks", "mode")))
end, after = 2 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 6 }
s[#s + 1] = { shot = "downloads" }
s[#s + 1] = { key = "Q", after = 5 } -- the Audiobooks folder
s[#s + 1] = { fn = function(E) print("[emu] after opening Audiobooks: " .. E.top()) end, after = 1 }
s[#s + 1] = { shot = "audiobooks" }
s[#s + 1] = { key = "Back", after = 3 }
s[#s + 1] = { fn = function(E)
    print("[emu] after Back: " .. E.top() .. " path " .. tostring(require("apps/filemanager/filemanager").instance.file_chooser.path))
end, after = 1 }
return s
