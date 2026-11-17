-- Reset GZreader (gzreader_reset.lua): what goes, what stays, never a folder
-- that holds the program, the wipe after Device:exit's last write, the restart.
--   luajit reset_test.lua <plugins/gzreader.koplugin> <work dir>
local PLUGIN, WORK = arg[1], arg[2]
package.path = PLUGIN .. "/?.lua;" .. package.path
package.preload["libs/libkoreader-lfs"] = function() return require("lfs") end

local passed, failed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end

-- stubs: the log, KOReader's UI
local logged = {}
package.loaded["gzreader_log"] = {
    info = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end,
    warn = function() end, err = function() end, flush = function() end,
}
local shown, timers, restarted = {}, {}, 0
package.loaded["ui/uimanager"] = {
    show = function(_u, w) shown[#shown + 1] = w end,
    forceRePaint = function() end,
    scheduleIn = function(_u, s, fn) timers[#timers + 1] = { s = s, fn = fn } end,
    restartKOReader = function() restarted = restarted + 1 end,
}
package.loaded["ui/widget/infomessage"] = { new = function(_c, o) o.kind = "info"; return o end }
package.loaded["ui/widget/confirmbox"] = { new = function(_c, o) o.kind = "confirm"; return o end }
package.loaded["gettext"] = function(s) return s end
package.loaded["datastorage"] = { getDataDir = function() return "/nowhere" end, getSettingsDir = function() return "/nowhere/settings" end }
package.loaded["device"] = { home_dir = "/nowhere" }
package.loaded["gzreader_secrets"] = { active = function() return false end, DIR = "/nowhere/secrets" }

local lfs = require("lfs")
local Reset = require("gzreader_reset")

local function write(p, s)
    os.execute("mkdir -p '" .. p:match("^(.*)/[^/]*$") .. "'")
    local f = assert(io.open(p, "wb")); f:write(s or "x"); f:close()
end
local function exists(p) return lfs.symlinkattributes(p, "mode") ~= nil end

-- a device: home (the USB drive), koreader/ (program + data), the GZreader folder, the Kindle's own disk
local function device()
    local root = WORK .. "/reset"
    os.execute("rm -rf '" .. root .. "'")
    local d = {
        home = root .. "/mnt/us", data = root .. "/mnt/us/koreader", settings = root .. "/mnt/us/koreader/settings",
        library = root .. "/mnt/us/GZreader", secrets = root .. "/var/local/gzreader",
        program = root .. "/mnt/us/koreader/plugins/gzreader.koplugin",
    }
    for _i, p in ipairs({
        -- go
        "settings.reader.lua", "settings.reader.lua.old", "history.lua",
        "settings/gzreader.lua", "settings/gzreader_recent.lua", "settings/collection.lua",
        "settings/zenos/config.lua", "settings/gzreader-notes.json", "settings/gzreader-drawings/a.png",
        "cache/gzreader-covers/1.jpg", "cache/zen-i18n-en.lua", "screensavers/mine.png",
        "gzreader-remote/spool/1.json", "gzreader-immich-wallpaper.png",
        "settings/statistics.sqlite3", "statistics.sqlite3", "statistics.sqlite3-wal",
        -- stay
        "gzreader.log", "crash.log", "gzreader-version",
        "plugins/gzreader.koplugin/main.lua", "frontend/x.lua",
    }) do write(d.data .. "/" .. p) end
    for _i, p in ipairs({ "Book One.epub", "Book One.sdr/metadata.epub.lua", ".audiobooks/7/a.mp3",
        "Music/Album/1.mp3", ".gzsync/keys.json", ".gzsync/reports/r.txt" }) do write(d.library .. "/" .. p) end
    write(d.secrets .. "/secrets.lua")
    write(d.secrets .. "/gzreader_tokens.pending")
    write(d.home .. "/documents/Own Book.epub") -- (a book the user copied: not GZreader's)
    os.execute("ln -s '" .. d.home .. "/documents' '" .. d.library .. "/link-to-documents'")
    return d
end

-- the folder checks
check(Reset.inside("/mnt/us/koreader", "/mnt/us") and Reset.inside("/mnt/us", "/mnt/us/") and not Reset.inside("/mnt/usb", "/mnt/us"),
    "inside: the folder itself and what's in it, not a name that only starts the same")
local guards = { "/mnt/us/koreader", "/mnt/us" }
check(Reset.safeDir("/mnt/us/GZreader", guards), "the GZreader folder may be emptied")
check(not Reset.safeDir("/", guards) and not Reset.safeDir("/mnt", guards) and not Reset.safeDir("/mnt/us", guards),
    "never /, a top folder or the home folder")
check(not Reset.safeDir("/mnt/us/koreader", guards) and not Reset.safeDir("/mnt/us/koreader/", guards),
    "never the folder that holds the program")
check(not Reset.safeDir("/mnt/us/GZreader/..", guards) and not Reset.safeDir("relative/dir", guards) and not Reset.safeDir(nil, guards),
    "never a path with .., a relative one, or none")

-- the plan
local d = device()
local plugin = { libraryDir = function() return d.library end, path = d.program }
local plan = Reset.plan(plugin, d)
local labels = {}
for _i, e in ipairs(plan.empty) do labels[#labels + 1] = e.label end
check(table.concat(labels, ",") == "settings,cache,screensavers,gzreader-remote,gzreader-usage,docsettings,hashdocsettings,sign-ins,library"
    and plan.library == d.library and #plan.skipped == 0, "the plan: settings, caches, sign-ins, the GZreader folder " .. table.concat(labels, ","))

-- a library set to something that holds the program: left alone
local bad = Reset.plan({ libraryDir = function() return d.home end }, { data = d.data, settings = d.settings, home = d.home, secrets = false })
check(bad.library == nil and bad.skipped[1] == "library", "a GZreader folder that is the home folder: not emptied")
bad = Reset.plan({ libraryDir = function() return d.data .. "/.." end }, { data = d.data, settings = d.settings, home = d.home, secrets = false })
check(bad.library == nil, "…nor one reached through ..")
bad = Reset.plan(nil, { data = d.data, settings = d.data, home = d.home, secrets = false })
check(bad.skipped[1] == "settings", "settings folder = the program's folder: not emptied")

-- the wipe
local removed, nfailed = Reset.wipe(plan)
local gone, stayed = {}, {}
for _i, p in ipairs({ "settings.reader.lua", "settings.reader.lua.old", "history.lua", "settings/gzreader.lua", "settings/gzreader_recent.lua",
    "settings/collection.lua", "settings/zenos", "settings/gzreader-notes.json", "settings/gzreader-drawings",
    "cache/gzreader-covers", "cache/zen-i18n-en.lua", "screensavers/mine.png", "gzreader-remote/spool", "gzreader-immich-wallpaper.png",
    "settings/statistics.sqlite3", "statistics.sqlite3", "statistics.sqlite3-wal" }) do
    if exists(d.data .. "/" .. p) then stayed[#stayed + 1] = p end
end
check(#stayed == 0 and removed > 20 and nfailed == 0, "settings, history, reading statistics (both places), caches, sleep pictures gone (left: " .. table.concat(stayed, ",") .. ")")
for _i, p in ipairs({ "gzreader.log", "crash.log", "gzreader-version", "plugins/gzreader.koplugin/main.lua", "frontend/x.lua" }) do
    if not exists(d.data .. "/" .. p) then gone[#gone + 1] = p end
end
check(#gone == 0, "the program and its logs stay (gone: " .. table.concat(gone, ",") .. ")")
check(lfs.attributes(d.settings, "mode") == "directory" and lfs.attributes(d.data .. "/cache", "mode") == "directory",
    "the folders themselves stay (the Nook's cache is a mount point)")
local left = {}
for name in lfs.dir(d.library) do if name ~= "." and name ~= ".." then left[#left + 1] = name end end
check(#left == 0 and lfs.attributes(d.library, "mode") == "directory", "the GZreader folder emptied, hidden folders too (" .. table.concat(left, ",") .. ")")
check(not exists(d.secrets .. "/secrets.lua") and not exists(d.secrets .. "/gzreader_tokens.pending"),
    "the sign-ins kept off the USB drive gone, and a login a background request got")
check(exists(d.home .. "/documents/Own Book.epub"), "a link in the GZreader folder: removed, not followed (books outside stay)")

-- armed on Device:exit: the wipe comes after its last write
d = device()
plan = Reset.plan(plugin, d)
local Dev = { exit = function(_self) write(d.data .. "/settings.reader.lua", "flushed"); write(d.settings .. "/gzreader.lua", "saved") end }
Reset.arm(plan, Dev)
Reset.arm(plan, Dev) -- (twice: wrapped once)
check(exists(d.data .. "/settings.reader.lua") and exists(d.library .. "/Book One.epub"), "armed: nothing goes before the exit")
Dev:exit()
check(not exists(d.data .. "/settings.reader.lua") and not exists(d.settings .. "/gzreader.lua") and not exists(d.library .. "/Book One.epub")
    and Reset.armed == nil, "Device:exit writes its settings, then the wipe takes them")
write(d.settings .. "/gzreader.lua")
Dev:exit()
check(exists(d.settings .. "/gzreader.lua"), "only once: a later exit wipes nothing")
local failing = { exit = function() error("screen") end }
d = device()
Reset.arm(Reset.plan(plugin, d), failing)
local okx = pcall(failing.exit, failing)
check(not okx and not exists(d.data .. "/settings.reader.lua"), "Device:exit failing: still wiped, the error passed on")

-- the confirmation
local q = Reset.question()
check(q:find("default", 1, true) and q:find("downloaded", 1, true) and q:find("account", 1, true)
    and q:find("setup guide", 1, true) and q:find("reading statistics are removed", 1, true) and q:find("other devices", 1, true),
    "the question says what goes, what stays, and the setup guide")
local box = Reset.confirm(plugin)
check(box.kind == "confirm" and shown[#shown] == box and box.ok_text == "Reset" and restarted == 0 and Reset.armed == nil,
    "Reset GZreader asks first: nothing happens yet")

-- Reset: background work stopped, armed, the book closed, restart
d = device()
package.loaded["datastorage"] = { getDataDir = function() return d.data end, getSettingsDir = function() return d.settings end }
package.loaded["device"] = { home_dir = d.home, exit = function() end }
local stopped, cancelled, terminated, remote_off, book_open = nil, nil, {}, false, true
package.loaded["gzreader_audioctl"] = { stopAll = function(why) stopped = why end }
package.loaded["gzreader_download"] = { cancelActive = function(why) cancelled = why end }
package.loaded["gzreader_async"] = { queue = { {}, {} }, running = { [111] = {}, [222] = {} } }
package.loaded["ffi/util"] = { terminateSubProcess = function(pid) terminated[#terminated + 1] = pid end }
package.loaded["gzreader_remote"] = { stop = function() remote_off = true end }
package.loaded["gzreader_update"] = { closeBook = function() local was = book_open; book_open = false; return was end }
timers = {}
box.ok_callback()
table.sort(terminated)
check(stopped == "reset" and cancelled == "reset" and #terminated == 2 and terminated[1] == 111
    and #package.loaded["gzreader_async"].queue == 0 and remote_off,
    "Reset: audio, the download, background requests and remote debugging stopped")
check(Reset.armed ~= nil and Reset.armed.library == d.library and shown[#shown].kind == "info" and shown[#shown].text:find("setup guide", 1, true),
    "Reset: the wipe armed, a message says it restarts with the setup guide")
check(restarted == 0 and exists(d.library .. "/Book One.epub"), "nothing removed while GZreader still runs")
timers[1].fn()
check(restarted == 0 and #timers == 2, "an open book: closed first")
timers[2].fn()
check(restarted == 1, "then GZreader restarts")
package.loaded["device"]:exit()
check(not exists(d.library .. "/Book One.epub") and not exists(d.settings .. "/gzreader.lua") and not exists(d.settings .. "/statistics.sqlite3"),
    "at the exit: downloads, settings and reading statistics gone")
local said = table.concat(logged, "\n")
check(said:find("reset: done", 1, true) and not said:find("token", 1, true), "the log says it was done (no sign-in in it)")

os.execute("rm -rf '" .. WORK .. "/reset'")
print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
