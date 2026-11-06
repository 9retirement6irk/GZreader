--[[--
Picture books: pages that are pictures fill the screen.

Some EPUBs are scans (Diary of a Wimpy Kid: every page is a 385 x 625 JPEG
of the printed page, text included), so the font size does nothing, and
with the book's own margins and padding the pictures came out small, or
cut off at the bottom of a page. GZreader recognizes such books when they
open (nearly every chapter file is pictures with next to no text) and, once
per book:
- adds a book-specific style tweak that makes each picture as tall as the
  space between ZenOS's title bar and the footer, keeping its shape, with
  no margins or padding around it: 99.5vh, crengine's vh being the text
  area inside the margins. (1.0.28 had no top margin, so pages ran under
  the clock; 1.0.30's height:100% was ignored on the Kindle, so the pages
  came out at their own, smaller size.) Pictures wider than the page's
  shape (a publisher's logo) are left at their own size, so they aren't
  stretched (found once per book from the pictures' own sizes);
- sets this book's margins: 0, except a top margin as tall as the title bar
  (unless ZenOS already reserves it), so the clock doesn't sit on the page
  (the previous margins are kept and put back when you turn it off);
- turns on smooth image scaling for the book: the pages are small scans
  (about 385 x 625) enlarged to the screen, and smooth scaling makes the
  enlarged handwriting look much less jagged.
Reading menu → "Fit pictures to the screen" turns it on or off for the book.
]]

local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")

local PB = {}

local MARK_BEGIN = "/* GZreader picture book: begin */"
local MARK_END = "/* GZreader picture book: end */"
PB.VERSION = 5

--- The style tweak, with pictures `vh` tall. In crengine 1vh is 1% of the
--- page's text area (inside the margins), and vh is honoured for pictures
--- on the Kindle (1.0.30's height:100% was ignored there).
function PB.css(vh, wide)
    local out = { MARK_BEGIN .. string.format([[ /* v%d */
body, p, div, section, h1, h2, h3, h4, h5, h6, figure, blockquote, center { margin: 0 !important; padding: 0 !important; text-indent: 0 !important; }
img { display: block !important; margin: 0 auto !important; padding: 0 !important;
      height: %.1fvh !important; width: auto !important;
      max-height: none !important; max-width: 100vw !important; }]], PB.VERSION, vh) }
    -- pictures wider than the page's shape (a publisher's logo): their own
    -- size, never wider than the screen, so they keep their shape
    for _i, name in ipairs(wide or {}) do
        out[#out + 1] = string.format('img[src$="%s"] { height: auto !important; width: auto !important; }',
            name:gsub('[\\"]', ""))
    end
    out[#out + 1] = MARK_END
    return table.concat(out, "\n")
end

--- Width and height of a JPEG, PNG or GIF from its first bytes, or nil.
function PB.imageSize(data)
    if type(data) ~= "string" or #data < 24 then return nil end
    local b = function(i) return data:byte(i) or 0 end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then
        return b(17) * 16777216 + b(18) * 65536 + b(19) * 256 + b(20), b(21) * 16777216 + b(22) * 65536 + b(23) * 256 + b(24)
    end
    if data:sub(1, 3) == "GIF" then return b(7) + b(8) * 256, b(9) + b(10) * 256 end
    if b(1) == 0xFF and b(2) == 0xD8 then
        local i = 3
        while i + 8 < #data do
            if b(i) ~= 0xFF then return nil end
            local m = b(i + 1)
            local len = b(i + 2) * 256 + b(i + 3)
            if (m >= 0xC0 and m <= 0xC3) or (m >= 0xC5 and m <= 0xC7) or (m >= 0xC9 and m <= 0xCB) or (m >= 0xCD and m <= 0xCF) then
                return b(i + 7) * 256 + b(i + 8), b(i + 5) * 256 + b(i + 6)
            end
            i = i + 2 + len
        end
    end
    return nil
end

--- File names of the book's pictures that are wider than w:h.
--- read(path) -> the file's bytes inside the EPUB.
function PB.widePictures(read, w, h)
    local out = {}
    local ok_s, Sync = pcall(require, "gzreader_sync")
    if not ok_s or type(read) ~= "function" then return out end
    local ok, spine = pcall(Sync.parseSpine, read)
    if not ok or not spine then return out end
    local seen = {}
    for _i, href in ipairs(spine.frag) do
        local html = read(href)
        local base = href:match("^(.*/)") or ""
        for src in (html or ""):gmatch("<[%w:]*img[^>]-src%s*=%s*[\"']([^\"']+)[\"']") do
            local path = Sync.normalizeHref(base .. src)
            local name = src:match("([^/]+)$")
            if name and not seen[path] then
                seen[path] = true
                local iw, ih = PB.imageSize(read(path))
                if iw and ih and ih > 0 and iw / ih > w / h * 1.05 then out[#out + 1] = name end
            end
        end
    end
    table.sort(out)
    return out
end

--- Screen space for a page, between the title bar and the footer:
--- { top = margin (unscaled px) for the title bar, vh = picture height }.
PB.VH = 99
function PB.layout(ui)
    local Screen = require("device").screen
    local H = Screen:getHeight()
    local view = ui.view
    local footer = view and view.footer
    local footer_h = 0
    if footer then
        local ok, h = pcall(footer.getHeight, footer)
        footer_h = ok and tonumber(h) or 0
    end
    local scale = Screen:scaleBySize(1000) / 1000
    -- ZenOS's title bar (clock…): ZenOS adds its height to the top margin
    -- itself when the margins are applied; reserve it here only if it can't
    local header_h = view and view._zen_header_dimen and tonumber(view._zen_header_dimen.h) or 0
    -- (it doesn't when the status bar overlaps the page: then 0 is reserved,
    -- and 1.2.6 put the page under the clock)
    local zen_reserved = ui.document and tonumber(ui.document._zen_top_status_bar_reserved_height) or 0
    local top = (header_h > 0 and zen_reserved <= 0) and math.ceil(header_h / scale) + 2 or 0
    -- KOReader adds the status bar's height to the bottom margin, but only
    -- its height when the margins are set: it grows when its text appears
    -- ("16 min left in chapter"), and with "overlap status bar" it isn't
    -- added at all. 1.2.5's pages ran under it. Keep a few pixels spare, and
    -- the whole status bar when it overlaps.
    local bottom = 4
    if footer and (footer.reclaim_height or (footer.settings and footer.settings.reclaim_height)) then
        bottom = bottom + math.ceil(footer_h / scale)
    end
    return { top = top, bottom = bottom, vh = PB.VH, header = header_h, footer = footer_h, screen = H,
        avail_w = Screen:getWidth(), avail_h = H - math.ceil((top + bottom) * scale) - footer_h }
end

--- The style tweak for this book on this screen (wide pictures looked up once per book).
--- Opening a book reads every picture's size to find the wide ones: that
--- took about a minute for Diary of a Wimpy Kid (230 pictures) on a Kindle 3,
--- and 1.2.0 did it on the screen's thread. Now in a background process,
--- once per book; until it's done no picture is treated as wide.
--- on_ready(ui) (optional): called with the open reader once the sizes are
--- known (also when they couldn't be read: then no picture counts as wide).
function PB.scanInBackground(ui, lay, on_ready)
    if PB.scanning or not (ui.document and ui.document.file and ui.doc_settings) then return end
    PB.scanning = true
    local file, w, h = ui.document.file, lay.avail_w, lay.avail_h
    Log.info("picture book: reading picture sizes in the background")
    require("gzreader_async").background(function()
        local Archiver = require("ffi/archiver")
        local r = Archiver.Reader:new()
        if not r:open(file) then return nil end
        for _e in r:iterate() do end
        local list = PB.widePictures(function(p) return r:extractToMemory(p) end, w, h)
        r:close()
        return list
    end, function(list, err)
        PB.scanning = false
        if type(list) ~= "table" then
            Log.info("picture book: picture sizes not read:", tostring(err))
            list = {}
        end
        Log.info("picture book: wide pictures", #list)
        -- the book may have been reloaded meanwhile (a new reader): use the open one
        local okr, ReaderUI = pcall(require, "apps/reader/readerui")
        local cur = okr and ReaderUI.instance or nil
        if cur and cur.document and cur.document.file == file and cur.doc_settings then
            PB.saveWide(cur, cur.doc_settings, list)
            if on_ready then on_ready(cur) end
            return
        end
        -- closed meanwhile: into the book's saved settings
        local okd, DocSettings = pcall(require, "docsettings")
        if okd then
            local ds = DocSettings:open(file)
            PB.saveWide(nil, ds, list)
            ds:flush()
        end
    end, "picture sizes", { timeout = 900 })
end


--- Is this a picture book? (EPUB whose chapter files are pictures, not text.)
function PB.detect(doc)
    if not doc or doc.info.has_pages or type(doc.getDocumentFileContent) ~= "function" then return false end
    return PB.detectWith(function(p) return doc:getDocumentFileContent(p) end)
end

--- The same from the EPUB's files: read(path) -> a file inside the EPUB.
function PB.detectWith(read)
    local ok_s, Sync = pcall(require, "gzreader_sync")
    if not ok_s then return false end
    local ok, spine = pcall(Sync.parseSpine, read)
    if not ok or not spine or #spine.frag < 3 then return false end
    local sampled, pictures, text_total, img_total = 0, 0, 0, 0
    local n = #spine.frag
    -- skip the first and last few (cover, title, copyright pages)
    local first, last = math.min(3, n), math.max(1, n - 1)
    local step = math.max(1, math.floor((last - first) / 10))
    for i = first, last, step do
        local html = read(spine.frag[i])
        if html then
            sampled = sampled + 1
            local body = html:match("<[%w:]*body[^>]*>(.*)</[%w:]*body>") or html
            local imgs = select(2, body:gsub("<[%w:]*img[%s>/]", "")) + select(2, body:gsub("<[%w:]*image[%s>/]", ""))
            local text = body:gsub("<[^>]*>", " "):gsub("&[#%w]+;", " "):gsub("%s+", "")
            img_total = img_total + imgs
            text_total = text_total + #text
            if imgs > 0 and #text < 100 * imgs then pictures = pictures + 1 end
        end
        if sampled >= 12 then break end
    end
    local yes = sampled >= 2 and pictures >= sampled * 0.7 and img_total >= sampled
    Log.info("picture book check:", sampled, "files,", pictures, "pictures-only,", img_total, "images,", text_total, "chars ->", yes and "yes" or "no")
    return yes
end

local function stripOurs(css)
    if not css then return nil end
    local a = css:find(MARK_BEGIN, 1, true)
    local b = css:find(MARK_END, 1, true)
    if a and b then css = css:sub(1, a - 1) .. css:sub(b + #MARK_END) end
    css = css:gsub("^%s+", ""):gsub("%s+$", "")
    return css ~= "" and css or nil
end

function PB.isOn(ui)
    local st = ui.styletweak
    return st ~= nil and st.book_style_tweak_enabled == true and type(st.book_style_tweak) == "string"
        and st.book_style_tweak:find(MARK_BEGIN, 1, true) ~= nil
end




--- Changing the layout of an open book made crengine lay the whole book out
--- again for each change (two margin changes and the style: three layouts,
--- several seconds each on a Kindle 3), then KOReader re-laid it out once
--- more in the background and reloaded it (the "random refreshes"), and
--- because pictures become blocks (display: block, a change to how the DOM
--- is built) it asked "Styles have changed in such a way…", a box only Press
--- or Back answer. Now the new layout is saved with the book, its layout
--- cache dropped, and the book reopened once: crengine builds it with the
--- picture-book style from the start. No relayouts, no prompt.
function PB.reopen(ui)
    PB.reopening = true
    UIManager:nextTick(function()
        PB.reopening = nil
        local d = ui.document
        if not d or ui.tearing_down then return end
        if d.invalidateCacheFile then pcall(d.invalidateCacheFile, d) end
        Log.info("picture book: reopening the book with its new layout")
        ui:reloadDocument(nil, true)
    end)
end

--- Turn it on or off for the open book (saved, then the book reopens).
--- opts.reopen = false: only save it (applies the next time the book opens).
function PB.set(ui, on, opts)
    opts = opts or {}
    local st = ui.styletweak
    local cfg = ui.document and ui.document.configurable
    if not st or not cfg then return false end
    local rest = stripOurs(st.book_style_tweak)
    if on then
        local lay = PB.layout(ui)
        local wide = ui.doc_settings:readSetting("gzreader_pb_wide")
        if type(wide) ~= "table" then
            -- the picture sizes first (wide ones such as a logo or a blank
            -- spacer would otherwise fill a page), then this again
            if PB.scanning then return true end
            local ok = pcall(PB.scanInBackground, ui, lay, function(cur) PB.set(cur, true, opts) end)
            if ok and PB.scanning then return true end
            wide = {}
        end
        st.book_style_tweak = (rest and (rest .. "\n") or "") .. PB.css(lay.vh, wide)
        st.book_style_tweak_enabled = true
        ui.doc_settings:saveSetting("gzreader_pb_vh", lay.vh)
        if not ui.doc_settings:readSetting("gzreader_pb_margins") then
            local h = cfg.h_page_margins or { 15, 15 }
            ui.doc_settings:saveSetting("gzreader_pb_margins",
                { h[1], cfg.t_page_margin, h[2], cfg.b_page_margin, cfg.sync_t_b_page_margins })
        end
        cfg.h_page_margins = { 0, 0 }
        cfg.t_page_margin = lay.top
        cfg.b_page_margin = lay.bottom
        cfg.sync_t_b_page_margins = 0
        if ui.doc_settings:readSetting("gzreader_pb_smooth") == nil then
            ui.doc_settings:saveSetting("gzreader_pb_smooth", cfg.smooth_scaling == 1)
        end
        cfg.smooth_scaling = 1
        -- (this Kindle's layout: books recognized before they're opened get it: PB.prefit)
        G_reader_settings:saveSetting("gzreader_pb_layout", { top = lay.top, bottom = lay.bottom, vh = lay.vh,
            avail_w = lay.avail_w, avail_h = lay.avail_h })
        ui.doc_settings:saveSetting("gzreader_pb_fit", { top = lay.top, bottom = lay.bottom })
        Log.info("picture book layout: screen", lay.screen, "title bar", lay.header, "footer", lay.footer,
            "margins top", lay.top, "bottom", lay.bottom, "pictures", lay.vh .. "vh", "wide ones kept as they are", #wide)
    else
        st.book_style_tweak = rest
        if not rest then st.book_style_tweak_enabled = nil end
        local old = ui.doc_settings:readSetting("gzreader_pb_margins")
        if type(old) == "table" then
            cfg.h_page_margins = { old[1] or 15, old[3] or 15 }
            cfg.t_page_margin, cfg.b_page_margin = old[2] or 15, old[4] or 15
            if old[5] ~= nil then cfg.sync_t_b_page_margins = old[5] end
        end
        ui.doc_settings:delSetting("gzreader_pb_margins")
        local smooth = ui.doc_settings:readSetting("gzreader_pb_smooth")
        if smooth ~= nil then cfg.smooth_scaling = smooth and 1 or 0 end
        ui.doc_settings:delSetting("gzreader_pb_smooth")
    end
    ui.doc_settings:saveSetting("gzreader_picture_book", on and true or false)
    Log.info("picture book", on and "on" or "off")
    if opts.reopen ~= false then PB.reopen(ui) end
    return true
end

--- The wide pictures found in the background: added to the saved style, so
--- they keep their own size from the next time the book opens (not now: that
--- would mean another reopen).
function PB.saveWide(ui, ds, list)
    ds:saveSetting("gzreader_pb_wide", list)
    if #list == 0 then return end
    local vh = tonumber(ds:readSetting("gzreader_pb_vh")) or PB.VH
    if ui and ui.styletweak then
        local st = ui.styletweak
        if PB.isOn(ui) then st.book_style_tweak = (stripOurs(st.book_style_tweak) and (stripOurs(st.book_style_tweak) .. "\n") or "") .. PB.css(vh, list) end
    else
        local css = ds:readSetting("book_style_tweak")
        if type(css) == "string" and css:find(MARK_BEGIN, 1, true) then
            local rest = stripOurs(css)
            ds:saveSetting("book_style_tweak", (rest and (rest .. "\n") or "") .. PB.css(vh, list))
        end
    end
end

--- On opening a book: recognize picture books once and fit them.
function PB.onOpen(ui)
    if not ui.doc_settings then return end
    local known = ui.doc_settings:readSetting("gzreader_picture_book")
    if known == true and PB.isOn(ui) and not ui.styletweak.book_style_tweak:find("/* v" .. PB.VERSION .. " */", 1, true) then
        -- fitted by an older version (page under the status bar, the
        -- "Styles have changed" box): fit it again, once
        UIManager:nextTick(function() if ui.document then PB.set(ui, true) end end)
        return
    end
    local fit = ui.doc_settings:readSetting("gzreader_pb_fit")
    if known == true and PB.isOn(ui) and type(fit) == "table" then
        -- fitted before it was first opened (PB.prefit): for this Kindle's
        -- layout as it was then; if the title bar or footer changed since, again
        local lay = PB.layout(ui)
        if lay.top ~= fit.top or lay.bottom ~= fit.bottom then
            UIManager:nextTick(function() if ui.document then PB.set(ui, true) end end)
        end
        return
    end
    if known == true and not PB.isOn(ui) then
        -- recognized, but closed before it was fitted: finish now
        UIManager:nextTick(function() if ui.document then PB.set(ui, true) end end)
        return
    end
    if known ~= nil then return end
    if G_reader_settings:isFalse("gzreader_picture_book_auto") then return end
    local yes = PB.detect(ui.document)
    ui.doc_settings:saveSetting("gzreader_picture_book", yes)
    if yes then
        UIManager:nextTick(function()
            if ui.document and PB.set(ui, true) then
                UIManager:show(Notification:new{ text = _("Picture book: the pages will be fitted to the screen in a moment…") })
            end
        end)
    end
end

--- Books just downloaded or brought by the computer: recognized and fitted
--- before they're first opened, in the background. Otherwise the first
--- opening read every picture (in the background, 22 s for Diary of a Wimpy
--- Kid on a Kindle DX) and then opened the book a second time with the new
--- layout. Fitted needs this Kindle's layout (title bar, footer): known once
--- a picture book has been fitted here; until then it's only recognized and
--- its pictures measured, and the first opening fits it (one reopen).
PB.queue = {}
function PB.prepare(file)
    -- (the tests turn it off where it isn't what they check)
    if rawget(_G, "GZ_NO_PB_PREPARE") or type(file) ~= "string" or not file:lower():match("%.epub$") then return end
    if G_reader_settings:readSetting("gzreader_picture_book_auto") == false then return end
    for _i, f in ipairs(PB.queue) do if f == file then return end end
    PB.queue[#PB.queue + 1] = file
    if #PB.queue == 1 then UIManager:scheduleIn(PB.PREPARE_DELAY or 10, PB.safeNext) end
end

function PB.safeNext()
    local ok, err = pcall(PB.prepareNext)
    if not ok then
        Log.warn("picture book: preparing:", tostring(err))
        PB.queue = {}
    end
end

local function openNow(file)
    local okr, ReaderUI = pcall(require, "apps/reader/readerui")
    local cur = okr and ReaderUI.instance or nil
    return cur and cur.document and cur.document.file == file
end

function PB.prepareNext()
    local file = PB.queue[1]
    if not file then return end
    local okd, DocSettings = pcall(require, "docsettings")
    if not okd or openNow(file) or DocSettings:open(file):readSetting("gzreader_picture_book") ~= nil then
        table.remove(PB.queue, 1)
        if #PB.queue > 0 then UIManager:scheduleIn(1, PB.safeNext) end
        return
    end
    local lay = G_reader_settings:readSetting("gzreader_pb_layout")
    local Screen = require("device").screen
    local w = type(lay) == "table" and tonumber(lay.avail_w) or Screen:getWidth()
    local h = type(lay) == "table" and tonumber(lay.avail_h) or math.floor(Screen:getHeight() * 0.95)
    require("gzreader_async").background(function()
        local Archiver = require("ffi/archiver")
        local r = Archiver.Reader:new()
        if not r:open(file) then return nil end
        for _e in r:iterate() do end
        local read = function(p) return r:extractToMemory(p) end
        local yes = PB.detectWith(read)
        local wide = yes and PB.widePictures(read, w, h) or {}
        r:close()
        return { yes = yes, wide = wide }
    end, function(res, err)
        if err == "busy" then return UIManager:scheduleIn(30, PB.safeNext) end -- (another job: later)
        table.remove(PB.queue, 1)
        if type(res) == "table" then
            local ok, e = pcall(PB.prefit, file, res.yes == true, type(res.wide) == "table" and res.wide or {})
            if not ok then Log.warn("picture book: couldn't prepare", tostring(e)) end
        else
            Log.info("picture book: not checked before opening:", tostring(err))
        end
        if #PB.queue > 0 then UIManager:scheduleIn(2, PB.safeNext) end
    end, "picture book check", { timeout = 900 })
end

--- Save what was found with the book (not when it was opened meanwhile).
function PB.prefit(file, yes, wide)
    if openNow(file) then return false end
    local DocSettings = require("docsettings")
    local ds = DocSettings:open(file)
    if ds:readSetting("gzreader_picture_book") ~= nil then return false end
    ds:saveSetting("gzreader_picture_book", yes)
    local fitted = false
    if yes then
        ds:saveSetting("gzreader_pb_wide", wide)
        local lay = G_reader_settings:readSetting("gzreader_pb_layout")
        if type(lay) == "table" and tonumber(lay.top) and tonumber(lay.bottom) then
            local function def(k, d)
                local v = G_reader_settings:readSetting("copt_" .. k)
                if v == nil then return d end
                return v
            end
            local hm = def("h_page_margins", { 15, 15 })
            local vh = tonumber(lay.vh) or PB.VH
            -- what PB.set keeps to put back when it's turned off
            ds:saveSetting("gzreader_pb_margins", { hm[1], def("t_page_margin", 15), hm[2], def("b_page_margin", 15),
                def("sync_t_b_page_margins", nil) })
            ds:saveSetting("gzreader_pb_smooth", def("smooth_scaling", 0) == 1)
            ds:saveSetting("gzreader_pb_vh", vh)
            ds:saveSetting("copt_h_page_margins", { 0, 0 })
            ds:saveSetting("copt_t_page_margin", lay.top)
            ds:saveSetting("copt_b_page_margin", lay.bottom)
            ds:saveSetting("copt_sync_t_b_page_margins", 0)
            ds:saveSetting("copt_smooth_scaling", 1)
            ds:saveSetting("book_style_tweak", PB.css(vh, wide))
            ds:saveSetting("book_style_tweak_enabled", true)
            ds:saveSetting("gzreader_pb_fit", { top = lay.top, bottom = lay.bottom })
            fitted = true
        end
    end
    ds:flush()
    Log.info("picture book check before opening:", (file:match("[^/]+$")), yes and (fitted and "yes, fitted" or "yes") or "no",
        yes and ("(wide pictures " .. #wide .. ")") or "")
    return true
end

function PB.menuItem(ui)
    return {
        text_func = function()
            return PB.isOn(ui) and _("Fit pictures to the screen: on") or _("Fit pictures to the screen (picture books)")
        end,
        callback = function() PB.set(ui, not PB.isOn(ui)) end,
    }
end

return PB
