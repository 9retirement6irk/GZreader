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
local Event = require("ui/event")
local Log = require("gzreader_log")
local _ = require("gettext")

local PB = {}

local MARK_BEGIN = "/* GZreader picture book: begin */"
local MARK_END = "/* GZreader picture book: end */"
PB.VERSION = 3

--- The style tweak, with pictures `vh` tall. In crengine 1vh is 1% of the
--- page's text area (inside the margins), and vh is honoured for pictures
--- on the Kindle (1.0.30's height:100% was ignored there).
function PB.css(vh, wide)
    local out = { MARK_BEGIN .. string.format([[ /* v%d */
body, p, div, section { margin: 0 !important; padding: 0 !important; text-indent: 0 !important; }
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
function PB.widePictures(doc, w, h)
    local out = {}
    local ok_s, Sync = pcall(require, "gzreader_sync")
    if not ok_s or not doc or type(doc.getDocumentFileContent) ~= "function" then return out end
    local ok, spine = pcall(Sync.parseSpine, function(p) return doc:getDocumentFileContent(p) end)
    if not ok or not spine then return out end
    local seen = {}
    for _i, href in ipairs(spine.frag) do
        local html = doc:getDocumentFileContent(href)
        local base = href:match("^(.*/)") or ""
        for src in (html or ""):gmatch("<[%w:]*img[^>]-src%s*=%s*[\"']([^\"']+)[\"']") do
            local path = Sync.normalizeHref(base .. src)
            local name = src:match("([^/]+)$")
            if name and not seen[path] then
                seen[path] = true
                local iw, ih = PB.imageSize(doc:getDocumentFileContent(path))
                if iw and ih and ih > 0 and iw / ih > w / h * 1.05 then out[#out + 1] = name end
            end
        end
    end
    table.sort(out)
    return out
end

--- Screen space for a page, between the title bar and the footer:
--- { top = margin (unscaled px) for the title bar, vh = picture height }.
function PB.layout(ui)
    local Screen = require("device").screen
    local H = Screen:getHeight()
    local view = ui.view
    local footer_h = 0
    if view and view.footer and not view.footer.reclaim_height then
        local ok, h = pcall(view.footer.getHeight, view.footer)
        footer_h = ok and tonumber(h) or 0
    end
    -- ZenOS's title bar (clock etc.) over the top of the page: its height as
    -- last painted (ZenOS normally reserves it as a top margin itself)
    local header_h = view and view._zen_header_dimen and tonumber(view._zen_header_dimen.h) or 0
    local scale = Screen:scaleBySize(1000) / 1000
    local top = header_h > 0 and math.ceil(header_h / scale) or 0
    local avail = H - math.ceil(top * scale) - footer_h
    -- crengine's vh is the page's text area (between the margins), so this
    -- fills the space under the title bar exactly; a hair under 100 so a
    -- page never spills onto a second one
    local vh = 99.5
    return { top = top, vh = vh, header = header_h, footer = footer_h, screen = H,
        avail_w = Screen:getWidth(), avail_h = avail }
end

--- The style tweak for this book on this screen (wide pictures looked up once per book).
function PB.cssFor(ui, lay)
    local wide = ui.doc_settings and ui.doc_settings:readSetting("gzreader_pb_wide")
    if type(wide) ~= "table" then
        local ok, list = pcall(PB.widePictures, ui.document, lay.avail_w, lay.avail_h)
        wide = ok and list or {}
        if ui.doc_settings then ui.doc_settings:saveSetting("gzreader_pb_wide", wide) end
    end
    return PB.css(lay.vh, wide), #wide
end

--- Is this a picture book? (EPUB whose chapter files are pictures, not text.)
function PB.detect(doc)
    if not doc or doc.info.has_pages or type(doc.getDocumentFileContent) ~= "function" then return false end
    local ok_s, Sync = pcall(require, "gzreader_sync")
    if not ok_s then return false end
    local ok, spine = pcall(Sync.parseSpine, function(p) return doc:getDocumentFileContent(p) end)
    if not ok or not spine or #spine.frag < 3 then return false end
    local sampled, pictures, text_total, img_total = 0, 0, 0, 0
    local n = #spine.frag
    -- skip the first and last few (cover, title, copyright pages)
    local first, last = math.min(3, n), math.max(1, n - 1)
    local step = math.max(1, math.floor((last - first) / 10))
    for i = first, last, step do
        local html = doc:getDocumentFileContent(spine.frag[i])
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

local function margins(ui)
    local t = ui.typeset
    return t and t.unscaled_margins
end

local function setSmooth(ui, on)
    local cfg = ui.document and ui.document.configurable
    if cfg then cfg.smooth_scaling = on and 1 or 0 end
    if ui.document and ui.document.setImageScaling then pcall(ui.document.setImageScaling, ui.document, on) end
end

local function setMargins(ui, m)
    local cfg = ui.document and ui.document.configurable
    if cfg then
        cfg.h_page_margins = { m[1], m[3] }
        cfg.t_page_margin = m[2]
        cfg.b_page_margin = m[4]
    end
    ui:handleEvent(Event:new("SetPageMargins", m))
end

--- Turn it on or off for the open book.
function PB.set(ui, on)
    local st = ui.styletweak
    if not st then return false end
    local rest = stripOurs(st.book_style_tweak)
    local lay = on and PB.layout(ui)
    if on then
        local css, nwide = PB.cssFor(ui, lay)
        lay.wide = nwide
        st.book_style_tweak = (rest and (rest .. "\n") or "") .. css
        st.book_style_tweak_enabled = true
        local m = margins(ui)
        if m and not ui.doc_settings:readSetting("gzreader_pb_margins") then
            ui.doc_settings:saveSetting("gzreader_pb_margins", { m[1], m[2], m[3], m[4] })
        end
        setMargins(ui, { 0, 0, 0, 0 })
        -- ZenOS reserves the title bar as a top margin itself; if it didn't, do it here
        local reserved = ui.document and tonumber(ui.document._zen_top_status_bar_reserved_height) or 0
        if reserved == 0 and lay.top > 0 then setMargins(ui, { 0, lay.top, 0, 0 }) end
        Log.info("picture book layout: screen", lay.screen, "title bar", lay.header, "footer", lay.footer,
            "top margin", reserved > 0 and ("(ZenOS) " .. reserved) or lay.top, "pictures", lay.vh .. "vh", "wide ones kept as they are", lay.wide)
        local cfg = ui.document and ui.document.configurable
        if cfg and ui.doc_settings:readSetting("gzreader_pb_smooth") == nil then
            ui.doc_settings:saveSetting("gzreader_pb_smooth", cfg.smooth_scaling == 1)
        end
        setSmooth(ui, true)
    else
        st.book_style_tweak = rest
        if not rest then st.book_style_tweak_enabled = nil end
        local old = ui.doc_settings:readSetting("gzreader_pb_margins")
        if type(old) == "table" then setMargins(ui, old) end
        ui.doc_settings:delSetting("gzreader_pb_margins")
        local smooth = ui.doc_settings:readSetting("gzreader_pb_smooth")
        if smooth ~= nil then setSmooth(ui, smooth == true) end
        ui.doc_settings:delSetting("gzreader_pb_smooth")
    end
    ui.doc_settings:saveSetting("gzreader_picture_book", on and true or false)
    st:updateCssText(true)
    Log.info("picture book", on and "on" or "off")
    return true
end

--- On opening a book: recognize picture books once and fit them.
function PB.onOpen(ui)
    if not ui.doc_settings then return end
    if ui.doc_settings:readSetting("gzreader_picture_book") ~= nil then return end
    if G_reader_settings:isFalse("gzreader_picture_book_auto") then return end
    local yes = PB.detect(ui.document)
    ui.doc_settings:saveSetting("gzreader_picture_book", yes)
    if yes then
        UIManager:nextTick(function()
            if ui.document and PB.set(ui, true) then
                UIManager:show(Notification:new{ text = _("Picture book: pages fill the screen. Reading menu to turn this off.") })
            end
        end)
    end
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
