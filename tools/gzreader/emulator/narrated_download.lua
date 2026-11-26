-- A narrated BookOrbit book (tests/mock_bookorbit.py on 127.0.0.1:18096, its
-- book 104): its page has With narration / Book only over Download, with the
-- sizes; then the same book on the Kindle without narration, and its hold
-- menu's Download with narration replacing that copy.
--   python3 -I tools/gzreader/tests/mock_bookorbit.py 18096 &
--   GZ_EMU_MODEL=scribe GZ_EMU_TREE=<tree>/koreader run.sh narrated_download.lua <out>
-- Checks go to <out>/narrated-download-checks.txt.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
local function UIM() return require("ui/uimanager") end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function top(name)
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if name == nil or w.name == name then return w end
    end
end
local page, copy, copy_size
add({ fn = function()
    for i = #UIM()._window_stack, 1, -1 do
        local w = UIM()._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIM():close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    E.say("sign-in:", tostring(ok), tostring(err))
    local t = top(); if t and t.text then UIM():close(t) end
    page = require("gzreader_bookpage").show({ api = p.api, plugin = p }, { id = 104, title = "Night Trains", authors = { "Example Author" },
        primaryFileType = "epub" })
end, after = 8 })
add({ shot = "narrdl-1-page" })
add({ fn = function(E)
    check(page and page.narr and page.narr.has, "the book page: BookOrbit says it has narration")
    local labels = {}
    for _i, c in ipairs(require("gzreader_narratedopen").pageChoices(page.narr)) do labels[#labels + 1] = c.label end
    check(#labels == 2 and labels[1]:find("With narration", 1, true) and labels[1]:find("MB", 1, true) and labels[2]:find("Book only", 1, true),
        "…With narration (its size) and Book only over Download: " .. table.concat(labels, " | "))
    E.tap("Book only (smaller)")
end, after = 2 })
add({ shot = "narrdl-2-book-only" })
add({ fn = function()
    check(page.variant == "audioless_epub", "Book only chosen")
    page:download(false)
end, after = 1 })
add({ wait_for = function()
    local e = plugin().store.downloads["104"]
    return e and require("libs/libkoreader-lfs").attributes(e.path, "mode") == "file" and not require("gzreader_download").active
end, timeout = 40 })
add({ fn = function()
    local e = plugin().store.downloads["104"]
    copy = e and e.path
    local N = require("gzreader_narration")
    local function last() local h = io.popen("curl -s http://127.0.0.1:18096/_mock/state"); local t = h:read("*a"); h:close(); return t end
    check(copy and N.quickCheck(copy) ~= true and last():find('"last_download_variant": "audioless_epub"', 1, true),
        "downloaded without its narration")
    copy_size = require("libs/libkoreader-lfs").attributes(copy, "size")
    require("gzreader_homemenu").manageBook(plugin(), { path = copy })
end, after = 3 })
add({ shot = "narrdl-3-hold" })
add({ fn = function()
    local d = top()
    local row
    for _i, r in ipairs(d and d.buttons or {}) do if r[1] and r[1].text == "Download with narration" then row = r[1] end end
    check(row ~= nil, "its hold menu: Download with narration")
    if row then row.callback() end
end, after = 5 })
add({ shot = "narrdl-4-ask" })
add({ fn = function()
    local box = top()
    check(box and box.ok_callback and tostring(box.text):find("with its narration", 1, true), "asked first, with the size")
    if box and box.ok_callback then box.ok_callback(); UIM():close(box) end
end, after = 1 })
add({ wait_for = function()
    return not require("gzreader_download").active and (require("libs/libkoreader-lfs").attributes(copy, "size") or 0) > (copy_size or 0)
end, timeout = 40 })
add({ fn = function(E)
    local e = plugin().store.downloads["104"]
    local h = io.popen("curl -s http://127.0.0.1:18096/_mock/state"); local st = h:read("*a"); h:close()
    check(e and e.path == copy and st:find('"last_download_variant": "original"', 1, true)
        and require("libs/libkoreader-lfs").attributes(copy, "size") > copy_size,
        "the narrated copy (the bigger one) in the same file's place")
    local f = io.open(E.out .. "/narrated-download-checks.txt", "w")
    f:write(table.concat(lines, "\n") .. "\n")
    f:close()
end, after = 2 })
return s
