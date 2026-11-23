--[[ GZreader: Home's recently read with the book server's books in progress
(Grimmory or BookOrbit), also the ones that aren't on this Kindle. The list,
the pictures and what a tap does are GZreader's (gzreader_serverrecent.lua,
through __GZ_SERVER_RECENT); this is what Home needs of it:

- merge(): the Kindle's own history and the server's list as one, newest
  first. A book on the Kindle keeps its path (moved up when it was read later
  on another device); one that isn't here gets a key (PREFIX .. id) in place
  of a path.
- book(): Home's record for such a key; tape(): an audiobook's stand-in
  drawn as a cassette.
- warm(): the picture for a strip cover, into the render cache.
]]

local M = { PREFIX = "gzserver:", TAPE_W = 155, TAPE_H = 100 }

local function hook()
    local h = rawget(_G, "__GZ_SERVER_RECENT")
    return type(h) == "table" and h or nil
end

local function call(name, ...)
    local h = hook()
    if not (h and type(h[name]) == "function") then return nil end
    local ok, a = pcall(h[name], ...)
    if ok then return a end
    return nil
end

function M.available() return hook() ~= nil end
function M.on() return call("on") == true end
function M.set(on) return call("set", on) end
function M.serverName() return call("name") or "Grimmory" end

function M.isKey(path)
    return type(path) == "string" and path:sub(1, #M.PREFIX) == M.PREFIX
end

--- Changes when Home's history has to be put together again.
function M.stamp()
    return tostring(call("stamp") or "")
end

function M.entries()
    local list = call("list")
    return type(list) == "table" and list or {}
end

--- paths: the Kindle's history, newest first; times[path]: when (epoch);
--- entries: the server's ({ key, time, path? … }). Returns the merged paths
--- (at most `limit`) and { key = entry } for the ones that aren't here.
function M.merge(paths, times, entries, limit)
    local items, by_path = {}, {}
    for i, path in ipairs(paths) do
        local it = { path = path, time = tonumber(times[path]) or 0, order = i }
        items[#items + 1] = it
        by_path[path] = it
    end
    local n = #items
    for j, e in ipairs(entries) do
        local t = tonumber(e.time) or 0
        local here = e.path and by_path[e.path]
        if here then
            if t > here.time then here.time = t end
        elseif type(e.path) == "string" and e.path ~= "" then
            -- on the Kindle, not in its history (read on another device only)
            local it = { path = e.path, time = t, order = n + j }
            items[#items + 1] = it
            by_path[e.path] = it
        elseif M.isKey(e.key) and not by_path[e.key] then
            local it = { path = e.key, time = t, order = n + j, entry = e }
            items[#items + 1] = it
            by_path[e.key] = it
        end
    end
    table.sort(items, function(a, b)
        if a.time ~= b.time then return a.time > b.time end
        return a.order < b.order
    end)
    local out, not_here = {}, {}
    for _i, it in ipairs(items) do
        if limit and #out >= limit then break end
        out[#out + 1] = it.path
        if it.entry then not_here[it.path] = it.entry end
    end
    return out, not_here
end

local function tape_dims(dims)
    local w = type(dims) == "table" and tonumber(dims.w) or 240
    return math.floor(w), math.max(1, math.floor(w * M.TAPE_H / M.TAPE_W + 0.5))
end

-- The picture: at once for the big current book, afterwards (warm) for a strip.
local function dress(book, key, audio, metadata_only, dims)
    if audio then
        book.gz_shape = { M.TAPE_W, M.TAPE_H }
        book.cover_w, book.cover_h = M.TAPE_W, M.TAPE_H
        book.has_real_cover = true
    else
        book.has_real_cover = call("hasCover", key) == true
    end
    if not book.has_real_cover then return book end
    if metadata_only then
        book.is_cover_pending = true
        return book
    end
    local w, h
    if audio then w, h = tape_dims(dims) else w, h = dims and dims.w, dims and dims.h end
    book.cover_bb = call("cover", key, w, h)
    if not book.cover_bb then book.has_real_cover = false end
    return book
end

--- Home's record of a book that isn't on this Kindle.
function M.book(e, metadata_only, dims)
    local pct = tonumber(e.percent)
    local book = {
        path = e.key, title = e.title or "", authors = e.authors or "",
        status = "reading", percent = pct or 0, percent_finished = pct,
        bookinfo = { title = e.title, authors = e.authors },
        gz_server = true, gz_cover_key = e.key,
        _zen_cover_loaded = not metadata_only, _zen_full_status = not metadata_only,
    }
    return dress(book, e.key, e.audio == true, metadata_only, dims)
end

--- The audiobook a stand-in file is for ({ id, title }) when audiobooks are
--- drawn as cassettes (the option is on), else nil.
function M.standIn(path)
    if not M.on() then return nil end
    local t = call("standIn", path)
    return type(t) == "table" and t or nil
end

--- An audiobook on the Kindle (its stand-in's record) as a cassette.
function M.asTape(book, metadata_only, dims)
    if type(book) ~= "table" or type(book.path) ~= "string" then return book end
    if book.cover_bb and book.cover_bb.free then pcall(book.cover_bb.free, book.cover_bb) end
    book.cover_bb = nil
    book.is_cover_pending = nil
    book.gz_cover_key = "gztape:" .. book.path
    return dress(book, book.path, true, metadata_only, dims)
end

--- A strip cover's picture into the render cache (provider:warmStripCover).
function M.warm(book, width, height, RenderCache)
    local key = book.gz_cover_key
    if type(key) ~= "string" then return "failed" end
    -- (a cassette: the size its shape gets in that room, unless that's it already)
    if type(book.gz_shape) == "table" then
        local sw, sh = book.gz_shape[1], book.gz_shape[2]
        if math.abs(width * sh - height * sw) > math.max(width, height, sw, sh) then
            local scale = math.min(width / sw, height / sh)
            width, height = math.max(1, math.floor(sw * scale + 0.5)), math.max(1, math.floor(sh * scale + 0.5))
        end
    end
    if type(RenderCache.hasReusable) == "function" and RenderCache:hasReusable(key, width, height) then
        return "cached"
    end
    local source = call("cover", book.path, width, height)
    if not source then return "failed" end
    local final, owned = RenderCache:renderShared(key, source, width, height)
    if not final then return "failed" end
    if owned then
        RenderCache:releaseShared(key, final)
        return "warmed"
    end
    if final.free then pcall(final.free, final) end
    return "failed"
end

function M.open(key)
    return call("open", key) == true
end

return M
