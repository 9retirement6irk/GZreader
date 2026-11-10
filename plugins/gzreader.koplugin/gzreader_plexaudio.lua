--[[--
Audiobooks from a Plex library, instead of Grimmory's (Settings → Connections
→ Plex → Audiobooks): the Catalog's Audiobooks page (gzreader_browser.lua
asks PA.items when a Plex library is chosen), its lists and search. The
Bookshelf view's shelves (Continue listening, Recently added) are
gzreader_bookshop.lua's Shop.plexAudioLists.

An album of the library is an audiobook and its artist the author (how Plex
lays out audiobook libraries). Downloading and listening are
gzreader_audiobook.lua's, with ids "plex-<album key>" and the summary's
`plex` = { key, thumb }; covers come from Plex (gzreader_covers.lua notePlex).
]]

local _ = require("gettext")
local T = require("ffi/util").template

local PA = { LIMIT = 50 }

local function Plex() return require("gzreader_plex") end
local function plexOf(plugin) return require("gzreader_music").plex(plugin) end

--- The Plex library audiobooks come from ({ key, title }), or nil (Grimmory's).
function PA.section(plugin)
    local s = type(plugin) == "table" and type(plugin.store) == "table" and plugin.store.plex
    return Plex().audiobookSection(s)
end

--- A Plex album as an audiobook summary (what gzreader_audiobook.lua and the
--- Catalog's audiobook lines take), or nil. Pure.
function PA.book(it)
    if type(it) ~= "table" or not it.key or (it.type ~= nil and it.type ~= "album") then return nil end
    return { id = "plex-" .. tostring(it.key), plex = { key = tostring(it.key), thumb = it.thumb },
        title = it.title, authors = it.artist and { it.artist } or nil, primaryFileType = "AUDIOBOOK", year = it.year }
end

--- Plex albums as audiobook summaries. Pure.
function PA.books(list)
    local out = {}
    for _i, it in ipairs(type(list) == "table" and list or {}) do out[#out + 1] = PA.book(it) end
    return out
end

--- Plex's answer (list, total) as a page of Grimmory's lists (what
--- Browser:openList's fetch gives), `start`: where it began. Pure.
function PA.page(list, total, start)
    if type(list) ~= "table" then return nil, total end
    start = start or 0
    total = tonumber(total) or (start + #list)
    return { content = list, hasNext = start + #list < total, totalPages = math.max(1, math.ceil(total / Plex().PAGE)) }
end

--- A search through the audiobook library (Browser:promptSearch's scope).
function PA.scope(sec)
    return { title = _("Audiobooks"), plex = sec, audio = true }
end

local function searchLine(browser, sec)
    return { gz_action = "search", text = _("Search audiobooks…"), callback = function() browser:promptSearch(PA.scope(sec)) end }
end

local function bookLine(browser)
    return function(it)
        local b = PA.book(it)
        return b and browser:audiobookItem(b) or nil
    end
end

--- The Audiobooks page with a Plex library: search, Continue listening and
--- Recently added (the shelves), then All audiobooks, Authors, On this
--- Kindle and which Plex library (gz_kind "section": compartments in the
--- Bookshelf view).
function PA.items(browser, sec)
    local Browser = require("gzreader_browser")
    local here = Browser.audiobooksHere(browser.plugin)
    return {
        gz_root = true, -- (the Bookshelf view: a shop, gzreader_bookshop.lua)
        { gz_id = "ab_search", gz_action = "search", text = _("Search audiobooks…"),
            callback = function() browser:promptSearch(PA.scope(sec)) end },
        { gz_id = "ab_continue", text = _("Continue listening"), callback = function() browser:openAudioContinue() end },
        { gz_id = "ab_recent", text = _("Recently added"), callback = function() PA.openRecent(browser, sec) end },
        { gz_id = "ab_all", gz_kind = "section", gz_contents = "tapes", text = _("All audiobooks"), mandatory = _("A–Z"),
            callback = function() PA.openAll(browser, sec) end },
        { gz_id = "ab_authors", gz_kind = "section", gz_contents = "dividers", text = _("Authors"), mandatory = _("A–Z"),
            callback = function() PA.openAuthors(browser, sec) end },
        { gz_id = "ab_downloaded", gz_kind = "section", gz_contents = "tapes", text = _("On this Kindle"),
            mandatory = #here > 0 and Browser.audioCount(#here) or _("none yet"), callback = function() browser:openAudioDownloaded() end },
        { gz_id = "ab_plex", gz_kind = "section", gz_contents = "none", text = _("From Plex"), mandatory = sec.title or "?",
            callback = function()
                require("gzreader_musictab").chooseAudiobooks(browser.plugin, function()
                    if not browser.closed and browser.menu then browser:openSection("audiobooks") end
                end)
            end },
    }
end

--- All audiobooks: the library's albums, A–Z, a page at a time.
function PA.openAll(browser, sec)
    local plex = plexOf(browser.plugin)
    local size = Plex().PAGE
    browser:openList{
        title = _("All audiobooks"), key = "plex-audio:all:" .. tostring(sec.key),
        header = { searchLine(browser, sec) },
        fetch = function(page)
            local list, total = plex:list(sec.key, "albums", page * size)
            return PA.page(list, total, page * size)
        end,
        to_item = bookLine(browser),
    }
end

--- Recently added: the library's newest albums.
function PA.openRecent(browser, sec)
    local plex = plexOf(browser.plugin)
    browser:openList{
        title = _("Recently added"), key = "plex-audio:recent:" .. tostring(sec.key),
        fetch = function()
            local list, err = plex:recentAlbums(sec.key, "added", PA.LIMIT)
            if not list then return nil, err end
            return PA.page(list, #list, 0)
        end,
        to_item = bookLine(browser),
    }
end

--- Authors: the library's artists, A–Z, each opening its audiobooks.
function PA.openAuthors(browser, sec)
    local plex = plexOf(browser.plugin)
    local size = Plex().PAGE
    browser:openList{
        title = _("Authors"), key = "plex-audio:authors:" .. tostring(sec.key),
        fetch = function(page)
            local list, total = plex:list(sec.key, "artists", page * size)
            return PA.page(list, total, page * size)
        end,
        to_item = function(it)
            if type(it) ~= "table" or not it.key then return nil end
            return { text = it.title or "?", callback = function() PA.openAuthor(browser, it) end }
        end,
    }
end

--- An author's audiobooks.
function PA.openAuthor(browser, artist)
    local plex = plexOf(browser.plugin)
    browser:openList{
        title = artist.title or "?",
        fetch = function()
            local list, err = plex:children(artist.key)
            if not list then return nil, err end
            return PA.page(list, #list, 0)
        end,
        to_item = bookLine(browser),
    }
end

--- Search the audiobook library (Browser:search with a Plex scope).
function PA.search(browser, q, scope)
    local plex = plexOf(browser.plugin)
    browser:openList{
        title = T(_("%1: “%2”"), scope.title, q),
        header = { { gz_action = "search", text = _("Search again…"), callback = function() browser:promptSearch(scope, q) end } },
        empty_text = T(_("No audiobooks found containing “%1”"), q), empty_kind = "nothing_found",
        fetch = function()
            local res, err = plex:search(q, scope.plex.key)
            if not res then return nil, err end
            return PA.page(res.albums, #res.albums, 0)
        end,
        to_item = bookLine(browser),
    }
end

return PA
