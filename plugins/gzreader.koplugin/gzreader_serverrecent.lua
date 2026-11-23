--[[--
Home's recently read, from the book server (Grimmory or BookOrbit): what you're
in the middle of on any device, also the books and audiobooks that aren't on
this Kindle. An option of Home (Recent strip → "Recently read on every
device"), off unless chosen.

- The list: the server's books in progress (continueReading) and audiobooks in
  progress (continueListening: BookOrbit's need its API key), newest first.
  Kept in the store (titles and times: nothing secret), from the server and
  user it was asked of; asked again in the background when Home shows and it's
  older than TTL. Only when Wi-Fi is already on: never turned on for this.
- ZenOS's Home merges it with the Kindle's own history by time
  (common/gz_server_recent.lua): a book on the Kindle keeps its own entry
  (moved up when it was read later elsewhere); one that isn't here gets an
  entry of its own, keyed PREFIX .. id, with the server's cover and a small
  arrow on it.
- Audiobooks are drawn as cassettes (the shelf's: gzreader_shelfview.lua),
  the ones on the Kindle too.
- A tap: a book on the Kindle opens; one that isn't shows its page (Download,
  Download & open); an audiobook asks to download it, or plays.
]]

local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local Recent = {
    TTL = 600,          -- asked again after 10 minutes
    BOOKS = 12,         -- books in progress asked for
    AUDIO = 6,          -- audiobooks (BookOrbit: one more request each, for its time)
    SETTING = "gzreader_home_server_recent",
    PREFIX = "gzserver:",
    TAPE = { 155, 100 }, -- a cassette facing out: its shape
}

function Recent.on()
    return G_reader_settings:isTrue(Recent.SETTING)
end

local function days(y, m, d)
    -- days since 1970-01-01 (the civil calendar; no time zone involved)
    if m <= 2 then y = y - 1 end
    local era = math.floor(y / 400)
    local yoe = y - era * 400
    local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
end

--- "2026-11-22T20:10:05.123Z" (or with +01:00; none: UTC) as seconds since 1970, or nil.
function Recent.epoch(iso)
    if type(iso) == "number" then return iso > 1e11 and math.floor(iso / 1000) or iso end
    if type(iso) ~= "string" then return nil end
    local y, mo, d, h, mi, s, rest = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):?(%d*)(.*)$")
    if not y then return nil end
    local t = days(tonumber(y), tonumber(mo), tonumber(d)) * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + (tonumber(s) or 0)
    local sign, oh, om = rest:match("([%+%-])(%d%d):?(%d%d)$")
    if sign then t = t - (sign == "-" and -1 or 1) * (tonumber(oh) * 3600 + tonumber(om) * 60) end
    return t
end

local KEEP = { "id", "title", "authors", "primaryFileType", "primaryFileName", "fileSizeKb", "readProgress",
    "seriesName", "seriesNumber", "coverUpdatedOn", "libraryId" }

--- One of the server's books as kept: { id, title, authors, audio, pct (0–100), at, book }.
function Recent.item(book)
    if type(book) ~= "table" or book.id == nil then return nil end
    local slim = {}
    for _i, k in ipairs(KEEP) do slim[k] = book[k] end
    local authors = type(book.authors) == "table" and table.concat(book.authors, ", ") or ""
    return {
        id = tostring(book.id),
        title = type(book.title) == "string" and book.title ~= "" and book.title or "?",
        authors = authors,
        audio = type(book.primaryFileType) == "string" and book.primaryFileType:upper() == "AUDIOBOOK" or nil,
        pct = tonumber(book.readProgress),
        at = Recent.epoch(book.lastReadTime),
        book = slim,
    }
end

--- Both lists as one, newest first (those with no time last, in the server's order).
function Recent.combine(books, audio)
    local items, seen = {}, {}
    for _i, src in ipairs({ books or {}, audio or {} }) do
        for _j, b in ipairs(src) do
            local it = Recent.item(b)
            if it and not seen[it.id] then
                seen[it.id] = true
                it.order = #items + 1
                items[#items + 1] = it
            end
        end
    end
    table.sort(items, function(a, b)
        local ta, tb = a.at or 0, b.at or 0
        if ta ~= tb then return ta > tb end
        return a.order < b.order
    end)
    for _i, it in ipairs(items) do it.order = nil end
    return items
end

--- Ask the server (in the background process).
function Recent.fetchFor(api)
    local books, err = api:continueReading(Recent.BOOKS)
    local audio
    if type(api.continueListening) == "function" then audio = api:continueListening(Recent.AUDIO) end
    if type(books) ~= "table" and type(audio) ~= "table" then return { error = tostring(err or "failed") } end
    return { items = Recent.combine(type(books) == "table" and books or nil, type(audio) == "table" and audio or nil) }
end

local function who(plugin)
    return table.concat({ plugin:backend(), tostring(plugin.store.server), tostring(plugin.store.username) }, "|")
end

--- The list kept, when it's this server's and this user's.
function Recent.kept(plugin)
    local k = plugin.store.server_recent
    if type(k) ~= "table" or k.who ~= who(plugin) or type(k.items) ~= "table" then return nil end
    return k
end

local function signature(items)
    local parts = {}
    for _i, it in ipairs(items or {}) do
        parts[#parts + 1] = it.id .. ":" .. tostring(it.at) .. ":" .. tostring(it.pct and math.floor(it.pct) or "")
    end
    return table.concat(parts, ",")
end

local function redraw()
    require("ui/uimanager"):nextTick(function() pcall(function() require("common/gz_view").redrawHome() end) end)
end

local function coverKind(it) return it.audio and "audiobook" or nil end

--- The covers of the ones that aren't on the Kindle (Home redraws when they're here).
function Recent.fetchCovers(plugin, items)
    local ok, Covers = pcall(require, "gzreader_covers")
    if not ok then return end
    local wanted = {}
    for _i, it in ipairs(items or {}) do
        if not Recent.pathFor(plugin, it) then wanted[#wanted + 1] = { id = it.book.id, kind = coverKind(it) } end
    end
    if #wanted == 0 then return end
    Covers.fetch(plugin, wanted, function(got)
        if (tonumber(got) or 0) < 1 then return end
        -- (a cassette drawn before its cover came: drawn again)
        pcall(function()
            local RC = require("common/cover_render_cache")
            for _i, it in ipairs(items) do RC:drop(Recent.PREFIX .. it.id) end
        end)
        Recent.bump()
        redraw()
    end)
end

Recent.rev = 0
function Recent.bump() Recent.rev = Recent.rev + 1 end

--- Fetch it if it's old (and Wi-Fi is on): Home redraws when it changed.
function Recent.refresh(plugin, force)
    if Recent.busy or not Recent.on() or not (plugin.api and plugin.api:isPaired()) then return end
    local kept = Recent.kept(plugin)
    if not force and kept and os.time() - (tonumber(kept.at) or 0) < Recent.TTL then return end
    if not require("ui/network/manager"):isConnected() then return end
    Recent.busy = true
    local asked_of = who(plugin)
    require("gzreader_async").run(plugin.api, function(api) return Recent.fetchFor(api) end, function(res)
        Recent.busy = nil
        if type(res) ~= "table" or asked_of ~= who(plugin) then return end
        if res.error or type(res.items) ~= "table" then
            Log.warn(plugin:serverName(), "recently read:", tostring(res.error))
            -- (not asked again at every redraw of Home: after TTL)
            plugin.store.server_recent = { at = os.time(), who = asked_of, items = kept and kept.items or {}, error = tostring(res.error) }
            plugin:save()
            return
        end
        local before = kept and signature(kept.items) or nil
        plugin.store.server_recent = { at = os.time(), who = asked_of, items = res.items }
        plugin:save()
        Log.info(plugin:serverName(), "recently read:", #res.items, "in progress")
        if signature(res.items) ~= before then
            Recent.bump()
            redraw()
        end
        Recent.fetchCovers(plugin, res.items)
    end, "recently read")
end

--- After this Kindle's reading reached the server: asked again next time.
function Recent.stale(plugin)
    if type(plugin.store.server_recent) == "table" then plugin.store.server_recent.at = 0 end
end

--- Where `it` is on this Kindle (a book's file; an audiobook's stand-in), or nil.
function Recent.pathFor(plugin, it)
    if it.audio then
        local ok, Folder = pcall(require, "gzreader_abfolder")
        if not ok then return nil end
        -- (the store's key is the id as the server gave it, or as text once saved)
        for _i, id in ipairs({ it.book and it.book.id, it.id, tonumber(it.id) }) do
            local path = id ~= nil and Folder.stubPath(plugin, id) or nil
            if path and lfs.attributes(path, "mode") == "file" then return path end
        end
        return nil
    end
    return plugin:localPathFor(it.id)
end

--- For Home: { { key, id, title, authors, audio, percent (0–1), time, path } }, newest
--- first; {} when the option is off or nobody is signed in.
function Recent.entries(plugin)
    if not Recent.on() or not (plugin.api and plugin.api:isPaired()) then return {} end
    pcall(Recent.refresh, plugin)
    local kept = Recent.kept(plugin)
    local out = {}
    for _i, it in ipairs(kept and kept.items or {}) do
        out[#out + 1] = {
            key = Recent.PREFIX .. it.id, id = it.id, title = it.title, authors = it.authors, audio = it.audio or nil,
            percent = it.pct and math.max(0, math.min(1, it.pct / 100)) or nil,
            time = it.at or 0,
            path = Recent.pathFor(plugin, it),
        }
    end
    return out
end

--- Changes when what Home should show changed (the option, the list, a cover).
function Recent.stamp(plugin)
    if not Recent.on() then return "" end
    local kept = Recent.kept(plugin)
    return table.concat({ "on", tostring(Recent.rev), kept and signature(kept.items) or "" }, "|")
end

local function find(plugin, key)
    local id = type(key) == "string" and key:sub(1, #Recent.PREFIX) == Recent.PREFIX and key:sub(#Recent.PREFIX + 1) or nil
    local kept = id and Recent.kept(plugin)
    for _i, it in ipairs(kept and kept.items or {}) do
        if it.id == id then return it end
    end
end
Recent.find = find

--- The audiobook a stand-in `path` is for, when the option is on: { id, title }.
function Recent.standIn(plugin, path)
    if not Recent.on() then return nil end
    local ok, Folder = pcall(require, "gzreader_abfolder")
    local id = ok and Folder.idForPath(plugin, path) or nil
    if not id then return nil end
    local e = plugin.store.audiobooks and plugin.store.audiobooks[id]
    return { id = tostring(id), title = type(e) == "table" and e.title or "", here = true }
end

local function coverFile(plugin, id, audio, here)
    local Covers = require("gzreader_covers")
    if here and audio then
        local ok, Audiobook = pcall(require, "gzreader_audiobook")
        local dir = ok and Audiobook.dir and Audiobook.dir(plugin, id) or nil
        if dir and lfs.attributes(dir .. "/cover.jpg", "mode") == "file" then return dir .. "/cover.jpg" end
    end
    if audio and Covers.state(id, "audiobook") == "have" then return Covers.path(id, "audiobook") end
    if Covers.state(id) == "have" then return Covers.path(id) end
end

--- Is there a picture for `key` (a book that isn't here)? An audiobook always has
--- one: its cassette.
function Recent.hasCover(plugin, key)
    local it = find(plugin, key)
    if not it then return false end
    return it.audio == true or coverFile(plugin, it.book.id, false) ~= nil
end

local function decode(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local RenderImage = require("ui/renderimage")
    local ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    return ok and bb or nil
end

--- A small arrow in the corner: not on this Kindle yet.
local function arrow(bb)
    local Blitbuffer = require("ffi/blitbuffer")
    local w, h = bb:getWidth(), bb:getHeight()
    local r = math.max(7, math.floor(math.min(w, h) * 0.11))
    local cx, cy = w - r - math.max(2, math.floor(r / 3)), h - r - math.max(2, math.floor(r / 3))
    bb:paintCircle(cx, cy, r, Blitbuffer.COLOR_BLACK)
    bb:paintCircle(cx, cy, r - math.max(1, math.floor(r / 6)), Blitbuffer.COLOR_WHITE)
    local t = math.max(1, math.floor(r / 4))
    local half = math.floor(r * 0.5)
    bb:paintRect(cx - math.floor(t / 2), cy - half, t, half + 1, Blitbuffer.COLOR_BLACK) -- the shaft
    for i = 0, half do -- the head, its point down
        bb:paintRect(cx - (half - i), cy + i, 2 * (half - i) + 1, 1, Blitbuffer.COLOR_BLACK)
    end
end

--- An audiobook as a cassette, w x h (white around it), with its cover on the label.
function Recent.tape(plugin, id, title, w, h, here)
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen = require("device").screen
    local View = require("gzreader_shelfview")
    local colour = Screen.isColorEnabled and Screen:isColorEnabled()
    local bb = Blitbuffer.new(w, h, colour and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local shadow = Screen:scaleBySize(4)
    local tw, th = w - shadow, h - shadow
    local cover, cover_bb
    local file = coverFile(plugin, id, true, here)
    local side = math.min(math.floor(th * 0.62) - Screen:scaleBySize(12), Screen:scaleBySize(40))
    if file and side >= 8 then
        local src = decode(file)
        if src then
            local scale = math.min(side / src:getWidth(), side / src:getHeight())
            cover_bb = require("ui/renderimage"):scaleBlitBuffer(src, math.max(1, math.floor(src:getWidth() * scale)),
                math.max(1, math.floor(src:getHeight() * scale)), true)
            cover = require("ui/widget/imagewidget"):new{ image = cover_bb, image_disposable = false, scale_factor = 1 }
        end
    end
    View.tapeFront(bb, 0, th, tw, th, title or "", cover)
    if cover then cover:free() end
    if cover_bb then cover_bb:free() end
    return bb
end

--- The picture Home draws for `key` (a book that isn't here: its cover with the
--- arrow; an audiobook: its cassette) or for an audiobook's stand-in `path`, at
--- about w x h. The caller owns it. nil: none.
function Recent.cover(plugin, key, w, h)
    w, h = math.max(16, math.floor(tonumber(w) or 160)), math.max(16, math.floor(tonumber(h) or 240))
    local it = find(plugin, key)
    if it and it.audio then
        local bb = Recent.tape(plugin, it.book.id, it.title, w, h, false)
        arrow(bb)
        return bb
    elseif it then
        local file = coverFile(plugin, it.book.id, false)
        local bb = file and decode(file) or nil
        if bb then arrow(bb) end
        return bb
    end
    local tape = Recent.standIn(plugin, key)
    if tape then return Recent.tape(plugin, tape.id, tape.title, w, h, true) end
end

--- A tap on `key` on Home.
function Recent.open(plugin, key)
    local it = find(plugin, key)
    if not it then return false end
    local path = Recent.pathFor(plugin, it)
    if it.audio then
        require("gzreader_audiobook").choose(plugin, it.book)
        return true
    end
    if path then
        plugin:openBook(path)
        return true
    end
    require("gzreader_browser"):new(plugin):onBook(it.book)
    return true
end

--- The option, from Home's settings.
function Recent.set(plugin, on)
    if on then G_reader_settings:makeTrue(Recent.SETTING) else G_reader_settings:delSetting(Recent.SETTING) end
    Recent.bump()
    if on then
        Recent.stale(plugin)
        pcall(Recent.refresh, plugin)
    end
end

--- What ZenOS's Home asks through (common/gz_server_recent.lua).
function Recent.hook(plugin)
    return {
        on = Recent.on,
        set = function(on) return Recent.set(plugin, on) end,
        name = function() return plugin:serverName() end,
        list = function() return Recent.entries(plugin) end,
        stamp = function() return Recent.stamp(plugin) end,
        hasCover = function(key) return Recent.hasCover(plugin, key) end,
        cover = function(key, w, h) return Recent.cover(plugin, key, w, h) end,
        standIn = function(path) return Recent.standIn(plugin, path) end,
        open = function(key) return Recent.open(plugin, key) end,
    }
end

return Recent
