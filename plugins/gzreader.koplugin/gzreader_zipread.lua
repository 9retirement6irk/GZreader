--[[--
One small file out of a zip held in memory.

For BookOrbit's "preconfigured plugin" download (gzreader_bookorbit.lua's
loginWithApiKey): the only way its API hands a device the KOReader sync key.
Reads the zip's directory at its end, then the one entry (stored or deflated;
zlib through gzreader_gzip.lua). Nothing is written to disk and nothing in
the zip is run.
]]

local Zip = {}

Zip.MAX = 256 * 1024 -- (the most one entry may unpack to)

local function u16(s, i) local a, b = s:byte(i, i + 1); return a and b and (a + b * 256) or nil end
local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a and d and (a + b * 256 + c * 65536 + d * 16777216) or nil
end

--- The contents of the entry whose name is `name` or ends in "/" .. name; nil, err otherwise.
function Zip.read(data, name)
    if type(data) ~= "string" or #data < 22 then return nil, "not a zip" end
    -- the end record: in the last 64 KB (it may be followed by a comment)
    local eocd
    local from = math.max(1, #data - 65557)
    local at = from
    while true do
        local i = data:find("PK\5\6", at, true)
        if not i then break end
        eocd, at = i, i + 1
    end
    if not eocd then return nil, "not a zip" end
    local count, dir_at = u16(data, eocd + 10), u32(data, eocd + 16)
    if not count or not dir_at then return nil, "not a zip" end
    local p = dir_at + 1
    for _i = 1, count do
        if data:sub(p, p + 3) ~= "PK\1\2" then return nil, "bad zip directory" end
        local method, csize, usize = u16(data, p + 10), u32(data, p + 20), u32(data, p + 24)
        local nlen, xlen, clen, local_at = u16(data, p + 28), u16(data, p + 30), u16(data, p + 32), u32(data, p + 42)
        if not (method and csize and usize and nlen and xlen and clen and local_at) then return nil, "bad zip directory" end
        local entry = data:sub(p + 46, p + 45 + nlen)
        if entry == name or entry:sub(-#name - 1) == "/" .. name then
            if usize > Zip.MAX or csize > Zip.MAX then return nil, "too big" end
            local l = local_at + 1
            if data:sub(l, l + 3) ~= "PK\3\4" then return nil, "bad zip entry" end
            local ln, lx = u16(data, l + 26), u16(data, l + 28)
            if not ln or not lx then return nil, "bad zip entry" end
            local body = data:sub(l + 30 + ln + lx, l + 29 + ln + lx + csize)
            if #body ~= csize then return nil, "bad zip entry" end
            if method == 0 then return body end
            if method ~= 8 then return nil, "unsupported compression" end
            local out, err = require("gzreader_gzip").inflate(body, true)
            if not out then return nil, err end
            if #out > Zip.MAX then return nil, "too big" end
            return out
        end
        p = p + 46 + nlen + xlen + clen
    end
    return nil, "not in the zip"
end

return Zip
