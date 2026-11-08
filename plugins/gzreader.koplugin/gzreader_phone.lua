--[[--
Set up the Kindle from a browser (a phone's or a computer's): one page,
opened with a QR code or by typing the Kindle's address, for every connection
and for sending books.

- Grimmory: sign in with a password or single sign-on, or disconnect.
- Notes (Memos): address and access token, or disconnect.
- Calendar: a CalDAV account (connect, disconnect, show or hide each of its
  calendars) and calendar links (add, rename, replace the link, show or hide,
  remove).
- Send books: files from the browser go into the GZreader folder.
- Diagnostics (while diagnostic logging is on): download the log.

Two ways in, both while the page is on the Kindle's screen:
- the QR code: a secret address (no PIN needed);
- the Kindle's address typed into a browser (http://192.168.1.20, or with
  :8642 where port 80 can't be used): the browser asks for the 6-digit PIN
  shown on the Kindle, then goes to the same secret address. 5 wrong PINs
  turn the PIN off (the QR code still works; opening the page again makes a
  new PIN).

The Kindle Keyboard has no camera: the Kindle shows a QR code with a secret
address served by the Kindle itself (gzreader_pairserver.lua); the phone opens
it. The page works while the code is on the Kindle's screen (Back closes it,
10 minutes without anything happening too). Forms post back to the Kindle and
the phone is sent back to the page (POST, then a redirect), with what happened
at the top. Passwords, tokens and calendar links are never written to the log.

Opened from the setup guide, from each Connect with QR code (Grimmory, Notes,
Calendar) and from the quick panel (Send books).
]]

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Log = require("gzreader_log")
local _ = require("gettext")
local T = require("ffi/util").template

local Phone = {
    TIMEOUT = 10 * 60,  -- seconds without a request
    MAX_FAILED = 10,    -- failed sign-ins (all services) before the page closes
    PIN_TRIES = 5,      -- wrong PINs before the PIN stops working
    MAX_MB = 1024,      -- per book
    ACCEPT = ".epub,.pdf,.mobi,.azw,.azw3,.prc,.fb2,.fbz,.cbz,.cbr,.cbt,.djvu,.txt,.rtf,.html,.htm,.doc,.docx,.odt,.md,.chm,.zip",
    session = nil,
}

local function toast(text)
    pcall(function() -- (modal: above the QR code screen, which is modal too)
        UIManager:show(require("ui/widget/notification"):new{ text = text, timeout = 3, modal = true })
    end)
end

local function host(url) return tostring(url or ""):gsub("^https?://", ""):gsub("/.*$", "") end

--- GZreader's single sign-on hand-off page (docs/oauth2-callback.html, on the
--- repository's GitHub Pages): one redirect address for every Kindle.
Phone.SSO_RELAY = "https://9retirement6irk.github.io/GZreader/oauth2-callback"

--- Where the identity provider sends the phone after signing in, and
--- whether it's a hand-off page (true) or the Kindle itself (false).
--- Settings → Connections → Grimmory → Single sign-on redirect: "relay"
--- (GZreader's page, the default), "kindle" (this Kindle's own address, as
--- before 1.11: kept for Kindles that signed in that way), or the address
--- of the same page hosted elsewhere (https://…/oauth2-callback).
function Phone.ssoRedirect(plugin, origin)
    local v = G_reader_settings:readSetting("gzreader_sso_redirect")
    if v == nil and plugin.store.sso_direct_ok then v = "kindle" end
    if v == "kindle" then return origin .. "/oauth2-callback", false end
    if type(v) == "string" and v:match("^https://[^/]+/.*oauth2%-callback$") then return v, true end
    return Phone.SSO_RELAY, true
end

--- scheme://host[:port] of an address (what Grimmory compares the Origin with).
function Phone.originOf(u) return tostring(u):match("^(https?://[^/?#]+)") end

-- The Notes and Calendar tabs' modules (their connect, disconnect, links…),
-- loaded when an action needs them; the page itself is drawn from the stored
-- settings only.
local function Notes() return require("gzreader_notes") end
local function Calendar() return require("gzreader_calendar") end

--- A calendar link's display name and id (as gzreader_calendar.lua has them).
local function feedName(f)
    if f.name and f.name ~= "" then return f.name end
    if f.own_name and f.own_name ~= "" then return f.own_name end
    return host(f.url) ~= "" and host(f.url) or _("Calendar link")
end
local function feedId(f)
    if not f.id then f.id = require("gzreader_pairserver").randomToken(4) end
    return f.id
end

--- What the page shows now.
local function state(S, flash)
    local plugin = S.plugin
    flash = flash or {}
    local sec = flash.section
    local st = { base = S.base, flash = flash.text and { ok = flash.ok, text = flash.text } or nil }
    -- Grimmory
    local store = plugin.store
    local g = { connected = plugin.api and plugin.api:isPaired() or false, username = store.username,
        host = host(store.server) }
    g.redirect_uri, g.sso_relay = Phone.ssoRedirect(plugin, S.origin)
    g.form = sec == "grimmory" and flash.form
        -- (copied from another GZreader: its address and account, to sign in with)
        or (not g.connected and type(S.opts.grimmory_form) == "table" and S.opts.grimmory_form)
        or { server = store.server, username = store.username }
    if sec == "grimmory" then g.error = flash.error end
    -- single sign-on: asked from Grimmory when the form is in view (not
    -- connected, or a sign-in just tried); otherwise what was learnt before
    if not g.connected or sec == "grimmory" then
        g.sso = S.ssoInfo(g.form.server)
    else
        local known = store.grimmory_sso
        if type(known) == "table" and known.server == g.form.server then g.sso = known.info end
    end
    st.grimmory = g
    -- Memos
    local ms = store.memos or {}
    st.memos = { connected = ms.server ~= nil and ms.token ~= nil, user = ms.user, host = host(ms.server),
        form = sec == "notes" and flash.form or { server = ms.server }, error = sec == "notes" and flash.error or nil }
    -- calendars
    local cs = store.caldav or {}
    local cals = {}
    for _i, c in ipairs(cs.calendars or {}) do cals[#cals + 1] = { href = c.href, name = c.name, shown = c.enabled ~= false } end
    st.caldav = { connected = cs.server ~= nil and cs.username ~= nil and cs.password ~= nil, username = cs.username,
        host = host(cs.server),
        calendars = cals, form = sec == "caldav" and flash.form or { server = cs.server, username = cs.username },
        error = sec == "caldav" and flash.error or nil }
    local links = {}
    for _i, f in ipairs(store.calendar_feeds or {}) do
        links[#links + 1] = { id = feedId(f), name = feedName(f), custom_name = f.name,
            own_name = f.own_name, host = host(f.url), shown = f.enabled ~= false }
    end
    st.links = { list = links, error = sec == "links" and flash.error or nil, results = flash.links_html }
    -- music (Plex): Kindles with audio
    if require("gzreader_touch").audio() then
        local ps = store.plex or {}
        local servers = {}
        for _i, sv in ipairs(ps.servers or {}) do
            servers[#servers + 1] = { id = sv.id, name = sv.name, current = sv.id == (ps.server or {}).id }
        end
        st.plex = { connected = ps.token ~= nil and ps.server ~= nil, username = ps.username, server = (ps.server or {}).name,
            servers = servers, error = sec == "music" and flash.error or nil }
    end
    -- access (Cloudflare)
    local Access = require("gzreader_access")
    local ac = store.access or {}
    local extra = {}
    for h in tostring(ac.hosts or ""):gmatch("[^%s,;]+") do extra[h:lower()] = true end
    local auto = {}
    for _i, h in ipairs(Access.hosts(plugin)) do if not extra[h] then auto[#auto + 1] = h end end
    st.access = { enabled = ac.enabled == true, key = ac.key, hosts = ac.hosts, auto = auto, cf_id = ac.cf_id,
        cf_secret_set = ac.cf_secret ~= nil, rule = ac.key and Access.ruleExpression(plugin) or nil,
        error = sec == "access" and flash.error or nil }
    st.start = S.opts.section or "grimmory"
    -- diagnostics: the log, while diagnostic logging is on
    if store.logging_disabled ~= true then st.diagnostics = { level = store.log_level } end
    -- books
    local dir = plugin:libraryDir()
    local free = Phone.freeBytes(dir)
    st.books = { folder = dir:match("[^/]+$"), received = S.received, accept = Phone.ACCEPT, max_mb = Phone.MAX_MB,
        free_mb = free and math.floor(free / 1048576) or nil }
    return st
end

local function resultsHtml(results)
    local function esc(x) return (tostring(x or ""):gsub("[&<>\"']", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" })) end
    local rows = {}
    for _i, r in ipairs(results or {}) do
        if r.ok then
            rows[#rows + 1] = '<p class="ok">✓ ' .. esc(r.label) .. (r.note and (" (" .. esc(r.note) .. ")")
                or (r.count and (" (" .. esc(r.count) .. " events this month)") or "")) .. "</p>"
        else
            rows[#rows + 1] = '<p class="err">✗ ' .. esc(r.label) .. ": " .. esc(r.err) .. "</p>"
        end
    end
    return table.concat(rows)
end

--- A file name for a book from the phone: safe on the Kindle's drive, not
--- taken yet in `dir`. nil if it isn't a book the Kindle can open.
function Phone.bookName(dir, name)
    name = tostring(name or ""):gsub("[%c]", ""):gsub("^.*[/\\]", ""):gsub("^%.+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or not name:find("%.%w+$") then return nil end
    local ext_l = name:match("(%.[^.]+)$"):lower()
    if not ("," .. Phone.ACCEPT .. ","):find("," .. ext_l .. ",", 1, true) then return nil end
    -- safe on the Kindle's FAT drive: no \ / : * ? " < > |, no trailing dots or spaces
    local stem, ext = name:match("^(.*)(%.[^.]+)$")
    stem = stem:gsub('[\\/:%*%?"<>|]', "_"):gsub("[%.%s]+$", "")
    if #stem > 180 then stem = stem:sub(1, 180):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") end
    if stem == "" then stem = "Book" end
    ext = ext:lower()
    local candidate, n = stem .. ext, 1
    while lfs.attributes(dir .. "/" .. candidate, "mode") do
        n = n + 1
        candidate = stem .. " (" .. n .. ")" .. ext
    end
    return candidate
end

--- Free space on the drive holding `dir` (bytes), or nil.
function Phone.freeBytes(dir)
    local ok, du = pcall(util.diskUsage, dir)
    return ok and type(du) == "table" and du.available or nil
end

--- The typed PIN is the PIN (every digit compared, whatever the first wrong one).
function Phone.samePin(typed, pin)
    typed, pin = tostring(typed or ""), tostring(pin or "")
    if #pin == 0 or #typed ~= #pin then return false end
    local diff = 0
    for i = 1, #pin do
        if typed:byte(i) ~= pin:byte(i) then diff = diff + 1 end
    end
    return diff == 0
end

--- Also listen on port 80 (the address is then just the IP), where it can
--- be used; false: only the page's own port.
Phone.PORT80 = 80

local function mb(bytes) return string.format("%.1f MB", (bytes or 0) / 1048576) end

--- Open the page; opts.section ("grimmory", "notes", "calendar", "books")
--- is where the phone starts; opts.on_close(changes) runs when it closes.
function Phone.open(plugin, opts)
    opts = opts or {}
    if Phone.session then return Phone.session end
    local PairServer, PairPage = require("gzreader_pairserver"), require("gzreader_pairpage")
    local Api = require("gzreader_api")
    local S = { plugin = plugin, opts = opts, flashes = {}, failed = 0, received = {}, changes = {},
        sso_cache = {}, last = os.time() }
    S.token = PairServer.randomToken(16)
    S.base = "/phone/" .. S.token
    S.pin, S.pin_tries = require("gzreader_spake").pin(), 0
    Phone.session = S

    local server, server80, screen, idle_task, done
    local function finish(reason)
        if done then return end
        done = true
        Phone.session = nil
        if idle_task then UIManager:unschedule(idle_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if server80 then UIManager:removeZMQ(server80); server80:stop() end
        if screen then UIManager:close(screen); screen = nil end
        pcall(function() require("gzreader_awake").release("phone") end)
        plugin.pairing = nil
        Log.info("phone page closed:", reason or "back")
        Phone.afterClose(S)
    end
    S.finish = finish

    local function touch()
        S.last = os.time()
        if idle_task then UIManager:unschedule(idle_task) end
        idle_task = function()
            if server and server:uploading() then return touch() end
            finish("expired")
        end
        UIManager:scheduleIn(Phone.TIMEOUT, idle_task)
    end

    local function flashId(f)
        local id = PairServer.randomToken(4)
        S.flashes[id] = f
        return id
    end
    local function back(f, anchor)
        return 303, "text/plain", S.base .. "?m=" .. flashId(f) .. "#" .. (anchor or f.section or "")
    end
    local function failedLogin()
        S.failed = S.failed + 1
        if S.failed >= Phone.MAX_FAILED then
            UIManager:nextTick(function()
                finish("too many failed sign-ins")
                UIManager:show(InfoMessage:new{ text = _("The setup page closed after too many failed sign-ins.") })
            end)
            return true
        end
    end

    -- Grimmory: what to offer for single sign-on (asked once per address)
    function S.ssoInfo(server_input)
        if not server_input or server_input == "" then return nil end
        local cached = S.sso_cache[server_input]
        if cached ~= nil then return cached end
        local srv = Api.normalizeServer(server_input)
        if not srv then return nil end
        local base, settings = plugin.api:publicSettings(srv)
        if not base or type(settings) ~= "table" then return nil end
        local info = false
        if settings.oidcEnabled == true then
            local pd = type(settings.oidcProviderDetails) == "table" and settings.oidcProviderDetails or {}
            info = { name = Api.str(pd.providerName), only = settings.oidcForceOnlyMode == true }
        end
        S.sso_cache[server_input] = info
        plugin.store.grimmory_sso = { server = server_input, info = info } -- (for the page while connected)
        return info
    end

    local function grimmoryOk()
        S.changes.grimmory = true
        toast(T(_("Connected to Grimmory as %1."), plugin.store.username or "?"))
        return back({ ok = true, text = T(_("Connected to Grimmory as %1."), plugin.store.username or "?"), section = "grimmory" })
    end
    local function grimmoryFailed(form, err)
        if failedLogin() then return 200, "text/html", PairPage.gone() end
        return back({ section = "grimmory", error = err, form = { server = form.server, username = form.username } })
    end

    local function startSso(form)
        local srv = Api.normalizeServer(form.server or "")
        if not srv then return grimmoryFailed(form, _("Enter your Grimmory address first.")) end
        plugin.api.explicit_https = (form.server or ""):match("^%s*https://") ~= nil
        local base, settings = plugin.api:publicSettings(srv)
        if not base then return grimmoryFailed(form, plugin:describeError(settings)) end
        local pd = type(settings.oidcProviderDetails) == "table" and settings.oidcProviderDetails or {}
        if settings.oidcEnabled ~= true or not Api.str(pd.clientId) or not Api.str(pd.issuerUri) then
            return grimmoryFailed(form, _("Single sign-on isn't turned on for this Grimmory server."))
        end
        local auth_ep = Api.discoverAuthorizationEndpoint(pd.issuerUri)
        if not auth_ep then return grimmoryFailed(form, _("Couldn't reach your identity provider from the Kindle.")) end
        local st = Api.oidcState(base)
        if not st then return grimmoryFailed(form, _("Grimmory didn't start single sign-on. Try again.")) end
        local redirect_uri, relay = Phone.ssoRedirect(plugin, S.origin)
        S.sso = { base = base, state = st, verifier = PairServer.randomToken(32), nonce = PairServer.randomToken(16),
            redirect_uri = redirect_uri, relay = relay }
        local q = Api.query{
            response_type = "code", client_id = pd.clientId, redirect_uri = S.sso.redirect_uri,
            scope = Api.str(pd.scopes) or "openid profile email offline_access",
            code_challenge = Api.pkceChallenge(S.sso.verifier), code_challenge_method = "S256",
            state = st, nonce = S.sso.nonce,
        }
        Log.info("sso: redirecting phone to", auth_ep, "redirect_uri", S.sso.redirect_uri)
        local sep = auth_ep:find("?", 1, true) and "&" or "?"
        local auth_url = auth_ep .. sep .. q:sub(2)
        if not relay then return 302, nil, auth_url end
        -- the hand-off page remembers the way back to this Kindle, then opens the provider
        local esc = require("socket.url").escape
        return 302, nil, redirect_uri .. "#back=" .. esc(S.origin .. "/oauth2-callback") .. "&go=" .. esc(auth_url)
    end

    local function finishSso(query)
        local params = PairServer.parseForm(query)
        local session = S.sso
        if params.error then
            S.sso = nil
            return grimmoryFailed({ server = session and session.base },
                T(_("Sign-in didn't complete: %1"), params.error_description or params.error))
        end
        if not session or not params.code or params.state ~= session.state then
            return 200, "text/html", PairPage.gone()
        end
        S.sso = nil -- single use
        local previous = { plugin.store.server, plugin.store.username }
        local ok, err = plugin.api:oidcExchange(session.base, {
            code = params.code, code_verifier = session.verifier, redirect_uri = session.redirect_uri,
            nonce = session.nonce, state = session.state,
        }, Phone.originOf(session.redirect_uri))
        if ok then
            Log.info("sso: signed in as", tostring(plugin.store.username), session.relay and "(hand-off page)" or "(this Kindle's address)")
            if not session.relay then plugin.store.sso_direct_ok = true end
            plugin:afterLogin(previous)
            return grimmoryOk()
        end
        Log.warn("sso: exchange failed:", tostring(err))
        return grimmoryFailed({ server = session.base }, T(_("Grimmory rejected the sign-in: %1"), plugin:describeError(err)))
    end

    local routes = {}
    routes["/grimmory"] = function(form)
        if form.action == "sso" then return startSso(form) end
        local ok, err = plugin:connect(form.server or "", form.username or "", form.password or "")
        if ok then return grimmoryOk() end
        return grimmoryFailed(form, err)
    end
    routes["/grimmory/disconnect"] = function()
        if plugin.sync then pcall(plugin.sync.onLeave, plugin.sync) end
        pcall(plugin.api.logout, plugin.api)
        plugin.api:clearTokens()
        S.changes.grimmory = true
        Log.info("phone: disconnected from Grimmory")
        toast(_("Disconnected from Grimmory."))
        return back({ ok = true, text = _("Disconnected from Grimmory. Downloaded books stay on the Kindle."), section = "grimmory" })
    end
    -- Plex: its own sign-in page (a "strong" PIN), then back here
    local function Music() return require("gzreader_music") end
    routes["/plex/oauth"] = function()
        local plex = Music().plex(plugin)
        local pin, err = plex:newPin(true)
        plugin:save()
        if not pin then return back({ section = "music", error = T(_("Couldn't reach Plex: %1"), tostring(err)) }) end
        S.plex_pin = pin
        Log.info("plex: sending the phone to Plex's sign-in")
        return 302, nil, plex:authUrl(pin, S.origin .. S.base .. "/plex/done")
    end
    local function plexDone()
        local pin = S.plex_pin
        if not pin then return back({ section = "music", error = _("That Plex sign-in has expired: sign in again.") }) end
        local plex = Music().plex(plugin)
        local token
        for _try = 1, 6 do -- (Plex may take a moment to mark the PIN signed in)
            token = plex:checkPin(pin)
            if token then break end
            require("socket").sleep(1)
        end
        if not token then return back({ section = "music", error = _("Plex didn't finish the sign-in. Try again.") }) end
        S.plex_pin = nil
        local ok, err = plex:connect(token)
        if not ok then
            local msgs = { no_server = _("This Plex account has no Plex Media Server."),
                server_unreachable = _("Couldn't reach your Plex Media Server from the Kindle's Wi-Fi.") }
            return back({ section = "music", error = msgs[err] or tostring(err) })
        end
        plugin:save()
        S.changes.music = true
        toast(T(_("Signed in to Plex as %1."), plugin.store.plex.username or "?"))
        return back({ ok = true, text = T(_("Signed in to Plex as %1 (%2)."), plugin.store.plex.username or "?",
            (plugin.store.plex.server or {}).name or "?"), section = "music" })
    end
    routes["/plex/server"] = function(form)
        local plex = Music().plex(plugin)
        local ok, err = plex:connect(plugin.store.plex.token, form.id)
        plugin:save()
        if not ok then return back({ section = "music", error = tostring(err) }) end
        S.changes.music = true
        return back({ ok = true, text = T(_("Using the Plex server “%1”."), (plugin.store.plex.server or {}).name or "?"), section = "music" })
    end
    routes["/plex/disconnect"] = function()
        Music().plex(plugin):signOut()
        plugin:save()
        S.changes.music = true
        return back({ ok = true, text = _("Signed out of Plex. Downloaded music stays on the Kindle."), section = "music" })
    end
    -- the Access key / Cloudflare service token
    routes["/access"] = function(form)
        local Access = require("gzreader_access")
        local ac = plugin.store.access or {}
        plugin.store.access = ac
        ac.enabled = form.enabled == "1"
        if ac.enabled and (not ac.key or form.new_key == "1") then Access.newKey(plugin) end
        ac.hosts = (form.hosts or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if form.cf_clear == "1" then
            ac.cf_id, ac.cf_secret = nil, nil
        else
            local id = (form.cf_id or ""):gsub("%s", "")
            if id ~= "" then ac.cf_id = id end
            local secret = (form.cf_secret or ""):gsub("%s", "")
            if secret ~= "" then ac.cf_secret = secret end
            if id == "" then ac.cf_id, ac.cf_secret = nil, nil end
        end
        plugin:save()
        Log.info("access: key", ac.enabled and "on" or "off", "service token", ac.cf_id and "set" or "none")
        return back({ ok = true, text = _("Saved."), section = "access" })
    end
    routes["/memos"] = function(form)
        local ok, err = Notes().connect(plugin, form.server, form.token)
        if not ok then
            if failedLogin() then return 200, "text/html", PairPage.gone() end
            return back({ section = "notes", error = err, form = { server = form.server } })
        end
        S.changes.notes = true
        Notes().notes = nil
        toast(T(_("Notes: connected to Memos as %1."), plugin.store.memos.user or "?"))
        return back({ ok = true, text = T(_("Notes connected to Memos as %1."), plugin.store.memos.user or "?"), section = "notes" })
    end
    routes["/memos/disconnect"] = function()
        Notes().disconnect(plugin)
        S.changes.notes = true
        toast(_("Notes: disconnected from Memos."))
        return back({ ok = true, text = _("Notes disconnected from Memos."), section = "notes" })
    end
    routes["/caldav"] = function(form)
        local ok, err = Calendar().connect(plugin, form.server, form.username, form.password)
        if not ok then
            if failedLogin() then return 200, "text/html", PairPage.gone() end
            return back({ section = "caldav", error = err, form = { server = form.server, username = form.username } }, "calendar")
        end
        S.changes.calendar = true
        Calendar().calendarsChanged()
        local n = #((plugin.store.caldav or {}).calendars or {})
        toast(T(_("Calendar: %1 calendars connected."), n))
        return back({ ok = true, text = T(_("CalDAV account connected: %1 calendars."), n), section = "calendar" })
    end
    routes["/caldav/disconnect"] = function()
        Calendar().disconnect(plugin)
        S.changes.calendar = true
        toast(_("Calendar: CalDAV account disconnected."))
        return back({ ok = true, text = _("CalDAV account disconnected (calendar links stay)."), section = "calendar" })
    end
    routes["/calendar/show"] = function(form)
        for _i, c in ipairs((plugin.store.caldav or {}).calendars or {}) do
            if c.href == form.href then
                c.enabled = form.shown == "1"
                plugin:save()
                S.changes.calendar = true
                Calendar().cached_at = nil
                return back({ ok = true, text = T(c.enabled and _("“%1” is shown.") or _("“%1” is hidden."), c.name or "?"), section = "calendar" })
            end
        end
        return back({ section = "links", error = _("That calendar isn't on the Kindle any more.") }, "calendar")
    end
    routes["/links"] = function(form)
        local entries = Calendar().parseLinkLines(form.links)
        if #entries == 0 then return back({ section = "links", error = _("Paste at least one calendar link.") }, "calendar") end
        local results = Calendar().addFeeds(plugin, entries)
        local added = 0
        for _i, r in ipairs(results) do if r.ok and not r.note then added = added + 1 end end
        if added > 0 then
            S.changes.calendar = true
            Calendar().calendarsChanged()
            toast(T(_("Calendar: %1 links added."), added))
        end
        return back({ section = "links", links_html = resultsHtml(results),
            ok = added > 0 or nil, text = added > 0 and T(_("Calendar: %1 links added."), added) or nil }, "calendar")
    end
    routes["/link"] = function(form)
        local feeds = Calendar().feeds(plugin)
        local index, f
        for i, x in ipairs(feeds) do if Calendar().feedId(x) == form.id then index, f = i, x end end
        if not f then return back({ section = "links", error = _("That calendar link isn't on the Kindle any more.") }, "calendar") end
        if form.action == "remove" then
            local name = Calendar().feedName(f)
            Calendar().removeFeed(plugin, index)
            S.changes.calendar = true
            toast(T(_("Calendar: removed “%1”."), name))
            return back({ ok = true, text = T(_("Removed “%1”."), name), section = "calendar" })
        end
        local new_url = (form.url or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if new_url ~= "" then
            local url, res = Calendar().checkFeed(new_url)
            if not url then return back({ section = "links", error = T(_("The new link didn't work: %1"), tostring(res)) }, "calendar") end
            f.url, f.own_name = url, res.name or f.own_name
            Calendar().calendarsChanged()
            Log.info("calendar: link replaced", require("gzreader_caldav").feedLabel(url))
        end
        local name = (form.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
        f.name = name ~= "" and name or nil
        f.enabled = form.shown == "1"
        plugin:save()
        Calendar().cached_at = nil
        S.changes.calendar = true
        return back({ ok = true, text = T(_("Saved “%1”."), Calendar().feedName(f)), section = "calendar" })
    end

    -- the typed-in address: the PIN on the Kindle's screen, then the page
    local function pinPage(method, body)
        local st = { tries_left = Phone.PIN_TRIES - S.pin_tries, off = S.pin_tries >= Phone.PIN_TRIES }
        if method == "GET" or st.off then return 200, "text/html", PairPage.pin(st) end
        if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
        local typed = tostring(PairServer.parseForm(body).pin or ""):gsub("%D", "")
        if Phone.samePin(typed, S.pin) then
            Log.info("phone page: PIN accepted")
            return 303, "text/plain", S.base .. (S.opts.section and ("#" .. S.opts.section) or "")
        end
        S.pin_tries = S.pin_tries + 1
        Log.info("phone page: wrong PIN", S.pin_tries, "of", Phone.PIN_TRIES)
        st.tries_left, st.off, st.wrong = Phone.PIN_TRIES - S.pin_tries, S.pin_tries >= Phone.PIN_TRIES, true
        if st.off and screen and screen.setPin then
            screen:setPin(nil, _("PIN off: 5 wrong tries"))
        end
        return 200, "text/html", PairPage.pin(st)
    end

    -- Diagnostics: the log as a file (made when asked; passwords and tokens are never in it)
    local function logFile()
        if plugin.store.logging_disabled == true then return 404, "text/plain", "Not found" end
        local lib = plugin:libraryDir()
        Log.probe_device = require("device"):isKindle()
        -- built in the cache and deleted there (nothing left next to the GZreader folder)
        local data_dir = require("datastorage"):getDataDir()
        pcall(function() require("libs/libkoreader-lfs").mkdir(data_dir .. "/cache") end)
        local content, filename = Log.exportText(data_dir .. "/cache", data_dir .. "/crash.log")
        if not content then return 500, "text/plain", "Couldn't save the log: " .. tostring(filename) end
        Log.pruneExports(lib:match("^(.+)/[^/]+$") or lib) -- (logs earlier versions left there: the newest few stay)
        Log.info("log sent to the browser", filename, #content, "bytes")
        return 200, "text/plain", content, { ["Content-Disposition"] = 'attachment; filename="' .. filename .. '"' }
    end

    server = PairServer:new{
        handler = function(method, full_path, _headers, body)
            local path, query = full_path:match("^([^?]*)%??(.*)$")
            if done then return 200, "text/html", PairPage.gone() end
            if path == "/oauth2-callback" and method == "GET" then touch(); return finishSso(query) end
            if path == "/" or path == "/pin" then touch(); return pinPage(method, body) end
            if path ~= S.base and path:sub(1, #S.base + 1) ~= S.base .. "/" then return 404, "text/plain", "Not found" end
            touch()
            local sub = path:sub(#S.base + 1)
            if sub == "" then
                if method ~= "GET" then return 405, "text/plain", "Method not allowed" end
                local m = PairServer.parseForm(query).m
                local f = m and S.flashes[m]
                return 200, "text/html", PairPage.hub(state(S, f))
            end
            if sub == "/plex/done" and method == "GET" then return plexDone() end
            if sub == "/log" and method == "GET" then return logFile() end
            local route = routes[sub]
            if not route then return 404, "text/plain", "Not found" end
            if method ~= "POST" then return 405, "text/plain", "Method not allowed" end
            return route(PairServer.parseForm(body))
        end,
        -- books: the request body is the file
        upload = function(method, full_path, _headers, length)
            local path, query = full_path:match("^([^?]*)%??(.*)$")
            if done or method ~= "POST" or path ~= S.base .. "/upload" then return nil end
            touch()
            local dir = plugin:libraryDir()
            local raw = PairServer.parseForm(query).name
            local name = Phone.bookName(dir, raw)
            if not name then
                return { error = 415, message = T(_("%1: not a book the Kindle can open."), tostring(raw or "?")) }
            end
            if not length or length <= 0 then return { error = 411, message = T(_("%1: empty file."), name) } end
            if length > Phone.MAX_MB * 1048576 then
                return { error = 413, message = T(_("%1: too big (%2; up to %3 MB)."), name, mb(length), Phone.MAX_MB) }
            end
            local free = Phone.freeBytes(dir)
            if free and free < length + 20 * 1048576 then
                return { error = 507, message = T(_("%1: not enough space on the Kindle (%2 free)."), name, mb(free)) }
            end
            local tmp = dir .. "/.gz-upload-" .. PairServer.randomToken(4) .. ".part"
            local started = os.time()
            return {
                file = tmp,
                done = function(ok, why)
                    if not ok then
                        Log.warn("phone: book not received:", name, tostring(why))
                        return 400, "text/plain", T(_("%1: the upload stopped (%2)."), name, tostring(why))
                    end
                    -- (another book of that name may have arrived meanwhile)
                    local final = Phone.bookName(dir, name) or name
                    os.rename(tmp, dir .. "/" .. final)
                    S.received[#S.received + 1] = final
                    S.changes.books = (S.changes.books or 0) + 1
                    touch()
                    Log.info("phone: book received", final, length, "bytes in", os.time() - started, "s")
                    toast(T(_("Book received: %1"), final))
                    return 200, "text/plain", T(_("%1 (%2) is on the Kindle."), final, mb(length))
                end,
            }
        end,
    }

    local ok, serr = server:start()
    if not ok then
        Phone.session = nil
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start: %1"), tostring(serr)) })
    end
    local hint_host = plugin.store.server and plugin.store.server:match("^https?://([^/:]+)")
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = PairServer.localIp(hint_host, iface)
    if not ip then
        Log.err("phone page: no local IP;", tostring(why))
        server:stop()
        Phone.session = nil
        return UIManager:show(InfoMessage:new{
            text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why) })
    end
    S.origin = T("http://%1:%2", ip, server.port)
    S.server = server
    plugin.pairing = true
    UIManager:insertZMQ(server)
    -- port 80 too, where it can be used, so that the address is just the IP
    -- (it only sends the browser to the PIN page)
    S.address = T("%1:%2", ip, server.port)
    if Phone.PORT80 then
        server80 = PairServer:new{ port = Phone.PORT80, exact_port = true, keep_wifi = false, handler = function()
            return 302, "text/plain", S.origin .. "/"
        end }
        if server80:start() then
            UIManager:insertZMQ(server80)
            S.address = Phone.PORT80 == 80 and ip or T("%1:%2", ip, Phone.PORT80)
        else
            server80 = nil
        end
    end
    pcall(function() require("gzreader_awake").hold("phone", { what = "phone page", still = function() return Phone.session == S end }) end) -- (uploads take a while)
    Log.info("phone page open on", S.origin, "section", tostring(opts.section))
    local url = S.origin .. S.base .. (opts.section and ("#" .. opts.section) or "")
    screen = require("gzreader_pairscreen"):new{
        url = url,
        title = opts.title or _("Set up from your browser"),
        instructions = opts.instructions or _("Scan this code with your phone to set up GZreader connections and send books."),
        address = S.address,
        pin = S.pin,
        footer = _("Press Back when you're done."),
        button_text = _("Done"),
        on_cancel = function() screen = nil; finish("back") end,
    }
    UIManager:show(screen)
    touch()
    return S
end

--- After the page closed: one summary, and the caller's own follow-up.
function Phone.afterClose(S)
    local lines = {}
    local plugin = S.plugin
    local ch = S.changes
    if ch.grimmory then
        lines[#lines + 1] = plugin.api:isPaired() and T(_("Grimmory: connected as %1."), plugin.store.username or "?")
            or _("Grimmory: disconnected.")
    end
    if ch.notes then
        local m = plugin.store.memos or {}
        lines[#lines + 1] = m.token and T(_("Notes: connected to Memos as %1."), m.user or "?") or _("Notes: disconnected.")
    end
    if ch.calendar then lines[#lines + 1] = _("Calendar: updated.") end
    if ch.music then
        local ps = plugin.store.plex or {}
        lines[#lines + 1] = ps.token and T(_("Music: signed in to Plex as %1."), ps.username or "?") or _("Music: signed out of Plex.")
    end
    if ch.books then
        lines[#lines + 1] = T(_("%1 books received (the Downloads tab shows them)."), ch.books)
        pcall(function()
            local fm = require("apps/filemanager/filemanager").instance
            if fm and fm.onRefresh then fm:onRefresh() end
        end)
    end
    if ch.calendar then
        pcall(function()
            local Cal = require("gzreader_calendar")
            Cal.cached_at = nil
            if Cal.board and not Cal.board._gz_closed then Cal.syncOnOpen(plugin) end
        end)
    end
    if #lines > 0 then UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 6 }) end
    if S.opts.on_close then
        local ok, err = pcall(S.opts.on_close, ch)
        if not ok then Log.warn("phone page: after close:", tostring(err)) end
    end
end

return Phone
