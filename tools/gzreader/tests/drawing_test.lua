-- Memos drawings (gzreader_drawing.lua): scenes, pen strokes, the scene's
-- stored text, and the PNG chunk memos reads it from. The PNGs it makes are
-- left in <out dir> for drawing_format_test.py, which checks them the way
-- memos' drawing sheet (@usememos/canvas) reads a drawing.
--   luajit drawing_test.lua <gzreader.koplugin> <tests lib> <koreader base> <out dir>
-- media/memos-v1.canvas.png is memos' own test drawing
-- (usememos/memos server/fileserver/testdata/v1.canvas.png, MIT licence).
local PLUGIN, LIB, KOROOT, OUT = arg[1], arg[2], arg[3], arg[4]
package.path = PLUGIN .. "/?.lua;" .. LIB .. "/?.lua;" .. KOROOT .. "/?.lua;" .. package.path

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end

-- LuaJSON stand-in (as the other suites): dkjson, null as nil
local dkjson = require("dkjson")
package.preload["json"] = function()
    return {
        decode = function(s) local v, _, err = dkjson.decode(s); if err then error(err) end; return v end,
        encode = function(v) return dkjson.encode(v) end,
    }
end

local ffi = require("ffi")
local Drawing = require("gzreader_drawing")
local Json = require("gzreader_json")
local HERE = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "."

local function readFile(p) local f = assert(io.open(p, "rb")); local s = f:read("*a"); f:close(); return s end
local function writeFile(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end

local function be32(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end
local function chunk(t, d) return be32(#d) .. t .. d .. be32(Drawing.crc32(t .. d)) end

--- A small 8-bit grey PNG (white, with a black diagonal), as bb:writePNG would leave one.
local function greyPng(w, h)
    local rows = {}
    for y = 0, h - 1 do
        local row = { "\0" }
        for x = 0, w - 1 do row[#row + 1] = (x == y) and "\0" or "\255" end
        rows[#rows + 1] = table.concat(row)
    end
    local idat = assert(Drawing.deflate(table.concat(rows)), "zlib on this computer")
    return "\137PNG\r\n\26\n"
        .. chunk("IHDR", be32(w) .. be32(h) .. "\8\0\0\0\0")
        .. chunk("tEXt", "Software\0KOReader")
        .. chunk("IDAT", idat)
        .. chunk("IEND", "")
end

print("== a stroke")
;(function()
    check(Drawing.SCENE_TYPE == "memos-canvas" and Drawing.SCENE_VERSION == 1, "scene type memos-canvas, version 1")
    local scene = Drawing.newScene()
    check(scene.type == "memos-canvas" and scene.version == 1 and #scene.elements == 0, "a new scene: type, version, no elements")
    check(scene.appState.viewBackgroundColor == "#ffffff" and scene.appState.zoom == 1 and scene.appState.handDrawn == false,
        "a new scene: white paper, zoom 1, not hand-drawn")

    local pts = Drawing.fromScreen({ { 400, 600 }, { 410, 590 }, { 410, 590 }, { 430.333, 620.126 } })
    check(pts[1][1] == 200 and pts[1][2] == 300 and pts[4][1] == 215.1665, "screen pixels: 2 per scene unit")
    local el = Drawing.addStroke(scene, pts, { width = 5, color = "#FF0000" })
    check(el and #scene.elements == 1 and el.type == "freedraw", "a stroke is a freedraw element in the scene")
    check(el.x == 200 and el.y == 295 and el.width == 15.17 and el.height == 15.06,
        "its box: the points' top left, width and height (2 decimals)")
    local minx, miny = math.huge, math.huge
    for _i, p in ipairs(el.points) do minx = math.min(minx, p[1]); miny = math.min(miny, p[2]) end
    check(minx == 0 and miny == 0, "its points start from the box's top left (no negative offsets)")
    check(#el.points == 3, "a repeated sample is left out")
    check(el.points[1][1] == 0 and el.points[1][2] == 5 and el.points[3][1] == 15.17 and el.points[3][2] == 15.06,
        "points are offsets from x, y, rounded to 2 decimals")
    check(el.simulatePressure == true and el.points[1][3] == 0.5, "no pressure from the pen: simulated (0.5 stored)")
    check(el.strokeWidth == 4 and el.strokeColor == "#ff0000", "width snapped to memos' 1/2/4; colour lower case")
    check(type(el.id) == "string" and el.id:match("^[0-9A-Za-z]+$") and #el.id == 10, "a 10-character id of letters and digits")
    check(el.seed >= 0 and el.seed < 2^31 and el.seed == math.floor(el.seed), "a 31-bit seed")
    check(el.angle == 0 and el.opacity == 100 and el.isDeleted == false and el.locked == false
        and el.backgroundColor == "transparent", "the other fields version 1 asks of every element")

    local p2 = Drawing.stroke({ { 0, 0, 0.2 }, { 5, 5, 1.7 }, { 9, 1, -1 } }, { color = "red", width = 1, opacity = 40 })
    check(p2.simulatePressure == false and p2.points[1][3] == 0.2 and p2.points[2][3] == 1 and p2.points[3][3] == 0,
        "pressure on every point: kept, between 0 and 1")
    check(p2.strokeColor == "#1e1e1e" and p2.strokeWidth == 1 and p2.opacity == 40, "a colour that isn't #rrggbb: memos' ink")
    check(Drawing.stroke({}) == nil and Drawing.stroke({ { 0 / 0, 1 } }) == nil and Drawing.stroke({ { 1, math.huge } }) == nil,
        "no points, or a point that isn't a finite number: no stroke")
    check(Drawing.stroke({ { 7, 8 } }).width == 0, "a dot: a stroke of one point")
    check(Drawing.randomId() ~= Drawing.randomId(), "ids differ")

    local b = Drawing.bounds(scene)
    check(b and b.x == 200 and b.y == 295 and math.abs(b.w - 15.17) < 1e-9 and math.abs(b.h - 15.06) < 1e-9, "the scene's bounds")
    check(Drawing.bounds(Drawing.newScene()) == nil, "an empty scene has no bounds")
end)()

print("== the stored text")
;(function()
    local scene = Drawing.newScene()
    Drawing.addStroke(scene, { { 1, 2 }, { 3.14159, 4 } })
    scene.elements[2] = {
        id = "t1", type = "text", x = 10, y = 20, width = 50, height = 20, angle = 0.123456789,
        text = "Caf\195\169 \226\128\148 \240\159\152\128 \"quoted\"\n\\", fontSize = 20, fontFamily = "sans", textAlign = "left",
        autoWidth = true, containerId = false, groupIds = Drawing.list(), boundElements = Drawing.list(), seed = 1,
    }
    scene.elements[3] = { id = "gone", type = "rectangle", x = 0, y = 0, isDeleted = true }
    scene.elements[4] = { id = "img", type = "image", x = 0, y = 0, fileId = "f1", scale = Drawing.list({ 1, 1 }) }
    scene.files = { f1 = { mimeType = "image/png", dataURL = "data:,", created = 1 }, unused = { mimeType = "image/png", dataURL = "data:,", created = 2 } }
    scene.someFutureField = { kept = true }
    local text = Drawing.encode(scene)
    check(not text:find("[\128-\255]") and not text:find("\127"), "ASCII only (nothing above U+007E written raw)")
    check(text:find("Caf\\u00e9", 1, true) and text:find("\\u2014", 1, true), "accents and dashes as \\uXXXX")
    check(text:find("\\ud83d\\ude00", 1, true), "an emoji as a UTF-16 surrogate pair, as JavaScript writes it")
    check(text:find('\\"quoted\\"\\n\\\\', 1, true), "quotes, newlines and backslashes escaped")
    check(text:find('"x":1,', 1, true) and text:find('"width":2.14', 1, true), "whole numbers without decimals, others to 2 decimals")
    check(text:find('"angle":0.12345678', 1, true), "an angle keeps its precision")
    check(text:find('"groupIds":[]', 1, true) and not text:find('"groupIds":{}', 1, true), "an empty list is []")
    check(not text:find('"gone"', 1, true), "a deleted element isn't written")
    check(text:find('"f1"', 1, true) and not text:find('"unused"', 1, true), "files no image uses are left out")
    check(text:find('"someFutureField":{"kept":true}', 1, true), "fields this version doesn't know are written back")
    check(#scene.elements == 4, "the scene itself isn't changed")

    local back = Json.decode(text)
    check(back and back.type == "memos-canvas" and #back.elements == 3, "it reads back as JSON")
    check(back.elements[2].text == scene.elements[2].text, "text comes back the same, accents and emoji included")

    local again, why = Drawing.decode(text)
    check(again and why == nil and #again.elements == 3, "Drawing.decode accepts it")
    local re = Drawing.encode(again)
    check(re:find('"groupIds":[]', 1, true) and re:find('"boundElements":[]', 1, true),
        "a scene read back writes its empty lists as [] again")
    check(not re:find('"groupIds":{}', 1, true) and not re:find('"boundElements":{}', 1, true), "…never as {}")

    check(select(2, Drawing.decode("{")) == "not-json", "not JSON: not-json")
    check(select(2, Drawing.decode('{"type":"excalidraw","version":1,"elements":[]}')) == "wrong-type", "another type: wrong-type")
    check(select(2, Drawing.decode('{"type":"memos-canvas","version":2,"elements":[]}')) == "version-too-high", "version 2: version-too-high")
    check(select(2, Drawing.decode('{"type":"memos-canvas","version":1.5,"elements":[]}')) == "invalid-scene", "version 1.5: invalid-scene")
    check(select(2, Drawing.decode('{"type":"memos-canvas","version":1,"elements":[{"id":"a","type":"freedraw","x":1,"y":2}]}')) == "invalid-scene",
        "a stroke without points: invalid-scene")
    check(select(2, Drawing.decode('{"type":"memos-canvas","version":1,"elements":[{"id":"","type":"text","x":1,"y":2,"text":""}]}')) == "invalid-scene",
        "an element without an id: invalid-scene")
    local ok = pcall(Drawing.encode, { type = "memos-canvas", version = 1, elements = Drawing.list({ { id = "n", type = "x", x = 0 / 0, y = 0 } }) })
    check(not ok, "a number that isn't finite can't be written")
end)()

print("== the PNG")
;(function()
    local png = greyPng(8, 6)
    local scene = Drawing.newScene()
    Drawing.addStroke(scene, Drawing.fromScreen({ { 10, 10 }, { 60, 40 }, { 120, 20 } }))
    Drawing.addStroke(scene, { { 5, 50, 0.3 }, { 6, 52, 0.6 }, { 9, 58, 0.9 } }, { width = 1 })
    local out = assert(Drawing.withScene(png, scene))
    local cs = Drawing.chunks(out)
    check(cs and cs[1].type == "IHDR" and cs[2].type == "zTXt", "the scene chunk right after IHDR, compressed (zTXt)")
    check(out:sub(cs[2].data, cs[2].data + 13) == "memos-canvas\0\0", "keyword memos-canvas, compression method 0")
    local names = {}
    for _i, c in ipairs(cs) do names[#names + 1] = c.type end
    check(table.concat(names, " ") == "IHDR zTXt tEXt IDAT IEND", "the PNG's own chunks kept, in order")
    local function idat(s) for _i, c in ipairs(Drawing.chunks(s)) do if c.type == "IDAT" then return s:sub(c.data, c.data + c.length - 1) end end end
    check(idat(out) == idat(png), "the pixels untouched")
    local back, why = Drawing.readScene(out)
    check(back and why == nil and #back.elements == 2, "read back: the scene and its two strokes")
    check(back and back.elements[2].points[3][3] == 0.9 and back.elements[2].simulatePressure == false, "…with their points and pressure")

    local again = assert(Drawing.withScene(out, Drawing.newScene()))
    local n = 0
    for _i, c in ipairs(Drawing.chunks(again)) do if c.type == "zTXt" or c.type == "tEXt" then n = n + 1 end end
    check(n == 2 and #assert(Drawing.readScene(again)).elements == 0, "a new scene replaces the old one (one scene chunk)")

    Drawing.no_zlib = true
    local plain = assert(Drawing.withScene(png, scene))
    Drawing.no_zlib = nil
    local pc = Drawing.chunks(plain)
    check(pc[2].type == "tEXt" and plain:sub(pc[2].data, pc[2].data + 12) == "memos-canvas\0", "without zlib: an uncompressed tEXt chunk")
    check(#assert(Drawing.readScene(plain)).elements == 2, "…which reads back too")

    check(select(2, Drawing.withScene("GIF89a", scene)) == "not-png", "not a PNG: not-png")
    check(select(2, Drawing.withScene(png:sub(1, 20), scene)) == "truncated", "a cut-off PNG: truncated")
    check(select(2, Drawing.readScene(png)) == "no-chunk", "a PNG without a scene: no-chunk")
    local broken = out:sub(1, cs[2].data + 20) .. string.char((out:byte(cs[2].data + 21) + 1) % 256) .. out:sub(cs[2].data + 22)
    check(select(2, Drawing.readScene(broken)) == "bad-crc", "a damaged scene chunk: bad-crc")
    -- after IDAT, memos doesn't look: neither do we
    local late = png:sub(1, #png - 12) .. chunk("tEXt", "memos-canvas\0" .. Drawing.encode(scene)) .. png:sub(#png - 11)
    check(select(2, Drawing.readScene(late)) == "no-chunk", "a scene chunk after the pixels isn't read (memos stops at IDAT)")

    local z = Drawing.deflate("hello hello hello")
    check(z and z:byte(1) == 0x78, "deflate is zlib's format (RFC 1950), as zTXt wants")
    check(ffi.sizeof("unsigned long") > 0 and Drawing.crc32("123456789") == 0xCBF43926, "CRC-32 of 123456789 is CBF43926")

    if OUT then
        os.execute("mkdir -p '" .. OUT .. "'")
        writeFile(OUT .. "/drawing-20261111-201500.canvas.png", out)
        writeFile(OUT .. "/drawing-20261111-201501.canvas.png", plain)
        local unicode = Drawing.newScene("#f7f3e8")
        Drawing.addStroke(unicode, { { 0, 0 }, { 1, 1 } }, { width = 2 })
        unicode.elements[2] = { id = "t", type = "text", x = 3, y = 4, text = "na\195\175ve \240\159\147\157", fontSize = 20,
            fontFamily = "sans", textAlign = "left", autoWidth = true, groupIds = Drawing.list(), boundElements = Drawing.list() }
        writeFile(OUT .. "/drawing-20261111-201502.canvas.png", assert(Drawing.withScene(png, unicode)))
    end
end)()

print("== files")
;(function()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local src, dst = dir .. "/page.png", dir .. "/" .. Drawing.fileName(os.time{ year = 2026, month = 11, day = 11, hour = 20, min = 15, sec = 7 })
    writeFile(src, greyPng(4, 4))
    local scene = Drawing.newScene()
    Drawing.addStroke(scene, { { 1, 1 }, { 2, 3 } })
    check(Drawing.writeFile(src, scene, dst) == true, "writeFile: the PNG with the scene written to a new file")
    check(dst:match("/drawing%-20261111%-201507%.canvas%.png$"), "the name memos gives a drawing: drawing-YYYYMMDD-HHMMSS.canvas.png")
    check(#assert(Drawing.readFile(dst)).elements == 1, "readFile reads it back")
    check(Drawing.writeFile(dst, Drawing.newScene()) == true and #assert(Drawing.readFile(dst)).elements == 0,
        "writeFile over the same file (through a temporary file)")
    local leftovers = io.open(dst .. ".part", "rb")
    check(leftovers == nil, "no temporary file left behind")
    if leftovers then leftovers:close() end
    check(Drawing.writeFile(dir .. "/missing.png", scene) == nil, "a missing PNG: nil")
    check(Drawing.isDrawingName("drawing-20261111-201507.canvas.png") and Drawing.isDrawingName("X.CANVAS.PNG")
        and not Drawing.isDrawingName("photo.png"), "isDrawingName: named like a drawing")
    os.execute("rm -rf '" .. dir .. "'")
end)()

print("== memos' own drawing")
;(function()
    local fixture = HERE .. "/media/memos-v1.canvas.png"
    local png = readFile(fixture)
    local scene, why = Drawing.readScene(png)
    check(scene and why == nil, "memos' test drawing reads (zTXt, written by @usememos/canvas)")
    check(scene and #scene.elements == 0 and scene.appState.viewBackgroundColor == "#1b1b1f", "…an empty dark-paper scene")
    check(scene and scene.appState.futureState == "kept", "…with a field this version doesn't know")
    Drawing.addStroke(scene, { { 0, 0 }, { 2, 2 } })
    local out = assert(Drawing.withScene(png, scene))
    local back = assert(Drawing.readScene(out))
    check(#back.elements == 1 and back.appState.futureState == "kept", "a stroke added to it: written back with the unknown field")
    if OUT then writeFile(OUT .. "/drawing-20261111-201503.canvas.png", out) end
end)()

print(string.format("drawing: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
