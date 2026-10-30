--[[--
Settings → Notes: the Memos connection, what's kept on the Kindle (and
freeing it), which tags to sync, and limits for kept notes and attachments.

Memos has no spaces or notebooks: tags are how notes are grouped, so "sync
only these tags" is how to keep part of your notes on the Kindle.
]]

local UIManager = require("ui/uimanager")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local NoteSettings = {}

NoteSettings.KEEP_CHOICES = { 50, 100, 200, 500 }
NoteSettings.FILES_CHOICES = { 10, 25, 50, 100, 0 } -- MB; 0: no limit

local function size(bytes)
    bytes = bytes or 0
    if bytes >= 1048576 then return string.format("%.1f MB", bytes / 1048576) end
    if bytes >= 1024 then return string.format("%d KB", math.floor(bytes / 1024 + 0.5)) end
    return T(_("%1 bytes"), bytes)
end
NoteSettings.size = size

local function closeTouchMenu(touchmenu)
    if touchmenu and touchmenu.closeMenu then pcall(touchmenu.closeMenu, touchmenu) end
end

local function info(text, timeout)
    UIManager:show(require("ui/widget/infomessage"):new{ text = text, timeout = timeout })
end

local function confirm(text, ok_text, fn)
    UIManager:show(require("ui/widget/confirmbox"):new{ text = text, ok_text = ok_text, ok_callback = fn })
end

--- After the synced tags change: the notes kept on the Kindle are another
--- set now, so they're fetched again (queued changes are kept).
local function resetKept(Notes, plugin)
    os.remove(require("gzreader_memos").cachePath())
    Notes.notes, Notes.cached_at, Notes.last_error = nil, nil, nil
    if Notes.board and not Notes.board._gz_closed then
        Notes.loadCache(plugin)
        Notes.reloadBoard(false)
        Notes.refresh(plugin, function() Notes.reloadBoard(false) end)
    end
end

--- Every tag we know of: Memos' counts (all your notes), the notes on the
--- Kindle, and the ones chosen. { {tag=, count=} }, most used first.
function NoteSettings.knownTags(plugin)
    local Notes = require("gzreader_notes")
    local count = {}
    local store = plugin.store.memos or {}
    for tag, n in pairs(type(store.tag_counts) == "table" and store.tag_counts or {}) do count[tag] = tonumber(n) or 0 end
    for _i, t in ipairs(Notes.allTags()) do count[t.tag] = math.max(count[t.tag] or 0, t.count) end
    for _i, t in ipairs(Notes.syncTags(plugin) or {}) do count[t] = count[t] or 0 end
    local list = {}
    for tag, n in pairs(count) do list[#list + 1] = { tag = tag, count = n } end
    table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.tag < b.tag end)
    return list
end

local function syncLabel(plugin)
    local Notes = require("gzreader_notes")
    local tags = Notes.syncTags(plugin)
    if not tags then return _("Sync: all notes") end
    local t = {}
    for i, tag in ipairs(tags) do
        if i > 3 then t[#t + 1] = T(_("+%1 more"), #tags - 3); break end
        t[#t + 1] = "#" .. tag
    end
    return T(_("Sync: %1"), table.concat(t, ", "))
end

function NoteSettings.syncItems(plugin)
    local Notes = require("gzreader_notes")
    local store = plugin.store.memos or {}
    local function chosen(tag)
        for _i, t in ipairs(store.sync_tags or {}) do if t == tag then return true end end
        return false
    end
    local items = {
        {
            text = _("All notes"),
            radio = true,
            checked_func = function() return Notes.syncTags(plugin) == nil end,
            callback = function()
                if not Notes.syncTags(plugin) then return end
                store.sync_tags = nil
                plugin:save()
                Log.info("notes: syncing all notes")
                resetKept(Notes, plugin)
            end,
            separator = true,
        },
    }
    local tags = NoteSettings.knownTags(plugin)
    for _i, t in ipairs(tags) do
        items[#items + 1] = {
            text = "#" .. t.tag,
            mandatory = t.count > 0 and tostring(t.count) or nil,
            checked_func = function() return chosen(t.tag) end,
            callback = function()
                local list = {}
                local on = chosen(t.tag)
                for _j, x in ipairs(store.sync_tags or {}) do if x ~= t.tag then list[#list + 1] = x end end
                if not on then list[#list + 1] = t.tag end
                table.sort(list)
                store.sync_tags = #list > 0 and list or nil
                plugin:save()
                Log.info("notes: syncing tags", #list)
                resetKept(Notes, plugin)
            end,
        }
    end
    if #tags == 0 then
        items[#items + 1] = { text = _("No tags yet: open the Notes tab once (or Refresh the tag list)."), enabled = false }
    end
    items[#items].separator = true
    items[#items + 1] = {
        text = _("Refresh the tag list"),
        keep_menu_open = true,
        enabled_func = function() return Notes.client(plugin):isConnected() end,
        callback = function(touchmenu)
            require("gzreader_net").run(function()
                require("gzreader_async").run(Notes.client(plugin), function(c) return c:tagCounts() end, function(counts)
                    if type(counts) ~= "table" then return info(_("Memos didn't send the tag list."), 3) end
                    store.tag_counts = counts
                    plugin:save()
                    local n = 0
                    for _k in pairs(counts) do n = n + 1 end
                    info(T(_("%1 tags. Go back and open this list again to see them."), n), 3)
                    if touchmenu and touchmenu.updateItems then pcall(touchmenu.updateItems, touchmenu) end
                end, "notes: tags")
            end, { reason = "Memos tags" })
        end,
    }
    items[#items + 1] = {
        text = _("About syncing tags"),
        keep_menu_open = true,
        callback = function()
            info(_("Choose tags to keep only notes with at least one of them on the Kindle: only those are fetched, shown and kept. With none chosen, all your notes are synced.\n\nMemos has no spaces or notebooks: tags are how it groups notes, so use a tag (for example #kindle) for the notes you want here.\n\nA new note written on the Kindle without one of these tags is still saved to Memos, but won't show on the Kindle after the next refresh."))
        end,
    }
    return items
end

function NoteSettings.storageItems(plugin)
    local Notes = require("gzreader_notes")
    local Memos = require("gzreader_memos")
    local notes_bytes, file_bytes, files = Notes.storage()
    local kept = Notes.notes and #Notes.notes
    if not kept then
        local cache = Memos.loadCache()
        kept = cache and type(cache.notes) == "table" and #cache.notes or 0
    end
    local queued = #((plugin.store.memos or {}).queue or {})
    return {
        { text = T(_("Notes: %1 (%2 notes)"), size(notes_bytes), kept), enabled = false },
        { text = T(_("Attachments and pictures: %1 in %2 files"), size(file_bytes), files), enabled = false },
        { text = queued > 0 and T(_("Changes waiting to be sent: %1"), queued) or _("No changes waiting to be sent"),
          enabled = false, separator = true },
        {
            text = _("Free up space: remove downloaded attachments"),
            enabled = files > 0,
            callback = function(touchmenu)
                confirm(T(_("Remove the %1 attachments and pictures downloaded for your notes (%2)?\n\nThey stay in Memos and are downloaded again when you open them."),
                    files, size(file_bytes)), _("Remove"), function()
                    local dir = Memos.filesDir()
                    local n = 0
                    for name in require("libs/libkoreader-lfs").dir(dir) do
                        if name ~= "." and name ~= ".." and os.remove(dir .. "/" .. name) then n = n + 1 end
                    end
                    Log.info("notes: removed all attachments", n)
                    info(T(_("Removed %1 files."), n), 2)
                    if touchmenu and touchmenu.backToUpperMenu then pcall(touchmenu.backToUpperMenu, touchmenu) end
                end)
            end,
        },
        {
            text = _("Free up space: remove kept notes"),
            enabled = notes_bytes > 0,
            callback = function(touchmenu)
                confirm(T(_("Remove the notes kept on this Kindle (%1)?\n\nThey stay in Memos and are fetched again the next time you open the Notes tab with Wi-Fi. Changes not sent yet are kept."),
                    size(notes_bytes)), _("Remove"), function()
                    os.remove(Memos.cachePath())
                    Notes.notes, Notes.cached_at = nil, nil
                    Log.info("notes: removed kept notes")
                    info(_("Removed."), 2)
                    if touchmenu and touchmenu.backToUpperMenu then pcall(touchmenu.backToUpperMenu, touchmenu) end
                end)
            end,
        },
    }
end

function NoteSettings.items(plugin)
    local Notes = require("gzreader_notes")
    local okI, IconItem = pcall(require, "common/ui/icon_menu_item")
    local okc, icons = pcall(require, "common/inline_icon_map")
    local function icon(name, item)
        if okI and okc and icons[name] then return IconItem.decorate(item, icons[name]) end
        return item
    end
    local prefs = Notes.prefs(plugin)
    local function connected() return Notes.client(plugin):isConnected() end
    local keep_items = {}
    for _i, n in ipairs(NoteSettings.KEEP_CHOICES) do
        keep_items[#keep_items + 1] = {
            text = T(_("%1 notes"), n) .. (n == Notes.KEEP and ("  " .. _("(default)")) or "")
                .. (n >= 500 and ("  " .. _("(slower to load)")) or ""),
            radio = true,
            checked_func = function() return prefs.keep == n end,
            callback = function()
                prefs.keep = n
                plugin:save()
            end,
        }
    end
    local files_items = {}
    for _i, mb in ipairs(NoteSettings.FILES_CHOICES) do
        files_items[#files_items + 1] = {
            text = (mb == 0 and _("No limit") or T(_("%1 MB"), mb)) .. (mb == Notes.FILES_MB and ("  " .. _("(default)")) or ""),
            radio = true,
            checked_func = function() return prefs.files_mb == mb end,
            callback = function()
                prefs.files_mb = mb
                plugin:save()
                local n = Notes.pruneFiles(plugin)
                if n > 0 then info(T(_("Removed %1 attachments used longest ago."), n), 2) end
            end,
        }
    end
    return {
        icon("connect", {
            text_func = function()
                local s = plugin.store.memos or {}
                if not connected() then return _("Memos: not connected") end
                return T(_("Memos: %1 · %2"), s.user or "?", ((s.server or ""):gsub("^https?://", "")))
            end,
            sub_item_table_func = function()
                local s = plugin.store.memos or {}
                local items = {}
                if connected() then
                    items[#items + 1] = { text = T(_("Connected as %1"), s.user or "?"), enabled = false }
                    items[#items + 1] = { text = s.server or "", enabled = false, separator = true }
                end
                items[#items + 1] = {
                    text = connected() and _("Connect again with QR code") or _("Connect with QR code"),
                    callback = function(touchmenu)
                        closeTouchMenu(touchmenu)
                        require("gzreader_net").run(function() Notes.qrConnect(plugin) end, { reason = "connecting to Memos" })
                    end,
                }
                items[#items + 1] = {
                    text = connected() and _("Connect again by typing") or _("Connect by typing"),
                    callback = function(touchmenu)
                        closeTouchMenu(touchmenu)
                        Notes.typeConnect(plugin)
                    end,
                }
                if connected() then
                    items[#items].separator = true
                    items[#items + 1] = {
                        text = _("Disconnect from Memos"),
                        callback = function(touchmenu)
                            local queued = #(s.queue or {})
                            confirm(_("Disconnect from Memos?\n\nThe notes kept on this Kindle are removed. Your notes in Memos stay as they are.")
                                .. (queued > 0 and ("\n\n" .. T(_("%1 changes haven't been sent yet and will be lost."), queued)) or ""),
                                _("Disconnect"), function()
                                    Notes.disconnect(plugin)
                                    if touchmenu and touchmenu.backToUpperMenu then pcall(touchmenu.backToUpperMenu, touchmenu) end
                                end)
                        end,
                    }
                end
                return items
            end,
        }),
        icon("keywords", {
            text_func = function() return syncLabel(plugin) end,
            enabled_func = connected,
            sub_item_table_func = function() return NoteSettings.syncItems(plugin) end,
        }),
        icon("disk", {
            text_func = function()
                local a, b = Notes.storage()
                return T(_("Storage used: %1"), size(a + b))
            end,
            sub_item_table_func = function() return NoteSettings.storageItems(plugin) end,
            separator = true,
        }),
        icon("view_list", {
            text_func = function() return T(_("Notes kept on the Kindle: %1"), prefs.keep) end,
            help_text = _("The newest notes (pinned first) fetched from Memos and kept for offline use. More notes take longer to load on a Kindle 3."),
            sub_item_table = keep_items,
        }),
        icon("download", {
            text_func = function()
                return T(_("Attachment storage limit: %1"), prefs.files_mb == 0 and _("no limit") or T(_("%1 MB"), prefs.files_mb))
            end,
            help_text = _("Attachments and pictures you open are downloaded once and kept. Past this limit, the ones used longest ago are removed (they stay in Memos)."),
            sub_item_table = files_items,
        }),
    }
end

return NoteSettings
