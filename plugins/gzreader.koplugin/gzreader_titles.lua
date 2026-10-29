--[[--
Book subtitles from Grimmory ("Diary of a Wimpy Kid: Old School").

Grimmory's app API lists books without subtitles, so they come from
- the library index (Grimmory's web book list, built in the background);
- the book itself (GET /api/v1/books/{id}) right after a download.

Shown in the Grimmory browser, and for downloaded books written as
KOReader custom metadata (the book's .sdr/custom_metadata.lua, as "Book
information → edit title" does), which is what Home, Downloaded, history and
the reader use. The original title is kept as the book's doc_props, so
resetting the title in Book information restores it.
]]

local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Log = require("gzreader_log")

local Titles = {}

local function trim(s) return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or nil end

--- "Title: Subtitle" (unless there's no subtitle, or the title already has it).
function Titles.full(title, subtitle)
    title, subtitle = trim(title), trim(subtitle)
    if not title or title == "" then return title end
    if not subtitle or subtitle == "" then return title end
    if title:lower():find(subtitle:lower(), 1, true) then return title end
    return title .. ": " .. subtitle
end

--- Subtitle known for a Grimmory book id (download record, then index).
function Titles.subtitle(plugin, book_id)
    local id = tostring(book_id)
    local e = plugin.store and plugin.store.downloads and plugin.store.downloads[id]
    if type(e) == "table" and type(e.subtitle) == "string" and e.subtitle ~= "" then return e.subtitle end
    local ok, Index = pcall(require, "gzreader_index")
    local data = ok and (Index.data or (plugin.store and Index.load(plugin.store)))
    local s = data and type(data.subtitles) == "table" and data.subtitles[id]
    return type(s) == "string" and s ~= "" and s or nil
end

function Titles.forBook(plugin, book)
    return Titles.full(type(book.title) == "string" and book.title or nil,
        book.subtitle or Titles.subtitle(plugin, book.id))
end

--- Give a downloaded file the full title (KOReader custom metadata).
--- Returns true when it changed something.
function Titles.apply(path, title, subtitle, authors)
    local full = Titles.full(title, subtitle)
    if not full or full == trim(title) or not path then return false end
    local DocSettings = require("docsettings")
    local file = DocSettings:findCustomMetadataFile(path)
    local cm = DocSettings.openSettingsFile(file)
    local custom = cm:readSetting("custom_props") or {}
    if custom.title == full then return false end
    if custom.title and custom.title ~= cm:readSetting("gzreader_title") then
        return false -- the user renamed the book themselves: leave it
    end
    if not cm:readSetting("doc_props") then
        cm:saveSetting("doc_props", { title = title, authors = authors })
    end
    custom.title = full
    cm:saveSetting("custom_props", custom)
    cm:saveSetting("gzreader_title", full)
    if not cm:flushCustomMetadata(path) then return false end
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", path))
    return true
end

--- Give books already on the Kindle their subtitles (after the index is built).
function Titles.backfill(plugin)
    local changed = 0
    for id, e in pairs(plugin.store.downloads or {}) do
        if type(e) == "table" and e.path then
            local sub = Titles.subtitle(plugin, id)
            if sub then
                local ok, did = pcall(Titles.apply, e.path, e.title, sub, nil)
                if ok and did then changed = changed + 1 end
            end
        end
    end
    if changed > 0 then
        Log.info("subtitles added to", changed, "downloaded book(s)")
        UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
    end
    return changed
end

return Titles
