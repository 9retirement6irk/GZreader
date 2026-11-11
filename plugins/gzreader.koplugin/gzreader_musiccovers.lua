--[[--
Album and playlist covers for the Catalog's Music page (the CD cases on its
shelves, gzreader_shopviews.lua): kept with the Catalog's book covers
(gzreader_covers.lua: cache/gzreader-covers/plex-<key>.jpg, the same memory
limit), from Plex's own scaled copy (Plex:downloadThumb, 300 px). An album
or playlist that's on the Kindle already has its cover.jpg in its folder: that
one is used, nothing fetched.
]]

local lfs = require("libs/libkoreader-lfs")

local MC = {
    SIZE = 300, running = false, pending = nil,
    tried = {}, -- (asked for once a session: one Plex can't scale, or that doesn't decode, isn't asked for at every redraw)
}

local function Covers() return require("gzreader_covers") end

--- The cover cache's id for a Plex item ({ key, type, thumb }).
function MC.id(it)
    return "plex-" .. tostring(it and it.key or ""):gsub("[^%w%-]", "_")
end

--- The folder of the album or playlist on the Kindle, or nil.
function MC.downloaded(plugin, it)
    if not (it and it.key and (it.type == "album" or it.type == "playlist")) then return nil end
    local ok, c = pcall(function()
        local Music = require("gzreader_music")
        return Music.load(Music.dirFor(plugin, it.type, it.key), { any = true })
    end)
    if ok and c and (c.have or 0) > 0 then return c end
    return nil
end

--- The cover fitted to w x h, or nil (not here yet).
function MC.image(plugin, it, w, h)
    local id = MC.id(it)
    local img = Covers().image(id, nil, w, h)
    if img then return img end
    -- on the Kindle: its folder's cover, copied into the cache once
    local c = MC.downloaded(plugin, it)
    local src = c and c.dir and (c.dir .. "/cover.jpg")
    if src and lfs.attributes(src, "mode") == "file" then
        local fi = io.open(src, "rb")
        local data = fi and fi:read("*a")
        if fi then fi:close() end
        local fo = data and io.open(Covers().path(id), "wb")
        if fo then fo:write(data); fo:close() end
        return Covers().image(id, nil, w, h)
    end
    return nil
end

--- Which of `list` (Plex items) have no cover here yet and can be fetched.
function MC.missing(list)
    local out = {}
    for _i, it in ipairs(list or {}) do
        if type(it) == "table" and it.thumb and it.key and not MC.tried[MC.id(it)] and Covers().state(MC.id(it)) == "missing" then
            out[#out + 1] = it
        end
    end
    return out
end

--- Fetch the missing covers of `list` in the background (Wi-Fi already up,
--- signed in to Plex), then on_done(got). One fetch at a time: a newer
--- request waits for the running one.
function MC.fetch(plugin, list, on_done)
    local todo = MC.missing(list)
    if #todo == 0 then return false end
    local ok_net, Net = pcall(require, "gzreader_net")
    if not (ok_net and Net.connected()) then return false end
    local Music = require("gzreader_music")
    local plex = Music.plex(plugin)
    if not plex:isConnected() then return false end
    if MC.running then
        MC.pending = { plugin = plugin, list = list, on_done = on_done }
        return true
    end
    MC.running = true
    local jobs = {}
    for _i, it in ipairs(todo) do
        MC.tried[MC.id(it)] = true
        jobs[#jobs + 1] = { thumb = it.thumb, path = Covers().path(MC.id(it)) }
    end
    require("gzreader_async").run(nil, function()
        local got = 0
        for _i, j in ipairs(jobs) do
            local tmp = j.path .. ".part"
            if plex:downloadThumb(j.thumb, tmp, MC.SIZE) and os.rename(tmp, j.path) then got = got + 1 else os.remove(tmp) end
        end
        return got
    end, function(got)
        MC.running = false
        if on_done then pcall(on_done, tonumber(got) or 0) end
        local nxt = MC.pending
        MC.pending = nil
        if nxt then MC.fetch(nxt.plugin, nxt.list, nxt.on_done) end
    end, "music covers")
    return true
end

return MC
