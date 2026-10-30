--[[--
The Notes tab: your Memos notes as sticky notes.

- Board: six sticky notes per page (Q–Y open one; ◀ ▶ pages), pinned first.
  N new note, F filter, Menu more (refresh, connect, disconnect).
- A note: the whole text, checklist items you tick with their letter key
  (saved to Memos), pictures, tags, place, attachments (PDFs open in the
  reader, pictures in the image viewer). Alt+E edit, Alt+P pin.
- Filters: tag, date, place, with attachments, pinned, search.
- Offline: the last notes are kept on the Kindle; changes wait for Wi-Fi.

The board is a KOReader Menu so ZenOS puts its tab bar under it (Notes
replaces Favorites); its page is drawn as sticky notes (gzreader_sticky).
]]

local Blitbuffer = require("ffi/blitbuffer")
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
local Sticky = require("gzreader_sticky")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen
local S = function(px) return Screen:scaleBySize(px) end

local Notes = {
    TAB_ID = "ct_notes",
    COLS = 2, ROWS = 3,
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

--- The tags chosen in Settings → Notes → Sync only these tags, or nil (all notes).
function Notes.syncTags(plugin)
    local t = plugin.store.memos and plugin.store.memos.sync_tags
    return (type(t) == "table" and #t > 0) and t or nil
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
    if f.kind == "tag" then return string.format('%q in tags', f.value) end
    if f.kind == "pinned" then return "pinned == true" end
    if f.kind == "date" then return string.format('created_ts > now - duration("%dh")', f.value * 24) end
    if f.kind == "search" then return string.format("content.contains(%q)", f.value) end
    return nil
end

--- The part done on the Kindle (Memos v0.31 can't filter by place or attachments).
function Notes.keep(m, f)
    f = f or Notes.filter
    if f.kind == "place" then return m.place == f.value end
    if f.kind == "attachments" then return #(m.attachments or {}) > 0 end
    return true
end

function Notes.visible()
    local out = {}
    for _i, m in ipairs(Notes.notes or {}) do
        if Notes.keep(m) then out[#out + 1] = m end
    end
    return out
end

function Notes.filterLabel(f)
    f = f or Notes.filter
    if f.kind == "tag" then return "#" .. f.value end
    if f.kind == "date" then return f.label end
    if f.kind == "place" then return f.value end
    if f.kind == "attachments" then return _("With attachments") end
    if f.kind == "pinned" then return _("Pinned") end
    if f.kind == "search" then return "\u{201C}" .. f.value .. "\u{201D}" end
    return _("All notes")
end

--- Notes from the cache (shown at once), with queued changes applied.
function Notes.loadCache(plugin)
    local cache = Memos.loadCache()
    Notes.notes = cache and cache.notes or {}
    Notes.cached_at = cache and cache.at
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
                    created = os.date("!%Y-%m-%dT%H:%M:%SZ", q.at), attachments = {}, pinned = false, pending = true })
            end
        else
            for _j, m in ipairs(Notes.notes) do
                if m.name == q.name then
                    if q.op == "update" then m.content = q.content; m.tags = Notes.tagsIn(q.content) end
                    if q.op == "pin" then m.pinned = q.pinned end
                    m.pending = true
                end
            end
        end
    end
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
--- on_done(ok, err) on the screen's thread.
function Notes.refresh(plugin, on_done)
    local client = Notes.client(plugin)
    if not client:isConnected() then return on_done and on_done(false, "not_connected") end
    if Notes.refreshing then return end
    Notes.refreshing = true
    local Async = require("gzreader_async")
    local store = plugin.store.memos
    local function fetch()
        local query = Notes.query(plugin)
        local keep = Notes.prefs(plugin).keep
        Async.run(client, function(c) return c:listAll(query, keep) end, function(res, err)
            Notes.refreshing = false
            if not res then
                Log.warn("notes: refresh failed:", tostring(err))
                Notes.last_error = err
                return on_done and on_done(false, err)
            end
            Notes.last_error = nil
            if type(res.tags) == "table" then store.tag_counts = res.tags; plugin:save() end
            Notes.notes = res.memos
            Notes.applyQueue(plugin)
            if not Notes.cel() then Memos.saveCache({ notes = res.memos, at = os.time() }) end
            Notes.cached_at = os.time()
            Log.info("notes: refreshed", #res.memos)
            if on_done then on_done(true) end
        end, "notes: list")
    end
    if store.queue and #store.queue > 0 then
        local queue = store.queue
        Async.run(client, function(c) return c:flush(queue) end, function(res)
            if type(res) == "table" then
                local gone = {}
                for _i, id in ipairs(res.done or {}) do gone[id] = true end
                local left = {}
                for _i, q in ipairs(store.queue or {}) do if not gone[q.id] then left[#left + 1] = q end end
                store.queue = left
                plugin:save()
                if res.err then Log.warn("notes: queued changes:", tostring(res.err), #left, "left") end
            end
            fetch()
        end, "notes: send changes")
    else
        fetch()
    end
end

local function describe(err)
    if err == "unauthorized" then return _("Memos didn't accept the access token. Connect again with a new one (Menu → Connect to Memos).") end
    if err == "unreachable" then return _("Couldn't reach Memos. Check Wi-Fi and the address.") end
    if err == "not_connected" then return _("Not connected to Memos.") end
    if err == "timeout" then return _("Memos took too long to answer.") end
    return T(_("Memos answered: %1"), tostring(err))
end
Notes.describe = describe

---------------------------------------------------------------- the board

local StickyItem = InputContainer:extend{ entry = nil, menu = nil, dimen = nil, shortcut = nil, look = nil, focused = false }

function StickyItem:init()
    self.ges_events = {
        TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
    }
    self:draw()
end

function StickyItem:draw()
    local w, h = self.dimen.w, self.dimen.h
    local note_w, note_h = math.floor(w * 0.88), math.floor(h * 0.86)
    local m = self.entry.memo
    if self.img then self.img:free(); self.img = nil end
    if not m then -- "No notes" and the like
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
            TextBoxWidget:new{ text = self.entry.text, face = Sticky.hand(20), width = w - S(20), alignment = "center" } }
        return
    end
    local paper = Sticky.paper(self.look)
    local pad = S(8)
    local inner_w = note_w - 2 * pad - 2 * Size.border.thin
    local sc = self.shortcut and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(24), h = S(24) }, self.shortcut, "square")
    local head = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = S(24) },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            HorizontalGroup:new{ sc or HorizontalSpan:new{ width = 0 }, HorizontalSpan:new{ width = sc and S(6) or 0 },
                TextWidget:new{ text = m.pending and (Sticky.when(m.created) .. " \u{2022} " .. _("not sent yet")) or Sticky.when(m.created),
                    face = Sticky.hand(15), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = inner_w - S(50) } } },
        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = S(24) },
            m.pinned and TextWidget:new{ text = Sticky.ICONS.pin, face = Sticky.iconFace(15) } or HorizontalSpan:new{ width = 0 } },
    }
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
    -- the text gets what's left of the note
    local body_h = note_h - 2 * pad - 2 * Size.border.thin - head:getSize().h - S(6) - S(4)
        - (tag_line and tag_line:getSize().h or 0) - (#foot_bits > 0 and foot_bits:getSize().h or 0)
    local pic = Notes.picture(self.menu.plugin, m, inner_w, math.floor(body_h * 0.55), true)
    local text_h = pic and (body_h - pic:getSize().h - S(4)) or body_h
    local body = TextBoxWidget:new{ text = Sticky.preview(m.content), face = Sticky.hand(19), width = inner_w,
        height = text_h, height_adjust = false, height_overflow_show_ellipsis = true, bgcolor = paper }
    local content = VerticalGroup:new{ align = "left", head, VerticalSpan:new{ width = S(6) }, body }
    if pic then content[#content + 1] = VerticalSpan:new{ width = S(4) }; content[#content + 1] = pic end
    content[#content + 1] = VerticalSpan:new{ width = S(4) }
    if tag_line then content[#content + 1] = tag_line end
    if #foot_bits > 0 then content[#content + 1] = foot_bits end
    local frame = FrameContainer:new{
        width = note_w, height = note_h, padding = pad, margin = 0, bordersize = Size.border.thin,
        background = paper, color = Blitbuffer.COLOR_DARK_GRAY, content,
    }
    self.img = Sticky.image(frame, note_w, note_h, self.look, self.focused)
    frame:free()
    self[1] = CenterContainer:new{ dimen = Geom:new{ w = w, h = h },
        ImageWidget:new{ image = self.img, image_disposable = false } }
end

function StickyItem:onFocus()
    if not self.focused then self.focused = true; self:draw() end
    return true
end

function StickyItem:onUnfocus()
    if self.focused then self.focused = false; self:draw() end
    return true
end

function StickyItem:onTapSelect()
    if self.entry.memo then self.menu:onMenuSelect(self.entry) end
    return true
end

function StickyItem:onHoldSelect() return self:onTapSelect() end

function StickyItem:onCloseWidget()
    if self.img then self.img:free(); self.img = nil end
end

--- A picture for note `m` (its first image), shrunk: an ImageWidget or nil.
--- Not on the Kindle yet: fetched in the background, then the view redraws.
function Notes.picture(plugin, m, max_w, max_h, small)
    local src = Sticky.firstImage(m.content)
    local att
    if src then
        local uid = src:match("/file/attachments/([^/%?]+)")
        for _i, a in ipairs(m.attachments or {}) do
            if uid and tostring(a.name):match("attachments/(.+)$") == uid then att = a end
        end
    end
    if not att then
        for _i, a in ipairs(m.attachments or {}) do
            if tostring(a.type):match("^image/") and not att then att = a end
        end
    end
    if not att then return nil end
    local path = Memos.filePath(att)
    if lfs.attributes(path, "mode") ~= "file" then
        if small then -- on the board: redraw it once the picture is here
            Notes.fetchFile(plugin, att, function()
                if Notes.board and not Notes.board._gz_closed then Notes.board:updateItems() end
            end)
        end
        return nil
    end
    local bb = Sticky.picture(path, max_w, max_h)
    if not bb then return nil end
    return FrameContainer:new{ padding = 0, bordersize = Size.border.thin, ImageWidget:new{ image = bb, image_disposable = true } }
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

--- Download an attachment in the background (only while Wi-Fi is up), then on_done().
function Notes.fetchFile(plugin, att, on_done)
    local path = Memos.filePath(att)
    if Notes.fetching[path] then return end
    local ok_net, Net = pcall(require, "gzreader_net")
    if not (ok_net and Net.connected()) then return end
    Notes.fetching[path] = true
    require("gzreader_async").run(Notes.client(plugin), function(c) return c:download(att, path) end, function(got, err)
        Notes.fetching[path] = nil
        if not got then Log.warn("notes: attachment not downloaded:", tostring(err)) end
        if got then Notes.pruneFiles(plugin, path) end
        if got and on_done then on_done() end
    end, "notes: attachment")
end

local function boardItems()
    local items = {}
    for _i, m in ipairs(Notes.visible()) do
        items[#items + 1] = { memo = m, text = Sticky.preview(m.content) }
    end
    if #items == 0 then
        if Notes.last_error then -- not "no notes": say why they didn't load
            items[1] = { text = T(_("Couldn't load your notes. %1\n\nMenu → Refresh to try again."), describe(Notes.last_error)) }
        elseif Notes.refreshing or not Notes.cached_at then -- (nothing kept from before: first load)
            items[1] = { text = _("Loading your notes…") }
        else
            items[1] = { text = Notes.filter.kind == "all" and _("No notes yet. Press N to write one.")
                or _("No notes match. Press F to change the filter.") }
        end
    end
    return items
end

--- Draw the board's page as sticky notes (replaces Menu:updateItems).
local function drawBoard(m, select_number)
    local old_dimen = m.dimen and m.dimen:copy()
    m.layout = {}
    m.item_group:clear()
    m.page_info:resetLayout()
    m.return_button:resetLayout()
    m.content_group:resetLayout()
    m.items_per_page = Notes.COLS * Notes.ROWS
    m:_recalculateDimen(false)
    local per = m.perpage
    local offset = (m.page - 1) * per
    local cell_w = math.floor(m.item_dimen.w / Notes.COLS)
    local cell_h = math.floor(m.available_height / Notes.ROWS)
    local row, layout_row
    for i = 1, per do
        local e = m.item_table[offset + i]
        if not e then break end
        e.idx = offset + i
        if offset + i == m.itemnumber then select_number = i end
        if (i - 1) % Notes.COLS == 0 then
            row = HorizontalGroup:new{ align = "top" }
            layout_row = {}
            table.insert(m.item_group, row)
            table.insert(m.layout, layout_row)
        end
        local item = StickyItem:new{ entry = e, menu = m, look = Sticky.look(i), show_parent = m.show_parent,
            shortcut = e.memo and KEYS[i] or nil,
            dimen = Geom:new{ w = e.memo and cell_w or m.item_dimen.w, h = cell_h } }
        table.insert(row, item)
        table.insert(layout_row, item)
    end
    m:updatePageInfo(select_number)
    m:mergeTitleBarIntoLayout()
    UIManager:setDirty(m.show_parent, function()
        return "ui", old_dimen and old_dimen:combine(m.dimen) or m.dimen
    end)
end

-- The board: a Menu (ZenOS puts its tab bar under it) whose page is drawn as
-- sticky notes. Q–Y open notes; N new note; F filter.
Notes.Board = Menu:extend{}

function Notes.Board:updateItems(select_number) return drawBoard(self, select_number) end

function Notes.Board:onMenuSelect(item)
    if item.memo then Notes.showNote(self.plugin, item.memo) end
    return true
end

function Notes.Board:onSelectByShortCut(arg, keyevent)
    local k = keyevent and keyevent.key
    if k == "N" then Notes.edit(self.plugin); return true end
    if k == "F" then Notes.showFilter(self.plugin); return true end
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
    b:switchItemTable(Notes.title(), boardItems(), keep_page and -1 or nil)
    pcall(Notes.decorate, b)
end

--- ZenOS's status row (clock, battery, Wi-Fi) in the title, like other tabs.
function Notes.decorate(menu, label)
    -- ZenOS: __ZEN_UI_PLUGIN is only set while ZenOS sets itself up, so
    -- after that the file manager's reference is the one to use (1.5.2: the
    -- status row never showed and the title kept KOReader's close button).
    local FileManager = require("apps/filemanager/filemanager")
    local zen = (FileManager.instance and FileManager.instance.zenos) or rawget(_G, "__ZEN_UI_PLUGIN")
    if not (menu and menu.title_bar and zen) then return end
    local SharedState = require("common/shared_state")
    local createStatusRow = SharedState.get(zen, "createStatusRow")
    if type(createStatusRow) ~= "function" then return end
    local StandalonePage = require("modules/filebrowser/patches/standalone_page")
    StandalonePage.apply_status_row(menu, {
        createStatusRow = createStatusRow,
        createStatusRowCustomBack = SharedState.get(zen, "createStatusRowCustomBack"),
        repaintTitleBar = SharedState.get(zen, "repaintTitleBar"),
        label = label or Notes.title(),
    })
end

--- Close GZreader's other tab views (the Grimmory tab, or the Notes tab
--- itself when `keep` is Grimmory's): ZenOS opens an action tab on top of the
--- one open, so switching between them stacked full-screen views (1.5.2).
function Notes.closeOtherTabs(keep_id)
    local stack = UIManager._window_stack or {}
    local close = {}
    for _i, w in ipairs(stack) do
        local id = w.widget and w.widget._gz_navbar_tab_id
        if id and id ~= keep_id and (id == Notes.TAB_ID or id == "ct_grimmory") then close[#close + 1] = w.widget end
    end
    for _i, widget in ipairs(close) do UIManager:close(widget) end
end

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
        subtitle = _("N new note  \u{00B7}  F filter  \u{00B7}  Menu more"),
        item_table = boardItems(),
        covers_fullscreen = true, is_borderless = true, is_popout = false, title_bar_fm_style = true,
        _gz_navbar_tab_id = Notes.TAB_ID,
        plugin = plugin,
    }
    menu.key_events.LeftButtonTap = nil -- (KOReader's Menu also maps the Menu key)
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
    menu.key_events.GzNotesMenu = { { "Menu" } }
    menu.onGzNotesMenu = function() Notes.showOptions(plugin); return true end
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        m._gz_closed = true
        if Notes.board == m then Notes.board = nil end
        local Net = package.loaded["gzreader_net"]
        if Net then Net.release("notes") end
        if orig_close then return orig_close(m, ...) end
    end
    Notes.board = menu
    pcall(Notes.decorate, menu)
    UIManager:show(menu)
    -- fresh notes (Wi-Fi only when needed: brought up quietly, kept while open)
    local Net = require("gzreader_net")
    Net.hold("notes")
    Net.run(function()
        Notes.refresh(plugin, function(_ok, err)
            Notes.reloadBoard(true) -- the notes, or why they didn't load
            if err == "unauthorized" then info(describe(err)) end
        end)
    end, { quiet = true, reason = "notes" })
    return menu
end

---------------------------------------------------------------- one note

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
        Options = { { "Menu" } },
        PageDown = { { { "RPgFwd", "LPgFwd" } } },
        PageUp = { { { "RPgBack", "LPgBack" } } },
    }
    self:build()
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
    add(iconLine("date", Sticky.when(m.created) .. (m.pinned and ("   \u{00B7}   " .. _("pinned")) or "")
        .. (m.pending and ("   \u{00B7}   " .. _("not sent yet")) or ""), Font:getFace("cfont", 15), false, Blitbuffer.COLOR_DARK_GRAY))
    add(VerticalSpan:new{ width = S(10) })
    local para = {}
    local function flush()
        local t = table.concat(para, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
        para = {}
        if t ~= "" then add(TextBoxWidget:new{ text = t, face = Sticky.hand(24), width = inner }) end
    end
    local n_check = 0
    for _i, l in ipairs(Sticky.lines(m.content)) do
        if l.kind == "check" then
            flush()
            n_check = n_check + 1
            local key = KEYS[#self.picks + 1]
            self.picks[#self.picks + 1] = { check = n_check }
            local focused = self.focus == #self.picks
            local sc = key and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, key, "square")
            add(FrameContainer:new{ padding = S(3), margin = 0, bordersize = focused and Size.border.thick or 0, width = inner,
                HorizontalGroup:new{ align = "center", sc or HorizontalSpan:new{ width = S(26) }, HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = l.done and "\u{2611}" or "\u{2610}", face = Font:getFace("cfont", 26) },
                    HorizontalSpan:new{ width = S(8) },
                    TextWidget:new{ text = Sticky.plain(l.text), face = Sticky.hand(24), max_width = inner - S(90),
                        fgcolor = l.done and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK } } })
        elseif l.kind == "heading" then
            flush()
            add(VerticalSpan:new{ width = S(6) })
            add(TextBoxWidget:new{ text = Sticky.plain(l.text), face = Sticky.hand(l.level <= 1 and 32 or (l.level == 2 and 29 or 26)),
                bold = true, width = inner })
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
    add(VerticalSpan:new{ width = S(12) })
    if #(m.tags or {}) > 0 then
        local tags = {}
        for _i, t in ipairs(m.tags) do tags[#tags + 1] = "#" .. t end
        add(iconLine("tag", table.concat(tags, "  "), Sticky.hand(20), true))
    end
    if m.place then
        add(VerticalSpan:new{ width = S(4) })
        add(iconLine("place", m.place, Font:getFace("cfont", 17)))
    end
    if #(m.attachments or {}) > 0 then
        add(VerticalSpan:new{ width = S(14) })
        add(TextWidget:new{ text = _("Attachments"), face = Font:getFace("smalltfont", 17), bold = true })
        add(VerticalSpan:new{ width = S(6) })
        for _i, a in ipairs(m.attachments) do
            local key = KEYS[#self.picks + 1]
            self.picks[#self.picks + 1] = { att = a }
            local focused = self.focus == #self.picks
            local sc = key and Menu.getItemShortCutIcon(nil, Geom:new{ w = S(26), h = S(26) }, key, "square")
            local here = lfs.attributes(Memos.filePath(a), "mode") == "file"
            local size = a.size and (a.size >= 1048576 and string.format("%.1f MB", a.size / 1048576)
                or string.format("%d KB", math.max(1, math.floor(a.size / 1024)))) or ""
            add(FrameContainer:new{ padding = S(8), bordersize = focused and Size.border.thick or Size.border.thin,
                radius = S(4), width = inner,
                HorizontalGroup:new{ align = "center", sc or HorizontalSpan:new{ width = S(26) }, HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = (tostring(a.type):match("^image/") and Sticky.ICONS.image or Sticky.ICONS.pdf) .. "  ",
                        face = Sticky.iconFace(18) },
                    TextWidget:new{ text = a.filename or "?", face = Font:getFace("cfont", 18), max_width = inner - S(170) },
                    HorizontalSpan:new{ width = S(10) },
                    TextWidget:new{ text = size .. (here and "" or (" \u{00B7} " .. _("download"))), face = Font:getFace("cfont", 14),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY } } })
        end
    end
    local hint = (#self.picks > 0 and (KEYS[1] .. (#self.picks > 1 and ("\u{2013}" .. KEYS[math.min(#self.picks, #KEYS)]) or "") .. "  "
        .. (n_check > 0 and _("tick / open") or _("open")) .. "     ") or "")
        .. _("Alt+E edit     Alt+P pin     Menu more     Back board")
    local title_h, footer_h = S(46), S(34)
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local content_h = sh - title_h - footer_h
    self.scroller = ScrollableContainer:new{
        dimen = Geom:new{ w = sw, h = content_h }, show_parent = self,
        HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = margin }, g },
    }
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = title_h },
                TextWidget:new{ text = _("Note"), face = Font:getFace("smalltfont", 22), bold = true } },
            self.scroller,
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = footer_h },
                TextWidget:new{ text = hint, face = Font:getFace("cfont", 13), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = sw - S(20) } },
        },
    }
end

function NoteView:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

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
    local pick = idx and self.picks[idx]
    if not pick then return true end
    if pick.check then
        self.memo.content = Sticky.toggle(self.memo.content, pick.check)
        self.focus = idx
        Notes.saveContent(self.plugin, self.memo)
        self:refresh()
    elseif pick.att then
        Notes.openAttachment(self.plugin, pick.att)
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

--- Open an attachment: PDFs and other documents in the reader, pictures in
--- the image viewer. Downloaded once and kept on the Kindle.
function Notes.openAttachment(plugin, att)
    if att.link then return info(T(_("This attachment is a link:\n%1"), att.link)) end
    local path = Memos.filePath(att)
    local function open()
        pcall(lfs.touch, path) -- used now: kept longest when space runs short
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
    end
    if lfs.attributes(path, "mode") == "file" then return open() end
    local busy = InfoMessage:new{ text = T(_("Downloading %1…"), att.filename or ""), timeout = 0 }
    UIManager:show(busy)
    require("gzreader_net").run(function()
        require("gzreader_async").run(Notes.client(plugin), function(c) return c:download(att, path) end, function(got, err)
            UIManager:close(busy)
            if got then Notes.pruneFiles(plugin, path); open() else info(describe(err)) end
        end, "notes: attachment")
    end, { reason = "a note's attachment" })
end

---------------------------------------------------------------- saving

--- Save a note's new text (queued; sent now when possible). `visibility`:
--- only when it changed.
function Notes.saveContent(plugin, memo, visibility)
    memo.tags = Notes.tagsIn(memo.content)
    if visibility then memo.visibility = visibility end
    if memo.name then
        local q = { op = "update", name = memo.name, content = memo.content }
        -- an earlier, unsent change of who can see it stays
        for _i, old in ipairs(plugin.store.memos.queue or {}) do
            if old.op == "update" and old.name == memo.name and old.visibility then q.visibility = old.visibility end
        end
        q.visibility = visibility or q.visibility
        Notes.enqueue(plugin, q)
    elseif memo.local_id then
        -- not in Memos yet: change the queued new note instead
        for _i, q in ipairs(plugin.store.memos.queue or {}) do
            if q.id == memo.local_id then
                q.content = memo.content
                if visibility then q.visibility = visibility end
            end
        end
        plugin:save()
    end
    memo.pending = true
    Notes.sendSoon(plugin)
end

--- Send queued changes when Wi-Fi is up (never turns it on just for this,
--- unless the Notes tab is open, which holds it).
function Notes.sendSoon(plugin)
    if Notes.send_scheduled then return end
    Notes.send_scheduled = true
    UIManager:scheduleIn(2, function()
        Notes.send_scheduled = false
        local Net = require("gzreader_net")
        if not Net.connected() then return end
        Notes.refresh(plugin, function(ok) if ok then Notes.reloadBoard(true) end end)
    end)
end

--- New note (memo nil) or edit one: the full-page editor.
function Notes.edit(plugin, memo)
    require("gzreader_noteeditor").show{
        plugin = plugin,
        memo = memo,
        tags = Notes.allTags(),
        on_save = function(content, visibility, vis_changed)
            if memo then
                memo.content = content
                Notes.saveContent(plugin, memo, vis_changed and visibility or nil)
            else
                local q = Notes.enqueue(plugin, { op = "create", content = content, visibility = visibility or "PRIVATE" })
                Notes.notes = Notes.notes or {}
                table.insert(Notes.notes, 1, { local_id = q.id, content = content, tags = Notes.tagsIn(content),
                    created = os.date("!%Y-%m-%dT%H:%M:%SZ"), attachments = {}, pinned = false, pending = true,
                    visibility = q.visibility })
                Notes.sendSoon(plugin)
            end
            Notes.reloadBoard(true)
            for _i, w in ipairs(UIManager._window_stack or {}) do
                if w.widget.memo == memo and w.widget.refresh and memo then w.widget:refresh() end
            end
        end,
    }
end

---------------------------------------------------------------- filters

function Notes.keyedDialog(title, rows)
    local dialog = ButtonDialog:new{ title = title, buttons = rows }
    local add = rawget(_G, "__ZEN_DIALOG_SHORTCUTS")
    if add then pcall(add, dialog) end
    UIManager:show(dialog)
    return dialog
end

function Notes.allTags()
    local count = {}
    for _i, m in ipairs(Notes.notes or {}) do
        for _j, t in ipairs(m.tags or {}) do count[t] = (count[t] or 0) + 1 end
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

function Notes.setFilter(plugin, f)
    Notes.filter = f
    -- place, attachments: picked out on the Kindle from all the notes
    if not Notes.cel(f) then Notes.loadCache(plugin) end
    Notes.reloadBoard(false)
    Notes.refresh(plugin, function(ok, err)
        if ok then Notes.reloadBoard(false) elseif err ~= "not_connected" then info(describe(err), 3) end
    end)
end

local function count(n) return n == 1 and _("1 note") or T(_("%1 notes"), n) end

local function listPicker(title, entries, on_pick)
    local items = {}
    for _i, e in ipairs(entries) do
        items[#items + 1] = { text = e.text, mandatory = e.mandatory, callback = function() on_pick(e) end }
    end
    if #items == 0 then items[1] = { text = _("Nothing here yet."), select_enabled = false } end
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
    UIManager:show(menu)
    return menu
end

function Notes.showFilter(plugin)
    local dialog
    local function pick(fn) return function() UIManager:close(dialog); fn() end end
    local cur = Notes.filter.kind
    local function mark(kind, text) return text .. (cur == kind and "  \u{2713}" or "") end
    dialog = Notes.keyedDialog(_("Show notes"), {
        { { text = mark("all", _("All notes")), align = "left", callback = pick(function() Notes.setFilter(plugin, { kind = "all" }) end) } },
        { { text = mark("tag", _("Tag…")), align = "left", callback = pick(function()
            local entries = {}
            for _i, t in ipairs(Notes.allTags()) do
                entries[#entries + 1] = { text = "#" .. t.tag, mandatory = count(t.count), tag = t.tag }
            end
            listPicker(_("Filter by tag"), entries, function(e) Notes.setFilter(plugin, { kind = "tag", value = e.tag }) end)
        end) } },
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
                entries[#entries + 1] = { text = p.place, mandatory = count(p.count), place = p.place }
            end
            listPicker(_("Filter by place"), entries, function(e) Notes.setFilter(plugin, { kind = "place", value = e.place }) end)
        end) } },
        { { text = mark("attachments", _("With attachments")), align = "left", callback = pick(function()
            Notes.setFilter(plugin, { kind = "attachments" })
        end) } },
        { { text = mark("pinned", _("Pinned")), align = "left", callback = pick(function() Notes.setFilter(plugin, { kind = "pinned" }) end) } },
        { { text = mark("search", _("Search text…")), align = "left", callback = pick(function()
            local InputDialog = require("ui/widget/inputdialog")
            local d
            d = InputDialog:new{ title = _("Search notes"), input = "",
                buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                    { text = _("Search"), is_enter_default = true, callback = function()
                        local q = d:getInputText()
                        UIManager:close(d)
                        if q ~= "" then Notes.setFilter(plugin, { kind = "search", value = q }) end
                    end } } } }
            UIManager:show(d)
            d:onShowKeyboard()
        end) } },
    })
end

function Notes.showOptions(plugin)
    local dialog
    local function run(fn) return function() UIManager:close(dialog); fn() end end
    local client = Notes.client(plugin)
    local store = plugin.store.memos
    local queued = #(store.queue or {})
    dialog = Notes.keyedDialog(store.user and T(_("Memos: %1"), store.user) or _("Memos"), {
        { { text = _("New note"), align = "left", callback = run(function() Notes.edit(plugin) end) } },
        { { text = _("Filter…"), align = "left", callback = run(function() Notes.showFilter(plugin) end) } },
        { { text = queued > 0 and T(_("Refresh (%1 changes to send)"), queued) or _("Refresh"), align = "left",
            callback = run(function()
                require("gzreader_net").run(function()
                    Notes.refresh(plugin, function(ok, err)
                        if ok then Notes.reloadBoard(true) else info(describe(err)) end
                    end)
                end, { reason = "notes" })
            end) } },
        { { text = _("Connect to Memos again"), align = "left", callback = run(function() Notes.showConnect(plugin, true) end) } },
        { { text = _("Disconnect from Memos"), align = "left", enabled = client:isConnected(), callback = run(function()
            local ConfirmBox = require("ui/widget/confirmbox")
            UIManager:show(ConfirmBox:new{
                text = _("Disconnect from Memos?\n\nThe notes kept on this Kindle are removed. Your notes in Memos stay as they are.")
                    .. (queued > 0 and ("\n\n" .. T(_("%1 changes haven't been sent yet and will be lost."), queued)) or ""),
                ok_text = _("Disconnect"),
                ok_callback = function() Notes.disconnect(plugin) end,
            })
        end) } },
    })
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
    if not user and err == "unreachable" and not server_input:match("^%s*https?://") then
        -- no https:// typed and no HTTPS there: a Memos on the home network (http)
        local plain = server:gsub("^https://", "http://")
        local t2 = Memos:new{ server = plain, token = token }
        local u2, e2 = t2:me()
        if u2 or e2 ~= "unreachable" then trial, user, err, server = t2, u2, e2, plain end
    end
    Log.info("notes: connecting to", server, user and "ok" or ("failed: " .. tostring(err)))
    if not user then
        if err == "unauthorized" then return false, _("Memos didn't accept that access token.") end
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
    return true
end

--- Not connected yet: how to connect (in the Notes tab).
function Notes.showConnect(plugin, again)
    local items = {
        { text = _("Connect with QR code (enter it on your phone)"), callback = function()
            require("gzreader_net").run(function() Notes.qrConnect(plugin) end, { reason = "connecting to Memos" })
        end },
        { text = _("Connect by typing"), callback = function() Notes.typeConnect(plugin) end },
        { text = _("You need your Memos address and an access token: in Memos, open Settings → Access Tokens and create one."),
          select_enabled = false },
    }
    local menu
    menu = Menu:new{
        title = _("Notes: connect to Memos"), item_table = items, covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, _gz_navbar_tab_id = (not again) and Notes.TAB_ID or nil,
        onMenuSelect = function(_m, item) if item.callback then item.callback() end return true end,
    }
    menu.key_events.LeftButtonTap = nil
    if not again then pcall(Notes.decorate, menu, _("Notes")) end
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

--- The phone enters the address and token (the Kindle Keyboard is slow for a
--- long token): same one-off page as connecting to Grimmory.
function Notes.qrConnect(plugin)
    local PairServer = require("gzreader_pairserver")
    local PairPage = require("gzreader_pairpage")
    local NetworkMgr = require("ui/network/manager")
    local token = PairServer.randomToken(16)
    local base = "/notes/" .. token
    local server, screen, timeout_task, done
    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if screen then UIManager:close(screen) end
    end
    server = PairServer:new{
        handler = function(method, path, _headers, body)
            if path ~= base then return 404, "text/plain", "Not found" end
            if method == "GET" then
                return 200, "text/html", PairPage.memosForm{ server = (plugin.store.memos or {}).server }
            end
            if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
            local form = PairServer.parseForm(body)
            local ok, err = Notes.connect(plugin, form.server, form.token)
            if not ok then
                return 200, "text/html", PairPage.memosForm{ server = form.server, error = err }
            end
            UIManager:nextTick(function() finish(); connected(plugin) end)
            return 200, "text/html", PairPage.memosSuccess(plugin.store.memos.user)
        end,
    }
    local ok, serr = server:start()
    if not ok then return info(T(_("Couldn't start: %1"), tostring(serr))) end
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = PairServer.localIp(nil, iface)
    if not ip then
        server:stop()
        return info(_("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why))
    end
    UIManager:insertZMQ(server)
    screen = require("gzreader_pairscreen"):new{
        url = T("http://%1:%2%3", ip, server.port, base),
        title = _("Connect to Memos"),
        instructions = _("Scan this code with your phone's camera, then enter your Memos address and an access token (Memos → Settings → Access Tokens). Your phone must be on the same Wi-Fi as this Kindle."),
        footer = _("Press Back to cancel."),
        on_cancel = function() screen = nil; finish() end,
    }
    UIManager:show(screen)
    timeout_task = function() finish() end
    UIManager:scheduleIn(600, timeout_task)
end

return Notes
