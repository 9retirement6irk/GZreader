--[[--
Split view: the book in one part of a big screen, a drawing page for notes
in the other (the owner, 2026-11-17, from a mockup). Upright: the book on
top, the notes under it. On its side: the book at the left, the notes at
the right. The pen draws in the notes; a tap or swipe on the book turns its
pages as usual; the Text tool types with the keyboard.

How:
- the book is laid out again in its part (`setReader`: KOReader's own way of
  taking a new size, as when the screen turns), always from the screen's
  top-left corner, which is where KOReader paints it;
- the drawing screen opens with `pane` (gzreader_drawscreen): it takes
  `Split.pending` when it's shown, so the note editor between the two needs
  to know nothing about it;
- when the drawing screen closes, `closed` gives the book the whole screen.

`Split.rects(w, h, share)` is the layout, on its own (tested).
]]

local Device = require("device")
local Geom = require("ui/geometry")
local Log = require("gzreader_log")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local _ = require("gettext")

local Split = {
    --- The book's share of the screen.
    SHARE = 0.5,
    --- A screen at least this wide (inches, its short side) has room for two.
    MIN_INCHES = 5.5,
    pending = nil, -- { pane, title }: for the drawing screen about to open
    active = nil,  -- { reader, book, pane }: while it's open
}

--- The two parts of a `w` x `h` screen: the book's (from the top-left
--- corner) and the notes'. Upright: one above the other; on its side: side
--- by side. `share`: the book's part of the long side.
function Split.rects(w, h, share)
    share = math.max(0.3, math.min(0.7, share or Split.SHARE))
    if h >= w then
        local bh = math.floor(h * share)
        return { x = 0, y = 0, w = w, h = bh }, { x = 0, y = bh, w = w, h = h - bh }
    end
    local bw = math.floor(w * share)
    return { x = 0, y = 0, w = bw, h = h }, { x = bw, y = 0, w = w - bw, h = h }
end

--- True on a screen with room for a book and notes side by side (inches of
--- its short side, from its pixels and DPI), with a touch screen.
function Split.fits(w, h, dpi, touch)
    if touch == false or not (w and h and dpi and dpi > 0) then return false end
    return math.min(w, h) / dpi >= Split.MIN_INCHES
end

function Split.available()
    local ok, yes = pcall(function()
        return Split.fits(Screen:getWidth(), Screen:getHeight(), Screen:getDPI(), Device:isTouchDevice())
    end)
    return ok and yes == true
end

--- The open book laid out in `g` (a Geom from the screen's corner): its
--- text flows again to that size and it stays at the same place in the book.
function Split.setReader(ui, g)
    ui.dimen = g
    if ui.view and ui.view.onSetDimensions then ui.view:onSetDimensions(g) end
    local doc = ui.document
    if ui.rolling and doc and doc.setViewDimen then
        -- (a book that reflows: as ReaderRolling does when the screen turns, with our size)
        doc:enableInternalHistory(true)
        doc:setViewDimen(g)
        ui.rolling:onUpdatePos()
        doc:enableInternalHistory(false)
        ui.rolling:onRedrawCurrentView()
    elseif ui.zooming and ui.zooming.onSetDimensions then
        -- (a PDF or comic: fitted again to the part it has)
        ui.zooming:onSetDimensions(g)
        if ui.paging and ui.paging.onRedrawCurrentPage then ui.paging:onRedrawCurrentPage() end
    end
    UIManager:setDirty(ui.dialog or ui, "partial")
end

local function reader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance or nil
end

--- The book's name, for the note's (from the book's own details; else its file's name).
function Split.bookTitle(ui)
    local props = ui and ui.doc_props
    local title = type(props) == "table" and (props.display_title or props.title)
    if (not title or title == "") and ui and ui.document and ui.document.file then
        title = ui.document.file:match("([^/]+)%.[^.]+$")
    end
    return title or ""
end

--- Opens the notes beside the open book: a new drawing (named for the
--- book; Done saves it as a note). Returns false, why when it can't.
function Split.open(plugin)
    local ui = reader()
    if not ui then return false, "no book" end
    if Split.active then return false, "open" end
    if not Split.available() then return false, "screen" end
    local Notes = require("gzreader_notes")
    if not Notes.client(plugin):isConnected() then return Notes.showConnect(plugin) end
    local book, pane = Split.rects(Screen:getWidth(), Screen:getHeight())
    Split.active = { reader = ui, book = book, pane = pane }
    local ok, err = pcall(Split.setReader, ui, Geom:new(book))
    if not ok then
        Split.active = nil
        Log.warn("split view: the book couldn't be laid out beside the notes:", tostring(err))
        return false, "layout"
    end
    Split.pending = { pane = pane, title = Split.bookTitle(ui) }
    Log.info("split view: the book in", book.w .. "x" .. book.h, "the notes in", pane.w .. "x" .. pane.h, "at", pane.x .. "," .. pane.y)
    local opened, why = pcall(Notes.edit, plugin, nil, { draw = true })
    -- (the drawing screen takes `pending` as it opens; still there: it didn't open)
    if not opened or Split.pending then
        Log.warn("split view: the notes didn't open:", tostring(why))
        Split.pending = nil
        Split.closed()
        return false, "notes"
    end
    return true
end

--- For the drawing screen as it opens: the pane to open in and the note's
--- name, once (nil when no split view is being opened).
function Split.take()
    local p = Split.pending
    Split.pending = nil
    return p
end

--- The drawing screen beside the book closed: the book has the screen again.
function Split.closed()
    local a = Split.active
    Split.active = nil
    if not a then return end
    local ui = reader()
    if ui and ui == a.reader then
        local ok, err = pcall(Split.setReader, ui, Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
        if not ok then Log.warn("split view: the book's own size not put back:", tostring(err)) end
    end
    UIManager:setDirty("all", "full")
    Log.info("split view: closed")
end

--- The quick panel's tile (a book open, a big touch screen, Memos connected).
function Split.tile(plugin)
    if not Split.available() or Split.active then return nil end
    local store = plugin and plugin.store and plugin.store.memos
    if not (type(store) == "table" and require("gzreader_memos"):new(store):isConnected()) then return nil end
    return { id = "split", icon = "quicknote", label = _("Notes beside the book"), run = function() Split.open(plugin) end }
end

return Split
