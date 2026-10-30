-- GZreader: the Kindle Keyboard has no Bluetooth. ZenOS's Bluetooth support
-- (Kobo, PocketBook and newer Kindles) asked the Kindle for its Bluetooth
-- state by starting `lipc-get-prop` in a shell every time the status bar,
-- quick panel or settings checked it, a process start each time on a
-- Kindle 3. This stub keeps the same interface and reports "no Bluetooth".
local M = {}

function M.getState() return nil end
function M.getCachedState() return nil end
function M.isAvailable() return false end
function M.isEnabled() return false end
function M.isChanging() return false end
function M.setEnabled(_enabled, complete) if complete then complete(false) end end
function M.toggle(complete) if complete then complete(false) end end
function M.logState() return nil end
function M.onSuspend() end

return M
