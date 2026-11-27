--[[--
Kid Pix stickers for the drawing screen's Stickers tool (gzreader_drawscreen.lua,
picked in gzreader_stickergrid.lua).

The stickers are the Memos fork's: Kid Pix Deluxe 4's 935 stickers, which the
fork draws from their Flash movies in its own drawing sheet. A Kindle can't read
Flash, so the fork also serves them as SVG pictures, gzipped (its
web/scripts/render-kidpix-stickers.mjs; swf.ts's svg()):

    <memos>/kidpix/sticker-svg/index.json
        { version = 1, categories = { { slug, name, items = { { name, file, width, height } } } } }
    <memos>/kidpix/sticker-svg/<slug>/<n>.svgz   (the sticker's shapes, at its own size, a clear ground)

They're public files of the web app (no sign-in). The list and a category's
pictures are fetched the first time they're opened (over Wi-Fi), unzipped and
kept in cache/gzreader-stickers/ as <slug>/<n>.svg, so a category opened once
works without Wi-Fi.

A sticker goes on the page as a picture (Sketch:addPicture), as the fork's own
Kid Pix mode puts its stickers into the drawing: drawn from its SVG at the size
it's put down (sharp at any size), kept in the drawing as a PNG. Memos shows it,
the lasso moves and sizes it, Undo takes it off.
]]

local DataStorage = require("datastorage")
local JSON = require("gzreader_json")
local Log = require("gzreader_log")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local Stickers = {
    PATH = "/kidpix/sticker-svg/",
    MAX_BYTES = 512 * 1024, -- (a sticker as fetched, gzipped; the biggest is about 60 kB)
    MAX_SVG_BYTES = 4 * 1024 * 1024, -- (unzipped; the biggest is about 250 kB)
    PX_PER_UNIT = 2, -- (a sticker put down: drawn at 2 pixels a drawing unit, as sharp as a Scribe shows it)
    MAX_SIDE = 1600, -- (… and never more than this many pixels a side)
    MAX_INDEX_BYTES = 1024 * 1024, -- (the list; the fork's is about 100 kB)
    MAX_CATEGORIES = 100, -- (the fork has 42)
    MAX_ITEMS = 500, -- (in a category; the fork's biggest has about 60)
    -- the sizes offered: the sticker's own size (1x: as Kid Pix put it down) times these
    SIZES = { 1, 1.6, 2.4 },
    DEFAULT_SIZE = 2,
}

--- Where the list and the pictures are kept.
function Stickers.dir()
    local dir = DataStorage:getDataDir() .. "/cache/gzreader-stickers"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        lfs.mkdir(dir)
    end
    return dir
end

--- The Memos server the stickers come from (GZreader's Memos sign-in), or nil.
function Stickers.server(plugin)
    local m = plugin and plugin.store and plugin.store.memos
    local s = type(m) == "table" and m.server
    if type(s) ~= "string" or not s:match("^https?://") then return nil end
    return (s:gsub("/+$", ""))
end

local function safe(s) return type(s) == "string" and s:match("^[%w][%w%-_]*$") ~= nil end

--- The fork's index.json, checked: { categories = { { slug, name, items = { { name, file, w, h } } } } } or nil.
--- (A file name must be "<slug>/<n>.svgz": nothing else is fetched or written.)
function Stickers.parseIndex(data)
    if type(data) ~= "table" or tonumber(data.version) ~= 1 or type(data.categories) ~= "table" then return nil end
    local out = { scale = tonumber(data.scale) or 2, categories = {} }
    for _i, c in ipairs(data.categories) do
        if #out.categories >= Stickers.MAX_CATEGORIES then break end
        if type(c) == "table" and safe(c.slug) and type(c.items) == "table" then
            local cat = { slug = c.slug, name = type(c.name) == "string" and c.name or c.slug, items = {} }
            for n, it in ipairs(c.items) do
                if n > Stickers.MAX_ITEMS then break end
                local file = type(it) == "table" and it.file
                local w, h = tonumber(type(it) == "table" and it.width), tonumber(type(it) == "table" and it.height)
                if file == c.slug .. "/" .. (n - 1) .. ".svgz" and w and h and w > 0 and h > 0 then
                    cat.items[#cat.items + 1] = { name = type(it.name) == "string" and it.name or "", file = file,
                        here = c.slug .. "/" .. (n - 1) .. ".svg", w = w, h = h, slug = c.slug }
                end
            end
            if #cat.items > 0 then out.categories[#out.categories + 1] = cat end
        end
    end
    return #out.categories > 0 and out or nil
end

--- The list kept on the Kindle (from the last time it was fetched), or nil.
function Stickers.index()
    local f = io.open(Stickers.dir() .. "/index.json", "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local ok, data = pcall(JSON.decode, text)
    return ok and Stickers.parseIndex(data) or nil
end

--- A sticker's picture on the Kindle (its SVG's path), or nil when it isn't there yet.
function Stickers.path(item)
    local p = Stickers.dir() .. "/" .. item.here
    return lfs.attributes(p, "mode") == "file" and p or nil
end

--- How many of a category's pictures are on the Kindle.
function Stickers.have(cat)
    local n = 0
    for _i, it in ipairs(cat.items) do if Stickers.path(it) then n = n + 1 end end
    return n
end

--- GET `url` into `sink`, at most `max` bytes (more: the download stops).
--- Returns the HTTP code (nil: no answer, or stopped) and whether it was too big.
local function get(url, sink, max)
    local Api = require("gzreader_api")
    local got, over = 0, false
    local function capped(chunk, err)
        if chunk then
            got = got + #chunk
            if got > max then over = true; return nil, "too big" end
        end
        return sink(chunk, err)
    end
    local code = Api.rawRequest("GET", url, { headers = { Accept = "image/svg+xml, application/gzip, application/json" }, sink = capped,
        timeouts = { 10, 30 } })
    return code, over
end

--- Fetches the list from `server` and keeps it: the list, or nil, err.
--- (In a background process or with Wi-Fi up: it waits for the answer.)
function Stickers.fetchIndex(server)
    local parts = {}
    local code, over = get(server .. Stickers.PATH .. "index.json", ltn12.sink.table(parts), Stickers.MAX_INDEX_BYTES)
    local text = table.concat(parts)
    if over then return nil, "too_big" end
    if type(code) ~= "number" then return nil, "unreachable" end
    if code == 404 then return nil, "no_stickers" end -- (a Memos without the fork's sticker pictures)
    if code ~= 200 then return nil, "http_" .. code end
    local ok, data = pcall(JSON.decode, type(text) == "string" and text or "")
    local index = ok and Stickers.parseIndex(data) or nil
    if not index then return nil, "bad_index" end
    local f = io.open(Stickers.dir() .. "/index.json", "wb")
    if f then f:write(text); f:close() end
    Log.info("stickers: the list,", #index.categories, "categories")
    return index
end

--- Fetches the pictures of category `cat` that aren't on the Kindle yet
--- (each gzipped SVG, unzipped and checked): how many it has now, and an
--- error when some couldn't be fetched.
function Stickers.fetchCategory(server, cat)
    local Gzip = require("gzreader_gzip")
    if not Gzip.available() then return Stickers.have(cat), "no_gzip" end
    local dir = Stickers.dir() .. "/" .. cat.slug
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local err
    for _i, it in ipairs(cat.items) do
        if not Stickers.path(it) then
            local parts = {}
            local code, over = get(server .. Stickers.PATH .. it.file, ltn12.sink.table(parts), Stickers.MAX_BYTES)
            local data = table.concat(parts)
            local svg, zerr
            if code == 200 and not over and data:sub(1, 2) == "\31\139" then
                svg, zerr = Gzip.inflate(data, Stickers.MAX_SVG_BYTES)
            end
            if svg and svg:match("^%s*<svg[%s>]") then
                local path = Stickers.dir() .. "/" .. it.here
                local fh = io.open(path .. ".part", "wb")
                if not fh then err = "write"; break end
                fh:write(svg)
                fh:close()
                os.rename(path .. ".part", path)
            else
                err = (over or zerr == "too big") and "too_big" or type(code) ~= "number" and "unreachable"
                    or code ~= 200 and ("http_" .. code) or "not_svg"
                if err == "unreachable" then break end
            end
        end
    end
    local n = Stickers.have(cat)
    Log.info("stickers:", cat.slug, n, "of", #cat.items, err and ("(" .. err .. ")") or "")
    return n, err
end

--- Sticker `item` at size `k` (Stickers.SIZES' index): its width and height in
--- the drawing's units (the drawing's units are Memos' pixels: a sticker at 1x
--- is as big as Kid Pix put it down).
function Stickers.size(item, k)
    local f = Stickers.SIZES[k] or Stickers.SIZES[Stickers.DEFAULT_SIZE]
    return item.w * f, item.h * f
end

--- Sticker `item` drawn from its SVG `w` x `h` pixels (its shape kept,
--- centred): a BlitBuffer (RGB with a clear ground), or nil.
function Stickers.render(item, w, h)
    local p = Stickers.path(item)
    if not p then return nil end
    local ok, bb = pcall(function()
        return require("ui/renderimage"):renderSVGImageFile(p, math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5)))
    end)
    if not ok or not bb then
        Log.warn("stickers: couldn't draw", item.here, ok and "" or tostring(bb))
        return nil
    end
    return bb
end

--- The sticker's picture as the drawing keeps it, for a sticker `w` x `h`
--- drawing units: drawn from its SVG at that size (PX_PER_UNIT, at most
--- MAX_SIDE a side), as a PNG data URL; or nil.
function Stickers.dataURL(item, w, h)
    local k = math.min(Stickers.PX_PER_UNIT, Stickers.MAX_SIDE / math.max(w, h))
    local bb = Stickers.render(item, w * k, h * k)
    if not bb then return nil end
    local tmp = Stickers.dir() .. "/stamp.png"
    local ok = pcall(bb.writePNG, bb, tmp)
    bb:free()
    local f = ok and io.open(tmp, "rb")
    local data = f and f:read("*a")
    if f then f:close() end
    os.remove(tmp)
    if not data or data:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end
    return "data:image/png;base64," .. require("gzreader_b64").encode(data)
end

--- The sticker and size last used (kept for next time): { slug, n }, size.
function Stickers.last()
    local s = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_sticker")
    local size = G_reader_settings and G_reader_settings:readSetting("gzreader_drawing_sticker_size")
    return type(s) == "table" and safe(s.slug) and tonumber(s.n) and s or nil, Stickers.SIZES[tonumber(size)] and tonumber(size) or Stickers.DEFAULT_SIZE
end

--- The sticker `slug`/`n` (0-based, as the fork's files) in `index`, or nil.
function Stickers.find(index, slug, n)
    for _i, c in ipairs(index and index.categories or {}) do
        if c.slug == slug then return c.items[(tonumber(n) or -1) + 1], c end
    end
end

--- The number of a sticker in its category (0-based, as its file).
function Stickers.number(item) return tonumber(item.file:match("/(%d+)%.svgz$")) end

--- Why fetching failed, in words.
function Stickers.why(err)
    local _ = require("gettext")
    if err == "no_server" then return _("Stickers come from your Memos server: sign in to Memos first (Settings → Accounts and services → Memos).") end
    if err == "no_stickers" then return _("Your Memos server has no stickers. They come with the Memos fork's Kid Pix stickers (sticker pictures from November 2026 on).") end
    if err == "unreachable" then return _("Couldn't reach your Memos server for the stickers.") end
    if err == "no_gzip" then return _("This Kindle can't unpack the stickers (no zlib).") end
    return _("Couldn't fetch the stickers.") .. " (" .. tostring(err) .. ")"
end

return Stickers
