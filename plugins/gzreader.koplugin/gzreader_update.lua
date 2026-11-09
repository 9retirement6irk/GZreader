--[[--
GZreader updates from GitHub releases (replaces ZenOS's own updater, which
would install upstream ZenOS over this build).

Source: https://github.com/9retirement6irk/GZreader/releases
  * the latest release's tag is the version (v1.2.0, also "v.1.2.0");
  * if the release has an asset "gzreader-update.zip" (attached by the
    repository's release workflow), it is used: a "koreader/" folder with
    only the parts GZreader changes (frontend/, the kept plugins,
    reader.lua, koreader.sh, gzreader-version);
  * otherwise the release's own source code zip (which GitHub makes for
    every release, nothing to upload) is used: only frontend/, reader.lua,
    platform/kindle/koreader.sh and the plugins already installed are
    taken from it. The native binaries, fonts and dictionary stay as
    installed either way;
  * test builds (Settings → Updates → Test builds, off by default): the
    updater reads latest-beta.json on the repository's "updates" branch
    instead (raw.githubusercontent.com; the release's latest.json is there
    too, for the sync page), which the "GZreader test builds
    (beta)" workflow writes from every push to the "beta" branch: the same
    kind of update package, version <version>-beta.<commit>. Any test build
    other than the one installed is offered. Switched off, the next release
    is offered as usual (1.2.0 is newer than 1.2.0-beta.7);
  * no hashing on the Kindle: the download comes over HTTPS straight from
    GitHub (which protects it in transit), its size must match the size
    GitHub lists for the asset, and the zip must open and contain a
    complete GZreader layout before anything is replaced.

On a Nook (GZreader in /data/gzreader: koreader/ next to the start script
gzreader.sh) the same update is installed, and the package's copy of the
Nook's scripts then replace theirs next to koreader/: the start script
(koreader/nook-gzreader.sh → gzreader.sh) and the icon's helper
(koreader/nook-launcher.sh → launcher.sh), each by a rename: a running
script keeps reading its old copy; the new one runs from the next start
(the helper: from the Nook's next restart).

Installing never touches settings/, the books, their .sdr folders, history or
the GZreader folder. Each replaced folder is renamed aside first and put back
if anything fails, then GZreader restarts.
]]

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local JSON = require("gzreader_json")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local Log = require("gzreader_log")
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

Update.BETA_BRANCH = "updates"

--- Test builds instead of releases (Settings → Updates → Test builds).
function Update.betaEnabled() return G_reader_settings:isTrue("gzreader_update_beta") end

--- A file on the updates branch, as it is at commit `ref` (default: the
--- branch as it is now).
function Update.betaUrl(file, ref)
    return "https://raw.githubusercontent.com/" .. Update.REPO .. "/" .. (ref or Update.BETA_BRANCH) .. "/" .. (file or "latest-beta.json")
end

--- Where to look: the latest release, or the latest test build.
function Update.feedUrl() return Update.betaEnabled() and Update.betaUrl() or Update.apiUrl() end

--- The updates branch's commit now, or the branch's name if GitHub doesn't
--- say. raw.githubusercontent.com keeps each file of a branch for up to
--- 5 minutes, each on its own: right after a new test build, latest-beta.json
--- could still be the last build's while the zip was already the new one
--- ("the download was incomplete"). A commit's files never change, so the
--- test build's data and its zip are read at the same commit.
function Update.betaRef()
    local code, body = Update.get("https://api.github.com/repos/" .. Update.REPO .. "/commits/" .. Update.BETA_BRANCH,
        nil, "application/vnd.github.sha")
    if code == 200 and type(body) == "string" then
        local sha = body:match("^%s*(%x+)%s*$")
        if not sha then
            local ok, j = pcall(JSON.decode, body)
            sha = ok and type(j) == "table" and type(j.sha) == "string" and j.sha:match("^%x+$") or nil
        end
        if sha and #sha == 40 then return sha end
    end
    return Update.BETA_BRANCH
end

--- Fetch the feed: returns code, body, err, the url asked and (test builds)
--- the commit it was read at.
function Update.fetchFeed()
    if not Update.betaEnabled() then
        local u = Update.apiUrl()
        local code, body, err = Update.get(u)
        return code, body, err, u
    end
    local ref = Update.betaRef()
    local u = Update.betaUrl(nil, ref)
    local code, body, err = Update.get(u)
    return code, body, err, u, ref
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
    ["codeload.github.com"] = true, -- source code zips
    ["raw.githubusercontent.com"] = true, -- test builds (the updates branch)
}

local function host(u) return tostring(u):match("^https://([^/:]+)") end

--- GET following redirects (only to GitHub's hosts, only https).
--- With `path`, the body is written there. Returns code, body, err.
function Update.get(u, path, accept)
    if Update.request then return Update.request(u, path, accept) end
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
                -- downloads accept anything: GitHub's API answers 415 to
                -- "application/octet-stream" for a release's source code zip
                headers = { ["User-Agent"] = "GZreader", ["Accept"] = accept or (path and "*/*" or "application/vnd.github+json") },
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
    local version = rel.tag_name:gsub("^[vV]%.?", "")
    local info = { version = version, tag = rel.tag_name, notes = type(rel.body) == "string" and rel.body or "",
        page = rel.html_url }
    for _i, a in ipairs(type(rel.assets) == "table" and rel.assets or {}) do
        if a.name == Update.ASSET and type(a.browser_download_url) == "string" then
            info.url = a.browser_download_url
            info.size = tonumber(a.size)
        end
    end
    if not info.url and type(rel.zipball_url) == "string" then
        -- no update package attached: GitHub's source code zip of the release
        info.url = rel.zipball_url
        info.source = true
    end
    if not info.url then return nil, "release " .. rel.tag_name .. " has nothing to download" end
    return info
end

--- Parse the updates branch's latest-beta.json into the same info.
function Update.parseBeta(body, ref)
    local ok, b = pcall(JSON.decode, body or "")
    if not ok or type(b) ~= "table" or type(b.version) ~= "string" or type(b.file) ~= "string"
            or not b.file:match("^[%w%._%-]+$") then
        return nil, "bad test build data"
    end
    local commit = type(b.commit) == "string" and b.commit:match("^%x+$") or nil
    return { version = b.version, url = Update.betaUrl(b.file, ref), size = tonumber(b.size), beta = true,
        notes = type(b.notes) == "string" and b.notes or "",
        page = commit and ("https://github.com/" .. Update.REPO .. "/commit/" .. commit) or nil }
end

--- The feed's body (a release's JSON, or the test build's latest-beta.json).
function Update.parseFeed(body, ref)
    if Update.betaEnabled() then return Update.parseBeta(body, ref) end
    return Update.parseRelease(body)
end

--- Whether `info` should be offered: a newer release; any other test build.
function Update.isNewer(info)
    if not info or not info.version then return false end
    if info.beta then return info.version ~= Update.currentVersion() end
    return Update.compare(info.version, Update.currentVersion()) > 0
end

--- Blocking check (a few seconds). Returns info or nil, err; updates state.
function Update.check()
    local code, body, err, feed, ref = Update.fetchFeed()
    Log.info("update check", feed, tostring(code or err))
    if code == 404 then
        return nil, Update.betaEnabled() and _("No test build has been published yet.") or _("No GZreader release has been published yet.")
    end
    if code ~= 200 then return nil, err or ("HTTP " .. tostring(code)) end
    local info, perr = Update.parseFeed(body, ref)
    if not info then return nil, perr end
    Update.state = { has_update = Update.isNewer(info), latest = info.version, info = info }
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
        if latest and Update.isNewer({ version = latest, beta = Update.betaEnabled() }) then
            Update.state = { has_update = true, latest = latest }
        end
        return
    end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        require("gzreader_async").lowerPriority(require("gzreader_async").NICE) -- (page turns first)
        local code, body, _, _, ref = Update.fetchFeed()
        -- (the commit it was read at on the first line)
        ffiutil.writeToFD(wfd, code == 200 and ((ref or "") .. "\n" .. body) or "", true)
    end, true)
    if not pid then return end
    local tries = 0
    local out = require("gzreader_async").reader(fd) -- (GitHub's release JSON can be over a pipe's 64 KB)
    local function poll()
        tries = tries + 1
        out:drain()
        if ffiutil.isSubProcessDone(pid) then
            local ref, body = (out:finish() or ""):match("^([^\n]*)\n(.*)$")
            local info = body and body ~= "" and Update.parseFeed(body, ref ~= "" and ref or nil)
            G_reader_settings:saveSetting("gzreader_update_last_check", os.time())
            if info then
                G_reader_settings:saveSetting("gzreader_update_latest", info.version)
                Update.state = { has_update = Update.isNewer(info), latest = info.version, info = info }
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

--- Copy a file or a folder (and what's in it) to `dest`. Returns true or nil.
local function copyTree(from, dest)
    local mode = lfs.attributes(from, "mode")
    if mode == "directory" then
        if not isDir(dest) and not lfs.mkdir(dest) then return nil end
        for e in lfs.dir(from) do
            if e ~= "." and e ~= ".." and not copyTree(from .. "/" .. e, dest .. "/" .. e) then return nil end
        end
        return true
    end
    local inf = io.open(from, "rb")
    if not inf then return nil end
    local out = io.open(dest, "wb")
    if not out then inf:close(); return nil end
    local ok = true
    while true do
        local chunk = inf:read(65536)
        if not chunk then break end
        if not out:write(chunk) then ok = false; break end
    end
    inf:close()
    if not out:close() then ok = false end
    return ok or nil
end
Update.copyTree = copyTree

--- Write `data` to `path`, making its folders. Returns true or nil.
function Update.writeFile(path, data)
    local dir = path:match("^(.*)/[^/]*$")
    if dir and not isDir(dir) then
        local at = ""
        for part in dir:gmatch("[^/]+") do
            at = at .. "/" .. part
            if not isDir(at) then lfs.mkdir(at) end
        end
        if dir:sub(1, 1) ~= "/" then return nil end
    end
    local f = io.open(path, "wb")
    if not f then return nil end
    local ok = f:write(data)
    return (f:close() and ok) and true or nil
end

--- Bytes free for us on the disk that holds `path` (nil: can't tell); a
--- test replaces it.
function Update.freeSpace(path)
    local ok, free = pcall(function()
        local ffi = require("ffi")
        require("ffi/posix_h")
        local st = ffi.new("struct statvfs")
        if ffi.C.statvfs(path, st) ~= 0 then return nil end
        return tonumber(st.f_bavail) * tonumber(st.f_bsize)
    end)
    return ok and free or nil
end

--- The disk a path is on; a test replaces it.
function Update.devOf(p) return lfs.attributes(p, "dev") end

--- The Nook's card (the start script says where), or nil; a test replaces it.
function Update.cardDir() return os.getenv("GZ_NOOK_HOME") end

--- Where an update is downloaded and unpacked: next to GZreader, or, when
--- that disk hasn't room for it (the Nook 1st Edition: GZreader shares a
--- 242 MB disk with Android, and it can be full), on the Nook's card.
--- `need`: bytes (the download and what it unpacks to). Returns the folder
--- and whether it's elsewhere (another disk: installed by copying).
function Update.workDir(need)
    local base = root()
    local here = base .. "/.gzreader-update"
    local free = Update.freeSpace(base)
    if not free or free >= need then return here, false end
    local card = Update.cardDir()
    if card and card ~= "" and isDir(card) then
        local cfree = Update.freeSpace(card)
        if not cfree or cfree >= need then
            lfs.mkdir(card .. "/GZreader")
            Log.info("update: not enough room next to GZreader (" .. math.floor(free / 1048576) .. " MB free), using the card")
            return card .. "/GZreader/.gzreader-update", true
        end
    end
    return here, false -- (try anyway: it says what failed)
end

--- The Nook's scripts in an update, and where they go next to koreader/.
local NOOK_SCRIPTS = { ["nook-gzreader.sh"] = "gzreader.sh", ["nook-launcher.sh"] = "launcher.sh" }
local NOOK_SCRIPT = "nook-gzreader.sh" -- (the start script: a Nook install has it)

--- The Nook's start script next to koreader/ (nil: not a Nook install).
local function nookScript(base)
    local p = base .. "/../gzreader.sh"
    return lfs.attributes(p, "mode") == "file" and p or nil
end

--- Things an update may replace, relative to koreader/. Anything else in
--- the package is ignored (settings, books, history are never in it).
local function allowed(rel)
    return rel == "frontend" or rel == "reader.lua" or rel == "koreader.sh" or rel == "gzreader-version" or NOOK_SCRIPTS[rel] ~= nil
        or rel == "git-rev" or rel:match("^plugins/[%w_%-]+%.koplugin$") ~= nil
end

--- For a source code zip: where (relative to koreader/) a file of the
--- repository goes, or nil to skip it. `rel` has the zip's top folder removed.
local function sourceTarget(rel, base)
    if rel == "reader.lua" then return "reader.lua" end
    if rel == "platform/kindle/koreader.sh" then return "koreader.sh" end
    if rel == "platform/nook/gzreader.sh" then return NOOK_SCRIPT end
    if rel == "platform/nook/launcher.sh" then return "nook-launcher.sh" end
    if rel:match("^frontend/") then return rel end
    local plugin, rest = rel:match("^plugins/([%w_%-]+%.koplugin)/(.+)$")
    if plugin and isDir(base .. "/plugins/" .. plugin) then -- only plugins this install has
        if plugin == "zenos.koplugin" and rest:match("^locales/.+%.po$") and not rest:match("/en%.po$") then
            return nil -- English only, like the full package
        end
        return "plugins/" .. plugin .. "/" .. rest
    end
    return nil
end

--- Unpack `zip` and swap its parts into the koreader folder.
--- opts.source: the zip is GitHub's source code zip (opts.version is then
--- written as the installed version). Returns true or nil, err (the
--- installation is unchanged on failure).
function Update.apply(zip, opts)
    opts = opts or {}
    local Archiver = require("ffi/archiver")
    local base = root()
    -- (opts.stage: on another disk, the Nook's card when GZreader's is full)
    local stage = opts.stage or (base .. "/.gzreader-update")
    local elsewhere = opts.stage ~= nil
    rmTree(stage)
    lfs.mkdir(stage)
    local reader = Archiver.Reader:new()
    if not reader:open(zip) then return nil, "cannot open update package" end
    local n = 0
    for entry in reader:iterate() do
        local p = entry.path
        if p:find("%.%.") or p:sub(1, 1) == "/" then reader:close(); rmTree(stage); return nil, "unsafe path in package: " .. p end
        if entry.mode == "file" then
            local dest = p
            if opts.source then
                local target = sourceTarget(p:match("^[^/]+/(.+)$") or "", base)
                dest = target and ("koreader/" .. target)
            end
            if dest then
                local okx
                if elsewhere then
                    -- (the card is FAT: libarchive's own writing fails there
                    -- setting owners and modes; the bytes are written here)
                    local data = reader:extractToMemory(p)
                    okx = data and Update.writeFile(stage .. "/" .. dest, data)
                else
                    okx = reader:extractToPath(p, stage .. "/" .. dest)
                end
                if not okx then
                    reader:close(); rmTree(stage); return nil, "could not unpack " .. p
                end
                n = n + 1
            end
        end
    end
    reader:close()
    local src = stage .. "/koreader"
    if opts.source and opts.version and isDir(src) then
        local vf = io.open(src .. "/gzreader-version", "wb")
        if vf then vf:write(opts.version, "\n"); vf:close() end
        -- the source zip has no git-rev: keep KOReader's version label current
        -- (About, crash.log) as "<base>-gzreader-<version>"
        local cur = io.open(root() .. "/git-rev", "rb")
        local rev_base = cur and (cur:read("*l") or ""):match("^(.-)%-gzreader%-") or nil
        if cur then cur:close() end
        if rev_base and rev_base ~= "" then
            local gf = io.open(src .. "/git-rev", "wb")
            if gf then gf:write(rev_base, "-gzreader-", opts.version, "\n"); gf:close() end
        end
    end
    if n == 0 or not isDir(src .. "/frontend") or not exists(src .. "/plugins/gzreader.koplugin/main.lua")
            or not exists(src .. "/gzreader-version") then
        rmTree(stage)
        return nil, "the package doesn't look like a GZreader update"
    end
    -- Work out what to replace.
    local items = {}
    local nook = nookScript(base)
    for e in lfs.dir(src) do
        if e ~= "." and e ~= ".." and e ~= "plugins" and allowed(e) and (not NOOK_SCRIPTS[e] or nook) then
            items[#items + 1] = e
        end
    end
    if isDir(src .. "/plugins") then
        for e in lfs.dir(src .. "/plugins") do
            if allowed("plugins/" .. e) then items[#items + 1] = "plugins/" .. e end
        end
    end
    -- Swap each part. Next to it on the same disk: current -> .gz-old, new ->
    -- current (renamed). Elsewhere (the update unpacked on the Nook's card,
    -- or a part that lives on the card: the Nook's start script mounts it
    -- into koreader/): the current part copied aside (to put back), taken
    -- out, the new one copied in; never more than one part's difference in
    -- room needed. Any failure puts every part back.
    local keep = stage .. "/kept"
    local devOf = Update.devOf
    local function parentOf(p) return p:match("^(.*)/[^/]+$") end
    local function byCopy(cur)
        if elsewhere then return true end
        local at = exists(cur) and cur or parentOf(cur)
        local d = devOf(at)
        if d ~= devOf(src) then return true end
        return exists(cur) and d ~= devOf(parentOf(cur)) -- (a mount point)
    end
    local done = {}
    local function fail(msg)
        for i = #done, 1, -1 do
            local rel, how = done[i][1], done[i][2]
            local cur = base .. "/" .. rel
            rmTree(cur)
            if how == "copy" then
                if exists(keep .. "/" .. rel) and not Update.copyTree(keep .. "/" .. rel, cur) then
                    Log.err("update: could not put back", rel)
                end
            elseif exists(cur .. ".gz-old") then
                os.rename(cur .. ".gz-old", cur)
            end
        end
        rmTree(stage)
        return nil, msg
    end
    for _i, rel in ipairs(items) do
        local cur = base .. "/" .. rel
        if byCopy(cur) then
            if not isDir(keep) then lfs.mkdir(keep); lfs.mkdir(keep .. "/plugins") end
            if exists(cur) and not Update.copyTree(cur, keep .. "/" .. rel) then
                return fail("could not keep a copy of " .. rel .. " (is the disk full?)")
            end
            done[#done + 1] = { rel, "copy" }
            rmTree(cur)
            if not Update.copyTree(src .. "/" .. rel, cur) then
                return fail("could not install " .. rel .. " (not enough room?)")
            end
        else
            local old = cur .. ".gz-old"
            rmTree(old)
            if exists(cur) and not os.rename(cur, old) then return fail("could not move " .. rel) end
            if not os.rename(src .. "/" .. rel, cur) then
                if exists(old) then os.rename(old, cur) end
                return fail("could not install " .. rel)
            end
            done[#done + 1] = { rel, "rename" }
        end
    end
    for _i, d in ipairs(done) do
        if d[2] == "rename" then rmTree(base .. "/" .. d[1] .. ".gz-old") end
    end
    rmTree(stage)
    -- the Nook's scripts: each a whole new file renamed over the old one
    -- (sh reads a running script as it goes; it keeps the old file)
    for from, to in pairs(nook and NOOK_SCRIPTS or {}) do
        if exists(base .. "/" .. from) then
            local dest = base .. "/../" .. to
            local new = io.open(base .. "/" .. from, "rb")
            local body = new and new:read("*a")
            if new then new:close() end
            local tmp = dest .. ".gz-new"
            local out = body and body:match("^#!") and io.open(tmp, "wb")
            if out and out:write(body) and out:close() and os.rename(tmp, dest) then
                Log.info("update: the Nook's", to, "updated")
            else
                if out then os.remove(tmp) end
                Log.warn("update: the Nook's", to, "not updated (kept as it was)")
            end
        end
    end
    Log.info("update installed", Update.currentVersion(), "items", #done)
    return true
end

--- Full flow from the menu: check, confirm, download (background), install, restart.
function Update.run()
    require("gzreader_net").run(function()
        local busy = InfoMessage:new{ text = _("Checking for GZreader updates…"), timeout = 0 }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local info, err = Update.check()
        UIManager:close(busy)
        if not info then
            UIManager:show(InfoMessage:new{ text = T(_("Couldn't check for updates:\n%1"), tostring(err)) })
            return
        end
        if not Update.isNewer(info) then
            UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 is up to date."), Update.currentVersion()), timeout = 4 })
            return
        end
        local notes = info.notes ~= "" and ("\n\n" .. info.notes:sub(1, 600)) or ""
        UIManager:show(ConfirmBox:new{
            text = T(info.beta and _("Test build %1 is available (installed: %2).%3\n\nYour settings, books and reading progress are kept.")
                    or _("GZreader %1 is available (installed: %2).%3\n\nYour settings, books and reading progress are kept."),
                info.version, Update.currentVersion(), notes),
            ok_text = _("Update"),
            ok_callback = function()
                -- Wi-Fi may have gone idle while the question was open
                require("gzreader_net").run(function() Update.download(info) end, { reason = "update" })
            end,
        })
    end, { reason = "checking for updates" })
end

function Update.download(info)
    local ProgressbarDialog = require("gzreader_progress")
    local Net = require("gzreader_net")
    -- (the download, and what it unpacks to: about three times its size)
    -- (and a copy of the parts it replaces when they're on another disk)
    local work, elsewhere = Update.workDir((info.size or (12 * 1024 * 1024)) * 5)
    local zip = elsewhere and (work .. ".zip") or (DataStorage:getDataDir() .. "/cache/gzreader-update.zip")
    lfs.mkdir(DataStorage:getDataDir() .. "/cache")
    os.remove(zip)
    local pid, fd = ffiutil.runInSubProcess(function(_p, wfd)
        require("gzreader_async").lowerPriority(require("gzreader_async").NICE) -- (page turns first)
        local code, _, err = Update.get(info.url, zip)
        ffiutil.writeToFD(wfd, code == 200 and "ok" or ("err " .. tostring(code or err)), true)
    end, true)
    if not pid then return UIManager:show(InfoMessage:new{ text = _("Couldn't start the download.") }) end
    Net.hold("update")
    -- Can't be closed (unlike book downloads): the update installs and
    -- restarts GZreader as soon as it's downloaded. Modal: keys don't reach
    -- the screens behind it either.
    local dialog = ProgressbarDialog:new{
        title = T(_("Downloading GZreader %1…"), info.version),
        subtitle = _("GZreader restarts when it's installed. Please wait."),
        progress_max = info.size or (12 * 1024 * 1024), refresh_time_seconds = 2, -- source zips: ~9 MB
        dismissable = false,
        modal = true,
    }
    -- swallow every key and tap, so shortcuts can't act behind it either
    local Input = require("device").input
    local GestureRange = require("ui/gesturerange")
    dialog.key_events = { Swallow = { { Input.group.Any } } }
    dialog.ges_events = { Swallow = { GestureRange:new{ ges = "tap", range = dialog.dimen } } }
    dialog.onSwallow = function() return true end
    dialog:show()
    local function poll()
        local size = lfs.attributes(zip, "size") or 0
        dialog:reportProgress(math.min(size, info.size or (12 * 1024 * 1024)))
        if not ffiutil.isSubProcessDone(pid) then return UIManager:scheduleIn(1, poll) end
        UIManager:close(dialog)
        Net.release("update")
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
        local busy = InfoMessage:new{ text = _("Installing… Please wait."), timeout = 0, dismissable = false, modal = true }
        UIManager:show(busy)
        UIManager:forceRePaint()
        local ok, err = Update.apply(zip, { source = info.source, version = info.version, stage = elsewhere and work or nil })
        os.remove(zip)
        UIManager:close(busy)
        if not ok then
            Log.err("update failed:", err)
            return UIManager:show(InfoMessage:new{ text = T(_("Update failed, nothing was changed:\n%1"), tostring(err)) })
        end
        Update.state = { has_update = false, latest = info.version }
        UIManager:show(InfoMessage:new{ text = T(_("GZreader %1 installed. Restarting…"), info.version), timeout = 2 })
        -- (not in the middle of a request to Grimmory: a new login it brings
        -- back would be lost; 20 s at most)
        local waited = 0
        local function restart()
            local Async = package.loaded["gzreader_async"]
            if Async and (Async.busy or #(Async.queue or {}) > 0) and waited < 20 then
                waited = waited + 1
                return UIManager:scheduleIn(1, restart)
            end
            UIManager:restartKOReader()
        end
        UIManager:scheduleIn(2, restart)
    end
    UIManager:scheduleIn(1, poll)
end

--- GZreader's own changelog (gzreader_changelog.lua), newest first.
function Update.showChangelog()
    local ok, log = pcall(require, "gzreader_changelog")
    local parts = {}
    for _i, entry in ipairs(ok and log or {}) do
        parts[#parts + 1] = "GZreader " .. entry.version .. (entry.date and ("  (" .. entry.date .. ")") or "")
        for _j, line in ipairs(entry.changes or {}) do
            parts[#parts + 1] = "  • " .. require("gzreader_whatsnew").text(line)
        end
        parts[#parts + 1] = ""
    end
    parts[#parts + 1] = T(_("Full release notes: %1"), Update.pageUrl())
    local TextViewer = require("ui/widget/textviewer")
    UIManager:show(TextViewer:new{ title = _("GZreader changelog"), text = table.concat(parts, "\n") })
end

--- Test builds on or off: the next check looks at the other source at once.
function Update.setBeta(on)
    G_reader_settings:saveSetting("gzreader_update_beta", on and true or false)
    G_reader_settings:saveSetting("gzreader_update_last_check", 0)
    G_reader_settings:delSetting("gzreader_update_latest")
    Update.state = { has_update = false }
    Log.info("update: test builds", on and "on" or "off")
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
            text = _("Test builds"),
            help_text = _("Get test builds instead of releases: what's waiting to be tried, before it's released. They update over Wi-Fi like releases. Turn it off to go back to releases: the next release is then offered."),
            checked_func = function() return Update.betaEnabled() end,
            callback = function() Update.setBeta(not Update.betaEnabled()) end,
        },
        {
            text = _("Changelog"),
            keep_menu_open = true,
            callback = function() Update.showChangelog() end,
        },
        {
            text_func = function()
                return T(_("Update source: %1"), "github.com/" .. Update.REPO .. (Update.betaEnabled() and " (test builds)" or ""))
            end,
            enabled = false,
        },
    }
end

return Update
