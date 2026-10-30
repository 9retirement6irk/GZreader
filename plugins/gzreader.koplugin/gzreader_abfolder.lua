--[[--
Where audiobooks live, kept small so starting GZreader doesn't load the player.

Audiobooks are stored in <GZreader folder>/.audiobooks/<book id>/ (hidden: a
long book is thousands of 15-second chunk files that file lists, folder
covers and file search would otherwise walk through). The visible
<GZreader folder>/Audiobooks folder stays empty; opening it in the file
manager's list (Downloads tab) shows the downloaded audiobooks instead.
]]

local lfs = require("libs/libkoreader-lfs")
local ffiutil = require("ffi/util")
local Log = require("gzreader_log")

local Folder = {
    STORE = ".audiobooks",
    ENTRY = "Audiobooks",
}

local function mkdirp(path)
    local acc = ""
    for part in path:gmatch("[^/]+") do
        acc = acc .. "/" .. part
        if lfs.attributes(acc, "mode") == nil then lfs.mkdir(acc) end
    end
end

--- Before 1.3.6 audiobooks were stored in the visible Audiobooks folder:
--- move them into the hidden one (same file system: one rename each).
function Folder.migrate(plugin)
    local lib = plugin:libraryDir()
    local old, new = lib .. "/" .. Folder.ENTRY, lib .. "/" .. Folder.STORE
    if lfs.attributes(old, "mode") ~= "directory" then return 0 end
    local moved = 0
    for name in lfs.dir(old) do
        local from = old .. "/" .. name
        if name ~= "." and name ~= ".." and lfs.attributes(from, "mode") == "directory" then
            if moved == 0 then
                mkdirp(new)
                -- a conversion left running by a restart would write to the old place
                pcall(function() require("gzreader_recovery").stopConversions(old) end)
            end
            local to = new .. "/" .. name
            if lfs.attributes(to, "mode") == nil then
                local ok, err = os.rename(from, to)
                if ok then moved = moved + 1 else Log.warn("audiobook move failed", name, tostring(err)) end
            end
        end
    end
    if moved > 0 then Log.info("audiobooks moved to the hidden folder:", moved) end
    return moved
end

--- The visible Audiobooks folder, made when there's something to show.
function Folder.ensureEntry(plugin)
    local dir = plugin:libraryDir() .. "/" .. Folder.ENTRY
    if lfs.attributes(dir, "mode") == nil then lfs.mkdir(dir) end
end

--- Opening the Audiobooks folder in the file manager's list shows the
--- downloaded audiobooks instead of a folder.
function Folder.install(plugin)
    Folder.plugin = plugin
    local FileChooser = require("ui/widget/filechooser")
    if FileChooser._gz_audiobook_entry then return end
    FileChooser._gz_audiobook_entry = true
    local orig = FileChooser.changeToPath
    function FileChooser:changeToPath(path, ...)
        local p = Folder.plugin
        if p and self.name == "filemanager" and Folder.isEntry(p, path) then
            local UIManager = require("ui/uimanager")
            UIManager:nextTick(function() require("gzreader_audiobook").showDownloaded(p) end)
            return
        end
        return orig(self, path, ...)
    end
end

function Folder.isEntry(plugin, path)
    if type(path) ~= "string" then return false end
    local entry = plugin:libraryDir() .. "/" .. Folder.ENTRY
    local real = ffiutil.realpath(path) or path
    return real == (ffiutil.realpath(entry) or entry)
end

--- At start: move old storage, hook the folder, make it if there are audiobooks.
function Folder.start(plugin)
    Folder.migrate(plugin)
    Folder.install(plugin)
    if next(plugin.store.audiobooks or {}) then Folder.ensureEntry(plugin) end
end

return Folder
