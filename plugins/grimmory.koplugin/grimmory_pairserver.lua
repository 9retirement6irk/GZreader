--[[--
Tiny one-shot HTTP server used for QR pairing.

The Kindle Keyboard has no camera, so pairing runs the other way round: the
Kindle shows a QR code with a secret URL pointing at this server, the phone
opens it, and the form on that page posts the Grimmory address and login to
the Kindle. Unlike ui/message/simpletcpserver, this server also reads the
request body so credentials travel in a POST body rather than in the URL.

It is polled by UIManager (insertZMQ), lives only while the QR screen is up,
and only answers requests carrying the random per-session token.
]]

local Device = require("device")
local logger = require("logger")
local socket = require("socket")

local MAX_BODY = 8192
local MAX_HEADER_LINES = 64

local PairServer = {
    port = 8642,
    handler = nil, -- function(method, path, headers, body) -> code, content_type, body
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
    for offset = 0, 4 do
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
    pcall(function() require("grimmory_net").hold("pairserver") end) -- keep Wi-Fi up while the QR page is open
    logger.dbg("Grimmory pairing server listening on", self.port)
    return true
end

function PairServer:stop()
    if self.server then
        self.server:close()
        self.server = nil
        firewall("-D", self.port)
        pcall(function() require("grimmory_net").release("pairserver") end)
        logger.dbg("Grimmory pairing server stopped")
    end
end

local REASONS = { [200] = "OK", [302] = "Found", [400] = "Bad Request", [404] = "Not Found", [405] = "Method Not Allowed", [413] = "Payload Too Large" }

local function respond(client, code, content_type, body, extra_headers)
    body = body or ""
    local lines = { string.format("HTTP/1.0 %d %s", code, REASONS[code] or "OK") }
    for k, v in pairs(type(extra_headers) == "table" and extra_headers or {}) do
        if tostring(k):match("^[%w%-]+$") and not tostring(v):find("[\r\n]") then
            lines[#lines + 1] = k .. ": " .. tostring(v)
        end
    end
    if code == 302 then
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

-- Called by UIManager:processZMQs() as an iterator; we handle at most one
-- connection per pass and always end the iteration by returning nil.
function PairServer:waitEvent()
    if not self.server then return nil end
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
