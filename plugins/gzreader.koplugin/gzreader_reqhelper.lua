--[[--
A long-lived request helper (experimental, off unless a file named
gz-request-helper is in the koreader folder).

Background requests run in forked processes (gzreader_async.lua); each keeps
its connections only while it lives (gzreader_api.lua's pool), so browsing the
Grimmory tab, one request every few seconds, still paid a TLS handshake for
each (most of a request's 0.3–3.5 s on a Kindle 3). While Wi-Fi is on, this
small separate LuaJIT process (like the remote-debugging watchdog) keeps the
connections to your servers open between those processes: they send their
requests to it on 127.0.0.1, as to an HTTP proxy, and it sends them on over
its kept connections. Replies come back as they are (still gzip-compressed).

- It listens only on 127.0.0.1, and only answers requests with its token
  (a random one, in <cache>/gz-reqhelper/endpoint, next to its port).
- If it isn't there or doesn't answer, a request goes directly, as before
  (a POST only when the helper couldn't be reached at all: never twice).
- It ends when Wi-Fi goes off (GZreader asks it), when GZreader is gone, or
  after IDLE_EXIT seconds without a request.

Run as: luajit gzreader_reqhelper.lua <dir> <GZreader's pid>
]]

local modname = ...
local H = { IDLE_EXIT = 300, KEEP_IDLE = 20, FLAG = "gz-request-helper" }

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function alive(pid) return pid and readFile("/proc/" .. tostring(pid) .. "/stat") ~= nil end

---------------------------------------------------------------- the helper itself

local function serve(dir, ppid)
    if not os.getenv("GZ_HELPER_NO_KOENV") then pcall(require, "setupkoenv") end
    local here = (arg and arg[0] or ""):match("^(.*)/[^/]+$")
    if here then package.path = here .. "/?.lua;" .. package.path end
    -- (outside KOReader, e.g. the tests: plain LuaFileSystem, a quiet logger)
    if not pcall(require, "libs/libkoreader-lfs") then package.preload["libs/libkoreader-lfs"] = function() return require("lfs") end end
    if not pcall(require, "json") and pcall(require, "dkjson") then package.preload["json"] = function() return require("dkjson") end end
    if not pcall(require, "logger") then
        package.preload["logger"] = function() local n = function() end; return { info = n, warn = n, err = n, dbg = n } end
    end
    local socket = require("socket")
    -- (GZreader's request code without KOReader's UI: socketutil, gzreader_net
    -- and gzreader_clock would load the device, the screen and the input)
    package.preload["socketutil"] = function()
        local http, ltn12 = require("socket.http"), require("ltn12")
        local S = { LARGE_BLOCK_TIMEOUT = 10, LARGE_TOTAL_TIMEOUT = 30 }
        function S.table_sink(t) return ltn12.sink.table(t) end
        function S.set_timeout(_s, block) http.TIMEOUT = block end
        function S.reset_timeout() http.TIMEOUT = 60 end
        return S
    end
    package.loaded["gzreader_net"] = { touch = function() end }
    package.loaded["gzreader_clock"] = { fromServer = function() end }
    package.loaded["gzreader_reqhelper"] = { endpoint = function() return nil end } -- (not through itself)
    local Api = require("gzreader_api")
    Api.poolBegin()
    Api.pool.IDLE_MAX = H.KEEP_IDLE
    local srv = assert(socket.bind("127.0.0.1", 0))
    srv:settimeout(1)
    local port = select(2, srv:getsockname())
    local f = io.open("/dev/urandom", "rb")
    local rnd = f and f:read(16) or tostring(os.time()) .. tostring(math.random())
    if f then f:close() end
    local token = rnd:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)
    local mypid = tonumber((readFile("/proc/self/stat") or ""):match("^(%d+)"))
    local tmp = io.open(dir .. "/endpoint.tmp", "wb")
    tmp:write(string.format("%d %s %d\n", port, token, mypid or 0))
    tmp:close()
    os.rename(dir .. "/endpoint.tmp", dir .. "/endpoint")
    local last = socket.gettime()
    local HOP = { connection = true, ["proxy-connection"] = true, ["keep-alive"] = true, te = true, host = true,
        ["x-gz-helper"] = true, ["transfer-encoding"] = true, ["content-length"] = true }
    local function reply(c, code, headers, body, err)
        local out = { string.format("HTTP/1.1 %d %s\r\n", code, code == 502 and "Bad Gateway" or "OK") }
        for k, v in pairs(headers or {}) do
            if not HOP[k:lower()] then out[#out + 1] = k .. ": " .. tostring(v):gsub("[\r\n]", " ") .. "\r\n" end
        end
        if err then out[#out + 1] = "X-Gz-Helper-Error: " .. tostring(err):gsub("[\r\n]", " ") .. "\r\n" end
        out[#out + 1] = "Content-Length: " .. #(body or "") .. "\r\nConnection: close\r\n\r\n"
        c:send(table.concat(out) .. (body or ""))
    end
    local function handle(c)
        c:settimeout(120)
        local line = c:receive("*l")
        local method, target = (line or ""):match("^(%u+) (%S+) HTTP/1%.%d$")
        local headers = {}
        while true do
            local h = c:receive("*l")
            if not h or h == "" then break end
            local k, v = h:match("^([^:]+):%s*(.*)$")
            if k then headers[k] = v end
        end
        local given
        for k, v in pairs(headers) do if k:lower() == "x-gz-helper" then given = v end end
        if not method or not target:match("^https?://") or given ~= token then return reply(c, 403, {}, "") end
        local len
        for k, v in pairs(headers) do if k:lower() == "content-length" then len = tonumber(v) end end
        local body = len and len > 0 and c:receive(len) or nil
        local send = {}
        for k, v in pairs(headers) do if not HOP[k:lower()] then send[k] = v end end
        local code, data, rh, status = Api.rawRequest(method, target, { headers = send, raw_body = body, want_raw = true, no_inflate = true })
        if type(code) ~= "number" then return reply(c, 502, {}, "", status or "network error") end
        reply(c, code, rh, data or "")
    end
    while true do
        local c = srv:accept()
        if c then
            pcall(handle, c)
            c:close()
            last = socket.gettime()
        end
        if not alive(ppid) or socket.gettime() - last > H.IDLE_EXIT or readFile(dir .. "/stop") then break end
    end
    os.remove(dir .. "/endpoint")
    os.remove(dir .. "/stop")
    Api.poolEnd()
    srv:close()
end

if modname ~= "gzreader_reqhelper" and arg and arg[1] then
    serve(arg[1], tonumber(arg[2]))
    os.exit(0)
end

---------------------------------------------------------------- GZreader's side

H.dir_override = nil -- (tests)
function H.dir()
    if H.dir_override then return H.dir_override end
    local d = require("datastorage"):getDataDir() .. "/cache/gz-reqhelper"
    require("libs/libkoreader-lfs").mkdir(d)
    return d
end

function H.enabled()
    if H.force ~= nil then return H.force end
    return require("libs/libkoreader-lfs").attributes(H.FLAG, "mode") == "file"
end

--- The running helper's port and token, or nil (read once per process).
function H.endpoint()
    if H.dead then return nil end
    local s = readFile(H.dir() .. "/endpoint")
    local port, token, pid = (s or ""):match("^(%d+) (%x+) (%d+)")
    if not port or not alive(tonumber(pid)) then return nil end
    return tonumber(port), token
end

--- Wi-Fi on: start it (if it's turned on and not running).
function H.start(plugin_path, luajit)
    if not H.enabled() or H.endpoint() then return false end
    local dir = H.dir()
    os.remove(dir .. "/stop")
    local me = tonumber((readFile("/proc/self/stat") or ""):match("^(%d+)"))
    local q = function(x) return "'" .. tostring(x):gsub("'", "'\\''") .. "'" end
    local script = (plugin_path or "plugins/gzreader.koplugin") .. "/gzreader_reqhelper.lua"
    luajit = luajit or require("gzreader_audiobook").luajit()
    os.execute(string.format("(nice -n 5 %s %s %s %d >/dev/null 2>&1 &) >/dev/null 2>&1", luajit, q(script), q(dir), me or 0))
    pcall(function() require("gzreader_log").info("request helper: started") end)
    return true
end

--- Wi-Fi off: stop it.
function H.stop()
    local f = io.open(H.dir() .. "/stop", "wb")
    if f then f:write("stop"); f:close() end
    os.remove(H.dir() .. "/endpoint")
    pcall(function() require("gzreader_log").info("request helper: stopped (Wi-Fi off)") end)
end

return H
