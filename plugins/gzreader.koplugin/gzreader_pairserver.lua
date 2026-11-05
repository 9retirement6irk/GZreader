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
]]

local Device = require("device")
local logger = require("logger")
local socket = require("socket")

local MAX_BODY = 65536 -- forms (calendar links pasted on the phone)
local MAX_HEADER_LINES = 64
local UPLOAD_STALL_S = 60 -- an upload with no data for this long is dropped
local UPLOAD_READ_PER_POLL = 1048576

local PairServer = {
    port = 8642,
    handler = nil, -- function(method, path, headers, body) -> code, content_type, body
    -- upload = function(method, path, headers, length) -> nil (not an upload) |
    --   { error = code, message } | { file = path to write, done = function(ok, err) -> code, ctype, body }
    upload = nil,
    exact_port = false, -- only `port` (otherwise the next few if it's taken)
    keep_wifi = true,   -- hold Wi-Fi on while it runs
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

local function respond(client, code, content_type, body, extra_headers)
    body = body or ""
    local lines = { string.format("HTTP/1.0 %d %s", code, REASONS[code] or "OK") }
    for k, v in pairs(type(extra_headers) == "table" and extra_headers or {}) do
        if tostring(k):match("^[%w%-]+$") and not tostring(v):find("[\r\n]") then
            lines[#lines + 1] = k .. ": " .. tostring(v)
        end
    end
    if code == 302 or code == 303 then
        -- the handler returns the redirect target as the body
        lines[#lines + 1] = "Location: " .. body
        body, content_type = "", "text/plain"
    end
    lines[#lines + 1] = "Content-Type: " .. (content_type or "text/plain") .. "; charset=utf-8"
    lines[#lines + 1] = "Content-Length: " .. #body
    lines[#lines + 1] = "Cache-Control: no-store"
    lines[#lines + 1] = "Referrer-Policy: no-referrer"
    lines[#lines + 1] = "X-Frame-Options: DENY"
    lines[#lines + 1] = "Connection: close"
    client:send(table.concat(lines, "\r\n") .. "\r\n\r\n" .. body)
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

-- Called by UIManager:processZMQs() as an iterator; we handle at most one
-- connection per pass and always end the iteration by returning nil.
function PairServer:waitEvent()
    if not self.server then return nil end
    self:pumpUploads()
    local client = self.server:accept()
    if not client then return nil end
    client:settimeout(3)

    local request_line = client:receive("*l")
    if not request_line then client:close() return nil end
    local method, path = request_line:match("^(%u+) (%S+) HTTP/%d%.%d$")
    if not method then
        respond(client, 400, "text/plain", "Bad request")
        return nil
    end

    local headers = {}
    for _ = 1, MAX_HEADER_LINES do
        local line = client:receive("*l")
        if not line or line == "" then break end
        local k, v = line:match("^([^:]+):%s*(.*)$")
        if k then headers[k:lower()] = v end
    end

    local body = ""
    local length = tonumber(headers["content-length"] or "0") or 0
    local up = self.upload and self.upload(method, path, headers, length)
    if up then
        if up.error then
            respond(client, up.error, up.ctype or "text/plain", up.message or "")
            return nil
        end
        local fh = io.open(up.file, "wb")
        if not fh then
            respond(client, 507, "text/plain", "The Kindle couldn't save the file.")
            return nil
        end
        if (headers["expect"] or ""):lower() == "100-continue" then client:send("HTTP/1.1 100 Continue\r\n\r\n") end
        client:settimeout(0)
        self.uploads = self.uploads or {}
        table.insert(self.uploads, { client = client, fh = fh, file = up.file, done = up.done,
            remaining = length, received = 0, last = socket.gettime() })
        self:pumpUploads()
        return nil
    end
    if length > MAX_BODY then
        respond(client, 413, "text/plain", "Too large")
        return nil
    elseif length > 0 then
        body = client:receive(length) or ""
    end

    local ok, code, ctype, resp, extra = pcall(self.handler, method, path, headers, body)
    if not ok then
        logger.err("Grimmory pairing handler error:", code)
        respond(client, 400, "text/plain", "Something went wrong on the Kindle.")
    else
        client:settimeout(30) -- big responses (the diagnostic log) on slow Wi-Fi
        respond(client, code or 200, ctype, resp, extra)
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
