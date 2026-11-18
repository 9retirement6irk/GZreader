-- Requests say GZreader/<version>: a little server here (GZ_UA_PORT, 18095)
-- writes down the User-Agent of what it's asked; GZreader asks it with
-- LuaSocket as Memos, Grimmory and the daily paper's feeds are asked.
--   GZ_EMU_TREE=<tree>/koreader run.sh user_agent.lua <out>      (any model)
-- Checks go to <out>/user-agent-checks.txt.
local PORT = tonumber(os.getenv("GZ_UA_PORT") or "18095")
local s = { start = 12 }
local function add(t) s[#s + 1] = t end
local lines = {}
local function check(ok, what) lines[#lines + 1] = (ok and "ok   " or "FAIL ") .. what end
add({ fn = function(E)
    E.ua_file = E.out .. "/ua.txt"
    os.remove(E.ua_file)
    -- (the server: one request, its User-Agent written to ua.txt)
    local py = E.out .. "/ua_server.py"
    local f = io.open(py, "w")
    f:write(table.concat({
        "import http.server, sys",
        "class H(http.server.BaseHTTPRequestHandler):",
        "    def do_GET(s):",
        "        open(sys.argv[1], 'a').write(s.headers.get('User-Agent', '') + '\\n')",
        "        s.send_response(200); s.end_headers(); s.wfile.write(b'ok')",
        "    def log_message(s, *a): pass",
        "http.server.HTTPServer(('127.0.0.1', " .. PORT .. "), H).handle_request()",
    }, "\n") .. "\n")
    f:close()
    os.execute("python3 -I '" .. py .. "' '" .. E.ua_file .. "' &")
end, after = 2 })
add({ fn = function(E)
    local f = io.open("gzreader-version"); local v = f and f:read("*l"); if f then f:close() end
    E.version = v and v:match("^%s*v?([%w%.%-]+)") or "dev"
    -- (a plain LuaSocket request, as a plugin makes: no User-Agent of its own)
    require("socket.http").request("http://127.0.0.1:" .. PORT .. "/")
end, after = 2 })
add({ fn = function(E)
    local f = io.open(E.ua_file); local got = f and f:read("*l"); if f then f:close() end
    check(got == "GZreader/" .. E.version, "a request says " .. tostring(got) .. " (GZreader/" .. E.version .. "), not LuaSocket or KOReader")
    check(require("socketutil").USER_AGENT == "GZreader/" .. E.version, "socketutil's user agent is the same")
    local out = io.open(E.out .. "/user-agent-checks.txt", "w")
    out:write(table.concat(lines, "\n") .. "\n"); out:close()
    for _i, l in ipairs(lines) do E.say("check", l) end
end, after = 1 })
return s
