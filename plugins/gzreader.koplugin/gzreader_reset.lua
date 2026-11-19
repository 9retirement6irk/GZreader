--[[--
Reset GZreader (Settings → About → Advanced → Reset GZreader): every setting
back to its default, everything downloaded taken off the device, every
account forgotten on it, then a restart into the setup guide.

What goes (`Reset.plan`):
- KOReader's and ZenOS's settings: `settings.reader.lua`, `history.lua`, the
  whole settings folder (GZreader's state with its accounts, ZenOS's config,
  collections, the notes and calendar copies, drawings, the shelf ornaments,
  the reading statistics — in the settings folder or, as KOReader may keep
  them, `statistics.sqlite3` in its own folder);
- the GZreader folder's contents (books, audiobooks, music, the sync page's
  `.gzsync` with its saved keys and reports; from 1.35 GZreader/books, music,
  audiobooks, notes and .gzsync, never GZreader/app) — books elsewhere stay;
- the cache, the sleep screen pictures, the remote debugging spool, the
  Immich wallpaper, KOReader's other book-settings folders;
- on a Kindle, the sign-ins kept off the USB drive (`gzreader_secrets.lua`'s
  folder).
What stays: the program, its logs (gzreader.log, crash.log), books outside
the GZreader folder, the device's own Wi-Fi networks. Accounts are only forgotten
here: nothing is sent to the servers (Grimmory's sign-out would sign out
every device of the user).

When: KOReader writes its settings once more while it quits (Device:exit
flushes settings.reader.lua; the audio stop in UIManager.quit can save
GZreader's state). So `Reset.start` stops what runs in the background,
closes an open book, arms the wipe on Device:exit (after its flush) and
restarts (exit 85: koreader.sh and the Nook's gzreader.sh start GZreader
again). ZenOS then finds no config: a first start, with the setup guide.

Every folder emptied is checked first (`Reset.safeDir`): never `/`, the
device's home folder, or a folder that holds the program.
]]

local Log = require("gzreader_log")

local Reset = {
    armed = nil, -- the plan Device:exit carries out
    wrapped = nil,
    RESTART_DELAY = 1, -- s: the message on screen, the book closed
}

local function lfs() return require("libs/libkoreader-lfs") end

local function trim(p)
    if type(p) ~= "string" or p == "" then return nil end
    p = p:gsub("/+", "/")
    if #p > 1 then p = p:gsub("/$", "") end
    return p
end

--- `p` as a full path. On a Kindle KOReader's own folder is "." (it runs
--- from there) and its settings folder "./settings": relative paths, which
--- `safeDir` refuses, so a reset once emptied only the GZreader folder.
function Reset.absolute(p, cwd)
    if type(p) ~= "string" or p == "" then return nil end
    if p:sub(1, 1) ~= "/" then
        cwd = cwd or lfs().currentdir()
        if type(cwd) ~= "string" or cwd:sub(1, 1) ~= "/" then return nil end
        p = cwd .. "/" .. p
    end
    p = p:gsub("/+", "/")
    repeat local n; p, n = p:gsub("/%./", "/") until n == 0
    p = p:gsub("/%.$", "")
    return p ~= "" and p or "/"
end

--- Is `path` `dir` itself or inside it?
function Reset.inside(path, dir)
    path, dir = trim(path), trim(dir)
    if not path or not dir then return false end
    if dir == "/" then return true end
    return path == dir or path:sub(1, #dir + 1) == dir .. "/"
end

--- May `dir` be emptied? Not `/` or a top folder, not a folder that holds
--- (or is) any of `guards` (the program, the device's home folder…).
function Reset.safeDir(dir, guards)
    dir = trim(dir)
    if not dir or dir:sub(1, 1) ~= "/" or dir:find("/%.%.?/") or dir:find("/%.%.?$") then return false end
    local depth = select(2, dir:gsub("/[^/]+", ""))
    if depth < 2 then return false end -- ("/", "/mnt", "/sdcard")
    for _i, g in ipairs(guards or {}) do
        if Reset.inside(g, dir) then return false end
    end
    return true
end

--- Remove `path` and, if it's a folder, all in it (a link is removed, not followed).
function Reset.removeTree(path)
    local L = lfs()
    local mode = L.symlinkattributes(path, "mode")
    if not mode then return 0, 0 end
    local removed, failed = 0, 0
    if mode == "directory" then
        local r, f = Reset.emptyDir(path)
        removed, failed = removed + r, failed + f
        if L.rmdir(path) then removed = removed + 1 else failed = failed + 1 end
    elseif os.remove(path) then
        removed = removed + 1
    else
        failed = failed + 1
    end
    return removed, failed
end

--- Everything in `dir` (not `dir` itself: it may be a mount point, as the
--- Nook's cache is), except the names in `keep`.
function Reset.emptyDir(dir, keep)
    local L = lfs()
    local removed, failed = 0, 0
    if L.attributes(dir, "mode") ~= "directory" then return 0, 0 end
    local names = {}
    for name in L.dir(dir) do
        if name ~= "." and name ~= ".." and not (keep and keep[name]) then names[#names + 1] = name end
    end
    for _i, name in ipairs(names) do
        local r, f = Reset.removeTree(dir .. "/" .. name)
        removed, failed = removed + r, failed + f
    end
    return removed, failed
end

--- The device's folders (`over` replaces any: the tests).
function Reset.dirs(plugin, over)
    over = over or {}
    local DataStorage = require("datastorage")
    local d = {
        data = over.data or DataStorage:getDataDir(),
        settings = over.settings or DataStorage:getSettingsDir(),
        home = over.home,
        library = over.library,
        secrets = over.secrets,
        program = over.program,
    }
    if d.home == nil then
        local okd, Device = pcall(require, "device")
        d.home = okd and Device.home_dir or nil
    end
    if d.library == nil and plugin and plugin.libraryDir then
        local okl, lib = pcall(plugin.libraryDir, plugin)
        d.library = okl and lib or nil
    end
    if d.secrets == nil then
        local oks, Secrets = pcall(require, "gzreader_secrets")
        if oks and Secrets.active() then d.secrets = Secrets.DIR end
    end
    if d.program == nil and plugin and type(plugin.path) == "string" then
        d.program = plugin.path
    end
    for _i, k in ipairs({ "data", "settings", "home", "library", "secrets", "program" }) do
        if type(d[k]) == "string" then d[k] = Reset.absolute(d[k], over.cwd) end
    end
    return d
end

--- What a reset removes: { files = { path… }, empty = { { dir, keep } … }, library = dir|nil }.
function Reset.plan(plugin, over)
    local d = Reset.dirs(plugin, over)
    local data = trim(d.data)
    local guards = {}
    for _i, g in ipairs({ "data", "program", "home" }) do
        if type(d[g]) == "string" then guards[#guards + 1] = d[g] end
    end
    local plan = { files = {}, empty = {}, skipped = {} }
    local function file(p) plan.files[#plan.files + 1] = p end
    local function empty(dir, keep, label)
        dir = trim(dir)
        if not dir then return end
        if Reset.safeDir(dir, guards) then
            plan.empty[#plan.empty + 1] = { dir = dir, keep = keep, label = label }
        else
            plan.skipped[#plan.skipped + 1] = label or dir
        end
    end
    for _i, name in ipairs({ "settings.reader.lua", "history.lua", "gzreader-immich-wallpaper.png" }) do
        file(data .. "/" .. name)
        file(data .. "/" .. name .. ".old")
    end
    -- the reading statistics where KOReader keeps them by default (ZenOS's db_connection.lua)
    for _i, suffix in ipairs({ "", "-wal", "-shm", "-journal" }) do
        file(data .. "/statistics.sqlite3" .. suffix)
    end
    empty(d.settings, nil, "settings")
    for _i, name in ipairs({ "cache", "screensavers", "gzreader-remote", "gzreader-usage", "docsettings", "hashdocsettings" }) do
        empty(data .. "/" .. name, nil, name)
    end
    if d.secrets then empty(d.secrets, nil, "sign-ins") end
    -- (GZreader in its own folder, 1.35: music, audiobooks, notes and the sync page's
    -- folder beside the books, never the folder itself, which holds the program)
    local root = (over or {}).root or require("gzreader_places").root()
    if root then
        for _i, name in ipairs({ "music", "audiobooks", "notes", ".gzsync" }) do empty(root .. "/" .. name, nil, name) end
    end
    if d.library then
        empty(d.library, nil, "library")
        local last = plan.empty[#plan.empty]
        if last and last.label == "library" then plan.library = trim(d.library) end
    end
    return plan
end

--- Carry out a plan. Returns how many entries went, how many couldn't.
function Reset.wipe(plan)
    local removed, failed = 0, 0
    for _i, p in ipairs(plan.files or {}) do
        if lfs().symlinkattributes(p, "mode") then
            if os.remove(p) then removed = removed + 1 else failed = failed + 1 end
        end
    end
    for _i, e in ipairs(plan.empty or {}) do
        local r, f = Reset.emptyDir(e.dir, e.keep)
        removed, failed = removed + r, failed + f
    end
    return removed, failed
end

--- The wipe, once Device:exit has written the last settings.
function Reset.arm(plan, Device)
    Device = Device or require("device")
    Reset.armed = plan
    if Reset.wrapped == Device then return end
    Reset.wrapped = Device
    local orig = Device.exit
    Device.exit = function(dev, ...)
        local ok, err = pcall(orig, dev, ...)
        local p = Reset.armed
        if p then
            Reset.armed = nil
            local okw, removed, failed = pcall(Reset.wipe, p)
            pcall(Log.info, "reset: done,", okw and removed or "?", "removed,",
                okw and failed or tostring(removed), "couldn't be")
            pcall(Log.flush)
        end
        if not ok then error(err, 0) end
    end
end

--- Stop what writes in the background: playing audio, a download, the
--- requests running in other processes, remote debugging.
function Reset.stopWork()
    pcall(function() require("gzreader_audioctl").stopAll("reset") end)
    local Download = package.loaded["gzreader_download"]
    if Download then pcall(Download.cancelActive, "reset") end
    local Async = package.loaded["gzreader_async"]
    if Async then
        Async.queue = {}
        local ffiutil = require("ffi/util")
        for pid in pairs(Async.running or {}) do pcall(ffiutil.terminateSubProcess, pid) end
        Async.running = {}
    end
    local R = package.loaded["gzreader_remote"]
    if R and R.stop then pcall(R.stop) end
end

--- Reset now (the user said yes): stop, arm, close the book, restart.
function Reset.start(plugin)
    local UIManager = require("ui/uimanager")
    local plan = Reset.plan(plugin)
    Log.info("reset: settings, downloads and accounts go at the restart;", #plan.empty, "folders to empty",
        #plan.skipped > 0 and ("(left alone: " .. table.concat(plan.skipped, ", ") .. ")") or "")
    pcall(Log.flush)
    Reset.stopWork()
    Reset.arm(plan)
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    UIManager:show(InfoMessage:new{ text = _("Resetting GZreader…\nIt restarts with the setup guide.") })
    UIManager:forceRePaint()
    local closed = false
    local function restart()
        if not closed then
            closed = true
            local okc, was_open = pcall(function() return require("gzreader_update").closeBook() end)
            if okc and was_open then return UIManager:scheduleIn(Reset.RESTART_DELAY, restart) end
        end
        UIManager:restartKOReader()
    end
    UIManager:scheduleIn(Reset.RESTART_DELAY, restart)
    return plan
end

--- What the confirmation says.
function Reset.question()
    local _ = require("gettext")
    return _("Reset GZreader?") .. "\n\n"
        .. _("• Every setting goes back to its default.") .. "\n"
        .. _("• Every downloaded book, audiobook and song is removed from this device (the GZreader folder is emptied).") .. "\n"
        .. _("• Every account is forgotten on this device: Grimmory, Plex, Memos, calendars, Home Assistant, Immich. Your servers and your other devices aren't touched.") .. "\n\n"
        .. _("Your reading statistics are removed too. Changes not sent yet (reading progress, notes) are lost. Books outside the GZreader folder stay.") .. "\n\n"
        .. _("GZreader then restarts with the setup guide.")
end

--- Settings → About → Advanced → Reset GZreader.
function Reset.confirm(plugin)
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local _ = require("gettext")
    local box = ConfirmBox:new{
        text = Reset.question(),
        ok_text = _("Reset"),
        cancel_text = _("Cancel"),
        ok_callback = function() Reset.start(plugin) end,
    }
    UIManager:show(box)
    return box
end

return Reset
