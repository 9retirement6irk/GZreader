--[[--
Native Grimmory progress sync (no KOReader sync server involved).

Books are identified by their Grimmory book/file IDs, recorded when the book
is downloaded through this plugin.

* EPUB: the exact place as an EPUB CFI in `positionData` (what Grimmory's web
  reader, foliate-js, resumes from), made from the page's crengine XPointer
  with grimmory_cfi; plus the chapter `positionHref` and the position within
  it (`contentSourceProgressPercent`) as a fallback. Until 1.1.0 no CFI was
  sent and the web reader opened at the start of the chapter.
  The percentage sent is worked out the way foliate-js does it (each spine
  file counts by its size in bytes, non-linear ones not at all), so Grimmory
  shows the same figure as its web reader on that page. KOReader's own
  footer counts rendered height, so it differs (11% here, 15% there).
  Pulling, a CFI from the web reader is turned back into an XPointer and the
  Kindle goes to that exact place; decisions (ahead, behind, same page) use
  KOReader's positions on both sides.
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
local Async = require("gzreader_async")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Log = require("gzreader_log")
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
--- source file of crengine's DocFragment[i], or nil. crengine makes a
--- fragment for every spine item (image and SVG pages too; checked on the
--- Kindle 3's crengine), so the two lists are the same.
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
    local all, frag, linear = {}, {}, {}
    local spine = opf:match("<[%w:]*spine[^>]*>(.-)</[%w:]*spine>") or ""
    for ref in spine:gmatch("<[%w:]*itemref%s[^>]*>") do
        local idref = ref:match("idref%s*=%s*[\"']([^\"']+)[\"']")
        local item = idref and manifest[idref]
        if item then
            all[#all + 1] = item.href
            frag[#frag + 1] = item.href
            linear[#frag] = not ref:match("linear%s*=%s*[\"']no[\"']")
        end
    end
    if #frag == 0 then return nil end
    return { all = all, frag = frag, linear = linear }
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
        Log.warn("sync: spine has", n, "items but crengine fragments differ; percentages only")
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
        p.chapter_frac = math.max(0, math.min(1, (pos - start) / math.max(stop - start, 1)))
        p.chapter_pct = round1(p.chapter_frac * 100)
    end
    if self.ui.rolling and self.ui.rolling.getLastPercent then
        local ok, last = pcall(self.ui.rolling.getLastPercent, self.ui.rolling)
        if ok and type(last) == "number" then p.pct = round1(last * 100) end
    end
    p.local_pct = p.pct -- KOReader's figure (the footer's)
    p.pos = pos
    if frag and p.chapter_frac then
        local web = self:webPercent(frag, p.chapter_frac)
        if web then p.pct = round1(web) end
    end
    return p
end

---------------------------------------------------------------- web reader's percentage

--- Uncompressed size of each spine item, from the EPUB's zip directory
--- (cached per book file).
function Sync:spineSizes()
    if self._sizes ~= nil then return self._sizes or nil end
    self._sizes = false
    local spine = self:spine()
    local file = self.ui.document.file
    if not spine or not file then return nil end
    local lfs = require("libs/libkoreader-lfs")
    local attr = lfs.attributes(file) or {}
    local sig = tostring(attr.size) .. ":" .. tostring(attr.modification)
    local c = self.entry.spine_sizes
    if type(c) == "table" and c.sig == sig and type(c.sizes) == "table" and #c.sizes == #spine.frag then
        self._sizes = c.sizes
        return c.sizes
    end
    local by_path = Sync.archiveSizes(file)
    local sizes = {}
    for i, href in ipairs(spine.frag) do
        local n = by_path and by_path[href]
        if not n then
            local ok, content = pcall(self.ui.document.getDocumentFileContent, self.ui.document, href)
            n = ok and type(content) == "string" and #content or 0
        end
        sizes[i] = (spine.linear and spine.linear[i] == false) and 0 or n
    end
    local total = 0
    for _i, n in ipairs(sizes) do total = total + n end
    if total <= 0 then return nil end
    self.entry.spine_sizes = { sig = sig, sizes = sizes }
    self._sizes = sizes
    return sizes
end

--- { [path] = uncompressed size } of a zip, or nil.
function Sync.archiveSizes(file)
    local ok, out = pcall(function()
        local Archiver = require("ffi/archiver")
        local r = Archiver.Reader:new()
        if not r:open(file) then return nil end
        local t = {}
        for e in r:iterate() do
            if e.mode == "file" then t[e.path] = tonumber(e.size) end
        end
        r:close()
        return t
    end)
    return ok and out or nil
end

--- Book percentage the way Grimmory's web reader (foliate-js) counts it:
--- spine files by size, `frac` of the way through file `frag`.
function Sync:webPercent(frag, frac)
    local sizes = self:spineSizes()
    if not sizes or not sizes[frag] then return nil end
    local total, before = 0, 0
    for i, n in ipairs(sizes) do
        total = total + n
        if i < frag then before = before + n end
    end
    if total <= 0 then return nil end
    frac = math.max(0, math.min(1, frac or 0))
    return (before + sizes[frag] * frac) / total * 100
end

---------------------------------------------------------------- CFI

--- This book's own copy of grimmory_cfi (its state is per book).
function Sync:cfiConverter()
    if self._cfi ~= nil then return self._cfi or nil end
    self._cfi = false
    if not self:isEpub() then return nil end
    local ok, conv = pcall(function()
        local path = package.searchpath("gzreader_cfi", package.path)
        local mod = assert(loadfile(path))()
        assert(mod.initBook(self.ui.document.file, Sync.cfiReader and Sync.cfiReader(self.ui.document.file)))
        return mod
    end)
    if ok then self._cfi = conv else Log.warn("sync: no CFI converter:", tostring(conv)) end
    return self._cfi or nil
end

function Sync:releaseCfi()
    if self._cfi then pcall(self._cfi.clearCache) end
    self._cfi = nil
end

--- EPUB CFI of an XPointer, or nil.
function Sync:cfiOf(xp)
    local conv = xp and self:cfiConverter()
    if not conv then return nil end
    local ok, cfi = pcall(conv.xpointerToCFI, xp)
    return ok and type(cfi) == "string" and cfi or nil
end

--- XPointer of a (point or range) CFI from the web reader, or nil.
function Sync:xpOf(cfi)
    local conv = cfi and self:cfiConverter()
    if not conv then return nil end
    local ok, xp = pcall(conv.cfiToXPointer, cfi)
    if not ok or type(xp) ~= "string" then return nil end
    local doc = self.ui.document
    if doc.isXPointerInDocument and not doc:isXPointerInDocument(xp) then return nil end
    return xp
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
    if r.cfi then
        local xp = self:xpOf(r.cfi)
        local pos = xp and doc:getPosFromXPointer(xp)
        if pos then return pos, true end
    end
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
    if interactive then
        local book, err = self.api:getBook(self.book_id)
        return self:applyRemote(book, true, err)
    end
    -- opening / waking: fetch in the background so the page shows right away
    Async.call(self.api, "getBook", { self.book_id }, function(book, err)
        if not self.ui.document or self.plugin.sync ~= self then return end
        self:applyRemote(book, false, err)
    end)
end

--- Act on Grimmory's record of the book (from pull).
function Sync:applyRemote(book, interactive, err)
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
    -- compare on KOReader's scale: where the remote place is in this book
    local remote_local = remote.pct
    local exact = false
    if self:isRolling() and here.pos then
        local target
        target, exact = self:targetPos(remote)
        local height = math.max(self.ui.document.info.doc_height or 1, 1)
        if target then remote_local = round1(target / height * 100) end
        remote.local_pct = remote_local
        here.pct = round1(here.pos / height * 100)
        local page_h = (self.ui.document.getPageHeight and pcall(self.ui.document.getPageHeight, self.ui.document)
            and self.ui.document:getPageHeight()) or nil
        if target and page_h and math.abs(target - here.pos) < page_h / 2 then
            remote_local = here.pct -- same page
        end
    end
    local diff = remote_local - here.pct
    Log.info("sync pull book", self.book_id, "remote", remote.pct .. "%", "(here " .. remote_local .. "%" .. (exact and ", from its CFI)" or ")"),
        remote.href or remote.cfi or "", "local", here.pct .. "%")
    if math.abs(diff) < SAME_POSITION_PCT then
        if interactive then UIManager:show(InfoMessage:new{ text = _("Already in sync with Grimmory."), timeout = 2 }) end
        return
    end
    local last = num(self.entry.last_pushed_pct)
    local is_our_echo = (remote.cfi and self.entry.last_pushed_cfi == remote.cfi)
        or (last and math.abs(remote.pct - last) < SAME_POSITION_PCT)
    if diff > 0 and (not is_our_echo or interactive) then
        self:jumpTo(remote)
        self.entry.last_pushed_pct = remote.pct -- now in agreement
        self.plugin:save()
        UIManager:show(InfoMessage:new{ text = T(_("Jumped to %1% from Grimmory."), round1(remote_local)), timeout = 2 })
    elseif diff < 0 and (not is_our_echo or interactive) then
        UIManager:show(ConfirmBox:new{
            text = T(_("Grimmory has an earlier position (%1%) than this Kindle (%2%), probably from another device. Go back to it?"),
                round1(remote_local), round1(here.pct)),
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
        fp.positionData = p.cfi -- the exact place for the web reader (nil: href + %)
    end
    return { fileProgress = fp }
end

function Sync:push(force, background)
    if not self.entry.file_id or not self.ui.document then return end
    local p = self:localPosition()
    local last = num(self.entry.last_pushed_pct)
    if not force and last and math.abs(p.pct - last) < 0.05 and self.entry.last_pushed_href == p.href then
        return
    end
    if p.xp and p.href then p.cfi = self:cfiOf(p.xp) end
    local body = self:progressBody(p)
    self.pages_since_push = 0
    self.last_push_time = os.time()
    if not self:canTalk() then
        self.plugin:queue("progress", self.book_id, body)
        return
    end
    local function done(ok, perr)
        Log.info("sync push book", self.book_id, p.pct .. "%", p.href or "", ok and "ok" or ("queued: " .. tostring(perr)))
        if ok then
            self.entry.last_pushed_pct = p.pct
            self.entry.last_pushed_href = p.href
            self.entry.last_pushed_cfi = p.cfi
            self.plugin:clearQueued("progress", self.book_id)
            -- we're evidently online: send anything queued while offline (the
            -- Kindle can bring Wi-Fi up without KOReader announcing it)
            UIManager:nextTick(function() self.plugin:flushPending() end)
        else
            self.plugin:queue("progress", self.book_id, body)
        end
        self.plugin:save()
    end
    if background then
        -- page turns: don't make the page wait for Grimmory
        return Async.call(self.api, "putProgress", { self.book_id, body }, done)
    end
    done(self.api:putProgress(self.book_id, body))
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
    if self:canTalk() then
        local ok, perr, code = self.api:postSession(body)
        if ok then return end
        Log.info("reading session queued:", tostring(perr))
        -- no HTTP answer (timeout, dropped): Grimmory may have saved it anyway
        if not code then body.gz_tries = 1 end
    end
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
        if NetworkMgr:isConnected() then self:push(false, true) end
    end
end

function Sync:onLeave()
    if self.plugin:syncEnabled() then self:push(false) end
    self:endSession()
end

return Sync
