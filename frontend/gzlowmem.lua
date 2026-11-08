--[[--
GZreader: defaults for Kindles with little memory (128 MB or less: the
Kindle 2 and DX; 2–3 MB of it free while a big book is open on a DX).

There's no swap on a Kindle: whatever memory GZreader holds is memory the
system can't use to keep the book file and its layout cache (cr3cache) in
RAM, so on those Kindles they're read again from storage while a book opens
(95–103 s for a 31.7 MB EPUB on a DX).

- crengine's in-memory caches: KOReader lets each grow to 40 times its base
  size (cre_storage_size_factor, credocument.lua), and says to lower it on
  older devices that run short of memory. On these Kindles it's 5; on a
  Kindle 3 (256 MB) and newer, KOReader's 40. Your own
  setting (settings.reader.lua: "cre_storage_size_factor") still wins.

Also, for the old Kindles with a slow ARM11 processor (Kindle 2, DX, DX
Graphite, Kindle 3, Kindle 4), whatever their memory:

- crengine's layout cache (cr3cache) is kept uncompressed. KOReader added the
  switch because decompressing it slows opening, page turns and closing big
  books (koreader#3670); the files are bigger (the cache is capped at 256 MB
  anyway). Your own setting ("cre_compress_cached_data") still wins.
]]

local GzLowMem = {
    LIMIT_KB = 160 * 1024, -- a Kindle 3 has 256 MB, a DX 128 MB
    CRE_STORAGE_FACTOR = 5,
    CRE_STORAGE_FACTOR_DEFAULT = 40, -- KOReader's
    -- KOReader's model names (frontend/device/kindle/device.lua; the DX runs as Kindle2)
    SLOW_MODELS = { Kindle2 = true, KindleDXG = true, Kindle3 = true, Kindle4 = true },
}

--- The device's memory (MemTotal, in KB) from `path` (/proc/meminfo), or nil.
function GzLowMem.totalKB(path)
    local f = io.open(path or "/proc/meminfo", "r")
    if not f then return nil end
    local s = f:read("*a") or ""
    f:close()
    return tonumber(s:match("MemTotal:%s*(%d+)"))
end

--- A Kindle with little memory (total in KB; read from /proc/meminfo when nil).
function GzLowMem.isLow(total_kb)
    total_kb = total_kb or GzLowMem.totalKB()
    return total_kb ~= nil and total_kb <= GzLowMem.LIMIT_KB
end

--- crengine's cache size factor, unless one was set.
function GzLowMem.creStorageFactor(total_kb)
    --- An old Kindle with a slow processor (model: KOReader's Device.model; read
--- from the device when nil).
function GzLowMem.isSlow(model)
    if model == nil then
        local ok, Device = pcall(require, "device")
        model = ok and Device and Device.model
    end
    return GzLowMem.SLOW_MODELS[tostring(model)] == true
end

--- Whether crengine compresses its layout cache, unless it was set.
function GzLowMem.creCompressCache(model)
    return not GzLowMem.isSlow(model)
end

return GzLowMem.isLow(total_kb) and GzLowMem.CRE_STORAGE_FACTOR or GzLowMem.CRE_STORAGE_FACTOR_DEFAULT
end

--- An old Kindle with a slow processor (model: KOReader's Device.model; read
--- from the device when nil).
function GzLowMem.isSlow(model)
    if model == nil then
        local ok, Device = pcall(require, "device")
        model = ok and Device and Device.model
    end
    return GzLowMem.SLOW_MODELS[tostring(model)] == true
end

--- Whether crengine compresses its layout cache, unless it was set.
function GzLowMem.creCompressCache(model)
    return not GzLowMem.isSlow(model)
end

return GzLowMem
