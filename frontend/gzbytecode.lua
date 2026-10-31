--[[--
GZreader: load Lua modules from compiled bytecode, kept in a cache.

A KOReader installed from source (GitHub's source archive, which the updater
falls back to when a release has no package, or a development copy) parses
and compiles hundreds of files at every start and for every screen opened
the first time; on a Kindle 3 that is seconds. (Release packages are
precompiled, package-kindle-legacy.sh: then this does nothing.) LuaJIT loads its own bytecode about four
times faster. The first time a module is loaded it is compiled as usual and
its bytecode written to cache/gz-bytecode/<LuaJIT, GZreader version>/; after
that the bytecode is loaded. Line numbers stay (crash reports are the same).

- A cache entry is named after the file's path, size and modification time,
  so an edited file is compiled again.
- An update (another GZreader version or LuaJIT) gets a new cache folder;
  the old ones are removed.
- Anything wrong with a cached file (unreadable, from another LuaJIT): it's
  removed and the source is loaded, as without the cache.
- Off with a file named `gz-no-bytecode` in the koreader folder (over USB),
  or KO_NO_BYTECODE_CACHE=1.
]]

local M = { hits = 0, misses = 0 }

local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function rmTree(lfs, dir)
    for e in lfs.dir(dir) do
        if e ~= "." and e ~= ".." then
            local p = dir .. "/" .. e
            if lfs.attributes(p, "mode") == "directory" then rmTree(lfs, p) else os.remove(p) end
        end
    end
    lfs.rmdir(dir)
end

--- The folder for this LuaJIT and this GZreader version (made if needed).
local function cacheDir(lfs, root)
    local version = (readFile("gzreader-version") or readFile("git-rev") or "dev"):gsub("%s+", "")
    local tag = ((jit and jit.version or "lua") .. "-" .. (jit and jit.arch or "") .. "-" .. version):gsub("[^%w%.%-_]", "_")
    local dir = root .. "/" .. tag
    if lfs.attributes(dir, "mode") == "directory" then return dir end
    if lfs.attributes(root, "mode") ~= "directory" and not lfs.mkdir(root) then return nil end
    -- a new version: the old caches go
    for e in lfs.dir(root) do
        if e ~= "." and e ~= ".." and lfs.attributes(root .. "/" .. e, "mode") == "directory" then
            pcall(rmTree, lfs, root .. "/" .. e)
        end
    end
    if not lfs.mkdir(dir) then return nil end
    return dir
end

--- Load `path` (a .lua file) through the cache. Returns the chunk, or nil, err.
function M.load(path)
    local attr = M.lfs.attributes(path)
    if not attr or attr.mode ~= "file" then return loadfile(path) end
    local key = path:gsub("^%./", ""):gsub("/", "!") .. "~" .. attr.size .. "-" .. attr.modification .. ".bc"
    local cached = M.dir .. "/" .. key
    local f = io.open(cached, "rb")
    if f then
        local code = f:read("*a")
        f:close()
        local fn = code and code:sub(1, 3) == "\27LJ" and loadstring(code) -- (LuaJIT bytecode only)
        if fn then
            M.hits = M.hits + 1
            return fn
        end
        os.remove(cached) -- broken or from another LuaJIT
    end
    local fn, err = loadfile(path)
    if not fn then return nil, err end
    M.misses = M.misses + 1
    local ok, code = pcall(string.dump, fn, false) -- false: keep line numbers
    if ok and code then
        local tmp = cached .. ".tmp"
        local w = io.open(tmp, "wb")
        if w then
            local wrote = w:write(code)
            w:close()
            if wrote then os.rename(tmp, cached) else os.remove(tmp) end
        end
    end
    return fn
end

function M.install()
    if M.installed then return true end
    if os.getenv("KO_NO_BYTECODE_CACHE") == "1" or not (jit and string.dump and package.searchpath) then return false end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then return false end
    if lfs.attributes("gz-no-bytecode", "mode") then return false end
    -- release packages are precompiled already (package-kindle-legacy.sh):
    -- the cache is for installs from source (an update from GitHub's source
    -- archive, a development copy)
    local probe = io.open("frontend/ui/uimanager.lua", "rb")
    local head = probe and probe:read(3)
    if probe then probe:close() end
    if head == "\27LJ" then return false end
    if lfs.attributes("cache", "mode") ~= "directory" and not lfs.mkdir("cache") then return false end
    local dir = cacheDir(lfs, "cache/gz-bytecode")
    if not dir then return false end
    M.lfs, M.dir = lfs, dir
    -- replace the standard Lua file searcher (the first C searcher after
    -- package.preload's; searchers added in Lua before it stay in front)
    local loaders = package.loaders
    local at
    for i = 2, #loaders do
        local info = debug.getinfo(loaders[i], "S")
        if info and info.what == "C" then at = i; break end
    end
    if not at then return false end
    loaders[at] = function(name)
        local path, err = package.searchpath(name, package.path)
        if not path then return err end
        local fn, lerr = M.load(path)
        if not fn then
            error(string.format("error loading module '%s' from file '%s':\n\t%s", name, path, tostring(lerr)), 0)
        end
        return fn
    end
    M.installed = true
    return true
end

return M
