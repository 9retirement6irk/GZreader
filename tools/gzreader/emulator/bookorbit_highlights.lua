-- BookOrbit highlights, end to end (tests/mock_bookorbit.py on 127.0.0.1:18096;
-- GZ_EMU_BOOK = a real EPUB): the book is matched and opened; a highlight with a note
-- made here reaches BookOrbit; one made "on the web" appears in the book; a note added
-- on the web arrives; a highlight removed here is removed there. Prints what each step found.
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
local function annos() return require("apps/reader/readerui").instance.annotation.annotations end
local function server()
    local _, st = http("GET", "/_mock/state")
    return st and st.annotations and st.annotations["101"] or {}
end
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    local doc = R.document
    state.a, state.b, state.c = doc:getPageXPointer(3), doc:getPageXPointer(4), doc:getPageXPointer(6)
    local item = { datetime = os.date("%Y-%m-%d %H:%M:%S"), drawer = "lighten", color = "yellow", text = "made on the Kindle", note = "a note from the Kindle",
        page = state.a, pos0 = state.a, pos1 = state.b, chapter = "One", pageno = 3 }
    R.annotation:addItem(item)
    R:handleEvent(require("ui/event"):new("AnnotationsModified", { item, nb_highlights_added = 1 }))
    E.say("a highlight made here; highlights in the book:", #annos(), "| module:", tostring(rplugin().annotations and rplugin().annotations.enabled and rplugin().annotations:enabled()))
end, after = 12 })
add({ fn = function(E)
    local sv = server()
    E.say("BookOrbit has:", #sv, "|", tostring(sv[1] and sv[1].text), "| note:", tostring(sv[1] and sv[1].note), "| style:", tostring(sv[1] and sv[1].drawer))
    state.first = sv[1] and sv[1].serverId
    local code, web = http("POST", "/_mock/set", { web_highlight = { book = 101, op = "add", pos0 = state.c, pos1 = state.c, text = "made on the web", color = "blue",
        datetime = "2026-11-22 10:00:00" } })
    http("POST", "/_mock/set", { web_highlight = { book = 101, op = "edit", serverId = state.first, note = "changed on the web" } })
    state.web = web and web.serverId
    E.say("the web added one and changed the first one's note:", tostring(code))
    rplugin().annotations:run()
end, after = 12 })
add({ fn = function(E)
    local out = {}
    for _i, a in ipairs(annos()) do out[#out + 1] = tostring(a.text) .. " / " .. tostring(a.note) .. " / " .. tostring(a.color) end
    E.say("in the book now:", #annos(), "|", table.concat(out, " | "))
    require("apps/reader/readerui").instance:handleEvent(require("ui/event"):new("GotoPage", 6))
end, after = 3 })
add({ shot = "bookorbit-highlight-from-web" })
add({ fn = function(E)
    local R = require("apps/reader/readerui").instance
    local list = annos()
    local gone
    for i, a in ipairs(list) do if a.text == "made on the Kindle" then gone = table.remove(list, i) break end end
    R:handleEvent(require("ui/event"):new("AnnotationsModified", { gone, nb_highlights_added = -1 }))
    E.say("removed here:", tostring(gone ~= nil))
end, after = 12 })
add({ fn = function(E)
    local n_deleted, n_live = 0, 0
    for _i, a in ipairs(server()) do if a.deleted then n_deleted = n_deleted + 1 else n_live = n_live + 1 end end
    E.say("BookOrbit after the removal: live", n_live, "deleted", n_deleted)
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    for line in text:gmatch("[^\n]+") do
        if line:find("BookOrbit highlight", 1, true) then E.say("log:", line:sub(1, 200)) end
    end
    require("apps/reader/readerui").instance:onHome()
end, after = 4 })
return s
