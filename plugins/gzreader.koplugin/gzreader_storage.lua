--[[--
Settings → General → Storage: what GZreader keeps on the Kindle, and what's biggest.

Books (the GZreader folder: book files and their KOReader settings),
audiobooks (.audiobooks), music (.music), notes (the offline copy and the
attachments kept), the calendar (its offline copy), and covers and saved
lists (caches: rebuilt when needed). Books, audiobooks, music and notes open
on their largest ones. The free space is the Kindle's own.

Measured in a background process (walking the folders takes a while on a
Kindle 3): the page shows "Measuring…" until it's done.
]]

local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local Storage = { TOP = 15 }

local BOOK_EXT = {
    epub = true, pdf = true, mobi = true, azw = true, azw3 = true, kfx = true, fb2 = true, cbz = true, cbr = true,
    cb7 = true, djvu = true, txt = true, rtf = true, doc = true, docx = true, htm = true, html = true, xps = true,
    zip = true, part = true,
}

--- Bytes as "12.3 MB" (KB below 1 MB, GB from 1 GB).
function Storage.size(n)
    n = tonumber(n) or 0
    if n >= 1024 ^ 3 then return string.format("%.2f GB", n / 1024 ^ 3) end
    if n >= 1024 ^ 2 then return string.format("%.1f MB", n / 1024 ^ 2) end
    if n >= 1024 then return string.format("%d KB", math.floor(n / 1024 + 0.5)) end
    return string.format("%d B", n)
end

local function fileSize(p) return tonumber((lfs.attributes(p, "size"))) or 0 end

--- A folder's size (everything in it), and how many files.
function Storage.dirSize(path)
    local total, files = 0, 0
    local ok, iter, obj = pcall(lfs.dir, path)
    if not ok then return 0, 0 end
    for name in iter, obj do
        if name ~= "." and name ~= ".." then
            local p = path .. "/" .. name
            local a = lfs.symlinkattributes and lfs.symlinkattributes(p) or lfs.attributes(p)
            if a and a.mode == "directory" then
                local t, f = Storage.dirSize(p)
                total, files = total + t, files + f
            elseif a and a.mode == "file" then
                total, files = total + (tonumber(a.size) or 0), files + 1
            end
        end
    end
    return total, files
end

local function largest(items, n)
    table.sort(items, function(a, b) return a.bytes > b.bytes end)
    local out = {}
    for i = 1, math.min(n or Storage.TOP, #items) do out[i] = items[i] end
    return out
end

local function sum(items)
    local t = 0
    for _i, it in ipairs(items) do t = t + it.bytes end
    return t
end

--- Books: the book files in the GZreader folder (not the hidden audio and
--- music folders, nor the audiobooks' and albums' stand-ins), each with its
--- KOReader settings (<name>.sdr).
function Storage.books(plugin, lib)
    local skip = { Audiobooks = true, Music = true }
    local titles = {}
    for _id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" and e.path then titles[e.path] = e.title end
    end
    local items, by_stem, sdrs = {}, {}, {}
    local function walk(dir, top)
        local ok, iter, obj = pcall(lfs.dir, dir)
        if not ok then return end
        for name in iter, obj do
            if name:sub(1, 1) ~= "." and not (top and skip[name]) then
                local p = dir .. "/" .. name
                local mode = lfs.attributes(p, "mode")
                if mode == "directory" then
                    if name:match("%.sdr$") then
                        sdrs[#sdrs + 1] = { stem = dir .. "/" .. name:gsub("%.sdr$", ""), bytes = (Storage.dirSize(p)) }
                    else
                        walk(p, false)
                    end
                elseif mode == "file" then
                    local ext = name:match("%.([%w]+)$")
                    if ext and BOOK_EXT[ext:lower()] then
                        local partial = ext:lower() == "part"
                        local shown = titles[p] or name:gsub("%.part$", ""):gsub("%.[%w]+$", "")
                        local it = { name = partial and T(_("%1 (unfinished download)"), shown) or shown, bytes = fileSize(p), path = p }
                        items[#items + 1] = it
                        by_stem[(p:gsub("%.part$", ""):gsub("%.[%w]+$", ""))] = it
                    end
                end
            end
        end
    end
    walk(lib, true)
    local extra = 0
    for _i, s in ipairs(sdrs) do
        local it = by_stem[s.stem]
        if it then it.bytes = it.bytes + s.bytes else extra = extra + s.bytes end
    end
    return { bytes = sum(items) + extra, count = #items, items = largest(items) }
end

--- Audiobooks: each one's folder in .audiobooks (the audio, and what was
--- made from it for the Kindle), plus the stand-ins on the shelves.
function Storage.audiobooks(plugin, lib)
    local known = plugin.store.audiobooks or {}
    local items = {}
    local root = lib .. "/.audiobooks"
    local ok, iter, obj = pcall(lfs.dir, root)
    if ok then
        for name in iter, obj do
            local p = root .. "/" .. name
            if name ~= "." and name ~= ".." and lfs.attributes(p, "mode") == "directory" then
                local e = known[name] or known[tonumber(name) or name] or {}
                items[#items + 1] = { name = type(e.title) == "string" and e.title or T(_("Audiobook %1"), name),
                    bytes = (Storage.dirSize(p)) }
            end
        end
    end
    local stubs = Storage.dirSize(lib .. "/Audiobooks")
    return { bytes = sum(items) + stubs, count = #items, items = largest(items) }
end

--- Music: each album or playlist in .music, plus the stand-ins.
function Storage.music(plugin, lib)
    local items = {}
    local root = lib .. "/.music"
    local Music
    pcall(function() Music = require("gzreader_music") end)
    local ok, iter, obj = pcall(lfs.dir, root)
    if ok then
        for name in iter, obj do
            local p = root .. "/" .. name
            if name ~= "." and name ~= ".." and lfs.attributes(p, "mode") == "directory" then
                local label = name
                local okc, c = pcall(function() return Music and Music.load(p, { any = true }) end)
                if okc and type(c) == "table" and type(c.title) == "string" then
                    label = c.title .. ((type(c.artist) == "string" and c.artist ~= "") and (" · " .. c.artist) or "")
                end
                items[#items + 1] = { name = label, bytes = (Storage.dirSize(p)) }
            end
        end
    end
    local stubs = Storage.dirSize(lib .. "/Music")
    return { bytes = sum(items) + stubs, count = #items, items = largest(items) }
end

--- A note's name: its first line, short.
function Storage.noteName(content)
    local line = tostring(content or ""):gsub("^%s+", ""):match("^[^\n]*") or ""
    line = line:gsub("^#+%s*", ""):gsub("%s+$", "")
    if line == "" then return _("(empty note)") end
    if #line > 48 then line = line:sub(1, 45):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "…" end
    return line
end

--- Notes: the offline copy, and the attachments kept on the Kindle. Each
--- note: its text and its attachments.
function Storage.notes(data_dir, settings_dir)
    local Memos
    pcall(function() Memos = require("gzreader_memos") end)
    local cache_file = settings_dir .. "/gzreader-notes.json"
    local items = {}
    local cache = Memos and Memos.loadCache and Memos.loadCache() or nil
    for _i, m in ipairs(cache and cache.notes or {}) do
        local bytes = #tostring(m.content or "")
        for _j, att in ipairs(m.attachments or {}) do
            local okp, p = pcall(Memos.filePath, att)
            if okp and p then bytes = bytes + fileSize(p) end
        end
        items[#items + 1] = { name = Storage.noteName(m.content), bytes = bytes }
    end
    local files = Storage.dirSize(data_dir .. "/cache/gzreader-notes")
    return { bytes = fileSize(cache_file) + files, count = #items, items = largest(items) }
end

--- Everything, as plain values (it comes back from a background process).
function Storage.measure(plugin)
    local DataStorage = require("datastorage")
    local data_dir, settings_dir = DataStorage:getDataDir(), DataStorage:getSettingsDir()
    local lib = plugin:libraryDir()
    local out = {}
    out.books = Storage.books(plugin, lib)
    out.audiobooks = Storage.audiobooks(plugin, lib)
    out.music = Storage.music(plugin, lib)
    out.notes = Storage.notes(data_dir, settings_dir)
    out.calendar = { bytes = fileSize(settings_dir .. "/gzreader-calendar.json") }
    local caches = fileSize(settings_dir .. "/gzreader_index.json") + fileSize(settings_dir .. "/bookinfo_cache.sqlite3")
    for _i, d in ipairs({ "gzreader-thumbs", "gzreader-lists", "gzreader-covers", "gz-covers", "gzreader-update" }) do
        caches = caches + (Storage.dirSize(data_dir .. "/cache/" .. d))
    end
    out.caches = { bytes = caches }
    local okd, du = pcall(function() return require("util").diskUsage(lib) end)
    if okd and type(du) == "table" and du.total then out.disk = { total = du.total, available = du.available } end
    return out
end

-- Settings rows' icons, per part: a glyph of ZenOS's common/inline_icon_map.lua,
-- one of ZenOS's icons (`name`, its icons/ folder) or one of GZreader's (`file`)
local here = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]+$") or "plugins/gzreader.koplugin"
Storage.ICONS = { free = { glyph = "settings_storage" }, books = { glyph = "reading" },
    audiobooks = { file = here .. "/icons/panel/readaloud.svg" }, music = { name = "tab_music" },
    notes = { name = "notes" }, calendar = { glyph = "calendar" }, caches = { glyph = "settings_covers" } }

-- `row` with part `key`'s icon
local function iconed(key, row)
    local icon = Storage.ICONS[key] or {}
    if icon.glyph then
        local ok, map = pcall(require, "common/inline_icon_map")
        row.icon_glyph = ok and type(map) == "table" and map[icon.glyph] or nil
    end
    row.icon_name, row.icon_file = icon.name, icon.file
    return row
end

--- The page's lines (pure: run_tests.lua). Each has an icon (`icon_glyph`)
--- and a part with things in it a submenu, for Settings → General → Storage.
function Storage.items(r)
    local items = {}
    if r.disk then
        items[#items + 1] = iconed("free", { text = _("Free on this Kindle"), keep_menu_open = true,
            mandatory = T(_("%1 of %2"), Storage.size(r.disk.available), Storage.size(r.disk.total)), select_enabled = false })
    end
    local function group(key, label, counted, none)
        local g = r[key]
        if not g then return end
        local entry = iconed(key, { text = label, mandatory = Storage.size(g.bytes) })
        if counted and g.count then entry.mandatory = T(counted(g.count), g.count) .. " · " .. entry.mandatory end
        if g.items then
            local sub = {}
            for _i, it in ipairs(g.items) do
                sub[#sub + 1] = iconed(key, { text = it.name, mandatory = Storage.size(it.bytes), select_enabled = false,
                    keep_menu_open = true })
            end
            if #sub == 0 then sub[1] = iconed(key, { text = none, select_enabled = false, keep_menu_open = true }) end
            entry.sub_item_table = sub
        else
            entry.select_enabled = false
            entry.keep_menu_open = true
        end
        items[#items + 1] = entry
    end
    local N_ = type(_) == "table" and _.ngettext or function(one, many, n) return n == 1 and one or many end
    group("books", _("Books"), function(n) return N_("1 book", "%1 books", n) end, _("No books on this Kindle."))
    group("audiobooks", _("Audiobooks"), function(n) return N_("1 audiobook", "%1 audiobooks", n) end, _("No audiobooks on this Kindle."))
    -- (albums and playlists together; "12 albums and playlists · 1.2 GB" didn't fit on the row)
    group("music", _("Music"), function(n) return N_("1 downloaded", "%1 downloaded", n) end, _("No music on this Kindle."))
    group("notes", _("Notes"), function(n) return N_("1 note", "%1 notes", n) end, _("No notes on this Kindle."))
    group("calendar", _("Calendar"))
    group("caches", _("Covers and saved lists"))
    return items
end

--- The last measurement (shown at once the next time, then measured again).
Storage.last = nil
--- How the measuring runs (a test replaces it): fn in the background, then done(result, err).
function Storage._background(fn, done)
    require("gzreader_async").background(fn, done, "storage")
end

--- Settings → General → Storage: the parts as Settings rows (icons, sizes,
--- arrows into the biggest of each). `page` is the Settings page that shows
--- them: the rows are filled in there when measured (the last measurement,
--- or "Measuring…", until then).
function Storage.settingsItems(plugin, page)
    local list = {}
    local function fill(items)
        for i = #list, 1, -1 do list[i] = nil end
        for i, it in ipairs(items) do list[i] = it end
        if page and not page._closed and page.item_table == list and page.updateItems then page:updateItems() end
    end
    fill(Storage.last and Storage.items(Storage.last)
        or { iconed("free", { text = _("Measuring…"), select_enabled = false, keep_menu_open = true }) })
    local tries = 0
    local function run()
        Storage._background(function() return Storage.measure(plugin) end, function(r, err)
            if type(r) ~= "table" then
                if err == "busy" and tries < 10 then
                    tries = tries + 1
                    return require("ui/uimanager"):scheduleIn(2, run)
                end
                require("gzreader_log").warn("storage: couldn't measure:", tostring(err))
                if not Storage.last then
                    fill({ { text = _("Couldn't measure the storage. Try again."), select_enabled = false, keep_menu_open = true } })
                end
                return
            end
            Storage.last = r
            fill(Storage.items(r))
        end)
    end
    run()
    return list
end

return Storage
