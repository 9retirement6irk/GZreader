--[[--
A Grimmory book's page (the Grimmory tab, a book not on the Kindle yet):
a small cover beside its title, subtitle, authors, series, Goodreads rating,
genres and the facts (pages, year, format, size), its description below
(scrolls: page keys, a swipe), and Download / Download & open. A BookOrbit
book with its own narration has a choice over them: With narration or Book
only, each with its size (gzreader_narratedopen.lua).

What the list already has shows at once; the rest (description, genres,
rating…) comes from Grimmory's book page (/api/v1/app/books/{id}) in the
background, and the cover from the Kindle's cache (the one the list
shows) or Grimmory.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local function S(px) return Screen:scaleBySize(px) end

local BookPage = FocusManager:extend{ name = "gzreader book page", modal = true, browser = nil, book = nil, detail = nil }

---------------------------------------------------------------- what it says (pure: run_tests.lua)

local function thousands(n)
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

--- The lines under the title: { subtitle, authors, series, rating, genres, facts }.
function BookPage.facts(book, detail)
    detail = detail or {}
    local out = {}
    local sub = detail.subtitle
    if type(sub) == "string" and sub ~= "" then out.subtitle = sub end
    local authors = type(book.authors) == "table" and book.authors or detail.authors
    if type(authors) == "table" and #authors > 0 then out.authors = table.concat(authors, ", ") end
    local series = book.seriesName or detail.seriesName
    if type(series) == "string" and series ~= "" then
        local n = tonumber(book.seriesNumber or detail.seriesNumber)
        out.series = n and T(_("Book %1 of %2"), (n == math.floor(n)) and string.format("%d", n) or tostring(n), series) or series
    end
    local r = tonumber(detail.goodreadsRating)
    if r and r > 0 then
        local count = tonumber(detail.goodreadsReviewCount)
        out.rating = T(_("Goodreads ★ %1"), string.format("%.2f", r))
            .. (count and count > 0 and (" · " .. T(_("%1 ratings"), thousands(count))) or "")
    end
    -- (BookOrbit: the community rating it fetched, from Goodreads, Hardcover…)
    local cr = type(detail.communityRating) == "table" and detail.communityRating
    if not out.rating and cr and tonumber(cr.rating) and tonumber(cr.rating) > 0 then
        local count = tonumber(cr.count)
        out.rating = T(_("%1 ★ %2"), cr.provider or "", string.format("%.2f", tonumber(cr.rating)))
            .. (count and count > 0 and (" · " .. T(_("%1 ratings"), thousands(count))) or "")
    end
    local cats, seen_cat = {}, {}
    if type(detail.categories) == "table" then
        for _k, c in pairs(detail.categories) do
            -- (one entry may hold several: "Audiobook;Nonfiction;Technology")
            for one in (type(c) == "string" and c or ""):gmatch("[^;|]+") do
                one = one:gsub("^%s+", ""):gsub("%s+$", "")
                if one ~= "" and not seen_cat[one:lower()] then seen_cat[one:lower()] = true; cats[#cats + 1] = one end
            end
        end
    end
    table.sort(cats)
    if #cats > 0 then
        local shown = {}
        for i = 1, math.min(4, #cats) do shown[i] = cats[i] end
        out.genres = table.concat(shown, " · ") .. (#cats > 4 and " …" or "")
    end
    local facts = {}
    local pages = tonumber(detail.pageCount)
    if pages and pages > 0 then facts[#facts + 1] = T(_("%1 pages"), pages) end
    local year = type(detail.publishedDate) == "string" and detail.publishedDate:match("^(%d%d%d%d)")
    if year then facts[#facts + 1] = year end
    if type(detail.publisher) == "string" and detail.publisher ~= "" then facts[#facts + 1] = detail.publisher end
    if type(book.primaryFileType) == "string" then facts[#facts + 1] = book.primaryFileType:upper() end
    local kb = tonumber(book.fileSizeKb)
    if kb then facts[#facts + 1] = kb >= 1024 and string.format("%.1f MB", kb / 1024) or T("%1 KB", kb) end
    if #facts > 0 then out.facts = table.concat(facts, " · ") end
    -- the audiobook: how long, who reads it
    local ai = type(detail.audio) == "table" and detail.audio
    if ai then
        local bits = { _("Audiobook") }
        local ms = tonumber(ai.durationMs)
        if ms and ms > 0 then
            local mins = math.floor(ms / 60000 + 0.5)
            bits[#bits + 1] = mins >= 60 and T(_("%1 h %2 min"), math.floor(mins / 60), mins % 60) or T(_("%1 min"), mins)
        end
        if type(ai.narrator) == "string" and ai.narrator ~= "" then bits[#bits + 1] = T(_("read by %1"), ai.narrator) end
        out.audio = table.concat(bits, " · ")
    end
    return out
end

--- The choices over the page's buttons: { { id, label } … } and which is chosen first.
--- A book that has an audiobook too (`audio`): narrated book (when its EPUB has narration),
--- ebook only, audiobook only, with their sizes (gzreader_narratedopen.lua); an audiobook
--- with no ebook: none (it's the audiobook); a narrated book alone: with narration or
--- book only; another: none. Pure.
function BookPage.choices(narr, audio, audio_bytes, has_ebook, start)
    local Open = require("gzreader_narratedopen")
    local list = {}
    if audio then
        if has_ebook ~= true then return {}, "audio" end
        for _i, c in ipairs(Open.bothChoices(narr, audio_bytes)) do
            list[#list + 1] = { id = c.how == "narrated" and "original" or c.how == "ebook" and "ebook" or "audio", label = c.label }
        end
        if start == "audio" then table.insert(list, 1, table.remove(list)) end
        return list, list[1].id
    end
    if narr and narr.has then
        for _i, c in ipairs(Open.pageChoices(narr)) do list[#list + 1] = { id = c.variant, label = c.label } end
        return list, "original"
    end
    return list, nil
end

--- The description as text (Grimmory keeps it as HTML).
function BookPage.description(detail)
    local html = type(detail) == "table" and detail.description
    if type(html) ~= "string" or html == "" then return nil end
    local ok, AB = pcall(require, "gzreader_audiobook")
    if ok and AB.plainText then return AB.plainText(html) end
    return (html:gsub("<[^>]+>", ""))
end

---------------------------------------------------------------- the cover

--- The book's cover as an image widget fitting cw x ch, or nil: the one the
--- Grimmory tab's list already shows (gzreader_covers.lua's cache: until
--- now the page looked only in a cache of its own, kept by the old download
--- box, and showed no cover when that fetch didn't come back), else that old
--- cache.
function BookPage.coverImage(book, cw, ch)
    local ok, img = pcall(function()
        local ImageWidget = require("ui/widget/imagewidget")
        local Covers = require("gzreader_covers")
        if book.id ~= nil and Covers.state(book.id) == "have" then
            local bb = Covers.image(book.id, nil, cw, ch)
            -- (a copy: Covers may let its own go while the page is open, when
            -- the list behind it draws other covers)
            if bb then return ImageWidget:new{ image = bb:copy(), image_disposable = true } end
        end
        local thumb = require("gzreader_browser").thumbPath(book)
        if lfs.attributes(thumb, "size") then
            return ImageWidget:new{ file = thumb, width = cw, height = ch, scale_factor = 0, file_do_cache = false }
        end
    end)
    if ok then return img end
    require("gzreader_log").warn("book page cover:", tostring(img))
    return nil
end

---------------------------------------------------------------- the page

function BookPage:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    local back = Device.input and Device.input.group and Device.input.group.Back or "Back"
    -- (added to FocusManager's keys, not instead of them: until 1.23.10 the
    -- 5-way's arrows and Press did nothing here, so a Kindle with keys
    -- couldn't press Download)
    self.key_events = self.key_events or {}
    self.key_events.Close = { { back } }
    self.key_events.ScrollDown = { { Device.input and Device.input.group and Device.input.group.PgFwd or "RPgFwd" } }
    self.key_events.ScrollUp = { { Device.input and Device.input.group and Device.input.group.PgBack or "RPgBack" } }
    self.ges_events = {
        TapOutside = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    self:build()
end

function BookPage:build()
    local book = self.book
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local W = math.min(sw - S(24), S(560))
    local pad = S(14)
    local inner = W - 2 * pad
    local H = math.floor(sh * 0.88)
    -- the cover, small, beside what it is
    local cw, ch = S(96), S(144)
    local cover
    local img = BookPage.coverImage(book, cw, ch)
    if img then cover = FrameContainer:new{ padding = 0, bordersize = 1, color = Blitbuffer.COLOR_BLACK, img } end
    cover = cover or FrameContainer:new{ width = cw, height = ch, padding = 0, bordersize = 1, background = Blitbuffer.COLOR_LIGHT_GRAY,
        CenterContainer:new{ dimen = Geom:new{ w = cw - 2, h = ch - 2 },
            TextBoxWidget:new{ text = book.title or "?", face = Font:getFace("cfont", 12), width = cw - S(12), alignment = "center" } } }
    local rw = inner - cw - S(14)
    local info = BookPage.facts(book, self.detail)
    if self.audio then info.audio = BookPage.facts(book, { audio = self.audio_info or {} }).audio end
    local col = VerticalGroup:new{ align = "left" }
    local function line(text, size, opts)
        if not text then return end
        opts = opts or {}
        if #col > 0 then col[#col + 1] = VerticalSpan:new{ width = S(opts.gap or 4) } end
        col[#col + 1] = TextBoxWidget:new{ text = text, face = Font:getFace("cfont", size), bold = opts.bold, width = rw,
            fgcolor = opts.gray and Blitbuffer.COLOR_DARK_GRAY or nil,
            height = opts.lines and math.floor(opts.lines * size * 1.5 * Screen:getDPI() / 160) or nil,
            height_adjust = true, height_overflow_show_ellipsis = true }
    end
    line(book.title or "?", 20, { bold = true, lines = 3 })
    line(info.subtitle, 15, { gray = true, lines = 2 })
    line(info.authors, 16, { gap = 6, lines = 2 })
    line(info.series, 14, { gray = true })
    line(info.rating, 14, { gap = 8 })
    line(info.genres, 14, { gray = true, lines = 2 })
    line(info.facts, 13, { gray = true, lines = 2 })
    line(info.audio, 13, { gray = true, lines = 2 })
    local head = HorizontalGroup:new{ align = "top", cover, HorizontalSpan:new{ width = S(14) }, col }
    -- the buttons
    local Download = require("gzreader_download")
    local busy = Download.active ~= nil
    local usb = require("gzreader_net").usb
    local choices, first = BookPage.choices(self.narr, self.audio, self.audio_bytes, self.has_ebook, self.start)
    -- (what the page starts on, until a choice is tapped: it can change as the details come in)
    if not self.user_chosen then self.chosen = first end
    local is_audio = self.chosen == "audio"
    if is_audio then busy = false end -- (an audiobook downloads on its own)
    local buttons = {
        {
            { text = busy and _("Add to queue") or _("Download"), callback = function() self:download(false) end },
            not busy and { text = is_audio and _("Download & listen") or _("Download & open"), callback = function() self:download(true) end } or nil,
        },
        { { text = _("Close"), callback = function() self:onClose() end } },
    }
    if usb then
        -- no Wi-Fi: the next sync with the computer brings it (gzreader_usbsync.lua)
        busy = false
        buttons[1] = { { text = _("Add to sync queue"), callback = function() self:download(false) end } }
    elseif #choices > 0 then
        -- which copy, over the download buttons: two side by side, three one under another
        local rows, row = {}, {}
        for _i, c in ipairs(choices) do
            local btn = { text = (self.chosen == c.id and "● " or "○ ") .. c.label, callback = function()
                self.chosen, self.user_chosen = c.id, true
                self:refresh()
            end }
            if #choices > 2 then rows[#rows + 1] = { btn } else row[#row + 1] = btn end
        end
        if #row > 0 then rows[#rows + 1] = row end
        for i = #rows, 1, -1 do table.insert(buttons, 1, rows[i]) end
    end
    self.buttontable = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self }
    -- the description takes the rest
    local desc = BookPage.description(self.detail)
    if not desc then
        desc = require("gzreader_servername").fix(self.detail and _("No description in Grimmory.") or (self.failed and _("Couldn't get the description from Grimmory.") or _("Getting the description…")))
    end
    if busy then desc = T(_("Another download is running; this one is queued (%1 waiting)."), #Download.queue) .. "\n\n" .. desc end
    local used = head:getSize().h + self.buttontable:getSize().h + 2 * pad + S(28)
    local dh = math.max(S(80), H - used)
    self.desc = ScrollTextWidget:new{ text = desc, face = Font:getFace("cfont", 15), width = inner, height = dh,
        dialog = self, justified = false }
    local body = VerticalGroup:new{ align = "left",
        head,
        VerticalSpan:new{ width = S(12) },
        self.desc,
        VerticalSpan:new{ width = S(12) },
        self.buttontable,
    }
    self.frame = FrameContainer:new{ padding = pad, bordersize = S(2), radius = S(8), background = Blitbuffer.COLOR_WHITE, body }
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, self.frame }
    self.layout = self.buttontable.layout
    self.buttontable.layout = nil
    self:moveFocusTo(1, 1, FocusManager.FOCUS_ONLY_ON_NT)
end

function BookPage:refresh()
    if self.closed then return end
    -- (the cover drawn before: its copy let go)
    if self[1] and self[1].free then pcall(self[1].free, self[1]) end
    self:build()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
end

function BookPage:download(open)
    UIManager:close(self)
    local b = self.browser
    local book = self.book
    local Open = require("gzreader_narratedopen")
    if self.chosen == "audio" and self.audio then
        -- the audiobook: downloaded, and played when asked
        if open then return Open.downloadAudio(b.plugin, self.audio) end
        local AB = require("gzreader_audiobook")
        return require("ui/network/manager"):runWhenOnline(function()
            AB.download(b.plugin, self.audio, function(got, err) if not got then b.plugin:showError(err) end end)
        end)
    end
    if self.narr and self.narr.has then
        -- (the copy chosen on the page: not asked again)
        book = Open.asVariant(book, self.narr, self.chosen == "original" and "original" or "audioless_epub")
    end
    if open then
        b.plugin:downloadAndOpen(book, b.menu)
    else
        b.plugin:downloadAndOpen(book, b.menu, { no_open = true })
    end
    if require("gzreader_download").isQueued(book.id) then b:markQueued(book) end
end

function BookPage:onScrollDown() if self.desc then self.desc:onScrollDown() end; return true end
function BookPage:onScrollUp() if self.desc then self.desc:onScrollUp() end; return true end

function BookPage:onTapOutside(_arg, ges)
    if self.frame.dimen and ges and ges.pos and not ges.pos:intersectWith(self.frame.dimen) then self:onClose() end
    return true
end

function BookPage:onClose()
    UIManager:close(self)
    return true
end

function BookPage:onCloseWidget()
    self.closed = true
    UIManager:setDirty(nil, function() return "ui", self.frame and self.frame.dimen end)
end

--- Show `book`'s page; fetch its details and cover. opts.audio: its audiobook (the
--- audiobook's summary, as Audiobook.choose takes it): the page offers it too;
--- opts.start = "audio": the audiobook chosen to begin with (the Audiobooks page).
function BookPage.show(browser, book, opts)
    opts = opts or {}
    local page = BookPage:new{ browser = browser, book = book, audio = opts.audio, start = opts.start,
        audio_bytes = opts.audio and tonumber(opts.audio.fileSizeKb) and opts.audio.fileSizeKb * 1024 or nil }
    UIManager:show(page)
    if book.id and browser.api then
        -- (the list opens from what's saved on the Kindle, so Wi-Fi may be off:
        -- on first, as the rest of the Grimmory tab does)
        require("gzreader_net").run(function() BookPage.fetch(page, browser, book) end,
            { reason = "a book's details", usb = true })
    end
    return page
end

--- The book's details and, if it isn't on the Kindle yet, its cover.
function BookPage.fetch(page, browser, book)
    if page.closed then return end
    local Async = require("gzreader_async")
    Async.call(browser.api, "getBookDetail", { book.id }, function(detail)
        if page.closed then return end
        if type(detail) == "table" then page.detail = detail else page.failed = true end
        if type(detail) == "table" and detail.has_ebook ~= nil then page.has_ebook = detail.has_ebook end
        page:refresh()
    end)
    -- its audiobook: how big, how long, who reads it
    if page.audio and browser.api.audiobookInfo and not page.audio.plex then
        Async.run(browser.api, function(api) return api:audiobookInfo(page.audio.id) end, function(info)
            if page.closed or type(info) ~= "table" then return end
            page.audio_info = { durationMs = info.durationMs, narrator = info.narrator }
            if tonumber(info.totalSizeBytes) and info.totalSizeBytes > 0 then page.audio_bytes = info.totalSizeBytes end
            page:refresh()
        end, "audiobook info")
    end
    -- BookOrbit: does it have its own narration? (the choice and the sizes)
    if browser.api.readAloudChoices and not require("gzreader_net").usb then
        Async.run(browser.api, function(api) return api:readAloudChoices(book.id) end, function(info)
            if page.closed or type(info) ~= "table" or not info.has then return end
            page.narr = info
            page:refresh()
        end, "read-aloud choices")
    end
    -- not on the Kindle yet: into the list's cover cache (the list then
    -- has it too)
    local Covers = require("gzreader_covers")
    if Covers.state(book.id) == "missing" and not lfs.attributes(require("gzreader_browser").thumbPath(book), "size") then
        Async.call(browser.api, "downloadThumbnail", { book.id, Covers.path(book.id) }, function(ok)
            if ok and not page.closed then page:refresh() end
        end)
    end
end

return BookPage
