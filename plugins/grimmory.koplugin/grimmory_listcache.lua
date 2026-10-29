--[[--
Saved Grimmory lists, so the Grimmory tab opens at once.

Every list the browser fetches from Grimmory (Continue reading, Recently
added, All books, a library, a shelf, an author's or a series' books, the
library and shelf lists) is kept on disk as it came back:
  <data>/cache/grimmory-lists/<md5 of key>.json
Opening a list shows the saved copy straight away, even with Wi-Fi off or
still connecting, then fetches a fresh one in the background and swaps it
in. Only the first page is kept; "Load more" always asks Grimmory.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local md5 = require("ffi/sha2").md5

local Cache = { MAX_FILES = 60 }

local dir_ready
function Cache.dir()
    local d = DataStorage:getDataDir() .. "/cache/grimmory-lists"
    if not dir_ready then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(d)
        dir_ready = true
    end
    return d
end

local function file(key) return Cache.dir() .. "/" .. md5(tostring(key)) .. ".json" end

--- The saved data for key and when it was saved, or nil.
function Cache.get(key)
    if not key then return nil end
    local f = io.open(file(key), "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    local ok, t = pcall(JSON.decode, s or "")
    if not ok or type(t) ~= "table" or t.key ~= key or t.data == nil then return nil end
    return t.data, tonumber(t.saved)
end

local function prune(d)
    local list = {}
    for name in lfs.dir(d) do
        if name:match("%.json$") then
            list[#list + 1] = { name = name, t = lfs.attributes(d .. "/" .. name, "modification") or 0 }
        end
    end
    if #list <= Cache.MAX_FILES then return end
    table.sort(list, function(a, b) return a.t < b.t end)
    for i = 1, #list - Cache.MAX_FILES do os.remove(d .. "/" .. list[i].name) end
end

function Cache.put(key, data)
    if not key or data == nil then return false end
    local ok, s = pcall(JSON.encode, { key = key, saved = os.time(), data = data })
    if not ok then return false end
    local name = file(key)
    local f = io.open(name .. ".tmp", "wb")
    if not f then return false end
    f:write(s)
    f:close()
    local done = os.rename(name .. ".tmp", name) and true or false
    pcall(prune, Cache.dir())
    return done
end

--- A stable key for a table of parameters.
function Cache.key(prefix, params)
    local keys = {}
    for k in pairs(params or {}) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = { prefix }
    for _i, k in ipairs(keys) do
        local v = params[k]
        if type(v) == "table" then v = table.concat(v, ",") end
        parts[#parts + 1] = k .. "=" .. tostring(v)
    end
    return table.concat(parts, "|")
end

function Cache.clear()
    local d = Cache.dir()
    for name in lfs.dir(d) do
        if name:match("%.json$") or name:match("%.tmp$") then os.remove(d .. "/" .. name) end
    end
end

return Cache
