--[[--
Photos from Immich, picked on the Kindle: for a note (they go with it as
attachments, as the Memos fork's "Insert image → From Immich" does) and for a
drawing (placed in it as a picture, as the fork's drawing sheet does).

Two ways to reach Immich, the first one there:
- the Memos fork's own connection (Settings → Immich in its web app): its
  /api/immich proxy, with GZreader's Memos sign-in (the Immich key stays on
  the Memos server);
- GZreader's Immich connection (Settings → Immich, the sleep screen's), with
  its API key.
When both are there, the picker can switch between them.

What's fetched: each photo's small thumbnail to pick from, then Immich's
preview of the ones picked (a JPEG at most 1440 pixels a side: what the fork's
drawing sheet uses; plenty for a Kindle, and quick over its Wi‑Fi).

    Pick.show(plugin, { title, on_pick = function(files) end })
    -- files: { { path, filename, type = "image/jpeg", w, h, id } }, in the order picked
]]

local JSON = require("gzreader_json")
local Log = require("gzreader_log")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local Pick = {
    PAGE = 60,          -- photos asked for at once (the fork's page)
    MAX_BYTES = 20 * 1048576,
    MAX_PICK = 20,      -- photos picked at once, at most
}

local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

--- True for an Immich id (what goes into a path).
function Pick.isId(id) return type(id) == "string" and id:match(UUID) ~= nil end

--- A picked photo's file name: its own, ending in .jpg (the preview is a JPEG,
--- whatever the original was: HEIC, PNG…), safe as a file name.
function Pick.fileName(name, id)
    name = type(name) == "string" and name or ""
    name = name:gsub("[/\\:%*%?\"<>|%c]", "_")
    local base = name:match("^(.*)%.[%w]+$") or name
    if base == "" then base = "photo-" .. tostring(id or ""):sub(1, 8) end
    return base .. ".jpg"
end

--- A page of photos from the fork's /api/immich/photos: { photos = { { id,
--- filename, w, h, taken } }, next } (next: nil at the end).
function Pick.parseMemosPage(data)
    local out = { photos = {} }
    if type(data) ~= "table" then return out end
    for _i, p in ipairs(type(data.photos) == "table" and data.photos or {}) do
        if type(p) == "table" and Pick.isId(p.id) then
            out.photos[#out.photos + 1] = { id = p.id, filename = tostring(p.fileName or ""), w = tonumber(p.width), h = tonumber(p.height),
                taken = type(p.takenAt) == "string" and p.takenAt or nil }
        end
    end
    out.next = type(data.next) == "string" and data.next ~= "" and data.next or nil
    return out
end

--- A page of Immich's own search (POST /search/metadata), the same shape;
--- next: "c:<cursor>" (Immich 3.2 and later) or "p:<page>" (before), as the fork pages.
function Pick.parseImmichPage(data)
    local out = { photos = {} }
    local assets = type(data) == "table" and type(data.assets) == "table" and data.assets
    if not assets then return out end
    for _i, a in ipairs(type(assets.items) == "table" and assets.items or {}) do
        if type(a) == "table" and Pick.isId(a.id) and (a.type == nil or a.type == "IMAGE") and not a.isTrashed then
            local exif = type(a.exifInfo) == "table" and a.exifInfo or {}
            out.photos[#out.photos + 1] = { id = a.id, filename = tostring(a.originalFileName or ""),
                w = tonumber(a.width or exif.exifImageWidth), h = tonumber(a.height or exif.exifImageHeight),
                taken = type(a.localDateTime) == "string" and a.localDateTime or nil }
        end
    end
    if type(assets.nextCursor) == "string" and assets.nextCursor ~= "" then
        out.next = "c:" .. assets.nextCursor
    elseif tostring(assets.nextPage):match("^%d+$") then -- (a number or "2"; null: the last page)
        out.next = "p:" .. tostring(assets.nextPage)
    end
    return out
end

-- ------------------------------------------------------------ the two ways in

local function download(url, headers, path)
    local part = path .. ".part"
    local fh, ferr = io.open(part, "wb")
    if not fh then return false, ferr end
    local Api = require("gzreader_api")
    local h = { Accept = "image/*" }
    for k, v in pairs(headers) do h[k] = v end
    local code, _, resp = Api.rawRequest("GET", url, { headers = h, sink = ltn12.sink.file(fh), timeouts = { 10, 60 } })
    local ctype = tostring(type(resp) == "table" and (resp["content-type"] or resp["Content-Type"]) or "")
    local size = lfs.attributes(part, "size") or 0
    if code == 200 and size > 0 and size <= Pick.MAX_BYTES and ctype:find("image", 1, true) then
        os.rename(part, path)
        return true
    end
    os.remove(part)
    if type(code) ~= "number" then return false, "unreachable" end
    return false, "http_" .. tostring(code)
end

local function json(method, url, headers, body)
    local Api = require("gzreader_api")
    local h = { Accept = "application/json" }
    for k, v in pairs(headers) do h[k] = v end
    local code, data = Api.rawRequest(method, url, { headers = h, body = body, timeouts = { 10, 30 } })
    if type(code) ~= "number" then return nil, "unreachable" end
    if code == 401 or code == 403 then return nil, "unauthorized" end
    if code == 404 then return nil, "not_connected" end
    if code >= 400 then return nil, "http_" .. code end
    return data
end

--- The Memos fork's Immich (its /api/immich proxy), for GZreader's Memos sign-in `memos` (plugin.store.memos).
function Pick.memosSource(memos)
    local base = tostring(memos.server or ""):gsub("/+$", "") .. "/api/immich"
    local headers = { Authorization = "Bearer " .. tostring(memos.token or "") }
    local src = { kind = "memos" }
    function src.connected()
        local data, err = json("GET", base .. "/connection", headers)
        if not data then return false, err end
        return data.configured == true
    end
    function src.albums()
        local data, err = json("GET", base .. "/albums", headers)
        if not data then return nil, err end
        local list = {}
        for _i, a in ipairs(type(data) == "table" and data or {}) do
            if type(a) == "table" and Pick.isId(a.id) then
                list[#list + 1] = { id = a.id, name = tostring(a.name or "?"), count = tonumber(a.photoCount) or 0 }
            end
        end
        table.sort(list, function(x, y) return x.name:lower() < y.name:lower() end)
        return list
    end
    function src.photos(album, next)
        local q = {}
        if album then q[#q + 1] = "album=" .. album end
        if next then q[#q + 1] = "next=" .. require("socket.url").escape(next) end
        local data, err = json("GET", base .. "/photos" .. (#q > 0 and ("?" .. table.concat(q, "&")) or ""), headers)
        if not data then return nil, err end
        return Pick.parseMemosPage(data)
    end
    function src.thumbnail(id, path) return download(base .. "/photos/" .. id .. "/thumbnail", headers, path) end
    function src.preview(id, path) return download(base .. "/photos/" .. id .. "/preview", headers, path) end
    return src
end

--- GZreader's own Immich connection (plugin.store.immich: server, key).
function Pick.immichSource(store)
    local base = tostring(store.server or ""):gsub("/+$", "") .. "/api"
    local headers = { ["x-api-key"] = tostring(store.key or "") }
    local src = { kind = "immich" }
    function src.connected() return type(store.key) == "string" and store.key ~= "" and type(store.server) == "string" end
    function src.albums()
        local list, err = require("gzreader_immich"):new(store):albums()
        return list, err
    end
    function src.photos(album, next)
        local body = { size = Pick.PAGE, order = "desc", type = "IMAGE" }
        if album then body.albumIds = JSON.list({ album }) else body.visibility = "timeline" end
        if next and next:match("^c:") then body.cursor = next:sub(3)
        elseif next and next:match("^p:") then body.page = tonumber(next:sub(3)) or 2 end
        local data, err = json("POST", base .. "/search/metadata", headers, body)
        if not data then return nil, err end
        return Pick.parseImmichPage(data)
    end
    function src.thumbnail(id, path) return download(base .. "/assets/" .. id .. "/thumbnail?size=thumbnail", headers, path) end
    function src.preview(id, path) return download(base .. "/assets/" .. id .. "/thumbnail?size=preview", headers, path) end
    return src
end

--- The ways to Immich this Kindle has, best first: { source… } (the fork's
--- is only listed; whether it's set up there is asked on the way in).
function Pick.sources(plugin)
    local out = {}
    local m = plugin.store and plugin.store.memos
    if type(m) == "table" and type(m.server) == "string" and type(m.token) == "string" and m.token ~= "" then
        out[#out + 1] = Pick.memosSource(m)
    end
    local im = plugin.store and plugin.store.immich
    if type(im) == "table" and type(im.key) == "string" and im.key ~= "" and type(im.server) == "string" then
        out[#out + 1] = Pick.immichSource(im)
    end
    return out
end

--- Where thumbnails and picked photos wait (thumbnails: thrown away when the picker closes).
function Pick.dir()
    local DataStorage = require("datastorage")
    local dir = DataStorage:getSettingsDir() .. "/gzreader-drawings"
    lfs.mkdir(dir)
    local thumbs = dir .. "/immich-thumbs"
    lfs.mkdir(thumbs)
    return dir, thumbs
end

-- -------------------------------------------------------------------- picking

--- How many thumbnails a screen shows: cols, rows (bigger cells on a small screen).
function Pick.grid(w, h)
    local cols = w >= 1000 and 4 or 3
    local cell = math.floor(w / cols)
    local rows = math.max(1, math.floor(h / cell))
    return cols, rows, cell
end

--- The picker. opts: title, on_pick(files) (see the top), on_cancel().
function Pick.show(plugin, opts)
    local Net = require("gzreader_net")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    local sources = Pick.sources(plugin)
    if #sources == 0 then
        return UIManager:show(InfoMessage:new{ text = _("Connect Immich first: in your Memos web app (Settings → Immich), or in GZreader (Settings → Immich)."), timeout = 5 })
    end
    Net.run(function() Pick.start(plugin, sources, opts) end, { reason = "immich photos" })
end

--- On Wi‑Fi: the first way in that answers, then its albums.
function Pick.start(plugin, sources, opts)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")
    local busy = InfoMessage:new{ text = _("Opening Immich…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local usable, why = {}, nil
    for _i, src in ipairs(sources) do
        local ok, err = src.connected()
        if ok then usable[#usable + 1] = src
        elseif src.kind == "memos" then why = why or (err and ("memos:" .. tostring(err)) or "memos:not set up") end
    end
    UIManager:close(busy)
    Log.info("immich pick: ways in", #usable, why and ("(" .. why .. ")") or "")
    if #usable == 0 then
        return UIManager:show(InfoMessage:new{ text = _("Immich isn't connected: set it up in your Memos web app (Settings → Immich) or in GZreader (Settings → Immich)."), timeout = 5 })
    end
    Pick.albums(plugin, usable, 1, opts)
end

--- The albums of way in `k` (All photos first; Switch when there are two ways).
function Pick.albums(plugin, usable, k, opts)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local _ = require("gettext")
    local T = require("ffi/util").template
    local src = usable[k]
    local list, err = src.albums()
    if not list then
        Log.warn("immich pick: albums:", tostring(err))
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't read your Immich albums (%1)."), tostring(err)), timeout = 4 })
    end
    local menu
    local items = {
        { text = _("All photos"), callback = function() Pick.grid_show(src, nil, _("All photos"), opts, menu) end },
    }
    for _i, a in ipairs(list) do
        items[#items + 1] = { text = a.name, mandatory = tostring(a.count),
            callback = function() Pick.grid_show(src, a.id, a.name, opts, menu) end }
    end
    if #usable > 1 then
        local other = usable[k % #usable + 1]
        table.insert(items, 1, { text = other.kind == "memos" and _("Use Memos' Immich connection") or _("Use GZreader's Immich connection"),
            callback = function() UIManager:close(menu); Pick.albums(plugin, usable, k % #usable + 1, opts) end })
    end
    menu = Menu:new{
        title = src.kind == "memos" and _("Photos from Immich (Memos' connection)") or _("Photos from Immich"),
        item_table = items, width = Screen:getWidth(), height = Screen:getHeight(), is_borderless = true, covers_fullscreen = true,
        close_callback = function() UIManager:close(menu); if opts.on_cancel then opts.on_cancel() end end,
    }
    menu.name = "gz_immich_albums"
    UIManager:show(menu)
    return menu
end

--- An album's photos as a grid of thumbnails to pick from.
function Pick.grid_show(src, album, title, opts, menu)
    local UIManager = require("ui/uimanager")
    local PickScreen = require("gzreader_immichgrid")
    local screen = PickScreen:new{ source = src, album = album, title = title, on_pick = function(files)
        if menu then UIManager:close(menu) end
        if opts.on_pick then opts.on_pick(files) end
    end }
    UIManager:show(screen)
    screen:load()
    return screen
end

--- Downloads the previews of `photos` (picked, in order) next to the
--- drawings waiting for Memos: the files for on_pick, or nil, err.
function Pick.fetchPreviews(src, photos)
    local dir = Pick.dir()
    local out = {}
    for _i, p in ipairs(photos) do
        local path = dir .. "/immich-" .. p.id .. ".jpg"
        local ok, err = src.preview(p.id, path)
        if not ok then return nil, err end
        -- its size: from the file's header (quick), else decoded once, else what Immich said
        local w, h = require("gzreader_sticky").imageSize(path)
        if not w then
            local okm, RenderImage = pcall(require, "ui/renderimage")
            if okm then
                local okr, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false)
                if okr and bb then w, h = bb:getWidth(), bb:getHeight(); bb:free() end
            end
        end
        w, h = w or p.w, h or p.h
        out[#out + 1] = { id = p.id, path = path, filename = Pick.fileName(p.filename, p.id), type = "image/jpeg", w = w, h = h }
    end
    return out
end

return Pick
