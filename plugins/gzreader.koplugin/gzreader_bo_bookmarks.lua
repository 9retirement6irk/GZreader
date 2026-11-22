--[[--
Two-way page-bookmark sync with BookOrbit (the dog-ears), for books whose
place is an XPointer (EPUB and the other reflowable formats), when the server
says it does bookmarks (its `bookmarkSync` capability).

BookOrbit's exchange (POST /koreader/plugin/bookmarks/exchange), like the one
for highlights (gzreader_bo_annotations.lua): the Kindle sends the key of every
bookmark in the book (md5 of "<datetime>|<place>") and the ones BookOrbit hasn't
had from it; BookOrbit answers with bookmarks to add (made elsewhere) and to
remove. A bookmark BookOrbit gives has no date: the Kindle dates it and says
in the acknowledgement which key it now has here. Bookmarks aren't edited.

The same interface as gzreader_bookmarks.lua (new, reconcile,
onAnnotationsModified): main picks this one when the book server is BookOrbit.

State in the download entry:
  entry.bo_marks = { [key] = true } what BookOrbit has had from, or given to, this copy
  (nil: never exchanged: sent as sidecarState "new", so nothing is deleted)

Written from BookOrbit's routes and field names; none of its plugin's code is here.
]]

local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")

local BM = { DEBOUNCE = 3, MAX_CHANGES = 50, MAX_KEYS = 2000 }
BM.__index = BM

function BM:new(sync)
    return setmetatable({
        sync = sync, ui = sync.ui, api = sync.api, plugin = sync.plugin, entry = sync.entry,
        book_id = sync.book_id, file = sync.ui.document and sync.ui.document.file,
        rolling = sync.ui.document ~= nil and sync:isRolling(),
    }, self)
end

function BM:enabled()
    return self.plugin:syncEnabled() and self.plugin:serverCan("bookmarks") and self.plugin.store.bookmark_sync_disabled ~= true
        and self.rolling and self.file ~= nil and type(self.entry.hash) == "string" and not self.off
        and (type(self.api.can) ~= "function" or self.api:can("bookmarkSync"))
end

local function md5(s) return require("ffi/sha2").md5(s) end
local function text(v) return type(v) == "string" and v ~= "" and v or nil end

local function isPageBookmark(item)
    return type(item) == "table" and not item.drawer and not item.pos0 and type(item.page) == "string"
end
BM.isPageBookmark = isPageBookmark

function BM.key(item) return md5(tostring(item.datetime) .. "|" .. tostring(item.page)) end

function BM.toRemote(item)
    return { datetime = item.datetime, datetimeUpdated = text(item.datetime_updated), pos = item.page,
        pageno = type(item.pageno) == "number" and item.pageno >= 0 and math.floor(item.pageno) or nil,
        chapter = text(item.chapter) and item.chapter:sub(1, 500) or nil,
        note = text(item.text) and item.text:sub(1, 500) or nil }
end

function BM:live()
    local ui = self.ui
    if ui.document and ui.document.file == self.file and ui.annotation then return ui.annotation.annotations or {}, true end
    local ok, list = pcall(function() return require("docsettings"):open(self.file):readSetting("annotations") end)
    return ok and type(list) == "table" and list or {}, false
end

--- What to send: every bookmark's key, and the ones not in `known`. A bookmark with no
--- date (one an older GZreader put there) is dated now, once (dated = true then).
function BM.outgoing(list, known, now)
    local keys, changes, dated = {}, {}, false
    known = type(known) == "table" and known or {}
    for _i, item in ipairs(list) do
        if isPageBookmark(item) then
            if not text(item.datetime) then item.datetime = now or os.date("%Y-%m-%d %H:%M:%S"); dated = true end
            local k = BM.key(item)
            if #keys < BM.MAX_KEYS then keys[#keys + 1] = { k = k, dt = item.datetime } end
            if not known[k] and #changes < BM.MAX_CHANGES then changes[#changes + 1] = BM.toRemote(item) end
        end
    end
    return keys, changes, #keys < BM.MAX_KEYS, dated
end

--- Put BookOrbit's answer into the list (in place). Returns changed, applied, deleted.
function BM.merge(list, res, valid, chapterOf, now)
    local by_key, by_pos = {}, {}
    for i, item in ipairs(list) do
        if isPageBookmark(item) then
            if text(item.datetime) then by_key[BM.key(item)] = i end
            by_pos[item.page] = i
        end
    end
    local applied, deleted, changed, remove = {}, {}, false, {}
    for _i, e in ipairs(res.delete or {}) do
        local i = type(e.key) == "string" and by_key[e.key]
        if i then remove[i] = true end
        deleted[#deleted + 1] = { serverId = e.serverId, status = "applied" }
    end
    if next(remove) then
        for i = #list, 1, -1 do
            if remove[i] then by_pos[list[i].page] = nil; table.remove(list, i) end
        end
        changed = true
        by_pos = {}
        for i, item in ipairs(list) do if isPageBookmark(item) then by_pos[item.page] = i end end
    end
    for _i, e in ipairs(res.add or {}) do
        local pos = text(e.pos)
        if pos and pos:sub(1, 1) == "/" and (not valid or valid(pos)) then
            local item = by_pos[pos] and list[by_pos[pos]]
            if not item then -- (a page that's already dog-eared here keeps its own bookmark)
                item = { datetime = now or os.date("%Y-%m-%d %H:%M:%S"), page = pos, text = text(e.title),
                    pageno = type(e.pageno) == "number" and e.pageno or nil, chapter = chapterOf and text(chapterOf(pos)) or nil }
                list[#list + 1] = item
                by_pos[pos] = #list
                changed = true
            elseif not text(item.datetime) then
                item.datetime = now or os.date("%Y-%m-%d %H:%M:%S")
                changed = true
            end
            applied[#applied + 1] = { serverId = e.serverId, status = "applied", key = BM.key(item), datetime = item.datetime, pos = pos }
        else
            applied[#applied + 1] = { serverId = e.serverId, status = "failed" }
        end
    end
    return changed, applied, deleted
end

function BM:apply(res, sent_keys)
    local list, open = self:live()
    local doc = open and self.ui.document
    local valid = doc and doc.isXPointerInDocument and function(xp)
        local ok, yes = pcall(doc.isXPointerInDocument, doc, xp)
        return ok and yes
    end or nil
    local chapterOf = open and self.ui.toc and function(xp)
        local ok, title = pcall(self.ui.toc.getTocTitleByPage, self.ui.toc, xp)
        return ok and title or nil
    end or nil
    local changed, applied, deleted = BM.merge(list, res, valid, chapterOf)
    local saved = true
    if changed or self.dated then
        self.applying = true
        if open and self.ui.annotation.sortItems then pcall(self.ui.annotation.sortItems, self.ui.annotation, list) end
        local copy = {}
        for i, item in ipairs(list) do copy[i] = item end
        saved = require("gzreader_annotations").saveLocal(self, copy)
        if open then
            list = self.ui.annotation.annotations
            if self.ui.bookmark and self.ui.bookmark.setDogearVisibility then
                pcall(function() self.ui.bookmark:setDogearVisibility(self.ui.bookmark:getCurrentPageNumber()) end)
            end
        end
        self.applying = false
        self.dated = nil
    end
    local known = {}
    local ok_keys = {}
    for _i, k in ipairs(sent_keys or {}) do ok_keys[k] = true end
    for _i, e in ipairs(applied) do if e.key then ok_keys[e.key] = true end end
    local old = type(self.entry.bo_marks) == "table" and self.entry.bo_marks or {}
    for _i, item in ipairs(list) do
        if isPageBookmark(item) and text(item.datetime) then
            local k = BM.key(item)
            if ok_keys[k] or old[k] then known[k] = true end
        end
    end
    self.entry.bo_marks = known
    self.entry.bm_dirty = (not saved or res.more) and true or nil
    self.plugin:save()
    Log.info("BookOrbit bookmarks", self.book_id, "sent", #(sent_keys or {}), "added here", #(res.add or {}), "removed here", #(res.delete or {}))
    if saved and (#applied > 0 or #deleted > 0) then
        local hash = self.entry.hash
        require("gzreader_async").run(self.api, function(api) return api:ackExchange("bookmarks", hash, applied, deleted) end, function(ok, err)
            if not ok then Log.info("BookOrbit bookmarks: the acknowledgement didn't arrive (asked again next time):", tostring(err)) end
        end, "bookmarks ack")
    end
end

--- One pass (in the background): called when the book opens, on Sync now, and after a change.
function BM:reconcile(on_done)
    if not self:enabled() then return on_done and on_done(false) end
    if self.busy then self.again = true; return end
    if not require("gzreader_net").connected() then return on_done and on_done(false) end
    self.busy, self.again = true, false
    local list = self:live()
    local keys, changes, complete, dated = BM.outgoing(list, self.entry.bo_marks)
    self.dated = dated or self.dated
    local sent = {}
    for _i, c in ipairs(changes) do sent[#sent + 1] = md5(c.datetime .. "|" .. c.pos) end
    local Json = require("gzreader_json")
    local book = { hash = self.entry.hash, keys = Json.list(keys), keysComplete = complete,
        sidecarState = type(self.entry.bo_marks) == "table" and "known" or "new", changes = Json.list(changes) }
    require("gzreader_async").run(self.api, function(api) return api:exchange("bookmarks", book) end, function(res, err)
        self.busy = false
        local ok = false
        if type(res) ~= "table" then
            if err == "bookorbit_unmatched" or err == "bookorbit_incompatible" then
                Log.info("BookOrbit bookmarks: not synced for this book:", err)
                self.off = true
            else
                Log.warn("BookOrbit bookmark sync failed:", tostring(err))
                self.entry.bm_dirty = true
                self.plugin:save()
            end
        else
            res.add = type(res.toApply) == "table" and res.toApply.add or {}
            res.delete = type(res.toApply) == "table" and res.toApply.delete or {}
            local done, crash = pcall(self.apply, self, res, sent)
            if not done then Log.warn("BookOrbit bookmark merge failed:", tostring(crash)) else ok = true end
        end
        if self.again then
            self.again = false
            UIManager:scheduleIn(1, function() self:reconcile(on_done) end)
            return
        end
        if on_done then on_done(ok) end
    end, "bookmarks", { nice = true })
end

--- KOReader event: a bookmark was added or removed.
function BM:onAnnotationsModified(items)
    if self.applying or type(items) ~= "table" then return end
    local item = items[1]
    if type(item) ~= "table" or item.drawer or item.pos0 then return end -- (a highlight: its own sync)
    if not self:enabled() then return end
    self.entry.bm_dirty = true
    if self.pending then UIManager:unschedule(self.pending) end
    if not require("gzreader_net").connected() then return end -- sent at the next open
    self.pending = function()
        self.pending = nil
        self:reconcile()
    end
    UIManager:scheduleIn(BM.DEBOUNCE, self.pending)
end

return BM
