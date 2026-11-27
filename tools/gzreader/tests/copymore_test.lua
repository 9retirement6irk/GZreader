-- Copy from another GZreader, the rest of it (gzreader_copymore.lua):
-- settings (nothing secret, nothing the device's own), the game board's
-- records merged, and the downloads kept and started once this Kindle is
-- signed in. The exchange itself (PIN, encryption) is tested in run_tests.lua.
--   luajit copymore_test.lua <plugin dir> <tests lib>
local PLUGIN, LIB = arg[1], arg[2]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

local logged = {}
package.preload["gettext"] = function() return function(t) return t end end
package.preload["gzreader_log"] = function()
    local function line(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        logged[#logged + 1] = table.concat(parts, " ")
    end
    return { info = line, warn = line }
end
package.preload["ffi/util"] = function()
    return { template = function(s, ...)
        local args = { ... }
        return (s:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
    end }
end
local files = {}
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function(p, what) return files[p] and (what == "mode" and "file" or {}) or nil end }
end
local plex_on = false
package.preload["gzreader_music"] = function()
    return {
        downloaded = function() return { { kind = "album", key = "/library/metadata/77", title = "Blue", artist = "Joni", year = 1971, have = 10 } } end,
        plex = function() return { isConnected = function() return plex_on end } end,
    }
end
package.preload["gzreader_audiobook"] = function()
    return { downloaded = function()
        return { { book = { id = "42", title = "A Walk in the Woods" } }, { book = { id = "narr-abc", title = "Narrated stand-in" } },
            { book = { id = "p9", title = "From Plex", plex = { key = "/library/metadata/9", token = "plex-secret-token" } } } }
    end }
end
package.preload["ui/uimanager"] = function() return { scheduleIn = function(_s, _t, f) f() end } end

local More = require("gzreader_copymore")

print("== settings: GZreader's, ZenOS's and the reader's, nothing secret")
local reader = {
    gzreader_wifi_mode = "auto", gzreader_panel_order = { "home", "wifi" }, zen_tags_global_collate = "title",
    copt_font_size = 22, kopt_margin = 3, footer = { mode = 2 }, night_mode = true, screensaver_type = "cover",
    -- the device's own
    gzreader_update_last_check = 123, gzreader_rotation_kept = 1, gzreader_pen_range = 9, lastfile = "/mnt/us/x.epub",
    -- secrets (by name)
    gzreader_hardcover_token = "tok", gzreader_api_key = "k", gzreader_wifi_password = "p", zen_sync_pin = "1234",
    screen_dpi = 300, frontlight_intensity = 12,
}
local store = {
    server = "https://books.example.com", token = "grimmory-token", refresh_token = "r", password = "never",
    daily = { enabled = true, feeds = { { url = "https://news.example.com/rss", on = true } }, order = "mixed", puzzles = { day = "x" }, ai_key = "sk-1" },
    notes_prefs = { space = "Home" }, calendar_prefs = { week_start = 1 }, auto_shelf = { id = 4, name = "Kindle" },
    memos = { server = "https://memos.example.com", token = "memos-token" }, ai = { key = "sk-2" },
    plex = { token = "plex-token" },
}
local zen = { home = { rows = { "featured", "shelf" } }, tabs = { "home", "downloads" } }
local s = More.settings(reader, store, zen)
check(s.reader.gzreader_wifi_mode == "auto" and s.reader.gzreader_panel_order[2] == "wifi" and s.reader.zen_tags_global_collate == "title"
    and s.reader.copt_font_size == 22 and s.reader.kopt_margin == 3 and s.reader.footer.mode == 2 and s.reader.night_mode == true
    and s.reader.screensaver_type == "cover", "GZreader's, ZenOS's and the reader's settings (book defaults, status bar, sleep screen)")
check(s.reader.gzreader_update_last_check == nil and s.reader.gzreader_rotation_kept == nil and s.reader.gzreader_pen_range == nil
    and s.reader.lastfile == nil and s.reader.screen_dpi == nil and s.reader.frontlight_intensity == nil,
    "not the device's own (its rotation, pen range, screen, light, last book, update checks)")
check(s.reader.gzreader_hardcover_token == nil and s.reader.gzreader_api_key == nil and s.reader.gzreader_wifi_password == nil
    and s.reader.zen_sync_pin == nil, "nothing whose name says token, key, password or PIN")
check(s.store.daily and s.store.daily.feeds[1].url == "https://news.example.com/rss" and s.store.daily.order == "mixed"
    and s.store.daily.puzzles == nil and s.store.daily.ai_key == nil, "the daily paper's feeds and choices, not its day or a key")
check(s.store.notes_prefs.space == "Home" and s.store.calendar_prefs.week_start == 1 and s.store.auto_shelf.name == "Kindle",
    "Notes', the calendar's and the auto-download shelf's preferences")
local all = require("dkjson").encode(s)
check(not all:find("grimmory-token", 1, true) and not all:find("memos-token", 1, true) and not all:find("sk-", 1, true)
    and not all:find("never", 1, true) and not all:find("plex-token", 1, true) and not all:find("\"p\"", 1, true),
    "no token, key or password anywhere in it")
check(s.zenos and s.zenos.home.rows[2] == "shelf" and More.count(s) > 10, "ZenOS's own settings (Home, tabs): " .. More.count(s) .. " in all")

-- taken in on the other Kindle
local saved = {}
local mine = { daily = { enabled = false, puzzles = { day = "today", began = { maze = 1 } }, edition = { day = "today" } } }
local s2 = More.settings(reader, store, zen)
s2.reader.gzreader_sneaky_token = "x" -- (a sender that tries)
s2.reader.unknown_key = 1
s2.store.memos = { token = "y" }
local n = More.applySettings(s2, mine, function(k, v) saved[k] = v end)
check(saved.gzreader_wifi_mode == "auto" and saved.copt_font_size == 22 and saved.gzreader_sneaky_token == nil and saved.unknown_key == nil,
    "taken in: the same checks again (nothing else a sender puts in) (" .. n .. ")")
check(mine.memos == nil and mine.daily.enabled == true and mine.daily.feeds[1].url and mine.daily.puzzles.day == "today"
    and mine.daily.edition.day == "today", "the store's sections: the paper's choices come, its edition and today's puzzles here stay")

print("== game data")
check(More.games({}) == nil, "no game board records: nothing to send")
local them = { games = {
    enabled = true, history = { { t = 300, k = "maze", s = "Animals" }, { t = 100, k = "cross" } },
    unlocked = { first = 100, maze = 300 }, stats = { total = 2, counts = { maze = 1, cross = 1 } },
    books = { { key = "/a.epub", title = "A" } }, set = { title = "Animals" } },
    daily = { puzzles = { day = "2030-03-14", began = { sudoku = 5 }, sudoku = { fill = "1" } } } }
local g = More.games(them)
check(g.history[1].k == "maze" and g.paper_puzzles.day == "2030-03-14", "the records and today's paper puzzles")
local fresh = {}
More.mergeGames(fresh, g)
check(fresh.games.history[2].k == "cross" and fresh.games.unlocked.maze == 300 and fresh.daily.puzzles.day == "2030-03-14",
    "a Kindle with none: everything")
local here = { games = { history = { { t = 200, k = "words" }, { t = 100, k = "cross" } }, unlocked = { first = 50 }, stats = { total = 1 } },
    daily = { puzzles = { day = "2030-03-14", began = { maze = 9 } } } }
More.mergeGames(here, More.games(them))
local ks = {}
for _i, h in ipairs(here.games.history) do ks[#ks + 1] = h.k end
check(table.concat(ks, " ") == "maze words cross", "merged: each puzzle once, newest first (" .. table.concat(ks, " ") .. ")")
check(here.games.unlocked.first == 50 and here.games.unlocked.maze == 300 and here.games.stats.total == 2,
    "achievements at their earliest; the counts of whichever finished more")
check(here.daily.puzzles.began.maze == 9, "today's paper puzzles begun here stay")

print("== downloads")
files["/mnt/us/GZreader/books/a.epub"] = true
files["/mnt/us/GZreader/books/b.pdf"] = true
files["/mnt/us/GZreader/books/n.epub"] = true
local sender = { store = { server = "https://books.example.com/", downloads = {
    ["11"] = { path = "/mnt/us/GZreader/books/a.epub", title = "Alpha", format = "EPUB" },
    ["12"] = { path = "/mnt/us/GZreader/books/b.pdf", title = "Beta", format = "PDF" },
    ["13"] = { path = "/mnt/us/GZreader/books/n.epub", title = "Narrated", format = "EPUB" },
    ["14"] = { path = "/mnt/us/GZreader/books/gone.epub", title = "Deleted since" } } } }
local d = More.downloads(sender, function(path) return path:find("n.epub", 1, true) ~= nil end)
check(d.server == "books.example.com" and #d.books == 3 and d.books[1].title == "Alpha" and d.books[3].narrated == true and d.books[1].narrated == nil,
    "the books on the Kindle (not ones deleted since), narrated ones marked")
check(#d.audiobooks == 2 and d.audiobooks[1].id == "42" and d.audiobooks[2].plex.key == "/library/metadata/9" and d.audiobooks[2].plex.token == nil,
    "the audiobooks (not narrated books' stand-ins; a Plex one by its key, never a token)")
check(#d.music == 1 and d.music[1].key == "/library/metadata/77" and d.music[1].title == "Blue", "the music")
check(More.downloadsText(d) == "3 books (1 narrated), 2 audiobooks, 1 album or playlist", "in words: " .. More.downloadsText(d))

local saves = 0
local paired = false
local recv = { store = { downloads = { ["12"] = { path = "/mnt/us/GZreader/books/b.pdf" } }, audiobooks = {} },
    save = function() saves = saves + 1 end, api = { isPaired = function() return paired end } }
local kept = More.keepDownloads(recv, d)
check(kept == 5 and #recv.store.copy_pending.books == 2 and recv.store.copy_pending.server == "books.example.com",
    "kept to download: what isn't here already (" .. kept .. ")")
check(More.keepDownloads(recv, d) == 0, "copied twice: nothing twice")
local started = { book = {}, audiobook = {}, music = {} }
local start = { book = function(b) started.book[#started.book + 1] = b end, audiobook = function(a) started.audiobook[#started.audiobook + 1] = a end,
    music = function(m) started.music[#started.music + 1] = m end }
check(More.resume(recv, { start = start, now = true }) == 0 and #started.book == 0, "not signed in yet: nothing starts, it waits")
check(More.waitingText(recv):find("once this Kindle is signed in to books.example.com", 1, true)
    and More.waitingText(recv):find("connected to Plex", 1, true), "…and says what it waits for")
paired = true
recv.store.server = "https://other.example.com"
check(More.resume(recv, { start = start, now = true }) == 0, "signed in to another server: its ids are other books, nothing starts")
recv.store.server = "https://books.example.com"
local n2 = More.resume(recv, { start = start, now = true })
check(n2 == 4 and #started.book == 2 and started.book[2].narrated == true and #started.audiobook == 2 and #started.music == 0,
    "signed in to the same server: the books (narrated with their narration) and audiobooks start")
check(recv.store.copy_pending and #recv.store.copy_pending.books == 0 and #recv.store.copy_pending.music == 1, "the music still waits for Plex")
plex_on = true
More.resume(recv, { start = start, now = true })
check(#started.music == 1 and recv.store.copy_pending == nil, "Plex connected: the music too, and nothing waits any more")
local log = table.concat(logged, "\n")
check(not log:find("Alpha", 1, true) and not log:find("example.com", 1, true), "the log names no book and no server")

print("== the copy screen and the device's hooks")
local function read(p) local f = assert(io.open(p)); local t = f:read("*a"); f:close(); return t end
local csrc, msrc = read(PLUGIN .. "/gzreader_copy.lua"), read(PLUGIN .. "/main.lua")
check(csrc:find('toggle({ text = _("Settings")', 1, true) and csrc:find('toggle({ text = _("Game board")', 1, true)
    and csrc:find('toggle({ text = _("Downloads")', 1, true), "the copy's list has Settings, Game board and Downloads to switch on")
check(csrc:find("want.settings = offer.settings ~= nil and only == nil", 1, true), "all three on to begin with (not from the Notes or Calendar tab)")
check(csrc:find("More.resume(plugin)", 1, true) and msrc:find('pcall(require("gzreader_copymore").resume, self)', 1, true)
    and select(2, msrc:gsub('require%("gzreader_copymore"%)%.resume', "")) == 2,
    "downloads start after the copy, after signing in, and at the next Wi-Fi connection")

print(string.format("copy more: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
