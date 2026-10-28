--[[--
Minimal Grimmory REST client.

Grimmory issues a short-lived JWT access token (2 h) and a rotating refresh
token (30 days, replaced on every refresh). Only the tokens are stored on the
device; the account password is never written to disk.
]]

local JSON = require("json")
local http = require("socket.http")
local ltn12 = require("ltn12")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
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
    local body = opts.body
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
    -- LuaSocket/LuaSec raise (rather than return) on some failures, e.g. a TLS
    -- handshake error; treat those like any other network error.
    local pcall_ok, code, resp_headers, status = pcall(function()
        return socket.skip(1, http.request(request))
    end)
    socketutil:reset_timeout()
    if not pcall_ok then
        logger.warn("Grimmory: request failed", method, full_url, code)
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
        return nil, data, resp_headers, code
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

--- Stream a book's primary file to `dest_path`. Returns true or false, err.
function Api:downloadBook(book_id, dest_path)
    local ok, err = self:ensureToken()
    if not ok then return false, err end
    local tmp = dest_path .. ".part"
    local fh, ferr = io.open(tmp, "wb")
    if not fh then return false, ferr end
    local code = rawRequest("GET", self.store.server .. "/api/v1/books/" .. tostring(book_id) .. "/download", {
        headers = { ["Authorization"] = "Bearer " .. self.store.access_token, ["Accept"] = "*/*" },
        sink = socketutil.file_sink(fh),
        timeouts = { socketutil.FILE_BLOCK_TIMEOUT, 600 },
    })
    -- file_sink closes the handle when the transfer ends.
    if code == 200 then
        os.remove(dest_path)
        local renamed, rerr = os.rename(tmp, dest_path)
        if not renamed then return false, rerr end
        return true
    end
    os.remove(tmp)
    return false, code and ("http_" .. code) or "unreachable"
end

--- Find or create this account's KOReader sync credentials on the server.
--- Returns username, md5_key or nil, error.
function Api:ensureSyncAccount(gen_password)
    local code, data, err = self:call("GET", "/api/v1/koreader-users/me")
    if code == 403 then return nil, "no_sync_permission" end
    if not code then return nil, err end
    local username, key
    if code == 200 and type(data) == "table" then
        username, key = str(data.username), str(data.passwordMD5)
        if username and key and data.syncEnabled ~= true then
            self:call("PATCH", "/api/v1/koreader-users/me/sync?enabled=true")
        end
    end
    if username and key then return username, key end
    -- No sync account yet: create one. Reusing an existing one (above) keeps other
    -- devices that already sync with it working.
    local base = self.store.username or "kindle"
    for _, candidate in ipairs({ base, base .. "-kindle" }) do
        local password = gen_password()
        code, data, err = self:call("PUT", "/api/v1/koreader-users/me",
            { body = { username = candidate, password = password } })
        if code == 200 and type(data) == "table" then
            self:call("PATCH", "/api/v1/koreader-users/me/sync?enabled=true")
            return str(data.username) or candidate, str(data.passwordMD5) or md5(password)
        elseif code == 403 then
            return nil, "no_sync_permission"
        elseif not code then
            return nil, err
        end
    end
    return nil, "http_" .. tostring(code)
end

return Api
