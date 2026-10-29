--[[--
GZreader: covers pre-sized on disk.

ZenOS scales every cover to the exact size of the place it's shown (Home,
the cover strip, the library grid and list) and keeps the result in memory
(cover_render_cache). On a Kindle 3 that scaling is slow (seconds for a Home
screen) and the memory cache is small and starts empty after every restart,
so it happened over and over.

This keeps each final-size cover as a raw bitmap file:
  <data>/cache/gz-covers/<md5 of path>-<w>x<h>.bb
Loading one is a file read and a memory copy: no decompression, no scaling.
A file is only used while the book file has the same size and date as when
it was made; dropping a book's cached covers (new cover, metadata reset)
deletes them.

It also remembers the sizes ZenOS asks for (the boxes covers are fitted into,
and exact crop sizes), so GZreader's background job (grimmory_coverwarm) can
pre-size the covers of every downloaded book before they're shown.
]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5

local M = {
    MAGIC = "GZC1",
    MAX_SIZES = 10,
    enabled = not (G_reader_settings and G_reader_settings:isFalse("gzreader_presize_covers")),
}

local dir_ready
function M.dir()
    local d = DataStorage:getDataDir() .. "/cache/gz-covers"
    if not dir_ready then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(d)
        dir_ready = true
    end
    return d
end

local function prefix(path) return md5(tostring(path)) end

function M.file(path, w, h)
    return string.format("%s/%s-%dx%d.bb", M.dir(), prefix(path), w, h)
end

local function signature(path)
    local attr = lfs.attributes(path)
    if not attr then return nil end
    return string.format("%d:%d", tonumber(attr.size) or 0, tonumber(attr.modification) or 0)
end

local function readHeader(f)
    local line = f:read("*l")
    if not line then return nil end
    local magic, sig, w, h, t, stride = line:match("^(%w+) (%S+) (%d+) (%d+) (%d+) (%d+)$")
    if magic ~= M.MAGIC then return nil end
    return sig, tonumber(w), tonumber(h), tonumber(t), tonumber(stride)
end

--- Is a fresh pre-sized cover on disk?
function M.has(path, w, h)
    if not M.enabled or not path or not w or not h then return false end
    local f = io.open(M.file(path, w, h), "rb")
    if not f then return false end
    local sig = readHeader(f)
    f:close()
    return sig ~= nil and sig == signature(path)
end

--- Load the pre-sized cover (a new, caller-owned Blitbuffer) or nil.
function M.load(path, w, h)
    if not M.enabled or not path or not w or not h then return nil end
    local name = M.file(path, w, h)
    local f = io.open(name, "rb")
    if not f then return nil end
    local sig, fw, fh, t, stride = readHeader(f)
    if not sig or sig ~= signature(path) or fw ~= w or fh ~= h then
        f:close()
        os.remove(name) -- stale (the book changed)
        return nil
    end
    local data = f:read("*a")
    f:close()
    if not data or #data ~= stride * h then os.remove(name); return nil end
    local ok, bb = pcall(Blitbuffer.new, w, h, t)
    if not ok or not bb then return nil end
    if tonumber(bb.stride) ~= stride then bb:free(); os.remove(name); return nil end
    ffi.copy(bb.data, data, #data)
    return bb
end

--- Save a final-size cover (bb is not modified or freed).
function M.save(path, w, h, bb)
    if not M.enabled or not path or not bb then return false end
    local sig = signature(path)
    if not sig then return false end
    local ok, t, stride, bh = pcall(function() return bb:getType(), tonumber(bb.stride), bb:getHeight() end)
    if not ok or not stride or bh ~= h or bb:getWidth() ~= w then return false end
    if bb.getRotation and bb:getRotation() ~= 0 then return false end
    if bb.getInverse and bb:getInverse() ~= 0 then return false end
    local name = M.file(path, w, h)
    local tmp = name .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return false end
    f:write(string.format("%s %s %d %d %d %d\n", M.MAGIC, sig, w, h, t, stride))
    f:write(ffi.string(bb.data, stride * h))
    f:close()
    return os.rename(tmp, name) and true or false
end

--- Forget a book's pre-sized covers.
function M.drop(path)
    if not path then return end
    local p = prefix(path)
    local d = M.dir()
    for name in lfs.dir(d) do
        if name:sub(1, #p) == p then os.remove(d .. "/" .. name) end
    end
end

--- Files and bytes on disk.
function M.usage()
    local d, n, bytes = M.dir(), 0, 0
    for name in lfs.dir(d) do
        if name:match("%.bb$") then
            n = n + 1
            bytes = bytes + (lfs.attributes(d .. "/" .. name, "size") or 0)
        end
    end
    return n, bytes
end

function M.clear()
    local d = M.dir()
    for name in lfs.dir(d) do
        if name:match("%.bb$") or name:match("%.tmp$") then os.remove(d .. "/" .. name) end
    end
end

---------------------------------------------------------------- sizes in use

local function sizes()
    local s = G_reader_settings:readSetting("gzreader_cover_sizes")
    if type(s) ~= "table" then s = { boxes = {}, exact = {} } end
    s.boxes, s.exact = s.boxes or {}, s.exact or {}
    return s
end

local function remember(list, w, h)
    w, h = math.floor(w + 0.5), math.floor(h + 0.5)
    for i, e in ipairs(list) do
        if e[1] == w and e[2] == h then
            if i > 1 then table.remove(list, i); table.insert(list, 1, e) end -- most recent first
            return false
        end
    end
    table.insert(list, 1, { w, h })
    while #list > M.MAX_SIZES do table.remove(list) end
    return true
end

local big
local function plausible(w, h)
    if not big then
        local Screen = require("device").screen
        big = math.max(Screen:getWidth(), Screen:getHeight())
    end
    return type(w) == "number" and type(h) == "number" and w >= 24 and h >= 24 and w <= big and h <= big
end

--- A box covers are fitted into (CoverUtils.fitDims), e.g. a Home tile.
function M.recordBox(w, h)
    if not plausible(w, h) then return end
    local s = sizes()
    if remember(s.boxes, w, h) then
        G_reader_settings:saveSetting("gzreader_cover_sizes", s)
        if M.on_new_size then pcall(M.on_new_size) end
    end
end

--- An exact (cropped) size, e.g. list thumbnails.
function M.recordExact(w, h)
    if not plausible(w, h) then return end
    local s = sizes()
    if remember(s.exact, w, h) then
        G_reader_settings:saveSetting("gzreader_cover_sizes", s)
        if M.on_new_size then pcall(M.on_new_size) end
    end
end

--- The sizes a cover of source size sw x sh is shown at.
function M.targetsFor(sw, sh)
    local CoverUtils = require("common/cover_utils")
    local s, out, seen = sizes(), {}, {}
    local was = M.recording
    M.recording = true -- our own fitDims calls aren't new boxes
    local function add(w, h)
        local k = w .. "x" .. h
        if w >= 1 and h >= 1 and not seen[k] then seen[k] = true; out[#out + 1] = { w, h } end
    end
    if sw and sh and sw > 0 and sh > 0 then
        for _i, b in ipairs(s.boxes) do
            local w, h = CoverUtils.fitDims(b[1], b[2], sw, sh)
            if w and h then add(math.max(1, w), math.max(1, h)) end
        end
    end
    for _i, e in ipairs(s.exact) do add(e[1], e[2]) end
    M.recording = was
    return out
end

function M.knownSizes() return sizes() end

--- Watch CoverUtils.fitDims to learn the boxes ZenOS fits covers into.
function M.install()
    if M.installed then return end
    M.installed = true
    local ok, CoverUtils = pcall(require, "common/cover_utils")
    if not ok or type(CoverUtils.fitDims) ~= "function" then return end
    local orig = CoverUtils.fitDims
    CoverUtils.fitDims = function(max_w, max_h, source_w, source_h, ...)
        if not M.recording then
            M.recording = true
            pcall(M.recordBox, max_w, max_h)
            M.recording = false
        end
        return orig(max_w, max_h, source_w, source_h, ...)
    end
end

return M
