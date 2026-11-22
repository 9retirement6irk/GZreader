-- BookOrbit audiobooks (tests/mock_bookorbit.py on 127.0.0.1:18096): sign in, enter the
-- API key, list the audiobooks, download one of two files through the player's own
-- download, and send and read back where it was left. (The mock's audio isn't real
-- audio: nothing is played.) Prints what each step found.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local KEY = "bok_" .. string.rep("a1B2c3D4e5", 4) .. "f6G7h8I9j"
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
    local ok, err = p:connect("http://127.0.0.1:18096", "will-kindle", "hunter22", "bookorbit")
    local none = p.api:listBooks{ page = 0, size = 20, fileType = { "AUDIOBOOK" } }
    local k_ok, k_err = p:setBookOrbitApiKey(KEY)
    local list = p.api:listBooks{ page = 0, size = 20, sort = "title", dir = "asc", fileType = { "AUDIOBOOK" } }
    local names = {}
    for _i, b in ipairs(list and list.content or {}) do names[#names + 1] = b.id .. "=" .. b.title end
    E.say("sign-in:", tostring(ok), tostring(err), "| audiobooks before the key:", tostring(none and #none.content), "| key:", tostring(k_ok), tostring(k_err),
        "| after:", table.concat(names, ", "))
    state.summary = list and list.content[1]
    require("gzreader_audiobook").download(p, state.summary, function(book, derr)
        state.book, state.err = book, derr
    end)
end, after = 25 })
add({ fn = function(E)
    local lfs = require("libs/libkoreader-lfs")
    local b = state.book
    local files = {}
    for _i, t in ipairs(b and b.tracks or {}) do files[#files + 1] = t.file .. ":" .. tostring(lfs.attributes(b.dir .. "/" .. t.file, "size")) end
    E.say("downloaded:", tostring(b ~= nil), tostring(state.err), "| id", tostring(b and b.id), "| files:", table.concat(files, ", "),
        "| chapters:", tostring(b and #b.chapters), "| file id:", tostring(b and b.file_id))
    local p = plugin()
    p:queue("progress", b.id, { fileProgress = { bookFileId = b.file_id, positionData = "12000", positionHref = "1", progressPercent = 68.5 } })
    p:flushPending()
end, after = 10 })
add({ fn = function(E)
    local p = plugin()
    local rec = p.api:getBook(state.book.id)
    local ap = rec and rec.audiobookProgress
    E.say("the place sent and read back: track", tostring(ap and ap.trackIndex), "ms", tostring(ap and ap.positionMs), "| still queued:", tostring(p.store.pending.progress[state.book.id] ~= nil))
    local log = io.open(require("datastorage"):getDataDir() .. "/gzreader.log", "rb")
    local text = log and log:read("*a") or ""
    if log then log:close() end
    E.say("log has the API key:", tostring(text:find(KEY, 1, true) ~= nil), "| part of it:", tostring(text:find("a1B2c3D4", 1, true) ~= nil))
end, after = 2 })
return s
