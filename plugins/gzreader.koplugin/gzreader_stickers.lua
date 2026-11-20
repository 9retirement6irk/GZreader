--[[--
Kid Pix stickers for the drawing screen's Stickers tool (gzreader_drawscreen.lua,
picked in gzreader_stickergrid.lua).

The stickers are the Memos fork's: Kid Pix Deluxe 4's 935 stickers, which the
fork draws from their Flash movies in its own drawing sheet. A Kindle can't read
Flash, so the fork also serves them as PNG pictures (its
web/scripts/render-kidpix-stickers.mjs):

    <memos>/kidpix/sticker-png/index.json
        { version = 1, scale = 2, categories = { { slug, name, items = { { name, file, width, height } } } } }
    <memos>/kidpix/sticker-png/<slug>/<n>.png   (twice the sticker's own size, 256 colours, a clear ground)

They're public files of the web app (no sign-in). The list and a category's
pictures are fetched the first time they're opened (over Wi-Fi) and kept in
cache/gzreader-stickers/, so a category opened once works without Wi-Fi.

A sticker goes on the page as a picture (Sketch:addPicture), as the fork's own
Kid Pix mode puts its stickers into the drawing: Memos shows it, the lasso
moves and sizes it, Undo takes it off.
]]

local DataStorage = require("datastorage")
local JSON = require("gzreader_json")
local Log = require("gzreader_log")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local Stickers = {
    PATH = "/kidpix/sticker-png/",
    MAX_BYTES = 512 * 1024, -- (a sticker picture; the biggest is about 60 kB)
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
--- (A file name must be "<slug>/<n>.png": nothing else is fetched or written.)
function Stickers.parseIndex(data)
    if type(data) ~= "table" or tonumber(data.version) ~= 1 or type(data.categories) ~= "table" then return nil end
    local out = { scale = tonumber(data.scale) or 2, categories = {} }
    for _i, c in ipairs(data.categories) do
        if type(c) == "table" and safe(c.slug) and type(c.items) == "table" then
            local cat = { slug = c.slug, name = type(c.name) == "string" and c.name or c.slug, items = {} }
            for n, it in ipairs(c.items) do
                local file = type(it) == "table" and it.file
                local w, h = tonumber(type(it) == "table" and it.width), tonumber(type(it) == "table" and it.height)
                if file == c.slug .. "/" .. (n - 1) .. ".png" and w and h and w > 0 and h > 0 then
                    cat.items[#cat.items + 1] = { name = type(it.name) == "string" and it.name or "", file = file, w = w, h = h, slug = c.slug }
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

--- A sticker's picture on the Kindle (its path), or nil when it isn't there yet.
function Stickers.path(item)
    local p = Stickers.dir() .. "/" .. item.file
    return lfs.attributes(p, "mode") == "file" and p or nil
end

--- How many of a category's pictures are on the Kindle.
function Stickers.have(cat)
    local n = 0
    for _i, it in ipairs(cat.items) do if Stickers.path(it) then n = n + 1 end end
    return n
end

local function get(url, sink)
    local Api = require("gzreader_api")
    return Api.rawRequest("GET", url, { headers = { Accept = sink and "image/png" or "application/json" }, sink = sink,
        want_raw = not sink or nil, timeouts = { 10, 30 } })
end

--- Fetches the list from `server` and keeps it: the list, or nil, err.
--- (In a background process or with Wi-Fi up: it waits for the answer.)
function Stickers.fetchIndex(server)
    local code, text = get(server .. Stickers.PATH .. "index.json")
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

--- Fetches the pictures of category `cat` that aren't on the Kindle yet:
--- how many it has now, and an error when some couldn't be fetched.
function Stickers.fetchCategory(server, cat)
    local dir = Stickers.dir() .. "/" .. cat.slug
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local err
    for _i, it in ipairs(cat.items) do
        if not Stickers.path(it) then
            local path = Stickers.dir() .. "/" .. it.file
            local part = path .. ".part"
            local fh = io.open(part, "wb")
            if not fh then err = "write"; break end
            local code = get(server .. Stickers.PATH .. it.file, ltn12.sink.file(fh))
            local size = lfs.attributes(part, "size") or 0
            local head
            local rf = io.open(part, "rb")
            if rf then head = rf:read(8); rf:close() end
            if code == 200 and size > 0 and size <= Stickers.MAX_BYTES and head == "\137PNG\r\n\26\n" then
                os.rename(part, path)
            else
                os.remove(part)
                err = type(code) == "number" and ("http_" .. code) or "unreachable"
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

--- The sticker's picture as the drawing keeps it: a PNG data URL, or nil.
function Stickers.dataURL(item)
    local p = Stickers.path(item)
    local f = p and io.open(p, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    if not data or #data == 0 then return nil end
    return "data:image/png;base64," .. require("ffi/sha2").bin_to_base64(data)
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
function Stickers.number(item) return tonumber(item.file:match("/(%d+)%.png$")) end

--- Why fetching failed, in words.
function Stickers.why(err)
    local _ = require("gettext")
    if err == "no_server" then return _("Stickers come from your Memos server: sign in to Memos first (Settings → Accounts and services → Memos).") end
    if err == "no_stickers" then return _("Your Memos server has no stickers. They come with the Memos fork's Kid Pix stickers (sticker pictures from November 2026 on).") end
    if err == "unreachable" then return _("Couldn't reach your Memos server for the stickers.") end
    return _("Couldn't fetch the stickers.") .. " (" .. tostring(err) .. ")"
end

return Stickers
