--[[--
Tiny one-shot HTTP server used for QR pairing.

The Kindle Keyboard has no camera, so pairing runs the other way round: the
Kindle shows a QR code with a secret URL pointing at this server, the phone
opens it, and the form on that page posts the Grimmory address and login to
the Kindle. Unlike ui/message/simpletcpserver, this server also reads the
request body so credentials travel in a POST body rather than in the URL.

It is polled by UIManager (insertZMQ), lives only while the QR screen is up,
and only answers requests carrying the random per-session token.

Uploads (books sent from the phone): the `upload` hook may take a POST whose
body is a raw file; it's written to disk as it arrives, a piece on every
poll, so the Kindle stays responsive and the file never sits in memory.

Every connection is read and answered the same way, a piece on each poll
(never waiting on one): a phone, or anything else on the Wi-Fi, that
connects and then sends slowly or not at all only holds its own connection
(dropped after REQUEST_S), never the Kindle's screen. At most MAX_CONNS at
once; the oldest goes when another comes.
]]

local Device = require("device")
local logger = require("logger")
local socket = require("socket")

local MAX_BODY = 65536 -- forms (calendar links pasted on the phone)
local MAX_HEADER_LINES = 64
local UPLOAD_STALL_S = 60 -- an upload with no data for this long is dropped
local UPLOAD_READ_PER_POLL = 1048576
local MAX_HEADER_BYTES = 16384

local PairServer = {
    port = 8642,
    handler = nil, -- function(method, path, headers, body) -> code, content_type, body
    -- upload = function(method, path, headers, length) -> nil (not an upload) |
    --   { error = code, message } | { file = path to write, done = function(ok, err) -> code, ctype, body }
    upload = nil,
    exact_port = false, -- only `port` (otherwise the next few if it's taken)
    keep_wifi = true,   -- hold Wi-Fi on while it runs
    REQUEST_S = 15,     -- to send the request (line, headers, body)
    ANSWER_S = 120,     -- to take the answer (the diagnostic log on slow Wi-Fi)
    MAX_CONNS = 8,      -- connections being read or answered at once
}

function PairServer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- The Kindle firewall drops inbound connections; open (and later close) a hole
-- for our port only. Plain rules (no conntrack/state match) so it also works
-- with the old iptables on Kindle 2/3/DX.
local function firewall(action, port)
    if not Device:isKindle() then return end
    os.execute(string.format("iptables %s INPUT -p tcp --dport %d -j ACCEPT 2>/dev/null", action, port))
    os.execute(string.format("iptables %s OUTPUT -p tcp --sport %d -j ACCEPT 2>/dev/null", action, port))
end

function PairServer:start()
    local server, err
    -- Try a few ports in case one is taken.
    for offset = 0, self.exact_port and 0 or 4 do
        server, err = socket.bind("*", self.port + offset)
        if server then
            self.port = self.port + offset
            break
        end
    end
    if not server then
        return false, err or "bind failed"
    end
    server:settimeout(0)
    self.server = server
    firewall("-A", self.port)
    if self.keep_wifi then
        pcall(function() require("gzreader_net").hold("pairserver") end) -- keep Wi-Fi up while the QR page is open
    end
    logger.dbg("Grimmory pairing server listening on", self.port)
    return true
end

function PairServer:stop()
    -- (the connection whose request stopped it still gets its answer: waitEvent)
    for _i, c in ipairs(self.conns or {}) do
        if c ~= self.handling then pcall(c.client.close, c.client) end
    end
    self.conns = nil
    for _i, up in ipairs(self.uploads or {}) do
        pcall(up.fh.close, up.fh)
        os.remove(up.file)
        pcall(up.client.close, up.client)
    end
    self.uploads = nil
    if self.server then
        self.server:close()
        self.server = nil
        firewall("-D", self.port)
        if self.keep_wifi then pcall(function() require("gzreader_net").release("pairserver") end) end
        logger.dbg("Grimmory pairing server stopped")
    end
end

local REASONS = { [200] = "OK", [302] = "Found", [303] = "See Other", [400] = "Bad Request", [404] = "Not Found",
    [405] = "Method Not Allowed", [409] = "Conflict", [411] = "Length Required", [413] = "Payload Too Large",
    [415] = "Unsupported Media Type", [500] = "Internal Server Error", [507] = "Insufficient Storage" }

local answer -- (below)

--- An upload's result (a short answer: sent at once).
local function respond(client, code, content_type, body, extra_headers)
    client:settimeout(10)
    client:send(answer(code, content_type, body, extra_headers))
    client:close()
end

--- Uploads in progress: read what has arrived, write it, finish the done ones.
function PairServer:pumpUploads()
    if not self.uploads then return end
    local now = socket.gettime()
    for i = #self.uploads, 1, -1 do
        local up = self.uploads[i]
        local got_any, failed = false, nil
        local budget = UPLOAD_READ_PER_POLL
        while up.remaining > 0 and budget > 0 do
            local want = math.min(up.remaining, 65536, budget)
            local data, err, partial = up.client:receive(want)
            data = data or partial
            if data and #data > 0 then
                local okw = up.fh:write(data)
                if not okw then failed = "write"; break end
                up.remaining = up.remaining - #data
                up.received = up.received + #data
                budget = budget - #data
                got_any = true
            end
            if err == "closed" then failed = "closed"; break end
            if err == "timeout" or not data or #data == 0 then break end
        end
        if got_any then up.last = now end
        if not failed and up.remaining > 0 and now - up.last > UPLOAD_STALL_S then failed = "stalled" end
        if failed or up.remaining == 0 then
            table.remove(self.uploads, i)
            up.fh:close()
            local ok_done, code, ctype, body = pcall(up.done, not failed, failed)
            if not ok_done then
                logger.err("pairing upload handler error:", code)
                code, ctype, body = 400, "text/plain", "Something went wrong on the Kindle."
            end
            if failed then os.remove(up.file) end
            up.client:settimeout(10)
            if failed ~= "closed" then respond(up.client, code or 200, ctype, body) else up.client:close() end
        end
    end
end

function PairServer:uploading() return self.uploads ~= nil and #self.uploads > 0 end

function answer(code, content_type, body, extra_headers)
    body = body or ""
    local lines = { string.format("HTTP/1.0 %d %s", code, REASONS[code] or "OK") }
    for k, v in pairs(type(extra_headers) == "table" and extra_headers or {}) do
        if tostring(k):match("^[%w%-]+$") and not tostring(v):find("[\r\n]") then
            lines[#lines + 1] = k .. ": " .. tostring(v)
        end
    end
    if code == 302 or code == 303 then
        lines[#lines + 1] = "Location: " .. body
        body, content_type = "", "text/plain"
    end
    lines[#lines + 1] = "Content-Type: " .. (content_type or "text/plain") .. "; charset=utf-8"
    lines[#lines + 1] = "Content-Length: " .. #body
    lines[#lines + 1] = "Cache-Control: no-store"
    lines[#lines + 1] = "Referrer-Policy: no-referrer"
    lines[#lines + 1] = "X-Frame-Options: DENY"
    lines[#lines + 1] = "Connection: close"
    return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end
PairServer._answer = answer -- (tests)

--- The request line and headers, once the buffer holds them all:
--- method, path, headers, the bytes after them; or nil (not yet); or false (bad).
local function parseHead(buf)
    local stop, after = buf:find("\r?\n\r?\n")
    if not stop then return #buf > MAX_HEADER_BYTES and false or nil end
    local head, rest = buf:sub(1, stop - 1), buf:sub(after + 1)
    local lines = {}
    for line in (head .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = (line:gsub("\r$", "")) end
    local method, path = (lines[1] or ""):match("^(%u+) (%S+) HTTP/%d%.%d$")
    if not method or #lines - 1 > MAX_HEADER_LINES then return false end
    local headers = {}
    for i = 2, #lines do
        local k, v = lines[i]:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end
    return method, path, headers, rest
end

--- Answer `c` (sent a piece at a time by step()).
function PairServer:reply(c, code, ctype, body, extra)
    c.state, c.out, c.sent, c.deadline = "write", answer(code or 200, ctype, body, extra), 0, socket.gettime() + self.ANSWER_S
end

--- The request is all here: an upload goes on to pumpUploads, anything else to the handler.
function PairServer:dispatch(c, method, path, headers, rest)
    local length = tonumber(headers["content-length"] or "0") or 0
    local up = self.upload and self.upload(method, path, headers, length)
    if up then
        if up.error then return self:reply(c, up.error, up.ctype or "text/plain", up.message or "") end
        local fh = io.open(up.file, "wb")
        if not fh then return self:reply(c, 507, "text/plain", "The Kindle couldn't save the file.") end
        if (headers["expect"] or ""):lower() == "100-continue" then c.client:send("HTTP/1.1 100 Continue\r\n\r\n") end
        local first = rest:sub(1, length)
        if #first > 0 then fh:write(first) end
        c.state = "upload"
        self.uploads = self.uploads or {}
        table.insert(self.uploads, { client = c.client, fh = fh, file = up.file, done = up.done,
            remaining = length - #first, received = #first, last = socket.gettime() })
        return
    end
    if length > MAX_BODY then return self:reply(c, 413, "text/plain", "Too large") end
    c.state, c.method, c.path, c.headers, c.length, c.buf = "body", method, path, headers, length, rest
end

--- One connection, as far as what has arrived lets it go. true when it's finished with.
function PairServer:step(c, now)
    if now > c.deadline then pcall(c.client.close, c.client); return true end
    if c.state == "head" or c.state == "body" then
        local data, err, partial = c.client:receive(8192)
        data = data or partial
        if data and #data > 0 then c.buf = c.buf .. data end
        if err == "closed" and (not data or #data == 0) then pcall(c.client.close, c.client); return true end
        if c.state == "head" then
            local method, path, headers, rest = parseHead(c.buf)
            if method == false then self:reply(c, 400, "text/plain", "Bad request")
            elseif method then self:dispatch(c, method, path, headers, rest) end
            if c.state == "upload" then return true end
        end
        if c.state == "body" and #c.buf >= c.length then
            self.handling = c
            local ok, code, ctype, resp, extra = pcall(self.handler, c.method, c.path, c.headers, c.buf:sub(1, c.length))
            self.handling = nil
            if not ok then
                logger.err("Grimmory pairing handler error:", code)
                self:reply(c, 400, "text/plain", "Something went wrong on the Kindle.")
            else
                self:reply(c, code, ctype, resp, extra)
            end
        end
    end
    if c.state == "write" then
        local last, err, partial = c.client:send(c.out, c.sent + 1)
        c.sent = last or partial or c.sent
        if c.sent >= #c.out or (err and err ~= "timeout") then pcall(c.client.close, c.client); return true end
    end
    return false
end

-- Called by UIManager:processZMQs() as an iterator; always ends the
-- iteration by returning nil. Nothing here waits on a connection.
function PairServer:waitEvent()
    if not self.server then return nil end
    self:pumpUploads()
    self.conns = self.conns or {}
    local now = socket.gettime()
    for _i = 1, 4 do -- (a few new connections per poll)
        local client = self.server:accept()
        if not client then break end
        client:settimeout(0)
        if #self.conns >= self.MAX_CONNS then
            local oldest = table.remove(self.conns, 1)
            pcall(oldest.client.close, oldest.client)
        end
        self.conns[#self.conns + 1] = { client = client, state = "head", buf = "", deadline = now + self.REQUEST_S }
    end
    local conns = self.conns
    for i = #conns, 1, -1 do
        local c = conns[i]
        local okc, finished = pcall(self.step, self, c, now)
        self.handling = nil
        if not okc then logger.err("pairing connection error:", finished); pcall(c.client.close, c.client) end
        if not okc or finished then table.remove(conns, i) end
        if not self.server then
            -- (stopped by what this request did: its answer still goes, the others are closed)
            if okc and not finished and c.state == "write" then
                c.client:settimeout(10)
                pcall(c.client.send, c.client, c.out, c.sent + 1)
                pcall(c.client.close, c.client)
            end
            return nil
        end
    end
    return nil
end

local function usable(ip)
    return type(ip) == "string" and ip:match("^%d+%.%d+%.%d+%.%d+$")
        and ip ~= "0.0.0.0" and not ip:match("^127%.") and not ip:match("^169%.254%.")
end

--- Address of a network interface, read from busybox/net-tools ifconfig
--- output ("inet addr:1.2.3.4" or "inet 1.2.3.4").
function PairServer.parseIfconfig(out)
    for ip in (out or ""):gmatch("inet addr:(%d+%.%d+%.%d+%.%d+)") do
        if usable(ip) then return ip end
    end
    for ip in (out or ""):gmatch("inet (%d+%.%d+%.%d+%.%d+)") do
        if usable(ip) then return ip end
    end
end

local function ifconfigIp(iface)
    for _, cmd in ipairs({ "ifconfig " .. iface, "/sbin/ifconfig " .. iface, "ifconfig" }) do
        local p = io.popen(cmd .. " 2>/dev/null")
        if p then
            local out = p:read("*a")
            p:close()
            local ip = PairServer.parseIfconfig(out)
            if ip then return ip end
        end
    end
end

--- Best guess at this device's LAN address. Returns ip or nil, details.
--- 1. "Connect" a UDP socket towards the Grimmory host / a public address and
---    read the local address the kernel picked (no packets are sent).
--- 2. Fall back to the Wi-Fi interface's address from ifconfig.
function PairServer.localIp(hint_host, iface)
    local tried = {}
    -- NB: build the list without holes; ipairs() stops at the first nil.
    local targets = {}
    if hint_host and hint_host ~= "" then targets[#targets + 1] = hint_host end
    targets[#targets + 1] = "192.0.2.1"
    targets[#targets + 1] = "8.8.8.8"
    for _, target in ipairs(targets) do
        local udp = socket.udp()
        if udp then
            local ok, err = udp:setpeername(target, 80)
            local ip = ok and udp:getsockname()
            udp:close()
            if usable(ip) then return ip end
            tried[#tried + 1] = target .. ": " .. tostring(ip or err)
        end
    end
    local ip = ifconfigIp(iface or "wlan0")
    if ip then return ip end
    tried[#tried + 1] = "ifconfig " .. (iface or "wlan0") .. ": no address"
    logger.warn("Grimmory: couldn't determine local IP;", table.concat(tried, "; "))
    return nil, table.concat(tried, "\n")
end

--- 128 random bits as hex (the secret in the QR URL).
function PairServer.randomToken(nbytes)
    nbytes = nbytes or 16
    local f = io.open("/dev/urandom", "rb")
    local bytes = f and f:read(nbytes)
    if f then f:close() end
    if not bytes or #bytes < nbytes then
        math.randomseed(os.time() + math.floor(os.clock() * 1e6))
        local t = {}
        for i = 1, nbytes do t[i] = string.char(math.random(0, 255)) end
        bytes = table.concat(t)
    end
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

function PairServer.parseForm(body)
    local form = {}
    for pair in (body or ""):gmatch("[^&]+") do
        local k, v = pair:match("^([^=]*)=?(.*)$")
        if k then
            local function dec(s)
                s = s:gsub("+", " ")
                return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
            end
            form[dec(k)] = dec(v)
        end
    end
    return form
end

return PairServer
