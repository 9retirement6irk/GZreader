--[[--
HTTPS connections that check the server's certificate.

LuaSec (KOReader's ssl.https) connects with verify = "none" unless told
otherwise, so a connection to "github.com" is encrypted but nobody checks it
really is GitHub: anyone on the same Wi-Fi could answer instead. The updater
installs what it downloads, so its connections go through here:

  * the certificate chain must lead to one of the authorities in KOReader's
    own list (data/ca-bundle.crt, the same list browsers trust);
  * the certificate must name the host asked for (subjectAltName, or the
    common name when it has none; "*.example.com" covers one label);
  * dates: a Nook's clock runs down to 2000 and a DX's to 1970, so every
    certificate would look "not yet valid" there. When this device's clock
    is before CLOCK_FLOOR (it can't be right then), date errors alone are let
    through; any other error still refuses the connection.

Tls.create(host) is a LuaSocket `create` function (the request's `create`
field): http.request then makes its connection through it.
]]

local socket = require("socket")

local Tls = {
    -- before this, the device's clock is wrong (this build is newer than that)
    CLOCK_FLOOR = os.time{ year = 2026, month = 1, day = 1, hour = 0 },
    TIME_ERRORS = { ["certificate has expired"] = true, ["certificate is not yet valid"] = true },
    cafile = nil, -- (tests: another list of authorities)
    now = os.time, -- (tests)
    TIMEOUT = 60,
}

--- KOReader's list of certificate authorities.
function Tls.bundle()
    if Tls.cafile then return Tls.cafile end
    local ok, DataStorage = pcall(require, "datastorage")
    local dir = ok and DataStorage:getDataDir() or "."
    return dir .. "/data/ca-bundle.crt"
end

--- Does a name from a certificate (maybe "*.example.com") cover `host`?
function Tls.hostMatches(pattern, host)
    if type(pattern) ~= "string" or type(host) ~= "string" then return false end
    pattern, host = pattern:lower():gsub("%.$", ""), host:lower():gsub("%.$", "")
    if pattern == host then return true end
    local rest = pattern:match("^%*%.(.+)$")
    if not rest or not rest:find(".", 1, true) then return false end -- (no "*" or "*.com")
    local first, tail = host:match("^([^.]+)%.(.+)$")
    return first ~= nil and tail == rest
end

--- The host names a certificate is for.
function Tls.certNames(cert)
    local names = {}
    local ok, ext = pcall(cert.extensions, cert)
    local san = ok and type(ext) == "table" and ext["2.5.29.17"]
    if type(san) == "table" and type(san.dNSName) == "table" then
        for _i, n in ipairs(san.dNSName) do names[#names + 1] = n end
    end
    if #names == 0 then
        local oks, subject = pcall(cert.subject, cert)
        for _i, part in ipairs(oks and type(subject) == "table" and subject or {}) do
            if part.name == "commonName" or part.name == "CN" then names[#names + 1] = part.value end
        end
    end
    return names
end

--- After the handshake: is this connection really to `host`? true, or nil and why.
function Tls.check(sock, host)
    local ok, errs = sock:getpeerverification()
    if not ok then
        local clock_wrong = Tls.now() < Tls.CLOCK_FLOOR
        local any = false
        for _depth, list in pairs(type(errs) == "table" and errs or {}) do
            for _i, e in ipairs(type(list) == "table" and list or { list }) do
                any = true
                if not (clock_wrong and Tls.TIME_ERRORS[e]) then
                    return nil, "certificate not trusted (" .. tostring(e) .. ")"
                end
            end
        end
        if not any then return nil, "certificate not verified" end
    end
    local cert = sock:getpeercertificate()
    if not cert then return nil, "no certificate" end
    local names = Tls.certNames(cert)
    for _i, n in ipairs(names) do
        if Tls.hostMatches(n, host) then return true end
    end
    return nil, "certificate is for " .. (#names > 0 and table.concat(names, ", ") or "no host name") .. ", not " .. tostring(host)
end

local function reg(conn)
    local mt = getmetatable(conn.sock).__index
    for name, method in pairs(mt) do
        if type(method) == "function" then
            conn[name] = function(self, ...) return method(self.sock, ...) end
        end
    end
end

--- A LuaSocket `create` for an HTTPS request to `host`: the connection is
--- refused unless the certificate checks out. nil and why when it can't be
--- checked at all (no list of authorities).
function Tls.create(host)
    local okl, ssl = pcall(require, "ssl")
    if not okl then return nil, "no TLS library" end
    local cafile = Tls.bundle()
    local f = io.open(cafile, "r")
    if not f then return nil, "can't check certificates: " .. cafile .. " is missing" end
    f:close()
    local params = {
        mode = "client", protocol = "any",
        options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
        verify = { "peer" }, verifyext = { "lsec_continue" }, -- (the errors are read after the handshake)
        cafile = cafile,
    }
    return function()
        local conn = { sock = socket.try(socket.tcp()) }
        local st = getmetatable(conn.sock).__index.settimeout
        function conn:settimeout(...) return st(self.sock, ...) end
        function conn:close() return self.sock:close() end -- (LuaSocket closes when connect fails)
        function conn:connect(h, port)
            local okc, err = self.sock:connect(h, port)
            if not okc then return nil, err end
            local wrapped, werr = ssl.wrap(self.sock, params)
            if not wrapped then self.sock:close(); return nil, werr end
            self.sock = wrapped
            self.sock:sni(host)
            self.sock:settimeout(Tls.TIMEOUT)
            local okh, herr = self.sock:dohandshake()
            if not okh then self.sock:close(); return nil, herr end
            local good, why = Tls.check(self.sock, host)
            if not good then self.sock:close(); return nil, why end
            reg(self)
            return 1
        end
        return conn
    end
end

return Tls
