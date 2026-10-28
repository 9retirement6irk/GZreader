--[[--
Grimmory for KOReader.

* Pair with a Grimmory server by scanning a QR code shown on the Kindle (the
  phone does the typing), or by typing on the Kindle's own keyboard.
* Browse the library and download books (text-only lists, no thumbnails).
* Configure KOReader's progress sync (kosync) against Grimmory's KOReader
  endpoint automatically, creating the sync account on the server if needed.

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
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local Api = require("grimmory_api")
local Browser = require("grimmory_browser")
local PairPage = require("grimmory_pairpage")
local PairScreen = require("grimmory_pairscreen")
local PairServer = require("grimmory_pairserver")

local PAIR_TIMEOUT_S = 10 * 60
local PAIR_MAX_ATTEMPTS = 5

--- Edit KOReader's progress-sync settings in place. kosync's module (and its
--- LuaSettings object) is loaded once per run and shared by every reader
--- session, so update that cached object when it exists instead of only the file.
local function editKOSyncSettings(fn)
    local PluginLoader = require("pluginloader")
    local mod
    for _, p in ipairs(PluginLoader.enabled_plugins or {}) do
        if p.name == "kosync" then mod = p break end
    end
    local obj = mod and mod.settings_obj
    if not obj then
        obj = LuaSettings:open(DataStorage:getSettingsDir() .. "/kosync.lua")
        if mod then mod.settings_obj = obj end
    end
    local cfg = obj:readSetting("settings")
    if type(cfg) ~= "table" then
        cfg = {}
        for k, v in pairs(mod and mod.default_settings or {}) do cfg[k] = v end
        obj:saveSetting("settings", cfg)
    end
    fn(cfg)
    obj:flush()
end

local Grimmory = WidgetContainer:extend{
    name = "grimmory",
    is_doc_only = false,
}

function Grimmory:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/grimmory.lua")
    self.store = self.settings:readSetting("state", {})
    self.store.downloads = self.store.downloads or {}
    self.api = Api:new(self.store, function() self:save() end)
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Grimmory:save()
    self.settings:saveSetting("state", self.store)
    self.settings:flush()
end

function Grimmory:onDispatcherRegisterActions()
    Dispatcher:registerAction("grimmory_library", {
        category = "none", event = "ShowGrimmoryLibrary", title = _("Grimmory library"),
        general = true, filemanager = true, reader = true,
    })
    Dispatcher:registerAction("grimmory_pair", {
        category = "none", event = "GrimmoryPair", title = _("Grimmory: connect with QR code"),
        general = true, filemanager = true, reader = true,
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
        {
            text = paired and _("Reconnect with QR code") or _("Connect with QR code"),
            callback = function(touchmenu) self:onGrimmoryPair(touchmenu) end,
        },
        {
            text = _("Connect by typing"),
            callback = function() self:keyboardLogin() end,
            separator = true,
        },
        {
            text = _("Disconnect"),
            enabled_func = function() return self.api:isPaired() end,
            callback = function() self:confirmDisconnect() end,
        },
    }
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
    no_sync_permission = _("Your Grimmory account doesn't have the KOReader Sync permission. An admin can enable it in Settings → Users."),
}

function Grimmory:describeError(err)
    if type(err) == "string" and ERRORS[err] then return ERRORS[err] end
    if type(err) == "string" and err:match("^http_") then
        return T(_("Grimmory returned an error (%1)."), err:sub(6))
    end
    return T(_("Something went wrong: %1"), tostring(err))
end

function Grimmory:showError(err)
    UIManager:show(InfoMessage:new{ text = self:describeError(err), icon = "notice-warning" })
end

---------------------------------------------------------------- pairing

--- Log in, then wire up progress sync. Returns ok, err, sync_ok.
function Grimmory:connect(server_input, username, password)
    local server = Api.normalizeServer(server_input)
    if not server then return false, _("That server address doesn't look right.") end
    username = (username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if username == "" or not password or password == "" then
        return false, _("Enter your username and password.")
    end
    self.api.explicit_https = server_input:match("^%s*https://") ~= nil
    local ok, err = self.api:login(server, username, password)
    if not ok then return false, self:describeError(err) end
    local sync_ok, sync_err = self:setupProgressSync()
    if not sync_ok then logger.warn("Grimmory: progress sync setup failed:", sync_err) end
    return true, nil, sync_ok, sync_err
end

function Grimmory:setupProgressSync()
    local username, key = self.api:ensureSyncAccount(function() return PairServer.randomToken(12) end)
    if not username or not key then return false, key end
    self.store.sync_username = username
    self:save()

    local kosync_settings = {
        custom_server = self.store.server .. "/api/koreader",
        username = username,
        userkey = key,
        checksum_method = 0, -- binary: Grimmory matches books by file hash
        auto_sync = true,
        sync_forward = 2,    -- jump ahead silently when another device is further along
        sync_backward = 3,   -- never jump backwards automatically
    }
    -- kosync only keeps auto-sync on when KOReader may turn Wi-Fi on by itself.
    G_reader_settings:saveSetting("wifi_enable_action", "turn_on")

    editKOSyncSettings(function(cfg)
        for k, v in pairs(kosync_settings) do cfg[k] = v end
    end)
    return true
end

function Grimmory:onGrimmoryPair(touchmenu)
    closeTouchMenu(touchmenu)
    NetworkMgr:runWhenOnline(function() self:startQrPairing() end)
    return true
end

function Grimmory:startQrPairing()
    if self.pairing then return end
    local token = PairServer.randomToken(16)
    local attempts = 0
    local done = false
    local server, screen, timeout_task

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

    local base_path = "/pair/" .. token
    server = PairServer:new{
        handler = function(method, path)
            path = path:gsub("%?.*$", "")
            if path ~= base_path then
                return 404, "text/plain", "Not found"
            end
            if done then
                return 200, "text/html", PairPage.gone()
            end
            if method == "GET" then
                return 200, "text/html", PairPage.form{ server = self.store.server, username = self.store.username }
            elseif method ~= "POST" then
                return 405, "text/plain", "Method not allowed"
            end
            -- POST: the form body is read by the server and passed via `self.last_body`
            return nil
        end,
    }
    -- The handler needs the request body for POST; wrap it so we see all args.
    local route = server.handler
    server.handler = function(method, path, headers, body)
        local code, ctype, resp = route(method, path, headers, body)
        if code or method ~= "POST" then return code, ctype, resp end
        attempts = attempts + 1
        local form = PairServer.parseForm(body)
        local ok, err, sync_ok = self:connect(form.server or "", form.username or "", form.password or "")
        form.password = nil
        if ok then
            UIManager:nextTick(function()
                finish()
                self:announceConnected(sync_ok)
            end)
            return 200, "text/html", PairPage.success(self.store.username, sync_ok)
        end
        if attempts >= PAIR_MAX_ATTEMPTS then
            UIManager:nextTick(function()
                finish()
                UIManager:show(InfoMessage:new{ text = _("Pairing stopped after too many failed attempts.") })
            end)
            return 200, "text/html", PairPage.gone()
        end
        return 200, "text/html", PairPage.form{ server = form.server, username = form.username, error = err }
    end

    local ok, err = server:start()
    if not ok then
        return UIManager:show(InfoMessage:new{ text = T(_("Couldn't start pairing: %1"), tostring(err)) })
    end
    local hint_host = self.store.server and self.store.server:match("^https?://([^/:]+)")
    local ip = PairServer.localIp(hint_host)
    if not ip then
        server:stop()
        return UIManager:show(InfoMessage:new{ text = _("Couldn't find this Kindle's Wi-Fi address. Make sure Wi-Fi is connected.") })
    end

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

function Grimmory:announceConnected(sync_ok)
    local text = T(_("Connected to Grimmory as %1."), self.store.username or "")
    if sync_ok then
        text = text .. "\n\n" .. _("Reading progress will sync automatically for books you download from Grimmory.")
    else
        text = text .. "\n\n" .. ERRORS.no_sync_permission
    end
    UIManager:show(InfoMessage:new{ text = text })
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
                    local ok, err, sync_ok = self:connect(f[1], f[2], f[3])
                    UIManager:close(msg)
                    if ok then
                        self:announceConnected(sync_ok)
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
            NetworkMgr:runWhenConnected(function() self.api:logout() end)
            self.api:clearTokens()
            editKOSyncSettings(function(cfg)
                cfg.userkey, cfg.username, cfg.auto_sync = nil, nil, false
            end)
            UIManager:show(InfoMessage:new{ text = _("Disconnected from Grimmory."), timeout = 3 })
        end,
    })
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
    local msg = InfoMessage:new{ text = T(_("Downloading “%1”…"), book.title or name), timeout = 0 }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local ok, err = self.api:downloadBook(book.id, path)
    UIManager:close(msg)
    if not ok then return self:showError(err) end
    self.store.downloads[tostring(book.id)] = {
        path = path,
        title = type(book.title) == "string" and book.title or name,
        format = type(book.primaryFileType) == "string" and book.primaryFileType or nil,
    }
    self:save()
    self:openBook(path, menu)
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
