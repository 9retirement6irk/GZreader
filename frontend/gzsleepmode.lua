-- GZreader: which sleep screen to show (frontend/ui/screensaver.lua's setup).
-- GZreader's own choice (on by default, gzreader_sleep_auto) is the open
-- book's cover while reading and a picture from the screensavers folder from
-- Home and menus, whatever screensaver_type was saved before (choosing
-- another tile saves one, and choosing GZreader's own again keeps it).
-- KOReader's per-event type (poweroff_/reboot_screensaver_type, Kobo) still
-- comes first; a plain sleep has no prefix, so screensaver_type itself never
-- overrides GZreader's choice (it did before: the saved type showed instead).
--
-- Where the picture comes from (gzreader_sleep_source): the screensavers
-- folder (nil, the default) or the pictures GZreader keeps from an Immich
-- album ("immich": gzreader_immich.lua fills M.immichDir()). With Immich, its
-- pictures come first and the folders are what's left when there are none.
local M = {
    -- the Kindle's own places, after the folder chosen in the settings
    KINDLE_DIRS = { "/mnt/us/screensavers", "/opt/amazon/screen_saver/600x800" },
}

--- `settings`: G_reader_settings; `prefix`: "" for a sleep, "poweroff_" or
--- "reboot_"; `reading`: a book is open.
function M.type(settings, prefix, reading)
    prefix = prefix or ""
    if prefix ~= "" and settings:has(prefix .. "screensaver_type") then
        return settings:readSetting(prefix .. "screensaver_type")
    end
    if settings:nilOrTrue("gzreader_sleep_auto") then
        return reading and "cover" or "random_image"
    end
    return settings:readSetting("screensaver_type")
end

--- Where GZreader keeps the Immich album's pictures (GZreader's own folder).
function M.immichDir()
    if M.IMMICH_DIR then return M.IMMICH_DIR end -- (tests)
    return require("datastorage"):getDataDir() .. "/gzreader-immich"
end

--- "immich" or "folder": where a sleep screen picture comes from.
function M.source(settings)
    return settings:readSetting("gzreader_sleep_source") == "immich" and "immich" or "folder"
end

--- The folders a random sleep screen picture is taken from, in order.
function M.pictureDirs(settings, prefix, kindle)
    prefix = prefix or ""
    local dirs, seen = {}, {}
    local function add(d)
        if type(d) == "string" and d ~= "" and not seen[d] then seen[d] = true; dirs[#dirs + 1] = d end
    end
    if M.source(settings) == "immich" then add(M.immichDir()) end
    add(settings:readSetting(prefix .. "screensaver_dir") or settings:readSetting("screensaver_dir"))
    if kindle then for _i, d in ipairs(M.KINDLE_DIRS) do add(d) end end
    return dirs
end

--- The sleep screen chosen, as Settings → General → Sleep → Wallpaper's
--- tiles name them: "auto" (cover while reading, a picture from the folder
--- elsewhere), "immich_auto" (the same with an Immich picture), "immich" (an
--- Immich picture always), or KOReader's screensaver_type ("cover",
--- "random_image", "readingprogress", "bookstatus", "disable"…).
function M.current(settings)
    local immich = M.source(settings) == "immich"
    if settings:nilOrTrue("gzreader_sleep_auto") then return immich and "immich_auto" or "auto" end
    local t = settings:readSetting("screensaver_type") or "disable"
    if t == "random_image" and immich then return "immich" end
    return t
end

--- Use the sleep screen `id` (one of M.current's names).
function M.use(settings, id)
    if id == "auto" or id == "immich_auto" then
        settings:makeTrue("gzreader_sleep_auto")
    else
        settings:saveSetting("screensaver_type", id == "immich" and "random_image" or id)
        settings:makeFalse("gzreader_sleep_auto")
    end
    if id == "immich" or id == "immich_auto" then
        settings:saveSetting("gzreader_sleep_source", "immich")
    else
        settings:delSetting("gzreader_sleep_source")
    end
end

return M
