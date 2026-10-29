--[[--
Picture books: pages that are pictures fill the screen.

Some EPUBs are scans (Diary of a Wimpy Kid: every page is a 385 x 625 JPEG
of the printed page, text included), so the font size does nothing, and
with the book's own margins and padding the pictures came out small, or
cut off at the bottom of a page. GZreader recognizes such books when they
open (nearly every chapter file is pictures with next to no text) and, once
per book:
- adds a book-specific style tweak that makes each picture as tall as the
  page area (height 100%, keeping its shape, never wider than the screen)
  with no margins or padding around it. 100% is the space between the top
  and bottom margins, so the title bar (ZenOS reserves a top margin for it)
  and the footer stay clear. (1.0.28 used 100vh, the whole screen: pictures
  ran under the title bar and the footer, and a narrow picture such as a
  publisher's logo was stretched to the full height);
- sets this book's page margins to 0 (the previous ones are kept and put
  back when you turn it off);
- turns on smooth image scaling for the book: the pages are small scans
  (about 385 x 625) enlarged to the screen, and smooth scaling makes the
  enlarged handwriting look much less jagged.
Reading menu → "Fit pictures to the screen" turns it on or off for the book.
]]

local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local Log = require("grimmory_log")
local _ = require("gettext")

local PB = {}

local MARK_BEGIN = "/* GZreader picture book: begin */"
local MARK_END = "/* GZreader picture book: end */"
PB.CSS = MARK_BEGIN .. [[

body, p, div, section { margin: 0 !important; padding: 0 !important; text-indent: 0 !important; }
img { display: block !important; margin: 0 auto !important; padding: 0 !important;
      height: 100% !important; width: auto !important;
      max-height: 100% !important; max-width: 100% !important; }
]] .. MARK_END

--- Is this a picture book? (EPUB whose chapter files are pictures, not text.)
function PB.detect(doc)
    if not doc or doc.info.has_pages or type(doc.getDocumentFileContent) ~= "function" then return false end
    local ok_s, Sync = pcall(require, "grimmory_sync")
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
    if on then
        st.book_style_tweak = (rest and (rest .. "\n") or "") .. PB.CSS
        st.book_style_tweak_enabled = true
        local m = margins(ui)
        if m and not ui.doc_settings:readSetting("gzreader_pb_margins") then
            ui.doc_settings:saveSetting("gzreader_pb_margins", { m[1], m[2], m[3], m[4] })
        end
        setMargins(ui, { 0, 0, 0, 0 })
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
    if ui.doc_settings:readSetting("gzreader_picture_book") ~= nil then
        -- turned on by an older version: bring its style tweak up to date
        local st = ui.styletweak
        if PB.isOn(ui) and not st.book_style_tweak:find(PB.CSS, 1, true) then
            UIManager:nextTick(function()
                if ui.document then PB.set(ui, true); Log.info("picture book: style updated") end
            end)
        end
        return
    end
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
