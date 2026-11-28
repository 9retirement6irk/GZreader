--[[--
What "Copy from another GZreader" (gzreader_copy.lua) brings besides the
connections:

- **Settings**: GZreader's and ZenOS's own (G_reader_settings' gzreader_ and
  zen_ keys, ZenOS's config file: Home, tabs, the shelf), the reader's
  defaults for books (copt_/kopt_), the status bar, sleep screen and sorting,
  and GZreader's own preferences kept with its data (the daily paper's
  feeds and choices, Notes' and the calendar's preferences, the auto-download
  shelf, what's synced). Never anything secret (no key whose name says token,
  password, secret, PIN or key; nothing from the accounts' sections), and
  nothing that belongs to the device itself (its rotation, pen range,
  update checks, what was last shown).
- **Game data**: the game board's records (store.games: history,
  achievements, themes, your books' words) and today's paper puzzles as far
  as they've got.
- **Downloads**: what's on the other Kindle, downloaded again here from the
  same servers: books (narrated ones with their narration), audiobooks,
  Plex music. Kept as a list (store.copy_pending) and started once this
  Kindle is signed in to the same book server (or to Plex, for music), at
  once if it already is, else at the next Wi-Fi connection after signing in.

Pure where it can be (lists in, lists out); the downloads themselves go
through the usual download queue (Grimmory:downloadAndOpen with no_open,
Audiobook.download, Music.download), one after another.
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local More = {
    SETTING_PREFIXES = { "gzreader_", "zen_", "copt_", "kopt_", "screensaver_" },
    SETTING_KEYS = {
        footer = true, reader_footer_mode = true, night_mode = true, end_document_action = true,
        collate = true, reverse_collate = true, collate_mixed = true, language = true,
    },
    -- (the device's own, not a preference)
    SETTING_SKIP = {
        gzreader_update_last_check = true, gzreader_update_latest = true, gzreader_hw_keyboard_last = true,
        gzreader_nook_lcd = true, gzreader_rotation_kept = true, gzreader_pen_range = true, gzreader_launcher_v = true,
        gzreader_downloads_list_v = true, gzreader_sso_redirect = true, gzreader_whats_new_seen = true,
        gzreader_usb_sync = true, zen_ui_just_updated = true,
    },
    -- GZreader's own preferences in its data file (store), as whole sections
    STORE_KEYS = { "daily", "notes_prefs", "calendar_prefs", "calendar_holidays", "logging_disabled",
        "annotation_sync_disabled", "sync_disabled", "bookmark_sync_disabled", "auto_shelf", "auto_shelf_mirror",
        "auto_shelf_refresh", "music_section" },
    -- (inside them: the day's state, not a preference)
    STORE_SKIP = { daily = { puzzles = true, last_error = true, refreshing = true } },
    SPACING = 2, -- s between starting one download and the next
}

--- A key whose name says it holds something secret.
function More.secretName(k)
    local l = tostring(k):lower()
    return l:find("token", 1, true) or l:find("pass", 1, true) or l:find("secret", 1, true) or l:find("cookie", 1, true)
        or l:find("api_?key") or l:find("_pin$") or l:find("^pin_") or l:find("_key$") or false
end

local function plain(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" or depth > 12 then return nil end
    local out = {}
    for k, x in pairs(v) do
        if (type(k) == "string" or type(k) == "number") and not (type(k) == "string" and More.secretName(k)) then
            local c = plain(x, depth + 1)
            if c ~= nil then out[k] = c end
        end
    end
    return out
end
More.plain = plain

--- Whether a G_reader_settings key is copied.
function More.settingWanted(k)
    if type(k) ~= "string" or More.SETTING_SKIP[k] or More.secretName(k) then return false end
    if More.SETTING_KEYS[k] then return true end
    for _i, p in ipairs(More.SETTING_PREFIXES) do
        if k:sub(1, #p) == p then return true end
    end
    return false
end

--- The settings to send: { reader = { k = v }, store = { section = … }, zenos = config or nil }.
--- `reader`: G_reader_settings' table (data), `store`: the plugin's store,
--- `zenos`: ZenOS's config table (or nil).
function More.settings(reader, store, zenos)
    local out = { reader = {}, store = {} }
    for k, v in pairs(reader or {}) do
        if More.settingWanted(k) then
            local c = plain(v)
            if c ~= nil then out.reader[k] = c end
        end
    end
    for _i, k in ipairs(More.STORE_KEYS) do
        local v = store and store[k]
        if v ~= nil then
            local c = plain(v)
            local skip = More.STORE_SKIP[k]
            if type(c) == "table" and skip then for s in pairs(skip) do c[s] = nil end end
            out.store[k] = c
        end
    end
    if type(zenos) == "table" then out.zenos = plain(zenos) end
    return out
end

--- How many settings: for the offer ("38 settings").
function More.count(s)
    local n = 0
    for _k in pairs(s.reader or {}) do n = n + 1 end
    for _k in pairs(s.store or {}) do n = n + 1 end
    if s.zenos then n = n + 1 end
    return n
end

--- Take settings that came: into G_reader_settings (`setter(k, v)`) and the
--- store. Returns how many. Only what passes the same checks (a sender on
--- an older or newer GZreader can't slip anything else in).
function More.applySettings(s, store, setter)
    local n = 0
    for k, v in pairs(type(s.reader) == "table" and s.reader or {}) do
        if More.settingWanted(k) then setter(k, plain(v)); n = n + 1 end
    end
    local allowed = {}
    for _i, k in ipairs(More.STORE_KEYS) do allowed[k] = true end
    for k, v in pairs(type(s.store) == "table" and s.store or {}) do
        if allowed[k] then
            local c = plain(v)
            if k == "daily" and type(c) == "table" and type(store.daily) == "table" then
                -- (the paper here keeps its own day: today's edition and puzzles)
                for dk, dv in pairs(store.daily) do
                    if More.STORE_SKIP.daily[dk] or dk == "edition" or dk == "editions" then c[dk] = dv end
                end
            end
            store[k] = c
            n = n + 1
        end
    end
    return n
end

---------------------------------------------------------------- game data

--- The game board's records to send (nil when there are none).
function More.games(store)
    local g = store and store.games
    if type(g) ~= "table" then return nil end
    local out = plain(g)
    local puzzles = type(store.daily) == "table" and store.daily.puzzles or nil
    if type(puzzles) == "table" then out.paper_puzzles = plain(puzzles) end
    return out
end

--- Game data that came, merged with this Kindle's: the history joined (each
--- puzzle once, newest first, at most 200), the achievements each at its
--- earliest, the counts from whichever has finished more, the books' words
--- and the theme from the sender when this one has none; today's paper
--- puzzles when they're the same day and further along.
function More.mergeGames(store, g)
    if type(g) ~= "table" then return false end
    g = plain(g)
    local paper = g.paper_puzzles
    g.paper_puzzles = nil
    local mine = type(store.games) == "table" and store.games or nil
    if not mine then
        store.games = g
    else
        local seen, hist = {}, {}
        local function add(list)
            for _i, h in ipairs(type(list) == "table" and list or {}) do
                local key = tostring(h.t) .. ":" .. tostring(h.k) .. ":" .. tostring(h.s)
                if type(h) == "table" and not seen[key] then seen[key] = true; hist[#hist + 1] = h end
            end
        end
        add(mine.history); add(g.history)
        table.sort(hist, function(a, b) return (tonumber(a.t) or 0) > (tonumber(b.t) or 0) end)
        while #hist > 200 do table.remove(hist) end
        mine.history = hist
        mine.unlocked = type(mine.unlocked) == "table" and mine.unlocked or {}
        for id, at in pairs(type(g.unlocked) == "table" and g.unlocked or {}) do
            if not mine.unlocked[id] or (tonumber(at) or math.huge) < (tonumber(mine.unlocked[id]) or math.huge) then mine.unlocked[id] = at end
        end
        local ms, gs = type(mine.stats) == "table" and mine.stats or {}, type(g.stats) == "table" and g.stats or {}
        if (tonumber(gs.total) or 0) > (tonumber(ms.total) or 0) then mine.stats = gs end
        if type(mine.books) ~= "table" or #mine.books == 0 then mine.books = g.books end
        if type(mine.set) ~= "table" then mine.set = g.set end
        if mine.enabled == nil then mine.enabled = g.enabled end
    end
    if type(paper) == "table" and paper.day then
        store.daily = type(store.daily) == "table" and store.daily or {}
        local here = store.daily.puzzles
        if type(here) ~= "table" or here.day ~= paper.day or not here.began then store.daily.puzzles = paper end
    end
    return true
end

---------------------------------------------------------------- downloads

--- What's downloaded here, to download again on the other Kindle:
--- { server = host, books = { { id, title, format, narrated } }, audiobooks =
--- { { id, title, plex } }, music = { { kind, key, title, artist, year, thumb } } }.
--- `narrated(path)`: whether a book's file has its narration in it.
function More.downloads(plugin, narrated)
    local store = plugin.store or {}
    local out = { server = store.server and tostring(store.server):gsub("^https?://", ""):gsub("/.*$", "") or nil,
        books = {}, audiobooks = {}, music = {} }
    local lfs = require("libs/libkoreader-lfs")
    for id, e in pairs(type(store.downloads) == "table" and store.downloads or {}) do
        if type(e) == "table" and e.path and lfs.attributes(e.path, "mode") == "file" then
            local n = false
            if narrated and tostring(e.path):lower():match("%.epub$") then
                local ok, yes = pcall(narrated, e.path)
                n = ok and yes == true
            end
            out.books[#out.books + 1] = { id = tostring(id), title = e.title, format = e.format, narrated = n or nil }
        end
    end
    table.sort(out.books, function(a, b) return tostring(a.title or a.id) < tostring(b.title or b.id) end)
    local okA, AB = pcall(require, "gzreader_audiobook")
    if okA then
        local ok, list = pcall(AB.downloaded, plugin)
        for _i, x in ipairs(ok and list or {}) do
            local b = x.book
            local id = b and tostring(b.id or "")
            -- (narrated books' stand-ins come with their EPUBs)
            if id and id ~= "" and not id:match("^narr%-") then
                out.audiobooks[#out.audiobooks + 1] = { id = id, title = b.title, plex = type(b.plex) == "table" and { key = b.plex.key } or nil }
            end
        end
    end
    local okM, Music = pcall(require, "gzreader_music")
    if okM then
        local ok, list = pcall(Music.downloaded, plugin)
        for _i, c in ipairs(ok and list or {}) do
            if c.kind and c.key then
                out.music[#out.music + 1] = { kind = c.kind, key = c.key, title = c.title, artist = c.artist, year = c.year, thumb = c.thumb }
            end
        end
    end
    return out
end

--- "12 books (2 narrated), 3 audiobooks, 5 albums".
function More.downloadsText(d)
    local parts, narrated = {}, 0
    for _i, b in ipairs(d.books or {}) do if b.narrated then narrated = narrated + 1 end end
    local nb = #(d.books or {})
    if nb > 0 then
        parts[#parts + 1] = (nb == 1 and _("1 book") or T(_("%1 books"), nb)) .. (narrated > 0 and (" " .. T(_("(%1 narrated)"), narrated)) or "")
    end
    local na = #(d.audiobooks or {})
    if na > 0 then parts[#parts + 1] = na == 1 and _("1 audiobook") or T(_("%1 audiobooks"), na) end
    local nm = #(d.music or {})
    if nm > 0 then parts[#parts + 1] = nm == 1 and _("1 album or playlist") or T(_("%1 albums and playlists"), nm) end
    return table.concat(parts, ", ")
end

--- Keep what came, to download (on top of anything still waiting). Things
--- already on this Kindle are left out.
function More.keepDownloads(plugin, d)
    local store = plugin.store
    local p = type(store.copy_pending) == "table" and store.copy_pending or { books = {}, audiobooks = {}, music = {} }
    p.server = d.server or p.server
    local have = type(store.downloads) == "table" and store.downloads or {}
    local seen = {}
    for _i, b in ipairs(p.books) do seen["b" .. b.id] = true end
    for _i, a in ipairs(p.audiobooks) do seen["a" .. a.id] = true end
    for _i, m in ipairs(p.music) do seen["m" .. m.kind .. m.key] = true end
    local n = 0
    for _i, b in ipairs(type(d.books) == "table" and d.books or {}) do
        if b.id and not have[tostring(b.id)] and not seen["b" .. b.id] then p.books[#p.books + 1] = b; n = n + 1 end
    end
    local abs = type(store.audiobooks) == "table" and store.audiobooks or {}
    for _i, a in ipairs(type(d.audiobooks) == "table" and d.audiobooks or {}) do
        if a.id and not abs[tostring(a.id)] and not seen["a" .. a.id] then p.audiobooks[#p.audiobooks + 1] = a; n = n + 1 end
    end
    for _i, m in ipairs(type(d.music) == "table" and d.music or {}) do
        if m.kind and m.key and not seen["m" .. m.kind .. m.key] then p.music[#p.music + 1] = m; n = n + 1 end
    end
    store.copy_pending = (#p.books + #p.audiobooks + #p.music > 0) and p or nil
    plugin:save()
    return n
end

--- What can start now: { books = bool, music = bool } (books and audiobooks
--- need this Kindle signed in to the same book server, music Plex).
function More.ready(plugin)
    local p = plugin.store.copy_pending
    if type(p) ~= "table" then return { books = false, music = false } end
    local here = plugin.store.server and tostring(plugin.store.server):gsub("^https?://", ""):gsub("/.*$", "") or nil
    local paired = plugin.api and plugin.api.isPaired and plugin.api:isPaired()
    local okM, Music = pcall(require, "gzreader_music")
    local plex = okM and Music.plex and Music.plex(plugin)
    return {
        books = paired and (p.server == nil or p.server == here) and true or false,
        music = (plex and plex.isConnected and plex:isConnected()) and true or false,
    }
end

--- Start what's waiting and can start: one at a time, SPACING apart (each
--- goes into the download queue). `opts.start = { book = fn(b), audiobook =
--- fn(a), music = fn(m) }` (tests stand in for the real ones). Returns how
--- many were started.
function More.resume(plugin, opts)
    opts = opts or {}
    local p = plugin.store.copy_pending
    if type(p) ~= "table" or More.running then return 0 end
    local ready = More.ready(plugin)
    local start = opts.start or More.starters(plugin)
    local jobs = {}
    if ready.books then
        for _i, b in ipairs(p.books) do jobs[#jobs + 1] = function() start.book(b) end end
        for _i, a in ipairs(p.audiobooks) do jobs[#jobs + 1] = function() start.audiobook(a) end end
        p.books, p.audiobooks = {}, {}
    end
    if ready.music then
        for _i, m in ipairs(p.music) do jobs[#jobs + 1] = function() start.music(m) end end
        p.music = {}
    end
    if #jobs == 0 then return 0 end
    if #p.books + #p.audiobooks + #p.music == 0 then plugin.store.copy_pending = nil end
    plugin:save()
    Log.info("copy: downloading again what the other Kindle had:", #jobs, "items")
    local i = 0
    local function step()
        i = i + 1
        if i > #jobs then More.running = nil; return end
        pcall(jobs[i])
        if opts.now then return step() end
        require("ui/uimanager"):scheduleIn(More.SPACING, step)
    end
    More.running = true
    step()
    return #jobs
end

--- The real downloads: a book into the queue (narrated ones with their
--- narration, BookOrbit's "original"), an audiobook, an album or playlist.
function More.starters(plugin)
    return {
        book = function(b)
            local book = { id = tonumber(b.id) or b.id, title = b.title, primaryFileType = b.format }
            if plugin.backend and plugin:backend() == "bookorbit" then book.gz_variant = b.narrated and "original" or nil end
            plugin:downloadAndOpen(book, nil, { no_open = true, gz_asked = true })
        end,
        audiobook = function(a)
            require("gzreader_audiobook").download(plugin, { id = a.id, title = a.title, plex = a.plex }, function(book, err)
                if not book then Log.warn("copy: an audiobook couldn't be downloaded:", tostring(err)) end
            end)
        end,
        music = function(m)
            local Music = require("gzreader_music")
            local plex = Music.plex(plugin)
            require("gzreader_async").run(nil, function()
                if m.kind == "playlist" then
                    local tracks, start = {}, 0
                    while true do
                        local page, total = plex:playlistItems(m.key, start)
                        if not page or #page == 0 then break end
                        for _i, t in ipairs(page) do tracks[#tracks + 1] = t end
                        start = start + #page
                        if not total or start >= total then break end
                    end
                    return tracks
                end
                return plex:children(m.key)
            end, function(tracks, err)
                if type(tracks) ~= "table" or #tracks == 0 then
                    return Log.warn("copy: music couldn't be listed:", tostring(err))
                end
                local c = { kind = m.kind, key = m.key, title = m.title, artist = m.artist, year = m.year, thumb = m.thumb, tracks = tracks }
                Music.download(plugin, c, {})
            end, "copy music")
        end,
    }
end

--- What's still waiting, in words (nil: nothing): for the copy's result.
function More.waitingText(plugin)
    local p = plugin.store.copy_pending
    if type(p) ~= "table" then return nil end
    local ready = More.ready(plugin)
    local lines = {}
    local nb = #p.books + #p.audiobooks
    if nb > 0 and not ready.books then
        lines[#lines + 1] = T(_("%1 will download once this Kindle is signed in to %2."),
            More.downloadsText({ books = p.books, audiobooks = p.audiobooks }), p.server or _("the book server"))
    end
    if #p.music > 0 and not ready.music then
        lines[#lines + 1] = T(_("%1 will download once this Kindle is connected to Plex."), More.downloadsText({ music = p.music }))
    end
    return #lines > 0 and table.concat(lines, "\n") or nil
end

return More
