--[[--
Copy connections from one GZreader device to another, over the Wi-Fi.

On the device that has them: Send connections (Settings → Connections, its
setup guide). It shows its name and a 6-digit PIN, answers mDNS for
_gzreader._tcp (gzreader_mdns.lua) and runs a small copy server.

On the device being set up: Copy from another GZreader (its setup guide,
Settings → Connections, the Notes or Calendar tab while not connected). It
lists the GZreader devices sending on the Wi-Fi (or takes an address typed
in), asks for the PIN, shows what the other one has, and copies what's ticked:

- Notes (Memos): the address and access token;
- Calendar: the CalDAV account (address, user name, app password; which of
  its calendars are hidden) and the calendar links;
- Grimmory: the address and user name only. Grimmory gives each device its
  own sign-in (its refresh tokens can't be shared: using one on two devices
  signs both out) and GZreader never keeps your password, so this device
  then signs in itself: the password, or the phone page for single sign-on,
  with everything else filled in.

Each copy is checked by connecting with it (as when typed in). The PIN and
the keys are SPAKE2 (gzreader_spake.lua): nothing secret crosses the Wi-Fi
in the clear, and a wrong PIN can't be tested offline; the sender gives up
after 5 tries and the PIN works for one copy only. Tokens and passwords are
never written to the log.

HTTP on the sender (JSON):
  GET  /gzcopy/hello                       -> { app, v, name, id }
  POST /gzcopy/start { X, name }           -> { id, Y, c, offer = sealed }
  POST /gzcopy/get   { id, c, want = sealed } -> { data = sealed }
]]

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Copy = {
    PORT = 8650,
    MAX_TRIES = 5,
    TIMEOUT = 10 * 60, -- the send screen closes after this long
    REQUEST_TIMEOUT = 30, -- s for an answer (the PIN exchange on a Kindle 3 takes a few)
    HELLO_TIMEOUT = 6,    -- s for "is a GZreader sending there?"
    session = nil,     -- the sending side, while its screen is up
}

local function Spake() return require("gzreader_spake") end
local function Mdns() return require("gzreader_mdns") end
local function host(url) return (tostring(url or ""):gsub("^https?://", ""):gsub("/.*$", "")) end

---------------------------------------------------------------- names

local MODELS = {
    Kindle2 = "Kindle 2", KindleDXG = "Kindle DX Graphite", Kindle3 = "Kindle Keyboard", Kindle4 = "Kindle 4",
    KindleTouch = "Kindle Touch", KindlePaperWhite = "Kindle Paperwhite", KindlePaperWhite2 = "Kindle Paperwhite 2",
    KindlePaperWhite3 = "Kindle Paperwhite 3", KindlePaperWhite4 = "Kindle Paperwhite 4", KindleVoyage = "Kindle Voyage",
    KindleOasis = "Kindle Oasis", KindleBasic = "Kindle", Nook1 = "Nook", NookTouch = "Nook Simple Touch",
}

--- This device's lasting id (6 hex digits, made once).
function Copy.deviceId(plugin)
    local store = plugin.store
    if type(store.device_id) ~= "string" or not store.device_id:match("^%x+$") then
        store.device_id = require("gzreader_pairserver").randomToken(3)
        plugin:save()
    end
    return store.device_id
end

--- "Kindle Paperwhite 3 · 3F2A": what the other device lists.
function Copy.deviceName(plugin)
    local model = MODELS[tostring(Device.model)]
    if not model then
        model = tostring(Device.model or "Kindle"):gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
        if Device.model == "Kindle2" and Device.screen and Device.screen.getWidth and Device.screen:getWidth() > 700 then
            model = "Kindle DX"
        end
    end
    return model .. " · " .. Copy.deviceId(plugin):sub(1, 4):upper()
end

---------------------------------------------------------------- what there is

local function feedName(f)
    if f.name and f.name ~= "" then return f.name end
    if f.own_name and f.own_name ~= "" then return f.own_name end
    return host(f.url) ~= "" and host(f.url) or _("Calendar link")
end

--- What this device could send, without anything secret (shown on the other).
function Copy.offer(plugin)
    local store, out = plugin.store, { name = Copy.deviceName(plugin) }
    if plugin.api and plugin.api:isPaired() then
        out.grimmory = { host = host(store.server), username = store.username }
    end
    local ms = store.memos or {}
    if ms.server and ms.token then out.memos = { host = host(ms.server), user = ms.user } end
    local cs = store.caldav or {}
    if cs.server and cs.username and cs.password then
        out.caldav = { host = host(cs.server), username = cs.username, calendars = #(cs.calendars or {}) }
    end
    out.links = {}
    for i, f in ipairs(store.calendar_feeds or {}) do
        if f.url then out.links[#out.links + 1] = { n = i, name = feedName(f), host = host(f.url) } end
    end
    return out
end

--- Anything to send at all?
function Copy.hasAnything(offer)
    return offer.grimmory ~= nil or offer.memos ~= nil or offer.caldav ~= nil or #offer.links > 0
end

--- The chosen connections, secrets included. want = { grimmory, memos,
--- caldav = bool, links = { n… } }.
function Copy.payload(plugin, want)
    local store, out = plugin.store, {}
    want = type(want) == "table" and want or {}
    if want.grimmory and plugin.api and plugin.api:isPaired() then
        -- (the address and account: Grimmory's sign-in stays on this device)
        out.grimmory = { server = store.server, username = store.username }
    end
    local ms = store.memos or {}
    if want.memos and ms.server and ms.token then out.memos = { server = ms.server, token = ms.token } end
    local cs = store.caldav or {}
    if want.caldav and cs.server and cs.username and cs.password then
        local hidden = {}
        for _i, c in ipairs(cs.calendars or {}) do if c.enabled == false then hidden[#hidden + 1] = c.href end end
        out.caldav = { server = cs.server, username = cs.username, password = cs.password, hidden = hidden }
    end
    local feeds = store.calendar_feeds or {}
    for _i, n in ipairs(type(want.links) == "table" and want.links or {}) do
        local f = feeds[tonumber(n) or 0]
        if f and f.url then
            out.links = out.links or {}
            out.links[#out.links + 1] = { url = f.url, name = f.name, enabled = f.enabled ~= false }
        end
    end
    return out
end

--- What was sent, in words (no secrets): "Notes, the CalDAV account, 2 calendar links".
function Copy.describe(t)
    local parts = {}
    if t.grimmory then parts[#parts + 1] = _("Grimmory's address") end
    if t.memos then parts[#parts + 1] = _("Notes") end
    if t.caldav then parts[#parts + 1] = _("the CalDAV account") end
    local n = t.links and #t.links or 0
    if n == 1 then parts[#parts + 1] = _("1 calendar link") elseif n > 1 then parts[#parts + 1] = T(_("%1 calendar links"), n) end
    return table.concat(parts, ", ")
end

---------------------------------------------------------------- sending

local function json(code, t) return code, "application/json", JSON.encode(t) end

--- The copy server's answers. S = { plugin, pin, tries, pending, on_status, on_sent }.
function Copy.serve(S, method, path, body)
    local plugin = S.plugin
    if method == "GET" and path == "/gzcopy/hello" then
        return json(200, { app = "GZreader", v = 1, name = Copy.deviceName(plugin), id = Copy.deviceId(plugin) })
    end
    if method ~= "POST" then return json(404, { error = "not found" }) end
    local ok, req = pcall(JSON.decode, body or "")
    if not ok or type(req) ~= "table" then return json(400, { error = "bad request" }) end
    if path == "/gzcopy/start" then
        if S.tries >= Copy.MAX_TRIES then return json(429, { error = "tries" }) end
        S.tries = S.tries + 1
        local b = Spake().new("B", S.pin)
        local okf = b:finish(req.X)
        if not okf then return json(400, { error = "bad request" }) end
        local who = tostring(req.name or ""):gsub("[%c]", ""):sub(1, 60)
        S.pending = { b = b, id = require("gzreader_pairserver").randomToken(8), name = who ~= "" and who or _("another GZreader") }
        Log.info("copy: " .. S.pending.name .. " is connecting (try " .. S.tries .. ")")
        if S.on_status then pcall(S.on_status, T(_("%1 is connecting…"), S.pending.name)) end
        local offer = Spake().seal(b.key, JSON.encode(Copy.offer(plugin)), "offer")
        if S.tries >= Copy.MAX_TRIES and S.on_tries then pcall(S.on_tries) end
        return json(200, { id = S.pending.id, Y = b:message(), c = b:confirmation(), offer = offer })
    end
    if path == "/gzcopy/get" then
        local p = S.pending
        if not p or req.id ~= p.id then return json(409, { error = "start again" }) end
        if not p.b:checkConfirmation(req.c) then
            S.pending = nil
            Log.info("copy: wrong PIN from " .. p.name)
            if S.on_status then pcall(S.on_status, T(_("%1 entered a different PIN."), p.name)) end
            return json(403, { error = "pin" })
        end
        local wtxt = Spake().open(p.b.key, req.want, "want")
        local okw, want = pcall(JSON.decode, wtxt or "")
        if not okw or type(want) ~= "table" then return json(400, { error = "bad request" }) end
        local payload = Copy.payload(plugin, want)
        S.pending = nil
        -- one PIN, one copy: a new PIN for the next one (the screen shows it)
        S.pin, S.tries = Spake().pin(), 0
        S.sent = { to = p.name, what = Copy.describe(payload), pin = S.pin }
        Log.info("copy: sent to " .. p.name .. ": " .. S.sent.what)
        if S.on_sent then UIManager:nextTick(function() pcall(S.on_sent, S.sent) end) end
        return json(200, { data = Spake().seal(p.b.key, JSON.encode(payload), "payload") })
    end
    return json(404, { error = "not found" })
end

--- The full screen the sender shows (its name, the PIN, what happens).
local function sendScreen(opts)
    local Blitbuffer = require("ffi/blitbuffer")
    local Button = require("ui/widget/button")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Screen = Device.screen
    local W = InputContainer:extend{ name = "copy send screen", modal = true }
    function W:init()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        if Device:hasKeys() then self.key_events.Cancel = { { Device.input.group.Back } } end
        self:build()
    end
    function W:build()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local tw = math.floor(sw * 0.86)
        local gap = VerticalSpan:new{ width = Size.span.vertical_large * 2 }
        local pin = opts.pin:sub(1, 3) .. " " .. opts.pin:sub(4)
        local group = VerticalGroup:new{
            align = "center",
            TextBoxWidget:new{ text = _("Send connections to another GZreader"), face = Font:getFace("tfont", 24),
                width = tw, alignment = "center" },
            gap,
            TextBoxWidget:new{ text = _("On the other GZreader, choose Copy from another GZreader (in its setup guide, Settings → Connections, or the Notes or Calendar tab), pick this one and enter the PIN:"),
                face = Font:getFace("cfont", 18), width = tw, alignment = "center" },
            gap,
            TextWidget:new{ text = opts.name, face = Font:getFace("cfont", 20), bold = true, max_width = tw },
            VerticalSpan:new{ width = Size.span.vertical_large },
            TextWidget:new{ text = pin, face = Font:getFace("tfont", 56), bold = true },
            gap,
            TextBoxWidget:new{ text = opts.what, face = Font:getFace("cfont", 16), width = tw, alignment = "center" },
            gap,
            TextBoxWidget:new{ text = self.status or _("Waiting for the other GZreader…"), face = Font:getFace("cfont", 18),
                bold = true, width = tw, alignment = "center" },
            gap,
            TextBoxWidget:new{ text = T(_("Not in its list? Choose Type its address there and enter %1"), opts.address),
                face = Font:getFace("smallinfofont", 15), width = tw, alignment = "center", fgcolor = Blitbuffer.COLOR_DARK_GRAY },
            gap,
        }
        if Device:isTouchDevice() then
            table.insert(group, Button:new{ text = self.done and _("Close") or _("Cancel"), width = math.floor(sw * 0.4),
                callback = function() self:onCancel() end })
        else
            table.insert(group, TextBoxWidget:new{ text = _("Press Back to stop."), face = Font:getFace("smallinfofont", 16),
                width = tw, alignment = "center" })
        end
        self[1] = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0,
            width = sw, height = sh, CenterContainer:new{ dimen = Geom:new{ w = sw, h = sh }, group } }
    end
    function W:setStatus(text, done)
        self.status, self.done = text, done
        self:build()
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end
    function W:onShow() UIManager:setDirty(self, function() return "full", self.dimen end) end
    function W:onCloseWidget() UIManager:setDirty(nil, "full") end
    function W:onCancel()
        UIManager:close(self)
        if opts.on_cancel then opts.on_cancel() end
        return true
    end
    return W:new{}
end

--- What the send screen says this device has.
local function offerText(offer)
    local lines = {}
    if offer.grimmory then lines[#lines + 1] = T(_("Grimmory: %1 · %2 (the address and account; the other signs in itself)"), offer.grimmory.host, offer.grimmory.username or "?") end
    if offer.memos then lines[#lines + 1] = T(_("Notes: %1"), offer.memos.host) end
    if offer.caldav then lines[#lines + 1] = T(_("Calendar: %1 · %2"), offer.caldav.host, offer.caldav.username or "?") end
    if #offer.links > 0 then lines[#lines + 1] = T(_("Calendar links: %1"), #offer.links) end
    return table.concat(lines, "\n")
end

--- Show the PIN and wait for the other device. opts.on_done(sent_or_nil).
function Copy.send(plugin, opts)
    opts = opts or {}
    if Copy.session then return Copy.session end
    local offer = Copy.offer(plugin)
    if not Copy.hasAnything(offer) then
        return UIManager:show(InfoMessage:new{ text = _("Nothing to send yet: connect Grimmory, Notes or a calendar on this Kindle first.") })
    end
    if not Spake().available() then
        return UIManager:show(InfoMessage:new{ text = _("This Kindle's encryption library is missing, so it can't send connections safely.") })
    end
    require("gzreader_net").run(function() Copy.startSending(plugin, opts, offer) end, { reason = "copying connections" })
end

function Copy.startSending(plugin, opts, offer)
    local PairServer = require("gzreader_pairserver")
    local S = { plugin = plugin, pin = Spake().pin(), tries = 0, started = os.time() }
    local server = PairServer:new{ port = Copy.PORT, handler = function(method, path, _headers, body)
        return Copy.serve(S, method, path, body)
    end }
    local ok, err = server:start()
    if not ok then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start: %1"), tostring(err)) })
    end
    local hint_host = plugin.store.server and plugin.store.server:match("^https?://([^/:]+)")
    local ip = PairServer.localIp(hint_host)
    if not ip then
        server:stop()
        return UIManager:show(InfoMessage:new{ text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") })
    end
    local name = Copy.deviceName(plugin)
    local responder, merr = Mdns().advertise({ name = name, id = Copy.deviceId(plugin), port = server.port, ip = ip,
        version = (pcall(require, "gzreader_update")) and require("gzreader_update").currentVersion() or "" })
    if not responder then Log.warn("copy: mDNS not answering:", tostring(merr)) end
    Copy.session = S
    local screen, timer, finished
    local function finish(sent)
        if finished then return end
        finished = true
        Copy.session = nil
        if timer then UIManager:unschedule(timer) end
        UIManager:removeZMQ(server); server:stop()
        if responder then UIManager:removeZMQ(responder); responder:close() end
        pcall(function() require("gzreader_awake").release("copy") end)
        Log.info("copy: send screen closed", sent and "(sent)" or "")
        if opts.on_done then pcall(opts.on_done, sent) end
    end
    local sopts = {
        name = name, pin = S.pin, what = offerText(offer), address = ip .. (server.port ~= Copy.PORT and (":" .. server.port) or ""),
        on_cancel = function() finish(S.sent) end,
    }
    screen = sendScreen(sopts)
    S.on_status = function(text) screen:setStatus(text) end
    S.on_sent = function(sent)
        -- the PIN was for that copy: the next one takes the new PIN (copying
        -- Notes after the calendars, or to a third device), for 10 more minutes
        sopts.pin = sent.pin or S.pin
        if timer then UIManager:unschedule(timer); UIManager:scheduleIn(Copy.TIMEOUT, timer) end
        screen:setStatus(T(_("Sent to %1: %2.\nTo copy more, use the new PIN."), sent.to, sent.what), true)
    end
    S.on_tries = function()
        screen:setStatus(_("That was the last try with this PIN. To try again, close this and send again (a new PIN)."))
    end
    timer = function()
        UIManager:close(screen)
        finish(S.sent)
    end
    UIManager:scheduleIn(Copy.TIMEOUT, timer)
    UIManager:insertZMQ(server)
    if responder then UIManager:insertZMQ(responder) end
    pcall(function() require("gzreader_awake").hold("copy") end)
    Log.info("copy: sending as " .. name .. " on port " .. server.port)
    UIManager:show(screen)
    return S
end

---------------------------------------------------------------- receiving

--- One request to the other device: code, decoded JSON (or nil, "unreachable").
function Copy.request(dev, method, path, tbl, timeout)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local body = tbl and JSON.encode(tbl) or nil
    local out = {}
    -- (http.open sets http.TIMEOUT on the socket after `create`, so set that:
    -- a device that has stopped sending, behind the Kindle's firewall, never
    -- answers, and 60 s with the screen stuck looks like a freeze)
    local old_timeout = http.TIMEOUT
    http.TIMEOUT = timeout or Copy.REQUEST_TIMEOUT
    local ok, one, code = pcall(http.request, {
        url = string.format("http://%s:%d%s", dev.ip, tonumber(dev.port) or Copy.PORT, path),
        method = method,
        headers = body and { ["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body) } or nil,
        source = body and ltn12.source.string(body) or nil,
        sink = ltn12.sink.table(out),
        create = function() local s = socket.tcp(); s:settimeout(http.TIMEOUT); return s end,
    })
    http.TIMEOUT = old_timeout
    if not ok or one ~= 1 or type(code) ~= "number" then return nil, "unreachable" end
    local okj, data = pcall(JSON.decode, table.concat(out))
    return code, okj and type(data) == "table" and data or {}
end

--- The PIN exchange with `dev` ({ ip, port, name }): a channel, or nil, why
--- ("pin", "tries", "unreachable", "bad").
function Copy.open(plugin, dev, pin)
    local a = Spake().new("A", pin)
    local code, r = Copy.request(dev, "POST", "/gzcopy/start", { X = a:message(), name = Copy.deviceName(plugin) })
    if not code then return nil, "unreachable" end
    if code == 429 then return nil, "tries" end
    if code ~= 200 or type(r.Y) ~= "string" then return nil, "bad" end
    if not a:finish(r.Y) or not a:checkConfirmation(r.c) then return nil, "pin" end
    local okj, offer = pcall(JSON.decode, Spake().open(a.key, r.offer, "offer") or "")
    if not okj or type(offer) ~= "table" then return nil, "bad" end
    offer.links = type(offer.links) == "table" and offer.links or {}
    return { dev = dev, a = a, id = r.id, offer = offer }
end

--- Ask for the chosen connections: the payload, or nil, why.
function Copy.fetch(ch, want)
    local code, r = Copy.request(ch.dev, "POST", "/gzcopy/get",
        { id = ch.id, c = ch.a:confirmation(), want = Spake().seal(ch.a.key, JSON.encode(want), "want") })
    if not code then return nil, "unreachable" end
    if code == 403 then return nil, "pin" end
    if code ~= 200 then return nil, "bad" end
    local okj, data = pcall(JSON.decode, Spake().open(ch.a.key, r.data, "payload") or "")
    if not okj or type(data) ~= "table" then return nil, "bad" end
    return data
end

--- Connect with what came: each checked by connecting. Returns { lines =
--- {…}, grimmory = { server, username } or nil, notes = bool, calendar = bool }.
function Copy.apply(plugin, data)
    local res = { lines = {} }
    local function line(ok, text) res.lines[#res.lines + 1] = (ok and "\u{2713} " or "\u{2717} ") .. text end
    if type(data.memos) == "table" then
        local ok, err = require("gzreader_notes").connect(plugin, data.memos.server, data.memos.token)
        if ok then
            res.notes = true
            line(true, T(_("Notes: connected to Memos as %1."), (plugin.store.memos or {}).user or "?"))
        else
            line(false, T(_("Notes: %1"), tostring(err)))
        end
    end
    local Calendar
    if type(data.caldav) == "table" then
        Calendar = require("gzreader_calendar")
        local c = data.caldav
        local ok, err = Calendar.connect(plugin, c.server, c.username, c.password)
        if ok then
            local hidden = {}
            for _i, href in ipairs(type(c.hidden) == "table" and c.hidden or {}) do hidden[href] = true end
            local cals = (plugin.store.caldav or {}).calendars or {}
            for _i, cal in ipairs(cals) do if hidden[cal.href] then cal.enabled = false end end
            plugin:save()
            res.calendar = true
            line(true, T(_("Calendar: connected, %1 calendars."), #cals))
        else
            line(false, T(_("Calendar: %1"), tostring(err)))
        end
    end
    if type(data.links) == "table" and #data.links > 0 then
        Calendar = Calendar or require("gzreader_calendar")
        local entries = {}
        for _i, l in ipairs(data.links) do entries[#entries + 1] = { url = l.url, name = l.name } end
        local results = Calendar.addFeeds(plugin, entries)
        local by_url = {}
        for _i, l in ipairs(data.links) do by_url[l.url] = l end
        for _i, f in ipairs(Calendar.feeds(plugin)) do
            local l = by_url[f.url]
            if l and l.enabled == false then f.enabled = false end
        end
        plugin:save()
        for _i, r in ipairs(results) do
            line(r.ok, r.ok and T(_("Calendar link: %1"), r.label) or T(_("Calendar link %1: %2"), r.label, tostring(r.err)))
            if r.ok then res.calendar = true end
        end
    end
    if res.calendar then Calendar.calendarsChanged() end
    if type(data.grimmory) == "table" and data.grimmory.server then
        local store = plugin.store
        if plugin.api:isPaired() and store.server == data.grimmory.server and store.username == data.grimmory.username then
            line(true, T(_("Grimmory: already connected as %1."), store.username or "?"))
        else
            res.grimmory = { server = data.grimmory.server, username = data.grimmory.username }
        end
    end
    return res
end

--- Grimmory: sign in on this device with the address and account filled in.
--- `before`: what else was copied (shown above).
function Copy.grimmorySignIn(plugin, g, before)
    local ButtonDialog = require("ui/widget/buttondialog")
    local d
    d = ButtonDialog:new{
        title = (before and before ~= "" and (before .. "\n\n") or "")
            .. T(_("Grimmory gives each device its own sign-in. Sign in on this Kindle as %1 at %2:"), g.username or "?", host(g.server)),
        buttons = {
            { { text = _("Type the password"), callback = function()
                UIManager:close(d)
                plugin:keyboardLogin({ server = g.server, username = g.username })
            end } },
            { { text = _("Single sign-on (phone page)"), callback = function()
                UIManager:close(d)
                require("gzreader_net").run(function()
                    require("gzreader_phone").open(plugin, { section = "grimmory", grimmory_form = { server = g.server, username = g.username } })
                end, { reason = "connecting to Grimmory" })
            end } },
            { { text = _("Later"), callback = function() UIManager:close(d) end } },
        },
    }
    UIManager:show(d)
end

local WHY = {
    pin = _("That PIN didn't match the one on the other GZreader. Check it and try again."),
    tries = _("Too many tries with that PIN. On the other GZreader, close the screen and send again: it shows a new PIN."),
    unreachable = _("Couldn't reach the other GZreader. Is its send screen up (Send connections), and is it on the same Wi-Fi?"),
    bad = _("The other GZreader answered something unexpected. Are both on the same GZreader version?"),
}

local function busy(text)
    local m = InfoMessage:new{ text = text, timeout = 0 }
    UIManager:show(m)
    UIManager:forceRePaint()
    return m
end

--- A list Menu above everything (also the setup guide).
local function listMenu(title, items)
    local Menu = require("ui/widget/menu")
    local m = Menu:new{ title = title, item_table = items, covers_fullscreen = true, is_borderless = true,
        is_popout = false, title_bar_fm_style = true, modal = true }
    m.onMenuSelect = function(_self, item) if item.callback then item.callback() end return true end
    return m
end

--- Default ticks: opts.only ("notes", "calendar", "grimmory") or what this
--- device doesn't have yet.
function Copy.defaults(plugin, offer, only)
    local store = plugin.store
    local has = {
        grimmory = plugin.api and plugin.api:isPaired(),
        memos = (store.memos or {}).token ~= nil,
        caldav = (store.caldav or {}).password ~= nil,
    }
    local want = { links = {} }
    want.grimmory = offer.grimmory ~= nil and (only == "grimmory" or (only == nil and not has.grimmory))
    want.memos = offer.memos ~= nil and (only == "notes" or (only == nil and not has.memos))
    want.caldav = offer.caldav ~= nil and (only == "calendar" or (only == nil and not has.caldav))
    local mine = {}
    for _i, f in ipairs(store.calendar_feeds or {}) do mine[f.name or f.own_name or ""] = true end
    for _i, l in ipairs(offer.links) do
        if (only == nil or only == "calendar") and not mine[l.name] then want.links[l.n] = true end
    end
    return want
end

--- What to copy: a list to tick, then Copy.
function Copy.choose(plugin, ch, opts)
    local offer, want = ch.offer, Copy.defaults(plugin, ch.offer, opts.only)
    local menu
    local function mark(on) return on and _("copy") or _("skip") end
    local items
    local function rebuild()
        items = {}
        local function toggle(item, get, set)
            item.mandatory = mark(get())
            item.dim = not get()
            item.callback = function()
                set(not get())
                rebuild()
                menu:switchItemTable(nil, items)
            end
            items[#items + 1] = item
        end
        if offer.grimmory then
            toggle({ text = T(_("Grimmory: %1 · %2 (then sign in here)"), offer.grimmory.host, offer.grimmory.username or "?") },
                function() return want.grimmory end, function(v) want.grimmory = v end)
        end
        if offer.memos then
            toggle({ text = T(_("Notes: Memos at %1"), offer.memos.host) }, function() return want.memos end, function(v) want.memos = v end)
        end
        if offer.caldav then
            toggle({ text = T(_("Calendar: CalDAV %1 · %2"), offer.caldav.host, offer.caldav.username or "?") },
                function() return want.caldav end, function(v) want.caldav = v end)
        end
        for _i, l in ipairs(offer.links) do
            toggle({ text = T(_("Calendar link: %1"), l.name) }, function() return want.links[l.n] == true end,
                function(v) want.links[l.n] = v or nil end)
        end
        items[#items + 1] = { text = _("Copy the ones marked copy"), bold = true, callback = function()
            local list = {}
            for n in pairs(want.links) do list[#list + 1] = n end
            table.sort(list)
            local w = { grimmory = want.grimmory or nil, memos = want.memos or nil, caldav = want.caldav or nil, links = list }
            if not (w.grimmory or w.memos or w.caldav or #list > 0) then
                return UIManager:show(InfoMessage:new{ text = _("Nothing is marked copy."), timeout = 3 })
            end
            UIManager:close(menu)
            Copy.copy(plugin, ch, w, opts)
        end }
        if #items == 1 then
            items = { { text = T(_("%1 has nothing to send yet."), offer.name or "?"), select_enabled = false } }
        end
    end
    rebuild()
    menu = listMenu(T(_("Copy from %1"), offer.name or ch.dev.name or "?"), items)
    UIManager:show(menu)
end

function Copy.copy(plugin, ch, want, opts)
    local msg = busy(_("Copying…"))
    local data, err = Copy.fetch(ch, want)
    if not data then
        UIManager:close(msg)
        return UIManager:show(InfoMessage:new{ text = WHY[err] or tostring(err) })
    end
    local ok, res = pcall(Copy.apply, plugin, data)
    UIManager:close(msg)
    if not ok then
        Log.warn("copy: couldn't apply:", tostring(res))
        return UIManager:show(InfoMessage:new{ text = _("Something went wrong while connecting.") })
    end
    Log.info("copy: received from " .. tostring(ch.offer.name) .. ": " .. Copy.describe(data))
    local text = table.concat(res.lines, "\n")
    if res.grimmory then
        Copy.grimmorySignIn(plugin, res.grimmory, text)
    else
        UIManager:show(InfoMessage:new{ text = text ~= "" and text or _("Done.") })
    end
    if opts.on_done then pcall(opts.on_done, res) end
end

--- The PIN for `dev`, then what to copy.
function Copy.askPin(plugin, dev, opts)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{
        title = T(_("PIN shown on %1"), dev.name or dev.ip),
        input_hint = "123456",
        input_type = "number",
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local pin = (d:getInputText() or ""):gsub("%D", "")
                UIManager:close(d)
                if #pin ~= 6 then
                    return UIManager:show(InfoMessage:new{ text = _("The PIN has 6 digits."), timeout = 3 })
                end
                local msg = busy(T(_("Connecting to %1…"), dev.name or dev.ip))
                local ch, why = Copy.open(plugin, dev, pin)
                UIManager:close(msg)
                if not ch then return UIManager:show(InfoMessage:new{ text = WHY[why] or tostring(why) }) end
                Copy.choose(plugin, ch, opts)
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- "192.168.1.5" or "192.168.1.5:8650": a device to ask (it says its name).
function Copy.typeAddress(plugin, opts)
    local InputDialog = require("ui/widget/inputdialog")
    local d
    d = InputDialog:new{
        title = _("The other GZreader's address"),
        input_hint = "192.168.1.5",
        description = _("Shown at the bottom of its send screen."),
        buttons = { {
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
            { text = _("Next"), is_enter_default = true, callback = function()
                local text = (d:getInputText() or ""):gsub("%s", "")
                UIManager:close(d)
                local ip, port = text:match("^(%d+%.%d+%.%d+%.%d+):?(%d*)$")
                if not ip then
                    return UIManager:show(InfoMessage:new{ text = _("That doesn't look like an address (four numbers with dots, e.g. 192.168.1.5)."), timeout = 4 })
                end
                local dev = { ip = ip, port = tonumber(port) or Copy.PORT }
                local msg = busy(T(_("Connecting to %1…"), text))
                local code, hello = Copy.request(dev, "GET", "/gzcopy/hello", nil, Copy.HELLO_TIMEOUT)
                UIManager:close(msg)
                if code ~= 200 or hello.app ~= "GZreader" then
                    return UIManager:show(InfoMessage:new{ text = WHY.unreachable })
                end
                dev.name = hello.name
                Copy.askPin(plugin, dev, opts)
            end },
        } },
    }
    UIManager:show(d)
    d:onShowKeyboard()
end

--- List the GZreader devices sending on this Wi-Fi; pick one.
--- opts = { only = "notes" | "calendar" | "grimmory", on_done = function(res) }.
function Copy.receive(plugin, opts)
    opts = opts or {}
    if not Spake().available() then
        return UIManager:show(InfoMessage:new{ text = _("This Kindle's encryption library is missing, so it can't copy connections safely.") })
    end
    require("gzreader_net").run(function() Copy.pick(plugin, opts) end, { reason = "copying connections" })
end

function Copy.pick(plugin, opts)
    local menu, browser, poller
    local function stop()
        if poller then UIManager:unschedule(poller); poller = nil end
        if browser then browser:close(); browser = nil end
    end
    local function items(searching, devices)
        local list = {}
        for _i, dev in ipairs(devices or {}) do
            list[#list + 1] = { text = dev.name, mandatory = dev.ip, callback = function()
                stop()
                UIManager:close(menu)
                Copy.askPin(plugin, dev, opts)
            end }
        end
        if searching then
            list[#list + 1] = { text = _("Looking for GZreader devices on this Wi-Fi…"), select_enabled = false }
        elseif #list == 0 then
            list[#list + 1] = { text = _("None found. On the other GZreader choose Send connections (Settings → Connections, or its setup guide), then look again."), select_enabled = false }
        end
        list[#list + 1] = { text = _("Look again"), callback = function()
            stop()
            Copy.look(menu, items, function(b, p) browser, poller = b, p end)
        end }
        list[#list + 1] = { text = _("Type its address…"), callback = function()
            stop()
            UIManager:close(menu)
            Copy.typeAddress(plugin, opts)
        end }
        return list
    end
    menu = listMenu(_("Copy from another GZreader"), items(true))
    local orig_close = menu.onCloseWidget
    menu.onCloseWidget = function(m, ...)
        stop()
        if orig_close then return orig_close(m, ...) end
    end
    UIManager:show(menu)
    Copy.look(menu, items, function(b, p) browser, poller = b, p end)
end

--- Browse for a few seconds, updating `menu` as devices answer.
function Copy.look(menu, items, keep)
    local browser, err = Mdns().browse({ duration = 5 })
    if not browser then
        Log.warn("copy: can't look for devices:", tostring(err))
        menu:switchItemTable(nil, items(false, {}))
        return
    end
    local shown = -1
    local poller
    poller = function()
        browser:poll()
        local devices = browser:devices()
        local done = browser:done()
        if #devices ~= shown or done then
            shown = #devices
            menu:switchItemTable(nil, items(not done, devices))
        end
        if done then
            browser:close()
            keep(nil, nil)
        else
            UIManager:scheduleIn(0.3, poller)
        end
    end
    keep(browser, poller)
    UIManager:scheduleIn(0.3, poller)
end

return Copy
