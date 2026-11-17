-- Settings and book sidecars read as data, not run (frontend/gzdataload.lua),
-- and KOReader's loaders going through it.
--   luajit dataload_test.lua <repo> <work dir>
local REPO, WORK = arg[1], arg[2]
package.path = REPO .. "/frontend/?.lua;" .. package.path
os.execute("mkdir -p '" .. WORK .. "'")

local passed, failed = 0, 0
local function check(cond, name)
    if cond then passed = passed + 1 else failed = failed + 1; print("FAIL: " .. name) end
end
local function write(name, text)
    local p = WORK .. "/" .. name
    local f = assert(io.open(p, "wb")); f:write(text); f:close()
    return p
end
local function exists(p) local f = io.open(p) if f then f:close() return true end return false end

local DataLoad = require("gzdataload")
local marker = WORK .. "/ran"
os.remove(marker)

-- what KOReader writes reads the same
local plain = write("plain.lua", '-- we can read Lua syntax here!\nreturn {\n    ["a"] = 1,\n    ["b"] = {\n        [1] = "x\\"y",\n        [2] = true,\n    },\n    ["c"] = -2.5e-3,\n    ["d"] = inf,\n}\n')
local t = DataLoad.file(plain)
check(t.a == 1 and t.b[1] == 'x"y' and t.b[2] == true and t.c == -2.5e-3 and t.d == nil, "settings as KOReader writes them: read the same")
local same = dofile(plain)
check(same.a == t.a and same.c == t.c and same.d == t.d, "…as dofile read them")

-- code in a file: nothing it does happens
local bad = write("bad.lua", 'os.execute("touch ' .. marker .. '")\nreturn { a = 1 }\n')
local ok, err = pcall(DataLoad.file, bad)
check(not ok and not exists(marker), "a file that runs a command: refused, the command never runs (" .. tostring(err) .. ")")
bad = write("bad2.lua", 'local f = io.open("' .. marker .. '", "w") f:write("x") f:close() return {}\n')
ok = pcall(DataLoad.file, bad)
check(not ok and not exists(marker), "a file that writes a file: refused")
bad = write("bad3.lua", 'return { a = require("ffi") }\n')
ok = pcall(DataLoad.file, bad)
check(not ok, "a file that reaches for require/ffi: refused")
bad = write("bad4.lua", 'return { a = ("x"):rep(10), b = ("").format }\n')
ok = pcall(DataLoad.file, bad)
check(not ok, "a file that reaches the string library through a string: refused")
check(("ab"):upper() == "AB" and ("x"):rep(3) == "xxx", "…and strings have their methods again afterwards")
bad = write("loop.lua", 'while true do end\n')
local t0 = os.clock()
ok, err = pcall(DataLoad.file, bad)
check(not ok and tostring(err):find("too long", 1, true) and os.clock() - t0 < 30, "a file that loops: stopped (" .. tostring(err) .. ")")
check(debug.gethook() == nil, "…and no hook is left behind")
local bc = write("bytecode.lua", string.dump(function() return { a = 1 } end))
ok, err = pcall(DataLoad.file, bc)
check(not ok and tostring(err):find("not a text file", 1, true), "a precompiled chunk: refused")
ok = pcall(DataLoad.file, WORK .. "/missing.lua")
check(not ok, "a missing file: an error, as dofile")

-- a big settings file (near the most LuaJIT reads in one: 65 536 values)
local parts = { "return {\n" }
for i = 1, 20000 do parts[#parts + 1] = string.format('    [%d] = { ["file"] = "/mnt/us/documents/book %d.epub", ["time"] = %d },\n', i, i, 1700000000 + i) end
parts[#parts + 1] = "}\n"
local big = write("big.lua", table.concat(parts))
local okb, bt = pcall(DataLoad.file, big)
check(okb and #bt == 20000 and bt[20000].time == 1700020000, "a big settings file (20 000 entries, as dofile can read): read whole")

-- KOReader's loaders use it
local lfs_stub = { attributes = function(p, what)
    local f = io.open(p, "rb")
    if not f then return nil end
    local size = f:seek("end"); f:close()
    if what == "mode" then return "file" elseif what == "size" then return size end
    return { mode = "file", size = size }
end }
package.loaded["libs/libkoreader-lfs"] = lfs_stub
package.loaded["logger"] = { warn = function() end, dbg = function() end, info = function() end, err = function() end }
package.loaded["util"] = {}
package.loaded["ffi/util"] = { orderedPairs = pairs }
local LuaSettings = require("luasettings")
local s = LuaSettings:open(plain)
check(s.data.a == 1 and s.data.b[1] == 'x"y', "LuaSettings: a settings file read as before")
local evil = write("evil_settings.lua", 'os.execute("touch ' .. marker .. '") return { a = 2 }\n')
write("evil_settings.lua.old", 'return { a = 3 }\n')
s = LuaSettings:open(evil)
check(not exists(marker) and s.data.a == 3, "LuaSettings: a settings file with code in it isn't run (its backup is read instead)")

local src = io.open(REPO .. "/frontend/docsettings.lua"):read("*a")
check(not src:find("pcall(dofile", 1, true) and select(2, src:gsub('require%("gzdataload"%)%.file', "")) == 2,
    "DocSettings: book sidecars (metadata.*.lua next to the book) go through it")
for _i, f in ipairs({ "frontend/luasettings.lua", "frontend/luadefaults.lua", "frontend/readhistory.lua",
        "plugins/statistics.koplugin/main.lua", "plugins/zenos.koplugin/common/paths.lua",
        "plugins/zenos.koplugin/common/brand_migration.lua",
        "plugins/zenos.koplugin/modules/filebrowser/patches/home/home_quotes.lua",
        "plugins/zenos.koplugin/modules/filebrowser/metadata/epub.lua",
        "plugins/zenos.koplugin/modules/filebrowser/metadata/service.lua" }) do
    local text = io.open(REPO .. "/" .. f):read("*a")
    check(text:find('require("gzdataload").file', 1, true) and not text:find("pcall(dofile, new.file", 1, true)
        and not text:find("pcall(dofile, history_file", 1, true) and not text:find("pcall(dofile, statistic_file", 1, true)
        and not text:find("loadfile(sidecar)", 1, true) and not text:find("loadfile(stage)", 1, true),
        f .. ": reads its data through it")
end

-- a translation's plural rule (built from its header) gets nothing but n
local gt = io.open(REPO .. "/frontend/gettext.lua"):read("*a")
check(gt:find("local plural_chunk = loadstring(plural_func_str)\n    setfenv(plural_chunk, {})", 1, true)
    and not gt:find("return loadstring(plural_func_str)()", 1, true), "gettext: a translation's plural rule runs with nothing in reach")
local rule = loadstring("return function(n) if (n%10==1 and n%100~=11) then return 0 elseif n ~= 0 then return 1 end return 2 end")
setfenv(rule, {})
local plural = rule()
check(plural(1) == 0 and plural(21) == 0 and plural(11) == 1 and plural(0) == 2, "…and a real one (n%10, n%100) still works there")
local crafted = loadstring('return function(n) if os.execute("touch ' .. marker .. '") then return 1 else return 0 end end')
setfenv(crafted, {})
check(not pcall(crafted(), 1) and not exists(marker), "…a crafted one can't run a command")

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
