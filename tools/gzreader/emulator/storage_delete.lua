-- Settings → General → Storage: a book and an album tapped in their lists
-- are deleted from the Kindle (asked first, with their size); the page
-- shows them gone.
--   GZ_EMU_MODEL=pw3 GZ_EMU_TREE=<tree>/koreader run.sh storage_delete.lua <out>
-- Checks go to <out>/storage-delete-checks.txt.
local s = { start = 14 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function zen() return require("apps/filemanager/filemanager").instance.zenos end
local lfs = require("libs/libkoreader-lfs")
local lib, music
local function put(path, bytes)
    os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
    local f = io.open(path, "wb"); f:write(string.rep("x", bytes)); f:close()
end
local function open(path)
    local Page = require("modules/settings/zen_settings_page")
    pcall(Page.closeActive)
    local p = {}
    for _i, t in ipairs(path) do p[#p + 1] = { key = "text", value = t } end
    Page.show(zen(), { path = p })
end
local function top(field, value)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w[field] ~= nil and (value == nil or tostring(w[field]):find(value, 1, true)) then return w end
    end
end
local function row(name)
    local St = require("gzreader_storage")
    for _i, part in ipairs(St.items(St.last or {})) do
        for _j, r in ipairs(part.sub_item_table or {}) do if r.text == name then return r end end
    end
end

add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
    lib = plugin():libraryDir()
    put(lib .. "/Storage Test Book.epub", 3 * 1024 * 1024)
    music = require("gzreader_music").root(plugin()) .. "/album-test"
    put(music .. "/01.mp3", 2 * 1024 * 1024)
    local f = io.open(music .. "/music.json", "w")
    f:write('{"kind":"album","key":"test","title":"Storage Test Album","artist":"Example Band","tracks":[]}')
    f:close()
end, after = 2 })
add({ fn = function() open({ "General", "Storage" }) end, after = 8 })
add({ fn = function() open({ "General", "Storage", "Books" }) end, after = 6 })
add({ shot = "storage-1-books" })
add({ fn = function()
    local r = row("Storage Test Book")
    check(r ~= nil and r.callback ~= nil and r.mandatory == "3.0 MB", "Storage → Books: the book listed with its size, tappable")
    if r then r.callback() end
end, after = 3 })
add({ shot = "storage-2-ask" })
add({ fn = function()
    local box = top("ok_callback")
    check(box ~= nil and tostring(box.text):find("Storage Test Book", 1, true) ~= nil, "a tap: asked first")
    if box then box.ok_callback(); UIM():close(box) end
end, after = 4 })
add({ fn = function()
    check(lfs.attributes(lib .. "/Storage Test Book.epub", "mode") == nil, "Delete: the book's file gone")
    check(row("Storage Test Book") == nil, "…and gone from the page")
    open({ "General", "Storage", "Music" })
end, after = 6 })
add({ fn = function()
    local r = row("Storage Test Album · Example Band")
    check(r ~= nil and r.callback ~= nil, "Storage → Music: the album listed, tappable")
    if r then r.callback() end
end, after = 3 })
add({ shot = "storage-3-album" })
add({ fn = function(E)
    local box = top("ok_callback")
    check(box ~= nil and tostring(box.text):find("2.0 MB", 1, true) ~= nil, "a tap: asked first, with its size")
    if box then box.ok_callback(); UIM():close(box) end
end, after = 4 })
add({ fn = function(E)
    check(lfs.attributes(music, "mode") == nil, "Delete: the album's folder gone")
    local f = io.open(E.out .. "/storage-delete-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 1 })
return s
