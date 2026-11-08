-- Home's status bar: across the top with no book read yet, beside the book
-- once one has been read, across the top again when it's gone from the
-- history (common/gz_home_status.lua). Shots: home-no-book, home-book,
-- home-history-cleared.
return {
    start = 12,
    { key = "Back", after = 4 },
    { shot = "home-no-book" },
    { fn = function(_E)
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/book.epub")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 15 },
    { key = "RPgFwd", after = 3 },
    { key = "Back", after = 10 },
    { shot = "home-book" },
    { fn = function(_E)
        require("readhistory"):removeItemByPath("/mnt/us/GZreader/book.epub")
        local fm = require("apps/filemanager/filemanager").instance
        local Home = require("common/shared_state").get(fm and fm.zenos, "home")
        Home.invalidateBookCache("/mnt/us/GZreader/book.epub", true)
        Home.invalidateLibraryCache()
        Home.rebuildActive()
    end, after = 8 },
    { shot = "home-history-cleared" },
}
