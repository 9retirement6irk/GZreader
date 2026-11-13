--[[--
Finding other GZreader devices on the Wi-Fi with mDNS / DNS-SD (multicast
DNS, what AirPrint and Chromecast use), for copying connections between them
(gzreader_copy.lua).

- A device sending its connections answers for the service
  _gzreader._tcp.local: its name ("Kindle Paperwhite 3 · 3F2A"), the port of
  its copy server and its address. Only while the send screen is up.
- A device receiving asks for that service ("legacy unicast": the question
  goes to the multicast group from an ordinary port, the answers come back to
  that port) a few times and lists what answers.
- The House tab looks for Home Assistant the same way (its own service,
  _home-assistant._tcp.local: browse with opts.service and a collector from
  M.collectService).

Nothing secret is in the answers: the name, the port, GZreader's version.
The Kindle's firewall drops what it isn't told to let in: the ports are
opened while in use, and closed again (plain rules, as for the phone page).
]]

local Device = require("device")
local socket = require("socket")

local M = {
    GROUP = "224.0.0.251",
    PORT = 5353,
    SERVICE = "_gzreader._tcp.local",
    HA_SERVICE = "_home-assistant._tcp.local",
    TTL = 120,
}

local T_A, T_PTR, T_TXT, T_SRV, T_ANY = 1, 12, 16, 33, 255

local function firewall(action, rules)
    if not Device:isKindle() then return end
    for _i, r in ipairs(rules) do
        os.execute(string.format("iptables %s %s -j ACCEPT 2>/dev/null", action, r))
    end
end

---------------------------------------------------------------- the wire format

local function u16(n) return string.char(bit.band(bit.rshift(n, 8), 255), bit.band(n, 255)) end
local function u32(n)
    return string.char(bit.band(bit.rshift(n, 24), 255), bit.band(bit.rshift(n, 16), 255),
        bit.band(bit.rshift(n, 8), 255), bit.band(n, 255))
end
local function rd16(s, i) return s:byte(i) * 256 + s:byte(i + 1) end

--- "a.b.local" as DNS labels (each up to 63 bytes; the first may hold dots
--- when it's an instance name: pass it as a table { "My Kindle", "_gzreader", … }).
function M.encodeName(name)
    local labels = type(name) == "table" and name or {}
    if type(name) == "string" then for l in name:gmatch("[^.]+") do labels[#labels + 1] = l end end
    local out = {}
    for _i, l in ipairs(labels) do
        l = l:sub(1, 63)
        out[#out + 1] = string.char(#l) .. l
    end
    return table.concat(out) .. "\0"
end

--- Read a (possibly compressed) name at i: labels (a table), next index.
function M.decodeName(s, i)
    local labels, jumped, next_i, guard = {}, false, nil, 0
    while true do
        guard = guard + 1
        if guard > 64 or i > #s then return nil end
        local len = s:byte(i)
        if len == 0 then
            if not jumped then next_i = i + 1 end
            break
        elseif bit.band(len, 0xC0) == 0xC0 then
            if i + 1 > #s then return nil end
            if not jumped then next_i = i + 2 end
            i = bit.band(len, 0x3F) * 256 + s:byte(i + 1) + 1
            jumped = true
        else
            labels[#labels + 1] = s:sub(i + 1, i + len)
            i = i + 1 + len
        end
    end
    return labels, next_i
end

local function joined(labels) return table.concat(labels, "."):lower() end

--- A DNS message: { id, response = bool, questions = { {name (labels), type, unicast} },
--- answers = { {name, type, ttl, data (raw), at (index of data)} } } or nil.
function M.parse(s)
    if type(s) ~= "string" or #s < 12 then return nil end
    local msg = { id = rd16(s, 1), response = bit.band(s:byte(3), 0x80) ~= 0, questions = {}, answers = {} }
    local qd, an, ns, ar = rd16(s, 5), rd16(s, 7), rd16(s, 9), rd16(s, 11)
    local i = 13
    for _q = 1, qd do
        local name, ni = M.decodeName(s, i)
        if not name or ni + 3 > #s then return nil end
        local qclass = rd16(s, ni + 2)
        msg.questions[#msg.questions + 1] = { name = name, type = rd16(s, ni), unicast = bit.band(qclass, 0x8000) ~= 0 }
        i = ni + 4
    end
    for _r = 1, an + ns + ar do
        local name, ni = M.decodeName(s, i)
        if not name or ni + 9 > #s then return msg end
        local rtype, ttl = rd16(s, ni), rd16(s, ni + 4) * 65536 + rd16(s, ni + 6)
        local len = rd16(s, ni + 8)
        local at = ni + 10
        if at + len - 1 > #s then return msg end
        msg.answers[#msg.answers + 1] = { name = name, type = rtype, ttl = ttl, data = s:sub(at, at + len - 1), at = at }
        i = at + len
    end
    return msg
end

local function record(name, rtype, flush, ttl, data)
    return M.encodeName(name) .. u16(rtype) .. u16(flush and 0x8001 or 0x0001) .. u32(ttl) .. u16(#data) .. data
end

local function txt(fields)
    local out = {}
    for _i, kv in ipairs(fields) do
        local s = (kv[1] .. "=" .. tostring(kv[2])):sub(1, 255)
        out[#out + 1] = string.char(#s) .. s
    end
    return table.concat(out)
end

local function ipBytes(ip)
    local a, b, c, d = tostring(ip):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    return string.char(tonumber(a), tonumber(b), tonumber(c), tonumber(d))
end

---------------------------------------------------------------- answering

--- svc = { name, id, port, ip, version }: what to answer.
local function instanceLabels(svc)
    local l = { svc.name }
    for part in M.SERVICE:gmatch("[^.]+") do l[#l + 1] = part end
    return l
end
local function hostName(svc) return "gzreader-" .. tostring(svc.id):lower() .. ".local" end

--- The answer to `q` (a parsed query), or nil if it isn't about us.
function M.answer(svc, q, legacy)
    local inst = instanceLabels(svc)
    local inst_s, host = joined(inst), hostName(svc)
    local want = {}
    for _i, question in ipairs(q.questions) do
        local n, t = joined(question.name), question.type
        if n == M.SERVICE and (t == T_PTR or t == T_ANY) then want.ptr = true end
        if n == inst_s and (t == T_SRV or t == T_TXT or t == T_ANY) then want.srv = true end
        if n == host and (t == T_A or t == T_ANY) then want.a = true end
    end
    if not (want.ptr or want.srv or want.a) then return nil end
    -- legacy unicast: no cache-flush bit, short lifetimes, the question echoed
    local ttl = legacy and 10 or M.TTL
    local flush = not legacy
    local ans, add = {}, {}
    local srv = record(inst, T_SRV, flush, ttl, u16(0) .. u16(0) .. u16(svc.port) .. M.encodeName(host))
    local text = record(inst, T_TXT, flush, ttl, txt({ { "v", 1 }, { "id", svc.id }, { "gz", svc.version or "" } }))
    local a = ipBytes(svc.ip) and record(host, T_A, flush, ttl, ipBytes(svc.ip)) or nil
    if want.ptr then
        ans[#ans + 1] = record(M.SERVICE, T_PTR, false, ttl, M.encodeName(inst))
        add[#add + 1] = srv; add[#add + 1] = text; add[#add + 1] = a
    elseif want.srv then
        ans[#ans + 1] = srv; ans[#ans + 1] = text; add[#add + 1] = a
    else
        ans[#ans + 1] = a
    end
    local questions = ""
    local qd = 0
    if legacy then
        for _i, question in ipairs(q.questions) do
            questions = questions .. M.encodeName(question.name) .. u16(question.type) .. u16(1)
            qd = qd + 1
        end
    end
    return u16(legacy and q.id or 0) .. u16(0x8400) .. u16(qd) .. u16(#ans) .. u16(0) .. u16(#add)
        .. questions .. table.concat(ans) .. table.concat(add)
end

--- Answer for svc while it's open; poll with :waitEvent() (UIManager's ZMQ
--- list) or :poll(). Returns the responder, or nil, err.
function M.advertise(svc, opts)
    opts = opts or {}
    local udp = (socket.udp4 or socket.udp)()
    if not udp then return nil, "no socket" end
    pcall(udp.setoption, udp, "reuseaddr", true)
    pcall(udp.setoption, udp, "reuseport", true)
    local ok, err = udp:setsockname(opts.bind or "*", opts.port or M.PORT)
    if not ok then udp:close(); return nil, err end
    if not opts.no_multicast then
        local okm, merr = pcall(udp.setoption, udp, "ip-add-membership", { multiaddr = M.GROUP, interface = "0.0.0.0" })
        if not okm then udp:close(); return nil, merr end
        pcall(udp.setoption, udp, "ip-multicast-ttl", 255)
        pcall(udp.setoption, udp, "ip-multicast-loop", true)
    end
    udp:settimeout(0)
    local rules = { "INPUT -p udp --dport " .. (opts.port or M.PORT), "OUTPUT -p udp --sport " .. (opts.port or M.PORT) }
    firewall("-A", rules)
    local r = { svc = svc, udp = udp, answered = 0 }
    function r:poll()
        for _i = 1, 16 do
            local data, ip, port = self.udp:receivefrom()
            if not data then return end
            local q = M.parse(data)
            if q and not q.response and #q.questions > 0 then
                local legacy = tonumber(port) ~= M.PORT
                local unicast = legacy
                for _j, question in ipairs(q.questions) do unicast = unicast or question.unicast end
                local reply = M.answer(self.svc, q, legacy)
                if reply then
                    if unicast then self.udp:sendto(reply, ip, port) else self.udp:sendto(reply, M.GROUP, M.PORT) end
                    self.answered = self.answered + 1
                end
            end
        end
    end
    function r:waitEvent() self:poll() end
    function r:announce()
        local reply = M.answer(self.svc, { id = 0, questions = { { name = { "_gzreader", "_tcp", "local" }, type = T_PTR } } }, false)
        if reply and not opts.no_multicast then pcall(self.udp.sendto, self.udp, reply, M.GROUP, M.PORT) end
    end
    function r:close()
        if not self.udp then return end
        pcall(self.udp.setoption, self.udp, "ip-drop-membership", { multiaddr = M.GROUP, interface = "0.0.0.0" })
        self.udp:close()
        self.udp = nil
        firewall("-D", rules)
    end
    r:announce()
    return r
end

---------------------------------------------------------------- asking

local function query(id, service)
    return u16(id) .. u16(0) .. u16(1) .. u16(0) .. u16(0) .. u16(0)
        .. M.encodeName(service or M.SERVICE) .. u16(T_PTR) .. u16(0x8001) -- (QU: answer me directly)
end
M._query = query -- (tests)

--- A response's records: { ptr = { instance labels }, srv = { [name] = { port,
--- target } }, txt = { [name] = { k = v } }, a = { [host] = ip } } for `service`.
local function records(msg, data, service)
    local out = { ptr = {}, srv = {}, txt = {}, a = {} }
    for _i, r in ipairs(msg.answers) do
        local n = table.concat(r.name, "."):lower()
        if r.type == T_PTR and n == service then
            local inst = M.decodeName(data, r.at)
            if inst then out.ptr[#out.ptr + 1] = inst end
        elseif r.type == T_SRV and #r.data >= 7 then
            out.srv[n] = { port = rd16(r.data, 5), target = table.concat(M.decodeName(data, r.at + 6) or {}, "."):lower() }
        elseif r.type == T_TXT then
            local t, i = {}, 1
            while i <= #r.data do
                local len = r.data:byte(i)
                local k, v = r.data:sub(i + 1, i + len):match("^([^=]+)=(.*)$")
                if k then t[k] = v end
                i = i + 1 + len
            end
            out.txt[n] = t
        elseif r.type == T_A and #r.data == 4 then
            out.a[n] = table.concat({ r.data:byte(1, 4) }, ".")
        end
    end
    return out
end

--- A collector for any service's answers (M.browse's opts.collect): merged
--- into `found` (key = instance name) as { name, port, ip, txt = { k = v } }.
function M.collectService(service)
    service = service:lower()
    return function(found, data, from)
        local msg = M.parse(data)
        if not msg or not msg.response then return end
        local rec = records(msg, data, service)
        for _i, inst in ipairs(rec.ptr) do
            local key = table.concat(inst, "."):lower()
            local srv = rec.srv[key]
            if srv then
                found[key] = { name = inst[1], port = srv.port, ip = rec.a[srv.target] or from, txt = rec.txt[key] or {} }
            end
        end
    end
end

--- What a response says about GZreader devices: merged into `found`
--- (key = instance name) as { name, id, port, ip, version }. `from` = the
--- address it came from (used when it has no A record).
function M.collect(found, data, from)
    local msg = M.parse(data)
    if not msg or not msg.response then return end
    local hosts, srvs, txts, instances = {}, {}, {}, {}
    for _i, r in ipairs(msg.answers) do
        local n = joined(r.name)
        if r.type == T_PTR and n == M.SERVICE then
            local inst = M.decodeName(data, r.at)
            if inst then instances[#instances + 1] = inst end
        elseif r.type == T_SRV and #r.data >= 7 then
            srvs[n] = { port = rd16(r.data, 5), target = joined(M.decodeName(data, r.at + 6) or {}) }
        elseif r.type == T_TXT then
            local t, i = {}, 1
            while i <= #r.data do
                local len = r.data:byte(i)
                local k, v = r.data:sub(i + 1, i + len):match("^([^=]+)=(.*)$")
                if k then t[k] = v end
                i = i + 1 + len
            end
            txts[n] = t
        elseif r.type == T_A and #r.data == 4 then
            hosts[n] = table.concat({ r.data:byte(1, 4) }, ".")
        end
    end
    for _i, inst in ipairs(instances) do
        local key = joined(inst)
        local srv, t = srvs[key], txts[key] or {}
        if srv and t.v then
            found[key] = { name = inst[1], id = t.id, version = t.gz, port = srv.port,
                ip = from or hosts[srv.target] }
        end
    end
end

--- Look for GZreader devices: asks now and again after 1 and 3 s.
--- Poll the returned browser (:poll() / :waitEvent()); :devices() lists what
--- answered so far; :close() when done. opts.service and opts.collect: look
--- for another service (M.collectService(service)).
function M.browse(opts)
    opts = opts or {}
    local udp = (socket.udp4 or socket.udp)()
    if not udp then return nil, "no socket" end
    local ok, err = udp:setsockname("*", 0)
    if not ok then udp:close(); return nil, err end
    pcall(udp.setoption, udp, "ip-multicast-ttl", 255)
    pcall(udp.setoption, udp, "ip-multicast-loop", true)
    udp:settimeout(0)
    local port = select(2, udp:getsockname())
    local rules = { "INPUT -p udp --dport " .. tostring(port), "OUTPUT -p udp --dport " .. (opts.port or M.PORT) }
    firewall("-A", rules)
    local b = { udp = udp, found = {}, started = socket.gettime(), sent = 0, id = math.random(1, 65535) }
    local SCHEDULE = { 0, 1, 3 }
    function b:poll()
        if not self.udp then return end
        local now = socket.gettime() - self.started
        while SCHEDULE[self.sent + 1] and now >= SCHEDULE[self.sent + 1] do
            pcall(self.udp.sendto, self.udp, query(self.id, opts.service), opts.to or M.GROUP, opts.port or M.PORT)
            self.sent = self.sent + 1
        end
        for _i = 1, 32 do
            local data, ip = self.udp:receivefrom()
            if not data then break end
            local collect = opts.collect or M.collect
            collect(self.found, data, ip)
        end
    end
    function b:waitEvent() self:poll() end
    function b:devices()
        local list = {}
        for _k, d in pairs(self.found) do list[#list + 1] = d end
        table.sort(list, function(x, y) return tostring(x.name) < tostring(y.name) end)
        return list
    end
    function b:done() return socket.gettime() - self.started > (opts.duration or 5) end
    function b:close()
        if not self.udp then return end
        self.udp:close()
        self.udp = nil
        firewall("-D", rules)
    end
    b:poll()
    return b
end

return M
