--[[--
Minimal Grimmory REST client.

Grimmory issues a short-lived JWT access token (2 h) and a rotating refresh
token (30 days, replaced on every refresh). Only the tokens are stored on the
device; the account password is never written to disk.
]]

local JSON = require("json")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local logger = require("logger")
local Log = require("grimmory_log")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")

local Api = {}
Api.__index = Api

-- Only keep plain strings/numbers coming out of decoded JSON (null sentinels
-- from the JSON library are userdata/functions).
local function str(v)
    if type(v) == "string" then return v end
    if type(v) == "number" then return tostring(v) end
    return nil
end
Api.str = str

function Api.normalizeServer(server)
    if type(server) ~= "string" then return nil end
    server = server:gsub("^%s+", ""):gsub("%s+$", "")
    if server == "" then return nil end
    if not server:match("^https?://") then
        server = "https://" .. server
    end
    server = server:gsub("/+$", "")
    -- People often paste the web UI login URL or the KOReader API path.
    server = server:gsub("/login.*$", ""):gsub("/api/koreader$", "")
    local parsed = url.parse(server)
    if not parsed or not parsed.host or parsed.host == "" then return nil end
    return server
end

--- @param store table holding persisted fields (server, username, access_token,
--- access_expires_at, refresh_token); `on_change` is called after it changes.
function Api:new(store, on_change)
    return setmetatable({ store = store, on_change = on_change or function() end }, self)
end

local function rawRequest(method, full_url, opts)
    opts = opts or {}
    local headers = { ["Accept"] = "application/json", ["Accept-Encoding"] = "identity" }
    for k, v in pairs(opts.headers or {}) do headers[k] = v end
    local body = opts.body or opts.raw_body
    if type(body) == "table" then
        body = JSON.encode(body)
        headers["Content-Type"] = "application/json"
    end
    if body then
        headers["Content-Length"] = tostring(#body)
    end
    local chunks = {}
    local sink = opts.sink or socketutil.table_sink(chunks)
    if opts.timeouts then
        socketutil:set_timeout(opts.timeouts[1], opts.timeouts[2])
    else
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    end
    local request = {
        url = full_url,
        method = method,
        headers = headers,
        source = body and ltn12.source.string(body) or nil,
        sink = sink,
    }
    logger.dbg("Grimmory:", method, full_url)
    pcall(function() require("grimmory_net").touch() end)
    local t0 = socket.gettime()
    -- LuaSocket/LuaSec raise (rather than return) on some failures, e.g. a TLS
    -- handshake error; treat those like any other network error.
    local pcall_ok, code, resp_headers, status = pcall(function()
        return socket.skip(1, http.request(request))
    end)
    socketutil:reset_timeout()
    pcall(function() require("grimmory_net").touch() end)
    local ms = math.floor((socket.gettime() - t0) * 1000)
    if not pcall_ok then
        logger.warn("Grimmory: request failed", method, full_url, code)
        Log.err("HTTP", method, full_url, "raised:", code, ms .. "ms")
        return nil, nil, nil, code
    end
    local raw = table.concat(chunks)
    local data
    if raw ~= "" and not opts.sink then
        local ok, decoded = pcall(JSON.decode, raw)
        if ok then data = decoded end
    end
    if type(code) ~= "number" then
        logger.warn("Grimmory: network error", method, full_url, code)
        Log.warn("HTTP", method, full_url, "network error:", code, ms .. "ms")
        return nil, data, resp_headers, code
    end
    if code >= 400 then
        Log.warn("HTTP", method, full_url, code, ms .. "ms", raw ~= "" and raw:sub(1, 300) or "")
    else
        Log.info("HTTP", method, full_url, code, ms .. "ms")
    end
    return code, data, resp_headers, status
end

function Api:isPaired()
    return self.store.server ~= nil and self.store.refresh_token ~= nil
end

function Api:_saveTokens(data)
    self.store.access_token = str(data.accessToken)
    self.store.refresh_token = str(data.refreshToken) or self.store.refresh_token
    local ttl = tonumber(data.expires) or 7200
    self.store.access_expires_at = os.time() + ttl
    self.on_change()
end

function Api:clearTokens()
    self.store.access_token = nil
    self.store.access_expires_at = nil
    self.store.refresh_token = nil
    self.on_change()
end

--- Log in with a username/password. Returns true or false, error_message.
--- On a scheme-less address we try https first, then plain http (common on LANs).
function Api:login(server, username, password)
    local candidates = { server }
    if server:match("^https://") and not self.explicit_https then
        candidates[2] = "http://" .. server:sub(9)
    end
    local last_err
    for _, base in ipairs(candidates) do
        local code, data = rawRequest("POST", base .. "/api/v1/auth/login", {
            body = { username = username, password = password },
            timeouts = { 10, 20 },
        })
        if code == 200 and type(data) == "table" and str(data.accessToken) then
            self.store.server = base
            self.store.username = username
            self:_saveTokens(data)
            return true
        elseif code == 401 or code == 403 or code == 400 then
            return false, "bad_credentials"
        elseif code == 429 then
            return false, "rate_limited"
        elseif code then
            last_err = "http_" .. code
            break -- server answered; don't retry over http
        else
            last_err = "unreachable"
        end
    end
    return false, last_err
end

--- Make sure we hold a valid access token, refreshing it if needed.
function Api:ensureToken()
    if self.store.access_token and os.time() < (self.store.access_expires_at or 0) - 120 then
        return true
    end
    if not self.store.refresh_token or not self.store.server then
        return false, "not_paired"
    end
    if self.no_refresh then
        -- download subprocess: a rotated refresh token would be lost on exit
        return false, "expired"
    end
    local code, data = rawRequest("POST", self.store.server .. "/api/v1/auth/refresh", {
        body = { refreshToken = self.store.refresh_token },
        timeouts = { 10, 20 },
    })
    if code == 200 and type(data) == "table" and str(data.accessToken) then
        self:_saveTokens(data)
        return true
    elseif code == 400 or code == 401 or code == 403 then
        -- Refresh token expired/revoked: the user must pair again.
        self:clearTokens()
        return false, "expired"
    end
    return false, code and ("http_" .. code) or "unreachable"
end

--- Authenticated request. path is relative to the server, e.g. "/api/v1/app/books".
function Api:call(method, path, opts)
    opts = opts or {}
    local ok, err = self:ensureToken()
    if not ok then return nil, nil, err end
    for attempt = 1, 2 do
        local o = {}
        for k, v in pairs(opts) do o[k] = v end
        o.headers = { ["Authorization"] = "Bearer " .. self.store.access_token }
        for k, v in pairs(opts.headers or {}) do o.headers[k] = v end
        local code, data, headers = rawRequest(method, self.store.server .. path, o)
        if code == 401 and attempt == 1 then
            -- Token rejected early (server restart, clock skew): force a refresh once.
            self.store.access_token = nil
            ok, err = self:ensureToken()
            if not ok then return nil, nil, err end
        else
            if not code then return nil, nil, "unreachable" end
            return code, data, nil, headers
        end
    end
end

function Api:logout()
    if self.store.server and self.store.refresh_token then
        pcall(rawRequest, "POST", self.store.server .. "/api/v1/auth/logout", {
            body = { refreshToken = self.store.refresh_token },
            headers = self.store.access_token and { ["Authorization"] = "Bearer " .. self.store.access_token } or nil,
            timeouts = { 5, 10 },
        })
    end
    self:clearTokens()
end

local function query(params)
    local parts = {}
    for k, v in pairs(params or {}) do
        if type(v) == "table" then
            for _, item in ipairs(v) do
                parts[#parts + 1] = url.escape(k) .. "=" .. url.escape(tostring(item))
            end
        elseif v ~= nil then
            parts[#parts + 1] = url.escape(k) .. "=" .. url.escape(tostring(v))
        end
    end
    table.sort(parts)
    return #parts > 0 and ("?" .. table.concat(parts, "&")) or ""
end
Api.query = query

-- Formats KOReader can open on a Kindle Keyboard; audiobooks are excluded.
Api.READABLE_TYPES = { "EPUB", "PDF", "FB2", "MOBI", "AZW3", "CBX" }

function Api:listBooks(params)
    local code, data, err = self:call("GET", "/api/v1/app/books" .. query(params))
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

--- GET /api/v1/books/page (the web app's list: full metadata, incl. subtitle).
function Api:listWebBooks(page, size)
    local code, data, err = self:call("GET", "/api/v1/books/page" .. query{ page = page, size = size },
        { timeouts = { 15, 60 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code)), code
end

--- GET /api/v1/app/libraries -> list of { id, name, bookCount, ... }
function Api:listLibraries()
    local code, data, err = self:call("GET", "/api/v1/app/libraries")
    if code == 200 and type(data) == "table" then return data end
    if code and code >= 500 then
        -- Some Grimmory versions fail here (library paths mapped outside a DB
        -- transaction). The web app's endpoint lists the same libraries.
        local c2, d2, e2 = self:call("GET", "/api/v1/libraries")
        if c2 == 200 and type(d2) == "table" then return d2 end
        return nil, e2 or ("http_" .. tostring(c2))
    end
    return nil, err or ("http_" .. tostring(code))
end

--- GET /api/v1/app/authors (paged; sort=name|bookCount..., search=...)
function Api:listAuthors(params)
    local code, data, err = self:call("GET", "/api/v1/app/authors" .. query(params))
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

--- GET /api/v1/app/series (paged; sort=name|bookCount|recentlyAdded...)
function Api:listSeries(params)
    local code, data, err = self:call("GET", "/api/v1/app/series" .. query(params))
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

function Api:searchBooks(q, page, size)
    local code, data, err = self:call("GET", "/api/v1/app/books/search" .. query{ q = q, page = page or 0, size = size or 25 })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

function Api:simpleList(endpoint, limit)
    local code, data, err = self:call("GET", "/api/v1/app/books/" .. endpoint .. query{ limit = limit or 20 })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

--- Stream a book's primary file straight into `path` (used by the download
--- subprocess, which writes the ".part" file). Returns true or false, err.
function Api:downloadToFile(book_id, path)
    local ok, err = self:ensureToken()
    if not ok then return false, err end
    local fh, ferr = io.open(path, "wb")
    if not fh then return false, ferr end
    local code, _, _, status = rawRequest("GET", self.store.server .. "/api/v1/books/" .. tostring(book_id) .. "/download", {
        headers = { ["Authorization"] = "Bearer " .. self.store.access_token, ["Accept"] = "*/*" },
        sink = ltn12.sink.file(fh), -- closes the file when the transfer ends
        timeouts = { 30, -1 },      -- 30 s per block; no overall cap (big books on slow Wi-Fi)
    })
    if code == 200 then return true end
    return false, code and ("http_" .. code) or tostring(status or "unreachable")
end

--- Full book record (includes this user's progress for its files).
function Api:getBook(book_id)
    local code, data, err = self:call("GET", "/api/v1/books/" .. tostring(book_id),
        { timeouts = { 8, 15 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

--- PUT /api/v1/app/books/{id}/progress with { fileProgress = {...} }.
function Api:putProgress(book_id, body)
    local code, _, err = self:call("PUT", "/api/v1/app/books/" .. tostring(book_id) .. "/progress",
        { body = body, timeouts = { 8, 15 } })
    if code == 200 or code == 204 then return true end
    return false, err or ("http_" .. tostring(code)), code
end

--- Audiobooks: duration, chapters, tracks (folder-based books), codec.
function Api:audiobookInfo(book_id)
    local code, data, err = self:call("GET", "/api/v1/audiobooks/" .. tostring(book_id) .. "/info",
        { timeouts = { 10, 30 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

--- Download one track of a folder-based audiobook (or, with track=nil, the
--- whole single-file audiobook) to `path`.
--- Download an audiobook file (track = Grimmory track index for folder
--- audiobooks, nil for a single-file one) to `path`, resuming whatever is
--- already there (HTTP Range on the audiobook stream endpoints).
--- Returns true | false, err, retryable.
function Api:downloadAudio(book_id, track, path)
    local ok, err = self:ensureToken()
    if not ok then return false, err, true end
    local have = lfs.attributes(path, "size") or 0
    local fh, ferr = io.open(path, have > 0 and "ab" or "wb")
    if not fh then return false, ferr end
    local base = self.store.server .. "/api/v1/audiobooks/" .. tostring(book_id)
    local full_url = track and (base .. "/track/" .. tostring(track) .. "/stream") or (base .. "/stream")
    local headers = { ["Authorization"] = "Bearer " .. self.store.access_token, ["Accept"] = "*/*" }
    if have > 0 then headers["Range"] = "bytes=" .. have .. "-" end
    local code, _, resp_headers, status = rawRequest("GET", full_url, {
        headers = headers,
        sink = ltn12.sink.file(fh), -- closes fh
        timeouts = { 60, -1 },
    })
    if code == 206 or (code == 200 and have == 0) then return true end
    if code == 416 then return true end -- nothing left to fetch
    if code == 200 and have > 0 then
        -- the server ignored Range and sent the whole file after the part we had
        local h = resp_headers and tonumber(resp_headers["content-length"])
        local size = lfs.attributes(path, "size") or 0
        if h and size == have + h then
            local inp, out = io.open(path, "rb"), io.open(path .. ".full", "wb")
            if inp and out then
                inp:seek("set", have)
                while true do
                    local buf = inp:read(1048576)
                    if not buf then break end
                    out:write(buf)
                end
                inp:close(); out:close()
                os.rename(path .. ".full", path)
                return true
            end
        end
        os.remove(path)
        return false, "server ignored Range", true
    end
    if code == 401 then return false, "http_401", true end
    if code and code >= 400 then return false, "http_" .. code, code >= 500 end
    return false, tostring(status or "unreachable"), true -- network error: partial data kept, resume
end

--- Bookmarks (Grimmory's own: EPUB by CFI, PDF by page number).
function Api:listBookmarks(book_id)
    local code, data, err = self:call("GET", "/api/v1/bookmarks/book/" .. tostring(book_id),
        { timeouts = { 8, 15 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code))
end

function Api:createBookmark(body)
    local code, data, err = self:call("POST", "/api/v1/bookmarks", { body = body, timeouts = { 8, 15 } })
    if code and code >= 200 and code < 300 and type(data) == "table" then return data end
    return nil, err or ("http_" .. tostring(code)), code
end

function Api:deleteBookmark(id)
    local code, _, err = self:call("DELETE", "/api/v1/bookmarks/" .. tostring(id), { timeouts = { 8, 15 } })
    if code == 204 or code == 200 or code == 404 then return true end
    return false, err or ("http_" .. tostring(code)), code
end

--- POST /api/v1/reading-sessions (feeds Grimmory's reading statistics).
function Api:postSession(body)
    local code, _, err = self:call("POST", "/api/v1/reading-sessions", { body = body, timeouts = { 8, 15 } })
    if code and code >= 200 and code < 300 then return true end
    return false, err or ("http_" .. tostring(code)), code
end

---------------------------------------------------------------- single sign-on (OIDC)

local function urlencodeForm(t)
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = url.escape(k) .. "=" .. url.escape(tostring(v))
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

--- RFC 7636 S256 code challenge for a verifier.
function Api.pkceChallenge(verifier)
    local sha2 = require("ffi/sha2")
    local b64 = sha2.bin_to_base64(sha2.hex_to_bin(sha2.sha256(verifier)))
    return (b64:gsub("%+", "-"):gsub("/", "_"):gsub("=", ""))
end

--- Unauthenticated GET returning decoded JSON.
function Api.fetchJson(full_url)
    local code, data = rawRequest("GET", full_url, { timeouts = { 10, 20 } })
    if code == 200 and type(data) == "table" then return data end
    return nil, code and ("http_" .. code) or "unreachable"
end

--- Grimmory's public settings (SSO on/off, provider details). Tries https
--- then http for a scheme-less address, like login. Returns base, settings.
function Api:publicSettings(server)
    local candidates = { server }
    if server:match("^https://") and not self.explicit_https then
        candidates[2] = "http://" .. server:sub(9)
    end
    local last_err
    for _, base in ipairs(candidates) do
        local data, err = Api.fetchJson(base .. "/api/v1/public-settings")
        if data then return base, data end
        last_err = err
        if err ~= "unreachable" then break end
    end
    return nil, last_err
end

--- Authorization endpoint from the provider's discovery document.
function Api.discoverAuthorizationEndpoint(issuer)
    issuer = (issuer or ""):gsub("/+$", "")
    local doc, err = Api.fetchJson(issuer .. "/.well-known/openid-configuration")
    if not doc then return nil, err end
    return str(doc.authorization_endpoint), "no_authorization_endpoint"
end

--- One-time state from Grimmory (it validates and consumes it on exchange).
function Api.oidcState(base)
    local data, err = Api.fetchJson(base .. "/api/v1/auth/oidc/state")
    if data and str(data.state) then return data.state end
    return nil, err or "no_state"
end

--- Exchange the provider's code for Grimmory tokens via the mobile callback.
--- `origin` must be the origin of redirect_uri: Grimmory checks they match.
function Api:oidcExchange(base, params, origin)
    local form = urlencodeForm(params)
    local code, data = rawRequest("POST", base .. "/api/v1/auth/oidc/mobile/callback", {
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Content-Length"] = tostring(#form),
            ["Origin"] = origin,
        },
        raw_body = form,
        timeouts = { 15, 30 },
    })
    if code == 200 and type(data) == "table" and str(data.accessToken) then
        self.store.server = base
        self:_saveTokens(data)
        local c2, me = self:call("GET", "/api/v1/users/me")
        if c2 == 200 and type(me) == "table" then
            self.store.username = str(me.username) or str(me.name) or self.store.username
            self.on_change()
        end
        return true
    end
    local msg = type(data) == "table" and (str(data.message) or str(data.error)) or nil
    return false, msg or (code and ("http_" .. code) or "unreachable")
end

return Api
