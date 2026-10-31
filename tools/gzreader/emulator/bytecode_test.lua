-- frontend/gzbytecode.lua: run from a KOReader tree with its luajit, e.g.
--   cd <tree> && qemu-arm-static -L /usr/arm-linux-gnueabi ./luajit <this file>
require("setupkoenv")
local fails = 0
local function check(ok, msg) if not ok then fails = fails + 1 end print((ok and "ok   " or "FAIL ") .. msg) end
os.execute("rm -rf cache/gz-bytecode cache/gzbc-test && mkdir -p cache/gzbc-test")
local f = io.open("cache/gzbc-test/gzbc_mod.lua", "w")
f:write("local src = debug.getinfo(1, 'S').source\nreturn { v = 1, src = src, boom = function() error('boom') end }\n")
f:close()
package.path = "cache/gzbc-test/?.lua;" .. package.path
local BC = dofile("frontend/gzbytecode.lua")
package.loaded["gzbytecode"] = BC
check(BC.install(), "installed")
local m = require("gzbc_mod")
check(m.v == 1 and BC.misses == 1 and BC.hits == 0, "first load: compiled and cached")
check(m.src == "@cache/gzbc-test/gzbc_mod.lua", "chunk name as without the cache: " .. tostring(m.src))
local err = select(2, pcall(m.boom))
check(tostring(err):match("gzbc_mod%.lua:2: boom"), "errors keep file and line: " .. tostring(err))
package.loaded["gzbc_mod"] = nil
local m2 = require("gzbc_mod")
check(m2.v == 1 and BC.hits == 1, "second load: from the cache")
check(m2.src == "@cache/gzbc-test/gzbc_mod.lua", "cached chunk keeps its name")
-- an edited file (another size) is compiled again
os.execute("sleep 1")
f = io.open("cache/gzbc-test/gzbc_mod.lua", "w")
f:write("return { v = 22 }\n")
f:close()
package.loaded["gzbc_mod"] = nil
check(require("gzbc_mod").v == 22 and BC.misses == 2, "edited file: compiled again")
-- a broken cache file is removed and the source used
local dir = BC.dir
for e in BC.lfs.dir(dir) do
    if e:match("^cache!gzbc%-test!gzbc_mod") then local w = io.open(dir .. "/" .. e, "wb"); w:write("garbage"); w:close() end
end
package.loaded["gzbc_mod"] = nil
check(require("gzbc_mod").v == 22, "broken cache file: the source is loaded")
-- syntax errors are reported like require's
f = io.open("cache/gzbc-test/gzbc_bad.lua", "w"); f:write("return {\n"); f:close()
local okb, errb = pcall(require, "gzbc_bad")
check(not okb and tostring(errb):match("error loading module 'gzbc_bad' from file"), "syntax error reported: " .. tostring(errb):sub(1, 80))
-- a missing module still errors as usual
local okm, errm = pcall(require, "gzbc_no_such_module")
check(not okm and tostring(errm):match("module 'gzbc_no_such_module' not found"), "missing module: the usual error")
os.execute("rm -rf cache/gzbc-test")
print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
