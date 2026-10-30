--[[--
Memos (https://usememos.com) client for the Notes tab: notes, tags, checklist
ticks, attachments. Written against Memos v0.31 (REST under /api/v1); newer
servers moved it to /api, which is tried when /api/v1 isn't there.

Sign-in: a personal access token (Memos → Settings → Access Tokens), sent as
"Authorization: Bearer". It's kept in GZreader's settings like the Grimmory
login token and never written to the log.

Offline: the last list of notes is kept on the Kindle (gzreader-notes.json),
and new notes, edits and checklist ticks made without Wi-Fi wait in a queue
(store.memos.queue) until the next time GZreader can reach Memos.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")

local Memos = {
    PAGE_SIZE = 50,
    PREFIXES = { "/api/v1", "/api" },
}
Memos.__index = Memos

--- `store` is plugin.store.memos (server, token, user, prefix, queue).
function Memos:new(store)
    return setmetatable({ store = store }, self)
end

function Memos.normalizeServer(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
    if s == "" then return nil end
    if not s:match("^https?://") then s = "https://" .. s end
    -- people paste the web page's address
    s = s:gsub("/explore$", ""):gsub("/auth$", ""):gsub("/setting$", ""):gsub("/api/v1$", ""):gsub("/api$", "")
    if not s:match("^https?://[^/]+") then return nil end
    return s
end

function Memos:isConnected()
    return self.store.server ~= nil and self.store.token ~= nil
end

local function query(params)
    local t = {}
    local url = require("socket.url")
    for k, v in pairs(params or {}) do
        if v ~= nil and v ~= "" then t[#t + 1] = k .. "=" .. url.escape(tostring(v)) end
    end
    table.sort(t)
    return #t > 0 and ("?" .. table.concat(t, "&")) or ""
end

--- One request. Returns code, data, err ("unreachable", "unauthorized", "http_<code>").
function Memos:request(method, path, body, params, opts)
    opts = opts or {}
    if not self:isConnected() then return nil, nil, "not_connected" end
    local Api = require("gzreader_api")
    local prefixes = self.store.prefix and { self.store.prefix } or Memos.PREFIXES
    local code, data
    for _i, prefix in ipairs(prefixes) do
        code, data = Api.rawRequest(method, self.store.server .. prefix .. path .. query(params), {
            headers = { ["Authorization"] = "Bearer " .. self.store.token },
            body = body,
            timeouts = opts.timeouts or { 10, 30 },
            sink = opts.sink,
        })
        if code ~= 404 or self.store.prefix then
            if code and code < 400 and not self.store.prefix then self.store.prefix = prefix end
            break
        end
    end
    if not code then return nil, nil, "unreachable" end
    if code == 401 or code == 403 then return code, data, "unauthorized" end
    if code >= 400 then return code, data, "http_" .. code end
    return code, data
end

--- The signed-in user ({ name, username, displayName }), or nil, err.
function Memos:me()
    local code, data, err = self:request("GET", "/auth/me")
    if err then return nil, err end
    local user = type(data) == "table" and (data.user or data) or nil
    if type(user) ~= "table" or not (user.name or user.username) then return nil, "http_" .. tostring(code) end
    return { name = user.name, username = user.username, displayName = user.displayName }
end

--- A page of notes: { memos = {…}, next = token } or nil, err.
--- filter: Memos' CEL filter (tags, created_ts, pinned, has_task_list…).
function Memos:list(filter, page_token, page_size)
    local _, data, err = self:request("GET", "/memos", nil, {
        pageSize = page_size or Memos.PAGE_SIZE, pageToken = page_token, filter = filter,
        orderBy = "pinned desc, create_time desc",
    })
    if err then return nil, err end
    data = type(data) == "table" and data or {}
    local out = {}
    for _i, m in ipairs(data.memos or {}) do out[#out + 1] = Memos.slim(m) end
    return { memos = out, next = data.nextPageToken ~= "" and data.nextPageToken or nil }
end

--- Only what the Notes tab uses (the cache stays small).
function Memos.slim(m)
    local atts = {}
    for _i, a in ipairs(type(m.attachments) == "table" and m.attachments or {}) do
        atts[#atts + 1] = { name = a.name, filename = a.filename, type = a.type, size = tonumber(a.size),
            link = a.externalLink ~= "" and a.externalLink or nil }
    end
    local loc = type(m.location) == "table" and m.location or nil
    return {
        name = m.name, content = m.content or "", pinned = m.pinned == true, visibility = m.visibility,
        tags = type(m.tags) == "table" and m.tags or {}, created = m.createTime, updated = m.updateTime,
        place = loc and (loc.placeholder ~= "" and loc.placeholder or nil) or nil, attachments = atts,
    }
end

--- New note (private unless said otherwise). Returns the note or nil, err.
function Memos:create(content, visibility)
    local _, data, err = self:request("POST", "/memos", { content = content, visibility = visibility or "PRIVATE" })
    if err then return nil, err end
    return Memos.slim(data or {})
end

--- Change a note's text (and who can see it, when given). Returns the note or nil, err.
function Memos:update(name, content, visibility)
    local _, data, err = self:request("PATCH", "/" .. name,
        { name = name, content = content, visibility = visibility },
        { updateMask = visibility and "content,visibility" or "content" })
    if err then return nil, err end
    return Memos.slim(data or {})
end

function Memos:setPinned(name, pinned)
    local _, data, err = self:request("PATCH", "/" .. name, { name = name, pinned = pinned == true },
        { updateMask = "pinned" })
    if err then return nil, err end
    return Memos.slim(data or {})
end

--- An attachment's file: /file/attachments/<uid>/<filename> (outside /api).
function Memos:download(att, dest)
    if att.link then return nil, "external" end
    local uid = tostring(att.name or ""):match("attachments/(.+)$")
    if not uid then return nil, "no id" end
    local part = dest .. ".part"
    local fh = io.open(part, "wb")
    if not fh then return nil, "can't write" end
    local Api = require("gzreader_api")
    local url = require("socket.url")
    local code = Api.rawRequest("GET", self.store.server .. "/file/attachments/" .. uid .. "/" .. url.escape(att.filename or "file"), {
        headers = { ["Authorization"] = "Bearer " .. self.store.token },
        sink = ltn12.sink.file(fh), timeouts = { 10, 120 },
    })
    if code == 200 and (lfs.attributes(part, "size") or 0) > 0 then
        os.rename(part, dest)
        return true
    end
    os.remove(part)
    return nil, code and ("http_" .. code) or "unreachable"
end

--- Run the queued changes (in the background process). Returns the queue
--- items that went through (their ids) and the first error.
function Memos:flush(queue)
    local done, first_err = {}, nil
    for _i, q in ipairs(queue or {}) do
        local ok, err
        if q.op == "create" then ok, err = self:create(q.content, q.visibility)
        elseif q.op == "update" then ok, err = self:update(q.name, q.content, q.visibility)
        elseif q.op == "pin" then ok, err = self:setPinned(q.name, q.pinned) end
        if ok then done[#done + 1] = q.id
        else
            first_err = err
            if err == "unreachable" or err == "unauthorized" then break end
            if err and err:match("^http_4") then done[#done + 1] = q.id end -- refused for good: drop it
        end
    end
    return { done = done, err = first_err }
end

---------------------------------------------------------------- the cache

function Memos.cachePath() return DataStorage:getSettingsDir() .. "/gzreader-notes.json" end

function Memos.loadCache()
    local f = io.open(Memos.cachePath(), "rb")
    if not f then return nil end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    return ok and type(data) == "table" and data or nil
end

function Memos.saveCache(data)
    local tmp = Memos.cachePath() .. ".tmp"
    local f = io.open(tmp, "wb")
    if not f then return end
    f:write(JSON.encode(data))
    f:close()
    os.rename(tmp, Memos.cachePath())
end

function Memos.filesDir()
    local dir = DataStorage:getDataDir() .. "/cache/gzreader-notes"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    lfs.mkdir(dir)
    return dir
end

--- Where an attachment's file is kept on the Kindle.
function Memos.filePath(att)
    local uid = tostring(att.name or ""):match("attachments/(.+)$") or "x"
    local fname = tostring(att.filename or "file"):gsub("[/\\:%*%?\"<>|%c]", "_")
    return Memos.filesDir() .. "/" .. uid:gsub("[^%w%-_]", "_") .. "-" .. fname
end

return Memos
