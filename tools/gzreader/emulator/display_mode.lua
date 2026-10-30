-- Downloads as tiles, then Menu → Display → List with details.
local s = { start = 12, { key = "Back", after = 4 } }
s[#s + 1] = { fn = function(E)
    os.execute("mkdir -p /mnt/us/GZreader && cp /root/work/demo/lib/1.epub /root/work/demo/lib/2.epub /root/work/demo/lib/3.epub /mnt/us/GZreader/")
    require("gzreader_homemenu").setDisplayMode("mosaic_image")
end, after = 3 }
s[#s + 1] = { combo = { "Alt", "W" }, after = 10 }
s[#s + 1] = { shot = "tiles" }
s[#s + 1] = { key = "Menu", after = 4 }
s[#s + 1] = { shot = "menu" }
s[#s + 1] = { key = "Y", after = 4 } -- Display (Q is Manage: a book is highlighted)
s[#s + 1] = { shot = "display" }
s[#s + 1] = { key = "Q", after = 10 }
s[#s + 1] = { fn = function(E) print("[emu] mode now: " .. require("gzreader_homemenu").displayMode()) end, after = 1 }
s[#s + 1] = { shot = "list" }
return s
