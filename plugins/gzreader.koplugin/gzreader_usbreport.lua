--[[
Send to the developer on a Kindle without Wi-Fi (Kindle 2, DX): the report
waits for the sync page.

Diagnostics → Send to the developer asks what happened (the same box as on a
Wi-Fi Kindle: Grimmory:askReportComment), then the diagnostic log is exported
(Log.exportTo: both logs, crash.log's tail, the staying-awake report, the
device probe) into .gzsync/reports/ next to the books:

  report-<n>-<time>.txt   the log, as a Wi-Fi Kindle sends it
  report-<n>-<time>.json  { note, at, version, device, test_build } (written
                          last: the page only sends a report whose .json is there)

<n> is a running number (4 digits), so the names sort oldest first even when
the clock is wrong (a DX's can go back to 1970) or two come in one second.

At the next sync the page (docs/sync/gzsync.js, Report.sendSaved) sends each
one to the developer's report feed in the same parts and with the same
names and tags as gzreader_remote.lua's R.sendLogs, then deletes both
files. Only the newest KEEP reports are kept. The outbox tells the page the
feed and the Kindle's name (Report.outboxInfo), so a test feed
(GZ_REMOTE_FEED) and the device name match a Wi-Fi Kindle's.

Pressing Sync (Usb.show) with diagnostic logging on also exports the log to
reports/latest.txt: the page's Diagnostics box sends that one (the whole
bundle, as a Wi-Fi Kindle would) with what's typed on the page.
]]
local Log = require("gzreader_log")
local JSON = require("json")

local Report = { KEEP = 3, FOLDER = "reports" }

local function lfs() return require("libs/libkoreader-lfs") end

function Report.dir(plugin)
    local dir = require("gzreader_usbsync").dir(plugin) .. "/" .. Report.FOLDER
    if lfs().attributes(dir, "mode") ~= "directory" then lfs().mkdir(dir) end
    return dir
end

local function version()
    local ok, v = pcall(function() return require("gzreader_update").currentVersion() end)
    return ok and v or "?"
end

--- The saved reports' stamps ("<n>-<time>"), oldest first (only those whose
--- .json is there).
function Report.saved(plugin)
    local dir, out = Report.dir(plugin), {}
    for f in lfs().dir(dir) do
        local stamp = f:match("^report%-([%d%-]+)%.json$")
        if stamp then out[#out + 1] = stamp end
    end
    table.sort(out)
    return out
end

--- The next running number: one more than any report's (sent ones are gone).
local function nextNumber(dir)
    local n = 0
    for f in lfs().dir(dir) do
        local k = tonumber(f:match("^report%-(%d%d%d%d)%-"))
        if k and k > n then n = k end
    end
    return n + 1
end

--- Export the log with what was typed, for the page. `export(dir)` makes the
--- log file and returns its path (Log.exportTo by default). Returns the
--- stamp, or nil and an error.
function Report.save(plugin, note, export)
    local dir = Report.dir(plugin)
    export = export or function(d)
        local DataStorage = require("datastorage")
        return Log.exportTo(d, DataStorage:getDataDir() .. "/crash.log")
    end
    local path, err = export(dir)
    if not path then return nil, err end
    local stamp = string.format("%04d-%s", nextNumber(dir) % 10000, os.date("%Y%m%d-%H%M%S"))
    local txt = dir .. "/report-" .. stamp .. ".txt"
    local ok_mv, mv_err = os.rename(path, txt)
    if not ok_mv then os.remove(path); return nil, mv_err end
    local Remote = require("gzreader_remote")
    local v = version()
    note = type(note) == "string" and Log.redact(note):gsub("^%s+", ""):gsub("%s+$", "") or ""
    local meta = { note = note, at = os.time(), version = v, device = Remote.deviceName(),
        test_build = Remote.testBuild(v) == true }
    local f, ferr = io.open(dir .. "/report-" .. stamp .. ".json", "wb")
    if not f then os.remove(txt); return nil, ferr end
    f:write(JSON.encode(meta))
    f:close()
    -- (the newest KEEP only: an old Kindle's drive is small)
    local all = Report.saved(plugin)
    for i = 1, #all - Report.KEEP do
        os.remove(dir .. "/report-" .. all[i] .. ".json")
        os.remove(dir .. "/report-" .. all[i] .. ".txt")
    end
    Log.info("debug report saved for the sync page:", stamp, note ~= "" and "(with a comment)" or "")
    return stamp
end

--- Sync (the quick panel's Sync tile, Usb.show): with diagnostic logging on,
--- the log exported fresh to reports/latest.txt, for the page's Diagnostics
--- box (it sends that rather than the raw log files, and deletes it once
--- sent). Without the device probe (quick: no shell commands). Logging off:
--- an old one is deleted, so the page never sends a stale log.
Report.LATEST = "latest.txt"
function Report.exportForPage(plugin, export)
    local dir = Report.dir(plugin)
    local dest = dir .. "/" .. Report.LATEST
    if not Log.enabled then
        os.remove(dest)
        return nil
    end
    export = export or function(d)
        local DataStorage = require("datastorage")
        local probe = Log.probe_device
        Log.probe_device = false
        local p, e = Log.exportTo(d, DataStorage:getDataDir() .. "/crash.log")
        Log.probe_device = probe
        return p, e
    end
    local path, err = export(dir)
    if not path then return nil, err end
    os.remove(dest)
    local ok, mv_err = os.rename(path, dest)
    if not ok then os.remove(path); return nil, mv_err end
    return dest
end

--- For the outbox (gzreader_usbsync.lua): where the page sends reports, and
--- the name a Wi-Fi Kindle would give this one.
function Report.outboxInfo()
    local ok, info = pcall(function()
        local Remote = require("gzreader_remote")
        local v = version()
        return { feed = Remote.reportUrl(), device = Remote.deviceName(), test_build = Remote.testBuild(v) == true }
    end)
    return ok and info or nil
end

return Report
