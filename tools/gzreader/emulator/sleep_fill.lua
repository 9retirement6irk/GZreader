-- Wallpaper options → Scale cover to fill screen (frontend/gzsleepfit.lua):
-- the sleep screen set to a picture from the screensavers folder (here
-- a wide mid-grey one), first as it was (fitted, black bars above and
-- below), then filling the screen. Reads what the e-ink panel shows
-- (E.display) at the top edge and the middle. Shots: sleep-fit, sleep-fill.
-- Prints "[emu] sleep fill: …".
--   GZ_EMU_PICTURE=<a wide PNG> GZ_EMU_TREE=<tree>/koreader run.sh sleep_fill.lua <out>
local function grey(E, x, y)
    return E.display:getPixel(x, y):getColor8().a
end
local function sleep(fill)
    return function(_E)
        G_reader_settings:saveSetting("gzreader_sleep_auto", false)
        G_reader_settings:saveSetting("screensaver_type", "random_image")
        G_reader_settings:saveSetting("screensaver_img_background", "black")
        G_reader_settings:makeFalse("screensaver_stretch_images")
        if fill then G_reader_settings:makeTrue("gzreader_sleep_fill") else G_reader_settings:delSetting("gzreader_sleep_fill") end
        local Screensaver = require("ui/screensaver")
        Screensaver:setup()
        print(("[emu] sleep fill: showing %s %s"):format(tostring(Screensaver.screensaver_type),
            tostring(Screensaver.image_file)))
        Screensaver:show()
    end
end
local function measure(name)
    return function(E)
        local Screen = require("device").screen
        local w, h = Screen:getWidth(), Screen:getHeight()
        print(("[emu] sleep fill: %s top %d, middle %d, bottom %d, left %d"):format(name,
            grey(E, math.floor(w / 2), 3), grey(E, math.floor(w / 2), math.floor(h / 2)),
            grey(E, math.floor(w / 2), h - 4), grey(E, 3, math.floor(h / 2))))
        require("ui/screensaver"):close()
    end
end
return {
    start = 12,
    { key = "Back", after = 4 },
    { fn = function(_E)
        os.execute("rm -rf /mnt/us/screensavers && mkdir -p /mnt/us/screensavers && cp "
            .. (os.getenv("GZ_EMU_PICTURE") or "wide.png") .. " /mnt/us/screensavers/wide.png")
    end, after = 2 },
    { fn = sleep(false), after = 8 },
    { shot = "sleep-fit" },
    { fn = measure("fit"), after = 6 },
    { fn = sleep(true), after = 8 },
    { shot = "sleep-fill" },
    { fn = measure("fill"), after = 6 },
}
