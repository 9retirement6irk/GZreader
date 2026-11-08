-- The Downloads tab names itself in the title bar, like History and the
-- other tabs; inside a folder the title is the folder's name.
--   GZ_EMU_TREE=<tree>/koreader ./run.sh downloads_title.lua <out>
local s = { start = 12, { key = "Back", after = 4 } }
s[#s + 1] = { fn = function()
    os.execute("mkdir -p /mnt/us/GZreader/Series && cp /root/work/demo/lib/1.epub /root/work/demo/lib/2.epub /mnt/us/GZreader/ 2>/dev/null")
end, after = 2 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 10 } -- the Downloads tab
s[#s + 1] = { shot = "downloads" }
s[#s + 1] = { fn = function()
    local fm = require("apps/filemanager/filemanager").instance
    if fm and fm.file_chooser then fm.file_chooser:changeToPath("/mnt/us/GZreader/Series") end
end, after = 6 }
s[#s + 1] = { shot = "folder" }
return s
