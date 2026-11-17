-- The updater's certificate checks (gzreader_tls.lua), against real TLS
-- servers on this machine with the test certificates in tls/.
--   luajit tls_test.lua <gzreader.koplugin dir> <port>
local plugin_dir, port = arg[1], tonumber(arg[2] or "18170")
package.path = plugin_dir .. "/?.lua;" .. package.path

local passed, failed = 0, 0
local function check(cond, name, extra)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name .. (extra and (" (" .. tostring(extra) .. ")") or "")) end
end

local okssl = pcall(require, "ssl")
if not okssl then
    print("FAIL: LuaSec (lua-sec) isn't installed: the certificate checks can't be tested")
    print("0 passed, 1 failed")
    os.exit(1)
end

local socket = require("socket")
local http = require("socket.http")
local ltn12 = require("ltn12")
local Tls = require("gzreader_tls")

local here = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
local certs = here .. "/tls"

-- the servers: a good certificate, an expired one
local pids = {}
local function serve(p, cert)
    local h = io.popen(string.format("python3 -I %q %d %q %q >/dev/null 2>&1 & echo $!", here .. "/tls_server.py", p, certs .. "/" .. cert, certs .. "/server.key"))
    pids[#pids + 1] = h:read("*l")
    h:close()
end
serve(port, "good.crt")
serve(port + 1, "expired.crt")
local function up(p)
    for _i = 1, 100 do
        local s = socket.tcp()
        s:settimeout(0.2)
        if s:connect("127.0.0.1", p) then s:close() return true end
        s:close()
        socket.sleep(0.1)
    end
end
check(up(port) and up(port + 1), "the test servers started")

local function get(p, name)
    local create, err = Tls.create(name)
    if not create then return nil, err end
    local body = {}
    local r, code = http.request{ url = "https://127.0.0.1:" .. p .. "/", create = create, sink = ltn12.sink.table(body) }
    if not r then return nil, code end
    return code, table.concat(body)
end

-- host names in certificates
check(Tls.hostMatches("api.github.com", "API.GitHub.com"), "names: same name, any case")
check(Tls.hostMatches("*.githubusercontent.com", "raw.githubusercontent.com"), "names: a wildcard covers one label")
check(not Tls.hostMatches("*.githubusercontent.com", "a.raw.githubusercontent.com"), "names: a wildcard covers only one label")
check(not Tls.hostMatches("*.githubusercontent.com", "githubusercontent.com"), "names: a wildcard doesn't cover the bare domain")
check(not Tls.hostMatches("*.com", "github.com"), "names: no wildcard for a whole top-level domain")
check(not Tls.hostMatches("github.com", "github.com.example.com"), "names: no prefix matches")

Tls.cafile = certs .. "/ca.crt"
local code, body = get(port, "api.example.com")
check(code == 200 and body == "hello", "a trusted certificate for that host: connected", code)
code = get(port, "x.files.example.com")
check(code == 200, "a trusted wildcard certificate: connected", code)
local c2, err = get(port, "github.com")
check(c2 == nil and tostring(err):find("not github.com", 1, true), "a certificate for another host: refused", err)
c2, err = get(port, "a.b.files.example.com")
check(c2 == nil, "a wildcard doesn't stretch over two labels: refused", err)

Tls.cafile = certs .. "/other-ca.crt"
c2, err = get(port, "api.example.com")
check(c2 == nil and tostring(err):find("not trusted", 1, true), "a certificate from an authority not in the list: refused", err)

Tls.cafile = certs .. "/ca.crt"
c2, err = get(port + 1, "api.example.com")
check(c2 == nil and tostring(err):find("expired", 1, true), "an expired certificate, the clock right: refused", err)
Tls.now = function() return os.time{ year = 2000, month = 1, day = 2 } end -- (a Nook's clock run down)
code = get(port + 1, "api.example.com")
check(code == 200, "an expired certificate while the clock is before 2026 (can't be right): connected", code)
c2, err = get(port + 1, "github.com")
check(c2 == nil, "the clock wrong: another host's certificate is still refused", err)
Tls.cafile = certs .. "/other-ca.crt"
c2, err = get(port + 1, "api.example.com")
check(c2 == nil and tostring(err):find("not trusted", 1, true), "the clock wrong: an untrusted authority is still refused", err)
Tls.now = os.time

Tls.cafile = certs .. "/missing.crt"
local create, cerr = Tls.create("api.github.com")
check(create == nil and tostring(cerr):find("missing", 1, true), "no list of authorities: nothing is connected", cerr)

-- the updater goes through it
do
    local noop = function() end
    local stubs = {
        ["datastorage"] = { getDataDir = function() return "/tmp" end },
        ["ui/widget/infomessage"] = {}, ["ui/widget/confirmbox"] = {}, ["ui/uimanager"] = {},
        ["gzreader_json"] = {}, ["ffi/util"] = { template = function(s) return s end },
        ["libs/libkoreader-lfs"] = {}, ["gzreader_log"] = { info = noop, warn = noop, err = noop },
        ["gettext"] = function(s) return s end,
        ["socketutil"] = { set_timeout = noop, reset_timeout = noop, table_sink = ltn12.sink.table },
    }
    for k, v in pairs(stubs) do package.loaded[k] = v end
    local Update = require("gzreader_update")
    local c3, _, uerr = Update.get("https://api.github.com/repos/x/y/releases/latest")
    check(c3 == nil and tostring(uerr):find("missing", 1, true), "the updater: no list of authorities, no request", uerr)
    Tls.cafile = certs .. "/ca.crt"
    local seen
    local real = http.request
    http.request = function(reqt) seen = reqt; return nil, "stopped here" end
    Update.get("https://api.github.com/repos/x/y/releases/latest")
    http.request = real
    check(seen and type(seen.create) == "function", "the updater's requests are made through the certificate check")
end

for _i, pid in ipairs(pids) do os.execute("kill " .. tonumber(pid) .. " 2>/dev/null") end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
