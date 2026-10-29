--[[--
Two-way bookmark sync with Grimmory's own bookmarks (the ones its web reader
shows), for books downloaded through the Grimmory tab.

Grimmory stores EPUB bookmarks as an EPUB CFI and PDF/CBZ bookmarks as a page
number. KOReader's page bookmarks ("dog-ears") are crengine XPointers, so for
EPUBs this converts between the two using the book's own XHTML (read from the
EPUB): /body/DocFragment[N]/body/div[2]/p[5] <-> epubcfi(/6/2s!/4/4/10).
Precision is the paragraph (element), which is what a page bookmark needs.

Highlights and notes are not synced (Grimmory's annotation model is
different); only bookmarks.

State kept per book in the download entry:
  entry.bookmarks = { [tostring(xp_or_page)] = grimmory_id }   -- synced pairs
  entry.bm_pending = { add = { [key]=true }, del = { [tostring(id)]=true } }  -- offline
]]

local Event = require("ui/event")
local NetworkMgr = require("ui/network/manager")
local Log = require("grimmory_log")
local _ = require("gettext")

local BM = {}
BM.__index = BM

---------------------------------------------------------------- XHTML

--- Minimal XHTML element tree: { tag = "p", kids = { ... } } (elements only).
function BM.parseXhtml(src)
    local root = { tag = "#root", kids = {} }
    local stack = { root }
    local i, n = 1, #src
    while i <= n do
        local lt = src:find("<", i, true)
        if not lt then break end
        if src:sub(lt, lt + 3) == "<!--" then
            local e = src:find("-->", lt + 4, true); i = e and e + 3 or n + 1
        elseif src:sub(lt, lt + 8) == "<![CDATA[" then
            local e = src:find("]]>", lt + 9, true); i = e and e + 3 or n + 1
        elseif src:sub(lt + 1, lt + 1) == "?" or src:sub(lt + 1, lt + 1) == "!" then
            local e = src:find(">", lt + 1, true); i = e and e + 1 or n + 1
        else
            -- find the end of the tag, skipping quoted attribute values
            local j, q = lt + 1, nil
            while j <= n do
                local c = src:sub(j, j)
                if q then if c == q then q = nil end
                elseif c == '"' or c == "'" then q = c
                elseif c == ">" then break end
                j = j + 1
            end
            local body = src:sub(lt + 1, j - 1)
            i = j + 1
            if body:sub(1, 1) == "/" then
                local name = body:match("^/%s*([%w_:%.%-]+)")
                name = name and name:gsub("^.*:", ""):lower()
                for k = #stack, 2, -1 do
                    if stack[k].tag == name then
                        for _r = #stack, k, -1 do stack[_r] = nil end
                        break
                    end
                end
            else
                local name = body:match("^([%w_:%.%-]+)")
                if name then
                    local node = { tag = name:gsub("^.*:", ""):lower(), kids = {} }
                    local parent = stack[#stack]
                    parent.kids[#parent.kids + 1] = node
                    if body:sub(-1) ~= "/" then stack[#stack + 1] = node end
                end
            end
        end
    end
    return root
end

local function child(node, tag)
    for i, k in ipairs(node and node.kids or {}) do
        if k.tag == tag then return k, i end
    end
end

---------------------------------------------------------------- conversion

--- spine = { all = {href,...}, frag = {href,...} }; read(href) -> xhtml
function BM.xpToCfi(xp, spine, read)
    local frag = tonumber(tostring(xp):match("^/body/DocFragment%[(%d+)%]"))
    local href = frag and spine.frag[frag]
    if not href then return nil end
    local s
    for i, h in ipairs(spine.all) do if h == href then s = i; break end end
    if not s then return nil end
    local cfi = { "/6/" .. (2 * s) .. "!" }
    local src = read(href)
    local doc = src and BM.parseXhtml(src)
    local html = doc and child(doc, "html")
    local body, bi = child(html, "body")
    if not body then return "epubcfi(" .. cfi[1] .. ")" end
    cfi[#cfi + 1] = "/" .. (2 * bi)
    local rest = xp:match("^/body/DocFragment%[%d+%]/body(.*)$") or ""
    local node = body
    for seg in rest:gmatch("/([^/]+)") do
        local name, idx = seg:match("^([%w_%-]+)%[(%d+)%]")
        if not name then name = seg:match("^([%w_%-]+)$") end
        if not name or name == "text" then break end
        idx = tonumber(idx) or 1
        local seen, found, pos = 0, nil, nil
        for p, k in ipairs(node.kids) do
            if k.tag == name:lower() then
                seen = seen + 1
                if seen == idx then found, pos = k, p; break end
            end
        end
        if not found then break end
        cfi[#cfi + 1] = "/" .. (2 * pos)
        node = found
    end
    return "epubcfi(" .. table.concat(cfi) .. ")"
end

function BM.cfiToXp(cfi, spine, read)
    local step, path = tostring(cfi):match("^epubcfi%(/6/(%d+)[^!]*!(.-)%)?$")
    step = tonumber(step)
    local href = step and spine.all[step / 2]
    if not href then return nil end
    local frag
    for i, h in ipairs(spine.frag) do if h == href then frag = i; break end end
    if not frag then return nil end
    local xp = "/body/DocFragment[" .. frag .. "]"
    local src = read(href)
    local doc = src and BM.parseXhtml(src)
    local node = doc and child(doc, "html")
    if not node then return xp end
    local first = true
    for num in (path or ""):gmatch("/(%d+)") do
        num = tonumber(num)
        if num % 2 == 1 then break end -- a text node: the element is precise enough
        local k = node.kids[num / 2]
        if not k then break end
        if first then
            first = false
            if k.tag ~= "body" then break end
            xp = xp .. "/body"
        else
            local same = 0
            for p = 1, num / 2 do if node.kids[p].tag == k.tag then same = same + 1 end end
            xp = xp .. "/" .. k.tag .. (same > 1 and ("[" .. same .. "]") or "")
        end
        node = k
    end
    return xp
end

---------------------------------------------------------------- sync

function BM:new(sync)
    local entry = sync.entry
    entry.bookmarks = entry.bookmarks or {}
    entry.bm_pending = entry.bm_pending or { add = {}, del = {} }
    return setmetatable({ sync = sync, ui = sync.ui, api = sync.api, entry = entry, plugin = sync.plugin }, self)
end

function BM:enabled()
    return self.plugin:syncEnabled() and self.plugin.store.bookmark_sync_disabled ~= true
end

local function isPageBookmark(item)
    return type(item) == "table" and not item.drawer and not item.pos0 and item.page ~= nil
end

function BM:reader(href)
    return self.ui.document:getDocumentFileContent(href)
end

--- Local key (xpointer / page) -> request body for Grimmory, or nil.
function BM:toRemote(item)
    local body = { bookId = tonumber(self.sync.book_id), title = item.chapter or item.text or _("Kindle bookmark") }
    if type(item.page) == "number" then
        body.pageNumber = item.page
        return body
    end
    local spine = self.sync:spine()
    if not spine then return nil end
    local ok, cfi = pcall(BM.xpToCfi, item.page, spine, function(h) return self:reader(h) end)
    if not ok or not cfi then return nil end
    body.cfi = cfi
    return body
end

function BM:toLocal(bm)
    if self.ui.rolling then
        if type(bm.cfi) ~= "string" then return nil end
        local spine = self.sync:spine()
        if not spine then return nil end
        local ok, xp = pcall(BM.cfiToXp, bm.cfi, spine, function(h) return self:reader(h) end)
        if not ok or not xp then return nil end
        local doc = self.ui.document
        if doc.isXPointerInDocument and not doc:isXPointerInDocument(xp) then
            xp = xp:match("^(/body/DocFragment%[%d+%])") -- chapter start
        end
        return xp
    end
    return tonumber(bm.pageNumber)
end

function BM:localBookmarks()
    local out = {}
    for _i, item in ipairs(self.ui.annotation and self.ui.annotation.annotations or {}) do
        if isPageBookmark(item) then out[tostring(item.page)] = item end
    end
    return out
end

function BM:addLocal(key, bm)
    self.applying = true
    local chapter = self.ui.toc and self.ui.toc:getTocTitleByPage(self.ui.rolling and key or tonumber(key))
    local page = self.ui.rolling and key or tonumber(key)
    local item = { page = page, chapter = chapter ~= "" and chapter or nil,
        text = bm.title ~= "" and bm.title or nil }
    local index = self.ui.annotation:addItem(item)
    self.ui:handleEvent(Event:new("AnnotationsModified", { item, index_modified = index }))
    self.applying = false
end

function BM:removeLocal(item)
    self.applying = true
    local idx
    for i, v in ipairs(self.ui.annotation.annotations) do if v == item then idx = i; break end end
    if idx then self.ui.bookmark:removeItemByIndex(idx) end
    self.applying = false
end

local function refreshDogear(ui)
    if ui.bookmark and ui.bookmark.setDogearVisibility then
        pcall(ui.bookmark.setDogearVisibility, ui.bookmark, ui.bookmark:getCurrentPageNumber())
    end
end

function BM:push(key, item)
    local body = self:toRemote(item)
    if not body then
        Log.warn("bookmark: can't convert", tostring(key))
        return
    end
    local made, err, code = self.api:createBookmark(body)
    if made and made.id then
        self.entry.bookmarks[key] = made.id
        self.entry.bm_pending.add[key] = nil
        Log.info("bookmark pushed", self.sync.book_id, body.cfi or body.pageNumber, "id", made.id)
    elseif code == 409 or code == 400 then
        self.entry.bm_pending.add[key] = nil -- already there; picked up on the next reconcile
        Log.info("bookmark exists on server", tostring(key), tostring(code))
    else
        self.entry.bm_pending.add[key] = true
        Log.warn("bookmark push failed", tostring(err))
    end
end

--- Bring both sides together. Called when the book opens and on "Sync now".
function BM:reconcile()
    if not self:enabled() or not NetworkMgr:isConnected() then return end
    local remote, err = self.api:listBookmarks(self.sync.book_id)
    if not remote then Log.warn("bookmark list failed", tostring(err)); return end
    -- deletes made offline
    for id in pairs(self.entry.bm_pending.del) do -- string ids
        if self.api:deleteBookmark(id) then self.entry.bm_pending.del[id] = nil end
    end
    local locals = self:localBookmarks()
    local remote_ids, added, removed, pushed = {}, 0, 0, 0
    local key_of_id = {}
    for k, id in pairs(self.entry.bookmarks) do key_of_id[tostring(id)] = k end
    for _i, bm in ipairs(remote) do
        if type(bm) == "table" and bm.id and not bm.positionMs and not self.entry.bm_pending.del[tostring(bm.id)] then
            remote_ids[tostring(bm.id)] = true
            if not key_of_id[tostring(bm.id)] then
                local key = self:toLocal(bm)
                key = key and tostring(key)
                if key then
                    if not locals[key] then self:addLocal(key, bm); added = added + 1 end
                    self.entry.bookmarks[key] = bm.id
                    locals[key] = locals[key] or true
                end
            end
        end
    end
    -- removed on another device / the web reader
    for key, id in pairs(self.entry.bookmarks) do
        if not remote_ids[tostring(id)] and not self.entry.bm_pending.del[tostring(id)] then
            self.entry.bookmarks[key] = nil
            if type(locals[key]) == "table" then self:removeLocal(locals[key]); removed = removed + 1 end
            locals[key] = nil
        end
    end
    -- made on this Kindle and not on Grimmory yet (including offline ones)
    for key, item in pairs(locals) do
        if type(item) == "table" and not self.entry.bookmarks[key] then
            self:push(key, item); pushed = pushed + 1
        end
    end
    self.plugin:save()
    if added + removed > 0 then refreshDogear(self.ui) end
    Log.info("bookmarks reconciled", self.sync.book_id, "remote", #remote, "added", added,
        "removed", removed, "pushed", pushed)
end

--- KOReader event: a bookmark was added (index > 0) or removed (index < 0).
function BM:onAnnotationsModified(items)
    if self.applying or type(items) ~= "table" then return end
    local item, idx = items[1], items.index_modified
    if not isPageBookmark(item) or not idx then return end
    local key = tostring(item.page)
    if idx > 0 then
        if not self:enabled() then return end
        if NetworkMgr:isConnected() then self:push(key, item)
        else self.entry.bm_pending.add[key] = true end
    else
        local id = self.entry.bookmarks[key]
        self.entry.bm_pending.add[key] = nil
        if id then
            self.entry.bookmarks[key] = nil
            if not (self:enabled() and NetworkMgr:isConnected() and self.api:deleteBookmark(id)) then
                self.entry.bm_pending.del[tostring(id)] = true
            end
            Log.info("bookmark removed", self.sync.book_id, tostring(id))
        end
    end
    self.plugin:save()
end

return BM
