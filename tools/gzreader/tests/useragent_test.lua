-- Every request GZreader makes says "GZreader/<version>": socketutil's user
-- agent (LuaSocket's default, put in every request it makes) is GZreader's,
-- and no code sends another one of its own.
--   luajit useragent_test.lua <repo> <work dir>
local REPO, WORK = arg[1], arg[2] or "/tmp/gz-ua-test"
package.path = REPO .. "/frontend/?.lua;" .. package.path
local pass, fail = 0, 0
local function check(ok, what) if ok then pass = pass + 1; print("  ok   " .. what) else fail = fail + 1; print("  FAIL " .. what) end end

local ok_s = pcall(require, "socket.http")
if ok_s then
    os.execute("rm -rf '" .. WORK .. "' && mkdir -p '" .. WORK .. "'")
    local f = io.open(WORK .. "/gzreader-version", "w"); f:write("v1.33.0\n"); f:close()
    -- (socketutil reads gzreader-version beside reader.lua: KOReader runs from that folder)
    local lfs_ok, lfs = pcall(require, "lfs")
    local here = lfs_ok and lfs.currentdir()
    if lfs_ok then lfs.chdir(WORK) end
    local socketutil = require("socketutil")
    local http = require("socket.http")
    check(socketutil.USER_AGENT == "GZreader/1.33.0" and http.USERAGENT == "GZreader/1.33.0",
        "socketutil: GZreader/1.33.0 (the installed version), and LuaSocket sends it with every request")
    check(socketutil.gzUserAgent("1.34.0-beta2") == "GZreader/1.34.0-beta2" and socketutil.gzUserAgent(nil):match("^GZreader/"),
        "…any version, a test build's too")
    if lfs_ok then lfs.chdir(WORK .. "/..") end
    check(socketutil.gzUserAgent() == "GZreader/dev" or not lfs_ok, "no gzreader-version (a build from source): GZreader/dev")
    if here then lfs.chdir(here) end
else
    print("  (no LuaSocket here: socketutil's part left to the emulator)")
end

-- no request sends a user agent of its own (KOReader's, LuaSocket's, ZenOS's or a fixed one)
local bad = {}
local p = io.popen("cd '" .. REPO .. "' && grep -rn 'User%-Agent\\|\\[\"User-Agent\"\\]\\|USER_AGENT =' plugins/gzreader.koplugin plugins/zenos.koplugin frontend --include=*.lua")
for line in p:lines() do
    if line:find('"User-Agent"', 1, true) or line:find("USER_AGENT =", 1, true) then
        local ok = line:find('socketutil"?%)?%.USER_AGENT') or line:find("= USER_AGENT", 1, true)
            or line:find('["User-Agent"] = userAgent()', 1, true) -- (gzreader_daily / _update: socketutil's, safely)
        if not ok then bad[#bad + 1] = line end
    end
end
p:close()
check(#bad == 0, "every User-Agent header in GZreader's and ZenOS's code is socketutil's" .. (#bad > 0 and (": " .. table.concat(bad, " | ")) or ""))
for _i, name in ipairs({ "gzreader_daily", "gzreader_update" }) do
    local src = io.open(REPO .. "/plugins/gzreader.koplugin/" .. name .. ".lua"):read("*a")
    check(src:find('local ok, su = pcall(require, "socketutil")\n    return ok and type(su) == "table" and su.USER_AGENT or "GZreader"', 1, true) ~= nil,
        name .. ": its userAgent() is socketutil's")
end
local main = io.open(REPO .. "/plugins/gzreader.koplugin/main.lua"):read("*a")
check(main:find('\nrequire("socketutil")\n', 1, true) ~= nil, "GZreader loads socketutil as it starts (no request goes out as LuaSocket)")

print(string.format("user agent: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
