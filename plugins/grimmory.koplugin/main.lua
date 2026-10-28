--[[--
Grimmory for KOReader.

* Pair with a Grimmory server by scanning a QR code shown on the Kindle (the
  phone does the typing), or by typing on the Kindle's own keyboard.
* Browse the library and download books (text-only lists, no thumbnails).
* Native progress sync through Grimmory's own reading-progress API (the one
  its web reader uses), plus reading sessions for Grimmory's statistics.
  No KOReader sync account, permission or file-hash matching involved.

@module koplugin.grimmory
]]

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Api = require("grimmory_api")
local Browser = require("grimmory_browser")
local PairPage = require("grimmory_pairpage")
local PairScreen = require("grimmory_pairscreen")
local PairServer = require("grimmory_pairserver")
local Sync = require("grimmory_sync")
local Download = require("grimmory_download")
local Log = require("grimmory_log")

local PAIR_TIMEOUT_S = 10 * 60
local PAIR_MAX_ATTEMPTS = 5
local MAX_QUEUED_SESSIONS = 200

local Grimmory = WidgetContainer:extend{
    name = "grimmory",
    is_doc_only = false,
}

function Grimmory:init()
    -- One settings object for the whole run, shared by every instance: KOReader
    -- creates a new plugin instance for each FileManager/ReaderUI, and a
    -- background download or queued sync data must not be written to a stale copy.
    if not Grimmory.shared_settings then
        Grimmory.shared_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/grimmory.lua")
        Log.init(DataStorage:getDataDir())
        Log.info("---- plugin loaded", "koreader", tostring(require("version"):getCurrentRevision()),
            "device", tostring(Device.model))
    end
    self.settings = Grimmory.shared_settings
    self.store = self.settings:readSetting("state", {})
    self.store.downloads = self.store.downloads or {}
    self.store.pending = self.store.pending or { progress = {}, sessions = {} }
    Log.enabled = self.store.logging_disabled ~= true
    self.api = Api:new(self.store, function() self:save() end)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if not self.ui.document and type(self.ui.active_widgets) == "table" then
        -- Dispatcher actions (e.g. ZenOS's Grimmory tab) are sent to the top
        -- window only; ZenOS's Home page sits above the file manager. Being an
        -- active widget lets our events still reach us. File manager only, so
        -- reader events are never delivered twice.
        table.insert(self.ui.active_widgets, self)
    end
end

function Grimmory:save()
    self.settings:saveSetting("state", self.store)
    self.settings:flush()
end

function Grimmory:syncEnabled()
    return self.store.sync_disabled ~= true and self.api:isPaired()
end

function Grimmory:onDispatcherRegisterActions()
    -- NB: in KOReader's Dispatcher, `reader = true` means "reader only" (the
    -- action is disabled in the file manager). These work everywhere: general.
    Dispatcher:registerAction("grimmory_library", {
        category = "none", event = "ShowGrimmoryLibrary", title = _("Grimmory library"),
        general = true,
    })
    Dispatcher:registerAction("grimmory_pair", {
        category = "none", event = "GrimmoryPair", title = _("Grimmory: connect with QR code"),
        general = true,
    })
    Dispatcher:registerAction("grimmory_sync_now", {
        category = "none", event = "GrimmorySyncNow", title = _("Grimmory: sync progress now"),
        reader = true,
    })
end

---------------------------------------------------------------- menu

function Grimmory:addToMainMenu(menu_items)
    menu_items.grimmory = {
        text = _("Grimmory"),
        sub_item_table_func = function() return self:menuItems() end,
    }
end

function Grimmory:menuItems()
    local paired = self.api:isPaired()
    local items = {
        {
            text_func = function()
                if self.api:isPaired() then
                    return T(_("Connected as %1"), self.store.username or "?")
                end
                return _("Not connected")
            end,
            enabled = false,
            separator = true,
        },
        {
            text = _("Browse library"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function(touchmenu) self:onShowGrimmoryLibrary(touchmenu) end,
        },
    }
    if self.sync then
        table.insert(items, {
            text = _("Sync progress now"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                self:onGrimmorySyncNow()
            end,
        })
    end
    local more = {
        {
            text = _("Sync reading progress"),
            help_text = _("Send your position to Grimmory as you read, and pick up where you left off on other devices or in Grimmory's web reader."),
            checked_func = function() return self.store.sync_disabled ~= true end,
            callback = function()
                self.store.sync_disabled = (self.store.sync_disabled ~= true) or nil
                self:save()
            end,
            separator = true,
        },
        {
            text = paired and _("Reconnect with QR code") or _("Connect with QR code"),
            callback = function(touchmenu) self:onGrimmoryPair(touchmenu) end,
        },
        {
            text = _("Connect by typing"),
            callback = function() self:keyboardLogin() end,
        },
        {
            text = _("Single sign-on (SSO) setup"),
            callback = function() self:showSsoSetup() end,
            separator = true,
        },
        {
            text = _("Disconnect"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function() self:confirmDisconnect() end,
            separator = true,
        },
        {
            text = _("Diagnostic logging"),
            help_text = _("Keep a log of Grimmory activity in koreader/grimmory.log (passwords and tokens are never written)."),
            checked_func = function() return self.store.logging_disabled ~= true end,
            callback = function()
                self.store.logging_disabled = (self.store.logging_disabled ~= true) or nil
                Log.enabled = self.store.logging_disabled ~= true
                self:save()
            end,
        },
        {
            text = _("Save diagnostic log"),
            callback = function() self:exportLog() end,
        },
    }
    for _, item in ipairs(more) do table.insert(items, item) end
    return items
end

local function closeTouchMenu(touchmenu)
    if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
end

---------------------------------------------------------------- errors

local ERRORS = {
    not_paired = _("This Kindle isn't connected to Grimmory yet."),
    expired = _("Your Grimmory login has expired. Connect again with the QR code."),
    unreachable = _("Couldn't reach the Grimmory server. Check Wi-Fi and the server address."),
    bad_credentials = _("Wrong username or password."),
    rate_limited = _("Too many attempts. Wait a minute and try again."),
}

function Grimmory:describeError(err)
    if type(err) == "string" and ERRORS[err] then return ERRORS[err] end
    if type(err) == "string" and err:match("^stalled") then
        return T(_("The download stalled (%1). Check the Kindle's Wi-Fi signal and try again."), err:gsub("^stalled:%s*", ""))
    end
    if type(err) == "string" and err:match("^http_") then
        return T(_("Grimmory returned an error (%1)."), err:sub(6))
    end
    return T(_("Something went wrong: %1"), tostring(err))
end

function Grimmory:exportLog()
    local dest, err = Log.exportTo(self:downloadDir(), DataStorage:getDataDir() .. "/crash.log")
    if dest then
        Log.info("log exported to", dest)
        UIManager:show(InfoMessage:new{
            text = T(_("Diagnostic log saved:\n%1\n\nConnect the Kindle over USB to copy it."), dest),
        })
    else
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log: %1"), tostring(err)) })
    end
end

function Grimmory:showError(err)
    Log.warn("shown to user:", tostring(err), "|", self:describeError(err))
    UIManager:show(InfoMessage:new{ text = self:describeError(err), icon = "notice-warning" })
end

---------------------------------------------------------------- pairing

--- Log in. Returns ok, err.
function Grimmory:connect(server_input, username, password)
    local server = Api.normalizeServer(server_input)
    if not server then return false, _("That server address doesn't look right.") end
    username = (username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if username == "" or not password or password == "" then
        return false, _("Enter your username and password.")
    end
    local previous = { self.store.server, self.store.username }
    self.api.explicit_https = server_input:match("^%s*https://") ~= nil
    local ok, err = self.api:login(server, username, password)
    Log.info("password login to", ok and self.store.server or server, ok and "ok" or ("failed: " .. tostring(err)))
    if not ok then return false, self:describeError(err) end
    self:afterLogin(previous)
    return true
end

--- Bookkeeping after any successful login. `previous` = { server, username }
--- from before the login.
function Grimmory:afterLogin(previous)
    if type(previous) ~= "table" or previous[1] ~= self.store.server or previous[2] ~= self.store.username then
        -- Different server/account: queued data belongs to the old one.
        self.store.pending = { progress = {}, sessions = {} }
        self:save()
    end
    self:flushPending()
end

function Grimmory:onGrimmoryPair(touchmenu)
    closeTouchMenu(touchmenu)
    NetworkMgr:runWhenOnline(function() self:startQrPairing() end)
    return true
end

function Grimmory:onGrimmoryKeyboardLogin()
    self:keyboardLogin()
    return true
end

function Grimmory:startQrPairing()
    if self.pairing then return end
    local token = PairServer.randomToken(16)
    local attempts = 0
    local done = false
    local server, screen, timeout_task
    local base_path = "/pair/" .. token

    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then
            UIManager:removeZMQ(server)
            server:stop()
        end
        if screen then UIManager:close(screen) end
        self.pairing = nil
    end

    local origin            -- http://<kindle-ip>:<port>, set once the server is up
    local sso_session       -- pending single sign-on: state, verifier, nonce, base
    local sso_info_cache = {}

    -- What the form should offer for SSO, for a known server address.
    local function ssoInfo(server_input)
        if not server_input or server_input == "" then return nil end
        local cached = sso_info_cache[server_input]
        if cached ~= nil then return cached end
        local srv = Api.normalizeServer(server_input)
        if not srv then return nil end
        local base, settings = self.api:publicSettings(srv)
        if not base or type(settings) ~= "table" then return nil end -- unknown: offer generic SSO
        local info = false
        if settings.oidcEnabled == true then
            local pd = type(settings.oidcProviderDetails) == "table" and settings.oidcProviderDetails or {}
            info = { name = Api.str(pd.providerName), only = settings.oidcForceOnlyMode == true }
        end
        sso_info_cache[server_input] = info
        return info
    end

    local function formPage(opts)
        opts.redirect_uri = origin .. "/oauth2-callback"
        if opts.sso == nil then opts.sso = ssoInfo(opts.server) end
        return 200, "text/html", PairPage.form(opts)
    end

    local function succeeded()
        UIManager:nextTick(function()
            finish()
            self:announceConnected()
        end)
        return 200, "text/html", PairPage.success(self.store.username)
    end

    local function failed(form, err)
        if attempts >= PAIR_MAX_ATTEMPTS then
            UIManager:nextTick(function()
                finish()
                UIManager:show(InfoMessage:new{ text = _("Pairing stopped after too many failed attempts.") })
            end)
            return 200, "text/html", PairPage.gone()
        end
        return formPage{ server = form.server, username = form.username, error = err }
    end

    -- Phone pressed "Sign in with SSO": send it to the identity provider.
    local function startSso(form)
        local srv = Api.normalizeServer(form.server or "")
        if not srv then return failed(form, _("Enter your Grimmory address first.")) end
        self.api.explicit_https = (form.server or ""):match("^%s*https://") ~= nil
        local base, settings = self.api:publicSettings(srv)
        if not base then return failed(form, self:describeError(settings)) end
        local pd = type(settings.oidcProviderDetails) == "table" and settings.oidcProviderDetails or {}
        if settings.oidcEnabled ~= true or not Api.str(pd.clientId) or not Api.str(pd.issuerUri) then
            return failed(form, _("Single sign-on isn't turned on for this Grimmory server."))
        end
        local auth_ep = Api.discoverAuthorizationEndpoint(pd.issuerUri)
        if not auth_ep then
            return failed(form, _("Couldn't reach your identity provider from the Kindle."))
        end
        local state = Api.oidcState(base)
        if not state then return failed(form, _("Grimmory didn't start single sign-on. Try again.")) end
        sso_session = {
            base = base,
            state = state,
            verifier = PairServer.randomToken(32), -- 64 hex chars, valid PKCE verifier
            nonce = PairServer.randomToken(16),
            redirect_uri = origin .. "/oauth2-callback",
        }
        local q = Api.query{
            response_type = "code",
            client_id = pd.clientId,
            redirect_uri = sso_session.redirect_uri,
            scope = Api.str(pd.scopes) or "openid profile email offline_access",
            code_challenge = Api.pkceChallenge(sso_session.verifier),
            code_challenge_method = "S256",
            state = state,
            nonce = sso_session.nonce,
        }
        Log.info("sso: redirecting phone to", auth_ep, "redirect_uri", sso_session.redirect_uri)
        local sep = auth_ep:find("?", 1, true) and "&" or "?"
        return 302, nil, auth_ep .. sep .. q:sub(2)
    end

    -- Identity provider sent the phone back here.
    local function finishSso(query)
        local params = PairServer.parseForm(query)
        local session = sso_session
        if params.error then
            sso_session = nil
            return failed({ server = session and session.base }, T(_("Sign-in didn't complete: %1"),
                params.error_description or params.error))
        end
        if not session or not params.code or params.state ~= session.state then
            return 200, "text/html", PairPage.gone()
        end
        sso_session = nil -- single use
        attempts = attempts + 1
        local previous = { self.store.server, self.store.username }
        local ok, err = self.api:oidcExchange(session.base, {
            code = params.code,
            code_verifier = session.verifier,
            redirect_uri = session.redirect_uri,
            nonce = session.nonce,
            state = session.state,
        }, origin)
        if ok then
            Log.info("sso: signed in as", tostring(self.store.username))
            self:afterLogin(previous)
            return succeeded()
        end
        Log.warn("sso: exchange failed:", tostring(err))
        return failed({ server = session.base }, T(_("Grimmory rejected the sign-in: %1"), self:describeError(err)))
    end

    server = PairServer:new{
        handler = function(method, full_path, _headers, body)
            local path, query = full_path:match("^([^?]*)%??(.*)$")
            if path == "/oauth2-callback" and method == "GET" and not done then
                return finishSso(query)
            end
            if path ~= base_path then
                return 404, "text/plain", "Not found"
            end
            if done then
                return 200, "text/html", PairPage.gone()
            end
            if method == "GET" then
                return formPage{ server = self.store.server, username = self.store.username }
            elseif method ~= "POST" then
                return 405, "text/plain", "Method not allowed"
            end
            local form = PairServer.parseForm(body)
            if form.action == "sso" then
                return startSso(form)
            end
            attempts = attempts + 1
            local ok, err = self:connect(form.server or "", form.username or "", form.password or "")
            form.password = nil
            if ok then return succeeded() end
            return failed(form, err)
        end,
    }

    local ok, err = server:start()
    if not ok then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start pairing: %1"), tostring(err)) })
    end
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = PairServer.localIp(hint_host, iface)
    if not ip then
        Log.err("pairing: no local IP;", tostring(why))
        server:stop()
        return UIManager:show(InfoMessage:new{
            text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.")
                .. "\n\n" .. _("Details:") .. "\n" .. tostring(why),
        })
    end

    origin = T("http://%1:%2", ip, server.port)
    Log.info("pairing started on", origin)
    self.pairing = true
    UIManager:insertZMQ(server)
    screen = PairScreen:new{
        url = T("http://%1:%2%3", ip, server.port, base_path),
        on_cancel = function() screen = nil; finish() end,
    }
    UIManager:show(screen)
    timeout_task = function()
        finish()
        UIManager:show(InfoMessage:new{ text = _("The pairing code expired. Start again when you're ready.") })
    end
    UIManager:scheduleIn(PAIR_TIMEOUT_S, timeout_task)
end

function Grimmory:showSsoSetup()
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local ip = PairServer.localIp(hint_host, iface)
    local uri = ip and T("http://%1:%2/oauth2-callback", ip, PairServer.port) or _("(connect to Wi-Fi to see it)")
    UIManager:show(InfoMessage:new{
        text = _("To sign in with SSO from the QR code page, add this redirect URI to Grimmory's client in your identity provider (Authentik, Pocket ID, Authelia, Keycloak…), next to the existing …/oauth2-callback one:")
            .. "\n\n" .. uri .. "\n\n"
            .. _("Reserve this Kindle's IP address in your router so the address doesn't change. If your Grimmory admin restricted ALLOWED_ORIGINS, add the same address without /oauth2-callback there too."),
    })
end

function Grimmory:announceConnected()
    UIManager:show(InfoMessage:new{
        text = T(_("Connected to Grimmory as %1."), self.store.username or "") .. "\n\n"
            .. _("Reading progress syncs automatically for books you download from Grimmory."),
    })
end

function Grimmory:keyboardLogin()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Connect to Grimmory"),
        fields = {
            { text = self.store.server or "", hint = _("Server, e.g. https://books.example.com") },
            { text = self.store.username or "", hint = _("Username") },
            { text = "", hint = _("Password"), text_type = "password" },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Connect"), is_enter_default = true, callback = function()
                local f = dialog:getFields()
                UIManager:close(dialog)
                NetworkMgr:runWhenOnline(function()
                    local msg = InfoMessage:new{ text = _("Connecting…"), timeout = 0 }
                    UIManager:show(msg)
                    UIManager:forceRePaint()
                    local ok, err = self:connect(f[1], f[2], f[3])
                    UIManager:close(msg)
                    if ok then
                        self:announceConnected()
                    else
                        UIManager:show(InfoMessage:new{ text = err, icon = "notice-warning" })
                    end
                end)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Grimmory:confirmDisconnect()
    UIManager:show(ConfirmBox:new{
        text = _("Disconnect this Kindle from Grimmory? Downloaded books stay on the Kindle. Progress sync will stop until you connect again."),
        ok_text = _("Disconnect"),
        ok_callback = function()
            if self.sync then self.sync:onLeave() end
            NetworkMgr:runWhenConnected(function() self.api:logout() end)
            self.api:clearTokens()
            UIManager:show(InfoMessage:new{ text = _("Disconnected from Grimmory."), timeout = 3 })
        end,
    })
end

---------------------------------------------------------------- offline queue

--- Remember a progress update (latest per book) or a reading session to send later.
function Grimmory:queue(kind, book_id, body)
    local pending = self.store.pending
    if kind == "progress" then
        pending.progress[tostring(book_id)] = body
    else
        table.insert(pending.sessions, body)
        while #pending.sessions > MAX_QUEUED_SESSIONS do table.remove(pending.sessions, 1) end
    end
    self:save()
end

function Grimmory:clearQueued(kind, book_id)
    if kind == "progress" then self.store.pending.progress[tostring(book_id)] = nil end
end

function Grimmory:flushPending()
    if self.flushing or not self.api:isPaired() or not NetworkMgr:isConnected() then return end
    local pending = self.store.pending
    if next(pending.progress) == nil and #pending.sessions == 0 then return end
    self.flushing = true
    for book_id, body in pairs(pending.progress) do
        local ok, _, code = self.api:putProgress(book_id, body)
        if ok or code == 404 or code == 400 or code == 403 then
            pending.progress[book_id] = nil -- sent, or the book is gone: drop it
            local entry = self.store.downloads[book_id]
            if ok and entry and body.fileProgress then entry.last_pushed_pct = body.fileProgress.progressPercent end
        else
            break -- still offline; try again later
        end
    end
    while #pending.sessions > 0 do
        local ok, _, code = self.api:postSession(pending.sessions[1])
        if ok or code == 400 or code == 404 then
            table.remove(pending.sessions, 1)
        else
            break
        end
    end
    self.flushing = nil
    self:save()
end

function Grimmory:onNetworkConnected()
    UIManager:scheduleIn(2, function() self:flushPending() end)
end

---------------------------------------------------------------- reader integration

--- Grimmory book id + download entry for an open file, if it came from Grimmory.
function Grimmory:entryForPath(path)
    if not path then return end
    for id, entry in pairs(self.store.downloads) do
        if type(entry) == "table" and entry.path == path then return id, entry end
    end
end

function Grimmory:onReaderReady()
    if not self.ui.document then return end
    local book_id, entry = self:entryForPath(self.ui.document.file)
    if not book_id then return end
    if not entry.file_id and self.api:isPaired() and NetworkMgr:isConnected() then
        -- Downloaded by an older version of this plugin: look up the file id once.
        local book = self.api:getBook(book_id)
        local pf = book and type(book.primaryFile) == "table" and tonumber(book.primaryFile.id)
        if pf then entry.file_id = pf; self:save() end
    end
    Log.info("opened Grimmory book", book_id, "file_id", tostring(entry.file_id), "format", tostring(entry.format))
    self.sync = Sync:new(self, self.ui, entry, book_id)
    self.sync:onReady()
end

function Grimmory:onPageUpdate()
    if self.sync then self.sync:onPageTurned() end
end

function Grimmory:onPosUpdate()
    if self.sync and self.ui.view and self.ui.view.view_mode ~= "page" then
        -- scroll mode fires this continuously; count roughly a screen per call
        self.sync:onPageTurned()
    end
end

function Grimmory:onGrimmorySyncNow()
    if not self.sync then
        UIManager:show(InfoMessage:new{ text = _("This book wasn't downloaded from Grimmory, so it can't be synced."), timeout = 3 })
        return true
    end
    NetworkMgr:runWhenOnline(function()
        self.sync:push(true)
        self.sync:pull(true)
    end)
    return true
end

function Grimmory:onSuspend()
    if self.sync then self.sync:onLeave() end
end

function Grimmory:onResume()
    if self.sync then
        self.sync:startSession()
        if self:syncEnabled() then
            UIManager:scheduleIn(3, function() if self.sync then self.sync:pull(false) end end)
        end
    end
end

function Grimmory:onEndOfBook()
    if self.sync and self:syncEnabled() then self.sync:push(true) end
end

function Grimmory:onCloseDocument()
    if self.sync then
        self.sync:onLeave()
        self.sync = nil
    end
end

---------------------------------------------------------------- library

function Grimmory:onShowGrimmoryLibrary(touchmenu)
    closeTouchMenu(touchmenu)
    if not self.api:isPaired() then
        UIManager:show(ConfirmBox:new{
            text = _("This Kindle isn't connected to Grimmory yet. Connect now with a QR code?"),
            ok_text = _("Connect"),
            ok_callback = function() self:onGrimmoryPair() end,
        })
        return true
    end
    NetworkMgr:runWhenOnline(function() Browser:new(self):show() end)
    return true
end

function Grimmory:downloadDir()
    local home = G_reader_settings:readSetting("home_dir") or Device.home_dir or DataStorage:getDataDir()
    local dir = home .. "/Grimmory"
    if lfs.attributes(dir, "mode") ~= "directory" then util.makePath(dir) end
    return dir
end

function Grimmory:localPathFor(book_id)
    local entry = book_id and self.store.downloads[tostring(book_id)]
    if type(entry) == "table" and entry.path and lfs.attributes(entry.path, "mode") == "file" then
        return entry.path
    end
end

function Grimmory:downloadAndOpen(book, menu)
    local dir = self:downloadDir()
    local name = type(book.primaryFileName) == "string" and book.primaryFileName:match("[^/\\]+$") or nil
    if not name or name == "" then
        local ext = (type(book.primaryFileType) == "string" and book.primaryFileType:lower() or "epub")
        if ext == "cbx" then ext = "cbz" end
        name = (book.title or ("book-" .. tostring(book.id))) .. "." .. ext
    end
    name = util.getSafeFilename(name, dir)
    local path = dir .. "/" .. name
    local title = type(book.title) == "string" and book.title or name
    Download.start(self, book, path, function(ok, err, watching)
        if not ok then
            if err ~= "cancelled" then self:showError(err) end
            return
        end
        self.store.downloads[tostring(book.id)] = {
            path = path,
            title = title,
            format = type(book.primaryFileType) == "string" and book.primaryFileType or nil,
            file_id = tonumber(book.primaryFileId),
        }
        self:save()
        if watching then
            self:openBook(path, menu)
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("“%1” has finished downloading. Open it now?"), title),
                ok_text = _("Open"),
                cancel_text = _("Later"),
                ok_callback = function() self:openBook(path, menu) end,
            })
        end
    end)
end

function Grimmory:openBook(path, menu)
    if menu then UIManager:close(menu) end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then
        ReaderUI.instance:switchDocument(path)
    else
        ReaderUI:showReader(path)
    end
end

return Grimmory
