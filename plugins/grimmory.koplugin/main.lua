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
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ConfirmBox = require("ui/widget/confirmbox")
local NetworkMgr = require("ui/network/manager")
local Net = require("grimmory_net")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Api = require("grimmory_api")
local Sync = require("grimmory_sync")
-- Loaded on first use (pairing, browsing, downloading, read aloud), not at start.
local LAZY = { Browser = "grimmory_browser", PairPage = "grimmory_pairpage", PairScreen = "grimmory_pairscreen",
    PairServer = "grimmory_pairserver", Download = "grimmory_download", TTS = "grimmory_tts",
    Annotations = "grimmory_annotations" }
local Mod = setmetatable({}, { __index = function(t, k)
    local v = require(LAZY[k])
    rawset(t, k, v)
    return v
end })
local Log = require("grimmory_log")
local Index = require("grimmory_index")
local JSON = require("json")
local ReadMenu = require("grimmory_readmenu")
local Bookmarks = require("grimmory_bookmarks")

local PAIR_TIMEOUT_S = 10 * 60
local PAIR_MAX_ATTEMPTS = 5
local MAX_QUEUED_SESSIONS = 200

-- Night mode makes legacy Kindles unusably slow (software inversion): keep it off.
pcall(function() require("grimmory_nightguard").install() end)

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
        pcall(function() require("grimmory_timezone").apply() end)
    end
    self.settings = Grimmory.shared_settings
    require("grimmory_audioengine").root = self.path
    self.store = self.settings:readSetting("state", {})
    self.store.downloads = self.store.downloads or {}
    self.store.pending = self.store.pending or { progress = {}, sessions = {} }
    Log.enabled = self.store.logging_disabled ~= true
    self.api = Api:new(self.store, function() self:save() end)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if not self.ui.document and not self.store.home_is_library then
        -- Grimmory build: the home folder is the Grimmory folder (no setup question)
        pcall(self.useLibraryAsHome, self)
    end
    if not self.ui.document then
        -- download status in ZenOS's title bar (after every plugin has loaded)
        UIManager:nextTick(function() pcall(function() require("grimmory_tasks").installStatusBar() end) end)
        -- Pre-size downloaded books' covers in the background (fast Home/library)
        pcall(function()
            local Warm = require("grimmory_coverwarm")
            Warm.schedule(self, Warm.START_DELAY)
            require("common/cover_disk_cache").on_new_size = function() Warm.schedule(self, 30) end
        end)
        pcall(self.restoreFromManifest, self)
        -- downloads / audiobook preparing cut short last time: ask what to do
        pcall(function() require("grimmory_recovery").schedule(self) end)
        if self.api:isPaired() then
            UIManager:scheduleIn(8, function()
                if not NetworkMgr:isConnected() then return end
                pcall(require("grimmory_shelfsync").run, self)
                local idx = Index.load(self.store)
                if idx then
                    pcall(self.relinkLibrary, self, idx)
                    pcall(require("grimmory_titles").backfill, self)
                end
                if Index.isStale(idx) then
                    Index.build(self, false, function(built)
                        if built then
                            pcall(self.relinkLibrary, self, built)
                            pcall(require("grimmory_titles").backfill, self)
                        end
                    end)
                end
            end)
        end
    end
    if not self.ui.document and self.ui.menu and not Device:isTouchDevice() and Device:hasKeyboard() then
        -- Kindle Keyboard: the Menu key opens GZreader's Home menu (a list
        -- with letter keys) instead of the touch quick-settings panel.
        -- ZenOS's Home page, its lists and OPDS call onShowMenu() directly,
        -- so that is the one replaced (HomeMenu.fullMenu() sets _gz_full to
        -- reach the original).
        local fm_menu = self.ui.menu
        local orig_show = fm_menu.onShowMenu
        local orig_key = fm_menu.onKeyPressShowMenu
        local plugin = self
        fm_menu.onShowMenu = function(m, ...)
            if not m._gz_full and G_reader_settings:nilOrTrue("gzreader_home_menu") then
                return require("grimmory_homemenu").show(plugin)
            end
            return orig_show and orig_show(m, ...)
        end
        fm_menu.onKeyPressShowMenu = function(m, a, k)
            if G_reader_settings:nilOrTrue("gzreader_home_menu") then
                return require("grimmory_homemenu").show(plugin)
            end
            return orig_key and orig_key(m, a, k) or (orig_show and orig_show(m))
        end
    end
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
                local n = require("grimmory_tasks").count()
                return n > 0 and T(_("Downloads (%1)"), n) or _("Downloads")
            end,
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                require("grimmory_tasks").show()
            end,
        },
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
        require("grimmory_shelfsync").menuItems(self),
        {
            text = _("Pre-size covers"),
            help_text = _("In the background, makes each downloaded book's cover at the exact sizes Home and the library show it, and keeps them, so covers appear without the Kindle scaling them every time."),
            checked_func = function() return not G_reader_settings:isFalse("gzreader_presize_covers") end,
            callback = function()
                G_reader_settings:flipNilOrTrue("gzreader_presize_covers")
                local Disk = require("common/cover_disk_cache")
                Disk.enabled = not G_reader_settings:isFalse("gzreader_presize_covers")
                if Disk.enabled then require("grimmory_coverwarm").schedule(self, 5) else Disk.clear() end
            end,
        },
        {
            text = _("Wi-Fi only when needed"),
            help_text = _("Saves battery: GZreader turns Wi-Fi on by itself for browsing Grimmory, downloads, updates and syncing when a book opens or closes (and on wake after 15 minutes or more), then turns it off after a minute of not being used. Reading-position and bookmark changes made in between wait and go with the next sync. Wi-Fi you turn on yourself stays on."),
            checked_func = function() return G_reader_settings:nilOrTrue("gzreader_wifi_on_demand") end,
            callback = function() G_reader_settings:flipNilOrTrue("gzreader_wifi_on_demand") end,
        },
        {
            text = _("Menu key opens the GZreader menu"),
            help_text = _("On the Home screen and in lists, the Menu key opens a list with letter shortcuts (like the Reading menu) instead of ZenOS's quick-settings panel. \"Quick panel\" in it opens ZenOS's panel."),
            checked_func = function() return G_reader_settings:nilOrTrue("gzreader_home_menu") end,
            callback = function() G_reader_settings:flipNilOrTrue("gzreader_home_menu") end,
        },
        {
            text = _("Sync bookmarks"),
            help_text = _("Keep page bookmarks the same here and in Grimmory (its web reader and other devices)."),
            checked_func = function() return self.store.bookmark_sync_disabled ~= true end,
            callback = function()
                self.store.bookmark_sync_disabled = (self.store.bookmark_sync_disabled ~= true) or nil
                self:save()
            end,
        },
        {
            text = _("Sync highlights and notes"),
            help_text = _("Keep highlights and notes in EPUBs the same here and in Grimmory (its web reader and other devices). A highlight changed in both places since the last sync is left as it is in each."),
            checked_func = function() return self.store.annotation_sync_disabled ~= true end,
            callback = function()
                self.store.annotation_sync_disabled = (self.store.annotation_sync_disabled ~= true) or nil
                self:save()
                if self.annotations and not self.store.annotation_sync_disabled then self.annotations:run() end
            end,
        },
        {
            text = _("Read aloud settings"),
            callback = function() self:showTtsSettings() end,
        },
        {
            text = _("Audiobooks"),
            sub_item_table_func = function() return self:audiobookItems() end,
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
            text = _("Send diagnostic log to my phone (QR code)"),
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                self:shareLog()
            end,
        },
        {
            text = _("Save diagnostic log (USB)"),
            callback = function() self:exportLog() end,
            separator = true,
        },
        {
            text = "GZreader updates",
            sub_item_table_func = function() return require("grimmory_update").menuItems() end,
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
    local lib = self:libraryDir()
    local dest_dir = lib:match("^(.+)/[^/]+$") or lib -- next to the library, not in it
    -- On a Kindle, include a read-only audio / text-to-speech survey.
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Saving diagnostic log…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local dest, err = Log.exportTo(dest_dir, DataStorage:getDataDir() .. "/crash.log")
    UIManager:close(busy)
    if dest then
        Log.info("log exported to", dest)
        UIManager:show(InfoMessage:new{
            text = T(_("Diagnostic log saved:\n%1\n\nConnect the Kindle over USB to copy it."), dest),
        })
    else
        UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log: %1"), tostring(err)) })
    end
end

--- Send the diagnostic log to a phone over Wi-Fi: the Kindle serves it on a
--- one-off address shown as a QR code (same mini web server as QR sign-in).
--- The phone saves the file, which can then be attached anywhere.
function Grimmory:shareLog()
    if self.pairing then return end
    if not Net.connected() and Net.enabled() then
        return Net.run(function() self:shareLog() end, { reason = "sending the log" })
    end
    local lib = self:libraryDir()
    local dest_dir = lib:match("^(.+)/[^/]+$") or lib
    Log.probe_device = Device:isKindle()
    local busy = InfoMessage:new{ text = _("Preparing the diagnostic log…"), timeout = 0 }
    UIManager:show(busy)
    UIManager:forceRePaint()
    local dest, err = Log.exportTo(dest_dir, DataStorage:getDataDir() .. "/crash.log")
    UIManager:close(busy)
    local f = dest and io.open(dest, "rb")
    if not f then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't save the log: %1"), tostring(err)) })
    end
    local content = f:read("*a")
    f:close()
    local filename = dest:match("[^/]+$")
    local token = Mod.PairServer.randomToken(16)
    local base = "/log/" .. token
    local server, screen, timeout_task, done
    local function finish()
        if done then return end
        done = true
        if timeout_task then UIManager:unschedule(timeout_task) end
        if server then UIManager:removeZMQ(server); server:stop() end
        if screen then UIManager:close(screen) end
        self.pairing = nil
    end
    local page = string.format([[<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GZreader diagnostic log</title><style>body{font-family:system-ui,sans-serif;max-width:32em;margin:2em auto;padding:0 1em;line-height:1.5}
a.b{display:inline-block;padding:.8em 1.4em;background:#000;color:#fff;border-radius:.5em;text-decoration:none;font-weight:600}</style></head>
<body><h1>GZreader diagnostic log</h1><p>%s (%d KB). Passwords and tokens are never in it.</p>
<p><a class="b" href="%s/%s" download="%s">Download the log</a></p>
<p>Then attach the downloaded file wherever you need it, for example in your chat with Claude.</p></body></html>]],
        filename, math.ceil(#content / 1024), base, filename, filename)
    server = Mod.PairServer:new{
        handler = function(method, path)
            if method ~= "GET" then return 405, "text/plain", "Method not allowed" end
            if path == base then return 200, "text/html", page end
            if path == base .. "/" .. filename then
                Log.info("log sent to phone", filename, #content, "bytes")
                return 200, "text/plain", content,
                    { ["Content-Disposition"] = 'attachment; filename="' .. filename .. '"' }
            end
            return 404, "text/plain", "Not found"
        end,
    }
    local ok, serr = server:start()
    if not ok then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start sharing: %1"), tostring(serr)) })
    end
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local iface = NetworkMgr.getNetworkInterfaceName and NetworkMgr:getNetworkInterfaceName() or nil
    local ip, why = Mod.PairServer.localIp(hint_host, iface)
    if not ip then
        server:stop()
        return UIManager:show(InfoMessage:new{
            text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") .. "\n\n" .. tostring(why) })
    end
    self.pairing = true
    UIManager:insertZMQ(server)
    local url = T("http://%1:%2%3", ip, server.port, base)
    Log.info("sharing log on", T("http://%1:%2", ip, server.port))
    screen = Mod.PairScreen:new{
        url = url,
        title = _("Send the diagnostic log"),
        instructions = T(_("Scan this code with your phone's camera and tap \"Download the log\". Your phone must be on the same Wi-Fi as this Kindle.\n\nThe log was also saved as %1."), dest),
        footer = _("Press Back when you're done."),
        on_cancel = function() screen = nil; finish() end,
    }
    UIManager:show(screen)
    timeout_task = function() finish() end
    UIManager:scheduleIn(PAIR_TIMEOUT_S, timeout_task)
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
    Net.run(function() self:startQrPairing() end, { reason = "connecting to Grimmory" })
    return true
end

function Grimmory:onGrimmoryKeyboardLogin()
    self:keyboardLogin()
    return true
end

function Grimmory:startQrPairing()
    if self.pairing then return end
    local token = Mod.PairServer.randomToken(16)
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
        return 200, "text/html", Mod.PairPage.form(opts)
    end

    local function succeeded()
        UIManager:nextTick(function()
            finish()
            self:announceConnected()
        end)
        return 200, "text/html", Mod.PairPage.success(self.store.username)
    end

    local function failed(form, err)
        if attempts >= PAIR_MAX_ATTEMPTS then
            UIManager:nextTick(function()
                finish()
                UIManager:show(InfoMessage:new{ text = _("Pairing stopped after too many failed attempts.") })
            end)
            return 200, "text/html", Mod.PairPage.gone()
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
            verifier = Mod.PairServer.randomToken(32), -- 64 hex chars, valid PKCE verifier
            nonce = Mod.PairServer.randomToken(16),
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
        local params = Mod.PairServer.parseForm(query)
        local session = sso_session
        if params.error then
            sso_session = nil
            return failed({ server = session and session.base }, T(_("Sign-in didn't complete: %1"),
                params.error_description or params.error))
        end
        if not session or not params.code or params.state ~= session.state then
            return 200, "text/html", Mod.PairPage.gone()
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

    server = Mod.PairServer:new{
        handler = function(method, full_path, _headers, body)
            local path, query = full_path:match("^([^?]*)%??(.*)$")
            if path == "/oauth2-callback" and method == "GET" and not done then
                return finishSso(query)
            end
            if path ~= base_path then
                return 404, "text/plain", "Not found"
            end
            if done then
                return 200, "text/html", Mod.PairPage.gone()
            end
            if method == "GET" then
                return formPage{ server = self.store.server, username = self.store.username }
            elseif method ~= "POST" then
                return 405, "text/plain", "Method not allowed"
            end
            local form = Mod.PairServer.parseForm(body)
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
    local ip, why = Mod.PairServer.localIp(hint_host, iface)
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
    screen = Mod.PairScreen:new{
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
    local ip = Mod.PairServer.localIp(hint_host, iface)
    local uri = ip and T("http://%1:%2/oauth2-callback", ip, Mod.PairServer.port) or _("(connect to Wi-Fi to see it)")
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
                Net.run(function()
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

--- Send progress and reading sessions queued while offline. In the
--- background (grimmory_async): sending a backlog can take many seconds.
function Grimmory:flushPending()
    if self.flushing or not self.api:isPaired() or not NetworkMgr:isConnected() then return end
    local pending = self.store.pending
    if next(pending.progress) == nil and #pending.sessions == 0 then return end
    self.flushing = true
    local progress, sessions = {}, {}
    for book_id, body in pairs(pending.progress) do progress[book_id] = body end
    for i, body in ipairs(pending.sessions) do
        sessions[i] = body
        -- remembered before sending: if this attempt's reply is lost, the
        -- next one first looks in Grimmory's history instead of re-posting
        body.gz_tries = (body.gz_tries or 0) + 1
    end
    if #sessions > 0 then self:save() end
    require("grimmory_async").run(self.api, function(api)
        local sent, dropped, n_sessions = {}, {}, 0
        for book_id, body in pairs(progress) do
            local ok, _, code = api:putProgress(book_id, body)
            if ok then sent[#sent + 1] = book_id
            elseif code == 404 or code == 400 or code == 403 then dropped[#dropped + 1] = book_id -- the book is gone
            else break end -- still offline; try again later
        end
        for _i, body in ipairs(sessions) do
            local ok, code
            if (body.gz_tries or 0) > 1 and api:hasSession(body) then
                ok = true -- already saved by an earlier attempt whose reply was lost
                require("grimmory_log").info("reading session already in Grimmory, not sent again", body.bookId, body.startTime)
            else
                local res = { api:postSession(body) }
                ok, code = res[1], res[3]
            end
            if ok or code == 400 or code == 404 then n_sessions = n_sessions + 1 else break end
        end
        return { sent = sent, dropped = dropped, sessions = n_sessions }
    end, function(res)
        self.flushing = nil
        if type(res) ~= "table" then return end
        for _i, book_id in ipairs(res.sent or {}) do
            local body = progress[book_id]
            -- only clear it if nothing newer was queued meanwhile
            if pending.progress[book_id] == body then pending.progress[book_id] = nil end
            local entry = self.store.downloads[book_id]
            if entry and body and body.fileProgress then entry.last_pushed_pct = body.fileProgress.progressPercent end
        end
        for _i, book_id in ipairs(res.dropped or {}) do
            if pending.progress[book_id] == progress[book_id] then pending.progress[book_id] = nil end
        end
        for _i = 1, tonumber(res.sessions) or 0 do
            if pending.sessions[1] == sessions[_i] then table.remove(pending.sessions, 1) end
        end
        self:save()
    end, "flush")
end

function Grimmory:onNetworkConnected()
    UIManager:scheduleIn(2, function() self:flushPending() end)
    -- auto-download shelf (at most every 30 min)
    UIManager:scheduleIn(6, function() pcall(require("grimmory_shelfsync").run, self) end)
end

---------------------------------------------------------------- reader integration

--- Grimmory book id + download entry for an open file, if it came from Grimmory.
function Grimmory:entryForPath(path)
    if not path then return end
    for id, entry in pairs(self.store.downloads) do
        if type(entry) == "table" and entry.path == path then return id, entry end
    end
end

function Grimmory:setupReader()
    -- Read aloud (any reflowable book) and the keyboard Reading menu.
    self.tts = Mod.TTS.Reader:new(self.ui)
    local menu = self.ui.menu
    if menu and not Device:isTouchDevice() and Device:hasKeyboard() then
        local orig = menu.onKeyPressShowMenu
        menu.onKeyPressShowMenu = function(m, a, k)
            if G_reader_settings:nilOrTrue("gzreader_reading_menu") then
                ReadMenu.show(self)
                return true
            end
            return orig(m, a, k)
        end
    end
end

function Grimmory:onKeyPress(key)
    if not (self.ui.document and self.tts and type(key) == "table") then return end
    if key.key == "ShiftSym" then
        self.tts:toggle()
        return true
    end
    -- The Kindle Keyboard's volume rocker sets the read-aloud volume.
    if key.key == "VPlus" or key.key == "VMinus" then
        Mod.TTS.setVolume(Mod.TTS.volume() + (key.key == "VPlus" and 1 or -1))
        UIManager:show(require("ui/widget/notification"):new{
            text = T(_("Read-aloud volume %1 / %2"), Mod.TTS.volume(), Mod.TTS.VOLUME_MAX) })
        return true
    end
end

function Grimmory:onAnnotationsModified(items)
    if self.bookmarks then self.bookmarks:onAnnotationsModified(items) end
    if self.annotations then self.annotations:onAnnotationsModified(items) end
end

function Grimmory:showTtsSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function speedRow()
        return {
            { text = _("Slower"), callback = function()
                Mod.TTS.setSpeed(math.max(50, Mod.TTS.speed() - 10)); UIManager:close(dialog); self:showTtsSettings()
            end },
            { text = T(_("Speed %1"), Mod.TTS.speed()), enabled = false },
            { text = _("Faster"), callback = function()
                Mod.TTS.setSpeed(math.min(200, Mod.TTS.speed() + 10)); UIManager:close(dialog); self:showTtsSettings()
            end },
        }
    end
    local function volumeRow()
        local function set(v)
            Mod.TTS.setVolume(v); UIManager:close(dialog); self:showTtsSettings()
            Mod.TTS.say("Volume " .. Mod.TTS.volume() .. ".")
        end
        return {
            { text = _("Quieter"), callback = function() set(Mod.TTS.volume() - 1) end },
            { text = T(_("Volume %1 / %2"), Mod.TTS.volume(), Mod.TTS.VOLUME_MAX), enabled = false },
            { text = _("Louder"), callback = function() set(Mod.TTS.volume() + 1) end },
        }
    end
    dialog = ButtonDialog:new{
        title = _("Read aloud\nShift + Sym starts and stops reading. The sentence being read is highlighted and pages turn by themselves."),
        buttons = {
            volumeRow(),
            speedRow(),
            { { text = _("Find the Kindle voice (test)"), callback = function()
                UIManager:close(dialog); Mod.TTS.findVoice()
            end } },
            { { text = _("Close"), callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function Grimmory:onReaderReady()
    if not self.ui.document then return end
    pcall(self.setupReader, self)
    pcall(function() require("grimmory_picturebook").onOpen(self.ui) end)
    local book_id, entry = self:entryForPath(self.ui.document.file)
    if not book_id then return end
    if not entry.file_id and self.api:isPaired() and NetworkMgr:isConnected() then
        -- Downloaded by an older version of this plugin: look up the file id once.
        local book = self.api:getBook(book_id)
        local pf = book and type(book.primaryFile) == "table" and tonumber(book.primaryFile.id)
        if pf then entry.file_id = pf; self:save(); self:writeManifest() end
    end
    Log.info("opened Grimmory book", book_id, "file_id", tostring(entry.file_id), "format", tostring(entry.format))
    self.sync = Sync:new(self, self.ui, entry, book_id)
    self.sync:onReady()
    self.bookmarks = Bookmarks:new(self.sync)
    UIManager:scheduleIn(4, function()
        if self.bookmarks and self.sync and self.ui.document then pcall(self.bookmarks.reconcile, self.bookmarks) end
    end)
    local anno = Mod.Annotations:new(self.sync)
    self.annotations = anno
    UIManager:scheduleIn(6, function()
        if self.annotations == anno then pcall(anno.run, anno) end
    end)
    if self:syncEnabled() and self.api:isPaired() and not Net.connected() then
        -- Wi-Fi only when needed: bring it up quietly to sync this book
        Net.run(function() self:syncOpenBook() end, { quiet = true, reason = "sync on open" })
    end
end

--- Pull position, send queued updates and bookmarks for the open book.
function Grimmory:syncOpenBook()
    if not (self.sync and self.ui.document) then return end
    self:flushPending()
    self.sync:pull(false)
    if self.bookmarks then pcall(self.bookmarks.reconcile, self.bookmarks) end
    if self.annotations then pcall(self.annotations.run, self.annotations) end
end

function Grimmory:hasPending()
    local p = self.store.pending
    return p and (next(p.progress or {}) ~= nil or #(p.sessions or {}) > 0)
end

function Grimmory:onPageUpdate()
    if self.sync then self.sync:onPageTurned() end
    if self.tts then self.tts:onManualPageTurn() end
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
    Net.run(function()
        if not self.sync then return end
        self.sync:push(true)
        self.sync:pull(true)
        if self.bookmarks then pcall(self.bookmarks.reconcile, self.bookmarks) end
        if self.annotations then pcall(self.annotations.run, self.annotations) end
    end, { reason = "sync now" })
    return true
end

function Grimmory:showAudiobookMenu()
    local Menu = require("ui/widget/menu")
    local menu
    local items = self:audiobookItems()
    for _i, it in ipairs(items) do
        local cb = it.callback
        it.callback = cb and function() UIManager:close(menu); cb() end
    end
    menu = Menu:new{ title = _("Audiobooks"), item_table = items, is_borderless = true, is_popout = false,
        covers_fullscreen = true, title_bar_fm_style = true }
    UIManager:show(menu)
end

function Grimmory:audiobookItems()
    local Audiobook = require("grimmory_audiobook")
    local Engine = require("grimmory_audioengine")
    local items = {}
    local cur = Audiobook.current
    if cur then
        items[#items + 1] = {
            text = T(_("Now playing: %1"), cur.book.title or "?"),
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                Audiobook.open(self, cur.book)
            end,
            separator = true,
        }
    end
    for _i, e in ipairs(Audiobook.downloaded(self)) do
        items[#items + 1] = {
            text = e.book.title or "?",
            mandatory = Audiobook.fmt(e.pos or 0),
            callback = function(touchmenu)
                if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
                Audiobook.open(self, e.book)
            end,
        }
    end
    items[#items + 1] = {
        text = _("Browse Grimmory audiobooks"),
        enabled_func = function() return self.api:isPaired() end,
        callback = function(touchmenu)
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            local b = Mod.Browser:new(self); b:show(); b:openAudiobooks()
        end,
        separator = true,
    }
    items[#items + 1] = {
        text = _("Test audio playback"),
        help_text = _("Plays two short tunes (MP3, and AAC as in M4B audiobooks) with each way this Kindle can play audio and asks which you heard."),
        callback = function(touchmenu)
            if touchmenu and touchmenu.closeMenu then touchmenu:closeMenu() end
            Engine.test()
        end,
    }
    return items
end

function Grimmory:onSuspend()
    local ok_ab, Audiobook = pcall(require, "grimmory_audiobook")
    if ok_ab and Audiobook.current and Audiobook.current.playing then Audiobook.current:pause() end
    if self.tts then self.tts:stop() end
    if self.sync then self.sync:onLeave() end
    self.suspended_at = os.time()
    Net.onSuspend()
end

Grimmory.WAKE_SYNC_AFTER = 15 * 60 -- Wi-Fi only when needed: sync on wake after a long sleep

function Grimmory:onResume()
    UIManager:scheduleIn(5, function() self:flushPending() end)
    if self.sync then
        self.sync:startSession()
        if self:syncEnabled() then
            UIManager:scheduleIn(3, function() if self.sync then self.sync:pull(false) end end)
            local slept = self.suspended_at and os.time() - self.suspended_at or 0
            if slept >= Grimmory.WAKE_SYNC_AFTER and self.api:isPaired() and not Net.connected() then
                -- maybe read elsewhere meanwhile
                UIManager:scheduleIn(4, function()
                    Net.run(function() self:syncOpenBook() end, { quiet = true, reason = "sync on wake" })
                end)
            end
        end
    end
end

function Grimmory:onEndOfBook()
    if self.sync and self:syncEnabled() then self.sync:push(true) end
end

function Grimmory:onCloseDocument()
    if self.tts then self.tts:stop(); self.tts = nil end
    self.bookmarks = nil
    if self.annotations then
        pcall(self.annotations.onClose, self.annotations)
        self.annotations = nil
    end
    if self.sync then
        self.sync:onLeave()
        pcall(self.sync.releaseCfi, self.sync)
        self.sync = nil
    end
    if self.api:isPaired() and self:hasPending() and not Net.connected() then
        -- Wi-Fi only when needed: send where you stopped reading
        UIManager:scheduleIn(1, function()
            Net.run(function() self:flushPending() end, { quiet = true, reason = "sync on close" })
        end)
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
    -- open at once: lists come from their saved copies while Wi-Fi connects
    Mod.Browser:new(self):show()
    if not Net.connected() then Net.run(function() end, { quiet = true, reason = "Grimmory library" }) end
    return true
end

--- The Grimmory folder: downloads go straight in, and it's KOReader's home
--- folder (the "Downloaded" tab). Created on first use and remembered.
function Grimmory:libraryDir()
    local dir = self.store.library_dir
    if not dir then
        local home = G_reader_settings:readSetting("home_dir") or Device.home_dir or DataStorage:getDataDir()
        local previous = home .. "/Grimmory" -- where earlier versions saved downloads
        if lfs.attributes(previous, "mode") == "directory" then
            dir = previous
        else
            dir = (Device.home_dir or home) .. "/Grimmory"
        end
        self.store.library_dir = dir
        self:save()
        Log.info("library folder:", dir)
    end
    if lfs.attributes(dir, "mode") ~= "directory" then util.makePath(dir) end
    return dir
end
Grimmory.downloadDir = Grimmory.libraryDir

--- Make the Grimmory folder KOReader's home folder (no prompt).
function Grimmory:useLibraryAsHome()
    local dir = self:libraryDir()
    if G_reader_settings:readSetting("home_dir") ~= dir then
        G_reader_settings:saveSetting("home_dir", dir)
        Log.info("home folder set to", dir)
    end
    if G_reader_settings:readSetting("collate") == nil then
        -- same sort default ZenOS's folder page applied: most recently opened first
        G_reader_settings:saveSetting("collate", "access")
        G_reader_settings:saveSetting("collate_mixed", true)
    end
    self.store.home_is_library = true
    self:save()
    -- show it now; looked up later because during startup the file manager
    -- isn't registered yet
    UIManager:nextTick(function()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager.instance
        if fm and fm.file_chooser and fm.file_chooser.goHome then
            pcall(fm.file_chooser.goHome, fm.file_chooser)
        end
    end)
    return dir
end

---------------------------------------------------------------- downloads list backup

-- The list of downloaded Grimmory books also lives in the books folder
-- (hidden file), so replacing the koreader folder (and its settings) on an
-- update doesn't forget which local files are Grimmory books.
local MANIFEST = ".gzreader-library.json"

function Grimmory:writeManifest()
    local dir = self.store.library_dir
    if not dir then return end
    local list = {}
    for id, e in pairs(self.store.downloads) do
        if type(e) == "table" and e.path then
            list[#list + 1] = { id = id, file = e.path:match("[^/]+$"), title = e.title,
                format = e.format, file_id = e.file_id, last_pushed_pct = e.last_pushed_pct }
        end
    end
    local f = io.open(dir .. "/" .. MANIFEST, "wb")
    if f then f:write(JSON.encode({ version = 1, books = list })); f:close() end
end

--- Merge the backup list into the settings (after an update wiped them).
function Grimmory:restoreFromManifest()
    local dir = self.store.library_dir
    local f = dir and io.open(dir .. "/" .. MANIFEST, "rb")
    if not f then return 0 end
    local ok, data = pcall(JSON.decode, f:read("*a"))
    f:close()
    local restored = 0
    if ok and type(data) == "table" and type(data.books) == "table" then
        for _, b in ipairs(data.books) do
            local id = b.id and tostring(b.id)
            local path = type(b.file) == "string" and (dir .. "/" .. b.file)
            if id and path and not self.store.downloads[id] and lfs.attributes(path, "mode") == "file" then
                self.store.downloads[id] = { path = path, title = b.title, format = b.format,
                    file_id = tonumber(b.file_id), last_pushed_pct = tonumber(b.last_pushed_pct) }
                restored = restored + 1
            end
        end
    end
    if restored > 0 then
        Log.info("restored", restored, "downloaded books from", MANIFEST)
        self:save()
    end
    return restored
end

--- Match books in the folder that aren't linked yet to Grimmory books by
--- file name, using the library index. Returns the number linked.
function Grimmory:relinkLibrary(index)
    local dir = self.store.library_dir
    if not dir or not index or type(index.files) ~= "table" then return 0 end
    local linked_paths = {}
    for _, e in pairs(self.store.downloads) do if type(e) == "table" and e.path then linked_paths[e.path] = true end end
    local by_safe_name = {}
    for name, info in pairs(index.files) do
        by_safe_name[util.getSafeFilename(name, dir)] = info
        by_safe_name[name] = info
    end
    local linked = 0
    for name in lfs.dir(dir) do
        local path = dir .. "/" .. name
        local info = by_safe_name[name]
        if info and not linked_paths[path] and lfs.attributes(path, "mode") == "file" then
            local id = tostring(info[1])
            if not self.store.downloads[id] then
                self.store.downloads[id] = { path = path, title = info[4], format = info[3], file_id = tonumber(info[2]) }
                linked = linked + 1
            end
        end
    end
    if linked > 0 then
        Log.info("relinked", linked, "books already on the Kindle")
        self:save()
        self:writeManifest()
    end
    return linked
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
    Mod.Download.start(self, book, path, function(ok, err, watching, info)
        info = info or {}
        if not ok then
            if err ~= "cancelled" then
                if info.queued then
                    UIManager:show(InfoMessage:new{ text = T(_("“%1” couldn't be downloaded: %2"), title, tostring(err)), timeout = 5 })
                else
                    self:showError(err)
                end
            end
            return
        end
        local entry = {
            path = path,
            title = title,
            subtitle = info.subtitle,
            format = type(book.primaryFileType) == "string" and book.primaryFileType or nil,
            file_id = tonumber(book.primaryFileId),
        }
        self.store.downloads[tostring(book.id)] = entry
        self:save()
        self:writeManifest()
        pcall(function() require("grimmory_coverwarm").schedule(self, 15) end)
        local Titles = require("grimmory_titles")
        local sub = info.subtitle or Titles.subtitle(self, book.id)
        if sub then
            entry.subtitle = sub
            local okA, did = pcall(Titles.apply, path, title, sub, type(book.authors) == "table" and table.concat(book.authors, "\n") or nil)
            if okA and did then
                UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
            end
        end
        local shown = Titles.full(title, sub)
        if watching then
            self:openBook(path, menu)
        elseif info.queued or (info.left or 0) > 0 then
            UIManager:show(InfoMessage:new{
                text = (info.left or 0) > 0 and T(_("Downloaded “%1”. %2 more in the queue."), shown, info.left)
                    or T(_("Downloaded “%1”. The download queue is done."), shown),
                timeout = 4 })
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("“%1” has finished downloading. Open it now?"), shown),
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
