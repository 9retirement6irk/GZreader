-- The watchdog (gzreader_watchdog.lua, its own process), run for real with
-- short times: no freeze report when the Kindle wakes up (its last beat is
-- from before it slept), a real freeze still reported. The Kindle's sleep is
-- the watchdog stopped (SIGSTOP) and continued: on a Kindle everything stops.
--   luajit watchdog_test.lua <gzreader.koplugin> <work dir>
local PLUGIN, WORK = arg[1], arg[2]
local ffi = require("ffi")
ffi.cdef("int getpid(void);")

local pass, fail = 0, 0
local function check(cond, msg)
    if cond then pass = pass + 1; print("  ok   " .. msg) else fail = fail + 1; print("  FAIL " .. msg) end
end
local function sh(cmd) local p = io.popen(cmd); local s = p:read("*a"); p:close(); return s end
local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function wait(s) os.execute("sleep " .. s) end

local dir = WORK .. "/watchdog"
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "/spool'")
-- (no report address: what it would send stays in the spool, to be looked at)
write(dir .. "/config", "\nKindle\n")
local function beat(status, what) write(dir .. "/heartbeat", os.time() .. " " .. status .. " " .. what) end
local function reports()
    local names = {}
    for name in sh("ls '" .. dir .. "/spool'"):gmatch("[^\n]+") do
        local s = io.open(dir .. "/spool/" .. name, "rb"):read("*a")
        names[#names + 1] = (s:match('"eventName":"([^"(]+)') or name):gsub("%s+$", "")
    end
    return table.concat(names, ", ")
end
local function clear() os.execute("rm -f '" .. dir .. "/spool/'*") end

beat("run", "on Home")
local pid = tonumber(sh(string.format(
    "cd '%s' && GZ_WD_TICK=1 GZ_WD_STALL=4 GZ_WD_SLOW=100 luajit '%s/gzreader_watchdog.lua' '%s' %d >/dev/null 2>&1 & echo $!",
    dir, PLUGIN, dir, ffi.C.getpid())))
check(pid ~= nil, "the watchdog started")

print("== waking up")
;(function()
    -- the screensaver went up while GZreader still said "run", then the Kindle slept
    wait(2)
    beat("run", "on Home (ScreenSaver)")
    os.execute("kill -STOP " .. pid)
    wait(9) -- (more than 6 ticks: the watchdog sees it slept)
    os.execute("kill -CONT " .. pid)
    wait(1.5)
    beat("run", "on Home") -- GZreader's first beat after waking
    wait(3)
    check(reports() == "", "woken after a sleep: no \"unresponsive\" (GZreader's last beat was from before it slept): " .. reports())
end)()

print("== a real freeze")
;(function()
    clear()
    beat("run", "opening a book")
    wait(9) -- no beats: more than STALL
    local r = reports()
    check(r:find("Kindle unresponsive", 1, true) ~= nil, "no beats for longer than it allows: reported as unresponsive: " .. r)
    beat("run", "reading")
    wait(3)
    check(reports():find("Kindle responsive again", 1, true) ~= nil, "…and responsive again when it beats")
end)()

print("== a freeze right after waking")
;(function()
    clear()
    beat("run", "on Home (ScreenSaver)")
    os.execute("kill -STOP " .. pid)
    wait(9)
    os.execute("kill -CONT " .. pid)
    wait(9) -- woken, but no beat since
    check(reports():find("Kindle unresponsive", 1, true) ~= nil,
        "no beat for longer than it allows after waking: still reported (counted from waking): " .. reports())
end)()

beat("off", "")
wait(2)
os.execute("kill " .. pid .. " 2>/dev/null")

print("== sending: GZreader's user agent; a message the feed keeps failing doesn't hold up the rest")
;(function()
    -- a feed that answers 500 to one message (POISON) and 200 to the others, and notes each request
    local fdir = WORK .. "/watchdog-feed"
    os.execute("rm -rf '" .. fdir .. "' && mkdir -p '" .. fdir .. "/spool'")
    local log = fdir .. "/requests.txt"
    local server = [[
import http.server, json, sys
log = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        body = raw.decode("utf-8", "replace")
        # (as Tianji: PostgreSQL text can't hold a NUL, nor invalid UTF-8)
        try:
            raw.decode("utf-8"); d = json.loads(body); bad = any("\x00" in str(v) for v in d.values())
        except Exception:
            bad = True
        what = "POISON" if "POISON" in body else ("NUL" if "nul test" in body else "ok")
        code = 500 if ("POISON" in body or bad) else 200
        with open(log, "a") as f:
            f.write("%s|%s|%s\n" % (self.headers.get("User-Agent"), what, code))
        self.send_response(code); self.send_header("Content-Length", "0"); self.end_headers()
    def log_message(self, *a): pass
s = http.server.HTTPServer(("127.0.0.1", 0), H)
print(s.server_address[1], flush=True)
s.serve_forever()
]]
    write(fdir .. "/server.py", server)
    local sp = io.popen("python3 -I '" .. fdir .. "/server.py' x '" .. log .. "' & echo $!")
    local spid = tonumber(sp:read("*l"))
    local port = tonumber(sp:read("*l"))
    check(port ~= nil, "a stand-in feed is listening")
    write(fdir .. "/config", "http://127.0.0.1:" .. tostring(port) .. "/open/feed/test\nKindle\n")
    write(fdir .. "/gzreader-version", "9.8.7-beta.abc\n")
    write(fdir .. "/heartbeat", os.time() .. " run on Home")
    write(fdir .. "/spool/10000001-send.json", '{"eventName":"POISON one"}')
    write(fdir .. "/spool/10000002-send.json", '{"eventName":"after it"}')
    -- written by GZreader before 1.34: the end of a crash.log with NUL bytes, a letter cut in two
    write(fdir .. "/spool/10000003-send.json", '{"eventName":"nul test","eventContent":"end of crash.log\\u0000\\u0000 caf\195"}')
    local wpid = tonumber(sh(string.format(
        "cd '%s' && GZ_WD_TICK=1 GZ_WD_STALL=100 GZ_WD_MAX_5XX=3 GZ_WD_MAX_WAIT=2 luajit '%s/gzreader_watchdog.lua' '%s' %d >/dev/null 2>&1 & echo $!",
        fdir, PLUGIN, fdir, ffi.C.getpid())))
    local function requests()
        local f = io.open(log, "rb")
        local t = f and f:read("*a") or ""
        if f then f:close() end
        local out = {}
        for line in t:gmatch("[^\n]+") do out[#out + 1] = line end
        return out
    end
    wait(3)
    local early = 0
    for _i, r in ipairs(requests()) do if r:find("|POISON|", 1, true) then early = early + 1 end end
    check(early >= 1 and early <= 2, "a server error: tried again later, not every few seconds (" .. early .. " tries in 3 s)")
    for _i = 1, 20 do
        local done = false
        for _j, r in ipairs(requests()) do if r:find("|NUL|", 1, true) then done = true end end
        if done then break end
        wait(1)
    end
    local poison, after, ua, nul = 0, 0, {}, {}
    for _i, r in ipairs(requests()) do
        local a, what = r:match("^(.-)|(%a+)|")
        ua[a or "?"] = true
        if what == "POISON" then poison = poison + 1 elseif what == "ok" then after = after + 1
        elseif what == "NUL" then nul[#nul + 1] = r:match("|(%d+)$") end
    end
    local agents = {}
    for a in pairs(ua) do agents[#agents + 1] = a end
    check(#agents == 1 and agents[1] == "GZreader/9.8.7-beta.abc", "every request says GZreader/<version>: " .. table.concat(agents, ", "))
    check(poison == 3 and after == 1, "after 3 server errors it's set aside, and the next message is sent (" .. poison .. " tries, " .. after .. " sent)")
    check(#nul == 1 and nul[1] == "200", "a report with NUL bytes and a cut letter: cleaned, and the feed takes it at once (" .. table.concat(nul, ",") .. ")")
    local files = sh("ls '" .. fdir .. "/spool'")
    check(files:find("10000001%-send%.json%.failed") ~= nil and not files:find("%.json\n") and not files:find("%.json$"),
        "…kept as .failed; nothing left to send: " .. files:gsub("\n", " "))
    os.execute("kill " .. wpid .. " " .. tostring(spid) .. " 2>/dev/null")
end)()
print(string.format("watchdog: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
