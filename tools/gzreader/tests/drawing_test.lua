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
    check(scene.appState.viewBackgroundColor == "#fbfaf7" and scene.appState.zoom == 1 and scene.appState.handDrawn == false,
        "a new scene: memos' paper (#fbfaf7), zoom 1, not hand-drawn")

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
    check(el.strokeWidth == 5 and el.strokeColor == "#ff0000"
        and Drawing.stroke({ { 0, 0 }, { 5, 5 } }, { width = 40 }).strokeWidth == 12 and Drawing.stroke({ { 0, 0 }, { 5, 5 } }, { width = 0 }).strokeWidth == 0.25
        and Drawing.stroke({ { 0, 0 }, { 5, 5 } }, {}).strokeWidth == 2,
        "its width kept as given (memos draws any; within 0.25 to 12, 2 when not said); colour lower case")
    check(type(el.id) == "string" and el.id:match("^[0-9A-Za-z]+$") and #el.id == 10, "a 10-character id of letters and digits")
    check(el.seed >= 0 and el.seed < 2^31 and el.seed == math.floor(el.seed), "a 31-bit seed")
    check(el.angle == 0 and el.opacity == 100 and el.isDeleted == false and el.locked == false
        and el.backgroundColor == "transparent", "the other fields version 1 asks of every element")

    local p2 = Drawing.stroke({ { 0, 0, 0.2 }, { 5, 5, 1.7 }, { 9, 1, -1 } }, { color = "red", width = 1, opacity = 40 })
    check(p2.simulatePressure == false and p2.points[1][3] == 0.2 and p2.points[2][3] == 1 and p2.points[3][3] == 0,
        "pressure on every point: kept, between 0 and 1")
    check(p2.strokeColor == "#1a1a1a" and p2.strokeWidth == 1 and p2.opacity == 40, "a colour that isn't #rrggbb: memos' ink")
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
    local nul = Drawing.encode({ type = "memos-canvas", version = 1, elements = Drawing.list({ { id = "t", type = "text", x = 0, y = 0,
        text = "a", containerId = function() end } }) })
    check(nul:find('"containerId":null', 1, true) ~= nil, "a JSON library's null placeholder (LuaJSON's is a function) is written as null")
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

print("== a drawing made in memos' web app (6 pen strokes, an ellipse, a text)")
;(function()
    local png = readFile(HERE .. "/media/memos-drawing.canvas.png")
    local scene, why = Drawing.readScene(png)
    check(scene and why == nil, "it reads")
    if not scene then return end
    local kinds = {}
    for _i, el in ipairs(scene.elements) do kinds[el.type] = (kinds[el.type] or 0) + 1 end
    check(kinds.freedraw == 6 and kinds.ellipse == 1 and kinds.text == 1, "its elements: 6 strokes, 1 ellipse, 1 text")
    check(scene.appState.viewBackgroundColor == Drawing.PAPER, "its paper is Drawing.PAPER (#fbfaf7)")
    local inks, offsets_ok = true, true
    for _i, el in ipairs(scene.elements) do
        if el.strokeColor ~= Drawing.INK then inks = false end
        if el.type == "freedraw" then
            local mx, my, xx, xy = math.huge, math.huge, 0, 0
            for _j, p in ipairs(el.points) do
                mx, my = math.min(mx, p[1]), math.min(my, p[2]); xx, xy = math.max(xx, p[1]), math.max(xy, p[2])
            end
            if mx ~= 0 or my ~= 0 or math.abs(xx - el.width) > 0.011 or math.abs(xy - el.height) > 0.011 then offsets_ok = false end
        end
    end
    check(inks, "its ink is Drawing.INK (#1a1a1a)")
    check(offsets_ok, "memos' strokes are what Drawing.stroke makes: offsets from the box's top left, box = extent")
    local thick
    for _i, el in ipairs(scene.elements) do if el.type == "freedraw" and el.strokeWidth == 4 then thick = el end end
    check(thick and thick.simulatePressure == true and thick.points[1][3] == 0.5, "a mouse stroke: simulated pressure, 0.5 stored (as ours)")
    check(Drawing.strokeDiameter(2) == 8 and Drawing.strokeDiameter(4) == 14, "full widths 8 and 14 units for widths 2 and 4")
    local text
    for _i, el in ipairs(scene.elements) do if el.type == "text" then text = el end end
    check(text and text.text == "jjjj" and text.containerId == nil, "its text element, its null containerId read as nil")
    Drawing.addStroke(scene, { { 10, 10 }, { 40, 30 } })
    local back = assert(Drawing.readScene(assert(Drawing.withScene(png, scene))))
    check(#back.elements == 9 and back.elements[9].type == "freedraw", "a stroke added: 9 elements written back")
    if OUT then writeFile(OUT .. "/drawing-20261112-173500.canvas.png", assert(Drawing.withScene(png, scene))) end
end)()

print("== notepaper: a background as memos keeps one")
;(function()
    package.preload["gettext"] = package.preload["gettext"] or function() return function(t) return t end end
    local Notepaper = require("gzreader_notepaper")
    local scene = Notepaper.scene("college")
    local bg = scene.elements[1]
    check(bg and bg.type == "image" and bg.locked and scene.files[bg.fileId] and #Notepaper.LIST == 18
        and Notepaper.LIST[1].id == "blank" and Notepaper.get("checklist").label == "Checklist" and Notepaper.get("cornell").label == "Cornell notes",
        "a new page on College ruled: its picture under everything, in the scene's files (eighteen papers offered, Blank first; the earlier ones still known)")
    local labels = {}
    for _i, p in ipairs(Notepaper.all()) do labels[#labels + 1] = p.label end
    check(table.concat(labels, "|") == "Blank|Medium ruled|Medium ruled with margin|Wide ruled|Wide ruled with margin|Narrow ruled|"
        .. "Narrow ruled with margin|Vertical ruled|Vertical ruled with margin|Graph|Dotted|Checklist|Daily planner|Weekly planner|"
        .. "Monthly planner|Habit tracker|Storyboard|Music",
        "the papers offered: the Kindle Scribe's templates, in its order after Blank")
    local function isFile(path) local f = path and io.open(path, "rb"); if f then f:close() end; return f ~= nil end
    local tiles, seen = true, {}
    for _i, p in ipairs(Notepaper.LIST) do
        if seen[p.id] or (p.file and not (isFile(Notepaper.path(p)) and isFile(Notepaper.tile(p)))) then tiles = false end
        seen[p.id] = true
    end
    check(tiles and Notepaper.tile(Notepaper.get("blank")) == nil, "…each has its page and the chooser's small tile (Blank: neither)")
    -- in colour (blue rules, a red margin line): shown so on a colour screen and in Memos
    local function coloured(path)
        local f = io.open(path, "rb"); local data = f:read("*a"); f:close()
        local at = data:find("PLTE", 1, true)
        if not at then return false end
        local n = ((data:byte(at - 4) * 256 + data:byte(at - 3)) * 256 + data:byte(at - 2)) * 256 + data:byte(at - 1)
        for i = at + 4, at + 3 + n - 2, 3 do
            local r, g, b = data:byte(i, i + 2)
            if math.abs(r - b) > 30 or math.abs(r - g) > 30 then return true end
        end
        return false
    end
    local grey = {}
    for _i, p in ipairs(Notepaper.LIST) do
        if p.file and p.id ~= "dots" and not coloured(Notepaper.path(p)) then grey[#grey + 1] = p.id end
    end
    check(#grey == 0 and coloured(Notepaper.path(Notepaper.get("ruled-medium-margin")))
        and coloured(Notepaper.tile(Notepaper.get("weekly"))),
        "the papers are in colour (a colour screen and Memos show them so; Dotted is grey dots): " .. table.concat(grey, ","))
    local msc = Notepaper.scene("music")
    check(msc.files[msc.elements[1].fileId].dataURL == Notepaper.dataURL("music")
        and require("ffi/sha2").base64_to_bin(Notepaper.dataURL("music"):match(",(.*)$")) == io.open(Notepaper.path(Notepaper.get("music")), "rb"):read("*a"),
        "a page on a paper carries the paper's own PNG to Memos, byte for byte (its colours with it)")
    -- notebook paper: the margin papers have their three punched holes (pale grey discs left of the margin line)
    ;(function()
        local f = io.open(Notepaper.path(Notepaper.get("ruled-medium-margin")), "rb"); local now = f:read("*a"); f:close()
        f = io.open(Notepaper.path(Notepaper.get("ruled-medium-margin-plain")), "rb"); local was = f:read("*a"); f:close()
        check(now ~= was and #now > 0 and #was > 0 and Notepaper.get("ruled-medium-margin").label == "Medium ruled with margin"
            and Notepaper.get("ruled-wide-margin-plain") ~= nil and Notepaper.get("ruled-narrow-margin-plain") ~= nil,
            "the margin papers are notebook paper again (punched holes); the ones without are kept for pages drawn on them")
    end)()
    for _i, p in ipairs(Notepaper.EARLIER) do
        local sc = Notepaper.scene(p.id)
        check(not seen[p.id] and sc.elements[1] and Notepaper.idOf(sc, sc.elements[1]) == p.id,
            p.label .. " (offered before): not in the chooser, a page on it still known as it")
    end
    local every = {}
    for _i, p in ipairs(Notepaper.LIST) do every[#every + 1] = p end
    for _i, p in ipairs(Notepaper.EARLIER) do every[#every + 1] = p end
    for _i, p in ipairs(every) do
        if p.file then
            local url = Notepaper.dataURL(p.id)
            local png = url and require("ffi/sha2").base64_to_bin(url:match(",(.*)$"))
            local w, h = png and png:sub(17, 20), png and png:sub(21, 24)
            local function be(x) local a, b, c, d = x:byte(1, 4); return ((a * 256 + b) * 256 + c) * 256 + d end
            check(png and png:sub(1, 8) == "\137PNG\r\n\26\n" and be(w) == Notepaper.W and be(h) == Notepaper.H,
                p.label .. ": a PNG at memos' stored size (" .. Notepaper.W .. " x " .. Notepaper.H .. ")")
        end
    end
    Drawing.addStroke(scene, { { 100, 120 }, { 400, 160 } })
    local png = greyPng(4, 4)
    local out = assert(Drawing.withScene(png, scene))
    local back = assert(Drawing.readScene(out))
    check(back.files[back.elements[1].fileId].dataURL == Notepaper.dataURL("college"), "read back: the paper's picture as it was")
    if OUT then writeFile(OUT .. "/drawing-20261112-221000.canvas.png", out) end
end)()

print("== your own notepaper (PNG files in settings/gzreader-notepaper)")
;(function()
    local Notepaper = require("gzreader_notepaper")
    package.preload["libs/libkoreader-lfs"] = package.preload["libs/libkoreader-lfs"] or function() return require("lfs") end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not (ok and lfs and OUT) then print("  (skipped: no lfs / work folder)"); return end
    local dir = OUT .. "/own-paper"
    os.execute("mkdir -p '" .. dir .. "'")
    local real_dir = Notepaper.ownDir
    Notepaper.ownDir = function() return dir end
    check(#Notepaper.own() == 0 and #Notepaper.all() == #Notepaper.LIST, "no files: only the papers that come with GZreader")
    writeFile(dir .. "/Planner page.png", greyPng(60, 80))
    writeFile(dir .. "/notes.txt", "not a picture")
    writeFile(dir .. "/broken.png", "PNG? no")
    writeFile(dir .. "/huge.png", greyPng(1500, 100))
    local own = Notepaper.own()
    check(#own == 1 and own[1].id == "own:Planner page.png" and own[1].label == "Planner page" and own[1].w == 60 and own[1].h == 80,
        "a PNG there is a paper, named after its file (not other files, a broken PNG, or one over 1440 px)")
    local all = Notepaper.all()
    check(#all == #Notepaper.LIST + 1 and all[#all].id == "own:Planner page.png" and Notepaper.get("own:Planner page.png") ~= nil
        and Notepaper.path(Notepaper.get("own:Planner page.png")) == dir .. "/Planner page.png",
        "…listed after GZreader's own")
    local scene = Notepaper.scene("own:Planner page.png")
    local bg = scene.elements[1]
    check(bg and bg.type == "image" and bg.locked and bg.width == 60 and bg.height == 80
        and scene.files[bg.fileId].dataURL:match("^data:image/png;base64,") ~= nil,
        "a page on it: the picture under everything at its own size, as Memos keeps a background")
    check(Notepaper.idOf(scene, bg) == "own:Planner page.png", "…recognised again when the drawing is opened")
    os.remove(dir .. "/Planner page.png")
    check(Notepaper.get("own:Planner page.png") == nil and Notepaper.idOf(scene, bg) == nil,
        "the file gone: the drawing keeps its picture, the paper is no longer offered")
    Notepaper.ownDir = real_dir
end)()

print(string.format("drawing: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
