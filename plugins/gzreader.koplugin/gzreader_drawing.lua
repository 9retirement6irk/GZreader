--[[--
Memos drawings: a PNG with its editable scene inside, as memos' drawing sheet
(@usememos/canvas, scene format version 1) writes and reads them.

A drawing is an ordinary PNG attachment named
`drawing-YYYYMMDD-HHMMSS.canvas.png`. Its pixels are what every viewer shows
(memos' thumbnails too); the scene, JSON in a `zTXt` chunk with the keyword
`memos-canvas`, is what memos' "Edit drawing" reopens. memos looks for that
chunk only before the first `IDAT`, so it goes right after `IHDR`, as memos
puts it. A `tEXt` chunk (uncompressed) is read as well: it's the fallback
here when zlib can't be loaded.

What this module does, with no UI and no network:
  * builds a scene and its pen strokes (`freedraw` elements), in scene units;
    `Drawing.fromScreen` turns screen pixels into them (by default 2 screen
    pixels per unit: memos exports at 2x, so a full Scribe page, 1860x2480,
    is a 930x1240 drawing that comes back out at the screen's resolution);
  * writes the scene as memos stores it: ASCII-only JSON (`\uXXXX` above
    U+007E), coordinates rounded to 2 decimals;
  * puts it into PNG bytes written by anything else (KOReader's
    `bb:writePNG(file)`), replacing a scene chunk already there, and reads it
    back.

The scene format follows @usememos/canvas `src/scene/types.ts` and
`src/png/{chunks,serialize}.ts` (26.11.2). Unknown fields of a scene read
back are kept, as memos keeps them.
]]

local ffi = require("ffi")
local bit = require("bit")

local Drawing = {
    SCENE_TYPE = "memos-canvas",
    SCENE_VERSION = 1,
    KEYWORD = "memos-canvas",
    SUFFIX = ".canvas.png",
    --- Screen pixels per scene unit (memos exports PNGs at 2x).
    SCREEN_PER_UNIT = 2,
    --- memos' pen widths: 1 thin, 2 medium, 4 thick.
    WIDTHS = { 1, 2, 4 },
    --- Most text memos will inflate from a scene chunk (its MAX_SCENE_TEXT).
    MAX_SCENE_TEXT = 64000000,
    --- memos' drawing sheet's paper and ink (web `DrawingSheet/useCanvasTheme.ts`).
    PAPER = "#fbfaf7",
    INK = "#1a1a1a",
    --- How wide memos draws a stroke whose width follows its speed (as every
    --- stroke here does), as a share of its full width: measured on a drawing
    --- exported by memos (thin 5–6 px, thick 12–13 px at 2x).
    SPEED_WIDTH = 0.42,
}

--- A stroke's full width in scene units for memos' width 1, 2 or 4 (@usememos/canvas `strokeDiameter`).
function Drawing.strokeDiameter(width) return 2 + (tonumber(width) or 2) * 3 end

local SIGNATURE = "\137PNG\r\n\26\n"
local LIST_MT = { __jsontype = "array", __is_luajson_array = true }

--- `t` (a new table when nil) marked as a JSON list, so an empty one is `[]`.
local function list(t) return setmetatable(t or {}, LIST_MT) end
Drawing.list = list

local function isList(t)
    local mt = getmetatable(t)
    if mt and mt.__jsontype == "array" then return true end
    if mt and mt.__jsontype == "object" then return false end
    local n = #t
    if n == 0 then return false end
    local count = 0
    for _k in pairs(t) do count = count + 1 end
    return count == n
end

--- Rounded to two decimals, the precision memos stores coordinates with.
local function round2(n)
    local r = math.floor(n * 100 + 0.5) / 100
    if r == 0 then return 0 end
    return r
end
Drawing.round2 = round2

-- ---------------------------------------------------------------- ids, seeds

local ID_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local seeded = false

local function randomBytes(n)
    local f = io.open("/dev/urandom", "rb")
    if f then
        local s = f:read(n)
        f:close()
        if s and #s == n then return s end
    end
    if not seeded then
        math.randomseed(os.time() + math.floor((os.clock() % 1) * 1e6))
        seeded = true
    end
    local t = {}
    for i = 1, n do t[i] = string.char(math.random(0, 255)) end
    return table.concat(t)
end

--- A random id of `length` (10) letters and digits, as memos makes them.
function Drawing.randomId(length)
    length = length or 10
    local bytes = randomBytes(length)
    local out = {}
    for i = 1, length do
        local b = bytes:byte(i) % #ID_ALPHABET + 1
        out[i] = ID_ALPHABET:sub(b, b)
    end
    return table.concat(out)
end

--- A random 31-bit seed (memos' hand-drawn style uses it; ours is never drawn by hand).
function Drawing.randomSeed()
    local a, b, c, d = randomBytes(4):byte(1, 4)
    return ((a % 128) * 256 + b) * 65536 + c * 256 + d
end

-- -------------------------------------------------------------------- scene

--- A new, empty scene on `paper` (`#rrggbb`, memos' drawing paper by default).
function Drawing.newScene(paper)
    return {
        type = Drawing.SCENE_TYPE,
        version = Drawing.SCENE_VERSION,
        elements = list(),
        files = {},
        appState = { viewBackgroundColor = paper or Drawing.PAPER, zoom = 1, scrollX = 0, scrollY = 0, handDrawn = false },
    }
end

--- Screen points `{ { x, y [, pressure] }, … }` in scene units (`per_unit`
--- screen pixels each, `Drawing.SCREEN_PER_UNIT` by default).
function Drawing.fromScreen(points, per_unit)
    per_unit = per_unit or Drawing.SCREEN_PER_UNIT
    local out = {}
    for i, p in ipairs(points) do
        out[i] = { p[1] / per_unit, p[2] / per_unit, p[3] }
    end
    return out
end

local function hexColor(c)
    if type(c) == "string" and c:match("^#%x%x%x%x%x%x$") then return c:lower() end
    return Drawing.INK
end

local function nearestWidth(w)
    w = tonumber(w) or 2
    local best = 2
    for _i, v in ipairs(Drawing.WIDTHS) do
        if math.abs(v - w) < math.abs(best - w) then best = v end
    end
    return best
end

--- A pen stroke from scene points `{ { x, y [, pressure 0..1] }, … }`.
--- `style`: `color` (`#rrggbb`), `width` (1, 2 or 4), `opacity` (0–100).
--- Without pressure on every point (the Scribe's pen reports none through
--- KOReader), memos draws the width from the stroke's speed instead
--- (`simulatePressure`), as it does for a mouse. Returns nil for no points.
function Drawing.stroke(points, style)
    style = style or {}
    if type(points) ~= "table" or #points == 0 then return nil end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    local pressured = true
    for _i, p in ipairs(points) do
        local x, y = tonumber(p[1]), tonumber(p[2])
        if not x or not y or x ~= x or y ~= y or math.abs(x) == math.huge or math.abs(y) == math.huge then
            return nil
        end
        if x < minX then minX = x end
        if y < minY then minY = y end
        if x > maxX then maxX = x end
        if y > maxY then maxY = y end
        if tonumber(p[3]) == nil then pressured = false end
    end
    local pts = list()
    local lastX, lastY
    for _i, p in ipairs(points) do
        local dx, dy = round2(p[1] - minX), round2(p[2] - minY)
        -- (repeated samples add nothing; memos' pen leaves them out too)
        if dx ~= lastX or dy ~= lastY then
            local pr = pressured and math.max(0, math.min(1, tonumber(p[3]))) or 0.5
            pts[#pts + 1] = list({ dx, dy, round2(pr) })
            lastX, lastY = dx, dy
        end
    end
    return {
        id = Drawing.randomId(),
        type = "freedraw",
        x = round2(minX),
        y = round2(minY),
        width = round2(maxX - minX),
        height = round2(maxY - minY),
        angle = 0,
        strokeColor = hexColor(style.color),
        backgroundColor = "transparent",
        strokeWidth = nearestWidth(style.width),
        opacity = math.max(0, math.min(100, math.floor(tonumber(style.opacity) or 100))),
        isDeleted = false,
        groupIds = list(),
        boundElements = list(),
        seed = Drawing.randomSeed(),
        locked = false,
        points = pts,
        simulatePressure = not pressured,
    }
end

--- Adds a stroke (see `Drawing.stroke`) to `scene`; returns the element, or nil.
function Drawing.addStroke(scene, points, style)
    local el = Drawing.stroke(points, style)
    if el then
        if not getmetatable(scene.elements) then list(scene.elements) end
        scene.elements[#scene.elements + 1] = el
    end
    return el
end

--- The elements memos draws (not deleted).
function Drawing.liveElements(scene)
    local out = {}
    for _i, el in ipairs(scene.elements or {}) do
        if not el.isDeleted then out[#out + 1] = el end
    end
    return out
end

--- The box the scene's live elements cover (scene units), or nil when empty.
function Drawing.bounds(scene)
    local minX, minY, maxX, maxY
    for _i, el in ipairs(Drawing.liveElements(scene)) do
        local x, y = tonumber(el.x) or 0, tonumber(el.y) or 0
        local w, h = tonumber(el.width) or 0, tonumber(el.height) or 0
        minX = math.min(minX or x, x)
        minY = math.min(minY or y, y)
        maxX = math.max(maxX or x + w, x + w)
        maxY = math.max(maxY or y + h, y + h)
    end
    if not minX then return nil end
    return { x = minX, y = minY, w = maxX - minX, h = maxY - minY }
end

--- `drawing-YYYYMMDD-HHMMSS.canvas.png` for time `t` (now), local time as memos names them.
function Drawing.fileName(t)
    return os.date("drawing-%Y%m%d-%H%M%S", t or os.time()) .. Drawing.SUFFIX
end

--- True when `name` is named like a memos drawing.
function Drawing.isDrawingName(name)
    return type(name) == "string" and name:lower():sub(-#Drawing.SUFFIX) == Drawing.SUFFIX
end

-- --------------------------------------------------------------- JSON text

local function utf8Codepoints(s)
    -- Yields code points; a byte that isn't valid UTF-8 counts as U+FFFD.
    local i, n = 1, #s
    return function()
        if i > n then return nil end
        local c = s:byte(i)
        local cp, len
        if c < 0x80 then cp, len = c, 1
        elseif c >= 0xC2 and c < 0xE0 then cp, len = c - 0xC0, 2
        elseif c >= 0xE0 and c < 0xF0 then cp, len = c - 0xE0, 3
        elseif c >= 0xF0 and c < 0xF5 then cp, len = c - 0xF0, 4
        else i = i + 1; return 0xFFFD end
        if i + len - 1 > n then i = n + 1; return 0xFFFD end
        for k = 1, len - 1 do
            local cc = s:byte(i + k)
            if cc < 0x80 or cc > 0xBF then i = i + k; return 0xFFFD end
            cp = cp * 64 + (cc - 0x80)
        end
        local min = ({ 0, 0x80, 0x800, 0x10000 })[len]
        i = i + len
        if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return 0xFFFD end
        return cp
    end
end

local SHORT_ESCAPES = { [8] = "\\b", [9] = "\\t", [10] = "\\n", [12] = "\\f", [13] = "\\r", [34] = '\\"', [92] = "\\\\" }

local function quote(s)
    local out = { '"' }
    for cp in utf8Codepoints(s) do
        if SHORT_ESCAPES[cp] then
            out[#out + 1] = SHORT_ESCAPES[cp]
        elseif cp < 0x20 or (cp >= 0x7F and cp <= 0xFFFF) then
            out[#out + 1] = string.format("\\u%04x", cp)
        elseif cp > 0xFFFF then
            local v = cp - 0x10000
            out[#out + 1] = string.format("\\u%04x\\u%04x", 0xD800 + bit.rshift(v, 10), 0xDC00 + bit.band(v, 0x3FF))
        else
            out[#out + 1] = string.char(cp)
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function number(v, exact)
    if v ~= v or v == math.huge or v == -math.huge then error("not a finite number", 0) end
    if v == math.floor(v) and math.abs(v) < 2^53 then return string.format("%d", v) end
    if exact then return string.format("%.17g", v) end
    v = round2(v)
    if v == math.floor(v) then return string.format("%d", v) end
    local s = string.format("%.2f", v):gsub("0+$", "")
    return s
end

local encodeValue

local function encodeTable(t, key, depth)
    if depth > 100 then error("too deep", 0) end
    local exact = key == "fixedPoint"
    if isList(t) then
        local parts = {}
        for i = 1, #t do parts[i] = encodeValue(t[i], exact and "fixedPoint" or nil, depth + 1) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(t) do
        if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for _i, k in ipairs(keys) do
        parts[#parts + 1] = quote(k) .. ":" .. encodeValue(t[k], k, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

encodeValue = function(v, key, depth)
    local tv = type(v)
    if tv == "table" then return encodeTable(v, key, depth or 0) end
    if tv == "string" then return quote(v) end
    if tv == "number" then return number(v, key == "angle" or key == "fixedPoint") end
    if tv == "boolean" then return v and "true" or "false" end
    -- (nil, and a JSON library's placeholder for a null read back: LuaJSON's
    -- is a function, rapidjson's a light userdata)
    if v == nil or tv == "function" or tv == "userdata" then return "null" end
    error("can't write a " .. tv, 0)
end

--- The scene as it's written: live elements only, files no image uses
--- dropped. A shallow copy; the scene itself isn't changed.
function Drawing.exportable(scene)
    local out = {}
    for k, v in pairs(scene) do out[k] = v end
    local elements, used = list(), {}
    for _i, el in ipairs(Drawing.liveElements(scene)) do
        elements[#elements + 1] = el
        if el.type == "image" and type(el.fileId) == "string" then used[el.fileId] = true end
    end
    local files = {}
    for id, f in pairs(type(scene.files) == "table" and scene.files or {}) do
        if used[id] then files[id] = f end
    end
    out.elements, out.files = elements, files
    out.type = out.type or Drawing.SCENE_TYPE
    out.version = out.version or Drawing.SCENE_VERSION
    return out
end

--- The scene's stored text: JSON, ASCII only. Raises on a value JSON can't hold.
function Drawing.encode(scene)
    return encodeValue(Drawing.exportable(scene), nil, 0)
end

-- ------------------------------------------------------------- scene check

local function finite(n) return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge end

local function validElement(el)
    if type(el) ~= "table" then return false end
    if type(el.id) ~= "string" or el.id == "" or type(el.type) ~= "string" then return false end
    if not finite(el.x) or not finite(el.y) then return false end
    if (el.type == "freedraw" or el.type == "line" or el.type == "arrow") and type(el.points) ~= "table" then return false end
    if el.type == "text" and type(el.text) ~= "string" then return false end
    if el.type == "image" and type(el.fileId) ~= "string" then return false end
    return true
end

-- The fields format version 1 keeps as lists, marked again after decoding
-- so a scene read back writes `[]`, not `{}`, for an empty one.
local function markLists(el)
    for _i, k in ipairs({ "groupIds", "boundElements", "scale" }) do
        if type(el[k]) == "table" then list(el[k]) end
    end
    if type(el.points) == "table" then
        list(el.points)
        for _i, p in ipairs(el.points) do
            if type(p) == "table" then list(p) end
        end
    end
    for _i, k in ipairs({ "startBinding", "endBinding" }) do
        local b = el[k]
        if type(b) == "table" and type(b.fixedPoint) == "table" then list(b.fixedPoint) end
    end
end

--- The scene in stored text `text`, or nil and memos' reason
--- (`not-json`, `invalid-scene`, `wrong-type`, `version-too-high`): the
--- checks memos makes before it opens one.
function Drawing.decode(text)
    local Json = require("gzreader_json")
    local ok, data = pcall(Json.decode, text)
    if not ok then return nil, "not-json" end
    if type(data) ~= "table" then return nil, "invalid-scene" end
    if data.type ~= Drawing.SCENE_TYPE then return nil, "wrong-type" end
    local v = data.version
    if type(v) ~= "number" or v ~= math.floor(v) or v < 1 then return nil, "invalid-scene" end
    if v > Drawing.SCENE_VERSION then return nil, "version-too-high" end
    if type(data.elements) ~= "table" then return nil, "invalid-scene" end
    for _i, el in ipairs(data.elements) do
        if not validElement(el) then return nil, "invalid-scene" end
    end
    if data.files ~= nil and type(data.files) ~= "table" then return nil, "invalid-scene" end
    if data.appState ~= nil and type(data.appState) ~= "table" then return nil, "invalid-scene" end
    data.files = data.files or {}
    list(data.elements)
    for _i, el in ipairs(data.elements) do markLists(el) end
    return data
end

-- -------------------------------------------------------------- PNG chunks

local crcTable
local function crc32(s)
    if not crcTable then
        crcTable = {}
        for i = 0, 255 do
            local c = i
            for _k = 1, 8 do
                if bit.band(c, 1) == 1 then c = bit.bxor(0xEDB88320, bit.rshift(c, 1)) else c = bit.rshift(c, 1) end
            end
            crcTable[i] = c
        end
    end
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bit.bxor(crcTable[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
    end
    c = bit.bnot(c)
    if c < 0 then c = c + 4294967296 end
    return c
end
Drawing.crc32 = crc32

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
end

local function be32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function chunk(ctype, data)
    return be32(#data) .. ctype .. data .. be32(crc32(ctype .. data))
end

--- The chunks of PNG bytes `png` as { type, start, data, length, stop }
--- (1-based offsets; `stop` is just past the CRC), or nil and a reason.
function Drawing.chunks(png)
    if type(png) ~= "string" or png:sub(1, 8) ~= SIGNATURE then return nil, "not-png" end
    local out, at = {}, 9
    while at <= #png do
        if at + 11 > #png then return nil, "truncated" end
        local len = u32(png, at)
        local stop = at + 12 + len
        if stop - 1 > #png then return nil, "truncated" end
        out[#out + 1] = { type = png:sub(at + 4, at + 7), start = at, data = at + 8, length = len, stop = stop }
        at = stop
    end
    return out
end

local function isSceneChunk(png, c)
    if c.type ~= "tEXt" and c.type ~= "zTXt" then return false end
    local k = Drawing.KEYWORD
    return c.length >= #k + 1 and png:sub(c.data, c.data + #k) == k .. "\0"
end

-- zlib's whole-buffer compression (zTXt's format), when it can be loaded.
local zlibLib
local function zlib()
    if zlibLib ~= nil then return zlibLib or nil end
    zlibLib = false
    pcall(require, "ffi/zlib_h")
    pcall(ffi.cdef, "unsigned long compressBound(unsigned long sourceLen);")
    pcall(ffi.cdef, "int compress2(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen, int level);")
    local tries = {
        function() return ffi.loadlib("z", 1) end,
        function() return ffi.load("libs/libz.so.1") end,
        function() return ffi.load("z") end,
        function() return ffi.load("libz.so.1") end,
    }
    for _i, t in ipairs(tries) do
        local ok, l = pcall(t)
        if ok and l and pcall(function() return l.compress2 end) then zlibLib = l; return l end
    end
    return nil
end

--- zlib-compressed `s` (RFC 1950), or nil when zlib can't be loaded.
function Drawing.deflate(s)
    if Drawing.no_zlib then return nil end
    local z = zlib()
    if not z then return nil end
    local n = tonumber(z.compressBound(#s))
    local buf = ffi.new("uint8_t[?]", n)
    local len = ffi.new("unsigned long[1]", n)
    if z.compress2(buf, len, ffi.cast("const uint8_t *", s), #s, 9) ~= 0 then return nil end
    return ffi.string(buf, tonumber(len[0]))
end

--- The scene chunk for `scene`: zTXt when zlib loads, tEXt otherwise.
function Drawing.sceneChunk(scene)
    local text = Drawing.encode(scene)
    local z = Drawing.deflate(text)
    if z then return chunk("zTXt", Drawing.KEYWORD .. "\0\0" .. z), "zTXt" end
    return chunk("tEXt", Drawing.KEYWORD .. "\0" .. text), "tEXt"
end

--- PNG bytes `png` with `scene` inside, right after IHDR; a scene chunk
--- already there is dropped. Pixels are untouched. nil and a reason when
--- `png` isn't a PNG with an IHDR.
function Drawing.withScene(png, scene)
    local list_, why = Drawing.chunks(png)
    if not list_ then return nil, why end
    if not list_[1] or list_[1].type ~= "IHDR" then return nil, "no-ihdr" end
    local scene_chunk = Drawing.sceneChunk(scene)
    local parts = { SIGNATURE }
    for i, c in ipairs(list_) do
        if not isSceneChunk(png, c) then
            parts[#parts + 1] = png:sub(c.start, c.stop - 1)
            if i == 1 then parts[#parts + 1] = scene_chunk end
        end
    end
    return table.concat(parts)
end

--- The scene inside PNG bytes `png`, or nil and memos' reason (`not-png`,
--- `truncated`, `no-chunk`, `bad-crc`, `bad-compression` and `decode`'s).
function Drawing.readScene(png)
    local list_, why = Drawing.chunks(png)
    if not list_ then return nil, why end
    for _i, c in ipairs(list_) do
        if c.type == "IDAT" or c.type == "IEND" then break end
        if isSceneChunk(png, c) then
            local body = png:sub(c.data, c.data + c.length - 1)
            if crc32(c.type .. body) ~= u32(png, c.data + c.length) then return nil, "bad-crc" end
            local text = body:sub(#Drawing.KEYWORD + 2)
            if c.type == "zTXt" then
                if text:byte(1) ~= 0 then return nil, "bad-compression" end
                local ok, out = pcall(function() return require("gzreader_gzip").inflate(text:sub(2)) end)
                if not ok or type(out) ~= "string" or #out > Drawing.MAX_SCENE_TEXT then return nil, "bad-compression" end
                text = out
            end
            return Drawing.decode(text)
        end
    end
    return nil, "no-chunk"
end

-- ------------------------------------------------------------------ files

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- Puts `scene` into the PNG at `png_path` and writes the result to
--- `out_path` (the same path is fine: written to a temporary file, then
--- renamed). true, or nil and a reason.
function Drawing.writeFile(png_path, scene, out_path)
    local png = readFile(png_path)
    if not png then return nil, "can't read " .. tostring(png_path) end
    local ok, bytes, why = pcall(Drawing.withScene, png, scene)
    if not ok then return nil, tostring(bytes) end
    if not bytes then return nil, why end
    out_path = out_path or png_path
    local tmp = out_path .. ".part"
    local f = io.open(tmp, "wb")
    if not f then return nil, "can't write " .. tmp end
    local wrote = f:write(bytes)
    f:close()
    if not wrote then os.remove(tmp); return nil, "can't write " .. tmp end
    local renamed, err = os.rename(tmp, out_path)
    if not renamed then os.remove(tmp); return nil, err end
    return true
end

--- The scene in the PNG file at `path`, or nil and a reason.
function Drawing.readFile(path)
    local png = readFile(path)
    if not png then return nil, "can't read " .. tostring(path) end
    return Drawing.readScene(png)
end

return Drawing
