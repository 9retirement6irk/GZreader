--[[--
Two-way highlight and note sync with Grimmory (the annotations its web
reader shows), for EPUBs downloaded through the Grimmory tab.

The conversion and three-way merge come from Grimmory-KOReader-Client (MIT,
vendored as grimmory_cfi, grimmory_slaxml and grimmory_annosync):
- KOReader keeps a highlight as two crengine XPointers; Grimmory as an EPUB
  CFI range with UTF-16 offsets. grimmory_cfi converts between them using
  the book's own XHTML.
- Each pass compares this Kindle's highlights, Grimmory's, and the state
  both had after the last clean pass (the "shadow", kept in the download
  entry). Changes on one side are copied to the other; a highlight changed
  on both sides since then is a conflict and left alone on both.

On the Kindle 3 the expensive part (parsing chapters, converting every
highlight, the requests) runs in one low-priority background process; only
the final merge into the open book happens on screen.

Runs a few seconds after the book opens, a few seconds after you add, edit
or delete a highlight or note (when Wi-Fi is on), on "Sync now", and when
the book closes if something is still waiting.

State in the download entry:
  entry.anno_shadow = { [grimmory id] = { full = …, immutable = … } }
  entry.anno_dirty  = true while local changes may not be on Grimmory yet
]]

local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")

local Anno = { DEBOUNCE = 3 }
Anno.__index = Anno

function Anno:new(sync)
    local entry = sync.entry
    entry.anno_shadow = type(entry.anno_shadow) == "table" and entry.anno_shadow or {}
    return setmetatable({
        sync = sync, ui = sync.ui, api = sync.api, plugin = sync.plugin, entry = entry,
        book_id = sync.book_id, file = sync.ui.document and sync.ui.document.file,
        is_epub = sync.ui.document ~= nil and sync:isEpub(),
    }, self)
end

function Anno:enabled()
    return self.plugin:syncEnabled() and self.plugin.store.annotation_sync_disabled ~= true
        and self.is_epub and self.file ~= nil
end

local function isHighlight(a)
    return type(a) == "table" and a.pos0 ~= nil and a.pos1 ~= nil
end

--- Plain copies of the open book's highlights (what the background job sees).
function Anno:snapshot()
    local out = {}
    for _i, a in ipairs(self.ui.annotation and self.ui.annotation.annotations or {}) do
        out[#out + 1] = a
    end
    return out
end

--- How the background job reads the EPUB (tests swap this out).
function Anno.openReader(_path) return nil end -- nil: grimmory_cfi opens it with ffi/archiver

---------------------------------------------------------------- background job

local function key(p0, p1) return tostring(p0) .. "\n" .. tostring(p1) end

--- Runs in the background process. Plain values in, plain values out.
function Anno.work(api, file, book_id, locals, shadow)
    local Real = require("gzreader_cfi")
    local AS = require("gzreader_annosync")
    local ok, err = Real.initBook(file, Anno.openReader(file))
    if not ok then return nil, "book: " .. tostring(err) end
    -- Highlights already linked to Grimmory carry the range both ways (from
    -- the last pass): answer those without parsing their chapters again.
    local known, known_rev = {}, {}
    for _i, a in ipairs(locals) do
        if isHighlight(a) and type(a.grimmory_cfi) == "string" then
            known[key(a.pos0, a.pos1)] = a.grimmory_cfi
            known_rev[a.grimmory_cfi] = { a.pos0, a.pos1 }
        end
    end
    local CFI = {
        xpointerRangeToCFI = function(p0, p1)
            return known[key(p0, p1)] or Real.xpointerRangeToCFI(p0, p1)
        end,
        cfiRangeToXPointers = function(range)
            local k = known_rev[range]
            if k then return k[1], k[2] end
            return Real.cfiRangeToXPointers(range)
        end,
    }
    local result
    local done, crash = pcall(function()
        local items, rejected = AS.fromLocal(locals, CFI, tonumber(book_id))
        local cfi_of = {}
        for _i, it in ipairs(items) do
            local a = locals[it.index]
            if a and not a.grimmory_cfi then cfi_of[key(a.pos0, a.pos1)] = it.body.cfi end
        end
        local remote, gerr = api:listAnnotations(book_id)
        if type(remote) ~= "table" then result = { error = "list: " .. tostring(gerr) }; return end
        local plan = AS.plan(items, remote, shadow)
        local errors, conflicts = {}, plan.conflicts
        local counts = { created = 0, updated = 0, deleted = 0 }
        for _i, d in ipairs(plan.deletes) do
            if api:deleteAnnotation(d.id) then counts.deleted = counts.deleted + 1
            else errors[#errors + 1] = "delete " .. tostring(d.id); conflicts[tostring(d.id)] = "delete-failed" end
        end
        for _i, u in ipairs(plan.updates) do
            if api:updateAnnotation(u.id, u.body) then counts.updated = counts.updated + 1
            else errors[#errors + 1] = "update " .. tostring(u.id); conflicts[tostring(u.id)] = "update-failed" end
        end
        for _i, c in ipairs(plan.creates) do
            local made, _e, code = api:createAnnotation(c.body)
            -- 409: already there (an earlier reply was lost); the final list adopts it
            if made or code == 409 then counts.created = counts.created + 1
            else errors[#errors + 1] = "create " .. tostring(code or _e) end
        end
        local final, ferr = api:listAnnotations(book_id)
        if type(final) ~= "table" then
            result = { error = "final list: " .. tostring(ferr), conflicts = conflicts }
            return
        end
        -- the reverse conversions the merge on screen needs
        -- (chapter by chapter, so each is parsed once)
        local order = {}
        for _i, r in ipairs(final) do
            if type(r) == "table" and type(r.cfi) == "string" then order[#order + 1] = r end
        end
        local function step(r) return tonumber(r.cfi:match("^epubcfi%(/6/(%d+)")) or 0 end
        table.sort(order, function(x, y) return step(x) < step(y) end)
        local xps = {}
        for _i, r in ipairs(order) do
            if not xps[r.cfi] then
                local okc, p0, p1, cerr = pcall(CFI.cfiRangeToXPointers, r.cfi)
                if okc and p0 and p1 then xps[r.cfi] = { p0, p1 }
                else xps[r.cfi] = { false, tostring(okc and cerr or p0) } end
            end
        end
        result = { remote = final, conflicts = conflicts, errors = errors, rejected = #rejected,
            cfi_of = cfi_of, xps = xps, counts = counts }
    end)
    Real.clearCache()
    if not done then return nil, "crash: " .. tostring(crash) end
    if result.error then return nil, result.error end
    return result
end

---------------------------------------------------------------- on screen

--- A converter that answers from the background job's results.
local function answers(res, doc)
    return {
        xpointerRangeToCFI = function(p0, p1)
            local c = res.cfi_of and res.cfi_of[key(p0, p1)]
            if not c then error("not converted yet") end
            return c
        end,
        cfiRangeToXPointers = function(range)
            local x = res.xps and res.xps[range]
            if not x then return nil, nil, "not converted" end
            if not x[1] then return nil, nil, x[2] end
            if doc and doc.isXPointerInDocument
                    and not (doc:isXPointerInDocument(x[1]) and doc:isXPointerInDocument(x[2])) then
                return nil, nil, "not in this copy of the book"
            end
            return x[1], x[2]
        end,
    }
end

local function differs(a, b)
    if #a ~= #b then return true end
    for i = 1, #a do
        local x, y = a[i], b[i]
        if x ~= y then
            for _i, f in ipairs({ "grimmory_id", "pos0", "pos1", "color", "drawer", "note", "text" }) do
                if x[f] ~= y[f] then return true end
            end
        end
    end
    return false
end

function Anno:saveLocal(merged)
    local ui = self.ui
    if ui.document and ui.document.file == self.file and ui.annotation then
        -- in place: other parts of KOReader hold on to this table
        local list = ui.annotation.annotations
        if type(list) ~= "table" then list = {}; ui.annotation.annotations = list end
        for i = #list, 1, -1 do list[i] = nil end
        for i, item in ipairs(merged) do list[i] = item end
        merged = list
        pcall(ui.annotation.updateAnnotations, ui.annotation, true, true)
        if ui.doc_settings then
            ui.doc_settings:saveSetting("annotations", merged)
            pcall(ui.doc_settings.flush, ui.doc_settings)
        end
        if ui.view and ui.view.resetHighlightBoxesCache then pcall(ui.view.resetHighlightBoxesCache, ui.view) end
        UIManager:setDirty(ui.dialog or "all", "ui")
        return true
    end
    -- the book was closed meanwhile: write its settings file
    local ok = pcall(function()
        local ds = require("docsettings"):open(self.file)
        ds:saveSetting("annotations", merged)
        ds:saveSetting("annotations_externally_modified", true)
        ds:flush()
    end)
    return ok
end

function Anno:apply(res)
    local AS = require("gzreader_annosync")
    local ui = self.ui
    local open = ui.document and ui.document.file == self.file and ui.annotation
    local live
    if open then
        live = ui.annotation.annotations or {}
    else
        local ok, ds = pcall(function() return require("docsettings"):open(self.file) end)
        live = ok and ds:readSetting("annotations") or self.last_snapshot or {}
    end
    local conflicts = type(res.conflicts) == "table" and res.conflicts or {}
    local merged, conv_errors = AS.mergeLocal(live, res.remote, answers(res, open and ui.document), conflicts)
    local saved = true
    if differs(merged, live) then saved = self:saveLocal(merged) end
    local shadow = AS.shadowFor(res.remote)
    for id in pairs(conflicts) do shadow[id] = self.entry.anno_shadow[id] end
    self.entry.anno_shadow = shadow
    local nconf = 0
    for _id in pairs(conflicts) do nconf = nconf + 1 end
    self.entry.anno_dirty = (not saved or #(res.errors or {}) > 0 or (res.rejected or 0) > 0
        or #conv_errors > 0 or nconf > 0) or nil
    self.entry.anno_conflicts = nconf > 0 and nconf or nil
    self.plugin:save()
    local c = res.counts or {}
    local n_here = 0
    for _i, a in ipairs(merged) do if isHighlight(a) then n_here = n_here + 1 end end
    Log.info("highlights synced", self.book_id, "on Grimmory", #res.remote, "here", n_here,
        "sent: new", c.created or 0, "changed", c.updated or 0, "deleted", c.deleted or 0,
        "conflicts", nconf, "not convertible", #conv_errors + (res.rejected or 0),
        #(res.errors or {}) > 0 and ("errors: " .. table.concat(res.errors, ", ")) or "")
    return merged
end

--- Does our reading of the book's spine match crengine's? (checked once)
function Anno:spineOk()
    if self.spine_ok == nil then
        local ok, sp = pcall(self.sync.spine, self.sync)
        self.spine_ok = (ok and sp) and true or false
    end
    return self.spine_ok
end

--- One pass (in the background). on_done(ok) optional.
function Anno:run(on_done)
    if not self:enabled() then return on_done and on_done(false) end
    if self.busy then self.again = true; return end
    local Net = require("gzreader_net")
    if not Net.connected() then return on_done and on_done(false) end
    if not self:spineOk() then -- our spine doesn't match crengine's: don't guess
        Log.warn("highlights: book layout not understood, not synced", self.book_id)
        return on_done and on_done(false)
    end
    self.busy, self.again, self.touched = true, false, false
    local snapshot = self:snapshot()
    self.last_snapshot = snapshot
    local file, book_id, shadow = self.file, self.book_id, self.entry.anno_shadow
    require("gzreader_async").run(self.api, function(api)
        return Anno.work(api, file, book_id, snapshot, shadow)
    end, function(res, err)
        self.busy = false
        local ok = false
        if type(res) ~= "table" or type(res.remote) ~= "table" then
            Log.warn("highlight sync failed:", tostring(err))
            self.entry.anno_dirty = true
            self.plugin:save()
        elseif self.touched then
            -- changed on this Kindle while the job ran: start over from the new state
            self.again = true
        else
            local done, crash = pcall(self.apply, self, res)
            if not done then Log.warn("highlight merge failed:", tostring(crash)) else ok = true end
        end
        if self.again and not self.closed then
            self.again = false
            UIManager:scheduleIn(1, function() self:run(on_done) end)
            return
        end
        if on_done then on_done(ok) end
    end, "annotations", { nice = true, timeout = 600 })
end

--- KOReader event: a highlight or note was added, changed or removed.
function Anno:onAnnotationsModified(items)
    if self.applying or type(items) ~= "table" or items.gz_synced then return end
    if not isHighlight(items[1]) then return end -- page bookmarks: gzreader_bookmarks
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

--- The book is closing: send what's waiting (Wi-Fi only when needed: brought up quietly).
function Anno:onClose()
    if self.pending then UIManager:unschedule(self.pending); self.pending = nil end
    self.closed = true
    if not self.entry.anno_dirty or not self:enabled() then return end
    local Net = require("gzreader_net")
    self:spineOk() -- while the book is still open
    local snapshot = self:snapshot()
    self.snapshot = function() return snapshot end -- the book's highlights as it closed
    if Net.connected() then return self:run() end
    UIManager:scheduleIn(1, function()
        Net.run(function() self:run() end, { quiet = true, reason = "highlights on close" })
    end)
end

return Anno
