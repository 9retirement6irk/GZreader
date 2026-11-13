--[[--
Memos (https://usememos.com) client for the Notes tab: notes, tags, checklist
ticks, attachments. Written against Memos v0.31 (REST under /api/v1). Memos
26.10 moved it to /api (and answers /api/v1 with 410 Gone; later releases
with 404): the address that works is remembered, and the other one is tried
when it stops working (a server updated either way).

Sign-in: a personal access token (Memos → Settings → Access Tokens), sent as
"Authorization: Bearer". It's kept in GZreader's settings like the Grimmory
login token and never written to the log.

Offline: the last list of notes is kept on the Kindle (gzreader-notes.json),
and new notes, edits and checklist ticks made without Wi-Fi wait in a queue
(store.memos.queue) until the next time GZreader can reach Memos.
]]

local DataStorage = require("datastorage")
local JSON = require("gzreader_json")
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
    -- (usb: notes brought by a computer, gzreader_usbsync.lua; the computer keeps the token)
    return (self.store.server ~= nil and self.store.token ~= nil) or self.store.usb == true
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
--- opts.here_only: only at the API address found already (a 404 there means
--- this Memos hasn't got it, not that the API moved).
function Memos:request(method, path, body, params, opts)
    opts = opts or {}
    if not self:isConnected() then return nil, nil, "not_connected" end
    local Api = require("gzreader_api")
    -- the remembered API address first, then the other
    local prefixes = {}
    if self.store.prefix then prefixes[1] = self.store.prefix end
    for _i, p in ipairs(Memos.PREFIXES) do
        if p ~= self.store.prefix and not (opts.here_only and self.store.prefix) then prefixes[#prefixes + 1] = p end
    end
    local code, data
    local gone -- a 404 / 410 answer, kept in case no address works
    for _i, prefix in ipairs(prefixes) do
        code, data = Api.rawRequest(method, self.store.server .. prefix .. path .. query(params), {
            headers = { ["Authorization"] = "Bearer " .. self.store.token },
            body = body,
            timeouts = opts.timeouts or { 10, 30 },
            sink = opts.sink,
        })
        if code ~= 404 and code ~= 410 then
            if code and code < 400 and prefix ~= self.store.prefix then
                if self.store.prefix then require("gzreader_log").info("memos: the API moved to", prefix) end
                self.store.prefix = prefix
            end
            gone = nil
            break
        end
        -- 410: "this API address was removed"; 404: no such address (or a
        -- real "not found": then the other address answers 404 / 410 too)
        if not gone or (gone.code == 410 and code == 404) then gone = { code = code, data = data } end
    end
    if gone then code, data = gone.code, gone.data end
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
--- order: Memos' order_by (pinned, create_time, update_time; pinned first, newest first by default).
function Memos:list(filter, page_token, page_size, order)
    local _, data, err = self:request("GET", "/memos", nil, {
        pageSize = page_size or Memos.PAGE_SIZE, pageToken = page_token, filter = filter,
        orderBy = order or "pinned desc, create_time desc",
    })
    if err then return nil, err end
    data = type(data) == "table" and data or {}
    local out = {}
    for _i, m in ipairs(data.memos or {}) do out[#out + 1] = Memos.slim(m) end
    return { memos = out, next = data.nextPageToken ~= "" and data.nextPageToken or nil }
end

--- Up to `max` notes, fetched a page at a time (Memos sends at most 1000
--- per page), with your tags and how many notes have each:
--- { memos = {…}, tags = { tag = count } } or nil, err.
function Memos:listAll(filter, max, order)
    max = max or 100
    local out, token = {}, nil
    repeat
        local page, err = self:list(filter, token, math.min(200, max - #out), order)
        if not page then return nil, err end
        for _i, m in ipairs(page.memos) do out[#out + 1] = m end
        token = page.next
    until not token or #out >= max
    local res = { memos = out }
    res.tags = self:tagCounts() -- nil if this Memos doesn't say
    res.spaces = self:spaces() -- nil: a Memos without spaces (before v0.31)
    -- (run in a background process: the API address it found goes back with the notes)
    res.prefix = self.store.prefix
    return res
end

--- { tag = number of notes } for all your tags (Memos' user stats), or nil.
function Memos:tagCounts()
    local name = self.store.user_name
    if not name then
        local user = self:me()
        name = user and user.name
        if not name then return nil end
    end
    local _, data, err = self:request("GET", "/" .. name .. ":getStats")
    -- (tagCount up to Memos 0.x; tagCounts from 26.10)
    local counts = type(data) == "table" and (data.tagCounts or data.tagCount)
    if err or type(counts) ~= "table" then return nil end
    local t = {}
    for tag, n in pairs(counts) do t[tag] = tonumber(n) or 0 end
    return t
end

--- Your spaces (Memos v0.31: the ones you're a member of), in Memos'
--- order: { { name = "spaces/…", title = "…" }, … }, or nil when this Memos
--- has none to offer (older: no /spaces) or didn't answer.
function Memos:spaces()
    local out, token = {}, nil
    repeat
        local code, data, err = self:request("GET", "/spaces", nil, { pageSize = 100, pageToken = token }, { here_only = true })
        if err or code ~= 200 or type(data) ~= "table" then return nil end
        for _i, sp in ipairs(type(data.spaces) == "table" and data.spaces or {}) do
            if type(sp) == "table" and type(sp.name) == "string" then
                out[#out + 1] = { name = sp.name, title = (type(sp.title) == "string" and sp.title ~= "") and sp.title
                    or sp.name:match("^spaces/(.+)$") or sp.name }
            end
        end
        token = type(data.nextPageToken) == "string" and data.nextPageToken ~= "" and data.nextPageToken or nil
    until not token or #out >= 500
    return out
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
        space = (type(m.space) == "string" and m.space ~= "") and m.space or nil,
    }
end

--- New note (private unless said otherwise), in `space` ("spaces/…") when
--- given. Returns the note or nil, err.
function Memos:create(content, visibility, space)
    local body = { content = content, visibility = visibility or "PRIVATE" }
    -- (only when there is one: Memos before v0.31 refuses a field it doesn't know)
    if space and space ~= "" then body.space = space end
    local _, data, err = self:request("POST", "/memos", body)
    if err then return nil, err end
    return Memos.slim(data or {})
end

--- The update mask and body for a note's change: its text, who can see it
--- (when given), its space (when given: "spaces/…", or "" for none). A
--- move sends the visibility too: Memos refuses to move a note only its
--- space's members can read without it.
function Memos.updateBody(name, content, visibility, space)
    local body, mask = { name = name, content = content }, { "content" }
    if visibility then body.visibility = visibility; mask[#mask + 1] = "visibility" end
    if space then
        mask[#mask + 1] = "space"
        if space ~= "" then body.space = space end
    end
    return body, table.concat(mask, ",")
end

--- Change a note's text (and who can see it, and its space, when given).
--- Returns the note or nil, err.
function Memos:update(name, content, visibility, space)
    local body, mask = Memos.updateBody(name, content, visibility, space)
    local _, data, err = self:request("PATCH", "/" .. name, body, { updateMask = mask })
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

--- Upload the file at `path` as an attachment named `filename` (`mime`:
--- image/png by default), on note `memo_name` ("memos/…") when given: Memos
--- links it to that note. Returns the attachment ({ name, filename, type })
--- or nil, err ("missing_file" when the file is gone).
function Memos:uploadAttachment(path, filename, memo_name, mime)
    local f = path and io.open(path, "rb")
    if not f then return nil, "missing_file" end
    local data = f:read("*a")
    f:close()
    local body = { filename = filename, type = mime or "image/png",
        content = require("ffi/sha2").bin_to_base64(data), memo = memo_name }
    local _, att, err = self:request("POST", "/attachments", body, nil, { timeouts = { 15, 120 } })
    if err then return nil, err end
    if type(att) ~= "table" or not att.name then return nil, "http_200" end
    return { name = att.name, filename = att.filename, type = att.type }
end

Memos.UPLOAD_CHUNK = 1024 * 1024 -- bytes a call (Memos takes up to 2 MiB)

--- Replace attachment `att_name`'s file with the file at `path` (an edited
--- drawing), keeping its name and note: Memos' resumable upload with
--- `replace_attachment` (its version after 26.11.0, as its web app does it).
--- Memos without it (v0.31) or that won't let us replace it (someone else's
--- drawing): the new file is added to note `memo_name` instead, and with an
--- old Memos the old one is deleted. Returns the attachment, or nil, err.
function Memos:replaceAttachment(att_name, path, filename, memo_name, mime)
    local f = path and io.open(path, "rb")
    if not f then return nil, "missing_file" end
    local data = f:read("*a")
    f:close()
    local b64 = require("ffi/sha2").bin_to_base64
    local id, offset, att = nil, 0
    repeat
        local part = data:sub(offset + 1, offset + Memos.UPLOAD_CHUNK)
        local last = offset + #part >= #data
        local body = { write_offset = offset, data = b64(part), finish_write = last }
        if id then body.upload_id = id
        else
            body.spec = { attachment = { filename = filename, type = mime or "image/png" }, total_size = #data,
                replace_attachment = att_name }
        end
        local code, res, err = self:request("POST", "/attachments:upload", body, nil, { timeouts = { 15, 120 } })
        if err then
            if id == nil and (code == 404 or code == 400 or code == 405 or code == 501) then
                -- (no replacing in this Memos: add the new one, then drop the old)
                local added, aerr = self:uploadAttachment(path, filename, memo_name, mime)
                if not added then return nil, aerr end
                self:deleteAttachment(att_name)
                return added
            elseif id == nil and code == 403 then
                -- (not ours to replace: the edit goes beside it, as in Memos' web app)
                return self:uploadAttachment(path, filename, memo_name, mime)
            end
            return nil, err
        end
        if type(res) ~= "table" then return nil, "http_200" end
        id = res.uploadId or res.upload_id or id
        offset = offset + #part
        att = res.attachment
    until last
    if type(att) ~= "table" or not att.name then return nil, "http_200" end
    return { name = att.name, filename = att.filename, type = att.type }
end

--- Delete attachment `att_name` ("attachments/…"). true, or nil, err.
function Memos:deleteAttachment(att_name)
    local _, _, err = self:request("DELETE", "/" .. att_name)
    if err and err ~= "http_404" then return nil, err end
    return true
end

--- A queue item's drawings ({ path, filename } each): `q.drawings`, or the
--- one `q.drawing` (queues from before several drawings).
function Memos.queuedDrawings(q)
    if type(q.drawings) == "table" then return q.drawings end
    if type(q.drawing) == "table" then return { q.drawing } end
    return {}
end

--- Uploads `q`'s drawings onto note `name`, in order. Returns true, or nil,
--- err and how many went before it stopped. (A drawing whose file is gone
--- is skipped: nothing left to send.)
function Memos:uploadDrawings(q, name)
    for i, d in ipairs(Memos.queuedDrawings(q)) do
        local att, err = self:uploadAttachment(d.path, d.filename, name)
        if not att and err ~= "missing_file" then return nil, err, i - 1 end
    end
    return true
end

--- Note `atts` (its attachments, as Memos lists them) in the order of
--- `filenames` (its drawings' pages): those first, in that order, then the
--- rest as they were. Names, or nil when they're in that order already.
function Memos.drawingOrder(atts, filenames)
    local used, out = {}, {}
    for _i, f in ipairs(filenames or {}) do
        for k, a in ipairs(atts or {}) do
            if not used[k] and a.filename == f then used[k] = true; out[#out + 1] = a.name; break end
        end
    end
    for k, a in ipairs(atts or {}) do if not used[k] then out[#out + 1] = a.name end end
    local same = #out == #(atts or {})
    for k, a in ipairs(atts or {}) do if out[k] ~= a.name then same = false end end
    if same then return nil end
    return out
end

--- One note, as Memos has it now.
function Memos:get(name)
    local _, memo, err = self:request("GET", "/" .. name)
    if err then return nil, err end
    if type(memo) ~= "table" or not memo.name then return nil, "http_200" end
    return memo
end

--- Puts note `name`'s drawings in the order of their pages (`filenames`):
--- Memos lists a note's attachments newest first, so pages uploaded one after
--- the other (or one replaced) come out of order. SetMemoAttachments sets the
--- order (Memos v0.31 and newer; an older Memos without it: left as it is).
function Memos:orderDrawings(name, filenames)
    if type(filenames) ~= "table" or #filenames < 1 then return true end
    local memo, err = self:get(name)
    if not memo then return nil, err end
    local order = Memos.drawingOrder(memo.attachments, filenames)
    if not order then return true end
    local list = {}
    for i, n in ipairs(order) do list[i] = { name = n } end
    local _, _, perr = self:request("PATCH", "/" .. name .. "/attachments", { name = name, attachments = list })
    if perr == "http_404" or perr == "http_405" or perr == "http_501" then return true end
    if perr then return nil, perr end
    return true
end

--- A new note with drawings: the note first, then the drawings uploaded
--- onto it. Returns the note, or nil, err and (the note made but not every
--- upload) the note's name and how many drawings went.
function Memos:createWithDrawing(q)
    local memo, err = self:create(q.content or "", q.visibility, q.space)
    if not memo then return nil, err end
    local ok, aerr, sent = self:uploadDrawings(q, memo.name)
    if not ok then return nil, aerr, memo.name, sent end
    return memo
end

--- Run the queued changes (in the background process). Returns the queue
--- items that went through (their ids), the first error, `attached`:
--- { [queue id] = note name } for notes made whose drawings didn't all
--- upload yet (the queue then sends only those: op "attach"), `sent`:
--- { [queue id] = how many of its drawings went } for those cut short, and
--- `reorder`: { [queue id] = note name } for notes whose drawings went but
--- couldn't be put in order yet (the queue then does only that: op "order").
function Memos:flush(queue)
    local done, first_err, attached, sent_some, reorder = {}, nil, {}, {}, {}
    for _i, q in ipairs(queue or {}) do
        local ok, err, made, sent
        if q.op == "create" and #Memos.queuedDrawings(q) > 0 then
            ok, err, made, sent = self:createWithDrawing(q)
            if made then attached[q.id] = made end
            if sent and sent > 0 then sent_some[q.id] = sent end
            -- the pages in order (not worth failing the note for: done later)
            if ok and q.order and not self:orderDrawings(ok.name, q.order) then reorder[q.id] = ok.name end
        elseif q.op == "attach" then
            ok, err, sent = self:uploadDrawings(q, q.name)
            if sent and sent > 0 then sent_some[q.id] = sent end
            if ok and q.order and not self:orderDrawings(q.name, q.order) then reorder[q.id] = q.name end
        elseif q.op == "order" then -- a note's drawings in the order of their pages
            ok, err = self:orderDrawings(q.name, q.order)
        elseif q.op == "redraw" then -- a drawing on a note edited: its new file over the old
            ok, err = self:replaceAttachment(q.attachment, q.drawing and q.drawing.path, q.drawing and q.drawing.filename, q.name)
            if err == "missing_file" then ok = true end
        elseif q.op == "undraw" then -- a drawing rubbed out to nothing: gone from the note
            ok, err = self:deleteAttachment(q.attachment)
        elseif q.op == "create" then ok, err = self:create(q.content, q.visibility, q.space)
        elseif q.op == "update" then ok, err = self:update(q.name, q.content, q.visibility, q.space)
        elseif q.op == "pin" then ok, err = self:setPinned(q.name, q.pinned) end
        if ok then done[#done + 1] = q.id
        else
            first_err = err
            if err == "unreachable" or err == "unauthorized" then break end
            if err and err:match("^http_4") then done[#done + 1] = q.id end -- refused for good: drop it
        end
    end
    return { done = done, err = first_err, prefix = self.store.prefix, attached = attached, sent = sent_some, reorder = reorder }
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
