-- BookOrbit page bookmarks, end to end (tests/mock_bookorbit.py on 127.0.0.1:18096;
-- GZ_EMU_BOOK = a real EPUB): a page dog-eared here reaches BookOrbit; a bookmark made
-- "elsewhere" dog-ears its page here; removing one here removes it there.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local BO = "http://127.0.0.1:18096"
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function rplugin() local R = require("apps/reader/readerui").instance; return R and R.gzreader end
local function http(method, path, body, headers)
    local ltn12, json = require("ltn12"), require("gzreader_json")
    local out = {}
    local src = body and json.encode(body) or nil
    local h = headers or {}
    if src then h["Content-Type"] = "application/json"; h["Content-Length"] = #src end
    local _, code = require("socket.http").request{ url = BO .. path, method = method, headers = h,
        source = src and ltn12.source.string(src) or nil, sink = ltn12.sink.table(out) }
    local ok, data = pcall(json.decode, table.concat(out))
    return code, ok and data or nil
end
local state = {}
add({ fn = function()
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
end, after = 6 })
add({ fn = function(E)
    local p = plugin()
    local src = os.getenv("GZ_EMU_BOOK")
    state.path = p.store.library_dir .. "/Named by another server.epub"
    local i, o = io.open(src, "rb"), io.open(state.path, "wb")
    o:write(i:read("*a")); i:close(); o:close()
    local BookOrbit = require("gzreader_bookorbit")
    state.hash = BookOrbit.hashFile(state.path)
    E.say("fingerprint:", tostring(state.hash ~= nil), "| the same as KOReader's own:", tostring(state.hash == require("util").partialMD5(state.path)),
        "| file bytes:", tostring(require("libs/libkoreader-lfs").attributes(state.path, "size")))
    http("POST", "/_mock/set", { book_hashes = { ["101"] = state.hash } })
    local ok, err = p:connect(BO, "will-kindle", "hunter22", "bookorbit")
    E.say("sign-in:", tostring(ok), tostring(err), "| progress synced:", tostring(p:serverCan("progress")))
    p:matchLibraryFiles()
end, after = 10 })
add({ fn = function(E)
    local e = plugin().store.downloads["101"]
    E.say("matched to BookOrbit's book 101:", tostring(e ~= nil), "| path:", tostring(e and e.path:match("[^/]+$")), "| file id:", tostring(e and e.file_id))
    require("apps/reader/readerui"):showReader(state.path)
end, after = 18 })
local function marks()
    local n, list = 0, {}
    for _i, a in ipairs(require("apps/reader/readerui").instance.annotation.annotations) do
        if not a.drawer and not a.pos0 then n = n + 1; list[#list + 1] = tostring(a.pageno) .. ":" .. tostring(a.text):sub(1, 24) end
    end
    return n, table.concat(list, " | ")
end
local function server()
    local _, st = http("GET", "/_mock/state")
    return st and st.bookmarks and st.bookmarks["101"] or {}
end
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    R:handleEvent(require("ui/event"):new("GotoPage", 5))
    R.bookmark:onToggleBookmark()
    state.there = R.document:getPageXPointer(9)
    E.say("page 5 dog-eared here; bookmarks in the book:", (marks()), "| module on:", tostring(rplugin().bookmarks:enabled()))
end, after = 12 })
add({ fn = function(E)
    local sv = server()
    E.say("BookOrbit has:", #sv, "| place is an XPointer:", tostring(sv[1] and sv[1].pos:sub(1, 18)))
    http("POST", "/_mock/set", { web_bookmark = { book = 101, op = "add", pos = state.there, pageno = 9, title = "From another device" } })
    rplugin().bookmarks:reconcile()
end, after = 10 })
add({ fn = function(E)
    local n, list = marks()
    E.say("after a bookmark made elsewhere:", n, "|", list)
    require("apps/reader/readerui").instance:handleEvent(require("ui/event"):new("GotoPage", 9))
end, after = 3 })
add({ shot = "bookorbit-bookmark-from-elsewhere" })
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    R.bookmark:onToggleBookmark() -- (page 9: off again)
    E.say("page 9's dog-ear removed here; bookmarks in the book:", (marks()))
end, after = 12 })
add({ fn = function(E)
    local live, gone = 0, 0
    for _i, m in ipairs(server()) do if m.deleted then gone = gone + 1 else live = live + 1 end end
    E.say("BookOrbit after the removal: live", live, "deleted", gone)
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    for line in text:gmatch("[^\n]+") do
        if line:find("BookOrbit bookmark", 1, true) then E.say("log:", line:sub(1, 200)) end
    end
    require("apps/reader/readerui").instance:onHome()
end, after = 4 })
return s
