--[[--
Mark up a book's page: in a book, the quick panel's **Mark up** takes the
page as it's on the screen, makes it the background of a new drawing (as a
PDF's page is: gzreader_pdfmarkup.lua), and opens the drawing screen on it,
named for the book and chapter. Draw, write, circle, choose tags in the top
bar; **Done** saves it to Memos at once (no note text after), the page under
your ink. No Paper icon: the book's page is the paper.

- The page is taken as drawn on the screen (the book's own page, its
  highlights, the status bars), in colour on a colour Kindle, at Memos'
  picture size (gzreader_pdfmarkup's MAX_SIDE).
- Nothing of the book is changed: the markup is a note in Memos.
- Needs what drawing needs: a touch Kindle that draws, and Memos connected
  (BookMarkup.canDraw, as gzreader_notes.canDraw).
]]

local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local BookMarkup = {}

--- Can this book's page be marked up here? (Memos connected, a Kindle that draws.)
function BookMarkup.available(plugin, ui)
    if type(ui) ~= "table" or not ui.document or not ui.view then return false end
    local ok, on = pcall(BookMarkup.canDraw, plugin)
    return ok and on == true
end

--- What gzreader_notes.canDraw says, without loading the Notes tab (the
--- quick panel asks each time it opens): a touch Kindle, Memos connected,
--- not syncing through a computer.
function BookMarkup.canDraw(plugin)
    if require("gzreader_net").usb then return false end
    local Touch = require("gzreader_touch")
    if not Touch.on() or Touch.keys() then return false end
    local store = plugin and plugin.store and plugin.store.memos
    return type(store) == "table" and require("gzreader_memos"):new(store):isConnected() == true
end

--- The page shown now, and how many there are (nil when unknown).
function BookMarkup.pageOf(ui)
    local page, total
    pcall(function()
        if ui.paging then page = ui.paging.current_page
        else page = ui.document:getCurrentPage() end
        total = ui.document:getPageCount()
    end)
    return tonumber(page), tonumber(total)
end

--- The drawing's name: the book's title and the chapter (when known). Pure.
function BookMarkup.title(book, chapter)
    local name = (type(book) == "string" and book:match("%S")) and (book:gsub("[\r\n]+", " ")) or _("A book")
    if type(chapter) == "string" and chapter:match("%S") then
        return T(_("%1 — %2"), name, (chapter:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")))
    end
    return name
end

--- The chapter `page` is in (the book's contents), or nil.
function BookMarkup.chapterOf(ui, page)
    local ok, t = pcall(function() return ui.toc:getTocTitleByPage(page) end)
    return ok and type(t) == "string" and t ~= "" and t or nil
end

--- The page as on the screen, written as a PNG at `path` at most `max_side`
--- on its longer side: w, h, colour, or nil and why.
function BookMarkup.snapshot(ui, path, max_side)
    local PdfMarkup = require("gzreader_pdfmarkup")
    max_side = max_side or PdfMarkup.MAX_SIDE
    local ok, w, h, colour = pcall(function()
        local Blitbuffer = require("ffi/blitbuffer")
        local Screen = require("device").screen
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local colour_screen = false
        pcall(function() colour_screen = require("gzreader_colour").enabled() == true end)
        local bb = Blitbuffer.new(sw, sh, colour_screen and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8)
        bb:fill(Blitbuffer.COLOR_WHITE)
        ui.view:paintTo(bb, 0, 0)
        local scale = math.min(1, max_side / math.max(sw, sh))
        local tw, th = math.floor(sw * scale + 0.5), math.floor(sh * scale + 0.5)
        if tw ~= sw or th ~= sh then
            local small = require("ui/renderimage"):scaleBlitBuffer(bb, tw, th, true)
            if small ~= bb then bb:free() end
            bb = small
        end
        local c = PdfMarkup.writePage(bb, path, false)
        bb:free()
        return tw, th, c
    end)
    if not ok then return nil, tostring(w) end
    return w, h, colour
end

--- Mark up the page on the screen (the quick panel's tile).
function BookMarkup.start(plugin, ui)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local Notes = require("gzreader_notes")
    if not BookMarkup.available(plugin, ui) then
        UIManager:show(InfoMessage:new{ text = _("Marking up a page needs Memos connected (Settings → Accounts and services → Notes)."), timeout = 4 })
        return false
    end
    local dir = require("gzreader_places").notes("drawings", require("datastorage"):getSettingsDir() .. "/gzreader-drawings")
    require("libs/libkoreader-lfs").mkdir(dir)
    local png = dir .. "/book-page-" .. os.time() .. ".png"
    local w, h = BookMarkup.snapshot(ui, png)
    local scene = w and require("gzreader_pdfmarkup").scene(png, w, h)
    os.remove(png)
    if not scene then
        Log.warn("book markup: the page couldn't be taken:", tostring(h))
        UIManager:show(InfoMessage:new{ text = _("Couldn't take this page."), timeout = 3 })
        return false
    end
    local props = ui.doc_props or {}
    local page, total = BookMarkup.pageOf(ui)
    local title = BookMarkup.title(props.display_title or props.title, page and BookMarkup.chapterOf(ui, page))
    Log.info("book markup: page", tostring(page), "of", tostring(total), "taken,", w .. "x" .. h)
    return Notes.edit(plugin, nil, { markup_pages = { { new = true, modified = true, scene = scene, book_page = page } },
        markup_title = title })
end

--- The quick panel's tile in a book (nil when it can't be used).
function BookMarkup.tile(plugin, ui)
    if not BookMarkup.available(plugin, ui) then return nil end
    return { id = "markup", icon = "markup", label = _("Mark up"), run = function() BookMarkup.start(plugin, ui) end }
end

return BookMarkup
