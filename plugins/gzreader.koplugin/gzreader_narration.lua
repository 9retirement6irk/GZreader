--[[--
Narrated EPUBs: a book with its own narration (EPUB 3 "media overlays", the
read-along books BookOrbit can send with their audio, or any EPUB 3 made
that way) plays its narration in the reader, with the sentence being read
highlighted and the pages turning by themselves.

- Quick panel → Narration (shown in a book that has narration): Play from
  this page, Pause / Resume, Stop.
- The book's SMIL files say which part of which audio file reads which
  sentence (a <par> with a <text src="chapter.xhtml#id"> and an
  <audio src clipBegin clipEnd>). Only those and the book's OPF are read;
  an audio file is copied out of the EPUB the first time it's played, into
  GZreader's cache (settings' cache/gz-narration), and played from there
  with the audiobook player (MP3 narration).
- The cache: a book's audio not played for 60 days is removed, and the
  oldest go first when it's over 2 GB (Narration.prune, at each start).
- BookOrbit leaves the narration out of a book sent to KOReader unless asked
  for the original file (its read-along books); a book without it simply
  has no Narration tile.
]]

local Log = require("gzreader_log")

local Narration = {
    TICK = 0.25,            -- s between looks at where the audio is
    JUMP = 1500,            -- ms: a gap this big between sentences: the player started again there
    KEEP_DAYS = 60,         -- a book's audio not played for this long is removed
    MAX_BYTES = 2 * 1024 * 1024 * 1024, -- the cache's most
    books = {},             -- [epub path] = the book's narration (parsed once a run)
    current = nil,          -- the narration playing (or paused)
}

---------------------------------------------------------------- reading the book (pure)

--- A SMIL clock value in milliseconds: "0:01:02.5", "01:02.5", "12.3s",
--- "500ms", "2min", "1h", "12.345". nil when it isn't one.
function Narration.clock(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    local h, m, s = v:match("^(%d+):(%d%d):(%d%d%.?%d*)$")
    if h then return math.floor((tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)) * 1000 + 0.5) end
    m, s = v:match("^(%d+):(%d%d%.?%d*)$")
    if m then return math.floor((tonumber(m) * 60 + tonumber(s)) * 1000 + 0.5) end
    local n, unit = v:match("^(%d*%.?%d+)%s*(%a*)$")
    n = tonumber(n)
    if not n then return nil end
    local mult = ({ [""] = 1000, s = 1000, ms = 1, min = 60000, h = 3600000 })[unit]
    if not mult then return nil end
    return math.floor(n * mult + 0.5)
end

--- `href` (relative to the file at `from`) as a path in the EPUB: "../"
--- and "./" worked out, the "#fragment" and any %-escapes taken off.
function Narration.resolve(from, href)
    href = (href or ""):gsub("#.*$", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    if href:sub(1, 1) == "/" then href = href:sub(2) end
    local base = (from or ""):match("^(.*)/[^/]*$") or ""
    local parts = {}
    for p in ((base ~= "" and (base .. "/") or "") .. href):gmatch("[^/]+") do
        if p == ".." then table.remove(parts) elseif p ~= "." then parts[#parts + 1] = p end
    end
    return table.concat(parts, "/")
end

local function attrs(tag)
    local a = {}
    for k, v in tag:gmatch('([%w:_%-]+)%s*=%s*"([^"]*)"') do a[k] = v end
    for k, v in tag:gmatch("([%w:_%-]+)%s*=%s*'([^']*)'") do a[k] = a[k] or v end
    return a
end

local function unescape(s)
    return (s:gsub("&amp;", "&"):gsub("&apos;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"))
end

--- The OPF's path, from META-INF/container.xml.
function Narration.parseContainer(xml)
    for tag in (xml or ""):gmatch("<[%w:]*rootfile%s[^>]*>") do
        local a = attrs(tag)
        if a["full-path"] then return unescape(a["full-path"]) end
    end
    return nil
end

--- The OPF: the spine, in order, each { href (path in the EPUB), smil (its
--- narration's path, or nil), index (0-based, as crengine counts them) }.
function Narration.parseOpf(xml, opf_path)
    xml = xml or ""
    local items = {}
    for tag in xml:gmatch("<[%w:]*item%s[^>]*>") do
        local a = attrs(tag)
        if a.id and a.href then
            items[a.id] = { href = Narration.resolve(opf_path, unescape(a.href)), type = a["media-type"], overlay = a["media-overlay"] }
        end
    end
    local spine = {}
    local body = xml:match("<[%w:]*spine[^>]*>(.-)</[%w:]*spine>") or ""
    for tag in body:gmatch("<[%w:]*itemref%s[^>]*>") do
        local a = attrs(tag)
        local it = a.idref and items[a.idref]
        if it then
            local ov = it.overlay and items[it.overlay]
            spine[#spine + 1] = { href = it.href, smil = ov and ov.href or nil, index = #spine }
        end
    end
    return spine
end

--- A SMIL file's sentences, in order: { file (the chapter's path), id, audio
--- (path), b, e (ms) }. Nested <seq>s are read through.
function Narration.parseSmil(xml, smil_path)
    local pars = {}
    for par in (xml or ""):gmatch("<[%w:]*par[%s>].-</[%w:]*par>") do
        local text = par:match("<[%w:]*text%s[^>]*>")
        local audio = par:match("<[%w:]*audio%s[^>]*>")
        local ta, aa = text and attrs(text), audio and attrs(audio)
        if ta and aa and ta.src and aa.src then
            local id = ta.src:match("#(.+)$")
            local b = Narration.clock(aa.clipBegin or aa["clip-begin"] or "0") or 0
            local e = Narration.clock(aa.clipEnd or aa["clip-end"] or "")
            if id then
                pars[#pars + 1] = { file = Narration.resolve(smil_path, unescape(ta.src)), id = unescape(id),
                    audio = Narration.resolve(smil_path, unescape(aa.src)), b = b, e = e }
            end
        end
    end
    return pars
end

--- Where crengine keeps the element with `id` in the spine's `index`th
--- file: its link form ("#_doc_fragment_<index>_ <id>").
function Narration.linkFor(index, id)
    return "#_doc_fragment_" .. tostring(index) .. "_ " .. tostring(id)
end

--- The book's narration from its parts: { pars (in reading order, each with
--- `index`, the spine's), duration (ms per audio file: its last clip's end) }.
function Narration.build(spine, smils)
    local pars, duration = {}, {}
    local seen = {}
    for _i, s in ipairs(spine) do
        if s.smil and smils[s.smil] and not seen[s.smil] then
            seen[s.smil] = true
            for _k, p in ipairs(smils[s.smil]) do
                -- (the spine item the sentence is in: usually this one)
                local index = s.index
                for _m, t in ipairs(spine) do if t.href == p.file then index = t.index; break end end
                p.index = index
                pars[#pars + 1] = p
                if p.e then duration[p.audio] = math.max(duration[p.audio] or 0, p.e) end
            end
        end
    end
    -- (a sentence with no end: up to the next one's start in the same file)
    for i, p in ipairs(pars) do
        if not p.e then
            local n = pars[i + 1]
            p.e = (n and n.audio == p.audio and n.b > p.b) and n.b or (p.b + 5000)
        end
    end
    return { pars = pars, duration = duration }
end

--- The sentence playing at `pos` ms of audio `audio`, from `from` on: its
--- index; or nil and the next one's (past the last in this stretch of the
--- audio: another file's turn, or a jump to another place in it).
function Narration.at(pars, from, audio, pos)
    local i = from
    while pars[i] and pars[i].audio == audio do
        if pos < pars[i].e then return i end
        local n = pars[i + 1]
        if not n or n.audio ~= audio or math.abs(n.b - pars[i].e) > Narration.JUMP then return nil, i + 1 end
        i = i + 1
    end
    return nil, i
end

---------------------------------------------------------------- the EPUB

local function Archiver() return require("ffi/archiver") end

--- The narration of the EPUB at `path`: { pars, duration, path }, or nil.
function Narration.load(path)
    if type(path) ~= "string" or not path:lower():match("%.epub$") then return nil end
    local cached = Narration.books[path]
    if cached ~= nil then return cached or nil end
    local ok, book = pcall(function()
        local r = Archiver().Reader:new()
        if not r:open(path) then return nil end
        for _e in r:iterate() do end -- (the entries' list: libarchive finds a file by it)
        local function read(name) return name and r:extractToMemory(name) or nil end
        local opf = Narration.parseContainer(read("META-INF/container.xml"))
        local spine = opf and Narration.parseOpf(read(opf), opf) or {}
        local smils, any = {}, false
        for _i, s in ipairs(spine) do
            if s.smil and not smils[s.smil] then
                smils[s.smil] = Narration.parseSmil(read(s.smil), s.smil)
                any = any or #smils[s.smil] > 0
            end
        end
        r:close()
        if not any then return nil end
        local b = Narration.build(spine, smils)
        b.path = path
        return b
    end)
    if not ok then Log.warn("narration: the book couldn't be read:", tostring(book)) end
    book = ok and book or nil
    Narration.books[path] = book or false
    if book then Log.info("narration: the book has", #book.pars, "narrated sentences") end
    return book
end

--- The book open in `ui` has narration.
function Narration.available(ui)
    local doc = ui and ui.document
    if not doc or not doc.file or (doc.info and doc.info.has_pages) then return false end
    return Narration.load(doc.file) ~= nil
end

---------------------------------------------------------------- the cache

function Narration.cacheDir()
    if Narration.CACHE_DIR then return Narration.CACHE_DIR end -- (tests)
    return require("datastorage"):getDataDir() .. "/cache/gz-narration"
end

local function bookDir(path)
    local md5 = require("ffi/sha2").md5
    return Narration.cacheDir() .. "/" .. md5(path)
end

--- The audio file `audio` (a path in the EPUB) on disk, copied out the
--- first time; nil when it can't be.
function Narration.audioFile(book, audio)
    local lfs = require("libs/libkoreader-lfs")
    local dir = bookDir(book.path)
    local name = audio:gsub("[^%w%._%-]", "_")
    local out = dir .. "/" .. name
    if lfs.attributes(out, "mode") ~= "file" then
        lfs.mkdir(Narration.cacheDir())
        lfs.mkdir(dir)
        local ok, done = pcall(function()
            local r = Archiver().Reader:new()
            if not r:open(book.path) then return false end
            for _e in r:iterate() do end
            local res = r:extractToPath(audio, out)
            r:close()
            return res
        end)
        if not ok or not done or lfs.attributes(out, "mode") ~= "file" then
            Log.warn("narration: the audio couldn't be copied out of the book:", tostring(done))
            os.remove(out)
            return nil
        end
        Log.info("narration: audio copied out of the book,", lfs.attributes(out, "size"), "bytes")
    end
    -- (played now: kept another 60 days)
    local f = io.open(dir .. "/.used", "w")
    if f then f:write(tostring(os.time())); f:close() end
    return out
end

--- The cache trimmed: books not played for KEEP_DAYS removed, then the
--- oldest until it's under MAX_BYTES. Returns how many books' audio went.
function Narration.prune(now)
    local lfs = require("libs/libkoreader-lfs")
    now = now or os.time()
    local root = Narration.cacheDir()
    if lfs.attributes(root, "mode") ~= "directory" then return 0 end
    local books, total = {}, 0
    for name in lfs.dir(root) do
        local dir = root .. "/" .. name
        if name:sub(1, 1) ~= "." and lfs.attributes(dir, "mode") == "directory" then
            local f = io.open(dir .. "/.used")
            local used = f and tonumber(f:read("*a")) or (lfs.attributes(dir, "modification") or now)
            if f then f:close() end
            local size = 0
            for file in lfs.dir(dir) do
                if file ~= "." and file ~= ".." then size = size + (lfs.attributes(dir .. "/" .. file, "size") or 0) end
            end
            books[#books + 1] = { dir = dir, used = used, size = size }
            total = total + size
        end
    end
    table.sort(books, function(a, b) return a.used < b.used end)
    local gone = 0
    local function remove(b)
        for file in lfs.dir(b.dir) do
            if file ~= "." and file ~= ".." then os.remove(b.dir .. "/" .. file) end
        end
        lfs.rmdir(b.dir)
        total = total - b.size
        gone = gone + 1
    end
    for _i, b in ipairs(books) do
        if now - b.used > Narration.KEEP_DAYS * 86400 then remove(b); b.gone = true end
    end
    for _i, b in ipairs(books) do
        if total <= Narration.MAX_BYTES then break end
        if not b.gone then remove(b) end
    end
    if gone > 0 then Log.info("narration: audio of", gone, "books removed from the cache") end
    return gone
end

---------------------------------------------------------------- playing

local function now() return require("ui/time").to_s(require("ui/time").now()) end
local function UIManager() return require("ui/uimanager") end
local function Engine() return require("gzreader_audioengine") end

local Player = {}
Player.__index = Player

--- The element of sentence `p` in the book: its xpointer, or nil.
function Player:xpOf(p)
    if p.xp ~= nil then return p.xp or nil end
    local doc = self.ui.document
    local link = Narration.linkFor(p.index, p.id)
    local ok, xp = pcall(function()
        if not doc:isXPointerInDocument(link) then return nil end
        return doc:getNormalizedXPointer(link)
    end)
    p.xp = ok and xp or false
    return p.xp or nil
end

--- The first sentence on the page shown (or after it).
function Player:firstOnPage()
    local doc = self.ui.document
    local page_xp = doc:getXPointer()
    local frag = tonumber(tostring(page_xp):match("DocFragment%[(%d+)%]"))
    for i, p in ipairs(self.book.pars) do
        if not frag or p.index >= frag - 1 then
            local xp = self:xpOf(p)
            if xp then
                if doc:isXPointerInCurrentPage(xp) then return i end
                local okc, c = pcall(doc.compareXPointers, doc, page_xp, xp)
                if okc and c and c > 0 then return i end
            end
        end
    end
    return 1
end

function Player:highlight(p)
    local doc = self.ui.document
    local xp = self:xpOf(p)
    if not xp then return end
    local text = doc:getTextFromXPointer(xp) or ""
    -- (the sentence's own text: its element's first text, to the length of all of it)
    local xp1 = xp .. "/text()." .. tostring(#require("util").splitToChars(text))
    if not doc:isXPointerInDocument(xp1) then xp1 = xp end
    pcall(doc.getTextFromXPointers, doc, xp .. "/text().0", xp1, true)
    -- (pages turn with the narration)
    for _i = 1, 3 do
        if doc:isXPointerInCurrentPage(xp) then break end
        self.ui:handleEvent(require("ui/event"):new("GotoViewRel", 1))
    end
    if not doc:isXPointerInCurrentPage(xp) then self.ui:handleEvent(require("ui/event"):new("GotoXPointer", xp, xp)) end
    UIManager():setDirty(self.ui.dialog, "ui")
end

function Player:clearHighlight()
    pcall(self.ui.document.clearSelection, self.ui.document)
    UIManager():setDirty(self.ui.dialog, "ui")
end

--- Start the audio at sentence i. False when it can't play.
function Player:startAt(i)
    local p = self.book.pars[i]
    if not p then return false end
    local file = Narration.audioFile(self.book, p.audio)
    if not file then return false end
    local E = Engine()
    local fmt = E.format(file)
    local pl = E.chosen(fmt)
    if not pl then
        self.missing = fmt
        return false
    end
    local lfs = require("libs/libkoreader-lfs")
    local src = { kind = "file", path = file, offset_ms = p.b, size = lfs.attributes(file, "size"),
        duration_ms = self.book.duration[p.audio] }
    local Music = package.loaded["gzreader_music"]
    if Music then pcall(Music.pauseAll) end
    local started = select(2, E.play(pl, src, "narration"))
    self.audio, self.base, self.t0 = p.audio, started or p.b, now()
    self.i = i
    self:highlight(p)
    return true
end

--- Where the audio is (ms in its file).
function Player:pos()
    if self.paused_at then return self.base + (self.paused_at - self.t0) * 1000 end
    return self.base + (now() - self.t0) * 1000
end

function Player:tick()
    if not self.playing or self.paused_at then return end
    local i, next_i = Narration.at(self.book.pars, self.i, self.audio, self:pos())
    if i then
        if i ~= self.i then self.i = i; self:highlight(self.book.pars[i]) end
    elseif next_i and self.book.pars[next_i] then
        -- another audio file, or a jump in the audio: start again there
        if not self:startAt(next_i) then return self:stop("the next audio couldn't be played") end
    else
        return self:stop("the end of the narration")
    end
    if not Engine().running() and self.playing and not self.paused_at then
        -- (the player stopped by itself before the sentence's end: on with the next)
        local n = self.book.pars[self.i + 1]
        if n then
            if not self:startAt(self.i + 1) then return self:stop("the player stopped") end
        else
            return self:stop("the end of the narration")
        end
    end
    UIManager():scheduleIn(Narration.TICK, self.ticker)
end

function Player:pause()
    if not self.playing or self.paused_at then return end
    self.paused_at = now()
    Engine().stop() -- (stopped, its place kept: the Kindle 3's sound comes back from that)
    Log.info("narration: paused")
end

function Player:resume()
    if not self.paused_at then return end
    local i = self.i
    self.paused_at = nil
    self:startAt(i)
    UIManager():scheduleIn(Narration.TICK, self.ticker)
    Log.info("narration: resumed")
end

function Player:stop(why)
    if not self.playing then return end
    self.playing = false
    UIManager():unschedule(self.ticker)
    Engine().stop()
    self:clearHighlight()
    pcall(function() require("gzreader_awake").release("narration") end)
    if Narration.current == self then Narration.current = nil end
    Log.info("narration: stopped", why and ("(" .. why .. ")") or "")
end

--- Play the narration of the book open in `ui` from the page shown.
function Narration.play(ui)
    local book = Narration.load(ui and ui.document and ui.document.file)
    if not book then return false, "none" end
    if Narration.current then Narration.current:stop("started again") end
    pcall(Narration.prune)
    local self = setmetatable({ ui = ui, book = book, playing = true }, Player)
    self.ticker = function() self:tick() end
    local i = self:firstOnPage()
    if not self:startAt(i) then
        self.playing = false
        return false, self.missing and "player" or "audio", self.missing
    end
    Narration.current = self
    pcall(function()
        require("gzreader_awake").hold("narration", { what = "narration", still = function() return Narration.current == self end })
    end)
    UIManager():scheduleIn(Narration.TICK, self.ticker)
    Log.info("narration: playing from sentence", i, "of", #book.pars)
    return true
end

function Narration.stop(why) if Narration.current then Narration.current:stop(why) end end

---------------------------------------------------------------- the quick panel

--- Its tile in a book with narration (nil otherwise).
function Narration.tile(plugin, ui)
    if not Narration.available(ui) then return nil end
    local _ = require("gettext")
    local cur = Narration.current
    local playing = cur and cur.ui == ui and cur.playing and not cur.paused_at
    return { id = "narration", icon = "narration", label = playing and _("Narration ▶") or _("Narration"), on = playing == true,
        run = function() Narration.menu(ui) end }
end

function Narration.menu(ui)
    local _ = require("gettext")
    local ButtonDialog = require("ui/widget/buttondialog")
    local cur = Narration.current
    local d
    local function close() UIManager():close(d) end
    local buttons = {}
    buttons[#buttons + 1] = { { text = _("Play from this page"), callback = function()
        close()
        local ok, why, fmt = Narration.play(ui)
        if not ok then
            local InfoMessage = require("ui/widget/infomessage")
            local T = require("ffi/util").template
            local text = why == "player" and T(_("No player has been found for %1 audio on this Kindle yet: run Settings → Audio → Test audiobook playback first."), (fmt or "?"):upper())
                or _("The narration couldn't be played (its audio couldn't be copied out of the book).")
            UIManager():show(InfoMessage:new{ text = text })
        end
    end } }
    if cur and cur.playing then
        if cur.paused_at then
            buttons[#buttons + 1] = { { text = _("Resume"), callback = function() close(); cur:resume() end } }
        else
            buttons[#buttons + 1] = { { text = _("Pause"), callback = function() close(); cur:pause() end } }
        end
        buttons[#buttons + 1] = { { text = _("Stop"), callback = function() close(); cur:stop("stopped by you") end } }
    end
    d = ButtonDialog:new{ title = _("Narration"), buttons = buttons }
    UIManager():show(d)
    return d
end

return Narration
