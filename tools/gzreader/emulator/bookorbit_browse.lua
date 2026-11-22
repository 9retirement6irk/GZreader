-- BookOrbit as the book server (tests/mock_bookorbit.py on 127.0.0.1:18096):
-- sign in with the KOReader sync user, then the Catalog's first page, the
-- libraries, All books and the menu's first line. Prints what each step found.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function browser() return require("gzreader_browser").current end
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "wrong", "bookorbit")
    E.say("wrong password:", tostring(ok), tostring(err))
    ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    E.say("sign-in:", tostring(ok), tostring(err), "backend", p:backend(), "books only", tostring(p:booksOnly()),
        "server", tostring((p.store.bookorbit or {}).server_version))
    p:announceConnected()
end, after = 2 })
add({ shot = "bookorbit-1-connected" })
add({ fn = function()
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    if top and top.text then UIManager:close(top) end
    plugin():onShowGrimmoryLibrary()
end, after = 12 })
add({ shot = "bookorbit-2-catalog" })
add({ fn = function() browser():openLibraries() end, after = 8 })
add({ fn = function(E)
    local m = browser().menu
    local names = {}
    for _i, it in ipairs(m and m.item_table or {}) do names[#names + 1] = tostring(it.text) .. "=" .. tostring(it.mandatory or it.gz_count) end
    E.say("libraries:", table.concat(names, ", "))
end })
add({ shot = "bookorbit-3-libraries" })
add({ fn = function() browser():openPaged("All books", { sort = "title", dir = "asc" }) end, after = 12 })
add({ fn = function(E)
    local m = browser().menu
    local names = {}
    for _i, it in ipairs(m and m.item_table or {}) do names[#names + 1] = tostring(it.text) end
    E.say("all books:", #names, table.concat(names, " | "))
end })
add({ shot = "bookorbit-4-all-books" })
-- a download through the plugin (quietly, as the shelf's auto-download does), then that auto-download
add({ fn = function()
    require("gzreader_download").background = true
    plugin():downloadAndOpen({ id = 101, title = "The Long Way Round", authors = { "Ada Marsh" }, primaryFileType = "EPUB",
        primaryFileName = "The Long Way Round.epub" }, nil)
end, after = 20 })
add({ fn = function(E)
    local e = plugin().store.downloads["101"]
    local lfs = require("libs/libkoreader-lfs")
    E.say("downloaded 101:", tostring(e and e.path and e.path:match("[^/]+$")), "bytes", tostring(e and lfs.attributes(e.path, "size")),
        "file id", tostring(e and e.file_id))
    local SS = require("gzreader_shelfsync")
    SS.set(plugin(), { id = 11, name = "Beach reads" })
    SS.run(plugin(), true)
end, after = 25 })
add({ fn = function(E)
    local got = {}
    for id, e in pairs(plugin().store.downloads) do got[#got + 1] = id .. "=" .. tostring(e.path and e.path:match("[^/]+$")) end
    table.sort(got)
    E.say("after the shelf's auto-download:", table.concat(got, ", "))
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    if top and top.text then UIManager:close(top) end
    require("apps/filemanager/filemanager").instance.gzreader:onShowGrimmoryLibrary()
end, after = 8 })
add({ shot = "bookorbit-5-after-downloads" })
add({ fn = function(E)
    local p = plugin()
    E.say("menu:", p:menuItems()[1].text_func(), "| sync:", tostring(p:syncEnabled()), "| covers:", require("gzreader_covers").dir():match("[^/]+$"))
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    E.say("log has the password:", tostring(text:find("hunter22", 1, true) ~= nil), "its MD5:",
        tostring(text:find(require("ffi/sha2").md5("hunter22"), 1, true) ~= nil), "x-auth-key:", tostring(text:find("x-auth-key", 1, true) ~= nil))
end })
return s
