--[[--
GZreader updates from GitHub releases (replaces ZenOS's own updater, which
would install upstream ZenOS over this build).

Source: https://github.com/9retirement6irk/GZreader/releases
  * the latest release's tag is the version (v1.2.0);
  * its asset "gzreader-update.zip" holds a "koreader/" folder with only the
    parts GZreader changes: frontend/, the kept plugins, reader.lua,
    koreader.sh, gzreader-version (the native binaries, fonts and dictionary
    stay as installed);
  * no hashing on the Kindle: the download comes over HTTPS straight from
    GitHub (which protects it in transit), its size must match the size
    GitHub lists for the asset, and the zip must open and contain a
    complete GZreader layout before anything is replaced.

Installing never touches settings/, the books, their .sdr folders, history or
the Grimmory folder. Each replaced folder is renamed aside first and put back
if anything fails, then GZreader restarts.
]]

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local JSON = require("json")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Log = require("grimmory_log")
local _ = require("gettext")
local T = ffiutil.template

local Update = {
    REPO = "9retirement6irk/GZreader",
    ASSET = "gzreader-update.zip",
    CHECK_EVERY = 24 * 3600,
    state = { has_update = false },
    -- injectable for tests
    request = nil,      -- function(url, sink_or_nil) -> code, body_or_nil, headers
    root = nil,         -- koreader dir (default: current dir)
}

local function root() return Update.root or (lfs.currentdir() or ".") end

function Update.apiUrl()
    return "https://api.github.com/repos/" .. Update.REPO .. "/releases/latest"
end

function Update.pageUrl()
    return "https://github.com/" .. Update.REPO .. "/releases"
end

function Update.currentVersion()
    local f = io.open(root() .. "/gzreader-version", "rb")
    local v = f and f:read("*l")
    if f then f:close() end
    return (v and v:match("^%s*v?([%w%.%-]+)")) or "0.0.0"
end

--- -1, 0, 1 comparing dotted versions ("1.10.0" > "1.9.2"; "1.0.0-beta1" < "1.0.0").
function Update.compare(a, b)
    local function parts(v)
        local base, pre = tostring(v):gsub("^v", ""):match("^([%d%.]+)(.*)$")
        local t = {}
        for n in (base or "0"):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t, pre or ""
    end
    local pa, prea = parts(a)
    local pb, preb = parts(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    if prea == preb then return 0 end
    if prea == "" then return 1 end
    if preb == "" then return -1 end
    return prea < preb and -1 or 1
end

---------------------------------------------------------------- HTTP

local TRUSTED = {
    ["api.github.com"] = true, ["github.com"] = true,
    ["objects.githubusercontent.com"] = true,
    ["release-assets.githubusercontent.com"] = true,
    ["github-releases.githubusercontent.com"] = true,
}

local function host(u) return tostring(u):match("^https://([^/:]+)") end

--- GET following redirects (only to GitHub's hosts, only https).
--- With `path`, the body is written there. Returns code, body, err.
function Update.get(u, path)
    if Update.request then return Update.request(u, path) end
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socket = require("socket")
    local socketutil = require("socketutil")
    for _hop = 1, 6 do
        if not TRUSTED[host(u) or ""] then return nil, nil, "untrusted host: " .. tostring(host(u)) end
        local chunks = {}
        local sink
        if path then
            local fh = io.open(path, "wb")
            if not fh then return nil, nil, "cannot write " .. path end
            sink = ltn12.sink.file(fh)
        else
            sink = socketutil.table_sink(chunks)
        end
        socketutil:set_timeout(path and 30 or 10, path and -1 or 30)
        local ok, code, headers = pcall(function()
            return socket.skip(1, http.request{
                url = u, method = "GET", sink = sink, redirect = false,
                headers = { ["User-Agent"] = "GZreader", ["Accept"] = path and "application/octet-stream" or "application/vnd.github+json" },
            })
        end)
        socketutil:reset_timeout()
        if not ok then return nil, nil, tostring(code) end
        if type(code) ~= "number" then return nil, nil, tostring(code) end
        if code >= 300 and code < 400 and headers and headers.location then
            u = headers.location
            if path then os.remove(path) end
        else
            return code, not path and table.concat(chunks) or nil
        end
    end
    return nil, nil, "too many redirects"
end

---------------------------------------------------------------- check

--- Parse a GitHub "latest release" JSON body into { version, url, size, notes, page }.
function Update.parseRelease(body)
    local ok, rel = pcall(JSON.decode, body or "")
    if not ok or type(rel) ~= "table" or type(rel.tag_name) ~= "string" then return nil, "bad release data" end
    local info = { version = rel.tag_name:gsub("^v", ""), notes = type(rel.body) == "string" and rel.body or "",
        page = rel.html_url }
    for _i, a in ipairs(type(rel.assets) == "table" and rel.assets or {}) do
        if a.name == Update.ASSET and type(a.browser_download_url) == "string" then
            info.url = a.browser_download_url
            info.size = tonumber(a.size)
        end
    end
    if not info.url then return nil, "release " .. rel.tag_name .. " has no " .. Update.ASSET end
    return info
end

--- Blocking check (a few seconds). Returns info or nil, err; updates state.
function Update.check()
    local code, body, err = Update.get(Update.apiUrl())
    Log.info("update check", Update.apiUrl(), tostring(code or err))
    if code == 404 then return nil, _("No GZreader release has been published yet.") end
    if code ~= 200 then return nil, err or ("HTTP " .. tostring(code)) end
    local info, perr = Update.parseRelease(body)
    if not info then return nil, perr end
    Update.state = { has_update = Update.compare(info.version, Update.currentVersion()) > 0,
        latest = info.version, info = info }
    G_reader_settings:saveSetting("gzreader_update_last_check", os.time())
    G_reader_settings:saveSetting("gzreader_update_latest", info.version)
    return info
end

function Update.autoCheckEnabled() return G_reader_settings:nilOrTrue("gzreader_update_auto") end

--- Once a day, when online, check quietly in a subprocess. on_found(info).
function Update.backgroundCheck(on_found)
    if not Update.autoCheckEnabled() then return end
    local last = G_reader_settings:readSetting("gzreader_update_last_check") or 0
    if os.time() - last < Update.CHECK_EVERY and os.time() >= last then
        local latest = G_reader_settings:readSetting("gzreader_update_latest")
        if latest and Update.compare(latest, Update.currentVersion()) > 0 then
            Update.state = { has_update = true, latest = latest }
        end
        return
    end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        local code, body = Update.get(Update.apiUrl())
        ffiutil.writeToFD(wfd, code == 200 and body or "", true)
    end, true)
    if not pid then return end
    local tries = 0
    local function poll()
        tries = tries + 1
        if ffiutil.isSubProcessDone(pid) then
            local body = ffiutil.readAllFromFD(fd)
            local info = body ~= "" and Update.parseRelease(body)
            G_reader_settings:saveSetting("gzreader_update_last_check", os.time())
            if info then
                G_reader_settings:saveSetting("gzreader_update_latest", info.version)
                Update.state = { has_update = Update.compare(info.version, Update.currentVersion()) > 0,
                    latest = info.version, info = info }
                Log.info("update background check: latest", info.version, "installed", Update.currentVersion())
                if Update.state.has_update and on_found then on_found(info) end
            end
            return
        end
        if tries > 60 then ffiutil.terminateSubProcess(pid); return end
        UIManager:scheduleIn(1, poll)
    end
    UIManager:scheduleIn(1, poll)
end

---------------------------------------------------------------- install

local function exists(p) return lfs.attributes(p, "mode") ~= nil end
local function isDir(p) return lfs.attributes(p, "mode") == "directory" end

local function rmTree(p)
    if lfs.attributes(p, "mode") == "directory" then
        for e in lfs.dir(p) do
            if e ~= "." and e ~= ".." then rmTree(p .. "/" .. e) end
        end
        lfs.rmdir(p)
    else
        os.remove(p)
    end
end

--- Things an update may replace, relative to koreader/. Anything else in
--- the package is ignored (settings, books, history are never in it).
local function allowed(rel)
    return rel == "frontend" or rel == "reader.lua" or rel == "koreader.sh" or rel == "gzreader-version"
        or rel == "git-rev" or rel:match("^plugins/[%w_%-]+%.koplugin$") ~= nil
end

--- Unpack `zip` and swap its parts into the koreader folder.
--- Returns true or nil, err (the installation is unchanged on failure).
function Update.apply(zip)
    local Archiver = require("ffi/archiver")
    local base = root()
    local stage = base .. "/.gzreader-update"
    rmTree(stage)
    lfs.mkdir(stage)
    local reader = Archiver.Reader:new()
    if not reader:open(zip) then return nil, "cannot open update package" end
    local n = 0
    for entry in reader:iterate() do
        local p = entry.path
        if p:find("%.%.") or p:sub(1, 1) == "/" then reader:close(); rmTree(stage); return nil, "unsafe path in package: " .. p end
        if entry.mode == "file" then
            if not reader:extractToPath(p, stage .. "/" .. p) then
                reader:close(); rmTree(stage); return nil, "could not unpack " .. p
            end
            n = n + 1
        end
    end
    reader:close()
    local src = stage .. "/koreader"
    if n == 0 or not isDir(src .. "/frontend") or not exists(src .. "/plugins/grimmory.koplugin/main.lua")
            or not exists(src .. "/gzreader-version") then
        rmTree(stage)
        return nil, "the package doesn't look like a GZreader update"
    end
    -- Work out what to replace.
    local items = {}
    for e in lfs.dir(src) do
        if e ~= "." and e ~= ".." and e ~= "plugins" and allowed(e) then items[#items + 1] = e end
    end
    if isDir(src .. "/plugins") then
        for e in lfs.dir(src .. "/plugins") do
            if allowed("plugins/" .. e) then items[#items + 1] = "plugins/" .. e end
        end
    end
    -- Swap: current -> .old, new -> current. Roll back on any failure.
    local done = {}
    local function rollback()
        for i = #done, 1, -1 do
            local rel = done[i]
            rmTree(base .. "/" .. rel)
            if exists(base .. "/" .. rel .. ".gz-old") then os.rename(base .. "/" .. rel .. ".gz-old", base .. "/" .. rel) end
        end
    end
    for _i, rel in ipairs(items) do
        local cur, old = base .. "/" .. rel, base .. "/" .. rel .. ".gz-old"
        rmTree(old)
        if exists(cur) and not os.rename(cur, old) then rollback(); rmTree(stage); return nil, "could not move " .. rel end
        if not os.rename(src .. "/" .. rel, cur) then
            if exists(old) then os.rename(old, cur) end
            rollback(); rmTree(stage)
            return nil, "could not install " .. rel
        end
        done[#done + 1] = rel
    end
    for _i, rel in ipairs(done) do rmTree(base .. "/" .. rel .. ".gz-old") end
    rmTree(stage)
    Log.info("update installed", Update.currentVersion(), "items", #done)
    return true
end

--- Full flow from the menu: check, confirm, download (background), install, restart.
function Update.run()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local busy = InfoMessage:new{ text = _("Checking for GZreader updates…"), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local info, err = Update.check()
        UIManager:close(busy)
        if not info then
            UIManager:show(InfoMessage:new{ text = T(_("Couldn't check for updates:\n%1"), tostring(err)) })
            return
        end
        if Update.compare(info.version, Update.currentVersion()) <= 0 then
            UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 is up to date."), Update.currentVersion()), timeout = 4 })
            return
        end
        local notes = info.notes ~= "" and ("\n\n" .. info.notes:sub(1, 600)) or ""
        UIManager:show(ConfirmBox:new{
            text = T(_("GZreader %1 is available (installed: %2).%3\n\nYour settings, books and reading progress are kept."),
                info.version, Update.currentVersion(), notes),
            ok_text = _("Update"),
            ok_callback = function() Update.download(info) end,
        })
    end)
end

function Update.download(info)
    local ProgressbarDialog = require("ui/widget/progressbardialog")
    local zip = DataStorage:getDataDir() .. "/cache/gzreader-update.zip"
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    os.remove(zip)
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        local code, _, err = Update.get(info.url, zip)
        ffiutil.writeToFD(wfd, code == 200 and "ok" or ("err " .. tostring(code or err)), true)
    end, true)
    if not pid then return UIManager:show(InfoMessage:new{ text = _("Couldn't start the download.") }) end
    local dialog = ProgressbarDialog:new{
        title = T(_("Downloading GZreader %1…"), info.version),
        progress_max = info.size or 1, refresh_time_seconds = 2,
    }
    dialog:show()
    local function poll()
        local size = lfs.attributes(zip, "size") or 0
        if info.size then dialog:reportProgress(size) end
        if not ffiutil.isSubProcessDone(pid) then return UIManager:scheduleIn(1, poll) end
        UIManager:close(dialog)
        local res = ffiutil.readAllFromFD(fd)
        if res ~= "ok" then
            os.remove(zip)
            return UIManager:show(InfoMessage:new{ text = T(_("Download failed: %1"), res) })
        end
        local final_size = lfs.attributes(zip, "size") or 0
        if info.size and final_size ~= info.size then
            os.remove(zip)
            Log.warn("update download size", final_size, "expected", info.size)
            return UIManager:show(InfoMessage:new{ text = _("The download was incomplete. Try again.") })
        end
        local busy = InfoMessage:new{ text = _("Installing…"), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local ok, err = Update.apply(zip)
        os.remove(zip)
        UIManager:close(busy)
        if not ok then
            Log.err("update failed:", err)
            return UIManager:show(InfoMessage:new{ text = T(_("Update failed, nothing was changed:\n%1"), tostring(err)) })
        end
        Update.state = { has_update = false, latest = info.version }
        UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 installed. Restarting…"), info.version), timeout = 2 })
        UIManager:scheduleIn(2, function() UIManager:restartKOReader() end)
    end
    UIManager:scheduleIn(1, poll)
end

--- Menu items (used for ZenOS's Settings → Updates section and the Grimmory menu).
function Update.menuItems()
    return {
        {
            text_func = function()
                if Update.state.has_update and Update.state.latest then
                    return T(_("Update available: GZreader %1"), Update.state.latest)
                end
                return T(_("Check for updates (installed %1)"), Update.currentVersion())
            end,
            keep_menu_open = true,
            callback = function() Update.run() end,
        },
        {
            text = _("Check automatically once a day"),
            checked_func = function() return Update.autoCheckEnabled() end,
            callback = function() G_reader_settings:flipNilOrTrue("gzreader_update_auto") end,
        },
        {
            text = T(_("Update source: %1"), "github.com/" .. Update.REPO),
            enabled = false,
        },
    }
end

return Update
