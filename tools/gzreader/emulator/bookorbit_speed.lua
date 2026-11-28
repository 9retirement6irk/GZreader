-- Is a Kindle as quick signed in to BookOrbit as signed in to nothing? (tests/mock_bookorbit.py
-- on 127.0.0.1:18096; GZ_EMU_BOOK = a real EPUB.) The same book is opened, read for 20
-- page turns and closed twice: before signing in, and signed in to BookOrbit with the
-- book matched (so progress, highlights, bookmarks and reading time all sync). Prints each
-- phase's CPU time in this process, the background jobs started, and which of GZreader's
-- modules were loaded by the end.
local s = { start = 16 }
local function add(t) s[#s + 1] = t end
local BO = "http://127.0.0.1:18096"
local function plugin() return require("apps/filemanager/filemanager").instance.gzreader end
local state = { jobs = {} }
local function cpu(E) return os.clock() - E.clock0 end

local function round(name)
    add({ fn = function(E)
        state.c0, state.n0 = cpu(E), #state.jobs
        require("apps/reader/readerui"):showReader(state.path)
    end, after = 1 })
    add({ wait_for = function()
        local ui = require("apps/reader/readerui").instance
        return ui and ui.document and ui.document:getCurrentPage() ~= nil
    end, timeout = 90, after = 10 })
    add({ fn = function(E) state.open = cpu(E) - state.c0; state.c0 = cpu(E) end, after = 0.2 })
    for _i = 1, 20 do
        add({ fn = function(E)
            if not pcall(E.key, "RPgFwd") then
                local Screen = require("device").screen
                E.tap({ Screen:getWidth() * 0.9, Screen:getHeight() / 2 })
            end
        end, after = 2 })
    end
    add({ fn = function(E) state.turns = cpu(E) - state.c0; state.c0 = cpu(E) end, after = 0.2 })
    add({ fn = function(E)
        if not pcall(E.key, "Home") then require("ui/uimanager"):sendEvent(require("ui/event"):new("Home")) end
    end, after = 12 })
    add({ fn = function(E)
        local tags = {}
        for i = state.n0 + 1, #state.jobs do tags[#tags + 1] = state.jobs[i] end
        E.say(string.format("SPEED %s: open %.2f s, 20 page turns %.2f s, close %.2f s CPU | background jobs: %d (%s)",
            name, state.open, state.turns, cpu(E) - state.c0, #tags, table.concat(tags, ", ")))
    end, after = 1 })
end

add({ fn = function(E)
    local UIManager = require("ui/uimanager")
    for i = #UIManager._window_stack, 1, -1 do
        local w = UIManager._window_stack[i].widget
        if w.name == "setup guide" or w.name == "QR code screen" then UIManager:close(w) end
    end
    local p = plugin()
    state.path = p.store.library_dir .. "/Speed test.epub"
    local i, o = io.open(os.getenv("GZ_EMU_BOOK"), "rb"), io.open(state.path, "wb")
    o:write(i:read("*a")); i:close(); o:close()
    -- count what's handed to the background
    local Async = require("gzreader_async")
    local run = Async.run
    Async.run = function(api, fn, cb, tag, ...)
        state.jobs[#state.jobs + 1] = tostring(tag or "?")
        return run(api, fn, cb, tag, ...)
    end
    -- every request, from this process and the background ones (they inherit this), to a file
    local Api = require("gzreader_api")
    local raw = Api.rawRequest
    state.reqs = require("datastorage"):getDataDir() .. "/speed-requests.txt"
    os.remove(state.reqs)
    Api.rawRequest = function(method, url, ...)
        local f = io.open(state.reqs, "a")
        if f then f:write(method, " ", (tostring(url):gsub("^https?://[^/]+", ""):gsub("%?.*$", ""):gsub("%x%x%x%x%x%x%x%x%x%x+", "<hash>"):gsub("%d+", "N")), "\n"); f:close() end
        return raw(method, url, ...)
    end
    local before = {}
    for k in pairs(package.loaded) do if tostring(k):match("^gzreader_") then before[k] = true end end
    state.before = before
    E.say("ready")
end, after = 6 })
round("signed in to nothing")
round("signed in to nothing, again")
add({ fn = function(E)
    local p = plugin()
    local hash = require("gzreader_bookorbit").hashFile(state.path)
    require("gzreader_api").rawRequest("POST", BO .. "/_mock/set", { body = { book_hashes = { ["101"] = hash } } })
    local ok, err = p:connect(BO, "will-kindle", "hunter22", "bookorbit")
    local UIManager = require("ui/uimanager")
    local top = UIManager._window_stack[#UIManager._window_stack].widget
    if top and top.text then UIManager:close(top) end
    p:matchLibraryFiles()
    E.say("sign-in:", tostring(ok), tostring(err))
end, after = 12 })
add({ fn = function(E)
    E.say("matched:", tostring(plugin().store.downloads["101"] ~= nil))
end, after = 1 })
round("BookOrbit")
round("BookOrbit, again")
add({ fn = function(E)
    local new, all = {}, 0
    for k in pairs(package.loaded) do
        if tostring(k):match("^gzreader_") then
            all = all + 1
            if not state.before[k] then new[#new + 1] = k end
        end
    end
    table.sort(new)
    E.say("GZreader modules loaded:", all, "| loaded since signing in:", table.concat(new, " "))
    local grim = {}
    for _i, k in ipairs{ "gzreader_bookmarks", "gzreader_annotations", "gzreader_cfi", "gzreader_copy", "gzreader_sso", "gzreader_sessions" } do
        grim[#grim + 1] = k .. "=" .. tostring(package.loaded[k] ~= nil)
    end
    E.say("Grimmory-only modules loaded:", table.concat(grim, " "))
    local counts, order = {}, {}
    local f = io.open(state.reqs, "r")
    for line in (f and f:lines() or function() end) do
        if not counts[line] then order[#order + 1] = line end
        counts[line] = (counts[line] or 0) + 1
    end
    if f then f:close() end
    for i, line in ipairs(order) do order[i] = counts[line] .. "x " .. line end
    E.say("requests made (" .. #order .. " kinds):", table.concat(order, " | "))
    collectgarbage(); collectgarbage()
    E.say(string.format("Lua memory: %.1f MB", collectgarbage("count") / 1024))
end, after = 1 })
return s
