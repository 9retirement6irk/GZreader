--[[--
Grimmory covers for the Grimmory tab, kept fast on a Kindle 3.

Grimmory has no small cover size: its thumbnail is 250 x 350 (audiobooks
250 x 250), 10–20 KB. So:
- each thumbnail is downloaded once and kept in koreader/cache/gzreader-covers
  (<id>.jpg, <id>-a.jpg for audiobook covers; a <id>.none marker when
  Grimmory has none, so it isn't asked again);
- only the covers of the page on screen are fetched, in the background
  process, one page at a time;
- each is decoded and shrunk once per size, and the result kept in memory
  for the session (a few dozen small images).
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local Covers = {
    MEMORY = 60,           -- shrunk covers kept in memory
    memory = {},           -- key -> { bb, used }
    pending = nil,         -- the request waiting for the running fetch
    running = false,
}

function Covers.dir()
    local dir = DataStorage:getDataDir() .. "/cache/gzreader-covers"
    if not Covers.dir_ok then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(dir)
        Covers.dir_ok = true
    end
    return dir
end

local function base(id, kind)
    return Covers.dir() .. "/" .. tostring(id) .. (kind == "audiobook" and "-a" or "")
end

function Covers.path(id, kind) return base(id, kind) .. ".jpg" end

--- "have", "none" (Grimmory has no cover) or "missing".
function Covers.state(id, kind)
    local b = base(id, kind)
    if lfs.attributes(b .. ".jpg", "mode") == "file" then return "have" end
    if lfs.attributes(b .. ".none", "mode") == "file" then return "none" end
    return "missing"
end

--- The cover shrunk to fit w x h (keeping its shape), or nil if not here.
function Covers.image(id, kind, w, h)
    local key = tostring(id) .. (kind or "") .. "@" .. w .. "x" .. h
    local m = Covers.memory[key]
    if m then
        m.used = os.time()
        return m.bb
    end
    local path = Covers.path(id, kind)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local RenderImage = require("ui/renderimage")
    local ok, bb = pcall(RenderImage.renderImageData, RenderImage, data, #data, false)
    if not ok or not bb then
        Log.warn("cover: can't decode", path)
        os.remove(path)
        return nil
    end
    local bw, bh = bb:getWidth(), bb:getHeight()
    local scale = math.min(w / bw, h / bh)
    local tw, th = math.max(1, math.floor(bw * scale + 0.5)), math.max(1, math.floor(bh * scale + 0.5))
    if tw ~= bw or th ~= bh then
        bb = RenderImage:scaleBlitBuffer(bb, tw, th, true)
    end
    -- keep the memory bounded: drop the least recently used
    local n, oldest_key, oldest = 0, nil, math.huge
    for k, v in pairs(Covers.memory) do
        n = n + 1
        if v.used < oldest then oldest_key, oldest = k, v.used end
    end
    if n >= Covers.MEMORY and oldest_key then
        Covers.memory[oldest_key].bb:free()
        Covers.memory[oldest_key] = nil
    end
    Covers.memory[key] = { bb = bb, used = os.time() }
    return bb
end

--- Fetch the missing covers among `wanted` ({ { id, kind } }) in the
--- background, then on_done(got). Only when Wi-Fi is already up; one fetch
--- at a time (a newer request replaces one still waiting).
function Covers.fetch(plugin, wanted, on_done)
    local items = {}
    for _i, w in ipairs(wanted) do
        if Covers.state(w.id, w.kind) == "missing" then
            items[#items + 1] = { id = w.id, kind = w.kind, path = Covers.path(w.id, w.kind) }
        end
    end
    if #items == 0 then return false end
    if not (plugin.api and plugin.api:isPaired()) then return false end
    local ok_net, Net = pcall(require, "gzreader_net")
    if not (ok_net and Net.connected()) then return false end
    if Covers.running then
        Covers.pending = { plugin = plugin, wanted = wanted, on_done = on_done }
        return true
    end
    Covers.running = true
    require("gzreader_async").call(plugin.api, "downloadThumbnails", { items }, function(res)
        Covers.running = false
        if type(res) == "table" then
            for _i, id in ipairs(res.none or {}) do
                for _j, it in ipairs(items) do
                    if tostring(it.id) == tostring(id) then
                        local f = io.open(base(it.id, it.kind) .. ".none", "wb")
                        if f then f:close() end
                    end
                end
            end
        end
        local got = type(res) == "table" and tonumber(res.got) or 0
        if on_done then pcall(on_done, got) end
        local nxt = Covers.pending
        Covers.pending = nil
        if nxt then Covers.fetch(nxt.plugin, nxt.wanted, nxt.on_done) end
    end)
    return true
end

--- Forget the shrunk covers in memory (e.g. leaving the Grimmory tab).
function Covers.release()
    for _k, v in pairs(Covers.memory) do pcall(v.bb.free, v.bb) end
    Covers.memory = {}
end

return Covers
