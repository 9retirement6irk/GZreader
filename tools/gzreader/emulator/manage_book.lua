-- Home menu "Manage <book>": ZenOS's book menu with Open and Delete on top,
-- and letter shortcuts in it (GZ_EMU_BOOK: an EPUB to read first).
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function(E)
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/book.epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 15 },
    { key = "RPgFwd", after = 3 },
    { key = "Back", after = 10 },
    { key = "Down", after = 3 },
    { shot = "home-focus" },
    { key = "Menu", after = 4 },
    { shot = "home-menu" },
    { key = "Q", after = 5 },
    { shot = "manage" },
    { key = "R", after = 4 },
    { shot = "manage-collection" },
    { key = "Back", after = 3 },
    { key = "Back", after = 3 },
    { key = "Down", after = 3 },
    { key = "Menu", after = 4 },
    { key = "Q", after = 5 },
    { key = "Q", after = 15 },
    { fn = function(E) print("[emu] after Open: " .. E.top()) end, after = 1 },
}
