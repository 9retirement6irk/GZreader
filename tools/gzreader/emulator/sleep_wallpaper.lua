-- Settings → General → Sleep → Wallpaper: the sleep screens as tiles with
-- previews (gzreader_sleeppreview.lua). A book read first (for its cover),
-- a picture in the screensavers folder. Shots: sleep-menu, wallpaper-tiles,
-- wallpaper-chosen (after picking "Book cover"). Prints "[emu] wallpaper: …".
--   GZ_EMU_BOOK=<an EPUB> GZ_EMU_TREE=<tree>/koreader run.sh sleep_wallpaper.lua <out>
local function settings(path)
    return function(_E)
        local fm = require("apps/filemanager/filemanager").instance
        local plugin = fm.zenos or rawget(_G, "__ZEN_UI_PLUGIN")
        local Page = require("modules/settings/zen_settings_page")
        Page.closeActive()
        local markers = {}
        for _i, t in ipairs(path) do markers[#markers + 1] = { key = "text", value = t } end
        Page.show(plugin, { path = markers })
    end
end
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function(_E)
        os.execute("mkdir -p /mnt/us/GZreader /mnt/us/screensavers && cp " .. (os.getenv("GZ_EMU_BOOK") or "book.epub")
            .. " /mnt/us/GZreader/book.epub && cp resources/koreader.png /mnt/us/screensavers/a.png")
        require("apps/reader/readerui"):showReader("/mnt/us/GZreader/book.epub")
    end, after = 15 },
    { fn = function(_E)
        local R = require("apps/reader/readerui").instance
        if R then R:onHome() end
    end, after = 12 },
    { fn = settings({ "General", "Sleep" }), after = 6 },
    { shot = "sleep-menu" },
    { fn = function(_E)
        local P = require("gzreader_sleeppreview")
        P.show(function(id) print("[emu] wallpaper: chose " .. id) end)
        print("[emu] wallpaper: in use " .. P.current())
        local labels = {}
        for _i, c in ipairs(P.choices()) do labels[#labels + 1] = c.id .. (c.enabled and "" or " (off)") end
        print("[emu] wallpaper: tiles " .. table.concat(labels, ", "))
    end, after = 12 },
    { shot = "wallpaper-tiles" },
    { fn = function(_E)
        local P = require("gzreader_sleeppreview")
        for _i, p in ipairs(P.open and P.open.placed or {}) do
            if p.tile.choice == "cover" then p.tile:onTapTile() end
        end
        print("[emu] wallpaper: now " .. P.current() .. ", open " .. tostring(P.open ~= nil))
        P.show()
    end, after = 10 },
    { shot = "wallpaper-chosen" },
}
