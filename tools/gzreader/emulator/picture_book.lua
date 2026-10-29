-- Skip the guide, open a picture book (GZ_EMU_BOOK), turn pages. Checks:
-- no "Styles have changed…" box, the page keys turn pages, Back closes it.
local s = {
    start = 12,
    { key = "Back", after = 4 },
    { shot = "01-home" },
    { fn = function(E)
        os.execute("mkdir -p /mnt/us/GZreader && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub") .. " /mnt/us/GZreader/book.epub")
        E.opened_at = os.time()
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 5 },
}
for i = 1, 30 do
    s[#s + 1] = { shot = string.format("02-wait-%02d", i), after = 4 }
end
for i = 1, 6 do
    s[#s + 1] = { key = "RPgFwd", after = 3 }
    s[#s + 1] = { shot = string.format("03-page-%02d", i) }
end
s[#s + 1] = { key = "Back", after = 6 }
s[#s + 1] = { shot = "04-closed" }
return s
