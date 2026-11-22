-- BookOrbit reading time, end to end (tests/mock_bookorbit.py on 127.0.0.1:18096;
-- GZ_EMU_BOOK = a real EPUB): pages are read in a real book, KOReader's statistics
-- plugin writes them to its database, and after the book closes GZreader reads that
-- database (the real SQLite) and sends the rows to BookOrbit. Prints what each step found.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local BO = "http://127.0.0.1:18096"
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local function http(method, path, body)
    local ltn12, json = require("ltn12"), require("gzreader_json")
    local out = {}
    local src = body and json.encode(body) or nil
    local h = {}
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
    state.path = p.store.library_dir .. "/A real book.epub"
    local i, o = io.open(os.getenv("GZ_EMU_BOOK"), "rb"), io.open(state.path, "wb")
    o:write(i:read("*a")); i:close(); o:close()
    state.hash = require("gzreader_bookorbit").hashFile(state.path)
    http("POST", "/_mock/set", { book_hashes = { ["101"] = state.hash } })
    local ok, err = p:connect(BO, "will-kindle", "hunter22", "bookorbit")
    E.say("sign-in:", tostring(ok), tostring(err), "| reading time synced:", tostring(p:serverCan("stats")))
    p:matchLibraryFiles()
end, after = 10 })
add({ fn = function() require("apps/reader/readerui"):showReader(state.path) end, after = 16 })
for page = 2, 6 do
    add({ fn = function() require("apps/reader/readerui").instance:handleEvent(require("ui/event"):new("GotoPage", page)) end, after = 7 })
end
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    E.say("read five pages; statistics plugin on:", tostring(R.statistics ~= nil and R.statistics.settings and R.statistics.settings.is_enabled))
    R:onHome()
end, after = 16 })
add({ fn = function(E)
    local _, st = http("GET", "/_mock/state")
    local rows = st and st.page_stats and st.page_stats[state.hash] or {}
    local first = rows[1] or {}
    E.say("BookOrbit has page rows:", #rows, "| first: page", tostring(first[1]), "seconds", tostring(first[3]), "of", tostring(first[4]), "pages",
        "| remembered up to:", tostring((plugin().store.bookorbit_stats or {})[state.hash] ~= nil))
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    for line in text:gmatch("[^\n]+") do
        if line:find("BookOrbit reading time", 1, true) then E.say("log:", line:sub(1, 160)) end
    end
end })
return s
