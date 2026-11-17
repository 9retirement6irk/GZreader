--[[--
GZreader: settings files read as data, not run as programs.

KOReader keeps its settings, each book's sidecar (book.sdr/metadata.*.lua)
and a few other files as Lua source that returns a table, and read them with
dofile(): whatever else such a file holds runs too, with everything the
reader can do (on the Nook, as root). A sidecar sits next to its book, and on
a Nook the books are on storage every Android app can write. So these files
are read here instead:

  * text only (a precompiled chunk is refused: LuaJIT doesn't check bytecode);
  * run with nothing in reach: an empty environment (no os, io, require…) and
    strings without their methods while it runs, so only the table it
    returns comes out of it;
  * a time limit (MAX_STEPS instructions), so a file that loops is stopped.

What KOReader writes (frontend/dump.lua: tables, strings, numbers, booleans)
reads exactly as before; `inf`/`nan` were names with no value under dofile
too. DataLoad.file(path) is a drop-in for dofile(path): it returns the value
or raises an error, so pcall(DataLoad.file, path) replaces pcall(dofile, path).
]]

local DataLoad = {
    MAX_STEPS = 50000000, -- (a big settings file is a few million)
}

local string_mt = getmetatable("")

function DataLoad.file(path)
    local f, oerr = io.open(path, "rb")
    if not f then error("cannot open " .. tostring(path) .. ": " .. tostring(oerr), 0) end
    local src = f:read("*a")
    f:close()
    if src:sub(1, 1) == "\27" then error(tostring(path) .. ": not a text file", 0) end
    local chunk, err = loadstring(src, "@" .. tostring(path))
    if not chunk then error(err, 0) end
    setfenv(chunk, {})
    if jit and jit.off then jit.off(chunk, true) end -- (count hooks don't fire in compiled code)
    local saved_index = string_mt and string_mt.__index
    if string_mt then string_mt.__index = {} end
    debug.sethook(function() error(tostring(path) .. ": too long to read (not plain settings)", 0) end, "", DataLoad.MAX_STEPS)
    local ok, res = pcall(chunk)
    debug.sethook()
    if string_mt then string_mt.__index = saved_index end
    if not ok then error(res, 0) end
    return res
end

return DataLoad
