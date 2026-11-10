-- GZreader: which sleep screen to show (frontend/ui/screensaver.lua's setup).
-- GZreader's own choice (on by default, gzreader_sleep_auto) is the open
-- book's cover while reading and a picture from the screensavers folder from
-- Home and menus, whatever screensaver_type was saved before (choosing
-- another tile saves one, and choosing GZreader's own again keeps it).
-- KOReader's per-event type (poweroff_/reboot_screensaver_type, Kobo) still
-- comes first; a plain sleep has no prefix, so screensaver_type itself never
-- overrides GZreader's choice (it did before: the saved type showed instead).
local M = {}

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

return M
