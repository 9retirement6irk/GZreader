-- Home menu → Diagnostics: the choice dialog with letter keys; W saves the
-- log for USB. Then the Reading menu lists Diagnostics too.
return {
    start = 12,
    { key = "Back", after = 4 },
    { key = "Menu", after = 4 },
    { shot = "homemenu" },
    { key = "O", after = 4 }, -- Diagnostics
    { shot = "diagnostics" },
    { key = "W", after = 12 },
    { fn = function(E) print("[emu] after W: " .. E.top()) end, after = 1 },
    { shot = "saved" },
    { key = "Back", after = 3 },
    { fn = function(E)
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/book.epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 15 },
    { key = "Menu", after = 4 },
    { shot = "readmenu" },
}
