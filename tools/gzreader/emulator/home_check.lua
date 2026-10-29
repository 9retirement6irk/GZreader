-- Skip the guide, read a page of a book (GZ_EMU_BOOK), back to Home: Home shots.
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function(E)
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/book.epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 15 },
    { key = "RPgFwd", after = 3 },
    { key = "RPgFwd", after = 3 },
    { key = "Back", after = 10 },
    { shot = "home" },
    { key = "Menu", after = 4 },
    { shot = "home-menu" },
}
