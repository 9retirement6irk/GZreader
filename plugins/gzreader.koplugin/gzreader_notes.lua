--[[--
The Notes tab: your Memos notes as sticky notes.

- Board: sticky notes, pinned first (Q, W, E… open one; ◀ ▶ pages). L layout:
  a list, two or three side by side, or Auto; Compact (every note the same
  size, six to a page two side by side) or Full (whole notes, as long as
  they need: gzreader_notelayout.lua). N new note, F filter, L layout,
  S sort, M connection (refresh, connect again, disconnect). (Not the Menu
  key: ZenOS sends it from tab views to the Home menu; a Kindle 4's Menu
  opens Notes.showMenu.)
- Wi-Fi: only to sync (when the tab opens, at most every 5 minutes, or with
  changes waiting; Connection → Refresh any time), to send what you change, and to
  open an attachment not on the Kindle yet. Browsing never needs it:
  notes, and the pictures in them, are kept on the Kindle.
- A note: the whole text, checklist items you tick with their letter key
  (saved to Memos), pictures, tags, place, attachments (PDFs open in the
  reader, pictures in the image viewer). Alt+E edit, Alt+P pin.
- Filters: tag, date, place, with attachments, pinned, search.
- Offline: the last notes are kept on the Kindle; changes wait for Wi-Fi.

The board is a KOReader Menu so ZenOS puts its tab bar under it (Notes
replaces Favorites); its page is drawn as sticky notes (gzreader_sticky).
]]

local Blitbuffer = require("ffi/blitbuffer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
local Memos = require("gzreader_memos")
local NL = require("gzreader_notelayout")
local Sticky = require("gzreader_sticky")
local Touch = require("gzreader_touch")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Notes = {
    TAB_ID = "ct_notes",
    KEEP = 100,           -- notes fetched and kept (newest, pinned first); Settings → Notes
    FILES_MB = 25,        -- attachments kept on the Kindle; Settings → Notes
    filter = { kind = "all" },
    notes = nil,          -- the list shown (cache, then fresh from Memos)
}

local KEYS = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" }

function Notes.client(plugin)
    plugin.store.memos = plugin.store.memos or {}
    return Memos:new(plugin.store.memos)
end

--- Settings → Notes (kept when you disconnect).
function Notes.prefs(plugin)
    plugin.store.notes_prefs = plugin.store.notes_prefs or {}
    local p = plugin.store.notes_prefs
    p.keep = tonumber(p.keep) or Notes.KEEP
    p.files_mb = tonumber(p.files_mb) or Notes.FILES_MB -- 0: no limit
    return p
end

---------------------------------------------------------------- views

--- The board's view: { columns = "list"|"2"|"3"|"auto", display = "compact"|"full" }.
function Notes.view(plugin) return NL.view(Notes.prefs(plugin)) end

--- How many columns Auto gives on a board `width` pixels wide (the screen's).
function Notes.autoColumns(width)
    return NL.columns("auto", width or Screen:getWidth(), S(NL.AUTO_MIN_W))
end

function Notes.columnsLabel(columns, short)
    if columns == "list" then return short and _("List") or _("List: one note under another") end
    if columns == "3" then return _("Three side by side") end
    if columns == "auto" then
        return short and _("Auto") or T(_("Auto: as many as fit (%1 here)"), Notes.autoColumns())
    end
    return _("Two side by side")
end

function Notes.displayLabel(display, short)
    if display == "full" then return short and _("Full") or _("Full: whole notes, nothing cut off") end
    return short and _("Compact") or _("Compact: every note the same size")
end

--- "Two side by side, compact" (Settings → Notes).
function Notes.viewLabel(view)
    return Notes.columnsLabel(view.columns, true) .. ", " .. Notes.displayLabel(view.display, true):lower()
end

--- Change the view (`field`: "columns" or "display"); the board shows the
--- page with the note that was first on screen.
function Notes.setView(plugin, field, value)
    local p = Notes.prefs(plugin)
    if p[field] == value then return end
    p[field] = value
    plugin:save()
    local v = NL.view(p)
    Log.info("notes: view", v.columns, v.display)
    local b = Notes.board
    if b and not b._gz_closed then
        b._gz_goto = b._gz_first
        Notes.reloadBoard(true)
    end
end

--- Touch Kindles, Layout → Scroll up and down: the board is one long page
--- that a swipe or a drag up or down moves as far as the finger went (notes
--- cut off at the top and bottom show there's more), instead of turning
--- pages sideways; no page number or arrows under it. (Compact notes:
--- they're all one height. Full notes are laid out page by page, so they
--- keep their pages.)
function Notes.scrolling(plugin)
    return Touch.on() and Notes.prefs(plugin).scroll == true and Notes.view(plugin).display ~= "full"
end

function Notes.setScrolling(plugin, on)
    Notes.prefs(plugin).scroll = on and true or nil
    plugin:save()
    Log.info("notes: scrolling", tostring(on))
    local b = Notes.board
    if b and not b._gz_closed then
        b._gz_goto = b._gz_first
        Notes.reloadBoard(true)
    end
end

Notes.SCROLL_PEEK = 0.3 -- scrolling: this much of the next row of notes shows at the bottom

--- Scrolling: where the notes are for a scroll of `y` pixels. `view_h`: the
--- room for notes (the page number and arrows aren't shown, so down to the
--- bottom); `fit`: the rows that fit whole. Returns { y (kept between 0 and
--- the end), cell_h (a row's height: `fit` rows and a part of the next one
--- show), first (the first row shown, from 0), shift (how much of it is
--- above the top), rows (rows drawn, the cut-off ones too), max_y }.
function Notes.scrollLayout(y, view_h, fit, total_rows)
    local cell_h = math.max(1, math.floor(view_h / (fit + Notes.SCROLL_PEEK)))
    local max_y = math.max(0, total_rows * cell_h - view_h)
    y = math.max(0, math.min(max_y, math.floor((tonumber(y) or 0) + 0.5)))
    local first = math.floor(y / cell_h)
    local shift = y - first * cell_h
    local rows = math.min(total_rows - first, math.ceil((view_h + shift) / cell_h))
    return { y = y, cell_h = cell_h, first = first, shift = shift, rows = math.max(0, rows), max_y = max_y }
end

--- L on the board (or Layout, More → Layout): side by side, and compact or full.
function Notes.showView(plugin)
    local dialog
    local view = Notes.view(plugin)
    local function row(field, value, text)
        return { { text = text .. (view[field] == value and "  \u{2713}" or ""), align = "left", callback = function()
            UIManager:close(dialog)
            Notes.setView(plugin, field, value)
        end } }
    end
    local rows = {}
    for _i, c in ipairs(NL.COLUMNS) do rows[#rows + 1] = row("columns", c, Notes.columnsLabel(c)) end
    for _i, d in ipairs(NL.DISPLAYS) do rows[#rows + 1] = row("display", d, Notes.displayLabel(d)) end
    if Touch.on() then
        local on = Notes.prefs(plugin).scroll == true
        rows[#rows + 1] = { { text = _("Scroll up and down (compact notes)") .. (on and "  \u{2713}" or ""), align = "left",
            callback = function()
                UIManager:close(dialog)
                Notes.setScrolling(plugin, not on)
            end } }
    end
    rows[#rows + 1] = { { text = _("Full screen: no tab bar") .. (Notes.fullscreen(plugin) and "  \u{2713}" or ""), align = "left",
        callback = function()
            UIManager:close(dialog)
            Notes.setFullscreen(plugin, not Notes.fullscreen(plugin))
        end } }
    dialog = Notes.keyedDialog(_("Layout"), rows)
    return dialog
end

--- Layout → Full screen: the Notes tab without the tab bar at the bottom
--- (more room for notes). The X button where its icon was leaves it (or
--- Layout, or a Kindle 4's Menu; Back or the quick panel's Home leave the tab).
Notes.FULLSCREEN_NAME = "gz_notes_fullscreen"
function Notes.fullscreen(plugin) return Notes.prefs(plugin).fullscreen == true end

function Notes.setFullscreen(plugin, on)
    local p = Notes.prefs(plugin)
    if (p.fullscreen == true) == (on == true) then return end
    p.fullscreen = on == true or nil
    plugin:save()
    Log.info("notes: full screen", on == true)
    -- (ZenOS adds the tab bar when a tab view is made: the board is made again)
    local b = Notes.board
    if b and not b._gz_closed then
        local page_note = b._gz_first
        UIManager:close(b)
        local nb = Notes.show(plugin)
        if nb and page_note then nb._gz_goto = page_note; Notes.reloadBoard(true) end
    end
end

---------------------------------------------------------------- sorting

Notes.SORTS = { { "created", _("Date created") }, { "updated", _("Date edited") } }

--- How the notes are sorted (the Notes tab's Sort button, or S):
--- { by = "created"|"updated", reverse = bool (oldest first), pinned = bool (pinned first) }.
function Notes.sort(plugin)
    local p = Notes.prefs(plugin)
    return { by = p.sort == "updated" and "updated" or "created", reverse = p.sort_reverse == true,
        pinned = p.sort_pinned ~= false }
end

--- Memos' order_by for it ("pinned desc, create_time desc" by default).
function Notes.orderBy(plugin)
    local so = Notes.sort(plugin)
    local field = (so.by == "updated" and "update_time" or "create_time") .. (so.reverse and " asc" or " desc")
    return so.pinned and ("pinned desc, " .. field) or field
end

--- `list` in that order, on the Kindle too (notes kept from before, notes
--- written here and not sent yet, a sync through a computer).
function Notes.sorted(list, plugin)
    local so = Notes.sort(plugin)
    local key = so.by == "updated" and "updated" or "created"
    local out, pos = {}, {}
    for i, m in ipairs(list) do out[i] = m; pos[m] = i end
    local function t(m) return tostring(m[key] or m.created or "") end
    table.sort(out, function(a, b)
        if so.pinned and (a.pinned == true) ~= (b.pinned == true) then return a.pinned == true end
        local ta, tb = t(a), t(b)
        if ta ~= tb then
            if so.reverse then return ta < tb end
            return ta > tb
        end
        return pos[a] < pos[b] -- (stable)
    end)
    return out
end

function Notes.setSort(plugin, field, value)
    local p = Notes.prefs(plugin)
    p[field] = value
    plugin:save()
    Log.info("notes: sort", Notes.orderBy(plugin))
    Notes.reloadBoard(false)
    -- (Memos sends the first notes in this order: with more than are kept, others)
    Notes.refresh(plugin, function(ok) if ok then Notes.reloadBoard(false) end end)
end

--- The Notes tab's Sort: "Sort notes by".
function Notes.showSort(plugin)
    local dialog
    local so = Notes.sort(plugin)
    local function pick(fn) return function() UIManager:close(dialog); fn() end end
    local rows = {}
    for _i, sd in ipairs(Notes.SORTS) do
        rows[#rows + 1] = { { text = sd[2] .. (so.by == sd[1] and "  \u{2713}" or ""), align = "left",
            callback = pick(function() Notes.setSort(plugin, "sort", sd[1]) end) } }
    end
    rows[#rows + 1] = { { text = _("Reverse order (oldest first)") .. (so.reverse and "  \u{2713}" or ""), align = "left",
        callback = pick(function() Notes.setSort(plugin, "sort_reverse", not so.reverse or nil) end) } }
    rows[#rows + 1] = { { text = _("Pinned first") .. (so.pinned and "  \u{2713}" or ""), align = "left",
        callback = pick(function() Notes.setSort(plugin, "sort_pinned", (not so.pinned) and true or false) end) } }
    dialog = Notes.keyedDialog(_("Sort notes by"), rows)
    return dialog
end

--- Whether the Notes tab is what's on screen (nothing over the board).
function Notes.onTop()
    local b = Notes.board
    if not b or b._gz_closed then return false end
    local stack = UIManager._window_stack or {}
    local top = stack[#stack]
    return top ~= nil and top.widget == b
end

--- The tags chosen in Settings → Notes → Sync only these tags, or nil (all notes).
function Notes.syncTags(plugin)
    local t = plugin.store.memos and plugin.store.memos.sync_tags
    return (type(t) == "table" and #t > 0) and t or nil
end

--- Your Memos spaces ({ { name = "spaces/…", title }, … }, Memos v0.31) as
--- of the last sync, or nil (a Memos without spaces, or not synced yet).
function Notes.spaces(plugin)
    local t = plugin and plugin.store.memos and plugin.store.memos.spaces
    return (type(t) == "table" and #t > 0) and t or nil
end

--- A space's title ("spaces/family" → "Family"), from the last sync.
function Notes.spaceTitle(plugin, name)
    if not name or name == "" then return nil end
    for _i, sp in ipairs(Notes.spaces(plugin) or {}) do
        if sp.name == name then return sp.title end
    end
    return name:match("^spaces/(.+)$") or name -- (a space not synced yet: its id)
end

local function quote(v) return '"' .. tostring(v):gsub('[\\"]', "\\%0") .. '"' end

--- The whole Memos filter: the synced tags (if chosen) and the board's filter.
function Notes.query(plugin, f)
    local parts = {}
    local tags = Notes.syncTags(plugin)
    if tags then
        local q = {}
        for _i, t in ipairs(tags) do q[#q + 1] = quote(t) end
        parts[#parts + 1] = "tag in [" .. table.concat(q, ", ") .. "]"
    end
    local cel = Notes.cel(f)
    if cel then parts[#parts + 1] = cel end
    if #parts == 0 then return nil end
    if #parts == 1 then return parts[1] end
    return "(" .. table.concat(parts, ") && (") .. ")"
end

local function closeTop(w, mode) if w then UIManager:close(w, mode or "ui") end end

local function info(text, timeout) UIManager:show(InfoMessage:new{ text = text, timeout = timeout }) end

---------------------------------------------------------------- data

--- Memos' filter (CEL) for the server-side part of the current filter.
function Notes.cel(f)
    f = f or Notes.filter
    if require("gzreader_net").usb then return nil end -- (no Memos to ask: Notes.keep filters here)
    if f.kind == "tag" then return string.format('%q in tags', f.value) end
    if f.kind == "pinned" then return "pinned == true" end
    if f.kind == "date" then return string.format('created_ts > now - duration("%dh")', f.value * 24) end
    if f.kind == "search" then return string.format("content.contains(%q)", f.value) end
    if f.kind == "space" then -- ("" for notes in no space)
        return f.value == "" and "space == null" or string.format("space == %q", f.value)
    end
    return nil
end

--- The part done on the Kindle (Memos v0.31 can't filter by place or attachments).
function Notes.keep(m, f)
    f = f or Notes.filter
    if require("gzreader_net").usb then return Notes.keepHere(m, f) end
    if f.kind == "place" then return m.place == f.value end
    if f.kind == "attachments" then return #(m.attachments or {}) > 0 end
    if f.kind == "drawings" then return Notes.hasDrawing(m) end
    return true
end

--- A note with a drawing (a sheet): the Drawings filter.
function Notes.hasDrawing(m)
    for _i, a in ipairs(m.attachments or {}) do
        if Notes.isDrawing(a) then return true end
    end
    return false
end

--- Every filter, worked out on the Kindle (syncing through a computer: no Memos to ask).
function Notes.keepHere(m, f)
    if f.kind == "tag" then
        for _i, t in ipairs(m.tags or {}) do if t == f.value then return true end end
        return false
    end
    if f.kind == "pinned" then return m.pinned == true end
    if f.kind == "date" then
        local y, mo, d, h, mi, s = tostring(m.created or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
        if not y then return true end
        local t = os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(s) }
        return t > os.time() - (tonumber(f.value) or 0) * 86400 - 86400
    end
    if f.kind == "search" then return tostring(m.content or ""):lower():find(tostring(f.value):lower(), 1, true) ~= nil end
    if f.kind == "place" then return m.place == f.value end
    if f.kind == "attachments" then return #(m.attachments or {}) > 0 end
    if f.kind == "drawings" then return Notes.hasDrawing(m) end
    if f.kind == "space" then return (m.space or "") == f.value end
    return true
end

--- The notes the board shows. While they're the saved copy (every note kept
--- on the Kindle, before Memos has answered for this filter, or when it
--- can't be reached) the filter is worked out here.
function Notes.visible()
    local out = {}
    local here = Notes.from_cache == true
    for _i, m in ipairs(Notes.notes or {}) do
        local ok
        if here then ok = Notes.keepHere(m, Notes.filter) else ok = Notes.keep(m) end
        if ok then out[#out + 1] = m end
    end
    return out
end

function Notes.filterLabel(f)
    f = f or Notes.filter
    if f.kind == "tag" then return "#" .. f.value end
    if f.kind == "date" then return f.label end
    if f.kind == "place" then return f.value end
    if f.kind == "attachments" then return _("With attachments") end
    if f.kind == "drawings" then return _("Drawings") end
    if f.kind == "pinned" then return _("Pinned") end
    if f.kind == "search" then return "\u{201C}" .. f.value .. "\u{201D}" end
    if f.kind == "space" then return f.value == "" and _("No space") or (f.label or f.value) end
    return _("All notes")
end

--- Notes from the cache (shown at once), with queued changes applied.
function Notes.loadCache(plugin)
    local cache = Memos.loadCache()
    Notes.notes = cache and cache.notes or {}
    Notes.cached_at = cache and cache.at
    Notes.from_cache = true -- (all the kept notes: Notes.visible filters them here)
    Notes.applyQueue(plugin)
end

--- Show local changes not yet in Memos (new notes, edits, ticks, pins).
function Notes.applyQueue(plugin)
    local store = plugin.store.memos or {}
    for _i, q in ipairs(store.queue or {}) do
        if q.op == "create" then
            local seen = false
            for _j, m in ipairs(Notes.notes) do if m.local_id == q.id then seen = true end end
            if not seen then
                table.insert(Notes.notes, 1, { local_id = q.id, content = q.content, tags = Notes.tagsIn(q.content),
                    created = os.date("!%Y-%m-%dT%H:%M:%SZ", q.at), attachments = Notes.queuedAttachments(q), pinned = false,
                    pending = true, visibility = q.visibility, space = q.space })
            end
        else
            for _j, m in ipairs(Notes.notes) do
                if m.name == q.name then
                    if q.op == "update" then
                        m.content = q.content; m.tags = Notes.tagsIn(q.content)
                        if q.visibility then m.visibility = q.visibility end
                        if q.space then m.space = q.space ~= "" and q.space or nil end
                    end
                    if q.op == "pin" then m.pinned = q.pinned end
                    m.pending = true
                end
            end
        end
    end
end

--- A queued note's drawings as attachments the board can show before
--- they're in Memos (`Notes.showDrawingNow` puts their files where the board looks).
function Notes.queuedAttachments(q)
    local out = {}
    for k, d in ipairs(Memos.queuedDrawings(q)) do
        if d.filename then
            out[#out + 1] = { name = "attachments/local-" .. tostring(q.id) .. (k > 1 and ("-" .. k) or ""),
                filename = d.filename, type = "image/png" }
        end
    end
    return out
end

--- Drawings (memos' `drawing-…canvas.png` attachments) show in the note,
--- as big as there's room for: enlarged at most this many times.
Notes.DRAWING_GROW = 3

--- True for a memos drawing (an attachment named like one).
function Notes.isDrawing(att)
    return type(att) == "table" and require("gzreader_drawing").isDrawingName(att.filename)
end

--- Note `m`'s drawings that aren't already pictures in its text: the note's
--- page shows them after its text, the board as its picture.
function Notes.drawings(m)
    local inline = {}
    for _i, l in ipairs(Sticky.lines(m.content)) do
        local uid = l.kind == "image" and tostring(l.src):match("/file/attachments/([^/%?]+)")
        if uid then inline[uid] = true end
    end
    local out = {}
    for _i, a in ipairs(m.attachments or {}) do
        if Notes.isDrawing(a) and not inline[tostring(a.name):match("attachments/(.+)$") or ""] then out[#out + 1] = a end
    end
    return out
end

--- A note's first heading (its text) and the rest of its preview without
--- that heading: a note with a drawing shows the heading above it.
function Notes.headingAndRest(content)
    local heading, rest = nil, {}
    for _i, l in ipairs(Sticky.lines(content)) do
        if l.kind == "heading" and not heading then heading = Sticky.plain(l.text)
        elseif l.kind == "check" then rest[#rest + 1] = (l.done and "\u{2611} " or "\u{2610} ") .. Sticky.plain(l.text)
        elseif l.kind == "heading" then rest[#rest + 1] = Sticky.plain(l.text)
        elseif l.kind == "text" and l.text:match("%S") and not Sticky.tagsOnly(l.text) then rest[#rest + 1] = Sticky.plain(l.text) end
    end
    if heading and not heading:match("%S") then heading = nil end
    return heading, (table.concat(rest, "\n"):gsub("^%s+", ""))
end

--- The size picture `a` (w x h in its file) is drawn at, for max_w x max_h:
--- { w, h, grow }. A drawing is enlarged to fit too (DRAWING_GROW times at
--- most); a photo only shrinks.
function Notes.fitPicture(a, w, h, max_w, max_h)
    local grow = Notes.isDrawing(a) and Notes.DRAWING_GROW or nil
    local fw, fh = Sticky.fitSize(w, h, max_w, max_h, grow)
    return { w = fw, h = fh, grow = grow }
end

--- Draws the board again (a picture arrived).
function Notes.redrawBoard()
    if Notes.board and not Notes.board._gz_closed then Notes.board:updateItems() end
end

--- A drawing, as big as fits max_w x max_h (enlarged up to DRAWING_GROW
--- times), framed; nil when it isn't on the Kindle yet: then it's fetched
--- (Wi-Fi up) and on_ready() runs once it's here.
function Notes.drawingWidget(plugin, att, max_w, max_h, on_ready)
    local path = Memos.filePath(att)
    if lfs.attributes(path, "mode") ~= "file" then
        Notes.fetchFile(plugin, att, on_ready)
        return nil
    end
    local bb = Sticky.picture(path, max_w, max_h, Notes.DRAWING_GROW)
    if not bb then return nil end
    return FrameContainer:new{ padding = 0, bordersize = Size.border.thin, ImageWidget:new{ image = bb, image_disposable = true } }
end

--- Over each sheet of a note with several: "Page 2 of 3" (keyboard Kindles: and the key that opens it).
function Notes.pageCaption(i, n, key)
    local text = T(_("Page %1 of %2"), i, n)
    return key and (text .. "  \u{00B7}  " .. T(_("%1 opens it"), key)) or text
end

--- A drawing changed in a note already in Memos (`drawing`: { path,
--- filename } or { removed = true }): queued (its new file over the old one,
--- the note's first drawing gone, or a first drawing added), and shown here
--- at once.
function Notes.saveDrawing(plugin, memo, drawing)
    local att = Notes.drawings(memo)[1]
    if drawing.removed then
        if not att then return end
        Notes.enqueue(plugin, { op = "undraw", name = memo.name, attachment = att.name })
        for i, a in ipairs(memo.attachments or {}) do
            if a == att then table.remove(memo.attachments, i); break end
        end
        Log.info("notes: a drawing taken off a note")
    elseif att then
        Notes.enqueue(plugin, { op = "redraw", name = memo.name, attachment = att.name,
            drawing = { path = drawing.path, filename = drawing.filename } })
        local src = io.open(drawing.path, "rb")
        local data = src and src:read("*a")
        if src then src:close() end
        local dst = data and io.open(Memos.filePath(att), "wb")
        if dst then dst:write(data); dst:close() end
        Notes.pic_sizes[Memos.filePath(att)] = nil
        Log.info("notes: a drawing edited")
    else
        local q = Notes.enqueue(plugin, { op = "attach", name = memo.name,
            drawing = { path = drawing.path, filename = drawing.filename } })
        Notes.showDrawingNow(q)
        memo.attachments = memo.attachments or {}
        table.insert(memo.attachments, Notes.queuedAttachments(q)[1])
        Log.info("notes: a drawing added to a note")
    end
    -- (kept note images, if the board keeps them, show the old drawing: drawn again)
    if Notes.dropImages then pcall(Notes.dropImages, true) end
    Notes.sendSoon(plugin)
end

--- Copies a queued note's drawings to where the board finds the note's pictures.
function Notes.showDrawingNow(q)
    local list = Memos.queuedDrawings(q)
    for k, att in ipairs(Notes.queuedAttachments(q)) do
        local src = list[k] and io.open(list[k].path, "rb")
        if src then
            local data = src:read("*a")
            src:close()
            local dst = io.open(Memos.filePath(att), "wb")
            if dst then dst:write(data); dst:close() end
        end
    end
end

--- Drawings changed in a note already in Memos (`list`: { att, path,
--- filename } drawn or edited, { att, removed = true } taken off; no att: a
--- new one): queued, and shown here at once.
function Notes.saveDrawings(plugin, memo, list)
    for _i, d in ipairs(list or {}) do
        if d.removed then
            if d.att then
                Notes.enqueue(plugin, { op = "undraw", name = memo.name, attachment = d.att.name })
                for i, a in ipairs(memo.attachments or {}) do
                    if a.name == d.att.name then table.remove(memo.attachments, i); break end
                end
                Log.info("notes: a drawing taken off a note")
            end
        elseif d.att then
            Notes.enqueue(plugin, { op = "redraw", name = memo.name, attachment = d.att.name,
                drawing = { path = d.path, filename = d.filename } })
            local src = io.open(d.path, "rb")
            local data = src and src:read("*a")
            if src then src:close() end
            local dst = data and io.open(Memos.filePath(d.att), "wb")
            if dst then dst:write(data); dst:close() end
            Notes.pic_sizes[Memos.filePath(d.att)] = nil
            Log.info("notes: a drawing edited")
        else
            local q = Notes.enqueue(plugin, { op = "attach", name = memo.name,
                drawing = { path = d.path, filename = d.filename } })
            Notes.showDrawingNow(q)
            memo.attachments = memo.attachments or {}
            table.insert(memo.attachments, Notes.queuedAttachments(q)[1])
            Log.info("notes: a drawing added to a note")
        end
    end
    -- the pages in their order, in Memos (which lists them newest first) and here
    if type(list) == "table" and type(list.order) == "table" and #list.order > 1 then
        Notes.enqueue(plugin, { op = "order", name = memo.name, order = list.order })
        local names = Memos.drawingOrder(memo.attachments, list.order)
        if names then
            local by = {}
            for _i, a in ipairs(memo.attachments) do by[a.name] = a end
            local sorted = {}
            for i, n in ipairs(names) do sorted[i] = by[n] end
            memo.attachments = sorted
        end
    end
    if Notes.dropImages then pcall(Notes.dropImages, true) end
    Notes.sendSoon(plugin)
end

--- Draw in a new note: touch Kindles, Memos over Wi-Fi (the sync page
--- doesn't send drawings).
function Notes.canDraw(plugin)
    if require("gzreader_net").usb then return false end
    return Touch.on() and not Touch.keys() and Notes.client(plugin):isConnected()
end

--- Draw (the Notes tab's button): a new note that opens on a page to draw
--- on (Done goes to its text, Save sends it). Drawings need Memos over Wi‑Fi.
function Notes.draw(plugin)
    if not Notes.canDraw(plugin) then
        return info(require("gzreader_net").usb and _("Drawings go to Memos over Wi‑Fi, not through the computer.")
            or _("Drawing needs Memos connected."), 3)
    end
    return Notes.edit(plugin, nil, { draw = true })
end

function Notes.tagsIn(content)
    local tags, seen = {}, {}
    for tag in ((" " .. (content or "")):gmatch("[%s%(]#([%w_%-/]+)")) do
        if not seen[tag] then seen[tag] = true; tags[#tags + 1] = tag end
    end
    return tags
end

--- Queue a change (sent now when possible).
function Notes.enqueue(plugin, q)
    local store = plugin.store.memos
    store.queue = store.queue or {}
    store.seq = (store.seq or 0) + 1
    q.id, q.at = "q" .. store.seq, os.time()
    -- one pending edit per note is enough
    if q.op == "update" then
        for i = #store.queue, 1, -1 do
            if store.queue[i].op == "update" and store.queue[i].name == q.name then table.remove(store.queue, i) end
        end
    end
    table.insert(store.queue, q)
    plugin:save()
    return q
end

--- Send queued changes, then fetch the notes for the current filter.
--- on_done(ok, err) on the screen's thread. opts.send_only: send the queue
--- and stop (a quick note while reading: the board isn't loaded, so there's
--- nothing to show the list in; the next time the tab opens it syncs).
function Notes.refresh(plugin, on_done, opts)
    -- (syncing through a computer: the notes come with the next sync)
    if require("gzreader_net").usb then return on_done and on_done(false, "usb") end
    local client = Notes.client(plugin)
    if not client:isConnected() then return on_done and on_done(false, "not_connected") end
    if Notes.refreshing then
        -- (one at a time. A filter chosen meanwhile is asked for when this one is back:
        -- its answer isn't shown as the new filter's notes)
        if not (opts and opts.send_only) then Notes.refresh_again = { on_done = on_done, opts = opts } end
        return
    end
    Notes.refreshing = true
    -- another refresh asked for while this one ran: now
    local function andThen(ok, err, stale)
        local again = Notes.refresh_again
        Notes.refresh_again = nil
        if stale and not again then again = { on_done = on_done } end
        if not again then return end
        if stale then return Notes.refresh(plugin, again.on_done, again.opts) end
        if again.on_done then again.on_done(ok, err) end -- (the same notes: this answer is its too)
    end
    local Async = require("gzreader_async")
    local store = plugin.store.memos
    local function fetch()
        local query = Notes.query(plugin)
        local keep = Notes.prefs(plugin).keep
        local order = Notes.orderBy(plugin)
        Async.run(client, function(c) return c:listAll(query, keep, order) end, function(res, err)
            Notes.refreshing = false
            local stale = Notes.query(plugin) ~= query or Notes.orderBy(plugin) ~= order
            if not res then
                Log.warn("notes: refresh failed:", tostring(err))
                Notes.last_error = err
                if on_done and not stale then on_done(false, err) end
                return andThen(false, err, stale)
            end
            Notes.last_error = nil
            if res.prefix and res.prefix ~= store.prefix then store.prefix = res.prefix; plugin:save() end
            if type(res.tags) == "table" then
                store.tag_counts = res.tags
                plugin:save()
            elseif not Notes.cel() then
                -- (a Memos that doesn't say: counted from all the notes it sent, and kept)
                store.tag_counts = Notes.countTags(res.memos)
                plugin:save()
            end
            if type(res.spaces) == "table" then store.spaces = res.spaces; plugin:save() end
            -- (false: this Memos has no journaling mode, the defaults again; nil: no answer, as it was)
            if res.journal ~= nil and (res.journal or nil) ~= store.journal then store.journal = res.journal or nil; plugin:save() end
            if stale then
                -- (the filter changed while Memos answered: these aren't its notes)
                Log.info("notes: an answer for another filter, asking again")
                return andThen(true, nil, true)
            end
            Notes.notes = res.memos
            Notes.from_cache = false -- (Memos' answer for this filter)
            Notes.applyQueue(plugin)
            if not Notes.cel() then Memos.saveCache({ notes = res.memos, at = os.time() }) end
            Notes.cached_at = os.time()
            Log.info("notes: refreshed", #res.memos)
            Notes.last_sync = os.time()
            Notes.prefetchPictures(plugin)
            if on_done then on_done(true) end
            andThen(true)
        end, "notes: list")
    end
    if store.queue and #store.queue > 0 then
        local queue = store.queue
        -- drawings to send: Wi-Fi power saving off until they're done (gzreader_wifips.lua)
        local uploads = false
        for _i, q in ipairs(queue) do
            if q.op == "redraw" or #Memos.queuedDrawings(q) > 0 then uploads = true break end
        end
        if uploads then pcall(function() require("gzreader_wifips").hold("memos-upload") end) end
        Async.run(client, function(c) return c:flush(queue) end, function(res)
            if uploads then pcall(function() require("gzreader_wifips").release("memos-upload") end) end
            if type(res) == "table" then
                if res.prefix and res.prefix ~= store.prefix then store.prefix = res.prefix end
                local gone = {}
                for _i, id in ipairs(res.done or {}) do gone[id] = true end
                local left = {}
                for _i, q in ipairs(store.queue or {}) do
                    if not gone[q.id] then
                        -- a note made whose drawings didn't all go: send only those left next time
                        local made = type(res.attached) == "table" and res.attached[q.id]
                        if made then q.op, q.name = "attach", made end
                        local sent = type(res.sent) == "table" and tonumber(res.sent[q.id])
                        if sent and sent > 0 then
                            local list = Memos.queuedDrawings(q)
                            for k = 1, sent do if list[k] and list[k].path then os.remove(list[k].path) end end
                            local rest = {}
                            for k = sent + 1, #list do rest[#rest + 1] = list[k] end
                            q.drawings, q.drawing = rest, nil
                        end
                        left[#left + 1] = q
                    else
                        -- (in Memos now; the board shows them from there)
                        for _k, d in ipairs(Memos.queuedDrawings(q)) do if d.path then os.remove(d.path) end end
                    end
                end
                store.queue = left
                -- notes whose drawings went but aren't in order yet: only that, next time
                for _i, q in ipairs(queue) do
                    local name = gone[q.id] and type(res.reorder) == "table" and res.reorder[q.id]
                    if name and q.order then Notes.enqueue(plugin, { op = "order", name = name, order = q.order }) end
                end
                plugin:save()
                if res.err then Log.warn("notes: queued changes:", tostring(res.err), #left, "left") end
            end
            if opts and opts.send_only then
                Notes.refreshing = false
                Notes.last_sync = nil -- (the board fetches the list when it next opens)
                local sent = type(res) == "table" and not res.err
                if on_done then on_done(sent, not sent and (type(res) == "table" and res.err or "failed") or nil) end
                return andThen(true, nil, Notes.refresh_again ~= nil)
            end
            fetch()
        end, "notes: send changes")
    elseif opts and opts.send_only then
        Notes.refreshing = false
        if on_done then on_done(true) end
        andThen(true, nil, Notes.refresh_again ~= nil)
    else
        fetch()
    end
end

local function describe(err)
    if err == "unauthorized" then return _("Memos didn't accept the access token. Connect again with a new one (Connection → Connect again).") end
    if err == "unreachable" then return _("Couldn't reach Memos. Check Wi-Fi and the address.") end
    if err == "not_connected" then return _("Not connected to Memos.") end
    if err == "usb" then return _("Notes come from Memos through your computer: they're brought and sent with each sync (Menu → Sync with computer).") end
    if err == "timeout" then return _("Memos took too long to answer.") end
    return T(_("Memos answered: %1"), tostring(err))
end
Notes.describe = describe

---------------------------------------------------------------- the board

-- A note on the board: the whole note, the same size as the others
-- (compact), or `part` of it as long as it needs (full: lines from…to of
-- its text, its pictures, its tags and place; gzreader_notelayout.lua).
local StickyItem = InputContainer:extend{ entry = nil, menu = nil, dimen = nil, shortcut = nil, look = nil, focused = false,
    part = nil, size = nil }

function StickyItem:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    self:draw()
end

Notes._StickyItem = StickyItem -- (tests)

local PAD = 8 -- (scaled) inside a note's frame
local HEAD_H, HEAD_GAP, GAP = 24, 6, 4 -- (scaled) the date line, under it, between the rest

--- A note's width in a `cell_w` wide place on the board (room for its
--- shadow, tape and tilt; at least as much as the board before views had).
function Notes.noteWidth(cell_w)
    local w = math.floor(cell_w * 0.88)
    if cell_w - w < S(36) then w = cell_w - S(36) end
    return math.max(S(60), w)
end

--- The date line: letter key, date (and "not sent yet", "continued"), pin.
local function noteHead(m, inner_w, shortcut, continued)
    local sc = shortcut and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(24), h = S(24) }, shortcut, "square")
    local when = Sticky.when(m.created)
    if m.pending then when = when .. " \u{2022} " .. _("not sent yet") end
    if continued then when = when .. " \u{2022} " .. _("continued") end
    return OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = S(HEAD_H) },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = S(HEAD_H) },
            HorizontalGroup:new{ sc or HorizontalSpan:new{ width = 0 }, HorizontalSpan:new{ width = sc and S(6) or 0 },
                TextWidget:new{ text = when, face = Sticky.hand(15), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = inner_w - S(50) } } },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = S(HEAD_H) },
            m.pinned and TextWidget:new{ text = Sticky.ICONS.pin, face = Sticky.iconFace(15) } or HorizontalSpan:new{ width = 0 } },
    }
end

--- The note's tags (a line, or nil) and its place and attachment count (a row).
local function noteFoot(m, inner_w)
    local foot_bits = HorizontalGroup:new{ align = "center" }
    if m.place then
        foot_bits[#foot_bits + 1] = TextWidget:new{ text = Sticky.ICONS.place .. " ", face = Sticky.iconFace(13) }
        foot_bits[#foot_bits + 1] = TextWidget:new{ text = m.place, face = Font:getFace("cfont", 13), max_width = math.floor(inner_w * 0.6) }
    end
    if #(m.attachments or {}) > 0 then
        foot_bits[#foot_bits + 1] = HorizontalSpan:new{ width = S(10) }
        foot_bits[#foot_bits + 1] = TextWidget:new{ text = Sticky.ICONS.attach .. " ", face = Sticky.iconFace(13) }
        foot_bits[#foot_bits + 1] = TextWidget:new{ text = tostring(#m.attachments), face = Font:getFace("cfont", 13) }
    end
    local tags = {}
    for _i, t in ipairs(m.tags or {}) do tags[#tags + 1] = "#" .. t end
    local tag_line = #tags > 0 and TextWidget:new{ text = table.concat(tags, "  "), face = Sticky.hand(16), bold = true, max_width = inner_w }
    return tag_line or nil, #foot_bits > 0 and foot_bits or nil
end

---------------------------------------------------------------- kept note images

-- A note drawn on the board is an image (painted, shadowed, tilted: most of
-- the time the board takes). Each is kept under what it shows, so drawing
-- the board again (the tab opened again, a sync that changed nothing, a
-- page back) paints only the notes that changed. Images not on the board's
-- last page are let go when it's drawn; the last page's stay while the tab
-- is closed, except on a Kindle with little memory (the 2 and DX).
Notes.images = {}   -- key → { bb, gen }
Notes.image_gen = 0 -- the board's draws

--- Note `m` as StickyItem `item` shows it: everything its image depends on.
function Notes.imageKey(item, m)
    local tags = table.concat(m.tags or {}, " ")
    local part, size = item.part, item.size
    local pic = "" -- compact: its picture, if it's on the Kindle yet
    if not part then
        local att = Notes.pictureAttachments(m)[1]
        pic = att and (lfs.attributes(Memos.filePath(att), "mode") == "file" and "p" or "-") or ""
    end
    local look = item.look or {}
    return table.concat({ tostring(m.content), tostring(m.pinned), tostring(m.pending), Sticky.when(m.created),
        tags, tostring(m.place), #(m.attachments or {}), pic, tostring(item.shortcut), tostring(look.angle),
        tostring(look.shade), tostring(look.tape), tostring(item.focused), item.dimen.w, item.dimen.h,
        part and (part.from .. "-" .. part.to .. "-" .. part.h) or "", size and size.sig or "" }, "\0")
end

--- After a draw of the board: let go of the images it no longer shows.
function Notes.dropImages(all)
    for key, kept in pairs(Notes.images) do
        if all or kept.gen ~= Notes.image_gen then
            kept.bb:free()
            Notes.images[key] = nil
        end
    end
end

function StickyItem:draw()
    local w, h = self.dimen.w, self.dimen.h
    local m = self.entry.memo
    self.img = nil -- (Notes.images has it)
    if not m then -- "No notes" and the like
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
            TextBoxWidget:new{ text = self.entry.text, face = Sticky.hand(20), width = w - S(20), alignment = "center" } }
        return
    end
    local key = Notes.imageKey(self, m)
    local kept = Notes.images[key]
    if kept then
        kept.gen = Notes.image_gen
        if not self.part then Notes.picture(self.menu.plugin, m, 0, 0, true, true) end -- (fetch it if it's missing)
    else
        local frame, note_w, note_h
        if self.part then
            frame, note_w, note_h = self:fullNote(m)
        else
            frame, note_w, note_h = self:compactNote(m, w, h)
        end
        kept = { bb = Sticky.image(frame, note_w, note_h, self.look, self.focused), gen = Notes.image_gen }
        frame:free()
        Notes.images[key] = kept
    end
    self.img = kept.bb
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
        ImageWidget:new{ image = self.img, image_disposable = false } }
end

--- Compact: the whole note in a cell of the grid, cut off where it ends.
function StickyItem:compactNote(m, w, h)
    local note_w, note_h = Notes.noteWidth(w), math.floor(h * 0.86)
    local paper = Sticky.paper(self.look)
    local pad = S(PAD)
    local inner_w = note_w - 2 * pad - 2 * Size.border.thin
    local head = noteHead(m, inner_w, self.shortcut)
    local tag_line, foot_bits = noteFoot(m, inner_w)
    -- the text gets what's left of the note
    local body_h = note_h - 2 * pad - 2 * Size.border.thin - head:getSize().h - S(HEAD_GAP) - S(GAP)
        - (tag_line and tag_line:getSize().h or 0) - (foot_bits and foot_bits:getSize().h or 0)
    local content = VerticalGroup:new{ align = "left", head, VerticalSpan:new{ width = S(HEAD_GAP) } }
    local drawing = Notes.pictureAttachments(m)[1]
    if Notes.isDrawing(drawing) then
        -- a drawing: its heading, if it has one, then the drawing as big as fits
        -- (the rest of its text is on the note's page)
        local heading = Notes.headingAndRest(m.content)
        if heading then
            local hw = TextBoxWidget:new{ text = heading, face = Sticky.hand(21), bold = true, width = inner_w, bgcolor = paper }
            local cap = math.floor(body_h * 0.3)
            if hw:getSize().h > cap then -- (a long heading: cut off)
                hw:free()
                hw = TextBoxWidget:new{ text = heading, face = Sticky.hand(21), bold = true, width = inner_w, height = cap,
                    height_adjust = true, height_overflow_show_ellipsis = true, bgcolor = paper }
            end
            content[#content + 1] = hw
            content[#content + 1] = VerticalSpan:new{ width = S(GAP) }
        end
        -- the drawing: all the room left (measured: what's on the note so far, and its tags and footer)
        local used = S(GAP) + (tag_line and tag_line:getSize().h or 0) + (foot_bits and foot_bits:getSize().h or 0)
        for _i, part in ipairs(content) do used = used + part:getSize().h end
        local room = note_h - 2 * pad - 2 * Size.border.thin - used
        local pic = Notes.drawingWidget(self.menu.plugin, drawing, inner_w - 2 * Size.border.thin,
            math.max(S(30), room - 2 * Size.border.thin), Notes.redrawBoard)
        if pic then content[#content + 1] = pic end
    else
        local pic = Notes.picture(self.menu.plugin, m, inner_w, math.floor(body_h * 0.55), true)
        local text_h = pic and (body_h - pic:getSize().h - S(GAP)) or body_h
        content[#content + 1] = TextBoxWidget:new{ text = Sticky.preview(m.content), face = Sticky.hand(19), width = inner_w,
            height = text_h, height_adjust = false, height_overflow_show_ellipsis = true, bgcolor = paper }
        if pic then content[#content + 1] = VerticalSpan:new{ width = S(GAP) }; content[#content + 1] = pic end
    end
    content[#content + 1] = VerticalSpan:new{ width = S(GAP) }
    if tag_line then content[#content + 1] = tag_line end
    if foot_bits then content[#content + 1] = foot_bits end
    local frame = FrameContainer:new{
        width = note_w, height = note_h, padding = pad, margin = 0, bordersize = Size.border.thin,
        background = paper, color = Blitbuffer.COLOR_DARK_GRAY, content,
    }
    return frame, note_w, note_h
end

--- Full: blocks part.from…part.to of the note (Notes.measure): its lines of
--- text, then each picture, then the tags and place. Nothing cut off.
function StickyItem:fullNote(m)
    local size, part = self.size, self.part
    local note_w = size.note_w
    local paper = Sticky.paper(self.look)
    local pad = S(PAD)
    local inner_w = note_w - 2 * pad - 2 * Size.border.thin
    local content = VerticalGroup:new{ align = "left", noteHead(m, inner_w, self.shortcut, part.from > 1),
        VerticalSpan:new{ width = S(HEAD_GAP) } }
    local first_line, n_lines = nil, 0
    for b = part.from, math.min(part.to, size.lines) do
        first_line = first_line or b
        n_lines = n_lines + 1
    end
    if n_lines > 0 then
        content[#content + 1] = TextBoxWidget:new{ text = size.text, face = Sticky.hand(19), width = inner_w,
            height = n_lines * size.line_h, height_adjust = false, virtual_line_num = first_line, bgcolor = paper }
    end
    for b = math.max(part.from, size.lines + 1), part.to do
        local p = size.pics[b - size.lines]
        if p then
            content[#content + 1] = VerticalSpan:new{ width = S(GAP) }
            local bb = Sticky.picture(p.path, p.w, p.h, p.grow) -- (fitted to the room measured: never taller)
            content[#content + 1] = FrameContainer:new{ padding = 0, bordersize = Size.border.thin,
                bb and ImageWidget:new{ image = bb, image_disposable = true } or VerticalSpan:new{ width = p.h } }
        elseif b == size.lines + #size.pics + 1 then -- the tags and place, last
            content[#content + 1] = VerticalSpan:new{ width = S(GAP) }
            local tag_line, foot_bits = noteFoot(m, inner_w)
            if tag_line then content[#content + 1] = tag_line end
            if foot_bits then content[#content + 1] = foot_bits end
        end
    end
    local note_h = part.h - size.slack
    local frame = FrameContainer:new{
        width = note_w, height = note_h, padding = pad, margin = 0, bordersize = Size.border.thin,
        background = paper, color = Blitbuffer.COLOR_DARK_GRAY, content,
    }
    return frame, note_w, note_h
end

function StickyItem:onFocus()
    if not self.focused then self.focused = true; self:draw() end
    return true
end

function StickyItem:onUnfocus()
    if self.focused then self.focused = false; self:draw() end
    return true
end

--- Scrolling: whether a gesture at `ges.pos` is on the notes' window. A row
--- cut off at the bottom (or top) reaches under the tab bar (or the buttons
--- above): painted over there, but its tap area was still there, so taps on
--- the tab bar opened a hidden note instead (owner, 2026-11-16).
function StickyItem:inView(ges)
    local m = self.menu
    local port = m and m._gz_scroll and m._gz_scroll.port
    local pos = ges and ges.pos
    if not port or not pos then return true end
    local d = port.dimen
    return pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h
end

function StickyItem:onTapSelect(_arg, ges)
    if not self:inView(ges) then return false end -- (the tab bar's, or the buttons')
    if self.entry.memo then self.menu:onMenuSelect(self.entry) end
    return true
end

function StickyItem:onHoldSelect(arg, ges) return self:onTapSelect(arg, ges) end

function StickyItem:onCloseWidget()
    self.img = nil -- (kept in Notes.images: let go by Notes.dropImages)
end

--- The pictures of note `m` (attachments): the ones in its text first, in
--- order, then its other picture attachments.
function Notes.pictureAttachments(m)
    local out, seen = {}, {}
    for _i, l in ipairs(Sticky.lines(m.content)) do
        local uid = l.kind == "image" and tostring(l.src):match("/file/attachments/([^/%?]+)")
        if uid then
            for _j, a in ipairs(m.attachments or {}) do
                if not seen[a] and tostring(a.name):match("attachments/(.+)$") == uid then
                    seen[a] = true
                    out[#out + 1] = a
                end
            end
        end
    end
    for _i, a in ipairs(m.attachments or {}) do
        if not seen[a] and tostring(a.type):match("^image/") then seen[a] = true; out[#out + 1] = a end
    end
    return out
end

local function redrawBoard()
    if Notes.board and not Notes.board._gz_closed then Notes.board:updateItems() end
end

--- A picture for note `m` (its first image), shrunk: an ImageWidget or nil.
--- Not on the Kindle yet: fetched in the background, then the view redraws.
--- `fetch_only`: only that (a kept note image without its picture).
function Notes.picture(plugin, m, max_w, max_h, small, fetch_only)
    local att = Notes.pictureAttachments(m)[1]
    if not att then return nil end
    local path = Memos.filePath(att)
    if lfs.attributes(path, "mode") ~= "file" then
        if small then -- on the board: redraw it once the picture is here
            Notes.fetchFile(plugin, att, redrawBoard)
        end
        return nil
    end
    if fetch_only then return nil end
    local bb = Sticky.picture(path, max_w, max_h)
    if not bb then return nil end
    return FrameContainer:new{ padding = 0, bordersize = Size.border.thin, ImageWidget:new{ image = bb, image_disposable = true } }
end

---------------------------------------------------------------- full view: measuring

Notes.pic_sizes = {} -- path → { w, h }

--- Where the small copies of big pictures are kept (gzreader_sticky.lua's
--- Sticky.picture: a photo is shrunk once for a sticky note, not at every draw).
local small_dir
function Notes.smallDir()
    if not small_dir then
        small_dir = Memos.filesDir() .. "-small"
        lfs.mkdir(small_dir)
    end
    return small_dir
end
Sticky.small_dir = Notes.smallDir
Notes.measured = setmetatable({}, { __mode = "k" }) -- note → its measure (Notes.measure)
Notes.PIC_MAX = 0.4 -- full view: a picture at most this much of the page's height

--- A picture file's width and height: from its first bytes, or (a format
--- that can't be read that way) decoded once.
function Notes.picSize(path)
    local known = Notes.pic_sizes[path]
    if known then return known[1], known[2] end
    local w, h = Sticky.imageSize(path)
    if not w then
        local bb = Sticky.picture(path, math.huge, math.huge)
        if bb then w, h = bb:getWidth(), bb:getHeight(); bb:free() end
    end
    if not (w and h and w > 0 and h > 0) then return nil end
    Notes.pic_sizes[path] = { w, h }
    return w, h
end

local MAX_TILT = 0
for _i, look in ipairs(Sticky.LOOK) do MAX_TILT = math.max(MAX_TILT, math.abs(look.angle or 0)) end

--- The room a full-view note `note_w` wide takes besides its frame: the
--- margin for its shadow and tape, what its tilt adds, and a gap.
function Notes.slack(note_w)
    local m = S(10)
    local a = math.rad(Sticky.tilt(MAX_TILT, note_w, 0))
    return 2 * m + math.ceil((note_w + 2 * m) * math.sin(a)) + S(GAP)
end

--- Full view: note `m` as gzreader_notelayout.lua lays it out, `note_w`
--- wide on a page `page_h` tall: { top, blocks } (a block per line of text,
--- one per picture, the tags and place last) and what drawing needs (its
--- text, line height, pictures). Kept until its text, pictures or size change.
--- Pictures not on the Kindle yet are left out (`missing`: the board fetches
--- those of the notes it shows, then measures them again).
function Notes.measure(m, note_w, page_h)
    local pad = S(PAD)
    local inner_w = note_w - 2 * pad - 2 * Size.border.thin
    local pic_max_h = math.max(S(40), math.floor(page_h * Notes.PIC_MAX))
    local pics, sig, missing = {}, {}, {}
    for _i, a in ipairs(Notes.pictureAttachments(m)) do
        local path = Memos.filePath(a)
        local w, h
        if lfs.attributes(path, "mode") == "file" then
            w, h = Notes.picSize(path)
        else
            missing[#missing + 1] = a
        end
        if w then
            local p = Notes.fitPicture(a, w, h, inner_w, pic_max_h)
            p.path = path
            w, h = p.w, p.h
            pics[#pics + 1] = p
        end
        sig[#sig + 1] = w and (w .. "x" .. h) or "-"
    end
    sig = table.concat(sig, ",") .. "|" .. tostring(m.place) .. "|" .. #(m.attachments or {}) .. "|" .. note_w .. "|" .. page_h
    local c = Notes.measured[m]
    if c and c.content == m.content and c.sig == sig then c.missing = missing; return c end
    local text = Sticky.preview(m.content)
    local lines, line_h = 0, 0
    if text:match("%S") then
        -- one line drawn: the rest only split into lines, to count them
        local tb = TextBoxWidget:new{ text = text, face = Sticky.hand(19), width = inner_w, height = 1 }
        lines, line_h = #(tb.vertical_string_list or {}), tb.line_height_px or 0
        tb:free()
    end
    local tag_line, foot_bits = noteFoot(m, inner_w)
    local tail = S(GAP) + (tag_line and tag_line:getSize().h or 0) + (foot_bits and foot_bits:getSize().h or 0)
    if tag_line then tag_line:free() end
    if foot_bits then foot_bits:free() end
    local blocks = {}
    for i = 1, lines do blocks[i] = line_h end
    for _i, p in ipairs(pics) do blocks[#blocks + 1] = S(GAP) + p.h + 2 * Size.border.thin end
    blocks[#blocks + 1] = tail
    local slack = Notes.slack(note_w)
    c = { content = m.content, sig = sig, text = text, lines = lines, line_h = line_h, pics = pics, note_w = note_w, missing = missing,
        blocks = blocks, slack = slack, top = 2 * pad + 2 * Size.border.thin + S(HEAD_H) + S(HEAD_GAP) + slack }
    Notes.measured[m] = c
    return c
end

Notes.fetching = {}

--- What the Notes tab keeps on the Kindle: notes (bytes), attachments (bytes, files).
function Notes.storage()
    local notes = lfs.attributes(Memos.cachePath(), "size") or 0
    local bytes, files = 0, 0
    local dir = Memos.filesDir()
    for name in lfs.dir(dir) do
        if name ~= "." and name ~= ".." then
            local size = lfs.attributes(dir .. "/" .. name, "size")
            if size then bytes, files = bytes + size, files + 1 end
        end
    end
    return notes, bytes, files
end

--- Keep downloaded attachments under Settings → Notes → limit: the ones
--- used longest ago go first (never `keep`, the one just downloaded).
function Notes.pruneFiles(plugin, keep)
    local limit = Notes.prefs(plugin).files_mb * 1024 * 1024
    if limit <= 0 then return 0 end
    local dir = Memos.filesDir()
    local list, total = {}, 0
    for name in lfs.dir(dir) do
        local path = dir .. "/" .. name
        local a = name ~= "." and name ~= ".." and lfs.attributes(path)
        if a and a.mode == "file" then
            list[#list + 1] = { path = path, size = a.size, t = math.max(a.modification or 0, a.access or 0) }
            total = total + a.size
        end
    end
    table.sort(list, function(x, y) return x.t < y.t end)
    local removed = 0
    for _i, f in ipairs(list) do
        if total <= limit then break end
        if f.path ~= keep then
            os.remove(f.path)
            total = total - f.size
            removed = removed + 1
        end
    end
    if removed > 0 then Log.info("notes: removed", removed, "old attachments (limit", Notes.prefs(plugin).files_mb, "MB)") end
    return removed
end

--- While Wi-Fi is up for a sync: download the pictures in the kept notes
--- (small ones, within the attachment limit), so they show offline.
Notes.PREFETCH_MAX = 2 * 1024 * 1024 -- bytes: bigger pictures wait until opened
function Notes.prefetchPictures(plugin)
    local limit = Notes.prefs(plugin).files_mb * 1024 * 1024
    local _, used = Notes.storage()
    local budget = limit > 0 and math.floor(limit * 0.8) - used or math.huge
    local todo = {}
    for _i, m in ipairs(Notes.notes or {}) do
        for _j, a in ipairs(m.attachments or {}) do
            if tostring(a.type):match("^image/") and not a.link and (a.size or 0) <= Notes.PREFETCH_MAX
                    and lfs.attributes(Memos.filePath(a), "mode") ~= "file" and budget - (a.size or 0) > 0 then
                budget = budget - (a.size or 0)
                todo[#todo + 1] = a
            end
        end
    end
    if #todo == 0 then return end
    Log.info("notes: fetching", #todo, "pictures for offline")
    for _i, a in ipairs(todo) do Notes.fetchFile(plugin, a) end
end

--- Download an attachment in the background (only while Wi-Fi is up), then
--- on_done(). Asked again while it's coming (the board asking for a picture
--- the sync's prefetch is already fetching): on_done waits for that download.
function Notes.fetchFile(plugin, att, on_done)
    local path = Memos.filePath(att)
    local waiting = Notes.fetching[path]
    if waiting then
        if on_done then waiting[#waiting + 1] = on_done end
        return
    end
    local ok_net, Net = pcall(require, "gzreader_net")
    if not (ok_net and Net.connected()) then return end
    waiting = { on_done }
    Notes.fetching[path] = waiting
    require("gzreader_async").run(Notes.client(plugin), function(c) return c:download(att, path) end, function(got, err)
        Notes.fetching[path] = nil
        if not got then Log.warn("notes: attachment not downloaded:", tostring(err)) end
        if got then Notes.pruneFiles(plugin, path) end
        if got then for _i, fn in ipairs(waiting) do fn() end end
    end, "notes: attachment")
end

local function boardItems(plugin)
    local items = {}
    for _i, m in ipairs(Notes.sorted(Notes.visible(), plugin)) do
        items[#items + 1] = { memo = m, text = Sticky.preview(m.content) }
    end
    if #items == 0 then
        if Notes.last_error then -- not "no notes": say why they didn't load
            items[1] = { text = T(Touch.text(_("Couldn't load your notes. %1\n\nM → Refresh to try again."),
                _("Couldn't load your notes. %1\n\nConnection → Refresh to try again."),
                _("Couldn't load your notes. %1\n\nMenu → Connection → Refresh to try again.")), describe(Notes.last_error)) }
        elseif Notes.refreshing or not Notes.cached_at then -- (nothing kept from before: first load)
            items[1] = { text = _("Loading your notes…") }
        else
            items[1] = { text = Notes.filter.kind == "all" and Touch.text(_("No notes yet. Press N to write one."),
                _("No notes yet. Tap New note to write one."),
                _("No notes yet. Menu → New note to write one."))
                or Touch.text(_("No notes match. Press F to change the filter."), _("No notes match. Tap Filter to change it."),
                _("No notes match. Menu → Filter to change it.")) }
        end
    end
    return items
end

--- Draw the board's page as sticky notes (replaces Menu:updateItems).
-- Compact: a grid of `cols` columns, every note the same size.
local function drawCompact(m, select_number, cols, max_items)
    local rows = NL.rows(cols, m.available_height, S(NL.ROW_MIN_H), max_items)
    m.items_per_page = cols * rows
    m:_recalculateDimen(false)
    if m._gz_goto then m.page = math.max(1, math.min(m:getPageNumber(m._gz_goto), m.page_num)) end
    local per = m.perpage
    local offset = (m.page - 1) * per
    m._gz_scroll = nil
    Notes.footerShown(m, true)
    local cell_w = math.floor(m.item_dimen.w / cols)
    local cell_h = math.floor(m.available_height / rows)
    local count, port = per, nil
    if Notes.scrolling(m.plugin) then
        -- scrolling: one long page, moved by `m._gz_y` pixels. No page number or
        -- arrows: their room is the notes' too.
        Notes.footerShown(m, false)
        local view_h = m.inner_dimen.h - ((m.title_bar and not m.no_title) and m.title_bar:getHeight() or 0)
        local total = math.ceil(#m.item_table / cols)
        local probe = Notes.scrollLayout(0, view_h, rows, total)
        if m._gz_goto then m._gz_y = math.floor((m._gz_goto - 1) / cols) * probe.cell_h end
        local sl = Notes.scrollLayout(m._gz_y or 0, view_h, rows, total)
        m._gz_y = sl.y
        offset, count, cell_h = sl.first * cols, sl.rows * cols, sl.cell_h
        -- (one page: ZenOS's page indicator, painted from these, stays away too)
        m.page, m.page_num = 1, 1
        m._gz_scroll = { rows = rows, cols = cols, cell_h = cell_h, view_h = view_h, max_y = sl.max_y, shift = sl.shift }
        port = Notes.Viewport:new{ dimen = Geom:new{ w = m.item_dimen.w, h = view_h }, shift = sl.shift,
            VerticalGroup:new{ align = "left" } }
        table.insert(m.item_group, port)
        m._gz_scroll.port = port
    end
    local row, layout_row
    for i = 1, count do
        local e = m.item_table[offset + i]
        if not e then break end
        e.idx = offset + i
        if offset + i == m.itemnumber then select_number = i end
        if (i - 1) % cols == 0 then
            row = HorizontalGroup:new{ align = "top" }
            layout_row = {}
            table.insert(port and port[1] or m.item_group, row)
            table.insert(m.layout, layout_row)
        end
        local key = e.memo and Touch.letter(KEYS[i]) or nil
        if e.memo and KEYS[i] then m._gz_keyed[i] = e end
        local item = StickyItem:new{ entry = e, menu = m, look = Sticky.look(port and (offset + i) or i), show_parent = m.show_parent,
            shortcut = key, dimen = Geom:new{ w = e.memo and cell_w or m.item_dimen.w, h = cell_h } }
        table.insert(row, item)
        table.insert(layout_row, item)
    end
    m._gz_first = offset + 1
    return select_number
end

--- Scrolling: the notes' window. Its rows are painted `shift` pixels up, so
--- the first is cut off at the top and the last at the bottom: what they'd
--- paint over (the buttons above, whatever is under) is put back after.
Notes.Viewport = WidgetContainer:extend{ shift = 0 }

function Notes.Viewport:getSize() return Geom:new{ w = self.dimen.w, h = self.dimen.h } end

function Notes.Viewport:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local inner = self[1]
    local w, h = self.dimen.w, self.dimen.h
    local over = inner:getSize().h - self.shift - h
    local kept = {}
    local function keep(sy, sh)
        sy, sh = math.max(0, sy), math.min(sh, bb:getHeight() - math.max(0, sy))
        if sh <= 0 then return end
        local part = Blitbuffer.new(w, sh, bb:getType())
        part:blitFrom(bb, 0, 0, x, sy, w, sh)
        kept[#kept + 1] = { part, sy, sh }
    end
    if self.shift > 0 then keep(y - self.shift, math.min(self.shift, y)) end
    if over > 0 then keep(y + h, over) end
    inner:paintTo(bb, x, y - self.shift)
    for _i, k in ipairs(kept) do
        bb:blitFrom(k[1], x, k[2], 0, 0, w, k[3])
        k[1]:free()
    end
end

--- The page number and arrows under the notes: there, or (scrolling) away.
function Notes.footerShown(m, shown)
    local pi = m.page_info
    if not pi then return end
    if shown then
        if m._gz_footer then
            for i, w in ipairs(m._gz_footer) do pi[i] = w end
            m._gz_footer = nil
            pi:resetLayout()
        end
    elseif not m._gz_footer then
        m._gz_footer = {}
        for i = #pi, 1, -1 do m._gz_footer[i] = pi[i]; pi[i] = nil end
        pi:resetLayout()
    end
end

-- Full: each note as long as it needs, in `cols` columns (Memos' masonry);
-- pages as gzreader_notelayout.lua lays them out.
local function drawFull(m, select_number, cols, max_items)
    local col_w = math.floor(m.item_dimen.w / cols)
    local note_w = Notes.noteWidth(col_w)
    local page_h = m.available_height
    local sizes = {}
    for i, e in ipairs(m.item_table) do sizes[i] = Notes.measure(e.memo, note_w, page_h) end
    local pages = NL.paginate(sizes, cols, page_h, { max_parts = max_items })
    m._gz_pages = pages
    m.page_num = math.max(1, #pages)
    if m._gz_goto then m.page = NL.pageOf(pages, m._gz_goto) end
    m.page = math.max(1, math.min(m.page or 1, m.page_num))
    local page = pages[m.page] or {}
    local row = HorizontalGroup:new{ align = "top" }
    local columns = {}
    for c = 1, cols do
        -- (a column keeps its width with nothing in it)
        columns[c] = VerticalGroup:new{ align = "left", HorizontalSpan:new{ width = col_w } }
        row[c] = columns[c]
    end
    local letter = {} -- note → its letter on this page (one for all its parts)
    for k, part in ipairs(page) do
        local e = m.item_table[part.note]
        e.idx = part.note
        if part.note == m.itemnumber and not m._gz_selected then select_number = k; m._gz_selected = true end
        if not letter[part.note] then
            letter[part.note] = #m._gz_keyed + 1
            if KEYS[letter[part.note]] then m._gz_keyed[letter[part.note]] = e end
        end
        local size = sizes[part.note]
        local item = StickyItem:new{ entry = e, menu = m, look = Sticky.look(k), show_parent = m.show_parent,
            shortcut = Touch.letter(KEYS[letter[part.note]]), part = part, size = size, dimen = Geom:new{ w = col_w, h = part.h } }
        table.insert(columns[part.col], item)
        table.insert(m.layout, { item }) -- (the 5-way goes from note to note, in order)
        if part.from == 1 then
            for _j, a in ipairs(size.missing or {}) do Notes.fetchFile(m.plugin, a, redrawBoard) end
        end
    end
    m._gz_selected = nil
    table.insert(m.item_group, row)
    m._gz_first = page[1] and page[1].note or 1
    return select_number
end

local function drawBoard(m, select_number)
    -- (opening on a touch Kindle: Menu's own first draw is skipped, the
    -- buttons under the title draw it once they're in: Notes.show)
    if m._gz_hold_draw then return end
    m._gz_drawn = true
    Notes.image_gen = Notes.image_gen + 1
    local old_dimen = m.dimen and m.dimen:copy()
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    local view = Notes.view(m.plugin)
    local cols = NL.columns(view.columns, m.inner_dimen.w, S(NL.AUTO_MIN_W))
    local max_items = Touch.keys() and #KEYS or nil -- (a letter for every note)
    m._gz_pages, m._gz_keyed = nil, {}
    local page = m.page
    m:_recalculateDimen(false) -- (the room for the notes)
    if view.display == "full" and m.item_table[1] and m.item_table[1].memo then
        m.page = page -- (Menu counted pages of equal notes: drawFull counts them itself)
        select_number = drawFull(m, select_number, cols, max_items)
    else
        select_number = drawCompact(m, select_number, cols, max_items)
    end
    m._gz_goto = nil
    m:updatePageInfo(select_number) -- (5-way: the focused note's image, kept too)
    m:mergeTitleBarIntoLayout()
    Notes.dropImages()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
end

-- The board: a Menu (ZenOS puts its tab bar under it) whose page is drawn as
-- sticky notes. Q, W, E… open notes; N new note; F filter; L layout.
Notes.Board = Menu:extend{}

function Notes.Board:updateItems(select_number) return drawBoard(self, select_number) end

--- The page a note is on (Full: pages hold as many notes as fit).
function Notes.Board:getPageNumber(item_number)
    if self._gz_pages then return NL.pageOf(self._gz_pages, item_number) end
    return Menu.getPageNumber(self, item_number)
end

--- Scrolling (Notes.scrolling): `dy` pixels down (up: negative). True when it moved.
function Notes.Board:scrollBy(dy)
    local sc = self._gz_scroll
    if not sc then return false end
    local to = math.max(0, math.min(sc.max_y, (self._gz_y or 0) + math.floor(dy + 0.5)))
    if to == (self._gz_y or 0) then return false end
    self._gz_y = to
    self:updateItems()
    return true
end

--- Scrolling: did this gesture start on the notes? One that starts above
--- them (the top of the screen, the buttons) isn't the notes': a swipe down
--- from the top still opens the quick panel.
function Notes.Board:onNotes(ges)
    local sc = self._gz_scroll
    local top = sc and sc.port and sc.port.dimen and sc.port.dimen.y
    local y = ges and ges.pos and ges.pos.y
    return not (top and y) or y >= top
end

--- Scrolling: a swipe up or down moves the notes as far as the finger went;
--- a swipe sideways, most of a screenful (a row stays in view).
function Notes.Board:onSwipe(arg, ges)
    local sc = self._gz_scroll
    if sc and ges and not self:onNotes(ges) then return false end -- (the quick panel's, the tab bar's)
    if sc and ges then
        local d = ges.direction
        -- (a drag that ended as a swipe: from where the notes were when it began, not from where they followed to)
        local pan = self._gz_pan
        self._gz_pan = nil
        if pan and (pan.y0 ~= (self._gz_y or 0) or pan.rough) then self._gz_y = pan.y0; self._gz_moved = true end
        if self._gz_moved and not (d == "north" or d == "south" or d == "west" or d == "east") then
            self._gz_moved = nil
            self:updateItems()
            return true
        end
        if d == "north" or d == "south" then
            if not self:scrollBy((d == "north" and 1 or -1) * (tonumber(ges.distance) or 0)) and self._gz_moved then self:updateItems() end
            self._gz_moved = nil
            return true
        elseif d == "west" or d == "east" then
            if not self:scrollBy((d == "west" and 1 or -1) * (sc.view_h - sc.cell_h)) and self._gz_moved then self:updateItems() end
            self._gz_moved = nil
            return true
        end
    end
    return Menu.onSwipe(self, arg, ges)
end

--- Scrolling: to `y` pixels down the notes. True when it moved.
function Notes.Board:scrollTo(y)
    return self:scrollBy(y - (self._gz_y or 0))
end

--- Scrolling: a drag moves the notes with the finger, a step at a time
--- (gzreader_livescroll: an e-ink screen can't follow every sample), and
--- they settle where it lifts.
function Notes.Board:onPan(arg, ges)
    if self._gz_scroll and ges and not ges.mousewheel_direction then
        if not self:onNotes(ges) then self._gz_pan = nil; return false end
        local pan = self._gz_pan
        if not pan then
            pan = { y0 = self._gz_y or 0, live = {} }
            self._gz_pan = pan
        end
        -- (how far the finger is from where it began: down is positive)
        local rel = ges.relative and ges.relative.y
        if not rel then
            rel = (ges.direction == "north" and -1 or ges.direction == "south" and 1 or 0) * (tonumber(ges.distance) or 0)
        end
        pan.rel = rel
        local LiveScroll = require("gzreader_livescroll")
        if LiveScroll.step(pan.live, rel, LiveScroll.now()) ~= 0 then
            -- (a step: shown without the flash of an ordinary refresh; properly when the finger lifts)
            LiveScroll.quiet(function() if self:scrollTo(pan.y0 - rel) then pan.rough = true end end)
        end
        return true
    end
    return Menu.onPan(self, arg, ges)
end

function Notes.Board:onGzPanRelease()
    local pan = self._gz_pan
    self._gz_pan = nil
    if not (pan and self._gz_scroll) then return false end
    if not self:scrollTo(pan.y0 - (pan.rel or 0)) and pan.rough then
        UIManager:setDirty(self.show_parent or self, function() return "ui", self.dimen end)
    end
    return true
end

--- Scrolling: the page keys (if any) move most of a screenful.
function Notes.Board:onGotoPage(page)
    local sc = self._gz_scroll
    if sc then
        self:scrollBy((page > (self.page or 1) and 1 or -1) * (sc.view_h - sc.cell_h))
        return true
    end
    return Menu.onGotoPage(self, page)
end

function Notes.Board:onMenuSelect(item)
    if item.memo then Notes.showNote(self.plugin, item.memo) end
    return true
end

function Notes.Board:onSelectByShortCut(arg, keyevent)
    local k = keyevent and keyevent.key
    if k == "N" then Notes.edit(self.plugin); return true end
    if k == "J" then Notes.journal(self.plugin); return true end
    -- (Z X C V B switch the bottom tabs: not those)
    if k == "K" then Notes.showSearch(self.plugin); return true end
    if k == "H" then Notes.showMenu(self.plugin); return true end
    if k == "G" then Notes.showTags(self.plugin); return true end
    if k == "D" then Notes.toggleDrawings(self.plugin); return true end
    if k == "A" then Notes.setFilter(self.plugin, { kind = "all" }); return true end
    if k == "F" then Notes.showFilter(self.plugin); return true end
    if k == "M" then Notes.showConnection(self.plugin); return true end
    if k == "L" then Notes.showView(self.plugin); return true end
    if k == "S" then Notes.showSort(self.plugin); return true end
    for i, key in ipairs(KEYS) do
        if key == k then -- the note with that letter on this page
            local e = self._gz_keyed and self._gz_keyed[i]
            if e and e.memo then self:onMenuSelect(e) end
            return true
        end
    end
    return Menu.onSelectByShortCut(self, arg, keyevent)
end

function Notes.title()
    local label = Notes.filterLabel()
    return label == _("All notes") and _("Notes") or (_("Notes") .. " \u{00B7} " .. label)
end

--- Redraw the board with the current notes and filter.
function Notes.reloadBoard(keep_page)
    local b = Notes.board
    if not b or b._gz_closed then return end
    if not keep_page then b._gz_y = 0 end -- (scrolling: other notes, from the top)
    b:switchItemTable(Notes.title(), boardItems(b.plugin), keep_page and -1 or nil)
    pcall(Notes.decorate, b)
    -- touch: the tag chips show the filter in use and your most used tags
    local sig = Notes.homeSignature(b.plugin)
    if Touch.on() and b._gz_home_sig ~= sig then
        b._gz_home_sig = sig
        Touch.actionRow(b, Notes.actions(b.plugin), Notes.homeRows(b.plugin), true)
    end
end

--- ZenOS's status row (clock, battery, Wi-Fi) in the title, like other tabs.
function Notes.decorate(menu, label)
    return require("gzreader_tabs").decorate(menu, label or Notes.title())
end

--- (kept for callers from 1.5.2) see gzreader_tabs
function Notes.closeOtherTabs(keep_id) return require("gzreader_tabs").closeOthers(keep_id) end

Notes.ICON_DIR = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or ".") .. "/icons/panel/"

--- Touch Kindles: the buttons under the Notes tab's title, one row: Note (a
--- new note), Draw (a new note that opens on a page to draw on) and Journal
--- (a journal entry), each with its picture; then icons for Sort, Filter,
--- Layout, Search and Full screen (an X while in it). Under them
--- (Notes.homeRows): what's shown: All, your tags, Drawings. Connection is
--- in Filter.
function Notes.actions(plugin)
    local full = Notes.fullscreen(plugin)
    local function icon(name) return Notes.ICON_DIR .. name .. ".svg" end
    return {
        { _("Note"), function() Notes.edit(plugin) end, icon_file = icon("quicknote") },
        { _("Draw"), function() Notes.draw(plugin) end, icon_file = Notes.ICON_DIR .. "../draw/pen.svg" },
        { _("Journal"), function() Notes.journal(plugin) end, icon_file = icon("journal") },
        { icon_file = icon("sort"), label = _("Sort"), callback = function() Notes.showSort(plugin) end },
        { icon_file = icon("filter"), label = _("Filter"), callback = function() Notes.showFilter(plugin) end },
        { icon_file = icon("layout"), label = _("Layout"), callback = function() Notes.showView(plugin) end },
        { icon_file = icon("search"), label = _("Search"), callback = function() Notes.showSearch(plugin) end },
        { icon_file = icon(full and "close" or "fullscreen"),
          label = full and _("Leave full screen") or _("Full screen"),
          callback = function() Notes.setFullscreen(plugin, not Notes.fullscreen(plugin)) end },
    }
end

Notes.HOME_TAGS = 3 -- tags with a chip of their own (the most used; the rest: Filter → Tag)

--- The tags with a chip on the Notes tab: the one being shown, then your most used.
function Notes.homeTags(plugin)
    local out, seen = {}, {}
    local f = Notes.filter
    if f.kind == "tag" then out[1] = f.value; seen[f.value] = true end
    -- (not a journal entry's mood and activity tags: every entry has them)
    local Journal = require("gzreader_journal")
    local js = Notes.journalSettings(plugin)
    local skip = {}
    for _i, k in ipairs({ "moodTagPrefix", "feelingTagPrefix", "impactTagPrefix", "activityTagPrefix" }) do
        local pre = Journal.normalizePrefix(js[k])
        if pre ~= "" then skip[#skip + 1] = pre end
    end
    for _i, t in ipairs(Notes.allTags(plugin)) do
        if #out >= Notes.HOME_TAGS then break end
        local journal = false
        for _j, pre in ipairs(skip) do if t.tag:sub(1, #pre) == pre then journal = true end end
        if not seen[t.tag] and not journal then out[#out + 1] = t.tag; seen[t.tag] = true end
    end
    return out
end

--- Touch Kindles, under Notes.actions: a row to choose what's shown: All,
--- your most used tags, Drawings.
function Notes.homeRows(plugin)
    local f = Notes.filter
    local tags = { { _("All"), function() Notes.setFilter(plugin, { kind = "all" }) end, chosen = f.kind == "all" } }
    for _i, tag in ipairs(Notes.homeTags(plugin)) do
        local short = #tag > 12 and (tag:sub(1, 11):gsub("[\128-\191]*$", "") .. "\u{2026}") or tag
        tags[#tags + 1] = { "#" .. short, function() Notes.setFilter(plugin, { kind = "tag", value = tag }) end,
            chosen = f.kind == "tag" and f.value == tag }
    end
    tags[#tags + 1] = { _("Drawings"), function() Notes.toggleDrawings(plugin) end, chosen = f.kind == "drawings" }
    return { tags }
end

--- What the tag chips show (they're put in again only when this changes).
function Notes.homeSignature(plugin)
    local f = Notes.filter
    return table.concat(Notes.homeTags(plugin), ",") .. "|" .. tostring(f.kind) .. "|" .. tostring(f.value)
end

--- Drawings (a chip; D): only the notes with a sheet, or back to all of them.
function Notes.toggleDrawings(plugin)
    return Notes.setFilter(plugin, { kind = Notes.filter.kind == "drawings" and "all" or "drawings" })
end

--- Keep the board's note images while the tab is closed (not on a Kindle
--- with 128 MB: the 2 and DX; the same line as laying books out ahead).
function Notes.keepImages()
    local ok, possible = pcall(function() return require("gzreader_layout").possible() end)
    return ok and possible == true
end

-- Keyboard Kindles: the keys under the Notes tab's title (H lists them all).
Notes.KEY_HINT = _("N note  \u{00B7}  J journal  \u{00B7}  K search  \u{00B7}  G tags  \u{00B7}  H all keys")

--- The Notes tab (the tab bar's Notes button).
function Notes.show(plugin)
    Notes.closeOtherTabs(Notes.TAB_ID)
    if Notes.board and not Notes.board._gz_closed then
        Notes.reloadBoard(true)
        return Notes.board
    end
    if not Notes.client(plugin):isConnected() then return Notes.showConnect(plugin) end
    if not Notes.notes then Notes.loadCache(plugin) end
    local menu = Notes.Board:new{
        title = Notes.title(),
        -- (touch: buttons in their place, Notes.actions)
        subtitle = Touch.text(Notes.KEY_HINT, Notes.KEY_HINT,
            _("Menu: new note, journal, search, filter, layout  \u{00B7}  Press opens a note")),
        item_table = boardItems(plugin),
        covers_fullscreen = true, is_borderless = true, is_popout = false, title_bar_fm_style = true,
        -- Layout → Full screen: a name, so ZenOS doesn't make room for the tab
        -- bar, and the tab's id only once it's made (ZenOS adds the bar a moment
        -- later to a view that says which tab it is)
        name = Notes.fullscreen(plugin) and Notes.FULLSCREEN_NAME or nil,
        _gz_navbar_tab_id = not Notes.fullscreen(plugin) and Notes.TAB_ID or nil,
        plugin = plugin,
        -- touch Kindles: the board is drawn once its buttons are in (they
        -- make the title taller: a first draw before them was thrown away)
        _gz_hold_draw = Touch.on() or nil,
    }
    menu._gz_navbar_tab_id = Notes.TAB_ID -- (GZreader's own tabs close each other by it)
    if Touch.on() then -- (scrolling: a drag ends)
        menu.ges_events.GzPanRelease = { GestureRange:new{ ges = "pan_release", range = function() return menu.dimen end } }
    end
    menu.key_events.LeftButtonTap = nil -- (KOReader's Menu also maps the Menu key)
    if Touch.dpad() then
        -- Kindle 4: no letter keys and no buttons; Menu opens what they'd do
        -- (keyboard Kindles: H lists every key; Menu is the quick panel there)
        menu.key_events.GzMenu = { { "Menu" } }
        menu.onGzMenu = function() Notes.showMenu(plugin); return true end
        -- (under the tab bar, ZenOS takes the Menu key first and asks the tab for its
        -- options this way; without it Menu opened the quick panel and the Kindle 4
        -- had no way to a new note)
        menu.onGzOptions = menu.onGzMenu
    end
    -- Alt + Q, W, E, R, T… (the Kindle Keyboard's 1-9) switch the bottom tabs, as in the Grimmory tab
    local digits = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }
    local row = { "Q", "W", "E", "R", "T", "Y", "U", "I", "O" }
    menu.key_events.GzTabKey = { { digits }, { "Alt", digits }, { "Alt", row } }
    menu.onGzTabKey = function(m, _args, key)
        UIManager:close(m)
        UIManager:nextTick(function()
            local FileManager = require("apps/filemanager/filemanager")
            local fc = FileManager.instance and FileManager.instance.file_chooser
            if fc and fc.onKeyPress then fc:onKeyPress(key) end
        end)
        return true
    end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        m._gz_closed = true
        if Notes.board == m then Notes.board = nil end
        if not Notes.keepImages() then Notes.dropImages(true) end
        if orig_close then return orig_close(m, ...) end
    end
    Notes.board = menu
    pcall(Notes.decorate, menu)
    menu._gz_hold_draw = nil
    menu._gz_home_sig = Notes.homeSignature(plugin)
    Touch.actionRow(menu, Notes.actions(plugin), Notes.homeRows(plugin))
    if not menu._gz_drawn then menu:updateItems(1) end
    UIManager:show(menu)
    Notes.syncOnOpen(plugin)
    return menu
end

---------------------------------------------------------------- one note

--- A note's own page reads in the note editor's font (KOReader's, as
--- gzreader_richedit.lua's RichEdit.face: the same sizes), so a note looks
--- the same opened as written; the Notes tab's sticky notes keep the
--- handwriting font (the owner, 2026-11-16).
Notes.PAGE_TEXT = 20
Notes.PAGE_HEADING = { 28, 24, 22, 21, 20, 20 }
function Notes.pageFace(size, bold)
    return Font:getFace(bold and "NotoSans-Bold.ttf" or "cfont", size) or Font:getFace("cfont", size)
end

local NoteView = InputContainer:extend{ covers_fullscreen = true, memo = nil, plugin = nil, focus = nil }

function NoteView:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.key_events = {
        Close = { { Device.input and Device.input.group and Device.input.group.Back or "Back" } },
        Pick = { { KEYS } },
        -- Alt + E / P: the Kindle Keyboard's kernel may send these as 3 / 0
        Edit = { { "Alt", "E" }, { "Alt", "3" }, { "3" } },
        Pin = { { "Alt", "P" }, { "Alt", "0" }, { "0" } },
        Options = { { "M" }, { "Menu" } },
        PageDown = { { { "RPgFwd", "LPgFwd" } } },
        PageUp = { { { "RPgBack", "LPgBack" } } },
        -- the 5-way: choose a checklist item or attachment, Press ticks / opens it
        FocusUp = { { "Up" } },
        FocusDown = { { "Down" } },
        PickFocused = { { "Press" } },
    }
    self:build()
end

function NoteView:moveFocus(dir)
    local n = #(self.picks or {})
    if n == 0 then return dir > 0 and self:onPageDown() or self:onPageUp() end
    self.focus = math.max(1, math.min(n, (self.focus or (dir > 0 and 0 or n + 1)) + dir))
    self:refresh()
    return true
end

function NoteView:onFocusUp() return self:moveFocus(-1) end
function NoteView:onFocusDown() return self:moveFocus(1) end
function NoteView:onPickFocused()
    if self.focus and self.picks and self.picks[self.focus] then return self:pickIndex(self.focus) end
    return true
end

function NoteView:build()
    local sw, sh = self.dimen.w, self.dimen.h
    local m = self.memo
    local margin = S(24)
    local inner = sw - 2 * margin
    local g = VerticalGroup:new{ align = "left" }
    local function add(w) g[#g + 1] = w end
    local function iconLine(icon, text, face, bold, color)
        return HorizontalGroup:new{ align = "center",
            TextWidget:new{ text = Sticky.ICONS[icon] .. " ", face = Sticky.iconFace(15), fgcolor = color },
            TextWidget:new{ text = text, face = face, bold = bold, fgcolor = color, max_width = inner - S(30) } }
    end
    self.picks = {}
    add(VerticalSpan:new{ width = S(14) })
    local space = Notes.spaceTitle(self.plugin, m.space)
    add(iconLine("date", Sticky.when(m.created) .. (space and ("   \u{00B7}   " .. T(_("in %1"), space)) or "")
        .. (m.pinned and ("   \u{00B7}   " .. _("pinned")) or "")
        .. (m.pending and ("   \u{00B7}   " .. _("not sent yet")) or ""), Font:getFace("cfont", 15), false, Blitbuffer.COLOR_DARK_GRAY))
    add(VerticalSpan:new{ width = S(10) })
    local para = {}
    local function flush()
        local t = table.concat(para, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
        para = {}
        if t ~= "" then add(TextBoxWidget:new{ text = t, face = Notes.pageFace(Notes.PAGE_TEXT), width = inner }) end
    end
    local n_check = 0
    for _i, l in ipairs(Sticky.lines(m.content)) do
        if l.kind == "check" then
            flush()
            n_check = n_check + 1
            local key = Touch.letter(KEYS[#self.picks + 1])
            self.picks[#self.picks + 1] = { check = n_check }
            local focused = self.focus == #self.picks
            local sc = key and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, key, "square")
            add(self:tappable(#self.picks, FrameContainer:new{ padding = S(3), margin = 0, bordersize = focused and Size.border.thick or 0, width = inner,
                HorizontalGroup:new{ align = "center", sc or HorizontalSpan:new{ width = Touch.keys() and S(26) or 0 }, HorizontalSpan:new{ width = Touch.keys() and S(10) or 0 },
                    TextWidget:new{ text = l.done and "\u{2611}" or "\u{2610}", face = Font:getFace("cfont", 26) },
                    HorizontalSpan:new{ width = S(8) },
                    TextWidget:new{ text = Sticky.plain(l.text), face = Notes.pageFace(Notes.PAGE_TEXT), max_width = inner - S(90),
                        fgcolor = l.done and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK } } }))
        elseif l.kind == "heading" then
            flush()
            add(VerticalSpan:new{ width = S(6) })
            add(TextBoxWidget:new{ text = Sticky.plain(l.text), face = Notes.pageFace(Notes.PAGE_HEADING[l.level] or Notes.PAGE_TEXT, true),
                width = inner })
        elseif l.kind == "image" then
            flush()
            local pic = Notes.pictureFor(self.plugin, m, l.src, inner, math.floor(sh * 0.45), function()
                if not self.closed then self:build(); UIManager:setDirty(self, "ui") end
            end)
            if pic then add(VerticalSpan:new{ width = S(6) }); add(pic); add(VerticalSpan:new{ width = S(6) }) end
        elseif not Sticky.tagsOnly(l.text) then -- (tags have their own row below)
            para[#para + 1] = Sticky.plain(l.text)
        end
    end
    flush()
    -- the note's drawings, after its text, as wide as the page (a tap opens one)
    local shown = {}
    local sheets = Notes.drawings(m)
    for i, a in ipairs(sheets) do
        shown[a] = true
        local pic = Notes.drawingWidget(self.plugin, a, inner, math.floor(sh * 0.55), function()
            if not self.closed then self:build(); UIManager:setDirty(self, "ui") end
        end)
        add(VerticalSpan:new{ width = S(8) })
        if #sheets > 1 then
            -- several sheets: which page each is (every Kindle shows them all; only touch Kindles draw)
            local key = pic and Touch.letter(KEYS[#self.picks + 1])
            add(TextWidget:new{ text = Notes.pageCaption(i, #sheets, key), face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY })
            add(VerticalSpan:new{ width = S(4) })
        end
        if pic then
            self.picks[#self.picks + 1] = { att = a }
            local focused = self.focus == #self.picks
            add(self:tappable(#self.picks, FrameContainer:new{ padding = 0, margin = 0,
                bordersize = focused and Size.border.thick or 0, pic }))
        else
            add(TextWidget:new{ text = _("(drawing: downloading…)"), face = Font:getFace("cfont", 15), fgcolor = Blitbuffer.COLOR_DARK_GRAY })
        end
    end
    add(VerticalSpan:new{ width = S(12) })
    if #(m.tags or {}) > 0 then
        local tags = {}
        for _i, t in ipairs(m.tags) do tags[#tags + 1] = "#" .. t end
        add(iconLine("tag", table.concat(tags, "  "), Notes.pageFace(18, true), false))
    end
    if m.place then
        add(VerticalSpan:new{ width = S(4) })
        add(iconLine("place", m.place, Font:getFace("cfont", 17)))
    end
    local listed = {}
    for _i, a in ipairs(m.attachments or {}) do if not shown[a] then listed[#listed + 1] = a end end
    if #listed > 0 then
        add(VerticalSpan:new{ width = S(14) })
        add(TextWidget:new{ text = _("Attachments"), face = Font:getFace("smalltfont", 17), bold = true })
        add(VerticalSpan:new{ width = S(6) })
        for _i, a in ipairs(listed) do
            local key = Touch.letter(KEYS[#self.picks + 1])
            self.picks[#self.picks + 1] = { att = a }
            local focused = self.focus == #self.picks
            local sc = key and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, key, "square")
            local here = lfs.attributes(Memos.filePath(a), "mode") == "file"
            local size = a.size and (a.size >= 1048576 and string.format("%.1f MB", a.size / 1048576)
                or string.format("%d KB", math.max(1, math.floor(a.size / 1024)))) or ""
            add(self:tappable(#self.picks, FrameContainer:new{ padding = S(8), bordersize = focused and Size.border.thick or Size.border.thin,
                radius = S(4), width = inner,
                HorizontalGroup:new{ align = "center", sc or HorizontalSpan:new{ width = Touch.keys() and S(26) or 0 }, HorizontalSpan:new{ width = Touch.keys() and S(10) or 0 },
                    TextWidget:new{ text = (tostring(a.type):match("^image/") and Sticky.ICONS.image or Sticky.ICONS.pdf) .. "  ",
                        face = Sticky.iconFace(18) },
                    TextWidget:new{ text = a.filename or "?", face = Font:getFace("cfont", 18), max_width = inner - S(170) },
                    HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = size .. (here and "" or (" \u{00B7} " .. _("download"))), face = Font:getFace("cfont", 14),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY } } }))
        end
    end
    local hint = (#self.picks > 0 and (KEYS[1] .. (#self.picks > 1 and ("\u{2013}" .. KEYS[math.min(#self.picks, #KEYS)]) or "") .. "  "
        .. (n_check > 0 and _("tick / open") or _("open")) .. "     ") or "")
        .. _("Alt+E edit     Alt+P pin     M more     Back board")
    local title_h, footer_h = S(46), S(34)
    local footer
    if not Touch.on() then
        if not Touch.keys() then -- (Kindle 4: the 5-way and Menu)
            hint = (#self.picks > 0 and ("\u{25B2} \u{25BC} " .. _("choose") .. "   Press " .. (n_check > 0 and _("tick / open") or _("open")) .. "     ") or "")
                .. _("Menu: edit, pin     Back: board")
        end
        footer = CenterContainer:new{ dimen = Geom:new{ w = sw, h = footer_h },
            TextWidget:new{ text = hint, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = sw - S(20) } }
    else
        -- touch: buttons; ticking an item or opening an attachment is a tap on it
        local chips = Touch.chips(math.floor(sw * 0.94), {
            { _("Edit"), function() self:onEdit() end },
            { m.pinned and _("Unpin") or _("Pin"), function() self:onPin() end },
            { _("More"), function() self:onOptions() end },
            { _("Close"), function() self:onClose() end },
        }, self)
        footer_h = chips:getSize().h + S(24)
        footer = CenterContainer:new{ dimen = Geom:new{ w = sw, h = footer_h }, chips }
    end
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local content_h = sh - title_h - footer_h
    self.scroller = ScrollableContainer:new{
        dimen = Geom:new{ w = sw, h = content_h }, show_parent = self,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, g },
    }
    require("gzreader_livescroll").on(self.scroller) -- (the note moves with the finger)
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
                TextWidget:new{ text = _("Note"), face = Font:getFace("smalltfont", 22), bold = true } },
            self.scroller,
            footer,
        },
    }
end

--- A checklist item or attachment row that a tap picks (as its letter key does).
function NoteView:tappable(idx, widget)
    if not Touch.on() then return widget end
    local view = self
    local box = InputContainer:new{ dimen = Geom:new{ w = widget:getSize().w, h = widget:getSize().h }, widget }
    box.ges_events = { TapPick = { GestureRange:new{ ges = "tap", range = function() return box.dimen end } } }
    function box:onTapPick() return view:pickIndex(idx) end
    return box
end

function NoteView:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

--- The screen turned (auto-rotate, gzreader_rotation.lua): the note laid out again at the new size.
require("gzreader_rotation").follow(NoteView, function(v)
    v.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    v:build()
end)

function NoteView:onPageDown()
    if self.scroller and self.scroller._scrollBy then self.scroller:_scrollBy(0, math.floor(self.scroller.dimen.h * 0.8)) end
    UIManager:setDirty(self, "ui")
    return true
end

function NoteView:onPageUp()
    if self.scroller and self.scroller._scrollBy then self.scroller:_scrollBy(0, -math.floor(self.scroller.dimen.h * 0.8)) end
    UIManager:setDirty(self, "ui")
    return true
end

function NoteView:onPick(_arg, key)
    local idx
    for i, k in ipairs(KEYS) do if key and key.key == k then idx = i end end
    return self:pickIndex(idx)
end

function NoteView:pickIndex(idx)
    local pick = idx and self.picks[idx]
    if not pick then return true end
    if pick.check then
        self.memo.content = Sticky.toggle(self.memo.content, pick.check)
        self.focus = idx
        Notes.saveContent(self.plugin, self.memo)
        self:refresh()
    elseif pick.att then
        Notes.tapAttachment(self.plugin, self.memo, pick.att)
    end
    return true
end

function NoteView:onEdit() Notes.edit(self.plugin, self.memo); return true end

function NoteView:onPin()
    local m = self.memo
    if not m.name then info(_("This note isn't in Memos yet; pin it once it's sent."), 3); return true end
    m.pinned = not m.pinned
    Notes.enqueue(self.plugin, { op = "pin", name = m.name, pinned = m.pinned })
    Notes.sendSoon(self.plugin)
    self:refresh()
    return true
end

function NoteView:onOptions()
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    dialog = Notes.keyedDialog(_("Note"), {
        { { text = _("Edit"), align = "left", callback = run(function() self:onEdit() end) } },
        { { text = self.memo.pinned and _("Unpin") or _("Pin"), align = "left", callback = run(function() self:onPin() end) } },
        { { text = _("Back to the board"), align = "left", callback = run(function() self:onClose() end) } },
    })
    return true
end

function NoteView:onClose()
    self.closed = true
    UIManager:close(self, "full")
    Notes.reloadBoard(true)
    return true
end

function Notes.showNote(plugin, memo)
    -- A note that is only a drawing (its name and tags, no words of its own) opens on
    -- its drawing, as a new one does: Done saves and comes back here (the owner, 2026-11-16).
    if memo and Notes.canDraw(plugin) and Notes.drawings(memo)[1] ~= nil
        and require("gzreader_newdrawing").parse(memo.content) ~= nil then
        Log.info("notes: a drawing note opened on its drawing")
        return Notes.edit(plugin, memo, { drawing_note = true })
    end
    local v = NoteView:new{ memo = memo, plugin = plugin }
    UIManager:show(v, "full")
    return v
end

--- A picture in a note (src from its Markdown): an ImageWidget, or nil while
--- it's being fetched (on_ready() runs when it's here).
function Notes.pictureFor(plugin, m, src, max_w, max_h, on_ready)
    local uid = tostring(src):match("/file/attachments/([^/%?]+)")
    local att
    for _i, a in ipairs(m.attachments or {}) do
        if uid and tostring(a.name):match("attachments/(.+)$") == uid then att = a end
    end
    if not att and uid then att = { name = "attachments/" .. uid, filename = tostring(src):match("/file/attachments/[^/]+/([^%?]+)") or "image" } end
    if not att then return nil end -- a picture from elsewhere on the web: not fetched
    local path = Memos.filePath(att)
    if lfs.attributes(path, "mode") ~= "file" then
        Notes.fetchFile(plugin, att, on_ready)
        return TextWidget:new{ text = _("(picture: downloading…)"), face = Font:getFace("cfont", 15), fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    end
    local bb = Sticky.picture(path, max_w, max_h)
    if not bb then return nil end
    return FrameContainer:new{ padding = 0, bordersize = Size.border.thin, ImageWidget:new{ image = bb, image_disposable = true } }
end

--- `att`'s file on the Kindle: downloaded first when it isn't here yet
--- (Wi‑Fi), then `fn(path)`. Kept on the Kindle afterwards.
function Notes.withAttachment(plugin, att, fn)
    local path = Memos.filePath(att)
    if lfs.attributes(path, "mode") == "file" then
        pcall(lfs.touch, path) -- used now: kept longest when space runs short
        return fn(path)
    end
    local busy = InfoMessage:new{ text = T(_("Downloading %1…"), att.filename or ""), timeout = 0 }
    UIManager:show(busy)
    require("gzreader_net").run(function()
        require("gzreader_async").run(Notes.client(plugin), function(c) return c:download(att, path) end, function(got, err)
            UIManager:close(busy)
            if got then Notes.pruneFiles(plugin, path); fn(path) else info(describe(err)) end
        end, "notes: attachment")
    end, { reason = "a note's attachment" })
end

--- Open an attachment: PDFs and other documents in the reader, pictures in
--- the image viewer. Downloaded once and kept on the Kindle.
function Notes.openAttachment(plugin, att)
    if att.link then return info(T(_("This attachment is a link:\n%1"), att.link)) end
    return Notes.withAttachment(plugin, att, function(path)
        if tostring(att.type):match("^image/") then
            local ImageViewer = require("ui/widget/imageviewer")
            local RenderImage = require("ui/renderimage")
            local bb = RenderImage:renderImageFile(path, false)
            if not bb then return info(_("Couldn't show this picture.")) end
            return UIManager:show(ImageViewer:new{ image = bb, image_disposable = true, with_title_bar = false, fullscreen = true })
        end
        local DocumentRegistry = require("document/documentregistry")
        if not DocumentRegistry:hasProvider(path) then
            return info(T(_("The Kindle can't open %1 files."), (att.filename or ""):match("%.(%w+)$") or att.type or "?"))
        end
        require("apps/reader/readerui"):showReader(path)
    end)
end

--- Mark up a PDF: on touch Kindles that draw (Memos over Wi‑Fi), a note
--- that's in Memos.
function Notes.canMarkUp(plugin, memo, att)
    return memo ~= nil and memo.name ~= nil and not att.link and require("gzreader_pdfmarkup").isPdf(att)
        and Notes.canDraw(plugin)
end

--- A tap on an attachment: a PDF asks Open or Mark up (where it can be
--- marked up); anything else opens.
function Notes.tapAttachment(plugin, memo, att)
    if not Notes.canMarkUp(plugin, memo, att) then return Notes.openAttachment(plugin, att) end
    local dialog
    dialog = require("ui/widget/buttondialog"):new{ title = att.filename or _("PDF"), buttons = {
        { { text = _("Open"), align = "left", callback = function()
            UIManager:close(dialog); Notes.openAttachment(plugin, att)
        end } },
        { { text = _("Mark up pages"), align = "left", callback = function()
            UIManager:close(dialog); Notes.markUpPdf(plugin, memo, att)
        end } },
    } }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

--- Mark up pages: which pages (a PDF of one page: that one), then the
--- drawing screen on them, in the note's editor (Done goes back to the
--- note's text; Save sends the drawings with the note).
function Notes.markUpPdf(plugin, memo, att)
    local PdfMarkup = require("gzreader_pdfmarkup")
    return Notes.withAttachment(plugin, att, function(path)
        local doc, err = PdfMarkup.open(path)
        if not doc then
            Log.warn("notes: PDF not opened for markup:", tostring(err))
            return info(PdfMarkup.message(err), 4)
        end
        local count = doc.count
        doc.close()
        local function go(list)
            local busy = InfoMessage:new{ text = T(_("Preparing %1 page(s)…"), #list), timeout = 0 }
            UIManager:show(busy)
            UIManager:forceRePaint()
            -- (where drawings wait to be sent: the pictures made on the way, removed after)
            local dir = require("datastorage"):getSettingsDir() .. "/gzreader-drawings"
            lfs.mkdir(dir)
            local pages, why, detail = PdfMarkup.pages(path, list, dir)
            UIManager:close(busy)
            if not pages then
                Log.warn("notes: PDF pages not made:", tostring(why), tostring(detail))
                return info(PdfMarkup.message(why), 4)
            end
            Log.info("notes: marking up", #pages, "PDF page(s) of", count)
            return Notes.edit(plugin, memo, { markup_pages = pages })
        end
        if count == 1 then return go({ 1 }) end
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        local function pick()
            local list, why = PdfMarkup.parsePages(dialog:getInputText(), count)
            if not list then
                return info(why == "many" and T(_("At most %1 pages at a time."), PdfMarkup.MAX_PAGES)
                    or why == "empty" and _("Type the pages to mark up.")
                    or T(_("This PDF has pages 1 to %1."), count), 3)
            end
            UIManager:close(dialog)
            go(list)
        end
        dialog = InputDialog:new{
            title = T(_("Pages to mark up (1–%1)"), count),
            description = T(_("For example 2, or 1-3, 7. At most %1."), PdfMarkup.MAX_PAGES),
            input = PdfMarkup.suggest(count),
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Mark up"), is_enter_default = true, callback = pick },
            } },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
        Notes.markup_dialog = dialog
        return dialog
    end)
end

---------------------------------------------------------------- saving

--- Save a note's new text (queued; sent now when possible). `visibility`:
--- only when it changed; `space` too ("spaces/…", or "" for none).
function Notes.saveContent(plugin, memo, visibility, space)
    memo.tags = Notes.tagsIn(memo.content)
    if visibility then memo.visibility = visibility end
    if space then memo.space = space ~= "" and space or nil end
    if memo.name then
        local q = { op = "update", name = memo.name, content = memo.content }
        -- an earlier, unsent change of who can see it, or of its space, stays
        for _i, old in ipairs(plugin.store.memos.queue or {}) do
            if old.op == "update" and old.name == memo.name then
                if old.visibility then q.visibility = old.visibility end
                if old.space then q.space = old.space end
            end
        end
        q.visibility = visibility or q.visibility
        q.space = space or q.space
        -- (Memos moves a note between spaces only with its visibility said too)
        if q.space and not q.visibility then q.visibility = memo.visibility or "PRIVATE" end
        Notes.enqueue(plugin, q)
    elseif memo.local_id then
        -- not in Memos yet: change the queued new note instead
        for _i, q in ipairs(plugin.store.memos.queue or {}) do
            if q.id == memo.local_id then
                q.content = memo.content
                if visibility then q.visibility = visibility end
                if space then q.space = space ~= "" and space or nil end
            end
        end
        plugin:save()
    end
    memo.pending = true
    Notes.sendSoon(plugin)
end

Notes.SYNC_EVERY = 300 -- s: opening the tab syncs at most this often (changes waiting: always)

--- Sync when the tab opens: quietly (Wi-Fi only when needed turns it on and
--- off again after a minute unused), unless it synced in the last 5 minutes
--- and nothing is waiting to be sent. Browsing itself never needs Wi-Fi.
function Notes.syncOnOpen(plugin)
    local queued = #((plugin.store.memos or {}).queue or {})
    if queued == 0 and Notes.last_sync and os.time() - Notes.last_sync < Notes.SYNC_EVERY then return end
    require("gzreader_net").run(function()
        Notes.refresh(plugin, function(_ok, err)
            Notes.reloadBoard(true) -- the notes, or why they didn't load
            if err == "unauthorized" then info(describe(err)) end
        end)
    end, { quiet = true, reason = "notes" })
end

--- Send a change (new note, edit, tick, pin) a moment after it's made:
--- turns Wi-Fi on for it (quietly) when Wi-Fi only when needed is on. Without
--- a connection it waits in the queue for the next sync. With the notes
--- never loaded (a quick note from a book), only the change is sent.
function Notes.sendSoon(plugin)
    if Notes.send_scheduled then return end
    Notes.send_scheduled = true
    UIManager:scheduleIn(2, function()
        Notes.send_scheduled = false
        local send_only = Notes.notes == nil
        require("gzreader_net").run(function()
            Notes.refresh(plugin, function(ok) if ok then Notes.reloadBoard(true) end end, { send_only = send_only })
        end, { quiet = true, reason = "a note changed" })
    end)
end

--- The space a new note starts in: the one the board is showing, if any.
function Notes.newNoteSpace()
    local f = Notes.filter
    return f.kind == "space" and f.value ~= "" and f.value or nil
end

--- New note (memo nil) or edit one: the full-page editor, or with
--- opts.floating a window over the screen (the quick panel's Quick note).
--- opts.on_created(): after a new note was saved (queued).
function Notes.edit(plugin, memo, opts)
    local NoteEditor = require("gzreader_noteeditor")
    local show = opts and opts.floating and NoteEditor.showFloating or NoteEditor.show
    show{
        plugin = plugin,
        memo = memo,
        tags = Notes.allTags(plugin),
        spaces = Notes.spaces(plugin),
        space = (memo == nil) and Notes.newNoteSpace() or nil, -- (an edit: the note's own)
        space_title = function(name) return Notes.spaceTitle(plugin, name) end,
        can_draw = Notes.canDraw(plugin),
        -- an edit of a note with drawings: Edit opens them (Done goes back to the text);
        -- Draw (a new note): a page to draw on at once; Mark up (a PDF): its pages after the note's drawings
        drawing_atts = memo and Notes.drawings(memo) or nil,
        extra_pages = opts and opts.markup_pages or nil,
        open_drawing = ((memo ~= nil and Notes.drawings(memo)[1] ~= nil) or (memo == nil and opts and opts.draw)
            or (opts and opts.markup_pages ~= nil)) and Notes.canDraw(plugin),
        -- Draw (a new note): after Done, the New drawing window (title, tags, Save)
        new_drawing = memo == nil and opts and opts.draw or nil,
        -- a note that's only a drawing, tapped: its drawing screen, named and tagged there; Done saves and closes
        drawing_note = memo ~= nil and opts and opts.drawing_note or nil,
        on_save = function(content, visibility, vis_changed, space, space_changed, drawings)
            if memo then
                memo.content = content
                Notes.saveContent(plugin, memo, vis_changed and visibility or nil, space_changed and (space or "") or nil)
                if drawings then Notes.saveDrawings(plugin, memo, drawings) end
            else
                local list = {}
                for _i, d in ipairs(drawings or {}) do
                    if d.path then list[#list + 1] = { path = d.path, filename = d.filename } end
                end
                local order
                if #list > 1 then
                    order = {}
                    for i, d in ipairs(list) do order[i] = d.filename end
                end
                local q = Notes.enqueue(plugin, { op = "create", content = content, visibility = visibility or "PRIVATE",
                    space = space, drawings = #list > 0 and list or nil, order = order })
                if #list > 0 then
                    Notes.showDrawingNow(q)
                    Log.info("notes: a new note with", #list, "drawing(s) queued")
                end
                -- (notes not loaded yet, e.g. a quick note from a book: the
                -- board loads the kept ones later and shows the queued note then)
                if Notes.notes then
                    table.insert(Notes.notes, 1, { local_id = q.id, content = content, tags = Notes.tagsIn(content),
                        created = os.date("!%Y-%m-%dT%H:%M:%SZ"), attachments = Notes.queuedAttachments(q), pinned = false,
                        pending = true, visibility = q.visibility, space = q.space })
                end
                Notes.sendSoon(plugin)
                if opts and opts.on_created then opts.on_created() end
            end
            Notes.reloadBoard(true)
            for _i, w in ipairs(UIManager._window_stack or {}) do
                if w.widget.memo == memo and w.widget.refresh and memo then w.widget:refresh() end
            end
        end,
    }
end

--- A new note with `content`, queued for Memos and shown on the board at once.
function Notes.addNote(plugin, content, visibility, space)
    local q = Notes.enqueue(plugin, { op = "create", content = content, visibility = visibility or "PRIVATE", space = space })
    if Notes.notes then
        table.insert(Notes.notes, 1, { local_id = q.id, content = content, tags = Notes.tagsIn(content),
            created = os.date("!%Y-%m-%dT%H:%M:%SZ"), attachments = {}, pinned = false,
            pending = true, visibility = q.visibility, space = q.space })
    end
    Notes.sendSoon(plugin)
    Notes.reloadBoard(true)
    return q
end

--- Your journal settings: the ones the last sync brought from a Memos with
--- journaling mode, or the defaults (stock Memos: entries are ordinary notes
--- with tags there too).
function Notes.journalSettings(plugin)
    local Journal = require("gzreader_journal")
    return Journal.settings(plugin.store.memos and plugin.store.memos.journal)
end

--- The space journal entries go to: the one set in Memos' journal settings,
--- when it's still one of yours.
function Notes.journalSpace(plugin)
    local space = Notes.journalSettings(plugin).space
    if space == "" then return nil end
    for _i, sp in ipairs(Notes.spaces(plugin) or {}) do
        if sp.name == space then return space end
    end
    return nil
end

--- Journal (a button; J): a journal entry, as Memos' journaling mode makes
--- them (gzreader_journalscreen.lua): how you felt, what you did, a prompt
--- to write about. Saved as a private note with its mood and activities as
--- tags, in your journal space if you have one.
function Notes.journal(plugin)
    if not Notes.client(plugin):isConnected() then return Notes.showConnect(plugin) end
    return require("gzreader_journalscreen").show{
        settings = Notes.journalSettings(plugin),
        on_save = function(content)
            Notes.addNote(plugin, content, "PRIVATE", Notes.journalSpace(plugin))
            Log.info("notes: a journal entry queued")
            info(require("gzreader_net").usb and _("Journal entry saved. It goes to Memos at the next sync with your computer.")
                or _("Journal entry saved."), 2)
        end,
    }
end

--- The quick panel's Quick note tile: a new note in a window over whatever
--- is on the screen (a book, Home, Settings), which stays visible around it.
--- Save queues it and sends it in the background; closing the editor leaves
--- you where you were.
function Notes.quickNote(plugin)
    if not Notes.client(plugin):isConnected() then return Notes.showConnect(plugin) end
    return Notes.edit(plugin, nil, { floating = true, on_created = function()
        info(require("gzreader_net").usb and _("Note saved. It goes to Memos at the next sync with your computer.")
            or _("Note saved. It goes to Memos as soon as GZreader can reach it."), 3)
    end })
end

---------------------------------------------------------------- filters

--- A dialog of `rows` (a row that's `false` is left out) with letter keys.
function Notes.keyedDialog(title, rows)
    local list = {}
    for _i, row in ipairs(rows) do if row then list[#list + 1] = row end end
    local dialog = ButtonDialog:new{ title = title, buttons = list }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

--- Your tags, most used first: from the notes loaded, or (notes not loaded,
--- e.g. a quick note from a book) from the counts Memos sent at the last sync.
function Notes.countTags(notes)
    local count = {}
    for _i, m in ipairs(notes or {}) do
        for _j, t in ipairs(m.tags or {}) do count[t] = (count[t] or 0) + 1 end
    end
    return count
end

--- Your tags, most used first: { { tag, count } }. From the list kept at the
--- last sync (Memos' own count of every note, or counted from the notes it
--- sent), so it's whole while the board shows one tag's notes and there
--- without a connection; tags of notes not yet sent are added.
function Notes.allTags(plugin)
    local saved = plugin and plugin.store and plugin.store.memos and plugin.store.memos.tag_counts
    local count = {}
    local kept = false
    if type(saved) == "table" then
        for t, n in pairs(saved) do
            if type(t) == "string" then count[t] = tonumber(n) or 0; kept = true end
        end
    end
    if not kept then
        -- (never synced with this version: from the notes there are; all of them unless a filter's answer is shown)
        count = Notes.countTags(Notes.notes)
    else
        for _i, m in ipairs(Notes.notes or {}) do
            if m.pending and m.local_id then
                for _j, t in ipairs(m.tags or {}) do count[t] = (count[t] or 0) + 1 end
            end
        end
    end
    local list = {}
    for t, n in pairs(count) do list[#list + 1] = { tag = t, count = n } end
    table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.tag < b.tag end)
    return list
end

local function allPlaces()
    local count = {}
    for _i, m in ipairs(Notes.notes or {}) do
        if m.place then count[m.place] = (count[m.place] or 0) + 1 end
    end
    local list = {}
    for p, n in pairs(count) do list[#list + 1] = { place = p, count = n } end
    table.sort(list, function(a, b) return a.count > b.count end)
    return list
end

--- Show the notes for a filter (a tag chip, Filter, search). At once from
--- the notes kept on the Kindle, picked out here; then Memos is asked (Wi-Fi
--- turned on for it when it's only on when needed), since it may have older
--- notes than the Kindle keeps. When Memos can't be reached the kept notes
--- stay, without a message: they're what there is.
function Notes.setFilter(plugin, f)
    Notes.filter = f
    Notes.loadCache(plugin)
    Notes.reloadBoard(false)
    local Net = require("gzreader_net")
    if Net.usb or not Notes.client(plugin):isConnected() then return end
    local asked = f
    Net.run(function()
        Notes.refresh(plugin, function(ok, err)
            if Notes.filter ~= asked then return end -- (another filter since: its own answer comes)
            if ok then
                Notes.reloadBoard(false)
            elseif err == "unauthorized" then
                info(describe(err), 3)
            else
                Log.info("notes: filter shown from the kept notes:", tostring(err))
            end
        end)
    end, { quiet = true, reason = "notes filter" })
end

local function count(n) return n == 1 and _("1 note") or T(_("%1 notes"), n) end

local function listPicker(title, entries, on_pick)
    local items = {}
    for _i, e in ipairs(entries) do
        items[#items + 1] = { text = e.text, mandatory = e.mandatory, gz_icon = e.icon, callback = function() on_pick(e) end }
    end
    if #items == 0 then items[1] = { text = _("Nothing here yet."), select_enabled = false } end
    local Rows = require("gzreader_rows")
    Rows.mark(items)
    local menu
    menu = Menu:new{ title = title, item_table = items, covers_fullscreen = true, is_borderless = true, is_popout = false,
        title_bar_fm_style = true, name = "gz_notes_picker", -- (a name: no tab bar)
        onMenuSelect = function(_m, item)
            if item.callback then UIManager:close(menu); item.callback() end
            return true
        end }
    menu.key_events.LeftButtonTap = nil
    menu.key_events.GzClose = { { "Menu" } }
    menu.onGzClose = function() UIManager:close(menu); return true end
    Rows.apply(menu)
    UIManager:show(menu)
    return menu
end

--- Whether to offer spaces (Filter → Space…): your Memos has them, or a
--- note is in one.
function Notes.spacesShown(plugin)
    if Notes.spaces(plugin) then return true end
    for _i, m in ipairs(Notes.notes or {}) do if m.space then return true end end
    return false
end

--- Filter → Space…: No space, then your spaces (with how many notes are in
--- each of those shown now).
function Notes.spaceEntries(plugin)
    local n, none, seen = {}, 0, {}
    for _i, m in ipairs(Notes.notes or {}) do
        if m.space then n[m.space] = (n[m.space] or 0) + 1 else none = none + 1 end
    end
    local entries = { { text = _("No space"), mandatory = none > 0 and count(none) or nil, value = "", icon = "name:document" } }
    local function add(name, title)
        if seen[name] then return end
        seen[name] = true
        entries[#entries + 1] = { text = title, mandatory = n[name] and count(n[name]) or nil, value = name, icon = "name:folder" }
    end
    for _i, sp in ipairs(Notes.spaces(plugin) or {}) do add(sp.name, sp.title) end
    -- (a note in a space not in the list yet)
    for _i, m in ipairs(Notes.notes or {}) do if m.space then add(m.space, Notes.spaceTitle(plugin, m.space)) end end
    return entries
end

function Notes.showSpaceFilter(plugin)
    return listPicker(_("Filter by space"), Notes.spaceEntries(plugin), function(e)
        Notes.setFilter(plugin, { kind = "space", value = e.value, label = e.text })
    end)
end

function Notes.showFilter(plugin)
    local dialog
    local function pick(fn) return function() UIManager:close(dialog); fn() end end
    local cur = Notes.filter.kind
    local function mark(kind, text) return text .. (cur == kind and "  \u{2713}" or "") end
    dialog = Notes.keyedDialog(_("Show notes"), {
        { { text = mark("all", _("All notes")), align = "left", callback = pick(function() Notes.setFilter(plugin, { kind = "all" }) end) } },
        { { text = mark("tag", _("Tag…")), align = "left", callback = pick(function() Notes.showTags(plugin) end) } },
        { { text = mark("date", _("Date…")), align = "left", callback = pick(function()
            local rows = {}
            local d2
            for _i, d in ipairs({ { 1, _("Today") }, { 7, _("Last 7 days") }, { 30, _("Last 30 days") }, { 365, _("Last year") } }) do
                rows[#rows + 1] = { { text = d[2], align = "left", callback = function()
                    UIManager:close(d2); Notes.setFilter(plugin, { kind = "date", value = d[1], label = d[2] })
                end } }
            end
            d2 = Notes.keyedDialog(_("Notes from"), rows)
        end) } },
        { { text = mark("place", _("Place…")), align = "left", callback = pick(function()
            local entries = {}
            for _i, p in ipairs(allPlaces()) do
                entries[#entries + 1] = { text = p.place, mandatory = count(p.count), place = p.place, icon = "name:globe" }
            end
            listPicker(_("Filter by place"), entries, function(e) Notes.setFilter(plugin, { kind = "place", value = e.place }) end)
        end) } },
        Notes.spacesShown(plugin) and { { text = mark("space", _("Space…")), align = "left", callback = pick(function()
            Notes.showSpaceFilter(plugin)
        end) } } or false,
        { { text = mark("attachments", _("With attachments")), align = "left", callback = pick(function()
            Notes.setFilter(plugin, { kind = "attachments" })
        end) } },
        { { text = mark("pinned", _("Pinned")), align = "left", callback = pick(function() Notes.setFilter(plugin, { kind = "pinned" }) end) } },
        { { text = mark("drawings", _("Drawings")), align = "left", callback = pick(function() Notes.setFilter(plugin, { kind = "drawings" }) end) } },
        { { text = mark("search", _("Search text…")), align = "left", callback = pick(function() Notes.showSearch(plugin) end) } },
        -- (touch Kindles: the row of buttons has no room for it; keyboard Kindles: M too)
        { { text = _("Memos connection…"), align = "left", callback = pick(function() Notes.showConnection(plugin) end) } },
    })
end

--- Your tags, most used first: pick one to see its notes (G; Filter → Tag).
function Notes.showTags(plugin)
    local entries = {}
    for _i, t in ipairs(Notes.allTags(plugin)) do
        entries[#entries + 1] = { text = "#" .. t.tag, mandatory = count(t.count), tag = t.tag, icon = "label" }
    end
    if #entries == 0 then return info(_("No tags yet. A #word in a note is a tag."), 3) end
    return listPicker(_("Filter by tag"), entries, function(e) Notes.setFilter(plugin, { kind = "tag", value = e.tag }) end)
end

--- Search (a button; K): the notes with these words.
function Notes.showSearch(plugin)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{ title = _("Search notes"), input = Notes.filter.kind == "search" and Notes.filter.value or "",
        buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local q = d:getInputText()
                UIManager:close(d)
                if q ~= "" then Notes.setFilter(plugin, { kind = "search", value = q })
                elseif Notes.filter.kind == "search" then Notes.setFilter(plugin, { kind = "all" }) end
            end } } } }
    UIManager:show(d)
    d:onShowKeyboard()
    return d
end

--- Everything the touch buttons do, as a list: Menu on the Kindle 4 (it has
--- no letter keys, so this is how it reaches them); H on a keyboard Kindle,
--- where each row names its key. (New sheet only where drawing is
--- possible, a touch screen: other Kindles open notes with drawings, every
--- page, but don't make or change them.)
function Notes.showMenu(plugin)
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    local keys = Touch.keys()
    local function row(text, key, fn)
        return { { text = (keys and key) and (text .. "  (" .. key .. ")") or text, align = "left", callback = run(fn) } }
    end
    dialog = Notes.keyedDialog(_("Notes"), {
        row(_("New note"), "N", function() Notes.edit(plugin) end),
        Notes.canDraw(plugin) and row(_("Draw"), nil, function() Notes.draw(plugin) end) or false,
        row(_("Journal entry"), "J", function() Notes.journal(plugin) end),
        row(_("Search…"), "K", function() Notes.showSearch(plugin) end),
        row(_("Tags…"), "G", function() Notes.showTags(plugin) end),
        row(Notes.filter.kind == "drawings" and _("All notes (not only drawings)") or _("Only notes with drawings"), "D",
            function() Notes.toggleDrawings(plugin) end),
        Notes.filter.kind ~= "all" and row(_("All notes"), "A", function() Notes.setFilter(plugin, { kind = "all" }) end) or false,
        row(_("Filter…"), "F", function() Notes.showFilter(plugin) end),
        row(T(_("Layout: %1"), Notes.viewLabel(Notes.view(plugin))), "L", function() Notes.showView(plugin) end),
        row(_("Sort…"), "S", function() Notes.showSort(plugin) end),
        row(Notes.fullscreen(plugin) and _("Leave full screen") or _("Full screen: no tab bar"), nil,
            function() Notes.setFullscreen(plugin, not Notes.fullscreen(plugin)) end),
        row(_("Connection…"), "M", function() Notes.showConnection(plugin) end),
    })
    return dialog
end

--- Connection (a button on touch Kindles, M on Kindles with keys): Memos
--- only. New note, Filter, Layout, Sort and Full screen have their own
--- buttons and keys.
function Notes.showConnection(plugin)
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    local client = Notes.client(plugin)
    local store = plugin.store.memos
    local queued = #(store.queue or {})
    dialog = Notes.keyedDialog(store.user and T(_("Memos: %1"), store.user) or _("Memos"), {
        { { text = queued > 0 and T(_("Refresh (%1 changes to send)"), queued) or _("Refresh"), align = "left",
            callback = run(function()
                require("gzreader_net").run(function()
                    Notes.refresh(plugin, function(ok, err)
                        if ok then Notes.reloadBoard(true) else info(describe(err)) end
                    end)
                end, { reason = "notes" })
            end) } },
        { { text = _("Connect again"), align = "left", callback = run(function() Notes.showConnect(plugin, true) end) } },
        { { text = _("Disconnect"), align = "left", enabled = client:isConnected(), callback = run(function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = _("Disconnect from Memos?\n\nThe notes kept on this Kindle are removed. Your notes in Memos stay as they are.")
                    .. (queued > 0 and ("\n\n" .. T(_("%1 changes haven't been sent yet and will be lost."), queued)) or ""),
                ok_text = _("Disconnect"),
                ok_callback = function() Notes.disconnect(plugin) end,
            })
        end) } },
    })
    return dialog
end

function Notes.disconnect(plugin)
    plugin.store.memos = {}
    plugin:save()
    os.remove(Memos.cachePath())
    Notes.notes, Notes.filter = nil, { kind = "all" }
    if Notes.board then closeTop(Notes.board) end
    Log.info("notes: disconnected from Memos")
end

---------------------------------------------------------------- connecting

--- Check an address and token, and keep them. Returns ok, err (to show).
function Notes.connect(plugin, server_input, token)
    local server = Memos.normalizeServer(server_input)
    token = (token or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not server then return false, _("That address doesn't look right.") end
    if token == "" then return false, _("Paste an access token from Memos (Settings → Access Tokens).") end
    local trial = Memos:new{ server = server, token = token }
    local user, err = trial:me()
    local Lan = require("gzreader_lan")
    if not user and err == "unreachable" and Lan.plainRetry(server_input) then
        -- no https:// typed and no HTTPS there: a Memos on the home network (http)
        local plain = server:gsub("^https://", "http://")
        local t2 = Memos:new{ server = plain, token = token }
        local u2, e2 = t2:me()
        if u2 or e2 ~= "unreachable" then trial, user, err, server = t2, u2, e2, plain end
    end
    Log.info("notes: connecting to", server, user and "ok" or ("failed: " .. tostring(err)))
    if not user then
        if err == "unauthorized" then return false, _("Memos didn't accept that access token.") end
        if err == "unreachable" and not server_input:match("^%s*https?://") and not Lan.isPrivate(server) then return false, Lan.noHttpsText() end
        if err == "unreachable" then return false, _("Couldn't reach Memos at that address.") end
        return false, T(_("That doesn't look like a Memos server (%1)."), tostring(err))
    end
    local old = plugin.store.memos or {}
    local same = old.server == server
    plugin.store.memos = { server = server, token = token, prefix = trial.store.prefix,
        user = user.displayName ~= "" and user.displayName or user.username, user_name = user.name,
        queue = same and old.queue or nil, sync_tags = same and old.sync_tags or nil }
    plugin:save()
    if old.server ~= server then os.remove(Memos.cachePath()); Notes.notes = nil end
    Memos.forgetLacks() -- (spaces, journaling mode: asked again, in case the server was updated)
    return true
end

--- Not connected yet: how to connect (in the Notes tab).
--- The ways to connect (ZenOS rows: short labels, the explanation behind About).
function Notes.connectItems(plugin)
    local Rows = require("gzreader_rows")
    if require("gzreader_net").usb then
        -- no Wi-Fi: the sync page connects to Memos (gzreader_usbsync.lua)
        return Rows.mark({
            { text = _("Sync with computer"), gz_icon = Rows.FILE.usb, callback = function() require("gzreader_usbsync").show(plugin) end },
            Rows.about(_("About notes"), _("Notes come from Memos through your computer: connect Memos on the sync page, then sync. Notes you write here go back with the next sync.")),
        })
    end
    return Rows.mark({
        { text = _("Connect with QR code"), gz_icon = "send", callback = function()
            require("gzreader_net").run(function() Notes.qrConnect(plugin) end, { reason = "connecting to Memos" })
        end },
        { text = _("Connect by typing"), gz_icon = "keyboard", callback = function() Notes.typeConnect(plugin) end },
        { text = _("Copy from another GZreader"), gz_icon = "copy", callback = function() Notes.copyConnect(plugin) end },
        Rows.about(_("About Memos"), _("Connect with QR code: a code to open on your phone, where you enter the address and token.\n\nYou need your Memos address and an access token: in Memos, open Settings → Access Tokens and create one.")),
    })
end

function Notes.showConnect(plugin, again)
    local items = Notes.connectItems(plugin)
    local menu
    menu = Menu:new{
        title = _("Notes: connect to Memos"), item_table = items, covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = (not again) and Notes.TAB_ID or nil,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    menu.key_events.LeftButtonTap = nil
    if not again then pcall(Notes.decorate, menu, _("Notes")) end
    require("gzreader_rows").apply(menu)
    Notes.connect_menu = menu
    UIManager:show(menu)
    return menu
end

local function connected(plugin)
    if Notes.connect_menu then closeTop(Notes.connect_menu); Notes.connect_menu = nil end
    if Notes.board then closeTop(Notes.board) end
    info(T(_("Connected to Memos as %1."), plugin.store.memos.user or "?"), 3)
    Notes.notes = nil
    Notes.show(plugin)
end

function Notes.typeConnect(plugin)
    local MultiInputDialog = require("ui/widget/multiinputdialog")
    local d
    d = MultiInputDialog:new{
        title = _("Connect to Memos"),
        fields = {
            { description = _("Memos address"), text = (plugin.store.memos or {}).server or "", hint = "https://memos.example.com" },
            { description = _("Access token"), text = "", hint = _("from Memos → Settings → Access Tokens"), text_type = "password" },
        },
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = d:getFields()
                UIManager:close(d)
                require("gzreader_net").run(function()
                    local ok, err = Notes.connect(plugin, f[1], f[2])
                    if ok then connected(plugin) else info(err) end
                end, { reason = "connecting to Memos" })
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- Copy Memos from another GZreader on the Wi-Fi (gzreader_copy.lua); back
--- in the Notes tab, connected, when it worked.
function Notes.copyConnect(plugin)
    require("gzreader_copy").receive(plugin, { only = "notes", on_done = function(res)
        if not (res.notes and Notes.client(plugin):isConnected()) then return end
        if not (Notes.connect_menu or Notes.board) then return end
        if Notes.connect_menu then closeTop(Notes.connect_menu); Notes.connect_menu = nil end
        if Notes.board then closeTop(Notes.board) end
        Notes.notes = nil
        Notes.show(plugin)
    end })
end

--- Connect with QR code: the phone page (gzreader_phone.lua), at Notes.
--- Back in the Notes tab afterwards when it was connected there.
function Notes.qrConnect(plugin)
    require("gzreader_phone").open(plugin, { section = "notes", on_close = function(changes)
        if not (changes.notes and Notes.client(plugin):isConnected()) then return end
        if not (Notes.connect_menu or Notes.board) then return end
        if Notes.connect_menu then closeTop(Notes.connect_menu); Notes.connect_menu = nil end
        if Notes.board then closeTop(Notes.board) end
        Notes.notes = nil
        Notes.show(plugin)
    end })
end

return Notes
