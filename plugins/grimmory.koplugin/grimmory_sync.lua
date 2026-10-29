--[[--
Native Grimmory progress sync (no KOReader sync server involved).

Books are identified by their Grimmory book/file IDs, recorded when the book
is downloaded through this plugin. Positions are exchanged in the form
Grimmory's own web reader understands without a CFI:

* EPUB: chapter `positionHref` (spine item path inside the EPUB) plus the
  position within that chapter (`contentSourceProgressPercent`) and the
  whole-book percentage. `positionData` (the web reader's CFI) is left empty
  so the web reader restores by chapter + in-chapter position.
* PDF / comics: page number in `positionData`.
* Other reflowable formats (FB2, MOBI, AZW3): whole-book percentage.

Pull on open: jump forward silently; ask before jumping back, and only when
another device actually moved the position back (not when the server simply
holds an older copy of our own last push). Push on page turns (debounced),
on close and on sleep; queued while offline. Reading sessions are sent too,
which feeds Grimmory's reading statistics.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = require("ffi/util").template

local PUSH_EVERY_PAGES = 10
local PUSH_EVERY_SECONDS = 180
local MIN_SESSION_SECONDS = 30
local SAME_POSITION_PCT = 0.15

local Sync = {}
Sync.__index = Sync

function Sync:new(plugin, ui, entry, book_id)
    local o = setmetatable({
        plugin = plugin,
        api = plugin.api,
        ui = ui,
        entry = entry,
        book_id = tostring(book_id),
        pages_since_push = 0,
        last_push_time = os.time(),
    }, self)
    return o
end

---------------------------------------------------------------- helpers

local function isoNow(t)
    return os.date("!%Y-%m-%dT%H:%M:%SZ", t or os.time())
end

local function round1(x)
    return math.floor(x * 10 + 0.5) / 10
end

local function num(v) return type(v) == "number" and v or tonumber(v) end
local function str(v) return type(v) == "string" and v ~= "" and v or nil end

function Sync:isRolling()
    return self.ui.rolling ~= nil and self.ui.document.info.has_pages ~= true
end

function Sync:isEpub()
    local file = self.ui.document.file or ""
    return self:isRolling() and file:lower():match("%.epub$") ~= nil
end

function Sync.normalizeHref(href)
    if not href then return nil end
    href = href:gsub("#.*$", ""):gsub("^[%./]+", "")
    href = href:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    -- resolve "a/b/../c"
    local parts = {}
    for seg in href:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts)
        elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    return table.concat(parts, "/")
end

local function hrefsMatch(a, b)
    if not a or not b then return false end
    return a == b or a:sub(-(#b + 1)) == "/" .. b or b:sub(-(#a + 1)) == "/" .. a
end
Sync.hrefsMatch = hrefsMatch

--- Parse the EPUB's spine from inside the book (crengine reads zip members).
--- Returns { all = {href,...}, frag = {href,...} } where `frag[i]` is the
--- source file of crengine's DocFragment[i] (XHTML spine items only), or nil.
function Sync.parseSpine(read)
    local container = read("META-INF/container.xml")
    local opf_path = container and container:match("<[%w:]*rootfile[^>]-full%-path%s*=%s*[\"']([^\"']+)[\"']")
    if not opf_path then return nil end
    local opf = read(opf_path)
    if not opf then return nil end
    local base = opf_path:match("^(.*/)") or ""
    local manifest = {}
    for item in opf:gmatch("<[%w:]*item%s[^>]*>") do
        local id = item:match("%sid%s*=%s*[\"']([^\"']+)[\"']")
        local href = item:match("%shref%s*=%s*[\"']([^\"']+)[\"']")
        local mt = item:match("media%-type%s*=%s*[\"']([^\"']+)[\"']") or ""
        if id and href then manifest[id] = { href = Sync.normalizeHref(base .. href), media = mt } end
    end
    local all, frag = {}, {}
    local spine = opf:match("<[%w:]*spine[^>]*>(.-)</[%w:]*spine>") or ""
    for ref in spine:gmatch("<[%w:]*itemref%s[^>]*>") do
        local idref = ref:match("idref%s*=%s*[\"']([^\"']+)[\"']")
        local item = idref and manifest[idref]
        if item then
            all[#all + 1] = item.href
            if item.media:match("html") then frag[#frag + 1] = item.href end
        end
    end
    if #frag == 0 then return nil end
    return { all = all, frag = frag }
end

function Sync:spine()
    if self._spine ~= nil then return self._spine or nil end
    self._spine = false
    if not self:isEpub() then return nil end
    local doc = self.ui.document
    local ok, spine = pcall(Sync.parseSpine, function(p) return doc:getDocumentFileContent(p) end)
    if not ok or not spine then return nil end
    -- Safety net: our XHTML spine count must match crengine's fragments.
    local n = #spine.frag
    if not doc:isXPointerInDocument(T("/body/DocFragment[%1]", n))
            or doc:isXPointerInDocument(T("/body/DocFragment[%1]", n + 1)) then
        logger.warn("Grimmory sync: spine/fragment mismatch, using percentages only")
        Log.warn("sync: spine has", n, "xhtml items but crengine fragments differ; percentages only")
        return nil
    end
    self._spine = spine
    return spine
end

function Sync:fragmentRange(idx)
    local doc = self.ui.document
    local start = doc:getPosFromXPointer(T("/body/DocFragment[%1]", idx))
    local next_xp = T("/body/DocFragment[%1]", idx + 1)
    local stop = doc:isXPointerInDocument(next_xp) and doc:getPosFromXPointer(next_xp) or doc.info.doc_height
    return start, stop
end

---------------------------------------------------------------- local position

--- Current position as { pct, page, href, chapter_pct, xp }.
function Sync:localPosition()
    local doc = self.ui.document
    if not self:isRolling() then
        local page = self.ui.paging and self.ui.paging.current_page or 1
        local count = doc:getPageCount()
        return { pct = round1(page / math.max(count, 1) * 100), page = page }
    end
    local xp = doc:getXPointer()
    local pos = doc:getPosFromXPointer(xp)
    local height = math.max(doc.info.doc_height or 1, 1)
    local p = { pct = round1(pos / height * 100), xp = xp }
    local frag = tonumber(xp and xp:match("^/body/DocFragment%[(%d+)%]"))
    local spine = self:spine()
    if frag and spine and spine.frag[frag] then
        local start, stop = self:fragmentRange(frag)
        p.href = spine.frag[frag]
        p.chapter_pct = round1(math.max(0, math.min(100, (pos - start) / math.max(stop - start, 1) * 100)))
    end
    if self.ui.rolling and self.ui.rolling.getLastPercent then
        -- Use the reader's own figure in page mode so the footer and Grimmory agree.
        local ok, last = pcall(self.ui.rolling.getLastPercent, self.ui.rolling)
        if ok and type(last) == "number" then p.pct = round1(last * 100) end
    end
    return p
end

---------------------------------------------------------------- remote position

function Sync:remotePosition(book)
    local ep, pp, cp = book.epubProgress, book.pdfProgress, book.cbxProgress
    if self:isRolling() and type(ep) == "table" and num(ep.percentage) then
        return {
            pct = num(ep.percentage),
            href = str(ep.href),
            chapter_pct = num(ep.contentSourceProgressPercent),
            cfi = str(ep.cfi),
        }
    end
    local paged = type(pp) == "table" and pp or (type(cp) == "table" and cp or nil)
    if paged and num(paged.percentage) then
        return { pct = num(paged.percentage), page = num(paged.page) }
    end
end

--- Map a remote position to a crengine document position (pixels).
function Sync:targetPos(r)
    local doc = self.ui.document
    local height = doc.info.doc_height
    local by_pct = r.pct / 100 * height
    local spine = self:spine()
    local frag
    if spine and r.href then
        local want = Sync.normalizeHref(r.href)
        for i, h in ipairs(spine.frag) do
            if hrefsMatch(h, want) then frag = i break end
        end
    end
    if spine and not frag and r.cfi then
        -- epubcfi(/6/<2n>!...) -> nth spine itemref
        local step = tonumber(r.cfi:match("^epubcfi%(/%d+/(%d+)"))
        local href = step and spine.all[step / 2]
        if href then
            for i, h in ipairs(spine.frag) do
                if h == href then frag = i break end
            end
        end
    end
    if not frag then return by_pct end
    local start, stop = self:fragmentRange(frag)
    if r.chapter_pct then
        return start + r.chapter_pct / 100 * (stop - start)
    end
    -- Web reader positions carry no in-chapter offset: use the whole-book
    -- percentage when it lands inside that chapter, else the chapter start.
    if by_pct >= start and by_pct < stop then return by_pct end
    return start
end

function Sync:jumpTo(r)
    -- Not added to the "go back" location history: when a book opened at its
    -- first page and sync moved it, Back then jumped to the start of the book.
    if not self:isRolling() then
        local count = self.ui.document:getPageCount()
        local page = r.page or math.floor(r.pct / 100 * count + 0.5)
        page = math.max(1, math.min(count, page))
        self.ui:handleEvent(Event:new("GotoPage", page))
        return
    end
    local doc = self.ui.document
    local target = self:targetPos(r)
    if self.ui.view and self.ui.view.view_mode == "page" then
        -- Last page whose top is at or before the target position.
        local lo, hi = 1, doc:getPageCount()
        while lo < hi do
            local mid = math.floor((lo + hi + 1) / 2)
            local xp = doc:getPageXPointer(mid)
            if xp and doc:getPosFromXPointer(xp) <= target then lo = mid else hi = mid - 1 end
        end
        self.ui:handleEvent(Event:new("GotoPage", lo))
    else
        self.ui.rolling:_gotoPos(target)
    end
end

---------------------------------------------------------------- pull / push

function Sync:canTalk()
    return self.api:isPaired() and NetworkMgr:isConnected()
end

function Sync:pull(interactive)
    if not self.ui.document or self.plugin.sync ~= self then return end
    if not self:canTalk() then
        if interactive then self.plugin:showError("unreachable") end
        return
    end
    self.plugin:flushPending()
    local book, err = self.api:getBook(self.book_id)
    if not book then
        if interactive then self.plugin:showError(err) end
        return
    end
    local remote = self:remotePosition(book)
    local here = self:localPosition()
    if not remote or remote.pct <= 0 then
        if interactive then UIManager:show(InfoMessage:new{ text = _("No reading progress on Grimmory yet."), timeout = 3 }) end
        return
    end
    local diff = remote.pct - here.pct
    Log.info("sync pull book", self.book_id, "remote", remote.pct .. "%", remote.href or remote.cfi or "",
        "local", here.pct .. "%")
    if math.abs(diff) < SAME_POSITION_PCT then
        if interactive then UIManager:show(InfoMessage:new{ text = _("Already in sync with Grimmory."), timeout = 2 }) end
        return
    end
    local last = num(self.entry.last_pushed_pct)
    local is_our_echo = last and math.abs(remote.pct - last) < SAME_POSITION_PCT
    if diff > 0 and (not is_our_echo or interactive) then
        self:jumpTo(remote)
        self.entry.last_pushed_pct = remote.pct -- now in agreement
        self.plugin:save()
        UIManager:show(InfoMessage:new{ text = T(_("Jumped to %1% from Grimmory."), round1(remote.pct)), timeout = 2 })
    elseif diff < 0 and (not is_our_echo or interactive) then
        UIManager:show(ConfirmBox:new{
            text = T(_("Grimmory has an earlier position (%1%) than this Kindle (%2%), probably from another device. Go back to it?"),
                round1(remote.pct), round1(here.pct)),
            ok_text = _("Go back"),
            cancel_text = _("Stay here"),
            ok_callback = function()
                self:jumpTo(remote)
                self.entry.last_pushed_pct = remote.pct
                self.plugin:save()
            end,
            cancel_callback = function() self:push(true) end,
        })
    end
end

function Sync:progressBody(p)
    local fp = {
        bookFileId = tonumber(self.entry.file_id),
        progressPercent = p.pct,
    }
    if p.page then
        fp.positionData = tostring(p.page)
    elseif p.href then
        fp.positionHref = p.href
        fp.contentSourceProgressPercent = p.chapter_pct
    end
    -- positionData (web CFI) intentionally omitted for reflowable books: the
    -- server then clears any stale CFI and the web reader resumes from
    -- positionHref + contentSourceProgressPercent.
    return { fileProgress = fp }
end

function Sync:push(force)
    if not self.entry.file_id or not self.ui.document then return end
    local p = self:localPosition()
    local last = num(self.entry.last_pushed_pct)
    if not force and last and math.abs(p.pct - last) < 0.05 and self.entry.last_pushed_href == p.href then
        return
    end
    local body = self:progressBody(p)
    self.pages_since_push = 0
    self.last_push_time = os.time()
    if not self:canTalk() then
        self.plugin:queue("progress", self.book_id, body)
        return
    end
    local ok, perr = self.api:putProgress(self.book_id, body)
    Log.info("sync push book", self.book_id, p.pct .. "%", p.href or "", ok and "ok" or ("queued: " .. tostring(perr)))
    if ok then
        self.entry.last_pushed_pct = p.pct
        self.entry.last_pushed_href = p.href
        self.plugin:clearQueued("progress", self.book_id)
        -- we're evidently online: send anything queued while offline (the
        -- Kindle can bring Wi-Fi up without KOReader announcing it)
        UIManager:nextTick(function() self.plugin:flushPending() end)
    else
        self.plugin:queue("progress", self.book_id, body)
    end
    self.plugin:save()
end

---------------------------------------------------------------- sessions

function Sync:startSession()
    self.session = { start = os.time(), start_pct = self:localPosition().pct }
end

function Sync:endSession()
    local s = self.session
    self.session = nil
    if not s then return end
    local now = os.time()
    local duration = now - s.start
    if duration < MIN_SESSION_SECONDS then return end
    local end_pct = self:localPosition().pct
    local body = {
        bookId = tonumber(self.book_id),
        bookType = self.entry.format and self.entry.format:upper() or nil,
        startTime = isoNow(s.start),
        endTime = isoNow(now),
        durationSeconds = duration,
        startProgress = s.start_pct,
        endProgress = end_pct,
        progressDelta = round1(end_pct - s.start_pct),
    }
    if self:canTalk() and self.api:postSession(body) then return end
    self.plugin:queue("session", nil, body)
end

---------------------------------------------------------------- events

function Sync:onReady()
    self:startSession()
    UIManager:scheduleIn(2, function() self.plugin:flushPending() end)
    if self.plugin:syncEnabled() then
        -- let the first page render before talking to the network
        UIManager:scheduleIn(1, function() self:pull(false) end)
    end
end

function Sync:onPageTurned()
    self.pages_since_push = self.pages_since_push + 1
    if not self.plugin:syncEnabled() then return end
    if self.pages_since_push >= PUSH_EVERY_PAGES
            or os.time() - self.last_push_time >= PUSH_EVERY_SECONDS then
        if NetworkMgr:isConnected() then self:push(false) end
    end
end

function Sync:onLeave()
    if self.plugin:syncEnabled() then self:push(false) end
    self:endSession()
end

return Sync
