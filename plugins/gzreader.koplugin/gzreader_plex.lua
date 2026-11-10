--[[--
Plex (https://plex.tv) client for the Music tab: sign-in, finding your Plex
Media Server, its music libraries, and the tracks' audio.

Sign-in, two ways (both "PINs" in Plex's API, POST plex.tv/api/v2/pins):
- on the Kindle: a 4-character code to enter at plex.tv/link on any phone or
  computer; the Kindle asks plex.tv every few seconds whether it was;
- on the phone page: "Sign in with Plex" sends the phone to Plex's own sign-in
  page (app.plex.tv/auth, a "strong" PIN), which sends it back to the phone
  page when done (forwardUrl).
Either way the Kindle gets a Plex token, kept in GZreader's settings like the
other sign-ins, never written to the log (it travels in the X-Plex-Token
header, not in addresses). Only the account's user name is kept with it.

The server: plex.tv lists the servers the account can use (resources) with
their addresses: on the same Wi-Fi first, then over the internet, then Plex's
relay. The first that answers is kept (and tried first next time).

Audio for the Kindle (it plays MP3 and AAC): MP3 files and AAC in M4A are
downloaded as they are (M4A then converted to ADTS like audiobooks); FLAC,
ALAC, Ogg, Opus… are converted to MP3 by the Plex server (its transcoder,
HLS with MP3 in MPEG-TS segments, which GZreader joins into an MP3 file).
]]

local Log = require("gzreader_log")
local ltn12 = require("ltn12")
local lfs = require("libs/libkoreader-lfs")

local Plex = {
    TV = "https://plex.tv",
    AUTH_APP = "https://app.plex.tv/auth",
    LINK_PAGE = "https://plex.tv/link",
    PRODUCT = "GZreader",
    PAGE = 100,
}
Plex.__index = Plex

local function Api() return require("gzreader_api") end
local str = function(v) return Api().str(v) end

-- (RFC 3986: letters, digits and - . _ ~ as they are)
local function escape(s)
    return (tostring(s):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function query(params)
    local t = {}
    for k, v in pairs(params or {}) do
        if v ~= nil and v ~= "" then t[#t + 1] = escape(k) .. "=" .. escape(v) end
    end
    table.sort(t)
    return #t > 0 and ("?" .. table.concat(t, "&")) or ""
end
Plex.query = query

--- `store` is plugin.store.plex: client_id, token, username, server = {
--- name, id, uri, token, uris }.
function Plex:new(store)
    return setmetatable({ store = store }, self)
end

function Plex:isSignedIn() return self.store.token ~= nil end
function Plex:isConnected() return self.store.token ~= nil and type(self.store.server) == "table" and self.store.server.uri ~= nil end

--- This Kindle's id for Plex (made once; Plex lists it under Authorized Devices).
function Plex:clientId()
    if type(self.store.client_id) ~= "string" then
        self.store.client_id = "gzreader-" .. require("gzreader_pairserver").randomToken(8)
        self.store.changed = true
    end
    return self.store.client_id
end

function Plex:headers(token)
    local version = "dev"
    pcall(function() version = require("gzreader_update").currentVersion() or version end)
    local name = "GZreader"
    pcall(function() name = "GZreader (" .. require("gzreader_copy").deviceName(self.plugin) .. ")" end)
    local h = {
        ["X-Plex-Product"] = Plex.PRODUCT,
        ["X-Plex-Version"] = tostring(version),
        ["X-Plex-Client-Identifier"] = self:clientId(),
        ["X-Plex-Platform"] = "Kindle",
        ["X-Plex-Device"] = "Kindle",
        ["X-Plex-Device-Name"] = name,
        ["X-Plex-Model"] = tostring(require("device").model or "Kindle"),
        ["Accept"] = "application/json",
    }
    if token then h["X-Plex-Token"] = token end
    return h
end

--- One request. Returns code, data (decoded JSON, or text with opts.want_raw), err.
function Plex:request(method, url, opts)
    opts = opts or {}
    local headers = self:headers(opts.token)
    for k, v in pairs(opts.headers or {}) do headers[k] = v end
    local code, data = Api().rawRequest(method, url, {
        headers = headers, body = opts.body, raw_body = opts.raw_body, sink = opts.sink,
        timeouts = opts.timeouts or { 10, 30 }, want_raw = opts.want_raw,
        log_url = opts.log_url or (url:gsub("%?.*$", "")),
    })
    if not code then return nil, nil, "unreachable" end
    if code == 401 then return code, data, "unauthorized" end
    if code >= 400 then return code, data, "http_" .. code end
    return code, data
end

---------------------------------------------------------------- sign-in

--- A new PIN: { id, code, expires } (strong: for Plex's sign-in page; not:
--- a 4-character code for plex.tv/link), or nil, err.
function Plex:newPin(strong)
    local _, data, err = self:request("POST", Plex.TV .. "/api/v2/pins" .. (strong and "?strong=true" or ""),
        { raw_body = "", headers = { ["Content-Type"] = "application/x-www-form-urlencoded" } })
    if err then return nil, err end
    if type(data) ~= "table" or not data.id or not str(data.code) then return nil, "bad answer" end
    return { id = tostring(data.id), code = str(data.code), expires = tonumber(data.expiresIn) or 900 }
end

--- Has the PIN been signed in with? token, or nil (not yet) / nil, err.
function Plex:checkPin(pin)
    local _, data, err = self:request("GET", Plex.TV .. "/api/v2/pins/" .. escape(pin.id) .. query({ code = pin.code }))
    if err then return nil, err end
    local token = type(data) == "table" and str(data.authToken)
    if token and token ~= "" then return token end
    return nil
end

--- Where to send the phone for Plex's own sign-in (then back to forward_url).
function Plex:authUrl(pin, forward_url)
    local parts = {
        "clientID=" .. escape(self:clientId()),
        "code=" .. escape(pin.code),
        "context%5Bdevice%5D%5Bproduct%5D=" .. escape(Plex.PRODUCT),
    }
    if forward_url then parts[#parts + 1] = "forwardUrl=" .. escape(forward_url) end
    return Plex.AUTH_APP .. "#?" .. table.concat(parts, "&")
end

--- The account the token belongs to: { username } or nil, err.
function Plex:user(token)
    local _, data, err = self:request("GET", Plex.TV .. "/api/v2/user", { token = token })
    if err then return nil, err end
    if type(data) ~= "table" then return nil, "bad answer" end
    return { username = str(data.username) or str(data.title) or "?" }
end

--- The Plex Media Servers this account can use: { { name, id, token,
--- connections = { { uri, local, relay } } } }, or nil, err.
function Plex:servers(token)
    local _, data, err = self:request("GET", Plex.TV .. "/api/v2/resources" .. query({ includeHttps = 1, includeRelay = 1 }),
        { token = token })
    if err then return nil, err end
    local out = {}
    for _i, r in ipairs(type(data) == "table" and data or {}) do
        if type(r) == "table" and tostring(r.provides or ""):find("server", 1, true) then
            local conns = {}
            for _j, c in ipairs(type(r.connections) == "table" and r.connections or {}) do
                if type(c) == "table" and str(c.uri) then
                    conns[#conns + 1] = { uri = str(c.uri), ["local"] = c["local"] == true, relay = c.relay == true,
                        http = str(c.protocol) == "http" }
                    -- (on the Wi-Fi a server also answers plain http at its address)
                    if c["local"] == true and str(c.address) and c.port then
                        conns[#conns + 1] = { uri = "http://" .. str(c.address) .. ":" .. tostring(c.port), ["local"] = true, http = true }
                    end
                end
            end
            -- this Wi-Fi first, then the internet, then Plex's relay (slow)
            local function rank(c) return (c["local"] and 0 or 2) + (c.relay and 4 or 0) + (c.http and 1 or 0) end
            table.sort(conns, function(a, b) return rank(a) < rank(b) end)
            out[#out + 1] = { name = str(r.name) or "Plex", id = str(r.clientIdentifier), token = str(r.accessToken) or token,
                owned = r.owned == true, connections = conns }
        end
    end
    return out
end

--- The first of a server's addresses that answers: uri, or nil, err.
function Plex:reach(server, prefer)
    local tried = {}
    local list = {}
    if prefer then list[1] = { uri = prefer } end
    for _i, c in ipairs(server.connections or {}) do list[#list + 1] = c end
    for _i, c in ipairs(list) do
        if not tried[c.uri] then
            tried[c.uri] = true
            local code = self:request("GET", c.uri .. "/identity", { token = server.token, timeouts = { 4, 8 } })
            if code == 200 then return c.uri end
        end
    end
    return nil, "unreachable"
end

--- Sign in with `token`: the account, a server (the one with music, the
--- owned one first), its address. Saves into the store. true, or nil, err.
function Plex:connect(token, server_id)
    local user, err = self:user(token)
    if not user then return nil, err == "unauthorized" and "That Plex sign-in didn't work." or err end
    local servers, serr = self:servers(token)
    if not servers then return nil, serr end
    if #servers == 0 then return nil, "no_server" end
    table.sort(servers, function(a, b) return (a.owned and 0 or 1) < (b.owned and 0 or 1) end)
    local chosen
    for _i, s in ipairs(servers) do
        if not server_id or s.id == server_id then
            local uri = self:reach(s)
            if uri then chosen = s; chosen.uri = uri; break end
        end
    end
    if not chosen then return nil, "server_unreachable" end
    self.store.token = token
    self.store.username = user.username
    local uris = {}
    for _i, c in ipairs(chosen.connections) do uris[#uris + 1] = c.uri end
    self.store.server = { name = chosen.name, id = chosen.id, uri = chosen.uri, token = chosen.token, uris = uris }
    self.store.servers = {}
    for _i, s in ipairs(servers) do self.store.servers[#self.store.servers + 1] = { name = s.name, id = s.id } end
    Log.info("plex: signed in as", user.username, "server", chosen.name)
    return true
end

function Plex:signOut()
    self.store.token, self.store.username, self.store.server, self.store.servers = nil, nil, nil, nil
end

---------------------------------------------------------------- the server

--- GET on the server; tries its other addresses when the kept one stops
--- answering (a laptop server that moved, the Kindle away from home).
function Plex:get(path, params, opts)
    opts = opts or {}
    local s = self.store.server
    if not s then return nil, nil, "not_connected" end
    local code, data, err = self:request("GET", s.uri .. path .. query(params), {
        token = s.token, sink = opts.sink, timeouts = opts.timeouts, want_raw = opts.want_raw,
        headers = opts.headers })
    if err == "unreachable" and not opts.sink then
        local uri = self:reach({ token = s.token, connections = (function()
            local t = {}
            for _i, u in ipairs(s.uris or {}) do if u ~= s.uri then t[#t + 1] = { uri = u } end end
            return t
        end)() })
        if uri then
            Log.info("plex: the server now answers at another address")
            s.uri = uri
            self.store.changed = true
            code, data, err = self:request("GET", s.uri .. path .. query(params), { token = s.token, timeouts = opts.timeouts,
                want_raw = opts.want_raw, headers = opts.headers })
        end
    end
    return code, data, err
end

local function container(data)
    return type(data) == "table" and type(data.MediaContainer) == "table" and data.MediaContainer or {}
end

--- The music libraries: { { key, title } }.
function Plex:musicSections()
    local _, data, err = self:get("/library/sections")
    if err then return nil, err end
    local out = {}
    for _i, d in ipairs(container(data).Directory or {}) do
        if type(d) == "table" and str(d.type) == "artist" then out[#out + 1] = { key = str(d.key), title = str(d.title) or "Music" } end
    end
    return out
end

--- The music library to browse: the one chosen in Settings → Connections →
--- Plex → Music library (store.music_section = { server, key, title }) while
--- this server still has it, else the server's first. Returns it ({ key,
--- title }) and every music library, or nil, err ("no_music": none).
function Plex:musicSection()
    local sections, err = self:musicSections()
    if not sections then return nil, err end
    if #sections == 0 then return nil, "no_music" end
    return Plex.pickSection(sections, self.store.music_section, self.store.server), sections
end

--- Of `sections`, the one `want` names (kept for `server`), else the first.
--- Pure (run_tests.lua).
function Plex.pickSection(sections, want, server)
    if type(want) == "table" and want.key and want.server == (type(server) == "table" and server.id or nil) then
        for _i, s in ipairs(sections) do
            if s.key == tostring(want.key) then return s end
        end
    end
    return sections[1]
end

--- A track, album, artist or playlist as GZreader keeps it.
function Plex.item(m)
    if type(m) ~= "table" then return nil end
    local t = {
        key = str(m.ratingKey), type = str(m.type), title = str(m.title) or "?",
        artist = str(m.grandparentTitle) or str(m.parentTitle), album = str(m.parentTitle),
        year = tonumber(m.year), index = tonumber(m.index), duration = tonumber(m.duration),
        thumb = str(m.thumb) or str(m.composite) or str(m.parentThumb), count = tonumber(m.leafCount) or tonumber(m.childCount),
        album_key = str(m.parentRatingKey),
        added = tonumber(m.addedAt), viewed = tonumber(m.lastViewedAt),
    }
    if t.type == "album" then t.artist = str(m.parentTitle) end
    if t.type == "artist" then t.artist = nil end
    local media = type(m.Media) == "table" and m.Media[1]
    local part = media and type(media.Part) == "table" and media.Part[1]
    if part then
        t.part = { key = str(part.key), container = str(part.container) or str(media.container),
            size = tonumber(part.size), codec = str(media.audioCodec), bitrate = tonumber(media.bitrate) }
    end
    return t
end

local function items(data)
    local out = {}
    local mc = container(data)
    for _i, m in ipairs(mc.Metadata or mc.Directory or {}) do
        local it = Plex.item(m)
        if it and it.key then out[#out + 1] = it end
    end
    return out, tonumber(mc.totalSize) or tonumber(mc.size)
end

local function paged(start)
    return { ["X-Plex-Container-Start"] = tostring(start or 0), ["X-Plex-Container-Size"] = tostring(Plex.PAGE) }
end

--- Artists (type 8) or albums (9) of a music library, A–Z, a page at a time:
--- list, total, or nil, err.
--- The Catalog's Music shelves: albums Recently added (`by` "added") or
--- Recently played ("played": the ones played at all, from any player), at
--- most `n`: list, or nil, err.
function Plex:recentAlbums(section, by, n)
    local _, data, err = self:get("/library/sections/" .. escape(section) .. "/all",
        { type = 9, sort = by == "played" and "lastViewedAt:desc" or "addedAt:desc" },
        { headers = { ["X-Plex-Container-Start"] = "0", ["X-Plex-Container-Size"] = tostring(n or 20) } })
    if err then return nil, err end
    local list = items(data)
    if by == "played" then
        local out = {}
        for _i, it in ipairs(list) do if (it.viewed or 0) > 0 then out[#out + 1] = it end end
        list = out
    end
    return list
end

function Plex:list(section, kind, start)
    local _, data, err = self:get("/library/sections/" .. escape(section) .. "/all",
        { type = kind == "albums" and 9 or 8, sort = "titleSort:asc" }, { headers = paged(start) })
    if err then return nil, err end
    return items(data)
end

--- An artist's albums, an album's tracks.
function Plex:children(key)
    local _, data, err = self:get("/library/metadata/" .. escape(key) .. "/children")
    if err then return nil, err end
    return items(data)
end

--- Audio playlists (of one library: `section`, when the server has several).
function Plex:playlists(section)
    local _, data, err = self:get("/playlists", { playlistType = "audio", sectionID = section })
    if err then return nil, err end
    return items(data)
end

function Plex:playlistItems(key, start)
    local _, data, err = self:get("/playlists/" .. escape(key) .. "/items", nil, { headers = paged(start) })
    if err then return nil, err end
    return items(data)
end

--- Search the music: { artists, albums, tracks }.
function Plex:search(q, section)
    local _, data, err = self:get("/hubs/search", { query = q, sectionId = section, limit = 20 })
    if err then return nil, err end
    local out = { artists = {}, albums = {}, tracks = {} }
    for _i, hub in ipairs(container(data).Hub or {}) do
        local kind = type(hub) == "table" and str(hub.type)
        local dest = kind == "artist" and out.artists or kind == "album" and out.albums or kind == "track" and out.tracks
        if dest then
            for _j, m in ipairs(hub.Metadata or {}) do
                local it = Plex.item(m)
                if it and it.key then dest[#dest + 1] = it end
            end
        end
    end
    return out
end

---------------------------------------------------------------- audio

--- How a track's audio comes to the Kindle: "file" (as it is: MP3), "m4a"
--- (as it is, then converted to ADTS AAC on the Kindle) or "transcode" (the
--- server makes MP3).
--- shrink_to (kbps; default Plex.shrink_to, from Settings: "Make bigger MP3
--- and AAC smaller"): an MP3 or AAC track well above it (15 % more, so a
--- VBR file at about that quality stays as it is) is made into MP3 at that
--- quality too, to save room.
Plex.SHRINK_MARGIN = 1.15
function Plex.how(track, shrink_to)
    local p = track.part or {}
    local c, codec = tostring(p.container or ""):lower(), tostring(p.codec or ""):lower()
    local how, ext
    if c == "mp3" or (codec == "mp3" and c == "") then how, ext = "file", "mp3"
    elseif (c == "mp4" or c == "m4a") and (codec == "aac" or codec == "") then how, ext = "m4a", "m4a"
    elseif c == "aac" or c == "adts" then how, ext = "file", "aac"
    else return "transcode", "mp3" end
    shrink_to = shrink_to or Plex.shrink_to
    local kbps = tonumber(p.bitrate)
    if shrink_to and kbps and kbps > shrink_to * Plex.SHRINK_MARGIN then return "transcode", "mp3" end
    return how, ext
end

--- The Plex settings' quality: { bitrate = kbps, shrink = true/false }.
function Plex.quality(store)
    local s = type(store) == "table" and store.plex or {}
    return { bitrate = tonumber(s and s.bitrate) or 192, shrink = (s and s.shrink) == true }
end

local function download(self, url, dest, opts)
    local part = dest .. ".part"
    local fh = io.open(part, "wb")
    if not fh then return nil, "can't write" end
    local s = self.store.server
    local code, _, err = self:request("GET", url, { token = s.token, sink = ltn12.sink.file(fh),
        timeouts = (opts and opts.timeouts) or { 15, 600 } })
    if code == 200 and (lfs.attributes(part, "size") or 0) > 0 then
        os.rename(part, dest)
        return true
    end
    os.remove(part)
    return nil, err or ("http_" .. tostring(code))
end

--- MPEG-TS → the audio elementary stream (MP3 or ADTS frames), appended to fh.
--- Returns the bytes written.
function Plex.demuxTs(data, fh, state)
    state = state or {}
    local n, written = #data, 0
    local i = 1
    -- (a segment may start off a packet boundary: find the 0x47 sync)
    while i <= n and data:byte(i) ~= 0x47 do i = i + 1 end
    while i + 187 <= n do
        if data:byte(i) ~= 0x47 then break end
        local b1, b2, b3 = data:byte(i + 1, i + 3)
        local pusi = bit.band(b1, 0x40) ~= 0
        local pid = bit.bor(bit.lshift(bit.band(b1, 0x1F), 8), b2)
        local afc = bit.band(bit.rshift(b3, 4), 3)
        local p = i + 4
        if afc == 2 or afc == 3 then p = p + 1 + data:byte(p) end
        local payload = (afc == 1 or afc == 3) and p <= i + 187 and data:sub(p, i + 187) or ""
        if pid == 0 and pusi and #payload > 12 then
            -- PAT: the PMT's PID
            local off = 1 + payload:byte(1)
            local sec = payload:sub(off + 1)
            local prog_pid = bit.bor(bit.lshift(bit.band(sec:byte(11) or 0, 0x1F), 8), sec:byte(12) or 0)
            state.pmt = prog_pid
        elseif state.pmt and pid == state.pmt and pusi and #payload > 16 then
            -- PMT: the first audio stream (MP3 0x03/0x04, AAC 0x0F)
            local off = 1 + payload:byte(1)
            local sec = payload:sub(off + 1)
            local slen = bit.bor(bit.lshift(bit.band(sec:byte(2), 0x0F), 8), sec:byte(3))
            local pinfo = bit.bor(bit.lshift(bit.band(sec:byte(11), 0x0F), 8), sec:byte(12))
            local j, stop = 13 + pinfo, 3 + slen - 4
            while j + 4 <= stop do
                local st = sec:byte(j)
                local epid = bit.bor(bit.lshift(bit.band(sec:byte(j + 1), 0x1F), 8), sec:byte(j + 2))
                local eslen = bit.bor(bit.lshift(bit.band(sec:byte(j + 3), 0x0F), 8), sec:byte(j + 4))
                if (st == 0x03 or st == 0x04 or st == 0x0F) and not state.audio then
                    state.audio = epid
                    state.stream_type = st
                end
                j = j + 5 + eslen
            end
        elseif state.audio and pid == state.audio and #payload > 0 then
            if pusi and payload:sub(1, 3) == "\0\0\1" then
                local hlen = payload:byte(9) or 0
                payload = payload:sub(10 + hlen)
            end
            fh:write(payload)
            written = written + #payload
        end
        i = i + 188
    end
    return written, state
end

--- The server's MP3 of a track via its transcoder (HLS, MP3 in MPEG-TS):
--- the playlist, then each segment, joined. true, or nil, err.
--[[ How to ask Plex's transcoder, in order (the first that works is kept for
the rest of the download). Plex picks a client profile by X-Plex-Platform; a
platform it doesn't know ("Kindle") has none, and a real server answered 400
Bad Request to every track (1.23.4 and before; the mock didn't mind). Plex
Web's ("Chrome") profile, with MP3 in MPEG-TS added; then the same at the
/audio/ address (as python-plexapi asks); then Plex Web's profile as it is
(AAC, kept as an .aac file). ]]
Plex.TRANSCODE = {
    { prefix = "/music", platform = "Chrome", mp3 = true },
    { prefix = "/audio", platform = "Chrome", mp3 = true },
    { prefix = "/music", platform = "Chrome", mp3 = false },
    { prefix = "/music", platform = "Kindle", mp3 = true },
}

--- Start the transcoder for track: the playlist's text, its address, or nil, err.
function Plex:transcodeStart(track, bitrate, session)
    local s = self.store.server
    local tried = {}
    local first = Plex.transcode_way or 1
    for n = 0, #Plex.TRANSCODE - 1 do
        local i = (first - 1 + n) % #Plex.TRANSCODE + 1
        local way = Plex.TRANSCODE[i]
        local params = {
            path = "/library/metadata/" .. track.key, protocol = "hls", mediaIndex = 0, partIndex = 0,
            directPlay = 0, directStream = 0, directStreamAudio = 0, musicBitrate = bitrate or 192,
            fastSeek = 1, hasMDE = 1,
            ["X-Plex-Session-Identifier"] = session, session = session, location = "lan",
            -- (who's asking, in the address too: the transcoder reads it there)
            ["X-Plex-Platform"] = way.platform, ["X-Plex-Client-Identifier"] = self:clientId(),
            ["X-Plex-Product"] = Plex.PRODUCT, ["X-Plex-Device"] = "Kindle",
            ["X-Plex-Client-Profile-Extra"] = way.mp3
                and "add-transcode-target(type=musicProfile&context=streaming&protocol=hls&container=mpegts&audioCodec=mp3)" or nil,
        }
        local base = s.uri .. way.prefix .. "/:/transcode/universal/"
        local code, text, err = self:request("GET", base .. "start.m3u8" .. query(params), { token = s.token, want_raw = true,
            timeouts = { 20, 60 }, headers = { ["X-Plex-Platform"] = way.platform } })
        if not err then
            if Plex.transcode_way ~= i then
                require("gzreader_log").info("plex: transcoding works asked as", way.prefix, way.platform, way.mp3 and "mp3" or "as it is")
            end
            Plex.transcode_way = i
            return text, base, s
        end
        tried[#tried + 1] = tostring(err)
        -- (not the way of asking: the server or the network)
        if code == nil or code == 401 or (code and code >= 500) then break end
    end
    return nil, "transcode " .. table.concat(tried, ", ")
end

function Plex:transcode(track, dest, bitrate)
    local session = require("gzreader_pairserver").randomToken(8)
    local text, base, s = self:transcodeStart(track, bitrate, session)
    if not text then return nil, base end
    -- a master playlist points at the media playlist (relative to it)
    local function lines(t)
        local out = {}
        for l in tostring(t or ""):gmatch("[^\r\n]+") do if l:sub(1, 1) ~= "#" then out[#out + 1] = l end end
        return out
    end
    local function resolve(rel, from)
        if rel:match("^https?://") then return rel end
        if rel:sub(1, 1) == "/" then return s.uri .. rel end
        return (from:gsub("[^/]*$", "")) .. rel
    end
    local media_url = base .. "start.m3u8"
    local list = lines(text)
    if list[1] and list[1]:match("%.m3u8") then
        media_url = resolve(list[1], base)
        local text2, err = select(2, self:request("GET", media_url, { token = s.token, want_raw = true, timeouts = { 20, 60 },
            headers = { ["X-Plex-Platform"] = Plex.TRANSCODE[Plex.transcode_way or 1].platform } }))
        if err then return nil, "transcode " .. err end
        text = text2
        list = lines(text)
    end
    if #list == 0 then return nil, "transcode: no segments" end
    local part = dest .. ".part"
    local fh = io.open(part, "wb")
    if not fh then return nil, "can't write" end
    local state, total = {}, 0
    for _i, seg in ipairs(list) do
        local url = resolve(seg, media_url)
        local data
        for _try = 1, 20 do -- (the transcoder makes segments as it goes)
            local c, raw = self:request("GET", url, { token = s.token, want_raw = true, timeouts = { 20, 60 } })
            if c == 200 and type(raw) == "string" and #raw > 0 then data = raw; break end
            require("socket").sleep(1)
        end
        if not data then fh:close(); os.remove(part); return nil, "transcode: a segment never came" end
        local w
        w, state = Plex.demuxTs(data, fh, state)
        total = total + w
    end
    fh:close()
    pcall(function() self:request("GET", base .. "stop" .. query({ session = session }), { token = s.token, timeouts = { 5, 5 } }) end)
    if total == 0 then
        os.remove(part)
        return nil, "transcode: no audio"
    end
    if state.stream_type and state.stream_type == 0x0F then
        -- AAC (Plex Web's own profile): its ADTS frames, as an .aac file
        local aac = dest:gsub("%.[^./]*$", "") .. ".aac"
        os.rename(part, aac)
        return true, "aac", aac
    end
    os.rename(part, dest)
    return true, "mp3", dest
end

--- Download a track for the Kindle into `dest_base` (without extension).
--- Returns the file written (and its kind "mp3" / "m4a" / "aac"), or nil, err.
function Plex:downloadTrack(track, dest_base, bitrate)
    local how, ext = Plex.how(track)
    local dest = dest_base .. "." .. ext
    if how == "transcode" then
        local ok, kind, path = self:transcode(track, dest, bitrate)
        if not ok then return nil, kind end
        return path or dest, kind or ext
    end
    if not (track.part and track.part.key) then return nil, "no file" end
    local ok, err = download(self, self.store.server.uri .. track.part.key .. "?download=1", dest)
    if not ok then return nil, err end
    return dest, ext
end

--- A cover (thumb path from the server) scaled by the server, into dest.
function Plex:downloadThumb(thumb, dest, size)
    if not thumb then return nil end
    local url = self.store.server.uri .. "/photo/:/transcode" .. query({ url = thumb, width = size or 300, height = size or 300, minSize = 1, upscale = 1, format = "jpeg" })
    return download(self, url, dest, { timeouts = { 10, 30 } })
end

return Plex
