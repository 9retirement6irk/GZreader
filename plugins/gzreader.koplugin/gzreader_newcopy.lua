--[[--
A book on the Kindle that Grimmory has a different copy of now.

A book replaced on Grimmory (a better edition uploaded over the old one)
keeps its id, so a Kindle that downloaded it before kept the old copy: the
owner's Kindle 3 had Dog Days from October (14.8 MB, a text edition that
came out wrong as a picture book) while the Scribe, downloading it in
November, had the new one (16.2 MB, the scanned pages). When a book opens,
its size here is compared with Grimmory's (the library index, kept on the
Kindle: no request); if they differ, GZreader asks once (for that copy)
whether to download it again. The place in the book comes back from
Grimmory as usual; how the old copy was shown (fitted as a picture book)
is forgotten, so the new one is looked at afresh.
]]

local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")

local NewCopy = {
    SLACK = 64 * 1024, -- (bytes: Grimmory gives sizes in KB, rounded)
    SHARE = 0.02,      -- (and a copy a few percent apart is a different one)
}

--- Does a file of `size` bytes differ from Grimmory's `kb`? (nil: unknown)
function NewCopy.differs(size, kb)
    size, kb = tonumber(size), tonumber(kb)
    if not size or not kb or kb <= 0 or size <= 0 then return nil end
    local there = kb * 1024
    return math.abs(size - there) > math.max(NewCopy.SLACK, NewCopy.SHARE * there)
end

--- The library index's record of a book: { id, file id, type, title, KB }, or nil.
function NewCopy.indexed(index, book_id)
    local files = type(index) == "table" and index.files
    if type(files) ~= "table" then return nil end
    local want = tostring(book_id)
    for name, info in pairs(files) do
        if type(info) == "table" and tostring(info[1]) == want then return info, name end
    end
    return nil
end

local function mb(bytes) return string.format("%.1f MB", bytes / 1048576) end

--- When a book from Grimmory opens: ask, once per copy, when Grimmory's differs.
function NewCopy.check(plugin, ui, book_id, entry)
    if not (plugin and plugin.store and ui and ui.document and entry and entry.path) then return end
    local ok_i, Index = pcall(require, "gzreader_index")
    local index = ok_i and Index.load(plugin.store) or nil
    local info, name = NewCopy.indexed(index, book_id)
    local kb = info and tonumber(info[5])
    local size = lfs.attributes(entry.path, "size")
    if not NewCopy.differs(size, kb) then return end
    plugin.store.newcopy_asked = plugin.store.newcopy_asked or {}
    local key = tostring(book_id)
    if plugin.store.newcopy_asked[key] == kb then return end
    Log.info("book", key, "differs from Grimmory's copy:", mb(size), "here,", mb(kb * 1024), "on Grimmory")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(2, function()
        if not (ui.document and ui.document.file == entry.path) then return end
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = require("gzreader_servername").fix(T(_("Grimmory has a different copy of “%1” now (%2 here, %3 on Grimmory): it may have been replaced with another edition.\n\nDownload it again? Your place in the book comes back from Grimmory."),
                entry.title or name or key, mb(size), mb(kb * 1024))),
            ok_text = _("Download again"),
            cancel_text = _("Keep this one"),
            ok_callback = function()
                plugin.store.newcopy_asked[key] = kb
                plugin:save()
                NewCopy.replace(plugin, ui, book_id, entry, info, name)
            end,
            cancel_callback = function()
                plugin.store.newcopy_asked[key] = kb
                plugin:save()
            end,
        })
    end)
end

--- The settings of how the old copy was shown, forgotten: the new one is looked at afresh.
NewCopy.FORGET = { "gzreader_picture_book", "gzreader_pb_check", "gzreader_pb_fit", "gzreader_pb_wide", "gzreader_pb_vh",
    "gzreader_pb_layers", "gzreader_pb_margins", "gzreader_pb_smooth" }
function NewCopy.forget(ds)
    local css = ds:readSetting("book_style_tweak")
    if type(css) == "string" and css:find("/* GZreader picture book: begin */", 1, true) then
        local a = css:find("/* GZreader picture book: begin */", 1, true)
        local b = css:find("/* GZreader picture book: end */", 1, true)
        local rest = b and (css:sub(1, a - 1) .. css:sub(b + #"/* GZreader picture book: end */")) or css:sub(1, a - 1)
        rest = rest:gsub("^%s+", ""):gsub("%s+$", "")
        if rest == "" then
            ds:delSetting("book_style_tweak")
            ds:delSetting("book_style_tweak_enabled")
        else
            ds:saveSetting("book_style_tweak", rest)
        end
    end
    local old = ds:readSetting("gzreader_pb_margins")
    if type(old) == "table" then
        ds:saveSetting("copt_h_page_margins", { old[1] or 15, old[3] or 15 })
        ds:saveSetting("copt_t_page_margin", old[2] or 15)
        ds:saveSetting("copt_b_page_margin", old[4] or 15)
    end
    for _i, k in ipairs(NewCopy.FORGET) do ds:delSetting(k) end
end

--- Close the book, download Grimmory's copy over it, open it again.
function NewCopy.replace(plugin, ui, book_id, entry, info, name)
    local path = entry.path
    local book = { id = book_id, title = entry.title or info[4], primaryFileId = info[2], primaryFileType = info[3],
        primaryFileName = name, fileSizeKb = info[5] }
    local UIManager = require("ui/uimanager")
    if ui.onClose then ui:onClose() end
    UIManager:nextTick(function()
        require("gzreader_download").start(plugin, book, path, function(ok, err)
            if not ok then
                if err ~= "cancelled" then plugin:showError(err) end
                return
            end
            local okd, DocSettings = pcall(require, "docsettings")
            if okd then
                local ds = DocSettings:open(path)
                NewCopy.forget(ds)
                ds:flush()
            end
            Log.info("book", tostring(book_id), "downloaded again: Grimmory's copy")
            require("apps/reader/readerui"):showReader(path)
        end)
    end)
end

return NewCopy
