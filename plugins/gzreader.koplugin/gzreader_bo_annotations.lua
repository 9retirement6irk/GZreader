--[[--
Two-way highlight and note sync with BookOrbit, for books whose place is an
XPointer (EPUB and the other reflowable formats).

BookOrbit's exchange (POST /koreader/plugin/annotations/exchange): the Kindle
sends, for one book,
  * the key of every highlight it has (md5 of "<datetime>|<pos0>"), so the
    server can tell which ones were deleted here;
  * the highlights that are new or changed since the last exchange, as KOReader
    keeps them (XPointers, text, note, style, colour);
and BookOrbit answers with what this Kindle lacks: highlights to add, to change
and to remove, made or changed on its web reader or another device. They are
put into the open book (or its settings file, if it closed meanwhile), and an
acknowledgement says which were applied. BookOrbit converts positions between
KOReader's and its web reader's itself, so nothing is converted here (Grimmory's
highlights are, gzreader_annotations.lua).

The same interface as gzreader_annotations.lua (new, run, onAnnotationsModified,
onClose): main picks this one when the book server is BookOrbit.

State in the download entry:
  entry.bo_anno = { [key] = fingerprint of what was last exchanged }
  (nil: this copy has never been through an exchange: sent as sidecarState
  "new", so nothing is deleted and everything is offered again)
  entry.anno_dirty = true while changes here may not be on BookOrbit yet

Written from BookOrbit's routes and field names; none of its plugin's code is here.
]]

local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")

local Anno = { DEBOUNCE = 3, MAX_CHANGES = 50, MAX_KEYS = 5000, MAX_ROUNDS = 8 }
Anno.__index = Anno

local DRAWERS = { lighten = true, underscore = true, strikeout = true, invert = true }

function Anno:new(sync)
    return setmetatable({
        sync = sync, ui = sync.ui, api = sync.api, plugin = sync.plugin, entry = sync.entry,
        book_id = sync.book_id, file = sync.ui.document and sync.ui.document.file,
        rolling = sync.ui.document ~= nil and sync:isRolling(),
    }, self)
end

function Anno:enabled()
    return self.plugin:syncEnabled() and self.plugin:serverCan("annotations") and self.plugin.store.annotation_sync_disabled ~= true
        and self.rolling and self.file ~= nil and type(self.entry.hash) == "string" and not self.off
end

local function isHighlight(a)
    return type(a) == "table" and type(a.pos0) == "string" and type(a.pos1) == "string" and type(a.datetime) == "string"
end

local function md5(s) return require("ffi/sha2").md5(s) end

--- A highlight's identity for BookOrbit: md5 of "<datetime>|<pos0>".
function Anno.key(a) return md5(tostring(a.datetime) .. "|" .. tostring(a.pos0)) end

local function text(v) return type(v) == "string" and v ~= "" and v or nil end

--- What BookOrbit keeps of a highlight, as one string: it changed when this did.
function Anno.fingerprint(a)
    return md5(table.concat({ DRAWERS[a.drawer] and a.drawer or "lighten", tostring(a.color or ""), tostring(a.text or ""),
        tostring(text(a.note) or ""), tostring(a.pos1 or "") }, "\0"))
end

--- A highlight as the exchange takes one.
function Anno.toRemote(a)
    return {
        datetime = a.datetime,
        datetimeUpdated = text(a.datetime_updated),
        drawer = DRAWERS[a.drawer] and a.drawer or "lighten",
        color = text(a.color) and a.color:sub(1, 30) or nil,
        text = text(a.text) and a.text:sub(1, 10000) or nil,
        note = text(a.note) and a.note:sub(1, 5000) or nil,
        chapter = text(a.chapter) and a.chapter:sub(1, 500) or nil,
        pageno = type(a.pageno) == "number" and a.pageno >= 0 and math.floor(a.pageno) or nil,
        posFormat = "xpointer",
        pos0 = a.pos0,
        pos1 = a.pos1,
    }
end

--- The book's highlights now: the open book's, or its settings file's.
function Anno:live()
    local ui = self.ui
    if ui.document and ui.document.file == self.file and ui.annotation then
        return ui.annotation.annotations or {}, true
    end
    local ok, list = pcall(function() return require("docsettings"):open(self.file):readSetting("annotations") end)
    return ok and type(list) == "table" and list or {}, false
end

--- What to send: every highlight's key, and the ones new or changed since `known`
--- (entry.bo_anno). Returns keys, changes (all of them), complete (the key list is whole).
function Anno.outgoing(list, known)
    local keys, changes = {}, {}
    known = type(known) == "table" and known or {}
    for _i, a in ipairs(list) do
        if isHighlight(a) then
            local k = Anno.key(a)
            if #keys < Anno.MAX_KEYS then keys[#keys + 1] = { k = k, dt = a.datetime } end
            if known[k] ~= Anno.fingerprint(a) then changes[#changes + 1] = Anno.toRemote(a) end
        end
    end
    local n = 0
    for _i, a in ipairs(list) do if isHighlight(a) then n = n + 1 end end
    return keys, changes, n <= Anno.MAX_KEYS
end

--- In the background: the exchanges for one book (its changes 50 at a time).
--- Returns { add, edit, delete, sent } or nil, err.
function Anno.work(api, hash, keys, changes, complete, state)
    local Json = require("gzreader_json")
    local out = { add = {}, edit = {}, delete = {}, sent = 0, taken = {} }
    local from, rounds = 1, 0
    repeat
        rounds = rounds + 1
        local part = {}
        for i = from, math.min(from + Anno.MAX_CHANGES - 1, #changes) do part[#part + 1] = changes[i] end
        from = from + #part
        local res, err = api:exchangeAnnotations({ hash = hash, keys = Json.list(keys), keysComplete = complete,
            sidecarState = state, changes = Json.list(part) })
        if not res then return nil, err end
        state = "known" -- (only the first round of a fresh copy says "new")
        out.sent = out.sent + #part
        for _i, c in ipairs(part) do out.taken[#out.taken + 1] = c end
        local t = type(res.toApply) == "table" and res.toApply or {}
        local seen = {}
        for _i, kind in ipairs({ "add", "edit", "delete" }) do
            for _j, e in ipairs(type(t[kind]) == "table" and t[kind] or {}) do
                if type(e) == "table" and type(e.serverId) == "number" and not seen[kind .. e.serverId] then
                    seen[kind .. e.serverId] = true
                    out[kind][#out[kind] + 1] = e
                end
            end
        end
        -- (what BookOrbit still has for this Kindle comes after these are acknowledged: the next pass)
        out.more = res.more == true
    until from > #changes or rounds >= Anno.MAX_ROUNDS
    out.unsent = #changes - out.sent
    return out
end

local function clean(v) return type(v) == "string" and v ~= "" and v or nil end

--- Put BookOrbit's answer into the list of highlights (in place). `valid(xp)`:
--- is this XPointer in the book (nil when the book isn't open: taken as it is).
--- Returns changed, applied (for the acknowledgement), deleted (same).
function Anno.merge(list, res, valid)
    local by_key = {}
    for i, a in ipairs(list) do if isHighlight(a) then by_key[Anno.key(a)] = i end end
    local applied, deleted, changed = {}, {}, false
    local remove = {}
    for _i, e in ipairs(res.delete or {}) do
        local i = type(e.key) == "string" and by_key[e.key]
        if i then remove[i] = true end
        -- (not here any more is what was asked for)
        deleted[#deleted + 1] = { serverId = e.serverId, status = "applied" }
    end
    for _i, e in ipairs(res.edit or {}) do
        local i = type(e.key) == "string" and by_key[e.key]
        local a = i and not remove[i] and list[i]
        if a then
            a.drawer = DRAWERS[e.drawer] and e.drawer or a.drawer
            a.color = clean(e.color) or a.color
            if clean(e.text) then a.text = e.text end
            a.note = clean(e.note)
            if clean(e.chapter) then a.chapter = e.chapter end
            a.datetime_updated = clean(e.datetimeUpdated) or a.datetime_updated
            changed = true
            applied[#applied + 1] = { serverId = e.serverId, version = e.version, status = "applied" }
        else
            applied[#applied + 1] = { serverId = e.serverId, version = e.version, status = "failed" }
        end
    end
    if next(remove) then
        for i = #list, 1, -1 do if remove[i] then table.remove(list, i) end end
        changed = true
        by_key = {}
        for i, a in ipairs(list) do if isHighlight(a) then by_key[Anno.key(a)] = i end end
    end
    for _i, e in ipairs(res.add or {}) do
        local ok = e.posFormat == "xpointer" and clean(e.pos0) and clean(e.pos1) and clean(e.datetime)
            and (not valid or (valid(e.pos0) and valid(e.pos1)))
        if ok then
            local a = { datetime = e.datetime, datetime_updated = clean(e.datetimeUpdated), drawer = DRAWERS[e.drawer] and e.drawer or "lighten",
                color = clean(e.color) or "yellow", text = clean(e.text) or "", note = clean(e.note), chapter = clean(e.chapter),
                pageno = type(e.pageno) == "number" and e.pageno or nil, page = e.pos0, pos0 = e.pos0, pos1 = e.pos1 }
            if not by_key[Anno.key(a)] then -- (already here: sent again because the last answer was lost)
                list[#list + 1] = a
                by_key[Anno.key(a)] = #list
                changed = true
            end
            applied[#applied + 1] = { serverId = e.serverId, version = e.version, status = "applied" }
        else
            applied[#applied + 1] = { serverId = e.serverId, version = e.version, status = "failed" }
        end
    end
    return changed, applied, deleted
end

--- Act on a finished pass.
function Anno:apply(res)
    local list, open = self:live()
    local doc = open and self.ui.document
    local valid = doc and doc.isXPointerInDocument and function(xp)
        local ok, yes = pcall(doc.isXPointerInDocument, doc, xp)
        return ok and yes
    end or nil
    local changed, applied, deleted = Anno.merge(list, res, valid)
    local saved = true
    if changed then
        self.applying = true
        if open and self.ui.annotation.sortItems then pcall(self.ui.annotation.sortItems, self.ui.annotation, list) end
        local copy = {} -- (saveLocal refills the book's own table from what it's given)
        for i, item in ipairs(list) do copy[i] = item end
        saved = require("gzreader_annotations").saveLocal(self, copy)
        if open then list = self.ui.annotation.annotations end
        self.applying = false
    end
    -- what BookOrbit now has of this Kindle's highlights: what was sent, and what it gave
    local known = type(self.entry.bo_anno) == "table" and self.entry.bo_anno or {}
    local now = {}
    local sent = {}
    for _i, c in ipairs(res.taken or {}) do sent[md5(tostring(c.datetime) .. "|" .. tostring(c.pos0))] = true end
    local given = {}
    for _i, e in ipairs(res.add or {}) do given[md5(tostring(e.datetime) .. "|" .. tostring(e.pos0))] = true end
    for _i, e in ipairs(res.edit or {}) do if type(e.key) == "string" then given[e.key] = true end end
    for _i, a in ipairs(list) do
        if isHighlight(a) then
            local k = Anno.key(a)
            if sent[k] or given[k] then now[k] = Anno.fingerprint(a) else now[k] = known[k] end
        end
    end
    self.entry.bo_anno = now
    local failed = 0
    for _i, e in ipairs(applied) do if e.status == "failed" then failed = failed + 1 end end
    local more = res.more or (res.unsent or 0) > 0
    self.entry.anno_dirty = (not saved or more) and true or nil
    self.plugin:save()
    Log.info("BookOrbit highlights", self.book_id, "sent", res.sent or 0, "added here", #(res.add or {}) - failed, "changed here", #(res.edit or {}),
        "removed here", #(res.delete or {}), failed > 0 and ("couldn't be placed: " .. failed) or "")
    if saved and (#applied > 0 or #deleted > 0) then
        local hash = self.entry.hash
        require("gzreader_async").run(self.api, function(api) return api:ackAnnotations(hash, applied, deleted) end, function(ok, err)
            if not ok then Log.info("BookOrbit highlights: the acknowledgement didn't arrive (asked again next time):", tostring(err)) end
            if more and not self.closed and self.plugin.sync == self.sync then self:run() end
        end, "annotations ack")
    end
    return list
end

--- One pass (in the background). on_done(ok) optional.
function Anno:run(on_done)
    if not self:enabled() then return on_done and on_done(false) end
    if self.busy then self.again = true; return end
    if not require("gzreader_net").connected() then return on_done and on_done(false) end
    self.busy, self.again, self.touched = true, false, false
    local list = self.snapshot and self.snapshot() or self:live()
    local keys, changes, complete = Anno.outgoing(list, self.entry.bo_anno)
    local hash, state = self.entry.hash, type(self.entry.bo_anno) == "table" and "known" or "new"
    require("gzreader_async").run(self.api, function(api)
        return Anno.work(api, hash, keys, changes, complete, state)
    end, function(res, err)
        self.busy = false
        local ok = false
        if type(res) ~= "table" then
            if err == "bookorbit_unmatched" or err == "bookorbit_incompatible" then
                -- (BookOrbit has no book with this file, or its copy differs: nothing to place highlights on)
                Log.info("BookOrbit highlights: not synced for this book:", err)
                self.off = true
            else
                Log.warn("BookOrbit highlight sync failed:", tostring(err))
                self.entry.anno_dirty = true
                self.plugin:save()
            end
        elseif self.touched then
            self.again = true -- changed here while the pass ran: start over from the new state
        else
            local done, crash = pcall(self.apply, self, res)
            if not done then Log.warn("BookOrbit highlight merge failed:", tostring(crash)) else ok = true end
        end
        if self.again and not self.closed then
            self.again = false
            UIManager:scheduleIn(1, function() self:run(on_done) end)
            return
        end
        if on_done then on_done(ok) end
    end, "annotations", { nice = true, timeout = 300 })
end

--- KOReader event: a highlight or note was added, changed or removed.
function Anno:onAnnotationsModified(items)
    if self.applying or type(items) ~= "table" or items.gz_synced then return end
    if not isHighlight(items[1]) then return end -- page bookmarks: their own sync
    if not self:enabled() then return end
    self.entry.anno_dirty = true
    self.touched = true
    if self.pending then UIManager:unschedule(self.pending) end
    if not require("gzreader_net").connected() then return end -- sent on close / next open
    self.pending = function()
        self.pending = nil
        self:run()
    end
    UIManager:scheduleIn(Anno.DEBOUNCE, self.pending)
end

--- Anything here that BookOrbit doesn't have yet (a note edited: KOReader says nothing then)?
function Anno:changedHere()
    local known = type(self.entry.bo_anno) == "table" and self.entry.bo_anno or nil
    if not known then return true end
    local list = self:live()
    local seen = {}
    for _i, a in ipairs(list) do
        if isHighlight(a) then
            local k = Anno.key(a)
            seen[k] = true
            if known[k] ~= Anno.fingerprint(a) then return true end
        end
    end
    for k in pairs(known) do if not seen[k] then return true end end
    return false
end

--- The book is closing: send what's waiting (Wi-Fi only when needed: brought up quietly).
function Anno:onClose()
    if self.pending then UIManager:unschedule(self.pending); self.pending = nil end
    self.closed = true
    if not self:enabled() then return end
    if not self.entry.anno_dirty and self:changedHere() then self.entry.anno_dirty = true end
    if not self.entry.anno_dirty then return end
    local Net = require("gzreader_net")
    local copy = {}
    for i, a in ipairs((self:live())) do copy[i] = a end
    self.snapshot = function() return copy end -- the book's highlights as it closed
    if Net.connected() then return self:run() end
    UIManager:scheduleIn(1, function()
        Net.run(function() self:run() end, { quiet = true, reason = "highlights on close" })
    end)
end

return Anno
