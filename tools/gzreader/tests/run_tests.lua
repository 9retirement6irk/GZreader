-- KOReader builds LuaJIT with LUA52COMPAT; mirror it for the stock interpreter
table.pack = table.pack or function(...) return { n = select("#", ...), ... } end
table.unpack = table.unpack or unpack
-- Functional tests for gzreader.koplugin against mock_grimmory.py.
-- Real LuaSocket + real plugin code; KOReader UI modules are stubbed.
local PLUGIN = arg[1]
local KOCOMMON = arg[2]       -- koreader/common (for dkjson)
local WORK = arg[3]           -- scratch work dir
local PORT = tonumber(arg[4])
KOROOT = arg[5]
package.path = package.path .. ";" .. KOROOT .. "/?.lua;" .. KOROOT .. "/frontend/?.lua"

package.path = PLUGIN .. "/?.lua;" .. KOCOMMON .. "/?.lua;" .. package.path

local socket = require("socket")
local ltn12 = require("ltn12")

local pass, fail = 0, 0
local function check(cond, name)
    if cond then pass = pass + 1; print("  ok   " .. name)
    else fail = fail + 1; print("  FAIL " .. name) end
end

---------------------------------------------------------------- stubs
local function magic()
    local m
    m = setmetatable({}, { __index = function() return function() return m end end, __call = function() return m end })
    return m
end
local function preload(name, val) package.preload[name] = function() return val end end

preload("logger", { dbg = function() end, info = function() end, warn = function(...) print("    [warn]", ...) end, err = function(...) print("    [err]", ...) end })
preload("gettext", function(s) return s end)
preload("json", require("dkjson"))
package.preload["ffi/sha2"] = function() return dofile(KOROOT .. "/ffi/sha2.lua") end
local socketutil = {
    LARGE_BLOCK_TIMEOUT = 10, LARGE_TOTAL_TIMEOUT = 30, FILE_BLOCK_TIMEOUT = 15, FILE_TOTAL_TIMEOUT = 60,
    set_timeout = function(_, a, b) return a, b end, reset_timeout = function() end,
    table_sink = function(t) return ltn12.sink.table(t) end,
    file_sink = function(h) return ltn12.sink.file(h) end,
}
preload("socketutil", socketutil)
preload("device", { isKindle = function() return false end, hasKeys = function() return true end,
    hasKeyboard = function() return true end, model = "Kindle3",
    isTouchDevice = function() return false end, home_dir = WORK .. "/home",
    input = { group = { Back = {} } }, screen = magic() })

local captured = { progress = {} }
preload("ui/widget/notification", { new = function(_, o) captured.notification = o.text; return o end })
local UI = { shown = {}, zmqs = {}, scheduled = {} }
preload("ui/uimanager", {
    show = function(_, w) table.insert(UI.shown, w) end,
    close = function(_, w) UI.closed = w; if w == captured.pdialog then captured.pdialog_open = false end end,
    forceRePaint = function() end,
    nextTick = function(_, f) f() end,
    scheduleIn = function(_, s, f) UI.scheduled[f] = s end,
    unschedule = function(_, f) UI.scheduled[f] = nil end,
    insertZMQ = function(_, z) table.insert(UI.zmqs, z) return z end,
    removeZMQ = function(_, z) for i = #UI.zmqs, 1, -1 do if UI.zmqs[i] == z then table.remove(UI.zmqs, i) end end end,
    setDirty = function() end,
    broadcastEvent = function() end,
})
NET = { connected = true }
captured.wifi = {}
preload("ui/network/manager", { runWhenOnline = function(_, f) f() end, runWhenConnected = function(_, f) f() end,
    isConnected = function() return NET.connected end, isWifiOn = function() return NET.connected end,
    enableWifi = function(_, cb) table.insert(captured.wifi, "on-quiet"); NET.connected = true; if cb then cb() end end,
    turnOnWifiAndWaitForConnection = function(_, cb) table.insert(captured.wifi, "on"); NET.connected = true; if cb then cb() end end,
    disableWifi = function() table.insert(captured.wifi, "off"); NET.connected = false end })
captured.custom_meta = {}
preload("docsettings", {
    findCustomMetadataFile = function(_, p) return captured.custom_meta[p] and (p .. ".sdr/custom_metadata.lua") or nil end,
    openSettingsFile = function(file)
        local doc = file and file:gsub("%.sdr/custom_metadata%.lua$", "")
        local o = { data = doc and captured.custom_meta[doc] or {} }
        function o:readSetting(k) return self.data[k] end
        function o:saveSetting(k, v) self.data[k] = v end
        function o:flushCustomMetadata(p) captured.custom_meta[p] = self.data; return true end
        return o
    end,
})
preload("ui/event", { new = function(_, name, ...) return { name = name, args = { ... } } end })
local function widgetClass()
    local C = {}
    C.__index = C
    function C:extend(o) o = o or {}; o.__index = o; return setmetatable(o, self) end
    function C:new(o) o = o or {}; setmetatable(o, self); self.__index = self; if o.init then o:init() end; return o end
    return C
end
preload("ui/widget/container/widgetcontainer", widgetClass())
preload("ui/widget/container/inputcontainer", widgetClass())
preload("ui/widget/progressbardialog", { extend = function(self, o) o.new = self.new; return o end, new = function(_, o)
    o.show = function(self) captured.pdialog = self; captured.pdialog_open = true end
    o.reportProgress = function(self, v) table.insert(captured.progress, v) end
    return o
end })
preload("ui/widget/buttondialog", { new = function(_, o) captured.buttons = o; return o end })
preload("ui/widget/infomessage", { new = function(_, o) captured.info = o.text; return o end })
preload("ui/widget/confirmbox", { new = function(_, o)
    captured.confirm = o
    o.added = {}
    o.addWidget = function(self, w) table.insert(self.added, w) end
    o.getAddedWidgetAvailableWidth = function() return 400 end
    return o
end })
preload("ui/widget/imagewidget", { new = function(_, o) return o end })
for _, n in ipairs({ "ui/widget/multiinputdialog", "ui/widget/inputdialog", "ui/widget/button",
        "ui/widget/container/centercontainer", "ui/widget/container/framecontainer", "ui/widget/qrwidget",
        "ui/widget/textboxwidget", "ui/widget/verticalgroup", "ui/widget/verticalspan", "ffi/blitbuffer",
        "ui/font", "ui/geometry", "ui/size", "dispatcher" }) do
    preload(n, magic())
end
-- Menu stub that records switched item tables
preload("ui/widget/menu", { new = function(_, o)
    o.item_table_stack = {}
    o.switchItemTable = function(self, title, items) self.title = title; self.item_table = items end
    o.onGotoPage = function(self, p) self.page = p end
    o.perpage = 14
    return o
end })

local settings_files = {}
preload("luasettings", { open = function(_, path)
    if settings_files[path] then return settings_files[path] end
    local s = { data = {}, flushed = 0 }
    function s:readSetting(k, default) if self.data[k] == nil and default ~= nil then self.data[k] = default end return self.data[k] end
    function s:saveSetting(k, v) self.data[k] = v end
    function s:flush() self.flushed = self.flushed + 1 end
    settings_files[path] = s
    return s
end })
preload("datastorage", { getSettingsDir = function() return WORK .. "/settings" end, getDataDir = function() return WORK end })
local kosync_mod = { name = "kosync", default_settings = { auto_sync = false, sync_forward = 1, sync_backward = 3, checksum_method = 0 } }
preload("pluginloader", { enabled_plugins = { kosync_mod } })
package.preload["libs/libkoreader-lfs"] = function() return require("lfs") end
package.preload["ffi/util"] = function() return dofile(KOROOT .. "/ffi/util.lua") end
preload("util", { makePath = function(p) os.execute("mkdir -p '" .. p .. "'") end,
    getSafeFilename = function(n) return (n:gsub("[/\\:*?\"<>|]", "_")) end })

local reader_opened
preload("apps/reader/readerui", { showReader = function(_, p) reader_opened = p end })

local gsettings = { gzreader_wifi_on_demand = false } -- the on-demand Wi-Fi tests turn it on
G_reader_settings = { saveSetting = function(_, k, v) gsettings[k] = v end, readSetting = function(_, k) return gsettings[k] end,
    nilOrTrue = function(_, k) return gsettings[k] == nil or gsettings[k] == true end,
    isTrue = function(_, k) return gsettings[k] == true end,
    makeTrue = function(_, k) gsettings[k] = true end,
    delSetting = function(_, k) gsettings[k] = nil end,
    flipNilOrTrue = function(_, k) if gsettings[k] == nil or gsettings[k] == true then gsettings[k] = false else gsettings[k] = nil end end }

---------------------------------------------------------------- helpers
local CTL = "http://127.0.0.1:" .. (PORT + 1)
local function ctl(path) local p = io.popen("curl -s '" .. CTL .. path .. "'"); local o = p:read("*a"); p:close(); return o end
local json = require("dkjson")

-- Run curl in the background and pump the pairing server until it finishes.
local function phone(args, server)
    local out = WORK .. "/phone_" .. tostring(math.random(1e9))
    os.execute("(curl -s -o '" .. out .. "' -w '%{http_code}' " .. args .. " > '" .. out .. ".code') &")
    for _ = 1, 400 do
        if #UI.zmqs > 0 then UI.zmqs[1]:waitEvent() elseif server and server.server then server:waitEvent() end
        local f = io.open(out .. ".code"); local c = f and f:read("*a"); if f then f:close() end
        if c and c ~= "" then
            local b = io.open(out):read("*a")
            return tonumber(c), b
        end
        socket.sleep(0.02)
    end
    return nil, nil
end

local function runLoop(pred, timeout)
    local t0 = socket.gettime()
    while socket.gettime() - t0 < (timeout or 20) do
        if pred() then return true end
        local due = {}
        for f in pairs(UI.scheduled) do due[#due + 1] = f end
        UI.scheduled = {}
        for _, f in ipairs(due) do f() end
        socket.sleep(0.05)
    end
    return pred()
end
local function pressButton(label)
    for _, row in ipairs(captured.buttons.buttons) do
        for _, btn in ipairs(row) do if btn.text == label then return btn.callback() end end
    end
    error("no button " .. label)
end

---------------------------------------------------------------- tests
os.execute("mkdir -p '" .. WORK .. "/settings' '" .. WORK .. "/home'")
local Grimmory = dofile(PLUGIN .. "/main.lua")
local AsyncMod = require("gzreader_async")
AsyncMod.sync = true -- most sections check results right away; the async section turns it off
local PairServer = require("gzreader_pairserver")
PairServer.port = PORT + 10

local plugin = Grimmory:new{ ui = { menu = { registerToMainMenu = function() end } } }

print("Pairing via QR (the phone page)")
check(not plugin.api:isPaired(), "starts unpaired")
local screen
local PS = require("gzreader_pairscreen")
local orig_new = PS.new
PS.new = function(self, o) screen = o; return o end
plugin:startQrPairing()
check(screen and screen.url and screen.url:match("^http://%d+%.%d+%.%d+%.%d+:%d+/phone/%x+#grimmory$") and not screen.url:match("^http://127%."), "QR encodes http://<lan ip>:<port>/phone/<token>#grimmory")
local token_path = screen.url:match("(/phone/%x+)")
local base = "http://127.0.0.1:" .. UI.zmqs[1].port
check(#token_path == 7 + 32, "token is 128-bit hex")

local code, body = phone("'" .. base .. "/phone/deadbeef'")
check(code == 404, "wrong token -> 404")
code, body = phone("'" .. base .. token_path .. "'")
check(code == 200 and body:find('action="' .. token_path .. '/grimmory"', 1, true) and body:find('action="' .. token_path .. '/memos"', 1, true)
    and body:find('action="' .. token_path .. '/caldav"', 1, true) and body:find('action="' .. token_path .. '/links"', 1, true)
    and body:find('id="files"', 1, true), "GET: one page with Grimmory, Notes, Calendar (account + links) and Send books")
code, body = phone("-X PUT '" .. base .. token_path .. "'")
check(code == 405, "other methods rejected")
code, body = phone("-X GET '" .. base .. token_path .. "/grimmory'")
check(code == 405, "actions are POST only")

local server_field = "127.0.0.1:" .. PORT -- no scheme: https first, then http fallback
local gpost = base .. token_path .. "/grimmory"
code, body = phone("-L --data-urlencode 'server=" .. server_field .. "' --data-urlencode 'username=will' --data-urlencode 'password=wrong' --data-urlencode 'action=password' '" .. gpost .. "'")
check(code == 200 and body:match("Wrong username or password") ~= nil, "bad password: the page explains (after POST → redirect)")
check(#UI.zmqs == 1, "page keeps running after a failed attempt")
check(not body:match("wrong\""), "password not echoed back")
check(body:find('value="127.0.0.1:' .. PORT .. '"', 1, true) and body:find('value="will"', 1, true), "typed address and user name kept in the form")

code, body = phone("-L --data-urlencode 'server=" .. server_field .. "' --data-urlencode 'username=will' --data-urlencode 'password=hunter22' --data-urlencode 'action=password' '" .. gpost .. "'")
check(code == 200 and body:match("Connected to Grimmory as will") ~= nil, "correct login -> the page says so")
check(#UI.zmqs == 1, "the page stays open (connect the rest, send books)")
check(plugin.api:isPaired(), "now paired")
check(plugin.store.server == "http://127.0.0.1:" .. PORT, "fell back from https to http for scheme-less LAN address")
check(plugin.store.password == nil and not json.encode(plugin.store):match("hunter22"), "password not stored")
screen.on_cancel()
check(#UI.zmqs == 0, "Back on the Kindle: page server removed from UI loop")
local s2 = socket.tcp(); s2:settimeout(0.5)
check(s2:connect("127.0.0.1", tonumber(base:match(":(%d+)$"))) == nil, "page port closed afterwards")
s2:close()
for f, delay in pairs(UI.scheduled) do if delay <= 15 then UI.scheduled[f] = nil end end -- (start-up checks: Wi-Fi, usage statistics)
check(next(UI.scheduled) == nil, "expiry timer cancelled")

print("Single sign-on from the phone page")
local function startPairing()
    PS.new = function(self, o) screen = o; return o end
    plugin:startQrPairing()
    local url = screen.url:gsub("#.*$", "")
    return url, url:match("^(http://[^/]+)"), url:match("(/phone/%x+)$")
end
plugin.api:clearTokens()
local sso_url, korigin, tpath = startPairing()
code, body = phone("'" .. sso_url .. "'")
check(body:match("9retirement6irk%.github%.io/GZreader/oauth2%-callback") ~= nil and body:match("same for every Kindle") ~= nil,
    "by default the page shows GZreader's hand-off page as the one redirect URI")
screen.on_cancel()
G_reader_settings:saveSetting("gzreader_sso_redirect", "kindle")
sso_url, korigin, tpath = startPairing()
code, body = phone("'" .. sso_url .. "'")
check(code == 200 and body:match("Sign in with Authentik") ~= nil, "page offers 'Sign in with Authentik' (provider from Grimmory's public settings)")
check(body:match(korigin:gsub("%p", "%%%0") .. "/oauth2%-callback") ~= nil, "page shows the exact redirect URI to register")
check(body:match('value="sso" formnovalidate') ~= nil, "SSO button skips the password fields' required checks")

local plug_before = plugin.store.refresh_token
local follow = "-L --max-redirs 5 --data-urlencode 'server=127.0.0.1:" .. PORT .. "' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'"
code, body = phone(follow)
check(code == 200 and body:match("Connected to Grimmory as will") ~= nil, "phone -> Kindle -> provider -> Kindle -> the page: connected")
check(plugin.api:isPaired() and plugin.store.username == "will", "paired via SSO, username from /users/me")
check(plugin.store.refresh_token ~= plug_before, "fresh Grimmory tokens stored")
check(json.decode(ctl("/state")).last_oidc_origin == korigin, "exchange sent Origin = Kindle redirect origin (Grimmory's check passes)")
code, body = phone("'" .. korigin .. "/oauth2-callback?code=again&state=again'")
check(code == 200 and body:match("has closed"), "the sign-in can't be replayed")
screen.on_cancel()
G_reader_settings:saveSetting("gzreader_sso_redirect", nil)
check(require("gzreader_phone").ssoRedirect(plugin, korigin) == korigin .. "/oauth2-callback",
    "a Kindle that signed in with its own address keeps using it")
plugin.store.sso_direct_ok = nil

print("Single sign-on through a hand-off page (phone on another network than Grimmory)")
do
local RELAY = "https://relay.example.com/gzreader/oauth2-callback"
G_reader_settings:saveSetting("gzreader_sso_redirect", RELAY)
plugin.api:clearTokens()
sso_url, korigin, tpath = startPairing()
code, body = phone("'" .. sso_url .. "'")
check(body:match("relay%.example%.com/gzreader/oauth2%-callback") ~= nil, "page shows your own hand-off page as the redirect URI")
local hdr = WORK .. "/sso_hdr"
local function location()
    local f = io.open(hdr); local h = f:read("*a"); f:close()
    return h:match("\n[Ll]ocation: ([^\r\n]+)")
end
code = phone("-D '" .. hdr .. "' --data-urlencode 'server=127.0.0.1:" .. PORT .. "' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'")
local loc = location() or ""
local unesc = require("socket.url").unescape
local back, go = loc:match("^" .. RELAY:gsub("%p", "%%%0") .. "#back=([^&]+)&go=(.+)$")
check(code == 302 and back and go, "Kindle sends the phone to the hand-off page with #back and #go")
check(back and unesc(back) == korigin .. "/oauth2-callback", "#back is this Kindle's own callback")
go = go and unesc(go) or ""
check(go:match("/idp/authorize%?tenant=x&") and go:match("redirect_uri=" .. require("socket.url").escape(RELAY):gsub("%p", "%%%0")),
    "#go is the provider's sign-in with redirect_uri = the hand-off page")
-- (the page's script: on to the provider; the provider sends the phone back to the page…)
code = phone("-D '" .. hdr .. "' '" .. go .. "'")
local ret = location() or ""
check(code == 302 and ret:sub(1, #RELAY + 1) == RELAY .. "?", "provider accepts the hand-off page and returns to it with ?code&state")
-- (…which forwards that to the Kindle)
code, body = phone("-L '" .. unesc(back) .. ret:sub(#RELAY + 1) .. "'")
check(code == 200 and body:match("Connected to Grimmory as will") ~= nil, "Kindle finishes the sign-in: connected")
check(json.decode(ctl("/state")).last_oidc_origin == "https://relay.example.com", "exchange sent Origin = the hand-off page's origin (Grimmory's check passes)")
check(not plugin.store.sso_direct_ok, "hand-off sign-in doesn't pin the Kindle's own address")
screen.on_cancel()
G_reader_settings:saveSetting("gzreader_sso_redirect", "relay")
check(require("gzreader_phone").ssoRedirect(plugin, korigin) == require("gzreader_phone").SSO_RELAY, "'relay' -> GZreader's page")
G_reader_settings:saveSetting("gzreader_sso_redirect", "http://insecure.example.com/oauth2-callback")
check(require("gzreader_phone").ssoRedirect(plugin, korigin) == require("gzreader_phone").SSO_RELAY, "a non-HTTPS page of your own is ignored")
local menu = plugin:ssoMenu()
local function picked() for _i, it in ipairs(menu) do if it.checked_func and it.checked_func() then return it.text end end end
G_reader_settings:saveSetting("gzreader_sso_redirect", nil)
check(#menu == 4 and picked():match("GZreader's sign%-in page"), "SSO menu: GZreader's page picked by default")
menu[4].callback()
check(picked():match("this Kindle's own address") and G_reader_settings:readSetting("gzreader_sso_redirect") == "kindle", "SSO menu: pick the Kindle's own address")
G_reader_settings:saveSetting("gzreader_sso_redirect", RELAY)
check(picked():match("your own copy"), "SSO menu: your own page shows as picked")
G_reader_settings:saveSetting("gzreader_sso_redirect", "kindle")
end

print("SSO failure paths")
sso_url, korigin, tpath = startPairing()
ctl("/set?idp_deny=true")
code, body = phone("-L --max-redirs 5 --data-urlencode 'server=127.0.0.1:" .. PORT .. "' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'")
check(code == 200 and body:match("Sign%-in didn") and body:match("User cancelled"), "cancel at provider -> the page explains, can retry")
check(#UI.zmqs == 1, "page still open after cancel")
ctl("/set?idp_deny=false&idp_strict=true")
code, body = phone("-L --max-redirs 5 --data-urlencode 'server=127.0.0.1:" .. PORT .. "' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'")
check(code == 400 and body:match("Invalid redirect URI"), "Kindle URI not registered -> provider's own error (why the setup note matters)")
ctl("/set?idp_strict=false")
code, body = phone("'" .. korigin .. "/oauth2-callback?code=forged&state=forged'")
check(code == 200 and body:match("has closed"), "forged/unknown state rejected without calling Grimmory")
code, body = phone("-L --data-urlencode 'server=' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'")
check(code == 200 and body:match("Enter your Grimmory address first"), "SSO without a server address -> clear error")
ctl("/set?oidc_enabled=false")
code, body = phone("-L --data-urlencode 'server=127.0.0.1:" .. PORT .. "' --data-urlencode 'action=sso' '" .. sso_url .. "/grimmory'")
check(body and body:match("turned on for this Grimmory server"), "server without SSO -> explains")
screen.on_cancel()

plugin.api:clearTokens()
sso_url = startPairing()
code, body = phone("'" .. sso_url .. "'")
check(not body:match("Sign in with"), "server without SSO -> no SSO button")
screen.on_cancel()
ctl("/set?oidc_enabled=true&oidc_force_only=true")
sso_url = startPairing()
code, body = phone("'" .. sso_url .. "'")
local sso_pos, pw_pos = body:find("Sign in with Authentik", 1, true), body:find("Use a local Grimmory password instead", 1, true)
check(sso_pos and pw_pos and sso_pos < pw_pos, "SSO-only server -> SSO first, password tucked away")
screen.on_cancel()
ctl("/set?oidc_force_only=false")
PS.new = orig_new
-- restore a password login for the remaining tests
plugin:connect("http://127.0.0.1:" .. PORT, "will", "hunter22")

print("Reconnect keeps state")
local ok = plugin:connect("http://127.0.0.1:" .. PORT, "will", "hunter22")
check(ok, "reconnect to same account works")
local srv_log = json.decode(ctl("/state")).log
local touched_ko = false
for _, e in ipairs(srv_log) do if e[2]:match("koreader") then touched_ko = true end end
check(not touched_ko, "never touches Grimmory's KOReader endpoints")

print("Token refresh")
local old_refresh = plugin.store.refresh_token
plugin.store.access_expires_at = 0
local data = plugin.api:listBooks{ page = 0, size = 5 }
check(data and #data.content == 5, "expired access token refreshed transparently")
check(plugin.store.refresh_token ~= old_refresh, "rotated refresh token stored")
ctl("/set?expire_next_access=true")
data = plugin.api:listBooks{ page = 0, size = 5 }
check(data ~= nil, "401 mid-session -> refresh once and retry")

print("Library browsing")
local Browser = require("gzreader_browser")
local b = Browser:new(plugin)
b:show()
b:openPaged("All books", { sort = "title", dir = "asc" })
local items = b.menu.item_table
local audiobooks = 0
for _, it in ipairs(items) do if it.book and it.book.primaryFileType == "AUDIOBOOK" then audiobooks = audiobooks + 1 end end
check(audiobooks == 0, "audiobooks filtered out")
check(#items == 26 and items[26].text:match("Load more"), "first page + 'Load more'")
items[26].callback()
check(#b.menu.item_table == 32 and not b.menu.item_table[32].text:match("Load more"), "second page appended, no more pages")
b:openSimple("continue-reading", "Continue reading")
check(#b.menu.item_table == 5, "continue reading list (audiobook dropped)")
check(b.menu.item_table[1].mandatory:match("13%%"), "progress shown")

print("Libraries, authors, series (local index of readable books)")
local Index = require("gzreader_index")
local root = Browser:new(plugin):rootItems()
local names = {}
for _, it in ipairs(root) do names[#names + 1] = it.text end
check(table.concat(names, "|"):match("All books.-|Libraries|Shelves|Authors|Series|Search"), "root menu: ... All books, Libraries, Shelves, Authors, Series, Search ...")
local function find(list, pat) for _, it in ipairs(list) do if it.text:match(pat) then return it end end end
local function texts(list) local t = {} for _, it in ipairs(list) do t[#t + 1] = it.text end return table.concat(t, "|") end

b = Browser:new(plugin); b:show()
captured.pdialog_open = false
b:openAuthors()
check(captured.pdialog_open and captured.pdialog.title:match("Indexing"), "first time: index built with a progress bar")
runLoop(function() return b.menu.title == "Authors" end, 30)
local al = b.menu.item_table
check(al[1].text == "Search authors…" and al[2].text:match("Refresh") and al[3].text == "Author 0", "authors: search, refresh, then A–Z")
check(not texts(al):match("Audio Author"), "author with only audiobooks is left out")
check(find(al, "^Author 1$").mandatory:match("%d+ books"), "author shows how many readable books")
local idx = Index.load(plugin.store)
check(idx and idx.total == 32 and idx.files["book5.epub"] and idx.files["book5.epub"][1] == 5, "index: 32 readable books, file names recorded for relinking")
check(idx.subtitles and idx.subtitles["2"] == "Rodrick Rules", "index: subtitles from Grimmory's web book list")
check(b:bookItem({ id = 2, title = "Book 02", authors = { "A" }, primaryFileType = "EPUB" }).text == "Book 02: Rodrick Rules — A", "Grimmory lists show the subtitle")
check(require("gzreader_titles").full("Diary of a Wimpy Kid: Old School", "Old School") == "Diary of a Wimpy Kid: Old School", "subtitle not doubled when the title already has it")
local index_requests = 0
for _, e in ipairs(json.decode(ctl("/state")).log) do if e[2]:match("^/api/v1/app/books%?") then index_requests = index_requests + 1 end end
local before = index_requests
b = Browser:new(plugin); b:show()
b:openAuthors()
check(b.menu.title == "Authors", "second time: opens instantly from the saved index")
index_requests = 0
for _, e in ipairs(json.decode(ctl("/state")).log) do if e[2]:match("^/api/v1/app/books%?") then index_requests = index_requests + 1 end end
check(index_requests == before, "no network request for a fresh index")
find(b.menu.item_table, "^Author 1$").callback()
local auth_ok, an = true, 0
for _, it in ipairs(b.menu.item_table) do if it.book then an = an + 1; auth_ok = auth_ok and it.book.authors[1] == "Author 1" end end
check(b.menu.title == "Author 1" and an > 0 and auth_ok, "author opens their books")
b = Browser:new(plugin); b:show()
b:openAuthors("author 1")
check(b.menu.title == "Authors: author 1" and #b.menu.item_table == 1 and b.menu.item_table[1].text == "Author 1",
    "author search filters the index")

b = Browser:new(plugin); b:show()
b:openSeries()
local sl = b.menu.item_table
check(sl[1].text:match("Refresh") and sl[2].text == "Saga / Part One — Author 2, Author 0, Author 1", "series A–Z (refresh first), with its authors")
check(not texts(sl):match("Audio Only Saga"), "audiobook-only series left out")
check(sl[2].mandatory == "3 books", "series counts readable books only")
sl[2].callback()
local st = {}
for _, it in ipairs(b.menu.item_table) do st[#st + 1] = it.text:match("^(#[%d%.]+)") or "?" end
check(table.concat(st, ",") == "#1,#2,#2.5", "series books in order with numbers; audiobook left out; '/' in name works")

ctl("/set?lib500=true")
b = Browser:new(plugin); b:show()
b:openLibraries()
check(b.menu.title == "Libraries" and texts(b.menu.item_table) == "Comics|fiction", "server's 500 on app libraries: falls back to the web endpoint")
check(not texts(b.menu.item_table):match("Audiobooks"), "audiobook-only library hidden")
check(b.menu.item_table[1].mandatory == "16 books", "library counts readable books (from the index)")
b.menu.item_table[2].callback()
local lib_ok, n = true, 0
for _, it in ipairs(b.menu.item_table) do if it.book then n = n + 1; lib_ok = lib_ok and it.book.libraryId == 2 end end
check(b.menu.title == "fiction" and n > 0 and lib_ok, "library opens its books only")
ctl("/set?lib500=false")

print("Saved library lists (open at once offline or while Wi-Fi connects)")
do
    local Cache = require("gzreader_listcache")
    local function reqs(pat)
        local n = 0
        for _, e in ipairs(json.decode(ctl("/state")).log) do if e[2]:match(pat) then n = n + 1 end end
        return n
    end
    -- the earlier "Continue reading" was saved
    local was, wod = NET.connected, gsettings.gzreader_wifi_on_demand
    NET.connected = false
    gsettings.gzreader_wifi_on_demand = false -- nothing may turn Wi-Fi on
    local before = reqs("continue%-reading")
    b = Browser:new(plugin); b:show()
    b:openSimple("continue-reading", "Continue reading")
    check(b.menu.title == "Continue reading · saved" and #b.menu.item_table == 5, "offline: saved list shown at once, marked saved")
    check(reqs("continue%-reading") == before, "offline: no request made")
    b:openLibraries()
    check(b.menu.title == "Libraries · saved" and texts(b.menu.item_table) == "Comics|fiction", "offline: saved libraries")
    -- Wi-Fi comes up: the fresh list replaces the saved one in place
    gsettings.gzreader_wifi_on_demand = nil
    captured.wifi = {}
    b = Browser:new(plugin); b:show()
    b:openPaged("All books", { sort = "title", dir = "asc" })
    check(captured.wifi[1] == "on-quiet", "Wi-Fi turned on quietly in the background")
    check(b.menu.title == "All books" and #b.menu.item_table == 26, "then the fresh list replaces the saved copy")
    -- moved on to another list before the fresh one arrived: not overwritten
    local AsyncMod = require("gzreader_async")
    local pending
    AsyncMod.sync = false
    local orig_run = AsyncMod.run
    AsyncMod.run = function(api, fn, done) pending = function() done(fn(api)) end end
    b = Browser:new(plugin); b:show()
    b:openSimple("recently-added", "Recently added")
    local shown_saved = b.menu.title ~= "Recently added · saved" -- never saved yet: waits
    b:openSimple("continue-reading", "Continue reading")
    check(b.menu.title == "Continue reading · saved", "online: saved copy shown while the fresh one loads")
    local cr = pending
    b:push("Elsewhere", { { text = "x" } })
    cr()
    check(b.menu.title == "Elsewhere", "fresh list doesn't replace a screen you moved to")
    AsyncMod.run, AsyncMod.sync = orig_run, true
    check(shown_saved, "a list never fetched before waits for Grimmory")
    -- per account
    local user = plugin.store.username
    plugin.store.username = "someone-else"
    NET.connected = false
    gsettings.gzreader_wifi_on_demand = false
    captured.err = nil
    b = Browser:new(plugin); b:show()
    b:openSimple("continue-reading", "Continue reading")
    check(b.menu.title ~= "Continue reading · saved", "another account doesn't see these saved lists")
    plugin.store.username = user
    NET.connected, gsettings.gzreader_wifi_on_demand = was, wod
    local d = Cache.dir()
    local nfiles = 0
    for name in require("libs/libkoreader-lfs").dir(d) do if name:match("%.json$") then nfiles = nfiles + 1 end end
    check(nfiles >= 4, "lists saved on disk (" .. nfiles .. ")")
    check(Cache.key("p", { b = 2, a = { "x", "y" } }) == "p|a=x,y|b=2", "stable keys")
end

print("Download & open (background subprocess)")
local Download = require("gzreader_download")
local path = WORK .. "/home/GZreader/book3.epub"
UI.scheduled = {}
plugin.store.access_expires_at = 0                       -- token must be refreshed...
local refresh_before = json.decode(ctl("/state")).refresh_calls
reader_opened = nil
plugin:downloadAndOpen({ id = 3, title = "Book 03", primaryFileName = "book3.epub", primaryFileType = "EPUB", fileSizeKb = 4 }, nil)
check(captured.pdialog_open and captured.pdialog.progress_max == 4096, "progress dialog shown with expected size")
check(Download.active ~= nil, "UI not blocked: download running in a subprocess")
runLoop(function() return reader_opened ~= nil end, 15)
local f = io.open(path, "rb"); local sz = f and #f:read("*a"); if f then f:close() end
check(sz == 4200, "file downloaded intact")
check(io.open(path .. ".part") == nil, "no leftover .part file")
check(reader_opened == path and not captured.pdialog_open, "dialog closed, book opened")
check(plugin:localPathFor(3) == path, "download remembered (shows 'on Kindle')")
check(json.decode(ctl("/state")).refresh_calls == refresh_before + 1, "...refreshed once, in the parent (rotated token kept)")
check(plugin.store.downloads["3"].subtitle == "Old School", "subtitle fetched with the download")
local cmeta = captured.custom_meta[path]
check(cmeta and cmeta.custom_props.title == "Book 03: Old School" and cmeta.doc_props.title == "Book 03",
    "downloaded file gets the full title as KOReader custom metadata (Home/Downloaded show it); original kept")

ctl("/set?dl_big=true&dl_slow=true")
captured.progress = {}
reader_opened = nil
plugin:downloadAndOpen({ id = 4, title = "Big Book", primaryFileName = "big.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
runLoop(function() return #captured.progress >= 3 end, 15)
local p1, p3 = captured.progress[1], captured.progress[#captured.progress]
check(#captured.progress >= 3 and p3 > p1 and p3 < 2048 * 1024, "progress bar advances while downloading")
captured.pdialog:onAnyKeyPressed()
check(captured.buttons and captured.buttons.buttons[1][1].text == "Stop download", "any key -> Stop / Continue in background / Keep watching")
pressButton("Keep watching")
check(Download.active ~= nil, "Keep watching: still downloading")
captured.pdialog:onAnyKeyPressed(); pressButton("Stop download")
check(Download.active == nil and not captured.pdialog_open, "Stop download: dialog closed immediately")
runLoop(function() return false end, 1)
check(io.open(WORK .. "/home/GZreader/big.epub.part") == nil and io.open(WORK .. "/home/GZreader/big.epub") == nil, "stopped: partial file removed")
check(plugin.store.downloads["4"] == nil and reader_opened == nil, "stopped: nothing recorded, nothing opened")

captured.confirm = nil
plugin:downloadAndOpen({ id = 4, title = "Big Book", primaryFileName = "big.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
runLoop(function() return #captured.progress > 0 end, 5)
captured.pdialog:onAnyKeyPressed(); pressButton("Continue in background")
check(not captured.pdialog_open and Download.active ~= nil, "Continue in background: free to use other screens")
runLoop(function() return captured.confirm ~= nil end, 30)
check(captured.confirm and captured.confirm.text:match("finished downloading"), "told when the background download finishes")
local bf = io.open(WORK .. "/home/GZreader/big.epub", "rb"); local bsz = bf and bf:seek("end"); if bf then bf:close() end
check(bsz == 2 * 1024 * 1024, "background download complete (2 MB)")
captured.confirm.ok_callback()
check(reader_opened == WORK .. "/home/GZreader/big.epub", "Open from the notice")

ctl("/set?dl_slow=false&dl_stall=true")
Download.STALL_SECONDS = 3
captured.info = nil
plugin:downloadAndOpen({ id = 5, title = "Stuck", primaryFileName = "stuck.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
runLoop(function() return Download.active == nil end, 20)
check(captured.info and captured.info:match("stalled"), "stalled transfer stopped and reported")
stuck_part = require("libs/libkoreader-lfs").attributes(WORK .. "/home/GZreader/stuck.epub.part", "size") or 0
check(stuck_part > 0, "stalled: the part downloaded is kept, to continue")
Download.STALL_SECONDS = nil
ctl("/set?dl_stall=false")

print("Unfinished downloads after a restart")
do
    local R = require("gzreader_recovery")
    check(plugin.store.unfinished["book:5"] ~= nil, "the cut-short download is remembered")
    R.checked = false
    captured.buttons = nil
    R.check(plugin)
    check(captured.buttons and captured.buttons.title:match("Stuck") and captured.buttons.title:match("didn't finish"),
        "on start: asks about it")
    pressButton("Continue downloading")
    runLoop(function() return Download.active == nil end, 30)
    local f = io.open(WORK .. "/home/GZreader/stuck.epub", "rb"); local sz = f and f:seek("end"); if f then f:close() end
    check(sz == 2 * 1024 * 1024, "continued to the end: whole book (2 MB)")
    local rng
    for _, e in ipairs(json.decode(ctl("/state")).log) do if e[1] == "BOOKDL" and e[2]:match("/5/") then rng = e[3] end end
    check(rng == "bytes=" .. stuck_part .. "-", "only the rest was asked for (Range from " .. stuck_part .. ")")
    check(plugin.store.unfinished["book:5"] == nil, "finished: no longer remembered")
    -- delete and ignore
    local p1 = WORK .. "/home/GZreader/half.epub"
    local fh = io.open(p1 .. ".part", "wb"); fh:write("partial"); fh:close()
    R.bookStarted(plugin, { id = 41, title = "Half" }, p1)
    R.bookStarted(plugin, { id = 42, title = "Other" }, WORK .. "/home/GZreader/other.epub")
    R.checked = false
    R.check(plugin)
    pressButton("Delete what was downloaded")
    check(io.open(p1 .. ".part") == nil and plugin.store.unfinished["book:41"] == nil, "Delete: part removed, not asked again")
    check(captured.buttons.title:match("Other"), "then asks about the next one")
    pressButton("Ignore")
    check(plugin.store.unfinished["book:42"] == nil, "Ignore: not asked again")
    -- audiobooks
    R.audioStarted(plugin, { id = 77, title = "Long Listen" }, "prepare")
    R.checked = false
    R.check(plugin)
    check(captured.buttons.title:match("Preparing the audiobook “Long Listen”"), "audiobook preparing that didn't finish: asks")
    local cont
    for _, row in ipairs(captured.buttons.buttons) do if row[1].text == "Continue preparing" then cont = true end end
    check(cont, "offers to continue preparing")
    pressButton("Ignore")
end
ctl("/set?dl_big=false")

print("Download queue")
ctl("/set?dl_big=true&dl_slow=true")
reader_opened, captured.info = nil, nil
plugin:downloadAndOpen({ id = 26, title = "First", primaryFileName = "first.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
plugin:downloadAndOpen({ id = 27, title = "Second", primaryFileName = "second.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
check(#Download.queue == 1 and captured.info and captured.info:match("download queue %(1 waiting%)"), "second download queued instead of refused")
captured.info = nil
plugin:downloadAndOpen({ id = 27, title = "Second", primaryFileName = "second.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
check(#Download.queue == 1 and captured.info and captured.info:match("already"), "same book twice: not queued again")
check(Download.isQueued(26) and Download.isQueued(27) and not Download.isQueued(28), "queued/active books are known (list shows 'queued')")
do
    local Tasks = require("gzreader_tasks")
    plugin:downloadAndOpen({ id = 29, title = "Third", primaryFileName = "third.epub", primaryFileType = "EPUB", fileSizeKb = 2048 }, nil)
    local list = Tasks.list()
    check(#list == 3 and list[1].kind == "book" and list[1].title == "First" and list[2].kind == "queued" and list[3].title == "Third",
        "Downloads: the current one, then the queue")
    local icon, label = Tasks.status()
    check(icon and label:match("%d+%%") and label:match("%+2"), "title bar: percentage and how many wait " .. tostring(label))
    check(Download.unqueue(29) and #Download.queue == 1, "take a book out of the queue")
    local hm = require("gzreader_homemenu").items(plugin)
    check(hm[1].text_func():match("^Downloads %(2%)"), "GZreader menu starts with Downloads (2) while downloading")
    Tasks.show()
end
ctl("/set?dl_slow=false")
runLoop(function() return plugin.store.downloads["27"] ~= nil end, 40)
check(reader_opened == WORK .. "/home/GZreader/first.epub", "first (watched) download opens")
check(plugin.store.downloads["27"] ~= nil and Download.active == nil and #Download.queue == 0, "queued download ran after it")
check(captured.info and captured.info:match("Downloaded “Second”. The download queue is done."), "queued completion: short notice, no Open prompt per book")
check(require("gzreader_tasks").status() == nil and require("gzreader_tasks").count() == 0, "title bar item empty again when done")
ctl("/set?dl_big=false")

print("Diagnostic log")
local logf = io.open(WORK .. "/gzreader.log", "rb"); local logtxt = logf and logf:read("*a") or ""; if logf then logf:close() end
check(logtxt:match("download start") and logtxt:match("download done") and logtxt:match("download stopped: cancelled")
    and logtxt:match("stalled"), "downloads logged (start, done, cancelled, stalled)")
check(logtxt:match("HTTP POST http://127.0.0.1:%d+/api/v1/auth/login 200"), "requests logged with status")
check(not logtxt:match("hunter22") and not logtxt:match(plugin.store.refresh_token) and not logtxt:match(plugin.store.access_token),
    "no password or tokens in the log")
check(logtxt:match("/pair/<token>") or not logtxt:match("/pair/%x%x%x%x"), "pairing URL token redacted")
plugin:exportLog()
check(captured.info and captured.info:match("gzreader%-log%-%d+%-%d+%.txt"), "Save diagnostic log -> file in the books folder")

print("Grimmory folder is the home folder")
local libdir = WORK .. "/home/GZreader"
check(plugin.store.library_dir == libdir, "Grimmory folder created under the device's documents folder")
check(gsettings.home_dir == libdir and plugin.store.home_is_library == true, "home folder set to it on first start, no prompt")
check(gsettings.collate == "access", "sorted by recently opened, like ZenOS's folder setup")
check(plugin:localPathFor(3) == libdir .. "/book3.epub", "downloads saved straight into it (shows in the Downloaded tab)")
gsettings.home_dir = "/somewhere/else"                     -- user changes it later
Grimmory:new{ ui = { menu = { registerToMainMenu = function() end }, active_widgets = {} } }
check(gsettings.home_dir == "/somewhere/else", "only done once: a later choice of home folder is respected")
gsettings.home_dir = libdir
check(not (captured.info or ""):match("/Grimmory/grimmory%-log"), "exported log saved next to the folder, not inside it (no stray 'book')")

print("Update wiped the settings (books stay in the folder)")
local mf = io.open(libdir .. "/.gzreader-library.json")
check(mf ~= nil, "downloads list backed up in the books folder"); if mf then mf:close() end
local had = {}
for id in pairs(plugin.store.downloads) do had[#had + 1] = id end
plugin.store.downloads = {}                                -- what replacing koreader/settings did
local restored = plugin:restoreFromManifest()
check(restored == #had and plugin:localPathFor(3) == libdir .. "/book3.epub", "restored from the backup: books show again, sync resumes")
local lone = io.open(libdir .. "/book7.epub", "wb"); lone:write("x"); lone:close()   -- no record anywhere
check(plugin:localPathFor(7) == nil, "a book with no record isn't linked yet")
local linked = plugin:relinkLibrary(Index.load(plugin.store))
check(linked == 1 and plugin:localPathFor(7) == libdir .. "/book7.epub" and plugin.store.downloads["7"].file_id == 1007,
    "relinked to its Grimmory book by file name (with file id for sync)")

print("Tab action reaches the plugin from ZenOS Home")
local fmui = { menu = { registerToMainMenu = function() end }, active_widgets = {} }
local fmplug = Grimmory:new{ ui = fmui }
check(fmui.active_widgets[1] == fmplug, "file manager: plugin is an active widget (dispatcher events reach it)")
local rdui = { menu = { registerToMainMenu = function() end }, active_widgets = {}, document = { file = "/x.epub" } }
Grimmory:new{ ui = rdui }
check(#rdui.active_widgets == 0, "reader: not registered (no double page-turn events)")
check(fmplug.store == plugin.store, "all instances share one settings object")
do
    local full_shown = 0
    local hui = { menu = { registerToMainMenu = function() end, onShowMenu = function() full_shown = full_shown + 1; return true end }, active_widgets = {} }
    local hplug = Grimmory:new{ ui = hui }

    hui.menu:onShowMenu() -- what ZenOS's Home page calls for the Menu key
    local HomeMenu = require("gzreader_homemenu")
    check(full_shown == 0 and HomeMenu.open ~= nil, "Menu key on Home: GZreader menu instead of the quick-settings panel")
    local hk = HomeMenu.open and HomeMenu.open.key_events or {}
    check(hk.LeftButtonTap == nil and hk.GzCloseHomeMenu ~= nil, "the Menu key only closes the Home menu (no other Menu-key action)")
    local NM = require("ui/network/manager"); NM.isWifiOn = NM.isWifiOn or function() return true end
    local NG = require("gzreader_nightguard"); local ng_applies = NG.applies; NG.applies = function() return true end
    local items = HomeMenu.items(hplug)
    NG.applies = ng_applies
    local labels = {}
    for _i, it in ipairs(items) do labels[#labels + 1] = it.text or it.text_func() end
    local all = table.concat(labels, "|")
    check(all:match("Continue reading") and all:match("Wi%-Fi") and all:match("|Settings|") and not all:match("KOReader settings")
        and not all:match("Grimmory library") and not all:match("Audiobook") and not all:match("Night mode"),
        "menu lists Continue reading, Wi-Fi, Settings (no library, audiobooks or KOReader settings); no night mode on a Kindle 3… " .. all)
    -- Settings opens ZenOS's Settings page with the ZenOS plugin instance
    local opened = {}
    package.loaded["modules/settings/zen_settings_page"] = { show = function(z, o) opened[#opened + 1] = { z = z, o = o } end }
    package.loaded["apps/filemanager/filemanager"] = { instance = { zenos = "ZEN", menu = hui.menu } }
    for _i, it in ipairs(items) do
        if it.text == "Settings" then it.callback() end
    end
    check(#opened == 1 and opened[1].z == "ZEN" and opened[1].o == nil, "Settings -> Settings page")
    package.loaded["modules/settings/zen_settings_page"] = nil; package.loaded["apps/filemanager/filemanager"] = nil
    HomeMenu.open = nil

    hui.menu._gz_full = true; hui.menu:onShowMenu(); hui.menu._gz_full = nil
    check(full_shown == 1, "All settings reaches the original full menu")
    gsettings.gzreader_home_menu = false -- (the old setting no longer brings the quick panel back)
    hui.menu:onShowMenu()
    check(full_shown == 1 and HomeMenu.open ~= nil, "no touch screen: always the GZreader menu, never the quick panel")
    HomeMenu.open = nil
    gsettings.gzreader_home_menu = nil
    check(not all:match("Quick panel"), "and no Quick panel entry in it")

end

print("Download progress + staying awake")
do
    local Progress = require("gzreader_progress")
    check(Progress.status(116 * 1048576, 276 * 1048576) == "42% · 116.0 MB of 276.0 MB", "progress line: percent, downloaded, total " .. Progress.status(116 * 1048576, 276 * 1048576))
    check(Progress.status(3 * 1073741824, nil) == "3.00 GB downloaded", "no total: just the amount")
    local Awake = require("gzreader_awake")
    local cmds = {}
    local exec = Awake.exec
    Awake.exec = function(c) cmds[#cmds + 1] = c end
    Awake.hold("dl"); Awake.hold("audio")
    Awake.release("dl")
    check(#cmds == 1 and cmds[1]:match("preventScreenSaver 1"), "download + audiobook: screensaver blocked once, still blocked after the download ends")
    Awake.release("audio")
    check(#cmds == 2 and cmds[2]:match("preventScreenSaver 0"), "released when nothing needs it")
    Awake.exec = exec
end

print("Shelves")
do
    local list = plugin.api:listShelves()
    check(list and #list == 2 and list[1].name == "Kindle" and list[2].magic == true, "shelves and smart shelves listed")
    local SS = require("gzreader_shelfsync")
    SS.set(plugin, list[1])
    ctl("/set?dl_slow=false&dl_big=false")
    captured.info = nil
    SS.run(plugin, true)
    check(captured.info and captured.info:match("Downloading 3 new book%(s%) from “Kindle”"), "shelf: 3 new books queued for download " .. tostring(captured.info))
    runLoop(function() return plugin.store.downloads["12"] ~= nil and Download.active == nil end, 40)
    check(plugin:localPathFor(10) and plugin:localPathFor(11) and plugin:localPathFor(12), "the shelf's books downloaded in the background")
    captured.info = nil
    SS.run(plugin, true)
    check(captured.info and captured.info:match("already on this Kindle"), "second run: nothing new")
    plugin.store.auto_shelf_last = os.time()
    captured.info = nil
    SS.run(plugin) -- automatic, too soon
    check(captured.info == nil, "automatic runs at most every 30 minutes")
    SS.set(plugin, nil)
end

print("Settings in ZenOS's sections")
do
    local function texts(list)
        local t = {}
        for _i, it in ipairs(list) do t[#t + 1] = it.text or (it.text_func and it.text_func()) or "?" end
        return "|" .. table.concat(t, "|") .. "|"
    end
    local g = texts(plugin:menuItems())
    check(g:match("|Sync reading progress|") and not g:match("Audiobooks") and g:match("|Disconnect|")
        and not g:match("Downloads") and not g:match("Browse library") and not g:match("updates")
        and not g:match("Diagnostic") and not g:match("Read aloud") and not g:match("Pre%-size")
        and not g:match("Wi%-Fi only"), "Grimmory section: connection and sync only " .. g)
    local gen = plugin:sectionItems("general")
    check(gen.wifi and gen.wifi.text == "Wi-Fi only when needed", "General: Wi-Fi only when needed")
    local d = texts(gen.diagnostics)
    check(d:match("|Diagnostic logging|Remote debugging|Usage statistics|Send diagnostic log to my phone %(QR code%)|Save diagnostic log %(USB%)|"),
        "General: logging, remote debugging, usage statistics, send and save the log " .. d)
    check(texts(plugin:sectionItems("reader")) == "|Read aloud|Test audiobook playback|", "Reader: Read aloud, Test audiobook playback")
    check(texts(plugin:sectionItems("interface")) == "|Pre-size covers|", "Interface: Pre-size covers (the Menu key always opens GZreader's menu)")
    local test = plugin:sectionItems("reader")[2]
    check(test.keep_menu_open == true, "Test audiobook playback stays over Settings")
end

print("A touch Kindle (Paperwhite 3): no keys, no audio")
do
    local Device = require("device")
    local saved = { model = Device.model, kb = Device.hasKeyboard, touch = Device.isTouchDevice, keys = Device.hasKeys }
    local Touch = require("gzreader_touch")
    check(Touch.audio() and Touch.keys() and not Touch.on() and Touch.letter("Q") == "Q", "Kindle 3: keys, audio, letters")
    Device.model = "KindlePaperWhite3"
    Device.hasKeyboard = function() return false end
    Device.isTouchDevice = function() return true end
    Device.hasKeys = function() return false end
    check(not Touch.audio() and not Touch.keys() and Touch.on() and Touch.letter("Q") == nil, "Paperwhite: touch, no keys, no audio")
    check(Touch.text("Press N", "Tap New note") == "Tap New note", "Paperwhite: touch wording")
    local function texts(list)
        local t = {}
        for _i, it in ipairs(list) do t[#t + 1] = it.text or (it.text_func and it.text_func()) or "?" end
        return "|" .. table.concat(t, "|") .. "|"
    end
    check(texts(plugin:sectionItems("reader")) == "||", "Paperwhite: no Read aloud or audiobook test in Settings")
    check(texts(plugin:sectionItems("interface")) == "|Pre-size covers|", "Paperwhite: no Menu key setting")
    local Browser = require("gzreader_browser")
    local root = texts(Browser.rootItems({}))
    check(root:match("|Downloaded books|$") and not root:match("Audiobooks"), "Paperwhite: no Audiobooks in the Grimmory tab " .. root)
    -- the launcher: GZreader's menu, the phone page, Send books (once)
    local cfg = { entries = {}, next_id = 0 }
    local saved_model = package.loaded["modules/menu/app_launcher/model"]
    package.loaded["modules/menu/app_launcher/model"] = {
        ensure = function() return cfg end,
        next_id = function(c) c.next_id = c.next_id + 1; return "al_" .. c.next_id end,
        save = function(c) cfg = c end,
    }
    -- (an install from before 1.12.2: its three entries, no context)
    cfg.entries = {
        { id = "al_a", type = "plugin", label = "GZreader", plugin = { key = "gzreader", method = "onGzLauncherMenu" } },
        { id = "al_b", type = "plugin", label = "My phone", plugin = { key = "gzreader", method = "onGzLauncherPhone" } },
    }
    G_reader_settings:delSetting("gzreader_launcher_v2")
    plugin:addLauncherEntries()
    plugin:addLauncherEntries()
    local labels, ctx = {}, {}
    for _i, e in ipairs(cfg.entries) do
        labels[#labels + 1] = e.label
        ctx[e.label] = e.gz_context or "both"
    end
    check(#cfg.entries == #Grimmory.LAUNCHER, "launcher: every GZreader entry once (" .. table.concat(labels, ",") .. ")")
    check(labels[2] == "My phone" and ctx["My phone"] == "library", "launcher: an existing entry keeps your name, now Home-only")
    check(ctx.GZreader == "both" and ctx.Continue == "library" and ctx["Send books"] == "library"
        and ctx.Contents == "reader" and ctx.Bookmarks == "reader" and ctx["Fit pictures"] == "reader",
        "launcher: GZreader everywhere, Continue / Send books at Home, Contents / Bookmarks / Fit pictures in a book")
    local opened
    local orig_open = plugin.openPhonePage
    plugin.openPhonePage = function(_self, section) opened = section or "all" end
    plugin:onGzLauncherBooks()
    check(opened == "books", "Send books in the launcher opens the phone page at Send books")
    plugin:onGzLauncherPhone()
    check(opened == "all", "Phone in the launcher opens the whole phone page")
    plugin.openPhonePage = orig_open
    package.loaded["modules/menu/app_launcher/model"] = saved_model
    G_reader_settings:delSetting("gzreader_launcher_v1")
    -- the Kindle Touch: touch, a speaker (audiobooks), no keyboard (no read aloud)
    Device.model = "KindleTouch"
    Device.hasKeys = function() return true end -- (its Home button)
    check(Touch.on() and Touch.audio() and Touch.tts() and not Touch.dpad(), "Kindle Touch: touch, audiobooks, read aloud")
    check(texts(plugin:sectionItems("reader")) == "|Read aloud|Test audiobook playback|", "Kindle Touch: Read aloud and the audiobook test")
    check(texts(Browser.rootItems({})):match("|Audiobooks|$"), "Kindle Touch: Audiobooks in the Grimmory tab")
    -- the Kindle 4: the 5-way and Menu, no keyboard, no touch, no audio
    Device.model = "Kindle4"
    Device.isTouchDevice = function() return false end
    check(Touch.dpad() and not Touch.on() and not Touch.keys() and not Touch.audio() and Touch.letter("Q") == nil,
        "Kindle 4: 5-way, no letters, no audio")
    check(Touch.text("Press N", "Tap New note", "Menu → New note") == "Menu → New note", "Kindle 4: 5-way wording")
    check(texts(plugin:sectionItems("interface")) == "|Pre-size covers|", "Kindle 4: no Menu key setting (always GZreader's menu)")
    Device.lcd = {} -- (the Nook 1st Edition's colour touchscreen)
    check(texts(plugin:sectionItems("interface")) == "|Colour screen|Pre-size covers|", "Nook: Colour screen settings first")
    Device.lcd = nil
    local model_was = Device.model
    Device.model = "NookTouch"
    check(texts(plugin:sectionItems("interface")) == "|Touch orientation|Pre-size covers|", "Nook Simple Touch: Touch orientation")
    Device.model = model_was
    Device.isNook = function() return true end
    local html = require("gzreader_pairpage").gone()
    check(not html:find("Kindle") and html:find("Nook's screen") ~= nil, "Nook: the phone page says Nook, not Kindle")
    Device.isNook = nil
    check(require("gzreader_pairpage").gone():find("Kindle's screen") ~= nil, "Kindle: still Kindle")
    check(texts(plugin:sectionItems("reader")) == "||", "Kindle 4: no read aloud or audiobooks")
    cfg = { entries = {}, next_id = 0 }
    package.loaded["modules/menu/app_launcher/model"] = { ensure = function() return cfg end,
        next_id = function(c) c.next_id = c.next_id + 1; return "al_" .. c.next_id end, save = function(c) cfg = c end }
    plugin:addLauncherEntries()
    check(#cfg.entries == 0, "Kindle 4: nothing added to the touch launcher")
    package.loaded["modules/menu/app_launcher/model"] = saved_model
    G_reader_settings:delSetting("gzreader_launcher_v1")
    -- the Kindle 2 and DX (KOReader's Kindle 2 class) and DX Graphite: like the Kindle 3
    Device.hasKeyboard = function() return true end
    for _i, m in ipairs({ "Kindle2", "KindleDXG" }) do
        Device.model = m
        check(Touch.keys() and Touch.audio() and Touch.tts() and not Touch.dpad(), m .. ": keyboard, audio, read aloud")
    end
    Device.model, Device.hasKeyboard, Device.isTouchDevice, Device.hasKeys = saved.model, saved.kb, saved.touch, saved.keys
    check(Touch.audio() and Touch.keys(), "back to the Kindle 3")
end

print("Home menu: the playing audiobook")
do
    local HM = require("gzreader_homemenu")
    local AB = require("gzreader_audiobook")
    local orig_open, orig_cur = AB.open, AB.current
    local opened
    AB.open = function(_p, book) opened = book end
    HM.context = nil
    local book = { id = 5, title = "Treasure Island" }
    AB.current = { book = book, playing = true }
    local function find(prefix)
        for _i, it in ipairs(HM.items(plugin)) do
            local t = it.text or (it.text_func and it.text_func()) or ""
            if t:sub(1, #prefix) == prefix then return it, t end
        end
    end
    local it, t = find("Now playing: ")
    check(it and t == "Now playing: Treasure Island", "playing: Now playing entry " .. tostring(t))
    if it then it.callback() end
    check(opened == book, "…which opens the same player")
    AB.current.playing = false
    check(find("Audiobook paused: Treasure Island") ~= nil, "paused: Audiobook paused entry")
    AB.current = nil
    check(not find("Now playing") and not find("Audiobook paused"), "nothing playing: no entry")
    AB.open, AB.current = orig_open, orig_cur
end

print("Audiobooks: hidden storage, tiles and Recent")
do
    local Folder = require("gzreader_abfolder")
    local AB = require("gzreader_audiobook")
    local lib = plugin:libraryDir()
    -- the Kindle's EPUB writer (libarchive) isn't loadable here: record what's written
    local written = {}
    local saved_arch = package.loaded["ffi/archiver"]
    package.loaded["ffi/archiver"] = { Writer = { new = function()
        local w = { files = {} }
        function w:open(path) self.path = path; return true end
        function w:setZipCompression() return true end
        function w:addFileFromMemory(name, content) self.files[name] = content; return true end
        function w:close()
            local f = io.open(self.path, "wb"); f:write("PK"); f:close()
            written[#written + 1] = self
        end
        return w
    end } }
    local history, progress = {}, {}
    local saved_rh, saved_ds = package.loaded["readhistory"], package.loaded["docsettings"]
    package.loaded["readhistory"] = {
        addItem = function(_s, path) history[#history + 1] = path end,
        removeItemByPath = function(_s, path) history.removed = path end,
    }
    package.loaded["docsettings"] = { open = function(_s, path)
        return { saveSetting = function(_d, k, v) progress[path] = progress[path] or {}; progress[path][k] = v end,
                 flush = function() end }
    end }

    local old = lib .. "/Audiobooks/77"
    os.execute("mkdir -p '" .. old .. "/audiobook.m4b.chunks'")
    local f = io.open(old .. "/audiobook.m4b.chunks/c0.aac", "wb"); f:write("x"); f:close()
    f = io.open(old .. "/audiobook.json", "wb")
    f:write('{"id":"77","title":"A Walk in the Woods","durationMs":600000,"files":["audiobook.m4b.chunks/c0.aac"],'
        .. '"tracks":[{"file":"audiobook.m4b","start":0,"durationMs":600000}]}')
    f:close()
    local saved = plugin.store.audiobooks
    plugin.store.audiobooks = { ["77"] = { title = "A Walk in the Woods", author = "Bill Bryson", pos_ms = 60000 } }
    check(Folder.migrate(plugin) == 1 and lfs.attributes(lib .. "/.audiobooks/77/audiobook.json", "mode") == "file"
        and lfs.attributes(old, "mode") == nil, "old visible storage moved to the hidden .audiobooks folder")
    check(AB.load(plugin, "77") ~= nil, "…and still loads from there")
    check(Folder.syncStubs(plugin) == 1, "a stand-in book is written for the downloaded audiobook")
    local stub = Folder.stubPath(plugin, "77")
    check(stub == lib .. "/Audiobooks/A Walk in the Woods.epub" and lfs.attributes(stub, "mode") == "file",
        "…as Audiobooks/<title>.epub " .. tostring(stub))
    local opf = written[1] and written[1].files["OEBPS/content.opf"] or ""
    check(written[1].files.mimetype == "application/epub+zip" and opf:match("<dc:title>A Walk in the Woods</dc:title>")
        and opf:match("<dc:creator>Bill Bryson</dc:creator>") and not opf:match("cover%-image"),
        "…an EPUB with the title and author (no cover until it's fetched)")
    check(Folder.syncStubs(plugin) == 0, "not written again at the next start")
    -- with Grimmory's cover
    f = io.open(lib .. "/.audiobooks/77/cover.jpg", "wb"); f:write("JPEGDATA"); f:close()
    Folder.writeStub(plugin, "77")
    check(written[2].files["OEBPS/cover.jpg"] == "JPEGDATA" and written[2].files["OEBPS/content.opf"]:match('name="cover" content="cover%-image"')
        and plugin.store.audiobooks["77"].stub_cover == true, "rewritten with the cover once it's downloaded")
    check(Folder.idForPath(plugin, stub) == "77" and not Folder.idForPath(plugin, lib .. "/Other.epub"), "the stand-in maps back to the audiobook")
    -- opening the stand-in opens the player, not the reader
    local RUI = require("apps/reader/readerui")
    local orig_open, opened = AB.open, nil
    AB.open = function(_p, book) opened = book end
    local orig_show = RUI.showReader
    local reader_opened
    RUI.showReader = function() reader_opened = true end
    RUI._gz_audiobook_hook = nil
    Folder.install(plugin)
    RUI:showReader(stub)
    check(opened and opened.title == "A Walk in the Woods" and not reader_opened, "opening its tile starts the player, not the reader")
    local stopped
    local saved_cur = AB.current
    AB.current = { stop = function() stopped = true end }
    RUI:showReader(lib .. "/Other.epub")
    check(reader_opened, "other books still open in the reader")
    check(stopped, "opening a book stops the audiobook (the Kindle voice needs the sound device)")
    AB.current = saved_cur
    RUI.showReader, RUI._gz_audiobook_hook, AB.open = orig_show, nil, orig_open
    -- played: into history (Recent), with progress
    local invalidated
    local saved_home_loader = package.loaded["common/shared_state"]
    package.loaded["common/shared_state"] = { get = function() return { invalidateBookCache = function(p) invalidated = p end } end }
    rawset(_G, "__ZEN_UI_PLUGIN", rawget(_G, "__ZEN_UI_PLUGIN") or {})
    Folder.saveProgress(plugin, "77", 300000, 600000)
    check(invalidated == stub and math.abs(progress[stub].percent_finished - 0.5) < 1e-9, "progress saved: Home re-reads it (50%)")
    package.loaded["common/shared_state"] = saved_home_loader
    Folder.recordPlay(plugin, "77", 60000, 600000)
    check(history[#history] == stub and math.abs((progress[stub] or {}).percent_finished - 0.1) < 1e-9,
        "played: added to Recent / history with 10% progress")
    AB.delete(plugin, "77")
    check(lfs.attributes(stub, "mode") == nil and history.removed == stub and lfs.attributes(lib .. "/.audiobooks/77", "mode") == nil
        and next(plugin.store.audiobooks) == nil, "delete removes the audio, the tile and its history entry")
    plugin.store.audiobooks = saved
    package.loaded["ffi/archiver"], package.loaded["readhistory"], package.loaded["docsettings"] = saved_arch, saved_rh, saved_ds
end

print("Grimmory tab covers")
do
    local Covers = require("gzreader_covers")
    local Async = require("gzreader_async")
    local NetM = require("gzreader_net")
    local saved_sync, saved_conn = Async.sync, NetM.connected
    Async.sync, NetM.connected = true, function() return true end
    os.execute("rm -rf '" .. Covers.dir() .. "'"); Covers.dir_ok = nil
    check(Covers.state(1) == "missing", "no cover yet")
    local got
    local started = Covers.fetch(plugin, { { id = 1 }, { id = 2 }, { id = 3, kind = "audiobook" } }, function(n) got = n end)
    check(started and got == 2, "the page's covers are fetched in one go " .. tostring(got))
    check(Covers.state(1) == "have" and Covers.state(2) == "have", "…and kept on the Kindle")
    check(Covers.state(3, "audiobook") == "none", "no audiobook cover on Grimmory: remembered, not asked again")
    got = nil
    check(not Covers.fetch(plugin, { { id = 1 }, { id = 3, kind = "audiobook" } }, function(n) got = n end) and got == nil,
        "nothing missing: nothing fetched")
    NetM.connected = function() return false end
    check(not Covers.fetch(plugin, { { id = 9 } }), "Wi-Fi off: covers aren't fetched (and Wi-Fi isn't turned on for them)")
    Async.sync, NetM.connected = saved_sync, saved_conn
end

print("Managing downloaded books")
do
    local HM = require("gzreader_homemenu")
    local UIM = require("ui/uimanager")
    local bookpath = WORK .. "/home/GZreader/manage-me.epub"
    local f = io.open(bookpath, "wb"); f:write("x"); f:close()
    plugin.store.downloads["777"] = { path = bookpath, title = "Manage Me" }
    local ctx_called, prepend
    local home = { _zen_home_focus_targets = { { path = bookpath, context = function()
        ctx_called = true
        prepend = rawget(_G, "__GZ_CONTEXT_PREPEND")
    end } }, _zen_home_focus_index = 1 }
    local orig_top = UIM.getTopmostVisibleWidget
    UIM.getTopmostVisibleWidget = function() return home end
    HM.context = HM.highlighted()
    local items = HM.items(plugin)
    UIM.getTopmostVisibleWidget = orig_top
    check(items[1].text:match("^Manage “") and not (items[2].text or ""):match("^Delete “"),
        "highlighted book on Home: one Manage entry at the top " .. tostring(items[1].text))
    local all = {}
    for _i, it in ipairs(items) do all[#all + 1] = it.text or (it.text_func and it.text_func()) end
    local joined = "|" .. table.concat(all, "|") .. "|"
    check(joined:match("|Sort|") and joined:match("|Check for updates|") and not joined:match("Sort books"),
        "menu wording: Sort, Check for updates")
    items[1].callback()
    check(ctx_called, "Manage opens ZenOS's own book menu")
    check(type(prepend) == "table" and #prepend == 2 and prepend[1].text:match("Open$")
        and prepend[2].text:match("Delete from this Kindle$"), "…with Open and Delete added at the top")
    captured.confirm = nil
    prepend[2].callback()
    check(captured.confirm and captured.confirm.text:match("Grimmory keeps the book"), "delete asks first (and says Grimmory keeps it)")
    captured.confirm.ok_callback()
    check(not lfs.attributes(bookpath) and plugin.store.downloads["777"] == nil, "deleted: file gone, no longer marked downloaded")
    -- no ZenOS menu for it: separate Open and Delete entries
    f = io.open(bookpath, "wb"); f:write("x"); f:close()
    HM.context = { path = bookpath }
    items = HM.items(plugin)
    check(items[1].text:match("^Open “") and items[2].text:match("^Delete “"), "no book menu: Open and Delete entries")
    os.remove(bookpath)
    HM.context = nil
    check(not HM.items(plugin)[1].text or not HM.items(plugin)[1].text:match("^Open “"), "nothing highlighted: no book section")
end

print("Login refreshed in the background process")
do
    AsyncMod.sync = false
    plugin.store.access_expires_at = 0
    local old_refresh = plugin.store.refresh_token
    local before = json.decode(ctl("/state")).refresh_calls
    local got
    AsyncMod.run(plugin.api, function(api) return api:listLibraries() end, function(libs) got = libs end, "test")
    runLoop(function() return got ~= nil end, 20)
    check(type(got) == "table", "request made with a refreshed login")
    check(json.decode(ctl("/state")).refresh_calls == before + 1 and plugin.store.refresh_token ~= old_refresh
        and (plugin.store.access_expires_at or 0) > os.time(), "the rotated tokens come back to the app and are kept")
    got = nil
    AsyncMod.run(plugin.api, function(api) return api:listLibraries() end, function(libs) got = libs end, "test")
    runLoop(function() return got ~= nil end, 20)
    check(type(got) == "table" and json.decode(ctl("/state")).refresh_calls == before + 1, "next request: no second refresh")
    AsyncMod.sync = true
end

print("Big results from the background process (more than a pipe holds)")
do
    AsyncMod.sync = false
    local got, gerr
    local t0 = socket.gettime()
    -- ~600 KB of JSON: a Memos account with many long notes (1.5.0 timed out here)
    AsyncMod.run({}, function()
        local notes = {}
        for i = 1, 300 do notes[i] = { name = "memos/" .. i, content = string.rep("note text " .. i .. " ", 200) } end
        return { memos = notes }
    end, function(res, err) got, gerr = res, err end, "big")
    runLoop(function() return got ~= nil or gerr ~= nil end, 30)
    check(got and #got.memos == 300 and got.memos[300].content:match("^note text 300 "),
        "all of it arrives (" .. string.format("%.1f s", socket.gettime() - t0) .. ", " .. tostring(gerr) .. ")")
    got, gerr = nil, nil
    AsyncMod.background(function() return string.rep("x", 300000) end, function(res, err) got, gerr = res, err end, "big local")
    runLoop(function() return got ~= nil or gerr ~= nil end, 30)
    check(type(got) == "string" and #got == 300000, "the same for local background jobs")
    AsyncMod.sync = true
end

print("Cover when choosing a book")
do
    local B = require("gzreader_browser")
    local br = B:new(plugin); br:show()
    AsyncMod.sync = false
    captured.confirm = nil
    br:onBook({ id = 14, title = "Book 14", authors = { "Author" }, primaryFileType = "EPUB", fileSizeKb = 300, coverUpdatedOn = "2026-01-02T03:04:05Z" })
    check(captured.confirm and captured.confirm.text:match("Book 14") and #captured.confirm.added == 0, "dialog shows at once")
    local box = captured.confirm
    runLoop(function() return #box.added > 0 end, 20)
    local img = box.added[1]
    check(img and img.file and lfs.attributes(img.file, "size") and img.width <= 400, "Grimmory's cover is fetched and added to it " .. tostring(img and img.file))
    captured.confirm = nil
    br:onBook({ id = 14, title = "Book 14", primaryFileType = "EPUB", coverUpdatedOn = "2026-01-02T03:04:05Z" })
    check(captured.confirm and #captured.confirm.added == 1, "next time: from the cache, straight away")
    AsyncMod.sync = true
end

print("No duplicate reading sessions")
do
    local before = #json.decode(ctl("/state")).sessions
    local body = { bookId = 3, bookType = "EPUB", startTime = "2026-10-29T10:00:00Z", endTime = "2026-10-29T10:10:00Z",
        durationSeconds = 600, startProgress = 1, endProgress = 2, progressDelta = 1 }
    check(plugin.api:postSession(body), "a session reaches Grimmory (its reply then gets lost)")
    body.gz_tries = 1 -- what a lost reply leaves behind
    plugin.store.pending.sessions = { body }
    NET.connected = true
    plugin.flushing = nil
    plugin:flushPending()
    local after = #json.decode(ctl("/state")).sessions
    check(after == before + 1 and #plugin.store.pending.sessions == 0, "retry finds it in Grimmory's history: not sent twice")
    local fresh = { bookId = 3, bookType = "EPUB", startTime = "2026-10-29T11:00:00Z", endTime = "2026-10-29T11:10:00Z",
        durationSeconds = 600, startProgress = 2, endProgress = 3, progressDelta = 1 }
    plugin.store.pending.sessions = { fresh }
    plugin:flushPending()
    check(#json.decode(ctl("/state")).sessions == after + 1 and #plugin.store.pending.sessions == 0, "a new session is sent normally")
end

print("Compressed replies")
check((json.decode(ctl("/state")).gzip_replies or 0) > 0, "JSON lists arrive gzip-compressed and are unpacked (lists above worked)")

print("Requests in the background")
do
    AsyncMod.sync = false
    local got, gerr
    AsyncMod.call(plugin.api, "getBook", { 1 }, function(b, e) got, gerr = b, e end)
    check(got == nil, "the call returns at once (the screen isn't held up)")
    runLoop(function() return got ~= nil or gerr ~= nil end, 20)
    check(type(got) == "table" and got.id == 1, "result arrives from the background process " .. tostring(gerr))
    local order = {}
    AsyncMod.run(plugin.api, function() return "a" end, function(v) order[#order + 1] = v end)
    AsyncMod.run(plugin.api, function() error("boom") end, function(v, e) order[#order + 1] = e and "err" or v end)
    AsyncMod.run(plugin.api, function() return "c" end, function(v) order[#order + 1] = v end)
    runLoop(function() return #order == 3 end, 20)
    check(table.concat(order, ",") == "a,err,c", "one at a time, in order; an error comes back as an error " .. table.concat(order, ","))
    AsyncMod.sync = true
end

print("Wi-Fi only when needed")
do
    local Net = require("gzreader_net")
    local now = 1000
    Net.clock = function() return now end
    gsettings.gzreader_wifi_on_demand = nil -- default: on
    local was = NET.connected
    NET.connected = false
    Net.holders, Net.ours = {}, false -- earlier tests' screens
    captured.wifi = {}
    local ran = 0
    Net.run(function() ran = ran + 1 end, { reason = "test" })
    check(ran == 1 and captured.wifi[1] == "on", "needed: Wi-Fi turned on (no prompt), then the action runs")
    Net.hold("download")
    now = now + 600
    local function idle() Net._check() end
    idle()
    check(NET.connected and captured.wifi[2] == nil, "kept on while something needs it (a download)")
    Net.release("download")
    now = now + 600
    idle()
    check(not NET.connected and captured.wifi[2] == "off", "turned off once idle and unused")
    -- 1.2.8: Wi-Fi the Kindle left on (on at start or after waking) is turned off too
    NET.connected = true
    captured.wifi = {}
    Net.run(function() end)
    Net.adopt()
    now = now + 30
    idle()
    check(NET.connected and #captured.wifi == 0, "Wi-Fi already on: kept for a minute after it was last used")
    now = now + 600
    idle()
    check(not NET.connected and captured.wifi[1] == "off", "Wi-Fi the Kindle left on is turned off once unused")
    -- Wi-Fi the user turns on (menu, quick panel) is left alone
    local NM = require("ui/network/manager")
    local saved_on, saved_off = NM.toggleWifiOn, NM.toggleWifiOff
    NM.toggleWifiOn = function() NET.connected = true end
    NM.toggleWifiOff = function() NET.connected = false end
    Net._toggle_on, Net._toggle_off = nil, nil
    Net.adopt() -- installs the toggle hooks
    captured.wifi = {}
    NM:toggleWifiOn()
    Net.run(function() end)
    Net.adopt()
    now = now + 600
    idle()
    check(NET.connected and #captured.wifi == 0, "Wi-Fi the user turned on is never turned off")
    NM:toggleWifiOff()
    check(not Net.user_on, "…until the user turns it off")
    NM.toggleWifiOn, NM.toggleWifiOff = saved_on, saved_off
    check(Net.keptOff(), "turned off by you: remembered (background work leaves it off)")
    gsettings.gzreader_wifi_kept_off = nil
    Net._toggle_on, Net._toggle_off, Net.user_on = nil, nil, nil
    gsettings.gzreader_wifi_on_demand = false
    NET.connected = false
    local q = 0
    Net.run(function() q = q + 1 end, { quiet = true })
    check(q == 0 and #captured.wifi == 0, "switch off: background syncs wait for Wi-Fi as before")
    NET.connected = was
    Net.clock = os.time
    Net.ours, Net.holders = false, {}
    UI.scheduled = {}
end

print("Night mode guard (Kindle 3)")
do
    local saved_dev, saved_ng = package.loaded["device"], package.loaded["gzreader_nightguard"]
    local inverts = 0
    local scr = { night_mode = true }
    function scr.toggleNightMode(self) self.night_mode = not self.night_mode; inverts = inverts + 1 end
    package.loaded["device"] = { isKindle = function() return true end, canHWInvert = function() return false end, screen = scr }
    package.loaded["gzreader_nightguard"] = nil
    gsettings.night_mode = true
    local NG = require("gzreader_nightguard")
    NG.install()
    check(scr.night_mode == false and inverts == 1 and gsettings.night_mode == false, "saved night mode switched off at start")
    scr:toggleNightMode()
    check(scr.night_mode == false and inverts == 1 and gsettings.night_mode == false, "turning it on is refused (menus, gestures, ZenOS schedule)")
    package.loaded["device"], package.loaded["gzreader_nightguard"] = saved_dev, saved_ng
end

print("Native progress sync (EPUB)")
-- Fake crengine document: 3 XHTML fragments; spine also has an SVG page
-- between titlepage and ch1 that crengine doesn't turn into a fragment.
local CONTAINER = [[<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>]]
local OPF = [[<package><manifest>
<item id="tp" href="Text/title%20page.xhtml" media-type="application/xhtml+xml"/>
<item id="img" href="Images/map.svg" media-type="image/svg+xml"/>
<item id="c1" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>
<item id="c2" href="Text/../Text/ch2.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine toc="ncx"><itemref idref="tp"/><itemref idref="img"/><itemref idref="c1"/><itemref idref="c2" linear="yes"/></spine></package>]]
local FRAG_START = { 0, 1000, 1000, 3000 } -- title page, SVG page (empty), ch1, ch2
local DOC_H = 6000
local reader = { pos = 0, events = {} }
local doc = {
    file = WORK .. "/home/GZreader/book3.epub",
    info = { doc_height = DOC_H, has_pages = false },
    getDocumentFileContent = function(_, p) return ({ ["META-INF/container.xml"] = CONTAINER, ["OEBPS/content.opf"] = OPF })[p] end,
    isXPointerInDocument = function(_, xp) local n = tonumber(xp:match("DocFragment%[(%d+)%]")); return n ~= nil and n >= 1 and n <= 4 end,
    getXPointer = function() return "cur:" .. reader.pos end,
    getPosFromXPointer = function(_, xp)
        local n = tonumber(xp:match("^/body/DocFragment%[(%d+)%]$")); if n then return FRAG_START[n] end
        return tonumber(xp:match("^cur:(%d+)") or xp:match("^page:(%d+)"))
    end,
    getPageCount = function() return DOC_H / 100 end,
    getPageXPointer = function(_, page) return "page:" .. ((page - 1) * 100) end,
}
-- current xpointer should carry the fragment, like crengine's
doc.getXPointer = function()
    local frag = 1; for i, st in ipairs(FRAG_START) do if reader.pos >= st then frag = i end end
    return string.format("/body/DocFragment[%d]/body/p[3]/text().0", frag)
end
local base_pos = doc.getPosFromXPointer
doc.getPosFromXPointer = function(d, xp)
    if xp:match("/body/p%[3%]") then return reader.pos end
    return base_pos(d, xp)
end
local readerui = {
    document = doc,
    rolling = { getLastPercent = function() return reader.pos / DOC_H end, _gotoPos = function(_, p) reader.pos = math.floor(p) end },
    view = { view_mode = "page" },
    link = { addCurrentLocationToStack = function() reader.stacked = true end },
    handleEvent = function(_, ev) table.insert(reader.events, ev); if ev.name == "GotoPage" then reader.pos = (ev.args[1] - 1) * 100 end end,
    menu = { registerToMainMenu = function() end },
}
local rplugin = Grimmory:new{ ui = readerui }
UI.scheduled = {}
reader.pos = 2000
rplugin:onReaderReady()
check(rplugin.sync ~= nil, "sync attached to Grimmory book")
check(rplugin.store.downloads["3"].file_id == 1003, "file id looked up for a download that lacked it")
for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}   -- initial pull (nothing on server)
local sp = rplugin.sync:spine()
check(sp and #sp.frag == 4 and #sp.all == 4, "spine parsed: every item is a crengine fragment, the SVG page too")
check(sp.frag[1] == "OEBPS/Text/title page.xhtml" and sp.frag[4] == "OEBPS/Text/ch2.xhtml", "hrefs resolved/decoded/normalized")
local lp = rplugin.sync:localPosition()
check(lp.href == "OEBPS/Text/ch1.xhtml" and lp.chapter_pct == 50 and math.abs(lp.pct - 33.3) < 0.1, "local position -> chapter href + 50% within chapter")

ctl("/webprogress?book=3&pct=10&cfi=epubcfi(/6/6!/4/2)&href=Text/ch1.xhtml")   -- stale web CFI
rplugin.sync:push(true)
local st = json.decode(ctl("/state"))
local fp = st.progress["3"]
check(fp and fp.positionHref == "OEBPS/Text/ch1.xhtml" and fp.contentSourceProgressPercent == 50, "push sends href + in-chapter percent")
check(fp.positionData == nil, "stale web CFI cleared so web reader resumes from href")
check(fp.bookFileId == 1003 and math.abs(fp.progressPercent - 33.3) < 0.1, "push carries file id + whole-book percent")
check(st.last_put_body.fileProgress.positionData == nil, "no CFI sent")

print("Pull from web reader")
-- web reader at ch2 with a CFI and only whole-book percent (what it saves)
ctl("/webprogress?book=3&pct=70&cfi=epubcfi(/6/8!/4/2/10)&href=OEBPS/Text/ch2.xhtml")
reader.events = {}
rplugin.sync:pull(false)
check(reader.pos == 4200 and not reader.stacked, "forward: jumped to the web position (ch2 @ 70%); not put in Back history (Back no longer returns to the book's start)")
check(captured.info and captured.info:match("70"), "user told about the jump")

ctl("/webprogress?book=3&pct=60&cfi=epubcfi(/6/8!/4/2/4)")   -- CFI only, no href; 60% is outside ch2? no: 3600 inside
reader.pos = 0; rplugin.sync.entry.last_pushed_pct = nil
rplugin.sync:pull(false)
check(reader.pos == 3600, "CFI-only position mapped via spine step (SVG page counted)")

ctl("/webprogress?book=3&pct=20&href=Text/ch2.xhtml&cpct=25")   -- another Kindle: ch2, 25% in
reader.pos = 0; rplugin.sync.entry.last_pushed_pct = nil
rplugin.sync:pull(false)
check(reader.pos == 3700, "href + in-chapter percent lands exactly (3000 + 25% of 3000)")

print("Backward positions")
reader.pos = 5000; rplugin.sync:push(true)
reader.pos = 5500                                  -- read on; server still has our own 83.3%
captured.confirm = nil
rplugin.sync:pull(false)
check(captured.confirm == nil and reader.pos == 5500, "server holding our own older push: no prompt, no jump")
ctl("/webprogress?book=3&pct=40&href=OEBPS/Text/ch1.xhtml&cpct=70")   -- someone went back on another device
rplugin.sync:pull(false)
check(captured.confirm ~= nil and reader.pos == 5500, "moved back elsewhere: asks before jumping back")
captured.confirm.ok_callback()
check(reader.pos == 2400, "confirmed: goes back (ch1 @ 70%)")

print("Offline queue + reading sessions")
NET.connected = false
reader.pos = 5900
rplugin.sync.session.start = os.time() - 300
rplugin:onCloseDocument()
check(rplugin.store.pending.progress["3"] ~= nil and #rplugin.store.pending.sessions == 1, "offline: progress and session queued")
local before = json.decode(ctl("/state")).progress["3"].progressPercent
NET.connected = true
rplugin:onNetworkConnected(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
st = json.decode(ctl("/state"))
check(next(rplugin.store.pending.progress) == nil and #rplugin.store.pending.sessions == 0, "queue flushed when Wi-Fi returns")
check(math.abs(st.progress["3"].progressPercent - 98.3) < 0.1 and before ~= st.progress["3"].progressPercent, "queued position reached server")
local sess = st.sessions[#st.sessions]
check(sess and sess.bookId == 3 and sess.durationSeconds >= 300 and sess.bookType == "EPUB"
    and sess.startTime:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"), "reading session sent with ISO times and duration")

print("Wi-Fi back without KOReader noticing")
rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
NET.connected = false
reader.pos = 1200; rplugin.sync.session.start = os.time() - 120
rplugin.sync:onLeave()                                -- e.g. Kindle went to sleep offline
rplugin.sync:startSession()
check(#rplugin.store.pending.sessions == 1 and rplugin.store.pending.progress["3"] ~= nil, "offline sleep: queued")
NET.connected = true                                  -- system brought Wi-Fi up; no NetworkConnected event
local n_sessions = #json.decode(ctl("/state")).sessions
reader.pos = 1300; rplugin.sync:push(true)
check(#rplugin.store.pending.sessions == 0 and next(rplugin.store.pending.progress) == nil, "next successful sync sends the queue")
check(#json.decode(ctl("/state")).sessions == n_sessions + 1, "queued reading session reached Grimmory")
rplugin:onCloseDocument()

print("Page-turn debounce")
rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
local puts = function() local n = 0; for _, e in ipairs(json.decode(ctl("/state")).log) do if e[1] == "PUT" then n = n + 1 end end; return n end
local p0 = puts()
for i = 1, 9 do reader.pos = reader.pos - 100; rplugin:onPageUpdate() end
check(puts() == p0, "no push for the first 9 page turns")
reader.pos = reader.pos - 100; rplugin:onPageUpdate()
check(puts() == p0 + 1, "push on the 10th page turn")
rplugin.store.sync_disabled = true
for i = 1, 12 do reader.pos = reader.pos - 100; rplugin:onPageUpdate() end
check(puts() == p0 + 1, "sync toggle off: no pushes")
rplugin.store.sync_disabled = nil

print("Books not from Grimmory")
local other = Grimmory:new{ ui = { document = { file = "/mnt/us/documents/sideloaded.epub" }, menu = readerui.menu } }
other:onReaderReady()
check(other.sync == nil, "sideloaded books are left alone")

print("Expired refresh token")
ctl("/expire_refresh")
plugin.store.access_expires_at = 0
local d, e = plugin.api:listBooks{}
check(d == nil and e == "expired" and not plugin.api:isPaired(), "expired login -> asks to pair again")

print("Pairing timeout + cancel")
PS.new = function(self, o) screen = o; return o end
plugin:startQrPairing()
local timer
for f, delay in pairs(UI.scheduled) do if delay == 600 then timer = f end end
check(timer ~= nil, "10 minutes without a request: the page closes")
timer()
check(#UI.zmqs == 0 and plugin.pairing == nil, "expiry stops server")
plugin:startQrPairing()
screen.on_cancel()
check(#UI.zmqs == 0 and plugin.pairing == nil, "Back/cancel stops server")
PS.new = orig_new


print("Bookmarks: CFI <-> XPointer")
local BM = require("gzreader_bookmarks")
local CH2 = [[<?xml version="1.0"?><!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title><link rel="stylesheet" href="a.css"/></head><body><!-- <p>not</p> --><h1>T</h1><div class="a"><p>one</p><img src="i.png"/><p>two <b>b</b></p><p data-x="a>b">three</p></div><p>after<br/></p></body></html>]]
local EPUB_FILES = { ["META-INF/container.xml"] = CONTAINER, ["OEBPS/content.opf"] = OPF, ["OEBPS/Text/ch2.xhtml"] = CH2 }
local readf = function(h) return EPUB_FILES[h] end
doc.getDocumentFileContent = function(_, p) return EPUB_FILES[p] end
local spn = rplugin.sync:spine()
check(BM.xpToCfi("/body/DocFragment[4]/body/div/p[3]/text().4", spn, readf) == "epubcfi(/6/8!/4/4/8)",
    "xpointer -> CFI (spine step skips nothing, element steps count all elements)")
check(BM.xpToCfi("/body/DocFragment[4]/body/p", spn, readf) == "epubcfi(/6/8!/4/6)", "first <p> among body children")
check(BM.cfiToXp("epubcfi(/6/8!/4/4/8/1:5)", spn, readf) == "/body/DocFragment[4]/body/div/p[3]", "CFI (with text offset) -> xpointer")
check(BM.cfiToXp("epubcfi(/6/8!/4/6)", spn, readf) == "/body/DocFragment[4]/body/p", "CFI -> xpointer round trip")
check(BM.cfiToXp("epubcfi(/6/4!/4)", spn, readf) == "/body/DocFragment[2]", "CFI into the SVG page -> that page")
check(BM.xpToCfi("/body/DocFragment[4]/body/div[9]/p", spn, readf) == "epubcfi(/6/8!/4)", "unknown element -> deepest valid CFI")

print("Bookmarks: two-way sync")
plugin:connect("http://127.0.0.1:" .. PORT, "will", "hunter22")
check(rplugin.api:isPaired(), "signed in again (previous test expired the login)")
rplugin:onCloseDocument()
readerui.annotation = { annotations = {}, addItem = function(self, item) table.insert(self.annotations, item); return #self.annotations end }
readerui.bookmark = {
    removeItemByIndex = function(_, i) table.remove(readerui.annotation.annotations, i) end,
    setDogearVisibility = function() end, getCurrentPageNumber = function() return 1 end,
}
readerui.toc = { getTocTitleByPage = function() return "Chapter 2" end }
ctl("/addbm?book=3&cfi=epubcfi(/6/8!/4/4/8)&title=From%20web")
UI.scheduled = {}
rplugin:onReaderReady()
runLoop(function() return #readerui.annotation.annotations > 0 end, 10)
local anns = readerui.annotation.annotations
check(#anns == 1 and anns[1].page == "/body/DocFragment[4]/body/div/p[3]" and anns[1].text == "From web", "web bookmark appears on the Kindle at the right paragraph")
local mine = { page = "/body/DocFragment[4]/body/p", chapter = "Chapter 2" }
table.insert(anns, mine)
rplugin:onAnnotationsModified({ mine, index_modified = 2 })
local bms = json.decode(ctl("/state")).bookmarks
local pushed
for _, b in ipairs(bms) do if b.cfi == "epubcfi(/6/8!/4/6)" then pushed = b end end
check(#bms == 2 and pushed and pushed.title == "Chapter 2", "Kindle bookmark sent to Grimmory as a CFI")
rplugin:onAnnotationsModified({ anns[1], index_modified = -1 })
table.remove(anns, 1)
bms = json.decode(ctl("/state")).bookmarks
check(#bms == 1 and bms[1].id == pushed.id, "removing a synced bookmark on the Kindle deletes it in Grimmory")
ctl("/delbm?id=" .. pushed.id)
rplugin.bookmarks:reconcile()
check(#anns == 0, "deleted in the web reader -> removed on the Kindle")
NET.connected = false
local offline_bm = { page = "/body/DocFragment[4]/body/div/p", chapter = "Chapter 2" }
table.insert(anns, offline_bm)
rplugin:onAnnotationsModified({ offline_bm, index_modified = 1 })
check(#json.decode(ctl("/state")).bookmarks == 0, "offline: nothing sent")
NET.connected = true
rplugin.bookmarks:reconcile()
bms = json.decode(ctl("/state")).bookmarks
check(#bms == 1 and bms[1].cfi == "epubcfi(/6/8!/4/4/2)" and #anns == 1, "back online: the offline bookmark is sent, no duplicates")
rplugin.bookmarks:reconcile()
check(#json.decode(ctl("/state")).bookmarks == 1 and #anns == 1, "reconcile again: stable (no duplicates either side)")
rplugin.store.bookmark_sync_disabled = true
local nb = { page = "/body/DocFragment[4]/body/h1", chapter = "c" }
table.insert(anns, nb); rplugin:onAnnotationsModified({ nb, index_modified = 2 })
check(#json.decode(ctl("/state")).bookmarks == 1, "bookmark sync switch off: nothing sent")
rplugin.store.bookmark_sync_disabled = nil

print("Highlights and notes: two-way sync")
do
    package.loaded["ffi/archiver"] = nil -- the real one failed to load earlier (no libarchive here)
    local Anno = require("gzreader_annotations")
    local CFI = require("gzreader_cfi")
    Anno.openReader = function()
        return { open = function() end, close = function() end,
            iterate = function() return function() return nil end end,
            extractToMemory = function(_, p) return EPUB_FILES[p] end }
    end
    CFI.initBook("x", Anno.openReader())
    local XP0, XP1 = "/body/DocFragment[4]/body/div/p[3]/text().0", "/body/DocFragment[4]/body/div/p[3]/text().5"
    local range = CFI.xpointerRangeToCFI(XP0, XP1)
    check(range == "epubcfi(/6/8[c2]!/4/4/8,/1:0,/1:5)", "highlight range -> Grimmory CFI (SVG spine page counted) " .. tostring(range))
    local b0, b1 = CFI.cfiRangeToXPointers(range)
    check(b0 == "/body/DocFragment[4]/body/div[1]/p[3]/text()[1].0" and b1:match("%.5$"), "CFI range -> crengine xpointers")
    CFI.clearCache()
    local function server() return json.decode(ctl("/state")).annotations end
    local anns = readerui.annotation.annotations
    for i = #anns, 1, -1 do table.remove(anns, i) end
    readerui.annotation.updateAnnotations = function() readerui.anno_updated = (readerui.anno_updated or 0) + 1 end
    rplugin.store.bookmark_sync_disabled = true -- keep this section to highlights
    -- a highlight made on the Kindle
    local hl = { pos0 = XP0, pos1 = XP1, page = XP0, text = "three", chapter = "Chapter 2", drawer = "lighten",
        color = "green", datetime = "2026-10-29 08:00:00" }
    table.insert(anns, hl)
    rplugin.annotations = Anno:new(rplugin.sync)
    local an = rplugin.annotations
    an:run()
    local sv = server()
    check(#sv == 1 and sv[1].cfi == range and sv[1].text == "three" and sv[1].color == "#4ADE80" and sv[1].style == "highlight"
        and sv[1].chapterTitle == "Chapter 2", "Kindle highlight sent with its range, text, colour and style")
    check(#anns == 1 and anns[1].grimmory_id == sv[1].id and rplugin.store.downloads["3"].anno_shadow[tostring(sv[1].id)],
        "linked to Grimmory's id; base state saved")
    check(not rplugin.store.downloads["3"].anno_dirty, "clean after a full pass")
    -- a note added on the Kindle
    anns[1].note = "Kindle note"
    rplugin:onAnnotationsModified({ anns[1] })
    check(UI.scheduled[an.pending] == Anno.DEBOUNCE, "edits are sent a few seconds later (debounced)")
    an.pending(); UI.scheduled = {}
    check(server()[1].note == "Kindle note", "note sent to Grimmory")
    -- from the web reader: a new highlight with a note, and a colour change
    ctl("/addan?book=3&cfi=" .. "epubcfi(/6/8%5Bc2%5D!/4/4/6,/1:0,/1:3)" .. "&text=two&note=web%20note&color=%23F472B6")
    ctl("/editan?id=" .. sv[1].id .. "&color=%23FB923C")
    an:run()
    check(#anns == 2, "web highlight appears on the Kindle")
    local web
    for _, a in ipairs(anns) do if a.text == "two" then web = a end end
    check(web and web.pos0 == "/body/DocFragment[4]/body/div[1]/p[2]/text()[1].0" and web.note == "web note" and web.color == "pink"
        and web.drawer == "lighten", "at the right words, with its note and colour")
    local mine
    for _, a in ipairs(anns) do if a.text == "three" then mine = a end end
    check(mine and mine.color == "orange" and mine.note == "Kindle note", "web colour change applied, Kindle note kept")
    check((readerui.anno_updated or 0) > 0, "open book's highlights refreshed")
    -- edited on both sides since the last sync: a conflict, nothing overwritten
    ctl("/editan?id=" .. sv[1].id .. "&note=web%20edit")
    mine.note = "kindle edit"
    an:run()
    check(server()[1].note == "web edit" and mine.note == "kindle edit", "edited in both places: each side keeps its own")
    check(rplugin.store.downloads["3"].anno_conflicts == 1 and rplugin.store.downloads["3"].anno_dirty, "conflict counted, retried next time")
    mine.note = "web edit" -- the user makes them the same
    an:run()
    check(not rplugin.store.downloads["3"].anno_conflicts, "conflict clears once both sides agree")
    -- deleted on the Kindle -> deleted on Grimmory
    for i, a in ipairs(anns) do if a == web then table.remove(anns, i) end end
    an:run()
    sv = server()
    check(#sv == 1 and sv[1].text == "three", "deleted on the Kindle: deleted in Grimmory")
    -- deleted in the web reader -> removed here
    ctl("/delan?id=" .. sv[1].id)
    an:run()
    check(#readerui.annotation.annotations == 0, "deleted in the web reader: removed on the Kindle")
    anns = readerui.annotation.annotations
    -- page bookmarks are left to bookmark sync
    table.insert(anns, { page = "/body/DocFragment[4]/body/h1", chapter = "c" })
    an:run()
    check(#server() == 0 and #anns == 1, "page bookmarks aren't sent as highlights")
    table.remove(anns, 1)
    -- the reply to a new highlight is lost: no duplicate, linked on the next look
    local hl2 = { pos0 = "/body/DocFragment[4]/body/div/p[1]/text().0", pos1 = "/body/DocFragment[4]/body/div/p[1]/text().3",
        page = "/body/DocFragment[4]/body/div/p[1]/text().0", text = "one", drawer = "underscore", color = "yellow" }
    table.insert(anns, hl2)
    ctl("/set?an_lose_reply=true")
    an:run()
    an:run()
    sv = server()
    check(#sv == 1 and sv[1].style == "underline" and anns[1].grimmory_id == sv[1].id, "lost reply: saved once, linked afterwards")
    -- offline: waits; sent when the book closes and Wi-Fi comes back
    NET.connected = false
    local hl3 = { pos0 = "/body/DocFragment[4]/body/p/text().0", pos1 = "/body/DocFragment[4]/body/p/text().5",
        page = "/body/DocFragment[4]/body/p/text().0", text = "after", drawer = "lighten", color = "yellow" }
    table.insert(anns, hl3)
    rplugin:onAnnotationsModified({ hl3, nb_highlights_added = 1, index_modified = 2 })
    check(an.pending == nil and rplugin.store.downloads["3"].anno_dirty and #server() == 1, "offline: nothing sent, marked waiting")
    UI.scheduled = {}
    gsettings.gzreader_wifi_on_demand = nil -- Wi-Fi only when needed
    rplugin:onCloseDocument()
    check(rplugin.annotations == nil, "closed")
    -- (what's scheduled may schedule more: run it in rounds, not while iterating)
    for _round = 1, 6 do
        local due = {}
        for f in pairs(UI.scheduled) do due[#due + 1] = f end
        UI.scheduled = {}
        if #due == 0 then break end
        for _i, f in ipairs(due) do f() end
    end
    check(#server() == 2, "on close: Wi-Fi brought up quietly and the highlight sent")
    gsettings.gzreader_wifi_on_demand = false
    -- switch
    rplugin.store.annotation_sync_disabled = true
    rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
    ctl("/addan?book=3&cfi=epubcfi(/6/8%5Bc2%5D!/4/4/6,/1:0,/1:3)&text=two")
    rplugin.annotations:run()
    check(#readerui.annotation.annotations == 2, "switch off: nothing synced")
    rplugin.store.annotation_sync_disabled = nil
    rplugin.store.bookmark_sync_disabled = nil
    rplugin:onCloseDocument(); UI.scheduled = {}
end

print("Page sync: exact place (CFI) and the web reader's percentage")
do
    local Sync = require("gzreader_sync")
    Sync.cfiReader = function()
        return { open = function() end, close = function() end,
            iterate = function() return function() return nil end end,
            extractToMemory = function(_, p) return EPUB_FILES[p] end }
    end
    EPUB_FILES["OEBPS/Text/title page.xhtml"] = string.rep("t", 100)
    EPUB_FILES["OEBPS/Text/ch1.xhtml"] = string.rep("c", 300)
    local XP_P3 = "/body/DocFragment[4]/body/div/p[3]/text().0"
    local XP_P2 = "/body/DocFragment[4]/body/div[1]/p[2]/text()[1].0"
    local orig_getXP, orig_pos = doc.getXPointer, doc.getPosFromXPointer
    doc.getXPointer = function() return XP_P3 end
    doc.getPosFromXPointer = function(d, xp)
        if xp == XP_P3 then return reader.pos end
        if xp == XP_P2 then return 3500 end
        return orig_pos(d, xp)
    end
    rplugin.store.downloads["3"].spine_sizes = nil
    rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
    local sy = rplugin.sync
    check(sy:cfiOf(XP_P3) == "epubcfi(/6/8[c2]!/4/4/8/1:0)", "page position -> CFI")
    local web = sy:webPercent(3, 0.5)
    check(math.abs(web - (100 + 150) / (400 + #CH2) * 100) < 0.01, "percentage counted like the web reader (spine files by size, SVG page 0)")
    reader.pos = 4500 -- half way through ch2 (3000..6000)
    sy:push(true)
    local fp = json.decode(ctl("/state")).progress["3"]
    check(fp.positionData == "epubcfi(/6/8[c2]!/4/4/8/1:0)", "push sends the exact place as a CFI (the web reader opens there)")
    check(fp.positionHref == "OEBPS/Text/ch2.xhtml" and fp.contentSourceProgressPercent == 50, "href and in-chapter percent still sent")
    check(math.abs(fp.progressPercent - (400 + #CH2 * 0.5) / (400 + #CH2) * 100) < 0.1, "percentage the web reader would show " .. tostring(fp.progressPercent))
    -- the web reader is earlier in the same chapter (though its 99% is higher)
    ctl("/webprogress?book=3&pct=99&cfi=epubcfi(/6/8%5Bc2%5D!/4/4/6/1:0)&href=OEBPS/Text/ch2.xhtml")
    reader.pos = 4500
    captured.confirm = nil
    sy:pull(false)
    check(captured.confirm ~= nil, "web place is behind (by KOReader's positions, not its 99%): asks")
    captured.confirm.ok_callback()
    check(reader.pos == 3500, "goes to the web reader's exact place (from its CFI)")
    -- our own push echoed back: nothing happens
    reader.pos = 4500; sy:push(true)
    reader.pos = 5000; captured.confirm = nil
    sy:pull(false)
    check(captured.confirm == nil and reader.pos == 5000, "our own last push on Grimmory: no prompt, no jump")
    doc.getXPointer, doc.getPosFromXPointer = orig_getXP, orig_pos
    rplugin:onCloseDocument(); UI.scheduled = {}
    Sync.cfiReader = nil
    package.loaded["ffi/archiver"] = nil -- the real one can't load here
end

print("Picture books")
do
    local PB = require("gzreader_picturebook")
    local Dev = require("device")
    local saved_screen = Dev.screen
    Dev.screen = { getHeight = function() return 800 end, getWidth = function() return 600 end,
        scaleBySize = function(_, v) return v end }
    local zen_saved = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_PLUGIN = { config = { features = { reader_top_status_bar = true }, reader_top_status_bar = {} } }
    local ds = { d = {} }
    function ds:readSetting(k) return self.d[k] end
    function ds:saveSetting(k, v) self.d[k] = v end
    function ds:delSetting(k) self.d[k] = nil end
    local smooth_calls = {}
    -- a tiny picture book: a page scan and a wide logo
    local function jpeg(w, h) return "\255\216\255\192\0\17\8" .. string.char(math.floor(h / 256), h % 256, math.floor(w / 256), w % 256) .. string.rep("\0", 20) end
    local files = {
        ["META-INF/container.xml"] = CONTAINER,
        ["OEBPS/content.opf"] = [[<package><manifest><item id="a" href="Text/p1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="a"/></spine></package>]],
        ["OEBPS/Text/p1.xhtml"] = [[<html><body><p><img src="../images/page1.jpg"/></p><p><img class="x" src="../images/logo.jpg"/></p></body></html>]],
        ["OEBPS/images/page1.jpg"] = jpeg(385, 625), ["OEBPS/images/logo.jpg"] = jpeg(338, 92),
    }
    local reopened = 0
    local relayouts = 0
    local ui = { doc_settings = ds,
        view = { footer = { getHeight = function() return 28 end, settings = {} }, _zen_header_dimen = { h = 28 } },
        styletweak = { updateCssText = function() relayouts = relayouts + 1 end },
        document = { configurable = { smooth_scaling = 0, h_page_margins = { 15, 15 }, t_page_margin = 10, b_page_margin = 10, sync_t_b_page_margins = 1 },
            setImageScaling = function() relayouts = relayouts + 1 end,
            invalidateCacheFile = function(d) d.cache_dropped = true end,
            info = {}, getDocumentFileContent = function(_, p) return files[p] end },
        reloadDocument = function() reopened = reopened + 1 end,
        handleEvent = function(_, ev) if ev.name == "SetPageMargins" then relayouts = relayouts + 1 end end }
    check(select(1, PB.imageSize(files["OEBPS/images/logo.jpg"])) == 338, "picture size read from the JPEG header")
    -- the picture sizes are read in a background job first, never on the screen's thread
    local reads = 0
    ui.document.getDocumentFileContent = function(_, p) if p:match("%.jpg$") then reads = reads + 1 end return files[p] end
    ui.document.file = "/tmp/gz-no-such-book.epub"
    local Async = require("gzreader_async")
    local orig_bg, bg_cb = Async.background, nil
    Async.background = function(fn, cb, name) bg_cb = cb end
    PB.set(ui, true)
    Async.background = orig_bg
    check(reads == 0 and bg_cb ~= nil and ui.styletweak.book_style_tweak == nil and reopened == 0,
        "turning it on: first a background job reads the picture sizes (nothing on the screen's thread, nothing changed yet)")
    local wide = PB.widePictures(function(p) return files[p] end, 600, 760)
    check(#wide == 1 and wide[1] == "logo.jpg", "background job finds the wide picture")
    local RUI = require("apps/reader/readerui")
    local saved_inst = RUI.instance
    RUI.instance = ui
    bg_cb(wide)
    RUI.instance = saved_inst
    local css = ui.styletweak.book_style_tweak or ""
    local cfg = ui.document.configurable
    check(reopened == 1 and relayouts == 0 and ui.document.cache_dropped,
        "then the layout is saved and the book reopened once, with a fresh layout cache (no re-layouts of the open book, no Styles-have-changed box)")
    check(css:find("height: 99.0vh !important", 1, true) and css:find("h1, h2", 1, true), "pictures 99vh; headings lose their margins too (Wimpy Kid's title page made an empty page)")
    check(cfg.t_page_margin == 30 and cfg.h_page_margins[1] == 0 and cfg.b_page_margin == 4 and cfg.sync_t_b_page_margins == 0,
        "margins: title bar on top, a little room above the status bar")
    check(css:find('img[src$="logo.jpg"]', 1, true) and not css:find('page1.jpg', 1, true), "a wide picture (logo) keeps its own size; page scans fill the page")
    check(cfg.smooth_scaling == 1, "smooth image scaling on")
    ui.view.footer.settings.reclaim_height = true
    ui.document._zen_top_status_bar_reserved_height = 30 -- ZenOS reserves the title bar itself
    PB.set(ui, true)
    check(cfg.t_page_margin == 0 and cfg.b_page_margin == 4 + 28 and reopened == 2, "ZenOS reserves the title bar: no extra top margin; overlapping status bar: room for it")
    ui.document._zen_top_status_bar_reserved_height = nil
    ui.view.footer.settings.reclaim_height = nil
    PB.set(ui, false)
    check(cfg.smooth_scaling == 0 and cfg.h_page_margins[1] == 15 and cfg.t_page_margin == 10 and cfg.sync_t_b_page_margins == 1
        and not (ui.styletweak.book_style_tweak or ""):find("picture book", 1, true) and reopened == 3, "off: style, margins and smooth scaling as before, book reopened")

    -- a book fitted by 1.2.x (style v3): fitted again once when it opens
    ds.d.gzreader_picture_book = true
    ui.styletweak.book_style_tweak = "/* GZreader picture book: begin */ /* v3 */ img{} /* GZreader picture book: end */"
    ui.styletweak.book_style_tweak_enabled = true
    PB.onOpen(ui)
    check(reopened == 4 and ui.styletweak.book_style_tweak:find("/* v5 */", 1, true), "fitted by an older version: fitted again once")
    PB.onOpen(ui)
    check(reopened == 4, "…and not again")

    Dev.screen = saved_screen
    _G.__ZEN_UI_PLUGIN = zen_saved
end

print("Read aloud")
local TTS = require("gzreader_tts")
local lipc_log = {}
local function fakeHandle()
    local h = {}
    function h:new_hasharray()
        local ha = { kv = {} }
        function ha:add_hash() end
        function ha:put_string(_, k, v) self.kv[k] = v end
        function ha:put_int(_, k, v) self.kv[k] = v end
        function ha:destroy() end
        return ha
    end
    function h:access_hash_property(pub, prop, ha) table.insert(lipc_log, { pub = pub, prop = prop, kv = ha.kv }); return { destroy = function() end } end
    function h:set_int_property(pub, prop, v) table.insert(lipc_log, { pub = pub, prop = prop, int = v }) end
    function h:close() end
    return h
end
TTS.lipc = { open_no_name = fakeHandle }
local TPL = { target = { pub = "com.lab126.ttsd", prop = "playSnippetNow" }, fields = { { "text", str = "x" }, { "id", int = 1 } } }
check(TTS.say("Hello there.", TPL) and lipc_log[1].prop == "playSnippetNow" and lipc_log[1].kv.text == "Hello there. " and type(lipc_log[1].kv.id) == "number", "speaks with the learned request shape (text + a fresh id)")
check(TTS.hashText({ { "text", str = 'He said "hi"\nok' }, { "id", int = 7 } }) == '{text = "He said \'hi\' ok", id = (7)}', "lipc-hash-prop format: strings quoted, ints in parentheses")
check(TTS.missingField("261029:033827 ttsd[2923]: E lipc_handling:bad_id:rc=82:enqueueSnippet unable to read id") == "id", "reads the missing field from ttsd's complaint")
check(TTS.duration("one two three four five six seven eight nine ten.") > 3 and TTS.duration("one two three four five six seven eight nine ten.") < 6, "sentence timing from length and speed")
gsettings.gzreader_tts_speed = 200
check(TTS.duration("one two three four five six seven eight nine ten.") < 3, "faster speed -> shorter wait")
gsettings.gzreader_tts_speed = nil
gsettings.gzreader_tts_template = TPL
local S = { s1 = { "First sentence here.", "s1e", "s2" }, s2 = { "Second one.", "s2e", "s3" }, s3 = { "On the next page.", "s3e", nil } }
local page = 1
local tts_ui = { events = {}, dialog = {} }
tts_ui.document = {
    info = { has_pages = false },
    getXPointer = function() return "s1" end,
    getNextVisibleWordEnd = function(_, xp) return S[xp] and S[xp][2] end,
    extendXPointersToSentenceSegment = function(_, a, b) return a, b end,
    getTextFromXPointers = function(_, a, _b, draw) if draw then tts_ui.hl = a end return S[a] and S[a][1] end,
    getNextVisibleWordStart = function(_, xp) for k, v in pairs(S) do if v[2] == xp then return v[3] end end end,
    getPrevVisibleWordStart = function(_, xp) return (xp:gsub("e$", "")) end,
    isXPointerInCurrentPage = function(_, xp) return (xp == "s3") == (page == 2) end,
    clearSelection = function() tts_ui.hl = nil end,
}
tts_ui.handleEvent = function(_, ev) table.insert(tts_ui.events, ev.name); if ev.name == "GotoViewRel" then page = page + 1; tts_ui.turned = true end end
local R = TTS.Reader:new(tts_ui)
lipc_log = {}
R:start()
local first_text
for _, e in ipairs(lipc_log) do if e.kv and e.kv.text then first_text = first_text or e.kv.text end end
check(R.active and tts_ui.hl == "s1" and first_text == "First sentence here. ", "first sentence spoken (with a trailing space so ttsd says the last word) and highlighted")
runLoop(function() return not R.active end, 30)
local spoken = {}
for _, e in ipairs(lipc_log) do if e.kv and e.kv.text then spoken[#spoken + 1] = e.kv.text end end
check(#spoken == 3 and spoken[3] == "On the next page. ", "reads sentence after sentence")
check(tts_ui.turned and page == 2, "turned the page by itself for the next sentence")
check(not R.active and tts_ui.hl == nil and captured.notification == "End of book.", "stops at the end, highlight cleared")
page = 1; R:start(); R:toggle()
check(not R.active and next(UI.scheduled) == nil, "Shift + Sym toggle stops and cancels the timer")
-- word-level document: sentences are built from words, not single words
local W = { "Call", "me", "Ishmael.", "Some", "years", "ago,", "never", "mind." }
local wdoc = {
    info = { has_pages = false },
    getNextVisibleWordEnd = function(_, xp) local i = tonumber(xp:match("^w(%d+)$")); return i and W[i] and ("e" .. i) or nil end,
    getNextVisibleWordStart = function(_, xp) local i = tonumber(xp:match("^e(%d+)$")); return i and W[i + 1] and ("w" .. (i + 1)) or nil end,
    getPrevVisibleWordStart = function(_, xp) return "w" .. xp:match("(%d+)") end,
    getTextFromXPointers = function(_, a, b)
        local i, j = tonumber(a:match("(%d+)")), tonumber(b:match("(%d+)"))
        local t = {} for k = i, j do t[#t + 1] = W[k] end return table.concat(t, " ")
    end,
}
local WR = TTS.Reader:new({ document = wdoc })
local t1, a1, b1 = WR:sentenceAt("w1")
local t2 = WR:sentenceAt(wdoc:getNextVisibleWordStart(b1))
check(t1 == "Call me Ishmael." and a1 == "w1" and t2 == "Some years ago, never mind.", "whole sentences, built word by word (commas don't split)")
do
    -- words with paragraph breaks ("\n" between blocks) and pages
    local function makeDoc(words, para_after, page_of)
        return {
            info = { has_pages = false },
            getNextVisibleWordEnd = function(_, xp) local i = tonumber(xp:match("^w(%d+)$")); return i and words[i] and ("e" .. i) or nil end,
            getNextVisibleWordStart = function(_, xp) local i = tonumber(xp:match("^e(%d+)$")); return i and words[i + 1] and ("w" .. (i + 1)) or nil end,
            getPrevVisibleWordStart = function(_, xp) return "w" .. xp:match("(%d+)") end,
            getPageFromXPointer = function(_, xp) return page_of(tonumber(xp:match("(%d+)"))) end,
            getTextFromXPointers = function(_, a, b)
                local i, j = tonumber(a:match("(%d+)")), tonumber(b:match("(%d+)"))
                if a:sub(1, 1) == "e" and b:sub(1, 1) == "w" then return para_after[i] and "\n" or " " end
                local t = {} for k = i, j do t[#t + 1] = words[k] end return table.concat(t, " ")
            end,
        }
    end
    local long = {}
    for i = 1, 45 do long[i] = "word" .. i end
    long[45] = "end."
    local R1 = TTS.Reader:new({ document = makeDoc(long, {}, function() return 1 end) })
    local t = R1:sentenceAt("w1")
    check(t and select(2, t:gsub("%S+", "")) == 45, "a 45-word sentence is one piece (no cut at 40 words)")
    local para = { "Heading", "Chapter", "One", "Text", "starts", "here." }
    local R2 = TTS.Reader:new({ document = makeDoc(para, { [3] = true }, function() return 1 end) })
    check(R2:sentenceAt("w1") == "Heading Chapter One", "a paragraph or heading ends a piece")
    local cross = { "The", "sentence", "goes", "onto", "the", "next", "page." }
    local R3 = TTS.Reader:new({ document = makeDoc(cross, {}, function(i) return i <= 4 and 1 or 2 end) })
    local _t, _a, _b, extra = R3:sentenceAt("w1")
    check(extra and extra.turn_xp == "w5" and extra.turn_frac > 0.4 and extra.turn_frac < 0.8,
        "a sentence crossing the page knows where, so the page turns while it's said")
    check(TTS.speakable("Web link (Huffman): http://asecuritysite.com/coding/huff and https://x.y/z?a=1 www.example.com/page")
        == "Web link (Huffman): and", "web addresses aren't read out " .. TTS.speakable("Web link (Huffman): http://asecuritysite.com/coding/huff and https://x.y/z?a=1 www.example.com/page"))
end
local pdf = TTS.Reader:new({ document = { info = { has_pages = true } } })
pdf:start()
check(not pdf.active and captured.info:match("not PDFs"), "PDFs: explains it's for reflowable books")

print("Read aloud on the Kindle 3: learning ttsd's request from its log")
TTS.lipc = { open_no_name = function() error("undefined symbol: LipcGetServiceName") end }
check(TTS.backend() == "shell", "libopenlipclua missing (as on the Kindle 3) -> lipc-hash-prop")
local SYSLOG = WORK .. "/messages"
TTS.syslog = SYSLOG
TTS.now = function() return "261029:000000" end
local tick = 0
local sent = {}
-- a ttsd that needs text (string), then id (int), then voice (string)
local function fakeTtsd(hash, prop)
    tick = tick + 1
    local function complain(what)
        local f = io.open(SYSLOG, "ab")
        f:write(string.format("261029:0400%02d ttsd[2923]: E lipc_handling:bad_%s:rc=82:enqueueSnippet unable to read %s\n", tick % 60, what, what))
        f:close()
        return 1, "Failed to access hasharray property (err=12 lipcErrInvalidArg, source=com.lab126.ttsd, prop=" .. prop .. ")"
    end
    if prop ~= "playSnippetNow" then return complain("text") end
    if not hash:match('text = "') then return complain("text") end
    if not hash:match("id = %(%d+%)") then return complain("id") end
    if not hash:match('voice = "') then return complain("voice") end
    return 0, ""
end
TTS.exec = function(cmd)
    local out = cmd:match("> (/tmp/gzreader%-tts%.%d+%.out) 2>&1")
    if out then
        local hf = io.open(cmd:match("< (%S+)")); local hash = hf:read("*a"); hf:close()
        local prop = cmd:match("lipc%-hash%-prop %S+ (%S+)")
        sent[#sent + 1] = hash
        local rc, body = fakeTtsd(hash, prop)
        local f = io.open(out, "wb"); f:write(body or "", "\nrc=", rc, "\n"); f:close()
    end
    return 0
end
os.remove(SYSLOG); io.open(SYSLOG, "wb"):close()
gsettings.gzreader_tts_template = nil
captured.confirm = nil
TTS.findVoice()
runLoop(function() return captured.confirm ~= nil or (captured.info and captured.info:match("didn't accept")) end, 60)
check(captured.confirm and captured.confirm.text:match("Did you hear"), "found a request ttsd accepts, asks if it was heard")
check(sent[1] == '{text = "This is the Kindle voice test. "}\n' and #sent >= 3, "started with just the text, then added what ttsd asked for")
captured.confirm.ok_callback()
local tpl = gsettings.gzreader_tts_template
check(tpl and tpl.target.prop == "playSnippetNow" and TTS.hashText(tpl.fields):match('id = %(%d+%)') and TTS.hashText(tpl.fields):match('voice = "Tom"'), "saved shape: text + id (number) + voice (string)")
sent = {}
TTS.say("A real sentence.")
check(sent[1] and sent[1]:match('text = "A real sentence%. "') and sent[1]:match("id = %(%d+%)"), "reading uses the saved shape")
local before = #sent
TTS.findVoice(); TTS.findVoice()
check(TTS.testing, "a second 'Find the Kindle voice' while one runs is ignored")
runLoop(function() return not TTS.testing end, 60)
-- a ttsd that rejects everything without saying why
fakeTtsd = function() return 1, "Failed to access hasharray property (err=12 lipcErrInvalidArg)" end
os.remove(SYSLOG); io.open(SYSLOG, "wb"):close()
captured.info = nil
TTS.findVoice()
runLoop(function() return captured.info and captured.info:match("didn't accept") end, 60)
check(captured.info and captured.info:match("didn't accept") and captured.info:match("err=12"), "nothing accepted -> shows ttsd's answer")
-- reading with a rejected request stops with the message
gsettings.gzreader_tts_template = TPL
page = 1
local R2 = TTS.Reader:new(tts_ui)
R2:start()
runLoop(function() return not R2.active end, 10)
check(not R2.active and captured.info:match("didn't respond"), "reading: rejection stops with the speech service's message")
-- paced by ttsd's own snippetStarted / snippetFinished events
local props = {}
TTS.exec = function(cmd)
    local out = cmd:match("> (/tmp/gzreader%-tts%.%d+%.out) 2>&1")
    if out then
        local hf = io.open(cmd:match("< (%S+)")); local hash = hf:read("*a"); hf:close()
        props[#props + 1] = { prop = cmd:match("lipc%-hash%-prop %S+ (%S+)"), id = tonumber(hash:match("id = %((%d+)%)")), text = hash:match('text = "(.-) "') }
        local f = io.open(out, "wb"); f:write("\nrc=0\n"); f:close()
    end
    return 0
end
local function ttsdEvent(line) local f = io.open(TTS.EVENTS_FILE, "ab"); f:write(line, "\n"); f:close() end
gsettings.gzreader_tts_template = TPL
page = 1; tts_ui.turned = nil
local R3 = TTS.Reader:new(tts_ui)
R3:start()
os.remove(TTS.EVENTS_FILE)
check(#props == 1, "one request at a time: the next waits for ttsd's answer")
runLoop(function() return #props >= 2 end, 5)
check(#props == 2 and props[1].prop == "enqueueSnippet" and props[2].prop == "enqueueSnippet" and props[2].id > props[1].id, "both queued with ttsd, in order (playSnippetNow would flush its queue)")
ttsdEvent("snippetStarted " .. props[1].id)
R3:poll()
check(R3.events_ok and tts_ui.hl == "s1", "highlight follows ttsd's snippetStarted")
local t0 = os.time()
ttsdEvent("snippetFinished " .. props[1].id); ttsdEvent("snippetStarted " .. props[2].id)
R3.queue[1].shown_at = t0 - 60 -- pretend it has been speaking long enough
R3:poll()
runLoop(function() return #props >= 3 end, 5)
check(tts_ui.hl == "s2" and #props == 3 and props[3].prop == "enqueueSnippet" and props[3].text == "On the next page.", "next sentence shown when ttsd starts it; one more queued")
R3:stop()
check(not R3.active and tts_ui.hl == nil, "stop clears everything")
TTS.exec = nil; TTS.lipc = nil; TTS.now = nil
local _ = before

print("Updates from GitHub releases")
local Update = require("gzreader_update")
check(Update.compare("1.10.0", "1.9.2") == 1 and Update.compare("v1.0.0", "1.0.0") == 0 and Update.compare("1.0.0-beta1", "1.0.0") == -1, "version comparison")
check(Update.apiUrl() == "https://api.github.com/repos/9retirement6irk/GZreader/releases/latest", "checks the GZreader GitHub repository")
local KO = WORK .. "/ko"
os.execute("rm -rf '" .. KO .. "' && mkdir -p '" .. KO .. "/frontend' '" .. KO .. "/plugins/gzreader.koplugin' '" .. KO .. "/settings'")
local function wf(p, c) local f = io.open(p, "wb"); f:write(c); f:close() end
local function rf(p) local f = io.open(p, "rb"); if not f then return nil end local c = f:read("*a"); f:close(); return c end
wf(KO .. "/frontend/old.lua", "old"); wf(KO .. "/plugins/gzreader.koplugin/main.lua", "old main")
wf(KO .. "/settings/settings.reader.lua", "mine"); wf(KO .. "/gzreader-version", "1.0.0\n")
Update.root = KO
check(Update.currentVersion() == "1.0.0", "installed version read from gzreader-version")
Update.request = function(u)
    return 200, json.encode({ tag_name = "v1.1.0", body = "Fixes", html_url = "https://github.com/x",
        assets = { { name = "other.zip", browser_download_url = "https://github.com/a" },
            { name = "gzreader-update.zip", size = 123, browser_download_url = "https://github.com/9retirement6irk/GZreader/releases/download/v1.1.0/gzreader-update.zip", digest = "sha256:" .. string.rep("ab", 32) } } })
end
local info = Update.check()
check(info and info.version == "1.1.0" and info.size == 123 and info.url:match("gzreader%-update%.zip$") and Update.state.has_update, "latest release found, newer than installed, asset + size picked")
local PKG
package.preload["ffi/archiver"] = function()
    local Reader = {}
    function Reader:new() return setmetatable({}, { __index = self }) end
    function Reader:open() return true end
    function Reader:iterate()
        local list = {}
        for p in pairs(PKG) do list[#list + 1] = p end
        table.sort(list)
        local i = 0
        return function() i = i + 1; return list[i] and { path = list[i], mode = "file" } end
    end
    function Reader:extractToPath(p, dest)
        os.execute("mkdir -p '" .. dest:match("^(.*)/") .. "'"); wf(dest, PKG[p]); return true
    end
    function Reader:close() end
    return { Reader = Reader }
end
PKG = { ["koreader/frontend/new.lua"] = "new", ["koreader/plugins/gzreader.koplugin/main.lua"] = "new main",
    ["koreader/gzreader-version"] = "1.1.0\n", ["koreader/settings/settings.reader.lua"] = "HACKED",
    ["koreader/plugins/notaplugin/x.lua"] = "x" }
local ok_apply, aerr = Update.apply("pkg.zip")
check(ok_apply, "update applied " .. tostring(aerr))
check(rf(KO .. "/frontend/new.lua") == "new" and rf(KO .. "/frontend/old.lua") == nil, "frontend replaced as a whole")
check(rf(KO .. "/plugins/gzreader.koplugin/main.lua") == "new main" and Update.currentVersion() == "1.1.0", "plugin + version replaced")
check(rf(KO .. "/settings/settings.reader.lua") == "mine" and rf(KO .. "/plugins/notaplugin/x.lua") == nil, "settings never touched; unexpected paths ignored")
local leftovers = io.popen("ls -a '" .. KO .. "' '" .. KO .. "/plugins' | grep -c 'gz-old\\|gzreader-update'"):read("*a")
check(tonumber(leftovers) == 0, "no backup or staging folders left behind")
PKG = { ["koreader/frontend/x.lua"] = "bad" }
local bad_ok = Update.apply("pkg.zip")
check(not bad_ok and rf(KO .. "/frontend/new.lua") == "new", "package without GZreader layout rejected, nothing changed")
PKG = { ["koreader/../evil"] = "x", ["koreader/gzreader-version"] = "9" }
check(not Update.apply("pkg.zip"), "path traversal rejected")
-- release without attached packages: GitHub's source code zip, tag "v.1.2.0"
Update.request = function()
    return 200, json.encode({ tag_name = "v.1.2.0", body = "", html_url = "https://github.com/x", assets = {},
        zipball_url = "https://api.github.com/repos/9retirement6irk/GZreader/zipball/v.1.2.0" })
end
local sinfo = Update.check()
check(sinfo and sinfo.version == "1.2.0" and sinfo.source and sinfo.url:match("/zipball/") and Update.state.has_update, "no assets: uses the release's source code zip; 'v.1.2.0' read as 1.2.0")
os.execute("mkdir -p '" .. KO .. "/plugins/zenos.koplugin/locales'")
wf(KO .. "/plugins/zenos.koplugin/main.lua", "old zen")
local TOP = "9retirement6irk-GZreader-abc1234/"
PKG = { [TOP .. "frontend/src.lua"] = "src", [TOP .. "reader.lua"] = "reader", [TOP .. "platform/kindle/koreader.sh"] = "sh",
    [TOP .. "plugins/gzreader.koplugin/main.lua"] = "src main", [TOP .. "plugins/zenos.koplugin/main.lua"] = "src zen",
    [TOP .. "plugins/zenos.koplugin/locales/de.po"] = "de", [TOP .. "plugins/zenos.koplugin/locales/en.po"] = "en",
    [TOP .. "plugins/kosync.koplugin/main.lua"] = "not installed", [TOP .. "base/thirdparty/x.c"] = "c",
    [TOP .. "GZREADER_VERSION"] = "1.0.0\n", [TOP .. "README.md"] = "readme" }
local sok, serr = Update.apply("src.zip", { source = true, version = "1.2.0" })
check(sok, "source zip applied " .. tostring(serr))
check(rf(KO .. "/frontend/src.lua") == "src" and rf(KO .. "/reader.lua") == "reader" and rf(KO .. "/koreader.sh") == "sh", "frontend, reader.lua and platform/kindle/koreader.sh taken from the source")
check(rf(KO .. "/plugins/gzreader.koplugin/main.lua") == "src main" and rf(KO .. "/plugins/zenos.koplugin/main.lua") == "src zen", "installed plugins updated")
check(rf(KO .. "/plugins/kosync.koplugin/main.lua") == nil and rf(KO .. "/README.md") == nil and rf(KO .. "/base/thirdparty/x.c") == nil, "plugins not installed and other repo files are skipped")
check(rf(KO .. "/plugins/zenos.koplugin/locales/de.po") == nil and rf(KO .. "/plugins/zenos.koplugin/locales/en.po") == "en", "English-only catalogs kept")
check(Update.currentVersion() == "1.2.0" and rf(KO .. "/settings/settings.reader.lua") == "mine", "version from the tag; settings untouched")
captured.textviewer = nil
preload("ui/widget/textviewer", { new = function(_, o) captured.textviewer = o; return o end })
Update.showChangelog()
check(captured.textviewer and captured.textviewer.title == "GZreader changelog" and captured.textviewer.text:match("GZreader 1%.0%.3"), "changelog is GZreader's")
Update.request = function() return 404 end
local none, nerr = Update.check()
check(none == nil and nerr:match("No GZreader release"), "no release yet -> clear message")
Update.request = nil; Update.root = nil

print("Audiobooks")
local Audiobook = require("gzreader_audiobook")
local AEngine = require("gzreader_audioengine")
-- Grimmory info -> local layout
local single = Audiobook.describe(31, { bookFileId = 1031, title = "B", durationMs = 600000, codec = "aac", folderBased = false,
    chapters = { { title = "A", startTimeMs = 0 }, { title = "B", startTimeMs = 200000 } } }, "Book.m4b")
check(single.files[1] == "audiobook.m4b" and #single.tracks == 1 and #single.chapters == 2, "single-file M4B: one file, Grimmory's chapters")
local folder = Audiobook.describe(32, { bookFileId = 1032, folderBased = true, durationMs = 120000,
    tracks = { { index = 0, fileName = "01.mp3", durationMs = 60000, cumulativeStartMs = 0, title = "Intro" },
               { index = 1, fileName = "02.mp3", durationMs = 60000, cumulativeStartMs = 60000, title = "Story" } } })
check(#folder.files == 2 and folder.files[2] == "track-002.mp3" and #folder.chapters == 2 and folder.chapters[2].title == "Story", "folder audiobook: one file per track, tracks as chapters")
local ti, tms = Audiobook.locate(folder, 75000)
check(ti == 2 and tms == 15000, "position 1:15 -> track 2 at 0:15")
check(select(2, Audiobook.chapterAt(single, 250000)).title == "B", "chapter at a position")
-- players
local mp3p = AEngine.PLAYERS[1]
local cmd, st = AEngine.command(mp3p, { kind = "file", path = "/b/x.mp3", offset_ms = 30000, size = 4096 * 100, duration_ms = 60000 })
check(cmd == "dd if='/b/x.mp3' bs=4096 skip=50 2>/dev/null | gst-launch-0.10 fdsrc ! mfw_mp3decoder ! audioconvert ! audioresample ! alsasink" and st == 30000, "MP3 starts mid-file by skipping bytes; Kindle's MP3 decoder; no -q " .. cmd)
do
local aacp
for _i, p in ipairs(AEngine.PLAYERS) do if p.id == "aac-mfw" then aacp = p end end
local acmd, ast = AEngine.command(aacp, { kind = "chunks", dir = "/b/x.m4b.chunks", starts = { 0, 15000, 30000, 45000 }, offset_ms = 40000 })
check(acmd:match("^i=2; while %[ %-f '/b/x%.m4b%.chunks'/c%$i%.aac %]; do cat '/b/x%.m4b%.chunks'/c%$i%.aac; i=%$%(%(i%+1%)%); done | gst%-launch%-0%.10 fdsrc ! mfw_aacdecoder ! ") and ast == 30000, "M4B: plays the converted chunks from the one holding 0:40 (starts 0:30)")
local pb = AEngine.command(AEngine.PLAYERS[#AEngine.PLAYERS], { kind = "file", path = "rel/x.mp3" })
check(pb:match("^gst%-launch%-0%.10 playbin uri='file:///"), "playbin gets an absolute file URI")
for _i, p in ipairs(AEngine.PLAYERS) do
    local c = AEngine.command(p, p.formats.mp3 and { kind = "file", path = "/x.mp3" } or { kind = "chunks", dir = "/d", starts = { 0 } })
    check(not c:find(" %-q"), "no -q option (" .. p.id .. ")")
end
-- the audio test sources: bundled MP3 + bundled M4A converted on the Kindle
AEngine.root = PLUGIN
local ts = AEngine.testSources()
check(ts.mp3.path:sub(1, 1) == "/" and ts.aac and #ts.aac.starts >= 1 and lfs.attributes(ts.aac.dir .. "/c0.aac", "size") > 100, "audio test: absolute MP3 path; M4A converted to ADTS chunks")
local fh = io.open(ts.aac.dir .. "/c0.aac", "rb"); local hdr = fh:read(2); fh:close()
check(hdr:byte(1) == 0xFF and bit.band(hdr:byte(2), 0xF0) == 0xF0, "chunk starts with an ADTS sync word")
-- resuming inside a chunk: from the ADTS frame playing then
;(function()
    local c0 = ts.aac.dir .. "/c0.aac"
    local b0, t0 = AEngine.adtsSkip(c0, 0)
    local b1, t1 = AEngine.adtsSkip(c0, 1000)
    local fh2 = io.open(c0, "rb"); local data = fh2:read("*a"); fh2:close()
    check(b0 == 0 and t0 == 0 and b1 > 0 and t1 <= 1000 and t1 > 900 and data:byte(b1 + 1) == 0xFF
        and bit.band(data:byte(b1 + 2), 0xF6) == 0xF0, "ADTS: 1 s into a chunk is a frame boundary just before 1 s (" .. b1 .. " bytes, " .. t1 .. " ms)")
    local bx = AEngine.adtsSkip(c0, 10 ^ 9)
    check(bx == 0, "ADTS: past the end of the chunk -> from its start")
    check(AEngine.adtsSkip("/nonexistent.aac", 5000) == 0, "ADTS: no file -> from the start of the chunk")
    local aacp2
    for _i, p in ipairs(AEngine.PLAYERS) do if p.id == "aac-mfw" then aacp2 = p end end
    local rcmd, rst = AEngine.command(aacp2, { kind = "chunks", dir = ts.aac.dir, starts = { 0 }, offset_ms = 1000 })
    check(rcmd:match("^i=1; { dd if='[^']+'/c0%.aac bs=" .. b1 .. " skip=1 2>/dev/null; while ") and rst == math.floor(t1),
        "resume inside a chunk: dd skips to that frame, then the next chunks " .. rcmd:sub(1, 90))
end)()
end
-- download a folder audiobook from Grimmory
plugin:connect("http://127.0.0.1:" .. PORT, "will", "hunter22")
local ab_done
Audiobook.download(plugin, { id = 32, title = "Book 32" }, function(b, err) ab_done = b or err end)
runLoop(function() return ab_done ~= nil end, 30)
check(type(ab_done) == "table" and #ab_done.files == 2 and ab_done.tracks[2].start == 60000, "downloaded both tracks + audiobook.json " .. tostring(type(ab_done) ~= "table" and ab_done or ""))
check(type(ab_done) == "table" and ab_done.description == "A folder audiobook & its tracks.\n\nSecond paragraph.",
    "Grimmory's description kept with the audiobook, as plain text: " .. tostring(type(ab_done) == "table" and ab_done.description))
-- play with a fake player; time is faked
local now = 1000
AEngine.clock = function() return now end
local ran = {}
AEngine.exec = function(c)
    ran[#ran + 1] = c
    local pidf = c:match("echo %$! > (%S+)%)")
    if pidf then local f = io.open(pidf, "wb"); f:write("4242\n"); f:close() end
    return 0
end
AEngine.alive = function() return true end
gsettings.gzreader_audio_players = { mp3 = "mp3-mfw", aac = "aac-mfw" }
for _i, t in ipairs(ab_done.tracks) do t.size = 4096 * 100 end -- a realistic size, so 0:15 is a whole number of 4 KB blocks
local P = Audiobook.Player:new(plugin, ab_done)
P.pos = 75000
check(P:play() and ran[#ran]:match("track%-002%.mp3") and P.track == 2, "plays track 2 from 0:15 (dd skip)")
now = now + 10
check(math.floor(P:globalPos()) == 85000, "position advances while playing")
P:push()
local prog = json.decode(ctl("/state")).progress["32"]
check(prog and prog.positionData == "25000" and prog.positionHref == "1" and prog.bookFileId == 1032 and math.abs(prog.progressPercent - 70.8) < 0.1, "progress sent like Grimmory's web player: ms in track + track index")
P:pause()
check(not P.playing and P.paused and ran[#ran]:match("kill %-TERM") and not AEngine.active(),
    "pause stops the player process (the Kindle 3 can't resume a suspended one)")
now = now + 30
check(math.floor(P:globalPos()) == 85000, "paused: position stays")
P:resume()
check(P.playing and not P.paused and ran[#ran]:match("track%-002%.mp3") and ran[#ran]:match("skip=") and math.abs(P:globalPos() - 85000) < 700,
    "resume plays again from the paused place (MP3: within a 4 KB block) " .. tostring(P:globalPos()))
P:chapterStep(-1)
check(math.floor(P.pos) == 60000, "previous chapter (track start)")
P:setSleep(1)
P.sleep_at = os.time() - 1
P:tick()
check(not P.playing, "sleep timer pauses")
P:stop()
check(Audiobook.current == nil, "stop clears the current player")
;(function()
    -- the volume rocker (everywhere) and stopping when GZreader closes
    local AudioCtl = require("gzreader_audioctl")
    local TTSm = require("gzreader_tts")
    local UIM = require("ui/uimanager")
    UIM.getTopmostVisibleWidget = UIM.getTopmostVisibleWidget or function() return nil end
    TTSm.setVolume(10)
    captured.notification = nil
    AudioCtl.onRockerEvent(1, { value = 1 })
    AudioCtl.onRockerEvent(1, { value = 2 }) -- held: auto-repeat
    AudioCtl.onRockerEvent(1, { value = 0 }) -- release: nothing
    check(TTSm.volume() == 12 and captured.notification == "Volume 12 / 15", "volume rocker: press and repeat step it, release doesn't; a note shows the level")
    AudioCtl.onRockerEvent(-1, { value = 1 })
    check(TTSm.volume() == 11, "volume rocker: down")
    local dev = require("device")
    local saved_input, saved_keys = dev.input, dev.hasKeys
    dev.input = {}
    dev.hasKeys = function() return true end
    local quit_called
    UIM.quit = function() quit_called = true end
    AudioCtl.installed = false
    AudioCtl.install()
    check(type(dev.input.event_map_adapter.VPlus) == "function" and type(dev.input.event_map_adapter.VMinus) == "function",
        "volume rocker: handled in the input layer (every screen)")
    dev.input.event_map_adapter.VMinus({ value = 1 })
    check(TTSm.volume() == 10, "volume rocker through the input layer")
    local P6 = Audiobook.Player:new(plugin, ab_done)
    P6.pos = 30000
    AEngine.alive = function() return true end
    P6:play()
    local flushes = 0
    local orig_flush = plugin.flushPending
    plugin.flushPending = function() flushes = flushes + 1 end
    now = now + 20
    UIM:quit()
    plugin.flushPending = orig_flush
    check(quit_called and not P6.playing and Audiobook.current == nil and not AEngine.active() and flushes == 0
        and math.floor(plugin.store.audiobooks[ab_done.id].pos_ms) == 50000,
        "GZreader closing: the audiobook is stopped, its place saved (sent at the next start)")
    Audiobook.quitting = nil
    dev.input, dev.hasKeys = saved_input, saved_keys
end)()
-- pull: Grimmory ahead by more than a minute -> offer to jump
ctl("/webprogress?book=32&pct=90&cfi=50000&href=1")
captured.confirm = nil
local P2 = Audiobook.Player:new(plugin, ab_done)
P2.pos = 0
local pulled
P2:pull(function() pulled = true end)
check(captured.confirm and captured.confirm.text:match("1:50"), "Grimmory's position offered (track 2 @ 0:50 = 1:50)")
captured.confirm.ok_callback()
check(pulled and P2.pos == 110000, "jumps there")
do
-- player quits at once: position kept, no skipping to the next track
local P3 = Audiobook.Player:new(plugin, ab_done)
P3.pos = 70000
P3:play()
local p3start = P3.pos
AEngine.alive = function() return false end
now = now + 1
captured.info = nil
P3:tick()
check(not P3.playing and math.floor(P3.pos) == p3start + 1000 and P3.track == 2, "failed player: stops, keeps the position (no jump to the end) " .. tostring(P3.pos))
AEngine.alive = function() return true end
P3:stop()
-- a player left running by a restart is stopped before playing / testing
do
    AEngine.stop()
    local f = io.open("/tmp/gzreader-audio.pid", "wb"); f:write("5151\n"); f:close()
    AEngine.alive = function(pid) return pid == 5151 end
    local before = #ran
    AEngine.stopStrayAtStart()
    local cmds = table.concat(ran, "\n", before + 1)
    check(cmds:match("kill %-CONT 5151") and cmds:match("kill %-TERM 5151") and not cmds:match("pidof"),
        "at start: the player from before the restart is stopped (no shell sweep) " .. cmds)
    f = io.open("/tmp/gzreader-audio.pid", "wb"); f:write("5151\n"); f:close()
    before = #ran
    local P6 = Audiobook.Player:new(plugin, ab_done)
    P6.pos = 70000
    P6:play()
    cmds = table.concat(ran, "\n", before + 1)
    check(cmds:match("kill %-TERM 5151") and cmds:match("pidof gst%-launch%-0%.10"), "before playing: leftover players are stopped")
    AEngine.alive = function() return true end
    P6:stop()
end
-- a long single-track book started mid-way: the player quitting is never "the end"
do
    local long = { id = 99, title = "Long", dir = WORK, files = { "x.mp3" },
        tracks = { { file = "x.mp3", start = 0, durationMs = 3600000, size = 4096 * 100000 } } }
    local P5 = Audiobook.Player:new(plugin, long)
    P5.pos = 1200000 -- 20 minutes in
    P5:play()
    AEngine.alive = function() return false end
    now = now + 1
    captured.info = nil
    P5:tick()
    check(not P5.playing and P5.pos >= 1190000 and Audiobook.current ~= nil
        and not (captured.info and captured.info:match("end of the audiobook")),
        "player quits at once 20 min in: not the end, position kept " .. tostring(P5.pos))
    AEngine.alive = function() return true end
    P5:play()
    now = now + 60
    AEngine.alive = function() return false end
    captured.info = nil
    P5:tick()
    check(not P5.playing and P5.pos >= 1250000 and captured.info and tostring(captured.info):match("stopped unexpectedly"),
        "player stops after a minute, far from the end: kept, says so " .. tostring(P5.pos))
    AEngine.alive = function() return true end
    P5:stop()
end
-- single-file M4B: resumed download over a dropped connection, converted to chunks, played from mid-book
ctl("/set?audio_cut=1")
local m4_done
Audiobook.download(plugin, { id = 31, title = "Book 31", primaryFileName = "b.m4b" }, function(b, err) m4_done = b or err end)
runLoop(function() return m4_done ~= nil end, 60)
check(type(m4_done) == "table", "M4B downloaded despite a dropped connection " .. tostring(type(m4_done) ~= "table" and m4_done or ""))
local ranges = 0
for _i, e in ipairs(json.decode(ctl("/state")).log or {}) do if e[1] == "TRACK" and e[2] == "31" and e[4] and e[4] ~= json.null then ranges = ranges + 1 end end
check(ranges >= 1, "the second request resumed with a Range header")
check(captured.pdialog and captured.pdialog.title:match("^Preparing") and captured.pdialog.progress_max and captured.pdialog.progress_max > 0,
    "preparing step has its own progress bar (bytes of the M4B)")
if type(m4_done) == "table" then
    local t1 = m4_done.tracks[1]
    check(t1.chunks and #t1.chunks.starts >= 1 and m4_done.files[1] == "audiobook.m4b.chunks/c0.aac"
        and lfs.attributes(m4_done.dir .. "/audiobook.m4b", "mode") == nil, "M4B converted to ADTS chunks; original removed")
    local P4 = Audiobook.Player:new(plugin, m4_done)
    P4.pos = 1500
    check(P4:play() and ran[#ran]:match("audiobook%.m4b%.chunks'/c%$i%.aac") and ran[#ran]:match("mfw_aacdecoder"), "M4B plays from the chunks with the Kindle's AAC decoder")
    P4:stop()
end
end
AEngine.exec = nil; AEngine.clock = os.time; AEngine.alive = nil
gsettings.gzreader_audio_players = nil

print("Send the diagnostic log to a phone")
PS.new = function(self, o) screen = o; return o end
plugin.pairing = nil
plugin:shareLog()
check(screen and screen.url:match("^http://%d+%.%d+%.%d+%.%d+:%d+/log/%x+$") and screen.title:match("diagnostic log"), "QR screen with a one-off log address")
local lbase = "http://127.0.0.1:" .. UI.zmqs[1].port
local lpath = screen.url:match("(/log/%x+)$")
code, body = phone("'" .. lbase .. lpath .. "'")
check(code == 200 and body:match("Download the log"), "phone gets a page with a download button")
local fname = body:match('download="([^"]+)"')
local hdr_file = WORK .. "/log_headers.txt"
code, body = phone("-D '" .. hdr_file .. "' '" .. lbase .. lpath .. "/" .. fname .. "'")
local hdrs = io.open(hdr_file):read("*a")
check(code == 200 and hdrs:match("Content%-Disposition: attachment") and body:match("Grimmory plugin log"), "download is the log file, as an attachment")
code, body = phone("'" .. lbase .. "/log/deadbeef'")
check(code == 404, "wrong address -> 404")
screen.on_cancel()
check(#UI.zmqs == 0 and not plugin.pairing, "Back stops sharing")
PS.new = orig_new


print("Usage statistics")
;(function()
    local U = require("gzreader_usage")
    local got = {}
    U.testing_sink = function(item) got[#got + 1] = item end
    gsettings.gzreader_usage = nil
    check(U.level() == "basic", "Basic by default")
    U.event("start", { device = "Kindle3" })
    U.event("reading", { minutes = 5 }, true)
    check(#got == 1 and got[1].type == "event" and got[1].payload.application == U.APP and got[1].payload.name == "start"
        and type(got[1].payload.data.install) == "string" and #got[1].payload.data.install == 32,
        "Basic: starts are recorded (with this Kindle's random ID); Full-only events aren't")
    U.download({ ok = false, error = "timeout", bytes = 2048000, seconds = 10, resumed = true })
    local d = got[#got].payload.data
    check(got[#got].payload.name == "download" and d.ok == false and d.error == "timeout" and d.kb == nil, "Basic download: done or failed only")
    gsettings.gzreader_usage = "full"
    got = {}
    U.download({ ok = true, bytes = 2048000, seconds = 10, resumed = true })
    d = got[1].payload.data
    check(d.ok and d.kb == 2000 and d.kb_per_s == 200 and d.resumed == true, "Full download: size, speed and resume")
    U.menu("home", "Open \u{201C}Secret Title\u{201D}")
    check(got[#got].payload.name == "menu" and not got[#got].payload.data.item:find("Secret", 1, true), "menu entries without book titles")
    U.request("flush", true, 800); U.request("flush", false, 1200); U.request("annotations", true, 500)
    U.slow("a keypress", 4)
    got = {}
    U.summary("test")
    local names = {}
    for _i, it in ipairs(got) do names[it.payload.name] = it.payload.data end
    check(names["slow operations"] and names["slow operations"].count == 1 and names.sync and names.sync.position.ok == 1
        and names.sync.position.failed == 1 and names.sync.position.avg_ms == 1000 and names.sync.highlights.ok == 1,
        "summaries: slow operations, and sync counts with Grimmory's answer time")
    gsettings.gzreader_usage = "off"
    got = {}
    U.event("start", {})
    U.download({ ok = true })
    check(#got == 0, "Off: nothing recorded")
    U.testing_sink = nil
    -- the batch really goes out (background process, while Wi-Fi is on)
    gsettings.gzreader_usage = "basic"
    U.SERVER = "http://127.0.0.1:" .. PORT
    U.event("start", { device = "Kindle3" })
    U.identify()
    U.maybeSend(true)
    runLoop(function() return not U.sending end, 30)
    local usage = json.decode(ctl("/state")).usage or {}
    local seen = {}
    for _i, e in ipairs(usage) do seen[e.type .. ":" .. tostring(e.payload.name)] = true end
    check(seen["event:start"] and seen["identify:nil"], "sent as one batch to /api/application/batch (event + identify)")
    local left = 0
    for name in require("libs/libkoreader-lfs").dir(U.dir()) do if name:match("jsonl$") then left = left + 1 end end
    check(left == 0, "sent batches are removed")
    gsettings.gzreader_usage = nil
end)()

print("Remote debugging")
;(function()
    local R = require("gzreader_remote")
    local lfs = require("libs/libkoreader-lfs")
    check(R.normalize(" https://in.example.com/open/feed/abc/send \n") == "https://in.example.com/open/feed/abc", "feed address: /send etc. trimmed")
    check(R.normalize("nonsense") == nil, "not an address: refused")
    local started = 0
    R.startWatchdog = function() started = started + 1 end
    -- off until an address is set
    R.started = false
    plugin.store.remote_url = nil
    R.start(plugin)
    check(not R.on and started == 0, "no address: nothing sent, no watchdog")
    -- address from the USB drive file; previous run didn't close normally
    local dir = R.dir()
    os.execute("rm -f '" .. dir .. "'/spool/*")
    local fh = io.open(dir .. "/heartbeat", "wb"); fh:write((os.time() - 600) .. " run reading big.epub p.40"); fh:close()
    fh = io.open(WORK .. "/gzreader.log.prev", "wb"); fh:write("2026 [INFO] the line before the freeze\n"); fh:close()
    fh = io.open(WORK .. "/gzreader-remote.txt", "wb"); fh:write("https://in.example.com/open/feed/xyz/send\n"); fh:close()
    R.started = false
    R.start(plugin)
    check(plugin.store.remote_url == "https://in.example.com/open/feed/xyz" and R.on, "address read from gzreader-remote.txt")
    check(started == 1, "watchdog started")
    local names = {}
    for n in lfs.dir(dir .. "/spool") do if n:match("%.json$") then names[#names + 1] = n end end
    table.sort(names)
    local bodies = {}
    for _, n in ipairs(names) do local f = io.open(dir .. "/spool/" .. n); bodies[#bodies + 1] = json.decode(f:read("*a")); f:close() end
    check(#bodies == 2 and bodies[1].eventName:match("^GZreader .* started") and bodies[1].eventContent:match("didn't close normally"),
        "start reported, with how the previous run ended")
    check(bodies[2].important == true and bodies[2].eventContent:match("big.epub p.40") and bodies[2].eventContent:match("the line before the freeze"),
        "unclean end reported: what it was doing and the previous log")
    check(bodies[1].tags[1] == "gzreader" and bodies[1].source == "gzreader", "tagged")
    local hb = io.open(dir .. "/heartbeat"):read("*a")
    check(hb:match("^%d+ run "), "heartbeat written")
    -- warnings are gathered
    require("gzreader_log").warn("something odd")
    check(R.pending and #R.pending == 1 and R.pending[1]:match("something odd"), "warnings gathered for one report")
    R.onSuspend()
    check(io.open(dir .. "/heartbeat"):read("*a"):match("^%d+ sleep "), "asleep: the watchdog doesn't call it a freeze")
    R.event("queued before turning it off", "x")
    R.stop()
    local left = 0
    for name in require("libs/libkoreader-lfs").dir(dir .. "/spool") do if name:match("%.json$") then left = left + 1 end end
    check(io.open(dir .. "/heartbeat"):read("*a"):match("^%d+ off") and left == 0 and not R.on and require("gzreader_log").on_line == nil,
        "turned off: queued reports dropped, heartbeat says off (the watchdog stops; no crash report at the next restart)")
    R.on = false
    require("gzreader_log").on_line = nil
    plugin.store.remote_url = nil
    os.remove(WORK .. "/gzreader-remote.txt")
end)()

print("Slow-operation tracing")
;(function()
    local Tr = require("gzreader_slowtrace")
    local logtxt = function() local f = io.open(WORK .. "/gzreader.log", "rb"); local t = f and f:read("*a") or ""; if f then f:close() end; return t end
    Tr.SLOW = 1
    local function spin() local t = os.time() + 1; local x = 0; while os.time() <= t do x = x + math.sin(x) end return x end
    Tr.installed = nil -- (the remote debugging section installed it without the profiler)
    Tr.install(WORK, { profile = true })
    Tr.timed("a test keypress", spin)
    local lt = logtxt()
    check(lt:match("slow: a test keypress took %d+ s %(") ~= nil, "a slow keypress is logged with its time")
    if Tr.available then
        check(lt:match("slow: a test keypress.-run_tests%.lua") ~= nil or lt:match("slow: a test keypress.-spin") ~= nil, "…and the code that used it (profiler)")
    end
    local reported
    Tr.BUSY_WINDOWS = 1
    Tr.tick(function(t) reported = t end)
    spin(); spin()
    Tr.tick(function(t) reported = t end)
    check(reported and reported:match("CPU"), "busy for a while: a report with where the CPU went")
end)()


print("Wi-Fi you turn off stays off for background work")
;(function()
    G_reader_settings.delSetting = G_reader_settings.delSetting or function(_, k) gsettings[k] = nil end
    local Net = require("gzreader_net")
    local NM = require("ui/network/manager")
    local was_c, was_wod = NET.connected, gsettings.gzreader_wifi_on_demand
    gsettings.gzreader_wifi_on_demand = true
    Net.adopt() -- wraps the Wi-Fi switches
    NET.connected = true
    NM:disableWifi(nil, true) -- the quick panel / Wi-Fi menu
    check(Net.keptOff(), "turning Wi-Fi off yourself is remembered")
    local ran = 0
    captured.wifi = {}
    Net.run(function() ran = ran + 1 end, { quiet = true, reason = "test background" })
    check(ran == 0 and #captured.wifi == 0, "background work doesn't turn it back on")
    Net.run(function() ran = ran + 1 end, { reason = "test you asked" })
    check(ran == 1 and captured.wifi[1] == "on", "something you ask for still connects")
    NET.connected = false
    NM:disableWifi() -- GZreader turning it off after a minute: not you
    check(Net.keptOff(), "…and Wi-Fi going off again by itself doesn't change that")
    NM:enableWifi(nil, true) -- Home menu → Turn Wi-Fi on
    check(not Net.keptOff(), "turning it on yourself lets background work use it again")
    NET.connected = false
    captured.wifi = {}
    Net.run(function() ran = ran + 1 end, { quiet = true, reason = "test background" })
    check(ran == 2 and captured.wifi[1] == "on-quiet", "background work turns it on quietly again")
    NET.connected, gsettings.gzreader_wifi_on_demand = was_c, was_wod
    Net.connecting = nil
end)()

print("Calendar (CalDAV, against Radicale)")
;(function()
    local CalDAV = require("gzreader_caldav")
    local CPORT = PORT + 3
    local dir = WORK .. "/caldav"
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/demo_caldav.py " .. CPORT .. " " .. dir
        .. " > " .. WORK .. "/caldav.log 2>&1 & echo $! > " .. WORK .. "/caldav.pid")
    runLoop(function() local f = io.open(WORK .. "/caldav.log"); local t = f and f:read("*a") or ""; if f then f:close() end
        return t:find("caldav ready", 1, true) ~= nil end, 30)
    -- iCalendar on its own
    local evs = CalDAV.parseEvents("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:Long \r\n title\\, with comma\r\n"
        .. "DTSTART;VALUE=DATE:20261102\r\nDTEND;VALUE=DATE:20261105\r\nBEGIN:VALARM\r\nSUMMARY:not this\r\nEND:VALARM\r\n"
        .. "END:VEVENT\r\nBEGIN:VEVENT\r\nUID:y\r\nSTATUS:CANCELLED\r\nDTSTART:20261102T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    check(#evs == 1 and evs[1].title == "Long title, with comma" and evs[1].all_day
        and evs[1].finish - evs[1].start >= 3 * 86400 - 3600, "iCalendar: folded lines, escapes, all-day span, alarms and cancelled skipped")
    check(CalDAV.parseDuration("PT1H30M") == 5400 and CalDAV.parseDuration("P1W") == 604800, "durations")
    -- repeating, expanded here (servers that don't expand)
    local base = CalDAV.timegm{ year = 2026, month = 11, day = 2, hour = 15, min = 0, sec = 0 } -- a Monday
    local rule = { start = base, finish = base + 3600, exdates = { [base + 2 * 86400] = true },
        rrule = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=6" }
    local starts = CalDAV.expandRule(rule, base - 1, base + 60 * 86400)
    check(#starts == 5 and starts[1] == base and starts[2] == base + 7 * 86400, "weekly by day, COUNT, EXDATE")
    local mrule = { start = base, finish = base + 3600, exdates = {}, rrule = "FREQ=MONTHLY;BYDAY=1TU;COUNT=3" }
    local m = CalDAV.expandRule(mrule, base - 1, base + 120 * 86400)
    local d1 = m[1] and os.date("*t", m[1])
    check(#m == 3 and d1.wday == 3 and d1.day <= 7, "monthly: first Tuesday")
    -- discovery and events from Radicale
    local store = { server = "http://127.0.0.1:" .. CPORT .. "/", username = "reader", password = "wrong" }
    local c = CalDAV:new(store)
    local got, err = c:discover()
    check(not got and err == "unauthorized", "wrong password: refused")
    store.password = "demo-app-password"
    got, err = c:discover()
    local names = {}
    for _i, cal in ipairs(got and got.calendars or {}) do names[#names + 1] = cal.name end
    check(got and table.concat(names, ",") == "Personal,Work" and got.calendars[1].color == "#2E7D32",
        "calendars found from the server address (" .. tostring(err) .. ")")
    local today = os.time{ year = os.date("*t").year, month = os.date("*t").month, day = os.date("*t").day, hour = 0 }
    local res = c:sync(got.calendars, today - 7 * 86400, today + 60 * 86400)
    local by = {}
    for _i, ev in ipairs(res and res.events or {}) do by[ev.title] = by[ev.title] or {}; table.insert(by[ev.title], ev) end
    local dentist = by["Dentist"] and by["Dentist"][1]
    check(dentist and os.date("%H:%M", dentist.start) == "15:30" and dentist.location:match("Main St") and dentist.notes:match("\n"),
        "an event: local time, place, notes")
    check(by["Mom's birthday"] and by["Mom's birthday"][1].all_day, "all-day event")
    local tm = by["Team meeting"] or {}
    local moved = by["Team meeting (moved to the afternoon)"]
    local gap = false
    for i = 2, #tm do if tm[i].start - tm[i - 1].start == 21 * 86400 then gap = true end end -- 2nd moved, 3rd cancelled
    check(#tm >= 6 and moved and #moved == 1 and moved[1].start - tm[1].start == 7 * 86400 + 4 * 3600 and gap,
        "weekly meeting: one moved, one cancelled (" .. #tm .. " left)")
    local ah = by["All hands"] or {}
    check(#ah >= 2 and os.date("*t", ah[1].start).wday == 3 and os.date("*t", ah[1].start).day <= 7, "monthly all hands on the first Tuesday")
    local bc = by["Book club: A Walk in the Woods"] and by["Book club: A Walk in the Woods"][1]
    check(bc and os.date("%H:%M", bc.start) == "19:00", "event with a TZID")
    local runs = by["Morning run"] or {}
    check(#runs >= 10 and runs[1].cal == 1 and by["Quarterly review"][1].cal == 2, "events know their calendar")
    local sorted = true
    for i = 2, #res.events do if res.events[i].start < res.events[i - 1].start then sorted = false end end
    check(sorted, "in time order")
    -- an address that is a calendar
    local c2 = CalDAV:new({ server = "http://127.0.0.1:" .. CPORT .. "/reader/work/", username = "reader", password = "demo-app-password" })
    local one = c2:discover()
    check(one and #one.calendars == 1 and one.calendars[1].name == "Work", "a calendar's own address works too")
    os.execute("kill $(cat " .. WORK .. "/caldav.pid) 2>/dev/null")
end)()

print("Notes (Memos v0.31)")
;(function()
    local MPORT = PORT + 2
    local MBASE = "http://127.0.0.1:" .. MPORT
    local function mctl(method, path)
        local h = io.popen("curl -s -X " .. method .. " '" .. MBASE .. path .. "'"); local o = h:read("*a"); h:close(); return o
    end
    local function mstate() return json.decode(mctl("GET", "/__state")) end
    -- the editor's helpers need KOReader's util.splitToChars (stubbed here)
    local U = require("util")
    U.splitToChars = U.splitToChars or function(t)
        local out = {}
        for ch in (t or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
        return out
    end
    -- UI widgets aren't loaded in tests: stand-ins for the Notes modules
    for _i, name in ipairs({ "ui/widget/buttondialog", "ui/widget/container/centercontainer", "ui/font",
        "ui/widget/container/framecontainer", "ui/geometry", "ui/gesturerange", "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan", "ui/widget/imagewidget", "ui/widget/infomessage", "ui/widget/container/inputcontainer",
        "ui/widget/container/leftcontainer", "ui/widget/menu", "ui/widget/overlapgroup", "ui/widget/container/rightcontainer",
        "ui/size", "ui/widget/textboxwidget", "ui/widget/textwidget", "ui/widget/verticalgroup", "ui/widget/verticalspan",
        "ffi/blitbuffer" }) do
        package.loaded[name] = magic() -- (the last section: nothing after needs the real ones)
    end
    local Memos = require("gzreader_memos")
    local Sticky = require("gzreader_sticky")
    local Notes = require("gzreader_notes")
    local NE = require("gzreader_noteeditor")
    local Log = require("gzreader_log")
    local function logtxt() local f = io.open(WORK .. "/gzreader.log", "rb"); local t = f and f:read("*a") or ""; if f then f:close() end; return t end

    -- Markdown, as the sticky notes show it
    local md = "## Trip\n\nPlan **the** _route_ and [map](https://x.y).\n- [ ] permit\n- [x] map\n* bullet\n![pic](/file/attachments/abc/p.png)\n\n"
    local ls = Sticky.lines(md)
    check(ls[1].kind == "heading" and ls[1].level == 2 and ls[1].text == "Trip", "markdown: heading")
    check(ls[4].kind == "check" and not ls[4].done and ls[5].kind == "check" and ls[5].done, "markdown: checklist items, ticked and not")
    check(ls[7].kind == "image" and ls[7].src == "/file/attachments/abc/p.png" and #ls == 7, "markdown: picture line; blank lines at the end dropped")
    check(Sticky.plain(ls[3].text) == "Plan the route and map.", "markdown: bold, italic, links made plain")
    check(Sticky.plain("* bullet") == "\u{2022} bullet", "markdown: bullets as •")
    check(Sticky.preview(md):match("^Trip\nPlan the route") and Sticky.preview(md):match("\u{2610} permit\n\u{2611} map"), "sticky preview: boxes for checklists")
    check(Sticky.firstImage(md) == "/file/attachments/abc/p.png", "first picture found")
    check(Sticky.tagsOnly("#travel #hiking") and not Sticky.tagsOnly("#idea buy milk") and not Sticky.tagsOnly(""), "a line of only tags")
    check(Sticky.preview("Title\n\nbody\n\n#a #b") == "Title\nbody", "sticky preview: no blank lines, tag line left out")
    local t2 = Sticky.toggle(md, 2)
    check(t2:match("%- %[ %] map") and t2:match("%- %[ %] permit") and t2:match("^## Trip"), "tick: the 2nd item unticked, the rest untouched")
    check(Sticky.toggle(Sticky.toggle("- [ ] a\n- [ ] b", 1), 1) == "- [ ] a\n- [ ] b", "tick twice: as before")
    local now = os.time()
    check(Sticky.when(os.date("!%Y-%m-%dT%H:%M:%SZ", now), now):match("^Today %d+:%d%d [AP]M$"), "date: today with the time (UTC turned local)")
    check(Sticky.when(os.date("!%Y-%m-%dT%H:%M:%SZ", now - 400 * 86400), now):match(", %d%d%d%d$"), "date: another year shows it")

    -- the editor's toolbar
    local text, cur = NE.applyPrefix("milk\neggs", 7, NE.TOOLS[2])
    check(text == "milk\n- [ ] eggs" and cur == 13, "toolbar Check: on the cursor's line, cursor after the box")
    text, cur = NE.applyPrefix(text, 13, NE.TOOLS[2])
    check(text == "milk\neggs", "toolbar Check again: removed")
    text = NE.applyPrefix("- milk", 3, NE.TOOLS[2])
    check(text == "- [ ] milk", "toolbar Check on a bullet: replaces it")
    text = NE.applyPrefix("1. one\ntwo", 9, NE.TOOLS[3])
    check(text == "1. one\n2. two", "toolbar Num: continues the list above")
    text = NE.applyPrefix("Title", 1, NE.TOOLS[4])
    check(text == "## Title", "toolbar Head")
    text, cur = NE.applyWrap("make it bold", 9, "**")
    check(text == "make it **bold**" and cur == 17, "toolbar B on a word: wrapped")
    text, cur = NE.applyWrap("a ", 3, "*")
    check(text == "a **" and cur == 4, "toolbar I between words: markers, cursor inside")
    text, cur = NE.insertTag("trip", 5, "travel")
    check(text == "trip #travel " and cur == 14, "toolbar Tag: #tag with a space before")
    check(NE.cleanTag(" #to read! ") == "to-read", "new tag: cleaned like Memos' tags")

    -- filters
    check(Notes.cel({ kind = "tag", value = "travel" }) == '"travel" in tags', "filter: tag (Memos CEL)")
    check(Notes.cel({ kind = "date", value = 7 }) == 'created_ts > now - duration("168h")', "filter: last 7 days")
    check(Notes.cel({ kind = "pinned" }) == "pinned == true" and Notes.cel({ kind = "all" }) == nil, "filter: pinned; all")
    check(Notes.cel({ kind = "search", value = 'say "hi"' }) == 'content.contains("say \\"hi\\"")', "filter: search text quoted")
    check(Notes.keep({ place = "Home", attachments = {} }, { kind = "place", value = "Home" })
        and not Notes.keep({ attachments = {} }, { kind = "attachments" }), "filter: place and attachments on the Kindle")
    local tg = Notes.tagsIn("#a and #b/c, (#d) x#no #a")
    check(#tg == 3 and tg[1] == "a" and tg[2] == "b/c" and tg[3] == "d", "tags from text (no repeats; not inside words)")

    -- connecting
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/mock_memos.py " .. MPORT .. " > " .. WORK .. "/memos.log 2>&1 & echo $! > " .. WORK .. "/memos.pid")
    runLoop(function() return mctl("GET", "/__state"):match("memos") ~= nil end, 10)
    mctl("POST", "/__reset?sample=1")
    plugin.store.memos = nil
    local ok, err = Notes.connect(plugin, "127.0.0.1:" .. MPORT, "wrong-token")
    check(not ok and err:match("didn't accept"), "connect: a wrong token is refused")
    ok, err = Notes.connect(plugin, "http://127.0.0.1:" .. MPORT .. "/explore", " memos-test-token\n")
    check(ok and plugin.store.memos.server == "http://127.0.0.1:" .. MPORT and plugin.store.memos.user == "Will"
        and plugin.store.memos.prefix == "/api/v1", "connect: address cleaned up, token trimmed, user kept, /api/v1")
    check(not logtxt():find("memos-test-token", 1, true), "the token is never in the log")

    -- notes
    AsyncMod.sync = true
    Notes.notes, Notes.filter = nil, { kind = "all" }
    local done
    Notes.refresh(plugin, function(r) done = r end)
    check(done and #Notes.notes == 7 and Notes.notes[1].pinned and Notes.notes[1].tags[1] == "reading", "list: 7 notes, pinned first")
    local trip
    for _i, m in ipairs(Notes.notes) do if m.place == "Amicalola Falls" then trip = m end end
    check(trip and trip.attachments[1].filename == "Trail map.pdf" and trip.attachments[1].type == "application/pdf"
        and trip.attachments[1].size > 0, "a note's place and attachments")
    local cache = Memos.loadCache()
    check(cache and #cache.notes == 7, "kept on the Kindle (offline)")
    Notes.setFilter(plugin, { kind = "tag", value = "travel" })
    check(#Notes.notes == 2, "tag filter: Memos sends 2 notes")
    Notes.setFilter(plugin, { kind = "date", value = 7, label = "Last 7 days" })
    check(#Notes.notes == 5, "date filter: last 7 days")
    Notes.setFilter(plugin, { kind = "attachments" })
    check(#Notes.visible() == 2, "with attachments (on the Kindle)")
    Notes.setFilter(plugin, { kind = "all" })
    check(#Memos.loadCache().notes == 7, "a filtered list doesn't replace the kept one")

    -- tick a box: saved to Memos
    trip.content = Sticky.toggle(trip.content, 2)
    Notes.saveContent(plugin, trip)
    check(#plugin.store.memos.queue == 1 and trip.pending, "ticked: queued")
    Notes.refresh(plugin, function() end)
    local st = mstate()
    local server_trip
    for _i, m in ipairs(st.memos) do if m.name == trip.name then server_trip = m end end
    check(server_trip and server_trip.content:match("%- %[x%] trail map printed") and #plugin.store.memos.queue == 0,
        "the tick reached Memos; queue empty")
    local patched = false
    for _i, l in ipairs(st.log) do if l:match("^PATCH /api/v1/" .. trip.name .. "%?updateMask=content$") then patched = true end end
    check(patched, "PATCH with updateMask=content")

    -- new notes offline wait, private by default
    NET.connected = false
    mctl("POST", "/__offline?on=1")
    local q = Notes.enqueue(plugin, { op = "create", content = "Buy stamps #errands", visibility = "PRIVATE" })
    Notes.refresh(plugin, function(r, e) done, err = r, e end)
    check(not done and #plugin.store.memos.queue == 1, "offline: the new note waits")
    Notes.loadCache(plugin)
    check(Notes.notes[1].local_id == q.id and Notes.notes[1].pending and Notes.notes[1].tags[1] == "errands", "…and shows on the board meanwhile")
    mctl("POST", "/__offline?on=0")
    NET.connected = true
    Notes.refresh(plugin, function(r) done = r end)
    st = mstate()
    local made
    for _i, m in ipairs(st.memos) do if m.content == "Buy stamps #errands" then made = m end end
    check(done and made and made.visibility == "PRIVATE" and #plugin.store.memos.queue == 0, "back online: created in Memos, private")
    check(#Notes.notes == 8 and not Notes.notes[2].local_id, "the board now has Memos' copy")

    -- edits change who can see it only when asked; pin
    Notes.saveContent(plugin, made and Memos.slim(made) or {}, "PROTECTED")
    Notes.enqueue(plugin, { op = "pin", name = made.name, pinned = true })
    Notes.refresh(plugin, function() end)
    st = mstate()
    for _i, m in ipairs(st.memos) do if m.name == made.name then made = m end end
    check(made.visibility == "PROTECTED" and made.pinned and Notes.notes[1].name == made.name, "visibility changed; pinned goes first")

    -- attachments
    local pic
    for _i, m in ipairs(Notes.notes) do
        for _j, a in ipairs(m.attachments) do if a.type == "image/png" then pic = a end end
    end
    local path = Memos.filePath(pic)
    os.remove(path)
    local got = Notes.client(plugin):download(pic, path)
    local f = io.open(path, "rb"); local head = f and f:read(4); if f then f:close() end
    check(got and head == "\137PNG", "picture downloaded")
    check(path:match("/cache/gzreader%-notes/ridge%-ridge%.png$"), "kept in cache/gzreader-notes")

    -- Settings → Notes: synced tags, how many notes are kept, attachment limit
    check(plugin.store.memos.user_name == "users/1", "connect keeps the user (for the tag list)")
    plugin.store.memos.sync_tags = { "travel", "quotes" }
    check(Notes.query(plugin, { kind = "all" }) == 'tag in ["travel", "quotes"]', "synced tags: Memos filter")
    check(Notes.query(plugin, { kind = "pinned" }) == '(tag in ["travel", "quotes"]) && (pinned == true)', "synced tags and the board's filter together")
    Notes.filter = { kind = "all" }
    Notes.refresh(plugin, function(r) done = r end)
    local only = true
    for _i, m in ipairs(Notes.notes) do
        local hit = false
        for _j, t in ipairs(m.tags) do if t == "travel" or t == "quotes" then hit = true end end
        only = only and hit
    end
    check(done and #Notes.notes == 3 and only, "only notes with the synced tags are fetched")
    check(plugin.store.memos.tag_counts and plugin.store.memos.tag_counts.reading == 2, "tag counts for all notes come with it (Memos user stats)")
    local NS = require("gzreader_notesettings")
    local known = {}
    for _i, t in ipairs(NS.knownTags(plugin)) do known[t.tag] = t.count end
    check(known.reading == 2 and known.shopping == 1, "the tag list shows tags of notes not on the Kindle too")
    plugin.store.memos.sync_tags = nil
    Notes.prefs(plugin).keep = 3
    Notes.refresh(plugin, function(r) done = r end)
    check(done and #Notes.notes == 3, "notes kept: limit respected")
    Notes.prefs(plugin).keep = 100
    local c3 = Notes.client(plugin)
    local all3 = c3:listAll(nil, 5)
    check(all3 and #all3.memos == 5, "paged fetch stops at the limit")
    -- attachments over the limit: the ones used longest ago go
    local dir = Memos.filesDir()
    os.execute("rm -f '" .. dir .. "'/*")
    local function put(name, kb, age)
        local f = io.open(dir .. "/" .. name, "wb"); f:write(string.rep("x", kb * 1024)); f:close()
        require("libs/libkoreader-lfs").touch(dir .. "/" .. name, os.time() - age, os.time() - age)
    end
    put("old.pdf", 600, 3000); put("mid.png", 600, 2000); put("new.png", 600, 10)
    local nb, fb, nf = Notes.storage()
    check(nf == 3 and fb == 3 * 600 * 1024 and nb > 0, "storage used: notes and attachments")
    Notes.prefs(plugin).files_mb = 1
    local removed = Notes.pruneFiles(plugin, dir .. "/old.pdf")
    check(removed == 2 and io.open(dir .. "/old.pdf") and io.open(dir .. "/new.png") == nil,
        "over the limit: oldest go first, never the one just opened")
    Notes.prefs(plugin).files_mb = 0
    put("a.png", 600, 1); put("b.png", 600, 1)
    check(Notes.pruneFiles(plugin) == 0, "no limit: nothing removed")
    Notes.prefs(plugin).files_mb = 25
    local items = NS.items(plugin)
    check(#items == 5 and items[1].text_func():match("Will") and items[3].text_func():match("^Storage used: "),
        "Settings → Notes: connection, sync, storage, kept notes, attachment limit")

    -- a token that stopped working
    plugin.store.memos.token = "revoked"
    Notes.refresh(plugin, function(r, e) done, err = r, e end)
    check(not done and err == "unauthorized" and Notes.describe(err):match("access token"), "revoked token: says to connect again")
    plugin.store.memos.token = "memos-test-token"

    -- newer servers: /api instead of /api/v1
    os.execute("kill $(cat " .. WORK .. "/memos.pid) 2>/dev/null")
    socket.sleep(0.3)
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/mock_memos.py " .. MPORT .. " --sample --prefix /api > " .. WORK .. "/memos.log 2>&1 & echo $! > " .. WORK .. "/memos.pid")
    runLoop(function() return mctl("GET", "/__state"):match("memos") ~= nil end, 10)
    local c2 = Memos:new({ server = "http://127.0.0.1:" .. MPORT, token = "memos-test-token" })
    local me = c2:me()
    check(me and me.username == "will" and c2.store.prefix == "/api", "newer Memos (/api): found and remembered")

    -- Memos 26.10+: /api/v1 answers 410 Gone. A connection made before the
    -- server was updated remembers /api/v1: it moves to /api by itself.
    os.execute("kill $(cat " .. WORK .. "/memos.pid) 2>/dev/null")
    socket.sleep(0.3)
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/mock_memos.py " .. MPORT .. " --sample --memos26 > " .. WORK .. "/memos.log 2>&1 & echo $! > " .. WORK .. "/memos.pid")
    runLoop(function() return mctl("GET", "/__state"):match("memos") ~= nil end, 10)
    plugin.store.memos.prefix = "/api/v1"
    plugin.store.memos.tag_counts = nil
    Notes.notes = nil
    local r26, e26
    Notes.refresh(plugin, function(r, e) r26, e26 = r, e end)
    runLoop(function() return r26 ~= nil end, 20)
    check(r26 and plugin.store.memos.prefix == "/api" and type(Notes.notes) == "table" and #Notes.notes > 0,
        "Memos 26.10 (410 Gone on /api/v1): notes load from /api, which is remembered " .. tostring(e26))
    check(type(plugin.store.memos.tag_counts) == "table" and next(plugin.store.memos.tag_counts) ~= nil,
        "Memos 26.10: tag counts (tagCounts) read")
    local log26 = mctl("GET", "/__state")
    local before = select(2, log26:gsub("/api/v1/", ""))
    local r26b
    Notes.refresh(plugin, function(r) r26b = r end)
    runLoop(function() return r26b ~= nil end, 20)
    check(r26b and select(2, mctl("GET", "/__state"):gsub("/api/v1/", "")) == before, "Memos 26.10: next refresh goes straight to /api")
    local c404, _d, e404 = Memos:new(plugin.store.memos):request("PATCH", "/memos/999", { content = "x" }, { updateMask = "content" })
    check(c404 == 404 and e404 == "http_404", "Memos 26.10: a note that isn't there is still 'not found' (not 410)")

    -- disconnect
    Notes.disconnect(plugin)
    check(next(plugin.store.memos) == nil and Memos.loadCache() == nil, "disconnect: address, token and kept notes removed")
    os.execute("kill $(cat " .. WORK .. "/memos.pid) 2>/dev/null")
end)()

print("Calendar tab")
;(function()
    package.loaded["ui/widget/container/widgetcontainer"] = magic()
    local Cal = require("gzreader_calendar")
    local CalDAV = require("gzreader_caldav")
    local CPORT = PORT + 4
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/demo_caldav.py " .. CPORT .. " " .. WORK .. "/caldav2"
        .. " > " .. WORK .. "/caldav2.log 2>&1 & echo $! > " .. WORK .. "/caldav2.pid")
    runLoop(function() local f = io.open(WORK .. "/caldav2.log"); local t = f and f:read("*a") or ""; if f then f:close() end
        return t:find("caldav ready", 1, true) ~= nil end, 30)
    -- dates (DST: Nov 1 2026 in US time zones)
    local d0 = os.time{ year = 2026, month = 10, day = 31, hour = 0 }
    check(os.date("%Y-%m-%d %H:%M", Cal.addDays(d0, 1)) == "2026-11-01 00:00" and os.date("%Y-%m-%d %H:%M", Cal.addDays(d0, 2)) == "2026-11-02 00:00",
        "days add up across the clock change")
    check(os.date("*t", Cal.weekStart(d0, 1)).wday == 1 and os.date("*t", Cal.weekStart(d0, 2)).wday == 2, "weeks start on Sunday or Monday")
    Cal.events = { { title = "Trip", start = d0, finish = Cal.addDays(d0, 3), all_day = true },
        { title = "Lunch", start = d0 + 12 * 3600, finish = d0 + 13 * 3600 } }
    check(#Cal.eventsOn(d0) == 2 and #Cal.eventsOn(Cal.addDays(d0, 2)) == 1 and #Cal.eventsOn(Cal.addDays(d0, 3)) == 0,
        "events per day; a three-day trip shows on its three days only")
    check(Cal.when(Cal.events[2]):match("12:00 PM \u{2013} 1:00 PM$"), "when: " .. Cal.when(Cal.events[2]))
    -- connecting
    local ok, err = Cal.connect(plugin, "127.0.0.1:" .. CPORT, "reader", "nope")
    check(not ok and err:match("didn't accept"), "wrong password refused")
    ok, err = Cal.connect(plugin, "127.0.0.1:" .. CPORT, "reader", "demo-app-password")
    local cals = plugin.store.caldav.calendars or {}
    check(ok and #cals == 2 and cals[1].enabled and plugin.store.caldav.server == "http://127.0.0.1:" .. CPORT,
        "connected (http after https failed): calendars found, all shown (" .. tostring(err) .. ")")
    local f = io.open(WORK .. "/gzreader.log", "rb"); local logtxt = f and f:read("*a") or ""; if f then f:close() end
    check(not logtxt:find("demo-app-password", 1, true), "the password is never in the log")
    -- syncing
    AsyncMod.sync = true
    Cal.events, Cal.cached_at = nil, nil
    local done
    Cal.refresh(plugin, function(r) done = r end)
    local titles = {}
    for _i, ev in ipairs(Cal.events or {}) do titles[ev.title] = true end
    check(done and titles["Dentist"] and titles["Team meeting"] and titles["Morning run"], "synced: events of both calendars")
    local cache = CalDAV.loadCache()
    check(cache and #cache.events == #Cal.events and cache.from and cache.to, "kept on the Kindle with the synced range")
    cals[2].enabled = false
    Cal.refresh(plugin, function(r) done = r end)
    titles = {}
    for _i, ev in ipairs(Cal.events or {}) do titles[ev.title] = true end
    check(done and titles["Dentist"] and not titles["Team meeting"], "a calendar turned off isn't synced")
    cals[2].enabled = true
    -- reconnecting keeps which calendars are shown
    cals[2].enabled = false
    Cal.connect(plugin, "http://127.0.0.1:" .. CPORT, "reader", "demo-app-password")
    check(plugin.store.caldav.calendars[2].enabled == false, "connecting again keeps the calendars you turned off")
    local prefs = Cal.prefs(plugin)
    check(prefs.layout == "agenda" and prefs.week_start == 1 and prefs.days_ahead == 90 and prefs.days_back == 14, "defaults: Agenda, Sunday, 90 / 14 days")
    Cal.cursor, Cal.layout = Cal.dayStart(), "week"
    check(Cal.periodLabel(plugin):match("\u{2013}"), "week label: " .. Cal.periodLabel(plugin))
    Cal.layout = "month"
    check(Cal.periodLabel(plugin):match("%d%d%d%d$"), "month label: " .. Cal.periodLabel(plugin))
    check(#Cal.settingsItems(plugin) == 7, "Settings → Connections → Calendar: links, CalDAV account, calendars, layout, week start, range, storage")

    -- calendar links (webcal / ICS): a Proton-style feed with two time zones
    local FPORT = PORT + 5
    os.execute("mkdir -p '" .. WORK .. "/feeds/api/calendar/v1/url/abc123' && cp " .. PLUGIN
        .. "/../../tools/gzreader/emulator/demo/proton_sample.ics '" .. WORK .. "/feeds/api/calendar/v1/url/abc123/calendar.ics'")
    os.execute("cd '" .. WORK .. "/feeds' && (python3 -m http.server " .. FPORT .. " --bind 127.0.0.1 > /dev/null 2>&1 & echo $! > ../feeds.pid)")
    socket.sleep(1)
    local secret = "CacheKey=s3cr3tCacheKey&PassphraseKey=s3cr3tPassphrase"
    local link = "http://127.0.0.1:" .. FPORT .. "/api/calendar/v1/url/abc123/calendar.ics?" .. secret
    check(CalDAV.normalizeFeed("webcal://calendar.proton.me/api/x/calendar.ics?a=1") == "https://calendar.proton.me/api/x/calendar.ics?a=1"
        and CalDAV.normalizeFeed("not a link at all") == nil, "webcal:// links become https://")
    local lines = Cal.parseLinkLines("# mine\n" .. link .. "\nWork | webcal://x.example/w.ics\n\n")
    check(#lines == 2 and lines[2].name == "Work" and lines[2].url == "webcal://x.example/w.ics", "pasted lines: one link each, optional name")
    local from = os.time{ year = 2026, month = 10, day = 20, hour = 0 }
    local to = os.time{ year = 2026, month = 12, day = 31, hour = 0 }
    local feed = CalDAV.fetchFeed(link, from, to)
    check(feed and feed.name == "Family" and feed.count == 6, "a calendar link fetched: its name and events")
    local by = {}
    for _i, ev in ipairs(feed and feed.events or {}) do by[ev.title] = by[ev.title] or {}; table.insert(by[ev.title], ev) end
    local b1, b2 = by["Call with Berlin office"], by["Call with Berlin office (after the US change)"]
    check(b1 and os.date("!%H:%M", b1[1].start) == "15:00" and b2 and os.date("!%H:%M", b2[1].start) == "15:00",
        "Europe/Berlin 16:00 in CET is 15:00 UTC (its own time zone rules)")
    local summer = CalDAV.parseEvents(io.open(PLUGIN .. "/../../tools/gzreader/emulator/demo/proton_sample.ics"):read("*a"))
    local sc
    for _i, e in ipairs(summer) do if e.title == "Summer call (Berlin CEST)" then sc = e end end
    check(sc and os.date("!%H:%M", sc.start) == "07:00", "…and 09:00 in CEST is 07:00 UTC")
    local piano = by["Piano lesson"] or {}
    local moved = by["Piano lesson (moved)"]
    local p1, p_after = piano[1], piano[2]
    check(#piano == 6 and moved and #moved == 1, "weekly: 8 lessons, one cancelled, one moved (" .. #piano .. ")")
    check(p1 and os.date("!%H:%M", p1.start) == "21:00" and p_after and os.date("!%H:%M", p_after.start) == "22:00"
        and os.date("!%H:%M", moved[1].start) == "23:30", "New York 5 PM: 21:00 UTC in October, 22:00 after the clock change")
    local school = by["No school (Thanksgiving)"]
    check(school and school[1].all_day and school[1].notes:match("\n"), "all-day event with notes")
    -- adding links: checked, named, kept; never logged
    local lf = io.open(WORK .. "/gzreader.log", "rb"); local before = lf and #lf:read("*a") or 0; if lf then lf:close() end
    local results = Cal.addFeeds(plugin, { { url = link }, { url = link }, { url = "http://127.0.0.1:" .. FPORT .. "/missing.ics" },
        { url = "nonsense here" } })
    check(results[1].ok and results[1].label == "Family" and results[1].count == 6 and results[2].ok and results[2].note
        and not results[3].ok and not results[4].ok, "links checked when added: added, already there, broken, not a link")
    check(#Cal.feeds(plugin) == 1, "one link kept")
    local r3 = Cal.addFeeds(plugin, { { url = "webcal://127.0.0.1:" .. FPORT .. "/api/calendar/v1/url/abc123/calendar.ics?x=2", name = "Plain" } })
    check(r3[1].ok and Cal.feeds(plugin)[2].url:match("^http://"), "webcal:// on a server without HTTPS: plain HTTP")
    Cal.removeFeed(plugin, 2)
    lf = io.open(WORK .. "/gzreader.log", "rb"); local logtxt2 = lf and lf:read("*a") or ""; if lf then lf:close() end
    check(not logtxt2:find("s3cr3t", 1, true) and not logtxt2:find("abc123", 1, true) and logtxt2:sub(before + 1):find("calendar link", 1, true),
        "the link (and its keys) never reach the log: only its server")
    -- syncing links and the CalDAV account together
    Cal.events, Cal.cached_at = nil, nil
    plugin.store.calendar_prefs.days_back, plugin.store.calendar_prefs.days_ahead = 30, 365
    Cal.refresh(plugin, function(r) done = r end)
    local fam, cd = 0, 0
    local ncal = #(plugin.store.caldav.calendars or {})
    for _i, ev in ipairs(Cal.events or {}) do
        if ev.cal == ncal + 1 then fam = fam + 1 end
        if ev.cal <= ncal then cd = cd + 1 end
    end
    check(done and fam > 0 and cd > 0, "synced: the CalDAV account's events and the link's (" .. cd .. " + " .. fam .. ")")
    local one
    for _i, ev in ipairs(Cal.events) do if ev.cal == ncal + 1 then one = ev end end
    check(one and Cal.calName(plugin, one) == "Family", "a link's events know its calendar name")
    -- calendars.txt on the USB drive
    Cal.removeFeed(plugin, 1)
    local libdir = plugin:libraryDir()
    local tf = io.open(libdir .. "/calendars.txt", "wb"); tf:write("# calendars\nKids | " .. link .. "\n"); tf:close()
    local res2 = Cal.importFile(plugin)
    check(res2 and res2[1].ok and Cal.feeds(plugin)[1].name == "Kids" and Cal.feedName(Cal.feeds(plugin)[1]) == "Kids",
        "calendars.txt: links added with their names")
    os.remove(libdir .. "/calendars.txt")
    Cal.disconnect(plugin)
    check(next(plugin.store.caldav) == nil and CalDAV.loadCache() == nil and plugin.store.calendar_prefs, "disconnect: password and events removed, preferences kept")
    check(Cal.hasSources(plugin) and #Cal.feeds(plugin) == 1, "disconnecting the CalDAV account keeps the calendar links")
    Cal.events, Cal.cached_at = nil, nil
    Cal.refresh(plugin, function(r) done = r end)
    local only_links = #(Cal.events or {}) > 0
    for _i, ev in ipairs(Cal.events or {}) do if ev.cal ~= 1 then only_links = false end end
    check(done and only_links, "links alone: the Calendar tab works without a CalDAV account")

    print("The phone page: Notes, Calendar (account, links, editing), books")
    for _i, f in ipairs(Cal.feeds(plugin)) do f.id = nil end
    while #Cal.feeds(plugin) > 0 do Cal.removeFeed(plugin, 1) end
    local MP = PORT + 2
    os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/emulator/demo/mock_memos.py " .. MP .. " --sample > " .. WORK .. "/memos3.log 2>&1 & echo $! > " .. WORK .. "/memos3.pid")
    runLoop(function()
        local p = io.popen("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:" .. MP .. "/__state"); local c = p:read("*a"); p:close()
        return c == "200" end, 10)
    local PS = require("gzreader_pairscreen")
    local orig_ps = PS.new
    local scr
    PS.new = function(_self, o) scr = o; return o end
    local Phone = require("gzreader_phone")
    local closed
    Phone.open(plugin, { section = "calendar", on_close = function(ch) closed = ch end })
    check(scr and scr.url:match("/phone/%x+#calendar$"), "opened at the calendar part (#calendar)")
    local P = "http://127.0.0.1:" .. UI.zmqs[1].port .. scr.url:match("(/phone/%x+)")
    local function post(path, fields, extra)
        local args = { "-L", #fields == 0 and "-d ''" or nil }
        for _i, kv in ipairs(fields) do args[#args + 1] = "--data-urlencode '" .. kv .. "'" end
        return phone(table.concat(args, " ") .. " " .. (extra or "") .. " '" .. P .. path .. "'")
    end
    local c, b = post("/memos", { "server=127.0.0.1:" .. MP, "token=not-it" })
    check(c == 200 and b:match("didn&#39;t accept that access token") or b:match("didn't accept that access token"), "Notes: a wrong token -> the page says so")
    c, b = post("/memos", { "server=127.0.0.1:" .. MP, "token=memos-test-token" })
    check(c == 200 and b:match("Notes connected to Memos as Will") and plugin.store.memos.token == "memos-test-token", "Notes: connected from the phone")
    c, b = post("/caldav", { "server=127.0.0.1:" .. CPORT, "username=reader", "password=demo-app-password" })
    check(c == 200 and b:match("CalDAV account connected: 2 calendars") and #plugin.store.caldav.calendars == 2, "Calendar: CalDAV account connected from the phone")
    local href = plugin.store.caldav.calendars[1].href
    c, b = post("/calendar/show", { "href=" .. href })
    check(c == 200 and plugin.store.caldav.calendars[1].enabled == false and b:match("is hidden"), "Calendar: one of the account's calendars hidden from the phone")
    c, b = post("/links", { "links=Family | " .. link .. "\nnonsense" })
    check(c == 200 and b:match("✓ Family") and b:match("✗") and #Cal.feeds(plugin) == 1, "Calendar: links added from the phone, each checked")
    local fid = Cal.feeds(plugin)[1].id
    check(fid and b:find('name="id" value="' .. fid .. '"', 1, true), "each link has its own form on the page")
    c, b = post("/link", { "id=" .. fid, "name=Kids", "url=", "action=save" })
    check(c == 200 and Cal.feeds(plugin)[1].name == "Kids" and Cal.feeds(plugin)[1].enabled == false and b:match("Saved “Kids”"),
        "Calendar: link renamed and hidden from the phone")
    local old_url = Cal.feeds(plugin)[1].url
    c, b = post("/link", { "id=" .. fid, "name=Kids", "url=http://127.0.0.1:" .. FPORT .. "/missing.ics", "shown=1", "action=save" })
    check(c == 200 and b:match("new link didn") and Cal.feeds(plugin)[1].url == old_url, "Calendar: a broken replacement link is refused, the old one kept")
    c, b = post("/link", { "id=" .. fid, "name=", "url=webcal://127.0.0.1:" .. FPORT .. "/api/calendar/v1/url/abc123/calendar.ics?v=2", "shown=1", "action=save" })
    check(c == 200 and Cal.feeds(plugin)[1].url:match("v=2$") and Cal.feeds(plugin)[1].enabled ~= false and Cal.feedName(Cal.feeds(plugin)[1]) == "Family",
        "Calendar: link replaced, shown again, its own name back")
    c, b = post("/link", { "id=" .. fid, "action=remove" })
    check(c == 200 and #Cal.feeds(plugin) == 0 and b:match("Removed"), "Calendar: link removed from the phone")
    c, b = post("/link", { "id=" .. fid, "action=remove" })
    check(c == 200 and b:match("isn&#39;t on the Kindle any more") or b:match("isn't on the Kindle any more"), "a link already gone: explained")
    -- books
    local libdir = plugin:libraryDir()
    local src = WORK .. "/upload-src.epub"
    os.execute("head -c 3500000 /dev/urandom > '" .. src .. "'")
    c, b = phone("--data-binary @'" .. src .. "' -H 'Content-Type: application/epub+zip' '" .. P .. "/upload?name=My%20Book.epub'")
    check(c == 200 and b:match("My Book.epub %(3.3 MB%) is on the Kindle"), "books: a 3.5 MB EPUB sent " .. tostring(b))
    local same = os.execute("cmp -s '" .. src .. "' '" .. libdir .. "/My Book.epub'")
    check(same == 0 or same == true, "books: the file arrived byte for byte (written as it arrived)")
    c, b = phone("--data-binary @'" .. src .. "' '" .. P .. "/upload?name=My%20Book.epub'")
    check(c == 200 and lfs.attributes(libdir .. "/My Book (2).epub", "size") == 3500000, "books: the same name again -> My Book (2).epub")
    c, b = phone("--data-binary 'MZ' '" .. P .. "/upload?name=setup.exe'")
    check(c == 415 and b:match("not a book"), "books: not a book format -> refused")
    c, b = phone("--data-binary @'" .. src .. "' '" .. P .. "/upload?name=..%2F..%2Fescape.epub'")
    check(c == 200 and lfs.attributes(libdir .. "/escape.epub", "mode") == "file", "books: a path in the name can't leave the GZreader folder")
    local leftovers = 0
    for e in lfs.dir(libdir) do if e:match("%.part$") then leftovers = leftovers + 1 end end
    check(leftovers == 0, "books: no partial files left")
    c, b = phone("'" .. P .. "'")
    check(b:match("✓ My Book.epub") and b:match("✓ My Book %(2%).epub"), "books received are listed on the page")
    -- disconnecting from the phone
    c, b = post("/memos/disconnect", {})
    check(c == 200 and not (plugin.store.memos or {}).token, "Notes: disconnected from the phone")
    c, b = post("/caldav/disconnect", {})
    check(c == 200 and not Cal.client(plugin):isConnected(), "Calendar: CalDAV account disconnected from the phone")
    local lg = io.open(WORK .. "/gzreader.log", "rb"); local ltxt = lg and lg:read("*a") or ""; if lg then lg:close() end
    check(not ltxt:find("demo-app-password", 1, true) and not ltxt:find("memos-test-token", 1, true) and not ltxt:find("abc123", 1, true),
        "no password, token or calendar link in the log")
    scr.on_cancel()
    check(closed and closed.notes and closed.calendar and closed.books == 3 and #UI.zmqs == 0 and Phone.session == nil,
        "Back on the Kindle: the page closes, the caller hears what changed")
    for _i, n in ipairs({ "My Book.epub", "My Book (2).epub", "escape.epub" }) do os.remove(libdir .. "/" .. n) end
    PS.new = orig_ps
    os.execute("kill $(cat " .. WORK .. "/memos3.pid) 2>/dev/null")
    os.execute("kill $(cat " .. WORK .. "/feeds.pid) 2>/dev/null")
    os.execute("kill $(cat " .. WORK .. "/caldav2.pid) 2>/dev/null")
end)()

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
