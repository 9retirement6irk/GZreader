--[[--
A Grimmory book's page (the Grimmory tab, a book not on the Kindle yet):
a small cover beside its title, subtitle, authors, series, Goodreads rating,
genres and the facts (pages, year, format, size), its description below
(scrolls: page keys, a swipe), and Download / Download & open.

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
    local cats = {}
    if type(detail.categories) == "table" then
        for _k, c in pairs(detail.categories) do
            if type(c) == "string" and c ~= "" then cats[#cats + 1] = c end
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
    return out
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
    local head = HorizontalGroup:new{ align = "top", cover, HorizontalSpan:new{ width = S(14) }, col }
    -- the buttons
    local Download = require("gzreader_download")
    local busy = Download.active ~= nil
    local usb = require("gzreader_net").usb
    local buttons = {
        {
            { text = busy and _("Add to queue") or _("Download"), callback = function() self:download(false) end },
            not busy and { text = _("Download & open"), callback = function() self:download(true) end } or nil,
        },
        { { text = _("Close"), callback = function() self:onClose() end } },
    }
    if usb then
        -- no Wi-Fi: the next sync with the computer brings it (gzreader_usbsync.lua)
        busy = false
        buttons[1] = { { text = _("Add to sync queue"), callback = function() self:download(false) end } }
    end
    self.buttontable = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self }
    -- the description takes the rest
    local desc = BookPage.description(self.detail)
    if not desc then
        desc = self.detail and _("No description in Grimmory.") or (self.failed and _("Couldn't get the description from Grimmory.") or _("Getting the description…"))
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

--- Show `book`'s page; fetch its details and cover.
function BookPage.show(browser, book)
    local page = BookPage:new{ browser = browser, book = book }
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
        page:refresh()
    end)
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
