--[[--
Immich (https://immich.app): pictures from one of your albums for the sleep
screen and the Home wallpaper.

Sign-in: an API key (Immich → Account Settings → API Keys), sent as
"x-api-key". It's kept in GZreader's settings like the Memos token and never
written to the log. The key needs album.read, asset.read and asset.view (and
user.read to show whose it is; without it the name is left out).

GZreader keeps COUNT pictures from the album on the Kindle (Immich's
"preview" size, made to fit the screen and grey, as PNGs named after the
asset) in gzsleepmode.immichDir(), so the sleep screen has them without
Wi‑Fi. On Wi‑Fi (at most every REFRESH_EVERY seconds, or Get new pictures
now) half of them are swapped for others from the album, so they change over
time. Kindles without Wi‑Fi get them through the sync page
(gzreader_usbsync.lua Usb.takeImmich).

store = plugin.store.immich = { server, key, user, album = { id, name, count },
count (pictures kept), at (last refresh), error }.
G_reader_settings: gzreader_immich_album (the album's name, for the sleep
screen's tiles: there only while an album is chosen), gzreader_sleep_source
(gzsleepmode.lua).
]]

local JSON = require("gzreader_json")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local Immich = {
    COUNT = 20,               -- pictures kept on the Kindle (Settings: 10, 20, 50)
    COUNTS = { 10, 20, 50 },
    REFRESH_EVERY = 6 * 3600, -- on Wi‑Fi, at most this often
    PAGE = 250,               -- assets per search page
    MAX_LIST = 2000,          -- assets looked at in a big album
    MAX_BYTES = 20 * 1048576, -- one picture, at most
    -- the web app's pages (an address pasted from the browser ends at them)
    PAGES = { albums = true, photos = true, share = true, sharing = true, explore = true, people = true, places = true,
        ["user-settings"] = true, admin = true, auth = true, api = true, search = true, archive = true, favorites = true,
        map = true, trash = true, memory = true, folders = true, tags = true, utilities = true, partners = true, locked = true },
}
Immich.__index = Immich

local UUID = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"

--- `store` is plugin.store.immich.
function Immich:new(store)
    return setmetatable({ store = store or {} }, self)
end

--- The address typed or pasted (the web page's address too, an album's
--- included): the server's address, and the album's id when there was one.
function Immich.normalizeServer(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    if not s:match("^https?://") then s = "https://" .. s end
    local album = s:match("/albums/(" .. UUID .. ")")
    s = s:gsub("[?#].*$", "")
    local base, path = s:match("^(https?://[^/]+)(.*)$")
    if not base then return nil end
    -- (an album's, a photo's or a page's address: the part before Immich's pages)
    local kept = {}
    for seg in path:gmatch("[^/]+") do
        if Immich.PAGES[seg] then break end
        kept[#kept + 1] = seg
    end
    return base .. (#kept > 0 and ("/" .. table.concat(kept, "/")) or ""), album
end

function Immich:isConnected()
    return type(self.store.server) == "string" and type(self.store.key) == "string" and self.store.key ~= ""
end

--- One request to /api. Returns code, data (decoded JSON), err
--- ("unreachable", "unauthorized", "forbidden", "http_<code>").
function Immich:request(method, path, body, opts)
    opts = opts or {}
    if not self:isConnected() then return nil, nil, "not_connected" end
    local Api = require("gzreader_api")
    local code, data = Api.rawRequest(method, self.store.server .. "/api" .. path, {
        headers = { ["x-api-key"] = self.store.key, ["Accept"] = opts.accept or "application/json" },
        body = body,
        timeouts = opts.timeouts or { 10, 30 },
        sink = opts.sink,
    })
    if type(code) ~= "number" then return nil, nil, "unreachable" end
    if code == 401 then return code, data, "unauthorized" end
    if code == 403 then return code, data, "forbidden" end
    if code >= 400 then return code, data, "http_" .. code end
    return code, data
end

--- Who the key is (name), or nil, err. "forbidden": a key without user.read
--- (it may still read albums).
function Immich:me()
    local code, data, err = self:request("GET", "/users/me")
    if err then return nil, err end
    if code ~= 200 or type(data) ~= "table" then return nil, "not_immich" end
    return { name = data.name ~= "" and data.name or data.email, email = data.email }
end

--- The albums the key can read (yours and the ones shared with you):
--- { { id, name, count } } by name, or nil, err.
function Immich:albums()
    local seen, list = {}, {}
    for _i, q in ipairs({ "", "?shared=true" }) do
        local code, data, err = self:request("GET", "/albums" .. q)
        if err then
            if q == "" then return nil, err end
        elseif code == 200 and type(data) == "table" then
            for _j, a in ipairs(data) do
                if type(a) == "table" and type(a.id) == "string" and not seen[a.id] then
                    seen[a.id] = true
                    list[#list + 1] = { id = a.id, name = tostring(a.albumName or "?"), count = tonumber(a.assetCount) or 0 }
                end
            end
        elseif q == "" then
            return nil, "not_immich"
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

--- The album's pictures (asset ids; photos only, no videos), up to MAX_LIST,
--- or nil, err. Immich's search (1.1xx to 3.x); an album's own list on
--- servers whose search doesn't know albums.
function Immich:albumPictures(album_id)
    local ids, page = {}, 1
    while #ids < Immich.MAX_LIST do
        local code, data, err = self:request("POST", "/search/metadata",
            { albumIds = JSON.list({ album_id }), type = "IMAGE", size = Immich.PAGE, page = page })
        if err == "unreachable" or err == "unauthorized" then return nil, err end
        local assets = code == 200 and type(data) == "table" and type(data.assets) == "table" and data.assets
        if not assets then
            if page > 1 then break end
            return self:albumPicturesOld(album_id, err)
        end
        for _i, a in ipairs(type(assets.items) == "table" and assets.items or {}) do
            if type(a) == "table" and type(a.id) == "string" and (a.type == nil or a.type == "IMAGE") and not a.isTrashed then
                ids[#ids + 1] = a.id
            end
        end
        local more = assets.nextPage
        if more == nil or more == false or #(assets.items or {}) < Immich.PAGE then break end
        page = tonumber(more) or (page + 1)
    end
    return ids
end

function Immich:albumPicturesOld(album_id, why)
    local code, data, err = self:request("GET", "/albums/" .. album_id)
    if err then return nil, err end
    if code ~= 200 or type(data) ~= "table" then return nil, why or "not_immich" end
    if type(data.assets) ~= "table" then return nil, why or "no_list" end
    local ids = {}
    for _i, a in ipairs(data.assets) do
        if type(a) == "table" and type(a.id) == "string" and (a.type == nil or a.type == "IMAGE") and not a.isTrashed then
            ids[#ids + 1] = a.id
            if #ids >= Immich.MAX_LIST then break end
        end
    end
    return ids
end

--- An asset's preview (a JPEG of about 1440 px, Immich's default) to `path`.
--- Returns true and its type, or false, err.
function Immich:downloadPreview(asset_id, path)
    local part = path .. ".part"
    local fh, ferr = io.open(part, "wb")
    if not fh then return false, ferr end
    local headers = {}
    local Api = require("gzreader_api")
    local code, _, resp = Api.rawRequest("GET", self.store.server .. "/api/assets/" .. asset_id .. "/thumbnail?size=preview", {
        headers = { ["x-api-key"] = self.store.key, ["Accept"] = "image/*" },
        sink = ltn12.sink.file(fh),
        timeouts = { 10, 60 },
    })
    headers = type(resp) == "table" and resp or headers
    local ctype = tostring(headers["content-type"] or headers["Content-Type"] or "")
    local size = lfs.attributes(part, "size") or 0
    if code == 200 and size > 0 and size <= Immich.MAX_BYTES and ctype:find("image", 1, true) then
        os.rename(part, path)
        return true, ctype
    end
    os.remove(part)
    if type(code) ~= "number" then return false, "unreachable" end
    return false, "http_" .. tostring(code)
end

---------------------------------------------------------------- the pictures

local function shuffle(t, rand)
    rand = rand or math.random
    for i = #t, 2, -1 do
        local j = rand(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- Which pictures to keep after a refresh: `album` (ids), `have` (ids on the
--- Kindle), `count`. Pictures no longer in the album go; with more in the
--- album than `count`, about half of those kept are swapped for new ones (so
--- they change over time) and the rest filled with new ones. Returns keep
--- (ids already there), get (ids to download), drop (ids to remove).
function Immich.plan(album, have, count, rand)
    local in_album, on_kindle = {}, {}
    for _i, id in ipairs(album or {}) do in_album[id] = true end
    local keep, drop = {}, {}
    for _i, id in ipairs(have or {}) do
        if in_album[id] and not on_kindle[id] then keep[#keep + 1] = id else drop[#drop + 1] = id end
        on_kindle[id] = true
    end
    shuffle(keep, rand)
    local new = {}
    for _i, id in ipairs(album or {}) do if not on_kindle[id] then new[#new + 1] = id end end
    shuffle(new, rand)
    -- (swap half of them when there are new ones to show instead)
    local keep_n = math.min(#keep, count)
    if #new > 0 then keep_n = math.min(keep_n, math.max(count - #new, math.ceil(count / 2))) end
    for i = #keep, keep_n + 1, -1 do drop[#drop + 1] = table.remove(keep, i) end
    local get = {}
    for i = 1, math.min(#new, count - #keep) do get[#get + 1] = new[i] end
    return keep, get, drop
end

--- The ids of the pictures on the Kindle (their files, newest first).
function Immich.have(dir)
    dir = dir or require("gzsleepmode").immichDir()
    local list = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return list end
    for name in lfs.dir(dir) do
        local id = name:match("^(" .. UUID .. ")%.%a+$")
        if id then list[#list + 1] = { id = id, at = lfs.attributes(dir .. "/" .. name, "modification") or 0 } end
    end
    table.sort(list, function(a, b) return a.at > b.at end)
    for i, x in ipairs(list) do list[i] = x.id end
    return list
end

--- The file of picture `id` in `dir` (whatever its extension), or nil.
function Immich.fileOf(dir, id)
    for _i, ext in ipairs({ "png", "jpg", "jpeg", "webp" }) do
        local p = dir .. "/" .. id .. "." .. ext
        if lfs.attributes(p, "mode") == "file" then return p end
    end
end

--- The picture at `src` made to fit the screen (w × h; proportions kept, never
--- bigger) and grey, as a PNG at `dest`. False when it can't be read (the
--- caller keeps the original then).
function Immich.fit(src, dest, w, h)
    local ok, err = pcall(function()
        local RenderImage = require("ui/renderimage")
        local Blitbuffer = require("ffi/blitbuffer")
        local bb = RenderImage:renderImageFile(src, false)
        if not bb then error("can't read it") end
        local iw, ih = bb:getWidth(), bb:getHeight()
        local k = math.min(w / iw, h / ih, 1)
        local tw, th = math.max(1, math.floor(iw * k + 0.5)), math.max(1, math.floor(ih * k + 0.5))
        bb = RenderImage:scaleBlitBuffer(bb, tw, th, true)
        local grey = Blitbuffer.new(tw, th, Blitbuffer.TYPE_BB8)
        grey:blitFrom(bb, 0, 0, 0, 0, tw, th)
        bb:free()
        local tmp = dest .. ".part"
        grey:writePNG(tmp)
        grey:free()
        if (lfs.attributes(tmp, "size") or 0) == 0 then os.remove(tmp); error("nothing written") end
        os.rename(tmp, dest)
    end)
    return ok, not ok and tostring(err) or nil
end

--- In the background process: the album's pictures on the Kindle brought up
--- to date. opts = { dir, album, count, w, h }. Returns { got, dropped,
--- total, failed, err }.
function Immich:refreshPictures(opts)
    local dir = opts.dir
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local album, err = self:albumPictures(opts.album)
    if not album then return { err = err } end
    local keep, get, drop = Immich.plan(album, Immich.have(dir), opts.count or Immich.COUNT)
    local got, failed = 0, 0
    for _i, id in ipairs(get) do
        local raw = dir .. "/." .. id .. ".download"
        local ok, what = self:downloadPreview(id, raw) -- (its type, or why not)
        if ok then
            local fitted = opts.w and opts.h and Immich.fit(raw, dir .. "/" .. id .. ".png", opts.w, opts.h)
            if fitted then
                os.remove(raw)
            else
                -- (the sleep screen still shows it, as it came)
                local ext = what:find("png", 1, true) and "png" or what:find("webp", 1, true) and "webp" or "jpg"
                os.rename(raw, dir .. "/" .. id .. "." .. ext)
            end
            got = got + 1
        else
            failed = failed + 1
            if what == "unreachable" then break end
        end
    end
    for _i, id in ipairs(drop) do
        local f = Immich.fileOf(dir, id)
        while f do os.remove(f); f = Immich.fileOf(dir, id) end
    end
    -- (a picture fitted with an older screen size stays: it's still shown whole)
    return { got = got, dropped = #drop, total = #album, failed = failed, kept = #keep }
end

---------------------------------------------------------------- on the Kindle

local function settings() return G_reader_settings end

function Immich.client(plugin)
    plugin.store.immich = plugin.store.immich or {}
    return Immich:new(plugin.store.immich)
end

function Immich.count(plugin)
    local n = tonumber((plugin.store.immich or {}).count)
    return n and n > 0 and n or Immich.COUNT
end

--- The album chosen (and the name the sleep screen's tiles show).
function Immich.setAlbum(plugin, album)
    local st = plugin.store.immich or {}
    plugin.store.immich = st
    st.album = album and { id = album.id, name = album.name, count = album.count } or nil
    st.at = nil
    if st.album then
        settings():saveSetting("gzreader_immich_album", st.album.name or "Immich")
    else
        settings():delSetting("gzreader_immich_album")
    end
    plugin:save()
end

--- Check an address and API key, and keep them. Returns ok, err (to show),
--- albums (the list, or nil).
function Immich.connect(plugin, server_input, key)
    local _T = require("ffi/util").template
    local _ = require("gettext")
    local Log = require("gzreader_log")
    local server, album_id = Immich.normalizeServer(server_input)
    key = (key or ""):gsub("%s", "")
    if not server then return false, _("That address doesn't look right.") end
    if key == "" then return false, _("Paste an API key from Immich (Account Settings → API Keys).") end
    local trial = Immich:new({ server = server, key = key })
    local albums, err = trial:albums()
    if not albums and err == "unreachable" and not server_input:match("^%s*https?://") then
        -- no https:// typed and no HTTPS there: an Immich on the home network (http)
        local plain = server:gsub("^https://", "http://")
        local t2 = Immich:new({ server = plain, key = key })
        local a2, e2 = t2:albums()
        if a2 or e2 ~= "unreachable" then trial, albums, err, server = t2, a2, e2, plain end
    end
    Log.info("immich: connecting to", server, albums and ("ok, " .. #albums .. " albums") or ("failed: " .. tostring(err)))
    if not albums then
        if err == "unauthorized" then return false, _("Immich didn't accept that API key.") end
        if err == "forbidden" then return false, _("That API key can't read albums: give it album.read, asset.read and asset.view (or all permissions).") end
        if err == "unreachable" then return false, _("Couldn't reach Immich at that address.") end
        return false, _T(_("That doesn't look like an Immich server (%1)."), tostring(err))
    end
    local me = trial:me()
    local old = plugin.store.immich or {}
    local st = { server = server, key = key, user = me and me.name or nil, count = old.count, albums = albums }
    -- the same album as before when it's still there, or the one in the address pasted
    local want = album_id or (old.server == server and old.album and old.album.id)
    for _i, a in ipairs(albums) do if a.id == want then st.album = { id = a.id, name = a.name, count = a.count } end end
    plugin.store.immich = st
    if st.album then settings():saveSetting("gzreader_immich_album", st.album.name) else settings():delSetting("gzreader_immich_album") end
    plugin:save()
    return true, nil, albums
end

--- Forget the connection and the pictures (the sleep screen goes back to the
--- screensavers folder, the wallpaper to what it was).
function Immich.disconnect(plugin)
    local Log = require("gzreader_log")
    plugin.store.immich = {}
    plugin:save()
    settings():delSetting("gzreader_immich_album")
    if settings():readSetting("gzreader_sleep_source") == "immich" then settings():delSetting("gzreader_sleep_source") end
    pcall(function() require("common/gz_immich_wallpaper").turnOff() end)
    local dir = require("gzsleepmode").immichDir()
    if lfs.attributes(dir, "mode") == "directory" then
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then os.remove(dir .. "/" .. name) end
        end
        lfs.rmdir(dir)
    end
    Log.info("immich: disconnected")
end

--- Whether the album's pictures are used (the sleep screen or the wallpaper).
function Immich.inUse()
    if settings():readSetting("gzreader_sleep_source") == "immich" then return true end
    local ok, on = pcall(function() return require("common/gz_immich_wallpaper").isOn() end)
    return ok and on == true
end

--- A picture on the Kindle, at random (for the wallpaper), or nil.
function Immich.randomPicture(not_this)
    local dir = require("gzsleepmode").immichDir()
    local ids = Immich.have(dir)
    local files = {}
    for _i, id in ipairs(ids) do
        local f = Immich.fileOf(dir, id)
        if f and f ~= not_this then files[#files + 1] = f end
    end
    if #files == 0 then return Immich.fileOf(dir, ids[1] or "") end
    return files[math.random(#files)]
end

--- After new pictures came: the wallpaper gets another one.
function Immich.changed()
    pcall(function()
        local W = require("common/gz_immich_wallpaper")
        if W.isOn() then W.changed(Immich.randomPicture(W.source())) end
    end)
end

--- The pictures brought up to date in the background (Wi‑Fi). opts.force:
--- now, whenever the last time was; on_done(ok, res_or_err).
function Immich.refresh(plugin, opts, on_done)
    opts = opts or {}
    local Log = require("gzreader_log")
    local st = plugin.store.immich or {}
    local client = Immich:new(st)
    local function finish(ok, x) if on_done then on_done(ok, x) end end
    if require("gzreader_net").usb then return finish(false, "usb") end
    if not client:isConnected() or not st.album then return finish(false, "not_connected") end
    if not opts.force and os.time() - (tonumber(st.at) or 0) < Immich.REFRESH_EVERY then return finish(false, "recent") end
    if Immich.refreshing then return finish(false, "busy") end
    Immich.refreshing = true
    local Screen = require("device").screen
    local job = { dir = require("gzsleepmode").immichDir(), album = st.album.id, count = Immich.count(plugin),
        w = Screen:getWidth(), h = Screen:getHeight() }
    if job.w > job.h then job.w, job.h = job.h, job.w end -- (portrait, as the sleep screen is)
    require("gzreader_async").run(client, function(c) return c:refreshPictures(job) end, function(res, err)
        Immich.refreshing = false
        if type(res) ~= "table" or res.err then
            st.error = type(res) == "table" and res.err or tostring(err)
            Log.warn("immich: pictures not brought up to date:", st.error)
            plugin:save()
            return finish(false, st.error)
        end
        st.at, st.error = os.time(), nil
        if st.album then st.album.count = res.total end
        plugin:save()
        Log.info("immich: pictures:", res.got, "new,", res.dropped, "removed,", res.kept, "kept of", res.total, res.failed > 0 and ("(" .. res.failed .. " failed)") or "")
        if res.got > 0 or res.dropped > 0 or opts.force then Immich.changed() end
        finish(true, res)
    end, "immich: pictures", { timeout = 300 })
end

--- On Wi‑Fi: the pictures, when they're used and not brought for a while.
function Immich.onNetworkConnected(plugin)
    if not Immich.inUse() then return end
    Immich.refresh(plugin)
end

return Immich
