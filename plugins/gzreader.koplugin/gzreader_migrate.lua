--[[--
Moving GZreader out of KOReader's folder into its own (1.35), once.

Until 1.35 GZreader was installed in KOReader's place (Kindle: /mnt/us/koreader;
Kobo: /mnt/onboard/.adds/koreader), its books straight in the GZreader folder,
music and audiobooks hidden in it (.music, .audiobooks), and Notes in its
settings and cache. From 1.35 everything is in one GZreader folder, beside
KOReader (gzreader_places.lua):

  GZreader/app  GZreader/books  GZreader/music  GZreader/audiobooks  GZreader/notes

The first start after the update does the move, from reader.lua, before
anything else has opened a file: the books, music, audiobooks and notes are
renamed into place (the same drive: no copying, however big), every saved
path to them is rewritten (KOReader's settings, reading history,
collections, GZreader's own state, ZenOS's), GZreader's launchers are
pointed at the new place, and last the program's own folder is renamed to
GZreader/app. The start goes on from there: the running program's folder
moves with it.

Each step can be done again: a move cut short (the battery ran out) is
finished at the next start; a path already rewritten isn't rewritten twice.
Nothing is deleted but GZreader's own old launchers (KUAL's and launchpad's
"koreader" entries when they're GZreader's) and caches kept by path.

  M.early()    from reader.lua (the device's own places)
  M.run(opts)  { home, app, lib }: the drive, the program's folder, the old GZreader folder
]]

local lfs = require("libs/libkoreader-lfs")

local M = {
    -- the program's old places, by device: the drive and KOReader's folder on it
    LEGACY = {
        { home = "/mnt/us", app = "/mnt/us/koreader", device = "kindle" },
        { home = "/mnt/onboard", app = "/mnt/onboard/.adds/koreader", device = "kobo" },
    },
    FOLDER = "GZreader",
    -- the Nook: its program stays on its own disk (/data, programs can't run from the
    -- card); the rest moves into GZreader/ on the card, and this says it's done
    NOOK_DONE = "settings/gzreader-folder.done",
    -- names in the old GZreader folder that aren't books (the new folders, and those moved apart)
    -- (.gzsync: the sync page's, stays at the top of the GZreader folder)
    NOT_BOOKS = { app = true, books = true, music = true, audiobooks = true, notes = true, [".music"] = true, [".audiobooks"] = true,
        [".gzsync"] = true },
    MAX_FILE = 8 * 1024 * 1024, -- (a saved file larger than this isn't a settings file: left as it is)
    log = nil, -- function(text): where the steps are told (stderr: crash.log)
}

local function say(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    local text = "GZreader move: " .. table.concat(parts, " ")
    if M.log then M.log(text) else io.stderr:write(text, "\n") end
end

local function mode(p) return lfs.attributes(p, "mode") end
local function isDir(p) return mode(p) == "directory" end

local function mkdirp(p)
    local acc = p:sub(1, 1) == "/" and "" or "."
    for part in p:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if not mode(acc) then lfs.mkdir(acc) end
    end
    return isDir(p)
end

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function writeFile(p, s)
    local tmp = p .. ".gzmove"
    local f = io.open(tmp, "wb")
    if not f then return false end
    local ok = f:write(s)
    f:close()
    if not ok then os.remove(tmp); return false end
    return os.rename(tmp, p) ~= nil
end

--- A file copied (another disk); true when the copy is whole.
function M.copyFile(from, to)
    local f = io.open(from, "rb")
    if not f then return false end
    local tmp = to .. ".gzmove"
    local o = io.open(tmp, "wb")
    if not o then f:close(); return false end
    local ok = true
    while ok do
        local chunk = f:read(65536) -- (in pieces: an audiobook is larger than the Nook's memory)
        if not chunk then break end
        ok = o:write(chunk) and true or false
    end
    f:close()
    o:close()
    if not ok or lfs.attributes(tmp, "size") ~= lfs.attributes(from, "size") then os.remove(tmp); return false end
    return os.rename(tmp, to) ~= nil
end

--- `from` to `to`: renamed (the same drive). A folder whose place is taken
--- already: its insides moved one by one (a move cut short, done again).
function M.move(from, to)
    if not mode(from) then return true end
    if not mode(to) then
        local ok, err = os.rename(from, to)
        if ok then return true end
        -- (another disk: the Nook's /data to its card; copied, checked, then the old one removed)
        if isDir(from) then
            if lfs.mkdir(to) then return M.move(from, to) end
        elseif mode(from) == "file" and M.copyFile(from, to) then
            os.remove(from)
            return true
        end
        say("couldn't move", from, "→", to, tostring(err))
        return false
    end
    if isDir(from) and isDir(to) then
        local all = true
        for name in lfs.dir(from) do
            if name ~= "." and name ~= ".." then
                all = M.move(from .. "/" .. name, to .. "/" .. name) and all
            end
        end
        if all then lfs.rmdir(from) end
        return all
    end
    say("left as it is (both there):", from, to)
    return false
end

--- The rules for a saved path, most particular first: { old prefix, new prefix }.
function M.rules(o)
    local R = o.root
    return {
        { o.lib .. "/.music", R .. "/music" },
        { o.lib .. "/.audiobooks", R .. "/audiobooks" },
        { o.app .. "/settings/gzreader-drawings", R .. "/notes/drawings" },
        { "./settings/gzreader-drawings", R .. "/notes/drawings" },
        { o.app .. "/cache/gzreader-notes", R .. "/notes/files" },
        { "./cache/gzreader-notes", R .. "/notes/files" },
        -- (the Nook's program stays where it is: a rule that changes nothing)
        o.keep_app and { false } or { o.app, R .. "/app" },
        { o.lib, R .. "/books" },
    }
end

--- A saved path, as it is after the move (nil: not one of the moved ones).
function M.mapPath(s, rules, root)
    -- (already in the new places: as it is, so a file rewritten twice stays right)
    for _i, n in ipairs({ "/app", "/books", "/music", "/audiobooks", "/notes" }) do
        local p = root .. n
        if s == p or s:sub(1, #p + 1) == p .. "/" then return nil end
    end
    for _i, r in ipairs(rules) do
        local old, new = r[1], r[2]
        if r and old then
            if s == old then return new end
            if s:sub(1, #old + 1) == old .. "/" then return new .. s:sub(#old + 1) end
        end
    end
    return nil
end

--- The text of a saved file (Lua or JSON), its quoted paths rewritten. The text, how many.
function M.rewriteText(text, rules, root)
    local n = 0
    local out = text:gsub('"([^"\n]*)"', function(str)
        -- (JSON may write / as \/)
        local plain = str:gsub("\\/", "/")
        local new = M.mapPath(plain, rules, root)
        if not new then return nil end
        n = n + 1
        if plain ~= str then new = new:gsub("/", "\\/") end
        return '"' .. new .. '"'
    end)
    return out, n
end

--- Every settings file under `dir` (Lua or JSON, not too big), its paths rewritten.
--- (`sdr`: only inside books' .sdr folders, the books' own files left alone)
local function rewriteTree(dir, rules, root, depth, done, sdr)
    if depth > 4 or not isDir(dir) then return end
    local in_sdr = not sdr or dir:match("%.sdr$") ~= nil
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local p = dir .. "/" .. name
            local m = mode(p)
            if m == "directory" and not name:match("^gzreader%-drawings$") then
                rewriteTree(p, rules, root, depth + 1, done, sdr)
            elseif m == "file" and in_sdr and (name:match("%.lua$") or name:match("%.json$")) and not name:match("%.old$")
                    and (lfs.attributes(p, "size") or 0) <= M.MAX_FILE then
                local text = readFile(p)
                if text then
                    local new, n = M.rewriteText(text, rules, root)
                    if n > 0 and writeFile(p, new) then
                        done.files = done.files + 1
                        done.paths = done.paths + n
                    end
                end
            end
        end
    end
end

local function copyFile(from, to)
    local s = readFile(from)
    if not s then return false end
    local ok = writeFile(to, s)
    pcall(function() if lfs.attributes(from, "permissions"):match("x") then os.execute("chmod 755 '" .. to .. "'") end end)
    return ok
end

local function copyTree(from, to)
    if not isDir(from) then return copyFile(from, to) end
    mkdirp(to)
    for name in lfs.dir(from) do
        if name ~= "." and name ~= ".." then copyTree(from .. "/" .. name, to .. "/" .. name) end
    end
    return true
end

local function rmTree(p)
    if isDir(p) then
        for name in lfs.dir(p) do
            if name ~= "." and name ~= ".." then rmTree(p .. "/" .. name) end
        end
        lfs.rmdir(p)
    elseif mode(p) then
        os.remove(p)
    end
end

--- KUAL's entry for GZreader there, starting GZreader/app's koreader.sh itself
--- (as KOReader's own entry does: nothing in between)?
M.KUAL_ACTION = "/mnt/us/GZreader/app/koreader.sh"
function M.kualReady(home)
    local menu = readFile(home .. "/extensions/gzreader/menu.json")
    return menu ~= nil and menu:find('"' .. M.KUAL_ACTION .. '"', 1, true) ~= nil
        and not menu:find("bin/start.sh", 1, true) and mode(home .. "/extensions/gzreader/config.xml") == "file"
end

--- GZreader's launchers pointed at GZreader/app (KOReader's own are left alone).
function M.launchers(o)
    local here = o.app .. "/plugins/gzreader.koplugin/launchers"
    local home = o.home
    if o.device == "kindle" then
        -- KUAL: GZreader's own entry (extensions/gzreader); the old one was in KOReader's place
        if isDir(home .. "/extensions") then
            local old = home .. "/extensions/koreader"
            local menu = readFile(old .. "/menu.json")
            if menu and menu:find("GZreader", 1, true) then rmTree(old); say("removed GZreader's old KUAL entry (extensions/koreader)") end
            copyTree(here .. "/kindle/extensions/gzreader", home .. "/extensions/gzreader")
            say("KUAL entry:", M.kualReady(home) and "extensions/gzreader, to GZreader/app" or "extensions/gzreader NOT written")
        end
        -- the Kindle 2/3/DX's launchpad
        if isDir(home .. "/launchpad") then
            local old = home .. "/launchpad/koreader.ini"
            local ini = readFile(old)
            if ini and ini:find("GZreader", 1, true) then os.remove(old) end
            copyFile(here .. "/kindle/launchpad/gzreader.ini", home .. "/launchpad/gzreader.ini")
        end
        -- the Kindle's home screen item (ZenOS's kindle-launcher: documents/GZreader.sh)
        local doc = home .. "/documents/GZreader.sh"
        if mode(doc) == "file" then
            copyFile(o.app .. "/plugins/zenos.koplugin/kindle-launcher/GZreader.sh", doc)
        end
    elseif o.device == "kobo" then
        local nm = home .. "/.adds/nm/gzreader"
        if mode(nm) == "file" then copyFile(here .. "/kobo/nm/gzreader", nm) end
        local kf = home .. "/.adds/kfmon/config/gzreader.ini"
        if mode(kf) == "file" then copyFile(here .. "/kobo/kfmon/gzreader.ini", kf) end
    end
end

--- A Kobo: Nickel's library leaves GZreader's own folders alone (the
--- program, its notes, music and audiobooks), as it leaves hidden folders:
--- its ExcludeSyncFolders setting, in [FeatureSettings] of `conf` (Nickel isn't
--- running while GZreader is; it reads it at its next start). True when changed.
M.KOBO_EXCLUDE = "GZreader/(app|notes|music|audiobooks)(/.*)?"
M.KOBO_DEFAULT = "(\\\\.(?!kobo|adobe).+|([^.][^/]*/)+\\\\..+)"
function M.koboExclude(conf)
    local text = readFile(conf)
    if not text then return false end
    if text:find(M.KOBO_EXCLUDE, 1, true) then return false end
    local lines, found, section, insert_at = {}, false, nil, nil
    for line in (text .. (text:sub(-1) == "\n" and "" or "\n")):gmatch("([^\n]*)\n") do
        local sec = line:match("^%[(.-)%]")
        if sec then section = sec end
        local value = section == "FeatureSettings" and line:match("^ExcludeSyncFolders=(.*)$")
        if value then
            value = value:gsub("\r$", "")
            line = "ExcludeSyncFolders=" .. (value == "" and M.KOBO_EXCLUDE or ("(" .. value .. ")|" .. M.KOBO_EXCLUDE))
            found = true
        end
        lines[#lines + 1] = line
        if sec == "FeatureSettings" then insert_at = #lines end
    end
    if not found then
        local entry = "ExcludeSyncFolders=(" .. M.KOBO_DEFAULT .. ")|" .. M.KOBO_EXCLUDE
        if insert_at then table.insert(lines, insert_at + 1, entry)
        else lines[#lines + 1] = ""; lines[#lines + 1] = "[FeatureSettings]"; lines[#lines + 1] = entry end
    end
    return writeFile(conf, table.concat(lines, "\n") .. "\n")
end

--- Is `lib` a GZreader folder on the drive `home` (its last part GZreader, any case)?
function M.ownLibrary(lib, home)
    if type(lib) ~= "string" or lib == "" then return false end
    local name = lib:match("([^/]+)$") or ""
    if name:lower() ~= M.FOLDER:lower() then return false end
    return lib:sub(1, #home + 1) == home .. "/"
end

--- The move, from `o` = { home, app, lib, device }. Returns the program's new folder, or nil and why.
function M.run(o)
    o.root = o.home .. "/" .. M.FOLDER
    local target = o.keep_app and o.app or o.root .. "/app"
    if o.keep_app then
        if mode(o.app .. "/" .. M.NOOK_DONE) then return nil, "moved already" end
    elseif mode(target) then return nil, "GZreader/app is there already" end
    o.lib = (o.lib or o.root):gsub("/+$", "")
    -- (the books' folder GZreader remembered is only taken when it's a GZreader folder
    -- GZreader made, e.g. documents/GZreader, and on this drive: never a folder of
    -- your own, nor one elsewhere)
    if not M.ownLibrary(o.lib, o.home) then
        say("the remembered books' folder isn't GZreader's own on this drive: left as it is")
        o.lib = o.root
    end
    say("from", o.app, "and", o.lib, "to", o.root)
    if not mkdirp(o.root .. "/books") then return nil, "couldn't make " .. o.root .. "/books" end
    -- 1. the books (and their .sdr folders, the Audiobooks stand-ins…)
    local books = 0
    if isDir(o.lib) then
        for name in lfs.dir(o.lib) do
            local skip = name == "." or name == ".." or (o.lib == o.root and M.NOT_BOOKS[name])
            if not skip and M.move(o.lib .. "/" .. name, o.root .. "/books/" .. name) then books = books + 1 end
        end
    end
    -- 2. music and audiobooks, no longer hidden (they're beside the books, not in them)
    M.move(o.lib .. "/.music", o.root .. "/music")
    M.move(o.lib .. "/.audiobooks", o.root .. "/audiobooks")
    -- 3. Notes: the notes kept, attachments, drawings waiting to go to Memos
    mkdirp(o.root .. "/notes")
    M.move(o.app .. "/settings/gzreader-notes.json", o.root .. "/notes/notes.json")
    M.move(o.app .. "/settings/gzreader-memos-lacks.json", o.root .. "/notes/memos-lacks.json")
    M.move(o.app .. "/cache/gzreader-notes", o.root .. "/notes/files")
    M.move(o.app .. "/settings/gzreader-drawings", o.root .. "/notes/drawings")
    -- 4. KOReader's book settings kept apart from the books ("in KOReader's folder"): their places follow the books
    local mirror = o.app .. "/docsettings" .. o.lib
    if isDir(mirror) then
        mkdirp(o.app .. "/docsettings" .. o.root .. "/books")
        for name in lfs.dir(mirror) do
            if name ~= "." and name ~= ".." and not M.NOT_BOOKS[name] then
                M.move(mirror .. "/" .. name, o.app .. "/docsettings" .. o.root .. "/books/" .. name)
            end
        end
    end
    -- 5. every saved path: KOReader's settings, history, collections; GZreader's and ZenOS's
    local rules = M.rules(o)
    local done = { files = 0, paths = 0 }
    -- (KOReader's reading history is beside the settings, not in settings/: 1.35's
    -- first betas missed it, and Home's recently read came up empty)
    for _i, f in ipairs({ o.app .. "/settings.reader.lua", o.app .. "/history.lua" }) do
        local text = readFile(f)
        if text then
            local new, n = M.rewriteText(text, rules, o.root)
            if n > 0 and writeFile(f, new) then done.files, done.paths = done.files + 1, done.paths + n end
        end
    end
    writeFile(o.app .. "/" .. M.HISTORY_FIXED, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    rewriteTree(o.app .. "/settings", rules, o.root, 1, done)
    -- (each book's own settings, in its .sdr folder, say where the book is: doc_path)
    rewriteTree(o.root .. "/books", rules, o.root, 1, done, true)
    rewriteTree(o.app .. "/docsettings", rules, o.root, 1, done)
    -- (caches kept by a book's path: made again)
    for _i, f in ipairs({ "docprops_cache.sqlite", "docprops_cache.sqlite-wal", "docprops_cache.sqlite-shm" }) do
        os.remove(o.app .. "/settings/" .. f)
    end
    -- 6. GZreader's launchers, to GZreader/app (the Nook's start where they did)
    if not o.keep_app then pcall(M.launchers, o) end
    if o.device == "kobo" then pcall(M.koboExclude, o.home .. "/.kobo/Kobo/Kobo eReader.conf") end
    -- 7. a note for the new place (GZreader says once that it moved), then the program itself
    -- (JSON: a file on the drive is read as data, never run)
    writeFile(o.app .. "/settings/gzreader-moved.json", string.format(
        '{"at":%d,"from":"%s","books":%d,"files":%d,"paths":%d,"device":"%s"}\n',
        os.time(), (o.app:gsub('[%c"\\]', "")), books, done.files, done.paths, (tostring(o.device or "?"):gsub("%W", ""))))
    if o.keep_app then
        -- (the Nook: the program stays; this says the rest is in GZreader/ now: gzreader_places)
        writeFile(o.app .. "/" .. M.NOOK_DONE, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    else
        local ok, err = os.rename(o.app, target)
        if not ok then return nil, "couldn't move the program: " .. tostring(err) end
    end
    say(string.format("done: %d books, %d paths in %d files; the program is %s", books, done.paths, done.files, target))
    return target
end

--- The reading history of a device moved by a beta that missed it
--- (1.34.0-beta.2bcfc79): its books' old places (GZreader/<book>,
--- koreader/…) to the new ones, once. Entries for a book read again since
--- (in the history twice now) are kept once, the newest. → how many changed.
M.HISTORY_FIXED = "settings/gzreader-history-moved.done"
function M.fixHistory(app, root, old_app, keep_app)
    if mode(app .. "/" .. M.HISTORY_FIXED) then return 0 end
    local file = app .. "/history.lua"
    local n = 0
    local text = readFile(file)
    if text then
        local ok_l, load = pcall(require, "gzdataload")
        local ok, list = false, nil
        if ok_l then ok, list = pcall(load.file, file) end
        if ok and type(list) == "table" then
            local rules = M.rules({ app = old_app, lib = root, root = root, keep_app = keep_app })
            local seen, out = {}, {}
            for _i, e in ipairs(list) do
                if type(e) == "table" and type(e.file) == "string" then
                    local new = M.mapPath(e.file, rules, root)
                    if new then e.file, n = new, n + 1 end
                    if not seen[e.file] then seen[e.file] = true; out[#out + 1] = e end
                end
            end
            if n > 0 then
                -- (newest first, as KOReader keeps it)
                table.sort(out, function(a, b) return (tonumber(a.time) or 0) > (tonumber(b.time) or 0) end)
                local ok_d, dump = pcall(require, "dump")
                if not (ok_d and writeFile(file, dump(out) .. "\n")) then return 0 end
            end
        end
    end
    writeFile(app .. "/" .. M.HISTORY_FIXED, os.date("!%Y-%m-%dT%H:%M:%SZ") .. "\n")
    if n > 0 then say("reading history: " .. n .. " books' places put right") end
    return n
end

--- From reader.lua: the device's own places; nothing when GZreader isn't in one of them.
function M.early()
    local cwd = (lfs.currentdir() or ""):gsub("/+$", "")
    -- the Nook (its start script says where its card is): everything but the program
    -- into GZreader/ on the card, once; no restart (the program didn't move)
    local nook = os.getenv("GZ_NOOK_HOME")
    if nook and nook ~= "" then
        nook = nook:gsub("/+$", "")
        if mode(cwd .. "/" .. M.NOOK_DONE) then
            -- (moved by a beta that left the reading history behind: put right once)
            pcall(M.fixHistory, cwd, nook .. "/" .. M.FOLDER, cwd, true)
            return nil
        end
        if not isDir(nook) then return nil end
        local state = readFile(cwd .. "/settings/gzreader.lua") or ""
        local lib = state:match('%["library_dir"%]%s*=%s*"([^"\n]+)"')
        local ok, res, why = pcall(M.run, { home = nook, app = cwd, lib = lib, device = "nook", keep_app = true })
        if not ok then say("stopped:", tostring(res)) end
        if ok and not res then say("not moved:", tostring(why)) end
        return nil
    end
    local test_home = os.getenv("GZ_MOVE_HOME") -- (the tests and the emulator: a drive of their own)
    for _i, l in ipairs(M.LEGACY) do
        local home, app = l.home, l.app
        if test_home then home = test_home end
        -- (moved already, by a beta that left the reading history behind: put right once)
        if cwd == home .. "/" .. M.FOLDER .. "/app" then
            pcall(M.fixHistory, cwd, home .. "/" .. M.FOLDER, test_home and (home .. "/koreader") or l.app)
            -- (KUAL's entry: written again when it's missing or goes through bin/start.sh,
            -- as 1.34.0-beta.2bcfc79's did: a Kindle 3 couldn't start GZreader from it)
            local device = os.getenv("GZ_MOVE_DEVICE") or l.device
            if device == "kindle" and isDir(home .. "/extensions") and not M.kualReady(home) then
                pcall(M.launchers, { app = cwd, home = home, device = device })
            end
            return nil
        end
        if test_home then app = cwd end
        if cwd == app and (test_home or isDir(home)) then
            -- (the books' folder GZreader remembers: kept in its state)
            local state = readFile(app .. "/settings/gzreader.lua") or ""
            local lib = state:match('%["library_dir"%]%s*=%s*"([^"\n]+)"')
            if mode(home .. "/" .. M.FOLDER .. "/app") then return nil end
            local ok, res, why = pcall(M.run, { home = home, app = app, lib = lib, device = os.getenv("GZ_MOVE_DEVICE") or l.device })
            if not ok then say("stopped:", tostring(res)) end
            if ok and not res then say("not moved:", tostring(why)) end
            return ok and res or nil
        end
        if test_home then break end
    end
end

return M
