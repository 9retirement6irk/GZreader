-- BookOrbit reading progress, end to end (tests/mock_bookorbit.py on 127.0.0.1:18096;
-- GZ_EMU_BOOK = a real EPUB). The EPUB is put in the books folder as if it came from
-- another server; BookOrbit is told it has that file (by fingerprint); then: sign in,
-- the book is matched, opened, a place is sent, and a later place from "another
-- device" is jumped to. Prints what each step found.
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
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    local Event = require("ui/event")
    R:handleEvent(Event:new("GotoPage", 7))
    state.far = { xp = R.document:getPageXPointer(15), pages = R.document:getPageCount() }
    E.say("open; sync running:", tostring(rplugin() and rplugin().sync ~= nil), "| pages:", tostring(state.far.pages))
end, after = 3 })
add({ fn = function() rplugin().sync:push(true) end, after = 8 })
add({ fn = function(E)
    local _, st = http("GET", "/_mock/state")
    local sent = st and st.progress[state.hash]
    local R = require("apps/reader/readerui").instance
    local last = R.rolling:getLastPercent()
    E.say("BookOrbit has:", tostring(sent and sent.percentage), "| KOReader's own percentage:", tostring(last),
        "| place is an XPointer:", tostring(sent and tostring(sent.progress):sub(1, 18)), "| device:", tostring(sent and sent.device))
    -- another device reads on: page 15
    local md5 = require("ffi/sha2").md5
    local code = http("PUT", "/api/v1/koreader/syncs/progress", { document = state.hash, percentage = 15 / state.far.pages, progress = state.far.xp,
        device = "Another reader", device_id = "other-1" }, { ["x-auth-user"] = "will-kindle", ["x-auth-key"] = md5("hunter22") })
    E.say("another device sent page 15:", tostring(code))
    rplugin().sync:pull(true)
end, after = 10 })
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    E.say("after the pull, this Kindle is on page:", tostring(R.rolling.current_page))
end, after = 1 })
add({ shot = "bookorbit-progress-jumped" })
add({ fn = function(E)
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    for line in text:gmatch("[^\n]+") do
        if line:find("sync pull book", 1, true) or line:find("BookOrbit: matched", 1, true) then E.say("log:", line:sub(1, 200)) end
    end
    require("apps/reader/readerui").instance:onHome()
end, after = 4 })
return s
