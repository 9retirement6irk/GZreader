--[[--
Book ratings, kept the same on the Kindle and in Grimmory.

KOReader keeps a rating of 1 to 5 stars in the book's settings (summary.rating:
the book's status page, the end-of-book page). Grimmory keeps a personal
rating of 1 to 10 for each user (its web reader shows it as 5 stars with
halves; Kobo sync doubles the stars the same way). So 4 stars here are 8
there, and 7 there are 4 stars here (rounded up).

Each Grimmory book on the Kindle remembers the last rating both sides agreed
on (entry.rating_synced; 0: none). Whichever side changed since then wins:
- changed on the Kindle: sent to Grimmory (queued while offline, like
  reading progress; removing the stars removes Grimmory's rating);
- changed in Grimmory: written into the book's settings here.

When: opening a book (Grimmory's record comes with the position), closing it,
and once after GZreader starts for books rated without being opened (from
the file browser), a few at a time.
]]

local Log = require("gzreader_log")

local Ratings = {}

--- Stars (1-5) or nil from a book's settings (a DocSettings).
function Ratings.localStars(doc_settings)
    if not doc_settings then return nil end
    local summary = doc_settings:readSetting("summary")
    local r = type(summary) == "table" and tonumber(summary.rating) or nil
    if not r or r < 1 then return nil end
    return math.min(5, math.floor(r + 0.5))
end

function Ratings.toGrimmory(stars)
    return stars and stars > 0 and math.min(10, stars * 2) or nil
end

function Ratings.fromGrimmory(value)
    local v = tonumber(value)
    if not v or v <= 0 then return nil end
    return math.max(1, math.min(5, math.ceil(v / 2)))
end

local function setLocal(doc_settings, stars)
    local summary = doc_settings:readSetting("summary")
    summary = type(summary) == "table" and summary or {}
    summary.rating = stars
    doc_settings:saveSetting("summary", summary)
end

--- The Kindle's rating changed since it last agreed with Grimmory? Queue it.
function Ratings.check(plugin, book_id, entry, doc_settings)
    if not entry then return false end
    local here = Ratings.localStars(doc_settings) or 0
    local synced = tonumber(entry.rating_synced)
    if synced == nil then
        -- (never compared: a rating made before 1.19 is sent; no rating waits for Grimmory's)
        if here == 0 then return false end
    elseif here == synced then
        return false
    end
    plugin.store.pending.ratings = plugin.store.pending.ratings or {}
    plugin.store.pending.ratings[tostring(book_id)] = here
    plugin:save()
    Log.info("rating changed on the Kindle", book_id, here, "stars")
    return true
end

--- Grimmory's record of an open book (`book`, from GET /books/{id}): take its
--- rating when only Grimmory's changed, send ours when ours did.
function Ratings.reconcile(plugin, book_id, entry, doc_settings, book)
    if not entry or type(book) ~= "table" or not doc_settings then return end
    local remote = Ratings.fromGrimmory(book.personalRating) or 0
    local here = Ratings.localStars(doc_settings) or 0
    local synced = tonumber(entry.rating_synced)
    local pending = plugin.store.pending.ratings
    if pending and pending[tostring(book_id)] ~= nil then return end -- ours is on its way
    if here == remote then
        if synced ~= here then entry.rating_synced = here; plugin:save() end
        return
    end
    -- the Kindle's changed since they last agreed (or, compared for the first
    -- time, it has one): send it. Otherwise only Grimmory's changed: take it.
    local kindle_changed
    if synced == nil then kindle_changed = here > 0 else kindle_changed = here ~= synced end
    if not kindle_changed then
        setLocal(doc_settings, remote > 0 and remote or nil)
        if doc_settings.flush then pcall(doc_settings.flush, doc_settings) end
        entry.rating_synced = remote
        plugin:save()
        Log.info("rating from Grimmory", book_id, remote, "stars")
        return "pulled"
    end
    Ratings.check(plugin, book_id, entry, doc_settings)
    return "pushed"
end

--- After GZreader starts: books rated in the file browser since. A few per
--- call (reading a book's settings is quick, but there may be hundreds).
function Ratings.sweep(plugin, limit)
    local DocSettings = require("docsettings")
    local lfs = require("libs/libkoreader-lfs")
    local open_file = plugin.ui and plugin.ui.document and plugin.ui.document.file
    local n, queued = 0, 0
    plugin._rating_sweep_done = plugin._rating_sweep_done or {}
    for book_id, entry in pairs(plugin.store.downloads or {}) do
        if n >= (limit or 40) then return queued, false end
        if not plugin._rating_sweep_done[book_id] then
            plugin._rating_sweep_done[book_id] = true
            local path = type(entry) == "table" and entry.path
            if path and path ~= open_file and lfs.attributes(path, "mode") == "file"
                    and DocSettings.hasSidecarFile and DocSettings:hasSidecarFile(path) then
                n = n + 1
                local ok, ds = pcall(DocSettings.open, DocSettings, path)
                if ok and ds and Ratings.check(plugin, book_id, entry, ds) then queued = queued + 1 end
            end
        end
    end
    return queued, true
end

return Ratings
