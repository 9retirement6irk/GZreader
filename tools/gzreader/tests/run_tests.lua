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
-- KOReader's JSON library (LuaJSON) decodes null as a function (a sentinel,
-- true in Lua) and encodes it back as null: so does this one, so code that
-- takes Grimmory's nulls for values fails here as on the Kindle.
do
    local dk = require("dkjson")
    local NULL = function() end
    local function out(v, seen)
        if v == NULL then return dk.null end
        if type(v) ~= "table" or v == dk.null then return v end
        seen = seen or {}
        if seen[v] then return seen[v] end
        local c = setmetatable({}, getmetatable(v))
        seen[v] = c
        for k, x in pairs(v) do c[k] = out(x, seen) end
        return c
    end
    preload("json", {
        null = NULL, util = { null = NULL },
        decode = function(str, pos) return dk.decode(str, pos, NULL) end,
        encode = function(v, state) return dk.encode(out(v), state) end,
    })
end
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
        if #UI.zmqs > 0 then for _i, z in ipairs(UI.zmqs) do z:waitEvent() end elseif server and server.server then server:waitEvent() end
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
-- (books fitted as picture books before they're opened: only in the picture book section)
rawset(_G, "GZ_NO_PB_PREPARE", true)
local PairServer = require("gzreader_pairserver")
PairServer.port = PORT + 10
require("gzreader_phone").PORT80 = false -- (the PIN part turns it on, on another port)
-- most sections read gzreader.log right after logging: lines written at once
-- (the log's own section turns buffering on)
require("gzreader_log").buffered = false

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
check(type(screen.pin) == "string" and screen.pin:match("^%d%d%d%d%d%d$") and screen.address and screen.address:match("^%d+%.%d+%.%d+%.%d+:%d+$"),
    "the screen shows the address to type (with the port when port 80 isn't used) and a 6-digit PIN")
code, body = phone("'" .. base .. "/'")
check(code == 200 and body:find('name="pin"', 1, true) and not body:find(token_path, 1, true), "typed address: asks for the PIN (no secret address in it)")
local wrong_pin = screen.pin == "000000" and "111111" or "000000"
code, body = phone("--data-urlencode 'pin=" .. wrong_pin .. "' '" .. base .. "/'")
check(code == 200 and body:find("That isn't the PIN", 1, true) and body:find("4 tries left", 1, true) and not body:find(token_path, 1, true), "wrong PIN: says so, 4 tries left")
code, body = phone("-i --data-urlencode 'pin=" .. screen.pin:sub(1, 3) .. " " .. screen.pin:sub(4) .. "' '" .. base .. "/'")
check(code == 303 and body:find("Location: " .. token_path .. "#grimmory", 1, true), "right PIN (spaces are fine): on to the page")
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
-- (and the look for books to lay out while charging: gzreader_layout.lua)
if require("gzreader_layout").loop then UI.scheduled[require("gzreader_layout").loop] = nil end
check(next(UI.scheduled) == nil, "expiry timer cancelled")

print("Setup from a browser: the Kindle's address and PIN")
do
    local Phone = require("gzreader_phone")
    Phone.PORT80 = PORT + 20
    PS.new = function(self, o) screen = o; return o end
    plugin:startQrPairing()
    local ip = screen.url:match("^http://([%d.]+):")
    check(#UI.zmqs == 2 and screen.address == ip .. ":" .. (PORT + 20), "a second port for the typed address (port 80 on a Kindle): " .. tostring(screen.address))
    local tpath = screen.url:match("(/phone/%x+)")
    local kbase = "http://127.0.0.1:" .. UI.zmqs[1].port
    code, body = phone("-i 'http://127.0.0.1:" .. (PORT + 20) .. "/'")
    check(code == 302 and body:find("Location: http://" .. ip .. ":" .. UI.zmqs[1].port .. "/", 1, true), "it sends the browser to the PIN page")
    local why
    screen.setPin = function(_s, _p, w) why = w end
    local wrong = screen.pin == "000000" and "111111" or "000000"
    for _i = 1, 5 do code, body = phone("--data-urlencode 'pin=" .. wrong .. "' '" .. kbase .. "/'") end
    check(body:find("The PIN is off after 5 wrong tries", 1, true) and why and why:match("PIN off"), "5 wrong PINs: the PIN is off (on the Kindle too)")
    code, body = phone("--data-urlencode 'pin=" .. screen.pin .. "' '" .. kbase .. "/'")
    check(code == 200 and not body:find(tpath, 1, true), "then not even the right PIN opens the page")
    code, body = phone("'" .. kbase .. tpath .. "'")
    check(code == 200 and body:find('id="diagnostics"', 1, true) and body:find(tpath .. '/log"', 1, true), "the QR code still works; Diagnostics tab while logging is on")
    code, body = phone("-i '" .. kbase .. tpath .. "/log'")
    check(code == 200 and body:find('Content-Disposition: attachment; filename="gzreader-log-', 1, true) and not body:find("hunter22", 1, true),
        "Download the log: the log as a file (no passwords)")
    plugin.store.logging_disabled = true
    code, body = phone("'" .. kbase .. tpath .. "'")
    local no_tab = code == 200 and not body:find('id="diagnostics"', 1, true)
    code = phone("'" .. kbase .. tpath .. "/log'")
    check(no_tab and code == 404, "diagnostics off: no tab, no log")
    plugin.store.logging_disabled = nil
    screen.on_cancel()
    check(#UI.zmqs == 0, "Back on the Kindle: both ports closed")
    Phone.PORT80 = false
    plugin.api:clearTokens()
end

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
check(not (body:match('<section id="grimmory".-</section>') or ""):match("Sign in with"), "server without SSO -> no SSO button")
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

print("A new login kept safe")
do
    local Api = require("gzreader_api")
    local path = os.tmpname()
    local st = { refresh_token = "R1", access_token = "A1", access_expires_at = 5 }
    -- a background process rotated R1 into R2, then GZreader restarted before saving it
    local child = { refresh_token = "R2", access_token = "A2", access_expires_at = 99 }
    check(Api.writePending(child, "R1", path), "the background process writes the new login at once")
    local f = io.open(path); local txt = f:read("*a"); f:close()
    check(not txt:find("R1", 1, true), "the file never holds the old token itself")
    check(Api.recoverPending(st, path) and st.refresh_token == "R2" and st.access_token == "A2" and st.access_expires_at == 99,
        "at start: the new login taken (it follows the saved one)")
    check(io.open(path) == nil, "and the file removed")
    Api.writePending({ refresh_token = "R9" }, "R7", path)
    local st2 = { refresh_token = "R5" }
    check(not Api.recoverPending(st2, path) and st2.refresh_token == "R5", "not from these tokens (a new login since): left alone")
    check(not Api.writePending({ refresh_token = "R1" }, "R1", path), "nothing new: nothing written")
    os.remove(path)
end

print("A stopped background request keeps the login it renewed")
;(function()
    local Api = require("gzreader_api")
    local Async = require("gzreader_async")
    local saved_sync = Async.sync
    Async.sync = false
    local saved_flag = 0
    local fake = { store = { refresh_token = "R1", access_token = "A1" }, writePending = Api.writePending,
        recoverPending = Api.recoverPending, dropPending = Api.dropPending,
        on_change = function() saved_flag = saved_flag + 1 end }
    os.remove(require("datastorage"):getSettingsDir() .. "/gzreader_tokens.pending")
    local result
    Async.run(fake, function(api)
        -- (the background process renews the login, keeps it on disk, then hangs)
        api.store.refresh_token, api.store.access_token = "R2", "A2"
        api.writePending(api.store, "R1")
        require("socket").sleep(6)
        return true
    end, function(...) result = { ... } end, "slow", { timeout = 1 })
    runLoop(function() return result ~= nil end, 15)
    check(result and result[2] == "timeout" and fake.store.refresh_token == "R2" and saved_flag == 1,
        "stopped after renewing: the new login is kept, not lost (" .. tostring(fake.store.refresh_token) .. ")")
    Async.sync = saved_sync
end)()

print("While a book opens, background processes wait")
;(function()
    local Async = require("gzreader_async")
    local saved_sync = Async.sync
    Async.sync = false
    local Log = require("gzreader_log")
    local orig_info, logged = Log.info, {}
    Log.info = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    local function state(pid)
        local f = io.open("/proc/" .. pid .. "/stat", "rb")
        if not f then return nil end
        local st = f:read("*a"):match("%) (%a)")
        f:close()
        return st
    end
    local function pauseNoTimer(reason)
        Async.pause(reason)
        if Async.paused then UI.scheduled[Async.paused.timer] = nil end -- (the stand-in UIManager runs everything at once)
    end
    -- a request running: paused, not stopped by its time limit, then finishes
    local res_a
    Async.run(nil, function() require("socket").sleep(1); return "a" end, function(r, e) res_a = r or e end, "calendar: sync", { timeout = 2 })
    local pid = next(Async.running)
    check(pid ~= nil, "the running request is known (pid " .. tostring(pid) .. ")")
    pauseNoTimer("a book opens")
    runLoop(function() return state(pid) == "T" end, 2)
    check(state(pid) == "T", "a book opens: the running request is paused (state " .. tostring(state(pid)) .. ")")
    runLoop(function() return res_a ~= nil end, 3.5)
    check(res_a == nil, "while paused it doesn't finish, and its 2 s limit doesn't stop it (3.5 s)")
    -- a request asked for meanwhile waits
    local res_b
    Async.run(nil, function() return "b" end, function(r) res_b = r end, "later")
    check(#Async.queue == 1, "a request asked for while the book opens waits")
    Async.resume("the book is open")
    runLoop(function() return res_a ~= nil and res_b ~= nil end, 10)
    check(res_a == "a" and res_b == "b", "the book is open: the paused one carries on and the waiting one runs ("
        .. tostring(res_a) .. ", " .. tostring(res_b) .. ")")
    check(next(Async.running) == nil, "and nothing is left running")
    -- a book that never finishes opening: carry on anyway
    pauseNoTimer("a book opens")
    local timer = Async.paused and Async.paused.timer
    local res_c
    Async.run(nil, function() return "c" end, function(r) res_c = r end, "later")
    runLoop(function() return false end, 0.3)
    check(res_c == nil and timer ~= nil, "held: nothing starts")
    timer()
    runLoop(function() return res_c ~= nil end, 10)
    check(res_c == "c" and Async.paused == nil, "after " .. Async.PAUSE_MAX .. " s without a page: carries on")
    Log.info = orig_info
    local log = table.concat(logged, "\n")
    check(log:find("async: paused 1 background process(es) while a book opens", 1, true)
        and log:find("async: resumed after", 1, true), "the log says what was paused and for how long")
    Async.sync = saved_sync
end)()

print("Library browsing")
local Browser = require("gzreader_browser")
local b = Browser:new(plugin)
b:show()
b:openPaged("All books", { sort = "title", dir = "asc" })
local items = b.menu.item_table
local audiobooks = 0
for _, it in ipairs(items) do if it.book and it.book.primaryFileType == "AUDIOBOOK" then audiobooks = audiobooks + 1 end end
check(audiobooks == 0, "audiobooks filtered out")
check(#items == 27 and items[1].text == "Search Grimmory…" and items[27].text:match("Load more"), "search, first page + 'Load more'")
items[27].callback()
check(#b.menu.item_table == 33 and not b.menu.item_table[33].text:match("Load more"), "second page appended, no more pages")
check(b.menu.page == 2, "Load more: on the page with the first new book")
do -- a big library: only MAX_PAGES pages kept, "Earlier books" brings the first back
    local saved = Browser.MAX_PAGES
    Browser.MAX_PAGES = 1
    b = Browser:new(plugin); b:show()
    b:openPaged("All books", { sort = "title", dir = "asc" })
    b.menu.item_table[27].callback()
    local t = b.menu.item_table
    check(#t == 9 and t[2].text:match("^Earlier books %(page 1 of 2%)") and t[3].book and t[3].book.title == "Book 26",
        "Load more past MAX_PAGES: the first page let go, 'Earlier books' instead " .. tostring(t[2] and t[2].text))
    t[2].callback()
    t = b.menu.item_table
    check(#t == 27 and t[2].book and t[2].book.title == "Book 01" and t[27].text:match("Load more %(page 2 of 2%)"),
        "Earlier books: the first page back, the second let go")
    Browser.MAX_PAGES = saved
    local slimmed = b.menu.item_table[2].book
    check(slimmed.id == 1 and slimmed.title == "Book 01" and slimmed.primaryFileType == "EPUB" and slimmed.fileSizeKb == 300
        and slimmed.authors and slimmed.libraryId and slimmed.thumbnailUrl == nil,
        "book items keep only what GZreader uses")
end

print("Grimmory tab search")
do
    b = Browser:new(plugin); b:show()
    local root = b:rootItems()
    check(root[1].text == "Search Grimmory…", "search is first in the Grimmory tab")
    b:search("book 1")
    local t = b.menu.item_table
    local titles = {}
    for _i, it in ipairs(t) do if it.book then titles[#titles + 1] = it.book.title end end
    check(b.menu.title == "Search: book 1" and t[1].text == "Search again…" and table.concat(titles, ",")
        == "Book 10,Book 11,Book 12,Book 13,Book 14,Book 15,Book 16,Book 17,Book 18,Book 19", "search: readable matches A–Z " .. table.concat(titles, ","))
    local last
    for _, e in ipairs(json.decode(ctl("/state")).log) do if e[2]:match("^/api/v1/app/books%?") then last = e[2] end end
    check(last and last:match("search=book") and last:match("fileType=EPUB"), "search: Grimmory's book list (readable formats, paged) " .. tostring(last))
    b:search("author 2")
    local n = 0
    for _i, it in ipairs(b.menu.item_table) do if it.book then n = n + 1 end end
    check(n > 0, "search finds authors too")
    b:search("nothing like this")
    t = b.menu.item_table
    check(#t == 2 and t[2].text == "No books found containing “nothing like this”" and t[2].select_enabled == false
        and t[2].gz_kind == "nothing_found", "search: nothing found (says what was searched for; marked for the empty ledges)")
    b:search("nothing like this", { title = "fiction", params = { libraryId = 2, sort = "title", dir = "asc" } })
    t = b.menu.item_table
    check(#t == 2 and t[2].gz_kind == "nothing_found" and t[2].text == "No books found containing “nothing like this”",
        "search in a library that found nothing: the same")
    -- in a library: the library's own search
    b:openPaged("fiction", { libraryId = 2, sort = "title", dir = "asc" })
    t = b.menu.item_table
    check(t[1].text == "Search in fiction…", "a library's list: search in it")
    b:search("book", { title = "fiction", params = { libraryId = 2, sort = "title", dir = "asc" } })
    local ok_lib, m = true, 0
    for _i, it in ipairs(b.menu.item_table) do if it.book then m = m + 1; ok_lib = ok_lib and it.book.libraryId == 2 end end
    check(b.menu.title == "fiction: “book”" and m > 0 and ok_lib, "search in a library: its books only")
    -- an older Grimmory that ignores search= in its book list: its own search endpoint
    ctl("/set?old_search=true")
    b:search("book 2")
    titles = {}
    for _i, it in ipairs(b.menu.item_table) do if it.book then titles[#titles + 1] = it.book.title end end
    check(#titles > 0 and not table.concat(titles, ","):match("Book 1"), "older Grimmory: falls back to its search endpoint " .. table.concat(titles, ","))
    ctl("/set?old_search=false")
end

print("Grimmory tab back arrow (touch)")
do
    -- the title's back arrow calls a method KOReader's Menu really has
    -- (1.12.2: menu:onReturn(), gone from KOReader; touch Kindles crashed)
    local src = io.open(PLUGIN .. "/gzreader_browser.lua"):read("*a")
    local method = src:match("back_callback = nested and function%(%) menu:([%w_]+)%(%)")
    local menu_src = io.open(PLUGIN .. "/../../frontend/ui/widget/menu.lua"):read("*a")
    check(method and menu_src:find("function Menu:" .. method .. "(", 1, true), "back arrow: Menu:" .. tostring(method) .. " exists")
end

print("Covers kept in memory")
do
    local Covers = require("gzreader_covers")
    local frees = 0
    local function fake(key) Covers.memory[key] = { bb = { free = function() frees = frees + 1 end }, used = 0 } end
    Covers.release(); Covers.tick = 0; Covers.page_start = 0
    local saved = Covers.MEMORY
    Covers.MEMORY = 3
    -- the page being drawn: three covers already used on it
    Covers.beginPage()
    for i = 1, 3 do fake("p" .. i); Covers.tick = Covers.tick + 1; Covers.memory["p" .. i].used = Covers.tick end
    local dir = Covers.dir()
    local jpg = io.open(dir .. "/77.jpg", "wb"); jpg:write("x"); jpg:close()
    package.loaded["ui/renderimage"] = { renderImageData = function() return { getWidth = function() return 10 end,
        getHeight = function() return 10 end, free = function() end } end, scaleBlitBuffer = function(_, bb) return bb end }
    check(Covers.image(77, nil, 10, 10) ~= nil and frees == 0 and Covers.memory.p1 and Covers.memory.p2 and Covers.memory.p3,
        "a cover on the page being drawn is never let go")
    Covers.beginPage()
    Covers.image(78, nil, 10, 10) -- (not on the Kindle: nil)
    jpg = io.open(dir .. "/79.jpg", "wb"); jpg:write("x"); jpg:close()
    Covers.image(79, nil, 10, 10)
    check(frees == 1 and Covers.memory.p1 == nil and Covers.memory.p2, "next page: the least recently used goes")
    Covers.MEMORY = saved
    package.loaded["ui/renderimage"] = nil
    os.remove(dir .. "/77.jpg"); os.remove(dir .. "/79.jpg")
    Covers.release()
end
b:openSimple("continue-reading", "Continue reading")
check(#b.menu.item_table == 5, "continue reading list (audiobook dropped)")
check(b.menu.item_table[1].mandatory:match("13%%"), "progress shown")
do -- Paused books: the app's /continue-reading leaves them out, the web shows them
    ctl("/set?cr_paused=true")
    local list = plugin.api:continueReading(30)
    local ids = {}
    for _i, bk in ipairs(list or {}) do ids[#ids + 1] = bk.id end
    check(list and #list == 6 and ids[1] == 7, "continue reading: Paused books too, most recently read first (" .. table.concat(ids, ",") .. ")")
    b:openSimple("continue-reading", "Continue reading")
    check(#b.menu.item_table == 6, "continue reading list: not empty when the app's list is")
    ctl("/set?cr_paused=false")
    local saved = plugin.api.listBooks
    plugin.api.listBooks = function() return nil, "http_400" end   -- an older Grimmory
    list = plugin.api:continueReading(30)
    plugin.api.listBooks = saved
    check(list and #list == 6, "continue reading: the app's list alone if the book list can't filter")
    b:openSimple("continue-reading", "Continue reading")
end

print("Catalog tab: Books, Audiobooks and Music pages")
;(function()
    local Catalog = require("gzreader_catalog")
    check(table.concat(Catalog.sections(true), ",") == "books,audiobooks,music" and table.concat(Catalog.sections(false), ",") == "books",
        "pages: Books, Audiobooks, Music with a speaker; Books alone without")
    local all = Catalog.sections(true)
    check(Catalog.step(all, "books", 1) == "audiobooks" and Catalog.step(all, "music", -1) == "audiobooks"
        and Catalog.step(all, "music", 1) == "books" and Catalog.step(all, "books", -1) == "music" and Catalog.step(all, "audiobooks", 0) == "audiobooks"
        and Catalog.step({ "books" }, "books", 1) == nil and Catalog.step({ "books" }, "books", -1) == nil,
        "pages: next and before, round the ends (after Music: Books; before Books: Music); nothing to turn to with one page")
    local p1, p2, p3 = Catalog.stripParts(all, "books"), Catalog.stripParts(all, "audiobooks"), Catalog.stripParts(all, "music")
    check(p1.left == "‹ Music" and p1.dots == "● ○ ○" and p1.right == "Audiobooks ›" and p2.left == "‹ Books" and p2.dots == "○ ● ○"
        and p2.right == "Music ›" and p3.left == "‹ Audiobooks" and p3.right == "Books ›" and Catalog.stripParts({ "books" }, "books") == nil,
        "the strip under the title: the page before, a dot a page, the next page, round the ends (none with one page)")
    check(Catalog.hit(p1, 590, 0, 600) == 1 and Catalog.hit(p1, 10, 0, 600) == -1 and Catalog.hit(p2, 10, 0, 600) == -1
        and Catalog.hit(p2, 300, 0, 600) == nil and Catalog.hit(p3, 590, 0, 600) == 1, "the strip: a tap on either side turns that way")
    check(Catalog.title("books") == "Books" and Catalog.title("audiobooks") == "Audiobooks" and Catalog.title("music") == "Music",
        "the title says which page")
    local saved_audio = require("gzreader_touch").audio
    require("gzreader_touch").audio = function() return true end
    local cb = Browser:new(plugin)
    cb:show()
    local m = cb.menu
    check(cb.section == "books" and m.title == "Books" and m.item_table.gz_catalog == "books" and m.item_table[1].gz_id == "search"
        and m.item_table.gz_root, "the Catalog opens on Books (the bookshop)")
    local last = m.item_table[#m.item_table]
    check(last.gz_id == "audiobooks" and last.text == "Audiobooks", "the Books list's last line is the Audiobooks page (its letter on keyboard Kindles)")
    last.callback()
    check(cb.section == "audiobooks" and #m.item_table_stack == 0, "…and turns to it (a page, not a list inside Books)")
    cb:openSection("books")
    m.page, m.page_num = 1, 1
    m:onNextPage()
    check(cb.section == "audiobooks" and m.title == "Audiobooks" and m.item_table.gz_catalog == "audiobooks"
        and m.item_table[4].text == "All audiobooks", "a swipe left (next page) on Books: the Audiobooks page")
    m:onNextPage()
    local music = m.item_table
    check(cb.section == "music" and m.title == "Music" and music.gz_catalog == "music" and #music > 0 and not music.gz_root,
        "and again: the Music page (Plex; not drawn as the bookshop)")
    local plain = { section = "audiobooks", api = plugin.api } -- (signed in)
    check(Browser.rootItems(plain)[4].text == "All audiobooks" and Browser.rootItems(plain).gz_catalog == "audiobooks",
        "the Audiobooks page: All audiobooks")
    m:onNextPage()
    check(cb.section == "books" and m.item_table[1].gz_id == "search" and m.title == "Books", "past Music (a swipe left): Books again")
    m:onPrevPage()
    check(cb.section == "music" and m.title == "Music", "before Books (a swipe right): Music")
    m:onPrevPage(); m:onPrevPage()
    check(cb.section == "books" and m.item_table[1].gz_id == "search", "a swipe right goes back, to Books")
    -- a page with more than one page of its own turns those first
    m.page, m.page_num = 1, 2
    m:onNextPage()
    check(cb.section == "books", "a page's own second page comes first (the Menu's own turn)")
    m.page, m.page_num = 1, 1
    m:onNextPage()
    cb:push("All audiobooks", { { text = "Book 31" } })
    m:onNextPage()
    check(cb.section == "audiobooks" and #m.item_table_stack == 1 and m.item_table[1].text == "Book 31",
        "inside a list (All audiobooks), page turns stay the list's")
    local b2 = Browser:new(plugin)
    b2:show({ section = "music" })
    check(b2.section == "music" and b2.menu.title == "Music", "the Catalog can open on another page")
    require("gzreader_touch").audio = function() return false end
    local b3 = Browser:new(plugin)
    b3:show({ section = "music" })
    check(b3.section == "books" and b3.menu.onNextPage and not b3:turnSection(1), "no speaker: Books only, nothing to turn to")
    -- the Audiobooks tab: the Catalog on its Audiobooks page alone, that tab underlined
    require("gzreader_touch").audio = function() return true end
    local at = Browser:new(plugin)
    at:show({ section = "audiobooks", tab_id = "ct_audiobooks", only = true })
    local am = at.menu
    am.page, am.page_num = 1, 1
    am:onNextPage(); am:onPrevPage()
    check(at.section == "audiobooks" and am._gz_navbar_tab_id == "ct_audiobooks" and am.title == "Audiobooks"
        and table.concat(at:sections(), ",") == "audiobooks" and not at:turnSection(1) and not at:turnSection(-1),
        "the Audiobooks tab: the Audiobooks page alone (no Books or Music to swipe to), its tab underlined")
    local cat = Browser:new(plugin)
    cat:show()
    check(cat.menu._gz_navbar_tab_id == "ct_grimmory" and #cat:sections() == 3, "the Catalog tab: its own tab, every page")
    local opened_with
    local saved_show = Browser.show
    Browser.show = function(_s, o) opened_with = o end
    plugin:onShowGzAudiobooks()
    Browser.show = saved_show
    check(type(opened_with) == "table" and opened_with.section == "audiobooks" and opened_with.tab_id == "ct_audiobooks" and opened_with.only,
        "the tab's action opens the Catalog that way")
    require("gzreader_touch").audio = function() return false end
    opened_with, captured.info = nil, nil
    Browser.show = function(_s, o) opened_with = o end
    plugin:onShowGzAudiobooks()
    Browser.show = saved_show
    check(opened_with == nil and tostring(captured.info):match("no speaker or headphone jack"),
        "a Kindle without audio: the tab says it can't play audiobooks (no Catalog page)")
    require("gzreader_touch").audio = saved_audio
    -- ZenOS's config: the tab's label becomes Catalog once, unless you named it yourself
    local mf = io.open(arg[1] .. "/../zenos.koplugin/config/manager.lua", "rb")
    local msrc = mf and mf:read("*a") or ""
    if mf then mf:close() end
    local from = msrc:find("if cfg._meta.gz_catalog_label_migrated ~= true then", 1, true)
    local to = from and select(2, msrc:find("cfg._meta.gz_catalog_label_migrated = true%s+changed = true%s+end", from))
    local migrate = from and to and load("return function(cfg) local changed = false\n" .. msrc:sub(from, to) .. "\nreturn changed end", "catalog migration", "t", { type = type, ipairs = ipairs })()
    local function cfgWith(label)
        return { _meta = {}, navbar = { custom_tabs = { { id = "ct_grimmory", label = label }, { id = "ct_notes", label = "Notes" } } } }
    end
    local c1, c2, c3 = cfgWith("Grimmory"), cfgWith("My books"), cfgWith(nil)
    local ok_m = migrate and migrate(c1) and migrate(c2) and migrate(c3)
    local c4 = cfgWith("Grimmory")
    c4._meta.gz_catalog_label_migrated = true
    check(ok_m and c1.navbar.custom_tabs[1].label == "Catalog" and c2.navbar.custom_tabs[1].label == "My books"
        and c3.navbar.custom_tabs[1].label == "Catalog" and c1.navbar.custom_tabs[2].label == "Notes"
        and migrate(c4) == false and c4.navbar.custom_tabs[1].label == "Grimmory",
        "the tab's label: Grimmory becomes Catalog once; a name of your own stays")
    local afrom = msrc:find("if cfg._meta.gz_audiobooks_tab_migrated ~= true then", 1, true)
    local ato = afrom and select(2, msrc:find("cfg._meta.gz_audiobooks_tab_migrated = true%s+changed = true%s+end", afrom))
    local amig = afrom and ato and load("return function(cfg) local changed = false\n" .. msrc:sub(afrom, ato) .. "\nreturn changed end",
        "audiobooks tab migration", "t", { type = type, ipairs = ipairs, table = table })()
    local acfg = { _meta = {}, navbar = { custom_tabs = { { id = "ct_grimmory" } }, show_tabs = {}, tab_order = { "home", "ct_grimmory" } } }
    local a1 = amig and amig(acfg)
    acfg._meta.gz_audiobooks_tab_migrated = nil
    amig(acfg)
    local n_ab = 0
    for _i, t in ipairs(acfg.navbar.custom_tabs) do if t.id == "ct_audiobooks" then n_ab = n_ab + 1 end end
    check(a1 and n_ab == 1 and acfg.navbar.show_tabs.ct_audiobooks == false and table.concat(acfg.navbar.tab_order, ",") == "home,ct_grimmory,ct_audiobooks",
        "an older config gets the Audiobooks tab listed, off, once")
end)()

print("Catalog: the Audiobooks page (search, All audiobooks, Authors, Shelves, Series)")
;(function()
    local saved_audio = require("gzreader_touch").audio
    require("gzreader_touch").audio = function() return true end
    local g = Browser.groupAudiobooks({ { id = 1, authors = { "A", "B" }, seriesName = "S" }, { id = 2, authors = { "A" }, seriesName = "S" },
        { id = 3, authors = { "C" } } })
    check(g.authors.A == 2 and g.authors.B == 1 and g.authors.C == 1 and g.series.S.count == 2
        and table.concat(g.series.S.authors, ",") == "A,B" and next(Browser.groupAudiobooks(nil).authors) == nil,
        "audiobooks grouped by author and series")
    local ab = Browser:new(plugin)
    ab:show({ section = "audiobooks" })
    local m = ab.menu
    local ids = {}
    for _i, it in ipairs(m.item_table) do ids[#ids + 1] = it.gz_id end
    local ab_card = m.item_table[#m.item_table]
    check(table.concat(ids, ",") == "ab_search,ab_continue,ab_recent,ab_all,ab_authors,ab_shelves,ab_series,ab_account"
        and m.item_table[1].gz_action == "search" and m.item_table[4].gz_kind == "section" and m.item_table[4].gz_contents == "tapes"
        and m.item_table.gz_root and not m.item_table.gz_signed_out and ab_card.text == "Grimmory" and ab_card.gz_contents == "none"
        and ab_card.mandatory == plugin.store.username .. " · " .. plugin.store.server:gsub("^https?://", ""),
        "the page: search, Continue listening, Recently added, then All audiobooks, Authors, Shelves, Series and the Grimmory card (no On this Kindle) "
        .. table.concat(ids, ",") .. " / " .. tostring(ab_card.mandatory))
    local function abItem(id) for _i, it in ipairs(m.item_table) do if it.gz_id == id then return it end end end
    local saved_w = {}
    local widget_mods = { "ui/widget/container/inputcontainer", "ui/widget/container/widgetcontainer", "ui/gesturerange", "ui/font", "ffi/blitbuffer" }
    for _i, wm in ipairs(widget_mods) do
        saved_w[wm] = package.loaded[wm]
        if type(saved_w[wm]) ~= "table" then package.loaded[wm] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    local Views = require("gzreader_shopviews")
    for _i, wm in ipairs(widget_mods) do package.loaded[wm] = saved_w[wm] end
    local Shop = require("gzreader_bookshop")
    local ps = Shop.pageSpec("audiobooks")
    local comp = {}
    for _i, c in ipairs(ps.compartments) do comp[#comp + 1] = tostring(c.id) end
    check(ps.ledges[1].id == "ab_continue" and ps.ledges[1].label == "Continue listening" and ps.ledges[2].id == "ab_recent"
        and table.concat(comp, ",") == "ab_all,ab_authors,ab_shelves,ab_series,ab_account" and ps.cover_kind == "audiobook"
        and Shop.pageSpec("books").ledges[1].id == "continue" and Views.cardOf(m.item_table[5]) == m.item_table[5].mandatory,
        "the Bookshelf view: the books' shop, with Continue listening and Recently added ledges, then a compartment each")
    -- Continue listening: what you've listened to on the Kindle first
    local AB = require("gzreader_audiobook")
    local saved_load, saved_store = AB.load, plugin.store.audiobooks
    AB.load = function(_p, id) if tostring(id) == "41" or tostring(id) == "42" then return { files = {}, tracks = {}, durationMs = 1000000 } end end
    plugin.store.audiobooks = { [41] = { title = "Older", pos_ms = 1000, updated = 10 }, [42] = { title = "Newer", pos_ms = 500, updated = 20 },
        [43] = { title = "Gone", pos_ms = 5, updated = 30 } }
    local lis = Shop.listening(plugin)
    check(#lis == 2 and lis[1].title == "Newer" and lis[2].title == "Older" and lis[1].primaryFileType == "AUDIOBOOK",
        "Continue listening: the Kindle's audiobooks in progress, latest first (not ones whose audio is gone)")
    AB.load, plugin.store.audiobooks = saved_load, saved_store
    check(Views.cardOf({ gz_kind = "author", gz_audio = true, gz_count = 2 }) == "2 audiobooks"
        and Views.cardOf({ gz_kind = "collection", gz_audio = true, gz_count = 1 }) == "1 audiobook"
        and Views.kindOf({ { gz_kind = "collection" } }) == "bay", "an author's or series' card counts audiobooks")
    local function lastRequest(pat)
        local last
        for _i, e in ipairs(json.decode(ctl("/state")).log) do if e[2]:match(pat) then last = e[2] end end
        return last
    end
    ab:openAudioAuthors()
    local names = {}
    for _i, it in ipairs(m.item_table) do names[#names + 1] = it.text .. "=" .. tostring(it.gz_count) end
    check(table.concat(names, ",") == "Audio Author=2,Author 1=1" and m.item_table[1].gz_audio and m.item_table[1].gz_contents == "tapes",
        "Authors: the audiobooks' authors only, with how many " .. table.concat(names, ","))
    m.item_table[1].callback()
    local books = {}
    for _i, it in ipairs(m.item_table) do if it.book then books[#books + 1] = it.book.title .. ":" .. tostring(it.cover_kind) end end
    local req = lastRequest("^/api/v1/app/books%?")
    check(table.concat(books, ",") == "Book 32:audiobook,Book 33:audiobook" and req and req:match("fileType=AUDIOBOOK") and req:match("authors=Audio")
        and m.item_table[1].text == "Search in Audio Author…", "an author: their audiobooks (Grimmory's list, audiobooks only) " .. tostring(req))
    ab:openSection("audiobooks")
    check(abItem("ab_all").mandatory == "3 audiobooks" and abItem("ab_authors").mandatory == "2 · A–Z" and abItem("ab_series").mandatory == "2 series",
        "the page's cards count what's known (from the list Authors fetched)")
    ab:openAudioSeries()
    local series = {}
    for _i, it in ipairs(m.item_table) do series[#series + 1] = it.text end
    check(table.concat(series, ",") == "Audio Only Saga — Audio Author,Saga / Part One — Author 1", "Series: the audiobooks' series " .. table.concat(series, ","))
    m.item_table[1].callback()
    req = lastRequest("^/api/v1/app/books%?")
    check(req and req:match("series=Audio") and req:match("fileType=AUDIOBOOK") and req:match("sort=seriesNumber"), "a series: in series order " .. tostring(req))
    ab:openSection("audiobooks")
    abItem("ab_shelves").callback()
    check(m.title == "Shelves" and m.item_table[1].gz_kind == "shelf" and m.item_table[1].gz_audio, "Shelves: your shelves, each opening to its audiobooks")
    m.item_table[1].callback()
    req = lastRequest("^/api/v1/app/books%?")
    check(req and req:match("fileType=AUDIOBOOK") and (req:match("shelfId=") or req:match("magicShelfId=")), "a shelf: the audiobooks on it " .. tostring(req))
    ab:openSection("audiobooks")
    ab:search("saga", Browser.audioScope())
    local found = {}
    for _i, it in ipairs(m.item_table) do if it.book then found[#found + 1] = it.book.title end end
    req = lastRequest("^/api/v1/app/books%?")
    check(m.title == "Audiobooks: “saga”" and #found > 0 and req:match("fileType=AUDIOBOOK") and req:match("search=saga"),
        "Search audiobooks: audiobooks only " .. table.concat(found, ","))
    ab:search("zzz", Browser.audioScope())
    check(m.item_table[#m.item_table].text == "No audiobooks found containing “zzz”", "a search that finds nothing says so")
    -- an author's audiobooks and books aren't the same saved list
    local Cache = require("gzreader_listcache")
    check(Cache.key("paged-audio", { authors = "X" }) ~= Cache.key("paged", { authors = "X" }), "saved lists: audiobooks and books kept apart")
    require("gzreader_touch").audio = saved_audio
end)()

print("Catalog: not signed in to Grimmory (it opens all the same)")
;(function()
    local saved_audio = require("gzreader_touch").audio
    require("gzreader_touch").audio = function() return true end
    local out_api = setmetatable({ isPaired = function() return false end }, { __index = plugin.api })
    local function idsOf(list) local t = {} for _i, it in ipairs(list) do t[#t + 1] = tostring(it.gz_id) end return table.concat(t, ",") end
    local b = Browser:new(plugin)
    b.api = out_api
    b.section = "books"
    local items = b:rootItems()
    check(items.gz_root and items.gz_signed_out and idsOf(items) == "search,grimmory,audiobooks"
        and items[1].text == "Sign in to Grimmory to browse the catalog" and items[2].text == "Grimmory" and items[2].mandatory == "signed out",
        "Books, not signed in: the shelves empty, the slip says to sign in, the Grimmory card " .. idsOf(items) .. " / " .. tostring(items[2].mandatory))
    local saved_user = plugin.store.username
    plugin.store.username = nil
    check(Browser.grimmoryItem(b, "grimmory").mandatory == "not signed in", "…never signed in: \"not signed in\"")
    plugin.store.username = saved_user
    b.section = "audiobooks"
    items = b:rootItems()
    check(items.gz_signed_out and idsOf(items) == "ab_search,ab_account" and items[1].text == "Sign in to Grimmory to browse the catalog"
        and items[2].text == "Grimmory", "Audiobooks (Grimmory's), not signed in: the same " .. idsOf(items))
    -- nothing saved from the account before is shown
    -- (saved under a server of its own: the other blocks' saved lists untouched)
    local saved_server = plugin.store.server
    plugin.store.server = "https://signed-out.example.com"
    local Cache = require("gzreader_listcache")
    local key = tostring(plugin.store.server) .. "|" .. tostring(plugin.store.username) .. "|"
    Cache.put(key .. "simple:continue-reading", { { id = 1, title = "Kept", primaryFileType = "EPUB" } })
    Cache.put(key .. "shop:ab_recent", { { id = 2, title = "Kept audio", primaryFileType = "AUDIOBOOK" } })
    local Shop = require("gzreader_bookshop")
    local st, ast = Shop.lists(b, "books"), Shop.lists(b, "audiobooks")
    check(st.fetched and st.continue == nil and st.recent == nil and ast.ab_recent == nil and ast.ab_continue == nil and not st.loading,
        "not signed in: the shelves stay empty (no saved lists from before)")
    local signed_in = Browser:new(plugin)
    signed_in._shop = { asked = true } -- (no fetch)
    check(#(Shop.lists(signed_in, "books").continue or {}) == 1, "signed in: the saved list as before")
    plugin.store.server = saved_server
    -- the Grimmory card's list
    local pushed
    b.push = function(_s, title, list) pushed = { title = title, list = list } end
    b:openGrimmory()
    local texts = {}
    for _i, it in ipairs(pushed and pushed.list or {}) do texts[#texts + 1] = it.text end
    local tx = table.concat(texts, " | ")
    check(pushed and pushed.title == "Grimmory" and tx:find("Signed out of " .. plugin.store.username .. " at " .. (plugin.store.server:gsub("^https?://", "")), 1, true) and tx:find("Connect from your browser (QR code)", 1, true)
        and tx:find("Connect by typing", 1, true) and tx:find("Copy from another GZreader", 1, true) and not tx:find("Rebuild", 1, true),
        "the Grimmory card, not signed in: the ways to sign in " .. tx)
    signed_in.push = b.push
    signed_in:openGrimmory()
    texts = {}
    for _i, it in ipairs(pushed.list) do texts[#texts + 1] = it.text end
    tx = table.concat(texts, " | ")
    check(tx:find("Signed in as " .. plugin.store.username .. " at ", 1, true) and tx:find("Rebuild library", 1, true)
        and tx:find("Reconnect from your browser (QR code)", 1, true), "the Grimmory card, signed in: the account " .. tx)
    -- the Catalog opens, signed out, from its tab (it used to ask to connect instead)
    local Net = require("gzreader_net")
    local saved_run, saved_api = Net.run, plugin.api
    Net.run = function() end
    plugin.api = out_api
    Browser.current = nil
    plugin:onShowGrimmoryLibrary()
    local open = Browser.current
    check(open and open.menu and open.menu.item_table.gz_signed_out and open.section == "books", "the Catalog tab opens without Grimmory")
    -- signed in while it shows: its page again
    plugin.api = saved_api
    if open then open.api = saved_api end
    Browser.signInChanged()
    check(open and not open.menu.item_table.gz_signed_out and idsOf(open.menu.item_table):match("^search,continue,recent,"),
        "signed in while it's open: the page with Grimmory's shelves")
    if open then open.closed = true end
    Net.run = saved_run
    local msrc = io.open(PLUGIN .. "/main.lua"):read("*a")
    local bsrc = io.open(PLUGIN .. "/gzreader_bookshop.lua"):read("*a")
    check(msrc:find("B.signInChanged", 1, true) and msrc:find("function Grimmory:afterLogin", 1, true) < msrc:find("B.signInChanged", 1, true),
        "any sign-in (QR, typing, SSO) shows the Catalog's page again")
    -- the account card: the last compartment (bottom right), whatever else is there
    local function arranged(section, present, fixed)
        local t = {}
        for _i, c in ipairs(Shop.arrange(Shop.pageSpec(section).compartments, function(id) return present[id] end, fixed, 6)) do t[#t + 1] = c.id or "-" end
        return table.concat(t, ",")
    end
    local all_ab = { ab_all = true, ab_authors = true, ab_shelves = true, ab_series = true, ab_account = true }
    check(arranged("books", {}, true) == "all,libraries,shelves,authors,series,grimmory"
        and arranged("audiobooks", all_ab, false) == "ab_all,ab_authors,ab_shelves,ab_series,-,ab_account"
        and arranged("audiobooks", { ab_all = true, ab_authors = true, ab_account = true }, false) == "ab_all,ab_authors,-,-,-,ab_account"
        and arranged("audiobooks", {}, true) == "ab_all,ab_authors,ab_shelves,ab_series,-,ab_account"
        and arranged("music", { mu_playlists = true, mu_albums = true, mu_artists = true, mu_account = true }, false) == "mu_playlists,mu_albums,mu_artists,-,-,mu_account"
        and arranged("music", { mu_playlists = true, mu_albums = true, mu_artists = true, mu_now = true, mu_account = true }, false)
            == "mu_playlists,mu_albums,mu_artists,mu_now,-,mu_account"
        and Shop.pageSpec("music").compartments[5].kind == "account" and Shop.pageSpec("audiobooks").compartments[5].kind == "account",
        "the Grimmory and Plex cards: always the bottom-right compartment, the whole of it")
    check(bsrc:find("by.search or by.ab_search or by.mu_search", 1, true),
        "the Bookshelf view's slip is each page's own search line (the Audiobooks and Music slips did nothing)")
    require("gzreader_touch").audio = saved_audio
end)()

print("Catalog: the Music page (CD cases on the shelves)")
;(function()
    local Tab = require("gzreader_musictab")
    local e1 = Tab.entry({ text = "A" }, { type = "album", key = "201", title = "A", artist = "X", year = 2020, thumb = "/t/201" })
    local e2 = Tab.entry({ text = "P" }, { type = "playlist", key = "9", title = "P", count = 12 })
    local e3 = Tab.entry({ text = "X" }, { type = "artist", key = "5", title = "X" })
    local e4 = Tab.entry({ text = "T" }, { type = "track", key = "7", title = "T" })
    check(e1.gz_music.key == "201" and e1.gz_music.thumb == "/t/201" and e2.gz_music.type == "playlist" and e3.gz_kind == "artist"
        and e3.gz_contents == "cds" and e4.gz_music == nil, "list lines carry their album, playlist or artist (tracks stay plain)")
    local widget_mods = { "ui/widget/container/inputcontainer", "ui/widget/container/widgetcontainer", "ui/gesturerange", "ui/font", "ffi/blitbuffer" }
    local saved_w = {}
    for _i, wm in ipairs(widget_mods) do
        saved_w[wm] = package.loaded[wm]
        if type(saved_w[wm]) ~= "table" then package.loaded[wm] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    local Views = require("gzreader_shopviews")
    for _i, wm in ipairs(widget_mods) do package.loaded[wm] = saved_w[wm] end
    check(Views.kindOf({ e1 }) == "cds" and Views.kindOf({ e2, { text = "More (25 of 80)…", callback = function() end } }) == "cds"
        and Views.kindOf({ e3 }) == "bay" and Views.kindOf({ e4 }) == nil, "albums and playlists: CD cases; artists: compartments; tracks: a list")
    local t1, t2 = Views.musicTag(e1.gz_music), Views.musicTag(e2.gz_music)
    check(t1.title == "A" and t1.authors[1] == "X · 2020" and t2.authors[1] == "12 tracks", "a case's tag: the artist and year, a playlist's tracks")
    local one = function(x) return x end
    local fits = true
    for _j, size in ipairs({ { 600, 574 }, { 1072, 1078 }, { 758, 760 }, { 824, 1000 } }) do
        local L = Views.layout("cds", size[1], size[2], false, one)
        local fit_ok = L.fits and L.box_w <= L.slots[1].w and L.box_h > 0 and math.abs(L.box_w / L.box_h - Views.CD_RATIO) < 0.05 and L.cols >= 2
        for _k, sl in ipairs(L.slots) do fit_ok = fit_ok and sl.x >= 0 and sl.x + sl.w <= size[1] and sl.y + sl.h <= size[2] end
        if not fit_ok then fits = false; print("  (cds don't fit at " .. size[1] .. "x" .. size[2] .. ")") end
    end
    check(fits, "CD cases: a little wider than tall, two or more a row, on every Kindle's page")
    -- covers: asked for once a session, and not at all when they're here
    local MC = require("gzreader_musiccovers")
    check(MC.id({ key = "/library/metadata/201" }) == "plex-_library_metadata_201", "a cover's name in the cache")
    local miss = MC.missing({ { key = "301", thumb = "/t" }, { key = "302" } })
    MC.tried[MC.id({ key = "301" })] = true
    check(#miss == 1 and miss[1].key == "301" and #MC.missing({ { key = "301", thumb = "/t" } }) == 0,
        "covers: only ones with a picture on Plex, each asked for once (one that doesn't come isn't asked for at every redraw)")
    MC.tried = {}
    -- the page, signed in
    local saved_plex = plugin.store.plex
    plugin.store.plex = { token = "t", username = "will", server = { uri = "http://127.0.0.1:9", name = "Home Server" } }
    local saved_audio = require("gzreader_touch").audio
    require("gzreader_touch").audio = function() return true end
    local mb = Browser:new(plugin)
    mb:show({ section = "music" })
    local ids = {}
    for _i, it in ipairs(mb.menu.item_table) do ids[#ids + 1] = it.gz_id end
    local m1 = mb.menu.item_table
    check(table.concat(ids, ","):match("^mu_search,mu_played,mu_recent,mu_playlists,mu_albums,mu_artists,") and m1[1].gz_action == "search"
        and m1[4].gz_contents == "cds" and m1[#m1].gz_id == "mu_account" and m1[#m1].mandatory == "will · Home Server" and m1.gz_root,
        "the Music page: search, Recently played, Recently added, then Playlists, Albums, Artists… and the Plex account " .. table.concat(ids, ","))
    local Shop = require("gzreader_bookshop")
    local mps = Shop.pageSpec("music")
    local mcomp = {}
    for _i, c in ipairs(mps.compartments) do mcomp[#mcomp + 1] = tostring(c.id) end
    check(mps.music and mps.ledges[1].id == "mu_played" and mps.ledges[1].label == "Recently played" and mps.ledges[2].id == "mu_recent"
        and table.concat(mcomp, ",") == "mu_playlists,mu_albums,mu_artists,mu_now,mu_account" and not table.concat(ids, ","):find("mu_downloaded", 1, true),
        "the Bookshelf view: the shop with Recently played and Recently added ledges of CD cases, then a compartment each (no On this Kindle)")
    -- Recently played: this Kindle's plays first (Plex only knows its own players'), once each
    local Music = require("gzreader_music")
    local saved_recent, saved_save = plugin.store.music_recent, plugin.save
    plugin.save = function() end
    plugin.store.music_recent = nil
    Music.notePlayed(plugin, { kind = "album", key = "201", title = "A", tracks = { {}, {} } })
    Music.notePlayed(plugin, { kind = "playlist", key = "9", title = "P", tracks = {} })
    Music.notePlayed(plugin, { kind = "album", key = "201", title = "A", tracks = { {}, {} } })
    Music.notePlayed(plugin, { kind = "all", key = "x" })
    local rk = {}
    for _i, it in ipairs(plugin.store.music_recent) do rk[#rk + 1] = it.type .. ":" .. it.key end
    check(table.concat(rk, ",") == "album:201,playlist:9" and plugin.store.music_recent[1].count == 2,
        "played here: newest first, each once (not Shuffle all) " .. table.concat(rk, ","))
    mb._shop_music = { asked = true, mu_played_remote = { { type = "album", key = "203", title = "C" }, { type = "album", key = "201", title = "A" } },
        mu_recent_remote = { { type = "album", key = "202" } } }
    local mst = Shop.musicLists(mb)
    local pk = {}
    for _i, it in ipairs(mst.mu_played) do pk[#pk + 1] = it.key end
    check(table.concat(pk, ",") == "201,9,203" and mst.mu_recent[1].key == "202" and #Shop.ledgeBooks(mst.mu_played, function(it) return it.key ~= nil end) == 3,
        "the ledges: the Kindle's plays, then Plex's; Recently added from Plex " .. table.concat(pk, ","))
    plugin.store.music_recent, plugin.save = saved_recent, saved_save
    -- Plex: Recently added / played albums (played: only ones played at all)
    local Plex = require("gzreader_plex")
    local px = Plex:new({ server = { uri = "http://127.0.0.1:9" } })
    local asked
    px.get = function(_s, path, params, opts)
        asked = { path = path, params = params, size = opts and opts.headers and opts.headers["X-Plex-Container-Size"] }
        return 200, { MediaContainer = { Metadata = {
            { ratingKey = "1", type = "album", title = "One", parentTitle = "X", lastViewedAt = 1700000000, addedAt = 1 },
            { ratingKey = "2", type = "album", title = "Two", parentTitle = "X", addedAt = 2 } } } }
    end
    local added = px:recentAlbums("7", "added", 12)
    local a_sort, a_size = asked.params.sort, asked.size
    local played = px:recentAlbums("7", "played", 12)
    check(#added == 2 and a_sort == "addedAt:desc" and a_size == "12" and asked.params.sort == "lastViewedAt:desc"
        and #played == 1 and played[1].key == "1" and played[1].viewed == 1700000000 and asked.path == "/library/sections/7/all",
        "Plex: albums by date added, and by last played (never-played ones left out)")
    plugin.store.plex = saved_plex
    local mb2 = Browser:new(plugin)
    mb2:show({ section = "music" })
    check(mb2.menu.item_table[1].gz_id == nil and tostring(mb2.menu.item_table[1].text):match("Plex"), "not signed in to Plex: the sign-in lines")
    require("gzreader_touch").audio = saved_audio
end)()

print("Libraries, authors, series (local index of readable books)")
local Index = require("gzreader_index")
local root = Browser:new(plugin):rootItems()
local names = {}
for _, it in ipairs(root) do names[#names + 1] = it.text end
check(table.concat(names, "|"):match("^Search Grimmory…|Continue reading|Recently added|All books.-|Libraries|Shelves|Authors|Series|Grimmory"), "root menu: Search, Continue, Recent, All books, Libraries, Shelves, Authors, Series, Grimmory")
print("Grimmory tab as a bookshop")
do
    local ids = {}
    for _i, it in ipairs(root) do ids[#ids + 1] = tostring(it.gz_id) end
    check(root.gz_root == true and table.concat(ids, ",") == "search,continue,recent,all,libraries,shelves,authors,series,grimmory"
        .. (#root > 9 and ",audiobooks" or ""), "root items: marked for the bookshop " .. table.concat(ids, ","))
    -- (its drawing only: its widgets stay stubs here)
    local widget_mods = { "ui/widget/container/inputcontainer", "ui/widget/container/widgetcontainer", "ui/gesturerange", "ui/font", "ffi/blitbuffer" }
    local kept = {}
    for _i, m in ipairs(widget_mods) do
        kept[m] = package.loaded[m]
        if type(kept[m]) ~= "table" then package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    local Shop = require("gzreader_bookshop")
    for _i, m in ipairs(widget_mods) do package.loaded[m] = kept[m] end
    local one = function(x) return x end
    local fits = true
    for _i, size in ipairs({ { 600, 614 }, { 600, 470 }, { 1072, 1150 }, { 758, 790 }, { 1448, 640 } }) do
        local w, h = size[1], size[2]
        local L = Shop.layout(w, h, one)
        local l1, l2 = L.ledges[1], L.ledges[2]
        local ok = L.fits and L.slip.y + L.slip.h < l1.sign.y and l1.ledge.y + l1.ledge.h < l2.sign.y
            and l2.ledge.y + l2.ledge.h <= L.case.y and L.case.y + L.case.h <= h and L.case.y >= 0
            and l1.box_h >= 40 and l1.box_w >= 40 and l1.cols[5].x + l1.cols[5].w <= w
        for _j, c in ipairs(L.cells) do
            ok = ok and c.x >= L.case.x and c.x + c.w <= L.case.x + L.case.w and c.y + c.h <= L.case.y + L.case.h
        end
        if not ok then fits = false; print("  (doesn't fit at " .. w .. "x" .. h .. ")") end
    end
    check(fits, "layout: the slip, two ledges and the bookcase fit, in order, on every Kindle's page")
    check(Shop.layout(800, 380, one).fits == false, "layout: too short a page (landscape) says so: the list instead")
    check(Shop.compartments()[6].id == "grimmory" and Shop.compartments()[6].kind == "account" and #Shop.compartments() == 6,
        "compartments: the last is the Grimmory card (Audiobooks are the Catalog's next page; what's here is in Downloads)")
    check(Shop.moreText(7) == "+3 more" and Shop.moreText(4) == "See all" and Shop.moreText(nil) == "See all", "the bundle's tag")
    local known = {
        index = { total = 1024, libraries = { ["1"] = 30, ["2"] = 0, ["3"] = 2 }, authors = { A = 1, B = 2, C = 3 }, series = { X = { count = 3 }, Y = { count = 1 } } },
        libraries = { { id = 1, name = "Fiction" }, { id = 2, name = "Audio only" }, { id = 3, name = "Classics" } },
        shelves = { { id = 1, name = "Favourites" }, { id = 2, name = "Book club" },
            { id = 9, name = "Unread sci-fi", magic = true, filter = { rules = { { field = "genre", value = "Science fiction" } } } } },
        audiobooks = 48,
    }
    local cards = {}
    for _i, id in ipairs({ "all", "libraries", "shelves", "authors", "series", "audiobooks" }) do cards[#cards + 1] = Shop.cardText(id, known) end
    check(table.concat(cards, "|") == "1,024 books|2 · Classics, Fiction|3 · 1 magic|3 · A–Z|1 series|48 audiobooks",
        "cards: counts from what's kept " .. table.concat(cards, "|"))
    check(not table.concat(cards, "|"):lower():find("genre", 1, true) and not table.concat(cards, "|"):find("Science", 1, true),
        "cards: a magic shelf's rules are never shown")
    check(Shop.cardText("all", {}) == "A–Z" and Shop.cardText("shelves", {}) == "yours and magic", "cards: nothing kept yet")
    -- (a word as wide as 6 px per letter at size 9, one less per size below)
    check(Shop.miniLabelSize("Shelves", 42, function(sz, w) return #w * (sz - 3) end) == 9
        and Shop.miniLabelSize("Shelves", 30, function(sz, w) return #w * (sz - 3) end) == 7
        and Shop.miniLabelSize("Beach reads", 30, function(sz, w) return #w * (sz - 3) end) == 9
        and Shop.miniLabelSize("Extraordinarily", 30, function(sz, w) return #w * (sz - 3) end) == 6,
        "Shelves card: its label's size lets every word fit the little cover (no \"Shelve / s\")")
    -- the lists opened from it, in its style
    local saved_w = {}
    for _i, m in ipairs(widget_mods) do
        saved_w[m] = package.loaded[m]
        if type(saved_w[m]) ~= "table" then package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    local Views = require("gzreader_shopviews")
    for _i, m in ipairs(widget_mods) do package.loaded[m] = saved_w[m] end
    check(Views.kindOf({ { text = "Search…", gz_action = "search" }, { book = { id = 1 } } }) == "ledges"
        and Views.kindOf({ { book = { id = 1 }, cover_kind = "audiobook" } }) == "tapes"
        and Views.kindOf({ { gz_kind = "series" } }) == "piles" and Views.kindOf({ { gz_kind = "author" } }) == "bay"
        and Views.kindOf({ { gz_kind = "shelf" } }) == "bay" and Views.kindOf({ { text = "x" } }) == nil
        and Views.kindOf({ { gz_action = "search" }, { text = "No books found containing “q”", gz_kind = "nothing_found" } }) == "ledges",
        "lists: books on ledges, audiobooks on a tape rack, series in piles, libraries/shelves/authors in compartments, nothing found: the same ledges, empty")
    check(Views.headerCount({ { gz_action = "search" }, { gz_action = "refresh" }, { gz_kind = "author" } }) == 2
        and Views.headerCount({ { gz_kind = "author" }, { gz_action = "search" } }) == 0, "lists: search and refresh above the list")
    local vfits = true
    for _i, kind in ipairs({ "ledges", "bay", "piles", "tapes" }) do
        for _j, size in ipairs({ { 600, 574 }, { 1072, 1078 }, { 758, 760 } }) do
            local L = Views.layout(kind, size[1], size[2], true, one)
            local ok = L.fits and #L.slots >= 4
            for _k, sl in ipairs(L.slots) do ok = ok and sl.x >= 0 and sl.x + sl.w <= size[1] and sl.y >= L.band.y + L.band.h and sl.y + sl.h <= size[2] end
            if not ok then vfits = false; print("  (" .. kind .. " doesn't fit at " .. size[1] .. "x" .. size[2] .. ")") end
        end
    end
    check(vfits, "lists: their places fit the page, below the search")
    local cw_ok = true
    for _j, size in ipairs({ { 600, 574 }, { 1072, 1078 }, { 758, 760 } }) do
        -- the card between the middle row's ledge and the row above
        local L = Views.layout("ledges", size[1], size[2], true, one)
        local s1 = L.slots[(math.ceil(L.rows / 2) - 1) * L.cols + 1]
        local c = { x = 0, y = s1.y, w = size[1], h = s1.h - L.fixed }
        -- a short message: its card in the middle; a long one: no wider than the page
        for _k, tw in ipairs({ 200, 5000 }) do
            local r = Views.nothingCard(c.x, c.y, c.w, c.h, tw, 30, one)
            cw_ok = cw_ok and r.x >= c.x and r.x + r.w <= c.x + c.w and r.y >= c.y and r.y + r.h <= c.y + c.h
                and math.abs((r.x + r.w / 2) - (c.x + c.w / 2)) <= 1
        end
    end
    check(cw_ok, "nothing found: the card in the middle, between the ledges, never wider than the page")
    local K3 = Views.layout("ledges", 600, 574, true, one)
    check(K3.rows == 3 and K3.cols == 3, "ledges on a Kindle 3: 3 rows of 3 (tags wide enough for their bigger type) " .. K3.rows .. "x" .. K3.cols)
    check(Views.bookLabel({ personalRating = 8 }) == "★★★★☆" and Views.bookLabel({ readProgress = 33.6 }) == "34%"
        and Views.bookLabel({}) == nil, "a book's label: your stars, else how far you are")
    check(Views.cardOf({ gz_kind = "shelf", gz_magic = true, mandatory = "smart shelf" }) == "magic shelf"
        and Views.cardOf({ gz_kind = "author", gz_count = 3 }) == "3 books", "a compartment's card: a magic shelf says so, nothing more")
    local books = Shop.ledgeBooks({ { id = 1, primaryFileType = "EPUB" }, { id = 2, primaryFileType = "AUDIOBOOK" }, "junk", { id = 3, primaryFileType = "PDF" } }, Browser.isReadable)
    check(#books == 2 and books[1].id == 1 and books[2].id == 3, "ledges: readable books only, in order")
end

local function find(list, pat) for _, it in ipairs(list) do if it.text:match(pat) then return it end end end
local function texts(list) local t = {} for _, it in ipairs(list) do t[#t + 1] = it.text end return table.concat(t, "|") end

print("Sorting Grimmory's lists")
do
    check(select(1, Browser.sortParams()) == "title" and select(2, Browser.sortParams()) == "asc", "sorted by title (A–Z) unless chosen")
    gsettings.gzreader_grimmory_sort = "added"
    local f, d = Browser.sortParams()
    gsettings.gzreader_grimmory_sort_reverse = true
    local f2, d2 = Browser.sortParams()
    check(f == "addedOn" and d == "desc" and f2 == "addedOn" and d2 == "asc", "Date added: newest first; Reverse: oldest first")
    gsettings.gzreader_grimmory_sort_reverse = nil
    local sb = Browser:new(plugin); sb:show()
    sb:openPaged("All books", { sort = "title", dir = "asc" })
    runLoop(function() return sb.menu.title == "All books" end, 20)
    local function lastList()
        local q
        for _i, e in ipairs(json.decode(ctl("/state")).log) do
            if e[1] == "GET" and e[2]:match("^/api/v1/app/books%?") then q = e[2] end
        end
        return q or ""
    end
    check(lastList():match("sort=addedOn") and lastList():match("dir=desc"), "a book list asks Grimmory in the chosen order")
    gsettings.gzreader_grimmory_sort = "lastread"
    sb:resort()
    runLoop(function() return lastList():match("sort=lastReadTime") ~= nil end, 20)
    check(lastList():match("sort=lastReadTime") and #sb.menu.item_table_stack == 1, "a new order: the list opened again with it, in its place")
    gsettings.gzreader_grimmory_sort = nil
end

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
do -- Refresh list from Grimmory: Wi-Fi on first (it may have gone off while the saved list was open)
    local Net = require("gzreader_net")
    local was_run, was_build = Net.run, Index.build
    local reason, built
    Net.run = function(fn, opts) reason = opts and opts.reason; fn() end
    Index.build = function(_plugin, show) built = show end
    find(b.menu.item_table, "^Refresh").callback()
    Net.run, Index.build = was_run, was_build
    check(reason == "refreshing the Grimmory list" and built == true, "Refresh list from Grimmory turns Wi-Fi on first, then rebuilds")
    -- Check for updates says why it turns Wi-Fi on (the log read "turning on for ?")
    local Upd = require("gzreader_update")
    local was_check = Upd.check
    local checked
    reason = nil
    Net.run = function(fn, opts) reason = opts and opts.reason; fn() end
    Upd.check = function() checked = true; return nil, "test" end
    Upd.run()
    Net.run, Upd.check = was_run, was_check
    check(reason == "checking for updates" and checked == true, "Check for updates gives its reason for turning Wi-Fi on")
end
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
check(sl[1].text == "Search series…" and sl[2].text:match("Refresh") and sl[3].text == "Saga / Part One — Author 2, Author 0, Author 1", "series: search, refresh, then A–Z, with its authors")
check(not texts(sl):match("Audio Only Saga"), "audiobook-only series left out")
check(sl[3].mandatory == "3 books", "series counts readable books only")
local ones = 0
for _i, it in ipairs(sl) do if it.gz_kind == "series" and (tonumber(it.gz_count) or 0) < 2 then ones = ones + 1 end end
check(ones == 0, "series of one book aren't listed")
sl[3].callback()
local st = {}
for _, it in ipairs(b.menu.item_table) do st[#st + 1] = it.text:match("^(#[%d%.]+)") or "?" end
check(table.concat(st, ",") == "#1,#2,#2.5", "series books in order with numbers; audiobook left out; '/' in name works")
check(b.menu.item_table[1].book ~= nil, "a series' books: no search line above them")
b = Browser:new(plugin); b:show()
b:openSeries("author 2")
check(b.menu.title == "Series: author 2" and #b.menu.item_table == 1 and b.menu.item_table[1].text:match("^Saga"), "series search: by name or author")

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
    gsettings.gzreader_wifi_mode = "off" -- nothing in the background may turn Wi-Fi on
    local before = reqs("continue%-reading")
    b = Browser:new(plugin); b:show()
    b:openSimple("continue-reading", "Continue reading")
    check(b.menu.title == "Continue reading · saved" and #b.menu.item_table == 5, "offline: saved list shown at once, marked saved")
    check(reqs("continue%-reading") == before, "offline: no request made")
    b:openLibraries()
    check(b.menu.title == "Libraries · saved" and texts(b.menu.item_table) == "Comics|fiction", "offline: saved libraries")
    -- Wi-Fi comes up: the fresh list replaces the saved one in place
    gsettings.gzreader_wifi_mode = "auto"
    captured.wifi = {}
    b = Browser:new(plugin); b:show()
    b:openPaged("All books", { sort = "title", dir = "asc" })
    check(captured.wifi[1] == "on-quiet", "Wi-Fi turned on quietly in the background")
    check(b.menu.title == "All books" and #b.menu.item_table == 27, "then the fresh list replaces the saved copy")
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
    gsettings.gzreader_wifi_mode = "off"
    captured.err = nil
    b = Browser:new(plugin); b:show()
    b:openSimple("continue-reading", "Continue reading")
    check(b.menu.title ~= "Continue reading · saved", "another account doesn't see these saved lists")
    plugin.store.username = user
    NET.connected, gsettings.gzreader_wifi_on_demand, gsettings.gzreader_wifi_mode = was, wod, nil
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

-- the book page's Download: no progress box, not opened, a note when done
ctl("/set?dl_big=false&dl_slow=false")
reader_opened, captured.info, captured.confirm = nil, nil, nil
captured.pdialog_open = false
plugin:downloadAndOpen({ id = 6, title = "Quiet Book", primaryFileName = "quiet.epub", primaryFileType = "EPUB", fileSizeKb = 4 }, nil, { no_open = true })
check(not captured.pdialog_open and Download.active ~= nil, "Download (not open): no progress box, running")
runLoop(function() return Download.active == nil end, 20)
runLoop(function() return captured.info ~= nil and captured.info:match("Downloaded") ~= nil end, 5)
check(reader_opened == nil and captured.confirm == nil and captured.info and captured.info:match("Downloaded “Quiet Book”"),
    "done: not opened, not asked, a note " .. tostring(captured.info))
check(plugin:localPathFor(6) ~= nil, "and it's on the Kindle")
ctl("/set?dl_big=true") -- (as the stalled download below expects)

-- downloads from before 1.22.4 get their Grimmory authors (for the spines)
do
    local was = NET.connected
    NET.connected = true
    plugin.store.downloads["3"].authors, plugin.store.downloads["3"].authors_asked = nil, nil
    plugin:backfillAuthors()
    runLoop(function() return plugin.backfilling == nil end, 20)
    check(plugin.store.downloads["3"].authors == "Author 0" and plugin.store.downloads["3"].authors_asked,
        "a download without authors gets Grimmory's, once " .. tostring(plugin.store.downloads["3"].authors))
    NET.connected = was
end

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

print("The Kindle 2/3/DX's screen: four pixels packed at a time, the same bytes")
;(function()
    local ffi = require("ffi")
    local okb, BB = pcall(require, "ffi/blitbuffer")
    local okf, ShadowFB = pcall(dofile, PLUGIN .. "/../../frontend/device/kindle/shadowfb.lua")
    check(okb and okf, "shadowfb.lua loads " .. tostring(not okf and ShadowFB or ""))
    if not (okb and okf) then return end
    local function buffers(w, h)
        local sh = { w = w, h = h, stride = w, data = ffi.new("uint8_t[?]", w * h + 16) }
        local fb = { w = w, h = h, stride = w / 2, data = ffi.new("uint8_t[?]", w * h / 2 + 16), getType = function() return BB.TYPE_BB4 end }
        return sh, fb
    end
    local seed = 12345
    local function rnd(m) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % m end
    local mismatches, cases = 0, 0
    for _i, size in ipairs({ { 600, 40 }, { 824, 30 }, { 602, 20 } }) do
        local w, h = size[1], size[2]
        local sh = buffers(w, h)
        for k = 0, w * h - 1 do sh.data[k] = rnd(256) end
        for _c = 1, 60 do
            local x, y = rnd(w + 20) - 10, rnd(h)
            local rw, rh = rnd(w) + 1, rnd(h - y) + 1
            local inv = rnd(2) == 1
            local fa = select(2, buffers(w, h))
            local fb2 = select(2, buffers(w, h))
            for k = 0, w * h / 2 - 1 do local v = rnd(256); fa.data[k] = v; fb2.data[k] = v end
            ShadowFB.wide = false
            ShadowFB.pack(sh, fa, x, y, rw, rh, inv)
            ShadowFB.wide = true
            ShadowFB.pack(sh, fb2, x, y, rw, rh, inv)
            if ffi.string(fa.data, w * h / 2) ~= ffi.string(fb2.data, w * h / 2) then mismatches = mismatches + 1 end
            cases = cases + 1
        end
    end
    check(mismatches == 0 and cases == 180, "four at a time: byte for byte what two at a time gives (" .. cases .. " rectangles, both grey levels, " .. mismatches .. " different)")
    ShadowFB.wide = true
end)()

print("Timers on the clock's quarter minutes; the clock in a book on old Kindles follows the pages")
;(function()
    local Ticks = require("gzreader_ticks")
    local real = Ticks.now
    Ticks.now = function() return 1000000.2 end -- (…:40.2 on the wall clock: 1000000 % 60 = 40)
    local q1, h1 = Ticks.untilNext(15), Ticks.untilNext(30)
    Ticks.now = function() return 1000004.9 end
    local c = Ticks.untilNext(15)
    Ticks.now = real
    check(math.abs(q1 - 4.85) < 0.01 and math.abs(h1 - 19.85) < 0.01 and math.abs(c - 0.15) < 0.01 + 15 and c > 15,
        "the next quarter / half minute (just after it, so they're due together; never less than half a second away)")
    local function src(rel) local h = io.open(PLUGIN .. "/" .. rel, "rb"); local t = h and h:read("*a") or ""; if h then h:close() end; return t end
    check(src("gzreader_remote.lua"):find('require("gzreader_ticks").untilNext(R.HEARTBEAT)', 1, true)
        and src("gzreader_net.lua"):find('require("gzreader_ticks").untilNext(Net.CHECK_EVERY)', 1, true),
        "the debug reports' heartbeat and the Wi-Fi idle check use it")
    local Eink = require("gzreader_eink")
    local Device = require("device")
    local was_model, was_kindle = Device.model, Device.isKindle
    Device.isKindle = function() return true end
    Device.model = "Kindle3"
    local k3 = Eink.minuteClock()
    Device.model = "KindlePaperWhite3"
    local pw3 = Eink.minuteClock()
    Device.model = "Kindle3"
    G_reader_settings:saveSetting(Eink.CLOCK_SETTING, true)
    local chosen = Eink.minuteClock()
    G_reader_settings:delSetting(Eink.CLOCK_SETTING)
    Device.model, Device.isKindle = was_model, was_kindle
    check(not k3 and pw3 and chosen, "in a book: the clock with the pages on a Kindle 3 (no REAGL), every minute on a Paperwhite; a setting wins")
    local zt = src("../zenos.koplugin/modules/reader/patches/reader_top_status_bar.lua")
    check(zt:find("local function gzMinuteRepaints()", 1, true) and zt:find("if not gzMinuteRepaints() then return end", 1, true)
        and zt:find("if not gzMinuteRepaints() then\n            _autoRefresh = nil", 1, true), "ZenOS's top bar in a book asks before its minute repaint")
end)()

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
do -- other requests first: the download waits while they run
    local job = Download.active
    local function state(pid)
        local fh = io.open("/proc/" .. pid .. "/stat", "rb")
        if not fh then return nil end
        local letter = fh:read("*a"):match("%) (%a)")
        fh:close()
        return letter
    end
    Download.yield()
    runLoop(function() return state(job.pid) == "T" end, 2)
    check(job and job.paused_at and state(job.pid) == "T", "a request asks Grimmory: the download's process is paused")
    local was_stall = Download.STALL_SECONDS
    Download.STALL_SECONDS = 1
    runLoop(function() return false end, 1.2) -- (what had arrived before the pause, counted)
    local size0 = job.last_size
    runLoop(function() return false end, 1.5)
    check(Download.active == job and not job.finished and job.last_size == size0,
        "paused: nothing arrives, and it isn't taken for a stalled download")
    Download.unyield()
    Download.STALL_SECONDS = was_stall
    check(job.paused_at == nil and state(job.pid) ~= "T" and job.yields == 1 and job.yielded_s >= 2, "the requests done: it carries on")
    -- at most YIELD_MAX at a time, then not again until the requests are done
    local was_max = Download.YIELD_MAX
    Download.YIELD_MAX = 1
    Download.yield()
    runLoop(function() return job.paused_at == nil end, 5)
    Download.yield()
    check(job.paused_at == nil and job.yielded_enough and state(job.pid) ~= "T", "waited YIELD_MAX: carries on, and isn't paused again meanwhile")
    Download.unyield()
    Download.YIELD_MAX = was_max
    -- gzreader_async: a request batch makes it wait, and it goes on after
    local A = require("gzreader_async")
    local was_y, was_u, calls = Download.yield, Download.unyield, {}
    Download.yield = function() calls[#calls + 1] = "wait" end
    Download.unyield = function() calls[#calls + 1] = "go on" end
    local saved_sync, res = A.sync, nil
    A.sync = false
    A.run(nil, function() return "details" end, function(r) res = r end, "getBookDetail")
    runLoop(function() return res ~= nil and #calls >= 2 end, 10)
    A.run(nil, function() return 1 end, function() end, "pre-size covers", { nice = true })
    runLoop(function() return not A.busy end, 10)
    A.sync = saved_sync
    Download.yield, Download.unyield = was_y, was_u
    check(res == "details" and calls[1] == "wait" and calls[2] == "go on" and #calls == 3,
        "a background request: the download waits, then goes on; long work (opts.nice) doesn't make it wait (" .. table.concat(calls, ", ") .. ")")
end
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
    -- the screen kept current: only the lines that changed, on the page shown
    local function rect(x, y, w, h)
        local r = { x = x, y = y, w = w, h = h }
        function r.copy(a) return rect(a.x, a.y, a.w, a.h) end
        function r.combine(p, q)
            local x0, y0 = math.min(p.x, q.x), math.min(p.y, q.y)
            return rect(x0, y0, math.max(p.x + p.w, q.x + q.w) - x0, math.max(p.y + p.h, q.y + q.h) - y0)
        end
        return r
    end
    local UIM = require("ui/uimanager")
    local was_dirty, dirty = UIM.setDirty, {}
    UIM.setDirty = function(_um, w, how) dirty[#dirty + 1] = { w = w, how = how } end
    local m = { page = 2, perpage = 2, item_group = { { dimen = rect(0, 100, 600, 60) }, { dimen = rect(0, 160, 600, 60) } } }
    m.item_table = { { text = "a", mandatory = "1%" }, { text = "b" }, { text = "c", mandatory = "5%" }, { text = "d" } }
    function m.switchItemTable(self, _t, new_list, keep)
        self.item_table, self.keep = new_list, keep
        UIM:setDirty(self, function() return "ui", rect(0, 0, 600, 800) end)
    end
    local same = { { text = "a", mandatory = "1%" }, { text = "b" }, { text = "c", mandatory = "5%" }, { text = "d" } }
    check(Tasks.update(m, same) == "same" and #dirty == 0, "Downloads screen: nothing changed, nothing redrawn")
    local moved = { { text = "a", mandatory = "1%" }, { text = "b" }, { text = "c", mandatory = "9%" }, { text = "d" } }
    local how, rows = Tasks.update(m, moved)
    local kind, area
    if dirty[1] then kind, area = dirty[1].how() end
    check(how == "rows" and rows[1] == 1 and #rows == 1 and m.keep == -1 and kind == "ui" and area.y == 100 and area.h == 60,
        "a percentage changed: only its line refreshed, on the same page (" .. tostring(area and area.y) .. "+" .. tostring(area and area.h) .. ")")
    dirty = {}
    check(Tasks.update(m, { { text = "a", mandatory = "2%" }, { text = "b" }, { text = "c", mandatory = "9%" }, { text = "d" } }) == "offpage"
        and #dirty == 0 and m.item_table[1].mandatory == "2%", "a change on another page: kept for when it's shown, nothing redrawn")
    local all = Tasks.update(m, { { text = "a" } })
    local full = select(2, (dirty[1] or { how = function() end }).how())
    check(all == "all" and full and full.h == 800,
        "the list itself changed (a download done): all of it redrawn")
    UIM.setDirty = was_dirty
end
ctl("/set?dl_slow=false")
runLoop(function() return plugin.store.downloads["27"] ~= nil end, 40)
check(reader_opened == WORK .. "/home/GZreader/first.epub", "first (watched) download opens")
check(plugin.store.downloads["27"] ~= nil and Download.active == nil and #Download.queue == 0, "queued download ran after it")
check(captured.info and captured.info:match("Downloaded “Second”. The download queue is done."), "queued completion: short notice, no Open prompt per book")
check(require("gzreader_tasks").status() == nil and require("gzreader_tasks").count() == 0, "title bar item empty again when done")
ctl("/set?dl_big=false")

print("New books laid out in the background while charging")
;(function()
    local L = require("gzreader_layout")
    local lfs = require("lfs")
    local dir = WORK .. "/layout"
    os.execute("mkdir -p '" .. dir .. "'")
    local function mk(name) local h = io.open(dir .. "/" .. name, "wb"); h:write("x"); h:close(); return dir .. "/" .. name end
    local fake = { store = { downloads = {
        ["1"] = { path = mk("old.epub") }, ["2"] = { path = mk("new.epub") }, ["3"] = { path = mk("read.epub") },
        ["4"] = { path = mk("scan.pdf") }, ["5"] = { path = dir .. "/gone.epub" }, ["6"] = { path = mk("done.epub"), laid_out = 1 },
        ["7"] = { path = mk("failed.epub"), layout_tries = 2 } } }, saves = 0 }
    function fake:saveSoon() self.saves = self.saves + 1 end
    lfs.touch(dir .. "/old.epub", os.time() - 100, os.time() - 100)
    local charge, reader, forks, busy = true, false, {}, nil
    local saved = { L.isCharging, L.readerOpen, L.sidecar, L.memTotalKB, L.fork, L.isBusy }
    L.isBusy = function() return busy end
    L.isCharging = function() return charge end
    L.readerOpen = function() return reader end
    local sidecars = {}
    L.sidecar = function(bp)
        if bp:find("read.epub", 1, true) then return { last_xpointer = "/body/DocFragment[3]" } end
        return sidecars[bp:match("[^/]+$")]
    end
    L.memTotalKB = function() return 252364 end
    L.fork = function(bpath)
        local fk = { path = bpath, line = nil, stopped = false }
        forks[#forks + 1] = fk
        return { poll = function() return fk.line end, stop = function() fk.stopped = true end }
    end
    local LUI = require("ui/uimanager")
    local real_in = LUI.scheduleIn
    local timers = {}
    LUI.scheduleIn = function(_u, sec, fn) timers[#timers + 1] = { s = sec, fn = fn } end
    local c = L.candidate(fake)
    check(c and c.id == "2", "the next book: the newest never opened (not a PDF, a gone file, one opened, laid out or failed twice)")
    -- picture books: the settings the check writes before the first open
    sidecars["new.epub"] = { gzreader_picture_book = true }
    c = L.candidate(fake)
    check(L.notYet(dir .. "/new.epub") == "a picture book fitted when it opens" and c and c.id == "1",
        "a picture book recognized but not fitted yet: not laid out (its first open fits it and lays it out again)")
    sidecars["new.epub"] = { gzreader_picture_book = true, gzreader_pb_fit = { top = 40, bottom = 30 } }
    c = L.candidate(fake)
    check(L.notYet(dir .. "/new.epub") == nil and c and c.id == "2",
        "a picture book fitted before its first open: laid out, with the margins and style it was given")
    sidecars["new.epub"] = { gzreader_picture_book = false }
    c = L.candidate(fake)
    check(c and c.id == "2", "checked and not a picture book: the settings file the check wrote doesn't count as opened")
    check(L.notYet(dir .. "/read.epub") == "opened", "a reading position next to it: opened")
    sidecars["new.epub"] = nil
    -- the real Layout.busy: a book waiting for its picture-book check comes first
    local was_busy, PBq = L.isBusy, package.loaded["gzreader_picturebook"]
    L.isBusy = nil
    package.loaded["gzreader_picturebook"] = { queue = { dir .. "/new.epub" } }
    local why_pb = L.busy()
    package.loaded["gzreader_picturebook"].queue = {}
    local why_none = L.busy()
    package.loaded["gzreader_picturebook"], L.isBusy = PBq, was_busy
    check(why_pb == "a picture-book check" and why_none == nil,
        "a picture-book check waiting: no layout until it's done (" .. tostring(why_pb) .. ", " .. tostring(why_none) .. ")")
    L.memTotalKB = function() return 124532 end
    check(not L.possible() and L.tick(fake) == nil and #forks == 0, "a DX (128 MB): never")
    L.memTotalKB = function() return 252364 end
    charge = false
    check(L.tick(fake) == nil and #forks == 0, "not charging: nothing")
    charge, reader = true, true
    check(L.tick(fake) == nil and #forks == 0, "a book open: nothing")
    reader = false
    G_reader_settings:saveSetting(L.SETTING, false)
    check(L.tick(fake) == nil and #forks == 0, "turned off in Settings: nothing")
    G_reader_settings:delSetting(L.SETTING)
    local job = L.tick(fake)
    check(job and #forks == 1 and forks[1].path == dir .. "/new.epub" and L.running == job, "charging on Home: the book laid out in a background process")
    check(L.tick(fake) == nil and #forks == 1, "…one at a time")
    forks[1].line = "ok 312 41"
    timers[#timers].fn()
    check(not L.running and fake.store.downloads["2"].laid_out and fake.saves == 1, "done: remembered (not again)")
    job = L.tick(fake)
    check(job and forks[2].path == dir .. "/old.epub", "then the next one")
    charge = false
    timers[#timers].fn()
    check(forks[2].stopped and not L.running and not fake.store.downloads["1"].laid_out and (fake.store.downloads["1"].layout_tries or 0) == 0,
        "unplugged: stopped at once (tried again another time)")
    charge = true
    L.tick(fake)
    reader = true
    timers[#timers].fn()
    check(forks[3].stopped and not L.running, "a book opened: stopped at once")
    reader = false
    L.tick(fake)
    forks[4].line = ""
    timers[#timers].fn()
    L.tick(fake)
    forks[5].line = "err not a book the engine lays out"
    timers[#timers].fn()
    check(fake.store.downloads["1"].layout_tries == 2 and L.candidate(fake) == nil, "failed twice (the process died, an error): not tried again")
    -- downloads first: not while one runs or waits, and stopped when one starts
    fake.store.downloads["8"] = { path = mk("later.epub") }
    busy = "a download"
    check(L.tick(fake) == nil and #forks == 5, "a book downloading (or waiting to): no layout meanwhile")
    busy = nil
    L.tick(fake)
    busy = "a download"
    timers[#timers].fn()
    check(forks[6].stopped and not L.running and (fake.store.downloads["8"].layout_tries or 0) == 0,
        "a download started: the layout stopped at once (tried again later)")
    busy = "other background work"
    check(L.tick(fake) == nil and #forks == 6, "other background work running (a picture-book check, covers): no layout either")
    busy = nil
    -- the layout it made, and whether the reader used it
    L.tick(fake)
    forks[7].line = "ok 120 9"
    local CD_was, inits = package.loaded["document/credocument"], 0
    package.loaded["document/credocument"] = { cacheInit = function() inits = inits + 1 end }
    timers[#timers].fn()
    local e8 = fake.store.downloads["8"]
    check(e8.laid_out and e8.layout_secs == 9, "done: how long the layout took kept")
    check(inits == 1, "done: the book engine reads its layout cache index again (else a book laid out after another was opened isn't found)")
    reader = true
    check(not L.reloadCacheIndex() and inits == 1, "…not under an open book")
    reader = false
    package.loaded["document/credocument"] = { cacheInit = function() error("crengine not started") end }
    check(L.reloadCacheIndex() == false, "…nothing before the first book opened (crengine not started yet)")
    package.loaded["document/credocument"] = CD_was
    local LogL = require("gzreader_log")
    local was_info, said = LogL.info, {}
    LogL.info = function(...) said[#said + 1] = table.concat({ ... }, " ") end
    L.opened(nil, e8, 8, 0.2)
    L.opened(nil, e8, 8, 30) -- (once per book)
    L.opened(nil, { laid_out = 1, layout_secs = 40 }, 9, 12.5)
    local OT_was = package.loaded["gzreader_opentiming"]
    package.loaded["gzreader_opentiming"] = { cur = { phases = { ["laid out"] = require("ui/time").s(0.3) } } }
    L.opened(nil, { laid_out = 1 }, 10)
    package.loaded["gzreader_opentiming"] = { cur = nil }
    L.opened(nil, { laid_out = 1 }, 11)
    package.loaded["gzreader_opentiming"] = OT_was
    LogL.info = was_info
    check(#said == 4 and said[1]:find("its layout used: laid out in 0.2 s (in the background: 9 s)", 1, true)
        and said[2]:find("laid out again, 12.5 s (in the background: 40 s)", 1, true)
        and said[3]:find("its layout used: laid out in 0.3 s", 1, true)
        and said[4]:find("the reader's layout time not known", 1, true),
        "opened: the log says whether the reader used the background layout, from the time its own layout took ("
            .. table.concat(said, " / ") .. ")")
    local src = io.open(PLUGIN .. "/gzreader_layout.lua", "rb")
    local ltext = src and src:read("*a") or ""
    if src then src:close() end
    check(ltext:find('require("readhistory").addItem = function() end', 1, true) and ltext:find('require("docsettings").flush = function() end', 1, true)
        and ltext:find("oom_score_adj", 1, true) and ltext:find("lowerPriority(19)", 1, true),
        "the background process: no history or book settings written, lowest priority, the first to go if memory runs out")
    LUI.scheduleIn = real_in
    L.isCharging, L.readerOpen, L.sidecar, L.memTotalKB, L.fork, L.isBusy = saved[1], saved[2], saved[3], saved[4], saved[5], saved[6]
    L.running = nil
    os.execute("rm -rf '" .. dir .. "'")
end)()

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

print("Diagnostic log: the device probe's unchanging part is kept between exports")
;(function()
    local Log = require("gzreader_log")
    local saved_cmds, saved_live, saved_cache = Log.PROBE_COMMANDS, Log.PROBE_LIVE, Log.probe_cache
    local counts = WORK .. "/probe-counts"
    os.remove(counts)
    local fixed = "echo s >> " .. counts .. "; echo fixed-answer"
    local live = "echo l >> " .. counts .. "; echo live-answer"
    Log.PROBE_COMMANDS, Log.PROBE_LIVE = { fixed, live }, { [live] = true }
    Log.probe_cache = WORK .. "/probe-cache/gz-device-probe.lua"
    os.remove(Log.probe_cache)
    local function ran()
        local fh = io.open(counts, "rb"); local txt = fh and fh:read("*a") or ""; if fh then fh:close() end
        local _, s_runs = txt:gsub("s", ""); local _, l_runs = txt:gsub("l", "")
        return s_runs, l_runs
    end
    local text1, how1 = Log.deviceProbe()
    local text2, how2 = Log.deviceProbe()
    local s_runs, l_runs = ran()
    check(how1 == "run now" and how2:match("^kept from") and s_runs == 1 and l_runs == 2,
        "the second export reuses the kept answers; the live commands run each time (" .. s_runs .. ", " .. l_runs .. ")")
    check(text1:find("fixed-answer", 1, true) and text2:find("fixed-answer", 1, true) and text2:find("live-answer", 1, true)
        and text2:find("kept from", 1, true) and not text1:find("kept from", 1, true), "the kept answers are in the log, marked as kept")
    local Update = require("gzreader_update")
    local was_version = Update.currentVersion
    Update.currentVersion = function() return "9.9.9-beta.abc1234" end
    local how_v = select(2, Log.deviceProbe())
    Update.currentVersion = was_version
    check(how_v:match("^kept from") and ran() == 1, "another GZreader version (a new test build): still kept")
    local was_fw = Log.firmwareText
    Log.firmwareText = function() return "Kindle 3.4.3 (2697260037)" end
    local how3 = select(2, Log.deviceProbe())
    Log.firmwareText = was_fw
    check(how3 == "run now" and ran() == 2, "another firmware: the probe runs again")
    Log.PROBE_COMMANDS = { fixed, live, "echo another" }
    local how4 = select(2, Log.deviceProbe())
    check(how4 == "run now" and ran() == 3, "the probe's commands changed: it runs again")
    local fh = io.open(Log.probe_cache, "wb"); fh:write("return {{{"); fh:close()
    local probe_ok, _text5, how5 = pcall(Log.deviceProbe)
    check(probe_ok and _text5 and how5 == "run now", "a damaged kept file: the probe runs again, no error")
    -- the export says how long it took and how the probe was made
    local saved_probe = Log.probe_device
    Log.probe_device = true
    local dest = Log.exportTo(WORK, nil)
    Log.probe_device = saved_probe
    local lf = io.open(Log.path, "rb"); local logged = lf and lf:read("*a") or ""; if lf then lf:close() end
    check(dest and logged:match("log built in [%d.]+ s %(device probe: kept from [^)]+%)\n$"), "the export logs how long it took")
    if dest then os.remove(dest) end
    Log.PROBE_COMMANDS, Log.PROBE_LIVE, Log.probe_cache = saved_cmds, saved_live, saved_cache
end)()

print("Diagnostic log files don't pile up")
;(function()
    local Log = require("gzreader_log")
    local lfs = require("libs/libkoreader-lfs")
    local dir = WORK .. "/saved-logs"
    lfs.mkdir(dir)
    local function touch(name) local fh = io.open(dir .. "/" .. name, "wb"); fh:write("x"); fh:close() end
    for _i, name in ipairs({ "gzreader-log-20261101-100000.txt", "gzreader-log-20261102-100000.txt", "gzreader-log-20261103-100000.txt",
            "gzreader-log-20261104-100000.txt", "gzreader-log-19700101-000500.txt", "notes.txt" }) do touch(name) end
    local removed = Log.pruneExports(dir, 3, dir .. "/gzreader-log-19700101-000500.txt")
    local left = {}
    for name in lfs.dir(dir) do if name:sub(1, 1) ~= "." then left[#left + 1] = name end end
    table.sort(left)
    check(removed == 2 and table.concat(left, " ") == "gzreader-log-19700101-000500.txt gzreader-log-20261103-100000.txt gzreader-log-20261104-100000.txt notes.txt",
        "only the newest 3 saved logs stay; the one just written always does (a 1970 clock); other files untouched: " .. table.concat(left, " "))
    check(Log.pruneExports(WORK .. "/no-such-dir") == 0, "no folder: nothing to do, no error")
    local text, name = Log.exportText(dir, nil)
    local after = 0
    for fname in lfs.dir(dir) do if fname:match("^gzreader%-log%-") then after = after + 1 end end
    check(text and text:find("Grimmory plugin log", 1, true) and name:match("^gzreader%-log%-%d+%-%d+%.txt$") and after == 3,
        "the log as text for sending: its file is deleted again")
end)()

print("Grimmory folder is the home folder")
local libdir = WORK .. "/home/GZreader"
check(plugin.store.library_dir == libdir, "Grimmory folder created under the device's documents folder")
check(gsettings.home_dir == libdir and plugin.store.home_is_library == true, "home folder set to it on first start, no prompt")
check(gsettings.collate == "access", "sorted by recently opened, like ZenOS's folder setup")
check(plugin:localPathFor(3) == libdir .. "/book3.epub", "downloads saved straight into it (shows in the Downloaded tab)")
gsettings.home_dir = "/somewhere/else"                     -- an older build's "Set home folder"
Grimmory:new{ ui = { menu = { registerToMainMenu = function() end }, active_widgets = {} } }
check(gsettings.home_dir == libdir, "the home folder is always the GZreader folder: set back at the next start")
gsettings.home_dir = libdir
do -- Settings → Library → Folders has no Home folder menu (Set / Lock / Additional home folders)
    local lf = io.open(PLUGIN .. "/../zenos.koplugin/modules/settings/sections/library_settings.lua", "rb")
    local lsrc = lf and lf:read("*a") or ""
    if lf then lf:close() end
    check(lsrc:find("local folders_item = {", 1, true) and lsrc:find('text = _("Hide up folder")', 1, true),
        "the Folders settings are still there (Hide up folder)")
    check(not lsrc:find('_("Home folder")', 1, true) and not lsrc:find('_("Lock home folder")', 1, true)
        and not lsrc:find('_("Additional home folders")', 1, true) and not lsrc:find("settings_home_folder", 1, true),
        "Settings → Library → Folders: no Home folder menu, so the home folder can't be changed there")
    local function koSource(rel)
        local kf = io.open(KOROOT .. "/frontend/apps/filemanager/" .. rel, "rb")
        local ksrc = kf and kf:read("*a") or ""
        if kf then kf:close() end
        return ksrc
    end
    local fmmenu, fm = koSource("filemanagermenu.lua"), koSource("filemanager.lua")
    check(fmmenu:find('_("Show parent folder")', 1, true) and not fmmenu:find('_("Home folder settings")', 1, true)
        and not fmmenu:find('_("Set home folder")', 1, true) and not fmmenu:find('_("Shorten home folder")', 1, true)
        and not fmmenu:find('_("Lock home folder")', 1, true),
        "KOReader's file manager menu: no Home folder settings (Set / Shorten / Lock home folder)")
    check(fm:find('_("Go to HOME folder")', 1, true) and not fm:find('_("Set as HOME folder")', 1, true),
        "KOReader's file manager: no Set as HOME folder button (folder hold, + menu); Go to HOME folder stays")
end
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

print("Saving: a small change doesn't rewrite the whole state")
do
    local real_fp = Grimmory.fingerprint
    local dumpf = require("dump")
    -- (rapidjson isn't here: the same parts, through KOReader's dump)
    Grimmory.fingerprint = function(store)
        local part = {}
        for _i, k in ipairs(Grimmory.BIG_KEYS) do part[k] = store[k] end
        for _i, k in ipairs(Grimmory.FULL_KEYS) do part[k] = store[k] end
        return dumpf(part, nil, true)
    end
    -- (LuaSettings is a stand-in here: what each file would hold, at each flush)
    local LS = require("luasettings")
    local files = { main = plugin.settings, recent = LS:open(Grimmory.recentPath()) }
    local writes, last, orig = { main = 0, recent = 0 }, {}, {}
    for name, obj in pairs(files) do
        orig[name] = obj.flush
        obj.flush = function(o) writes[name] = writes[name] + 1; last[name] = dumpf(o.data, nil, true); return orig[name](o) end
    end
    local function fileState(name) return load("return " .. last[name])().state end
    local function counts() return writes.main, writes.recent end
    local pend = plugin.store.pending.progress
    plugin:saveFull()
    local m0, r0 = counts()
    check(m0 == 1 and r0 == 0 and fileState("main").downloads["3"] and not Grimmory.recent_written,
        "a full save: gzreader.lua, with the downloads; no recent part")
    pend["999"] = { gz_note = "small change" }
    plugin:save()
    local m1, r1 = counts()
    check(m1 == 1 and r1 == 1 and last.recent:find("small change", 1, true) and not last.recent:find("book3.epub", 1, true),
        "a queued position: only gzreader_recent.lua, without the download list")
    local fresh = fileState("main")
    check(fresh.pending.progress["999"] == nil and fresh.downloads["3"], "gzreader.lua alone is complete, a little older (what an older GZreader reads)")
    check(Grimmory.applyRecent(fresh) and fresh.pending.progress["999"] and fresh.downloads["3"] and fresh.save_seq == plugin.store.save_seq,
        "at start: the recent part laid over it, downloads kept")
    plugin.store.gz_test_key = "x"
    plugin:saveFull()
    plugin.store.gz_test_key = nil
    plugin:save()
    fresh = fileState("main")
    check(fresh.gz_test_key == "x" and Grimmory.applyRecent(fresh) and fresh.gz_test_key == nil, "…and what was removed since stays removed")
    local m2 = counts()
    plugin.store.downloads["998"] = { path = WORK .. "/none.epub", file_id = 1 }
    plugin:save()
    check(counts() == m2 + 1 and fileState("main").downloads["998"] and not Grimmory.recent_written,
        "a download: the whole file again, the recent part removed")
    plugin:save()
    check(Grimmory.recent_written, "(then small again)")
    local tok = plugin.store.refresh_token
    plugin.store.refresh_token = "rt-changed"
    plugin:save()
    check(not Grimmory.recent_written and fileState("main").refresh_token == "rt-changed", "a new sign-in token: the whole file (an older GZreader stays signed in)")
    plugin.store.refresh_token = tok
    -- a recent part written before the last full save is never laid over
    files.recent.data.seq = 1
    files.recent.data.state = { server = "https://old.example.com" }
    fresh = fileState("main")
    check(not Grimmory.applyRecent(fresh) and fresh.server ~= "https://old.example.com", "an older recent part: ignored")
    -- a while without a full save: one anyway
    plugin:save()
    Grimmory.full_at = os.time() - Grimmory.FULL_EVERY
    pend["996"] = { gz_note = "an hour later" }
    plugin:save()
    check(last.main:find("an hour later", 1, true) and not Grimmory.recent_written, "every " .. Grimmory.FULL_EVERY .. " s: the whole file anyway")
    local msf = io.open(PLUGIN .. "/main.lua", "rb")
    local msrc = msf and msf:read("*a") or ""
    if msf then msf:close() end
    check(msrc:find("if Grimmory.save_soon or Grimmory.recent_written then pcall(self.saveFull, self) end", 1, true)
        and msrc:find("if Grimmory.recent_written or Grimmory.save_soon then\n            Grimmory.full_due = true", 1, true), "sleep and exit: the whole file")
    -- no rapidjson: every save is a full one, as before
    Grimmory.fingerprint = real_fp
    local m3, r3 = counts()
    pend["995"] = { gz_note = "no rapidjson" }
    plugin:save()
    plugin:save()
    local m4, r4 = counts()
    check(m4 == m3 + 2 and r4 == r3, "without rapidjson: gzreader.lua every time, as before")
    for _i, k in ipairs({ "999", "996", "995" }) do pend[k] = nil end
    plugin.store.downloads["998"] = nil
    plugin:saveFull()
    for name, obj in pairs(files) do obj.flush = orig[name] end
end

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

    -- (the panel's tiles only: its widgets stay stubs here)
    local widget_mods = { "ui/widget/focusmanager", "ui/widget/iconwidget", "ui/widget/menu", "ui/widget/textboxwidget",
        "ui/widget/textwidget", "ui/widget/container/inputcontainer", "ui/gesturerange", "ui/font", "ffi/blitbuffer" }
    local kept = {}
    for _i, m in ipairs(widget_mods) do
        kept[m] = package.loaded[m]
        if type(kept[m]) ~= "table" then package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    local Panel = require("gzreader_panel")
    for _i, m in ipairs(widget_mods) do package.loaded[m] = kept[m] end
    local panel_shown, panel_show = 0, Panel.show
    Panel.show = function() panel_shown = panel_shown + 1; return true end
    hui.menu:onShowMenu() -- what ZenOS's Home page calls for the Menu key
    hui.menu:onKeyPressShowMenu()
    check(full_shown == 0 and panel_shown == 2, "Menu key on Home: the quick panel instead of ZenOS's or the GZreader menu")
    local HomeMenu = require("gzreader_homemenu")
    local NM = require("ui/network/manager"); NM.isWifiOn = NM.isWifiOn or function() return true end
    local NG = require("gzreader_nightguard"); local ng_applies = NG.applies; NG.applies = function() return true end
    local function labels(list)
        local out = {}
        for _i, t in ipairs(list) do out[#out + 1] = t.label end
        return "|" .. table.concat(out, "|") .. "|"
    end
    local controls = labels(Panel.controls(hplug))
    NG.applies = ng_applies
    check(controls:match("|Wi%-Fi on|") and controls:match("|Restart|") and controls:match("|Sleep|") and controls:match("|Settings|")
        and controls:match("|Exit to Kindle|") and not controls:match("Night mode"),
        "panel controls: Wi-Fi, Restart, Sleep, Settings, Exit; no night mode on a Kindle 3… " .. controls)
    local saved_ld = hplug.store.logging_disabled
    hplug.store.logging_disabled = true
    local no_diag = labels(Panel.controls(hplug))
    hplug.store.logging_disabled = nil
    check(not no_diag:match("Diagnostics") and labels(Panel.controls(hplug)):match("|Diagnostics|"), "Diagnostics tile only while diagnostics is on")
    hplug.store.logging_disabled = saved_ld
    local home = labels(Panel.homeTiles(hplug, nil))
    check(home:match("|Continue|") and home:match("|Send books|") and home:match("|Sort|") and not home:match("|More|")
        and not home:match("Manage") and not home:match("Contents"), "panel at Home: Continue, Send books, Sort (no More); Manage only with a book… " .. home)
    -- Settings opens ZenOS's Settings page with the ZenOS plugin instance
    local opened = {}
    package.loaded["modules/settings/zen_settings_page"] = { show = function(z, o) opened[#opened + 1] = { z = z, o = o } end }
    package.loaded["apps/filemanager/filemanager"] = { instance = { zenos = "ZEN", menu = hui.menu } }
    for _i, t in ipairs(Panel.controls(hplug)) do
        if t.label == "Settings" then t.run() end
    end
    check(#opened == 1 and opened[1].z == "ZEN" and opened[1].o == nil, "Settings tile -> Settings page")
    package.loaded["modules/settings/zen_settings_page"] = nil; package.loaded["apps/filemanager/filemanager"] = nil
    -- Settings → Interface → Quick panel: tiles shown or hidden, by group
    Panel.showAll()
    Panel.setShown("controls", "rotate", false)
    Panel.setShown("home", "sort", false)
    Panel.setShown("home", "send", false)
    for _i, id in ipairs({ "home", "settings", "exit" }) do Panel.setShown("controls", id, false) end
    local c2, h2 = labels(Panel.controls(hplug)), labels(Panel.homeTiles(hplug, nil))
    check(not c2:match("|Rotate|") and c2:match("|Restart|") and not h2:match("|Sort|") and not h2:match("|Send books|") and h2:match("|Continue|"),
        "hidden tiles aren't on the panel; the others are… " .. c2 .. " " .. h2)
    check(c2:match("|Home|") and c2:match("|Settings|") and c2:match("|Exit to Kindle|") and Panel.isShown("controls", "settings"),
        "Home, Settings and Exit to Kindle can't be hidden")
    local hidden = G_reader_settings:readSetting("gzreader_panel_hidden") or {}
    check(hidden["controls:rotate"] and hidden["home:sort"] and not hidden["controls:settings"] and not hidden["controls:home"],
        "kept as group:tile, only the hideable ones")
    check(Panel.isShown("book", "music") and not Panel.isShown("home", "sort"), "Music in a book is its own tick (Home's Music is separate)")
    local fakeui = { handleEvent = function() end, view = {}, document = { info = { has_pages = true } } }
    Panel.setShown("book", "gotopage", false)
    check(not labels(Panel.bookTiles(hplug, fakeui)):match("Go to page") and labels(Panel.bookTiles(hplug, fakeui)):match("|Contents|"),
        "a book's tiles hidden too")
    -- Layout opens KOReader's bottom menu with force: ZenOS's Zen mode blocks a
    -- plain ShowConfigMenu on touch Kindles (the tile did nothing on a Paperwhite)
    local forced, sent = nil, {}
    local layoutui = { handleEvent = function(_s, ev) sent[#sent + 1] = ev.handler end, view = {},
        document = { info = { has_pages = true } },
        config = { onShowConfigMenu = function(_s, force) forced = force; return true end } }
    for _i, t in ipairs(Panel.bookTiles(hplug, layoutui)) do
        if t.id == "layout" then t.run() end
    end
    check(forced == true and #sent == 0, "Layout tile: the layout menu opened with force (Zen mode on a touch Kindle doesn't block it)")
    -- Music and Audiobook: only while one plays (or is paused), in both groups; they open its player
    do
        local saved_audio = require("gzreader_touch").audio
        require("gzreader_touch").audio = function() return true end
        local M, AB = require("gzreader_music"), require("gzreader_audiobook")
        local saved_m, saved_ab, saved_open, saved_np = M.current, AB.current, AB.open, require("gzreader_musictab").nowPlaying
        M.current, AB.current = nil, nil
        local h0, b0 = labels(Panel.homeTiles(hplug, nil)), labels(Panel.bookTiles(hplug, fakeui))
        check(not h0:match("Music") and not h0:match("Audiobook") and not b0:match("Music") and not b0:match("Audiobook"),
            "nothing playing: no Music or Audiobook tile (music and audiobooks are in the Catalog) " .. h0)
        local opened_p = {}
        require("gzreader_musictab").nowPlaying = function() opened_p[#opened_p + 1] = "cd" end
        AB.open = function(_p, book) opened_p[#opened_p + 1] = "ab" .. tostring(book.id) end
        M.current = { playing = true }
        AB.current = { book = { id = 7 }, playing = false }
        local h1, b1 = labels(Panel.homeTiles(hplug, nil)), labels(Panel.bookTiles(hplug, fakeui))
        check(h1:match("|Music ▶|") and h1:match("|Audiobook|") and b1:match("|Music ▶|") and b1:match("|Audiobook|"),
            "music playing, an audiobook paused: both tiles, at Home and in a book " .. h1 .. " " .. b1)
        for _i, t in ipairs(Panel.homeTiles(hplug, nil)) do if t.id == "music" or t.id == "audiobook" then t.run() end end
        check(table.concat(opened_p, ",") == "cd,ab7", "…each opens its player " .. table.concat(opened_p, ","))
        M.current, AB.current, AB.open = saved_m, saved_ab, saved_open
        require("gzreader_musictab").nowPlaying = saved_np
        require("gzreader_touch").audio = saved_audio
    end
    local item = Panel.settingsItem()
    local subs = {}
    for _i, s in ipairs(item.sub_item_table) do subs[#subs + 1] = s.text end
    check(item.text == "Quick panel" and table.concat(subs, "|") == "Controls|Home|This book|Show every tile",
        "the settings: Quick panel → Controls, Home, This book, Show every tile… " .. table.concat(subs, "|"))
    local function row(group_i, label)
        for _i, r in ipairs(item.sub_item_table[group_i].sub_item_table) do
            if r.text == label or r.text:match("^" .. label:gsub("%-", "%%-") .. " %(") then return r end
        end
    end
    local exit_row, rot_row, diag_row = row(1, "Exit to Kindle"), row(1, "Rotate"), row(1, "Diagnostics")
    check(exit_row and exit_row.enabled_func() == false and exit_row.checked_func() and rot_row and rot_row.enabled_func() and not rot_row.checked_func()
        and diag_row and diag_row.text:match("while logging is on"),
        "fixed tiles ticked and greyed out; the others tick; a tile that only sometimes shows says when")
    rot_row.callback()
    check(Panel.isShown("controls", "rotate") and labels(Panel.controls(hplug)):match("|Rotate|"), "ticking a tile puts it back")
    exit_row.callback()
    check(Panel.isShown("controls", "exit"), "…and a fixed one stays")
    local NetM = require("gzreader_net"); local was_usb = NetM.usb
    NetM.usb = true
    local usb_item = Panel.settingsItem()
    local usb_rows = {}
    for _i, r in ipairs(usb_item.sub_item_table[1].sub_item_table) do usb_rows[#usb_rows + 1] = r.text end
    for _i, r in ipairs(usb_item.sub_item_table[2].sub_item_table) do usb_rows[#usb_rows + 1] = r.text end
    usb_rows = "|" .. table.concat(usb_rows, "|") .. "|"
    NetM.usb = was_usb
    check(usb_rows:match("|Sync|") and not usb_rows:match("|Updates|") and not usb_rows:match("|Send books|"),
        "a Kindle without Wi-Fi: only the tiles it can have are listed… " .. usb_rows)
    for _i, id in ipairs({ "continue", "search", "history", "view", "manage", "music", "audiobook", "tasks" }) do Panel.setShown("home", id, false) end
    check(#Panel.homeTiles(hplug, { path = "/mnt/us/a.epub" }) == 0, "every Home tile hidden: an empty group (the panel leaves it out)")
    item.sub_item_table[4].callback()
    check(G_reader_settings:readSetting("gzreader_panel_hidden") == nil and labels(Panel.homeTiles(hplug, nil)):match("|Sort|"),
        "Show every tile: all back")
    -- in ZenOS's Settings → Interface: Quick panel in place of Controls and Launcher, no Zen mode toggle
    local zroot = debug.getinfo(Panel.controls, "S").source:sub(2):gsub("gzreader%.koplugin/gzreader_panel%.lua$", "zenos.koplugin/")
    local function src(rel)
        local zf = io.open(zroot .. rel, "rb")
        local s = zf and zf:read("*a") or ""
        if zf then zf:close() end
        return s
    end
    local iface = src("modules/settings/sections/interface_settings.lua")
    check(iface:find("GzPanel.settingsItem()", 1, true) and not iface:find("sections/menu_settings", 1, true)
        and not iface:find("app_launcher_item", 1, true) and not iface:find('text = _("Zen mode")', 1, true)
        and iface:find('text = _("Blur menu background")', 1, true),
        "Settings → Interface: Quick panel (no Controls, no Launcher), Blur menu background kept, no Zen mode toggle")
    check(src("config/manager.lua"):find("if cfg.features.zen_mode ~= true then\n        cfg.features.zen_mode = true", 1, true),
        "Zen mode turned back on at start if it was off")
    local da = src("common/dispatch_action.lua")
    local fn_src = da:match("(function M%.onToggleZenMode%(plugin%).-\nend\n)")
    local zsaved, zapplied = 0, nil
    local M = {}
    local env = setmetatable({ M = M, save_config = function() zsaved = zsaved + 1 end, _ = function(s) return s end,
        require = function(name)
            if name == "modules/settings/zen_settings_apply" then return { apply_feature_toggle = function(_p, _k, v) zapplied = v end } end
            if name == "ui/uimanager" then return { show = function() end } end
            if name == "ui/widget/infomessage" then return { new = function() return {} end } end
            return require(name)
        end }, { __index = _G })
    local chunk = fn_src and load(fn_src, "onToggleZenMode", "t", env)
    if chunk then chunk() end
    local zp = { config = { features = { zen_mode = true } } }
    if M.onToggleZenMode then M.onToggleZenMode(zp) end
    local stayed = zp.config.features.zen_mode == true and zsaved == 0
    zp.config.features.zen_mode = false
    if M.onToggleZenMode then M.onToggleZenMode(zp) end
    check(M.onToggleZenMode and stayed and zp.config.features.zen_mode == true and zapplied == true and zsaved == 1,
        "ZenOS's Toggle Zen Mode action (a gesture) keeps it on, and turns it on if it was off")
    Panel.showAll()
    -- More: the full Home menu, still without KOReader settings or night mode
    NG.applies = function() return true end
    local items = HomeMenu.items(hplug)
    NG.applies = ng_applies
    local all = {}
    for _i, it in ipairs(items) do all[#all + 1] = it.text or it.text_func() end
    all = table.concat(all, "|")
    check(all:match("Continue reading") and not all:match("KOReader settings") and not all:match("Night mode"),
        "More (the Home menu): no KOReader settings, no night mode on a Kindle 3… " .. all)
    HomeMenu.open = nil

    hui.menu._gz_full = true; hui.menu:onShowMenu(); hui.menu._gz_full = nil
    check(full_shown == 1 and panel_shown == 2, "All settings reaches the original full menu")
    Panel.show = panel_show

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
    -- a holder that ended without letting go (a player that couldn't start
    -- again after a skip): let go of at the next check, the Kindle sleeps
    local player = { playing = true }
    Awake.hold(player, { what = "audiobook", still = function() return player.playing end })
    Awake.hold("other", { what = "download", still = function() return true end })
    player.playing = false
    Awake.prune()
    check(not Awake.held(player) and Awake.held("other") and Awake.who() == "download",
        "staying awake: a holder that has ended is let go of, the others kept")
    Awake.release("other")
    check(cmds[#cmds]:match("preventScreenSaver 0"), "…and the Kindle may sleep again")
    -- the wall clock set while something is held (a Nook's run-down clock): the time held still right
    local mono, logged = 100, {}
    local orig_now = Awake.now
    Awake.now = function() return mono end
    Awake.hold("phone", { what = "phone page" })
    mono = 180
    local Log = require("gzreader_log")
    local orig_info = Log.info
    Log.info = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    Awake.release("phone")
    Log.info = orig_info
    Awake.now = orig_now
    check(logged[1] and logged[1]:match("after 80s$"), "staying awake: timed on a clock that doesn't jump (" .. tostring(logged[1]) .. ")")
    check(type(Awake.now()) == "number", "…which is there")
    Awake.exec = exec
end

print("Book-open timing only while diagnostic logging is on")
do
    local Log = require("gzreader_log")
    local OT = require("gzreader_opentiming")
    local saved_enabled, saved_cur = Log.enabled, OT.cur
    local opened = WORK .. "/timed-book.epub"
    local tbf = io.open(opened, "wb"); tbf:write("x"); tbf:close()
    Log.enabled = false
    OT.cur = { file = "an earlier book" }
    OT.start(opened)
    check(OT.cur == nil, "logging off: a book opening isn't measured (no /proc reads, no timing)")
    Log.enabled = true
    OT.start(opened)
    check(OT.cur and OT.cur.file == opened and OT.cur.size == 1 and OT.cur.t0, "logging on: the book opening is measured")
    Log.enabled, OT.cur = saved_enabled, saved_cur
    os.remove(opened)
end

print("Shelves")
do
    local list = plugin.api:listShelves()
    check(list and #list == 4 and list[1].name == "Kindle" and list[4].magic == true, "shelves and smart shelves listed")
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
    check(g:match("|Sync highlights and notes|Keep connections open %(experimental%)|Rebuild library|Reconnect"),
        "Grimmory section: Keep connections open after the sync switches, then Rebuild library " .. g)
    do -- Rebuild library: the index from Grimmory again, the saved lists forgotten, Wi-Fi on first
        local NetR = require("gzreader_net")
        local IndexR, LCR = require("gzreader_index"), require("gzreader_listcache")
        local was_run, was_build, was_clear = NetR.run, IndexR.build, LCR.clear
        local why, cleared, built
        NetR.run = function(fn, o) why = o and o.reason; fn() end
        LCR.clear = function() cleared = true end
        IndexR.build = function(_p, show, cb) built = show; cb({ total = 189 }) end
        captured.info = nil
        local rb
        for _i, it in ipairs(plugin:menuItems()) do if it.text == "Rebuild library" then rb = it end end
        rb.callback()
        check(why == "rebuilding the library" and cleared and built == true and captured.info == "Library rebuilt: 189 books.",
            "Rebuild library: Wi-Fi on, saved lists forgotten, the library list built again (" .. tostring(captured.info) .. ")")
        NetR.run, IndexR.build, LCR.clear = was_run, was_build, was_clear
    end
    local gen = plugin:sectionItems("general")
    check(gen.wifi and gen.wifi.text == "Wi-Fi" and #gen.wifi.sub_item_table == 3, "General: Wi-Fi (On, Off, Auto)")
    local d = texts(gen.diagnostics)
    check(d:match("|Diagnostic logging|Send debug reports automatically|Send diagnostic log to the developer|Send diagnostic log to a browser %(QR code%)|Save diagnostic log %(USB%)|"),
        "General: logging, automatic debug reports, send (to the developer or a browser) and save the log (no usage statistics) " .. d)
    check(texts(plugin:sectionItems("reader")) == "|Read aloud|Test audiobook playback|Pause when headphones are unplugged|Find the headphone jack|Lay out new books while charging|",
        "Reader: Read aloud, Test audiobook playback, the headphones, laying out new books while charging")
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
    local root = texts(Browser.rootItems({ api = plugin.api, plugin = plugin }))
    check(root:match("|Grimmory|$") and not root:match("Audiobooks") and table.concat(require("gzreader_catalog").sections(), ",") == "books",
        "Paperwhite: the Catalog is the Books page alone (no Audiobooks or Music) " .. root)
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
    G_reader_settings:delSetting("gzreader_launcher_v3")
    plugin:addLauncherEntries()
    plugin:addLauncherEntries()
    local n_audio = 0
    for _i, d in ipairs(Grimmory.LAUNCHER) do if d[5] == "audio" then n_audio = n_audio + 1 end end
    local labels, ctx = {}, {}
    for _i, e in ipairs(cfg.entries) do
        labels[#labels + 1] = e.label
        ctx[e.label] = e.gz_context or "both"
    end
    check(#cfg.entries == #Grimmory.LAUNCHER - (require("gzreader_touch").audio() and 0 or n_audio),
        "launcher: every GZreader entry once (Music ones on Kindles with audio) (" .. table.concat(labels, ",") .. ")")
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
    check(texts(plugin:sectionItems("reader")) == "|Read aloud|Test audiobook playback|Pause when headphones are unplugged|Find the headphone jack|Lay out new books while charging|",
        "Kindle Touch: Read aloud, the audiobook test, the headphones, laying out new books")
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
    local rows = { { { text = "Mark as read" } }, { { text = "Edit  >", _gz_manage_hide = true } },
        { { text = "More  >" } }, { { text = "Book information" } } }
    check(type(prepend.filter) == "function" and prepend.filter(rows) == rows and #rows == 3
        and rows[1][1].text == "Mark as read" and rows[2][1].text == "More  >" and rows[3][1].text == "Book information",
        "…and without ZenOS's Edit submenu (Delete is already there); the other rows stay, in order")
    do
        local zen = debug.getinfo(HM.manage, "S").source:sub(2):gsub("gzreader%.koplugin/gzreader_homemenu%.lua$",
            "zenos.koplugin/modules/filebrowser/patches/")
        local function read(name)
            local fh = io.open(zen .. name, "rb")
            local t = fh and fh:read("*a") or ""
            if fh then fh:close() end
            return t
        end
        local dialog_src, menu_src = read("context_menu_file_dialog.lua"), read("context_menu.lua")
        local at = dialog_src:find("callback = showEditSubmenu,", 1, true)
        check(at and dialog_src:sub(at, at + 160):find("_gz_manage_hide = true,", 1, true)
            and menu_src:find("prepend.filter(options.buttons)", 1, true),
            "ZenOS marks its Edit row and lets Manage filter the menu")
    end
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

print("Holding a book in the Downloads tab: Manage, as on Home")
do
    local HM = require("gzreader_homemenu")
    local bookpath = WORK .. "/home/GZreader/hold-me.epub"
    local fh = io.open(bookpath, "wb"); fh:write("x"); fh:close()
    local was_fm, was_showing = package.loaded["apps/filemanager/filemanager"], rawget(plugin, "downloadsTabShowing")
    local own_hold, dialog_item, prepend_then
    local FakeFM = { setupLayout = function(layout_fm)
        layout_fm.file_chooser = {
            onFileHold = function(_fc, item) own_hold = item end,
            showFileDialog = function(_fc, item) dialog_item = item; prepend_then = rawget(_G, "__GZ_CONTEXT_PREPEND") end,
        }
    end }
    package.loaded["apps/filemanager/filemanager"] = FakeFM
    check(HM.hookHold() == true and HM.hookHold() == false, "hooked into the file manager's layout once")
    local fmi = { gzreader = plugin }
    FakeFM.setupLayout(fmi)
    local fc = fmi.file_chooser
    local showing = true
    plugin.downloadsTabShowing = function() return showing end
    local book = { path = bookpath, is_file = true, text = "hold-me.epub" }
    check(fc:onFileHold(book) == true and own_hold == nil and dialog_item == book
        and type(prepend_then) == "table" and prepend_then[2].text:match("Delete from this Kindle$")
        and type(prepend_then.filter) == "function",
        "a book in Downloads: Manage (Open and Delete at the top of ZenOS's menu for that book, without Edit)")
    rawset(_G, "__GZ_CONTEXT_PREPEND", nil)
    dialog_item = nil
    showing = false
    fc:onFileHold(book)
    check(own_hold == book and dialog_item == nil, "another folder: ZenOS's own menu, as before")
    own_hold = nil
    showing = true
    local folder = { path = WORK .. "/home/GZreader", is_file = false }
    fc:onFileHold(folder)
    check(own_hold == folder and dialog_item == nil, "a folder in Downloads: its own menu")
    own_hold = nil
    FakeFM.instance = { selected_files = { [bookpath] = true } }
    fc:onFileHold(book)
    check(own_hold == book and dialog_item == nil, "select mode: KOReader's own (the selection's menu)")
    FakeFM.instance, own_hold = nil, nil
    FakeFM.setupLayout(fmi) -- laid out again (a rotation): a new file list
    check(fmi.file_chooser ~= fc and fmi.file_chooser:onFileHold(book) == true and dialog_item == book and own_hold == nil,
        "laid out again (rotation): still Manage")
    rawset(_G, "__GZ_CONTEXT_PREPEND", nil)
    package.loaded["apps/filemanager/filemanager"], plugin.downloadsTabShowing = was_fm, was_showing
    os.remove(bookpath)
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

print("A book's page")
do
    local wm = { "ui/widget/container/inputcontainer", "ui/widget/focusmanager", "ui/widget/buttontable", "ui/widget/scrolltextwidget" }
    local kept = {}
    for _i, m in ipairs(wm) do
        kept[m] = package.loaded[m]
        if type(kept[m]) ~= "table" then package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end }) end
    end
    -- (a failed load earlier, with the real widgets, left a marker behind)
    if type(package.loaded["gzreader_bookpage"]) ~= "table" then package.loaded["gzreader_bookpage"] = nil end
    local okbp, BP = pcall(require, "gzreader_bookpage")
    for _i, m in ipairs(wm) do package.loaded[m] = kept[m] end
    check(okbp, "the book page loads " .. tostring(not okbp and BP or ""))
    local detail = plugin.api:getBookDetail(5)
    check(type(detail) == "table" and detail.goodreadsRating == 4.12 and type(detail.categories) == "table", "Grimmory's book page: rating, genres…")
    if okbp then
        local f = BP.facts({ title = "Book 05", authors = { "Author 2" }, seriesName = "Saga / Part One", seriesNumber = 2.0,
            primaryFileType = "EPUB", fileSizeKb = 1536 }, detail)
        check(f.authors == "Author 2" and f.series == "Book 2 of Saga / Part One" and f.rating == "Goodreads ★ 4.12 · 1,234 ratings"
            and f.genres == "Adventure · Fantasy" and f.facts == "320 pages · 2001 · Mock House · EPUB · 1.5 MB",
            "what it shows: authors, series, Goodreads rating, genres, the facts")
        check(BP.description({ description = "<p>A <b>bold</b> start.</p>" }):match("A bold start") and BP.description({}) == nil,
            "its description as text")
        local bare = BP.facts({ title = "x" }, nil)
        check(bare.rating == nil and bare.genres == nil and bare.facts == nil, "nothing known: nothing made up")
        -- the 5-way's keys (FocusManager's, set before init) are kept
        local page = { key_events = { Press = { { "Press" } }, FocusUp = { { "Up" } } }, build = function() end }
        local oki, ierr = pcall(BP.init, page)
        check(oki and page.key_events.Press and page.key_events.FocusUp and page.key_events.Close,
            "book page: Press and the arrows still work on a Kindle with keys (Download can be pressed) " .. tostring(ierr or ""))
    end
end

print("A book's page: the cover the list shows")
do
    if type(package.loaded["gzreader_bookpage"]) ~= "table" then package.loaded["gzreader_bookpage"] = nil end
    local okbp, BP = pcall(require, "gzreader_bookpage")
    check(okbp and BP.coverImage, "the book page loads " .. tostring(not okbp and BP or ""))
    if okbp then
        local Covers = require("gzreader_covers")
        local orig_image = Covers.image
        local asked
        Covers.image = function(id, kind, w, h)
            asked = { id = id, kind = kind, w = w, h = h }
            return { copy = function() return "a copy of the list's cover" end }
        end
        os.remove(Covers.path(9071)); os.remove(Covers.dir() .. "/9071.none")
        local none = BP.coverImage({ id = 9071, coverUpdatedOn = "2026-01-01" }, 96, 144)
        check(none == nil and asked == nil, "no cover on the Kindle: none drawn (it's fetched)")
        local f = io.open(Covers.path(9071), "wb"); f:write("jpeg"); f:close()
        local img = BP.coverImage({ id = 9071, coverUpdatedOn = "2026-01-01" }, 96, 144)
        check(img and img.image == "a copy of the list's cover" and img.image_disposable == true
            and asked and asked.id == 9071 and asked.w == 96 and asked.h == 144,
            "the Grimmory tab's cached cover is the page's cover (a copy, sized for the page), whatever the old cache has")
        os.remove(Covers.path(9071))
        Covers.image = orig_image
        -- Wi-Fi off (the list opens from what's on the Kindle): on first, for the page and for Download
        local Net = require("gzreader_net")
        local was_run, was_new, was_fetch, was_conn = Net.run, rawget(BP, "new"), BP.fetch, Net.connected
        local why, fetched = {}, nil
        Net.run = function(fn, o) why[#why + 1] = o and o.reason; fn() end
        BP.new = function(_s, o) return o end
        BP.fetch = function(pg) fetched = pg end
        local shown = BP.show({ api = plugin.api }, { id = 5, title = "Book 05" })
        check(why[1] == "a book's details" and fetched == shown, "a book's page turns Wi-Fi on before asking for its details and cover")
        local Dl = require("gzreader_download")
        local was_start, started = Dl.start, nil
        Dl.start = function(_p, book) started = book end
        Net.connected = function() return false end
        plugin:downloadAndOpen({ id = 9072, title = "Offline", primaryFileName = "offline.epub", primaryFileType = "EPUB" }, nil)
        check(why[2] == "downloading a book" and started and started.id == 9072, "Download with Wi-Fi off: on first, then the download starts")
        why, started = {}, nil
        Net.connected = function() return true end
        plugin:downloadAndOpen({ id = 9073, title = "Online", primaryFileName = "online.epub", primaryFileType = "EPUB" }, nil)
        check(#why == 0 and started and started.id == 9073, "Wi-Fi on: straight to the download")
        Net.run, BP.fetch, Net.connected, Dl.start = was_run, was_fetch, was_conn, was_start
        rawset(BP, "new", was_new)
    end
end

print("The Grimmory tab's selection stays where it is (keys)")
do
    local F = require("gzreader_focus")
    check(F.keyOf({ book = { id = 5 }, text = "x" }) == "book:5" and F.keyOf({ gz_id = "all", text = "All" }) == "id:all"
        and F.keyOf({ gz_action = "search", text = "S" }) == "action:search" and F.keyOf({ text = "Libraries" }) == "text:Libraries"
        and F.keyOf(nil) == nil, "what's selected is known by what it is: a book's id, a card, a row's text")
    -- a menu drawn three to a row, the page putting the selection on the first
    -- thing (as the bookshop and the list views do)
    local function books(ids)
        local t = {}
        for i, id in ipairs(ids) do t[i] = { book = { id = id }, text = "Book " .. id } end
        return t
    end
    local function newMenu(items)
        local m = { item_table = items, page = 1, drawn = 0 }
        function m:moveFocusTo(x, y) self.selected = { x = x, y = y } end
        function m:updateItems()
            self.drawn = self.drawn + 1
            self.layout = {}
            for i, e in ipairs(self.item_table) do
                local r = math.floor((i - 1) / 3) + 1
                self.layout[r] = self.layout[r] or {}
                table.insert(self.layout[r], { entry = e })
            end
            self.selected = { x = 1, y = 1 }
        end
        return m
    end
    local function on(m) local c = F.current(m); return c and c.key end
    local m = newMenu(books({ 1, 2, 3, 4, 5, 6, 7 }))
    F.apply(m, true)
    m:updateItems()
    check(on(m) == "book:1", "first drawn: where the page puts it")
    m:updateItems()
    check(on(m) == "book:1", "not moved: a redraw places it as the page always did")
    m.selected = { x = 2, y = 2 } -- the 5-way, down to book 5
    m:updateItems()
    check(on(m) == "book:5" and m.selected.x == 2 and m.selected.y == 2,
        "moved, then the page drawn again (covers in, the bookshop's lists in, a download): still on book 5")
    m:updateItems()
    check(on(m) == "book:5", "and at every redraw after that")
    table.insert(m.item_table, 1, { book = { id = 99 }, text = "Book 99" })
    m:updateItems()
    check(on(m) == "book:5" and m.selected.x == 3 and m.selected.y == 2, "a book added before it: still on book 5, where it is now")
    -- Grimmory's fresh copy of the list replaces the saved one
    local fresh = books({ 99, 5, 1, 2 })
    local at = F.carry(m, fresh)
    check(at == 2, "the fresh copy is shown from book 5's place " .. tostring(at))
    m.item_table = fresh
    m:updateItems()
    check(on(m) == "book:5" and m.selected.x == 2 and m.selected.y == 1, "the fresh copy: still on book 5")
    local gone = books({ 10, 11 })
    check(F.carry(m, gone) == nil, "book 5 not in the fresh copy: shown from the start")
    -- not moved since: the fresh copy as before (from the first)
    local m2 = newMenu(books({ 1, 2, 3 }))
    F.apply(m2, true)
    m2:updateItems()
    check(F.carry(m2, books({ 1, 2, 3 })) == nil and m2._gz_focus_want == nil, "not moved: the fresh copy as before")
    -- another list opened: where it starts as before
    local m3 = newMenu(books({ 1, 2, 3, 4 }))
    F.apply(m3, true)
    m3:updateItems()
    m3.selected = { x = 3, y = 1 }
    m3.item_table = books({ 7, 8 })
    m3:updateItems()
    check(on(m3) == "book:7", "another list: from its start")
    local touch = newMenu(books({ 1, 2 }))
    local before = touch.updateItems
    F.apply(touch, false)
    check(touch.updateItems == before and not touch._gz_focus, "touch Kindles: nothing selected, nothing changed")
end

print("A download shows in the Downloads tab when it's on screen")
do
    local was_fm = package.loaded["apps/filemanager/filemanager"]
    local UIM = require("ui/uimanager")
    local was_stack = UIM._window_stack
    local refreshed = 0
    local fc = { path = WORK .. "/library/", refreshPath = function() refreshed = refreshed + 1 end }
    local fm = { file_chooser = fc, covers_fullscreen = true }
    package.loaded["apps/filemanager/filemanager"] = { instance = fm }
    local p = { store = { library_dir = WORK .. "/library" } }
    setmetatable(p, { __index = plugin })
    UIM._window_stack = { { widget = fm }, { widget = { text = "Downloading…" } } }
    check(p:refreshDownloadsTab() == true and refreshed == 1, "the Downloads tab on screen (a message over it): shown again with the book")
    UIM._window_stack = { { widget = fm }, { widget = { name = "home", covers_fullscreen = true } } }
    check(p:refreshDownloadsTab() == false and refreshed == 1, "Home over it: left alone")
    UIM._window_stack = { { widget = fm }, { widget = { _gz_navbar_tab_id = "ct_grimmory" } } }
    check(p:refreshDownloadsTab() == false and refreshed == 1, "the Grimmory tab over it: left alone")
    UIM._window_stack = { { widget = fm } }
    fc.path = WORK .. "/elsewhere"
    check(p:refreshDownloadsTab() == false and refreshed == 1, "another folder in the file manager: left alone")
    package.loaded["apps/filemanager/filemanager"] = was_fm
    UIM._window_stack = was_stack
end

print("Kindle DX: four shelves in Downloads, two on Home")
do
    local Device = require("device")
    local was_model, was_screen = Device.model, Device.screen
    local Touch = require("gzreader_touch")
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    -- (a failed load earlier left a marker behind; its widgets stubbed while it loads)
    if type(package.loaded["gzreader_shelfview"]) ~= "table" then package.loaded["gzreader_shelfview"] = nil end
    local wm = { "ui/widget/textwidget", "ui/gesturerange", "ui/widget/container/inputcontainer" }
    local kept = {}
    for _i, m in ipairs(wm) do
        kept[m] = package.loaded[m]
        if type(kept[m]) ~= "table" then
            package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end })
        end
    end
    local okv, View = pcall(require, "gzreader_shelfview")
    for _i, m in ipairs(wm) do package.loaded[m] = kept[m] end
    local okg, GzView = pcall(require, "common/gz_view")
    package.path = saved_path
    check(okv and okg, "the shelf views load " .. tostring(not okv and View or not okg and GzView or ""))
    local function as(model, w, h)
        Device.model = model
        Device.screen = { getWidth = function() return w end, getHeight = function() return h end }
    end
    as("Kindle2", 824, 1200)
    check(Touch.dx() and okv and View.maxRows() == 4 and okg and GzView.homeShelves() == 2, "DX: Downloads four shelves a page, Home two")
    as("KindleDXG", 824, 1200)
    check(Touch.dx() and okv and View.maxRows() == 4 and okg and GzView.homeShelves() == 2, "DX Graphite: the same")
    as("Kindle2", 600, 800)
    check(not Touch.dx() and okv and View.maxRows() == nil and okg and GzView.homeShelves() == 1, "Kindle 2 (6\"): as before")
    as("Kindle3", 600, 800)
    check(not Touch.dx() and okv and View.maxRows() == nil and okg and GzView.homeShelves() == 1, "Kindle 3: as before")
    as("KindlePaperWhite3", 1072, 1448)
    check(not Touch.dx() and okv and View.maxRows() == nil and okg and GzView.homeShelves() == 1, "Paperwhite 3: as before")
    Device.model, Device.screen = was_model, was_screen
end

print("Downloads in the bookshelf view: shelves filled by the spines' widths, letters Q to L")
do
    -- (a fresh copy of the view with a plain screen and a stand-in shelf module: widths from the path)
    local Device = require("device")
    local was_screen = Device.screen
    Device.screen = { getWidth = function() return 600 end, getHeight = function() return 800 end, scaleBySize = function(_s, v) return v end }
    local SHELF = "modules/filebrowser/patches/home/widgets/shelf"
    local saved = {}
    for _i, m in ipairs({ "gzreader_shelfview", SHELF, "ui/widget/textwidget", "ui/gesturerange", "ui/widget/container/inputcontainer" }) do
        saved[m] = package.loaded[m]
    end
    local narrow = {}
    package.loaded[SHELF] = { MIN_SPINE = 44, MAX_SPINE = 58, BOARD_H = 14, UNDER_H = 6, PAGES = 6,
        look = function(book) return { w = narrow[book.path] and 44 or 58, h = 100, shade = 0.5 } end }
    for _i, m in ipairs({ "ui/widget/textwidget", "ui/gesturerange", "ui/widget/container/inputcontainer" }) do
        if type(package.loaded[m]) ~= "table" then
            package.loaded[m] = setmetatable({ extend = function(_s, o) return o or {} end }, { __index = function() return function() end end })
        end
    end
    package.loaded["gzreader_shelfview"] = nil
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    local okv, SV = pcall(require, "gzreader_shelfview")
    package.path = saved_path
    if okv then
        local function books(count, narrow_ones)
            local t = {}
            for i = 1, count do
                local p = "/books/" .. i .. ".epub"
                t[i] = { is_file = true, path = p, text = i .. ".epub" }
                narrow[p] = narrow_ones and true or nil
            end
            return t
        end
        local wide = SV.countPerPage(books(60, false), 3, 190, 600)
        local thin = SV.countPerPage(books(60, true), 3, 190, 600)
        check(thin > wide and wide >= 18, "narrow spines: more books on a page (" .. thin .. " against " .. wide .. " of the widest)")
        local all = books(60, true)
        local fits = true
        for first = 0, #all - 1, thin do if not SV.pageFits(all, first, thin, 3, 190, 600) then fits = false end end
        check(fits and not SV.pageFits(all, 0, thin + 4, 3, 190, 600), "every page's books fit on its shelves, and no more than that")
        check(SV.KEYS == 19, "letters on the shelves: Q to L (19), not Del")
        -- no ornament on the first shelf beside the walkman or the CD player
        local okt, Th = pcall(require, "gzreader_shelftheme")
        if okt then
            local function sides(filled, players)
                local t = SV.ornamentRows(filled, 3, players)
                local o = {}
                for r = 1, 3 do o[r] = t[r] and t[r]:sub(1, 1) or "-" end
                return table.concat(o)
            end
            Th.setOrnaments("room"); Th.setCount(1); Th.setSide("right")
            check(sides({ true, false, false }, false) == "r--", "one shelf of books, no player: its ornament on that shelf")
            check(sides({ true, false, false }, true) == "---", "…the walkman or the CD player on the first shelf: no ornament there")
            check(sides({ true, true, false }, true) == "-r-" and sides({ true, true, true }, true) == "--r", "…the shelves under it keep theirs")
            Th.setCount("all")
            check(sides({ true, true, true }, true) == "-rr" and sides({ true, true, true }, false) == "rrr", "one on every shelf: every shelf but the players' one")
            Th.setSide("scattered")
            check(sides({ true, true, true }, true) == "-rl", "scattered: the first under the players on the right, the next on the left")
            Th.setOrnaments("always")
            check(SV.ornamentRoom(190, 1, 3, true) == 0 and SV.ornamentRoom(190, 1, 3, false) > 0 and SV.ornamentRoom(190, 2, 3, true) > 0,
                "an ornament on every page: the players' shelf keeps no room for one, the others do")
            Th.setOrnaments("room"); Th.setCount(1); Th.setSide("right")
        else
            check(false, "the shelf theme loads: " .. tostring(Th))
        end
    else
        check(false, "the shelf view loads: " .. tostring(SV))
    end
    for m, v in pairs(saved) do package.loaded[m] = v end
    Device.screen = was_screen
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

print("Keep-alive inside a background process (one connection for several requests)")
;(function()
    local Api = require("gzreader_api")
    local KPORT = PORT + 70
    os.execute("python3 -I keepalive_server.py " .. KPORT .. " >/dev/null 2>&1 & echo $! > '" .. WORK .. "/keepalive.pid'")
    local sock = require("socket")
    local kbase = "http://127.0.0.1:" .. KPORT
    for _i = 1, 40 do
        local c = sock.tcp(); c:settimeout(0.2)
        if c:connect("127.0.0.1", KPORT) then c:close(); break end
        c:close(); sock.sleep(0.1)
    end
    local function conn(kpath, method)
        local kcode, kdata = Api.rawRequest(method or "GET", kbase .. kpath, method == "POST" and { body = { x = 1 } } or nil)
        return kcode == 200 and type(kdata) == "table" and kdata.conn or nil
    end
    -- outside a background process: a connection per request, as before
    local ka, kb = conn("/n"), conn("/n")
    check(ka and kb and ka ~= kb, "the main process: a new connection for each request (" .. tostring(ka) .. ", " .. tostring(kb) .. ")")
    Api.poolBegin()
    local c1, c2, c3 = conn("/n"), conn("/n"), conn("/n")
    check(c1 and c1 == c2 and c2 == c3 and Api.pool.made == 1 and Api.pool.reused == 2, "in a background process: three requests, one connection")
    local kp1 = conn("/n", "POST")
    local after_post = conn("/n")
    check(kp1 and kp1 ~= c3 and after_post == kp1, "a POST takes a new connection (never sent twice), and leaves it for the next")
    local cl = conn("/close")
    local after_close = conn("/n")
    check(cl == kp1 and after_close and after_close ~= cl, "\"Connection: close\": not kept")
    local d = conn("/drop")
    local after_drop = conn("/n")
    check(d and after_drop and after_drop ~= d, "closed by the server without saying so: sent again on a new connection")
    local idle_was = Api.pool.IDLE_MAX
    Api.pool.IDLE_MAX = 0
    local i1 = conn("/n")
    sock.sleep(0.05)
    local i2 = conn("/n")
    check(i1 and i2 and i1 ~= i2, "idle too long: not used again (the server may have closed it)")
    Api.pool.IDLE_MAX = idle_was
    -- a fault in the keep-alive code itself: the request as before, and keep-alive off for the process
    local Conn = Api._Conn
    local orig = Conn.connect
    Conn.connect = function() error("gzreader_api.lua:1: a fault for the test") end
    local f1 = conn("/n")
    Conn.connect = orig
    local f2, f3 = conn("/n"), conn("/n")
    check(f1 and Api.pool.broken and f2 ~= f3, "a fault in keep-alive itself: the request still goes, keep-alive off after that")
    Api.pool.broken = false
    local before_end = Api.pool.requests
    Api.poolEnd()
    local x, y = conn("/n"), conn("/n")
    check(before_end >= 10 and not Api.pool.on and x ~= y and next(Api.pool.idle) == nil, "after the process's last request: closed, and off")
    local src = io.open(PLUGIN .. "/gzreader_async.lua", "rb")
    local at = src and src:read("*a") or ""
    if src then src:close() end
    local isrc = io.open(PLUGIN .. "/gzreader_index.lua", "rb")
    local it = isrc and isrc:read("*a") or ""
    if isrc then isrc:close() end
    check(at:find("ApiMod.poolBegin()", 1, true) and at:find("ApiMod.poolEnd()", 1, true) and it:find("Api.poolBegin()", 1, true)
        and it:find("Api.poolEnd()", 1, true), "background requests and the library index use it")
    local pf = io.open(WORK .. "/keepalive.pid")
    if pf then os.execute("kill " .. (pf:read("*l") or "") .. " 2>/dev/null"); pf:close(); os.remove(WORK .. "/keepalive.pid") end
end)()

print("The request helper (opt-in): connections kept between background processes")
;(function()
    local Api = require("gzreader_api")
    local Helper = require("gzreader_reqhelper")
    -- Settings → Connections → Grimmory → Keep connections open: off by default
    local was_force = Helper.force
    Helper.force = nil
    check(not Helper.enabled() and not Helper.setting(), "the helper is off by default")
    local item
    for _i, it in ipairs(plugin:menuItems()) do if it.text == "Keep connections open (experimental)" then item = it end end
    local started, was_start = 0, Helper.start
    Helper.start = function() started = started + 1 end
    item.callback()
    check(Helper.enabled() and Helper.setting() and item.checked_func() and gsettings.gzreader_request_helper == true,
        "Settings → Keep connections open: on (kept in KOReader's settings)")
    item.callback()
    check(not Helper.enabled() and not item.checked_func() and gsettings.gzreader_request_helper == nil, "and off again")
    Helper.start = was_start
    Helper.force = was_force
    local hsock = require("socket")
    local UP = PORT + 71
    os.execute("python3 -I keepalive_server.py " .. UP .. " >/dev/null 2>&1 & echo $! > '" .. WORK .. "/keepalive2.pid'")
    local hdir = WORK .. "/reqhelper"
    os.execute("rm -rf '" .. hdir .. "'; mkdir -p '" .. hdir .. "'")
    Helper.dir_override = hdir
    local me = tonumber((io.open("/proc/self/stat"):read("*l") or ""):match("^(%d+)"))
    local function q(x) return "'" .. tostring(x):gsub("'", "'\\''") .. "'" end
    os.execute(string.format("LUA_PATH=%s LUA_CPATH=%s GZ_HELPER_NO_KOENV=1 luajit %s %s %d > %s 2>&1 & echo $! > %s",
        q(package.path), q(package.cpath), q(PLUGIN .. "/gzreader_reqhelper.lua"), q(hdir), me, q(WORK .. "/reqhelper.log"), q(WORK .. "/reqhelper.pid")))
    for _i = 1, 50 do
        local c = hsock.tcp(); c:settimeout(0.2)
        local up = c:connect("127.0.0.1", UP); c:close()
        if up and Helper.endpoint() then break end
        hsock.sleep(0.1)
    end
    local port = Helper.endpoint()
    local lf = io.open(WORK .. "/reqhelper.log")
    check(port ~= nil, "the helper started: listening on 127.0.0.1 " .. tostring(port) .. (port and "" or (" " .. (lf and lf:read("*a") or ""))))
    if lf then lf:close() end
    local base2 = "http://127.0.0.1:" .. UP
    local function upconn(hpath, method)
        local c, d = Api.rawRequest(method or "GET", base2 .. hpath, method == "POST" and { body = { y = 2 } } or nil)
        return c == 200 and type(d) == "table" and d.conn or nil
    end
    if port then
        Api.poolBegin() -- (a background process)
        local u1, u2 = upconn("/n"), upconn("/n")
        local glog = require("gzreader_log")
        local lines_seen, was_info = {}, glog.info
        glog.info = function(...) lines_seen[#lines_seen + 1] = table.concat({ ... }, " ") end
        Api.poolEnd()
        glog.info = was_info
        check(lines_seen[1] == "http: 2 requests, 2 through the request helper, 0 connection(s) here",
            "the log says the requests went through the helper (" .. tostring(lines_seen[1]) .. ")")
        Api.poolBegin() -- (the next one, a moment later)
        local u3 = upconn("/n")
        local up = upconn("/n", "POST")
        check(u1 and u1 == u2 and u2 == u3, "requests from two background processes: one connection to the server, kept by the helper")
        check(up ~= nil, "a POST through it too")
        local c4 = Api.rawRequest("GET", "http://127.0.0.1:" .. (PORT + 72) .. "/nothing")
        check(type(c4) ~= "number", "the server unreachable: a network error, as without the helper (" .. tostring(c4) .. ")")
        -- someone without the token
        local s = hsock.tcp(); s:settimeout(2)
        s:connect("127.0.0.1", port)
        s:send("GET " .. base2 .. "/n HTTP/1.1\r\nHost: x\r\nX-Gz-Helper: wrong\r\n\r\n")
        local line = s:receive("*l") or ""
        s:close()
        check(line:find(" 403 ", 1, true), "without its token: refused (" .. line .. ")")
        Api.poolEnd()
        -- stopped: requests go directly
        local stop_lines, was_info2 = {}, require("gzreader_log").info
        require("gzreader_log").info = function(...) stop_lines[#stop_lines + 1] = table.concat({ ... }, " ") end
        Helper.stop()
        require("gzreader_log").info = was_info2
        check(stop_lines[1] == "request helper: stopped (Wi-Fi off)", "stopping it is logged")
        for _i = 1, 30 do if not io.open(hdir .. "/stop") then break end hsock.sleep(0.1) end
        Api.poolBegin()
        check(Helper.endpoint() == nil and upconn("/n") ~= nil, "stopped: requests go directly again")
        Api.poolEnd()
    end
    -- an endpoint that isn't there (the helper died): directly, and not tried again in that process
    local ef = io.open(hdir .. "/endpoint", "wb"); ef:write(string.format("%d %s %d\n", PORT + 73, "abcd", me)); ef:close()
    Api.poolBegin()
    local direct = upconn("/n")
    check(direct ~= nil and Helper.dead == true, "a helper that doesn't answer: the request goes directly (" .. tostring(direct) .. ")")
    Api.poolEnd()
    Helper.dead, Helper.dir_override = nil, nil
    os.remove(hdir .. "/endpoint")
    for _i, pf in ipairs({ WORK .. "/keepalive2.pid", WORK .. "/reqhelper.pid" }) do
        local h = io.open(pf)
        if h then os.execute("kill " .. (h:read("*l") or "") .. " 2>/dev/null"); h:close(); os.remove(pf) end
    end
end)()

print("Bookshelf view: square cover corners")
do
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    local okg, GV = pcall(require, "common/gz_view")
    package.path = saved_path
    check(okg, "gz_view loads " .. tostring(not okg and GV or ""))
    if okg then
        local saves = 0
        local function save() saves = saves + 1 end
        local cfg = { features = { browser_cover_rounded_corners = true } }
        check(GV.applyCorners(true, cfg, save) and cfg.features.browser_cover_rounded_corners == false
            and cfg.features.gz_rounded_outside_shelf == true and saves == 1,
            "Bookshelf view: rounded corners off, the other views' choice kept, saved")
        check(not GV.applyCorners(true, cfg, save) and saves == 1, "again in the Bookshelf view: nothing to change, not saved")
        check(GV.applyCorners(false, cfg, save) and cfg.features.browser_cover_rounded_corners == true
            and cfg.features.gz_rounded_outside_shelf == nil and saves == 2,
            "another view: rounded corners back on")
        local off = { features = { browser_cover_rounded_corners = false } }
        check(not GV.applyCorners(true, off, save) and off.features.gz_rounded_outside_shelf == nil
            and not GV.applyCorners(false, off, save) and off.features.browser_cover_rounded_corners == false,
            "corners off already: they stay off in every view")
        local fresh = {}
        check(not GV.applyCorners(false, fresh, save) and type(fresh.features) == "table", "no features table yet: no error")
        -- choosing the view through the quick panel's View (M.set) does it too
        local zen = { config = { features = { browser_cover_rounded_corners = true } }, saved = 0 }
        function zen:saveConfig() self.saved = self.saved + 1 end
        local was_zen = rawget(_G, "__ZEN_UI_PLUGIN")
        rawset(_G, "__ZEN_UI_PLUGIN", zen)
        local was_view = G_reader_settings:readSetting("gzreader_view")
        pcall(GV.set, "bookshelf")
        check(zen.config.features.browser_cover_rounded_corners == false and zen.saved == 1,
            "View → Bookshelf: square corners, saved in ZenOS's settings")
        pcall(GV.set, "mosaic_image")
        check(zen.config.features.browser_cover_rounded_corners == true and zen.saved == 2,
            "View → Tiles: rounded corners again")
        rawset(_G, "__ZEN_UI_PLUGIN", was_zen)
        G_reader_settings:saveSetting("gzreader_view", was_view)
    end
    check(io.open(PLUGIN .. "/main.lua"):read("*a"):find("GV.applyCorners()", 1, true) ~= nil,
        "at start: corners set for the view chosen earlier")
end

print("Compressed replies")
check((json.decode(ctl("/state")).gzip_replies or 0) > 0, "JSON lists arrive gzip-compressed and are unpacked (lists above worked)")

print("Requests queued together run in one background process")
;(function()
    local Async = require("gzreader_async")
    local ffi = require("ffi")
    require("ffi/posix_h")
    pcall(ffi.cdef, "int getpriority(int which, unsigned int who);")
    local saved_sync = Async.sync
    Async.sync = false
    local api = { store = {} }
    local other = { store = {} }
    local got, order = {}, {}
    local function job(name, fn, opts)
        Async.run(opts and opts.api or api, function() return fn() end, function(...)
            got[name] = { t = socket.gettime(), ... }
            order[#order + 1] = name
        end, name, opts)
    end
    local pid = function() return tonumber(ffi.C.getpid()), tonumber(ffi.C.getpriority(0, 0)) end
    Async.together(function()
        job("highlights", pid, { nice = true })
        job("place", pid)
        job("elsewhere", pid, { api = other })
        job("slow", function() socket.sleep(2); return pid() end)
        job("bookmarks", pid)
        check(#Async.queue == 5 and not Async.busy, "inside together(): queued, nothing started yet")
    end)
    runLoop(function() return #order == 5 end, 30)
    local p = function(key) return got[key] and got[key][1] end
    check(#order == 5 and p("place") and p("place") == p("slow") and p("slow") == p("bookmarks") and p("bookmarks") == p("highlights"),
        "the same login's four requests: one process (" .. tostring(p("place")) .. ")")
    check(p("elsewhere") and p("elsewhere") ~= p("place"), "another login's: its own process, after")
    check(table.concat(order, ","):find("^place,slow,bookmarks,highlights") ~= nil,
        "in the order queued, the long one (opts.nice) last: " .. table.concat(order, ","))
    check(got.place and got.slow and got.slow.t - got.place.t > 1.5, "each result as soon as it's ready (not when all are done)")
    check(got.place and got.place[2] >= Async.NICE and got.highlights and got.highlights[2] >= Async.NICE_LONG,
        "nice 5 for requests, 10 from the long one on")
    -- the login can't be renewed: every request in the process gets the error
    local denied = { store = {}, ensureToken = function() return false, "signed out" end }
    local errs = {}
    Async.together(function()
        for i = 1, 3 do Async.run(denied, function() return true end, function(res, err) errs[i] = { res, err } end, "d" .. i) end
    end)
    runLoop(function() return errs[3] ~= nil end, 15)
    check(errs[1] and errs[1][1] == nil and errs[1][2] == "signed out" and errs[3] and errs[3][2] == "signed out",
        "login refused: each request gets the error")
    -- one alone, as before
    local alone
    Async.run(api, function() return "x", 2 end, function(a, second) alone = { a, second } end, "alone")
    runLoop(function() return alone ~= nil end, 15)
    check(alone and alone[1] == "x" and alone[2] == 2 and not Async.busy and #Async.queue == 0, "a single request: as before")
    Async.sync = saved_sync
end)()

print("A book's sync when it opens: one go, a moment after the first page")
;(function()
    local Sync = require("gzreader_sync")
    local Async = require("gzreader_async")
    local calls = {}
    local held_seen = {}
    local s = { pull = function(_, interactive, saved) calls[#calls + 1] = "pull:" .. tostring(saved); held_seen[#held_seen + 1] = Async.held end }
    local fake = {
        sync = s, ui = { document = true }, syncEnabled = function() return true end,
        flushPending = function() calls[#calls + 1] = "flush"; held_seen[#held_seen + 1] = Async.held end,
        bookmarks = { reconcile = function() calls[#calls + 1] = "bookmarks" end },
        annotations = { run = function() calls[#calls + 1] = "highlights" end },
    }
    Grimmory.openSync(fake, s, "saved")
    check(table.concat(calls, ",") == "pull:saved,flush,bookmarks,highlights" and held_seen[1] == 1 and held_seen[2] == 1,
        "openSync: place, queued updates, bookmarks, highlights, inside Async.together (" .. table.concat(calls, ",") .. ")")
    calls = {}
    Grimmory.openSync(fake, { pull = function() end }, nil)
    check(#calls == 0, "openSync for a book that has closed since: nothing")
    -- Sync:onReady schedules one sync, OPEN_SYNC_DELAY after the first page
    local scheduled_before = {}
    for fn in pairs(UI.scheduled) do scheduled_before[fn] = true end
    local gz_plugin = { syncEnabled = function() return true end, save = function() end, store = { pending = { progress = {}, sessions = {} } },
        queue = function() end, flushPending = function() end, api = { isPaired = function() return false end } }
    local opened
    gz_plugin.openSync = function(_, sync, saved) opened = { sync, saved } end
    local entry = { grimmory_progress = { pct = 12 } }
    local sync = Sync:new(gz_plugin, { document = { file = "x.epub", info = {} } }, entry, 5)
    sync.startSession = function() end
    sync:onReady()
    local new = {}
    for fn, d in pairs(UI.scheduled) do if not scheduled_before[fn] then new[#new + 1] = d; UI.scheduled[fn] = nil; fn() end end
    check(#new == 1 and new[1] == Sync.OPEN_SYNC_DELAY, "Sync:onReady: one timer (" .. table.concat(new, ", ") .. " s)")
    check(opened and opened[1] == sync and opened[2] and opened[2].pct == 12 and entry.grimmory_progress == nil,
        "…which hands the book's sync to openSync, with Grimmory's progress from the download (once)")
end)()

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

print("Background requests run below the screen's priority")
;(function()
    local Async = require("gzreader_async")
    local ffi = require("ffi")
    pcall(ffi.cdef, "int getpriority(int which, unsigned int who);")
    local saved_sync = Async.sync
    Async.sync = false
    local function niceOf() return tonumber(ffi.C.getpriority(0, 0)) end
    local nice_before = niceOf()
    local plain, long
    Async.run(nil, niceOf, function(v) plain = v or false end, "nice check")
    Async.run(nil, niceOf, function(v) long = v or false end, "nice check (long)", { nice = true })
    runLoop(function() return plain ~= nil and long ~= nil end, 15)
    check(plain and plain >= Async.NICE and Async.NICE >= 5, "a request's process: nice " .. tostring(plain) .. " (page turns go first)")
    check(long and long >= Async.NICE_LONG and Async.NICE_LONG > Async.NICE, "long work (opts.nice): nice " .. tostring(long))
    check(niceOf() == nice_before, "the screen's own process keeps its priority")
    Async.sync = saved_sync
end)()

print("Wi-Fi: on, off, auto")
;(function()
    local UIM = require("ui/uimanager")
    local Net = require("gzreader_net")
    local now = 1000
    Net.clock = function() return now end
    gsettings.gzreader_wifi_on_demand = nil -- default: auto (was "Wi-Fi only when needed", on)
    check(Net.mode() == "auto", "nothing saved: Auto")
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
    -- Wi-Fi the user turns on elsewhere (KOReader's menu, a gesture): On, left alone
    local NM = require("ui/network/manager")
    local saved_on, saved_off = NM.toggleWifiOn, NM.toggleWifiOff
    NM.toggleWifiOn = function() NET.connected = true end
    NM.toggleWifiOff = function() NET.connected = false end
    Net._toggle_on, Net._toggle_off = nil, nil
    Net.adopt() -- installs the toggle hooks
    captured.wifi = {}
    NM:toggleWifiOn()
    check(Net.mode() == "on" and gsettings.gzreader_wifi_mode == "on", "turned on by you elsewhere: Wi-Fi is On (saved)")
    Net.run(function() end)
    Net.adopt()
    now = now + 600
    idle()
    check(NET.connected and #captured.wifi == 0, "Wi-Fi the user turned on is never turned off")
    NM:toggleWifiOff()
    check(Net.mode() == "off", "…until the user turns it off: Off")
    NM.toggleWifiOn, NM.toggleWifiOff = saved_on, saved_off
    check(Net.keptOff(), "turned off by you: remembered (background work leaves it off)")
    local q = 0
    Net.run(function() q = q + 1 end, { quiet = true })
    check(q == 0 and #captured.wifi == 0, "Off: background syncs wait for Wi-Fi")

    -- the settings from before the three modes
    gsettings.gzreader_wifi_mode = nil
    gsettings.gzreader_wifi_kept_off = true
    check(Net.mode() == "off", "until 1.28: turned off by you → Off")
    gsettings.gzreader_wifi_kept_off, gsettings.gzreader_wifi_on_demand = nil, false
    check(Net.mode() == "on", "until 1.28: Wi-Fi only when needed unticked → On")
    gsettings.gzreader_wifi_on_demand = nil
    check(Net.mode() == "auto", "until 1.28: Wi-Fi only when needed ticked (the default) → Auto")
    gsettings.gzreader_wifi_mode = "sometimes"
    check(Net.mode() == "auto", "an unknown saved mode counts as Auto")
    check(Net.nextMode("on") == "off" and Net.nextMode("off") == "auto" and Net.nextMode("auto") == "on",
        "the tile's order: on → off → auto → on")

    -- choosing a mode (the tile, Settings → General → Wi-Fi)
    local switched, events = 0, {}
    local saved_switch, saved_bc = Net._switch, UIM.broadcastEvent
    Net._switch = function() switched = switched + 1; NET.connected = not NET.connected end
    UIM.broadcastEvent = function(_, ev) events[#events + 1] = ev and ev.handler or ev and ev.name or "?" end
    gsettings.gzreader_wifi_kept_off, gsettings.gzreader_wifi_on_demand = true, false
    NET.connected = false
    check(Net.setMode("on") == true and switched == 1 and NET.connected and gsettings.gzreader_wifi_mode == "on",
        "On with Wi-Fi off: saved, Wi-Fi switched on")
    check(gsettings.gzreader_wifi_kept_off == nil and gsettings.gzreader_wifi_on_demand == nil, "the old settings are forgotten once a mode is saved")
    check(#events >= 1 and tostring(events[1]):match("NetworkStateChanged"), "the status bars are told (their Wi-Fi icon) " .. tostring(events[1]))
    check(Net.setMode("on") == false and switched == 1, "On again with Wi-Fi on: nothing switched")
    -- On: something needs Wi-Fi after it went off by itself (sleep, out of range): back on, and it stays on
    NET.connected = false
    captured.wifi = {}
    local bg = 0
    Net.run(function() bg = bg + 1 end, { quiet = true, reason = "test background" })
    now = now + 600
    idle()
    check(bg == 1 and captured.wifi[1] == "on-quiet" and NET.connected and captured.wifi[2] == nil,
        "On: background work turns Wi-Fi on again, and it's never turned off")
    check(Net.setMode("auto") == false and switched == 1 and Net.ours, "Auto with Wi-Fi on: nothing switched now…")
    captured.wifi = {}
    now = now + 600
    idle()
    check(not NET.connected and captured.wifi[1] == "off", "…and it goes off once unused")
    NET.connected = true
    check(Net.setMode("off") == true and switched == 2 and not NET.connected and Net.mode() == "off", "Off with Wi-Fi on: switched off")
    check(Net.setMode("auto") == false and switched == 2 and not NET.connected, "Auto with Wi-Fi off: stays off until something needs it")
    check(Net.setMode("sometimes") == nil and Net.mode() == "auto", "an unknown mode is ignored")

    -- the quick panel's tile
    local Panel = require("gzreader_panel")
    captured.info = nil
    gsettings.gzreader_wifi_mode = "on"
    local t = Panel.wifiTile()
    check(t.id == "wifi" and t.label == "Wi-Fi on" and t.icon == "wifi" and t.on == true, "tile, On: \"Wi-Fi on\", drawn inverted")
    NET.connected = true
    t.run()
    check(Net.mode() == "off" and not NET.connected and captured.info == nil, "a tap: Off (Wi-Fi switched off; KOReader says so)")
    t = Panel.wifiTile()
    check(t.label == "Wi-Fi off" and t.icon == "wifi_off" and not t.on, "tile, Off: \"Wi-Fi off\"")
    t.run()
    check(Net.mode() == "auto" and not NET.connected and captured.info == "Wi-Fi: Auto", "a tap: Auto (says so; Wi-Fi left off) " .. tostring(captured.info))
    t = Panel.wifiTile()
    check(t.label == "Wi-Fi auto" and t.icon == "wifi_auto_off" and not t.on, "tile, Auto with Wi-Fi off: the auto icon, slashed")
    NET.connected = true
    check(Panel.wifiTile().icon == "wifi_auto", "tile, Auto with Wi-Fi on: the auto icon")
    NET.connected = false
    captured.info = nil
    t.run()
    check(Net.mode() == "on" and NET.connected, "a tap: On (Wi-Fi switched on)")

    -- Settings → General → Wi-Fi
    local item = Net.menuItem()
    local names = {}
    for _i, it in ipairs(item.sub_item_table) do names[#names + 1] = it.text end
    check(item.text == "Wi-Fi" and table.concat(names, "|") == "On|Off|Auto (only when needed)" and item.sub_item_table[1].radio,
        "General → Wi-Fi: On, Off, Auto (only when needed) " .. table.concat(names, "|"))
    check(item.mandatory_func() == "On" and item.sub_item_table[1].checked_func() and not item.sub_item_table[3].checked_func(),
        "it shows the mode, and the mode is ticked")
    item.sub_item_table[3].callback()
    check(Net.mode() == "auto" and item.mandatory_func() == "Auto", "choosing Auto there saves it")

    Net._switch, UIM.broadcastEvent = saved_switch, saved_bc
    gsettings.gzreader_wifi_mode, gsettings.gzreader_wifi_kept_off = nil, nil
    gsettings.gzreader_wifi_on_demand = false
    Net._toggle_on, Net._toggle_off = nil, nil
    NET.connected = was
    Net.clock = os.time
    Net.ours, Net.holders, Net.connecting = false, {}, nil
    UI.scheduled = {}
end)()

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
local hold_test = { calls = {}, A = require("gzreader_async") } -- (one local: the main chunk is near Lua's 200)
hold_test.pause, hold_test.resume = hold_test.A.pause, hold_test.A.resume
hold_test.A.pause = function(why) hold_test.calls[#hold_test.calls + 1] = "pause: " .. tostring(why) end
hold_test.A.resume = function(why) hold_test.calls[#hold_test.calls + 1] = "resume: " .. tostring(why) end
do
    local was_opened = reader_opened
    require("apps/reader/readerui"):showReader("/books/x.epub")
    reader_opened = was_opened
end
rplugin:onReaderReady()
check(rplugin.sync ~= nil, "sync attached to Grimmory book")
check(rplugin.store.downloads["3"].file_id == 1003, "file id looked up for a download that lacked it")
for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}   -- initial pull (nothing on server)
hold_test.A.pause, hold_test.A.resume = hold_test.pause, hold_test.resume
check(hold_test.calls[1] == "pause: a book opens" and hold_test.calls[2] == "resume: the book is open",
    "background work waits from the book's opening until its first page: " .. table.concat(hold_test.calls, ", "))
hold_test = nil
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

print("Progress kept at download (first opening, no Wi-Fi)")
NET.connected = false
reader.pos = 0; rplugin.sync.entry.last_pushed_pct = nil
rplugin.sync.entry.grimmory_progress = { epubProgress = { percentage = 20, href = "Text/ch2.xhtml", contentSourceProgressPercent = 25 } }
UI.scheduled = {}
rplugin.sync:onReady()
for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
check(reader.pos == 3700 and rplugin.sync.entry.grimmory_progress == nil,
    "a just-downloaded book opens at Grimmory's place without Wi-Fi; only the first time")
reader.pos = 100
rplugin.sync:onReady()
for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
check(reader.pos == 100, "…not again at the next opening")
NET.connected = true

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

print("The clock from a server's, when it ran down")
do
    local Clock = require("gzreader_clock")
    check(Clock.parseHttpDate("Sat, 07 Nov 2026 06:57:01 GMT") == 1794034621 and Clock.parseHttpDate("Thu, 01 Jan 1970 00:00:00 GMT") == 0
        and Clock.parseHttpDate("Tue, 29 Feb 2028 23:59:59 GMT") == 1835481599 and Clock.parseHttpDate("yesterday") == nil,
        "a server's Date read (UTC)")
    local orig_set, set_to = Clock.set, nil
    Clock.set = function(t) set_to = t; return true end
    Clock.done = false
    check(not Clock.fromServer({ date = "Sat, 07 Nov 2026 06:57:01 GMT" }, 1794030000) and set_to == nil and Clock.done,
        "a clock that's right: left alone (and not looked at again)")
    Clock.done = false
    check(not Clock.fromServer({ date = "garbage" }, 946729573) and set_to == nil and not Clock.done, "no usable Date: nothing")
    check(Clock.fromServer({ ["date"] = "Sat, 07 Nov 2026 06:57:01 GMT" }, 946729573) and set_to == 1794034621,
        "a clock in the year 2000 (a Nook's after its battery ran down): set from the server's")
    set_to = nil
    check(not Clock.fromServer({ date = "Sat, 07 Nov 2026 06:58:01 GMT" }, 946729600) and set_to == nil, "…once per start")
    Clock.set, Clock.done = orig_set, true
end

print("Grimmory reading stats (Home widget)")
do
    local GS = require("gzreader_grimstats")
    check(GS.isoWeekOfYear(os.time{ year = 2026, month = 11, day = 4, hour = 12 }) == 45
        and GS.isoWeekOfYear(os.time{ year = 2027, month = 1, day = 1, hour = 12 }) == 0
        and GS.isoWeekOfYear(os.time{ year = 2026, month = 1, day = 1, hour = 12 }) == 1,
        "the week Grimmory's timeline asks for (ISO, Monday first)")
    rplugin.store.grimmory_stats = nil
    local v = GS.values(rplugin)
    check(v.reading_days and v.reading_days >= 1 and v.streak and v.week_time and v.week_time >= 300 and v.week_books == 1
        and v.year_finished == 3 and v.month_sessions and v.longest_streak == 5,
        "streak, days, this week's time and books, this month's sessions, finished this year: from Grimmory")
    ctl("/set?stats_perm=false")
    GS.refresh(rplugin, true)
    check(rplugin.store.grimmory_stats.error == "permission" and rplugin.store.grimmory_stats.values.year_finished == 3,
        "a user who may not see statistics: the last numbers stay, the log says why")
    ctl("/set?stats_perm=true")
    local at = rplugin.store.grimmory_stats.at
    GS.values(rplugin)
    check(rplugin.store.grimmory_stats.at == at, "not asked again within 15 minutes")
    GS.stale(rplugin)
    GS.values(rplugin)
    check(rplugin.store.grimmory_stats.error == nil, "asked again after this Kindle's sessions reached Grimmory")
end

print("Ratings (Grimmory's personal rating)")
do
    local R = require("gzreader_ratings")
    check(R.toGrimmory(4) == 8 and R.fromGrimmory(7) == 4 and R.fromGrimmory(10) == 5 and R.fromGrimmory(1) == 1
        and R.fromGrimmory(nil) == nil and R.toGrimmory(nil) == nil, "stars: 4 = 8 of 10; 7 of 10 = 4 stars")
    local data = {}
    readerui.doc_settings = { readSetting = function(_, k) return data[k] end, saveSetting = function(_, k, v) data[k] = v end, flush = function() end }
    local entry = rplugin.store.downloads["3"]
    entry.rating_synced = nil
    local function openBook() rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {} end
    local function closeBook() rplugin:onCloseDocument(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {} end
    ctl("/rating?book=3&r=7")
    openBook()
    check(data.summary and data.summary.rating == 4 and entry.rating_synced == 4, "rated 7 of 10 in Grimmory: 4 stars on the Kindle when the book opens")
    data.summary.rating = 2
    closeBook()
    st = json.decode(ctl("/state"))
    check(st.ratings["3"] == 4 and entry.rating_synced == 2 and next(rplugin.store.pending.ratings) == nil, "rated 2 stars on the Kindle: 4 of 10 in Grimmory on closing")
    ctl("/rating?book=3&r=10")
    openBook()
    check(data.summary.rating == 5 and entry.rating_synced == 5, "changed in Grimmory only: the Kindle takes it")
    data.summary.rating = nil
    NET.connected = false
    closeBook()
    check(rplugin.store.pending.ratings["3"] == 0, "stars removed offline: queued")
    NET.connected = true
    rplugin:onNetworkConnected(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
    st = json.decode(ctl("/state"))
    check(st.ratings["3"] == nil and entry.rating_synced == 0 and next(rplugin.store.pending.ratings) == nil, "and Grimmory's rating removed when Wi-Fi returns")
    readerui.doc_settings = nil
end

print("Grimmory shelves on the Kindle (Add to shelf / Remove from shelf, kept, queued)")
do
    local S = require("gzreader_shelves")
    local entry = rplugin.store.downloads["3"]
    local path = entry.path
    local path10 = rplugin.store.downloads["10"] and rplugin.store.downloads["10"].path
    local side = "/mnt/us/documents/sideloaded.epub"
    rplugin.store.shelf_cache = nil
    rplugin.store.grimmory_user = nil
    rplugin.store.pending.shelves = nil
    local function openBook() rplugin:onReaderReady(); for f in pairs(UI.scheduled) do f() end; UI.scheduled = {} end
    local function wifiBack()
        UI.scheduled = {}
        rplugin:onNetworkConnected()
        local due = {}
        for f in pairs(UI.scheduled) do due[#due + 1] = f end
        UI.scheduled = {}
        for _i, f in ipairs(due) do f() end
    end
    local changed = 0
    local function buttons(p) return rplugin:shelfButtons(p or path, function() changed = changed + 1 end) end
    local function shelvesOf(bk)
        local st = json.decode(ctl("/state"))
        local on = {}
        for sid, ids in pairs(st.shelves) do for _i, b in ipairs(ids) do if b == bk then on[#on + 1] = tonumber(sid) end end end
        table.sort(on)
        return table.concat(on, ","), st
    end
    local function names(list) local t = {} for _i, x in ipairs(list) do t[#t + 1] = x.text or x.name end return table.concat(t, "|") end

    -- not signed in / not a Grimmory book: the menu is there and says why it can't
    local saved_api = rplugin.api
    rplugin.api = setmetatable({ isPaired = function() return false end }, { __index = saved_api })
    local b = buttons()
    check(b and #b == 1 and b[1].text == "Add to shelf", "not signed in: the book menu still has Add to shelf")
    captured.info = nil; S.menu = nil
    b[1].callback()
    check(S.menu == nil and captured.info == "Sign in to Grimmory to continue: Settings → Connections → Grimmory.",
        "…which says to sign in to Grimmory to continue")
    rplugin.api = setmetatable({ offline = true, isPaired = function() return false end }, { __index = saved_api })
    buttons()[1].callback()
    check(captured.info and captured.info:find("sync with the sync page", 1, true), "a Kindle without Wi-Fi, never synced: says to sync through a computer")
    rplugin.api = saved_api
    b = buttons(side)
    check(#b == 1 and b[1].text == "Add to shelf", "a book not from Grimmory: Add to shelf too (no Add to collection)")
    b[1].callback()
    check(S.menu == nil and captured.info:find("isn't from your Grimmory library", 1, true), "…which says it can't go on a Grimmory shelf")

    -- a Grimmory book, nothing kept yet: your shelves (and their books) from Grimmory, then the list
    openBook() -- (its record says: on none of your shelves; that alone isn't all your shelves)
    check(S.mine(rplugin) == nil or not rplugin.store.shelf_cache.full, "a book's own record alone: not taken for all your shelves")
    b = buttons()
    check(#b == 1 and b[1].submenu, "a Grimmory book on none of your shelves: Add to shelf only")
    b[1].callback()
    local m = S.menu
    check(m and m.title == "Add to shelf" and names(m.item_table) == "Beach reads|Kindle",
        "Add to shelf: your own shelves by name (not someone else's public one, not smart shelves)")
    check(S.isOn(rplugin, 10, 4) and S.isOn(rplugin, 12, 4) and not S.isOn(rplugin, 3, 4) and rplugin.store.grimmory_user.id == 1,
        "every book on your shelves kept on the Kindle (not only downloaded ones), and your user id")
    m.onMenuSelect(m, m.item_table[2])
    local on, st = shelvesOf(3)
    check(on == "4,7" and json.encode(st.last_shelves_body.shelvesToUnassign) == "[]" and json.encode(st.last_shelves_body.bookIds) == "[3]",
        "picked Kindle with Wi-Fi: on it in Grimmory straight away (JSON lists)")
    check(not S.hasPending(rplugin) and S.isOn(rplugin, 3, 4) and captured.info == "Added to “Kindle”." and changed == 1,
        "nothing left queued, kept, said so")
    b = buttons()
    check(#b == 2 and b[2].text == "Remove from shelf" and not b[2].submenu, "now on one of your shelves: Remove from shelf")
    b[1].callback()
    check(S.menu.item_table[2].dim and S.menu.item_table[2].text == "Kindle  ✓", "Add to shelf again: Kindle ticked and greyed out")

    -- no Wi-Fi: queued, shown at once, sent when Wi-Fi is back
    NET.connected = false
    gsettings.gzreader_wifi_mode = "off" -- (On would turn it back on to send)
    b[2].callback()
    check(not S.isOn(rplugin, 3, 4) and #buttons() == 1 and shelvesOf(3) == "4,7"
        and captured.info == "Removed from “Kindle”.\nGrimmory gets it when Wi-Fi is on.",
        "Remove from shelf without Wi-Fi: off at once on the Kindle, queued for Grimmory")
    local jobs = S.jobs(rplugin)
    check(#jobs == 1 and jobs[1].kind == "shelf" and jobs[1].path == "/api/v1/books/shelves"
        and json.encode(jobs[1].body.shelvesToAssign) == "[]" and json.encode(jobs[1].body.shelvesToUnassign) == "[4]",
        "the queue as a job for the sync page (lists as JSON lists)")
    buttons()[1].callback()
    S.menu.onMenuSelect(S.menu, S.menu.item_table[2]) -- Kindle again: back to how Grimmory has it
    check(not S.hasPending(rplugin) and S.isOn(rplugin, 3, 4), "put back on before it was sent: nothing to send")
    buttons()[2].callback()
    NET.connected, gsettings.gzreader_wifi_mode = true, nil
    wifiBack()
    check(shelvesOf(3) == "7" and not S.hasPending(rplugin) and not S.isOn(rplugin, 3, 4), "Wi-Fi back: the change sent, the queue empty")

    -- changed in Grimmory's web app: the book's record when it opens, and the 30-minute refresh
    ctl("/shelf?book=3&add=6")
    openBook()
    b = buttons()
    check(S.isOn(rplugin, 3, 6) and b[2].text == "Remove from shelf", "put on a shelf in the web app: kept when the book opens")
    ctl("/shelf?book=3&add=4")
    ctl("/shelf?book=11&remove=4")
    wifiBack()
    check(not S.isOn(rplugin, 3, 4) and S.isOn(rplugin, 11, 4), "…not again before 30 minutes")
    rplugin.store.shelf_cache.at = 0
    wifiBack()
    b = buttons()
    check(S.isOn(rplugin, 3, 4) and not S.isOn(rplugin, 11, 4) and b[2].text == "Remove from shelves" and b[2].submenu,
        "after 30 minutes, with Wi-Fi: every shelf again from Grimmory (a book not opened too)")
    S.menu = nil
    b[2].callback()
    m = S.menu
    check(m and names(m.item_table) == "Beach reads|Kindle|All 2 shelves", "Remove from shelves: which one, or all")
    m.onMenuSelect(m, m.item_table[1])
    check(shelvesOf(3) == "4,7" and captured.info == "Removed from “Beach reads”.", "took it off Beach reads only")
    ctl("/shelf?book=3&add=6")
    rplugin.store.shelf_cache.at = 0
    wifiBack()
    buttons()[2].callback()
    S.menu.onMenuSelect(S.menu, S.menu.item_table[3])
    check(shelvesOf(3) == "7" and captured.info == "Removed from 2 shelves." and #buttons() == 1, "All 2 shelves: off both")

    -- changed again while a send is under way (the requests in the background): that's sent too
    do
        local Async = require("gzreader_async")
        ctl("/shelf?book=3&add=4&add=6")
        rplugin.store.shelf_cache.at = 0
        wifiBack()
        Async.sync = false
        S.set(rplugin, { 3 }, 6, false)
        S.set(rplugin, { 3 }, 4, false)
        runLoop(function() return not S.running and not S.hasPending(rplugin) and next(Async.queue) == nil and not Async.busy end, 30)
        Async.sync = true
        check(shelvesOf(3) == "7" and not S.hasPending(rplugin) and #S.on(rplugin, 3) == 0,
            "two changes, the second while the first was being sent: both reach Grimmory")
    end

    -- several selected books
    S.menu = nil
    rplugin:shelfAddMany({ path, path10, side }, function() changed = changed + 1 end)
    m = S.menu
    check(m and m.title == "Add 2 books to shelf" and not m.item_table[2].dim, "selected books: Add to shelf for the Grimmory ones")
    m.onMenuSelect(m, m.item_table[1])
    check(shelvesOf(3) == "6,7" and shelvesOf(10) == "4,6" and captured.info == "Added 2 books to “Beach reads”.\n1 not from Grimmory left out.",
        "both on Beach reads in Grimmory; the sideloaded one left out, said so")
    ctl("/shelf?book=3&remove=6"); ctl("/shelf?book=10&remove=6")

    -- someone else's shelf: Grimmory refuses it for good; not sent again
    S.set(rplugin, { 3 }, 7, false)
    check(not S.hasPending(rplugin) and shelvesOf(3) == "7", "someone else's shelf: refused by Grimmory, off the queue")
    rplugin.store.shelf_cache.at = 0
    wifiBack()

    local function src(f) return io.open(PLUGIN .. "/../zenos.koplugin/" .. f):read("*a") end
    local dialog, multi, guide = src("modules/filebrowser/patches/context_menu_file_dialog.lua"),
        src("modules/filebrowser/patches/context_menu.lua"), src("common/quickstart/quickstart_pages.lua")
    check(dialog:find("gz:shelfButtons(file,", 1, true) and not dialog:find('_("Add to collection")', 1, true)
        and multi:find("gz:shelfAddMany(book_paths,", 1, true) and not multi:find('text = icons.fav_add .. "  " .. _("Add to collection")', 1, true)
        and not guide:find('_("Add to collection")', 1, true),
        "ZenOS: Add to shelf in the book menu, for selected books and in the setup guide's picture; no Add to collection")
end

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

print("Bookmarks: Grimmory's own replies (nulls), deletes from the list")
do
    -- start clean: nothing here, nothing in Grimmory
    for _i, bm in ipairs(json.decode(ctl("/state")).bookmarks) do ctl("/delbm?id=" .. bm.id) end
    for i = #anns, 1, -1 do table.remove(anns, i) end
    rplugin.store.downloads["3"].bookmarks, rplugin.store.downloads["3"].bm_pending = {}, { add = {}, del = {} }
    local function remote() return json.decode(ctl("/state")).bookmarks end
    local NULL = require("json").null
    check(not BM.isAudio({ positionMs = NULL }) and BM.isAudio({ positionMs = 1500 }),
        "a JSON null positionMs isn't an audiobook bookmark")
    -- the owner's case (2026-11-08): two made here, the book closed, one added
    -- in the web reader, the book opened again -> all three on both sides
    local k1 = { page = "/body/DocFragment[4]/body/p", chapter = "Chapter 2" }
    local k2 = { page = "/body/DocFragment[4]/body/div/p[2]", chapter = "Chapter 2" }
    table.insert(anns, k1); rplugin:onAnnotationsModified({ k1, index_modified = #anns })
    table.insert(anns, k2); rplugin:onAnnotationsModified({ k2, index_modified = #anns })
    local r = remote()
    check(#r == 2 and r[1].positionMs == nil and r[1].priority == 3, "two Kindle bookmarks in Grimmory (its full replies, nulls and all)")
    rplugin:onCloseDocument()
    ctl("/addbm?book=3&cfi=epubcfi(/6/8!/4/4/8)&title=web")
    UI.scheduled = {}
    rplugin:onReaderReady()
    runLoop(function() return #anns >= 3 end, 10)
    local pages = {}
    for _i, a in ipairs(anns) do pages[a.page] = (pages[a.page] or 0) + 1 end
    check(#anns == 3 and pages[k1.page] == 1 and pages[k2.page] == 1 and pages["/body/DocFragment[4]/body/div/p[3]"] == 1,
        "opened again: both Kindle bookmarks kept and the web one added (none lost, none twice)")
    check(#remote() == 3, "Grimmory still has all three")
    local web
    for _i, a in ipairs(anns) do if a.page == "/body/DocFragment[4]/body/div/p[3]" then web = a end end
    check(web and web.text == "web", "the web bookmark's title")
    ctl("/addbm?book=3&cfi=epubcfi(/6/8!/4/4/8)&title=nameless") -- (title null in the next one)
    ctl("/addbm?book=3&pos=61000&title=audio")
    rplugin.bookmarks:reconcile()
    check(#anns == 3, "an audiobook bookmark (a time) isn't put in the book")
    -- deleted from the bookmark list (KOReader sends no event for that)
    for i, a in ipairs(anns) do if a == k1 then table.remove(anns, i) end end
    rplugin.bookmarks:reconcile()
    runLoop(function() return #remote() == 4 end, 5)
    local left = {}
    for _i, bm in ipairs(remote()) do left[tostring(bm.cfi)] = true end
    check(#remote() == 4 and not left["epubcfi(/6/8!/4/6)"] and left["epubcfi(/6/8!/4/4/6)"],
        "deleted from the bookmark list here: deleted in Grimmory at the next sync")
    rplugin.bookmarks:reconcile()
    check(#anns == 2 and #remote() == 4, "…and stays deleted (not brought back)")
    for _i, bm in ipairs(remote()) do ctl("/delbm?id=" .. bm.id) end
    rplugin.bookmarks:reconcile()
    for i = #anns, 1, -1 do table.remove(anns, i) end
end

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
    gsettings.gzreader_wifi_mode = "auto" -- (was "Wi-Fi only when needed")
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
    gsettings.gzreader_wifi_mode = nil
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

print("Notes: the web reader's Notes tab (Grimmory's book notes)")
do
    local NS = require("gzreader_notesync")
    -- the merge on its own
    local p = NS.plan({ a = { note = "x" }, b = { note = "same" }, c = {} },
        NS.byCfi({ { id = 1, cfi = "b", noteContent = "same" }, { id = 2, cfi = "c", noteContent = "web" },
            { id = 3, cfi = "d", noteContent = "gone here", selectedText = require("json").null } }),
        { b = { id = 1, note = "same" }, d = { id = 3, note = "gone here" } })
    check(#p.creates == 1 and p.creates[1].cfi == "a" and #p.updates == 0 and #p.deletes == 1 and p.deletes[1].id == 3
        and next(p.conflicts) == nil, "notes plan: new here -> create, deleted here -> delete, new there -> left for the merge")
    local Anno = require("gzreader_annotations")
    local CFI = require("gzreader_cfi")
    local function notes() return json.decode(ctl("/state")).notes end
    local function hls() return json.decode(ctl("/state")).annotations end
    for _i, a in ipairs(hls()) do ctl("/delan?id=" .. a.id) end
    rplugin.store.bookmark_sync_disabled = true
    rplugin:onReaderReady(); UI.scheduled = {}
    local note_anns = readerui.annotation.annotations
    for i = #note_anns, 1, -1 do table.remove(note_anns, i) end
    local entry = rplugin.store.downloads["3"]
    entry.anno_shadow, entry.note_shadow, entry.anno_dirty = {}, nil, nil
    local note_an = rplugin.annotations
    local P0, P1 = "/body/DocFragment[4]/body/div/p[3]/text().0", "/body/DocFragment[4]/body/div/p[3]/text().5"
    CFI.initBook("x", Anno.openReader()); local range = CFI.xpointerRangeToCFI(P0, P1); CFI.clearCache()
    table.insert(note_anns, { pos0 = P0, pos1 = P1, page = P0, text = "three", chapter = "Chapter 2", drawer = "lighten",
        color = "green", note = "Kindle note", datetime = "2026-11-08 03:00:00" })
    note_an:run()
    local nt = notes()
    check(#nt == 1 and nt[1].cfi == range and nt[1].noteContent == "Kindle note" and nt[1].selectedText == "three"
        and nt[1].color == "#4ADE80" and nt[1].chapterTitle == "Chapter 2", "a Kindle note is in Grimmory's Notes, at its highlight")
    check(#hls() == 1 and hls()[1].note == "Kindle note", "…and the highlight keeps it too")
    note_an:run()
    check(#notes() == 1 and not entry.anno_dirty, "again: no duplicate, nothing waiting")
    ctl("/editnote?id=" .. nt[1].id .. "&note=edited%20on%20the%20web")
    note_an:run()
    check(note_anns[1].note == "edited on the web", "edited in the web reader: the Kindle's note changes")
    note_an:run()
    check(hls()[1].note == "edited on the web" and #notes() == 1, "…the highlight's copy follows")
    note_anns[1].note = "kindle edit" -- (KOReader sends no event for an edit)
    check(note_an:notesChanged(), "an edited note is noticed when the book closes")
    note_an:run()
    check(notes()[1].noteContent == "kindle edit" and not note_an:notesChanged(), "edited on the Kindle: Grimmory's note changes")
    -- a note in the web reader where the Kindle has no highlight
    ctl("/addnote?book=3&note=web%20only&text=two&cfi=epubcfi(/6/8%5Bc2%5D!/4/4/6,/1:0,/1:3)")
    note_an:run()
    local only, hl
    for _i, a in ipairs(note_anns) do if a.grimmory_note_only then only = a else hl = a end end
    check(#note_anns == 2 and only and only.note == "web only" and only.pos0 == "/body/DocFragment[4]/body/div[1]/p[2]/text()[1].0",
        "a web note comes to the Kindle at its words")
    note_an:run()
    check(#hls() == 1 and #notes() == 2, "…and isn't sent back as a highlight")
    hl.note = nil
    note_an:run()
    nt = notes()
    check(#nt == 1 and nt[1].noteContent == "web only", "note removed on the Kindle: removed from Grimmory's Notes")
    ctl("/delnote?id=" .. nt[1].id)
    note_an:run()
    check(#note_anns == 1 and not note_anns[1].grimmory_note_only and note_anns[1].text == "three", "deleted in the web reader: gone from the Kindle")
    -- (a pass puts Grimmory's copy of a synced highlight in its place: note_anns[1] each time)
    note_anns[1].note = "a"; note_an:run()
    ctl("/editnote?id=" .. notes()[1].id .. "&note=web%20b"); note_anns[1].note = "kindle c"
    note_an:run()
    check(notes()[1].noteContent == "web b" and note_anns[1].note == "kindle c" and entry.anno_dirty,
        "edited in both places: each keeps its own, tried again later")
    note_anns[1].note = "web b"; note_an:run()
    check(not entry.anno_dirty and #notes() == 1, "settles once both agree")
    for i = #note_anns, 1, -1 do table.remove(note_anns, i) end
    note_an:run()
    check(#notes() == 0 and #hls() == 0, "highlight with its note deleted here: both gone in Grimmory")
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

print("Highlights that show on both the Kindle and the web reader")
;(function()
    local AnnotationSync = require("gzreader_annosync")
    local fake_cfi = { xpointerRangeToCFI = function() return "epubcfi(/6/4!/4/2,/1:0,/1:5)" end }
    local function sentColor(annotation)
        annotation.pos0, annotation.pos1, annotation.text = "/body/p[1]/text().0", "/body/p[1]/text().5", "Hello"
        local out = AnnotationSync.fromLocal({ annotation }, fake_cfi, 1)
        return out[1] and out[1].body.color
    end
    check(sentColor({ color = "gray", drawer = "lighten" }) == "#FFC107", "a Kindle's grey highlight goes to Grimmory as the web reader's yellow")
    check(sentColor({ color = "gray", drawer = "lighten", grimmory_id = 7, grimmory_color = "#AAAAAA", grimmory_local_color = "gray" }) == "#AAAAAA",
        "a grey highlight already in Grimmory keeps its colour there")
    check(sentColor({ color = "green", drawer = "lighten" }) == "#4ADE80", "other colours as before")
    local back = AnnotationSync.toLocal({ id = 8, cfi = "epubcfi(/6/4!/4/2,/1:0,/1:5)", color = "#FFC107", style = "highlight" },
        { cfiRangeToXPointers = function() return "/body/p[1]/text().0", "/body/p[1]/text().5" end })
    local grey = AnnotationSync.toLocal({ id = 9, cfi = "epubcfi(/6/4!/4/2,/1:0,/1:5)", color = "#AAAAAA", style = "highlight" },
        { cfiRangeToXPointers = function() return "/body/p[1]/text().0", "/body/p[1]/text().5" end })
    check(back and back.color == "yellow" and grey and grey.color == "gray", "Grimmory's yellow comes back yellow, its grey grey")

    -- drawing on the Kindle: too-light colours drawn like the grey highlight
    local HL = require("gzreader_hlcolor")
    local yellow, orange, blue = { r = 255, g = 255, b = 51 }, { r = 255, g = 136, b = 0 }, { r = 0, g = 102, b = 255 }
    check(HL.tooLight(yellow, 0.2) and not HL.tooLight(orange, 0.2) and not HL.tooLight(blue, 0.2) and not HL.tooLight(nil, 0.2),
        "KOReader's yellow is too light on a greyscale screen; orange and blue aren't")
    local saved = { rv = package.loaded["apps/reader/modules/readerview"], dev = package.loaded["device"],
        bb = package.loaded["ffi/blitbuffer"], installed = HL.installed }
    local drawn = {}
    local FakeView = { drawHighlightRect = function(_self, _bb, _x, _y, _rect, drawer, color) drawn[#drawn + 1] = { drawer, color } end }
    local colour_screen = false
    package.loaded["apps/reader/modules/readerview"] = FakeView
    package.loaded["device"] = { screen = { isColorEnabled = function() return colour_screen end } }
    package.loaded["ffi/blitbuffer"] = { isColor8 = function(c) return c and c.grey ~= nil end }
    HL.installed = false
    HL.install()
    local view = setmetatable({ highlight = { lighten_factor = 0.2 } }, { __index = FakeView })
    view:drawHighlightRect(nil, 0, 0, {}, "lighten", yellow)
    view:drawHighlightRect(nil, 0, 0, {}, "lighten", orange)
    view:drawHighlightRect(nil, 0, 0, {}, "underscore", yellow)
    view:drawHighlightRect(nil, 0, 0, {}, "lighten", nil)
    colour_screen = true
    view:drawHighlightRect(nil, 0, 0, {}, "lighten", yellow)
    check(drawn[1][2] == nil and drawn[2][2] == orange and drawn[3][2] == yellow and drawn[4][2] == nil and drawn[5][2] == yellow,
        "greyscale: yellow drawn as the grey highlight, orange and underlines as they were; a colour screen: unchanged")
    view.highlight.lighten_factor = 0.05
    colour_screen = false
    view:drawHighlightRect(nil, 0, 0, {}, "lighten", yellow)
    check(drawn[6][2] == yellow, "a lighter grey highlight chosen in KOReader's settings: yellow is drawn as before")
    package.loaded["apps/reader/modules/readerview"], package.loaded["device"], package.loaded["ffi/blitbuffer"] = saved.rv, saved.dev, saved.bb
    HL.installed = saved.installed
end)()

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

    -- recognizing picture books, however the book is split into files
    local function epubOf(spine_files)
        local man, sp, fs = {}, {}, { ["META-INF/container.xml"] = CONTAINER }
        for i, body in ipairs(spine_files) do
            man[#man + 1] = string.format('<item id="f%d" href="Text/f%d.xhtml" media-type="application/xhtml+xml"/>', i, i)
            sp[#sp + 1] = string.format('<itemref idref="f%d"/>', i)
            fs[string.format("OEBPS/Text/f%d.xhtml", i)] = "<html><body>" .. body .. "</body></html>"
        end
        fs["OEBPS/content.opf"] = "<package><manifest>" .. table.concat(man) .. "</manifest><spine>" .. table.concat(sp) .. "</spine></package>"
        return function(p) return fs[p] end
    end
    local function pics(a, b, text)
        local t = {}
        for i = a, b do
            t[#t + 1] = string.format('<p><img src="../images/p%d.jpg"/></p>', i)
            if text then t[#t + 1] = "<p>" .. text .. "</p>" end
        end
        return table.concat(t, "\n")
    end
    local cover = '<div><img src="../images/cover.jpg"/></div>'
    local contents = "<h1>Contents</h1><ul>" .. string.rep("<li>Page so and so of the book</li>", 40) .. "</ul>"
    local scans = {}
    for i = 1, 20 do scans[i] = pics(i * 10, i * 10 + 9) end
    check(PB.detectWith(epubOf(scans)), "picture book: a scan per page, in many files")
    -- Dog Days as Grimmory had it: the whole book in one file between a cover and a contents page
    check(PB.detectWith(epubOf({ cover, pics(1, 450), contents })), "picture book in one big file (with a cover and a contents page): recognized")
    check(PB.detectWith(epubOf({ pics(1, 300) })), "…and as the only file")
    check(PB.detectWith(epubOf({ cover, pics(1, 200), pics(201, 400), contents })), "…in a few big files")
    local line = "For me, summer vacation is basically a three-month guilt trip, and everyone expects you to be outside."
    check(not PB.detectWith(epubOf({ cover, pics(1, 450, line .. " " .. line), contents })),
        "a converted PDF (pictures with the text as lines between them, one big file): not a picture book")
    check(not PB.detectWith(epubOf({ cover, string.rep("<p>" .. line .. "</p>", 3000), contents })), "a novel in one file: not a picture book")
    local chapters = {}
    for i = 1, 3 do chapters[i] = string.rep("<p>" .. line .. "</p>", 300) end
    check(not PB.detectWith(epubOf(chapters)), "a novel in three files: not a picture book")
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

    -- a second picture book opened, or Fit pictures to the screen tapped,
    -- while another book's pictures are measured: fitted after it (it did nothing)
    do
        local cbs = {}
        Async.background = function(_fn, cb) cbs[#cbs + 1] = cb end
        local DSm = require("docsettings")
        local orig_dso = DSm.open
        local function mkds()
            local kv = {}
            return { d = kv, readSetting = function(_s, k) return kv[k] end, saveSetting = function(_s, k, v) kv[k] = v end,
                delSetting = function(_s, k) kv[k] = nil end, flush = function() end }
        end
        DSm.open = function() return mkds() end
        local function mkui(file)
            return { doc_settings = mkds(), view = ui.view, styletweak = { updateCssText = function() end },
                document = { file = file, info = {}, invalidateCacheFile = function() end,
                    configurable = { smooth_scaling = 0, h_page_margins = { 15, 15 }, t_page_margin = 10, b_page_margin = 10 } },
                reloadDocument = function(self) self.reloaded = (self.reloaded or 0) + 1 end }
        end
        local uA, uB = mkui(WORK .. "/pb-first.epub"), mkui(WORK .. "/pb-second.epub")
        RUI.instance = uA
        PB.set(uA, true) -- the first book: its pictures being measured
        RUI.instance = uB -- the second book opened meanwhile
        local shown = #UI.shown
        PB.menuItem(uB).callback() -- (or opened: PB.onOpen's PB.set, the same)
        check(#cbs == 1 and not PB.isOn(uB) and #UI.shown == shown + 1,
            "Fit pictures to the screen while another book's pictures are measured: waits, and says the pages will be fitted in a moment")
        cbs[1]({})
        check(#cbs == 2 and uA.reloaded == nil, "the first one done (closed: saved with it): the second book's pictures are measured next")
        cbs[2]({})
        check(PB.isOn(uB) and uB.reloaded == 1 and uB.document.configurable.h_page_margins[1] == 0,
            "…and the second book is fitted and reopened")
        DSm.open, RUI.instance, Async.background = orig_dso, saved_inst, orig_bg
    end

    -- a book fitted by 1.2.x (style v3): fitted again once when it opens
    ds.d.gzreader_picture_book = true
    ui.styletweak.book_style_tweak = "/* GZreader picture book: begin */ /* v3 */ img{} /* GZreader picture book: end */"
    ui.styletweak.book_style_tweak_enabled = true
    PB.onOpen(ui)
    check(reopened == 4 and ui.styletweak.book_style_tweak:find("/* v5 */", 1, true), "fitted by an older version: fitted again once")
    PB.onOpen(ui)
    check(reopened == 4, "…and not again")

    -- a picture book brought by the computer (or downloaded for later): recognized and
    -- fitted before it's first opened, so it opens once, already fitted
    local pf = WORK .. "/pb-prefit.epub"
    local pfh = io.open(pf, "wb"); pfh:write("x"); pfh:close()
    local DocSettings = require("docsettings")
    local docstore, orig_open = {}, DocSettings.open
    DocSettings.open = function(_s, path)
        docstore[path] = docstore[path] or {}
        local o = { data = docstore[path] }
        function o:readSetting(k) return self.data[k] end
        function o:saveSetting(k, v) self.data[k] = v end
        function o:flush() end
        return o
    end
    check(PB.prefit(pf, true, { "logo.jpg" }), "picture book recognized before it's opened")
    local dsx = DocSettings:open(pf)
    local tweak = dsx:readSetting("book_style_tweak") or ""
    check(dsx:readSetting("gzreader_picture_book") == true and dsx:readSetting("copt_t_page_margin") == 30
        and dsx:readSetting("copt_b_page_margin") == 4 and dsx:readSetting("copt_h_page_margins")[1] == 0
        and dsx:readSetting("copt_smooth_scaling") == 1 and dsx:readSetting("book_style_tweak_enabled") == true
        and tweak:find("/* v5 */", 1, true) and tweak:find('img[src$="logo.jpg"]', 1, true)
        and type(dsx:readSetting("gzreader_pb_margins")) == "table",
        "…fitted with this Kindle's layout (from the last picture book fitted here), the old margins kept")
    check(not PB.prefit(pf, true, {}), "…once")
    ds.d = { gzreader_picture_book = true, gzreader_pb_fit = dsx:readSetting("gzreader_pb_fit") }
    ui.styletweak.book_style_tweak = tweak
    ui.styletweak.book_style_tweak_enabled = true
    local before_open = reopened
    PB.onOpen(ui)
    for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
    check(reopened == before_open, "opening it: already fitted, not opened a second time")
    ds.d.gzreader_pb_fit = { top = 0, bottom = 40 }
    PB.onOpen(ui)
    for f in pairs(UI.scheduled) do f() end; UI.scheduled = {}
    check(reopened == before_open + 1, "…unless the title bar or footer changed since: fitted again")
    local pg = WORK .. "/pb-plain.epub"
    pfh = io.open(pg, "wb"); pfh:write("x"); pfh:close()
    local orig_bg2 = Async.background
    Async.background = function(_fn, cb) cb({ yes = false, wide = {} }) end
    PB.PREPARE_DELAY = 0
    rawset(_G, "GZ_NO_PB_PREPARE", nil)
    -- a book being laid out in the background: the check waits for it
    local L_was = package.loaded["gzreader_layout"]
    package.loaded["gzreader_layout"] = { running = { id = "9" } }
    PB.prepare(pg); PB.prepare(pg)
    for fn in pairs(UI.scheduled) do fn() end; UI.scheduled = {}
    check(DocSettings:open(pg):readSetting("gzreader_picture_book") == nil and #PB.queue == 1,
        "a background layout running: the picture-book check waits (two book processes ran a Kindle 3 out of memory)")
    package.loaded["gzreader_layout"] = L_was
    PB.safeNext()
    for fn in pairs(UI.scheduled) do fn() end; UI.scheduled = {}
    Async.background = orig_bg2
    check(DocSettings:open(pg):readSetting("gzreader_picture_book") == false and #PB.queue == 0,
        "a book that isn't one: noted (not checked again when it opens)")
    DocSettings.open = orig_open
    rawset(_G, "GZ_NO_PB_PREPARE", true)
    os.execute("rm -f '" .. pf .. "' '" .. pg .. "'")

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
    if out and cmd:match("lipc%-set%-prop %-s") then
        -- (firmware 3's playFile is a hash property: a string is refused)
        local f = io.open(out, "wb"); f:write("com.lab126.tts failed to access property playFile (0x8)\nrc=1\n"); f:close()
    elseif out then
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
print("Read aloud on the Kindle DX (firmware 2.x): the speech pipe, then a text file for ttsd")
do
    local said, calls, cmds = {}, {}, {}
    local refuse -- function(path) -> true when this ttsd says "wrong file"
    TTS.exec = function(cmd)
        cmds[#cmds + 1] = cmd
        local out = cmd:match("> (/tmp/gzreader%-tts%.%d+%.out) 2>&1")
        if not out then return 0 end
        local rc, body = 0, ""
        if cmd:match("lipc%-hash%-prop") then
            rc, body = 127, "sh: lipc-hash-prop: not found"
        else
            local path = cmd:match("lipc%-set%-prop %-s com%.lab126%.tts playFile (%S+)")
            calls[#calls + 1] = path
            -- (through the pipe: the text is what `cat` writes into it)
            local src = cmd:match("%(cat (%S+) > " .. (path or ""):gsub("%p", "%%%0") .. "%)") or path
            if refuse(path) then
                local f = io.open(SYSLOG, "ab")
                f:write("261029:040100 ttsd[2070]: E lipc_handling:wrong_file:file=" .. path .. ":playFile: wrong file\n")
                f:close()
            else
                local tf = src and io.open(src, "rb")
                if tf then said[#said + 1] = tf:read("*a"); tf:close() end
            end
        end
        local f = io.open(out, "wb"); f:write(body, "\nrc=", rc, "\n"); f:close()
        return 0
    end

    -- 1. the DX of the logs: plain text files are "wrong file"; its pipe works
    refuse = function(path) return not path:match("ttsUSFifo$") end
    os.remove(SYSLOG); io.open(SYSLOG, "wb"):close()
    gsettings.gzreader_tts_template = nil
    captured.confirm, captured.info = nil, nil
    TTS.findVoice()
    runLoop(function() return captured.confirm ~= nil or (captured.info and captured.info:match("didn't accept")) end, 60)
    local first
    for _i, c in ipairs(cmds) do if c:find("playFile", 1, true) then first = c; break end end
    check(captured.confirm and calls[1] == "/var/tmp/ttsUSFifo" and said[1] == "This is the Kindle voice test. \n",
        "no lipc-hash-prop: the sentence goes into the Kindle's speech pipe, its path to ttsd's playFile")
    check(first and first:find("[ -p /var/tmp/ttsUSFifo ] || { rm -f /var/tmp/ttsUSFifo; mkfifo /var/tmp/ttsUSFifo", 1, true)
        and first:find("(cat /tmp/gzreader-tts.fifo.", 1, true) and first:find("echo $w > " .. TTS.FIFO_WRITER_PID, 1, true)
        and first:find("sleep " .. TTS.FIFO_WRITER_TIMEOUT .. "; kill $w", 1, true) and first:find("&$"),
        "the pipe is made when missing; the writer runs in the background and gives up after a while")
    captured.confirm.ok_callback()
    local tpl1 = gsettings.gzreader_tts_template
    check(tpl1 and tpl1.target.prop == "playFile" and tpl1.target.fifo == "/var/tmp/ttsUSFifo" and TTS.oneAtATime(tpl1), "saved: the speech pipe, one sentence at a time")
    calls, said = {}, {}
    page = 1; tts_ui.turned = nil
    local R5 = TTS.Reader:new(tts_ui)
    R5:start()
    check(R5.active and #calls == 1 and calls[1] == "/var/tmp/ttsUSFifo" and said[1]:match("^" .. R5.queue[1].text) and tts_ui.hl == "s1",
        "reading through the pipe: the sentence shown, paced by estimates")
    R5:advance(R5.queue[1].id)
    check(#calls == 2 and said[2]:match("^Second one%.") and cmds[#cmds]:find("kill $(cat " .. TTS.FIFO_WRITER_PID, 1, true),
        "…then the next one (a writer still waiting is stopped first)")
    local wf = io.open(TTS.FIFO_WRITER_PID, "wb"); wf:write("4242"); wf:close()
    R5:stop()
    local killed
    for _i, c in ipairs(cmds) do if c == "kill 4242 >/dev/null 2>&1" then killed = true end end
    check(not R5.active and killed and not io.open(TTS.FIFO_WRITER_PID, "rb"), "stopping also stops a sentence still waiting for the pipe")

    -- 2. a ttsd that wants neither pipe nor /tmp: a text file in /var/tmp
    refuse = function(path) return path:match("ttsUSFifo$") or path:match("^/tmp/") end
    calls, said, cmds = {}, {}, {}
    os.remove(SYSLOG); io.open(SYSLOG, "wb"):close()
    gsettings.gzreader_tts_template = nil
    captured.confirm, captured.info = nil, nil
    TTS.findVoice()
    runLoop(function() return captured.confirm ~= nil or (captured.info and captured.info:match("didn't accept")) end, 60)
    check(captured.confirm and #calls >= 4 and calls[1] == "/var/tmp/ttsUSFifo" and calls[2] == "/tmp/ttsUSFifo"
        and calls[3]:match("^/tmp/gzreader%-tts%.") and calls[4]:match("^/var/tmp/gzreader%-tts%.")
        and said[1] == "This is the Kindle voice test. \n",
        "pipes refused: the sentence in a text file, its path to ttsd's playFile (the next folder when ttsd can't use it)")
    captured.confirm.ok_callback()
    local tpl2 = gsettings.gzreader_tts_template
    check(tpl2 and tpl2.target.prop == "playFile" and tpl2.target.file == "/var/tmp" and not tpl2.target.fifo and TTS.oneAtATime(tpl2), "saved: playFile, one sentence at a time")
    check(TTS.plainText("\u{201C}Hi\u{201D} \u{2014} it\u{2019}s\u{2026}") == '"Hi" ,  it\'s...', "typographic punctuation as plain text")
    calls, said = {}, {}
    page = 1; tts_ui.turned = nil
    local R4 = TTS.Reader:new(tts_ui)
    R4:start()
    check(R4.active and #calls == 1 and R4.events_ok == false and said[1]:match("^" .. R4.queue[1].text) and tts_ui.hl == "s1",
        "reading: only the sentence shown goes to ttsd (no queue there), paced by estimates")
    R4:advance(R4.queue[1].id)
    check(#calls == 2 and tts_ui.hl == "s2" and said[2]:match("^Second one%."), "…then the next one")
    R4:stop()
    check(not R4.active, "stopped")
    gsettings.gzreader_tts_template = TPL
end
-- stopping: only the voice's own properties, and nothing when it wasn't reading
do
    local sets, lipc_was, tpl_was = {}, TTS.lipc, gsettings.gzreader_tts_template
    TTS.lipc = { open_no_name = function()
        return { set_int_property = function(_h, pub, prop) sets[#sets + 1] = pub .. " " .. prop end, close = function() end }
    end }
    TTS.cancel({ target = { pub = "com.lab126.tts", prop = "playFile", file = "/var/tmp" } })
    check(#sets == 1 and sets[1] == "com.lab126.tts stop",
        "Kindle 2/DX voice (playFile): only com.lab126.tts stop (no ttsd there: it failed in the system log) " .. table.concat(sets, ", "))
    sets = {}
    TTS.cancel({ target = { pub = "com.lab126.ttsd", prop = "playSnippetNow" } })
    check(#sets == 2 and sets[1] == "com.lab126.ttsd cancelSnippetPlayback" and sets[2] == "com.lab126.tts stop", "Kindle 3 voice (ttsd): both, as before")
    sets = {}
    gsettings.gzreader_tts_template = nil
    TTS.cancel()
    check(#sets == 0, "no voice set up: nothing sent")
    gsettings.gzreader_tts_template = { target = { pub = "com.lab126.tts", prop = "playFile", file = "/var/tmp" } }
    local idle = TTS.Reader:new(tts_ui)
    idle:stop()
    check(#sets == 0, "a book closing without read aloud: nothing sent (it started lipc-set-prop each time)")
    TTS.lipc, gsettings.gzreader_tts_template = lipc_was, tpl_was
end
TTS.exec = nil; TTS.lipc = nil; TTS.now = nil
local _ = before

print("ZenOS's updater: not loaded (GZreader's in its place, on first use)")
;(function()
    local Z = PLUGIN .. "/../zenos.koplugin/"
    local function src(rel) local h = io.open(Z .. rel, "rb"); local t = h and h:read("*a") or ""; if h then h:close() end; return t end
    local callers = { "main.lua", "modules/settings/zen_settings.lua", "modules/settings/zen_bugreporter.lua",
        "modules/settings/sections/updates_settings.lua" }
    local loads_zen, used = {}, {}
    for _i, rel in ipairs(callers) do
        local t = src(rel)
        if t:find('require("modules/settings/zen_updater")', 1, true) or not t:find('require("modules/settings/gz_updater")', 1, true) then
            loads_zen[#loads_zen + 1] = rel
        end
        -- (the module's functions: `updater.x(`, `zen_updater.x`; not config.updater's fields)
        for fn in t:gmatch("%f[%w_]updater%.([%w_]+)%(") do used[fn] = true end
        for fn in t:gmatch("%f[%w_]zen_updater%.([%w_]+)") do used[fn] = true end
    end
    check(#loads_zen == 0, "ZenOS's main, settings, bug reporter and Updates section use gz_updater (" .. table.concat(loads_zen, ", ") .. ")")
    local saved_path = package.path
    package.path = Z .. "?.lua;" .. package.path
    local kept = { u = package.loaded["gzreader_update"], z = package.loaded["modules/settings/zen_updater"], ui = package.loaded["ui/uimanager"] }
    package.loaded["gzreader_update"], package.loaded["modules/settings/gz_updater"], package.loaded["modules/settings/zen_updater"] = nil, nil, nil
    local okm, U = pcall(require, "modules/settings/gz_updater")
    check(okm and package.loaded["gzreader_update"] == nil and package.loaded["modules/settings/zen_updater"] == nil,
        "loading it loads neither ZenOS's updater nor gzreader_update " .. (okm and "" or tostring(U)))
    local missing = {}
    for fn in pairs(used) do if fn ~= "_on_update_found" and type(U[fn]) ~= "function" then missing[#missing + 1] = fn end end
    table.sort(missing)
    check(okm and #missing == 0, "…and has everything they call (" .. table.concat(missing, ", ") .. ")")
    U.init_banner()
    check(U.has_update() == false and package.loaded["gzreader_update"] == nil, "at start: no update known, nothing loaded")
    -- the check 20 s after start: gzreader_update then
    local checks, found = 0, 0
    package.loaded["gzreader_update"] = { state = {}, backgroundCheck = function(cb) checks = checks + 1; package.loaded["gzreader_update"].state = { has_update = true, latest = "9.9.9" }; cb() end,
        menuItems = function() return { "now", "auto", "changelog", "channel" } end, run = function() end }
    local timers = {}
    package.loaded["ui/uimanager"] = { scheduleIn = function(_u, s, fn) timers[#timers + 1] = { s = s, fn = fn } end, unschedule = function() end }
    U._on_update_found = function() found = found + 1 end
    U.schedule_wakeup_check()
    check(#timers == 1 and timers[1].s == 20, "a check 20 s after start or a wake")
    timers[1].fn()
    check(checks == 1 and found == 1 and U.has_update() and U.latest_version() == "9.9.9" and U.build_update_available_action({}) ~= nil,
        "…done by gzreader_update; an update found shows (the Settings icon, the header button)")
    check(U.build_update_now_item() == "now" and U.build_auto_check_item() == "auto" and U.build_changelog_item() == "changelog"
        and U.build_channel_item() == "channel" and U.get_channel() == "stable", "the Updates section: GZreader's items")
    local cfg = { updater = { update_available = true } }
    U.clear_update_state(cfg)
    package.loaded["gzreader_update"].state = {}
    check(cfg.updater.update_available == false and not U.has_update(), "an update noticed elsewhere: cleared")
    package.loaded["gzreader_update"], package.loaded["modules/settings/zen_updater"], package.loaded["ui/uimanager"] = kept.u, kept.z, kept.ui
    package.loaded["modules/settings/gz_updater"] = nil
    package.path = saved_path
    -- Rakuyomi (a manga plugin GZreader doesn't ship): not loaded at start
    local dbl, fb = src("common/db_library.lua"), src("modules/filebrowser/filebrowser.lua")
    check(not dbl:find('\nlocal Rakuyomi = require("modules/filebrowser/patches/rakuyomi")', 1, true)
        and dbl:find('local Rakuyomi = setmetatable({}, { __index = function(_t, k) return require("modules/filebrowser/patches/rakuyomi")[k] end })', 1, true),
        "the library counts: Rakuyomi only loaded for a finished .cbz")
    check(fb:find('(not installed or installed.rakuyomi)\n        and OptionalProvider.call(PATCH_MODULES.rakuyomi, "is_available")', 1, true),
        "the file browser: not loaded to ask when the plugin scan found none")
end)()

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
package.loaded["ffi/archiver"] = nil -- (the real one can't load here; a failed try leaves a marker)
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
    function Reader:extractToMemory(p) return PKG[p] end
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
do
-- the same update package on a Kindle and on a Nook: the Nook's start script only on a Nook
PKG = { ["koreader/frontend/k.lua"] = "k", ["koreader/plugins/gzreader.koplugin/main.lua"] = "k main",
    ["koreader/gzreader-version"] = "1.3.0\n", ["koreader/nook-gzreader.sh"] = "#!/system/bin/sh\n# new\n",
    ["koreader/nook-launcher.sh"] = "#!/system/bin/sh\n# new helper\n" }
check(Update.apply("pkg.zip") and Update.currentVersion() == "1.3.0", "update with the Nook's start script in it, on a Kindle: installed")
check(rf(KO .. "/nook-gzreader.sh") == nil and rf(WORK .. "/gzreader.sh") == nil and rf(WORK .. "/launcher.sh") == nil,
    "…without the Nook's scripts (a Kindle has none)")
local NK = WORK .. "/nook/gzreader/koreader"
os.execute("rm -rf '" .. WORK .. "/nook' && mkdir -p '" .. NK .. "/frontend' '" .. NK .. "/plugins/gzreader.koplugin'")
wf(NK .. "/plugins/gzreader.koplugin/main.lua", "old main"); wf(NK .. "/gzreader-version", "1.2.0\n")
wf(WORK .. "/nook/gzreader/gzreader.sh", "#!/system/bin/sh\n# old\n")
local running = io.open(WORK .. "/nook/gzreader/gzreader.sh", "rb") -- (sh has the running script open)
Update.root = NK
check(Update.apply("pkg.zip") and Update.currentVersion() == "1.3.0" and rf(NK .. "/frontend/k.lua") == "k", "on a Nook: the same update installed")
check(rf(WORK .. "/nook/gzreader/gzreader.sh") == "#!/system/bin/sh\n# new\n", "…and the Nook's start script replaced, from the next start")
check(rf(WORK .. "/nook/gzreader/launcher.sh") == "#!/system/bin/sh\n# new helper\n", "…and the icon's helper (from the Nook's next restart)")
check(running:read("*a") == "#!/system/bin/sh\n# old\n", "…by a new file: the running script still reads its own copy")
running:close()
check(io.popen("ls -a '" .. WORK .. "/nook/gzreader' | grep -c 'gz-new'"):read("*a"):match("^0"), "…no temporary file left")
PKG = { ["koreader/frontend/k.lua"] = "k2", ["koreader/plugins/gzreader.koplugin/main.lua"] = "k main",
    ["koreader/gzreader-version"] = "1.3.1\n", ["koreader/nook-gzreader.sh"] = "not a script" }
check(Update.apply("pkg.zip") and rf(WORK .. "/nook/gzreader/gzreader.sh") == "#!/system/bin/sh\n# new\n", "a broken start script in the package: the Nook keeps its own")
PKG = { [TOP .. "frontend/src.lua"] = "src", [TOP .. "reader.lua"] = "reader", [TOP .. "platform/nook/gzreader.sh"] = "#!/system/bin/sh\n# src\n",
    [TOP .. "plugins/gzreader.koplugin/main.lua"] = "src main" }
check(Update.apply("src.zip", { source = true, version = "1.4.0" }) and rf(WORK .. "/nook/gzreader/gzreader.sh") == "#!/system/bin/sh\n# src\n",
    "a release's source code zip: the Nook's start script from platform/nook/")
-- the Nook's disk full (GZreader shares 242 MB with Android): downloaded and
-- unpacked on the card, installed by copying
local CARD = WORK .. "/card"
os.execute("rm -rf '" .. CARD .. "' && mkdir -p '" .. CARD .. "'")
local real_free, real_card, real_copy = Update.freeSpace, Update.cardDir, Update.copyTree
Update.cardDir = function() return CARD end
Update.freeSpace = function(p) return p == NK and 1024 * 1024 or 1e10 end
local work, elsewhere = Update.workDir(30e6)
check(elsewhere and work == CARD .. "/GZreader/.gzreader-update", "1 MB free next to GZreader, 30 MB needed: the update goes to the card")
PKG = { ["koreader/frontend/c.lua"] = "card", ["koreader/plugins/gzreader.koplugin/main.lua"] = "card main",
    ["koreader/gzreader-version"] = "1.5.0\n" }
local cok, cerr = Update.apply("pkg.zip", { stage = work })
check(cok and rf(NK .. "/frontend/c.lua") == "card" and rf(NK .. "/frontend/k.lua") == nil
    and rf(NK .. "/plugins/gzreader.koplugin/main.lua") == "card main" and Update.currentVersion() == "1.5.0",
    "…unpacked there and copied in, each part as a whole (" .. tostring(cerr) .. ")")
check(rf(WORK .. "/nook/gzreader/gzreader.sh") == "#!/system/bin/sh\n# src\n"
    and io.popen("ls -a '" .. CARD .. "/GZreader' '" .. NK .. "' | grep -c 'gzreader-update\\|gz-old'"):read("*a"):match("^0"),
    "…nothing left on the card or next to GZreader")
PKG = { ["koreader/frontend/d.lua"] = "d", ["koreader/plugins/gzreader.koplugin/main.lua"] = "d main",
    ["koreader/gzreader-version"] = "1.6.0\n" }
Update.copyTree = function(from, dest)
    if dest == NK .. "/plugins/gzreader.koplugin" and from:find("/koreader/plugins/") then return nil end
    return real_copy(from, dest)
end
local fok, ferr = Update.apply("pkg.zip", { stage = work })
Update.copyTree = real_copy
check(not fok and ferr:match("could not install plugins/gzreader.koplugin") and rf(NK .. "/frontend/c.lua") == "card"
    and rf(NK .. "/frontend/d.lua") == nil and rf(NK .. "/plugins/gzreader.koplugin/main.lua") == "card main"
    and Update.currentVersion() == "1.5.0",
    "a part that can't be copied in (the disk full after all): every part put back as it was, nothing changed")
check(io.popen("ls -a '" .. CARD .. "/GZreader' | grep -c 'gzreader-update'"):read("*a"):match("^0"), "…and nothing left on the card")
Update.freeSpace = function() return 1e10 end
check(select(2, Update.workDir(30e6)) == false, "room next to GZreader: unpacked there, as before")
-- parts on the card (the Nook's start script mounts them into koreader/):
-- unpacked next to GZreader, but those parts copied in, not renamed
local real_dev, copied = Update.devOf, {}
Update.devOf = function(p)
    if p == NK .. "/frontend" or p:find("^" .. NK:gsub("%p", "%%%0") .. "/frontend/") then return "card" end
    return real_dev(p)
end
Update.copyTree = function(from, dest)
    copied[#copied + 1] = dest
    return real_copy(from, dest)
end
PKG = { ["koreader/frontend/m.lua"] = "mounted", ["koreader/plugins/gzreader.koplugin/main.lua"] = "m main",
    ["koreader/gzreader-version"] = "1.7.0\n" }
local mok, merr = Update.apply("pkg.zip")
Update.copyTree, Update.devOf = real_copy, real_dev
local copied_frontend, copied_other = false, false
for _i, d in ipairs(copied) do
    if d == NK .. "/frontend" then copied_frontend = true elseif not d:find("/kept/") and not d:find("^" .. NK:gsub("%p", "%%%0") .. "/frontend/") then copied_other = true end
end
check(mok and rf(NK .. "/frontend/m.lua") == "mounted" and rf(NK .. "/frontend/c.lua") == nil and Update.currentVersion() == "1.7.0"
    and copied_frontend and not copied_other,
    "a part on another disk (frontend on the card): copied in; the rest renamed as before (" .. tostring(merr) .. ")")
check(io.popen("ls -a '" .. NK .. "' '" .. NK .. "/plugins' | grep -c 'gzreader-update\\|gz-old'"):read("*a"):match("^0"), "…nothing left behind")
Update.freeSpace, Update.cardDir = real_free, real_card
Update.root = KO
end
captured.textviewer = nil
preload("ui/widget/textviewer", { new = function(_, o) captured.textviewer = o; return o end })
Update.showChangelog()
check(captured.textviewer and captured.textviewer.title == "GZreader changelog" and captured.textviewer.text:match("GZreader 1%.0%.3"), "changelog is GZreader's")
-- test builds: latest-beta.json on the updates branch, any build other than the installed one
do
    local asked
    Update.request = function(u)
        asked = u
        return 200, json.encode({ version = "1.4.0-beta.12", size = 4567, sha256 = string.rep("cd", 32), file = "gzreader-beta-update.zip",
            commit = "0123abcd", notes = "• Nook: fewer flashes" })
    end
    check(not Update.betaEnabled() and Update.feedUrl() == Update.apiUrl(), "test builds off by default: releases")
    Update.setBeta(true)
    local binfo = Update.check()
    check(Update.betaEnabled() and asked == "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/latest-beta.json",
        "test builds on: latest-beta.json on the updates branch (next to the release's latest.json)")
    check(binfo and binfo.beta and binfo.version == "1.4.0-beta.12" and binfo.size == 4567
        and binfo.url == "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/gzreader-beta-update.zip"
        and binfo.notes:match("fewer flashes") and binfo.page:match("/commit/0123abcd$") and Update.state.has_update,
        "a test build found, with its download, size and what's in it (installed " .. Update.currentVersion() .. ")")
    -- (GitHub's file server keeps each file of a branch for minutes, each on its own:
    -- the test build's data and its zip are read at the branch's commit)
    local sha, asks = string.rep("ab12", 10), {}
    Update.request = function(u, _path, accept)
        asks[#asks + 1] = u
        if u:match("/commits/updates$") then return 200, accept == "application/vnd.github.sha" and sha or "{}" end
        return 200, json.encode({ version = "1.4.0-beta.13", size = 4568, file = "gzreader-beta-update.zip" })
    end
    local pinned = Update.check()
    check(asks[1] == "https://api.github.com/repos/9retirement6irk/GZreader/commits/updates"
        and asks[2] == "https://raw.githubusercontent.com/9retirement6irk/GZreader/" .. sha .. "/latest-beta.json"
        and pinned and pinned.url == "https://raw.githubusercontent.com/9retirement6irk/GZreader/" .. sha .. "/gzreader-beta-update.zip",
        "test builds: the data and the zip from the same commit of the updates branch (no half-old, half-new: 'incomplete')")
    Update.request = function(u)
        if u:match("/commits/") then return 403 end
        return 200, json.encode({ version = "1.4.0-beta.13", size = 4568, file = "gzreader-beta-update.zip" })
    end
    pinned = Update.check()
    check(pinned and pinned.url == "https://raw.githubusercontent.com/9retirement6irk/GZreader/updates/gzreader-beta-update.zip",
        "GitHub doesn't say the commit (rate limit): the branch as before")
    Update.request = function()
        return 200, json.encode({ version = Update.currentVersion(), size = 1, file = "gzreader-update.zip" })
    end
    check(Update.check() and not Update.state.has_update, "the installed test build: nothing to offer")
    Update.request = function() return 200, json.encode({ version = "1.0.0-beta.3", size = 1, file = "gzreader-update.zip" }) end
    check(Update.check() and Update.state.has_update, "an older test build than the installed version: still offered (test builds go by build, not number)")
    Update.request = function() return 200, json.encode({ version = "1.5.0-beta.1", size = 1, file = "../../evil.zip" }) end
    check(not Update.check(), "a file name with a path in it: refused")
    Update.request = function() return 404 end
    local _n, berr = Update.check()
    check(berr and berr:match("No test build"), "no test build yet: says so")
    Update.setBeta(false)
    check(not Update.betaEnabled() and Update.feedUrl() == Update.apiUrl() and gsettings.gzreader_update_last_check == 0,
        "test builds off: releases again, checked at once")
    check(Update.compare("1.4.0", "1.4.0-beta.12") > 0 and Update.compare("1.3.9", "1.4.0-beta.12") < 0,
        "after test builds: the release of that version is newer, an older release isn't")
end
-- The quick panel's Updates tile: what a check already found, nothing fetched
;(function()
    local Panel = require("gzreader_panel")
    local kept = { state = Update.state, latest = gsettings.gzreader_update_latest, last = gsettings.gzreader_update_last_check,
        beta = gsettings.gzreader_update_beta, request = Update.request, version = rf(KO .. "/gzreader-version") }
    wf(KO .. "/gzreader-version", "1.0.0\n")
    local fetched = 0
    Update.request = function() fetched = fetched + 1; return 404 end
    gsettings.gzreader_update_beta = false
    local function tile() local t = Panel.updatesTile(); return t.label .. (t.on and " (on)" or "") end
    Update.state = { has_update = false }; gsettings.gzreader_update_latest = nil
    check(Update.known() == nil and tile() == "Updates", "Updates tile: no check yet, plain Updates " .. tile())
    gsettings.gzreader_update_latest = "1.1.0" -- (a check before this start: the daily one)
    check(Update.known() == "1.1.0" and tile() == "Update available (on)",
        "…a check before a restart found 1.1.0 (installed 1.0.0): Update available, drawn inverted " .. tile())
    gsettings.gzreader_update_latest = "1.0.0"
    check(Update.known() == nil and tile() == "Updates", "…the saved check found the installed version: plain Updates")
    gsettings.gzreader_update_latest = "1.1.0"; gsettings.gzreader_update_last_check = os.time()
    Update.backgroundCheck()
    check(Update.state.has_update and Update.known() == "1.1.0" and tile() == "Update available (on)",
        "…the daily check, already done today: its result shown without asking again")
    Update.state = { has_update = false, latest = "1.0.0" }
    check(Update.known() == nil and tile() == "Updates", "…a check in this session found nothing: it wins over the saved one")
    Update.state = { has_update = true, latest = "1.2.0" }
    check(Update.known() == "1.2.0" and tile() == "Update available (on)", "…a check in this session found 1.2.0")
    gsettings.gzreader_update_beta = true; Update.state = { has_update = false }; gsettings.gzreader_update_latest = "1.0.0-beta.3"
    check(Update.known() == "1.0.0-beta.3", "…test builds: another test build than the installed one")
    check(fetched == 0, "…nothing fetched to draw the tile")
    local kept_mod = package.loaded["gzreader_update"]
    package.loaded["gzreader_update"] = nil; gsettings.gzreader_update_latest = nil
    check(tile() == "Updates" and package.loaded["gzreader_update"] == nil, "…before any check, the panel doesn't load the updater")
    package.loaded["gzreader_update"] = kept_mod
    local ran = 0
    local kept_run = Update.run
    Update.run = function() ran = ran + 1 end
    Panel.updatesTile().run()
    Update.run = kept_run
    check(ran == 1, "…a tap checks and offers it, as before")
    Update.state, Update.request = kept.state, kept.request
    gsettings.gzreader_update_latest, gsettings.gzreader_update_last_check, gsettings.gzreader_update_beta = kept.latest, kept.last, kept.beta
    if kept.version then wf(KO .. "/gzreader-version", kept.version) end
end)()
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
check(acmd:match("^i=2; while %[ %-f '/b/x%.m4b%.chunks'/c%$i%.aac %]; do cat '/b/x%.m4b%.chunks'/c%$i%.aac || break; i=%$%(%(i%+1%)%); done | gst%-launch%-0%.10 fdsrc ! mfw_aacdecoder ! ") and ast == 30000, "M4B: plays the converted chunks from the one holding 0:40 (starts 0:30)")
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
P2.pos = 5000
local pulled
P2:pull(function() pulled = true end)
check(captured.confirm and captured.confirm.text:match("1:50"), "Grimmory's position offered (track 2 @ 0:50 = 1:50)")
captured.confirm.ok_callback()
check(pulled and P2.pos == 110000, "jumps there")
-- nothing listened to here yet: Grimmory's place without asking
captured.confirm = nil
local P2b = Audiobook.Player:new(plugin, ab_done)
P2b.pos = 0
pulled = nil
P2b:pull(function() pulled = true end)
check(pulled and not captured.confirm and P2b.pos == 110000, "just downloaded: starts at Grimmory's place, no question")
-- syncing through a computer: the progress the page brought, without Wi-Fi
do
    local was = NET.connected
    NET.connected = false
    plugin.store.audiobooks[ab_done.id] = plugin.store.audiobooks[ab_done.id] or {}
    plugin.store.audiobooks[ab_done.id].grimmory_progress = { audiobookProgress = { positionMs = 20000, trackIndex = 1 } }
    local P2c = Audiobook.Player:new(plugin, ab_done)
    P2c.pos = 0
    pulled = nil
    P2c:pull(function() pulled = true end)
    check(pulled and P2c.pos == 80000 and plugin.store.audiobooks[ab_done.id].grimmory_progress == nil,
        "no Wi-Fi: the progress kept at download (track 2 @ 0:20 = 1:20), once")
    NET.connected = was
end
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
local function savedLogs()
    local count = 0
    for _i, logdir in ipairs({ plugin:libraryDir():match("^(.+)/[^/]+$"), require("datastorage"):getDataDir() .. "/cache" }) do
        pcall(function() for fname in require("libs/libkoreader-lfs").dir(logdir) do if fname:match("^gzreader%-log%-") then count = count + 1 end end end)
    end
    return count
end
local saved_before = savedLogs()
plugin:shareLog()
check(savedLogs() <= math.min(saved_before, 3), "sharing leaves no log file behind (" .. saved_before .. " -> " .. savedLogs() .. ")")
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


print("A line in the log for each start: how long until Home is on screen")
;(function()
    local OT = require("gzreader_opentiming")
    -- /proc/self/stat: the command name may hold spaces and brackets; starttime is field 22
    local stat = "4242 (lua jit (x)) S 1 4242 4242 0 -1 4194304 100 0 0 0 50 10 0 0 20 0 1 0 12345 1000 200"
    check(math.abs((OT.processAge(stat, "135.95 400.00", 100) or -1) - 12.5) < 1e-6,
        "the program's age: uptime minus its start (12.5 s)")
    check(OT.processAge("garbage", "10.0 0") == nil and OT.processAge(stat, "100.0 0", 100) == nil,
        "unreadable or impossible: no age")
    check(type(OT.processAge()) == "number", "this process's own age, from /proc")
    local line = OT.startupLine({ what = "Home", shown = 14.21, cpu = 9.06, plugin_at = 6.3, setup = 0.71,
        modules = 905, lua_mb = 15.32, free = 98, cached = 31, rss = 44 })
    check(line == "start: Home on screen 14.2 s after the program started (CPU 9.1 s) | GZreader started at 6.3 s, "
        .. "set up in 0.7 s | modules loaded 905, Lua memory 15.3 MB | free memory 98 MB (+ 31 MB cache), GZreader 44 MB",
        "the start's line: " .. line)
    check(OT.startupLine({}):find("^start: the first screen on screen %? s"), "missing figures: \"?\", not an error")
    -- the run: begun, set up, then refreshes until one has Home (or a book) on screen
    local Log = require("gzreader_log")
    local logged = {}
    local orig_info = Log.info
    Log.info = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    local saved_boot = OT.boot
    OT.boot = nil
    OT.bootBegin()
    OT.bootRefresh({ { widget = { _zen_home_focus_targets = {} } } })
    check(#logged == 0, "a refresh before GZreader is set up: not the end of the start")
    OT.bootReady()
    OT.bootRefresh({ { widget = { name = "filemanager" } } })
    check(#logged == 0, "the file manager alone: still starting (Home comes over it)")
    OT.bootRefresh({ { widget = { name = "filemanager" } }, { widget = { _zen_home_focus_targets = {} } } })
    check(#logged == 1 and logged[1]:find("^start: Home on screen [%d.]+ s") and logged[1]:find("modules loaded %d+"),
        "Home on screen: one line (" .. tostring(logged[1]) .. ")")
    OT.bootRefresh({ { widget = { _zen_home_focus_targets = {} } } })
    OT.bootBegin()
    check(#logged == 1 and OT.boot == false, "once a run")
    OT.boot = nil
    OT.bootBegin(); OT.bootReady()
    OT.bootRefresh({ { widget = { name = "ReaderUI" } } })
    check(#logged == 2 and logged[2]:find("^start: a book on screen"), "a book opened at start ends it too")
    OT.boot = nil
    OT.bootBegin(); OT.bootReady()
    local saved_fb = OT.BOOT_FALLBACK
    OT.BOOT_FALLBACK = -1 -- (a minute has gone by)
    OT.bootRefresh({ { widget = { name = "filemanager" } } })
    OT.BOOT_FALLBACK = saved_fb
    check(#logged == 3 and logged[3]:find("^start: the first screen on screen [%d.]+ s"),
        "neither Home nor a book within a minute: the start ends at that refresh")
    Log.info = orig_info
    OT.boot = saved_boot
end)()

print("No usage statistics (since 1.28.1); debug reports have their own setting")
;(function()
    local R = require("gzreader_remote")
    local lfs = require("libs/libkoreader-lfs")
    local function rd(p) local h = io.open(p, "rb"); local t = h and h:read("*a"); if h then h:close() end; return t end
    -- nothing records or sends usage statistics any more
    local uses = {}
    for name in lfs.dir(PLUGIN) do
        if name:match("%.lua$") and (rd(PLUGIN .. "/" .. name) or ""):find('require("gzreader_usage")', 1, true) then uses[#uses + 1] = name end
    end
    local Usb = require("gzreader_usbsync")
    check(not rd(PLUGIN .. "/gzreader_usage.lua") and #uses == 0 and Usb.usageInfo == nil and Usb.handOverUsage == nil
        and not (rd(PLUGIN .. "/gzreader_usbsync.lua") or ""):find("usage = ", 1, true),
        "no usage statistics: the module is gone, nothing calls it, the outbox has no usage " .. table.concat(uses, ","))
    -- debug reports: off unless chosen; a Full level carries over once, the rest is deleted
    local saved_dr, saved_u = gsettings.gzreader_debug_reports, gsettings.gzreader_usage
    gsettings.gzreader_debug_reports, gsettings.gzreader_usage = nil, nil
    check(R.setting() == false and R.SETTING == "gzreader_debug_reports", "debug reports: off by default")
    gsettings.gzreader_usage = "basic"
    check(R.setting() == false, "…off after Basic usage statistics")
    gsettings.gzreader_usage = "full"
    check(R.setting() == true, "…on after Full (Full sent them)")
    local udir = WORK .. "/gzreader-usage"
    lfs.mkdir(udir)
    local fh = io.open(udir .. "/queue.jsonl", "wb"); fh:write('{"type":"event"}\n'); fh:close()
    R.forgetUsage()
    check(gsettings.gzreader_debug_reports == true and gsettings.gzreader_usage == nil and not lfs.attributes(udir, "mode"),
        "at start: Full becomes debug reports on, the old level and the waiting statistics are deleted")
    check((rd(PLUGIN .. "/main.lua") or ""):find('require("gzreader_remote").forgetUsage()', 1, true),
        "…once a run, 15 s after start (main.lua)")
    gsettings.gzreader_debug_reports, gsettings.gzreader_usage = nil, "off"
    R.forgetUsage()
    check(gsettings.gzreader_debug_reports == false and gsettings.gzreader_usage == nil, "…Off (or Basic): debug reports off")
    R.forgetUsage()
    check(gsettings.gzreader_debug_reports == false, "…once: a choice made since stays")
    -- the random ID stays (it names this Kindle in reports)
    local id = gsettings.gzreader_usage_id
    gsettings.gzreader_usage_id = string.rep("ab", 16)
    check(R.id() == string.rep("ab", 16) and R.deviceName():match("%-ababab$"), "the Kindle's random ID is kept: reports name it as before")
    gsettings.gzreader_usage_id = id
    -- Settings → General: the switch
    local item = R.menuItem()
    check(item and item.text == "Send debug reports automatically" and not item.checked_func()
        and item.help_text:find("freezes and crashes", 1, true) and item.help_text:find("never passwords or tokens", 1, true),
        "Settings → General → Send debug reports automatically (says what it sends)")
    local Net = require("gzreader_net")
    local was_usb = Net.usb
    Net.usb = true
    check(R.menuItem() == nil and not R.enabled(), "a Kindle without Wi-Fi: no switch (it couldn't send)")
    Net.usb = was_usb
    gsettings.gzreader_debug_reports, gsettings.gzreader_usage = saved_dr, saved_u
end)()

print("Remote debugging (debug reports on)")
;(function()
    local R = require("gzreader_remote")
    local lfs = require("libs/libkoreader-lfs")
    check(R.normalize(" https://in.example.com/open/feed/abc/send \n") == "https://in.example.com/open/feed/abc", "feed address: /send etc. trimmed")
    check(R.normalize("nonsense") == nil, "not an address: refused")
    check(not R.testBuild("1.26.7") and R.testBuild("1.26.7-beta.abc1234") and R.feedUrl("1.26.7") == R.FEED
        and R.feedUrl("1.26.7-beta.abc1234") == R.TEST_FEED and R.FEED ~= R.TEST_FEED
        and R.FEED:match("/open/feed/%w+$") and R.TEST_FEED:match("/open/feed/%w+$"),
        "releases report to one feed, test builds to another")
    local started = 0
    R.startWatchdog = function() started = started + 1 end
    -- off (the default): nothing; a feed set by hand before is forgotten
    gsettings.gzreader_debug_reports = false
    plugin.store.remote_url, plugin.store.remote_profile = "https://in.example.com/open/feed/old", true
    R.started = false
    R.start(plugin)
    check(not R.on and started == 0 and plugin.store.remote_url == nil and plugin.store.remote_profile == nil,
        "off: nothing sent, no watchdog; the old hand-set feed is gone")
    -- on: the previous run didn't close normally
    R.LIVE_DIR = WORK .. "/live"
    lfs.mkdir(R.LIVE_DIR)
    local dir = R.dir()
    os.execute("rm -f '" .. dir .. "'/spool/*")
    local fh = io.open(dir .. "/heartbeat", "wb"); fh:write((os.time() - 600) .. " run reading big.epub p.40"); fh:close()
    fh = io.open(WORK .. "/gzreader.log.prev", "wb"); fh:write("2026 [INFO] the line before the freeze\n"); fh:close()
    R.menuItem().callback() -- (Settings: on; starts it: R.apply)
    check(R.on and started == 1 and gsettings.gzreader_debug_reports == true, "turned on: on at once, watchdog started")
    local cfg = io.open(dir .. "/config"):read("*a")
    check(cfg:sub(1, #R.feedUrl() + 1) == R.feedUrl() .. "\n" and cfg:match("\n" .. R.deviceName():gsub("%-", "%%-") .. "\n"),
        "the watchdog reports to this build's feed")
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
    -- the 15 s beat: to the RAM disk; the kept one only when the status changes or every KEEP s
    local function rd(p) local h = io.open(p, "rb"); local t = h and h:read("*a"); if h then h:close() end; return t end
    check(R.livePath():match("/live/gzreader%-heartbeat%.%d+$") and (rd(R.livePath()) or ""):match("^%d+ run "),
        "the beat goes to the live file (/tmp on a Kindle: no flash write)")
    local kept = io.open(dir .. "/heartbeat", "wb"); kept:write("100 run the kept one"); kept:close()
    R.beat("run")
    check(rd(dir .. "/heartbeat") == "100 run the kept one" and (rd(R.livePath()) or ""):match("^%d+ run "),
        "a beat while still running: only the live file is written")
    R.kept_at = os.time() - R.KEEP
    R.beat("run")
    check((rd(dir .. "/heartbeat") or ""):match("^%d+ run ") and rd(dir .. "/heartbeat") ~= "100 run the kept one",
        "…and every " .. R.KEEP .. " s the kept one too (when it was last seen, after a hard reboot)")
    -- a live beat left by a previous process (no reboot since): newer than the kept one, so it counts
    local prev_live = R.LIVE_DIR .. "/gzreader-heartbeat.999999"
    kept = io.open(prev_live, "wb"); kept:write((os.time() + 5) .. " run reading late.epub p.9"); kept:close()
    local prevb = R.previousBeat(dir)
    check(prevb and prevb:match("late%.epub p%.9") and not io.open(prev_live, "rb"), "the previous run's live beat is used and removed")
    kept = io.open(prev_live, "wb"); kept:write("50 run older"); kept:close()
    check(not R.previousBeat(dir):match("older"), "…unless the kept one is newer")
    -- the watchdog reads the newer of the two
    local wsrc = rd(PLUGIN .. "/gzreader_watchdog.lua") or ""
    check(wsrc:find('live_dir .. "/gzreader-heartbeat." .. ppid', 1, true) and (rd(PLUGIN .. "/gzreader_remote.lua") or ""):find("q(R.LIVE_DIR)", 1, true),
        "the watchdog is told where the live beat is, and reads it")
    -- warnings are gathered
    require("gzreader_log").warn("something odd")
    check(R.pending and #R.pending == 1 and R.pending[1]:match("something odd"), "warnings gathered for one report")
    R.onSuspend()
    check(io.open(dir .. "/heartbeat"):read("*a"):match("^%d+ sleep "), "asleep: the watchdog doesn't call it a freeze")
    R.event("queued before turning it off", "x")
    R.setSetting(false) -- (Settings or the setup guide: off; stops it)
    local left = 0
    for name in require("libs/libkoreader-lfs").dir(dir .. "/spool") do if name:match("%.json$") then left = left + 1 end end
    check(io.open(dir .. "/heartbeat"):read("*a"):match("^%d+ off") and left == 0 and not R.on and require("gzreader_log").on_line == nil,
        "turned off: queued reports dropped, heartbeat says off (the watchdog stops; no crash report at the next restart)")
    check(not io.open(R.livePath(), "rb"), "…and the live beat is gone")
    -- Diagnostics → Send to the developer
    local logf = WORK .. "/devlog.txt"
    local big = {}
    for k = 1, 3000 do big[#big + 1] = string.format("line %05d é a GZreader log line\n", k) end
    fh = io.open(logf, "wb"); fh:write(table.concat(big)); fh:close()
    local posts = {}
    local was_part, was_max = R.PART, R.MAX_PARTS
    R.PART, R.MAX_PARTS = 20000, 3
    local typed = "  The book froze when I turned the page, then the Kindle restarted. My token is Bearer abc123def  "
    local n = R.sendLogs(logf, typed, function(url, body) posts[#posts + 1] = { url = url, body = json.decode(body) }; return 201 end)
    local whole = ""
    for _i, p in ipairs(posts) do whole = whole .. p.body.eventContent end
    local valid = true
    for _i, p in ipairs(posts) do if p.body.eventContent:find("^[\128-\191]") then valid = false end end
    check(n == 3 and #posts == 3 and posts[1].url == R.REPORT_FEED .. "/send" and R.reportUrl() == R.REPORT_FEED
        and R.REPORT_FEED:match("/open/feed/cmw7f51fm0e318o2f94o54020$") and R.REPORT_FEED ~= R.FEED and R.REPORT_FEED ~= R.TEST_FEED
        and posts[1].body.eventName:match("^Debug report from .* %(1/3%): The book froze")
        and posts[3].body.eventName:match("%(3/3%)$") and posts[1].body.tags[3] == "debug-log" and posts[1].body.tags[5] == "with-comment",
        "the log goes to the report feed (releases and test builds alike), in parts, numbered; the first named after what was typed")
    check(posts[1].body.eventContent:match("What happened: The book froze when I turned the page, then the Kindle restarted%.")
        and not posts[1].body.eventContent:find("abc123def", 1, true) and not posts[2].body.eventContent:find("What happened", 1, true),
        "what was typed is at the top of the first part (a token in it redacted)")
    local quiet = {}
    R.sendLogs(logf, "", function(_u, body) quiet[#quiet + 1] = json.decode(body); return 201 end)
    check(quiet[1] and quiet[1].eventName:match("%(1/3%)$") and quiet[1].eventContent:match("What happened: %(nothing typed%)")
        and quiet[1].tags[5] == nil, "nothing typed: sent anyway, and says so")
    check(whole:match("line 03000") and not whole:match("line 00001") and whole:match("The last %d+ KB of %d+ KB") and valid,
        "a long log: its newest part (says so), never cut inside a character")
    local failed = { R.sendLogs(logf, nil, function() return 500 end) }
    local offline = { R.sendLogs(logf, nil, function() return nil end) }
    check(failed[1] == nil and failed[2] == "http_500" and offline[2] == "unreachable" and R.sendLogs(WORK .. "/none.txt") == nil,
        "not sent: says why")
    R.PART, R.MAX_PARTS = was_part, was_max
    os.remove(logf)
    R.on = false
    require("gzreader_log").on_line = nil
    gsettings.gzreader_debug_reports = nil
    -- the menus
    local src = io.open(debug.getinfo(R.start, "S").source:sub(2):gsub("gzreader_remote%.lua$", "main.lua"), "rb")
    local text = src and src:read("*a") or ""
    if src then src:close() end
    check(not text:find("gzreader_remote\").menuItems", 1, true) and R.menuItems == nil
        and text:find('_("Send to the developer")', 1, true) and text:find("function Grimmory:sendLogToDeveloper", 1, true),
        "no Remote debugging settings; Diagnostics has Send to the developer")
    -- the box for what happened, then the send with what was typed
    local was_send = plugin.sendLogToDeveloper
    local sent_with
    local UIManager = require("ui/uimanager")
    local orig_tick, orig_show, orig_close = UIManager.nextTick, UIManager.show, UIManager.close
    UIManager.nextTick = function(_self, fn) fn() end
    UIManager.show = function() end
    UIManager.close = function() end
    plugin.sendLogToDeveloper = function(_self, c) sent_with = c end
    -- (a stand-in dialog: the real one needs a screen)
    local real_input = package.loaded["ui/widget/inputdialog"]
    package.loaded["ui/widget/inputdialog"] = { new = function(_self, o) o.onShowKeyboard = function() end; return o end }
    local dlg = plugin:askReportComment()
    package.loaded["ui/widget/inputdialog"] = real_input
    dlg.getInputText = function() return "the calendar was empty" end
    for _i, row in ipairs(dlg.buttons) do for _j, b in ipairs(row) do if b.text == "Send" then b.callback() end end end
    plugin.sendLogToDeveloper = was_send
    UIManager.nextTick, UIManager.show, UIManager.close = orig_tick, orig_show, orig_close
    check(dlg.title == "Send to the developer" and dlg.allow_newline and sent_with == "the calendar was empty",
        "Send to the developer asks what happened first, and sends what was typed")
end)()

print("The log: lines written together, not one write per line")
;(function()
    local Log = require("gzreader_log")
    local bpath = WORK .. "/buffered.log"
    local keep_path, keep_main = Log.path, Log.main_pid
    local function rd() local fh = io.open(bpath, "rb"); local t = fh and fh:read("*a") or ""; if fh then fh:close() end; return t end
    os.remove(bpath)
    Log.init(WORK)
    Log.path = bpath
    local LUI = require("ui/uimanager")
    local real_in = LUI.scheduleIn
    local timers = {}
    LUI.scheduleIn = function(_ui, s, fn) timers[#timers + 1] = { s = s, fn = fn } end
    Log.buffered = true
    Log.info("first line")
    Log.info("second line")
    check(rd() == "" and #timers == 1 and timers[1].s == Log.FLUSH_AFTER, "INFO lines wait in memory; one write planned")
    timers[1].fn()
    local t = rd()
    check(t:match("first line\n.*second line\n$"), "…written together, in order, a few seconds later")
    Log.info("before a warning")
    Log.warn("a warning")
    check(rd():match("before a warning\n.*a warning\n$"), "a warning: written at once, with what came before it")
    Log.info("waiting at sleep")
    Log.flush()
    check(rd():match("waiting at sleep\n$"), "Log.flush (sleep, exit, export) writes what's waiting")
    local was_max = Log.MAX_BUFFER
    Log.MAX_BUFFER = 200
    for k = 1, 6 do Log.info(string.rep("x", 40), k) end
    check(rd():match("x+ %d\n$"), "a lot waiting: written without waiting for the timer")
    Log.MAX_BUFFER = was_max
    -- a background process (another pid) writes at once and drops the parent's lines
    Log.info("the parent's line")
    Log.main_pid = -1
    Log.info("the child's line")
    t = rd()
    check(t:match("the child's line\n$") and not t:find("the parent's line", 1, true), "a background process: its own lines at once, not the parent's")
    Log.main_pid = keep_main
    -- export includes what's waiting
    Log.info("just before export")
    local dest = Log.exportTo(WORK)
    local ef = dest and io.open(dest, "rb")
    local et = ef and ef:read("*a") or ""
    if ef then ef:close(); os.remove(dest) end
    check(et:find("just before export", 1, true), "Save/Send the log: includes the lines still waiting")
    local msrc = io.open(PLUGIN .. "/main.lua", "rb")
    local mtext = msrc and msrc:read("*a") or ""
    if msrc then msrc:close() end
    check(mtext:find("Log.flush()\n        Log.buffered = false\n        return orig_quit", 1, true)
        and select(2, mtext:gsub("Log%.flush%(%)", "")) >= 3, "flushed on exit (then every line at once), sleep and settings flush")
    LUI.scheduleIn = real_in
    Log.buffered = false
    Log.path, Log.main_pid = keep_path, keep_main
    os.remove(bpath)
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
    gsettings.gzreader_wifi_mode = "auto"
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
    NET.connected, gsettings.gzreader_wifi_on_demand, gsettings.gzreader_wifi_mode = was_c, was_wod, nil
    Net.connecting, Net.ours = nil, false
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

    do -- the icon font (pin, place, file, image, tag, date) is found where Font:getFace looks: <fonts folder>/<name>
        local ko = arg[5]
        local function opens(dir, name)
            local fh = io.open(dir .. "/" .. name, "rb")
            if fh then fh:close() end
            return fh ~= nil
        end
        local rel = Sticky.iconFontName("./fonts")
        local abs = Sticky.iconFontName(ko .. "/fonts", ko)
        check(rel == "../plugins/zenos.koplugin/fonts/SymbolsNerdFont-Regular.ttf" and opens(ko .. "/fonts", rel),
            "Notes icons: the icon font is found from KOReader's fonts folder (" .. rel .. ")")
        check(opens(ko .. "/fonts", abs) and not opens(ko .. "/fonts", "./plugins/zenos.koplugin/fonts/SymbolsNerdFont-Regular.ttf"),
            "…and from a fonts folder given in full (the old path wasn't found: " .. abs .. ")")
    end

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
    do -- the bar next to an event is as tall as it's drawn, so a row centres it on the title
        -- (real geometry and HorizontalGroup here: the rest of this file has stand-ins)
        local REAL = { "ui/geometry", "ui/widget/eventlistener", "ui/widget/widget",
            "ui/widget/container/widgetcontainer", "ui/widget/horizontalgroup" }
        local saved = { gzreader_calendar = package.loaded["gzreader_calendar"], ["ui/bidi"] = package.loaded["ui/bidi"],
            optmath = package.loaded["optmath"] }
        for _i, rn in ipairs(REAL) do saved[rn] = package.loaded[rn] end
        local Dev = require("device")
        local was_screen = Dev.screen
        local scr = magic()
        scr.scaleBySize = function(_, v) return v end
        local ok_m, res = pcall(function()
            Dev.screen = scr
            package.loaded["ui/bidi"] = { mirroredUILayout = function() return false end }
            package.loaded["optmath"] = { round = function(x) return math.floor(x + 0.5) end }
            for _i, rn in ipairs(REAL) do package.loaded[rn] = dofile(arg[5] .. "/frontend/" .. rn .. ".lua") end -- (arg[5]: KOReader)
            package.loaded["gzreader_calendar"] = nil
            local Cal2 = require("gzreader_calendar")
            local mk = Cal2.marker({ title = "Rent" }, 40)
            local row = package.loaded["ui/widget/horizontalgroup"]:new{ align = "center", mk, Cal2.marker({ title = "x" }, 54) }
            local size = row:getSize()
            return { h = mk:getSize().h, w = mk:getSize().w, top = math.floor((size.h - row._offsets[1].y) / 2) }
        end)
        Dev.screen = was_screen
        for rn, v in pairs(saved) do package.loaded[rn] = v end
        check(ok_m and res.h == 40 and res.w == 3 and res.top == 7,
            "the event's calendar bar is centred on its row: " .. (ok_m and (res.w .. "x" .. res.h .. " from y " .. res.top) or tostring(res)))
    end

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
    -- copying connections to another GZreader (gzreader_copy.lua)
    do
        local Copy = require("gzreader_copy")
        local Spake = require("gzreader_spake")
        Cal.addFeeds(plugin, { { url = link, name = "Family" } })
        Cal.feeds(plugin)[1].enabled = false
        local S = { plugin = plugin, pin = "246810", tries = 0 }
        local sent
        S.on_sent = function(x) sent = x end
        local orig_req = Copy.request
        Copy.request = function(_dev, method, path, tbl)
            local code, _ct, body = Copy.serve(S, method, path, tbl and json.encode(tbl))
            return code, json.decode(body)
        end
        local saves = 0
        local other = { store = {}, save = function() saves = saves + 1 end,
            api = { isPaired = function() return false end } }
        local dev = { ip = "127.0.0.1", port = 8650, name = "Sender" }
        local code, hello = Copy.request(dev, "GET", "/gzcopy/hello")
        check(code == 200 and hello.app == "GZreader" and hello.name:match("^Kindle Keyboard · %x%x%x%x$"), "copy: the sender says its name " .. tostring(hello.name))
        -- a wrong PIN: found out before anything is asked for
        local ch, why = Copy.open(other, dev, "111111")
        check(ch == nil and why == "pin" and S.tries == 1, "copy: a wrong PIN is refused (and counts as a try)")
        ch = Copy.open(other, dev, "246810")
        local o = ch and ch.offer
        check(o and o.grimmory and o.grimmory.username == "will" and o.memos and o.memos.user == "Will" and o.caldav
            and o.caldav.calendars == 2 and #o.links == 1 and o.links[1].name == "Family", "copy: the right PIN shows what the sender has")
        local otxt = json.encode(o or {})
        check(not otxt:find("memos-test-token", 1, true) and not otxt:find("demo-app-password", 1, true) and not otxt:find("abc123", 1, true),
            "copy: what's shown has no token, password or link in it")
        -- the whole exchange as it goes over the Wi-Fi: nothing secret in the clear
        local wire = {}
        local inner = Copy.request
        Copy.request = function(d, m, p, t)
            local c2, r = inner(d, m, p, t)
            wire[#wire + 1] = json.encode(t or {}) .. json.encode(r or {})
            return c2, r
        end
        local data = Copy.fetch(ch, { grimmory = true, memos = true, caldav = true, links = { 1 } })
        Copy.request = inner
        local wtxt = table.concat(wire)
        check(data and data.memos.token == "memos-test-token" and data.caldav.password == "demo-app-password"
            and data.caldav.hidden[1] == href and data.links[1].enabled == false, "copy: the chosen connections arrive")
        check(not wtxt:find("memos-test-token", 1, true) and not wtxt:find("demo-app-password", 1, true) and not wtxt:find("abc123", 1, true)
            and #wtxt > 0, "copy: tokens, passwords and links travel encrypted")
        check(data and data.grimmory and data.grimmory.username == "will" and data.grimmory.refresh_token == nil
            and not json.encode(data):find(plugin.store.refresh_token, 1, true), "copy: Grimmory's address and account only, never its sign-in")
        check(sent and sent.to == "Kindle Keyboard · " .. Copy.deviceId(other):sub(1, 4):upper() and sent.what:match("Notes"), "copy: the sender shows who got what")
        check(Copy.fetch(ch, { memos = true }) == nil, "copy: the PIN is for one copy only")
        check(sent and sent.pin and sent.pin ~= "246810" and S.pin == sent.pin and S.tries == 0,
            "copy: after a copy the sender has a new PIN (and its tries back)")
        local chx = Copy.open(other, dev, "246810")
        check(chx == nil, "copy: the old PIN no longer works")
        local ch2 = Copy.open(other, dev, S.pin)
        local data2 = ch2 and Copy.fetch(ch2, { memos = true })
        check(data2 and data2.memos and data2.memos.token == "memos-test-token" and data2.caldav == nil,
            "copy: a second copy (Notes after the calendars) with the new PIN")
        -- the receiving side connects with each
        local res = Copy.apply(other, data)
        check(other.store.memos and other.store.memos.token == "memos-test-token" and res.notes, "copy: Notes connected on the other device")
        check(other.store.caldav and #other.store.caldav.calendars == 2 and res.calendar, "copy: CalDAV account connected on the other device")
        local hidden_ok = false
        for _i, cal in ipairs(other.store.caldav.calendars) do if cal.href == href then hidden_ok = cal.enabled == false end end
        check(hidden_ok, "copy: the calendar hidden on the sender is hidden here too")
        local of = (other.store.calendar_feeds or {})[1]
        check(of and of.name == "Family" and of.enabled == false and of.url == Cal.feeds(plugin)[1].url, "copy: the calendar link, its name and shown or hidden")
        check(res.grimmory and res.grimmory.server == plugin.store.server and table.concat(res.lines, "\n"):match("Notes: connected"),
            "copy: Grimmory left to sign in, the rest listed")
        -- a payload that doesn't check out: said so, nothing kept
        local bad = { store = {}, save = function() end, api = { isPaired = function() return false end } }
        local r2 = Copy.apply(bad, { memos = { server = "127.0.0.1:" .. MP, token = "not-it" } })
        check(bad.store.memos == nil and r2.lines[1]:match("^✗ Notes"), "copy: a connection that fails is reported, not kept")
        -- 5 tries, then no more
        local S2 = { plugin = plugin, pin = "000001", tries = 0 }
        Copy.request = function(_dev, method, path, tbl)
            local c3, _ct, body = Copy.serve(S2, method, path, tbl and json.encode(tbl))
            return c3, json.decode(body)
        end
        for _i = 1, 5 do Copy.open(other, dev, "999999") end
        local ch3, why3 = Copy.open(other, dev, "000001")
        check(ch3 == nil and why3 == "tries", "copy: after 5 tries even the right PIN is refused")
        -- what's ticked to begin with: what this device doesn't have, or the tab's own
        local fresh = { store = {}, api = { isPaired = function() return false end } }
        local o2 = { grimmory = {}, memos = {}, caldav = {}, links = { { n = 1, name = "Family" } } }
        check(Copy.defaults(fresh, o2, nil).memos and Copy.defaults(fresh, o2, nil).links[1] and Copy.defaults(fresh, o2, nil).grimmory,
            "copy: a new device: everything ticked")
        local d2 = Copy.defaults(fresh, o2, "notes")
        check(d2.memos and not d2.caldav and not d2.grimmory and not d2.links[1], "copy from the Notes tab: Notes only")
        local d3 = Copy.defaults(other, o2, nil)
        check(not d3.memos and not d3.caldav and not d3.links[1] and d3.grimmory, "copy: what this device already has isn't ticked")
        Copy.request = orig_req
        -- a device that never answers: given up on in its time (not LuaSocket's 60 s)
        local mute = socket.bind("127.0.0.1", 0)
        local _mip, mport = mute:getsockname()
        local t0 = socket.gettime()
        local mc, mwhy = Copy.request({ ip = "127.0.0.1", port = mport }, "GET", "/gzcopy/hello", nil, 1)
        local took = socket.gettime() - t0
        mute:close()
        check(mc == nil and mwhy == "unreachable" and took < 4 and require("socket.http").TIMEOUT == 60,
            string.format("copy: a device that never answers: unreachable after %.1f s, http's own timeout put back", took))
        -- PINs: 6 digits
        local p1, p2 = Spake.pin(), Spake.pin()
        check(p1:match("^%d%d%d%d%d%d$") and p2:match("^%d%d%d%d%d%d$"), "copy: 6-digit PINs")
        while #Cal.feeds(plugin) > 0 do Cal.removeFeed(plugin, 1) end
    end
    -- the page's tabs; Plex (its own sign-in page, then back); Access
    do
        local PXP = PORT + 11
        os.execute("python3 -I " .. PLUGIN .. "/../../tools/gzreader/tests/mock_plex.py " .. PXP .. " > " .. WORK .. "/plex.log 2>&1 & echo $! > " .. WORK .. "/plex.pid")
        -- (not runLoop: it would run the page's idle timer too)
        for _try = 1, 50 do
            local pp = io.popen("curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:" .. PXP .. "/ctl/log"); local cc = pp:read("*a"); pp:close()
            if cc == "200" then break end
            socket.sleep(0.2)
        end
        local Plex = require("gzreader_plex")
        Plex.TV = "http://127.0.0.1:" .. PXP
        c, b = phone("'" .. P .. "'")
        check(c == 200 and b:find('data-tab="grimmory"', 1, true) and b:find('data-tab="music"', 1, true) and b:find('data-tab="access"', 1, true)
            and b:find('<section id="music" class="tab">', 1, true) and b:find('<section id="books" class="tab">', 1, true)
            and b:find('"calendar";', 1, true), "phone page: tabs (Grimmory, Notes, Calendar, Music, Send books, Access), opening at Calendar")
        local hdr = WORK .. "/plex_hdr.txt"
        c = phone("-d '' -D '" .. hdr .. "' '" .. P .. "/plex/oauth'")
        local hf = io.open(hdr); local htxt = hf and hf:read("*a") or ""; if hf then hf:close() end
        local loc = htxt:match("[Ll]ocation: ([^\r\n]+)") or ""
        local S0 = Phone.session
        check(c == 302 and loc:match("^https://app%.plex%.tv/auth#%?") and loc:find("clientID=gzreader-", 1, true) and loc:find("code=strongcode", 1, true)
            and loc:find("forwardUrl=http%3A%2F%2F", 1, true) and loc:find("%2Fplex%2Fdone", 1, true)
            and loc:find("context%5Bdevice%5D%5Bproduct%5D=GZreader", 1, true), "Plex on the phone: off to Plex's own sign-in page, back to /plex/done " .. tostring(c) .. " " .. loc)
        os.execute("curl -s 'http://127.0.0.1:" .. PXP .. "/ctl/claim?id=" .. S0.plex_pin.id .. "' >/dev/null")
        c, b = phone("-L '" .. P .. "/plex/done'")
        local ps = plugin.store.plex or {}
        check(c == 200 and b:match("Signed in to Plex as will %(Home Server%)") and ps.token == "plex-token" and ps.username == "will"
            and ps.server.uri == "http://127.0.0.1:" .. PXP and ps.server.token == "srv-token" and #ps.servers == 2,
            "Plex: back from its sign-in: signed in, the owned server, the address that answers")
        check(not json.encode(ps):find("secret@example.com", 1, true), "Plex: the account's e-mail isn't kept")
        c, b = phone("'" .. P .. "#music'")
        check(b:find("Signed in as <b>will</b> · Home Server", 1, true) and b:find('name="id"', 1, true), "phone page: Plex signed in, the servers to choose from")
        -- Access: the key for a Cloudflare rule
        c, b = post("/access", { "enabled=1", "hosts=photos.example.com" })
        local ac = plugin.store.access or {}
        local Access = require("gzreader_access")
        check(c == 200 and ac.enabled and type(ac.key) == "string" and #ac.key == 32 and b:find(ac.key, 1, true)
            and b:find("http.host in {", 1, true) and b:find('x-gzreader-key', 1, true), "Access: a key made, the Cloudflare rule shown")
        local h1, h2, h3 = Access.headersFor("https://photos.example.com/a"), Access.headersFor("https://x.photos.example.com/"),
            Access.headersFor("https://plex.tv/api")
        check(h1 and h1["X-GZreader-Key"] == ac.key and h2 and h3 == nil and Access.headersFor("https://example.com") == nil
            and Access.headersFor(plugin.store.server .. "/api/v1/x") ~= nil, "Access: the key goes to your servers only (and their subdomains)")
        c, b = post("/access", { "enabled=1", "hosts=photos.example.com", "cf_id=abc.access", "cf_secret=s3cr3t" })
        h1 = Access.headersFor("https://photos.example.com/a")
        check(h1 and h1["CF-Access-Client-Id"] == "abc.access" and h1["CF-Access-Client-Secret"] == "s3cr3t" and not b:find("s3cr3t", 1, true),
            "Access: a Cloudflare Access service token (the secret not shown back)")
        local key_before = ac.key
        post("/access", { "hosts=", "cf_id=abc.access" })
        local hs = Access.headersFor(plugin.store.server .. "/x")
        check(not plugin.store.access.enabled and hs and hs["X-GZreader-Key"] == nil and hs["CF-Access-Client-Id"] == "abc.access"
            and plugin.store.access.key == key_before, "Access: the key off (kept for later), the token still sent")
        post("/access", { "hosts=", "cf_clear=1" })
        check(Access.headersFor(plugin.store.server .. "/x") == nil, "Access: everything off")
        _G.__gz_access_key = key_before
    end
    -- disconnecting from the phone
    c, b = post("/memos/disconnect", {})
    check(c == 200 and not (plugin.store.memos or {}).token, "Notes: disconnected from the phone")
    c, b = post("/caldav/disconnect", {})
    check(c == 200 and not Cal.client(plugin):isConnected(), "Calendar: CalDAV account disconnected from the phone")
    local lg = io.open(WORK .. "/gzreader.log", "rb"); local ltxt = lg and lg:read("*a") or ""; if lg then lg:close() end
    check(not ltxt:find("demo-app-password", 1, true) and not ltxt:find("memos-test-token", 1, true) and not ltxt:find("abc123", 1, true)
        and not ltxt:find("plex-token", 1, true) and not ltxt:find("srv-token", 1, true) and not ltxt:find("s3cr3t", 1, true)
        and not ltxt:find(_G.__gz_access_key or "nokey", 1, true),
        "no password, token, key or calendar link in the log")
    scr.on_cancel()
    check(closed and closed.notes and closed.calendar and closed.books == 3 and #UI.zmqs == 0 and Phone.session == nil,
        "Back on the Kindle: the page closes, the caller hears what changed")
    for _i, n in ipairs({ "My Book.epub", "My Book (2).epub", "escape.epub" }) do os.remove(libdir .. "/" .. n) end
    PS.new = orig_ps
    os.execute("kill $(cat " .. WORK .. "/memos3.pid) 2>/dev/null")
    os.execute("kill $(cat " .. WORK .. "/feeds.pid) 2>/dev/null")
    os.execute("kill $(cat " .. WORK .. "/caldav2.pid) 2>/dev/null")
end)()

print("Music (Plex): the server, downloads, the player")
;(function()
    local Plex = require("gzreader_plex")
    local Music = require("gzreader_music")
    local Engine = require("gzreader_audioengine")
    local PXP = PORT + 11
    local plex = Music.plex(plugin)
    plugin.store.plex.token = nil
    -- sign-in on the Kindle: a code for plex.tv/link
    local pin = plex:newPin(false)
    check(pin and #pin.code == 4 and plex:checkPin(pin) == nil, "Plex: a 4-character code, not signed in yet")
    os.execute("curl -s 'http://127.0.0.1:" .. PXP .. "/ctl/claim?id=" .. pin.id .. "' >/dev/null")
    local token = plex:checkPin(pin)
    check(token == "plex-token" and plex:connect(token) and plex:isConnected(), "Plex: signed in with the code")
    check(plex:connect("wrong") == nil, "Plex: a bad token is refused")
    plex:connect(token)
    local secs = plex:musicSections()
    check(secs and #secs == 3 and secs[1].key == "1" and secs[2].key == "4" and secs[2].title == "Concerts" and secs[3].title == "Audiobooks",
        "Plex: the music libraries (not the films)")
    do -- the music library to browse: the one chosen in Settings (on this server), else the server's first
        local MusicTab = require("gzreader_musictab")
        local Cache = require("gzreader_listcache")
        local px = plugin.store.plex
        local saved_ms, saved_save = px.music_section, plugin.save
        plugin.save = function() end
        px.music_section = nil
        local first, all0 = plex:musicSection()
        check(first and first.key == "1" and #all0 == 3 and MusicTab.libraryText(plugin) == "Music library: the server's first"
            and MusicTab.only(plex) == "1", "Plex: nothing chosen: the first music library (playlists and search kept to it, the server has two)")
        local ckey = tostring(plugin.store.server) .. "|" .. tostring(plugin.store.username) .. "|shop:mu_recent"
        Cache.put(ckey, { { type = "album", key = "201" } })
        -- the choice, as Settings → Connections → Plex → Music library offers it
        local saved_net, saved_bd = require("gzreader_net").run, package.loaded["ui/widget/buttondialog"]
        local dlg, picked
        require("gzreader_net").run = function(fn) fn() end
        package.loaded["ui/widget/buttondialog"] = { new = function(_self, o) dlg = o; return o end }
        MusicTab.chooseLibrary(plugin, function() picked = true end)
        runLoop(function() return dlg ~= nil end, 15)
        local labels = {}
        for _i, row in ipairs(dlg and dlg.buttons or {}) do labels[#labels + 1] = row[1].text end
        check(dlg and dlg.title == "Music library" and table.concat(labels, ",") == "\u{2713} Music,Concerts,Audiobooks",
            "Plex: Music library offers the server's music libraries, the one in use ticked " .. table.concat(labels, ","))
        if dlg then dlg.buttons[2][1].callback() end
        require("gzreader_net").run, package.loaded["ui/widget/buttondialog"] = saved_net, saved_bd
        local chosen, all = plex:musicSection()
        local albums4 = plex:list(chosen.key, "albums", 0)
        check(picked and px.music_section.key == "4" and px.music_section.server == px.server.id and chosen.key == "4" and #all == 3
            and albums4[1].title == "Live Album" and MusicTab.libraryText(plugin) == "Music library: Concerts",
            "Plex: Concerts chosen: kept for this server, its albums listed")
        local rec = Cache.get(ckey)
        check(type(rec) == "table" and #rec == 0, "Plex: another library chosen: the Catalog's Music shelves are asked for again")
        check(#plex:playlists(MusicTab.only(plex)) == 0 and plex:search("live", MusicTab.only(plex)).albums[1].key == "205"
            and #plex:search("tone", MusicTab.only(plex)).tracks == 0, "Plex: with two music libraries, playlists and search keep to the one chosen")
        local Plex1 = require("gzreader_plex")
        check(Plex1.pickSection(all, px.music_section, { id = "another" }).key == "1"
            and Plex1.pickSection(all, { server = px.server.id, key = "9" }, px.server).key == "1",
            "Plex: a library chosen on another server, or one that's gone: the server's first")
        px.music_section, plugin.save = saved_ms, saved_save
    end
    do -- audiobooks from a Plex library (Settings → Connections → Plex → Audiobooks)
        local MusicTab = require("gzreader_musictab")
        local PA = require("gzreader_plexaudio")
        local ABk = require("gzreader_audiobook")
        local px = plugin.store.plex
        local saved_ab, saved_save = px.audiobook_section, plugin.save
        plugin.save = function() end
        px.audiobook_section = nil
        check(PA.section(plugin) == nil and MusicTab.audiobooksText(plugin) == "Audiobooks: from Grimmory", "Plex audiobooks: Grimmory's until a Plex library is chosen")
        local saved_net, saved_bd = require("gzreader_net").run, package.loaded["ui/widget/buttondialog"]
        local dlg
        require("gzreader_net").run = function(fn) fn() end
        package.loaded["ui/widget/buttondialog"] = { new = function(_self, o) dlg = o; return o end }
        MusicTab.chooseAudiobooks(plugin)
        runLoop(function() return dlg ~= nil end, 15)
        local labels = {}
        for _i, row in ipairs(dlg and dlg.buttons or {}) do labels[#labels + 1] = row[1].text end
        check(table.concat(labels, ",") == "\u{2713} Grimmory,Plex: Music,Plex: Concerts,Plex: Audiobooks",
            "Plex audiobooks: Audiobooks from offers Grimmory and the server's music libraries " .. table.concat(labels, ","))
        if dlg then dlg.buttons[4][1].callback() end
        require("gzreader_net").run, package.loaded["ui/widget/buttondialog"] = saved_net, saved_bd
        local sec = PA.section(plugin)
        check(sec and sec.key == "5" and px.audiobook_section.server == px.server.id and MusicTab.audiobooksText(plugin) == "Audiobooks: from Plex (Audiobooks)",
            "Plex audiobooks: the Audiobooks library chosen, for this server")
        local Plex1 = require("gzreader_plex")
        local mfirst = plex:musicSection()
        px.audiobook_section = { server = px.server.id, key = "1", title = "Music" }
        local mskip = plex:musicSection()
        px.audiobook_section = { server = px.server.id, key = "5", title = "Audiobooks" }
        check(mfirst.key == "1" and mskip.key == "4" and Plex1.audiobookSection({ audiobook_section = px.audiobook_section, server = px.server }) == nil,
            "Plex: music skips the audiobook library when nothing's chosen for music; signed out: Grimmory's audiobooks")
        -- a book: its tracks, chapters, summary
        local pinfo = plex:audiobookInfo("206")
        local one = plex:audiobookInfo("207")
        local pbk = pinfo and ABk.describe("plex-206", pinfo)
        local pbk1 = one and ABk.describe("plex-207", one)
        check(pbk and #pbk.tracks == 2 and pbk.tracks[2].start == 3000 and pbk.tracks[2].plex_key == "307" and pbk.files[1] == "track-001.mp3"
            and pbk.plex.key == "206" and pbk.plex.thumb == "/library/metadata/206/thumb/1" and pbk.author == "Narr Author" and pbk.description == "A book in two parts."
            and pbk.chapters[2].title == "Part 2", "Plex audiobook: an album's tracks as its files and chapters, the summary as its description")
        check(pbk1 and #pbk1.tracks == 1 and pbk1.files[1] == "track-001.m4a" and #pbk1.chapters == 2 and pbk1.chapters[2].title == "Closing"
            and pbk1.chapters[2].startTimeMs == 1500, "Plex audiobook: one M4B/M4A file with Plex's chapters")
        -- where it was listened to last (any Plex player)
        local LL = Plex1.lastListened
        local llp = LL({ { key = "1", viewed = 10, views = 1 }, { key = "2", viewed = 20, offset = 500 } })
        local lf = LL({ { key = "1", viewed = 30, views = 1 }, { key = "2" } })
        check(LL({ { key = "1" } }) == false and llp.track == "2" and llp.offset == 500 and lf.track == "1" and lf.finished,
            "Plex audiobook: the place is the track listened to last (in it, or after it when played through)")
        check(ABk.plexMs(pbk, { track = "307", offset = 700 }) == 3700 and ABk.plexMs(pbk, { track = "306", offset = 0, finished = true }) == 3000
            and ABk.plexMs(pbk, { track = "999" }) == nil and ABk.plexMs(pbk, false) == nil, "Plex audiobook: Plex's place as a time in the book")
        -- download it
        local summary = PA.book({ type = "album", key = "206", title = "Two Part Book", artist = "Narr Author", thumb = "/library/metadata/206/thumb/1" })
        check(summary.id == "plex-206" and summary.primaryFileType == "AUDIOBOOK" and summary.authors[1] == "Narr Author", "Plex audiobook: an album as an audiobook summary")
        local got
        ABk.download(plugin, summary, function(bk, err) got = bk or err or false end)
        runLoop(function() return got ~= nil end, 30)
        local mp3 = io.open(PLUGIN .. "/../../tools/gzreader/tests/media/tone.mp3", "rb"):read("*a")
        local f2 = type(got) == "table" and io.open(got.dir .. "/track-002.mp3", "rb")
        local d2 = f2 and f2:read("*a"); if f2 then f2:close() end
        check(type(got) == "table" and got.plex.key == "206" and d2 == mp3 and require("libs/libkoreader-lfs").attributes(got.dir .. "/cover.jpg", "mode") == "file"
            and plugin.store.audiobooks["plex-206"].plex_thumb == "/library/metadata/206/thumb/1" and ABk.load(plugin, "plex-206") ~= nil,
            "Plex audiobook downloaded: its tracks, Plex's cover, kept like Grimmory's " .. tostring(type(got) ~= "table" and got or ""))
        -- the place goes to Plex, and comes from it
        if type(got) == "table" then
            local PlA = ABk.Player:new(plugin, got)
            PlA.pos = 4200
            PlA:push()
            PlA:save()
            local pp = io.popen("curl -s http://127.0.0.1:" .. PXP .. "/ctl/progress"); local pr = json.decode(pp:read("*a")); pp:close()
            check(pr["307"] and pr["307"].offset == 1200 and pr["307"].state == "stopped" and pr["306"] == nil,
                "Plex audiobook: the place sent to Plex as the track's position (1.2 s into part 2)")
            os.execute("curl -s 'http://127.0.0.1:" .. PXP .. "/ctl/progress?key=306&offset=2500&at=" .. (os.time() + 100) .. "' >/dev/null")
            local PlB = ABk.Player:new(plugin, got)
            local offered
            PlB.offerRemote = function(_s, ms, from_plex, done) offered = { ms, from_plex }; done() end
            local plx_pulled
            PlB:pull(function() plx_pulled = true end)
            runLoop(function() return plx_pulled end, 10)
            check(plx_pulled and offered and offered[1] == 2500 and offered[2] == true,
                "Plex audiobook: Plex's place offered (another player's, part 1 at 2.5 s)")
            local PlC = ABk.Player:new(plugin, got)
            PlC.pos = 0
            PlC:offerRemote(120000, true, function() end)
            check(PlC.pos == 120000, "Plex audiobook: nothing listened to here: Plex's place, no question")
        end
        -- the Catalog's Audiobooks page with Plex's
        local saved_audio = require("gzreader_touch").audio
        require("gzreader_touch").audio = function() return true end
        local Brw = require("gzreader_browser")
        local ab = Brw:new(plugin)
        ab:show({ section = "audiobooks" })
        local ids = {}
        for _i, it in ipairs(ab.menu.item_table) do ids[#ids + 1] = it.gz_id end
        local last = ab.menu.item_table[#ab.menu.item_table]
        check(table.concat(ids, ",") == "ab_search,ab_continue,ab_recent,ab_all,ab_authors,ab_account" and last.text == "Plex"
            and tostring(last.mandatory):match("^Audiobooks · ") and ab.menu.item_table.gz_root,
            "Catalog → Audiobooks from Plex: search, the shelves, All, Authors and the Plex card (no On this Kindle) " .. table.concat(ids, ",") .. " / " .. tostring(last.mandatory))
        ;(function() -- not signed in to Grimmory: Plex's audiobooks all the same
            local nb = Brw:new(plugin)
            nb.api = setmetatable({ isPaired = function() return false end }, { __index = plugin.api })
            nb.section = "audiobooks"
            local items = nb:rootItems()
            check(not items.gz_signed_out and #items == 6 and items[6].text == "Plex" and items[1].text == "Search audiobooks…",
                "Plex audiobooks: not signed in to Grimmory, the page is Plex's as usual")
        end)()
        ;(function() -- the Plex card: its list, a change shown in place, back to the page made again
            local m = ab.menu
            local root_before, saved_br = m.item_table, px.bitrate
            m.onClose = function(menu)
                local t = table.remove(menu.item_table_stack)
                if t then menu:switchItemTable(t.title, t) end
            end
            last.callback()
            local opened = m.title == "Plex" and #m.item_table_stack == 1
            local q
            for _i, it in ipairs(m.item_table) do if tostring(it.text):match("128 kbps") then q = it end end
            if q then q.callback() end
            local in_place = m.title == "Plex" and #m.item_table_stack == 1 and m.item_table_stack[1] == root_before
                and q and tostring(m.item_table[1].text):match("kbps")
            local mark
            for _i, it in ipairs(m.item_table) do if tostring(it.text):match("128 kbps") then mark = it.mandatory end end
            m:onClose()
            check(opened and in_place and mark == "\u{2713}" and #m.item_table_stack == 0 and m.item_table.gz_catalog == "audiobooks"
                and m.item_table ~= root_before and m.item_table[#m.item_table].text == "Plex" and not ab._refresh_root,
                "the Plex card: its list; a change shows it again in place (1.28.0 left an empty list behind it); back: the page made again")
            m.onClose, px.bitrate = nil, saved_br
        end)()
        local Shop = require("gzreader_bookshop")
        Shop.audioLists(ab) -- (asks Plex)
        local sst = Shop.audioLists(ab)
        local rk = {}
        for _i, x in ipairs(sst.ab_recent or {}) do rk[#rk + 1] = x.id end
        check(sst.plex == "5" and table.concat(rk, ",") == "plex-206,plex-207" and sst.ab_continue[1] and sst.ab_continue[1].id == "plex-206",
            "Plex audiobooks: Recently added from Plex, Continue listening with what was listened to " .. table.concat(rk, ","))
        PA.openAll(ab, sec)
        local alltexts = {}
        for _i, it in ipairs(ab.menu.item_table) do alltexts[#alltexts + 1] = tostring(it.text) .. (it.mandatory and (" [" .. it.mandatory .. "]") or "") end
        local tx = table.concat(alltexts, " | ")
        check(tx:find("One File Book — Narr Author", 1, true) and tx:find("Two Part Book — Narr Author [on Kindle]", 1, true) and tx:find("Search audiobooks", 1, true),
            "Plex audiobooks: All audiobooks, the one downloaded marked " .. tx)
        local line
        for _i, it in ipairs(ab.menu.item_table) do if it.book and it.book.id == "plex-207" then line = it end end
        check(line and line.book.plex.key == "207" and line.cover_kind == "audiobook", "Plex audiobooks: a line carries its Plex album")
        ab:search("one", PA.scope(sec))
        local found = {}
        for _i, it in ipairs(ab.menu.item_table) do if it.book then found[#found + 1] = it.book.id end end
        check(table.concat(found, ",") == "plex-207", "Plex audiobooks: search keeps to the audiobook library " .. table.concat(found, ","))
        PA.openAuthors(ab, sec)
        local au = ab.menu.item_table
        local author
        for _i, it in ipairs(au) do if it.text == "Narr Author" then author = it end end
        if author then author.callback() end
        local nbooks = 0
        for _i, it in ipairs(ab.menu.item_table) do if it.book then nbooks = nbooks + 1 end end
        check(author and nbooks == 2, "Plex audiobooks: Authors, and an author's audiobooks")
        -- covers from Plex, never Grimmory
        local Covers = require("gzreader_covers")
        local cpath = Covers.path("plex-206", "audiobook")
        os.remove(cpath)
        Covers.plex_tried = {}
        local cgot
        Covers.fetch(plugin, { { id = "plex-206", kind = "audiobook" }, { id = "plex-207", kind = "audiobook" } }, function(got_n) cgot = got_n end)
        runLoop(function() return cgot ~= nil end, 10)
        check(cgot == 1 and require("libs/libkoreader-lfs").attributes(cpath, "mode") == "file" and Covers.state("plex-207", "audiobook") == "missing",
            "Plex audiobooks: covers from Plex (one with no picture there isn't asked of Grimmory)")
        ab.closed = true
        require("gzreader_touch").audio = saved_audio
        -- the outbox: which library (the sync page lists it)
        check(require("gzreader_usbsync").audiobookLibrary(plugin.store).key == "5"
            and require("gzreader_usbsync").audiobookLibrary({ plex = {} }) == nil, "outbox: the Plex audiobook library, for the sync page")
        ABk.delete(plugin, "plex-206")
        px.audiobook_section, plugin.save = saved_ab, saved_save
    end
    local artists, total = plex:list("1", "artists", 0)
    local albums = plex:list("1", "albums", 0)
    check(artists and total == 1 and artists[1].title == "The Tones" and albums and #albums == 3 and albums[1].artist == "The Tones", "Plex: artists and albums")
    local tracks = plex:children("201")
    check(tracks and #tracks == 2 and tracks[1].part.container == "mp3" and tracks[1].duration == 3000 and tracks[1].artist == "The Tones", "Plex: an album's tracks")
    local pls = plex:playlists()
    check(pls and pls[1].title == "Mix" and #plex:playlistItems("401", 0) == 2, "Plex: playlists")
    local res = plex:search("tone")
    check(res and #res.tracks == 4 and #res.artists == 1, "Plex: search")
    check(Plex.how(tracks[1]) == "file" and Plex.how(plex:children("202")[1]) == "m4a" and Plex.how(plex:children("203")[1]) == "transcode",
        "Plex: MP3 as it is, AAC converted on the Kindle, FLAC converted by the server")
    do -- "Make bigger MP3 and AAC smaller": tracks well above the quality made into MP3 at it
        local aac1 = plex:children("202")[1]
        check(tracks[1].part.bitrate == 320 and Plex.how(tracks[1], 192) == "transcode" and select(2, Plex.how(tracks[1], 192)) == "mp3"
            and Plex.how(tracks[2], 192) == "file" and Plex.how(aac1, 128) == "transcode" and Plex.how(aac1, 192) == "m4a"
            and Plex.how({ part = { container = "mp3" } }, 128) == "file",
            "Plex: bigger MP3/AAC converted when asked (320 kbps MP3 at 192, 160 kbps AAC at 128), not a VBR 200 kbps at 192, nor without a bitrate")
        local q0, q1 = Plex.quality({}), Plex.quality({ plex = { bitrate = 128, shrink = true } })
        check(q0.bitrate == 192 and q0.shrink == false and q1.bitrate == 128 and q1.shrink == true, "Plex: the quality settings, and their defaults")
        local Usb = require("gzreader_usbsync")
        local fakep = { store = {}, save = function() end }
        check(Usb.takeMusicQuality(fakep, { music_quality = { bitrate = 128, shrink = true } }) and fakep.store.plex.bitrate == 128
            and fakep.store.plex.shrink == true and not Usb.takeMusicQuality(fakep, { music_quality = { bitrate = 128, shrink = true } })
            and not Usb.takeMusicQuality(fakep, { music_quality = { bitrate = 999 } }) and fakep.store.plex.bitrate == 128
            and Usb.takeMusicQuality(fakep, { music_quality = { bitrate = 320, shrink = false } }) and fakep.store.plex.shrink == nil,
            "sync: the music quality chosen on the page kept in the Kindle's Plex settings (a bitrate it doesn't offer ignored)")
    end
    -- downloads
    Engine.root = PLUGIN
    local album = { kind = "album", key = "201", title = "MP3 Album", artist = "The Tones", thumb = "/t", tracks = tracks }
    local arrived = {}
    local done
    Music.download(plugin, album, { on_track = function(i) arrived[#arrived + 1] = i end, on_done = function(ok, err) done = { ok, err } end })
    runLoop(function() return done ~= nil end, 30)
    local c = Music.find(plugin, "album", "201")
    local mp3 = io.open(PLUGIN .. "/../../tools/gzreader/tests/media/tone.mp3", "rb"):read("*a")
    local got = c and io.open(c.dir .. "/" .. c.tracks[1].file, "rb")
    local gotdata = got and got:read("*a"); if got then got:close() end
    check(done and done[1] and c and c.have == 2 and table.concat(arrived, ",") == "1,2" and gotdata == mp3, "Music: an MP3 album downloaded, in order")
    local flac = { kind = "album", key = "203", title = "FLAC Album", tracks = plex:children("203") }
    done = nil
    Music.download(plugin, flac, { on_done = function(ok, err) done = { ok, err } end })
    runLoop(function() return done ~= nil end, 30)
    local fc = Music.find(plugin, "album", "203")
    local f3 = fc and io.open(fc.dir .. "/" .. (fc.tracks[1].file or "x"), "rb")
    local d3 = f3 and f3:read("*a"); if f3 then f3:close() end
    local b1, b2 = (d3 or ""):byte(1, 2)
    check(done and done[1] and fc.have == 1 and fc.tracks[1].file:match("%.mp3$") and b1 == 0xFF and bit.band(b2 or 0, 0xE0) == 0xE0 and #d3 > 8000,
        "Music: FLAC made into MP3 by the server (HLS segments joined, MPEG-TS unpacked) " .. tostring(done and done[2]))
    local aac = { kind = "album", key = "202", title = "AAC Album", tracks = plex:children("202") }
    done = nil
    Music.download(plugin, aac, { on_done = function(ok, err) done = { ok, err } end })
    runLoop(function() return done ~= nil end, 60)
    local ac = Music.find(plugin, "album", "202")
    check(done and done[1] and ac and ac.have == 1 and ac.tracks[1].chunks and #ac.tracks[1].chunks.starts > 0,
        "Music: AAC in M4A made into ADTS chunks on the Kindle " .. tostring(done and done[2]))
    local list = Music.downloaded(plugin)
    check(#list == 3, "Music: three albums downloaded")
    do -- progress, stopping, and what's left after
        local st = { dir = "x", total = 12, done = 2, failed = 0, current_frac = 0.5, title = "T" }
        check(Music.progressText(st) == "Downloading… track 3 of 12 · 20%", "Music: progress " .. Music.progressText(st))
        st.failed = 1
        check(Music.progressShort(st) == "track 4 of 12 · 29% · 1 failed", "Music: failed tracks counted " .. Music.progressShort(st))
        check(Music.resultText(st, "http_500"):match("^1 of 12 tracks of “T” couldn't be downloaded %(http_500%)%. The others are on the Kindle"),
            "Music: a failure says how many and that the rest stay")
        st.cancelled = true
        check(Music.resultText(st):match("^Download stopped: 2 of 12 tracks"), "Music: a stopped download says what's on the Kindle")
        -- a download stopped part-way: the first track stays, no half-written files
        local mp3b = { kind = "album", key = "201b", title = "Slow Album", tracks = tracks }
        os.execute("curl -s 'http://127.0.0.1:" .. PXP .. "/ctl/slow?s=3' >/dev/null")
        local arrived2, stopped = {}, nil
        local sst = Music.download(plugin, mp3b, { on_track = function(i) arrived2[#arrived2 + 1] = i end,
            on_done = function(ok, err, s2) stopped = { ok, err, s2 } end })
        local Tasks = require("gzreader_tasks")
        local listed
        for _i, t in ipairs(Tasks.list()) do if t.kind == "music" then listed = t end end
        check(listed and listed.title == "Slow Album" and listed.status:match("^track 1 of 2") and listed.stop, "Music: on the Downloads screen, stoppable")
        runLoop(function() return #arrived2 >= 1 end, 20)
        Music.stop(sst.dir)
        runLoop(function() return stopped ~= nil end, 20)
        os.execute("curl -s 'http://127.0.0.1:" .. PXP .. "/ctl/slow?s=0' >/dev/null")
        local sc = Music.find(plugin, "album", "201b")
        local parts = 0
        for name in lfs.dir(sc.dir) do if name:match("%.part$") then parts = parts + 1 end end
        check(stopped and stopped[1] == false and stopped[2] == "stopped" and stopped[3].cancelled and sc.have == 1 and parts == 0
            and Music.downloads[sc.dir] == nil, "Music: stopped part-way: the track that came stays, nothing half-written " .. tostring(sc and sc.have))
        local Tab = require("gzreader_musictab")
        local t2 = Tab.new(plugin)
        local labels = {}
        for _i, it in ipairs(t2:collectionItems(mp3b)) do labels[#labels + 1] = it.text end
        check(table.concat(labels, "|"):match("Download the 1 missing tracks"), "Music: then it offers the missing tracks " .. table.concat(labels, "|"))
        -- GZreader stopped mid-download: a track written but not noted is taken up again
        local saved = Music.load(c.dir)
        local missing = saved.tracks[2].file
        saved.tracks[2].file = nil
        Music.save(saved)
        local again = Music.find(plugin, "album", "201")
        check(again.have == 2 and again.tracks[2].file == missing, "Music: a track downloaded but not written down is taken up again")
        -- playing an album with tracks missing: on to the next one that's here
        local half = { dir = "/nonexistent", tracks = { { key = "a" }, { key = "b", chunks = {} }, { key = "c" } } }
        local pl = Music.Player:new(plugin, half, 1)
        local n1 = pl:nextReady()
        pl.at = 2
        local n2 = pl:nextReady()
        pl["repeat"] = "all"; pl.at = 3
        local n3 = pl:nextReady()
        check(n1 == 2 and n2 == nil and n3 == 2, "Music: a missing track: straight on to the next one on the Kindle (round, with repeat all)")
        -- a line showing the download keeps up
        local items = { { text = "x", gz_music_dl = "d" } }
        check(Tab.updateProgress(items, { dir = "d", total = 3, done = 1, failed = 0, current_frac = 0 }) and items[1].text:match("track 2 of 3"),
            "Music: the progress line updates")
        Music.delete(plugin, sc)
    end
    do -- Downloads → Music: a stand-in per album (the bookshelf's CD player)
        local MF = require("gzreader_musicfolder")
        local mdir = MF.entryDir(plugin)
        local saved_arch = package.loaded["ffi/archiver"]
        package.loaded["ffi/archiver"] = { Writer = { new = function()
            local w = {}
            function w:open(path) self.path = path; return true end
            function w:setZipCompression() return true end
            function w:addFileFromMemory() return true end
            function w:close() local f = io.open(self.path, "wb"); f:write("PK"); f:close() end
            return w
        end } }
        MF.sync(plugin)
        package.loaded["ffi/archiver"] = saved_arch
        local n = 0
        for name in lfs.dir(mdir) do if name:match("%.epub$") then n = n + 1 end end
        local stub = mdir .. "/AAC Album.epub"
        check(n == 3 and lfs.attributes(stub, "mode") == "file" and MF.folderForPath(plugin, stub) == "album-202",
            "Music: Downloads → Music holds a stand-in for each album (" .. n .. ")")
        local SV = require("gzreader_shelforder")
        local saved_home = G_reader_settings:readSetting("home_dir")
        G_reader_settings:saveSetting("home_dir", plugin:libraryDir())
        local items = { { text = "A book.epub", path = plugin:libraryDir() .. "/A book.epub", is_file = true },
            { text = "Music/", path = mdir }, { text = "Other/", path = plugin:libraryDir() .. "/Other" },
            { text = "Audiobooks/", path = plugin:libraryDir() .. "/Audiobooks" } }
        SV.specialsFirst(items)
        local cdf = io.open(PLUGIN .. "/icons/shelf/cdplayer.svg", "rb")
        local cd = cdf and cdf:read("*a") or ""
        if cdf then cdf:close() end
        local vw, vh = cd:match('viewBox="0 0 (%d+) (%d+)"')
        local ecy, ery = cd:match('<ellipse cx="85" cy="(%d+)" rx="74" ry="(%d+)" fill="url%(#edge%)"')
        check(tonumber(vw) and math.abs(tonumber(vw) / tonumber(vh) - SV.SPECIAL.Music.ratio) < 0.001
            and math.abs(SV.SPECIAL.Music.height - tonumber(vh) / 160) < 0.001
            and tonumber(ecy) and tonumber(ecy) + tonumber(ery) >= tonumber(vh) - 2,
            "the CD player lies on the shelf: the bottom of its edge is the bottom of the picture, its size as the picture's")
        check(items[1].text == "Audiobooks/" and items[2].text == "Music/" and items[3].text == "A book.epub",
            "Audiobooks and Music come first, whatever the sort")
        check(SV.SPECIAL.Audiobooks.height == 1 and SV.SPECIAL.Music.height < 0.85,
            "the walkman and the CD player drawn to one scale (the CD player lower)")
        do -- the walkman wears its headphones, as the CD player does
            local fh = io.open(PLUGIN .. "/icons/shelf/walkman.svg", "rb")
            local svg = fh and fh:read("*a") or ""
            if fh then fh:close() end
            local px, pw = svg:match('<rect x="(%d+)" y="66" width="(%d+)" height="92"')
            px, pw = tonumber(px) or 0, tonumber(pw) or 0
            local left, right = false, false
            for cx in svg:gmatch('<ellipse cx="(%d+)"[^>]*url%(#foam%)') do
                cx = tonumber(cx)
                if cx < px + 8 then left = true elseif cx > px + pw - 8 then right = true end
            end
            local band = svg:find("the headphones' band", 1, true)
            local player = svg:find("<!-- the player", 1, true)
            check(svg:match('viewBox="0 0 130 160"') and SV.SPECIAL.Audiobooks.ratio == 130 / 160
                and left and right and band and player and band < player,
                "the walkman's headphones sit on it: band behind, a pad on each side")
        end
        G_reader_settings:saveSetting("home_dir", saved_home)
    end
    -- the player
    local cmds = {}
    local saved_exec, saved_alive, saved_clock = Engine.exec, Engine.alive, Engine.clock
    Engine.exec = function(cmd) cmds[#cmds + 1] = cmd; return 0 end
    local now_t = 1000
    Engine.clock = function() return now_t end
    Engine.alive = function() return true end
    G_reader_settings:saveSetting("gzreader_audio_players", { mp3 = "mp3-mfw", aac = "aac-mfw" })
    local p = Music.play(plugin, c, 1, false)
    check(p and p.playing and cmds[#cmds]:find("01.mp3", 1, true) and cmds[#cmds]:find("mfw_mp3decoder", 1, true) and Music.nowText() == "Tone A — The Tones",
        "player: the first track through the MP3 player")
    p:step(1)
    check(p.at == 2 and cmds[#cmds]:find("02.mp3", 1, true), "player: next track")
    now_t = now_t + 10
    p:step(-1)
    check(p.at == 2, "player: previous after 3 s restarts the track")
    p:step(-1); p:step(-1)
    check(p.at == 1, "player: previous at the start goes back")
    p:setShuffle(true)
    check(p.order[p.at] == 1 and #p.order == 2, "player: shuffle keeps the track playing")
    p:setShuffle(false)
    p:jump(2)
    p:step(1)
    check(not p.playing and Music.current == nil, "player: the end of the album stops (repeat off)")
    p = Music.play(plugin, c, 2, false)
    p["repeat"] = "all"
    p:step(1)
    check(p.at == 1 and p.playing, "player: repeat all goes round")
    -- an audiobook or read aloud: music pauses
    Music.pauseAll()
    check(p.paused and not p.playing, "player: paused (sleep, read aloud, an audiobook)")
    p:resume()
    check(p.playing, "player: on again")
    local Folder = require("gzreader_abfolder")
    Folder.releaseAudio("a book opened")
    check(p.playing, "player: opening a book doesn't stop the music")
    Folder.releaseAudio("read aloud", true)
    check(p.paused and not p.playing, "player: read aloud pauses it")
    p:resume()
    -- a track still downloading: waits for it, then plays
    local waiting = { kind = "album", key = "w", title = "W", dir = c.dir, tracks = { { title = "Later", file = "nothere.mp3" } } }
    Music.downloads[c.dir] = { listeners = {} }
    local pw = Music.play(plugin, waiting, 1, false)
    Music.downloads[c.dir] = nil
    check(pw and pw.waiting, "player: waits for a track still downloading")
    pw:stop()
    -- …but not for one nothing is bringing: it says none are here, at once
    pw = Music.play(plugin, waiting, 1, false)
    check(not (pw and pw.waiting) and Music.current == nil, "player: no download, no track: stops at once")
    -- …and plays it when it comes (the download writes music.json, not the player's copy)
    local wdir = Music.dirFor(plugin, "album", "w2")
    os.execute("mkdir -p '" .. wdir .. "'")
    local w2 = { kind = "album", key = "w2", title = "W2", dir = wdir, tracks = { { key = "t1", title = "Later", base = "01" } } }
    Music.save(w2)
    Music.downloads[wdir] = { listeners = {} }
    pw = Music.play(plugin, Music.load(wdir), 1, false)
    local disk = Music.load(wdir)
    os.execute("cp '" .. PLUGIN .. "/../../tools/gzreader/tests/media/tone.mp3' '" .. wdir .. "/01.mp3'")
    disk.tracks[1].file = "01.mp3"
    Music.save(disk)
    Music.downloads[wdir] = { listeners = {} }
    pw:tick()
    Music.downloads[wdir] = nil
    check(pw.playing and not pw.waiting and cmds[#cmds]:find("w2/01.mp3", 1, true), "player: the track plays once it's downloaded")
    pw:stop()
    Music.delete(plugin, Music.load(wdir))
    Engine.exec, Engine.alive, Engine.clock = saved_exec, saved_alive, saved_clock
    -- the Music tab's menus
    local Tab = require("gzreader_musictab")
    local items = Tab.controlItems(plugin)
    check(items[1].text == "Shuffle all downloaded" and items[2].text == "Open the Music tab", "menus: Music without anything playing")
    Engine.exec = function() return 0 end
    Engine.alive = function() return true end
    Music.play(plugin, c, 1, false)
    items = Tab.controlItems(plugin)
    check(items[1].text == "Pause" and items[2].text == "Next track", "menus: Music while playing")
    local mi = Tab.menuItem(plugin)
    check(mi.text_func() == "Music: Tone A — The Tones", "Home / Reading menu: what's playing")
    local RM = require("gzreader_readmenu")
    local found = false
    for _i, it in ipairs(RM.items({ ui = { view = {}, document = { info = {} } } })) do
        if it.text_func and tostring(it.text_func()):match("^Music") then found = true end
    end
    check(found, "Reading menu: a Music line (Kindles with audio)")
    Music.current:stop()
    Engine.exec, Engine.alive = saved_exec, saved_alive
    Music.delete(plugin, Music.find(plugin, "album", "202"))
    check(Music.find(plugin, "album", "202") == nil and #Music.downloaded(plugin) == 2, "Music: a download deleted")
    check(lfs.attributes(require("gzreader_musicfolder").entryDir(plugin) .. "/AAC Album.epub", "mode") == nil,
        "and its stand-in in Downloads → Music is gone")
    -- Settings → Connections → Plex (Music)
    local function texts(list)
        local out = {}
        for _i, it in ipairs(list) do out[#out + 1] = it.text or (it.text_func and it.text_func()) or "" end
        return table.concat(out, " | ")
    end
    local si = Tab.settingsItems(plugin)
    local st = texts(si)
    check(st:match("^Signed in as will | Plex server: Home Server | Music library: the server's first | Audiobooks: from Grimmory | Quality when converting: 192 kbps | Make bigger MP3 and AAC smaller | Downloaded music: 2 %(%d+ MB%) | Sign out of Plex"),
        "Settings → Connections → Plex: account, server, music library, quality, downloads, sign out: " .. st)
    local q = si[5].sub_item_table_func()
    q[3].callback()
    check(plugin.store.plex.bitrate == 320 and q[3].checked_func() and not q[2].checked_func() and texts(si):match("320 kbps"),
        "Settings → Plex: the conversion quality")
    plugin.store.plex.bitrate = nil
    local servers = si[2].sub_item_table_func()
    check(#servers == 2 and servers[1].text == "Home Server" and servers[1].checked_func() and not servers[2].checked_func(), "Settings → Plex: the account's servers, this one ticked")
    local saved_plex = plugin.store.plex
    plugin.store.plex = { client_id = saved_plex.client_id }
    st = texts(Tab.settingsItems(plugin))
    check(st:match("^Plex: sign in with a code") and st:match("QR code") and st:match("Navbar → Tabs"), "Settings → Plex, signed out: the ways to sign in")
    plugin.store.plex = saved_plex
    -- no token in an address (the mock refuses those) or the log
    local pp = io.popen("curl -s http://127.0.0.1:" .. PXP .. "/ctl/log"); local lg = json.decode(pp:read("*a")); pp:close()
    local in_url = false
    for _i, e in ipairs(lg) do if tostring(e[2]):lower():find("token", 1, true) then in_url = true end end
    check(not in_url, "Plex: the token only ever in a header")
    os.execute("kill $(cat " .. WORK .. "/plex.pid) 2>/dev/null")
end)()

print("Music's CD player: the headphones' band reaches both pads");
(function()
    local fh = io.open(PLUGIN .. "/icons/shelf/cd_player.svg", "rb")
    local svg = fh and fh:read("*a") or ""
    if fh then fh:close() end
    local x1, y1, r, x2, y2 = svg:match('<path d="M([%d.]+) ([%d.]+) A([%d.]+) [%d.]+ 0 0 1 ([%d.]+) ([%d.]+)" fill="none" stroke="#2a2a2a"')
    x1, y1, r, x2, y2 = tonumber(x1), tonumber(y1), tonumber(r), tonumber(x2), tonumber(y2)
    local pads = {}
    for cx, cy, pr in svg:gmatch('<circle cx="([%d.]+)" cy="([%d.]+)" r="([%d.]+)" fill="url%(#foam%)"') do
        pads[#pads + 1] = { x = tonumber(cx), y = tonumber(cy), r = tonumber(pr) }
    end
    local sliders = {}
    for sx, sy, sw, sh, a, ax, ay in svg:gmatch('<rect x="([%d.]+)" y="([%d.]+)" width="([%d.]+)" height="([%d.]+)" rx="2" fill="#2a2a2a" transform="rotate%((%-?[%d.]+) ([%d.]+) ([%d.]+)%)"/>') do
        sliders[#sliders + 1] = { x = tonumber(ax), y = tonumber(ay), len = tonumber(sh), a = math.rad(tonumber(a)) }
    end
    local function inside(px, py, pad) return math.sqrt((px - pad.x) ^ 2 + (py - pad.y) ^ 2) < pad.r end
    check(x2 and #pads == 2 and #sliders == 2, "the band, two pads and two sliders found in cd_player.svg")
    if x2 and #pads == 2 and #sliders == 2 then
        -- the band's circle (the arc's centre on the side the sweep goes round)
        local mx, my, dx, dy = (x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1
        local chord = math.sqrt(dx * dx + dy * dy)
        local hh = math.sqrt(math.max(0, r * r - (chord / 2) ^ 2))
        local cx, cy = mx - hh * dy / chord, my + hh * dx / chord
        local right = pads[1].x > pads[2].x and pads[1] or pads[2]
        check(inside(x2, y2, right), "the band runs into the right pad (it stopped short of it: a gap under the slider)")
        for i, slider in ipairs(sliders) do
            -- a slider's long side, turned by its rotation: both ends, one on the band, one in a pad
            local ux, uy = -math.sin(slider.a), math.cos(slider.a)
            local ends = { { slider.x - ux * slider.len / 2, slider.y - uy * slider.len / 2 }, { slider.x + ux * slider.len / 2, slider.y + uy * slider.len / 2 } }
            local on_band = math.abs(math.sqrt((slider.x - cx) ^ 2 + (slider.y - cy) ^ 2) - r) < 4
            local in_pad = inside(ends[1][1], ends[1][2], pads[1]) or inside(ends[1][1], ends[1][2], pads[2])
                or inside(ends[2][1], ends[2][2], pads[1]) or inside(ends[2][1], ends[2][2], pads[2])
            check(on_band and in_pad, "slider " .. i .. " sits on the band and reaches its pad")
        end
    end
end)()

print("Wi-Fi turned on by GZreader: no scan messages (touch Kindles)")
;(function()
    local Net = require("gzreader_net")
    local NM = require("ui/network/manager")
    local saved = { NM.enableWifi, NM.turnOnWifiAndWaitForConnection, NM.reconnectOrShowNetworkMenu, NM.isWifiOn, NM.isConnected,
        Net.connected, Net.enabled, Net.keptOff }
    local shown = {}
    local orig_show = UI.show
    local UIM = require("ui/uimanager")
    local real_show = UIM.show
    UIM.show = function(um, w, ...) shown[#shown + 1] = w and w.text or "?"; return real_show and real_show(um, w, ...) end
    NM.reconnectOrShowNetworkMenu = function(self, cb, interactive)
        UIM:show({ text = "Scanning for networks…" })
        UIM:show({ text = "Connecting to network Home…", timeout = 3 })
        if cb then cb() end
        return true
    end
    NM.enableWifi = function(self, cb, interactive) return self:reconnectOrShowNetworkMenu(cb, interactive) end
    NM.turnOnWifiAndWaitForConnection = function(self, cb)
        UIM:show({ text = "Connecting to Wi-Fi…" })
        return self:reconnectOrShowNetworkMenu(cb)
    end
    NM.isWifiOn = function() return false end
    Net.connected = function() return false end
    Net.enabled = function() return true end
    Net.keptOff = function() return false end
    Net.connecting = nil
    local ran = 0
    Net.run(function() ran = ran + 1 end, { quiet = true, reason = "test" })
    check(ran == 1 and #shown == 0, "a background sync turns Wi-Fi on without a message (" .. table.concat(shown, ", ") .. ")")
    Net.connecting = nil
    Net.run(function() ran = ran + 1 end, { reason = "browsing" })
    check(ran == 2 and #shown == 1 and shown[1] == "Connecting to Wi-Fi…", "something you asked for: only \"Connecting to Wi-Fi…\", as on the Kindle 3 (" .. table.concat(shown, ", ") .. ")")
    -- connected, but no route out yet (a Paperwhite, the first moment): wait for one
    local saved_route = Net.routeReady
    local calls = 0
    Net.routeReady = function() calls = calls + 1; return calls > 2 end
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end
    Net.connecting = nil
    Net.run(function() ran = ran + 1 end, { quiet = true, reason = "test" })
    local before = ran
    for _round = 1, 5 do
        local due = {}
        for f in pairs(UI.scheduled) do due[#due + 1] = f end
        for _i, f in ipairs(due) do
            local t = UI.scheduled[f]
            UI.scheduled[f] = nil
            if type(t) ~= "number" or t < 60 then f() end -- (not the 90 s give-up)
        end
    end
    check(before == 2 and ran == 3 and calls == 3, string.format(
        "after connecting, the work waits for a route out (then runs once): %d %d %d", before, ran, calls))
    Net.routeReady = saved_route
    shown = {}
    NM:reconnectOrShowNetworkMenu(nil, true)
    check(#shown == 2, "the Wi-Fi menu (you): its messages as usual")
    UIM.show = real_show
    NM.enableWifi, NM.turnOnWifiAndWaitForConnection, NM.reconnectOrShowNetworkMenu, NM.isWifiOn, NM.isConnected,
        Net.connected, Net.enabled, Net.keptOff = unpack(saved, 1, 8)
    Net.connecting = nil
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end
    local _unused = orig_show
end)()

print("Downloads tab: its name in the title bar, like the other tabs")
;(function()
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    package.loaded["common/gz_tab_title"] = nil
    local T = require("common/gz_tab_title")
    local home = "/mnt/us/documents/GZreader"
    check(T.downloads(home, home, nil, false) == "Downloads", "the home folder (the Downloads tab): \"Downloads\"")
    check(T.downloads(home, home, { books_label = "" }, false) == "Downloads", "an empty navbar label: still \"Downloads\"")
    check(T.downloads(home, home, { books_label = "My books" }, false) == "My books", "the navbar's own label for the tab wins")
    check(T.downloads(home, home, nil, false, function(s) return "[" .. s .. "]" end) == "[Downloads]", "translated")
    check(T.downloads(home .. "/Series", home, nil, false) == nil, "a folder inside it: ZenOS's folder name stays")
    check(T.downloads(home, home, nil, true) == nil, "a series group open: ZenOS's own title stays")
    check(T.downloads("/mnt/us/documents", home, nil, false) == nil, "another folder (Folder tab, archive): nothing added")
    check(T.downloads(nil, home, nil, false) == nil and T.downloads(home, nil, nil, false) == nil,
        "no path (collections) or no home folder: nothing added")
    local sbf = io.open(PLUGIN .. "/../zenos.koplugin/modules/filebrowser/patches/status_bar.lua")
    local src = sbf and sbf:read("*a") or ""
    if sbf then sbf:close() end
    check(src:find('require("common/gz_tab_title").downloads(', 1, true) ~= nil,
        "ZenOS's status row asks it when nothing else names the view")
    package.path = saved_path
end)()

print("Menus drawn as ZenOS rows: an icon, short labels, an arrow")
;(function()
    local Rows = require("gzreader_rows")
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    local saved_map = package.loaded["common/inline_icon_map"]
    package.loaded["common/inline_icon_map"] = nil
    local okm, map = pcall(require, "common/inline_icon_map")
    local rows = Rows.mark({
        { text = "Action", gz_icon = "download", callback = function() end },
        { text = "Info", select_enabled = false },
        { text = "Switch", checked_func = function() return true end, callback = function() end },
        { text = "Pick", gz_pick = true, gz_icon = "name:usb" },
        { text = "Picked", gz_pick = true, dim = true, gz_icon = "/x/music.svg" },
        { text = "Bold", bold = true, gz_no_arrow = true, callback = function() end },
    })
    package.path = saved_path
    package.loaded["common/inline_icon_map"] = saved_map
    check(Rows.isRows(rows) and rows[1]._zen_settings_row and rows[2]._zen_settings_row and rows[6]._zen_settings_row,
        "every row marked as ZenOS's Settings row, the list too")
    check(rows[1]._zen_has_submenu and rows[1]._zen_caret_icon == "chevron.right" and not rows[2]._zen_has_submenu
        and not rows[3]._zen_has_submenu and rows[4]._zen_has_submenu and not rows[5]._zen_has_submenu and not rows[6]._zen_has_submenu,
        "an arrow on rows that do something; none on a line of text, a switch, a greyed-out choice or when asked")
    check(okm and rows[1].icon_glyph == map.download and rows[4].icon_name == "usb" and rows[5].icon_file == "/x/music.svg",
        "icons: ZenOS's glyphs, its icons by name, a file")
    check(rows[6]._zen_primary_bold, "bold stays bold")
    check(not Rows.isRows({ { text = "a book" } }), "other lists aren't touched")
    -- the long explanations behind About, shown when it's tapped
    local saved_info = package.loaded["ui/widget/infomessage"]
    local UIM = require("ui/uimanager")
    local real_show, shown = UIM.show, {}
    package.loaded["ui/widget/infomessage"] = { new = function(_s, o) return o end }
    UIM.show = function(_um, w) shown[#shown + 1] = w and w.text end
    local about = Rows.mark({ Rows.about("About it", "The whole story.") })[1]
    about.callback()
    check(shown[1] == "The whole story." and about._zen_has_submenu and about.icon_glyph ~= false, "About: the explanation in a message")
    -- the menus: short labels (they were cut off at the screen's edge), every row a ZenOS row
    local Net = require("gzreader_net")
    local was_usb = Net.usb
    local function short(list, name)
        local long = {}
        for _i, it in ipairs(list) do
            local t = it.text or ""
            if #t > 30 or not it._zen_settings_row then long[#long + 1] = t end
        end
        check(Rows.isRows(list) and #list > 1 and #long == 0, name .. ": short labels, ZenOS rows " .. table.concat(long, " | "))
    end
    for _i, usb in ipairs({ false, true }) do
        Net.usb = usb
        local how = usb and " (no Wi-Fi)" or ""
        short(require("gzreader_calendar").connectItems(plugin), "Calendar's connect list" .. how)
        short(require("gzreader_notes").connectItems(plugin), "Notes' connect list" .. how)
    end
    Net.usb = was_usb
    local cal = require("gzreader_calendar").connectItems(plugin)
    shown = {}
    cal[#cal].callback()
    check(cal[1].text == "Add with QR code" and tostring(shown[1]):match("Proton") and tostring(shown[1]):match("app password"),
        "Calendar: About calendar links says what was cut off before")
    local Tab = require("gzreader_musictab")
    short(Tab.signInItems(plugin), "Plex's sign-in")
    local Touch = require("gzreader_touch")
    local was_audio = Touch.audio
    Touch.audio = function() return false end
    local tab = Tab.new(plugin)
    local mute = tab:rootItems()
    Touch.audio = was_audio
    check(#mute == 1 and mute[1].text == "No speaker on this Kindle" and mute[1].gz_about:match("headphone jack"),
        "Music on a Kindle without a speaker: a short line, the reason behind it")
    UIM.show = real_show
    package.loaded["ui/widget/infomessage"] = saved_info
    -- Downloads: the title, where it's at on the right, an icon for what's happening
    local Tasks = require("gzreader_tasks")
    local dl = { Tasks.line({ kind = "book", title = "Diper Överlöde", done = 30 * 1048576, total = 77 * 1048576 }) }
    local wq = { Tasks.line({ kind = "queued", title = "Hot Mess" }) }
    local mu = { Tasks.line({ kind = "music", title = "Album", status = "track 3 of 12 · 41%" }) }
    check(dl[1] == "Diper Överlöde" and dl[2] == "38% of 77.0 MB" and dl[3] == "download" and wq[1] == "Hot Mess" and wq[2] == "waiting"
        and wq[3] == "tbr" and mu[2] == "track 3 of 12 · 41%" and mu[3] == Rows.FILE.music,
        "Downloads: the title alone, a short status, an icon (" .. tostring(dl[2]) .. ")")
    -- ZenOS's row height for the lists made so, the Menu's own for others
    local saved_ii = package.loaded["common/ui/icon_menu_item"]
    package.loaded["common/ui/icon_menu_item"] = { getSettingsRowHeight = function() return 69 end, getSettingsFontSize = function() return 22 end }
    local m = { page = 1, item_table = rows, updated = 0 }
    function m._recalculateDimen(self) self.perpage, self.font_size, self.available_height, self.item_dimen = 14, 19, 700, { h = 50 } end
    function m.getPageNumber(self, count) return math.max(1, math.ceil(count / self.perpage)) end
    function m.updateItems(self) self.updated = self.updated + 1; self:_recalculateDimen() end
    Rows.apply(m)
    check(m.updated == 1 and m.perpage == 10 and m.item_dimen.h == 69 and m.font_size == 22 and m.page_num == 1,
        "a Menu with such a list: ZenOS's row height and font, as many rows as fit")
    m.item_table = { { text = "a book" } }
    m:_recalculateDimen()
    check(m.perpage == 14 and m.item_dimen.h == 50, "…and its other lists keep the Menu's own")
    Rows.apply(m)
    check(m.updated == 1, "applied once")
    package.loaded["common/ui/icon_menu_item"] = saved_ii
    -- the lists use it
    for _i, mod in ipairs({ "gzreader_calendar", "gzreader_notes", "gzreader_musictab", "gzreader_tasks", "gzreader_usbsync",
            "gzreader_copy", "gzreader_panel", "gzreader_shelves", "gzreader_browser" }) do
        local fh = io.open(PLUGIN .. "/" .. mod .. ".lua")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        check(src:find('require("gzreader_rows")', 1, true) and src:find("apply(", 1, true), mod .. ": its menu drawn with ZenOS rows")
    end
end)()

print("The reader's top status bar stays drawn under KOReader's layout menu")
;(function()
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    package.loaded["common/gz_header_overlay"] = nil
    local O = require("common/gz_header_overlay")
    local dialog, a_window = { name = "ConfigDialog" }, { name = "a window" }
    local view = { ui = { config = { config_dialog = dialog } } }
    check(O.leavesHeader(view, dialog) == true, "the book's open layout menu leaves the bar in view")
    check(O.leavesHeader(view, a_window) == false, "another window over the book: the bar isn't drawn (as before)")
    local closed = { ui = { config = {} } }
    check(O.leavesHeader(closed, dialog) == false, "a layout menu that was closed doesn't count")
    check(O.leavesHeader({ ui = {} }, dialog) == false and O.leavesHeader(nil, dialog) == false
        and O.leavesHeader(view, nil) == false, "no reader config, no view or no window: false")
    local tf = io.open(PLUGIN .. "/../zenos.koplugin/modules/reader/patches/reader_top_status_bar.lua")
    local src = tf and tf:read("*a") or ""
    if tf then tf:close() end
    local fn = src:match("local function is_view_active_top%(view%)(.-)\n    end\n") or ""
    check(fn:find('require("common/gz_header_overlay").leavesHeader(view, top_widget)', 1, true) ~= nil,
        "ZenOS's top bar asks it when the book isn't the topmost window")
    package.path = saved_path
end)()

print("Kindle Wi-Fi networks (ZenOS's switcher): KOReader's lipc library")
;(function()
    local zen = PLUGIN .. "/../zenos.koplugin/?.lua"
    local saved_path = package.path
    package.path = zen .. ";" .. package.path
    local calls = {}
    local handle = {}
    function handle:set_string_property(svc, prop, val) calls[#calls + 1] = svc .. " " .. prop .. " " .. tostring(val) end
    function handle:set_int_property(svc, prop, val) calls[#calls + 1] = svc .. " " .. prop .. " " .. tostring(val) end
    function handle:get_string_property() return "idle" end
    function handle:new_hasharray()
        local ha = {}
        for _i, m in ipairs({ "add_hash", "put_string", "put_int", "destroy" }) do ha[m] = function() end end
        return ha
    end
    function handle:access_hash_property(_svc, prop)
        local rows = prop == "profileData" and { { essid = "Home", netid = 3 } }
            or prop == "scanList" and { { essid = "Home", signal = 4, signal_max = 5, key_mgmt = "WPA-PSK", known = "yes", netid = 3 },
                { essid = "Cafe", signal = 2, signal_max = 5, key_mgmt = "WPA-PSK", known = "no" } } or {}
        return { to_table = function() return rows end, destroy = function() end }
    end
    function handle:close() end
    package.loaded["liblipclua"] = nil
    package.preload["liblipclua"] = function() error("module 'liblipclua' not found") end
    package.loaded["libopenlipclua"] = { open_no_name = function() return handle end }
    local NM = { getCurrentNetwork = function() return nil end, turnOffWifi = function() end }
    package.loaded["modules/menu/network_adapters/kindle"] = nil
    local ok, Adapter = pcall(require, "modules/menu/network_adapters/kindle")
    check(ok, "the Kindle adapter loads " .. tostring(not ok and Adapter or ""))
    if ok then
        local a = Adapter.new(NM)
        local list = a.getNetworkList()
        local home, cafe
        for _i, n in ipairs(list or {}) do if n.ssid == "Home" then home = n elseif n.ssid == "Cafe" then cafe = n end end
        check(home and home.saved and cafe and not cafe.saved, "networks the Kindle knows are marked saved (no password asked)")
        local connected = a.connect({ ssid = "Home" })
        check(connected and calls[#calls] == "com.lab126.cmd ensureConnection wifi:Home",
            "connecting without liblipclua: libopenlipclua, as KOReader's own menu does (" .. tostring(calls[#calls]) .. ")")
        local done
        a.scan(function(scanned) done = scanned end)
        check(calls[#calls] == "com.lab126.wifid scan " and done ~= false, "a scan starts (no \"timed out\" at once)")
        a.close()
    end
    package.preload["liblipclua"] = nil
    package.loaded["libopenlipclua"] = nil
    package.loaded["modules/menu/network_adapters/kindle"] = nil
    package.path = saved_path
end)()

print("Home's status bar with no book to show (as on the other tabs)")
;(function()
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    package.loaded["common/gz_home_status"] = nil
    local S = require("common/gz_home_status")
    local rows = { { id = "datetime" }, { id = "featured" }, { id = "strip" } }
    local function preset(home_bar, book_bar)
        return { show_status_bar = home_bar, modules = { featured = { show_status_bar = book_bar } } }
    end
    local asked = 0
    local function book(yes) return function() asked = asked + 1; return yes end end
    -- the presets: Home's bar off, the book widget carries it
    check(S.wanted(preset(false, true), rows, book(true)) == false,
        "a book on Home: the status bar stays inside the book widget")
    check(S.wanted(preset(false, true), rows, book(false)) == true,
        "no recently read book: Home shows the status bar across the top")
    check(S.wanted(preset(false, true), { { id = "strip" } }, book(true)) == true,
        "the book widget off: Home shows the status bar across the top")
    asked = 0
    check(S.wanted(preset(true, false), rows, book(false)) == true and S.wanted(preset(nil, false), rows, book(false)) == true
        and asked == 0, "Home's own status bar on: shown, no book looked up")
    check(S.wanted(preset(false, false), rows, book(false)) == false and asked == 0,
        "the status bar turned off on Home (not in the book widget): stays off")
    check(S.wanted(preset(false, true), rows, function() error("boom") end) == false
        and S.wanted(preset(false, true), rows, nil) == false,
        "can't tell whether there's a book: as before (the book widget's bar)")
    -- Home uses it: built with it, rebuilt when it changes, no second bar
    local src = io.open(PLUGIN .. "/../zenos.koplugin/modules/filebrowser/patches/home_page.lua", "rb")
    local text = src and src:read("*a") or ""
    if src then src:close() end
    local _n, uses = text:gsub("home_status_bar_wanted%(dcfg, rows, data_provider%)", "")
    check(text:find("local show_status_bar = home_status_bar_wanted(dcfg, rows, data_provider)", 1, true)
        and text:find("show_status_bar = menu._zen_home_status_bar_wanted(dcfg)", 1, true)
        and text:find('return false, "status_bar_changed"', 1, true) and uses == 4
        and text:find("buildStatusRow = menu._zen_home_show_status_bar == false", 1, true),
        "Home: built with it, built again when a book appears or goes, no second bar in the book widget")
    package.loaded["common/gz_home_status"] = nil
    package.path = saved_path
end)()

print("Audiobook player: go to a time, skips gathered, the cassette")
;(function()
    local AB = require("gzreader_audiobook")
    local H = 3600000
    check(AB.parseTime("1:23:45") == (3600 + 23 * 60 + 45) * 1000 and AB.parseTime("23:45") == (23 * 60 + 45) * 1000
        and AB.parseTime(" 50% ", 10 * H) == 5 * H and AB.parseTime("abc") == nil
        and AB.parseTime("12%") == nil, "go to: 1:23:45, 23:45, a percentage of the book")
    check(AB.parseTime("5000") == 50 * 60000 and AB.parseTime("13000") == (3600 + 30 * 60) * 1000
        and AB.parseTime("12345") == (3600 + 23 * 60 + 45) * 1000 and AB.parseTime("45") == 45000
        and AB.parseTime("130") == 90000 and AB.parseTime("1.5") == nil,
        "go to: digits without colons read like a clock (5000 is 50:00, 13000 is 1:30:00)")
    check(AB.runtime(10 * H + 28 * 60000) == "10 h 28 min" and AB.runtime(25 * 60000) == "25 min", "the cassette's running time")
    -- three presses of 30 s on: the player started once, 90 s on
    local seeks = {}
    local fake = { player = { globalPos = function() return 60000 end, seekTo = function(_p, g) seeks[#seeks + 1] = g end },
        build = function() end, refresh = function() end }
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end
    for _i = 1, 3 do AB.Screen.queueSkip(fake, AB.SKIP_MS) end
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil; f() end
    check(#seeks == 1 and seeks[1] == 60000 + 3 * AB.SKIP_MS, "skips pressed close together: the player is started once, where they end")
    local Deck = require("gzreader_deck")
    check(Deck.Cassette and Deck.Cassette.RATIO == 0.63, "the player shows the audiobook as a cassette (100 × 63)")
    -- Music's CD player: the disc fills the lid's window, the cover nearly all of the disc
    local D = Deck.CD.DISC
    local svgf = io.open(debug.getinfo(Deck.CD.paintTo, "S").source:sub(2):gsub("gzreader_deck%.lua$", "icons/shelf/cd_player.svg"), "rb")
    local svg = svgf and svgf:read("*a") or ""
    if svgf then svgf:close() end
    local win = tonumber(svg:match('<circle cx="180" cy="126" r="(%d+)" fill="#2a2a2a"/>'))
    local deck_src = io.open(debug.getinfo(Deck.CD.paintTo, "S").source:sub(2), "rb")
    local dsrc = deck_src and deck_src:read("*a") or ""
    if deck_src then deck_src:close() end
    check(win and D.disc == win and D.label >= D.disc - 4 and D.hub < D.label / 4 and D.spindle < D.hole and D.hole < D.hub
        and dsrc:find("fit(st.cover_bb, 2 * rl, 2 * rl, true)", 1, true),
        "the CD player: the album's cover fills the disc, the disc fills the lid's window (it was a small label in the middle)")
    -- the chunk feeder ends with the player
    local Engine = require("gzreader_audioengine")
    local cmd = Engine.command({ pipe = "fakesink" }, { kind = "chunks", dir = "/x", starts = { 0, 15000 }, offset_ms = 0 })
    check(cmd:find("|| break", 1, true), "the chunks' feeder stops when the player does (it went on through every chunk)")
end)()

print("Audiobook player: the 5-way goes from key to key (Kindle 3)")
;(function()
    local S = require("gzreader_audiobook").Screen
    local function m(f, ...) for _i, d in ipairs({ ... }) do f = S.move(f, d) end return f[1] .. "," .. f[2] end
    check(m({ 1, 3 }, "Right", "Right", "Right") == "1,5" and m({ 1, 3 }, "Left", "Left", "Left") == "1,1",
        "along a row, stopping at its ends")
    check(m({ 1, 3 }, "Down") == "2,3" and m({ 1, 5 }, "Down") == "2,4" and m({ 1, 1 }, "Down") == "2,1" and m({ 2, 3 }, "Down") == "3,2"
        and m({ 3, 1 }, "Up") == "2,2" and m({ 1, 3 }, "Up") == "1,3" and m({ 3, 2 }, "Down") == "3,2",
        "up and down keep to the same part of the screen (play → Stop → volume +)")
end)()

print("Kindles without REAGL: flash when the screen changes")
;(function()
    local Eink = require("gzreader_eink")
    local W, H = 600, 800
    local function m(mode, region, pending) return (Eink.promote(mode, region, W, H, pending)) end
    check(m("ui", nil) == "full" and m("ui", { w = 600, h = 800 }) == "flashui" and m("partial", { w = 600, h = 600 }) == "flashui",
        "most of the screen changing (a tab, a menu, a list's page) flashes")
    check(m("ui", { w = 584, h = 354 }) == "ui" and m("ui", { w = 36, h = 25 }) == "ui", "small changes (the focus, the clock) don't")
    check(m("partial", nil) == "partial" and m("partial", nil, true) == "full", "a page turn is left to the page rate, unless a book or full-screen menu just opened or closed")
    check(m("fast", nil) == "fast" and m("full", nil) == "full" and m("a2", { w = 600, h = 800 }) == "a2", "other modes as asked")
    check(Eink.promote("ui", nil, W, H, false, true) == "ui" and Eink.promote("ui", { w = 600, h = 800 }, W, H, false, true) == "ui",
        "the 5-way's arrows (along the tab bar, around the quick panel) don't flash, however much they redraw")
    check(Eink.promote("ui", nil, W, H, true, true) == "full", "unless a full-screen window just opened or closed")
    check(Eink.promote("ui", nil, W, H, false, false, true) == "ui" and Eink.promote("ui", { w = 600, h = 800 }, W, H, false, false, true) == "ui"
        and Eink.promote("ui", nil, W, H, true, false, true) == "full",
        "nothing you did (no key or tap for a while: a download done, covers arriving): no flash, unless a window opened or closed")
    check(require("gzreader_tasks").REFRESH == 3, "the download status in the status bar: updated every 3 s")
    local player = { covers_fullscreen = true, gz_player = true }
    local chapters = { covers_fullscreen = true }
    local stack = { { widget = { name = "home" } }, { widget = player } }
    check(Eink.inPlayer(stack) and not Eink.inPlayer({ { widget = { name = "home" } } }), "a player is open: one marked gz_player is on the stack")
    check(Eink.flashesFor(player, stack) and not Eink.flashesFor(chapters, stack) and Eink.flashesFor(chapters, { { widget = {} } }),
        "inside a player only its own opening and closing flash (not its chapter list)")
    -- (the widgets are stand-ins here: the editor's class is read from its file)
    local src = io.open(debug.getinfo(Eink.promote, "S").source:sub(2):gsub("gzreader_eink%.lua$", "gzreader_noteeditor.lua"), "rb")
    local text = src and src:read("*a") or ""
    if src then src:close() end
    local ed = { covers_fullscreen = true, gz_no_flash = true }
    local estack = { { widget = { name = "home" } }, { widget = ed } }
    check(text:match("local Editor = InputContainer:extend{ covers_fullscreen = true,%s*gz_no_flash = true }")
        and Eink.inPlayer(estack) and Eink.flashesFor(ed, { { widget = {} } }) and not Eink.flashesFor({ covers_fullscreen = true }, estack),
        "the note editor: typing doesn't flash the screen at every key (only its opening and closing do)")
end)()

print("Quick panel's light: the swipe that opens it doesn't move the light")
;(function()
    local Panel = require("gzreader_panel")
    local PW = Panel._Widget
    -- (the panel's sizes go through the screen it was loaded with: 1:1 here)
    local Screen = require("device").screen
    local was_scale = rawget(Screen, "scaleBySize")
    Screen.scaleBySize = function(_s, px) return px end
    local set = {}
    local w = setmetatable({ light_y = 40, w = 600 }, { __index = PW })
    w.lightInfo = function() return nil, 0, 24, 12 end
    w.setLight = function(_self, v) set[#set + 1] = v end
    local on_strip = 40 + 20
    local function at(x, y) return { pos = { x = x, y = y } } end
    -- the swipe down that opened the panel goes on over the slider, then lets go
    w:onPanLight(nil, at(100, on_strip))
    w:onPanLight(nil, at(400, on_strip))
    w:onPanReleaseLight(nil, at(400, on_strip + 4))
    w:onSwipeLight(nil, { pos = at(100, on_strip).pos, direction = "east", distance = 300 })
    check(#set == 0, "the rest of the opening swipe (pans, release, swipe) leaves the light alone")
    -- a finger put down below the slider (on the tiles) and dragged up over it
    check(w:onTouchPanel(nil, at(300, 300)) == false, "a touch isn't taken from the tiles")
    w:onPanLight(nil, at(400, on_strip))
    w:onPanReleaseLight(nil, at(400, on_strip))
    check(#set == 0, "a drag that started on the tiles doesn't move the light")
    -- a finger put down on the slider and dragged
    w:onTouchPanel(nil, at(200, on_strip))
    w:onPanLight(nil, at(300, on_strip))
    w:onPanReleaseLight(nil, at(350, on_strip))
    check(#set == 2, "a drag on the slider moves the light (" .. #set .. ")")
    -- then the next gesture needs its own touch
    w:onPanLight(nil, at(100, on_strip))
    check(#set == 2, "…and only until that finger lets go")
    w:onTouchPanel(nil, at(200, on_strip))
    w:onSwipeLight(nil, { pos = at(200, on_strip).pos, direction = "east", distance = 100 })
    check(#set == 3, "a quick swipe on the slider moves the light")
    w:onSwipeLight(nil, { pos = at(200, on_strip).pos, direction = "east", distance = 100 })
    check(#set == 3, "…once")
    local pf = io.open(debug.getinfo(PW.onTouchPanel, "S").source:sub(2), "rb")
    local src = pf and pf:read("*a") or ""
    if pf then pf:close() end
    check(src:match('TouchPanel = { GestureRange:new{ ges = "touch", range = whole } }'),
        "the panel listens for a finger put down (KOReader's touch gesture)")
    Screen.scaleBySize = was_scale
end)()

print("The first tour on a touch Kindle: GZreader's quick panel")
;(function()
    local Tour = require("gzreader_tour")
    local UIManager = require("ui/uimanager")
    local Device = require("device")
    local was_screen = Device.screen
    Device.screen = { getWidth = function() return 600 end, getHeight = function() return 800 end }
    -- a stand-in panel: 10 Controls tiles (Settings the 8th), 6 Home tiles
    local function tile(label) return { label = label, w = 100, h = 100 } end
    local placed, controls = {}, {}
    for i = 1, 10 do
        controls[i] = {}
        placed[i] = { tile = tile(i == 8 and "Settings" or ("c" .. i)), x = 16 + ((i - 1) % 5) * 110, y = 70 + math.floor((i - 1) / 5) * 110 }
    end
    for i = 1, 6 do
        placed[10 + i] = { tile = tile("h" .. i), x = 16 + ((i - 1) % 5) * 110, y = 320 + math.floor((i - 1) / 5) * 110 }
    end
    local panel = { placed = placed, controls = controls, titles = { { y = 40 }, { y = 290 } } }
    local t = Tour.targets(panel)
    check(t.controls and t.controls.y == 40 and t.controls.h == 70 + 110 + 100 - 40 and t.controls.w == 600 - 32
        and t.settings and t.settings.x == 16 + 2 * 110 and t.settings.y == 180
        and t.section and t.section.y == 290 and t.section.h == 320 + 100 - 290,
        "points at the panel's own parts: the Controls tiles, Settings, the section's heading and first row")
    local book, home = Tour.steps(panel, true), Tour.steps(panel, false)
    check(#book == 3 and book[1].text == Tour.TEXT.panel and book[2].text == Tour.TEXT.settings and book[3].text == Tour.TEXT.book
        and home[3].text == Tour.TEXT.home, "three steps: the panel (how to open and close it), Settings, This book or Home")
    -- the tour itself: opens the panel, then on its end closes it and hands over to the page browser tour
    local Panel = require("gzreader_panel")
    local shown, closed, reader_tour = {}, {}, 0
    local orig_show, orig_close, orig_tick = UIManager.show, UIManager.close, UIManager.nextTick
    UIManager.show = function(_self, w) shown[#shown + 1] = w end
    UIManager.close = function(_self, w) closed[#closed + 1] = w; if Panel.open == w then Panel.open = nil end end
    UIManager.nextTick = function(_self, fn) fn() end
    local real_cm = package.loaded["common/quickstart/menu_coachmark"]
    package.loaded["common/quickstart/menu_coachmark"] = { new = function(_self, o) return o end }
    local meta = { quickstart_menu_tour_pending = true, quickstart_reader_tour_pending = true }
    local saved = 0
    local plugin = { config = { _meta = meta }, saveConfig = function() saved = saved + 1 end,
        ui = { document = {}, menu = {
            onShowMenu = function() Panel.open = panel end,
            _zen_start_reader_tour = function() reader_tour = reader_tour + 1 end } } }
    local started = Tour.start(plugin)
    local mark = shown[#shown]
    check(started and Panel.open == panel and mark and mark.name == "gzreader tour" and #mark.steps == 3 and Tour.active,
        "in a book: the quick panel opens and the tour shows on it")
    check(not Tour.start(plugin), "…once")
    mark._finished = true
    mark.on_complete()
    check(Panel.open == nil and closed[#closed] == panel and meta.quickstart_menu_tour_pending == false and saved == 1
        and reader_tour == 1 and not Tour.active,
        "at its end: the panel closes, then the page browser tour (never under the panel)")
    meta.quickstart_menu_tour_pending, reader_tour = true, 0
    plugin.ui.document = nil
    Tour.start(plugin)
    shown[#shown].on_cancel()
    check(Panel.open == nil and meta.quickstart_menu_tour_pending == true and reader_tour == 0,
        "cancelled (the screen turned): the panel closes, the tour waits for the next start")
    UIManager.show, UIManager.close, UIManager.nextTick = orig_show, orig_close, orig_tick
    package.loaded["common/quickstart/menu_coachmark"] = real_cm
    Device.screen = was_screen
    Panel.open = nil
    local src = io.open(debug.getinfo(Tour.start, "S").source:sub(2):gsub("gzreader%.koplugin/gzreader_tour%.lua$",
        "zenos.koplugin/common/quickstart/reader_tour.lua"), "rb")
    local text = src and src:read("*a") or ""
    if src then src:close() end
    check(text:find("meta.quickstart_menu_tour_pending == true or GzTour.active then return false end", 1, true)
        and text:find("GzTour.closePanel()", 1, true), "ZenOS's page browser tour waits for it and never shows under the panel")
end)()

print("What's new after an update: GZreader's version and short points")
;(function()
    local New = require("gzreader_whatsnew")
    local log = {
        { version = "next", changes = { { short = "Next A", text = "Next A, long." }, "Next B. More about B." } },
        { version = "1.26.8", changes = { { short = "Eight", text = "Eight, long." } } },
        { version = "1.26.7", changes = { "Seven: it does this. And more.", { text = "Seven two. Long." } } },
        { version = "1.26.6", changes = { "Six." } },
    }
    local function same(a, b) return table.concat(a, "|") == table.concat(b, "|") end
    check(same(New.items(log, "1.26.8", "1.26.7"), { "Eight" }), "a release: its own points (short ones), not the older versions'")
    check(same(New.items(log, "1.26.8", "1.26.6"), { "Eight", "Seven: it does this.", "Seven two." }),
        "versions skipped since the last one shown come along; a line without a short point gives its first sentence")
    check(same(New.items(log, "1.26.8", nil), { "Eight" }), "nothing shown before (the first update with this screen): its own points")
    -- (a test build carries the last release's number: 1.26.7-beta.<commit> until 1.26.8 is out)
    check(same(New.items(log, "1.26.7-beta.abc1234", "1.26.7"), { "Next A", "Next B." })
        and same(New.items(log, "1.26.7-beta.def5678", "1.26.7-beta.abc1234"), { "Next A", "Next B." }),
        "a test build: what it brings (the next entry), each test build")
    check(same(New.items(log, "1.26.8", "1.26.7-beta.abc1234"), { "Eight" }), "from a test build to the release: the release's points")
    local long = New.firstSentence(string.rep("word ", 40))
    check(#long <= New.MAX_LEN + 2 and long:match("…$") and New.text({ short = "s", text = "t" }) == "t" and New.text("plain") == "plain",
        "a long first sentence is cut at a word; the full text stays for the changelog")
    -- pending(): marks seen, once per version
    local real_cur, seen_was = New.current, G_reader_settings:readSetting(New.SEEN)
    local cur = "1.26.8"
    New.current = function() return cur end
    local real_log = package.loaded["gzreader_changelog"]
    package.loaded["gzreader_changelog"] = log
    G_reader_settings:saveSetting(New.SEEN, "1.26.7")
    local p = New.pending()
    check(p and p.version == "1.26.8" and same(p.items, { "Eight" }) and New.pending() == nil
        and G_reader_settings:readSetting(New.SEEN) == "1.26.8", "shown once after the update, then not again")
    cur = "0.0.0"
    check(New.pending() == nil, "a tree without a version (development): nothing")
    package.loaded["gzreader_changelog"] = real_log
    New.current = real_cur
    if seen_was == nil then G_reader_settings:delSetting(New.SEEN) else G_reader_settings:saveSetting(New.SEEN, seen_was) end
    -- the real changelog: every line of the next entry has a short point
    local real = dofile(debug.getinfo(New.items, "S").source:sub(2):gsub("gzreader_whatsnew%.lua$", "gzreader_changelog.lua"))
    local ok_next = real[1].version ~= "next" or #real[1].changes > 0
    for _i, c in ipairs(real[1].version == "next" and real[1].changes or {}) do
        if not (type(c) == "table" and type(c.short) == "string" and #c.short <= New.MAX_LEN and type(c.text) == "string") then ok_next = false end
    end
    check(ok_next, "the changelog's next lines each have a short point (for the screen) and a text")
    -- ZenOS's update screen asks GZreader's
    local src = io.open(debug.getinfo(New.items, "S").source:sub(2):gsub("gzreader%.koplugin/gzreader_whatsnew%.lua$",
        "zenos.koplugin/main.lua"), "rb")
    local text = src and src:read("*a") or ""
    if src then src:close() end
    check(text:find('pcall(require, "gzreader_whatsnew")', 1, true) and text:find("is_update = gz_new ~= nil", 1, true)
        and text:find('"v" .. (gz_new and gz_new.version or current_ver)', 1, true)
        and text:find("hide_logo   = gz_new ~= nil", 1, true),
        "ZenOS's update screen shows GZreader's version and points, for GZreader's updates")
end)()

print("Flash on every page turn (Settings → General → Screen refresh)")
;(function()
    local Eink = require("gzreader_eink")
    local UIManager = require("ui/uimanager")
    local real_applies, keep_count = Eink.applies, UIManager.FULL_REFRESH_COUNT
    local keys = { Eink.PAGE_SETTING, Eink.SETTING, "full_refresh_count", "night_mode" }
    local saved = {}
    for _i, k in ipairs(keys) do saved[k] = G_reader_settings:readSetting(k); G_reader_settings:delSetting(k) end
    local legacy = true
    Eink.applies = function() return legacy end
    Eink.pageRate()
    check(Eink.flashPageTurns() and UIManager.FULL_REFRESH_COUNT == 1,
        "Kindle 2, DX, 3, 4: on by default, every page turn flashes")
    legacy = false
    Eink.pageRate()
    check(not Eink.flashPageTurns() and UIManager.FULL_REFRESH_COUNT == 6, "other devices: off by default (KOReader's every 6 pages)")
    Eink.setFlashPageTurns(true)
    check(Eink.flashPageTurns() and UIManager.FULL_REFRESH_COUNT == 1 and Eink.pageTurnsTicked(), "…and can be turned on there too")
    G_reader_settings:delSetting(Eink.PAGE_SETTING)
    legacy = true
    G_reader_settings:saveSetting(Eink.SETTING, false)
    check(not Eink.flashPageTurns(), "a Kindle 3 that had turned off \"Flash when the screen changes\" (it did both until now): stays off")
    Eink.setFlashPageTurns(true)
    check(Eink.flashPageTurns() and Eink.enabled() == false, "…and the two are separate now")
    G_reader_settings:saveSetting("full_refresh_count", 8)
    UIManager.FULL_REFRESH_COUNT = 8
    Eink.pageRate()
    check(UIManager.FULL_REFRESH_COUNT == 8 and not Eink.pageTurnsTicked(),
        "a rate chosen in a book's menu (every 8 pages) is kept, and the box shows it isn't every page")
    Eink.setFlashPageTurns(true)
    check(UIManager.FULL_REFRESH_COUNT == 1 and G_reader_settings:readSetting("full_refresh_count") == nil and Eink.pageTurnsTicked(),
        "ticking the box replaces that rate: every page")
    Eink.setFlashPageTurns(false)
    check(UIManager.FULL_REFRESH_COUNT == 6 and not Eink.pageTurnsTicked(), "unticked: every 6 pages")
    local f = io.open(debug.getinfo(Eink.promote, "S").source:sub(2):gsub("gzreader%.koplugin/gzreader_eink%.lua$",
        "zenos.koplugin/modules/settings/sections/gz_screen_refresh.lua"), "rb")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    check(src:find('if Eink and Eink.flashPageTurns then\n        items[#items + 1] = IconItem.decorate({\n            text = _("Flash on every page turn"),', 1, true)
        and src:find("Eink.pageTurnsTicked()", 1, true), "in Settings → General → Screen refresh, on every device")
    Eink.applies = real_applies
    UIManager.FULL_REFRESH_COUNT = keep_count
    for _i, k in ipairs(keys) do
        if saved[k] == nil then G_reader_settings:delSetting(k) else G_reader_settings:saveSetting(k, saved[k]) end
    end
end)()

print("No Local reading stats widget on Home (Settings → Home → Widgets)")
;(function()
    local saved_path = package.path
    package.path = PLUGIN .. "/../zenos.koplugin/?.lua;" .. package.path
    local WDIR = "modules/filebrowser/patches/home/widgets/"
    local stubs = { "datetime", "featured", "stats_triplet", "grimmory_stats", "reading_goals", "strip", "quotes" }
    local kept = {}
    for _i, id in ipairs(stubs) do
        kept[id] = package.loaded[WDIR .. id]
        package.loaded[WDIR .. id] = { id = id, label = id, size = "s", build = function() end }
    end
    local RP = "modules/filebrowser/patches/home/components/registry"
    package.loaded[RP] = nil
    local loaded, Registry = pcall(require, RP)
    check(loaded, "ZenOS's Home widget registry loads " .. tostring(not loaded and Registry or ""))
    if loaded then
        local function has(list, id) for _i, v in ipairs(list) do if v == id then return true end end end
        local rows = Registry.normalizeRows({}, { "datetime", "featured", "grimmory_stats", "stats_triplet", "strip" },
            { featured = true, grimmory_stats = true, stats_triplet = true, strip = true })
        check(not has(rows.order, "stats_triplet") and rows.enabled.stats_triplet == nil
            and has(rows.order, "grimmory_stats") and rows.enabled.grimmory_stats == true,
            "a new Home: Grimmory's reading stats, no Local reading stats (not in Widgets, not on Home)")
        rows = Registry.normalizeRows({ order = { "stats_triplet", "featured", "strip" },
            enabled = { stats_triplet = true, featured = true, strip = true } }, {}, {})
        check(not has(rows.order, "stats_triplet") and rows.enabled.stats_triplet == nil
            and rows.enabled.featured == true and rows.order[1] == "featured",
            "an older build's Home that showed them: gone, the other widgets kept in their order")
        rows = Registry.normalizeRows({ enabled = { stats_triplet = true } }, {}, { featured = true })
        check(rows.enabled.stats_triplet == nil and rows.enabled.featured == true,
            "a Home with only them: the default widgets instead of an empty Home")
        check(Registry.get("stats_triplet") ~= nil, "still there for the end-of-book page's stats")
    end
    package.loaded[RP] = nil
    for _i, id in ipairs(stubs) do package.loaded[WDIR .. id] = kept[id] end
    local sf = io.open(PLUGIN .. "/../zenos.koplugin/modules/settings/sections/library_settings/home_settings.lua", "rb")
    local src = sf and sf:read("*a") or ""
    if sf then sf:close() end
    local order = src:match("local DEFAULT_ORDER = (%b{})") or ""
    check(order:find('"grimmory_stats"', 1, true) and not order:find('"stats_triplet"', 1, true),
        "Settings → Home → Widgets' default list has no Local reading stats")
    package.path = saved_path
end)()

print("Headphones: the Kindle 3's audioHS message")
;(function()
    local Jack = require("gzreader_jack")
    local files, cmds, killed = {}, {}, {}
    files["/proc/bus/input/devices"] = "" -- (nothing that can be looked at: the Kindle 3)
    files[Jack.SYSLOG] = "Nov  8 18:00:00 kindle powerd: older line\n"
    Jack.read = function(p) return files[p] end
    Jack.exec = function(c) cmds[#cmds + 1] = c; files[Jack.EVENTS_FILE] = ""; files[Jack.EVENTS_FILE .. ".pid"] = "4242\n" end
    Jack.kill = function(pid) killed[#killed + 1] = pid end
    local was_info = package.loaded["ui/widget/infomessage"] -- (stand-ins above replaced it)
    package.loaded["ui/widget/infomessage"] = { new = function(_, o) captured.info = o.text; return o end }
    G_reader_settings:delSetting(Jack.SETTING)
    -- the guided test: the listener hears audioHS 1 plugging in, audioHS 0 unplugging
    Jack.test()
    check(cmds[1] and cmds[1]:find("lipc-wait-event -m com.lab126.hal audioHS > " .. Jack.EVENTS_FILE, 1, true),
        "Find the headphone jack listens to the Kindle's hardware service (" .. tostring(cmds[1]) .. ")")
    files[Jack.EVENTS_FILE] = "audioHS 1\n"
    captured.confirm.ok_callback()
    files[Jack.EVENTS_FILE] = "audioHS 1\naudioHS 0\n"
    captured.confirm.ok_callback()
    local det = G_reader_settings:readSetting(Jack.SETTING)
    check(type(det) == "table" and det.kind == "event" and det.name == "audioHS" and det.on == "1" and det.off == "0",
        "…and keeps the message that changed: audioHS 1 in, 0 out")
    check(killed[1] == 4242 and Jack.listening == nil, "the listener is stopped after the test")
    check(tostring(captured.info):find("com.lab126.hal audioHS", 1, true), "it says what it found: " .. tostring(captured.info))
    -- no listener output: the system log's lipc-send-event lines (as in a Kindle 3's log)
    G_reader_settings:delSetting(Jack.SETTING)
    Jack.exec = function(c) cmds[#cmds + 1] = c end
    files[Jack.EVENTS_FILE], files[Jack.EVENTS_FILE .. ".pid"] = nil, nil
    Jack.test()
    files[Jack.SYSLOG] = files[Jack.SYSLOG] .. "261108:235055 lipc-send-event[4467]: I lipc:evts:name=audioHS, origin=com.lab126.hal, fparam=1:Event sent\n"
    captured.confirm.ok_callback()
    files[Jack.SYSLOG] = files[Jack.SYSLOG] .. "261108:235058 lipc-send-event[4473]: I lipc:evts:name=audioHS, origin=com.lab126.hal, fparam=0:Event sent\n"
    captured.confirm.ok_callback()
    det = G_reader_settings:readSetting(Jack.SETTING)
    check(type(det) == "table" and det.kind == "event" and det.on == "1" and det.off == "0", "…or from the system log")
    -- nothing heard: nothing kept (as before)
    G_reader_settings:delSetting(Jack.SETTING)
    Jack.test()
    captured.confirm.ok_callback()
    captured.confirm.ok_callback()
    check(G_reader_settings:readSetting(Jack.SETTING) == nil and tostring(captured.info):find("Nothing on this Kindle changed", 1, true),
        "no message either: nothing kept")
    check(Jack.fromEvents({ { name = "audioHS", value = "1" } }, { { name = "audioHS", value = "1" } }) == nil,
        "the same message both times isn't the jack")
    -- while playing: one listener, its file read each second, paused on audioHS 0
    G_reader_settings:saveSetting(Jack.SETTING, { kind = "event", source = "com.lab126.hal", name = "audioHS", on = "1", off = "0" })
    check(Jack.plugged() == nil, "a message isn't a state: plugged() can't tell")
    cmds, killed = {}, {}
    Jack.exec = function(c) cmds[#cmds + 1] = c; files[Jack.EVENTS_FILE] = ""; files[Jack.EVENTS_FILE .. ".pid"] = "5151\n" end
    local paused = 0
    UI.scheduled = {}
    Jack.watch("music", function() paused = paused + 1 end)
    Jack.watch("tts", function() paused = paused + 1 end)
    check(#cmds == 1, "one listener for everything that plays (" .. #cmds .. " started)")
    local function runDue() local due = {}; for fn in pairs(UI.scheduled) do due[#due + 1] = fn end; UI.scheduled = {}; for _i, fn in ipairs(due) do fn() end end
    for _i = 1, 3 do runDue() end
    check(paused == 0 and #cmds == 1, "nothing heard: playing on, and no shell started for each look")
    files[Jack.EVENTS_FILE] = "audioHS 0\n"
    runDue()
    check(paused == 2 and next(Jack.watchers) == nil and killed[1] == 5151, "audioHS 0: everything playing pauses, and the listener stops")
    -- stopped by hand
    Jack.watch("audiobook", function() paused = paused + 1 end)
    Jack.unwatch("audiobook")
    check(Jack.listening == nil and Jack.event_ticker == nil and #killed == 2, "playback stopped: the listener stops")
    G_reader_settings:delSetting(Jack.SETTING)
    UI.scheduled = {}
    Jack.read, Jack.exec, Jack.kill = nil, nil, nil
    package.loaded["ui/widget/infomessage"] = was_info
end)()

print("Headphones")
;(function()
    local Jack = require("gzreader_jack")
    local files = {
        ["/proc/bus/input/devices"] = 'I: Bus=0000\nN: Name="mxc_ts"\nH: Handlers=event0\nB: EV=b\n\nI: Bus=0019\nN: Name="headphones"\nH: Handlers=kbd event2\nB: EV=21\nB: SW=4\n',
        ["/dev/input/event2#sw"] = "4",
    }
    Jack.read = function(p) return files[p] end
    G_reader_settings:delSetting(Jack.SETTING)
    local devs = Jack.switchDevices()
    check(#devs == 1 and devs[1].event == "/dev/input/event2" and Jack.plugged() == true, "an input device with a headphone switch: plugged in")
    files["/dev/input/event2#sw"] = "0"
    check(Jack.plugged() == false, "and unplugged")
    -- watching while playing
    files["/dev/input/event2#sw"] = "4"
    local paused = 0
    Jack.watch("music", function() paused = paused + 1 end)
    local tick = Jack.ticker
    tick()
    check(paused == 0, "headphones in: nothing happens")
    files["/dev/input/event2#sw"] = "0"
    Jack.ticker()
    check(paused == 1 and next(Jack.watchers) == nil, "unplugged while playing: paused")
    -- nowhere to tell: the test finds a file that changed
    files["/proc/bus/input/devices"] = ""
    files["#files"] = "/sys/devices/platform/codec/hp_det /sys/devices/platform/codec/other"
    files["/sys/devices/platform/codec/hp_det"] = "1"
    files["/sys/devices/platform/codec/other"] = "7"
    check(Jack.detector() == nil and Jack.plugged() == nil, "no switch: can't tell (nothing is paused)")
    local with = Jack.snapshot()
    files["/sys/devices/platform/codec/hp_det"] = "0"
    local det = Jack.compare(with, Jack.snapshot())
    check(det and det.kind == "file" and det.path == "/sys/devices/platform/codec/hp_det" and det.on == "1", "Find the headphone jack: the place that changed")
    G_reader_settings:saveSetting(Jack.SETTING, det)
    check(Jack.plugged() == false, "and it's used")
    files["/sys/devices/platform/codec/hp_det"] = "1"
    check(Jack.plugged() == true, "and plugged in again")
    -- an lipc property: read in the process when KOReader's lipc library opens
    Jack.unwatch("music")
    G_reader_settings:saveSetting(Jack.SETTING, { kind = "lipc", prop = "headphoneState", on = "1" })
    local reads, closed, state = 0, 0, "1"
    local handle = {
        get_string_property = function(_h, svc, prop)
            reads = reads + 1
            return svc == "com.lab126.audio" and prop == "headphoneState" and state or nil
        end,
        close = function() closed = closed + 1 end,
    }
    Jack.handle = nil
    Jack.lipc_open = function() return handle end
    Jack.shells = 0
    files["lipc:headphoneState"] = "1"
    local sched = {}
    local JUI = require("ui/uimanager")
    local real_in, real_un = JUI.scheduleIn, JUI.unschedule
    JUI.scheduleIn = function(_ui, s, fn) sched[#sched + 1] = { s = s, fn = fn } end
    JUI.unschedule = function() end
    paused = 0
    Jack.watch("audiobook", function() paused = paused + 1 end)
    check(Jack.inProcess() and sched[1] and sched[1].s == Jack.INTERVAL, "lipc in the process: a look every second")
    Jack.ticker()
    state = "0"
    Jack.ticker()
    check(paused == 1 and reads >= 3 and Jack.shells == 0, "unplugged: paused, with no shell started")
    check(closed == 1 and Jack.handle == nil, "nothing playing: the lipc handle is closed")
    -- no lipc library: lipc-get-prop, but only every few seconds
    Jack.handle = nil
    Jack.lipc_open = function() return nil end
    sched = {}
    Jack.watch("audiobook", function() end)
    check(not Jack.inProcess() and sched[1] and sched[1].s == Jack.SHELL_INTERVAL and Jack.SHELL_INTERVAL >= 3,
        "no lipc library: looks with a shell every " .. tostring(Jack.SHELL_INTERVAL) .. " s, not every second")
    Jack.unwatch("audiobook")
    check(Jack.handle == nil, "stopped: nothing kept open")
    JUI.scheduleIn, JUI.unschedule = real_in, real_un
    Jack.lipc_open = nil
    Jack.handle = nil
    G_reader_settings:delSetting(Jack.SETTING)
    Jack.read = nil
end)()

print("Copying connections: the PIN exchange and mDNS")
;(function()
    local Spake = require("gzreader_spake")
    check(Spake.available(), "libcrypto found")
    local a, b = Spake.new("A", "123456"), Spake.new("B", "123456")
    check(a:finish(b:message()) and b:finish(a:message()) and a.key == b.key and a:checkConfirmation(b:confirmation())
        and b:checkConfirmation(a:confirmation()), "SPAKE2: the same PIN, the same keys, each confirmed")
    local c, d = Spake.new("A", "123456"), Spake.new("B", "123457")
    c:finish(d:message()); d:finish(c:message())
    check(c.key ~= d.key and not c:checkConfirmation(d:confirmation()) and not d:checkConfirmation(c:confirmation()), "SPAKE2: a different PIN, different keys")
    check(a:message() ~= Spake.new("A", "123456"):message(), "SPAKE2: a new message every time")
    local x = Spake.new("A", "1")
    check(x:finish(string.rep("00", 255) .. "01") == nil and x:finish(Spake.hex(string.rep("\255", 256))) == nil
        and x:finish("abcd") == nil, "SPAKE2: 1, p - 1 or more, and short messages refused")
    local sealed = Spake.seal(a.key, "secret", "to receiver")
    check(Spake.open(b.key, sealed, "to receiver") == "secret" and Spake.open(b.key, sealed, "to sender") == nil
        and Spake.open(c.key, sealed, "to receiver") == nil, "AES-GCM: opens with its key and label only")
    local flip = sealed:sub(1, 30) .. (sealed:sub(31, 31) == "a" and "b" or "a") .. sealed:sub(32)
    check(Spake.open(b.key, flip, "to receiver") == nil, "AES-GCM: a changed message is refused")
    -- mDNS: answers as DNS-SD has them; found by asking (over loopback, unicast)
    local Mdns = require("gzreader_mdns")
    local MP = PORT + 9
    local r = Mdns.advertise({ name = "Kindle Keyboard · 3F2A", id = "3f2a91", port = 8650, ip = "127.0.0.1", version = "9.9" },
        { bind = "127.0.0.1", port = MP, no_multicast = true })
    local br = Mdns.browse({ to = "127.0.0.1", port = MP, duration = 1.5 })
    local t0 = socket.gettime()
    while socket.gettime() - t0 < 1.6 do r:poll(); br:poll(); socket.sleep(0.05) end
    local devs = br:devices()
    check(r and #devs == 1 and devs[1].name == "Kindle Keyboard · 3F2A" and devs[1].port == 8650 and devs[1].ip == "127.0.0.1"
        and devs[1].id == "3f2a91" and devs[1].version == "9.9", "mDNS: the sending device is found, with its name, address and port")
    r:close(); br:close()
    local q = Mdns.parse(string.char(0, 7, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0) .. Mdns.encodeName("other._tcp.local") .. string.char(0, 12, 0, 1))
    check(q and Mdns.answer({ name = "x", id = "1", port = 1, ip = "1.2.3.4" }, q, true) == nil, "mDNS: other services' questions aren't answered")
    check(Mdns.parse("short") == nil and Mdns.parse(string.rep("\255", 40)) ~= false, "mDNS: junk doesn't break it")
end)()

print("1.23.7 fixes and speed-ups")
;(function()
    -- Wi-Fi: an older attempt's 90 s give-up leaves a later attempt alone
    local Net = require("gzreader_net")
    local NM = require("ui/network/manager")
    local saved = { NM.enableWifi, NM.isWifiOn, Net.connected, Net.enabled, Net.keptOff }
    NM.enableWifi = function() return nil end -- (still connecting)
    NM.isWifiOn = function() return false end
    Net.connected = function() return false end
    Net.enabled = function() return true end
    Net.keptOff = function() return false end
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end
    Net.connecting = nil
    Net.run(function() end, { quiet = true, reason = "first" })
    local first_timer
    for f, t in pairs(UI.scheduled) do if t == 90 then first_timer = f end end
    Net.connecting = nil -- (that one ended: Wi-Fi off again)
    Net.run(function() end, { quiet = true, reason = "second" })
    local second = Net.connecting
    if first_timer then first_timer() end
    check(first_timer and second and Net.connecting == second, "Wi-Fi: the first attempt's 90 s timer doesn't drop a later attempt")
    for f, t in pairs(UI.scheduled) do if t == 90 and f ~= first_timer then f() end end
    check(Net.connecting == nil, "…its own timer still gives up on it")
    NM.enableWifi, NM.isWifiOn, Net.connected, Net.enabled, Net.keptOff = unpack(saved, 1, 5)
    Net.connecting, Net.ours = nil, false
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end

    -- positions for a book Grimmory doesn't have: not queued again this run
    local G = Grimmory
    local lfs = require("libs/libkoreader-lfs")
    G.gone_books["98765"] = true
    plugin:queue("progress", 98765, { fileProgress = {} })
    check(plugin.store.pending.progress["98765"] == nil, "a book Grimmory said is gone: its position isn't queued again")
    G.gone_books["98765"] = nil

    -- queued changes: saved once, a little later (or at once when flushed)
    local saves = 0
    local orig_save = plugin.save
    plugin.save = function(self) saves = saves + 1; return orig_save(self) end
    if G.save_soon then G.save_soon() end
    saves = 0
    plugin:queue("progress", 4242, { fileProgress = { progressPercent = 1 } })
    plugin:queue("progress", 4242, { fileProgress = { progressPercent = 2 } })
    check(saves == 0 and G.save_soon ~= nil, "queued positions: not written at once")
    plugin:onFlushSettings()
    check(saves == 1, "…written when KOReader flushes settings (sleep, closing a book)")
    plugin:clearQueued("progress", 4242)
    if G.save_soon then G.save_soon() end
    for f in pairs(UI.scheduled) do UI.scheduled[f] = nil end

    -- the music folder: nothing changed, nothing written
    local MF = require("gzreader_musicfolder")
    saves = 0
    pcall(MF.sync, plugin)
    check(saves == 0, "music folder check: settings not written when nothing changed")
    plugin.save = orig_save

    -- subtitles: each book's looked at once
    local Titles = require("gzreader_titles")
    local s_sub, s_apply = Titles.subtitle, Titles.apply
    local applied, fsaves = 0, 0
    Titles.subtitle = function() return "Old School" end
    Titles.apply = function() applied = applied + 1; return true end
    local fake = { store = { downloads = { ["1"] = { path = "/x.epub", title = "T" } } }, save = function() fsaves = fsaves + 1 end }
    Titles.backfill(fake); Titles.backfill(fake)
    check(applied == 1 and fsaves == 1, "subtitles: a book's file is looked at once, not at every start")
    Titles.subtitle, Titles.apply = s_sub, s_apply

    -- library upkeep: only when the index or the folder changed
    local relinks = 0
    local lib = { store = { library_dir = WORK, downloads = {} }, relinkLibrary = function() relinks = relinks + 1 end }
    G.upkeep_sig = nil
    G.libraryUpkeep(lib, { built_at = 1 }); G.libraryUpkeep(lib, { built_at = 1 })
    check(relinks == 1, "library upkeep: not again when nothing changed")
    G.libraryUpkeep(lib, { built_at = 2 })
    G.libraryUpkeep(lib, { built_at = 2 }, true)
    check(relinks == 3, "…again after a new index, or when asked")
    G.upkeep_sig = nil

    -- saved lists: the folder tidied every 10 minutes at most
    local Cache = require("gzreader_listcache")
    local max = Cache.MAX_FILES
    local function count()
        local n = 0
        for name in lfs.dir(Cache.dir()) do if name:match("%.json$") then n = n + 1 end end
        return n
    end
    Cache.MAX_FILES = 1
    Cache.pruned_at = os.time()
    Cache.put("t-a", { 1 }); Cache.put("t-b", { 2 })
    local kept = count()
    Cache.pruned_at = 0
    Cache.put("t-c", { 3 })
    check(kept >= 2 and count() == 1, "saved lists: tidied at most every 10 minutes (" .. kept .. ", " .. count() .. ")")
    Cache.MAX_FILES, Cache.pruned_at = max, nil

    -- the shop's front page: what GZreader keeps, read once a minute
    local Shop = require("gzreader_bookshop")
    local s_read, reads = Shop.readKnown, 0
    Shop.readKnown = function() reads = reads + 1; return {} end
    local br = { plugin = plugin }
    Shop.known(br); Shop.known(br)
    check(reads == 1, "shop front page: its counts not read again at every return")
    br._shop.known_at = os.time() - 61
    Shop.known(br)
    check(reads == 2, "…but again after a minute")
    Shop.readKnown = s_read

    -- slow traces: due tasks still run, in order, each timed
    local UIM = require("ui/uimanager")
    local order = {}
    local q = { _task_queue = {
        { time = 2, action = function(x) order[#order + 1] = x end, args = { "late", n = 1 } },
        { time = 0, action = function(x) order[#order + 1] = x end, args = { "b", n = 1 } },
        { time = 0, action = function(x) order[#order + 1] = x end, args = { "a", n = 1 } },
    } }
    local time = require("ui/time")
    q._task_queue[1].time = time.now() + time.s(60)
    q._task_queue[2].time, q._task_queue[3].time = time.s(0), time.s(0)
    local wait = UIM._checkTasks(q)
    check(table.concat(order, ",") == "a,b" and #q._task_queue == 1 and wait == q._task_queue[1].time,
        "slow traces: scheduled tasks run as KOReader runs them (" .. table.concat(order, ",") .. ")")
end)()

print("Settings → Storage")
;(function()
    local St = require("gzreader_storage")
    local lib = WORK .. "/storage-lib"
    os.execute("rm -rf '" .. lib .. "'")
    local function put(path, bytes)
        os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
        local f = io.open(path, "wb"); f:write(string.rep("x", bytes)); f:close()
    end
    put(lib .. "/Big Book.epub", 5000)
    put(lib .. "/Big Book.sdr/metadata.epub.lua", 1000)
    put(lib .. "/Small.pdf", 300)
    put(lib .. "/Series/Third.epub", 2000)
    put(lib .. "/Half.epub.part", 700)
    put(lib .. "/Audiobooks/Walk.epub", 50)            -- a stand-in: not a book
    put(lib .. "/.audiobooks/90/audiobook.m4b", 9000)
    put(lib .. "/.audiobooks/90/audiobook.m4b.chunks/0.aac", 4000)
    put(lib .. "/.audiobooks/7/a.mp3", 3000)
    put(lib .. "/.music/album-1/01.mp3", 6000)
    put(lib .. "/Music/Album.epub", 40)
    local fake = { store = {
        downloads = { ["5"] = { path = lib .. "/Big Book.epub", title = "The Big Book" } },
        audiobooks = { [90] = { title = "A Walk in the Woods" } },
    } }
    local b = St.books(fake, lib)
    check(b.count == 4 and b.bytes == 9000 and b.items[1].name == "The Big Book" and b.items[1].bytes == 6000
        and b.items[2].name == "Third" and b.items[3].name:match("^Half") and b.items[3].name:match("unfinished"),
        "storage: books with their KOReader settings, largest first, titles from Grimmory (" .. b.bytes .. ")")
    local a = St.audiobooks(fake, lib)
    check(a.count == 2 and a.items[1].name == "A Walk in the Woods" and a.items[1].bytes == 13000 and a.bytes == 16050,
        "storage: audiobooks (audio and what was made from it), by title")
    local m = St.music(fake, lib)
    check(m.count == 1 and m.bytes == 6040, "storage: music, with the stand-ins")
    check(St.noteName("# Groceries\nmilk") == "Groceries" and St.noteName("  ") ~= "" and #St.noteName(string.rep("é", 60)) < 140,
        "storage: a note is named by its first line")
    local items = St.items({ disk = { total = 3 * 1024 ^ 3, available = 1024 ^ 3 }, books = b, audiobooks = a, music = m,
        notes = { bytes = 2048, count = 0, items = {} }, calendar = { bytes = 2048 }, caches = { bytes = 10 * 1024 ^ 2 } })
    local by = {}
    for _i, it in ipairs(items) do by[it.text] = it end
    check(by["Free on this Kindle"].mandatory == "1.00 GB of 3.00 GB" and by.Books.mandatory == "4 books · 9 KB"
        and #by.Books.sub_item_table == 4 and by.Notes.sub_item_table[1].text:match("No notes")
        and by.Calendar.mandatory == "2 KB" and by["Covers and saved lists"].mandatory == "10.0 MB",
        "storage page: free space, each part's size, the biggest of each")
    -- Settings → General → Storage: rows with icons, arrows into the biggest
    local function iconed(it) return it and (it.icon_glyph or it.icon_name or it.icon_file) ~= nil end
    check(iconed(by["Free on this Kindle"]) and iconed(by.Books) and iconed(by.Books.sub_item_table[1]) and iconed(by.Audiobooks)
        and by.Music.icon_name == "tab_music" and iconed(by.Notes) and iconed(by["Covers and saved lists"])
        and by.Books.sub_item_table and not by.Calendar.sub_item_table,
        "storage rows: an icon on each (the parts and their books), a submenu where there are things in it")
    local saved_bg, saved_last = St._background, St.last
    local pending
    St._background = function(fn, done) pending = done end
    St.last = nil
    local spage = { updated = 0 }
    function spage.updateItems(p) p.updated = p.updated + 1 end
    local list = St.settingsItems(fake, spage)
    check(#list == 1 and list[1].text:match("Measuring"), "storage settings: Measuring… until it's measured")
    spage.item_table = list
    pending({ disk = { total = 2 * 1024 ^ 3, available = 1024 ^ 3 }, books = b, calendar = { bytes = 10 } })
    check(spage.updated == 1 and list[1].text == "Free on this Kindle" and list[2].text == "Books" and #list == 3
        and St.last ~= nil, "storage settings: the same rows filled in where they're shown, then kept")
    local again = St.settingsItems(fake, spage)
    check(again[2] and again[2].text == "Books", "storage settings: shown at once the next time (measured again behind)")
    pending({ disk = { total = 1, available = 1 } })
    check(spage.updated == 1, "storage settings: a page showing other rows isn't redrawn")
    St._background, St.last = saved_bg, saved_last
    os.execute("rm -rf '" .. lib .. "'")
end)()

print("Sync through a computer (Kindles without Wi-Fi)")
;(function()
    local Usb = require("gzreader_usbsync")
    local OfflineApi = require("gzreader_offlineapi")
    local Net = require("gzreader_net")
    local JSON = require("json")
    local lib = WORK .. "/usb-lib"
    os.execute("rm -rf '" .. lib .. "'; mkdir -p '" .. lib .. "'")
    local function put(path, text)
        os.execute("mkdir -p '" .. path:match("^(.*)/[^/]*$") .. "'")
        local f = io.open(path, "wb"); f:write(text); f:close()
    end
    local function read(path) local f = io.open(path, "rb"); if not f then return nil end local t = f:read("*a"); f:close(); return t end
    local function exists(path) return require("lfs").attributes(path, "mode") ~= nil end

    check(Usb.noWifi("Kindle2") and Usb.noWifi("KindleDXG") and not Usb.noWifi("Kindle3") and not Usb.noWifi("KindlePaperWhite3"),
        "the Kindle 2 and DX have no Wi-Fi; the Kindle Keyboard and Paperwhite do")
    check(not Usb.active(), "a Kindle Keyboard syncs over Wi-Fi unless told otherwise")
    Usb.setActive(true)
    check(Usb.active(), "…any Kindle can choose to sync through a computer")
    Usb.setActive(false)
    check(not Usb.active() and G_reader_settings:readSetting("gzreader_usb_sync") == nil, "…and back (no setting kept for the default)")

    local saved = 0
    local fake = { store = {
        server = "https://books.example.com", username = "reader",
        access_token = "SECRET-ACCESS", refresh_token = "SECRET-REFRESH",
        downloads = {}, audiobooks = {},
        pending = { progress = {
            ["12"] = { fileProgress = { bookFileId = 120, progressPercent = 41.5, positionHref = "ch3.xhtml" },
                gz_xp = "/body/DocFragment[3]", gz_file = lib .. "/x.epub" },
        }, sessions = {
            { bookId = 12, startTime = "2026-11-05T10:00:00Z", endTime = "2026-11-05T10:30:00Z", durationSeconds = 1800, gz_tries = 1 },
        }, ratings = { ["12"] = 4, ["13"] = 0 } },
        memos = { server = "https://notes.example.com", token = "SECRET-MEMOS",
            queue = { { id = "q1", op = "create", content = "milk #shopping", visibility = "PRIVATE", at = 5 } } },
        caldav = { server = "https://cal.example.com", password = "SECRET-CALDAV" },
        plex = { token = "SECRET-PLEX" },
    } }
    function fake:libraryDir() return lib end
    function fake:save() saved = saved + 1 end
    function fake:saveSoon() end
    function fake:writeManifest() end

    -- the queue
    check(Usb.enqueue(fake, { id = 20, title = "Dune", authors = { "Frank Herbert" }, primaryFileType = "EPUB", primaryFileId = 200,
        primaryFileName = "lib/Dune.epub", fileSizeKb = 900 }) and not Usb.enqueue(fake, { id = 20, title = "Dune" }),
        "sync queue: a book goes in once")
    Usb.enqueue(fake, { id = 30, title = "Walden (audio)", primaryFileType = "AUDIOBOOK", fileSizeKb = 50000 })
    check(#fake.store.usb_queue == 2 and fake.store.usb_queue[2].kind == "audiobook" and fake.store.usb_queue[1].name == "Dune.epub"
        and Usb.isQueued(fake, "20") and Usb.queueSizeKb(fake) == 50900, "…audiobooks too; ids and sizes kept")

    -- the outbox
    Usb.number(fake)
    Usb.writeOutbox(fake)
    local text = read(lib .. "/.gzsync/outbox.json") or ""
    local out = JSON.decode(text) or {}
    local jobs = {}
    for _i, j in ipairs(out.jobs or {}) do jobs[j.kind] = jobs[j.kind] or {}; table.insert(jobs[j.kind], j) end
    local pj = jobs.progress and jobs.progress[1]
    check(out.format == 1 and out.grimmory.server == "https://books.example.com" and pj and pj.method == "PUT"
        and pj.path == "/api/v1/app/books/12/progress" and pj.body.fileProgress.progressPercent == 41.5
        and pj.body.gz_xp == nil and pj.body.gz_seq == nil and pj.id:match("^p:12:%d+$"),
        "outbox: a reading position as a ready request (GZreader's own fields left out)")
    local sj = jobs.session and jobs.session[1]
    check(sj and sj.path == "/api/v1/reading-sessions" and sj.body.durationSeconds == 1800 and sj.body.gz_tries == nil
        and sj.id == "s:12:2026-11-05T10:00:00Z", "outbox: reading time")
    local rj = {}
    for _i, j in ipairs(jobs.rating or {}) do rj[j.book] = j end
    check(rj[12] and rj[12].method == "PUT" and rj[12].body.rating == 8 and rj[13] and rj[13].path == "/api/v1/books/reset-personal-rating",
        "outbox: ratings (and a rating taken away)")
    check(#out.queue == 2 and out.notes.queue[1].content == "milk #shopping" and out.calendar.days_ahead == 90,
        "outbox: the sync queue, notes written here, the calendar range")
    check(out.music_quality and out.music_quality.bitrate == ((fake.store.plex or {}).bitrate or 192)
        and out.music_quality.shrink == ((fake.store.plex or {}).shrink == true),
        "outbox: Plex music's quality, for the page")
    check(Usb.musicLibrary({ plex = { music_section = { server = "s", key = 4, title = "Concerts" } } }).key == "4"
        and Usb.musicLibrary({ plex = {} }) == nil and Usb.musicLibrary({}) == nil, "outbox: the music library chosen on the Kindle, for the page")
    check(text:find('"music":[]', 1, true) and text:find('"audiobooks":[]', 1, true),
        "outbox: empty lists written as lists ([], not {}: the page reads them as lists)")
    check(not text:find("SECRET", 1, true) and not text:find("password", 1, true),
        "outbox: no password or token in it")
    local mtime = require("lfs").attributes(lib .. "/.gzsync/outbox.json", "modification")
    os.remove(lib .. "/.gzsync/outbox.json")
    Usb.writeOutbox(fake)
    check(exists(lib .. "/.gzsync/outbox.json") and mtime, "outbox: written again when it's gone")
    check(out.test_builds == nil, "outbox: test builds off, not mentioned")
    gsettings.gzreader_update_beta = true
    os.remove(lib .. "/.gzsync/outbox.json")
    Usb.writeOutbox(fake)
    check((JSON.decode(read(lib .. "/.gzsync/outbox.json") or "") or {}).test_builds == true, "outbox: test builds on (the page then brings those)")
    gsettings.gzreader_update_beta = nil

    -- the library copy: browsing without a network
    local api = OfflineApi:new(fake.store, nil, lib .. "/.gzsync")
    check(not api:isPaired(), "no copy of the library yet: not connected")
    local books = {
        { id = 1, title = "Emma", authors = { "Jane Austen" }, primaryFileType = "EPUB", libraryId = 1, addedOn = "2026-01-02", readStatus = "READING" },
        { id = 2, title = "persuasion", authors = { "Jane Austen" }, primaryFileType = "PDF", libraryId = 2, addedOn = "2026-03-01", seriesName = "Novels", seriesNumber = 2 },
        { id = 3, title = "Walden", authors = { "Henry David Thoreau" }, primaryFileType = "AUDIOBOOK", libraryId = 1, addedOn = "2026-02-01" },
        { id = 4, title = "Dracula", authors = { "Bram Stoker" }, primaryFileType = "EPUB", libraryId = 1, seriesName = "Novels", seriesNumber = 1 },
    }
    put(lib .. "/.gzsync/library.json", JSON.encode({ format = 1, server = "https://books.example.com", user = "reader", books = books,
        libraries = { { id = 1, name = "Main" }, { id = 2, name = "Papers" } }, shelves = { { id = 7, name = "Fav" }, { id = 8, name = "Magic", magic = true } },
        lists = { shelf = { ["7"] = { 4, 1 } }, magic = { ["8"] = { 2 } }, continue = { 1 } },
        full = { ["1"] = { id = 1, epubProgress = { cfi = "epubcfi(/6/4)", percentage = 10 } } },
        audio = { ["3"] = { durationMs = 1000, folderBased = false } }, subtitles = { ["2"] = "A Novel" } }))
    put(lib .. "/.gzsync/details/1.json", JSON.encode({ id = 1, title = "Emma", description = "A clever young woman…" }))
    put(lib .. "/.gzsync/covers/1.jpg", "JPEGDATA")
    OfflineApi.forget()
    check(api:isPaired(), "with a copy: connected (offline)")
    local all = api:listBooks{ sort = "title", dir = "asc", size = 2, page = 0 }
    check(all.totalElements == 4 and all.totalPages == 2 and all.content[1].title == "Dracula" and all.content[2].title == "Emma"
        and all.hasNext, "copy: all books, A–Z, a page at a time (case ignored)")
    local readable = api:listBooks{ fileType = api.READABLE_TYPES, libraryId = 1, sort = "addedOn", dir = "desc" }
    check(readable.totalElements == 2 and readable.content[1].id == 1 and readable.content[2].id == 4,
        "copy: by type and library; newest first, undated last")
    check(api:listBooks{ shelfId = 7 }.totalElements == 2 and api:listBooks{ magicShelfId = 8 }.content[1].id == 2
        and api:listBooks{ status = { "READING" } }.content[1].id == 1 and api:listBooks{ authors = "Jane Austen" }.totalElements == 2,
        "copy: shelves, magic shelves, reading status, author")
    local series = api:listBooks{ series = "Novels", sort = "seriesName", dir = "asc" }
    check(series.content[1].id == 4 and series.content[2].id == 2, "copy: a series in its order")
    check(api:searchBooks("austen").totalElements == 2 and api:searchBooks("WALD").content[1].id == 3, "copy: search titles and authors")
    check(api:continueReading(10)[1].id == 1 and api:simpleList("recently-added", 2)[1].id == 2, "copy: continue reading, recently added")
    check(#api:listLibraries() == 2 and api:listShelves()[2].magic == true, "copy: libraries and shelves")
    check(api:getBook(1).epubProgress.cfi == "epubcfi(/6/4)" and select(2, api:getBook(2)) == "usb",
        "copy: a downloaded book's record (its place elsewhere)")
    check(api:getBookDetail(1).description:match("clever") and api:getBookDetail(2).subtitle == "A Novel",
        "copy: a book's page, or what the list knows")
    check(api:listWebBooks(0).content[1].metadata.subtitle == "A Novel", "copy: subtitles for the index")
    check(api:audiobookInfo(3).durationMs == 1000, "copy: an audiobook's details")
    local thumb = WORK .. "/usb-thumb.jpg"
    check(api:downloadThumbnail(1, thumb) and read(thumb) == "JPEGDATA" and not api:downloadThumbnail(2, thumb),
        "copy: covers")
    check(api:downloadThumbnails({ { id = 1, path = thumb }, { id = 4, path = thumb } }).got == 1, "copy: covers for a page")
    check(not api:putProgress(1, {}) and select(2, api:putProgress(1, {})) == "usb" and select(2, api:postSession({})) == "usb"
        and not api:putRating(1, 8), "copy: writes aren't sent (they stay queued for the computer)")

    -- bookmarks and highlights without Wi-Fi: the journal
    local snapx = JSON.decode(read(lib .. "/.gzsync/library.json"))
    snapx.marks = { ["1"] = { bookmarks = { { id = 501, bookId = 1, cfi = "epubcfi(/6/4!/4/2)", title = "web" } },
        annotations = { { id = 901, bookId = 1, cfi = "epubcfi(/6/4!/4/2,/1:0,/1:5)", text = "Hello", color = "#FFC107", note = nil } } } }
    put(lib .. "/.gzsync/library.json", JSON.encode(snapx))
    OfflineApi.forget()
    check(api:listBookmarks(2) == nil and #api:listBookmarks(1) == 1, "marks: Grimmory's bookmarks from the copy (none known: nothing to compare)")
    local made = api:createBookmark({ bookId = 1, cfi = "epubcfi(/6/8!/4/2)", title = "Kindle" })
    check(made and tostring(made.id):match("^usb%-") and #api:listBookmarks(1) == 2, "marks: a bookmark made here gets a temporary id and is listed")
    check(api:deleteBookmark(501) and #api:listBookmarks(1) == 1 and api:listBookmarks(1)[1].id == made.id, "marks: …a deleted one isn't")
    local hl = api:createAnnotation({ bookId = 1, cfi = "epubcfi(/6/8!/4/2,/1:0,/1:3)", text = "Abc", color = "#4ADE80" })
    api:updateAnnotation(hl.id, { color = "#F87171", note = "mine" })
    api:updateAnnotation(901, { note = "web note" })
    local anns = api:listAnnotations(1)
    local by = {}
    for _i, a in ipairs(anns) do by[tostring(a.id)] = a end
    check(#anns == 2 and by[tostring(hl.id)].color == "#F87171" and by[tostring(hl.id)].note == "mine" and by["901"].note == "web note",
        "marks: highlights made and changed here, on top of Grimmory's")
    api:deleteAnnotation(901)
    check(#api:listAnnotations(1) == 1, "marks: …and deleted")
    local mj = {}
    for _i, j in ipairs(Usb.jobs(fake)) do if j.kind == "mark" then mj[#mj + 1] = j end end
    check(#mj == 6 and mj[1].op == "bookmark+" and mj[1].temp == made.id and mj[2].ref == "501" and mj[2].path == "/api/v1/bookmarks/{id}"
        and mj[4].ref == tostring(hl.id) and mj[6].op == "highlight-", "outbox: the journal's requests, in order, for the page")
    fake.store.downloads["1"] = { bookmarks = { ["/body/x"] = made.id }, anno_shadow = { [tostring(hl.id)] = { full = 1 } } }
    local sent = Usb.applyMarks(fake, { [mj[1].id] = true, [mj[2].id] = true, [mj[3].id] = true }, { [made.id] = 777, [hl.id] = 888 })
    local rest = Usb.journal(fake)
    check(sent == 3 and #rest == 3 and rest[1].ref == "888" and fake.store.downloads["1"].bookmarks["/body/x"] == 777
        and fake.store.downloads["1"].anno_shadow["888"] and Usb.realId(fake, hl.id) == 888,
        "inbox: what was sent leaves the journal; Grimmory's ids replace the temporary ones everywhere")
    os.remove(Usb.journalPath(fake))
    fake.store.downloads["1"] = nil

    -- what the page brought
    local base = lib .. "/.gzsync"
    put(base .. "/in/book-20.epub", "EPUB-DUNE")
    put(base .. "/in/audio-30/audiobook.mp3", "ID3-MP3")
    put(base .. "/in/audio-30/cover.jpg", "JPEG")
    put(base .. "/in/music-album-55/01.mp3", "ID3")
    put(base .. "/in/music-album-55/music.json", JSON.encode({ kind = "album", key = "55", title = "Blue", artist = "Joni",
        tracks = { { key = "551", title = "All I Want", base = "01", file = "01.mp3", duration = 1000 } } }))
    put(base .. "/in/notes.json", JSON.encode({ at = 1000, notes = { { name = "memos/1", content = "hello #a", tags = { "a" }, attachments = {} } },
        tags = { a = 1 } }))
    put(base .. "/in/notes-files/abc-pic.jpg", "PIC")
    local now = os.time()
    local function ics(t) return os.date("!%Y%m%dT%H%M%SZ", t) end
    put(base .. "/in/calendar/1.ics", "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:e1\r\nSUMMARY:Dentist\r\nDTSTART:" .. ics(now + 86400)
        .. "\r\nDTEND:" .. ics(now + 90000) .. "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n")
    local done = { pj.id, sj.id, rj[12].id }
    put(base .. "/inbox.json", JSON.encode({ format = 1, written_at = 1700000000, done = done,
        failed = { { id = rj[13].id, error = "unreachable" } },
        grimmory = { server = "https://books.example.com", user = "reader" },
        books = { { id = 20, file = "in/book-20.epub", name = "Dune.epub", title = "Dune", authors = { "Frank Herbert" }, format = "EPUB", file_id = 200,
            progress = { epubProgress = { percentage = 40, cfi = "epubcfi(/6/4)" } } } },
        audiobooks = { { id = 30, dir = "in/audio-30", primaryFileName = "Walden.mp3", title = "Walden",
            progress = { audiobookProgress = { positionMs = 2000, trackIndex = 0 } },
            info = { title = "Walden", author = "Thoreau", durationMs = 5000, codec = "mp3", bookFileId = 300, folderBased = false } } },
        music = { { kind = "album", key = "55", dir = "in/music-album-55" } },
        notes = { file = "in/notes.json", files = "in/notes-files", done = { "q1" }, server = "https://notes.example.com", user = "me" },
        calendars = { { name = "Family", file = "in/calendar/1.ics" } } }))
    local prepared = false
    local r = Usb.import(fake, function() prepared = true end)
    local entry = fake.store.downloads["20"]
    check(r and r.books == 1 and entry and entry.path == lib .. "/Dune.epub" and read(entry.path) == "EPUB-DUNE"
        and entry.authors == "Frank Herbert" and entry.file_id == 200 and not Usb.isQueued(fake, 20),
        "inbox: a book into the GZreader folder, as a download, off the queue")
    check(entry.grimmory_progress and entry.grimmory_progress.epubProgress.percentage == 40
        and fake.store.audiobooks["30"].grimmory_progress.audiobookProgress.positionMs == 2000,
        "inbox: Grimmory's progress kept for the first opening (books and audiobooks)")
    check(next(fake.store.pending.progress) == nil and #fake.store.pending.sessions == 0 and fake.store.pending.ratings["12"] == nil
        and fake.store.pending.ratings["13"] == 0 and fake.store.downloads["20"] and r.sent == 3 and r.failed == 1,
        "inbox: what went to Grimmory is off the pending lists; what didn't stays")
    local ab = require("gzreader_audiobook").load(fake, "30")
    check(r.audiobooks == 1 and prepared and ab and ab.title == "Walden" and ab.files[1] == "audiobook.mp3"
        and fake.store.audiobooks["30"] and not Usb.isQueued(fake, 30), "inbox: an audiobook, ready to listen to")
    local col = require("gzreader_music").load(require("gzreader_music").dirFor(fake, "album", "55"))
    check(r.music == 1 and col and col.have == 1 and col.title == "Blue", "inbox: music")
    local Memos = require("gzreader_memos")
    local cache = Memos.loadCache()
    check(r.notes == 1 and cache and cache.notes[1].content == "hello #a" and #fake.store.memos.queue == 0
        and fake.store.memos.token == "SECRET-MEMOS" and read(Memos.filesDir() .. "/abc-pic.jpg") == "PIC",
        "inbox: notes (the ones written here are in Memos now), their pictures")
    local cal = require("gzreader_caldav").loadCache()
    check(r.events == 1 and cal and cal.events[1].title == "Dentist" and fake.store.calendar_feeds[1].name == "Family"
        and fake.store.calendar_feeds[1].usb, "inbox: calendars, as events")
    check(not exists(base .. "/inbox.json") and not exists(base .. "/in") and fake.store.usb_last.books == 1,
        "inbox: taken in once, then gone")
    check(Usb.import(fake) == nil, "no inbox: nothing to do")
    local set_to
    local orig_set = Usb.setClock
    Usb.setClock = function(t) set_to = t; return true end
    local later = os.time() + 3600
    check(Usb.fixClock(later) and set_to == later + 60 and not Usb.fixClock(os.time() - 600) and not Usb.fixClock(0),
        "the Kindle's clock behind the computer's (when the page wrote the inbox): set from it; a right clock is left alone")
    Usb.setClock = orig_set
    check(Usb.summaryText(r):match("1 book") and Usb.summaryText(r):match("3 reading updates"), "the summary says what came")

    -- a GZreader update the page brought: installed before the rest comes in
    local Update = require("gzreader_update")
    local KO2 = WORK .. "/ko-usb"
    os.execute("rm -rf '" .. KO2 .. "' && mkdir -p '" .. KO2 .. "/frontend' '" .. KO2 .. "/plugins/gzreader.koplugin'")
    put(KO2 .. "/gzreader-version", "1.0.0\n"); put(KO2 .. "/frontend/old.lua", "old")
    Update.root = KO2
    PKG = { ["koreader/frontend/new.lua"] = "new", ["koreader/plugins/gzreader.koplugin/main.lua"] = "new main",
        ["koreader/gzreader-version"] = "1.2.0\n" }
    put(base .. "/in/gzreader-update.zip", "ZIPDATA")
    local ib = { format = 1, update = { version = "1.2.0", file = "in/gzreader-update.zip", size = 7 }, books = { { id = 1 } } }
    put(base .. "/inbox.json", JSON.encode(ib))
    local installed = Usb.installUpdate(fake, base, ib)
    local left = JSON.decode(read(base .. "/inbox.json") or "{}")
    check(installed and Update.currentVersion() == "1.2.0" and read(KO2 .. "/frontend/new.lua") == "new"
        and left.update == nil and left.books and not exists(base .. "/in/gzreader-update.zip"),
        "update from the computer: installed first; the rest of the inbox waits for the new GZreader")
    put(base .. "/in/gzreader-update.zip", "ZIPDATA")
    local same = { update = { version = "1.2.0", file = "in/gzreader-update.zip", size = 7 } }
    local short = { update = { version = "1.3.0", file = "in/gzreader-update.zip", size = 99 } }
    check(Usb.installUpdate(fake, base, same) == nil and same.update == nil, "…not again when it's already installed")
    put(base .. "/in/gzreader-update.zip", "ZIPDATA")
    local r2, e2 = Usb.installUpdate(fake, base, short)
    check(r2 == nil and tostring(e2):match("incomplete") and Update.currentVersion() == "1.2.0", "…nor when the file is incomplete")
    -- a test build from the page: any other than the installed one, even with a lower number
    put(base .. "/in/gzreader-update.zip", "ZIPDATA")
    local older = { update = { version = "1.1.0-beta.abc1234", file = "in/gzreader-update.zip", size = 7 } }
    check(Usb.installUpdate(fake, base, older) == nil and Update.currentVersion() == "1.2.0", "an older release from the page: not installed")
    put(base .. "/in/gzreader-update.zip", "ZIPDATA")
    local beta = { update = { version = "1.1.0-beta.abc1234", file = "in/gzreader-update.zip", size = 7, beta = true } }
    check(Usb.installUpdate(fake, base, beta) == true, "a test build from the page: installed, though its number is lower")
    check(Usb.takeTestBuilds({ test_builds = true }) and Update.betaEnabled() and not Usb.takeTestBuilds({ test_builds = true })
        and not Usb.takeTestBuilds({}) and Update.betaEnabled() and Usb.takeTestBuilds({ test_builds = false }) and not Update.betaEnabled(),
        "test builds switched on and off on the page: the Kindle's setting follows")
    Update.root = nil
    os.remove(base .. "/inbox.json")
    os.execute("rm -rf '" .. KO2 .. "' '" .. base .. "/in'")

    -- the rest of GZreader when there's no Wi-Fi
    local ran = {}
    local onUsb = Net.onUsb
    Net.onUsb = function(reason) ran.screen = reason end
    Net.usb = true
    Net.run(function() ran.copy = true end, { usb = true, reason = "Grimmory library" })
    Net.run(function() ran.quiet = true end, { quiet = true, reason = "notes" })
    Net.run(function() ran.asked = true end, { reason = "the setup page" })
    check(ran.copy and not ran.quiet and not ran.asked and ran.screen == "the setup page",
        "no Wi-Fi: the library copy answers; background work waits; asking for the network opens Sync with computer")
    local okp, Panel = pcall(require, "gzreader_panel")
    if okp then
        local icons = {}
        for _i, t in ipairs(Panel.controls(plugin)) do icons[#icons + 1] = t.icon end
        local list = table.concat(icons, ",")
        check(list:match("^usb,") and not list:match("wifi") and not list:match("updates"),
            "no Wi-Fi: the quick panel has Sync instead of Wi-Fi, no Updates (" .. list .. ")")
    end
    -- Connect to computer: GZreader quits with 86 (koreader.sh lets the Kindle share its drive)
    local UIMq = require("ui/uimanager")
    local quit_code, orig_quit = nil, UIMq.quit
    UIMq.quit = function(_um, code) quit_code = code end
    local orig_fs = UIMq.flushSettings
    UIMq.flushSettings = UIMq.flushSettings or function() end
    Usb.connect(fake)
    UIMq.quit, UIMq.flushSettings = orig_quit, orig_fs
    check(quit_code == 86, "Connect to computer: GZreader saves and steps aside (exit code 86)")
    -- no Wi-Fi: no sending the log to a phone, no remote debugging, no Wi-Fi switch
    local gen = plugin:sectionItems("general")
    local labels = {}
    for _i, it in ipairs(gen.diagnostics or {}) do labels[#labels + 1] = tostring(it.text) end
    local orig_bd = package.loaded["ui/widget/buttondialog"]
    local nbtn
    package.loaded["ui/widget/buttondialog"] = { new = function(_self, o) nbtn = #o.buttons; return o end }
    plugin:showDiagnostics()
    package.loaded["ui/widget/buttondialog"] = orig_bd
    check(gen.wifi == nil and #labels == 3 and not table.concat(labels, "|"):match("browser") and not table.concat(labels, "|"):match("Remote")
        and not table.concat(labels, "|"):match("automatically") and table.concat(labels, "|"):match("to the developer %(at the next sync%)")
        and nbtn == 3, "no Wi-Fi: Settings and Diagnostics don't offer sending the log to a phone or automatic debug reports; Send to the developer goes at the next sync (" .. table.concat(labels, ", ") .. ")")
    -- Send to the developer without Wi-Fi: the report waits in .gzsync/reports/ for the sync page (gzreader_usbreport.lua)
    do
        local Rep = require("gzreader_usbreport")
        local RemoteM = require("gzreader_remote")
        local rlfs = require("libs/libkoreader-lfs")
        local LogM = require("gzreader_log")
        local rdir = Rep.dir(plugin)
        local function rexists(p) return rlfs.attributes(p, "mode") == "file" end
        local function slurp(p) local fh = io.open(p, "rb"); local t = fh and fh:read("*a"); if fh then fh:close() end; return t end
        local n_export = 0
        local function fakeExport(into)
            n_export = n_export + 1
            local p = into .. "/gzreader-log-test-" .. n_export .. ".txt"
            local fh = io.open(p, "wb"); fh:write("exported log " .. n_export .. "\n"); fh:close()
            return p
        end
        local stamp = Rep.save(plugin, "  froze at https://books.example.com/x?password=hunter2  ", fakeExport)
        local meta = stamp and JSON.decode(slurp(rdir .. "/report-" .. stamp .. ".json") or "null") or {}
        check(stamp and slurp(rdir .. "/report-" .. stamp .. ".txt") == "exported log 1\n"
            and meta.note == "froze at https://books.example.com/x?password=<redacted>" and meta.device == RemoteM.deviceName()
            and type(meta.at) == "number" and meta.version and meta.test_build ~= nil and not rexists(rdir .. "/gzreader-log-test-1.txt"),
            "no Wi-Fi: Send to the developer saves the log and what was typed (redacted) for the sync page")
        for _i = 1, 4 do Rep.save(plugin, "", fakeExport) end
        local rsaved = Rep.saved(plugin)
        local txts = 0
        for rname in rlfs.dir(rdir) do if rname:match("^report%-.*%.txt$") then txts = txts + 1 end end
        check(#rsaved == Rep.KEEP and txts == Rep.KEEP and rsaved[1]:match("^0003%-") and rsaved[#rsaved]:match("^0005%-")
            and not rexists(rdir .. "/report-" .. stamp .. ".json"),
            "…the newest " .. Rep.KEEP .. " kept (an old Kindle's drive is small): " .. table.concat(rsaved, ", "))
        local box = Usb.outbox(plugin).report or {}
        check(box.feed == RemoteM.reportUrl() and box.device == RemoteM.deviceName() and box.test_build ~= nil,
            "the outbox tells the page the report feed and the Kindle's name, as a Wi-Fi Kindle sends them")
        local was_enabled = LogM.enabled
        LogM.enabled = true
        local latest = Rep.exportForPage(plugin, fakeExport)
        local fresh = latest and slurp(latest)
        LogM.enabled = false
        Rep.exportForPage(plugin, fakeExport)
        local gone = not rexists(rdir .. "/latest.txt")
        LogM.enabled = was_enabled
        check(latest == rdir .. "/latest.txt" and fresh and fresh:match("^exported log") and gone,
            "Sync with diagnostic logging on: a fresh log for the page's Diagnostics box; logging off: none (an old one deleted)")
        local usrc = slurp(debug.getinfo(Usb.show, "S").source:sub(2)) or ""
        check(usrc:find('Usb.writeOutbox(plugin)\n    -- (diagnostic logging on: a fresh log for the page', 1, true)
            and usrc:find('require("gzreader_usbreport").exportForPage(plugin)', 1, true),
            "the Sync window (the quick panel's Sync) exports that log when it opens")
        -- the Kindle's own Send to the developer: the box, then saved (not sent: no Wi-Fi)
        local UIM2 = require("ui/uimanager")
        local orig_show2, orig_close2, orig_rp = UIM2.show, UIM2.close, UIM2.forceRePaint
        local shown_text
        UIM2.show = function(_s, w) if w and w.text then shown_text = w.text end end
        UIM2.close = function() end
        UIM2.forceRePaint = function() end
        local orig_exp = LogM.exportTo
        LogM.exportTo = function(into) return fakeExport(into) end
        local before_n = #Rep.saved(plugin)
        local rstamp = plugin:sendLogToDeveloper("the sync page said nothing")
        LogM.exportTo = orig_exp
        UIM2.show, UIM2.close, UIM2.forceRePaint = orig_show2, orig_close2, orig_rp
        local last = Rep.saved(plugin)
        local lmeta = JSON.decode(slurp(rdir .. "/report-" .. last[#last] .. ".json") or "null") or {}
        check(rstamp and last[#last] == rstamp and #last == math.min(Rep.KEEP, before_n + 1) and lmeta.note == "the sync page said nothing"
            and tostring(shown_text):match("next sync"),
            "no Wi-Fi: Diagnostics → Send to the developer saves the report and says it goes at the next sync (" .. tostring(shown_text) .. ")")
        os.execute("rm -rf '" .. rdir .. "'")
    end
    local Notes = require("gzreader_notes")
    local err
    Notes.refresh(fake, function(_ok, e) err = e end)
    check(err == "usb" and Notes.cel({ kind = "tag", value = "a" }) == nil
        and Notes.keep({ tags = { "a" } }, { kind = "tag", value = "a" }) and not Notes.keep({ tags = {} }, { kind = "tag", value = "a" })
        and Notes.keep({ content = "Buy Milk" }, { kind = "search", value = "milk" }),
        "no Wi-Fi: notes are filtered on the Kindle and come with the sync")
    local orig_plugin = Usb.plugin
    Usb.plugin = plugin
    plugin.store.usb_queue = nil
    local before = #UI.shown
    plugin:downloadAndOpen({ id = 77, title = "Ivanhoe", primaryFileType = "EPUB" }, nil)
    check(Usb.isQueued(plugin, 77) and require("gzreader_download").isQueued(77) and #UI.shown == before + 1
        and not require("gzreader_download").active,
        "no Wi-Fi: Download puts the book in the sync queue")
    Usb.dequeue(plugin, 77)
    Net.usb, Net.onUsb, Usb.plugin = nil, onUsb, orig_plugin
    os.execute("rm -rf '" .. lib .. "'")
    os.remove(Memos.cachePath())
    os.remove(require("gzreader_caldav").cachePath())
end)()

-- The sync page's own output (sync_page_test.py ran it in a browser and left
-- the GZreader folder it wrote in GZ_SYNC_DUMP): taken in by the Kindle.
if os.getenv("GZ_SYNC_DUMP") and require("lfs").attributes(os.getenv("GZ_SYNC_DUMP") .. "/.gzsync/inbox.json", "mode") then
    print("Sync through a computer: what the page brought, taken in")
    ;(function()
        local Usb = require("gzreader_usbsync")
        local JSON = require("json")
        local lib = WORK .. "/usb-e2e"
        os.execute("rm -rf '" .. lib .. "'; mkdir -p '" .. lib .. "'; cp -r '" .. os.getenv("GZ_SYNC_DUMP") .. "/.gzsync' '" .. lib .. "/'")
        local fake = { store = { downloads = { ["1"] = { path = lib .. "/book1.epub", title = "Book 01" } }, audiobooks = {},
            pending = { progress = {
                ["1"] = { gz_seq = 7, fileProgress = { bookFileId = 1001, progressPercent = 42.5 } },
                ["999"] = { gz_seq = 3, fileProgress = { bookFileId = 1, progressPercent = 1 } },
            }, sessions = { { bookId = 1, startTime = "2026-11-05T10:00:00Z", durationSeconds = 1800 } }, ratings = { ["2"] = 4 },
                -- (books put on shelves here: the page's jobs sh:3:5 and sh:5:6)
                shelves = { ["3"] = { seq = 5, set = { ["6"] = true } }, ["5"] = { seq = 6, set = { ["7"] = true } } } },
            memos = { queue = { { id = "q1", op = "create", content = "Written on the Kindle #kindle" } } },
            usb_queue = { { id = 3, kind = "book", title = "Book 03" }, { id = 32, kind = "audiobook", title = "Book 32" } } } }
        local f = io.open(lib .. "/book1.epub", "wb"); f:write("x"); f:close()
        function fake:libraryDir() return lib end
        function fake:save() end
        function fake:saveSoon() end
        function fake:writeManifest() end
        -- (the journal the page's outbox had: two made here, one changed, one deleted)
        local jf = io.open(lib .. "/.gzsync/journal.jsonl", "wb")
        for _i, j in ipairs({ { id = "m:1", op = "bookmark+", temp = "usb-1" }, { id = "m:2", op = "highlight+", temp = "usb-2" },
                { id = "m:3", op = "highlight~", ref = "usb-2" }, { id = "m:4", op = "bookmark-", ref = "9999" },
                { id = "m:5", op = "highlight~", ref = "usb-2", body = { note = "later" } } }) do
            jf:write(JSON.encode(j), "\n")
        end
        jf:close()
        fake.store.downloads["1"].bookmarks = { ["/body/DocFragment[2]"] = "usb-1" }
        local ready = false
        Usb.SCREENSAVER_DIR = lib .. "/screensavers"
        local r = Usb.import(fake, function() ready = true end)
        local left = Usb.journal(fake)
        do
            local S = require("gzreader_shelves")
            local mine = S.mine(fake)
            local names = {}
            for _i, sh in ipairs(mine or {}) do names[#names + 1] = sh.name end
            check(next(fake.store.pending.shelves) == nil and table.concat(names, ",") == "Beach reads,Kindle"
                and S.isOn(fake, 3, 6) and S.isOn(fake, 10, 4) and not S.isOn(fake, 5, 7),
                "e2e: shelf changes sent by the page are off the queue; your shelves (not someone else's) kept from the copy, with their books")
        end
        local pf = io.open(lib .. "/screensavers/My Dog.png", "rb")
        local phead = pf and pf:read(24)
        if pf then pf:close() end
        local hf = io.open(lib .. "/screensavers/Beach.png", "rb") -- (made on the page from a HEIC photo)
        local hhead = hf and hf:read(24)
        if hf then hf:close() end
        check(r.pictures == 2 and phead and phead:sub(2, 4) == "PNG" and hhead and hhead:sub(2, 4) == "PNG"
            and G_reader_settings:readSetting("screensaver_type") == "random_image"
            and G_reader_settings:readSetting("gzreader_sleep_auto") == false and G_reader_settings:readSetting("screensaver_dir") == lib .. "/screensavers"
            and Usb.sleepMode() == "always" and #Usb.screensavers() == 2 and Usb.summaryText(r):match("2 sleep screen pictures"),
            "e2e: the sleep screen pictures (one from a HEIC photo) in the screensavers folder; pictures always, as chosen on the page")
        G_reader_settings:saveSetting("gzreader_sleep_auto", nil); G_reader_settings:saveSetting("screensaver_type", nil)
        G_reader_settings:saveSetting("screensaver_dir", nil)
        Usb.SCREENSAVER_DIR = nil
        check(r.marks == 4 and #left == 1 and left[1].id == "m:5" and left[1].ref ~= "usb-2" and tonumber(left[1].ref)
            and fake.store.downloads["1"].bookmarks["/body/DocFragment[2]"] ~= "usb-1" and fake.store.usb_idmap["usb-2"],
            "e2e: the journal's sent lines gone, the rest now refer to Grimmory's ids, as does the Kindle")
        local api2 = require("gzreader_offlineapi"):new(fake.store, nil, lib .. "/.gzsync")
        require("gzreader_offlineapi").forget()
        local anns = api2:listAnnotations(1) or {}
        check(#anns == 1 and anns[1].note == "later" and anns[1].color == "#F87171",
            "e2e: highlights as GZreader sees them: Grimmory's (from the copy) with the journal's change on top")
        check(r and r.sent == 5 and next(fake.store.pending.progress) == nil and #fake.store.pending.sessions == 0
            and next(fake.store.pending.ratings) == nil, "e2e: what the page sent is off the Kindle's lists (the gone book's position dropped)")
        local b = fake.store.downloads["3"]
        check(b and b.path == lib .. "/book3.epub" and b.subtitle == "Old School" and #fake.store.usb_queue == 0,
            "e2e: the book is in the GZreader folder, the queue empty")
        check(b and b.grimmory_progress and b.grimmory_progress.epubProgress.percentage == 30
            and fake.store.audiobooks["32"].grimmory_progress.audiobookProgress.positionMs == 50000,
            "e2e: Grimmory's places kept for the first opening")
        local gst = fake.store.grimmory_stats
        check(r.stats and gst and gst.values.year_finished == 3 and (gst.values.week_time or 0) >= 1800 and gst.values.reading_days >= 1,
            "e2e: Home's Grimmory reading stats, from the page")
        check(runLoop(function() return ready end, 60), "e2e: audiobooks and music prepared (AAC converted on the Kindle)")
        local ab = require("gzreader_audiobook").load(fake, "32")
        check(ab and #ab.files == 2 and ab.files[1] == "track-001.mp3" and ab.chapters[2].title == "Story",
            "e2e: the folder audiobook plays from its two tracks")
        local pab = require("gzreader_audiobook").load(fake, "plex-206")
        check(pab and pab.plex and pab.plex.key == "206" and #pab.files == 2 and pab.files[2] == "track-002.mp3" and pab.tracks[2].plex_key == "307"
            and pab.tracks[2].start == 3000 and pab.description == "A book in two parts." and fake.store.audiobooks["plex-206"].title == "Two Part Book",
            "e2e: a Plex audiobook the page brought: its tracks, and where its place goes in Plex")
        local ab33 = require("gzreader_audiobook").load(fake, "33")
        local d33 = ab33 and require("gzreader_audiobook").dir(fake, "33")
        local lfs = require("libs/libkoreader-lfs")
        check(ab33 and ab33.tracks[1].chunks and #ab33.tracks[1].chunks.starts >= 1 and ab33.files[1]:match("^audiobook%.m4b%.chunks/c0%.aac$")
            and lfs.attributes(d33 .. "/audiobook.m4b.chunks/c0.aac", "mode") == "file" and not lfs.attributes(d33 .. "/audiobook.m4b"),
            "e2e: the M4B audiobook the page prepared plays from its chunks (nothing to convert on the Kindle)")
        local Music = require("gzreader_music")
        local mp3 = Music.load(Music.dirFor(fake, "album", "201"))
        local aac = Music.load(Music.dirFor(fake, "album", "202"))
        local flac = Music.load(Music.dirFor(fake, "album", "203"))
        check(mp3 and mp3.have == 2 and aac and aac.have == 1 and aac.tracks[1].chunks and flac and flac.have == 1,
            "e2e: the three albums play (MP3, AAC made into chunks, FLAC as MP3)")
        check(fake.store.plex and fake.store.plex.bitrate == 192 and fake.store.plex.shrink == true,
            "e2e: the music quality chosen on the page, in the Kindle's Plex settings")
        check(r.notes and r.notes >= 3 and #fake.store.memos.queue == 0, "e2e: notes in, the Kindle's note sent")
        check(r.events == 2 and #fake.store.calendar_feeds == 2, "e2e: the calendar's events, the failed one kept by name")
        local api = require("gzreader_offlineapi"):new(fake.store, nil, lib .. "/.gzsync")
        require("gzreader_offlineapi").forget()
        local thumb = WORK .. "/e2e-thumb.jpg"
        check(api:isPaired() and api:listBooks{ fileType = api.READABLE_TYPES }.totalElements == 32 and api:listShelves()[1]
            and api:listBooks{ shelfId = 4 }.totalElements == 3 and api:getBook(1).epubProgress.percentage == 42.5
            and api:getBookDetail(32).description and api:downloadThumbnail(5, thumb),
            "e2e: the Grimmory tab browses the page's copy: books, shelves, places, pages, covers")
        os.execute("rm -rf '" .. lib .. "'")
        os.remove(require("gzreader_memos").cachePath())
        os.remove(require("gzreader_caldav").cachePath())
    end)()
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
