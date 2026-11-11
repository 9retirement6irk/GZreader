-- GZreader: the status bars' Wi-Fi item while Wi-Fi is on Auto (GZreader turns
-- it on and off by itself: gzreader_net.lua). The icon still says whether
-- Wi-Fi is on or off right now; an "A" after it says it's automatic.
-- Asked by modules/filebrowser/patches/status_bar.lua (Home, tabs) and
-- modules/reader/patches/reader_top_status_bar.lua (a book's top bar).
local M = {}

M.AUTO_MARK = "A"

--- GZreader's Wi-Fi mode ("on", "off", "auto"), or nil (no GZreader, or a
--- Kindle without Wi-Fi).
function M.mode()
    local Net = package.loaded["gzreader_net"]
    if not Net then
        local ok, mod = pcall(require, "gzreader_net")
        Net = ok and type(mod) == "table" and mod or nil
    end
    if not Net or Net.usb or type(Net.mode) ~= "function" then return nil end
    local ok, m = pcall(Net.mode)
    return ok and m or nil
end

--- What goes after the Wi-Fi icon: the auto mark, or nil.
function M.mark()
    if M.mode() == "auto" then return M.AUTO_MARK end
    return nil
end

return M
